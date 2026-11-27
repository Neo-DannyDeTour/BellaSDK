"""Procedural Wall-Mounted Fire Hose Cabinet with Standpipe Valve (0.72m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-24_12-31.png:
- Chipped red enamel steel cabinet body (0.72m H, grounded min_y = 0 at origin)
- Hinged front door with barrel hinges, left cam latch, top yellow hazard plaque,
  and lower white fire-hose pictogram decal
- Recessed rubber-gasketed viewing window with broken corner glass edges exposing
  coiled tan canvas fire hose and tarnished brass nozzle inside
- Right-side red standpipe valve tee, brass union collar, and spoked gate handwheel
- Single manifold mesh with 2048x2048 PBR atlas (Albedo, Normal, ORM) + .tres

Usage:
    .venv/bin/python tools/blender/props/fire_hose_cabinet.py --textures
    python3 tools/blender/run.py tools/blender/props/fire_hose_cabinet.py
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

PROP_SLUG: str = "fire_hose_cabinet"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-24_12-31.png"

MAT_RED_ENAMEL: Path = REPO_ROOT / "assets" / "materials" / "chipped_red_enamel_metal" / "textures"
MAT_RUSTED_STEEL: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
MAT_BRASS: Path = REPO_ROOT / "assets" / "materials" / "tarnished_brass" / "textures"

TEX_SIZE: int = 2048
TARGET_HEIGHT_M: float = 0.72
TRI_BUDGET: int = 1200

# Dimensions in meters (Blender Z-up, front door faces -Y)
CAB_W: float = 0.54
CAB_D: float = 0.22
CAB_H: float = 0.72

DOOR_W: float = 0.505
DOOR_H: float = 0.685
DOOR_T: float = 0.024
DOOR_Y0: float = -CAB_D * 0.5 - DOOR_T  # -0.134
DOOR_Y1: float = -CAB_D * 0.5           # -0.110

# Viewing recess window in upper-middle of door
WIN_W: float = 0.31
WIN_H: float = 0.26
WIN_Z0: float = 0.30
WIN_Z1: float = WIN_Z0 + WIN_H  # 0.56
WIN_X0: float = -WIN_W * 0.5    # -0.155
WIN_X1: float = +WIN_W * 0.5    # +0.155
RECESS_Y1: float = -0.025       # recessed cavity back wall


def _load_resized_rgb(path: Path, w: int, h: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (w, h):
        img = img.resize((w, h), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def _load_resized_l(path: Path, w: int, h: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("L")
    if img.size != (w, h):
        img = img.resize((w, h), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def _generate_pbr_textures() -> None:
    """Build 2048x2048 PBR atlas: front door decals, red enamel, canvas hose, brass/steel."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2  # 1024

    # Load base chipped red enamel textures (1024x1024)
    red_alb = _load_resized_rgb(MAT_RED_ENAMEL / "chipped_red_enamel_metal_albedo.png", half, half)
    red_nrm = _load_resized_rgb(MAT_RED_ENAMEL / "chipped_red_enamel_metal_normal.png", half, half)
    red_ao = _load_resized_l(MAT_RED_ENAMEL / "chipped_red_enamel_metal_ao.png", half, half)
    red_rgh = _load_resized_l(MAT_RED_ENAMEL / "chipped_red_enamel_metal_roughness.png", half, half)
    red_met = _load_resized_l(MAT_RED_ENAMEL / "chipped_red_enamel_metal_metallic.png", half, half)

    # Darken & warm-shift red slightly toward aged industrial crimson (matches ref photo)
    red_alb[..., 0] = np.clip(red_alb[..., 0] * 0.88, 30, 240)
    red_alb[..., 1] = np.clip(red_alb[..., 1] * 0.72, 30, 240)
    red_alb[..., 2] = np.clip(red_alb[..., 2] * 0.72, 30, 240)

    # --- Q0 (Top-Left, U[0..0.5], V[0.5..1.0]): Front Door Planar Decal Panel ---
    # Matches door bounds: X in [-DOOR_W/2, +DOOR_W/2], Z in [0.0175, 0.7025]
    door_alb = red_alb.copy()
    door_nrm = red_nrm.copy()
    door_ao = red_ao.copy()
    door_rgh = red_rgh.copy()
    door_met = red_met.copy()

    # Perimeter door grime & edge chipping
    uu = np.linspace(0.0, 1.0, half, dtype=np.float32)[None, :]
    vv = np.linspace(1.0, 0.0, half, dtype=np.float32)[:, None]  # top=1, bottom=0
    edge_d = np.minimum(np.minimum(uu, 1.0 - uu), np.minimum(vv, 1.0 - vv))
    edge_grime = np.clip(1.0 - edge_d / 0.045, 0.0, 1.0) ** 2.0
    door_alb *= (1.0 - edge_grime[..., None] * 0.35)
    door_ao = np.clip(door_ao - edge_grime * 65.0, 40, 255)
    door_rgh = np.clip(door_rgh + edge_grime * 35.0, 40, 245)

    # Paint crisp decals on an RGBA overlay for top yellow sign + lower white fire-hose placard
    decal_img = Image.new("RGBA", (half, half), (0, 0, 0, 0))
    draw = ImageDraw.Draw(decal_img)

    # Top yellow plaque: X in [-0.09, +0.09] -> u in [0.32, 0.68]; Z in [0.60, 0.665] -> v in [0.85, 0.945]
    # Note PIL y=0 is v=1.0 (top)
    def _uv_to_px(u_val: float, v_val: float) -> tuple[int, int]:
        return int(round(u_val * (half - 1))), int(round((1.0 - v_val) * (half - 1)))

    yx0, yy1 = _uv_to_px(0.32, 0.855)
    yx1, yy0 = _uv_to_px(0.68, 0.942)
    draw.rectangle([yx0, yy0, yx1, yy1], fill=(214, 174, 48, 245), outline=(65, 45, 22, 255), width=4)
    # Hazard border bar inside yellow sign
    draw.rectangle([yx0 + 10, yy0 + 10, yx1 - 10, yy1 - 10], outline=(40, 32, 20, 220), width=3)

    # Lower white Soviet fire-hose pictogram placard (u in [0.29, 0.71], v in [0.075, 0.345])
    px0, py1 = _uv_to_px(0.29, 0.075)
    px1, py0 = _uv_to_px(0.71, 0.345)
    draw.rectangle([px0, py0, px1, py1], fill=(224, 222, 212, 242), outline=(140, 45, 40, 255), width=5)
    # Red fire-hose symbol inside white placard (stylized coil + nozzle + "01" bars)
    cx_p = (px0 + px1) // 2
    cy_p = (py0 + py1) // 2 - 18
    r_outer = int((px1 - px0) * 0.24)
    draw.ellipse([cx_p - r_outer, cy_p - r_outer, cx_p + r_outer, cy_p + r_outer], outline=(168, 34, 30, 255), width=14)
    r_inner = int(r_outer * 0.52)
    draw.ellipse([cx_p - r_inner, cy_p - r_inner, cx_p + r_inner, cy_p + r_inner], outline=(168, 34, 30, 255), width=10)
    # Hose tail + nozzle diagonal bar
    draw.line([(cx_p + r_outer - 8, cy_p + 10), (px1 - 36, py1 - 56)], fill=(168, 34, 30, 255), width=12)
    # Bottom red stencil band on placard ("ПК-01" block bars)
    draw.rectangle([px0 + 26, py1 - 44, px1 - 26, py1 - 18], fill=(168, 34, 30, 255))

    # Scuff/weather the decals using existing enamel chip pattern (where metal shows through)
    decal_arr = np.asarray(decal_img, dtype=np.float32)
    chip_mask = np.clip((red_met - 60.0) / 140.0, 0.0, 1.0)
    alpha = (decal_arr[..., 3] / 255.0) * (1.0 - chip_mask * 0.85)
    door_alb = door_alb * (1.0 - alpha[..., None]) + decal_arr[..., :3] * alpha[..., None]
    door_met = door_met * (1.0 - alpha * 0.9)
    door_rgh = np.clip(door_rgh * (1.0 - alpha * 0.25) + 125.0 * alpha * 0.25, 40, 240)

    # --- Q1 (Top-Right, U[0.5..1.0], V[0.5..1.0]): General Chipped Red Enamel ---
    q1_alb = red_alb.copy()
    q1_nrm = red_nrm.copy()
    q1_ao = red_ao.copy()
    q1_rgh = red_rgh.copy()
    q1_met = red_met.copy()

    # --- Q2 (Bottom-Left, U[0..0.5], V[0..0.5]): Coiled Canvas Fire Hose + Dark Cavity ---
    # Left half of Q2 (512x1024): dirty woven tan/cream fire hose canvas
    # Right half of Q2 (512x1024): dark recessed interior steel cavity
    rng = np.random.default_rng(20261124)
    yy_q2, xx_q2 = np.mgrid[0:half, 0:half].astype(np.float32)
    weave_u = np.sin(xx_q2 * 0.45) * 0.5 + 0.5
    weave_v = np.sin(yy_q2 * 0.52) * 0.5 + 0.5
    rib = 0.5 * (weave_u + weave_v)
    noise_c = rng.normal(0.0, 1.0, (half, half)).astype(np.float32)
    noise_c = np.asarray(
        Image.fromarray(np.clip((noise_c * 0.15 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=6.0)
        ),
        dtype=np.float32,
    ) / 255.0

    canvas_col = np.zeros((half, half, 3), dtype=np.float32)
    canvas_lum = 158.0 + rib * 22.0 + (noise_c - 0.5) * 42.0
    canvas_col[..., 0] = np.clip(canvas_lum * 1.02, 35, 225)
    canvas_col[..., 1] = np.clip(canvas_lum * 0.94, 35, 215)
    canvas_col[..., 2] = np.clip(canvas_lum * 0.78, 30, 195)

    # Normal from canvas weave
    dx_w = np.gradient(rib, axis=1) * 1.6
    dy_w = np.gradient(rib, axis=0) * 1.6
    dz_w = np.ones_like(rib)
    n_len = np.sqrt(dx_w * dx_w + dy_w * dy_w + dz_w * dz_w)
    canvas_nrm = np.stack(
        [
            (dx_w / n_len * 0.5 + 0.5) * 255.0,
            (-dy_w / n_len * 0.5 + 0.5) * 255.0,
            (dz_w / n_len * 0.5 + 0.5) * 255.0,
        ],
        axis=-1,
    )
    canvas_ao = np.clip(190.0 + rib * 45.0, 80, 255)
    canvas_rgh = np.clip(212.0 + (0.5 - rib) * 24.0, 180, 245)
    canvas_met = np.zeros((half, half), dtype=np.float32)

    # Dark cavity (right half of Q2): deep shadowed steel interior
    rust_alb = _load_resized_rgb(MAT_RUSTED_STEEL / "rusted_steel_albedo.png", half, half)
    rust_nrm = _load_resized_rgb(MAT_RUSTED_STEEL / "rusted_steel_normal.png", half, half)
    cav_alb = np.clip(rust_alb * 0.42 + 18.0, 30, 95)
    cav_nrm = rust_nrm
    cav_ao = np.full((half, half), 110.0, dtype=np.float32)
    cav_rgh = np.full((half, half), 210.0, dtype=np.float32)
    cav_met = np.full((half, half), 65.0, dtype=np.float32)

    split_q2 = half // 2
    q2_alb = np.concatenate([canvas_col[:, :split_q2], cav_alb[:, split_q2:]], axis=1)
    q2_nrm = np.concatenate([canvas_nrm[:, :split_q2], cav_nrm[:, split_q2:]], axis=1)
    q2_ao = np.concatenate([canvas_ao[:, :split_q2], cav_ao[:, split_q2:]], axis=1)
    q2_rgh = np.concatenate([canvas_rgh[:, :split_q2], cav_rgh[:, split_q2:]], axis=1)
    q2_met = np.concatenate([canvas_met[:, :split_q2], cav_met[:, split_q2:]], axis=1)

    # --- Q3 (Bottom-Right, U[0.5..1.0], V[0..0.5]): Hardware Steel | Brass | Rubber/Glass ---
    # 3 vertical strips inside Q3 (341, 341, 342 px)
    s1 = half // 3
    s2 = (2 * half) // 3
    brass_alb = _load_resized_rgb(MAT_BRASS / "tarnished_brass_albedo.png", half, half)
    brass_nrm = _load_resized_rgb(MAT_BRASS / "tarnished_brass_normal.png", half, half)
    brass_rgh = _load_resized_l(MAT_BRASS / "tarnished_brass_roughness.png", half, half)

    # Strip 0: galvanized/bare steel hardware (hinges, latch, union collar, handwheel hub)
    steel_alb = np.clip(rust_alb * 0.35 + np.array([105.0, 108.0, 112.0])[None, None, :] * 0.65, 45, 210)
    steel_nrm = (rust_nrm - 128.0) * 0.45 + 128.0
    steel_ao = np.full((half, half), 220.0, dtype=np.float32)
    steel_rgh = np.full((half, half), 108.0, dtype=np.float32)  # ~0.42 roughness
    steel_met = np.full((half, half), 225.0, dtype=np.float32)  # ~0.88 metallic

    # Strip 1: tarnished brass nozzle & coupling
    b_ao = np.full((half, half), 230.0, dtype=np.float32)
    b_rgh = np.clip(brass_rgh, 70, 175)
    b_met = np.full((half, half), 235.0, dtype=np.float32)

    # Strip 2: upper half = dark vulcanized rubber gasket; lower half = dusty specular glass edge
    rub_alb = np.full((half, half, 3), 38.0, dtype=np.float32) + (noise_c[..., None] - 0.5) * 14.0
    rub_nrm = np.full((half, half, 3), 128.0, dtype=np.float32)
    rub_nrm[..., 2] = 255.0
    rub_ao = np.full((half, half), 210.0, dtype=np.float32)
    rub_rgh = np.full((half, half), 200.0, dtype=np.float32)  # ~0.78 matte rubber
    rub_met = np.zeros((half, half), dtype=np.float32)

    # Lower half of strip 2 -> dusty greenish-blue tinted glass corner shards
    rub_alb[half // 2 :, :, 0] = 108.0
    rub_alb[half // 2 :, :, 1] = 132.0
    rub_alb[half // 2 :, :, 2] = 136.0
    rub_rgh[half // 2 :, :] = 32.0  # ~0.12 glossy glass
    rub_met[half // 2 :, :] = 25.0

    q3_alb = np.concatenate([steel_alb[:, :s1], brass_alb[:, s1:s2], rub_alb[:, s2:]], axis=1)
    q3_nrm = np.concatenate([steel_nrm[:, :s1], brass_nrm[:, s1:s2], rub_nrm[:, s2:]], axis=1)
    q3_ao = np.concatenate([steel_ao[:, :s1], b_ao[:, s1:s2], rub_ao[:, s2:]], axis=1)
    q3_rgh = np.concatenate([steel_rgh[:, :s1], b_rgh[:, s1:s2], rub_rgh[:, s2:]], axis=1)
    q3_met = np.concatenate([steel_met[:, :s1], b_met[:, s1:s2], rub_met[:, s2:]], axis=1)

    # Stitch 2x2 quadrants (Top row: Q0 left, Q1 right; Bottom row: Q2 left, Q3 right)
    top_alb = np.concatenate([door_alb, q1_alb], axis=1)
    bot_alb = np.concatenate([q2_alb, q3_alb], axis=1)
    atlas_alb = np.concatenate([top_alb, bot_alb], axis=0)

    top_nrm = np.concatenate([door_nrm, q1_nrm], axis=1)
    bot_nrm = np.concatenate([q2_nrm, q3_nrm], axis=1)
    atlas_nrm = np.concatenate([top_nrm, bot_nrm], axis=0)

    atlas_ao = np.concatenate([np.concatenate([door_ao, q1_ao], axis=1), np.concatenate([q2_ao, q3_ao], axis=1)], axis=0)
    atlas_rgh = np.concatenate([np.concatenate([door_rgh, q1_rgh], axis=1), np.concatenate([q2_rgh, q3_rgh], axis=1)], axis=0)
    atlas_met = np.concatenate([np.concatenate([door_met, q1_met], axis=1), np.concatenate([q2_met, q3_met], axis=1)], axis=0)

    Image.fromarray(np.clip(atlas_alb, 30, 240).astype(np.uint8), mode="RGB").save(ALBEDO_PATH, format="PNG")
    Image.fromarray(np.clip(atlas_nrm, 0, 255).astype(np.uint8), mode="RGB").save(NORMAL_PATH, format="PNG")

    ao_tmp = ASSET_DIR / "_tmp_ao.png"
    rgh_tmp = ASSET_DIR / "_tmp_rgh.png"
    met_tmp = ASSET_DIR / "_tmp_met.png"
    Image.fromarray(np.clip(atlas_ao, 0, 255).astype(np.uint8), mode="L").save(ao_tmp, format="PNG")
    Image.fromarray(np.clip(atlas_rgh, 0, 255).astype(np.uint8), mode="L").save(rgh_tmp, format="PNG")
    Image.fromarray(np.clip(atlas_met, 0, 255).astype(np.uint8), mode="L").save(met_tmp, format="PNG")

    process_pbr.pack_orm(ao_tmp, rgh_tmp, str(met_tmp), ORM_PATH, target_size=(TEX_SIZE, TEX_SIZE))
    ao_tmp.unlink(missing_ok=True)
    rgh_tmp.unlink(missing_ok=True)
    met_tmp.unlink(missing_ok=True)

    process_pbr.generate_godot_tres(
        material_name="M_FireHoseCabinet",
        albedo_path=ALBEDO_PATH,
        normal_path=NORMAL_PATH,
        orm_path=ORM_PATH,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] Generated 2048x2048 {ALBEDO_PATH.name}, {NORMAL_PATH.name}, {ORM_PATH.name}, {TRES_PATH.name}")


def _build_mesh_and_export() -> None:
    """Build single-mesh Fire Hose Cabinet with recessed hose bay & side valve, then export GLB."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            [str(REPO_ROOT / ".venv" / "bin" / "python"), str(Path(__file__).resolve()), "--textures"],
            check=True,
        )

    clean_scene()
    bm = bmesh.new()

    # Region tags:
    # 0 = Front door face (planar Q0)
    # 1 = Red enamel metal (cabinet shell, door edges, side pipe, valve rim)
    # 2 = Canvas fire hose coil
    # 3 = Recessed dark interior cavity
    # 4 = Hardware steel (hinges, latch, union nut, valve stem)
    # 5 = Tarnished brass (nozzle & coupling)
    # 6 = Rubber gasket
    # 7 = Broken corner glass shards

    def add_box(center: Vector, size: Vector, tag: int, rot_mat: Matrix | None = None) -> list[bmesh.types.BMFace]:
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        scale_m = Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        xform = Matrix.Translation(center) @ (rot_mat if rot_mat is not None else Matrix.Identity(4)) @ scale_m
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        vset = set(verts)
        created: list[bmesh.types.BMFace] = []
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = tag
                created.append(f)
        return created

    def add_cyl(
        center: Vector,
        radius: float,
        depth: float,
        segs: int,
        tag: int,
        rot_mat: Matrix | None = None,
    ) -> list[bmesh.types.BMFace]:
        ret = bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=segs,
            radius1=radius,
            radius2=radius,
            depth=depth,
        )
        verts = ret["verts"]
        xform = Matrix.Translation(center) @ (rot_mat if rot_mat is not None else Matrix.Identity(4))
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        vset = set(verts)
        created: list[bmesh.types.BMFace] = []
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = tag
                created.append(f)
        return created

    def add_torus(
        center: Vector,
        major_r: float,
        minor_r: float,
        major_segs: int,
        minor_segs: int,
        tag: int,
        scale_z: float = 1.0,
    ) -> list[bmesh.types.BMFace]:
        """Create a closed torus lying in XZ plane (facing -Y) for coiled hose or handwheel."""
        rings: list[list[bmesh.types.BMVert]] = []
        for i in range(major_segs):
            theta = 2.0 * math.pi * float(i) / float(major_segs)
            ct, st = math.cos(theta), math.sin(theta)
            ring: list[bmesh.types.BMVert] = []
            for j in range(minor_segs):
                phi = 2.0 * math.pi * float(j) / float(minor_segs)
                cp, sp = math.cos(phi), math.sin(phi)
                r = major_r + minor_r * cp
                x = center.x + r * ct
                y = center.y + minor_r * sp
                z = center.z + r * st * scale_z
                ring.append(bm.verts.new((x, y, z)))
            rings.append(ring)
        created: list[bmesh.types.BMFace] = []
        for i in range(major_segs):
            ni = (i + 1) % major_segs
            for j in range(minor_segs):
                nj = (j + 1) % minor_segs
                f = bm.faces.new((rings[i][j], rings[ni][j], rings[ni][nj], rings[i][nj]))
                f.material_index = tag
                created.append(f)
        return created

    # 1. Outer cabinet box with open front recess cavity (non-overlapping walls, zero coplanar z-fighting)
    hx = CAB_W * 0.5
    hy = CAB_D * 0.5
    wall_t = 0.022
    side_d = CAB_D - wall_t
    side_yc = -wall_t * 0.5
    # Back wall (Y: +hy-wall_t .. +hy, full width/height)
    add_box(Vector((0.0, hy - wall_t * 0.5, CAB_H * 0.5)), Vector((CAB_W, wall_t, CAB_H)), tag=1)
    # Left & Right side walls (Y: -hy .. +hy-wall_t, Z: wall_t .. CAB_H-wall_t)
    add_box(Vector((-hx + wall_t * 0.5, side_yc, CAB_H * 0.5)), Vector((wall_t, side_d, CAB_H - 2 * wall_t)), tag=1)
    add_box(Vector((+hx - wall_t * 0.5, side_yc, CAB_H * 0.5)), Vector((wall_t, side_d, CAB_H - 2 * wall_t)), tag=1)
    # Bottom & Top walls (Y: -hy .. +hy-wall_t, full width; top slightly overhanging front/sides)
    add_box(Vector((0.0, side_yc, wall_t * 0.5)), Vector((CAB_W, side_d, wall_t)), tag=1)
    add_box(Vector((0.0, side_yc - 0.008, CAB_H - wall_t * 0.5)), Vector((CAB_W + 0.014, side_d + 0.016, wall_t)), tag=1)

    # Dark interior backing plate & cavity liners behind window
    add_box(Vector((0.0, RECESS_Y1, (WIN_Z0 + WIN_Z1) * 0.5)), Vector((WIN_W + 0.06, 0.012, WIN_H + 0.06)), tag=3)

    # 2. Front Door (built from 4 perimeter strips around viewing window so cavity is truly recessed!)
    door_z0 = (CAB_H - DOOR_H) * 0.5  # 0.0175
    door_z1 = door_z0 + DOOR_H        # 0.7025
    door_yc = (DOOR_Y0 + DOOR_Y1) * 0.5
    dx0 = -DOOR_W * 0.5
    dx1 = +DOOR_W * 0.5

    door_pieces = [
        # Top door panel (above window, holds yellow hazard plate)
        (Vector((0.0, door_yc, 0.5 * (WIN_Z1 + door_z1))), Vector((DOOR_W, DOOR_T, door_z1 - WIN_Z1))),
        # Bottom door panel (below window, holds white Soviet fire-hose pictogram)
        (Vector((0.0, door_yc, 0.5 * (door_z0 + WIN_Z0))), Vector((DOOR_W, DOOR_T, WIN_Z0 - door_z0))),
        # Left door stile
        (Vector((0.5 * (dx0 + WIN_X0), door_yc, 0.5 * (WIN_Z0 + WIN_Z1))), Vector((WIN_X0 - dx0, DOOR_T, WIN_H))),
        # Right door stile
        (Vector((0.5 * (WIN_X1 + dx1), door_yc, 0.5 * (WIN_Z0 + WIN_Z1))), Vector((dx1 - WIN_X1, DOOR_T, WIN_H))),
    ]
    for c_pos, c_size in door_pieces:
        faces = add_box(c_pos, c_size, tag=1)
        # Front-facing polygons (-Y normal) get planar door decal tag=0
        for f in faces:
            f.normal_update()
            if f.normal.y < -0.8:
                f.material_index = 0

    # Rubber window gasket frame around opening
    gask_t = 0.014
    gask_d = 0.016
    gask_y = DOOR_Y0 + 0.004
    add_box(Vector((0.0, gask_y, WIN_Z1 - gask_t * 0.5)), Vector((WIN_W, gask_d, gask_t)), tag=6)
    add_box(Vector((0.0, gask_y, WIN_Z0 + gask_t * 0.5)), Vector((WIN_W, gask_d, gask_t)), tag=6)
    add_box(Vector((WIN_X0 + gask_t * 0.5, gask_y, 0.5 * (WIN_Z0 + WIN_Z1))), Vector((gask_t, gask_d, WIN_H - 2 * gask_t)), tag=6)
    add_box(Vector((WIN_X1 - gask_t * 0.5, gask_y, 0.5 * (WIN_Z0 + WIN_Z1))), Vector((gask_t, gask_d, WIN_H - 2 * gask_t)), tag=6)

    # Two subtle triangular broken-glass shards in top-left & bottom-right corners of window
    shard_y = DOOR_Y0 + 0.010
    for sx, sz, dx, dz in (
        (WIN_X0 + gask_t, WIN_Z1 - gask_t, +0.075, -0.065),
        (WIN_X1 - gask_t, WIN_Z0 + gask_t, -0.065, +0.055),
    ):
        v0 = bm.verts.new((sx, shard_y, sz))
        v1 = bm.verts.new((sx + dx, shard_y, sz))
        v2 = bm.verts.new((sx, shard_y, sz + dz))
        v3 = bm.verts.new((sx, shard_y + 0.004, sz))
        v4 = bm.verts.new((sx + dx, shard_y + 0.004, sz))
        v5 = bm.verts.new((sx, shard_y + 0.004, sz + dz))
        for verts in ((v0, v1, v2), (v5, v4, v3)):
            f = bm.faces.new(verts)
            f.material_index = 7

    # 3. Coiled Canvas Fire Hose + Tarnished Brass Nozzle inside Recessed Cavity
    hose_cx = -0.01
    hose_cz = 0.5 * (WIN_Z0 + WIN_Z1)
    hose_y = 0.5 * (RECESS_Y1 + DOOR_Y1) + 0.005  # ~ -0.062
    add_torus(Vector((hose_cx, hose_y, hose_cz)), major_r=0.088, minor_r=0.020, major_segs=14, minor_segs=6, tag=2, scale_z=0.92)
    add_torus(Vector((hose_cx, hose_y - 0.004, hose_cz)), major_r=0.054, minor_r=0.018, major_segs=12, minor_segs=6, tag=2, scale_z=0.92)
    # Central red reel hub
    rot_x90 = Matrix.Rotation(math.radians(90.0), 4, "X")
    add_cyl(Vector((hose_cx, hose_y, hose_cz)), radius=0.028, depth=0.045, segs=10, tag=1, rot_mat=rot_x90)
    # Brass coupling + tapered nozzle tucked on right side of hose coil
    nozzle_rot = Matrix.Rotation(math.radians(-18.0), 4, "Y") @ Matrix.Rotation(math.radians(90.0), 4, "X")
    add_cyl(Vector((0.095, hose_y - 0.010, hose_cz - 0.04)), radius=0.017, depth=0.085, segs=8, tag=5, rot_mat=nozzle_rot)

    # 4. Door Hardware: 2 right barrel hinges + left cam latch handle
    for hz in (0.14, 0.58):
        add_cyl(Vector((dx1 + 0.006, DOOR_Y0 + 0.010, hz)), radius=0.010, depth=0.055, segs=8, tag=4)
    # Left latch housing + handle
    add_box(Vector((dx0 + 0.026, DOOR_Y0 - 0.006, 0.36)), Vector((0.024, 0.014, 0.065)), tag=4)
    add_box(Vector((dx0 + 0.026, DOOR_Y0 - 0.015, 0.36)), Vector((0.014, 0.010, 0.032)), tag=4)

    # 5. Right-side Red Standpipe Valve Tee + Brass Union + Gate Handwheel (matches ref)
    rot_y90 = Matrix.Rotation(math.radians(90.0), 4, "Y")
    pipe_x = hx + 0.095  # +0.365
    pipe_y = 0.02
    valve_z = 0.50
    # Horizontal pipe into right wall of cabinet
    add_cyl(Vector((hx + 0.048, pipe_y, valve_z)), radius=0.020, depth=0.10, segs=10, tag=1, rot_mat=rot_y90)
    # Brass/steel union nut at cabinet side entry
    add_cyl(Vector((hx + 0.014, pipe_y, valve_z)), radius=0.028, depth=0.022, segs=6, tag=4, rot_mat=rot_y90)
    # Vertical riser stub tee (Z: 0.36..0.56)
    add_cyl(Vector((pipe_x, pipe_y, 0.46)), radius=0.022, depth=0.20, segs=10, tag=1)
    # Valve bonnet + stem
    add_cyl(Vector((pipe_x, pipe_y, 0.58)), radius=0.018, depth=0.06, segs=8, tag=4)
    add_cyl(Vector((pipe_x, pipe_y, 0.625)), radius=0.007, depth=0.04, segs=6, tag=4)
    # Horizontal spoked valve handwheel at Z = 0.645 (stays below CAB_H = 0.72)
    rot_wheel = Matrix.Rotation(math.radians(90.0), 4, "X")
    # Build handwheel torus in XY plane around (pipe_x, pipe_y, 0.645)
    wheel_r = 0.055
    wheel_segs = 12
    w_rings: list[list[bmesh.types.BMVert]] = []
    for i in range(wheel_segs):
        th = 2.0 * math.pi * float(i) / float(wheel_segs)
        ct, st = math.cos(th), math.sin(th)
        ring: list[bmesh.types.BMVert] = []
        for j in range(5):
            ph = 2.0 * math.pi * float(j) / 5.0
            cp, sp = math.cos(ph), math.sin(ph)
            rr = wheel_r + 0.007 * cp
            ring.append(bm.verts.new((pipe_x + rr * ct, pipe_y + rr * st, 0.645 + 0.007 * sp)))
        w_rings.append(ring)
    for i in range(wheel_segs):
        ni = (i + 1) % wheel_segs
        for j in range(5):
            nj = (j + 1) % 5
            f = bm.faces.new((w_rings[i][j], w_rings[ni][j], w_rings[ni][nj], w_rings[i][nj]))
            f.material_index = 1
    # 2 crossed spokes on handwheel
    add_box(Vector((pipe_x, pipe_y, 0.645)), Vector((wheel_r * 1.9, 0.010, 0.008)), tag=1)
    add_box(Vector((pipe_x, pipe_y, 0.645)), Vector((0.010, wheel_r * 1.9, 0.008)), tag=1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.verify()

    region_faces: dict[int, list[bmesh.types.BMFace]] = {k: [] for k in range(8)}
    for f in bm.faces:
        region_faces[f.material_index].append(f)
        f.material_index = 0

    # Map tag=0 (Front Door Planar Q0: U in [0.0, 0.5], V in [0.5, 1.0])
    for f in region_faces[0]:
        for loop in f.loops:
            v = loop.vert.co
            u_norm = (v.x - dx0) / DOOR_W
            v_norm = (v.z - door_z0) / DOOR_H
            loop[uv_layer].uv = (
                max(0.002, min(0.498, u_norm * 0.5)),
                max(0.502, min(0.998, 0.5 + v_norm * 0.5)),
            )

    def _box_unwrap_bmesh(
        faces: list[bmesh.types.BMFace], u0: float, u1: float, v0: float, v1: float
    ) -> None:
        if not faces:
            return
        # Bucket faces by dominant normal axis (+X,-X,+Y,-Y,+Z,-Z) into a 3x2 grid inside [u0,u1]x[v0,v1]
        buckets: list[list[bmesh.types.BMFace]] = [[] for _ in range(6)]
        for f in faces:
            f.normal_update()
            n = f.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            if ax >= ay and ax >= az:
                buckets[0 if n.x >= 0.0 else 1].append(f)
            elif ay >= ax and ay >= az:
                buckets[2 if n.y >= 0.0 else 3].append(f)
            else:
                buckets[4 if n.z >= 0.0 else 5].append(f)

        active_buckets = [(bi, bfaces) for bi, bfaces in enumerate(buckets) if bfaces]
        cols = min(3, max(1, len(active_buckets)))
        rows = (len(active_buckets) + cols - 1) // cols
        cell_w = (u1 - u0) / float(cols)
        cell_h = (v1 - v0) / float(rows)
        pad_u = cell_w * 0.04
        pad_v = cell_h * 0.04

        for slot_i, (bi, bfaces) in enumerate(active_buckets):
            r, c = divmod(slot_i, cols)
            bu0 = u0 + c * cell_w + pad_u
            bu1 = u0 + (c + 1) * cell_w - pad_u
            bv0 = v0 + r * cell_h + pad_v
            bv1 = v0 + (r + 1) * cell_h - pad_v

            raw_uvs: list[tuple[bmesh.types.BMLoop, float, float]] = []
            for f in bfaces:
                for loop in f.loops:
                    co = loop.vert.co
                    if bi in (0, 1):
                        pu, pv = co.y, co.z
                    elif bi in (2, 3):
                        pu, pv = co.x, co.z
                    else:
                        pu, pv = co.x, co.y
                    raw_uvs.append((loop, pu, pv))

            min_u = min(item[1] for item in raw_uvs)
            max_u = max(item[1] for item in raw_uvs)
            min_v = min(item[2] for item in raw_uvs)
            max_v = max(item[2] for item in raw_uvs)
            du = max(max_u - min_u, 1e-5)
            dv = max(max_v - min_v, 1e-5)
            for loop, pu, pv in raw_uvs:
                loop[uv_layer].uv = (
                    bu0 + ((pu - min_u) / du) * (bu1 - bu0),
                    bv0 + ((pv - min_v) / dv) * (bv1 - bv0),
                )

    # Atlas layout (Blender UV V=0 is bottom, V=1 is top):
    _box_unwrap_bmesh(region_faces[1], 0.51, 0.99, 0.51, 0.99)
    _box_unwrap_bmesh(region_faces[2], 0.01, 0.24, 0.01, 0.49)
    _box_unwrap_bmesh(region_faces[3], 0.26, 0.49, 0.01, 0.49)
    _box_unwrap_bmesh(region_faces[4], 0.51, 0.655, 0.01, 0.49)
    _box_unwrap_bmesh(region_faces[5], 0.675, 0.825, 0.01, 0.49)
    _box_unwrap_bmesh(region_faces[6], 0.845, 0.99, 0.26, 0.49)
    _box_unwrap_bmesh(region_faces[7], 0.845, 0.99, 0.01, 0.24)

    mesh = bpy.data.meshes.new("FireHoseCabinet")
    bm.to_mesh(mesh)
    bm.free()

    mat = bpy.data.materials.new(name="M_FireHoseCabinet")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (500, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (180, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.location = (-380, 260)
    img_alb = bpy.data.images.load(str(ALBEDO_PATH.resolve()), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-380, 0)
    img_orm = bpy.data.images.load(str(ORM_PATH.resolve()), check_existing=True)
    img_orm.colorspace_settings.name = "Non-Color"
    tex_orm.image = img_orm

    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-120, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-380, -260)
    img_nrm = bpy.data.images.load(str(NORMAL_PATH.resolve()), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm

    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-120, -260)
    nrm_node.inputs["Strength"].default_value = 0.85
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new("FireHoseCabinet", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Enforce exact min_z = 0.0 and target height = 0.72m baked into vertices
    zs = [v.co.z for v in mesh.vertices]
    z_min, z_max = min(zs), max(zs)
    cur_h = z_max - z_min
    if abs(cur_h - TARGET_HEIGHT_M) > 1e-4 or abs(z_min) > 1e-5:
        scale_h = TARGET_HEIGHT_M / cur_h
        for v in mesh.vertices:
            v.co.z = (v.co.z - z_min) * scale_h
            v.co.x *= scale_h
            v.co.y *= scale_h

    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    # Godot coords: X = x, Y = z, Z = -y
    dims_godot = [
        round(max(xs) - min(xs), 4),
        round(max(zs) - min(zs), 4),
        round(max(ys) - min(ys), 4),
    ]

    export_godot_glb(GLB_PATH, export_animations=False, export_morph=False)

    manifest = {
        "prop_slug": PROP_SLUG,
        "tri_count": tri_count,
        "tri_budget": TRI_BUDGET,
        "uv_layers": len(mesh.uv_layers),
        "dimensions_m": dims_godot,
        "min_y": round(min(zs), 4),
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "reference_image": REF_IMAGE,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_FIRE_HOSE_CABINET:", json.dumps(manifest, indent=2))


def main() -> None:
    if "--textures" in sys.argv:
        _generate_pbr_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
