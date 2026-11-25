"""Headless Blender generator for the Fluorescent Lamp prop.

Builds a single merged low-poly fluorescent ceiling fixture (`Fluorescent_Lamp`)
with a recessed trapezoidal reflector trough, twin 8-sided emissive tubes,
end-cap tombstones, Smart UV Project lightmap UVs, and a Godot `-colonly`
collision sibling (`Fluorescent_Lamp-colonly`). Exports directly to GLB.

Usage:
    blender --background --python tools/blender/generators/generate_fluorescent_lamp.py
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix


DEFAULT_OUT_PATH = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "..",
        "assets",
        "models",
        "props",
        "fluorescent_lamp",
        "fluorescent_lamp.glb",
    )
)


def clear_scene() -> None:
    """Remove all existing objects and orphan data blocks."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_material(
    name: str,
    base_color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
    emission_color: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 1.0),
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    """Create or update a Principled BSDF material."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emission_color
            bsdf.inputs["Emission Strength"].default_value = emission_strength
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = emission_color
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def build_fluorescent_lamp() -> tuple[bpy.types.Object, bpy.types.Object]:
    """Build Fluorescent_Lamp mesh and Fluorescent_Lamp-colonly sibling."""
    for obj_name in ("Fluorescent_Lamp", "Fluorescent_Lamp-colonly"):
        existing = bpy.data.objects.get(obj_name)
        if existing:
            bpy.data.objects.remove(existing, do_unlink=True)

    mat_housing = create_material(
        name="Mat_Lamp_Housing",
        base_color=(0.32, 0.35, 0.34, 1.0),
        metallic=0.75,
        roughness=0.55,
    )
    mat_tube = create_material(
        name="Mat_Lamp_Tube",
        base_color=(0.90, 0.98, 0.95, 1.0),
        metallic=0.0,
        roughness=0.15,
        emission_color=(0.82, 0.96, 0.92, 1.0),
        emission_strength=6.0,
    )

    bm = bmesh.new()

    # 1. Outer Housing with Recessed Reflector Trough (Material 0)
    # Dimensions: Length=1.20m (Y), Width=0.18m (X), Height=0.08m (-Z)
    hl = 0.60
    tw = 0.090     # Top half-width (ceiling mount)
    bw = 0.082     # Bottom outer lip half-width
    rw = 0.068     # Inner reflector rim half-width
    cw = 0.042     # Inner reflector ceiling half-width
    z_top = 0.0
    z_bot = -0.055
    z_trough = -0.022

    # 8-point cross-section profile along Y (-hl to +hl)
    profile_coords = [
        (-tw, z_top),     # 0: Top-Left
        (tw, z_top),      # 1: Top-Right
        (bw, z_bot),      # 2: Bottom-Right Outer
        (rw, z_bot),      # 3: Bottom-Right Inner Lip
        (cw, z_trough),   # 4: Trough Ceiling Right
        (-cw, z_trough),  # 5: Trough Ceiling Left
        (-rw, z_bot),     # 6: Bottom-Left Inner Lip
        (-bw, z_bot),     # 7: Bottom-Left Outer
    ]

    front_verts = [bm.verts.new((x, -hl, z)) for x, z in profile_coords]
    back_verts = [bm.verts.new((x, hl, z)) for x, z in profile_coords]

    n_pts = len(profile_coords)
    for i in range(n_pts):
        nxt = (i + 1) % n_pts
        f = bm.faces.new(
            (
                front_verts[i],
                front_verts[nxt],
                back_verts[nxt],
                back_verts[i],
            )
        )
        f.material_index = 0

    # End caps (quad subdivisions to keep clean topology)
    quad_indices = [
        (0, 1, 4, 5),
        (1, 2, 3, 4),
        (5, 4, 3, 6),  # Inner trough end wall
        (0, 5, 6, 7),
    ]
    for a, b, c, d in quad_indices:
        f_front = bm.faces.new(
            (
                front_verts[d],
                front_verts[c],
                front_verts[b],
                front_verts[a],
            )
        )
        f_front.material_index = 0
        f_back = bm.faces.new(
            (
                back_verts[a],
                back_verts[b],
                back_verts[c],
                back_verts[d],
            )
        )
        f_back.material_index = 0

    # 2. End-Cap Socket Blocks / Tombstones (Material 0)
    socket_offsets_x = (-0.032, 0.032)
    socket_offsets_y = (-0.565, 0.565)
    for sx in socket_offsets_x:
        for sy in socket_offsets_y:
            res = bmesh.ops.create_cube(bm, size=1.0)
            verts = res["verts"]
            bmesh.ops.scale(bm, vec=(0.028, 0.035, 0.042), verts=verts)
            bmesh.ops.translate(bm, vec=(sx, sy, -0.043), verts=verts)
            for v in verts:
                for f in v.link_faces:
                    f.material_index = 0

    # 3. Twin Fluorescent Tubes (Material 1)
    tube_radius = 0.015
    tube_length = 1.095
    tube_z = -0.048
    rot_mat = Matrix.Rotation(math.radians(90.0), 3, "X")

    for tx in socket_offsets_x:
        res = bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=8,
            radius1=tube_radius,
            radius2=tube_radius,
            depth=tube_length,
        )
        verts = res["verts"]
        bmesh.ops.rotate(
            bm,
            cent=(0.0, 0.0, 0.0),
            matrix=rot_mat,
            verts=verts,
        )
        bmesh.ops.translate(bm, vec=(tx, 0.0, tube_z), verts=verts)
        for v in verts:
            for f in v.link_faces:
                f.material_index = 1
                f.smooth = True

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Write Mesh & Object
    mesh = bpy.data.meshes.new("Fluorescent_Lamp_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    lamp_obj = bpy.data.objects.new("Fluorescent_Lamp", mesh)
    bpy.context.collection.objects.link(lamp_obj)
    lamp_obj.data.materials.append(mat_housing)
    lamp_obj.data.materials.append(mat_tube)

    # Smart UV Project for Godot LightmapGI / baking
    bpy.context.view_layer.objects.active = lamp_obj
    lamp_obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    # 4. Godot Collision Sibling (-colonly)
    bm_col = bmesh.new()
    res_col = bmesh.ops.create_cube(bm_col, size=1.0)
    bmesh.ops.scale(bm_col, vec=(0.18, 1.20, 0.08), verts=res_col["verts"])
    bmesh.ops.translate(bm_col, vec=(0.0, 0.0, -0.04), verts=res_col["verts"])
    col_mesh = bpy.data.meshes.new("Fluorescent_Lamp_Col_Mesh")
    bm_col.to_mesh(col_mesh)
    bm_col.free()

    col_obj = bpy.data.objects.new("Fluorescent_Lamp-colonly", col_mesh)
    col_obj.display_type = "WIRE"
    bpy.context.collection.objects.link(col_obj)
    col_obj.parent = lamp_obj

    return lamp_obj, col_obj


def export_glb(out_path: str, objects: tuple[bpy.types.Object, ...]) -> None:
    """Export selected objects to glTF 2.0 binary (.glb)."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
    )


def main() -> None:
    """Parse optional CLI output path after `--`, build lamp, and export GLB."""
    out_path = DEFAULT_OUT_PATH
    if "--" in sys.argv:
        extra = sys.argv[sys.argv.index("--") + 1 :]
        if extra:
            out_path = os.path.abspath(extra[0])

    clear_scene()
    lamp_obj, col_obj = build_fluorescent_lamp()
    export_glb(out_path, (lamp_obj, col_obj))
    print(f"Exported Fluorescent_Lamp GLB -> {out_path}")


if __name__ == "__main__":
    main()
