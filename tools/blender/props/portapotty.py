"""Procedural Post-Soviet Portable Chemical Toilet (Portapotty).

Generates a weathered ~1.15m x 1.20m x 2.30m HDPE portable toilet cabin in
Post-Soviet Industrial Gothic style with non-overlapping quadrant UVs,
photorealistic weathered PBR textures derived from BellaSDK scans via
process_pbr.py, Godot 4 ORMMaterial3D (.tres), GLB, and asset_manifest.json.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/portapotty.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/portapotty.py --gen-textures
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

PROP_SLUG: str = "portapotty"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TARGET_HEIGHT_M: float = 2.30
TRI_BUDGET: int = 3000

SRC_HDPE_DIR: Path = REPO_ROOT / "assets" / "materials" / "hdpe_weathered_plastic" / "textures"
SRC_METAL_DIR: Path = REPO_ROOT / "assets" / "materials" / "painted_industrial_metal" / "textures"
SRC_RUST_DIR: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
SRC_CONCRETE_DIR: Path = REPO_ROOT / "assets" / "materials" / "weathered_concrete" / "textures"

# Proportions in meters (Blender Z-up, front door facing -Y)
BASE_W: float = 1.15
BASE_D: float = 1.20
BASE_H: float = 0.11

CAB_W: float = 1.11
CAB_D: float = 1.16
WALL_TOP_Z: float = 2.08
ROOF_PEAK_Z: float = 2.22
VENT_TOP_Z: float = 2.30


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    """Load an image as float32 RGB resized to (size, size)."""
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def _make_faded_blue_hdpe(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Derive sun-faded, scuffed blue-gray HDPE panels from hdpe_weathered_plastic scan."""
    import numpy as np
    from PIL import Image, ImageFilter

    src_alb = _load_square_rgb(SRC_HDPE_DIR / "hdpe_weathered_plastic_albedo.png", size)
    src_nrm = _load_square_rgb(SRC_HDPE_DIR / "hdpe_weathered_plastic_normal.png", size)
    src_rgh = _load_square_rgb(SRC_HDPE_DIR / "hdpe_weathered_plastic_roughness.png", size)[..., 0] / 255.0

    lum = (0.299 * src_alb[..., 0] + 0.587 * src_alb[..., 1] + 0.114 * src_alb[..., 2]) / 255.0
    low_pass = np.asarray(
        Image.fromarray(np.clip(lum * 255.0, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=16)
        ),
        dtype=np.float32,
    ) / 255.0

    # Desaturated sun-bleached Post-Soviet portable toilet blue-slate
    base_blue = np.array([68.0, 102.0, 132.0], dtype=np.float32)
    chalk_tint = np.array([128.0, 138.0, 144.0], dtype=np.float32)
    fade_mask = np.clip((low_pass - 0.35) * 1.4, 0.0, 0.65)
    col = base_blue[None, None, :] * (1.0 - fade_mask[..., None]) + chalk_tint[None, None, :] * fade_mask[..., None]

    # Micro-scuff & grime variation from HDPE scan
    detail = (lum - low_pass) * 90.0
    col = col + detail[..., None]

    # Bottom splash grime gradient (v=0 is bottom in image space if we map UV upright, y=size-1 is bottom)
    v_grad = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None]
    mud_mask = np.clip((v_grad - 0.72) / 0.28, 0.0, 1.0) * 0.55
    mud_col = np.array([64.0, 58.0, 50.0], dtype=np.float32)
    col = col * (1.0 - mud_mask[..., None]) + mud_col[None, None, :] * mud_mask[..., None]

    rough = np.clip(0.56 + src_rgh * 0.22 + fade_mask * 0.10 + mud_mask * 0.15, 0.50, 0.85)
    nrm = (src_nrm - 128.0) * 0.65 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def _make_weathered_roof_hdpe(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Derive weathered translucent-gray HDPE roof & vent cap."""
    import numpy as np

    src_alb = _load_square_rgb(SRC_HDPE_DIR / "hdpe_weathered_plastic_albedo.png", size)
    src_nrm = _load_square_rgb(SRC_HDPE_DIR / "hdpe_weathered_plastic_normal.png", size)
    conc_alb = _load_square_rgb(SRC_CONCRETE_DIR / "weathered_concrete_albedo.png", size)

    hdpe_lum = (0.299 * src_alb[..., 0] + 0.587 * src_alb[..., 1] + 0.114 * src_alb[..., 2]) / 255.0
    conc_lum = (0.299 * conc_alb[..., 0] + 0.587 * conc_alb[..., 1] + 0.114 * conc_alb[..., 2]) / 255.0

    base_gray = np.array([156.0, 160.0, 154.0], dtype=np.float32)
    soot_col = np.array([92.0, 90.0, 82.0], dtype=np.float32)
    grime = np.clip((0.60 - conc_lum) * 1.3, 0.0, 0.55)
    col = base_gray[None, None, :] * (1.0 - grime[..., None]) + soot_col[None, None, :] * grime[..., None]
    col += (hdpe_lum - 0.5)[..., None] * 28.0

    rough = np.clip(0.62 + grime * 0.22, 0.56, 0.88)
    nrm = (src_nrm - 128.0) * 0.50 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def _make_skid_base_hdpe(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Dark charcoal mud-stained HDPE pallet skid & vent pipe."""
    import numpy as np

    src_alb = _load_square_rgb(SRC_HDPE_DIR / "hdpe_weathered_plastic_albedo.png", size)
    src_nrm = _load_square_rgb(SRC_HDPE_DIR / "hdpe_weathered_plastic_normal.png", size)
    conc_alb = _load_square_rgb(SRC_CONCRETE_DIR / "weathered_concrete_albedo.png", size)

    conc_lum = (0.299 * conc_alb[..., 0] + 0.587 * conc_alb[..., 1] + 0.114 * conc_alb[..., 2]) / 255.0
    dark_hdpe = np.array([52.0, 54.0, 56.0], dtype=np.float32)
    dried_mud = np.array([78.0, 68.0, 56.0], dtype=np.float32)
    mud_mask = np.clip((0.55 - conc_lum) * 1.4, 0.0, 0.60)
    col = dark_hdpe[None, None, :] * (1.0 - mud_mask[..., None]) + dried_mud[None, None, :] * mud_mask[..., None]
    col += (src_alb - 128.0) * 0.18

    rough = np.clip(0.76 + mud_mask * 0.16, 0.70, 0.94)
    nrm = (src_nrm - 128.0) * 0.70 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def _make_hardware_steel(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Rusted/galvanized steel for door latch, hinges, and indicator."""
    import numpy as np

    rust_alb = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_albedo.png", size)
    rust_nrm = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_normal.png", size)
    galv = np.array([108.0, 112.0, 114.0], dtype=np.float32)
    col = rust_alb * 0.48 + galv[None, None, :] * 0.52
    lum = (0.299 * rust_alb[..., 0] + 0.587 * rust_alb[..., 1] + 0.114 * rust_alb[..., 2]) / 255.0
    rough = np.clip(0.44 + (1.0 - lum) * 0.28, 0.40, 0.76)
    nrm = (rust_nrm - 128.0) * 0.65 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def generate_textures() -> None:
    """Synthesize 2048x2048 PBR atlas and compile ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    q0_rgb, q0_rough, q0_nrm = _make_faded_blue_hdpe(half)
    q0_met = np.full((half, half), 0.02, dtype=np.float32)

    q1_rgb, q1_rough, q1_nrm = _make_weathered_roof_hdpe(half)
    q1_met = np.full((half, half), 0.02, dtype=np.float32)

    q2_rgb, q2_rough, q2_nrm = _make_skid_base_hdpe(half)
    q2_met = np.full((half, half), 0.02, dtype=np.float32)

    q3_rgb, q3_rough, q3_nrm = _make_hardware_steel(half)
    q3_met = np.full((half, half), 0.65, dtype=np.float32)

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
            "plaster",
            "--base-roughness",
            "0.68",
            "--normal-strength",
            "1.2",
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
    nrm_node.inputs["Strength"].default_value = 0.65
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _tag_faces(faces: list, region_id: int, smooth: bool = False) -> None:
    for f in faces:
        f.material_index = region_id
        f.smooth = smooth


def _add_box(bm: "bmesh.types.BMesh", center: "Vector", size: "Vector", region: int, bevel_w: float = 0.0) -> list:
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


def _add_pitched_roof(bm: "bmesh.types.BMesh", region: int) -> None:
    """Create hipped/pitched translucent-gray HDPE roof from WALL_TOP_Z to ROOF_PEAK_Z."""
    hw_out = (CAB_W + 0.05) * 0.5
    hd_out = (CAB_D + 0.05) * 0.5
    hw_top = (CAB_W - 0.24) * 0.5
    hd_top = (CAB_D - 0.24) * 0.5

    z_eave_bot = WALL_TOP_Z - 0.02
    z_eave_top = WALL_TOP_Z + 0.035

    # Eave rim
    _add_box(bm, Vector_((0.0, 0.0, 0.5 * (z_eave_bot + z_eave_top))), Vector_((hw_out * 2.0, hd_out * 2.0, z_eave_top - z_eave_bot)), region=region, bevel_w=0.008)

    # Sloped upper pyramid cap
    vb = [
        bm.verts.new((-hw_out + 0.01, -hd_out + 0.01, z_eave_top)),
        bm.verts.new((hw_out - 0.01, -hd_out + 0.01, z_eave_top)),
        bm.verts.new((hw_out - 0.01, hd_out - 0.01, z_eave_top)),
        bm.verts.new((-hw_out + 0.01, hd_out - 0.01, z_eave_top)),
    ]
    vt = [
        bm.verts.new((-hw_top, -hd_top, ROOF_PEAK_Z)),
        bm.verts.new((hw_top, -hd_top, ROOF_PEAK_Z)),
        bm.verts.new((hw_top, hd_top, ROOF_PEAK_Z)),
        bm.verts.new((-hw_top, hd_top, ROOF_PEAK_Z)),
    ]
    faces = [bm.faces.new(list(reversed(vb))), bm.faces.new(vt)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((vb[i], vb[j], vt[j], vt[i])))
    _tag_faces(faces, region, smooth=False)


def Vector_(xyz: tuple[float, float, float]) -> "Vector":
    from mathutils import Vector

    return Vector(xyz)


def _build_geometry() -> "bpy.types.Mesh":
    """Build portapotty mesh with 4 region material slots."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    # 1. Skid Pallet Base (region 2: dark charcoal HDPE skid)
    # Two outer skid runners + central floor deck
    skid_h = 0.05
    _add_box(bm, Vector((-0.44, 0.0, skid_h * 0.5)), Vector((0.26, BASE_D, skid_h)), region=2, bevel_w=0.006)
    _add_box(bm, Vector((0.44, 0.0, skid_h * 0.5)), Vector((0.26, BASE_D, skid_h)), region=2, bevel_w=0.006)
    _add_box(bm, Vector((0.0, 0.0, skid_h + (BASE_H - skid_h) * 0.5)), Vector((BASE_W, BASE_D, BASE_H - skid_h)), region=2, bevel_w=0.008)

    # 2. Main Cabin Shell (region 0: sun-faded blue-gray HDPE)
    wall_h = WALL_TOP_Z - BASE_H
    wall_cz = BASE_H + wall_h * 0.5
    # Core cabin body (recessed slightly at front so door frame stands proud)
    _add_box(bm, Vector((0.0, 0.02, wall_cz)), Vector((CAB_W - 0.02, CAB_D - 0.04, wall_h)), region=0, bevel_w=0.006)

    # Four vertical corner pilasters
    pil_w = 0.11
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            _add_box(
                bm,
                Vector((sx * (CAB_W * 0.5 - pil_w * 0.5), sy * (CAB_D * 0.5 - pil_w * 0.5), wall_cz)),
                Vector((pil_w, pil_w, wall_h)),
                region=0,
                bevel_w=0.008,
            )

    # Side & rear molded stiffening ribs (authentic HDPE wall panels)
    for sx in (-1.0, 1.0):
        for ry in (-0.28, 0.0, 0.28):
            _add_box(
                bm,
                Vector((sx * (CAB_W * 0.5 - 0.008), ry, wall_cz)),
                Vector((0.024, 0.065, wall_h - 0.14)),
                region=0,
                bevel_w=0.004,
            )
        # Side upper louvered vent grille
        _add_box(
            bm,
            Vector((sx * (CAB_W * 0.5 - 0.005), 0.0, WALL_TOP_Z - 0.18)),
            Vector((0.022, 0.36, 0.16)),
            region=2,
            bevel_w=0.003,
        )

    for rx in (-0.28, 0.0, 0.28):
        _add_box(
            bm,
            Vector((rx, CAB_D * 0.5 - 0.008, wall_cz)),
            Vector((0.065, 0.024, wall_h - 0.14)),
            region=0,
            bevel_w=0.004,
        )

    # 3. Front Door Frame & Recessed Door (facing -Y)
    door_w = 0.74
    door_h = 1.82
    door_cz = BASE_H + 0.04 + door_h * 0.5
    front_y = -CAB_D * 0.5

    # Top lintel & bottom threshold
    _add_box(bm, Vector((0.0, front_y + 0.025, WALL_TOP_Z - 0.055)), Vector((CAB_W - 0.08, 0.05, 0.11)), region=0, bevel_w=0.005)
    _add_box(bm, Vector((0.0, front_y + 0.025, BASE_H + 0.02)), Vector((CAB_W - 0.08, 0.05, 0.04)), region=0, bevel_w=0.004)

    # Recessed Door Panel (recessed 3.5cm behind front pilasters)
    door_y = front_y + 0.045
    _add_box(bm, Vector((0.0, door_y, door_cz)), Vector((door_w, 0.035, door_h)), region=0, bevel_w=0.005)
    # Molded door center relief panels (upper & lower)
    _add_box(bm, Vector((0.0, door_y - 0.016, door_cz + 0.42)), Vector((door_w - 0.16, 0.016, 0.62)), region=0, bevel_w=0.004)
    _add_box(bm, Vector((0.0, door_y - 0.016, door_cz - 0.38)), Vector((door_w - 0.16, 0.016, 0.68)), region=0, bevel_w=0.004)

    # 4. Door Hardware (region 3: rusted/galvanized steel)
    # 3 left hinges
    for hz in (BASE_H + 0.25, door_cz, WALL_TOP_Z - 0.28):
        _add_box(bm, Vector((-door_w * 0.5 + 0.01, door_y - 0.022, hz)), Vector((0.045, 0.022, 0.08)), region=3, bevel_w=0.002)

    # Right-side latch plate, slide-bolt & pull handle
    latch_x = door_w * 0.5 - 0.08
    latch_z = door_cz - 0.04
    _add_box(bm, Vector((latch_x, door_y - 0.022, latch_z)), Vector((0.075, 0.018, 0.14)), region=3, bevel_w=0.002)
    _add_box(bm, Vector((latch_x + 0.02, door_y - 0.036, latch_z)), Vector((0.09, 0.018, 0.026)), region=3, bevel_w=0.002)
    # Pull handle bar
    _add_box(bm, Vector((latch_x - 0.02, door_y - 0.048, latch_z - 0.15)), Vector((0.022, 0.036, 0.14)), region=3, bevel_w=0.003)
    # Occupancy indicator plate above handle
    _add_box(bm, Vector((latch_x, door_y - 0.022, latch_z + 0.16)), Vector((0.07, 0.014, 0.05)), region=3, bevel_w=0.002)

    # 5. Pitched Translucent-Gray Roof (region 1)
    _add_pitched_roof(bm, region=1)

    # 6. Roof Vent Pipe & Rain Cap (region 2: dark HDPE pipe, cap region 1)
    vent_x = 0.32
    vent_y = 0.28
    vent_base_z = WALL_TOP_Z + 0.02
    vent_h = VENT_TOP_Z - 0.02 - vent_base_z
    _add_cylinder(
        bm,
        Vector((vent_x, vent_y, vent_base_z + vent_h * 0.5)),
        Vector((0.0, 0.0, 1.0)),
        radius=0.048,
        depth=vent_h,
        segments=12,
        region=2,
        smooth=True,
    )
    _add_cylinder(
        bm,
        Vector((vent_x, vent_y, VENT_TOP_Z - 0.015)),
        Vector((0.0, 0.0, 1.0)),
        radius=0.075,
        depth=0.03,
        segments=12,
        region=1,
        smooth=True,
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
        0: (0.01, 0.49, 0.51, 0.99),  # Q0 (Top-Left): Faded blue-gray HDPE walls & door
        1: (0.51, 0.99, 0.51, 0.99),  # Q1 (Top-Right): Weathered gray HDPE roof & vent cap
        2: (0.01, 0.49, 0.01, 0.49),  # Q2 (Bottom-Left): Dark skid pallet, vents, vent pipe
        3: (0.51, 0.99, 0.01, 0.49),  # Q3 (Bottom-Right): Steel latch & hinges
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
    """Build portapotty GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh = _build_geometry()
    obj = bpy.data.objects.new("Portapotty", mesh)
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
