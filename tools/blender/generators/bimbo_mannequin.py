"""Generator for the 2.00m Articulated Bimbo Mannequin (Rigged Ragdoll Model).

Produces:
- Articulated 17-segment ball-jointed hourglass mannequin mesh ('Mannequin_Mesh') at exact 2.00m
  height calibrated directly from orthographic pixel measurements of the reference turnaround sheet:
  full-proportioned ribcage & torso depth, dedicated pole-free sculpted teardrop breast shells with
  deep cleavage and overhanging lower curve, cinched waist, wide curved hips, dedicated sculpted
  spherical gluteal cheek domes overhanging the upper hamstring fold, and lush curvy thighs.
- Procedural Blue UV-Checker Grid PBR material ('Mat_Bimbo_Mannequin_Grid') with two-tone
  slate/cerulean checker squares, sub-grid crosshairs, and dark joint-socket crevice shading.
- 17-bone Armature ('Mannequin_Armature') with 100% rigid per-shell vertex group skinning for
  drop-in compatibility with Godot's MannequinRagdoll PhysicalBoneSimulator3D controller.
- Multi-angle studio turnaround preview render (Front, Side, Back) for visual QA.
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
# Calibrated from pixel measurements of the Front / Side / Back reference sheet.
# ---------------------------------------------------------------------------

JOINTS: dict[str, mathutils.Vector] = {
    "PelvisBase": mathutils.Vector((0.0, 0.004, 0.940)),
    "WaistLower": mathutils.Vector((0.0, -0.016, 1.180)),
    "WaistUpper": mathutils.Vector((0.0, -0.018, 1.330)),
    "NeckBase": mathutils.Vector((0.0, 0.028, 1.648)),
    "HeadBase": mathutils.Vector((0.0, 0.018, 1.730)),
    "HeadTop": mathutils.Vector((0.0, 0.006, 2.000)),
    # Left Arm (+X in Blender)
    "Shoulder.L": mathutils.Vector((0.194, 0.022, 1.568)),
    "Elbow.L": mathutils.Vector((0.376, 0.032, 1.348)),
    "Wrist.L": mathutils.Vector((0.554, 0.006, 1.112)),
    "HandTip.L": mathutils.Vector((0.652, -0.022, 0.955)),
    # Right Arm (-X in Blender)
    "Shoulder.R": mathutils.Vector((-0.194, 0.022, 1.568)),
    "Elbow.R": mathutils.Vector((-0.376, 0.032, 1.348)),
    "Wrist.R": mathutils.Vector((-0.554, 0.006, 1.112)),
    "HandTip.R": mathutils.Vector((-0.652, -0.022, 0.955)),
    # Left Leg (+X in Blender)
    "Hip.L": mathutils.Vector((0.120, 0.004, 0.975)),
    "Knee.L": mathutils.Vector((0.106, 0.012, 0.505)),
    "Ankle.L": mathutils.Vector((0.104, 0.014, 0.102)),
    "Heel.L": mathutils.Vector((0.102, 0.080, 0.014)),
    "Toe.L": mathutils.Vector((0.118, -0.175, 0.014)),
    # Right Leg (-X in Blender)
    "Hip.R": mathutils.Vector((-0.120, 0.004, 0.975)),
    "Knee.R": mathutils.Vector((-0.106, 0.012, 0.505)),
    "Ankle.R": mathutils.Vector((-0.104, 0.014, 0.102)),
    "Heel.R": mathutils.Vector((-0.102, 0.080, 0.014)),
    "Toe.R": mathutils.Vector((-0.118, -0.175, 0.014)),
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


def _piecewise_hermite(t: float, pts: list[tuple[float, float]]) -> float:
    """Smooth piecewise-cubic interpolation over sorted (t, value) control points."""
    if t <= pts[0][0]:
        return pts[0][1]
    if t >= pts[-1][0]:
        return pts[-1][1]
    for i in range(len(pts) - 1):
        t0, v0 = pts[i]
        t1, v1 = pts[i + 1]
        if t0 <= t <= t1:
            u = (t - t0) / max(1e-6, t1 - t0)
            s = u * u * (3.0 - 2.0 * u)
            return v0 + (v1 - v0) * s
    return pts[-1][1]


def _wrap_angle(ang: float) -> float:
    """Wrap angle in radians into [-pi, pi]."""
    return ((ang + math.pi) % math.tau) - math.pi


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
    """Synthesize two-tone slate/cerulean UV checker grid with dark joint-seam strip."""
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

    c_light = np.array([0.095, 0.252, 0.520], dtype=np.float32)
    c_dark = np.array([0.062, 0.172, 0.390], dtype=np.float32)
    c_line = np.array([0.185, 0.410, 0.710], dtype=np.float32)
    c_sub = np.array([0.125, 0.305, 0.580], dtype=np.float32)
    c_seam = np.array([0.012, 0.028, 0.058], dtype=np.float32)

    albedo = np.zeros((res, res, 4), dtype=np.float32)
    albedo[..., 3] = 1.0
    for ch in range(3):
        albedo[..., ch] = np.where(checker == 0, c_light[ch], c_dark[ch])

    dist_major = np.minimum(np.minimum(fu, 1.0 - fu), np.minimum(fv, 1.0 - fv))
    major_mask = np.clip(1.0 - dist_major / 0.022, 0.0, 1.0)

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

    seam_blend = np.clip((v_grid - 0.935) / 0.015, 0.0, 1.0)
    for ch in range(3):
        albedo[..., ch] = albedo[..., ch] * (1.0 - seam_blend) + c_seam[ch] * seam_blend

    rough = np.where(checker == 0, 0.38, 0.42).astype(np.float32)
    rough = rough * (1.0 - seam_blend) + 0.55 * seam_blend
    rough_rgba = np.stack([rough, rough, rough, np.ones_like(rough)], axis=-1)

    height = -0.05 * major_mask - 0.02 * sub_grid_mask - 0.22 * seam_blend
    normal_rgba = _height_to_normal_rgba(height, strength=0.40)

    img_albedo = _save_np_image("bimbo_mannequin_grid_albedo", albedo, output_dir, is_data=False)
    img_rough = _save_np_image("bimbo_mannequin_grid_roughness", rough_rgba, output_dir, is_data=True)
    img_norm = _save_np_image("bimbo_mannequin_grid_normal", normal_rgba, output_dir, is_data=True)
    return img_albedo, img_rough, img_norm


# ---------------------------------------------------------------------------
# Parametric Quad-Grid Shell & Ball-Joint Builders (Uniform 1:1 Square UVs)
# ---------------------------------------------------------------------------

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
    u_offset: float = 0.25,
) -> None:
    """Loft a smooth watertight quad-grid shell with uniform 1:1 metric square UVs."""
    expanded_frames: list[
        tuple[mathutils.Vector, mathutils.Vector, mathutils.Vector, float, float, float, bool]
    ] = []
    n_raw = len(frames)

    for idx, (c, ax_x, ax_y, rx, ry) in enumerate(frames):
        s_frac = idx / max(1, n_raw - 1)
        is_inner_cup = (idx == 0 and seam_start) or (idx == n_raw - 1 and seam_end)
        expanded_frames.append((c, ax_x, ax_y, rx, ry, s_frac, is_inner_cup))
        if idx == 0 and seam_start and n_raw >= 2:
            c1, _, _, rx1, ry1 = frames[1]
            s1 = 1.0 / max(1, n_raw - 1)
            expanded_frames.append(
                (
                    c.lerp(c1, 0.85),
                    ax_x,
                    ax_y,
                    rx + (rx1 - rx) * 0.85,
                    ry + (ry1 - ry) * 0.85,
                    s1 * 0.85,
                    False,
                )
            )
        elif idx == n_raw - 2 and seam_end and n_raw >= 2:
            c_end, _, _, rx_e, ry_e = frames[-1]
            s_prev = (n_raw - 2) / max(1, n_raw - 1)
            expanded_frames.append(
                (
                    c.lerp(c_end, 0.15),
                    ax_x,
                    ax_y,
                    rx + (rx_e - rx) * 0.15,
                    ry + (ry_e - ry) * 0.15,
                    s_prev + (1.0 - s_prev) * 0.15,
                    False,
                )
            )

    rings: list[list[bmesh.types.BMVert]] = []
    for _, (center, ax_x, ax_y, rx, ry, s_frac, _) in enumerate(expanded_frames):
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

    # Cumulative ring arc length without mid-segment modulo wrap jumps
    ring_arcs: list[float] = [0.0]
    for idx in range(1, n_exp):
        d_c = (expanded_frames[idx][0] - expanded_frames[idx - 1][0]).length
        ring_arcs.append(ring_arcs[-1] + d_c)

    # Representative 75th-percentile perimeter so end-tapers don't distort checker square aspect
    perims = sorted(
        sum((ring[(k + 1) % num_radial].co - ring[k].co).length for k in range(num_radial))
        for ring in rings
    )
    rep_perim = perims[int(0.75 * (len(perims) - 1))] if perims else 0.5
    u_repeats = max(0.25, round((rep_perim / UV_METRIC_REPEAT) * 8.0) / 8.0)

    total_v_span = max(0.01, ring_arcs[-1] / UV_METRIC_REPEAT)
    v_scale = min(1.0, 0.80 / total_v_span)

    for idx in range(n_exp - 1):
        r0 = rings[idx]
        r1 = rings[idx + 1]
        s0 = expanded_frames[idx][5]
        s1 = expanded_frames[idx + 1][5]
        cup_face = expanded_frames[idx][6] or expanded_frames[idx + 1][6]

        v_metric_0 = 0.06 + (ring_arcs[idx] / UV_METRIC_REPEAT) * v_scale
        v_metric_1 = 0.06 + (ring_arcs[idx + 1] / UV_METRIC_REPEAT) * v_scale

        for k in range(num_radial):
            kn = (k + 1) % num_radial
            theta_mid = ((k + 0.5) / num_radial) * math.tau
            extra_seam = False
            if custom_seam_fn is not None:
                extra_seam = custom_seam_fn(0.5 * (s0 + s1), theta_mid)

            is_dark = cup_face or extra_seam
            va = 0.97 if is_dark else v_metric_0
            vb = 0.97 if is_dark else v_metric_1

            ua = (((k / num_radial) + u_offset) * u_repeats) % 1.0
            ub = ((((k + 1) / num_radial) + u_offset) * u_repeats) % 1.0
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
    """Add an articulated spherical/ellipsoidal ball joint with clean blue grid & polar collars."""
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
# Individual Articulated Bimbo Mannequin Shell Constructors (17 Bone Segments)
# ---------------------------------------------------------------------------

def _build_head_segment(bm: bmesh.types.BMesh, uv_layer: bmesh.types.BMLayerItem) -> None:
    """Build ovoid female mannequin head (z = 1.724..2.000m) matching reference proportions."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    head_slices = [
        (1.724, 0.014, 0.036, 0.040),
        (1.730, -0.004, 0.052, 0.068),
        (1.750, -0.014, 0.068, 0.094),
        (1.778, -0.012, 0.084, 0.106),
        (1.814, -0.004, 0.096, 0.118),
        (1.852, 0.002, 0.105, 0.125),
        (1.888, 0.004, 0.107, 0.127),
        (1.925, 0.006, 0.100, 0.118),
        (1.958, 0.007, 0.082, 0.098),
        (1.984, 0.007, 0.050, 0.060),
        (1.996, 0.007, 0.022, 0.026),
        (2.000, 0.007, 0.005, 0.006),
    ]

    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in head_slices
    ]

    def _head_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        z = 1.724 + s_frac * (2.000 - 1.724)
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
    """Build cylindrical articulated neck column (z = 1.644..1.732m)."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    neck_slices = [
        (1.644, 0.028, 0.045, 0.045),
        (1.648, 0.028, 0.058, 0.057),
        (1.672, 0.026, 0.056, 0.055),
        (1.700, 0.022, 0.055, 0.054),
        (1.726, 0.019, 0.056, 0.055),
        (1.731, 0.018, 0.044, 0.044),
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
    """Build unified upper torso + 2D-spherical overhanging teardrop breasts on one manifold."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # 20 slices with the breast hemisphere starting right at the lower ribcage rim (slice 1, z=1.316m)
    # so the round breasts fill the chest vertically and leave ONLY the central /\ sternum window!
    chest_slices = [
        (1.308, -0.018, 0.128, 0.092),  # 0: Recessed lower socket lip inside waist
        (1.314, -0.018, 0.146, 0.106),  # 1: Lower ribcage rim & under-bust root (t_v = 0.00)
        (1.326, -0.016, 0.149, 0.108),  # 2: Under-bust overhang tuck (t_v = 0.05)
        (1.342, -0.014, 0.152, 0.110),  # 3: Lower breast pole (t_v = 0.12 -> hangs to z=1.312m!)
        (1.360, -0.011, 0.155, 0.112),  # 4: Lower-front breast cup (t_v = 0.20)
        (1.380, -0.008, 0.158, 0.114),  # 5: Lower-mid breast swell (t_v = 0.28)
        (1.402, -0.005, 0.160, 0.116),  # 6: Sub-apex fullness (t_v = 0.37)
        (1.425, -0.002, 0.163, 0.118),  # 7: Breast apex center (t_v = 0.46)
        (1.448,  0.002, 0.165, 0.119),  # 8: Supra-apex fullness (t_v = 0.56)
        (1.472,  0.005, 0.167, 0.120),  # 9: Upper-mid breast curve (t_v = 0.66)
        (1.496,  0.009, 0.169, 0.120),  # 10: Upper breast roundness (t_v = 0.76)
        (1.520,  0.013, 0.171, 0.118),  # 11: Upper pectoral curve (t_v = 0.86)
        (1.544,  0.016, 0.172, 0.115),  # 12: Sub-clavicular blend (t_v = 0.95)
        (1.564,  0.019, 0.171, 0.111),  # 13: Shoulder socket lower (t_v = 1.00)
        (1.584,  0.022, 0.168, 0.106),  # 14: Shoulder socket upper
        (1.610,  0.024, 0.160, 0.095),  # 15: Clavicle / acromion rim
        (1.636,  0.027, 0.114, 0.074),  # 16: Trapezius slope
        (1.648,  0.028, 0.064, 0.060),  # 17: Neck socket collar rim
        (1.645,  0.028, 0.048, 0.046),  # 18: Recessed inner neck socket lip
    ]

    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in chest_slices
    ]

    n_slices = len(chest_slices) - 1
    s_bust_start = 1.0 / n_slices
    s_bust_end = 13.0 / n_slices

    def _chest_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        idx_f = s_frac * n_slices
        i0 = int(min(n_slices - 1, max(0, math.floor(idx_f))))
        frac = idx_f - i0
        z = chest_slices[i0][0] * (1.0 - frac) + chest_slices[i0 + 1][0] * frac

        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        # 1. Arched lower ribcage cut (+3.2cm arch in front center, revealing /\ sternum window!)
        if s_frac < 0.20:
            arch_env = 1.0 - (s_frac / 0.20)
            if sin_t < 0.0:
                dz += 0.032 * arch_env * ((-sin_t) ** 1.2) * math.exp(-((cos_t / 0.55) ** 2))
            else:
                dz += 0.022 * arch_env * (sin_t**1.2) * math.exp(-((cos_t / 0.68) ** 2))

        # 2. Metric-Z Teardrop-Sphere Breasts (true 1:1 circular U-cup in Front & teardrop in Side!)
        if 1.312 <= z <= 1.568:
            phi_f = _wrap_angle(theta + 0.5 * math.pi)
            abs_phi = abs(phi_f)
            side_sign = 1.0 if phi_f >= 0.0 else -1.0

            # True metric Z center at z_c = 1.416m (rz_dn = 0.098m -> z=1.318m, rz_up = 0.148m -> z=1.564m)
            # Because dz_n is in true meters, the lower contour dx^2 + dz_n^2 = 1 is a TRUE 1:1
            # semi-circular U-cup (9.8cm deep!) opening a clean /\ sternum window between the breasts!
            phi_c = 0.58
            z_c = 1.416
            dx = (abs_phi - phi_c) / (0.56 if abs_phi < phi_c else 1.02)
            dz_n = (z - z_c) / (0.148 if z >= z_c else 0.098)
            r2 = dx * dx + dz_n * dz_n

            if r2 < 1.0:
                rim_fillet = _smoothstep(1.0, 0.90, r2)
                # Natural teardrop exponent: plump 0.45 hemisphere on lower cup (dz_n <= 0),
                # smoothly tapering to 0.88 on upper slope (dz_n > 0) so top isn't a balloon shelf!
                up_frac = max(0.0, dz_n)
                exp_p = 0.45 + 0.45 * (up_frac ** 0.80)
                h_teardrop = (max(0.0, 1.0 - r2) ** exp_p) * rim_fillet

                # Forward projection (-Y): reaches y_front = -0.240m at z=1.416m
                dly -= 0.128 * h_teardrop

                # Strong lateral outward bulge so outer breast reaches x = +-0.216m
                outer_boost = _smoothstep(-0.25, 0.55, dx)
                dlx += side_sign * (0.046 + 0.036 * outer_boost) * h_teardrop

                # Inward cleavage swell so left & right spheres kiss along x=0 above z=1.385m
                if dx < 0.0 and dz_n > -0.35:
                    dlx -= side_sign * 0.020 * (-dx) * h_teardrop * _smoothstep(-0.35, -0.05, dz_n)

                # Overhanging lower belly droop (peaks on lower cup, zero at upper chest)
                low_w = _smoothstep(0.35, -0.65, dz_n)
                dz -= 0.028 * (h_teardrop ** 0.75) * low_w

            # Deep crisp vertical cleavage crease right at sternum x = 0 (z = 1.38..1.52m)
            if abs_phi < 0.14 and 1.375 < z < 1.535:
                cleft_w = math.exp(-((abs_phi / 0.045) ** 2))
                cleft_env = math.sin(((z - 1.375) / 0.160) * math.pi) ** 0.75
                dly += 0.026 * cleft_w * cleft_env

        # 3. Concave shoulder socket cutouts on left/right (z in 1.49..1.63)
        if 1.49 < z < 1.635 and abs(cos_t) > 0.68:
            lat_env = ((abs(cos_t) - 0.68) / 0.32) ** 1.3
            z_env = math.exp(-(((z - 1.568) / 0.052) ** 2))
            dlx -= (0.022 if cos_t > 0 else -0.022) * lat_env * z_env

        # 4. Sculpted back scapular contour & dorsal spine groove (sin_t > 0)
        if 1.34 < z < 1.62 and sin_t > 0.0:
            bw = sin_t
            back_z = math.sin(((z - 1.34) / 0.28) * math.pi)
            scapula = math.exp(-(((abs(cos_t) - 0.46) / 0.34) ** 2))
            spine = math.exp(-((cos_t / 0.15) ** 2))
            dly += (0.016 * scapula - 0.010 * spine) * back_z * (bw**1.4)

        return dlx, dly, dz

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=64,
        cap_start=True,
        cap_end=True,
        shape_fn=_chest_shape,
        seam_start=True,
        seam_end=True,
    )


def _build_waist_segment(bm: bmesh.types.BMesh, uv_layer: bmesh.types.BMLayerItem) -> None:
    """Build hourglass mid-torso / waist shell (z = 1.176..1.345m) matching pixel-measured width & depth."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Calibrated from reference scan: narrowest waist at z=1.260 has rx=0.119m, ry=0.101m (yc=-0.025m)
    waist_slices = [
        (1.176, -0.016, 0.142, 0.096),  # Recessed lower lip inside pelvis
        (1.180, -0.016, 0.158, 0.108),  # Lower waist rim (100% flush with Pelvis top rim!)
        (1.215, -0.021, 0.134, 0.104),  # Lower waist hourglass flare
        (1.245, -0.025, 0.120, 0.101),  # Lower-mid waist pinch
        (1.268, -0.025, 0.119, 0.101),  # Narrowest waist pinch (rx=0.119m, ry=0.101m)
        (1.292, -0.022, 0.128, 0.103),  # Upper waist flare
        (1.312, -0.018, 0.145, 0.105),  # Upper waist rim entering chest arch (flush with Chest!)
        (1.338, -0.018, 0.124, 0.090),  # Recessed upper dome inside chest shell
    ]

    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in waist_slices
    ]

    def _waist_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        # Follow downward curve of lower navel/iliac seam in front & back
        if s_frac < 0.28 and sin_t < 0.0:
            bot_env = (1.0 - s_frac / 0.28) * ((-sin_t) ** 1.1)
            dz -= 0.014 * bot_env * math.exp(-((cos_t / 0.65) ** 2))

        # Follow upward arch of ribcage seam in front & back
        if s_frac > 0.70:
            top_env = (s_frac - 0.70) / 0.30
            if sin_t < 0.0:
                dz += 0.026 * top_env * ((-sin_t) ** 1.2) * math.exp(-((cos_t / 0.68) ** 2))
            else:
                dz += 0.018 * top_env * (sin_t**1.2) * math.exp(-((cos_t / 0.68) ** 2))

        if abs(cos_t) < 0.25:
            mid_groove = math.exp(-((cos_t / 0.15) ** 2)) * math.sin(s_frac * math.pi)
            if sin_t < 0.0:
                dly += 0.004 * mid_groove * (-sin_t)
            else:
                dly -= 0.008 * mid_groove * sin_t

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
    """Build unified hourglass pelvic shell: front bikini V-cut + full wide hanging back glutes."""
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Notice: we keep base rx wider on the lower slices and narrow ONLY the front (sin_t < 0) into
    # the bikini V-brief, so the back (sin_t > 0) has full width all the way down to z=0.896m for
    # two huge, round, spherical butt cheeks that completely cover the hip joints from behind!
    pelvis_slices = [
        (0.932,  0.004, 0.040, 0.056),  # 0: Recessed bottom socket rim (tucked up at z=0.932m!)
        (0.922,  0.008, 0.175, 0.096),  # 1: Lower gluteal fold / crotch base
        (0.938,  0.008, 0.206, 0.112),  # 2: Lower-bottom glute cheek overhang
        (0.960,  0.006, 0.218, 0.120),  # 3: Lower rounded glute cheek
        (0.985,  0.004, 0.222, 0.124),  # 4: Sub-apex glute cheek
        (1.012,  0.002, 0.222, 0.126),  # 5: Glute apex center
        (1.040,  0.000, 0.220, 0.126),  # 6: Outer hip crest max width
        (1.074, -0.003, 0.212, 0.124),  # 7: Upper-mid glute shelf
        (1.112, -0.007, 0.198, 0.120),  # 8: Upper glute slope
        (1.148, -0.012, 0.178, 0.114),  # 9: Upper iliac hip curve
        (1.178, -0.016, 0.158, 0.108),  # 10: Top pelvic rim (100% flush with Waist lower rim!)
        (1.183, -0.016, 0.142, 0.096),  # 11: Recessed inner waist socket collar
    ]

    frames = [
        (mathutils.Vector((0.0, yc, z)), ax_x, ax_y, rx, ry)
        for z, yc, rx, ry in pelvis_slices
    ]

    n_slices = len(pelvis_slices) - 1

    def _pelvis_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        idx_f = s_frac * n_slices
        i0 = int(min(n_slices - 1, max(0, math.floor(idx_f))))
        frac = idx_f - i0
        z = pelvis_slices[i0][0] * (1.0 - frac) + pelvis_slices[i0 + 1][0] * frac

        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        # 1. Match gently dipped front & back waist seam at top of pelvis (z=1.18m)
        if s_frac > 0.78:
            top_env = (s_frac - 0.78) / 0.22
            if sin_t < 0.0:
                dz -= 0.014 * top_env * ((-sin_t) ** 1.1) * math.exp(-((cos_t / 0.65) ** 2))
            else:
                dz -= 0.012 * top_env * (sin_t ** 1.1) * math.exp(-((cos_t / 0.65) ** 2))

        # 2. Front-only high-cut bikini V-brief: pinch front width toward crotch & lift lateral front rim
        if s_frac < 0.56 and sin_t < 0.08:
            fw = max(0.0, (-sin_t + 0.08) / 1.08) ** 1.15
            bot_env = 1.0 - (s_frac / 0.56)
            dlx -= lx * 0.74 * (bot_env ** 1.05) * (max(0.0, -sin_t) ** 0.80)
            if abs(cos_t) > 0.14:
                lat = (abs(cos_t) - 0.14) / 0.86
                dz += 0.096 * bot_env * (lat ** 1.05) * fw

        # 3. Metric-Z Spherical Gluteal Cheek Hemispheres (round top shelf + U-bottom, zero crotch peek!)
        if s_frac >= (1.0 / n_slices) and sin_t > -0.15:
            phi_b = _wrap_angle(theta - 0.5 * math.pi)
            abs_phi = abs(phi_b)
            side_sign = 1.0 if phi_b >= 0.0 else -1.0

            # True metric Z center at z_c = 1.022m (rz_dn = 0.104m -> z=0.918m, rz_up = 0.148m -> z=1.170m)
            phi_c = 0.54
            z_c = 1.022
            dx = (abs_phi - phi_c) / (0.52 if abs_phi < phi_c else 0.96)
            dz_n = (z - z_c) / (0.148 if z >= z_c else 0.104)
            r2 = dx * dx + dt * dt if False else dx * dx + dz_n * dz_n

            if r2 < 1.0:
                rim_fillet = _smoothstep(1.0, 0.90, r2)
                top_fillet = 1.0 - 0.15 * _smoothstep(0.78, 1.00, dz_n)
                h_sphere = (max(0.0, 1.0 - r2) ** 0.45) * rim_fillet * top_fillet

                # High, round spherical rear projection (+Y) across both upper & lower butt cheek!
                dly += 0.082 * h_sphere

                # Lateral roundness on lower-outer cheek so the butt has a wide peach silhouette
                dlx += side_sign * (0.022 * h_sphere * _smoothstep(0.4, -0.7, dz_n) + 0.012 * max(-0.2, dx) * h_sphere)
                if dx < 0.0:
                    dlx -= side_sign * 0.016 * (-dx) * h_sphere

                # Overhanging lower gluteal fold down to z = 0.896m!
                low_w = _smoothstep(0.35, -0.65, dz_n)
                dz -= 0.028 * (h_sphere ** 0.78) * low_w

            # Deep crisp vertical intergluteal cleft right down center back (x = 0)
            if abs_phi < 0.18 and 0.920 <= z <= 1.155:
                cleft_w = math.exp(-((abs_phi / 0.050) ** 2))
                cleft_env = math.sin(((z - 0.920) / 0.235) * math.pi) ** 0.58
                dly -= 0.056 * cleft_w * cleft_env

        # 4. Smooth mons pubis / lower belly contour in front
        if 0.10 < s_frac < 0.88 and sin_t < 0.0:
            fw = -sin_t
            front_z = math.sin(((s_frac - 0.10) / 0.78) * math.pi)
            dly -= 0.012 * front_z * math.exp(-((cos_t / 0.58) ** 2)) * (fw**1.3)

        return dlx, dly, dz

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=64,
        cap_start=True,
        cap_end=True,
        shape_fn=_pelvis_shape,
        seam_start=True,
        seam_end=True,
    )


def _build_limb_basis(
    axis_dir: mathutils.Vector,
) -> tuple[mathutils.Vector, mathutils.Vector, mathutils.Vector]:
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
        (0.145, 0.037, 0.037),
        (0.155, 0.049, 0.047),
        (0.320, 0.047, 0.045),
        (0.550, 0.044, 0.042),
        (0.760, 0.040, 0.039),
        (0.865, 0.039, 0.038),
        (0.878, 0.030, 0.030),
    ]
    frames = [(sh + w * (s * length), ax_x, ax_y, rx, ry) for s, rx, ry in samples]
    _build_lofted_shell(bm, uv_layer, frames, num_radial=32, cap_start=True, cap_end=True)


def _build_lower_arm_segment(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    side: int,
) -> None:
    """Build spherical elbow ball joint + tapered forearm shell."""
    suf = "L" if side > 0 else "R"
    el = JOINTS[f"Elbow.{suf}"]
    wr = JOINTS[f"Wrist.{suf}"]
    vec = wr - el
    length = vec.length
    ax_x, ax_y, w = _build_limb_basis(vec)

    _add_ball_joint(bm, uv_layer, el, radii=(0.041, 0.040, 0.041), axis_z=w, num_radial=28, num_lat=12)

    samples = [
        (0.120, 0.030, 0.030),
        (0.132, 0.040, 0.039),
        (0.280, 0.042, 0.040),
        (0.520, 0.037, 0.035),
        (0.760, 0.031, 0.028),
        (0.885, 0.028, 0.025),
        (0.900, 0.020, 0.018),
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

    _add_ball_joint(bm, uv_layer, wr, radii=(0.026, 0.024, 0.025), axis_z=w, num_radial=24, num_lat=10)

    palm_len = length * 0.52
    palm_samples = [
        (0.17, 0.020, 0.014),
        (0.20, 0.028, 0.017),
        (0.55, 0.036, 0.016),
        (0.92, 0.039, 0.015),
        (1.00, 0.032, 0.010),
    ]
    palm_frames = [
        (wr + w * (s * palm_len), u_fwd, v_thick, rx, ry)
        for s, rx, ry in palm_samples
    ]
    _build_lofted_shell(bm, uv_layer, palm_frames, num_radial=28, cap_start=True, cap_end=True)

    knuckle_base = wr + w * (palm_len * 0.94)
    finger_specs = [
        (0.026, 0.92, 0.0078),
        (0.009, 1.00, 0.0082),
        (-0.009, 0.94, 0.0076),
        (-0.027, 0.78, 0.0066),
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
            bm,
            uv_layer,
            f_frames,
            num_radial=14,
            cap_start=True,
            cap_end=True,
            seam_start=True,
            seam_end=False,
        )

    thumb_base = wr + w * (palm_len * 0.36) + u_fwd * 0.029 - v_thick * 0.006
    thumb_dir = (w * 0.76 + u_fwd * 0.58 - v_thick * 0.28).normalized()
    thumb_len = length * 0.36
    t_samples = [
        (0.00, 0.0090),
        (0.15, 0.0108),
        (0.50, 0.0096),
        (0.55, 0.0084),
        (0.88, 0.0078),
        (1.00, 0.0040),
    ]
    t_frames = [
        (thumb_base + thumb_dir * (s_t * thumb_len), u_fwd, v_thick, r_t, r_t * 0.92)
        for s_t, r_t in t_samples
    ]
    _build_lofted_shell(
        bm,
        uv_layer,
        t_frames,
        num_radial=14,
        cap_start=True,
        cap_end=True,
        seam_start=True,
        seam_end=False,
    )


def _build_upper_leg_segment(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    side: int,
) -> None:
    """Build hip ball joint + pixel-calibrated curvy thigh shell tucked under back glutes."""
    suf = "L" if side > 0 else "R"
    hip = JOINTS[f"Hip.{suf}"]
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Shift internal hip ball slightly forward (-Y) so it sits cleanly inside the front bikini V-socket
    hip_ball_pos = hip + mathutils.Vector((0.0, -0.014, 0.0))
    _add_ball_joint(bm, uv_layer, hip_ball_pos, radii=(0.060, 0.058, 0.060), num_radial=28, num_lat=12)

    # Calibrated from reference scan: knee ball at z=0.505m, wide upper thigh (outer x = +-0.226m)
    thigh_slices = [
        (0.546, 0.012, 0.106, 0.040, 0.042),  # Recessed distal knee socket lip
        (0.550, 0.012, 0.106, 0.052, 0.054),  # Distal thigh rim above knee ball
        (0.610, 0.010, 0.108, 0.060, 0.064),  # Lower thigh taper
        (0.685, 0.008, 0.111, 0.072, 0.078),  # Lower-mid thigh
        (0.770, 0.006, 0.116, 0.086, 0.094),  # Mid quadriceps/hamstring belly
        (0.855, 0.005, 0.120, 0.100, 0.108),  # Upper-mid thigh swell (outer x=+-0.220)
        (0.920, 0.004, 0.122, 0.104, 0.114),  # Upper thigh max fullness (outer x=+-0.226!)
        (0.968, 0.004, 0.120, 0.100, 0.108),  # Diagonal hip V-socket rim (flush with pelvis!)
        (0.972, 0.004, 0.120, 0.082, 0.088),  # Recessed inner hip socket lip
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

        # 1. Diagonal top rim matching the pelvis bikini hip arch in front (z=0.92..1.03m)
        # while dropping DOWN in back (z=0.90m) so the thigh tucks cleanly under the round butt cheeks!
        if s_frac > 0.58:
            top_env = (s_frac - 0.58) / 0.42
            if sin_t <= 0.0:
                dz += 0.060 * top_env * outward
            else:
                back_w = sin_t ** 1.15
                dz += (0.048 * (1.0 - 0.65 * back_w) * outward - 0.062 * back_w) * top_env

        # 2. Concave semi-circular cutout at bottom rim around knee ball
        if s_frac < 0.16:
            bot_env = 1.0 - (s_frac / 0.16)
            dz -= 0.009 * bot_env * (abs(cos_t) ** 1.4)

        # 3. Voluptuous outer-thigh sweep & clean inner-thigh clearance gap
        mid_bell = math.sin(s_frac * math.pi)
        if sin_t < 0.0:
            dly -= 0.010 * mid_bell * ((-sin_t) ** 1.3)
        if outward > 0.0:
            dlx += (0.008 * side) * mid_bell * (outward**1.2)
        elif outward < 0.0 and s_frac > 0.40:
            inward = -outward
            dlx += (0.008 * side) * (inward**1.4) * _smoothstep(0.40, 0.88, s_frac)

        return dlx, dly, dz

    _build_lofted_shell(
        bm,
        uv_layer,
        frames,
        num_radial=44,
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
    """Build prominent spherical knee ball joint (z = 0.505m) + sculpted calf/shin shell."""
    suf = "L" if side > 0 else "R"
    knee = JOINTS[f"Knee.{suf}"]
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    _add_ball_joint(bm, uv_layer, knee, radii=(0.052, 0.052, 0.050), num_radial=32, num_lat=14)

    calf_slices = [
        (0.135, 0.014, 0.104, 0.030, 0.032),
        (0.139, 0.014, 0.104, 0.040, 0.042),
        (0.195, 0.018, 0.105, 0.042, 0.045),
        (0.268, 0.022, 0.107, 0.050, 0.054),
        (0.342, 0.028, 0.109, 0.058, 0.063),
        (0.398, 0.030, 0.110, 0.060, 0.065),
        (0.444, 0.022, 0.108, 0.055, 0.057),
        (0.460, 0.016, 0.106, 0.051, 0.052),
        (0.464, 0.016, 0.106, 0.039, 0.040),
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
            dly += 0.011 * calf_env * (sin_t**1.4)
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
        (0.00, 0.024, 0.070, 0.004, False),
        (0.10, 0.039, 0.090, 0.000, False),
        (0.28, 0.042, 0.094, 0.000, False),
        (0.48, 0.042, 0.074, 0.000, False),
        (0.66, 0.045, 0.054, 0.000, False),
        (0.68, 0.042, 0.048, 0.001, True),
        (0.70, 0.046, 0.051, 0.000, False),
        (0.86, 0.044, 0.040, 0.000, False),
        (0.95, 0.035, 0.028, 0.002, False),
        (1.00, 0.016, 0.015, 0.005, False),
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

def build_mannequin_mesh_and_rig(
    mat_grid: bpy.types.Material,
) -> tuple[bpy.types.Object, bpy.types.Object]:
    """Build all 17 articulated mannequin segments, assign rigid weights, and bind Armature."""
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
        add_bone(
            arm_obj,
            f"UpperArm.{suf}",
            JOINTS[f"Shoulder.{suf}"],
            JOINTS[f"Elbow.{suf}"],
            parent_name="Chest",
        )
        add_bone(
            arm_obj,
            f"LowerArm.{suf}",
            JOINTS[f"Elbow.{suf}"],
            JOINTS[f"Wrist.{suf}"],
            parent_name=f"UpperArm.{suf}",
        )
        add_bone(
            arm_obj,
            f"Hand.{suf}",
            JOINTS[f"Wrist.{suf}"],
            JOINTS[f"HandTip.{suf}"],
            parent_name=f"LowerArm.{suf}",
        )

    for suf in ("L", "R"):
        add_bone(
            arm_obj,
            f"UpperLeg.{suf}",
            JOINTS[f"Hip.{suf}"],
            JOINTS[f"Knee.{suf}"],
            parent_name="Pelvis",
        )
        add_bone(
            arm_obj,
            f"LowerLeg.{suf}",
            JOINTS[f"Knee.{suf}"],
            JOINTS[f"Ankle.{suf}"],
            parent_name=f"UpperLeg.{suf}",
        )
        add_bone(
            arm_obj,
            f"Foot.{suf}",
            JOINTS[f"Ankle.{suf}"],
            JOINTS[f"Toe.{suf}"],
            parent_name=f"LowerLeg.{suf}",
        )

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
        out_p = output_dir / f"bimbo_mannequin_{v_name}.png"
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
    comb_img = bpy.data.images.new(
        "Bimbo_Mannequin_Turnaround", width=comb_w, height=comb_h, alpha=False
    )
    comb_img.pixels.foreach_set(combined.ravel())
    sheet_path = output_dir / "bimbo_mannequin_turnaround_preview.png"
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


def generate_bimbo_mannequin(output_dir: Path) -> Path:
    clean_scene()
    output_dir.mkdir(parents=True, exist_ok=True)

    alb_img, rough_img, norm_img = _generate_mannequin_grid_textures(output_dir)
    mat_grid = create_pbr_material(
        name="Mat_Bimbo_Mannequin_Grid",
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

    glb_path = output_dir / "bimbo_mannequin.glb"
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
        assets_dir = sdk_root / "assets" / "models" / "bimbo_mannequin"
        generate_bimbo_mannequin(assets_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
