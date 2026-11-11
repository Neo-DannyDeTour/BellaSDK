"""Headless Blender 5.x Mantaflow ceiling dust plume simulation and 8x8 flipbook generator.

Bakes a 64-frame gas simulation with top downward emitter and bottom floor collision.
Stitches 256x256 rendered frames into a 2048x2048 RGBA flipbook texture atlas.
"""

import os
import sys
import glob
import math
import tempfile
import bpy


def generate_ceiling_dust_flipbook(output_dir: str, target_png_path: str) -> None:
    # 1. Reset scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # 2. Timing and Resolution
    scene.frame_start = 1
    scene.frame_end = 64
    scene.render.fps = 60
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.render.filepath = os.path.join(output_dir, "frame_")

    # 3. Create Emitter (Circle facing downward at top of domain)
    # Rotation 180 deg around X so normal points downward (-Z)
    bpy.ops.mesh.primitive_circle_add(
        vertices=32,
        radius=0.25,
        fill_type='NGON',
        location=(0.0, 0.0, 2.7),
        rotation=(math.pi, 0.0, 0.0)
    )
    emitter = bpy.context.active_object
    emitter.name = "Ceiling_Emitter"

    # Particle system for downward impulse burst
    p_mod = emitter.modifiers.new(name="Dust_Particles", type='PARTICLE_SYSTEM')
    ps = p_mod.particle_system.settings
    ps.count = 45
    ps.frame_start = 1
    ps.frame_end = 1
    ps.lifetime = 10
    ps.normal_factor = 6.5
    ps.factor_random = 0.35
    ps.physics_type = 'NEWTON'
    ps.render_type = 'NONE'

    # Fluid Flow modifier
    flow_mod = emitter.modifiers.new(name="Fluid_Flow", type='FLUID')
    flow_mod.fluid_type = 'FLOW'
    fs = flow_mod.flow_settings
    fs.flow_type = 'SMOKE'
    fs.flow_behavior = 'INFLOW'
    fs.flow_source = 'PARTICLES'
    fs.particle_system = p_mod.particle_system
    fs.use_initial_velocity = True
    fs.velocity_factor = 1.0

    # 4. Mantaflow Gas Domain
    # Domain: Z from 0.0 to 3.0, center at (0, 0, 1.5)
    bpy.ops.mesh.primitive_cube_add(
        location=(0.0, 0.0, 1.5),
        scale=(1.4, 1.4, 1.5)
    )
    domain = bpy.context.active_object
    domain.name = "Ceiling_Dust_Domain"

    d_mod = domain.modifiers.new(name="Fluid_Domain", type='FLUID')
    d_mod.fluid_type = 'DOMAIN'
    ds = d_mod.domain_settings
    ds.domain_type = 'GAS'
    ds.resolution_max = 80
    ds.time_scale = 1.1
    ds.alpha = -0.15 # Slight negative buoyancy: dust settles
    ds.beta = 0.0    # Neutral temperature: no rising heat
    ds.vorticity = 2.2 # Turbulence as plume mushrooms on floor
    ds.use_collision_border_bottom = True # Floor barrier
    ds.use_dissolve_smoke = True
    ds.dissolve_speed = 35
    ds.use_dissolve_smoke_log = True
    ds.use_adaptive_domain = False
    ds.cache_type = 'ALL'
    ds.cache_frame_start = 1
    ds.cache_frame_end = 64

    cache_dir = os.path.join(output_dir, "cache")
    os.makedirs(cache_dir, exist_ok=True)
    ds.cache_directory = cache_dir

    # 5. Volumetric Material (Unlit density emission)
    mat = bpy.data.materials.new(name="Dust_Volume_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_out.location = (400, 0)

    node_volume = nodes.new(type="ShaderNodeVolumePrincipled")
    node_volume.location = (100, 0)
    node_volume.inputs["Density"].default_value = 0.0
    node_volume.inputs["Absorption Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    node_volume.inputs["Emission Color"].default_value = (1.0, 1.0, 1.0, 1.0)

    node_attr = nodes.new(type="ShaderNodeAttribute")
    node_attr.location = (-300, 0)
    node_attr.attribute_name = "density"

    node_mult = nodes.new(type="ShaderNodeMath")
    node_mult.location = (-100, 0)
    node_mult.operation = 'MULTIPLY'
    node_mult.inputs[1].default_value = 4.5

    links.new(node_attr.outputs["Fac"], node_mult.inputs[0])
    links.new(node_mult.outputs["Value"], node_volume.inputs["Emission Strength"])
    links.new(node_volume.outputs["Volume"], node_out.inputs["Volume"])

    domain.data.materials.append(mat)

    # 6. Orthographic Camera
    bpy.ops.object.camera_add(
        location=(0.0, -5.0, 1.4),
        rotation=(math.pi / 2.0, 0.0, 0.0)
    )
    cam = bpy.context.active_object
    cam.name = "Front_Ortho_Camera"
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 3.2
    scene.camera = cam

    # Active domain for bake
    bpy.context.view_layer.objects.active = domain
    domain.select_set(True)

    blend_path = os.path.join(output_dir, "ceiling_dust.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)

    print("Beginning Mantaflow ceiling dust bake...")
    bpy.ops.fluid.bake_all()
    print("Mantaflow bake complete.")

    print("Rendering 64 frames...")
    bpy.ops.render.render(animation=True)
    print("Frame render complete.")

    # 7. Stitch into 8x8 atlas
    stitch_atlas(output_dir, target_png_path)


def stitch_atlas(directory: str, target_png_path: str) -> None:
    try:
        from PIL import Image
    except ImportError:
        import subprocess
        # Fall back to host system python3 if Blender python lacks PIL
        cmd = [
            "python3", "-c",
            f"""
import os, glob
from PIL import Image
frames = sorted(glob.glob('{directory}/frame_*.png'))
sheet = Image.new('RGBA', (2048, 2048), (0, 0, 0, 0))
for idx, path in enumerate(frames[:64]):
    im = Image.open(path).convert('RGBA')
    r, g, b, _ = im.split()
    remapped = Image.merge('RGBA', (r, g, b, r))
    row = idx // 8
    col = idx % 8
    sheet.paste(remapped, (col * 256, row * 256))
os.makedirs(os.path.dirname('{target_png_path}'), exist_ok=True)
sheet.save('{target_png_path}')
print('Packed 8x8 flipbook via system python: {target_png_path}')
"""
        ]
        subprocess.run(cmd, check=True)
        return

    frames = sorted(glob.glob(os.path.join(directory, "frame_*.png")))
    if len(frames) < 64:
        print(f"Warning: expected 64 frames, found {len(frames)}")

    sheet = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
    for idx, path in enumerate(frames[:64]):
        im = Image.open(path).convert("RGBA")
        r, g, b, _ = im.split()
        remapped = Image.merge("RGBA", (r, g, b, r))
        row = idx // 8
        col = idx % 8
        sheet.paste(remapped, (col * 256, row * 256))

    os.makedirs(os.path.dirname(os.path.abspath(target_png_path)), exist_ok=True)
    sheet.save(target_png_path)
    print(f"Packed 8x8 flipbook successfully saved to {target_png_path}")


if __name__ == "__main__":
    work_dir = tempfile.mkdtemp(prefix="mantaflow_ceiling_dust_")
    out_file = "/home/dkd/Documents/BellaSDK/vfx/ceiling_dust/ceiling_dust_flipbook_8x8.png"
    generate_ceiling_dust_flipbook(work_dir, out_file)
