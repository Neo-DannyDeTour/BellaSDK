"""Procedural Weathered Blue/Gray HDPE Chemical Drum (Plastic Barrel) + PBR ORMMaterial3D.

Dimensions: ~0.58m diameter x 0.90m height.
Origin: bottom-center (min_z = 0.0 in Blender -> min_y = 0.0 in Godot).
Tri budget: <= 1500 tris.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/plastic_barrel.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/plastic_barrel.py --gen-textures
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

PROP_SLUG: str = "plastic_barrel"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TRI_BUDGET: int = 1500

RADIUS: float = 0.29
HEIGHT: float = 0.90
SEGMENTS: int = 20


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


def _paint_hdpe_quadrant(
    size: int,
    base_rgb: tuple[int, int, int],
    fade_rgb: tuple[int, int, int],
    grime_rgb: tuple[int, int, int],
    scuff_rgb: tuple[int, int, int],
    seed: int,
) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize weathered sun-faded HDPE plastic with scuffs and grime."""
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.50), (16, 0.35), (48, 0.15)])
    detail = _fbm_noise(size, size, seed + 19, [(28, 0.45), (84, 0.35), (190, 0.20)])
    streak = _fbm_noise(size, size, seed + 41, [(5, 0.35), (40, 0.65)])
    col_prof = np.mean(streak, axis=0, keepdims=True)
    streaks = np.clip(0.60 * col_prof + 0.40 * streak, 0.0, 1.0)

    rgb = np.zeros((size, size, 3), dtype=np.float32)
    for c in range(3):
        rgb[..., c] = base_rgb[c] * (1.0 - macro * 0.45) + fade_rgb[c] * (macro * 0.45)

    grime = np.clip((streaks - 0.50) * 1.1, 0.0, 0.60)
    for c in range(3):
        rgb[..., c] = rgb[..., c] * (1.0 - grime) + grime_rgb[c] * grime

    scuff = detail > 0.78
    for c in range(3):
        rgb[..., c] = np.where(scuff, scuff_rgb[c] * (0.9 + 0.2 * detail), rgb[..., c])

    rgb = rgb * (0.92 + 0.14 * detail[..., None])
    metallic = np.zeros((size, size), dtype=np.float32)
    return np.clip(rgb, 30.0, 240.0), metallic


def _draw_chem_label(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize weathered blue HDPE band with faded chemical hazard label."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont

    rgb, metallic = _paint_hdpe_quadrant(
        size,
        base_rgb=(50, 78, 106),
        fade_rgb=(82, 106, 126),
        grime_rgb=(64, 60, 52),
        scuff_rgb=(112, 126, 138),
        seed=seed,
    )
    img = Image.fromarray(rgb.astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img)

    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    if not Path(font_path).is_file():
        font_path = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
    font_lg = ImageFont.truetype(font_path, int(size * 0.075)) if Path(font_path).is_file() else ImageFont.load_default()
    font_sm = ImageFont.truetype(font_path, int(size * 0.048)) if Path(font_path).is_file() else ImageFont.load_default()

    # Faded off-white/yellow chemical label patch on front
    x0, y0, x1, y1 = int(size * 0.28), int(size * 0.22), int(size * 0.72), int(size * 0.78)
    draw.rectangle([x0, y0, x1, y1], fill=(196, 188, 158), outline=(44, 42, 40), width=4)
    draw.rectangle([x0, y0, x1, int(y0 + size * 0.14)], fill=(178, 132, 44))
    draw.text((size * 0.50, y0 + size * 0.07), "ОПАСНО", fill=(36, 34, 32), font=font_sm, anchor="mm")
    draw.text((size * 0.50, size * 0.50), "ХИМИЯ", fill=(36, 34, 32), font=font_lg, anchor="mm")
    draw.text((size * 0.50, size * 0.65), "220 Л  HDPE", fill=(54, 52, 48), font=font_sm, anchor="mm")

    arr = np.asarray(img, dtype=np.float32)
    wear = _fbm_noise(size, size, seed + 55, [(14, 0.5), (46, 0.5)])
    arr = np.where(wear[..., None] > 0.72, rgb, arr)
    arr = arr * (0.90 + 0.16 * wear[..., None])
    return np.clip(arr, 30.0, 240.0), metallic


def generate_textures() -> None:
    """Synthesize 1024x1024 weathered HDPE chemical drum PBR atlas + ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 1024
    half = atlas_size // 2

    # Q0 (Top-Left): Sun-faded industrial blue/gray HDPE body
    q0_rgb, q0_met = _paint_hdpe_quadrant(
        half,
        base_rgb=(48, 76, 104),
        fade_rgb=(80, 104, 124),
        grime_rgb=(64, 58, 48),
        scuff_rgb=(110, 124, 136),
        seed=105,
    )
    # Q1 (Top-Right): Darker blue/slate recessed grooves & domed top
    q1_rgb, q1_met = _paint_hdpe_quadrant(
        half,
        base_rgb=(40, 62, 86),
        fade_rgb=(64, 82, 100),
        grime_rgb=(54, 50, 44),
        scuff_rgb=(96, 108, 118),
        seed=205,
    )
    # Q2 (Bottom-Left): Matte black HDPE bung caps
    q2_rgb, q2_met = _paint_hdpe_quadrant(
        half,
        base_rgb=(44, 46, 48),
        fade_rgb=(62, 64, 66),
        grime_rgb=(52, 48, 42),
        scuff_rgb=(78, 80, 82),
        seed=305,
    )
    # Q3 (Bottom-Right): Chemical hazard label belly band
    q3_rgb, q3_met = _draw_chem_label(half, seed=405)

    albedo = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    albedo[0:half, 0:half] = q0_rgb
    albedo[0:half, half:atlas_size] = q1_rgb
    albedo[half:atlas_size, 0:half] = q2_rgb
    albedo[half:atlas_size, half:atlas_size] = q3_rgb
    albedo = np.clip(albedo, 30.0, 240.0).astype(np.uint8)

    metallic_u8 = np.zeros((atlas_size, atlas_size), dtype=np.uint8)

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
            "wood",
            "--base-roughness",
            "0.72",
            "--normal-strength",
            "1.8",
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
    nrm_node.inputs["Strength"].default_value = 0.65
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _build_geometry() -> "bpy.types.Mesh":
    """Construct blow-molded L-ring HDPE chemical drum with recessed top & bung caps."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    bm = bmesh.new()

    profile: list[tuple[float, float, int]] = [
        (0.0, 0.012, 1),
        (RADIUS - 0.04, 0.012, 1),
        (RADIUS - 0.03, 0.0, 1),
        (RADIUS - 0.01, 0.02, 0),
        (RADIUS, 0.06, 0),
        # Lower handling groove
        (RADIUS, 0.22, 0),
        (RADIUS - 0.016, 0.235, 1),
        (RADIUS - 0.016, 0.265, 1),
        (RADIUS, 0.280, 3),  # Center belly with chemical label
        # Slight barrel swell
        (RADIUS + 0.006, 0.450, 3),
        (RADIUS, 0.620, 0),
        # Upper handling groove & L-ring
        (RADIUS - 0.016, 0.635, 1),
        (RADIUS - 0.016, 0.665, 1),
        (RADIUS, 0.680, 0),
        (RADIUS, 0.810, 0),
        (RADIUS - 0.018, 0.855, 1),
        # Top L-ring rim
        (RADIUS - 0.010, 0.900, 1),
        (RADIUS - 0.042, 0.900, 1),
        (RADIUS - 0.052, 0.862, 1),
        (0.0, 0.862, 1),
    ]

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
        fb.material_index = 1
        fb.smooth = False
        ft = bm.faces.new((top_center, rings[i][-1], rings[ni][-1]))
        ft.material_index = 1
        ft.smooth = False
        for j in range(len(ring_pts) - 1):
            f = bm.faces.new((rings[i][j], rings[ni][j], rings[ni][j + 1], rings[i][j + 1]))
            f.material_index = ring_pts[j][2]
            f.smooth = True

    # 2 Black HDPE screw bung caps on top (region 2)
    for bx, by, br in ((0.125, 0.0, 0.036), (-0.125, 0.0, 0.026)):
        ret = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=8, radius1=br, radius2=br, depth=0.028
        )
        verts = ret["verts"]
        bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((bx, by, 0.876))), verts=verts)
        vset = set(verts)
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = 2
                f.smooth = False

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh


def _unwrap_quadrants_and_merge_material(obj: "bpy.types.Object", final_mat: "bpy.types.Material") -> None:
    """Smart-project structural regions and cylindrically project label band into Q3."""
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
    uv_layer = bm.loops.layers.uv.verify()
    z_min, z_max = 0.280, 0.620
    for f in bm.faces:
        if f.material_index != 3:
            continue
        angles = [math.atan2(loop.vert.co.y, loop.vert.co.x) for loop in f.loops]
        if max(angles) - min(angles) > math.pi:
            angles = [a + 2.0 * math.pi if a < 0.0 else a for a in angles]
        for loop, ang in zip(f.loops, angles):
            u = (ang + math.pi) / (2.0 * math.pi)
            v = (loop.vert.co.z - z_min) / (z_max - z_min)
            loop[uv_layer].uv = (0.52 + (u % 1.0) * 0.46, 0.02 + max(0.0, min(1.0, v)) * 0.46)

    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(obj.data)
    bm.free()

    obj.data.materials.clear()
    obj.data.materials.append(final_mat)


def build_prop() -> None:
    """Build plastic_barrel GLB and asset_manifest.json."""
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
