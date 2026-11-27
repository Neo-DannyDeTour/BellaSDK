"""Procedural 20ft Post-Soviet Industrial Gothic Freight Container + PBR ORMMaterial3D.

Dimensions: ~6.06m (X) x 2.44m (Z in Godot / Y in Blender) x 2.59m (Y in Godot / Z in Blender).
Origin: bottom-center (min_z = 0.0 in Blender -> min_y = 0.0 in Godot).
Tri budget: <= 4000 tris.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/freight_container.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/freight_container.py --gen-textures
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

PROP_SLUG: str = "freight_container"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TRI_BUDGET: int = 4000

# 20ft ISO container dimensions (meters, Blender Z-up, doors at +X)
LENGTH: float = 6.06
WIDTH: float = 2.44
HEIGHT: float = 2.59


def _fbm_noise(h: int, w: int, seed: int, octaves: list[tuple[int, float]]) -> "np.ndarray":
    """Generate smooth multi-octave 2D value noise in [0, 1] using numpy + PIL."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    weight_sum = 0.0
    for grid, weight in octaves:
        low = rng.random((max(2, grid), max(2, grid)), dtype=np.float32)
        img = Image.fromarray((low * 255.0).astype(np.uint8), mode="L")
        up = np.asarray(img.resize((w, h), resample=Image.Resampling.BICUBIC), dtype=np.float32) / 255.0
        acc += up * weight
        weight_sum += weight
    out = acc / max(weight_sum, 1e-6)
    return np.clip(out, 0.0, 1.0)


def _paint_metal_quadrant(
    size: int,
    base_rgb: tuple[int, int, int],
    ochre_rgb: tuple[int, int, int],
    rust_rgb: tuple[int, int, int],
    bare_rgb: tuple[int, int, int],
    seed: int,
    rust_thresh: float = 0.62,
    streak_strength: float = 0.35,
    base_metallic: float = 0.15,
) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize weathered painted steel with ochre fade, rust streaks, and chipped edges."""
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.50), (18, 0.35), (56, 0.15)])
    detail = _fbm_noise(size, size, seed + 17, [(32, 0.45), (96, 0.35), (220, 0.20)])
    # Vertical rain/rust streaking
    streak_band = _fbm_noise(size, size, seed + 41, [(4, 0.25), (48, 0.75)])
    # Stretch vertically by blending column-wise mean
    col_profile = np.mean(streak_band, axis=0, keepdims=True)
    streaks = np.clip(0.65 * col_profile + 0.35 * streak_band, 0.0, 1.0)

    rgb = np.zeros((size, size, 3), dtype=np.float32)
    for c in range(3):
        rgb[..., c] = base_rgb[c] * (1.0 - macro * 0.45) + ochre_rgb[c] * (macro * 0.45)

    # Darken with vertical grime streaks
    grime_mask = np.clip((streaks - 0.45) * streak_strength * 2.2, 0.0, 0.65)
    rgb = rgb * (1.0 - grime_mask[..., None] * 0.45)

    # Rust patches + drips
    rust_score = 0.55 * macro + 0.30 * streaks + 0.15 * detail
    rust_mask = np.clip((rust_score - rust_thresh) / max(1.0 - rust_thresh, 1e-4), 0.0, 1.0)
    rust_mask = np.power(rust_mask, 0.85)
    for c in range(3):
        rgb[..., c] = rgb[..., c] * (1.0 - rust_mask) + rust_rgb[c] * rust_mask

    # Chipped bare steel specks
    chip_mask = (detail > 0.82) & (rust_score < rust_thresh + 0.05)
    for c in range(3):
        rgb[..., c] = np.where(chip_mask, bare_rgb[c] * (0.85 + 0.3 * detail), rgb[..., c])

    # Subtle micro-grain
    rgb = rgb * (0.92 + 0.16 * detail[..., None])

    metallic = np.full((size, size), base_metallic, dtype=np.float32)
    metallic = np.where(rust_mask > 0.35, 0.05, metallic)
    metallic = np.where(chip_mask, 0.85, metallic)
    return np.clip(rgb, 30.0, 240.0), np.clip(metallic, 0.0, 1.0)


def _draw_door_stencil_quadrant(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize weathered olive/ochre door panel with faded ISO/Soviet stencil markings."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont

    rgb, metallic = _paint_metal_quadrant(
        size,
        base_rgb=(84, 90, 60),
        ochre_rgb=(132, 102, 54),
        rust_rgb=(92, 46, 26),
        bare_rgb=(96, 98, 100),
        seed=seed,
        rust_thresh=0.66,
        streak_strength=0.30,
        base_metallic=0.12,
    )

    img = Image.fromarray(rgb.astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img)

    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    if not Path(font_path).is_file():
        font_path = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

    font_lg = ImageFont.truetype(font_path, int(size * 0.078)) if Path(font_path).is_file() else ImageFont.load_default()
    font_md = ImageFont.truetype(font_path, int(size * 0.048)) if Path(font_path).is_file() else ImageFont.load_default()
    font_sm = ImageFont.truetype(font_path, int(size * 0.036)) if Path(font_path).is_file() else ImageFont.load_default()

    stencil_cream = (206, 198, 172)
    stencil_ochre = (196, 158, 68)
    ink_dark = (38, 36, 34)

    # Container code & weight ratings
    draw.text((size * 0.14, size * 0.18), "SOVU 204819 4", fill=stencil_cream, font=font_lg)
    draw.text((size * 0.14, size * 0.29), "22G1   20T", fill=stencil_ochre, font=font_md)
    draw.text((size * 0.14, size * 0.42), "MAX GROSS  24 000 KG", fill=stencil_cream, font=font_sm)
    draw.text((size * 0.14, size * 0.48), "TARE        2 240 KG", fill=stencil_cream, font=font_sm)
    draw.text((size * 0.14, size * 0.54), "NET        21 760 KG", fill=stencil_cream, font=font_sm)

    # Faded yellow/black industrial caution bar near bottom
    bar_y0, bar_y1 = int(size * 0.72), int(size * 0.80)
    draw.rectangle([int(size * 0.12), bar_y0, int(size * 0.88), bar_y1], fill=stencil_ochre, outline=ink_dark, width=3)
    for sx in range(int(size * 0.12), int(size * 0.88), int(size * 0.08)):
        draw.polygon(
            [
                (sx, bar_y1),
                (sx + int(size * 0.035), bar_y1),
                (sx + int(size * 0.065), bar_y0),
                (sx + int(size * 0.030), bar_y0),
            ],
            fill=ink_dark,
        )

    # Weathering pass over stencil ink
    arr = np.asarray(img, dtype=np.float32)
    wear = _fbm_noise(size, size, seed + 88, [(14, 0.5), (48, 0.5)])
    arr = np.where(wear[..., None] > 0.72, rgb, arr)
    arr = arr * (0.90 + 0.16 * wear[..., None])
    return np.clip(arr, 30.0, 240.0), metallic


def generate_textures() -> None:
    """Synthesize 2048x2048 weathered freight container PBR atlas + ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    # Q0 (Top-Left, UV U:0..0.5 V:0.5..1.0): Rusted olive/ochre corrugated walls & roof
    q0_rgb, q0_met = _paint_metal_quadrant(
        half,
        base_rgb=(82, 88, 58),
        ochre_rgb=(136, 102, 52),
        rust_rgb=(96, 44, 24),
        bare_rgb=(96, 98, 100),
        seed=101,
        rust_thresh=0.58,
        streak_strength=0.42,
        base_metallic=0.14,
    )
    # Q1 (Top-Right, UV U:0.5..1.0 V:0.5..1.0): Heavy dark rusted frame, corner castings, rubber seal
    q1_rgb, q1_met = _paint_metal_quadrant(
        half,
        base_rgb=(64, 58, 48),
        ochre_rgb=(98, 66, 38),
        rust_rgb=(84, 36, 20),
        bare_rgb=(86, 86, 88),
        seed=202,
        rust_thresh=0.50,
        streak_strength=0.35,
        base_metallic=0.25,
    )
    # Q2 (Bottom-Left, UV U:0..0.5 V:0..0.5): Galvanized/oxidized steel locking bars & hinges
    q2_rgb, q2_met = _paint_metal_quadrant(
        half,
        base_rgb=(118, 122, 124),
        ochre_rgb=(128, 114, 92),
        rust_rgb=(92, 48, 28),
        bare_rgb=(142, 146, 148),
        seed=303,
        rust_thresh=0.68,
        streak_strength=0.20,
        base_metallic=0.72,
    )
    # Q3 (Bottom-Right, UV U:0.5..1.0 V:0..0.5): Door panel with faded stenciled markings
    q3_rgb, q3_met = _draw_door_stencil_quadrant(half, seed=404)

    albedo = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    albedo[0:half, 0:half] = q0_rgb
    albedo[0:half, half:atlas_size] = q1_rgb
    albedo[half:atlas_size, 0:half] = q2_rgb
    albedo[half:atlas_size, half:atlas_size] = q3_rgb
    albedo = np.clip(albedo, 30.0, 240.0).astype(np.uint8)

    metallic = np.zeros((atlas_size, atlas_size), dtype=np.float32)
    metallic[0:half, 0:half] = q0_met
    metallic[0:half, half:atlas_size] = q1_met
    metallic[half:atlas_size, 0:half] = q2_met
    metallic[half:atlas_size, half:atlas_size] = q3_met
    metallic_u8 = np.clip(metallic * 255.0, 0.0, 255.0).astype(np.uint8)

    albedo_path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    metallic_path = TEX_DIR / f"{PROP_SLUG}_metallic_tmp.png"
    Image.fromarray(albedo, mode="RGB").save(albedo_path, format="PNG")
    Image.fromarray(metallic_u8, mode="L").save(metallic_path, format="PNG")

    process_pbr = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"
    subprocess.run(
        [
            sys.executable,
            str(process_pbr),
            "derive-maps",
            str(albedo_path),
            "--out-dir",
            str(TEX_DIR),
            "--slug",
            PROP_SLUG,
            "--preset",
            "metal",
            "--base-roughness",
            "0.68",
            "--normal-strength",
            "2.2",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEX_DIR / f"{PROP_SLUG}_ao.png"
    rough_path = TEX_DIR / f"{PROP_SLUG}_roughness.png"
    normal_path = TEX_DIR / f"{PROP_SLUG}_normal.png"
    orm_path = TEX_DIR / f"{PROP_SLUG}_orm.png"
    tres_path = ASSET_DIR / f"{PROP_SLUG}.tres"

    subprocess.run(
        [
            sys.executable,
            str(process_pbr),
            "pack-orm",
            "--ao",
            str(ao_path),
            "--roughness",
            str(rough_path),
            "--metallic",
            str(metallic_path),
            "--output",
            str(orm_path),
        ],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(process_pbr),
            "build-tres",
            "--name",
            PROP_SLUG,
            "--albedo",
            str(albedo_path),
            "--normal",
            str(normal_path),
            "--orm",
            str(orm_path),
            "--output",
            str(tres_path),
        ],
        check=True,
    )

    for tmp in (metallic_path, TEX_DIR / f"{PROP_SLUG}_height.png", ao_path, rough_path):
        tmp.unlink(missing_ok=True)
    print(f"[Textures] Generated PBR maps + {tres_path.relative_to(REPO_ROOT)}")


def _ensure_textures_exist() -> None:
    required = [
        TEX_DIR / f"{PROP_SLUG}_albedo.png",
        TEX_DIR / f"{PROP_SLUG}_normal.png",
        TEX_DIR / f"{PROP_SLUG}_orm.png",
        ASSET_DIR / f"{PROP_SLUG}.tres",
    ]
    if all(p.is_file() for p in required):
        return
    venv_py = REPO_ROOT / ".venv" / "bin" / "python"
    py_bin = str(venv_py) if venv_py.is_file() else sys.executable
    subprocess.run([py_bin, str(Path(__file__).resolve()), "--gen-textures"], check=True)


def _create_atlas_material() -> "bpy.types.Material":
    import bpy

    mat = bpy.data.materials.new(name=f"M_{PROP_SLUG}")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (520, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (200, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.location = (-360, 260)
    img_alb = bpy.data.images.load(str(TEX_DIR / f"{PROP_SLUG}_albedo.png"), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-360, 0)
    img_orm = bpy.data.images.load(str(TEX_DIR / f"{PROP_SLUG}_orm.png"), check_existing=True)
    img_orm.colorspace_settings.name = "Non-Color"
    tex_orm.image = img_orm

    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-100, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-360, -260)
    img_nrm = bpy.data.images.load(str(TEX_DIR / f"{PROP_SLUG}_normal.png"), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm

    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -260)
    nrm_node.inputs["Strength"].default_value = 0.75
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _tag_faces(faces: list, region_id: int, smooth: bool) -> None:
    for f in faces:
        f.material_index = region_id
        f.smooth = smooth


def _add_box(bm: "bmesh.types.BMesh", center: "Vector", size: "Vector", region: int, smooth: bool = False) -> None:
    import bmesh
    from mathutils import Matrix

    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    mat = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    vset = set(verts)
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth)


def _add_cylinder(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    axis: "Vector",
    radius: float,
    length: float,
    segments: int,
    region: int,
    smooth: bool = True,
) -> None:
    import bmesh
    from mathutils import Matrix, Vector

    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=length,
    )
    verts = ret["verts"]
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(center) @ rot
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    vset = set(verts)
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth)


def _add_corrugated_sheet(
    bm: "bmesh.types.BMesh",
    x0: float,
    x1: float,
    z0: float,
    z1: float,
    y_outer: float,
    y_inner: float,
    num_ribs: int,
    flip_normal: bool,
    region: int,
) -> None:
    """Build a vertical trapezoidal corrugated wall along X (at Y = y_outer..y_inner)."""
    span = x1 - x0
    pitch = span / num_ribs
    # 4 points per rib: trough_start, slope_up, crest_end, slope_down
    xs: list[float] = []
    ys: list[float] = []
    for i in range(num_ribs):
        bx = x0 + i * pitch
        xs.extend([bx, bx + pitch * 0.22, bx + pitch * 0.34, bx + pitch * 0.66, bx + pitch * 0.78])
        ys.extend([y_inner, y_inner, y_outer, y_outer, y_inner])
    xs.append(x1)
    ys.append(y_inner)

    bot_verts = [bm.verts.new((px, py, z0)) for px, py in zip(xs, ys)]
    top_verts = [bm.verts.new((px, py, z1)) for px, py in zip(xs, ys)]

    new_faces = []
    for i in range(len(xs) - 1):
        if flip_normal:
            f = bm.faces.new((bot_verts[i + 1], bot_verts[i], top_verts[i], top_verts[i + 1]))
        else:
            f = bm.faces.new((bot_verts[i], bot_verts[i + 1], top_verts[i + 1], top_verts[i]))
        new_faces.append(f)
    _tag_faces(new_faces, region, smooth=False)


def _add_corrugated_roof(
    bm: "bmesh.types.BMesh",
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    z_low: float,
    z_high: float,
    num_ribs: int,
    region: int,
) -> None:
    """Build horizontal trapezoidal corrugated roof panel along X."""
    span = x1 - x0
    pitch = span / num_ribs
    xs: list[float] = []
    zs: list[float] = []
    for i in range(num_ribs):
        bx = x0 + i * pitch
        xs.extend([bx, bx + pitch * 0.22, bx + pitch * 0.34, bx + pitch * 0.66, bx + pitch * 0.78])
        zs.extend([z_low, z_low, z_high, z_high, z_low])
    xs.append(x1)
    zs.append(z_low)

    front_v = [bm.verts.new((px, y0, pz)) for px, pz in zip(xs, zs)]
    back_v = [bm.verts.new((px, y1, pz)) for px, pz in zip(xs, zs)]

    new_faces = []
    for i in range(len(xs) - 1):
        f = bm.faces.new((front_v[i], front_v[i + 1], back_v[i + 1], back_v[i]))
        new_faces.append(f)
    _tag_faces(new_faces, region, smooth=False)


def _add_corrugated_rear_wall(
    bm: "bmesh.types.BMesh",
    x_outer: float,
    x_inner: float,
    y0: float,
    y1: float,
    z0: float,
    z1: float,
    num_ribs: int,
    region: int,
) -> None:
    """Build vertical trapezoidal corrugated rear wall at -X spanning Y."""
    span = y1 - y0
    pitch = span / num_ribs
    ys: list[float] = []
    xs: list[float] = []
    for i in range(num_ribs):
        by = y0 + i * pitch
        ys.extend([by, by + pitch * 0.22, by + pitch * 0.34, by + pitch * 0.66, by + pitch * 0.78])
        xs.extend([x_inner, x_inner, x_outer, x_outer, x_inner])
    ys.append(y1)
    xs.append(x_inner)

    bot_v = [bm.verts.new((px, py, z0)) for px, py in zip(xs, ys)]
    top_v = [bm.verts.new((px, py, z1)) for px, py in zip(xs, ys)]

    new_faces = []
    for i in range(len(ys) - 1):
        f = bm.faces.new((bot_v[i + 1], bot_v[i], top_v[i], top_v[i + 1]))
        new_faces.append(f)
    _tag_faces(new_faces, region, smooth=False)


def _build_geometry() -> tuple["bpy.types.Mesh", list[int]]:
    """Construct 20ft corrugated freight container geometry."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()
    hx = LENGTH * 0.5
    hy = WIDTH * 0.5

    # 1. Floor deck & structural base/top rails (region 1 = frame)
    _add_box(bm, Vector((0.0, 0.0, 0.085)), Vector((LENGTH - 0.08, WIDTH - 0.08, 0.13)), region=1)
    # Bottom side rails
    for sy in (-1.0, 1.0):
        _add_box(bm, Vector((0.0, sy * (hy - 0.045), 0.07)), Vector((LENGTH - 0.34, 0.09, 0.14)), region=1)
        # Forklift pocket trim plates along bottom side rails
        for fx in (-1.02, 1.02):
            _add_box(bm, Vector((fx, sy * (hy - 0.025), 0.07)), Vector((0.36, 0.06, 0.10)), region=1)
    # Bottom end sills
    for sx in (-1.0, 1.0):
        _add_box(bm, Vector((sx * (hx - 0.05), 0.0, 0.07)), Vector((0.10, WIDTH - 0.32, 0.14)), region=1)

    # Top side rails & end headers
    for sy in (-1.0, 1.0):
        _add_box(bm, Vector((0.0, sy * (hy - 0.045), HEIGHT - 0.055)), Vector((LENGTH - 0.34, 0.09, 0.11)), region=1)
    for sx in (-1.0, 1.0):
        _add_box(bm, Vector((sx * (hx - 0.05), 0.0, HEIGHT - 0.055)), Vector((0.10, WIDTH - 0.32, 0.11)), region=1)

    # 4 Vertical corner posts
    post_h = HEIGHT - 0.236
    post_cz = 0.118 + post_h * 0.5
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            _add_box(
                bm,
                Vector((sx * (hx - 0.08), sy * (hy - 0.08), post_cz)),
                Vector((0.16, 0.16, post_h)),
                region=1,
            )

    # 8 ISO corner castings (slightly proud of rails)
    cc_x, cc_y, cc_z = 0.178, 0.162, 0.118
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            for sz_z in (cc_z * 0.5, HEIGHT - cc_z * 0.5):
                _add_box(
                    bm,
                    Vector((sx * (hx - cc_x * 0.5), sy * (hy - cc_y * 0.5), sz_z)),
                    Vector((cc_x, cc_y, cc_z)),
                    region=1,
                )

    # 2. Corrugated side walls (-Y and +Y, region 0)
    _add_corrugated_sheet(
        bm,
        x0=-hx + 0.16,
        x1=hx - 0.16,
        z0=0.14,
        z1=HEIGHT - 0.11,
        y_outer=-hy + 0.015,
        y_inner=-hy + 0.060,
        num_ribs=18,
        flip_normal=False,
        region=0,
    )
    _add_corrugated_sheet(
        bm,
        x0=-hx + 0.16,
        x1=hx - 0.16,
        z0=0.14,
        z1=HEIGHT - 0.11,
        y_outer=hy - 0.015,
        y_inner=hy - 0.060,
        num_ribs=18,
        flip_normal=True,
        region=0,
    )

    # 3. Corrugated rear wall (-X, region 0)
    _add_corrugated_rear_wall(
        bm,
        x_outer=-hx + 0.025,
        x_inner=-hx + 0.070,
        y0=-hy + 0.16,
        y1=hy - 0.16,
        z0=0.14,
        z1=HEIGHT - 0.11,
        num_ribs=8,
        region=0,
    )

    # 4. Corrugated roof (+Z, region 0) + inner ceiling backing
    _add_box(bm, Vector((0.0, 0.0, HEIGHT - 0.06)), Vector((LENGTH - 0.18, WIDTH - 0.18, 0.03)), region=0)
    _add_corrugated_roof(
        bm,
        x0=-hx + 0.16,
        x1=hx - 0.16,
        y0=-hy + 0.09,
        y1=hy - 0.09,
        z_low=HEIGHT - 0.045,
        z_high=HEIGHT - 0.012,
        num_ribs=16,
        region=0,
    )

    # 5. Front double doors (+X end)
    door_x = hx - 0.055
    door_h = HEIGHT - 0.25
    door_cz = 0.125 + door_h * 0.5
    door_w = hy - 0.17
    # Left door (-Y) -> region 0; Right door (+Y) -> region 3 (stencil panel)
    _add_box(bm, Vector((door_x, -0.01 - door_w * 0.5, door_cz)), Vector((0.045, door_w, door_h)), region=0)
    _add_box(bm, Vector((door_x, 0.01 + door_w * 0.5, door_cz)), Vector((0.045, door_w, door_h)), region=3)

    # Central rubber gasket strip
    _add_box(bm, Vector((door_x + 0.018, 0.0, door_cz)), Vector((0.016, 0.024, door_h)), region=1)

    # Horizontal stamped door ribs (3 per door leaf)
    for rz in (0.65, 1.30, 1.95):
        _add_box(bm, Vector((door_x + 0.026, -0.01 - door_w * 0.5, rz)), Vector((0.020, door_w - 0.10, 0.11)), region=0)
        _add_box(bm, Vector((door_x + 0.026, 0.01 + door_w * 0.5, rz)), Vector((0.020, door_w - 0.10, 0.11)), region=0)

    # 4 vertical locking bars (region 2 = galvanized/oxidized steel hardware)
    bar_x = hx - 0.015
    bar_len = HEIGHT - 0.18
    bar_cz = 0.09 + bar_len * 0.5
    for by in (-0.82, -0.26, 0.26, 0.82):
        _add_cylinder(bm, Vector((bar_x, by, bar_cz)), Vector((0.0, 0.0, 1.0)), 0.017, bar_len, 6, region=2, smooth=True)
        # Top & bottom cam keepers
        _add_box(bm, Vector((bar_x - 0.006, by, 0.085)), Vector((0.045, 0.065, 0.055)), region=2)
        _add_box(bm, Vector((bar_x - 0.006, by, HEIGHT - 0.07)), Vector((0.045, 0.065, 0.055)), region=2)
        # 3 guide brackets along door height
        for gz in (0.45, 1.30, 2.15):
            _add_box(bm, Vector((bar_x - 0.008, by, gz)), Vector((0.036, 0.055, 0.038)), region=2)
        # Lever handle + retainer
        handle_dir = -1.0 if by < 0.0 else 1.0
        _add_box(bm, Vector((bar_x + 0.018, by + handle_dir * 0.10, 1.06)), Vector((0.016, 0.22, 0.026)), region=2)

    # 8 door hinges (4 per outer corner post)
    for sy in (-1.0, 1.0):
        for hz in (0.36, 0.96, 1.62, 2.22):
            _add_box(bm, Vector((hx - 0.035, sy * (hy - 0.13), hz)), Vector((0.055, 0.11, 0.045)), region=2)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    bm.faces.ensure_lookup_table()
    # Front-facing (+X) face of right door leaf for clean stencil UV mapping
    stencil_faces = [f.index for f in bm.faces if f.material_index == 3 and f.normal.x > 0.9]

    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh, stencil_faces


def _unwrap_quadrants_and_merge_material(
    obj: "bpy.types.Object",
    stencil_faces: list[int],
    final_mat: "bpy.types.Material",
) -> None:
    """Smart-project each material region into its own non-overlapping UV quadrant."""
    import bmesh
    import bpy

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    quads = {
        0: (0.02, 0.48, 0.52, 0.98),  # Top-Left: olive/ochre corrugated steel
        1: (0.52, 0.98, 0.52, 0.98),  # Top-Right: dark rusted frame & castings
        2: (0.02, 0.48, 0.02, 0.48),  # Bottom-Left: galvanized locking bars & hinges
    }

    for region_id, (u0, u1, v0, v1) in quads.items():
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")

        for poly in obj.data.polygons:
            if poly.material_index == region_id:
                poly.select = True

        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
        bpy.ops.object.mode_set(mode="OBJECT")

        bm = bmesh.new()
        bm.from_mesh(obj.data)
        uv_layer = bm.loops.layers.uv.verify()
        for f in bm.faces:
            if f.material_index != region_id:
                continue
            for loop in f.loops:
                uv = loop[uv_layer].uv
                loop[uv_layer].uv = (u0 + uv.x * (u1 - u0), v0 + uv.y * (v1 - v0))
        bm.to_mesh(obj.data)
        bm.free()

    # Map region 3 (stencil door leaf) cleanly
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.verify()
    stencil_set = set(stencil_faces)
    for f in bm.faces:
        if f.material_index != 3:
            continue
        if f.index in stencil_set:
            ys = [loop.vert.co.y for loop in f.loops]
            zs = [loop.vert.co.z for loop in f.loops]
            y_min, y_max = min(ys), max(ys)
            z_min, z_max = min(zs), max(zs)
            dy = max(y_max - y_min, 1e-5)
            dz = max(z_max - z_min, 1e-5)
            for loop in f.loops:
                ty = (loop.vert.co.y - y_min) / dy
                tz = (loop.vert.co.z - z_min) / dz
                loop[uv_layer].uv = (0.525 + ty * 0.45, 0.025 + tz * 0.45)
        else:
            for idx, loop in enumerate(f.loops):
                u = 0.51 + (0.01 if idx in (1, 2) else 0.0)
                v = 0.01 + (0.01 if idx in (2, 3) else 0.0)
                loop[uv_layer].uv = (u, v)

    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(obj.data)
    bm.free()

    obj.data.materials.clear()
    obj.data.materials.append(final_mat)


def build_prop() -> None:
    """Build freight_container GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh, stencil_faces = _build_geometry()
    obj = bpy.data.objects.new(PROP_SLUG, mesh)
    bpy.context.collection.objects.link(obj)

    final_mat = _create_atlas_material()
    _unwrap_quadrants_and_merge_material(obj, stencil_faces, final_mat)

    # Center XY at origin, guarantee min_z = 0.0, exact target height
    coords = [v.co for v in obj.data.vertices]
    min_x, max_x = min(c.x for c in coords), max(c.x for c in coords)
    min_y, max_y = min(c.y for c in coords), max(c.y for c in coords)
    min_z, max_z = min(c.z for c in coords), max(c.z for c in coords)
    scale_f = HEIGHT / max(max_z - min_z, 1e-5)
    cx = 0.5 * (min_x + max_x)
    cy = 0.5 * (min_y + max_y)
    for v in obj.data.vertices:
        v.co.x = (v.co.x - cx) * scale_f
        v.co.y = (v.co.y - cy) * scale_f
        v.co.z = (v.co.z - min_z) * scale_f
    obj.data.update()

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    tri_count = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    dims = obj.dimensions
    # Godot +Y up, -Z forward: Blender (X, Y, Z) -> Godot (X, Z, Y)
    godot_dims = [round(float(dims.x), 4), round(float(dims.z), 4), round(float(dims.y), 4)]

    glb_path = ASSET_DIR / f"{PROP_SLUG}.glb"
    export_godot_glb(glb_path, export_animations=False, apply_modifiers=True)

    manifest = {
        "prop_slug": PROP_SLUG,
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": godot_dims,
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "tri_budget": TRI_BUDGET,
        "material": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres",
        "mesh": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb",
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[OK] {PROP_SLUG}: tris={tri_count}/{TRI_BUDGET}, dims_m={godot_dims}, uv_layers={len(obj.data.uv_layers)}")


if __name__ == "__main__":
    if "--gen-textures" in sys.argv:
        generate_textures()
    else:
        build_prop()
