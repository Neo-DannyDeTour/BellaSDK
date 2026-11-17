"""Procedural silhouette-traced hard-surface Colt Single Action Army generator.

Generates a 5-part articulated revolver (frame, 6-chamber fluted cylinder,
hammer, trigger, ejector rod) aligned with Blender +Y forward (Godot -Z) and
origin at the grip trigger web, bakes 2048x2048 Albedo / NormalGL / ORM maps
in Cycles, renders 3 review stills, and exports a rigged Godot 4 GLB.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bpy
import bmesh
import numpy as np
from mathutils import Euler, Matrix, Vector

from common.armature import add_bone, create_action, create_armature, push_action_to_nla
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material

# ---------------------------------------------------------------------------
# Key landmarks (meters) measured from leveled Colt SAA reference
# Origin (0, 0, 0) = grip hand point / trigger web
# Blender axes: +X Right (loading gate / ejector), +Y Forward (Godot -Z), +Z Up
# ---------------------------------------------------------------------------
BORE_Z = 0.032
CYL_Y_START = 0.0155
CYL_Y_END = 0.0565
CYL_Y_CENTER = 0.5 * (CYL_Y_START + CYL_Y_END)
CYL_Z_CENTER = 0.0190
CYL_LEN = CYL_Y_END - CYL_Y_START
CYL_RADIUS = 0.0205

BARREL_Y_START = 0.0620
BARREL_Y_END = 0.1840
EJECTOR_X = 0.0092
EJECTOR_Z = 0.0172

PIVOT_CYLINDER = Vector((0.0, CYL_Y_CENTER, CYL_Z_CENTER))
PIVOT_HAMMER = Vector((0.0, 0.0020, 0.0140))
PIVOT_TRIGGER = Vector((0.0, 0.0185, -0.0035))
PIVOT_EJECTOR = Vector((EJECTOR_X, 0.0640, EJECTOR_Z))


def _set_smooth_by_angle(obj: bpy.types.Object, angle_deg: float = 35.0) -> None:
    """Apply smooth shading with sharp edge preservation (Blender 5.x safe)."""
    mesh = obj.data
    for poly in mesh.polygons:
        poly.use_smooth = True
    mod = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    mod.keep_sharp = True
    # Mark edges sharper than angle_deg as sharp
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.edges.ensure_lookup_table()
    thresh = math.radians(angle_deg)
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            ang = edge.link_faces[0].normal.angle(edge.link_faces[1].normal, 0.0)
            edge.smooth = ang < thresh
        else:
            edge.smooth = False
    bm.to_mesh(mesh)
    bm.free()


def _add_bevel(obj: bpy.types.Object, width: float = 0.0005, segments: int = 2) -> None:
    """Add clamped hard-surface bevel modifier."""
    bev = obj.modifiers.new(name="Bevel", type="BEVEL")
    bev.width = width
    bev.segments = segments
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(32.0)
    bev.harden_normals = False
    bev.use_clamp_overlap = True


def _apply_modifiers(obj: bpy.types.Object) -> None:
    """Apply all modifiers cleanly on obj."""
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def _extrude_yz_profile(
    name: str,
    profile_yz: list[tuple[float, float]],
    half_width_x: float,
    x_offset: float = 0.0,
    bevel_width: float = 0.0005,
    bevel_segments: int = 2,
) -> bpy.types.Object:
    """Build a manifold solid by extruding a 2D (y, z) loop symmetrically along X."""
    bm = bmesh.new()
    verts_l = [bm.verts.new((x_offset - half_width_x, y, z)) for (y, z) in profile_yz]
    verts_r = [bm.verts.new((x_offset + half_width_x, y, z)) for (y, z) in profile_yz]
    bm.faces.new(list(reversed(verts_l)))
    bm.faces.new(verts_r)
    n = len(profile_yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((verts_l[i], verts_l[j], verts_r[j], verts_r[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if bevel_width > 0.0:
        _add_bevel(obj, width=bevel_width, segments=bevel_segments)
        _apply_modifiers(obj)
    _set_smooth_by_angle(obj, 36.0)
    return obj


def _assign_mat_to_all_faces(obj: bpy.types.Object, mat: bpy.types.Material) -> None:
    """Ensure obj has mat assigned to slot 0 and every face uses slot 0."""
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.material_index = 0


def _join_objects(objects: list[bpy.types.Object], name: str) -> bpy.types.Object:
    """Join a list of mesh objects preserving multi-material slots."""
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


# ---------------------------------------------------------------------------
# Part Builders
# ---------------------------------------------------------------------------
def build_barrel(mat_blued: bpy.types.Material, mat_case: bpy.types.Material) -> list[bpy.types.Object]:
    """Build tapered 4.75-inch Colt SAA barrel with chamfered muzzle bore and front sight."""
    bm = bmesh.new()
    segs = 32
    # Rings along Y: (y, r_outer)
    # Bore hole sits inside muzzle face
    rings_outer = [
        (BARREL_Y_START - 0.002, 0.0112),
        (BARREL_Y_START, 0.0114),
        (BARREL_Y_START + 0.007, 0.0113),
        (BARREL_Y_START + 0.010, 0.0104),
        (BARREL_Y_END - 0.002, 0.0088),
        (BARREL_Y_END, 0.0085),
    ]
    ring_verts = []
    for y_val, r_val in rings_outer:
        ring = [
            bm.verts.new((r_val * math.cos(2.0 * math.pi * i / segs), y_val, BORE_Z + r_val * math.sin(2.0 * math.pi * i / segs)))
            for i in range(segs)
        ]
        ring_verts.append(ring)

    # Cap breech
    bm.faces.new(list(reversed(ring_verts[0])))

    for k in range(len(ring_verts) - 1):
        r0 = ring_verts[k]
        r1 = ring_verts[k + 1]
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))

    # Muzzle crown + recessed bore (r = 0.0056)
    r_crown = 0.0063
    r_bore = 0.0055
    crown_ring = [
        bm.verts.new((r_crown * math.cos(2.0 * math.pi * i / segs), BARREL_Y_END + 0.0005, BORE_Z + r_crown * math.sin(2.0 * math.pi * i / segs)))
        for i in range(segs)
    ]
    bore_lip = [
        bm.verts.new((r_bore * math.cos(2.0 * math.pi * i / segs), BARREL_Y_END - 0.0005, BORE_Z + r_bore * math.sin(2.0 * math.pi * i / segs)))
        for i in range(segs)
    ]
    bore_deep = [
        bm.verts.new((r_bore * math.cos(2.0 * math.pi * i / segs), BARREL_Y_END - 0.024, BORE_Z + r_bore * math.sin(2.0 * math.pi * i / segs)))
        for i in range(segs)
    ]

    for r0, r1 in ((ring_verts[-1], crown_ring), (crown_ring, bore_lip), (bore_lip, bore_deep)):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm.faces.new(bore_deep)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Barrel")
    bm.to_mesh(mesh)
    bm.free()
    barrel_obj = bpy.data.objects.new("Barrel", mesh)
    bpy.context.collection.objects.link(barrel_obj)
    _set_smooth_by_angle(barrel_obj, 38.0)
    _assign_mat_to_all_faces(barrel_obj, mat_blued)

    # Quarter-moon front sight blade
    sight_profile = [
        (0.157, 0.0392),
        (0.163, 0.0430),
        (0.169, 0.0485),
        (0.174, 0.0498),
        (0.1765, 0.0482),
        (0.1775, 0.0435),
        (0.1775, 0.0392),
    ]
    sight_obj = _extrude_yz_profile(
        "FrontSight", sight_profile, half_width_x=0.0011, bevel_width=0.00025, bevel_segments=2
    )
    _assign_mat_to_all_faces(sight_obj, mat_blued)

    # Ejector housing shroud (right-under barrel, crescent/tubular profile)
    bm_eh = bmesh.new()
    eh_segs = 20
    r_eh = 0.0056
    eh_rings = [
        (BARREL_Y_START - 0.001, r_eh * 1.04),
        (BARREL_Y_START + 0.006, r_eh),
        (0.150, r_eh * 0.96),
        (0.157, r_eh * 0.88),
    ]
    eh_vrings = []
    for y_val, rv in eh_rings:
        ring = [
            bm_eh.verts.new((EJECTOR_X + rv * math.cos(2.0 * math.pi * i / eh_segs), y_val, EJECTOR_Z + rv * math.sin(2.0 * math.pi * i / eh_segs)))
            for i in range(eh_segs)
        ]
        eh_vrings.append(ring)
    bm_eh.faces.new(list(reversed(eh_vrings[0])))
    for k in range(len(eh_vrings) - 1):
        r0, r1 = eh_vrings[k], eh_vrings[k + 1]
        for i in range(eh_segs):
            j = (i + 1) % eh_segs
            bm_eh.faces.new((r0[i], r0[j], r1[j], r1[i]))
    # Front hollow cap for ejector rod
    r_inner = 0.0033
    inner_front = [
        bm_eh.verts.new((EJECTOR_X + r_inner * math.cos(2.0 * math.pi * i / eh_segs), 0.157, EJECTOR_Z + r_inner * math.sin(2.0 * math.pi * i / eh_segs)))
        for i in range(eh_segs)
    ]
    inner_back = [
        bm_eh.verts.new((EJECTOR_X + r_inner * math.cos(2.0 * math.pi * i / eh_segs), 0.140, EJECTOR_Z + r_inner * math.sin(2.0 * math.pi * i / eh_segs)))
        for i in range(eh_segs)
    ]
    for r0, r1 in ((eh_vrings[-1], inner_front), (inner_front, inner_back)):
        for i in range(eh_segs):
            j = (i + 1) % eh_segs
            bm_eh.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm_eh.faces.new(inner_back)
    bmesh.ops.recalc_face_normals(bm_eh, faces=bm_eh.faces)
    eh_mesh = bpy.data.meshes.new("EjectorHousing")
    bm_eh.to_mesh(eh_mesh)
    bm_eh.free()
    eh_obj = bpy.data.objects.new("EjectorHousing", eh_mesh)
    bpy.context.collection.objects.link(eh_obj)
    _set_smooth_by_angle(eh_obj, 38.0)
    _assign_mat_to_all_faces(eh_obj, mat_blued)

    # Ejector mounting boss / screw stud near front of housing
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=14, radius=0.0022, depth=0.007, location=(EJECTOR_X + 0.0028, 0.148, EJECTOR_Z - 0.0055), rotation=(0.0, math.pi * 0.5, 0.0)
    )
    eh_stud = bpy.context.active_object
    eh_stud.name = "EjectorStud"
    _add_bevel(eh_stud, 0.0003, 1)
    _apply_modifiers(eh_stud)
    _set_smooth_by_angle(eh_stud, 35.0)
    _assign_mat_to_all_faces(eh_stud, mat_case)

    return [barrel_obj, sight_obj, eh_obj, eh_stud]


def build_receiver_frame(mat_case: bpy.types.Material, mat_blued: bpy.types.Material) -> list[bpy.types.Object]:
    """Build Colt SAA receiver frame: top strap, front wall, bottom rail, recoil shield, loading gate, screws."""
    parts: list[bpy.types.Object] = []

    # 1. Top strap (with rear sight V-notch groove)
    top_profile = [
        (-0.005, 0.0410),
        (-0.005, 0.0458),
        (0.012, 0.0462),
        (0.056, 0.0445),
        (0.0625, 0.0432),
        (0.0625, 0.0402),
        (0.014, 0.0405),
    ]
    top_strap = _extrude_yz_profile("FrameTopStrap", top_profile, half_width_x=0.0078, bevel_width=0.0006, bevel_segments=2)
    _assign_mat_to_all_faces(top_strap, mat_case)
    parts.append(top_strap)

    # 2. Front cylinder-window wall (barrel mounting ring)
    front_profile = [
        (0.0565, -0.0040),
        (0.0565, 0.0415),
        (0.0630, 0.0415),
        (0.0645, 0.0250),
        (0.0630, 0.0030),
        (0.0605, -0.0040),
    ]
    front_wall = _extrude_yz_profile("FrameFrontWall", front_profile, half_width_x=0.0112, bevel_width=0.0007, bevel_segments=2)
    _assign_mat_to_all_faces(front_wall, mat_case)
    parts.append(front_wall)

    # Cylinder arbor base pin protruding forward under barrel
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=16, radius=0.0034, depth=0.018, location=(0.0, 0.066, CYL_Z_CENTER), rotation=(math.pi * 0.5, 0.0, 0.0)
    )
    arbor_pin = bpy.context.active_object
    arbor_pin.name = "ArborBasePin"
    _add_bevel(arbor_pin, 0.0003, 1)
    _apply_modifiers(arbor_pin)
    _set_smooth_by_angle(arbor_pin, 35.0)
    _assign_mat_to_all_faces(arbor_pin, mat_blued)
    parts.append(arbor_pin)

    # 3. Bottom frame rail under cylinder window
    bot_profile = [
        (0.004, -0.0045),
        (0.004, 0.0015),
        (0.058, 0.0015),
        (0.058, -0.0045),
    ]
    bot_rail = _extrude_yz_profile("FrameBottomRail", bot_profile, half_width_x=0.0110, bevel_width=0.0006, bevel_segments=2)
    _assign_mat_to_all_faces(bot_rail, mat_case)
    parts.append(bot_rail)

    # 4. Receiver side plates (left and right of hammer slot) with smooth Colt SAA tang sweep
    side_profile = [
        (-0.018, -0.0080),
        (-0.015, -0.0010),
        (-0.012, 0.0070),
        (-0.010, 0.0180),
        (-0.007, 0.0310),
        (-0.004, 0.0435),
        (0.014, 0.0445),
        (0.014, -0.0045),
        (-0.006, -0.0045),
    ]
    left_cheek = _extrude_yz_profile("ReceiverLeft", side_profile, half_width_x=0.0040, x_offset=-0.0078, bevel_width=0.0007, bevel_segments=2)
    right_cheek = _extrude_yz_profile("ReceiverRight", side_profile, half_width_x=0.0040, x_offset=0.0078, bevel_width=0.0007, bevel_segments=2)
    _assign_mat_to_all_faces(left_cheek, mat_case)
    _assign_mat_to_all_faces(right_cheek, mat_case)
    parts.extend([left_cheek, right_cheek])

    # Lower receiver bridge connecting left & right beneath hammer
    lower_rec = _extrude_yz_profile(
        "ReceiverBridge",
        [(-0.015, -0.0045), (-0.012, 0.012), (0.014, 0.012), (0.014, -0.0045)],
        half_width_x=0.0045,
        bevel_width=0.0005,
        bevel_segments=1,
    )
    _assign_mat_to_all_faces(lower_rec, mat_case)
    parts.append(lower_rec)

    # 5. Rounded recoil shield (left & right semi-cylindrical domes behind cylinder)
    for side_sign, side_name in ((-1.0, "RecoilLeft"), (1.0, "RecoilRight")):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=32, radius=0.0195, depth=0.0115, location=(0.0, 0.0100, CYL_Z_CENTER), rotation=(math.pi * 0.5, 0.0, 0.0)
        )
        shield = bpy.context.active_object
        shield.name = side_name
        bm = bmesh.new()
        bm.from_mesh(shield.data)
        for v in bm.verts:
            if side_sign < 0 and v.co.x > -0.0035:
                v.co.x = -0.0035
            elif side_sign > 0 and v.co.x < 0.0035:
                v.co.x = 0.0035
            if v.co.z < -0.002:
                v.co.z = -0.002
            if v.co.y < 0.009:
                v.co.x *= 0.85
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(shield.data)
        bm.free()
        _add_bevel(shield, 0.0006, 2)
        _apply_modifiers(shield)
        _set_smooth_by_angle(shield, 40.0)
        _assign_mat_to_all_faces(shield, mat_case)
        parts.append(shield)

    # 6. Right-side loading gate (smooth crescent flap tucked against recoil shield)
    gate_profile = [
        (0.0065, 0.0070),
        (0.0065, 0.0220),
        (0.0100, 0.0270),
        (0.0138, 0.0245),
        (0.0152, 0.0165),
        (0.0145, 0.0095),
        (0.0110, 0.0055),
    ]
    gate = _extrude_yz_profile("LoadingGate", gate_profile, half_width_x=0.0018, x_offset=0.0162, bevel_width=0.0006, bevel_segments=2)
    _assign_mat_to_all_faces(gate, mat_case)
    parts.append(gate)

    # 7. Frame pin screws (4 side screws + 1 front base-pin screw)
    screw_coords = [
        (-0.0120, 0.003, 0.007),
        (-0.0120, 0.011, 0.001),
        (-0.0120, 0.028, 0.001),
        (0.0120, 0.003, 0.007),
        (0.0120, 0.028, 0.001),
        (-0.0115, 0.0595, 0.019),
    ]
    for idx, (sx, sy, sz) in enumerate(screw_coords):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=14, radius=0.0024, depth=0.0024, location=(sx, sy, sz), rotation=(0.0, math.pi * 0.5, 0.0)
        )
        scr = bpy.context.active_object
        scr.name = f"FrameScrew_{idx}"
        _add_bevel(scr, 0.0003, 1)
        _apply_modifiers(scr)
        _set_smooth_by_angle(scr, 35.0)
        _assign_mat_to_all_faces(scr, mat_blued)
        parts.append(scr)

    return parts


def build_brass_guard_and_strap(mat_brass: bpy.types.Material) -> list[bpy.types.Object]:
    """Build aged brass trigger guard bow, mounting tangs, backstrap, and frontstrap."""
    parts: list[bpy.types.Object] = []

    # 1. Trigger guard mounting plate under receiver
    tang_profile = [
        (-0.006, -0.0075),
        (-0.006, -0.0040),
        (0.045, -0.0040),
        (0.045, -0.0075),
    ]
    guard_tang = _extrude_yz_profile("TriggerGuardTang", tang_profile, half_width_x=0.0075, bevel_width=0.0005, bevel_segments=2)
    _assign_mat_to_all_faces(guard_tang, mat_brass)
    parts.append(guard_tang)

    # 2. Swept oval trigger guard bow (18 smooth spline points)
    bm = bmesh.new()
    bow_pts = []
    for k in range(19):
        t = k / 18.0
        ang = math.pi * (1.0 - t)  # pi (rear) -> pi/2 (bottom) -> 0 (front)
        py = 0.0210 - 0.0185 * math.cos(ang)
        pz = -0.0060 - 0.0295 * math.sin(ang)
        bow_pts.append((py, pz))
    half_w = 0.0044
    half_t = 0.0017
    rings = []
    for i, (py, pz) in enumerate(bow_pts):
        if i == 0:
            dy, dz = bow_pts[1][0] - py, bow_pts[1][1] - pz
        elif i == len(bow_pts) - 1:
            dy, dz = py - bow_pts[-2][0], pz - bow_pts[-2][1]
        else:
            dy, dz = bow_pts[i + 1][0] - bow_pts[i - 1][0], bow_pts[i + 1][1] - bow_pts[i - 1][1]
        length = max(math.hypot(dy, dz), 1e-6)
        ny, nz = -dz / length, dy / length
        ring = [
            bm.verts.new((-half_w, py + ny * half_t, pz + nz * half_t)),
            bm.verts.new((half_w, py + ny * half_t, pz + nz * half_t)),
            bm.verts.new((half_w, py - ny * half_t, pz - nz * half_t)),
            bm.verts.new((-half_w, py - ny * half_t, pz - nz * half_t)),
        ]
        rings.append(ring)
    bm.faces.new(list(reversed(rings[0])))
    for k in range(len(rings) - 1):
        r0, r1 = rings[k], rings[k + 1]
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bow_mesh = bpy.data.meshes.new("TriggerGuardBow")
    bm.to_mesh(bow_mesh)
    bm.free()
    bow_obj = bpy.data.objects.new("TriggerGuardBow", bow_mesh)
    bpy.context.collection.objects.link(bow_obj)
    _add_bevel(bow_obj, 0.0005, 2)
    _apply_modifiers(bow_obj)
    _set_smooth_by_angle(bow_obj, 38.0)
    _assign_mat_to_all_faces(bow_obj, mat_brass)
    parts.append(bow_obj)

    # 3. Brass backstrap (swept along rear spine of grip, proud of walnut by 1mm)
    backstrap_profile = [
        (-0.008, 0.001),
        (-0.017, -0.004),
        (-0.027, -0.014),
        (-0.038, -0.028),
        (-0.050, -0.045),
        (-0.062, -0.063),
        (-0.071, -0.076),
        (-0.065, -0.078),
        (-0.054, -0.064),
        (-0.042, -0.046),
        (-0.030, -0.029),
        (-0.019, -0.015),
        (-0.009, -0.006),
        (-0.003, -0.003),
    ]
    backstrap = _extrude_yz_profile("Backstrap", backstrap_profile, half_width_x=0.0088, bevel_width=0.0005, bevel_segments=2)
    _assign_mat_to_all_faces(backstrap, mat_brass)
    parts.append(backstrap)

    # 4. Brass frontstrap + butt cap (proud of walnut front edge)
    frontstrap_profile = [
        (-0.004, -0.006),
        (-0.007, -0.016),
        (-0.012, -0.031),
        (-0.016, -0.050),
        (-0.021, -0.070),
        (-0.024, -0.078),
        (-0.069, -0.077),
        (-0.068, -0.072),
        (-0.028, -0.072),
        (-0.023, -0.052),
        (-0.018, -0.033),
        (-0.013, -0.018),
        (-0.008, -0.006),
    ]
    frontstrap = _extrude_yz_profile("Frontstrap", frontstrap_profile, half_width_x=0.0088, bevel_width=0.0005, bevel_segments=2)
    _assign_mat_to_all_faces(frontstrap, mat_brass)
    parts.append(frontstrap)

    # 5. Grip screw brass escutcheons on both grip panels
    for side_sign, sname in ((-1.0, "EscutcheonL"), (1.0, "EscutcheonR")):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=16, radius=0.0036, depth=0.0022, location=(side_sign * 0.0148, -0.031, -0.037), rotation=(0.0, math.pi * 0.5, 0.0)
        )
        esc = bpy.context.active_object
        esc.name = sname
        _add_bevel(esc, 0.0003, 1)
        _apply_modifiers(esc)
        _set_smooth_by_angle(esc, 35.0)
        _assign_mat_to_all_faces(esc, mat_brass)
        parts.append(esc)

    return parts


def build_walnut_grip(mat_walnut: bpy.types.Material) -> bpy.types.Object:
    """Build lofted Colt SAA plow-handle walnut grip matching backstrap/frontstrap curve."""
    # Spine slices from top under frame down to butt: (y_back, y_front, z_center, half_x)
    sections = [
        (-0.012, -0.006, -0.004, 0.0108),
        (-0.020, -0.009, -0.012, 0.0122),
        (-0.030, -0.014, -0.024, 0.0138),
        (-0.041, -0.018, -0.038, 0.0150),
        (-0.052, -0.021, -0.052, 0.0152),
        (-0.061, -0.024, -0.064, 0.0146),
        (-0.068, -0.026, -0.073, 0.0138),
        (-0.066, -0.028, -0.076, 0.0122),
    ]
    bm = bmesh.new()
    ring_n = 20
    rings = []
    for yb, yf, zc, hx in sections:
        yc = 0.5 * (yb + yf)
        hy = 0.5 * (yf - yb)
        ring = []
        for i in range(ring_n):
            theta = 2.0 * math.pi * i / ring_n
            # Superellipse (squircle-oval) for classic gun grip swell
            ct = math.cos(theta)
            st = math.sin(theta)
            vx = hx * math.copysign(abs(ct) ** 0.72, ct)
            vy = yc + hy * math.copysign(abs(st) ** 0.78, st)
            ring.append(bm.verts.new((vx, vy, zc)))
        rings.append(ring)

    bm.faces.new(list(reversed(rings[0])))
    for k in range(len(rings) - 1):
        r0, r1 = rings[k], rings[k + 1]
        for i in range(ring_n):
            j = (i + 1) % ring_n
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("WalnutGrip")
    bm.to_mesh(mesh)
    bm.free()
    grip_obj = bpy.data.objects.new("WalnutGrip", mesh)
    bpy.context.collection.objects.link(grip_obj)
    _set_smooth_by_angle(grip_obj, 50.0)
    _assign_mat_to_all_faces(grip_obj, mat_walnut)
    return grip_obj


def build_cylinder(mat_blued: bpy.types.Material) -> bpy.types.Object:
    """Build 6-chamber fluted Colt SAA cylinder with bevels, bolt notches, and chamber bores."""
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=48,
        radius=CYL_RADIUS,
        depth=CYL_LEN,
        location=PIVOT_CYLINDER,
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    cyl_obj = bpy.context.active_object
    cyl_obj.name = "mesh_cylinder"
    _add_bevel(cyl_obj, 0.0010, 2)
    _apply_modifiers(cyl_obj)

    chamber_offset = 0.0130  # CYL_Z_CENTER + 0.0130 = 0.0320 == BORE_Z!
    for i in range(6):
        ang = i * (math.pi / 3.0) + math.pi * 0.5  # i=0 at top (+Z) aligned with bore
        cx = chamber_offset * math.cos(ang)
        cz = CYL_Z_CENTER + chamber_offset * math.sin(ang)

        # Through-chamber bore
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=20,
            radius=0.0054,
            depth=CYL_LEN + 0.008,
            location=(cx, CYL_Y_CENTER, cz),
            rotation=(math.pi * 0.5, 0.0, 0.0),
        )
        ch_cut = bpy.context.active_object
        b_mod = cyl_obj.modifiers.new(name=f"Ch_{i}", type="BOOLEAN")
        b_mod.operation = "DIFFERENCE"
        b_mod.solver = "EXACT"
        b_mod.object = ch_cut
        bpy.context.view_layer.objects.active = cyl_obj
        bpy.ops.object.modifier_apply(modifier=b_mod.name)
        bpy.data.objects.remove(ch_cut, do_unlink=True)

        # Exterior flute groove (offset by 30 deg between chambers)
        f_ang = ang + (math.pi / 6.0)
        fx = (CYL_RADIUS + 0.0020) * math.cos(f_ang)
        fz = CYL_Z_CENTER + (CYL_RADIUS + 0.0020) * math.sin(f_ang)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=20,
            radius=0.0054,
            depth=0.0255,
            location=(fx, CYL_Y_CENTER + 0.0035, fz),
            rotation=(math.pi * 0.5, 0.0, 0.0),
        )
        fl_cut = bpy.context.active_object
        f_mod = cyl_obj.modifiers.new(name=f"Fl_{i}", type="BOOLEAN")
        f_mod.operation = "DIFFERENCE"
        f_mod.solver = "EXACT"
        f_mod.object = fl_cut
        bpy.context.view_layer.objects.active = cyl_obj
        bpy.ops.object.modifier_apply(modifier=f_mod.name)
        bpy.data.objects.remove(fl_cut, do_unlink=True)

        # Locking bolt notch near rear collar
        nx = (CYL_RADIUS + 0.0004) * math.cos(f_ang)
        nz = CYL_Z_CENTER + (CYL_RADIUS + 0.0004) * math.sin(f_ang)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(nx, CYL_Y_START + 0.0065, nz))
        notch_cut = bpy.context.active_object
        notch_cut.scale = (0.0032, 0.0040, 0.0032)
        notch_cut.rotation_euler = (0.0, -f_ang, 0.0)
        n_mod = cyl_obj.modifiers.new(name=f"Nt_{i}", type="BOOLEAN")
        n_mod.operation = "DIFFERENCE"
        n_mod.solver = "EXACT"
        n_mod.object = notch_cut
        bpy.context.view_layer.objects.active = cyl_obj
        bpy.ops.object.modifier_apply(modifier=n_mod.name)
        bpy.data.objects.remove(notch_cut, do_unlink=True)

    # Central arbor hole
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=16, radius=0.0035, depth=CYL_LEN + 0.008, location=PIVOT_CYLINDER, rotation=(math.pi * 0.5, 0.0, 0.0)
    )
    arb_cut = bpy.context.active_object
    a_mod = cyl_obj.modifiers.new(name="ArborCut", type="BOOLEAN")
    a_mod.operation = "DIFFERENCE"
    a_mod.solver = "EXACT"
    a_mod.object = arb_cut
    bpy.context.view_layer.objects.active = cyl_obj
    bpy.ops.object.modifier_apply(modifier=a_mod.name)
    bpy.data.objects.remove(arb_cut, do_unlink=True)

    _set_smooth_by_angle(cyl_obj, 34.0)
    _assign_mat_to_all_faces(cyl_obj, mat_blued)
    return cyl_obj


def build_hammer(mat_case: bpy.types.Material) -> bpy.types.Object:
    """Build Colt SAA hammer with firing pin nose and swept curved thumb spur."""
    hammer_profile = [
        (-0.004, 0.008),
        (-0.006, 0.022),
        (-0.010, 0.033),
        (-0.017, 0.042),
        (-0.024, 0.048),
        (-0.027, 0.052),
        (-0.024, 0.053),
        (-0.018, 0.049),
        (-0.010, 0.044),
        (-0.003, 0.039),
        (0.005, 0.035),
        (0.011, 0.033),
        (0.011, 0.030),
        (0.006, 0.028),
        (0.006, 0.012),
    ]
    ham_obj = _extrude_yz_profile(
        "mesh_hammer", hammer_profile, half_width_x=0.0030, bevel_width=0.0005, bevel_segments=2
    )
    _assign_mat_to_all_faces(ham_obj, mat_case)
    return ham_obj


def build_trigger(mat_blued: bpy.types.Material) -> bpy.types.Object:
    """Build curved Colt SAA trigger blade hanging inside trigger guard bow."""
    trig_profile = [
        (0.0155, -0.0020),
        (0.0155, -0.0100),
        (0.0145, -0.0185),
        (0.0125, -0.0255),
        (0.0152, -0.0265),
        (0.0185, -0.0195),
        (0.0205, -0.0110),
        (0.0210, -0.0020),
    ]
    trig_obj = _extrude_yz_profile(
        "mesh_trigger", trig_profile, half_width_x=0.0017, bevel_width=0.00035, bevel_segments=2
    )
    _assign_mat_to_all_faces(trig_obj, mat_blued)
    return trig_obj


def build_ejector(mat_blued: bpy.types.Material) -> bpy.types.Object:
    """Build sliding ejector rod and crescent thumb head protruding from housing."""
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=16,
        radius=0.0026,
        depth=0.095,
        location=(EJECTOR_X, 0.1115, EJECTOR_Z),
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    rod = bpy.context.active_object
    rod.name = "EjectorRod"
    _set_smooth_by_angle(rod, 38.0)

    # Iconic crescent thumb button at front of rod
    head_profile = [
        (0.1555, EJECTOR_Z - 0.0055),
        (0.1555, EJECTOR_Z + 0.0028),
        (0.1615, EJECTOR_Z + 0.0028),
        (0.1635, EJECTOR_Z - 0.0010),
        (0.1605, EJECTOR_Z - 0.0065),
    ]
    head = _extrude_yz_profile(
        "EjectorHead", head_profile, half_width_x=0.0034, x_offset=EJECTOR_X + 0.0005, bevel_width=0.0004, bevel_segments=2
    )
    ejec = _join_objects([rod, head], "mesh_ejector")
    _assign_mat_to_all_faces(ejec, mat_blued)
    return ejec


# ---------------------------------------------------------------------------
# Procedural Cycles Materials (Heavy Wear, Case-Hardened, Brass, Walnut)
# ---------------------------------------------------------------------------
def _make_procedural_materials() -> dict[str, bpy.types.Material]:
    """Build 4 procedural PBR Cycles materials with bevel-edge wear & crevice grime."""

    def base_setup(name: str) -> tuple[bpy.types.Material, bpy.types.NodeTree, bpy.types.Node]:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        tree = mat.node_tree
        nodes = tree.nodes
        links = tree.links
        bsdf = nodes.get("Principled BSDF")
        # Common Object coords + Bevel edge curvature mask
        tex_coord = nodes.new("ShaderNodeTexCoord")
        tex_coord.location = (-1200, 200)

        geom = nodes.new("ShaderNodeNewGeometry")
        geom.location = (-1000, -150)

        bev_node = nodes.new("ShaderNodeBevel")
        bev_node.samples = 4
        bev_node.inputs["Radius"].default_value = 0.0018
        bev_node.location = (-1000, -320)

        dot_node = nodes.new("ShaderNodeVectorMath")
        dot_node.operation = "DOT_PRODUCT"
        dot_node.location = (-800, -240)
        links.new(geom.outputs["Normal"], dot_node.inputs[0])
        links.new(bev_node.outputs["Normal"], dot_node.inputs[1])

        # Edge wear = 1 - dot(N, BevelN), amplified
        inv_dot = nodes.new("ShaderNodeMapRange")
        inv_dot.location = (-600, -240)
        inv_dot.inputs["From Min"].default_value = 0.996
        inv_dot.inputs["From Max"].default_value = 0.920
        inv_dot.inputs["To Min"].default_value = 0.0
        inv_dot.inputs["To Max"].default_value = 1.0
        links.new(dot_node.outputs["Value"], inv_dot.inputs["Value"])

        # AO crevice mask
        ao_node = nodes.new("ShaderNodeAmbientOcclusion")
        ao_node.samples = 8
        ao_node.inputs["Distance"].default_value = 0.018
        ao_node.location = (-600, -480)

        return mat, tree, bsdf

    # Helper to find common nodes we just created
    def get_helpers(tree: bpy.types.NodeTree):
        tc = [n for n in tree.nodes if n.type == "TEX_COORD"][0]
        edge_mr = [n for n in tree.nodes if n.type == "MAP_RANGE"][0]
        ao = [n for n in tree.nodes if n.type == "AMBIENT_OCCLUSION"][0]
        return tc, edge_mr, ao

    # 1. Case-Hardened Steel (Receiver, Hammer, Loading Gate) — mottled patina + worn silver edges
    mat_case, tree, bsdf = base_setup("Mat_CaseHardened")
    nodes, links = tree.nodes, tree.links
    tc, edge_mr, ao = get_helpers(tree)

    noise_mottle = nodes.new("ShaderNodeTexNoise")
    noise_mottle.inputs["Scale"].default_value = 65.0
    noise_mottle.inputs["Detail"].default_value = 8.0
    noise_mottle.inputs["Roughness"].default_value = 0.65
    noise_mottle.inputs["Distortion"].default_value = 1.6
    noise_mottle.location = (-850, 320)
    links.new(tc.outputs["Object"], noise_mottle.inputs["Vector"])

    ramp_case = nodes.new("ShaderNodeValToRGB")
    ramp_case.location = (-600, 320)
    elts = ramp_case.color_ramp.elements
    elts[0].position = 0.28
    elts[0].color = (0.045, 0.042, 0.048, 1.0)  # Dark charcoal-steel
    elts[1].position = 0.56
    elts[1].color = (0.125, 0.085, 0.060, 1.0)  # Warm bronze-tan case mottle
    e2 = ramp_case.color_ramp.elements.new(0.75)
    e2.color = (0.075, 0.095, 0.145, 1.0)  # Case-hardened slate blue
    links.new(noise_mottle.outputs["Fac"], ramp_case.inputs["Fac"])

    # Mix in bright worn steel on edges (heavy wear)
    mix_edge = nodes.new("ShaderNodeMix")
    mix_edge.data_type = "RGBA"
    mix_edge.location = (-320, 260)
    mix_edge.inputs["B"].default_value = (0.30, 0.30, 0.32, 1.0)
    links.new(edge_mr.outputs["Result"], mix_edge.inputs["Factor"])
    links.new(ramp_case.outputs["Color"], mix_edge.inputs["A"])

    # Darken crevices via AO
    mix_ao = nodes.new("ShaderNodeMix")
    mix_ao.data_type = "RGBA"
    mix_ao.blend_type = "MULTIPLY"
    mix_ao.inputs["Factor"].default_value = 0.65
    mix_ao.location = (-140, 260)
    links.new(mix_edge.outputs["Result"], mix_ao.inputs["A"])
    links.new(ao.outputs["Color"], mix_ao.inputs["B"])
    links.new(mix_ao.outputs["Result"], bsdf.inputs["Base Color"])

    bsdf.inputs["Metallic"].default_value = 0.90

    # Roughness: 0.35 base, rougher in crevices, shinier on worn edges
    noise_r = nodes.new("ShaderNodeTexNoise")
    noise_r.inputs["Scale"].default_value = 180.0
    noise_r.inputs["Detail"].default_value = 6.0
    noise_r.location = (-850, 40)
    links.new(tc.outputs["Object"], noise_r.inputs["Vector"])

    mr_r = nodes.new("ShaderNodeMapRange")
    mr_r.inputs["To Min"].default_value = 0.26
    mr_r.inputs["To Max"].default_value = 0.46
    mr_r.location = (-350, 20)
    links.new(noise_r.outputs["Fac"], mr_r.inputs["Value"])
    links.new(mr_r.outputs["Result"], bsdf.inputs["Roughness"])

    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    bump.inputs["Distance"].default_value = 0.001
    bump.location = (-180, -120)
    links.new(noise_r.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    # 2. Blued / Worn Steel (Barrel, Cylinder, Sight, Trigger, Ejector, Screws)
    mat_blued, tree_b, bsdf_b = base_setup("Mat_BluedSteel")
    nodes, links = tree_b.nodes, tree_b.links
    tc, edge_mr, ao = get_helpers(tree_b)

    noise_b = nodes.new("ShaderNodeTexNoise")
    noise_b.inputs["Scale"].default_value = 85.0
    noise_b.inputs["Detail"].default_value = 8.0
    noise_b.inputs["Roughness"].default_value = 0.72
    noise_b.location = (-850, 300)
    links.new(tc.outputs["Object"], noise_b.inputs["Vector"])

    ramp_b = nodes.new("ShaderNodeValToRGB")
    ramp_b.location = (-600, 300)
    ramp_b.color_ramp.elements[0].position = 0.32
    ramp_b.color_ramp.elements[0].color = (0.032, 0.036, 0.048, 1.0)  # Deep gunmetal bluing (linear)
    ramp_b.color_ramp.elements[1].position = 0.72
    ramp_b.color_ramp.elements[1].color = (0.145, 0.145, 0.155, 1.0)  # Worn grey-silver steel
    links.new(noise_b.outputs["Fac"], ramp_b.inputs["Fac"])

    mix_b_edge = nodes.new("ShaderNodeMix")
    mix_b_edge.data_type = "RGBA"
    mix_b_edge.location = (-320, 240)
    mix_b_edge.inputs["B"].default_value = (0.32, 0.32, 0.34, 1.0)
    links.new(edge_mr.outputs["Result"], mix_b_edge.inputs["Factor"])
    links.new(ramp_b.outputs["Color"], mix_b_edge.inputs["A"])

    mix_b_ao = nodes.new("ShaderNodeMix")
    mix_b_ao.data_type = "RGBA"
    mix_b_ao.blend_type = "MULTIPLY"
    mix_b_ao.inputs["Factor"].default_value = 0.7
    mix_b_ao.location = (-140, 240)
    links.new(mix_b_edge.outputs["Result"], mix_b_ao.inputs["A"])
    links.new(ao.outputs["Color"], mix_b_ao.inputs["B"])
    links.new(mix_b_ao.outputs["Result"], bsdf_b.inputs["Base Color"])

    bsdf_b.inputs["Metallic"].default_value = 0.92
    mr_br = nodes.new("ShaderNodeMapRange")
    mr_br.inputs["To Min"].default_value = 0.25
    mr_br.inputs["To Max"].default_value = 0.44
    mr_br.location = (-350, 20)
    links.new(noise_b.outputs["Fac"], mr_br.inputs["Value"])
    links.new(mr_br.outputs["Result"], bsdf_b.inputs["Roughness"])

    bump_b = nodes.new("ShaderNodeBump")
    bump_b.inputs["Strength"].default_value = 0.07
    bump_b.inputs["Distance"].default_value = 0.001
    bump_b.location = (-180, -120)
    links.new(noise_b.outputs["Fac"], bump_b.inputs["Height"])
    links.new(bump_b.outputs["Normal"], bsdf_b.inputs["Normal"])

    # 3. Aged Tarnished Brass (Trigger guard, Backstrap, Frontstrap, Escutcheons)
    mat_brass, tree_br, bsdf_br = base_setup("Mat_AgedBrass")
    nodes, links = tree_br.nodes, tree_br.links
    tc, edge_mr, ao = get_helpers(tree_br)

    noise_br = nodes.new("ShaderNodeTexNoise")
    noise_br.inputs["Scale"].default_value = 110.0
    noise_br.inputs["Detail"].default_value = 7.0
    noise_br.location = (-850, 300)
    links.new(tc.outputs["Object"], noise_br.inputs["Vector"])

    ramp_br = nodes.new("ShaderNodeValToRGB")
    ramp_br.location = (-600, 300)
    ramp_br.color_ramp.elements[0].position = 0.30
    ramp_br.color_ramp.elements[0].color = (0.14, 0.095, 0.032, 1.0)  # Dark tarnished bronze-brass (linear)
    ramp_br.color_ramp.elements[1].position = 0.72
    ramp_br.color_ramp.elements[1].color = (0.34, 0.24, 0.085, 1.0)  # Dull aged brass
    links.new(noise_br.outputs["Fac"], ramp_br.inputs["Fac"])

    mix_br_edge = nodes.new("ShaderNodeMix")
    mix_br_edge.data_type = "RGBA"
    mix_br_edge.location = (-320, 240)
    mix_br_edge.inputs["B"].default_value = (0.48, 0.35, 0.14, 1.0)
    links.new(edge_mr.outputs["Result"], mix_br_edge.inputs["Factor"])
    links.new(ramp_br.outputs["Color"], mix_br_edge.inputs["A"])

    mix_br_ao = nodes.new("ShaderNodeMix")
    mix_br_ao.data_type = "RGBA"
    mix_br_ao.blend_type = "MULTIPLY"
    mix_br_ao.inputs["Factor"].default_value = 0.55
    mix_br_ao.location = (-140, 240)
    links.new(mix_br_edge.outputs["Result"], mix_br_ao.inputs["A"])
    links.new(ao.outputs["Color"], mix_br_ao.inputs["B"])
    links.new(mix_br_ao.outputs["Result"], bsdf_br.inputs["Base Color"])

    bsdf_br.inputs["Metallic"].default_value = 0.94
    mr_brr = nodes.new("ShaderNodeMapRange")
    mr_brr.inputs["To Min"].default_value = 0.24
    mr_brr.inputs["To Max"].default_value = 0.40
    mr_brr.location = (-350, 20)
    links.new(noise_br.outputs["Fac"], mr_brr.inputs["Value"])
    links.new(mr_brr.outputs["Result"], bsdf_br.inputs["Roughness"])

    bump_br = nodes.new("ShaderNodeBump")
    bump_br.inputs["Strength"].default_value = 0.05
    bump_br.inputs["Distance"].default_value = 0.001
    bump_br.location = (-180, -120)
    links.new(noise_br.outputs["Fac"], bump_br.inputs["Height"])
    links.new(bump_br.outputs["Normal"], bsdf_br.inputs["Normal"])

    # 4. Worn Walnut Wood (Grip) — rich dark antique walnut grain + dented scratches
    mat_walnut, tree_w, bsdf_w = base_setup("Mat_WornWalnut")
    nodes, links = tree_w.nodes, tree_w.links
    tc, edge_mr, ao = get_helpers(tree_w)

    mapping_w = nodes.new("ShaderNodeMapping")
    mapping_w.inputs["Rotation"].default_value = (0.42, 0.0, 0.0)
    mapping_w.inputs["Scale"].default_value = (24.0, 22.0, 3.0)
    mapping_w.location = (-1000, 300)
    links.new(tc.outputs["Object"], mapping_w.inputs["Vector"])

    wave_w = nodes.new("ShaderNodeTexWave")
    wave_w.wave_type = "BANDS"
    wave_w.bands_direction = "Y"
    wave_w.inputs["Scale"].default_value = 5.0
    wave_w.inputs["Distortion"].default_value = 6.5
    wave_w.inputs["Detail"].default_value = 7.0
    wave_w.location = (-780, 300)
    links.new(mapping_w.outputs["Vector"], wave_w.inputs["Vector"])

    ramp_w = nodes.new("ShaderNodeValToRGB")
    ramp_w.location = (-540, 300)
    ramp_w.color_ramp.elements[0].position = 0.25
    ramp_w.color_ramp.elements[0].color = (0.012, 0.005, 0.002, 1.0)  # Deep dark walnut grain (linear)
    ramp_w.color_ramp.elements[1].position = 0.78
    ramp_w.color_ramp.elements[1].color = (0.048, 0.020, 0.008, 1.0)  # Warm dark antique walnut (linear)
    links.new(wave_w.outputs["Fac"], ramp_w.inputs["Fac"])

    # Dents / scratches noise
    noise_dent = nodes.new("ShaderNodeTexNoise")
    noise_dent.inputs["Scale"].default_value = 160.0
    noise_dent.inputs["Detail"].default_value = 8.0
    noise_dent.location = (-780, 60)
    links.new(tc.outputs["Object"], noise_dent.inputs["Vector"])

    mix_w_edge = nodes.new("ShaderNodeMix")
    mix_w_edge.data_type = "RGBA"
    mix_w_edge.location = (-300, 240)
    mix_w_edge.inputs["B"].default_value = (0.085, 0.040, 0.016, 1.0)  # Rubbed grip edge wear
    links.new(edge_mr.outputs["Result"], mix_w_edge.inputs["Factor"])
    links.new(ramp_w.outputs["Color"], mix_w_edge.inputs["A"])

    mix_w_ao = nodes.new("ShaderNodeMix")
    mix_w_ao.data_type = "RGBA"
    mix_w_ao.blend_type = "MULTIPLY"
    mix_w_ao.inputs["Factor"].default_value = 0.65
    mix_w_ao.location = (-120, 240)
    links.new(mix_w_edge.outputs["Result"], mix_w_ao.inputs["A"])
    links.new(ao.outputs["Color"], mix_w_ao.inputs["B"])
    links.new(mix_w_ao.outputs["Result"], bsdf_w.inputs["Base Color"])

    bsdf_w.inputs["Metallic"].default_value = 0.0
    mr_wr = nodes.new("ShaderNodeMapRange")
    mr_wr.inputs["To Min"].default_value = 0.54
    mr_wr.inputs["To Max"].default_value = 0.76
    mr_wr.location = (-350, 20)
    links.new(noise_dent.outputs["Fac"], mr_wr.inputs["Value"])
    links.new(mr_wr.outputs["Result"], bsdf_w.inputs["Roughness"])

    bump_w = nodes.new("ShaderNodeBump")
    bump_w.inputs["Strength"].default_value = 0.14
    bump_w.inputs["Distance"].default_value = 0.0015
    bump_w.location = (-180, -120)
    links.new(noise_dent.outputs["Fac"], bump_w.inputs["Height"])
    links.new(bump_w.outputs["Normal"], bsdf_w.inputs["Normal"])

    return {
        "case": mat_case,
        "blued": mat_blued,
        "brass": mat_brass,
        "walnut": mat_walnut,
    }


# ---------------------------------------------------------------------------
# UV Packing + Cycles Bake (2048 Albedo / NormalGL / ORM)
# ---------------------------------------------------------------------------
def bake_revolver_maps(
    meshes: list[bpy.types.Object],
    materials: list[bpy.types.Material],
    tex_dir: Path,
    tex_size: int = 2048,
) -> tuple[bpy.types.Image, bpy.types.Image, bpy.types.Image]:
    """Smart-UV pack all 5 meshes together and bake Albedo, NormalGL (+Y), and ORM."""
    tex_dir.mkdir(parents=True, exist_ok=True)

    # Multi-object Edit Mode Smart UV Project so all 5 parts share non-overlapping atlas
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55.0), island_margin=0.004, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = False
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 8
    scene.render.bake.use_clear = True

    def make_bake_image(name: str, is_data: bool) -> bpy.types.Image:
        img = bpy.data.images.new(name, width=tex_size, height=tex_size, alpha=False, is_data=is_data)
        return img

    def set_bake_target_on_all_mats(img: bpy.types.Image) -> None:
        for mat in materials:
            nodes = mat.node_tree.nodes
            bake_node = nodes.get("__BakeTarget")
            if bake_node is None:
                bake_node = nodes.new("ShaderNodeTexImage")
                bake_node.name = "__BakeTarget"
                bake_node.location = (300, 300)
            bake_node.image = img
            for n in nodes:
                n.select = False
            bake_node.select = True
            nodes.active = bake_node

    # 1. Albedo (Diffuse Color only = zero shadows)
    img_alb = make_bake_image("T_Revolver_Albedo", is_data=False)
    set_bake_target_on_all_mats(img_alb)
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
    alb_path = tex_dir / "T_Revolver_Albedo.png"
    img_alb.filepath_raw = str(alb_path)
    img_alb.file_format = "PNG"
    img_alb.save()

    # 2. NormalGL (+Y OpenGL Tangent)
    img_nrm = make_bake_image("T_Revolver_NormalGL", is_data=True)
    set_bake_target_on_all_mats(img_nrm)
    scene.render.bake.normal_space = "TANGENT"
    scene.render.bake.normal_r = "POS_X"
    scene.render.bake.normal_g = "POS_Y"
    scene.render.bake.normal_b = "POS_Z"
    bpy.ops.object.bake(type="NORMAL", use_clear=True)
    nrm_path = tex_dir / "T_Revolver_NormalGL.png"
    img_nrm.filepath_raw = str(nrm_path)
    img_nrm.file_format = "PNG"
    img_nrm.save()

    # 3. Ambient Occlusion -> ORM.R
    scene.cycles.samples = 24
    img_ao = make_bake_image("__Bake_AO", is_data=True)
    set_bake_target_on_all_mats(img_ao)
    bpy.ops.object.bake(type="AO", use_clear=True)

    # 4. Roughness -> ORM.G
    scene.cycles.samples = 8
    img_rough = make_bake_image("__Bake_Rough", is_data=True)
    set_bake_target_on_all_mats(img_rough)
    bpy.ops.object.bake(type="ROUGHNESS", use_clear=True)

    # 5. Metallic -> ORM.B (temporarily link Metallic scalar into Emission)
    saved_links = []
    for mat in materials:
        tree = mat.node_tree
        bsdf = tree.nodes.get("Principled BSDF")
        out_node = tree.nodes.get("Material Output")
        metal_val = bsdf.inputs["Metallic"].default_value
        emit_node = tree.nodes.new("ShaderNodeEmission")
        emit_node.name = "__BakeMetalEmit"
        emit_node.inputs["Color"].default_value = (metal_val, metal_val, metal_val, 1.0)
        orig_link = out_node.inputs["Surface"].links[0]
        saved_links.append((mat, orig_link.from_socket))
        tree.links.new(emit_node.outputs["Emission"], out_node.inputs["Surface"])

    img_metal = make_bake_image("__Bake_Metal", is_data=True)
    set_bake_target_on_all_mats(img_metal)
    bpy.ops.object.bake(type="EMIT", use_clear=True)

    # Restore original material outputs
    for mat, orig_sock in saved_links:
        tree = mat.node_tree
        out_node = tree.nodes.get("Material Output")
        tree.links.new(orig_sock, out_node.inputs["Surface"])

    # Pack ORM (R=AO, G=Roughness, B=Metallic, A=1.0)
    px_ao = np.empty(tex_size * tex_size * 4, dtype=np.float32)
    px_rg = np.empty(tex_size * tex_size * 4, dtype=np.float32)
    px_mt = np.empty(tex_size * tex_size * 4, dtype=np.float32)
    img_ao.pixels.foreach_get(px_ao)
    img_rough.pixels.foreach_get(px_rg)
    img_metal.pixels.foreach_get(px_mt)

    orm_arr = np.empty((tex_size * tex_size, 4), dtype=np.float32)
    orm_arr[:, 0] = np.clip(px_ao[0::4], 0.0, 1.0)
    orm_arr[:, 1] = np.clip(px_rg[0::4], 0.05, 1.0)
    orm_arr[:, 2] = np.clip(px_mt[0::4], 0.0, 1.0)
    orm_arr[:, 3] = 1.0

    img_orm = make_bake_image("T_Revolver_ORM", is_data=True)
    img_orm.pixels.foreach_set(orm_arr.ravel())
    orm_path = tex_dir / "T_Revolver_ORM.png"
    img_orm.filepath_raw = str(orm_path)
    img_orm.file_format = "PNG"
    img_orm.save()

    # Clean temp bake images
    for tmp in (img_ao, img_rough, img_metal):
        bpy.data.images.remove(tmp)

    # Reload saved PNGs into single unified PBR material for GLB & review renders
    mat_baked = bpy.data.materials.new("M_Revolver_SAA_ORM")
    mat_baked.use_nodes = True
    nt = mat_baked.node_tree
    bsdf = nt.nodes.get("Principled BSDF")

    tex_a = nt.nodes.new("ShaderNodeTexImage")
    tex_a.image = img_alb
    nt.links.new(tex_a.outputs["Color"], bsdf.inputs["Base Color"])

    tex_o = nt.nodes.new("ShaderNodeTexImage")
    tex_o.image = img_orm
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_o.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_n = nt.nodes.new("ShaderNodeTexImage")
    tex_n.image = img_nrm
    nrm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex_n.outputs["Color"], nrm.inputs["Color"])
    nt.links.new(nrm.outputs["Normal"], bsdf.inputs["Normal"])

    for m in meshes:
        m.data.materials.clear()
        m.data.materials.append(mat_baked)

    return img_alb, img_orm, img_nrm


# ---------------------------------------------------------------------------
# Rigging & Review Renders
# ---------------------------------------------------------------------------
def rig_revolver(parts: dict[str, bpy.types.Object]) -> bpy.types.Object:
    """Create 5-bone Skeleton3D with heads at exact part pivots and bind meshes."""
    arm_obj = create_armature("Revolver_Rig")

    add_bone(arm_obj, "bone_root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.05), use_deform=True)
    add_bone(
        arm_obj,
        "bone_cylinder",
        PIVOT_CYLINDER,
        PIVOT_CYLINDER + Vector((0.0, 0.041, 0.0)),
        parent_name="bone_root",
    )
    add_bone(
        arm_obj,
        "bone_hammer",
        PIVOT_HAMMER,
        PIVOT_HAMMER + Vector((0.0, -0.020, 0.032)),
        parent_name="bone_root",
    )
    add_bone(
        arm_obj,
        "bone_trigger",
        PIVOT_TRIGGER,
        PIVOT_TRIGGER + Vector((0.0, -0.004, -0.022)),
        parent_name="bone_root",
    )
    add_bone(
        arm_obj,
        "bone_ejector",
        PIVOT_EJECTOR,
        PIVOT_EJECTOR + Vector((0.0, 0.095, 0.0)),
        parent_name="bone_root",
    )

    bpy.ops.object.mode_set(mode="OBJECT")

    part_to_bone = {
        "frame": "bone_root",
        "cylinder": "bone_cylinder",
        "hammer": "bone_hammer",
        "trigger": "bone_trigger",
        "ejector": "bone_ejector",
    }

    for key, obj in parts.items():
        bname = part_to_bone[key]
        vg = obj.vertex_groups.new(name=bname)
        vg.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
        obj.parent = arm_obj
        mod = obj.modifiers.new(name="Armature", type="ARMATURE")
        mod.object = arm_obj

    # Add fire_cycle action so GLB carries verified mechanical motion
    action = create_action(arm_obj, "fire_cycle")
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 30
    bpy.context.scene.render.fps = 30

    p_cyl = arm_obj.pose.bones["bone_cylinder"]
    p_ham = arm_obj.pose.bones["bone_hammer"]
    p_trig = arm_obj.pose.bones["bone_trigger"]
    p_ejec = arm_obj.pose.bones["bone_ejector"]
    for pb in (p_cyl, p_ham, p_trig, p_ejec):
        pb.rotation_mode = "XYZ"

    # Keyframes: rest -> cock + 60 deg index -> trigger pull + hammer drop -> rest
    keys = [
        (1, 0.0, 0.0, 0.0, 0.0),
        (10, -0.60, math.radians(60.0), 0.0, 0.0),
        (14, -0.60, math.radians(60.0), 0.42, 0.0),
        (17, 0.0, math.radians(60.0), 0.42, 0.0),
        (24, 0.0, math.radians(60.0), 0.0, -0.025),
        (30, 0.0, math.radians(60.0), 0.0, 0.0),
    ]
    for fr, ham_x, cyl_y, trig_x, ejec_y in keys:
        bpy.context.scene.frame_set(fr)
        p_ham.rotation_euler = (ham_x, 0.0, 0.0)
        p_cyl.rotation_euler = (0.0, cyl_y, 0.0)
        p_trig.rotation_euler = (trig_x, 0.0, 0.0)
        p_ejec.location = (0.0, ejec_y, 0.0)
        p_ham.keyframe_insert("rotation_euler", frame=fr)
        p_cyl.keyframe_insert("rotation_euler", frame=fr)
        p_trig.keyframe_insert("rotation_euler", frame=fr)
        p_ejec.keyframe_insert("location", frame=fr)

    bpy.context.scene.frame_set(1)
    push_action_to_nla(arm_obj, action, "fire_cycle")
    return arm_obj


def render_review_stills(render_dir: Path) -> list[Path]:
    """Render 3 Cycles studio stills (side, 3/4 front, FPS camera) for user review."""
    render_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"

    # Neutral mid-grey studio world lighting
    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.18, 0.19, 0.21, 1.0)
        bg.inputs["Strength"].default_value = 0.85

    def add_area_light(name: str, loc: tuple[float, float, float], target: tuple[float, float, float], energy: float, size: float) -> None:
        ld = bpy.data.lights.new(name, type="AREA")
        ld.energy = energy
        ld.size = size
        lo = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo)
        lo.location = loc
        direction = Vector(target) - Vector(loc)
        lo.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    center = (0.0, 0.055, -0.012)
    add_area_light("KeyLight", (0.35, 0.22, 0.38), center, 28.0, 0.45)
    add_area_light("FillLight", (-0.35, -0.05, 0.15), center, 10.0, 0.60)
    add_area_light("RimLight", (0.10, -0.30, 0.30), center, 18.0, 0.35)

    cam_data = bpy.data.cameras.new("ReviewCam")
    cam_data.clip_start = 0.01
    cam_obj = bpy.data.objects.new("ReviewCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    views = [
        ("revolver_v2_side.png", (0.50, 0.056, -0.012), (0.0, 0.056, -0.012), 55.0),
        ("revolver_v2_3q.png", (0.30, 0.34, 0.10), (0.0, 0.050, -0.005), 50.0),
        ("revolver_v2_fps.png", (-0.11, -0.20, 0.085), (0.0, 0.14, 0.025), 55.0),
    ]

    out_paths: list[Path] = []
    for fname, loc, target, lens in views:
        cam_data.lens = lens
        cam_obj.location = loc
        direction = Vector(target) - Vector(loc)
        cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        out_p = render_dir / fname
        scene.render.filepath = str(out_p)
        bpy.ops.render.render(write_still=True)
        out_paths.append(out_p)
        print(f"[RevolverSAA] Rendered review still -> {out_p}")

    return out_paths


def generate_revolver_saa(review_only: bool = False) -> None:
    """Build, bake, rig, render stills, and optionally export GLB."""
    clean_scene()
    mats = _make_procedural_materials()

    # Build static frame sub-parts + join into mesh_frame
    barrel_parts = build_barrel(mats["blued"], mats["case"])
    frame_parts = build_receiver_frame(mats["case"], mats["blued"])
    brass_parts = build_brass_guard_and_strap(mats["brass"])
    walnut_grip = build_walnut_grip(mats["walnut"])
    mesh_frame = _join_objects(barrel_parts + frame_parts + brass_parts + [walnut_grip], "mesh_frame")

    # Build 4 moving parts
    mesh_cylinder = build_cylinder(mats["blued"])
    mesh_hammer = build_hammer(mats["case"])
    mesh_trigger = build_trigger(mats["blued"])
    mesh_ejector = build_ejector(mats["blued"])

    parts = {
        "frame": mesh_frame,
        "cylinder": mesh_cylinder,
        "hammer": mesh_hammer,
        "trigger": mesh_trigger,
        "ejector": mesh_ejector,
    }

    total_tris = sum(sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons) for obj in parts.values())
    print(f"[RevolverSAA] Built 5 meshes -> total_tris={total_tris}")

    # Bake 2048 textures in Cycles
    tex_dir = Path("build/textures").resolve()
    bake_revolver_maps(list(parts.values()), list(mats.values()), tex_dir, tex_size=2048)

    # Rig 5-bone Skeleton3D
    rig_revolver(parts)

    # Render 3 review stills
    render_review_stills(Path("build/renders").resolve())

    if not review_only:
        out_glb = Path("assets/weapons/revolver/revolver_saa_animated.glb").resolve()
        export_godot_glb(out_glb, export_animations=True, apply_modifiers=False)

        # Also copy baked textures alongside GLB
        import shutil
        for fname in ("T_Revolver_Albedo.png", "T_Revolver_NormalGL.png", "T_Revolver_ORM.png"):
            shutil.copyfile(tex_dir / fname, out_glb.parent / fname)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate Colt SAA 3D asset.")
    parser.add_argument("--review-only", action="store_true", help="Render stills without overwriting Godot assets.")
    args = parser.parse_args(argv)
    generate_revolver_saa(review_only=args.review_only)


if __name__ == "__main__":
    main()
