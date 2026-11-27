"""Procedural Retro Soviet Tabletop Radio Receiver (0.26m H).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-10-29_18-06_1.png
- /home/dkd/Downloads/hl2_refs/2026-10-29_18-23_1.png

Features:
- Rounded-top chamfered olive-gray/wood cabinet on 4 tiny rubber feet (min_y = 0)
- Recessed front fascia with upper-left VU meter dial & wide amber frequency scale
- 2 large central tuning/volume knobs + 6 small control/band knobs + trim strip
- Vented rear speaker cloth & slotted backplate
- 2048x2048 PBR atlas (custom dial graphics + weathered wood/enamel + bakelite/metal)

Usage:
    .venv/bin/python tools/blender/props/retro_soviet_radio.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/retro_soviet_radio.py
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

PROP_SLUG: str = "retro_soviet_radio"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = TEX_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = TEX_DIR / f"{PROP_SLUG}_orm.png"

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-29_18-06_1.png"
TARGET_HEIGHT_M: float = 0.26
TRI_BUDGET: int = 1200

SRC_WOOD_DIR: Path = REPO_ROOT / "assets" / "materials" / "weathered_olive_crate_wood" / "textures"
SRC_METAL_DIR: Path = REPO_ROOT / "assets" / "materials" / "painted_industrial_metal" / "textures"

TEX_SIZE: int = 2048


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def generate_textures() -> None:
    """Generate 2048x2048 retro Soviet radio PBR atlas (fascia dial + cabinet + knobs)."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2

    src_wood_alb = _load_square_rgb(SRC_WOOD_DIR / "weathered_olive_crate_wood_albedo.png", half)
    src_wood_nrm = _load_square_rgb(SRC_WOOD_DIR / "weathered_olive_crate_wood_normal.png", half)
    src_met_alb = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_albedo.png", half)
    src_met_nrm = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_normal.png", half)

    # Quadrant layout:
    # Q_UL (0..half, 0..half): Front fascia panel (mapped 1:1 upright!) with VU meter + frequency scale + olive-taupe metal
    # Q_LL (0..half, half..TEX_SIZE): Cabinet shell (olive-gray/dark wood-enamel housing)
    # Q_UR (half..TEX_SIZE, 0..half): Woven speaker grille cloth + rear vents
    # Q_LR (half..TEX_SIZE, half..TEX_SIZE): Bakelite / brushed brass-steel knobs & trim

    # 1. Cabinet shell (Q_LL)
    met_lum = 0.299 * src_met_alb[..., 0] + 0.587 * src_met_alb[..., 1] + 0.114 * src_met_alb[..., 2]
    met_low = np.asarray(
        Image.fromarray(np.clip(met_lum, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=14)
        ),
        dtype=np.float32,
    )
    met_hp = np.clip(met_lum - met_low, -22.0, 20.0)
    olive_cab = np.array([94.0, 102.0, 90.0], dtype=np.float32)
    cab_alb = olive_cab[None, None, :] * 0.82 + src_wood_alb * 0.18 + met_hp[..., None] * 0.30
    cab_nrm = (src_met_nrm - 128.0) * 0.30 + (src_wood_nrm - 128.0) * 0.18 + 128.0
    cab_rough = np.clip(0.58 - met_hp * 0.004, 0.44, 0.78)
    cab_metal = np.full((half, half), 0.18, dtype=np.float32)
    cab_ao = np.clip(0.90 + met_hp * 0.002, 0.65, 1.0)

    # 2. Front Fascia Panel (Q_UL): weathered brownish-taupe painted metal + crisp VU meter & wide tuning scale
    fascia_base = np.array([106.0, 96.0, 84.0], dtype=np.float32)
    fascia_alb = fascia_base[None, None, :] + (met_low - 115.0)[..., None] * 0.18 + met_hp[..., None] * 0.40
    fascia_rough = np.clip(0.54 - met_hp * 0.004, 0.40, 0.75)
    fascia_metal = np.full((half, half), 0.12, dtype=np.float32)
    fascia_ao = np.clip(0.90 + met_hp * 0.002, 0.65, 1.0)
    fascia_nrm = (src_met_nrm - 128.0) * 0.35 + 128.0

    # Draw VU meter (upper-left) & wide illuminated frequency scale (upper-right) onto fascia_alb
    f_img = Image.fromarray(np.clip(fascia_alb, 30, 240).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(f_img)

    # VU Meter window: x in [0.08..0.24], y in [0.12..0.33] (PIL y=0 is top!)
    vu_x0, vu_y0, vu_x1, vu_y1 = int(half * 0.085), int(half * 0.12), int(half * 0.24), int(half * 0.33)
    draw.rectangle([vu_x0, vu_y0, vu_x1, vu_y1], fill=(224, 218, 198), outline=(44, 40, 36), width=5)
    # Curved scale arc & needle
    cx_vu, cy_vu = (vu_x0 + vu_x1) // 2, vu_y1 - 24
    draw.arc([vu_x0 + 18, vu_y0 + 22, vu_x1 - 18, vu_y1 + 20], start=210, end=330, fill=(48, 44, 40), width=3)
    draw.line([(cx_vu, cy_vu), (cx_vu + 22, vu_y0 + 38)], fill=(155, 48, 36), width=3)
    draw.ellipse([cx_vu - 8, cy_vu - 8, cx_vu + 8, cy_vu + 8], fill=(42, 38, 36))

    # Wide frequency dial window: x in [0.29..0.91], y in [0.11..0.35]
    dl_x0, dl_y0, dl_x1, dl_y1 = int(half * 0.29), int(half * 0.11), int(half * 0.91), int(half * 0.35)
    draw.rectangle([dl_x0, dl_y0, dl_x1, dl_y1], fill=(218, 192, 146), outline=(42, 38, 34), width=6)
    # Warm inner glow band
    draw.rectangle([dl_x0 + 8, dl_y0 + 8, dl_x1 - 8, dl_y1 - 8], fill=(228, 202, 154), outline=(145, 118, 82), width=2)
    # Horizontal band lines + fine frequency tick marks
    for row_frac in (0.28, 0.50, 0.72):
        ry = int(dl_y0 + (dl_y1 - dl_y0) * row_frac)
        draw.line([(dl_x0 + 18, ry), (dl_x1 - 18, ry)], fill=(68, 56, 42), width=2)
        for tx in range(dl_x0 + 24, dl_x1 - 24, 18):
            tick_h = 10 if ((tx - dl_x0) % 54 == 0) else 5
            draw.line([(tx, ry - tick_h), (tx, ry)], fill=(54, 44, 34), width=2)
    # Red vertical tuning indicator needle
    needle_x = int(dl_x0 + (dl_x1 - dl_x0) * 0.62)
    draw.line([(needle_x, dl_y0 + 10), (needle_x, dl_y1 - 10)], fill=(178, 46, 32), width=4)

    # Glassy lower roughness on meter & dial windows
    fascia_rough[vu_y0:vu_y1, vu_x0:vu_x1] = 0.18
    fascia_rough[dl_y0:dl_y1, dl_x0:dl_x1] = 0.20
    fascia_alb = np.asarray(f_img, dtype=np.float32)

    # 3. Woven speaker cloth / vented grille (Q_UR)
    yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
    weave = 0.5 + 0.5 * np.sin(xx * 0.45) * np.sin(yy * 0.45)
    cloth_base = np.array([62.0, 58.0, 48.0], dtype=np.float32)
    cloth_alb = cloth_base[None, None, :] + weave[..., None] * 26.0 + met_hp[..., None] * 0.25
    cloth_nrm = np.full((half, half, 3), 128.0, dtype=np.float32)
    cloth_nrm[..., 0] = 128.0 + np.cos(xx * 0.45) * 28.0
    cloth_nrm[..., 1] = 128.0 + np.cos(yy * 0.45) * 28.0
    cloth_nrm[..., 2] = 240.0
    cloth_rough = np.full((half, half), 0.88, dtype=np.float32)
    cloth_metal = np.zeros((half, half), dtype=np.float32)
    cloth_ao = 0.72 + weave * 0.28

    # 4. Knobs & metallic hardware (Q_LR)
    knob_base = np.array([76.0, 68.0, 58.0], dtype=np.float32)
    knob_alb = knob_base[None, None, :] + met_hp[..., None] * 0.45
    knob_nrm = (src_met_nrm - 128.0) * 0.35 + 128.0
    knob_rough = np.clip(0.34 - met_hp * 0.003, 0.24, 0.52)
    knob_metal = np.full((half, half), 0.45, dtype=np.float32)
    knob_ao = np.clip(0.88 + met_hp * 0.002, 0.65, 1.0)

    alb_full = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    nrm_full = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    rough_full = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    metal_full = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    ao_full = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)

    alb_full[0:half, 0:half, :] = fascia_alb
    alb_full[half:TEX_SIZE, 0:half, :] = cab_alb
    alb_full[0:half, half:TEX_SIZE, :] = cloth_alb
    alb_full[half:TEX_SIZE, half:TEX_SIZE, :] = knob_alb

    nrm_full[0:half, 0:half, :] = fascia_nrm
    nrm_full[half:TEX_SIZE, 0:half, :] = cab_nrm
    nrm_full[0:half, half:TEX_SIZE, :] = cloth_nrm
    nrm_full[half:TEX_SIZE, half:TEX_SIZE, :] = knob_nrm

    rough_full[0:half, 0:half] = fascia_rough
    rough_full[half:TEX_SIZE, 0:half] = cab_rough
    rough_full[0:half, half:TEX_SIZE] = cloth_rough
    rough_full[half:TEX_SIZE, half:TEX_SIZE] = knob_rough

    metal_full[0:half, 0:half] = fascia_metal
    metal_full[half:TEX_SIZE, 0:half] = cab_metal
    metal_full[0:half, half:TEX_SIZE] = cloth_metal
    metal_full[half:TEX_SIZE, half:TEX_SIZE] = knob_metal

    ao_full[0:half, 0:half] = fascia_ao
    ao_full[half:TEX_SIZE, 0:half] = cab_ao
    ao_full[0:half, half:TEX_SIZE] = cloth_ao
    ao_full[half:TEX_SIZE, half:TEX_SIZE] = knob_ao

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
        material_name="M_RetroSovietRadio",
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
    # 0 = Cabinet shell (Q_LL)
    # 1 = Front fascia face 1:1 (Q_UL)
    # 2 = Speaker cloth / rear vent panel (Q_UR)
    # 3 = Knobs, feet & trim (Q_LR)

    cab_w = 0.39
    cab_d = 0.24
    foot_h = 0.008
    cab_z0 = foot_h
    cab_z1 = 0.260
    cab_h = cab_z1 - cab_z0
    cab_cz = (cab_z0 + cab_z1) * 0.5

    # 4 corner feet (min_z = 0.0)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            add_cylinder(
                Vector((sx * (cab_w * 0.5 - 0.032), sy * (cab_d * 0.5 - 0.030), foot_h * 0.5)),
                Vector((0.0, 0.0, 1.0)),
                0.012,
                foot_h,
                8,
                region=3,
                smooth=False,
            )

    # Main rounded-top cabinet body (2-segment top edge bevel for authentic Soviet radio curve)
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    bmesh.ops.transform(
        bm,
        matrix=Matrix.Translation((0.0, 0.0, cab_cz)) @ Matrix.Diagonal((cab_w, cab_d, cab_h, 1.0)),
        verts=verts,
    )
    vset = set(verts)
    top_corner_edges = [
        e for e in bm.edges
        if all(v in vset for v in e.verts)
        and abs(e.verts[0].co.y - e.verts[1].co.y) > 0.10
        and e.verts[0].co.z > cab_cz
    ]
    bmesh.ops.bevel(
        bm,
        geom=top_corner_edges,
        offset=0.032,
        offset_type="OFFSET",
        segments=3,
        profile=0.5,
        affect="EDGES",
        clamp_overlap=True,
    )
    for f in bm.faces:
        if any(v in vset for v in f.verts):
            f.material_index = 0
            f.smooth = False

    # Front recessed fascia panel (slightly inset inside front rim)
    fascia_w = cab_w - 0.026
    fascia_h = cab_h - 0.026
    fascia_y = -cab_d * 0.5 - 0.002
    fascia_faces = add_box(Vector((0.0, fascia_y, cab_cz)), Vector((fascia_w, 0.012, fascia_h)), region=0, bevel_w=0.003)
    bm.normal_update()
    for f in fascia_faces:
        if f.normal.y < -0.94:
            f.material_index = 1

    # Horizontal decorative metal trim bar across middle of fascia
    add_box(Vector((0.0, fascia_y - 0.008, cab_cz - 0.020)), Vector((fascia_w - 0.020, 0.008, 0.010)), region=3)

    # 2 Large Central Control Knobs (volume & tuning)
    for kx in (0.005, 0.095):
        ky = fascia_y - 0.012
        kz = cab_cz - 0.020
        add_cylinder(Vector((kx, ky, kz)), Vector((0.0, -1.0, 0.0)), 0.024, 0.012, 10, region=3, smooth=True)
        add_cylinder(Vector((kx, ky - 0.009, kz)), Vector((0.0, -1.0, 0.0)), 0.018, 0.012, 10, region=3, smooth=True)

    # 2 Small Left Knobs (above/below on left under VU meter)
    for kz in (cab_cz - 0.022, cab_cz - 0.078):
        ky = fascia_y - 0.011
        add_cylinder(Vector((-0.128, ky, kz)), Vector((0.0, -1.0, 0.0)), 0.013, 0.014, 8, region=3, smooth=True)

    # 4 Small Bottom Row Knobs
    for kx in (-0.068, -0.012, 0.062, 0.132):
        ky = fascia_y - 0.011
        add_cylinder(Vector((kx, ky, cab_cz - 0.078)), Vector((0.0, -1.0, 0.0)), 0.012, 0.014, 8, region=3, smooth=True)

    # Rear speaker cloth panel & ventilated slatted backplate (+Y)
    add_box(Vector((0.0, cab_d * 0.5 + 0.002, cab_cz)), Vector((cab_w - 0.036, 0.008, cab_h - 0.036)), region=2)
    for vz in (cab_cz - 0.05, cab_cz, cab_cz + 0.05):
        add_box(Vector((0.0, cab_d * 0.5 + 0.008, vz)), Vector((cab_w - 0.07, 0.006, 0.012)), region=0)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    fascia_front_indices = [f.index for f in bm.faces if f.material_index == 1]

    mesh = bpy.data.meshes.new("RetroSovietRadio")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))

    obj = bpy.data.objects.new("RetroSovietRadio", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")
    uv_regions = {
        0: (0.015, 0.485, 0.015, 0.485),
        2: (0.515, 0.985, 0.515, 0.985),
        3: (0.515, 0.985, 0.015, 0.485),
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

    # Map front fascia face 1:1 into Q_UL [0.0..0.5, 0.5..1.0]
    bm_uv = bmesh.new()
    bm_uv.from_mesh(mesh)
    uv_layer = bm_uv.loops.layers.uv.verify()
    fset = set(fascia_front_indices)
    ffaces = [f for f in bm_uv.faces if f.index in fset]
    if ffaces:
        xs = [l.vert.co.x for f in ffaces for l in f.loops]
        zs = [l.vert.co.z for f in ffaces for l in f.loops]
        x0, x1 = min(xs), max(xs)
        z0, z1 = min(zs), max(zs)
        dx = max(x1 - x0, 1e-5)
        dz = max(z1 - z0, 1e-5)
        for f in ffaces:
            for l in f.loops:
                tx = (l.vert.co.x - x0) / dx
                tz = (l.vert.co.z - z0) / dz
                l[uv_layer].uv = (0.0 + tx * 0.495, 0.505 + tz * 0.49)

    for f in bm_uv.faces:
        f.material_index = 0
    bm_uv.to_mesh(mesh)
    bm_uv.free()

    mat = bpy.data.materials.new(name="M_RetroSovietRadio")
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
