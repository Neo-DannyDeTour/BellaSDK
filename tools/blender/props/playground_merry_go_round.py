"""Procedural Soviet Courtyard Roundabout / Merry-Go-Round (0.95m H, ~2.20m Dia).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-29_3.png:
- RoundaboutBase: grounded concrete footing pad (min_y = 0) + central steel bearing pedestal
- RoundaboutDeck: pivot centered on vertical spin axis (0, 0.14, 0 in Godot), circular rimmed
  diamond-plate deck with weathered red/yellow quadrant paint, central bearing cap, 2 opposing
  tubular steel safety railing bays with red/white striped diagonal handrails, and 2 wooden benches
- 2048x2048 PBR atlas (red/yellow painted diamond-plate steel + olive pipe + striped rails + wood)

Usage:
    /usr/bin/python3 tools/blender/props/playground_merry_go_round.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/playground_merry_go_round.py
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

from tools.blender.common.street_prop import (  # noqa: E402
    TEX_SIZE,
    TILE,
    Builder,
    _fbm,
    _streaks,
)

PROP_SLUG: str = "playground_merry_go_round"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-29_3.png"

MAT_DIAMOND: Path = REPO_ROOT / "assets" / "materials" / "steel_diamond_plate" / "textures"
MAT_WOOD: Path = REPO_ROOT / "assets" / "materials" / "weathered_deck_planks" / "textures"
MAT_RUST: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TARGET_H: float = 0.95
DECK_RADIUS: float = 1.10   # 2.20m diameter
DECK_PIVOT_Z: float = 0.140
TRI_BUDGET: int = 2000


def _load_tiled_rgb(path: Path, tiles: float, out_size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    src = Image.open(path).convert("RGB")
    sw, sh = src.size
    rep = max(1, int(math.ceil(tiles)))
    tiled = Image.new("RGB", (sw * rep, sh * rep))
    for iy in range(rep):
        for ix in range(rep):
            tiled.paste(src, (ix * sw, iy * sh))
    cropped = tiled.crop((0, 0, max(1, int(round(sw * tiles))), max(1, int(round(sh * tiles)))))
    return np.asarray(cropped.resize((out_size, out_size), Image.Resampling.BICUBIC), dtype=np.float32)


def _load_tiled_l(path: Path, tiles: float, out_size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    src = Image.open(path).convert("L")
    sw, sh = src.size
    rep = max(1, int(math.ceil(tiles)))
    tiled = Image.new("L", (sw * rep, sh * rep))
    for iy in range(rep):
        for ix in range(rep):
            tiled.paste(src, (ix * sw, iy * sh))
    cropped = tiled.crop((0, 0, max(1, int(round(sw * tiles))), max(1, int(round(sh * tiles)))))
    return np.asarray(cropped.resize((out_size, out_size), Image.Resampling.BICUBIC), dtype=np.float32) / 255.0


def _generate_textures() -> None:
    """Build 2048x2048 diamond-plate quadrant deck + striped rail + wood bench PBR atlas."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(18293)

    alb_a = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    nrm_a = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    rgh_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    met_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    ao_a = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)

    def _put_tile(region: int, alb: np.ndarray, nrm: np.ndarray, rgh: np.ndarray, met: np.ndarray, ao: np.ndarray) -> None:
        col, row = region % 2, region // 2
        x0, y0 = col * TILE, (1 - row) * TILE
        sl = (slice(y0, y0 + TILE), slice(x0, x0 + TILE))
        alb_a[sl] = np.clip(alb, 30, 240)
        nrm_a[sl] = np.clip(nrm, 0, 255)
        rgh_a[sl] = np.clip(rgh, 0.25, 0.96)
        met_a[sl] = np.clip(met, 0.0, 1.0)
        ao_a[sl] = np.clip(ao, 0.35, 1.0)

    # Tile 0: Quadrant diamond-plate steel deck (faded Soviet red vs dirty ochre-yellow quarters)
    dp_alb = _load_tiled_rgb(MAT_DIAMOND / "steel_diamond_plate_albedo.png", 3.0, TILE)
    dp_nrm = _load_tiled_rgb(MAT_DIAMOND / "steel_diamond_plate_normal.png", 3.0, TILE)
    dp_ao = _load_tiled_l(MAT_DIAMOND / "steel_diamond_plate_ao.png", 3.0, TILE)
    dp_rgh = _load_tiled_l(MAT_DIAMOND / "steel_diamond_plate_roughness.png", 3.0, TILE)
    rs_alb = _load_tiled_rgb(MAT_RUST / "rusted_steel_albedo.png", 2.0, TILE)
    rs_nrm = _load_tiled_rgb(MAT_RUST / "rusted_steel_normal.png", 2.0, TILE)
    rs_ao = _load_tiled_l(MAT_RUST / "rusted_steel_ao.png", 2.0, TILE)
    rs_rgh = _load_tiled_l(MAT_RUST / "rusted_steel_roughness.png", 2.0, TILE)

    yy, xx = np.mgrid[0:TILE, 0:TILE].astype(np.float32)
    xn = xx / float(TILE) - 0.5
    yn = yy / float(TILE) - 0.5
    rad = np.sqrt(xn * xn + yn * yn)
    quad_red = ((xn * yn) >= 0.0)
    m_deck = _fbm(rng, TILE, TILE, cells=(6, 18, 48, 120), weights=(0.4, 0.3, 0.2, 0.1))

    red_paint = np.array([128.0, 58.0, 48.0], dtype=np.float32)
    yel_paint = np.array([154.0, 138.0, 96.0], dtype=np.float32)
    quad_col = np.where(quad_red[..., None], red_paint[None, None, :], yel_paint[None, None, :])
    dp_lum = (0.299 * dp_alb[..., 0] + 0.587 * dp_alb[..., 1] + 0.114 * dp_alb[..., 2]) / 255.0
    deck_alb = quad_col * (0.65 + 0.55 * dp_lum)[..., None] * (0.82 + 0.28 * m_deck)[..., None]
    # Heavy rust wear near rim and center hub
    wear_ring = np.clip((rad - 0.39) / 0.08, 0.0, 1.0) + np.clip((0.10 - rad) / 0.05, 0.0, 1.0)
    wear_mask = np.clip(wear_ring * 0.65 + np.clip((m_deck - 0.60) / 0.18, 0.0, 1.0) * 0.65, 0.0, 0.85)
    deck_alb = deck_alb * (1.0 - wear_mask[..., None]) + rs_alb * wear_mask[..., None]
    deck_rgh = np.clip(0.55 + 0.25 * dp_rgh + 0.15 * wear_mask, 0.40, 0.92)
    deck_met = np.clip(0.28 + 0.35 * dp_lum * 0.4 + 0.25 * wear_mask, 0.15, 0.72)
    _put_tile(0, deck_alb, dp_nrm, deck_rgh, deck_met, np.clip(dp_ao * 0.9, 0.45, 1.0))

    # Tile 1: Weathered olive-gray tubular steel (railing hoops, base spindle, deck rim)
    m1 = _fbm(rng, TILE, TILE)
    m2 = _fbm(rng, TILE, TILE, cells=(10, 40, 140, 280), weights=(0.3, 0.3, 0.25, 0.15))
    rail_col = np.array([124.0, 128.0, 112.0], dtype=np.float32)
    rail_alb = rail_col[None, None, :] * (0.76 + 0.38 * m1)[..., None]
    rust_m = np.clip((m2 - 0.65) / 0.10, 0.0, 1.0)
    rail_alb = rail_alb * (1.0 - 0.7 * rust_m[..., None]) + rs_alb * (0.7 * rust_m[..., None])
    rail_rgh = np.clip(0.52 + 0.24 * (m1 - 0.5) + 0.20 * rust_m, 0.38, 0.90)
    rail_met = np.clip(0.25 + 0.30 * rust_m, 0.15, 0.60)
    _put_tile(1, rail_alb, rs_nrm, rail_rgh, rail_met, rs_ao)

    # Tile 2: Red & weathered off-white hazard striped diagonal handrail + rusty concrete base
    # Diagonal stripes along U+V
    stripe = np.sin((xx + yy) * 2.0 * math.pi / 140.0) > 0.0
    stripe_red = np.array([156.0, 56.0, 42.0], dtype=np.float32)
    stripe_wht = np.array([168.0, 162.0, 146.0], dtype=np.float32)
    st_alb = np.where(stripe[..., None], stripe_red[None, None, :], stripe_wht[None, None, :])
    st_alb = st_alb * (0.78 + 0.30 * m1)[..., None]
    st_alb = st_alb * (1.0 - 0.45 * rust_m[..., None]) + rs_alb * (0.45 * rust_m[..., None])
    _put_tile(2, st_alb, rs_nrm, np.clip(0.50 + 0.25 * m2, 0.38, 0.88), np.full((TILE, TILE), 0.22, np.float32), rs_ao)

    # Tile 3: Weathered wood plank bench seats + dark base hub
    wd_alb = _load_tiled_rgb(MAT_WOOD / "weathered_deck_planks_albedo.png", 1.2, TILE)
    wd_nrm = _load_tiled_rgb(MAT_WOOD / "weathered_deck_planks_normal.png", 1.2, TILE)
    wd_ao = _load_tiled_l(MAT_WOOD / "weathered_deck_planks_ao.png", 1.2, TILE)
    wd_rgh = _load_tiled_l(MAT_WOOD / "weathered_deck_planks_roughness.png", 1.2, TILE)
    grain = _streaks(rng, TILE, TILE, cy=80, cx=5)
    bench_alb = wd_alb * np.array([0.92, 0.86, 0.78], dtype=np.float32) * (0.86 + 0.24 * grain)[..., None]
    _put_tile(3, bench_alb, wd_nrm, np.clip(0.62 + 0.25 * wd_rgh, 0.50, 0.92), np.zeros((TILE, TILE), np.float32), wd_ao)

    albedo_p = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    normal_p = TEX_DIR / f"{PROP_SLUG}_normal.png"
    orm_p = TEX_DIR / f"{PROP_SLUG}_orm.png"
    Image.fromarray(alb_a.astype(np.uint8), mode="RGB").save(albedo_p)
    Image.fromarray(nrm_a.astype(np.uint8), mode="RGB").save(normal_p)
    tmp = {}
    for name, arr in (("ao", ao_a), ("rough", rgh_a), ("metal", met_a)):
        tmp[name] = TEX_DIR / f"_tmp_{name}.png"
        Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), mode="L").save(tmp[name])
    process_pbr.pack_orm(tmp["ao"], tmp["rough"], str(tmp["metal"]), orm_p, target_size=(TEX_SIZE, TEX_SIZE))
    for p in tmp.values():
        p.unlink(missing_ok=True)
    process_pbr.generate_godot_tres(
        material_name="M_PlaygroundMerryGoRound",
        albedo_path=albedo_p,
        normal_path=normal_p,
        orm_path=orm_p,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] {PROP_SLUG}: generated 2048x2048 albedo/normal/orm + .tres")


def _make_material():
    import bpy

    mat = bpy.data.materials.new(name="M_PlaygroundMerryGoRound")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def tex_node(suffix: str, cs: str):
        node = nt.nodes.new("ShaderNodeTexImage")
        img = bpy.data.images.load(str((TEX_DIR / f"{PROP_SLUG}_{suffix}.png").resolve()), check_existing=True)
        img.colorspace_settings.name = cs
        node.image = img
        return node

    nt.links.new(tex_node("albedo", "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_node("orm", "Non-Color").outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = 0.85
    nt.links.new(tex_node("normal", "Non-Color").outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _add_swept_tube(b: Builder, points: list, radius: float, segs: int, region: int) -> None:
    from mathutils import Vector

    rings: list[list[Vector]] = []
    n_pts = len(points)
    for idx, pt in enumerate(points):
        p = Vector(pt)
        if idx == 0:
            tangent = (Vector(points[1]) - p).normalized()
        elif idx == n_pts - 1:
            tangent = (p - Vector(points[-2])).normalized()
        else:
            t_in = (p - Vector(points[idx - 1])).normalized()
            t_out = (Vector(points[idx + 1]) - p).normalized()
            tangent = t_in + t_out
            tangent = tangent.normalized() if tangent.length > 1e-6 else t_out

        ref = Vector((0.0, 1.0, 0.0)) if abs(tangent.y) < 0.9 else Vector((1.0, 0.0, 0.0))
        binorm = tangent.cross(ref).normalized()
        norm = binorm.cross(tangent).normalized()
        rings.append([
            p + (binorm * math.cos(2.0 * math.pi * s / segs) + norm * math.sin(2.0 * math.pi * s / segs)) * radius
            for s in range(segs)
        ])
    b.add_loft(rings, region=region, caps=(True, True), smooth=True)


def _add_strut(b: Builder, p0, p1, radius: float, segs: int, region: int) -> None:
    from mathutils import Vector

    a = Vector(p0)
    z = Vector(p1)
    delta = z - a
    length = delta.length
    if length < 1e-6:
        return
    rot = delta.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    b.add_cyl((a + z) * 0.5, radius, length, region=region, segs=segs, rot=rot, caps=(False, False))


def _build_base(mat) -> tuple[object, int]:
    """Build grounded RoundaboutBase (min_z = 0.0) with central spindle pedestal."""
    import bmesh
    import bpy
    from mathutils import Vector

    b = Builder(seed=301)
    # 1. Grounded cast-concrete / steel footing pad (z = 0.0 .. 0.055m)
    b.add_cyl(Vector((0.0, 0.0, 0.0275)), 0.460, 0.055, region=1, segs=16, r_top=0.440)
    # 2. Central steel bearing pedestal & vertical spin axle (z = 0.055 .. 0.170m)
    b.add_cyl(Vector((0.0, 0.0, 0.110)), 0.115, 0.110, region=1, segs=12, r_top=0.085)
    b.add_cyl(Vector((0.0, 0.0, 0.155)), 0.052, 0.050, region=1, segs=12)

    # 3. 4 radial steel gusset ribs anchoring pedestal to footing pad
    for i in range(4):
        ang = math.radians(45.0 + i * 90.0)
        ca, sa = math.cos(ang), math.sin(ang)
        p_in = Vector((ca * 0.095, sa * 0.095, 0.125))
        p_out = Vector((ca * 0.340, sa * 0.340, 0.055))
        _add_strut(b, p_in, p_out, 0.018, segs=6, region=1)

    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    mesh = bpy.data.meshes.new("RoundaboutBase")
    b.bm.to_mesh(mesh)
    b.bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("RoundaboutBase", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (0.0, 0.0, 0.0)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tris


def _build_deck(mat) -> tuple[object, int]:
    """Build RoundaboutDeck with origin centered on the vertical spin axis (0, 0, DECK_PIVOT_Z)."""
    import bmesh
    import bpy
    from mathutils import Vector

    b = Builder(seed=302)
    # Local z=0 is at world z = DECK_PIVOT_Z (0.14m).
    # Total height = 0.95m -> local max z = 0.95 - 0.14 = 0.810m.
    deck_bot = 0.0
    deck_top = 0.068
    segs = 24

    # 1. Circular deck body with beveled outer steel rim + quadrant top UVs
    r_inner = DECK_RADIUS - 0.028
    r_outer = DECK_RADIUS
    ring_bot = [
        Vector((r_inner * math.cos(2.0 * math.pi * i / segs), r_inner * math.sin(2.0 * math.pi * i / segs), deck_bot))
        for i in range(segs)
    ]
    ring_mid_b = [
        Vector((r_outer * math.cos(2.0 * math.pi * i / segs), r_outer * math.sin(2.0 * math.pi * i / segs), deck_bot + 0.014))
        for i in range(segs)
    ]
    ring_mid_t = [
        Vector((r_outer * math.cos(2.0 * math.pi * i / segs), r_outer * math.sin(2.0 * math.pi * i / segs), deck_top - 0.010))
        for i in range(segs)
    ]
    ring_top = [
        Vector((r_inner * math.cos(2.0 * math.pi * i / segs), r_inner * math.sin(2.0 * math.pi * i / segs), deck_top))
        for i in range(segs)
    ]
    # Rim sides & underside in region 1 (weathered steel)
    b.add_loft([ring_bot, ring_mid_b, ring_mid_t, ring_top], region=1, caps=(True, False), smooth=False)

    # Top deck face projected linearly onto Tile 0 (red/yellow quadrants!)
    top_verts = [b.bm.verts.new(p) for p in ring_top]
    top_face = b.bm.faces.new(top_verts)
    top_face.smooth = False
    for lp, p in zip(top_face.loops, ring_top):
        u = (p.x / (2.0 * r_inner)) + 0.5
        v = (p.y / (2.0 * r_inner)) + 0.5
        lp[b.uv].uv = b.tile_uv(0, u, v)

    # 2. Central hub bearing cap on deck center
    b.add_cyl(Vector((0.0, 0.0, deck_top + 0.032)), 0.095, 0.064, region=1, segs=12, r_top=0.075)

    # 3. Two opposing tubular safety railing bays + wooden seat benches (centered at -Y and +Y)
    pipe_r = 0.019
    outer_top_z = 0.810 - pipe_r  # world max Z = 0.140 + 0.810 = 0.950m exact
    inner_top_z = 0.480
    outer_x = 0.430
    outer_y = 0.920
    inner_x = 0.300
    inner_y = 0.380
    cr = 0.055

    for side in (-1.0, 1.0):
        # Outer tall tubular U-arch
        outer_pts = [
            Vector((-outer_x, side * outer_y, deck_top)),
            Vector((-outer_x, side * outer_y, outer_top_z - cr)),
            Vector((-(outer_x - cr * 0.35), side * outer_y, outer_top_z - cr * 0.35)),
            Vector((-(outer_x - cr), side * outer_y, outer_top_z)),
            Vector((+(outer_x - cr), side * outer_y, outer_top_z)),
            Vector((+(outer_x - cr * 0.35), side * outer_y, outer_top_z - cr * 0.35)),
            Vector((+outer_x, side * outer_y, outer_top_z - cr)),
            Vector((+outer_x, side * outer_y, deck_top)),
        ]
        _add_swept_tube(b, outer_pts, pipe_r, segs=8, region=1)

        # Inner shorter tubular U-arch
        inner_pts = [
            Vector((-inner_x, side * inner_y, deck_top)),
            Vector((-inner_x, side * inner_y, inner_top_z - cr)),
            Vector((-(inner_x - cr * 0.35), side * inner_y, inner_top_z - cr * 0.35)),
            Vector((-(inner_x - cr), side * inner_y, inner_top_z)),
            Vector((+(inner_x - cr), side * inner_y, inner_top_z)),
            Vector((+(inner_x - cr * 0.35), side * inner_y, inner_top_z - cr * 0.35)),
            Vector((+inner_x, side * inner_y, inner_top_z - cr)),
            Vector((+inner_x, side * inner_y, deck_top)),
        ]
        _add_swept_tube(b, inner_pts, pipe_r * 0.9, segs=8, region=1)

        # Two sloped red/white hazard-striped handrails linking outer arch down to inner arch
        for sx in (-1.0, 1.0):
            p_hi = Vector((sx * outer_x, side * outer_y, outer_top_z - 0.12))
            p_lo = Vector((sx * inner_x, side * inner_y, inner_top_z - 0.06))
            _add_strut(b, p_hi, p_lo, pipe_r * 0.92, segs=8, region=2)
            # Base mounting flanges on deck
            b.add_cyl(Vector((sx * outer_x, side * outer_y, deck_top + 0.008)), 0.036, 0.016, region=1, segs=8)
            b.add_cyl(Vector((sx * inner_x, side * inner_y, deck_top + 0.008)), 0.032, 0.016, region=1, segs=8)

        # Weathered wood seat bench across the railing bay at z_local = 0.28m (world 0.42m)
        bench_y = side * 0.720
        bench_z = 0.275
        b.add_box(Vector((0.0, bench_y, bench_z)), (0.760, 0.210, 0.036), region=3)
        # Tubular steel seat support legs down to deck
        for sx in (-0.310, 0.310):
            b.add_cyl(Vector((sx, bench_y, (deck_top + bench_z) * 0.5)), 0.014, bench_z - deck_top, region=1, segs=6)

    bmesh.ops.recalc_face_normals(b.bm, faces=b.bm.faces)
    mesh = bpy.data.meshes.new("RoundaboutDeck")
    b.bm.to_mesh(mesh)
    b.bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("RoundaboutDeck", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (0.0, 0.0, DECK_PIVOT_Z)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    return obj, tris


def _write_tscn() -> None:
    lines = [
        "[gd_scene load_steps=4 format=3]",
        "",
        f'[ext_resource type="PackedScene" path="res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb" id="1_glb"]',
        f'[ext_resource type="Material" path="res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres" id="2_mat"]',
        "",
        '[sub_resource type="BoxShape3D" id="BoxShape3D_1"]',
        "size = Vector3(2.2, 0.95, 2.2)",
        "",
        '[node name="PlaygroundMerryGoRound" type="StaticBody3D"]',
        "collision_layer = 1",
        "collision_mask = 0",
        "",
        '[node name="Model" parent="." instance=ExtResource("1_glb")]',
        "",
        '[node name="RoundaboutBase" parent="Model" index="0"]',
        "layers = 1",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="RoundaboutDeck" parent="Model" index="1"]',
        "layers = 1",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="."]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.0, 0.475, 0.0)",
        'shape = SubResource("BoxShape3D_1")',
        "",
        '[editable path="Model"]',
    ]
    out_tscn = REPO_ROOT / "props" / PROP_SLUG / f"{PROP_SLUG}.tscn"
    out_tscn.parent.mkdir(parents=True, exist_ok=True)
    out_tscn.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _build_mesh_and_export() -> None:
    import bpy
    from mathutils import Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    needed = [TEX_DIR / f"{PROP_SLUG}_{s}.png" for s in ("albedo", "normal", "orm")]
    if not all(p.is_file() for p in needed) or not TRES_PATH.is_file():
        subprocess.run(["/usr/bin/python3", str(Path(__file__).resolve()), "--gen-textures"], check=True)

    clean_scene()
    mat = _make_material()
    base_obj, base_tris = _build_base(mat)
    deck_obj, deck_tris = _build_deck(mat)

    bpy.ops.object.select_all(action="DESELECT")
    for o in (base_obj, deck_obj):
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.select_set(False)

    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for o in (base_obj, deck_obj):
        for v in o.data.vertices:
            wp = o.matrix_world @ v.co
            mins.x = min(mins.x, wp.x)
            mins.y = min(mins.y, wp.y)
            mins.z = min(mins.z, wp.z)
            maxs.x = max(maxs.x, wp.x)
            maxs.y = max(maxs.y, wp.y)
            maxs.z = max(maxs.z, wp.z)

    total_tris = base_tris + deck_tris
    assert total_tris <= TRI_BUDGET, f"{PROP_SLUG}: {total_tris} tris > {TRI_BUDGET}"
    dims_godot = [
        round(maxs.x - mins.x, 4),
        round(maxs.z - mins.z, 4),
        round(maxs.y - mins.y, 4),
    ]

    export_godot_glb(GLB_PATH, export_animations=False, export_morph=False, only_selected=False)

    manifest = {
        "prop_slug": PROP_SLUG,
        "objects": ["RoundaboutBase", "RoundaboutDeck"],
        "deck_pivot_godot": [0.0, DECK_PIVOT_Z, 0.0],
        "tri_count": total_tris,
        "tri_budget": TRI_BUDGET,
        "uv_layers": len(base_obj.data.uv_layers),
        "min_y": round(mins.z, 4),
        "dimensions_m": dims_godot,
        "layer": "Layer 1 Environment",
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "ref_image": REF_IMAGE,
        "reference_image": REF_IMAGE,
        "material": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres",
        "mesh": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    _write_tscn()
    print(f"[OK] {PROP_SLUG}: tris={total_tris}/{TRI_BUDGET}, dims_m={dims_godot}, min_y={manifest['min_y']}")


def main() -> None:
    if "--gen-textures" in sys.argv:
        _generate_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
