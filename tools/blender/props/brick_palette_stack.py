"""Procedural Post-Soviet Brick Pallet Stack (brick_palette_stack).

Generates a weathered ~1.20m x 1.00m x 1.10m wooden pallet stacked with
weathered red/clay bricks and steel strapping in Post-Soviet Industrial Gothic
style, with non-overlapping quadrant UVs, PBR textures via process_pbr.py,
Godot 4 ORMMaterial3D (.tres), GLB, and asset_manifest.json.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/brick_palette_stack.py
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

PROP_SLUG: str = "brick_palette_stack"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TARGET_HEIGHT_M: float = 1.10
TRI_BUDGET: int = 2500

SRC_BRICK_DIR: Path = REPO_ROOT / "assets" / "materials" / "weathered_clay_brick" / "textures"
SRC_WOOD_DIR: Path = REPO_ROOT / "assets" / "materials" / "weathered_deck_planks" / "textures"
SRC_RUST_DIR: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

PAL_W: float = 1.20
PAL_D: float = 1.00
PAL_H: float = 0.14


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def _make_clay_brick_stack_tex(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    import numpy as np

    alb = _load_square_rgb(SRC_BRICK_DIR / "weathered_clay_brick_albedo.png", size)
    nrm = _load_square_rgb(SRC_BRICK_DIR / "weathered_clay_brick_normal.png", size)
    rgh = _load_square_rgb(SRC_BRICK_DIR / "weathered_clay_brick_roughness.png", size)[..., 0] / 255.0

    # Deepen into dusty Post-Soviet terracotta/ochre clay brick
    col = alb * np.array([1.05, 0.92, 0.84], dtype=np.float32)[None, None, :]
    rough = np.clip(0.76 + rgh * 0.16, 0.72, 0.94)
    nrm_out = (nrm - 128.0) * 0.80 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm_out, 0.0, 255.0)


def _make_pallet_wood_tex(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    import numpy as np

    alb = _load_square_rgb(SRC_WOOD_DIR / "weathered_deck_planks_albedo.png", size)
    nrm = _load_square_rgb(SRC_WOOD_DIR / "weathered_deck_planks_normal.png", size)
    rgh = _load_square_rgb(SRC_WOOD_DIR / "weathered_deck_planks_roughness.png", size)[..., 0] / 255.0

    col = alb * np.array([0.88, 0.82, 0.72], dtype=np.float32)[None, None, :]
    rough = np.clip(0.78 + rgh * 0.14, 0.74, 0.92)
    nrm_out = (nrm - 128.0) * 0.70 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm_out, 0.0, 255.0)


def _make_strapping_steel_tex(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    import numpy as np

    alb = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_albedo.png", size)
    nrm = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_normal.png", size)
    dark = np.array([46.0, 48.0, 50.0], dtype=np.float32)
    col = alb * 0.35 + dark[None, None, :] * 0.65
    rough = np.full((size, size), 0.48, dtype=np.float32)
    nrm_out = (nrm - 128.0) * 0.50 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm_out, 0.0, 255.0)


def generate_textures() -> None:
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    q0_rgb, q0_rough, q0_nrm = _make_clay_brick_stack_tex(half)
    q0_met = np.full((half, half), 0.02, dtype=np.float32)

    q1_rgb, q1_rough, q1_nrm = _make_pallet_wood_tex(half)
    q1_met = np.full((half, half), 0.02, dtype=np.float32)

    q2_rgb, q2_rough, q2_nrm = _make_strapping_steel_tex(half)
    q2_met = np.full((half, half), 0.70, dtype=np.float32)

    q3_rgb = np.clip(q0_rgb * 0.86, 30.0, 240.0)
    q3_rough = q0_rough
    q3_nrm = q0_nrm
    q3_met = np.full((half, half), 0.02, dtype=np.float32)

    albedo = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    albedo[0:half, 0:half] = q0_rgb
    albedo[0:half, half:atlas_size] = q1_rgb
    albedo[half:atlas_size, 0:half] = q2_rgb
    albedo[half:atlas_size, half:atlas_size] = q3_rgb

    roughness = np.zeros((atlas_size, atlas_size), dtype=np.float32)
    roughness[0:half, 0:half] = q0_rough
    roughness[0:half, half:atlas_size] = q1_rough
    roughness[half:atlas_size, 0:half] = q2_rough
    roughness[half:atlas_size, half:atlas_size] = q3_rough

    metallic = np.zeros((atlas_size, atlas_size), dtype=np.float32)
    metallic[0:half, 0:half] = q0_met
    metallic[0:half, half:atlas_size] = q1_met
    metallic[half:atlas_size, 0:half] = q2_met
    metallic[half:atlas_size, half:atlas_size] = q3_met

    scanned_nrm = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    scanned_nrm[0:half, 0:half] = q0_nrm
    scanned_nrm[0:half, half:atlas_size] = q1_nrm
    scanned_nrm[half:atlas_size, 0:half] = q2_nrm
    scanned_nrm[half:atlas_size, half:atlas_size] = q3_nrm

    albedo_path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    rough_tmp_path = TEX_DIR / f"{PROP_SLUG}_rough_override_tmp.png"
    metal_tmp_path = TEX_DIR / f"{PROP_SLUG}_metallic_tmp.png"
    Image.fromarray(np.clip(albedo, 30.0, 240.0).astype(np.uint8), mode="RGB").save(albedo_path, format="PNG")
    Image.fromarray(np.clip(roughness * 255.0, 0.0, 255.0).astype(np.uint8), mode="L").save(rough_tmp_path, format="PNG")
    Image.fromarray(np.clip(metallic * 255.0, 0.0, 255.0).astype(np.uint8), mode="L").save(metal_tmp_path, format="PNG")

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
            "stone",
            "--base-roughness",
            "0.80",
            "--normal-strength",
            "1.3",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEX_DIR / f"{PROP_SLUG}_ao.png"
    normal_path = TEX_DIR / f"{PROP_SLUG}_normal.png"
    orm_path = TEX_DIR / f"{PROP_SLUG}_orm.png"
    tres_path = ASSET_DIR / f"{PROP_SLUG}.tres"

    derived_nrm = np.asarray(Image.open(normal_path).convert("RGB"), dtype=np.float32)
    blended_nrm = (derived_nrm - 128.0) * 0.30 + (scanned_nrm - 128.0) * 0.75 + 128.0
    Image.fromarray(np.clip(blended_nrm, 0.0, 255.0).astype(np.uint8), mode="RGB").save(normal_path, format="PNG")

    subprocess.run(
        [
            sys.executable,
            str(process_pbr),
            "pack-orm",
            "--ao",
            str(ao_path),
            "--roughness",
            str(rough_tmp_path),
            "--metallic",
            str(metal_tmp_path),
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

    for tmp in (
        rough_tmp_path,
        metal_tmp_path,
        TEX_DIR / f"{PROP_SLUG}_height.png",
        TEX_DIR / f"{PROP_SLUG}_roughness.png",
        ao_path,
    ):
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


def _add_box(bm: "bmesh.types.BMesh", center: "Vector", size: "Vector", region: int, bevel_w: float = 0.0) -> None:
    import bmesh
    from mathutils import Matrix

    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    mat = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    vset = set(verts)
    if bevel_w > 0.0:
        edges = [e for e in bm.edges if all(v in vset for v in e.verts)]
        b_ret = bmesh.ops.bevel(bm, geom=edges, offset=bevel_w, segments=1, affect="EDGES", clamp_overlap=True)
        for v in b_ret.get("verts", []):
            vset.add(v)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = region
            f.smooth = False


def _build_geometry() -> "bpy.types.Mesh":
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    # 1. Wooden Pallet (region 1)
    # 3 bottom runner boards along X
    for ry in (-0.42, 0.0, 0.42):
        _add_box(bm, Vector((0.0, ry, 0.012)), Vector((PAL_W, 0.12, 0.024)), region=1, bevel_w=0.002)
    # 9 spacer blocks
    for bx in (-0.52, 0.0, 0.52):
        for by in (-0.42, 0.0, 0.42):
            _add_box(bm, Vector((bx, by, 0.070)), Vector((0.12, 0.12, 0.092)), region=1, bevel_w=0.002)
    # 6 top deck boards along X
    for idx in range(6):
        dy = -0.42 + idx * (0.84 / 5.0)
        _add_box(bm, Vector((0.0, dy, 0.128)), Vector((PAL_W, 0.115, 0.024)), region=1, bevel_w=0.002)

    # 2. Stepped Brick Stack Tiers (region 0: clay brick)
    tier_h = 0.18
    tier_specs = [
        (0.0, 0.0, 1.14, 0.94),
        (0.004, -0.003, 1.135, 0.935),
        (-0.003, 0.004, 1.13, 0.93),
        (0.002, -0.002, 1.125, 0.925),
        (-0.004, 0.002, 1.11, 0.915),
    ]
    z_cur = PAL_H
    for ox, oy, tw, td in tier_specs:
        _add_box(bm, Vector((ox, oy, z_cur + tier_h * 0.5)), Vector((tw, td, tier_h - 0.004)), region=0, bevel_w=0.006)
        z_cur += tier_h

    # Top partial brick clusters (so top silhouette is broken up, total H = 1.10m)
    top_h = TARGET_HEIGHT_M - z_cur
    _add_box(bm, Vector((-0.26, -0.10, z_cur + top_h * 0.5)), Vector((0.48, 0.62, top_h)), region=0, bevel_w=0.005)
    _add_box(bm, Vector((0.28, 0.12, z_cur + top_h * 0.5)), Vector((0.46, 0.56, top_h)), region=0, bevel_w=0.005)

    # 3. 3 Steel/Poly Strapping Bands wrapping stack (region 2)
    strap_h = z_cur - PAL_H + 0.02
    strap_cz = PAL_H - 0.01 + strap_h * 0.5
    for sx in (-0.36, 0.0, 0.36):
        # Top strap
        _add_box(bm, Vector((sx, 0.0, z_cur + 0.004)), Vector((0.022, 0.955, 0.008)), region=2)
        # Front & back vertical straps
        _add_box(bm, Vector((sx, -0.476, strap_cz)), Vector((0.022, 0.008, strap_h)), region=2)
        _add_box(bm, Vector((sx, 0.476, strap_cz)), Vector((0.022, 0.008, strap_h)), region=2)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh


def _unwrap_quadrants_and_merge_material(obj: "bpy.types.Object", final_mat: "bpy.types.Material") -> None:
    import bmesh
    import bpy

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    quads = {
        0: (0.01, 0.49, 0.51, 0.99),
        1: (0.51, 0.99, 0.51, 0.99),
        2: (0.01, 0.49, 0.01, 0.49),
        3: (0.51, 0.99, 0.01, 0.49),
    }

    for region_id, (u0, u1, v0, v1) in quads.items():
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")

        selected = False
        for poly in obj.data.polygons:
            if poly.material_index == region_id:
                poly.select = True
                selected = True
        if not selected:
            continue

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
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh = _build_geometry()
    obj = bpy.data.objects.new("BrickPaletteStack", mesh)
    bpy.context.collection.objects.link(obj)

    final_mat = _create_atlas_material()
    _unwrap_quadrants_and_merge_material(obj, final_mat)

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
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[OK] {PROP_SLUG}: tris={tri_count}/{TRI_BUDGET}, dims_m={godot_dims}, uv_layers={len(obj.data.uv_layers)}")


if __name__ == "__main__":
    if "--gen-textures" in sys.argv:
        generate_textures()
    else:
        build_prop()
