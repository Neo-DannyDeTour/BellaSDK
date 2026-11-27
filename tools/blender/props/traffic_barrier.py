"""Procedural Post-Soviet Weathered Steel-Legged Street Traffic Barrier.

Generates weathered PBR texture maps via PIL/numpy + process_pbr.py, builds a
clean manifold steel-framed street traffic barrier (~1.50m x 0.55m x 1.05m)
with splayed steel base legs, welded foot plates, and two weathered orange/white
warning boards grounded at min_z = 0 (Godot min_y = 0). Exports GLB,
ORMMaterial3D .tres, and asset_manifest.json.

Run:
    /snap/bin/blender --background --python tools/blender/props/traffic_barrier.py
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "traffic_barrier"
TEXTURE_DIR: Path = ASSET_DIR / "textures"
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"

TRI_BUDGET: int = 1800
TEX_SIZE: int = 1024


def _generate_textures() -> None:
    """Synthesize clamped [30..240] sRGB weathered steel & warning board PBR maps."""
    import numpy as np
    from PIL import Image, ImageFilter

    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(64209)
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
    metallic = np.zeros((h, w), dtype=np.float32)

    split_x = int(w * 0.56)

    # --- Region 0 (UV u in [0.0, 0.56]): Weathered Orange/White Warning Board ---
    yy0, xx0 = np.mgrid[0:h, 0:split_x]
    u0 = xx0 / float(max(1, split_x))
    v0 = 1.0 - (yy0 / float(max(1, h)))

    stripe_phase = (u0 * 5.0 + v0 * 0.85) % 1.0
    is_orange = stripe_phase < 0.5
    warn_orange = np.array([208.0, 86.0, 32.0], dtype=np.float32)
    warn_white = np.array([214.0, 210.0, 198.0], dtype=np.float32)
    board_col = np.where(is_orange[..., None], warn_orange, warn_white)
    board_var = board_col * (
        0.86 + 0.18 * macro[:, :split_x, None] + 0.08 * (fine[:, :split_x, None] - 0.5)
    )

    # Scratches, grime & rust bleed at board edges
    chip_score = macro[:, :split_x] * 0.62 + fine[:, :split_x] * 0.38
    chip_mask = (chip_score > 0.71) | (v0 < 0.06) | (v0 > 0.94)
    rust_col = np.array([108.0, 62.0, 38.0], dtype=np.float32)
    albedo[:, :split_x, :] = np.where(chip_mask[..., None], rust_col, board_var)
    metallic[:, :split_x] = np.where(chip_mask, 0.25, 0.05)

    # --- Region 1 (UV u in [0.56, 1.0]): Rusted Galvanized Steel Frame & Legs ---
    steel_base = np.array([82.0, 80.0, 78.0], dtype=np.float32)
    steel_var = steel_base[None, None, :] * (
        0.82 + 0.28 * macro[:, split_x:, None] + 0.12 * fine[:, split_x:, None]
    )
    rust_patch = (macro[:, split_x:] * 0.58 + fine[:, split_x:] * 0.42) > 0.50
    heavy_rust = np.array([114.0, 64.0, 38.0], dtype=np.float32) * (
        0.85 + 0.24 * fine[:, split_x:, None]
    )
    albedo[:, split_x:, :] = np.where(rust_patch[..., None], heavy_rust, steel_var)
    metallic[:, split_x:] = np.where(rust_patch, 0.25, 0.78)

    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)
    alb_img = Image.fromarray(albedo_u8, mode="RGB").filter(ImageFilter.GaussianBlur(radius=0.3))
    alb_arr = np.clip(np.array(alb_img, dtype=np.uint8), 30, 240)
    albedo_path = TEXTURE_DIR / "traffic_barrier_albedo.png"
    Image.fromarray(alb_arr, mode="RGB").save(albedo_path, format="PNG")

    metallic_path = TEXTURE_DIR / "traffic_barrier_metallic.png"
    Image.fromarray(np.clip(metallic * 255.0, 0, 255).astype(np.uint8), mode="L").save(
        metallic_path, format="PNG"
    )

    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "derive-maps",
            str(albedo_path),
            "--out-dir",
            str(TEXTURE_DIR),
            "--slug",
            "traffic_barrier",
            "--preset",
            "metal",
            "--normal-strength",
            "1.6",
            "--base-roughness",
            "0.58",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEXTURE_DIR / "traffic_barrier_ao.png"
    rough_path = TEXTURE_DIR / "traffic_barrier_roughness.png"
    height_path = TEXTURE_DIR / "traffic_barrier_height.png"
    normal_path = TEXTURE_DIR / "traffic_barrier_normal.png"
    orm_path = TEXTURE_DIR / "traffic_barrier_orm.png"

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
            str(metallic_path),
            "--output",
            str(orm_path),
        ],
        check=True,
    )

    tres_path = ASSET_DIR / "traffic_barrier.tres"
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "build-tres",
            "--name",
            "traffic_barrier",
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

    for tmp in (ao_path, rough_path, height_path, metallic_path):
        tmp.unlink(missing_ok=True)


def _ensure_textures() -> None:
    required = [
        TEXTURE_DIR / "traffic_barrier_albedo.png",
        TEXTURE_DIR / "traffic_barrier_normal.png",
        TEXTURE_DIR / "traffic_barrier_orm.png",
        ASSET_DIR / "traffic_barrier.tres",
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

    # Groups: 0 = orange/white warning boards, 1 = rusted steel frame & splayed legs
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
        bevel_w: float = 0.0025,
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
        bmesh.ops.transform(tmp, matrix=Matrix.Translation(center), verts=tmp.verts)
        _merge_into(bms[group], tmp)

    def add_strut(group: int, p0: Vector, p1: Vector, width_x: float, depth_perp: float) -> None:
        axis = p1 - p0
        length = axis.length
        z_dir = axis.normalized()
        x_dir = Vector((1.0, 0.0, 0.0))
        y_dir = z_dir.cross(x_dir).normalized()
        rot = Matrix((
            (x_dir.x, y_dir.x, z_dir.x, 0.0),
            (x_dir.y, y_dir.y, z_dir.y, 0.0),
            (x_dir.z, y_dir.z, z_dir.z, 0.0),
            (0.0, 0.0, 0.0, 1.0),
        ))
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.scale(tmp, vec=Vector((width_x, depth_perp, length)), verts=tmp.verts)
        bmesh.ops.bevel(
            tmp,
            geom=list(tmp.edges),
            offset=0.002,
            segments=1,
            affect="EDGES",
            clamp_overlap=True,
        )
        xf = Matrix.Translation((p0 + p1) * 0.5) @ rot
        bmesh.ops.transform(tmp, matrix=xf, verts=tmp.verts)
        _merge_into(bms[group], tmp)

    # 1. Steel frame & splayed A-frame legs (Group 1, 1.50m x 0.55m x 1.05m)
    post_x = 0.66
    for sx in (-1.0, 1.0):
        px = sx * post_x
        # Main vertical upright tube
        add_box(1, Vector((px, 0.0, 0.56)), Vector((0.036, 0.036, 0.98)))
        # Splayed front/rear feet + horizontal base skid (0.55m total Y)
        add_box(1, Vector((px, 0.0, 0.012)), Vector((0.056, 0.55, 0.024)))
        # Diagonal leg braces from base ends up to upright
        add_strut(1, Vector((px, -0.24, 0.024)), Vector((px, -0.015, 0.34)), 0.030, 0.030)
        add_strut(1, Vector((px, 0.24, 0.024)), Vector((px, 0.015, 0.34)), 0.030, 0.030)

    # Top rail & lower cross rail
    add_box(1, Vector((0.0, 0.0, 1.035)), Vector((1.50, 0.034, 0.030)))
    add_box(1, Vector((0.0, 0.0, 0.43)), Vector((1.36, 0.032, 0.028)))
    # Top corner lamp/flag socket lugs
    for sx in (-1.0, 1.0):
        add_box(1, Vector((sx * post_x, 0.0, 1.05)), Vector((0.044, 0.044, 0.030)))

    # 2. Two horizontal weathered orange/white warning boards (Group 0)
    add_box(0, Vector((0.0, 0.0, 0.87)), Vector((1.46, 0.026, 0.20)), bevel_w=0.002)
    add_box(0, Vector((0.0, 0.0, 0.58)), Vector((1.46, 0.026, 0.16)), bevel_w=0.002)

    uv_regions = {
        0: (0.02, 0.02, 0.54, 0.98),
        1: (0.58, 0.02, 0.98, 0.98),
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

        if grp == 0:
            # Explicit planar UV projection (X -> U, Z -> V) for crisp orange/white stripes
            if not m.uv_layers:
                m.uv_layers.new(name="UVMap")
            uv_layer = m.uv_layers.active.data
            u0, v0, u1, v1 = uv_regions[grp]
            for poly in m.polygons:
                for li in poly.loop_indices:
                    co = m.vertices[m.loops[li].vertex_index].co
                    u_norm = (co.x + 0.73) / 1.46
                    v_norm = (co.z - 0.48) / 0.50
                    uv_layer[li].uv = (
                        u0 + max(0.0, min(1.0, u_norm)) * (u1 - u0),
                        v0 + max(0.0, min(1.0, v_norm)) * (v1 - v0),
                    )
        else:
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
    obj.name = "TrafficBarrier"
    obj.data.name = "TrafficBarrier_Mesh"

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

    mat = bpy.data.materials.new(name="Mat_TrafficBarrier")
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
        str(TEXTURE_DIR / "traffic_barrier_albedo.png"), check_existing=True
    )
    tex_alb.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-400, 0)
    tex_orm.image = bpy.data.images.load(
        str(TEXTURE_DIR / "traffic_barrier_orm.png"), check_existing=True
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
        str(TEXTURE_DIR / "traffic_barrier_normal.png"), check_existing=True
    )
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -280)
    nrm_node.inputs["Strength"].default_value = 0.75
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.append(mat)

    glb_path = ASSET_DIR / "traffic_barrier.glb"
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
        "prop_slug": "traffic_barrier",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "materials": ["res://assets/models/traffic_barrier/traffic_barrier.tres"],
        "glb": "res://assets/models/traffic_barrier/traffic_barrier.glb",
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_TRAFFIC_BARRIER:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    if "--generate-textures" in sys.argv:
        _generate_textures()
    else:
        _run_blender_build()
