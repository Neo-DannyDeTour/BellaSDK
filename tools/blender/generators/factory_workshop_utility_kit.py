"""Procedural Blender generator for factory workshop utility prop GLBs.

Generates 3 workshop utility prop assets in assets/models/props/factory_workshop/:
1. electric_wires_4m.glb - 4.00m L x 0.38m H x 0.22m D steel ladder cable tray with
                           top ribbed conduit, 3 catenary-sagging rubber power cables,
                           saddle clamps, and 1 severed dangling cable loop near X = +0.6.
2. coiled_hose.glb       - 0.78m x 0.26m x 0.78m stacked 3.5-coil rubber hose with
                           riveted steel retaining strap clamp and tarnished_brass spray nozzle.
3. trolley_cart.glb      - 1.10m L x 0.90m H x 0.60m W 2-tier workshop steel push-cart with
                           4 swivel casters touching min_y = 0.0, angle-iron uprights,
                           corner gussets, lipped trays, and +X bent tubular push handle.

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Blender Y / Godot Z).
- Clean world-metric 1.0m cubic box UVs.
- Explicit deterministic material slots for Godot ORM reassignment (with embedded glTF rubber_dark).
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
from common.materials import assign_material, create_pbr_material
from mathutils import Matrix, Vector

_REPO_ROOT = _TOOL_DIR.parent.parent
_OUTPUT_DIR = _REPO_ROOT / "assets" / "models" / "props" / "factory_workshop"


# ==============================================================================
# SHARED BMESH, SMOOTHING, UV & EXPORT HELPERS
# ==============================================================================
def _get_smooth_layer(bm: bmesh.types.BMesh) -> bmesh.types.BMLayerItem:
    """Return or create an integer edge layer tagging curved barrel edges as smooth."""
    layer = bm.edges.layers.int.get("force_smooth")
    if layer is None:
        layer = bm.edges.layers.int.new("force_smooth")
    return layer


def _merge_temp_bmesh(
    tmp: bmesh.types.BMesh,
    dst: bmesh.types.BMesh,
    mat_idx: int,
    smooth_barrel_edges: bool = False,
) -> list[bmesh.types.BMFace]:
    """Copy geometry from tmp BMesh into dst BMesh with mat_idx and optional edge smooth tagging."""
    tmp.verts.ensure_lookup_table()
    tmp.edges.ensure_lookup_table()
    vert_map: dict[int, bmesh.types.BMVert] = {
        idx: dst.verts.new(v.co) for idx, v in enumerate(tmp.verts)
    }

    created_faces: list[bmesh.types.BMFace] = []
    for f in tmp.faces:
        new_f = dst.faces.new([vert_map[v.index] for v in f.verts])
        new_f.material_index = mat_idx
        created_faces.append(new_f)

    if smooth_barrel_edges:
        smooth_layer = _get_smooth_layer(dst)
        for e in tmp.edges:
            if len(e.link_faces) == 2:
                # Keep cap rims sharp (90 deg), force smooth along curved lateral edges
                angle = e.calc_face_angle(0.0)
                if angle < math.radians(65.0):
                    dst_edge = dst.edges.get(
                        (vert_map[e.verts[0].index], vert_map[e.verts[1].index])
                    )
                    if dst_edge is not None:
                        dst_edge[smooth_layer] = 1

    tmp.free()
    return created_faces


def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append an axis-aligned box with optional chamfer to a BMesh."""
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        return []

    if chamfer <= 0.0:
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
        quads = [
            (0, 3, 2, 1),
            (4, 5, 6, 7),
            (0, 1, 5, 4),
            (1, 2, 6, 5),
            (2, 3, 7, 6),
            (3, 0, 4, 7),
        ]
        faces: list[bmesh.types.BMFace] = []
        for q in quads:
            f = bm.faces.new([verts[i] for i in q])
            f.material_index = mat_idx
            faces.append(f)
        return faces

    tmp = bmesh.new()
    cx = 0.5 * (x0 + x1)
    cy = 0.5 * (y0 + y1)
    cz = 0.5 * (z0 + z1)
    sx = x1 - x0
    sy = y1 - y0
    sz = z1 - z0
    xf = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    bmesh.ops.create_cube(tmp, size=1.0, matrix=xf)
    c_limit = min(chamfer, min(sx, sy, sz) * 0.25)
    if c_limit > 1e-5:
        bmesh.ops.bevel(
            tmp,
            geom=list(tmp.edges),
            offset=c_limit,
            segments=1,
            affect="EDGES",
        )
    return _merge_temp_bmesh(tmp, bm, mat_idx, smooth_barrel_edges=False)


def _add_prism_x_bm(
    bm: bmesh.types.BMesh,
    y0: float,
    y1: float,
    profile_xz: list[tuple[float, float]],
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    """Extrude a 2D (x, z) convex/simple polygon along Y from y0 to y1."""
    if y1 <= y0 or len(profile_xz) < 3:
        return []
    n = len(profile_xz)
    v_front = [bm.verts.new((px, y0, pz)) for (px, pz) in profile_xz]
    v_back = [bm.verts.new((px, y1, pz)) for (px, pz) in profile_xz]

    faces: list[bmesh.types.BMFace] = []
    f0 = bm.faces.new(list(reversed(v_front)))
    f0.material_index = mat_idx
    faces.append(f0)

    f1 = bm.faces.new(v_back)
    f1.material_index = mat_idx
    faces.append(f1)

    for i in range(n):
        j = (i + 1) % n
        fs = bm.faces.new((v_front[i], v_back[i], v_back[j], v_front[j]))
        fs.material_index = mat_idx
        faces.append(fs)
    return faces


def _add_cylinder_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    r0: float,
    r1: float | None = None,
    segments: int = 12,
    cap_ends: bool = True,
    mat_idx: int = 0,
    smooth: bool = True,
) -> list[bmesh.types.BMFace]:
    """Append a cylinder or frustum between p0 and p1."""
    if r1 is None:
        r1 = r0
    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return []
    mid = (p0 + p1) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    xf = Matrix.Translation(mid) @ rot

    tmp = bmesh.new()
    bmesh.ops.create_cone(
        tmp,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=r0,
        radius2=r1,
        depth=length,
        matrix=xf,
    )
    return _merge_temp_bmesh(tmp, bm, mat_idx, smooth_barrel_edges=smooth)


def _add_swept_tube_bm(
    bm: bmesh.types.BMesh,
    points: list[Vector],
    radius: float,
    radial_segments: int = 8,
    cap_ends: bool = True,
    mat_idx: int = 0,
    closed: bool = False,
) -> list[bmesh.types.BMFace]:
    """Sweep a circular tube along a 3D polyline using a twist-free parallel transport frame."""
    if len(points) < 2:
        return []

    n_pts = len(points)
    tangents: list[Vector] = []
    for i in range(n_pts):
        if closed:
            p_prev = points[(i - 1) % n_pts]
            p_next = points[(i + 1) % n_pts]
            t = p_next - p_prev
        elif i == 0:
            t = points[1] - points[0]
        elif i == n_pts - 1:
            t = points[-1] - points[-2]
        else:
            t = points[i + 1] - points[i - 1]
        if t.length < 1e-7:
            t = tangents[-1] if tangents else Vector((1.0, 0.0, 0.0))
        else:
            t = t.normalized()
        tangents.append(t)

    ref = Vector((0.0, 0.0, 1.0)) if abs(tangents[0].z) < 0.9 else Vector((0.0, 1.0, 0.0))
    b_vec = tangents[0].cross(ref).normalized()
    n_vec = b_vec.cross(tangents[0]).normalized()

    tmp = bmesh.new()
    rings: list[list[bmesh.types.BMVert]] = []
    for i in range(n_pts):
        if i > 0:
            rot = tangents[i - 1].rotation_difference(tangents[i])
            n_vec = (rot @ n_vec).normalized()
            b_vec = tangents[i].cross(n_vec).normalized()
        ring: list[bmesh.types.BMVert] = []
        for s in range(radial_segments):
            ang = (2.0 * math.pi * s) / radial_segments
            offset = (n_vec * math.cos(ang) + b_vec * math.sin(ang)) * radius
            ring.append(tmp.verts.new(points[i] + offset))
        rings.append(ring)

    seg_count = n_pts if closed else (n_pts - 1)
    for i in range(seg_count):
        r0 = rings[i]
        r1 = rings[(i + 1) % n_pts]
        for s in range(radial_segments):
            sn = (s + 1) % radial_segments
            tmp.faces.new((r0[s], r0[sn], r1[sn], r1[s]))

    if cap_ends and not closed:
        tmp.faces.new(list(reversed(rings[0])))
        tmp.faces.new(rings[-1])

    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    return _merge_temp_bmesh(tmp, bm, mat_idx, smooth_barrel_edges=True)


def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 1.0) -> None:
    """Assign world-metric cubic box UVs across all polygon loops."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data
    inv_tile = 1.0 / tile_meters

    for poly in mesh.polygons:
        nx = abs(poly.normal.x)
        ny = abs(poly.normal.y)
        nz = abs(poly.normal.z)
        for loop_idx in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            if nx >= ny and nx >= nz:
                u, v = co.y * inv_tile, co.z * inv_tile
            elif ny >= nx and ny >= nz:
                u, v = co.x * inv_tile, co.z * inv_tile
            else:
                u, v = co.x * inv_tile, co.y * inv_tile
            uv_layer[loop_idx].uv = (u, v)


def _finalize_and_export(
    slug: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    out_path: Path,
    auto_smooth_deg: float = 35.0,
) -> Path:
    """Finalize normals/smoothing, apply transforms, assign material slots, print stats, export GLB."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    smooth_layer = bm.edges.layers.int.get("force_smooth")
    thresh_rad = math.radians(auto_smooth_deg)

    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if smooth_layer is not None and edge[smooth_layer] == 1:
            edge.smooth = True
        elif len(edge.link_faces) == 2:
            edge.smooth = edge.calc_face_angle(0.0) <= thresh_rad
        else:
            edge.smooth = False

    if smooth_layer is not None:
        bm.edges.layers.int.remove(smooth_layer)

    mesh = bpy.data.meshes.new(slug)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(slug, mesh)
    bpy.context.collection.objects.link(obj)

    if materials:
        assign_material(obj, materials[0])
        for mat in materials[1:]:
            obj.data.materials.append(mat)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    _apply_box_uvs(obj, tile_meters=1.0)

    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    world_verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    min_x = min(v.x for v in world_verts)
    max_x = max(v.x for v in world_verts)
    min_y = min(v.y for v in world_verts)
    max_y = max(v.y for v in world_verts)
    min_z = min(v.z for v in world_verts)
    max_z = max(v.z for v in world_verts)

    blender_bbox = (min_x, max_x, min_y, max_y, min_z, max_z)
    godot_bbox = (min_x, max_x, min_z, max_z, -max_y, -min_y)
    godot_size = (
        godot_bbox[1] - godot_bbox[0],
        godot_bbox[3] - godot_bbox[2],
        godot_bbox[5] - godot_bbox[4],
    )
    slots = [(i, m.name) for i, m in enumerate(obj.data.materials)]

    print(
        f"[{slug}] tris={tri_count} | "
        f"blender_bbox=({blender_bbox[0]:.3f}, {blender_bbox[1]:.3f}, "
        f"{blender_bbox[2]:.3f}, {blender_bbox[3]:.3f}, "
        f"{blender_bbox[4]:.3f}, {blender_bbox[5]:.3f}) | "
        f"godot_bbox=({godot_bbox[0]:.3f}, {godot_bbox[1]:.3f}, "
        f"{godot_bbox[2]:.3f}, {godot_bbox[3]:.3f}, "
        f"{godot_bbox[4]:.3f}, {godot_bbox[5]:.3f}) | "
        f"godot_size=({godot_size[0]:.3f}, {godot_size[1]:.3f}, {godot_size[2]:.3f}) | "
        f"slots={slots}"
    )

    return export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )


def _create_shared_materials() -> dict[str, bpy.types.Material]:
    """Create standard PBR placeholders matching existing Godot .tres and glTF rubber_dark."""
    return {
        "steel": create_pbr_material(
            name="steel",
            base_color=(0.28, 0.26, 0.24, 1.0),
            metallic=0.85,
            roughness=0.55,
        ),
        "conduit": create_pbr_material(
            name="conduit",
            base_color=(0.46, 0.48, 0.50, 1.0),
            metallic=0.88,
            roughness=0.45,
        ),
        "painted_metal": create_pbr_material(
            name="painted_metal",
            base_color=(0.20, 0.34, 0.38, 1.0),
            metallic=0.45,
            roughness=0.62,
        ),
        "brass": create_pbr_material(
            name="brass",
            base_color=(0.68, 0.55, 0.32, 1.0),
            metallic=0.88,
            roughness=0.42,
        ),
        "rubber_dark": create_pbr_material(
            name="rubber_dark",
            base_color=(0.07, 0.075, 0.08, 1.0),
            metallic=0.0,
            roughness=0.82,
        ),
    }


# ==============================================================================
# 7. ELECTRIC WIRES 4M (4.0m L x 0.38m H x 0.22m D, <= 2,800 tris)
# ==============================================================================
def build_electric_wires_4m(out_path: Path) -> Path:
    """Build 4.0m steel ladder cable tray with ribbed conduit, 3 sagging cables & severed loop."""
    clean_scene()
    mats = _create_shared_materials()
    mat_steel = 0
    mat_conduit = 1
    mat_rubber = 2

    bm = bmesh.new()

    # 1. Steel ladder cable tray: X[-2.00, +2.00], Z[0.21, 0.33], Y[-0.094, +0.094]
    # C-channel side rails (front -Y and back +Y)
    for side in (-1.0, 1.0):
        if side < 0.0:
            y_outer, y_inner = -0.094, -0.080
            y_lip_in = -0.060
        else:
            y_inner, y_outer = 0.080, 0.094
            y_lip_in = 0.060

        # Vertical web
        _add_box_bm(
            bm,
            (-2.000, y_outer if side < 0.0 else y_inner, 0.210),
            (2.000, y_inner if side < 0.0 else y_outer, 0.330),
            mat_idx=mat_steel,
        )
        # Top and bottom inward return flanges
        for z0, z1 in ((0.210, 0.222), (0.318, 0.330)):
            fy0 = y_outer if side < 0.0 else y_lip_in
            fy1 = y_lip_in if side < 0.0 else y_outer
            _add_box_bm(bm, (-2.000, fy0, z0), (2.000, fy1, z1), mat_idx=mat_steel)

    # 11 cross rungs spanning between rails (Z in [0.212, 0.226])
    for i in range(11):
        rx = -1.94 + i * 0.388
        _add_box_bm(bm, (rx - 0.014, -0.080, 0.212), (rx + 0.014, 0.080, 0.226), mat_idx=mat_steel)

    # 4 wall-mounting tabs along +Y back face (Godot -Z wall flush at Y = +0.110, Z in [0.16, 0.38])
    tab_xs = (-1.65, -0.55, 0.55, 1.65)
    for tx in tab_xs:
        # Vertical wall mounting plate
        _add_box_bm(bm, (tx - 0.038, 0.094, 0.160), (tx + 0.038, 0.110, 0.380), mat_idx=mat_steel)
        # Underside support bracket gusset tying tab to tray base
        _add_box_bm(bm, (tx - 0.014, 0.025, 0.160), (tx + 0.014, 0.094, 0.210), mat_idx=mat_steel)
        # Hex mounting bolts on top & bottom tab ears (facing -Y so back stays flush at +0.110)
        for bz in (0.180, 0.360):
            _add_cylinder_bm(
                bm,
                Vector((tx, 0.082, bz)),
                Vector((tx, 0.094, bz)),
                r0=0.011,
                segments=6,
                mat_idx=mat_steel,
                smooth=False,
            )

    # 2. Rigid ribbed conduit pipe along top front rail (X[-2.00, +2.00], Y=-0.080, Z=0.354)
    conduit_y = -0.080
    conduit_z = 0.354
    _add_cylinder_bm(
        bm,
        Vector((-2.000, conduit_y, conduit_z)),
        Vector((2.000, conduit_y, conduit_z)),
        r0=0.022,
        segments=10,
        mat_idx=mat_conduit,
        smooth=True,
    )
    # Ribbed coupling rings & union collars along conduit (top reaches Z = 0.380)
    collar_xs = [-1.980, -1.420, -0.820, 0.000, 0.820, 1.420, 1.980]
    for cx in collar_xs:
        hw = 0.020 if abs(cx) > 1.9 else 0.014
        _add_cylinder_bm(
            bm,
            Vector((cx - hw, conduit_y, conduit_z)),
            Vector((cx + hw, conduit_y, conduit_z)),
            r0=0.026,
            segments=10,
            mat_idx=mat_conduit,
            smooth=True,
        )

    # 3. Steel saddle clamps at 4 stations (top conduit strap + lower cable-bundle cradle)
    clamp_xs = (-1.85, -0.60, 0.60, 1.85)
    for cx in clamp_xs:
        # Upper conduit saddle strap clamping conduit onto front top rail (front reaches Y = -0.110)
        _add_box_bm(bm, (cx - 0.020, -0.110, 0.328), (cx + 0.020, -0.094, 0.380), mat_idx=mat_steel)
        _add_box_bm(bm, (cx - 0.020, -0.110, 0.372), (cx + 0.020, -0.052, 0.380), mat_idx=mat_steel)
        _add_box_bm(bm, (cx - 0.020, -0.060, 0.330), (cx + 0.020, -0.050, 0.372), mat_idx=mat_steel)

        # Lower cable bundle U-saddle clamp under tray (holds 3 cables at Z = 0.14..0.21)
        _add_box_bm(bm, (cx - 0.018, -0.068, 0.146), (cx + 0.018, -0.056, 0.212), mat_idx=mat_steel)
        _add_box_bm(bm, (cx - 0.018, 0.028, 0.146), (cx + 0.018, 0.040, 0.212), mat_idx=mat_steel)
        _add_box_bm(bm, (cx - 0.018, -0.068, 0.134), (cx + 0.018, 0.040, 0.146), mat_idx=mat_steel)

    # 4. Three bundled matte-black rubber power cables with smooth catenary sag to Z = 0.0
    def catenary_weight(u: float, alpha: float = 1.85) -> float:
        denom = math.cosh(alpha) - 1.0
        return (math.cosh(alpha) - math.cosh(alpha * (2.0 * u - 1.0))) / denom

    def build_cable_path(
        y_clamp: float,
        z_clamp: float,
        sags: tuple[float, float, float],
        y_weaves: tuple[float, float, float],
    ) -> list[Vector]:
        pts: list[Vector] = [Vector((-2.000, y_clamp, z_clamp))]
        spans = [
            (-1.85, -0.60, sags[0], y_weaves[0], 8),
            (-0.60, 0.60, sags[1], y_weaves[1], 8),
            (0.60, 1.85, sags[2], y_weaves[2], 8),
        ]
        for x0, x1, sag, yw, steps in spans:
            for k in range(steps):
                u = k / float(steps)
                w = catenary_weight(u)
                px = x0 + (x1 - x0) * u
                py = y_clamp + yw * math.sin(math.pi * u)
                pz = z_clamp - sag * w
                pts.append(Vector((px, py, pz)))
        pts.append(Vector((1.85, y_clamp, z_clamp)))
        pts.append(Vector((2.000, y_clamp, z_clamp)))
        return pts

    # Lowest cable (r=0.018m) clamped at Z=0.164 -> sag 0.146m hits z_center=0.018 => min_z=0.000!
    cables_spec = [
        # (radius, y_clamp, z_clamp, (sag_left, sag_mid, sag_right), (yw_left, yw_mid, yw_right))
        (0.023, -0.034, 0.192, (0.150, 0.144, 0.128), (-0.014, -0.018, -0.010)),
        (0.020, 0.008, 0.194, (0.146, 0.156, 0.134), (0.012, 0.015, 0.010)),
        (0.018, -0.014, 0.164, (0.146, 0.146, 0.126), (-0.004, 0.005, -0.005)),
    ]
    for rad, yc, zc, sags, yws in cables_spec:
        path = build_cable_path(yc, zc, sags, yws)
        _add_swept_tube_bm(bm, path, radius=rad, radial_segments=8, cap_ends=True, mat_idx=mat_rubber)

    # 5. Severed dangling cable loop near X = +0.60
    loop_pts = [
        Vector((0.48, -0.055, 0.228)),
        Vector((0.52, -0.072, 0.175)),
        Vector((0.55, -0.084, 0.100)),
        Vector((0.58, -0.088, 0.045)),
        Vector((0.62, -0.088, 0.028)),
        Vector((0.66, -0.082, 0.045)),
        Vector((0.70, -0.074, 0.086)),
        Vector((0.72, -0.070, 0.128)),
    ]
    _add_swept_tube_bm(
        bm, loop_pts, radius=0.019, radial_segments=8, cap_ends=True, mat_idx=mat_rubber
    )
    # Stripped metal wire core tip at severed cable end
    tip_dir = (loop_pts[-1] - loop_pts[-2]).normalized()
    _add_cylinder_bm(
        bm,
        loop_pts[-1],
        loop_pts[-1] + tip_dir * 0.018,
        r0=0.010,
        segments=8,
        mat_idx=mat_steel,
        smooth=True,
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    return _finalize_and_export(
        slug="electric_wires_4m",
        bm=bm,
        materials=[mats["steel"], mats["conduit"], mats["rubber_dark"]],
        out_path=out_path,
    )


# ==============================================================================
# 8. COILED HOSE (0.78m x 0.26m x 0.78m, <= 2,800 tris)
# ==============================================================================
def build_coiled_hose(out_path: Path) -> Path:
    """Build 0.78m x 0.26m x 0.78m organic 3.5-coil rubber hose with steel strap & brass nozzle."""
    clean_scene()
    mats = _create_shared_materials()
    mat_rubber = 0
    mat_brass = 1
    mat_steel = 2

    bm = bmesh.new()
    hose_r = 0.024  # 0.048m tube diameter

    # Build 3.65 tightly stacked organic turns resting flat on Z=0.0, zero floating gaps.
    # At -X (theta = pi mod 2pi), turns 0.5, 1.5, 2.5, 3.5 stack cleanly for the retaining strap.
    coil_pts: list[Vector] = []
    n_coil_steps = 88
    theta_end = 3.72 * 2.0 * math.pi

    for i in range(n_coil_steps + 1):
        u = i / float(n_coil_steps)
        theta = u * theta_end
        turns = theta / (2.0 * math.pi)

        # Organic hand-coiled radial undulation balanced across X and Y (~0.36m outer centerline)
        # Inner start tucks smoothly inside coil core over the first 0.25 turn
        lobe = 0.009 * math.sin(2.0 * theta + 0.3) + 0.005 * math.cos(3.0 * theta - 0.5)
        tuck = 0.042 * max(0.0, 1.0 - turns / 0.25)
        base_r = 0.358 - 0.004 * turns - tuck
        rad = base_r + lobe

        # Flat base for first 0.75 turn, then continuous 0.047m vertical pitch so every upper loop
        # rests directly on the coil underneath it without air gaps.
        if turns <= 0.75:
            z_center = hose_r
        else:
            z_center = hose_r + (turns - 0.75) * 0.047

        coil_pts.append(Vector((rad * math.cos(theta), rad * math.sin(theta), z_center)))

    # Leading outer tail continues from 3.72 turns smoothly across the top coil ridge
    # resting directly on the coil beneath it, terminating at front-right (+X, -Y)
    last_p = coil_pts[-1]
    tail_pts = [
        Vector((last_p.x + 0.06, last_p.y - 0.02, last_p.z + 0.010)),
        Vector((0.02, -0.340, 0.180)),
        Vector((0.15, -0.312, 0.202)),
        Vector((0.24, -0.258, 0.214)),
    ]

    full_pts = coil_pts + tail_pts
    _add_swept_tube_bm(
        bm, full_pts, radius=hose_r, radial_segments=9, cap_ends=True, mat_idx=mat_rubber
    )

    # Inner starting tail brass coupling cap tucked neatly inside bottom ring
    start_dir = (coil_pts[0] - coil_pts[1]).normalized()
    _add_cylinder_bm(
        bm,
        coil_pts[0],
        coil_pts[0] + start_dir * 0.024,
        r0=0.022,
        segments=10,
        mat_idx=mat_brass,
        smooth=True,
    )

    # Leading outer tail tarnished_brass industrial spray nozzle coupling resting across top coil
    n_base = tail_pts[-1]
    n_dir = (tail_pts[-1] - tail_pts[-2]).normalized()
    n_dir = Vector((n_dir.x, n_dir.y, 0.04)).normalized()

    p_ferrule0 = n_base - n_dir * 0.006
    p_ferrule1 = n_base + n_dir * 0.030
    p_hex0 = p_ferrule1
    p_hex1 = p_hex0 + n_dir * 0.024
    p_collar0 = p_hex1
    p_collar1 = p_collar0 + n_dir * 0.020
    p_barrel0 = p_collar1
    p_barrel1 = p_barrel0 + n_dir * 0.042
    p_tip0 = p_barrel1
    p_tip1 = p_tip0 + n_dir * 0.016

    _add_cylinder_bm(bm, p_ferrule0, p_ferrule1, r0=0.027, segments=12, mat_idx=mat_brass)
    _add_cylinder_bm(
        bm, p_hex0, p_hex1, r0=0.033, segments=6, mat_idx=mat_brass, smooth=False
    )
    _add_cylinder_bm(bm, p_collar0, p_collar1, r0=0.029, segments=12, mat_idx=mat_brass)
    _add_cylinder_bm(bm, p_barrel0, p_barrel1, r0=0.024, r1=0.015, segments=12, mat_idx=mat_brass)
    _add_cylinder_bm(bm, p_tip0, p_tip1, r0=0.017, r1=0.013, segments=12, mat_idx=mat_brass)

    # Riveted steel retaining strap clamp binding the -X side of the coil tightly (hug exact stack)
    neg_x_pts = [p for p in coil_pts if p.x < -0.20 and abs(p.y) < 0.035]
    sx_outer = min(p.x for p in neg_x_pts) - hose_r - 0.001
    sx_inner = max(p.x for p in neg_x_pts) + hose_r + 0.001
    sz_bot = max(0.002, min(p.z for p in neg_x_pts) - hose_r - 0.001)
    sz_top = max(p.z for p in neg_x_pts) + hose_r + 0.001

    strap_y0, strap_y1 = -0.026, 0.026
    strap_t = 0.010
    # Snug outer, inner, top, bottom strap plates
    _add_box_bm(bm, (sx_outer - strap_t, strap_y0, sz_bot), (sx_outer, strap_y1, sz_top + strap_t), mat_steel)
    _add_box_bm(bm, (sx_inner, strap_y0, sz_bot), (sx_inner + strap_t, strap_y1, sz_top + strap_t), mat_steel)
    _add_box_bm(bm, (sx_outer, strap_y0, sz_top), (sx_inner, strap_y1, sz_top + strap_t), mat_steel)
    _add_box_bm(bm, (sx_outer, strap_y0, sz_bot), (sx_inner, strap_y1, sz_bot + strap_t), mat_steel)

    # Clamping tension lug & bolt across top of strap
    sx_mid = 0.5 * (sx_outer + sx_inner)
    _add_box_bm(
        bm,
        (sx_mid - 0.018, strap_y0, sz_top + strap_t),
        (sx_mid + 0.018, strap_y1, sz_top + strap_t + 0.022),
        mat_steel,
    )
    _add_cylinder_bm(
        bm,
        Vector((sx_mid, strap_y0 - 0.008, sz_top + strap_t + 0.011)),
        Vector((sx_mid, strap_y1 + 0.008, sz_top + strap_t + 0.011)),
        r0=0.007,
        segments=6,
        mat_idx=mat_steel,
        smooth=False,
    )
    # 4 dome steel rivets on outer strap leg
    for ry in (-0.014, 0.014):
        for rz in (sz_bot + 0.040, sz_top - 0.040):
            _add_cylinder_bm(
                bm,
                Vector((sx_outer - strap_t - 0.005, ry, rz)),
                Vector((sx_outer - strap_t + 0.001, ry, rz)),
                r0=0.006,
                segments=8,
                mat_idx=mat_steel,
            )

    # Center XY precisely and scale uniformly into 0.78m x 0.26m x 0.78m with min_z = 0.000
    bm.verts.ensure_lookup_table()
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    cx = 0.5 * (min(xs) + max(xs))
    cy = 0.5 * (min(ys) + max(ys))
    z_min = min(zs)
    sx = max(xs) - min(xs)
    sy = max(ys) - min(ys)
    sz = max(zs) - z_min
    scale_x = 0.78 / sx
    scale_y = 0.78 / sy
    scale_z = 0.26 / sz

    for v in bm.verts:
        v.co.x = (v.co.x - cx) * scale_x
        v.co.y = (v.co.y - cy) * scale_y
        v.co.z = (v.co.z - z_min) * scale_z

    out_path.parent.mkdir(parents=True, exist_ok=True)
    return _finalize_and_export(
        slug="coiled_hose",
        bm=bm,
        materials=[mats["rubber_dark"], mats["brass"], mats["steel"]],
        out_path=out_path,
    )


# ==============================================================================
# 9. TROLLEY CART (1.10m L x 0.90m H x 0.60m W, <= 2,200 tris)
# ==============================================================================
def _add_swivel_caster(
    bm: bmesh.types.BMesh,
    kingpin_xy: tuple[float, float],
    yaw_deg: float,
    mat_steel: int,
    mat_rubber: int,
) -> None:
    """Append a swivel steel caster fork + rubber wheel touching Z = 0.000."""
    kx, ky = kingpin_xy
    wheel_r = 0.055
    wheel_w = 0.036
    trail = 0.026

    # Top mounting plate (Z: 0.168 .. 0.180) + swivel bearing collar (Z: 0.146 .. 0.168)
    _add_box_bm(bm, (kx - 0.042, ky - 0.042, 0.168), (kx + 0.042, ky + 0.042, 0.180), mat_steel)
    _add_cylinder_bm(
        bm,
        Vector((kx, ky, 0.146)),
        Vector((kx, ky, 0.168)),
        r0=0.028,
        segments=12,
        mat_idx=mat_steel,
    )

    # Swivel fork + wheel transformed by yaw around kingpin Z axis
    tmp = bmesh.new()
    # Fork crown bridge (Z: 0.130 .. 0.146)
    _add_box_bm(tmp, (-trail - 0.022, -0.028, 0.130), (0.024, 0.028, 0.146), mat_steel)
    # Left & right fork legs angled from crown down to wheel axle (Z: 0.055)
    for side in (-1.0, 1.0):
        fy = side * 0.025
        _add_box_bm(
            tmp,
            (-trail - 0.015, fy - 0.004, 0.042),
            (-trail + 0.015, fy + 0.004, 0.136),
            mat_steel,
        )
    # Steel axle pin & hub
    _add_cylinder_bm(
        tmp,
        Vector((-trail, -0.032, wheel_r)),
        Vector((-trail, 0.032, wheel_r)),
        r0=0.008,
        segments=8,
        mat_idx=mat_steel,
    )
    _add_cylinder_bm(
        tmp,
        Vector((-trail, -wheel_w * 0.5 - 0.003, wheel_r)),
        Vector((-trail, wheel_w * 0.5 + 0.003, wheel_r)),
        r0=0.023,
        segments=10,
        mat_idx=mat_steel,
    )
    # Rubber wheel tire touching Z = 0.000
    _add_cylinder_bm(
        tmp,
        Vector((-trail, -wheel_w * 0.5, wheel_r)),
        Vector((-trail, wheel_w * 0.5, wheel_r)),
        r0=wheel_r,
        segments=16,
        mat_idx=mat_rubber,
    )

    rot_xf = Matrix.Translation((kx, ky, 0.0)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
    bmesh.ops.transform(tmp, matrix=rot_xf, verts=tmp.verts)

    # Merge tmp while preserving each face's own material index and smooth tags
    tmp.verts.ensure_lookup_table()
    tmp.edges.ensure_lookup_table()
    smooth_layer_tmp = tmp.edges.layers.int.get("force_smooth")
    smooth_layer_dst = _get_smooth_layer(bm)
    vert_map = {idx: bm.verts.new(v.co) for idx, v in enumerate(tmp.verts)}
    for f in tmp.faces:
        nf = bm.faces.new([vert_map[v.index] for v in f.verts])
        nf.material_index = f.material_index
    if smooth_layer_tmp is not None:
        for e in tmp.edges:
            if e[smooth_layer_tmp] == 1:
                de = bm.edges.get((vert_map[e.verts[0].index], vert_map[e.verts[1].index]))
                if de is not None:
                    de[smooth_layer_dst] = 1
    tmp.free()


def _add_lipped_tray(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    z_bot: float,
    z_top: float,
    wall_t: float,
    floor_t: float,
    mat_idx: int,
) -> None:
    """Append a lipped sheet-steel workshop tray pan with upturned perimeter walls."""
    z_floor_top = z_bot + floor_t
    # Pan floor
    _add_box_bm(bm, (x0, y0, z_bot), (x1, y1, z_floor_top), mat_idx=mat_idx)
    # 4 perimeter lip walls
    _add_box_bm(bm, (x0, y0, z_floor_top), (x1, y0 + wall_t, z_top), mat_idx=mat_idx)
    _add_box_bm(bm, (x0, y1 - wall_t, z_floor_top), (x1, y1, z_top), mat_idx=mat_idx)
    _add_box_bm(bm, (x0, y0 + wall_t, z_floor_top), (x0 + wall_t, y1 - wall_t, z_top), mat_idx=mat_idx)
    _add_box_bm(bm, (x1 - wall_t, y0 + wall_t, z_floor_top), (x1, y1 - wall_t, z_top), mat_idx=mat_idx)


def build_trolley_cart(out_path: Path) -> Path:
    """Build 1.10m L x 0.90m H x 0.60m W heavy 2-tier steel utility workshop push-cart."""
    clean_scene()
    mats = _create_shared_materials()
    mat_painted = 0
    mat_steel = 1
    mat_rubber = 2

    bm = bmesh.new()

    # Outer frame bounds: X[-0.550, +0.490] (push handle reaches +0.550), Y[-0.297, +0.297] (+3mm bolt = +-0.300)
    cx0, cx1 = -0.550, 0.490
    cy0, cy1 = -0.297, 0.297
    leg_w = 0.040
    leg_t = 0.006

    # Trays nest inside angle-iron upright flanges (no coplanar z-fighting at corners)
    tx0, tx1 = cx0 + leg_t, cx1 - leg_t
    ty0, ty1 = cy0 + leg_t, cy1 - leg_t

    # 1. Lower & upper lipped tray decks
    _add_lipped_tray(bm, tx0, tx1, ty0, ty1, z_bot=0.180, z_top=0.240, wall_t=0.014, floor_t=0.014, mat_idx=mat_painted)
    _add_lipped_tray(bm, tx0, tx1, ty0, ty1, z_bot=0.740, z_top=0.800, wall_t=0.014, floor_t=0.014, mat_idx=mat_painted)

    # Under-tray cross stiffener ribs beneath lower deck
    for rx in (-0.28, 0.0, 0.22):
        _add_box_bm(bm, (rx - 0.015, -0.26, 0.166), (rx + 0.015, 0.26, 0.180), mat_idx=mat_painted)

    # 2. Four angle-iron corner uprights (Z: 0.180 .. 0.800) + 8 welded corner gussets
    gusset_l = 0.075
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx = cx0 if sx < 0.0 else cx1
            cy = cy0 if sy < 0.0 else cy1

            # X-aligned flange of angle-iron upright (spanning outer corner cleanly)
            fx0 = cx if sx < 0.0 else (cx - leg_w)
            fx1 = (cx + leg_w) if sx < 0.0 else cx
            fy0 = cy if sy < 0.0 else (cy - leg_t)
            fy1 = (cy + leg_t) if sy < 0.0 else cy
            _add_box_bm(bm, (fx0, fy0, 0.180), (fx1, fy1, 0.800), mat_idx=mat_painted)

            # Y-aligned flange (starts past leg_t so the two flanges don't overlap)
            gx0 = cx if sx < 0.0 else (cx - leg_t)
            gx1 = (cx + leg_t) if sx < 0.0 else cx
            gy0 = (cy + leg_t) if sy < 0.0 else (cy - leg_w)
            gy1 = (cy + leg_w) if sy < 0.0 else (cy - leg_t)
            _add_box_bm(bm, (gx0, gy0, 0.180), (gx1, gy1, 0.800), mat_idx=mat_painted)

            # Welded triangular corner gussets (under upper tray & above lower tray)
            gy_in0 = (cy + leg_t) if sy < 0.0 else (cy - leg_t - 0.005)
            gy_in1 = (cy + leg_t + 0.005) if sy < 0.0 else (cy - leg_t)
            x_root = cx + leg_t if sx < 0.0 else cx - leg_t
            x_tip = x_root + gusset_l if sx < 0.0 else x_root - gusset_l

            # Upper corner gusset (Z: 0.665 .. 0.740)
            up_pts = [(x_root, 0.665), (x_root, 0.740), (x_tip, 0.740)]
            if sx > 0.0:
                up_pts = list(reversed(up_pts))
            _add_prism_x_bm(bm, gy_in0, gy_in1, up_pts, mat_idx=mat_painted)

            # Lower corner gusset (Z: 0.240 .. 0.315)
            lo_pts = [(x_root, 0.240), (x_tip, 0.240), (x_root, 0.315)]
            if sx > 0.0:
                lo_pts = list(reversed(lo_pts))
            _add_prism_x_bm(bm, gy_in0, gy_in1, lo_pts, mat_idx=mat_painted)

            # Corner steel rivets/bolts at upper and lower tray joints (outer face at +-0.300)
            for bz in (0.210, 0.770):
                by_out0 = cy - 0.003 if sy < 0.0 else cy
                by_out1 = cy if sy < 0.0 else cy + 0.003
                bx = cx + 0.022 if sx < 0.0 else cx - 0.022
                _add_cylinder_bm(
                    bm,
                    Vector((bx, by_out0, bz)),
                    Vector((bx, by_out1, bz)),
                    r0=0.006,
                    segments=6,
                    mat_idx=mat_steel,
                    smooth=False,
                )

    # 3. Four swivel caster forks + dark rubber wheels touching Z = 0.000
    casters = [
        ((-0.455, -0.215), 0.0),
        ((-0.455, 0.215), 0.0),
        ((0.405, -0.215), 16.0),
        ((0.405, 0.215), -14.0),
    ]
    for pos_xy, yaw in casters:
        _add_swivel_caster(bm, pos_xy, yaw, mat_steel=mat_steel, mat_rubber=mat_rubber)

    # 4. Bent tubular steel push handle on +X end rising cleanly to Z = 0.900m (X_max = 0.550m)
    handle_r = 0.015  # centerline X=0.535, Z=0.885 -> max X=0.550, max Z=0.900
    hy = 0.235
    x_root = 0.478
    z_root = 0.785
    x_bar = 0.535
    z_bar = 0.885
    bend_r = 0.055

    # Mounting weld sockets at handle roots
    for sy in (-1.0, 1.0):
        _add_cylinder_bm(
            bm,
            Vector((x_root - 0.008, sy * hy, z_root - 0.020)),
            Vector((x_root + 0.008, sy * hy, z_root + 0.012)),
            r0=0.021,
            segments=10,
            mat_idx=mat_steel,
        )

    # Continuous U-bend tubular path in tilted handle plane (exact max X=0.550, max Z=0.900)
    top_left = Vector((x_bar, -hy, z_bar))
    top_right = Vector((x_bar, hy, z_bar))
    leg_dir = Vector((x_bar - x_root, 0.0, z_bar - z_root)).normalized()
    bend_r = 0.045

    c_left = top_left - leg_dir * bend_r + Vector((0.0, bend_r, 0.0))
    c_right = top_right - leg_dir * bend_r + Vector((0.0, -bend_r, 0.0))

    handle_pts: list[Vector] = [Vector((x_root, -hy, z_root))]
    for k in range(6):
        ang = (k / 5.0) * (math.pi * 0.5)
        pt = c_left + leg_dir * (bend_r * math.sin(ang)) + Vector((0.0, -bend_r * math.cos(ang), 0.0))
        handle_pts.append(pt)
    handle_pts.append(Vector((x_bar, 0.0, z_bar)))
    for k in range(6):
        ang = (k / 5.0) * (math.pi * 0.5)
        pt = c_right + leg_dir * (bend_r * math.cos(ang)) + Vector((0.0, bend_r * math.sin(ang), 0.0))
        handle_pts.append(pt)
    handle_pts.append(Vector((x_root, hy, z_root)))

    _add_swept_tube_bm(
        bm, handle_pts, radius=handle_r, radial_segments=10, cap_ends=True, mat_idx=mat_steel
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    return _finalize_and_export(
        slug="trolley_cart",
        bm=bm,
        materials=[mats["painted_metal"], mats["steel"], mats["rubber_dark"]],
        out_path=out_path,
    )


def main() -> None:
    """Generate all 3 factory workshop utility prop GLBs (or a single named asset)."""
    parser = argparse.ArgumentParser(description="Generate factory workshop utility prop GLBs.")
    parser.add_argument(
        "--asset",
        choices=["electric_wires_4m", "coiled_hose", "trolley_cart"],
        default=None,
        help="Optional single asset slug to generate; generates all 3 if omitted.",
    )
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    args, _ = parser.parse_known_args(argv)

    _OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    builders = {
        "electric_wires_4m": build_electric_wires_4m,
        "coiled_hose": build_coiled_hose,
        "trolley_cart": build_trolley_cart,
    }
    targets = [args.asset] if args.asset else list(builders.keys())
    for slug in targets:
        builders[slug](_OUTPUT_DIR / f"{slug}.glb")


if __name__ == "__main__":
    main()
