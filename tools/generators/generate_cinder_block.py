import os
import bpy
import bmesh
from mathutils import Vector

# Dimensions: 0.39m (X) x 0.19m (Y - width) x 0.19m (Z - height)
LENGTH = 0.39
WIDTH = 0.19
HEIGHT = 0.19
WALL = 0.03
BEVEL_WIDTH = 0.004
OUTPUT_PATH = os.path.abspath("./assets/props/cinder_block.glb")


def build_cinder_block() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # Base outer block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    block = bpy.context.active_object
    block.name = "CinderBlock"
    block.scale = (LENGTH, WIDTH, HEIGHT)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Core cutout dimensions
    core_x = (LENGTH - (WALL * 3.0)) * 0.5
    core_y = WIDTH - (WALL * 2.0)
    core_z = HEIGHT + 0.04
    offset_x = (WALL * 0.5) + (core_x * 0.5)

    for sign in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(
            size=1.0, location=(sign * offset_x, 0.0, 0.0)
        )
        cutter = bpy.context.active_object
        cutter.scale = (core_x, core_y, core_z)
        bpy.ops.object.transform_apply(
            location=False, rotation=False, scale=True
        )

        bool_mod = block.modifiers.new(name="CoreCut", type="BOOLEAN")
        bool_mod.operation = "DIFFERENCE"
        bool_mod.solver = "EXACT"
        bool_mod.object = cutter
        bpy.context.view_layer.objects.active = block
        bpy.ops.object.modifier_apply(modifier=bool_mod.name)

        bpy.data.objects.remove(cutter, do_unlink=True)

    # Bevel hard edges
    bevel_mod = block.modifiers.new(name="Bevel", type="BEVEL")
    bevel_mod.width = BEVEL_WIDTH
    bevel_mod.segments = 1
    bevel_mod.limit_method = "ANGLE"
    bevel_mod.angle_limit = 0.785398  # 45 deg
    bpy.ops.object.modifier_apply(modifier=bevel_mod.name)

    # Bake interior core cavity darkening into Vertex Color (COLOR_0)
    mesh = block.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    color_layer = bm.loops.layers.color.new("Color")

    outer_x = (LENGTH * 0.5) - (WALL * 0.5)
    outer_y = (WIDTH * 0.5) - (WALL * 0.5)
    outer_z = (HEIGHT * 0.5) - (BEVEL_WIDTH * 1.5)

    for face in bm.faces:
        center = face.calc_center_median()
        is_inner_wall = (
            abs(center.x) < outer_x
            and abs(center.y) < outer_y
            and abs(center.z) < outer_z
        )
        ao_val = 0.35 if is_inner_wall else 1.0
        for loop in face.loops:
            loop[color_layer] = Vector((ao_val, ao_val, ao_val, 1.0))

    bm.to_mesh(mesh)
    bm.free()

    # Auto UV unwrap
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Rotate so Y is UP in Godot (Z in Blender = Height -> Y in glTF)
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_PATH,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_attributes=True,
        export_all_vertex_colors=True,
        export_active_vertex_color_when_no_material=True,
    )
    print(f"Exported: {OUTPUT_PATH}")


if __name__ == "__main__":
    build_cinder_block()
