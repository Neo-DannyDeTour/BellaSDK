"""Modular Pipe Kit generator (1.0m diameter / 0.5m radius).

Origin: entry ring center. Run direction: Blender -Y (Godot -Z). Bends: into Blender -Z.
UVs: U = 0..1 around circumference, V = cumulative_meters / CIRCUMFERENCE (1:1 texels).
"""

import math
from pathlib import Path
import sys
import bmesh
import bpy
from mathutils import Matrix, Vector

# --- CONFIG ---
PIPE_RADIUS = 0.5  # 1.0m outer diameter
BEND_RADIUS = 1.0  # Centerline turn radius
RADIAL_SEGS = 16  # Low-poly faceted silhouette
CIRCUMFERENCE = 2.0 * math.pi * PIPE_RADIUS  # pi * 1.0m ~= 3.1416m
GRID_SPACING_X = 2.5  # Viewport inspection spacing (object location only)
DEFAULT_MAT_NAME = "pipe_metal"

# Spillway: 1.75m visible drop = entry pipe underside (Z -0.5) -> bottom lip (Z -2.25).
# Centerline straight after bend = 2.25 - BEND_RADIUS = 1.25m.
SPILLWAY_DROP_STRAIGHT = 1.25

COLLAR_R_OUT = PIPE_RADIUS + 0.06  # 0.56m
COLLAR_R_IN = PIPE_RADIUS - 0.02  # 0.48m, buried 2cm into pipe wall
COLLAR_HALF_LEN = 0.10  # 0.2m total, centered on origin for seam snapping


def remove_existing_object(name: str) -> None:
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)
    mesh = bpy.data.meshes.get(name)
    if mesh and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def get_or_create_material(name: str = DEFAULT_MAT_NAME) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
    return mat


def new_mesh_object(name: str, x_offset: float) -> bpy.types.Object:
    remove_existing_object(name)
    mesh = bpy.data.meshes.new(name)
    mesh.materials.append(get_or_create_material())
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location.x = x_offset
    return obj


def ring_offset(j: int, radius: float) -> Vector:
    """Ring point in local XZ plane. Seam at bottom (-Z)."""
    phi = (2.0 * math.pi * j) / RADIAL_SEGS - (math.pi * 0.5)
    return Vector((radius * math.cos(phi), 0.0, radius * math.sin(phi)))


def generate_stations(segments: list) -> list:
    """
    Centerline stations: list of (pos: Vector, pitch_x: float, cum_dist: float).
    Starts at (0, 0, 0) facing -Y. Positive bend angle turns down into -Z.
      ('straight', length, steps)
      ('bend', angle_deg, radius, steps)
    """
    pos = Vector((0.0, 0.0, 0.0))
    pitch = 0.0
    cum_dist = 0.0
    stations = [(pos.copy(), pitch, cum_dist)]

    for seg in segments:
        kind = seg[0]
        if kind == "straight":
            length, steps = seg[1], seg[2]
            step_len = length / steps
            tangent = Vector((0.0, -math.cos(pitch), -math.sin(pitch)))
            for _ in range(steps):
                pos = pos + tangent * step_len
                cum_dist += step_len
                stations.append((pos.copy(), pitch, cum_dist))

        elif kind == "bend":
            angle_deg, radius, steps = seg[1], seg[2], seg[3]
            angle_rad = math.radians(angle_deg)
            sign = 1.0 if angle_rad >= 0.0 else -1.0
            # Unit vector toward center of curvature (YZ plane)
            normal = Vector((0.0, math.sin(pitch) * sign, -math.cos(pitch) * sign))
            pivot = pos + normal * radius
            arc_step = (abs(angle_rad) * radius) / steps
            for i in range(1, steps + 1):
                cur_pitch = pitch + angle_rad * (i / steps)
                normal_i = Vector(
                    (0.0, math.sin(cur_pitch) * sign, -math.cos(cur_pitch) * sign)
                )
                pos = pivot - normal_i * radius
                cum_dist += arc_step
                stations.append((pos.copy(), cur_pitch, cum_dist))
            pitch += angle_rad
        else:
            raise ValueError(f"Unknown segment kind: {kind}")

    return stations


def bridge_rings(bm, uv_layer, ring_a, v_a, ring_b, v_b, smooth: bool) -> None:
    """Quad strip between two rings. UV seam closes at u = 1.0."""
    for j in range(RADIAL_SEGS):
        j_next = (j + 1) % RADIAL_SEGS
        u_0 = j / RADIAL_SEGS
        u_1 = (j + 1) / RADIAL_SEGS
        face = bm.faces.new((ring_a[j], ring_a[j_next], ring_b[j_next], ring_b[j]))
        face.smooth = smooth
        face.loops[0][uv_layer].uv = (u_0, v_a)
        face.loops[1][uv_layer].uv = (u_1, v_a)
        face.loops[2][uv_layer].uv = (u_1, v_b)
        face.loops[3][uv_layer].uv = (u_0, v_b)


def create_pipe_from_stations(name: str, stations: list, x_offset: float) -> bpy.types.Object:
    obj = new_mesh_object(name, x_offset)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    rings = []
    for center, pitch, dist in stations:
        rot_mat = Matrix.Rotation(pitch, 4, "X")
        verts = [bm.verts.new(center + (rot_mat @ ring_offset(j, PIPE_RADIUS)))
                 for j in range(RADIAL_SEGS)]
        rings.append((verts, dist / CIRCUMFERENCE))

    for r_idx in range(len(rings) - 1):
        ring_a, v_a = rings[r_idx]
        ring_b, v_b = rings[r_idx + 1]
        bridge_rings(bm, uv_layer, ring_a, v_a, ring_b, v_b, True)

    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def create_collar_flange(name: str, x_offset: float) -> bpy.types.Object:
    """Closed collar ring: 0.56m outer, 0.48m inner, 0.2m long, centered on origin."""
    obj = new_mesh_object(name, x_offset)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    cap_w = COLLAR_R_OUT - COLLAR_R_IN
    length = 2.0 * COLLAR_HALF_LEN
    # (radius, y_pos) profile loop: front cap -> outer barrel -> back cap -> inner bore
    profile = [
        (COLLAR_R_IN, COLLAR_HALF_LEN),
        (COLLAR_R_OUT, COLLAR_HALF_LEN),
        (COLLAR_R_OUT, -COLLAR_HALF_LEN),
        (COLLAR_R_IN, -COLLAR_HALF_LEN),
    ]
    # Cumulative meters along profile; last entry closes loop without V reversal
    v_meters = [0.0, cap_w, cap_w + length, 2.0 * cap_w + length, 2.0 * (cap_w + length)]
    smooth_flags = [False, True, False, True]  # caps flat, barrel + bore smooth

    rings = []
    for rad, y_pos in profile:
        verts = [bm.verts.new(ring_offset(j, rad) + Vector((0.0, y_pos, 0.0)))
                 for j in range(RADIAL_SEGS)]
        rings.append(verts)

    for r_idx in range(len(rings)):
        ring_a = rings[r_idx]
        ring_b = rings[(r_idx + 1) % len(rings)]
        v_a = v_meters[r_idx] / CIRCUMFERENCE
        v_b = v_meters[r_idx + 1] / CIRCUMFERENCE
        bridge_rings(bm, uv_layer, ring_a, v_a, ring_b, v_b, smooth_flags[r_idx])

    # Hard edges on all 4 profile corners so smooth barrel/bore normals stay radial
    for ring in rings:
        for j in range(RADIAL_SEGS):
            edge = bm.edges.get((ring[j], ring[(j + 1) % RADIAL_SEGS]))
            if edge:
                edge.smooth = False

    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def build_pipe_kit() -> list:
    kit_specs = [
        # 1. Spillway: 0.5m entry -> 90 bend -> 1.25m centerline drop (Z +0.5 .. -2.25)
        ("pipe_tall_spillway_90", [
            ("straight", 0.5, 1),
            ("bend", 90.0, BEND_RADIUS, 5),
            ("straight", SPILLWAY_DROP_STRAIGHT, 2),
        ]),
        # 2. Straight 1.0m
        ("pipe_straight_1m", [
            ("straight", 1.0, 1),
        ]),
        # 3. Straight 3.0m (3 rings for vertex lighting / deformation)
        ("pipe_straight_3m", [
            ("straight", 3.0, 3),
        ]),
        # 4. Symmetric 90: 1.0m -> 90 bend -> 1.0m (2.5m bbox height/reach)
        ("pipe_bend_90_mid", [
            ("straight", 1.0, 1),
            ("bend", 90.0, BEND_RADIUS, 5),
            ("straight", 1.0, 1),
        ]),
        # 5. Symmetric 45: 0.75m -> 45 bend -> 0.75m
        ("pipe_bend_45", [
            ("straight", 0.75, 1),
            ("bend", 45.0, BEND_RADIUS, 3),
            ("straight", 0.75, 1),
        ]),
        # 6. S-offset: drops elevation, exits parallel to entry
        ("pipe_offset_45_s", [
            ("straight", 0.5, 1),
            ("bend", 45.0, BEND_RADIUS, 3),
            ("straight", 1.0, 1),
            ("bend", -45.0, BEND_RADIUS, 3),
            ("straight", 0.5, 1),
        ]),
        # 7. 180 U-turn
        ("pipe_uturn_180", [
            ("straight", 0.5, 1),
            ("bend", 180.0, BEND_RADIUS, 10),
            ("straight", 0.5, 1),
        ]),
    ]

    created = []
    for idx, (name, segments) in enumerate(kit_specs):
        stations = generate_stations(segments)
        created.append(create_pipe_from_stations(name, stations, idx * GRID_SPACING_X))

    created.append(create_collar_flange("pipe_collar_flange", len(kit_specs) * GRID_SPACING_X))

    # Context-free selection (works from Text Editor, headless, or MCP)
    view_layer = bpy.context.view_layer
    for obj in view_layer.objects:
        obj.select_set(False)
    for obj in created:
        obj.select_set(True)
    if created:
        view_layer.objects.active = created[0]

    for obj in created:
        zs = [v.co.z for v in obj.data.vertices]
        ys = [v.co.y for v in obj.data.vertices]
        print(f"[PipeKit] {obj.name}: verts={len(obj.data.vertices)} "
              f"Z=[{min(zs):+.3f}, {max(zs):+.3f}] Y=[{min(ys):+.3f}, {max(ys):+.3f}]")
    return created


def export_pipe_kit(objects: list, export_dir: Path) -> None:
    """Export each module at origin (0,0,0) with a sibling col-colonly trimesh."""
    export_dir.mkdir(parents=True, exist_ok=True)
    view_layer = bpy.context.view_layer
    collection = bpy.context.scene.collection

    for obj in objects:
        orig_x = obj.location.x
        obj.location.x = 0.0

        # Sibling trimesh collision proxy for Godot -colonly import
        col_mesh = obj.data.copy()
        col_mesh.materials.clear()
        col_obj = bpy.data.objects.new("col-colonly", col_mesh)
        collection.objects.link(col_obj)
        col_obj.location = (0.0, 0.0, 0.0)

        for scene_obj in view_layer.objects:
            scene_obj.select_set(False)
        obj.select_set(True)
        col_obj.select_set(True)
        view_layer.objects.active = obj

        out_path = export_dir / f"{obj.name}.glb"
        bpy.ops.export_scene.gltf(
            filepath=str(out_path),
            export_format="GLB",
            export_yup=True,
            export_apply=True,
            export_materials="EXPORT",
            export_attributes=True,
            export_animations=False,
            use_selection=True,
        )
        print(f"[PipeKit] Exported: {out_path}")

        bpy.data.objects.remove(col_obj, do_unlink=True)
        if col_mesh.users == 0:
            bpy.data.meshes.remove(col_mesh)
        obj.location.x = orig_x

    for scene_obj in view_layer.objects:
        scene_obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    if objects:
        view_layer.objects.active = objects[0]


def _parse_export_dir() -> Path | None:
    if "--" not in sys.argv:
        return None
    extra = sys.argv[sys.argv.index("--") + 1:]
    for idx, arg in enumerate(extra):
        if arg == "--export-dir" and idx + 1 < len(extra):
            return Path(extra[idx + 1]).resolve()
    return None


kit_objects = build_pipe_kit()
_export_dir = _parse_export_dir()
if _export_dir is not None:
    export_pipe_kit(kit_objects, _export_dir)
