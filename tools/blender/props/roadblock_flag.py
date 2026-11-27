"""Procedural Post-Soviet Weathered Galvanized Roadblock Warning Flag.

Generates weathered PBR texture maps via PIL/numpy + process_pbr.py, builds a
weathered galvanized steel post (~1.35m tall, base flange grounded at min_z = 0
centered on the pole axis so it mounts cleanly onto the roadblock steel socket)
with bolted collar, mounting rings, finial cap, and a faded weathered orange/red
cloth warning pennant flag with natural wind billow. Exports GLB, ORMMaterial3D
.tres, and asset_manifest.json.

Run:
    /snap/bin/blender --background --python tools/blender/props/roadblock_flag.py
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "roadblock_flag"
TEXTURE_DIR: Path = ASSET_DIR / "textures"
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"

TARGET_HEIGHT_M: float = 1.35
TRI_BUDGET: int = 800
TEX_SIZE: int = 1024


def _pick_python() -> str:
    """Return a Python interpreter that has numpy and PIL available."""
    venv_py = REPO_ROOT / ".venv" / "bin" / "python"
    if venv_py.is_file():
        return str(venv_py)
    return "/usr/bin/python3"


def _generate_textures() -> None:
    """Synthesize clamped [30..240] sRGB weathered cloth & galvanized steel PBR maps."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(84219)
    h = TEX_SIZE
    w = TEX_SIZE

    def fbm_noise(scale_list: tuple[tuple[int, float], ...]) -> np.ndarray:
        acc = np.zeros((h, w), dtype=np.float32)
        total_wt = 0.0
        for grid_sz, wt in scale_list:
            coarse = rng.random((grid_sz, grid_sz), dtype=np.float32)
            img_c = Image.fromarray((coarse * 255.0).astype(np.uint8), mode="L")
            up = (
                np.array(img_c.resize((w, h), Image.Resampling.BICUBIC), dtype=np.float32)
                / 255.0
            )
            acc += up * wt
            total_wt += wt
        return acc / max(total_wt, 1e-6)

    macro = fbm_noise(((8, 0.5), (24, 0.3), (64, 0.2)))
    fine = fbm_noise(((128, 0.5), (256, 0.5)))

    albedo = np.zeros((h, w, 3), dtype=np.float32)
    metallic = np.zeros((h, w), dtype=np.float32)

    split_x = int(w * 0.58)
    split_y = int(h * 0.58)  # PIL y < split_y => UV v > 0.42

    # --- Region 0 (UV u in [0.0, 0.58]): Faded Weathered Orange/Red Warning Cloth ---
    yy0, xx0 = np.mgrid[0:h, 0:split_x]
    u0 = xx0 / float(max(1, split_x - 1))  # 0 at hoist, 1 at fly tip
    v0 = 1.0 - (yy0 / float(max(1, h - 1)))  # 0 at bottom edge, 1 at top edge

    # Woven coarse canvas threads
    weave_x = 0.5 + 0.5 * np.sin(xx0 * 0.85)
    weave_y = 0.5 + 0.5 * np.sin(yy0 * 0.85)
    weave = 0.5 * (weave_x + weave_y)

    # Faded Post-Soviet warning orange-red cloth (sun-bleached center, grimy edges)
    cloth_base = np.array([176.0, 74.0, 44.0], dtype=np.float32)
    sun_fade = np.array([202.0, 114.0, 76.0], dtype=np.float32)
    fade_factor = np.clip(0.25 + 0.55 * macro[:, :split_x] * (0.4 + 0.6 * v0), 0.0, 0.72)
    cloth_col = cloth_base[None, None, :] * (1.0 - fade_factor[..., None]) + sun_fade[
        None, None, :
    ] * fade_factor[..., None]
    cloth_col *= 0.88 + 0.14 * weave[..., None] + 0.12 * (fine[:, :split_x, None] - 0.5)

    # Distressed faded off-white vertical/chevron warning stripe near hoist (u in 0.18..0.30)
    stripe_band = (u0 > 0.18) & (u0 < 0.30) & (v0 > 0.10) & (v0 < 0.90)
    wear_noise = macro[:, :split_x] * 0.65 + fine[:, :split_x] * 0.35
    stripe_mask = stripe_band & (wear_noise < 0.62)
    stripe_col = np.array([194.0, 184.0, 166.0], dtype=np.float32) * (
        0.86 + 0.18 * weave[..., None]
    )
    cloth_col = np.where(stripe_mask[..., None], cloth_col * 0.30 + stripe_col * 0.70, cloth_col)

    # Dark grime & oil staining near hoist sleeve, bottom hem, and tattered fly tip
    edge_grime = np.clip(
        np.exp(-u0 * 7.5) * 0.65
        + np.exp(-(1.0 - u0) * 5.0) * 0.70
        + np.exp(-v0 * 9.0) * 0.45
        + np.exp(-(1.0 - v0) * 10.0) * 0.35,
        0.0,
        0.85,
    )
    grime_mask = edge_grime * (0.55 + 0.75 * macro[:, :split_x])
    grime_col = np.array([64.0, 48.0, 38.0], dtype=np.float32)
    cloth_col = cloth_col * (1.0 - grime_mask[..., None] * 0.65) + grime_col * (
        grime_mask[..., None] * 0.65
    )

    albedo[:, :split_x, :] = cloth_col
    metallic[:, :split_x] = 0.0

    # --- Region 1 (UV u in [0.58, 1.0], PIL y < split_y): Weathered Galvanized Steel ---
    galv_base = np.array([136.0, 140.0, 142.0], dtype=np.float32)
    spangle = fbm_noise(((32, 0.5), (96, 0.5)))[:split_y, split_x:]
    galv_col = galv_base[None, None, :] * (
        0.78 + 0.30 * spangle[..., None] + 0.14 * (fine[:split_y, split_x:, None] - 0.5)
    )
    rust_spots = (macro[:split_y, split_x:] * 0.58 + fine[:split_y, split_x:] * 0.42) > 0.60
    rust_col1 = np.array([118.0, 68.0, 42.0], dtype=np.float32) * (
        0.82 + 0.26 * fine[:split_y, split_x:, None]
    )
    albedo[:split_y, split_x:, :] = np.where(rust_spots[..., None], rust_col1, galv_col)
    metallic[:split_y, split_x:] = np.where(rust_spots, 0.22, 0.78)

    # --- Region 2 (UV u in [0.58, 1.0], PIL y >= split_y): Rusted Iron Flange & Clamps ---
    iron_base = np.array([82.0, 78.0, 74.0], dtype=np.float32)
    iron_col = iron_base[None, None, :] * (
        0.78 + 0.28 * macro[split_y:, split_x:, None] + 0.14 * fine[split_y:, split_x:, None]
    )
    heavy_rust = (macro[split_y:, split_x:] * 0.55 + fine[split_y:, split_x:] * 0.45) > 0.46
    rust_col2 = np.array([116.0, 60.0, 36.0], dtype=np.float32) * (
        0.84 + 0.26 * fine[split_y:, split_x:, None]
    )
    albedo[split_y:, split_x:, :] = np.where(heavy_rust[..., None], rust_col2, iron_col)
    metallic[split_y:, split_x:] = np.where(heavy_rust, 0.18, 0.68)

    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)
    alb_img = Image.fromarray(albedo_u8, mode="RGB")

    # Add hem stitch lines on cloth and subtle vertical rust streaks on galvanized post
    draw = ImageDraw.Draw(alb_img)
    for y_hem in (int(h * 0.05), int(h * 0.95)):
        for x_dash in range(12, split_x - 16, 18):
            draw.line((x_dash, y_hem, x_dash + 10, y_hem), fill=(72, 42, 32), width=2)
    for _ in range(28):
        x0 = int(rng.integers(split_x + 12, w - 12))
        y0 = int(rng.integers(12, split_y - 70))
        dy = int(rng.integers(24, 64))
        draw.line((x0, y0, x0, y0 + dy), fill=(86, 62, 46), width=2)
    alb_img = alb_img.filter(ImageFilter.GaussianBlur(radius=0.35))

    alb_arr = np.clip(np.array(alb_img, dtype=np.uint8), 30, 240)
    albedo_path = TEXTURE_DIR / "roadblock_flag_albedo.png"
    Image.fromarray(alb_arr, mode="RGB").save(albedo_path, format="PNG")

    metallic_path = TEXTURE_DIR / "roadblock_flag_metallic.png"
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
            "roadblock_flag",
            "--preset",
            "fabric",
            "--normal-strength",
            "2.0",
            "--base-roughness",
            "0.90",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = TEXTURE_DIR / "roadblock_flag_ao.png"
    rough_path = TEXTURE_DIR / "roadblock_flag_roughness.png"
    height_path = TEXTURE_DIR / "roadblock_flag_height.png"
    normal_path = TEXTURE_DIR / "roadblock_flag_normal.png"
    orm_path = TEXTURE_DIR / "roadblock_flag_orm.png"

    # Calibrate roughness per atlas region:
    # Region 0 (cloth): matte 0.85..0.97 (216..247)
    # Region 1 (galvanized steel): 0.42..0.72 (108..184), rougher on rust spots
    # Region 2 (rusted iron flange/clamps): 0.58..0.84 (148..214)
    rough_arr = np.array(Image.open(rough_path).convert("L"), dtype=np.float32)
    rough_arr[:, :split_x] = np.clip(rough_arr[:, :split_x], 216.0, 247.0)
    galv_rough = np.where(rust_spots, 195.0, 128.0) + (fine[:split_y, split_x:] - 0.5) * 42.0
    rough_arr[:split_y, split_x:] = np.clip(galv_rough, 108.0, 215.0)
    iron_rough = np.where(heavy_rust, 208.0, 152.0) + (fine[split_y:, split_x:] - 0.5) * 36.0
    rough_arr[split_y:, split_x:] = np.clip(iron_rough, 138.0, 224.0)
    Image.fromarray(rough_arr.astype(np.uint8), mode="L").save(rough_path, format="PNG")

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

    tres_path = ASSET_DIR / "roadblock_flag.tres"
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "build-tres",
            "--name",
            "roadblock_flag",
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
        TEXTURE_DIR / "roadblock_flag_albedo.png",
        TEXTURE_DIR / "roadblock_flag_normal.png",
        TEXTURE_DIR / "roadblock_flag_orm.png",
        ASSET_DIR / "roadblock_flag.tres",
    ]
    if all(p.is_file() for p in required):
        return
    env = os.environ.copy()
    subprocess.run(
        [_pick_python(), str(Path(__file__).resolve()), "--generate-textures"],
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
    # 0 = weathered orange/red cloth warning pennant flag
    # 1 = galvanized steel vertical post + top finial cap
    # 2 = rusted iron socket base flange, collar sleeve, bolt heads & flag tie-rings
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
        bevel_w: float = 0.003,
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

    def add_cyl(
        group: int,
        z_bot: float,
        z_top: float,
        r_bot: float,
        r_top: float,
        segs: int = 12,
        center_xy: tuple[float, float] = (0.0, 0.0),
    ) -> None:
        tmp = bmesh.new()
        height = z_top - z_bot
        bmesh.ops.create_cone(
            tmp,
            cap_ends=True,
            cap_tris=False,
            segments=segs,
            radius1=r_bot,
            radius2=r_top,
            depth=height,
        )
        cx, cy = center_xy
        bmesh.ops.transform(
            tmp,
            matrix=Matrix.Translation(Vector((cx, cy, z_bot + height * 0.5))),
            verts=tmp.verts,
        )
        _merge_into(bms[group], tmp)

    # --- Group 2: Base mounting flange + collar sleeve (seats flush on roadblock 0.085m socket) ---
    # Square mounting plate: 0.082 x 0.082 x 0.018m, z in [0.000, 0.018]
    add_box(2, Vector((0.0, 0.0, 0.009)), Vector((0.082, 0.082, 0.018)), bevel_w=0.0025)
    # Tapered weld collar sleeve: z in [0.016, 0.085]
    add_cyl(2, 0.016, 0.085, r_bot=0.030, r_top=0.024, segs=10)
    # Set-screw clamping lug on collar side
    add_box(2, Vector((-0.032, 0.0, 0.052)), Vector((0.018, 0.016, 0.016)), bevel_w=0.002)

    # Two rusted iron flag tie-rings / mounting clamps along upper post
    for z_ring in (0.905, 1.280):
        add_cyl(2, z_ring - 0.012, z_ring + 0.012, r_bot=0.0255, r_top=0.0255, segs=10)
        # Small bracket tab facing +X toward flag hoist grommet
        add_box(2, Vector((0.026, 0.0, z_ring)), Vector((0.018, 0.012, 0.018)), bevel_w=0.0015)

    # --- Group 1: Weathered Galvanized Steel Pole (~1.35m tall) ---
    # Main conduit pipe: z in [0.015, 1.326], radius 0.0195m (~39mm OD)
    add_cyl(1, 0.015, 1.326, r_bot=0.0195, r_top=0.0190, segs=12)
    # Pressed weathered steel cap finial: z in [1.324, 1.350]
    add_cyl(1, 1.324, 1.340, r_bot=0.023, r_top=0.021, segs=10)
    add_cyl(1, 1.340, TARGET_HEIGHT_M, r_bot=0.021, r_top=0.011, segs=10)

    # --- Group 0: Faded Weathered Orange/Red Cloth Warning Pennant Flag ---
    # Solid watertight double-sided pennant mesh extending +X from hoist (x=0.024..0.60m),
    # tapering from height 0.42m (z=0.88..1.30) to blunted tip (height 0.065m) with wind billow.
    nx = 6  # 6 columns along fly (7 grid verts in X)
    nz = 4  # 4 rows top-to-bottom (5 grid verts in Z)
    x_start = 0.024
    x_len = 0.576  # extends to x = 0.600m
    z_hoist_bot = 0.880
    z_hoist_top = 1.300
    half_thick = 0.0032  # 6.4mm solid cloth thickness for clean double-sided rendering

    def _flag_surface_point(u: float, v: float) -> Vector:
        # u in [0, 1] hoist -> tip, v in [0, 1] bottom -> top
        x = x_start + u * x_len
        # Taper smoothly toward a blunted warning pennant tip + slight gravity sag
        half_h_hoist = 0.5 * (z_hoist_top - z_hoist_bot)
        half_h_tip = 0.032
        half_h = half_h_hoist * (1.0 - 0.85 * u) + half_h_tip * (0.85 * u)
        z_mid = 0.5 * (z_hoist_bot + z_hoist_top) - 0.048 * (u ** 1.35)
        # Subtle worn sag along bottom edge
        z = z_mid + (v - 0.5) * 2.0 * half_h
        # Organic wind billow S-curve along Y
        y = (
            0.044 * math.sin(u * 1.55 * math.pi) * (u ** 0.80)
            + 0.010 * math.sin(u * 2.6 * math.pi + v * math.pi) * u
        )
        return Vector((x, y, z))

    # Build front (+Y) and back (-Y) vertex grids + perimeter seam faces
    bm_flag = bms[0]
    front_grid: list[list[bmesh.types.BMVert]] = []
    back_grid: list[list[bmesh.types.BMVert]] = []

    for ix in range(nx + 1):
        u = ix / float(nx)
        f_col: list[bmesh.types.BMVert] = []
        b_col: list[bmesh.types.BMVert] = []
        for iz in range(nz + 1):
            v = iz / float(nz)
            pt = _flag_surface_point(u, v)
            # Finite-difference tangent to get local surface normal for clean constant thickness
            du = 0.01
            p_u = _flag_surface_point(min(1.0, u + du), v) - _flag_surface_point(
                max(0.0, u - du), v
            )
            p_v = _flag_surface_point(u, min(1.0, v + du)) - _flag_surface_point(
                u, max(0.0, v - du)
            )
            nrm = p_u.cross(p_v)
            if nrm.length < 1e-6:
                nrm = Vector((0.0, 1.0, 0.0))
            else:
                nrm.normalize()
            if nrm.y < 0.0:
                nrm = -nrm
            f_col.append(bm_flag.verts.new(pt + nrm * half_thick))
            b_col.append(bm_flag.verts.new(pt - nrm * half_thick))
        front_grid.append(f_col)
        back_grid.append(b_col)

    # Front faces (+Y outward) and Back faces (-Y outward)
    for ix in range(nx):
        for iz in range(nz):
            bm_flag.faces.new(
                (
                    front_grid[ix][iz],
                    front_grid[ix][iz + 1],
                    front_grid[ix + 1][iz + 1],
                    front_grid[ix + 1][iz],
                )
            )
            bm_flag.faces.new(
                (
                    back_grid[ix][iz],
                    back_grid[ix + 1][iz],
                    back_grid[ix + 1][iz + 1],
                    back_grid[ix][iz + 1],
                )
            )

    # Stitch 4 perimeter edges watertight
    for ix in range(nx):
        # Bottom edge (iz = 0)
        bm_flag.faces.new(
            (front_grid[ix][0], front_grid[ix + 1][0], back_grid[ix + 1][0], back_grid[ix][0])
        )
        # Top edge (iz = nz)
        bm_flag.faces.new(
            (front_grid[ix][nz], back_grid[ix][nz], back_grid[ix + 1][nz], front_grid[ix + 1][nz])
        )
    for iz in range(nz):
        # Hoist edge (ix = 0)
        bm_flag.faces.new(
            (front_grid[0][iz], back_grid[0][iz], back_grid[0][iz + 1], front_grid[0][iz + 1])
        )
        # Fly tip edge (ix = nx)
        bm_flag.faces.new(
            (front_grid[nx][iz], front_grid[nx][iz + 1], back_grid[nx][iz + 1], back_grid[nx][iz])
        )

    # UV atlas regions:
    # 0 = weathered orange/red cloth (left 0.02..0.56, v 0.02..0.98)
    # 1 = galvanized steel post (right 0.60..0.98, top v 0.44..0.98)
    # 2 = rusted iron flange & clamps (right 0.60..0.98, bottom v 0.02..0.40)
    uv_regions = {
        0: (0.02, 0.02, 0.56, 0.98),
        1: (0.60, 0.44, 0.98, 0.98),
        2: (0.60, 0.02, 0.98, 0.40),
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
            # Explicit planar UV projection (X -> U, local Z -> V) so weave & warning stripe align
            if not m.uv_layers:
                m.uv_layers.new(name="UVMap")
            uv_layer = m.uv_layers.active.data
            u0, v0, u1, v1 = uv_regions[grp]
            for poly in m.polygons:
                for li in poly.loop_indices:
                    co = m.vertices[m.loops[li].vertex_index].co
                    u_norm = max(0.0, min(1.0, (co.x - x_start) / max(x_len, 1e-4)))
                    v_norm = max(
                        0.0,
                        min(1.0, (co.z - z_hoist_bot) / max(z_hoist_top - z_hoist_bot, 1e-4)),
                    )
                    uv_layer[li].uv = (
                        u0 + u_norm * (u1 - u0),
                        v0 + v_norm * (v1 - v0),
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
    obj.name = "RoadblockFlag"
    obj.data.name = "RoadblockFlag_Mesh"

    # Ground min_z = 0 ONLY; keep pole axis centered at X=0, Y=0 for socket mounting!
    min_z = min(v.co.z for v in obj.data.vertices)
    if abs(min_z) > 1e-6:
        for v in obj.data.vertices:
            v.co.z -= min_z
        obj.data.update()

    bpy.ops.object.shade_smooth()
    wn = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    wn.weight = 50
    bpy.ops.object.modifier_apply(modifier=wn.name)

    mat = bpy.data.materials.new(name="Mat_RoadblockFlag")
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
        str(TEXTURE_DIR / "roadblock_flag_albedo.png"), check_existing=True
    )
    tex_alb.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-400, 0)
    tex_orm.image = bpy.data.images.load(
        str(TEXTURE_DIR / "roadblock_flag_orm.png"), check_existing=True
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
        str(TEXTURE_DIR / "roadblock_flag_normal.png"), check_existing=True
    )
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -280)
    nrm_node.inputs["Strength"].default_value = 0.80
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.append(mat)

    glb_path = ASSET_DIR / "roadblock_flag.glb"
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
        "prop_slug": "roadblock_flag",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": dims_godot,
        "min_y_m": round(min(zs2), 4),
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "CylinderShape3D",
        "generator": "procedural_bpy",
        "tri_budget": TRI_BUDGET,
        "materials": ["res://assets/models/roadblock_flag/roadblock_flag.tres"],
        "glb": "res://assets/models/roadblock_flag/roadblock_flag.glb",
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_ROADBLOCK_FLAG:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    if "--generate-textures" in sys.argv:
        _generate_textures()
    else:
        _run_blender_build()
