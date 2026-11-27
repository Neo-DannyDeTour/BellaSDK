"""Procedural Industrial Cable Reel (Timber Flanges, Steel Hub, Wound Power Cable).

Generates the 0.90m-diameter x 0.65m-wide Post-Soviet Industrial Gothic cable
spool prop, with non-overlapping quadrant UVs, weathered PBR texture maps via
process_pbr.py, Godot 4 ORMMaterial3D (.tres), GLB, and asset_manifest.json.

Run headless via Blender:
    /snap/bin/blender --background --python tools/blender/props/cable_reel.py

Generate textures only (via .venv/bin/python):
    .venv/bin/python tools/blender/props/cable_reel.py --gen-textures
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

PROP_SLUG: str = "cable_reel"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
TARGET_HEIGHT_M: float = 0.90
TRI_BUDGET: int = 2500

# Spool dimensions (meters, Blender Z-up, axle along X, resting on YZ circle)
REEL_R: float = 0.45
REEL_W: float = 0.65
FLANGE_T: float = 0.056
FLANGE_X: float = (REEL_W - FLANGE_T) * 0.5
CENTER_Z: float = REEL_R


def _fbm_noise(h: int, w: int, seed: int, octaves: list[tuple[int, float]]) -> "np.ndarray":
    """Generate smooth multi-octave 2D value noise in [0, 1] using numpy + PIL."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    weight_sum = 0.0
    for grid_res, weight in octaves:
        grid = rng.random((grid_res, grid_res), dtype=np.float32)
        img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
        up = img.resize((w, h), Image.Resampling.BILINEAR)
        acc += (np.asarray(up, dtype=np.float32) / 255.0) * weight
        weight_sum += weight
    return np.clip(acc / max(weight_sum, 1e-6), 0.0, 1.0)


def _grain_noise(h: int, w: int, seed: int, cols: int = 18, rows: int = 180) -> "np.ndarray":
    """Generate directional wood/rubber grain noise in [0, 1]."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    grid = rng.random((rows, cols), dtype=np.float32)
    img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
    up = img.resize((w, h), Image.Resampling.BICUBIC)
    return np.clip(np.asarray(up, dtype=np.float32) / 255.0, 0.0, 1.0)


def _paint_timber_quadrant(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize weathered industrial timber planks with seams and grime."""
    import numpy as np

    grain = _grain_noise(size, size, seed, cols=20, rows=220)
    macro = _fbm_noise(size, size, seed + 13, [(6, 0.55), (18, 0.30), (54, 0.15)])
    fine = _fbm_noise(size, size, seed + 37, [(64, 0.5), (192, 0.5)])

    base = np.array([128.0, 106.0, 82.0], dtype=np.float32)
    weathered = np.array([154.0, 142.0, 126.0], dtype=np.float32)
    dark_stain = np.array([72.0, 58.0, 44.0], dtype=np.float32)

    col = base[None, None, :] * (1.0 - 0.5 * macro[..., None]) + weathered[None, None, :] * (
        0.5 * macro[..., None]
    )
    col += (grain[..., None] - 0.5) * 26.0
    col += (fine[..., None] - 0.5) * 12.0

    # Plank seam lines every 1/6 of quadrant height
    plank_h = max(1, size // 6)
    for py in range(plank_h, size, plank_h):
        col[max(0, py - 3) : min(size, py + 3), :] *= 0.55

    # Subtle grime near edges
    stain_mask = np.clip((macro - 0.55) * 0.65, 0.0, 0.35)
    col = col * (1.0 - stain_mask[..., None]) + dark_stain[None, None, :] * stain_mask[..., None]

    metallic = np.zeros((size, size), dtype=np.float32)
    return np.clip(col, 30.0, 240.0), metallic


def _paint_rubber_quadrant(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize thick matte-satin black vulcanized rubberized power cable."""
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(8, 0.5), (24, 0.3), (72, 0.2)])
    fine = _fbm_noise(size, size, seed + 29, [(96, 0.6), (256, 0.4)])
    scuffs = _fbm_noise(size, size, seed + 61, [(20, 0.4), (64, 0.6)])

    base = np.array([38.0, 40.0, 42.0], dtype=np.float32)
    dust = np.array([78.0, 76.0, 70.0], dtype=np.float32)

    col = base[None, None, :] + (macro[..., None] - 0.5) * 10.0 + (fine[..., None] - 0.5) * 8.0
    dust_mask = np.clip((scuffs - 0.62) * 0.75, 0.0, 0.35)
    col = col * (1.0 - dust_mask[..., None]) + dust[None, None, :] * dust_mask[..., None]

    metallic = np.zeros((size, size), dtype=np.float32)
    return np.clip(col, 30.0, 240.0), metallic


def _paint_steel_quadrant(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Synthesize rusted dark industrial steel hub plates and tie hardware."""
    import numpy as np

    macro = _fbm_noise(size, size, seed, [(6, 0.5), (18, 0.3), (48, 0.2)])
    rust = _fbm_noise(size, size, seed + 41, [(14, 0.45), (52, 0.55)])
    fine = _fbm_noise(size, size, seed + 77, [(64, 0.5), (192, 0.5)])

    steel = np.array([96.0, 100.0, 104.0], dtype=np.float32)
    rust_col = np.array([108.0, 62.0, 38.0], dtype=np.float32)
    dark_oxide = np.array([58.0, 56.0, 54.0], dtype=np.float32)

    col = steel[None, None, :] * (0.7 + 0.3 * macro[..., None]) + dark_oxide[None, None, :] * (
        0.3 * (1.0 - macro[..., None])
    )
    rust_mask = np.clip((rust - 0.52) * 1.4, 0.0, 0.75)
    col = col * (1.0 - rust_mask[..., None]) + rust_col[None, None, :] * rust_mask[..., None]
    col += (fine[..., None] - 0.5) * 12.0

    metallic = np.clip(0.82 * (1.0 - rust_mask * 0.75), 0.15, 0.85)
    return np.clip(col, 30.0, 240.0), metallic


def _draw_stencil_quadrant(size: int, seed: int) -> tuple["np.ndarray", "np.ndarray"]:
    """Draw weathered timber batten/stencil plate with '380V / КГ 3x16' markings."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont

    col, metallic = _paint_timber_quadrant(size, seed)
    img = Image.fromarray(col.astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img)

    font_path = "/usr/share/fonts/truetype/noto/NotoSans-CondensedBold.ttf"
    if not Path(font_path).is_file():
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
    font_lg = ImageFont.truetype(font_path, int(size * 0.12))
    font_sm = ImageFont.truetype(font_path, int(size * 0.085))

    ink = (34, 34, 32)
    red_ink = (142, 46, 40)
    draw.text((size * 0.50, size * 0.34), "380V", fill=red_ink, font=font_lg, anchor="mm")
    draw.text((size * 0.50, size * 0.62), "КГ 3x16", fill=ink, font=font_sm, anchor="mm")

    arr = np.asarray(img, dtype=np.float32)
    wear = _fbm_noise(size, size, seed + 88, [(16, 0.5), (48, 0.5)])
    arr *= 0.88 + 0.14 * wear[..., None]
    return np.clip(arr, 30.0, 240.0), metallic


def generate_textures() -> None:
    """Synthesize weathered 2048x2048 PBR texture atlas and compile ORM + .tres."""
    import numpy as np
    from PIL import Image

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    atlas_size = 2048
    half = atlas_size // 2

    q0_rgb, q0_met = _paint_timber_quadrant(half, seed=105)
    q1_rgb, q1_met = _paint_rubber_quadrant(half, seed=205)
    q2_rgb, q2_met = _paint_steel_quadrant(half, seed=305)
    q3_rgb, q3_met = _draw_stencil_quadrant(half, seed=405)

    albedo = np.zeros((atlas_size, atlas_size, 3), dtype=np.float32)
    albedo[0:half, 0:half] = q0_rgb
    albedo[0:half, half:atlas_size] = q1_rgb
    albedo[half:atlas_size, 0:half] = q2_rgb
    albedo[half:atlas_size, half:atlas_size] = q3_rgb
    albedo = np.clip(albedo, 30.0, 240.0).astype(np.uint8)

    metallic = np.zeros((atlas_size, atlas_size), dtype=np.float32)
    metallic[0:half, 0:half] = q0_met
    metallic[0:half, half:atlas_size] = q1_met
    metallic[half:atlas_size, 0:half] = q2_met
    metallic[half:atlas_size, half:atlas_size] = q3_met
    metallic_u8 = np.clip(metallic * 255.0, 0.0, 255.0).astype(np.uint8)

    albedo_path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
    metallic_path = TEX_DIR / f"{PROP_SLUG}_metallic_tmp.png"
    Image.fromarray(albedo, mode="RGB").save(albedo_path, format="PNG")
    Image.fromarray(metallic_u8, mode="L").save(metallic_path, format="PNG")

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
            "wood",
            "--base-roughness",
            "0.72",
            "--normal-strength",
            "2.0",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEX_DIR / f"{PROP_SLUG}_ao.png"
    rough_path = TEX_DIR / f"{PROP_SLUG}_roughness.png"
    normal_path = TEX_DIR / f"{PROP_SLUG}_normal.png"
    orm_path = TEX_DIR / f"{PROP_SLUG}_orm.png"
    tres_path = ASSET_DIR / f"{PROP_SLUG}.tres"

    subprocess.run(
        [
            sys.executable,
            str(process_pbr),
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

    for tmp in (metallic_path, TEX_DIR / f"{PROP_SLUG}_height.png", ao_path, rough_path):
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
    nrm_node.inputs["Strength"].default_value = 0.75
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _tag_faces(faces: list, region_id: int, smooth: bool) -> None:
    for f in faces:
        f.material_index = region_id
        f.smooth = smooth


def _add_box(bm: "bmesh.types.BMesh", center: "Vector", size: "Vector", region: int, smooth: bool = False) -> None:
    import bmesh
    from mathutils import Matrix

    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    mat = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
    bmesh.ops.transform(bm, matrix=mat, verts=verts)
    vset = set(verts)
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth)


def _add_cylinder_x(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    radius: float,
    depth: float,
    segments: int,
    region: int,
    smooth: bool = True,
) -> None:
    import bmesh
    from mathutils import Matrix, Vector

    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(Vector((1.0, 0.0, 0.0))).to_matrix().to_4x4()
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
    _tag_faces([f for f in bm.faces if all(v in vset for v in f.verts)], region, smooth)


def _add_torus_x(
    bm: "bmesh.types.BMesh",
    center: "Vector",
    major_r: float,
    minor_r: float,
    major_segs: int,
    minor_segs: int,
    region: int,
    smooth: bool = True,
) -> None:
    """Create a torus ring around the X axis."""
    from mathutils import Vector

    rings: list[list] = []
    for i in range(major_segs):
        theta = (2.0 * math.pi * i) / major_segs
        cy = math.cos(theta)
        cz = math.sin(theta)
        ring = []
        for j in range(minor_segs):
            phi = (2.0 * math.pi * j) / minor_segs
            r_off = major_r + minor_r * math.cos(phi)
            x_off = minor_r * math.sin(phi)
            v = bm.verts.new(center + Vector((x_off, r_off * cy, r_off * cz)))
            ring.append(v)
        rings.append(ring)

    new_faces = []
    for i in range(major_segs):
        r0 = rings[i]
        r1 = rings[(i + 1) % major_segs]
        for j in range(minor_segs):
            jn = (j + 1) % minor_segs
            new_faces.append(bm.faces.new((r0[j], r1[j], r1[jn], r0[jn])))
    _tag_faces(new_faces, region, smooth)


def _add_cable_tail(bm: "bmesh.types.BMesh", region: int) -> None:
    """Add a short thick rubberized cable tail emerging from the outer coil wrap."""
    from mathutils import Vector

    pts = [
        Vector((0.20, -0.32, CENTER_Z + 0.12)),
        Vector((0.25, -0.37, CENTER_Z - 0.02)),
        Vector((0.27, -0.36, CENTER_Z - 0.18)),
        Vector((0.26, -0.29, CENTER_Z - 0.29)),
    ]
    segs = 6
    minor_r = 0.022
    rings = []
    for idx, p in enumerate(pts):
        if idx < len(pts) - 1:
            tangent = (pts[idx + 1] - p).normalized()
        else:
            tangent = (p - pts[idx - 1]).normalized()
        up = Vector((1.0, 0.0, 0.0))
        if abs(tangent.dot(up)) > 0.9:
            up = Vector((0.0, 0.0, 1.0))
        binorm = tangent.cross(up).normalized()
        norm = binorm.cross(tangent).normalized()
        ring = []
        for s in range(segs):
            ang = (2.0 * math.pi * s) / segs
            v = bm.verts.new(p + (norm * math.cos(ang) + binorm * math.sin(ang)) * minor_r)
            ring.append(v)
        rings.append(ring)

    faces = []
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for s in range(segs):
            sn = (s + 1) % segs
            faces.append(bm.faces.new((r0[s], r1[s], r1[sn], r0[sn])))
    faces.append(bm.faces.new(list(reversed(rings[0]))))
    faces.append(bm.faces.new(rings[-1]))
    _tag_faces(faces, region, True)


def _build_geometry() -> tuple["bpy.types.Mesh", list[int]]:
    """Build industrial cable reel geometry with 4 region slots."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    # 1. Two heavy timber flanges (region 0)
    for sx in (-FLANGE_X, FLANGE_X):
        _add_cylinder_x(bm, Vector((sx, 0.0, CENTER_Z)), REEL_R, FLANGE_T, 24, region=0, smooth=False)

    # Inner wooden drum core behind coils (region 0)
    _add_cylinder_x(bm, Vector((0.0, 0.0, CENTER_Z)), 0.25, REEL_W - 2.0 * FLANGE_T, 16, region=0, smooth=True)

    # Outer timber reinforcement battens on each flange (region 0)
    for sx in (-REEL_W * 0.5 - 0.008, REEL_W * 0.5 + 0.008):
        for bz in (-0.23, 0.23):
            _add_box(bm, Vector((sx, 0.0, CENTER_Z + bz)), Vector((0.016, 0.54, 0.065)), region=0)

    # 2. Wound black rubberized power cable coils (10 rings -> ~1600 tris, region 1)
    num_coils = 10
    span_x = 0.47
    for ci in range(num_coils):
        cx = -span_x * 0.5 + (ci / (num_coils - 1)) * span_x
        _add_torus_x(
            bm,
            Vector((cx, 0.0, CENTER_Z)),
            major_r=0.305,
            minor_r=0.0255,
            major_segs=16,
            minor_segs=5,
            region=1,
            smooth=True,
        )
    # Second inner layer hint / end wrap tail
    _add_cable_tail(bm, region=1)

    # 3. Steel hub plates, axle sleeve & 6 perimeter bolts per side (region 2)
    for sx in (-REEL_W * 0.5 - 0.006, REEL_W * 0.5 + 0.006):
        _add_cylinder_x(bm, Vector((sx, 0.0, CENTER_Z)), 0.14, 0.012, 16, region=2, smooth=False)
        for bi in range(6):
            ang = math.radians(bi * 60.0)
            by = math.cos(ang) * 0.105
            bz = math.sin(ang) * 0.105
            bolt_x = sx + (-0.008 if sx < 0 else 0.008)
            _add_cylinder_x(bm, Vector((bolt_x, by, CENTER_Z + bz)), 0.012, 0.016, 6, region=2, smooth=False)

    # Central steel axle pipe
    _add_cylinder_x(bm, Vector((0.0, 0.0, CENTER_Z)), 0.048, REEL_W + 0.036, 12, region=2, smooth=True)

    # 4. Stencil placard on front/right flange outer face (region 3)
    stencil_x = -REEL_W * 0.5 - 0.004
    _add_box(bm, Vector((stencil_x, -0.24, CENTER_Z)), Vector((0.008, 0.18, 0.12)), region=3)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    stencil_front_indices = [f.index for f in bm.faces if f.material_index == 3 and f.normal.x < -0.9]

    mesh = bpy.data.meshes.new(f"{PROP_SLUG}_mesh")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(4):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    return mesh, stencil_front_indices


def _unwrap_quadrants_and_merge_material(
    obj: "bpy.types.Object",
    stencil_front_indices: list[int],
    final_mat: "bpy.types.Material",
) -> None:
    """Smart-project each material region into its own non-overlapping UV quadrant."""
    import bmesh
    import bpy

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    quads = {
        0: (0.02, 0.48, 0.52, 0.98),  # Top-Left: weathered timber
        1: (0.52, 0.98, 0.52, 0.98),  # Top-Right: black rubber cable
        2: (0.02, 0.48, 0.02, 0.48),  # Bottom-Left: rusted steel hub & bolts
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
    uv_layer = bm.loops.layers.uv.verify()
    stencil_set = set(stencil_front_indices)
    for f in bm.faces:
        if f.material_index != 3:
            continue
        if f.index in stencil_set:
            ys = [loop.vert.co.y for loop in f.loops]
            zs = [loop.vert.co.z for loop in f.loops]
            y_min, y_max = min(ys), max(ys)
            z_min, z_max = min(zs), max(zs)
            dy = max(y_max - y_min, 1e-5)
            dz = max(z_max - z_min, 1e-5)
            for loop in f.loops:
                ty = (loop.vert.co.y - y_min) / dy
                tz = (loop.vert.co.z - z_min) / dz
                loop[uv_layer].uv = (0.525 + ty * 0.45, 0.025 + tz * 0.45)
        else:
            for idx, loop in enumerate(f.loops):
                u = 0.51 + (0.01 if idx in (1, 2) else 0.0)
                v = 0.01 + (0.01 if idx in (2, 3) else 0.0)
                loop[uv_layer].uv = (u, v)

    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(obj.data)
    bm.free()

    obj.data.materials.clear()
    obj.data.materials.append(final_mat)


def build_prop() -> None:
    """Build cable_reel GLB and asset_manifest.json."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    _ensure_textures_exist()
    clean_scene()

    mesh, stencil_front_indices = _build_geometry()
    obj = bpy.data.objects.new("cable_reel", mesh)
    bpy.context.collection.objects.link(obj)

    final_mat = _create_atlas_material()
    _unwrap_quadrants_and_merge_material(obj, stencil_front_indices, final_mat)

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
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "CylinderShape3D",
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
