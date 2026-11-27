"""Headless Blender Mantaflow narrow vertical smoke plume generator.
Generates 64 frames of unlit white smoke density and stitches an 8x8 flipbook.
"""

import os
import sys
import tempfile
import bpy
import math

def setup_scene(output_dir: str) -> None:
    # Clear all existing objects in default scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    # Set frame range
    scene.frame_start = 1
    scene.frame_end = 64
    scene.render.fps = 60

    # Render settings
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    if "BLENDER_EEVEE" in engines:
        scene.render.engine = "BLENDER_EEVEE"
    elif "BLENDER_EEVEE_NEXT" in engines:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    elif "CYCLES" in engines:
        scene.render.engine = "CYCLES"

    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.filepath = os.path.join(output_dir, "frame_")

    # 1. Emitter Disk (radius 0.12m, Z = -1.95m inside domain boundary)
    bpy.ops.mesh.primitive_circle_add(
        vertices=32,
        radius=0.12,
        fill_type='NGON',
        location=(0.0, 0.0, -1.95)
    )
    emitter = bpy.context.active_object
    emitter.name = "Smoke_Emitter"

    # Emitter Particle System
    part_mod = emitter.modifiers.new(name="Smoke_Particles", type='PARTICLE_SYSTEM')
    psys = emitter.particle_systems[part_mod.name]
    pset = psys.settings
    pset.count = 35
    pset.frame_start = 1
    pset.frame_end = 1
    pset.lifetime = 12
    pset.normal_factor = 7.0
    pset.factor_random = 0.3
    pset.physics_type = 'NEWTON'
    pset.render_type = 'NONE'

    # Emitter Fluid Flow Modifier
    flow_mod = emitter.modifiers.new(name="Fluid_Flow", type='FLUID')
    flow_mod.fluid_type = 'FLOW'
    flow_settings = flow_mod.flow_settings
    flow_settings.flow_type = 'SMOKE'
    flow_settings.flow_behavior = 'INFLOW'
    flow_settings.flow_source = 'PARTICLES'
    flow_settings.particle_system = psys
    flow_settings.use_initial_velocity = True
    flow_settings.velocity_factor = 1.5
    flow_settings.temperature = 4.0

    # 2. Mantaflow Smoke Domain
    # Tall bounding box: Dimensions (1.2m, 1.2m, 5.0m) centered at Z = 0.5m
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=(0.0, 0.0, 0.5),
        scale=(1.2, 1.2, 5.0)
    )
    domain = bpy.context.active_object
    domain.name = "Smoke_Domain"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    domain_mod = domain.modifiers.new(name="Fluid_Domain", type='FLUID')
    domain_mod.fluid_type = 'DOMAIN'
    dsettings = domain_mod.domain_settings
    dsettings.domain_type = 'GAS'
    dsettings.resolution_max = 112
    dsettings.time_scale = 1.4
    dsettings.beta = 4.0  # Upward heat buoyancy / temperature difference
    dsettings.vorticity = 0.15
    dsettings.use_dissolve_smoke = True
    dsettings.dissolve_speed = 30
    dsettings.use_dissolve_smoke_log = True  # Slow dissolve
    dsettings.cache_type = 'ALL'
    dsettings.cache_frame_start = 1
    dsettings.cache_frame_end = 64

    # Cache directory inside output_dir
    cache_dir = os.path.join(output_dir, "cache_fluid")
    os.makedirs(cache_dir, exist_ok=True)
    dsettings.cache_directory = cache_dir

    # 3. Domain Material / Volumetric Shading
    mat = bpy.data.materials.new(name="M_Smoke_Volume")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    # Attribute density -> Math (Multiply 4.5) -> Volume Emission Strength
    # Emission color: Pure White (1.0, 1.0, 1.0)
    vol_output = nodes.new(type="ShaderNodeOutputMaterial")
    vol_output.location = (400, 0)

    pvol = nodes.new(type="ShaderNodeVolumePrincipled")
    pvol.location = (150, 0)
    pvol.inputs["Density"].default_value = 0.0
    pvol.inputs["Emission Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    pvol.inputs["Absorption Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    pvol.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)

    attr = nodes.new(type="ShaderNodeAttribute")
    attr.location = (-300, 0)
    attr.attribute_name = "density"

    math_mul = nodes.new(type="ShaderNodeMath")
    math_mul.location = (-100, 0)
    math_mul.operation = 'MULTIPLY'
    math_mul.inputs[1].default_value = 4.5

    links.new(attr.outputs["Fac"], math_mul.inputs[0])
    links.new(math_mul.outputs["Value"], pvol.inputs["Emission Strength"])
    links.new(pvol.outputs["Volume"], vol_output.inputs["Volume"])

    domain.data.materials.append(mat)

    # 4. Orthographic Camera
    bpy.ops.object.camera_add(
        location=(0.0, -4.5, 0.5),
        rotation=(math.radians(90.0), 0.0, 0.0)
    )
    cam = bpy.context.active_object
    cam.name = "Render_Camera"
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 5.0 / 0.85
    scene.camera = cam

    # Save temp blend file so Mantaflow cache can bake
    blend_path = os.path.join(output_dir, "mantaflow_smoke.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)

    # Bake Mantaflow ALL cache
    print("Baking Mantaflow simulation frames 1 to 64...")
    bpy.context.view_layer.objects.active = domain
    domain.select_set(True)
    bpy.ops.fluid.bake_all()
    print("Mantaflow bake complete.")

    # Render animation frames
    print("Rendering animation frames...")
    bpy.ops.render.render(animation=True)
    print("Animation render complete.")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[-1] != "--":
        out_dir = sys.argv[-1]
    else:
        out_dir = tempfile.mkdtemp(prefix="smoke_sim_")

    print(f"Target simulation directory: {out_dir}")
    setup_scene(out_dir)
