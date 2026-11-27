"""Procedural Outdoor Electric Cabinet (Sloped Cap, Junction Box, Louvers, Pedestal).

Generates the 1.35m-tall weathered off-white street utility cabinet matching
ref IMG_20261125_163519.jpg (oriented upright), with non-overlapping quadrant
UVs, photorealistic weathered PBR textures (powder-coated metal + concrete
base scan) via process_pbr.py, Godot 4 ORMMaterial3D (.tres), GLB, and
asset_manifest.json.

Run headless via Blender:
    python3 tools/blender/run.py tools/blender/props/outdoor_electric_cabinet.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/outdoor_electric_cabinet.py --gen-textures
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

PROP_SLUG: str = "outdoor_electric_cabinet"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
REF_IMAGE: str = "/home/dkd/Desktop/Refs/IMG_20261125_163519.jpg"
TARGET_HEIGHT_M: float = 1.35
TRI_BUDGET: int = 2000

# Source photorealistic scans in BellaSDK
SRC_METAL_DIR: Path = REPO_ROOT / "assets" / "materials" / "painted_industrial_metal" / "textures"
SRC_CONCRETE_DIR: Path = REPO_ROOT / "assets" / "materials" / "weathered_concrete" / "textures"
SRC_RUST_DIR: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

# Proportions in meters (Blender Z-up, front door facing -Y)
PAD_BOT_W: float = 0.66
PAD_BOT_D: float = 0.48
PAD_TOP_W: float = 0.60
PAD_TOP_D: float = 0.42
PAD_H: float = 0.045

PED_W: float = 0.44
PED_D: float = 0.30
PED_TOP_Z: float = 0.32
COLLAR_W: float = 0.60
COLLAR_D: float = 0.38
COLLAR_H: float = 0.025

CAB_W: float = 0.66
CAB_D: float = 0.36
CAB_BOT_Z: float = PED_TOP_Z + COLLAR_H
CAB_TOP_Z: float = 1.29
CAP_FRONT_Z: float = 1.35
CAP_BACK_Z: float = 1.315

JBOX_W: float = 0.13
JBOX_D: float = 0.28
JBOX_H: float = 0.34
JBOX_BOT_Z: float = 0.92


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    """Load an image as float32 RGB resized to (size, size)."""
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def _make_powder_coated_metal(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Derive crisp off-white powder-coated steel from painted_industrial_metal scan."""
    import numpy as np
    from PIL import Image, ImageFilter

    src_alb = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_albedo.png", size)
    src_nrm = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_normal.png", size)

    # Identify intact paint vs heavy dark rust holes in the source scan:
    # Teal paint has higher G/B and luminance > 95; rust chips are dark brownish-black.
    lum = 0.299 * src_alb[..., 0] + 0.587 * src_alb[..., 1] + 0.114 * src_alb[..., 2]
    # Keep fine micro-scratches/grain via high-pass while discarding large dark rust patches
    low_pass = np.asarray(
        Image.fromarray(np.clip(lum, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=18)
        ),
        dtype=np.float32,
    )
    # Use clean painted patches: sample high-pass micro-detail and subtle dust variation
    detail = np.clip(lum - low_pass, -24.0, 20.0)
    # Gentle multi-scale chalky weathering from blurred clean luminance
    soft_var = np.clip((low_pass - 115.0) * 0.18, -10.0, 10.0)

    # Cool off-white / light-gray powder-coated enamel matching ref IMG_20261125_163519.jpg
    # Use fine micro-grain & subtle chalky weathering without large dark peeling patches
    base_rgb = np.array([202.0, 206.0, 202.0], dtype=np.float32)
    clean_mask = np.clip((lum - 88.0) / 30.0, 0.0, 1.0)
    fine_detail = detail * clean_mask * 0.45
    col = base_rgb[None, None, :] + soft_var[..., None] * 0.75 + fine_detail[..., None]

    # Only microscopic pinhead wear scuffs (< 1% area) from deep scratch lines
    tiny_chip = np.clip((-detail - 18.0) / 14.0, 0.0, 1.0) * np.clip((52.0 - lum) / 25.0, 0.0, 1.0)
    chip_col = np.array([138.0, 136.0, 130.0], dtype=np.float32)
    col = col * (1.0 - tiny_chip[..., None] * 0.45) + chip_col[None, None, :] * (tiny_chip[..., None] * 0.45)

    # Matte-satin powder coat roughness strictly in [0.48, 0.68]
    rough = np.clip(0.55 - fine_detail * 0.004 + tiny_chip * 0.10, 0.48, 0.68)

    # Subtle micro-relief normal from scanned painted metal (preserve flat OpenGL +Y)
    nrm = (src_nrm - 128.0) * (0.25 * clean_mask[..., None]) + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def _paint_door_panel_ao(
    base_rgb: "np.ndarray",
    base_rough: "np.ndarray",
    base_nrm: "np.ndarray",
) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Add crisp perimeter door-seam AO and localized rust/grime around hinges, latches & lip."""
    import numpy as np
    from PIL import Image, ImageFilter

    h, w, _ = base_rgb.shape
    col = base_rgb.copy()
    rough = base_rough.copy()
    nrm = base_nrm.copy()

    # Normalized door coordinates: u in [0..1] left->right, v in [0..1] bottom->top
    u = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :]
    v = np.linspace(1.0, 0.0, h, dtype=np.float32)[:, None]

    # 1. Crisp dark door-seam perimeter AO around all 4 edges
    edge_dist = np.minimum(np.minimum(u, 1.0 - u), np.minimum(v, 1.0 - v))
    seam_ao = np.clip(edge_dist / 0.032, 0.0, 1.0)
    seam_dark = (1.0 - seam_ao) ** 2.0 * 0.42
    col *= (1.0 - seam_dark[..., None])
    rough = np.clip(rough + seam_dark * 0.18, 0.48, 0.68)

    # 2. Localized rust/grime drip streaks ONLY below 3 left hinges, 2 upper latches, and bottom lip
    rust_src = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_albedo.png", max(h, w))[:h, :w]
    grime_col = rust_src * 0.45 + np.array([86.0, 68.0, 52.0], dtype=np.float32)[None, None, :] * 0.55

    mask = np.zeros((h, w), dtype=np.float32)

    # 3 left-edge hinges (v ~= 0.12, 0.50, 0.88; door height ~0.88m)
    for hv in (0.12, 0.50, 0.88):
        dx = np.abs(u - 0.015) / 0.055
        dy_below = np.where(v <= hv, (hv - v) / 0.14, (v - hv) / 0.025)
        blob = np.exp(-(dx * dx + dy_below * dy_below) * 2.2)
        mask = np.maximum(mask, blob * 0.55)

    # 2 upper cam latches (u ~= 0.22, 0.78, v ~= 0.87) & central handle (u ~= 0.50, v ~= 0.74)
    for lu, lv in ((0.22, 0.87), (0.78, 0.87), (0.50, 0.74)):
        dx = (u - lu) / 0.045
        dy = np.where(v <= lv, (lv - v) / 0.09, (v - lv) / 0.025)
        blob = np.exp(-(dx * dx + dy * dy) * 2.4)
        mask = np.maximum(mask, blob * 0.42)

    # Bottom lip splash & rust along v < 0.08
    lip = np.clip((0.085 - v) / 0.085, 0.0, 1.0) ** 1.6
    mask = np.maximum(mask, lip * 0.50)

    # Break up streak edges organically using scanned rust luminance
    rust_lum = (0.299 * rust_src[..., 0] + 0.587 * rust_src[..., 1] + 0.114 * rust_src[..., 2]) / 255.0
    mask = np.clip(mask * (0.55 + 0.85 * rust_lum), 0.0, 0.65)
    # Soften slightly for natural stain bleed
    mask = (
        np.asarray(
            Image.fromarray((mask * 255.0).astype(np.uint8), mode="L").filter(
                ImageFilter.GaussianBlur(radius=2.5)
            ),
            dtype=np.float32,
        )
        / 255.0
    )

    col = col * (1.0 - mask[..., None]) + grime_col * mask[..., None]
    rough = np.clip(rough + mask * 0.15, 0.48, 0.68)
    return np.clip(col, 30.0, 240.0), rough, nrm


def _make_concrete_base_flange(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Build weathered mud-splattered concrete/galvanized base flange from weathered_concrete scan."""
    import numpy as np

    conc_alb = _load_square_rgb(SRC_CONCRETE_DIR / "weathered_concrete_albedo.png", size)
    conc_nrm = _load_square_rgb(SRC_CONCRETE_DIR / "weathered_concrete_normal.png", size)

    # Subtle radial mud/dirt splatter toward outer edges + bottom skirt of the concrete pad
    u = np.linspace(-1.0, 1.0, size, dtype=np.float32)[None, :]
    v = np.linspace(-1.0, 1.0, size, dtype=np.float32)[:, None]
    edge_r = np.maximum(np.abs(u), np.abs(v))
    mud_zone = np.clip((edge_r - 0.48) / 0.48, 0.0, 1.0)

    # Modulate mud splatter organically using concrete's own dark pore/stain texture
    conc_lum = (0.299 * conc_alb[..., 0] + 0.587 * conc_alb[..., 1] + 0.114 * conc_alb[..., 2]) / 255.0
    mud_mask = np.clip(mud_zone * (1.15 - conc_lum * 0.75), 0.0, 0.72)

    # Lightly lime/paint-dusted concrete center + earthy dried mud around flange edges
    light_conc = conc_alb * 1.10 + 12.0
    mud_col = conc_alb * 0.52 + np.array([58.0, 50.0, 40.0], dtype=np.float32)[None, None, :] * 0.48
    col = light_conc * (1.0 - mud_mask[..., None]) + mud_col * mud_mask[..., None]

    # Concrete/mud roughness strictly in [0.85, 0.95]
    rough = np.clip(0.87 + (1.0 - conc_lum) * 0.06 + mud_mask * 0.04, 0.85, 0.95)
    nrm = (conc_nrm - 128.0) * 0.75 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def _make_hardware_steel(size: int) -> tuple["np.ndarray", "np.ndarray", "np.ndarray"]:
    """Dark oxidized/rusted steel for hinges, latches, key lock, and anchor bolts."""
    import numpy as np

    rust_alb = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_albedo.png", size)
    rust_nrm = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_normal.png", size)
    gunmetal = np.array([78.0, 82.0, 86.0], dtype=np.float32)
    col = rust_alb * 0.45 + gunmetal[None, None, :] * 0.55
    lum = (0.299 * rust_alb[..., 0] + 0.587 * rust_alb[..., 1] + 0.114 * rust_alb[..., 2]) / 255.0
    rough = np.clip(0.45 + (1.0 - lum) * 0.22, 0.42, 0.68)
    nrm = (rust_nrm - 128.0) * 0.60 + 128.0
    return np.clip(col, 30.0, 240.0), rough, np.clip(nrm, 0.0, 255.0)


def generate_textures() -> None:
    """Synthesize photorealistic 2048x2048 PBR atlas and compile ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    # Base powder-coated off-white metal (1024x1024)
    metal_rgb, metal_rough, metal_nrm = _make_powder_coated_metal(half)

    # Q0 Left Half (512x1024): Front door panel with crisp perimeter AO & hinge/latch/lip wear
    door_rgb, door_rough, door_nrm = _paint_door_panel_ao(
        metal_rgb[:, : half // 2],
        metal_rough[:, : half // 2],
        metal_nrm[:, : half // 2],
    )
    # Q0 Right Half (512x1024): Clean powder-coated cabinet body, roof, side jbox & pedestal
    q0_rgb = np.concatenate([door_rgb, metal_rgb[:, half // 2 :]], axis=1)
    q0_rough = np.concatenate([door_rough, metal_rough[:, half // 2 :]], axis=1)
    q0_nrm = np.concatenate([door_nrm, metal_nrm[:, half // 2 :]], axis=1)
    q0_met = np.full((half, half), 0.12, dtype=np.float32)

    # Q1 (Top-Right): Weathered mud-splattered concrete base flange (roughness 0.85-0.95)
    q1_rgb, q1_rough, q1_nrm = _make_concrete_base_flange(half)
    q1_met = np.full((half, half), 0.04, dtype=np.float32)

    # Q2 (Bottom-Left): Dark rusted/oxidized steel hardware (hinges, bolts, latches, conduit)
    q2_rgb, q2_rough, q2_nrm = _make_hardware_steel(half)
    q2_met = np.full((half, half), 0.72, dtype=np.float32)

    # Q3 (Bottom-Right): Ventilation louvers with crisp dark crevice AO
    q3_rgb = metal_rgb * 0.76
    v_grad = np.linspace(0.70, 1.0, half, dtype=np.float32)[:, None]
    q3_rgb = np.clip(q3_rgb * v_grad[..., None], 30.0, 240.0)
    q3_rough = np.clip(metal_rough + 0.06, 0.50, 0.72)
    q3_nrm = metal_nrm
    q3_met = np.full((half, half), 0.12, dtype=np.float32)

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

    # Blend derived OpenGL +Y normal with scanned material normal maps (preserving tangent Z > 0)
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
    print(f"[Textures] Generated photorealistic PBR maps + {tres_path.relative_to(REPO_ROOT)}")


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


def _add_tapered_slab(
    bm: "bmesh.types.BMesh",
    z0: float,
    z1: float,
    w0: float,
    d0: float,
    w1: float,
    d1: float,
    region: int,
) -> None:
    """Create beveled rectangular base pad tapering from (w0, d0) to (w1, d1)."""
    hw0, hd0 = w0 * 0.5, d0 * 0.5
    hw1, hd1 = w1 * 0.5, d1 * 0.5
    vb = [
        bm.verts.new((-hw0, -hd0, z0)),
        bm.verts.new((hw0, -hd0, z0)),
        bm.verts.new((hw0, hd0, z0)),
        bm.verts.new((-hw0, hd0, z0)),
    ]
    vt = [
        bm.verts.new((-hw1, -hd1, z1)),
        bm.verts.new((hw1, -hd1, z1)),
        bm.verts.new((hw1, hd1, z1)),
        bm.verts.new((-hw1, hd1, z1)),
    ]
    faces = [bm.faces.new(list(reversed(vb))), bm.faces.new(vt)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((vb[i], vb[j], vt[j], vt[i])))
    _tag_faces(faces, region, smooth=False)


def _add_sloped_cap(bm: "bmesh.types.BMesh", region: int) -> None:
    """Create overhanging rain cap sloped front-to-back (higher at front -Y)."""
    hw = (CAB_W + 0.04) * 0.5
    y_front = -CAB_D * 0.5 - 0.032
    y_back = CAB_D * 0.5 + 0.018
    z_bot_f = CAB_TOP_Z - 0.008
    z_bot_b = CAB_TOP_Z - 0.008

    vb = [
        bm.verts.new((-hw, y_front, z_bot_f)),
        bm.verts.new((hw, y_front, z_bot_f)),
        bm.verts.new((hw, y_back, z_bot_b)),
        bm.verts.new((-hw, y_back, z_bot_b)),
    ]
    vt = [
        bm.verts.new((-hw, y_front, CAP_FRONT_Z)),
        bm.verts.new((hw, y_front, CAP_FRONT_Z)),
        bm.verts.new((hw, y_back, CAP_BACK_Z)),
        bm.verts.new((-hw, y_back, CAP_BACK_Z)),
    ]
    faces = [bm.faces.new(list(reversed(vb))), bm.faces.new(vt)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((vb[i], vb[j], vt[j], vt[i])))
    _tag_faces(faces, region, smooth=False)


def _add_cylinder(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    axis: "Vector",
    radius: float,
    depth: float,
    segments: int,
    region: int,
    smooth: bool = False,
) -> None:
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
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth=smooth)


def _add_louver_bank(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    outward_normal: "Vector",
    width: float,
    num_slats: int,
    pitch_z: float,
    region: int,
) -> None:
    """Create angled stamped ventilation louver hoods."""
    import bmesh
    from mathutils import Matrix, Vector

    n_dir = outward_normal.normalized()
    u_dir = Vector((0.0, 0.0, 1.0)).cross(n_dir).normalized()
    tilt = Matrix.Rotation(math.radians(-32.0), 4, u_dir)

    start_z = center.z - 0.5 * (num_slats - 1) * pitch_z
    for i in range(num_slats):
        cz = start_z + i * pitch_z
        slat_pos = Vector((center.x, center.y, cz)) + n_dir * 0.008
        rot = Matrix((
            (u_dir.x, n_dir.x, 0.0, 0.0),
            (u_dir.y, n_dir.y, 0.0, 0.0),
            (u_dir.z, n_dir.z, 1.0, 0.0),
            (0.0, 0.0, 0.0, 1.0),
        ))
        mat = Matrix.Translation(slat_pos) @ tilt @ rot @ Matrix.Diagonal((width, 0.018, 0.012, 1.0))
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        bmesh.ops.transform(bm, matrix=mat, verts=verts)
        vset = set(verts)
        _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth=False)


def _build_geometry() -> tuple["bpy.types.Mesh", list[int]]:
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    # 1. Bolted flared concrete base pad (Region 1) + off-white pedestal column & collar (Region 0)
    _add_tapered_slab(bm, 0.0, PAD_H, PAD_BOT_W, PAD_BOT_D, PAD_TOP_W, PAD_TOP_D, region=1)
    _add_box(
        bm,
        Vector((0.0, 0.0, (PAD_H + PED_TOP_Z) * 0.5)),
        Vector((PED_W, PED_D, PED_TOP_Z - PAD_H)),
        region=0,
        bevel_w=0.004,
    )
    _add_box(
        bm,
        Vector((0.0, 0.0, PED_TOP_Z + COLLAR_H * 0.5)),
        Vector((COLLAR_W, COLLAR_D, COLLAR_H)),
        region=0,
    )
    # 4 corner anchor bolts + washers on base pad (Region 2)
    for bx in (-0.265, 0.265):
        for by in (-0.175, 0.175):
            _add_cylinder(bm, Vector((bx, by, PAD_H + 0.005)), Vector((0.0, 0.0, 1.0)), 0.022, 0.010, 8, region=2)
            _add_cylinder(bm, Vector((bx, by, PAD_H + 0.016)), Vector((0.0, 0.0, 1.0)), 0.013, 0.014, 6, region=2)

    # 2. Main weatherproof cabinet body + sloped rain cap (Region 0)
    cab_h = CAB_TOP_Z - CAB_BOT_Z
    cab_cz = (CAB_BOT_Z + CAB_TOP_Z) * 0.5
    _add_box(bm, Vector((0.0, 0.0, cab_cz)), Vector((CAB_W, CAB_D, cab_h)), region=0, bevel_w=0.006)
    _add_sloped_cap(bm, region=0)

    # 3. Front recessed door leaf: tag front (-Y) face as Region 4 for crisp seam/hinge AO
    door_w = CAB_W - 0.055
    door_h = cab_h - 0.055
    door_y = -CAB_D * 0.5 - 0.009
    door_faces = _add_box(bm, Vector((0.0, door_y, cab_cz)), Vector((door_w, 0.018, door_h)), region=0, bevel_w=0.003)
    bm.normal_update()
    for f in door_faces:
        if f.normal.y < -0.95:
            f.material_index = 4

    # 3 barrel hinges on left seam
    for hz in (0.48, 0.82, 1.15):
        _add_cylinder(bm, Vector((-door_w * 0.5 - 0.002, door_y - 0.006, hz)), Vector((0.0, 0.0, 1.0)), 0.011, 0.048, 8, region=2, smooth=True)

    # 2 upper square cam latch blocks + central horizontal bar handle + side key lock
    for lx in (-0.17, 0.17):
        _add_box(bm, Vector((lx, door_y - 0.013, 1.14)), Vector((0.036, 0.014, 0.036)), region=0)
        _add_cylinder(bm, Vector((lx, door_y - 0.022, 1.14)), Vector((0.0, 1.0, 0.0)), 0.008, 0.008, 6, region=2)
    _add_box(bm, Vector((0.0, door_y - 0.016, 1.03)), Vector((0.12, 0.020, 0.022)), region=0)
    _add_cylinder(bm, Vector((0.23, door_y - 0.012, 0.82)), Vector((0.0, 1.0, 0.0)), 0.016, 0.012, 8, region=2)

    # 4. Stamped ventilation louvers on lower door & left side (-X) (Region 3)
    _add_louver_bank(bm, Vector((0.0, door_y - 0.008, 0.53)), Vector((0.0, -1.0, 0.0)), width=0.28, num_slats=5, pitch_z=0.028, region=3)
    _add_louver_bank(bm, Vector((-CAB_W * 0.5, 0.0, 0.56)), Vector((-1.0, 0.0, 0.0)), width=0.18, num_slats=4, pitch_z=0.028, region=3)

    # 5. Protruding side junction box on upper-right (+X)
    jbox_cx = CAB_W * 0.5 + JBOX_W * 0.5
    jbox_cz = JBOX_BOT_Z + JBOX_H * 0.5
    jbox_cy = -0.01
    _add_box(bm, Vector((jbox_cx, jbox_cy, jbox_cz)), Vector((JBOX_W, JBOX_D, JBOX_H)), region=0, bevel_w=0.004)
    _add_box(bm, Vector((jbox_cx + JBOX_W * 0.5 + 0.005, jbox_cy, jbox_cz)), Vector((0.010, JBOX_D - 0.012, JBOX_H - 0.012)), region=0)
    for tz in (JBOX_BOT_Z + 0.06, JBOX_BOT_Z + JBOX_H - 0.06):
        _add_box(bm, Vector((jbox_cx + 0.02, jbox_cy - JBOX_D * 0.5 - 0.006, tz)), Vector((0.024, 0.012, 0.024)), region=2)
    _add_cylinder(bm, Vector((jbox_cx, jbox_cy, JBOX_BOT_Z - 0.025)), Vector((0.0, 0.0, 1.0)), 0.022, 0.05, 8, region=2)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    door_front_indices = [f.index for f in bm.faces if f.material_index == 4]

    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(5):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh, door_front_indices


def _unwrap_quadrants_and_merge_material(
    obj: "bpy.types.Object",
    door_front_indices: list[int],
    final_mat: "bpy.types.Material",
) -> None:
    """Smart-project regions into non-overlapping quadrants; map door face 1:1 for seam AO."""
    import bmesh
    import bpy

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    quads = {
        0: (0.26, 0.49, 0.51, 0.99),  # Q0 Right: clean off-white cabinet/jbox/pedestal
        1: (0.51, 0.99, 0.51, 0.99),  # Q1: mud-splattered concrete base pad
        2: (0.01, 0.49, 0.01, 0.49),  # Q2: dark steel hardware
        3: (0.51, 0.99, 0.01, 0.49),  # Q3: louvers
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

    # Map front door panel face (region 4) upright 1:1 into Q0 Left [0.01..0.24, 0.51..0.99]
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv.verify()
    door_set = set(door_front_indices)
    door_faces = [f for f in bm.faces if f.index in door_set]
    if door_faces:
        xs = [loop.vert.co.x for f in door_faces for loop in f.loops]
        zs = [loop.vert.co.z for f in door_faces for loop in f.loops]
        x_min, x_max = min(xs), max(xs)
        z_min, z_max = min(zs), max(zs)
        dx = max(x_max - x_min, 1e-5)
        dz = max(z_max - z_min, 1e-5)
        for f in door_faces:
            for loop in f.loops:
                tx = (loop.vert.co.x - x_min) / dx
                tz = (loop.vert.co.z - z_min) / dz
                loop[uv_layer].uv = (0.01 + tx * 0.23, 0.51 + tz * 0.48)

    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(obj.data)
    bm.free()

    obj.data.materials.clear()
    obj.data.materials.append(final_mat)


def build_prop() -> None:
    """Build outdoor_electric_cabinet GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh, door_front_indices = _build_geometry()
    obj = bpy.data.objects.new("OutdoorElectricCabinet", mesh)
    bpy.context.collection.objects.link(obj)

    final_mat = _create_atlas_material()
    _unwrap_quadrants_and_merge_material(obj, door_front_indices, final_mat)

    # Center XY at origin, guarantee min_z = 0, exact target height 1.35m
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
    # Godot +Y up, -Z forward: Blender (X, Y, Z) -> Godot (X, Z, Y)
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
        "reference_image": REF_IMAGE,
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
