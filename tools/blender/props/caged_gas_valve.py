"""Procedural Caged Gas Valve (Yellow Pipe, Red Gate Valve, Mesh Cage & Sign).

Generates the 1.55m-tall industrial caged gas valve prop matching ref
IMG_20261125_161747.jpg, with non-overlapping quadrant UVs, weathered PBR
texture maps via process_pbr.py, Godot 4 ORMMaterial3D (.tres), GLB, and
asset_manifest.json.

Run headless via Blender:
    python3 tools/blender/run.py tools/blender/props/caged_gas_valve.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/caged_gas_valve.py --gen-textures
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

PROP_SLUG: str = "caged_gas_valve"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
REF_IMAGE: str = "/home/dkd/Desktop/Refs/IMG_20261125_161747.jpg"
TARGET_HEIGHT_M: float = 1.55
TRI_BUDGET: int = 2000

# Cage dimensions (meters, Blender Z-up, front facing -Y)
CAGE_W: float = 2.18
CAGE_D: float = 0.76
CAGE_H: float = 1.55
TUBE_W: float = 0.036
RAIL_BOT_Z: float = 0.09
RAIL_TOP_Z: float = CAGE_H - TUBE_W * 0.5
DOOR_DIV_X: float = -0.34
BAR_W: float = 0.008
BAR_T: float = 0.006

# Pipe & valve dimensions (meters)
PIPE_R: float = 0.080
PIPE_Z: float = 0.86
PIPE_Y: float = 0.02
PIPE_LEFT_X: float = -0.72
PIPE_RIGHT_X: float = 0.84
PIPE_RIGHT_BACK_Y: float = 0.18
VALVE_CX: float = 0.16


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
    chip_thresh: float = 0.87,
) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize weathered painted steel RGB and metallic mask for one UV quadrant."""
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.55), (16, 0.30), (48, 0.15)])
    streaks = _streak_noise(size, size, seed + 17, cols=110, rows=10)
    fine = _fbm_noise(size, size, seed + 31, [(64, 0.5), (192, 0.5)])
    chips = _fbm_noise(size, size, seed + 73, [(28, 0.45), (96, 0.55)])

    base = np.array(base_rgb, dtype=np.float32)
    fade = np.array(fade_rgb, dtype=np.float32)
    grime = np.array(grime_rgb, dtype=np.float32)
    chip = np.array(chip_rgb, dtype=np.float32)

    col = base[None, None, :] * (1.0 - 0.45 * macro[..., None]) + fade[None, None, :] * (0.45 * macro[..., None])
    grime_mask = np.clip((streaks - 0.50) * 0.70, 0.0, 0.30)
    col = col * (1.0 - grime_mask[..., None]) + grime[None, None, :] * grime_mask[..., None]
    col += (fine[..., None] - 0.5) * 12.0

    chip_mask = (chips > chip_thresh).astype(np.float32)
    col = col * (1.0 - chip_mask[..., None]) + chip[None, None, :] * chip_mask[..., None]

    # Painted metal has low metallic (~0.15), chipped bare steel spots are metallic (~0.80)
    metallic = np.full((size, size), 0.15, dtype=np.float32)
    metallic = metallic * (1.0 - chip_mask) + 0.80 * chip_mask
    return col, metallic


def _draw_warning_sign(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Draw weathered yellow/black Kazakh+Russian gas hazard sign in Q3."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont

    # Base aged yellow enamel sign background
    col, metallic = _paint_quadrant(
        size=size,
        base_rgb=(206, 186, 76),
        fade_rgb=(218, 200, 96),
        grime_rgb=(142, 124, 52),
        chip_rgb=(82, 70, 56),
        seed=seed,
        chip_thresh=0.92,
    )
    img = Image.fromarray(np.clip(col, 30, 240).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img)

    pad = int(size * 0.05)
    bw = max(6, int(size * 0.012))
    ink = (34, 34, 32)

    # Outer black border
    draw.rectangle([pad, pad, size - pad, size - pad], outline=ink, width=bw)

    font_path = "/usr/share/fonts/truetype/noto/NotoSans-CondensedBold.ttf"
    if not Path(font_path).is_file():
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"

    font_lg = ImageFont.truetype(font_path, int(size * 0.095))
    font_sm = ImageFont.truetype(font_path, int(size * 0.038))

    # Top Kazakh text
    draw.text(
        (size * 0.50, size * 0.21),
        "ӨРТКЕ ҚАУІПТІ-ГАЗ!",
        fill=ink,
        font=font_lg,
        anchor="mm",
    )

    # Center yellow/black hazard triangle + side stickers
    cx, cy = size * 0.50, size * 0.49
    tri_r = size * 0.115
    pts = [
        (cx, cy - tri_r * 0.95),
        (cx - tri_r * 0.95, cy + tri_r * 0.72),
        (cx + tri_r * 0.95, cy + tri_r * 0.72),
    ]
    draw.polygon(pts, fill=(214, 194, 68), outline=ink)
    draw.line(pts + [pts[0]], fill=ink, width=max(4, int(size * 0.009)))
    # Flame silhouette inside triangle
    draw.polygon(
        [
            (cx, cy - tri_r * 0.45),
            (cx - tri_r * 0.22, cy + tri_r * 0.15),
            (cx + tri_r * 0.22, cy + tri_r * 0.15),
        ],
        fill=ink,
    )
    draw.text((cx, cy + tri_r * 0.44), "ГАЗ", fill=ink, font=font_sm, anchor="mm")

    # Small left/right faded hazard decals matching reference photo
    s_w, s_h = int(size * 0.075), int(size * 0.055)
    draw.rectangle([int(size * 0.26), int(cy - s_h * 0.5), int(size * 0.26 + s_w), int(cy + s_h * 0.5)], fill=(216, 212, 198), outline=ink, width=2)
    draw.rectangle([int(size * 0.67), int(cy - s_h * 0.5), int(size * 0.67 + s_w), int(cy + s_h * 0.5)], fill=(64, 108, 146), outline=ink, width=2)

    # Bottom Russian text
    draw.text(
        (size * 0.50, size * 0.77),
        "ОГНЕОПАСНО-ГАЗ!",
        fill=ink,
        font=font_lg,
        anchor="mm",
    )

    # Subtle grime & corner bolt wear over printed ink
    arr = np.asarray(img, dtype=np.float32)
    dust = _fbm_noise(size, size, seed + 99, [(10, 0.5), (36, 0.5)])
    arr = arr * (0.90 + 0.12 * dust[..., None])
    return np.clip(arr, 30.0, 240.0), metallic


def generate_textures() -> None:
    """Synthesize weathered 2048x2048 PBR texture atlas and compile ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    # Q0 (Top-Left, UV U:0..0.5 V:0.5..1.0): Mustard-yellow cage + gas pipe
    q0_rgb, q0_met = _paint_quadrant(
        half,
        base_rgb=(210, 176, 82),
        fade_rgb=(224, 194, 102),
        grime_rgb=(156, 128, 56),
        chip_rgb=(82, 74, 62),
        seed=101,
        chip_thresh=0.89,
    )
    # Q1 (Top-Right, UV U:0.5..1.0 V:0.5..1.0): Weathered oxide-red gate valve + flange
    q1_rgb, q1_met = _paint_quadrant(
        half,
        base_rgb=(152, 54, 56),
        fade_rgb=(172, 78, 76),
        grime_rgb=(88, 36, 36),
        chip_rgb=(104, 98, 92),
        seed=202,
        chip_thresh=0.85,
    )
    # Q2 (Bottom-Left, UV U:0..0.5 V:0..0.5): Galvanized gray pedestal + hardware
    q2_rgb, q2_met = _paint_quadrant(
        half,
        base_rgb=(138, 142, 146),
        fade_rgb=(158, 162, 164),
        grime_rgb=(96, 94, 88),
        chip_rgb=(78, 80, 82),
        seed=303,
        chip_thresh=0.88,
    )
    q2_met = np.clip(q2_met * 0.5 + 0.55, 0.50, 0.85)
    # Q3 (Bottom-Right, UV U:0.5..1.0 V:0..0.5): Warning sign plate
    q3_rgb, q3_met = _draw_warning_sign(half, seed=404)

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
            "0.58",
            "--normal-strength",
            "2.0",
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


def _add_cylinder(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    axis: "Vector",
    radius: float,
    depth: float,
    segments: int,
    region: int,
    smooth: bool = True,
    cap_ends: bool = True,
) -> None:
    import bmesh
    from mathutils import Matrix, Vector

    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(center) @ rot
    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
        matrix=mat,
    )
    vset = set(ret["verts"])
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth)


def _add_frustum(
    bm: "bmesh.types.BMesh",
    p0: "Vector",
    p1: "Vector",
    r0: float,
    r1: float,
    segments: int,
    region: int,
    smooth: bool = True,
) -> None:
    import bmesh
    from mathutils import Matrix, Vector

    delta = p1 - p0
    depth = delta.length
    if depth < 1e-5:
        return
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation((p0 + p1) * 0.5) @ rot
    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=r0,
        radius2=r1,
        depth=depth,
        matrix=mat,
    )
    vset = set(ret["verts"])
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth)


def _add_bar(
    bm: "bmesh.types.BMesh",
    p0: "Vector",
    p1: "Vector",
    normal: "Vector",
    width: float,
    thick: float,
    region: int,
) -> None:
    """Add an open-ended 4-sided steel mesh bar between p0 and p1 (8 tris)."""
    from mathutils import Vector

    axis = p1 - p0
    if axis.length < 1e-4:
        return
    t_dir = axis.normalized()
    n_dir = normal.normalized()
    b_dir = n_dir.cross(t_dir).normalized()

    hw = width * 0.5
    ht = thick * 0.5
    offsets = [
        -b_dir * hw - n_dir * ht,
        b_dir * hw - n_dir * ht,
        b_dir * hw + n_dir * ht,
        -b_dir * hw + n_dir * ht,
    ]
    v0 = [bm.verts.new(p0 + off) for off in offsets]
    v1 = [bm.verts.new(p1 + off) for off in offsets]
    faces = []
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((v0[i], v0[j], v1[j], v1[i])))
    _tag_faces(faces, region, smooth=False)


def _add_diamond_panel(
    bm: "bmesh.types.BMesh",
    origin: "Vector",
    u_dir: "Vector",
    v_dir: "Vector",
    normal: "Vector",
    width: float,
    height: float,
    spacing: float,
    region: int,
) -> None:
    """Fill rectangular bay [0..width] x [0..height] with 45-deg diagonal steel bars."""
    # Parameterize diagonal lines u - v = c and u + v = c
    step = spacing * math.sqrt(2.0)

    def clip_line(slope_sign: int, c_val: float) -> tuple[float, float, float, float] | None:
        # Line: v = slope_sign * u + c_val, clipped to [0, width] x [0, height]
        pts: list[tuple[float, float]] = []
        for u in (0.0, width):
            v = slope_sign * u + c_val
            if -1e-5 <= v <= height + 1e-5:
                pts.append((u, max(0.0, min(height, v))))
        for v in (0.0, height):
            u = (v - c_val) * slope_sign
            if 1e-5 < u < width - 1e-5:
                pts.append((u, v))
        if len(pts) < 2:
            return None
        pts.sort()
        if (pts[-1][0] - pts[0][0]) ** 2 + (pts[-1][1] - pts[0][1]) ** 2 < 0.08 ** 2:
            return None
        return pts[0][0], pts[0][1], pts[-1][0], pts[-1][1]

    c_min_pos = -width + step * 0.5
    c_max_pos = height - step * 0.5
    c = c_min_pos
    while c <= c_max_pos:
        seg = clip_line(1, c)
        if seg is not None:
            p0 = origin + u_dir * seg[0] + v_dir * seg[1]
            p1 = origin + u_dir * seg[2] + v_dir * seg[3]
            _add_bar(bm, p0, p1, normal, BAR_W, BAR_T, region)
        c += step

    c_min_neg = step * 0.5
    c_max_neg = width + height - step * 0.5
    c = c_min_neg
    while c <= c_max_neg:
        seg = clip_line(-1, c)
        if seg is not None:
            p0 = origin + u_dir * seg[0] + v_dir * seg[1]
            p1 = origin + u_dir * seg[2] + v_dir * seg[3]
            _add_bar(bm, p0, p1, normal, BAR_W, BAR_T, region)
        c += step


def _add_swept_pipe(
    bm: "bmesh.types.BMesh",
    points: list["Vector"],
    radius: float,
    segments: int,
    region: int,
) -> None:
    """Sweep a circular cross-section cleanly along a 3D polyline."""
    from mathutils import Vector

    rings: list[list] = []
    prev_up = Vector((0.0, 1.0, 0.0))

    for idx, pt in enumerate(points):
        if idx == 0:
            tangent = (points[1] - points[0]).normalized()
        elif idx == len(points) - 1:
            tangent = (points[-1] - points[-2]).normalized()
        else:
            t0 = (pt - points[idx - 1]).normalized()
            t1 = (points[idx + 1] - pt).normalized()
            tangent = (t0 + t1).normalized()
            if tangent.length < 1e-4:
                tangent = t0

        # Parallel transport frame to avoid twist across 90-degree bends
        u_axis = prev_up - tangent * prev_up.dot(tangent)
        if u_axis.length < 1e-4:
            fallback = Vector((1.0, 0.0, 0.0)) if abs(tangent.x) < 0.8 else Vector((0.0, 0.0, 1.0))
            u_axis = fallback - tangent * fallback.dot(tangent)
        u_axis.normalize()
        v_axis = tangent.cross(u_axis).normalized()
        prev_up = u_axis

        ring = []
        for s in range(segments):
            ang = 2.0 * math.pi * s / segments
            offset = (u_axis * math.cos(ang) + v_axis * math.sin(ang)) * radius
            ring.append(bm.verts.new(pt + offset))
        rings.append(ring)

    faces = []
    for r_idx in range(len(rings) - 1):
        r0 = rings[r_idx]
        r1 = rings[r_idx + 1]
        for s in range(segments):
            sn = (s + 1) % segments
            faces.append(bm.faces.new((r0[s], r0[sn], r1[sn], r1[s])))
    _tag_faces(faces, region, smooth=True)


def _add_torus_ring(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    major_r: float,
    minor_r: float,
    major_segs: int,
    minor_segs: int,
    region: int,
) -> None:
    """Create horizontal handwheel rim torus centered at `center`."""
    from mathutils import Vector

    rings = []
    for i in range(major_segs):
        theta = 2.0 * math.pi * i / major_segs
        radial = Vector((math.cos(theta), math.sin(theta), 0.0))
        ring_c = center + radial * major_r
        ring = []
        for j in range(minor_segs):
            phi = 2.0 * math.pi * j / minor_segs
            off = radial * (math.cos(phi) * minor_r) + Vector((0.0, 0.0, math.sin(phi) * minor_r))
            ring.append(bm.verts.new(ring_c + off))
        rings.append(ring)

    faces = []
    for i in range(major_segs):
        inext = (i + 1) % major_segs
        for j in range(minor_segs):
            jnext = (j + 1) % minor_segs
            faces.append(bm.faces.new((rings[i][j], rings[inext][j], rings[inext][jnext], rings[i][jnext])))
    _tag_faces(faces, region, smooth=True)


def _build_geometry() -> tuple["bpy.types.Mesh", list[int]]:
    """Construct complete caged gas valve BMesh and record warning sign face indices."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()
    hx = CAGE_W * 0.5 - TUBE_W * 0.5
    hy = CAGE_D * 0.5 - TUBE_W * 0.5

    # 1. Yellow cage vertical posts (4 corners + front door divider + back intermediate post)
    post_coords = [
        (-hx, -hy),
        (DOOR_DIV_X, -hy),
        (hx, -hy),
        (-hx, hy),
        (hx, hy),
    ]
    for px, py in post_coords:
        _add_box(bm, Vector((px, py, CAGE_H * 0.5)), Vector((TUBE_W, TUBE_W, CAGE_H)), region=0)
    # Back intermediate post spans cleanly between bottom and top back rails (no coplanar Z-fighting)
    back_post_h = RAIL_TOP_Z - RAIL_BOT_Z - TUBE_W
    _add_box(
        bm,
        Vector((DOOR_DIV_X, hy, (RAIL_BOT_Z + RAIL_TOP_Z) * 0.5)),
        Vector((TUBE_W * 0.92, TUBE_W * 0.92, back_post_h)),
        region=0,
    )

    # 2. Horizontal top & bottom cage rails (inset 0.5mm from post extremes to avoid coplanar caps)
    main_w = hx - DOOR_DIV_X - TUBE_W
    main_cx = (DOOR_DIV_X + hx) * 0.5
    door_w = DOOR_DIV_X - (-hx) - TUBE_W
    door_cx = (-hx + DOOR_DIV_X) * 0.5
    side_l = CAGE_D - 2.0 * TUBE_W
    back_w = CAGE_W - 2.0 * TUBE_W

    for rz in (RAIL_BOT_Z, RAIL_TOP_Z - 0.001):
        # Front main rail
        _add_box(bm, Vector((main_cx, -hy, rz)), Vector((main_w, TUBE_W * 0.96, TUBE_W * 0.96)), region=0)
        # Front door rail (inner leaf)
        _add_box(bm, Vector((door_cx, -hy, rz)), Vector((door_w - 0.02, TUBE_W * 0.85, TUBE_W * 0.85)), region=0)
        # Left & Right side rails
        _add_box(bm, Vector((-hx, 0.0, rz)), Vector((TUBE_W * 0.96, side_l, TUBE_W * 0.96)), region=0)
        _add_box(bm, Vector((hx, 0.0, rz)), Vector((TUBE_W * 0.96, side_l, TUBE_W * 0.96)), region=0)
        # Back rail
        _add_box(bm, Vector((0.0, hy, rz)), Vector((back_w, TUBE_W * 0.96, TUBE_W * 0.96)), region=0)

    # Door inner vertical stiles + 2 hinge barrels + latch plate
    door_inner_h = RAIL_TOP_Z - RAIL_BOT_Z - TUBE_W * 0.85
    door_mid_z = (RAIL_BOT_Z + RAIL_TOP_Z) * 0.5
    door_left_x = -hx + TUBE_W * 0.9
    door_right_x = DOOR_DIV_X - TUBE_W * 0.9
    for sx in (door_left_x, door_right_x):
        _add_box(bm, Vector((sx, -hy, door_mid_z)), Vector((TUBE_W * 0.85, TUBE_W * 0.85, door_inner_h)), region=0)
    for hz in (0.35, 1.25):
        _add_cylinder(bm, Vector((DOOR_DIV_X - TUBE_W * 0.45, -hy - 0.015, hz)), Vector((0.0, 0.0, 1.0)), 0.012, 0.06, 6, region=0, smooth=False)
    _add_box(bm, Vector((-hx + 0.015, -hy - 0.022, 0.86)), Vector((0.04, 0.016, 0.11)), region=0)

    # 3. Diagonal diamond steel mesh infill across all 5 cage bays
    mesh_z0 = RAIL_BOT_Z + TUBE_W * 0.4
    mesh_h = RAIL_TOP_Z - RAIL_BOT_Z - TUBE_W * 0.8
    # Front door bay
    _add_diamond_panel(
        bm,
        Vector((door_left_x + 0.01, -hy, mesh_z0)),
        Vector((1.0, 0.0, 0.0)),
        Vector((0.0, 0.0, 1.0)),
        Vector((0.0, -1.0, 0.0)),
        door_right_x - door_left_x - 0.02,
        mesh_h,
        spacing=0.25,
        region=0,
    )
    # Front main bay
    _add_diamond_panel(
        bm,
        Vector((DOOR_DIV_X + TUBE_W * 0.4, -hy, mesh_z0)),
        Vector((1.0, 0.0, 0.0)),
        Vector((0.0, 0.0, 1.0)),
        Vector((0.0, -1.0, 0.0)),
        main_w + TUBE_W * 0.2,
        mesh_h,
        spacing=0.25,
        region=0,
    )
    # Left & Right side bays
    for sx, nx in ((-hx, -1.0), (hx, 1.0)):
        _add_diamond_panel(
            bm,
            Vector((sx, -hy + TUBE_W * 0.4, mesh_z0)),
            Vector((0.0, 1.0, 0.0)),
            Vector((0.0, 0.0, 1.0)),
            Vector((nx, 0.0, 0.0)),
            side_l + TUBE_W * 0.2,
            mesh_h,
            spacing=0.25,
            region=0,
        )
    # Back bay
    _add_diamond_panel(
        bm,
        Vector((-hx + TUBE_W * 0.4, hy, mesh_z0)),
        Vector((1.0, 0.0, 0.0)),
        Vector((0.0, 0.0, 1.0)),
        Vector((0.0, 1.0, 0.0)),
        back_w + TUBE_W * 0.2,
        mesh_h,
        spacing=0.27,
        region=0,
    )

    # 4. Yellow gas pipe (vertical riser -> 90 elbow -> valve -> 90 back+down drop)
    elbow_r = 0.14
    left_pts = [
        Vector((PIPE_LEFT_X, PIPE_Y, 0.0)),
        Vector((PIPE_LEFT_X, PIPE_Y, PIPE_Z - elbow_r)),
        Vector((PIPE_LEFT_X + elbow_r * (1.0 - math.cos(math.radians(30))), PIPE_Y, PIPE_Z - elbow_r + elbow_r * math.sin(math.radians(30)))),
        Vector((PIPE_LEFT_X + elbow_r * (1.0 - math.cos(math.radians(60))), PIPE_Y, PIPE_Z - elbow_r + elbow_r * math.sin(math.radians(60)))),
        Vector((PIPE_LEFT_X + elbow_r, PIPE_Y, PIPE_Z)),
        Vector((VALVE_CX - 0.17, PIPE_Y, PIPE_Z)),
    ]
    _add_swept_pipe(bm, left_pts, PIPE_R, segments=10, region=0)

    # Right pipe: from valve exit -> right -> bend toward back (+Y) -> bend down to ground
    bend_x = PIPE_RIGHT_X - elbow_r
    right_pts = [
        Vector((VALVE_CX + 0.17, PIPE_Y, PIPE_Z)),
        Vector((bend_x, PIPE_Y, PIPE_Z)),
        Vector((bend_x + elbow_r * math.sin(math.radians(45)), PIPE_Y + (PIPE_RIGHT_BACK_Y - PIPE_Y) * 0.5, PIPE_Z)),
        Vector((PIPE_RIGHT_X, PIPE_RIGHT_BACK_Y, PIPE_Z - 0.04)),
        Vector((PIPE_RIGHT_X, PIPE_RIGHT_BACK_Y, PIPE_Z - elbow_r)),
        Vector((PIPE_RIGHT_X, PIPE_RIGHT_BACK_Y, 0.0)),
    ]
    _add_swept_pipe(bm, right_pts, PIPE_R, segments=10, region=0)

    # Ground pipe base collars
    _add_cylinder(bm, Vector((PIPE_LEFT_X, PIPE_Y, 0.025)), Vector((0.0, 0.0, 1.0)), PIPE_R + 0.025, 0.05, 8, region=2, smooth=False)
    _add_cylinder(bm, Vector((PIPE_RIGHT_X, PIPE_RIGHT_BACK_Y, 0.025)), Vector((0.0, 0.0, 1.0)), PIPE_R + 0.025, 0.05, 8, region=2, smooth=False)

    # Lower red bolted pipe flange on left vertical riser
    _add_cylinder(bm, Vector((PIPE_LEFT_X, PIPE_Y, 0.27)), Vector((0.0, 0.0, 1.0)), 0.132, 0.045, 10, region=1, smooth=True)

    # 5. Red flanged gate valve + handwheel
    v_center = Vector((VALVE_CX, PIPE_Y, PIPE_Z))
    # Left & right bolted flanges
    for fx in (VALVE_CX - 0.155, VALVE_CX + 0.155):
        _add_cylinder(bm, Vector((fx, PIPE_Y, PIPE_Z)), Vector((1.0, 0.0, 0.0)), 0.145, 0.036, 12, region=1, smooth=True)
        for bi in range(6):
            ang = math.radians(bi * 60.0 + 15.0)
            by = PIPE_Y + math.cos(ang) * 0.118
            bz = PIPE_Z + math.sin(ang) * 0.118
            _add_cylinder(bm, Vector((fx, by, bz)), Vector((1.0, 0.0, 0.0)), 0.013, 0.054, 6, region=1, smooth=False)

    # Valve throat + central cast body + bonnet flange + dome
    _add_cylinder(bm, v_center, Vector((1.0, 0.0, 0.0)), 0.105, 0.28, 10, region=1, smooth=True)
    _add_cylinder(bm, Vector((VALVE_CX, PIPE_Y, PIPE_Z + 0.04)), Vector((0.0, 0.0, 1.0)), 0.115, 0.28, 10, region=1, smooth=True)
    _add_cylinder(bm, Vector((VALVE_CX, PIPE_Y, PIPE_Z + 0.19)), Vector((0.0, 0.0, 1.0)), 0.135, 0.032, 10, region=1, smooth=True)
    _add_frustum(bm, Vector((VALVE_CX, PIPE_Y, PIPE_Z + 0.205)), Vector((VALVE_CX, PIPE_Y, PIPE_Z + 0.30)), 0.105, 0.045, 10, region=1, smooth=True)
    _add_cylinder(bm, Vector((VALVE_CX, PIPE_Y, PIPE_Z + 0.39)), Vector((0.0, 0.0, 1.0)), 0.024, 0.20, 8, region=1, smooth=True)

    # Handwheel at z = 1.36m
    wheel_z = PIPE_Z + 0.50
    _add_torus_ring(bm, Vector((VALVE_CX, PIPE_Y, wheel_z)), major_r=0.132, minor_r=0.015, major_segs=12, minor_segs=4, region=1)
    _add_cylinder(bm, Vector((VALVE_CX, PIPE_Y, wheel_z)), Vector((0.0, 0.0, 1.0)), 0.032, 0.032, 8, region=1, smooth=True)
    for si in range(2):
        rot_ang = math.radians(si * 90.0 + 45.0)
        dx = math.cos(rot_ang) * 0.125
        dy = math.sin(rot_ang) * 0.125
        _add_frustum(bm, Vector((VALVE_CX - dx, PIPE_Y - dy, wheel_z)), Vector((VALVE_CX + dx, PIPE_Y + dy, wheel_z)), 0.011, 0.011, 4, region=1, smooth=False)

    # 6. Gray vertical support pedestal under valve
    _add_box(bm, Vector((VALVE_CX, PIPE_Y, 0.010)), Vector((0.18, 0.18, 0.020)), region=2)
    _add_cylinder(bm, Vector((VALVE_CX, PIPE_Y, 0.38)), Vector((0.0, 0.0, 1.0)), 0.042, 0.72, 8, region=2, smooth=True)
    _add_box(bm, Vector((VALVE_CX, PIPE_Y, 0.735)), Vector((0.14, 0.12, 0.030)), region=2)

    # 7. Warning sign plate mounted on upper-right front panel
    sign_cx, sign_cy, sign_cz = 0.50, -hy - 0.014, 1.31
    sign_w, sign_d, sign_h = 0.58, 0.008, 0.36
    _add_box(bm, Vector((sign_cx, sign_cy, sign_cz)), Vector((sign_w, sign_d, sign_h)), region=3)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Identify the exact front-facing face of the warning sign (-Y normal, region 3)
    bm.faces.ensure_lookup_table()
    sign_front_indices = [
        f.index for f in bm.faces if f.material_index == 3 and f.normal.y < -0.9
    ]

    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    # Keep temporary 4 region slots so we can UV-pack each region cleanly into its quadrant
    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh, sign_front_indices


def _unwrap_quadrants_and_merge_material(
    obj: "bpy.types.Object",
    sign_front_indices: list[int],
    final_mat: "bpy.types.Material",
) -> None:
    """Smart-project each material region into its own non-overlapping UV quadrant."""
    import bmesh
    import bpy

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Region bounds in Blender UV space: (u_min, u_max, v_min, v_max)
    # Note: PIL image y=0 is top -> Blender V=1.0 is top!
    quads = {
        0: (0.02, 0.48, 0.52, 0.98),  # Top-Left: yellow paint
        1: (0.52, 0.98, 0.52, 0.98),  # Top-Right: red valve
        2: (0.02, 0.48, 0.02, 0.48),  # Bottom-Left: gray pedestal
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

    # Map warning sign (region 3) cleanly: front face fills Q3 graphic, back/edges use Q3 border yellow
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.verify()
    sign_set = set(sign_front_indices)
    for f in bm.faces:
        if f.material_index != 3:
            continue
        if f.index in sign_set:
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
            # Plain yellow border region in Q3
            for idx, loop in enumerate(f.loops):
                u = 0.51 + (0.01 if idx in (1, 2) else 0.0)
                v = 0.01 + (0.01 if idx in (2, 3) else 0.0)
                loop[uv_layer].uv = (u, v)

    # Collapse all faces onto single unified ORMMaterial3D slot
    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(obj.data)
    bm.free()

    obj.data.materials.clear()
    obj.data.materials.append(final_mat)


def build_prop() -> None:
    """Build caged_gas_valve GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh, sign_front_indices = _build_geometry()
    obj = bpy.data.objects.new("CagedGasValve", mesh)
    bpy.context.collection.objects.link(obj)

    final_mat = _create_atlas_material()
    _unwrap_quadrants_and_merge_material(obj, sign_front_indices, final_mat)

    # Center XY at origin, guarantee min_z = 0, exact target height 1.55m
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
        "reference_image": REF_IMAGE,
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
