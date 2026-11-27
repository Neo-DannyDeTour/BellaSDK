"""Procedural Folding Yellow Parking Lock (Tubular Steel A-Frame Blocker).

Generates weathered PBR texture maps via PIL/numpy + process_pbr.py, builds a
clean manifold A-frame parking blocker with base rail and pivot hinges grounded
at min_z = 0 (Godot min_y = 0) and exact 0.52m height, exports GLB with wired
PBR textures, generates Godot 4 ORMMaterial3D .tres, and writes asset_manifest.json.

Run:
    python3 tools/blender/run.py tools/blender/props/yellow_parking_lock.py
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "yellow_parking_lock"
TEXTURE_DIR: Path = ASSET_DIR / "textures"
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"
REFERENCE_IMAGE: str = "/home/dkd/Desktop/Refs/IMG_20261125_163759.jpg"

TARGET_HEIGHT_M: float = 0.52
TRI_BUDGET: int = 2500
TEX_SIZE: int = 1024


def _generate_textures() -> None:
    """Synthesize clamped [30..240] sRGB weathered PBR maps and Godot .tres."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(40231)
    h = TEX_SIZE
    w = TEX_SIZE

    # Multi-scale tileable/smooth noise helpers
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

    # --- Region A (UV u in [0.0, 0.68]): Weathered Safety Yellow Painted Steel ---
    split_x = int(w * 0.68)
    split_y = int(h * 0.65)  # PIL y < split_y => UV v > 0.35

    yellow_base = np.array([230.0, 184.0, 38.0], dtype=np.float32)
    yellow_var = yellow_base[None, None, :] * (
        0.93 + 0.11 * macro[:, :split_x, None] + 0.04 * (fine[:, :split_x, None] - 0.5)
    )

    # Sparse localized paint chips & rust flecks (avoid noisy speckling)
    chip_score = macro[:, :split_x] * 0.65 + fine[:, :split_x] * 0.35
    chip_mask = chip_score > 0.78
    rust_col = np.array([104.0, 62.0, 38.0], dtype=np.float32)
    scuff_col = np.array([86.0, 82.0, 74.0], dtype=np.float32)
    dark_fleck = (fine[:, :split_x] > 0.60)[..., None]
    chip_color = np.where(dark_fleck, rust_col, scuff_col)

    albedo[:, :split_x, :] = np.where(chip_mask[..., None], chip_color, yellow_var)
    metallic[:, :split_x] = np.where(chip_mask, 0.65, 0.05)

    # Subtle dusty/faded paint patches
    dust_mask = (macro[:, :split_x] < 0.24) & (fine[:, :split_x] > 0.60)
    dust_col = np.array([175.0, 158.0, 96.0], dtype=np.float32)
    albedo[:, :split_x, :] = np.where(
        dust_mask[..., None],
        albedo[:, :split_x, :] * 0.65 + dust_col * 0.35,
        albedo[:, :split_x, :],
    )

    # --- Region B (UV u in [0.68, 1.0], v in [0.35, 1.0] -> PIL y < split_y): Rusted Steel Hardware ---
    steel_base = np.array([76.0, 72.0, 68.0], dtype=np.float32)
    steel_var = steel_base[None, None, :] * (
        0.82 + 0.30 * macro[:split_y, split_x:, None] + 0.12 * fine[:split_y, split_x:, None]
    )
    rust_patch = (macro[:split_y, split_x:] * 0.6 + fine[:split_y, split_x:] * 0.4) > 0.52
    heavy_rust = np.array([116.0, 66.0, 40.0], dtype=np.float32) * (
        0.85 + 0.22 * fine[:split_y, split_x:, None]
    )
    albedo[:split_y, split_x:, :] = np.where(rust_patch[..., None], heavy_rust, steel_var)
    metallic[:split_y, split_x:] = np.where(rust_patch, 0.30, 0.82)

    # --- Region C (UV u in [0.68, 1.0], v in [0.0, 0.35] -> PIL y >= split_y): Grey Webbing Strap ---
    yy, xx = np.mgrid[split_y:h, split_x:w]
    weave = 0.5 + 0.5 * np.sin(xx * 0.9) * np.sin(yy * 0.9)
    strap_base = np.array([112.0, 116.0, 118.0], dtype=np.float32)
    strap_var = strap_base[None, None, :] * (
        0.86 + 0.14 * weave[..., None] + 0.10 * (macro[split_y:, split_x:, None] - 0.5)
    )
    albedo[split_y:, split_x:, :] = strap_var
    metallic[split_y:, split_x:] = 0.0

    # Clamp strictly to valid PBR sRGB bounds [30, 240]
    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)
    alb_img = Image.fromarray(albedo_u8, mode="RGB")

    # Add a few tiny localized edge scuffs inside Region A
    draw = ImageDraw.Draw(alb_img)
    for _ in range(24):
        x0 = int(rng.integers(16, split_x - 32))
        y0 = int(rng.integers(16, h - 32))
        dx = int(rng.integers(-14, 15))
        dy = int(rng.integers(-14, 15))
        draw.line((x0, y0, x0 + dx, y0 + dy), fill=(110, 84, 52), width=1)
    alb_img = alb_img.filter(ImageFilter.GaussianBlur(radius=0.3))

    # Re-clamp after blur
    alb_arr = np.clip(np.array(alb_img, dtype=np.uint8), 30, 240)
    albedo_path = TEXTURE_DIR / "yellow_parking_lock_albedo.png"
    Image.fromarray(alb_arr, mode="RGB").save(albedo_path, format="PNG")

    metallic_path = TEXTURE_DIR / "yellow_parking_lock_metallic.png"
    Image.fromarray(np.clip(metallic * 255.0, 0, 255).astype(np.uint8), mode="L").save(
        metallic_path, format="PNG"
    )

    # Derive Normal (+Y), AO, Roughness using process_pbr.py (non-seamless UV atlas)
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "derive-maps",
            str(albedo_path),
            "--out-dir",
            str(TEXTURE_DIR),
            "--slug",
            "yellow_parking_lock",
            "--preset",
            "metal",
            "--normal-strength",
            "1.8",
            "--base-roughness",
            "0.46",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEXTURE_DIR / "yellow_parking_lock_ao.png"
    rough_path = TEXTURE_DIR / "yellow_parking_lock_roughness.png"
    height_path = TEXTURE_DIR / "yellow_parking_lock_height.png"
    normal_path = TEXTURE_DIR / "yellow_parking_lock_normal.png"
    orm_path = TEXTURE_DIR / "yellow_parking_lock_orm.png"

    # Raise roughness on fabric strap region (Region C) so webbing stays matte
    rough_arr = np.array(Image.open(rough_path).convert("L"), dtype=np.uint8)
    rough_arr[split_y:, split_x:] = np.clip(
        rough_arr[split_y:, split_x:].astype(np.int32) + 85, 190, 242
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

    tres_path = ASSET_DIR / "yellow_parking_lock.tres"
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "build-tres",
            "--name",
            "yellow_parking_lock",
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

    # Remove intermediate single-channel maps so only final PBR maps remain
    for tmp in (ao_path, rough_path, height_path, metallic_path):
        tmp.unlink(missing_ok=True)


def _ensure_textures() -> None:
    required = [
        TEXTURE_DIR / "yellow_parking_lock_albedo.png",
        TEXTURE_DIR / "yellow_parking_lock_normal.png",
        TEXTURE_DIR / "yellow_parking_lock_orm.png",
        ASSET_DIR / "yellow_parking_lock.tres",
    ]
    if all(p.is_file() for p in required):
        return
    env = os.environ.copy()
    # Invoke system Python3 (PIL + numpy) cleanly from Snap Blender
    subprocess.run(["/usr/bin/python3", str(Path(__file__).resolve()), "--generate-textures"], env=env, check=True)


def _run_blender_build() -> None:
    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))

    import bmesh
    import bpy
    from mathutils import Matrix, Vector
    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures()
    clean_scene()

    # Helper builders tagging each bmesh face with region ID:
    # 0 = yellow painted steel, 1 = dark rusted/galvanized hardware/base, 2 = grey webbing strap
    bms = {0: bmesh.new(), 1: bmesh.new(), 2: bmesh.new()}

    def add_box(group: int, center: Vector, size: Vector, rot_xform: Matrix | None = None, bevel_w: float = 0.0025) -> None:
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.scale(tmp, vec=size, verts=tmp.verts)
        if bevel_w > 0.0:
            bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bevel_w, segments=1, affect="EDGES", clamp_overlap=True)
        xf = Matrix.Translation(center)
        if rot_xform is not None:
            xf = xf @ rot_xform
        bmesh.ops.transform(tmp, matrix=xf, verts=tmp.verts)
        _merge_into(bms[group], tmp)

    def add_strut(group: int, p0: Vector, p1: Vector, width_x: float, depth_perp: float, bevel_w: float = 0.0025) -> None:
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
        add_box(group, (p0 + p1) * 0.5, Vector((width_x, depth_perp, length)), rot_xform=rot, bevel_w=bevel_w)

    def add_cyl_x(group: int, center: Vector, length: float, radius: float, segs: int = 10) -> None:
        tmp = bmesh.new()
        rot = Matrix.Rotation(math.radians(90.0), 4, "Y")
        bmesh.ops.create_cone(
            tmp,
            cap_ends=True,
            cap_tris=False,
            segments=segs,
            radius1=radius,
            radius2=radius,
            depth=length,
            matrix=Matrix.Translation(center) @ rot,
        )
        _merge_into(bms[group], tmp)

    def add_cyl_z(group: int, center: Vector, height: float, radius: float, segs: int = 6) -> None:
        tmp = bmesh.new()
        bmesh.ops.create_cone(
            tmp,
            cap_ends=True,
            cap_tris=False,
            segments=segs,
            radius1=radius,
            radius2=radius,
            depth=height,
            matrix=Matrix.Translation(center),
        )
        _merge_into(bms[group], tmp)

    def _merge_into(dst: bmesh.types.BMesh, src: bmesh.types.BMesh) -> None:
        vmap = {v.index: dst.verts.new(v.co) for v in src.verts}
        for f in src.faces:
            dst.faces.new([vmap[v.index] for v in f.verts])
        src.free()

    # Geometry dimensions (meters; Blender +Z is Godot +Y)
    arm_x = 0.250
    rear_y = 0.365
    apex_y = -0.155
    front_y = -0.295
    apex_z = 0.494  # + half tube / top bar reaches 0.520m

    # 1. Base rail assembly (Group 1: dark weathered/galvanized steel resting flat at Z=0)
    rail_h = 0.012
    rail_w = 0.052
    for sx in (-1.0, 1.0):
        # Longitudinal base rail
        add_box(1, Vector((sx * arm_x, 0.025, rail_h * 0.5)), Vector((rail_w, 0.77, rail_h)), bevel_w=0.0015)
        # Anchor bolt pads & hex anchor bolts (front & rear)
        for by in (-0.335, 0.375):
            add_cyl_z(1, Vector((sx * arm_x, by, rail_h + 0.005)), height=0.010, radius=0.011, segs=6)
    # Front and rear cross base bars tying the rails together
    add_box(1, Vector((0.0, front_y, rail_h * 0.5)), Vector((arm_x * 2.0 + rail_w, 0.044, rail_h)), bevel_w=0.0015)
    add_box(1, Vector((0.0, rear_y - 0.015, rail_h * 0.5)), Vector((arm_x * 2.0 + rail_w, 0.038, rail_h)), bevel_w=0.0015)

    # Central ground latch / padlock loop tab on front base rail
    add_box(1, Vector((0.0, front_y - 0.028, 0.016)), Vector((0.034, 0.016, 0.032)), bevel_w=0.0015)

    # 2. Pivot hinge brackets & pins (Group 1)
    for sx in (-1.0, 1.0):
        x0 = sx * arm_x
        # Front pivot hinge clevis ears + pin
        for ear_off in (-0.025, 0.025):
            add_box(1, Vector((x0 + ear_off, front_y, 0.036)), Vector((0.007, 0.046, 0.048)), bevel_w=0.001)
        add_cyl_x(1, Vector((x0, front_y, 0.038)), length=0.070, radius=0.0085, segs=8)

        # Rear pivot hinge clevis ears + pin
        for ear_off in (-0.026, 0.026):
            add_box(1, Vector((x0 + ear_off, rear_y - 0.025, 0.030)), Vector((0.007, 0.044, 0.038)), bevel_w=0.001)
        add_cyl_x(1, Vector((x0, rear_y - 0.025, 0.030)), length=0.072, radius=0.0085, segs=8)

    # 3. Tubular steel A-frame arms (Group 0: safety yellow painted steel)
    for sx in (-1.0, 1.0):
        x0 = sx * arm_x
        # Rear long diagonal square tube (42mm)
        p_rear_bot = Vector((x0, rear_y, 0.024))
        p_apex = Vector((x0, apex_y, apex_z))
        add_strut(0, p_rear_bot, p_apex, width_x=0.042, depth_perp=0.042, bevel_w=0.0025)

        # Rusted mitered ground tip shoe at rear tip (Group 1, sits flush on Z=0.002)
        add_box(1, Vector((x0, rear_y + 0.022, 0.014)), Vector((0.044, 0.032, 0.024)), bevel_w=0.0015)

        # Front steep square tube strut (38mm)
        p_front_bot = Vector((x0, front_y, 0.038))
        add_strut(0, p_front_bot, p_apex, width_x=0.038, depth_perp=0.038, bevel_w=0.0025)

        # Small side guide lugs on rear arm (visible in reference photo)
        mid_arm = p_rear_bot.lerp(p_apex, 0.36)
        add_box(0, mid_arm + Vector((sx * 0.024, 0.0, 0.0)), Vector((0.012, 0.026, 0.018)), bevel_w=0.001)

    # 4. Top apex crossbar & rear lower crossbar (Group 0 + Group 1 end bolts/collars)
    # Top crossbar (reaches exact 0.52m height with 0.018m radius or top collar at 0.52m)
    add_cyl_x(0, Vector((0.0, apex_y, apex_z)), length=arm_x * 2.0 + 0.068, radius=0.016, segs=10)
    # Apex mounting plates & bolts (Group 1)
    for sx in (-1.0, 1.0):
        add_box(1, Vector((sx * arm_x, apex_y, apex_z + 0.004)), Vector((0.050, 0.046, 0.044)), bevel_w=0.002)
        add_cyl_x(1, Vector((sx * (arm_x + 0.036), apex_y, apex_z)), length=0.014, radius=0.011, segs=6)

    # Rear lower crossbar connecting the two rear diagonal arms
    rear_bar_t = 0.20
    rear_bar_y = rear_y + (apex_y - rear_y) * rear_bar_t
    rear_bar_z = 0.024 + (apex_z - 0.024) * rear_bar_t
    add_cyl_x(0, Vector((0.0, rear_bar_y, rear_bar_z)), length=arm_x * 2.0 + 0.056, radius=0.014, segs=10)
    for sx in (-1.0, 1.0):
        add_cyl_x(1, Vector((sx * (arm_x - 0.024), rear_bar_y, rear_bar_z)), length=0.012, radius=0.020, segs=10)
        add_cyl_x(1, Vector((sx * (arm_x + 0.028), rear_bar_y, rear_bar_z)), length=0.012, radius=0.012, segs=6)

    # 5. Folded grey webbing safety/stop strap tucked cleanly around front hinge (Group 2)
    for sx in (-1.0, 1.0):
        x0 = sx * arm_x
        add_box(2, Vector((x0 + sx * 0.022, front_y + 0.024, 0.088)), Vector((0.008, 0.018, 0.090)), bevel_w=0.0015)
        add_box(2, Vector((x0, front_y + 0.022, 0.130)), Vector((0.048, 0.020, 0.010)), bevel_w=0.0015)

    # Build temporary objects per group so smart_project creates strictly non-overlapping atlas UVs
    uv_regions = {
        0: (0.02, 0.02, 0.66, 0.98),  # u0, v0, u1, v1
        1: (0.70, 0.37, 0.98, 0.98),
        2: (0.70, 0.02, 0.98, 0.33),
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

        # Remap UVs into group's disjoint atlas rectangle
        u0, v0, u1, v1 = uv_regions[grp]
        du = u1 - u0
        dv = v1 - v0
        uv_layer = m.uv_layers.active.data
        for poly in m.polygons:
            for li in poly.loop_indices:
                uv = uv_layer[li].uv
                uv_layer[li].uv = (u0 + uv.x * du, v0 + uv.y * dv)

        part_objs.append(o)

    # Join all parts into single YellowParkingLock object
    bpy.ops.object.select_all(action="DESELECT")
    for o in part_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = part_objs[0]
    bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = "YellowParkingLock"
    obj.data.name = "YellowParkingLock_Mesh"

    # Ground min_z = 0, center XY at origin, and scale Z uniformly only if needed to hit exact 0.52m
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    min_z = min(zs)
    cur_h = max(zs) - min_z
    scale_factor = TARGET_HEIGHT_M / cur_h if cur_h > 1e-5 else 1.0
    for v in obj.data.vertices:
        v.co.x = (v.co.x - cx) * scale_factor
        v.co.y = (v.co.y - cy) * scale_factor
        v.co.z = (v.co.z - min_z) * scale_factor
    obj.data.update()

    # Smooth shading + WeightedNormal for crisp hard-surface bevel highlights
    bpy.ops.object.shade_smooth()
    wn = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    wn.weight = 50
    bpy.ops.object.modifier_apply(modifier=wn.name)

    # Wire PBR textures into Principled BSDF so GLB exports textured material
    mat = bpy.data.materials.new(name="Mat_YellowParkingLock")
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
    tex_alb.image = bpy.data.images.load(str(TEXTURE_DIR / "yellow_parking_lock_albedo.png"), check_existing=True)
    tex_alb.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-400, 0)
    tex_orm.image = bpy.data.images.load(str(TEXTURE_DIR / "yellow_parking_lock_orm.png"), check_existing=True)
    tex_orm.image.colorspace_settings.name = "Non-Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-120, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-400, -280)
    tex_nrm.image = bpy.data.images.load(str(TEXTURE_DIR / "yellow_parking_lock_normal.png"), check_existing=True)
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -280)
    nrm_node.inputs["Strength"].default_value = 0.75
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.append(mat)

    # Export GLB
    glb_path = ASSET_DIR / "yellow_parking_lock.glb"
    export_godot_glb(glb_path, export_animations=False)

    # Stats & asset_manifest.json (Godot coords: X=x, Y=z(up), Z=y)
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
        "prop_slug": "yellow_parking_lock",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "reference_image": REFERENCE_IMAGE,
        "materials": ["res://assets/models/yellow_parking_lock/yellow_parking_lock.tres"],
        "glb": "res://assets/models/yellow_parking_lock/yellow_parking_lock.glb",
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_YELLOW_PARKING_LOCK:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    if "--generate-textures" in sys.argv:
        _generate_textures()
    else:
        _run_blender_build()
