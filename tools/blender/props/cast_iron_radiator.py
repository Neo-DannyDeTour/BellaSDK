"""Procedural Cast Iron Sectional Radiator (0.68m H).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-24_1.png
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-33.png

Features:
- 12 cast-iron two-column radiator sections with chamfered tops/bottoms
- Top & bottom connecting manifold bosses + hex end plugs & bleed valve
- Right-side dark iron supply & return pipes descending to floor flanges (min_y = 0)
- Rear wall-mounting steel brackets
- 2048x2048 PBR atlas (weathered painted cast iron + dark oxidized iron pipework)

Usage:
    .venv/bin/python tools/blender/props/cast_iron_radiator.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/cast_iron_radiator.py
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

PROP_SLUG: str = "cast_iron_radiator"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / PROP_SLUG
TEX_DIR: Path = ASSET_DIR / "textures"
GLB_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{PROP_SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = TEX_DIR / f"{PROP_SLUG}_albedo.png"
NORMAL_PATH: Path = TEX_DIR / f"{PROP_SLUG}_normal.png"
ORM_PATH: Path = TEX_DIR / f"{PROP_SLUG}_orm.png"

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-24_1.png"
TARGET_HEIGHT_M: float = 0.68
TRI_BUDGET: int = 1800

SRC_METAL_DIR: Path = REPO_ROOT / "assets" / "materials" / "painted_industrial_metal" / "textures"
SRC_RUST_DIR: Path = REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"

TEX_SIZE: int = 2048


def _load_square_rgb(path: Path, size: int) -> "np.ndarray":
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.float32)


def generate_textures() -> None:
    """Generate 2048x2048 weathered painted cast-iron + dark iron pipe PBR atlas."""
    import numpy as np
    from PIL import Image, ImageFilter

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2

    src_metal_alb = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_albedo.png", half)
    src_metal_nrm = _load_square_rgb(SRC_METAL_DIR / "painted_industrial_metal_normal.png", half)
    src_rust_alb = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_albedo.png", half)
    src_rust_nrm = _load_square_rgb(SRC_RUST_DIR / "rusted_steel_normal.png", half)

    # 1. Painted Cast Iron (Left half: U in [0.0, 0.5])
    # Extract clean micro-grain & subtle bumps from painted_industrial_metal, plus sand-cast pitting
    lum = 0.299 * src_metal_alb[..., 0] + 0.587 * src_metal_alb[..., 1] + 0.114 * src_metal_alb[..., 2]
    low_lum = np.asarray(
        Image.fromarray(np.clip(lum, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=14)
        ),
        dtype=np.float32,
    )
    high_pass = np.clip(lum - low_lum, -26.0, 22.0)

    rng = np.random.default_rng(18241)
    sand_cast = rng.normal(0.0, 4.5, (half, TEX_SIZE)).astype(np.float32)
    # Tile vertically to fill (TEX_SIZE, half)
    alb_paint = np.zeros((TEX_SIZE, half, 3), dtype=np.float32)
    nrm_paint = np.zeros((TEX_SIZE, half, 3), dtype=np.float32)
    rough_paint = np.zeros((TEX_SIZE, half), dtype=np.float32)
    metal_paint = np.zeros((TEX_SIZE, half), dtype=np.float32)
    ao_paint = np.zeros((TEX_SIZE, half), dtype=np.float32)

    # Off-white / pale warm gray-green enamel paint (matching HL2 radiator refs)
    base_enamel = np.array([186.0, 188.0, 178.0], dtype=np.float32)
    rust_stain = np.array([108.0, 82.0, 66.0], dtype=np.float32)

    for y0, y1 in ((0, half), (half, TEX_SIZE)):
        sl_hp = high_pass
        sl_low = low_lum
        sl_nrm = src_metal_nrm
        sl_rust = src_rust_alb

        # Subtle patina & tiny pinhead rust flecks instead of heavy dark blotches
        chip_mask = np.clip((68.0 - sl_low) / 30.0, 0.0, 1.0) * 0.28
        grime_var = np.clip((sl_low - 122.0) * 0.14, -9.0, 9.0)

        col = base_enamel[None, None, :] + grime_var[..., None] + sl_hp[..., None] * 0.38
        col = col * (1.0 - chip_mask[..., None]) + (sl_rust * 0.45 + rust_stain[None, None, :] * 0.55) * chip_mask[..., None]

        alb_paint[y0:y1, :, :] = col

        # Sand-cast bump + metal normal
        nrm_block = (sl_nrm - 128.0) * 0.40 + 128.0
        nrm_paint[y0:y1, :, :] = nrm_block

        # Painted cast iron roughness: 0.46 (satin enamel) to 0.74 (chalky grime/rust chips)
        rough_paint[y0:y1, :] = np.clip(0.52 - sl_hp * 0.003 + chip_mask * 0.24, 0.42, 0.78)
        # Bare iron chips slightly metallic, intact paint mostly dielectric
        metal_paint[y0:y1, :] = np.clip(0.08 + chip_mask * 0.45, 0.05, 0.55)
        ao_paint[y0:y1, :] = np.clip(0.94 - chip_mask * 0.22 + sl_hp * 0.002, 0.60, 1.0)

    # Add subtle fine sand-cast grain across full painted panel
    cast_noise = rng.normal(0.0, 3.0, (TEX_SIZE, half)).astype(np.float32)
    alb_paint += cast_noise[..., None]

    # Subtle vertical V-axis grime darkening at bottom & top manifolds (when mapped, bottom/top collect soot)
    v_lin = np.linspace(1.0, 0.0, TEX_SIZE, dtype=np.float32)[:, None]
    soot_bot = np.clip((0.18 - v_lin) / 0.18, 0.0, 1.0) * 0.14
    alb_paint *= (1.0 - soot_bot[..., None])
    ao_paint *= (1.0 - soot_bot * 0.45)

    # 2. Dark Oxidized Iron Pipework & Brackets (Right half: U in [0.5, 1.0])
    alb_iron = np.zeros((TEX_SIZE, half, 3), dtype=np.float32)
    nrm_iron = np.zeros((TEX_SIZE, half, 3), dtype=np.float32)
    rough_iron = np.zeros((TEX_SIZE, half), dtype=np.float32)
    metal_iron = np.zeros((TEX_SIZE, half), dtype=np.float32)
    ao_iron = np.zeros((TEX_SIZE, half), dtype=np.float32)

    rust_lum = 0.299 * src_rust_alb[..., 0] + 0.587 * src_rust_alb[..., 1] + 0.114 * src_rust_alb[..., 2]
    for y0, y1 in ((0, half), (half, TEX_SIZE)):
        dark_iron = src_rust_alb * 0.36 + np.array([26.0, 24.0, 22.0], dtype=np.float32)[None, None, :]
        alb_iron[y0:y1, :, :] = dark_iron
        nrm_iron[y0:y1, :, :] = (src_rust_nrm - 128.0) * 0.65 + 128.0
        rough_iron[y0:y1, :] = np.clip(0.46 + (1.0 - rust_lum / 255.0) * 0.24, 0.36, 0.74)
        metal_iron[y0:y1, :] = np.clip(0.84 - np.clip((src_rust_alb[..., 0] - src_rust_alb[..., 2]) / 80.0, 0.0, 0.45), 0.35, 0.90)
        ao_iron[y0:y1, :] = np.clip(0.76 + (rust_lum / 255.0) * 0.24, 0.50, 1.0)

    # Stitch left + right
    alb_full = np.concatenate([alb_paint, alb_iron], axis=1)
    nrm_full = np.concatenate([nrm_paint, nrm_iron], axis=1)
    rough_full = np.concatenate([rough_paint, rough_iron], axis=1)
    metal_full = np.concatenate([metal_paint, metal_iron], axis=1)
    ao_full = np.concatenate([ao_paint, ao_iron], axis=1)

    # Renormalize normal map
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
        material_name="M_CastIronRadiator",
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
            # Re-gather all faces touching original verts or newly created bevel verts
            for f in bm.faces:
                if any(v in vset for v in f.verts):
                    f.material_index = region
                    f.smooth = False
        else:
            _tag_verts(verts, region, smooth=False)

    def add_cylinder(
        center: Vector,
        axis: Vector,
        radius: float,
        depth: float,
        segments: int,
        region: int,
        smooth: bool = True,
    ) -> None:
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
        _tag_verts(ret["verts"], region, smooth=smooth)

    def add_pipe_polyline(
        points: list[Vector],
        radius: float,
        segments: int,
        region: int,
    ) -> None:
        """Sweep an n-gon pipe cleanly along a 3D polyline with mitered joints."""
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
                offset = (side * math.cos(ang) + binorm * math.sin(ang)) * radius
                ring.append(bm.verts.new(pt + offset))
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

    def add_radiator_rib(cx: float, z0: float, z1: float, depth: float, width: float, region: int) -> None:
        """Build 1 cast-iron 2-column radiator section with rounded end caps & central slot."""
        col_depth = 0.044
        y_off = (depth - col_depth) * 0.5
        col_h = z1 - z0
        cz = (z0 + z1) * 0.5
        # Front and rear vertical fluted columns
        for sy in (-1.0, 1.0):
            add_box(Vector((cx, sy * y_off, cz)), Vector((width, col_depth, col_h)), region=region, bevel_w=0.005)
        # Top and bottom manifold shoulder blocks connecting front & rear columns (inset in X & Z to avoid coplanar Z-fighting)
        hub_h = 0.068
        hub_w = width * 0.68
        add_box(Vector((cx, 0.0, z1 - hub_h * 0.5 - 0.012)), Vector((hub_w, depth - 0.036, hub_h)), region=region)
        add_box(Vector((cx, 0.0, z0 + hub_h * 0.5 + 0.012)), Vector((hub_w, depth - 0.036, hub_h)), region=region)

    # Radiator core dimensions (Blender Z-up, front facing -Y)
    num_ribs = 12
    pitch_x = 0.064
    rib_w = 0.040
    rib_d = 0.138
    rib_z0 = 0.062
    rib_z1 = 0.680
    span_x = (num_ribs - 1) * pitch_x
    x_start = -span_x * 0.5

    # Region 0: Weathered painted cast iron
    for i in range(num_ribs):
        add_radiator_rib(x_start + i * pitch_x, rib_z0, rib_z1, rib_d, rib_w, region=0)

    # Top and bottom internal manifold pipes connecting all 12 ribs
    top_man_z = rib_z1 - 0.042
    bot_man_z = rib_z0 + 0.042
    man_len = span_x + rib_w + 0.024
    add_cylinder(Vector((0.0, 0.0, top_man_z)), Vector((1.0, 0.0, 0.0)), 0.022, man_len, 8, region=0, smooth=True)
    add_cylinder(Vector((0.0, 0.0, bot_man_z)), Vector((1.0, 0.0, 0.0)), 0.022, man_len, 8, region=0, smooth=True)

    # Left-side (-X) bleed valve / hex plug & lower blank cap (Region 1: dark oxidized iron)
    left_x = x_start - rib_w * 0.5 - 0.014
    add_cylinder(Vector((left_x, 0.0, top_man_z)), Vector((1.0, 0.0, 0.0)), 0.018, 0.018, 6, region=1, smooth=False)
    add_cylinder(Vector((left_x - 0.016, 0.0, top_man_z)), Vector((1.0, 0.0, 0.0)), 0.009, 0.016, 6, region=1, smooth=False)
    add_cylinder(Vector((left_x, 0.0, bot_man_z)), Vector((1.0, 0.0, 0.0)), 0.018, 0.016, 6, region=1, smooth=False)

    # Right-side (+X) supply & return iron pipes descending cleanly to floor (z = 0.0)
    right_x = x_start + span_x + rib_w * 0.5
    pipe_x = right_x + 0.068
    add_cylinder(Vector((right_x + 0.010, 0.0, top_man_z)), Vector((1.0, 0.0, 0.0)), 0.020, 0.020, 6, region=1, smooth=False)
    add_cylinder(Vector((right_x + 0.010, 0.0, bot_man_z)), Vector((1.0, 0.0, 0.0)), 0.020, 0.020, 6, region=1, smooth=False)

    # Supply pipe: exits top-right manifold, arcs down to floor z=0.0
    supply_pts = [
        Vector((right_x + 0.012, 0.0, top_man_z)),
        Vector((pipe_x - 0.022, 0.0, top_man_z)),
        Vector((pipe_x - 0.006, 0.0, top_man_z - 0.008)),
        Vector((pipe_x, 0.0, top_man_z - 0.024)),
        Vector((pipe_x, 0.0, 0.0)),
    ]
    add_pipe_polyline(supply_pts, radius=0.0115, segments=8, region=1)
    add_cylinder(Vector((pipe_x, 0.0, 0.006)), Vector((0.0, 0.0, 1.0)), 0.024, 0.012, 8, region=1, smooth=False)

    # Lower return pipe teeing into vertical drop or separate parallel return drop to z=0.0
    ret_x = right_x + 0.042
    ret_pts = [
        Vector((right_x + 0.012, 0.018, bot_man_z)),
        Vector((ret_x - 0.012, 0.022, bot_man_z)),
        Vector((ret_x, 0.024, bot_man_z - 0.014)),
        Vector((ret_x, 0.024, 0.0)),
    ]
    add_pipe_polyline(ret_pts, radius=0.010, segments=8, region=1)
    add_cylinder(Vector((ret_x, 0.024, 0.006)), Vector((0.0, 0.0, 1.0)), 0.021, 0.012, 8, region=1, smooth=False)

    # 2 rear wall-mount steel L-brackets (+Y back face)
    for bx in (x_start + pitch_x * 1.5, x_start + span_x - pitch_x * 1.5):
        add_box(Vector((bx, rib_d * 0.5 + 0.014, 0.50)), Vector((0.022, 0.028, 0.022)), region=1)
        add_box(Vector((bx, rib_d * 0.5 + 0.025, 0.52)), Vector((0.036, 0.008, 0.085)), region=1)
        add_box(Vector((bx, rib_d * 0.5 + 0.014, 0.16)), Vector((0.022, 0.028, 0.022)), region=1)
        add_box(Vector((bx, rib_d * 0.5 + 0.025, 0.18)), Vector((0.036, 0.008, 0.085)), region=1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("CastIronRadiator")
    bm.to_mesh(mesh)
    bm.free()

    for r in range(2):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))

    obj = bpy.data.objects.new("CastIronRadiator", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")

    # Pack region 0 into left half [0.015..0.485, 0.015..0.985] and region 1 into right half [0.515..0.985, 0.015..0.985]
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

    # Build final PBR material matching the ORM atlas
    mat = bpy.data.materials.new(name="M_CastIronRadiator")
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

    # Normalize origin: center XY, min_z = 0, exact target height = 0.68m
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
