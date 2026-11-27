"""Procedural Workshop Circular Saw Table (0.85m H, 2 separate GLB objects).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-11-05_19-28_2.png (weathered timber/steel sawbench frame)
- /home/dkd/Downloads/hl2_refs/2026-11-05_19-27_2.png (toothed rusted circular steel sawblade)

Separate GLB objects:
- SawTableBase: grounded frame, slotted timber deck, steel throat plate, arbor cradle, motor & switch
- SawBlade: toothed 0.49m circular steel blade with pivot centered at blade arbor (0, 0, 0.605m)

Usage:
    /usr/bin/python3 tools/blender/props/circular_saw_table.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/circular_saw_table.py
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
    ry,
)

PROP_SLUG: str = "circular_saw_table"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-05_19-28_2.png"
REF_BLADE: str = "/home/dkd/Downloads/hl2_refs/2026-11-05_19-27_2.png"

MAT_WOOD: Path = REPO_ROOT / "assets" / "materials" / "weathered_deck_planks" / "textures"
MAT_RUST: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TARGET_H: float = 0.85
TRI_BUDGET: int = 1800

TABLE_W: float = 1.18
TABLE_D: float = 0.74
DECK_TOP_Z: float = 0.710
DECK_THICK: float = 0.042
DECK_BOT_Z: float = DECK_TOP_Z - DECK_THICK

BLADE_ARBOR_Z: float = 0.605
BLADE_RADIUS: float = 0.245  # 0.605 + 0.245 = 0.850m exact target height
BLADE_HUB_R: float = 0.032
BLADE_TEETH: int = 28


def _load_tiled_rgb(path: Path, out_size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB").resize((out_size, out_size), Image.Resampling.BICUBIC)
    return np.asarray(img, dtype=np.float32)


def _load_tiled_l(path: Path, out_size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("L").resize((out_size, out_size), Image.Resampling.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def _generate_textures() -> None:
    """Build 2048x2048 wood plank + painted steel frame + dark motor + circular sawblade atlas."""
    import numpy as np
    from PIL import Image, ImageDraw

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(51928)

    alb_a = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    nrm_a = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    rgh_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    met_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    ao_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)

    def _put_tile(
        region: int, alb: np.ndarray, nrm: np.ndarray, rgh: np.ndarray, met: np.ndarray, ao: np.ndarray
    ) -> None:
        col, row = region % 2, region // 2
        x0, y0 = col * TILE, (1 - row) * TILE
        sl = (slice(y0, y0 + TILE), slice(x0, x0 + TILE))
        alb_a[sl] = np.clip(alb, 30, 240)
        nrm_a[sl] = np.clip(nrm, 0, 255)
        rgh_a[sl] = np.clip(rgh, 0.22, 0.96)
        met_a[sl] = np.clip(met, 0.0, 1.0)
        ao_a[sl] = np.clip(ao, 0.35, 1.0)

    def _nrm_from_h(height: np.ndarray, strength: float) -> np.ndarray:
        gy, gx = np.gradient(height)
        nx, ny, nz = -gx * strength, gy * strength, np.ones_like(height)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        return (np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5) * 255.0

    # Tile 0: Bleached/weathered gray workshop timber deck planks (matches 2026-11-05_19-28_2.png)
    wd_alb = _load_tiled_rgb(MAT_WOOD / "weathered_deck_planks_albedo.png", TILE)
    wd_nrm = _load_tiled_rgb(MAT_WOOD / "weathered_deck_planks_normal.png", TILE)
    wd_ao = _load_tiled_l(MAT_WOOD / "weathered_deck_planks_ao.png", TILE)
    wd_rgh = _load_tiled_l(MAT_WOOD / "weathered_deck_planks_roughness.png", TILE)
    grain = _streaks(rng, TILE, TILE, cy=120, cx=4)
    grime = _fbm(rng, TILE, TILE, cells=(3, 10, 28, 72), weights=(0.45, 0.30, 0.15, 0.10))
    # Bleached cool-gray workshop timber tint + dark oil stains
    gray_lum = (0.3 * wd_alb[..., 0] + 0.59 * wd_alb[..., 1] + 0.11 * wd_alb[..., 2])[..., None]
    wd_alb = 0.55 * wd_alb + 0.45 * gray_lum * np.array([0.96, 0.95, 0.92], dtype=np.float32)
    wd_alb *= (0.86 + 0.24 * grain)[..., None] * (0.82 + 0.22 * grime)[..., None]
    wd_rgh = np.clip(wd_rgh * 0.95 + 0.10 * (1.0 - grain), 0.58, 0.94)
    _put_tile(0, wd_alb, wd_nrm, wd_rgh, np.zeros((TILE, TILE), dtype=np.float32), wd_ao)

    # Tile 1: Weathered painted gray-green steel frame + legs + throat plate
    rs_alb = _load_tiled_rgb(MAT_RUST / "rusted_steel_albedo.png", TILE)
    rs_nrm = _load_tiled_rgb(MAT_RUST / "rusted_steel_normal.png", TILE)
    rs_rgh = _load_tiled_l(MAT_RUST / "rusted_steel_roughness.png", TILE)
    m_f1 = _fbm(rng, TILE, TILE, cells=(4, 12, 36, 96), weights=(0.4, 0.3, 0.2, 0.1))
    paint_col = np.array([104.0, 108.0, 102.0], dtype=np.float32)
    chip = np.clip((m_f1 - 0.62) / 0.12, 0.0, 1.0)
    frame_alb = paint_col[None, None, :] * (0.82 + 0.34 * m_f1)[..., None]
    frame_alb = frame_alb * (1.0 - chip[..., None]) + rs_alb * 0.72 * chip[..., None]
    frame_rgh = np.clip(0.54 + 0.28 * chip + 0.14 * (rs_rgh - 0.5), 0.36, 0.92)
    frame_met = np.clip(0.68 - 0.35 * chip, 0.20, 0.82)
    _put_tile(1, frame_alb, rs_nrm, frame_rgh, frame_met, np.clip(0.92 - 0.22 * chip, 0.55, 1.0))

    # Tile 2: Dark cast-iron motor, arbor blocks, rip fence + small red switch decal corner
    m_f2 = _fbm(rng, TILE, TILE, cells=(6, 18, 48, 120), weights=(0.4, 0.3, 0.2, 0.1))
    iron_col = np.array([56.0, 58.0, 60.0], dtype=np.float32)
    iron_alb = iron_col[None, None, :] * (0.78 + 0.42 * m_f2)[..., None]
    # Reserve ONLY bottom-left corner (image y >= 0.78, x <= 0.35 -> UV u in [0, 0.35], v in [0, 0.22]) for red switch
    sw_mask = np.zeros((TILE, TILE), dtype=np.float32)
    sw_mask[int(TILE * 0.78) :, : int(TILE * 0.35)] = 1.0
    red_col = np.array([148.0, 42.0, 34.0], dtype=np.float32) * (0.84 + 0.28 * m_f2)[..., None]
    iron_alb = iron_alb * (1.0 - sw_mask[..., None]) + red_col * sw_mask[..., None]
    iron_rgh = np.clip(0.46 + 0.26 * (1.0 - m_f2), 0.30, 0.88)
    iron_met = np.where(sw_mask > 0.5, 0.25, 0.82).astype(np.float32)
    _put_tile(2, iron_alb, _nrm_from_h(m_f2, 8.0), iron_rgh, iron_met, np.clip(0.85 + 0.15 * m_f2, 0.6, 1.0))

    # Tile 3: Circular Sawblade face (matches 2026-11-05_19-27_2.png)
    # Concentric lathe-turned steel rings + heavy rust patches + 4 radial expansion slots
    yy, xx = np.mgrid[0:TILE, 0:TILE].astype(np.float32)
    cx = cy = (TILE - 1) * 0.5
    dx = (xx - cx) / (TILE * 0.47)
    dy = (yy - cy) / (TILE * 0.47)
    rad = np.sqrt(dx * dx + dy * dy)

    blade_noise = _fbm(rng, TILE, TILE, cells=(4, 10, 32, 96), weights=(0.42, 0.28, 0.18, 0.12))
    rings = 0.5 + 0.5 * np.sin(rad * 125.0 + blade_noise * 2.5)
    steel_base = np.array([128.0, 126.0, 122.0], dtype=np.float32)
    blade_alb = steel_base[None, None, :] * (0.82 + 0.18 * rings + 0.14 * (blade_noise - 0.5))[..., None]

    # Heavy rust blotches near outer third & mid radius (like ref)
    rust_zone = np.clip((rad - 0.30) / 0.55, 0.0, 1.0)
    rust_m = np.clip((blade_noise * 0.78 + rust_zone * 0.32 - 0.54) / 0.16, 0.0, 1.0)
    rust_c = np.array([124.0, 66.0, 36.0], dtype=np.float32)
    blade_alb = blade_alb * (1.0 - rust_m[..., None]) + rust_c[None, None, :] * rust_m[..., None]

    # Bright worn metal on outer tooth rim (rad > 0.86)
    tooth_rim = np.clip((rad - 0.85) / 0.06, 0.0, 1.0) * 0.45
    blade_alb = blade_alb * (1.0 - tooth_rim[..., None]) + np.array([162.0, 160.0, 156.0]) * tooth_rim[..., None]

    # 4 dark expansion slots with diamond relief endpoints (at 0, 90, 180, 270 deg)
    slot_img = Image.new("L", (TILE, TILE), 0)
    sd = ImageDraw.Draw(slot_img)
    r_outer_px = int(TILE * 0.49)
    r_inner_px = int(TILE * 0.22)
    c_px = TILE // 2
    d_r = int(TILE * 0.016)
    for vx, vy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        p0 = (c_px + vx * r_inner_px, c_px + vy * r_inner_px)
        p1 = (c_px + vx * r_outer_px, c_px + vy * r_outer_px)
        sd.line([p0, p1], fill=255, width=max(5, int(TILE * 0.008)))
        # Diamond relief hole at inner end of each slot
        dcx, dcy = p0
        sd.polygon([(dcx, dcy - d_r), (dcx + d_r, dcy), (dcx, dcy + d_r), (dcx - d_r, dcy)], fill=255)
    slot_mask = np.asarray(slot_img, dtype=np.float32) / 255.0

    blade_alb = blade_alb * (1.0 - 0.78 * slot_mask[..., None]) + np.array([34.0, 32.0, 30.0]) * (0.78 * slot_mask[..., None])
    blade_rgh = np.clip(0.36 + 0.40 * rust_m - 0.10 * tooth_rim + 0.45 * slot_mask, 0.24, 0.94)
    blade_met = np.clip(0.88 - 0.72 * rust_m - 0.80 * slot_mask, 0.08, 0.94)
    blade_ao = np.clip(0.94 - 0.22 * rust_m - 0.55 * slot_mask, 0.35, 1.0)
    blade_h = 0.25 * rings + 0.35 * blade_noise + 0.25 * rust_m - 0.85 * slot_mask
    _put_tile(3, blade_alb, _nrm_from_h(blade_h, 11.0), blade_rgh, blade_met, blade_ao)

    albedo_p = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    normal_p = TEX_DIR / f"{PROP_SLUG}_normal.png"
    orm_p = TEX_DIR / f"{PROP_SLUG}_orm.png"
    Image.fromarray(alb_a.astype(np.uint8)).save(albedo_p)
    Image.fromarray(np.clip(nrm_a, 0, 255).astype(np.uint8)).save(normal_p)
    tmp = {}
    for name, arr in (("ao", ao_a), ("rough", rgh_a), ("metal", met_a)):
        tmp[name] = TEX_DIR / f"_tmp_{name}.png"
        Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), mode="L").save(tmp[name])
    process_pbr.pack_orm(tmp["ao"], tmp["rough"], str(tmp["metal"]), orm_p, target_size=(TEX_SIZE, TEX_SIZE))
    for p in tmp.values():
        p.unlink(missing_ok=True)
    process_pbr.generate_godot_tres(
        material_name="M_CircularSawTable",
        albedo_path=albedo_p,
        normal_path=normal_p,
        orm_path=orm_p,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] {PROP_SLUG}: albedo/normal/orm + .tres")


def _make_material() -> "bpy.types.Material":
    import bpy

    mat = bpy.data.materials.new(name="M_CircularSawTable")
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


def _build_table_base(mat: "bpy.types.Material") -> tuple["bpy.types.Object", int]:
    """Build SawTableBase: slotted deck, steel throat plate, legs, stretchers, motor & arbor."""
    import bmesh
    import bpy

    b = Builder(seed=51928)
    deck_zc = DECK_BOT_Z + DECK_THICK * 0.5

    # 1. Slotted wooden tabletop planks (leaving central steel throat plate & blade slot open)
    # Front and back full-width planks
    b.add_box((0.0, -0.275, deck_zc), (TABLE_W, 0.190, DECK_THICK), region=0)
    b.add_box((0.0, +0.275, deck_zc), (TABLE_W, 0.190, DECK_THICK), region=0)
    # Middle left and right planks flanking throat plate (x in [-0.27, +0.27])
    side_w = (TABLE_W - 0.540) * 0.5
    b.add_box((-0.270 - side_w * 0.5, 0.0, deck_zc), (side_w, 0.354, DECK_THICK), region=0)
    b.add_box((+0.270 + side_w * 0.5, 0.0, deck_zc), (side_w, 0.354, DECK_THICK), region=0)
    # Narrow wood filler strips in front & back of steel throat plate
    b.add_box((0.0, -0.145, deck_zc), (0.540, 0.068, DECK_THICK), region=0)
    b.add_box((0.0, +0.145, deck_zc), (0.540, 0.068, DECK_THICK), region=0)

    # 2. Split steel throat plate framing the central blade slot (slot gap y in [-0.018, +0.018])
    throat_zc = DECK_TOP_Z - 0.008
    b.add_box((0.0, -0.064, throat_zc), (0.540, 0.092, 0.018), region=1)
    b.add_box((0.0, +0.064, throat_zc), (0.540, 0.092, 0.018), region=1)
    b.add_box((-0.258, 0.0, throat_zc), (0.024, 0.036, 0.018), region=1)
    b.add_box((+0.258, 0.0, throat_zc), (0.024, 0.036, 0.018), region=1)

    # 3. Steel frame apron, 4 grounded legs, foot pads & lower H-stretchers
    leg_x = TABLE_W * 0.5 - 0.055
    leg_y = TABLE_D * 0.5 - 0.055
    leg_h = DECK_BOT_Z - 0.008
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            lx, ly = sx * leg_x, sy * leg_y
            b.add_box((lx, ly, 0.004), (0.072, 0.072, 0.008), region=1)
            b.add_box((lx, ly, 0.008 + leg_h * 0.5), (0.044, 0.044, leg_h), region=1)

    # Upper apron rails under deck
    apron_z = DECK_BOT_Z - 0.028
    b.add_box((0.0, -leg_y, apron_z), (leg_x * 2.0 - 0.044, 0.022, 0.056), region=1)
    b.add_box((0.0, +leg_y, apron_z), (leg_x * 2.0 - 0.044, 0.022, 0.056), region=1)
    b.add_box((-leg_x, 0.0, apron_z), (0.022, leg_y * 2.0 - 0.044, 0.056), region=1)
    b.add_box((+leg_x, 0.0, apron_z), (0.022, leg_y * 2.0 - 0.044, 0.056), region=1)

    # Lower horizontal stretcher rails (H-frame)
    stretcher_z = 0.195
    b.add_box((-leg_x, 0.0, stretcher_z), (0.032, leg_y * 2.0 - 0.044, 0.032), region=1)
    b.add_box((+leg_x, 0.0, stretcher_z), (0.032, leg_y * 2.0 - 0.044, 0.032), region=1)
    b.add_box((0.0, 0.0, stretcher_z), (leg_x * 2.0 - 0.032, 0.034, 0.032), region=1)

    # 4. Under-table arbor cradle, bearing blocks, electric motor & belt guard
    b.add_box((-0.250, 0.0, 0.575), (0.020, 0.220, 0.180), region=1)
    b.add_box((+0.250, 0.0, 0.575), (0.020, 0.220, 0.180), region=1)
    b.add_box((0.0, 0.0, 0.480), (0.520, 0.220, 0.018), region=1)

    # Arbor bearing pillow blocks + shaft (passes through SawBlade pivot at y=0, z=0.605)
    safe_iron_uv = {k: (0.42, 0.30, 0.95, 0.95) for k in ("front", "back", "left", "right", "top", "bottom")}
    b.add_box((0.0, -0.045, BLADE_ARBOR_Z), (0.064, 0.042, 0.056), region=2, uv_rects=safe_iron_uv)
    b.add_box((0.0, +0.045, BLADE_ARBOR_Z), (0.064, 0.042, 0.056), region=2, uv_rects=safe_iron_uv)
    from mathutils import Matrix

    rx90 = Matrix.Rotation(math.radians(90.0), 3, "X")
    b.add_cyl((0.0, 0.0, BLADE_ARBOR_Z), 0.015, 0.160, region=2, segs=10, rot=rx90)

    # Electric drive motor slung under rear-left + belt guard
    b.add_cyl((-0.140, +0.165, 0.515), 0.082, 0.220, region=2, segs=12, rot=ry(90.0))
    b.add_box((-0.020, +0.110, 0.560), (0.045, 0.140, 0.140), region=1)

    # 5. Rip fence rail on front edge + guide fence bar + power switch box on front-right leg
    b.add_box((0.0, -TABLE_D * 0.5 - 0.014, DECK_TOP_Z - 0.018), (TABLE_W, 0.020, 0.032), region=2,
              uv_rects=safe_iron_uv)
    b.add_box((+0.340, 0.0, DECK_TOP_Z + 0.026), (0.036, TABLE_D + 0.020, 0.052), region=2,
              uv_rects=safe_iron_uv)
    b.add_box((+0.340, -TABLE_D * 0.5 - 0.012, DECK_TOP_Z + 0.008), (0.068, 0.032, 0.046), region=2,
              uv_rects=safe_iron_uv)

    # Power switch box with red button face (UV mapped to bottom-left corner of tile 2)
    sw_x, sw_y, sw_z = leg_x, -leg_y - 0.042, 0.555
    sw_uvs = dict(safe_iron_uv)
    sw_uvs["front"] = (0.03, 0.03, 0.32, 0.19)
    b.add_box((sw_x, sw_y, sw_z), (0.072, 0.044, 0.105), region=2, uv_rects=sw_uvs)

    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    mesh = bpy.data.meshes.new("SawTableBase")
    b.bm.to_mesh(mesh)
    b.bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("SawTableBase", mesh)
    bpy.context.collection.objects.link(obj)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tris


def _build_saw_blade(mat: "bpy.types.Material") -> tuple["bpy.types.Object", int]:
    """Build SawBlade with local origin at arbor center (0, 0, BLADE_ARBOR_Z)."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    n = BLADE_TEETH
    r_bore = BLADE_HUB_R
    r_mid = 0.135
    r_root = 0.214
    r_tip = BLADE_RADIUS
    half_t = 0.004

    def _blade_uv(x: float, z: float) -> tuple[float, float]:
        # Region 3 is col=1, row=1 -> UV [0.51, 0.99] x [0.51, 0.99]
        u = 0.5 + (x / (2.0 * r_tip)) * 0.94
        v = 0.5 + (z / (2.0 * r_tip)) * 0.94
        return Builder.tile_uv(3, max(0.02, min(0.98, u)), max(0.02, min(0.98, v)))

    # Build front (-Y) and back (+Y) rings: bore, mid, root, and hooked tooth tips
    for sign_y in (-1.0, 1.0):
        pass  # created simultaneously below for clean bridging

    rings_f: list[list] = []
    rings_b: list[list] = []
    for r in (r_bore, r_mid, r_root):
        rf, rb = [], []
        for i in range(n):
            ang = 2.0 * math.pi * i / n
            px, pz = r * math.cos(ang), r * math.sin(ang)
            rf.append(bm.verts.new(Vector((px, -half_t, pz))))
            rb.append(bm.verts.new(Vector((px, +half_t, pz))))
        rings_f.append(rf)
        rings_b.append(rb)

    # Tooth tips (hooked forward clockwise in XZ plane)
    tips_f, tips_b = [], []
    step = 2.0 * math.pi / n
    for i in range(n):
        ang_tip = step * (i + 0.18)
        px, pz = r_tip * math.cos(ang_tip), r_tip * math.sin(ang_tip)
        tips_f.append(bm.verts.new(Vector((px, -half_t, pz))))
        tips_b.append(bm.verts.new(Vector((px, +half_t, pz))))

    def _add_face_uv(verts: list, smooth: bool = False) -> None:
        f = bm.faces.new(verts)
        f.smooth = smooth
        for lp in f.loops:
            lp[uv_layer].uv = _blade_uv(lp.vert.co.x, lp.vert.co.z)

    # Annular rings (bore -> mid -> root)
    for r_idx in range(2):
        for i in range(n):
            j = (i + 1) % n
            _add_face_uv([rings_f[r_idx][i], rings_f[r_idx][j], rings_f[r_idx + 1][j], rings_f[r_idx + 1][i]])
            _add_face_uv([rings_b[r_idx][j], rings_b[r_idx][i], rings_b[r_idx + 1][i], rings_b[r_idx + 1][j]])

    # Saw teeth wedges (each tooth spans root[i] -> root[i+1] -> tip[i]) + outer blade rim
    for i in range(n):
        j = (i + 1) % n
        # Front & back triangle for tooth
        _add_face_uv([rings_f[2][i], rings_f[2][j], tips_f[i]])
        _add_face_uv([rings_b[2][j], rings_b[2][i], tips_b[i]])
        # Cutting edge face (root[i] -> tip[i]) & back slope (tip[i] -> root[j])
        _add_face_uv([rings_f[2][i], tips_f[i], tips_b[i], rings_b[2][i]])
        _add_face_uv([tips_f[i], rings_f[2][j], rings_b[2][j], tips_b[i]])
        # Inner bore rim
        _add_face_uv([rings_b[0][i], rings_b[0][j], rings_f[0][j], rings_f[0][i]])

    # Center clamping arbor flange washers (on both sides of the blade)
    flange_r = 0.056
    flange_t = 0.011
    n_fl = 14
    for sign_y in (-1.0, 1.0):
        inner_y = sign_y * half_t
        outer_y = sign_y * flange_t
        c_in, c_out = [], []
        for k in range(n_fl):
            ang = 2.0 * math.pi * k / n_fl
            fx, fz = flange_r * math.cos(ang), flange_r * math.sin(ang)
            c_in.append(bm.verts.new(Vector((fx, inner_y, fz))))
            c_out.append(bm.verts.new(Vector((fx, outer_y, fz))))
        b_out = []
        for k in range(n_fl):
            ang = 2.0 * math.pi * k / n_fl
            bx, bz = r_bore * math.cos(ang), r_bore * math.sin(ang)
            b_out.append(bm.verts.new(Vector((bx, outer_y, bz))))

        for k in range(n_fl):
            k2 = (k + 1) % n_fl
            if sign_y < 0:
                f1 = bm.faces.new([c_in[k], c_in[k2], c_out[k2], c_out[k]])
                f2 = bm.faces.new([b_out[k], b_out[k2], c_out[k2], c_out[k]])
            else:
                f1 = bm.faces.new([c_in[k2], c_in[k], c_out[k], c_out[k2]])
                f2 = bm.faces.new([b_out[k2], b_out[k], c_out[k], c_out[k2]])
            for face in (f1, f2):
                face.smooth = False
                for lp in face.loops:
                    lp[uv_layer].uv = Builder.tile_uv(2, 0.5, 0.5)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("SawBlade")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("SawBlade", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (0.0, 0.0, BLADE_ARBOR_Z)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tris


def _write_tscn(dims: list[float]) -> None:
    lines = [
        "[gd_scene load_steps=4 format=3]",
        "",
        f'[ext_resource type="PackedScene" path="res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb" id="1_glb"]',
        f'[ext_resource type="Material" path="res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres" id="2_mat"]',
        "",
        '[sub_resource type="BoxShape3D" id="BoxShape3D_1"]',
        f"size = Vector3({dims[0]}, {dims[1]}, {dims[2]})",
        "",
        '[node name="CircularSawTable" type="StaticBody3D"]',
        "collision_layer = 1",
        "collision_mask = 0",
        "",
        '[node name="Model" parent="." instance=ExtResource("1_glb")]',
        "",
        '[node name="SawBlade" parent="Model" index="0"]',
        "layers = 1",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="SawTableBase" parent="Model" index="1"]',
        "layers = 1",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="."]',
        f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.0, {round(dims[1] * 0.5, 4)}, 0.0)",
        'shape = SubResource("BoxShape3D_1")',
        "",
        '[editable path="Model"]',
        "",
    ]
    out_tscn = REPO_ROOT / "props" / PROP_SLUG / f"{PROP_SLUG}.tscn"
    out_tscn.parent.mkdir(parents=True, exist_ok=True)
    out_tscn.write_text("\n".join(lines), encoding="utf-8")


def _build_mesh_and_export() -> None:
    import bpy
    from mathutils import Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    needed = [TEX_DIR / f"{PROP_SLUG}_{s}.png" for s in ("albedo", "normal", "orm")]
    if not all(p.is_file() for p in needed) or not TRES_PATH.is_file():
        subprocess.run(["/usr/bin/python3", str(Path(__file__).resolve()), "--gen-textures"], check=True)

    clean_scene()
    mat = _make_material()
    base_obj, base_tris = _build_table_base(mat)
    blade_obj, blade_tris = _build_saw_blade(mat)

    bpy.ops.object.select_all(action="DESELECT")
    for o in (base_obj, blade_obj):
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.select_set(False)

    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for o in (base_obj, blade_obj):
        for v in o.data.vertices:
            wp = o.matrix_world @ v.co
            mins.x = min(mins.x, wp.x)
            mins.y = min(mins.y, wp.y)
            mins.z = min(mins.z, wp.z)
            maxs.x = max(maxs.x, wp.x)
            maxs.y = max(maxs.y, wp.y)
            maxs.z = max(maxs.z, wp.z)

    total_tris = base_tris + blade_tris
    assert total_tris <= TRI_BUDGET, f"{PROP_SLUG}: {total_tris} tris > {TRI_BUDGET}"
    dims_godot = [
        round(maxs.x - mins.x, 4),
        round(maxs.z - mins.z, 4),
        round(maxs.y - mins.y, 4),
    ]

    export_godot_glb(GLB_PATH, export_animations=False, export_morph=False, only_selected=False)

    manifest = {
        "prop_slug": PROP_SLUG,
        "objects": ["SawTableBase", "SawBlade"],
        "blade_pivot_godot": [0.0, BLADE_ARBOR_Z, 0.0],
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
        "ref_blade": REF_BLADE,
        "material": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres",
        "mesh": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    _write_tscn(dims_godot)
    print(f"[OK] {PROP_SLUG}: tris={total_tris}/{TRI_BUDGET}, dims_m={dims_godot}, min_y={manifest['min_y']}")


def main() -> None:
    if "--gen-textures" in sys.argv:
        _generate_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
