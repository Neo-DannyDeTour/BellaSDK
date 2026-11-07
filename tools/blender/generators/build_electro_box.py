#!/usr/bin/env python3
"""Procedural generator for industrial electro box / electrical cabinet prop.

Generates ElectroBox mesh with Godot 4 convex collider (-convcolonly) and exports to
assets/props/electro_box/electro_box.glb.
Compatible with Blender 4.x and 5.x.
"""

from __future__ import annotations

import math
import os
from pathlib import Path
import bmesh
import bpy
from mathutils import Matrix, Vector

SCRIPT_DIR: Path = Path(__file__).resolve().parent
PROJECT_ROOT: Path = SCRIPT_DIR.parents[1]
OUTPUT_DIR: Path = PROJECT_ROOT / "assets" / "props" / "electro_box"
OUTPUT_PATH: Path = OUTPUT_DIR / "electro_box.glb"

# Material slot indices
MAT_CABINET: int = 0
MAT_ROOF: int = 1
MAT_CONCRETE: int = 2
MAT_PIPES: int = 3


def clear_existing(names: list[str]) -> None:
    """Purge old objects and orphaned meshes matching given names."""
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh_name in names:
        mesh = bpy.data.meshes.get(mesh_name)
        if mesh and mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def get_or_create_material(
    name: str, base_color: tuple[float, float, float, float], metallic: float, roughness: float
) -> bpy.types.Material:
    """Retrieve existing material or configure a new Principled BSDF material."""
    mat = bpy.data.materials.get(name)
    if not mat:
        mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_box(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    mat_idx: int,
    taper_top: tuple[float, float] = (1.0, 1.0),
    rot_x: float = 0.0,
) -> None:
    """Add a box with optional top taper and X-axis rotation."""
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=verts)

    for v in verts:
        if v.co.z > 0.0:
            v.co.x *= taper_top[0]
            v.co.y *= taper_top[1]

    if rot_x != 0.0:
        bmesh.ops.rotate(
            bm,
            cent=Vector((0.0, 0.0, 0.0)),
            matrix=Matrix.Rotation(rot_x, 3, "X"),
            verts=verts,
        )

    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)

    vert_set = set(verts)
    for f in bm.faces:
        if all(v in vert_set for v in f.verts):
            f.material_index = mat_idx


def add_cylinder(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    radius: float,
    depth: float,
    segments: int,
    mat_idx: int,
    rot_x: float = 0.0,
) -> None:
    """Add a cylinder with smooth sides and flat end caps."""
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
    )
    verts = res["verts"]
    if rot_x != 0.0:
        bmesh.ops.rotate(
            bm,
            cent=Vector((0.0, 0.0, 0.0)),
            matrix=Matrix.Rotation(rot_x, 3, "X"),
            verts=verts,
        )
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)

    vert_set = set(verts)
    for f in bm.faces:
        if all(v in vert_set for v in f.verts):
            f.material_index = mat_idx
            # Smooth side faces, keep end caps flat
            f.smooth = abs(f.normal.z if rot_x == 0.0 else f.normal.y) < 0.85


def add_louver_group(bm: bmesh.types.BMesh, cx: float, cy: float, cz: float) -> None:
    """Add ventilation louver panel with 3 angled louvers and 4 corner rivets."""
    # Stamped backing plate
    add_box(bm, (cx, cy - 0.003, cz), (0.17, 0.006, 0.11), MAT_CABINET)

    # 3 horizontal angled louver hoods
    for slot_idx in (-1, 0, 1):
        sz = cz + slot_idx * 0.026
        add_box(
            bm,
            (cx, cy - 0.009, sz),
            (0.125, 0.012, 0.013),
            MAT_CABINET,
            taper_top=(0.95, 0.6),
            rot_x=math.radians(18.0),
        )

    # 4 corner rivets
    for rx in (-0.068, 0.068):
        for rz in (-0.042, 0.042):
            add_cylinder(
                bm,
                (cx + rx, cy - 0.007, cz + rz),
                radius=0.0045,
                depth=0.006,
                segments=8,
                mat_idx=MAT_CABINET,
                rot_x=math.radians(90.0),
            )


def apply_world_box_uvs(bm: bmesh.types.BMesh) -> None:
    """Apply world-aligned box UV projections to mesh faces."""
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        nx, ny, nz = abs(face.normal.x), abs(face.normal.y), abs(face.normal.z)
        for loop in face.loops:
            co = loop.vert.co
            if nx >= ny and nx >= nz:
                loop[uv_layer].uv = (co.y, co.z)
            elif ny >= nx and ny >= nz:
                loop[uv_layer].uv = (co.x, co.z)
            else:
                loop[uv_layer].uv = (co.x, co.y)


def build_electro_box() -> bpy.types.Object:
    """Build procedural ElectroBox geometry and convex collision child."""
    clear_existing(["ElectroBox", "ElectroBox-convcolonly", "ElectroBox-colonly"])

    bm = bmesh.new()

    # 1. Concrete support blocks (x2, tapered top)
    for bx in (-0.59, 0.59):
        add_box(bm, (bx, 0.0, 0.14), (0.34, 0.56, 0.28), MAT_CONCRETE, taper_top=(0.86, 0.90))

    # 2. Bottom conduit pipes (x3) + ground flanges
    for px in (-0.33, -0.19, -0.05):
        add_cylinder(bm, (px, -0.08, 0.145), radius=0.032, depth=0.29, segments=16, mat_idx=MAT_PIPES)
        add_cylinder(bm, (px, -0.08, 0.012), radius=0.044, depth=0.024, segments=16, mat_idx=MAT_PIPES)

    # 3. Lower plinth / rusted base beam (Z: 0.28 -> 0.35)
    add_box(bm, (0.0, 0.0, 0.315), (1.56, 0.56, 0.07), MAT_ROOF)
    add_box(bm, (0.0, 0.0, 0.288), (1.58, 0.58, 0.016), MAT_ROOF)

    # 4. Main cabinet recessed core + outer frame rails (Z: 0.35 -> 1.28)
    add_box(bm, (0.0, 0.015, 0.815), (1.54, 0.53, 0.93), MAT_CABINET)
    # Left, Right, Center vertical pillars on front face
    add_box(bm, (-0.755, -0.265, 0.815), (0.05, 0.03, 0.93), MAT_CABINET)
    add_box(bm, (0.755, -0.265, 0.815), (0.05, 0.03, 0.93), MAT_CABINET)
    add_box(bm, (0.0, -0.262, 0.815), (0.022, 0.024, 0.90), MAT_CABINET)
    # Top & Bottom horizontal front rails
    add_box(bm, (0.0, -0.265, 1.265), (1.46, 0.03, 0.03), MAT_CABINET)
    add_box(bm, (0.0, -0.265, 0.365), (1.46, 0.03, 0.03), MAT_CABINET)

    # 5. Double Doors (Left & Right) + 4 Louver groups
    door_y = -0.268
    for dx in (-0.37, 0.37):
        add_box(bm, (dx, door_y, 0.815), (0.705, 0.024, 0.865), MAT_CABINET, taper_top=(0.995, 0.95))
        add_louver_group(bm, dx, door_y - 0.012, 1.12)
        add_louver_group(bm, dx, door_y - 0.012, 0.49)

    # 6. Segmented overhanging roof cap (Z: 1.28 -> 1.35)
    add_box(bm, (0.0, 0.0, 1.292), (1.62, 0.61, 0.024), MAT_ROOF)
    plank_count = 12
    total_w = 1.62
    plank_w = total_w / plank_count
    for i in range(plank_count):
        px = -total_w * 0.5 + (i + 0.5) * plank_w
        add_box(
            bm,
            (px, 0.0, 1.322),
            (plank_w - 0.004, 0.62, 0.042),
            MAT_ROOF,
            taper_top=(0.98, 0.92),
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    apply_world_box_uvs(bm)

    mesh = bpy.data.meshes.new("ElectroBox")
    bm.to_mesh(mesh)
    bm.free()

    # Assign materials
    materials = [
        get_or_create_material("Mat_Cabinet_Metal", (0.25, 0.27, 0.29, 1.0), 0.75, 0.62),
        get_or_create_material("Mat_Roof_Metal", (0.22, 0.18, 0.16, 1.0), 0.55, 0.78),
        get_or_create_material("Mat_Concrete", (0.36, 0.33, 0.30, 1.0), 0.0, 0.92),
        get_or_create_material("Mat_Pipes", (0.38, 0.39, 0.40, 1.0), 0.80, 0.50),
    ]
    for mat in materials:
        mesh.materials.append(mat)

    obj = bpy.data.objects.new("ElectroBox", mesh)
    bpy.context.collection.objects.link(obj)

    # 7. Godot convex collision child (`-convcolonly`)
    bm_col = bmesh.new()
    add_box(bm_col, (0.0, 0.0, 0.675), (1.62, 0.62, 1.35), 0)
    bmesh.ops.recalc_face_normals(bm_col, faces=bm_col.faces)
    col_mesh = bpy.data.meshes.new("ElectroBox-convcolonly")
    bm_col.to_mesh(col_mesh)
    bm_col.free()

    col_obj = bpy.data.objects.new("ElectroBox-convcolonly", col_mesh)
    col_obj.parent = obj
    col_obj.display_type = "WIRE"
    bpy.context.collection.objects.link(col_obj)

    return obj


def export_glb(root_obj: bpy.types.Object, out_path: Path) -> str:
    """Export root object and children to GLB with Godot conventions."""
    bpy.ops.object.select_all(action="DESELECT")
    root_obj.select_set(True)
    for child in root_obj.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root_obj

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_str = str(out_path)
    bpy.ops.export_scene.gltf(
        filepath=out_str,
        use_selection=True,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    return out_str


if __name__ == "__main__":
    cabinet = build_electro_box()
    exported = export_glb(cabinet, OUTPUT_PATH)
    print(f"ElectroBox generated and exported -> {exported}")
