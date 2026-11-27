"""Procedural Industrial Exhaust Fan with Separate FanHousing & FanRotor (0.90m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-55.png:
- FanHousing: 0.90m x 0.90m square galvanized/painted steel frame with circular
  venturi shroud barrel, 4 corner bolts, upper-left nameplate, rear motor housing,
  and 3 radial support struts (grounded min_y = 0 at origin)
- FanRotor: separate 5-blade pitched sheet-metal impeller with center hub & shaft nut,
  object origin centered exactly on the spin axis (0, 0.45, 0) in Godot
- Shared 2048x2048 weathered industrial metal + rust PBR atlas & ORMMaterial3D .tres

Usage:
    .venv/bin/python tools/blender/props/industrial_exhaust_fan.py --textures
    python3 tools/blender/run.py tools/blender/props/industrial_exhaust_fan.py
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

PROP_SLUG: str = "industrial_exhaust_fan"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-55.png"

MAT_PAINTED_METAL: Path = REPO_ROOT / "assets" / "materials" / "painted_industrial_metal" / "textures"
MAT_RUSTED_STEEL: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
MAT_WROUGHT: Path = REPO_ROOT / "assets" / "materials" / "gothic_wrought_metal" / "textures"

TEX_SIZE: int = 2048
TARGET_HEIGHT_M: float = 0.90
TRI_BUDGET: int = 1800

# Dimensions in meters (Blender Z-up, front shroud faces -Y)
FRAME_SIZE: float = 0.90
SPIN_Z: float = FRAME_SIZE * 0.5  # 0.45m
BORE_R: float = 0.365
DUCT_DEPTH: float = 0.22
ROTOR_Y: float = 0.045            # inside shroud barrel (-0.02..+0.20)
BLADE_COUNT: int = 5


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
    """Build 2048x2048 weathered industrial metal + corroded blade PBR atlas."""
    import numpy as np
    from PIL import Image, ImageDraw

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2  # 1024

    pm_alb = _load_resized_rgb(MAT_PAINTED_METAL / "painted_industrial_metal_albedo.png", half, half)
    pm_nrm = _load_resized_rgb(MAT_PAINTED_METAL / "painted_industrial_metal_normal.png", half, half)
    pm_ao = _load_resized_l(MAT_PAINTED_METAL / "painted_industrial_metal_ao.png", half, half)
    pm_rgh = _load_resized_l(MAT_PAINTED_METAL / "painted_industrial_metal_roughness.png", half, half)

    rs_alb = _load_resized_rgb(MAT_RUSTED_STEEL / "rusted_steel_albedo.png", half, half)
    rs_nrm = _load_resized_rgb(MAT_RUSTED_STEEL / "rusted_steel_normal.png", half, half)
    rs_ao = _load_resized_l(MAT_RUSTED_STEEL / "rusted_steel_ao.png", half, half)
    rs_rgh = _load_resized_l(MAT_RUSTED_STEEL / "rusted_steel_roughness.png", half, half)

    wr_alb = _load_resized_rgb(MAT_WROUGHT / "gothic_wrought_metal_albedo.png", half, half)
    wr_nrm = _load_resized_rgb(MAT_WROUGHT / "gothic_wrought_metal_normal.png", half, half)
    wr_rgh = _load_resized_l(MAT_WROUGHT / "gothic_wrought_metal_roughness.png", half, half)

    # --- Left Top (Q0): Weathered Galvanized / Gray Painted Steel Frame + Corner Rust ---
    # Desaturate teal painted_industrial_metal toward gritty HL2 weathered olive-gray steel
    pm_lum = 0.299 * pm_alb[..., 0] + 0.587 * pm_alb[..., 1] + 0.114 * pm_alb[..., 2]
    gray_steel = np.stack([pm_lum * 1.08, pm_lum * 1.07, pm_lum * 1.02], axis=-1)
    # Keep subtle rust specks from original scan without deep pitted holes
    rust_chip_mask = np.clip((72.0 - pm_lum) / 36.0, 0.0, 1.0)
    q0_alb = gray_steel * (1.0 - rust_chip_mask[..., None] * 0.55) + rs_alb * (rust_chip_mask[..., None] * 0.55)
    q0_alb = np.clip(q0_alb * 1.12, 40, 228)
    q0_nrm = np.clip((pm_nrm - 128.0) * 0.42 + 128.0, 0, 255)
    q0_ao = np.clip(pm_ao * 0.7 + 75.0, 90, 255)
    q0_rgh = np.clip(pm_rgh * 0.85, 75, 220)
    q0_met = np.clip(115.0 + (pm_lum - 100.0) * 0.7 - rust_chip_mask * 80.0, 35, 215)

    # --- Left Bottom (Q2): Spec Nameplate (upper) & Duct Shroud Grime (lower) ---
    plate_img = Image.new("RGB", (half, half // 2), (168, 166, 158))
    draw = ImageDraw.Draw(plate_img)
    draw.rectangle([16, 16, half - 16, half // 2 - 16], outline=(52, 50, 46), width=8)
    for row_y in (72, 132, 192, 252):
        draw.rectangle([52, row_y, half - 90, row_y + 22], fill=(64, 62, 58))
    plate_arr = np.asarray(plate_img, dtype=np.float32) * 0.82 + gray_steel[: half // 2] * 0.18

    q2_alb = np.concatenate([plate_arr, q0_alb[half // 2 :] * 0.82], axis=0)
    q2_nrm = q0_nrm.copy()
    q2_ao = np.clip(q0_ao * 0.92, 50, 255)
    q2_rgh = np.clip(q0_rgh + 12.0, 75, 230)
    q2_met = np.clip(q0_met, 35, 215)

    # --- Right Top (Q1): Rusted Impeller Blades (weathered bare steel + pitted orange-brown rust) ---
    rs_lum = 0.299 * rs_alb[..., 0] + 0.587 * rs_alb[..., 1] + 0.114 * rs_alb[..., 2]
    # Blend pitted rust with worn brushed steel patches matching ref fan blades
    bare_patch = np.clip((rs_lum - 54.0) / 34.0, 0.0, 1.0)
    bare_col = np.stack([rs_lum * 1.78, rs_lum * 1.80, rs_lum * 1.85], axis=-1)
    q1_alb = rs_alb * (1.0 - bare_patch[..., None] * 0.72) + bare_col * (bare_patch[..., None] * 0.72)
    q1_alb = np.clip(q1_alb * 1.15, 42, 232)
    q1_nrm = np.clip((rs_nrm - 128.0) * 0.65 + 128.0, 0, 255)
    q1_ao = np.clip(rs_ao * 0.75 + 60.0, 80, 255)
    q1_rgh = np.clip(rs_rgh * 0.78 - bare_patch * 38.0, 52, 215)
    q1_met = np.clip(90.0 + bare_patch * 145.0, 55, 235)

    # --- Right Bottom (Q3): Dark Oxidized Motor Casing & Struts ---
    q3_alb = np.clip(wr_alb * 0.85 + rs_alb * 0.15, 30, 180)
    q3_nrm = wr_nrm
    q3_ao = np.clip(rs_ao * 0.95, 60, 255)
    q3_rgh = np.clip(wr_rgh * 0.90, 75, 215)
    q3_met = np.full((half, half), 205.0, dtype=np.float32)

    atlas_alb = np.concatenate([np.concatenate([q0_alb, q1_alb], axis=1), np.concatenate([q2_alb, q3_alb], axis=1)], axis=0)
    atlas_nrm = np.concatenate([np.concatenate([q0_nrm, q1_nrm], axis=1), np.concatenate([q2_nrm, q3_nrm], axis=1)], axis=0)
    atlas_ao = np.concatenate([np.concatenate([q0_ao, q1_ao], axis=1), np.concatenate([q2_ao, q3_ao], axis=1)], axis=0)
    atlas_rgh = np.concatenate([np.concatenate([q0_rgh, q1_rgh], axis=1), np.concatenate([q2_rgh, q3_rgh], axis=1)], axis=0)
    atlas_met = np.concatenate([np.concatenate([q0_met, q1_met], axis=1), np.concatenate([q2_met, q3_met], axis=1)], axis=0)

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
        material_name="M_IndustrialExhaustFan",
        albedo_path=ALBEDO_PATH,
        normal_path=NORMAL_PATH,
        orm_path=ORM_PATH,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] Generated 2048x2048 {ALBEDO_PATH.name}, {NORMAL_PATH.name}, {ORM_PATH.name}, {TRES_PATH.name}")


def _build_shared_material() -> "bpy.types.Material":
    import bpy

    mat = bpy.data.materials.new(name="M_IndustrialExhaustFan")
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

    return mat


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


def _build_housing(mat: "bpy.types.Material") -> tuple["bpy.types.Object", int]:
    """Build FanHousing (square frame, circular shroud barrel, bolts, nameplate, motor + struts)."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    bm = bmesh.new()
    # Tags: 0=frame/flange/bolts, 1=nameplate, 2=duct barrel, 3=rear motor & struts
    half_w = FRAME_SIZE * 0.5
    front_y0 = -0.025
    front_y1 = 0.015
    segs = 16

    # 1. Solid airtight square outer plate transitioning cleanly to 16-gon circular bore (radius BORE_R)
    # Include exact 45/135/225/315 deg corner points in the outer perimeter so corners are sharp 90-deg squares!
    half_w = FRAME_SIZE * 0.5
    front_y0 = -0.025
    front_y1 = 0.015
    segs = 16

    # Build 4 quadrant arcs (4 bore segments per quadrant, sharing the corner vertex on the square)
    inner_f: list[bmesh.types.BMVert] = []
    inner_b: list[bmesh.types.BMVert] = []
    for i in range(segs):
        ang = 2.0 * math.pi * float(i) / float(segs)  # starts at 0 deg (+X), hits 45, 90, 135, ...
        ca, sa = math.cos(ang), math.sin(ang)
        ix = ca * BORE_R
        iz = SPIN_Z + sa * BORE_R
        inner_f.append(bm.verts.new((ix, front_y0, iz)))
        inner_b.append(bm.verts.new((ix, front_y1, iz)))

    outer_f: list[bmesh.types.BMVert] = []
    outer_b: list[bmesh.types.BMVert] = []
    for i in range(segs):
        ang = 2.0 * math.pi * float(i) / float(segs)
        ca, sa = math.cos(ang), math.sin(ang)
        scale_sq = half_w / max(abs(ca), abs(sa))
        ox = ca * scale_sq
        oz = SPIN_Z + sa * scale_sq
        outer_f.append(bm.verts.new((ox, front_y0, oz)))
        outer_b.append(bm.verts.new((ox, front_y1, oz)))

    for i in range(segs):
        ni = (i + 1) % segs
        for verts, tag in (
            ((outer_f[i], outer_f[ni], inner_f[ni], inner_f[i]), 0),
            ((inner_b[i], inner_b[ni], outer_b[ni], outer_b[i]), 0),
            ((outer_b[i], outer_b[ni], outer_f[ni], outer_f[i]), 0),
            ((inner_f[i], inner_f[ni], inner_b[ni], inner_b[i]), 2),
        ):
            f = bm.faces.new(verts)
            f.material_index = tag

    # Outer perimeter folded return flange (non-overlapping 4 perimeter bars behind front_y1)
    flange_t = 0.022
    flange_d = 0.068
    flange_yc = front_y1 + flange_d * 0.5
    for pos, size in (
        (Vector((0.0, flange_yc, FRAME_SIZE - flange_t * 0.5)), Vector((FRAME_SIZE, flange_d, flange_t))),
        (Vector((0.0, flange_yc, flange_t * 0.5)), Vector((FRAME_SIZE, flange_d, flange_t))),
        (Vector((-half_w + flange_t * 0.5, flange_yc, SPIN_Z)), Vector((flange_t, flange_d, FRAME_SIZE - 2 * flange_t))),
        (Vector((+half_w - flange_t * 0.5, flange_yc, SPIN_Z)), Vector((flange_t, flange_d, FRAME_SIZE - 2 * flange_t))),
    ):
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        bmesh.ops.transform(
            bm,
            matrix=Matrix.Translation(pos) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0)),
            verts=verts,
        )
        vset = set(verts)
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = 0

    # 2. Cylindrical/16-sided Venturi Duct Barrel extending rearward (Y = front_y1..DUCT_DEPTH)
    r_outer = BORE_R + 0.022
    barrel_f_in: list[bmesh.types.BMVert] = []
    barrel_b_in: list[bmesh.types.BMVert] = []
    barrel_f_out: list[bmesh.types.BMVert] = []
    barrel_b_out: list[bmesh.types.BMVert] = []
    y_b0 = front_y1
    y_b1 = DUCT_DEPTH
    for i in range(segs):
        ang = 2.0 * math.pi * float(i) / float(segs)
        ca, sa = math.cos(ang), math.sin(ang)
        barrel_f_in.append(bm.verts.new((ca * BORE_R, y_b0, SPIN_Z + sa * BORE_R)))
        barrel_b_in.append(bm.verts.new((ca * BORE_R, y_b1, SPIN_Z + sa * BORE_R)))
        barrel_f_out.append(bm.verts.new((ca * r_outer, y_b0, SPIN_Z + sa * r_outer)))
        barrel_b_out.append(bm.verts.new((ca * r_outer, y_b1, SPIN_Z + sa * r_outer)))

    for i in range(segs):
        ni = (i + 1) % segs
        for verts in (
            (barrel_f_in[i], barrel_f_in[ni], barrel_b_in[ni], barrel_b_in[i]),
            (barrel_b_out[i], barrel_b_out[ni], barrel_f_out[ni], barrel_f_out[i]),
            (barrel_b_in[i], barrel_b_in[ni], barrel_b_out[ni], barrel_b_out[i]),
        ):
            f = bm.faces.new(verts)
            f.material_index = 2

    # 3. 4 Corner mounting bolts + Upper-left spec nameplate
    rot_x90 = Matrix.Rotation(math.radians(90.0), 4, "X")
    bolt_off = half_w - 0.055
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=0.015, radius2=0.015, depth=0.018)
            verts = ret["verts"]
            bmesh.ops.transform(
                bm,
                matrix=Matrix.Translation(Vector((sx * bolt_off, front_y0 - 0.006, SPIN_Z + sz * bolt_off))) @ rot_x90,
                verts=verts,
            )
            vset = set(verts)
            for f in bm.faces:
                if all(v in vset for v in f.verts):
                    f.material_index = 3

    ret_np = bmesh.ops.create_cube(bm, size=1.0)
    verts_np = ret_np["verts"]
    bmesh.ops.transform(
        bm,
        matrix=Matrix.Translation(Vector((-0.295, front_y0 - 0.004, FRAME_SIZE - 0.075))) @ Matrix.Diagonal((0.15, 0.008, 0.055, 1.0)),
        verts=verts_np,
    )
    vset_np = set(verts_np)
    for f in bm.faces:
        if all(v in vset_np for v in f.verts):
            f.material_index = 1

    # 4. Rear motor body + 3 radial steel struts connecting motor to duct barrel
    motor_y = 0.165
    ret_m = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=12, radius1=0.105, radius2=0.095, depth=0.11)
    verts_m = ret_m["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((0.0, motor_y, SPIN_Z))) @ rot_x90, verts=verts_m)
    vset_m = set(verts_m)
    for f in bm.faces:
        if all(v in vset_m for v in f.verts):
            f.material_index = 3

    for k in range(3):
        ang = math.radians(30.0 + k * 120.0)
        strut_r = 0.5 * (0.09 + BORE_R)
        sx = math.cos(ang) * strut_r
        sz = SPIN_Z + math.sin(ang) * strut_r
        rot_strut = Matrix.Rotation(-ang, 4, "Y")
        ret_s = bmesh.ops.create_cube(bm, size=1.0)
        verts_s = ret_s["verts"]
        bmesh.ops.transform(
            bm,
            matrix=Matrix.Translation(Vector((sx, 0.195, sz))) @ rot_strut @ Matrix.Diagonal((BORE_R - 0.08, 0.022, 0.032, 1.0)),
            verts=verts_s,
        )
        vset_s = set(verts_s)
        for f in bm.faces:
            if all(v in vset_s for v in f.verts):
                f.material_index = 3

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    _unwrap_bmesh_regions(
        bm,
        {
            0: (0.01, 0.49, 0.51, 0.99),    # Q0 weathered gray frame
            1: (0.01, 0.49, 0.26, 0.49),    # Q2 top nameplate
            2: (0.01, 0.49, 0.01, 0.24),    # Q2 bottom duct barrel
            3: (0.51, 0.99, 0.01, 0.49),    # Q3 dark motor & struts
        },
    )

    mesh = bpy.data.meshes.new("FanHousing")
    bm.to_mesh(mesh)
    bm.free()

    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new("FanHousing", mesh)
    bpy.context.collection.objects.link(obj)
    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tri_count


def _build_rotor(mat: "bpy.types.Material") -> tuple["bpy.types.Object", int]:
    """Build FanRotor (5-blade impeller) with origin centered on spin axis (0, ROTOR_Y, SPIN_Z)."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    bm = bmesh.new()
    # Tags: 0=central hub & shaft cap (Q3), 1=5 pitched fan blades (Q1)
    rot_x90 = Matrix.Rotation(math.radians(90.0), 4, "X")

    # Central stepped hub centered at local (0, 0, 0)
    ret_h = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=10, radius1=0.092, radius2=0.086, depth=0.072)
    verts_h = ret_h["verts"]
    bmesh.ops.transform(bm, matrix=rot_x90, verts=verts_h)
    vset_h = set(verts_h)
    for f in bm.faces:
        if all(v in vset_h for v in f.verts):
            f.material_index = 0

    # Front center shaft nut/boss facing -Y
    ret_n = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.022, radius2=0.018, depth=0.028)
    verts_n = ret_n["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((0.0, -0.044, 0.0))) @ rot_x90, verts=verts_n)
    vset_n = set(verts_n)
    for f in bm.faces:
        if all(v in vset_n for v in f.verts):
            f.material_index = 0

    # 5 Pitched, tapered sheet-metal impeller blades around local Y spin axis
    r_stations = (0.082, 0.165, 0.255, 0.340)
    chord_stations = (0.085, 0.125, 0.145, 0.135)
    pitch_stations = (38.0, 33.0, 28.0, 24.0)
    blade_thick = 0.008

    for b_idx in range(BLADE_COUNT):
        az = math.radians(b_idx * (360.0 / float(BLADE_COUNT)))
        rot_az = Matrix.Rotation(az, 4, "Y")

        front_rows: list[list[bmesh.types.BMVert]] = []
        back_rows: list[list[bmesh.types.BMVert]] = []
        for r_val, c_val, p_deg in zip(r_stations, chord_stations, pitch_stations):
            pitch = math.radians(p_deg)
            cp, sp = math.cos(pitch), math.sin(pitch)
            f_row: list[bmesh.types.BMVert] = []
            b_row: list[bmesh.types.BMVert] = []
            # 3 spanwise chord points for slight aerodynamic camber
            for s_t, camber in ((-0.5, -0.004), (0.0, 0.006), (0.5, -0.004)):
                local_x = r_val
                tangent_z = s_t * c_val
                # Pitch rotates chord in local (Y, Z) plane around radial X axis
                y_off = tangent_z * sp + camber * cp
                z_off = tangent_z * cp - camber * sp
                p_f = rot_az @ Vector((local_x, y_off - blade_thick * 0.5 * cp, z_off + blade_thick * 0.5 * sp))
                p_b = rot_az @ Vector((local_x, y_off + blade_thick * 0.5 * cp, z_off - blade_thick * 0.5 * sp))
                f_row.append(bm.verts.new(p_f))
                b_row.append(bm.verts.new(p_b))
            front_rows.append(f_row)
            back_rows.append(b_row)

        blade_faces: list[bmesh.types.BMFace] = []
        n_r = len(r_stations)
        n_c = 3
        for ri in range(n_r - 1):
            for ci in range(n_c - 1):
                blade_faces.append(bm.faces.new((front_rows[ri][ci], front_rows[ri + 1][ci], front_rows[ri + 1][ci + 1], front_rows[ri][ci + 1])))
                blade_faces.append(bm.faces.new((back_rows[ri][ci + 1], back_rows[ri + 1][ci + 1], back_rows[ri + 1][ci], back_rows[ri][ci])))
        # Leading & trailing edges
        for ri in range(n_r - 1):
            blade_faces.append(bm.faces.new((front_rows[ri][0], back_rows[ri][0], back_rows[ri + 1][0], front_rows[ri + 1][0])))
            blade_faces.append(bm.faces.new((front_rows[ri + 1][-1], back_rows[ri + 1][-1], back_rows[ri][-1], front_rows[ri][-1])))
        # Root & tip caps
        for ci in range(n_c - 1):
            blade_faces.append(bm.faces.new((front_rows[0][ci], front_rows[0][ci + 1], back_rows[0][ci + 1], back_rows[0][ci])))
            blade_faces.append(bm.faces.new((back_rows[-1][ci], back_rows[-1][ci + 1], front_rows[-1][ci + 1], front_rows[-1][ci])))
        for f in blade_faces:
            f.material_index = 1

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    _unwrap_bmesh_regions(
        bm,
        {
            0: (0.51, 0.99, 0.01, 0.49),    # Q3 dark oxidized hub
            1: (0.51, 0.99, 0.51, 0.99),    # Q1 rusted steel blades
        },
    )

    mesh = bpy.data.meshes.new("FanRotor")
    bm.to_mesh(mesh)
    bm.free()

    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new("FanRotor", mesh)
    bpy.context.collection.objects.link(obj)
    # Pivot centered exactly on spin axis (X=0, Y=ROTOR_Y, Z=0.45 -> Godot (0, 0.45, -ROTOR_Y))
    obj.location = (0.0, ROTOR_Y, SPIN_Z)
    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tri_count


def _build_mesh_and_export() -> None:
    """Build FanHousing + FanRotor as separate objects and export Godot GLB."""
    import bpy
    from mathutils import Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            [str(REPO_ROOT / ".venv" / "bin" / "python"), str(Path(__file__).resolve()), "--textures"],
            check=True,
        )

    clean_scene()
    mat = _build_shared_material()
    housing_obj, housing_tris = _build_housing(mat)
    rotor_obj, rotor_tris = _build_rotor(mat)

    # Apply rotation/scale only; preserve FanRotor location pivot on spin axis!
    bpy.ops.object.select_all(action="DESELECT")
    for o in (housing_obj, rotor_obj):
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.select_set(False)

    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for o in (housing_obj, rotor_obj):
        for v in o.data.vertices:
            wp = o.matrix_world @ v.co
            mins.x = min(mins.x, wp.x)
            mins.y = min(mins.y, wp.y)
            mins.z = min(mins.z, wp.z)
            maxs.x = max(maxs.x, wp.x)
            maxs.y = max(maxs.y, wp.y)
            maxs.z = max(maxs.z, wp.z)

    dims_godot = [
        round(maxs.x - mins.x, 4),
        round(maxs.z - mins.z, 4),
        round(maxs.y - mins.y, 4),
    ]
    total_tris = housing_tris + rotor_tris

    export_godot_glb(GLB_PATH, export_animations=False, export_morph=False, only_selected=False)

    manifest = {
        "prop_slug": PROP_SLUG,
        "objects": ["FanHousing", "FanRotor"],
        "rotor_pivot_godot": [0.0, SPIN_Z, -ROTOR_Y],
        "tri_count": total_tris,
        "tri_budget": TRI_BUDGET,
        "uv_layers": len(housing_obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "min_y": round(mins.z, 4),
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "reference_image": REF_IMAGE,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_INDUSTRIAL_EXHAUST_FAN:", json.dumps(manifest, indent=2))


def main() -> None:
    if "--textures" in sys.argv:
        _generate_pbr_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
