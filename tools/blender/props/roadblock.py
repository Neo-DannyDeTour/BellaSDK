"""Procedural Post-Soviet Concrete/Plastic Jersey Roadblock Barrier.

Generates weathered PBR texture maps via PIL/numpy + process_pbr.py, builds a
clean manifold Jersey barrier (~1.80m x 0.60m x 0.85m) with forklift recesses,
hazard stripe wear, end interlocking keyways, and a rusted steel top post
socket grounded at min_z = 0 (Godot min_y = 0). Exports GLB, ORMMaterial3D
.tres, and asset_manifest.json.

Run:
    /snap/bin/blender --background --python tools/blender/props/roadblock.py
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "roadblock"
TEXTURE_DIR: Path = ASSET_DIR / "textures"
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"

TARGET_LENGTH_M: float = 1.80
TARGET_WIDTH_M: float = 0.60
TARGET_HEIGHT_M: float = 0.85
TRI_BUDGET: int = 1500
TEX_SIZE: int = 1024


def _generate_textures() -> None:
    """Synthesize clamped [30..240] sRGB weathered PBR maps and Godot .tres."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(77104)
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

    split_x = int(w * 0.64)
    split_y = int(h * 0.66)  # PIL y < split_y => UV v > 0.34

    # --- Region 0 (UV u in [0.0, 0.64]): Weathered Poured Concrete ---
    conc_base = np.array([128.0, 125.0, 118.0], dtype=np.float32)
    conc_var = conc_base[None, None, :] * (
        0.82 + 0.24 * macro[:, :split_x, None] + 0.10 * (fine[:, :split_x, None] - 0.5)
    )
    # Aggregate pitting & grime mottling
    pit_mask = (macro[:, :split_x] * 0.55 + fine[:, :split_x] * 0.45) < 0.30
    pit_col = np.array([76.0, 74.0, 70.0], dtype=np.float32)
    conc_var = np.where(pit_mask[..., None], conc_var * 0.72 + pit_col * 0.28, conc_var)
    albedo[:, :split_x, :] = conc_var
    metallic[:, :split_x] = 0.0

    # --- Region 1 (UV u in [0.64, 1.0], PIL y < split_y): Hazard-Striped Upper Concrete ---
    yy1, xx1 = np.mgrid[0:split_y, split_x:w]
    u1 = (xx1 - split_x) / float(max(1, w - split_x))
    v1 = 1.0 - (yy1 / float(max(1, split_y)))

    # Diagonal hazard stripes (45 deg) across the band
    stripe_phase = ((u1 * 4.5 + v1 * 1.2) % 1.0)
    is_yellow = stripe_phase < 0.5
    haz_yellow = np.array([198.0, 148.0, 42.0], dtype=np.float32)
    haz_black = np.array([44.0, 43.0, 41.0], dtype=np.float32)
    stripe_col = np.where(is_yellow[..., None], haz_yellow, haz_black)

    # Heavy paint flaking & concrete bleed-through
    conc_bleed = conc_base[None, None, :] * (0.85 + 0.22 * macro[:split_y, split_x:, None])
    wear_score = macro[:split_y, split_x:] * 0.62 + fine[:split_y, split_x:] * 0.38
    peel_mask = (wear_score > 0.62) | (v1 < 0.14) | (v1 > 0.88)
    stripe_weathered = stripe_col * (0.85 + 0.20 * (fine[:split_y, split_x:, None] - 0.5))
    albedo[:split_y, split_x:, :] = np.where(peel_mask[..., None], conc_bleed, stripe_weathered)
    metallic[:split_y, split_x:] = 0.0

    # --- Region 2 (UV u in [0.64, 1.0], PIL y >= split_y): Rusted Steel Socket & Lugs ---
    steel_base = np.array([84.0, 80.0, 76.0], dtype=np.float32)
    steel_var = steel_base[None, None, :] * (
        0.80 + 0.28 * macro[split_y:, split_x:, None] + 0.14 * fine[split_y:, split_x:, None]
    )
    rust_patch = (macro[split_y:, split_x:] * 0.6 + fine[split_y:, split_x:] * 0.4) > 0.48
    rust_col = np.array([112.0, 62.0, 38.0], dtype=np.float32) * (
        0.85 + 0.25 * fine[split_y:, split_x:, None]
    )
    albedo[split_y:, split_x:, :] = np.where(rust_patch[..., None], rust_col, steel_var)
    metallic[split_y:, split_x:] = np.where(rust_patch, 0.25, 0.80)

    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)
    alb_img = Image.fromarray(albedo_u8, mode="RGB")

    # Subtle vertical rain/grime streaks in Region 0
    draw = ImageDraw.Draw(alb_img)
    for _ in range(36):
        x0 = int(rng.integers(12, split_x - 12))
        y0 = int(rng.integers(12, h - 90))
        dy = int(rng.integers(24, 80))
        draw.line((x0, y0, x0, y0 + dy), fill=(68, 66, 62), width=2)
    alb_img = alb_img.filter(ImageFilter.GaussianBlur(radius=0.35))

    alb_arr = np.clip(np.array(alb_img, dtype=np.uint8), 30, 240)
    albedo_path = TEXTURE_DIR / "roadblock_albedo.png"
    Image.fromarray(alb_arr, mode="RGB").save(albedo_path, format="PNG")

    metallic_path = TEXTURE_DIR / "roadblock_metallic.png"
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
            "roadblock",
            "--preset",
            "stone",
            "--normal-strength",
            "2.0",
            "--base-roughness",
            "0.84",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEXTURE_DIR / "roadblock_ao.png"
    rough_path = TEXTURE_DIR / "roadblock_roughness.png"
    height_path = TEXTURE_DIR / "roadblock_height.png"
    normal_path = TEXTURE_DIR / "roadblock_normal.png"
    orm_path = TEXTURE_DIR / "roadblock_orm.png"

    # Slightly lower roughness on bare steel socket (Region 2)
    rough_arr = np.array(Image.open(rough_path).convert("L"), dtype=np.uint8)
    rough_arr[split_y:, split_x:] = np.clip(
        rough_arr[split_y:, split_x:].astype(np.int32) - 55, 95, 220
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
            str(metallic_path),
            "--output",
            str(orm_path),
        ],
        check=True,
    )

    tres_path = ASSET_DIR / "roadblock.tres"
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "build-tres",
            "--name",
            "roadblock",
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
        TEXTURE_DIR / "roadblock_albedo.png",
        TEXTURE_DIR / "roadblock_normal.png",
        TEXTURE_DIR / "roadblock_orm.png",
        ASSET_DIR / "roadblock.tres",
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
    # 0 = weathered concrete body
    # 1 = hazard-striped upper band
    # 2 = rusted steel post socket + lifting lugs
    bms = {0: bmesh.new(), 1: bmesh.new(), 2: bmesh.new()}

    def _merge_into(dst: bmesh.types.BMesh, src: bmesh.types.BMesh) -> None:
        vmap = {v.index: dst.verts.new(v.co) for v in src.verts}
        for f in src.faces:
            dst.faces.new([vmap[v.index] for v in f.verts])
        src.free()

    def add_box(
        group: int,
        center: Vector,
        size: Vector,
        bevel_w: float = 0.008,
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

    # Jersey barrier profile extruded along X (length 1.80m)
    # Profile points (y, z) in CCW order:
    # Base width 0.60m (y in [-0.30, 0.30]), haunch to 0.30m at z=0.34, top 0.18m at z=0.85
    half_x = TARGET_LENGTH_M * 0.5
    profile = [
        (-0.30, 0.00),
        (0.30, 0.00),
        (0.30, 0.15),
        (0.15, 0.33),
        (0.095, 0.84),
        (0.075, 0.85),
        (-0.075, 0.85),
        (-0.095, 0.84),
        (-0.15, 0.33),
        (-0.30, 0.15),
    ]

    # Build main concrete body in Group 0, plus thin hazard-stripe panel faces on Group 1
    bm_body = bms[0]
    rings: list[list[bmesh.types.BMVert]] = []
    # Slice along X to form forklift recesses at base and crisp end bevels
    x_stations = [-half_x, -half_x + 0.02, -0.52, -0.34, 0.34, 0.52, half_x - 0.02, half_x]
    for xi, x_val in enumerate(x_stations):
        shrink = 0.96 if xi in (0, len(x_stations) - 1) else 1.0
        ring = []
        for py, pz in profile:
            # Slight lift at forklift notch stations (-0.52..-0.34 and 0.34..0.52)
            z_mod = pz
            if xi in (2, 3, 4, 5) and abs(pz) < 0.01:
                z_mod = 0.055 if xi in (2, 5) else 0.055
            v = bm_body.verts.new((x_val, py * shrink, z_mod))
            ring.append(v)
        rings.append(ring)

    n_pts = len(profile)
    for ri in range(len(rings) - 1):
        r0 = rings[ri]
        r1 = rings[ri + 1]
        for pi in range(n_pts):
            pn = (pi + 1) % n_pts
            bm_body.faces.new((r0[pi], r0[pn], r1[pn], r1[pi]))

    # Cap ends
    bm_body.faces.new(list(reversed(rings[0])))
    bm_body.faces.new(rings[-1])

    # Hazard stripe band overlay (Group 1) seated 2mm proud on upper wall front & back
    # Spans x in [-0.76, 0.76], z in [0.46, 0.74] following wall slope
    def _wall_y(z_val: float) -> float:
        t = (z_val - 0.33) / (0.84 - 0.33)
        return 0.15 + (0.095 - 0.15) * t

    for sign_y in (-1.0, 1.0):
        z_bot, z_top = 0.46, 0.74
        y_bot = sign_y * (_wall_y(z_bot) + 0.0025)
        y_top = sign_y * (_wall_y(z_top) + 0.0025)
        x0, x1 = -0.76, 0.76
        v0 = bms[1].verts.new((x0, y_bot, z_bot))
        v1 = bms[1].verts.new((x1, y_bot, z_bot))
        v2 = bms[1].verts.new((x1, y_top, z_top))
        v3 = bms[1].verts.new((x0, y_top, z_top))
        if sign_y > 0:
            bms[1].faces.new((v0, v1, v2, v3))
        else:
            bms[1].faces.new((v3, v2, v1, v0))

    # Steel post socket collar on top center + 2 recessed rebar lifting lugs (Group 2)
    add_box(2, Vector((0.0, 0.0, 0.856)), Vector((0.14, 0.13, 0.016)), bevel_w=0.003)
    add_box(2, Vector((0.0, 0.0, 0.885)), Vector((0.085, 0.085, 0.055)), bevel_w=0.004)
    for lx in (-0.58, 0.58):
        add_box(2, Vector((lx, 0.0, 0.862)), Vector((0.055, 0.022, 0.028)), bevel_w=0.003)

    uv_regions = {
        0: (0.02, 0.02, 0.62, 0.98),
        1: (0.66, 0.36, 0.98, 0.98),
        2: (0.66, 0.02, 0.98, 0.32),
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

        if grp == 1:
            # Explicit planar UV projection (X -> U, Z -> V) so diagonal hazard stripes stay crisp
            if not m.uv_layers:
                m.uv_layers.new(name="UVMap")
            uv_layer = m.uv_layers.active.data
            u0, v0, u1, v1 = uv_regions[grp]
            for poly in m.polygons:
                for li in poly.loop_indices:
                    co = m.vertices[m.loops[li].vertex_index].co
                    u_norm = (co.x + 0.76) / 1.52
                    v_norm = (co.z - 0.46) / (0.74 - 0.46)
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
    obj.name = "Roadblock"
    obj.data.name = "Roadblock_Mesh"

    # Ground min_z = 0, center XY at origin
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

    mat = bpy.data.materials.new(name="Mat_Roadblock")
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
    tex_alb.image = bpy.data.images.load(str(TEXTURE_DIR / "roadblock_albedo.png"), check_existing=True)
    tex_alb.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-400, 0)
    tex_orm.image = bpy.data.images.load(str(TEXTURE_DIR / "roadblock_orm.png"), check_existing=True)
    tex_orm.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-120, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-400, -280)
    tex_nrm.image = bpy.data.images.load(str(TEXTURE_DIR / "roadblock_normal.png"), check_existing=True)
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -280)
    nrm_node.inputs["Strength"].default_value = 0.85
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.append(mat)

    glb_path = ASSET_DIR / "roadblock.glb"
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
        "prop_slug": "roadblock",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "materials": ["res://assets/models/roadblock/roadblock.tres"],
        "glb": "res://assets/models/roadblock/roadblock.glb",
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_ROADBLOCK:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    if "--generate-textures" in sys.argv:
        _generate_textures()
    else:
        _run_blender_build()
