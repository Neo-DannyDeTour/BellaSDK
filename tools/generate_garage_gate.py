"""Procedural generator for sectional garage gate panel and frame meshes.

Run headless:
blender -b -P tools/generate_garage_gate.py
"""
import math
import os

import bmesh
import bpy

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


def unwrap_box(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=1.0)
    bpy.ops.object.mode_set(mode="OBJECT")


def build_slotted_panel() -> bpy.types.Object:
    # 3.0m wide (X), 0.05m thick (Y), 0.56m base height + 0.04m teeth = 0.60m total (Z)
    width = 3.0
    depth = 0.05
    base_h = 0.56
    slot_h = 0.04
    num_slots = 7
    slot_w = 0.28

    # 8 posts + 7 slots = 15 segments along X
    post_w = (width - (num_slots * slot_w)) / (num_slots + 1)
    x_coords = [-width * 0.5]
    for _ in range(num_slots):
        x_coords.append(x_coords[-1] + post_w)
        x_coords.append(x_coords[-1] + slot_w)
    x_coords.append(width * 0.5)

    y_coords = [-depth * 0.5, depth * 0.5]
    z_coords = [0.0, base_h, base_h + slot_h]

    bm = bmesh.new()
    verts = {}
    for ix, x in enumerate(x_coords):
        for iy, y in enumerate(y_coords):
            for iz, z in enumerate(z_coords):
                verts[(ix, iy, iz)] = bm.verts.new((x, y, z))

    def add_box(ix: int, iz: int) -> None:
        v000 = verts[(ix, 0, iz)]
        v100 = verts[(ix + 1, 0, iz)]
        v110 = verts[(ix + 1, 1, iz)]
        v010 = verts[(ix, 1, iz)]
        v001 = verts[(ix, 0, iz + 1)]
        v101 = verts[(ix + 1, 0, iz + 1)]
        v111 = verts[(ix + 1, 1, iz + 1)]
        v011 = verts[(ix, 1, iz + 1)]
        for f_verts in [
            (v000, v010, v110, v100),
            (v001, v101, v111, v011),
            (v000, v100, v101, v001),
            (v110, v010, v011, v111),
            (v010, v000, v001, v011),
            (v100, v110, v111, v101),
        ]:
            try:
                bm.faces.new(f_verts)
            except ValueError:
                pass

    for ix in range(len(x_coords) - 1):
        # Solid lower plate
        add_box(ix, 0)
        # Interlocking top teeth on even indices (posts); odd indices stay open slots
        if ix % 2 == 0:
            add_box(ix, 1)

    # Remove internal shared faces for clean manifold mesh
    inner_faces = [
        f
        for f in bm.faces
        if len(f.loops) == 4 and all(len(e.link_faces) > 2 for e in f.edges)
    ]
    bmesh.ops.delete(bm, geom=inner_faces, context="FACES_ONLY")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    for e in bm.edges:
        if e.calc_face_angle(0.0) > math.radians(60):
            e.smooth = False

    mesh = bpy.data.meshes.new("SM_GaragePanel")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("SM_GaragePanel", mesh)
    bpy.context.collection.objects.link(obj)
    set_weighted_normals(obj)
    unwrap_box(obj)
    return obj


def build_static_frame() -> bpy.types.Object:
    bm = bmesh.new()
    track_x_offset = 1.54
    track_w = 0.04
    track_d = 0.06
    v_height = 2.05
    radius = 0.35
    h_length = 2.40
    arc_steps = 8

    # Build L and R tracks (Vertical -> 90 deg Radius -> Horizontal)
    for side in (-1.0, 1.0):
        cx = side * track_x_offset
        pts = [(0.0, 0.0), (0.0, v_height)]
        for s in range(1, arc_steps + 1):
            ang = (math.pi * 0.5) * (s / arc_steps)
            py = radius * (1.0 - math.cos(ang))
            pz = v_height + radius * math.sin(ang)
            pts.append((py, pz))
        pts.append((radius + h_length, v_height + radius))

        rings = []
        for idx, (py, pz) in enumerate(pts):
            ring = [
                bm.verts.new(
                    (cx - track_w * 0.5, py - track_d * 0.5, pz - track_w * 0.5)
                ),
                bm.verts.new(
                    (cx + track_w * 0.5, py - track_d * 0.5, pz - track_w * 0.5)
                ),
                bm.verts.new(
                    (cx + track_w * 0.5, py + track_d * 0.5, pz + track_w * 0.5)
                ),
                bm.verts.new(
                    (cx - track_w * 0.5, py + track_d * 0.5, pz + track_w * 0.5)
                ),
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

    # Torsion shaft + 2 torsion springs + 2 cable drums at Z = 2.55m, Y = 0.08m
    def add_x_cylinder(
        x0: float, x1: float, rad: float, segs: int = 12
    ) -> None:
        r0 = []
        r1 = []
        for s in range(segs):
            ang = (2.0 * math.pi * s) / segs
            vy = 0.08 + rad * math.cos(ang)
            vz = 2.55 + rad * math.sin(ang)
            r0.append(bm.verts.new((x0, vy, vz)))
            r1.append(bm.verts.new((x1, vy, vz)))
        bm.faces.new(r0[::-1])
        bm.faces.new(r1)
        for s in range(segs):
            sn = (s + 1) % segs
            bm.faces.new((r0[s], r0[sn], r1[sn], r1[s]))

    # Torsion shaft
    add_x_cylinder(-1.60, 1.60, 0.018, 10)
    # Left & Right Torsion Springs
    add_x_cylinder(-0.85, -0.15, 0.045, 14)
    add_x_cylinder(0.15, 0.85, 0.045, 14)
    # Left & Right Cable Drums
    add_x_cylinder(-1.52, -1.42, 0.075, 16)
    add_x_cylinder(1.42, 1.52, 0.075, 16)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for e in bm.edges:
        if e.calc_face_angle(0.0) > math.radians(60):
            e.smooth = False

    mesh = bpy.data.meshes.new("SM_GarageFrame")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("SM_GarageFrame", mesh)
    bpy.context.collection.objects.link(obj)
    set_weighted_normals(obj)
    unwrap_box(obj)
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
