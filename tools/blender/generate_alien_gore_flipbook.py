#!/usr/bin/env python3
"""Headless Blender 5.x Mantaflow microgravity alien gore flipbook generator.

Bakes a 64-frame Mantaflow liquid burst simulation (`resolution_max = 96`, `mesh_scale = 2`)
in microgravity (`gravity = (0.0, 0.0, -0.5)`) with a strong `TURBULENCE` effector, jagged
crimson meat/bone chunk particles (`MeatChunks`), Brownian glowing green "Acid Fizz" particles,
and secondary spray/bubble/foam droplets. Renders 64 top-down orthographic 256x256 RGBA frames
in `BLENDER_EEVEE` with motion blur and stitches them into a 2048x2048 (8x8) RGBA flipbook
atlas at `assets/vfx/green_blood_atlas.png` preserving true RGBA alpha.
"""

from __future__ import annotations

import glob
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import bpy  # type: ignore
import mathutils  # type: ignore


def log(msg: str) -> None:
    """Print flush-enabled progress message."""
    print(f"[AlienGoreFlipbook] {msg}", flush=True)


def create_blood_material() -> bpy.types.Material:
    """Build the multi-hue wet alien blood Principled BSDF material for the liquid domain."""
    mat = bpy.data.materials.new(name="AlienBlood_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_out.location = (700, 0)

    node_bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    node_bsdf.location = (350, 0)
    node_bsdf.inputs["Roughness"].default_value = 0.02
    node_bsdf.inputs["IOR"].default_value = 1.38
    if "Specular IOR Level" in node_bsdf.inputs:
        node_bsdf.inputs["Specular IOR Level"].default_value = 1.0
    if "Subsurface Weight" in node_bsdf.inputs:
        node_bsdf.inputs["Subsurface Weight"].default_value = 0.5
    if "Subsurface Radius" in node_bsdf.inputs:
        node_bsdf.inputs["Subsurface Radius"].default_value = (0.6, 0.8, 0.2)
    if "Subsurface Scale" in node_bsdf.inputs:
        node_bsdf.inputs["Subsurface Scale"].default_value = 0.012
    if "Emission Strength" in node_bsdf.inputs:
        node_bsdf.inputs["Emission Strength"].default_value = 0.28

    # 3D Object-space Noise Texture
    node_texcoord = nodes.new(type="ShaderNodeTexCoord")
    node_texcoord.location = (-750, 150)

    node_noise = nodes.new(type="ShaderNodeTexNoise")
    node_noise.location = (-500, 150)
    node_noise.noise_dimensions = "3D"
    node_noise.inputs["Scale"].default_value = 2.6
    node_noise.inputs["Detail"].default_value = 6.0
    node_noise.inputs["Roughness"].default_value = 0.65
    node_noise.inputs["Distortion"].default_value = 1.1

    # Geometry Pointiness + LayerWeight Fresnel for thin tearing edges in EEVEE & Cycles
    node_geom = nodes.new(type="ShaderNodeNewGeometry")
    node_geom.location = (-750, -120)

    node_layer = nodes.new(type="ShaderNodeLayerWeight")
    node_layer.location = (-750, -320)
    node_layer.inputs["Blend"].default_value = 0.45

    # Combine Pointiness and Fresnel (thin/grazing edges -> higher value)
    node_edge_add = nodes.new(type="ShaderNodeMath")
    node_edge_add.location = (-480, -200)
    node_edge_add.operation = "ADD"

    # Combine 3D Noise Factor with edge factor to drive ColorRamp across full [0.3..0.75] span
    node_mix_fac = nodes.new(type="ShaderNodeMath")
    node_mix_fac.location = (-240, 0)
    node_mix_fac.operation = "MULTIPLY_ADD"
    node_mix_fac.inputs[1].default_value = 0.72

    node_edge_scale = nodes.new(type="ShaderNodeMath")
    node_edge_scale.location = (-360, -200)
    node_edge_scale.operation = "MULTIPLY"
    node_edge_scale.inputs[1].default_value = 0.25

    # ColorRamp: deep oxidized maroon -> rotting yellow -> vibrant acidic green/chartreuse
    node_ramp = nodes.new(type="ShaderNodeValToRGB")
    node_ramp.location = (0, 80)
    cr = node_ramp.color_ramp
    cr.interpolation = "LINEAR"
    cr.elements[0].position = 0.42
    cr.elements[0].color = (0.22, 0.015, 0.03, 1.0)
    mid_elem = cr.elements.new(0.53)
    mid_elem.color = (0.72, 0.66, 0.1, 1.0)
    cr.elements[2].position = 0.62
    cr.elements[2].color = (0.22, 1.0, 0.08, 1.0)

    # Subtle micro-ripple bump so specular highlights catch organic wet sheen
    node_bump = nodes.new(type="ShaderNodeBump")
    node_bump.location = (80, -180)
    node_bump.inputs["Strength"].default_value = 0.08
    node_bump.inputs["Distance"].default_value = 0.02

    noise_out = node_noise.outputs["Factor"] if "Factor" in node_noise.outputs else node_noise.outputs[0]
    ramp_in = node_ramp.inputs["Factor"] if "Factor" in node_ramp.inputs else node_ramp.inputs[0]

    links.new(node_texcoord.outputs["Object"], node_noise.inputs["Vector"])
    links.new(node_geom.outputs["Pointiness"], node_edge_add.inputs[0])
    links.new(node_layer.outputs["Fresnel"], node_edge_add.inputs[1])
    links.new(node_edge_add.outputs["Value"], node_edge_scale.inputs[0])
    links.new(noise_out, node_mix_fac.inputs[0])
    links.new(node_edge_scale.outputs["Value"], node_mix_fac.inputs[2])
    links.new(node_mix_fac.outputs["Value"], ramp_in)
    links.new(node_ramp.outputs["Color"], node_bsdf.inputs["Base Color"])
    if "Emission Color" in node_bsdf.inputs:
        links.new(node_ramp.outputs["Color"], node_bsdf.inputs["Emission Color"])
    links.new(noise_out, node_bump.inputs["Height"])
    links.new(node_bump.outputs["Normal"], node_bsdf.inputs["Normal"])
    links.new(node_bsdf.outputs["BSDF"], node_out.inputs["Surface"])

    return mat


def create_meat_chunk_material() -> bpy.types.Material:
    """Create dark crimson, non-reflective rough jagged shader for meat/bone chunks."""
    mat = bpy.data.materials.new(name="MeatChunk_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_out.location = (500, 0)

    node_bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    node_bsdf.location = (200, 0)
    node_bsdf.inputs["Base Color"].default_value = (0.18, 0.01, 0.015, 1.0)
    node_bsdf.inputs["Roughness"].default_value = 0.88
    if "Specular IOR Level" in node_bsdf.inputs:
        node_bsdf.inputs["Specular IOR Level"].default_value = 0.15

    node_texcoord = nodes.new(type="ShaderNodeTexCoord")
    node_texcoord.location = (-500, 0)

    node_noise = nodes.new(type="ShaderNodeTexNoise")
    node_noise.location = (-280, 0)
    node_noise.noise_dimensions = "3D"
    node_noise.inputs["Scale"].default_value = 18.0
    node_noise.inputs["Detail"].default_value = 8.0
    node_noise.inputs["Roughness"].default_value = 0.85

    node_bump = nodes.new(type="ShaderNodeBump")
    node_bump.location = (-40, -120)
    node_bump.inputs["Strength"].default_value = 0.65
    node_bump.inputs["Distance"].default_value = 0.05

    noise_out = node_noise.outputs["Factor"] if "Factor" in node_noise.outputs else node_noise.outputs[0]
    links.new(node_texcoord.outputs["Object"], node_noise.inputs["Vector"])
    links.new(noise_out, node_bump.inputs["Height"])
    links.new(node_bump.outputs["Normal"], node_bsdf.inputs["Normal"])
    links.new(node_bsdf.outputs["BSDF"], node_out.inputs["Surface"])

    return mat


def create_acid_fizz_material() -> bpy.types.Material:
    """Create glowing green emissive material for Acid Fizz particles."""
    mat = bpy.data.materials.new(name="AcidFizz_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_out.location = (300, 0)

    node_bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    node_bsdf.location = (0, 0)
    node_bsdf.inputs["Base Color"].default_value = (0.2, 1.0, 0.1, 1.0)
    node_bsdf.inputs["Roughness"].default_value = 0.1
    if "Emission Color" in node_bsdf.inputs:
        node_bsdf.inputs["Emission Color"].default_value = (0.2, 1.0, 0.1, 1.0)
    if "Emission Strength" in node_bsdf.inputs:
        node_bsdf.inputs["Emission Strength"].default_value = 4.0

    links.new(node_bsdf.outputs["BSDF"], node_out.inputs["Surface"])
    return mat


def create_meat_chunks_collection(scene: bpy.types.Scene, mat: bpy.types.Material) -> bpy.types.Collection:
    """Create 4 jagged high-frequency displaced organic meat/bone chunks in MeatChunks collection."""
    meat_col = bpy.data.collections.new("MeatChunks")
    scene.collection.children.link(meat_col)

    chunk_scales = [
        (0.11, 0.06, 0.05),
        (0.08, 0.12, 0.06),
        (0.13, 0.05, 0.07),
        (0.09, 0.09, 0.05),
    ]

    for idx, sc in enumerate(chunk_scales):
        # Place template meshes far behind the top-down camera (Z=50) so only particle instances are seen
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=3,
            radius=1.0,
            location=(50.0 + idx * 2.0, 50.0, 50.0),
        )
        chunk = bpy.context.active_object
        chunk.name = f"MeatChunk_{idx + 1}"
        chunk.scale = sc
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

        # High-frequency displacement texture
        tex = bpy.data.textures.new(name=f"MeatNoise_{idx + 1}", type="VORONOI")
        tex.noise_scale = 0.18 + 0.04 * idx
        disp = chunk.modifiers.new(name="JaggedDisplace", type="DISPLACE")
        disp.texture = tex
        disp.strength = 0.045
        bpy.ops.object.modifier_apply(modifier="JaggedDisplace")

        chunk.data.materials.append(mat)

        # Move strictly into MeatChunks collection
        for c in list(chunk.users_collection):
            c.objects.unlink(chunk)
        meat_col.objects.link(chunk)

    meat_col.hide_viewport = True
    return meat_col


def create_particle_instance_meshes(
    scene: bpy.types.Scene,
    fizz_mat: bpy.types.Material,
    blood_mat: bpy.types.Material,
) -> tuple[bpy.types.Object, bpy.types.Object]:
    """Create template sphere objects for Acid Fizz and Mantaflow secondary spray droplets."""
    hidden_col = bpy.data.collections.new("HiddenTemplates")
    scene.collection.children.link(hidden_col)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.028, location=(55.0, 55.0, 50.0))
    fizz_sphere = bpy.context.active_object
    fizz_sphere.name = "AcidFizz_Sphere"
    fizz_sphere.data.materials.append(fizz_mat)
    for c in list(fizz_sphere.users_collection):
        c.objects.unlink(fizz_sphere)
    hidden_col.objects.link(fizz_sphere)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.032, location=(58.0, 55.0, 50.0))
    droplet_sphere = bpy.context.active_object
    droplet_sphere.name = "SprayDroplet_Sphere"
    droplet_sphere.data.materials.append(blood_mat)
    for c in list(droplet_sphere.users_collection):
        c.objects.unlink(droplet_sphere)
    hidden_col.objects.link(droplet_sphere)

    hidden_col.hide_viewport = True
    return fizz_sphere, droplet_sphere


def setup_emitters_and_domain(
    scene: bpy.types.Scene,
    cache_dir: str,
    blood_mat: bpy.types.Material,
    meat_col: bpy.types.Collection,
    fizz_sphere: bpy.types.Object,
    droplet_sphere: bpy.types.Object,
) -> bpy.types.Object:
    """Create central burst inflow, turbulence effector, meat/fizz emitters, and liquid domain."""
    # 1. Physics Core: Microgravity + Turbulence Effector
    scene.use_gravity = True
    scene.gravity = (0.0, 0.0, -0.5)

    bpy.ops.object.effector_add(type="TURBULENCE", location=(0.0, 0.0, 0.0))
    turb = bpy.context.active_object
    turb.name = "Gore_Turbulence"
    turb.field.strength = 8.5
    turb.field.flow = 0.5
    turb.field.noise = 1.0
    turb.field.size = 0.42
    turb.field.use_max_distance = True
    turb.field.distance_max = 1.35
    turb.field.falloff_power = 1.8

    # 2. Central Burst Inflow UV Sphere (frames 1..10 active, frame 11+ off)
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=32,
        ring_count=16,
        radius=0.28,
        location=(0.0, 0.0, 0.0),
    )
    inflow = bpy.context.active_object
    inflow.name = "Burst_Inflow_Sphere"
    inflow.hide_render = True

    # Displace UV sphere slightly so initial normal velocity shoots out in organic lobes/tendrils
    inflow_tex = bpy.data.textures.new(name="BurstLobeNoise", type="CLOUDS")
    inflow_tex.noise_scale = 0.22
    inflow_disp = inflow.modifiers.new(name="LobeDisplace", type="DISPLACE")
    inflow_disp.texture = inflow_tex
    inflow_disp.strength = 0.22
    bpy.ops.object.modifier_apply(modifier="LobeDisplace")

    flow_mod = inflow.modifiers.new(name="Fluid", type="FLUID")
    flow_mod.fluid_type = "FLOW"
    fs = flow_mod.flow_settings
    fs.flow_type = "LIQUID"
    fs.flow_behavior = "INFLOW"
    fs.use_initial_velocity = True
    fs.velocity_factor = 0.95
    fs.velocity_normal = 1.25
    fs.velocity_random = 1.1
    fs.subframes = 2

    # Keyframe rapid scale burst + chaotic spin on frames 1..10, and turn inflow off at frame 11
    scene.frame_set(1)
    inflow.scale = (0.32, 0.32, 0.32)
    inflow.rotation_euler = (0.0, 0.0, 0.0)
    inflow.keyframe_insert(data_path="scale", frame=1)
    inflow.keyframe_insert(data_path="rotation_euler", frame=1)
    fs.use_inflow = True
    fs.keyframe_insert(data_path="use_inflow", frame=1)

    scene.frame_set(5)
    inflow.scale = (0.95, 0.88, 0.82)
    inflow.rotation_euler = (1.1, -0.9, 1.3)
    inflow.keyframe_insert(data_path="scale", frame=5)
    inflow.keyframe_insert(data_path="rotation_euler", frame=5)

    scene.frame_set(10)
    inflow.scale = (0.45, 0.50, 0.42)
    inflow.rotation_euler = (2.1, 1.5, -1.8)
    inflow.keyframe_insert(data_path="scale", frame=10)
    inflow.keyframe_insert(data_path="rotation_euler", frame=10)
    fs.use_inflow = True
    fs.keyframe_insert(data_path="use_inflow", frame=10)

    scene.frame_set(11)
    fs.use_inflow = False
    fs.keyframe_insert(data_path="use_inflow", frame=11)
    scene.frame_set(1)

    # 3. Meat Chunks & Acid Fizz Particle Emitters
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.20, location=(0.0, 0.0, 0.0))
    p_emitter = bpy.context.active_object
    p_emitter.name = "Gore_Particle_Emitter"
    p_emitter.show_instancer_for_render = False
    p_emitter.show_instancer_for_viewport = False

    # 3a. Meat Chunks Particle System (COLLECTION -> MeatChunks)
    chunk_mod = p_emitter.modifiers.new(name="MeatChunks_Particles", type="PARTICLE_SYSTEM")
    ps_chunk = chunk_mod.particle_system.settings
    ps_chunk.count = 28
    ps_chunk.frame_start = 1.0
    ps_chunk.frame_end = 8.0
    ps_chunk.lifetime = 64.0
    ps_chunk.emit_from = "FACE"
    ps_chunk.normal_factor = 1.65
    ps_chunk.factor_random = 1.15
    ps_chunk.angular_velocity_mode = "RAND"
    ps_chunk.angular_velocity_factor = 4.5
    ps_chunk.use_rotations = True
    ps_chunk.use_dynamic_rotation = True
    ps_chunk.rotation_mode = "VEL"
    ps_chunk.rotation_factor_random = 1.0
    ps_chunk.phase_factor_random = 1.0
    ps_chunk.drag_factor = 0.48
    ps_chunk.damping = 0.52
    ps_chunk.brownian_factor = 0.5
    ps_chunk.render_type = "COLLECTION"
    ps_chunk.instance_collection = meat_col
    ps_chunk.use_collection_pick_random = True
    ps_chunk.particle_size = 0.85
    ps_chunk.size_random = 0.55

    # 3b. Acid Fizz Particle System (OBJECT -> AcidFizz_Sphere)
    fizz_mod = p_emitter.modifiers.new(name="AcidFizz_Particles", type="PARTICLE_SYSTEM")
    ps_fizz = fizz_mod.particle_system.settings
    ps_fizz.count = 95
    ps_fizz.frame_start = 1.0
    ps_fizz.frame_end = 14.0
    ps_fizz.lifetime = 56.0
    ps_fizz.lifetime_random = 0.35
    ps_fizz.emit_from = "VOLUME"
    ps_fizz.normal_factor = 1.8
    ps_fizz.factor_random = 1.4
    ps_fizz.brownian_factor = 3.2
    ps_fizz.drag_factor = 0.52
    ps_fizz.damping = 0.55
    ps_fizz.render_type = "OBJECT"
    ps_fizz.instance_object = fizz_sphere
    ps_fizz.particle_size = 0.95
    ps_fizz.size_random = 0.65

    # 4. Mantaflow Liquid Domain (resolution_max = 96, frames 1..64)
    bpy.ops.mesh.primitive_cube_add(size=5.0, location=(0.0, 0.0, 0.0))
    domain = bpy.context.active_object
    domain.name = "AlienGore_Domain"

    d_mod = domain.modifiers.new(name="Fluid", type="FLUID")
    d_mod.fluid_type = "DOMAIN"
    ds = d_mod.domain_settings
    ds.domain_type = "LIQUID"
    ds.resolution_max = 96
    ds.time_scale = 0.95

    # Open domain borders so filaments never flatten against invisible box walls
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

    # Diffusion / Viscosity / Surface Tension (verified on Blender 5.3 FluidDomainSettings)
    ds.use_diffusion = True
    if hasattr(ds, "viscosity_base"):
        ds.viscosity_base = 15.0
    if hasattr(ds, "viscosity_exponent"):
        ds.viscosity_exponent = 3
    if hasattr(ds, "surface_tension"):
        ds.surface_tension = 0.0025

    # Liquid Mesh (mesh_scale = 2, particle_radius = 1.1)
    ds.use_mesh = True
    if hasattr(ds, "mesh_scale"):
        ds.mesh_scale = 2
    if hasattr(ds, "upres_factor"):
        ds.upres_factor = 2
    ds.particle_radius = 1.1

    # Secondary Particles (Spray, Bubble, Foam)
    ds.use_spray_particles = True
    ds.use_bubble_particles = True
    ds.use_foam_particles = True

    ds.cache_type = "ALL"
    ds.cache_frame_start = 1
    ds.cache_frame_end = 64
    ds.cache_directory = cache_dir

    domain.data.materials.append(blood_mat)

    # Configure Mantaflow secondary particle systems on domain to render droplet instances
    for mod in domain.modifiers:
        if mod.type == "PARTICLE_SYSTEM":
            ps = mod.particle_system.settings
            if "Liquid" in mod.name or ps.type == "FLIP":
                mod.show_render = False
                mod.show_viewport = False
            else:
                mod.show_render = True
                ps.render_type = "OBJECT"
                ps.instance_object = droplet_sphere
                ps.particle_size = 0.55
                ps.size_random = 0.65

    return domain


def setup_camera_and_lighting(scene: bpy.types.Scene) -> bpy.types.Object:
    """Configure BLENDER_EEVEE 256x256 RGBA motion-blurred render, studio rim/key lights, and top-down ortho camera."""
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.use_motion_blur = True
    if hasattr(scene.render, "motion_blur_shutter"):
        scene.render.motion_blur_shutter = 0.35
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"

    # Key Sun Light (angled from upper-left to sculpt wet specular highlights without washing out colors)
    sun_data = bpy.data.lights.new(name="Studio_Key_Sun", type="SUN")
    sun_data.energy = 2.2
    sun_data.color = (1.0, 0.98, 0.95)
    sun_obj = bpy.data.objects.new(name="Studio_Key_Sun", object_data=sun_data)
    scene.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(32.0), math.radians(-28.0), math.radians(25.0))

    # Rim Area Light 1 (grazing green-white rim light from +X/-Y)
    rim1_data = bpy.data.lights.new(name="Studio_Rim_Area_1", type="AREA")
    rim1_data.energy = 42.0
    rim1_data.color = (0.65, 1.0, 0.55)
    rim1_data.size = 3.5
    rim1_obj = bpy.data.objects.new(name="Studio_Rim_Area_1", object_data=rim1_data)
    scene.collection.objects.link(rim1_obj)
    rim1_obj.location = (2.8, -2.8, 1.4)
    rim1_obj.rotation_euler = (math.radians(65.0), 0.0, math.radians(45.0))

    # Rim Area Light 2 (warm crimson-gold counter rim light from -X/+Y)
    rim2_data = bpy.data.lights.new(name="Studio_Rim_Area_2", type="AREA")
    rim2_data.energy = 32.0
    rim2_data.color = (1.0, 0.45, 0.35)
    rim2_data.size = 3.5
    rim2_obj = bpy.data.objects.new(name="Studio_Rim_Area_2", object_data=rim2_data)
    scene.collection.objects.link(rim2_obj)
    rim2_obj.location = (-2.8, 2.8, 1.4)
    rim2_obj.rotation_euler = (math.radians(65.0), 0.0, math.radians(-135.0))

    # Top Specular Point Light near camera for wet specular glints
    pt_data = bpy.data.lights.new(name="Studio_Spec_Point", type="POINT")
    pt_data.energy = 28.0
    pt_data.color = (1.0, 1.0, 1.0)
    pt_obj = bpy.data.objects.new(name="Studio_Spec_Point", object_data=pt_data)
    scene.collection.objects.link(pt_obj)
    pt_obj.location = (0.6, -0.6, 3.6)

    # Orthographic Top-Down Camera at (0, 0, 5) looking straight down (-Z)
    cam_data = bpy.data.cameras.new(name="TopDown_Ortho_Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 4.6
    cam_data.clip_start = 0.1
    cam_data.clip_end = 25.0
    cam_obj = bpy.data.objects.new(name="TopDown_Ortho_Camera", object_data=cam_data)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (0.0, 0.0, 5.0)
    cam_obj.rotation_euler = (0.0, 0.0, 0.0)
    scene.camera = cam_obj

    return cam_obj


def calibrate_ortho_scale(scene: bpy.types.Scene, domain: bpy.types.Object, cam_obj: bpy.types.Object) -> None:
    """Tune ortho_scale after fluid bake so the liquid burst fills the frame without clipping."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    max_extent: float = 0.0
    for f_idx in range(1, 65):
        scene.frame_set(f_idx)
        eval_dom = domain.evaluated_get(depsgraph)
        verts = eval_dom.data.vertices
        if len(verts) <= 8:
            continue
        frame_max = max(max(abs(v.co.x), abs(v.co.y)) for v in verts)
        max_extent = max(max_extent, frame_max)

    scene.frame_set(1)
    if max_extent > 0.2:
        # Full width is 2 * max_extent; add 25% margin so burst and secondary droplets fit inside frame
        tuned_scale = max(4.2, min(5.8, max_extent * 2.0 * 1.25))
        cam_obj.data.ortho_scale = tuned_scale
        log(f"Calibrated top-down ortho_scale = {tuned_scale:.2f}m (max liquid half-extent = {max_extent:.2f}m)")


def stitch_rgba_atlas(frames_dir: str, output_png_path: str) -> None:
    """Stitch 64 256x256 RGBA frames into an 8x8 (2048x2048) RGBA PNG preserving true alpha."""
    py_code = """
import glob
import os
import sys
from PIL import Image

frames_dir = sys.argv[1]
output_png_path = sys.argv[2]

frames = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
if len(frames) < 64:
    raise RuntimeError(f"Expected 64 frames in {frames_dir}, found {len(frames)}")

sheet = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
for idx, path in enumerate(frames[:64]):
    im = Image.open(path).convert("RGBA")
    if im.size != (256, 256):
        im = im.resize((256, 256), Image.Resampling.LANCZOS)
    row = idx // 8
    col = idx % 8
    sheet.paste(im, (col * 256, row * 256))

os.makedirs(os.path.dirname(os.path.abspath(output_png_path)), exist_ok=True)
sheet.save(output_png_path, format="PNG")
print(f"Saved 2048x2048 RGBA atlas (8x8) to {output_png_path}")
"""
    project_root = Path(__file__).resolve().parent.parent.parent
    venv_py = project_root / ".venv" / "bin" / "python"
    py_exe = str(venv_py) if venv_py.exists() else "python3"
    subprocess.run([py_exe, "-c", py_code, frames_dir, output_png_path], check=True)


def generate_alien_gore_flipbook(output_png_path: str) -> None:
    """Run full headless Blender 5.x Mantaflow liquid gore simulation, EEVEE render, and 8x8 packing."""
    work_dir = tempfile.mkdtemp(prefix="alien_gore_flipbook_")
    cache_dir = os.path.join(work_dir, "cache")
    frames_dir = os.path.join(work_dir, "frames")
    os.makedirs(cache_dir, exist_ok=True)
    os.makedirs(frames_dir, exist_ok=True)

    try:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.frame_start = 1
        scene.frame_end = 64
        scene.render.fps = 60
        scene.render.filepath = os.path.join(frames_dir, "frame_")

        log("Creating materials, meat chunk meshes, and particle templates...")
        blood_mat = create_blood_material()
        meat_mat = create_meat_chunk_material()
        fizz_mat = create_acid_fizz_material()

        meat_col = create_meat_chunks_collection(scene, meat_mat)
        fizz_sphere, droplet_sphere = create_particle_instance_meshes(scene, fizz_mat, blood_mat)

        log("Configuring microgravity physics, turbulence, inflow, emitters, and liquid domain...")
        domain = setup_emitters_and_domain(
            scene,
            cache_dir,
            blood_mat,
            meat_col,
            fizz_sphere,
            droplet_sphere,
        )
        cam_obj = setup_camera_and_lighting(scene)

        bpy.context.view_layer.objects.active = domain
        domain.select_set(True)

        blend_path = os.path.join(work_dir, "alien_gore_scene.blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)

        log("Baking Mantaflow liquid simulation & secondary particles (frames 1..64)...")
        bpy.ops.fluid.bake_all()
        log("Mantaflow bake complete.")

        calibrate_ortho_scale(scene, domain, cam_obj)

        # Warm up particle caches sequentially across frames 1..64 before rendering
        for f_idx in range(1, 65):
            scene.frame_set(f_idx)
        scene.frame_set(1)

        log("Rendering 64 frames (256x256 RGBA, BLENDER_EEVEE, motion blur)...")
        bpy.ops.render.render(animation=True)
        log("Render complete.")

        log("Stitching 64 frames into 8x8 (2048x2048) RGBA flipbook atlas...")
        stitch_rgba_atlas(frames_dir, output_png_path)
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parent.parent.parent
    default_out = str(repo_root / "assets" / "vfx" / "green_blood_atlas.png")
    target_out = default_out
    if "--" in sys.argv:
        extra = sys.argv[sys.argv.index("--") + 1 :]
        if extra:
            target_out = extra[0]
    generate_alien_gore_flipbook(target_out)
