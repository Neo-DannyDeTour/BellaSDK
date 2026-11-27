"""Procedural Firewood Stack with Split Bark-Edged Logs & Staggered Ends (0.95m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-10_19-24.png:
- Grounded min_y = 0.0 (bottom logs rest cleanly on floor)
- 1.45m wide x 0.95m tall x ~0.50m deep
- Neatly piled split quarter/half/round firewood logs with staggered ends
- 1024x1024 3-band wood PBR atlas: rough bark + split heartwood + concentric end-grain rings
- Single mesh, <= 1,600 tris

Usage:
    python3 tools/blender/props/firewood_stack.py --textures
    python3 tools/blender/run.py tools/blender/props/firewood_stack.py
"""

from __future__ import annotations

import json
import math
import random
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

SLUG: str = "firewood_stack"
MESH_NAME: str = "FirewoodStack"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / SLUG
GLB_PATH: Path = ASSET_DIR / f"{SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-10_19-24.png"

MAT_BARK: Path = REPO_ROOT / "assets" / "materials" / "overgrown_bark" / "textures"
MAT_WOOD: Path = REPO_ROOT / "assets" / "materials" / "roof_truss_timber" / "textures"

TEX_SIZE: int = 1024
# Atlas U bands:
# [0.0, 0.34): dark rough bark
# [0.34, 0.68): warm split heartwood sides
# [0.68, 1.0]: radial cut log end-grain rings
BARK_U_MAX: float = 0.34
SPLIT_U_MAX: float = 0.68

TARGET_W: float = 1.45
TARGET_H: float = 0.95


def _generate_pbr_textures() -> None:
    """Build 1024x1024 bark + split heartwood + concentric ring end-grain PBR atlas."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    u1_px = int(round(TEX_SIZE * BARK_U_MAX))
    u2_px = int(round(TEX_SIZE * SPLIT_U_MAX))
    bark_w = u1_px
    split_w = u2_px - u1_px
    end_w = TEX_SIZE - u2_px

    def _load_fit(path: Path, out_w: int, out_h: int, mode: str) -> np.ndarray:
        img = Image.open(path).convert(mode).resize((out_w, out_h), Image.Resampling.BICUBIC)
        return np.array(img, dtype=np.float32)

    # 1. Bark band (dark weathered brownish-grey bark, suppressing mossy green)
    bk_alb = _load_fit(MAT_BARK / "overgrown_bark_albedo.png", bark_w, TEX_SIZE, "RGB")
    bk_nrm = _load_fit(MAT_BARK / "overgrown_bark_normal.png", bark_w, TEX_SIZE, "RGB")
    bk_orm = _load_fit(MAT_BARK / "overgrown_bark_orm.png", bark_w, TEX_SIZE, "RGB")

    lum_bk = 0.299 * bk_alb[..., 0] + 0.587 * bk_alb[..., 1] + 0.114 * bk_alb[..., 2]
    bk_desat = np.stack([lum_bk * 0.92, lum_bk * 0.85, lum_bk * 0.78], axis=-1)
    bark_alb = 0.35 * bk_alb + 0.65 * bk_desat
    bark_alb *= 0.85
    bark_alb_img = Image.fromarray(np.clip(bark_alb, 30, 185).astype(np.uint8), mode="RGB")

    bnrm = bk_nrm / 255.0 * 2.0 - 1.0
    bnrm[..., 2] = np.maximum(bnrm[..., 2], 0.2)
    blen = np.sqrt(np.sum(bnrm * bnrm, axis=-1, keepdims=True))
    bnrm = bnrm / np.maximum(blen, 1e-6)
    bark_nrm_img = Image.fromarray(np.clip((bnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    bark_ao = np.clip(bk_orm[..., 0], 55, 255).astype(np.uint8)
    bark_rough = np.clip(bk_orm[..., 1], 195, 250).astype(np.uint8)

    # 2. Split heartwood side faces (warm weathered cut timber)
    sp_alb = _load_fit(MAT_WOOD / "roof_truss_timber_albedo.png", split_w, TEX_SIZE, "RGB")
    sp_nrm = _load_fit(MAT_WOOD / "roof_truss_timber_normal.png", split_w, TEX_SIZE, "RGB")
    sp_orm = _load_fit(MAT_WOOD / "roof_truss_timber_orm.png", split_w, TEX_SIZE, "RGB")

    sp_alb[..., 0] *= 1.15
    sp_alb[..., 1] *= 1.06
    sp_alb[..., 2] *= 0.90
    split_alb_img = Image.fromarray(np.clip(sp_alb, 45, 230).astype(np.uint8), mode="RGB")

    snrm = sp_nrm / 255.0 * 2.0 - 1.0
    snrm[..., 2] = np.maximum(snrm[..., 2], 0.3)
    slen = np.sqrt(np.sum(snrm * snrm, axis=-1, keepdims=True))
    snrm = snrm / np.maximum(slen, 1e-6)
    split_nrm_img = Image.fromarray(np.clip((snrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    split_ao = np.clip(sp_orm[..., 0], 70, 255).astype(np.uint8)
    split_rough = np.clip(sp_orm[..., 1], 165, 235).astype(np.uint8)

    # 3. Cut end-grain concentric growth rings (radial rings + pith + radial checks)
    yy, xx = np.mgrid[0:TEX_SIZE, 0:end_w].astype(np.float32)
    nx = (xx / float(end_w) - 0.5) * 2.0
    ny = (yy / float(TEX_SIZE) - 0.5) * 2.0
    r = np.sqrt(nx * nx + ny * ny)
    theta = np.arctan2(ny, nx)
    wobble = 0.045 * np.sin(theta * 3.0 + 0.7) + 0.025 * np.cos(theta * 5.0 - 1.2)
    rw = np.maximum(r + wobble, 0.0)

    ring_wave = 0.5 + 0.5 * np.sin(rw * 46.0)
    heart_darken = np.exp(-((rw / 0.24) ** 2)) * 0.24
    sap_fade = np.clip((rw - 0.55) * 0.35, 0.0, 0.14)
    # Subtle radial drying checks
    crack_a = np.exp(-(((theta - 0.4) * 14.0) ** 2)) * np.clip((0.55 - rw) * 2.0, 0.0, 1.0)
    crack_b = np.exp(-(((theta + 2.1) * 18.0) ** 2)) * np.clip((0.45 - rw) * 2.0, 0.0, 1.0)
    cracks = np.clip(crack_a + crack_b, 0.0, 1.0) * 0.38

    base_tone = 0.76 - 0.18 * ring_wave - heart_darken + sap_fade - cracks
    end_r = np.clip(base_tone * 212.0, 35, 235)
    end_g = np.clip(base_tone * 174.0, 32, 220)
    end_b = np.clip(base_tone * 132.0, 30, 195)
    end_alb_img = Image.fromarray(np.stack([end_r, end_g, end_b], axis=-1).astype(np.uint8), mode="RGB")

    # End-grain normal from rings + cracks
    end_h = np.clip(0.65 - 0.15 * ring_wave - cracks * 0.8, 0.0, 1.0)
    dx_e = np.gradient(end_h, axis=1) * 8.0
    dy_e = np.gradient(end_h, axis=0) * 8.0
    dz_e = np.ones_like(end_h)
    enorm = np.sqrt(dx_e * dx_e + dy_e * dy_e + dz_e * dz_e)
    enrm_rgb = np.zeros((TEX_SIZE, end_w, 3), dtype=np.uint8)
    enrm_rgb[..., 0] = np.clip(((dx_e / enorm) * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    enrm_rgb[..., 1] = np.clip(((-dy_e / enorm) * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    enrm_rgb[..., 2] = np.clip(((dz_e / enorm) * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    end_nrm_img = Image.fromarray(enrm_rgb, mode="RGB")

    end_ao = np.clip((0.88 - cracks * 0.55 - ring_wave * 0.08) * 255.0, 70, 255).astype(np.uint8)
    end_rough = np.clip((0.80 + cracks * 0.12 + ring_wave * 0.06) * 255.0, 175, 248).astype(np.uint8)

    def _stitch3(a: Image.Image, b: Image.Image, c: Image.Image, mode: str) -> Image.Image:
        canvas = Image.new(mode, (TEX_SIZE, TEX_SIZE))
        canvas.paste(a, (0, 0))
        canvas.paste(b, (u1_px, 0))
        canvas.paste(c, (u2_px, 0))
        return canvas

    albedo_atlas = _stitch3(bark_alb_img, split_alb_img, end_alb_img, "RGB")
    normal_atlas = _stitch3(bark_nrm_img, split_nrm_img, end_nrm_img, "RGB")
    ao_atlas = _stitch3(
        Image.fromarray(bark_ao, mode="L"),
        Image.fromarray(split_ao, mode="L"),
        Image.fromarray(end_ao, mode="L"),
        "L",
    )
    rough_atlas = _stitch3(
        Image.fromarray(bark_rough, mode="L"),
        Image.fromarray(split_rough, mode="L"),
        Image.fromarray(end_rough, mode="L"),
        "L",
    )

    ao_tmp = ASSET_DIR / "_tmp_ao.png"
    rough_tmp = ASSET_DIR / "_tmp_rough.png"
    albedo_atlas.save(ALBEDO_PATH, format="PNG")
    normal_atlas.save(NORMAL_PATH, format="PNG")
    ao_atlas.save(ao_tmp, format="PNG")
    rough_atlas.save(rough_tmp, format="PNG")

    process_pbr.pack_orm(ao_tmp, rough_tmp, "0.0", ORM_PATH, target_size=(TEX_SIZE, TEX_SIZE))
    ao_tmp.unlink(missing_ok=True)
    rough_tmp.unlink(missing_ok=True)

    process_pbr.generate_godot_tres(
        material_name=f"M_{MESH_NAME}",
        albedo_path=ALBEDO_PATH,
        normal_path=NORMAL_PATH,
        orm_path=ORM_PATH,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] Generated {TEX_SIZE}x{TEX_SIZE} maps + {TRES_PATH.name}")


def _build_mesh_and_export() -> None:
    """Build firewood_stack geometry in Blender, UV-map bark/split/end-grain, and export GLB."""
    import bmesh
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).resolve()), "--textures"],
            check=True,
        )

    clean_scene()
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    rng = random.Random(1924)

    def _assign_uv_band(face: bmesh.types.BMFace, band: int) -> None:
        """Map face loops cleanly into atlas band: 0=bark, 1=split, 2=end-grain."""
        if band == 0:
            u0, u1 = 0.02, BARK_U_MAX - 0.02
        elif band == 1:
            u0, u1 = BARK_U_MAX + 0.02, SPLIT_U_MAX - 0.02
        else:
            u0, u1 = SPLIT_U_MAX + 0.02, 0.98

        if band == 2:
            # End-grain cap: project X-Z into centered radial ring disk
            xs = [v.co.x for v in face.verts]
            zs = [v.co.z for v in face.verts]
            cx = (min(xs) + max(xs)) * 0.5
            cz = (min(zs) + max(zs)) * 0.5
            rad = max(max(max(xs) - min(xs), max(zs) - min(zs)) * 0.55, 0.03)
            u_mid = (u0 + u1) * 0.5
            u_half = (u1 - u0) * 0.45
            v_mid = 0.5
            v_half = 0.42
            for loop in face.loops:
                dx = (loop.vert.co.x - cx) / rad
                dz = (loop.vert.co.z - cz) / rad
                loop[uv_layer].uv = (
                    max(u0, min(u1, u_mid + dx * u_half)),
                    max(0.03, min(0.97, v_mid + dz * v_half)),
                )
        else:
            # Side face (bark or split wood): map perimeter arc/length along U, log Y along V
            ys = [v.co.y for v in face.verts]
            y0, y1 = min(ys), max(ys)
            dy = max(y1 - y0, 0.05)
            # Use local tangent around face center for U spread
            coords = [v.co for v in face.verts]
            xs = [c.x for c in coords]
            zs = [c.z for c in coords]
            span_xz = [math.hypot(c.x - xs[0], c.z - zs[0]) for c in coords]
            max_s = max(max(span_xz), 0.03)
            for loop, s in zip(face.loops, span_xz):
                u_frac = s / max_s
                v_frac = (loop.vert.co.y - y0) / dy
                loop[uv_layer].uv = (
                    u0 + u_frac * (u1 - u0),
                    0.04 + v_frac * 0.92,
                )

    def add_split_log(
        cx: float,
        cz_bottom: float,
        y0: float,
        y1: float,
        width: float,
        height: float,
        kind: str,
        flip: bool,
    ) -> None:
        """Create a split or round firewood log along Y, resting at cz_bottom.

        kind: 'wedge' (quarter-split), 'half' (half-round), 'round' (full log).
        """
        profile_xz: list[tuple[float, float, int]] = []  # (x, z, band_for_edge_i_to_i+1)
        hw = width * 0.5

        if kind == "round":
            # 7-sided slightly irregular cylinder
            r_x = hw
            r_z = height * 0.5
            cz = cz_bottom + r_z
            n_seg = 7
            for k in range(n_seg):
                ang = (2.0 * math.pi * k) / n_seg + rng.uniform(-0.08, 0.08)
                jit = rng.uniform(0.92, 1.06)
                profile_xz.append((cx + math.cos(ang) * r_x * jit, cz + math.sin(ang) * r_z * jit, 0))
        elif kind == "half":
            # Flat split bottom (or top if flip), 4-segment curved bark arc
            arc_n = 4
            if not flip:
                # Flat at bottom z=cz_bottom, curved bark arch on top
                pts = [(-hw, 0.0)]
                for k in range(1, arc_n):
                    ang = math.pi * (1.0 - float(k) / arc_n)
                    pts.append((math.cos(ang) * hw, math.sin(ang) * height))
                pts.append((+hw, 0.0))
                # Winding: CCW in X-Z so normals face outward
                # Order: (-hw,0) -> (+hw,0) -> arc right-to-left
                profile_xz.append((cx - hw, cz_bottom, 1))  # flat split bottom
                for k in range(arc_n, 0, -1):
                    ang = math.pi * (1.0 - float(k) / arc_n)
                    px = cx + math.cos(ang) * hw
                    pz = cz_bottom + math.sin(ang) * height
                    profile_xz.append((px, pz, 0))
            else:
                # Flat split top, curved bark belly resting at cz_bottom
                profile_xz.append((cx - hw, cz_bottom + height, 0))
                for k in range(1, arc_n):
                    ang = math.pi + math.pi * (float(k) / arc_n)
                    px = cx + math.cos(ang) * hw
                    pz = cz_bottom + height + math.sin(ang) * height
                    profile_xz.append((px, pz, 0))
                profile_xz.append((cx + hw, cz_bottom + height, 1))
        else:
            # 'wedge': quarter-split log (flat base + angled split side + curved bark face)
            if not flip:
                # Apex left, curved bark right-top
                profile_xz = [
                    (cx - hw, cz_bottom, 1),
                    (cx + hw * 0.92, cz_bottom, 0),
                    (cx + hw * 0.85, cz_bottom + height * 0.55, 0),
                    (cx + hw * 0.35, cz_bottom + height, 1),
                ]
            else:
                # Apex right, curved bark left-top
                profile_xz = [
                    (cx - hw * 0.92, cz_bottom, 1),
                    (cx + hw, cz_bottom, 1),
                    (cx - hw * 0.35, cz_bottom + height, 0),
                    (cx - hw * 0.85, cz_bottom + height * 0.55, 0),
                ]

        # Shift profile so its exact min z equals cz_bottom
        min_pz = min(p[1] for p in profile_xz)
        dz_fix = cz_bottom - min_pz

        front_verts: list[bmesh.types.BMVert] = []
        back_verts: list[bmesh.types.BMVert] = []
        for px, pz, _ in profile_xz:
            front_verts.append(bm.verts.new((px, y0 + rng.uniform(-0.006, 0.006), pz + dz_fix)))
            back_verts.append(bm.verts.new((px, y1 + rng.uniform(-0.006, 0.006), pz + dz_fix)))

        f_cap = bm.faces.new(front_verts)
        _assign_uv_band(f_cap, 2)
        b_cap = bm.faces.new(list(reversed(back_verts)))
        _assign_uv_band(b_cap, 2)

        n_v = len(profile_xz)
        for i in range(n_v):
            j = (i + 1) % n_v
            band = profile_xz[i][2]
            side_f = bm.faces.new((front_verts[i], back_verts[i], back_verts[j], front_verts[j]))
            _assign_uv_band(side_f, band)

    # Stack logs in 7 overlapping rows matching ref (1.45m wide x 0.95m tall, tapered top)
    # Row specs: (z_base, x_left, x_right, avg_log_h, log_count, round_chance)
    rows = [
        (0.000, -0.725, +0.725, 0.145, 9, 0.05),
        (0.132, -0.690, +0.715, 0.150, 8, 0.05),
        (0.268, -0.650, +0.700, 0.155, 8, 0.10),
        (0.405, -0.575, +0.675, 0.150, 7, 0.12),
        (0.538, -0.420, +0.640, 0.148, 6, 0.18),
        (0.668, -0.180, +0.580, 0.145, 4, 0.30),
        (0.798, +0.100, +0.490, 0.152, 2, 0.75),
    ]

    for row_idx, (z_base, x0, x1, row_h, count, round_prob) in enumerate(rows):
        span = x1 - x0
        cell_w = span / float(count)
        for idx in range(count):
            cx = x0 + (idx + 0.5) * cell_w + rng.uniform(-0.012, 0.012)
            lw = cell_w * rng.uniform(0.88, 1.02)
            lh = row_h * rng.uniform(0.90, 1.06)
            if row_idx == len(rows) - 1 and idx == count - 1:
                # Top crown log hits exact 0.95m height target
                lh = TARGET_H - z_base
            # Staggered Y ends matching rustic split firewood stack
            y_shift = rng.uniform(-0.045, 0.045)
            log_len = rng.uniform(0.40, 0.48)
            y0 = -log_len * 0.5 + y_shift
            y1 = +log_len * 0.5 + y_shift

            r_roll = rng.random()
            if r_roll < round_prob:
                kind = "round"
            elif r_roll < round_prob + 0.42:
                kind = "half"
            else:
                kind = "wedge"
            flip = rng.random() < 0.45
            z_bot = 0.0 if row_idx == 0 else z_base + rng.uniform(-0.008, 0.006)
            add_split_log(cx, z_bot, y0, y1, lw, lh, kind, flip)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new(MESH_NAME)
    bm.to_mesh(mesh)
    bm.free()

    mat = bpy.data.materials.new(name=f"M_{MESH_NAME}")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    img_alb = bpy.data.images.load(str(ALBEDO_PATH.resolve()), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    img_orm = bpy.data.images.load(str(ORM_PATH.resolve()), check_existing=True)
    img_orm.colorspace_settings.name = "Non-Color"
    tex_orm.image = img_orm
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    img_nrm = bpy.data.images.load(str(NORMAL_PATH.resolve()), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.inputs["Strength"].default_value = 0.9
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new(MESH_NAME, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Normalize exact height = 0.95m, width ~1.45m, center X/Y=0, min_z=0.0
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    cur_w = max(xs) - min(xs)
    cur_h = max(zs) - min(zs)
    sx = TARGET_W / cur_w
    sz = TARGET_H / cur_h
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    z0 = min(zs)
    for v in mesh.vertices:
        v.co.x = (v.co.x - cx) * sx
        v.co.y = v.co.y - cy
        v.co.z = (v.co.z - z0) * sz
    mesh.update()

    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

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
        "prop_slug": SLUG,
        "tri_count": tri_count,
        "tri_budget": 1600,
        "uv_layers": len(mesh.uv_layers),
        "min_y": round(min(zs), 4),
        "dimensions_m": dims_godot,
        "layer": "Layer 1 Environment",
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "ref_image": REF_IMAGE,
        "reference_image": REF_IMAGE,
        "material": f"res://assets/models/{SLUG}/{SLUG}.tres",
        "mesh": f"res://assets/models/{SLUG}/{SLUG}.glb",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"BUILT_{SLUG.upper()}:", json.dumps(manifest, indent=2))


def main() -> None:
    if "--textures" in sys.argv:
        _generate_pbr_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
