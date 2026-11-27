"""Procedural Tilting Park Bin on Tubular Steel Hairpin Frame (0.72m).

Matches reference /home/dkd/Desktop/Refs/IMG_20261125_170206.jpg:
- Tapered open-top cylindrical weathered dusty slate-blue-gray painted steel drum
- Two bent tubular steel hairpin A-frame side legs with ground crossbars & foot pads
- Side pivot axle sleeves + hex bolt caps connecting drum to frame
- 2048x2048 mixed-material PBR maps derived from painted_industrial_metal + rusted_steel
  (faded matte paint + chalky water-drip weathering + scuffed bare metal edges + grimy interior)

Usage:
    python3 tools/blender/props/tilting_park_bin.py --textures
    python3 tools/blender/run.py tools/blender/props/tilting_park_bin.py
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

ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "tilting_park_bin"
GLB_PATH: Path = ASSET_DIR / "tilting_park_bin.glb"
TRES_PATH: Path = ASSET_DIR / "tilting_park_bin.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / "tilting_park_bin_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / "tilting_park_bin_normal.png"
ORM_PATH: Path = ASSET_DIR / "tilting_park_bin_orm.png"
REF_IMAGE: str = "/home/dkd/Desktop/Refs/IMG_20261125_170206.jpg"

MAT_PAINTED_METAL: Path = REPO_ROOT / "assets" / "materials" / "painted_industrial_metal" / "textures"
MAT_RUSTED_STEEL: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
MAT_STAINED_CONCRETE: Path = REPO_ROOT / "assets" / "materials" / "factory_stained_concrete" / "textures"

TEX_SIZE: int = 2048
EXT_SPLIT_U: float = 0.72  # [0, 0.72) exterior + frame (with top rim strip V>=0.84), [0.72, 1.0] grimy interior

# Target height = 0.72m (Blender Z: 0.0 -> 0.72m, Godot Y: 0.0 -> 0.72m)
TOTAL_HEIGHT: float = 0.72
DRUM_BOT_Z: float = 0.135
DRUM_BOT_R: float = 0.154
DRUM_TOP_R: float = 0.168
DRUM_WALL_T: float = 0.007
DRUM_SEGS: int = 24

FRAME_HALF_W: float = 0.200
TUBE_R: float = 0.013
TUBE_SEGS: int = 10
FOOT_PAD_H: float = 0.008
FOOT_PAD_R: float = 0.019
PIVOT_Z: float = 0.445
PIVOT_Y: float = -0.037


def _generate_pbr_textures() -> None:
    """Build 2048x2048 weathered slate-blue-gray painted steel PBR atlas maps."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    split_px = int(round(TEX_SIZE * EXT_SPLIT_U))
    ext_w = split_px
    int_w = TEX_SIZE - split_px

    def _load_tiled(path: Path, tiles_x: float, tiles_y: float, out_w: int, out_h: int, mode: str) -> np.ndarray:
        src = Image.open(path).convert(mode)
        sw, sh = src.size
        rep_x = max(1, int(math.ceil(tiles_x)))
        rep_y = max(1, int(math.ceil(tiles_y)))
        tiled = Image.new(mode, (sw * rep_x, sh * rep_y))
        for iy in range(rep_y):
            for ix in range(rep_x):
                tiled.paste(src, (ix * sw, iy * sh))
        crop_w = max(1, int(round(sw * tiles_x)))
        crop_h = max(1, int(round(sh * tiles_y)))
        cropped = tiled.crop((0, 0, crop_w, crop_h))
        resized = cropped.resize((out_w, out_h), Image.Resampling.BICUBIC)
        return np.array(resized, dtype=np.float32)

    def _build_slate_region(out_w: int, tiles_x: float, tiles_y: float, is_interior: bool) -> tuple[
        Image.Image, Image.Image, Image.Image, Image.Image, Image.Image
    ]:
        pm_alb = _load_tiled(MAT_PAINTED_METAL / "painted_industrial_metal_albedo.png", tiles_x, tiles_y, out_w, TEX_SIZE, "RGB")
        pm_nrm = _load_tiled(MAT_PAINTED_METAL / "painted_industrial_metal_normal.png", tiles_x, tiles_y, out_w, TEX_SIZE, "RGB")
        pm_orm = _load_tiled(MAT_PAINTED_METAL / "painted_industrial_metal_orm.png", tiles_x, tiles_y, out_w, TEX_SIZE, "RGB")

        rs_alb = _load_tiled(MAT_RUSTED_STEEL / "rusted_steel_albedo.png", tiles_x * 1.4, tiles_y * 1.4, out_w, TEX_SIZE, "RGB")
        rs_nrm = _load_tiled(MAT_RUSTED_STEEL / "rusted_steel_normal.png", tiles_x * 1.4, tiles_y * 1.4, out_w, TEX_SIZE, "RGB")

        drip_src = _load_tiled(MAT_STAINED_CONCRETE / "factory_stained_concrete_albedo.png", tiles_x * 1.2, tiles_y * 1.5, out_w, TEX_SIZE, "RGB")
        drip_lum = (0.299 * drip_src[..., 0] + 0.587 * drip_src[..., 1] + 0.114 * drip_src[..., 2]) / 255.0

        # Identify chipped/scratched areas in painted_industrial_metal (subtle edge & scratch wear)
        pm_lum = (0.299 * pm_alb[..., 0] + 0.587 * pm_alb[..., 1] + 0.114 * pm_alb[..., 2]) / 255.0
        chip_mask = np.clip((0.23 - pm_lum) / 0.11, 0.0, 1.0) * 0.65

        # Color-grade faded teal paint into weathered dusty slate-blue-gray (sRGB ~75..135)
        paint_gray = (pm_lum * 0.36 + 0.27) * 255.0
        slate_r = np.clip(paint_gray * 0.86 + pm_alb[..., 0] * 0.06, 68.0, 122.0)
        slate_g = np.clip(paint_gray * 0.93 + pm_alb[..., 1] * 0.06, 74.0, 128.0)
        slate_b = np.clip(paint_gray * 1.00 + pm_alb[..., 2] * 0.08, 78.0, 134.0)
        slate_rgb = np.stack([slate_r, slate_g, slate_b], axis=-1)

        # Blend bare scuffed steel into chipped spots (gunmetal gray + faint oxide, never bright orange)
        rs_lum = (0.299 * rs_alb[..., 0] + 0.587 * rs_alb[..., 1] + 0.114 * rs_alb[..., 2])[..., None]
        desat_steel = 0.70 * rs_lum + 0.30 * rs_alb
        bare_metal_rgb = np.clip(desat_steel * 0.95 + np.array([34.0, 36.0, 39.0]), 54.0, 118.0)
        alb = slate_rgb * (1.0 - chip_mask[..., None]) + bare_metal_rgb * chip_mask[..., None]

        # Chalky water-drip weathering using real stained concrete drip pattern
        chalk_mask = np.clip((drip_lum - 0.54) * 2.8, 0.0, 0.42)
        alb = alb * (1.0 - chalk_mask[..., None]) + np.array([124.0, 128.0, 131.0]) * chalk_mask[..., None]

        # V coordinates (image top = V=1.0, bottom = V=0.0)
        v_coords = 1.0 - np.linspace(0.0, 1.0, TEX_SIZE, dtype=np.float32)[:, None]

        if not is_interior:
            # Top rolled rim band (V >= 0.84) gets extra exposed scuffed steel edge wear
            rim_band = np.clip((v_coords - 0.84) / 0.14, 0.0, 1.0)
            scuff_mask = np.clip(chip_mask + rim_band * (0.45 + 0.45 * (1.0 - pm_lum)), 0.0, 1.0)
            alb = alb * (1.0 - rim_band[..., None] * 0.25) + np.array([112.0, 118.0, 124.0]) * (rim_band[..., None] * 0.25)
        else:
            # Grimy interior drum & rim (warmer dusty ash grime, darker in lower basin)
            grime_grad = np.clip((0.88 - v_coords) / 0.85, 0.0, 0.35)
            rim_grime = np.clip((v_coords - 0.78) / 0.20, 0.0, 1.0) * 0.22
            alb = alb * (1.0 - grime_grad[..., None] - rim_grime[..., None])
            alb[..., 0] += grime_grad * 18.0 + rim_grime * 24.0
            alb[..., 1] += grime_grad * 17.0 + rim_grime * 22.0
            alb[..., 2] += grime_grad * 14.0 + rim_grime * 18.0
            scuff_mask = np.clip(chip_mask * 0.8 + rim_grime * 1.4, 0.0, 1.0)

        alb_img = Image.fromarray(np.clip(alb, 30, 240).astype(np.uint8), mode="RGB")

        # Normal map blend (painted metal + rusted steel micro-pitting)
        nrm_mix = (0.75 * pm_nrm + 0.25 * rs_nrm) / 255.0 * 2.0 - 1.0
        nrm_mix[..., 2] = np.maximum(nrm_mix[..., 2], 0.25)
        nrm_len = np.sqrt(np.sum(nrm_mix * nrm_mix, axis=-1, keepdims=True))
        nrm_mix /= np.maximum(nrm_len, 1e-6)
        nrm_img = Image.fromarray(np.clip((nrm_mix * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

        # Mixed-material ORM:
        # Faded matte paint: metallic 0.00..0.15 (0..38), roughness 0.65..0.85 (166..217)
        # Exposed scuffed metal: metallic 0.75..0.90 (191..230), roughness 0.32..0.45 (82..115)
        paint_rough = np.clip(0.68 + (1.0 - pm_lum) * 0.16 + chalk_mask * 0.12, 0.65, 0.85)
        metal_rough = np.clip(0.34 + pm_lum * 0.14, 0.32, 0.45)
        eff_rough = paint_rough * (1.0 - scuff_mask) + metal_rough * scuff_mask

        paint_metal = np.full_like(scuff_mask, 0.06)
        bare_metal = np.full_like(scuff_mask, 0.83)
        eff_metal = paint_metal * (1.0 - scuff_mask) + bare_metal * scuff_mask

        ao = np.clip(pm_orm[..., 0] * (1.0 - chalk_mask * 0.15), 60, 255).astype(np.uint8)
        ao_img = Image.fromarray(ao, mode="L")
        rough_img = Image.fromarray(np.clip(eff_rough * 255.0, 0, 255).astype(np.uint8), mode="L")
        metal_img = Image.fromarray(np.clip(eff_metal * 255.0, 0, 255).astype(np.uint8), mode="L")
        return alb_img, nrm_img, ao_img, rough_img, metal_img

    e_alb, e_nrm, e_ao, e_rgh, e_mtl = _build_slate_region(ext_w, 1.45, 2.0, is_interior=False)
    i_alb, i_nrm, i_ao, i_rgh, i_mtl = _build_slate_region(int_w, 0.70, 2.0, is_interior=True)

    def _stitch_lr(left: Image.Image, right: Image.Image, mode: str) -> Image.Image:
        canvas = Image.new(mode, (TEX_SIZE, TEX_SIZE))
        canvas.paste(left, (0, 0))
        canvas.paste(right, (split_px, 0))
        return canvas

    albedo_atlas = _stitch_lr(e_alb, i_alb, "RGB")
    normal_atlas = _stitch_lr(e_nrm, i_nrm, "RGB")
    ao_atlas = _stitch_lr(e_ao, i_ao, "L")
    rough_atlas = _stitch_lr(e_rgh, i_rgh, "L")
    metal_atlas = _stitch_lr(e_mtl, i_mtl, "L")

    ao_tmp = ASSET_DIR / "_tmp_ao.png"
    rough_tmp = ASSET_DIR / "_tmp_rough.png"
    metal_tmp = ASSET_DIR / "_tmp_metal.png"

    albedo_atlas.save(ALBEDO_PATH, format="PNG")
    normal_atlas.save(NORMAL_PATH, format="PNG")
    ao_atlas.save(ao_tmp, format="PNG")
    rough_atlas.save(rough_tmp, format="PNG")
    metal_atlas.save(metal_tmp, format="PNG")

    process_pbr.pack_orm(ao_tmp, rough_tmp, str(metal_tmp), ORM_PATH, target_size=(TEX_SIZE, TEX_SIZE))
    ao_tmp.unlink(missing_ok=True)
    rough_tmp.unlink(missing_ok=True)
    metal_tmp.unlink(missing_ok=True)

    process_pbr.generate_godot_tres(
        material_name="M_TiltingParkBin",
        albedo_path=ALBEDO_PATH,
        normal_path=NORMAL_PATH,
        orm_path=ORM_PATH,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] Generated 2048x2048 {ALBEDO_PATH.name}, {NORMAL_PATH.name}, {ORM_PATH.name}, {TRES_PATH.name}")


def _build_mesh_and_export() -> None:
    """Build tilting park bin geometry in Blender, smart-UV unwrap regions, and export GLB."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).resolve()), "--textures"],
            check=True,
        )

    clean_scene()
    bm = bmesh.new()

    # Tags: 0=exterior/frame, 1=rolled top rim (scuffed metal edge), 2=interior drum basin
    rim_r_out = DRUM_TOP_R + 0.008
    rim_r_in = DRUM_TOP_R - DRUM_WALL_T
    drum_profile = [
        (DRUM_BOT_R - 0.006, DRUM_BOT_Z),
        (DRUM_BOT_R, DRUM_BOT_Z + 0.010),
        (DRUM_TOP_R, TOTAL_HEIGHT - 0.014),
        (rim_r_out, TOTAL_HEIGHT - 0.007),
        (rim_r_out - 0.004, TOTAL_HEIGHT),
        (rim_r_in + 0.002, TOTAL_HEIGHT - 0.002),
        (rim_r_in, TOTAL_HEIGHT - 0.012),
        (DRUM_BOT_R - DRUM_WALL_T - 0.005, DRUM_BOT_Z + 0.012),
    ]

    rings: list[list[bmesh.types.BMVert]] = []
    for i in range(DRUM_SEGS):
        ang = (2.0 * math.pi * i) / DRUM_SEGS
        ca, sa = math.cos(ang), math.sin(ang)
        rings.append([bm.verts.new((ca * r, sa * r, z)) for r, z in drum_profile])

    n_prof = len(drum_profile)
    for i in range(DRUM_SEGS):
        ni = (i + 1) % DRUM_SEGS
        for j in range(n_prof - 1):
            f = bm.faces.new((rings[i][j], rings[ni][j], rings[ni][j + 1], rings[i][j + 1]))
            f.smooth = True
            if j in (2, 3, 4, 5):
                f.material_index = 1
            elif j == 6:
                f.material_index = 2
            else:
                f.material_index = 0

    v_bot_center = bm.verts.new((0.0, 0.0, DRUM_BOT_Z))
    v_in_center = bm.verts.new((0.0, 0.0, DRUM_BOT_Z + 0.012))
    for i in range(DRUM_SEGS):
        ni = (i + 1) % DRUM_SEGS
        f_out = bm.faces.new((v_bot_center, rings[ni][0], rings[i][0]))
        f_out.smooth = False
        f_out.material_index = 0
        f_in = bm.faces.new((v_in_center, rings[i][-1], rings[ni][-1]))
        f_in.smooth = False
        f_in.material_index = 2

    def add_swept_tube(points: list[Vector], radius: float, segs: int, cap_ends: bool = True) -> None:
        tube_rings: list[list[bmesh.types.BMVert]] = []
        n_pts = len(points)
        for idx, pt in enumerate(points):
            if idx == 0:
                tangent = (points[1] - points[0]).normalized()
            elif idx == n_pts - 1:
                tangent = (points[-1] - points[-2]).normalized()
            else:
                t1 = (points[idx] - points[idx - 1]).normalized()
                t2 = (points[idx + 1] - points[idx]).normalized()
                tangent = (t1 + t2).normalized()
                if tangent.length < 1e-5:
                    tangent = t1

            ref = Vector((1.0, 0.0, 0.0)) if abs(tangent.x) < 0.85 else Vector((0.0, 0.0, 1.0))
            u_ax = tangent.cross(ref).normalized()
            v_ax = tangent.cross(u_ax).normalized()
            ring = []
            for s in range(segs):
                th = (2.0 * math.pi * s) / segs
                offset = (u_ax * math.cos(th) + v_ax * math.sin(th)) * radius
                ring.append(bm.verts.new(pt + offset))
            tube_rings.append(ring)

        for idx in range(n_pts - 1):
            for s in range(segs):
                ns = (s + 1) % segs
                f = bm.faces.new((
                    tube_rings[idx][s],
                    tube_rings[idx][ns],
                    tube_rings[idx + 1][ns],
                    tube_rings[idx + 1][s],
                ))
                f.smooth = True
                f.material_index = 0

        if cap_ends:
            f_start = bm.faces.new(list(reversed(tube_rings[0])))
            f_start.smooth = False
            f_start.material_index = 0
            f_end = bm.faces.new(tube_rings[-1])
            f_end.smooth = False
            f_end.material_index = 0

    z_foot = FOOT_PAD_H + TUBE_R
    arc_cy = 0.015
    arc_cz = 0.465
    arc_r = 0.046
    arc_pts_yz: list[tuple[float, float]] = [(-0.140, z_foot)]
    arc_steps = 8
    for k in range(arc_steps + 1):
        ang = math.radians(165.0 - (150.0 * k / arc_steps))
        py = arc_cy + math.cos(ang) * arc_r
        pz = arc_cz + math.sin(ang) * arc_r
        arc_pts_yz.append((py, pz))
    arc_pts_yz.append((0.190, z_foot))

    for sx in (-1.0, 1.0):
        pts = [Vector((sx * FRAME_HALF_W, py, pz)) for py, pz in arc_pts_yz]
        add_swept_tube(pts, TUBE_R, TUBE_SEGS, cap_ends=True)

        for fy in (-0.140, 0.190):
            ret = bmesh.ops.create_cone(
                bm,
                cap_ends=True,
                cap_tris=False,
                segments=12,
                radius1=FOOT_PAD_R,
                radius2=FOOT_PAD_R * 0.92,
                depth=FOOT_PAD_H,
                matrix=Matrix.Translation((sx * FRAME_HALF_W, fy, FOOT_PAD_H * 0.5)),
            )
            vset = set(ret["verts"])
            for f in bm.faces:
                if all(v in vset for v in f.verts):
                    f.material_index = 0

        rot_x = Matrix.Rotation(math.radians(90.0), 4, "Y")
        inner_x = DRUM_BOT_R - 0.004
        outer_x = FRAME_HALF_W + TUBE_R * 0.6
        axle_mid_x = sx * (inner_x + outer_x) * 0.5
        axle_len = outer_x - inner_x
        ret = bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=10,
            radius1=0.015,
            radius2=0.015,
            depth=axle_len,
            matrix=Matrix.Translation((axle_mid_x, PIVOT_Y, PIVOT_Z)) @ rot_x,
        )
        vset = set(ret["verts"])
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = 0

        ret = bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=6,
            radius1=0.012,
            radius2=0.011,
            depth=0.012,
            matrix=Matrix.Translation((sx * (FRAME_HALF_W + TUBE_R + 0.005), PIVOT_Y, PIVOT_Z)) @ rot_x,
        )
        vset = set(ret["verts"])
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = 1

    for bar_y in (-0.140, 0.190):
        add_swept_tube(
            [
                Vector((-FRAME_HALF_W, bar_y, z_foot)),
                Vector((FRAME_HALF_W, bar_y, z_foot)),
            ],
            TUBE_R * 0.88,
            TUBE_SEGS,
            cap_ends=False,
        )

    add_swept_tube(
        [
            Vector((-FRAME_HALF_W, -0.095, 0.165)),
            Vector((FRAME_HALF_W, -0.095, 0.165)),
        ],
        TUBE_R * 0.72,
        8,
        cap_ends=False,
    )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    bm.faces.ensure_lookup_table()
    ext_faces = [f.index for f in bm.faces if f.material_index == 0]
    rim_faces = [f.index for f in bm.faces if f.material_index == 1]
    int_faces = [f.index for f in bm.faces if f.material_index == 2]
    for f in bm.faces:
        f.material_index = 0

    mesh = bpy.data.meshes.new("TiltingParkBin")
    bm.to_mesh(mesh)
    bm.free()

    mat = bpy.data.materials.new(name="M_TiltingParkBin")
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
    nrm_node.inputs["Strength"].default_value = 0.70
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    mesh.materials.append(mat)

    obj = bpy.data.objects.new("TiltingParkBin", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")

    def _unwrap_region(
        face_indices: list[int],
        u_min: float,
        u_max: float,
        v_min: float,
        v_max: float,
    ) -> None:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for idx in face_indices:
            mesh.polygons[idx].select = True
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.018)
        bpy.ops.object.mode_set(mode="OBJECT")

        uv_data = mesh.uv_layers.active.data
        u_vals: list[float] = []
        v_vals: list[float] = []
        for idx in face_indices:
            for li in mesh.polygons[idx].loop_indices:
                uv = uv_data[li].uv
                u_vals.append(uv.x)
                v_vals.append(uv.y)
        cur_u0, cur_u1 = min(u_vals), max(u_vals)
        cur_v0, cur_v1 = min(v_vals), max(v_vals)
        du = max(cur_u1 - cur_u0, 1e-6)
        dv = max(cur_v1 - cur_v0, 1e-6)
        for idx in face_indices:
            for li in mesh.polygons[idx].loop_indices:
                uv = uv_data[li].uv
                uv.x = u_min + ((uv.x - cur_u0) / du) * (u_max - u_min)
                uv.y = v_min + ((uv.y - cur_v0) / dv) * (v_max - v_min)

    _unwrap_region(ext_faces, 0.015, EXT_SPLIT_U - 0.015, 0.015, 0.825)
    _unwrap_region(rim_faces, 0.015, EXT_SPLIT_U - 0.015, 0.845, 0.985)
    _unwrap_region(int_faces, EXT_SPLIT_U + 0.015, 0.985, 0.015, 0.985)

    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    min_z = min(zs)
    for v in mesh.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= min_z

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
        "prop_slug": "tilting_park_bin",
        "tri_count": tri_count,
        "uv_layers": len(mesh.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "ConvexPolygonShape3D",
        "generator": "procedural_bpy",
        "reference_image": REF_IMAGE,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_TILTING_PARK_BIN:", json.dumps(manifest, indent=2))


def main() -> None:
    if "--textures" in sys.argv:
        _generate_pbr_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
