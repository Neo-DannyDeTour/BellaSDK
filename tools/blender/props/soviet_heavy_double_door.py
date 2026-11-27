"""Procedural Soviet Heavy Double Door with Separate Frame & Hinged Leaves (2.20m H).

Matches references /home/dkd/Downloads/hl2_refs/2026-10-30_18-28_2.png and
/home/dkd/Downloads/hl2_refs/2026-11-05_19-30.png:
- DoorFrame: stepped architrave casing, rebate jambs, steel threshold, 6 barrel hinges
- DoorLeafLeft: pivot centered at left hinge edge (-0.684, 0.015, 0.025 in Godot)
- DoorLeafRight: pivot centered at right hinge edge (+0.684, 0.015, 0.025 in Godot)
- Coffered upper molded panels, lower rosette medallions, metal kickplates, lever handles
- Shared 2048x2048 weathered painted timber + oxidized iron/brass PBR atlas & .tres

Usage:
    .venv/bin/python tools/blender/props/soviet_heavy_double_door.py --textures
    python3 tools/blender/run.py tools/blender/props/soviet_heavy_double_door.py
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

PROP_SLUG: str = "soviet_heavy_double_door"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{PROP_SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-28_2.png"

MAT_WOOD: Path = REPO_ROOT / "assets" / "materials" / "weathered_olive_crate_wood" / "textures"
MAT_RUSTED_STEEL: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
MAT_WROUGHT: Path = REPO_ROOT / "assets" / "materials" / "gothic_wrought_metal" / "textures"
MAT_BRASS: Path = REPO_ROOT / "assets" / "materials" / "tarnished_brass" / "textures"

TEX_SIZE: int = 2048
TARGET_HEIGHT_M: float = 2.20
TRI_BUDGET: int = 1800

# Dimensions in meters (Blender Z-up, front faces -Y)
FRAME_W: float = 1.56
FRAME_H: float = 2.20
FRAME_D: float = 0.16
JAMB_W: float = 0.094
HEADER_H: float = 0.085
THRESHOLD_H: float = 0.015

LEAF_W: float = 0.680
LEAF_H: float = 2.095
LEAF_T: float = 0.052
LEAF_PIVOT_X: float = 0.684   # +/-0.684m from center -> 4mm center gap, 2mm side clearance
LEAF_PIVOT_Y: float = -0.025
LEAF_PIVOT_Z: float = THRESHOLD_H


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
    """Build 2048x2048 weathered Soviet painted wood + dark iron + brass PBR atlas."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2

    wd_alb = _load_resized_rgb(MAT_WOOD / "weathered_olive_crate_wood_albedo.png", half, half)
    wd_nrm = _load_resized_rgb(MAT_WOOD / "weathered_olive_crate_wood_normal.png", half, half)
    wd_ao = _load_resized_l(MAT_WOOD / "weathered_olive_crate_wood_ao.png", half, half)
    wd_rgh = _load_resized_l(MAT_WOOD / "weathered_olive_crate_wood_roughness.png", half, half)

    wr_alb = _load_resized_rgb(MAT_WROUGHT / "gothic_wrought_metal_albedo.png", half, half)
    wr_nrm = _load_resized_rgb(MAT_WROUGHT / "gothic_wrought_metal_normal.png", half, half)
    wr_rgh = _load_resized_l(MAT_WROUGHT / "gothic_wrought_metal_roughness.png", half, half)

    rs_alb = _load_resized_rgb(MAT_RUSTED_STEEL / "rusted_steel_albedo.png", half, half)
    rs_nrm = _load_resized_rgb(MAT_RUSTED_STEEL / "rusted_steel_normal.png", half, half)
    rs_ao = _load_resized_l(MAT_RUSTED_STEEL / "rusted_steel_ao.png", half, half)
    rs_rgh = _load_resized_l(MAT_RUSTED_STEEL / "rusted_steel_roughness.png", half, half)

    br_alb = _load_resized_rgb(MAT_BRASS / "tarnished_brass_albedo.png", half, half)
    br_nrm = _load_resized_rgb(MAT_BRASS / "tarnished_brass_normal.png", half, half)
    br_rgh = _load_resized_l(MAT_BRASS / "tarnished_brass_roughness.png", half, half)

    # Rotate wood grain 90 degrees so planks run vertically on door stiles & panels
    wd_alb_v = np.rot90(wd_alb, k=1)
    wd_nrm_v = np.rot90(wd_nrm, k=1)
    wd_ao_v = np.rot90(wd_ao, k=1)
    wd_rgh_v = np.rot90(wd_rgh, k=1)

    # Q0 (Top-Left): Dusty Soviet Slate-Blue-Gray Painted Wood (door stiles, rails, casing)
    wd_lum = 0.299 * wd_alb_v[..., 0] + 0.587 * wd_alb_v[..., 1] + 0.114 * wd_alb_v[..., 2]
    slate_wood = np.stack([wd_lum * 0.88, wd_lum * 0.96, wd_lum * 0.98], axis=-1)
    # Subtle warm wood exposure in deep gouges/scratches
    gouge = np.clip((68.0 - wd_lum) / 30.0, 0.0, 1.0)
    q0_alb = np.clip(slate_wood * (1.0 - gouge[..., None] * 0.45) + wd_alb_v * (gouge[..., None] * 0.45), 34, 220)
    q0_nrm = np.clip((wd_nrm_v - 128.0) * 0.65 + 128.0, 0, 255)
    q0_ao = np.clip(wd_ao_v, 65, 255)
    q0_rgh = np.clip(wd_rgh_v * 0.95, 130, 238)
    q0_met = np.zeros((half, half), dtype=np.float32)

    # Q1 (Top-Right): Darker Aged Recessed Panel Wood + Grime
    q1_alb = np.clip(q0_alb * 0.84 + np.array([12.0, 14.0, 16.0])[None, None, :] * 0.16, 30, 200)
    q1_nrm = q0_nrm
    q1_ao = np.clip(q0_ao * 0.88, 55, 255)
    q1_rgh = np.clip(q0_rgh + 12.0, 145, 242)
    q1_met = np.zeros((half, half), dtype=np.float32)

    # Q2 (Bottom-Left): Heavy Oxidized Iron Kickplates, Astragal Strip, Threshold & Hinges
    q2_alb = np.clip(wr_alb * 0.68 + rs_alb * 0.32, 32, 185)
    q2_nrm = np.clip((wr_nrm - 128.0) * 0.55 + (rs_nrm - 128.0) * 0.45 + 128.0, 0, 255)
    q2_ao = np.clip(rs_ao * 0.85 + 30.0, 60, 255)
    q2_rgh = np.clip(0.55 * wr_rgh + 0.45 * rs_rgh, 80, 220)
    # Bare iron = high metallic; rust patches = lower metallic
    rs_lum = 0.299 * rs_alb[..., 0] + 0.587 * rs_alb[..., 1] + 0.114 * rs_alb[..., 2]
    q2_met = np.clip(215.0 - np.clip((85.0 - rs_lum) * 1.4, 0.0, 110.0), 80, 235)

    # Q3 (Bottom-Right): Left half = Rosette Medallion Relief Metal/Wood; Right half = Tarnished Brass Hardware
    split = half // 2
    med_alb = np.clip(q0_alb[:, :split] * 0.90 + wr_alb[:, :split] * 0.10, 34, 210)
    med_nrm = q0_nrm[:, :split]
    med_ao = np.clip(q0_ao[:, :split] * 0.90, 60, 255)
    med_rgh = np.clip(q0_rgh[:, :split] * 0.90, 120, 225)
    med_met = np.full((half, split), 40.0, dtype=np.float32)

    b_ao = np.full((half, half - split), 225.0, dtype=np.float32)
    b_rgh = np.clip(br_rgh[:, split:], 65, 175)
    b_met = np.full((half, half - split), 235.0, dtype=np.float32)

    q3_alb = np.concatenate([med_alb, br_alb[:, split:]], axis=1)
    q3_nrm = np.concatenate([med_nrm, br_nrm[:, split:]], axis=1)
    q3_ao = np.concatenate([med_ao, b_ao], axis=1)
    q3_rgh = np.concatenate([med_rgh, b_rgh], axis=1)
    q3_met = np.concatenate([med_met, b_met], axis=1)

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
        material_name="M_SovietHeavyDoubleDoor",
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

    mat = bpy.data.materials.new(name="M_SovietHeavyDoubleDoor")
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


def _add_box(bm: "bmesh.types.BMesh", center: "Vector", size: "Vector", tag: int) -> None:
    import bmesh
    from mathutils import Matrix

    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    bmesh.ops.transform(
        bm,
        matrix=Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0)),
        verts=verts,
    )
    vset = set(verts)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = tag


def _add_cyl(bm: "bmesh.types.BMesh", center: "Vector", radius: float, depth: float, segs: int, tag: int, rot_mat: "Matrix | None" = None) -> None:
    import bmesh
    from mathutils import Matrix

    ret = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segs, radius1=radius, radius2=radius, depth=depth
    )
    verts = ret["verts"]
    bmesh.ops.transform(
        bm,
        matrix=Matrix.Translation(center) @ (rot_mat if rot_mat is not None else Matrix.Identity(4)),
        verts=verts,
    )
    vset = set(verts)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = tag


def _build_frame(mat: "bpy.types.Material") -> tuple["bpy.types.Object", int]:
    """Build DoorFrame with stepped architrave casing, steel threshold, and 6 hinge knuckles."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()
    # Tags: 0=slate painted wood frame, 2=oxidized iron threshold & hinge knuckles
    hx = FRAME_W * 0.5  # 0.78
    # Main jambs (left & right, full height 2.20m)
    _add_box(bm, Vector((-hx + JAMB_W * 0.5, 0.0, FRAME_H * 0.5)), Vector((JAMB_W, FRAME_D, FRAME_H)), tag=0)
    _add_box(bm, Vector((+hx - JAMB_W * 0.5, 0.0, FRAME_H * 0.5)), Vector((JAMB_W, FRAME_D, FRAME_H)), tag=0)
    # Top header lintel (between jambs)
    inner_span = FRAME_W - 2.0 * JAMB_W  # 1.372
    _add_box(bm, Vector((0.0, 0.0, FRAME_H - HEADER_H * 0.5)), Vector((inner_span, FRAME_D, HEADER_H)), tag=0)

    # Stepped front & back architrave trim moldings (non-overlapping proud casing strips)
    trim_w = 0.055
    trim_d = 0.022
    for y_sign in (-1.0, 1.0):
        ty = y_sign * (FRAME_D * 0.5 + trim_d * 0.5)
        _add_box(bm, Vector((-hx + trim_w * 0.5, ty, FRAME_H * 0.5)), Vector((trim_w, trim_d, FRAME_H)), tag=0)
        _add_box(bm, Vector((+hx - trim_w * 0.5, ty, FRAME_H * 0.5)), Vector((trim_w, trim_d, FRAME_H)), tag=0)
        _add_box(bm, Vector((0.0, ty, FRAME_H - trim_w * 0.5)), Vector((FRAME_W - 2.0 * trim_w, trim_d, trim_w)), tag=0)

    # Steel threshold plate at floor level (Z = 0..0.015)
    _add_box(bm, Vector((0.0, 0.0, THRESHOLD_H * 0.5)), Vector((inner_span, FRAME_D + 0.02, THRESHOLD_H)), tag=2)

    # 3 Heavy barrel hinge knuckles mounted along left & right inner jambs
    for sx in (-1.0, 1.0):
        for hz in (0.28, 1.08, 1.88):
            _add_cyl(bm, Vector((sx * LEAF_PIVOT_X, LEAF_PIVOT_Y - 0.026, hz)), radius=0.013, depth=0.085, segs=8, tag=2)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    _unwrap_bmesh_regions(
        bm,
        {
            0: (0.01, 0.49, 0.51, 0.99),  # Q0 weathered slate wood
            2: (0.01, 0.49, 0.01, 0.49),  # Q2 oxidized iron
        },
    )

    mesh = bpy.data.meshes.new("DoorFrame")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new("DoorFrame", mesh)
    bpy.context.collection.objects.link(obj)
    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tri_count


def _build_door_leaf(name: str, is_left: bool, mat: "bpy.types.Material") -> tuple["bpy.types.Object", int]:
    """Build DoorLeafLeft or DoorLeafRight in local space with origin on the hinge edge."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    bm = bmesh.new()
    # Tags: 0=stiles/rails (Q0), 1=recessed coffered panels (Q1),
    #       2=kickplate/astragal/hinge straps (Q2), 3=rosette medallion (Q3 left), 4=brass handle (Q3 right)
    dir_x = 1.0 if is_left else -1.0
    x_center = dir_x * (LEAF_W * 0.5)
    x_meet = dir_x * LEAF_W

    stile_w = 0.095
    mid_rail_z0 = 0.60
    mid_rail_z1 = 0.72
    bot_rail_h = 0.16
    top_rail_h = 0.14
    panel_t = 0.024

    # 1. Outer stiles & rails (full thickness LEAF_T = 0.052m around recessed upper & lower panels)
    # Hinge stile (at x = 0..dir_x*stile_w)
    _add_box(bm, Vector((dir_x * stile_w * 0.5, 0.0, LEAF_H * 0.5)), Vector((stile_w, LEAF_T, LEAF_H)), tag=0)
    # Meeting stile (at x = x_meet - dir_x*stile_w .. x_meet)
    _add_box(bm, Vector((x_meet - dir_x * stile_w * 0.5, 0.0, LEAF_H * 0.5)), Vector((stile_w, LEAF_T, LEAF_H)), tag=0)

    inner_w = LEAF_W - 2.0 * stile_w  # 0.490m
    # Bottom rail, middle lock rail, top rail (fit cleanly between stiles)
    _add_box(bm, Vector((x_center, 0.0, bot_rail_h * 0.5)), Vector((inner_w, LEAF_T, bot_rail_h)), tag=0)
    _add_box(bm, Vector((x_center, 0.0, 0.5 * (mid_rail_z0 + mid_rail_z1))), Vector((inner_w, LEAF_T, mid_rail_z1 - mid_rail_z0)), tag=0)
    _add_box(bm, Vector((x_center, 0.0, LEAF_H - top_rail_h * 0.5)), Vector((inner_w, LEAF_T, top_rail_h)), tag=0)

    # 2. Recessed Upper Coffered Panel + Beveled Inner Molding Frame
    up_h = (LEAF_H - top_rail_h) - mid_rail_z1
    up_cz = 0.5 * (mid_rail_z1 + (LEAF_H - top_rail_h))
    _add_box(bm, Vector((x_center, 0.0, up_cz)), Vector((inner_w, panel_t, up_h)), tag=1)
    # Inner raised bolection molding frame around upper panel (front & back)
    mold_w = 0.026
    mold_d = 0.010
    for y_s in (-1.0, 1.0):
        my = y_s * (panel_t * 0.5 + mold_d * 0.5)
        _add_box(bm, Vector((x_center - inner_w * 0.5 + mold_w * 0.5, my, up_cz)), Vector((mold_w, mold_d, up_h)), tag=0)
        _add_box(bm, Vector((x_center + inner_w * 0.5 - mold_w * 0.5, my, up_cz)), Vector((mold_w, mold_d, up_h)), tag=0)
        _add_box(bm, Vector((x_center, my, up_cz + up_h * 0.5 - mold_w * 0.5)), Vector((inner_w - 2.0 * mold_w, mold_d, mold_w)), tag=0)
        _add_box(bm, Vector((x_center, my, up_cz - up_h * 0.5 + mold_w * 0.5)), Vector((inner_w - 2.0 * mold_w, mold_d, mold_w)), tag=0)

    # 3. Recessed Lower Panel + Embossed Circular Rosette Medallion (matching 2026-10-30_18-28_2.png)
    lo_h = mid_rail_z0 - bot_rail_h
    lo_cz = 0.5 * (bot_rail_h + mid_rail_z0)
    _add_box(bm, Vector((x_center, 0.0, lo_cz)), Vector((inner_w, panel_t, lo_h)), tag=1)
    rot_x90 = Matrix.Rotation(math.radians(90.0), 4, "X")
    for y_s in (-1.0, 1.0):
        _add_cyl(bm, Vector((x_center, y_s * (panel_t * 0.5 + 0.006), lo_cz)), radius=0.125, depth=0.012, segs=12, tag=3, rot_mat=rot_x90)
        _add_cyl(bm, Vector((x_center, y_s * (panel_t * 0.5 + 0.012), lo_cz)), radius=0.055, depth=0.010, segs=10, tag=3, rot_mat=rot_x90)

    # 4. Iron Kickplate (bottom front/back) + Hinge Straps + Center Astragal Seam Strip (on left leaf)
    _add_box(bm, Vector((x_center, -LEAF_T * 0.5 - 0.002, 0.075)), Vector((LEAF_W - 0.01, 0.004, 0.145)), tag=2)
    _add_box(bm, Vector((x_center, +LEAF_T * 0.5 + 0.002, 0.075)), Vector((LEAF_W - 0.01, 0.004, 0.145)), tag=2)

    if is_left:
        # Center astragal security cover strip along meeting edge
        _add_box(bm, Vector((x_meet, -LEAF_T * 0.5 - 0.004, LEAF_H * 0.5)), Vector((0.032, 0.008, LEAF_H - 0.02)), tag=2)

    # Hinge leaf straps connecting hinge edge to door face
    for hz in (0.28, 1.08, 1.88):
        _add_box(bm, Vector((dir_x * 0.045, -LEAF_T * 0.5 - 0.003, hz - LEAF_PIVOT_Z)), Vector((0.09, 0.006, 0.036)), tag=2)

    # 5. Brass Escutcheon Backplate & Lever Handles (front & back)
    handle_x = x_meet - dir_x * 0.068
    handle_z = 0.98
    lever_dir = -dir_x  # lever points away from center seam toward hinge
    for y_s in (-1.0, 1.0):
        ey = y_s * (LEAF_T * 0.5 + 0.004)
        _add_box(bm, Vector((handle_x, ey, handle_z)), Vector((0.036, 0.008, 0.165)), tag=4)
        # Lever stem + horizontal grip bar
        _add_box(bm, Vector((handle_x, ey + y_s * 0.018, handle_z + 0.02)), Vector((0.016, 0.032, 0.016)), tag=4)
        _add_box(bm, Vector((handle_x + lever_dir * 0.048, ey + y_s * 0.034, handle_z + 0.02)), Vector((0.105, 0.014, 0.016)), tag=4)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    _unwrap_bmesh_regions(
        bm,
        {
            0: (0.01, 0.49, 0.51, 0.99),   # Q0 slate wood stiles/rails
            1: (0.51, 0.99, 0.51, 0.99),   # Q1 darker recessed panels
            2: (0.01, 0.49, 0.01, 0.49),   # Q2 oxidized iron kickplate/straps
            3: (0.51, 0.74, 0.01, 0.49),   # Q3 left rosette medallion
            4: (0.76, 0.99, 0.01, 0.49),   # Q3 right tarnished brass handle
        },
    )

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (-LEAF_PIVOT_X if is_left else +LEAF_PIVOT_X, LEAF_PIVOT_Y, LEAF_PIVOT_Z)
    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tri_count


def _build_mesh_and_export() -> None:
    """Build DoorFrame + DoorLeafLeft + DoorLeafRight and export Godot GLB."""
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
    frame_obj, frame_tris = _build_frame(mat)
    left_obj, left_tris = _build_door_leaf("DoorLeafLeft", True, mat)
    right_obj, right_tris = _build_door_leaf("DoorLeafRight", False, mat)

    bpy.ops.object.select_all(action="DESELECT")
    for o in (frame_obj, left_obj, right_obj):
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.select_set(False)

    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for o in (frame_obj, left_obj, right_obj):
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
    total_tris = frame_tris + left_tris + right_tris

    export_godot_glb(GLB_PATH, export_animations=False, export_morph=False, only_selected=False)

    manifest = {
        "prop_slug": PROP_SLUG,
        "objects": ["DoorFrame", "DoorLeafLeft", "DoorLeafRight"],
        "leaf_pivots_godot": {
            "DoorLeafLeft": [-LEAF_PIVOT_X, LEAF_PIVOT_Z, -LEAF_PIVOT_Y],
            "DoorLeafRight": [LEAF_PIVOT_X, LEAF_PIVOT_Z, -LEAF_PIVOT_Y],
        },
        "tri_count": total_tris,
        "tri_budget": TRI_BUDGET,
        "uv_layers": len(frame_obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "min_y": round(mins.z, 4),
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "reference_image": REF_IMAGE,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_SOVIET_HEAVY_DOUBLE_DOOR:", json.dumps(manifest, indent=2))


def main() -> None:
    if "--textures" in sys.argv:
        _generate_pbr_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
