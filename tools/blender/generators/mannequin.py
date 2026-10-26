"""Generator for the 2.00m Articulated Female Mannequin (Rigged Ragdoll Model).

Produces:
- Articulated 17-segment female ball-jointed mannequin mesh ('Mannequin_Mesh') at exact 2.00m height
  with Catmull-Clark Subdivision Surface topology, crisp 2.5mm recessed ball-joint sockets,
  anatomical bust/waist/pelvis/glute/limb shells, and uniform metric 1:1 square UV-grid layout.
- Procedural Blue UV-Checker Grid PBR material ('Mat_Mannequin_Grid') with two-tone slate/cerulean
  checker squares, sub-grid crosshairs, and dark joint-socket crevice shading.
- 17-bone Armature ('Mannequin_Armature') with 100% rigid per-shell vertex group skinning so ball
  joints pivot cleanly inside their sockets without rubbery mesh deformation during ragdoll physics.
- Multi-angle studio turnaround preview render (Front, Side, Back) matching the reference sheet.
"""

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
from common.armature import add_bone, create_action, create_armature, push_action_to_nla
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material


# ---------------------------------------------------------------------------
# Exact 2.00m A-Pose Anatomical Joint Landmarks (Blender meters: -Y Front, +Z Up)
# Extracted directly from the Front / Side / Back turnaround reference sheet.
# ---------------------------------------------------------------------------

JOINTS: dict[str, mathutils.Vector] = {
    "PelvisBase": mathutils.Vector((0.0, 0.016, 0.955)),
    "WaistLower": mathutils.Vector((0.0, 0.012, 1.182)),
    "WaistUpper": mathutils.Vector((0.0, 0.010, 1.365)),
    "NeckBase": mathutils.Vector((0.0, 0.032, 1.648)),
    "HeadBase": mathutils.Vector((0.0, 0.022, 1.732)),
    "HeadTop": mathutils.Vector((0.0, 0.008, 2.000)),
    # Left Arm (+X in Blender)
    "Shoulder.L": mathutils.Vector((0.188, 0.036, 1.562)),
    "Elbow.L": mathutils.Vector((0.370, 0.050, 1.348)),
    "Wrist.L": mathutils.Vector((0.546, 0.012, 1.115)),
    "HandTip.L": mathutils.Vector((0.642, -0.020, 0.960)),
    # Right Arm (-X in Blender)
    "Shoulder.R": mathutils.Vector((-0.188, 0.036, 1.562)),
    "Elbow.R": mathutils.Vector((-0.370, 0.050, 1.348)),
    "Wrist.R": mathutils.Vector((-0.546, 0.012, 1.115)),
    "HandTip.R": mathutils.Vector((-0.642, -0.020, 0.960)),
    # Left Leg (+X in Blender)
    "Hip.L": mathutils.Vector((0.110, 0.016, 0.985)),
    "Knee.L": mathutils.Vector((0.108, 0.020, 0.540)),
    "Ankle.L": mathutils.Vector((0.106, 0.014, 0.105)),
    "Heel.L": mathutils.Vector((0.104, 0.082, 0.014)),
    "Toe.L": mathutils.Vector((0.122, -0.178, 0.014)),
    # Right Leg (-X in Blender)
    "Hip.R": mathutils.Vector((-0.110, 0.016, 0.985)),
    "Knee.R": mathutils.Vector((-0.108, 0.020, 0.540)),
    "Ankle.R": mathutils.Vector((-0.106, 0.014, 0.105)),
    "Heel.R": mathutils.Vector((-0.104, 0.082, 0.014)),
    "Toe.R": mathutils.Vector((-0.122, -0.178, 0.014)),
}

BONE_NAMES: list[str] = [
    "Pelvis",
    "Waist",
    "Chest",
    "Neck",
    "Head",
    "UpperArm.L",
    "LowerArm.L",
    "Hand.L",
    "UpperArm.R",
    "LowerArm.R",
    "Hand.R",
    "UpperLeg.L",
    "LowerLeg.L",
    "Foot.L",
    "UpperLeg.R",
    "LowerLeg.R",
    "Foot.R",
]


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------
# Procedural Blue UV-Checker Grid PBR Textures (Matching Reference Sheet)
# ---------------------------------------------------------------------------

def _save_np_image(
    name: str,
    pixels_rgba: np.ndarray,
    output_dir: Path,
    is_data: bool = False,
) -> bpy.types.Image:
    res_y, res_x = pixels_rgba.shape[:2]
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name=name, width=res_x, height=res_y, alpha=False, is_data=is_data)
    img.pixels.foreach_set(pixels_rgba.ravel())
    file_path = output_dir / f"{name}.png"
    img.filepath_raw = str(file_path)
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def _height_to_normal_rgba(height: np.ndarray, strength: float = 1.0) -> np.ndarray:
    dh_du = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dh_dv = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -dh_du * strength
    ny = -dh_dv * strength
    nz = np.ones_like(height)
    norm_len = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx /= norm_len
    ny /= norm_len
    nz /= norm_len

    normal_rgba = np.zeros((*height.shape, 4), dtype=np.float32)
    normal_rgba[..., 0] = nx * 0.5 + 0.5
    normal_rgba[..., 1] = ny * 0.5 + 0.5
    normal_rgba[..., 2] = nz * 0.5 + 0.5
    normal_rgba[..., 3] = 1.0
    return normal_rgba


def _generate_mannequin_grid_textures(
    output_dir: Path,
) -> tuple[bpy.types.Image, bpy.types.Image, bpy.types.Image]:
    """Synthesize the exact two-tone slate/cerulean UV checker grid with dark joint-seam strip.

    UV layout convention:
    - v in [0.00, 0.92]: Repeating 16x16 two-tone blue UV checker grid with light-blue quad
      border lines and subtle sub-grid crosshairs.
    - v in [0.94, 1.00]: Dark slate-navy joint socket / inner bevel band used ONLY on tucked-in
      2mm socket lips so every joint has a crisp thin dark separation line.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    res = 2048
    v_grid, u_grid = np.mgrid[0:res, 0:res].astype(np.float32) / float(res)

    cells = 16.0
    cu = u_grid * cells
    cv = v_grid * cells
    cell_x = np.floor(cu).astype(np.int32)
    cell_y = np.floor(cv).astype(np.int32)
    checker = (cell_x + cell_y) & 1

    fu = cu - np.floor(cu)
    fv = cv - np.floor(cv)

    # Exact reference cerulean/slate blue checker squares (linear sRGB)
    c_light = np.array([0.095, 0.252, 0.520], dtype=np.float32)
    c_dark = np.array([0.062, 0.172, 0.390], dtype=np.float32)
    c_line = np.array([0.185, 0.410, 0.710], dtype=np.float32)
    c_sub = np.array([0.125, 0.305, 0.580], dtype=np.float32)
    c_seam = np.array([0.012, 0.028, 0.058], dtype=np.float32)

    albedo = np.zeros((res, res, 4), dtype=np.float32)
    albedo[..., 3] = 1.0
    for ch in range(3):
        albedo[..., ch] = np.where(checker == 0, c_light[ch], c_dark[ch])

    # Crisp primary grid lines along cell boundaries
    dist_major = np.minimum(np.minimum(fu, 1.0 - fu), np.minimum(fv, 1.0 - fv))
    major_mask = np.clip(1.0 - dist_major / 0.022, 0.0, 1.0)

    # Subtle 2x2 sub-grid & tiny center plus-ticks inside each checker square
    dist_sub_u = np.abs(fu - 0.5)
    dist_sub_v = np.abs(fv - 0.5)
    sub_grid_mask = np.clip(1.0 - np.minimum(dist_sub_u, dist_sub_v) / 0.012, 0.0, 1.0) * 0.38

    q_u = np.minimum(np.abs(fu - 0.25), np.abs(fu - 0.75))
    q_v = np.minimum(np.abs(fv - 0.25), np.abs(fv - 0.75))
    tick_mask = (
        ((q_u < 0.010) & (q_v < 0.055)) | ((q_v < 0.010) & (q_u < 0.055))
    ).astype(np.float32) * 0.45

    for ch in range(3):
        albedo[..., ch] = (
            albedo[..., ch] * (1.0 - sub_grid_mask) + c_sub[ch] * sub_grid_mask
        )
        albedo[..., ch] = (
            albedo[..., ch] * (1.0 - tick_mask) + c_line[ch] * tick_mask
        )
        albedo[..., ch] = (
            albedo[..., ch] * (1.0 - major_mask * 0.68) + c_line[ch] * (major_mask * 0.68)
        )

    # Narrow dark joint socket / inner bevel band at v >= 0.94
    seam_blend = np.clip((v_grid - 0.935) / 0.015, 0.0, 1.0)
    for ch in range(3):
        albedo[..., ch] = albedo[..., ch] * (1.0 - seam_blend) + c_seam[ch] * seam_blend

    rough = np.where(checker == 0, 0.38, 0.42).astype(np.float32)
    rough = rough * (1.0 - seam_blend) + 0.55 * seam_blend
    rough_rgba = np.stack([rough, rough, rough, np.ones_like(rough)], axis=-1)

    height = -0.05 * major_mask - 0.02 * sub_grid_mask - 0.22 * seam_blend
    normal_rgba = _height_to_normal_rgba(height, strength=0.40)

    img_albedo = _save_np_image("mannequin_grid_albedo", albedo, output_dir, is_data=False)
    img_rough = _save_np_image("mannequin_grid_roughness", rough_rgba, output_dir, is_data=True)
    img_norm = _save_np_image("mannequin_grid_normal", normal_rgba, output_dir, is_data=True)
    return img_albedo, img_rough, img_norm


# ---------------------------------------------------------------------------
# Parametric Quad-Grid Shell & Ball-Joint Builders (Uniform 1:1 Square UVs)
# ---------------------------------------------------------------------------

# Metric UV scale: 1.0 UV repeat (16 checker squares) = 0.64m -> 1 checker square = 4.0cm!
UV_METRIC_REPEAT = 0.64


def _build_lofted_shell(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    frames: list[tuple[mathutils.Vector, mathutils.Vector, mathutils.Vector, float, float]],
    num_radial: int = 36,
    cap_start: bool = True,
    cap_end: bool = True,
    shape_fn=None,
    seam_start: bool = True,
    seam_end: bool = True,
    custom_seam_fn=None,
) -> None:
    """Loft a smooth watertight quad-grid shell with uniform 1:1 metric square UVs.

    Only the tightly tucked-in 2mm inner lip rings at the start/end are mapped to the dark
    socket crevice UV (v=0.97), so the outer shell displays 100% clean blue checker squares
    right up to the thin joint gap!
    """
    # Insert tight 2mm double-ring bevels near the start and end caps so SubD holds a crisp rim
    expanded_frames: list[tuple[mathutils.Vector, mathutils.Vector, mathutils.Vector, float, float, float, bool]] = []
    n_raw = len(frames)

    for idx, (c, ax_x, ax_y, rx, ry) in enumerate(frames):
        s_frac = idx / max(1, n_raw - 1)
        is_inner_cup = (idx == 0 and seam_start) or (idx == n_raw - 1 and seam_end)
        expanded_frames.append((c, ax_x, ax_y, rx, ry, s_frac, is_inner_cup))
        # Add a holding edge ring right next to the rim so Catmull-Clark SubD doesn't blur the seam
        if idx == 0 and seam_start and n_raw >= 2:
            c1, _, _, rx1, ry1 = frames[1]
            s1 = 1.0 / max(1, n_raw - 1)
            expanded_frames.append(
                (c.lerp(c1, 0.85), ax_x, ax_y, rx + (rx1 - rx) * 0.85, ry + (ry1 - ry) * 0.85, s1 * 0.85, False)
            )
        elif idx == n_raw - 2 and seam_end and n_raw >= 2:
            c_end, _, _, rx_e, ry_e = frames[-1]
            s_prev = (n_raw - 2) / max(1, n_raw - 1)
            expanded_frames.append(
                (c.lerp(c_end, 0.15), ax_x, ax_y, rx + (rx_e - rx) * 0.15, ry + (ry_e - ry) * 0.15, s_prev + (1.0 - s_prev) * 0.15, False)
            )

    rings: list[list[bmesh.types.BMVert]] = []
    arc_lengths: list[float] = [0.0]
    for idx in range(1, len(expanded_frames)):
        d_c = (expanded_frames[idx][0] - expanded_frames[idx - 1][0]).length
        arc_lengths.append(arc_lengths[-1] + d_c)

    # Estimate mean circumference to pick an integer number of checker squares around the ring
    mean_rx = sum(f[3] for f in expanded_frames) / len(expanded_frames)
    mean_ry = sum(f[4] for f in expanded_frames) / len(expanded_frames)
    circumference = math.pi * (mean_rx + mean_ry)
    # Snap U repeat to multiples of 0.125 (2 checker squares) for seamless wrap
    u_repeats = max(0.25, round((circumference / UV_METRIC_REPEAT) * 8.0) / 8.0)

    for idx, (center, ax_x, ax_y, rx, ry, s_frac, _) in enumerate(expanded_frames):
        ring: list[bmesh.types.BMVert] = []
        for k in range(num_radial):
            theta = (k / num_radial) * math.tau
            cos_t = math.cos(theta)
            sin_t = math.sin(theta)
            lx = rx * cos_t
            ly = ry * sin_t
            dz = 0.0
            if shape_fn is not None:
                dlx, dly, dz = shape_fn(s_frac, theta, lx, ly)
                lx += dlx
                ly += dly
            pt = center + ax_x * lx + ax_y * ly + mathutils.Vector((0.0, 0.0, dz))
            ring.append(bm.verts.new(pt))
        rings.append(ring)

    n_exp = len(expanded_frames)
    for idx in range(n_exp - 1):
        r0 = rings[idx]
        r1 = rings[idx + 1]
        s0 = expanded_frames[idx][5]
        s1 = expanded_frames[idx + 1][5]
        cup_face = expanded_frames[idx][6] or expanded_frames[idx + 1][6]

        # Metric V coordinate mapped cleanly inside [0.04, 0.88]
        v_metric_0 = 0.06 + ((arc_lengths[idx] / UV_METRIC_REPEAT) % 0.80)
        v_metric_1 = 0.06 + ((arc_lengths[idx + 1] / UV_METRIC_REPEAT) % 0.80)
        if v_metric_1 < v_metric_0:
            v_metric_1 = v_metric_0 + 0.02

        for k in range(num_radial):
            kn = (k + 1) % num_radial
            theta_mid = ((k + 0.5) / num_radial) * math.tau
            extra_seam = False
            if custom_seam_fn is not None:
                extra_seam = custom_seam_fn(0.5 * (s0 + s1), theta_mid)

            is_dark = cup_face or extra_seam
            va = 0.97 if is_dark else v_metric_0
            vb = 0.97 if is_dark else v_metric_1

            # Offset theta by +pi/2 so U=0.5 sits cleanly along the front/back centerline
            ua = (((k / num_radial) + 0.25) * u_repeats) % 1.0
            ub = ((((k + 1) / num_radial) + 0.25) * u_repeats) % 1.0
            if ub < ua:
                ub = 1.0

            f = bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
            f.smooth = True
            loops = f.loops
            loops[0][uv_layer].uv = (ua, va)
            loops[1][uv_layer].uv = (ub, va)
            loops[2][uv_layer].uv = (ub, vb)
            loops[3][uv_layer].uv = (ua, vb)

    if cap_start and rings:
        c0 = sum((v.co for v in rings[0]), mathutils.Vector()) / len(rings[0])
        v_c0 = bm.verts.new(c0)
        cap_v = 0.97 if seam_start else 0.25
        for k in range(num_radial):
            kn = (k + 1) % num_radial
            f = bm.faces.new((v_c0, rings[0][kn], rings[0][k]))
            f.smooth = True
            for loop in f.loops:
                loop[uv_layer].uv = (0.5, cap_v)

    if cap_end and rings:
        c1 = sum((v.co for v in rings[-1]), mathutils.Vector()) / len(rings[-1])
        v_c1 = bm.verts.new(c1)
        cap_v = 0.97 if seam_end else 0.25
        for k in range(num_radial):
            kn = (k + 1) % num_radial
            f = bm.faces.new((v_c1, rings[-1][k], rings[-1][kn]))
            f.smooth = True
            for loop in f.loops:
                loop[uv_layer].uv = (0.5, cap_v)


def _add_ball_joint(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    center: mathutils.Vector,
    radii: tuple[float, float, float],
    axis_z: mathutils.Vector | None = None,
    num_radial: int = 28,
    num_lat: int = 14,
) -> None:
    """Add an articulated spherical/ellipsoidal ball joint with clean blue grid & thin polar collars."""
    rx, ry, rz = radii
    ax_z = mathutils.Vector((0.0, 0.0, 1.0)) if axis_z is None else axis_z.normalized()
    ref = mathutils.Vector((0.0, 1.0, 0.0)) if abs(ax_z.y) < 0.9 else mathutils.Vector((1.0, 0.0, 0.0))
    ax_x = ref.cross(ax_z).normalized()
    ax_y = ax_z.cross(ax_x).normalized()

    frames = []
    for i in range(num_lat + 1):
        u = i / num_lat
        phi = -0.47 * math.pi + u * (0.94 * math.pi)
        cos_p = math.cos(phi)
        sin_p = math.sin(phi)
        c = center + ax_z * (rz * sin_p)
        frames.append((c, ax_x, ax_y, max(0.004, rx * cos_p), max(0.004, ry * cos_p)))

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=num_radial,
        cap_start=True,
        cap_end=True,
        seam_start=True,
        seam_end=True,
    )


# ---------------------------------------------------------------------------
# Individual Articulated Mannequin Shell Constructors (17 Bone Segments)
# ---------------------------------------------------------------------------

def _build_head_segment(bm: bmesh.types.BMesh, uv_layer: bmesh.types.BMLayerItem) -> None:
    """Build ovoid female mannequin head (z = 1.725..2.000m) matching Front/Side/Back profile."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    head_slices = [
        (1.726, 0.012, 0.036, 0.040),   # Recessed neck socket base
        (1.732, -0.006, 0.052, 0.068),  # Under-jaw / submental plane
        (1.750, -0.016, 0.068, 0.092),  # Chin & lower jaw
        (1.778, -0.014, 0.082, 0.104),  # Mandible / mouth level
        (1.814, -0.006, 0.094, 0.114),  # Cheekbones & lower cranium
        (1.852, 0.002, 0.102, 0.120),   # Eye/brow plane & mid-occiput
        (1.888, 0.006, 0.104, 0.122),   # Parietal / forehead peak width
        (1.925, 0.008, 0.096, 0.114),   # Upper forehead & skull dome
        (1.958, 0.009, 0.078, 0.094),   # Crown slope
        (1.984, 0.009, 0.048, 0.058),   # Upper crown
        (1.996, 0.009, 0.022, 0.026),   # Skull apex
        (2.000, 0.009, 0.005, 0.006),   # Exact 2.000m pole
    ]

    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in head_slices
    ]

    def _head_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        z = 1.726 + s_frac * (2.000 - 1.726)
        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        if sin_t < 0.0:
            fw = -sin_t
            jaw_taper = _smoothstep(1.84, 1.73, z)
            dlx -= 0.012 * jaw_taper * abs(cos_t) * (fw**0.7)
            chin_proj = math.exp(-(((z - 1.748) / 0.024) ** 2)) * math.exp(-((cos_t / 0.45) ** 2))
            brow_proj = math.exp(-(((z - 1.872) / 0.032) ** 2)) * math.exp(-((cos_t / 0.65) ** 2))
            eye_recess = math.exp(-(((z - 1.838) / 0.024) ** 2)) * math.exp(
                -(((abs(cos_t) - 0.34) / 0.22) ** 2)
            )
            dly -= (0.010 * chin_proj + 0.006 * brow_proj - 0.005 * eye_recess) * (fw**1.2)
        else:
            bw = sin_t
            nape_tuck = _smoothstep(1.81, 1.73, z)
            dly -= 0.028 * nape_tuck * (bw**1.3)

        return dlx, dly, dz

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=40,
        cap_start=True,
        cap_end=True,
        shape_fn=_head_shape,
        seam_start=True,
        seam_end=False,
    )


def _build_neck_segment(bm: bmesh.types.BMesh, uv_layer: bmesh.types.BMLayerItem) -> None:
    """Build cylindrical articulated neck column (z = 1.644..1.734m) with thin collar seams."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    neck_slices = [
        (1.644, 0.034, 0.044, 0.044),
        (1.648, 0.034, 0.056, 0.055),
        (1.672, 0.032, 0.054, 0.053),
        (1.700, 0.028, 0.053, 0.052),
        (1.728, 0.024, 0.054, 0.053),
        (1.733, 0.023, 0.042, 0.042),
    ]
    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in neck_slices
    ]
    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=32,
        cap_start=True,
        cap_end=True,
        seam_start=True,
        seam_end=True,
    )


def _build_chest_segment(bm: bmesh.types.BMesh, uv_layer: bmesh.types.BMLayerItem) -> None:
    """Build articulated upper torso shell with sculpted female bust, under-bust seam & ribcage arch."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    chest_slices = [
        (1.348, 0.008, 0.114, 0.078),  # Inner recessed lower socket lip (2mm tucked)
        (1.352, 0.008, 0.132, 0.092),  # Lower ribcage arch rim (matches waist at z=1.352)
        (1.375, 0.008, 0.140, 0.098),  # Epigastric ribcage below breasts
        (1.396, 0.009, 0.146, 0.102),  # Inframammary crease (under-bust seam ring)
        (1.418, 0.010, 0.152, 0.108),  # Lower breast cup swell
        (1.452, 0.012, 0.157, 0.113),  # Breast apex level
        (1.490, 0.016, 0.160, 0.114),  # Upper breast slope
        (1.532, 0.022, 0.162, 0.112),  # Upper chest / axilla
        (1.572, 0.028, 0.162, 0.106),  # Shoulder socket center level
        (1.612, 0.032, 0.154, 0.094),  # Acromion / clavicle rim
        (1.638, 0.034, 0.108, 0.072),  # Trapezius slope
        (1.648, 0.034, 0.062, 0.058),  # Neck socket collar rim
        (1.645, 0.034, 0.048, 0.046),  # Inner recessed neck socket lip
    ]

    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in chest_slices
    ]

    def _chest_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        idx_f = s_frac * (len(chest_slices) - 1)
        i0 = int(min(len(chest_slices) - 2, max(0, math.floor(idx_f))))
        frac = idx_f - i0
        z = chest_slices[i0][0] * (1.0 - frac) + chest_slices[i0 + 1][0] * frac

        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        # 1. Arched lower ribcage cut (+3.4cm arch in front center, thin crisp rim)
        if s_frac < 0.24 and sin_t < 0.15:
            arch_env = (1.0 - s_frac / 0.24) * (max(0.0, -sin_t + 0.15) / 1.15) ** 1.2
            dz += 0.034 * arch_env * math.exp(-((cos_t / 0.68) ** 2))

        # 2. Sculpted Female Bust / Breasts with crisp inframammary crease & sternum cleavage
        if 1.388 < z < 1.565 and sin_t < 0.0:
            fw = -sin_t
            t_bust = (z - 1.388) / (1.565 - 1.388)
            bust_z = (math.sin(t_bust * math.pi) ** 0.95) * (1.0 + 0.35 * (1.0 - t_bust))
            cup = math.exp(-(((abs(cos_t) - 0.43) / 0.31) ** 2))
            cleavage = math.exp(-((cos_t / 0.13) ** 2))
            dly -= (0.054 * cup - 0.012 * cleavage) * bust_z * (fw**1.20)
            dlx += (0.011 if cos_t > 0 else -0.011) * cup * bust_z * fw
            # Curve the under-bust crease downward under each breast cup and up at sternum
            if t_bust < 0.35:
                dz -= 0.014 * cup * (1.0 - t_bust / 0.35) * fw

        # 3. Semi-spherical concave shoulder socket cutouts on left/right (z in 1.49..1.63)
        if 1.49 < z < 1.635 and abs(cos_t) > 0.68:
            lat_env = ((abs(cos_t) - 0.68) / 0.32) ** 1.3
            z_env = math.exp(-(((z - 1.562) / 0.052) ** 2))
            dlx -= (0.022 if cos_t > 0 else -0.022) * lat_env * z_env

        # 4. Back scapular contour & dorsal spine groove (sin_t > 0)
        if 1.36 < z < 1.62 and sin_t > 0.0:
            bw = sin_t
            back_z = math.sin(((z - 1.36) / 0.26) * math.pi)
            scapula = math.exp(-(((abs(cos_t) - 0.45) / 0.34) ** 2))
            spine = math.exp(-((cos_t / 0.15) ** 2))
            dly += (0.016 * scapula - 0.009 * spine) * back_z * (bw**1.4)

        return dlx, dly, dz

    def _chest_seam(s_mid: float, theta_mid: float) -> bool:
        # Thin dark under-bust contour crease (inframammary fold) on front breast cups
        sin_t = math.sin(theta_mid)
        cos_t = math.cos(theta_mid)
        return (0.21 < s_mid < 0.27) and (sin_t < -0.32) and (0.08 < abs(cos_t) < 0.78)

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=52,
        cap_start=True,
        cap_end=True,
        shape_fn=_chest_shape,
        seam_start=True,
        seam_end=True,
        custom_seam_fn=_chest_seam,
    )


def _build_waist_segment(bm: bmesh.types.BMesh, uv_layer: bmesh.types.BMLayerItem) -> None:
    """Build hourglass mid-torso / waist shell (z = 1.180..1.380m) flush with pelvis & chest."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Matches Pelvis top rim (rx=0.162, ry=0.106 at z=1.182) and Chest lower arch (rx=0.132 at z=1.352)
    waist_slices = [
        (1.178, 0.012, 0.144, 0.094),  # Recessed 2mm lower lip inside pelvis
        (1.182, 0.012, 0.162, 0.106),  # Lower waist rim (100% flush with Pelvis top rim!)
        (1.220, 0.010, 0.138, 0.096),  # Lower waist hourglass curve
        (1.268, 0.008, 0.118, 0.088),  # Narrowest female waist (rx=0.118m)
        (1.312, 0.008, 0.124, 0.090),  # Upper waist flare
        (1.352, 0.008, 0.131, 0.091),  # Upper waist rim entering chest arch
        (1.378, 0.008, 0.110, 0.076),  # Recessed upper dome inside chest shell
    ]

    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in waist_slices
    ]

    def _waist_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        # Follow the downward curve of the lower navel/iliac seam in front (dips -1.4cm at center)
        if s_frac < 0.28 and sin_t < 0.0:
            bot_env = (1.0 - s_frac / 0.28) * ((-sin_t) ** 1.1)
            dz -= 0.014 * bot_env * math.exp(-((cos_t / 0.65) ** 2))

        # Follow the upward arch of the ribcage seam in front
        if s_frac > 0.72 and sin_t < 0.0:
            top_env = ((s_frac - 0.72) / 0.28) * ((-sin_t) ** 1.2)
            dz += 0.026 * top_env * math.exp(-((cos_t / 0.68) ** 2))

        if abs(cos_t) < 0.25:
            mid_groove = math.exp(-((cos_t / 0.15) ** 2)) * math.sin(s_frac * math.pi)
            if sin_t < 0.0:
                dly += 0.004 * mid_groove * (-sin_t)
            else:
                dly -= 0.007 * mid_groove * sin_t

        return dlx, dly, dz

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=48,
        cap_start=True,
        cap_end=True,
        shape_fn=_waist_shape,
        seam_start=True,
        seam_end=True,
    )


def _build_pelvis_segment(bm: bmesh.types.BMesh, uv_layer: bmesh.types.BMLayerItem) -> None:
    """Build articulated bikini-brief pelvic shell flush with waist above & thighs below."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Smooth hourglass continuation from z=1.182m (rx=0.162, matching Waist!) out to hips (rx=0.204)
    # and down the V-cut bikini arch to the crotch apex (z=0.946m, rx=0.022).
    pelvis_slices = [
        (0.946, 0.015, 0.020, 0.052),  # Crotch / perineal bridge apex
        (0.964, 0.018, 0.056, 0.088),  # Lower pubic arch & gluteal fold
        (0.992, 0.021, 0.112, 0.112),  # Mid V-cut bikini arch / lower glutes
        (1.024, 0.023, 0.166, 0.124),  # Upper V-cut bikini arch / glute max
        (1.052, 0.022, 0.204, 0.128),  # Outer hip crest above hip socket cut (matches outer thigh!)
        (1.088, 0.019, 0.198, 0.124),  # Mid hip curve
        (1.135, 0.015, 0.182, 0.116),  # Upper iliac hip curve
        (1.180, 0.012, 0.162, 0.106),  # Top pelvic rim (100% flush with Waist lower rim!)
        (1.184, 0.012, 0.146, 0.095),  # Recessed 2mm inner waist socket collar
    ]

    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in pelvis_slices
    ]

    def _pelvis_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        idx_f = s_frac * (len(pelvis_slices) - 1)
        i0 = int(min(len(pelvis_slices) - 2, max(0, math.floor(idx_f))))
        frac = idx_f - i0
        z = pelvis_slices[i0][0] * (1.0 - frac) + pelvis_slices[i0 + 1][0] * frac

        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        # 1. Match the gently dipped front waist seam at top of pelvis (z=1.18m)
        if s_frac > 0.75 and sin_t < 0.0:
            top_env = ((s_frac - 0.75) / 0.25) * ((-sin_t) ** 1.1)
            dz -= 0.014 * top_env * math.exp(-((cos_t / 0.65) ** 2))

        # 2. High-cut diagonal V-arch on front/sides for hip sockets (lifts lateral bottom edge to z=1.05m)
        if s_frac < 0.50 and abs(cos_t) > 0.28:
            lat = (abs(cos_t) - 0.28) / 0.72
            # In front (sin_t <= 0), V-cut is higher; in back (sin_t > 0), glute cheeks hang lower!
            front_bias = 1.0 if sin_t <= 0.0 else max(0.32, 1.0 - 0.68 * (sin_t**1.2))
            arch_lift = (1.0 - s_frac / 0.50) * (lat**1.10) * front_bias
            dz += 0.064 * arch_lift

        # 3. Sculpted Female Gluteal Cheeks & Intergluteal Cleft (Back view sin_t > 0)
        if 0.955 < z < 1.165 and sin_t > 0.0:
            bw = sin_t
            glute_z = math.sin(((z - 0.955) / 0.210) * math.pi)
            cheek = math.exp(-(((abs(cos_t) - 0.44) / 0.34) ** 2))
            cleft = math.exp(-((cos_t / 0.14) ** 2))
            dly += (0.030 * cheek - 0.018 * cleft) * glute_z * (bw**1.25)
            dlx += (0.012 if cos_t > 0 else -0.012) * cheek * glute_z * bw

        # 4. Smooth mons pubis / lower belly contour (Front view sin_t < 0)
        if 0.965 < z < 1.175 and sin_t < 0.0:
            fw = -sin_t
            front_z = math.sin(((z - 0.965) / 0.210) * math.pi)
            dly -= 0.010 * front_z * math.exp(-((cos_t / 0.55) ** 2)) * (fw**1.3)

        return dlx, dly, dz

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=52,
        cap_start=True,
        cap_end=True,
        shape_fn=_pelvis_shape,
        seam_start=True,
        seam_end=True,
    )


def _build_limb_basis(axis_dir: mathutils.Vector) -> tuple[mathutils.Vector, mathutils.Vector, mathutils.Vector]:
    """Construct right-handed local frame (ax_x, ax_y_front_back, ax_z_along_limb)."""
    w = axis_dir.normalized()
    y_hint = mathutils.Vector((0.0, 1.0, 0.0))
    ax_x = y_hint.cross(w).normalized()
    ax_y = w.cross(ax_x).normalized()
    if ax_y.y < 0.0:
        ax_y = -ax_y
        ax_x = -ax_x
    return ax_x, ax_y, w


def _build_upper_arm_segment(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    side: int,
) -> None:
    """Build spherical shoulder ball joint + tapered anatomical upper arm shell."""
    suf = "L" if side > 0 else "R"
    sh = JOINTS[f"Shoulder.{suf}"]
    el = JOINTS[f"Elbow.{suf}"]
    vec = el - sh
    length = vec.length
    ax_x, ax_y, w = _build_limb_basis(vec)

    _add_ball_joint(bm, uv_layer, sh, radii=(0.052, 0.050, 0.052), axis_z=w, num_radial=32, num_lat=14)

    samples = [
        (0.145, 0.038, 0.038),  # Recessed collar lip under shoulder ball
        (0.155, 0.050, 0.048),  # Upper biceps/deltoid rim
        (0.320, 0.048, 0.047),  # Upper-mid arm
        (0.550, 0.045, 0.044),  # Mid biceps/triceps taper
        (0.760, 0.042, 0.041),  # Lower upper-arm taper
        (0.865, 0.041, 0.040),  # Distal elbow socket rim
        (0.878, 0.031, 0.031),  # Recessed inner elbow socket cup
    ]
    frames = [(sh + w * (s * length), ax_x, ax_y, rx, ry) for s, rx, ry in samples]
    _build_lofted_shell(bm, uv_layer, frames, num_radial=32, cap_start=True, cap_end=True)


def _build_lower_arm_segment(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    side: int,
) -> None:
    """Build spherical elbow ball joint + tapered anatomical forearm shell."""
    suf = "L" if side > 0 else "R"
    el = JOINTS[f"Elbow.{suf}"]
    wr = JOINTS[f"Wrist.{suf}"]
    vec = wr - el
    length = vec.length
    ax_x, ax_y, w = _build_limb_basis(vec)

    _add_ball_joint(bm, uv_layer, el, radii=(0.042, 0.041, 0.042), axis_z=w, num_radial=28, num_lat=12)

    samples = [
        (0.120, 0.031, 0.031),  # Recessed proximal socket lip below elbow ball
        (0.132, 0.041, 0.040),  # Proximal forearm collar
        (0.280, 0.043, 0.041),  # Forearm muscle belly swell
        (0.520, 0.038, 0.036),  # Mid forearm taper
        (0.760, 0.032, 0.029),  # Lower forearm taper
        (0.885, 0.029, 0.026),  # Distal wrist cuff rim
        (0.900, 0.021, 0.019),  # Recessed inner wrist socket cup
    ]
    frames = [(el + w * (s * length), ax_x, ax_y, rx, ry) for s, rx, ry in samples]
    _build_lofted_shell(bm, uv_layer, frames, num_radial=32, cap_start=True, cap_end=True)


def _build_hand_segment(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    side: int,
) -> None:
    """Build wrist ball joint + sculpted female mannequin palm, 4 fingers & opposable thumb."""
    suf = "L" if side > 0 else "R"
    wr = JOINTS[f"Wrist.{suf}"]
    tip = JOINTS[f"HandTip.{suf}"]
    vec = tip - wr
    length = vec.length
    w = vec.normalized()

    u_fwd = mathutils.Vector((0.0, -1.0, 0.0))
    u_fwd = (u_fwd - w * u_fwd.dot(w)).normalized()
    v_thick = w.cross(u_fwd).normalized()
    if v_thick.x * side < 0.0:
        v_thick = -v_thick

    _add_ball_joint(bm, uv_layer, wr, radii=(0.027, 0.024, 0.026), axis_z=w, num_radial=24, num_lat=10)

    palm_len = length * 0.52
    palm_samples = [
        (0.17, 0.021, 0.014),
        (0.20, 0.029, 0.018),
        (0.55, 0.037, 0.017),
        (0.92, 0.040, 0.015),
        (1.00, 0.033, 0.010),
    ]
    palm_frames = [
        (wr + w * (s * palm_len), u_fwd, v_thick, rx, ry)
        for s, rx, ry in palm_samples
    ]
    _build_lofted_shell(bm, uv_layer, palm_frames, num_radial=28, cap_start=True, cap_end=True)

    knuckle_base = wr + w * (palm_len * 0.94)
    finger_specs = [
        (0.027, 0.92, 0.0080),
        (0.009, 1.00, 0.0084),
        (-0.010, 0.94, 0.0078),
        (-0.028, 0.78, 0.0068),
    ]
    max_f_len = length * 0.50

    for f_lat, len_mult, r_base in finger_specs:
        f_start = knuckle_base + u_fwd * f_lat
        f_len = max_f_len * len_mult
        f_samples = [
            (0.00, 0.75),
            (0.06, 1.00),
            (0.38, 0.94),
            (0.42, 0.84),
            (0.46, 0.91),
            (0.72, 0.84),
            (0.75, 0.76),
            (0.92, 0.72),
            (1.00, 0.38),
        ]
        f_frames = []
        for s_f, r_scale in f_samples:
            curl = -v_thick * (0.010 * (s_f**1.6))
            c = f_start + w * (s_f * f_len) + curl
            rad = r_base * r_scale
            f_frames.append((c, u_fwd, v_thick, rad, rad * 0.90))
        _build_lofted_shell(
            bm, uv_layer, f_frames, num_radial=14, cap_start=True, cap_end=True, seam_start=True, seam_end=False
        )

    thumb_base = wr + w * (palm_len * 0.36) + u_fwd * 0.030 - v_thick * 0.006
    thumb_dir = (w * 0.76 + u_fwd * 0.58 - v_thick * 0.28).normalized()
    thumb_len = length * 0.36
    t_samples = [
        (0.00, 0.0092),
        (0.15, 0.0112),
        (0.50, 0.0100),
        (0.55, 0.0088),
        (0.88, 0.0082),
        (1.00, 0.0042),
    ]
    t_frames = [
        (thumb_base + thumb_dir * (s_t * thumb_len), u_fwd, v_thick, r_t, r_t * 0.92)
        for s_t, r_t in t_samples
    ]
    _build_lofted_shell(
        bm, uv_layer, t_frames, num_radial=14, cap_start=True, cap_end=True, seam_start=True, seam_end=False
    )


def _build_upper_leg_segment(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    side: int,
) -> None:
    """Build hip ball joint + sculpted female thigh shell flush with diagonal V-hip cut."""
    suf = "L" if side > 0 else "R"
    hip = JOINTS[f"Hip.{suf}"]
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Internal Hip Ball Joint nested inside pelvis V-socket
    _add_ball_joint(bm, uv_layer, hip, radii=(0.064, 0.064, 0.064), num_radial=28, num_lat=12)

    # Thigh slices from knee socket (z=0.586m) up to diagonal hip V-arch (center z=0.990m):
    # At z=0.990m, with dz = +0.052 * outward, the outer hip edge reaches z=1.042m at x=±0.205m
    # (100% flush with Pelvis outer hip at z=1.050m, x=±0.204m!), while the inner crotch edge
    # sits at z=0.938m, x=±0.018m (leaving a clean 3mm diagonal bikini-line gap!).
    thigh_slices = [
        (0.584, 0.020, 0.108, 0.042, 0.044),  # Recessed distal knee socket lip (2mm tucked)
        (0.588, 0.020, 0.108, 0.054, 0.057),  # Distal thigh rim above knee ball
        (0.645, 0.016, 0.108, 0.064, 0.068),  # Lower thigh taper
        (0.715, 0.012, 0.109, 0.075, 0.080),  # Lower-mid thigh
        (0.795, 0.010, 0.110, 0.086, 0.091),  # Mid quadriceps/hamstring belly
        (0.875, 0.012, 0.111, 0.093, 0.098),  # Upper-mid thigh
        (0.945, 0.014, 0.111, 0.095, 0.100),  # Upper thigh
        (0.990, 0.016, 0.111, 0.094, 0.098),  # Diagonal hip V-socket rim (blue grid all the way to rim!)
        (0.994, 0.016, 0.111, 0.076, 0.080),  # Recessed 2mm inner hip socket lip
    ]

    frames = [
        (mathutils.Vector((side * xc, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, xc, rx, ry in thigh_slices
    ]

    def _thigh_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        outward = cos_t * side

        # 1. Diagonal top rim matching the pelvis 42-degree bikini hip arch in front
        # and tucking cleanly under the rounded gluteal fold in back!
        if s_frac > 0.62:
            top_env = (s_frac - 0.62) / 0.38
            if sin_t <= 0.0:
                dz += 0.052 * top_env * outward
            else:
                back_w = sin_t**1.2
                dz += (0.046 * (1.0 - 0.25 * back_w) * outward - 0.008 * back_w) * top_env

        # 2. Concave semi-circular cutout at bottom rim around the spherical knee ball
        if s_frac < 0.16:
            bot_env = 1.0 - (s_frac / 0.16)
            dz -= 0.009 * bot_env * (abs(cos_t) ** 1.4)

        # 3. Feminine quadriceps front sweep & outer-thigh fullness
        mid_bell = math.sin(s_frac * math.pi)
        if sin_t < 0.0:
            dly -= 0.008 * mid_bell * ((-sin_t) ** 1.3)
        if outward > 0.0:
            dlx += (0.006 * side) * mid_bell * (outward**1.2)

        return dlx, dly, dz

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=40,
        cap_start=True,
        cap_end=True,
        shape_fn=_thigh_shape,
        seam_start=True,
        seam_end=True,
    )


def _build_lower_leg_segment(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    side: int,
) -> None:
    """Build prominent spherical knee ball joint + sculpted female calf/shin shell."""
    suf = "L" if side > 0 else "R"
    knee = JOINTS[f"Knee.{suf}"]
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    _add_ball_joint(bm, uv_layer, knee, radii=(0.053, 0.053, 0.051), num_radial=32, num_lat=14)

    calf_slices = [
        (0.138, 0.014, 0.106, 0.030, 0.032),  # Recessed distal ankle socket lip
        (0.142, 0.014, 0.106, 0.040, 0.042),  # Distal ankle cuff rim
        (0.205, 0.018, 0.106, 0.043, 0.046),  # Lower Achilles/shin taper
        (0.285, 0.024, 0.108, 0.051, 0.055),  # Mid shin
        (0.365, 0.030, 0.110, 0.059, 0.064),  # Lower gastrocnemius calf swell
        (0.425, 0.032, 0.111, 0.061, 0.066),  # Peak calf muscle contour
        (0.475, 0.026, 0.109, 0.056, 0.058),  # Upper tibia below knee ball
        (0.494, 0.022, 0.108, 0.052, 0.053),  # Proximal knee socket rim
        (0.498, 0.022, 0.108, 0.040, 0.042),  # Recessed proximal knee socket lip
    ]

    frames = [
        (mathutils.Vector((side * xc, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, xc, rx, ry in calf_slices
    ]

    def _calf_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0
        if 0.40 < s_frac < 0.88 and sin_t > 0.0:
            calf_env = math.sin(((s_frac - 0.40) / 0.48) * math.pi)
            dly += 0.010 * calf_env * (sin_t**1.4)
        return dlx, dly, dz

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=36,
        cap_start=True,
        cap_end=True,
        shape_fn=_calf_shape,
        seam_start=True,
        seam_end=True,
    )


def _build_foot_segment(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    side: int,
) -> None:
    """Build spherical ankle ball joint + sculpted mannequin foot with thin toe-box seam."""
    suf = "L" if side > 0 else "R"
    ankle = JOINTS[f"Ankle.{suf}"]
    heel = JOINTS[f"Heel.{suf}"]
    toe = JOINTS[f"Toe.{suf}"]

    _add_ball_joint(bm, uv_layer, ankle, radii=(0.038, 0.039, 0.037), num_radial=28, num_lat=12)

    foot_vec = mathutils.Vector((toe.x - heel.x, toe.y - heel.y, 0.0))
    foot_len = foot_vec.length
    f_fwd = foot_vec.normalized()
    f_lat = mathutils.Vector((-f_fwd.y, f_fwd.x, 0.0))
    if f_lat.x * side < 0.0:
        f_lat = -f_lat

    foot_slices = [
        (0.00, 0.024, 0.072, 0.004, False),  # Rounded heel back
        (0.10, 0.039, 0.092, 0.000, False),  # Heel cup under ankle ball
        (0.28, 0.042, 0.096, 0.000, False),  # Ankle arch collar peak
        (0.48, 0.042, 0.076, 0.000, False),  # Midfoot instep wedge slope
        (0.66, 0.045, 0.056, 0.000, False),  # Forefoot before toe joint
        (0.68, 0.042, 0.050, 0.001, True),   # Thin 2mm transverse toe-cap joint seam
        (0.70, 0.046, 0.053, 0.000, False),  # Toe-box cap start
        (0.86, 0.044, 0.042, 0.000, False),  # Toe-box taper
        (0.95, 0.035, 0.030, 0.002, False),  # Rounded toe tip
        (1.00, 0.016, 0.016, 0.005, False),  # Distal toe pole
    ]

    n_rad = 28
    rings: list[list[bmesh.types.BMVert]] = []
    seam_flags: list[bool] = []

    for u_f, rx, z_top, z_bot, is_seam in foot_slices:
        base_xy = mathutils.Vector((heel.x, heel.y, 0.0)) + f_fwd * (u_f * foot_len)
        z_mid = 0.5 * (z_bot + z_top)
        h_half = 0.5 * (z_top - z_bot)
        ring: list[bmesh.types.BMVert] = []
        for k in range(n_rad):
            theta = (k / n_rad) * math.tau
            cos_t = math.cos(theta)
            sin_t = math.sin(theta)
            if sin_t < 0.0:
                z_pt = max(z_bot, z_mid + h_half * (sin_t * 0.55))
            else:
                z_pt = z_mid + h_half * (sin_t**0.80)
            pt = mathutils.Vector((base_xy.x, base_xy.y, z_pt)) + f_lat * (rx * cos_t)
            ring.append(bm.verts.new(pt))
        rings.append(ring)
        seam_flags.append(is_seam)

    for idx in range(len(rings) - 1):
        r0 = rings[idx]
        r1 = rings[idx + 1]
        is_seam = seam_flags[idx] and seam_flags[idx + 1]
        uv_va = 0.97 if is_seam else (0.12 + (idx / len(rings)) * 0.35)
        uv_vb = 0.97 if is_seam else (0.12 + ((idx + 1) / len(rings)) * 0.35)
        for k in range(n_rad):
            kn = (k + 1) % n_rad
            f = bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
            f.smooth = True
            ua = (((k / n_rad) + 0.25) * 0.5) % 1.0
            ub = ((((k + 1) / n_rad) + 0.25) * 0.5) % 1.0
            loops = f.loops
            loops[0][uv_layer].uv = (ua, uv_va)
            loops[1][uv_layer].uv = (ub, uv_va)
            loops[2][uv_layer].uv = (ub, uv_vb)
            loops[3][uv_layer].uv = (ua, uv_vb)

    for ring_idx, flip in ((0, True), (-1, False)):
        ring = rings[ring_idx]
        avg = sum((v.co for v in ring), mathutils.Vector()) / len(ring)
        vc = bm.verts.new(avg)
        for k in range(n_rad):
            kn = (k + 1) % n_rad
            f = bm.faces.new((vc, ring[kn], ring[k]) if flip else (vc, ring[k], ring[kn]))
            f.smooth = True
            for loop in f.loops:
                loop[uv_layer].uv = (0.25, 0.25)


# ---------------------------------------------------------------------------
# Assemble Unified Skinned Mannequin Mesh + 17-Bone Ragdoll Armature
# ---------------------------------------------------------------------------

def build_mannequin_mesh_and_rig(mat_grid: bpy.types.Material) -> tuple[bpy.types.Object, bpy.types.Object]:
    """Build all 17 articulated mannequin segments, assign 100% rigid bone weights, and bind Armature."""
    segment_builders = [
        ("Pelvis", lambda bm, uv: _build_pelvis_segment(bm, uv)),
        ("Waist", lambda bm, uv: _build_waist_segment(bm, uv)),
        ("Chest", lambda bm, uv: _build_chest_segment(bm, uv)),
        ("Neck", lambda bm, uv: _build_neck_segment(bm, uv)),
        ("Head", lambda bm, uv: _build_head_segment(bm, uv)),
        ("UpperArm.L", lambda bm, uv: _build_upper_arm_segment(bm, uv, side=+1)),
        ("LowerArm.L", lambda bm, uv: _build_lower_arm_segment(bm, uv, side=+1)),
        ("Hand.L", lambda bm, uv: _build_hand_segment(bm, uv, side=+1)),
        ("UpperArm.R", lambda bm, uv: _build_upper_arm_segment(bm, uv, side=-1)),
        ("LowerArm.R", lambda bm, uv: _build_lower_arm_segment(bm, uv, side=-1)),
        ("Hand.R", lambda bm, uv: _build_hand_segment(bm, uv, side=-1)),
        ("UpperLeg.L", lambda bm, uv: _build_upper_leg_segment(bm, uv, side=+1)),
        ("LowerLeg.L", lambda bm, uv: _build_lower_leg_segment(bm, uv, side=+1)),
        ("Foot.L", lambda bm, uv: _build_foot_segment(bm, uv, side=+1)),
        ("UpperLeg.R", lambda bm, uv: _build_upper_leg_segment(bm, uv, side=-1)),
        ("LowerLeg.R", lambda bm, uv: _build_lower_leg_segment(bm, uv, side=-1)),
        ("Foot.R", lambda bm, uv: _build_foot_segment(bm, uv, side=-1)),
    ]

    seg_objs: list[bpy.types.Object] = []
    for bone_name, builder_fn in segment_builders:
        bm = bmesh.new()
        uv_layer = bm.loops.layers.uv.new("UVMap")
        builder_fn(bm, uv_layer)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

        mesh = bpy.data.meshes.new(f"Seg_{bone_name}_Mesh")
        bm.to_mesh(mesh)
        bm.free()

        for poly in mesh.polygons:
            poly.use_smooth = True

        obj = bpy.data.objects.new(f"Seg_{bone_name}", mesh)
        bpy.context.collection.objects.link(obj)
        assign_material(obj, mat_grid)

        subsurf = obj.modifiers.new(name="Subsurf", type="SUBSURF")
        subsurf.levels = 1
        subsurf.render_levels = 1
        subsurf.uv_smooth = "PRESERVE_BOUNDARIES"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=subsurf.name)

        for b_name in BONE_NAMES:
            obj.vertex_groups.new(name=b_name)
        vg = obj.vertex_groups[bone_name]
        vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        seg_objs.append(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in seg_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = seg_objs[0]
    bpy.ops.object.join()

    mannequin_mesh = bpy.context.active_object
    mannequin_mesh.name = "Mannequin_Mesh"
    mannequin_mesh.data.name = "Mannequin_Mesh_Data"
    mannequin_mesh.data.validate(verbose=False)

    arm_obj = create_armature("Mannequin_Armature")
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    add_bone(arm_obj, "Pelvis", JOINTS["PelvisBase"], JOINTS["WaistLower"], parent_name=None)
    add_bone(arm_obj, "Waist", JOINTS["WaistLower"], JOINTS["WaistUpper"], parent_name="Pelvis")
    add_bone(arm_obj, "Chest", JOINTS["WaistUpper"], JOINTS["NeckBase"], parent_name="Waist")
    add_bone(arm_obj, "Neck", JOINTS["NeckBase"], JOINTS["HeadBase"], parent_name="Chest")
    add_bone(arm_obj, "Head", JOINTS["HeadBase"], JOINTS["HeadTop"], parent_name="Neck")

    for suf in ("L", "R"):
        add_bone(arm_obj, f"UpperArm.{suf}", JOINTS[f"Shoulder.{suf}"], JOINTS[f"Elbow.{suf}"], parent_name="Chest")
        add_bone(arm_obj, f"LowerArm.{suf}", JOINTS[f"Elbow.{suf}"], JOINTS[f"Wrist.{suf}"], parent_name=f"UpperArm.{suf}")
        add_bone(arm_obj, f"Hand.{suf}", JOINTS[f"Wrist.{suf}"], JOINTS[f"HandTip.{suf}"], parent_name=f"LowerArm.{suf}")

    for suf in ("L", "R"):
        add_bone(arm_obj, f"UpperLeg.{suf}", JOINTS[f"Hip.{suf}"], JOINTS[f"Knee.{suf}"], parent_name="Pelvis")
        add_bone(arm_obj, f"LowerLeg.{suf}", JOINTS[f"Knee.{suf}"], JOINTS[f"Ankle.{suf}"], parent_name=f"UpperLeg.{suf}")
        add_bone(arm_obj, f"Foot.{suf}", JOINTS[f"Ankle.{suf}"], JOINTS[f"Toe.{suf}"], parent_name=f"LowerLeg.{suf}")

    bpy.ops.object.mode_set(mode="OBJECT")

    arm_mod = mannequin_mesh.modifiers.new(name="Armature", type="ARMATURE")
    arm_mod.object = arm_obj
    mannequin_mesh.parent = arm_obj

    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    idle_action = create_action(arm_obj, "APose_Idle")
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 2
    for frame in (1, 2):
        bpy.context.scene.frame_set(frame)
        for pb in arm_obj.pose.bones:
            pb.location = (0.0, 0.0, 0.0)
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            pb.keyframe_insert(data_path="location", frame=frame)
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
    push_action_to_nla(arm_obj, idle_action, track_name="NLA_APose_Idle")
    bpy.ops.pose.transforms_clear()
    bpy.ops.object.mode_set(mode="OBJECT")

    return mannequin_mesh, arm_obj


# ---------------------------------------------------------------------------
# Studio Turnaround Preview Renderer (Front, Side, Back)
# ---------------------------------------------------------------------------

def render_turnaround_previews(output_dir: Path) -> Path:
    """Render 3-view telephoto studio turnaround matching the reference image."""
    scene = bpy.context.scene
    available = {e.identifier for e in scene.render.bl_rna.properties["engine"].enum_items}
    if "BLENDER_EEVEE_NEXT" in available:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    elif "BLENDER_EEVEE" in available:
        scene.render.engine = "BLENDER_EEVEE"
    else:
        scene.render.engine = "BLENDER_WORKBENCH"

    world = bpy.data.worlds.new("Temp_Preview_World")
    scene.world = world
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs[0].default_value = (0.032, 0.044, 0.062, 1.0)
        bg.inputs[1].default_value = 1.0

    lights_spec = [
        ("Temp_Key_Front", (0.0, -3.20, 2.35), (0.0, 0.0, 1.15), 220.0, 2.20, (0.98, 0.99, 1.0)),
        ("Temp_Fill_Left", (-2.40, -2.20, 1.40), (0.0, 0.0, 1.05), 95.0, 2.00, (0.90, 0.95, 1.0)),
        ("Temp_Fill_Right", (2.40, -2.20, 1.40), (0.0, 0.0, 1.05), 95.0, 2.00, (0.90, 0.95, 1.0)),
        ("Temp_Back_Key", (0.0, 3.20, 2.25), (0.0, 0.0, 1.15), 210.0, 2.20, (0.98, 0.99, 1.0)),
        ("Temp_Side_Key", (3.20, 0.0, 2.10), (0.0, 0.0, 1.15), 160.0, 2.00, (0.96, 0.98, 1.0)),
    ]

    temp_objs: list[bpy.types.Object] = []
    temp_lights: list[bpy.types.Light] = []
    for name, loc, target, energy, size, color in lights_spec:
        ldata = bpy.data.lights.new(name=name, type="AREA")
        ldata.energy = energy
        ldata.size = size
        ldata.color = color
        lobj = bpy.data.objects.new(name=name, object_data=ldata)
        bpy.context.collection.objects.link(lobj)
        lobj.location = loc
        direction = mathutils.Vector(target) - mathutils.Vector(loc)
        lobj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        temp_objs.append(lobj)
        temp_lights.append(ldata)

    cam_data = bpy.data.cameras.new("Temp_Camera")
    cam_data.lens = 85.0
    cam_obj = bpy.data.objects.new("Temp_Camera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    temp_objs.append(cam_obj)

    scene.render.resolution_x = 520
    scene.render.resolution_y = 760
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"

    look_target = mathutils.Vector((0.0, 0.0, 1.00))
    views = [
        ("front", mathutils.Vector((0.0, -5.80, 1.02))),
        ("side", mathutils.Vector((5.80, 0.0, 1.02))),
        ("back", mathutils.Vector((0.0, 5.80, 1.02))),
    ]

    panel_paths: list[Path] = []
    for v_name, cam_pos in views:
        cam_obj.location = cam_pos
        cam_obj.rotation_euler = (look_target - cam_pos).to_track_quat("-Z", "Y").to_euler()
        out_p = output_dir / f"mannequin_{v_name}.png"
        scene.render.filepath = str(out_p)
        bpy.ops.render.render(write_still=True)
        panel_paths.append(out_p)

    panels_np = []
    for p in panel_paths:
        img = bpy.data.images.load(str(p))
        w, h = img.size
        arr = np.empty((h, w, 4), dtype=np.float32)
        img.pixels.foreach_get(arr.ravel())
        bpy.data.images.remove(img)
        panels_np.append(arr)

    combined = np.concatenate(panels_np, axis=1)
    comb_h, comb_w = combined.shape[:2]
    comb_img = bpy.data.images.new("Mannequin_Turnaround", width=comb_w, height=comb_h, alpha=False)
    comb_img.pixels.foreach_set(combined.ravel())
    sheet_path = output_dir / "mannequin_turnaround_preview.png"
    comb_img.filepath_raw = str(sheet_path)
    comb_img.file_format = "PNG"
    comb_img.save()
    bpy.data.images.remove(comb_img)

    scene.camera = None
    for obj in temp_objs:
        bpy.data.objects.remove(obj, do_unlink=True)
    for ldata in temp_lights:
        bpy.data.lights.remove(ldata)
    bpy.data.cameras.remove(cam_data)
    scene.world = None
    bpy.data.worlds.remove(world)

    print(f"[Blender] Saved 3-view turnaround preview to: {sheet_path}")
    return sheet_path


def generate_mannequin(output_dir: Path) -> Path:
    clean_scene()
    output_dir.mkdir(parents=True, exist_ok=True)

    alb_img, rough_img, norm_img = _generate_mannequin_grid_textures(output_dir)
    mat_grid = create_pbr_material(
        name="Mat_Mannequin_Grid",
        base_color=(0.28, 0.50, 0.74, 1.0),
        metallic=0.0,
        roughness=0.38,
        base_color_image=alb_img,
        roughness_image=rough_img,
        normal_image=norm_img,
        normal_strength=0.40,
    )

    mesh_obj, arm_obj = build_mannequin_mesh_and_rig(mat_grid)

    z_vals = [v.co.z for v in mesh_obj.data.vertices]
    total_tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
    print(
        f"[Blender] Skinned mesh '{mesh_obj.name}' + '{arm_obj.name}': {total_tris} tris, "
        f"{len(arm_obj.data.bones)} bones, Z bounds = [{min(z_vals):.4f}m, {max(z_vals):.4f}m]"
    )

    render_turnaround_previews(output_dir)

    glb_path = output_dir / "mannequin.glb"
    export_godot_glb(
        filepath=glb_path,
        export_animations=True,
        apply_modifiers=False,
        save_blend=True,
    )
    return glb_path


def main() -> None:
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        assets_dir = sdk_root / "assets" / "models" / "mannequin"
        generate_mannequin(assets_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
