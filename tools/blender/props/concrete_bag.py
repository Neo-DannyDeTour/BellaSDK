"""Procedural 50kg Cement Sack (concrete_bag).

Generates a weathered 0.55m x 0.38m x 0.16m Post-Soviet Industrial Gothic
cement bag prop with pinched sewn ends, kraft paper texture, Cyrillic
"ЦЕМЕНТ М500" print, ORM maps, GLB, and asset_manifest.json.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/concrete_bag.py
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

PROP_SLUG: str = "concrete_bag"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TARGET_HEIGHT_M: float = 0.16
TRI_BUDGET: int = 1000


def _fbm_noise(h: int, w: int, seed: int, octaves: list[tuple[int, float]]) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    w_sum = 0.0
    for grid_res, weight in octaves:
        grid = rng.random((grid_res, grid_res), dtype=np.float32)
        img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
        up = img.resize((w, h), Image.Resampling.BILINEAR)
        acc += (np.asarray(up, dtype=np.float32) / 255.0) * weight
        w_sum += weight
    return np.clip(acc / max(w_sum, 1e-6), 0.0, 1.0)


def _paint_kraft_paper(size: int, seed: int) -> "np.ndarray":
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.5), (16, 0.3), (48, 0.2)])
    fine = _fbm_noise(size, size, seed + 19, [(64, 0.5), (192, 0.5)])
    dust = _fbm_noise(size, size, seed + 47, [(10, 0.45), (36, 0.55)])

    kraft = np.array([152.0, 134.0, 108.0], dtype=np.float32)
    faded = np.array([172.0, 158.0, 134.0], dtype=np.float32)
    cement = np.array([166.0, 166.0, 160.0], dtype=np.float32)

    col = kraft[None, None, :] * (1.0 - 0.45 * macro[..., None]) + faded[None, None, :] * (0.45 * macro[..., None])
    dust_mask = np.clip((dust - 0.52) * 1.1, 0.0, 0.55)
    col = col * (1.0 - dust_mask[..., None]) + cement[None, None, :] * dust_mask[..., None]
    col += (fine[..., None] - 0.5) * 14.0
    return np.clip(col, 30.0, 240.0)


def _draw_bag_front(size: int, seed: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont

    col = _paint_kraft_paper(size, seed)
    img = Image.fromarray(col.astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img)

    pad = int(size * 0.08)
    bw = max(4, int(size * 0.012))
    red_ink = (146, 52, 44)
    dark_ink = (42, 42, 40)

    draw.rectangle([pad, pad, size - pad, size - pad], outline=red_ink, width=bw)
    draw.rectangle([pad, int(size * 0.20), size - pad, int(size * 0.26)], fill=red_ink)
    draw.rectangle([pad, int(size * 0.74), size - pad, int(size * 0.80)], fill=dark_ink)

    font_path = "/usr/share/fonts/truetype/noto/NotoSans-CondensedBold.ttf"
    if not Path(font_path).is_file():
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
    font_lg = ImageFont.truetype(font_path, int(size * 0.11))
    font_md = ImageFont.truetype(font_path, int(size * 0.08))

    draw.text((size * 0.50, size * 0.42), "ЦЕМЕНТ", fill=dark_ink, font=font_lg, anchor="mm")
    draw.text((size * 0.50, size * 0.60), "М500  |  50 КГ", fill=red_ink, font=font_md, anchor="mm")

    arr = np.asarray(img, dtype=np.float32)
    cement_smudge = _fbm_noise(size, size, seed + 83, [(8, 0.5), (28, 0.5)])
    smudge_mask = np.clip((cement_smudge - 0.58) * 1.2, 0.0, 0.50)
    cement = np.array([172.0, 170.0, 164.0], dtype=np.float32)
    arr = arr * (1.0 - smudge_mask[..., None]) + cement[None, None, :] * smudge_mask[..., None]
    return np.clip(arr, 30.0, 240.0)


def generate_textures() -> None:
    """Synthesize weathered 1024x1024 PBR texture atlas and compile ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 1024
    half = atlas_size // 2

    q0_rgb = _draw_bag_front(half, seed=121)
    q1_rgb = _paint_kraft_paper(half, seed=221)
    q2_rgb = _paint_kraft_paper(half, seed=321) * 0.88
    q3_rgb = _paint_kraft_paper(half, seed=421)

    albedo = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    albedo[0:half, 0:half] = q0_rgb
    albedo[0:half, half:atlas_size] = q1_rgb
    albedo[half:atlas_size, 0:half] = q2_rgb
    albedo[half:atlas_size, half:atlas_size] = q3_rgb
    albedo = np.clip(albedo, 30.0, 240.0).astype(np.uint8)

    albedo_path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    Image.fromarray(albedo, mode="RGB").save(albedo_path, format="PNG")

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
            "fabric",
            "--base-roughness",
            "0.86",
            "--normal-strength",
            "1.4",
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
            "0.0",
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

    for tmp in (TEX_DIR / f"{PROP_SLUG}_height.png", ao_path, rough_path):
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
    nrm_node.inputs["Strength"].default_value = 0.65
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _build_geometry() -> "bpy.types.Mesh":
    """Build a subdivided pillowed cement sack with pinched sewn ends."""
    import bmesh
    import bpy

    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=4, use_grid_fill=True)

    half_x = 0.275
    half_y = 0.19
    half_z = 0.08

    for v in bm.verts:
        nx = v.co.x * 2.0  # -1..1
        ny = v.co.y * 2.0  # -1..1
        nz = v.co.z * 2.0  # -1..1

        # Pillow bulge in center, pinched flat along X ends (sewn sack seams)
        end_taper = max(0.18, 1.0 - 0.82 * (abs(nx) ** 3.2))
        side_bulge = 1.0 + 0.12 * (1.0 - nx * nx) * (1.0 - ny * ny)
        corner_flare = 1.0 + 0.08 * (abs(nx) ** 2.5) * (abs(ny) ** 1.5)

        x = nx * half_x
        y = ny * half_y * corner_flare
        z = nz * half_z * end_taper * side_bulge + half_z
        # Subtle organic lumpiness
        z += 0.004 * math.sin(nx * 5.0 + ny * 3.0)
        v.co = (x, y, z)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.verify()

    for f in bm.faces:
        f.smooth = True
        if f.normal.z > 0.45:
            # Top face -> Q0 front print (U:0.02..0.48, V:0.52..0.98)
            for loop in f.loops:
                u = 0.02 + ((loop.vert.co.x + half_x) / (2.0 * half_x)) * 0.46
                v_coord = 0.52 + ((loop.vert.co.y + half_y) / (2.0 * half_y)) * 0.46
                loop[uv_layer].uv = (max(0.01, min(0.49, u)), max(0.51, min(0.99, v_coord)))
        elif abs(f.normal.x) > 0.65:
            # Pinched sewn ends -> Q2 (U:0.02..0.48, V:0.02..0.48)
            for loop in f.loops:
                u = 0.02 + ((loop.vert.co.y + half_y) / (2.0 * half_y)) * 0.46
                v_coord = 0.02 + (loop.vert.co.z / (2.0 * half_z)) * 0.46
                loop[uv_layer].uv = (max(0.01, min(0.49, u)), max(0.01, min(0.49, v_coord)))
        else:
            # Bottom & sides -> Q1 kraft paper (U:0.52..0.98, V:0.52..0.98)
            for loop in f.loops:
                u = 0.52 + ((loop.vert.co.x + half_x) / (2.0 * half_x)) * 0.46
                v_coord = 0.52 + ((loop.vert.co.y + half_y) / (2.0 * half_y)) * 0.46
                loop[uv_layer].uv = (max(0.51, min(0.99, u)), max(0.51, min(0.99, v_coord)))

    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def build_prop() -> None:
    """Build concrete_bag GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh = _build_geometry()
    obj = bpy.data.objects.new("concrete_bag", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(_create_atlas_material())

    coords = [v.co for v in obj.data.vertices]
    min_x, max_x = min(c.x for c in coords), max(c.x for c in coords)
    min_y, max_y = min(c.y for c in coords), max(c.y for c in coords)
    min_z, max_z = min(c.z for c in coords), max(c.z for c in coords)
    scale_f = TARGET_HEIGHT_M / max(max_z - min_z, 1e-5)
    cx = 0.5 * (min_x + max_x)
    cy = 0.5 * (min_y + max_y)
    for v in obj.data.vertices:
        v.co.x = (v.co.x - cx) * scale_f
        v.co.y = (v.co.y - cy) * scale_f
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
        "collision_hint": "BoxShape3D",
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
