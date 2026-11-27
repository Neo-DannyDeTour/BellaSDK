#!/usr/bin/env python3
"""Headless Blender Mantaflow dual-emitter mushroom-cloud explosion flipbook pipeline.

Executes within Ubuntu headless Blender (`blender --background --python tools/generate_explosion_flipbook.py`):
1. Builds dual-mesh split emitter (`Upper_Cap` domed top + `Lower_Ring` base skirt) from a 12m
   diameter cylinder with soft domed top, outward/upward face normals, and applied scale (`Ctrl+A`).
2. Configures zero-gravity (`effector_weights.gravity = 0.0`) particle systems:
   - `Upper_Cap`: 20,000 particles, burst frames 1-7, lifetime 12 (randomness 1.0),
     normal velocity 85 m/s, velocity randomize 10.0.
   - `Lower_Ring`: 10,000 particles, delayed burst frames 22-36, lifetime 20,
     normal velocity 55 m/s, velocity randomize 2.0.
3. Configures Mantaflow Gas Domain:
   - Resolution 192 (or CLI override), Adaptive Domain = True, Buoyancy Density = 1.0,
     Heat = 0.05, Vorticity = 0.2, Upres Noise (Factor = 2, Strength = 1.0, Scale = 10.0,
     Time = 0.1), Cache = Modular + OpenVDB.
   - `Upper_Cap` Flow: Fire + Smoke (`BOTH`), Particle System source, Initial Velocity = 1.0,
     Sampling Substeps = 2.
   - `Lower_Ring` Flow: Smoke (`SMOKE`), Particle System source, Initial Velocity = 1.0,
     Sampling Substeps = 2.
4. Builds Principled Volume shader network:
   - `Volume Info (Density)` -> `Math (Multiply, 4.0)` -> `Density`.
   - `Volume Info (Flame)` -> `ColorRamp` (0.08 to 0.24) -> `Math (Multiply, 8.0)` ->
     `Blackbody Intensity` (`Blackbody Tint` warm orange-white, `Temperature = 1200 K`).
5. Enables Compositor node tree with `Glare` (`Fog Glow`, `High`, `Threshold = 0.5`,
   `Size = 8` / `0.8`, `Mix = -0.9` / `Strength = 0.1`) preserving RGBA alpha.
6. Auto-calibrates orthographic camera to full expansion bounds across all baked frames + 10%
   margin so smoke never clips frame edges.
7. Renders 64 evenly-spaced frames across active explosion lifespan in Cycles GPU (`OPTIX`/`CUDA`)
   with `film_transparent = True` as 256x256 16-bit RGBA PNGs.
8. Stitches frames 0-63 into `explosion_flipbook_8x8.png`, `explosion_core_8x8.png`, and
   `explosion_emissive_8x8.png` (2048x2048) with halo-free alpha handling.
"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def log(msg: str) -> None:
    """Print timestamped pipeline progress message."""
    print(f"[FlipbookPipeline] {msg}", flush=True)


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments passed after '--' in Blender headless invocation."""
    raw_args: list[str] = sys.argv
    if "--" in raw_args:
        raw_args = raw_args[raw_args.index("--") + 1 :]
    else:
        raw_args = []

    parser = argparse.ArgumentParser(
        description="Headless Blender Mantaflow dual-emitter mushroom explosion flipbook generator"
    )
    parser.add_argument(
        "--resolution",
        type=int,
        default=192,
        help="Mantaflow domain max resolution divisions (default: 192)",
    )
    parser.add_argument(
        "--sim-frames",
        type=int,
        default=96,
        help="Total simulation frames to bake before sampling 64 frames (default: 96)",
    )
    parser.add_argument(
        "--frames",
        type=int,
        default=64,
        help="Number of flipbook frames to render and pack into 8x8 sheet (default: 64)",
    )
    parser.add_argument(
        "--frame-size",
        type=int,
        default=256,
        help="Per-frame pixel width and height (default: 256)",
    )
    parser.add_argument(
        "--samples",
        type=int,
        default=48,
        help="Cycles render samples per frame (default: 48)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="",
        help="Primary output path (default: assets/vfx/explosion/explosion_flipbook_8x8.png)",
    )
    parser.add_argument(
        "--skip-import",
        action="store_true",
        help="Skip running godot --headless --editor --quit after generation",
    )
    return parser.parse_args(raw_args)


def build_dual_split_emitters(scene: object) -> tuple[object, object]:
    """Create 12m diameter low cylinder + soft domed top split into Upper_Cap and Lower_Ring."""
    import bmesh  # type: ignore
    import bpy  # type: ignore

    segments: int = 64

    # 1a. Lower_Ring: 12m diameter (radius = 6.0m) low cylindrical base ring
    # Profile tapers slightly so outward normals also have a gentle upward component (+Z)
    bm_low = bmesh.new()
    low_rings: list[tuple[float, float]] = [
        (0.4, 6.00),
        (1.0, 6.05),
        (1.7, 5.90),
    ]
    rv_low: list[list[object]] = []
    for z_val, r_val in low_rings:
        ring = [
            bm_low.verts.new(
                (
                    r_val * math.cos(2.0 * math.pi * i / segments),
                    r_val * math.sin(2.0 * math.pi * i / segments),
                    z_val,
                )
            )
            for i in range(segments)
        ]
        rv_low.append(ring)

    for r_idx in range(len(low_rings) - 1):
        for i in range(segments):
            ni = (i + 1) % segments
            bm_low.faces.new(
                (
                    rv_low[r_idx][i],
                    rv_low[r_idx][ni],
                    rv_low[r_idx + 1][ni],
                    rv_low[r_idx + 1][i],
                )
            )

    bmesh.ops.recalc_face_normals(bm_low, faces=bm_low.faces)
    for face in bm_low.faces:
        face.normal_update()
        center = face.calc_center_median()
        if face.normal.x * center.x + face.normal.y * center.y < 0.0:
            face.normal_flip()

    mesh_low = bpy.data.meshes.new("Lower_Ring_Mesh")
    bm_low.to_mesh(mesh_low)
    bm_low.free()
    lower_ring = bpy.data.objects.new("Lower_Ring", mesh_low)
    scene.collection.objects.link(lower_ring)
    lower_ring.hide_render = True

    # 1b. Upper_Cap: Soft domed top spanning 12m diameter down to apex, normals upward/outward
    bm_up = bmesh.new()
    up_rings: list[tuple[float, float]] = [
        (1.7, 5.90),
        (2.3, 4.90),
        (2.8, 3.60),
        (3.2, 2.20),
        (3.45, 0.90),
    ]
    rv_up: list[list[object]] = []
    for z_val, r_val in up_rings:
        ring = [
            bm_up.verts.new(
                (
                    r_val * math.cos(2.0 * math.pi * i / segments),
                    r_val * math.sin(2.0 * math.pi * i / segments),
                    z_val,
                )
            )
            for i in range(segments)
        ]
        rv_up.append(ring)

    apex_vert = bm_up.verts.new((0.0, 0.0, 3.6))
    for r_idx in range(len(up_rings) - 1):
        for i in range(segments):
            ni = (i + 1) % segments
            bm_up.faces.new(
                (
                    rv_up[r_idx][i],
                    rv_up[r_idx][ni],
                    rv_up[r_idx + 1][ni],
                    rv_up[r_idx + 1][i],
                )
            )
    for i in range(segments):
        ni = (i + 1) % segments
        bm_up.faces.new((rv_up[-1][i], rv_up[-1][ni], apex_vert))

    bmesh.ops.recalc_face_normals(bm_up, faces=bm_up.faces)
    for face in bm_up.faces:
        face.normal_update()
        if face.normal.z < 0.0:
            face.normal_flip()

    mesh_up = bpy.data.meshes.new("Upper_Cap_Mesh")
    bm_up.to_mesh(mesh_up)
    bm_up.free()
    upper_cap = bpy.data.objects.new("Upper_Cap", mesh_up)
    scene.collection.objects.link(upper_cap)
    upper_cap.hide_render = True

    # Apply scale (Ctrl+A equivalent) on both objects
    bpy.ops.object.select_all(action="DESELECT")
    upper_cap.select_set(True)
    lower_ring.select_set(True)
    bpy.context.view_layer.objects.active = upper_cap
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    return upper_cap, lower_ring


def configure_particles_and_flows(upper_cap: object, lower_ring: object) -> None:
    """Attach zero-gravity burst particle systems and Mantaflow Fluid Flow modifiers."""
    # Upper_Cap particle system: 20,000 particles, frames 1-7, life 12 (rand 1.0),
    # normal_factor = 85 m/s, factor_random = 10.0, gravity = 0.0
    p_mod_up = upper_cap.modifiers.new(name="Upper_Cap_Particles", type="PARTICLE_SYSTEM")
    ps_up = p_mod_up.particle_system.settings
    ps_up.count = 20000
    ps_up.frame_start = 1.0
    ps_up.frame_end = 7.0
    ps_up.lifetime = 12.0
    ps_up.lifetime_random = 1.0
    ps_up.emit_from = "FACE"
    ps_up.normal_factor = 85.0
    ps_up.factor_random = 10.0
    ps_up.drag_factor = 0.22
    ps_up.damping = 0.62
    ps_up.render_type = "NONE"
    ps_up.effector_weights.gravity = 0.0

    # Lower_Ring particle system: 10,000 particles, frames 22-36, life 20,
    # normal_factor = 55 m/s, factor_random = 2.0, gravity = 0.0
    p_mod_low = lower_ring.modifiers.new(name="Lower_Ring_Particles", type="PARTICLE_SYSTEM")
    ps_low = p_mod_low.particle_system.settings
    ps_low.count = 10000
    ps_low.frame_start = 22.0
    ps_low.frame_end = 36.0
    ps_low.lifetime = 20.0
    ps_low.lifetime_random = 0.25
    ps_low.emit_from = "FACE"
    ps_low.normal_factor = 55.0
    ps_low.factor_random = 2.0
    ps_low.drag_factor = 0.32
    ps_low.damping = 0.72
    ps_low.render_type = "NONE"
    ps_low.effector_weights.gravity = 0.0

    # Upper_Cap Flow: Fire + Smoke ('BOTH'), Source = Particle System,
    # Initial Velocity = True (1.0), Sampling Substeps = 2
    flow_mod_up = upper_cap.modifiers.new(name="Fluid_Flow_Upper", type="FLUID")
    flow_mod_up.fluid_type = "FLOW"
    fs_up = flow_mod_up.flow_settings
    fs_up.flow_type = "BOTH"
    fs_up.flow_behavior = "INFLOW"
    fs_up.flow_source = "PARTICLES"
    fs_up.particle_system = p_mod_up.particle_system
    fs_up.use_initial_velocity = True
    fs_up.velocity_factor = 1.0
    fs_up.subframes = 2
    fs_up.fuel_amount = 1.6
    fs_up.temperature = 2.2
    fs_up.use_particle_size = True
    fs_up.particle_size = 1.25

    # Lower_Ring Flow: Smoke ('SMOKE'), Source = Particle System,
    # Initial Velocity = True (1.0), Sampling Substeps = 2
    flow_mod_low = lower_ring.modifiers.new(name="Fluid_Flow_Lower", type="FLUID")
    flow_mod_low.fluid_type = "FLOW"
    fs_low = flow_mod_low.flow_settings
    fs_low.flow_type = "SMOKE"
    fs_low.flow_behavior = "INFLOW"
    fs_low.flow_source = "PARTICLES"
    fs_low.particle_system = p_mod_low.particle_system
    fs_low.use_initial_velocity = True
    fs_low.velocity_factor = 1.0
    fs_low.subframes = 2
    fs_low.density = 1.0
    fs_low.use_particle_size = True
    fs_low.particle_size = 1.15


def build_domain(scene: object, resolution: int, sim_frames: int, cache_dir: str) -> object:
    """Create Mantaflow Gas Domain with Adaptive Domain, Heat=0.05, Vorticity=0.2, Upres=2."""
    import bpy  # type: ignore

    # 180m x 180m x 180m domain with floor at Z=0 -> center at (0, 0, 90)
    # Ensures zero wall clipping during 85 m/s burst; Adaptive Domain shrinks active grid tightly.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 90.0))
    domain = bpy.context.active_object
    domain.name = "Explosion_Domain"
    domain.scale = (180.0, 180.0, 180.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    d_mod = domain.modifiers.new(name="Fluid_Domain", type="FLUID")
    d_mod.fluid_type = "DOMAIN"
    ds = d_mod.domain_settings
    ds.domain_type = "GAS"
    ds.resolution_max = resolution
    ds.use_adaptive_domain = True
    ds.adapt_margin = 6
    ds.adapt_threshold = 0.005

    # Gas dynamics matching prompt specification
    ds.alpha = 1.0  # Buoyancy Density = 1.0
    ds.beta = 0.05  # Heat = 0.05 (keeps fireball rolling instead of burning out instantly)
    ds.vorticity = 0.2  # Vorticity = 0.2
    ds.burning_rate = 0.55
    ds.flame_smoke = 1.8
    ds.flame_vorticity = 0.35
    ds.use_collision_border_bottom = True

    # Gentle logarithmic smoke dissolve in late frames so final frames fade cleanly without sudden pop
    ds.use_dissolve_smoke = True
    ds.dissolve_speed = 65
    ds.use_dissolve_smoke_log = True

    # Upres Noise: Factor = 2, Strength = 1.0, Scale = 10.0, Time = 0.1
    ds.use_noise = True
    ds.noise_scale = 2
    ds.noise_strength = 1.0
    ds.noise_pos_scale = 10.0
    ds.noise_time_anim = 0.1

    # Cache: Modular + OpenVDB + Resumable (required by Mantaflow noise upres solver)
    ds.cache_type = "MODULAR"
    ds.cache_resumable = True
    ds.cache_data_format = "OPENVDB"
    ds.cache_noise_format = "OPENVDB"
    ds.cache_frame_start = 1
    ds.cache_frame_end = sim_frames
    ds.cache_directory = cache_dir

    return domain


def build_volume_shader(domain: object) -> None:
    """Create Principled Volume shader network matching exact specification."""
    import bpy  # type: ignore

    mat = bpy.data.materials.new(name="Explosion_Principled_Volume")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    # Volume Info node
    node_vol_info = nodes.new(type="ShaderNodeVolumeInfo")
    node_vol_info.location = (-650, 0)

    # Density path: Volume Info (Density) -> Math (Multiply, 4.0) -> Principled Volume (Density)
    node_mult_density = nodes.new(type="ShaderNodeMath")
    node_mult_density.location = (-300, 150)
    node_mult_density.operation = "MULTIPLY"
    node_mult_density.inputs[1].default_value = 4.0

    # Flame path: Volume Info (Flame) -> ColorRamp (0.08 to 0.24) -> Math (Multiply, 8.0) -> Blackbody Intensity
    node_ramp = nodes.new(type="ShaderNodeValToRGB")
    node_ramp.location = (-420, -150)
    cr = node_ramp.color_ramp
    cr.interpolation = "LINEAR"
    cr.elements[0].position = 0.08
    cr.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    cr.elements[1].position = 0.24
    cr.elements[1].color = (1.0, 1.0, 1.0, 1.0)

    node_mult_flame = nodes.new(type="ShaderNodeMath")
    node_mult_flame.location = (-120, -150)
    node_mult_flame.operation = "MULTIPLY"
    node_mult_flame.inputs[1].default_value = 8.0

    # Principled Volume
    node_pvol = nodes.new(type="ShaderNodeVolumePrincipled")
    node_pvol.location = (180, 0)
    node_pvol.inputs["Color"].default_value = (0.26, 0.24, 0.22, 1.0)
    node_pvol.inputs["Absorption Color"].default_value = (0.12, 0.11, 0.10, 1.0)
    node_pvol.inputs["Anisotropy"].default_value = 0.25
    node_pvol.inputs["Blackbody Tint"].default_value = (1.0, 0.72, 0.38, 1.0)
    node_pvol.inputs["Temperature"].default_value = 1200.0
    # Clear attribute strings so socket links drive Density and Blackbody directly
    if "Density Attribute" in node_pvol.inputs:
        node_pvol.inputs["Density Attribute"].default_value = ""
    if "Temperature Attribute" in node_pvol.inputs:
        node_pvol.inputs["Temperature Attribute"].default_value = ""

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_out.location = (480, 0)

    links.new(node_vol_info.outputs["Density"], node_mult_density.inputs[0])
    links.new(node_mult_density.outputs["Value"], node_pvol.inputs["Density"])
    links.new(node_vol_info.outputs["Flame"], node_ramp.inputs["Fac"])
    links.new(node_ramp.outputs["Color"], node_mult_flame.inputs[0])
    links.new(node_mult_flame.outputs["Value"], node_pvol.inputs["Blackbody Intensity"])
    links.new(node_pvol.outputs["Volume"], node_out.inputs["Volume"])

    domain.data.materials.clear()
    domain.data.materials.append(mat)


def configure_compositor(scene: object) -> None:
    """Enable Compositor nodes with Glare (Fog Glow, High, Threshold=0.5, Size=8/0.8, Mix=-0.9)."""
    import bpy  # type: ignore

    # Support both Blender 5.x compositing_node_group and legacy scene.node_tree
    if hasattr(scene, "compositing_node_group"):
        comp_tree = bpy.data.node_groups.new("ExplosionCompositor", "CompositorNodeTree")
        scene.compositing_node_group = comp_tree
        nodes = comp_tree.nodes
        links = comp_tree.links
        nodes.clear()

        node_rl = nodes.new(type="CompositorNodeRLayers")
        node_rl.location = (-300, 0)

        node_glare = nodes.new(type="CompositorNodeGlare")
        node_glare.location = (0, 0)
        if "Type" in node_glare.inputs:
            node_glare.inputs["Type"].default_value = "Fog Glow"
        if "Quality" in node_glare.inputs:
            node_glare.inputs["Quality"].default_value = "High"
        if "Threshold" in node_glare.inputs:
            node_glare.inputs["Threshold"].default_value = 0.5
        if "Size" in node_glare.inputs:
            # Blender 5.x Glare Size socket is normalized [0..1] corresponding to legacy Size 8
            node_glare.inputs["Size"].default_value = 0.8
        if "Strength" in node_glare.inputs:
            # Legacy Mix = -0.9 corresponds to 10% glare blend (Strength = 0.1)
            node_glare.inputs["Strength"].default_value = 0.1

        comp_tree.interface.new_socket(
            name="Image", in_out="OUTPUT", socket_type="NodeSocketColor"
        )
        node_out = nodes.new(type="NodeGroupOutput")
        node_out.location = (300, 0)

        links.new(node_rl.outputs["Image"], node_glare.inputs["Image"])
        links.new(node_glare.outputs["Image"], node_out.inputs["Image"])
    else:
        scene.use_nodes = True
        comp_tree = scene.node_tree
        nodes = comp_tree.nodes
        links = comp_tree.links
        nodes.clear()

        node_rl = nodes.new(type="CompositorNodeRLayers")
        node_glare = nodes.new(type="CompositorNodeGlare")
        node_glare.glare_type = "FOG_GLOW"
        node_glare.quality = "HIGH"
        node_glare.mix = -0.9
        node_glare.threshold = 0.5
        node_glare.size = 8

        node_comp = nodes.new(type="CompositorNodeComposite")
        node_comp.use_alpha = True
        links.new(node_rl.outputs["Image"], node_glare.inputs["Image"])
        links.new(node_glare.outputs["Image"], node_comp.inputs["Image"])


def configure_cycles_gpu(scene: object, frame_size: int, samples: int) -> None:
    """Configure Cycles GPU (OPTIX/CUDA), transparent film, and 256x256 16-bit RGBA PNG output."""
    import bpy  # type: ignore

    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences

    selected_backend: str = "NONE"
    for backend in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
            gpu_devs = [d for d in prefs.devices if d.type == backend]
            if gpu_devs:
                for dev in prefs.devices:
                    dev.use = dev.type in ("OPTIX", "CUDA")
                selected_backend = backend
                break
        except Exception:  # pylint: disable=broad-exception-caught
            continue

    scene.cycles.device = "GPU" if selected_backend != "NONE" else "CPU"
    scene.cycles.samples = samples
    scene.cycles.volume_step_rate = 0.5
    scene.cycles.volume_preview_step_rate = 0.5
    scene.cycles.volume_max_steps = 512
    scene.cycles.use_denoising = True
    log(f"Cycles configured on {scene.cycles.device} (backend={selected_backend}, samples={samples})")

    scene.render.film_transparent = True
    scene.render.resolution_x = frame_size
    scene.render.resolution_y = frame_size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "16"


def setup_lighting_and_camera(scene: object) -> object:
    """Create directional volumetric key/rim lighting and front orthographic camera."""
    import bpy  # type: ignore

    # Warm key sun to sculpt rolling mushroom cloud lobes
    key_data = bpy.data.lights.new(name="Sun_Key", type="SUN")
    key_data.energy = 5.5
    key_data.color = (1.0, 0.95, 0.88)
    key_obj = bpy.data.objects.new(name="Sun_Key", object_data=key_data)
    scene.collection.objects.link(key_obj)
    key_obj.rotation_euler = (math.radians(52.0), math.radians(24.0), math.radians(-38.0))

    # Cool sky fill light to lift dark smoke crevices cleanly
    fill_data = bpy.data.lights.new(name="Sun_Fill", type="SUN")
    fill_data.energy = 2.2
    fill_data.color = (0.76, 0.86, 1.0)
    fill_obj = bpy.data.objects.new(name="Sun_Fill", object_data=fill_data)
    scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(-32.0), math.radians(-42.0), math.radians(125.0))

    cam_data = bpy.data.cameras.new(name="Ortho_Flipbook_Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 160.0
    cam_data.clip_start = 0.1
    cam_data.clip_end = 600.0
    cam_obj = bpy.data.objects.new(name="Ortho_Flipbook_Camera", object_data=cam_data)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (0.0, -220.0, 50.0)
    cam_obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.camera = cam_obj
    return cam_obj


def calibrate_camera_to_baked_bounds(
    scene: object, domain: object, cam_obj: object, sim_frames: int
) -> tuple[float, float, float, float]:
    """Inspect adaptive domain bounds across all baked frames and frame camera with 12% margin."""
    import bpy  # type: ignore

    depsgraph = bpy.context.evaluated_depsgraph_get()
    min_x: float = 1e9
    max_x: float = -1e9
    min_z: float = 1e9
    max_z: float = -1e9

    for f_idx in range(1, sim_frames + 1):
        scene.frame_set(f_idx)
        eval_dom = domain.evaluated_get(depsgraph)
        verts = [eval_dom.matrix_world @ v.co for v in eval_dom.data.vertices]
        if not verts:
            continue
        fx_min = min(v.x for v in verts)
        fx_max = max(v.x for v in verts)
        fz_min = min(v.z for v in verts)
        fz_max = max(v.z for v in verts)
        # Ignore default unbaked full-domain cube if empty on frame 1
        if (fx_max - fx_min) < 179.0 or (fz_max - fz_min) < 179.0:
            min_x = min(min_x, fx_min)
            max_x = max(max_x, fx_max)
            min_z = min(min_z, fz_min)
            max_z = max(max_z, fz_max)

    if min_x > max_x:
        min_x, max_x, min_z, max_z = -75.0, 75.0, 0.0, 85.0

    # Symmetric X framing around X=0 so explosion stem stays centered horizontally
    half_width: float = max(abs(min_x), abs(max_x))
    width_span: float = half_width * 2.0
    height_span: float = max_z - min_z
    max_span: float = max(width_span, height_span)

    # Add 12% safety margin (>= 10% required) so smoke and bloom never touch frame borders
    ortho_scale: float = max_span * 1.12
    center_z: float = min_z + 0.5 * height_span

    cam_obj.data.ortho_scale = ortho_scale
    cam_obj.location = (0.0, -220.0, center_z)
    log(
        f"Calibrated Ortho Camera: bounds X=[{min_x:.1f}, {max_x:.1f}], "
        f"Z=[{min_z:.1f}, {max_z:.1f}] -> center_z={center_z:.2f}, ortho_scale={ortho_scale:.2f}m"
    )
    return min_x, max_x, min_z, max_z


def stitch_and_pack_sheets(
    frames_dir: Path,
    flipbook_path: Path,
    core_path: Path,
    emissive_path: Path,
    frame_count: int = 64,
    frame_size: int = 256,
) -> None:
    """Stitch 64 frames into 8x8 RGBA flipbook + emissive mask using system Python (Pillow/numpy)."""
    log(f"Stitching {frame_count} frames into 2048x2048 sheets...")
    py_script = """
import sys
from pathlib import Path
import numpy as np
from PIL import Image

frames_dir = Path(sys.argv[1])
flipbook_path = Path(sys.argv[2])
core_path = Path(sys.argv[3])
emissive_path = Path(sys.argv[4])
frame_count = int(sys.argv[5])
frame_size = int(sys.argv[6])

frame_files = sorted(frames_dir.glob("frame_*.png"))[:frame_count]
if len(frame_files) < frame_count:
    raise RuntimeError(f"Expected {frame_count} frames, found {len(frame_files)}")

grid_cols = 8
grid_rows = 8
sheet_w = grid_cols * frame_size
sheet_h = grid_rows * frame_size

rgba_sheet = np.zeros((sheet_h, sheet_w, 4), dtype=np.uint8)
emissive_sheet = np.zeros((sheet_h, sheet_w, 4), dtype=np.uint8)

# Precompute smooth radial edge safety mask (1.0 inside 96% radius, smooth taper to 0 at 100% border)
yy, xx = np.mgrid[0:frame_size, 0:frame_size]
nx = (xx - (frame_size - 1) * 0.5) / ((frame_size - 1) * 0.5)
ny = (yy - (frame_size - 1) * 0.5) / ((frame_size - 1) * 0.5)
cheb = np.maximum(np.abs(nx), np.abs(ny))
border_taper = np.clip((1.0 - cheb) / 0.04, 0.0, 1.0)

for idx, fpath in enumerate(frame_files):
    col = idx % grid_cols
    row = idx // grid_cols
    with Image.open(fpath) as im:
        arr = np.array(im.convert("RGBA"), dtype=np.float32) / 255.0

    rgb = arr[..., :3]
    alpha = arr[..., 3]

    # Compute fire/glow intensity from warm orange-white luminance so additive blackbody fire
    # & Fog Glow remain visible and halo-free when rendered with standard alpha blending.
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    warmth = np.clip(rgb[..., 0] - 0.65 * rgb[..., 2], 0.0, 1.0)
    fire_mask = np.clip(warmth * 1.45 + np.maximum(0.0, lum - 0.35) * 1.15, 0.0, 1.0)

    # Effective alpha combines smoke absorption alpha with warm fire emission visibility
    eff_alpha = np.maximum(alpha, np.clip(fire_mask * 0.95, 0.0, 1.0))

    # Clean zeroing of near-zero noise floor (< 1.5%) to prevent faint alpha halos
    eff_alpha = np.where(eff_alpha < 0.015, 0.0, np.clip((eff_alpha - 0.015) / 0.985, 0.0, 1.0))
    eff_alpha *= border_taper

    # Blender PNG output already stores straight (unpremultiplied) RGB where alpha > 0.
    # For pure smoke edges (where fire_mask is low), clamp fringe RGB to natural dark smoke albedo
    # so semi-transparent smoke wisps never brighten into a gray/white halo over dark backgrounds.
    smoke_edge_cap = np.clip(0.24 + 0.76 * np.maximum(eff_alpha, fire_mask), 0.24, 1.0)[..., None]
    clean_rgb = np.minimum(rgb, smoke_edge_cap)
    clean_rgb = np.where(eff_alpha[..., None] > 0.0, clean_rgb, 0.0)

    # Emissive sheet stores warm HDR fire color in RGB and fire intensity in Alpha (zero on pure smoke)
    emissive_a = np.clip((fire_mask - 0.08) / 0.92, 0.0, 1.0) * border_taper
    emissive_rgb = np.clip(rgb * (emissive_a[..., None] ** 0.75) * 1.35, 0.0, 1.0)
    emissive_rgb = np.where(emissive_a[..., None] > 0.01, emissive_rgb, 0.0)
    emissive_a = np.where(emissive_a > 0.01, emissive_a, 0.0)

    y0, y1 = row * frame_size, (row + 1) * frame_size
    x0, x1 = col * frame_size, (col + 1) * frame_size

    rgba_sheet[y0:y1, x0:x1, :3] = np.round(clean_rgb * 255.0).astype(np.uint8)
    rgba_sheet[y0:y1, x0:x1, 3] = np.round(eff_alpha * 255.0).astype(np.uint8)

    emissive_sheet[y0:y1, x0:x1, :3] = np.round(emissive_rgb * 255.0).astype(np.uint8)
    emissive_sheet[y0:y1, x0:x1, 3] = np.round(emissive_a * 255.0).astype(np.uint8)

flipbook_path.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray(rgba_sheet, mode="RGBA").save(str(flipbook_path), format="PNG")
if core_path != flipbook_path:
    Image.fromarray(rgba_sheet, mode="RGBA").save(str(core_path), format="PNG")
Image.fromarray(emissive_sheet, mode="RGBA").save(str(emissive_path), format="PNG")
print("Saved flipbook, core alias, and emissive mask sheets successfully.")
"""
    proc = subprocess.run(
        [
            "python3",
            "-c",
            py_script,
            str(frames_dir),
            str(flipbook_path),
            str(core_path),
            str(emissive_path),
            str(frame_count),
            str(frame_size),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"Stitching script failed:\n{proc.stderr}")
    log(proc.stdout.strip())


def trigger_godot_import(project_root: Path) -> None:
    """Run headless Godot editor import to generate/refresh .import and .uid metadata."""
    godot_bin = shutil.which("godot")
    if not godot_bin:
        log("WARNING: godot binary not found in PATH; skipping import.")
        return

    log(f"Running '{godot_bin} --headless --editor --quit'...")
    try:
        proc = subprocess.run(
            [godot_bin, "--headless", "--editor", "--quit"],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            timeout=90,
            check=False,
        )
        if proc.returncode == 0:
            log("Godot headless import completed cleanly.")
        else:
            log(f"Godot import exited with code {proc.returncode}: {proc.stderr[:300]}")
    except subprocess.TimeoutExpired:
        log("Godot headless import timed out after 90s.")


def run_pipeline() -> None:
    """Execute full dual-emitter Mantaflow simulation, Cycles GPU render, and 8x8 packing."""
    try:
        import bpy  # type: ignore # pylint: disable=import-error
    except ImportError:
        log("Error: Must be executed via 'blender --background --python tools/generate_explosion_flipbook.py'")
        sys.exit(1)

    args = parse_args()
    project_root = Path(__file__).resolve().parent.parent
    out_dir = project_root / "assets" / "vfx" / "explosion"

    if args.output:
        flipbook_path = Path(args.output).resolve()
    else:
        flipbook_path = out_dir / "explosion_flipbook_8x8.png"
    core_path = out_dir / "explosion_core_8x8.png"
    emissive_path = out_dir / "explosion_emissive_8x8.png"

    log("=================================================================")
    log("Starting Dual-Emitter Mushroom-Cloud Explosion Flipbook Pipeline")
    log(f"Domain Resolution: {args.resolution} (Noise Upres Factor = 2 -> {args.resolution * 2})")
    log(f"Sim Frames: {args.sim_frames} -> Rendered Flipbook Frames: {args.frames} ({args.frame_size}x{args.frame_size})")
    log(f"Output Flipbook: {flipbook_path}")
    log(f"Output Emissive: {emissive_path}")
    log("=================================================================")

    temp_work_dir = tempfile.mkdtemp(prefix="mantaflow_mushroom_")
    temp_cache_dir = os.path.join(temp_work_dir, "cache")
    temp_frames_dir = os.path.join(temp_work_dir, "frames")
    os.makedirs(temp_cache_dir, exist_ok=True)
    os.makedirs(temp_frames_dir, exist_ok=True)

    try:
        # Step 1: Clean factory reset
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.frame_start = 1
        scene.frame_end = args.sim_frames
        scene.render.fps = 24

        # Step 2: Build Dual-Mesh Split Emitters (Upper_Cap + Lower_Ring)
        log("Step 1: Building 12m dual-mesh split emitters (Upper_Cap & Lower_Ring)...")
        upper_cap, lower_ring = build_dual_split_emitters(scene)

        # Step 3: Particle systems (gravity = 0.0) & Mantaflow Inflow modifiers
        log("Step 2: Configuring particle systems (20k & 10k) and Mantaflow Flow modifiers...")
        configure_particles_and_flows(upper_cap, lower_ring)

        # Step 4: Mantaflow Gas Domain (Res 192, Adaptive, Heat=0.05, Vorticity=0.2, Upres=2)
        log(f"Step 3: Creating Mantaflow Gas Domain (res={args.resolution}, Upres=2, OpenVDB)...")
        domain = build_domain(scene, args.resolution, args.sim_frames, temp_cache_dir)

        # Step 5: Principled Volume Shader & Compositor Glare
        log("Step 4: Building Principled Volume shader network & Compositor Glare...")
        build_volume_shader(domain)
        configure_compositor(scene)

        # Step 6: Cycles GPU & Camera
        log("Step 5: Configuring Cycles GPU (OPTIX/CUDA) and Orthographic Camera...")
        configure_cycles_gpu(scene, args.frame_size, args.samples)
        cam_obj = setup_lighting_and_camera(scene)

        # Save .blend so Modular OpenVDB cache writes reliably
        blend_file = os.path.join(temp_work_dir, "mushroom_explosion.blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend_file)

        # Step 7: Bake Modular Data + Noise
        log("Step 6: Baking Mantaflow Gas Data (bpy.ops.fluid.bake_data)...")
        bpy.context.view_layer.objects.active = domain
        domain.select_set(True)
        bpy.ops.fluid.bake_data()
        log("Step 7: Baking Mantaflow Upres Noise (bpy.ops.fluid.bake_noise)...")
        bpy.ops.fluid.bake_noise()

        # Step 8: Calibrate Orthographic Camera to full expansion bounds + 12% margin
        log("Step 8: Calibrating orthographic camera to baked expansion bounds...")
        calibrate_camera_to_baked_bounds(scene, domain, cam_obj, args.sim_frames)

        # Step 9: Render 64 evenly-spaced frames across active explosion lifespan (frames 2..sim_frames)
        log(f"Step 9: Rendering {args.frames} evenly-spaced 16-bit RGBA frames...")
        start_sim_frame: int = 2
        end_sim_frame: int = args.sim_frames
        for out_idx in range(args.frames):
            t_ratio: float = out_idx / float(max(1, args.frames - 1))
            sim_f: int = int(round(start_sim_frame + t_ratio * (end_sim_frame - start_sim_frame)))
            scene.frame_set(sim_f)
            frame_out_path = os.path.join(temp_frames_dir, f"frame_{out_idx:04d}.png")
            scene.render.filepath = frame_out_path
            bpy.ops.render.render(write_still=True)
            if (out_idx + 1) % 8 == 0 or out_idx == args.frames - 1:
                log(f"Rendered flipbook frame {out_idx + 1}/{args.frames} (sim frame {sim_f})")

        # Step 10: Stitch 8x8 flipbook + emissive mask
        log("Step 10: Stitching 8x8 flipbook and emissive sheets...")
        stitch_and_pack_sheets(
            Path(temp_frames_dir),
            flipbook_path,
            core_path,
            emissive_path,
            frame_count=args.frames,
            frame_size=args.frame_size,
        )

        # Step 11: Trigger Godot import
        if not args.skip_import:
            trigger_godot_import(project_root)

        log("Pipeline complete!")
    finally:
        log("Cleaning up temporary simulation cache and frame directories...")
        shutil.rmtree(temp_work_dir, ignore_errors=True)


if __name__ == "__main__":
    run_pipeline()
