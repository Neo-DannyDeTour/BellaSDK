"""Procedural Sloped-Side Wooden Storage Chest with Iron Hasp & Side Cleats (0.58m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-11_13-31.png:
- Grounded min_y = 0.0 (corner gable skirt feet sit cleanly on floor)
- ~0.92m wide x 0.58m tall x ~0.52m deep
- Battered/sloped timber chest walls + arched cutout gable feet + overhanging plank lid
- Protruding wooden side handle cleats
- Front iron strap hasp & staple latch + twin top lid strap hinges
- 1024x1024 wood + wrought-iron PBR atlas, single mesh, <= 1,100 tris

Usage:
    python3 tools/blender/props/wooden_storage_chest.py --textures
    python3 tools/blender/run.py tools/blender/props/wooden_storage_chest.py
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

SLUG: str = "wooden_storage_chest"
MESH_NAME: str = "WoodenStorageChest"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / SLUG
GLB_PATH: Path = ASSET_DIR / f"{SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-11_13-31.png"

MAT_WOOD_A: Path = REPO_ROOT / "assets" / "materials" / "roof_truss_timber" / "textures"
MAT_WOOD_B: Path = REPO_ROOT / "assets" / "materials" / "weathered_deck_planks" / "textures"
MAT_METAL_A: Path = REPO_ROOT / "assets" / "materials" / "gothic_wrought_metal" / "textures"
MAT_METAL_B: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TEX_SIZE: int = 1024
WOOD_SPLIT_U: float = 0.60

TARGET_W: float = 0.92
TARGET_H: float = 0.58


def _generate_pbr_textures() -> None:
    """Build 1024x1024 weathered timber + wrought-iron hardware PBR atlas."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    split_px = int(round(TEX_SIZE * WOOD_SPLIT_U))
    wood_w = split_px
    metal_w = TEX_SIZE - split_px

    def _load_fit(path: Path, out_w: int, out_h: int, mode: str) -> np.ndarray:
        img = Image.open(path).convert(mode).resize((out_w, out_h), Image.Resampling.BICUBIC)
        return np.array(img, dtype=np.float32)

    wa_alb = _load_fit(MAT_WOOD_A / "roof_truss_timber_albedo.png", wood_w, TEX_SIZE, "RGB")
    wa_nrm = _load_fit(MAT_WOOD_A / "roof_truss_timber_normal.png", wood_w, TEX_SIZE, "RGB")
    wa_orm = _load_fit(MAT_WOOD_A / "roof_truss_timber_orm.png", wood_w, TEX_SIZE, "RGB")

    wb_alb = _load_fit(MAT_WOOD_B / "weathered_deck_planks_albedo.png", wood_w, TEX_SIZE, "RGB")
    wb_nrm = _load_fit(MAT_WOOD_B / "weathered_deck_planks_normal.png", wood_w, TEX_SIZE, "RGB")
    wb_orm = _load_fit(MAT_WOOD_B / "weathered_deck_planks_orm.png", wood_w, TEX_SIZE, "RGB")

    wood_alb = 0.55 * wa_alb + 0.45 * wb_alb
    wood_alb[..., 0] *= 1.15
    wood_alb[..., 1] *= 1.08
    wood_alb[..., 2] *= 0.90
    # Slight ground damp darkening along bottom V < 0.14
    v_coords = 1.0 - np.linspace(0.0, 1.0, TEX_SIZE, dtype=np.float32)[:, None]
    foot_damp = np.clip((0.15 - v_coords) / 0.15, 0.0, 1.0) * 0.22
    wood_alb *= (1.0 - foot_damp[..., None])
    wood_alb_img = Image.fromarray(np.clip(wood_alb, 35, 232).astype(np.uint8), mode="RGB")

    wnrm = (0.55 * wa_nrm + 0.45 * wb_nrm) / 255.0 * 2.0 - 1.0
    wnrm[..., 2] = np.maximum(wnrm[..., 2], 0.28)
    wlen = np.sqrt(np.sum(wnrm * wnrm, axis=-1, keepdims=True))
    wnrm = wnrm / np.maximum(wlen, 1e-6)
    wood_nrm_img = Image.fromarray(np.clip((wnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    wood_ao = np.clip(0.55 * wa_orm[..., 0] + 0.45 * wb_orm[..., 0], 65, 255).astype(np.uint8)
    wood_rough = np.clip(0.55 * wa_orm[..., 1] + 0.45 * wb_orm[..., 1], 145, 230).astype(np.uint8)
    wood_metal = np.zeros((TEX_SIZE, wood_w), dtype=np.uint8)

    ma_alb = _load_fit(MAT_METAL_A / "gothic_wrought_metal_albedo.png", metal_w, TEX_SIZE, "RGB")
    ma_nrm = _load_fit(MAT_METAL_A / "gothic_wrought_metal_normal.png", metal_w, TEX_SIZE, "RGB")
    ma_orm = _load_fit(MAT_METAL_A / "gothic_wrought_metal_orm.png", metal_w, TEX_SIZE, "RGB")

    mb_alb = _load_fit(MAT_METAL_B / "rusted_steel_albedo.png", metal_w, TEX_SIZE, "RGB")
    mb_nrm = _load_fit(MAT_METAL_B / "rusted_steel_normal.png", metal_w, TEX_SIZE, "RGB")
    mb_orm = _load_fit(MAT_METAL_B / "rusted_steel_orm.png", metal_w, TEX_SIZE, "RGB")

    metal_alb = 0.72 * ma_alb + 0.28 * mb_alb
    metal_alb *= 0.80
    metal_alb_img = Image.fromarray(np.clip(metal_alb, 30, 195).astype(np.uint8), mode="RGB")

    mnrm = (0.72 * ma_nrm + 0.28 * mb_nrm) / 255.0 * 2.0 - 1.0
    mnrm[..., 2] = np.maximum(mnrm[..., 2], 0.28)
    mlen = np.sqrt(np.sum(mnrm * mnrm, axis=-1, keepdims=True))
    mnrm = mnrm / np.maximum(mlen, 1e-6)
    metal_nrm_img = Image.fromarray(np.clip((mnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    metal_ao = np.clip(0.72 * ma_orm[..., 0] + 0.28 * mb_orm[..., 0], 65, 255).astype(np.uint8)
    metal_rough = np.clip(0.72 * ma_orm[..., 1] + 0.28 * mb_orm[..., 1], 100, 190).astype(np.uint8)
    metal_metal = np.full((TEX_SIZE, metal_w), 225, dtype=np.uint8)

    def _stitch(left: Image.Image, right: Image.Image, mode: str) -> Image.Image:
        canvas = Image.new(mode, (TEX_SIZE, TEX_SIZE))
        canvas.paste(left, (0, 0))
        canvas.paste(right, (split_px, 0))
        return canvas

    albedo_atlas = _stitch(wood_alb_img, metal_alb_img, "RGB")
    normal_atlas = _stitch(wood_nrm_img, metal_nrm_img, "RGB")
    ao_atlas = _stitch(Image.fromarray(wood_ao, mode="L"), Image.fromarray(metal_ao, mode="L"), "L")
    rough_atlas = _stitch(Image.fromarray(wood_rough, mode="L"), Image.fromarray(metal_rough, mode="L"), "L")
    metal_atlas = _stitch(Image.fromarray(wood_metal, mode="L"), Image.fromarray(metal_metal, mode="L"), "L")

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
    """Build wooden_storage_chest geometry in Blender, UV-pack wood/metal atlas, and export GLB."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).resolve()), "--textures"],
            check=True,
        )

    clean_scene()
    bm = bmesh.new()

    def tag_verts(verts: list[bmesh.types.BMVert], tag: int) -> None:
        vset = set(verts)
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = tag

    def add_box(center: Vector, size: Vector, tag: int) -> None:
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        xform = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        tag_verts(verts, tag)

    def add_tapered_prism(
        z0: float,
        z1: float,
        hx0: float,
        hy0: float,
        hx1: float,
        hy1: float,
        tag: int,
    ) -> None:
        v0 = [
            bm.verts.new((-hx0, -hy0, z0)),
            bm.verts.new((+hx0, -hy0, z0)),
            bm.verts.new((+hx0, +hy0, z0)),
            bm.verts.new((-hx0, +hy0, z0)),
        ]
        v1 = [
            bm.verts.new((-hx1, -hy1, z1)),
            bm.verts.new((+hx1, -hy1, z1)),
            bm.verts.new((+hx1, +hy1, z1)),
            bm.verts.new((-hx1, +hy1, z1)),
        ]
        faces = [bm.faces.new(list(reversed(v0))), bm.faces.new(v1)]
        for i in range(4):
            j = (i + 1) % 4
            faces.append(bm.faces.new((v0[i], v0[j], v1[j], v1[i])))
        for f in faces:
            f.material_index = tag

    # Reference proportions: 0.92m W (X), ~0.52m D (Y, -Y front), 0.58m H (Z)
    # 1. Lower chest body (z: 0.06 -> 0.31) + upper sloped body (z: 0.31 -> 0.55)
    add_tapered_prism(0.060, 0.308, hx0=0.435, hy0=0.250, hx1=0.405, hy1=0.222, tag=0)
    add_tapered_prism(0.312, 0.552, hx0=0.405, hy0=0.222, hx1=0.375, hy1=0.185, tag=0)

    # 2. Gable end-panel plank wings & arched corner legs touching z=0.0 (matching ref side cutouts)
    plank_t = 0.022
    for sx in (-1.0, 1.0):
        # Front & rear leg extensions of the sloped side panels (reach down to z=0.0)
        for sy in (-1.0, 1.0):
            x_bot = sx * (0.445 - plank_t * 0.5)
            x_top = sx * (0.432 - plank_t * 0.5)
            y_outer = sy * 0.252
            y_inner = sy * 0.175
            # Front/rear leg tab from z=0.0 to z=0.065
            v_b = [
                bm.verts.new((x_bot - plank_t * 0.5, min(y_outer, y_inner), 0.0)),
                bm.verts.new((x_bot + plank_t * 0.5, min(y_outer, y_inner), 0.0)),
                bm.verts.new((x_bot + plank_t * 0.5, max(y_outer, y_inner), 0.0)),
                bm.verts.new((x_bot - plank_t * 0.5, max(y_outer, y_inner), 0.0)),
            ]
            v_t = [
                bm.verts.new((x_top - plank_t * 0.5, min(y_outer, y_inner) * 0.98, 0.065)),
                bm.verts.new((x_top + plank_t * 0.5, min(y_outer, y_inner) * 0.98, 0.065)),
                bm.verts.new((x_top + plank_t * 0.5, max(y_outer, y_inner) * 0.98, 0.065)),
                bm.verts.new((x_top - plank_t * 0.5, max(y_outer, y_inner) * 0.98, 0.065)),
            ]
            faces = [bm.faces.new(list(reversed(v_b))), bm.faces.new(v_t)]
            for i in range(4):
                j = (i + 1) % 4
                faces.append(bm.faces.new((v_b[i], v_b[j], v_t[j], v_t[i])))
            for f in faces:
                f.material_index = 0

        # Protruding wooden side handle cleats (matching ref!)
        add_box(Vector((sx * 0.442, 0.0, 0.225)), Vector((0.055, 0.145, 0.024)), tag=0)

    # 3. Overhanging flat plank lid (z: 0.556 -> 0.580)
    add_tapered_prism(0.556, 0.580, hx0=0.392, hy0=0.205, hx1=0.386, hy1=0.200, tag=0)

    # 4. Iron hardware (tag=1 metal): twin rear top strap hinges + front iron strap hasp & latch
    for hx in (-0.24, +0.24):
        # Top lid hinge strap
        add_box(Vector((hx, +0.120, 0.582)), Vector((0.032, 0.140, 0.006)), tag=1)
        # Rear hinge knuckle wrapping over back edge
        add_box(Vector((hx, +0.198, 0.562)), Vector((0.032, 0.012, 0.036)), tag=1)

    # Front iron strap hasp & shield latch plate (facing -Y)
    # Top strap on lid
    add_box(Vector((0.0, -0.155, 0.582)), Vector((0.032, 0.088, 0.006)), tag=1)
    # Angled down-folding strap across lid lip & upper sloped front wall
    slope_dy = 0.222 - 0.185
    slope_dz = 0.552 - 0.312
    # Approximate front slope y at z=0.48 and z=0.55
    y_top_hasp = -0.196
    y_mid_hasp = -0.206
    # Shield-shaped latch backplate mounted flush against sloped front face
    # Upper hasp tongue + plate + staple loop + pin
    hasp_v_f = [
        bm.verts.new((-0.024, y_top_hasp - 0.007, 0.555)),
        bm.verts.new((+0.024, y_top_hasp - 0.007, 0.555)),
        bm.verts.new((+0.034, y_mid_hasp - 0.007, 0.485)),
        bm.verts.new((+0.020, y_mid_hasp - 0.012, 0.415)),
        bm.verts.new((-0.020, y_mid_hasp - 0.012, 0.415)),
        bm.verts.new((-0.034, y_mid_hasp - 0.007, 0.485)),
    ]
    hasp_v_b = [bm.verts.new((v.co.x, v.co.y + 0.010, v.co.z)) for v in hasp_v_f]
    bm.faces.new(hasp_v_f).material_index = 1
    bm.faces.new(list(reversed(hasp_v_b))).material_index = 1
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((hasp_v_f[i], hasp_v_b[i], hasp_v_b[j], hasp_v_f[j])).material_index = 1

    # Protruding staple loop & locking pin at center of hasp
    add_box(Vector((0.0, y_mid_hasp - 0.017, 0.465)), Vector((0.014, 0.022, 0.034)), tag=1)
    add_box(Vector((0.0, y_mid_hasp - 0.024, 0.455)), Vector((0.008, 0.008, 0.052)), tag=1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    wood_faces = [f.index for f in bm.faces if f.material_index == 0]
    metal_faces = [f.index for f in bm.faces if f.material_index == 1]
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

    _unwrap_region(wood_faces, 0.015, WOOD_SPLIT_U - 0.015, 0.015, 0.985)
    _unwrap_region(metal_faces, WOOD_SPLIT_U + 0.015, 0.985, 0.015, 0.985)

    # Normalize exact width = 0.92m, height = 0.58m, center X/Y=0, min_z=0.0
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    sx = TARGET_W / (max(xs) - min(xs))
    sz = TARGET_H / (max(zs) - min(zs))
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
        "tri_budget": 1100,
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
