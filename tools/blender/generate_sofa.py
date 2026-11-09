"""
Generates a blocky 2-seat loveseat (sofa.glb) for Godot 4.
Includes beveled cushion geometry, vertex color AO/dirt in COLOR_0,
smart UV project, and -colonly box primitives.
"""

import os
import sys
import bpy
import bmesh
from mathutils import Vector


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_material() -> bpy.types.Material:
    mat = bpy.data.materials.new(name="M_Sofa_Fabric")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        # Dirty reddish-brown terracotta base (#6E2C1E in linear)
        base_color = (0.155, 0.025, 0.012, 1.0)
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Roughness"].default_value = 0.85

        # Link COLOR_0 into shader so glTF exporter preserves vertex color attribute
        vcol = nodes.new(type="ShaderNodeVertexColor")
        vcol.layer_name = "COLOR_0"
        mix = nodes.new(type="ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[6].default_value = base_color
        mat.node_tree.links.new(vcol.outputs["Color"], mix.inputs[7])
        mat.node_tree.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def make_part(
    name: str,
    size: tuple[float, float, float],
    loc: tuple[float, float, float],
    bevel_width: float = 0.02,
    bevel_segments: int = 2,
    front_droop: float = 0.0,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)

    # Slight front-lip sag/taper for seat cushions (+Y is forward in Blender -> -Z in Godot)
    if front_droop != 0.0:
        for v in bm.verts:
            if v.co.y > 0.0 and v.co.z < 0.0:
                v.co.z -= front_droop

    bmesh.ops.translate(bm, vec=loc, verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()

    bevel = obj.modifiers.new(name="Bevel", type="BEVEL")
    bevel.width = bevel_width
    bevel.segments = bevel_segments
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = 0.523599  # 30 deg

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)

    for poly in obj.data.polygons:
        poly.use_smooth = True

    return obj


def bake_procedural_vertex_dirt(obj: bpy.types.Object) -> None:
    """Writes crevice/ground AO approximation into COLOR_0 for Godot shaders."""
    mesh = obj.data
    if not mesh.color_attributes:
        mesh.color_attributes.new(name="COLOR_0", type="BYTE_COLOR", domain="CORNER")
    color_layer = mesh.color_attributes["COLOR_0"].data

    # Darken lower vertices, inner cushion seams (X near 0 or +/-0.68), and back crease (Y near -0.25)
    for poly in mesh.polygons:
        for loop_idx in poly.loop_indices:
            v = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            height_ao = min(1.0, max(0.35, v.z / 0.55))
            seam_dist_center = abs(v.x)
            seam_ao = min(1.0, max(0.45, seam_dist_center / 0.08))
            back_crease = min(1.0, max(0.5, abs(v.y + 0.22) / 0.12))

            ao = height_ao * seam_ao * back_crease
            color_layer[loop_idx].color = (ao, ao, ao, 1.0)


def create_collider(
    name: str,
    size: tuple[float, float, float],
    loc: tuple[float, float, float],
    parent: bpy.types.Object,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=loc, verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()

    obj.parent = parent
    return obj


def build_sofa(output_path: str = "assets/models/props/sofa/sofa.glb") -> None:
    clear_scene()
    mat = create_material()

    root = bpy.data.objects.new("Sofa_Root", None)
    bpy.context.collection.objects.link(root)

    parts: list[bpy.types.Object] = []

    # 1. Outer Box Frame (1.8m W x 0.9m D x 0.75m H)
    # Left & Right Outer Arms
    parts.append(make_part("Arm_L", (0.16, 0.90, 0.75), (-0.82, 0.0, 0.375), 0.015, 2))
    parts.append(make_part("Arm_R", (0.16, 0.90, 0.75), (0.82, 0.0, 0.375), 0.015, 2))
    # Back Outer Wall
    parts.append(make_part("Back_Wall", (1.48, 0.14, 0.75), (0.0, -0.38, 0.375), 0.015, 2))
    # Bottom Kickplate / Base
    parts.append(make_part("Base_Deck", (1.48, 0.76, 0.24), (0.0, 0.05, 0.12), 0.012, 2))

    # 2. Seat Cushions (2 wide pads overhanging the front base slightly)
    parts.append(
        make_part("Seat_L", (0.735, 0.76, 0.13), (-0.37, 0.08, 0.305), 0.035, 3, front_droop=0.018)
    )
    parts.append(
        make_part("Seat_R", (0.735, 0.76, 0.13), (0.37, 0.08, 0.305), 0.035, 3, front_droop=0.018)
    )

    # 3. Backrest Cushions (2 cushions resting above seats against back wall)
    parts.append(make_part("Back_Cushion_L", (0.73, 0.16, 0.37), (-0.37, -0.23, 0.545), 0.04, 3))
    parts.append(make_part("Back_Cushion_R", (0.73, 0.16, 0.37), (0.37, -0.23, 0.545), 0.04, 3))

    # 4. Inner Armrest Bolsters (2 thinner rectangular pillows tucked inside outer arms)
    parts.append(make_part("Bolster_L", (0.11, 0.58, 0.25), (-0.68, 0.12, 0.48), 0.035, 3))
    parts.append(make_part("Bolster_R", (0.11, 0.58, 0.25), (0.68, 0.12, 0.48), 0.035, 3))

    # Join visual parts into single mesh
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    sofa_obj = bpy.context.active_object
    sofa_obj.name = "Sofa"
    sofa_obj.data.name = "Sofa_Mesh"
    sofa_obj.parent = root
    sofa_obj.data.materials.append(mat)

    # Smart UV Project
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    bake_procedural_vertex_dirt(sofa_obj)

    # 5. Compound Box Colliders (-colonly suffix for Godot 4 primitive BoxShape3D import)
    create_collider("Col_Seat-colonly", (1.48, 0.78, 0.37), (0.0, 0.06, 0.185), root)
    create_collider("Col_Back-colonly", (1.48, 0.28, 0.75), (0.0, -0.31, 0.375), root)
    create_collider("Col_Arm_L-colonly", (0.22, 0.90, 0.75), (-0.79, 0.0, 0.375), root)
    create_collider("Col_Arm_R-colonly", (0.22, 0.90, 0.75), (0.79, 0.0, 0.375), root)

    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    # Export to GLB (Y-Up for glTF/Godot)
    export_kwargs = {
        "filepath": output_path,
        "export_format": "GLB",
        "use_selection": False,
        "export_apply": True,
        "export_yup": True,
        "export_texcoords": True,
        "export_normals": True,
        "export_materials": "EXPORT",
    }
    # Handle Blender version variations for vertex color export flag
    gltf_props = bpy.ops.export_scene.gltf.get_rna_type().properties
    if "export_all_vertex_colors" in gltf_props:
        export_kwargs["export_all_vertex_colors"] = True
    elif "export_colors" in gltf_props:
        export_kwargs["export_colors"] = True
    if "export_attributes" in gltf_props:
        export_kwargs["export_attributes"] = True

    bpy.ops.export_scene.gltf(**export_kwargs)
    print(f"Exported {output_path} successfully.")


if __name__ == "__main__":
    target = "assets/models/props/sofa/sofa.glb"
    if len(sys.argv) > 1 and sys.argv[-1].endswith(".glb"):
        target = sys.argv[-1]
    build_sofa(target)
