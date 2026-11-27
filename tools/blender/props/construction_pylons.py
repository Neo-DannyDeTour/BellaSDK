"""Procedural Post-Soviet Weathered Traffic Cone Pylon.

Generates weathered PBR texture maps via PIL/numpy + process_pbr.py, builds a
clean manifold traffic cone (~0.38m x 0.38m x 0.72m) with heavy black rubber
base, tapered orange/red PVC body, recessed hollow top rim, and two scuffed
reflective collar bands grounded at min_z = 0 (Godot min_y = 0). Exports GLB,
ORMMaterial3D .tres, and asset_manifest.json.

Run:
    /snap/bin/blender --background --python tools/blender/props/construction_pylons.py
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "construction_pylons"
TEXTURE_DIR: Path = ASSET_DIR / "textures"
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"

TARGET_BASE_M: float = 0.38
TARGET_HEIGHT_M: float = 0.72
TRI_BUDGET: int = 1000
TEX_SIZE: int = 1024


def _generate_textures() -> None:
    """Synthesize clamped [30..240] sRGB weathered PBR maps and Godot .tres."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(55912)
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

    macro = fbm_noise(((8, 0.5), (24, 0.3), (64, 0.2)))
    fine = fbm_noise(((128, 0.5), (256, 0.5)))

    albedo = np.zeros((h, w, 3), dtype=np.float32)

    split_x = int(w * 0.58)
    split_y = int(h * 0.55)

    # --- Region 0 (UV u in [0.0, 0.58]): Weathered Safety Orange-Red PVC ---
    orange_base = np.array([204.0, 74.0, 32.0], dtype=np.float32)
    orange_var = orange_base[None, None, :] * (
        0.88 + 0.16 * macro[:, :split_x, None] + 0.06 * (fine[:, :split_x, None] - 0.5)
    )
    # Sun-faded pale orange patches & dark tar/mud scuffs
    fade_mask = macro[:, :split_x] > 0.72
    fade_col = np.array([218.0, 118.0, 76.0], dtype=np.float32)
    orange_var = np.where(fade_mask[..., None], orange_var * 0.65 + fade_col * 0.35, orange_var)

    grime_mask = (macro[:, :split_x] * 0.65 + fine[:, :split_x] * 0.35) < 0.28
    grime_col = np.array([62.0, 52.0, 44.0], dtype=np.float32)
    albedo[:, :split_x, :] = np.where(
        grime_mask[..., None], orange_var * 0.45 + grime_col * 0.55, orange_var
    )

    # --- Region 1 (UV u in [0.58, 1.0], PIL y < split_y): Heavy Black Rubber Base ---
    rubber_base = np.array([44.0, 44.0, 46.0], dtype=np.float32)
    rubber_var = rubber_base[None, None, :] * (
        0.84 + 0.24 * macro[:split_y, split_x:, None] + 0.10 * fine[:split_y, split_x:, None]
    )
    dust_mask = (macro[:split_y, split_x:] * 0.55 + fine[:split_y, split_x:] * 0.45) > 0.68
    dust_col = np.array([96.0, 92.0, 84.0], dtype=np.float32)
    albedo[:split_y, split_x:, :] = np.where(
        dust_mask[..., None], rubber_var * 0.5 + dust_col * 0.5, rubber_var
    )

    # --- Region 2 (UV u in [0.58, 1.0], PIL y >= split_y): Scuffed Reflective Collar ---
    yy2, xx2 = np.mgrid[split_y:h, split_x:w]
    prism = 0.5 + 0.5 * np.sin(xx2 * 0.6) * np.sin(yy2 * 0.6)
    refl_base = np.array([208.0, 210.0, 204.0], dtype=np.float32)
    refl_var = refl_base[None, None, :] * (
        0.88 + 0.10 * prism[..., None] + 0.06 * (macro[split_y:, split_x:, None] - 0.5)
    )
    scuff_mask = (macro[split_y:, split_x:] * 0.6 + fine[split_y:, split_x:] * 0.4) > 0.66
    scuff_col = np.array([78.0, 74.0, 70.0], dtype=np.float32)
    albedo[split_y:, split_x:, :] = np.where(scuff_mask[..., None], scuff_col, refl_var)

    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)
    alb_img = Image.fromarray(albedo_u8, mode="RGB")

    draw = ImageDraw.Draw(alb_img)
    for _ in range(28):
        x0 = int(rng.integers(12, split_x - 24))
        y0 = int(rng.integers(12, h - 24))
        dx = int(rng.integers(-18, 19))
        dy = int(rng.integers(-12, 13))
        draw.line((x0, y0, x0 + dx, y0 + dy), fill=(52, 46, 42), width=2)
    alb_img = alb_img.filter(ImageFilter.GaussianBlur(radius=0.3))

    alb_arr = np.clip(np.array(alb_img, dtype=np.uint8), 30, 240)
    albedo_path = TEXTURE_DIR / "construction_pylons_albedo.png"
    Image.fromarray(alb_arr, mode="RGB").save(albedo_path, format="PNG")

    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "derive-maps",
            str(albedo_path),
            "--out-dir",
            str(TEXTURE_DIR),
            "--slug",
            "construction_pylons",
            "--preset",
            "plaster",
            "--normal-strength",
            "1.4",
            "--base-roughness",
            "0.68",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEXTURE_DIR / "construction_pylons_ao.png"
    rough_path = TEXTURE_DIR / "construction_pylons_roughness.png"
    height_path = TEXTURE_DIR / "construction_pylons_height.png"
    normal_path = TEXTURE_DIR / "construction_pylons_normal.png"
    orm_path = TEXTURE_DIR / "construction_pylons_orm.png"

    # Matte rubber base (Region 1 high roughness), semi-glossy weathered PVC (Region 0),
    # and slightly lower roughness on intact reflective collar (Region 2)
    rough_arr = np.array(Image.open(rough_path).convert("L"), dtype=np.uint8)
    rough_arr[:split_y, split_x:] = np.clip(
        rough_arr[:split_y, split_x:].astype(np.int32) + 55, 195, 245
    ).astype(np.uint8)
    rough_arr[split_y:, split_x:] = np.clip(
        rough_arr[split_y:, split_x:].astype(np.int32) - 55, 85, 200
    ).astype(np.uint8)
    Image.fromarray(rough_arr, mode="L").save(rough_path, format="PNG")

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

    tres_path = ASSET_DIR / "construction_pylons.tres"
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "build-tres",
            "--name",
            "construction_pylons",
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
        TEXTURE_DIR / "construction_pylons_albedo.png",
        TEXTURE_DIR / "construction_pylons_normal.png",
        TEXTURE_DIR / "construction_pylons_orm.png",
        ASSET_DIR / "construction_pylons.tres",
    ]
    if all(p.is_file() for p in required):
        return
    env = os.environ.copy()
    subprocess.run(
        ["/usr/bin/python3", str(Path(__file__).resolve()), "--generate-textures"],
        env=env,
        check=True,
    )


def _run_blender_build() -> None:
    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))

    import bmesh
    import bpy
    from mathutils import Matrix, Vector
    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures()
    clean_scene()

    # Groups:
    # 0 = weathered orange/red PVC cone body
    # 1 = heavy black rubber base + collar ring
    # 2 = scuffed reflective collar bands
    bms = {0: bmesh.new(), 1: bmesh.new(), 2: bmesh.new()}

    def _merge_into(dst: bmesh.types.BMesh, src: bmesh.types.BMesh) -> None:
        vmap = {v.index: dst.verts.new(v.co) for v in src.verts}
        for f in src.faces:
            dst.faces.new([vmap[v.index] for v in f.verts])
        src.free()

    # 1. Heavy octagonal-chamfered square black rubber base (Group 1, 0.38m x 0.38m x 0.048m)
    tmp_base = bmesh.new()
    bmesh.ops.create_cube(tmp_base, size=1.0)
    bmesh.ops.scale(tmp_base, vec=Vector((TARGET_BASE_M, TARGET_BASE_M, 0.046)), verts=tmp_base.verts)
    bmesh.ops.bevel(
        tmp_base,
        geom=list(tmp_base.edges),
        offset=0.012,
        segments=1,
        affect="EDGES",
        clamp_overlap=True,
    )
    bmesh.ops.transform(tmp_base, matrix=Matrix.Translation(Vector((0.0, 0.0, 0.023))), verts=tmp_base.verts)
    _merge_into(bms[1], tmp_base)

    # Molded rubber collar ring at cone root
    tmp_ring = bmesh.new()
    bmesh.ops.create_cone(
        tmp_ring,
        cap_ends=True,
        cap_tris=False,
        segments=16,
        radius1=0.148,
        radius2=0.138,
        depth=0.028,
        matrix=Matrix.Translation(Vector((0.0, 0.0, 0.056))),
    )
    _merge_into(bms[1], tmp_ring)

    # 2. Tapered cone body (Group 0) with hollow recessed top throat
    segs = 16
    def _cone_radius(z_val: float) -> float:
        t = (z_val - 0.050) / (TARGET_HEIGHT_M - 0.050)
        return 0.134 + (0.040 - 0.134) * t

    cone_z = [0.050, 0.285, 0.415, 0.485, 0.595, TARGET_HEIGHT_M - 0.008, TARGET_HEIGHT_M]
    cone_rings: list[list[bmesh.types.BMVert]] = []
    for zi, z_val in enumerate(cone_z):
        r = _cone_radius(z_val)
        if zi == len(cone_z) - 1:
            r = 0.035  # beveled top lip
        ring = []
        for si in range(segs):
            ang = 2.0 * math.pi * si / segs
            ring.append(bms[0].verts.new((r * math.cos(ang), r * math.sin(ang), z_val)))
        cone_rings.append(ring)

    # Inner throat ring
    inner_top = []
    inner_bot = []
    for si in range(segs):
        ang = 2.0 * math.pi * si / segs
        inner_top.append(bms[0].verts.new((0.024 * math.cos(ang), 0.024 * math.sin(ang), TARGET_HEIGHT_M)))
        inner_bot.append(bms[0].verts.new((0.022 * math.cos(ang), 0.022 * math.sin(ang), TARGET_HEIGHT_M - 0.065)))
    cone_rings.append(inner_top)
    cone_rings.append(inner_bot)

    for ri in range(len(cone_rings) - 1):
        r0 = cone_rings[ri]
        r1 = cone_rings[ri + 1]
        for si in range(segs):
            sn = (si + 1) % segs
            bms[0].faces.new((r0[si], r0[sn], r1[sn], r1[si]))
    bms[0].faces.new(list(reversed(cone_rings[0])))
    bms[0].faces.new(cone_rings[-1])

    # 3. Two stepped scuffed reflective collar bands (Group 2)
    for z_bot, z_top in ((0.295, 0.405), (0.495, 0.585)):
        r_bot = _cone_radius(z_bot) + 0.002
        r_top = _cone_radius(z_top) + 0.002
        tmp_band = bmesh.new()
        bmesh.ops.create_cone(
            tmp_band,
            cap_ends=False,
            cap_tris=False,
            segments=segs,
            radius1=r_bot,
            radius2=r_top,
            depth=z_top - z_bot,
            matrix=Matrix.Translation(Vector((0.0, 0.0, (z_bot + z_top) * 0.5))),
        )
        _merge_into(bms[2], tmp_band)

    uv_regions = {
        0: (0.02, 0.02, 0.56, 0.98),
        1: (0.60, 0.47, 0.98, 0.98),
        2: (0.60, 0.02, 0.98, 0.43),
    }

    part_objs = []
    for grp, bm in bms.items():
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        m = bpy.data.meshes.new(f"TmpMesh_{grp}")
        bm.to_mesh(m)
        bm.free()

        o = bpy.data.objects.new(f"TmpObj_{grp}", m)
        bpy.context.collection.objects.link(o)
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = o
        o.select_set(True)

        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.03)
        bpy.ops.object.mode_set(mode="OBJECT")

        u0, v0, u1, v1 = uv_regions[grp]
        du = u1 - u0
        dv = v1 - v0
        uv_layer = m.uv_layers.active.data
        for poly in m.polygons:
            for li in poly.loop_indices:
                uv = uv_layer[li].uv
                uv_layer[li].uv = (u0 + uv.x * du, v0 + uv.y * dv)

        part_objs.append(o)

    bpy.ops.object.select_all(action="DESELECT")
    for o in part_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = part_objs[0]
    bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = "ConstructionPylons"
    obj.data.name = "ConstructionPylons_Mesh"

    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    min_z = min(zs)
    for v in obj.data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= min_z
    obj.data.update()

    bpy.ops.object.shade_smooth()
    wn = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    wn.weight = 50
    bpy.ops.object.modifier_apply(modifier=wn.name)

    mat = bpy.data.materials.new(name="Mat_ConstructionPylons")
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
    tex_alb.image = bpy.data.images.load(
        str(TEXTURE_DIR / "construction_pylons_albedo.png"), check_existing=True
    )
    tex_alb.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-400, 0)
    tex_orm.image = bpy.data.images.load(
        str(TEXTURE_DIR / "construction_pylons_orm.png"), check_existing=True
    )
    tex_orm.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-120, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-400, -280)
    tex_nrm.image = bpy.data.images.load(
        str(TEXTURE_DIR / "construction_pylons_normal.png"), check_existing=True
    )
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -280)
    nrm_node.inputs["Strength"].default_value = 0.65
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.append(mat)

    glb_path = ASSET_DIR / "construction_pylons.glb"
    export_godot_glb(glb_path, export_animations=False)

    tri_count = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    assert tri_count <= TRI_BUDGET, f"Tri count {tri_count} exceeds budget {TRI_BUDGET}"
    assert len(obj.data.uv_layers) >= 1, "Missing UV layer"

    xs2 = [v.co.x for v in obj.data.vertices]
    ys2 = [v.co.y for v in obj.data.vertices]
    zs2 = [v.co.z for v in obj.data.vertices]
    dims_godot = [
        round(max(xs2) - min(xs2), 4),
        round(max(zs2) - min(zs2), 4),
        round(max(ys2) - min(ys2), 4),
    ]

    manifest = {
        "prop_slug": "construction_pylons",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "BoxShape3D+CylinderShape3D",
        "generator": "procedural_bpy",
        "materials": ["res://assets/models/construction_pylons/construction_pylons.tres"],
        "glb": "res://assets/models/construction_pylons/construction_pylons.glb",
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_CONSTRUCTION_PYLONS:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    if "--generate-textures" in sys.argv:
        _generate_textures()
    else:
        _run_blender_build()
