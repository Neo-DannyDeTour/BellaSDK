"""Procedural Blender generator for factory yard cardboard, brick, and wood debris GLBs.

Builds post-Soviet industrial yard debris props one asset at a time via `--asset <name>`:
- cardboard_box: 0.45m x 0.35m x 0.35m creased/taped shipping box
- cardboard_debris_01: ~0.75m x 0.04m x 0.55m flattened/torn damp cardboard sheet
- cardboard_debris_02: ~0.75m x 0.04m x 0.55m flattened/torn damp cardboard sheet (variant)
- brick_01: 0.24m x 0.07m x 0.115m chipped clay brick
- brick_02: 0.35m x 0.14m x 0.28m 4-brick rubble cluster
- wood_plank_01: 1.40m x 0.04m x 0.16m weathered split board
- wood_plank_02: 1.10m x 0.04m x 0.14m weathered split board (variant)

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
from mathutils import Euler, Matrix, Vector

_REPO_ROOT = _TOOL_DIR.parent.parent


def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMVert]:
    """Append an axis-aligned box with optional chamfer to a BMesh and return its verts."""
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        return []

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
        res = bmesh.ops.bevel(
            bm,
            geom=edges,
            offset=chamfer,
            offset_type="OFFSET",
            segments=1,
            profile=0.5,
            affect="EDGES",
            clamp_overlap=True,
        )
        return list(res.get("verts", verts))
    return verts


def _add_solid_polygon_grid(
    bm: bmesh.types.BMesh,
    grid_xy: list[list[tuple[float, float, float]]],
    thickness: float,
    mat_idx: int = 0,
) -> list[bmesh.types.BMVert]:
    """Extrude a 2D deformed grid (rows x cols of bottom XYZ) upward by thickness."""
    rows = len(grid_xy)
    cols = len(grid_xy[0])
    bot_verts: list[list[bmesh.types.BMVert]] = []
    top_verts: list[list[bmesh.types.BMVert]] = []
    for r in range(rows):
        b_row = []
        t_row = []
        for c in range(cols):
            x, y, z = grid_xy[r][c]
            b_row.append(bm.verts.new((x, y, z)))
            t_row.append(bm.verts.new((x, y, z + thickness)))
        bot_verts.append(b_row)
        top_verts.append(t_row)

    for r in range(rows - 1):
        for c in range(cols - 1):
            fb = bm.faces.new(
                [bot_verts[r][c], bot_verts[r + 1][c], bot_verts[r + 1][c + 1], bot_verts[r][c + 1]]
            )
            fb.material_index = mat_idx
            ft = bm.faces.new(
                [top_verts[r][c], top_verts[r][c + 1], top_verts[r + 1][c + 1], top_verts[r + 1][c]]
            )
            ft.material_index = mat_idx

    # Perimeter stitch
    for c in range(cols - 1):
        f1 = bm.faces.new([bot_verts[0][c], bot_verts[0][c + 1], top_verts[0][c + 1], top_verts[0][c]])
        f1.material_index = mat_idx
        f2 = bm.faces.new(
            [bot_verts[rows - 1][c + 1], bot_verts[rows - 1][c], top_verts[rows - 1][c], top_verts[rows - 1][c + 1]]
        )
        f2.material_index = mat_idx
    for r in range(rows - 1):
        f3 = bm.faces.new([bot_verts[r + 1][0], bot_verts[r][0], top_verts[r][0], top_verts[r + 1][0]])
        f3.material_index = mat_idx
        f4 = bm.faces.new(
            [bot_verts[r][cols - 1], bot_verts[r + 1][cols - 1], top_verts[r + 1][cols - 1], top_verts[r][cols - 1]]
        )
        f4.material_index = mat_idx

    return [v for row in bot_verts + top_verts for v in row]


def _normalize_bottom_center(bm: bmesh.types.BMesh) -> None:
    """Center X/Y around 0 and ground min Z at exactly 0.0."""
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    cx = 0.5 * (min(xs) + max(xs))
    cy = 0.5 * (min(ys) + max(ys))
    min_z = min(zs)
    for v in bm.verts:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= min_z


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
    _normalize_bottom_center(bm)
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


def build_cardboard_box(out_path: Path) -> None:
    """Generate a 0.45m x 0.35m x 0.35m creased/taped corrugated shipping box."""
    clean_scene()
    cardboard_mat = create_pbr_material(
        "weathered_cardboard",
        (0.45, 0.36, 0.25, 1.0),
        metallic=0.0,
        roughness=0.86,
    )

    bm = bmesh.new()
    hx, hy, hz = 0.225, 0.175, 0.344

    # Subdivided shipping carton body (3x3x3 grid -> subtle damp bulge + corner dent)
    res = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    for v in bm.verts:
        v.co.x *= 2.0 * hx
        v.co.y *= 2.0 * hy
        v.co.z = (v.co.z + 0.5) * hz

        # Keep bottom plane flat at Z=0
        if v.co.z > 0.02:
            # Subtle damp wall bulge/sag on mid-sections
            if abs(v.co.x) < 0.10 and abs(v.co.y) > hy * 0.9:
                v.co.y += math.copysign(0.004, v.co.y)
            if abs(v.co.y) < 0.08 and abs(v.co.x) > hx * 0.9:
                v.co.x -= math.copysign(0.003, v.co.x)
            # Creased top-center sag
            if v.co.z > hz - 0.01 and abs(v.co.y) < 0.08:
                v.co.z -= 0.006
            # Dented upper corner (+X, -Y, top)
            if v.co.x > 0.15 and v.co.y < -0.10 and v.co.z > 0.22:
                v.co.x -= 0.009
                v.co.y += 0.009
                v.co.z -= 0.008

    # Folded top flaps meeting at center seam (slight asymmetry for lived-in feel)
    _add_box_bm(bm, (-hx, -hy, hz - 0.004), (hx, -0.003, hz + 0.003), 0)
    _add_box_bm(bm, (-hx, 0.003, hz - 0.004), (hx, hy, hz + 0.004), 0)

    # Raised packing tape strap across top flap seam and wrapping down -X/+X ends
    _add_box_bm(bm, (-hx - 0.002, -0.028, hz + 0.001), (hx + 0.002, 0.028, 0.350), 0)
    _add_box_bm(bm, (-hx - 0.004, -0.028, 0.285), (-hx + 0.002, 0.028, hz + 0.004), 0)
    _add_box_bm(bm, (hx - 0.002, -0.028, 0.285), (hx + 0.004, 0.028, hz + 0.004), 0)

    obj = _finalize_bmesh_object("cardboard_box", bm, [cardboard_mat])
    _report_and_export("cardboard_box", obj, out_path)


def build_cardboard_debris_01(out_path: Path) -> None:
    """Generate a ~0.75m x 0.04m x 0.55m flattened/torn damp cardboard sheet."""
    clean_scene()
    cardboard_mat = create_pbr_material(
        "weathered_cardboard",
        (0.42, 0.34, 0.24, 1.0),
        metallic=0.0,
        roughness=0.88,
    )

    bm = bmesh.new()
    # 5x4 irregular torn rectangular profile (X ~ 0.75m, Y ~ 0.55m, curled Z up to 0.04m)
    xs = [-0.375, -0.18, 0.01, 0.19, 0.365]
    ys = [-0.275, -0.09, 0.09, 0.270]
    grid: list[list[tuple[float, float, float]]] = []
    for r, y in enumerate(ys):
        row = []
        for c, x in enumerate(xs):
            jx, jy, jz = x, y, 0.002
            # Torn irregular outer edges
            if r == 0 and c == 1:
                jy += 0.032
            elif r == 0 and c == 3:
                jy -= 0.012
            elif r == 3 and c == 2:
                jy -= 0.040
            elif r == 3 and c == 4:
                jx -= 0.025
                jy -= 0.020
            if c == 0 and r == 2:
                jx += 0.022
            if c == 4 and r == 1:
                jx += 0.010

            # Damp curl & fold crease
            if r == 0 and c >= 3:
                jz = 0.018
            elif r == 3 and c <= 1:
                jz = 0.032
            elif c == 2:
                jz = 0.008
            elif r == 1 and c == 1:
                jz = 0.000
            row.append((jx, jy, jz))
        grid.append(row)

    _add_solid_polygon_grid(bm, grid, thickness=0.008, mat_idx=0)

    # Torn attached corner flap folded inward/upward along one edge (reaches Z = 0.040m)
    flap_grid = [
        [(0.18, -0.25, 0.014), (0.34, -0.24, 0.018)],
        [(0.19, -0.15, 0.028), (0.33, -0.14, 0.032)],
    ]
    _add_solid_polygon_grid(bm, flap_grid, thickness=0.008, mat_idx=0)

    obj = _finalize_bmesh_object("cardboard_debris_01", bm, [cardboard_mat])
    _report_and_export("cardboard_debris_01", obj, out_path)


def build_cardboard_debris_02(out_path: Path) -> None:
    """Generate a ~0.75m x 0.04m x 0.55m flattened/torn damp cardboard sheet variant."""
    clean_scene()
    cardboard_mat = create_pbr_material(
        "weathered_cardboard",
        (0.42, 0.34, 0.24, 1.0),
        metallic=0.0,
        roughness=0.88,
    )

    bm = bmesh.new()
    xs = [-0.365, -0.17, 0.02, 0.21, 0.375]
    ys = [-0.265, -0.08, 0.10, 0.275]
    grid: list[list[tuple[float, float, float]]] = []
    for r, y in enumerate(ys):
        row = []
        for c, x in enumerate(xs):
            jx, jy, jz = x, y, 0.001
            # Distinct diagonal torn edge & notch
            if r == 0 and c == 0:
                jx += 0.045
                jy += 0.035
            elif r == 0 and c == 2:
                jy += 0.024
            elif r == 3 and c == 4:
                jx -= 0.035
                jy -= 0.045
            elif r == 2 and c == 4:
                jx -= 0.022

            # Diagonal damp fold ridge across center + curled corners
            if (r + c) == 3:
                jz = 0.016
            elif r == 0 and c == 4:
                jz = 0.026
            elif r == 3 and c == 0:
                jz = 0.032
            elif r == 1 and c == 2:
                jz = 0.000
            row.append((jx, jy, jz))
        grid.append(row)

    _add_solid_polygon_grid(bm, grid, thickness=0.008, mat_idx=0)

    # Attached torn side flap curled upward at +Y edge
    flap_grid = [
        [(-0.26, 0.15, 0.012), (-0.06, 0.16, 0.014)],
        [(-0.24, 0.25, 0.030), (-0.08, 0.24, 0.032)],
    ]
    _add_solid_polygon_grid(bm, flap_grid, thickness=0.008, mat_idx=0)

    obj = _finalize_bmesh_object("cardboard_debris_02", bm, [cardboard_mat])
    _report_and_export("cardboard_debris_02", obj, out_path)


def _add_chipped_brick_bm(
    bm: bmesh.types.BMesh,
    length: float,
    width: float,
    height: float,
    transform: Matrix,
    chip_seed: int = 0,
    mat_idx: int = 0,
) -> None:
    """Append a single chipped/beveled clay brick transformed into the target BMesh."""
    temp = bmesh.new()
    bmesh.ops.create_cube(temp, size=1.0)
    bmesh.ops.subdivide_edges(temp, edges=temp.edges[:], cuts=2, use_grid_fill=True)

    hx, hy = length * 0.5, width * 0.5
    for v in temp.verts:
        v.co.x *= length
        v.co.y *= width
        v.co.z = (v.co.z + 0.5) * height

        # Shallow mortar frog recess on top face
        if v.co.z > height * 0.85 and abs(v.co.x) < hx * 0.55 and abs(v.co.y) < hy * 0.45:
            v.co.z -= 0.004

        # Asymmetric corner chips based on chip_seed
        if chip_seed % 2 == 0:
            if v.co.x > hx * 0.65 and v.co.y > hy * 0.65 and v.co.z > height * 0.55:
                v.co.x -= 0.011
                v.co.y -= 0.009
                v.co.z -= 0.008
            if v.co.x < -hx * 0.65 and v.co.y < -hy * 0.65 and v.co.z > height * 0.65:
                v.co.x += 0.007
                v.co.y += 0.007
                v.co.z -= 0.005
        else:
            if v.co.x < -hx * 0.65 and v.co.y > hy * 0.65 and v.co.z > height * 0.55:
                v.co.x += 0.010
                v.co.y -= 0.008
                v.co.z -= 0.007
            if v.co.x > hx * 0.65 and v.co.y < -hy * 0.65 and v.co.z < height * 0.45:
                v.co.x -= 0.006
                v.co.y += 0.006

    # Copy into main BMesh with transform
    vert_map: dict[int, bmesh.types.BMVert] = {}
    for v in temp.verts:
        vert_map[v.index] = bm.verts.new(transform @ v.co)
    for f in temp.faces:
        nf = bm.faces.new([vert_map[v.index] for v in f.verts])
        nf.material_index = mat_idx
    temp.free()


def build_brick_01(out_path: Path) -> None:
    """Generate a 0.24m x 0.07m x 0.115m chipped clay brick."""
    clean_scene()
    brick_mat = create_pbr_material(
        "weathered_clay_brick",
        (0.52, 0.23, 0.16, 1.0),
        metallic=0.0,
        roughness=0.88,
    )

    bm = bmesh.new()
    _add_chipped_brick_bm(bm, length=0.24, width=0.115, height=0.070, transform=Matrix.Identity(4), chip_seed=0)
    obj = _finalize_bmesh_object("brick_01", bm, [brick_mat])
    _report_and_export("brick_01", obj, out_path)


def build_brick_02(out_path: Path) -> None:
    """Generate a 0.35m x 0.14m x 0.28m 4-brick rubble cluster."""
    clean_scene()
    brick_mat = create_pbr_material(
        "weathered_clay_brick",
        (0.52, 0.23, 0.16, 1.0),
        metallic=0.0,
        roughness=0.88,
    )

    bm = bmesh.new()
    # Use 1-cut boxes per brick (~56 tris each -> ~224 tris total <= 300)
    def add_rubble_brick(length: float, width: float, height: float, pos: tuple[float, float, float], rot_deg: tuple[float, float, float], chip: int) -> None:
        temp = bmesh.new()
        bmesh.ops.create_cube(temp, size=1.0)
        bmesh.ops.subdivide_edges(temp, edges=temp.edges[:], cuts=1, use_grid_fill=True)
        hx, hy = length * 0.5, width * 0.5
        for v in temp.verts:
            v.co.x *= length
            v.co.y *= width
            v.co.z = (v.co.z + 0.5) * height
            if chip % 2 == 0 and v.co.x > hx * 0.8 and v.co.y > hy * 0.8 and v.co.z > height * 0.8:
                v.co.x -= 0.015
                v.co.y -= 0.012
                v.co.z -= 0.010
            elif chip % 2 == 1 and v.co.x < -hx * 0.8 and v.co.y < -hy * 0.8 and v.co.z > height * 0.8:
                v.co.x += 0.014
                v.co.y += 0.011
                v.co.z -= 0.009

        rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
        xform = Matrix.Translation(pos) @ rot
        vmap: dict[int, bmesh.types.BMVert] = {}
        for v in temp.verts:
            vmap[v.index] = bm.verts.new(xform @ v.co)
        for f in temp.faces:
            nf = bm.faces.new([vmap[v.index] for v in f.verts])
            nf.material_index = 0
        temp.free()

    # 3 grounded base bricks + 1 leaning rubble half-brick on top (total span <= 0.35 x 0.28 x 0.14)
    add_rubble_brick(0.22, 0.11, 0.068, (-0.055, -0.055, 0.0), (0.0, 0.0, 14.0), chip=0)
    add_rubble_brick(0.19, 0.11, 0.068, (0.065, 0.045, 0.0), (0.0, 0.0, -24.0), chip=1)
    add_rubble_brick(0.14, 0.105, 0.065, (-0.095, 0.068, 0.0), (0.0, 0.0, 42.0), chip=2)
    add_rubble_brick(0.17, 0.105, 0.066, (0.005, -0.010, 0.055), (12.0, -18.0, 8.0), chip=3)

    # Clamp height to <= 0.140m and XY within 0.35m x 0.28m
    _normalize_bottom_center(bm)
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    sx = min(1.0, 0.35 / max(1e-5, max(xs) - min(xs)))
    sy = min(1.0, 0.28 / max(1e-5, max(ys) - min(ys)))
    sz = min(1.0, 0.14 / max(1e-5, max(zs)))
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz

    obj = _finalize_bmesh_object("brick_02", bm, [brick_mat])
    _report_and_export("brick_02", obj, out_path)


def _build_split_plank(
    name: str,
    length: float,
    width: float,
    thickness: float,
    variant: int,
    out_path: Path,
) -> None:
    """Generate a weathered split timber board within exact bounding box."""
    clean_scene()
    wood_mat = create_pbr_material(
        "weathered_olive_crate_wood",
        (0.34, 0.28, 0.20, 1.0),
        metallic=0.0,
        roughness=0.86,
    )

    bm = bmesh.new()
    hx, hy = length * 0.5, width * 0.5
    xs = [-hx + length * (i / 6.0) for i in range(7)]
    ys = [-hy, -hy * 0.33, hy * 0.33, hy]

    grid: list[list[tuple[float, float, float]]] = []
    for r, y in enumerate(ys):
        row = []
        for c, x in enumerate(xs):
            jx, jy, jz = x, y, 0.0
            if variant == 0:
                # Jagged split on +X end; slight edge notch near X=0.22
                if c == 6:
                    if r == 0:
                        jx -= 0.065
                    elif r == 1:
                        jx -= 0.015
                    elif r == 2:
                        jx -= 0.095
                    elif r == 3:
                        jx -= 0.045
                elif c == 4 and r == 0:
                    jy += 0.008
                elif c == 2 and r == 3:
                    jy -= 0.006
            else:
                # Diagonal/stepped splits on both ends
                if c == 0:
                    if r == 0:
                        jx += 0.055
                    elif r == 1:
                        jx += 0.020
                    elif r == 3:
                        jx += 0.075
                elif c == 6:
                    if r == 0:
                        jx -= 0.030
                    elif r == 2:
                        jx -= 0.085
                    elif r == 3:
                        jx -= 0.015
                elif c == 3 and r == 3:
                    jy -= 0.010

            # Subtle organic warp (stays strictly within [0, thickness])
            if c in (2, 3, 4) and r in (1, 2):
                jz = 0.002
            row.append((jx, jy, jz))
        grid.append(row)

    _add_solid_polygon_grid(bm, grid, thickness=thickness - 0.002, mat_idx=0)
    # Re-clamp exact Z to [0.0, thickness]
    _normalize_bottom_center(bm)
    max_z = max(v.co.z for v in bm.verts)
    if max_z > 1e-5:
        scale_z = thickness / max_z
        for v in bm.verts:
            v.co.z *= scale_z

    obj = _finalize_bmesh_object(name, bm, [wood_mat])
    _report_and_export(name, obj, out_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate factory yard cardboard/brick/wood debris GLBs.")
    parser.add_argument(
        "--asset",
        required=True,
        choices=[
            "cardboard_box",
            "cardboard_debris_01",
            "cardboard_debris_02",
            "brick_01",
            "brick_02",
            "wood_plank_01",
            "wood_plank_02",
        ],
        help="Debris prop asset to generate.",
    )
    args, _ = parser.parse_known_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])

    out_dir = _REPO_ROOT / "assets/models/props/factory_yard"
    if args.asset == "cardboard_box":
        build_cardboard_box(out_dir / "cardboard_box.glb")
    elif args.asset == "cardboard_debris_01":
        build_cardboard_debris_01(out_dir / "cardboard_debris_01.glb")
    elif args.asset == "cardboard_debris_02":
        build_cardboard_debris_02(out_dir / "cardboard_debris_02.glb")
    elif args.asset == "brick_01":
        build_brick_01(out_dir / "brick_01.glb")
    elif args.asset == "brick_02":
        build_brick_02(out_dir / "brick_02.glb")
    elif args.asset == "wood_plank_01":
        _build_split_plank("wood_plank_01", 1.40, 0.16, 0.04, 0, out_dir / "wood_plank_01.glb")
    elif args.asset == "wood_plank_02":
        _build_split_plank("wood_plank_02", 1.10, 0.14, 0.04, 1, out_dir / "wood_plank_02.glb")


if __name__ == "__main__":
    main()
