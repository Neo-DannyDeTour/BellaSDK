"""Procedural Soviet Wooden Kitchen Chair with Woven Seat Pad (0.86m H).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-10-29_18-24_1.png
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-31_2.png

Features:
- 4 splayed tapered wooden legs (rear legs rise into canted backrest stiles, min_y = 0)
- Lower 4-bar H-stretcher rungs & beveled seat apron frame
- Slightly recessed pale woven cane/canvas seat insert
- Arched backrest crest rail + slender horizontal mid-rail
- 2048x2048 PBR atlas (weathered warm walnut/oak wood + stained woven seat pad)

Usage:
    .venv/bin/python tools/blender/props/soviet_wooden_chair.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/soviet_wooden_chair.py
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

PROP_SLUG: str = "soviet_wooden_chair"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = TEX_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = TEX_DIR / f"{PROP_SLUG}_orm.png"

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-29_18-24_1.png"
TARGET_HEIGHT_M: float = 0.86
TRI_BUDGET: int = 1400

SRC_WOOD_DIR: Path = REPO_ROOT / "assets" / "materials" / "roof_truss_timber" / "textures"
SRC_TICKING_DIR: Path = REPO_ROOT / "assets" / "materials" / "stained_mattress_ticking" / "textures"

TEX_SIZE: int = 2048


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def generate_textures() -> None:
    """Generate 2048x2048 weathered dark oak/walnut wood + woven seat pad atlas."""
    import numpy as np
    from PIL import Image, ImageFilter

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2

    src_wood_alb = _load_square_rgb(SRC_WOOD_DIR / "roof_truss_timber_albedo.png", half)
    src_wood_nrm = _load_square_rgb(SRC_WOOD_DIR / "roof_truss_timber_normal.png", half)
    src_mat_alb = _load_square_rgb(SRC_TICKING_DIR / "stained_mattress_ticking_albedo.png", half)
    src_mat_nrm = _load_square_rgb(SRC_TICKING_DIR / "stained_mattress_ticking_normal.png", half)

    # 1. Weathered warm cherry-walnut stained wood (Left half: U in [0.0, 0.5])
    wood_lum = 0.299 * src_wood_alb[..., 0] + 0.587 * src_wood_alb[..., 1] + 0.114 * src_wood_alb[..., 2]
    wood_low = np.asarray(
        Image.fromarray(np.clip(wood_lum, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=14)
        ),
        dtype=np.float32,
    )
    wood_hp = np.clip(wood_lum - wood_low, -24.0, 22.0)

    warm_walnut = np.array([104.0, 62.0, 38.0], dtype=np.float32)
    wood_half_alb = warm_walnut[None, None, :] * 0.72 + src_wood_alb * 0.28 + wood_hp[..., None] * 0.58
    wood_alb = np.concatenate([wood_half_alb, wood_half_alb], axis=0)
    wood_nrm_half = (src_wood_nrm - 128.0) * 0.60 + 128.0
    wood_nrm = np.concatenate([wood_nrm_half, wood_nrm_half], axis=0)
    wood_rough_half = np.clip(0.58 - wood_hp * 0.004, 0.44, 0.80)
    wood_rough = np.concatenate([wood_rough_half, wood_rough_half], axis=0)
    wood_ao_half = np.clip(0.88 + wood_hp * 0.003, 0.55, 1.0)
    wood_ao = np.concatenate([wood_ao_half, wood_ao_half], axis=0)

    # 2. Woven pale-tan/cream cane-canvas seat pad (Right half: U in [0.5, 1.0])
    yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
    cane_weave = 0.5 + 0.5 * np.sin(xx * 0.35) * np.sin(yy * 0.35)
    mat_lum = 0.299 * src_mat_alb[..., 0] + 0.587 * src_mat_alb[..., 1] + 0.114 * src_mat_alb[..., 2]
    seat_base = np.array([164.0, 148.0, 118.0], dtype=np.float32)
    seat_half_alb = seat_base[None, None, :] * 0.68 + src_mat_alb * 0.32 + (cane_weave - 0.5)[..., None] * 22.0
    # Subtle center wear darkening
    dist_c = np.sqrt(((xx / half) - 0.5) ** 2 + ((yy / half) - 0.5) ** 2)
    seat_half_alb *= (1.0 - np.clip(0.35 - dist_c, 0.0, 0.35)[..., None] * 0.32)

    seat_alb = np.concatenate([seat_half_alb, seat_half_alb], axis=0)
    seat_nrm_half = (src_mat_nrm - 128.0) * 0.55 + 128.0
    seat_nrm_half[..., 0] += np.cos(xx * 0.35) * 18.0
    seat_nrm_half[..., 1] += np.cos(yy * 0.35) * 18.0
    seat_nrm = np.concatenate([seat_nrm_half, seat_nrm_half], axis=0)
    seat_rough_half = np.clip(0.84 - (cane_weave - 0.5) * 0.06, 0.72, 0.96)
    seat_rough = np.concatenate([seat_rough_half, seat_rough_half], axis=0)
    seat_ao_half = np.clip(0.86 + (mat_lum / 255.0) * 0.14 - (1.0 - cane_weave) * 0.10, 0.55, 1.0)
    seat_ao = np.concatenate([seat_ao_half, seat_ao_half], axis=0)

    alb_full = np.concatenate([wood_alb, seat_alb], axis=1)
    nrm_full = np.concatenate([wood_nrm, seat_nrm], axis=1)
    rough_full = np.concatenate([wood_rough, seat_rough], axis=1)
    ao_full = np.concatenate([wood_ao, seat_ao], axis=1)

    nrm_v = (nrm_full / 255.0) * 2.0 - 1.0
    nrm_v[..., 2] = np.maximum(nrm_v[..., 2], 0.30)
    nrm_l = np.sqrt(np.sum(nrm_v * nrm_v, axis=-1, keepdims=True))
    nrm_v /= np.maximum(nrm_l, 1e-6)
    nrm_u8 = np.clip((nrm_v * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)

    Image.fromarray(np.clip(alb_full, 30.0, 240.0).astype(np.uint8), mode="RGB").save(ALBEDO_PATH, format="PNG")
    Image.fromarray(nrm_u8, mode="RGB").save(NORMAL_PATH, format="PNG")

    ao_tmp = TEX_DIR / "_tmp_ao.png"
    rough_tmp = TEX_DIR / "_tmp_rough.png"
    Image.fromarray(np.clip(ao_full * 255.0, 0, 255).astype(np.uint8), mode="L").save(ao_tmp, format="PNG")
    Image.fromarray(np.clip(rough_full * 255.0, 0, 255).astype(np.uint8), mode="L").save(rough_tmp, format="PNG")

    process_pbr.pack_orm(ao_tmp, rough_tmp, "0.0", ORM_PATH, target_size=(TEX_SIZE, TEX_SIZE))
    ao_tmp.unlink(missing_ok=True)
    rough_tmp.unlink(missing_ok=True)

    process_pbr.generate_godot_tres(
        material_name="M_SovietWoodenChair",
        albedo_path=ALBEDO_PATH,
        normal_path=NORMAL_PATH,
        orm_path=ORM_PATH,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] Generated {PROP_SLUG} 2048x2048 PBR maps + {TRES_PATH.name}")


def _build_mesh_and_export() -> None:
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).resolve()), "--gen-textures"],
            check=True,
        )

    clean_scene()
    bm = bmesh.new()

    def _tag_verts(verts: list[bmesh.types.BMVert], region: int, smooth: bool = False) -> None:
        vset = set(verts)
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = region
                f.smooth = smooth

    def add_tapered_beam(
        p0: Vector,
        p1: Vector,
        w0: float,
        d0: float,
        w1: float,
        d1: float,
        region: int,
    ) -> None:
        delta = p1 - p0
        length = delta.length
        if length < 1e-5:
            return
        z_axis = delta.normalized()
        up_ref = Vector((0.0, 1.0, 0.0)) if abs(z_axis.y) < 0.9 else Vector((1.0, 0.0, 0.0))
        x_axis = up_ref.cross(z_axis).normalized()
        y_axis = z_axis.cross(x_axis).normalized()

        def _ring(pt: Vector, w: float, d: float) -> list[bmesh.types.BMVert]:
            hw, hd = w * 0.5, d * 0.5
            return [
                bm.verts.new(pt - x_axis * hw - y_axis * hd),
                bm.verts.new(pt + x_axis * hw - y_axis * hd),
                bm.verts.new(pt + x_axis * hw + y_axis * hd),
                bm.verts.new(pt - x_axis * hw + y_axis * hd),
            ]

        r0 = _ring(p0, w0, d0)
        r1 = _ring(p1, w1, d1)
        faces = [bm.faces.new(list(reversed(r0))), bm.faces.new(r1)]
        for i in range(4):
            j = (i + 1) % 4
            faces.append(bm.faces.new((r0[i], r0[j], r1[j], r1[i])))
        for f in faces:
            f.material_index = region
            f.smooth = False

    def add_box(center: Vector, size: Vector, region: int, bevel_w: float = 0.0) -> None:
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        xform = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        _tag_verts(verts, region, smooth=False)
        if bevel_w > 0.0:
            vset = set(verts)
            edges = [e for e in bm.edges if all(v in vset for v in e.verts)]
            bev = bmesh.ops.bevel(
                bm,
                geom=edges,
                offset=bevel_w,
                offset_type="OFFSET",
                segments=1,
                profile=0.5,
                affect="EDGES",
                clamp_overlap=True,
            )
            for f in bev.get("faces", []):
                f.material_index = region
                f.smooth = False

    # Chair geometry (Blender Z-up, front facing -Y, backrest at +Y)
    seat_z = 0.435
    seat_w = 0.42
    seat_d = 0.41
    hw = seat_w * 0.5
    hd = seat_d * 0.5

    # 4 splayed legs (front legs stop at seat_z; rear legs rise to 0.86m backrest)
    fl_bot = Vector((-hw - 0.015, -hd - 0.012, 0.0))
    fl_top = Vector((-hw + 0.018, -hd + 0.018, seat_z))
    fr_bot = Vector((+hw + 0.015, -hd - 0.012, 0.0))
    fr_top = Vector((+hw - 0.018, -hd + 0.018, seat_z))

    rl_bot = Vector((-hw + 0.004, +hd + 0.018, 0.0))
    rl_seat = Vector((-hw + 0.018, +hd - 0.018, seat_z))
    rl_top = Vector((-hw + 0.022, +hd + 0.042, TARGET_HEIGHT_M))

    rr_bot = Vector((+hw - 0.004, +hd + 0.018, 0.0))
    rr_seat = Vector((+hw - 0.018, +hd - 0.018, seat_z))
    rr_top = Vector((+hw - 0.022, +hd + 0.042, TARGET_HEIGHT_M))

    # Region 0: Weathered wood frame
    add_tapered_beam(fl_bot, fl_top, 0.024, 0.024, 0.032, 0.032, region=0)
    add_tapered_beam(fr_bot, fr_top, 0.024, 0.024, 0.032, 0.032, region=0)
    add_tapered_beam(rl_bot, rl_seat, 0.024, 0.024, 0.032, 0.032, region=0)
    add_tapered_beam(rr_bot, rr_seat, 0.024, 0.024, 0.032, 0.032, region=0)
    # Upper backrest stiles
    add_tapered_beam(rl_seat, rl_top, 0.032, 0.028, 0.026, 0.024, region=0)
    add_tapered_beam(rr_seat, rr_top, 0.032, 0.028, 0.026, 0.024, region=0)

    # Lower H-stretcher rungs (~0.15m height)
    def _lerp(a: Vector, b: Vector, t: float) -> Vector:
        return a + (b - a) * t

    t_rung = 0.36
    add_tapered_beam(_lerp(fl_bot, fl_top, t_rung), _lerp(rl_bot, rl_seat, t_rung), 0.018, 0.018, 0.018, 0.018, region=0)
    add_tapered_beam(_lerp(fr_bot, fr_top, t_rung), _lerp(rr_bot, rr_seat, t_rung), 0.018, 0.018, 0.018, 0.018, region=0)
    add_tapered_beam(_lerp(fl_bot, fl_top, 0.44), _lerp(fr_bot, fr_top, 0.44), 0.018, 0.018, 0.018, 0.018, region=0)
    add_tapered_beam(_lerp(rl_bot, rl_seat, 0.32), _lerp(rr_bot, rr_seat, 0.32), 0.018, 0.018, 0.018, 0.018, region=0)

    # Seat apron frame rails
    apron_h = 0.044
    apron_z = seat_z - apron_h * 0.5 + 0.002
    add_box(Vector((0.0, -hd + 0.018, apron_z)), Vector((seat_w - 0.036, 0.024, apron_h)), region=0, bevel_w=0.002)
    add_box(Vector((0.0, +hd - 0.018, apron_z)), Vector((seat_w - 0.036, 0.024, apron_h)), region=0, bevel_w=0.002)
    add_box(Vector((-hw + 0.018, 0.0, apron_z)), Vector((0.024, seat_d - 0.036, apron_h)), region=0, bevel_w=0.002)
    add_box(Vector((+hw - 0.018, 0.0, apron_z)), Vector((0.024, seat_d - 0.036, apron_h)), region=0, bevel_w=0.002)

    # Backrest arched top crest rail (4 segments for slight curve & top crest arch matching HL2 chair)
    t_mid = 0.36
    add_tapered_beam(_lerp(rl_seat, rl_top, t_mid), _lerp(rr_seat, rr_top, t_mid), 0.020, 0.024, 0.020, 0.024, region=0)

    crest_pts_x = [-hw + 0.022, -0.095, 0.0, 0.095, +hw - 0.022]
    crest_z_bot = 0.725
    crest_z_tops = [0.835, 0.852, 0.858, 0.852, 0.835]
    crest_ys = [hd + 0.036, hd + 0.046, hd + 0.050, hd + 0.046, hd + 0.036]
    crest_t = 0.018
    c_rings: list[list[bmesh.types.BMVert]] = []
    for cx, cy, zt in zip(crest_pts_x, crest_ys, crest_z_tops):
        c_rings.append([
            bm.verts.new((cx, cy - crest_t * 0.5, crest_z_bot)),
            bm.verts.new((cx, cy + crest_t * 0.5, crest_z_bot)),
            bm.verts.new((cx, cy + crest_t * 0.5, zt)),
            bm.verts.new((cx, cy - crest_t * 0.5, zt)),
        ])
    c_faces: list[bmesh.types.BMFace] = [
        bm.faces.new(list(reversed(c_rings[0]))),
        bm.faces.new(c_rings[-1]),
    ]
    for i in range(len(c_rings) - 1):
        for k in range(4):
            kn = (k + 1) % 4
            c_faces.append(bm.faces.new((c_rings[i][k], c_rings[i][kn], c_rings[i + 1][kn], c_rings[i + 1][k])))
    for f in c_faces:
        f.material_index = 0
        f.smooth = False

    # Region 1: Woven seat pad insert resting cleanly on top of seat frame
    add_box(Vector((0.0, 0.0, seat_z + 0.008)), Vector((seat_w - 0.048, seat_d - 0.048, 0.022)), region=1, bevel_w=0.004)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("SovietWoodenChair")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(2):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))

    obj = bpy.data.objects.new("SovietWoodenChair", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")
    uv_regions = {
        0: (0.015, 0.485, 0.015, 0.985),
        1: (0.515, 0.985, 0.015, 0.985),
    }
    for region_id, (u0, u1, v0, v1) in uv_regions.items():
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for poly in mesh.polygons:
            if poly.material_index == region_id:
                poly.select = True
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015)
        bpy.ops.object.mode_set(mode="OBJECT")

        uv_data = mesh.uv_layers.active.data
        u_vals: list[float] = []
        v_vals: list[float] = []
        for poly in mesh.polygons:
            if poly.material_index != region_id:
                continue
            for li in poly.loop_indices:
                uv = uv_data[li].uv
                u_vals.append(uv.x)
                v_vals.append(uv.y)
        cur_u0, cur_u1 = min(u_vals), max(u_vals)
        cur_v0, cur_v1 = min(v_vals), max(v_vals)
        du = max(cur_u1 - cur_u0, 1e-6)
        dv = max(cur_v1 - cur_v0, 1e-6)
        for poly in mesh.polygons:
            if poly.material_index != region_id:
                continue
            for li in poly.loop_indices:
                uv = uv_data[li].uv
                uv.x = u0 + ((uv.x - cur_u0) / du) * (u1 - u0)
                uv.y = v0 + ((uv.y - cur_v0) / dv) * (v1 - v0)

    for poly in mesh.polygons:
        poly.material_index = 0

    mat = bpy.data.materials.new(name="M_SovietWoodenChair")
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

    mesh.materials.clear()
    mesh.materials.append(mat)

    coords = [v.co for v in mesh.vertices]
    min_x, max_x = min(c.x for c in coords), max(c.x for c in coords)
    min_y, max_y = min(c.y for c in coords), max(c.y for c in coords)
    min_z, max_z = min(c.z for c in coords), max(c.z for c in coords)
    scale_f = TARGET_HEIGHT_M / max(max_z - min_z, 1e-5)
    cx = 0.5 * (min_x + max_x)
    cy = 0.5 * (min_y + max_y)
    for v in mesh.vertices:
        v.co.x = (v.co.x - cx) * scale_f
        v.co.y = (v.co.y - cy) * scale_f
        v.co.z = (v.co.z - min_z) * scale_f
    mesh.update()

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

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
        "min_y": round(min(zs), 4),
        "dimensions_m": dims_godot,
        "layer": "Layer 3 Interactive",
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "compound BoxShape3D (seat + backrest)",
        "generator": "procedural_bpy",
        "ref_image": REF_IMAGE,
        "reference_image": REF_IMAGE,
        "material": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres",
        "mesh": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[OK] {PROP_SLUG}: tris={tri_count}/{TRI_BUDGET}, dims_m={dims_godot}, uv_layers={len(mesh.uv_layers)}")


def main() -> None:
    if "--gen-textures" in sys.argv:
        generate_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
