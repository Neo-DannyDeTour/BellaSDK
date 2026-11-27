"""Procedural Post-Soviet Towable Floodlight Tower & Diesel Generator.

Generates a weathered ~2.40m x 1.30m x 3.50m towable construction floodlight
tower & diesel generator in Post-Soviet Industrial Gothic style with
non-overlapping quadrant UVs, photorealistic weathered PBR textures derived
from BellaSDK scans via process_pbr.py, Godot 4 ORMMaterial3D (.tres), GLB,
and asset_manifest.json.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/light_generator.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/light_generator.py --gen-textures
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

PROP_SLUG: str = "light_generator"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TARGET_HEIGHT_M: float = 3.50
TRI_BUDGET: int = 4000

SRC_ORANGE_DIR: Path = REPO_ROOT / "assets" / "materials" / "rusty_orange_metal" / "textures"
SRC_METAL_DIR: Path = REPO_ROOT / "assets" / "materials" / "painted_industrial_metal" / "textures"
SRC_RUST_DIR: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
SRC_RUBBER_DIR: Path = REPO_ROOT / "assets" / "materials" / "ribbed_black_cable_rubber" / "textures"

# Proportions in meters (Blender Z-up, hitch facing -Y, mast at +Y rear)
WHEEL_R: float = 0.31
WHEEL_W: float = 0.18
CHASSIS_W: float = 0.96
CHASSIS_L: float = 1.62
CHASSIS_BOT_Z: float = 0.34
CHASSIS_TOP_Z: float = 0.44

CANOPY_W: float = 0.92
CANOPY_L: float = 1.42
CANOPY_TOP_Z: float = 1.28

MAST_TOP_Z: float = 3.36
CROSSBAR_Z: float = 3.30


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    """Load an image as float32 RGB resized to (size, size)."""
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def _make_weathered_yellow_housing(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Derive weathered industrial yellow/ochre painted steel from rusty_orange_metal + painted_industrial_metal."""
    import numpy as np

    org_alb = _load_square_rgb(SRC_ORANGE_DIR / "rusty_orange_metal_albedo.png", size)
    org_nrm = _load_square_rgb(SRC_ORANGE_DIR / "rusty_orange_metal_normal.png", size)
    org_rgh = _load_square_rgb(SRC_ORANGE_DIR / "rusty_orange_metal_roughness.png", size)[..., 0] / 255.0
    mtl_alb = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_albedo.png", size)

    # Identify rust/dark chips from painted_industrial_metal luminance
    mtl_lum = (0.299 * mtl_alb[..., 0] + 0.587 * mtl_alb[..., 1] + 0.114 * mtl_alb[..., 2]) / 255.0
    rust_mask = np.clip((0.42 - mtl_lum) * 2.2, 0.0, 0.78)

    # Desaturated Post-Soviet mustard-ochre construction yellow
    ochre = np.array([182.0, 138.0, 48.0], dtype=np.float32)
    org_lum = (0.299 * org_alb[..., 0] + 0.587 * org_alb[..., 1] + 0.114 * org_alb[..., 2]) / 255.0
    paint_col = ochre[None, None, :] * (0.78 + org_lum[..., None] * 0.38)
    rust_col = org_alb * 0.52 + np.array([76.0, 44.0, 30.0], dtype=np.float32)[None, None, :] * 0.48

    col = paint_col * (1.0 - rust_mask[..., None]) + rust_col * rust_mask[..., None]

    # Subtle grime & soot darkening near bottom
    v_grad = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None]
    grime = np.clip((v_grad - 0.75) / 0.25, 0.0, 1.0) * 0.40
    col *= (1.0 - grime[..., None])

    rough = np.clip(0.48 + org_rgh * 0.20 + rust_mask * 0.20, 0.45, 0.82)
    nrm = (org_nrm - 128.0) * 0.65 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def _make_chassis_steel(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Dark oxidized/galvanized steel for trailer frame, hitch, mast, and exhaust."""
    import numpy as np

    rust_alb = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_albedo.png", size)
    rust_nrm = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_normal.png", size)
    gunmetal = np.array([82.0, 86.0, 90.0], dtype=np.float32)
    col = rust_alb * 0.50 + gunmetal[None, None, :] * 0.50
    lum = (0.299 * rust_alb[..., 0] + 0.587 * rust_alb[..., 1] + 0.114 * rust_alb[..., 2]) / 255.0
    rough = np.clip(0.44 + (1.0 - lum) * 0.30, 0.40, 0.78)
    nrm = (rust_nrm - 128.0) * 0.65 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def _make_rubber_tires(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Heavy dusty black rubber for tires, mudflaps, and power cable."""
    import numpy as np

    rub_alb = _load_square_rgb(SRC_RUBBER_DIR / "ribbed_black_cable_rubber_albedo.png", size)
    rub_nrm = _load_square_rgb(SRC_RUBBER_DIR / "ribbed_black_cable_rubber_normal.png", size)
    col = rub_alb * 0.85 + np.array([18.0, 17.0, 15.0], dtype=np.float32)[None, None, :]
    lum = (0.299 * rub_alb[..., 0] + 0.587 * rub_alb[..., 1] + 0.114 * rub_alb[..., 2]) / 255.0
    rough = np.clip(0.76 + (1.0 - lum) * 0.16, 0.72, 0.92)
    nrm = (rub_nrm - 128.0) * 0.65 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def _make_floodlight_lens(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Weathered halogen/LED floodlight reflector & frosted glass face."""
    import numpy as np

    mtl_alb = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_albedo.png", size)
    mtl_nrm = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_normal.png", size)
    lum = (0.299 * mtl_alb[..., 0] + 0.587 * mtl_alb[..., 1] + 0.114 * mtl_alb[..., 2]) / 255.0
    base = np.array([188.0, 192.0, 184.0], dtype=np.float32)
    col = base[None, None, :] * (0.85 + lum[..., None] * 0.22)
    rough = np.clip(0.28 + (1.0 - lum) * 0.22, 0.24, 0.54)
    nrm = (mtl_nrm - 128.0) * 0.30 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def generate_textures() -> None:
    """Synthesize 2048x2048 PBR atlas and compile ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    q0_rgb, q0_rough, q0_nrm = _make_weathered_yellow_housing(half)
    q0_met = np.full((half, half), 0.25, dtype=np.float32)

    q1_rgb, q1_rough, q1_nrm = _make_chassis_steel(half)
    q1_met = np.full((half, half), 0.72, dtype=np.float32)

    q2_rgb, q2_rough, q2_nrm = _make_rubber_tires(half)
    q2_met = np.full((half, half), 0.02, dtype=np.float32)

    q3_rgb, q3_rough, q3_nrm = _make_floodlight_lens(half)
    q3_met = np.full((half, half), 0.35, dtype=np.float32)

    albedo = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    albedo[0:half, 0:half] = q0_rgb
    albedo[0:half, half:atlas_size] = q1_rgb
    albedo[half:atlas_size, 0:half] = q2_rgb
    albedo[half:atlas_size, half:atlas_size] = q3_rgb
    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)

    roughness = np.zeros((atlas_size, atlas_size), dtype=np.float32)
    roughness[0:half, 0:half] = q0_rough
    roughness[0:half, half:atlas_size] = q1_rough
    roughness[half:atlas_size, 0:half] = q2_rough
    roughness[half:atlas_size, half:atlas_size] = q3_rough
    rough_u8 = np.clip(roughness * 255.0, 0.0, 255.0).astype(np.uint8)

    metallic = np.zeros((atlas_size, atlas_size), dtype=np.float32)
    metallic[0:half, 0:half] = q0_met
    metallic[0:half, half:atlas_size] = q1_met
    metallic[half:atlas_size, 0:half] = q2_met
    metallic[half:atlas_size, half:atlas_size] = q3_met
    metal_u8 = np.clip(metallic * 255.0, 0.0, 255.0).astype(np.uint8)

    scanned_nrm = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    scanned_nrm[0:half, 0:half] = q0_nrm
    scanned_nrm[0:half, half:atlas_size] = q1_nrm
    scanned_nrm[half:atlas_size, 0:half] = q2_nrm
    scanned_nrm[half:atlas_size, half:atlas_size] = q3_nrm

    albedo_path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    rough_tmp_path = TEX_DIR / f"{PROP_SLUG}_rough_override_tmp.png"
    metal_tmp_path = TEX_DIR / f"{PROP_SLUG}_metallic_tmp.png"
    Image.fromarray(albedo_u8, mode="RGB").save(albedo_path, format="PNG")
    Image.fromarray(rough_u8, mode="L").save(rough_tmp_path, format="PNG")
    Image.fromarray(metal_u8, mode="L").save(metal_tmp_path, format="PNG")

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
            "metal",
            "--base-roughness",
            "0.58",
            "--normal-strength",
            "1.4",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEX_DIR / f"{PROP_SLUG}_ao.png"
    normal_path = TEX_DIR / f"{PROP_SLUG}_normal.png"
    orm_path = TEX_DIR / f"{PROP_SLUG}_orm.png"
    tres_path = ASSET_DIR / f"{PROP_SLUG}.tres"

    derived_nrm = np.asarray(Image.open(normal_path).convert("RGB"), dtype=np.float32)
    blended_nrm = (derived_nrm - 128.0) * 0.35 + (scanned_nrm - 128.0) * 0.75 + 128.0
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
    nrm_node.inputs["Strength"].default_value = 0.70
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _tag_faces(faces: list, region_id: int, smooth: bool = False) -> None:
    for f in faces:
        f.material_index = region_id
        f.smooth = smooth


def _add_box(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    size: "Vector",
    region: int,
    bevel_w: float = 0.0,
    rot_euler: tuple[float, float, float] | None = None,
) -> list:
    import bmesh
    from mathutils import Euler, Matrix

    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    rot_m = Euler(rot_euler, "XYZ").to_matrix().to_4x4() if rot_euler else Matrix.Identity(4)
    mat = Matrix.Translation(center) @ rot_m @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    vset = set(verts)
    if bevel_w > 0.0:
        edges = [e for e in bm.edges if all(v in vset for v in e.verts)]
        b_ret = bmesh.ops.bevel(bm, geom=edges, offset=bevel_w, segments=1, affect="EDGES", clamp_overlap=True)
        for v in b_ret.get("verts", []):
            vset.add(v)
    created_faces = [f for f in bm.faces if all(v in vset for v in f.verts)]
    _tag_faces(created_faces, region, smooth=False)
    return created_faces


def _add_cylinder(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    axis: "Vector",
    radius: float,
    depth: float,
    segments: int,
    region: int,
    smooth: bool = True,
) -> list:
    import bmesh
    from mathutils import Matrix, Vector

    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(center) @ rot
    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
        matrix=mat,
    )
    vset = set(ret["verts"])
    created_faces = [f for f in bm.faces if all(v in vset for v in f.verts)]
    _tag_faces(created_faces, region, smooth=smooth)
    return created_faces


def _build_geometry() -> "bpy.types.Mesh":
    """Build light_generator mesh with 4 region material slots."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    # Center trailer body slightly toward +Y so total length with front hitch (-Y) is ~2.40m
    body_cy = 0.28
    chassis_cz = 0.5 * (CHASSIS_BOT_Z + CHASSIS_TOP_Z)
    chassis_h = CHASSIS_TOP_Z - CHASSIS_BOT_Z

    # 1. Trailer Chassis Frame (region 1: dark oxidized steel)
    _add_box(bm, Vector((0.0, body_cy, chassis_cz)), Vector((CHASSIS_W, CHASSIS_L, chassis_h)), region=1, bevel_w=0.006)

    # A-Frame Drawbar Hitch extending forward (-Y) from chassis front
    front_y = body_cy - CHASSIS_L * 0.5
    hitch_tip_y = front_y - 0.72
    for sx in (-1.0, 1.0):
        start_x = sx * 0.34
        end_x = sx * 0.04
        mid_x = 0.5 * (start_x + end_x)
        mid_y = 0.5 * (front_y + hitch_tip_y)
        dx = end_x - start_x
        dy = hitch_tip_y - front_y
        arm_len = math.hypot(dx, dy) + 0.06
        # Local +Y is rotated by yaw around Z: (-sin(yaw), cos(yaw)) -> align with (-dx, -dy)
        yaw = math.atan2(dx, -dy)
        _add_box(
            bm,
            Vector((mid_x, mid_y, chassis_cz)),
            Vector((0.07, arm_len, 0.08)),
            region=1,
            bevel_w=0.004,
            rot_euler=(0.0, 0.0, yaw),
        )
    # Cross-brace on A-frame & tow coupler block + ring at hitch tip
    _add_box(bm, Vector((0.0, front_y - 0.34, chassis_cz)), Vector((0.38, 0.06, 0.06)), region=1, bevel_w=0.003)
    _add_box(bm, Vector((0.0, hitch_tip_y - 0.04, chassis_cz)), Vector((0.12, 0.16, 0.09)), region=1, bevel_w=0.004)
    _add_cylinder(bm, Vector((0.0, hitch_tip_y - 0.14, chassis_cz)), Vector((0.0, 0.0, 1.0)), 0.055, 0.03, 12, region=1, smooth=False)

    # Front Jockey Prop Stand touching z=0
    jockey_y = front_y - 0.34
    _add_cylinder(bm, Vector((0.0, jockey_y, chassis_cz * 0.5)), Vector((0.0, 0.0, 1.0)), 0.028, chassis_cz + 0.06, 8, region=1)
    _add_box(bm, Vector((0.0, jockey_y, 0.015)), Vector((0.14, 0.14, 0.03)), region=1, bevel_w=0.003)

    # 2 Rear Stabilizer Outrigger Legs touching z=0
    rear_y = body_cy + CHASSIS_L * 0.5 - 0.08
    for sx in (-1.0, 1.0):
        out_x = sx * (CHASSIS_W * 0.5 + 0.14)
        _add_box(bm, Vector((sx * (CHASSIS_W * 0.5 + 0.07), rear_y, chassis_cz)), Vector((0.18, 0.06, 0.06)), region=1)
        _add_box(bm, Vector((out_x, rear_y, chassis_cz * 0.5)), Vector((0.055, 0.055, chassis_cz + 0.04)), region=1)
        _add_box(bm, Vector((out_x, rear_y, 0.015)), Vector((0.14, 0.14, 0.03)), region=1, bevel_w=0.003)

    # 2. Axle, 2 Tires, Hubs & Fenders (axle at y = body_cy + 0.08)
    axle_y = body_cy + 0.08
    _add_cylinder(bm, Vector((0.0, axle_y, WHEEL_R)), Vector((1.0, 0.0, 0.0)), 0.035, CHASSIS_W + 0.24, 10, region=1)

    for sx in (-1.0, 1.0):
        wx = sx * (CHASSIS_W * 0.5 + WHEEL_W * 0.5 + 0.04)
        # Tire (region 2: black rubber)
        _add_cylinder(bm, Vector((wx, axle_y, WHEEL_R)), Vector((1.0, 0.0, 0.0)), WHEEL_R, WHEEL_W, 16, region=2, smooth=True)
        # Steel wheel rim & hub cap (region 1)
        _add_cylinder(bm, Vector((wx, axle_y, WHEEL_R)), Vector((1.0, 0.0, 0.0)), WHEEL_R * 0.55, WHEEL_W + 0.014, 12, region=1, smooth=True)
        _add_cylinder(bm, Vector((wx + sx * 0.02, axle_y, WHEEL_R)), Vector((1.0, 0.0, 0.0)), 0.07, WHEEL_W, 10, region=1, smooth=True)
        # Steel wheel fender over tire (region 0: yellow)
        _add_box(bm, Vector((wx, axle_y, WHEEL_R * 2.0 + 0.05)), Vector((WHEEL_W + 0.05, 0.54, 0.035)), region=0, bevel_w=0.004)
        _add_box(
            bm,
            Vector((wx, axle_y - 0.34, WHEEL_R * 2.0 - 0.04)),
            Vector((WHEEL_W + 0.05, 0.22, 0.035)),
            region=0,
            rot_euler=(math.radians(42.0), 0.0, 0.0),
        )
        _add_box(
            bm,
            Vector((wx, axle_y + 0.34, WHEEL_R * 2.0 - 0.04)),
            Vector((WHEEL_W + 0.05, 0.22, 0.035)),
            region=0,
            rot_euler=(math.radians(-42.0), 0.0, 0.0),
        )

    # 3. Diesel Generator Canopy / Housing (region 0: weathered yellow steel)
    canopy_h = CANOPY_TOP_Z - CHASSIS_TOP_Z
    canopy_cz = CHASSIS_TOP_Z + canopy_h * 0.5
    _add_box(bm, Vector((0.0, body_cy - 0.06, canopy_cz)), Vector((CANOPY_W, CANOPY_L, canopy_h)), region=0, bevel_w=0.018)

    # Side access doors & cooling louvers
    for sx in (-1.0, 1.0):
        # Recessed/raised door panel
        _add_box(
            bm,
            Vector((sx * (CANOPY_W * 0.5 + 0.006), body_cy - 0.06, canopy_cz - 0.02)),
            Vector((0.018, 0.92, 0.62)),
            region=0,
            bevel_w=0.004,
        )
        # Louver grille panel
        _add_box(
            bm,
            Vector((sx * (CANOPY_W * 0.5 + 0.014), body_cy - 0.32, canopy_cz + 0.06)),
            Vector((0.014, 0.32, 0.36)),
            region=1,
            bevel_w=0.002,
        )
        # Door latch
        _add_box(
            bm,
            Vector((sx * (CANOPY_W * 0.5 + 0.018), body_cy + 0.14, canopy_cz - 0.02)),
            Vector((0.018, 0.06, 0.10)),
            region=1,
            bevel_w=0.002,
        )

    # Rear control panel recess (dark steel)
    _add_box(
        bm,
        Vector((0.0, body_cy - 0.06 - CANOPY_L * 0.5 - 0.008, canopy_cz + 0.04)),
        Vector((0.52, 0.02, 0.40)),
        region=1,
        bevel_w=0.003,
    )

    # Vertical Exhaust Pipe & Muffler on top of canopy
    ex_x = -0.22
    ex_y = body_cy + 0.24
    _add_cylinder(bm, Vector((ex_x, ex_y, CANOPY_TOP_Z + 0.14)), Vector((0.0, 0.0, 1.0)), 0.055, 0.28, 10, region=1, smooth=True)
    _add_cylinder(bm, Vector((ex_x, ex_y, CANOPY_TOP_Z + 0.34)), Vector((0.0, 0.0, 1.0)), 0.028, 0.16, 8, region=1, smooth=True)

    # 4. Telescoping Mast (at rear of canopy, y = body_cy + CANOPY_L * 0.5 + 0.06)
    mast_y = body_cy + CANOPY_L * 0.5 + 0.05
    # Base bracket & winch drum
    _add_box(bm, Vector((0.0, mast_y, CHASSIS_TOP_Z + 0.45)), Vector((0.16, 0.16, 0.90)), region=1, bevel_w=0.004)
    _add_cylinder(bm, Vector((0.13, mast_y, CHASSIS_TOP_Z + 0.55)), Vector((1.0, 0.0, 0.0)), 0.075, 0.10, 10, region=1)
    # 3 telescoping square tube sections
    _add_box(bm, Vector((0.0, mast_y, 1.25)), Vector((0.11, 0.11, 1.65)), region=1, bevel_w=0.003)
    _add_box(bm, Vector((0.0, mast_y, 2.25)), Vector((0.085, 0.085, 1.15)), region=1, bevel_w=0.003)
    _add_box(bm, Vector((0.0, mast_y, 2.95)), Vector((0.065, 0.065, 0.85)), region=1, bevel_w=0.003)

    # Coiled black power cable alongside mast (region 2)
    for cz in (1.50, 1.85, 2.20, 2.55, 2.90):
        _add_cylinder(bm, Vector((-0.07, mast_y, cz)), Vector((0.0, 0.0, 1.0)), 0.022, 0.26, 8, region=2, smooth=True)

    # 5. Crossbar & 4 Floodlight Heads at top (z = CROSSBAR_Z)
    _add_box(bm, Vector((0.0, mast_y, CROSSBAR_Z)), Vector((0.96, 0.065, 0.065)), region=1, bevel_w=0.003)

    for lx in (-0.39, -0.13, 0.13, 0.39):
        # U-bracket
        _add_box(bm, Vector((lx, mast_y, CROSSBAR_Z + 0.07)), Vector((0.06, 0.06, 0.08)), region=1)
        # Floodlight housing (region 1: dark steel, tilted slightly downward toward -Y)
        head_center = Vector((lx, mast_y - 0.03, CROSSBAR_Z + 0.14))
        _add_box(
            bm,
            head_center,
            Vector((0.20, 0.12, 0.15)),
            region=1,
            bevel_w=0.006,
            rot_euler=(math.radians(15.0), 0.0, 0.0),
        )
        # Front glass/reflector lens face (region 3)
        _add_box(
            bm,
            head_center + Vector((0.0, -0.056, -0.014)),
            Vector((0.17, 0.018, 0.12)),
            region=3,
            rot_euler=(math.radians(15.0), 0.0, 0.0),
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh


def _unwrap_quadrants_and_merge_material(obj: "bpy.types.Object", final_mat: "bpy.types.Material") -> None:
    """Smart-project each region into non-overlapping quadrants and assign single atlas material."""
    import bmesh
    import bpy

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    quads = {
        0: (0.01, 0.49, 0.51, 0.99),  # Q0 (Top-Left): Weathered yellow/ochre generator housing
        1: (0.51, 0.99, 0.51, 0.99),  # Q1 (Top-Right): Dark oxidized steel chassis, mast, hitch
        2: (0.01, 0.49, 0.01, 0.49),  # Q2 (Bottom-Left): Black rubber tires & cable
        3: (0.51, 0.99, 0.01, 0.49),  # Q3 (Bottom-Right): Floodlight lens faces
    }

    for region_id, (u0, u1, v0, v1) in quads.items():
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")

        for poly in obj.data.polygons:
            if poly.material_index == region_id:
                poly.select = True

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
    """Build light_generator GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh = _build_geometry()
    obj = bpy.data.objects.new("LightGenerator", mesh)
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
