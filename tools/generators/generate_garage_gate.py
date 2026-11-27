"""Procedural generator for grounded sectional garage gate panel and frame meshes.

Run headless:
blender -b -P tools/generate_garage_gate.py
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPORT_PATH = os.path.join(PROJECT_ROOT, "props", "garage_gate", "garage_gate.glb")


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def set_weighted_normals(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    if hasattr(obj.data, "use_auto_smooth"):
        obj.data.use_auto_smooth = True
        obj.data.auto_smooth_angle = math.radians(60)
    mod = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    mod.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=mod.name)


def add_bm_box(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    z0: float,
    z1: float,
) -> None:
    v = [
        bm.verts.new((x0, y0, z0)),
        bm.verts.new((x1, y0, z0)),
        bm.verts.new((x1, y1, z0)),
        bm.verts.new((x0, y1, z0)),
        bm.verts.new((x0, y0, z1)),
        bm.verts.new((x1, y0, z1)),
        bm.verts.new((x1, y1, z1)),
        bm.verts.new((x0, y1, z1)),
    ]
    faces = [
        (v[0], v[3], v[2], v[1]),
        (v[4], v[5], v[6], v[7]),
        (v[0], v[1], v[5], v[4]),
        (v[2], v[3], v[7], v[6]),
        (v[3], v[0], v[4], v[7]),
        (v[1], v[2], v[6], v[5]),
    ]
    for f_verts in faces:
        bm.faces.new(f_verts)


def add_bm_x_cylinder(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    cy: float,
    cz: float,
    rad: float,
    segs: int = 12,
) -> None:
    r0 = []
    r1 = []
    for s in range(segs):
        ang = (2.0 * math.pi * s) / segs
        vy = cy + rad * math.cos(ang)
        vz = cz + rad * math.sin(ang)
        r0.append(bm.verts.new((x0, vy, vz)))
        r1.append(bm.verts.new((x1, vy, vz)))
    bm.faces.new(r0[::-1])
    bm.faces.new(r1)
    for s in range(segs):
        sn = (s + 1) % segs
        bm.faces.new((r0[s], r0[sn], r1[sn], r1[s]))


def apply_normalized_box_uv(bm: bmesh.types.BMesh, u_span: float, v_span: float) -> None:
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if ay >= ax and ay >= az:
                # Front/back faces: map full 3.0m width -> 0..1 U, 0.60m height -> 0..1 V
                u = (co.x + u_span * 0.5) / u_span
                v = co.z / v_span
            elif ax >= ay and ax >= az:
                u = (co.y + 0.5) / v_span
                v = co.z / v_span
            else:
                u = (co.x + u_span * 0.5) / u_span
                v = (co.y + 0.5) / v_span
            loop[uv_layer].uv = (u, v)


def build_slotted_panel() -> bpy.types.Object:
    width = 3.0
    depth = 0.05
    tooth_depth = 0.034  # Recessed 8mm per side so teeth never Z-fight with upper panel
    base_h = 0.56
    slot_h = 0.04
    num_slots = 7
    slot_w = 0.28

    post_w = (width - (num_slots * slot_w)) / (num_slots + 1)
    x_coords = [-width * 0.5]
    for _ in range(num_slots):
        x_coords.append(x_coords[-1] + post_w)
        x_coords.append(x_coords[-1] + slot_w)
    x_coords.append(width * 0.5)

    bm = bmesh.new()

    # Solid lower plate (0.0 -> 0.56m, full 0.05m depth)
    add_bm_box(
        bm,
        -width * 0.5,
        width * 0.5,
        -depth * 0.5,
        depth * 0.5,
        0.0,
        base_h,
    )

    # Interlocking top teeth on even indices (0.56 -> 0.60m, recessed 0.034m depth)
    for ix in range(len(x_coords) - 1):
        if ix % 2 == 0:
            add_bm_box(
                bm,
                x_coords[ix],
                x_coords[ix + 1],
                -tooth_depth * 0.5,
                tooth_depth * 0.5,
                base_h,
                base_h + slot_h,
            )

    # Side hinge brackets + steel roller wheels riding inside tracks (X = +/- 1.545m)
    for side in (-1.0, 1.0):
        x_edge = side * (width * 0.5)
        x_roller_in = side * 1.530
        x_roller_out = side * 1.555
        for rz in (0.05, 0.51):
            # Axle pin
            ax0 = min(x_edge, x_roller_out)
            ax1 = max(x_edge, x_roller_out)
            add_bm_x_cylinder(bm, ax0, ax1, 0.0, rz, 0.008, 10)
            # Roller wheel inside track
            rx0 = min(x_roller_in, x_roller_out)
            rx1 = max(x_roller_in, x_roller_out)
            add_bm_x_cylinder(bm, rx0, rx1, 0.0, rz, 0.022, 14)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for e in bm.edges:
        if e.calc_face_angle(0.0) > math.radians(60):
            e.smooth = False

    apply_normalized_box_uv(bm, width, base_h + slot_h)

    mesh = bpy.data.meshes.new("SM_GaragePanel")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("SM_GaragePanel", mesh)
    bpy.context.collection.objects.link(obj)
    set_weighted_normals(obj)
    return obj


def build_static_frame() -> bpy.types.Object:
    bm = bmesh.new()
    track_x_offset = 1.545
    track_w = 0.045
    track_d = 0.065
    v_height = 2.05
    radius = 0.35
    h_length = 2.40
    arc_steps = 10

    # 1. Left & Right perpendicular-swept tracks (no pinching at 90-deg bend)
    pts: list[Vector] = [Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, v_height))]
    for s in range(1, arc_steps + 1):
        ang = (math.pi * 0.5) * (s / arc_steps)
        py = radius * (1.0 - math.cos(ang))
        pz = v_height + radius * math.sin(ang)
        pts.append(Vector((0.0, py, pz)))
    pts.append(Vector((0.0, radius + h_length, v_height + radius)))

    # Compute smooth tangents and perpendicular normals in YZ plane
    normals: list[Vector] = []
    for idx in range(len(pts)):
        if idx == 0:
            tangent = (pts[1] - pts[0]).normalized()
        elif idx == len(pts) - 1:
            tangent = (pts[-1] - pts[-2]).normalized()
        else:
            tangent = (pts[idx + 1] - pts[idx - 1]).normalized()
        # Cross with +X gives perpendicular normal in YZ plane
        n_yz = tangent.cross(Vector((1.0, 0.0, 0.0))).normalized()
        normals.append(n_yz)

    for side in (-1.0, 1.0):
        cx = side * track_x_offset
        rings = []
        for idx, pt in enumerate(pts):
            n_vec = normals[idx] * (track_d * 0.5)
            p_front = pt - n_vec
            p_back = pt + n_vec
            ring = [
                bm.verts.new((cx - track_w * 0.5, p_front.y, p_front.z)),
                bm.verts.new((cx + track_w * 0.5, p_front.y, p_front.z)),
                bm.verts.new((cx + track_w * 0.5, p_back.y, p_back.z)),
                bm.verts.new((cx - track_w * 0.5, p_back.y, p_back.z)),
            ]
            rings.append(ring)
            if idx == 0:
                bm.faces.new(ring[::-1])
            elif idx == len(pts) - 1:
                bm.faces.new(ring)
            if idx > 0:
                prev = rings[idx - 1]
                for k in range(4):
                    kn = (k + 1) % 4
                    bm.faces.new((prev[k], prev[kn], ring[kn], ring[k]))

    # 2. Vertical Wall Mounting Jambs (ground tracks from Z=0 to Z=2.66m)
    for side in (-1.0, 1.0):
        jx = side * 1.545
        add_bm_box(bm, jx - 0.04, jx + 0.04, -0.065, -0.025, 0.0, 2.66)
        # Floor anchor foot plate
        add_bm_box(bm, jx - 0.06, jx + 0.06, -0.08, 0.04, 0.0, 0.02)

    # 3. Top Header Lintel Beam (connects L & R jambs across top of door opening)
    add_bm_box(bm, -1.60, 1.60, -0.065, 0.035, 2.46, 2.66)

    # 4. Torsion Bearing End-Plates & Center Bracket (physically hold torsion shaft at Y=0.08, Z=2.55)
    for bx in (-1.57, 0.0, 1.57):
        add_bm_box(bm, bx - 0.015, bx + 0.015, 0.02, 0.14, 2.47, 2.63)

    # 5. Torsion shaft + 2 torsion springs + 2 cable drums at Z = 2.55m, Y = 0.08m
    add_bm_x_cylinder(bm, -1.58, 1.58, 0.08, 2.55, 0.018, 10)
    add_bm_x_cylinder(bm, -0.85, -0.15, 0.08, 2.55, 0.045, 14)
    add_bm_x_cylinder(bm, 0.15, 0.85, 0.08, 2.55, 0.045, 14)
    add_bm_x_cylinder(bm, -1.52, -1.42, 0.08, 2.55, 0.075, 16)
    add_bm_x_cylinder(bm, 1.42, 1.52, 0.08, 2.55, 0.075, 16)

    # 6. Rear Horizontal Track Cross-Brace & Overhead Ceiling Hanger Struts
    rear_y = radius + h_length - 0.05
    track_top_z = v_height + radius
    add_bm_box(bm, -1.57, 1.57, rear_y - 0.025, rear_y + 0.025, track_top_z - 0.025, track_top_z + 0.025)
    for side in (-1.0, 1.0):
        hx = side * track_x_offset
        # Vertical ceiling hanger drop from Z=3.0m down to track
        add_bm_box(bm, hx - 0.018, hx + 0.018, rear_y - 0.018, rear_y + 0.018, track_top_z, 3.00)
        # Mid-span hanger strut
        add_bm_box(bm, hx - 0.018, hx + 0.018, 1.40 - 0.018, 1.40 + 0.018, track_top_z, 3.00)
        # Ceiling mounting plates
        add_bm_box(bm, hx - 0.05, hx + 0.05, rear_y - 0.05, rear_y + 0.05, 2.98, 3.00)
        add_bm_box(bm, hx - 0.05, hx + 0.05, 1.40 - 0.05, 1.40 + 0.05, 2.98, 3.00)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for e in bm.edges:
        if e.calc_face_angle(0.0) > math.radians(60):
            e.smooth = False

    apply_normalized_box_uv(bm, 2.0, 2.0)

    mesh = bpy.data.meshes.new("SM_GarageFrame")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("SM_GarageFrame", mesh)
    bpy.context.collection.objects.link(obj)
    set_weighted_normals(obj)
    return obj


if __name__ == "__main__":
    clear_scene()
    build_slotted_panel()
    build_static_frame()
    os.makedirs(os.path.dirname(EXPORT_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=EXPORT_PATH,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
    )
    print(f"Successfully generated {EXPORT_PATH}")
