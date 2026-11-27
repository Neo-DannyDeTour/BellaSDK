"""Procedural 1000L IBC Tote Water Tank (HDPE Tank, Galvanized Cage, Pallet & Valve).

Generates the 1.16m-tall Post-Soviet Industrial Gothic 1000L IBC water tank
prop (~1.2m x 1.0m x 1.16m), with non-overlapping quadrant UVs, weathered PBR
texture maps via process_pbr.py, Godot 4 ORMMaterial3D (.tres), GLB, and
asset_manifest.json.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/water_tank.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/water_tank.py --gen-textures
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

PROP_SLUG: str = "water_tank"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TARGET_HEIGHT_M: float = 1.16
TRI_BUDGET: int = 3500

# IBC tote dimensions (meters, Blender Z-up, front facing -Y)
PALLET_W: float = 1.20
PALLET_D: float = 1.00
PALLET_H: float = 0.14

TANK_W: float = 1.12
TANK_D: float = 0.92
TANK_H: float = 0.94
TANK_Z0: float = PALLET_H

CAGE_W: float = 1.18
CAGE_D: float = 0.98
CAGE_Z0: float = PALLET_H
CAGE_Z1: float = 1.13
TUBE_R: float = 0.011


def _fbm_noise(h: int, w: int, seed: int, octaves: list[tuple[int, float]]) -> "np.ndarray":
    """Generate smooth multi-octave 2D value noise in [0, 1] using numpy + PIL."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    weight_sum = 0.0
    for grid_res, weight in octaves:
        grid = rng.random((grid_res, grid_res), dtype=np.float32)
        img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
        up = img.resize((w, h), Image.Resampling.BILINEAR)
        acc += (np.asarray(up, dtype=np.float32) / 255.0) * weight
        weight_sum += weight
    return np.clip(acc / max(weight_sum, 1e-6), 0.0, 1.0)


def _streak_noise(h: int, w: int, seed: int, cols: int = 96, rows: int = 12) -> "np.ndarray":
    """Generate vertically elongated rain/grime streak noise in [0, 1]."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    grid = rng.random((rows, cols), dtype=np.float32)
    img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
    up = img.resize((w, h), Image.Resampling.BICUBIC)
    return np.clip(np.asarray(up, dtype=np.float32) / 255.0, 0.0, 1.0)


def _paint_quadrant(
    size: int,
    base_rgb: tuple[int, int, int],
    fade_rgb: tuple[int, int, int],
    grime_rgb: tuple[int, int, int],
    chip_rgb: tuple[int, int, int],
    seed: int,
    base_metallic: float = 0.0,
    chip_metallic: float = 0.0,
    chip_thresh: float = 0.87,
) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize weathered material RGB and metallic mask for one UV quadrant."""
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.55), (16, 0.30), (48, 0.15)])
    streaks = _streak_noise(size, size, seed + 17, cols=110, rows=10)
    fine = _fbm_noise(size, size, seed + 31, [(64, 0.5), (192, 0.5)])
    chips = _fbm_noise(size, size, seed + 73, [(28, 0.45), (96, 0.55)])

    base = np.array(base_rgb, dtype=np.float32)
    fade = np.array(fade_rgb, dtype=np.float32)
    grime = np.array(grime_rgb, dtype=np.float32)
    chip = np.array(chip_rgb, dtype=np.float32)

    col = base[None, None, :] * (1.0 - 0.45 * macro[..., None]) + fade[None, None, :] * (
        0.45 * macro[..., None]
    )
    grime_mask = np.clip((streaks - 0.48) * 0.72, 0.0, 0.35)
    col = col * (1.0 - grime_mask[..., None]) + grime[None, None, :] * grime_mask[..., None]
    col += (fine[..., None] - 0.5) * 14.0

    chip_mask = (chips > chip_thresh).astype(np.float32)
    col = col * (1.0 - chip_mask[..., None]) + chip[None, None, :] * chip_mask[..., None]

    metallic = np.full((size, size), base_metallic, dtype=np.float32)
    metallic = metallic * (1.0 - chip_mask) + chip_metallic * chip_mask
    return col, metallic


def _draw_placard_and_red_quadrant(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Draw weathered oxide-red cap/valve zone (top half) and spec placard (bottom half)."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont

    half_h = size // 2
    red_rgb, red_met = _paint_quadrant(
        size=size,
        base_rgb=(138, 46, 44),
        fade_rgb=(162, 68, 62),
        grime_rgb=(78, 30, 28),
        chip_rgb=(54, 48, 44),
        seed=seed,
        base_metallic=0.04,
        chip_metallic=0.08,
        chip_thresh=0.88,
    )

    plate_rgb, plate_met = _paint_quadrant(
        size=size,
        base_rgb=(176, 174, 162),
        fade_rgb=(194, 190, 178),
        grime_rgb=(116, 110, 96),
        chip_rgb=(92, 74, 58),
        seed=seed + 55,
        base_metallic=0.35,
        chip_metallic=0.70,
        chip_thresh=0.89,
    )

    # Composite top half = red HDPE cap/valve, bottom half = galvanized spec placard
    col = red_rgb.copy()
    col[half_h:, :] = plate_rgb[half_h:, :]
    metallic = red_met.copy()
    metallic[half_h:, :] = plate_met[half_h:, :]

    img = Image.fromarray(np.clip(col, 30, 240).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img)

    pad_x = int(size * 0.06)
    y0 = half_h + int(half_h * 0.10)
    y1 = size - int(half_h * 0.10)
    bw = max(4, int(size * 0.008))
    ink = (36, 36, 34)
    draw.rectangle([pad_x, y0, size - pad_x, y1], outline=ink, width=bw)

    font_path = "/usr/share/fonts/truetype/noto/NotoSans-CondensedBold.ttf"
    if not Path(font_path).is_file():
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
    font_lg = ImageFont.truetype(font_path, int(size * 0.075))
    font_sm = ImageFont.truetype(font_path, int(size * 0.045))

    draw.text((size * 0.50, half_h + half_h * 0.34), "ТЕХ. ВОДА", fill=ink, font=font_lg, anchor="mm")
    draw.text((size * 0.50, half_h + half_h * 0.62), "1000 Л  |  IBC-T1", fill=ink, font=font_sm, anchor="mm")

    arr = np.asarray(img, dtype=np.float32)
    dust = _fbm_noise(size, size, seed + 91, [(12, 0.5), (40, 0.5)])
    arr[half_h:, :] *= 0.88 + 0.14 * dust[half_h:, :, None]
    return np.clip(arr, 30.0, 240.0), metallic


def generate_textures() -> None:
    """Synthesize weathered 2048x2048 PBR texture atlas and compile ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    # Q0 (Top-Left): Stained translucent-style milky-gray HDPE tank with mineral/algae grime
    q0_rgb, q0_met = _paint_quadrant(
        half,
        base_rgb=(188, 186, 174),
        fade_rgb=(208, 204, 188),
        grime_rgb=(118, 114, 92),
        chip_rgb=(142, 138, 120),
        seed=111,
        base_metallic=0.0,
        chip_metallic=0.0,
        chip_thresh=0.90,
    )
    # Subtle water-level algae/sediment tint toward bottom of Q0
    grad_y = np.linspace(0.0, 1.0, half, dtype=np.float32)[:, None, None]
    algae = np.array([104.0, 112.0, 82.0], dtype=np.float32)[None, None, :]
    q0_rgb = q0_rgb * (1.0 - 0.22 * grad_y) + algae * (0.22 * grad_y)

    # Q1 (Top-Right): Weathered galvanized zinc-steel cage + pallet runners
    q1_rgb, q1_met = _paint_quadrant(
        half,
        base_rgb=(142, 146, 148),
        fade_rgb=(166, 170, 172),
        grime_rgb=(98, 92, 82),
        chip_rgb=(114, 72, 46),
        seed=222,
        base_metallic=0.78,
        chip_metallic=0.25,
        chip_thresh=0.84,
    )

    # Q2 (Bottom-Left): Dark rusted steel pallet blocks + black rubber/iron valve body
    q2_rgb, q2_met = _paint_quadrant(
        half,
        base_rgb=(54, 56, 58),
        fade_rgb=(74, 72, 68),
        grime_rgb=(38, 36, 34),
        chip_rgb=(96, 58, 38),
        seed=333,
        base_metallic=0.45,
        chip_metallic=0.20,
        chip_thresh=0.82,
    )

    # Q3 (Bottom-Right): Oxide-red cap/valve handle (top) + spec placard (bottom)
    q3_rgb, q3_met = _draw_placard_and_red_quadrant(half, seed=444)

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
            "0.56",
            "--normal-strength",
            "1.8",
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
    nrm_node.inputs["Strength"].default_value = 0.70
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


def _add_beveled_box(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    size: "Vector",
    bevel: float,
    region: int,
    smooth: bool = True,
) -> None:
    import bmesh
    from mathutils import Matrix

    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    mat = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    vset = set(verts)
    edges = [e for e in bm.edges if all(v in vset for v in e.verts)]
    bev = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect="EDGES")
    all_verts = vset | set(bev.get("verts", []))
    _tag_faces([f for f in bm.faces if all(v in all_verts for v in f.verts)], region, smooth)


def _add_cylinder(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    axis: "Vector",
    radius: float,
    depth: float,
    segments: int,
    region: int,
    smooth: bool = True,
) -> None:
    import bmesh
    from mathutils import Matrix, Vector

    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(center) @ rot
    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
        matrix=mat,
    )
    vset = set(ret["verts"])
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth)


def _add_tube(bm: "bmesh.types.BMesh", p0: "Vector", p1: "Vector", half_w: float, region: int) -> None:
    """Add a 4-sided square galvanized steel tube between p0 and p1."""
    import bmesh
    from mathutils import Matrix, Vector

    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return
    mid = (p0 + p1) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(mid) @ rot @ Matrix.Diagonal((half_w * 2.0, half_w * 2.0, length, 1.0))
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    vset = set(verts)
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, False)


def _build_geometry() -> tuple["bpy.types.Mesh", list[int], list[int]]:
    """Build IBC water tank geometry with 4 region slots and return mesh + special face indices."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    # 1. Pallet Base (z = 0.00 to 0.14m)
    # 3 bottom steel skid runners along X
    for py in (-0.43, 0.0, 0.43):
        _add_box(bm, Vector((0.0, py, 0.012)), Vector((PALLET_W, 0.10, 0.024)), region=1)
    # 9 dark steel/composite corner & mid spacer blocks (z = 0.024 to 0.116)
    for px in (-0.52, 0.0, 0.52):
        for py in (-0.43, 0.0, 0.43):
            _add_box(bm, Vector((px, py, 0.070)), Vector((0.14, 0.10, 0.092)), region=2)
    # Upper galvanized deck tray (z = 0.116 to 0.140)
    _add_box(bm, Vector((0.0, 0.0, 0.128)), Vector((PALLET_W, PALLET_D, 0.024)), region=1)

    # 2. Inner HDPE Tank (z = 0.14 to 1.08m) - beveled box + top neck + valve recess
    tank_cz = TANK_Z0 + TANK_H * 0.5
    _add_beveled_box(
        bm,
        Vector((0.0, 0.0, tank_cz)),
        Vector((TANK_W, TANK_D, TANK_H)),
        bevel=0.055,
        region=0,
        smooth=True,
    )
    # Molded top fill neck collar (z = 1.08 to 1.11m)
    _add_cylinder(bm, Vector((0.0, 0.0, 1.095)), Vector((0.0, 0.0, 1.0)), 0.115, 0.035, 16, region=0, smooth=True)
    # Red ribbed screw cap on top (z = 1.11 to 1.16m) -> region 3 (upper half)
    _add_cylinder(bm, Vector((0.0, 0.0, 1.135)), Vector((0.0, 0.0, 1.0)), 0.125, 0.050, 16, region=3, smooth=True)
    # Small breather bung next to cap
    _add_cylinder(bm, Vector((0.20, 0.0, 1.105)), Vector((0.0, 0.0, 1.0)), 0.032, 0.030, 10, region=2, smooth=True)

    # 3. Bottom Drain Valve (front -Y face at z = 0.21m)
    vy = -TANK_D * 0.5
    vz = 0.21
    # Flange + outlet body (dark iron/HDPE, region 2)
    _add_cylinder(bm, Vector((0.0, vy - 0.025, vz)), Vector((0.0, 1.0, 0.0)), 0.055, 0.05, 12, region=2, smooth=True)
    _add_cylinder(bm, Vector((0.0, vy - 0.070, vz)), Vector((0.0, 1.0, 0.0)), 0.036, 0.07, 12, region=2, smooth=True)
    # Red valve lever handle (region 3 upper half)
    _add_box(bm, Vector((0.04, vy - 0.065, vz + 0.048)), Vector((0.11, 0.022, 0.020)), region=3)

    # 4. Galvanized Steel Cage (region 1)
    hx = CAGE_W * 0.5
    hy = CAGE_D * 0.5
    # 4 horizontal perimeter rings
    for rz in (0.155, 0.43, 0.74, 1.115):
        _add_tube(bm, Vector((-hx, -hy, rz)), Vector((hx, -hy, rz)), TUBE_R, region=1)
        _add_tube(bm, Vector((-hx, hy, rz)), Vector((hx, hy, rz)), TUBE_R, region=1)
        _add_tube(bm, Vector((-hx, -hy, rz)), Vector((-hx, hy, rz)), TUBE_R, region=1)
        _add_tube(bm, Vector((hx, -hy, rz)), Vector((hx, hy, rz)), TUBE_R, region=1)

    # Vertical cage bars on front (-Y) and back (+Y)
    for vx in (-hx, -0.36, -0.14, 0.14, 0.36, hx):
        _add_tube(bm, Vector((vx, -hy, 0.155)), Vector((vx, -hy, 1.115)), TUBE_R, region=1)
        _add_tube(bm, Vector((vx, hy, 0.155)), Vector((vx, hy, 1.115)), TUBE_R, region=1)

    # Vertical cage bars on left (-X) and right (+X)
    for vy_bar in (-0.28, 0.0, 0.28):
        _add_tube(bm, Vector((-hx, vy_bar, 0.155)), Vector((-hx, vy_bar, 1.115)), TUBE_R, region=1)
        _add_tube(bm, Vector((hx, vy_bar, 0.155)), Vector((hx, vy_bar, 1.115)), TUBE_R, region=1)

    # 2 top tie-bars bridging across tank roof (avoiding center cap)
    for tx in (-0.36, 0.36):
        _add_tube(bm, Vector((tx, -hy, 1.115)), Vector((tx, hy, 1.115)), TUBE_R, region=1)

    # 5. Front Spec Placard mounted on upper-front cage bars
    placard_w = 0.46
    placard_h = 0.24
    placard_cz = 0.93
    _add_box(bm, Vector((0.0, -hy - 0.012, placard_cz)), Vector((placard_w, 0.008, placard_h)), region=3)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()

    # Separate region 3 faces into: placard front face (-Y normal at y < -hy) vs red cap/valve
    placard_front_indices = [
        f.index
        for f in bm.faces
        if f.material_index == 3 and f.normal.y < -0.9 and f.calc_center_median().y < -hy
    ]
    placard_side_indices = [
        f.index
        for f in bm.faces
        if f.material_index == 3 and f.index not in placard_front_indices and f.calc_center_median().y < -hy
    ]

    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh, placard_front_indices, placard_side_indices


def _unwrap_quadrants_and_merge_material(
    obj: "bpy.types.Object",
    placard_front_indices: list[int],
    placard_side_indices: list[int],
    final_mat: "bpy.types.Material",
) -> None:
    """Smart-project each material region into its own non-overlapping UV quadrant."""
    import bmesh
    import bpy

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Region bounds in Blender UV space (PIL y=0 top -> Blender V=1.0 top)
    quads = {
        0: (0.02, 0.48, 0.52, 0.98),  # Top-Left: stained HDPE tank
        1: (0.52, 0.98, 0.52, 0.98),  # Top-Right: galvanized cage + pallet
        2: (0.02, 0.48, 0.02, 0.48),  # Bottom-Left: dark steel blocks + valve body
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

    # Map Region 3:
    # - placard front face -> Q3 bottom half (V: 0.02..0.23, U: 0.52..0.98)
    # - placard back/sides -> Q3 bottom border
    # - red cap + valve handle -> Q3 top half (V: 0.27..0.48, U: 0.52..0.98)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")

    pfront_set = set(placard_front_indices)
    pside_set = set(placard_side_indices)
    for poly in obj.data.polygons:
        if poly.material_index == 3 and poly.index not in pfront_set and poly.index not in pside_set:
            poly.select = True

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        if f.material_index != 3:
            continue
        if f.index in pfront_set:
            xs = [loop.vert.co.x for loop in f.loops]
            zs = [loop.vert.co.z for loop in f.loops]
            x_min, x_max = min(xs), max(xs)
            z_min, z_max = min(zs), max(zs)
            dx = max(x_max - x_min, 1e-5)
            dz = max(z_max - z_min, 1e-5)
            for loop in f.loops:
                tx = (loop.vert.co.x - x_min) / dx
                tz = (loop.vert.co.z - z_min) / dz
                loop[uv_layer].uv = (0.525 + tx * 0.45, 0.02 + tz * 0.21)
        elif f.index in pside_set:
            for idx, loop in enumerate(f.loops):
                u = 0.51 + (0.01 if idx in (1, 2) else 0.0)
                v = 0.01 + (0.01 if idx in (2, 3) else 0.0)
                loop[uv_layer].uv = (u, v)
        else:
            for loop in f.loops:
                uv = loop[uv_layer].uv
                loop[uv_layer].uv = (0.52 + uv.x * 0.46, 0.27 + uv.y * 0.21)

    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(obj.data)
    bm.free()

    obj.data.materials.clear()
    obj.data.materials.append(final_mat)


def build_prop() -> None:
    """Build water_tank GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh, placard_front_indices, placard_side_indices = _build_geometry()
    obj = bpy.data.objects.new("water_tank", mesh)
    bpy.context.collection.objects.link(obj)

    final_mat = _create_atlas_material()
    _unwrap_quadrants_and_merge_material(obj, placard_front_indices, placard_side_indices, final_mat)

    # Center XY at origin, guarantee min_z = 0, exact target height 1.16m
    coords = [v.co for v in obj.data.vertices]
    min_x, max_x = min(c.x for c in coords), max(c.x for c in coords)
    min_y, max_y = min(c.y for c in coords), max(c.y for c in coords)
    min_z, max_z = min(c.z for c in coords), max(c.z for c in coords)
    scale_f = TARGET_HEIGHT_M / max(max_z - min_z, 1e-5)
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
