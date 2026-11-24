"""Procedural Blender generator for workshop MEP control & valve kit GLBs.

Generates 3 clean-room post-apocalyptic industrial MEP assets in
assets/models/props/factory_workshop/:
4. steel_pipe_elbow_valve.glb   - 1.0m x 0.72m x 1.0m flanged 90-deg pipe elbow + gate valve & gauge.
5. electrical_panel_openable.glb - 0.75m x 1.05m x 0.28m wall NEMA cabinet + hinged openable door.
6. emergency_button.glb          - 0.18m x 0.22m x 0.14m yellow E-stop box + articulated red cap.

Conventions:
- Blender CLI: /snap/bin/blender --background --python tools/blender/generators/factory_mep_control_kit.py
- Godot Y-up export (export_yup=True): Godot +X = Blender +X, Godot +Y = Blender +Z, Godot +Z = Blender -Y.
- Grounded min_y = 0.0 in Godot (min_z = 0.0 in Blender).
- Wall-mounted assets have rear mounting face flush at Godot Z = 0.0 (Blender Y = 0.0) protruding into Godot +Z (Blender Y <= 0.0).
- Articulated multi-object assets (electrical_panel_openable, emergency_button) preserve child object pivot locations without apply location=True.
- Clean world-metric 1.0m cubic box UVs.
- Deterministic material slot ordering matching BellaSDK Godot .tres overrides + embedded glTF PBR slots.
"""

from __future__ import annotations

import json
import math
import struct
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


def _fmt(val: float) -> float:
    """Round float to 4 decimals and normalize -0.0 to 0.0."""
    rounded = round(val, 4)
    return 0.0 if rounded == 0.0 else rounded


def _create_shared_materials() -> dict[str, bpy.types.Material]:
    """Create PBR materials matching BellaSDK .tres overrides and embedded glTF slots."""
    painted_mat = create_pbr_material(
        name="painted_metal",
        base_color=(0.20, 0.34, 0.38, 1.0),
        metallic=0.45,
        roughness=0.62,
    )
    steel_mat = create_pbr_material(
        name="steel",
        base_color=(0.24, 0.22, 0.20, 1.0),
        metallic=0.82,
        roughness=0.58,
    )
    brass_mat = create_pbr_material(
        name="brass",
        base_color=(0.68, 0.55, 0.32, 1.0),
        metallic=0.85,
        roughness=0.42,
    )
    glass_mat = create_pbr_material(
        name="glass",
        base_color=(0.46, 0.54, 0.60, 0.38),
        metallic=0.05,
        roughness=0.24,
    )
    if glass_mat.node_tree:
        bsdf = glass_mat.node_tree.nodes.get("Principled BSDF")
        if bsdf and "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = 0.38
    if hasattr(glass_mat, "blend_method"):
        glass_mat.blend_method = "BLEND"

    rubber_dark_mat = create_pbr_material(
        name="rubber_dark",
        base_color=(0.07, 0.075, 0.08, 1.0),
        metallic=0.0,
        roughness=0.82,
    )
    safety_red_mat = create_pbr_material(
        name="safety_red",
        base_color=(0.58, 0.09, 0.07, 1.0),
        metallic=0.15,
        roughness=0.45,
    )
    safety_yellow_mat = create_pbr_material(
        name="safety_yellow",
        base_color=(0.68, 0.50, 0.09, 1.0),
        metallic=0.1,
        roughness=0.52,
    )

    return {
        "painted_metal": painted_mat,
        "steel": steel_mat,
        "brass": brass_mat,
        "glass": glass_mat,
        "rubber_dark": rubber_dark_mat,
        "safety_red": safety_red_mat,
        "safety_yellow": safety_yellow_mat,
    }


def _merge_temp_bmesh(
    tmp: bmesh.types.BMesh,
    dst: bmesh.types.BMesh,
    mat_idx: int,
) -> list[bmesh.types.BMFace]:
    """Copy geometry from tmp BMesh into dst BMesh and assign mat_idx."""
    vert_map: dict[int, bmesh.types.BMVert] = {}
    tmp.verts.ensure_lookup_table()
    for idx, vert in enumerate(tmp.verts):
        vert_map[idx] = dst.verts.new(vert.co)

    created_faces: list[bmesh.types.BMFace] = []
    for face in tmp.faces:
        new_face = dst.faces.new([vert_map[v.index] for v in face.verts])
        new_face.material_index = mat_idx
        created_faces.append(new_face)

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
        for quad in quads:
            face = bm.faces.new([verts[i] for i in quad])
            face.material_index = mat_idx
            faces.append(face)
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


def _add_oriented_box_bm(
    bm: bmesh.types.BMesh,
    center: Vector,
    size: tuple[float, float, float],
    rot_matrix: Matrix,
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append an oriented box with local (sx, sy, sz) and rotation matrix."""
    sx, sy, sz = size
    xf = Matrix.Translation(center) @ rot_matrix.to_4x4() @ Matrix.Diagonal((sx, sy, sz, 1.0))
    tmp = bmesh.new()
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


def _add_strut_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    width: float,
    thickness: float,
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append a rectangular strut running from p0 to p1."""
    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return []
    z_axis = vec.normalized()
    ref_x = Vector((1.0, 0.0, 0.0))
    if abs(z_axis.dot(ref_x)) > 0.98:
        ref_x = Vector((0.0, 1.0, 0.0))
    y_axis = z_axis.cross(ref_x).normalized()
    x_axis = y_axis.cross(z_axis).normalized()
    rot = Matrix((x_axis, y_axis, z_axis)).transposed()
    return _add_oriented_box_bm(
        bm,
        center=(p0 + p1) * 0.5,
        size=(width, thickness, length),
        rot_matrix=rot,
        mat_idx=mat_idx,
        chamfer=chamfer,
    )


def _add_cylinder_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    r0: float,
    r1: float | None = None,
    segments: int = 16,
    cap_ends: bool = True,
    mat_idx: int = 0,
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
    return _merge_temp_bmesh(tmp, bm, mat_idx)


def _add_annular_ring_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    r_inner: float,
    r_outer: float,
    segments: int = 16,
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    """Append a watertight hollow circular ring/flange between p0 and p1."""
    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return []
    z_axis = vec.normalized()
    ref = Vector((0.0, 0.0, 1.0))
    if abs(z_axis.dot(ref)) > 0.98:
        ref = Vector((0.0, 1.0, 0.0))
    u_dir = z_axis.cross(ref).normalized()
    v_dir = z_axis.cross(u_dir).normalized()

    ring_0_out: list[bmesh.types.BMVert] = []
    ring_0_in: list[bmesh.types.BMVert] = []
    ring_1_out: list[bmesh.types.BMVert] = []
    ring_1_in: list[bmesh.types.BMVert] = []
    for k in range(segments):
        ang = 2.0 * math.pi * float(k) / float(segments)
        radial = u_dir * math.cos(ang) + v_dir * math.sin(ang)
        ring_0_out.append(bm.verts.new(p0 + radial * r_outer))
        ring_0_in.append(bm.verts.new(p0 + radial * r_inner))
        ring_1_out.append(bm.verts.new(p1 + radial * r_outer))
        ring_1_in.append(bm.verts.new(p1 + radial * r_inner))

    faces: list[bmesh.types.BMFace] = []
    for k in range(segments):
        kn = (k + 1) % segments
        for quad in (
            (ring_0_out[k], ring_0_out[kn], ring_1_out[kn], ring_1_out[k]),
            (ring_1_in[k], ring_1_in[kn], ring_0_in[kn], ring_0_in[k]),
            (ring_0_in[k], ring_0_in[kn], ring_0_out[kn], ring_0_out[k]),
            (ring_1_out[k], ring_1_out[kn], ring_1_in[kn], ring_1_in[k]),
        ):
            face = bm.faces.new(quad)
            face.material_index = mat_idx
            faces.append(face)
    return faces


def _add_sweep_tube_bm(
    bm: bmesh.types.BMesh,
    stations: list[tuple[Vector, Vector, Vector, float]],
    radial_segments: int = 16,
    mat_idx: int = 0,
    cap_start: bool = False,
    cap_end: bool = False,
) -> list[bmesh.types.BMFace]:
    """Sweep a circular cross-section through stations (center, u_dir, v_dir, radius)."""
    rings: list[list[bmesh.types.BMVert]] = []
    for center, u_dir, v_dir, radius in stations:
        ring: list[bmesh.types.BMVert] = []
        for s_idx in range(radial_segments):
            ang = 2.0 * math.pi * float(s_idx) / float(radial_segments)
            pt = center + (u_dir * math.cos(ang) + v_dir * math.sin(ang)) * radius
            ring.append(bm.verts.new(pt))
        rings.append(ring)

    faces: list[bmesh.types.BMFace] = []
    for r_idx in range(len(rings) - 1):
        r0 = rings[r_idx]
        r1 = rings[r_idx + 1]
        for s_idx in range(radial_segments):
            s_next = (s_idx + 1) % radial_segments
            face = bm.faces.new((r0[s_idx], r0[s_next], r1[s_next], r1[s_idx]))
            face.material_index = mat_idx
            faces.append(face)

    if cap_start:
        f_start = bm.faces.new(list(reversed(rings[0])))
        f_start.material_index = mat_idx
        faces.append(f_start)
    if cap_end:
        f_end = bm.faces.new(list(rings[-1]))
        f_end.material_index = mat_idx
        faces.append(f_end)

    return faces


def _add_torus_bm(
    bm: bmesh.types.BMesh,
    center: Vector,
    major_radius: float,
    minor_radius: float,
    major_segments: int = 16,
    minor_segments: int = 8,
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    """Append a horizontal Z-up torus ring around center."""
    rings: list[list[bmesh.types.BMVert]] = []
    for i in range(major_segments):
        phi = 2.0 * math.pi * float(i) / float(major_segments)
        radial_dir = Vector((math.cos(phi), math.sin(phi), 0.0))
        up_dir = Vector((0.0, 0.0, 1.0))
        ring_center = center + radial_dir * major_radius
        ring: list[bmesh.types.BMVert] = []
        for j in range(minor_segments):
            theta = 2.0 * math.pi * float(j) / float(minor_segments)
            pt = ring_center + (radial_dir * math.cos(theta) + up_dir * math.sin(theta)) * minor_radius
            ring.append(bm.verts.new(pt))
        rings.append(ring)

    faces: list[bmesh.types.BMFace] = []
    for i in range(major_segments):
        i_next = (i + 1) % major_segments
        r0 = rings[i]
        r1 = rings[i_next]
        for j in range(minor_segments):
            j_next = (j + 1) % minor_segments
            face = bm.faces.new((r0[j], r1[j], r1[j_next], r0[j_next]))
            face.material_index = mat_idx
            faces.append(face)
    return faces


def _add_curved_shroud_bm(
    bm: bmesh.types.BMesh,
    center_xz: tuple[float, float],
    y_back: float,
    y_front: float,
    r_inner: float,
    r_outer: float,
    angle_start_deg: float,
    angle_end_deg: float,
    arc_segments: int,
    mat_idx: int,
) -> list[bmesh.types.BMFace]:
    """Append a watertight U-shroud curved guard along Blender Y around an XZ center."""
    cx, cz = center_xz
    a0 = math.radians(angle_start_deg)
    a1 = math.radians(angle_end_deg)

    # 4 corner loops along the arc: (r_in, y_back), (r_out, y_back), (r_out, y_front), (r_in, y_front)
    sections: list[list[bmesh.types.BMVert]] = []
    for i in range(arc_segments + 1):
        t = float(i) / float(arc_segments)
        ang = a0 + (a1 - a0) * t
        ca, sa = math.cos(ang), math.sin(ang)
        pts = [
            (cx + r_inner * ca, y_back, cz + r_inner * sa),
            (cx + r_outer * ca, y_back, cz + r_outer * sa),
            (cx + r_outer * ca, y_front, cz + r_outer * sa),
            (cx + r_inner * ca, y_front, cz + r_inner * sa),
        ]
        sections.append([bm.verts.new(p) for p in pts])

    faces: list[bmesh.types.BMFace] = []
    for i in range(arc_segments):
        s0 = sections[i]
        s1 = sections[i + 1]
        for k in range(4):
            k_next = (k + 1) % 4
            face = bm.faces.new((s0[k], s0[k_next], s1[k_next], s1[k]))
            face.material_index = mat_idx
            faces.append(face)

    f_start = bm.faces.new(list(reversed(sections[0])))
    f_start.material_index = mat_idx
    faces.append(f_start)

    f_end = bm.faces.new(list(sections[-1]))
    f_end.material_index = mat_idx
    faces.append(f_end)

    return faces


def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 1.0) -> None:
    """Assign clean world-metric cubic box UVs in object local coordinates."""
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


def _finalize_bmesh_object(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
    auto_smooth_deg: float = 35.0,
) -> bpy.types.Object:
    """Convert BMesh into a Blender object with slot ordering, smooth angles, and UVs."""
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

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
    obj.location = location
    bpy.context.collection.objects.link(obj)

    if materials:
        assign_material(obj, materials[0])
        for mat in materials[1:]:
            mesh.materials.append(mat)

    _apply_box_uvs(obj, tile_meters=1.0)
    return obj


def _inspect_and_report(
    slug: str,
    objs: list[bpy.types.Object],
    glb_path: Path,
) -> None:
    """Print deterministic metrics: tris, world bboxes, slot lists, pivots, and glTF node order."""
    total_tris = 0
    all_pts: list[Vector] = []

    for obj in objs:
        mesh = obj.data
        obj_tris = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
        total_tris += obj_tris
        mat_world = obj.matrix_world
        for v in mesh.vertices:
            all_pts.append(mat_world @ v.co)

    xs = [p.x for p in all_pts]
    ys = [p.y for p in all_pts]
    zs = [p.z for p in all_pts]

    blender_bbox = (
        _fmt(min(xs)),
        _fmt(max(xs)),
        _fmt(min(ys)),
        _fmt(max(ys)),
        _fmt(min(zs)),
        _fmt(max(zs)),
    )
    godot_bbox = (
        _fmt(min(xs)),
        _fmt(max(xs)),
        _fmt(min(zs)),
        _fmt(max(zs)),
        _fmt(-max(ys)),
        _fmt(-min(ys)),
    )
    godot_size = (
        _fmt(godot_bbox[1] - godot_bbox[0]),
        _fmt(godot_bbox[3] - godot_bbox[2]),
        _fmt(godot_bbox[5] - godot_bbox[4]),
    )

    with open(glb_path, "rb") as f:
        data = f.read()
    chunk_len = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + chunk_len])
    scene_nodes = gltf.get("scenes", [{}])[0].get("nodes", [])
    gltf_nodes = gltf.get("nodes", [])
    node_order = [
        (
            idx,
            gltf_nodes[n_idx].get("name"),
            [_fmt(v) for v in gltf_nodes[n_idx].get("translation", [0.0, 0.0, 0.0])],
        )
        for idx, n_idx in enumerate(scene_nodes)
    ]

    print(
        f"[{slug}] tris={total_tris} blender_bbox={blender_bbox} "
        f"godot_bbox={godot_bbox} godot_size={godot_size} gltf_nodes={node_order}"
    )
    for obj in objs:
        obj_tris = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
        slots = [(i, m.name) for i, m in enumerate(obj.data.materials)]
        loc = tuple(_fmt(c) for c in obj.location)
        godot_pivot = (_fmt(loc[0]), _fmt(loc[2]), _fmt(-loc[1]))
        print(
            f"  - obj={obj.name} tris={obj_tris} blender_pivot={loc} "
            f"godot_pivot={godot_pivot} slots={slots}"
        )


# ==============================================================================
# 4. STEEL PIPE ELBOW VALVE (1.0m x 0.72m x 1.0m modular corner, <= 2,800 tris)
# ==============================================================================
def build_steel_pipe_elbow_valve(output_dir: Path) -> Path:
    """Build flanged 0.16m diam 90-deg pipe elbow (+X -> Godot +Z) with gate valve & gauge."""
    clean_scene()
    mats = _create_shared_materials()

    # Slots: [0: painted_metal, 1: steel, 2: brass, 3: safety_red, 4: glass]
    m_paint = 0
    m_steel = 1
    m_brass = 2
    m_red = 3
    m_glass = 4

    bm = bmesh.new()

    pipe_z = 0.16
    r_pipe = 0.080
    r_bore = 0.062
    bend_r = 0.240
    arc_center = Vector((bend_r, -bend_r, pipe_z))
    up_z = Vector((0.0, 0.0, 1.0))

    # 1. Continuous 90-deg pipe sweep with recessed hollow bores at +X (X=0.50) and -Y (Y=-0.50)
    stations: list[tuple[Vector, Vector, Vector, float]] = [
        (Vector((0.420, 0.0, pipe_z)), Vector((0.0, 1.0, 0.0)), up_z, r_bore),
        (Vector((0.500, 0.0, pipe_z)), Vector((0.0, 1.0, 0.0)), up_z, r_bore),
        (Vector((0.500, 0.0, pipe_z)), Vector((0.0, 1.0, 0.0)), up_z, r_pipe),
        (Vector((0.240, 0.0, pipe_z)), Vector((0.0, 1.0, 0.0)), up_z, r_pipe),
    ]

    arc_steps = 6
    for i in range(1, arc_steps):
        ang = math.radians(90.0 + 90.0 * float(i) / float(arc_steps))
        radial_out = Vector((math.cos(ang), math.sin(ang), 0.0))
        pt = arc_center + radial_out * bend_r
        stations.append((pt, radial_out, up_z, r_pipe))

    stations.extend(
        [
            (Vector((0.0, -0.240, pipe_z)), Vector((-1.0, 0.0, 0.0)), up_z, r_pipe),
            (Vector((0.0, -0.500, pipe_z)), Vector((-1.0, 0.0, 0.0)), up_z, r_pipe),
            (Vector((0.0, -0.500, pipe_z)), Vector((-1.0, 0.0, 0.0)), up_z, r_bore),
            (Vector((0.0, -0.420, pipe_z)), Vector((-1.0, 0.0, 0.0)), up_z, r_bore),
        ]
    )
    _add_sweep_tube_bm(
        bm,
        stations,
        radial_segments=14,
        mat_idx=m_paint,
        cap_start=True,
        cap_end=True,
    )

    # 2. Bolted hollow circular end flanges at +X (X=0.50) and -Y (Y=-0.50, Godot +Z)
    flange_r = 0.145
    gasket_r = 0.104
    bolt_ring_r = 0.122

    # +X flange (hollow annular rings leaving pipe bore open!)
    _add_annular_ring_bm(
        bm,
        Vector((0.435, 0.0, pipe_z)),
        Vector((0.464, 0.0, pipe_z)),
        r_inner=r_pipe - 0.002,
        r_outer=0.098,
        segments=14,
        mat_idx=m_paint,
    )
    _add_annular_ring_bm(
        bm,
        Vector((0.464, 0.0, pipe_z)),
        Vector((0.492, 0.0, pipe_z)),
        r_inner=r_pipe - 0.002,
        r_outer=flange_r,
        segments=16,
        mat_idx=m_steel,
    )
    _add_annular_ring_bm(
        bm,
        Vector((0.492, 0.0, pipe_z)),
        Vector((0.500, 0.0, pipe_z)),
        r_inner=r_pipe - 0.002,
        r_outer=gasket_r,
        segments=14,
        mat_idx=m_steel,
    )
    for b_idx in range(8):
        ang = 2.0 * math.pi * float(b_idx) / 8.0 + math.pi / 8.0
        by = bolt_ring_r * math.cos(ang)
        bz = pipe_z + bolt_ring_r * math.sin(ang)
        _add_cylinder_bm(
            bm,
            Vector((0.456, by, bz)),
            Vector((0.499, by, bz)),
            r0=0.011,
            segments=6,
            mat_idx=m_steel,
        )

    # -Y (Godot +Z) flange (hollow annular rings leaving pipe bore open!)
    _add_annular_ring_bm(
        bm,
        Vector((0.0, -0.435, pipe_z)),
        Vector((0.0, -0.464, pipe_z)),
        r_inner=r_pipe - 0.002,
        r_outer=0.098,
        segments=14,
        mat_idx=m_paint,
    )
    _add_annular_ring_bm(
        bm,
        Vector((0.0, -0.464, pipe_z)),
        Vector((0.0, -0.492, pipe_z)),
        r_inner=r_pipe - 0.002,
        r_outer=flange_r,
        segments=16,
        mat_idx=m_steel,
    )
    _add_annular_ring_bm(
        bm,
        Vector((0.0, -0.492, pipe_z)),
        Vector((0.0, -0.500, pipe_z)),
        r_inner=r_pipe - 0.002,
        r_outer=gasket_r,
        segments=14,
        mat_idx=m_steel,
    )
    for b_idx in range(8):
        ang = 2.0 * math.pi * float(b_idx) / 8.0 + math.pi / 8.0
        bx = bolt_ring_r * math.cos(ang)
        bz = pipe_z + bolt_ring_r * math.sin(ang)
        _add_cylinder_bm(
            bm,
            Vector((bx, -0.456, bz)),
            Vector((bx, -0.499, bz)),
            r0=0.011,
            segments=6,
            mat_idx=m_steel,
        )

    # 3. Heavy floor foot saddle at elbow crown touching min_z = 0.0
    crown_xy = arc_center + Vector((-math.sqrt(0.5), math.sqrt(0.5), 0.0)) * bend_r
    cx, cy = crown_xy.x, crown_xy.y  # ~ (0.0703, -0.0703)
    diag_rot = Matrix.Rotation(math.radians(-45.0), 3, "Z")

    # Anchor baseplate (Z: 0.000 .. 0.022)
    _add_oriented_box_bm(
        bm,
        center=Vector((cx, cy, 0.011)),
        size=(0.22, 0.22, 0.022),
        rot_matrix=diag_rot,
        mat_idx=m_paint,
        chamfer=0.0,
    )
    # Saddle pedestal + cradle neck (Z: 0.022 .. 0.112)
    _add_oriented_box_bm(
        bm,
        center=Vector((cx, cy, 0.066)),
        size=(0.13, 0.15, 0.090),
        rot_matrix=diag_rot,
        mat_idx=m_paint,
        chamfer=0.0,
    )
    # 4 corner anchor bolts on foot saddle
    for sx in (-0.082, 0.082):
        for sy in (-0.082, 0.082):
            off = diag_rot @ Vector((sx, sy, 0.0))
            _add_cylinder_bm(
                bm,
                Vector((cx + off.x, cy + off.y, 0.022)),
                Vector((cx + off.x, cy + off.y, 0.040)),
                r0=0.012,
                segments=6,
                mat_idx=m_steel,
            )

    # 4. Vertical valve bonnet on elbow crown + chunky safety-red 5-spoke handwheel (top Z=0.720)
    # Forged valve body sleeve rising around elbow crown
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.160)),
        Vector((cx, cy, 0.285)),
        r0=0.086,
        r1=0.086,
        segments=14,
        mat_idx=m_paint,
    )
    # Mating bonnet flanges + 6 hex bolts
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.285)),
        Vector((cx, cy, 0.312)),
        r0=0.122,
        r1=0.122,
        segments=14,
        mat_idx=m_paint,
    )
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.312)),
        Vector((cx, cy, 0.340)),
        r0=0.122,
        r1=0.122,
        segments=14,
        mat_idx=m_steel,
    )
    for b_idx in range(6):
        ang = 2.0 * math.pi * float(b_idx) / 6.0
        bx = cx + 0.100 * math.cos(ang)
        by = cy + 0.100 * math.sin(ang)
        _add_cylinder_bm(
            bm,
            Vector((bx, by, 0.278)),
            Vector((bx, by, 0.350)),
            r0=0.010,
            segments=6,
            mat_idx=m_steel,
        )

    # Tapered bonnet neck + brass packing gland + steel gland nut + valve stem
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.340)),
        Vector((cx, cy, 0.480)),
        r0=0.076,
        r1=0.052,
        segments=12,
        mat_idx=m_paint,
    )
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.480)),
        Vector((cx, cy, 0.516)),
        r0=0.044,
        r1=0.044,
        segments=12,
        mat_idx=m_brass,
    )
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.516)),
        Vector((cx, cy, 0.548)),
        r0=0.036,
        r1=0.036,
        segments=6,
        mat_idx=m_steel,
    )
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.548)),
        Vector((cx, cy, 0.675)),
        r0=0.016,
        r1=0.016,
        segments=10,
        mat_idx=m_steel,
    )

    # Chunky 5-spoke safety-red handwheel centered at Z = 0.688 (rim top ~0.706, top locknut = 0.720)
    wheel_z = 0.688
    wheel_r = 0.132
    _add_torus_bm(
        bm,
        center=Vector((cx, cy, wheel_z)),
        major_radius=wheel_r,
        minor_radius=0.018,
        major_segments=14,
        minor_segments=6,
        mat_idx=m_red,
    )
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.668)),
        Vector((cx, cy, 0.706)),
        r0=0.034,
        r1=0.032,
        segments=10,
        mat_idx=m_red,
    )
    for s_idx in range(5):
        ang = 2.0 * math.pi * float(s_idx) / 5.0
        p0 = Vector((cx + 0.024 * math.cos(ang), cy + 0.024 * math.sin(ang), wheel_z))
        p1 = Vector((cx + (wheel_r - 0.008) * math.cos(ang), cy + (wheel_r - 0.008) * math.sin(ang), wheel_z))
        _add_strut_bm(bm, p0, p1, width=0.022, thickness=0.018, mat_idx=m_red, chamfer=0.0)

    # Top steel stem locknut reaching Godot Y = 0.720
    _add_cylinder_bm(
        bm,
        Vector((cx, cy, 0.706)),
        Vector((cx, cy, 0.720)),
        r0=0.020,
        r1=0.018,
        segments=6,
        mat_idx=m_steel,
    )

    # 5. Side-mounted tarnished_brass pressure gauge with glass face on +X leg (X=0.32)
    gx, gy = 0.320, -0.042
    _add_cylinder_bm(
        bm,
        Vector((gx, gy, 0.210)),
        Vector((gx, gy, 0.265)),
        r0=0.020,
        r1=0.020,
        segments=10,
        mat_idx=m_brass,
    )
    _add_cylinder_bm(
        bm,
        Vector((gx, gy, 0.265)),
        Vector((gx, gy, 0.295)),
        r0=0.025,
        r1=0.025,
        segments=6,
        mat_idx=m_brass,
    )
    _add_cylinder_bm(
        bm,
        Vector((gx, gy, 0.295)),
        Vector((gx, gy, 0.340)),
        r0=0.014,
        r1=0.014,
        segments=8,
        mat_idx=m_brass,
    )
    _add_cylinder_bm(
        bm,
        Vector((gx, gy + 0.012, 0.340)),
        Vector((gx, -0.088, 0.340)),
        r0=0.016,
        r1=0.016,
        segments=8,
        mat_idx=m_brass,
    )
    # Cylindrical brass gauge housing (dial faces -Y = Godot +Z)
    gauge_z = 0.345
    _add_cylinder_bm(
        bm,
        Vector((gx, -0.086, gauge_z)),
        Vector((gx, -0.120, gauge_z)),
        r0=0.056,
        r1=0.056,
        segments=16,
        mat_idx=m_brass,
    )
    # Brass bezel frame (4 segmented ring arcs / raised rim via outer tube ring)
    bezel_r_out = 0.058
    bezel_r_in = 0.048
    bezel_ring: list[tuple[Vector, Vector, Vector, float]] = []
    # Build chunky bezel ring with 16-segment annular face
    b_segs = 16
    v_front_out: list[bmesh.types.BMVert] = []
    v_front_in: list[bmesh.types.BMVert] = []
    v_back_out: list[bmesh.types.BMVert] = []
    v_back_in: list[bmesh.types.BMVert] = []
    for k in range(b_segs):
        ang = 2.0 * math.pi * float(k) / float(b_segs)
        ca, sa = math.cos(ang), math.sin(ang)
        v_front_out.append(bm.verts.new((gx + bezel_r_out * ca, -0.128, gauge_z + bezel_r_out * sa)))
        v_front_in.append(bm.verts.new((gx + bezel_r_in * ca, -0.128, gauge_z + bezel_r_in * sa)))
        v_back_out.append(bm.verts.new((gx + bezel_r_out * ca, -0.118, gauge_z + bezel_r_out * sa)))
        v_back_in.append(bm.verts.new((gx + bezel_r_in * ca, -0.118, gauge_z + bezel_r_in * sa)))
    for k in range(b_segs):
        kn = (k + 1) % b_segs
        for quad in (
            (v_front_out[k], v_front_in[k], v_front_in[kn], v_front_out[kn]),
            (v_back_out[k], v_back_out[kn], v_front_out[kn], v_front_out[k]),
            (v_front_in[k], v_back_in[k], v_back_in[kn], v_front_in[kn]),
            (v_back_in[k], v_back_out[k], v_back_out[kn], v_back_in[kn]),
        ):
            f = bm.faces.new(quad)
            f.material_index = m_brass

    # Recessed dial plate (brass inner ring + steel dial + safety_red needle) + front glass lens
    _add_cylinder_bm(
        bm,
        Vector((gx, -0.118, gauge_z)),
        Vector((gx, -0.121, gauge_z)),
        r0=0.048,
        r1=0.048,
        segments=16,
        mat_idx=m_steel,
    )
    _add_cylinder_bm(
        bm,
        Vector((gx, -0.121, gauge_z)),
        Vector((gx, -0.1235, gauge_z)),
        r0=0.008,
        r1=0.008,
        segments=8,
        mat_idx=m_brass,
    )
    _add_strut_bm(
        bm,
        Vector((gx - 0.010, -0.1225, gauge_z - 0.010)),
        Vector((gx + 0.032, -0.1225, gauge_z + 0.032)),
        width=0.008,
        thickness=0.003,
        mat_idx=m_red,
    )
    _add_cylinder_bm(
        bm,
        Vector((gx, -0.125, gauge_z)),
        Vector((gx, -0.127, gauge_z)),
        r0=0.048,
        r1=0.048,
        segments=16,
        mat_idx=m_glass,
    )

    obj = _finalize_bmesh_object(
        "steel_pipe_elbow_valve",
        bm,
        [
            mats["painted_metal"],
            mats["steel"],
            mats["brass"],
            mats["safety_red"],
            mats["glass"],
        ],
    )
    out_path = output_dir / "steel_pipe_elbow_valve.glb"
    export_godot_glb(out_path, export_animations=False, apply_modifiers=True, save_blend=False)
    _inspect_and_report("steel_pipe_elbow_valve", [obj], out_path)
    return out_path


# ==============================================================================
# 5. ELECTRICAL PANEL OPENABLE (0.75m W x 1.05m H x 0.28m D, <= 3,000 tris)
# ==============================================================================
def build_electrical_panel_openable(output_dir: Path) -> Path:
    """Build wall-mounted hollow NEMA cabinet + separate hinged door object."""
    clean_scene()
    mats = _create_shared_materials()

    # ----- Object 0: cabinet (Blender origin (0, 0, 0), back flush at Y = 0.0) -----
    # Slots: [0: painted_metal, 1: steel, 2: brass, 3: rubber_dark, 4: safety_red]
    c_paint = 0
    c_steel = 1
    c_brass = 2
    c_rubber = 3
    c_red = 4

    bm_cab = bmesh.new()

    box_x = 0.365  # Main box X[-0.365, +0.365]; rear mounting ears extend to +/-0.375 (0.75m W)
    wall_t = 0.020
    z_bot = 0.015  # Conduit glands sit in [0.000, 0.015] and [1.035, 1.050]
    z_top = 1.035
    y_front = -0.260

    # Outer hollow NEMA cabinet shell (back inset 4mm so rear mounting straps sit cleanly at Y=0.0)
    _add_box_bm(bm_cab, (-box_x, -wall_t, z_bot), (box_x, -0.004, z_top), c_paint)
    _add_box_bm(bm_cab, (-box_x, y_front, z_bot), (-box_x + wall_t, -wall_t, z_top), c_paint)
    _add_box_bm(bm_cab, (box_x - wall_t, y_front, z_bot), (box_x, -wall_t, z_top), c_paint)
    _add_box_bm(
        bm_cab,
        (-box_x + wall_t, y_front, z_bot),
        (box_x - wall_t, -wall_t, z_bot + wall_t),
        c_paint,
    )
    _add_box_bm(
        bm_cab,
        (-box_x + wall_t, y_front, z_top - wall_t),
        (box_x - wall_t, -wall_t, z_top),
        c_paint,
    )

    # Inward front sealing lip framing the open cavity
    lip_w = 0.014
    lip_d = 0.014
    _add_box_bm(
        bm_cab,
        (-box_x + wall_t, y_front, z_bot + wall_t),
        (-box_x + wall_t + lip_w, y_front + lip_d, z_top - wall_t),
        c_paint,
    )
    _add_box_bm(
        bm_cab,
        (box_x - wall_t - lip_w, y_front, z_bot + wall_t),
        (box_x - wall_t, y_front + lip_d, z_top - wall_t),
        c_paint,
    )
    _add_box_bm(
        bm_cab,
        (-box_x + wall_t + lip_w, y_front, z_bot + wall_t),
        (box_x - wall_t - lip_w, y_front + lip_d, z_bot + wall_t + lip_w),
        c_paint,
    )
    _add_box_bm(
        bm_cab,
        (-box_x + wall_t + lip_w, y_front, z_top - wall_t - lip_w),
        (box_x - wall_t - lip_w, y_front + lip_d, z_top - wall_t),
        c_paint,
    )

    # 4 Rear wall-mounting flange ears flush at Blender Y = 0.0 (zero coplanar overlap)
    for sign_x in (-1.0, 1.0):
        ex0 = -0.375 if sign_x < 0.0 else 0.315
        ex1 = -0.315 if sign_x < 0.0 else 0.375
        bx = sign_x * 0.362
        for ez0, ez1 in ((0.035, 0.125), (0.925, 1.015)):
            _add_box_bm(bm_cab, (ex0, -0.008, ez0), (ex1, 0.0, ez1), c_steel)
            _add_cylinder_bm(
                bm_cab,
                Vector((bx, -0.016, 0.5 * (ez0 + ez1))),
                Vector((bx, -0.008, 0.5 * (ez0 + ez1))),
                r0=0.008,
                segments=6,
                mat_idx=c_steel,
            )

    # Top & bottom steel conduit gland collars (Z in [0.000, 0.015] and [1.035, 1.050])
    for gx in (-0.18, 0.0, 0.18):
        # Top gland
        _add_cylinder_bm(
            bm_cab,
            Vector((gx, -0.13, z_top)),
            Vector((gx, -0.13, 1.044)),
            r0=0.028,
            segments=6,
            mat_idx=c_steel,
        )
        _add_cylinder_bm(
            bm_cab,
            Vector((gx, -0.13, 1.044)),
            Vector((gx, -0.13, 1.050)),
            r0=0.020,
            segments=8,
            mat_idx=c_steel,
        )
        _add_cylinder_bm(
            bm_cab,
            Vector((gx, -0.13, 1.048)),
            Vector((gx, -0.13, 1.050)),
            r0=0.013,
            segments=8,
            mat_idx=c_rubber,
        )
        # Bottom gland
        _add_cylinder_bm(
            bm_cab,
            Vector((gx, -0.13, z_bot)),
            Vector((gx, -0.13, 0.006)),
            r0=0.028,
            segments=6,
            mat_idx=c_steel,
        )
        _add_cylinder_bm(
            bm_cab,
            Vector((gx, -0.13, 0.006)),
            Vector((gx, -0.13, 0.000)),
            r0=0.020,
            segments=8,
            mat_idx=c_steel,
        )
        _add_cylinder_bm(
            bm_cab,
            Vector((gx, -0.13, 0.002)),
            Vector((gx, -0.13, 0.000)),
            r0=0.013,
            segments=8,
            mat_idx=c_rubber,
        )

    # Cabinet-side interlocking hinge knuckles at (-0.365, -0.260) matching door hinges
    for hz in (0.18, 0.87):
        for dz0, dz1 in ((-0.036, -0.015), (0.015, 0.036)):
            _add_cylinder_bm(
                bm_cab,
                Vector((-0.365, -0.260, hz + dz0)),
                Vector((-0.365, -0.260, hz + dz1)),
                r0=0.009,
                segments=8,
                mat_idx=c_steel,
            )

    # Interior sub-panel mounting plate
    _add_box_bm(bm_cab, (-0.315, -0.032, 0.080), (0.315, -0.020, 0.970), c_paint)

    # 2 Interior horizontal steel DIN mounting rails
    for rz in (0.47, 0.70):
        _add_box_bm(bm_cab, (-0.28, -0.044, rz - 0.018), (0.28, -0.032, rz + 0.018), c_steel)
        _add_box_bm(bm_cab, (-0.28, -0.048, rz - 0.022), (0.28, -0.044, rz - 0.012), c_steel)
        _add_box_bm(bm_cab, (-0.28, -0.048, rz + 0.012), (0.28, -0.044, rz + 0.022), c_steel)

    # Row of 8 chunky breaker modules on upper DIN rail (Z=0.70) with safety-red toggles
    for i in range(8):
        bx_c = -0.217 + float(i) * 0.062
        _add_box_bm(
            bm_cab,
            (bx_c - 0.026, -0.112, 0.640),
            (bx_c + 0.026, -0.046, 0.760),
            c_rubber,
        )
        # Stepped front breaker collar + safety_red toggle lever
        _add_box_bm(
            bm_cab,
            (bx_c - 0.018, -0.124, 0.675),
            (bx_c + 0.018, -0.112, 0.725),
            c_rubber,
        )
        # Alternate 2 breakers tripped downward for industrial detail
        trig_z0, trig_z1 = (0.680, 0.702) if i in (2, 5) else (0.700, 0.722)
        _add_box_bm(
            bm_cab,
            (bx_c - 0.012, -0.142, trig_z0),
            (bx_c + 0.012, -0.124, trig_z1),
            c_red,
        )

    # Lower DIN rail: main rotary disconnect switch + 2 auxiliary relay blocks
    _add_box_bm(bm_cab, (0.10, -0.115, 0.415), (0.24, -0.046, 0.525), c_rubber)
    _add_cylinder_bm(
        bm_cab,
        Vector((0.17, -0.115, 0.470)),
        Vector((0.17, -0.130, 0.470)),
        r0=0.032,
        segments=10,
        mat_idx=c_red,
    )
    _add_box_bm(bm_cab, (0.158, -0.148, 0.440), (0.182, -0.128, 0.500), c_red)

    # Small inset analog panel meter (upper-left inside cabinet)
    mx, mz = -0.18, 0.875
    _add_box_bm(bm_cab, (mx - 0.070, -0.092, mz - 0.055), (mx + 0.070, -0.032, mz + 0.055), c_rubber)
    _add_box_bm(bm_cab, (mx - 0.054, -0.095, mz - 0.040), (mx + 0.054, -0.088, mz + 0.040), c_steel)
    _add_strut_bm(
        bm_cab,
        Vector((mx - 0.004, -0.098, mz - 0.025)),
        Vector((mx + 0.028, -0.098, mz + 0.024)),
        width=0.005,
        thickness=0.002,
        mat_idx=c_red,
    )

    # 2 Horizontal brass busbars + rubber standoff insulators + steel terminal screws
    for bz in (0.215, 0.305):
        for sx in (-0.20, 0.20):
            _add_box_bm(bm_cab, (sx - 0.020, -0.058, bz - 0.020), (sx + 0.020, -0.032, bz + 0.020), c_rubber)
        _add_box_bm(bm_cab, (-0.26, -0.072, bz - 0.016), (0.26, -0.058, bz + 0.016), c_brass)
        for lx in (-0.18, -0.06, 0.06, 0.18):
            _add_cylinder_bm(
                bm_cab,
                Vector((lx, -0.080, bz)),
                Vector((lx, -0.072, bz)),
                r0=0.007,
                segments=6,
                mat_idx=c_steel,
            )

    # Brass grounding terminal block near bottom-left
    _add_box_bm(bm_cab, (-0.27, -0.060, 0.115), (-0.15, -0.032, 0.145), c_brass)

    cab_obj = _finalize_bmesh_object(
        "cabinet",
        bm_cab,
        [
            mats["painted_metal"],
            mats["steel"],
            mats["brass"],
            mats["rubber_dark"],
            mats["safety_red"],
        ],
        location=(0.0, 0.0, 0.0),
    )

    # ----- Object 1: door (Blender pivot (-0.365, -0.260, 0.0) -> Godot (-0.365, 0.0, 0.260)) -----
    # Slots: [0: painted_metal, 1: steel, 2: rubber_dark]
    d_paint = 0
    d_steel = 1
    d_rubber = 2

    bm_door = bmesh.new()

    # Main beveled door sheet (local X in [0.000, 0.730], Z in [0.020, 1.030], Y in [-0.014, -0.003])
    _add_box_bm(bm_door, (0.000, -0.014, 0.020), (0.730, -0.003, 1.030), d_paint, chamfer=0.003)

    # Stamped raised inner door panel (local Y in [-0.019, -0.014])
    _add_box_bm(bm_door, (0.065, -0.019, 0.085), (0.665, -0.014, 0.965), d_paint, chamfer=0.003)

    # Rubber perimeter gasket lip on back edge (local Y in [-0.004, 0.000])
    gx0, gx1 = 0.012, 0.720
    gz0, gz1 = 0.028, 1.022
    gw = 0.014
    _add_box_bm(bm_door, (gx0, -0.004, gz0), (gx0 + gw, 0.0, gz1), d_rubber)
    _add_box_bm(bm_door, (gx1 - gw, -0.004, gz0), (gx1, 0.0, gz1), d_rubber)
    _add_box_bm(bm_door, (gx0 + gw, -0.004, gz0), (gx1 - gw, 0.0, gz0 + gw), d_rubber)
    _add_box_bm(bm_door, (gx0 + gw, -0.004, gz1 - gw), (gx1 - gw, 0.0, gz1), d_rubber)

    # 6 Cooling louver slats stamped on lower panel face
    for idx in range(6):
        lz = 0.165 + float(idx) * 0.042
        _add_box_bm(
            bm_door,
            (0.165, -0.024, lz),
            (0.565, -0.019, lz + 0.020),
            d_paint,
        )

    # Right-side quarter-turn steel latch handle (local X = 0.675, Z = 0.525, Y >= -0.025)
    _add_box_bm(bm_door, (0.648, -0.022, 0.475), (0.702, -0.014, 0.575), d_steel)
    _add_cylinder_bm(
        bm_door,
        Vector((0.675, -0.022, 0.525)),
        Vector((0.675, -0.025, 0.525)),
        r0=0.013,
        segments=10,
        mat_idx=d_steel,
    )
    _add_box_bm(bm_door, (0.666, -0.025, 0.452), (0.684, -0.020, 0.538), d_steel)

    # 2 Left barrel hinges along local X = 0.0 (matching cabinet hinge knuckles at Z=0.18, 0.87)
    for hz in (0.18, 0.87):
        _add_cylinder_bm(
            bm_door,
            Vector((0.0, 0.0, hz - 0.014)),
            Vector((0.0, 0.0, hz + 0.014)),
            r0=0.009,
            segments=8,
            mat_idx=d_steel,
        )
        _add_cylinder_bm(
            bm_door,
            Vector((0.0, 0.0, hz - 0.040)),
            Vector((0.0, 0.0, hz + 0.040)),
            r0=0.004,
            segments=6,
            mat_idx=d_steel,
        )
        _add_box_bm(bm_door, (-0.002, -0.014, hz - 0.014), (0.032, -0.002, hz + 0.014), d_steel)

    door_obj = _finalize_bmesh_object(
        "door",
        bm_door,
        [
            mats["painted_metal"],
            mats["steel"],
            mats["rubber_dark"],
        ],
        location=(-0.365, -0.260, 0.0),
    )

    out_path = output_dir / "electrical_panel_openable.glb"
    export_godot_glb(out_path, export_animations=False, apply_modifiers=True, save_blend=False)
    _inspect_and_report("electrical_panel_openable", [cab_obj, door_obj], out_path)
    return out_path


# ==============================================================================
# 6. EMERGENCY BUTTON (0.18m W x 0.22m H x 0.14m D, <= 1,400 tris)
# ==============================================================================
def build_emergency_button(output_dir: Path) -> Path:
    """Build yellow E-stop wall housing + separate articulated mushroom button cap."""
    clean_scene()
    mats = _create_shared_materials()

    # ----- Object: housing (Blender origin (0, 0, 0), back flush at Y = 0.0) -----
    # Slots: [0: safety_yellow, 1: steel]
    h_yellow = 0
    h_steel = 1

    bm_hous = bmesh.new()

    # Enclosure body & chamfered front lid (back inset 4mm so rear tabs sit cleanly at Y=0.0)
    _add_box_bm(bm_hous, (-0.084, -0.065, 0.020), (0.084, -0.004, 0.200), h_yellow, chamfer=0.004)
    _add_box_bm(bm_hous, (-0.088, -0.090, 0.018), (0.088, -0.062, 0.202), h_yellow, chamfer=0.006)

    # Raised yellow circular legend ring centered at button axis (0.0, -0.090, 0.110)
    _add_cylinder_bm(
        bm_hous,
        Vector((0.0, -0.088, 0.110)),
        Vector((0.0, -0.092, 0.110)),
        r0=0.048,
        r1=0.045,
        segments=16,
        mat_idx=h_yellow,
    )

    # 4 Rear mounting flange tabs flush at Y = 0.0 reaching X = +/-0.090 (0.18m W)
    for sign_x in (-1.0, 1.0):
        tx0 = -0.090 if sign_x < 0.0 else 0.055
        tx1 = -0.055 if sign_x < 0.0 else 0.090
        for tz0, tz1 in ((0.034, 0.056), (0.164, 0.186)):
            _add_box_bm(bm_hous, (tx0, -0.008, tz0), (tx1, 0.0, tz1), h_steel)

    # 4 Corner hex screws on lid face
    for sx in (-0.068, 0.068):
        for sz in (0.036, 0.184):
            _add_cylinder_bm(
                bm_hous,
                Vector((sx, -0.088, sz)),
                Vector((sx, -0.095, sz)),
                r0=0.0065,
                segments=6,
                mat_idx=h_steel,
            )

    # Top & bottom steel conduit gland collars (Z in [0.000, 0.020] and [0.200, 0.220])
    # Top gland
    _add_cylinder_bm(
        bm_hous,
        Vector((0.0, -0.034, 0.200)),
        Vector((0.0, -0.034, 0.212)),
        r0=0.018,
        segments=6,
        mat_idx=h_steel,
    )
    _add_cylinder_bm(
        bm_hous,
        Vector((0.0, -0.034, 0.212)),
        Vector((0.0, -0.034, 0.220)),
        r0=0.013,
        segments=12,
        mat_idx=h_steel,
    )
    # Bottom gland
    _add_cylinder_bm(
        bm_hous,
        Vector((0.0, -0.034, 0.020)),
        Vector((0.0, -0.034, 0.008)),
        r0=0.018,
        segments=6,
        mat_idx=h_steel,
    )
    _add_cylinder_bm(
        bm_hous,
        Vector((0.0, -0.034, 0.008)),
        Vector((0.0, -0.034, 0.000)),
        r0=0.013,
        segments=12,
        mat_idx=h_steel,
    )

    # Protective curved U-shroud steel guard around plunger face (Godot Z in [0.09, 0.14])
    _add_curved_shroud_bm(
        bm_hous,
        center_xz=(0.0, 0.110),
        y_back=-0.090,
        y_front=-0.140,
        r_inner=0.055,
        r_outer=0.064,
        angle_start_deg=-30.0,
        angle_end_deg=210.0,
        arc_segments=12,
        mat_idx=h_steel,
    )
    # Two side shroud mounting feet bolted onto lid face
    for sign_x in (-1.0, 1.0):
        fx0 = -0.074 if sign_x < 0.0 else 0.056
        fx1 = -0.056 if sign_x < 0.0 else 0.074
        _add_box_bm(bm_hous, (fx0, -0.096, 0.076), (fx1, -0.088, 0.112), h_steel, chamfer=0.001)

    housing_obj = _finalize_bmesh_object(
        "housing",
        bm_hous,
        [mats["safety_yellow"], mats["steel"]],
        location=(0.0, 0.0, 0.0),
    )

    # ----- Object: button_cap (Blender pivot (0.0, -0.09, 0.11) -> Godot (0.0, 0.11, 0.09)) -----
    # Slots: [0: safety_red, 1: brass]
    b_red = 0
    b_brass = 1

    bm_cap = bmesh.new()

    # Brass collar ring at plunger base (local Y in [-0.012, 0.000])
    _add_cylinder_bm(
        bm_cap,
        Vector((0.0, 0.0, 0.0)),
        Vector((0.0, -0.012, 0.0)),
        r0=0.032,
        r1=0.028,
        segments=16,
        mat_idx=b_brass,
    )
    _add_cylinder_bm(
        bm_cap,
        Vector((0.0, -0.012, 0.0)),
        Vector((0.0, -0.022, 0.0)),
        r0=0.018,
        r1=0.018,
        segments=12,
        mat_idx=b_brass,
    )

    # Chunky mushroom-head safety_red E-stop cap (diam 0.085m, local Y in [-0.050, -0.014])
    segs = 20
    profile_yr = [
        (-0.014, 0.0220),
        (-0.024, 0.0405),
        (-0.028, 0.0425),
        (-0.041, 0.0425),
        (-0.047, 0.0370),
        (-0.0495, 0.0200),
    ]
    rings: list[list[bmesh.types.BMVert]] = []
    for py, pr in profile_yr:
        ring: list[bmesh.types.BMVert] = []
        for k in range(segs):
            ang = 2.0 * math.pi * float(k) / float(segs)
            ring.append(bm_cap.verts.new((pr * math.cos(ang), py, pr * math.sin(ang))))
        rings.append(ring)

    for idx in range(len(rings) - 1):
        r0 = rings[idx]
        r1 = rings[idx + 1]
        for k in range(segs):
            kn = (k + 1) % segs
            face = bm_cap.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
            face.material_index = b_red

    # Back cap at Y=-0.014 and domed center apex at Y=-0.050
    f_back = bm_cap.faces.new(list(reversed(rings[0])))
    f_back.material_index = b_red

    apex = bm_cap.verts.new((0.0, -0.050, 0.0))
    top_ring = rings[-1]
    for k in range(segs):
        kn = (k + 1) % segs
        face = bm_cap.faces.new((top_ring[k], top_ring[kn], apex))
        face.material_index = b_red

    cap_obj = _finalize_bmesh_object(
        "button_cap",
        bm_cap,
        [mats["safety_red"], mats["brass"]],
        location=(0.0, -0.090, 0.110),
    )

    out_path = output_dir / "emergency_button.glb"
    export_godot_glb(out_path, export_animations=False, apply_modifiers=True, save_blend=False)
    _inspect_and_report("emergency_button", [housing_obj, cap_obj], out_path)
    return out_path


def main() -> None:
    """Entry point for Blender headless generation of all 3 workshop MEP control assets."""
    try:
        output_dir = _REPO_ROOT / "assets" / "models" / "props" / "factory_workshop"
        output_dir.mkdir(parents=True, exist_ok=True)
        build_steel_pipe_elbow_valve(output_dir)
        build_electrical_panel_openable(output_dir)
        build_emergency_button(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
