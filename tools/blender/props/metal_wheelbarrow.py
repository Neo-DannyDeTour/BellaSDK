"""Procedural Metal Wheelbarrow with Dented Tray, Tubular Frame & Front Wheel (0.68m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-10_19-26.png:
- Grounded min_y = 0.0 (both front pneumatic tire and twin rear legs touch floor)
- ~1.42m long x ~0.62m wide x 0.68m tall
- Tapered dented painted steel tray with rolled rim
- Twin tubular undercarriage rails, rear U-loop legs + cross brace, long handles
- Front pneumatic rubber tire on steel hub
- 1024x1024 3-band PBR atlas (painted steel + rusted tube frame + rubber tire), <= 1,800 tris

Usage:
    python3 tools/blender/props/metal_wheelbarrow.py --textures
    python3 tools/blender/run.py tools/blender/props/metal_wheelbarrow.py
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

SLUG: str = "metal_wheelbarrow"
MESH_NAME: str = "MetalWheelbarrow"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / SLUG
GLB_PATH: Path = ASSET_DIR / f"{SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-10_19-26.png"

MAT_TRAY: Path = REPO_ROOT / "assets" / "materials" / "chipped_red_enamel_metal" / "textures"
MAT_RUST: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
MAT_RUBBER: Path = REPO_ROOT / "assets" / "materials" / "ribbed_black_cable_rubber" / "textures"

TEX_SIZE: int = 1024
# UV atlas bands:
# [0.0, 0.40): chipped red painted steel tray
# [0.40, 0.72): rusted/painted tubular steel frame & rim
# [0.72, 1.0]: matte black vulcanized pneumatic tire & grips
TRAY_U_MAX: float = 0.40
FRAME_U_MAX: float = 0.72

TARGET_L: float = 1.42
TARGET_H: float = 0.68


def _generate_pbr_textures() -> None:
    """Build 1024x1024 chipped enamel + rusted frame + rubber tire PBR atlas."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    u1_px = int(round(TEX_SIZE * TRAY_U_MAX))
    u2_px = int(round(TEX_SIZE * FRAME_U_MAX))
    tray_w = u1_px
    frame_w = u2_px - u1_px
    tire_w = TEX_SIZE - u2_px

    def _load_fit(path: Path, out_w: int, out_h: int, mode: str) -> np.ndarray:
        img = Image.open(path).convert(mode).resize((out_w, out_h), Image.Resampling.BICUBIC)
        return np.array(img, dtype=np.float32)

    # 1. Chipped red enamel steel tray
    tr_alb = _load_fit(MAT_TRAY / "chipped_red_enamel_metal_albedo.png", tray_w, TEX_SIZE, "RGB")
    tr_nrm = _load_fit(MAT_TRAY / "chipped_red_enamel_metal_normal.png", tray_w, TEX_SIZE, "RGB")
    tr_orm = _load_fit(MAT_TRAY / "chipped_red_enamel_metal_orm.png", tray_w, TEX_SIZE, "RGB")

    rs_alb = _load_fit(MAT_RUST / "rusted_steel_albedo.png", tray_w, TEX_SIZE, "RGB")
    rs_nrm = _load_fit(MAT_RUST / "rusted_steel_normal.png", tray_w, TEX_SIZE, "RGB")
    rs_orm = _load_fit(MAT_RUST / "rusted_steel_orm.png", tray_w, TEX_SIZE, "RGB")

    tray_alb = 0.74 * tr_alb + 0.26 * rs_alb
    tray_alb[..., 0] *= 0.96
    tray_alb[..., 1] *= 0.85
    tray_alb[..., 2] *= 0.82
    tray_alb_img = Image.fromarray(np.clip(tray_alb, 30, 225).astype(np.uint8), mode="RGB")

    tnrm = (0.72 * tr_nrm + 0.28 * rs_nrm) / 255.0 * 2.0 - 1.0
    tnrm[..., 2] = np.maximum(tnrm[..., 2], 0.25)
    tlen = np.sqrt(np.sum(tnrm * tnrm, axis=-1, keepdims=True))
    tnrm = tnrm / np.maximum(tlen, 1e-6)
    tray_nrm_img = Image.fromarray(np.clip((tnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    tray_ao = np.clip(0.75 * tr_orm[..., 0] + 0.25 * rs_orm[..., 0], 60, 255).astype(np.uint8)
    tray_rough = np.clip(0.70 * tr_orm[..., 1] + 0.30 * rs_orm[..., 1], 115, 220).astype(np.uint8)
    tray_metal = np.clip(0.65 * tr_orm[..., 2] + 0.35 * 140.0, 75, 220).astype(np.uint8)

    # 2. Tubular frame & wheel hub (oxidized painted dark red/rust steel)
    fr_alb = _load_fit(MAT_RUST / "rusted_steel_albedo.png", frame_w, TEX_SIZE, "RGB")
    fr_nrm = _load_fit(MAT_RUST / "rusted_steel_normal.png", frame_w, TEX_SIZE, "RGB")
    fr_orm = _load_fit(MAT_RUST / "rusted_steel_orm.png", frame_w, TEX_SIZE, "RGB")
    fr_paint = _load_fit(MAT_TRAY / "chipped_red_enamel_metal_albedo.png", frame_w, TEX_SIZE, "RGB")

    frame_alb = 0.60 * fr_alb + 0.40 * fr_paint
    frame_alb *= 0.85
    frame_alb_img = Image.fromarray(np.clip(frame_alb, 30, 200).astype(np.uint8), mode="RGB")

    fnrm = fr_nrm / 255.0 * 2.0 - 1.0
    fnrm[..., 2] = np.maximum(fnrm[..., 2], 0.25)
    flen = np.sqrt(np.sum(fnrm * fnrm, axis=-1, keepdims=True))
    fnrm = fnrm / np.maximum(flen, 1e-6)
    frame_nrm_img = Image.fromarray(np.clip((fnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    frame_ao = np.clip(fr_orm[..., 0], 65, 255).astype(np.uint8)
    frame_rough = np.clip(fr_orm[..., 1], 125, 225).astype(np.uint8)
    frame_metal = np.full((TEX_SIZE, frame_w), 205, dtype=np.uint8)

    # 3. Pneumatic rubber tire & grips
    rb_alb = _load_fit(MAT_RUBBER / "ribbed_black_cable_rubber_albedo.png", tire_w, TEX_SIZE, "RGB")
    rb_nrm = _load_fit(MAT_RUBBER / "ribbed_black_cable_rubber_normal.png", tire_w, TEX_SIZE, "RGB")
    rb_orm = _load_fit(MAT_RUBBER / "ribbed_black_cable_rubber_orm.png", tire_w, TEX_SIZE, "RGB")

    tire_alb_img = Image.fromarray(np.clip(rb_alb * 0.85, 30, 120).astype(np.uint8), mode="RGB")
    rnrm = rb_nrm / 255.0 * 2.0 - 1.0
    rnrm[..., 2] = np.maximum(rnrm[..., 2], 0.3)
    rlen = np.sqrt(np.sum(rnrm * rnrm, axis=-1, keepdims=True))
    rnrm = rnrm / np.maximum(rlen, 1e-6)
    tire_nrm_img = Image.fromarray(np.clip((rnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    tire_ao = np.clip(rb_orm[..., 0], 65, 255).astype(np.uint8)
    tire_rough = np.clip(rb_orm[..., 1], 175, 238).astype(np.uint8)
    tire_metal = np.zeros((TEX_SIZE, tire_w), dtype=np.uint8)

    def _stitch3(a: Image.Image, b: Image.Image, c: Image.Image, mode: str) -> Image.Image:
        canvas = Image.new(mode, (TEX_SIZE, TEX_SIZE))
        canvas.paste(a, (0, 0))
        canvas.paste(b, (u1_px, 0))
        canvas.paste(c, (u2_px, 0))
        return canvas

    albedo_atlas = _stitch3(tray_alb_img, frame_alb_img, tire_alb_img, "RGB")
    normal_atlas = _stitch3(tray_nrm_img, frame_nrm_img, tire_nrm_img, "RGB")
    ao_atlas = _stitch3(
        Image.fromarray(tray_ao, mode="L"),
        Image.fromarray(frame_ao, mode="L"),
        Image.fromarray(tire_ao, mode="L"),
        "L",
    )
    rough_atlas = _stitch3(
        Image.fromarray(tray_rough, mode="L"),
        Image.fromarray(frame_rough, mode="L"),
        Image.fromarray(tire_rough, mode="L"),
        "L",
    )
    metal_atlas = _stitch3(
        Image.fromarray(tray_metal, mode="L"),
        Image.fromarray(frame_metal, mode="L"),
        Image.fromarray(tire_metal, mode="L"),
        "L",
    )

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
    """Build metal_wheelbarrow geometry in Blender, UV-pack atlas, and export GLB."""
    import bmesh
    import bpy
    from mathutils import Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).resolve()), "--textures"],
            check=True,
        )

    clean_scene()
    bm = bmesh.new()

    def add_tube_polyline(
        pts: list[tuple[float, float, float]],
        radius: float,
        sides: int,
        tag: int,
        closed: bool = False,
    ) -> None:
        rings: list[list[bmesh.types.BMVert]] = []
        n = len(pts)
        for i, p in enumerate(pts):
            pv = Vector(p)
            if closed:
                t = (Vector(pts[(i + 1) % n]) - Vector(pts[(i - 1) % n])).normalized()
            elif i == 0:
                t = (Vector(pts[1]) - pv).normalized()
            elif i == n - 1:
                t = (pv - Vector(pts[-2])).normalized()
            else:
                t = (Vector(pts[i + 1]) - Vector(pts[i - 1])).normalized()

            ref = Vector((0.0, 0.0, 1.0)) if abs(t.z) < 0.85 else Vector((1.0, 0.0, 0.0))
            u_ax = t.cross(ref).normalized()
            v_ax = t.cross(u_ax).normalized()
            ring = []
            for s in range(sides):
                ang = (2.0 * math.pi * s) / sides
                offset = (u_ax * math.cos(ang) + v_ax * math.sin(ang)) * radius
                ring.append(bm.verts.new(pv + offset))
            rings.append(ring)

        seg_count = n if closed else n - 1
        for i in range(seg_count):
            j = (i + 1) % n
            for s in range(sides):
                sn = (s + 1) % sides
                f = bm.faces.new((rings[i][s], rings[i][sn], rings[j][sn], rings[j][s]))
                f.material_index = tag

        if not closed:
            f0 = bm.faces.new(list(reversed(rings[0])))
            f0.material_index = tag
            f1 = bm.faces.new(rings[-1])
            f1.material_index = tag

    # Orientation: X = length (-X front wheel nose, +X rear handles), Y = width, Z = height [0..0.68]
    # Front pneumatic wheel centered at x=-0.51, y=0.0, z=0.19 (R_outer = 0.19 -> touches z=0.0)
    wheel_cx = -0.51
    wheel_cz = 0.19
    tire_major_r = 0.145
    tire_minor_r = 0.045

    # 1. Front pneumatic rubber tire (torus along X-Z plane, tag=2 rubber)
    n_maj = 14
    n_min = 8
    tire_rings: list[list[bmesh.types.BMVert]] = []
    for i in range(n_maj):
        ang = (2.0 * math.pi * i) / n_maj
        ca, sa = math.cos(ang), math.sin(ang)
        cx_r = wheel_cx + ca * tire_major_r
        cz_r = wheel_cz + sa * tire_major_r
        ring = []
        for j in range(n_min):
            phi = (2.0 * math.pi * j) / n_min
            cp, sp = math.cos(phi), math.sin(phi)
            vx = cx_r + ca * cp * tire_minor_r
            vy = sp * tire_minor_r * 1.15
            vz = cz_r + sa * cp * tire_minor_r
            ring.append(bm.verts.new((vx, vy, vz)))
        tire_rings.append(ring)

    for i in range(n_maj):
        inext = (i + 1) % n_maj
        for j in range(n_min):
            jnext = (j + 1) % n_min
            f = bm.faces.new((
                tire_rings[i][j],
                tire_rings[inext][j],
                tire_rings[inext][jnext],
                tire_rings[i][jnext],
            ))
            f.material_index = 2

    # Steel wheel rim & axle hub (tag=1 frame)
    rim_r = 0.105
    rim_w = 0.036
    rim_l = []
    rim_r_verts = []
    for i in range(10):
        ang = (2.0 * math.pi * i) / 10
        vx = wheel_cx + math.cos(ang) * rim_r
        vz = wheel_cz + math.sin(ang) * rim_r
        rim_l.append(bm.verts.new((vx, -rim_w, vz)))
        rim_r_verts.append(bm.verts.new((vx, +rim_w, vz)))
    bm.faces.new(list(reversed(rim_l))).material_index = 1
    bm.faces.new(rim_r_verts).material_index = 1
    for i in range(10):
        j = (i + 1) % 10
        bm.faces.new((rim_l[i], rim_l[j], rim_r_verts[j], rim_r_verts[i])).material_index = 1

    # Axle shaft across forks
    add_tube_polyline([(wheel_cx, -0.11, wheel_cz), (wheel_cx, +0.11, wheel_cz)], 0.012, 6, tag=1)

    # 2. Dented painted steel tray (tag=0)
    # Build outer & inner shell profiles with subtle dented distortion for authentic wear
    # Bottom pan: x in [-0.36, +0.26], y half-width 0.175, z ~ 0.28..0.34
    # Rim: x in [-0.56, +0.34], y half-width 0.295, z ~ 0.65..0.68
    n_u = 4  # along X
    n_v = 3  # across Y
    floor_grid_out: list[list[bmesh.types.BMVert]] = []
    floor_grid_in: list[list[bmesh.types.BMVert]] = []
    wall_t = 0.012
    for iu in range(n_u + 1):
        fu = iu / float(n_u)
        px = -0.34 + fu * 0.60
        pz_base = 0.29 + fu * 0.045
        row_out = []
        row_in = []
        for iv in range(n_v + 1):
            fv = iv / float(n_v)
            py = -0.17 + fv * 0.34
            # Subtle organic dent on floor
            dent = -0.010 * math.sin(fu * math.pi * 2.0) * math.sin(fv * math.pi)
            row_out.append(bm.verts.new((px, py, pz_base + dent)))
            row_in.append(bm.verts.new((px, py, pz_base + dent + wall_t)))
        floor_grid_out.append(row_out)
        floor_grid_in.append(row_in)

    for iu in range(n_u):
        for iv in range(n_v):
            bm.faces.new((
                floor_grid_out[iu][iv],
                floor_grid_out[iu][iv + 1],
                floor_grid_out[iu + 1][iv + 1],
                floor_grid_out[iu + 1][iv],
            )).material_index = 0
            bm.faces.new((
                floor_grid_in[iu][iv],
                floor_grid_in[iu + 1][iv],
                floor_grid_in[iu + 1][iv + 1],
                floor_grid_in[iu][iv + 1],
            )).material_index = 0

    # Perimeter ring of floor (14 verts CCW in X-Y from top view)
    def _floor_ring(grid: list[list[bmesh.types.BMVert]]) -> list[bmesh.types.BMVert]:
        pts: list[bmesh.types.BMVert] = []
        for iv in range(n_v + 1):
            pts.append(grid[0][iv])
        for iu in range(1, n_u + 1):
            pts.append(grid[iu][n_v])
        for iv in range(n_v - 1, -1, -1):
            pts.append(grid[n_u][iv])
        for iu in range(n_u - 1, 0, -1):
            pts.append(grid[iu][0])
        return pts

    f_ring_out = _floor_ring(floor_grid_out)
    f_ring_in = _floor_ring(floor_grid_in)

    # Matching top rim points (sloped chute front at x=-0.57, flared sides y=+-0.295, rear wall x=+0.34)
    # Build corresponding 14 rim coords
    rim_coords: list[tuple[float, float, float]] = []
    # Front edge (iu=0, iv=0..3)
    for iv in range(n_v + 1):
        fv = iv / float(n_v)
        py = -0.265 + fv * 0.530
        dent_r = -0.012 if iv == 1 else 0.0
        rim_coords.append((-0.57, py, 0.645 + dent_r))
    # +Y side (iu=1..4, iv=3)
    for iu in range(1, n_u + 1):
        fu = iu / float(n_u)
        px = -0.57 + fu * 0.91
        dent_y = -0.014 if iu == 2 else 0.0
        rim_coords.append((px, 0.295 + dent_y, 0.645 + fu * 0.035))
    # Rear edge (iu=4, iv=2..0)
    for iv in range(n_v - 1, -1, -1):
        fv = iv / float(n_v)
        py = -0.285 + fv * 0.570
        rim_coords.append((0.34, py, 0.680))
    # -Y side (iu=3..1, iv=0)
    for iu in range(n_u - 1, 0, -1):
        fu = iu / float(n_u)
        px = -0.57 + fu * 0.91
        dent_y = 0.012 if iu == 3 else 0.0
        rim_coords.append((px, -0.295 + dent_y, 0.645 + fu * 0.035))

    rim_out: list[bmesh.types.BMVert] = []
    rim_in: list[bmesh.types.BMVert] = []
    rim_lip: list[bmesh.types.BMVert] = []
    for rx, ry, rz in rim_coords:
        rim_in.append(bm.verts.new((rx, ry, rz)))
        # Slight rolled lip outward
        dx_out = -0.016 if rx < -0.4 else (0.014 if rx > 0.25 else 0.0)
        dy_out = 0.016 if ry > 0.1 else (-0.016 if ry < -0.1 else 0.0)
        rim_lip.append(bm.verts.new((rx + dx_out, ry + dy_out, rz)))
        rim_out.append(bm.verts.new((rx + dx_out, ry + dy_out, rz - 0.020)))

    n_perim = len(f_ring_out)
    for i in range(n_perim):
        j = (i + 1) % n_perim
        # Inner wall
        bm.faces.new((f_ring_in[i], rim_in[i], rim_in[j], f_ring_in[j])).material_index = 0
        # Top rolled lip
        bm.faces.new((rim_in[i], rim_lip[i], rim_lip[j], rim_in[j])).material_index = 0
        # Lip turn-down
        bm.faces.new((rim_lip[i], rim_out[i], rim_out[j], rim_lip[j])).material_index = 0
        # Outer wall
        bm.faces.new((rim_out[i], f_ring_out[i], f_ring_out[j], rim_out[j])).material_index = 0

    # 3. Tubular frame, long handles, twin rear legs & front wheel hoop (tag=1 frame, grips tag=2)
    for side in (-1.0, 1.0):
        # Main longitudinal rail from front axle fork -> under tray -> rear handle grip
        rail_pts = [
            (wheel_cx, side * 0.115, wheel_cz),
            (-0.34, side * 0.145, 0.275),
            (0.24, side * 0.200, 0.345),
            (0.55, side * 0.240, 0.485),
        ]
        add_tube_polyline(rail_pts, 0.014, 6, tag=1)

        # Rubber handle grip sleeve at rear end (tag=2)
        grip_pts = [
            (0.54, side * 0.238, 0.480),
            (0.71, side * 0.262, 0.560),
        ]
        add_tube_polyline(grip_pts, 0.019, 6, tag=2)

        # Twin rear U-loop support leg touching z=0.0 cleanly
        leg_pts = [
            (0.05, side * 0.180, 0.320),
            (0.14, side * 0.205, 0.015),
            (0.24, side * 0.215, 0.015),
            (0.32, side * 0.205, 0.365),
        ]
        add_tube_polyline(leg_pts, 0.013, 6, tag=1)

        # Front tray nose support strut
        add_tube_polyline(
            [(-0.36, side * 0.140, 0.270), (-0.49, side * 0.160, 0.550)],
            0.011,
            6,
            tag=1,
        )

    # Rear leg horizontal cross-brace + front bumper nose hoop
    add_tube_polyline([(0.19, -0.210, 0.130), (0.19, +0.210, 0.130)], 0.011, 6, tag=1)
    add_tube_polyline(
        [
            (wheel_cx, -0.115, wheel_cz),
            (-0.69, -0.095, 0.220),
            (-0.71, 0.0, 0.235),
            (-0.69, +0.095, 0.220),
            (wheel_cx, +0.115, wheel_cz),
        ],
        0.012,
        6,
        tag=1,
    )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    tray_faces = [f.index for f in bm.faces if f.material_index == 0]
    frame_faces = [f.index for f in bm.faces if f.material_index == 1]
    tire_faces = [f.index for f in bm.faces if f.material_index == 2]
    for f in bm.faces:
        f.material_index = 0

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
    nrm_node.inputs["Strength"].default_value = 0.85
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new(MESH_NAME, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")

    def _unwrap_region(face_indices: list[int], u_min: float, u_max: float, v_min: float, v_max: float) -> None:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for idx in face_indices:
            mesh.polygons[idx].select = True
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015)
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

    _unwrap_region(tray_faces, 0.015, TRAY_U_MAX - 0.015, 0.015, 0.985)
    _unwrap_region(frame_faces, TRAY_U_MAX + 0.015, FRAME_U_MAX - 0.015, 0.015, 0.985)
    _unwrap_region(tire_faces, FRAME_U_MAX + 0.015, 0.985, 0.015, 0.985)

    # Normalize exact height = 0.68m, length ~1.42m, center X/Y=0, min_z=0.0
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    cur_l = max(xs) - min(xs)
    cur_h = max(zs) - min(zs)
    sx = TARGET_L / cur_l
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
        "tri_budget": 1800,
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
