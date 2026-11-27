"""Procedural Double Metal Industrial Locker (1.90m H).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-37_3.png
- /home/dkd/Downloads/hl2_refs/2026-11-01_13-40.png

Features:
- Grounded recessed steel plinth with front intake vent grille (min_y = 0)
- Heavy sheet-steel carcass with recessed door frame and twin full-height doors
- 6 barrel hinges, 2 recessed pocket latch handles, upper header cornice
- Upper-right louvered vent grille + upper-left stenciled ID tag
- 2048x2048 PBR atlas (weathered slate-teal-green painted steel + dark hardware)

Usage:
    .venv/bin/python tools/blender/props/metal_locker_double.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/metal_locker_double.py
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

PROP_SLUG: str = "metal_locker_double"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = TEX_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = TEX_DIR / f"{PROP_SLUG}_orm.png"

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-37_3.png"
TARGET_HEIGHT_M: float = 1.90
TRI_BUDGET: int = 1600

SRC_METAL_DIR: Path = REPO_ROOT / "assets" / "materials" / "painted_industrial_metal" / "textures"
SRC_RUST_DIR: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TEX_SIZE: int = 2048


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def generate_textures() -> None:
    """Generate 2048x2048 industrial slate-green locker + dark hardware PBR atlas."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2

    src_metal_alb = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_albedo.png", half)
    src_metal_nrm = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_normal.png", half)
    src_rust_alb = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_albedo.png", half)
    src_rust_nrm = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_normal.png", half)

    lum = 0.299 * src_metal_alb[..., 0] + 0.587 * src_metal_alb[..., 1] + 0.114 * src_metal_alb[..., 2]
    low_lum = np.asarray(
        Image.fromarray(np.clip(lum, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=16)
        ),
        dtype=np.float32,
    )
    high_pass = np.clip(lum - low_lum, -26.0, 22.0)

    # Quadrant layout (2048x2048):
    # Q_UL (0..half, 0..half): Front doors upright (with subtle edge wear, center seam AO, stencil tag)
    # Q_LL (0..half, half..TEX_SIZE): Cabinet body / sides / top / plinth (weathered slate-teal-green steel)
    # Q_UR (half..TEX_SIZE, 0..half): Dark iron/steel hardware (hinges, pocket handles, louvers, vent grille)
    # Q_LR (half..TEX_SIZE, half..TEX_SIZE): Secondary grime/steel trim

    # Base industrial slate-teal-green steel matching HL2 refs (readable value ~80..105 sRGB)
    base_col = np.array([80.0, 102.0, 94.0], dtype=np.float32)
    rust_col = np.array([78.0, 62.0, 50.0], dtype=np.float32)

    # Subtle micro-scuffs and gentle chalky variation (avoid oversized dark blotches)
    chip_mask = np.clip((64.0 - low_lum) / 32.0, 0.0, 1.0) * 0.22
    var_macro = np.clip((low_lum - 120.0) * 0.14, -9.0, 9.0)

    paint_alb = base_col[None, None, :] + var_macro[..., None] + high_pass[..., None] * 0.36
    paint_alb = paint_alb * (1.0 - chip_mask[..., None]) + (src_rust_alb * 0.45 + rust_col[None, None, :] * 0.55) * chip_mask[..., None]
    paint_nrm = (src_metal_nrm - 128.0) * 0.32 + 128.0
    paint_rough = np.clip(0.48 - high_pass * 0.003 + chip_mask * 0.20, 0.38, 0.74)
    paint_metal = np.clip(0.24 + chip_mask * 0.50, 0.18, 0.78)
    paint_ao = np.clip(0.94 - chip_mask * 0.20 + high_pass * 0.002, 0.60, 1.0)

    # Door front upright panel (Q_UL): add subtle hand-wear around middle height + bottom scuff + top-left ID stencil
    door_alb = paint_alb.copy()
    door_rough = paint_rough.copy()
    door_metal = paint_metal.copy()
    door_ao = paint_ao.copy()
    door_nrm = paint_nrm.copy()

    yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
    yn = yy / float(half)  # 0 = top, 1 = bottom
    xn = xx / float(half)  # 0 = left, 1 = right

    # Bottom scuffing near floor
    bot_scuff = np.clip((yn - 0.84) / 0.16, 0.0, 1.0)
    door_alb *= (1.0 - bot_scuff[..., None] * 0.22)
    door_rough = np.clip(door_rough + bot_scuff * 0.14, 0.38, 0.85)
    door_ao *= (1.0 - bot_scuff * 0.25)

    # Center vertical door gap shadow & edge wear near handles (yn ~ 0.45..0.60, xn ~ 0.05..0.95)
    edge_dist = np.minimum(xn, 1.0 - xn)
    edge_wear = np.clip((0.035 - edge_dist) / 0.035, 0.0, 1.0)
    handle_wear = np.exp(-(((yn - 0.52) / 0.10) ** 2 + ((xn - 0.82) / 0.14) ** 2)) * 0.30
    door_alb += (edge_wear[..., None] * 14.0) - handle_wear[..., None] * 14.0
    door_metal = np.clip(door_metal + edge_wear * 0.38, 0.16, 0.85)
    door_rough = np.clip(door_rough - handle_wear * 0.12, 0.34, 0.85)

    # Small warm ochre/tan painted stencil tag ("26 / 8" style) on upper-left of door texture
    tag_img = Image.fromarray(np.clip(door_alb, 30, 240).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(tag_img)
    tag_x0, tag_y0 = int(half * 0.07), int(half * 0.05)
    tag_x1, tag_y1 = int(half * 0.19), int(half * 0.13)
    draw.rectangle([tag_x0, tag_y0, tag_x1, tag_y1], fill=(128, 102, 58), outline=(54, 46, 36), width=3)
    # Crisp painted stencil digits
    draw.text((tag_x0 + 18, tag_y0 + 12), "26", fill=(42, 38, 34))
    draw.text((tag_x0 + 26, tag_y0 + 38), "8", fill=(42, 38, 34))
    door_alb = np.asarray(tag_img, dtype=np.float32)

    # Cabinet shell (Q_LL): vertical floor-to-top grime gradient
    body_alb = paint_alb.copy()
    body_ao = paint_ao.copy()
    body_rough = paint_rough.copy()
    body_alb *= (1.0 - bot_scuff[..., None] * 0.25)
    body_ao *= (1.0 - bot_scuff * 0.28)
    body_rough = np.clip(body_rough + bot_scuff * 0.14, 0.38, 0.85)

    # Dark hardware & vents (Q_UR & Q_LR)
    rust_lum = 0.299 * src_rust_alb[..., 0] + 0.587 * src_rust_alb[..., 1] + 0.114 * src_rust_alb[..., 2]
    hw_alb = src_rust_alb * 0.34 + np.array([34.0, 34.0, 36.0], dtype=np.float32)[None, None, :]
    hw_nrm = (src_rust_nrm - 128.0) * 0.55 + 128.0
    hw_rough = np.clip(0.42 + (1.0 - rust_lum / 255.0) * 0.24, 0.32, 0.72)
    hw_metal = np.clip(0.80 - np.clip((src_rust_alb[..., 0] - src_rust_alb[..., 2]) / 85.0, 0.0, 0.42), 0.38, 0.88)
    hw_ao = np.clip(0.72 + (rust_lum / 255.0) * 0.28, 0.45, 1.0)

    # Assemble 2048x2048 sheets
    alb_full = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    nrm_full = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    rough_full = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    metal_full = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    ao_full = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)

    # Top-left = door_alb (V in [0.5, 1.0]), Bottom-left = body_alb (V in [0.0, 0.5])
    alb_full[0:half, 0:half, :] = door_alb
    alb_full[half:TEX_SIZE, 0:half, :] = body_alb
    alb_full[0:half, half:TEX_SIZE, :] = hw_alb
    alb_full[half:TEX_SIZE, half:TEX_SIZE, :] = hw_alb

    nrm_full[0:half, 0:half, :] = door_nrm
    nrm_full[half:TEX_SIZE, 0:half, :] = paint_nrm
    nrm_full[0:half, half:TEX_SIZE, :] = hw_nrm
    nrm_full[half:TEX_SIZE, half:TEX_SIZE, :] = hw_nrm

    rough_full[0:half, 0:half] = door_rough
    rough_full[half:TEX_SIZE, 0:half] = body_rough
    rough_full[0:half, half:TEX_SIZE] = hw_rough
    rough_full[half:TEX_SIZE, half:TEX_SIZE] = hw_rough

    metal_full[0:half, 0:half] = door_metal
    metal_full[half:TEX_SIZE, 0:half] = paint_metal
    metal_full[0:half, half:TEX_SIZE] = hw_metal
    metal_full[half:TEX_SIZE, half:TEX_SIZE] = hw_metal

    ao_full[0:half, 0:half] = door_ao
    ao_full[half:TEX_SIZE, 0:half] = body_ao
    ao_full[0:half, half:TEX_SIZE] = hw_ao
    ao_full[half:TEX_SIZE, half:TEX_SIZE] = hw_ao

    nrm_v = (nrm_full / 255.0) * 2.0 - 1.0
    nrm_v[..., 2] = np.maximum(nrm_v[..., 2], 0.30)
    nrm_l = np.sqrt(np.sum(nrm_v * nrm_v, axis=-1, keepdims=True))
    nrm_v /= np.maximum(nrm_l, 1e-6)
    nrm_u8 = np.clip((nrm_v * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)

    Image.fromarray(np.clip(alb_full, 30.0, 240.0).astype(np.uint8), mode="RGB").save(ALBEDO_PATH, format="PNG")
    Image.fromarray(nrm_u8, mode="RGB").save(NORMAL_PATH, format="PNG")

    ao_tmp = TEX_DIR / "_tmp_ao.png"
    rough_tmp = TEX_DIR / "_tmp_rough.png"
    metal_tmp = TEX_DIR / "_tmp_metal.png"
    Image.fromarray(np.clip(ao_full * 255.0, 0, 255).astype(np.uint8), mode="L").save(ao_tmp, format="PNG")
    Image.fromarray(np.clip(rough_full * 255.0, 0, 255).astype(np.uint8), mode="L").save(rough_tmp, format="PNG")
    Image.fromarray(np.clip(metal_full * 255.0, 0, 255).astype(np.uint8), mode="L").save(metal_tmp, format="PNG")

    process_pbr.pack_orm(ao_tmp, rough_tmp, str(metal_tmp), ORM_PATH, target_size=(TEX_SIZE, TEX_SIZE))
    ao_tmp.unlink(missing_ok=True)
    rough_tmp.unlink(missing_ok=True)
    metal_tmp.unlink(missing_ok=True)

    process_pbr.generate_godot_tres(
        material_name="M_MetalLockerDouble",
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

    def add_box(center: Vector, size: Vector, region: int, bevel_w: float = 0.0) -> list[bmesh.types.BMFace]:
        before_faces = set(bm.faces)
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        xform = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        if bevel_w > 0.0:
            vset = set(verts)
            edges = [e for e in bm.edges if all(v in vset for v in e.verts)]
            bmesh.ops.bevel(
                bm,
                geom=edges,
                offset=bevel_w,
                offset_type="OFFSET",
                segments=1,
                profile=0.5,
                affect="EDGES",
                clamp_overlap=True,
            )
        touched = [f for f in bm.faces if f not in before_faces]
        for f in touched:
            f.material_index = region
            f.smooth = False
        return touched

    def add_cylinder(
        center: Vector,
        axis: Vector,
        radius: float,
        depth: float,
        segments: int,
        region: int,
        smooth: bool = True,
    ) -> None:
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
        _tag_verts(ret["verts"], region, smooth=smooth)

    # Regions:
    # 0 = Cabinet body / sides / plinth / cornice (Q_LL: u=[0.01..0.49], v=[0.01..0.49])
    # 1 = Front door panels upright (Q_UL: u=[0.01..0.49], v=[0.51..0.99]) - mapped 1:1 per door
    # 2 = Dark iron hardware: hinges, handle pockets, louvers, bottom vent (Q_UR: u=[0.51..0.99], v=[0.01..0.99])

    locker_w = 1.04
    locker_d = 0.50
    plinth_h = 0.095
    body_z0 = plinth_h
    body_z1 = 1.735
    header_z0 = 1.745
    header_z1 = 1.900

    # 1. Recessed steel plinth base (min_z = 0.0) + front vent grille panel
    add_box(Vector((0.0, 0.015, plinth_h * 0.5)), Vector((locker_w - 0.02, locker_d - 0.03, plinth_h)), region=0)
    add_box(Vector((0.0, -locker_d * 0.5 + 0.025, plinth_h * 0.5)), Vector((locker_w - 0.14, 0.012, plinth_h - 0.03)), region=2)

    # 2. Main cabinet carcass (with front outer frame flange)
    body_h = body_z1 - body_z0
    body_cz = (body_z0 + body_z1) * 0.5
    add_box(Vector((0.0, 0.0, body_cz)), Vector((locker_w, locker_d, body_h)), region=0, bevel_w=0.004)

    # Subtle reveal neck between body & top header cornice
    add_box(Vector((0.0, 0.005, 1.740)), Vector((locker_w - 0.024, locker_d - 0.018, 0.016)), region=2)

    # 3. Upper header cornice + louvered vent bank on upper-right + small nameplate on upper-left
    hdr_h = header_z1 - header_z0
    hdr_cz = (header_z0 + header_z1) * 0.5
    add_box(Vector((0.0, 0.0, hdr_cz)), Vector((locker_w, locker_d, hdr_h)), region=0, bevel_w=0.004)
    # Upper-right louver recess frame & 4 angled slats
    louver_x = 0.22
    louver_y = -locker_d * 0.5 - 0.002
    add_box(Vector((louver_x, louver_y + 0.004, hdr_cz)), Vector((0.38, 0.012, 0.096)), region=2)
    for si in range(4):
        sz = hdr_cz - 0.030 + si * 0.020
        add_box(Vector((louver_x, louver_y - 0.004, sz)), Vector((0.34, 0.012, 0.009)), region=2)
    # Upper-left nameplate badge
    add_box(Vector((-0.36, -locker_d * 0.5 - 0.004, hdr_cz - 0.01)), Vector((0.11, 0.008, 0.024)), region=2)

    # 4. Twin full-height steel doors (Left Door & Right Door with 8mm center reveal gap)
    door_w = (locker_w - 0.072) * 0.5  # 0.484m each
    door_h = body_h - 0.056
    door_d = 0.020
    door_y = -locker_d * 0.5 - door_d * 0.5 + 0.002
    left_door_x = -0.004 - door_w * 0.5
    right_door_x = +0.004 + door_w * 0.5

    bm.normal_update()
    left_door_faces = add_box(Vector((left_door_x, door_y, body_cz)), Vector((door_w, door_d, door_h)), region=0, bevel_w=0.003)
    right_door_faces = add_box(Vector((right_door_x, door_y, body_cz)), Vector((door_w, door_d, door_h)), region=0, bevel_w=0.003)

    bm.normal_update()
    left_front_indices: list[int] = []
    right_front_indices: list[int] = []
    bm.faces.ensure_lookup_table()
    for f in left_door_faces:
        if f.normal.y < -0.92:
            f.material_index = 1
    for f in right_door_faces:
        if f.normal.y < -0.92:
            f.material_index = 3

    # 5. 6 barrel hinges along outer left & right door edges (3 per side)
    hinge_x = locker_w * 0.5 - 0.026
    for sx in (-1.0, 1.0):
        for hz in (0.30, 0.92, 1.54):
            add_cylinder(
                Vector((sx * hinge_x, door_y - door_d * 0.5 - 0.004, hz)),
                Vector((0.0, 0.0, 1.0)),
                radius=0.011,
                depth=0.058,
                segments=8,
                region=2,
                smooth=True,
            )

    # 6. 2 recessed rectangular pocket latch handles near center meeting stile
    for sx in (-1.0, 1.0):
        hx = sx * 0.078
        hy = door_y - door_d * 0.5
        # Outer dark frame bezel
        add_box(Vector((hx, hy - 0.004, 0.95)), Vector((0.068, 0.010, 0.135)), region=2)
        # Inner latch grip bar
        add_box(Vector((hx, hy - 0.011, 0.95)), Vector((0.022, 0.012, 0.088)), region=2)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    left_front_indices = [f.index for f in bm.faces if f.material_index == 1]
    right_front_indices = [f.index for f in bm.faces if f.material_index == 3]

    mesh = bpy.data.meshes.new("MetalLockerDouble")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))

    obj = bpy.data.objects.new("MetalLockerDouble", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")

    # Smart-project region 0 (body) -> Q_LL, region 2 (hardware) -> right half
    uv_regions = {
        0: (0.015, 0.485, 0.015, 0.485),
        2: (0.515, 0.985, 0.015, 0.985),
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

    # Map left front door face 1:1 into Q_UL (including stencil tag), right front door into clean right strip of Q_UL
    bm_uv = bmesh.new()
    bm_uv.from_mesh(mesh)
    uv_layer = bm_uv.loops.layers.uv.verify()

    def _map_planar_front(indices: list[int], u0: float, u1: float, v0: float, v1: float, flip_x: bool = False) -> None:
        iset = set(indices)
        faces = [f for f in bm_uv.faces if f.index in iset]
        if not faces:
            return
        xs = [l.vert.co.x for f in faces for l in f.loops]
        zs = [l.vert.co.z for f in faces for l in f.loops]
        x0, x1 = min(xs), max(xs)
        z0, z1 = min(zs), max(zs)
        dx = max(x1 - x0, 1e-5)
        dz = max(z1 - z0, 1e-5)
        for f in faces:
            for l in f.loops:
                tx = (l.vert.co.x - x0) / dx
                if flip_x:
                    tx = 1.0 - tx
                tz = (l.vert.co.z - z0) / dz
                l[uv_layer].uv = (u0 + tx * (u1 - u0), v0 + tz * (v1 - v0))

    _map_planar_front(left_front_indices, 0.015, 0.485, 0.515, 0.985, flip_x=False)
    # Right door avoids stencil tag in upper-left [0.07..0.19, 0.87..0.95] by sampling [0.22..0.485]
    _map_planar_front(right_front_indices, 0.22, 0.485, 0.515, 0.985, flip_x=True)

    for f in bm_uv.faces:
        f.material_index = 0
    bm_uv.to_mesh(mesh)
    bm_uv.free()

    mat = bpy.data.materials.new(name="M_MetalLockerDouble")
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
    print(f"[OK] {PROP_SLUG}: tris={tri_count}/{TRI_BUDGET}, dims_m={dims_godot}, uv_layers={len(mesh.uv_layers)}")


def main() -> None:
    if "--gen-textures" in sys.argv:
        generate_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
