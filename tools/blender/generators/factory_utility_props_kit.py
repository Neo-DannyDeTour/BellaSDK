"""Procedural Blender generator for factory utility prop GLBs.

Builds clean-room post-apocalyptic industrial props one asset at a time via `--asset <name>`:
- wooden_pallet: 1.20m x 0.145m x 1.00m Euro/industrial timber pallet (`assets/models/props/factory_yard/wooden_pallet.glb`)

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Clean world-metric box UVs (1.0m tile).
- Explicit material slots for Godot ORM material reassignment.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import create_pbr_material
from mathutils import Vector

_REPO_ROOT = _TOOL_DIR.parent.parent


def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> None:
    """Append an axis-aligned box with optional chamfer to a BMesh."""
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        return

    coords = [
        (x0, y0, z0),
        (x1, y0, z0),
        (x1, y1, z0),
        (x0, y1, z0),
        (x0, y0, z1),
        (x1, y0, z1),
        (x1, y1, z1),
        (x0, y1, z1),
    ]
    verts = [bm.verts.new(c) for c in coords]
    quad_indices = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    created_faces: list[bmesh.types.BMFace] = []
    for idx in quad_indices:
        f = bm.faces.new([verts[i] for i in idx])
        f.material_index = mat_idx
        created_faces.append(f)

    if chamfer > 0.0:
        edges = list({e for f in created_faces for e in f.edges})
        bmesh.ops.bevel(
            bm,
            geom=edges,
            offset=chamfer,
            offset_type="OFFSET",
            segments=1,
            profile=0.5,
            affect="EDGES",
            clamp_overlap=True,
        )


def _apply_box_uvs(bm: bmesh.types.BMesh, tile_meters: float = 1.0) -> None:
    """Assign world-metric triplanar box UVs to all loops in a BMesh."""
    uv_layer = bm.loops.layers.uv.verify()
    inv_tile = 1.0 / tile_meters
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * inv_tile, co.y * inv_tile
            elif ax >= ay and ax >= az:
                u, v = co.y * inv_tile, co.z * inv_tile
            else:
                u, v = co.x * inv_tile, co.z * inv_tile
            loop[uv_layer].uv = (u, v)


def _finalize_bmesh_object(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
) -> bpy.types.Object:
    """Convert BMesh to mesh object, apply UVs, normals, and materials."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_box_uvs(bm, tile_meters=1.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)
    return obj


def build_wooden_pallet(out_path: Path) -> None:
    """Generate a 1.20m x 0.145m x 1.00m Euro/industrial wooden pallet."""
    clean_scene()
    wood_mat = create_pbr_material("wood", (0.34, 0.27, 0.19, 1.0), metallic=0.0, roughness=0.88)

    bm = bmesh.new()
    # Dimensions in Blender Z-up: X = 1.20m width, Y = 1.00m depth, Z = 0.145m height
    width = 1.20
    depth = 1.00
    hx = width * 0.5
    hy = depth * 0.5

    # 3 bottom runner boards (along X, thickness 22mm, width 100mm at front/mid/back)
    bot_z0, bot_z1 = 0.0, 0.022
    for y_center in (-hy + 0.05, 0.0, hy - 0.05):
        _add_box_bm(bm, (-hx, y_center - 0.05, bot_z0), (hx, y_center + 0.05, bot_z1), 0, 0.002)

    # 9 spacer blocks (3x3 grid, height 78mm)
    blk_z0, blk_z1 = bot_z1, bot_z1 + 0.078
    x_centers = (-hx + 0.0725, 0.0, hx - 0.0725)
    y_centers = (-hy + 0.05, 0.0, hy - 0.05)
    for xc in x_centers:
        for yc in y_centers:
            _add_box_bm(bm, (xc - 0.0725, yc - 0.05, blk_z0), (xc + 0.0725, yc + 0.05, blk_z1), 0, 0.002)

    # 3 transverse stringer boards (along Y, thickness 22mm)
    str_z0, str_z1 = blk_z1, blk_z1 + 0.022
    for xc in x_centers:
        _add_box_bm(bm, (xc - 0.0725, -hy, str_z0), (xc + 0.0725, hy, str_z1), 0, 0.002)

    # 7 top deck slats (along X, thickness 23mm -> total Z = 0.145m)
    top_z0, top_z1 = str_z1, 0.145
    slat_specs = [
        (-hy + 0.0725, 0.145),
        (-0.31, 0.100),
        (-0.155, 0.100),
        (0.0, 0.145),
        (0.155, 0.100),
        (0.31, 0.100),
        (hy - 0.0725, 0.145),
    ]
    for yc, slat_w in slat_specs:
        hw = slat_w * 0.5
        _add_box_bm(bm, (-hx, yc - hw, top_z0), (hx, yc + hw, top_z1), 0, 0.002)

    obj = _finalize_bmesh_object("wooden_pallet", bm, [wood_mat])
    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    bmin = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    bmax = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    export_godot_glb(str(out_path))
    print(f"[wooden_pallet] tris={tri_count} bbox_blender=({bmin.x:.3f}..{bmax.x:.3f}, {bmin.y:.3f}..{bmax.y:.3f}, {bmin.z:.3f}..{bmax.z:.3f}) -> {out_path}")


def build_cable_reel(out_path: Path) -> None:
    """Generate a 1.10m diameter x 0.72m wide industrial wooden/steel cable drum."""
    clean_scene()
    wood_mat = create_pbr_material("wood", (0.34, 0.27, 0.19, 1.0), metallic=0.0, roughness=0.88)
    steel_mat = create_pbr_material("steel", (0.25, 0.23, 0.21, 1.0), metallic=0.82, roughness=0.58)
    cable_mat = create_pbr_material("cable", (0.07, 0.07, 0.08, 1.0), metallic=0.05, roughness=0.65)

    bm = bmesh.new()
    # Upright standing drum in Blender Z-up: axis along X, resting on Z=0
    flange_r = 0.55
    flange_t = 0.045
    half_w = 0.36
    inner_x = half_w - flange_t
    hub_z = flange_r

    def add_x_cyl(x0: float, x1: float, radius: float, segs: int, mat_idx: int) -> None:
        length = x1 - x0
        xc = 0.5 * (x0 + x1)
        from mathutils import Matrix

        rot = Matrix.Translation((xc, 0.0, hub_z)) @ Matrix.Rotation(math.pi * 0.5, 4, "Y")
        res = bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=segs,
            radius1=radius,
            radius2=radius,
            depth=length,
            matrix=rot,
        )
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = mat_idx

    # Twin wooden flanges
    add_x_cyl(-half_w, -inner_x, flange_r, 32, 0)
    add_x_cyl(inner_x, half_w, flange_r, 32, 0)

    # Inner wooden core drum
    add_x_cyl(-inner_x, inner_x, 0.26, 24, 0)

    # Coiled dark power cable wraps (10 ribbed turns)
    wraps = 10
    span = (inner_x * 2.0) - 0.04
    step = span / wraps
    cable_r = 0.43
    for i in range(wraps):
        cx0 = -inner_x + 0.02 + i * step
        cx1 = cx0 + step * 0.86
        r_turn = cable_r + (0.008 if i % 2 == 0 else -0.004)
        add_x_cyl(cx0, cx1, r_turn, 28, 2)

    # Steel hub plates & central arbor collars on outer faces
    add_x_cyl(-half_w - 0.008, -half_w + 0.002, 0.14, 16, 1)
    add_x_cyl(half_w - 0.002, half_w + 0.008, 0.14, 16, 1)
    add_x_cyl(-half_w - 0.022, half_w + 0.022, 0.055, 16, 1)

    # 4 steel tie-rod bolts around flange
    for k in range(4):
        ang = math.radians(45.0 + k * 90.0)
        ry = 0.36 * math.cos(ang)
        rz = hub_z + 0.36 * math.sin(ang)
        from mathutils import Matrix

        rot = Matrix.Translation((0.0, ry, rz)) @ Matrix.Rotation(math.pi * 0.5, 4, "Y")
        res = bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=8,
            radius1=0.016,
            radius2=0.016,
            depth=(half_w * 2.0 + 0.03),
            matrix=rot,
        )
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = 1

    obj = _finalize_bmesh_object("cable_reel", bm, [wood_mat, steel_mat, cable_mat])
    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    bmin = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    bmax = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    export_godot_glb(str(out_path))
    print(f"[cable_reel] tris={tri_count} bbox_blender=({bmin.x:.3f}..{bmax.x:.3f}, {bmin.y:.3f}..{bmax.y:.3f}, {bmin.z:.3f}..{bmax.z:.3f}) -> {out_path}")


def build_ac_unit(out_path: Path) -> None:
    """Generate a 1.10m W x 0.85m H x 0.45m D industrial HVAC condenser unit."""
    clean_scene()
    body_mat = create_pbr_material("painted_metal", (0.48, 0.49, 0.47, 1.0), metallic=0.35, roughness=0.68)
    steel_mat = create_pbr_material("steel", (0.24, 0.22, 0.20, 1.0), metallic=0.82, roughness=0.58)
    dark_mat = create_pbr_material("dark_interior", (0.06, 0.06, 0.07, 1.0), metallic=0.2, roughness=0.85)

    bm = bmesh.new()
    from mathutils import Matrix

    # Blender Z-up: X = width (1.10m), Y = depth (0.45m, front at -Y), Z = height (0.85m)
    # 2 steel mounting feet (Z: 0.0 .. 0.06)
    for sx in (-0.36, 0.36):
        _add_box_bm(bm, (sx - 0.06, -0.24, 0.0), (sx + 0.06, 0.24, 0.06), 1, 0.004)

    # Main sheet-metal cabinet (Z: 0.06 .. 0.82)
    _add_box_bm(bm, (-0.54, -0.21, 0.06), (0.54, 0.21, 0.82), 0, 0.008)
    # Top overhang cap (Z: 0.82 .. 0.85)
    _add_box_bm(bm, (-0.55, -0.225, 0.82), (0.55, 0.225, 0.85), 0, 0.005)

    # Front recessed dark fan backing disc (at Y = -0.212)
    fan_cx, fan_cz = -0.16, 0.44
    rot_y = Matrix.Translation((fan_cx, -0.213, fan_cz)) @ Matrix.Rotation(math.pi * 0.5, 4, "X")
    res_back = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=24, radius1=0.26, radius2=0.26, depth=0.012, matrix=rot_y
    )
    for v in res_back["verts"]:
        for f in v.link_faces:
            f.material_index = 2

    # 5 angled fan blades
    for b in range(5):
        ang = math.radians(b * 72.0)
        bx = fan_cx + 0.13 * math.cos(ang)
        bz = fan_cz + 0.13 * math.sin(ang)
        _add_box_bm(bm, (bx - 0.045, -0.224, bz - 0.03), (bx + 0.045, -0.214, bz + 0.03), 1, 0.002)

    # Fan hub
    rot_hub = Matrix.Translation((fan_cx, -0.222, fan_cz)) @ Matrix.Rotation(math.pi * 0.5, 4, "X")
    res_hub = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=16, radius1=0.065, radius2=0.065, depth=0.025, matrix=rot_hub
    )
    for v in res_hub["verts"]:
        for f in v.link_faces:
            f.material_index = 1

    # Fan grille horizontal + vertical guard bars
    for offset in (-0.18, -0.09, 0.0, 0.09, 0.18):
        _add_box_bm(bm, (fan_cx - 0.26, -0.236, fan_cz + offset - 0.006), (fan_cx + 0.26, -0.228, fan_cz + offset + 0.006), 1)
        _add_box_bm(bm, (fan_cx + offset - 0.006, -0.236, fan_cz - 0.26), (fan_cx + offset + 0.006, -0.228, fan_cz + 0.26), 1)

    # Right front control/service panel plate
    _add_box_bm(bm, (0.20, -0.22, 0.14), (0.48, -0.21, 0.74), 0, 0.003)

    # Side louvered vents (6 horizontal slats on -X face)
    for i in range(6):
        lz = 0.20 + i * 0.09
        _add_box_bm(bm, (-0.555, -0.15, lz), (-0.54, 0.15, lz + 0.025), 1)

    # Right side (+X) refrigerant valve manifold box + 2 pipe stubs
    _add_box_bm(bm, (0.54, -0.10, 0.14), (0.59, 0.10, 0.34), 1, 0.004)
    for py in (-0.04, 0.04):
        rot_p = Matrix.Translation((0.57, py, 0.10))
        res_p = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=10, radius1=0.014, radius2=0.014, depth=0.10, matrix=rot_p
        )
        for v in res_p["verts"]:
            for f in v.link_faces:
                f.material_index = 1

    obj = _finalize_bmesh_object("ac_unit", bm, [body_mat, steel_mat, dark_mat])
    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    bmin = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    bmax = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    export_godot_glb(str(out_path))
    print(f"[ac_unit] tris={tri_count} bbox_blender=({bmin.x:.3f}..{bmax.x:.3f}, {bmin.y:.3f}..{bmax.y:.3f}, {bmin.z:.3f}..{bmax.z:.3f}) -> {out_path}")


def build_pump_skid(out_path: Path) -> None:
    """Generate a 1.50m L x 0.95m H x 0.72m W industrial pump-motor skid."""
    clean_scene()
    painted_mat = create_pbr_material("painted_metal", (0.20, 0.34, 0.38, 1.0), metallic=0.45, roughness=0.62)
    steel_mat = create_pbr_material("steel", (0.24, 0.22, 0.20, 1.0), metallic=0.82, roughness=0.58)

    bm = bmesh.new()
    from mathutils import Matrix

    def add_cyl(
        center: tuple[float, float, float],
        axis: str,
        radius: float,
        length: float,
        segs: int,
        mat_idx: int,
    ) -> None:
        mat = Matrix.Translation(center)
        if axis == "X":
            mat = mat @ Matrix.Rotation(math.pi * 0.5, 4, "Y")
        elif axis == "Y":
            mat = mat @ Matrix.Rotation(math.pi * 0.5, 4, "X")
        res = bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=segs,
            radius1=radius,
            radius2=radius,
            depth=length,
            matrix=mat,
        )
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = mat_idx

    # Steel skid base: 2 longitudinal rails + 3 cross members (X[-0.75, 0.75], Y[-0.36, 0.36], Z[0, 0.12])
    for sy in (-0.31, 0.31):
        _add_box_bm(bm, (-0.75, sy - 0.05, 0.0), (0.75, sy + 0.05, 0.12), 1, 0.005)
    for sx in (-0.68, 0.0, 0.68):
        _add_box_bm(bm, (sx - 0.05, -0.26, 0.02), (sx + 0.05, 0.26, 0.12), 1, 0.004)
    # Skid deck plate
    _add_box_bm(bm, (-0.72, -0.32, 0.10), (0.72, 0.32, 0.14), 1, 0.003)

    # Motor mounting plinth + electric motor body (X[-0.60, -0.08], axis Z=0.36)
    _add_box_bm(bm, (-0.56, -0.20, 0.14), (-0.12, 0.20, 0.20), 0, 0.003)
    add_cyl((-0.34, 0.0, 0.37), "X", 0.18, 0.44, 24, 0)
    # Cooling fins along motor barrel
    for i in range(8):
        ang = math.radians(i * 45.0)
        fy = 0.185 * math.cos(ang)
        fz = 0.37 + 0.185 * math.sin(ang)
        _add_box_bm(bm, (-0.50, fy - 0.012, fz - 0.012), (-0.18, fy + 0.012, fz + 0.012), 0)
    # Rear fan cowl + top terminal box
    add_cyl((-0.60, 0.0, 0.37), "X", 0.185, 0.12, 24, 1)
    _add_box_bm(bm, (-0.42, -0.07, 0.52), (-0.26, 0.07, 0.63), 1, 0.004)

    # Shaft coupling guard (X[-0.12, 0.10])
    add_cyl((-0.01, 0.0, 0.37), "X", 0.085, 0.24, 16, 1)

    # Centrifugal pump volute + pedestal (X[0.10, 0.46])
    _add_box_bm(bm, (0.14, -0.16, 0.14), (0.42, 0.16, 0.24), 1, 0.003)
    add_cyl((0.28, 0.0, 0.39), "X", 0.21, 0.18, 24, 0)

    # Axial intake pipe + flange (+X end)
    add_cyl((0.50, 0.0, 0.39), "X", 0.085, 0.26, 16, 1)
    add_cyl((0.63, 0.0, 0.39), "X", 0.13, 0.03, 16, 1)

    # Vertical discharge pipe + flange + elbow cap (Z[0.52, 0.95])
    add_cyl((0.28, 0.0, 0.68), "Z", 0.075, 0.34, 16, 1)
    add_cyl((0.28, 0.0, 0.85), "Z", 0.12, 0.03, 16, 1)
    add_cyl((0.28, 0.0, 0.91), "Z", 0.07, 0.08, 16, 1)

    # Pressure gauge stem + dial
    add_cyl((0.28, -0.14, 0.62), "Z", 0.015, 0.10, 10, 1)
    add_cyl((0.28, -0.14, 0.70), "Y", 0.055, 0.03, 16, 1)

    obj = _finalize_bmesh_object("pump_skid", bm, [painted_mat, steel_mat])
    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    bmin = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    bmax = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    export_godot_glb(str(out_path))
    print(f"[pump_skid] tris={tri_count} bbox_blender=({bmin.x:.3f}..{bmax.x:.3f}, {bmin.y:.3f}..{bmax.y:.3f}, {bmin.z:.3f}..{bmax.z:.3f}) -> {out_path}")


def build_fluorescent_light(out_path: Path) -> None:
    """Generate a 1.50m L x 0.28m W x 0.49m H twin-tube industrial workshop light fixture."""
    clean_scene()
    hood_mat = create_pbr_material("painted_metal", (0.34, 0.37, 0.36, 1.0), metallic=0.45, roughness=0.65)
    steel_mat = create_pbr_material("steel", (0.24, 0.22, 0.20, 1.0), metallic=0.82, roughness=0.58)
    tube_mat = create_pbr_material("tube_glass", (0.86, 0.88, 0.84, 1.0), metallic=0.0, roughness=0.28)

    bm = bmesh.new()
    from mathutils import Matrix

    # Fixture hood centered on X[-0.75, 0.75], Y[-0.14, 0.14], Z[0.0, 0.14]
    # Top ballast spine (Z: 0.08 .. 0.14)
    _add_box_bm(bm, (-0.75, -0.055, 0.08), (0.75, 0.055, 0.14), 0, 0.003)

    # Reflector hood upper plate + angled side skirts
    _add_box_bm(bm, (-0.75, -0.11, 0.065), (0.75, 0.11, 0.085), 0, 0.002)
    for sy in (-0.125, 0.125):
        y0 = sy - 0.015 if sy < 0 else sy - 0.015
        _add_box_bm(bm, (-0.75, y0, 0.015), (0.75, y0 + 0.03, 0.075), 0, 0.002)

    # End caps (tombstone housing) at X = +-0.735
    for sx in (-0.735, 0.735):
        _add_box_bm(bm, (sx - 0.015, -0.14, 0.005), (sx + 0.015, 0.14, 0.095), 1, 0.002)

    # Twin T8 fluorescent tubes (radius 0.016m, length 1.44m)
    for ty in (-0.052, 0.052):
        mat = Matrix.Translation((0.0, ty, 0.032)) @ Matrix.Rotation(math.pi * 0.5, 4, "Y")
        res = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=16, radius1=0.016, radius2=0.016, depth=1.44, matrix=mat
        )
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = 2

    # Twin suspension rods + ceiling mount plates (Z: 0.14 .. 0.49)
    for rx in (-0.52, 0.52):
        mat_r = Matrix.Translation((rx, 0.0, 0.31))
        res_r = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=10, radius1=0.008, radius2=0.008, depth=0.34, matrix=mat_r
        )
        for v in res_r["verts"]:
            for f in v.link_faces:
                f.material_index = 1
        _add_box_bm(bm, (rx - 0.04, -0.04, 0.475), (rx + 0.04, 0.04, 0.49), 1, 0.002)

    obj = _finalize_bmesh_object("fluorescent_light", bm, [hood_mat, steel_mat, tube_mat])
    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    bmin = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    bmax = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    export_godot_glb(str(out_path))
    print(f"[fluorescent_light] tris={tri_count} bbox_blender=({bmin.x:.3f}..{bmax.x:.3f}, {bmin.y:.3f}..{bmax.y:.3f}, {bmin.z:.3f}..{bmax.z:.3f}) -> {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate factory utility prop GLBs.")
    parser.add_argument(
        "--asset",
        required=True,
        choices=["wooden_pallet", "cable_reel", "ac_unit", "pump_skid", "fluorescent_light"],
        help="Prop asset to generate.",
    )
    args, _ = parser.parse_known_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])

    if args.asset == "wooden_pallet":
        build_wooden_pallet(_REPO_ROOT / "assets/models/props/factory_yard/wooden_pallet.glb")
    elif args.asset == "cable_reel":
        build_cable_reel(_REPO_ROOT / "assets/models/props/factory_yard/cable_reel.glb")
    elif args.asset == "ac_unit":
        build_ac_unit(_REPO_ROOT / "assets/models/props/factory_yard/ac_unit.glb")
    elif args.asset == "pump_skid":
        build_pump_skid(_REPO_ROOT / "assets/models/props/factory_workshop/pump_skid.glb")
    elif args.asset == "fluorescent_light":
        build_fluorescent_light(_REPO_ROOT / "assets/models/props/factory_workshop/fluorescent_light.glb")


if __name__ == "__main__":
    main()
