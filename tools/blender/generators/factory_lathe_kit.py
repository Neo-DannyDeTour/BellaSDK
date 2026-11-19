"""Procedural Blender generator for post-Soviet industrial engine lathe GLB.

Generates clean-room industrial workshop prop asset in
assets/models/props/factory_workshop/metal_lathe.glb:
- Dimensions: ~2.00m wide x 1.45m tall x 0.90m deep
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y/Z)
- Clean world-metric box UVs (1.0m tile)
- Material slots: ['painted_steel', 'steel']
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


# ==============================================================================
# BMESH & UV HELPERS
# ==============================================================================
def _merge_temp_bmesh(
    tmp: bmesh.types.BMesh,
    dst: bmesh.types.BMesh,
    mat_idx: int,
) -> list[bmesh.types.BMFace]:
    """Copy geometry from tmp BMesh into dst BMesh and assign mat_idx."""
    vert_map: dict[int, bmesh.types.BMVert] = {}
    tmp.verts.ensure_lookup_table()
    for idx, v in enumerate(tmp.verts):
        vert_map[idx] = dst.verts.new(v.co)

    created_faces: list[bmesh.types.BMFace] = []
    for f in tmp.faces:
        new_f = dst.faces.new([vert_map[v.index] for v in f.verts])
        new_f.material_index = mat_idx
        created_faces.append(new_f)

    tmp.free()
    return created_faces


def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append an axis-aligned box (with optional edge chamfer) to a BMesh."""
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
            (2, 3, 7, 6),
            (0, 4, 7, 3),
            (1, 2, 6, 5),
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
    return _merge_temp_bmesh(tmp, bm, mat_idx)


def _add_cylinder_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    r0: float,
    r1: float | None = None,
    segments: int = 12,
    cap_ends: bool = True,
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    """Append a cylinder or frustum between p0 and p1 with explicit material index."""
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
    return _merge_temp_bmesh(tmp, bm, mat_idx)


def _add_handwheel_bm(
    bm: bmesh.types.BMesh,
    center: Vector,
    axis: Vector,
    outer_r: float,
    rim_r: float,
    spokes: int = 3,
    segments: int = 14,
    handle_len: float = 0.045,
    mat_idx: int = 1,
) -> None:
    """Append a spoked industrial handwheel with rim ring, center hub, and crank handle."""
    n = axis.normalized()
    ref = Vector((0.0, 0.0, 1.0)) if abs(n.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = n.cross(ref).normalized()
    v = n.cross(u).normalized()

    # Center hub
    hub_half = max(0.012, rim_r * 1.2)
    _add_cylinder_bm(
        bm,
        center - n * hub_half,
        center + n * hub_half,
        r0=max(0.014, outer_r * 0.22),
        segments=10,
        mat_idx=mat_idx,
    )

    # Outer rim built from straight chord segments between ring vertices
    ring_r = outer_r - rim_r
    for i in range(segments):
        a0 = 2.0 * math.pi * i / segments
        a1 = 2.0 * math.pi * ((i + 1) % segments) / segments
        p0 = center + u * (math.cos(a0) * ring_r) + v * (math.sin(a0) * ring_r)
        p1 = center + u * (math.cos(a1) * ring_r) + v * (math.sin(a1) * ring_r)
        _add_cylinder_bm(bm, p0, p1, r0=rim_r, segments=6, cap_ends=True, mat_idx=mat_idx)

    # Radial spokes
    for s in range(spokes):
        ang = 2.0 * math.pi * s / spokes
        p_out = center + u * (math.cos(ang) * ring_r) + v * (math.sin(ang) * ring_r)
        _add_cylinder_bm(
            bm,
            center,
            p_out,
            r0=max(0.006, rim_r * 0.72),
            segments=6,
            mat_idx=mat_idx,
        )

    # Offset crank handle protruding along +axis
    if handle_len > 0.0:
        h_base = center + u * ring_r
        _add_cylinder_bm(
            bm,
            h_base,
            h_base + n * handle_len,
            r0=max(0.007, rim_r * 0.85),
            r1=max(0.009, rim_r * 1.05),
            segments=8,
            mat_idx=mat_idx,
        )


def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 1.0) -> None:
    """Generate world-metric cubic box UVs so PBR materials tile cleanly."""
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
            vert = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            if nx >= ny and nx >= nz:
                u, v = vert.y * inv_tile, vert.z * inv_tile
            elif ny >= nx and ny >= nz:
                u, v = vert.x * inv_tile, vert.z * inv_tile
            else:
                u, v = vert.x * inv_tile, vert.y * inv_tile
            uv_layer[loop_idx].uv = (u, v)


def _finalize_bmesh_to_object(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    auto_smooth_deg: float = 35.0,
) -> bpy.types.Object:
    """Convert BMesh into scene Object with multi-material slots and angle-based smoothing."""
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    thresh_rad = math.radians(auto_smooth_deg)
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            edge.smooth = edge.calc_face_angle(0.0) <= thresh_rad
        else:
            edge.smooth = False

    bm.to_mesh(mesh)
    bm.free()

    for mat in materials:
        mesh.materials.append(mat)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _report_mesh_stats(label: str, obj: bpy.types.Object) -> None:
    """Print triangle count, material slots, and Godot Y-up bounding box."""
    mesh = obj.data
    tri_count = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    g_min = (min(xs), min(zs), -max(ys))
    g_max = (max(xs), max(zs), -min(ys))
    slot_names = [m.name for m in mesh.materials]
    print(
        f"[{label}] tris={tri_count} slots={slot_names} | "
        f"Godot BBox min=({g_min[0]:.3f}, {g_min[1]:.3f}, {g_min[2]:.3f}) "
        f"max=({g_max[0]:.3f}, {g_max[1]:.3f}, {g_max[2]:.3f}) "
        f"size=({g_max[0] - g_min[0]:.3f}, {g_max[1] - g_min[1]:.3f}, {g_max[2] - g_min[2]:.3f})"
    )


# ==============================================================================
# LATHE SUB-ASSEMBLIES
# ==============================================================================
def _add_pedestal(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    y_half: float,
    z_top: float,
    mat_paint: int,
    mat_steel: int,
) -> None:
    """Build a cast pedestal cabinet with flanged footplate, anchor bolts, and front door."""
    flange_h = 0.048
    # Flanged mounting footplate resting cleanly on Z=0
    _add_box_bm(
        bm,
        (x0 - 0.024, -y_half - 0.030, 0.0),
        (x1 + 0.024, y_half + 0.030, flange_h),
        mat_idx=mat_paint,
        chamfer=0.008,
    )
    # 4 corner anchor bolts
    for bx in (x0 - 0.006, x1 + 0.006):
        for by in (-y_half - 0.010, y_half + 0.010):
            _add_cylinder_bm(
                bm,
                Vector((bx, by, flange_h)),
                Vector((bx, by, flange_h + 0.014)),
                r0=0.010,
                segments=6,
                mat_idx=mat_steel,
            )

    # Main cabinet column
    _add_box_bm(
        bm,
        (x0, -y_half, flange_h),
        (x1, y_half, z_top),
        mat_idx=mat_paint,
        chamfer=0.012,
    )

    # Front recessed-frame access door + latch + hinges
    door_x0 = x0 + 0.055
    door_x1 = x1 - 0.055
    door_z0 = flange_h + 0.065
    door_z1 = z_top - 0.075
    _add_box_bm(
        bm,
        (door_x0, -y_half - 0.014, door_z0),
        (door_x1, -y_half, door_z1),
        mat_idx=mat_paint,
        chamfer=0.004,
    )
    # Recessed steel finger latch on right edge of door
    _add_box_bm(
        bm,
        (door_x1 - 0.055, -y_half - 0.022, 0.5 * (door_z0 + door_z1) - 0.045),
        (door_x1 - 0.028, -y_half - 0.014, 0.5 * (door_z0 + door_z1) + 0.045),
        mat_idx=mat_steel,
    )
    # Two door hinges on left edge
    for hz in (door_z0 + 0.065, door_z1 - 0.065):
        _add_cylinder_bm(
            bm,
            Vector((door_x0, -y_half - 0.012, hz - 0.020)),
            Vector((door_x0, -y_half - 0.012, hz + 0.020)),
            r0=0.008,
            segments=6,
            mat_idx=mat_steel,
        )


def _add_headstock_and_chuck(
    bm: bmesh.types.BMesh,
    mat_paint: int,
    mat_steel: int,
) -> None:
    """Build headstock gearbox, left gear cover, Norton feed box, levers, and 3-jaw chuck."""
    spindle_y = 0.0
    spindle_z = 1.180

    # Main headstock gearbox casting (top reaches exact Z = 1.450m)
    _add_box_bm(
        bm,
        (-0.94, -0.23, 0.92),
        (-0.40, 0.23, 1.41),
        mat_idx=mat_paint,
        chamfer=0.015,
    )
    # Top removable inspection cap
    _add_box_bm(
        bm,
        (-0.91, -0.20, 1.41),
        (-0.43, 0.20, 1.45),
        mat_idx=mat_paint,
        chamfer=0.010,
    )

    # Left end change-gear / belt guard housing (reaches X = -1.000m)
    _add_box_bm(
        bm,
        (-1.00, -0.21, 0.75),
        (-0.94, 0.19, 1.35),
        mat_idx=mat_paint,
        chamfer=0.012,
    )

    # Lower Norton quick-change feed gearbox protruding forward
    _add_box_bm(
        bm,
        (-0.94, -0.28, 0.745),
        (-0.42, -0.17, 0.94),
        mat_idx=mat_paint,
        chamfer=0.010,
    )

    # Headstock front steel speed-chart nameplate
    _add_box_bm(
        bm,
        (-0.84, -0.238, 1.24),
        (-0.54, -0.23, 1.36),
        mat_idx=mat_steel,
    )

    # Upper headstock shift selector dials & lever arms
    for lx, lz, ang in ((-0.78, 1.11, 0.45), (-0.58, 1.11, -0.35)):
        _add_cylinder_bm(
            bm,
            Vector((lx, -0.23, lz)),
            Vector((lx, -0.275, lz)),
            r0=0.036,
            segments=10,
            mat_idx=mat_steel,
        )
        _add_cylinder_bm(
            bm,
            Vector((lx, -0.265, lz)),
            Vector((lx + math.sin(ang) * 0.085, -0.305, lz + math.cos(ang) * 0.085)),
            r0=0.008,
            r1=0.011,
            segments=8,
            mat_idx=mat_steel,
        )

    # Lower Norton gearbox selector dials & shift levers
    for lx, lz, ang in ((-0.84, 0.85, 0.35), (-0.70, 0.84, -0.45), (-0.56, 0.85, 0.20)):
        _add_cylinder_bm(
            bm,
            Vector((lx, -0.28, lz)),
            Vector((lx, -0.320, lz)),
            r0=0.028,
            segments=10,
            mat_idx=mat_steel,
        )
        _add_cylinder_bm(
            bm,
            Vector((lx, -0.312, lz)),
            Vector((lx + math.sin(ang) * 0.070, -0.345, lz + math.cos(ang) * 0.070)),
            r0=0.007,
            r1=0.010,
            segments=8,
            mat_idx=mat_steel,
        )

    # Spindle nose collar + 3-jaw self-centering chuck
    _add_cylinder_bm(
        bm,
        Vector((-0.40, spindle_y, spindle_z)),
        Vector((-0.34, spindle_y, spindle_z)),
        r0=0.095,
        segments=16,
        mat_idx=mat_steel,
    )
    _add_cylinder_bm(
        bm,
        Vector((-0.34, spindle_y, spindle_z)),
        Vector((-0.22, spindle_y, spindle_z)),
        r0=0.142,
        segments=20,
        mat_idx=mat_steel,
    )
    # Chuck front inner step ring
    _add_cylinder_bm(
        bm,
        Vector((-0.22, spindle_y, spindle_z)),
        Vector((-0.208, spindle_y, spindle_z)),
        r0=0.068,
        segments=14,
        mat_idx=mat_steel,
    )

    # 3 stepped radial chuck jaws at 0, 120, 240 degrees
    for j in range(3):
        ang = math.radians(j * 120.0 + 30.0)
        for r_mid, x_len, rad_len in ((0.095, 0.048, 0.055), (0.062, 0.066, 0.036)):
            tmp = bmesh.new()
            jaw_w = 0.032
            xf_rot = Matrix.Rotation(ang, 4, "X")
            xf_box = (
                Matrix.Translation((0.0, spindle_y, spindle_z))
                @ xf_rot
                @ Matrix.Translation((-0.22 + x_len * 0.5, r_mid, 0.0))
                @ Matrix.Diagonal((x_len, rad_len, jaw_w, 1.0))
            )
            bmesh.ops.create_cube(tmp, size=1.0, matrix=xf_box)
            _merge_temp_bmesh(tmp, bm, mat_steel)


def _add_carriage_and_toolpost(
    bm: bmesh.types.BMesh,
    mat_paint: int,
    mat_steel: int,
) -> None:
    """Build saddle, front apron with handwheels, cross-slide, compound rest, and 4-way toolpost."""
    # Saddle wings riding across the twin ways
    _add_box_bm(
        bm,
        (-0.08, -0.21, 0.945),
        (0.32, 0.21, 1.005),
        mat_idx=mat_paint,
        chamfer=0.006,
    )

    # Front carriage apron gearbox
    _add_box_bm(
        bm,
        (-0.06, -0.31, 0.750),
        (0.30, -0.18, 0.950),
        mat_idx=mat_paint,
        chamfer=0.008,
    )

    # Large carriage handwheel (crank reaches Y = -0.450m)
    _add_handwheel_bm(
        bm,
        center=Vector((0.01, -0.365, 0.840)),
        axis=Vector((0.0, -1.0, 0.0)),
        outer_r=0.105,
        rim_r=0.012,
        spokes=3,
        segments=14,
        handle_len=0.085,
        mat_idx=mat_steel,
    )

    # Half-nut & feed engagement levers on apron
    for lx, lz, dx in ((0.18, 0.87, 0.045), (0.24, 0.81, -0.035)):
        _add_cylinder_bm(
            bm,
            Vector((lx, -0.31, lz)),
            Vector((lx, -0.345, lz)),
            r0=0.018,
            segments=8,
            mat_idx=mat_steel,
        )
        _add_cylinder_bm(
            bm,
            Vector((lx, -0.335, lz)),
            Vector((lx + dx, -0.365, lz + 0.065)),
            r0=0.007,
            r1=0.010,
            segments=8,
            mat_idx=mat_steel,
        )

    # Cross-slide dovetail base + carriage + front handwheel
    _add_box_bm(
        bm,
        (0.02, -0.23, 1.005),
        (0.22, 0.16, 1.060),
        mat_idx=mat_steel,
        chamfer=0.005,
    )
    _add_handwheel_bm(
        bm,
        center=Vector((0.12, -0.285, 1.032)),
        axis=Vector((0.0, -1.0, 0.0)),
        outer_r=0.062,
        rim_r=0.009,
        spokes=3,
        segments=12,
        handle_len=0.048,
        mat_idx=mat_steel,
    )

    # Compound rest swivel base + upper slide
    _add_cylinder_bm(
        bm,
        Vector((0.12, 0.0, 1.060)),
        Vector((0.12, 0.0, 1.095)),
        r0=0.088,
        segments=14,
        mat_idx=mat_paint,
    )
    _add_box_bm(
        bm,
        (0.04, -0.095, 1.095),
        (0.22, 0.065, 1.135),
        mat_idx=mat_steel,
        chamfer=0.004,
    )
    _add_handwheel_bm(
        bm,
        center=Vector((0.255, -0.015, 1.115)),
        axis=Vector((1.0, 0.0, 0.0)),
        outer_r=0.042,
        rim_r=0.007,
        spokes=3,
        segments=10,
        handle_len=0.036,
        mat_idx=mat_steel,
    )

    # 4-way turret toolpost + locking lever + cutting tool shank
    _add_box_bm(
        bm,
        (0.055, -0.065, 1.135),
        (0.175, 0.055, 1.225),
        mat_idx=mat_steel,
        chamfer=0.005,
    )
    # Toolpost clamp hub + handle
    _add_cylinder_bm(
        bm,
        Vector((0.115, -0.005, 1.225)),
        Vector((0.115, -0.005, 1.258)),
        r0=0.022,
        segments=8,
        mat_idx=mat_steel,
    )
    _add_cylinder_bm(
        bm,
        Vector((0.115, -0.005, 1.246)),
        Vector((0.225, -0.055, 1.275)),
        r0=0.008,
        r1=0.011,
        segments=8,
        mat_idx=mat_steel,
    )
    # Protruding cutting tool bit toward chuck
    _add_box_bm(
        bm,
        (-0.025, -0.022, 1.165),
        (0.055, 0.008, 1.192),
        mat_idx=mat_steel,
    )


def _add_tailstock(
    bm: bmesh.types.BMesh,
    mat_paint: int,
    mat_steel: int,
) -> None:
    """Build tailstock sliding base, sculpted casting, quill barrel, live center, and handwheel."""
    spindle_y = 0.0
    spindle_z = 1.180

    # Tailstock base plate riding on bed ways
    _add_box_bm(
        bm,
        (0.56, -0.16, 0.955),
        (0.88, 0.16, 1.015),
        mat_idx=mat_paint,
        chamfer=0.006,
    )
    # Tailstock body column
    _add_box_bm(
        bm,
        (0.58, -0.115, 1.015),
        (0.85, 0.115, 1.190),
        mat_idx=mat_paint,
        chamfer=0.010,
    )
    # Upper cylindrical quill housing along spindle axis
    _add_cylinder_bm(
        bm,
        Vector((0.57, spindle_y, spindle_z)),
        Vector((0.86, spindle_y, spindle_z)),
        r0=0.068,
        segments=14,
        mat_idx=mat_paint,
    )
    # Quill clamping lever
    _add_cylinder_bm(
        bm,
        Vector((0.66, spindle_y, 1.240)),
        Vector((0.66, -0.085, 1.295)),
        r0=0.008,
        r1=0.011,
        segments=8,
        mat_idx=mat_steel,
    )
    # Extending steel quill barrel + conical live center
    _add_cylinder_bm(
        bm,
        Vector((0.48, spindle_y, spindle_z)),
        Vector((0.57, spindle_y, spindle_z)),
        r0=0.042,
        segments=12,
        mat_idx=mat_steel,
    )
    _add_cylinder_bm(
        bm,
        Vector((0.40, spindle_y, spindle_z)),
        Vector((0.48, spindle_y, spindle_z)),
        r0=0.004,
        r1=0.032,
        segments=12,
        mat_idx=mat_steel,
    )
    # Right-end tailstock feed handwheel (crank stays inside +1.000m)
    _add_handwheel_bm(
        bm,
        center=Vector((0.915, spindle_y, spindle_z)),
        axis=Vector((1.0, 0.0, 0.0)),
        outer_r=0.105,
        rim_r=0.012,
        spokes=3,
        segments=14,
        handle_len=0.072,
        mat_idx=mat_steel,
    )


# ==============================================================================
# MAIN GENERATOR
# ==============================================================================
def generate_metal_lathe(output_dir: Path) -> Path:
    """Generate post-Soviet industrial engine lathe GLB (~2.0m W x 1.45m H x 0.90m D)."""
    clean_scene()

    painted_mat = create_pbr_material(
        name="painted_steel",
        base_color=(0.24, 0.29, 0.24, 1.0),
        metallic=0.30,
        roughness=0.56,
    )
    steel_mat = create_pbr_material(
        name="steel",
        base_color=(0.58, 0.60, 0.62, 1.0),
        metallic=0.90,
        roughness=0.30,
    )

    bm = bmesh.new()
    mat_paint = 0
    mat_steel = 1

    # 1. Twin cast pedestals (Z: 0.00 -> 0.68)
    _add_pedestal(bm, x0=-0.95, x1=-0.26, y_half=0.34, z_top=0.68, mat_paint=mat_paint, mat_steel=mat_steel)
    _add_pedestal(bm, x0=0.45, x1=0.93, y_half=0.32, z_top=0.68, mat_paint=mat_paint, mat_steel=mat_steel)

    # 2. Full-width chip & coolant pan tray (X: -1.00 -> +1.00, Z: 0.68 -> 0.745)
    _add_box_bm(bm, (-1.00, -0.39, 0.68), (1.00, 0.39, 0.715), mat_idx=mat_paint, chamfer=0.006)
    # Tray steel bottom liner
    _add_box_bm(bm, (-0.97, -0.36, 0.715), (0.97, 0.36, 0.722), mat_idx=mat_steel)
    # Raised perimeter rim walls
    _add_box_bm(bm, (-1.00, -0.39, 0.715), (1.00, -0.36, 0.745), mat_idx=mat_paint, chamfer=0.004)
    _add_box_bm(bm, (-1.00, 0.36, 0.715), (1.00, 0.39, 0.745), mat_idx=mat_paint, chamfer=0.004)
    _add_box_bm(bm, (-1.00, -0.36, 0.715), (-0.97, 0.36, 0.745), mat_idx=mat_paint, chamfer=0.004)
    _add_box_bm(bm, (0.97, -0.36, 0.715), (1.00, 0.36, 0.745), mat_idx=mat_paint, chamfer=0.004)

    # Rear sheet-metal coolant splash guard (reaches Y = +0.450m for clean 0.90m depth envelope)
    _add_box_bm(bm, (-0.44, 0.375, 0.72), (0.88, 0.450, 0.76), mat_idx=mat_paint, chamfer=0.004)
    _add_box_bm(bm, (-0.44, 0.415, 0.755), (0.88, 0.450, 1.22), mat_idx=mat_paint, chamfer=0.005)
    # Two vertical support brackets tying splash guard into chip tray
    for bx in (-0.34, 0.78):
        _add_box_bm(bm, (bx - 0.025, 0.35, 0.72), (bx + 0.025, 0.43, 0.98), mat_idx=mat_paint)

    # 3. Cast bed pedestals, main bed beam, and twin precision steel ways
    _add_box_bm(bm, (-0.91, -0.18, 0.722), (-0.38, 0.18, 0.775), mat_idx=mat_paint)
    _add_box_bm(bm, (0.50, -0.17, 0.722), (0.92, 0.17, 0.775), mat_idx=mat_paint)
    # Main bed casting
    _add_box_bm(bm, (-0.92, -0.165, 0.775), (0.94, 0.165, 0.920), mat_idx=mat_paint, chamfer=0.008)
    # Bed right-end leadscrew bearing block
    _add_box_bm(bm, (0.87, -0.23, 0.755), (0.94, 0.165, 0.935), mat_idx=mat_paint, chamfer=0.006)

    # Twin precision steel ways (front + rear)
    _add_box_bm(bm, (-0.42, -0.155, 0.920), (0.94, -0.075, 0.960), mat_idx=mat_steel, chamfer=0.007)
    _add_box_bm(bm, (-0.42, 0.075, 0.920), (0.94, 0.155, 0.960), mat_idx=mat_steel, chamfer=0.007)

    # 4. Leadscrew, feed rod, and spindle control rod
    for ry, rz, rr in ((-0.205, 0.878, 0.014), (-0.205, 0.826, 0.011), (-0.205, 0.778, 0.010)):
        _add_cylinder_bm(
            bm,
            Vector((-0.44, ry, rz)),
            Vector((0.88, ry, rz)),
            r0=rr,
            segments=10,
            mat_idx=mat_steel,
        )

    # 5. Headstock + chuck, carriage + toolpost, tailstock
    _add_headstock_and_chuck(bm, mat_paint=mat_paint, mat_steel=mat_steel)
    _add_carriage_and_toolpost(bm, mat_paint=mat_paint, mat_steel=mat_steel)
    _add_tailstock(bm, mat_paint=mat_paint, mat_steel=mat_steel)

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)

    lathe_obj = _finalize_bmesh_to_object("metal_lathe", bm, [painted_mat, steel_mat])
    _apply_box_uvs(lathe_obj, tile_meters=1.0)
    _report_mesh_stats("metal_lathe", lathe_obj)

    output_path = output_dir / "metal_lathe.glb"
    return export_godot_glb(
        filepath=output_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )


def main() -> None:
    """Generate metal_lathe.glb under assets/models/props/factory_workshop/."""
    sdk_root = Path(__file__).resolve().parent.parent.parent.parent
    output_dir = sdk_root / "assets" / "models" / "props" / "factory_workshop"
    output_dir.mkdir(parents=True, exist_ok=True)
    generate_metal_lathe(output_dir)


if __name__ == "__main__":
    main()
