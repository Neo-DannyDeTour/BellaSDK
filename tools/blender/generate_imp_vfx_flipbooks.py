"""Headless Blender 5.x Mantaflow + lightning VFX flipbook generator for the Imp enemy.

Generates two 8x8 (2048x2048, 256x256 per cell) transparent RGBA sprite sheets:
1. vfx/imp/imp_mantaflow_explosion_flipbook.png — Mantaflow fire+smoke plasma explosion burst
   with crackling electric arc filaments.
2. vfx/imp/imp_lightning_flipbook.png — Branching electric charge arcs and plasma sparks.

Usage:
    /snap/bin/blender -b -P tools/blender/generate_imp_vfx_flipbooks.py
"""

import glob
import math
import os
import random
import shutil
import subprocess
import tempfile
import bpy


REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR: str = os.path.join(REPO_ROOT, "vfx", "imp")
EXPLOSION_PNG: str = os.path.join(OUT_DIR, "imp_mantaflow_explosion_flipbook.png")
LIGHTNING_PNG: str = os.path.join(OUT_DIR, "imp_lightning_flipbook.png")


def _configure_render(scene: bpy.types.Scene, frame_dir: str, frames: int = 64) -> None:
    """Configure EEVEE 256x256 RGBA transparent render settings."""
    scene.frame_start = 1
    scene.frame_end = frames
    scene.render.fps = 60
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.filepath = os.path.join(frame_dir, "frame_")


def _add_ortho_camera(
    scene: bpy.types.Scene,
    location: tuple[float, float, float],
    ortho_scale: float,
) -> None:
    """Add an orthographic front camera looking along +Y."""
    bpy.ops.object.camera_add(
        location=location,
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    cam = bpy.context.active_object
    cam.name = "VFX_Ortho_Camera"
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho_scale
    scene.camera = cam


def _make_emission_material(
    name: str,
    color: tuple[float, float, float, float],
    strength: float,
) -> bpy.types.Material:
    """Create a pure unlit emission material for electric arcs and sparks."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    emit_node = nodes.new(type="ShaderNodeEmission")
    emit_node.inputs["Color"].default_value = color
    emit_node.inputs["Strength"].default_value = strength
    links.new(emit_node.outputs["Emission"], out_node.inputs["Surface"])
    return mat


def _build_arc_curve(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    segments: int,
    jitter: float,
    bevel_depth: float,
    rng: random.Random,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    """Create a jagged 3D polyline curve representing a lightning bolt segment."""
    curve_data = bpy.data.curves.new(name=name, type="CURVE")
    curve_data.dimensions = "3D"
    curve_data.bevel_depth = bevel_depth
    curve_data.bevel_resolution = 1

    spline = curve_data.splines.new("POLY")
    spline.points.add(segments)

    for i in range(segments + 1):
        t = i / float(segments)
        envelope = math.sin(t * math.pi)
        px = start[0] + (end[0] - start[0]) * t + rng.uniform(-jitter, jitter) * envelope
        py = start[1] + (end[1] - start[1]) * t + rng.uniform(-jitter, jitter) * envelope
        pz = start[2] + (end[2] - start[2]) * t + rng.uniform(-jitter, jitter) * envelope
        spline.points[i].co = (px, py, pz, 1.0)

    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def _stitch_8x8_rgba(frame_dir: str, target_png: str) -> None:
    """Stitch 64 rendered 256x256 RGBA frames into a 2048x2048 8x8 flipbook PNG.

    Uses system python3 Pillow so emissive RGB luminance cleanly drives alpha
    while preserving any existing volume alpha, ensuring a 100% transparent
    background.
    """
    os.makedirs(os.path.dirname(os.path.abspath(target_png)), exist_ok=True)
    script = f"""
import glob, os
from PIL import Image

frames = sorted(glob.glob({frame_dir!r} + "/frame_*.png"))
if len(frames) < 64:
    raise RuntimeError(f"Expected 64 frames in {frame_dir!r}, found {{len(frames)}}")

sheet = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
for idx, path in enumerate(frames[:64]):
    im = Image.open(path).convert("RGBA")
    r, g, b, a = im.split()
    rp, gp, bp, ap = r.load(), g.load(), b.load(), a.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            lum = max(rp[x, y], gp[x, y], bp[x, y])
            ap[x, y] = max(ap[x, y], lum)
    merged = Image.merge("RGBA", (r, g, b, a))
    row = idx // 8
    col = idx % 8
    sheet.paste(merged, (col * 256, row * 256))

sheet.save({target_png!r})
print(f"Saved 8x8 RGBA flipbook: {target_png!r} ({{sheet.size[0]}}x{{sheet.size[1]}})")
"""
    subprocess.run(["python3", "-c", script], check=True)


def generate_explosion_flipbook(work_dir: str) -> None:
    """Bake Mantaflow fire+smoke plasma explosion + electric arcs into 8x8 flipbook."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    _configure_render(scene, work_dir, frames=64)

    # Burst emitter sphere at center of domain (hidden from final render)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.22, location=(0.0, 0.0, 1.0))
    emitter = bpy.context.active_object
    emitter.name = "Plasma_Emitter"
    emitter.hide_render = True

    p_mod = emitter.modifiers.new(name="Burst_Particles", type="PARTICLE_SYSTEM")
    ps = p_mod.particle_system.settings
    ps.count = 40
    ps.frame_start = 1
    ps.frame_end = 4
    ps.lifetime = 10
    ps.normal_factor = 2.4
    ps.factor_random = 0.8
    ps.physics_type = "NEWTON"
    ps.effector_weights.gravity = 0.0
    ps.render_type = "NONE"

    flow_mod = emitter.modifiers.new(name="Fluid_Flow", type="FLUID")
    flow_mod.fluid_type = "FLOW"
    fs = flow_mod.flow_settings
    fs.flow_type = "BOTH"
    fs.flow_behavior = "INFLOW"
    fs.flow_source = "PARTICLES"
    fs.particle_system = p_mod.particle_system
    fs.fuel_amount = 2.4
    fs.smoke_color = (0.35, 0.55, 0.85)
    fs.use_initial_velocity = True
    fs.velocity_factor = 1.2

    # Keyframe inflow off after frame 6 so it forms a discrete burst
    fs.use_inflow = True
    fs.keyframe_insert(data_path="use_inflow", frame=1)
    fs.use_inflow = False
    fs.keyframe_insert(data_path="use_inflow", frame=7)

    # Mantaflow Gas Domain
    bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.0, 1.25), scale=(1.4, 1.4, 1.4))
    domain = bpy.context.active_object
    domain.name = "Explosion_Domain"

    d_mod = domain.modifiers.new(name="Fluid_Domain", type="FLUID")
    d_mod.fluid_type = "DOMAIN"
    ds = d_mod.domain_settings
    ds.domain_type = "GAS"
    ds.resolution_max = 64
    ds.time_scale = 0.95
    ds.alpha = 0.15
    ds.beta = 0.6
    ds.vorticity = 1.8
    ds.use_dissolve_smoke = True
    ds.dissolve_speed = 34
    ds.use_dissolve_smoke_log = True
    ds.use_adaptive_domain = True
    ds.cache_type = "ALL"
    ds.cache_frame_start = 1
    ds.cache_frame_end = 64

    cache_dir = os.path.join(work_dir, "cache_explosion")
    os.makedirs(cache_dir, exist_ok=True)
    ds.cache_directory = cache_dir

    # Volumetric plasma + smoke material driven by flame + density
    mat = bpy.data.materials.new(name="Plasma_Volume_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_vol = nodes.new(type="ShaderNodeVolumePrincipled")
    node_vol.inputs["Density"].default_value = 0.0
    node_vol.inputs["Color"].default_value = (0.28, 0.42, 0.65, 1.0)
    node_vol.inputs["Absorption Color"].default_value = (0.15, 0.25, 0.45, 1.0)

    attr_density = nodes.new(type="ShaderNodeAttribute")
    attr_density.attribute_name = "density"

    attr_flame = nodes.new(type="ShaderNodeAttribute")
    attr_flame.attribute_name = "flame"

    # Density -> volume density * 2.2
    dens_mult = nodes.new(type="ShaderNodeMath")
    dens_mult.operation = "MULTIPLY"
    dens_mult.inputs[1].default_value = 2.2
    links.new(attr_density.outputs["Fac"], dens_mult.inputs[0])
    links.new(dens_mult.outputs["Value"], node_vol.inputs["Density"])

    # Flame -> bright electric cyan/white emission, plus subtle smoke self-glow
    flame_mult = nodes.new(type="ShaderNodeMath")
    flame_mult.operation = "MULTIPLY"
    flame_mult.inputs[1].default_value = 10.0
    links.new(attr_flame.outputs["Fac"], flame_mult.inputs[0])

    smoke_glow = nodes.new(type="ShaderNodeMath")
    smoke_glow.operation = "MULTIPLY"
    smoke_glow.inputs[1].default_value = 1.4
    links.new(attr_density.outputs["Fac"], smoke_glow.inputs[0])

    emit_sum = nodes.new(type="ShaderNodeMath")
    emit_sum.operation = "ADD"
    links.new(flame_mult.outputs["Value"], emit_sum.inputs[0])
    links.new(smoke_glow.outputs["Value"], emit_sum.inputs[1])
    links.new(emit_sum.outputs["Value"], node_vol.inputs["Emission Strength"])

    # Color ramp from cool blue-smoke to electric cyan-white plasma core
    ramp = nodes.new(type="ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.25, 0.48, 0.85, 1.0)
    elem_mid = ramp.color_ramp.elements.new(0.35)
    elem_mid.color = (0.25, 0.85, 1.0, 1.0)
    ramp.color_ramp.elements[-1].position = 0.85
    ramp.color_ramp.elements[-1].color = (0.92, 0.98, 1.0, 1.0)
    links.new(attr_flame.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], node_vol.inputs["Emission Color"])

    links.new(node_vol.outputs["Volume"], node_out.inputs["Volume"])
    domain.data.materials.append(mat)

    # Add crackling electric arc filaments visible during initial explosion frames (1..22)
    arc_mat = _make_emission_material("Explosion_Arc_Mat", (0.45, 0.92, 1.0, 1.0), 12.0)
    rng = random.Random(42)
    for arc_idx in range(10):
        angle = (arc_idx / 10.0) * math.tau + rng.uniform(-0.2, 0.2)
        elev = rng.uniform(-0.45, 0.55)
        r_end = rng.uniform(0.65, 1.05)
        end_pt = (
            math.cos(angle) * r_end,
            math.sin(angle) * 0.25,
            1.0 + math.sin(angle) * r_end * 0.7 + elev * 0.5,
        )
        arc = _build_arc_curve(
            f"Expl_Arc_{arc_idx}",
            (0.0, 0.0, 1.0),
            end_pt,
            segments=7,
            jitter=0.14,
            bevel_depth=0.014,
            rng=rng,
            mat=arc_mat,
        )
        start_f = 1 + (arc_idx % 4)
        end_f = start_f + rng.randint(5, 10)
        arc.hide_render = True
        arc.keyframe_insert(data_path="hide_render", frame=1)
        arc.hide_render = False
        arc.keyframe_insert(data_path="hide_render", frame=start_f)
        arc.hide_render = True
        arc.keyframe_insert(data_path="hide_render", frame=end_f)

    _add_ortho_camera(scene, location=(0.0, -4.5, 1.25), ortho_scale=3.8)

    bpy.context.view_layer.objects.active = domain
    domain.select_set(True)

    blend_path = os.path.join(work_dir, "imp_explosion.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)

    print("[generate_imp_vfx_flipbooks] Baking Mantaflow explosion simulation...")
    bpy.ops.fluid.bake_all()
    print("[generate_imp_vfx_flipbooks] Rendering 64 explosion frames...")
    bpy.ops.render.render(animation=True)
    _stitch_8x8_rgba(work_dir, EXPLOSION_PNG)


def generate_lightning_flipbook(work_dir: str) -> None:
    """Render 64 frames of crackling electric charge arcs and sparks into 8x8 flipbook."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    _configure_render(scene, work_dir, frames=64)

    core_mat = _make_emission_material("Charge_Core_Mat", (0.85, 0.97, 1.0, 1.0), 14.0)
    arc_mat_bright = _make_emission_material("Charge_Arc_Bright", (0.35, 0.88, 1.0, 1.0), 10.0)
    arc_mat_outer = _make_emission_material("Charge_Arc_Outer", (0.18, 0.45, 1.0, 1.0), 6.0)

    # Pulsing central plasma orb
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.18, location=(0.0, 0.0, 0.0))
    core = bpy.context.active_object
    core.name = "Charge_Core"
    core.data.materials.append(core_mat)
    for f in range(1, 65, 2):
        pulse = 0.75 + 0.45 * math.sin(f * 0.45) + 0.15 * math.cos(f * 1.3)
        core.scale = (pulse, pulse, pulse)
        core.keyframe_insert(data_path="scale", frame=f)

    # Generate crackling radial arcs that flicker on/off every 2-4 frames
    rng = random.Random(1337)
    for frame_group in range(0, 64, 2):
        f_start = frame_group + 1
        f_end = min(65, f_start + 2)
        num_arcs = 5
        for a_idx in range(num_arcs):
            angle = rng.uniform(0.0, math.tau)
            r_in = rng.uniform(0.12, 0.25)
            r_out = rng.uniform(0.75, 1.18)
            start_pt = (math.cos(angle) * r_in, 0.0, math.sin(angle) * r_in)
            end_pt = (
                math.cos(angle + rng.uniform(-0.4, 0.4)) * r_out,
                rng.uniform(-0.15, 0.15),
                math.sin(angle + rng.uniform(-0.4, 0.4)) * r_out,
            )
            mat = arc_mat_bright if a_idx % 2 == 0 else arc_mat_outer
            arc = _build_arc_curve(
                f"Bolt_{frame_group}_{a_idx}",
                start_pt,
                end_pt,
                segments=8,
                jitter=0.16,
                bevel_depth=0.012 if a_idx % 2 == 0 else 0.008,
                rng=rng,
                mat=mat,
            )
            arc.hide_render = True
            arc.keyframe_insert(data_path="hide_render", frame=1)
            arc.hide_render = False
            arc.keyframe_insert(data_path="hide_render", frame=f_start)
            arc.hide_render = True
            arc.keyframe_insert(data_path="hide_render", frame=f_end)

            # Secondary fork branch
            if a_idx < 3:
                mid_pt = (
                    (start_pt[0] + end_pt[0]) * 0.5 + rng.uniform(-0.1, 0.1),
                    0.0,
                    (start_pt[2] + end_pt[2]) * 0.5 + rng.uniform(-0.1, 0.1),
                )
                fork_angle = angle + rng.choice([-0.55, 0.55])
                fork_end = (
                    mid_pt[0] + math.cos(fork_angle) * 0.42,
                    0.0,
                    mid_pt[2] + math.sin(fork_angle) * 0.42,
                )
                fork = _build_arc_curve(
                    f"Fork_{frame_group}_{a_idx}",
                    mid_pt,
                    fork_end,
                    segments=5,
                    jitter=0.1,
                    bevel_depth=0.007,
                    rng=rng,
                    mat=arc_mat_outer,
                )
                fork.hide_render = True
                fork.keyframe_insert(data_path="hide_render", frame=1)
                fork.hide_render = False
                fork.keyframe_insert(data_path="hide_render", frame=f_start)
                fork.hide_render = True
                fork.keyframe_insert(data_path="hide_render", frame=f_end)

    # Orbiting spark motes
    for s_idx in range(12):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.025, location=(0.0, 0.0, 0.0))
        spark = bpy.context.active_object
        spark.name = f"Spark_{s_idx}"
        spark.data.materials.append(core_mat)
        base_ang = (s_idx / 12.0) * math.tau
        speed = rng.uniform(0.14, 0.28) * (1.0 if s_idx % 2 == 0 else -1.0)
        rad = rng.uniform(0.35, 0.95)
        for f in range(1, 65, 4):
            ang = base_ang + f * speed
            r_cur = rad * (0.7 + 0.35 * math.sin(f * 0.2 + s_idx))
            spark.location = (math.cos(ang) * r_cur, 0.0, math.sin(ang) * r_cur)
            spark.keyframe_insert(data_path="location", frame=f)

    _add_ortho_camera(scene, location=(0.0, -4.0, 0.0), ortho_scale=2.5)

    print("[generate_imp_vfx_flipbooks] Rendering 64 lightning charge frames...")
    bpy.ops.render.render(animation=True)
    _stitch_8x8_rgba(work_dir, LIGHTNING_PNG)


def main() -> None:
    """Run both flipbook generation pipelines inside temporary working directories."""
    os.makedirs(OUT_DIR, exist_ok=True)
    expl_dir = tempfile.mkdtemp(prefix="imp_mantaflow_expl_")
    bolt_dir = tempfile.mkdtemp(prefix="imp_lightning_charge_")
    try:
        generate_explosion_flipbook(expl_dir)
        generate_lightning_flipbook(bolt_dir)
    finally:
        shutil.rmtree(expl_dir, ignore_errors=True)
        shutil.rmtree(bolt_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
