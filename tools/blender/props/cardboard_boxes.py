"""Procedural Post-Soviet Weathered Stacked Cardboard Supply Boxes.

Generates weathered PBR texture maps via PIL/numpy + process_pbr.py, builds 3
stacked/slightly offset corrugated cardboard boxes (~0.65m x 0.55m x 0.65m)
with packing tape strips, flap seams, and stenciled shipping marks grounded at
min_z = 0 (Godot min_y = 0). Exports GLB, ORMMaterial3D .tres, and
asset_manifest.json.

Run:
    /snap/bin/blender --background --python tools/blender/props/cardboard_boxes.py
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "cardboard_boxes"
TEXTURE_DIR: Path = ASSET_DIR / "textures"
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"

TRI_BUDGET: int = 1200
TEX_SIZE: int = 1024


def _generate_textures() -> None:
    """Synthesize clamped [30..240] sRGB weathered cardboard & tape PBR maps."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(90311)
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
    split_x = int(w * 0.68)

    # --- Region 0 (UV u in [0.0, 0.68]): Weathered Corrugated Kraft Cardboard ---
    yy0, xx0 = np.mgrid[0:h, 0:split_x]
    fluting = 0.5 + 0.5 * np.sin(yy0 * 0.42)
    kraft_base = np.array([154.0, 118.0, 78.0], dtype=np.float32)
    kraft_var = kraft_base[None, None, :] * (
        0.84
        + 0.20 * macro[:, :split_x, None]
        + 0.06 * (fluting[..., None] - 0.5)
        + 0.06 * (fine[:, :split_x, None] - 0.5)
    )
    # Damp water stains & grime blotches
    stain_mask = (macro[:, :split_x] * 0.65 + fine[:, :split_x] * 0.35) < 0.32
    stain_col = np.array([86.0, 68.0, 48.0], dtype=np.float32)
    albedo[:, :split_x, :] = np.where(
        stain_mask[..., None], kraft_var * 0.55 + stain_col * 0.45, kraft_var
    )

    # --- Region 1 (UV u in [0.68, 1.0]): Tan/Yellowish Packing Tape ---
    tape_base = np.array([186.0, 158.0, 102.0], dtype=np.float32)
    tape_var = tape_base[None, None, :] * (
        0.88 + 0.16 * macro[:, split_x:, None] + 0.08 * (fine[:, split_x:, None] - 0.5)
    )
    albedo[:, split_x:, :] = tape_var

    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)
    alb_img = Image.fromarray(albedo_u8, mode="RGB")

    # Add subtle dark stenciled box markings & seam lines on cardboard region
    draw = ImageDraw.Draw(alb_img)
    for _ in range(18):
        x0 = int(rng.integers(24, split_x - 70))
        y0 = int(rng.integers(24, h - 40))
        bw = int(rng.integers(24, 58))
        draw.rectangle((x0, y0, x0 + bw, y0 + 6), fill=(62, 52, 44))
    alb_img = alb_img.filter(ImageFilter.GaussianBlur(radius=0.35))

    alb_arr = np.clip(np.array(alb_img, dtype=np.uint8), 30, 240)
    albedo_path = TEXTURE_DIR / "cardboard_boxes_albedo.png"
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
            "cardboard_boxes",
            "--preset",
            "wood",
            "--normal-strength",
            "1.5",
            "--base-roughness",
            "0.86",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEXTURE_DIR / "cardboard_boxes_ao.png"
    rough_path = TEXTURE_DIR / "cardboard_boxes_roughness.png"
    height_path = TEXTURE_DIR / "cardboard_boxes_height.png"
    normal_path = TEXTURE_DIR / "cardboard_boxes_normal.png"
    orm_path = TEXTURE_DIR / "cardboard_boxes_orm.png"

    # Packing tape (Region 1) is slightly smoother than raw kraft cardboard
    rough_arr = np.array(Image.open(rough_path).convert("L"), dtype=np.uint8)
    rough_arr[:, split_x:] = np.clip(
        rough_arr[:, split_x:].astype(np.int32) - 85, 110, 175
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

    tres_path = ASSET_DIR / "cardboard_boxes.tres"
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "build-tres",
            "--name",
            "cardboard_boxes",
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
        TEXTURE_DIR / "cardboard_boxes_albedo.png",
        TEXTURE_DIR / "cardboard_boxes_normal.png",
        TEXTURE_DIR / "cardboard_boxes_orm.png",
        ASSET_DIR / "cardboard_boxes.tres",
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

    # Groups: 0 = corrugated cardboard boxes, 1 = packing tape strips
    bms = {0: bmesh.new(), 1: bmesh.new()}

    def _merge_into(dst: bmesh.types.BMesh, src: bmesh.types.BMesh) -> None:
        vmap = {v.index: dst.verts.new(v.co) for v in src.verts}
        for f in src.faces:
            dst.faces.new([vmap[v.index] for v in f.verts])
        src.free()

    def add_box(
        group: int,
        center: Vector,
        size: Vector,
        rot_z_deg: float = 0.0,
        bevel_w: float = 0.006,
    ) -> None:
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.scale(tmp, vec=size, verts=tmp.verts)
        if bevel_w > 0.0:
            bmesh.ops.bevel(
                tmp,
                geom=list(tmp.edges),
                offset=bevel_w,
                segments=1,
                affect="EDGES",
                clamp_overlap=True,
            )
        xf = Matrix.Translation(center) @ Matrix.Rotation(math.radians(rot_z_deg), 4, "Z")
        bmesh.ops.transform(tmp, matrix=xf, verts=tmp.verts)
        _merge_into(bms[group], tmp)

    # Box 1 (bottom large): 0.62 x 0.50 x 0.34m, grounded at z=0
    add_box(0, Vector((0.0, 0.0, 0.17)), Vector((0.62, 0.50, 0.34)), rot_z_deg=0.0)
    add_box(1, Vector((0.0, 0.0, 0.342)), Vector((0.624, 0.055, 0.004)), rot_z_deg=0.0, bevel_w=0.0)
    add_box(1, Vector((0.311, 0.0, 0.28)), Vector((0.004, 0.055, 0.12)), rot_z_deg=0.0, bevel_w=0.0)
    add_box(1, Vector((-0.311, 0.0, 0.28)), Vector((0.004, 0.055, 0.12)), rot_z_deg=0.0, bevel_w=0.0)

    # Box 2 (middle medium, slightly rotated): 0.44 x 0.36 x 0.20m, z=0.34..0.54
    add_box(0, Vector((-0.04, 0.02, 0.44)), Vector((0.44, 0.36, 0.20)), rot_z_deg=9.0)
    add_box(1, Vector((-0.04, 0.02, 0.542)), Vector((0.444, 0.050, 0.004)), rot_z_deg=9.0, bevel_w=0.0)

    # Box 3 (top small): 0.32 x 0.26 x 0.11m, z=0.54..0.65
    add_box(0, Vector((0.02, -0.02, 0.595)), Vector((0.32, 0.26, 0.11)), rot_z_deg=-7.0)
    add_box(1, Vector((0.02, -0.02, 0.652)), Vector((0.324, 0.045, 0.004)), rot_z_deg=-7.0, bevel_w=0.0)

    uv_regions = {
        0: (0.02, 0.02, 0.66, 0.98),
        1: (0.70, 0.02, 0.98, 0.98),
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
    obj.name = "CardboardBoxes"
    obj.data.name = "CardboardBoxes_Mesh"

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

    mat = bpy.data.materials.new(name="Mat_CardboardBoxes")
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
        str(TEXTURE_DIR / "cardboard_boxes_albedo.png"), check_existing=True
    )
    tex_alb.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-400, 0)
    tex_orm.image = bpy.data.images.load(
        str(TEXTURE_DIR / "cardboard_boxes_orm.png"), check_existing=True
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
        str(TEXTURE_DIR / "cardboard_boxes_normal.png"), check_existing=True
    )
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -280)
    nrm_node.inputs["Strength"].default_value = 0.70
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.append(mat)

    glb_path = ASSET_DIR / "cardboard_boxes.glb"
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
        "prop_slug": "cardboard_boxes",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "materials": ["res://assets/models/cardboard_boxes/cardboard_boxes.tres"],
        "glb": "res://assets/models/cardboard_boxes/cardboard_boxes.glb",
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_CARDBOARD_BOXES:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    if "--generate-textures" in sys.argv:
        _generate_textures()
    else:
        _run_blender_build()
