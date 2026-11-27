"""Procedural Gothic Iron-Bound Oak Lancet Door (2.40m H).

Matches references /home/dkd/Downloads/hl2_refs/Gemini_Generated_Image_dz62c1dz62c1dz62.jpeg
and /home/dkd/Downloads/hl2_refs/2_315_31_master.jpeg:
- Exact lancet arch curve from props/gothic_arch/generate_high_poly.py (get_lancet_arc_point)
- Single slab leaf (2.40m H, grounded min_y = 0 at origin) built from 9 vertical beveled
  dark oak planks trimmed to the pointed Gothic lancet arch profile
- Embossed wrought-iron perimeter band, 2 heavy forged strap hinges with foliate
  C-scroll arms, hinge pintle loops, pyramid rivet studs, and iron ring pull + escutcheon
- 2048x2048 dark oak + hammered wrought iron PBR atlas & ORMMaterial3D .tres

Usage:
    .venv/bin/python tools/blender/props/gothic_iron_door.py --textures
    python3 tools/blender/run.py tools/blender/props/gothic_iron_door.py
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

PROP_SLUG: str = "gothic_iron_door"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2_315_31_master.jpeg"

MAT_WOOD: Path = REPO_ROOT / "assets" / "materials" / "weathered_olive_crate_wood" / "textures"
MAT_WROUGHT: Path = REPO_ROOT / "assets" / "materials" / "gothic_wrought_metal" / "textures"
MAT_RUSTED: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TEX_SIZE: int = 2048
TARGET_HEIGHT_M: float = 2.40
TRI_BUDGET: int = 3000

# Lancet door dimensions matching props/gothic_arch/generate_high_poly.py curve
HALF_W: float = 0.60
SPRING_Z: float = 1.60
APEX_Z: float = 2.40
SLAB_T: float = 0.072
PLANK_COUNT: int = 9


def get_lancet_arc_point(
    half_w: float, spring_z: float, apex_z: float, side: float, t: float
) -> tuple[float, float, float]:
    """Compute (x, z, normal_angle) along a pointed Gothic lancet arc.

    Exact curve formulation from props/gothic_arch/generate_high_poly.py.
    side = -1.0 for left arc, +1.0 for right arc; t in [0.0, 1.0] from spring to apex.
    """
    c_x = half_w * 0.65
    term1 = (half_w + c_x) ** 2 - c_x**2 + spring_z**2 - apex_z**2
    c_z = term1 / (2.0 * (spring_z - apex_z))
    radius = math.sqrt(c_x**2 + (apex_z - c_z) ** 2)

    if side < 0.0:
        center_x = c_x
        ang_start = math.atan2(spring_z - c_z, -half_w - center_x)
        ang_end = math.atan2(apex_z - c_z, 0.0 - center_x)
    else:
        center_x = -c_x
        ang_start = math.atan2(spring_z - c_z, half_w - center_x)
        ang_end = math.atan2(apex_z - c_z, 0.0 - center_x)

    ang = ang_start + t * (ang_end - ang_start)
    px = center_x + radius * math.cos(ang)
    pz = c_z + radius * math.sin(ang)
    return px, pz, ang


def _lancet_z_at_x(x_val: float, half_w: float = HALF_W, spring_z: float = SPRING_Z, apex_z: float = APEX_Z) -> float:
    """Evaluate exact lancet arch height Z for any horizontal coordinate x in [-half_w, +half_w]."""
    ax = min(abs(x_val), half_w)
    c_x = half_w * 0.65
    term1 = (half_w + c_x) ** 2 - c_x**2 + spring_z**2 - apex_z**2
    c_z = term1 / (2.0 * (spring_z - apex_z))
    radius = math.sqrt(c_x**2 + (apex_z - c_z) ** 2)
    dx = ax + c_x
    rad_sq = max(0.0, radius * radius - dx * dx)
    return max(spring_z, c_z + math.sqrt(rad_sq))


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
    """Build 2048x2048 dark aged oak + forged wrought iron PBR atlas."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2

    wd_alb = np.rot90(_load_resized_rgb(MAT_WOOD / "weathered_olive_crate_wood_albedo.png", half, half), k=1)
    wd_nrm = np.rot90(_load_resized_rgb(MAT_WOOD / "weathered_olive_crate_wood_normal.png", half, half), k=1)
    wd_ao = np.rot90(_load_resized_l(MAT_WOOD / "weathered_olive_crate_wood_ao.png", half, half), k=1)
    wd_rgh = np.rot90(_load_resized_l(MAT_WOOD / "weathered_olive_crate_wood_roughness.png", half, half), k=1)

    wr_alb = _load_resized_rgb(MAT_WROUGHT / "gothic_wrought_metal_albedo.png", half, half)
    wr_nrm = _load_resized_rgb(MAT_WROUGHT / "gothic_wrought_metal_normal.png", half, half)
    wr_rgh = _load_resized_l(MAT_WROUGHT / "gothic_wrought_metal_roughness.png", half, half)

    rs_alb = _load_resized_rgb(MAT_RUSTED / "rusted_steel_albedo.png", half, half)
    rs_nrm = _load_resized_rgb(MAT_RUSTED / "rusted_steel_normal.png", half, half)
    rs_ao = _load_resized_l(MAT_RUSTED / "rusted_steel_ao.png", half, half)
    rs_rgh = _load_resized_l(MAT_RUSTED / "rusted_steel_roughness.png", half, half)

    # Left half (U[0..0.5]): Dark Smoked / Aged Walnut-Oak Timber (vertical grain)
    wd_lum = (0.299 * wd_alb[..., 0] + 0.587 * wd_alb[..., 1] + 0.114 * wd_alb[..., 2]) / 255.0
    oak_r = np.clip(44.0 + wd_lum * 108.0, 32, 165)
    oak_g = np.clip(32.0 + wd_lum * 74.0, 28, 120)
    oak_b = np.clip(24.0 + wd_lum * 48.0, 24, 85)
    oak_alb = np.stack([oak_r, oak_g, oak_b], axis=-1)
    # Subtle bottom-edge damp darkening & upper patina
    vv = np.linspace(1.0, 0.0, TEX_SIZE, dtype=np.float32)[:, None]
    damp = np.clip((0.18 - vv) / 0.18, 0.0, 1.0) * 0.25
    oak_alb_full = np.concatenate([oak_alb, oak_alb], axis=0) * (1.0 - damp[..., None])
    oak_nrm_full = np.concatenate([wd_nrm, wd_nrm], axis=0)
    oak_ao_full = np.concatenate([wd_ao, wd_ao], axis=0)
    oak_rgh_full = np.clip(np.concatenate([wd_rgh, wd_rgh], axis=0) * 0.92, 128, 232)
    oak_met_full = np.zeros((TEX_SIZE, half), dtype=np.float32)

    # Right half (U[0.5..1.0]): Forged Hammered Wrought Iron + Subtle Oxide Patina
    iron_alb = np.clip(wr_alb * 0.92 + rs_alb * 0.25 + 22.0, 48, 205)
    iron_nrm = np.clip((wr_nrm - 128.0) * 0.65 + (rs_nrm - 128.0) * 0.35 + 128.0, 0, 255)
    iron_ao = np.clip(rs_ao * 0.85 + 35.0, 80, 255)
    iron_rgh = np.clip(wr_rgh * 0.55 + rs_rgh * 0.35 - 24.0, 58, 180)
    rs_lum = 0.299 * rs_alb[..., 0] + 0.587 * rs_alb[..., 1] + 0.114 * rs_alb[..., 2]
    iron_met = np.clip(230.0 - np.clip((85.0 - rs_lum) * 1.1, 0.0, 85.0), 125, 245)

    iron_alb_full = np.concatenate([iron_alb, iron_alb * 0.88], axis=0)
    iron_nrm_full = np.concatenate([iron_nrm, iron_nrm], axis=0)
    iron_ao_full = np.concatenate([iron_ao, iron_ao], axis=0)
    iron_rgh_full = np.concatenate([iron_rgh, np.clip(iron_rgh - 15.0, 62, 185)], axis=0)
    iron_met_full = np.concatenate([iron_met, iron_met], axis=0)

    atlas_alb = np.concatenate([oak_alb_full, iron_alb_full], axis=1)
    atlas_nrm = np.concatenate([oak_nrm_full, iron_nrm_full], axis=1)
    atlas_ao = np.concatenate([oak_ao_full, iron_ao_full], axis=1)
    atlas_rgh = np.concatenate([oak_rgh_full, iron_rgh_full], axis=1)
    atlas_met = np.concatenate([oak_met_full, iron_met_full], axis=1)

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
        material_name="M_GothicIronDoor",
        albedo_path=ALBEDO_PATH,
        normal_path=NORMAL_PATH,
        orm_path=ORM_PATH,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] Generated 2048x2048 {ALBEDO_PATH.name}, {NORMAL_PATH.name}, {ORM_PATH.name}, {TRES_PATH.name}")


def _unwrap_bmesh_regions(
    bm: "bmesh.types.BMesh",
    uv_boxes: dict[int, tuple[float, float, float, float]],
) -> None:
    """Assign deterministic 6-direction box UVs directly in bmesh without bpy.ops."""
    uv_layer = bm.loops.layers.uv.verify()
    region_faces: dict[int, list] = {tag: [] for tag in uv_boxes}
    for f in bm.faces:
        region_faces[f.material_index].append(f)
        f.material_index = 0

    for tag, faces in region_faces.items():
        if not faces:
            continue
        u0, u1, v0, v1 = uv_boxes[tag]
        buckets: list[list] = [[] for _ in range(6)]
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

            raw_uvs = []
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


def _build_mesh_and_export() -> None:
    """Build single-slab Gothic Iron-Bound Oak Door with lancet arch and export GLB."""
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
    # Tags: 0 = dark oak planks (U[0..0.5]), 1 = forged wrought iron hardware (U[0.5..1.0])

    def add_box(center: Vector, size: Vector, tag: int, rot_mat: Matrix | None = None) -> None:
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        xform = Matrix.Translation(center) @ (rot_mat if rot_mat is not None else Matrix.Identity(4)) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        vset = set(verts)
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = tag

    def add_stud(pos: Vector, radius: float, height: float, y_dir: float, tag: int) -> None:
        """Add forged 4-sided pyramid iron rivet stud."""
        v_tip = bm.verts.new((pos.x, pos.y + y_dir * height, pos.z))
        ring = [
            bm.verts.new((pos.x - radius, pos.y, pos.z - radius)),
            bm.verts.new((pos.x + radius, pos.y, pos.z - radius)),
            bm.verts.new((pos.x + radius, pos.y, pos.z + radius)),
            bm.verts.new((pos.x - radius, pos.y, pos.z + radius)),
        ]
        if y_dir > 0.0:
            ring.reverse()
        for i in range(4):
            ni = (i + 1) % 4
            f = bm.faces.new((ring[i], ring[ni], v_tip))
            f.material_index = tag
        f_base = bm.faces.new(list(reversed(ring)))
        f_base.material_index = tag

    def add_scroll_arm(pts: list[tuple[float, float]], half_h: float, y_front: float, y_back: float, tag: int) -> None:
        """Sweep a rectangular iron strap scroll along 2D (x, z) polyline."""
        n_pts = len(pts)
        rings: list[list[bmesh.types.BMVert]] = []
        for idx, (px, pz) in enumerate(pts):
            if idx == 0:
                dx, dz = pts[1][0] - px, pts[1][1] - pz
            elif idx == n_pts - 1:
                dx, dz = px - pts[idx - 1][0], pz - pts[idx - 1][1]
            else:
                dx, dz = pts[idx + 1][0] - pts[idx - 1][0], pz - pts[idx - 1][1] - 0.0
            ln = max(math.hypot(dx, dz), 1e-5)
            nx, nz = -dz / ln, dx / ln
            t_tap = half_h * (1.0 - 0.35 * (float(idx) / float(max(1, n_pts - 1))))
            rings.append([
                bm.verts.new((px - nx * t_tap, y_front, pz - nz * t_tap)),
                bm.verts.new((px + nx * t_tap, y_front, pz + nz * t_tap)),
                bm.verts.new((px + nx * t_tap, y_back, pz + nz * t_tap)),
                bm.verts.new((px - nx * t_tap, y_back, pz - nz * t_tap)),
            ])
        for idx in range(n_pts - 1):
            for k in range(4):
                nk = (k + 1) % 4
                f = bm.faces.new((rings[idx][k], rings[idx + 1][k], rings[idx + 1][nk], rings[idx][nk]))
                f.material_index = tag
        bm.faces.new(list(reversed(rings[0]))).material_index = tag
        bm.faces.new(rings[-1]).material_index = tag

    # 1. Core solid lancet oak backing core (prevents light leaks through plank V-grooves)
    arc_segs = 10
    core_pts: list[tuple[float, float]] = [(HALF_W - 0.008, 0.0), (-HALF_W + 0.008, 0.0), (-HALF_W + 0.008, SPRING_Z)]
    for i in range(1, arc_segs):
        px, pz, _ = get_lancet_arc_point(HALF_W - 0.008, SPRING_Z, APEX_Z - 0.008, -1.0, float(i) / float(arc_segs))
        core_pts.append((px, pz))
    core_pts.append((0.0, APEX_Z - 0.008))
    for i in range(arc_segs - 1, 0, -1):
        px, pz, _ = get_lancet_arc_point(HALF_W - 0.008, SPRING_Z, APEX_Z - 0.008, 1.0, float(i) / float(arc_segs))
        core_pts.append((px, pz))
    core_pts.append((HALF_W - 0.008, SPRING_Z))

    cy_c = SLAB_T * 0.34
    vf_core = [bm.verts.new((x, -cy_c, z)) for x, z in core_pts]
    vb_core = [bm.verts.new((x, +cy_c, z)) for x, z in core_pts]
    bm.faces.new(vf_core).material_index = 0
    bm.faces.new(list(reversed(vb_core))).material_index = 0
    for i in range(len(core_pts)):
        ni = (i + 1) % len(core_pts)
        bm.faces.new((vf_core[i], vb_core[i], vb_core[ni], vf_core[ni])).material_index = 0

    # 2. 9 Chamfered Vertical Oak Planks on Front & Back trimmed to exact Lancet Curve
    plank_w = (2.0 * HALF_W) / float(PLANK_COUNT)
    chamfer = 0.0055
    hy_plank = SLAB_T * 0.5
    for p_idx in range(PLANK_COUNT):
        x0 = -HALF_W + float(p_idx) * plank_w + 0.002
        x1 = -HALF_W + float(p_idx + 1) * plank_w - 0.002
        xm = 0.5 * (x0 + x1)
        # Sample top profile along [x0, xm, x1] (middle plank hits apex 0.0!)
        xs_top = [x0, 0.0, x1] if (x0 < 0.0 < x1) else [x0, xm, x1]
        top_zs = [_lancet_z_at_x(xv) for xv in xs_top]

        # Build front & back chamfered plank prisms (8-point profile in X-Z? Better: 2-step bevel face per plank)
        for y_s in (-1.0, 1.0):
            y_in = y_s * (hy_plank - 0.010)
            y_out = y_s * hy_plank
            base_pts = [(x0, 0.0), (x1, 0.0)]
            top_pts = list(reversed(list(zip(xs_top, top_zs))))
            outer_pts = [(x0 + chamfer, chamfer), (x1 - chamfer, chamfer)] + [
                (xv + (-chamfer if xv > xm else chamfer if xv < xm else 0.0), zv - chamfer)
                for xv, zv in top_pts
            ]
            inner_pts = base_pts + top_pts
            v_in = [bm.verts.new((px, y_in, pz)) for px, pz in inner_pts]
            v_out = [bm.verts.new((px, y_out, pz)) for px, pz in outer_pts]
            if y_s < 0.0:
                bm.faces.new(v_out).material_index = 0
                for k in range(len(v_in)):
                    nk = (k + 1) % len(v_in)
                    bm.faces.new((v_in[k], v_in[nk], v_out[nk], v_out[k])).material_index = 0
            else:
                bm.faces.new(list(reversed(v_out))).material_index = 0
                for k in range(len(v_in)):
                    nk = (k + 1) % len(v_in)
                    bm.faces.new((v_out[k], v_out[nk], v_in[nk], v_in[k])).material_index = 0

    # 3. Embossed Wrought-Iron Perimeter Binding Rim following Lancet Arch
    band_w = 0.026
    rim_pts_out = [(HALF_W, 0.0), (-HALF_W, 0.0), (-HALF_W, SPRING_Z)]
    rim_pts_in = [(HALF_W - band_w, 0.0), (-HALF_W + band_w, 0.0), (-HALF_W + band_w, SPRING_Z)]
    for i in range(1, arc_segs):
        t = float(i) / float(arc_segs)
        px, pz, _ = get_lancet_arc_point(HALF_W, SPRING_Z, APEX_Z, -1.0, t)
        rim_pts_out.append((px, pz))
        pxi, pzi, _ = get_lancet_arc_point(HALF_W - band_w, SPRING_Z, APEX_Z - band_w, -1.0, t)
        rim_pts_in.append((pxi, pzi))
    rim_pts_out.append((0.0, APEX_Z))
    rim_pts_in.append((0.0, APEX_Z - band_w))
    for i in range(arc_segs - 1, 0, -1):
        t = float(i) / float(arc_segs)
        px, pz, _ = get_lancet_arc_point(HALF_W, SPRING_Z, APEX_Z, 1.0, t)
        rim_pts_out.append((px, pz))
        pxi, pzi, _ = get_lancet_arc_point(HALF_W - band_w, SPRING_Z, APEX_Z - band_w, 1.0, t)
        rim_pts_in.append((pxi, pzi))
    rim_pts_out.append((HALF_W, SPRING_Z))
    rim_pts_in.append((HALF_W - band_w, SPRING_Z))

    ry = hy_plank + 0.005
    v_ro_f = [bm.verts.new((x, -ry, z)) for x, z in rim_pts_out]
    v_ro_b = [bm.verts.new((x, +ry, z)) for x, z in rim_pts_out]
    v_ri_f = [bm.verts.new((x, -ry, z)) for x, z in rim_pts_in]
    v_ri_b = [bm.verts.new((x, +ry, z)) for x, z in rim_pts_in]
    for i in range(len(rim_pts_out)):
        ni = (i + 1) % len(rim_pts_out)
        if i == 0:
            # Bottom iron kick-rail bar stays thin (skip bottom segment if needed, or keep clean)
            pass
        for verts in (
            (v_ro_f[i], v_ro_b[i], v_ro_b[ni], v_ro_f[ni]),
            (v_ri_f[i], v_ro_f[i], v_ro_f[ni], v_ri_f[ni]),
            (v_ro_b[i], v_ri_b[i], v_ri_b[ni], v_ro_b[ni]),
            (v_ri_b[i], v_ri_f[i], v_ri_f[ni], v_ri_b[ni]),
        ):
            bm.faces.new(verts).material_index = 1

    # 4. 2 Heavy Forged Wrought-Iron Strap Hinges + Foliate C-Scrolls + Pintle Barrels + Studs
    for hz in (0.42, 1.46):
        # Main horizontal strap bar (front & back) spanning from right hinge edge (+0.60) to -0.44
        strap_cx = 0.08
        strap_w = 1.04
        add_box(Vector((strap_cx, -hy_plank - 0.007, hz)), Vector((strap_w, 0.014, 0.056)), tag=1)
        add_box(Vector((strap_cx, +hy_plank + 0.007, hz)), Vector((strap_w, 0.014, 0.056)), tag=1)
        # Right-edge hinge pintle barrel wrapping around +HALF_W
        ret_p = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.022, radius2=0.022, depth=0.085)
        vp = ret_p["verts"]
        bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((HALF_W + 0.016, 0.0, hz))), verts=vp)
        vpset = set(vp)
        for f in bm.faces:
            if all(v in vpset for v in f.verts):
                f.material_index = 1

        # 4 Foliate C-scroll tendrils per strap hinge (2 upper, 2 lower curving outward toward latch)
        for sx in (0.30, -0.06):
            for z_dir in (-1.0, 1.0):
                pts_scroll = [
                    (sx, hz + z_dir * 0.018),
                    (sx - 0.045, hz + z_dir * 0.085),
                    (sx - 0.115, hz + z_dir * 0.145),
                    (sx - 0.185, hz + z_dir * 0.155),
                    (sx - 0.215, hz + z_dir * 0.115),
                    (sx - 0.175, hz + z_dir * 0.085),
                ]
                if z_dir < 0.0:
                    pts_scroll.reverse()
                add_scroll_arm(pts_scroll, half_h=0.012, y_front=-hy_plank - 0.013, y_back=-hy_plank + 0.002, tag=1)

        # Forged pyramid iron studs along strap hinge
        for st_x in (-0.38, -0.22, -0.04, 0.14, 0.32, 0.48):
            add_stud(Vector((st_x, -hy_plank - 0.014, hz)), radius=0.012, height=0.012, y_dir=-1.0, tag=1)

    # 5. Wrought-Iron Ring Pull + Escutcheon Backplate + Keyhole Plate (left latch edge)
    ring_x = -0.44
    ring_z = 1.02
    add_box(Vector((ring_x, -hy_plank - 0.007, ring_z)), Vector((0.078, 0.014, 0.155)), tag=1)
    add_box(Vector((ring_x, +hy_plank + 0.007, ring_z)), Vector((0.078, 0.014, 0.155)), tag=1)
    # Keyhole escutcheon below ring pull
    add_box(Vector((ring_x, -hy_plank - 0.006, 0.83)), Vector((0.044, 0.012, 0.090)), tag=1)

    # Ring pull boss + 12-sided forged iron ring hanging at Z = 0.96
    add_box(Vector((ring_x, -hy_plank - 0.020, ring_z + 0.026)), Vector((0.026, 0.026, 0.026)), tag=1)
    ring_r = 0.052
    ring_segs = 12
    tube_segs = 5
    r_rings: list[list[bmesh.types.BMVert]] = []
    ring_cz = ring_z - 0.018
    ring_y = -hy_plank - 0.026
    for i in range(ring_segs):
        th = 2.0 * math.pi * float(i) / float(ring_segs)
        ct, st = math.cos(th), math.sin(th)
        r_loop: list[bmesh.types.BMVert] = []
        for j in range(tube_segs):
            ph = 2.0 * math.pi * float(j) / float(tube_segs)
            cp, sp = math.cos(ph), math.sin(ph)
            rr = ring_r + 0.008 * cp
            r_loop.append(bm.verts.new((ring_x + rr * ct, ring_y + 0.008 * sp, ring_cz + rr * st)))
        r_rings.append(r_loop)
    for i in range(ring_segs):
        ni = (i + 1) % ring_segs
        for j in range(tube_segs):
            nj = (j + 1) % tube_segs
            bm.faces.new((r_rings[i][j], r_rings[ni][j], r_rings[ni][nj], r_rings[i][nj])).material_index = 1

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    _unwrap_bmesh_regions(
        bm,
        {
            0: (0.01, 0.49, 0.01, 0.99),  # Left half: dark oak planks
            1: (0.51, 0.99, 0.01, 0.99),  # Right half: forged wrought iron
        },
    )

    mesh = bpy.data.meshes.new("GothicIronDoor")
    bm.to_mesh(mesh)
    bm.free()

    mat = bpy.data.materials.new(name="M_GothicIronDoor")
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

    obj = bpy.data.objects.new("GothicIronDoor", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Enforce exact min_z = 0.0 and target height = 2.40m baked into vertices
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
    print("BUILT_GOTHIC_IRON_DOOR:", json.dumps(manifest, indent=2))


def main() -> None:
    if "--textures" in sys.argv:
        _generate_pbr_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
