"""Procedural Post-Soviet Industrial Construction Dumpster / Skip + PBR ORMMaterial3D.

Dimensions: ~2.20m (X) x 1.50m (Z in Godot / Y in Blender) x 1.30m (Y in Godot / Z in Blender).
Origin: bottom-center (min_z = 0.0 in Blender -> min_y = 0.0 in Godot).
Tri budget: <= 2500 tris.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/dumpster.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/dumpster.py --gen-textures
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

PROP_SLUG: str = "dumpster"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TRI_BUDGET: int = 2500

# Construction skip dimensions (meters, Blender Z-up)
TOP_LEN: float = 2.20
TOP_WID: float = 1.50
BOT_LEN: float = 1.58
BOT_WID: float = 1.24
HEIGHT: float = 1.30


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


def _paint_skip_quadrant(
    size: int,
    base_rgb: tuple[int, int, int],
    fade_rgb: tuple[int, int, int],
    rust_rgb: tuple[int, int, int],
    bare_rgb: tuple[int, int, int],
    seed: int,
    rust_thresh: float = 0.58,
    base_metallic: float = 0.16,
) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize chipped dark green steel with rust blooms, scratches, and grime."""
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.50), (18, 0.35), (52, 0.15)])
    detail = _fbm_noise(size, size, seed + 19, [(28, 0.45), (92, 0.35), (210, 0.20)])
    streak_band = _fbm_noise(size, size, seed + 37, [(6, 0.30), (44, 0.70)])
    col_profile = np.mean(streak_band, axis=0, keepdims=True)
    streaks = np.clip(0.60 * col_profile + 0.40 * streak_band, 0.0, 1.0)

    rgb = np.zeros((size, size, 3), dtype=np.float32)
    for c in range(3):
        rgb[..., c] = base_rgb[c] * (1.0 - macro * 0.40) + fade_rgb[c] * (macro * 0.40)

    grime_mask = np.clip((streaks - 0.45) * 0.9, 0.0, 0.55)
    rgb = rgb * (1.0 - grime_mask[..., None] * 0.45)

    rust_score = 0.52 * macro + 0.28 * streaks + 0.20 * detail
    rust_mask = np.clip((rust_score - rust_thresh) / max(1.0 - rust_thresh, 1e-4), 0.0, 1.0)
    rust_mask = np.power(rust_mask, 0.85)
    for c in range(3):
        rgb[..., c] = rgb[..., c] * (1.0 - rust_mask) + rust_rgb[c] * rust_mask

    chip_mask = (detail > 0.79) & (rust_score < rust_thresh + 0.06)
    for c in range(3):
        rgb[..., c] = np.where(chip_mask, bare_rgb[c] * (0.85 + 0.3 * detail), rgb[..., c])

    rgb = rgb * (0.90 + 0.18 * detail[..., None])

    metallic = np.full((size, size), base_metallic, dtype=np.float32)
    metallic = np.where(rust_mask > 0.35, 0.05, metallic)
    metallic = np.where(chip_mask, 0.85, metallic)
    return np.clip(rgb, 30.0, 240.0), np.clip(metallic, 0.0, 1.0)


def _draw_stencil_plate(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize chipped dark green side plate with faded industrial stencil & hazard band."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont

    rgb, metallic = _paint_skip_quadrant(
        size,
        base_rgb=(42, 62, 48),
        fade_rgb=(58, 76, 56),
        rust_rgb=(98, 44, 22),
        bare_rgb=(104, 106, 108),
        seed=seed,
        rust_thresh=0.64,
        base_metallic=0.14,
    )

    img = Image.fromarray(rgb.astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img)

    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    if not Path(font_path).is_file():
        font_path = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
    font_lg = ImageFont.truetype(font_path, int(size * 0.072)) if Path(font_path).is_file() else ImageFont.load_default()
    font_sm = ImageFont.truetype(font_path, int(size * 0.052)) if Path(font_path).is_file() else ImageFont.load_default()

    cream = (204, 198, 174)
    yellow = (198, 156, 58)
    ink = (34, 34, 34)

    draw.text((size * 0.50, size * 0.28), "СТРОЙМУСОР", fill=cream, font=font_lg, anchor="mm")
    draw.text((size * 0.50, size * 0.44), "№ 04   8 Т", fill=yellow, font=font_sm, anchor="mm")

    # Worn diagonal hazard band at bottom of plate
    y0, y1 = int(size * 0.66), int(size * 0.78)
    draw.rectangle([int(size * 0.10), y0, int(size * 0.90), y1], fill=yellow, outline=ink, width=3)
    for sx in range(int(size * 0.10), int(size * 0.90), int(size * 0.10)):
        draw.polygon(
            [
                (sx, y1),
                (sx + int(size * 0.045), y1),
                (sx + int(size * 0.080), y0),
                (sx + int(size * 0.035), y0),
            ],
            fill=ink,
        )

    arr = np.asarray(img, dtype=np.float32)
    wear = _fbm_noise(size, size, seed + 77, [(12, 0.5), (42, 0.5)])
    arr = np.where(wear[..., None] > 0.70, rgb, arr)
    arr = arr * (0.90 + 0.16 * wear[..., None])
    return np.clip(arr, 30.0, 240.0), metallic


def generate_textures() -> None:
    """Synthesize 2048x2048 weathered dumpster PBR atlas + ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    # Q0 (Top-Left): Chipped dark green painted exterior steel & ribs
    q0_rgb, q0_met = _paint_skip_quadrant(
        half,
        base_rgb=(40, 60, 46),
        fade_rgb=(58, 76, 56),
        rust_rgb=(102, 46, 22),
        bare_rgb=(102, 104, 106),
        seed=111,
        rust_thresh=0.58,
        base_metallic=0.16,
    )
    # Q1 (Top-Right): Heavily scuffed/rusted dark interior steel & floor grime
    q1_rgb, q1_met = _paint_skip_quadrant(
        half,
        base_rgb=(54, 48, 42),
        fade_rgb=(68, 60, 50),
        rust_rgb=(88, 38, 20),
        bare_rgb=(86, 84, 82),
        seed=222,
        rust_thresh=0.46,
        base_metallic=0.22,
    )
    # Q2 (Bottom-Left): Forged/oxidized steel lifting lugs, trunnion pins & skid runners
    q2_rgb, q2_met = _paint_skip_quadrant(
        half,
        base_rgb=(98, 100, 102),
        fade_rgb=(116, 114, 108),
        rust_rgb=(94, 44, 22),
        bare_rgb=(132, 136, 140),
        seed=333,
        rust_thresh=0.64,
        base_metallic=0.76,
    )
    # Q3 (Bottom-Right): Stencil & hazard band plate
    q3_rgb, q3_met = _draw_stencil_plate(half, seed=444)

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
            "0.66",
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


def _add_tilted_box(
    bm: "bmesh.types.BMesh",
    p0: "Vector",
    p1: "Vector",
    width: float,
    depth: float,
    region: int,
) -> None:
    """Create a rectangular rib/strut along segment p0->p1 with cross-section width x depth."""
    import bmesh
    from mathutils import Matrix, Vector

    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return
    center = (p0 + p1) * 0.5
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(center) @ rot @ Matrix.Diagonal((width, depth, length, 1.0))
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    vset = set(verts)
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth=False)


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


def _build_skip_tub(bm: "bmesh.types.BMesh") -> None:
    """Build hollow flared trapezoidal skip tub with real wall thickness."""
    z_bot = 0.06
    z_top = HEIGHT - 0.08
    z_in_bot = 0.11
    wall = 0.045

    ox0, oy0 = BOT_LEN * 0.5, BOT_WID * 0.5
    ox1, oy1 = (TOP_LEN - 0.08) * 0.5, (TOP_WID - 0.08) * 0.5
    ix0, iy0 = ox0 - wall, oy0 - wall
    ix1, iy1 = ox1 - wall, oy1 - wall

    # Outer ring bottom & top
    ob = [
        bm.verts.new((-ox0, -oy0, z_bot)),
        bm.verts.new((ox0, -oy0, z_bot)),
        bm.verts.new((ox0, oy0, z_bot)),
        bm.verts.new((-ox0, oy0, z_bot)),
    ]
    ot = [
        bm.verts.new((-ox1, -oy1, z_top)),
        bm.verts.new((ox1, -oy1, z_top)),
        bm.verts.new((ox1, oy1, z_top)),
        bm.verts.new((-ox1, oy1, z_top)),
    ]
    # Inner ring bottom & top
    ib = [
        bm.verts.new((-ix0, -iy0, z_in_bot)),
        bm.verts.new((ix0, -iy0, z_in_bot)),
        bm.verts.new((ix0, iy0, z_in_bot)),
        bm.verts.new((-ix0, iy0, z_in_bot)),
    ]
    it = [
        bm.verts.new((-ix1, -iy1, z_top)),
        bm.verts.new((ix1, -iy1, z_top)),
        bm.verts.new((ix1, iy1, z_top)),
        bm.verts.new((-ix1, iy1, z_top)),
    ]

    ext_faces = []
    int_faces = []

    # Outer bottom cap (facing -Z)
    ext_faces.append(bm.faces.new((ob[3], ob[2], ob[1], ob[0])))
    # Inner floor (facing +Z)
    int_faces.append(bm.faces.new((ib[0], ib[1], ib[2], ib[3])))

    for i in range(4):
        ni = (i + 1) % 4
        # Outer wall
        ext_faces.append(bm.faces.new((ob[i], ob[ni], ot[ni], ot[i])))
        # Inner wall (reversed winding to face inward)
        int_faces.append(bm.faces.new((ib[ni], ib[i], it[i], it[ni])))
        # Top wall lip
        ext_faces.append(bm.faces.new((ot[i], ot[ni], it[ni], it[i])))

    _tag_faces(ext_faces, region_id=0, smooth=False)
    _tag_faces(int_faces, region_id=1, smooth=False)


def _build_geometry() -> tuple["bpy.types.Mesh", list[int]]:
    """Construct industrial construction skip/dumpster geometry."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    # 1. Hollow flared skip tub (region 0 outer, region 1 inner)
    _build_skip_tub(bm)

    # 2. Heavy box-section top rim collar (region 0)
    rim_h = 0.08
    rim_w = 0.08
    rim_z = HEIGHT - rim_h * 0.5
    for sy in (-1.0, 1.0):
        _add_box(bm, Vector((0.0, sy * (TOP_WID * 0.5 - rim_w * 0.5), rim_z)), Vector((TOP_LEN, rim_w, rim_h)), region=0)
    for sx in (-1.0, 1.0):
        _add_box(
            bm,
            Vector((sx * (TOP_LEN * 0.5 - rim_w * 0.5), 0.0, rim_z)),
            Vector((rim_w, TOP_WID - rim_w * 2.0, rim_h)),
            region=0,
        )

    # 3. Bottom skid runners (region 2 = forged/oxidized heavy steel)
    for sy in (-1.0, 1.0):
        _add_box(bm, Vector((0.0, sy * 0.44, 0.03)), Vector((BOT_LEN - 0.04, 0.12, 0.06)), region=2)
    # Cross-members between skids
    for sx in (-0.55, 0.0, 0.55):
        _add_box(bm, Vector((sx, 0.0, 0.03)), Vector((0.08, 0.76, 0.05)), region=2)

    # 4. Ribbed sides: 4 vertical flared ribs per long side (-Y, +Y)
    z_bot = 0.09
    z_top = HEIGHT - 0.08
    y_bot = BOT_WID * 0.5
    y_top = (TOP_WID - 0.08) * 0.5
    for sy in (-1.0, 1.0):
        for rx in (-0.66, -0.22, 0.22, 0.66):
            p0 = Vector((rx * (BOT_LEN / TOP_LEN), sy * (y_bot + 0.02), z_bot))
            p1 = Vector((rx, sy * (y_top + 0.02), z_top))
            _add_tilted_box(bm, p0, p1, width=0.065, depth=0.055, region=0)
        # Horizontal mid-belt reinforcement bar
        y_mid = 0.5 * (y_bot + y_top) + 0.018
        _add_box(bm, Vector((0.0, sy * y_mid, 0.68)), Vector((1.84, 0.045, 0.055)), region=0)

    # 2 vertical ribs on each sloped end (-X, +X)
    x_bot = BOT_LEN * 0.5
    x_top = (TOP_LEN - 0.08) * 0.5
    for sx in (-1.0, 1.0):
        for ry in (-0.36, 0.36):
            p0 = Vector((sx * (x_bot + 0.02), ry * (BOT_WID / TOP_WID), z_bot))
            p1 = Vector((sx * (x_top + 0.02), ry, z_top))
            _add_tilted_box(bm, p0, p1, width=0.055, depth=0.065, region=0)

    # 5. Lifting lugs & tipping trunnion pins (region 2)
    # 4 upper corner crane lifting lugs
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            lug_x = sx * (TOP_LEN * 0.5 - 0.14)
            lug_y = sy * (TOP_WID * 0.5 - 0.02)
            _add_box(bm, Vector((lug_x, lug_y, HEIGHT - 0.06)), Vector((0.12, 0.04, 0.14)), region=2)
            _add_cylinder(
                bm,
                Vector((lug_x, lug_y + sy * 0.03, HEIGHT - 0.02)),
                Vector((0.0, 1.0, 0.0)),
                0.032,
                0.06,
                10,
                region=2,
                smooth=True,
            )

    # 2 heavy side tipping trunnion pins + backing plates
    for sy in (-1.0, 1.0):
        y_mid = 0.5 * (y_bot + y_top) + 0.01
        _add_box(bm, Vector((0.0, sy * y_mid, 0.68)), Vector((0.20, 0.04, 0.18)), region=2)
        _add_cylinder(
            bm,
            Vector((0.0, sy * (y_mid + 0.06), 0.68)),
            Vector((0.0, 1.0, 0.0)),
            0.042,
            0.12,
            10,
            region=2,
            smooth=True,
        )

    # 2 lower chain-hook lugs on ends
    for sx in (-1.0, 1.0):
        x_low = sx * (0.5 * (x_bot + x_top) - 0.02)
        _add_box(bm, Vector((x_low, 0.0, 0.42)), Vector((0.06, 0.24, 0.12)), region=2)
        _add_cylinder(
            bm,
            Vector((x_low + sx * 0.05, 0.0, 0.42)),
            Vector((1.0, 0.0, 0.0)),
            0.028,
            0.08,
            8,
            region=2,
            smooth=True,
        )

    # 6. Stencil/hazard sign plate on -Y front side (region 3)
    y_plate = -(0.5 * (y_bot + y_top) + 0.035)
    _add_box(bm, Vector((0.0, y_plate, 0.92)), Vector((0.52, 0.012, 0.30)), region=3)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    stencil_faces = [f.index for f in bm.faces if f.material_index == 3 and f.normal.y < -0.9]

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
        0: (0.02, 0.48, 0.52, 0.98),  # Top-Left: chipped dark green steel
        1: (0.52, 0.98, 0.52, 0.98),  # Top-Right: scuffed interior steel
        2: (0.02, 0.48, 0.02, 0.48),  # Bottom-Left: lifting lugs, trunnions & skids
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

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.verify()
    stencil_set = set(stencil_faces)
    for f in bm.faces:
        if f.material_index != 3:
            continue
        if f.index in stencil_set:
            xs = [loop.vert.co.x for loop in f.loops]
            zs = [loop.vert.co.z for loop in f.loops]
            x_min, x_max = min(xs), max(xs)
            z_min, z_max = min(zs), max(zs)
            dx = max(x_max - x_min, 1e-5)
            dz = max(z_max - z_min, 1e-5)
            for loop in f.loops:
                tx = (loop.vert.co.x - x_min) / dx
                tz = (loop.vert.co.z - z_min) / dz
                loop[uv_layer].uv = (0.525 + tx * 0.45, 0.025 + tz * 0.45)
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
    """Build dumpster GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh, stencil_faces = _build_geometry()
    obj = bpy.data.objects.new(PROP_SLUG, mesh)
    bpy.context.collection.objects.link(obj)

    final_mat = _create_atlas_material()
    _unwrap_quadrants_and_merge_material(obj, stencil_faces, final_mat)

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
