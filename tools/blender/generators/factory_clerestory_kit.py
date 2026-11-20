"""Procedural Blender generator for high-clerestory 4x2 factory windows.

Generates two clean-room industrial clerestory assets in assets/models/factory_shells/:
1. factory_clerestory_window.glb  - 2.2m W x 1.15m H x 0.16m D standalone 4x2 steel window (2 broken panes)
2. factory_clerestory_wall_4m.glb - 4.0m W x 1.60m H x 0.35m D concrete upper-wall strip + 4x2 window

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Clean world-metric box UVs (2.0m tile).
- Material slots:
  - factory_clerestory_window: ['steel', 'glass']
  - factory_clerestory_wall_4m: ['concrete', 'steel', 'glass']
"""

from __future__ import annotations

import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import create_pbr_material
from mathutils import Vector

_REPO_ROOT = _TOOL_DIR.parent.parent


def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> None:
    """Append an axis-aligned box with optional edge chamfer to a BMesh."""
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        return

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

    if chamfer > 0.0:
        edges = list({e for f in faces for e in f.edges})
        bmesh.ops.bevel(
            bm,
            geom=edges,
            offset=chamfer,
            offset_type="OFFSET",
            segments=1,
            profile=0.5,
            affect="EDGES",
            clamp_overlap=True,
        )


def _apply_box_uvs(bm: bmesh.types.BMesh, tile_meters: float = 2.0) -> None:
    """Assign world-metric triplanar box UVs."""
    uv_layer = bm.loops.layers.uv.verify()
    inv = 1.0 / tile_meters
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * inv, co.y * inv
            elif ax >= ay and ax >= az:
                u, v = co.y * inv, co.z * inv
            else:
                u, v = co.x * inv, co.z * inv
            loop[uv_layer].uv = (u, v)


def _add_clerestory_4x2_window(
    bm: bmesh.types.BMesh,
    center_x: float,
    z_bottom: float,
    width: float,
    height: float,
    depth: float,
    steel_idx: int,
    glass_idx: int,
    broken_panes: set[tuple[int, int]],
) -> None:
    """Add a 4x2 steel-mullion clerestory window frame + panes into BMesh."""
    hx = width * 0.5
    hy = depth * 0.5
    frame_t = 0.055
    mullion_w = 0.032
    mullion_d = 0.048

    x0, x1 = center_x - hx, center_x + hx
    z0, z1 = z_bottom, z_bottom + height

    # Outer steel perimeter frame
    _add_box_bm(bm, (x0, -hy, z0), (x1, hy, z0 + frame_t), steel_idx, 0.004)
    _add_box_bm(bm, (x0, -hy, z1 - frame_t), (x1, hy, z1), steel_idx, 0.004)
    _add_box_bm(bm, (x0, -hy, z0 + frame_t), (x0 + frame_t, hy, z1 - frame_t), steel_idx, 0.004)
    _add_box_bm(bm, (x1 - frame_t, -hy, z0 + frame_t), (x1, hy, z1 - frame_t), steel_idx, 0.004)

    ix0, ix1 = x0 + frame_t, x1 - frame_t
    iz0, iz1 = z0 + frame_t, z1 - frame_t
    inner_w = ix1 - ix0
    inner_h = iz1 - iz0
    col_w = inner_w / 4.0
    row_h = inner_h / 2.0

    # 3 vertical mullions + 1 center horizontal transom bar
    for c in range(1, 4):
        mx = ix0 + c * col_w
        _add_box_bm(
            bm,
            (mx - mullion_w * 0.5, -mullion_d * 0.5, iz0),
            (mx + mullion_w * 0.5, mullion_d * 0.5, iz1),
            steel_idx,
            0.002,
        )
    mz = iz0 + row_h
    _add_box_bm(
        bm,
        (ix0, -mullion_d * 0.5, mz - mullion_w * 0.5),
        (ix1, mullion_d * 0.5, mz + mullion_w * 0.5),
        steel_idx,
        0.002,
    )

    # 8 panes (skip broken ones, add small jagged corner shard on broken panes)
    for col in range(4):
        for row in range(2):
            px0 = ix0 + col * col_w + (mullion_w * 0.45 if col > 0 else 0.0)
            px1 = ix0 + (col + 1) * col_w - (mullion_w * 0.45 if col < 3 else 0.0)
            pz0 = iz0 + row * row_h + (mullion_w * 0.45 if row > 0 else 0.0)
            pz1 = iz0 + (row + 1) * row_h - (mullion_w * 0.45 if row < 1 else 0.0)
            if (col, row) in broken_panes:
                # Small jagged corner glass shard for industrial decay detail
                shard_w = (px1 - px0) * 0.28
                shard_h = (pz1 - pz0) * 0.32
                _add_box_bm(bm, (px0, -0.004, pz0), (px0 + shard_w, 0.004, pz0 + shard_h), glass_idx)
            else:
                _add_box_bm(bm, (px0, -0.004, pz0), (px1, 0.004, pz1), glass_idx)


def _finalize_and_export(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    out_path: Path,
) -> None:
    """Finalize BMesh normals/UVs, print stats, and export GLB."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_box_uvs(bm, tile_meters=2.0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for m in materials:
        mesh.materials.append(m)

    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    bmin = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    bmax = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    export_godot_glb(str(out_path))
    print(f"[{name}] tris={tri_count} bbox_blender=({bmin.x:.3f}..{bmax.x:.3f}, {bmin.y:.3f}..{bmax.y:.3f}, {bmin.z:.3f}..{bmax.z:.3f}) -> {out_path}")


def build_clerestory_window(out_path: Path) -> None:
    """Generate standalone 2.2m W x 1.15m H x 0.16m D 4x2 clerestory window."""
    clean_scene()
    steel_mat = create_pbr_material("steel", (0.22, 0.20, 0.19, 1.0), metallic=0.82, roughness=0.58)
    glass_mat = create_pbr_material("glass", (0.46, 0.54, 0.60, 0.38), metallic=0.05, roughness=0.24)
    bm = bmesh.new()
    _add_clerestory_4x2_window(
        bm,
        center_x=0.0,
        z_bottom=0.0,
        width=2.20,
        height=1.15,
        depth=0.16,
        steel_idx=0,
        glass_idx=1,
        broken_panes={(1, 0), (2, 1)},
    )
    _finalize_and_export("factory_clerestory_window", bm, [steel_mat, glass_mat], out_path)


def build_clerestory_wall_4m(out_path: Path) -> None:
    """Generate 4.0m W x 1.60m H x 0.35m D concrete clerestory upper-wall strip."""
    clean_scene()
    concrete_mat = create_pbr_material("concrete", (0.45, 0.44, 0.42, 1.0), metallic=0.0, roughness=0.90)
    steel_mat = create_pbr_material("steel", (0.22, 0.20, 0.19, 1.0), metallic=0.82, roughness=0.58)
    glass_mat = create_pbr_material("glass", (0.46, 0.54, 0.60, 0.38), metallic=0.05, roughness=0.24)

    bm = bmesh.new()
    # Concrete wall 4.0m wide, 1.60m tall, 0.35m thick, opening 2.20m W x 1.15m H at Z[0.225, 1.375]
    # Left & right concrete pillars
    _add_box_bm(bm, (-2.00, -0.175, 0.0), (-1.10, 0.175, 1.60), 0, 0.008)
    _add_box_bm(bm, (1.10, -0.175, 0.0), (2.00, 0.175, 1.60), 0, 0.008)
    # Bottom spandrel + top lintel
    _add_box_bm(bm, (-1.10, -0.175, 0.0), (1.10, 0.175, 0.225), 0, 0.006)
    _add_box_bm(bm, (-1.10, -0.175, 1.375), (1.10, 0.175, 1.60), 0, 0.006)
    # Concrete sill ledge
    _add_box_bm(bm, (-1.14, -0.205, 0.195), (1.14, 0.205, 0.235), 0, 0.005)
    # Top steel I-beam lip
    _add_box_bm(bm, (-2.00, -0.19, 1.54), (2.00, 0.19, 1.60), 1, 0.004)

    _add_clerestory_4x2_window(
        bm,
        center_x=0.0,
        z_bottom=0.225,
        width=2.20,
        height=1.15,
        depth=0.16,
        steel_idx=1,
        glass_idx=2,
        broken_panes={(1, 0), (3, 1)},
    )
    _finalize_and_export("factory_clerestory_wall_4m", bm, [concrete_mat, steel_mat, glass_mat], out_path)


def main() -> None:
    out_dir = _REPO_ROOT / "assets/models/factory_shells"
    build_clerestory_window(out_dir / "factory_clerestory_window.glb")
    build_clerestory_wall_4m(out_dir / "factory_clerestory_wall_4m.glb")


if __name__ == "__main__":
    main()
