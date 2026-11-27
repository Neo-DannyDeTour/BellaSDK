"""Procedural Soviet Courtyard Seesaw with Separate Base & Pivoting Plank (0.78m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-29_1.png:
- SeesawBase: grounded tubular steel A-frame fulcrum legs (min_y = 0) + horizontal pivot axle + collars
- SeesawPlank: pivot centered on fulcrum axle (0, 0.56, 0 in Godot), weathered pine plank with
  tapered/beveled ends, rusty under-plank saddle bracket, and twin tubular steel U-handles
- 2048x2048 PBR atlas (sun-bleached weathered pine wood + olive-gray painted steel + rusty iron)

Usage:
    /usr/bin/python3 tools/blender/props/soviet_seesaw.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/soviet_seesaw.py
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

from tools.blender.common.street_prop import (  # noqa: E402
    TEX_SIZE,
    TILE,
    Builder,
    _fbm,
    _streaks,
    rx,
    ry,
)

PROP_SLUG: str = "soviet_seesaw"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-29_1.png"

MAT_WOOD: Path = REPO_ROOT / "assets" / "materials" / "roof_truss_timber" / "textures"
MAT_RUST: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TARGET_H: float = 0.78
TRI_BUDGET: int = 1400
FULCRUM_Z: float = 0.560


def _load_tiled_rgb(path: Path, tiles_x: float, tiles_y: float, out_size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    src = Image.open(path).convert("RGB")
    sw, sh = src.size
    rep_x = max(1, int(math.ceil(tiles_x)))
    rep_y = max(1, int(math.ceil(tiles_y)))
    tiled = Image.new("RGB", (sw * rep_x, sh * rep_y))
    for iy in range(rep_y):
        for ix in range(rep_x):
            tiled.paste(src, (ix * sw, iy * sh))
    cropped = tiled.crop((0, 0, max(1, int(round(sw * tiles_x))), max(1, int(round(sh * tiles_y)))))
    return np.asarray(cropped.resize((out_size, out_size), Image.Resampling.BICUBIC), dtype=np.float32)


def _load_tiled_l(path: Path, tiles_x: float, tiles_y: float, out_size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    src = Image.open(path).convert("L")
    sw, sh = src.size
    rep_x = max(1, int(math.ceil(tiles_x)))
    rep_y = max(1, int(math.ceil(tiles_y)))
    tiled = Image.new("L", (sw * rep_x, sh * rep_y))
    for iy in range(rep_y):
        for ix in range(rep_x):
            tiled.paste(src, (ix * sw, iy * sh))
    cropped = tiled.crop((0, 0, max(1, int(round(sw * tiles_x))), max(1, int(round(sh * tiles_y)))))
    return np.asarray(cropped.resize((out_size, out_size), Image.Resampling.BICUBIC), dtype=np.float32) / 255.0


def _generate_textures() -> None:
    """Build 2048x2048 weathered pine plank + painted steel + rusty iron PBR atlas."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(18291)

    alb_a = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    nrm_a = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    rgh_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    met_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    ao_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)

    def _put_tile(region: int, alb: np.ndarray, nrm: np.ndarray, rgh: np.ndarray, met: np.ndarray, ao: np.ndarray) -> None:
        col, row = region % 2, region // 2
        x0, y0 = col * TILE, (1 - row) * TILE
        sl = (slice(y0, y0 + TILE), slice(x0, x0 + TILE))
        alb_a[sl] = np.clip(alb, 30, 240)
        nrm_a[sl] = np.clip(nrm, 0, 255)
        rgh_a[sl] = np.clip(rgh, 0.25, 0.96)
        met_a[sl] = np.clip(met, 0.0, 1.0)
        ao_a[sl] = np.clip(ao, 0.35, 1.0)

    # Tile 0: Sun-bleached warm weathered pine wood plank (continuous grain along U / horizontal)
    wd_alb = np.rot90(_load_tiled_rgb(MAT_WOOD / "roof_truss_timber_albedo.png", 1.0, 1.0, TILE), k=1)
    wd_nrm = np.rot90(_load_tiled_rgb(MAT_WOOD / "roof_truss_timber_normal.png", 1.0, 1.0, TILE), k=1)
    wd_ao = np.rot90(_load_tiled_l(MAT_WOOD / "roof_truss_timber_ao.png", 1.0, 1.0, TILE), k=1)
    wd_rgh = np.rot90(_load_tiled_l(MAT_WOOD / "roof_truss_timber_roughness.png", 1.0, 1.0, TILE), k=1)

    grain = _streaks(rng, TILE, TILE, cy=110, cx=3)
    macro_w = _fbm(rng, TILE, TILE, cells=(3, 8, 24, 64), weights=(0.45, 0.30, 0.15, 0.10))
    # Bleached warm pine tone matching 2026-10-30_18-29_1.png
    lum_wd = (0.299 * wd_alb[..., 0] + 0.587 * wd_alb[..., 1] + 0.114 * wd_alb[..., 2]) / 255.0
    pine_base = np.array([212.0, 176.0, 134.0], dtype=np.float32)
    wood_alb = pine_base[None, None, :] * (0.76 + 0.38 * lum_wd)[..., None]
    wood_alb *= (0.86 + 0.24 * grain)[..., None]
    wood_alb *= (0.90 + 0.16 * macro_w)[..., None]

    # Add dark weathered knots and gouge scuffs
    knot_img = Image.new("L", (TILE, TILE), 0)
    kd = ImageDraw.Draw(knot_img)
    for _ in range(14):
        kx, ky = int(rng.integers(40, TILE - 40)), int(rng.integers(40, TILE - 40))
        rx_k, ry_k = int(rng.integers(14, 48)), int(rng.integers(4, 11))
        kd.ellipse([kx - rx_k, ky - ry_k, kx + rx_k, ky + ry_k], fill=int(rng.integers(110, 210)))
    knots = np.asarray(knot_img.filter(ImageFilter.GaussianBlur(4.0)), dtype=np.float32) / 255.0
    wood_alb *= (1.0 - 0.50 * knots[..., None])
    wood_alb[..., 2] *= (1.0 - 0.18 * knots)

    wood_rgh = np.clip(0.58 + 0.28 * wd_rgh + 0.10 * (1.0 - grain), 0.52, 0.92)
    wood_met = np.zeros((TILE, TILE), dtype=np.float32)
    wood_ao = np.clip(0.85 * wd_ao + 0.15 - 0.25 * knots, 0.45, 1.0)
    _put_tile(0, wood_alb, wd_nrm, wood_rgh, wood_met, wood_ao)

    # Tile 3: Darker grime-stained wood (underside / tip edge wear)
    wood_dark_alb = wood_alb * np.array([0.68, 0.65, 0.60], dtype=np.float32)
    _put_tile(3, wood_dark_alb, wd_nrm, np.clip(wood_rgh + 0.08, 0.55, 0.94), wood_met, wood_ao * 0.85)

    # Tile 1: Weathered olive-gray painted tubular steel (A-frame legs & U-handles)
    rs_alb = _load_tiled_rgb(MAT_RUST / "rusted_steel_albedo.png", 1.5, 1.5, TILE)
    rs_nrm = _load_tiled_rgb(MAT_RUST / "rusted_steel_normal.png", 1.5, 1.5, TILE)
    rs_ao = _load_tiled_l(MAT_RUST / "rusted_steel_ao.png", 1.5, 1.5, TILE)
    rs_rgh = _load_tiled_l(MAT_RUST / "rusted_steel_roughness.png", 1.5, 1.5, TILE)

    m1 = _fbm(rng, TILE, TILE)
    m2 = _fbm(rng, TILE, TILE, cells=(12, 48, 160, 320), weights=(0.3, 0.3, 0.25, 0.15))
    paint_col = np.array([122.0, 126.0, 114.0], dtype=np.float32)
    steel_alb = paint_col[None, None, :] * (0.78 + 0.36 * m1)[..., None]
    rust_mask = np.clip((m2 - 0.64) / 0.10, 0.0, 1.0)
    steel_alb = steel_alb * (1.0 - 0.72 * rust_mask[..., None]) + rs_alb * (0.72 * rust_mask[..., None])
    steel_rgh = np.clip(0.56 + 0.24 * (m1 - 0.5) + 0.18 * rust_mask, 0.42, 0.90)
    steel_met = np.clip(0.18 + 0.45 * rust_mask * 0.4, 0.0, 0.55)
    steel_ao = np.clip(0.84 + 0.16 * rs_ao - 0.18 * rust_mask, 0.45, 1.0)
    _put_tile(1, steel_alb, rs_nrm, steel_rgh, steel_met, steel_ao)

    # Tile 2: Oxidized rusty iron hardware (axle sleeve, saddle clamp, bolts)
    iron_alb = rs_alb * np.array([1.05, 0.85, 0.72], dtype=np.float32)
    iron_rgh = np.clip(0.66 + 0.24 * rs_rgh, 0.55, 0.92)
    iron_met = np.full((TILE, TILE), 0.42, dtype=np.float32)
    _put_tile(2, iron_alb, rs_nrm, iron_rgh, iron_met, rs_ao)

    albedo_p = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    normal_p = TEX_DIR / f"{PROP_SLUG}_normal.png"
    orm_p = TEX_DIR / f"{PROP_SLUG}_orm.png"
    Image.fromarray(alb_a.astype(np.uint8), mode="RGB").save(albedo_p)
    Image.fromarray(nrm_a.astype(np.uint8), mode="RGB").save(normal_p)
    tmp = {}
    for name, arr in (("ao", ao_a), ("rough", rgh_a), ("metal", met_a)):
        tmp[name] = TEX_DIR / f"_tmp_{name}.png"
        Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), mode="L").save(tmp[name])
    process_pbr.pack_orm(tmp["ao"], tmp["rough"], str(tmp["metal"]), orm_p, target_size=(TEX_SIZE, TEX_SIZE))
    for p in tmp.values():
        p.unlink(missing_ok=True)
    process_pbr.generate_godot_tres(
        material_name="M_SovietSeesaw",
        albedo_path=albedo_p,
        normal_path=normal_p,
        orm_path=orm_p,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] {PROP_SLUG}: generated 2048x2048 albedo/normal/orm + .tres")


def _make_material():
    import bpy

    mat = bpy.data.materials.new(name="M_SovietSeesaw")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def tex_node(suffix: str, cs: str):
        node = nt.nodes.new("ShaderNodeTexImage")
        img = bpy.data.images.load(str((TEX_DIR / f"{PROP_SLUG}_{suffix}.png").resolve()), check_existing=True)
        img.colorspace_settings.name = cs
        node.image = img
        return node

    nt.links.new(tex_node("albedo", "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_node("orm", "Non-Color").outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = 0.85
    nt.links.new(tex_node("normal", "Non-Color").outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _add_swept_tube(b: Builder, points: list, radius: float, segs: int, region: int) -> None:
    """Skin a continuous multi-segment tubular pipe through 3D points."""
    from mathutils import Vector

    rings: list[list[Vector]] = []
    n_pts = len(points)
    for idx, pt in enumerate(points):
        p = Vector(pt)
        if idx == 0:
            tangent = (Vector(points[1]) - p).normalized()
        elif idx == n_pts - 1:
            tangent = (p - Vector(points[-2])).normalized()
        else:
            t_in = (p - Vector(points[idx - 1])).normalized()
            t_out = (Vector(points[idx + 1]) - p).normalized()
            tangent = (t_in + t_out)
            tangent = tangent.normalized() if tangent.length > 1e-6 else t_out

        ref = Vector((0.0, 1.0, 0.0)) if abs(tangent.y) < 0.9 else Vector((1.0, 0.0, 0.0))
        binorm = tangent.cross(ref).normalized()
        norm = binorm.cross(tangent).normalized()

        ring = []
        for s in range(segs):
            a = 2.0 * math.pi * s / segs
            ring.append(p + (binorm * math.cos(a) + norm * math.sin(a)) * radius)
        rings.append(ring)

    b.add_loft(rings, region=region, caps=(True, True), smooth=True)


def _build_base(mat) -> tuple[object, int]:
    """Build grounded tubular steel A-frame fulcrum SeesawBase (min_z = 0.0)."""
    import bmesh
    import bpy
    from mathutils import Vector

    b = Builder(seed=101)

    # 1. Horizontal pivot axle bar along Y at z = FULCRUM_Z
    b.add_cyl(Vector((0.0, 0.0, FULCRUM_Z)), 0.022, 0.340, region=2, segs=10, rot=rx(90.0))
    # Bearing collars flanking center saddle
    for sy in (-0.125, 0.125):
        b.add_cyl(Vector((0.0, sy, FULCRUM_Z)), 0.029, 0.030, region=2, segs=10, rot=rx(90.0))

    # 2. Two curved, splayed tubular steel legs (-Y and +Y sides) grounded at z = 0.0
    leg_r = 0.020
    for side in (-1.0, 1.0):
        # Curved elbow from axle end (y = side*0.155, z = FULCRUM_Z) down to splayed foot (y = side*0.235, z = 0.0)
        pts = [
            Vector((0.0, side * 0.145, FULCRUM_Z)),
            Vector((0.0, side * 0.175, FULCRUM_Z - 0.006)),
            Vector((0.0, side * 0.194, FULCRUM_Z - 0.026)),
            Vector((0.0, side * 0.200, FULCRUM_Z - 0.062)),
            Vector((0.0, side * 0.233, 0.032)),
        ]
        _add_swept_tube(b, pts, leg_r, segs=8, region=1)
        # Ground foot collar sitting flush at z = 0.0
        b.add_cyl(Vector((0.0, side * 0.235, 0.022)), 0.028, 0.044, region=2, segs=10)

    # Subtle steel A-frame cross-brace bar lower down for stability (z = 0.16m)
    b.add_cyl(Vector((0.0, 0.0, 0.160)), 0.013, 0.440, region=1, segs=8, rot=rx(90.0))

    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    mesh = bpy.data.meshes.new("SeesawBase")
    b.bm.to_mesh(mesh)
    b.bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("SeesawBase", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (0.0, 0.0, 0.0)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tris


def _build_plank(mat) -> tuple[object, int]:
    """Build SeesawPlank with origin centered on the fulcrum axle (0, 0, FULCRUM_Z)."""
    import bmesh
    import bpy
    from mathutils import Vector

    b = Builder(seed=202)

    # Local Z=0 is fulcrum axle center. Plank rests right above axle via saddle bracket.
    # 1. Rusty saddle pivot clamp & under-plank mounting plate
    b.add_cyl(Vector((0.0, 0.0, 0.0)), 0.031, 0.210, region=2, segs=10, rot=rx(90.0))
    b.add_box(Vector((0.0, 0.0, 0.022)), (0.220, 0.265, 0.018), region=2)

    # 2. Weathered wood plank (3.10m along X, 0.275m wide, 0.044m thick, tapered/beveled ends)
    # Stations: (x, half_width, z_bottom, z_top)
    stations = [
        (-1.550, 0.105, 0.014, 0.042),
        (-1.515, 0.128, 0.022, 0.056),
        (-1.420, 0.138, 0.024, 0.068),
        (-1.180, 0.138, 0.024, 0.068),
        (0.000, 0.138, 0.024, 0.068),
        (1.180, 0.138, 0.024, 0.068),
        (1.420, 0.138, 0.024, 0.068),
        (1.515, 0.128, 0.022, 0.056),
        (1.550, 0.105, 0.014, 0.042),
    ]
    plank_rings: list[list[Vector]] = []
    bev = 0.008
    for x, hw, zb, zt in stations:
        # 8-point chamfered rectangle in YZ plane (CCW looking from +X)
        plank_rings.append([
            Vector((x, -(hw - bev), zb)),
            Vector((x, +(hw - bev), zb)),
            Vector((x, +hw, zb + bev)),
            Vector((x, +hw, zt - bev)),
            Vector((x, +(hw - bev), zt)),
            Vector((x, -(hw - bev), zt)),
            Vector((x, -hw, zt - bev)),
            Vector((x, -hw, zb + bev)),
        ])
    b.bm.faces.ensure_lookup_table()
    plank_start = len(b.bm.faces)
    b.add_loft(plank_rings, region=0, caps=(True, True), smooth=False)
    # Remap plank faces cleanly along plank length (U = X, V = Y/Z) for continuous grain
    b.bm.faces.ensure_lookup_table()
    for face in b.bm.faces[plank_start:]:
        for lp in face.loops:
            u = (lp.vert.co.x + 1.550) / 3.100
            v = (lp.vert.co.y + 0.140) / 0.280 * 0.70 + 0.15
            lp[b.uv].uv = b.tile_uv(0, max(0.01, min(0.99, u)), max(0.01, min(0.99, v)))

    # 3. Twin tubular steel U-handles near each end (world max Z = 0.560 + 0.220 = 0.780m)
    handle_r = 0.013
    top_z = 0.220 - handle_r  # outer top surface hits z_local = 0.220 -> world 0.780m
    base_z = 0.066
    hy = 0.112
    cr = 0.032
    for sx in (-1.020, 1.020):
        pts = [
            Vector((sx, -hy, base_z)),
            Vector((sx, -hy, top_z - cr)),
            Vector((sx, -(hy - cr * 0.30), top_z - cr * 0.30)),
            Vector((sx, -(hy - cr), top_z)),
            Vector((sx, +(hy - cr), top_z)),
            Vector((sx, +(hy - cr * 0.30), top_z - cr * 0.30)),
            Vector((sx, +hy, top_z - cr)),
            Vector((sx, +hy, base_z)),
        ]
        _add_swept_tube(b, pts, handle_r, segs=8, region=1)
        # Bolted steel mounting feet on plank top
        for sy in (-hy, hy):
            b.add_box(Vector((sx, sy, base_z + 0.005)), (0.042, 0.042, 0.010), region=2)

    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    mesh = bpy.data.meshes.new("SeesawPlank")
    b.bm.to_mesh(mesh)
    b.bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("SeesawPlank", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (0.0, 0.0, FULCRUM_Z)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tris


def _write_tscn() -> None:
    lines = [
        "[gd_scene load_steps=4 format=3]",
        "",
        f'[ext_resource type="PackedScene" path="res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb" id="1_glb"]',
        f'[ext_resource type="Material" path="res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres" id="2_mat"]',
        "",
        '[sub_resource type="BoxShape3D" id="BoxShape3D_1"]',
        "size = Vector3(3.1, 0.78, 0.526)",
        "",
        '[node name="SovietSeesaw" type="StaticBody3D"]',
        "collision_layer = 1",
        "collision_mask = 0",
        "",
        '[node name="Model" parent="." instance=ExtResource("1_glb")]',
        "",
        '[node name="SeesawBase" parent="Model" index="0"]',
        "layers = 1",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="SeesawPlank" parent="Model" index="1"]',
        "layers = 1",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="."]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.0, 0.39, 0.0)",
        'shape = SubResource("BoxShape3D_1")',
        "",
        '[editable path="Model"]',
    ]
    out_tscn = REPO_ROOT / "props" / PROP_SLUG / f"{PROP_SLUG}.tscn"
    out_tscn.parent.mkdir(parents=True, exist_ok=True)
    out_tscn.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _build_mesh_and_export() -> None:
    import bpy
    from mathutils import Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    needed = [TEX_DIR / f"{PROP_SLUG}_{s}.png" for s in ("albedo", "normal", "orm")]
    if not all(p.is_file() for p in needed) or not TRES_PATH.is_file():
        subprocess.run(["/usr/bin/python3", str(Path(__file__).resolve()), "--gen-textures"], check=True)

    clean_scene()
    mat = _make_material()
    base_obj, base_tris = _build_base(mat)
    plank_obj, plank_tris = _build_plank(mat)

    bpy.ops.object.select_all(action="DESELECT")
    for o in (base_obj, plank_obj):
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.select_set(False)

    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for o in (base_obj, plank_obj):
        for v in o.data.vertices:
            wp = o.matrix_world @ v.co
            mins.x = min(mins.x, wp.x)
            mins.y = min(mins.y, wp.y)
            mins.z = min(mins.z, wp.z)
            maxs.x = max(maxs.x, wp.x)
            maxs.y = max(maxs.y, wp.y)
            maxs.z = max(maxs.z, wp.z)

    total_tris = base_tris + plank_tris
    assert total_tris <= TRI_BUDGET, f"{PROP_SLUG}: {total_tris} tris > {TRI_BUDGET}"
    dims_godot = [
        round(maxs.x - mins.x, 4),
        round(maxs.z - mins.z, 4),
        round(maxs.y - mins.y, 4),
    ]

    export_godot_glb(GLB_PATH, export_animations=False, export_morph=False, only_selected=False)

    manifest = {
        "prop_slug": PROP_SLUG,
        "objects": ["SeesawBase", "SeesawPlank"],
        "plank_pivot_godot": [0.0, FULCRUM_Z, 0.0],
        "tri_count": total_tris,
        "tri_budget": TRI_BUDGET,
        "uv_layers": len(base_obj.data.uv_layers),
        "min_y": round(mins.z, 4),
        "dimensions_m": dims_godot,
        "layer": "Layer 1 Environment",
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "ref_image": REF_IMAGE,
        "reference_image": REF_IMAGE,
        "material": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres",
        "mesh": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    _write_tscn()
    print(f"[OK] {PROP_SLUG}: tris={total_tris}/{TRI_BUDGET}, dims_m={dims_godot}, min_y={manifest['min_y']}")


def main() -> None:
    if "--gen-textures" in sys.argv:
        _generate_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
