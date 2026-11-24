#!/usr/bin/env python3
"""Procedural Anime Head, Eye, Eyelash, Mouth, Custom Normals & ARKit-52 Builder for Ghost Girl.

Constructs GhostGirl's stylized anime head package conformed to the 4 bald head ortho plates
(`ref_head_front_side.jpg` and `ref_head_back.jpg`):
- `GhostGirl_Head` (~4,200 tris symmetrical quad-loop anime head with smooth planar cheeks,
  tiny upturned anime nose, closed thin neutral mouth + recessed oral cavity, soft V-chin,
  clean anime ears, almond eye sockets, slender neck tucked into turtleneck collar, and custom
  ellipsoidal split vertex normals via `apply_anime_face_normals`).
- `GhostGirl_Eye_L`, `GhostGirl_Eye_R` (slightly flattened curved anime cornea domes tucked
  cleanly inside almond sockets with +/-20deg yaw and +/-14deg pitch clearance; UV center (0.5, 0.5),
  iris radius 0.30).
- `GhostGirl_Eyelashes` (crisp bold upper arch + upturned outer wing + delicate lower ticks).
- `GhostGirl_Teeth_Upper`, `GhostGirl_Teeth_Lower`, `GhostGirl_Tongue` (stylized smooth anime
  oral anatomy tucked cleanly behind closed neutral lips).
- 52 `ARKIT_52` blendshapes on `GhostGirl_Head` + 6 `EYELASH_6` keys on `GhostGirl_Eyelashes`.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

# ---------------------------------------------------------------------------
# Locked Anatomical Landmarks (1.58m tall, -Y forward, +Z up, +X char left)
# ---------------------------------------------------------------------------

Z_NECK_CUT_DEFAULT: float = 1.2800
Z_CHIN: float = 1.3340
Z_MOUTH: float = 1.3650
Z_NOSE_TIP: float = 1.3960
Z_EYE: float = 1.4340
Z_BROW: float = 1.4590
Z_FOREHEAD_MID: float = 1.5120
Z_CROWN: float = 1.5800

EYE_X: float = 0.0392
EYE_Y: float = -0.1045
EYE_Z: float = Z_EYE
EYE_RX: float = 0.0202
EYE_RY: float = 0.0102
EYE_RZ: float = 0.0168

SKULL_MAX_RX: float = 0.0960
HEAD_CENTER_Y: float = -0.0170
HEAD_Y_FRONT: float = -0.1245
HEAD_Y_BACK: float = 0.0920

EAR_X_MAX: float = 0.1070
EAR_Y_CENTER: float = -0.0100
EAR_Z_CENTER: float = 1.4120

TMJ_Y: float = -0.0320
TMJ_Z: float = 1.4000
JAW_OPEN_DEG: float = 18.0

SKIN_PEACH_RGB: Tuple[float, float, float] = (0.9922, 0.9020, 0.8549)  # #FDE6DA

ARKIT_52: Tuple[str, ...] = (
    "eyeBlinkLeft",
    "eyeLookDownLeft",
    "eyeLookInLeft",
    "eyeLookOutLeft",
    "eyeLookUpLeft",
    "eyeSquintLeft",
    "eyeWideLeft",
    "eyeBlinkRight",
    "eyeLookDownRight",
    "eyeLookInRight",
    "eyeLookOutRight",
    "eyeLookUpRight",
    "eyeSquintRight",
    "eyeWideRight",
    "jawForward",
    "jawRight",
    "jawLeft",
    "jawOpen",
    "mouthClose",
    "mouthFunnel",
    "mouthPucker",
    "mouthRight",
    "mouthLeft",
    "mouthSmileLeft",
    "mouthSmileRight",
    "mouthFrownLeft",
    "mouthFrownRight",
    "mouthDimpleLeft",
    "mouthDimpleRight",
    "mouthStretchLeft",
    "mouthStretchRight",
    "mouthRollLower",
    "mouthRollUpper",
    "mouthShrugLower",
    "mouthShrugUpper",
    "mouthPressLeft",
    "mouthPressRight",
    "mouthLowerDownLeft",
    "mouthLowerDownRight",
    "mouthUpperUpLeft",
    "mouthUpperUpRight",
    "browDownLeft",
    "browDownRight",
    "browInnerUp",
    "browOuterUpLeft",
    "browOuterUpRight",
    "cheekPuff",
    "cheekSquintLeft",
    "cheekSquintRight",
    "noseSneerLeft",
    "noseSneerRight",
    "tongueOut",
)

EYELASH_6: Tuple[str, ...] = (
    "eyeBlinkLeft",
    "eyeBlinkRight",
    "eyeWideLeft",
    "eyeWideRight",
    "eyeSquintLeft",
    "eyeSquintRight",
)


# ---------------------------------------------------------------------------
# Math & Image Helpers
# ---------------------------------------------------------------------------

def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    if abs(edge1 - edge0) < 1e-8:
        return 1.0 if x >= edge1 else 0.0
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _gauss(d: float, sigma: float) -> float:
    return math.exp(-0.5 * (d / max(sigma, 1e-6)) ** 2)


def _lerp_piecewise(z: float, stops: Sequence[Tuple[float, float]]) -> float:
    if z <= stops[0][0]:
        return stops[0][1]
    if z >= stops[-1][0]:
        return stops[-1][1]
    for i in range(len(stops) - 1):
        z0, v0 = stops[i]
        z1, v1 = stops[i + 1]
        if z0 <= z <= z1:
            t = (z - z0) / max(z1 - z0, 1e-6)
            t_s = t * t * (3.0 - 2.0 * t)
            return v0 * (1.0 - t_s) + v1 * t_s
    return stops[-1][1]


def _save_image_array(path: Path, arr: np.ndarray) -> Path:
    """Save top-down float32 (0..1) or uint8 (H, W, 3|4) array to PNG via Blender."""
    path.parent.mkdir(parents=True, exist_ok=True)
    h, w, ch = arr.shape
    f = (
        arr.astype(np.float32) / 255.0
        if arr.dtype == np.uint8
        else np.clip(arr, 0.0, 1.0).astype(np.float32)
    )
    if ch == 3:
        rgba = np.ones((h, w, 4), dtype=np.float32)
        rgba[:, :, :3] = f
    else:
        rgba = f
    rgba_bu = np.ascontiguousarray(rgba[::-1, :, :]).ravel()
    img = bpy.data.images.new(name=path.stem, width=w, height=h, alpha=(ch == 4))
    try:
        img.pixels.foreach_set(rgba_bu)
        img.filepath_raw = str(path)
        img.file_format = "PNG"
        img.save()
    finally:
        bpy.data.images.remove(img)
    return path


def _dilate_rgb_padding(rgb: np.ndarray, valid_mask: np.ndarray, steps: int = 12) -> np.ndarray:
    """Dilate valid UV island pixels outward to prevent mipmap border seams."""
    dil = rgb.copy()
    mask = valid_mask.copy()
    for _ in range(steps):
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted = np.roll(np.roll(dil, dy, axis=0), dx, axis=1)
            smask = np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
            fill = (~mask) & smask
            dil[fill] = shifted[fill]
            mask = mask | fill
    return dil


def _make_material(
    name: str,
    albedo_path: Optional[Path] = None,
    orm_path: Optional[Path] = None,
    base_color: Tuple[float, float, float, float] = (0.95, 0.95, 0.95, 1.0),
    roughness: float = 0.60,
    specular: float = 0.35,
    alpha_mode: str = "OPAQUE",
    alpha_threshold: float = 0.35,
    double_sided: bool = False,
    coat: float = 0.0,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    """Create a glTF-2.0 Principled BSDF material."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = not double_sided
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Alpha"].default_value = base_color[3]
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.04
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if albedo_path and albedo_path.exists():
        img = bpy.data.images.load(str(albedo_path), check_existing=True)
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_mode != "OPAQUE":
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        if emission_strength > 0.0 and "Emission Color" in bsdf.inputs:
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = emission_strength

    if orm_path and orm_path.exists():
        img_o = bpy.data.images.load(str(orm_path), check_existing=True)
        img_o.colorspace_settings.name = "Non-Color"
        tex_o = nt.nodes.new("ShaderNodeTexImage")
        tex_o.image = img_o
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(tex_o.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    if alpha_mode == "CLIP":
        if hasattr(mat, "blend_method"):
            mat.blend_method = "CLIP"
        if hasattr(mat, "alpha_threshold"):
            mat.alpha_threshold = alpha_threshold
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "DITHERED"
    elif alpha_mode == "BLEND":
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
    return mat


# ---------------------------------------------------------------------------
# Swept Cornea Envelope Clearance (Guarantees +/-20deg Yaw & +/-14deg Pitch)
# ---------------------------------------------------------------------------

def _eye_cornea_surface_y(
    x: float,
    z: float,
    eye_center: Vector,
    extra_margin: float = 0.0018,
    include_gaze_sweep: bool = True,
) -> Optional[float]:
    """Return minimum anterior Y of rotated anime eye ellipsoid + safety margin, or None if outside."""
    dx = x - eye_center.x
    dz = z - eye_center.z
    # Quick AABB reject
    if abs(dx) > EYE_RX + extra_margin + 0.008 or abs(dz) > EYE_RZ + extra_margin + 0.006:
        return None

    rx = EYE_RX + extra_margin
    ry = EYE_RY + extra_margin
    rz = EYE_RZ + extra_margin

    # Base unrotated front Y
    u0 = (dx / rx) ** 2 + (dz / rz) ** 2
    best_y: Optional[float] = None
    if u0 < 1.0:
        best_y = eye_center.y - ry * math.sqrt(max(0.0, 1.0 - u0))

    if include_gaze_sweep:
        # Check extreme yaw (+/-22deg) and pitch (+/-15deg) eye rotations
        for yaw_deg in (-22.0, 0.0, 22.0):
            cy_a = math.cos(math.radians(yaw_deg))
            sy_a = math.sin(math.radians(yaw_deg))
            for pitch_deg in (-15.0, 0.0, 15.0):
                if yaw_deg == 0.0 and pitch_deg == 0.0:
                    continue
                cp_a = math.cos(math.radians(pitch_deg))
                sp_a = math.sin(math.radians(pitch_deg))
                # Ray cast in -Y direction through inverse rotated ellipsoid
                # Local p = R_inv * [dx, dy, dz], solve a*dy^2 + b*dy + c = 0
                # R = Rz(yaw) @ Rx(pitch) => R_inv = Rx(-pitch) @ Rz(-yaw)
                # Step 1: u = Rz(-yaw) * [dx, dy, dz] -> ux = dx*cy + dy*sy, uy = -dx*sy + dy*cy, uz = dz
                # Step 2: v = Rx(-pitch) * u -> vx = ux, vy = uy*cp + uz*sp, vz = -uy*sp + uz*cp
                # Write v = v0 + v1 * dy
                v0x = dx * cy_a
                v1x = sy_a
                u0y = -dx * sy_a
                u1y = cy_a
                v0y = u0y * cp_a + dz * sp_a
                v1y = u1y * cp_a
                v0z = -u0y * sp_a + dz * cp_a
                v1z = -u1y * sp_a

                qa = (v1x / rx) ** 2 + (v1y / ry) ** 2 + (v1z / rz) ** 2
                qb = 2.0 * ((v0x * v1x) / (rx * rx) + (v0y * v1y) / (ry * ry) + (v0z * v1z) / (rz * rz))
                qc = (v0x / rx) ** 2 + (v0y / ry) ** 2 + (v0z / rz) ** 2 - 1.0
                disc = qb * qb - 4.0 * qa * qc
                if disc >= 0.0 and qa > 1e-8:
                    dy_front = (-qb - math.sqrt(disc)) / (2.0 * qa)
                    cand_y = eye_center.y + dy_front
                    if best_y is None or cand_y < best_y:
                        best_y = cand_y
    return best_y


def _clamp_outside_eye_swept(pt: Vector, eye_center: Vector, margin: float = 0.0018) -> Vector:
    """Push anterior orbital point out to safe clearance ahead of swept rotated eye dome."""
    if pt.y > eye_center.y + 0.004:
        return pt
    safe_y = _eye_cornea_surface_y(pt.x, pt.z, eye_center, extra_margin=margin, include_gaze_sweep=True)
    if safe_y is not None and pt.y > safe_y:
        return Vector((pt.x, safe_y, pt.z))
    return pt


# ---------------------------------------------------------------------------
# Base Anime Head Surface & Feature Sculpting
# ---------------------------------------------------------------------------

def _eval_base_head_point(
    theta: float,
    z: float,
    collar_center: Vector,
    z_neck_cut: float,
) -> Vector:
    """Evaluate symmetrical anime head surface at angle theta (0=-Y front, pi=+Y back) and world Z."""
    sin_t = math.sin(theta)
    cos_t = math.cos(theta)  # +1 front (-Y), -1 back (+Y)
    front_w = max(0.0, cos_t)
    back_w = max(0.0, -cos_t)

    # 1. Slender anime neck (z_neck_cut .. Z_CHIN) docking smoothly into collar_center (NO hourglass pinch!)
    if z < Z_CHIN:
        t_neck = max(0.0, min(1.0, (z - z_neck_cut) / max(Z_CHIN - z_neck_cut, 1e-4)))
        rx_neck = _lerp_piecewise(
            z,
            (
                (z_neck_cut, 0.0430),
                (z_neck_cut + 0.014, 0.0390),
                (1.300, 0.0370),
                (1.316, 0.0365),
                (1.330, 0.0365),
            ),
        )
        ry_neck = _lerp_piecewise(
            z,
            (
                (z_neck_cut, 0.0450),
                (z_neck_cut + 0.014, 0.0415),
                (1.300, 0.0405),
                (1.316, 0.0400),
                (1.330, 0.0400),
            ),
        )
        cy_neck = collar_center.y * (1.0 - _smoothstep(0.0, 0.65, t_neck)) + (-0.0100) * _smoothstep(0.0, 0.65, t_neck)
        x = sin_t * rx_neck
        y = cy_neck - cos_t * ry_neck

        # Crisp flat anime submental jaw shelf rising cleanly from throat (-0.048) to chin (-0.115)
        if z > 1.323 and front_w > 0.08:
            shelf_t = _smoothstep(1.323, Z_CHIN, z) ** 1.10
            arc = front_w ** 1.35
            y -= 0.0655 * shelf_t * arc
            x *= 1.0 - 0.56 * shelf_t * arc
        return Vector((x, y, z))

    # 2. Cranium & Face (Z_CHIN .. Z_CROWN) calibrated to all 4 ortho plates (cute wider anime oval-V)
    rx_stops = (
        (1.334, 0.0195),
        (1.344, 0.0365),
        (1.358, 0.0545),
        (1.374, 0.0685),
        (1.392, 0.0805),
        (1.412, 0.0885),
        (1.434, 0.0935),
        (1.462, 0.0960),
        (1.495, 0.0945),
        (1.524, 0.0885),
        (1.548, 0.0750),
        (1.564, 0.0550),
        (1.575, 0.0300),
        (1.580, 0.0010),
    )
    yf_stops = (
        (1.334, -0.1190),
        (1.340, -0.1228),
        (1.352, -0.1205),
        (1.362, -0.1245),
        (1.365, -0.1252),
        (1.369, -0.1270),
        (1.377, -0.1242),
        (1.387, -0.1232),
        (1.396, -0.1230),
        (1.416, -0.1222),
        (1.434, -0.1222),
        (1.459, -0.1246),
        (1.486, -0.1242),
        (1.515, -0.1208),
        (1.540, -0.1095),
        (1.562, -0.0840),
        (1.574, -0.0520),
        (1.580, -0.0170),
    )
    yb_stops = (
        (1.334, 0.0305),
        (1.350, 0.0345),
        (1.370, 0.0430),
        (1.388, 0.0555),
        (1.406, 0.0705),
        (1.425, 0.0825),
        (1.445, 0.0895),
        (1.472, 0.0920),
        (1.500, 0.0890),
        (1.526, 0.0790),
        (1.548, 0.0620),
        (1.565, 0.0385),
        (1.575, 0.0140),
        (1.580, -0.0170),
    )

    rx = _lerp_piecewise(z, rx_stops)
    y_f = _lerp_piecewise(z, yf_stops)
    y_b = _lerp_piecewise(z, yb_stops)

    cy = 0.5 * (y_f + y_b)
    ry = max(0.001, 0.5 * (y_b - y_f))

    # Smooth jaw/neck separation without pinching the neck width below 0.0365m!
    if z < 1.385:
        t_jaw = _smoothstep(Z_CHIN, 1.385, z)
        # Keep back/side of neck cylindrical (rx >= 0.0365) while V-chin tapers smoothly in front
        rx_back = max(0.0365, rx)
        rx = rx * front_w + rx_back * (1.0 - front_w)
        if front_w > 0.0:
            rx *= 1.0 - 0.04 * (1.0 - t_jaw) * (front_w ** 1.5)
        if back_w > 0.15 and z < 1.365:
            # Blend back/side smoothly into neck cylinder without waist pinch
            t_b = _smoothstep(Z_CHIN, 1.365, z)
            rx = rx * t_b + max(rx, 0.0365) * (1.0 - t_b)

    # Smooth planar anime cheek plane (zero concave troughs!)
    if 1.355 <= z <= 1.455 and front_w > 0.30:
        w_plane = _smoothstep(0.30, 0.85, front_w) * _smoothstep(1.355, 1.385, z) * (1.0 - _smoothstep(1.425, 1.455, z))
        ry *= 1.0 - 0.025 * (front_w ** 2.5) * w_plane

    x = sin_t * rx
    y = cy - cos_t * ry

    # Delicate forward-soft chin curve matching side profile ref
    if front_w > 0.65 and z <= 1.352:
        w_chin = _gauss(z - 1.340, 0.009) * _gauss(x, 0.019)
        y -= 0.0018 * w_chin

    # Dainty upturned anime nose point (delicate concave bridge swoop, sharp small tip at Z=1.396)
    if front_w > 0.72 and 1.384 <= z <= 1.425:
        nx_w = _gauss(x, 0.0066)
        if z >= Z_NOSE_TIP:
            t_br = _smoothstep(1.425, Z_NOSE_TIP, z)
            protrude = 0.0124 * (t_br ** 2.15)
        else:
            t_un = _smoothstep(1.384, Z_NOSE_TIP, z)
            protrude = 0.0124 * (t_un ** 1.45)
        y -= protrude * nx_w

    return Vector((x, y, z))


def _eye_rim_target(
    ang: float,
    side_sign: float,
    eye_center: Vector,
    t_lid: float,
) -> Vector:
    """Compute exact almond anime eyelid target point recessed cleanly behind cheek/brow plane."""
    c_a = math.cos(ang)
    s_a = math.sin(ang)
    is_upper = s_a >= 0.0

    # Large expressive almond anime proportions matching ref_head_front_side.jpg (zero corner sclera notch)
    w_inner = 0.0195
    w_outer = 0.0218
    w_rad = w_outer if (c_a * side_sign >= 0.0) else w_inner
    h_rad = 0.0122 if is_upper else 0.0094

    # Slight anime outer canthus lift (+1.4mm outer vs -0.8mm inner) + snug lower-outer corner seal
    u_x = (c_a * w_rad * side_sign) / 0.0215
    canthus_lift = 0.0014 * u_x
    if not is_upper:
        canthus_lift += 0.0008 * _smoothstep(0.30, 1.0, c_a * side_sign)
    arch_boost = 0.0009 * max(0.0, s_a) ** 0.75 if is_upper else 0.0

    scale = 1.50 * (1.0 - t_lid) + 1.0 * t_lid
    tx = eye_center.x + c_a * w_rad * scale
    tz = eye_center.z + s_a * h_rad * scale + (canthus_lift + arch_boost) * (0.25 + 0.75 * t_lid)

    # Seat rim comfortably outside swept flattened eye dome (+ extra outer corner shield to prevent sclera notch!)
    outer_pad = 0.0010 * _smoothstep(0.55, 1.0, c_a * side_sign) * t_lid
    margin = 0.0020 + (1.0 - t_lid) * 0.0010
    safe_y = _eye_cornea_surface_y(tx, tz, eye_center, extra_margin=margin, include_gaze_sweep=True)
    if safe_y is not None:
        ty = safe_y - outer_pad
    else:
        d2 = (tx - eye_center.x) ** 2 + (tz - eye_center.z) ** 2
        ty = eye_center.y - max(0.0038, math.sqrt(max(0.0, (EYE_RY + 0.0028) ** 2 - min(d2, 0.00018)))) - outer_pad
    return Vector((tx, ty, tz))


def _sculpt_eye_sockets_and_lids(
    bm: bmesh.types.BMesh,
    eye_center: Vector,
    side_sign: float,
    ring_loops: List[List[bmesh.types.BMVert]],
    socket_loops: List[List[bmesh.types.BMVert]],
) -> None:
    """Shape smooth flush almond anime eye sockets (zero under-eye troughs or heavy brow overhang)."""
    n_rings = len(ring_loops)
    for r_idx, loop in enumerate(ring_loops):
        t_lid = r_idx / float(max(1, n_rings - 1))  # 0 outer orbital -> 1 lid margin
        blend = _smoothstep(0.08, 1.0, t_lid)
        for v in loop:
            dx = v.co.x - eye_center.x
            dz = v.co.z - eye_center.z
            ang = math.atan2(dz, dx)
            tgt = _eye_rim_target(ang, side_sign, eye_center, t_lid)

            # For outer orbital ring (t_lid near 0), keep Y flush with cheek/forehead plane!
            nx = v.co.x * (1.0 - blend) + tgt.x * blend
            nz = v.co.z * (1.0 - blend) + tgt.z * blend
            if t_lid < 0.35:
                ny = v.co.y * (1.0 - blend * 0.65) + tgt.y * (blend * 0.65)
            else:
                ny = v.co.y * (1.0 - blend) + tgt.y * blend

            cand = Vector((nx, ny, nz))
            # Strictly enforce cornea clearance on inner lid rings
            if t_lid > 0.35:
                cand = _clamp_outside_eye_swept(cand, eye_center, margin=0.0020)
            v.co = cand

    # Pull inner socket loops smoothly behind eyeball equator to close orbital pocket
    for s_idx, s_loop in enumerate(socket_loops):
        depth = 0.003 + 0.005 * (s_idx + 1)
        shrink = 0.86 - 0.16 * s_idx
        for v in s_loop:
            dx = v.co.x - eye_center.x
            dz = v.co.z - eye_center.z
            v.co.x = eye_center.x + dx * shrink
            v.co.z = eye_center.z + dz * shrink
            v.co.y = eye_center.y - 0.004 + depth


def _sculpt_mouth_and_cavity(
    bm: bmesh.types.BMesh,
    ring_loops: List[List[bmesh.types.BMVert]],
    cavity_loops: List[List[bmesh.types.BMVert]],
    collar_center: Vector,
    z_neck_cut: float,
) -> Set[int]:
    """Keep neutral mouth 100% flush with smooth muzzle surface + shallow coral oral cavity."""
    mouth_bag_indices: Set[int] = set()
    n_rings = len(ring_loops)
    mouth_hw = 0.0155

    for r_idx, loop in enumerate(ring_loops):
        t_lip = r_idx / float(max(1, n_rings - 1))  # 0 outer muzzle -> 1 sealed lip slit
        blend = _smoothstep(0.06, 1.0, t_lip)
        for v in loop:
            x = v.co.x
            dz = v.co.z - Z_MOUTH
            u_x = max(-1.0, min(1.0, x / mouth_hw))
            is_upper = dz >= 0.0
            taper_x = max(0.0, 1.0 - (u_x ** 2)) ** 1.25

            # Exterior rings stay 100% flush on smooth base muzzle curve (ZERO concave mouth pit!)
            lip_h = (0.0008 if is_upper else 0.0009) * taper_x
            if t_lip > 0.80:
                tz = Z_MOUTH + (0.00015 if is_upper else -0.00015)
            else:
                lip_curve = (1.0 - t_lip) ** 0.95
                tz = Z_MOUTH + (lip_h * lip_curve if is_upper else -lip_h * lip_curve)

            tx = max(-mouth_hw, min(mouth_hw, x * (1.0 - 0.22 * t_lip))) if abs(x) > mouth_hw else x
            # Evaluate exact base head surface Y at (tx, tz) so mouth slit is 100% flush!
            ang_m = math.atan2(tx, 0.107)  # front midline angle from tx
            surf_pt = _eval_base_head_point(ang_m, tz, collar_center, z_neck_cut)
            ty = surf_pt.y

            v.co.x = v.co.x * (1.0 - blend) + tx * blend
            v.co.y = v.co.y * (1.0 - blend) + ty * blend
            v.co.z = v.co.z * (1.0 - blend) + tz * blend

    # Clean warm oral cavity enclosed snugly behind dental arches & tongue (24mm depth catches light cleanly)
    y_offsets = (0.0024, 0.0065, 0.0125, 0.0185, 0.0245)
    width_scales = (1.02, 1.24, 1.40, 1.36, 1.15)
    height_halfs = (0.00018, 0.0095, 0.0140, 0.0155, 0.0120)
    for c_idx, c_loop in enumerate(cavity_loops):
        dy_off = y_offsets[min(c_idx, len(y_offsets) - 1)]
        ws = width_scales[min(c_idx, len(width_scales) - 1)]
        hh = height_halfs[min(c_idx, len(height_halfs) - 1)]
        for v in c_loop:
            mouth_bag_indices.add(v.index)
            is_upper = v.co.z >= Z_MOUTH
            u_x = max(-1.0, min(1.0, v.co.x / mouth_hw))
            nx = max(-0.025, min(0.025, v.co.x * ws))
            ang_m = math.atan2(max(-mouth_hw, min(mouth_hw, nx)), 0.107)
            surf_pt = _eval_base_head_point(ang_m, Z_MOUTH, collar_center, z_neck_cut)
            v.co.x = nx
            v.co.y = surf_pt.y + dy_off + 0.002 * (u_x * u_x)
            corner_fade = max(0.18, math.sqrt(max(0.0, 1.0 - 0.80 * (u_x * u_x))))
            v.co.z = Z_MOUTH + (hh if is_upper else -hh) * corner_fade

    return mouth_bag_indices


def _sculpt_ears(bm: bmesh.types.BMesh) -> Set[int]:
    """Build sleek vertical C-shaped anime ears (Z=1.391..1.445, tucked close to skull) on both sides."""
    ear_vert_indices: Set[int] = set()

    # Parametric vertical anime C-ear: 18 perimeter points x 5 depth rings (base -> helix -> concha)
    n_p = 18
    e_cy = -0.0120
    e_cz = 1.4180
    e_ry = 0.0135
    e_rz = 0.0265
    tilt_rad = math.radians(-14.0)  # top helix tilts back (+Y)
    c_t, s_t = math.cos(tilt_rad), math.sin(tilt_rad)

    for side_sign in (1.0, -1.0):
        ring_specs = (
            (1.00, 0.0000, -0.0035),  # root tucked cleanly inside skull wall
            (1.02, 0.0115, 0.0008),   # sleek tucked outer helix silhouette (ref_head_back.jpg)
            (0.84, 0.0125, 0.0015),   # rounded helix roll crest
            (0.54, 0.0085, -0.0005),  # concha bowl
            (0.24, 0.0072, -0.0015),  # deep concha center
        )
        rings: List[List[bmesh.types.BMVert]] = []
        for scale_r, x_flare, x_base_off in ring_specs:
            ring: List[bmesh.types.BMVert] = []
            for i in range(n_p):
                ang = (i / float(n_p)) * math.tau
                ca, sa = math.cos(ang), math.sin(ang)
                # Sleek C-ear profile: delicate top helix, slim tapered lower earlobe (ref_head_back.jpg)
                w_scale = 1.02 if sa >= 0.0 else (0.56 + 0.46 * (1.0 + sa))
                ly = -ca * e_ry * w_scale * scale_r
                lz = sa * e_rz * scale_r
                ry = ly * c_t - lz * s_t
                rz = ly * s_t + lz * c_t
                py = e_cy + ry
                pz = e_cz + rz

                # Match slim skull wall width (~0.086m) cleanly
                skull_x = 0.0860 * (1.0 - 0.14 * max(0.0, -sa))
                back_w = _smoothstep(-0.85, 0.72, -ca)
                vert_w = 0.35 + 0.65 * math.cos(sa * math.pi * 0.35)
                px = side_sign * (skull_x + x_base_off + x_flare * back_w * vert_w)
                v = bm.verts.new(Vector((px, py, pz)))
                ring.append(v)
            rings.append(ring)

        for ri in range(len(rings) - 1):
            for i in range(n_p):
                inext = (i + 1) % n_p
                v0, v1 = rings[ri][i], rings[ri][inext]
                v2, v3 = rings[ri + 1][inext], rings[ri + 1][i]
                f = bm.faces.new((v0, v1, v2, v3) if side_sign > 0 else (v1, v0, v3, v2))
                f.smooth = True

        # Cap inner concha center cleanly
        center_v = bm.verts.new(Vector((side_sign * (0.0885 + 0.0085), e_cy + 0.001, e_cz)))
        for i in range(n_p):
            inext = (i + 1) % n_p
            v0, v1 = rings[-1][i], rings[-1][inext]
            f = bm.faces.new((v0, v1, center_v) if side_sign > 0 else (v1, v0, center_v))
            f.smooth = True

        bm.verts.ensure_lookup_table()
        for r in rings:
            for v in r:
                ear_vert_indices.add(v.index)
        ear_vert_indices.add(center_v.index)

    bm.verts.ensure_lookup_table()
    return ear_vert_indices


def _build_head_mesh(
    collar_center: Vector,
    z_neck_cut: float,
) -> Tuple[bpy.types.Object, Set[int], Set[int], Set[int]]:
    """Construct symmetrical quad-loop GhostGirl_Head (~4.2k tris) with dedicated frontal UVs."""
    bm = bmesh.new()
    n_ang = 48

    # Carefully spaced Z stations from collar tuck (z_neck_cut) to crown (1.580)
    z_stops: List[float] = [
        z_neck_cut,
        z_neck_cut + 0.012,
        1.304,
        1.316,
        1.326,
        Z_CHIN,
        1.341,
        1.349,
        1.356,
        1.360,  # mouth_r_mid - 1
        Z_MOUTH,  # mouth_r_mid
        1.371,
        1.379,
        1.388,
        Z_NOSE_TIP,
        1.406,
        1.415,
        1.422,  # eye_r_mid - 1
        Z_EYE,  # eye_r_mid
        1.448,
        Z_BROW,
        1.474,
        1.490,
        1.506,
        1.522,
        1.536,
        1.550,
        1.562,
        1.571,
        1.576,
    ]
    n_rings = len(z_stops)

    grid: List[List[bmesh.types.BMVert]] = []
    for z_val in z_stops:
        ring: List[bmesh.types.BMVert] = []
        for j in range(n_ang):
            theta = (j / float(n_ang)) * math.tau
            pt = _eval_base_head_point(theta, z_val, collar_center, z_neck_cut)
            ring.append(bm.verts.new(pt))
        grid.append(ring)

    for r in range(n_rings - 1):
        for j in range(n_ang):
            jn = (j + 1) % n_ang
            bm.faces.new((grid[r][j], grid[r][jn], grid[r + 1][jn], grid[r + 1][j]))

    crown_v = bm.verts.new((0.0, HEAD_CENTER_Y, Z_CROWN))
    for j in range(n_ang):
        jn = (j + 1) % n_ang
        bm.faces.new((grid[-1][j], grid[-1][jn], crown_v))

    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    # Eye patches (L: cols [2,3,4], R: cols [43,44,45]; rows straddling Z_EYE)
    eye_r_mid = z_stops.index(Z_EYE)
    eye_rows = (eye_r_mid - 1, eye_r_mid)
    eye_ring_records: List[Tuple[float, Vector, List[List[bmesh.types.BMVert]], List[List[bmesh.types.BMVert]]]] = []
    for side_sign, col_indices in ((1.0, (2, 3, 4)), (-1.0, (43, 44, 45))):
        eye_faces: List[bmesh.types.BMFace] = []
        for r in eye_rows:
            for c in col_indices:
                v0, v1 = grid[r][c], grid[r][(c + 1) % n_ang]
                v2, v3 = grid[r + 1][(c + 1) % n_ang], grid[r + 1][c]
                f = next((fc for fc in v0.link_faces if v1 in fc.verts and v2 in fc.verts and v3 in fc.verts), None)
                if f is not None:
                    eye_faces.append(f)

        ring_loops: List[List[bmesh.types.BMVert]] = []
        cur_faces = eye_faces
        for step in range(4):
            b_edges = {e for f in cur_faces for e in f.edges if sum(1 for lf in e.link_faces if lf in cur_faces) == 1}
            ring_loops.append(list({v for e in b_edges for v in e.verts}))
            bmesh.ops.inset_region(
                bm, faces=cur_faces, thickness=0.00075 if step < 2 else 0.00050, depth=0.0, use_even_offset=True
            )
            cur_faces = [f for f in cur_faces if f.is_valid]

        res_dis = bmesh.ops.dissolve_faces(bm, faces=cur_faces, use_verts=False)
        cur_faces = [g for g in res_dis.get("region", []) if isinstance(g, bmesh.types.BMFace) and g.is_valid]
        if not cur_faces:
            cur_faces = [f for f in bm.faces if f.is_valid and all(v in ring_loops[-1] for v in f.verts)]
        b_edges = list({e for f in cur_faces for e in f.edges if sum(1 for lf in e.link_faces if lf in cur_faces) == 1})
        ring_loops.append(list({v for e in b_edges for v in e.verts}))

        bmesh.ops.delete(bm, geom=cur_faces, context="FACES_ONLY")
        socket_loops: List[List[bmesh.types.BMVert]] = []
        cur_edges = b_edges
        for _ in range(3):
            res_ext = bmesh.ops.extrude_edge_only(bm, edges=cur_edges)
            cur_edges = [g for g in res_ext["geom"] if isinstance(g, bmesh.types.BMEdge)]
            socket_loops.append([g for g in res_ext["geom"] if isinstance(g, bmesh.types.BMVert)])
        bmesh.ops.contextual_create(bm, geom=cur_edges)

        eye_c = Vector((side_sign * EYE_X, EYE_Y, EYE_Z))
        eye_ring_records.append((side_sign, eye_c, ring_loops, socket_loops))

    # Mouth patch straddling X=0 (cols 46, 47, 0, 1; rows straddling Z_MOUTH)
    mouth_r_mid = z_stops.index(Z_MOUTH)
    mouth_rows = (mouth_r_mid - 1, mouth_r_mid)
    mouth_faces: List[bmesh.types.BMFace] = []
    for r in mouth_rows:
        for c in (46, 47, 0, 1):
            v0, v1 = grid[r][c], grid[r][(c + 1) % n_ang]
            v2, v3 = grid[r + 1][(c + 1) % n_ang], grid[r + 1][c]
            f = next((fc for fc in v0.link_faces if v1 in fc.verts and v2 in fc.verts and v3 in fc.verts), None)
            if f is not None:
                mouth_faces.append(f)

    mouth_ring_loops: List[List[bmesh.types.BMVert]] = []
    cur_m_faces = mouth_faces
    for step in range(4):
        b_edges = {e for f in cur_m_faces for e in f.edges if sum(1 for lf in e.link_faces if lf in cur_m_faces) == 1}
        mouth_ring_loops.append(list({v for e in b_edges for v in e.verts}))
        bmesh.ops.inset_region(
            bm, faces=cur_m_faces, thickness=0.00055 if step < 2 else 0.00035, depth=0.0, use_even_offset=True
        )
        cur_m_faces = [f for f in cur_m_faces if f.is_valid]

    res_mdis = bmesh.ops.dissolve_faces(bm, faces=cur_m_faces, use_verts=False)
    cur_m_faces = [g for g in res_mdis.get("region", []) if isinstance(g, bmesh.types.BMFace) and g.is_valid]
    if not cur_m_faces:
        cur_m_faces = [f for f in bm.faces if f.is_valid and all(v in mouth_ring_loops[-1] for v in f.verts)]
    m_edges = list({e for f in cur_m_faces for e in f.edges if sum(1 for lf in e.link_faces if lf in cur_m_faces) == 1})
    mouth_ring_loops.append(list({v for e in m_edges for v in e.verts}))

    bmesh.ops.delete(bm, geom=cur_m_faces, context="FACES_ONLY")
    mouth_cavity_loops: List[List[bmesh.types.BMVert]] = []
    cur_m_edges = m_edges
    for _ in range(5):
        res_m = bmesh.ops.extrude_edge_only(bm, edges=cur_m_edges)
        cur_m_edges = [g for g in res_m["geom"] if isinstance(g, bmesh.types.BMEdge)]
        mouth_cavity_loops.append([g for g in res_m["geom"] if isinstance(g, bmesh.types.BMVert)])
    bmesh.ops.contextual_create(bm, geom=cur_m_edges)

    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    for side_sign, eye_c, r_loops, s_loops in eye_ring_records:
        _sculpt_eye_sockets_and_lids(bm, eye_c, side_sign, r_loops, s_loops)

    mouth_bag_indices = _sculpt_mouth_and_cavity(
        bm, mouth_ring_loops, mouth_cavity_loops, collar_center, z_neck_cut
    )

    eye_socket_indices: Set[int] = set()
    feature_indices: Set[int] = set(mouth_bag_indices)
    for _, _, r_loops, s_loops in eye_ring_records:
        for lp in r_loops[1:]:
            for v in lp:
                feature_indices.add(v.index)
        for lp in s_loops:
            for v in lp:
                feature_indices.add(v.index)
                eye_socket_indices.add(v.index)
    for lp in mouth_ring_loops[1:]:
        for v in lp:
            feature_indices.add(v.index)

    ear_indices = _sculpt_ears(bm)
    feature_indices.update(ear_indices)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    # Gentle cheek/cranium/neck smoothing (preserve nose ridge, eyelids, lips, chin, ears!)
    for _ in range(2):
        updates: Dict[int, Vector] = {}
        for v in bm.verts:
            if v.index in feature_indices or not v.link_edges:
                continue
            if v.co.z <= z_neck_cut + 0.006:
                continue
            # Keep nose ridge AND delicate upper/lower lip & chin side-profile crisp
            if v.co.y < -0.115 and abs(v.co.x) < 0.015 and 1.334 <= v.co.z <= 1.425:
                continue
            avg = Vector((0.0, 0.0, 0.0))
            for e in v.link_edges:
                avg += e.other_vert(v).co
            avg /= float(len(v.link_edges))
            updates[v.index] = v.co * 0.72 + avg * 0.28
        for idx, new_co in updates.items():
            bm.verts[idx].co = new_co

    # Enforce strict X=0 mirror symmetry
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        if abs(v.co.x) < 0.0014:
            v.co.x = 0.0
    pos_verts = [v for v in bm.verts if v.co.x > 0.001]
    neg_verts = [v for v in bm.verts if v.co.x < -0.001]
    if pos_verts and neg_verts:
        kd = KDTree(len(pos_verts))
        for i, pv in enumerate(pos_verts):
            kd.insert(pv.co, i)
        kd.balance()
        for nv in neg_verts:
            mir = Vector((-nv.co.x, nv.co.y, nv.co.z))
            _, idx_match, d = kd.find(mir)
            if d < 0.006:
                pv = pos_verts[idx_match]
                avg_x = 0.5 * (pv.co.x - nv.co.x)
                avg_y = 0.5 * (pv.co.y + nv.co.y)
                avg_z = 0.5 * (pv.co.z + nv.co.z)
                pv.co = Vector((avg_x, avg_y, avg_z))
                nv.co = Vector((-avg_x, avg_y, avg_z))

    # Re-clamp eyelid rims strictly outside swept cornea bounds after smoothing/symmetry
    for v in bm.verts:
        if v.index in mouth_bag_indices or v.index in eye_socket_indices:
            continue
        for sx in (1.0, -1.0):
            if v.co.x * sx > 0.005:
                v.co = _clamp_outside_eye_swept(v.co, Vector((sx * EYE_X, EYE_Y, EYE_Z)), margin=0.0020)

    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    # Dedicated Frontal Pelt UV Layout (~70% front face, clean islands for ears, sockets, mouth bag)
    uv_lay = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        fc = f.calc_center_median()
        in_mouth_bag = any(v.index in mouth_bag_indices for v in f.verts)
        in_eye_socket = all(v.index in eye_socket_indices for v in f.verts)
        in_ear = any(v.index in ear_indices for v in f.verts) and abs(fc.x) > 0.072

        ang_c = math.atan2(fc.x, -(fc.y - HEAD_CENTER_Y))
        for loop in f.loops:
            co = loop.vert.co
            if in_mouth_bag:
                u = 0.87 + max(-0.08, min(0.08, co.x * 3.0))
                v_uv = 0.10 + max(-0.055, min(0.055, (co.z - Z_MOUTH) * 2.5))
            elif in_eye_socket:
                side_off = 0.63 if co.x >= 0.0 else 0.69
                u = side_off + max(-0.025, min(0.025, (co.x - math.copysign(EYE_X, co.x)) * 1.1))
                v_uv = 0.09 + max(-0.04, min(0.04, (co.z - EYE_Z) * 2.0))
            elif in_ear:
                side_off = 0.09 if co.x >= 0.0 else 0.25
                u = side_off + max(-0.065, min(0.065, (co.y - EAR_Y_CENTER) * 1.8))
                v_uv = 0.09 + max(-0.065, min(0.065, (co.z - EAR_Z_CENTER) * 1.8))
            else:
                ang = math.atan2(co.x, -(co.y - HEAD_CENTER_Y))
                if abs(co.x) < 1.5e-3 and co.y > HEAD_CENTER_Y:
                    ang = math.pi if fc.x >= 0.0 else -math.pi
                if ang - ang_c > math.pi:
                    ang -= math.tau
                elif ang - ang_c < -math.pi:
                    ang += math.tau
                ang = max(-math.pi, min(math.pi, ang))
                ang_norm = ang / math.pi
                sign_a = 1.0 if ang_norm >= 0.0 else -1.0
                abs_a = abs(ang_norm)
                if abs_a <= 0.42:
                    u_mapped = sign_a * (abs_a / 0.42) * 0.36
                else:
                    u_mapped = sign_a * (0.36 + ((abs_a - 0.42) / 0.58) * 0.10)
                u = 0.50 + u_mapped
                t_z = max(0.0, min(1.0, (co.z - z_neck_cut) / max(Z_CROWN - z_neck_cut, 1e-4)))
                v_uv = 0.18 + t_z * 0.77
            loop[uv_lay].uv = (max(0.01, min(0.99, u)), max(0.01, min(0.99, v_uv)))

    mesh = bpy.data.meshes.new("GhostGirl_Head")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True

    head_obj = bpy.data.objects.new("GhostGirl_Head", mesh)
    bpy.context.collection.objects.link(head_obj)
    head_obj.data.calc_loop_triangles()
    print(f"[ghost_girl_head] Built GhostGirl_Head: {len(head_obj.data.vertices)} verts, {len(head_obj.data.loop_triangles)} tris")
    return head_obj, mouth_bag_indices, eye_socket_indices, ear_indices


# ---------------------------------------------------------------------------
# Custom Anime Face Split Normals (Blender 5.3)
# ---------------------------------------------------------------------------

def apply_anime_face_normals(
    head_obj: bpy.types.Object,
    lm: Optional[Dict[str, Any]] = None,
) -> None:
    """Apply smooth ellipsoidal anime split vertex normals on anterior face features.

    Idempotently computes raw geometric smooth normals from polygon faces, blends 85-95%
    toward a smooth ellipsoidal field over cheeks/brow/nose-bridge/chin, and tapers smoothly
    on ears, neck, inner eyelid rims, and oral cavity before calling
    `mesh.normals_split_custom_set_from_vertices(...)`.
    """
    mesh = head_obj.data
    for poly in mesh.polygons:
        poly.use_smooth = True

    # Compute pure area-weighted geometric vertex normals (100% independent of prior custom normals)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    geom_normals: List[Vector] = [v.normal.copy() for v in bm.verts]
    bm.free()

    # Resolve reference coordinates from lm when provided (e.g. re-run inside rig_ghost_girl.py)
    le = Vector(lm["left_eye"]) if (lm and "left_eye" in lm) else Vector((EYE_X, EYE_Y, EYE_Z))
    chin = Vector(lm["chin"]) if (lm and "chin" in lm) else Vector((0.0, -0.1125, Z_CHIN))
    mouth = Vector(lm["mouth"]) if (lm and "mouth" in lm) else Vector((0.0, -0.1265, Z_MOUTH))
    ear_y = lm["ear_y"].y if (lm and "ear_y" in lm) else EAR_Y_CENTER

    # Ellipsoidal center behind face plane so normals radiate smoothly across cheeks, nose, lips
    e_center = Vector((0.0, le.y + 0.068, le.z - 0.018))
    inv_rx2 = 1.0 / (0.095 ** 2)
    inv_ry2 = 1.0 / (0.112 ** 2)
    inv_rz2 = 1.0 / (0.122 ** 2)

    # Exact topological detection via preserved head UV islands (prevents leaking onto exterior skin!)
    bag_verts: Set[int] = set()
    socket_verts: Set[int] = set()
    uv_layer = mesh.uv_layers.active
    if uv_layer is not None:
        uv_data = uv_layer.data
        for poly in mesh.polygons:
            uvs = [uv_data[li].uv for li in poly.loop_indices]
            if all(uv[0] > 0.74 and uv[1] < 0.17 for uv in uvs):
                for vi in poly.vertices:
                    bag_verts.add(vi)
            elif all(0.57 < uv[0] < 0.74 and uv[1] < 0.17 for uv in uvs):
                for vi in poly.vertices:
                    socket_verts.add(vi)

    custom_normals: List[Vector] = []
    for idx, v in enumerate(mesh.vertices):
        p = v.co
        g_n = geom_normals[idx]
        if g_n.length_squared < 1e-10:
            g_n = Vector((0.0, -1.0, 0.0))
        else:
            g_n.normalize()

        # Analytical outward normal of smooth face ellipsoid
        rel = p - e_center
        e_n = Vector((rel.x * inv_rx2, rel.y * inv_ry2, rel.z * inv_rz2))
        if e_n.length_squared < 1e-10:
            e_n = g_n.copy()
        else:
            e_n.normalize()

        # Anterior face mask: cheeks, brow, forehead, nose bridge, mouth exterior, chin
        w_front = _smoothstep(ear_y + 0.015, ear_y - 0.032, p.y)
        w_lat = 1.0 - _smoothstep(0.068, 0.094, abs(p.x))
        w_chin = _smoothstep(chin.z - 0.014, chin.z + 0.002, p.z)
        w_crown = 1.0 - _smoothstep(Z_CROWN - 0.035, Z_CROWN, p.z)
        w = 0.95 * w_front * w_lat * w_chin * (0.45 + 0.55 * w_crown)

        # Preserve crisp subtle shading on back cranium (moderate smooth blend)
        if p.y > ear_y - 0.015 and p.z > chin.z + 0.01:
            w = max(w, 0.30 * (1.0 - _smoothstep(0.074, 0.092, abs(p.x))))

        # Taper smoothly down around ears so helix/concha retain clean definition
        if abs(p.x) > 0.072 and (ear_y - 0.025) <= p.y <= (ear_y + 0.025):
            w_ear = _smoothstep(0.072, 0.088, abs(p.x))
            w *= 1.0 - 0.85 * w_ear

        # Taper ONLY interior orbital socket vertices (keep outer eyelid rims 100% smooth!)
        if idx in socket_verts:
            w *= 0.15

        # Keep interior oral cavity bag smooth forward-upward normals (leave front lip rim on ellipsoid!)
        if idx in bag_verts and p.y > -0.1225:
            e_n = Vector((0.0, -0.96, 0.28)).normalized()
            w = 0.88

        # Taper cleanly to 0 on lower neck cylinder so neck meets body collar naturally
        if p.z < chin.z - 0.004:
            w *= _smoothstep(chin.z - 0.024, chin.z - 0.004, p.z)

        blended = g_n.lerp(e_n, max(0.0, min(0.96, w)))
        if blended.length_squared < 1e-10:
            blended = g_n
        else:
            blended.normalize()
        custom_normals.append(blended)

    mesh.normals_split_custom_set_from_vertices(custom_normals)
    mesh.update()


# ---------------------------------------------------------------------------
# Texture Painting (2K Head Atlas, 1K Eye Atlas, 512 Lash, Mouth & Tongue)
# ---------------------------------------------------------------------------

def _rasterize_head_uv_attributes(
    head_obj: bpy.types.Object,
    mouth_bag_indices: Set[int],
    eye_socket_indices: Set[int],
    ear_indices: Set[int],
    size: int = 2048,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Rasterize 3D positions and region masks onto the 2048x2048 head UV atlas."""
    mesh = head_obj.data
    mesh.calc_loop_triangles()
    uv_lay = mesh.uv_layers.active.data

    pos = np.zeros((size, size, 3), dtype=np.float32)
    valid = np.zeros((size, size), dtype=bool)
    mouth_bag = np.zeros((size, size), dtype=bool)
    socket_map = np.zeros((size, size), dtype=bool)
    ear_map = np.zeros((size, size), dtype=np.float32)

    verts_co = np.array([v.co[:] for v in mesh.vertices], dtype=np.float32)
    ear_w = np.zeros(len(mesh.vertices), dtype=np.float32)
    for ei in ear_indices:
        ear_w[ei] = 1.0

    for tri in mesh.loop_triangles:
        vi = tri.vertices
        li = tri.loops
        uv0 = uv_lay[li[0]].uv
        uv1 = uv_lay[li[1]].uv
        uv2 = uv_lay[li[2]].uv
        px0, py0 = uv0[0] * (size - 1), (1.0 - uv0[1]) * (size - 1)
        px1, py1 = uv1[0] * (size - 1), (1.0 - uv1[1]) * (size - 1)
        px2, py2 = uv2[0] * (size - 1), (1.0 - uv2[1]) * (size - 1)

        min_x = max(0, int(math.floor(min(px0, px1, px2))))
        max_x = min(size - 1, int(math.ceil(max(px0, px1, px2))))
        min_y = max(0, int(math.floor(min(py0, py1, py2))))
        max_y = min(size - 1, int(math.ceil(max(py0, py1, py2))))
        if max_x < min_x or max_y < min_y:
            continue

        denom = (py1 - py2) * (px0 - px2) + (px2 - px1) * (py0 - py2)
        if abs(denom) < 1e-6:
            continue
        inv_d = 1.0 / denom

        xs = np.arange(min_x, max_x + 1, dtype=np.float32)
        ys = np.arange(min_y, max_y + 1, dtype=np.float32)
        gx, gy = np.meshgrid(xs, ys)
        w0 = ((py1 - py2) * (gx - px2) + (px2 - px1) * (gy - py2)) * inv_d
        w1 = ((py2 - py0) * (gx - px2) + (px0 - px2) * (gy - py2)) * inv_d
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -0.002) & (w1 >= -0.002) & (w2 >= -0.002)
        if not np.any(inside):
            continue

        iy, ix = np.where(inside)
        b0 = w0[iy, ix][:, None]
        b1 = w1[iy, ix][:, None]
        b2 = w2[iy, ix][:, None]
        py_i = min_y + iy
        px_i = min_x + ix

        pos[py_i, px_i] = b0 * verts_co[vi[0]] + b1 * verts_co[vi[1]] + b2 * verts_co[vi[2]]
        valid[py_i, px_i] = True
        ear_map[py_i, px_i] = b0[:, 0] * ear_w[vi[0]] + b1[:, 0] * ear_w[vi[1]] + b2[:, 0] * ear_w[vi[2]]
        if any(int(v) in mouth_bag_indices for v in vi):
            mouth_bag[py_i, px_i] = True
        elif all(int(v) in eye_socket_indices for v in vi):
            socket_map[py_i, px_i] = True

    return pos, valid, mouth_bag, socket_map, ear_map


def _generate_head_textures(
    head_obj: bpy.types.Object,
    mouth_bag_indices: Set[int],
    eye_socket_indices: Set[int],
    ear_indices: Set[int],
    tex_dir: Path,
) -> Tuple[Path, Path]:
    """Paint 2K warm peach anime face atlas (brows, lid fold, blush, nose dot, mouth line) + ORM."""
    size = 2048
    pos, valid, mouth_bag, socket_map, ear_map = _rasterize_head_uv_attributes(
        head_obj, mouth_bag_indices, eye_socket_indices, ear_indices, size=size
    )

    base_skin = np.array(SKIN_PEACH_RGB, dtype=np.float32)  # #FDE6DA
    blush_col = np.array([0.968, 0.725, 0.705], dtype=np.float32)
    shadow_col = np.array([0.910, 0.750, 0.720], dtype=np.float32)
    brow_col = np.array([0.340, 0.250, 0.480], dtype=np.float32)
    brow_dark = np.array([0.115, 0.072, 0.205], dtype=np.float32)
    mouth_line_col = np.array([0.160, 0.068, 0.082], dtype=np.float32)
    oral_col = np.array([0.860, 0.340, 0.400], dtype=np.float32)

    albedo = np.broadcast_to(base_skin[None, None, :], (size, size, 3)).copy()
    ys_c, xs_c = np.where(valid)
    P = pos[ys_c, xs_c]
    px, py, pz = P[:, 0], P[:, 1], P[:, 2]
    is_bag = mouth_bag[ys_c, xs_c]
    is_sock = socket_map[ys_c, xs_c]
    ear_w = ear_map[ys_c, xs_c]

    col = np.broadcast_to(base_skin[None, :], (len(px), 3)).copy()
    is_front = (py < EAR_Y_CENTER - 0.015) & (~is_bag) & (~is_sock)

    # 1. Soft ear concha peach-shadow
    w_ear = np.clip(ear_w * 0.38, 0.0, 0.38)[:, None]
    col = col * (1.0 - w_ear) + shadow_col[None, :] * w_ear

    # 2. Inner orbital socket soft warm peach shading behind eyeball
    sock_w = np.where(is_sock, 0.42, 0.0)[:, None]
    col = col * (1.0 - sock_w) + (shadow_col * 0.90)[None, :] * sock_w

    # 3. Soft cheek blush ovals on mid-cheeks (well below eye rims!)
    for sx in (1.0, -1.0):
        d_chk = ((px - sx * 0.044) / 0.017) ** 2 + ((pz - (EYE_Z - 0.032)) / 0.0085) ** 2
        w_chk = np.where(is_front, np.exp(-0.5 * d_chk) * 0.22, 0.0)[:, None]
        col = col * (1.0 - w_chk) + blush_col[None, :] * w_chk

    # 4. Delicate tiny anime nose dot right beneath tip (ref_head_front_side.jpg)
    d_nose = (px / 0.00085) ** 2 + ((pz - (Z_NOSE_TIP - 0.0012)) / 0.0013) ** 2
    w_nose = np.where(is_front & (py < -0.128), np.exp(-0.5 * d_nose) * 0.56, 0.0)[:, None]
    nose_dot_col = np.array([0.745, 0.565, 0.550], dtype=np.float32)
    col = col * (1.0 - w_nose) + nose_dot_col[None, :] * w_nose

    # 5. Crisp minimal closed mouth crease line strictly on anterior outer seam (zero pink outer box!)
    mouth_u = np.abs(px) / 0.0080
    center_gap = 1.0 - 0.28 * np.exp(-0.5 * (px / 0.0009) ** 2)
    mouth_stroke = (
        np.exp(-0.5 * ((pz - Z_MOUTH) / 0.00046) ** 2)
        * np.clip(1.0 - mouth_u ** 2.8, 0.0, 1.0)
        * center_gap
    )
    w_mline = np.where(is_front & (py < -0.1225), np.clip(mouth_stroke * 0.90, 0.0, 0.90), 0.0)[:, None]
    col = col * (1.0 - w_mline) + mouth_line_col[None, :] * w_mline

    # 6. Thin crisp arched lavender-grey anime eyebrows matching ref_head_front_side.jpg
    for sx in (1.0, -1.0):
        # Inner brow ~0.015, peak ~0.037, outer tail ~0.059
        bx = (px * sx - 0.0375) / 0.0220
        arch_z = Z_BROW + 0.0028 * (1.0 - bx * bx) - 0.0008 * bx
        brow_dist = np.abs(pz - arch_z)
        thick = 0.00180 * np.clip(1.0 - (np.abs(bx) ** 2.2), 0.0, 1.0) + 0.00028
        brow_a = np.clip(1.0 - (brow_dist / np.maximum(thick, 1e-4)) ** 2, 0.0, 1.0)
        brow_a *= np.clip(1.0 - (np.abs(bx) ** 3.2), 0.0, 1.0)
        w_brow = np.where(is_front & (np.abs(bx) < 1.02) & (py < -0.105), brow_a * 0.96, 0.0)[:, None]
        core_a = np.clip(brow_a * 1.15 - 0.22, 0.0, 1.0)[:, None]
        b_col = brow_col[None, :] * (1.0 - 0.55 * core_a) + brow_dark[None, :] * (0.55 * core_a)
        col = col * (1.0 - w_brow) + b_col * w_brow

    # 7. Ultra-delicate upper-eyelid fold crease arc (NO dark rim bleed on eyelid skin so Blink stays spotless!)
    for sx in (1.0, -1.0):
        ex_u = (px * sx - EYE_X) / 0.0202
        canthus_lift = 0.0014 * ex_u
        upper_rim_z = EYE_Z + 0.0122 * np.sqrt(np.clip(1.0 - ex_u * ex_u, 0.0, 1.0)) + canthus_lift + 0.0006
        fold_z = upper_rim_z + 0.0036
        fold_w = np.exp(-0.5 * ((pz - fold_z) / 0.00038) ** 2) * np.clip(1.0 - (np.abs(ex_u) / 0.72) ** 2, 0.0, 1.0)
        w_fold = np.where(is_front & (np.abs(ex_u) < 0.72) & (py < -0.105), fold_w * 0.18, 0.0)[:, None]
        col = col * (1.0 - w_fold) + (shadow_col * 0.88)[None, :] * w_fold

    # 8. Warm soft coral interior oral cavity bag (visible only on jawOpen)
    bag_w = np.where(is_bag, 1.0, 0.0)[:, None]
    col = col * (1.0 - bag_w) + oral_col[None, :] * bag_w

    albedo[ys_c, xs_c] = np.clip(col, 0.0, 1.0)
    albedo = _dilate_rgb_padding(albedo, valid, steps=12)

    alb_path = tex_dir / "ghost_girl_head_albedo.png"
    _save_image_array(alb_path, np.clip(albedo, 0.0, 1.0))

    # Clean matte cel skin ORM (R=AO 0.98, G=Roughness 0.64, B=Metallic 0.0)
    orm = np.zeros((size, size, 3), dtype=np.float32)
    orm[:, :, 0] = 0.98
    orm[:, :, 1] = 0.64
    orm[:, :, 2] = 0.0
    orm[mouth_bag, 0] = 0.85
    orm[mouth_bag, 1] = 0.34
    orm[socket_map, 0] = 0.86
    ear_ao_mask = valid & (ear_map > 0.4)
    orm[ear_ao_mask, 0] = 0.88

    orm_path = tex_dir / "ghost_girl_head_orm.png"
    _save_image_array(orm_path, orm)
    return alb_path, orm_path


def _generate_eye_textures(tex_dir: Path) -> Tuple[Path, Path]:
    """Generate 1K layered lavender-violet iris centered at (0.5, 0.5), radius 0.30, ZERO catchlights."""
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz - 1)
    dx = xx - 0.5
    dy = yy - 0.5  # dy < 0 is TOP of eye, dy > 0 is BOTTOM of eye
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)

    iris_r = 0.300
    iris_mask = r <= iris_r

    img = np.zeros((sz, sz, 3), dtype=np.float32)
    # Clean crisp anime sclera (#FCFAFF)
    img[:, :, 0] = 0.988
    img[:, :, 1] = 0.980
    img[:, :, 2] = 1.000

    # Rich multi-layered lavender-violet iris (deep plum-violet top -> radiant lilac bottom)
    grad_y = np.clip((dy / iris_r + 1.0) * 0.5, 0.0, 1.0)
    spokes = 0.5 + 0.5 * np.cos(ang * 28.0)
    spokes2 = 0.5 + 0.5 * np.sin(ang * 56.0 + r * 35.0)
    fiber = 0.6 * spokes + 0.4 * spokes2

    col_top = np.array([0.310, 0.220, 0.580], dtype=np.float32)
    col_mid = np.array([0.625, 0.510, 0.900], dtype=np.float32)
    col_bot = np.array([0.895, 0.820, 1.000], dtype=np.float32)

    t_low = np.clip(grad_y / 0.52, 0.0, 1.0)[:, :, None]
    t_high = np.clip((grad_y - 0.52) / 0.48, 0.0, 1.0)[:, :, None]
    iris_col = np.where(
        (grad_y < 0.52)[:, :, None],
        col_top[None, None, :] * (1.0 - t_low) + col_mid[None, None, :] * t_low,
        col_mid[None, None, :] * (1.0 - t_high) + col_bot[None, None, :] * t_high,
    )
    # Subtle lower crescent glow & radial fiber texture
    crescent = np.exp(-0.5 * ((dy - 0.14) / 0.09) ** 2) * np.clip(1.0 - (r / iris_r) ** 2, 0.0, 1.0)
    iris_col = np.clip(
        iris_col + (fiber[:, :, None] - 0.5) * 0.055 + crescent[:, :, None] * np.array([0.10, 0.08, 0.14], dtype=np.float32),
        0.0,
        1.0,
    )

    # Dark limbal outline ring at outer 16% of iris radius
    u_ir = r / iris_r
    rim_w = np.clip((u_ir - 0.83) / 0.17, 0.0, 1.0)[:, :, None]
    limbal_col = np.array([0.135, 0.095, 0.275], dtype=np.float32)
    iris_col = iris_col * (1.0 - 0.86 * rim_w) + limbal_col[None, None, :] * (0.86 * rim_w)

    aa_iris = np.clip((iris_r + 0.008 - r) / 0.012, 0.0, 1.0)[:, :, None]
    img = img * (1.0 - aa_iris) + iris_col * aa_iris

    # Dark vertical-oval anime pupil (matching ref_head_front_side.jpg)
    r_pup = np.sqrt((dx / 0.092) ** 2 + (dy / 0.112) ** 2)
    aa_pup = np.clip((1.0 - r_pup) / 0.055, 0.0, 1.0)[:, :, None]
    pup_col = np.array([0.015, 0.008, 0.042], dtype=np.float32)
    img = img * (1.0 - aa_pup) + pup_col[None, None, :] * aa_pup

    # Soft upper-lid cast shadow across top of sclera & upper iris (dy < -0.05)
    upper_sh = np.clip((-dy - 0.05) / 0.18, 0.0, 1.0)[:, :, None]
    sh_tint = np.array([0.76, 0.73, 0.89], dtype=np.float32)
    img = img * (1.0 - 0.34 * upper_sh) + (img * sh_tint[None, None, :]) * (0.34 * upper_sh)

    # Soft warm sclera edge shadow near outer corners (r > 0.38)
    periph = np.clip((r - 0.38) / 0.12, 0.0, 1.0)[:, :, None]
    sclera_rim = np.array([0.88, 0.81, 0.87], dtype=np.float32)
    img = img * (1.0 - 0.45 * periph) + sclera_rim[None, None, :] * (0.45 * periph)

    # ZERO baked white catchlights (anime_eye.gdshader renders dynamic catchlights cleanly!)
    alb_path = tex_dir / "ghost_girl_eye_albedo.png"
    _save_image_array(alb_path, img)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.98
    orm[:, :, 1] = np.where(iris_mask, 0.05, 0.14)
    orm[:, :, 2] = 0.0
    orm_path = tex_dir / "ghost_girl_eye_orm.png"
    _save_image_array(orm_path, orm)
    return alb_path, orm_path


def _generate_lash_texture(tex_dir: Path) -> Path:
    """Generate 1024x1024 RGBA crisp bold anime upper arch + sleek single wing + delicate lower ticks."""
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz - 1)
    v_uv = 1.0 - yy

    alpha = np.zeros((sz, sz), dtype=np.float32)

    # 1. Upper lash region (v_uv in [0.0, 0.56]): bold crisp solid anime eyeliner arch + sleek upturned wing (>)
    t_up = np.clip(v_uv / 0.52, 0.0, 1.0)
    in_upper = v_uv <= 0.57
    arch_center_h = np.where(
        xx < 0.78,
        0.40 + 0.42 * np.sin(np.clip((xx - 0.01) / 0.84, 0.0, 1.0) * math.pi * 0.76),
        0.78 * np.clip(1.0 - np.maximum(0.0, (xx - 0.78) / 0.21) ** 1.00, 0.0, 1.0),
    )
    wing_lift = 0.34 * np.clip((xx - 0.64) / 0.35, 0.0, 1.0) ** 1.25
    wing_top = np.minimum(0.99, wing_lift + arch_center_h)
    solid_arch = (
        np.clip((t_up - wing_lift + 0.014) / 0.014, 0.0, 1.0)
        * np.clip((wing_top - t_up) / 0.014, 0.0, 1.0)
        * np.clip(xx / 0.022, 0.0, 1.0)
        * np.clip((0.995 - xx) / 0.015, 0.0, 1.0)
    )
    # 2 tiny crisp upper outer accent tips cleanly rooted ON the arch top (never below wing_lift!)
    accent = np.zeros_like(alpha)
    for u0, h0 in ((0.74, 0.86), (0.82, 0.96)):
        dist = np.abs(xx - (u0 + 0.03 * np.maximum(0.0, t_up - wing_lift)))
        w_t = 0.018 * np.maximum(0.0, 1.0 - t_up / h0) ** 0.82
        tip_mask = np.clip((w_t - dist) / 0.005, 0.0, 1.0) * (t_up >= wing_lift + 0.14) * (t_up <= h0)
        accent = np.maximum(accent, tip_mask)
    alpha = np.where(in_upper, np.maximum(solid_arch, accent), alpha)

    # 2. Lower lash region (v_uv in [0.62, 0.96]): 3 crisp delicate lower ticks + fine outer corner rim
    t_lo = np.clip((v_uv - 0.64) / 0.30, 0.0, 1.0)
    in_lower = v_uv >= 0.62
    lower_ticks = np.zeros_like(alpha)
    for u0, l_len in ((0.64, 0.48), (0.74, 0.60), (0.84, 0.52)):
        dist = np.abs(xx - (u0 + 0.022 * t_lo))
        w_t = 0.012 * np.maximum(0.0, 1.0 - t_lo / l_len) ** 0.80
        lower_ticks = np.maximum(lower_ticks, np.clip((w_t - dist) / 0.004, 0.0, 1.0) * (t_lo <= l_len))
    lower_hairline = (
        np.clip((0.12 - t_lo) / 0.025, 0.0, 1.0)
        * np.clip((xx - 0.52) / 0.08, 0.0, 1.0)
        * np.clip((0.992 - xx) / 0.03, 0.0, 1.0)
    )
    alpha = np.where(in_lower, np.maximum(lower_hairline, lower_ticks), alpha)

    rgba = np.zeros((sz, sz, 4), dtype=np.float32)
    rgba[:, :, 0] = 0.012
    rgba[:, :, 1] = 0.007
    rgba[:, :, 2] = 0.028
    rgba[:, :, 3] = np.clip(alpha, 0.0, 1.0)

    out_path = tex_dir / "ghost_girl_lash_albedo.png"
    _save_image_array(out_path, rgba)
    return out_path


def _generate_mouth_and_tongue_textures(tex_dir: Path) -> Tuple[Path, Path]:
    """Generate clean stylized anime teeth/gum and coral-pink tongue textures."""
    sz = 512
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz - 1)
    v_uv = 1.0 - yy  # 0 bottom, 1 top

    # Teeth + gum atlas (v_uv < 0.72 enamel, >= 0.72 soft pink gum)
    ivory = np.array([0.985, 0.972, 0.960], dtype=np.float32)
    shade = np.array([0.915, 0.895, 0.905], dtype=np.float32)
    gum = np.array([0.840, 0.505, 0.545], dtype=np.float32)
    # Very gentle anime tooth divider hints (never noisy realistic grooves!)
    grooves = np.abs(np.sin(xx * 8.0 * math.pi)) ** 0.22
    t_col = shade[None, None, :] * (1.0 - grooves[:, :, None]) + ivory[None, None, :] * grooves[:, :, None]
    gum_w = np.clip((v_uv - 0.70) / 0.06, 0.0, 1.0)[:, :, None]
    mouth_img = t_col * (1.0 - gum_w) + gum[None, None, :] * gum_w
    mouth_path = tex_dir / "ghost_girl_mouth_albedo.png"
    _save_image_array(mouth_path, mouth_img)

    # Stylized soft coral-pink tongue atlas
    tg_base = np.array([0.780, 0.405, 0.460], dtype=np.float32)
    tg_tip = np.array([0.945, 0.585, 0.625], dtype=np.float32)
    t_len = np.clip(v_uv, 0.0, 1.0)[:, :, None]
    groove = np.exp(-0.5 * ((xx - 0.5) / 0.04) ** 2) * 0.10
    tg_img = (tg_base[None, None, :] * (1.0 - t_len) + tg_tip[None, None, :] * t_len) * (1.0 - groove[:, :, None])
    tongue_path = tex_dir / "ghost_girl_tongue_albedo.png"
    _save_image_array(tongue_path, tg_img)
    return mouth_path, tongue_path


# ---------------------------------------------------------------------------
# Modular Sub-Meshes: Eyes, Eyelashes, Teeth Upper/Lower, Tongue
# ---------------------------------------------------------------------------

def _build_anime_eye(
    name: str,
    center: Vector,
    eye_mat: bpy.types.Material,
) -> bpy.types.Object:
    """Build GhostGirl_Eye_L/R slightly flattened curved anime dome centered at UV (0.5, 0.5)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=26, v_segments=16, radius=1.0)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(math.radians(90.0), 3, "X"))

    # Ellipsoid dimensions: rx=0.0195, ry=0.0145, rz=0.0160 (curved anime cornea dome!)
    for v in bm.verts:
        v.co.x *= EYE_RX
        v.co.y *= EYE_RY
        v.co.z *= EYE_RZ

    # Map front (-Y) iris linearly out to uv_r=0.30 at r_3d = 0.0128m, shifted +0.8mm in Z so upper lid overlaps ~15% iris
    iris_r_3d = 0.0128
    uv_lay = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        f.smooth = True
        for loop in f.loops:
            p = loop.vert.co
            pz_shift = p.z - 0.0008
            r_xz = math.sqrt(p.x * p.x + pz_shift * pz_shift)
            if p.y <= 0.002:
                if r_xz <= iris_r_3d:
                    uv_r = (r_xz / iris_r_3d) * 0.300
                else:
                    uv_r = 0.300 + ((r_xz - iris_r_3d) / max(EYE_RX - iris_r_3d, 0.004)) * 0.165
                uv_r = min(0.475, uv_r)
                ang = math.atan2(pz_shift, p.x)
                u = 0.5 + uv_r * math.cos(ang)
                v_uv = 0.5 + uv_r * math.sin(ang)
            else:
                # Posterior hemisphere sits cleanly on sclera edge
                ang = math.atan2(p.z, p.x)
                u = 0.5 + 0.48 * math.cos(ang)
                v_uv = 0.5 + 0.48 * math.sin(ang)
            loop[uv_lay].uv = (max(0.01, min(0.99, u)), max(0.01, min(0.99, v_uv)))

    for v in bm.verts:
        v.co += center

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(eye_mat)
    bpy.context.collection.objects.link(obj)
    return obj


def _build_anime_eyelashes(lash_mat: bpy.types.Material) -> bpy.types.Object:
    """Build GhostGirl_Eyelashes hugging upper & lower almond rims with upturned outer wings."""
    bm = bmesh.new()
    uv_lay = bm.loops.layers.uv.new("UVMap")
    n_u = 28
    n_v = 4

    for side_sign in (1.0, -1.0):
        eye_c = Vector((side_sign * EYE_X, EYE_Y, EYE_Z))
        for is_upper, v_uv_lo, v_uv_hi, lash_h, lash_fwd in (
            (True, 0.02, 0.54, 0.0054, 0.0014),
            (False, 0.63, 0.94, 0.0020, 0.0008),
        ):
            grid: List[List[bmesh.types.BMVert]] = []
            for iv in range(n_v):
                tv = iv / float(n_v - 1)
                row: List[bmesh.types.BMVert] = []
                for iu in range(n_u):
                    tu = iu / float(n_u - 1)  # 0 inner canthus -> 1 outer canthus
                    ang = math.pi * (1.0 - tu) if side_sign > 0 else tu * math.pi
                    if not is_upper:
                        ang = -ang
                    rim_pt = _eye_rim_target(ang, side_sign, eye_c, t_lid=1.0)
                    # Seat upper lash on rim over top iris; tuck lower lash tightly onto lower lid margin (zero corner gap!)
                    root_pt = rim_pt + Vector((0.0, -0.0010 if is_upper else -0.0005, -0.0007 if is_upper else 0.0006))

                    wing_flare = 0.0074 * _smoothstep(0.64, 1.0, tu) if is_upper else 0.0012 * _smoothstep(0.68, 1.0, tu)
                    curl_z = (lash_h * tv + wing_flare * 0.52 * tv) * (1.0 if is_upper else -0.85)
                    flare_y = -lash_fwd * tv
                    flare_x = side_sign * (0.0010 * tv * max(0.0, tu - 0.28) + wing_flare * tv)

                    pt = root_pt + Vector((flare_x, flare_y, curl_z))
                    pt = _clamp_outside_eye_swept(pt, eye_c, margin=0.0022)
                    # Keep outer wing strictly in front of temple/cheek skin so wing NEVER buries inside cheek!
                    ang_h = math.atan2(pt.x, 0.105)
                    h_surf = _eval_base_head_point(ang_h, pt.z, Vector((0.0, -0.002, Z_NECK_CUT_DEFAULT)), Z_NECK_CUT_DEFAULT)
                    if pt.y > h_surf.y - 0.0015:
                        pt.y = h_surf.y - 0.0015
                    row.append(bm.verts.new(pt))
                grid.append(row)

            for iv in range(n_v - 1):
                for iu in range(n_u - 1):
                    v0, v1 = grid[iv][iu], grid[iv][iu + 1]
                    v2, v3 = grid[iv + 1][iu + 1], grid[iv + 1][iu]
                    f = bm.faces.new((v0, v1, v2, v3) if (is_upper == (side_sign > 0)) else (v1, v0, v3, v2))
                    f.smooth = True
                    u0 = iu / float(n_u - 1)
                    u1 = (iu + 1) / float(n_u - 1)
                    v_a = v_uv_lo + (v_uv_hi - v_uv_lo) * (iv / float(n_v - 1))
                    v_b = v_uv_lo + (v_uv_hi - v_uv_lo) * ((iv + 1) / float(n_v - 1))
                    uvs = [(u0, v_a), (u1, v_a), (u1, v_b), (u0, v_b)]
                    if not (is_upper == (side_sign > 0)):
                        uvs = [uvs[1], uvs[0], uvs[3], uvs[2]]
                    for l, uv in zip(f.loops, uvs):
                        l[uv_lay].uv = uv

    bm.normal_update()
    mesh = bpy.data.meshes.new("GhostGirl_Eyelashes")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True

    obj = bpy.data.objects.new("GhostGirl_Eyelashes", mesh)
    obj.data.materials.append(lash_mat)
    bpy.context.collection.objects.link(obj)
    return obj


def _build_dental_arch(name: str, is_upper: bool, mouth_mat: bpy.types.Material) -> bpy.types.Object:
    """Build smooth stylized anime upper/lower dental arch tucked cleanly behind closed neutral lips."""
    bm = bmesh.new()
    uv_lay = bm.loops.layers.uv.new("UVMap")
    n_u, n_v = 28, 5
    arch_w = 0.0124 if is_upper else 0.0114
    arch_d = 0.0150 if is_upper else 0.0140
    y_front = -0.1195 if is_upper else -0.1170
    z_edge = Z_MOUTH + (0.0001 if is_upper else -0.0040)
    h_arch = 0.0075

    grid: List[List[bmesh.types.BMVert]] = []
    for iv in range(n_v):
        tv = iv / float(n_v - 1)
        row: List[bmesh.types.BMVert] = []
        for iu in range(n_u):
            tu = iu / float(n_u - 1)
            ang = -math.pi * 0.42 + tu * math.pi * 0.84
            x = math.sin(ang) * arch_w
            y = y_front + (1.0 - math.cos(ang)) * arch_d
            z = z_edge + (h_arch * tv if is_upper else -h_arch * tv)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)

    for iv in range(n_v - 1):
        for iu in range(n_u - 1):
            v0, v1 = grid[iv][iu], grid[iv][iu + 1]
            v2, v3 = grid[iv + 1][iu + 1], grid[iv + 1][iu]
            f = bm.faces.new((v0, v1, v2, v3) if is_upper else (v1, v0, v3, v2))
            f.smooth = True
            for idx_l, l in enumerate(f.loops):
                cu = (iu + (1 if idx_l in (1, 2) else 0)) / float(n_u - 1)
                cv = (iv + (1 if idx_l in (2, 3) else 0)) / float(n_v - 1)
                if not is_upper:
                    cu = (iu + (1 if idx_l in (0, 3) else 0)) / float(n_u - 1)
                l[uv_lay].uv = (0.05 + cu * 0.90, 0.08 + cv * 0.82)

    back_row: List[bmesh.types.BMVert] = []
    for iu in range(n_u):
        p = grid[0][iu].co
        back_row.append(bm.verts.new((p.x * 0.90, p.y + 0.0025, p.z + (0.0018 if is_upper else -0.0018))))
    for iu in range(n_u - 1):
        f = bm.faces.new(
            (grid[0][iu + 1], grid[0][iu], back_row[iu], back_row[iu + 1])
            if is_upper
            else (grid[0][iu], grid[0][iu + 1], back_row[iu + 1], back_row[iu])
        )
        f.smooth = True
        for l in f.loops:
            l[uv_lay].uv = (0.5, 0.35)

    bm.normal_update()
    for f in bm.faces:
        fc = f.calc_center_median()
        out_dir = Vector((fc.x, fc.y - (-0.095), 0.0))
        if f.normal.dot(out_dir) < 0.0:
            f.normal_flip()
    bm.normal_update()

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mouth_mat)
    bpy.context.collection.objects.link(obj)
    return obj


def _build_tongue(tongue_mat: bpy.types.Material) -> bpy.types.Object:
    """Build smooth stylized anime tongue tucked cleanly inside lower dental arch."""
    bm = bmesh.new()
    uv_lay = bm.loops.layers.uv.new("UVMap")
    n_rings, n_seg = 9, 14
    rings: List[List[bmesh.types.BMVert]] = []
    for ir in range(n_rings):
        t = ir / float(n_rings - 1)
        y = -0.097 - t * 0.0185  # -0.097 back -> -0.1155 tip (peeks cleanly above lower teeth in open mouth!)
        z_c = Z_MOUTH - 0.0022 + 0.0014 * math.sin(t * math.pi * 0.80)
        rx = 0.0098 * math.sqrt(max(0.05, 1.0 - (t ** 1.8) * 0.94))
        rz = 0.0036 * math.sqrt(max(0.06, 1.0 - (t ** 1.9) * 0.92))
        ring: List[bmesh.types.BMVert] = []
        for j in range(n_seg):
            ang = (j / float(n_seg)) * math.tau
            x = math.cos(ang) * rx
            z = z_c + math.sin(ang) * rz
            ring.append(bm.verts.new((x, y, z)))
        rings.append(ring)

    for ir in range(n_rings - 1):
        for j in range(n_seg):
            jn = (j + 1) % n_seg
            f = bm.faces.new((rings[ir][j], rings[ir][jn], rings[ir + 1][jn], rings[ir + 1][j]))
            f.smooth = True
            for l in f.loops:
                t_y = max(0.0, min(1.0, (-0.082 - l.vert.co.y) / 0.032))
                l[uv_lay].uv = (0.5 + l.vert.co.x * 24.0, 0.08 + t_y * 0.84)

    tip_v = bm.verts.new((0.0, -0.1160, Z_MOUTH - 0.0022))
    base_v = bm.verts.new((0.0, -0.0965, Z_MOUTH - 0.0030))
    for j in range(n_seg):
        jn = (j + 1) % n_seg
        f1 = bm.faces.new((rings[-1][j], rings[-1][jn], tip_v))
        f2 = bm.faces.new((rings[0][jn], rings[0][j], base_v))
        for f in (f1, f2):
            f.smooth = True
            for l in f.loops:
                l[uv_lay].uv = (0.5, 0.90 if f is f1 else 0.10)

    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("GhostGirl_Tongue")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True

    obj = bpy.data.objects.new("GhostGirl_Tongue", mesh)
    obj.data.materials.append(tongue_mat)
    bpy.context.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------------------
# 52 ARKit Blendshapes on GhostGirl_Head + 6 Eyelash Keys
# ---------------------------------------------------------------------------

def _rotate_around_x_pivot(pt: Vector, pivot_y: float, pivot_z: float, angle_rad: float) -> Vector:
    dy = pt.y - pivot_y
    dz = pt.z - pivot_z
    c = math.cos(angle_rad)
    s = math.sin(angle_rad)
    return Vector((pt.x, pivot_y + dy * c - dz * s, pivot_z + dy * s + dz * c))


def _compute_eye_arkit_delta(
    pt: Vector,
    key_name: str,
    is_lash: bool,
) -> Vector:
    """Compute leak-free orbital lid/eyelash deltas clamped outside swept rotated cornea dome."""
    is_left = key_name.endswith("Left")
    is_right = key_name.endswith("Right")
    if not (is_left or is_right):
        return Vector((0.0, 0.0, 0.0))

    sx = 1.0 if is_left else -1.0
    eye_c = Vector((sx * EYE_X, EYE_Y, EYE_Z))
    dx = pt.x - eye_c.x
    dz = pt.z - eye_c.z
    if pt.y > eye_c.y + 0.008 or abs(dx) > 0.036 or abs(dz) > 0.027:
        return Vector((0.0, 0.0, 0.0))

    margin = 0.0022 if is_lash else 0.0020
    u_x = (dx * sx) / 0.0215
    canthus_lift = 0.0014 * u_x
    # Smooth downward anime closed-eye arc
    z_seam = eye_c.z - 0.0058 + 0.0014 * (u_x * u_x) + canthus_lift

    # Smooth horizontal envelope spanning inner-to-outer canthus (extended slightly past outer wing for lashes)
    w_x_in = _smoothstep(-0.026, -0.017, dx * sx)
    w_x_out = 1.0 - _smoothstep(0.022 if is_lash else 0.019, 0.036 if is_lash else 0.030, dx * sx)
    w_x = w_x_in * w_x_out

    if key_name.startswith("eyeBlink"):
        if dz >= -0.0028 or (is_lash and dz >= -0.0024):
            # Strict upper ceiling dz <= 0.0215 so eyebrows (dz=0.0250) NEVER move on blink!
            w_z = _smoothstep(0.0215, 0.0145, dz)
            w = min(1.0, w_x * w_z)
            if is_lash and dz > -0.0015:
                w = max(w, w_x * 0.98)
                # Preserve ~2.6mm vertical lash ribbon height facing camera (-Y) so closed lid reads crisp & bold!
                row_fan = 0.0013 - 0.0026 * max(0.0, min(1.0, (dz - 0.001) / 0.015))
                target_z = pt.z * (1.0 - w) + (z_seam + row_fan) * w
            else:
                target_z = pt.z * (1.0 - w) + z_seam * w
            safe_y = _eye_cornea_surface_y(pt.x, target_z, eye_c, extra_margin=margin, include_gaze_sweep=True)
            target_y = min(pt.y, safe_y) if safe_y is not None else pt.y
            cand = _clamp_outside_eye_swept(Vector((pt.x, target_y, target_z)), eye_c, margin=margin)
            return cand - pt
        else:
            # Lower lid rises cleanly to z_seam; lower lashes tuck cleanly behind upper lash seam
            w_z = _smoothstep(-0.0150, -0.0095, dz)
            w = min(1.0, w_x * w_z)
            target_z = pt.z * (1.0 - w) + (z_seam + (0.0008 if is_lash else 0.0)) * w
            safe_y = _eye_cornea_surface_y(pt.x, target_z, eye_c, extra_margin=margin, include_gaze_sweep=True)
            target_y = (min(pt.y, safe_y) + (0.0014 * w if is_lash else 0.0)) if safe_y is not None else pt.y
            cand = _clamp_outside_eye_swept(Vector((pt.x, target_y, target_z)), eye_c, margin=margin)
            return cand - pt

    elif key_name.startswith("eyeWide"):
        if dz >= -0.001:
            w = w_x * _gauss(dz - 0.010, 0.008)
            cand = _clamp_outside_eye_swept(pt + Vector((0.0, 0.0, 0.0042 * w)), eye_c, margin=margin)
            return cand - pt
        w = w_x * _gauss(dz + 0.009, 0.007)
        cand = _clamp_outside_eye_swept(pt + Vector((0.0, 0.0, -0.0018 * w)), eye_c, margin=margin)
        return cand - pt

    elif key_name.startswith("eyeSquint"):
        if dz < 0.001:
            w = w_x * _gauss(dz + 0.009, 0.007)
            cand = _clamp_outside_eye_swept(pt + Vector((-sx * 0.0008 * w, -0.0006 * w, 0.0042 * w)), eye_c, margin=margin)
            return cand - pt
        w = w_x * _gauss(dz - 0.010, 0.007)
        cand = _clamp_outside_eye_swept(pt + Vector((0.0, 0.0, -0.0012 * w)), eye_c, margin=margin)
        return cand - pt

    elif key_name.startswith("eyeLook"):
        w = w_x * _gauss(dz, 0.013)
        if "Down" in key_name:
            cand = _clamp_outside_eye_swept(pt + Vector((0.0, 0.0, -0.0028 * w)), eye_c, margin=margin)
        elif "Up" in key_name:
            cand = _clamp_outside_eye_swept(pt + Vector((0.0, 0.0, 0.0028 * w)), eye_c, margin=margin)
        elif "In" in key_name:
            cand = _clamp_outside_eye_swept(pt + Vector((-sx * 0.0022 * w, 0.0, 0.0)), eye_c, margin=margin)
        else:
            cand = _clamp_outside_eye_swept(pt + Vector((sx * 0.0022 * w, 0.0, 0.0)), eye_c, margin=margin)
        return cand - pt

    return Vector((0.0, 0.0, 0.0))


def _bake_arkit_52_shape_keys(
    head_obj: bpy.types.Object,
    lash_obj: bpy.types.Object,
    mouth_bag_indices: Set[int],
) -> None:
    """Bake all 52 ARKit blendshapes on GhostGirl_Head and 6 eyelid keys on GhostGirl_Eyelashes."""
    head_obj.shape_key_clear()
    head_basis = head_obj.shape_key_add(name="Basis", from_mix=False)
    head_basis.interpolation = "KEY_LINEAR"
    head_base_pts = [v.co.copy() for v in head_obj.data.vertices]

    lash_obj.shape_key_clear()
    lash_basis = lash_obj.shape_key_add(name="Basis", from_mix=False)
    lash_basis.interpolation = "KEY_LINEAR"
    lash_base_pts = [v.co.copy() for v in lash_obj.data.vertices]

    jaw_angle_rad = math.radians(JAW_OPEN_DEG)
    mouth_hw = 0.0155

    def compute_head_delta(shape: str, pt: Vector, in_bag: bool) -> Vector:
        x, y, z = pt.x, pt.y, pt.z
        if y > EAR_Y_CENTER + 0.012 or z < Z_CHIN - 0.025:
            return Vector((0.0, 0.0, 0.0))

        # Eye keys
        if (
            shape.startswith("eyeBlink")
            or shape.startswith("eyeWide")
            or shape.startswith("eyeSquint")
            or shape.startswith("eyeLook")
        ):
            if in_bag:
                return Vector((0.0, 0.0, 0.0))
            return _compute_eye_arkit_delta(pt, shape, is_lash=False)

        is_left = shape.endswith("Left")
        sx = 1.0 if is_left else -1.0

        # Jaw keys (wide smooth D/O-oval opening, upper lip + entry edge move together cleanly)
        if shape == "jawOpen":
            if y < -0.012 and z < 1.408:
                u_m = min(1.0, abs(x) / 0.0165)
                oval_x = max(0.0, 1.0 - u_m * u_m) ** 0.72
                if in_bag:
                    if z >= Z_MOUTH:
                        if y < -0.118:
                            w_up = oval_x * _smoothstep(-0.117, -0.123, y)
                            return Vector((0.0, -0.0006 * w_up, 0.0028 * w_up))
                        return Vector((0.0, 0.0, 0.0))
                    w_jaw = 0.06 + 0.94 * oval_x
                else:
                    t_chin = _smoothstep(Z_MOUTH - 0.004, Z_MOUTH - 0.025, z)
                    if z >= Z_MOUTH:
                        if y < -0.105:
                            w_up = oval_x * _smoothstep(Z_MOUTH + 0.007, Z_MOUTH, z)
                            return Vector((0.0, -0.0008 * w_up, 0.0028 * w_up))
                        return Vector((0.0, 0.0, 0.0))
                    w_lip_open = (0.04 + 0.96 * oval_x) * (1.0 - t_chin) + t_chin
                    w_cheek_smooth = _smoothstep(1.385, 1.342, z)
                    lat_blend = _smoothstep(0.015, 0.032, abs(x))
                    w_vert = w_lip_open * (1.0 - lat_blend) + w_cheek_smooth * lat_blend
                    w_neck = _smoothstep(1.300, 1.328, z)
                    w_side = _gauss(x, 0.075)
                    w_back = _smoothstep(0.010, -0.042, y)
                    w_jaw = w_vert * w_neck * w_side * w_back
                if w_jaw > 1e-4:
                    rot_pt = _rotate_around_x_pivot(pt, TMJ_Y, TMJ_Z, jaw_angle_rad * w_jaw)
                    wide_x = (1.0 if x >= 0.0 else -1.0) * 0.0068 * _gauss(z - Z_MOUTH, 0.008) * _smoothstep(0.002, 0.015, abs(x))
                    return (rot_pt - pt) + Vector((wide_x, 0.0006 * w_jaw, 0.0))
            return Vector((0.0, 0.0, 0.0))

        if shape == "jawForward":
            w = _smoothstep(Z_MOUTH + 0.004, Z_CHIN, z) * _smoothstep(-0.02, -0.08, y) * _gauss(x, 0.048)
            return Vector((0.0, -0.0060 * w, 0.0))

        if shape in ("jawLeft", "jawRight"):
            w = _smoothstep(Z_MOUTH + 0.004, Z_CHIN, z) * _smoothstep(-0.02, -0.08, y) * _gauss(x, 0.048)
            return Vector(((0.0060 if shape == "jawLeft" else -0.0060) * w, 0.0, 0.0))

        # Mouth keys (calibrated for compact anime mouth!)
        if shape == "mouthClose":
            w = _gauss(x, 0.020) * _gauss(z - Z_MOUTH, 0.011) * _smoothstep(-0.08, -0.115, y)
            return Vector((0.0, -0.001 * w, (0.0045 if z < Z_MOUTH else -0.0020) * w))

        if shape == "mouthFunnel":
            if in_bag and y >= -0.116:
                return Vector((0.0, 0.0, 0.0))
            w = _gauss(x, 0.024) * _gauss(z - Z_MOUTH, 0.014) * _smoothstep(-0.08, -0.110, y)
            sign_z = 1.0 if z >= Z_MOUTH else -1.0
            oval_f = math.sqrt(max(0.0, 1.0 - min(1.0, abs(x) / 0.018) ** 2))
            return Vector((x * 0.28 * w, -0.0040 * w, sign_z * 0.0046 * oval_f * w))

        if shape == "mouthPucker":
            w = _gauss(x, 0.020) * _gauss(z - Z_MOUTH, 0.014) * _smoothstep(-0.08, -0.115, y)
            return Vector((-x * 0.34 * w, -0.0082 * w, 0.0))

        if shape in ("mouthLeft", "mouthRight"):
            w = _gauss(x, 0.022) * _gauss(z - Z_MOUTH, 0.014) * _smoothstep(-0.08, -0.115, y)
            return Vector(((0.0065 if shape == "mouthLeft" else -0.0065) * w, 0.0, 0.0))

        if shape in ("mouthSmileLeft", "mouthSmileRight"):
            if y < -0.085:
                w_side = _smoothstep(-0.004, 0.010, sx * x)
                w_c = w_side * _gauss(sx * x - 0.013, 0.016) * _gauss(z - Z_MOUTH, 0.014)
                # Lift ONLY corners upward/outward into crisp curved 'D' smile; keep lower center open cleanly!
                dz = 0.0068 * w_c * _smoothstep(0.004, 0.015, sx * x)
                if not in_bag and z >= Z_MOUTH:
                    dz += 0.0020 * w_side * _gauss(x, 0.012) * _gauss(z - (Z_MOUTH + 0.002), 0.007)
                return Vector((sx * 0.0072 * w_c, 0.0040 * w_c, dz))
            return Vector((0.0, 0.0, 0.0))

        if shape in ("mouthFrownLeft", "mouthFrownRight"):
            if not in_bag and y < -0.085:
                w = _smoothstep(-0.003, 0.011, sx * x) * _gauss(sx * x - 0.014, 0.014) * _gauss(z - Z_MOUTH, 0.012)
                w_seal = _smoothstep(-0.002, 0.006, sx * x) * _gauss(x, 0.012) * _gauss(z - Z_MOUTH, 0.009)
                # Downturn outer corners cleanly while keeping center cleanly sealed without wave
                dz_seal = (0.0018 if z < Z_MOUTH else -0.0010) * w_seal
                return Vector((-sx * 0.0010 * w, 0.0012 * w, -0.0046 * w + dz_seal))
            return Vector((0.0, 0.0, 0.0))

        if shape in ("mouthDimpleLeft", "mouthDimpleRight"):
            w = _gauss((pt - Vector((sx * 0.020, -0.123, Z_MOUTH))).length, 0.015)
            return Vector((sx * 0.0030 * w, 0.0035 * w, 0.0))

        if shape in ("mouthStretchLeft", "mouthStretchRight"):
            w = _smoothstep(-0.003, 0.011, sx * x) * _gauss(sx * x - 0.014, 0.016) * _gauss(z - Z_MOUTH, 0.013)
            return Vector((sx * 0.0065 * w, 0.0030 * w, -0.0008 * w))

        if shape in ("mouthRollLower", "mouthRollUpper"):
            lip_z = Z_MOUTH - 0.003 if "Lower" in shape else Z_MOUTH + 0.003
            w = _gauss((pt - Vector((0.0, -0.126, lip_z))).length, 0.015)
            return Vector((0.0, 0.0040 * w, (0.0025 if "Lower" in shape else -0.0025) * w))

        if shape in ("mouthShrugLower", "mouthShrugUpper"):
            lip_z = Z_MOUTH - 0.003 if "Lower" in shape else Z_MOUTH + 0.003
            w = _gauss((pt - Vector((0.0, -0.126, lip_z))).length, 0.016)
            return Vector((0.0, -0.0022 * w, 0.0040 * w))

        if shape in ("mouthPressLeft", "mouthPressRight"):
            w = _gauss((pt - Vector((sx * 0.010, -0.126, Z_MOUTH))).length, 0.013)
            return Vector((0.0, 0.0024 * w, (0.0020 if z < Z_MOUTH else -0.0020) * w))

        if shape in ("mouthUpperUpLeft", "mouthUpperUpRight"):
            if not in_bag and y < -0.095 and z >= Z_MOUTH:
                w = _smoothstep(-0.009, 0.007, sx * x) * _gauss(x, 0.014) * _gauss(z - (Z_MOUTH + 0.002), 0.009)
                return Vector((0.0, -0.0026 * w, 0.0068 * w))
            return Vector((0.0, 0.0, 0.0))

        if shape in ("mouthLowerDownLeft", "mouthLowerDownRight"):
            if not in_bag and y < -0.095 and z < Z_MOUTH:
                w = _smoothstep(-0.005, 0.008, sx * x) * _gauss(sx * x - 0.008, 0.013) * _gauss(z - (Z_MOUTH - 0.002), 0.009)
                return Vector((0.0, -0.0020 * w, -0.0048 * w))
            return Vector((0.0, 0.0, 0.0))

        # Brow keys
        if shape == "browInnerUp" and not in_bag and y < -0.090:
            w = _gauss(x, 0.024) * _gauss(z - Z_BROW, 0.016)
            return Vector((0.0, -0.0006 * w, 0.0075 * w))

        if shape in ("browDownLeft", "browDownRight") and not in_bag and y < -0.088:
            if sx * x > -0.004:
                w = _smoothstep(-0.004, 0.015, sx * x) * _gauss(sx * x - 0.032, 0.025) * _gauss(z - Z_BROW, 0.016)
                return Vector((-sx * 0.0025 * w, 0.0006 * w, -0.0076 * w))
            return Vector((0.0, 0.0, 0.0))

        if shape in ("browOuterUpLeft", "browOuterUpRight") and not in_bag and y < -0.085:
            w = _gauss(sx * x - 0.048, 0.022) * _gauss(z - Z_BROW, 0.016)
            return Vector((0.0, -0.0005 * w, 0.0072 * w))

        # Cheek & Nose keys
        if shape == "cheekPuff" and not in_bag:
            w = max(
                _gauss((pt - Vector((0.042, -0.114, Z_MOUTH + 0.014))).length, 0.022),
                _gauss((pt - Vector((-0.042, -0.114, Z_MOUTH + 0.014))).length, 0.022),
            )
            return Vector(((1.0 if x >= 0.0 else -1.0) * 0.0075 * w, -0.0070 * w, 0.0))

        if shape in ("cheekSquintLeft", "cheekSquintRight") and not in_bag and y < -0.080:
            w = _smoothstep(0.002, 0.018, sx * x) * _gauss(sx * x - 0.042, 0.024) * _gauss(z - (EYE_Z - 0.024), 0.020)
            return Vector((sx * 0.0010 * w, -0.0032 * w, 0.0046 * w))

        if shape in ("noseSneerLeft", "noseSneerRight") and not in_bag and y < -0.100:
            w = _gauss((pt - Vector((sx * 0.012, -0.129, Z_NOSE_TIP + 0.004))).length, 0.014)
            return Vector((0.0, 0.0, 0.0042 * w))

        if shape == "tongueOut":
            w = _gauss((pt - Vector((0.0, -0.126, Z_MOUTH))).length, 0.013)
            return Vector((0.0, 0.0, -0.0018 * w))

        return Vector((0.0, 0.0, 0.0))

    for shape_name in ARKIT_52:
        kb = head_obj.shape_key_add(name=shape_name, from_mix=False)
        kb.interpolation = "KEY_LINEAR"
        kb.value = 0.0
        for idx, pt in enumerate(head_base_pts):
            kb.data[idx].co = pt + compute_head_delta(shape_name, pt, idx in mouth_bag_indices)
    head_obj.active_shape_key_index = 0

    for shape_name in EYELASH_6:
        kb_l = lash_obj.shape_key_add(name=shape_name, from_mix=False)
        kb_l.interpolation = "KEY_LINEAR"
        kb_l.value = 0.0
        for idx, pt in enumerate(lash_base_pts):
            kb_l.data[idx].co = pt + _compute_eye_arkit_delta(pt, shape_name, is_lash=True)
    lash_obj.active_shape_key_index = 0


# ---------------------------------------------------------------------------
# Public Entry Point
# ---------------------------------------------------------------------------

def build_anime_head_package(
    collar_center: Vector,
    z_neck_cut: float,
    tex_dir: Path,
) -> Tuple[
    bpy.types.Object,
    bpy.types.Object,
    bpy.types.Object,
    bpy.types.Object,
    bpy.types.Object,
    bpy.types.Object,
    bpy.types.Object,
    Dict[str, Any],
    Dict[str, Path],
]:
    """Build GhostGirl's complete anime head package, textures, custom normals & 52 ARKit morphs."""
    tex_dir.mkdir(parents=True, exist_ok=True)

    # 1. Build GhostGirl_Head mesh + bake 2K head face atlas & ORM
    head_obj, mouth_bag_indices, eye_socket_indices, ear_indices = _build_head_mesh(
        collar_center=collar_center,
        z_neck_cut=z_neck_cut,
    )
    head_alb, head_orm = _generate_head_textures(
        head_obj, mouth_bag_indices, eye_socket_indices, ear_indices, tex_dir
    )
    face_mat = _make_material(
        "M_ghost_girl_face",
        albedo_path=head_alb,
        orm_path=head_orm,
        roughness=0.72,
        specular=0.10,
    )
    head_obj.data.materials.clear()
    head_obj.data.materials.append(face_mat)

    # 2. Build eyes, eyelashes, dental arches, and tongue + textures
    eye_alb, eye_orm = _generate_eye_textures(tex_dir)
    eye_mat = _make_material(
        "M_ghost_girl_eye",
        albedo_path=eye_alb,
        orm_path=eye_orm,
        roughness=0.05,
        coat=0.95,
    )
    eye_l_obj = _build_anime_eye("GhostGirl_Eye_L", Vector((EYE_X, EYE_Y, EYE_Z)), eye_mat)
    eye_r_obj = _build_anime_eye("GhostGirl_Eye_R", Vector((-EYE_X, EYE_Y, EYE_Z)), eye_mat)

    lash_alb = _generate_lash_texture(tex_dir)
    lash_mat = _make_material(
        "M_ghost_girl_eyelashes",
        albedo_path=lash_alb,
        roughness=0.92,
        specular=0.04,
        alpha_mode="CLIP",
        alpha_threshold=0.35,
        double_sided=True,
    )
    lash_obj = _build_anime_eyelashes(lash_mat)

    mouth_alb, tongue_alb = _generate_mouth_and_tongue_textures(tex_dir)
    mouth_mat = _make_material("M_ghost_girl_mouth", albedo_path=mouth_alb, roughness=0.22, emission_strength=0.40)
    tongue_mat = _make_material("M_ghost_girl_tongue", albedo_path=tongue_alb, roughness=0.32, emission_strength=0.38)
    teeth_u_obj = _build_dental_arch("GhostGirl_Teeth_Upper", is_upper=True, mouth_mat=mouth_mat)
    teeth_l_obj = _build_dental_arch("GhostGirl_Teeth_Lower", is_upper=False, mouth_mat=mouth_mat)
    tongue_obj = _build_tongue(tongue_mat)

    # 3. Measure exact head landmarks
    pts = [v.co for v in head_obj.data.vertices]
    head_lm: Dict[str, Any] = {
        "left_eye": Vector((EYE_X, EYE_Y, EYE_Z)),
        "right_eye": Vector((-EYE_X, EYE_Y, EYE_Z)),
        "mouth": Vector((0.0, -0.1265, Z_MOUTH)),
        "nose_tip": Vector((0.0, -0.1415, Z_NOSE_TIP)),
        "chin": Vector((0.0, -0.1125, Z_CHIN)),
        "ear_y": Vector((EAR_X_MAX, EAR_Y_CENTER, EAR_Z_CENTER)),
        "head_center": Vector((0.0, HEAD_CENTER_Y, 0.5 * (Z_CHIN + Z_CROWN))),
        "head_y_min": Vector((0.0, HEAD_Y_FRONT, EYE_Z)),
        "head_y_max": Vector((0.0, HEAD_Y_BACK, EYE_Z)),
        "bbox_min": Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
        "bbox_max": Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))),
        "crown_z": Z_CROWN,
        "brow_z": Z_BROW,
        "skull_rx": SKULL_MAX_RX,
        "z_neck_cut": z_neck_cut,
        "neck_collar_rx": 0.0430,
        "neck_collar_ry": 0.0450,
        "neck_rim_rx": 0.0375,
        "neck_rim_ry": 0.0405,
        "neck_top_rx": 0.0360,
        "neck_top_ry": 0.0400,
    }

    # 4. Apply smooth custom anime face normals BEFORE baking shape keys
    apply_anime_face_normals(head_obj, head_lm)

    # 5. Bake all 52 ARKit blendshapes on GhostGirl_Head + 6 eyelid keys on GhostGirl_Eyelashes
    _bake_arkit_52_shape_keys(head_obj, lash_obj, mouth_bag_indices)

    tex_paths: Dict[str, Path] = {
        "head_albedo": head_alb,
        "head_orm": head_orm,
        "eye_albedo": eye_alb,
        "eye_orm": eye_orm,
        "lash_albedo": lash_alb,
        "mouth_albedo": mouth_alb,
        "tongue_albedo": tongue_alb,
    }
    return (
        head_obj,
        eye_l_obj,
        eye_r_obj,
        lash_obj,
        teeth_u_obj,
        teeth_l_obj,
        tongue_obj,
        head_lm,
        tex_paths,
    )


# ---------------------------------------------------------------------------
# Stage 1 Standalone QA Render Mode (4-View Bald Head + 2x3 ARKit Preview)
# ---------------------------------------------------------------------------

def _render_stage1_iso_qa(output_path: Path, tile_size: int = 384) -> None:
    """Build isolated bald head package and render 4-view + 2x3 ARKit sheet for Stage 1 QA."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sdk_root = Path(__file__).resolve().parents[2]
    tex_dir = sdk_root / "assets" / "models" / "ghost_girl" / "textures"

    head_obj, eye_l, eye_r, lash_obj, teeth_u, teeth_l, tongue, lm, _ = build_anime_head_package(
        collar_center=Vector((0.0, -0.002, Z_NECK_CUT_DEFAULT)),
        z_neck_cut=Z_NECK_CUT_DEFAULT,
        tex_dir=tex_dir,
    )

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = tile_size
    scene.render.resolution_y = tile_size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.new("Stage1World")
    scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg is not None:
        bg.inputs[0].default_value = (0.34, 0.36, 0.40, 1.0)
        bg.inputs[1].default_value = 0.65

    center = Vector((0.0, -0.025, 1.445))
    light_specs = (
        ("KeyLight", (0.55, -0.85, 0.45), 7.2, 0.90),
        ("FillLight", (-0.65, -0.75, 0.20), 4.8, 1.10),
        ("RimLight", (0.10, 0.85, 0.50), 5.0, 0.80),
    )
    for name, off, energy, sz in light_specs:
        ldata = bpy.data.lights.new(name=name, type="AREA")
        ldata.energy = energy
        ldata.size = sz
        lobj = bpy.data.objects.new(name=name, object_data=ldata)
        scene.collection.objects.link(lobj)
        lobj.location = center + Vector(off)
        lobj.rotation_euler = (center - lobj.location).to_track_quat("-Z", "Y").to_euler()

    cdata = bpy.data.cameras.new("IsoCam")
    cdata.lens = 85.0
    cam = bpy.data.objects.new("IsoCam", cdata)
    scene.collection.objects.link(cam)
    scene.camera = cam

    def _aim(yaw_deg: float, pitch_deg: float, dist: float) -> None:
        yaw = math.radians(yaw_deg)
        pitch = math.radians(pitch_deg)
        offset = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * dist
        cam.location = center + offset
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()

    def _reset_expr() -> None:
        for obj in (head_obj, lash_obj):
            if obj.data.shape_keys:
                for kb in obj.data.shape_keys.key_blocks[1:]:
                    kb.value = 0.0
        for e in (eye_l, eye_r):
            e.rotation_euler = (0.0, 0.0, 0.0)
            e.location = (0.0, 0.0, 0.0)
        for m_obj in (teeth_l, tongue):
            m_obj.rotation_euler = (0.0, 0.0, 0.0)
            m_obj.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()

    def _render_tile(tmp: Path) -> np.ndarray:
        scene.render.filepath = str(tmp)
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(str(tmp), check_existing=False)
        try:
            w, h = img.size[0], img.size[1]
            arr = np.empty(w * h * 4, dtype=np.float32)
            img.pixels.foreach_get(arr)
            return arr.reshape((h, w, 4))
        finally:
            bpy.data.images.remove(img)

    # Row 0 (cols 0..3): Front (0°), Side (90°), Back (180°), 3/4 Back (135°)
    # Row 1 (cols 0..3): Happy, Surprised, Blink+GazeLeft, JawOpen
    # Plus Row 2 (or 4x2 + 2 -> let's do clean 5x2 grid: 4 ortho views + 6 ARKit expressions!)
    # Actually 5 cols x 2 rows = 10 tiles:
    # Row 0: Front, Side, Back, 3/4 Back, 3/4 Front Neutral
    # Row 1: Happy, Surprised, Angry, Blink+GazeLeft, JawOpen
    tiles: List[np.ndarray] = []
    tmp_p = Path("/tmp/_iso_tile.png")
    views = (
        ("Front", 0.0, 2.0, {}, 0.0, 0.0),
        ("Side", 90.0, 2.0, {}, 0.0, 0.0),
        ("Back", 180.0, 2.0, {}, 0.0, 0.0),
        ("3/4 Back", 138.0, 4.0, {}, 0.0, 0.0),
        ("3/4 Front", 32.0, 4.0, {}, 0.0, 0.0),
        (
            "Happy",
            0.0,
            2.0,
            {
                "mouthSmileLeft": 0.82,
                "mouthSmileRight": 0.82,
                "cheekSquintLeft": 0.45,
                "cheekSquintRight": 0.45,
                "eyeSquintLeft": 0.28,
                "eyeSquintRight": 0.28,
                "jawOpen": 0.18,
                "mouthUpperUpLeft": 0.22,
                "mouthUpperUpRight": 0.22,
            },
            3.0,
            0.0,
        ),
        (
            "Surprised",
            0.0,
            2.0,
            {
                "browInnerUp": 0.80,
                "browOuterUpLeft": 0.70,
                "browOuterUpRight": 0.70,
                "eyeWideLeft": 0.85,
                "eyeWideRight": 0.85,
                "jawOpen": 0.55,
                "mouthFunnel": 0.35,
            },
            9.0,
            0.0,
        ),
        (
            "Angry",
            0.0,
            2.0,
            {
                "browDownLeft": 0.90,
                "browDownRight": 0.90,
                "eyeSquintLeft": 0.45,
                "eyeSquintRight": 0.45,
                "mouthFrownLeft": 0.55,
                "mouthFrownRight": 0.55,
            },
            0.0,
            0.0,
        ),
        (
            "Blink+GazeL",
            0.0,
            2.0,
            {"eyeBlinkLeft": 1.0, "eyeBlinkRight": 0.0},
            0.0,
            20.0,
        ),
        (
            "JawOpen",
            8.0,
            -3.0,
            {"jawOpen": 0.85, "mouthLowerDownLeft": 0.35, "mouthLowerDownRight": 0.35},
            15.0,
            0.0,
        ),
    )

    dist = 0.86
    for label, yaw_d, pitch_d, sk_w, jaw_d, eye_yaw_d in views:
        _reset_expr()
        for obj in (head_obj, lash_obj):
            if obj.data.shape_keys:
                kbs = obj.data.shape_keys.key_blocks
                for k_n, val in sk_w.items():
                    if k_n in kbs:
                        kbs[k_n].value = val
        if abs(eye_yaw_d) > 1e-4:
            # Rotate RightEye around its own center along +Z
            ec_r = Vector((-EYE_X, EYE_Y, EYE_Z))
            eye_r.location = ec_r - (Matrix.Rotation(math.radians(eye_yaw_d), 3, "Z") @ ec_r)
            eye_r.rotation_euler = (0.0, 0.0, math.radians(eye_yaw_d))
        if abs(jaw_d) > 1e-4:
            piv = Vector((0.0, TMJ_Y, TMJ_Z))
            rot_m = Matrix.Rotation(math.radians(jaw_d * 0.45), 3, "X")
            for m_obj in (teeth_l, tongue):
                m_obj.location = piv - (rot_m @ piv)
                m_obj.rotation_euler = (math.radians(jaw_d * 0.45), 0.0, 0.0)
        bpy.context.view_layer.update()
        _aim(yaw_d, pitch_d, dist)
        tiles.append(_render_tile(tmp_p))
        print(f"[Stage1 QA] Rendered {label}")

    tmp_p.unlink(missing_ok=True)
    cols, rows = 5, 2
    sheet = np.zeros((tile_size * rows, tile_size * cols, 4), dtype=np.float32)
    sheet[:, :, 3] = 1.0
    for idx, tile in enumerate(tiles):
        r, c = divmod(idx, cols)
        y0 = (rows - 1 - r) * tile_size
        x0 = c * tile_size
        sheet[y0 : y0 + tile_size, x0 : x0 + tile_size, :] = tile

    output_path.parent.mkdir(parents=True, exist_ok=True)
    out_img = bpy.data.images.new("Stage1Sheet", width=tile_size * cols, height=tile_size * rows, alpha=False)
    try:
        out_img.pixels.foreach_set(sheet.ravel())
        out_img.filepath_raw = str(output_path)
        out_img.file_format = "PNG"
        out_img.save()
    finally:
        bpy.data.images.remove(out_img)
    print(f"[Stage1 QA] Saved {output_path} ({tile_size * cols}x{tile_size * rows})")


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="GhostGirl anime head builder & Stage 1 QA")
    parser.add_argument("--qa-iso", type=Path, default=Path("/tmp/ghost_girl_qa_head_iso.png"))
    parser.add_argument("--tile-size", type=int, default=384)
    args = parser.parse_args(argv)
    _render_stage1_iso_qa(args.qa_iso, tile_size=args.tile_size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
