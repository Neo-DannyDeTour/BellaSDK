#!/usr/bin/env python3
"""Headless Blender 5.3.0 Mantaflow + Particle Radial Gibbing Burst / Viscera Splatter simulation.

Builds and bakes a deterministic (seed=42) 64-frame simulation:
- 2.5m Mantaflow FLIP Liquid Domain (resolution_max=128, spray particles, viscosity=0.05)
- 0.22m Icosphere Liquid Inflow (frames 1-4) with radial initial velocity + Turbulence field
- Secondary 2.5m Mantaflow Gas/Smoke Domain for expanding aerosol mist dissipating by frame 64
- 2500-particle tapered teardrop streak system aligned to velocity (frames 1-3, lifetime 64)
- Cycles 256x256 orthographic (+Y) render with motion blur (shutter=0.65) and OpenImageDenoise
- Dual output per frame to `build/frames/`:
  - `rgba_####.png` (pure white wet specular/subsurface lit grayscale + alpha)
  - `norm_####.png` (camera-space normal AOV mapped [0..1] with matching alpha)

Usage:
    /snap/bin/blender -b -P tools/blender/build_splatter_sim.py
"""

from __future__ import annotations

import math
import os
import shutil
import tempfile
from pathlib import Path

import bmesh  # type: ignore
import bpy  # type: ignore


def log(msg: str) -> None:
    """Print flush-enabled progress message."""
    print(f"[SplatterSim] {msg}", flush=True)


def configure_cycles_device(scene: bpy.types.Scene) -> None:
    """Select GPU (OPTIX/CUDA) if available in headless environment, else CPU."""
    prefs = bpy.context.preferences.addons.get("cycles")
    if prefs is not None:
        cprefs = prefs.preferences
        for compute_type in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
            try:
                cprefs.compute_device_type = compute_type
                cprefs.get_devices()
                has_gpu = any(d.type == compute_type for d in cprefs.devices)
                if has_gpu:
                    for dev in cprefs.devices:
                        dev.use = dev.type == compute_type
                    scene.cycles.device = "GPU"
                    log(f"Cycles device: GPU ({compute_type})")
                    return
            except Exception:
                continue
    scene.cycles.device = "CPU"
    log("Cycles device: CPU")


def create_wet_white_material(scene: bpy.types.Scene) -> bpy.types.Material:
    """Create pure white (#FFFFFF) wet specular/subsurface material with CamNormal AOV."""
    mat = bpy.data.materials.new(name="Splatter_WetWhite_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_out.location = (500, 0)

    node_bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    node_bsdf.location = (180, 0)
    node_bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    node_bsdf.inputs["Roughness"].default_value = 0.05
    node_bsdf.inputs["IOR"].default_value = 1.38
    if "Specular IOR Level" in node_bsdf.inputs:
        node_bsdf.inputs["Specular IOR Level"].default_value = 1.0
    if "Subsurface Weight" in node_bsdf.inputs:
        node_bsdf.inputs["Subsurface Weight"].default_value = 0.2
    if "Subsurface Radius" in node_bsdf.inputs:
        node_bsdf.inputs["Subsurface Radius"].default_value = (1.0, 1.0, 1.0)
    if "Subsurface Scale" in node_bsdf.inputs:
        node_bsdf.inputs["Subsurface Scale"].default_value = 0.015

    # Fade remaining droplets/filaments to zero alpha by frame 64
    scene.frame_set(48)
    node_bsdf.inputs["Alpha"].default_value = 1.0
    node_bsdf.inputs["Alpha"].keyframe_insert(data_path="default_value", frame=48)
    scene.frame_set(63)
    node_bsdf.inputs["Alpha"].default_value = 0.0
    node_bsdf.inputs["Alpha"].keyframe_insert(data_path="default_value", frame=63)
    scene.frame_set(1)

    links.new(node_bsdf.outputs["BSDF"], node_out.inputs["Surface"])

    # Camera-space normal AOV mapped [-1..1] -> [0..1] (facing camera = (0.5, 0.5, 1.0))
    node_geom = nodes.new(type="ShaderNodeNewGeometry")
    node_geom.location = (-450, -280)

    node_vtrans = nodes.new(type="ShaderNodeVectorTransform")
    node_vtrans.location = (-230, -280)
    node_vtrans.vector_type = "NORMAL"
    node_vtrans.convert_from = "WORLD"
    node_vtrans.convert_to = "CAMERA"

    node_scale = nodes.new(type="ShaderNodeVectorMath")
    node_scale.location = (-20, -280)
    node_scale.operation = "SCALE"
    node_scale.inputs["Scale"].default_value = 0.5

    node_bias = nodes.new(type="ShaderNodeVectorMath")
    node_bias.location = (180, -280)
    node_bias.operation = "ADD"
    node_bias.inputs[1].default_value = (0.5, 0.5, 0.5)

    node_aov = nodes.new(type="ShaderNodeOutputAOV")
    node_aov.location = (420, -280)
    node_aov.aov_name = "CamNormal"

    links.new(node_geom.outputs["Normal"], node_vtrans.inputs["Vector"])
    links.new(node_vtrans.outputs["Vector"], node_scale.inputs[0])
    links.new(node_scale.outputs["Vector"], node_bias.inputs[0])
    links.new(node_bias.outputs["Vector"], node_aov.inputs["Color"])

    return mat


def create_aerosol_mist_material(scene: bpy.types.Scene) -> bpy.types.Material:
    """Create pure white (#FFFFFF) volumetric aerosol mist material fading out by frame 64."""
    mat = bpy.data.materials.new(name="AerosolMist_Vol_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_out.location = (520, 0)

    node_vol = nodes.new(type="ShaderNodeVolumePrincipled")
    node_vol.location = (220, 0)
    node_vol.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    node_vol.inputs["Anisotropy"].default_value = 0.2
    node_vol.inputs["Emission Color"].default_value = (1.0, 1.0, 1.0, 1.0)

    node_attr = nodes.new(type="ShaderNodeAttribute")
    node_attr.location = (-360, 0)
    node_attr.attribute_name = "density"

    node_dens_mul = nodes.new(type="ShaderNodeMath")
    node_dens_mul.location = (-80, 60)
    node_dens_mul.operation = "MULTIPLY"
    node_dens_mul.inputs[1].default_value = 2.4

    node_emit_mul = nodes.new(type="ShaderNodeMath")
    node_emit_mul.location = (-80, -100)
    node_emit_mul.operation = "MULTIPLY"
    node_emit_mul.inputs[1].default_value = 0.45

    links.new(node_attr.outputs["Fac"], node_dens_mul.inputs[0])
    links.new(node_attr.outputs["Fac"], node_emit_mul.inputs[0])
    links.new(node_dens_mul.outputs["Value"], node_vol.inputs["Density"])
    links.new(node_emit_mul.outputs["Value"], node_vol.inputs["Emission Strength"])
    links.new(node_vol.outputs["Volume"], node_out.inputs["Volume"])

    # Smoothly fade residual density/emission to 0 by frame 64
    scene.frame_set(40)
    node_dens_mul.inputs[1].default_value = 2.4
    node_emit_mul.inputs[1].default_value = 0.45
    node_dens_mul.inputs[1].keyframe_insert(data_path="default_value", frame=40)
    node_emit_mul.inputs[1].keyframe_insert(data_path="default_value", frame=40)

    scene.frame_set(62)
    node_dens_mul.inputs[1].default_value = 0.0
    node_emit_mul.inputs[1].default_value = 0.0
    node_dens_mul.inputs[1].keyframe_insert(data_path="default_value", frame=62)
    node_emit_mul.inputs[1].keyframe_insert(data_path="default_value", frame=62)
    scene.frame_set(1)

    return mat


def create_teardrop_mesh(
    scene: bpy.types.Scene,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    """Create tapered teardrop mesh oriented along +Y for velocity-aligned particle streaks."""
    hidden_col = bpy.data.collections.new("ParticleTemplates")
    scene.collection.children.link(hidden_col)

    mesh = bpy.data.meshes.new("Teardrop_Mesh")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.5)

    # Taper tail (-Y) and elongate along +Y so rotation_mode='VEL' aligns streaks radially
    for v in bm.verts:
        y = v.co.y
        if y < 0.0:
            taper = max(0.05, 1.0 + y * 1.85)
            v.co.x *= taper * 0.45
            v.co.z *= taper * 0.45
            v.co.y *= 2.8
        else:
            v.co.x *= 0.45
            v.co.z *= 0.45
            v.co.y *= 1.1

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = True

    teardrop = bpy.data.objects.new("Teardrop_Template", mesh)
    teardrop.location = (50.0, 50.0, 50.0)
    teardrop.data.materials.append(mat)
    hidden_col.objects.link(teardrop)
    hidden_col.hide_viewport = True
    hidden_col.hide_render = True
    return teardrop


def setup_liquid_sim(
    scene: bpy.types.Scene,
    cache_dir: str,
    wet_mat: bpy.types.Material,
    teardrop_obj: bpy.types.Object,
) -> bpy.types.Object:
    """Create 2.5m FLIP liquid domain, 0.22m icosphere inflow (frames 1-4), and turbulence field."""
    scene.use_gravity = True
    scene.gravity = (0.0, 0.0, -2.5)

    # Turbulence force field
    bpy.ops.object.effector_add(type="TURBULENCE", location=(0.0, 0.0, 0.0))
    turb = bpy.context.active_object
    turb.name = "Splatter_Turbulence"
    turb.field.strength = 18.0
    turb.field.size = 0.4
    turb.field.flow = 2.0
    turb.field.seed = 42

    scene.frame_set(15)
    turb.field.strength = 18.0
    turb.field.keyframe_insert(data_path="strength", frame=15)
    scene.frame_set(35)
    turb.field.strength = 0.0
    turb.field.keyframe_insert(data_path="strength", frame=35)
    scene.frame_set(1)

    # 0.22m Icosphere Flow (INFLOW, frames 1-4 only) at origin
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=3,
        radius=0.11,
        location=(0.0, 0.0, 0.0),
    )
    inflow = bpy.context.active_object
    inflow.name = "Splatter_Liquid_Inflow"
    inflow.hide_render = True

    flow_mod = inflow.modifiers.new(name="Fluid", type="FLUID")
    flow_mod.fluid_type = "FLOW"
    fs = flow_mod.flow_settings
    fs.flow_type = "LIQUID"
    fs.flow_behavior = "INFLOW"
    fs.use_initial_velocity = True
    fs.velocity_normal = 14.0
    fs.velocity_random = 4.5
    fs.subframes = 1

    scene.frame_set(1)
    fs.use_inflow = True
    fs.keyframe_insert(data_path="use_inflow", frame=1)
    scene.frame_set(4)
    fs.use_inflow = True
    fs.keyframe_insert(data_path="use_inflow", frame=4)
    scene.frame_set(5)
    fs.use_inflow = False
    fs.keyframe_insert(data_path="use_inflow", frame=5)
    scene.frame_set(1)

    # 2.5m Cube Domain (MANTA, DOMAIN, LIQUID)
    bpy.ops.mesh.primitive_cube_add(size=2.5, location=(0.0, 0.0, 0.0))
    domain = bpy.context.active_object
    domain.name = "Splatter_Liquid_Domain"

    d_mod = domain.modifiers.new(name="Fluid", type="FLUID")
    d_mod.fluid_type = "DOMAIN"
    ds = d_mod.domain_settings
    ds.domain_type = "LIQUID"
    ds.resolution_max = 128
    ds.mesh_scale = 1
    ds.timesteps_min = 1
    ds.timesteps_max = 1
    if hasattr(ds, "particle_number"):
        ds.particle_number = 1
    ds.use_mesh = True
    ds.use_spray_particles = True
    ds.particle_randomness = 0.35
    ds.use_viscosity = True
    ds.viscosity_value = 0.05

    # Open domain borders so fluid exits cleanly and dissipates by frame 64
    for border_attr in (
        "use_collision_border_front",
        "use_collision_border_back",
        "use_collision_border_left",
        "use_collision_border_right",
        "use_collision_border_top",
        "use_collision_border_bottom",
    ):
        if hasattr(ds, border_attr):
            setattr(ds, border_attr, False)

    ds.cache_type = "ALL"
    ds.cache_frame_start = 1
    ds.cache_frame_end = 64
    ds.cache_directory = cache_dir

    domain.data.materials.append(wet_mat)

    for mod in domain.modifiers:
        if mod.type == "PARTICLE_SYSTEM":
            ps = mod.particle_system.settings
            if "Liquid" in mod.name or ps.type == "FLIP":
                mod.show_render = False
                mod.show_viewport = False
            else:
                mod.show_render = True
                ps.render_type = "OBJECT"
                ps.instance_object = teardrop_obj
                ps.particle_size = 0.03
                ps.size_random = 0.5

    return domain


def setup_gas_sim(
    scene: bpy.types.Scene,
    cache_dir: str,
    mist_mat: bpy.types.Material,
) -> bpy.types.Object:
    """Create secondary Mantaflow Gas/Smoke domain for expanding aerosol mist core."""
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=2,
        radius=0.14,
        location=(0.0, 0.0, 0.0),
    )
    smoke_inflow = bpy.context.active_object
    smoke_inflow.name = "Aerosol_Smoke_Inflow"
    smoke_inflow.hide_render = True

    flow_mod = smoke_inflow.modifiers.new(name="Fluid", type="FLUID")
    flow_mod.fluid_type = "FLOW"
    fs = flow_mod.flow_settings
    fs.flow_type = "SMOKE"
    fs.flow_behavior = "INFLOW"
    fs.use_initial_velocity = True
    fs.velocity_normal = 8.0
    fs.velocity_random = 2.5

    scene.frame_set(1)
    fs.use_inflow = True
    fs.keyframe_insert(data_path="use_inflow", frame=1)
    scene.frame_set(4)
    fs.use_inflow = True
    fs.keyframe_insert(data_path="use_inflow", frame=4)
    scene.frame_set(5)
    fs.use_inflow = False
    fs.keyframe_insert(data_path="use_inflow", frame=5)
    scene.frame_set(1)

    bpy.ops.mesh.primitive_cube_add(size=2.5, location=(0.0, 0.0, 0.0))
    gas_domain = bpy.context.active_object
    gas_domain.name = "Aerosol_Gas_Domain"

    d_mod = gas_domain.modifiers.new(name="Fluid", type="FLUID")
    d_mod.fluid_type = "DOMAIN"
    ds = d_mod.domain_settings
    ds.domain_type = "GAS"
    ds.resolution_max = 64
    ds.use_dissolve_smoke = True
    ds.dissolve_speed = 12
    ds.use_dissolve_smoke_log = True
    ds.use_adaptive_domain = True
    ds.cache_type = "ALL"
    ds.cache_frame_start = 1
    ds.cache_frame_end = 64
    ds.cache_directory = cache_dir

    gas_domain.data.materials.append(mist_mat)
    return gas_domain


def setup_streak_particles(
    scene: bpy.types.Scene,
    teardrop_obj: bpy.types.Object,
) -> bpy.types.Object:
    """Create 2500-particle radial teardrop streak system (frames 1-3, lifetime 64, seed 42)."""
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=2,
        radius=0.11,
        location=(0.0, 0.0, 0.0),
    )
    emitter = bpy.context.active_object
    emitter.name = "Splatter_Streak_Emitter"
    emitter.show_instancer_for_render = False
    emitter.show_instancer_for_viewport = False

    mod = emitter.modifiers.new(name="RadialStreaks", type="PARTICLE_SYSTEM")
    psys = mod.particle_system
    psys.seed = 42
    ps = psys.settings
    ps.count = 2500
    ps.frame_start = 1.0
    ps.frame_end = 3.0
    ps.lifetime = 64.0
    ps.emit_from = "FACE"
    ps.normal_factor = 16.0
    ps.factor_random = 6.0
    ps.drag_factor = 0.12
    ps.effector_weights.gravity = 0.25
    ps.use_rotations = True
    ps.rotation_mode = "VEL"
    ps.use_dynamic_rotation = True
    ps.render_type = "OBJECT"
    ps.instance_object = teardrop_obj
    ps.particle_size = 0.04
    ps.size_random = 0.55

    # Fade particle size to 0 by frame 64 so no lingering particles remain on frame 64
    scene.frame_set(45)
    ps.particle_size = 0.04
    ps.keyframe_insert(data_path="particle_size", frame=45)
    scene.frame_set(63)
    ps.particle_size = 0.0
    ps.keyframe_insert(data_path="particle_size", frame=63)
    scene.frame_set(1)

    return emitter


def setup_cycles_and_compositor(scene: bpy.types.Scene, frames_dir: str) -> None:
    """Configure Cycles, orthographic +Y camera, studio lighting, and dual RGBA/Normal output."""
    scene.render.engine = "CYCLES"
    configure_cycles_device(scene)
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.cycles.denoiser = "OPENIMAGEDENOISE"
    scene.cycles.seed = 42
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 1
    scene.cycles.glossy_bounces = 2
    scene.cycles.transmission_bounces = 2
    scene.cycles.volume_bounces = 0
    scene.cycles.transparent_max_bounces = 4

    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.use_motion_blur = True
    if hasattr(scene.render, "motion_blur_shutter"):
        scene.render.motion_blur_shutter = 0.65
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.filepath = os.path.join(frames_dir, "rgba_")

    # Orthographic camera at (0, -3.5, 0) looking +Y, ortho_scale = 3.2
    cam_data = bpy.data.cameras.new(name="Splatter_Ortho_Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 3.2
    cam_data.clip_start = 0.1
    cam_data.clip_end = 25.0
    cam_obj = bpy.data.objects.new(name="Splatter_Ortho_Cam", object_data=cam_data)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (0.0, -3.5, 0.0)
    cam_obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.camera = cam_obj

    # Neutral studio lighting for crisp wet specular/subsurface grayscale density
    key_data = bpy.data.lights.new(name="Studio_Key_Sun", type="SUN")
    key_data.energy = 2.8
    key_data.color = (1.0, 1.0, 1.0)
    key_obj = bpy.data.objects.new(name="Studio_Key_Sun", object_data=key_data)
    scene.collection.objects.link(key_obj)
    key_obj.rotation_euler = (math.radians(55.0), math.radians(-20.0), math.radians(30.0))

    rim_data = bpy.data.lights.new(name="Studio_Rim_Area", type="AREA")
    rim_data.energy = 85.0
    rim_data.size = 4.0
    rim_data.color = (1.0, 1.0, 1.0)
    rim_obj = bpy.data.objects.new(name="Studio_Rim_Area", object_data=rim_data)
    scene.collection.objects.link(rim_obj)
    rim_obj.location = (2.5, 2.5, 2.0)
    rim_obj.rotation_euler = (math.radians(-65.0), 0.0, math.radians(135.0))

    fill_data = bpy.data.lights.new(name="Studio_Front_Point", type="POINT")
    fill_data.energy = 45.0
    fill_data.color = (1.0, 1.0, 1.0)
    fill_obj = bpy.data.objects.new(name="Studio_Front_Point", object_data=fill_data)
    scene.collection.objects.link(fill_obj)
    fill_obj.location = (-1.2, -3.0, 0.8)

    # Register CamNormal AOV and compositor dual-pass output
    view_layer = scene.view_layers[0]
    aov = view_layer.aovs.add()
    aov.name = "CamNormal"
    aov.type = "COLOR"

    ng = bpy.data.node_groups.new(name="Splatter_Compositor", type="CompositorNodeTree")
    scene.compositing_node_group = ng
    nodes = ng.nodes
    links = ng.links

    rl = nodes.new(type="CompositorNodeRLayers")
    rl.location = (-300, 0)

    set_alpha = nodes.new(type="CompositorNodeSetAlpha")
    set_alpha.location = (0, -120)
    set_alpha.inputs["Type"].default_value = "Replace Alpha"

    fo = nodes.new(type="CompositorNodeOutputFile")
    fo.location = (280, -120)
    fo.directory = frames_dir
    fo.file_name = ""
    fo.format.media_type = "IMAGE"
    fo.format.file_format = "PNG"
    fo.format.color_mode = "RGBA"
    fo.format.color_depth = "8"

    item = fo.file_output_items.new("RGBA", "norm_")
    item.override_node_format = True
    item.save_as_render = False
    item.format.media_type = "IMAGE"
    item.format.file_format = "PNG"
    item.format.color_mode = "RGBA"
    item.format.color_depth = "8"

    links.new(rl.outputs["CamNormal"], set_alpha.inputs["Image"])
    links.new(rl.outputs["Alpha"], set_alpha.inputs["Alpha"])
    links.new(set_alpha.outputs["Image"], fo.inputs["norm_"])


def bake_domain(domain: bpy.types.Object) -> None:
    """Select and bake a single Mantaflow domain deterministically."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = domain
    domain.select_set(True)
    bpy.ops.fluid.bake_all()


def run_splatter_sim() -> None:
    """Build, bake, and render the 64-frame radial splatter simulation."""
    repo_root = Path(__file__).resolve().parent.parent.parent
    frames_dir = str(repo_root / "build" / "frames")
    os.makedirs(frames_dir, exist_ok=True)

    cache_root = tempfile.mkdtemp(prefix="splatter_manta_cache_")
    liquid_cache = os.path.join(cache_root, "liquid")
    gas_cache = os.path.join(cache_root, "gas")
    os.makedirs(liquid_cache, exist_ok=True)
    os.makedirs(gas_cache, exist_ok=True)

    try:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.frame_start = 1
        scene.frame_end = 64
        scene.render.fps = 60

        log("Creating materials and teardrop particle template...")
        wet_mat = create_wet_white_material(scene)
        mist_mat = create_aerosol_mist_material(scene)
        teardrop_obj = create_teardrop_mesh(scene, wet_mat)

        log("Setting up Mantaflow liquid domain, gas mist domain, and streak particles...")
        liquid_domain = setup_liquid_sim(scene, liquid_cache, wet_mat, teardrop_obj)
        gas_domain = setup_gas_sim(scene, gas_cache, mist_mat)
        streak_emitter = setup_streak_particles(scene, teardrop_obj)
        setup_cycles_and_compositor(scene, frames_dir)

        # Guarantee zero alpha at frame 64 after smooth 48..63 dissipation
        for obj in (liquid_domain, gas_domain, streak_emitter):
            scene.frame_set(63)
            obj.hide_render = False
            obj.keyframe_insert(data_path="hide_render", frame=63)
            scene.frame_set(64)
            obj.hide_render = True
            obj.keyframe_insert(data_path="hide_render", frame=64)
        scene.frame_set(1)

        blend_path = os.path.join(cache_root, "splatter_sim.blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)

        log("Baking Mantaflow FLIP liquid domain (1..64)...")
        bake_domain(liquid_domain)

        log("Baking Mantaflow Gas/Smoke aerosol domain (1..64)...")
        bake_domain(gas_domain)

        # Warm up particle caches sequentially across frames 1..64
        for f_idx in range(1, 65):
            scene.frame_set(f_idx)
        scene.frame_set(1)

        log(f"Rendering 64 frames (rgba_####.png & norm_####.png) to {frames_dir}...")
        bpy.ops.render.render(animation=True)
        log("Render complete.")
    finally:
        shutil.rmtree(cache_root, ignore_errors=True)


if __name__ == "__main__":
    run_splatter_sim()
