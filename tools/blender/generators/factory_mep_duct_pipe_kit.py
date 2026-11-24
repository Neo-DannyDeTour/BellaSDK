"""Procedural Blender generator for modular factory workshop MEP duct & pipe runs.

Generates 3 modular MEP prop GLBs in assets/models/props/factory_workshop/:
1. ac_duct_straight_4m.glb   - 4.0m x 0.75m x 0.56m galvanized rectangular HVAC duct with bolted
                               flange collars at X=+/-1.98 & X=0, plus 2 ceiling hanger U-strap pairs.
2. ac_duct_elbow_90.glb      - 1.0m grid (0.78m x 0.46m x 0.78m mesh) 90-deg HVAC elbow (+X port to
                               Godot +Z port) with bolted flanges & underside louvered diffuser grille.
3. steel_pipe_straight_4m.glb - 4.0m x 0.50m x 0.24m twin parallel horizontal industrial steel pipes
                               (diam 0.16m @ Y=0.16, diam 0.09m @ Y=0.40) with end flanges, center
                               coupling collar, and 3 welded wall-standoff U-clamp support brackets.

Conventions:
- Godot Y-up export (export_yup=True): Godot +X = Blender +X, +Y = +Z, +Z = -Y.
- Origin grounded at min_z = 0.0 in Blender (min_y = 0.0 in Godot).
- Clean world-metric 1.0m cubic box UVs.
- Deterministic material slot ordering logged with tris, blender_bbox, and godot_bbox.
"""

from __future__ import annotations

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


def _merge_temp_bmesh(
    src: bmesh.types.BMesh,
    dst: bmesh.types.BMesh,
    mat_idx: int,
    smooth_faces: bool = False,
) -> list[bmesh.types.BMFace]:
    """Copy all geometry from src BMesh into dst BMesh with target material index."""
    vert_map: dict[bmesh.types.BMVert, bmesh.types.BMVert] = {}
    for v in src.verts:
        vert_map[v] = dst.verts.new(v.co)

    created_faces: list[bmesh.types.BMFace] = []
    for f in src.faces:
        new_verts = [vert_map[v] for v in f.verts]
        nf = dst.faces.new(new_verts)
        nf.material_index = mat_idx
        nf.smooth = smooth_faces
        created_faces.append(nf)

    src.free()
    return created_faces


def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append an axis-aligned box with optional edge chamfer to BMesh."""
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        return []

    cx = 0.5 * (x0 + x1)
    cy = 0.5 * (y0 + y1)
    cz = 0.5 * (z0 + z1)
    sx = x1 - x0
    sy = y1 - y0
    sz = z1 - z0

    tmp = bmesh.new()
    xf = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    bmesh.ops.create_cube(tmp, size=1.0, matrix=xf)
    if chamfer > 0.0:
        c_limit = min(chamfer, min(sx, sy, sz) * 0.25)
        if c_limit > 1e-5:
            bmesh.ops.bevel(
                tmp,
                geom=list(tmp.edges),
                offset=c_limit,
                segments=1,
                affect="EDGES",
                clamp_overlap=True,
            )
    return _merge_temp_bmesh(tmp, bm, mat_idx, smooth_faces=False)


def _add_oriented_box_bm(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    rotation_deg: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append a rotated box centered at `center` with XYZ `size` and Euler degrees."""
    sx, sy, sz = size
    rot = (
        Matrix.Rotation(math.radians(rotation_deg[2]), 4, "Z")
        @ Matrix.Rotation(math.radians(rotation_deg[1]), 4, "Y")
        @ Matrix.Rotation(math.radians(rotation_deg[0]), 4, "X")
    )
    xf = Matrix.Translation(center) @ rot @ Matrix.Diagonal((sx, sy, sz, 1.0))

    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0, matrix=xf)
    if chamfer > 0.0:
        c_limit = min(chamfer, min(sx, sy, sz) * 0.25)
        if c_limit > 1e-5:
            bmesh.ops.bevel(
                tmp,
                geom=list(tmp.edges),
                offset=c_limit,
                segments=1,
                affect="EDGES",
                clamp_overlap=True,
            )
    return _merge_temp_bmesh(tmp, bm, mat_idx, smooth_faces=False)


def _add_strut_bm(
    bm: bmesh.types.BMesh,
    p0: tuple[float, float, float],
    p1: tuple[float, float, float],
    width_x: float,
    thickness: float,
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    """Append a rectangular gusset/brace strut spanning p0 -> p1 with width along X."""
    v0 = Vector(p0)
    v1 = Vector(p1)
    vec = v1 - v0
    length = vec.length
    if length < 1e-5:
        return []
    z_axis = vec.normalized()
    ref_x = Vector((1.0, 0.0, 0.0))
    if abs(z_axis.dot(ref_x)) > 0.98:
        ref_x = Vector((0.0, 1.0, 0.0))
    y_axis = z_axis.cross(ref_x).normalized()
    x_axis = y_axis.cross(z_axis).normalized()

    rot = Matrix((x_axis, y_axis, z_axis)).transposed().to_4x4()
    mid = (v0 + v1) * 0.5
    xf = Matrix.Translation(mid) @ rot @ Matrix.Diagonal((width_x, thickness, length, 1.0))

    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0, matrix=xf)
    return _merge_temp_bmesh(tmp, bm, mat_idx, smooth_faces=False)


def _add_cylinder_bm(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    axis: str,
    radius: float,
    depth: float,
    segments: int,
    mat_idx: int = 0,
    smooth_sides: bool = True,
) -> list[bmesh.types.BMFace]:
    """Append a closed cylinder oriented along X, Y, or Z with optional smooth side walls."""
    rot = Matrix.Identity(4)
    if axis == "X":
        rot = Matrix.Rotation(math.pi * 0.5, 4, "Y")
    elif axis == "Y":
        rot = Matrix.Rotation(math.pi * 0.5, 4, "X")
    xf = Matrix.Translation(center) @ rot

    tmp = bmesh.new()
    bmesh.ops.create_cone(
        tmp,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
        matrix=xf,
    )

    axis_vec = Vector((1.0, 0.0, 0.0)) if axis == "X" else (
        Vector((0.0, 1.0, 0.0)) if axis == "Y" else Vector((0.0, 0.0, 1.0))
    )
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    for f in tmp.faces:
        is_cap = abs(f.normal.dot(axis_vec)) > 0.9
        f.smooth = smooth_sides and (not is_cap)

    if smooth_sides:
        cap_rim_edges = [
            e
            for e in tmp.edges
            if len(e.link_faces) == 2 and e.link_faces[0].smooth != e.link_faces[1].smooth
        ]
        if cap_rim_edges:
            bmesh.ops.split_edges(tmp, edges=cap_rim_edges)

    vert_map: dict[bmesh.types.BMVert, bmesh.types.BMVert] = {}
    for v in tmp.verts:
        vert_map[v] = bm.verts.new(v.co)
    faces: list[bmesh.types.BMFace] = []
    for f in tmp.faces:
        nf = bm.faces.new([vert_map[v] for v in f.verts])
        nf.material_index = mat_idx
        nf.smooth = f.smooth
        faces.append(nf)
    tmp.free()
    return faces


def _add_rect_frame_x_bm(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    half_y: float,
    z0: float,
    z1: float,
    rim_y: float,
    rim_z: float,
    mat_idx: int = 1,
    chamfer: float = 0.002,
) -> None:
    """Append a 4-bar rectangular flange frame aligned perpendicular to X."""
    _add_box_bm(bm, (x0, -half_y, z0), (x1, half_y, z0 + rim_z), mat_idx, chamfer)
    _add_box_bm(bm, (x0, -half_y, z1 - rim_z), (x1, half_y, z1), mat_idx, chamfer)
    _add_box_bm(bm, (x0, -half_y, z0 + rim_z), (x1, -half_y + rim_y, z1 - rim_z), mat_idx, chamfer)
    _add_box_bm(bm, (x0, half_y - rim_y, z0 + rim_z), (x1, half_y, z1 - rim_z), mat_idx, chamfer)


def _add_rect_frame_y_bm(
    bm: bmesh.types.BMesh,
    y0: float,
    y1: float,
    half_x: float,
    z0: float,
    z1: float,
    rim_x: float,
    rim_z: float,
    mat_idx: int = 1,
    chamfer: float = 0.002,
) -> None:
    """Append a 4-bar rectangular flange frame aligned perpendicular to Y."""
    _add_box_bm(bm, (-half_x, y0, z0), (half_x, y1, z0 + rim_z), mat_idx, chamfer)
    _add_box_bm(bm, (-half_x, y0, z1 - rim_z), (half_x, y1, z1), mat_idx, chamfer)
    _add_box_bm(bm, (-half_x, y0, z0 + rim_z), (-half_x + rim_x, y1, z1 - rim_z), mat_idx, chamfer)
    _add_box_bm(bm, (half_x - rim_x, y0, z0 + rim_z), (half_x, y1, z1 - rim_z), mat_idx, chamfer)


def _add_u_clamp_strap_bm(
    bm: bmesh.types.BMesh,
    x_center: float,
    width_x: float,
    pipe_z: float,
    r_inner: float,
    thickness: float,
    segments: int,
    mat_idx: int = 1,
) -> None:
    """Append a semicircular front-facing (-Y) steel U-clamp strap with rear mounting ears."""
    x0 = x_center - width_x * 0.5
    x1 = x_center + width_x * 0.5
    r_outer = r_inner + thickness

    tmp = bmesh.new()
    # Arc from top (+Z, angle pi/2) through front (-Y, angle pi) to bottom (-Z, angle 3*pi/2)
    # Using local (y, z) = (r * cos(a), pipe_z + r * sin(a))
    inner_pts_l: list[bmesh.types.BMVert] = []
    inner_pts_r: list[bmesh.types.BMVert] = []
    outer_pts_l: list[bmesh.types.BMVert] = []
    outer_pts_r: list[bmesh.types.BMVert] = []

    for i in range(segments + 1):
        ang = math.pi * 0.5 + math.pi * (float(i) / float(segments))
        ca = math.cos(ang)
        sa = math.sin(ang)
        yi, zi = r_inner * ca, pipe_z + r_inner * sa
        yo, zo = r_outer * ca, pipe_z + r_outer * sa
        inner_pts_l.append(tmp.verts.new((x0, yi, zi)))
        inner_pts_r.append(tmp.verts.new((x1, yi, zi)))
        outer_pts_l.append(tmp.verts.new((x0, yo, zo)))
        outer_pts_r.append(tmp.verts.new((x1, yo, zo)))

    for i in range(segments):
        # Outer curved band
        tmp.faces.new((outer_pts_l[i], outer_pts_l[i + 1], outer_pts_r[i + 1], outer_pts_r[i]))
        # Inner curved band
        tmp.faces.new((inner_pts_l[i], inner_pts_r[i], inner_pts_r[i + 1], inner_pts_l[i + 1]))
        # Side cheeks (-X and +X)
        tmp.faces.new((inner_pts_l[i], inner_pts_l[i + 1], outer_pts_l[i + 1], outer_pts_l[i]))
        tmp.faces.new((inner_pts_r[i], outer_pts_r[i], outer_pts_r[i + 1], inner_pts_r[i + 1]))

    # End caps at top (i=0) and bottom (i=segments)
    tmp.faces.new((inner_pts_l[0], outer_pts_l[0], outer_pts_r[0], inner_pts_r[0]))
    tmp.faces.new((inner_pts_l[-1], inner_pts_r[-1], outer_pts_r[-1], outer_pts_l[-1]))

    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    _merge_temp_bmesh(tmp, bm, mat_idx, smooth_faces=False)

    # Rear strap legs extending back from Y=0 to Y=+0.095 so clamp meets rear standoff spine
    _add_box_bm(
        bm,
        (x0, 0.0, pipe_z + r_inner),
        (x1, 0.095, pipe_z + r_outer),
        mat_idx=mat_idx,
        chamfer=0.0,
    )
    _add_box_bm(
        bm,
        (x0, 0.0, pipe_z - r_outer),
        (x1, 0.095, pipe_z - r_inner),
        mat_idx=mat_idx,
        chamfer=0.0,
    )


def _apply_box_uvs(bm: bmesh.types.BMesh, tile_meters: float = 1.0) -> None:
    """Assign world-metric cubic box UVs across all face loops."""
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
    output_dir: Path,
) -> dict[str, object]:
    """Finalize normals/UVs, create mesh object, apply transforms, verify slots/bounds, and export."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_box_uvs(bm, tile_meters=1.0)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    slots = [(i, m.name) for i, m in enumerate(obj.data.materials)]
    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    blender_bbox = (
        round(min(xs), 4),
        round(max(xs), 4),
        round(min(ys), 4),
        round(max(ys), 4),
        round(min(zs), 4),
        round(max(zs), 4),
    )
    godot_bbox = (
        round(min(xs), 4),
        round(max(xs), 4),
        round(min(zs), 4),
        round(max(zs), 4),
        round(-max(ys), 4),
        round(-min(ys), 4),
    )

    out_path = output_dir / f"{name}.glb"
    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    print(
        f"[{name}] slots={slots} tris={tri_count} "
        f"blender_bbox={blender_bbox} godot_bbox={godot_bbox} path={out_path}"
    )
    return {
        "name": name,
        "path": out_path,
        "slots": slots,
        "tris": tri_count,
        "blender_bbox": blender_bbox,
        "godot_bbox": godot_bbox,
    }


def generate_ac_duct_straight_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 0.75m x 0.56m galvanized rectangular HVAC duct with flanges & hangers."""
    clean_scene()
    conduit_mat = create_pbr_material(
        "conduit", base_color=(0.48, 0.50, 0.52, 1.0), metallic=0.80, roughness=0.45
    )
    steel_mat = create_pbr_material(
        "steel", base_color=(0.24, 0.16, 0.12, 1.0), metallic=0.82, roughness=0.62
    )

    bm = bmesh.new()

    # Duct body: 0.50m W (Y in [-0.25, 0.25]) x 0.40m H (Z in [0.03, 0.43]) inside 0.56 x 0.46 flanges
    # Keeps min_z = 0.0 and aligns centerline Z = 0.23 with ac_duct_elbow_90.
    duct_z0, duct_z1 = 0.03, 0.43
    _add_box_bm(bm, (-1.985, -0.25, duct_z0), (1.985, 0.25, duct_z1), mat_idx=0, chamfer=0.006)

    # Folded sheet-metal stiffening ribs at quarter spans (X = -1.0, +1.0)
    for rx in (-1.0, 1.0):
        _add_box_bm(
            bm,
            (rx - 0.014, -0.256, duct_z0 - 0.006),
            (rx + 0.014, 0.256, duct_z1 + 0.006),
            mat_idx=0,
            chamfer=0.002,
        )

    # Bolted rectangular flange collars (0.56m x 0.46m, Z in [0.0, 0.46]) at X = +/-1.98 and X = 0.0
    bolt_yz = [
        (-0.252, 0.028),
        (0.0, 0.028),
        (0.252, 0.028),
        (-0.252, 0.230),
        (0.252, 0.230),
        (-0.252, 0.432),
        (0.0, 0.432),
        (0.252, 0.432),
    ]

    # End flanges (outer bolt faces flush at X = +/-2.000)
    for sign in (-1.0, 1.0):
        fx0, fx1 = (sign * 1.964, sign * 1.992) if sign > 0 else (-1.992, -1.964)
        _add_rect_frame_x_bm(
            bm,
            x0=fx0,
            x1=fx1,
            half_y=0.28,
            z0=0.0,
            z1=0.46,
            rim_y=0.055,
            rim_z=0.055,
            mat_idx=1,
            chamfer=0.0,
        )
        bolt_cx = sign * 1.978
        for by, bz in bolt_yz:
            _add_cylinder_bm(
                bm,
                center=(bolt_cx, by, bz),
                axis="X",
                radius=0.010,
                depth=0.044,  # protrudes to +/-2.000
                segments=6,
                mat_idx=1,
                smooth_sides=False,
            )

    # Center coupling flange collar at X = 0.0
    _add_rect_frame_x_bm(
        bm,
        x0=-0.022,
        x1=0.022,
        half_y=0.28,
        z0=0.0,
        z1=0.46,
        rim_y=0.055,
        rim_z=0.055,
        mat_idx=1,
        chamfer=0.0,
    )
    for by, bz in bolt_yz:
        _add_cylinder_bm(
            bm,
            center=(0.0, by, bz),
            axis="X",
            radius=0.010,
            depth=0.060,
            segments=6,
            mat_idx=1,
            smooth_sides=False,
        )

    # 2 pairs of vertical steel ceiling hanger rods + U-straps (Z up to 0.75m)
    for hx in (-1.15, 1.15):
        # Bottom U-strap cross-bar beneath duct (Z=0.014..0.030 >= 0.0)
        _add_box_bm(bm, (hx - 0.022, -0.268, 0.014), (hx + 0.022, 0.268, 0.032), mat_idx=1, chamfer=0.0)
        for side in (-1.0, 1.0):
            # Vertical U-strap side leg
            y_in = side * 0.250
            y_out = side * 0.268
            _add_box_bm(
                bm,
                (hx - 0.022, min(y_in, y_out), 0.014),
                (hx + 0.022, max(y_in, y_out), 0.448),
                mat_idx=1,
                chamfer=0.0,
            )
            # Top hanger clevis bracket ear (stays within Y in [-0.28, 0.28])
            ey0, ey1 = (0.236, 0.278) if side > 0 else (-0.278, -0.236)
            _add_box_bm(bm, (hx - 0.024, ey0, 0.430), (hx + 0.024, ey1, 0.456), mat_idx=1, chamfer=0.0)

            # Vertical ceiling threaded hanger rod rising Godot Y = 0.43..0.75
            rod_y = side * 0.257
            _add_cylinder_bm(
                bm,
                center=(hx, rod_y, 0.598),
                axis="Z",
                radius=0.010,
                depth=0.290,
                segments=8,
                mat_idx=1,
                smooth_sides=True,
            )
            # Lower lock nut on clevis
            _add_cylinder_bm(
                bm,
                center=(hx, rod_y, 0.464),
                axis="Z",
                radius=0.016,
                depth=0.016,
                segments=6,
                mat_idx=1,
                smooth_sides=False,
            )
            # Upper ceiling anchor plate flush at Z = 0.750
            _add_box_bm(
                bm,
                (hx - 0.024, rod_y - 0.021, 0.736),
                (hx + 0.024, rod_y + 0.021, 0.750),
                mat_idx=1,
                chamfer=0.0,
            )

    return _finalize_and_export(
        "ac_duct_straight_4m",
        bm,
        [conduit_mat, steel_mat],
        output_dir,
    )


def generate_ac_duct_elbow_90(output_dir: Path) -> dict[str, object]:
    """Build 90-deg rectangular HVAC elbow (+X port to Godot +Z / Blender -Y port) with diffuser."""
    clean_scene()
    conduit_mat = create_pbr_material(
        "conduit", base_color=(0.48, 0.50, 0.52, 1.0), metallic=0.80, roughness=0.45
    )
    steel_mat = create_pbr_material(
        "steel", base_color=(0.24, 0.16, 0.12, 1.0), metallic=0.82, roughness=0.62
    )

    bm = bmesh.new()

    # Cross-section: 0.50m W x 0.40m H (Z in [0.03, 0.43]) inside 0.56m x 0.46m flanges (Z in [0.0, 0.46]).
    # +X port at Blender (0.50, 0.0, 0.23), Godot +Z port at Blender (0.0, -0.50, 0.23).
    # Straight 0.04m port stubs + 90-deg sweep centered at C = (0.46, -0.46) with R_center = 0.46m.
    duct_z0, duct_z1 = 0.03, 0.43
    half_w = 0.25
    cx, cy = 0.46, -0.46
    r_inner = 0.46 - half_w  # 0.21m
    r_outer = 0.46 + half_w  # 0.71m

    # Build curved sweep cross-sections (from +X straight stub -> arc -> -Y straight stub)
    # Recessed 9mm inside the 0.494 flange face to avoid coplanar Z-fighting with steel flange bars.
    n_arc = 12
    profile_frames: list[tuple[tuple[float, float], tuple[float, float]]] = []
    # 0: +X port end (at X=0.485, Y in [-0.25, +0.25])
    profile_frames.append(((0.485, -half_w), (0.485, half_w)))
    # 1..n_arc+1: arc sweep from theta = 90 deg to 180 deg around C=(0.46, -0.46)
    for i in range(n_arc + 1):
        theta = math.pi * 0.5 + math.pi * 0.5 * (float(i) / float(n_arc))
        ct = math.cos(theta)
        st = math.sin(theta)
        p_in = (cx + r_inner * ct, cy + r_inner * st)
        p_out = (cx + r_outer * ct, cy + r_outer * st)
        profile_frames.append((p_in, p_out))
    # Last: -Y port end (Godot +Z port at Y=-0.485, X in [-0.25, +0.25])
    profile_frames.append(((half_w, -0.485), (-half_w, -0.485)))

    sweep_bm = bmesh.new()
    rings: list[tuple[bmesh.types.BMVert, bmesh.types.BMVert, bmesh.types.BMVert, bmesh.types.BMVert]] = []
    for p_in, p_out in profile_frames:
        v_ib = sweep_bm.verts.new((p_in[0], p_in[1], duct_z0))
        v_ob = sweep_bm.verts.new((p_out[0], p_out[1], duct_z0))
        v_ot = sweep_bm.verts.new((p_out[0], p_out[1], duct_z1))
        v_it = sweep_bm.verts.new((p_in[0], p_in[1], duct_z1))
        rings.append((v_ib, v_ob, v_ot, v_it))

    for i in range(len(rings) - 1):
        a = rings[i]
        b = rings[i + 1]
        is_arc_seg = 1 <= i <= n_arc - 1
        # Bottom face (flat)
        f_bot = sweep_bm.faces.new((a[0], a[1], b[1], b[0]))
        f_bot.smooth = False
        # Outer curved wall (smooth on arc)
        f_out = sweep_bm.faces.new((a[1], a[2], b[2], b[1]))
        f_out.smooth = is_arc_seg
        # Top face (flat)
        f_top = sweep_bm.faces.new((a[2], a[3], b[3], b[2]))
        f_top.smooth = False
        # Inner curved wall (smooth on arc)
        f_in = sweep_bm.faces.new((a[3], a[0], b[0], b[3]))
        f_in.smooth = is_arc_seg

    # End caps (flat)
    f_start = sweep_bm.faces.new((rings[0][0], rings[0][3], rings[0][2], rings[0][1]))
    f_start.smooth = False
    f_end = sweep_bm.faces.new((rings[-1][0], rings[-1][1], rings[-1][2], rings[-1][3]))
    f_end.smooth = False

    bmesh.ops.recalc_face_normals(sweep_bm, faces=sweep_bm.faces)
    sharp_edges = [
        e
        for e in sweep_bm.edges
        if len(e.link_faces) == 2 and (not e.link_faces[0].smooth or not e.link_faces[1].smooth)
    ]
    if sharp_edges:
        bmesh.ops.split_edges(sweep_bm, edges=sharp_edges)

    vert_map: dict[bmesh.types.BMVert, bmesh.types.BMVert] = {}
    for v in sweep_bm.verts:
        vert_map[v] = bm.verts.new(v.co)
    for f in sweep_bm.faces:
        nf = bm.faces.new([vert_map[v] for v in f.verts])
        nf.material_index = 0
        nf.smooth = f.smooth
    sweep_bm.free()

    # 2 gore-seam stiffening ribs around curved duct body (top + side walls, clear of underside diffuser)
    for deg in (112.5, 157.5):
        rad = math.radians(deg)
        mx = cx + 0.46 * math.cos(rad)
        my = cy + 0.46 * math.sin(rad)
        _add_oriented_box_bm(
            bm,
            center=(mx, my, 0.236),
            size=(0.022, 0.514, 0.404),
            rotation_deg=(0.0, 0.0, deg - 90.0),
            mat_idx=0,
            chamfer=0.002,
        )

    # Bolted end flange frames on both ports (0.56m x 0.46m, Z in [0.0, 0.46])
    bolt_offsets_perp = (-0.252, 0.0, 0.252)
    bolt_zs = (0.028, 0.230, 0.432)

    # +X port flange (X in [0.462, 0.494], bolts flush at X = 0.500)
    _add_rect_frame_x_bm(
        bm,
        x0=0.462,
        x1=0.494,
        half_y=0.28,
        z0=0.0,
        z1=0.46,
        rim_y=0.055,
        rim_z=0.055,
        mat_idx=1,
        chamfer=0.002,
    )
    for by in bolt_offsets_perp:
        for bz in bolt_zs:
            if by == 0.0 and bz == 0.230:
                continue
            _add_cylinder_bm(
                bm,
                center=(0.478, by, bz),
                axis="X",
                radius=0.010,
                depth=0.044,  # max X = 0.500
                segments=6,
                mat_idx=1,
                smooth_sides=False,
            )

    # Godot +Z port flange (Blender Y in [-0.494, -0.462], bolts flush at Blender Y = -0.500)
    _add_rect_frame_y_bm(
        bm,
        y0=-0.494,
        y1=-0.462,
        half_x=0.28,
        z0=0.0,
        z1=0.46,
        rim_x=0.055,
        rim_z=0.055,
        mat_idx=1,
        chamfer=0.002,
    )
    for bx in bolt_offsets_perp:
        for bz in bolt_zs:
            if bx == 0.0 and bz == 0.230:
                continue
            _add_cylinder_bm(
                bm,
                center=(bx, -0.478, bz),
                axis="Y",
                radius=0.010,
                depth=0.044,  # min Y = -0.500 (Godot max Z = +0.500)
                segments=6,
                mat_idx=1,
                smooth_sides=False,
            )

    # Underside slatted steel diffuser vent grille (0.40m x 0.40m) centered on elbow underside
    diff_ang = math.radians(135.0)
    diff_cx = cx + 0.46 * math.cos(diff_ang)
    diff_cy = cy + 0.46 * math.sin(diff_ang)
    diff_rot_z = 45.0
    rad45 = math.radians(diff_rot_z)
    cos45, sin45 = math.cos(rad45), math.sin(rad45)

    # 4-bar 0.40m x 0.40m bezel frame (Z in [0.012, 0.036] -> cleanly above min_z=0.0)
    frame_half = 0.20
    rim = 0.030
    frame_mid = frame_half - rim * 0.5
    inner_len = 0.40 - 2.0 * rim
    for sign in (-1.0, 1.0):
        # Local X bars
        lx, ly = 0.0, sign * frame_mid
        wx = diff_cx + lx * cos45 - ly * sin45
        wy = diff_cy + lx * sin45 + ly * cos45
        _add_oriented_box_bm(
            bm, (wx, wy, 0.024), (0.40, rim, 0.024), (0.0, 0.0, diff_rot_z), mat_idx=1, chamfer=0.002
        )
        # Local Y bars
        lx2, ly2 = sign * frame_mid, 0.0
        wx2 = diff_cx + lx2 * cos45 - ly2 * sin45
        wy2 = diff_cy + lx2 * sin45 + ly2 * cos45
        _add_oriented_box_bm(
            bm, (wx2, wy2, 0.024), (rim, inner_len, 0.024), (0.0, 0.0, diff_rot_z), mat_idx=1, chamfer=0.002
        )

    # Recessed dark steel diffuser plenum plate behind slats (strictly below Z=0.030 duct bottom)
    _add_oriented_box_bm(
        bm,
        (diff_cx, diff_cy, 0.0265),
        (inner_len, inner_len, 0.005),
        (0.0, 0.0, diff_rot_z),
        mat_idx=1,
        chamfer=0.0,
    )

    # 7 angled louver slats + central divider spine
    for s_idx in range(-3, 4):
        ly_local = s_idx * 0.044
        wx = diff_cx - ly_local * sin45
        wy = diff_cy + ly_local * cos45
        _add_oriented_box_bm(
            bm,
            (wx, wy, 0.019),
            (inner_len, 0.020, 0.006),
            (30.0, 0.0, diff_rot_z),
            mat_idx=1,
            chamfer=0.0,
        )
    _add_oriented_box_bm(
        bm,
        (diff_cx, diff_cy, 0.019),
        (0.014, inner_len, 0.012),
        (0.0, 0.0, diff_rot_z),
        mat_idx=1,
        chamfer=0.0,
    )

    return _finalize_and_export(
        "ac_duct_elbow_90",
        bm,
        [conduit_mat, steel_mat],
        output_dir,
    )


def generate_steel_pipe_straight_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 0.50m x 0.24m twin parallel steel pipes with flanges, coupling & 3 brackets."""
    clean_scene()
    painted_mat = create_pbr_material(
        "painted_metal", base_color=(0.20, 0.34, 0.38, 1.0), metallic=0.45, roughness=0.62
    )
    steel_mat = create_pbr_material(
        "steel", base_color=(0.24, 0.16, 0.12, 1.0), metallic=0.82, roughness=0.62
    )

    bm = bmesh.new()

    lower_z = 0.16
    lower_r = 0.080  # diam 0.16m
    upper_z = 0.40
    upper_r = 0.045  # diam 0.09m

    # Slot 0 (painted_metal): Twin horizontal pipe barrels spanning X in [-2.0, 2.0]
    _add_cylinder_bm(
        bm,
        center=(0.0, 0.0, lower_z),
        axis="X",
        radius=lower_r,
        depth=4.0,
        segments=16,
        mat_idx=0,
        smooth_sides=True,
    )
    _add_cylinder_bm(
        bm,
        center=(0.0, 0.0, upper_z),
        axis="X",
        radius=upper_r,
        depth=4.0,
        segments=12,
        mat_idx=0,
        smooth_sides=True,
    )

    # Slot 1 (steel): Bolted circular end flanges at X = +/-1.97
    for sign in (-1.0, 1.0):
        fx = sign * 1.97
        # Lower main pipe flange + 6 hex bolts
        _add_cylinder_bm(
            bm,
            center=(fx, 0.0, lower_z),
            axis="X",
            radius=0.115,
            depth=0.028,
            segments=12,
            mat_idx=1,
            smooth_sides=True,
        )
        for k in range(6):
            ang = math.radians(k * 60.0 + 30.0)
            by = 0.097 * math.cos(ang)
            bz = lower_z + 0.097 * math.sin(ang)
            _add_cylinder_bm(
                bm,
                center=(fx, by, bz),
                axis="X",
                radius=0.009,
                depth=0.044,
                segments=6,
                mat_idx=1,
                smooth_sides=False,
            )

        # Upper secondary pipe flange + 4 hex bolts
        _add_cylinder_bm(
            bm,
            center=(fx, 0.0, upper_z),
            axis="X",
            radius=0.072,
            depth=0.024,
            segments=12,
            mat_idx=1,
            smooth_sides=True,
        )
        for k in range(4):
            ang = math.radians(k * 90.0 + 45.0)
            by = 0.058 * math.cos(ang)
            bz = upper_z + 0.058 * math.sin(ang)
            _add_cylinder_bm(
                bm,
                center=(fx, by, bz),
                axis="X",
                radius=0.007,
                depth=0.038,
                segments=6,
                mat_idx=1,
                smooth_sides=False,
            )

    # Center coupling collars at X = 0 (sleek central waist at X in [-0.04, 0.04] + twin bolted flange rings)
    _add_cylinder_bm(
        bm, center=(0.0, 0.0, lower_z), axis="X", radius=0.092, depth=0.140, segments=12, mat_idx=1, smooth_sides=True
    )
    _add_cylinder_bm(
        bm, center=(0.0, 0.0, upper_z), axis="X", radius=0.054, depth=0.120, segments=12, mat_idx=1, smooth_sides=True
    )
    for ring_sign in (-1.0, 1.0):
        rx_low = ring_sign * 0.056
        _add_cylinder_bm(
            bm,
            center=(rx_low, 0.0, lower_z),
            axis="X",
            radius=0.114,
            depth=0.022,
            segments=12,
            mat_idx=1,
            smooth_sides=True,
        )
        for k in range(4):
            ang = math.radians(k * 90.0 + 45.0)
            by = 0.098 * math.cos(ang)
            bz = lower_z + 0.098 * math.sin(ang)
            _add_cylinder_bm(
                bm,
                center=(rx_low + ring_sign * 0.005, by, bz),
                axis="X",
                radius=0.009,
                depth=0.028,
                segments=6,
                mat_idx=1,
                smooth_sides=False,
            )

        rx_up = ring_sign * 0.048
        _add_cylinder_bm(
            bm,
            center=(rx_up, 0.0, upper_z),
            axis="X",
            radius=0.071,
            depth=0.018,
            segments=12,
            mat_idx=1,
            smooth_sides=True,
        )
        for k in range(4):
            ang = math.radians(k * 90.0 + 45.0)
            by = 0.058 * math.cos(ang)
            bz = upper_z + 0.058 * math.sin(ang)
            _add_cylinder_bm(
                bm,
                center=(rx_up + ring_sign * 0.004, by, bz),
                axis="X",
                radius=0.007,
                depth=0.024,
                segments=6,
                mat_idx=1,
                smooth_sides=False,
            )

    # 3 Heavy Welded Steel Wall-Standoff U-Clamp Support Brackets (X = -1.35, 0.0, +1.35)
    for bx in (-1.35, 0.0, 1.35):
        is_center = abs(bx) < 0.01
        r_low_clamp = 0.092 if is_center else lower_r
        r_up_clamp = 0.054 if is_center else upper_r

        # Base foot plate (min_z = 0.0, Y in [-0.12, 0.12])
        _add_box_bm(bm, (bx - 0.052, -0.12, 0.0), (bx + 0.052, 0.12, 0.022), mat_idx=1, chamfer=0.0)

        # Vertical rear wall-standoff spine channel (Y in [0.090, 0.120], Z in [0.0, 0.500])
        _add_box_bm(bm, (bx - 0.038, 0.090, 0.0), (bx + 0.038, 0.120, 0.500), mat_idx=1, chamfer=0.0)
        for side in (-1.0, 1.0):
            rx0, rx1 = (bx + 0.024, bx + 0.038) if side > 0 else (bx - 0.038, bx - 0.024)
            _add_box_bm(bm, (rx0, 0.068, 0.022), (rx1, 0.096, 0.478), mat_idx=1, chamfer=0.0)

        # Top cap / wall mounting bracket flange flush at Z = 0.500
        _add_box_bm(bm, (bx - 0.052, 0.018, 0.478), (bx + 0.052, 0.120, 0.500), mat_idx=1, chamfer=0.0)

        # Lower cantilever shelf arm + diagonal welded knee gusset
        low_seat_z = lower_z - r_low_clamp
        _add_box_bm(
            bm,
            (bx - 0.042, -0.105, low_seat_z - 0.022),
            (bx + 0.042, 0.096, low_seat_z + 0.002),
            mat_idx=1,
            chamfer=0.0,
        )
        _add_strut_bm(
            bm,
            (bx, 0.088, 0.018),
            (bx, -0.025, low_seat_z - 0.014),
            width_x=0.024,
            thickness=0.022,
            mat_idx=1,
        )

        # Upper cantilever shelf arm + diagonal welded knee gusset
        up_seat_z = upper_z - r_up_clamp
        _add_box_bm(
            bm,
            (bx - 0.036, -0.068, up_seat_z - 0.020),
            (bx + 0.036, 0.096, up_seat_z + 0.002),
            mat_idx=1,
            chamfer=0.0,
        )
        _add_strut_bm(
            bm,
            (bx, 0.088, up_seat_z - 0.072),
            (bx, -0.010, up_seat_z - 0.014),
            width_x=0.020,
            thickness=0.020,
            mat_idx=1,
        )

        # Lower & upper U-clamp semicircular straps wrapping front (-Y) side of pipes
        _add_u_clamp_strap_bm(
            bm,
            x_center=bx,
            width_x=0.034,
            pipe_z=lower_z,
            r_inner=r_low_clamp,
            thickness=0.012,
            segments=6,
            mat_idx=1,
        )
        _add_u_clamp_strap_bm(
            bm,
            x_center=bx,
            width_x=0.028,
            pipe_z=upper_z,
            r_inner=r_up_clamp,
            thickness=0.010,
            segments=5,
            mat_idx=1,
        )

    return _finalize_and_export(
        "steel_pipe_straight_4m",
        bm,
        [painted_mat, steel_mat],
        output_dir,
    )


def main() -> None:
    """Generate all 3 factory workshop MEP duct & pipe run GLB assets."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "props" / "factory_workshop"
        generate_ac_duct_straight_4m(output_dir)
        generate_ac_duct_elbow_90(output_dir)
        generate_steel_pipe_straight_4m(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
