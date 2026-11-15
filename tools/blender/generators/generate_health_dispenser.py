"""Procedural Blender 5.x generator for the Gothic Health Dispenser,
25mm corrugated pipe conduit segment, and rigged octopus-fang nozzle.

Run via:
    python3 tools/blender/run.py tools/blender/generators/generate_health_dispenser.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[3]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import bmesh
import bpy
import mathutils

from tools.blender.common.armature import (
    add_bone,
    create_action,
    create_armature,
    parent_mesh_to_armature,
    push_action_to_nla,
)
from tools.blender.common.exporter import clean_scene, export_godot_glb
from tools.blender.common.materials import assign_material, create_pbr_material

OUT_DIR = Path("assets/models/health_dispenser")


def _link_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    mat: bpy.types.Material,
    bevel: float = 0.006,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(
            bm,
            geom=list(bm.edges),
            offset=bevel,
            segments=2,
            affect="EDGES",
        )
    bm.to_mesh(mesh)
    bm.free()
    obj.location = location
    assign_material(obj, mat)
    return obj


def _link_cylinder(
    name: str,
    radius: float,
    depth: float,
    segments: int,
    location: tuple[float, float, float],
    rotation_euler: tuple[float, float, float],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
    )
    bm.to_mesh(mesh)
    bm.free()
    obj.location = location
    obj.rotation_euler = rotation_euler
    assign_material(obj, mat)
    return obj


def _add_rivet_row(
    bm: bmesh.types.BMesh,
    points: list[tuple[float, float, float]],
    radius: float = 0.011,
) -> None:
    for pt in points:
        mat_loc = mathutils.Matrix.Translation(pt)
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius, matrix=mat_loc)


def _set_bezier_keyframes(action: bpy.types.Action) -> None:
    fcurves = list(getattr(action, "fcurves", []))
    if not fcurves and hasattr(action, "layers"):
        for layer in action.layers:
            for strip in getattr(layer, "strips", []):
                for bag in getattr(strip, "channelbags", []):
                    fcurves.extend(getattr(bag, "fcurves", []))
    for fcurve in fcurves:
        for kp in fcurve.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"


def generate_chassis() -> None:
    clean_scene()

    mat_rust = create_pbr_material(
        "RustedIron",
        base_color=(0.18, 0.12, 0.09, 1.0),
        metallic=0.82,
        roughness=0.72,
    )
    mat_gothic = create_pbr_material(
        "GothicWroughtMetal",
        base_color=(0.11, 0.11, 0.12, 1.0),
        metallic=0.90,
        roughness=0.48,
    )
    mat_brass = create_pbr_material(
        "TarnishedBrass",
        base_color=(0.38, 0.28, 0.14, 1.0),
        metallic=0.88,
        roughness=0.42,
    )
    mat_dial = create_pbr_material(
        "GaugeDial",
        base_color=(0.68, 0.64, 0.54, 1.0),
        metallic=0.0,
        roughness=0.65,
    )
    mat_screen_bg = create_pbr_material(
        "ScreenBacking",
        base_color=(0.03, 0.05, 0.04, 1.0),
        metallic=0.1,
        roughness=0.25,
    )

    # 1. Main Rusted Backplate (1.50 x 1.50 x 0.14, front face at Z = +0.07)
    _link_box("Backplate", (1.50, 1.50, 0.14), (0.0, 0.0, 0.0), mat_rust, bevel=0.01)

    # 2. Gothic Perimeter Edge Trim + Stepped Corner Plates + Rivets
    edge_t = 0.085
    edge_d = 0.05
    _link_box("TrimTop", (1.52, edge_t, edge_d), (0.0, 0.715, 0.085), mat_gothic, bevel=0.012)
    _link_box("TrimBottom", (1.52, edge_t, edge_d), (0.0, -0.715, 0.085), mat_gothic, bevel=0.012)
    _link_box("TrimLeft", (edge_t, 1.36, edge_d), (-0.715, 0.0, 0.085), mat_gothic, bevel=0.012)
    _link_box("TrimRight", (edge_t, 1.36, edge_d), (0.715, 0.0, 0.085), mat_gothic, bevel=0.012)
    # Inner stepped gothic molding lip
    _link_box("TrimInnerTop", (1.36, 0.028, 0.03), (0.0, 0.66, 0.095), mat_brass, bevel=0.005)
    _link_box("TrimInnerBot", (1.36, 0.028, 0.03), (0.0, -0.66, 0.095), mat_brass, bevel=0.005)

    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            _link_box(
                f"CornerFiligree_{int(sx)}_{int(sy)}",
                (0.20, 0.20, 0.06),
                (sx * 0.65, sy * 0.65, 0.092),
                mat_gothic,
                bevel=0.012,
            )
            _link_box(
                f"CornerCap_{int(sx)}_{int(sy)}",
                (0.11, 0.11, 0.03),
                (sx * 0.67, sy * 0.67, 0.118),
                mat_brass,
                bevel=0.006,
            )

    # Rivet mesh across backplate seams
    rivet_mesh = bpy.data.meshes.new("Rivets_Mesh")
    rivet_obj = bpy.data.objects.new("Rivets", rivet_mesh)
    bpy.context.collection.objects.link(rivet_obj)
    bm_riv = bmesh.new()
    riv_pts: list[tuple[float, float, float]] = []
    for i in range(9):
        t = -0.64 + i * 0.16
        riv_pts.append((t, 0.715, 0.114))
        riv_pts.append((t, -0.715, 0.114))
        riv_pts.append((-0.715, t, 0.114))
        riv_pts.append((0.715, t, 0.114))
    _add_rivet_row(bm_riv, riv_pts, radius=0.013)
    bm_riv.to_mesh(rivet_mesh)
    bm_riv.free()
    assign_material(rivet_obj, mat_gothic)

    # 3. Central Gothic Arch TV Bezel (around X=0.0, Y=0.08) - zero Z-fighting!
    _link_box("ScreenBacking", (0.44, 0.56, 0.02), (0.0, 0.08, 0.08), mat_screen_bg, bevel=0.002)
    _link_box("BezelLeft", (0.06, 0.62, 0.07), (-0.25, 0.08, 0.105), mat_gothic, bevel=0.008)
    _link_box("BezelRight", (0.06, 0.62, 0.07), (0.25, 0.08, 0.105), mat_gothic, bevel=0.008)
    _link_box("BezelBottom", (0.56, 0.07, 0.07), (0.0, -0.22, 0.105), mat_gothic, bevel=0.008)

    # Pointed Gothic Arch Crown (non-overlapping rafters + proud keystone cap)
    for side in (-1.0, 1.0):
        arch = _link_box(
            f"GothicArch_{int(side)}",
            (0.28, 0.07, 0.072),
            (side * 0.14, 0.44, 0.106),
            mat_brass,
            bevel=0.008,
        )
        arch.rotation_euler = (0.0, 0.0, side * -0.52)
    _link_box("GothicKeystone", (0.11, 0.12, 0.082), (0.0, 0.515, 0.112), mat_gothic, bevel=0.01)

    # Top Analog Gauge (cleanly in front of upper arch tympanum, zero clipping)
    _link_cylinder(
        "TopGaugeRim", 0.095, 0.045, 24, (0.0, 0.36, 0.145), (math.pi * 0.5, 0.0, 0.0), mat_brass
    )
    _link_cylinder(
        "TopGaugeFace", 0.076, 0.02, 24, (0.0, 0.36, 0.162), (math.pi * 0.5, 0.0, 0.0), mat_dial
    )
    needle = _link_box("TopGaugeNeedle", (0.008, 0.058, 0.008), (0.01, 0.37, 0.175), mat_gothic, bevel=0.0)
    needle.rotation_euler = (0.0, 0.0, -0.55)

    # Bottom Gargoyle Spout Bracket
    _link_box("SpoutBase", (0.12, 0.14, 0.12), (0.0, -0.34, 0.13), mat_gothic, bevel=0.01)
    spout_snout = _link_box(
        "SpoutSnout", (0.075, 0.12, 0.14), (0.0, -0.43, 0.16), mat_gothic, bevel=0.012
    )
    spout_snout.rotation_euler = (0.35, 0.0, 0.0)

    # 4. Left Pipe Elbow Socket (for 25mm Conduit + Tentacle at X=-0.50, Y=-0.22)
    _link_cylinder(
        "PipeFlange", 0.11, 0.04, 16, (-0.50, -0.22, 0.09), (math.pi * 0.5, 0.0, 0.0), mat_gothic
    )
    _link_cylinder(
        "PipeCollar", 0.065, 0.12, 16, (-0.50, -0.22, 0.14), (math.pi * 0.5, 0.0, 0.0), mat_rust
    )

    # 5. Right Glass Tank Cradle (X=+0.52, Y=-0.34..+0.38)
    _link_cylinder(
        "TankCapBottom", 0.135, 0.09, 20, (0.52, -0.39, 0.19), (0.0, 0.0, 0.0), mat_gothic
    )
    _link_cylinder(
        "TankCapTop", 0.135, 0.09, 20, (0.52, 0.43, 0.19), (0.0, 0.0, 0.0), mat_gothic
    )
    _link_cylinder(
        "TankFeedPipeTop", 0.025, 0.16, 12, (0.52, 0.54, 0.14), (0.2, 0.0, 0.0), mat_brass
    )
    _link_cylinder(
        "TankFeedPipeBot", 0.025, 0.16, 12, (0.52, -0.50, 0.14), (-0.2, 0.0, 0.0), mat_brass
    )
    # Two thin retaining bands around the glass cylinder
    for band_y in (-0.15, 0.19):
        _link_cylinder(
            f"TankBand_{band_y:.2f}",
            0.112,
            0.014,
            24,
            (0.52, band_y, 0.19),
            (0.0, 0.0, 0.0),
            mat_brass,
        )
    # Small Pressure Gauge near tank
    _link_cylinder(
        "SideGaugeRim", 0.065, 0.04, 16, (0.34, 0.46, 0.10), (math.pi * 0.5, 0.0, 0.0), mat_brass
    )
    _link_cylinder(
        "SideGaugeFace", 0.050, 0.015, 16, (0.34, 0.46, 0.118), (math.pi * 0.5, 0.0, 0.0), mat_dial
    )

    # 6. Articulated Twin Iron Shutter Doors (Armature + `close` clip at 60 FPS)
    arm = create_armature("ChassisArmature")
    add_bone(arm, "Root", (0.0, 0.0, 0.0), (0.0, 0.2, 0.0), use_deform=False)
    add_bone(arm, "Shutter_L", (-0.24, 0.08, 0.145), (-0.24, 0.28, 0.145), parent_name="Root")
    add_bone(arm, "Shutter_R", (0.24, 0.08, 0.145), (0.24, 0.28, 0.145), parent_name="Root")
    bpy.ops.object.mode_set(mode="OBJECT")

    # Left door spans X: -0.24 -> 0.0 (width 0.24), Right door spans X: 0.0 -> +0.24
    door_l = _link_box("ShutterDoorLeft", (0.24, 0.58, 0.025), (-0.12, 0.08, 0.145), mat_gothic, bevel=0.004)
    door_r = _link_box("ShutterDoorRight", (0.24, 0.58, 0.025), (0.12, 0.08, 0.145), mat_gothic, bevel=0.004)

    # Weight each door 100% to its bone
    for door_obj, bone_name in ((door_l, "Shutter_L"), (door_r, "Shutter_R")):
        vg = door_obj.vertex_groups.new(name=bone_name)
        vg.add([v.index for v in door_obj.data.vertices], 1.0, "REPLACE")
        parent_mesh_to_armature(door_obj, arm, auto_weights=False)

    # Animate `close` clip: Open (+/-105 deg outward) -> Anticipation -> Slam Shut (0 deg) + Bounce
    action = create_action(arm, "close")
    bpy.context.scene.render.fps = 60
    bpy.ops.object.mode_set(mode="POSE")
    pb_l = arm.pose.bones["Shutter_L"]
    pb_r = arm.pose.bones["Shutter_R"]
    pb_l.rotation_mode = "XYZ"
    pb_r.rotation_mode = "XYZ"

    # Frame 0: Open wide (-105 deg on Y for left, +105 deg on Y for right)
    open_rad = math.radians(105.0)
    keyframes = [
        (0, open_rad),
        (5, math.radians(110.0)),   # 5-frame anticipation
        (22, 0.0),                   # Slam shut
        (27, math.radians(6.0)),     # Rebound
        (36, 0.0),                   # Settle
    ]
    for frame, angle in keyframes:
        pb_l.rotation_euler = (0.0, -angle, 0.0)
        pb_r.rotation_euler = (0.0, angle, 0.0)
        pb_l.keyframe_insert(data_path="rotation_euler", frame=frame)
        pb_r.keyframe_insert(data_path="rotation_euler", frame=frame)

    _set_bezier_keyframes(action)
    bpy.ops.object.mode_set(mode="OBJECT")
    push_action_to_nla(arm, action, track_name="close")

    export_godot_glb(OUT_DIR / "health_dispenser_chassis.glb", export_animations=True)


def generate_conduit_segment() -> None:
    clean_scene()
    mat_conduit = create_pbr_material(
        "ConduitRibbedMetal",
        base_color=(0.24, 0.25, 0.27, 1.0),
        metallic=0.85,
        roughness=0.45,
    )

    mesh = bpy.data.meshes.new("ConduitSegment_Mesh")
    obj = bpy.data.objects.new("ConduitSegment", mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()

    rings = 32
    segs = 14
    height = 1.0
    for r in range(rings + 1):
        t = r / rings
        y = -height * 0.5 + t * height
        # Corrugated 25mm pipe profile (heroic 0.026m - 0.034m radius)
        rad = 0.026 + 0.008 * (0.5 + 0.5 * math.sin(t * math.pi * 16.0))
        ring_verts = []
        for s in range(segs):
            ang = (s / segs) * math.pi * 2.0
            v = bm.verts.new((math.cos(ang) * rad, y, math.sin(ang) * rad))
            ring_verts.append(v)
        if r > 0:
            prev_ring = bm.verts[-segs * 2 : -segs]
            for s in range(segs):
                s_next = (s + 1) % segs
                bm.faces.new((prev_ring[s], prev_ring[s_next], ring_verts[s_next], ring_verts[s]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    assign_material(obj, mat_conduit)
    export_godot_glb(OUT_DIR / "conduit_segment.glb", export_animations=False)


def generate_octopus_nozzle() -> None:
    clean_scene()
    mat_flesh = create_pbr_material(
        "OctopusFlesh",
        base_color=(0.18, 0.11, 0.24, 1.0),
        metallic=0.0,
        roughness=0.18,
    )
    mat_sucker = create_pbr_material(
        "OctopusSucker",
        base_color=(0.34, 0.21, 0.30, 1.0),
        metallic=0.0,
        roughness=0.25,
    )
    mat_fang = create_pbr_material(
        "ChitinFang",
        base_color=(0.74, 0.68, 0.54, 1.0),
        metallic=0.05,
        roughness=0.35,
    )

    # 1. Bulbous tapered tentacle tip along +Y (0.0 -> 0.22m)
    body_mesh = bpy.data.meshes.new("NozzleBody_Mesh")
    body_obj = bpy.data.objects.new("NozzleBody", body_mesh)
    bpy.context.collection.objects.link(body_obj)
    bm = bmesh.new()

    rings = 14
    segs = 14
    for r in range(rings + 1):
        t = r / rings
        y = t * 0.20
        # Bulges slightly near maw then tapers into rim
        rad = 0.036 + 0.018 * math.sin(t * math.pi * 0.85)
        ring_verts = []
        for s in range(segs):
            ang = (s / segs) * math.pi * 2.0
            ring_verts.append(bm.verts.new((math.cos(ang) * rad, y, math.sin(ang) * rad)))
        if r > 0:
            prev_ring = bm.verts[-segs * 2 : -segs]
            for s in range(segs):
                s_next = (s + 1) % segs
                bm.faces.new((prev_ring[s], prev_ring[s_next], ring_verts[s_next], ring_verts[s]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body_mesh)
    bm.free()
    assign_material(body_obj, mat_flesh)

    # 2. Fleshy Suction Cups along underside (-Z)
    sucker_mesh = bpy.data.meshes.new("Suckers_Mesh")
    sucker_obj = bpy.data.objects.new("Suckers", sucker_mesh)
    bpy.context.collection.objects.link(sucker_obj)
    bm_s = bmesh.new()
    for row in range(3):
        y_pos = 0.04 + row * 0.05
        for side in (-1.0, 1.0):
            x_pos = side * 0.022
            z_pos = -0.040
            mat_t = mathutils.Matrix.Translation((x_pos, y_pos, z_pos)) @ mathutils.Matrix.Rotation(
                math.pi * 0.5, 4, "X"
            )
            bmesh.ops.create_cone(
                bm_s,
                cap_ends=True,
                cap_tris=False,
                segments=10,
                radius1=0.013,
                radius2=0.009,
                depth=0.014,
                matrix=mat_t,
            )
    bm_s.to_mesh(sucker_mesh)
    bm_s.free()
    assign_material(sucker_obj, mat_sucker)

    # 3. Rigged Nasty Curved Chitinous Fangs (6 fangs around the circular maw)
    arm = create_armature("NozzleArmature")
    add_bone(arm, "NozzleRoot", (0.0, 0.0, 0.0), (0.0, 0.15, 0.0), use_deform=True)
    fang_count = 6
    for i in range(fang_count):
        ang = (i / fang_count) * math.pi * 2.0
        fx = math.cos(ang) * 0.036
        fz = math.sin(ang) * 0.036
        add_bone(
            arm,
            f"Fang_{i}",
            (fx, 0.19, fz),
            (fx * 0.6, 0.27, fz * 0.6),
            parent_name="NozzleRoot",
        )
    bpy.ops.object.mode_set(mode="OBJECT")

    # Parent body + suckers to NozzleRoot
    for static_part in (body_obj, sucker_obj):
        vg = static_part.vertex_groups.new(name="NozzleRoot")
        vg.add([v.index for v in static_part.data.vertices], 1.0, "REPLACE")
        parent_mesh_to_armature(static_part, arm, auto_weights=False)

    # Create each fang mesh and bind to Fang_i
    for i in range(fang_count):
        ang = (i / fang_count) * math.pi * 2.0
        fx = math.cos(ang) * 0.036
        fz = math.sin(ang) * 0.036
        f_mesh = bpy.data.meshes.new(f"Fang_{i}_Mesh")
        f_obj = bpy.data.objects.new(f"Fang_{i}", f_mesh)
        bpy.context.collection.objects.link(f_obj)
        bm_f = bmesh.new()
        bmesh.ops.create_cone(
            bm_f,
            cap_ends=True,
            cap_tris=False,
            segments=8,
            radius1=0.010,
            radius2=0.001,
            depth=0.085,
        )
        bm_f.to_mesh(f_mesh)
        bm_f.free()
        # Position fang at maw rim pointing forward + slightly inward
        f_obj.location = (fx * 0.85, 0.225, fz * 0.85)
        f_obj.rotation_euler = (-math.sin(ang) * 0.45, 0.0, math.cos(ang) * 0.45)
        assign_material(f_obj, mat_fang)

        vg = f_obj.vertex_groups.new(name=f"Fang_{i}")
        vg.add([v.index for v in f_obj.data.vertices], 1.0, "REPLACE")
        parent_mesh_to_armature(f_obj, arm, auto_weights=False)

    # Animate `bite` clip at 60 FPS (frames 0..24)
    action = create_action(arm, "bite")
    bpy.context.scene.render.fps = 60
    bpy.ops.object.mode_set(mode="POSE")
    for i in range(fang_count):
        pb = arm.pose.bones[f"Fang_{i}"]
        pb.rotation_mode = "XYZ"
        for frame, x_rot in ((0, 0.0), (8, -0.55), (14, 0.45), (24, 0.0)):
            pb.rotation_euler = (x_rot, 0.0, 0.0)
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)
    _set_bezier_keyframes(action)
    bpy.ops.object.mode_set(mode="OBJECT")
    push_action_to_nla(arm, action, track_name="bite")

    export_godot_glb(OUT_DIR / "octopus_nozzle.glb", export_animations=True)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    generate_chassis()
    generate_conduit_segment()
    generate_octopus_nozzle()
    print("[HealthDispenser] All 3 GLBs exported successfully.")


if __name__ == "__main__":
    main()
