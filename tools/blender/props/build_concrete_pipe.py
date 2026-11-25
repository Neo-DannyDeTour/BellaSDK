"""Procedural bell-and-spigot concrete drainage pipe (3 m, 2 m OD) + concave collider.

Run:
    python3 tools/blender/run.py tools/blender/props/build_concrete_pipe.py

Output:
    assets/models/props/concrete_pipe/concrete_pipe.glb
      - concrete_pipe          visual mesh (32 seg, chamfered, cylindrical UV)
      - concrete_pipe-colonly  16 seg concave collider (Godot -> StaticBody3D + trimesh)

Axis: pipe length on Blender Y (Godot Z). Origin bottom-centre. Chain pitch = LENGTH - JOINT_DEPTH.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.exporter import clean_scene, export_godot_glb  # noqa: E402

OUTPUT_PATH: Path = REPO_ROOT / "assets/models/props/concrete_pipe/concrete_pipe.glb"

MESH_NAME: str = "concrete_pipe"
COL_SUFFIX: str = "-colonly"
SEGMENTS: int = 32
COL_SEGMENTS: int = 16
LENGTH: float = 3.0
OUTER_RADIUS: float = 1.0
INNER_RADIUS: float = 0.85
JOINT_DEPTH: float = 0.12
JOINT_MID_RADIUS: float = 0.925
CHAMFER: float = 0.015
HALF_LEN: float = LENGTH * 0.5


def visual_profile() -> list[tuple[float, float]]:
    """Closed (Y, radius) loop. Front -Y = female bell, rear +Y = male spigot."""
    h: float = HALF_LEN
    return [
        # Outer wall (front -> rear)
        (-h, OUTER_RADIUS - CHAMFER),
        (-h + CHAMFER, OUTER_RADIUS),
        (h - JOINT_DEPTH - CHAMFER, OUTER_RADIUS),
        (h - JOINT_DEPTH, OUTER_RADIUS - CHAMFER),
        # Rear spigot step
        (h - JOINT_DEPTH, JOINT_MID_RADIUS),
        (h - CHAMFER, JOINT_MID_RADIUS),
        (h, JOINT_MID_RADIUS - CHAMFER),
        # Rear inner rim
        (h, INNER_RADIUS + CHAMFER),
        (h - CHAMFER, INNER_RADIUS),
        # Inner wall (rear -> front)
        (-h + JOINT_DEPTH + CHAMFER, INNER_RADIUS),
        (-h + JOINT_DEPTH, INNER_RADIUS + CHAMFER),
        # Front bell step
        (-h + JOINT_DEPTH, JOINT_MID_RADIUS),
        (-h + CHAMFER, JOINT_MID_RADIUS),
        (-h, JOINT_MID_RADIUS + CHAMFER),
    ]


def collider_profile() -> list[tuple[float, float]]:
    """Same silhouette as [visual_profile] without chamfers."""
    h: float = HALF_LEN
    return [
        (-h, OUTER_RADIUS),
        (h - JOINT_DEPTH, OUTER_RADIUS),
        (h - JOINT_DEPTH, JOINT_MID_RADIUS),
        (h, JOINT_MID_RADIUS),
        (h, INNER_RADIUS),
        (-h + JOINT_DEPTH, INNER_RADIUS),
        (-h + JOINT_DEPTH, JOINT_MID_RADIUS),
        (-h, JOINT_MID_RADIUS),
    ]


def lathe(
    name: str, profile: list[tuple[float, float]], segments: int, with_uv: bool
) -> bpy.types.Object:
    """Spin [param profile] around the Y axis (offset up by OUTER_RADIUS) into a closed solid.

    All ring loops are marked sharp -> smooth around circumference, flat across profile.
    UV: U = angle (0..1, seam at +X), V = profile perimeter in metres (tiles 1:1).
    """
    mesh: bpy.types.Mesh = bpy.data.meshes.new(name)
    obj: bpy.types.Object = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    bm: bmesh.types.BMesh = bmesh.new()
    num_pts: int = len(profile)

    rings: list[list[bmesh.types.BMVert]] = []
    for i in range(segments):
        angle: float = (2.0 * math.pi * i) / segments
        cos_a: float = math.cos(angle)
        sin_a: float = math.sin(angle)
        ring: list[bmesh.types.BMVert] = []
        for y_pos, rad in profile:
            ring.append(bm.verts.new((cos_a * rad, y_pos, sin_a * rad + OUTER_RADIUS)))
        rings.append(ring)

    # Cumulative perimeter for V coordinate (closing edge included at index num_pts).
    v_coords: list[float] = [0.0]
    for j in range(num_pts):
        y0, r0 = profile[j]
        y1, r1 = profile[(j + 1) % num_pts]
        v_coords.append(v_coords[-1] + math.hypot(y1 - y0, r1 - r0))

    uv_layer: bmesh.types.BMLayerItem | None = bm.loops.layers.uv.new("UVMap") if with_uv else None

    for i in range(segments):
        next_i: int = (i + 1) % segments
        u0: float = i / segments
        u1: float = (i + 1) / segments
        for j in range(num_pts):
            next_j: int = (j + 1) % num_pts
            face: bmesh.types.BMFace = bm.faces.new(
                (rings[i][j], rings[next_i][j], rings[next_i][next_j], rings[i][next_j])
            )
            if uv_layer is not None:
                corner_uvs: tuple[tuple[float, float], ...] = (
                    (u0, v_coords[j]),
                    (u1, v_coords[j]),
                    (u1, v_coords[j + 1]),
                    (u0, v_coords[j + 1]),
                )
                for loop, uv in zip(face.loops, corner_uvs):
                    loop[uv_layer].uv = uv

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

    # Ring edges join same profile index across segments -> equal Y and equal radius.
    for edge in bm.edges:
        v_a, v_b = edge.verts
        same_y: bool = abs(v_a.co.y - v_b.co.y) < 1e-6
        rad_a: float = math.hypot(v_a.co.x, v_a.co.z - OUTER_RADIUS)
        rad_b: float = math.hypot(v_b.co.x, v_b.co.z - OUTER_RADIUS)
        edge.smooth = not (same_y and abs(rad_a - rad_b) < 1e-6)

    for face in bm.faces:
        face.smooth = True

    bm.to_mesh(mesh)
    bm.free()
    return obj


def build_material() -> bpy.types.Material:
    """Placeholder slot; Godot overrides with weathered_concrete.tres."""
    mat: bpy.types.Material = bpy.data.materials.new("M_ConcretePipe")
    mat.use_nodes = True
    bsdf: bpy.types.Node | None = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.38, 0.39, 0.37, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.88
    return mat


def main() -> None:
    clean_scene()

    visual: bpy.types.Object = lathe(MESH_NAME, visual_profile(), SEGMENTS, True)
    visual.data.materials.append(build_material())

    col: bpy.types.Object = lathe(MESH_NAME + COL_SUFFIX, collider_profile(), COL_SEGMENTS, False)
    col.display_type = "WIRE"
    col.hide_render = True

    for obj in (visual, col):
        print(f"[ConcretePipe] {obj.name}: {len(obj.data.vertices)} verts, "
              f"{len(obj.data.polygons)} quads")

    export_godot_glb(OUTPUT_PATH, export_animations=False, export_morph=False)


if __name__ == "__main__":
    main()
