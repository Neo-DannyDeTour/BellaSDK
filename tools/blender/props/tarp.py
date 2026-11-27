"""Procedural Weathered Tarpaulin Sheet (tarp).

Generates a ~1.6m x 1.2m x 0.35m Post-Soviet Industrial Gothic folded/draped
olive-drab tarpaulin sheet with brass grommets and ripstop weave, ORM maps,
GLB, and asset_manifest.json.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/tarp.py
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

PROP_SLUG: str = "tarp"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TARGET_HEIGHT_M: float = 0.35
TRI_BUDGET: int = 1800


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


def _paint_tarpaulin(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.5), (18, 0.3), (48, 0.2)])
    mud = _fbm_noise(size, size, seed + 29, [(10, 0.45), (36, 0.55)])
    fine = _fbm_noise(size, size, seed + 53, [(64, 0.5), (192, 0.5)])

    olive = np.array([82.0, 92.0, 68.0], dtype=np.float32)
    faded = np.array([106.0, 114.0, 88.0], dtype=np.float32)
    dirt = np.array([76.0, 66.0, 52.0], dtype=np.float32)

    col = olive[None, None, :] * (1.0 - 0.5 * macro[..., None]) + faded[None, None, :] * (0.5 * macro[..., None])
    dirt_mask = np.clip((mud - 0.56) * 1.1, 0.0, 0.45)
    col = col * (1.0 - dirt_mask[..., None]) + dirt[None, None, :] * dirt_mask[..., None]
    col += (fine[..., None] - 0.5) * 10.0

    # Ripstop tarp grid weave
    yy, xx = np.mgrid[0:size, 0:size]
    grid_x = (xx % 16 == 0).astype(np.float32)
    grid_y = (yy % 16 == 0).astype(np.float32)
    weave = np.clip(grid_x + grid_y, 0.0, 1.0)
    col *= 1.0 - 0.06 * weave[..., None]

    metallic = np.zeros((size, size), dtype=np.float32)
    return np.clip(col, 30.0, 240.0), metallic


def _paint_brass(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(8, 0.5), (24, 0.5)])
    brass = np.array([148.0, 126.0, 74.0], dtype=np.float32)
    tarnish = np.array([86.0, 76.0, 52.0], dtype=np.float32)
    col = brass[None, None, :] * (1.0 - 0.45 * macro[..., None]) + tarnish[None, None, :] * (0.45 * macro[..., None])
    metallic = np.full((size, size), 0.78, dtype=np.float32)
    return np.clip(col, 30.0, 240.0), metallic


def generate_textures() -> None:
    """Synthesize weathered 1024x1024 PBR texture atlas and compile ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 1024
    half = atlas_size // 2

    q0_rgb, q0_met = _paint_tarpaulin(half, seed=141)
    q1_rgb, q1_met = _paint_brass(half, seed=241)

    albedo = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    albedo[0:half, 0:half] = q0_rgb
    albedo[0:half, half:atlas_size] = q1_rgb
    albedo[half:atlas_size, 0:half] = q0_rgb * 0.90
    albedo[half:atlas_size, half:atlas_size] = q0_rgb
    albedo = np.clip(albedo, 30.0, 240.0).astype(np.uint8)

    metallic = np.zeros((atlas_size, atlas_size), dtype=np.float32)
    metallic[0:half, 0:half] = q0_met
    metallic[0:half, half:atlas_size] = q1_met
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
            "fabric",
            "--base-roughness",
            "0.74",
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
    nrm_node.inputs["Strength"].default_value = 0.75
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _build_geometry() -> "bpy.types.Mesh":
    """Build draped/folded tarpaulin sheet with brass hem grommets."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    bm = bmesh.new()

    nx_verts = 20
    ny_verts = 15
    w = 1.60
    d = 1.20
    h = 0.35

    grid: list[list] = []
    for j in range(ny_verts):
        v_norm = j / (ny_verts - 1)  # 0..1
        vy = (v_norm - 0.5) * d
        row = []
        for i in range(nx_verts):
            u_norm = i / (nx_verts - 1)  # 0..1
            vx = (u_norm - 0.5) * w

            # Draped plateau over low supply stack with soft folded skirt edges
            dx = abs(u_norm - 0.5) * 2.0  # 0 at center, 1 at edge
            dy = abs(v_norm - 0.5) * 2.0
            edge_r = max(dx, dy)
            plateau = max(0.0, 1.0 - max(0.0, edge_r - 0.52) / 0.48)
            z = h * (plateau ** 1.45)

            # Diagonal & radial cloth folds
            fold = 0.022 * math.sin(vx * 7.5 + vy * 4.5) * (0.35 + 0.65 * edge_r)
            fold += 0.014 * math.cos(vx * 12.0 - vy * 9.0) * edge_r
            z = max(0.0, z + fold)

            # Slight irregular skirt silhouette
            sk_x = vx + 0.03 * math.sin(vy * 5.0) * edge_r
            sk_y = vy + 0.03 * math.cos(vx * 4.5) * edge_r
            row.append(bm.verts.new(Vector((sk_x, sk_y, z))))
        grid.append(row)

    tarp_faces = []
    for j in range(ny_verts - 1):
        for i in range(nx_verts - 1):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.material_index = 0
            f.smooth = True
            tarp_faces.append(f)

    # Brass grommet eyelets along lower perimeter skirt (region 1)
    grommet_pts = [
        (-0.74, -0.54), (-0.25, -0.57), (0.25, -0.56), (0.74, -0.54),
        (-0.74, 0.54), (-0.25, 0.56), (0.25, 0.57), (0.74, 0.54),
    ]
    for gx, gy in grommet_pts:
        ret = bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=8,
            radius1=0.020,
            radius2=0.020,
            depth=0.012,
            matrix=Matrix.Translation(Vector((gx, gy, 0.012))),
        )
        vset = set(ret["verts"])
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = 1
                f.smooth = False

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.verify()

    for f in bm.faces:
        if f.material_index == 0:
            for loop in f.loops:
                u = 0.02 + ((loop.vert.co.x + w * 0.55) / (w * 1.1)) * 0.46
                v_coord = 0.52 + ((loop.vert.co.y + d * 0.55) / (d * 1.1)) * 0.46
                loop[uv_layer].uv = (max(0.01, min(0.49, u)), max(0.51, min(0.99, v_coord)))
        else:
            for idx, loop in enumerate(f.loops):
                loop[uv_layer].uv = (0.55 + (0.1 if idx in (1, 2) else 0.0), 0.55 + (0.1 if idx in (2, 3) else 0.0))
        f.material_index = 0

    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def build_prop() -> None:
    """Build tarp GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh = _build_geometry()
    obj = bpy.data.objects.new("tarp", mesh)
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
        "target_layer": "Layer 1 Environment",
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
