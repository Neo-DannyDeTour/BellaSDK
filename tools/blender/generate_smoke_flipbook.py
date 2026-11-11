"""Headless Blender 5.x Mantaflow smoke simulation and flipbook renderer.

Bakes a 64-frame gas simulation and renders 256x256 unlit emissive frames.
"""

import os
import sys
import tempfile
import bpy
import mathutils

def build_smoke_scene(output_dir: str) -> None:
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

    # Frame output pattern
    scene.render.filepath = os.path.join(output_dir, "frame_")

    # 3. Create Emitter (Circle mesh)
    bpy.ops.mesh.primitive_circle_add(
        vertices=32,
        radius=0.3,
        fill_type='NGON',
        location=(0, 0, 0.2)
    )
    emitter = bpy.context.active_object
    emitter.name = "Smoke_Emitter"

    # Particle system on emitter for burst
    p_mod = emitter.modifiers.new(name="Smoke_Particles", type='PARTICLE_SYSTEM')
    p_settings = p_mod.particle_system.settings
    p_settings.count = 30
    p_settings.frame_start = 1
    p_settings.frame_end = 1
    p_settings.lifetime = 8
    p_settings.normal_factor = 2.0
    p_settings.factor_random = 0.5
    p_settings.render_type = 'NONE'

    # Flow modifier
    flow_mod = emitter.modifiers.new(name="Fluid_Flow", type='FLUID')
    flow_mod.fluid_type = 'FLOW'
    fs = flow_mod.flow_settings
    fs.flow_type = 'SMOKE'
    fs.flow_behavior = 'INFLOW'
    fs.flow_source = 'PARTICLES'
    fs.particle_system = p_mod.particle_system
    fs.use_initial_velocity = True
    fs.velocity_factor = 1.0

    # 4. Create Mantaflow Gas Domain
    # Bounds: center at (0, 0, 1.25), size 2.5 x 2.5 x 2.5
    bpy.ops.mesh.primitive_cube_add(
        location=(0.0, 0.0, 1.25),
        scale=(1.25, 1.25, 1.25)
    )
    domain = bpy.context.active_object
    domain.name = "Smoke_Domain"

    d_mod = domain.modifiers.new(name="Fluid_Domain", type='FLUID')
    d_mod.fluid_type = 'DOMAIN'
    ds = d_mod.domain_settings
    ds.domain_type = 'GAS'
    ds.resolution_max = 96
    ds.time_scale = 1.2
    ds.use_dissolve_smoke = True
    ds.dissolve_speed = 25
    ds.use_dissolve_smoke_log = True  # Slow dissolve
    ds.use_adaptive_domain = True
    ds.cache_type = 'ALL'
    ds.cache_frame_start = 1
    ds.cache_frame_end = 64

    cache_dir = os.path.join(output_dir, "cache")
    os.makedirs(cache_dir, exist_ok=True)
    ds.cache_directory = cache_dir

    # 5. Volumetric Material (Pure unlit emission driven by density)
    mat = bpy.data.materials.new(name="Smoke_Volume_Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_out.location = (400, 0)

    node_volume = nodes.new(type="ShaderNodeVolumePrincipled")
    node_volume.location = (100, 0)
    # Zero scattering absorption to avoid shadows/lighting dependency
    node_volume.inputs["Density"].default_value = 0.0
    node_volume.inputs["Absorption Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    node_volume.inputs["Emission Color"].default_value = (1.0, 1.0, 1.0, 1.0)

    # Attribute node reading Smoke Density
    node_attr = nodes.new(type="ShaderNodeAttribute")
    node_attr.location = (-300, 0)
    node_attr.attribute_name = "density"

    # Math multiply: density * 5.0 -> Emission Strength
    node_mult = nodes.new(type="ShaderNodeMath")
    node_mult.location = (-100, 0)
    node_mult.operation = 'MULTIPLY'
    node_mult.inputs[1].default_value = 5.0

    links.new(node_attr.outputs["Fac"], node_mult.inputs[0])
    links.new(node_mult.outputs["Value"], node_volume.inputs["Emission Strength"])
    links.new(node_volume.outputs["Volume"], node_out.inputs["Volume"])

    domain.data.materials.append(mat)

    # 6. Orthographic Front Camera
    # Domain is Z: 0.0 to 2.5, X: -1.25 to 1.25. Center: (0, 0, 1.25)
    bpy.ops.object.camera_add(
        location=(0.0, -4.0, 1.25),
        rotation=(1.5707963, 0.0, 0.0)  # 90 degrees around X
    )
    cam = bpy.context.active_object
    cam.name = "Front_Ortho_Camera"
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 2.6  # Fits 2.5m domain safely without edge clipping
    scene.camera = cam

    # Make domain active object before invoking fluid bake operator
    bpy.context.view_layer.objects.active = domain
    domain.select_set(True)

    # Save blend file so Mantaflow relative cache operates reliably
    blend_path = os.path.join(output_dir, "smoke_scene.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)

    # 7. Bake simulation
    print("Beginning Mantaflow simulation bake...")
    bpy.ops.fluid.bake_all()
    print("Simulation bake finished successfully.")

    # 8. Render animation frames
    print("Rendering 64 animation frames...")
    bpy.ops.render.render(animation=True)
    print("Render complete.")

    # 9. Pack frames into 8x8 flipbook with emission-to-alpha mapping
    stitch_flipbook(output_dir)

def stitch_flipbook(directory: str) -> None:
    import glob
    try:
        from PIL import Image
    except ImportError:
        print("Pillow not installed in Blender Python environment.")
        return

    frames = sorted(glob.glob(os.path.join(directory, "frame_*.png")))
    if len(frames) < 64:
        print(f"Warning: Expected 64 frames, found {len(frames)}")

    sheet = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
    for idx, path in enumerate(frames[:64]):
        im = Image.open(path).convert("RGBA")
        r, g, b, _ = im.split()
        # Pure emissive smoke has alpha in RGB intensity
        remapped = Image.merge("RGBA", (r, g, b, r))
        row = idx // 8
        col = idx % 8
        sheet.paste(remapped, (col * 256, row * 256))

    out_path = os.path.join(directory, "smoke_puff_8x8.png")
    sheet.save(out_path)
    print(f"Packed 8x8 flipbook saved to {out_path}")

if __name__ == "__main__":
    out_dir = sys.argv[-1] if len(sys.argv) > 1 and not sys.argv[-1].endswith(".py") else "/tmp/blender_smoke"
    os.makedirs(out_dir, exist_ok=True)
    build_smoke_scene(out_dir)
