"""Generator for the 2.0m Glossy Black Coverall Axe Man (Static Background Model).

Produces:
- Single unified static mesh ('axe_man') at exact 2.00m height with 2 material slots:
  1. Mat_AxeMan_LatexSuit (wrinkled glossy black rubberized coverall/hood/gloves/boots)
  2. Mat_AxeMan_Weapon (tactical fire axe with double-flared bearded blade, rear pike & ribbed haft)
- Zero bones/armatures, zero cameras, zero lights, zero collision proxies in .blend and .glb
- Multi-angle studio preview render (Front, Side Profile, Back View) for visual verification
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
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material


# ---------------------------------------------------------------------------
# 2.00m Menacing Pose Landmarks (Blender meters: -Y is Front, +Z is Up)
# Note: In Front View (looking from -Y toward +Y), -X is screen-left (character's
# right side) and +X is screen-right (character's left side).
# ---------------------------------------------------------------------------

JOINTS: dict[str, mathutils.Vector] = {
    "Root": mathutils.Vector((0.0, 0.0, 0.0)),
    "Hips": mathutils.Vector((0.0, 0.010, 0.995)),
    "Waist": mathutils.Vector((0.0, 0.005, 1.185)),
    "Chest": mathutils.Vector((0.0, 0.008, 1.485)),
    "NeckBase": mathutils.Vector((0.0, 0.004, 1.665)),
    "NeckMid": mathutils.Vector((0.0, -0.004, 1.720)),
    "HeadCenter": mathutils.Vector((0.0, -0.020, 1.855)),
    "HeadTop": mathutils.Vector((0.0, -0.006, 2.000)),
    # Right Arm (viewer's left in Front View - bent elbow, high chest grip matching Image 1 & 2)
    "Shoulder.R": mathutils.Vector((-0.232, 0.006, 1.585)),
    "Elbow.R": mathutils.Vector((-0.322, -0.018, 1.325)),
    "Wrist.R": mathutils.Vector((-0.214, -0.205, 1.445)),
    "Hand.R": mathutils.Vector((-0.192, -0.228, 1.472)),
    # Left Arm (viewer's right in Front View - wide menacing elbow, lower hip grip matching Image 1 & 2)
    "Shoulder.L": mathutils.Vector((0.232, 0.006, 1.585)),
    "Elbow.L": mathutils.Vector((0.348, -0.005, 1.305)),
    "Wrist.L": mathutils.Vector((0.220, -0.155, 1.120)),
    "Hand.L": mathutils.Vector((0.186, -0.175, 1.082)),
    # Right Leg (viewer's left in Front View - strong A-stance with clean inner-thigh V-gap)
    "Hip.R": mathutils.Vector((-0.090, 0.005, 0.975)),
    "Knee.R": mathutils.Vector((-0.136, -0.015, 0.535)),
    "Ankle.R": mathutils.Vector((-0.172, 0.015, 0.095)),
    "Heel.R": mathutils.Vector((-0.166, 0.068, 0.022)),
    "Toe.R": mathutils.Vector((-0.198, -0.185, 0.022)),
    # Left Leg (viewer's right in Front View - strong A-stance with clean inner-thigh V-gap)
    "Hip.L": mathutils.Vector((0.090, 0.005, 0.975)),
    "Knee.L": mathutils.Vector((0.136, -0.015, 0.535)),
    "Ankle.L": mathutils.Vector((0.172, 0.015, 0.095)),
    "Heel.L": mathutils.Vector((0.166, 0.068, 0.022)),
    "Toe.L": mathutils.Vector((0.198, -0.185, 0.022)),
}


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _axe_transform() -> tuple[mathutils.Vector, mathutils.Vector, mathutils.Vector, mathutils.Vector]:
    """Compute the 1.40m tactical fire-axe haft origin (pommel) and basis (u_blade, v_side, w_shaft).

    Passes cleanly through Hand.L (at s=0.35m) and Hand.R (at s=0.89m) at a ~44 deg torso diagonal.
    """
    hand_l = JOINTS["Hand.L"]
    hand_r = JOINTS["Hand.R"]

    w_shaft = (hand_r - hand_l).normalized()
    pommel_origin = hand_l - w_shaft * 0.35

    # Cutting edge direction lies primarily in the X-Z plane (facing down-left in Front View)
    # with a slight forward (-Y) pitch so the full broad blade profile reads in Front & Back views.
    blade_hint = mathutils.Vector((-0.70, -0.16, -0.69)).normalized()
    u_blade = (blade_hint - w_shaft * blade_hint.dot(w_shaft)).normalized()
    v_side = w_shaft.cross(u_blade).normalized()

    return pommel_origin, u_blade, v_side, w_shaft


# ---------------------------------------------------------------------------
# Procedural 1024x1024 PBR Texture Synthesis (Suit & Axe)
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


def _generate_suit_pbr_textures(
    output_dir: Path,
) -> tuple[bpy.types.Image, bpy.types.Image, bpy.types.Image]:
    """Synthesize dark satin-matte rubberized coverall PBR maps with subtle micro-grain."""
    output_dir.mkdir(parents=True, exist_ok=True)
    res = 1024
    v_grid, u_grid = np.mgrid[0:res, 0:res].astype(np.float32) / float(res)

    # Subtle low-frequency tension sheen variation so 3D sculpted mesh folds carry the lighting
    warp = 0.03 * np.sin(u_grid * 2.0 * math.tau) * np.cos(v_grid * 2.0 * math.tau)
    drape_a = np.sin(((u_grid + warp) * 3.0 + v_grid * 5.0) * math.tau)
    drape_b = np.cos(((u_grid - warp) * 2.0 - v_grid * 4.0) * math.tau)
    smooth_drapes = 0.55 * drape_a + 0.45 * drape_b

    base_val = np.clip(0.011 + 0.0012 * smooth_drapes, 0.008, 0.015)
    albedo = np.zeros((res, res, 4), dtype=np.float32)
    albedo[..., 0] = base_val * 0.98
    albedo[..., 1] = base_val * 0.99
    albedo[..., 2] = base_val * 1.02
    albedo[..., 3] = 1.0

    rough = np.clip(0.36 - 0.035 * smooth_drapes, 0.28, 0.44)
    rough_rgba = np.stack([rough, rough, rough, np.ones_like(rough)], axis=-1)

    height = 0.06 * smooth_drapes
    normal_rgba = _height_to_normal_rgba(height, strength=0.35)

    img_albedo = _save_np_image("axe_man_suit_albedo", albedo, output_dir, is_data=False)
    img_rough = _save_np_image("axe_man_suit_roughness", rough_rgba, output_dir, is_data=True)
    img_norm = _save_np_image("axe_man_suit_normal", normal_rgba, output_dir, is_data=True)
    return img_albedo, img_rough, img_norm


def _generate_axe_pbr_textures(
    output_dir: Path,
) -> tuple[bpy.types.Image, bpy.types.Image, bpy.types.Image]:
    """Synthesize tactical axe PBR atlas:
    - v in [0.00, 0.50]: Jet-black composite/wood haft + ribbed/spiral grip
    - v in [0.50, 0.86]: Matte black-oxide steel head cheeks
    - v in [0.86, 1.00]: Honed steel cutting bevel
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    res = 1024
    v_grid, u_grid = np.mgrid[0:res, 0:res].astype(np.float32) / float(res)

    rng = np.random.default_rng(202)
    fine = rng.standard_normal((res, res)).astype(np.float32)
    streak = np.repeat(rng.standard_normal((res, res // 16)).astype(np.float32), 16, axis=1)

    albedo = np.zeros((res, res, 4), dtype=np.float32)
    albedo[..., 3] = 1.0
    rough = np.full((res, res), 0.5, dtype=np.float32)
    height = np.zeros((res, res), dtype=np.float32)

    m_haft = v_grid < 0.50
    wood_grain = 0.4 * streak + 0.6 * np.sin((u_grid * 36.0 + v_grid * 5.0) * math.tau)
    albedo[..., 0] = np.where(m_haft, np.clip(0.015 + 0.003 * wood_grain, 0.008, 0.028), albedo[..., 0])
    albedo[..., 1] = np.where(m_haft, np.clip(0.014 + 0.003 * wood_grain, 0.008, 0.026), albedo[..., 1])
    albedo[..., 2] = np.where(m_haft, np.clip(0.014 + 0.003 * wood_grain, 0.008, 0.026), albedo[..., 2])
    rough = np.where(m_haft, np.clip(0.45 + 0.04 * wood_grain + 0.02 * fine, 0.34, 0.62), rough)
    height = np.where(m_haft, 0.08 * wood_grain + 0.02 * fine, height)

    m_head = (v_grid >= 0.50) & (v_grid < 0.86)
    albedo[..., 0] = np.where(m_head, np.clip(0.016 + 0.002 * fine, 0.008, 0.028), albedo[..., 0])
    albedo[..., 1] = np.where(m_head, np.clip(0.017 + 0.002 * fine, 0.008, 0.028), albedo[..., 1])
    albedo[..., 2] = np.where(m_head, np.clip(0.019 + 0.002 * fine, 0.010, 0.032), albedo[..., 2])
    rough = np.where(m_head, np.clip(0.28 + 0.02 * fine, 0.20, 0.36), rough)
    height = np.where(m_head, 0.02 * fine, height)

    m_edge = v_grid >= 0.86
    blend_edge = np.clip((v_grid - 0.86) / 0.04, 0.0, 1.0)
    grind = 0.6 * streak + 0.4 * fine
    edge_r = 0.016 + blend_edge * (0.34 + 0.02 * grind - 0.016)
    edge_g = 0.017 + blend_edge * (0.36 + 0.02 * grind - 0.017)
    edge_b = 0.019 + blend_edge * (0.40 + 0.02 * grind - 0.019)
    albedo[..., 0] = np.where(m_edge, np.clip(edge_r, 0.015, 0.55), albedo[..., 0])
    albedo[..., 1] = np.where(m_edge, np.clip(edge_g, 0.015, 0.58), albedo[..., 1])
    albedo[..., 2] = np.where(m_edge, np.clip(edge_b, 0.018, 0.62), albedo[..., 2])
    rough = np.where(m_edge, np.clip(0.28 - blend_edge * 0.12 + 0.015 * grind, 0.14, 0.32), rough)
    height = np.where(m_edge, 0.02 * grind, height)

    rough_rgba = np.stack([rough, rough, rough, np.ones_like(rough)], axis=-1)
    normal_rgba = _height_to_normal_rgba(height, strength=0.75)

    img_albedo = _save_np_image("axe_man_weapon_albedo", albedo, output_dir, is_data=False)
    img_rough = _save_np_image("axe_man_weapon_roughness", rough_rgba, output_dir, is_data=True)
    img_norm = _save_np_image("axe_man_weapon_normal", normal_rgba, output_dir, is_data=True)
    return img_albedo, img_rough, img_norm


# ---------------------------------------------------------------------------
# 2.00m Imposing Coverall Character Mesh Builder
# ---------------------------------------------------------------------------

def _create_bmesh_object(name: str, bm: bmesh.types.BMesh) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _add_lofted_tube(
    bm: bmesh.types.BMesh,
    frames: list[tuple[mathutils.Vector, mathutils.Vector, mathutils.Vector, float, float]],
    num_radial: int = 32,
    cap_start: bool = True,
    cap_end: bool = True,
    shape_fn=None,
) -> list[list[bmesh.types.BMVert]]:
    """Loft a watertight quad tube through oriented elliptical cross-sections."""
    rings: list[list[bmesh.types.BMVert]] = []
    n_frames = len(frames)

    for idx, (center, ax_x, ax_y, rx, ry) in enumerate(frames):
        s_frac = idx / max(1, n_frames - 1)
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

    for idx in range(n_frames - 1):
        r0 = rings[idx]
        r1 = rings[idx + 1]
        for k in range(num_radial):
            kn = (k + 1) % num_radial
            bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))

    if cap_start and rings:
        c0 = sum((v.co for v in rings[0]), mathutils.Vector()) / len(rings[0])
        v_c0 = bm.verts.new(c0)
        for k in range(num_radial):
            kn = (k + 1) % num_radial
            bm.faces.new((v_c0, rings[0][kn], rings[0][k]))

    if cap_end and rings:
        c1 = sum((v.co for v in rings[-1]), mathutils.Vector()) / len(rings[-1])
        v_c1 = bm.verts.new(c1)
        for k in range(num_radial):
            kn = (k + 1) % num_radial
            bm.faces.new((v_c1, rings[-1][k], rings[-1][kn]))

    return rings


def _build_torso_and_neck_obj() -> bpy.types.Object:
    """Build lean-hipped, broad-shouldered 2.0m coverall torso with high traps & thick short neck."""
    bm = bmesh.new()
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Lean male hips (rx=0.170) expanding into a powerful chest/lats V-taper (rx=0.232)
    # and high muscular trapezius/neck transition (short, thick, menacing predator neck)
    z_specs = [
        (0.905, 0.008, 0.038, 0.065),   # Clean V-crotch apex
        (0.950, 0.014, 0.138, 0.118),   # Lower pelvis
        (1.000, 0.015, 0.172, 0.132),   # Lean male hips (flush with outer thighs)
        (1.075, 0.008, 0.170, 0.126),   # Iliac crest / belt line
        (1.160, 0.005, 0.174, 0.126),   # Waist
        (1.250, 0.006, 0.188, 0.136),   # Lower ribcage / obliques
        (1.345, 0.008, 0.206, 0.146),   # Mid ribcage / lats flare
        (1.435, 0.010, 0.222, 0.154),   # Lower pectorals / upper back
        (1.515, 0.008, 0.232, 0.156),   # Full chest / pectoral peak
        (1.580, 0.006, 0.230, 0.144),   # High broad shoulder girdle
        (1.630, 0.005, 0.182, 0.122),   # Muscular trapezius slope
        (1.668, 0.003, 0.118, 0.098),   # Collar seam ring / thick neck base
        (1.705, 0.000, 0.086, 0.088),   # Short thick muscular neck
        (1.745, -0.005, 0.080, 0.084),  # Upper neck entering cranium
        (1.785, -0.010, 0.048, 0.050),  # Inner neck dome cap inside cranium
    ]

    frames = [
        (mathutils.Vector((0.0, y_off, z)), ax_x, ax_y, rx, ry)
        for (z, y_off, rx, ry) in z_specs
    ]

    def _torso_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        z = 0.905 + s_frac * (1.785 - 0.905)
        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        if 0.92 < z < 1.08 and sin_t > 0.0:
            glute_env = math.sin(((z - 0.92) / 0.16) * math.pi)
            cleft = math.exp(-((cos_t / 0.20) ** 2))
            cheeks = math.exp(-(((abs(cos_t) - 0.46) / 0.35) ** 2))
            dly += (0.016 * cheeks - 0.010 * cleft) * glute_env * (sin_t**1.4)

        if 1.36 < z < 1.59 and sin_t < 0.0:
            pec_z = math.sin(((z - 1.36) / 0.23) * math.pi)
            sternum = math.exp(-((cos_t / 0.18) ** 2))
            pec_lobe = math.exp(-(((abs(cos_t) - 0.46) / 0.36) ** 2))
            dly -= (0.015 * pec_lobe - 0.006 * sternum) * pec_z * ((-sin_t) ** 1.4)

        if 1.24 < z < 1.63 and sin_t > 0.0:
            back_z = math.sin(((z - 1.24) / 0.39) * math.pi)
            spine_furrow = math.exp(-((cos_t / 0.20) ** 2))
            scapula = math.exp(-(((abs(cos_t) - 0.45) / 0.36) ** 2))
            dly += (0.015 * scapula - 0.008 * spine_furrow) * back_z * (sin_t**1.5)

        return dlx, dly, dz

    _add_lofted_tube(bm, frames, num_radial=44, cap_start=True, cap_end=True, shape_fn=_torso_shape)
    return _create_bmesh_object("Part_Torso", bm)


def _build_head_obj() -> bpy.types.Object:
    """Build menacing human-proportioned masked head (z = 1.725..2.000m) with smooth taut hood."""
    bm = bmesh.new()
    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Tucked chin at z=1.725 up to z=2.000 crown with 19.6cm cranium width (rx=0.098)
    head_specs = [
        (1.725, -0.028, 0.042, 0.052),  # Submental / under-chin base
        (1.744, -0.025, 0.070, 0.090),  # Chin & jaw mandible
        (1.772, -0.020, 0.086, 0.104),  # Angular jaw gonion & lower face
        (1.805, -0.016, 0.093, 0.111),  # Cheekbones / mouth area under taut hood
        (1.838, -0.012, 0.097, 0.115),  # Nose bridge & zygomatic arch
        (1.870, -0.009, 0.098, 0.116),  # Orbital hollows / mid cranium
        (1.902, -0.007, 0.098, 0.115),  # Overhanging brow ridge / parietal width
        (1.936, -0.005, 0.091, 0.106),  # Forehead slope
        (1.968, -0.003, 0.074, 0.088),  # Upper cranium dome
        (1.990, -0.002, 0.045, 0.056),  # Skull crown
        (2.000, -0.001, 0.018, 0.022),  # Exact 2.000m skull apex
    ]

    frames = [
        (mathutils.Vector((0.0, y_c, z)), ax_x, ax_y, rx, ry)
        for (z, y_c, rx, ry) in head_specs
    ]

    def _head_mask_shape(s_frac: float, theta: float, lx: float, ly: float) -> tuple[float, float, float]:
        z = 1.735 + s_frac * (2.000 - 1.735)
        cos_t = math.cos(theta)
        sin_t = math.sin(theta)
        dlx, dly, dz = 0.0, 0.0, 0.0

        # Subtle facial plane taper toward front of mask without pinching
        if sin_t < -0.15:
            front_w = (-sin_t - 0.15) / 0.85
            chin = math.exp(-(((z - 1.758) / 0.022) ** 2)) * math.exp(-((cos_t / 0.42) ** 2)) * front_w
            nose = math.exp(-(((z - 1.838) / 0.030) ** 2)) * math.exp(-((cos_t / 0.28) ** 2)) * front_w
            brow = math.exp(-(((z - 1.895) / 0.022) ** 2)) * math.exp(-((cos_t / 0.58) ** 2)) * front_w
            eye_hollow = (
                math.exp(-(((z - 1.868) / 0.020) ** 2))
                * math.exp(-(((abs(cos_t) - 0.30) / 0.16) ** 2))
                * front_w
            )
            dly -= 0.007 * chin + 0.008 * nose + 0.009 * brow - 0.006 * eye_hollow

        return dlx, dly, dz

    _add_lofted_tube(bm, frames, num_radial=40, cap_start=True, cap_end=True, shape_fn=_head_mask_shape)
    return _create_bmesh_object("Part_Head", bm)


def _build_leg_obj(side: int) -> bpy.types.Object:
    """Build straight-cut A-stance coverall trouser leg flush with the lean 0.170m outer hip."""
    bm = bmesh.new()
    suffix = "R" if side < 0 else "L"
    hip = JOINTS[f"Hip.{suffix}"]
    knee = JOINTS[f"Knee.{suffix}"]
    ankle = JOINTS[f"Ankle.{suffix}"]

    ax_x = mathutils.Vector((1.0, 0.0, 0.0))
    ax_y = mathutils.Vector((0.0, 1.0, 0.0))

    # Hip.R/L is at x=±0.090, rx=0.083 -> outer thigh at ±0.173, flush with lean Hips (0.170),
    # and leaving a clean inverted-V inner-thigh gap from crotch down to ankles!
    leg_samples = [
        (-0.14, 0.034, 0.038),  # Inner pelvis dome apex
        (-0.07, 0.072, 0.080),  # Inside pelvis socket
        (0.00, 0.083, 0.095),   # Upper hip transition (flush with lean hip)
        (0.10, 0.084, 0.096),   # Upper thigh
        (0.24, 0.081, 0.092),   # Mid thigh
        (0.38, 0.077, 0.086),   # Lower thigh
        (0.50, 0.074, 0.082),   # Knee joint
        (0.62, 0.075, 0.083),   # Upper calf trouser hang
        (0.75, 0.072, 0.079),   # Mid shin trouser leg
        (0.86, 0.070, 0.076),   # Lower shin trouser leg
        (0.94, 0.072, 0.078),   # Stacked ankle cuff gather
        (0.98, 0.068, 0.074),   # Bottom trouser hem over boot
        (1.02, 0.048, 0.054),   # Taper inside boot
    ]

    frames = []
    for t, rx, ry in leg_samples:
        if t <= 0.0:
            u_in = -t / 0.14
            c = hip.lerp(mathutils.Vector((side * 0.064, 0.010, 1.040)), u_in)
        elif t <= 0.50:
            u = t / 0.50
            c = hip.lerp(knee, u)
        else:
            u = min(1.0, (t - 0.50) / 0.50)
            c = knee.lerp(ankle, u)
            c.y += 0.008 * math.sin(u * math.pi)
            if t > 1.0:
                c.z -= (t - 1.0) * 0.48
        frames.append((c, ax_x, ax_y, rx, ry))

    _add_lofted_tube(bm, frames, num_radial=32, cap_start=True, cap_end=True)
    return _create_bmesh_object(f"Part_Leg_{suffix}", bm)


def _build_boot_obj(side: int) -> bpy.types.Object:
    """Build heavy black combat/work boot with rounded-square tactical toe box on Z=0.0."""
    bm = bmesh.new()
    suffix = "R" if side < 0 else "L"
    heel = JOINTS[f"Heel.{suffix}"]
    toe = JOINTS[f"Toe.{suffix}"]

    foot_dir = toe - heel
    foot_dir.z = 0.0
    foot_len = foot_dir.length
    f_fwd = foot_dir.normalized()
    f_side = mathutils.Vector((f_fwd.y, -f_fwd.x, 0.0))

    boot_slices = [
        (0.00, 0.032, 0.088, 0.004),
        (0.08, 0.048, 0.105, 0.000),
        (0.28, 0.052, 0.108, 0.000),
        (0.48, 0.050, 0.088, 0.004),
        (0.68, 0.054, 0.068, 0.000),
        (0.85, 0.052, 0.058, 0.000),
        (0.95, 0.044, 0.046, 0.002),
        (1.00, 0.028, 0.030, 0.005),
    ]

    boot_rings: list[list[bmesh.types.BMVert]] = []
    n_boot_rad = 24
    for u_f, w_rx, h_top, z_bot in boot_slices:
        base_xy = heel + f_fwd * (u_f * foot_len)
        z_mid = 0.5 * (z_bot + h_top)
        h_half = 0.5 * (h_top - z_bot)
        ring: list[bmesh.types.BMVert] = []
        for k in range(n_boot_rad):
            theta = (k / n_boot_rad) * math.tau
            cos_t = math.cos(theta)
            sin_t = math.sin(theta)
            if sin_t < 0.0:
                z_pt = max(z_bot, z_mid + h_half * (sin_t * 0.65))
                welt = 0.0040 if sin_t > -0.6 else 0.0
            else:
                z_pt = z_mid + h_half * (sin_t**0.82)
                welt = 0.0
            lat = (w_rx + welt) * cos_t
            pt = mathutils.Vector((base_xy.x, base_xy.y, z_pt)) + f_side * lat
            ring.append(bm.verts.new(pt))
        boot_rings.append(ring)

    for idx in range(len(boot_rings) - 1):
        r0 = boot_rings[idx]
        r1 = boot_rings[idx + 1]
        for k in range(n_boot_rad):
            kn = (k + 1) % n_boot_rad
            bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))

    for ring_idx, flip in ((0, True), (-1, False)):
        ring = boot_rings[ring_idx]
        avg = sum((v.co for v in ring), mathutils.Vector()) / len(ring)
        vc = bm.verts.new(avg)
        for k in range(n_boot_rad):
            kn = (k + 1) % n_boot_rad
            bm.faces.new((vc, ring[kn], ring[k]) if flip else (vc, ring[k], ring[kn]))

    return _create_bmesh_object(f"Part_Boot_{suffix}", bm)


def _build_arm_and_glove_objs(side: int) -> list[bpy.types.Object]:
    """Build heavy coverall sleeve + gloved hand gripping the axe on the 2.0m figure."""
    suffix = "R" if side < 0 else "L"
    shoulder = JOINTS[f"Shoulder.{suffix}"]
    elbow = JOINTS[f"Elbow.{suffix}"]
    wrist = JOINTS[f"Wrist.{suffix}"]
    hand = JOINTS[f"Hand.{suffix}"]

    chest_anchor = mathutils.Vector((side * 0.120, 0.010, 1.565))
    clavicle_mid = mathutils.Vector((side * 0.175, 0.010, 1.592))

    # Muscular upper arm & heavy coverall sleeve radii
    arm_keyframes = [
        (chest_anchor, 0.042, 0.042),
        (clavicle_mid, 0.080, 0.076),
        (shoulder, 0.084, 0.078),
        (shoulder.lerp(elbow, 0.25), 0.076, 0.072),
        (shoulder.lerp(elbow, 0.55), 0.070, 0.067),
        (shoulder.lerp(elbow, 0.85), 0.065, 0.062),
        (elbow, 0.063, 0.060),
        (elbow.lerp(wrist, 0.22), 0.065, 0.062),
        (elbow.lerp(wrist, 0.52), 0.059, 0.056),
        (elbow.lerp(wrist, 0.82), 0.052, 0.049),
        (wrist, 0.044, 0.040),
        (wrist.lerp(hand, 0.65), 0.046, 0.030),
        (hand, 0.040, 0.025),
        (hand.lerp(wrist, -0.15), 0.018, 0.014),
    ]

    raw_pts = [kf[0].copy() for kf in arm_keyframes]
    for _ in range(2):
        smoothed_pts = [raw_pts[0]]
        for i in range(1, len(raw_pts) - 1):
            smoothed_pts.append(0.25 * raw_pts[i - 1] + 0.50 * raw_pts[i] + 0.25 * raw_pts[i + 1])
        smoothed_pts.append(raw_pts[-1])
        raw_pts = smoothed_pts

    frames = []
    prev_tang = (raw_pts[1] - raw_pts[0]).normalized()
    ax_u = prev_tang.cross(mathutils.Vector((0.0, 1.0, 0.0))).normalized()
    ax_v = prev_tang.cross(ax_u).normalized()

    for i, (_, rx, ry) in enumerate(arm_keyframes):
        if i == 0:
            tang = (raw_pts[1] - raw_pts[0]).normalized()
        elif i == len(raw_pts) - 1:
            tang = (raw_pts[-1] - raw_pts[-2]).normalized()
        else:
            tang = (raw_pts[i + 1] - raw_pts[i - 1]).normalized()

        rot_quat = prev_tang.rotation_difference(tang)
        ax_u = (rot_quat @ ax_u).normalized()
        ax_v = tang.cross(ax_u).normalized()
        prev_tang = tang
        frames.append((raw_pts[i], ax_u, ax_v, rx, ry))

    bm_arm = bmesh.new()
    _add_lofted_tube(bm_arm, frames, num_radial=32, cap_start=True, cap_end=True)
    objs = [_create_bmesh_object(f"Part_Arm_{suffix}", bm_arm)]

    _, u_blade, v_side, w_shaft = _axe_transform()
    grip_center = hand

    finger_offsets = [-0.034, -0.011, 0.011, 0.032]
    finger_radii = [0.0110, 0.0118, 0.0110, 0.0098]

    for f_idx, (f_off, f_rad) in enumerate(zip(finger_offsets, finger_radii)):
        bm_f = bmesh.new()
        base_c = grip_center + w_shaft * f_off
        f_frames = []
        angles = [-0.65 * math.pi, -0.15 * math.pi, 0.35 * math.pi, 0.80 * math.pi, 1.12 * math.pi]
        for a_idx, ang in enumerate(angles):
            r_wrap = 0.025
            pt = base_c + u_blade * (math.cos(ang) * r_wrap) + v_side * (math.sin(ang) * r_wrap)
            taper = 0.45 if a_idx in (0, len(angles) - 1) else (1.0 - 0.15 * (a_idx / 4.0))
            rad = f_rad * taper
            n_dir = (u_blade * math.cos(ang) + v_side * math.sin(ang)).normalized()
            f_frames.append((pt, w_shaft, n_dir, rad, rad * 0.92))
        _add_lofted_tube(bm_f, f_frames, num_radial=12, cap_start=True, cap_end=True)
        objs.append(_create_bmesh_object(f"Part_Finger_{suffix}_{f_idx}", bm_f))

    bm_th = bmesh.new()
    thumb_sign = 1.0 if side < 0 else -1.0
    thumb_base = grip_center + w_shaft * (0.038 * thumb_sign)
    thumb_frames = []
    t_angles = [-0.65 * math.pi, -1.05 * math.pi, -1.38 * math.pi, -1.62 * math.pi]
    for a_idx, ang in enumerate(t_angles):
        r_wrap = 0.026
        pt = thumb_base + u_blade * (math.cos(ang) * r_wrap) + v_side * (math.sin(ang) * r_wrap)
        taper = 0.50 if a_idx in (0, len(t_angles) - 1) else 0.95
        rad = 0.0125 * taper
        n_dir = (u_blade * math.cos(ang) + v_side * math.sin(ang)).normalized()
        thumb_frames.append((pt, w_shaft, n_dir, rad, rad))
    _add_lofted_tube(bm_th, thumb_frames, num_radial=12, cap_start=True, cap_end=True)
    objs.append(_create_bmesh_object(f"Part_Thumb_{suffix}", bm_th))

    return objs


def _cloth_ridge(phase: float, sharpness: float = 2.4) -> float:
    """Evaluate a sharp-crested, deep cloth fold profile in [-0.42, +0.58]."""
    s = 0.5 + 0.5 * math.sin(phase)
    return (s**sharpness) - 0.42


def _sculpt_heavy_coverall_folds(char_obj: bpy.types.Object) -> None:
    """Displace the unified 2.0m character mesh with authentic 3D coverall drapes & joint folds."""
    mesh = char_obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    shoulder_r = JOINTS["Shoulder.R"]
    shoulder_l = JOINTS["Shoulder.L"]
    elbow_r = JOINTS["Elbow.R"]
    elbow_l = JOINTS["Elbow.L"]
    wrist_r = JOINTS["Wrist.R"]
    wrist_l = JOINTS["Wrist.L"]

    for v in bm.verts:
        co = v.co
        n = v.normal
        z = co.z
        x = co.x
        y = co.y
        theta = math.atan2(y, x)
        disp = 0.0

        # 1. Subtle Front Neck / Collar Seam (front-biased, zero back-neck ring artifact)
        if 1.63 < z < 1.71 and y < 0.0:
            collar_env = math.exp(-(((z - 1.668) / 0.016) ** 2)) * (-y / 0.09)
            disp += 0.0038 * collar_env * _cloth_ridge((z - 1.668) / 0.024 * math.tau, 2.0)

        # 2. Front Coverall Zipper Storm-Flap & Placket Seam (x ~ 0, y < -0.06, z in 0.94..1.65)
        if y < -0.06 and 0.94 < z < 1.65:
            zip_flap = math.exp(-(((x - 0.005) / 0.011) ** 2)) - 0.55 * math.exp(
                -(((x + 0.009) / 0.006) ** 2)
            )
            disp += 0.0042 * zip_flap

        # 3. Torso, Chest, Armpit & Back Coverall Drapes (z in 0.98..1.62)
        if 0.98 < z < 1.62 and abs(x) < 0.24:
            lower_torso_env = math.sin(((z - 0.98) / 0.64) * math.pi) * (1.0 - 0.60 * _smoothstep(1.40, 1.58, z))
            armpit_pull = math.exp(-(((abs(x) - 0.175) / 0.055) ** 2)) * math.exp(-(((z - 1.44) / 0.11) ** 2))

            if y < 0.0:
                diag_front = _cloth_ridge((z * 6.5 + x * 7.5 + y * 2.5) * math.tau, 2.2)
                armpit_fold = _cloth_ridge((z * 11.0 - abs(x) * 9.0) * math.tau, 2.3)
                waist_bunch = math.exp(-(((z - 1.10) / 0.10) ** 2)) * _cloth_ridge(
                    (z * 14.0 + x * 4.5) * math.tau, 2.4
                )
                disp += (
                    0.0058 * lower_torso_env * diag_front
                    + 0.0068 * armpit_pull * armpit_fold
                    + 0.0068 * waist_bunch
                )
            else:
                vert_drape_1 = _cloth_ridge((x * 8.0 + (z - 1.25) * 3.0) * math.tau, 2.2)
                vert_drape_2 = _cloth_ridge((x * 6.0 - (z - 1.25) * 3.5 + 0.8) * math.tau, 2.2)
                lumbar_bunch = math.exp(-(((z - 1.08) / 0.095) ** 2)) * _cloth_ridge(
                    (z * 14.5 + x * 5.0) * math.tau, 2.4
                )
                disp += (
                    0.0070 * lower_torso_env * (0.55 * vert_drape_1 + 0.45 * vert_drape_2)
                    + 0.0065 * lumbar_bunch
                )

        # 4. Heavy Sleeve Accordion & Spiral Folds (Upper Arm, Inner Elbow, Forearm, Wrist Cuff)
        for sh, elb, wr in ((shoulder_r, elbow_r, wrist_r), (shoulder_l, elbow_l, wrist_l)):
            d_elb = (co - elb).length
            d_wr = (co - wr).length
            d_sh = (co - sh).length

            if d_sh < 0.19 and abs(x) > 0.15:
                sh_env = math.exp(-(((d_sh - 0.075) / 0.065) ** 2))
                disp += 0.0065 * sh_env * _cloth_ridge(d_sh * 12.0 * math.tau + theta * 2.0, 2.2)

            if d_elb < 0.22:
                e_env = math.exp(-((d_elb / 0.125) ** 2))
                f_elbow = 0.65 * _cloth_ridge(d_elb * 14.5 * math.tau, 2.5) + 0.35 * _cloth_ridge(
                    (d_elb * 9.5 + z * 5.5) * math.tau, 2.2
                )
                disp += 0.0105 * e_env * f_elbow

            if 0.030 < d_wr < 0.18:
                w_env = math.exp(-(((d_wr - 0.080) / 0.052) ** 2))
                disp += 0.0085 * w_env * _cloth_ridge(d_wr * 16.5 * math.tau + y * 5.0, 2.4)

        # 5. Crotch, Seat & Upper-Thigh Catenary Drape Folds (z in 0.74..1.02)
        if 0.74 < z < 1.02:
            g_env = math.sin(((z - 0.74) / 0.28) * math.pi)
            catenary = _cloth_ridge((z * 10.5 - abs(x) * 9.5 + y * 4.0) * math.tau, 2.3)
            seat_sag = (
                math.exp(-(((z - 0.88) / 0.085) ** 2))
                * max(0.0, y / 0.10)
                * _cloth_ridge((z * 13.5 + x * 5.5) * math.tau, 2.4)
            )
            disp += 0.0072 * g_env * catenary + 0.0070 * seat_sag

        # 6. Asymmetric Trouser Column Drapes, Knee Chevrons & Stacked Boot Cuffs (z in 0.09..0.84)
        if 0.09 < z < 0.84:
            leg_cx = -0.145 if x < 0.0 else 0.145
            leg_phase = 0.0 if x < 0.0 else 1.65
            theta_leg = math.atan2(y, x - leg_cx)
            leg_env = math.sin(((z - 0.09) / 0.75) * math.pi)
            col_drape = 0.55 * _cloth_ridge(theta_leg * 3.0 + z * 4.5 * math.tau + leg_phase, 2.2) + 0.45 * _cloth_ridge(
                theta_leg * 2.0 - z * 6.0 * math.tau - leg_phase, 2.2
            )
            disp += 0.0068 * leg_env * col_drape

            if 0.43 < z < 0.65:
                k_env = math.exp(-(((z - 0.535) / 0.075) ** 2))
                back_boost = 0.65 + 0.70 * max(0.0, y / 0.09)
                k_fold = _cloth_ridge((z * 15.5 + abs(x - leg_cx) * 7.5 + leg_phase * 0.4) * math.tau, 2.5)
                disp += 0.0095 * k_env * back_boost * k_fold

            if 0.09 < z < 0.30:
                cuff_env = math.exp(-(((z - 0.170) / 0.068) ** 2))
                cuff_fold = 0.7 * _cloth_ridge((z * 18.5 + theta_leg * 0.5 + leg_phase) * math.tau, 2.5) + 0.3 * _cloth_ridge(
                    (z * 12.0 - theta_leg) * math.tau, 2.2
                )
                disp += 0.0105 * cuff_env * cuff_fold

        v.co = co + n * disp

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()


def _assign_character_box_uvs(obj: bpy.types.Object) -> None:
    """Assign clean cylindrical/triplanar UVs named 'UVMap' so joining with axe preserves UVs."""
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")

    for face in bm.faces:
        n = face.normal
        for loop in face.loops:
            co = loop.vert.co
            if abs(n.z) > 0.72:
                u = (co.x + 0.5) * 1.2
                v = (co.y + 0.5) * 1.2
            else:
                theta = math.atan2(co.y, co.x)
                u = (theta / math.tau) + 0.5
                v = co.z / 2.02
            loop[uv_layer].uv = (u % 1.0, max(0.01, min(0.99, v)))

    bm.to_mesh(mesh)
    bm.free()


def build_axe_man_character() -> bpy.types.Object:
    """Assemble, Boolean-union, voxel-remesh, and sculpt deep coverall folds on the 2.0m character."""
    base_obj = _build_torso_and_neck_obj()
    base_obj.name = "Axe_Man_Body"
    base_obj.data.name = "Axe_Man_Body_Mesh"

    sub_objs: list[bpy.types.Object] = [
        _build_head_obj(),
        _build_leg_obj(side=-1),
        _build_leg_obj(side=+1),
        _build_boot_obj(side=-1),
        _build_boot_obj(side=+1),
    ]
    sub_objs.extend(_build_arm_and_glove_objs(side=-1))
    sub_objs.extend(_build_arm_and_glove_objs(side=+1))

    bpy.ops.object.select_all(action="DESELECT")
    for s_obj in sub_objs:
        s_obj.select_set(True)
    bpy.context.view_layer.objects.active = sub_objs[0]
    bpy.ops.object.join()
    limbs_obj = bpy.context.active_object

    bpy.ops.object.select_all(action="DESELECT")
    base_obj.select_set(True)
    bpy.context.view_layer.objects.active = base_obj

    bool_mod = base_obj.modifiers.new(name="UnionLimbs", type="BOOLEAN")
    bool_mod.operation = "UNION"
    bool_mod.object = limbs_obj
    bpy.ops.object.modifier_apply(modifier=bool_mod.name)

    bpy.data.objects.remove(limbs_obj, do_unlink=True)

    remesh = base_obj.modifiers.new(name="SeamlessVoxel", type="REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 0.0110
    remesh.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=remesh.name)

    smooth = base_obj.modifiers.new(name="AnatomicalPolish", type="SMOOTH")
    smooth.factor = 0.52
    smooth.iterations = 4
    bpy.ops.object.modifier_apply(modifier=smooth.name)

    _sculpt_heavy_coverall_folds(base_obj)

    # Very light 1-pass relax (factor=0.12) so deep 3D folds remain sharp and pronounced!
    smooth_folds = base_obj.modifiers.new(name="FoldPolish", type="SMOOTH")
    smooth_folds.factor = 0.12
    smooth_folds.iterations = 1
    bpy.ops.object.modifier_apply(modifier=smooth_folds.name)

    # Normalize exact height to [0.000, 2.000] meters
    min_z = min(v.co.z for v in base_obj.data.vertices)
    max_z = max(v.co.z for v in base_obj.data.vertices)
    scale_z = 2.000 / (max_z - min_z)
    for v in base_obj.data.vertices:
        v.co.z = (v.co.z - min_z) * scale_z

    _assign_character_box_uvs(base_obj)
    base_obj.data.validate(verbose=False)
    for poly in base_obj.data.polygons:
        poly.use_smooth = True

    final_tris = sum(len(p.vertices) - 2 for p in base_obj.data.polygons)
    print(f"[Blender] Character mesh 'Axe_Man_Body' triangle count: {final_tris}")
    return base_obj


# ---------------------------------------------------------------------------
# Heavy Tactical Fire / Breaching Axe Prop Builder (Scaled for 2.00m Figure)
# ---------------------------------------------------------------------------

def build_tactical_fire_axe() -> bpy.types.Object:
    """Build the menacing 1.40m Tactical Fire Axe with thick ribbed upper grip & double-flared blade."""
    pommel_origin, u_blade, v_side, w_shaft = _axe_transform()

    mesh = bpy.data.meshes.new("Axe_Man_Axe_Mesh")
    obj = bpy.data.objects.new("Axe_Man_Axe", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    # -----------------------------------------------------------------------
    # 1. 1.40m Ergonomic Haft (num_s=160 for zero-aliasing grip ribs & spiral flutes)
    # -----------------------------------------------------------------------
    num_s = 160
    num_rad = 24
    s_max = 1.395
    haft_rings: list[list[bmesh.types.BMVert]] = []
    haft_v_uvs: list[float] = []

    for i in range(num_s):
        s_frac = i / (num_s - 1)
        s = s_frac * s_max

        rx = 0.0205
        ry = 0.0150
        hook_u = 0.0

        # Fawn's-foot pommel flare at bottom end (s < 0.18m)
        if s < 0.18:
            p_t = 1.0 - (s / 0.18)
            hook_u = -0.028 * (p_t**2.1)
            rx += 0.0090 * (p_t**1.6) - 0.0028 * math.sin(p_t * math.pi)
            ry += 0.0040 * (p_t**1.6)
            if i == 0:
                rx *= 0.45
                ry *= 0.45

        # Center divider collar band (s in 0.58..0.67m)
        if 0.58 <= s <= 0.67:
            div_env = _smoothstep(0.58, 0.595, s) * (1.0 - _smoothstep(0.655, 0.67, s))
            rx += 0.0020 * div_env
            ry += 0.0020 * div_env

        # Thick tapered ribbed rubber shock-absorber sleeve below axe head (s in 0.90..1.25m)
        if 0.90 <= s <= 1.25:
            rib_env = _smoothstep(0.90, 0.92, s) * (1.0 - _smoothstep(1.235, 1.25, s))
            taper_swell = (s - 0.90) / 0.35
            rib_wave = 0.5 + 0.5 * math.sin((s - 0.90) / 0.35 * 22.0 * math.tau)
            rib_bump = 0.0024 * rib_env * rib_wave
            rx += (0.0025 + 0.0045 * taper_swell) * rib_env + rib_bump
            ry += (0.0022 + 0.0038 * taper_swell) * rib_env + rib_bump

        # Forged steel socket base collar transition (s in 1.24..1.27m)
        if 1.24 < s < 1.27:
            col_env = math.sin(((s - 1.24) / 0.03) * math.pi)
            rx += 0.0050 * col_env
            ry += 0.0042 * col_env

        center = pommel_origin + w_shaft * s + u_blade * hook_u
        ring: list[bmesh.types.BMVert] = []

        for k in range(num_rad):
            theta = (k / num_rad) * math.tau
            cos_t = math.cos(theta)
            sin_t = math.sin(theta)

            spiral_groove = 0.0
            if 0.16 < s < 0.88:
                sp_env = _smoothstep(0.16, 0.21, s) * (1.0 - _smoothstep(0.83, 0.88, s))
                sp_phase = (s * 8.0 + (theta / math.tau) * 2.0) * math.tau
                spiral_groove = -0.0018 * sp_env * max(0.0, math.sin(sp_phase)) ** 2

            lx = (rx + spiral_groove) * cos_t
            ly = (ry + spiral_groove) * sin_t
            pt = center + u_blade * lx + v_side * ly
            ring.append(bm.verts.new(pt))

        haft_rings.append(ring)
        haft_v_uvs.append(0.04 + 0.42 * s_frac)

    for i in range(num_s - 1):
        r0, r1 = haft_rings[i], haft_rings[i + 1]
        va, vb = haft_v_uvs[i], haft_v_uvs[i + 1]
        for k in range(num_rad):
            kn = (k + 1) % num_rad
            u1, u2 = k / num_rad, (k + 1) / num_rad
            f = bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
            for loop, uv in zip(f.loops, [(u1, va), (u2, va), (u2, vb), (u1, vb)]):
                loop[uv_layer].uv = uv

    for ring_idx, flip in ((0, True), (-1, False)):
        ring = haft_rings[ring_idx]
        avg = sum((v.co for v in ring), mathutils.Vector()) / len(ring)
        vc = bm.verts.new(avg)
        for k in range(num_rad):
            kn = (k + 1) % num_rad
            f = bm.faces.new((vc, ring[kn], ring[k]) if flip else (vc, ring[k], ring[kn]))
            for loop in f.loops:
                loop[uv_layer].uv = (0.5, 0.25)

    # -----------------------------------------------------------------------
    # 2. Double-Flared Fire-Axe Head (Top-Mounted Socket Eye + Bearded Bit + Upper-Rear Pike)
    # -----------------------------------------------------------------------
    n_h = 22
    pos_grid_plus: list[list[bmesh.types.BMVert]] = []
    pos_grid_minus: list[list[bmesh.types.BMVert]] = []
    j_uv_v = [0.95, 0.86, 0.68, 0.62, 0.60, 0.58, 0.55]

    for i_h in range(n_h):
        t_h = i_h / (n_h - 1)  # 0.0 = bottom heel of blade, 1.0 = top toe of blade

        # Cutting edge flares downward to s=1.155 (deep beard) and upward to s=1.400 (24.5cm curved bit)
        s_edge = 1.155 + 0.245 * t_h
        curve_arc = math.sin(t_h * math.pi)
        u_edge = 0.220 + 0.032 * curve_arc - 0.014 * ((1.0 - t_h) ** 2)
        u_bevel = u_edge - 0.018

        # Top-mounted central socket collar spans s in [1.260, 1.385] (flush with top of 1.395m shaft!)
        s_eye = 1.260 + 0.125 * t_h
        s_cheek = 1.210 + 0.180 * t_h

        # Upper-rear breaching spike / pike projects on the upper half (t_h >= 0.45)
        spike_weight = _smoothstep(0.45, 0.76, t_h) * (1.0 - 0.18 * _smoothstep(0.90, 1.0, t_h))
        s_spike_mid = s_eye + 0.014 * spike_weight
        s_spike_tip = s_eye + 0.028 * spike_weight
        u_spike_mid = -0.029 - 0.050 * spike_weight
        u_spike_tip = -0.030 - 0.105 * spike_weight

        cheek_groove = -0.0028 if (0.26 < t_h < 0.42 or 0.58 < t_h < 0.74) else 0.0

        row_specs = [
            (s_edge, u_edge, 0.0005),                            # j=0: Razor cutting edge
            (s_edge * 0.90 + s_cheek * 0.10, u_bevel, 0.0060),   # j=1: Bevel shoulder
            (s_cheek, 0.096, 0.0125 + cheek_groove),             # j=2: Mid blade cheek
            (s_eye, 0.030, 0.0205),                              # j=3: Front of shaft eye socket
            (s_eye, -0.029, 0.0195),                             # j=4: Rear of shaft eye socket
            (s_spike_mid, u_spike_mid, 0.0120 * (1.0 - 0.35 * spike_weight)),  # j=5: Spike body
            (s_spike_tip, u_spike_tip, 0.0020),                  # j=6: Rear breaching spike wedge tip
        ]

        row_p: list[bmesh.types.BMVert] = []
        row_m: list[bmesh.types.BMVert] = []
        for s_c, u_c, h_thick in row_specs:
            base = pommel_origin + w_shaft * s_c + u_blade * u_c
            row_p.append(bm.verts.new(base + v_side * h_thick))
            row_m.append(bm.verts.new(base - v_side * h_thick))
        pos_grid_plus.append(row_p)
        pos_grid_minus.append(row_m)

    n_cols = len(pos_grid_plus[0])

    for i_h in range(n_h - 1):
        u1, u2 = i_h / (n_h - 1), (i_h + 1) / (n_h - 1)
        for j in range(n_cols - 1):
            va, vb = j_uv_v[j], j_uv_v[j + 1]
            fp = bm.faces.new(
                (
                    pos_grid_plus[i_h][j],
                    pos_grid_plus[i_h + 1][j],
                    pos_grid_plus[i_h + 1][j + 1],
                    pos_grid_plus[i_h][j + 1],
                )
            )
            for loop, uv in zip(fp.loops, [(u1, va), (u2, va), (u2, vb), (u1, vb)]):
                loop[uv_layer].uv = uv

            fm = bm.faces.new(
                (
                    pos_grid_minus[i_h][j + 1],
                    pos_grid_minus[i_h + 1][j + 1],
                    pos_grid_minus[i_h + 1][j],
                    pos_grid_minus[i_h][j],
                )
            )
            for loop, uv in zip(fm.loops, [(u1, vb), (u2, vb), (u2, va), (u1, va)]):
                loop[uv_layer].uv = uv

    for i_h in range(n_h - 1):
        f_edge = bm.faces.new(
            (
                pos_grid_minus[i_h][0],
                pos_grid_minus[i_h + 1][0],
                pos_grid_plus[i_h + 1][0],
                pos_grid_plus[i_h][0],
            )
        )
        for loop in f_edge.loops:
            loop[uv_layer].uv = (0.5, 0.94)

        j_last = n_cols - 1
        f_back = bm.faces.new(
            (
                pos_grid_plus[i_h][j_last],
                pos_grid_plus[i_h + 1][j_last],
                pos_grid_minus[i_h + 1][j_last],
                pos_grid_minus[i_h][j_last],
            )
        )
        for loop in f_back.loops:
            loop[uv_layer].uv = (0.5, 0.62)

    for j in range(n_cols - 1):
        v_uv = j_uv_v[j]
        f_bot = bm.faces.new(
            (
                pos_grid_plus[0][j],
                pos_grid_plus[0][j + 1],
                pos_grid_minus[0][j + 1],
                pos_grid_minus[0][j],
            )
        )
        for loop in f_bot.loops:
            loop[uv_layer].uv = (0.5, v_uv)

        top_i = n_h - 1
        f_top = bm.faces.new(
            (
                pos_grid_minus[top_i][j],
                pos_grid_minus[top_i][j + 1],
                pos_grid_plus[top_i][j + 1],
                pos_grid_plus[top_i][j],
            )
        )
        for loop in f_top.loops:
            top_v = 0.89 if j >= 5 else v_uv
            loop[uv_layer].uv = (0.5, top_v)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    mesh.validate(verbose=False)
    for poly in mesh.polygons:
        poly.use_smooth = True

    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    print(f"[Blender] Weapon mesh 'Axe_Man_Axe' triangle count: {tri_count}")
    return obj


# ---------------------------------------------------------------------------
# Temporary Studio Preview Renderer (Stripped before saving .blend / .glb)
# ---------------------------------------------------------------------------

def render_turnaround_previews(output_dir: Path) -> Path:
    """Temporarily add studio lights & camera to render Front/Side/Back views, then delete them."""
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
        bg.inputs[0].default_value = (0.16, 0.17, 0.19, 1.0)
        bg.inputs[1].default_value = 0.60

    lights_spec = [
        ("Temp_Overhead_Key", (0.0, -0.40, 3.35), (0.0, 0.0, 1.35), 260.0, 1.75, (0.96, 0.98, 1.0)),
        ("Temp_Front_Fill", (-1.65, -2.25, 1.65), (0.0, 0.0, 1.15), 80.0, 1.50, (0.92, 0.95, 1.0)),
        ("Temp_Right_Fill", (1.65, -2.05, 1.45), (0.0, 0.0, 1.10), 60.0, 1.50, (0.90, 0.93, 1.0)),
        ("Temp_Rim_Back", (0.0, 2.00, 2.65), (0.0, 0.0, 1.35), 160.0, 1.60, (0.95, 0.97, 1.0)),
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
    cam_data.lens = 50.0
    cam_obj = bpy.data.objects.new("Temp_Camera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    temp_objs.append(cam_obj)

    scene.render.resolution_x = 640
    scene.render.resolution_y = 840
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"

    look_target = mathutils.Vector((0.0, 0.0, 1.02))
    views = [
        ("front", mathutils.Vector((0.0, -3.65, 1.06))),
        ("side", mathutils.Vector((-3.65, 0.0, 1.06))),
        ("back", mathutils.Vector((0.0, 3.65, 1.06))),
    ]

    panel_paths: list[Path] = []
    for v_name, cam_pos in views:
        cam_obj.location = cam_pos
        cam_obj.rotation_euler = (look_target - cam_pos).to_track_quat("-Z", "Y").to_euler()
        out_p = output_dir / f"axe_man_{v_name}.png"
        scene.render.filepath = str(out_p)
        bpy.ops.render.render(write_still=True)
        panel_paths.append(out_p)

    # Stitch 3-panel turnaround sheet
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
    comb_img = bpy.data.images.new("Turnaround_Sheet", width=comb_w, height=comb_h, alpha=False)
    comb_img.pixels.foreach_set(combined.ravel())
    sheet_path = output_dir / "axe_man_turnaround_preview.png"
    comb_img.filepath_raw = str(sheet_path)
    comb_img.file_format = "PNG"
    comb_img.save()
    bpy.data.images.remove(comb_img)

    # Completely remove temporary lights, camera, and world so scene is 100% pure model
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


# ---------------------------------------------------------------------------
# Main Pipeline Entrypoint
# ---------------------------------------------------------------------------

def generate_axe_man(output_dir: Path) -> Path:
    clean_scene()
    output_dir.mkdir(parents=True, exist_ok=True)

    # 1. Generate Procedural PBR Textures
    suit_alb, suit_rough, suit_norm = _generate_suit_pbr_textures(output_dir)
    axe_alb, axe_rough, axe_norm = _generate_axe_pbr_textures(output_dir)

    # 2. Build 2.00m Character & Tactical Fire Axe Geometry
    char_obj = build_axe_man_character()
    axe_obj = build_tactical_fire_axe()

    # 3. Create & Assign PBR Materials
    mat_suit = create_pbr_material(
        name="Mat_AxeMan_LatexSuit",
        base_color=(0.011, 0.011, 0.013, 1.0),
        metallic=0.02,
        roughness=0.35,
        base_color_image=suit_alb,
        roughness_image=suit_rough,
        normal_image=suit_norm,
        normal_strength=0.45,
    )
    bsdf_suit = next((n for n in mat_suit.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf_suit:
        if "Coat Weight" in bsdf_suit.inputs:
            bsdf_suit.inputs["Coat Weight"].default_value = 0.14
        if "Coat Roughness" in bsdf_suit.inputs:
            bsdf_suit.inputs["Coat Roughness"].default_value = 0.28
    assign_material(char_obj, mat_suit)

    mat_axe = create_pbr_material(
        name="Mat_AxeMan_Weapon",
        base_color=(0.08, 0.08, 0.09, 1.0),
        metallic=0.72,
        roughness=0.28,
        base_color_image=axe_alb,
        roughness_image=axe_rough,
        normal_image=axe_norm,
        normal_strength=0.80,
    )
    assign_material(axe_obj, mat_axe)

    # 4. Join Character & Axe into a single unified static mesh ('axe_man') with 2 material slots
    bpy.ops.object.select_all(action="DESELECT")
    char_obj.select_set(True)
    axe_obj.select_set(True)
    bpy.context.view_layer.objects.active = char_obj
    bpy.ops.object.join()

    unified_obj = bpy.context.active_object
    unified_obj.name = "axe_man"
    unified_obj.data.name = "axe_man_mesh"
    unified_obj.data.validate(verbose=False)

    z_vals = [v.co.z for v in unified_obj.data.vertices]
    total_tris = sum(len(p.vertices) - 2 for p in unified_obj.data.polygons)
    print(
        f"[Blender] Unified static mesh 'axe_man': {total_tris} tris, "
        f"Z bounds = [{min(z_vals):.4f}m, {max(z_vals):.4f}m] (height = {max(z_vals) - min(z_vals):.4f}m)"
    )

    # 5. Render verification turnaround sheet (lights/camera are deleted immediately after render)
    render_turnaround_previews(output_dir)

    # Verify scene contains ONLY the single static 'axe_man' mesh object
    scene_objs = [o.name for o in bpy.data.objects]
    print(f"[Blender] Final scene objects before export: {scene_objs}")

    # 6. Save clean .blend and export static Godot 4 .glb (no bones, no animations, no cameras, no lights)
    glb_path = output_dir / "axe_man.glb"
    export_godot_glb(
        filepath=glb_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=True,
    )
    return glb_path


def main() -> None:
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        assets_dir = sdk_root / "assets" / "models" / "axe_man"
        generate_axe_man(assets_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
