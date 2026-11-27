"""Procedural Soviet Creosote Timber Utility Pole with Double Crossarms & Insulators (6.50m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-05_19-33_1.png:
- Tapered creosote-soaked weathered timber pole (grounded min_y = 0, height = 6.50m)
- Steel pole clamp bands + twin angled lower equipment hanger brackets
- Steel-braced upper double crossarms (2-insulator upper arm + 4-insulator lower arm)
- 6 glazed off-white ceramic pin insulators on vertical steel pins with crossarm straps
- 2048x2048 PBR atlas (creosote weathered timber + rusted steel hardware + glazed ceramic)

Usage:
    /usr/bin/python3 tools/blender/props/utility_pole_insulators.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/utility_pole_insulators.py
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
    rz,
)

PROP_SLUG: str = "utility_pole_insulators"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-05_19-33_1.png"

MAT_TIMBER: Path = REPO_ROOT / "assets" / "materials" / "roof_truss_timber" / "textures"
MAT_RUST: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TARGET_H: float = 6.50
TRI_BUDGET: int = 1600


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
    """Build 2048x2048 creosote pole timber + crossarm wood + rusted iron + ceramic PBR atlas."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(19331)

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

    tm_alb = _load_tiled_rgb(MAT_TIMBER / "roof_truss_timber_albedo.png", 1.5, 2.5, TILE)
    tm_nrm = _load_tiled_rgb(MAT_TIMBER / "roof_truss_timber_normal.png", 1.5, 2.5, TILE)
    tm_ao = _load_tiled_l(MAT_TIMBER / "roof_truss_timber_ao.png", 1.5, 2.5, TILE)
    tm_rgh = _load_tiled_l(MAT_TIMBER / "roof_truss_timber_roughness.png", 1.5, 2.5, TILE)

    rs_alb = _load_tiled_rgb(MAT_RUST / "rusted_steel_albedo.png", 2.0, 2.0, TILE)
    rs_nrm = _load_tiled_rgb(MAT_RUST / "rusted_steel_normal.png", 2.0, 2.0, TILE)
    rs_ao = _load_tiled_l(MAT_RUST / "rusted_steel_ao.png", 2.0, 2.0, TILE)
    rs_rgh = _load_tiled_l(MAT_RUST / "rusted_steel_roughness.png", 2.0, 2.0, TILE)

    # Tile 0: Creosote-soaked dark weathered vertical pole timber (splits/checks + tar streaks)
    splits = _streaks(rng, TILE, TILE, cy=4, cx=80)
    creosote = _fbm(rng, TILE, TILE, cells=(4, 10, 28, 80), weights=(0.45, 0.30, 0.15, 0.10))
    pole_alb = tm_alb * np.array([0.74, 0.66, 0.56], dtype=np.float32)
    pole_alb *= (0.72 + 0.36 * splits)[..., None]
    pole_alb *= (0.75 + 0.38 * creosote)[..., None]
    pole_rgh = np.clip(0.68 + 0.22 * tm_rgh + 0.08 * (1.0 - splits), 0.58, 0.94)
    _put_tile(0, pole_alb, tm_nrm, pole_rgh, np.zeros((TILE, TILE), np.float32), tm_ao)

    # Tile 1: Crossarm timber (horizontal grain, slightly lighter weathered brown-gray)
    arm_alb = np.rot90(tm_alb, k=1) * np.array([0.86, 0.78, 0.68], dtype=np.float32)
    arm_nrm = np.rot90(tm_nrm, k=1)
    arm_ao = np.rot90(tm_ao, k=1)
    arm_rgh = np.clip(0.66 + 0.24 * np.rot90(tm_rgh, k=1), 0.55, 0.93)
    _put_tile(1, arm_alb, arm_nrm, arm_rgh, np.zeros((TILE, TILE), np.float32), arm_ao)

    # Tile 2: Rusted galvanized steel braces, straps, pole bands, and insulator pins
    iron_alb = rs_alb * np.array([0.96, 0.90, 0.86], dtype=np.float32)
    iron_rgh = np.clip(0.60 + 0.26 * rs_rgh, 0.45, 0.90)
    iron_met = np.full((TILE, TILE), 0.58, dtype=np.float32)
    _put_tile(2, iron_alb, rs_nrm, iron_rgh, iron_met, rs_ao)

    # Tile 3: Grimy glazed ceramic pin insulators (warm off-white porcelain with dust/soot)
    m_cer = _fbm(rng, TILE, TILE, cells=(6, 16, 48, 120), weights=(0.4, 0.3, 0.2, 0.1))
    cer_base = np.array([196.0, 190.0, 174.0], dtype=np.float32)
    cer_alb = cer_base[None, None, :] * (0.82 + 0.24 * m_cer)[..., None]
    flat_nrm = np.zeros((TILE, TILE, 3), dtype=np.float32)
    flat_nrm[..., 0] = 128.0
    flat_nrm[..., 1] = 128.0
    flat_nrm[..., 2] = 255.0
    cer_rgh = np.clip(0.28 + 0.14 * (1.0 - m_cer), 0.25, 0.45)
    _put_tile(3, cer_alb, flat_nrm, cer_rgh, np.zeros((TILE, TILE), np.float32), np.full((TILE, TILE), 0.95, np.float32))

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
        material_name="M_UtilityPoleInsulators",
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

    mat = bpy.data.materials.new(name="M_UtilityPoleInsulators")
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


def _add_strut(b: Builder, p0, p1, radius: float, segs: int, region: int) -> None:
    from mathutils import Vector

    a = Vector(p0)
    z = Vector(p1)
    delta = z - a
    length = delta.length
    if length < 1e-6:
        return
    rot = delta.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    b.add_cyl((a + z) * 0.5, radius, length, region=region, segs=segs, rot=rot, caps=(False, False))


def _add_ceramic_insulator(b: Builder, cx: float, cy: float, arm_top_z: float) -> None:
    """Add vertical steel mounting strap, pin stalk, and skirted glazed ceramic insulator."""
    from mathutils import Vector

    # Steel U-strap wrapping crossarm top & sides + vertical steel pin stalk
    b.add_box(Vector((cx, cy, arm_top_z - 0.052)), (0.042, 0.114, 0.112), region=2)
    b.add_cyl(Vector((cx, cy, arm_top_z + 0.065)), 0.015, 0.130, region=2, segs=8)

    # Bell/skirted ceramic insulator (3-ring lathe profile on top of pin)
    z0 = arm_top_z + 0.115
    profile = [
        (0.068, z0),
        (0.062, z0 + 0.032),
        (0.040, z0 + 0.066),
        (0.024, z0 + 0.092),
    ]
    segs = 10
    rings: list[list[Vector]] = []
    for rad, zz in profile:
        rings.append([
            Vector((cx + rad * math.cos(2.0 * math.pi * i / segs),
                    cy + rad * math.sin(2.0 * math.pi * i / segs), zz))
            for i in range(segs)
        ])
    b.add_loft(rings, region=3, caps=(True, True), smooth=True)


def _build_mesh_and_export() -> None:
    import bmesh
    import bpy
    from mathutils import Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    needed = [TEX_DIR / f"{PROP_SLUG}_{s}.png" for s in ("albedo", "normal", "orm")]
    if not all(p.is_file() for p in needed) or not TRES_PATH.is_file():
        subprocess.run(["/usr/bin/python3", str(Path(__file__).resolve()), "--gen-textures"], check=True)

    clean_scene()
    b = Builder(seed=19331)

    # 1. Main tapered creosote timber pole (z = 0.0 .. 6.50m)
    b.add_cyl(Vector((0.0, 0.0, TARGET_H * 0.5)), 0.145, TARGET_H, region=0, segs=12, r_top=0.105)

    # 2. Steel pole clamp bands at crossarms & hanger brackets
    for bz, br in ((6.00, 0.112), (5.20, 0.118), (4.35, 0.124)):
        b.add_cyl(Vector((0.0, 0.0, bz)), br, 0.048, region=2, segs=12)

    # 3. Upper crossarm (z = 5.95m, 1.90m wide) + 2 steel V-braces + 2 insulators
    arm_y = -0.155  # mounted cleanly on front (-Y) face of pole
    upper_z = 5.950
    b.add_box(Vector((0.0, arm_y, upper_z)), (1.900, 0.100, 0.108), region=1)
    # Pole-to-crossarm bolt saddle
    b.add_box(Vector((0.0, arm_y * 0.5, upper_z)), (0.140, 0.180, 0.120), region=2)
    for sx in (-1.0, 1.0):
        _add_strut(
            b,
            Vector((0.0, arm_y + 0.055, 5.420)),
            Vector((sx * 0.520, arm_y + 0.045, upper_z - 0.045)),
            0.014,
            segs=6,
            region=2,
        )
    for ix in (-0.780, 0.780):
        _add_ceramic_insulator(b, ix, arm_y, upper_z + 0.054)

    # 4. Lower crossarm (z = 5.15m, 2.34m wide) + 2 steel V-braces + 4 insulators
    lower_z = 5.150
    b.add_box(Vector((0.0, arm_y, lower_z)), (2.340, 0.100, 0.108), region=1)
    b.add_box(Vector((0.0, arm_y * 0.5, lower_z)), (0.140, 0.180, 0.120), region=2)
    for sx in (-1.0, 1.0):
        _add_strut(
            b,
            Vector((0.0, arm_y + 0.055, 4.520)),
            Vector((sx * 0.680, arm_y + 0.045, lower_z - 0.045)),
            0.014,
            segs=6,
            region=2,
        )
    for ix in (-1.020, -0.520, 0.520, 1.020):
        _add_ceramic_insulator(b, ix, arm_y, lower_z + 0.054)

    # 5. Twin angled steel equipment hanger brackets below lower crossarm (matching ref)
    for sx in (-1.0, 1.0):
        b.add_box(
            Vector((sx * 0.185, arm_y * 0.5, 4.240)),
            (0.055, 0.045, 0.420),
            region=2,
            rot=rz(sx * 12.0) @ rx(28.0),
        )
        b.add_box(
            Vector((sx * 0.240, arm_y - 0.030, 4.080)),
            (0.040, 0.180, 0.036),
            region=2,
        )

    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    mesh = bpy.data.meshes.new("UtilityPoleInsulators")
    b.bm.to_mesh(mesh)
    b.bm.free()
    mesh.materials.append(_make_material())
    obj = bpy.data.objects.new("UtilityPoleInsulators", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    assert tris <= TRI_BUDGET, f"{PROP_SLUG}: {tris} tris > {TRI_BUDGET}"
    xs, ys, zs = ([getattr(v.co, a) for v in mesh.vertices] for a in "xyz")
    dims_godot = [round(max(xs) - min(xs), 4), round(max(zs) - min(zs), 4), round(max(ys) - min(ys), 4)]

    export_godot_glb(GLB_PATH, export_animations=False, export_morph=False)

    manifest = {
        "prop_slug": PROP_SLUG,
        "tri_count": tris,
        "tri_budget": TRI_BUDGET,
        "uv_layers": len(mesh.uv_layers),
        "min_y": round(min(zs), 4),
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

    # Pole collision box covers trunk + crossarm envelope cleanly (pole trunk centered at X=0, Z=0)
    tscn_lines = [
        "[gd_scene load_steps=4 format=3]",
        "",
        f'[ext_resource type="PackedScene" path="res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb" id="1_glb"]',
        f'[ext_resource type="Material" path="res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres" id="2_mat"]',
        "",
        '[sub_resource type="BoxShape3D" id="BoxShape3D_1"]',
        "size = Vector3(0.32, 6.5, 0.32)",
        "",
        '[node name="UtilityPoleInsulators" type="StaticBody3D"]',
        "collision_layer = 1",
        "collision_mask = 0",
        "",
        '[node name="Model" parent="." instance=ExtResource("1_glb")]',
        "",
        '[node name="UtilityPoleInsulators" parent="Model" index="0"]',
        "layers = 1",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="."]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.0, 3.25, 0.0)",
        'shape = SubResource("BoxShape3D_1")',
        "",
        '[editable path="Model"]',
    ]
    out_tscn = REPO_ROOT / "props" / PROP_SLUG / f"{PROP_SLUG}.tscn"
    out_tscn.parent.mkdir(parents=True, exist_ok=True)
    out_tscn.write_text("\n".join(tscn_lines) + "\n", encoding="utf-8")
    print(f"[OK] {PROP_SLUG}: tris={tris}/{TRI_BUDGET}, dims_m={dims_godot}, min_y={manifest['min_y']}")


def main() -> None:
    if "--gen-textures" in sys.argv:
        _generate_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
