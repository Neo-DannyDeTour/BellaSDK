"""Procedural Blender generator for factory hero tower GLBs.

Builds post-Soviet industrial hero towers one asset at a time via `--asset <name>`:
- crane_tower: 18.0m tall steel lattice tower crane + slewing jib + counterweight
- network_tower: 12.0m tapered steel lattice telecom mast + dishes/antennas
- water_tank: 6.0m elevated cylindrical steel water tank + cross-braced legs + caged ladder

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
from mathutils import Matrix, Vector

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
        face = bm.faces.new([verts[i] for i in idx])
        face.material_index = mat_idx
        created_faces.append(face)

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


def _add_strut_bm(
    bm: bmesh.types.BMesh,
    p0: tuple[float, float, float] | Vector,
    p1: tuple[float, float, float] | Vector,
    width: float,
    mat_idx: int = 0,
    cap_ends: bool = True,
) -> None:
    """Append a square-section structural strut connecting p0 and p1."""
    v0 = Vector(p0)
    v1 = Vector(p1)
    delta = v1 - v0
    if delta.length < 1e-5:
        return
    tangent = delta.normalized()
    up_ref = Vector((0.0, 0.0, 1.0)) if abs(tangent.z) < 0.95 else Vector((1.0, 0.0, 0.0))
    side = tangent.cross(up_ref).normalized()
    up = side.cross(tangent).normalized()

    hw = width * 0.5
    offsets = (
        (-side - up) * hw,
        (side - up) * hw,
        (side + up) * hw,
        (-side + up) * hw,
    )
    ring0 = [bm.verts.new(v0 + off) for off in offsets]
    ring1 = [bm.verts.new(v1 + off) for off in offsets]

    for i in range(4):
        j = (i + 1) % 4
        face = bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
        face.material_index = mat_idx

    if cap_ends:
        f0 = bm.faces.new((ring0[3], ring0[2], ring0[1], ring0[0]))
        f0.material_index = mat_idx
        f1 = bm.faces.new((ring1[0], ring1[1], ring1[2], ring1[3]))
        f1.material_index = mat_idx


def _add_cyl_bm(
    bm: bmesh.types.BMesh,
    p0: tuple[float, float, float] | Vector,
    p1: tuple[float, float, float] | Vector,
    r0: float,
    r1: float,
    segs: int,
    mat_idx: int = 0,
    cap_ends: bool = True,
) -> None:
    """Append a cylinder or frustum aligned from p0 (r0) to p1 (r1)."""
    v0 = Vector(p0)
    v1 = Vector(p1)
    delta = v1 - v0
    length = delta.length
    if length < 1e-5:
        return

    mid = (v0 + v1) * 0.5
    rot = delta.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    mat = Matrix.Translation(mid) @ rot

    res = bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=length,
        matrix=mat,
    )
    for vert in res["verts"]:
        for face in vert.link_faces:
            face.material_index = mat_idx


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
    smooth_sharp_deg: float | None = None,
) -> bpy.types.Object:
    """Convert BMesh to mesh object, apply UVs, normals, and materials."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_box_uvs(bm, tile_meters=1.0)

    if smooth_sharp_deg is not None:
        thresh = math.radians(smooth_sharp_deg)
        sharp_edges = [
            e
            for e in bm.edges
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > thresh
        ]
        if sharp_edges:
            bmesh.ops.split_edges(bm, edges=sharp_edges)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    if smooth_sharp_deg is not None:
        for poly in mesh.polygons:
            poly.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)
    return obj


def _log_export_stats(name: str, obj: bpy.types.Object, out_path: Path) -> None:
    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    bmin = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    bmax = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    size = bmax - bmin
    print(
        f"[{name}] tris={tri_count} "
        f"size=({size.x:.3f}m x {size.y:.3f}m x {size.z:.3f}m) "
        f"bbox_blender=({bmin.x:.3f}..{bmax.x:.3f}, {bmin.y:.3f}..{bmax.y:.3f}, "
        f"{bmin.z:.3f}..{bmax.z:.3f}) -> {out_path}"
    )


def build_crane_tower(out_path: Path) -> None:
    """Generate an 18.0m tall steel lattice tower crane with slewing jib and counterweight."""
    clean_scene()
    galv_mat = create_pbr_material(
        "galvanized_lattice_steel", (0.44, 0.46, 0.47, 1.0), metallic=0.80, roughness=0.52
    )
    rust_mat = create_pbr_material(
        "rusted_steel", (0.26, 0.17, 0.13, 1.0), metallic=0.72, roughness=0.68
    )
    paint_mat = create_pbr_material(
        "painted_industrial_metal", (0.54, 0.39, 0.14, 1.0), metallic=0.35, roughness=0.62
    )
    # Slots: 0 = galvanized_lattice_steel, 1 = rusted_steel, 2 = painted_industrial_metal
    bm = bmesh.new()

    # 1. Cruciform ballast base resting cleanly at Z=0.0
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            # Footing pads
            _add_box_bm(
                bm,
                (sx * 1.55 - 0.30, sy * 1.55 - 0.30, 0.0),
                (sx * 1.55 + 0.30, sy * 1.55 + 0.30, 0.14),
                1,
                0.01,
            )
            # Diagonal outrigger I-beam arms
            _add_strut_bm(bm, (sx * 1.55, sy * 1.55, 0.24), (sx * 0.55, sy * 0.55, 0.34), 0.22, 1)

    # Central base chassis frame + 4 heavy ballast blocks (Z: 0.0 .. 1.38)
    _add_box_bm(bm, (-0.85, -0.85, 0.0), (0.85, 0.85, 0.36), 1, 0.01)
    for bx, by in ((-0.75, 0.0), (0.75, 0.0), (0.0, -0.75), (0.0, 0.75)):
        dx = 0.28 if bx != 0.0 else 0.76
        dy = 0.28 if by != 0.0 else 0.76
        _add_box_bm(bm, (bx - dx, by - dy, 0.36), (bx + dx, by + dy, 1.36), 2, 0.015)

    # 2. Vertical lattice mast (Z: 0.36 .. 13.86, 9 bays of 1.50m)
    mast_hw = 0.58
    z_mast_bot = 0.36
    bays = 9
    bay_h = 1.50
    z_mast_top = z_mast_bot + bays * bay_h  # 13.86m

    corners = [(-mast_hw, -mast_hw), (mast_hw, -mast_hw), (mast_hw, mast_hw), (-mast_hw, mast_hw)]
    for cx, cy in corners:
        _add_box_bm(bm, (cx - 0.055, cy - 0.055, z_mast_bot), (cx + 0.055, cy + 0.055, z_mast_top), 0)

    for b in range(bays + 1):
        z = z_mast_bot + b * bay_h
        for i in range(4):
            c0 = corners[i]
            c1 = corners[(i + 1) % 4]
            _add_strut_bm(bm, (c0[0], c0[1], z), (c1[0], c1[1], z), 0.065, 0)

        if b < bays:
            z_next = z + bay_h
            for i in range(4):
                c0 = corners[i]
                c1 = corners[(i + 1) % 4]
                if (b + i) % 2 == 0:
                    _add_strut_bm(bm, (c0[0], c0[1], z), (c1[0], c1[1], z_next), 0.052, 0)
                else:
                    _add_strut_bm(bm, (c1[0], c1[1], z), (c0[0], c0[1], z_next), 0.052, 0)

    # Internal mast access ladder along +X inner face
    for ly in (-0.18, 0.18):
        _add_box_bm(bm, (0.42, ly - 0.018, z_mast_bot), (0.46, ly + 0.018, z_mast_top), 1)
    for r in range(26):
        rz = 0.80 + r * 0.50
        _add_strut_bm(bm, (0.44, -0.18, rz), (0.44, 0.18, rz), 0.025, 1)

    # 3. Slewing ring turntable & machinery deck (Z: 13.86 .. 14.48)
    _add_cyl_bm(bm, (0.0, 0.0, 13.86), (0.0, 0.0, 14.28), 0.68, 0.68, 16, 1)
    _add_box_bm(bm, (-0.78, -0.78, 14.28), (0.78, 0.78, 14.48), 2, 0.01)

    # Side-mounted operator cab on +X (Z: 14.25 .. 15.95)
    _add_box_bm(bm, (0.68, -0.58, 14.32), (1.58, 0.58, 15.86), 2, 0.015)
    # Cab roof visor + recessed dark window frame
    _add_box_bm(bm, (0.64, -0.72, 15.84), (1.64, 0.64, 15.96), 1, 0.01)
    _add_box_bm(bm, (0.78, -0.62, 14.88), (1.48, -0.56, 15.66), 1)
    _add_box_bm(bm, (1.56, -0.48, 14.88), (1.61, 0.48, 15.66), 1)
    # Cab support bracket
    _add_strut_bm(bm, (0.72, -0.40, 14.12), (1.48, -0.40, 14.36), 0.09, 1)
    _add_strut_bm(bm, (0.72, 0.40, 14.12), (1.48, 0.40, 14.36), 0.09, 1)

    # 4. Cathead A-frame peak (Z: 14.48 .. 18.00m exact top)
    apex = (0.0, 0.0, 17.86)
    for cx, cy in corners:
        _add_strut_bm(bm, (cx, cy, 14.48), apex, 0.095, 2)
    # Mid collar on cathead
    mid_z = 16.15
    mid_hw = mast_hw * 0.50
    mid_c = [(-mid_hw, -mid_hw), (mid_hw, -mid_hw), (mid_hw, mid_hw), (-mid_hw, mid_hw)]
    for i in range(4):
        c0 = mid_c[i]
        c1 = mid_c[(i + 1) % 4]
        _add_strut_bm(bm, (c0[0], c0[1], mid_z), (c1[0], c1[1], mid_z), 0.06, 0)
    # Peak sheave block reaching Z = 18.00m
    _add_box_bm(bm, (-0.18, -0.22, 17.74), (0.18, 0.22, 18.00), 1, 0.01)

    # 5. Main triangular lattice jib (-Y from Y=0.0 to Y=-11.20m, Z: 14.52 .. 15.56)
    jib_bays = 8
    jib_len = 11.20
    jib_step = jib_len / jib_bays
    jib_z_bot = 14.52
    jib_z_top = 15.56
    jib_hw = 0.48

    # 3 longitudinal chords
    _add_strut_bm(bm, (-jib_hw, 0.0, jib_z_bot), (-jib_hw * 0.65, -jib_len, jib_z_bot), 0.075, 2)
    _add_strut_bm(bm, (jib_hw, 0.0, jib_z_bot), (jib_hw * 0.65, -jib_len, jib_z_bot), 0.075, 2)
    _add_strut_bm(bm, (0.0, 0.0, jib_z_top), (0.0, -jib_len, jib_z_top - 0.28), 0.08, 2)

    def _jib_pts(idx: int) -> tuple[Vector, Vector, Vector]:
        t = idx / jib_bays
        y = -idx * jib_step
        hw = jib_hw * (1.0 - 0.35 * t)
        zt = jib_z_top - 0.28 * t
        return (
            Vector((-hw, y, jib_z_bot)),
            Vector((hw, y, jib_z_bot)),
            Vector((0.0, y, zt)),
        )

    for b in range(jib_bays + 1):
        p_l, p_r, p_t = _jib_pts(b)
        _add_strut_bm(bm, p_l, p_r, 0.05, 0)
        _add_strut_bm(bm, p_l, p_t, 0.05, 0)
        _add_strut_bm(bm, p_r, p_t, 0.05, 0)
        if b < jib_bays:
            n_l, n_r, n_t = _jib_pts(b + 1)
            if b % 2 == 0:
                _add_strut_bm(bm, p_l, n_t, 0.042, 0)
                _add_strut_bm(bm, p_r, n_t, 0.042, 0)
                _add_strut_bm(bm, p_l, n_r, 0.040, 0)
            else:
                _add_strut_bm(bm, p_t, n_l, 0.042, 0)
                _add_strut_bm(bm, p_t, n_r, 0.042, 0)
                _add_strut_bm(bm, p_r, n_l, 0.040, 0)

    # Trolley carriage + hoist cables + pulley hook block at Y = -6.80m
    ty = -6.80
    _add_box_bm(bm, (-0.42, ty - 0.38, 14.32), (0.42, ty + 0.38, 14.56), 1, 0.01)
    for cx in (-0.12, 0.12):
        _add_cyl_bm(bm, (cx, ty, 14.32), (cx, ty, 10.65), 0.016, 0.016, 6, 1)
    # Pulley block
    _add_box_bm(bm, (-0.20, ty - 0.15, 10.22), (0.20, ty + 0.15, 10.68), 2, 0.01)
    # Steel crane hook shank + J-hook
    _add_cyl_bm(bm, (0.0, ty, 10.22), (0.0, ty, 9.96), 0.045, 0.045, 8, 1)
    _add_box_bm(bm, (-0.05, ty - 0.05, 9.82), (0.18, ty + 0.05, 9.96), 1)
    _add_box_bm(bm, (0.10, ty - 0.05, 9.82), (0.20, ty + 0.05, 10.04), 1)

    # 6. Counter-jib & counterweight blocks (+Y from Y=0.0 to Y=+4.80m)
    cj_len = 4.80
    cj_bays = 4
    cj_step = cj_len / cj_bays
    cj_hw = 0.56
    cj_z0, cj_z1 = 14.52, 15.32
    cj_corners = [(-cj_hw, cj_z0), (cj_hw, cj_z0), (cj_hw, cj_z1), (-cj_hw, cj_z1)]
    for cx, cz in cj_corners:
        _add_strut_bm(bm, (cx, 0.0, cz), (cx, cj_len, cz), 0.075, 0)

    for b in range(cj_bays + 1):
        y = b * cj_step
        for i in range(4):
            a0 = cj_corners[i]
            a1 = cj_corners[(i + 1) % 4]
            _add_strut_bm(bm, (a0[0], y, a0[1]), (a1[0], y, a1[1]), 0.055, 0)
        if b < cj_bays:
            yn = y + cj_step
            for i in (0, 2):  # side truss faces
                a0 = cj_corners[i]
                a1 = cj_corners[(i + 1) % 4]
                if i == 0:
                    _add_strut_bm(bm, (-cj_hw, y, cj_z0), (-cj_hw, yn, cj_z1), 0.048, 0)
                    _add_strut_bm(bm, (cj_hw, y, cj_z0), (cj_hw, yn, cj_z1), 0.048, 0)
                else:
                    _add_strut_bm(bm, (-cj_hw, y, cj_z1), (cj_hw, yn, cj_z1), 0.045, 0)

    # Winch motor housing + 3 heavy counterweight slabs
    _add_box_bm(bm, (-0.42, 1.45, 14.55), (0.42, 2.45, 15.22), 1, 0.015)
    for k in range(3):
        wy0 = 3.25 + k * 0.48
        _add_box_bm(bm, (-0.72, wy0, 13.95), (0.72, wy0 + 0.42, 15.40), 2 if k == 1 else 1, 0.015)

    # 7. Forestay and backstay tension tie-rods
    for sx in (-0.12, 0.12):
        _add_strut_bm(bm, (sx, 0.0, 17.86), (sx * 0.3, -7.0, 15.38), 0.036, 1)
        _add_strut_bm(bm, (sx, 0.0, 17.86), (sx * 4.0, 4.65, 15.32), 0.036, 1)

    obj = _finalize_bmesh_object("crane_tower", bm, [galv_mat, rust_mat, paint_mat], smooth_sharp_deg=38.0)
    _log_export_stats("crane_tower", obj, out_path)
    export_godot_glb(str(out_path))


def build_network_tower(out_path: Path) -> None:
    """Generate a 12.0m tapered steel lattice telecom mast with microwave dishes and antennas."""
    clean_scene()
    galv_mat = create_pbr_material(
        "galvanized_lattice_steel", (0.44, 0.46, 0.47, 1.0), metallic=0.80, roughness=0.52
    )
    rust_mat = create_pbr_material(
        "rusted_steel", (0.26, 0.17, 0.13, 1.0), metallic=0.72, roughness=0.68
    )
    # Slots: 0 = galvanized_lattice_steel, 1 = rusted_steel
    bm = bmesh.new()

    # 1. Base anchor plates & pedestals (Z: 0.0 .. 0.28)
    bays = 7
    z_bot = 0.16
    z_top_lattice = 10.60
    hw_bot = 1.12
    hw_top = 0.32

    def _hw_at(z: float) -> float:
        t = (z - z_bot) / (z_top_lattice - z_bot)
        return hw_bot + (hw_top - hw_bot) * t

    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx, cy = sx * hw_bot, sy * hw_bot
            _add_box_bm(bm, (cx - 0.20, cy - 0.20, 0.0), (cx + 0.20, cy + 0.20, 0.06), 1, 0.005)
            _add_box_bm(bm, (cx - 0.13, cy - 0.13, 0.06), (cx + 0.13, cy + 0.13, 0.26), 1, 0.005)

    # Ground junction cabinet + mounting frame resting at Z=0.0
    _add_box_bm(bm, (-0.32, -0.24, 0.0), (0.32, 0.24, 0.12), 1)
    _add_box_bm(bm, (-0.28, -0.20, 0.12), (0.28, 0.20, 0.96), 1, 0.01)
    _add_strut_bm(bm, (-0.28, 0.0, 0.45), (-hw_bot * 0.96, 0.0, 0.20), 0.055, 1)
    _add_strut_bm(bm, (0.28, 0.0, 0.45), (hw_bot * 0.96, 0.0, 0.20), 0.055, 1)

    # 2. Tapered 4-legged lattice tower (Z: 0.16 .. 10.60)
    z_levels = [z_bot + (z_top_lattice - z_bot) * (i / bays) for i in range(bays + 1)]
    signs = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]

    for b in range(bays):
        z0, z1 = z_levels[b], z_levels[b + 1]
        h0, h1 = _hw_at(z0), _hw_at(z1)
        ring0 = [(sx * h0, sy * h0, z0) for sx, sy in signs]
        ring1 = [(sx * h1, sy * h1, z1) for sx, sy in signs]

        # Corner legs (slightly thicker on lower 3 bays)
        leg_w = 0.095 if b < 3 else 0.075
        for i in range(4):
            _add_strut_bm(bm, ring0[i], ring1[i], leg_w, 0)

        # Bottom horizontal ring of bay
        for i in range(4):
            _add_strut_bm(bm, ring0[i], ring0[(i + 1) % 4], 0.055, 0)

        # Bracing: full X-brace on bottom 3 bays, alternating single diagonal on upper 4 bays
        for i in range(4):
            j = (i + 1) % 4
            if b < 3:
                _add_strut_bm(bm, ring0[i], ring1[j], 0.044, 0)
                _add_strut_bm(bm, ring0[j], ring1[i], 0.044, 0)
            else:
                if (b + i) % 2 == 0:
                    _add_strut_bm(bm, ring0[i], ring1[j], 0.042, 0)
                else:
                    _add_strut_bm(bm, ring0[j], ring1[i], 0.042, 0)

    # Top ring of lattice at Z = 10.60
    ring_top = [(sx * hw_top, sy * hw_top, z_top_lattice) for sx, sy in signs]
    for i in range(4):
        _add_strut_bm(bm, ring_top[i], ring_top[(i + 1) % 4], 0.06, 0)

    # 3. Central vertical waveguide cable ladder (Z: 0.0 .. 10.60)
    for lx in (-0.14, 0.14):
        _add_box_bm(bm, (lx - 0.018, -0.02, 0.0), (lx + 0.018, 0.02, z_top_lattice), 1)
    for r in range(21):
        rz = 0.45 + r * 0.50
        _add_strut_bm(bm, (-0.14, 0.0, rz), (0.14, 0.0, rz), 0.024, 1)
    # Tie ladder into horizontal mast crossbars every 2 bays
    for b in (1, 3, 5):
        zb = z_levels[b]
        hb = _hw_at(zb)
        _add_strut_bm(bm, (-hb, 0.0, zb), (hb, 0.0, zb), 0.04, 1)

    # 4. Upper maintenance platform & guardrail at Z = z_levels[6] (~9.11m)
    z_plat = z_levels[6]
    plat_hw = 0.72
    _add_box_bm(bm, (-plat_hw, -plat_hw, z_plat - 0.04), (plat_hw, plat_hw, z_plat + 0.02), 1)
    rail_z = z_plat + 0.92
    rail_mid_z = z_plat + 0.48
    rail_c = [(-plat_hw + 0.03, -plat_hw + 0.03), (plat_hw - 0.03, -plat_hw + 0.03),
              (plat_hw - 0.03, plat_hw - 0.03), (-plat_hw + 0.03, plat_hw - 0.03)]
    for i in range(4):
        c0 = rail_c[i]
        c1 = rail_c[(i + 1) % 4]
        _add_strut_bm(bm, (c0[0], c0[1], z_plat), (c0[0], c0[1], rail_z), 0.035, 0)
        _add_strut_bm(bm, (c0[0], c0[1], rail_z), (c1[0], c1[1], rail_z), 0.035, 0)
        _add_strut_bm(bm, (c0[0], c0[1], rail_mid_z), (c1[0], c1[1], rail_mid_z), 0.030, 0)

    # 5. Microwave drum dishes (facing -Y and +X)
    # Dish 1: -Y at Z = 9.60m
    _add_strut_bm(bm, (0.0, -0.35, 9.60), (0.0, -0.78, 9.60), 0.08, 1)
    _add_cyl_bm(bm, (0.0, -0.76, 9.60), (0.0, -1.04, 9.60), 0.44, 0.46, 16, 0)
    _add_cyl_bm(bm, (0.0, -1.02, 9.60), (0.0, -1.10, 9.60), 0.44, 0.14, 12, 1)
    # Dish 2: +X at Z = 8.20m
    _add_strut_bm(bm, (0.42, 0.0, 8.20), (0.84, 0.0, 8.20), 0.08, 1)
    _add_cyl_bm(bm, (0.82, 0.0, 8.20), (1.08, 0.0, 8.20), 0.38, 0.40, 16, 0)
    _add_cyl_bm(bm, (1.06, 0.0, 8.20), (1.13, 0.0, 8.20), 0.38, 0.12, 12, 1)

    # 6. 3 Sector panel antennas around top collar (Z: 10.10 .. 11.35)
    for k in range(3):
        ang = math.radians(k * 120.0 - 90.0)
        dx, dy = math.cos(ang), math.sin(ang)
        _add_strut_bm(bm, (dx * 0.26, dy * 0.26, 10.65), (dx * 0.62, dy * 0.62, 10.65), 0.05, 1)
        _add_strut_bm(bm, (dx * 0.26, dy * 0.26, 10.25), (dx * 0.62, dy * 0.62, 10.25), 0.05, 1)
        p_center = Vector((dx * 0.65, dy * 0.65, 10.75))
        _add_strut_bm(
            bm,
            p_center - Vector((0.0, 0.0, 0.58)),
            p_center + Vector((0.0, 0.0, 0.58)),
            0.16,
            0,
        )

    # 7. Top mast pole + obstruction beacon + lightning spire (Z: 10.50 .. 12.00m exact)
    _add_box_bm(bm, (-0.34, -0.34, 10.52), (0.34, 0.34, 10.64), 1)
    _add_cyl_bm(bm, (0.0, 0.0, 10.60), (0.0, 0.0, 11.72), 0.055, 0.042, 12, 1)
    _add_cyl_bm(bm, (0.0, 0.0, 11.42), (0.0, 0.0, 11.56), 0.095, 0.095, 10, 1)
    _add_cyl_bm(bm, (0.0, 0.0, 11.72), (0.0, 0.0, 12.00), 0.032, 0.004, 8, 1)

    obj = _finalize_bmesh_object("network_tower", bm, [galv_mat, rust_mat], smooth_sharp_deg=38.0)
    _log_export_stats("network_tower", obj, out_path)
    export_godot_glb(str(out_path))


def build_water_tank(out_path: Path) -> None:
    """Generate a 6.0m elevated cylindrical steel water tank with cross-braced legs and caged ladder."""
    clean_scene()
    paint_mat = create_pbr_material(
        "painted_industrial_metal", (0.28, 0.38, 0.36, 1.0), metallic=0.38, roughness=0.62
    )
    galv_mat = create_pbr_material(
        "galvanized_lattice_steel", (0.44, 0.46, 0.47, 1.0), metallic=0.80, roughness=0.52
    )
    rust_mat = create_pbr_material(
        "rusted_steel", (0.26, 0.17, 0.13, 1.0), metallic=0.72, roughness=0.68
    )
    # Slots: 0 = painted_industrial_metal, 1 = galvanized_lattice_steel, 2 = rusted_steel
    bm = bmesh.new()

    # 1. Footings & battered steel legs (Z: 0.0 .. 3.35m)
    hw_bot = 1.32
    hw_top = 1.02
    z_foot = 0.16
    z_mid = 1.72
    z_ring = 3.26
    signs = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]

    for sx, sy in signs:
        _add_box_bm(
            bm,
            (sx * hw_bot - 0.22, sy * hw_bot - 0.22, 0.0),
            (sx * hw_bot + 0.22, sy * hw_bot + 0.22, z_foot),
            2,
            0.01,
        )
        _add_strut_bm(
            bm,
            (sx * hw_bot, sy * hw_bot, z_foot * 0.8),
            (sx * hw_top, sy * hw_top, z_ring + 0.12),
            0.14,
            1,
        )

    # Horizontal tie beams + X-bracing in 2 tiers
    hw_mid = 0.5 * (hw_bot + hw_top)
    bot_pts = [(sx * hw_bot, sy * hw_bot, z_foot + 0.08) for sx, sy in signs]
    mid_pts = [(sx * hw_mid, sy * hw_mid, z_mid) for sx, sy in signs]
    top_pts = [(sx * hw_top, sy * hw_top, z_ring) for sx, sy in signs]

    for i in range(4):
        j = (i + 1) % 4
        _add_strut_bm(bm, mid_pts[i], mid_pts[j], 0.09, 1)
        _add_strut_bm(bm, top_pts[i], top_pts[j], 0.12, 1)
        # Lower bay X-brace
        _add_strut_bm(bm, bot_pts[i], mid_pts[j], 0.055, 1)
        _add_strut_bm(bm, bot_pts[j], mid_pts[i], 0.055, 1)
        # Upper bay X-brace
        _add_strut_bm(bm, mid_pts[i], top_pts[j], 0.055, 1)
        _add_strut_bm(bm, mid_pts[j], top_pts[i], 0.055, 1)

    # Support ring cradle beams under tank bottom (Z: 3.24 .. 3.38)
    _add_box_bm(bm, (-1.12, -1.12, 3.26), (1.12, 1.12, 3.38), 2)

    # Central vertical riser pipe + base flange + gate valve (Z: 0.0 .. 3.40)
    _add_cyl_bm(bm, (0.0, 0.0, 0.0), (0.0, 0.0, 0.10), 0.24, 0.24, 12, 2)
    _add_cyl_bm(bm, (0.0, 0.0, 0.10), (0.0, 0.0, 3.40), 0.13, 0.13, 12, 2)
    _add_cyl_bm(bm, (0.0, 0.0, 1.25), (0.0, 0.0, 1.33), 0.20, 0.20, 12, 2)
    _add_strut_bm(bm, (0.0, 0.0, 1.10), (0.0, -0.26, 1.10), 0.04, 2)
    _add_cyl_bm(bm, (0.0, -0.26, 1.10), (0.0, -0.30, 1.10), 0.12, 0.12, 10, 2)

    # 2. Elevated cylindrical steel tank drum + stiffening bands + conical roof (Z: 3.36 .. 6.00m)
    tank_r = 1.42
    _add_cyl_bm(bm, (0.0, 0.0, 3.36), (0.0, 0.0, 5.42), tank_r, tank_r, 24, 0)
    # 3 rusted steel stiffening belly bands
    for bz in (3.44, 4.38, 5.34):
        _add_cyl_bm(bm, (0.0, 0.0, bz - 0.04), (0.0, 0.0, bz + 0.04), tank_r + 0.03, tank_r + 0.03, 24, 2)
    # Conical roof + top vent cupola reaching Z = 6.00m
    _add_cyl_bm(bm, (0.0, 0.0, 5.42), (0.0, 0.0, 5.84), tank_r + 0.06, 0.24, 24, 0)
    _add_cyl_bm(bm, (0.0, 0.0, 5.82), (0.0, 0.0, 6.00), 0.24, 0.24, 12, 2)

    # 3. Caged steel access ladder on -Y side (Z: 0.0 .. 5.56)
    lad_y = -1.56
    for lx in (-0.22, 0.22):
        _add_box_bm(bm, (lx - 0.02, lad_y - 0.02, 0.0), (lx + 0.02, lad_y + 0.02, 5.65), 2)
    # Tie-in brackets connecting ladder stiles solidly to frame & tank wall
    for tz in (1.72, 3.32, 4.38, 5.34):
        target_y = -hw_mid if tz < 2.0 else (-hw_top if tz < 3.5 else -tank_r)
        for lx in (-0.22, 0.22):
            _add_strut_bm(bm, (lx, lad_y, tz), (lx, target_y, tz), 0.04, 2)

    # 18 ladder rungs (Z: 0.30 .. 5.40)
    for r in range(18):
        rz = 0.30 + r * 0.30
        _add_strut_bm(bm, (-0.22, lad_y, rz), (0.22, lad_y, rz), 0.024, 2)

    # Safety cage hoops (Z: 2.30 .. 5.50, 5 hoops + 3 spine bars)
    hoop_pts = [
        (-0.22, lad_y),
        (-0.32, lad_y - 0.26),
        (-0.16, lad_y - 0.56),
        (0.16, lad_y - 0.56),
        (0.32, lad_y - 0.26),
        (0.22, lad_y),
    ]
    hoop_zs = [2.30, 3.10, 3.90, 4.70, 5.50]
    for hz in hoop_zs:
        for i in range(len(hoop_pts) - 1):
            p0 = hoop_pts[i]
            p1 = hoop_pts[i + 1]
            _add_strut_bm(bm, (p0[0], p0[1], hz), (p1[0], p1[1], hz), 0.026, 1)

    for sx, sy in (hoop_pts[1], (0.0, lad_y - 0.58), hoop_pts[4]):
        _add_strut_bm(bm, (sx, sy, hoop_zs[0]), (sx, sy, hoop_zs[-1]), 0.026, 1)

    # Top ladder landing platform & guard rail at Z = 5.42
    _add_box_bm(bm, (-0.36, -1.60, 5.38), (0.36, -1.30, 5.44), 2)
    for lx in (-0.34, 0.34):
        _add_strut_bm(bm, (lx, -1.58, 5.42), (lx, -1.58, 6.00), 0.032, 2)
        _add_strut_bm(bm, (lx, -1.58, 5.98), (lx, -1.25, 5.98), 0.032, 2)

    obj = _finalize_bmesh_object("water_tank", bm, [paint_mat, galv_mat, rust_mat], smooth_sharp_deg=38.0)
    _log_export_stats("water_tank", obj, out_path)
    export_godot_glb(str(out_path))


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate factory hero tower GLBs.")
    parser.add_argument(
        "--asset",
        required=True,
        choices=["crane_tower", "network_tower", "water_tank"],
        help="Hero tower asset to generate.",
    )
    args, _ = parser.parse_known_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])

    out_dir = _REPO_ROOT / "assets/models/props/factory_yard"
    if args.asset == "crane_tower":
        build_crane_tower(out_dir / "crane_tower.glb")
    elif args.asset == "network_tower":
        build_network_tower(out_dir / "network_tower.glb")
    elif args.asset == "water_tank":
        build_water_tank(out_dir / "water_tank.glb")


if __name__ == "__main__":
    main()
