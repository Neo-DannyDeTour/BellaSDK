"""Procedural Small Industrial Wire/Cable Spool + PBR ORMMaterial3D.

Dimensions: ~0.45m diameter x 0.35m height.
Origin: bottom-center (min_z = 0.0 in Blender -> min_y = 0.0 in Godot).
Tri budget: <= 1200 tris.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/spool.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/spool.py --gen-textures
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

PROP_SLUG: str = "spool"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TRI_BUDGET: int = 1200

RADIUS: float = 0.225
HEIGHT: float = 0.35
SEGMENTS: int = 16


def _fbm_noise(h: int, w: int, seed: int, octaves: list[tuple[int, float]]) -> "np.ndarray":
    """Generate smooth multi-octave 2D value noise in [0, 1] using numpy + PIL."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    weight_sum = 0.0
    for grid, weight in octaves:
        low = rng.random((max(2, grid), max(2, grid)), dtype=np.float32)
        img = Image.fromarray((low * 255.0).astype(np.uint8), mode="L")
        up = np.asarray(img.resize((w, h), resample=Image.Resampling.BICUBIC), dtype=np.float32) / 255.0
        acc += up * weight
        weight_sum += weight
    return np.clip(acc / max(weight_sum, 1e-6), 0.0, 1.0)


def _paint_quadrant(
    size: int,
    base_rgb: tuple[int, int, int],
    fade_rgb: tuple[int, int, int],
    rust_rgb: tuple[int, int, int],
    bare_rgb: tuple[int, int, int],
    seed: int,
    rust_thresh: float = 0.60,
    base_metallic: float = 0.16,
) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize weathered industrial steel/rubber quadrant."""
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.50), (18, 0.35), (48, 0.15)])
    detail = _fbm_noise(size, size, seed + 17, [(28, 0.45), (88, 0.35), (190, 0.20)])

    rgb = np.zeros((size, size, 3), dtype=np.float32)
    for c in range(3):
        rgb[..., c] = base_rgb[c] * (1.0 - macro * 0.40) + fade_rgb[c] * (macro * 0.40)

    rust_score = 0.65 * macro + 0.35 * detail
    rust_mask = np.clip((rust_score - rust_thresh) / max(1.0 - rust_thresh, 1e-4), 0.0, 1.0)
    for c in range(3):
        rgb[..., c] = rgb[..., c] * (1.0 - rust_mask) + rust_rgb[c] * rust_mask

    chip = (detail > 0.80) & (rust_score < rust_thresh + 0.05)
    for c in range(3):
        rgb[..., c] = np.where(chip, bare_rgb[c] * (0.85 + 0.3 * detail), rgb[..., c])

    rgb = rgb * (0.90 + 0.16 * detail[..., None])
    metallic = np.full((size, size), base_metallic, dtype=np.float32)
    metallic = np.where(rust_mask > 0.35, 0.05, metallic)
    metallic = np.where(chip, 0.80, metallic)
    return np.clip(rgb, 30.0, 240.0), np.clip(metallic, 0.0, 1.0)


def generate_textures() -> None:
    """Synthesize 1024x1024 weathered cable spool PBR atlas + ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 1024
    half = atlas_size // 2

    # Q0 (Top-Left): Weathered olive/gray painted steel flanges
    q0_rgb, q0_met = _paint_quadrant(
        half,
        base_rgb=(84, 88, 72),
        fade_rgb=(106, 106, 86),
        rust_rgb=(96, 46, 24),
        bare_rgb=(112, 114, 116),
        seed=109,
        rust_thresh=0.58,
        base_metallic=0.20,
    )
    # Q1 (Top-Right): Matte black rubberized wound cable
    q1_rgb, q1_met = _paint_quadrant(
        half,
        base_rgb=(38, 40, 42),
        fade_rgb=(54, 54, 52),
        rust_rgb=(62, 56, 48),
        bare_rgb=(64, 66, 68),
        seed=209,
        rust_thresh=0.72,
        base_metallic=0.0,
    )
    # Q2 (Bottom-Left): Galvanized steel arbor hub & bolts
    q2_rgb, q2_met = _paint_quadrant(
        half,
        base_rgb=(122, 126, 128),
        fade_rgb=(140, 142, 144),
        rust_rgb=(94, 48, 26),
        bare_rgb=(148, 152, 154),
        seed=309,
        rust_thresh=0.68,
        base_metallic=0.80,
    )
    # Q3 (Bottom-Right): Same as Q0 for spare
    q3_rgb, q3_met = q0_rgb.copy(), q0_met.copy()

    albedo = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    albedo[0:half, 0:half] = q0_rgb
    albedo[0:half, half:atlas_size] = q1_rgb
    albedo[half:atlas_size, 0:half] = q2_rgb
    albedo[half:atlas_size, half:atlas_size] = q3_rgb
    albedo = np.clip(albedo, 30.0, 240.0).astype(np.uint8)

    metallic = np.zeros((atlas_size, atlas_size), dtype=np.float32)
    metallic[0:half, 0:half] = q0_met
    metallic[0:half, half:atlas_size] = q1_met
    metallic[half:atlas_size, 0:half] = q2_met
    metallic[half:atlas_size, half:atlas_size] = q3_met
    metallic_u8 = np.clip(metallic * 255.0, 0.0, 255.0).astype(np.uint8)

    albedo_path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    metallic_path = TEX_DIR / f"{PROP_SLUG}_metallic_tmp.png"
    Image.fromarray(albedo, mode="RGB").save(albedo_path, format="PNG")
    Image.fromarray(metallic_u8, mode="L").save(metallic_path, format="PNG")

    process_pbr = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"
    subprocess.run(
        [
            sys.executable,
            str(process_pbr),
            "derive-maps",
            str(albedo_path),
            "--out-dir",
            str(TEX_DIR),
            "--slug",
            PROP_SLUG,
            "--preset",
            "metal",
            "--base-roughness",
            "0.68",
            "--normal-strength",
            "1.9",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEX_DIR / f"{PROP_SLUG}_ao.png"
    rough_path = TEX_DIR / f"{PROP_SLUG}_roughness.png"
    normal_path = TEX_DIR / f"{PROP_SLUG}_normal.png"
    orm_path = TEX_DIR / f"{PROP_SLUG}_orm.png"
    tres_path = ASSET_DIR / f"{PROP_SLUG}.tres"

    subprocess.run(
        [
            sys.executable,
            str(process_pbr),
            "pack-orm",
            "--ao",
            str(ao_path),
            "--roughness",
            str(rough_path),
            "--metallic",
            str(metallic_path),
            "--output",
            str(orm_path),
        ],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(process_pbr),
            "build-tres",
            "--name",
            PROP_SLUG,
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

    for tmp in (metallic_path, TEX_DIR / f"{PROP_SLUG}_height.png", ao_path, rough_path):
        tmp.unlink(missing_ok=True)
    print(f"[Textures] Generated PBR maps + {tres_path.relative_to(REPO_ROOT)}")


def _ensure_textures_exist() -> None:
    required = [
        TEX_DIR / f"{PROP_SLUG}_albedo.png",
        TEX_DIR / f"{PROP_SLUG}_normal.png",
        TEX_DIR / f"{PROP_SLUG}_orm.png",
        ASSET_DIR / f"{PROP_SLUG}.tres",
    ]
    if all(p.is_file() for p in required):
        return
    venv_py = REPO_ROOT / ".venv" / "bin" / "python"
    py_bin = str(venv_py) if venv_py.is_file() else sys.executable
    subprocess.run([py_bin, str(Path(__file__).resolve()), "--gen-textures"], check=True)


def _create_atlas_material() -> "bpy.types.Material":
    import bpy

    mat = bpy.data.materials.new(name=f"M_{PROP_SLUG}")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (520, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (200, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.location = (-360, 260)
    img_alb = bpy.data.images.load(str(TEX_DIR / f"{PROP_SLUG}_albedo.png"), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-360, 0)
    img_orm = bpy.data.images.load(str(TEX_DIR / f"{PROP_SLUG}_orm.png"), check_existing=True)
    img_orm.colorspace_settings.name = "Non-Color"
    tex_orm.image = img_orm

    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-100, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-360, -260)
    img_nrm = bpy.data.images.load(str(TEX_DIR / f"{PROP_SLUG}_normal.png"), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm

    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -260)
    nrm_node.inputs["Strength"].default_value = 0.70
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _build_geometry() -> "bpy.types.Mesh":
    """Construct small industrial wire/cable spool with ribbed wound cable and steel hub."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    bm = bmesh.new()

    flange_h = 0.026
    coil_z0 = flange_h
    coil_z1 = HEIGHT - flange_h
    num_coils = 8
    coil_pitch = (coil_z1 - coil_z0) / num_coils
    r_coil_out = 0.180
    r_coil_in = 0.164

    profile: list[tuple[float, float, int]] = [
        (0.0, 0.0, 2),
        (0.055, 0.0, 2),
        (0.055, 0.002, 0),
        (RADIUS - 0.006, 0.0, 0),
        (RADIUS, 0.006, 0),
        (RADIUS, flange_h - 0.004, 0),
        (RADIUS - 0.004, flange_h, 0),
        (r_coil_in, coil_z0, 1),
    ]
    for i in range(num_coils):
        cz0 = coil_z0 + i * coil_pitch
        cz_mid = cz0 + coil_pitch * 0.5
        cz1 = cz0 + coil_pitch
        profile.append((r_coil_out, cz_mid, 1))
        profile.append((r_coil_in, cz1, 1))

    profile.extend([
        (RADIUS - 0.004, coil_z1, 0),
        (RADIUS, coil_z1 + 0.004, 0),
        (RADIUS, HEIGHT - 0.006, 0),
        (RADIUS - 0.006, HEIGHT, 0),
        (0.055, HEIGHT - 0.002, 0),
        (0.055, HEIGHT, 2),
        (0.0, HEIGHT, 2),
    ])

    rings: list[list[bmesh.types.BMVert]] = []
    bot_center = bm.verts.new((0.0, 0.0, profile[0][1]))
    top_center = bm.verts.new((0.0, 0.0, profile[-1][1]))
    ring_pts = profile[1:-1]

    for i in range(SEGMENTS):
        ang = (2.0 * math.pi * i) / SEGMENTS
        ca, sa = math.cos(ang), math.sin(ang)
        ring = [bm.verts.new((ca * r, sa * r, z)) for r, z, _ in ring_pts]
        rings.append(ring)

    for i in range(SEGMENTS):
        ni = (i + 1) % SEGMENTS
        fb = bm.faces.new((bot_center, rings[ni][0], rings[i][0]))
        fb.material_index = 2
        fb.smooth = False
        ft = bm.faces.new((top_center, rings[i][-1], rings[ni][-1]))
        ft.material_index = 2
        ft.smooth = False
        for j in range(len(ring_pts) - 1):
            f = bm.faces.new((rings[i][j], rings[ni][j], rings[ni][j + 1], rings[i][j + 1]))
            f.material_index = ring_pts[j][2]
            f.smooth = True

    # 4 Tie-rod bolt heads on top & bottom flanges (region 2)
    for k in range(4):
        ang = (2.0 * math.pi * k) / 4.0 + math.pi * 0.25
        bx, by = math.cos(ang) * 0.115, math.sin(ang) * 0.115
        for bz in (HEIGHT + 0.004, 0.004):
            ret = bmesh.ops.create_cone(
                bm, cap_ends=True, cap_tris=False, segments=6, radius1=0.012, radius2=0.012, depth=0.010
            )
            verts = ret["verts"]
            bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((bx, by, bz))), verts=verts)
            vset = set(verts)
            for f in bm.faces:
                if all(v in vset for v in f.verts):
                    f.material_index = 2
                    f.smooth = False

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(3):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh


def _unwrap_quadrants_and_merge_material(obj: "bpy.types.Object", final_mat: "bpy.types.Material") -> None:
    """Smart-project each material region into its own non-overlapping UV quadrant."""
    import bmesh
    import bpy

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    quads = {
        0: (0.02, 0.48, 0.52, 0.98),
        1: (0.52, 0.98, 0.52, 0.98),
        2: (0.02, 0.48, 0.02, 0.48),
    }

    for region_id, (u0, u1, v0, v1) in quads.items():
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")

        for poly in obj.data.polygons:
            if poly.material_index == region_id:
                poly.select = True

        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
        bpy.ops.object.mode_set(mode="OBJECT")

        bm = bmesh.new()
        bm.from_mesh(obj.data)
        uv_layer = bm.loops.layers.uv.verify()
        for f in bm.faces:
            if f.material_index != region_id:
                continue
            for loop in f.loops:
                uv = loop[uv_layer].uv
                loop[uv_layer].uv = (u0 + uv.x * (u1 - u0), v0 + uv.y * (v1 - v0))
        bm.to_mesh(obj.data)
        bm.free()

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(obj.data)
    bm.free()

    obj.data.materials.clear()
    obj.data.materials.append(final_mat)


def build_prop() -> None:
    """Build spool GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh = _build_geometry()
    obj = bpy.data.objects.new(PROP_SLUG, mesh)
    bpy.context.collection.objects.link(obj)

    final_mat = _create_atlas_material()
    _unwrap_quadrants_and_merge_material(obj, final_mat)

    coords = [v.co for v in obj.data.vertices]
    min_z, max_z = min(c.z for c in coords), max(c.z for c in coords)
    scale_f = HEIGHT / max(max_z - min_z, 1e-5)
    for v in obj.data.vertices:
        v.co.x *= scale_f
        v.co.y *= scale_f
        v.co.z = (v.co.z - min_z) * scale_f
    obj.data.update()

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    tri_count = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    dims = obj.dimensions
    godot_dims = [round(float(dims.x), 4), round(float(dims.z), 4), round(float(dims.y), 4)]

    glb_path = ASSET_DIR / f"{PROP_SLUG}.glb"
    export_godot_glb(glb_path, export_animations=False, apply_modifiers=True)

    manifest = {
        "prop_slug": PROP_SLUG,
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": godot_dims,
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "CylinderShape3D",
        "generator": "procedural_bpy",
        "tri_budget": TRI_BUDGET,
        "material": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.tres",
        "mesh": f"res://assets/models/{PROP_SLUG}/{PROP_SLUG}.glb",
    }
    (ASSET_DIR / "asset_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[OK] {PROP_SLUG}: tris={tri_count}/{TRI_BUDGET}, dims_m={godot_dims}, uv_layers={len(obj.data.uv_layers)}")


if __name__ == "__main__":
    if "--gen-textures" in sys.argv:
        generate_textures()
    else:
        build_prop()
