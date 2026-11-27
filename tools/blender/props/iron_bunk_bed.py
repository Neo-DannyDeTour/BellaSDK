"""Procedural Iron Bunk Bed with Olive-Drab Fabric Mattresses (1.75m H).

Matches reference:
- /home/dkd/Downloads/hl2_refs/2026-11-04_03-45_2.png

Features:
- 4 tubular iron corner posts with rounded top U-arches (1.75m H, min_y = 0)
- Lower & upper angle-iron bunk frames, crossbars, and diagonal corner gusset braces
- 2 beveled institutional olive-drab fabric mattresses with integrated pillow bolsters
- 2048x2048 PBR atlas (oxidized maroon-brown iron frame + stained olive mattress ticking)

Usage:
    .venv/bin/python tools/blender/props/iron_bunk_bed.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/iron_bunk_bed.py
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

PROP_SLUG: str = "iron_bunk_bed"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = TEX_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = TEX_DIR / f"{PROP_SLUG}_orm.png"

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-04_03-45_2.png"
TARGET_HEIGHT_M: float = 1.75
TRI_BUDGET: int = 2000

SRC_RUST_DIR: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
SRC_TICKING_DIR: Path = REPO_ROOT / "assets" / "materials" / "stained_mattress_ticking" / "textures"

TEX_SIZE: int = 2048


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def generate_textures() -> None:
    """Generate 2048x2048 painted-rust iron frame + olive-drab mattress ticking atlas."""
    import numpy as np
    from PIL import Image, ImageFilter

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2

    src_rust_alb = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_albedo.png", half)
    src_rust_nrm = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_normal.png", half)
    src_mat_alb = _load_square_rgb(SRC_TICKING_DIR / "stained_mattress_ticking_albedo.png", half)
    src_mat_nrm = _load_square_rgb(SRC_TICKING_DIR / "stained_mattress_ticking_normal.png", half)

    # 1. Maroon-brown painted/rusted iron frame (Left half: U in [0.0, 0.5])
    rust_lum = 0.299 * src_rust_alb[..., 0] + 0.587 * src_rust_alb[..., 1] + 0.114 * src_rust_alb[..., 2]
    maroon_paint = np.array([86.0, 42.0, 38.0], dtype=np.float32)
    iron_var = (rust_lum - 100.0) * 0.25
    iron_half_alb = maroon_paint[None, None, :] + iron_var[..., None]
    # Blend in real rust blotches
    rust_mask = np.clip((110.0 - rust_lum) / 45.0, 0.0, 1.0) * 0.55
    iron_half_alb = iron_half_alb * (1.0 - rust_mask[..., None]) + src_rust_alb * 0.65 * rust_mask[..., None]

    iron_alb = np.concatenate([iron_half_alb, iron_half_alb], axis=0)
    iron_nrm_half = (src_rust_nrm - 128.0) * 0.55 + 128.0
    iron_nrm = np.concatenate([iron_nrm_half, iron_nrm_half], axis=0)
    iron_rough_half = np.clip(0.46 + rust_mask * 0.30, 0.36, 0.80)
    iron_rough = np.concatenate([iron_rough_half, iron_rough_half], axis=0)
    iron_metal_half = np.clip(0.68 - rust_mask * 0.38, 0.25, 0.82)
    iron_metal = np.concatenate([iron_metal_half, iron_metal_half], axis=0)
    iron_ao_half = np.clip(0.84 + (rust_lum / 255.0) * 0.16 - rust_mask * 0.18, 0.45, 1.0)
    iron_ao = np.concatenate([iron_ao_half, iron_ao_half], axis=0)

    # 2. Institutional olive-drab stained canvas mattresses (Right half: U in [0.5, 1.0])
    mat_lum = 0.299 * src_mat_alb[..., 0] + 0.587 * src_mat_alb[..., 1] + 0.114 * src_mat_alb[..., 2]
    mat_low = np.asarray(
        Image.fromarray(np.clip(mat_lum, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=18)
        ),
        dtype=np.float32,
    )
    mat_hp = np.clip(mat_lum - mat_low, -22.0, 22.0)
    olive_base = np.array([92.0, 96.0, 68.0], dtype=np.float32)
    stain_col = np.array([62.0, 60.0, 44.0], dtype=np.float32)
    stain_mask = np.clip((138.0 - mat_low) / 48.0, 0.0, 1.0) * 0.62

    mat_half_alb = olive_base[None, None, :] + mat_hp[..., None] * 0.72
    mat_half_alb = mat_half_alb * (1.0 - stain_mask[..., None]) + stain_col[None, None, :] * stain_mask[..., None]

    # Subtle fabric edge piping/seam shading
    mat_alb = np.concatenate([mat_half_alb, mat_half_alb], axis=0)
    mat_nrm_half = (src_mat_nrm - 128.0) * 0.72 + 128.0
    mat_nrm = np.concatenate([mat_nrm_half, mat_nrm_half], axis=0)
    mat_rough_half = np.clip(0.86 + stain_mask * 0.10 - mat_hp * 0.002, 0.76, 0.98)
    mat_rough = np.concatenate([mat_rough_half, mat_rough_half], axis=0)
    mat_metal = np.zeros((TEX_SIZE, half), dtype=np.float32)
    mat_ao_half = np.clip(0.90 - stain_mask * 0.22 + mat_hp * 0.002, 0.55, 1.0)
    mat_ao = np.concatenate([mat_ao_half, mat_ao_half], axis=0)

    alb_full = np.concatenate([iron_alb, mat_alb], axis=1)
    nrm_full = np.concatenate([iron_nrm, mat_nrm], axis=1)
    rough_full = np.concatenate([iron_rough, mat_rough], axis=1)
    metal_full = np.concatenate([iron_metal, mat_metal], axis=1)
    ao_full = np.concatenate([iron_ao, mat_ao], axis=1)

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
        material_name="M_IronBunkBed",
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

    def add_box(center: Vector, size: Vector, region: int, bevel_w: float = 0.0) -> None:
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        xform = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        vset = set(verts)
        if bevel_w > 0.0:
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
            for f in bm.faces:
                if any(v in vset for v in f.verts):
                    f.material_index = region
                    f.smooth = False
        else:
            _tag_verts(verts, region, smooth=False)

    def add_strut(p0: Vector, p1: Vector, thickness: float, region: int) -> None:
        delta = p1 - p0
        length = delta.length
        if length < 1e-5:
            return
        mid = (p0 + p1) * 0.5
        rot = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized()).to_matrix().to_4x4()
        mat = Matrix.Translation(mid) @ rot @ Matrix.Diagonal((thickness, thickness, length, 1.0))
        ret = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.transform(bm, matrix=mat, verts=ret["verts"])
        _tag_verts(ret["verts"], region, smooth=False)

    def add_tube_polyline(points: list[Vector], radius: float, segments: int, region: int) -> None:
        rings: list[list[bmesh.types.BMVert]] = []
        for idx, pt in enumerate(points):
            if idx == 0:
                tangent = (points[1] - points[0]).normalized()
            elif idx == len(points) - 1:
                tangent = (points[-1] - points[-2]).normalized()
            else:
                t_in = (pt - points[idx - 1]).normalized()
                t_out = (points[idx + 1] - pt).normalized()
                tangent = (t_in + t_out)
                if tangent.length < 1e-5:
                    tangent = t_out
                else:
                    tangent.normalize()
            up = Vector((0.0, 1.0, 0.0)) if abs(tangent.y) < 0.9 else Vector((1.0, 0.0, 0.0))
            side = tangent.cross(up).normalized()
            binorm = side.cross(tangent).normalized()
            ring: list[bmesh.types.BMVert] = []
            for s in range(segments):
                ang = (2.0 * math.pi * s) / float(segments)
                ring.append(bm.verts.new(pt + (side * math.cos(ang) + binorm * math.sin(ang)) * radius))
            rings.append(ring)

        faces: list[bmesh.types.BMFace] = []
        for r in range(len(rings) - 1):
            for s in range(segments):
                sn = (s + 1) % segments
                faces.append(bm.faces.new((rings[r][s], rings[r][sn], rings[r + 1][sn], rings[r + 1][s])))
        faces.append(bm.faces.new(list(reversed(rings[0]))))
        faces.append(bm.faces.new(rings[-1]))
        for f in faces:
            f.material_index = region
            f.smooth = True

    def add_mattress(z_bot: float, region: int) -> None:
        """Build pillowy beveled mattress with raised head bolster at -X."""
        mat_l = 1.90
        mat_w = 0.86
        mat_h = 0.135
        hx = mat_l * 0.5
        hy = mat_w * 0.5

        # Segmented grid along X so we can raise the head pillow mound cleanly
        xs = [-hx, -hx + 0.08, -hx + 0.24, -hx + 0.44, 0.0, hx - 0.08, hx]
        ys = [-hy, 0.0, hy]

        def _top_z(x: float, y: float) -> float:
            # Subtle crown + raised pillow mound around x in [-hx+0.04, -hx+0.42]
            pillow = 0.0
            if x < -hx + 0.46:
                u = (x - (-hx + 0.22)) / 0.22
                pillow = max(0.0, 1.0 - u * u) * 0.055 * (1.0 - 0.22 * (abs(y) / hy) ** 2)
            edge_drop = -0.016 * (abs(y) / hy) ** 4
            if abs(x) > hx - 0.08:
                edge_drop -= 0.014
            return z_bot + mat_h + pillow + edge_drop

        def _bot_z(x: float, y: float) -> float:
            lift = 0.010 if (abs(y) > hy - 0.01 or abs(x) > hx - 0.01) else 0.0
            return z_bot + lift

        nx, ny = len(xs), len(ys)
        top_v = [[bm.verts.new((xs[ix], ys[iy], _top_z(xs[ix], ys[iy]))) for iy in range(ny)] for ix in range(nx)]
        bot_v = [[bm.verts.new((xs[ix], ys[iy], _bot_z(xs[ix], ys[iy]))) for iy in range(ny)] for ix in range(nx)]

        faces: list[bmesh.types.BMFace] = []
        for ix in range(nx - 1):
            for iy in range(ny - 1):
                faces.append(bm.faces.new((top_v[ix][iy], top_v[ix + 1][iy], top_v[ix + 1][iy + 1], top_v[ix][iy + 1])))
                faces.append(bm.faces.new((bot_v[ix][iy + 1], bot_v[ix + 1][iy + 1], bot_v[ix + 1][iy], bot_v[ix][iy])))
        for ix in range(nx - 1):
            faces.append(bm.faces.new((bot_v[ix][0], bot_v[ix + 1][0], top_v[ix + 1][0], top_v[ix][0])))
            faces.append(bm.faces.new((top_v[ix][-1], top_v[ix + 1][-1], bot_v[ix + 1][-1], bot_v[ix][-1])))
        for iy in range(ny - 1):
            faces.append(bm.faces.new((top_v[0][iy], top_v[0][iy + 1], bot_v[0][iy + 1], bot_v[0][iy])))
            faces.append(bm.faces.new((bot_v[-1][iy], bot_v[-1][iy + 1], top_v[-1][iy + 1], top_v[-1][iy])))
        for f in faces:
            f.material_index = region
            f.smooth = True

    # Dimensions (Blender Z-up, length along X, width along Y)
    bed_l = 1.98
    bed_w = 0.92
    half_x = bed_l * 0.5
    half_y = bed_w * 0.5
    tube_r = 0.017
    corner_r = 0.11

    low_z = 0.28
    mid_z = 0.78
    high_z = 1.24
    top_z = 1.75

    # Region 0: Iron frame (head & foot U-arch tubular posts + crossbars + gusset struts + rails)
    for sx in (-1.0, 1.0):
        px = sx * half_x
        arch_pts = [
            Vector((px, -half_y, 0.0)),
            Vector((px, -half_y, top_z - corner_r)),
            Vector((px, -half_y + corner_r * 0.29, top_z - corner_r * 0.29)),
            Vector((px, -half_y + corner_r, top_z)),
            Vector((px, +half_y - corner_r, top_z)),
            Vector((px, +half_y - corner_r * 0.29, top_z - corner_r * 0.29)),
            Vector((px, +half_y, top_z - corner_r)),
            Vector((px, +half_y, 0.0)),
        ]
        add_tube_polyline(arch_pts, radius=tube_r, segments=6, region=0)

        # Horizontal end crossbars at low, mid, high, and upper headboard
        for cz in (low_z, mid_z, high_z, high_z + 0.30):
            add_box(Vector((px, 0.0, cz)), Vector((0.022, bed_w - 0.02, 0.022)), region=0)

        # Diagonal corner gusset braces matching HL2 bunk bed ref
        for sy in (-1.0, 1.0):
            add_strut(Vector((px, sy * half_y, low_z - 0.14)), Vector((px, sy * (half_y - 0.18), low_z)), 0.014, region=0)
            add_strut(Vector((px, sy * half_y, high_z - 0.18)), Vector((px, sy * (half_y - 0.20), high_z)), 0.014, region=0)

    # Lower and upper bed perimeter angle-iron frames + recessed wood/iron deck platforms
    for bz in (low_z, high_z):
        for sy in (-1.0, 1.0):
            add_box(Vector((0.0, sy * half_y, bz)), Vector((bed_l, 0.026, 0.036)), region=0)
        for sx in (-1.0, 1.0):
            add_box(Vector((sx * (half_x - 0.02), 0.0, bz)), Vector((0.026, bed_w, 0.036)), region=0)
        # Thin support deck
        add_box(Vector((0.0, 0.0, bz - 0.004)), Vector((bed_l - 0.04, bed_w - 0.04, 0.018)), region=0)

    # Region 1: Lower & upper institutional olive-drab fabric mattresses
    add_mattress(low_z + 0.006, region=1)
    add_mattress(high_z + 0.006, region=1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("IronBunkBed")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(2):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))

    obj = bpy.data.objects.new("IronBunkBed", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")
    uv_regions = {
        0: (0.015, 0.485, 0.015, 0.985),
        1: (0.515, 0.985, 0.015, 0.985),
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

    for poly in mesh.polygons:
        poly.material_index = 0

    mat = bpy.data.materials.new(name="M_IronBunkBed")
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
        "layer": "Layer 1 Environment",
        "target_layer": "Layer 1 Environment",
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
