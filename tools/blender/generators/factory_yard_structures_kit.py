"""Procedural Blender generator for factory yard structures and roof terrace GLBs.

Builds gritty post-Soviet industrial assets one at a time via `--asset <name>` (or `all`):
- street_light:  6.50m rusted gooseneck yard lamp pole + cobra head (<= 1,200 tris)
                 -> assets/models/props/factory_yard/street_light.glb
                 -> slots: [0: galvanized_lattice_steel, 1: rusted_steel]
- ramp_panel_01: 2.0m x 1.5m x 0.22m heavy steel diamond-plate ramp panel (<= 800 tris)
                 -> assets/models/props/factory_yard/ramp_panel_01.glb
                 -> slots: [0: steel_diamond_plate, 1: rusted_steel]
- ramp_panel_02: 2.5m x 1.2m x 0.18m ribbed/diamond-plate dock ramp panel (<= 800 tris)
                 -> assets/models/props/factory_yard/ramp_panel_02.glb
                 -> slots: [0: steel_diamond_plate, 1: rusted_steel]
- roof_terrace:  4.0m x 4.0m x 0.35m modular concrete roof terrace slab (<= 600 tris)
                 -> assets/models/factory_shells/roof_terrace.glb
                 -> slots: [0: factory_stained_concrete, 1: factory_floor_slab]

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Godot Y-up export (export_yup=True): Godot +X = Blender +X, +Y = +Z, +Z = -Y.
- Clean world-metric cubic box UVs (1.0m tile for props, 2.0m tile for 4m shells).
- Explicit material slots for Godot ORMMaterial3D surface overrides.
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


# ==============================================================================
# SHARED MESH & UV HELPERS
# ==============================================================================
def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append an axis-aligned box with optional edge chamfer to a BMesh."""
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
        face = bm.faces.new([verts[i] for i in idx])
        face.material_index = mat_idx
        created_faces.append(face)

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
        for face in res.get("faces", []):
            face.material_index = mat_idx
    return created_faces


def _add_transformed_box_bm(
    bm: bmesh.types.BMesh,
    size: tuple[float, float, float],
    matrix: Matrix,
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> None:
    """Append an oriented box of given dimensions using a 4x4 transform matrix."""
    sx, sy, sz = size
    tmp = bmesh.new()
    _add_box_bm(tmp, (-sx * 0.5, -sy * 0.5, -sz * 0.5), (sx * 0.5, sy * 0.5, sz * 0.5), mat_idx, chamfer)
    bmesh.ops.transform(tmp, matrix=matrix, verts=tmp.verts)

    vert_map: dict[bmesh.types.BMVert, bmesh.types.BMVert] = {}
    for v in tmp.verts:
        vert_map[v] = bm.verts.new(v.co)
    for f in tmp.faces:
        nf = bm.faces.new([vert_map[v] for v in f.verts])
        nf.material_index = mat_idx
    tmp.free()


def _add_cone_bm(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    radius1: float,
    radius2: float,
    depth: float,
    segments: int,
    mat_idx: int = 0,
    rot_matrix: Matrix | None = None,
) -> None:
    """Append a capped cone/cylinder primitive to a BMesh with material assignment."""
    xf = Matrix.Translation(center)
    if rot_matrix is not None:
        xf = xf @ rot_matrix
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        matrix=xf,
    )
    for v in res["verts"]:
        for f in v.link_faces:
            f.material_index = mat_idx


def _add_strut_bm(
    bm: bmesh.types.BMesh,
    p0: tuple[float, float, float],
    p1: tuple[float, float, float],
    width_x: float,
    thick_perp: float,
    mat_idx: int = 0,
) -> None:
    """Append a rectangular steel brace strut connecting p0 to p1."""
    v0 = Vector(p0)
    v1 = Vector(p1)
    vec = v1 - v0
    length = vec.length
    if length < 1e-5:
        return
    mid = (v0 + v1) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    _add_transformed_box_bm(
        bm,
        (width_x, thick_perp, length),
        Matrix.Translation(mid) @ rot,
        mat_idx=mat_idx,
        chamfer=0.002,
    )


def _apply_box_uvs(bm: bmesh.types.BMesh, tile_meters: float = 1.0) -> None:
    """Assign world-metric triplanar cubic box UVs to all face loops."""
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


def _finalize_and_export(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    out_path: Path,
    tile_meters: float = 1.0,
    auto_smooth_deg: float = 35.0,
) -> None:
    """Recalculate normals, apply auto-smooth creases + box UVs, export GLB, and log stats."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_box_uvs(bm, tile_meters=tile_meters)

    thresh_rad = math.radians(auto_smooth_deg)
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            edge.smooth = edge.calc_face_angle(0.0) <= thresh_rad
        else:
            edge.smooth = False

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)

    tri_count = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    bmin = (min(xs), min(ys), min(zs))
    bmax = (max(xs), max(ys), max(zs))
    # Godot Y-up bbox: X, Y(=Blender Z), Z(=-Blender Y)
    gmin = (min(xs), min(zs), -max(ys))
    gmax = (max(xs), max(zs), -min(ys))

    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    slots = [(i, m.name) for i, m in enumerate(mesh.materials)]
    print(
        f"[{name}] tris={tri_count} slots={slots} "
        f"blender_bbox=({bmin[0]:.3f}..{bmax[0]:.3f}, {bmin[1]:.3f}..{bmax[1]:.3f}, {bmin[2]:.3f}..{bmax[2]:.3f}) "
        f"godot_dims=({gmax[0]-gmin[0]:.3f}m W x {gmax[1]-gmin[1]:.3f}m H x {gmax[2]-gmin[2]:.3f}m D) "
        f"min_y={gmin[1]:.4f} -> {out_path}"
    )


# ==============================================================================
# 1. STREET LIGHT (6.50m gooseneck yard lamp pole + cobra head)
# ==============================================================================
def _bezier_pt_tan(
    p0: Vector, p1: Vector, p2: Vector, p3: Vector, t: float
) -> tuple[Vector, Vector]:
    """Evaluate point and unit tangent on a cubic Bezier curve."""
    u = 1.0 - t
    pt = (
        (u**3) * p0
        + 3.0 * (u**2) * t * p1
        + 3.0 * u * (t**2) * p2
        + (t**3) * p3
    )
    tan = (
        3.0 * (u**2) * (p1 - p0)
        + 6.0 * u * t * (p2 - p1)
        + 3.0 * (t**2) * (p3 - p2)
    )
    return pt, tan.normalized()


def _add_gooseneck_tube(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    p2: Vector,
    p3: Vector,
    r0: float,
    r1: float,
    steps: int,
    radial_segs: int,
    mat_idx: int,
) -> None:
    """Sweep a closed tubular gooseneck arm along a cubic Bezier in the YZ plane."""
    rings: list[list[bmesh.types.BMVert]] = []
    for i in range(steps + 1):
        t = i / steps
        pt, tan = _bezier_pt_tan(p0, p1, p2, p3, t)
        # Curve lies in YZ plane (X=0), so local +X is exact binormal
        right = Vector((1.0, 0.0, 0.0))
        up = right.cross(tan).normalized()
        rad = r0 + (r1 - r0) * t
        ring: list[bmesh.types.BMVert] = []
        for k in range(radial_segs):
            ang = 2.0 * math.pi * k / radial_segs
            pos = pt + (right * math.cos(ang) + up * math.sin(ang)) * rad
            ring.append(bm.verts.new(pos))
        rings.append(ring)

    for i in range(steps):
        r_a = rings[i]
        r_b = rings[i + 1]
        for k in range(radial_segs):
            k_next = (k + 1) % radial_segs
            f = bm.faces.new((r_a[k], r_a[k_next], r_b[k_next], r_b[k]))
            f.material_index = mat_idx

    f_start = bm.faces.new(list(reversed(rings[0])))
    f_start.material_index = mat_idx
    f_end = bm.faces.new(rings[-1])
    f_end.material_index = mat_idx


def _add_cobra_head(bm: bmesh.types.BMesh, mat_shell: int, mat_guard: int) -> None:
    """Build die-cast industrial cobra-head luminaire housing at tip of gooseneck."""
    # Lofted octagonal chamfered sections along Y from neck (-1.36) to nose (-2.00)
    # (y, half_w, z_bot, z_top, chamfer)
    sections = [
        (-1.36, 0.068, 6.210, 6.330, 0.018),
        (-1.50, 0.110, 6.220, 6.385, 0.028),
        (-1.74, 0.185, 6.230, 6.475, 0.045),
        (-1.90, 0.175, 6.240, 6.455, 0.042),
        (-2.00, 0.125, 6.255, 6.380, 0.032),
    ]
    rings: list[list[bmesh.types.BMVert]] = []
    for y, hw, zb, zt, ch in sections:
        c = min(ch, hw * 0.45, (zt - zb) * 0.40)
        pts = [
            (-hw + c, y, zb),
            (hw - c, y, zb),
            (hw, y, zb + c),
            (hw, y, zt - c),
            (hw - c, y, zt),
            (-hw + c, y, zt),
            (-hw, y, zt - c),
            (-hw, y, zb + c),
        ]
        rings.append([bm.verts.new(p) for p in pts])

    n_pts = 8
    for i in range(len(rings) - 1):
        r_a = rings[i]
        r_b = rings[i + 1]
        for k in range(n_pts):
            k_next = (k + 1) % n_pts
            f = bm.faces.new((r_a[k], r_b[k], r_b[k_next], r_a[k_next]))
            f.material_index = mat_shell

    f_back = bm.faces.new(rings[0])
    f_back.material_index = mat_shell
    f_front = bm.faces.new(list(reversed(rings[-1])))
    f_front.material_index = mat_shell

    # 3 dorsal cast-metal cooling fins peaking cleanly at Z = 6.500m
    for fx in (-0.065, 0.0, 0.065):
        _add_box_bm(bm, (fx - 0.012, -1.88, 6.44), (fx + 0.012, -1.56, 6.500), mat_shell, 0.003)

    # Underside recessed reflector bezel frame + twin guard bars (galvanized_lattice_steel)
    _add_box_bm(bm, (-0.135, -1.94, 6.205), (0.135, -1.56, 6.240), mat_guard, 0.006)
    _add_box_bm(bm, (-0.105, -1.90, 6.185), (0.105, -1.60, 6.215), mat_guard, 0.005)
    for gx in (-0.055, 0.055):
        _add_box_bm(bm, (gx - 0.008, -1.92, 6.175), (gx + 0.008, -1.58, 6.195), mat_guard)


def build_street_light(out_path: Path) -> None:
    """Generate 6.50m rusted gooseneck yard lamp pole + cobra head."""
    clean_scene()
    galv_mat = create_pbr_material(
        "galvanized_lattice_steel", (0.42, 0.44, 0.45, 1.0), metallic=0.80, roughness=0.55
    )
    rust_mat = create_pbr_material(
        "rusted_steel", (0.24, 0.16, 0.12, 1.0), metallic=0.82, roughness=0.62
    )

    bm = bmesh.new()
    # 1. Heavy square steel base plate (Z: 0.00 .. 0.035) + 4 hex anchor bolts + 4 gusset fins
    _add_box_bm(bm, (-0.21, -0.21, 0.0), (0.21, 0.21, 0.035), mat_idx=1, chamfer=0.005)
    for bx in (-0.155, 0.155):
        for by in (-0.155, 0.155):
            _add_cone_bm(bm, (bx, by, 0.047), 0.018, 0.018, 0.024, 6, mat_idx=1)

    # 4 tapered base gusset ribs bracing shaft to base plate
    for ang_deg in (0.0, 90.0, 180.0, 270.0):
        ang = math.radians(ang_deg)
        ca, sa = math.cos(ang), math.sin(ang)
        # Place gusset from r=0.095..0.185, z=0.035..0.24
        rot = Matrix.Translation((ca * 0.135, sa * 0.135, 0.13)) @ Matrix.Rotation(ang, 4, "Z")
        _add_transformed_box_bm(bm, (0.09, 0.022, 0.19), rot, mat_idx=1, chamfer=0.0)

    # 2. Lower pedestal shaft (Z: 0.035 .. 1.65)
    _add_cone_bm(bm, (0.0, 0.0, 0.8425), 0.105, 0.088, 1.615, 10, mat_idx=0)
    # Electrical access hatch plate on -Y front side (Z: 0.55 .. 1.05)
    _add_box_bm(bm, (-0.055, -0.108, 0.56), (0.055, -0.072, 1.04), mat_idx=1, chamfer=0.0)
    _add_box_bm(bm, (-0.016, -0.118, 0.78), (0.016, -0.104, 0.83), mat_idx=1, chamfer=0.0)

    # 3. Stepped transition collar ring (Z: 1.62 .. 1.72)
    _add_cone_bm(bm, (0.0, 0.0, 1.67), 0.104, 0.096, 0.10, 10, mat_idx=1)

    # 4. Upper tapered pole mast (Z: 1.72 .. 5.56)
    _add_cone_bm(bm, (0.0, 0.0, 3.64), 0.080, 0.056, 3.84, 10, mat_idx=0)

    # 5. Mast-top slip-fitter clamp collar & finial cap (Z: 5.38 .. 5.66)
    _add_cone_bm(bm, (0.0, 0.0, 5.50), 0.070, 0.068, 0.24, 10, mat_idx=1)
    _add_cone_bm(bm, (0.0, 0.0, 5.64), 0.072, 0.048, 0.05, 10, mat_idx=1)

    # 6. Swept tubular gooseneck arm (pole Z=5.46 -> apex Z=6.36 -> knuckle Y=-1.38, Z=6.27)
    _add_gooseneck_tube(
        bm,
        p0=Vector((0.0, -0.02, 5.46)),
        p1=Vector((0.0, -0.26, 6.22)),
        p2=Vector((0.0, -0.80, 6.44)),
        p3=Vector((0.0, -1.39, 6.27)),
        r0=0.042,
        r1=0.036,
        steps=8,
        radial_segs=8,
        mat_idx=0,
    )

    # 7. Diagonal under-arm brace strut + clamp collar
    _add_cone_bm(bm, (0.0, 0.0, 4.98), 0.068, 0.068, 0.08, 10, mat_idx=1)
    _add_strut_bm(bm, (0.0, -0.05, 4.98), (0.0, -0.56, 6.04), width_x=0.034, thick_perp=0.034, mat_idx=1)
    _add_box_bm(bm, (-0.046, -0.60, 5.99), (0.046, -0.51, 6.10), mat_idx=1, chamfer=0.004)

    # 8. Cobra-head luminaire + knuckle collar
    _add_cone_bm(
        bm,
        (0.0, -1.36, 6.27),
        0.052,
        0.052,
        0.10,
        8,
        mat_idx=1,
        rot_matrix=Matrix.Rotation(math.pi * 0.5, 4, "X"),
    )
    _add_cobra_head(bm, mat_shell=1, mat_guard=0)

    _finalize_and_export(
        "street_light", bm, [galv_mat, rust_mat], out_path, tile_meters=1.0, auto_smooth_deg=40.0
    )


# ==============================================================================
# 2 & 3. HEAVY STEEL RAMP PANELS (ramp_panel_01 & ramp_panel_02)
# ==============================================================================
def _add_sloped_wedge_deck(
    bm: bmesh.types.BMesh,
    half_x: float,
    y_toe: float,
    y_slope_start: float,
    y_slope_end: float,
    y_rear: float,
    z_toe_top: float,
    z_deck_top: float,
    deck_thick: float,
    mat_idx: int,
) -> None:
    """Append a manifold sloped steel ramp deck with chamfered entry toe and flat rear lip."""
    # Profile in (y, z) ordered CCW when viewed from +X
    z_bot_rear = max(0.0, z_deck_top - deck_thick)
    # Inner slope bottom follows parallel offset clipped at z=0
    z_bot_mid = max(0.0, z_toe_top + 0.028 - deck_thick)
    profile_yz = [
        (y_toe, 0.0),
        (y_slope_start, 0.0),
        (y_slope_end, z_bot_rear),
        (y_rear, z_bot_rear),
        (y_rear, z_deck_top),
        (y_slope_end, z_deck_top),
        (y_slope_start, z_toe_top + 0.028),
        (y_toe, z_toe_top),
    ]
    if z_bot_mid > 0.001:
        profile_yz[1] = (y_slope_start, z_bot_mid)

    v_l = [bm.verts.new((-half_x, y, z)) for y, z in profile_yz]
    v_r = [bm.verts.new((half_x, y, z)) for y, z in profile_yz]
    n = len(profile_yz)
    f_l = bm.faces.new(list(reversed(v_l)))
    f_l.material_index = mat_idx
    f_r = bm.faces.new(v_r)
    f_r.material_index = mat_idx
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((v_l[i], v_l[j], v_r[j], v_r[i]))
        f.material_index = mat_idx


def _add_sloped_curb_rail(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    y_toe: float,
    y_slope_end: float,
    y_rear: float,
    z_toe_curb: float,
    z_top_curb: float,
    mat_idx: int,
) -> None:
    """Append a solid steel curb rail resting flat on Z=0 along a ramp edge."""
    profile_yz = [
        (y_toe, 0.0),
        (y_rear, 0.0),
        (y_rear, z_top_curb),
        (y_slope_end, z_top_curb),
        (y_toe, z_toe_curb),
    ]
    v_l = [bm.verts.new((x0, y, z)) for y, z in profile_yz]
    v_r = [bm.verts.new((x1, y, z)) for y, z in profile_yz]
    n = len(profile_yz)
    f_l = bm.faces.new(list(reversed(v_l)))
    f_l.material_index = mat_idx
    f_r = bm.faces.new(v_r)
    f_r.material_index = mat_idx
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((v_l[i], v_l[j], v_r[j], v_r[i]))
        f.material_index = mat_idx


def build_ramp_panel_01(out_path: Path) -> None:
    """Generate 2.0m x 1.5m heavy steel diamond-plate ramp panel (<= 800 tris)."""
    clean_scene()
    diamond_mat = create_pbr_material(
        "steel_diamond_plate", (0.28, 0.29, 0.30, 1.0), metallic=0.86, roughness=0.52
    )
    rust_mat = create_pbr_material(
        "rusted_steel", (0.24, 0.16, 0.12, 1.0), metallic=0.82, roughness=0.62
    )

    bm = bmesh.new()
    # Dimensions: X in [-1.00, 1.00] (2.0m), Y in [-0.75, 0.75] (1.5m), Z in [0.00, 0.22]
    y_toe = -0.75
    y_slope_start = -0.63
    y_slope_end = 0.53
    y_rear = 0.75
    z_toe_top = 0.014
    z_deck_top = 0.185
    deck_thick = 0.055

    # 1. Main diamond-plate sloped deck (slot 0)
    _add_sloped_wedge_deck(
        bm,
        half_x=0.91,
        y_toe=y_toe,
        y_slope_start=y_slope_start,
        y_slope_end=y_slope_end,
        y_rear=y_rear,
        z_toe_top=z_toe_top,
        z_deck_top=z_deck_top,
        deck_thick=deck_thick,
        mat_idx=0,
    )

    # 2. Heavy side curb rails (slot 1 rusted_steel, rising 0.035m proud -> Z_max=0.220m)
    for x0, x1 in ((-0.99, -0.905), (0.905, 0.99)):
        _add_sloped_curb_rail(
            bm,
            x0=x0,
            x1=x1,
            y_toe=y_toe,
            y_slope_end=y_slope_end,
            y_rear=y_rear,
            z_toe_curb=0.035,
            z_top_curb=0.220,
            mat_idx=1,
        )

    # 4 corner lifting lugs / tie-down brackets flush to X = +-1.000
    for sign_x in (-1.0, 1.0):
        x_in = sign_x * 0.985
        x_out = sign_x * 1.000
        x0, x1 = (min(x_in, x_out), max(x_in, x_out))
        _add_box_bm(bm, (x0, -0.52, 0.02), (x1, -0.34, 0.085), mat_idx=1, chamfer=0.002)
        _add_box_bm(bm, (x0, 0.44, 0.06), (x1, 0.64, 0.195), mat_idx=1, chamfer=0.002)

    # 3. Underside structural bearing ribs + rear dock support beam (Z resting at 0.0)
    def _deck_bot_z(y_val: float) -> float:
        t = (y_val - y_slope_start) / (y_slope_end - y_slope_start)
        t = max(0.0, min(1.0, t))
        z_top = (z_toe_top + 0.028) + t * (z_deck_top - (z_toe_top + 0.028))
        return max(0.02, z_top - deck_thick + 0.01)

    for ry, r_thick in ((-0.15, 0.06), (0.28, 0.06), (0.68, 0.10)):
        _add_box_bm(bm, (-0.91, ry - r_thick * 0.5, 0.0), (0.91, ry + r_thick * 0.5, _deck_bot_z(ry)), mat_idx=1, chamfer=0.003)

    # 2 longitudinal underside gusset webs
    for sx in (-0.48, 0.48):
        _add_sloped_curb_rail(
            bm,
            x0=sx - 0.025,
            x1=sx + 0.025,
            y_toe=-0.50,
            y_slope_end=y_slope_end,
            y_rear=0.72,
            z_toe_curb=0.025,
            z_top_curb=0.145,
            mat_idx=1,
        )

    # 4. Rear landing anchor bar + 4 hex bolts
    _add_box_bm(bm, (-0.90, 0.63, 0.180), (0.90, 0.74, 0.198), mat_idx=1, chamfer=0.002)
    for bx in (-0.72, -0.24, 0.24, 0.72):
        _add_cone_bm(bm, (bx, 0.685, 0.205), 0.014, 0.014, 0.014, 6, mat_idx=1)

    _finalize_and_export(
        "ramp_panel_01", bm, [diamond_mat, rust_mat], out_path, tile_meters=1.0, auto_smooth_deg=35.0
    )


def build_ramp_panel_02(out_path: Path) -> None:
    """Generate 2.5m x 1.2m ribbed/diamond-plate dock ramp panel (<= 800 tris)."""
    clean_scene()
    diamond_mat = create_pbr_material(
        "steel_diamond_plate", (0.28, 0.29, 0.30, 1.0), metallic=0.86, roughness=0.52
    )
    rust_mat = create_pbr_material(
        "rusted_steel", (0.24, 0.16, 0.12, 1.0), metallic=0.82, roughness=0.62
    )

    bm = bmesh.new()
    # Dimensions: X in [-1.25, 1.25] (2.5m), Y in [-0.60, 0.60] (1.2m), Z in [0.00, 0.18]
    y_toe = -0.60
    y_slope_start = -0.50
    y_slope_end = 0.40
    y_rear = 0.60
    z_toe_top = 0.012
    z_deck_top = 0.155
    deck_thick = 0.045

    # 1. Main diamond-plate dock ramp deck (slot 0)
    _add_sloped_wedge_deck(
        bm,
        half_x=1.155,
        y_toe=y_toe,
        y_slope_start=y_slope_start,
        y_slope_end=y_slope_end,
        y_rear=y_rear,
        z_toe_top=z_toe_top,
        z_deck_top=z_deck_top,
        deck_thick=deck_thick,
        mat_idx=0,
    )

    # 2. 7 transverse welded steel anti-slip traction ribs across the sloped deck (slot 1)
    z_s0 = z_toe_top + 0.028
    slope_ang = math.atan2(z_deck_top - z_s0, y_slope_end - y_slope_start)
    rot_rib = Matrix.Rotation(slope_ang, 4, "X")
    for idx in range(7):
        t = (idx + 0.5) / 7.0
        ry = y_slope_start + 0.04 + t * (y_slope_end - y_slope_start - 0.08)
        tz = z_s0 + ((ry - y_slope_start) / (y_slope_end - y_slope_start)) * (z_deck_top - z_s0)
        _add_transformed_box_bm(
            bm,
            (2.22, 0.028, 0.022),
            Matrix.Translation((0.0, ry, tz + 0.002)) @ rot_rib,
            mat_idx=1,
            chamfer=0.002,
        )

    # 3. Heavy rolled side curb beams (X in [-1.25, -1.15] and [1.15, 1.25], Z_max = 0.180m)
    for x0, x1 in ((-1.25, -1.15), (1.15, 1.25)):
        _add_sloped_curb_rail(
            bm,
            x0=x0,
            x1=x1,
            y_toe=y_toe,
            y_slope_end=y_slope_end,
            y_rear=y_rear,
            z_toe_curb=0.032,
            z_top_curb=0.180,
            mat_idx=1,
        )

    # 4. Rear dock-hook flange & front hinged threshold lip (slot 1)
    _add_box_bm(bm, (-1.15, 0.42, 0.150), (1.15, 0.595, 0.168), mat_idx=1, chamfer=0.003)
    # 3 underside bearing stringers + rear cross-beam resting on Z = 0.0
    _add_box_bm(bm, (-1.15, 0.46, 0.0), (1.15, 0.59, 0.125), mat_idx=1, chamfer=0.003)
    for sx in (-0.75, 0.0, 0.75):
        _add_sloped_curb_rail(
            bm,
            x0=sx - 0.028,
            x1=sx + 0.028,
            y_toe=-0.42,
            y_slope_end=y_slope_end,
            y_rear=0.46,
            z_toe_curb=0.025,
            z_top_curb=0.125,
            mat_idx=1,
        )

    # Twin forklift pickup loops on top rear corners
    for lx in (-0.98, 0.98):
        _add_box_bm(bm, (lx - 0.07, 0.46, 0.165), (lx + 0.07, 0.54, 0.180), mat_idx=1, chamfer=0.002)

    _finalize_and_export(
        "ramp_panel_02", bm, [diamond_mat, rust_mat], out_path, tile_meters=1.0, auto_smooth_deg=35.0
    )


# ==============================================================================
# 4. ROOF TERRACE (4.0m x 4.0m x 0.35m modular concrete roof terrace slab)
# ==============================================================================
def build_roof_terrace(out_path: Path) -> None:
    """Generate 4.0m x 4.0m x 0.35m modular concrete roof terrace slab (<= 600 tris)."""
    clean_scene()
    stained_mat = create_pbr_material(
        "factory_stained_concrete", (0.40, 0.39, 0.37, 1.0), metallic=0.0, roughness=0.90
    )
    slab_mat = create_pbr_material(
        "factory_floor_slab", (0.46, 0.45, 0.43, 1.0), metallic=0.0, roughness=0.86
    )

    bm = bmesh.new()
    # Modular 4.0m x 4.0m x 0.35m matching factory_shells 4m grid & terrace_parapet_4m (0.35m thick)
    half = 2.00
    rim = 0.22
    joint_h = 0.008
    slab_top = 0.350
    deck_base = 0.310
    soffit_z = 0.100

    # 1. Underside precast concrete coffer beams (Z: 0.00 .. 0.10, slot 0 factory_stained_concrete)
    # Outer perimeter beams (width 0.35m matching wall/parapet thickness)
    _add_box_bm(bm, (-half, -half, 0.0), (half, -half + 0.35, soffit_z), mat_idx=0, chamfer=0.0)
    _add_box_bm(bm, (-half, half - 0.35, 0.0), (half, half, soffit_z), mat_idx=0, chamfer=0.0)
    _add_box_bm(bm, (-half, -half + 0.35, 0.0), (-half + 0.35, half - 0.35, soffit_z), mat_idx=0, chamfer=0.0)
    _add_box_bm(bm, (half - 0.35, -half + 0.35, 0.0), (half, half - 0.35, soffit_z), mat_idx=0, chamfer=0.0)
    # Central cross ribs underneath
    _add_box_bm(bm, (-0.14, -half + 0.35, 0.0), (0.14, half - 0.35, soffit_z), mat_idx=0, chamfer=0.0)
    _add_box_bm(bm, (-half + 0.35, -0.14, 0.0), (-0.14, 0.14, soffit_z), mat_idx=0, chamfer=0.0)
    _add_box_bm(bm, (0.14, -0.14, 0.0), (half - 0.35, 0.14, soffit_z), mat_idx=0, chamfer=0.0)

    # 2. Main structural concrete slab core (Z: 0.10 .. 0.31, slot 0)
    _add_box_bm(bm, (-half, -half, soffit_z), (half, half, deck_base), mat_idx=0, chamfer=0.0)

    # 3. Top outer concrete parapet-seat border frame (Z: 0.31 .. 0.35, slot 0)
    _add_box_bm(bm, (-half, -half, deck_base), (half, -half + rim, slab_top), mat_idx=0, chamfer=0.0)
    _add_box_bm(bm, (-half, half - rim, deck_base), (half, half, slab_top), mat_idx=0, chamfer=0.0)
    _add_box_bm(bm, (-half, -half + rim, deck_base), (-half + rim, half - rim, slab_top), mat_idx=0, chamfer=0.0)
    _add_box_bm(bm, (half - rim, -half + rim, deck_base), (half, half - rim, slab_top), mat_idx=0, chamfer=0.0)

    # 4. 4 poured terrace floor slab quadrant bays inside perimeter frame (Z: 0.31 .. 0.35, slot 1)
    inner = half - rim - 0.010  # 10mm reveal gap around perimeter border
    quadrants = [
        (-inner, -joint_h, -inner, -joint_h),
        (joint_h, inner, -inner, -joint_h),
        (-inner, -joint_h, joint_h, inner),
        (joint_h, inner, joint_h, inner),
    ]
    for x0, x1, y0, y1 in quadrants:
        _add_box_bm(bm, (x0, y0, deck_base), (x1, y1, slab_top), mat_idx=1, chamfer=0.008)

    _finalize_and_export(
        "roof_terrace", bm, [stained_mat, slab_mat], out_path, tile_meters=2.0, auto_smooth_deg=35.0
    )


def main() -> None:
    """CLI entrypoint for generating factory yard structures and roof terrace GLBs."""
    parser = argparse.ArgumentParser(description="Generate factory yard structure GLBs.")
    parser.add_argument(
        "--asset",
        default="all",
        choices=["street_light", "ramp_panel_01", "ramp_panel_02", "roof_terrace", "all"],
        help="Asset to generate (default: all).",
    )
    args, _ = parser.parse_known_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])

    builders = {
        "street_light": (
            build_street_light,
            _REPO_ROOT / "assets/models/props/factory_yard/street_light.glb",
        ),
        "ramp_panel_01": (
            build_ramp_panel_01,
            _REPO_ROOT / "assets/models/props/factory_yard/ramp_panel_01.glb",
        ),
        "ramp_panel_02": (
            build_ramp_panel_02,
            _REPO_ROOT / "assets/models/props/factory_yard/ramp_panel_02.glb",
        ),
        "roof_terrace": (
            build_roof_terrace,
            _REPO_ROOT / "assets/models/factory_shells/roof_terrace.glb",
        ),
    }

    targets = list(builders.keys()) if args.asset == "all" else [args.asset]
    for name in targets:
        fn, out_path = builders[name]
        fn(out_path)


if __name__ == "__main__":
    main()
