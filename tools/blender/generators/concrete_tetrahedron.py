"""Procedural Blender generator for a Concrete Tetrahedron (Höcker / Pyramid Obstacle).

Builds a 3-legged cast-concrete anti-tank/coastal obstacle (~1.20 m tall) with
flat-grounded feet, beveled weathered edges, metric box-projected UVs, protruding
rusted rebar stubs at the apex, and a Godot 4 '-convcolonly' convex collision proxy.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.collisions import create_convex_collision
from common.exporter import clean_scene, export_godot_glb
from common.materials import create_pbr_material
from mathutils import Matrix, Vector

TARGET_HEIGHT = 1.20
BASE_RADIUS = 0.72
TOP_RADIUS = 0.09
LEG_WIDTH_BOT = 0.23
LEG_WIDTH_TOP = 0.18
UV_TILE_METERS = 2.0  # aggregate_concrete texture covers 2m x 2m
REBAR_RADIUS = 0.009
REBAR_SIDES = 8
RNG_SEED = 42


def _load_image_if_exists(path: Path) -> bpy.types.Image | None:
    if path.is_file():
        return bpy.data.images.load(str(path.resolve()), check_existing=True)
    return None


def _build_leg_bmesh(angle_rad: float, rng: random.Random) -> bmesh.types.BMesh:
    """Create one tapered concrete leg beam cut flat at z=0."""
    bm = bmesh.new()

    dir_xy = Vector((math.cos(angle_rad), math.sin(angle_rad), 0.0))
    perp_xy = Vector((-math.sin(angle_rad), math.cos(angle_rad), 0.0))

    p_bot = dir_xy * BASE_RADIUS - Vector((0.0, 0.0, 0.14))
    p_top = dir_xy * TOP_RADIUS + Vector((0.0, 0.0, TARGET_HEIGHT))

    axis = (p_top - p_bot).normalized()
    side_u = perp_xy.normalized()
    side_v = axis.cross(side_u).normalized()

    hb = LEG_WIDTH_BOT * 0.5
    ht = LEG_WIDTH_TOP * 0.5

    bot_verts = [
        bm.verts.new(p_bot + side_u * (-hb) + side_v * (-hb)),
        bm.verts.new(p_bot + side_u * (hb) + side_v * (-hb)),
        bm.verts.new(p_bot + side_u * (hb) + side_v * (hb)),
        bm.verts.new(p_bot + side_u * (-hb) + side_v * (hb)),
    ]
    top_verts = [
        bm.verts.new(p_top + side_u * (-ht) + side_v * (-ht)),
        bm.verts.new(p_top + side_u * (ht) + side_v * (-ht)),
        bm.verts.new(p_top + side_u * (ht) + side_v * (ht)),
        bm.verts.new(p_top + side_u * (-ht) + side_v * (ht)),
    ]

    bm.faces.new(bot_verts[::-1])
    bm.faces.new(top_verts)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([bot_verts[i], bot_verts[j], top_verts[j], top_verts[i]])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Cut bottom cleanly at z = 0.0 so the leg sits flush on the ground plane.
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    res = bmesh.ops.bisect_plane(
        bm,
        geom=geom,
        plane_co=Vector((0.0, 0.0, 0.0)),
        plane_no=Vector((0.0, 0.0, 1.0)),
        clear_inner=True,
        clear_outer=False,
    )
    cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if cut_edges:
        bmesh.ops.edgeloop_fill(bm, edges=cut_edges)

    # Subdivide long edges slightly so bevel + chipping look weathered.
    long_edges = [e for e in bm.edges if e.calc_length() > 0.30]
    if long_edges:
        bmesh.ops.subdivide_edges(bm, edges=long_edges, cuts=4, use_grid_fill=False)

    # Chamfer edges for rough-cast concrete feel.
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=0.016,
        segments=2,
        affect="EDGES",
        clamp_overlap=True,
    )

    # Subtle weathering displacement (keep z=0 grounded).
    for v in bm.verts:
        if v.co.z > 0.02:
            v.co.x += rng.uniform(-0.006, 0.006)
            v.co.y += rng.uniform(-0.006, 0.006)
            v.co.z += rng.uniform(-0.004, 0.004)
        else:
            v.co.z = 0.0

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _build_rebar_bmesh(angle_rad: float, rng: random.Random) -> bmesh.types.BMesh:
    """Create 2 protruding rusted rebar stubs near the top of one leg."""
    bm = bmesh.new()
    dir_xy = Vector((math.cos(angle_rad), math.sin(angle_rad), 0.0))
    perp_xy = Vector((-math.sin(angle_rad), math.cos(angle_rad), 0.0))

    for idx in range(2):
        offset_side = -0.045 if idx == 0 else 0.045
        start = (
            dir_xy * (TOP_RADIUS + (0.02 if idx == 0 else -0.01))
            + perp_xy * offset_side
            + Vector((0.0, 0.0, TARGET_HEIGHT - 0.02))
        )
        length = rng.uniform(0.08, 0.13)
        tilt = (
            Vector((0.0, 0.0, 1.0))
            + dir_xy * rng.uniform(0.08, 0.38)
            + perp_xy * rng.uniform(-0.22, 0.22)
        ).normalized()
        rot_quat = Vector((0.0, 0.0, 1.0)).rotation_difference(tilt)
        mat = Matrix.Translation(start + tilt * (length * 0.45)) @ rot_quat.to_matrix().to_4x4()

        bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=REBAR_SIDES,
            radius1=REBAR_RADIUS,
            radius2=REBAR_RADIUS * 0.9,
            depth=length,
            matrix=mat,
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _box_project_uvs(bm: bmesh.types.BMesh, tile_meters: float) -> None:
    """Assign metric box-projected UVs across all faces."""
    uv_layer = bm.loops.layers.uv.verify()
    scale = 1.0 / tile_meters
    for face in bm.faces:
        n = face.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            co = loop.vert.co
            if ax == 0:
                u, v = co.y * scale, co.z * scale
            elif ax == 1:
                u, v = co.x * scale, co.z * scale
            else:
                u, v = co.x * scale, co.y * scale
            loop[uv_layer].uv = (u, v)


def build_concrete_tetrahedron(project_root: Path, output_dir: Path) -> dict[str, object]:
    """Generate the concrete tetrahedron GLB and manifest."""
    clean_scene()
    rng = random.Random(RNG_SEED)

    # Load PBR textures for Blender GLB preview / QA
    agg_dir = project_root / "assets/materials/aggregate_concrete/textures"
    rust_dir = project_root / "assets/materials/rusted_steel/textures"

    mat_concrete = create_pbr_material(
        name="aggregate_concrete",
        base_color=(0.68, 0.67, 0.64, 1.0),
        metallic=0.0,
        roughness=0.88,
        base_color_image=_load_image_if_exists(agg_dir / "aggregate_concrete_albedo.png"),
        roughness_image=_load_image_if_exists(agg_dir / "aggregate_concrete_roughness.png"),
        normal_image=_load_image_if_exists(agg_dir / "aggregate_concrete_normal.png"),
        normal_strength=0.65,
    )
    mat_rebar = create_pbr_material(
        name="rusted_steel",
        base_color=(0.35, 0.18, 0.10, 1.0),
        metallic=0.85,
        roughness=0.72,
        base_color_image=_load_image_if_exists(rust_dir / "rusted_steel_albedo.png"),
        roughness_image=_load_image_if_exists(rust_dir / "rusted_steel_roughness.png"),
        normal_image=_load_image_if_exists(rust_dir / "rusted_steel_normal.png"),
        normal_strength=0.45,
    )

    # Combine 3 concrete legs + rebar stubs into one mesh with 2 material slots.
    combined_bm = bmesh.new()
    for i in range(3):
        angle = i * (2.0 * math.pi / 3.0)
        leg_bm = _build_leg_bmesh(angle, rng)
        _box_project_uvs(leg_bm, UV_TILE_METERS)
        for f in leg_bm.faces:
            f.material_index = 0
        tmp_mesh = bpy.data.meshes.new(f"_leg_{i}")
        leg_bm.to_mesh(tmp_mesh)
        leg_bm.free()
        combined_bm.from_mesh(tmp_mesh)
        bpy.data.meshes.remove(tmp_mesh)

        rebar_bm = _build_rebar_bmesh(angle, rng)
        _box_project_uvs(rebar_bm, 0.5)
        for f in rebar_bm.faces:
            f.material_index = 1
        tmp_rebar = bpy.data.meshes.new(f"_rebar_{i}")
        rebar_bm.to_mesh(tmp_rebar)
        rebar_bm.free()
        combined_bm.from_mesh(tmp_rebar)
        bpy.data.meshes.remove(tmp_rebar)

    # Ground min_z to exactly 0.0 and normalize height if needed.
    min_z = min(v.co.z for v in combined_bm.verts)
    for v in combined_bm.verts:
        v.co.z -= min_z

    bmesh.ops.triangulate(combined_bm, faces=combined_bm.faces)
    tri_count = len(combined_bm.faces)

    mesh = bpy.data.meshes.new("concrete_tetrahedron")
    combined_bm.to_mesh(mesh)
    combined_bm.free()

    obj = bpy.data.objects.new("concrete_tetrahedron", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat_concrete)
    obj.data.materials.append(mat_rebar)

    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    dims = [
        round(max(xs) - min(xs), 4),
        round(max(zs) - min(zs), 4),  # Godot Y = Blender Z
        round(max(ys) - min(ys), 4),
    ]

    output_dir.mkdir(parents=True, exist_ok=True)
    glb_path = output_dir / "concrete_tetrahedron.glb"
    export_godot_glb(glb_path, export_animations=False, apply_modifiers=True)

    manifest = {
        "slug": "concrete_tetrahedron",
        "layer": "Layer 1 Environment",
        "source": "procedural_bpy",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": {"x": dims[0], "y": dims[1], "z": dims[2]},
        "materials": [
            "res://assets/materials/aggregate_concrete/aggregate_concrete.tres",
            "res://assets/materials/rusted_steel/rusted_steel.tres",
        ],
        "collision_hint": "ConvexPolygonShape3D (-convcolonly)",
        "glb_path": "res://assets/models/concrete_tetrahedron/concrete_tetrahedron.glb",
    }
    manifest_path = output_dir / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[concrete_tetrahedron] Exported {glb_path} ({tri_count} tris, dims={dims})")
    return manifest


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate Concrete Tetrahedron GLB")
    parser.add_argument(
        "--output-dir",
        default="assets/models/concrete_tetrahedron",
        help="Output directory relative to project root",
    )
    args = parser.parse_args(argv)
    project_root = Path(__file__).resolve().parent.parent.parent.parent
    out_dir = (project_root / args.output_dir).resolve()
    build_concrete_tetrahedron(project_root, out_dir)


if __name__ == "__main__":
    main()
