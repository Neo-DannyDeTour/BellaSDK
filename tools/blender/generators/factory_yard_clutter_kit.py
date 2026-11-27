"""Procedural Blender generator for factory yard clutter prop GLBs.

Builds post-Soviet industrial yard clutter props one asset at a time via `--asset <name>`:
- plastic_crate_01: 0.60m x 0.35m x 0.40m solid ribbed stackable HDPE crate
- plastic_crate_02: 0.60m x 0.35m x 0.40m vented/slotted HDPE crate
- plastic_crate_03: 0.60m x 0.50m x 0.40m tall reinforced HDPE crate
- traffic_cone: 0.70m weathered PVC safety cone w/ weighted square base & collar bands

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


def _add_tapered_ring_bm(
    bm: bmesh.types.BMesh,
    z0: float,
    z1: float,
    r0: float,
    r1: float,
    segs: int,
    mat_idx: int = 0,
    cap_bottom: bool = False,
    cap_top: bool = False,
) -> None:
    """Append a Z-aligned frustum ring (or cylinder if r0 == r1) to a BMesh."""
    ring0 = []
    ring1 = []
    for i in range(segs):
        ang = (2.0 * math.pi * i) / segs
        ca = math.cos(ang)
        sa = math.sin(ang)
        ring0.append(bm.verts.new((r0 * ca, r0 * sa, z0)))
        ring1.append(bm.verts.new((r1 * ca, r1 * sa, z1)))

    for i in range(segs):
        ni = (i + 1) % segs
        f = bm.faces.new([ring0[i], ring0[ni], ring1[ni], ring1[i]])
        f.material_index = mat_idx

    if cap_bottom:
        f_bot = bm.faces.new(list(reversed(ring0)))
        f_bot.material_index = mat_idx
    if cap_top:
        f_top = bm.faces.new(ring1)
        f_top.material_index = mat_idx


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


def _report_and_export(name: str, obj: bpy.types.Object, out_path: Path) -> None:
    """Print tri count + Blender bounding box and export GLB."""
    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    bmin = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    bmax = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    export_godot_glb(str(out_path), export_animations=False)
    print(
        f"[{name}] tris={tri_count} "
        f"bbox_blender=({bmin.x:.3f}..{bmax.x:.3f}, {bmin.y:.3f}..{bmax.y:.3f}, "
        f"{bmin.z:.3f}..{bmax.z:.3f}) -> {out_path}"
    )


def _add_crate_shell_and_rim(
    bm: bmesh.types.BMesh,
    width: float,
    depth: float,
    height: float,
    wall_t: float,
    base_h: float,
    rim_h: float,
    mat_idx: int = 0,
) -> None:
    """Build stepped stacking base, hollow solid walls/floor, and top stacking rim."""
    hx = width * 0.5
    hy = depth * 0.5
    body_hx = hx - 0.012
    body_hy = hy - 0.012
    foot_hx = hx - 0.024
    foot_hy = hy - 0.024

    # Stepped stacking foot skirt (sits inside lower crate rim when stacked)
    _add_box_bm(bm, (-foot_hx, -foot_hy, 0.0), (foot_hx, foot_hy, base_h), mat_idx)

    # Solid floor slab above foot
    floor_top = base_h + 0.018
    _add_box_bm(bm, (-body_hx, -body_hy, base_h), (body_hx, body_hy, floor_top), mat_idx)

    # Four solid enclosure walls up to rim bottom
    rim_z0 = height - rim_h
    _add_box_bm(bm, (-body_hx, -body_hy, floor_top), (body_hx, -body_hy + wall_t, rim_z0), mat_idx)
    _add_box_bm(bm, (-body_hx, body_hy - wall_t, floor_top), (body_hx, body_hy, rim_z0), mat_idx)
    _add_box_bm(
        bm,
        (-body_hx, -body_hy + wall_t, floor_top),
        (-body_hx + wall_t, body_hy - wall_t, rim_z0),
        mat_idx,
    )
    _add_box_bm(
        bm,
        (body_hx - wall_t, -body_hy + wall_t, floor_top),
        (body_hx, body_hy - wall_t, rim_z0),
        mat_idx,
    )

    # Top flared stacking collar rim (4 perimeter bars enclosing open top)
    rim_in_x = body_hx - wall_t - 0.004
    rim_in_y = body_hy - wall_t - 0.004
    _add_box_bm(bm, (-hx, -hy, rim_z0), (hx, -rim_in_y, height), mat_idx, chamfer=0.003)
    _add_box_bm(bm, (-hx, rim_in_y, rim_z0), (hx, hy, height), mat_idx, chamfer=0.003)
    _add_box_bm(bm, (-hx, -rim_in_y, rim_z0), (-rim_in_x, rim_in_y, height), mat_idx, chamfer=0.003)
    _add_box_bm(bm, (rim_in_x, -rim_in_y, rim_z0), (hx, rim_in_y, height), mat_idx, chamfer=0.003)


def build_plastic_crate_01(out_path: Path) -> None:
    """Generate a 0.60m x 0.35m x 0.40m solid ribbed stackable HDPE crate."""
    clean_scene()
    hdpe_mat = create_pbr_material(
        "hdpe_weathered_plastic",
        (0.24, 0.27, 0.22, 1.0),
        metallic=0.0,
        roughness=0.72,
    )

    bm = bmesh.new()
    width, depth, height = 0.60, 0.40, 0.35
    hx, hy = width * 0.5, depth * 0.5
    body_hx, body_hy = hx - 0.012, hy - 0.012
    base_h, rim_h = 0.024, 0.032
    rib_z0, rib_z1 = base_h + 0.004, height - rim_h

    _add_crate_shell_and_rim(bm, width, depth, height, wall_t=0.016, base_h=base_h, rim_h=rim_h)

    # 4 heavy vertical corner pilasters (+0.009m proud, prouder than all ribs)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            x0 = sx * body_hx - (0.028 if sx > 0 else 0.009)
            x1 = sx * body_hx + (0.009 if sx > 0 else 0.028)
            y0 = sy * body_hy - (0.028 if sy > 0 else 0.009)
            y1 = sy * body_hy + (0.009 if sy > 0 else 0.028)
            _add_box_bm(bm, (x0, y0, rib_z0), (x1, y1, rib_z1), 0)

    # 5 vertical reinforcing ribs on each long face (-Y / +Y, +0.005m proud)
    for rx in (-0.19, -0.095, 0.0, 0.095, 0.19):
        _add_box_bm(bm, (rx - 0.009, -body_hy - 0.005, rib_z0), (rx + 0.009, -body_hy + 0.002, rib_z1), 0)
        _add_box_bm(bm, (rx - 0.009, body_hy - 0.002, rib_z0), (rx + 0.009, body_hy + 0.005, rib_z1), 0)

    # Horizontal mid-band belt (+0.0075m proud -> wraps cleanly over vertical ribs, under corner pilasters)
    mid_z0, mid_z1 = 0.165, 0.187
    _add_box_bm(bm, (-body_hx - 0.0075, -body_hy - 0.0075, mid_z0), (body_hx + 0.0075, -body_hy + 0.002, mid_z1), 0)
    _add_box_bm(bm, (-body_hx - 0.0075, body_hy - 0.002, mid_z0), (body_hx + 0.0075, body_hy + 0.0075, mid_z1), 0)
    _add_box_bm(bm, (-body_hx - 0.0075, -body_hy + 0.002, mid_z0), (-body_hx + 0.002, body_hy - 0.002, mid_z1), 0)
    _add_box_bm(bm, (body_hx - 0.002, -body_hy + 0.002, mid_z0), (body_hx + 0.0075, body_hy - 0.002, mid_z1), 0)

    # Short-face vertical ribs (+0.005m proud) + ergonomic grab-handle hoods (+0.011m proud)
    for ry in (-0.085, 0.085):
        _add_box_bm(bm, (-body_hx - 0.005, ry - 0.009, rib_z0), (-body_hx + 0.002, ry + 0.009, rib_z1), 0)
        _add_box_bm(bm, (body_hx - 0.002, ry - 0.009, rib_z0), (body_hx + 0.005, ry + 0.009, rib_z1), 0)

    for sx in (-1.0, 1.0):
        gx0 = sx * body_hx - (0.002 if sx > 0 else 0.011)
        gx1 = sx * body_hx + (0.011 if sx > 0 else 0.002)
        _add_box_bm(bm, (gx0, -0.072, 0.255), (gx1, 0.072, 0.295), 0)

    obj = _finalize_bmesh_object("plastic_crate_01", bm, [hdpe_mat])
    _report_and_export("plastic_crate_01", obj, out_path)


def build_plastic_crate_02(out_path: Path) -> None:
    """Generate a 0.60m x 0.35m x 0.40m vented/slotted HDPE crate."""
    clean_scene()
    hdpe_mat = create_pbr_material(
        "hdpe_weathered_plastic",
        (0.24, 0.27, 0.22, 1.0),
        metallic=0.0,
        roughness=0.72,
    )

    bm = bmesh.new()
    width, depth, height = 0.60, 0.40, 0.35
    hx, hy = width * 0.5, depth * 0.5
    body_hx, body_hy = hx - 0.012, hy - 0.012
    wall_t = 0.016
    base_h = 0.022
    rim_z0 = height - 0.030

    # Stepped stacking foot frame (4 perimeter rails + 4 cross-grid floor slats for vented bottom)
    foot_hx, foot_hy = hx - 0.024, hy - 0.024
    _add_box_bm(bm, (-foot_hx, -foot_hy, 0.0), (foot_hx, -foot_hy + 0.028, base_h), 0)
    _add_box_bm(bm, (-foot_hx, foot_hy - 0.028, 0.0), (foot_hx, foot_hy, base_h), 0)
    _add_box_bm(bm, (-foot_hx, -foot_hy + 0.028, 0.0), (-foot_hx + 0.028, foot_hy - 0.028, base_h), 0)
    _add_box_bm(bm, (foot_hx - 0.028, -foot_hy + 0.028, 0.0), (foot_hx, foot_hy - 0.028, base_h), 0)

    # Vented floor lattice slats (Z: 0.016 .. 0.034)
    for ry in (-0.11, 0.0, 0.11):
        _add_box_bm(bm, (-body_hx + 0.01, ry - 0.016, 0.016), (body_hx - 0.01, ry + 0.016, 0.034), 0)
    for rx in (-0.18, -0.06, 0.06, 0.18):
        _add_box_bm(bm, (rx - 0.016, -body_hy + 0.01, 0.020), (rx + 0.016, body_hy - 0.01, 0.036), 0)

    # Lower solid perimeter wall skirt (Z: 0.022 .. 0.092)
    low_z0, low_z1 = base_h, 0.092
    _add_box_bm(bm, (-body_hx, -body_hy, low_z0), (body_hx, -body_hy + wall_t, low_z1), 0)
    _add_box_bm(bm, (-body_hx, body_hy - wall_t, low_z0), (body_hx, body_hy, low_z1), 0)
    _add_box_bm(bm, (-body_hx, -body_hy + wall_t, low_z0), (-body_hx + wall_t, body_hy - wall_t, low_z1), 0)
    _add_box_bm(bm, (body_hx - wall_t, -body_hy + wall_t, low_z0), (body_hx, body_hy - wall_t, low_z1), 0)

    # Upper solid perimeter band (Z: 0.245 .. rim_z0) — short walls split for handle slot
    up_z0 = 0.245
    _add_box_bm(bm, (-body_hx, -body_hy, up_z0), (body_hx, -body_hy + wall_t, rim_z0), 0)
    _add_box_bm(bm, (-body_hx, body_hy - wall_t, up_z0), (body_hx, body_hy, rim_z0), 0)
    for sx in (-1.0, 1.0):
        wx0 = sx * body_hx - (wall_t if sx > 0 else 0.0)
        wx1 = sx * body_hx + (0.0 if sx > 0 else wall_t)
        # Side wings flanking open handhold slot (Y: -0.075 .. 0.075)
        _add_box_bm(bm, (wx0, -body_hy + wall_t, up_z0), (wx1, -0.075, rim_z0), 0)
        _add_box_bm(bm, (wx0, 0.075, up_z0), (wx1, body_hy - wall_t, rim_z0), 0)
        # Lower sill below handhold
        _add_box_bm(bm, (wx0, -0.075, up_z0), (wx1, 0.075, 0.262), 0)

    # 4 corner structural columns (Z: low_z1 .. up_z0)
    col_w = 0.044
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx0 = body_hx - col_w if sx > 0 else -body_hx
            cx1 = body_hx if sx > 0 else -body_hx + col_w
            cy0 = body_hy - col_w if sy > 0 else -body_hy
            cy1 = body_hy if sy > 0 else -body_hy + col_w
            _add_box_bm(bm, (cx0, cy0, low_z1), (cx1, cy1, up_z0), 0)

    # Vertical slotted mullions along long faces (Z: low_z1 .. up_z0) -> 6 open slots/side
    for rx in (-0.195, -0.117, -0.039, 0.039, 0.117, 0.195):
        _add_box_bm(bm, (rx - 0.011, -body_hy, low_z1), (rx + 0.011, -body_hy + wall_t, up_z0), 0)
        _add_box_bm(bm, (rx - 0.011, body_hy - wall_t, low_z1), (rx + 0.011, body_hy, up_z0), 0)

    # Vertical slotted mullions along short faces -> 4 open slots/side
    for ry in (-0.095, 0.0, 0.095):
        _add_box_bm(bm, (-body_hx, ry - 0.011, low_z1), (-body_hx + wall_t, ry + 0.011, up_z0), 0)
        _add_box_bm(bm, (body_hx - wall_t, ry - 0.011, low_z1), (body_hx, ry + 0.011, up_z0), 0)

    # Horizontal mid-tie ribs on vented zone (proud +0.005m outside, embedded 2mm inside wall, clear of corner X)
    mid_z0, mid_z1 = 0.158, 0.178
    _add_box_bm(bm, (-body_hx + 0.002, -body_hy - 0.005, mid_z0), (body_hx - 0.002, -body_hy + 0.002, mid_z1), 0)
    _add_box_bm(bm, (-body_hx + 0.002, body_hy - 0.002, mid_z0), (body_hx - 0.002, body_hy + 0.005, mid_z1), 0)

    # Top flared stacking rim (Z: rim_z0 .. height)
    rim_in_x = body_hx - wall_t - 0.004
    rim_in_y = body_hy - wall_t - 0.004
    _add_box_bm(bm, (-hx, -hy, rim_z0), (hx, -rim_in_y, height), 0, chamfer=0.003)
    _add_box_bm(bm, (-hx, rim_in_y, rim_z0), (hx, hy, height), 0, chamfer=0.003)
    _add_box_bm(bm, (-hx, -rim_in_y, rim_z0), (-rim_in_x, rim_in_y, height), 0, chamfer=0.003)
    _add_box_bm(bm, (rim_in_x, -rim_in_y, rim_z0), (hx, rim_in_y, height), 0, chamfer=0.003)

    obj = _finalize_bmesh_object("plastic_crate_02", bm, [hdpe_mat])
    _report_and_export("plastic_crate_02", obj, out_path)


def build_plastic_crate_03(out_path: Path) -> None:
    """Generate a 0.60m x 0.50m x 0.40m tall reinforced HDPE crate."""
    clean_scene()
    hdpe_mat = create_pbr_material(
        "hdpe_weathered_plastic",
        (0.24, 0.27, 0.22, 1.0),
        metallic=0.0,
        roughness=0.72,
    )

    bm = bmesh.new()
    width, depth, height = 0.60, 0.40, 0.50
    hx, hy = width * 0.5, depth * 0.5
    body_hx, body_hy = hx - 0.013, hy - 0.013
    base_h, rim_h = 0.030, 0.038
    rib_z0, rib_z1 = base_h + 0.004, height - rim_h

    foot_hx, foot_hy = hx - 0.024, hy - 0.024
    _add_crate_shell_and_rim(bm, width, depth, height, wall_t=0.018, base_h=base_h, rim_h=rim_h)

    # Bottom perimeter reinforcing skid ribs along X (outside foot at Z: 0.004 .. base_h)
    for sy in (-body_hy + 0.008, body_hy - 0.008):
        _add_box_bm(bm, (-foot_hx + 0.004, sy - 0.008, 0.004), (foot_hx - 0.004, sy + 0.008, base_h - 0.002), 0)

    # 4 heavy corner buttress columns (+0.010m proud, prouder than all ribs)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            x0 = sx * body_hx - (0.034 if sx > 0 else 0.010)
            x1 = sx * body_hx + (0.010 if sx > 0 else 0.034)
            y0 = sy * body_hy - (0.034 if sy > 0 else 0.010)
            y1 = sy * body_hy + (0.010 if sy > 0 else 0.034)
            _add_box_bm(bm, (x0, y0, rib_z0), (x1, y1, rib_z1), 0)

    # Dual horizontal reinforcing belt ribs (+0.008m proud -> wraps over vertical ribs, under corner pilasters)
    for bz in (0.165, 0.325):
        bz0, bz1 = bz, bz + 0.024
        _add_box_bm(bm, (-body_hx - 0.008, -body_hy - 0.008, bz0), (body_hx + 0.008, -body_hy + 0.002, bz1), 0)
        _add_box_bm(bm, (-body_hx - 0.008, body_hy - 0.002, bz0), (body_hx + 0.008, body_hy + 0.008, bz1), 0)
        _add_box_bm(bm, (-body_hx - 0.008, -body_hy + 0.002, bz0), (-body_hx + 0.002, body_hy - 0.002, bz1), 0)
        _add_box_bm(bm, (body_hx - 0.002, -body_hy + 0.002, bz0), (body_hx + 0.008, body_hy - 0.002, bz1), 0)

    # 4 heavy vertical gusset ribs on each long face (-Y / +Y, +0.0055m proud)
    for rx in (-0.18, -0.06, 0.06, 0.18):
        _add_box_bm(bm, (rx - 0.011, -body_hy - 0.0055, rib_z0), (rx + 0.011, -body_hy + 0.002, rib_z1), 0)
        _add_box_bm(bm, (rx - 0.011, body_hy - 0.002, rib_z0), (rx + 0.011, body_hy + 0.0055, rib_z1), 0)

    # Label card pocket ribs on center of long faces (+0.010m proud, between center vertical ribs)
    for sy in (-1.0, 1.0):
        ly0 = sy * body_hy - (0.002 if sy > 0 else 0.010)
        ly1 = sy * body_hy + (0.010 if sy > 0 else 0.002)
        _add_box_bm(bm, (-0.045, ly0, 0.21), (0.045, ly1, 0.305), 0)

    # Short-face vertical ribs (+0.0055m proud) + heavy grip handle pockets (+0.012m proud)
    for ry in (-0.095, 0.095):
        _add_box_bm(bm, (-body_hx - 0.0055, ry - 0.010, rib_z0), (-body_hx + 0.002, ry + 0.010, rib_z1), 0)
        _add_box_bm(bm, (body_hx - 0.002, ry - 0.010, rib_z0), (body_hx + 0.0055, ry + 0.010, rib_z1), 0)

    for sx in (-1.0, 1.0):
        gx0 = sx * body_hx - (0.002 if sx > 0 else 0.012)
        gx1 = sx * body_hx + (0.012 if sx > 0 else 0.002)
        _add_box_bm(bm, (gx0, -0.080, 0.385), (gx1, 0.080, 0.435), 0)

    obj = _finalize_bmesh_object("plastic_crate_03", bm, [hdpe_mat])
    _report_and_export("plastic_crate_03", obj, out_path)


def build_traffic_cone(out_path: Path) -> None:
    """Generate a 0.70m weathered PVC safety cone w/ weighted square base & collar bands."""
    clean_scene()
    orange_mat = create_pbr_material(
        "pvc_safety_orange",
        (0.84, 0.28, 0.04, 1.0),
        metallic=0.0,
        roughness=0.58,
    )
    base_mat = create_pbr_material(
        "rusted_steel",
        (0.10, 0.10, 0.11, 1.0),
        metallic=0.25,
        roughness=0.82,
    )
    collar_mat = create_pbr_material(
        "collar_band",
        (0.82, 0.81, 0.76, 1.0),
        metallic=0.08,
        roughness=0.45,
    )

    bm = bmesh.new()
    segs = 12

    # Two-tier heavy weighted square base (0.38m x 0.38m, Z: 0.0 .. 0.044) -> mat 1
    _add_box_bm(bm, (-0.19, -0.19, 0.0), (0.19, 0.19, 0.018), 1)
    _add_box_bm(bm, (-0.165, -0.165, 0.018), (0.165, 0.165, 0.044), 1)

    # Molded octagonal/round base collar transition (Z: 0.044 .. 0.068) -> mat 1
    _add_tapered_ring_bm(bm, 0.044, 0.068, 0.155, 0.138, segs, mat_idx=1, cap_top=True)

    # Lower safety-orange cone shaft (Z: 0.066 .. 0.295) -> mat 0
    _add_tapered_ring_bm(bm, 0.066, 0.295, 0.134, 0.097, segs, mat_idx=0, cap_bottom=True)

    # Lower retroreflective collar band (Z: 0.295 .. 0.395, +2mm proud step) -> mat 2
    _add_tapered_ring_bm(bm, 0.295, 0.295, 0.097, 0.099, segs, mat_idx=2)
    _add_tapered_ring_bm(bm, 0.295, 0.395, 0.099, 0.083, segs, mat_idx=2)
    _add_tapered_ring_bm(bm, 0.395, 0.395, 0.083, 0.081, segs, mat_idx=2)

    # Mid safety-orange gap (Z: 0.395 .. 0.455) -> mat 0
    _add_tapered_ring_bm(bm, 0.395, 0.455, 0.081, 0.071, segs, mat_idx=0)

    # Upper retroreflective collar band (Z: 0.455 .. 0.555, +2mm proud step) -> mat 2
    _add_tapered_ring_bm(bm, 0.455, 0.455, 0.071, 0.073, segs, mat_idx=2)
    _add_tapered_ring_bm(bm, 0.455, 0.555, 0.073, 0.057, segs, mat_idx=2)
    _add_tapered_ring_bm(bm, 0.555, 0.555, 0.057, 0.055, segs, mat_idx=2)

    # Upper safety-orange cone shaft + rounded top lip + hollow top bore (Z: 0.555 .. 0.700) -> mat 0
    _add_tapered_ring_bm(bm, 0.555, 0.692, 0.055, 0.032, segs, mat_idx=0)
    _add_tapered_ring_bm(bm, 0.692, 0.700, 0.032, 0.028, segs, mat_idx=0)
    _add_tapered_ring_bm(bm, 0.700, 0.700, 0.028, 0.019, segs, mat_idx=0)
    _add_tapered_ring_bm(bm, 0.700, 0.640, 0.019, 0.023, segs, mat_idx=0, cap_top=True)

    obj = _finalize_bmesh_object("traffic_cone", bm, [orange_mat, base_mat, collar_mat])
    _report_and_export("traffic_cone", obj, out_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate factory yard clutter prop GLBs.")
    parser.add_argument(
        "--asset",
        required=True,
        choices=["plastic_crate_01", "plastic_crate_02", "plastic_crate_03", "traffic_cone"],
        help="Clutter prop asset to generate.",
    )
    args, _ = parser.parse_known_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])

    out_dir = _REPO_ROOT / "assets/models/props/factory_yard"
    if args.asset == "plastic_crate_01":
        build_plastic_crate_01(out_dir / "plastic_crate_01.glb")
    elif args.asset == "plastic_crate_02":
        build_plastic_crate_02(out_dir / "plastic_crate_02.glb")
    elif args.asset == "plastic_crate_03":
        build_plastic_crate_03(out_dir / "plastic_crate_03.glb")
    elif args.asset == "traffic_cone":
        build_traffic_cone(out_dir / "traffic_cone.glb")


if __name__ == "__main__":
    main()
