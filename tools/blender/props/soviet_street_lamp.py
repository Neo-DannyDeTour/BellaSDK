"""Procedural Soviet Street Lamp Post with Gooseneck & Cobra-Head Luminaire (5.80m H).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-11-04_03-40.png
- /home/dkd/Downloads/hl2_refs/2026-11-05_19-39_2.png

Features:
- Square bolted steel base flange plate (min_y = 0) with 4 anchor bolts
- Tapered concrete/galvanized-steel column with lower inspection hatch & mid-shaft joint collar
- Smooth curved tubular gooseneck arm sweeping up & forward
- Cobra-head luminaire housing with recessed dark bezel & weathered frosted glass diffuser
- 2048x2048 PBR atlas (galvanized/concrete pole, dark iron hardware, aluminum hood, glass diffuser)

Usage:
    /usr/bin/python3 tools/blender/props/soviet_street_lamp.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/soviet_street_lamp.py
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.domestic_kit import (  # noqa: E402
    Kit,
    _make_material,
    _paths,
    _unwrap_regions,
    ellipse,
    generate_atlas,
)

CFG: dict = {
    "slug": "soviet_street_lamp",
    "node_name": "SovietStreetLamp",
    "mat_name": "M_SovietStreetLamp",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-11-04_03-40.png",
    "tri_budget": 1400,
    "body": "static",
    "seed": 110403,
    "regions": [
        # 0: Weathered galvanized steel / spun concrete-gray tapered pole shaft
        {"base": (148, 150, 146), "var": 0.11, "grime": 0.36, "rust": 0.10, "rough": 0.68,
         "metal": 0.35, "normal": 2.2},
        # 1: Dark weathered cast-iron base plate, bolts, hatch door & shaft collar
        {"base": (70, 72, 74), "var": 0.10, "grime": 0.32, "rust": 0.38, "rough": 0.56,
         "metal": 0.72, "normal": 2.0},
        # 2: Weathered aluminum/gray-enamel cobra-head luminaire hood & gooseneck
        {"base": (132, 134, 130), "var": 0.10, "grime": 0.30, "rust": 0.16, "rough": 0.50,
         "metal": 0.68, "normal": 1.8},
        # 3: Weathered frosted glass/acrylic luminaire diffuser lens
        {"base": (214, 208, 190), "var": 0.06, "grime": 0.20, "rust": 0.0, "rough": 0.24,
         "metal": 0.0, "normal": 0.8},
    ],
}


def _paint_lamp(idx: int, maps: dict, half: int) -> None:
    """Add vertical rain streaks on pole (0) and frosted rim grime on diffuser (3)."""
    import numpy as np

    if idx == 0:
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        streak = 0.5 + 0.5 * np.sin((xx / float(half)) * 28.0 * math.pi)
        # Subtle fine concrete/galvanized grain
        maps["alb"] = np.clip(maps["alb"] * (0.94 + 0.08 * streak[..., None]), 35.0, 235.0)
        maps["rough"] = np.clip(maps["rough"] + 0.05 * (1.0 - streak), 0.50, 0.90)
    elif idx == 3:
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        nx = (xx / float(half) - 0.5) * 2.0
        ny = (yy / float(half) - 0.5) * 2.0
        r2 = np.clip(nx * nx + ny * ny, 0.0, 1.5)
        rim = np.clip((r2 - 0.55) / 0.65, 0.0, 1.0)
        maps["alb"] = np.clip(maps["alb"] * (1.02 - 0.28 * rim[..., None]), 45.0, 235.0)
        maps["rough"] = np.clip(0.20 + 0.22 * rim, 0.16, 0.48)
        maps["metal"] = np.zeros((half, half), dtype=np.float32)


def _circle_ring(cx: float, cy: float, z: float, r: float, segs: int) -> list[tuple[float, float, float]]:
    return [
        (cx + r * math.cos(2.0 * math.pi * k / segs), cy + r * math.sin(2.0 * math.pi * k / segs), z)
        for k in range(segs)
    ]


def build(kit: Kit) -> None:
    """Build 5.80m Soviet gooseneck cobra-head street lamp grounded at origin (0, 0, 0)."""
    # 1. Grounded square steel base flange plate (min_z = 0.0) + 4 anchor bolts
    kit.box((0.0, 0.0, 0.012), (0.36, 0.36, 0.024), 1, bevel=0.004)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.cyl((sx * 0.135, sy * 0.135, 0.032), (0.0, 0.0, 1.0), 0.016, 0.018, 6, 1)

    # 2. Stepped base pedestal collar + access hatch door (z = 0.024 -> 0.85m)
    segs_pole = 10
    base_rings = [
        _circle_ring(0.0, 0.0, 0.024, 0.132, segs_pole),
        _circle_ring(0.0, 0.0, 0.120, 0.122, segs_pole),
        _circle_ring(0.0, 0.0, 0.820, 0.106, segs_pole),
        _circle_ring(0.0, 0.0, 0.860, 0.096, segs_pole),
    ]
    kit.loft(base_rings, [0, 0, 1], cap_start=True, cap_end=False)

    # Raised access hatch door on front-side (-Y) of lower base section
    kit.box((0.0, -0.108, 0.460), (0.105, 0.026, 0.320), 1, bevel=0.006)

    # 3. Main tapered column (z = 0.860 -> 4.92m) with joint collar sleeve at z = 3.45m
    lower_rings = [
        _circle_ring(0.0, 0.0, 0.860, 0.096, segs_pole),
        _circle_ring(0.0, 0.0, 3.420, 0.074, segs_pole),
    ]
    kit.loft(lower_rings, 0, cap_start=False, cap_end=False)

    # Joint collar sleeve
    kit.cyl((0.0, 0.0, 3.455), (0.0, 0.0, 1.0), 0.082, 0.075, segs_pole, 1)

    upper_rings = [
        _circle_ring(0.0, 0.0, 3.490, 0.072, segs_pole),
        _circle_ring(0.0, 0.0, 4.920, 0.056, segs_pole),
    ]
    kit.loft(upper_rings, 0, cap_start=False, cap_end=False)

    # Upper clamp collar where gooseneck attaches
    kit.cyl((0.0, 0.0, 4.925), (0.0, 0.0, 1.0), 0.064, 0.060, segs_pole, 1)

    # 4. Smooth curved gooseneck arm (z=4.92 -> apex ~5.65, reaching y=-1.10)
    arm_pts = [
        (0.0, 0.000, 4.920),
        (0.0, -0.055, 5.140),
        (0.0, -0.175, 5.330),
        (0.0, -0.355, 5.470),
        (0.0, -0.575, 5.565),
        (0.0, -0.825, 5.635),
        (0.0, -1.080, 5.680),
    ]
    arm_radii = [0.054, 0.050, 0.046, 0.043, 0.040, 0.037, 0.035]
    kit.tube(arm_pts, arm_radii, segs=10, region=2, cap=True)

    # 5. Cobra-head luminaire housing + weathered diffuser (nose reaches y=-1.68, top reaches z=5.80)
    # Tilted up slightly (~9 deg) matching 2026-11-04_03-40.png
    from mathutils import Matrix, Vector

    pivot = Vector((0.0, -1.075, 5.680))
    tilt = Matrix.Rotation(math.radians(-9.0), 3, "X")

    def _xform_ring(ring_local: list[tuple[float, float, float]]) -> list[tuple[float, float, float]]:
        return [tuple(pivot + tilt @ Vector(p)) for p in ring_local]

    # Housing loft along local -Y (neck y=0.0 to nose y=-0.62), top Z=+0.088 -> world ~5.80m
    # Check exact top Z: pivot.z=5.680, at y=-0.42, local z=+0.082 ->
    # world_z = 5.680 + (-sin(-9)*(-0.42) + cos(-9)*0.082) = 5.680 + (-0.1564*0.42) + 0.081?
    # Wait: Rotation(-9 deg, X): y' = y*c - z*s, z' = y*s + z*c.
    # For y < 0 and angle = -9 deg: s = sin(-9) = -0.1564, so y*s > 0!
    # At y = -0.44, z = +0.052: y*s + z*c = (-0.44)*(-0.1564) + 0.052*0.9877 = +0.0688 + 0.0514 = +0.1202
    # 5.680 + 0.120 = 5.800m!
    head_specs = [
        # (local_y, width, height, local_z_center, power)
        (0.02, 0.092, 0.076, 0.000, 2.0),
        (-0.11, 0.125, 0.092, 0.002, 2.2),
        (-0.23, 0.245, 0.112, 0.004, 2.5),
        (-0.41, 0.285, 0.114, 0.002, 2.6),
        (-0.56, 0.230, 0.096, 0.002, 2.3),
        (-0.63, 0.115, 0.062, 0.004, 2.0),
    ]
    head_rings = []
    for ly, hw, hh, lz, pwr in head_specs:
        # Build YZ-cross-section ring (normal along -Y, CCW around -Y)
        pts_local = []
        n_seg = 12
        e = 2.0 / pwr
        for k in range(n_seg):
            t = 2.0 * math.pi * k / n_seg
            cx, cz = math.cos(t), math.sin(t)
            px = math.copysign(abs(cx) ** e, cx) * hw * 0.5
            pz = lz + math.copysign(abs(cz) ** e, cz) * hh * 0.5
            pts_local.append((px, ly, pz))
        head_rings.append(_xform_ring(pts_local))
    kit.loft(head_rings, 2, cap_start=True, cap_end=True)

    # Convex oval diffuser lens on the underside of the cobra-head housing
    diff_specs = [
        # (local_y, width, depth_z)
        (-0.40, 0.210, -0.048),
        (-0.40, 0.165, -0.064),
        (-0.40, 0.090, -0.072),
    ]
    diff_rings = []
    for idx_r, (cy, dw, dz) in enumerate(diff_specs):
        dl = [0.34, 0.26, 0.14][idx_r]
        ring_xz = ellipse(0.0, cy, dz, dw, dl, n=12, power=2.2)
        # Flip winding so dome bulges downward (-Z) cleanly
        diff_rings.append(_xform_ring(list(reversed(ring_xz))))
    kit.loft(diff_rings, 3, cap_start=False, cap_end=True)


def _write_lamp_tscn(paths: dict) -> None:
    """Write StaticBody3D scene with pole-centered BoxShape3D so sidewalks stay clear."""
    slug = CFG["slug"]
    node = CFG["node_name"]
    lines = [
        "[gd_scene load_steps=4 format=3]",
        "",
        f'[ext_resource type="PackedScene" path="res://assets/models/{slug}/{slug}.glb" id="1_glb"]',
        f'[ext_resource type="Material" path="res://assets/models/{slug}/{slug}.tres" id="2_mat"]',
        "",
        '[sub_resource type="BoxShape3D" id="BoxShape3D_1"]',
        "size = Vector3(0.36, 5.8, 0.36)",
        "",
        f'[node name="{node}" type="StaticBody3D"]',
        "collision_layer = 1",
        "collision_mask = 0",
        "",
        '[node name="Model" parent="." instance=ExtResource("1_glb")]',
        "",
        f'[node name="{node}" parent="Model" index="0"]',
        "layers = 1",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="."]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.0, 2.9, 0.0)",
        'shape = SubResource("BoxShape3D_1")',
        "",
        '[editable path="Model"]',
        "",
    ]
    paths["tscn"].parent.mkdir(parents=True, exist_ok=True)
    paths["tscn"].write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    """Entry point: '--gen-textures' builds atlas; otherwise builds Blender mesh & exports."""
    if "--gen-textures" in sys.argv:
        generate_atlas(CFG, _paint_lamp)
        return

    import bpy

    from tools.blender.common.domestic_kit import SHARP_ANGLE
    from tools.blender.common.exporter import clean_scene, export_godot_glb

    paths = _paths(CFG)
    if not all(paths[k].is_file() for k in ("albedo", "normal", "orm", "tres")):
        subprocess.run(["/usr/bin/python3", str(Path(__file__).resolve()), "--gen-textures"], check=True)

    clean_scene()
    kit = Kit()
    build(kit)
    bm = kit.bm
    kit.bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) != 2 or e.calc_face_angle(0.0) > SHARP_ANGLE:
            e.smooth = False

    name = CFG["node_name"]
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    n_regions = len(CFG["regions"])
    for r in range(n_regions):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    _unwrap_regions(mesh, list(range(n_regions)))

    for p in mesh.polygons:
        p.material_index = 0
    mesh.materials.clear()
    mesh.materials.append(_make_material(CFG, paths))

    # Ground min_z=0 and scale height strictly to 5.80m while preserving pole center at (0, 0)
    min_z = min(v.co.z for v in mesh.vertices)
    max_z = max(v.co.z for v in mesh.vertices)
    scale_h = 5.80 / max(max_z - min_z, 1e-6)
    for v in mesh.vertices:
        v.co.x *= scale_h
        v.co.y *= scale_h
        v.co.z = (v.co.z - min_z) * scale_h
    mesh.update()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    dims = [
        round(max(xs) - min(xs), 4),
        round(max(zs) - min(zs), 4),
        round(max(ys) - min(ys), 4),
    ]
    assert tri_count <= CFG["tri_budget"], f"tri budget {tri_count}>{CFG['tri_budget']}"
    export_godot_glb(paths["glb"], export_animations=False, export_morph=False)

    slug = CFG["slug"]
    manifest = {
        "prop_slug": slug,
        "tri_count": tri_count,
        "tri_budget": CFG["tri_budget"],
        "uv_layers": len(mesh.uv_layers),
        "min_y": round(min(zs), 4),
        "dimensions_m": dims,
        "layer": "Layer 1 Environment",
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "ref_image": CFG["ref_image"],
        "reference_image": CFG["ref_image"],
        "material": f"res://assets/models/{slug}/{slug}.tres",
        "mesh": f"res://assets/models/{slug}/{slug}.glb",
    }
    paths["manifest"].write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    _write_lamp_tscn(paths)
    print(f"[OK] {slug}: tris={tri_count}/{CFG['tri_budget']} dims_m={dims} uv={len(mesh.uv_layers)}")


if __name__ == "__main__":
    main()
