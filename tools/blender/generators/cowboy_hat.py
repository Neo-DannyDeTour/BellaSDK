"""Generator for a detailed mid-poly Western Cowboy Hat with PBR textures and Godot 4 collision."""

from __future__ import annotations

import math
import sys
from pathlib import Path

# Add tools/blender to sys.path so common utilities are importable
_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
import mathutils
import numpy as np
from common.collisions import create_convex_collision
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material


# ---------------------------------------------------------------------------
# Continuous C2-Smooth Parametric Cowboy Hat Surface Math
# ---------------------------------------------------------------------------

def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _hat_surface_point(theta: float, p: float) -> tuple[float, float, float]:
    """Evaluate a single continuous, seam-free 3D point on the cowboy hat.

    theta: angle around Z in [0, 2*pi). -Y (sin=-1) is FRONT, +Y (sin=+1) is BACK.
    p: continuous profile parameter in [0, 1]:
       - p in [0.00, 0.34]: Crown top dome & cattleman crease
       - p in [0.34, 0.62]: Crown rounded shoulder & tapered side wall down to headband
       - p in [0.62, 1.00]: Wide sweeping western brim out to outer edge
    """
    cos_t = math.cos(theta)
    sin_t = math.sin(theta)

    # Base headband ellipse at p = 0.62 (z = 0.038m)
    rx_base = 0.084  # 16.8cm crown width
    ry_base = 0.106  # 21.2cm crown length
    z_band = 0.038
    z_crown_peak = 0.158

    if p <= 0.62:
        # Normalized crown coordinate u_c in [0, 1] from center (0) to headband (1)
        u_c = p / 0.62

        # Smooth rounded dome + tapered wall profile:
        # From u_c=0..0.55: expands from 0 to shoulder (0.74 * base)
        # From u_c=0.55..1.0: tapers smoothly from 0.74 * base out to 1.00 * base
        if u_c < 0.55:
            s_top = u_c / 0.55
            # Smooth sin curve for radius, cosine curve for rounded shoulder height
            r_scale_x = 0.75 * math.sin(s_top * math.pi * 0.45)
            r_scale_y = 0.82 * math.sin(s_top * math.pi * 0.45)
            shoulder_drop = 0.014 * (1.0 - math.cos(s_top * math.pi * 0.5))
            z = z_crown_peak - shoulder_drop
        else:
            s_wall = (u_c - 0.55) / 0.45
            r0_x = 0.75 * math.sin(math.pi * 0.45)
            r0_y = 0.82 * math.sin(math.pi * 0.45)
            # Smooth flare out to 1.0 at headband
            flare = s_wall + 0.12 * math.sin(s_wall * math.pi)
            r_scale_x = r0_x + (1.0 - r0_x) * flare
            r_scale_y = r0_y + (1.0 - r0_y) * flare
            z_shoulder = z_crown_peak - 0.014
            # Smoothly curve down the wall
            z = z_shoulder - (z_shoulder - z_band) * (s_wall**1.12)

        x = rx_base * r_scale_x * cos_t
        y = ry_base * r_scale_y * sin_t

        # Subtle front-to-back saddle on crown top (front & rear peaks slightly higher)
        top_weight = 1.0 - _smoothstep(0.45, 0.85, u_c)
        fb_saddle = (0.007 * (sin_t * sin_t) - 0.003 * sin_t) * _smoothstep(0.05, 0.45, u_c)
        z += fb_saddle * top_weight

        # Slight backward rake as crown rises
        height_frac = max(0.0, (z - z_band) / (z_crown_peak - z_band))
        y += 0.008 * (height_frac**1.3)

        # 1. Smooth Cattleman Center Crease (runs front-to-back along X=0 on top of crown)
        # Uses smooth Gaussian across X and fades out before reaching front/back walls
        crease_mask = (1.0 - _smoothstep(0.42, 0.72, u_c)) * (1.0 - (abs(y) / (ry_base * 0.84)) ** 3.2)
        crease_mask = max(0.0, crease_mask)
        valley_x = math.exp(-((x / 0.032) ** 2))
        # Subtle lift on the two side ridges flanking the center crease (|x| ~ 0.044)
        ridge_x = math.exp(-(((abs(x) - 0.044) / 0.020) ** 2)) * _smoothstep(0.15, 0.45, u_c)
        z -= 0.034 * valley_x * crease_mask
        z += 0.009 * ridge_x * crease_mask

        # 2. Classic Front-Side Teardrop Pinches (Dimples on upper-front crown walls)
        # Centered at y ~ -0.046m (front half), height_frac ~ 0.68
        if y < 0.02:
            h_env = math.exp(-(((height_frac - 0.68) / 0.28) ** 2))
            y_env = math.exp(-(((y - (-0.046)) / 0.040) ** 2))
            x_env = math.exp(-(((abs(x) - 0.054) / 0.028) ** 2))
            pinch = h_env * y_env * x_env
            x -= math.copysign(0.022 * pinch, x)
            z -= 0.007 * pinch

        return x, y, z

    # Brim section: p in [0.62, 1.00] -> s in [0, 1]
    s = (p - 0.62) / 0.38

    # Wide Western Brim radii (43cm wide before curl, 45cm front-to-back)
    rx = rx_base + (0.215 - rx_base) * s
    ry = ry_base + (0.226 - ry_base) * s

    x = rx * cos_t
    y = ry * sin_t
    z = z_band

    side_w = cos_t * cos_t
    is_front = sin_t < 0.0
    front_w = (-sin_t) ** 1.5 if is_front else 0.0
    back_w = (sin_t) ** 1.5 if not is_front else 0.0

    # Smooth Cattleman Side Roll (sweeps upward and curls gently inward)
    side_lift = 0.076 * (s**1.75) * (side_w**1.15)
    side_inward = 0.028 * (s**2.2) * (side_w**1.35)
    x -= math.copysign(side_inward, cos_t)

    # Classic Front Scoop Dip
    front_dip = -0.028 * (s**1.2) * front_w

    # Back Brim: slight dip then gentle upward sweep
    back_curve = (-0.010 * s + 0.020 * (s**2.0)) * back_w

    z += side_lift + front_dip + back_curve
    return x, y, z


# ---------------------------------------------------------------------------
# Procedural PBR Texture Synthesis (1024x1024 Albedo, Roughness, Normal)
# ---------------------------------------------------------------------------

def _generate_pbr_textures(output_dir: Path) -> tuple[bpy.types.Image, bpy.types.Image, bpy.types.Image]:
    """Synthesize clean, velvety felt & tooled leather 1024x1024 PBR maps."""
    output_dir.mkdir(parents=True, exist_ok=True)
    res = 1024

    v_grid, u_grid = np.mgrid[0:res, 0:res].astype(np.float32) / float(res)

    rng = np.random.default_rng(42)
    fine_noise = rng.standard_normal((res, res)).astype(np.float32)
    med_noise = np.repeat(
        np.repeat(rng.standard_normal((res // 4, res // 4)).astype(np.float32), 4, axis=0),
        4,
        axis=1,
    )
    coarse_noise = np.repeat(
        np.repeat(rng.standard_normal((res // 16, res // 16)).astype(np.float32), 16, axis=0),
        16,
        axis=1,
    )
    for _ in range(4):
        med_noise = 0.25 * (
            np.roll(med_noise, 1, 0)
            + np.roll(med_noise, -1, 0)
            + np.roll(med_noise, 1, 1)
            + np.roll(med_noise, -1, 1)
        )
        coarse_noise = 0.25 * (
            np.roll(coarse_noise, 2, 0)
            + np.roll(coarse_noise, -2, 0)
            + np.roll(coarse_noise, 2, 1)
            + np.roll(coarse_noise, -2, 1)
        )

    felt_grain = 0.45 * fine_noise + 0.35 * med_noise + 0.20 * coarse_noise

    albedo = np.zeros((res, res, 4), dtype=np.float32)
    albedo[..., 3] = 1.0
    roughness = np.full((res, res), 0.80, dtype=np.float32)
    height = np.zeros((res, res), dtype=np.float32)

    # 1. HAT FELT SHELL (v < 0.72)
    # Note: In _build_hat_shell_with_uvs:
    # - Crown center to shoulder: v_uv in [0.00, 0.26] -> v_felt in [0.00, 0.36]
    # - Headband seam (p=0.62): v_uv = 0.46 -> v_felt = 0.46 / 0.72 = 0.64
    # - Outer brim edge (p=1.00): v_uv = 0.715 -> v_felt = 0.993
    mask_felt = v_grid < 0.72
    v_felt = np.clip(v_grid / 0.72, 0.0, 1.0)
    theta_u = u_grid * math.tau

    # Warm, rich Stetson saddle-tan / cognac beaver-felt color
    base_r = 0.38 + 0.018 * coarse_noise + 0.008 * fine_noise
    base_g = 0.20 + 0.010 * coarse_noise + 0.005 * fine_noise
    base_b = 0.09 + 0.005 * coarse_noise + 0.003 * fine_noise

    # Subtle AO darkening in center crease (v_felt < 0.14) and right at headband crease (v_felt ~ 0.64)
    crease_ao = np.exp(-((v_felt - 0.06) / 0.08) ** 2) * (0.5 + 0.5 * np.sin(theta_u) ** 2)
    headband_ao = np.exp(-((v_felt - 0.64) / 0.045) ** 2)
    brim_edge_ao = np.exp(-((v_felt - 0.99) / 0.03) ** 2)
    crown_ridge_highlight = np.exp(-((v_felt - 0.26) / 0.10) ** 2)

    shade_mult = (
        1.0
        - 0.22 * crease_ao
        - 0.28 * headband_ao
        - 0.18 * brim_edge_ao
        + 0.10 * crown_ridge_highlight
    )

    albedo[..., 0] = np.where(mask_felt, np.clip(base_r * shade_mult, 0.05, 0.95), albedo[..., 0])
    albedo[..., 1] = np.where(mask_felt, np.clip(base_g * shade_mult, 0.03, 0.95), albedo[..., 1])
    albedo[..., 2] = np.where(mask_felt, np.clip(base_b * shade_mult, 0.01, 0.95), albedo[..., 2])

    # Delicate, fine single stitch row right inside the bound brim edge (v_felt ~ 0.968)
    stitch_dash = (np.sin(u_grid * 220.0 * math.pi) > 0.25).astype(np.float32)
    stitches = (np.abs(v_felt - 0.968) < 0.0018).astype(np.float32) * stitch_dash * mask_felt

    albedo[..., 0] = np.where(stitches > 0.5, 0.58, albedo[..., 0])
    albedo[..., 1] = np.where(stitches > 0.5, 0.38, albedo[..., 1])
    albedo[..., 2] = np.where(stitches > 0.5, 0.18, albedo[..., 2])

    roughness = np.where(
        mask_felt,
        np.clip(0.82 - 0.10 * headband_ao + 0.03 * felt_grain, 0.45, 0.95),
        roughness,
    )
    height = np.where(mask_felt, 0.08 * felt_grain + 0.25 * stitches, height)

    # 2. TOOLED LEATHER HATBAND & BOUND BRIM PIPING (0.72 <= v < 0.88)
    mask_band = (v_grid >= 0.72) & (v_grid < 0.88)
    v_band = np.clip((v_grid - 0.72) / 0.16, 0.0, 1.0)

    # Subtle western basketweave tooling in center of leather band
    diamond_a = np.sin((u_grid * 56.0 + v_band * 2.5) * math.tau)
    diamond_b = np.sin((u_grid * 56.0 - v_band * 2.5) * math.tau)
    tooling = (diamond_a * diamond_b) * np.exp(-((v_band - 0.5) / 0.28) ** 2)

    band_r = 0.12 + 0.018 * tooling + 0.006 * med_noise
    band_g = 0.055 + 0.009 * tooling + 0.003 * med_noise
    band_b = 0.025 + 0.004 * tooling

    albedo[..., 0] = np.where(mask_band, np.clip(band_r, 0.02, 0.45), albedo[..., 0])
    albedo[..., 1] = np.where(mask_band, np.clip(band_g, 0.01, 0.45), albedo[..., 1])
    albedo[..., 2] = np.where(mask_band, np.clip(band_b, 0.01, 0.45), albedo[..., 2])

    roughness = np.where(mask_band, np.clip(0.40 - 0.06 * tooling, 0.25, 0.60), roughness)
    height = np.where(mask_band, 0.30 * tooling + 0.05 * fine_noise, height)

    # 3. BRASS & SILVER HARDWARE (v >= 0.88)
    mask_metal = v_grid >= 0.88
    albedo[..., 0] = np.where(mask_metal, np.clip(0.84 + 0.02 * fine_noise, 0.5, 0.98), albedo[..., 0])
    albedo[..., 1] = np.where(mask_metal, np.clip(0.66 + 0.02 * fine_noise, 0.4, 0.90), albedo[..., 1])
    albedo[..., 2] = np.where(mask_metal, np.clip(0.25 + 0.01 * fine_noise, 0.1, 0.50), albedo[..., 2])
    roughness = np.where(mask_metal, np.clip(0.24 + 0.03 * fine_noise, 0.15, 0.40), roughness)
    height = np.where(mask_metal, 0.03 * fine_noise, height)

    # Compute smooth tangent-space Normal Map
    dh_du = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dh_dv = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    strength = 1.35
    nx = -dh_du * strength
    ny = -dh_dv * strength
    nz = np.ones_like(height)
    norm_len = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx /= norm_len
    ny /= norm_len
    nz /= norm_len

    normal_rgba = np.zeros((res, res, 4), dtype=np.float32)
    normal_rgba[..., 0] = nx * 0.5 + 0.5
    normal_rgba[..., 1] = ny * 0.5 + 0.5
    normal_rgba[..., 2] = nz * 0.5 + 0.5
    normal_rgba[..., 3] = 1.0

    rough_rgba = np.zeros((res, res, 4), dtype=np.float32)
    rough_rgba[..., 0] = roughness
    rough_rgba[..., 1] = roughness
    rough_rgba[..., 2] = roughness
    rough_rgba[..., 3] = 1.0

    def _save_image(name: str, pixels_rgba: np.ndarray, is_data: bool = False) -> bpy.types.Image:
        img = bpy.data.images.get(name)
        if img:
            bpy.data.images.remove(img)
        img = bpy.data.images.new(name=name, width=res, height=res, alpha=False, is_data=is_data)
        img.pixels.foreach_set(pixels_rgba.ravel())
        file_path = output_dir / f"{name}.png"
        img.filepath_raw = str(file_path)
        img.file_format = "PNG"
        img.save()
        img.pack()
        return img

    img_albedo = _save_image("cowboy_hat_albedo", albedo, is_data=False)
    img_rough = _save_image("cowboy_hat_roughness", rough_rgba, is_data=True)
    img_norm = _save_image("cowboy_hat_normal", normal_rgba, is_data=True)
    return img_albedo, img_rough, img_norm


# ---------------------------------------------------------------------------
# Mesh Builders with Explicit UV Mapping
# ---------------------------------------------------------------------------

def _build_hat_shell_with_uvs() -> bpy.types.Object:
    """Create the thickened Stetson crown and wide curled brim with seamless curvature."""
    mesh = bpy.data.meshes.new("CowboyHat_Shell_Mesh")
    obj = bpy.data.objects.new("CowboyHat_Shell", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    num_angular = 48

    # 22 continuous profile rings from crown center (p=0.04) to outer brim (p=1.00)
    p_samples = [
        0.04, 0.10, 0.16, 0.22, 0.27, 0.31, 0.35, 0.39,
        0.44, 0.49, 0.54, 0.58, 0.61, 0.62,
        0.65, 0.70, 0.76, 0.82, 0.88, 0.94, 0.98, 1.00,
    ]
    # Map p in [0, 1] to UV v in [0.02, 0.715]
    uv_v_samples = [0.02 + (0.715 - 0.02) * p for p in p_samples]

    thickness = 0.0042
    top_rings: list[list[bmesh.types.BMVert]] = []
    bot_rings: list[list[bmesh.types.BMVert]] = []

    cx, cy, cz = _hat_surface_point(0.0, 0.0)
    top_center = bm.verts.new((cx, cy, cz))
    bot_center = bm.verts.new((cx, cy, cz - thickness))

    for p in p_samples:
        t_ring: list[bmesh.types.BMVert] = []
        b_ring: list[bmesh.types.BMVert] = []
        for i in range(num_angular):
            theta = (i / num_angular) * math.tau
            x, y, z = _hat_surface_point(theta, p)
            t_ring.append(bm.verts.new((x, y, z)))

            # Offset inward on crown wall and downward on crown top / brim
            wall_mask = math.exp(-(((p - 0.48) / 0.14) ** 2))
            in_scale = 1.0 - (thickness * 0.85 * wall_mask) / 0.085
            b_ring.append(bm.verts.new((x * in_scale, y * in_scale, z - thickness * (1.0 - 0.5 * wall_mask))))
        top_rings.append(t_ring)
        bot_rings.append(b_ring)

    bm.verts.ensure_lookup_table()

    def _set_face_uvs(face: bmesh.types.BMFace, uvs: list[tuple[float, float]]) -> None:
        for loop, uv in zip(face.loops, uvs):
            loop[uv_layer].uv = uv

    # 1. Center fans
    v0_uv = uv_v_samples[0]
    for i in range(num_angular):
        next_i = (i + 1) % num_angular
        u1, u2 = i / num_angular, (i + 1) / num_angular
        f_top = bm.faces.new((top_center, top_rings[0][i], top_rings[0][next_i]))
        _set_face_uvs(f_top, [(0.5, 0.0), (u1, v0_uv), (u2, v0_uv)])

        f_bot = bm.faces.new((bot_center, bot_rings[0][next_i], bot_rings[0][i]))
        _set_face_uvs(f_bot, [(0.5, 0.0), (u2, v0_uv), (u1, v0_uv)])

    # 2. Bridge rings
    for r_idx in range(len(p_samples) - 1):
        va, vb = uv_v_samples[r_idx], uv_v_samples[r_idx + 1]
        t_a, t_b = top_rings[r_idx], top_rings[r_idx + 1]
        b_a, b_b = bot_rings[r_idx], bot_rings[r_idx + 1]
        for i in range(num_angular):
            next_i = (i + 1) % num_angular
            u1, u2 = i / num_angular, (i + 1) / num_angular

            f_t = bm.faces.new((t_a[i], t_b[i], t_b[next_i], t_a[next_i]))
            _set_face_uvs(f_t, [(u1, va), (u1, vb), (u2, vb), (u2, va)])

            f_b = bm.faces.new((b_a[next_i], b_b[next_i], b_b[i], b_a[i]))
            _set_face_uvs(f_b, [(u2, va), (u2, vb), (u1, vb), (u1, va)])

    # 3. Outer Brim Cap
    t_outer, b_outer = top_rings[-1], bot_rings[-1]
    for i in range(num_angular):
        next_i = (i + 1) % num_angular
        u1, u2 = i / num_angular, (i + 1) / num_angular
        f_rim = bm.faces.new((t_outer[i], b_outer[i], b_outer[next_i], t_outer[next_i]))
        _set_face_uvs(f_rim, [(u1, 0.78), (u1, 0.82), (u2, 0.82), (u2, 0.78)])

    # Gentle Laplacian relax on the crown vertices (r_idx <= 11) so creases & pinches blend like real felt
    crown_verts = [top_center, bot_center]
    for r_idx in range(12):
        crown_verts.extend(top_rings[r_idx])
        crown_verts.extend(bot_rings[r_idx])
    for _ in range(2):
        bmesh.ops.smooth_vert(bm, verts=crown_verts, factor=0.38, use_axis_x=True, use_axis_y=True, use_axis_z=True)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def _build_brim_piping_trim() -> bpy.types.Object:
    """Create a sleek bound leather trim along the outer edge of the brim."""
    mesh = bpy.data.meshes.new("CowboyHat_Trim_Mesh")
    obj = bpy.data.objects.new("CowboyHat_Trim", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    num_angular = 48
    tube_sides = 8
    tube_r = 0.0036

    centers = [
        mathutils.Vector(_hat_surface_point((i / num_angular) * math.tau, 1.0))
        + mathutils.Vector((0.0, 0.0, -0.0021))
        for i in range(num_angular)
    ]

    rings: list[list[bmesh.types.BMVert]] = []
    for i in range(num_angular):
        p_prev = centers[(i - 1) % num_angular]
        p_curr = centers[i]
        p_next = centers[(i + 1) % num_angular]
        tangent = (p_next - p_prev).normalized()
        up = mathutils.Vector((0.0, 0.0, 1.0))
        normal = tangent.cross(up).normalized()
        binormal = normal.cross(tangent).normalized()

        ring: list[bmesh.types.BMVert] = []
        for j in range(tube_sides):
            phi = (j / tube_sides) * math.tau
            offset = normal * (math.cos(phi) * tube_r) + binormal * (math.sin(phi) * tube_r)
            ring.append(bm.verts.new(p_curr + offset))
        rings.append(ring)

    for i in range(num_angular):
        next_i = (i + 1) % num_angular
        u1, u2 = i / num_angular, (i + 1) / num_angular
        for j in range(tube_sides):
            next_j = (j + 1) % tube_sides
            # Map to solid dark leather band center (v in [0.77, 0.83])
            v1 = 0.77 + 0.06 * (j / tube_sides)
            v2 = 0.77 + 0.06 * ((j + 1) / tube_sides)
            f = bm.faces.new((rings[i][j], rings[next_i][j], rings[next_i][next_j], rings[i][next_j]))
            for loop, uv in zip(f.loops, [(u1, v1), (u2, v1), (u2, v2), (u1, v2)]):
                loop[uv_layer].uv = uv

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def _build_tooled_hatband() -> bpy.types.Object:
    """Create the thick tooled leather hatband hugging the base of the crown."""
    mesh = bpy.data.meshes.new("CowboyHat_Band_Mesh")
    obj = bpy.data.objects.new("CowboyHat_Band", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    num_angular = 48
    # p=0.62 is bottom headband seam (z=0.038), p=0.545 is top of hatband (z~0.059)
    p_vals = [0.62, 0.582, 0.545]
    v_uvs = [0.73, 0.80, 0.87]
    band_offset = 0.0035

    outer_rings: list[list[bmesh.types.BMVert]] = []
    inner_rings: list[list[bmesh.types.BMVert]] = []

    for p_val in p_vals:
        o_ring: list[bmesh.types.BMVert] = []
        i_ring: list[bmesh.types.BMVert] = []
        for i in range(num_angular):
            theta = (i / num_angular) * math.tau
            x, y, z = _hat_surface_point(theta, p_val)
            r_xy = math.hypot(x, y)
            scale_out = (r_xy + band_offset) / r_xy
            scale_in = (r_xy - 0.0005) / r_xy
            o_ring.append(bm.verts.new((x * scale_out, y * scale_out, z)))
            i_ring.append(bm.verts.new((x * scale_in, y * scale_in, z)))
        outer_rings.append(o_ring)
        inner_rings.append(i_ring)

    for r_idx in range(len(p_vals) - 1):
        va, vb = v_uvs[r_idx], v_uvs[r_idx + 1]
        for i in range(num_angular):
            next_i = (i + 1) % num_angular
            u1, u2 = i / num_angular, (i + 1) / num_angular
            f = bm.faces.new(
                (
                    outer_rings[r_idx][i],
                    outer_rings[r_idx + 1][i],
                    outer_rings[r_idx + 1][next_i],
                    outer_rings[r_idx][next_i],
                )
            )
            for loop, uv in zip(f.loops, [(u1, va), (u1, vb), (u2, vb), (u2, va)]):
                loop[uv_layer].uv = uv

    for i in range(num_angular):
        next_i = (i + 1) % num_angular
        u1, u2 = i / num_angular, (i + 1) / num_angular
        f_top = bm.faces.new(
            (outer_rings[-1][i], inner_rings[-1][i], inner_rings[-1][next_i], outer_rings[-1][next_i])
        )
        for loop, uv in zip(f_top.loops, [(u1, 0.87), (u1, 0.86), (u2, 0.86), (u2, 0.87)]):
            loop[uv_layer].uv = uv

        f_bot = bm.faces.new(
            (inner_rings[0][i], outer_rings[0][i], outer_rings[0][next_i], inner_rings[0][next_i])
        )
        for loop, uv in zip(f_bot.loops, [(u1, 0.73), (u1, 0.74), (u2, 0.74), (u2, 0.73)]):
            loop[uv_layer].uv = uv

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def _build_buckle_and_conchos() -> bpy.types.Object:
    """Create a 3D hollow belt buckle, center bar, prong, and western diamond conchos."""
    mesh = bpy.data.meshes.new("CowboyHat_Hardware_Mesh")
    obj = bpy.data.objects.new("CowboyHat_Hardware", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    bx, by, bz = _hat_surface_point(-math.pi * 0.5, 0.582)
    by -= 0.0052

    ox, oz = 0.017, 0.0135
    ix, iz = 0.0115, 0.0085
    depth = 0.0032

    bars = [
        (-ox, ox, iz, oz, -depth, depth),
        (-ox, ox, -oz, -iz, -depth, depth),
        (-ox, -ix, -iz, iz, -depth, depth),
        (ix, ox, -iz, iz, -depth, depth),
        (-0.002, 0.002, -iz, iz, -depth * 0.8, depth * 0.8),
        (-0.013, 0.001, -0.0016, 0.0016, -depth * 1.25, depth * 0.5),
    ]

    for x0, x1, z0, z1, y0, y1 in bars:
        ret = bmesh.ops.create_cube(bm, size=1.0)
        for v in ret["verts"]:
            vx = bx + x0 + (v.co.x + 0.5) * (x1 - x0)
            vz = bz + z0 + (v.co.z + 0.5) * (z1 - z0)
            curve_y = (vx * vx) * 3.8
            vy = by + y0 + (v.co.y + 0.5) * (y1 - y0) + curve_y
            v.co = (vx, vy, vz)

    concho_angles = [
        -math.pi * 0.22,
        0.0,
        math.pi * 0.25,
        math.pi * 0.50,
        math.pi * 0.75,
        math.pi,
        -math.pi * 0.78,
    ]
    for angle in concho_angles:
        cx, cy, cz = _hat_surface_point(angle, 0.582)
        r_xy = math.hypot(cx, cy)
        nx, ny = cx / r_xy, cy / r_xy
        tx, ty = -ny, nx

        center_pos = mathutils.Vector((cx + nx * 0.0050, cy + ny * 0.0050, cz))
        c_top = bm.verts.new(center_pos + mathutils.Vector((nx * 0.0025, ny * 0.0025, 0.0)))
        c_ring: list[bmesh.types.BMVert] = []
        n_sides = 8
        for k in range(n_sides):
            a = (k / n_sides) * math.tau
            mod = 1.15 if (k % 2 == 0) else 0.82
            du = math.cos(a) * 0.010 * mod
            dz = math.sin(a) * 0.0075 * mod
            pos = center_pos + mathutils.Vector((tx * du, ty * du, dz))
            c_ring.append(bm.verts.new(pos))

        for k in range(n_sides):
            bm.faces.new((c_top, c_ring[k], c_ring[(k + 1) % n_sides]))

    for face in bm.faces:
        for loop in face.loops:
            loop[uv_layer].uv = (0.5, 0.94)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


# ---------------------------------------------------------------------------
# Headless Preview Renderer (for visual verification)
# ---------------------------------------------------------------------------

def render_preview(hat_obj: bpy.types.Object, preview_path: Path) -> None:
    """Render a lit 3/4 view preview PNG of the cowboy hat to verify shape & textures."""
    scene = bpy.context.scene

    available = {e.identifier for e in scene.render.bl_rna.properties["engine"].enum_items}
    if "BLENDER_EEVEE_NEXT" in available:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    elif "BLENDER_EEVEE" in available:
        scene.render.engine = "BLENDER_EEVEE"
    else:
        scene.render.engine = "BLENDER_WORKBENCH"

    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.film_transparent = False

    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.13, 0.13, 0.15, 1.0)
        bg.inputs[1].default_value = 1.0

    lights_spec = [
        ("KeyLight", "AREA", (0.65, -0.75, 0.70), 42.0, (1.0, 0.96, 0.90)),
        ("FillLight", "AREA", (-0.75, -0.55, 0.45), 20.0, (0.82, 0.88, 1.0)),
        ("RimLight", "AREA", (0.0, 0.80, 0.60), 32.0, (1.0, 0.90, 0.78)),
    ]
    created_objs: list[bpy.types.Object] = []
    for name, ltype, loc, energy, color in lights_spec:
        ldata = bpy.data.lights.new(name=name, type=ltype)
        ldata.energy = energy
        ldata.color = color
        lobj = bpy.data.objects.new(name=name, object_data=ldata)
        bpy.context.collection.objects.link(lobj)
        lobj.location = loc
        direction = mathutils.Vector((0.0, 0.0, 0.08)) - mathutils.Vector(loc)
        lobj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        created_objs.append(lobj)

    # Pulled back slightly so the entire wide western brim is framed cleanly
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 50.0
    cam_obj = bpy.data.objects.new("PreviewCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0.48, -0.58, 0.34)
    look_target = mathutils.Vector((0.0, 0.0, 0.075))
    cam_obj.rotation_euler = (look_target - cam_obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_obj
    created_objs.append(cam_obj)

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(preview_path)
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)

    for obj in created_objs:
        bpy.data.objects.remove(obj, do_unlink=True)


# ---------------------------------------------------------------------------
# Main Asset Pipeline Entrypoint
# ---------------------------------------------------------------------------

def generate_cowboy_hat(output_dir: Path) -> Path:
    clean_scene()

    # 1. Generate 1024x1024 PBR Textures (Albedo, Roughness, Normal)
    img_albedo, img_rough, img_norm = _generate_pbr_textures(output_dir)

    # 2. Build Seamless Cowboy Hat Geometry with Explicit UVs
    shell = _build_hat_shell_with_uvs()
    trim = _build_brim_piping_trim()
    band = _build_tooled_hatband()
    hardware = _build_buckle_and_conchos()

    # 3. Create Textured PBR Materials (with matching Solid Viewport colors)
    mat_felt = create_pbr_material(
        name="Mat_Hat_Felt",
        base_color=(0.38, 0.20, 0.09, 1.0),
        metallic=0.0,
        roughness=0.80,
        base_color_image=img_albedo,
        roughness_image=img_rough,
        normal_image=img_norm,
        normal_strength=0.65,
    )
    assign_material(shell, mat_felt)

    mat_leather = create_pbr_material(
        name="Mat_Hat_LeatherBand",
        base_color=(0.12, 0.055, 0.025, 1.0),
        metallic=0.05,
        roughness=0.40,
        base_color_image=img_albedo,
        roughness_image=img_rough,
        normal_image=img_norm,
        normal_strength=0.90,
    )
    assign_material(band, mat_leather)
    assign_material(trim, mat_leather)

    mat_metal = create_pbr_material(
        name="Mat_Hat_BuckleBrass",
        base_color=(0.85, 0.66, 0.24, 1.0),
        metallic=0.92,
        roughness=0.25,
        base_color_image=img_albedo,
        roughness_image=img_rough,
        normal_image=img_norm,
        normal_strength=0.25,
    )
    assign_material(hardware, mat_metal)

    # Join parts into single unified game mesh
    bpy.ops.object.select_all(action="DESELECT")
    for part in (shell, trim, band, hardware):
        part.select_set(True)
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.join()
    hat = bpy.context.active_object
    hat.name = "cowboy_hat"

    # Shift lowest vertex to Z=0.0
    min_z = min(v.co.z for v in hat.data.vertices)
    for v in hat.data.vertices:
        v.co.z -= min_z

    tri_count = sum(len(p.vertices) - 2 for p in hat.data.polygons)
    print(f"[Blender] Remade cowboy_hat triangle count: {tri_count}")

    # 4. Render a preview image so we can visually inspect the result
    preview_path = output_dir / "cowboy_hat_preview.png"
    render_preview(hat, preview_path)

    # 5. Create Wireframe Convex Collision Proxy (-convcolonly)
    create_convex_collision(hat, suffix="-convcolonly")

    bpy.ops.object.select_all(action="DESELECT")
    hat.select_set(True)
    bpy.context.view_layer.objects.active = hat

    # 6. Export to GLB & .blend
    output_path = output_dir / "cowboy_hat.glb"
    export_godot_glb(
        filepath=output_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=True,
    )
    return output_path


def main() -> None:
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        assets_dir = sdk_root / "assets" / "models" / "cowboy_hat"
        generate_cowboy_hat(assets_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
