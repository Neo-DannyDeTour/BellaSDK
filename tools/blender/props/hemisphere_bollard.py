"""Procedural Chipped Yellow Concrete Hemisphere Anti-Parking Bollard.

Generates weathered concrete + chipped mustard-yellow paint PBR texture maps
via PIL/numpy + process_pbr.py, builds a watertight manifold concrete dome
grounded at min_z = 0 (Godot min_y = 0) with exact 0.28m height and clean
non-overlapping polar UVs, exports GLB with wired PBR textures, generates
Godot 4 ORMMaterial3D .tres, and writes asset_manifest.json.

Run:
    python3 tools/blender/run.py tools/blender/props/hemisphere_bollard.py
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "hemisphere_bollard"
TEXTURE_DIR: Path = ASSET_DIR / "textures"
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"
REFERENCE_IMAGE: str = "/home/dkd/Desktop/Refs/IMG_20261125_170140.jpg"

TARGET_HEIGHT_M: float = 0.28
BASE_RADIUS_M: float = 0.275
TRI_BUDGET: int = 1200
TEX_SIZE: int = 1024

# Polar UV layout constants (must match mesh UV projection exactly)
DOME_UV_CENTER: tuple[float, float] = (0.37, 0.50)
DOME_UV_RADIUS: float = 0.35
BOT_UV_CENTER: tuple[float, float] = (0.85, 0.50)
BOT_UV_RADIUS: float = 0.12


def _generate_textures() -> None:
    """Synthesize clamped [30..240] sRGB weathered painted concrete maps and .tres."""
    import numpy as np
    from PIL import Image, ImageFilter

    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(70140)
    h = TEX_SIZE
    w = TEX_SIZE

    def fbm_noise(scale_list: tuple[tuple[int, float], ...]) -> np.ndarray:
        acc = np.zeros((h, w), dtype=np.float32)
        total_wt = 0.0
        for grid_sz, wt in scale_list:
            coarse = rng.random((grid_sz, grid_sz), dtype=np.float32)
            img_c = Image.fromarray((coarse * 255.0).astype(np.uint8), mode="L")
            up = np.array(
                img_c.resize((w, h), Image.Resampling.BICUBIC), dtype=np.float32
            ) / 255.0
            acc += up * wt
            total_wt += wt
        return acc / max(total_wt, 1e-6)

    macro = fbm_noise(((6, 0.45), (16, 0.35), (48, 0.20)))
    med = fbm_noise(((32, 0.5), (96, 0.5)))
    fine = fbm_noise(((160, 0.55), (320, 0.45)))

    # Compute polar UV coordinates for every pixel (PIL y=0 -> v=1.0)
    px_x = (np.arange(w, dtype=np.float32) + 0.5) / w
    px_y = 1.0 - (np.arange(h, dtype=np.float32) + 0.5) / h
    uu, vv = np.meshgrid(px_x, px_y)

    du = uu - DOME_UV_CENTER[0]
    dv = vv - DOME_UV_CENTER[1]
    r_norm = np.sqrt(du * du + dv * dv) / DOME_UV_RADIUS  # 0 at apex, 1 at rim
    angle = np.arctan2(dv, du)

    # 1. Base weathered mustard-yellow traffic paint
    paint_base = np.array([202.0, 172.0, 72.0], dtype=np.float32)
    paint_col = paint_base[None, None, :] * (
        0.92 + 0.12 * macro[..., None] + 0.05 * (fine[..., None] - 0.5)
    )

    # 2. Soft chalky faded dust/abrasion patch on one side (matches pale wear in ref)
    ang_diff_chalk = np.arctan2(np.sin(angle - 2.4), np.cos(angle - 2.4))
    chalk_blob = np.exp(-(ang_diff_chalk ** 2) / 0.85) * np.exp(-((r_norm - 0.52) ** 2) / 0.14)
    scuff_zone = np.clip((chalk_blob + (macro - 0.5) * 0.35 - 0.15) * 1.4, 0.0, 1.0)
    chalk_col = np.array([174.0, 170.0, 160.0], dtype=np.float32) * (0.94 + 0.10 * fine[..., None])
    paint_col = paint_col * (1.0 - scuff_zone[..., None] * 0.72) + chalk_col * (scuff_zone[..., None] * 0.72)

    # 3. Soft organic tire/bumper rub smudges near the upper shoulder (zero sharp geometric edges)
    ang_diff_t1 = np.arctan2(np.sin(angle - 0.85), np.cos(angle - 0.85))
    ang_diff_t2 = np.arctan2(np.sin(angle + 0.45), np.cos(angle + 0.45))
    tire_blob_1 = np.exp(-(ang_diff_t1 ** 2) / 0.16) * np.exp(-((r_norm - 0.38) ** 2) / 0.028)
    tire_blob_2 = np.exp(-(ang_diff_t2 ** 2) / 0.09) * np.exp(-((r_norm - 0.46) ** 2) / 0.022)
    tire_blend = np.clip((np.maximum(tire_blob_1, tire_blob_2) * (0.7 + 0.6 * med) - 0.25) * 1.8, 0.0, 0.70)
    tire_col = np.array([86.0, 86.0, 78.0], dtype=np.float32) * (0.88 + 0.18 * fine[..., None])
    paint_col = paint_col * (1.0 - tire_blend[..., None]) + tire_col * tire_blend[..., None]

    # 4. Chipped concrete rim patches exposing dark grey raw concrete & aggregate
    ang_c1 = np.arctan2(np.sin(angle - 0.15), np.cos(angle - 0.15))
    ang_c2 = np.arctan2(np.sin(angle + 2.10), np.cos(angle + 2.10))
    ang_c3 = np.arctan2(np.sin(angle - 1.55), np.cos(angle - 1.55))
    chip_lobe_1 = np.exp(-(ang_c1 ** 2) / 0.12) * np.clip((r_norm - 0.76 + (macro - 0.5) * 0.22) * 4.5, 0.0, 1.0)
    chip_lobe_2 = np.exp(-(ang_c2 ** 2) / 0.09) * np.clip((r_norm - 0.80 + (med - 0.5) * 0.20) * 5.0, 0.0, 1.0)
    chip_lobe_3 = np.exp(-(ang_c3 ** 2) / 0.05) * np.clip((r_norm - 0.83 + (med - 0.5) * 0.18) * 5.5, 0.0, 1.0)
    chip_scatter = ((r_norm > 0.72) & (med > 0.77) & (fine > 0.62)).astype(np.float32) * 0.85
    chip_field = np.clip(np.maximum.reduce([chip_lobe_1, chip_lobe_2, chip_lobe_3, chip_scatter]), 0.0, 1.0)
    chip_mask = chip_field > 0.48

    concrete_base = np.array([92.0, 90.0, 86.0], dtype=np.float32)
    aggregate = (fine - 0.5) * 44.0 + (med - 0.5) * 20.0
    concrete_col = concrete_base[None, None, :] + aggregate[..., None]

    # Subtle weathered mortar transition ring at chip edges
    chip_edge = (chip_field > 0.34) & (~chip_mask)
    paint_col = np.where(
        chip_edge[..., None],
        paint_col * 0.60 + np.array([154.0, 148.0, 134.0], dtype=np.float32) * 0.40,
        paint_col,
    )
    albedo = np.where(chip_mask[..., None], concrete_col, paint_col)

    # 5. Ground-edge asphalt grime & very sparse concrete air-void pinholes
    rim_grime = np.clip((r_norm - 0.90) / 0.12, 0.0, 1.0) * 0.32
    albedo *= (1.0 - rim_grime[..., None])
    pinholes = (fine < 0.16) & (med < 0.36)
    albedo = np.where(pinholes[..., None], albedo * 0.74, albedo)

    # 6. Bottom cap UV island (u > 0.72) -> raw concrete underside
    bottom_region = uu > 0.72
    albedo = np.where(bottom_region[..., None], concrete_col, albedo)

    # Clamp strictly to [30, 240] sRGB
    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)
    alb_img = Image.fromarray(albedo_u8, mode="RGB").filter(ImageFilter.GaussianBlur(radius=0.35))
    alb_arr = np.clip(np.array(alb_img, dtype=np.uint8), 30, 240)

    albedo_path = TEXTURE_DIR / "hemisphere_bollard_albedo.png"
    Image.fromarray(alb_arr, mode="RGB").save(albedo_path, format="PNG")

    # Derive Normal (+Y), AO, Roughness using process_pbr.py (stone preset)
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "derive-maps",
            str(albedo_path),
            "--out-dir",
            str(TEXTURE_DIR),
            "--slug",
            "hemisphere_bollard",
            "--preset",
            "stone",
            "--normal-strength",
            "2.2",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEXTURE_DIR / "hemisphere_bollard_ao.png"
    rough_path = TEXTURE_DIR / "hemisphere_bollard_roughness.png"
    height_path = TEXTURE_DIR / "hemisphere_bollard_height.png"
    normal_path = TEXTURE_DIR / "hemisphere_bollard_normal.png"
    orm_path = TEXTURE_DIR / "hemisphere_bollard_orm.png"

    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "pack-orm",
            "--ao",
            str(ao_path),
            "--roughness",
            str(rough_path),
            "--metallic",
            "0.0",
            "--output",
            str(orm_path),
        ],
        check=True,
    )

    tres_path = ASSET_DIR / "hemisphere_bollard.tres"
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "build-tres",
            "--name",
            "hemisphere_bollard",
            "--albedo",
            str(albedo_path),
            "--normal",
            str(normal_path),
            "--orm",
            str(orm_path),
            "--output",
            str(tres_path),
        ],
        check=True,
    )

    for tmp in (ao_path, rough_path, height_path):
        tmp.unlink(missing_ok=True)


def _ensure_textures() -> None:
    required = [
        TEXTURE_DIR / "hemisphere_bollard_albedo.png",
        TEXTURE_DIR / "hemisphere_bollard_normal.png",
        TEXTURE_DIR / "hemisphere_bollard_orm.png",
        ASSET_DIR / "hemisphere_bollard.tres",
    ]
    if all(p.is_file() for p in required):
        return
    env = os.environ.copy()
    subprocess.run(["/usr/bin/python3", str(Path(__file__).resolve()), "--generate-textures"], env=env, check=True)


def _run_blender_build() -> None:
    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))

    import bmesh
    import bpy
    from mathutils import Vector
    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures()
    clean_scene()

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()

    segs = 28
    rings = 12  # ring 0 = ground rim (z=0), ring 1 = lip (z=0.014), rings 2..12 -> apex
    skirt_h = 0.012
    dome_h = TARGET_HEIGHT_M - skirt_h

    def dome_chip_offset(phi: float, theta: float) -> float:
        """Subtle deterministic cast-concrete irregularity + rim chips matching texture."""
        # Subtle organic casting waviness
        wobble = 0.0018 * math.sin(3.0 * phi + 0.5) * math.sin(theta * 2.0)
        # Rim chips aligned with texture chip angles (0.15, -2.10, 1.55 rad)
        rim_wt = max(0.0, (theta / (math.pi * 0.5) - 0.72) / 0.28)
        c1 = math.exp(-((math.atan2(math.sin(phi - 0.15), math.cos(phi - 0.15))) ** 2) / 0.10)
        c2 = math.exp(-((math.atan2(math.sin(phi + 2.10), math.cos(phi + 2.10))) ** 2) / 0.08)
        chip = 0.0065 * rim_wt * max(c1, c2)
        return wobble - chip

    # Build rings from bottom (r=0) up to near-apex (r=rings-1), then apex vertex
    ring_verts: list[list[bmesh.types.BMVert]] = []
    ring_thetas: list[float] = []

    for r in range(rings):
        if r == 0:
            z = 0.0
            rad = BASE_RADIUS_M
            theta = math.pi * 0.5
        elif r == 1:
            z = skirt_h
            rad = BASE_RADIUS_M * 0.996
            theta = math.pi * 0.5 * 0.95
        else:
            t = float(r - 1) / float(rings - 1)  # 0..1
            theta = (math.pi * 0.5) * (1.0 - t)
            z = skirt_h + dome_h * math.cos(theta)
            rad = BASE_RADIUS_M * math.sin(theta)

        ring_thetas.append(theta)
        verts_r = []
        for s in range(segs):
            phi = (2.0 * math.pi * s) / segs
            dr = dome_chip_offset(phi, theta) if r >= 1 else 0.0
            eff_r = max(0.005, rad + dr)
            v = bm.verts.new((eff_r * math.cos(phi), eff_r * math.sin(phi), z))
            verts_r.append(v)
        ring_verts.append(verts_r)

    apex_vert = bm.verts.new((0.0, 0.0, TARGET_HEIGHT_M))
    bot_center = bm.verts.new((0.0, 0.0, 0.0))

    # Helper to compute polar UV for a dome vertex
    def dome_uv(co: Vector) -> tuple[float, float]:
        r_xy = math.hypot(co.x, co.y)
        phi = math.atan2(co.y, co.x)
        # Map height & radius smoothly to normalized arc angle 0..1
        dz = max(0.0, min(1.0, (co.z - skirt_h) / max(dome_h, 1e-5)))
        theta_norm = math.acos(dz) / (math.pi * 0.5) if co.z >= skirt_h else 1.0
        if r_xy < 1e-5:
            return DOME_UV_CENTER
        r_uv = DOME_UV_RADIUS * theta_norm
        return (
            DOME_UV_CENTER[0] + r_uv * math.cos(phi),
            DOME_UV_CENTER[1] + r_uv * math.sin(phi),
        )

    # Create quad bands between consecutive rings
    for r in range(rings - 1):
        v_lo = ring_verts[r]
        v_hi = ring_verts[r + 1]
        for s in range(segs):
            sn = (s + 1) % segs
            f = bm.faces.new((v_lo[s], v_lo[sn], v_hi[sn], v_hi[s]))
            f.smooth = r >= 1
            for loop in f.loops:
                loop[uv_layer].uv = dome_uv(loop.vert.co)

    # Create triangle cap at apex
    top_ring = ring_verts[-1]
    for s in range(segs):
        sn = (s + 1) % segs
        f = bm.faces.new((top_ring[s], top_ring[sn], apex_vert))
        f.smooth = True
        for loop in f.loops:
            loop[uv_layer].uv = dome_uv(loop.vert.co)

    # Create closed flat manifold bottom cap mapped to non-overlapping BOT_UV_CENTER
    bot_ring = ring_verts[0]
    for s in range(segs):
        sn = (s + 1) % segs
        f = bm.faces.new((bot_ring[sn], bot_ring[s], bot_center))
        f.smooth = False
        for loop in f.loops:
            co = loop.vert.co
            r_xy = math.hypot(co.x, co.y)
            if r_xy < 1e-5:
                loop[uv_layer].uv = BOT_UV_CENTER
            else:
                phi = math.atan2(co.y, co.x)
                loop[uv_layer].uv = (
                    BOT_UV_CENTER[0] + BOT_UV_RADIUS * math.cos(phi),
                    BOT_UV_CENTER[1] + BOT_UV_RADIUS * math.sin(phi),
                )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Verify exact height & grounded min_z = 0
    zs = [v.co.z for v in bm.verts]
    min_z = min(zs)
    max_z = max(zs)
    scale_z = TARGET_HEIGHT_M / (max_z - min_z)
    for v in bm.verts:
        v.co.z = (v.co.z - min_z) * scale_z

    mesh = bpy.data.meshes.new("HemisphereBollard_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("HemisphereBollard", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Wire PBR textures into Principled BSDF
    mat = bpy.data.materials.new(name="Mat_HemisphereBollard")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (480, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (160, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.location = (-400, 280)
    tex_alb.image = bpy.data.images.load(str(TEXTURE_DIR / "hemisphere_bollard_albedo.png"), check_existing=True)
    tex_alb.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-400, 0)
    tex_orm.image = bpy.data.images.load(str(TEXTURE_DIR / "hemisphere_bollard_orm.png"), check_existing=True)
    tex_orm.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-120, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-400, -280)
    tex_nrm.image = bpy.data.images.load(str(TEXTURE_DIR / "hemisphere_bollard_normal.png"), check_existing=True)
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -280)
    nrm_node.inputs["Strength"].default_value = 0.80
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.append(mat)

    glb_path = ASSET_DIR / "hemisphere_bollard.glb"
    export_godot_glb(glb_path, export_animations=False)

    tri_count = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    assert tri_count <= TRI_BUDGET, f"Tri count {tri_count} exceeds budget {TRI_BUDGET}"
    assert len(obj.data.uv_layers) >= 1, "Missing UV layer"

    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs2 = [v.co.z for v in obj.data.vertices]
    dims_godot = [
        round(max(xs) - min(xs), 4),
        round(max(zs2) - min(zs2), 4),
        round(max(ys) - min(ys), 4),
    ]

    manifest = {
        "prop_slug": "hemisphere_bollard",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 1 Environment",
        "collision_hint": "ConvexPolygonShape3D",
        "generator": "procedural_bpy",
        "reference_image": REFERENCE_IMAGE,
        "materials": ["res://assets/models/hemisphere_bollard/hemisphere_bollard.tres"],
        "glb": "res://assets/models/hemisphere_bollard/hemisphere_bollard.glb",
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_HEMISPHERE_BOLLARD:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    if "--generate-textures" in sys.argv:
        _generate_textures()
    else:
        _run_blender_build()
