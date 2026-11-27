"""Procedural Wall Coat Rack with Wooden Hat Shelf, Angled Brackets & Cast Hooks (0.34m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-30_3.png:
- Grounded min_y = 0.0 (bottom of bracket mounting straps in Godot Y)
- 1.25m wide x 0.34m tall x ~0.30m deep
- 3 longitudinal slatted wooden hat-shelf boards + rear mounting batten
- 3 curved/angled flat-steel wall brackets with diagonal strut braces
- Row of 6 cast metal coat hooks along the rail
- 1024x1024 wood + cast-metal PBR atlas, single mesh, <= 1,000 tris

Usage:
    python3 tools/blender/props/wall_coat_rack.py --textures
    python3 tools/blender/run.py tools/blender/props/wall_coat_rack.py
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

SLUG: str = "wall_coat_rack"
MESH_NAME: str = "WallCoatRack"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / SLUG
GLB_PATH: Path = ASSET_DIR / f"{SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-30_3.png"

MAT_WOOD_A: Path = REPO_ROOT / "assets" / "materials" / "roof_truss_timber" / "textures"
MAT_WOOD_B: Path = REPO_ROOT / "assets" / "materials" / "dark_varnished_planks" / "textures"
MAT_METAL_A: Path = REPO_ROOT / "assets" / "materials" / "gothic_wrought_metal" / "textures"
MAT_METAL_B: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TEX_SIZE: int = 1024
WOOD_SPLIT_U: float = 0.52

# Dimensions in meters (Blender: X=width, Y=depth [-Y front, +Y wall], Z=height [0..0.34])
TOTAL_W: float = 1.25
TOTAL_H: float = 0.34
TOTAL_D: float = 0.30


def _generate_pbr_textures() -> None:
    """Build 1024x1024 wood + cast-iron PBR atlas maps."""
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

    # Left half: weathered dark/medium timber slats
    wa_alb = _load_fit(MAT_WOOD_A / "roof_truss_timber_albedo.png", wood_w, TEX_SIZE, "RGB")
    wa_nrm = _load_fit(MAT_WOOD_A / "roof_truss_timber_normal.png", wood_w, TEX_SIZE, "RGB")
    wa_orm = _load_fit(MAT_WOOD_A / "roof_truss_timber_orm.png", wood_w, TEX_SIZE, "RGB")

    wb_alb = _load_fit(MAT_WOOD_B / "dark_varnished_planks_albedo.png", wood_w, TEX_SIZE, "RGB")
    wb_nrm = _load_fit(MAT_WOOD_B / "dark_varnished_planks_normal.png", wood_w, TEX_SIZE, "RGB")
    wb_orm = _load_fit(MAT_WOOD_B / "dark_varnished_planks_orm.png", wood_w, TEX_SIZE, "RGB")

    wood_alb = 0.45 * wa_alb + 0.55 * wb_alb
    wood_alb[..., 0] *= 0.96
    wood_alb[..., 1] *= 0.93
    wood_alb[..., 2] *= 0.88
    wood_alb_img = Image.fromarray(np.clip(wood_alb, 30, 235).astype(np.uint8), mode="RGB")

    wnrm = (0.5 * wa_nrm + 0.5 * wb_nrm) / 255.0 * 2.0 - 1.0
    wnrm[..., 2] = np.maximum(wnrm[..., 2], 0.25)
    wlen = np.sqrt(np.sum(wnrm * wnrm, axis=-1, keepdims=True))
    wnrm = wnrm / np.maximum(wlen, 1e-6)
    wood_nrm_img = Image.fromarray(np.clip((wnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    wood_ao = np.clip(0.5 * wa_orm[..., 0] + 0.5 * wb_orm[..., 0], 60, 255).astype(np.uint8)
    wood_rough = np.clip(0.5 * wa_orm[..., 1] + 0.5 * wb_orm[..., 1], 140, 230).astype(np.uint8)
    wood_metal = np.zeros((TEX_SIZE, wood_w), dtype=np.uint8)

    # Right half: cast iron & weathered steel brackets/hooks
    ma_alb = _load_fit(MAT_METAL_A / "gothic_wrought_metal_albedo.png", metal_w, TEX_SIZE, "RGB")
    ma_nrm = _load_fit(MAT_METAL_A / "gothic_wrought_metal_normal.png", metal_w, TEX_SIZE, "RGB")
    ma_orm = _load_fit(MAT_METAL_A / "gothic_wrought_metal_orm.png", metal_w, TEX_SIZE, "RGB")

    mb_alb = _load_fit(MAT_METAL_B / "rusted_steel_albedo.png", metal_w, TEX_SIZE, "RGB")
    mb_nrm = _load_fit(MAT_METAL_B / "rusted_steel_normal.png", metal_w, TEX_SIZE, "RGB")
    mb_orm = _load_fit(MAT_METAL_B / "rusted_steel_orm.png", metal_w, TEX_SIZE, "RGB")

    metal_alb = 0.72 * ma_alb + 0.28 * mb_alb
    metal_alb *= 0.85
    metal_alb_img = Image.fromarray(np.clip(metal_alb, 30, 210).astype(np.uint8), mode="RGB")

    mnrm = (0.7 * ma_nrm + 0.3 * mb_nrm) / 255.0 * 2.0 - 1.0
    mnrm[..., 2] = np.maximum(mnrm[..., 2], 0.25)
    mlen = np.sqrt(np.sum(mnrm * mnrm, axis=-1, keepdims=True))
    mnrm = mnrm / np.maximum(mlen, 1e-6)
    metal_nrm_img = Image.fromarray(np.clip((mnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    metal_ao = np.clip(0.7 * ma_orm[..., 0] + 0.3 * mb_orm[..., 0], 65, 255).astype(np.uint8)
    metal_rough = np.clip(0.7 * ma_orm[..., 1] + 0.3 * mb_orm[..., 1], 105, 195).astype(np.uint8)
    metal_metal = np.full((TEX_SIZE, metal_w), 220, dtype=np.uint8)

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
    """Build wall_coat_rack geometry in Blender, UV-pack wood/metal atlas, and export GLB."""
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

    def add_extruded_profile(
        x_center: float,
        thickness_x: float,
        pts_yz: list[tuple[float, float]],
        half_w_yz: float,
        tag: int,
    ) -> None:
        """Sweep a rectangular strap along a 2D (y, z) polyline."""
        hx = thickness_x * 0.5
        rings: list[list[bmesh.types.BMVert]] = []
        n_pts = len(pts_yz)
        for idx, (py, pz) in enumerate(pts_yz):
            if idx == 0:
                dy, dz = pts_yz[1][0] - py, pts_yz[1][1] - pz
            elif idx == n_pts - 1:
                dy, dz = py - pts_yz[-2][0], pz - pts_yz[-2][1]
            else:
                dy = pts_yz[idx + 1][0] - pts_yz[idx - 1][0]
                dz = pts_yz[idx + 1][1] - pts_yz[idx - 1][1]
            length = max(math.hypot(dy, dz), 1e-6)
            ny, nz = -dz / length, dy / length
            rings.append([
                bm.verts.new((x_center - hx, py - ny * half_w_yz, pz - nz * half_w_yz)),
                bm.verts.new((x_center + hx, py - ny * half_w_yz, pz - nz * half_w_yz)),
                bm.verts.new((x_center + hx, py + ny * half_w_yz, pz + nz * half_w_yz)),
                bm.verts.new((x_center - hx, py + ny * half_w_yz, pz + nz * half_w_yz)),
            ])
        faces: list[bmesh.types.BMFace] = [
            bm.faces.new(list(reversed(rings[0]))),
            bm.faces.new(rings[-1]),
        ]
        for r in range(len(rings) - 1):
            for i in range(4):
                j = (i + 1) % 4
                faces.append(bm.faces.new((rings[r][i], rings[r][j], rings[r + 1][j], rings[r + 1][i])))
        for f in faces:
            f.material_index = tag

    # Wall is at +Y (+0.15m), front faces -Y (-0.15m).
    wall_y = TOTAL_D * 0.5  # +0.15m
    slat_t = 0.022
    slat_z_center = TOTAL_H - slat_t * 0.5  # top at 0.34m

    # 1. Wooden hat shelf: 3 longitudinal slats + 1 rear hook mounting rail (tag=0 wood)
    slat_ys = [-0.115, -0.020, +0.075]
    slat_depth = 0.072
    for sy in slat_ys:
        add_box(Vector((0.0, sy, slat_z_center)), Vector((TOTAL_W, slat_depth, slat_t)), tag=0)

    # Rear wooden hook cleat rail mounted flush to wall side (+Y)
    rail_h = 0.068
    rail_d = 0.026
    rail_z = 0.215
    rail_y = wall_y - rail_d * 0.5
    add_box(Vector((0.0, rail_y, rail_z)), Vector((TOTAL_W - 0.02, rail_d, rail_h)), tag=0)

    # 2. Three curved/angled steel strap brackets (left, center, right) (tag=1 metal)
    bracket_xs = [-0.54, 0.0, +0.54]
    strap_t = 0.008
    strap_w = 0.022
    under_shelf_z = TOTAL_H - slat_t - strap_t * 0.5
    for bx in bracket_xs:
        # Curved main wall-to-shelf arm (from z=0.0 at wall up & forward under slats)
        arm_pts = [
            (wall_y - strap_t * 0.5, 0.0 + strap_t * 0.5),
            (wall_y - strap_t * 0.5, 0.235),
            (wall_y - 0.025, 0.285),
            (wall_y - 0.075, under_shelf_z),
            (-TOTAL_D * 0.5 + 0.012, under_shelf_z),
        ]
        add_extruded_profile(bx, strap_w, arm_pts, strap_t * 0.5, tag=1)

        # Diagonal strut brace from lower wall bar up to front underside of shelf
        strut_pts = [
            (wall_y - 0.014, 0.055),
            (-0.085, under_shelf_z - 0.004),
        ]
        add_extruded_profile(bx, strap_w * 0.85, strut_pts, strap_t * 0.45, tag=1)

    # 3. Row of 6 cast metal coat hooks along the wooden wall rail (tag=1 metal)
    hook_xs = [-0.45, -0.27, -0.09, +0.09, +0.27, +0.45]
    hook_front_y = rail_y - rail_d * 0.5
    for hx in hook_xs:
        # Cast backplate on rail
        add_box(Vector((hx, hook_front_y - 0.004, rail_z)), Vector((0.026, 0.008, 0.048)), tag=1)
        # Main lower J-hook projecting toward -Y
        j_pts = [
            (hook_front_y - 0.006, rail_z - 0.012),
            (hook_front_y - 0.036, rail_z - 0.046),
            (hook_front_y - 0.068, rail_z - 0.052),
            (hook_front_y - 0.088, rail_z - 0.028),
        ]
        add_extruded_profile(hx, 0.011, j_pts, 0.006, tag=1)
        # Small upper hat-peg nub above main hook
        peg_pts = [
            (hook_front_y - 0.006, rail_z + 0.010),
            (hook_front_y - 0.030, rail_z + 0.028),
        ]
        add_extruded_profile(hx, 0.010, peg_pts, 0.005, tag=1)

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

    # Center X/Y around 0 and ground min_z = 0.0 exactly
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    z0 = min(zs)
    for v in mesh.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= z0
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
        "tri_budget": 1000,
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
