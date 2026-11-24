#!/usr/bin/env python3
"""Parametric anime hair, ghost hood, accessories, and outfit builders for Ghost Girl.

Exposes modular builders consumed by `tools/blender/build_ghost_girl.py`:
- `sculpt_clean_mpfb2_humanizer_base(bm_obj)`
- `build_sculpted_lavender_hair(head_obj, head_lm, tex_dir)` -> `(cap_obj, cards_obj, hair_alb, hair_cap_alb, hair_orm)`
- `build_ghost_hood(head_obj, head_lm, tex_dir)` -> `(hood_obj, hood_alb, hood_orm)`
- `build_croptop(bm_obj, lm, tex_dir, head_obj)` -> `(crop_obj, alb_p)`
- `build_skirt(bm_obj, tex_dir)` -> `(skirt_obj, alb_p)`
- `paint_cape_texture(tex_dir)` -> `(alb_p, orm_p)`
- `build_ghost_cape(body_obj, alb_p, orm_p, is_tpose, hood_obj, lm)` -> `cape_obj`
- `paint_gloves_textures(tex_dir)` -> `(alb_p, orm_p)`
- `build_gloves(body_obj, alb_p, orm_p)` -> `gloves_obj`
- `build_boots(bm_obj, tex_dir)` -> `(boots_obj, alb_p)`
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set, Tuple

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

SDK_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TEX_DIR = SDK_ROOT / "assets" / "models" / "ghost_girl" / "textures"


# ---------------------------------------------------------------------------
# Shared Math, Image, Material & Landmark Helpers
# ---------------------------------------------------------------------------

def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge1 == edge0:
        return 1.0 if x >= edge1 else 0.0
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _gauss(d: float, sigma: float) -> float:
    if sigma <= 1e-6:
        return 0.0
    return math.exp(-0.5 * (d / sigma) ** 2)


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def _save_image(path: Path, arr: np.ndarray) -> None:
    """Save float32 (0..1) or uint8 (H, W, 3|4) top-down array to PNG via Blender."""
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
    img.pixels.foreach_set(rgba_bu)
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def _make_pbr_material(
    name: str,
    albedo_path: Optional[Path] = None,
    orm_path: Optional[Path] = None,
    base_color: Tuple[float, float, float, float] = (0.85, 0.85, 0.85, 1.0),
    roughness: float = 0.60,
    metallic: float = 0.0,
    alpha_mode: str = "OPAQUE",
    double_sided: bool = False,
) -> bpy.types.Material:
    """Create or update a glTF-2.0 Principled BSDF material."""
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
    bsdf.inputs["Metallic"].default_value = metallic
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if albedo_path and albedo_path.exists():
        img = bpy.data.images.load(str(albedo_path), check_existing=True)
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_mode != "OPAQUE":
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])

    if orm_path and orm_path.exists():
        img_o = bpy.data.images.load(str(orm_path), check_existing=True)
        img_o.colorspace_settings.name = "Non-Color"
        tex_o = nt.nodes.new("ShaderNodeTexImage")
        tex_o.image = img_o
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(tex_o.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    if alpha_mode == "BLEND":
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
    elif alpha_mode == "OPAQUE":
        if hasattr(mat, "blend_method"):
            mat.blend_method = "OPAQUE"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "DITHERED"
    return mat


def _vg_indices(obj: bpy.types.Object, names: Sequence[str], min_w: float = 0.01) -> Set[int]:
    out: Set[int] = set()
    g_idxs = [obj.vertex_groups[n].index for n in names if n in obj.vertex_groups]
    if not g_idxs:
        return out
    g_set = set(g_idxs)
    for v in obj.data.vertices:
        if any(g.group in g_set and g.weight >= min_w for g in v.groups):
            out.add(v.index)
    return out


def _body_or_all_indices(obj: bpy.types.Object) -> Set[int]:
    body_vs = _vg_indices(obj, ("body",))
    return body_vs if body_vs else set(range(len(obj.data.vertices)))


def _to_vec(val: object, fallback: Vector) -> Vector:
    if isinstance(val, Vector):
        return val.copy()
    if isinstance(val, (tuple, list)) and len(val) >= 3:
        return Vector((float(val[0]), float(val[1]), float(val[2])))
    return fallback.copy()


def _build_bvh(obj: bpy.types.Object, allowed_indices: Optional[Set[int]] = None) -> BVHTree:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    if allowed_indices is not None and len(allowed_indices) < len(bm.verts):
        del_v = [v for v in bm.verts if v.index not in allowed_indices]
        if del_v:
            bmesh.ops.delete(bm, geom=del_v, context="VERTS")
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    bvh = BVHTree.FromBMesh(bm)
    bm.free()
    return bvh


def _resolve_head_landmarks(
    head_obj: bpy.types.Object,
    head_lm: Optional[Dict[str, object]],
) -> Dict[str, Vector | float]:
    """Resolve parametric anime head metrics from head_lm + direct head_obj geometry."""
    lm = head_lm or {}
    body_vs = _body_or_all_indices(head_obj)
    all_pts = [head_obj.data.vertices[i].co.copy() for i in body_vs]
    z_max_mesh = max((p.z for p in all_pts), default=1.58)
    z_crown = float(lm["crown_z"]) if isinstance(lm.get("crown_z"), (int, float)) else (
        _to_vec(lm.get("bbox_max"), Vector((0.0, 0.0, z_max_mesh))).z
    )
    if z_crown < 1.30:
        z_crown = z_max_mesh

    left_eye = _to_vec(lm.get("left_eye"), Vector((0.036, -0.108, z_crown - 0.136)))
    if isinstance(lm.get("eye_z"), (int, float)):
        left_eye.z = float(lm["eye_z"])
    right_eye = _to_vec(lm.get("right_eye"), Vector((-left_eye.x, left_eye.y, left_eye.z)))
    eye_z = 0.5 * (left_eye.z + right_eye.z)
    eye_x = max(0.026, 0.5 * (abs(left_eye.x) + abs(right_eye.x)))
    eye_y = 0.5 * (left_eye.y + right_eye.y)

    # Filter head vertices above neck cut if head_obj is a full MPFB2 body mesh
    z_head_floor = eye_z - 0.165
    head_pts = [p for p in all_pts if p.z >= z_head_floor and abs(p.x) < 0.16]
    if not head_pts:
        head_pts = all_pts

    chin = _to_vec(lm.get("chin"), Vector((0.0, eye_y - 0.002, eye_z - 0.108)))
    mouth = _to_vec(lm.get("mouth"), Vector((0.0, eye_y - 0.015, eye_z - 0.072)))
    ear_y_v = _to_vec(lm.get("ear_y"), Vector((0.092, eye_y + 0.088, eye_z - 0.016)))

    cranial_pts = [p for p in head_pts if p.z >= eye_z - 0.010]
    forehead_pts = [p for p in cranial_pts if p.z >= eye_z + 0.015 and abs(p.x) < 0.055]
    forehead_y = min((p.y for p in forehead_pts), default=eye_y - 0.012)
    hy_min_raw = lm.get("head_y_min")
    hy_max_raw = lm.get("head_y_max")
    hy_min = float(hy_min_raw) if isinstance(hy_min_raw, (int, float)) else min((p.y for p in cranial_pts), default=forehead_y)
    hy_max = float(hy_max_raw) if isinstance(hy_max_raw, (int, float)) else max((p.y for p in cranial_pts), default=forehead_y + 0.215)
    if isinstance(hy_min_raw, Vector) or isinstance(hy_min_raw, (tuple, list)):
        hy_min = _to_vec(hy_min_raw, Vector((0.0, forehead_y, eye_z))).y
    if isinstance(hy_max_raw, Vector) or isinstance(hy_max_raw, (tuple, list)):
        hy_max = _to_vec(hy_max_raw, Vector((0.0, forehead_y + 0.215, eye_z))).y
    if isinstance(hy_min_raw, (int, float)):
        forehead_y = min(forehead_y, float(hy_min_raw) + 0.002) if forehead_pts else float(hy_min_raw)

    # Exclude protruding outer ears when measuring cranial rx
    skull_band = [
        p for p in cranial_pts
        if (p.z >= eye_z + 0.022 or p.y < ear_y_v.y - 0.020 or p.y > ear_y_v.y + 0.028)
    ]
    measured_skull_rx = max((abs(p.x) for p in skull_band), default=0.088)
    skull_rx = float(lm["skull_rx"]) if isinstance(lm.get("skull_rx"), (int, float)) else measured_skull_rx
    skull_rx = max(skull_rx, measured_skull_rx)
    ear_rx = max(skull_rx, abs(ear_y_v.x), max((abs(p.x) for p in cranial_pts), default=0.094))
    brow_z = float(lm["brow_z"]) if isinstance(lm.get("brow_z"), (int, float)) else (eye_z + 0.025)

    hc_default = Vector((0.0, 0.5 * (hy_min + hy_max), eye_z + 0.022))
    head_center = _to_vec(lm.get("head_center"), hc_default)
    # Keep head_center.y grounded to cranial center rather than nose/neck outliers
    head_center.x = 0.0
    if abs(head_center.y - hc_default.y) > 0.035:
        head_center.y = hc_default.y

    return {
        "crown_z": z_crown,
        "eye_z": eye_z,
        "brow_z": brow_z,
        "eye_x": eye_x,
        "eye_y": eye_y,
        "left_eye": Vector((eye_x, eye_y, eye_z)),
        "right_eye": Vector((-eye_x, eye_y, eye_z)),
        "chin": chin,
        "mouth": mouth,
        "ear_y": Vector((ear_rx, ear_y_v.y, ear_y_v.z)),
        "head_center": head_center,
        "forehead_y": forehead_y,
        "hy_min": hy_min,
        "hy_max": hy_max,
        "skull_rx": skull_rx,
        "skull_ry": max(0.095, 0.5 * (hy_max - hy_min)),
        "ear_rx": ear_rx,
    }


def _push_outside_bvh(
    pt: Vector,
    origin: Vector,
    bvh: BVHTree,
    clearance: float,
    max_cap: Optional[float] = None,
) -> Vector:
    """Ensure pt stays at least `clearance` outside bvh surface away from origin."""
    loc, nrm, _, dist = bvh.find_nearest(pt)
    if loc is None:
        return pt
    rad = pt - origin
    rad_dir = rad.normalized() if rad.length > 1e-5 else Vector((0.0, -1.0, 0.0))
    loc_rad = loc - origin
    out_ref = loc_rad.normalized() if loc_rad.length > 1e-5 else rad_dir
    surf_n = nrm.normalized() if nrm.length > 1e-5 else out_ref
    if surf_n.dot(out_ref) < 0.0:
        surf_n = -surf_n
    signed_d = (pt - loc).dot(surf_n)
    if signed_d < clearance or dist < clearance:
        out_pt = loc + surf_n * clearance
        if max_cap is not None:
            loc_r = loc_rad.length
            out_r = (out_pt - origin).length
            if out_r > loc_r + max_cap:
                out_pt = origin + (out_pt - origin).normalized() * (loc_r + max_cap)
        return out_pt
    return pt


# ---------------------------------------------------------------------------
# 1. Clean MPFB2 Humanizer Base Face Sculpt
# ---------------------------------------------------------------------------

def sculpt_clean_mpfb2_humanizer_base(bm_obj: bpy.types.Object) -> None:
    """Open MPFB2 eyelids, slim neck to collar size, and soften brow/nose/lips for Humanizer mode.

    Operates directly on the 19,158-vert MPFB2 canonical mesh while preserving vertex indices,
    helper-mesh alignment, and max_delta < 0.70m against un-morphed basis.data.
    """
    verts = bm_obj.data.vertices
    body_vs = _vg_indices(bm_obj, ("body",))
    if not body_vs:
        body_vs = set(range(len(verts)))
    ear_vs = _vg_indices(bm_obj, ("ears",))
    lip_vs = _vg_indices(bm_obj, ("lips",))

    l_eye_h = _vg_indices(bm_obj, ("helper-l-eye",))
    r_eye_h = _vg_indices(bm_obj, ("helper-r-eye",))
    lash_l_hs = _vg_indices(bm_obj, ("helper-l-eyelashes-1", "helper-l-eyelashes-2"))
    lash_r_hs = _vg_indices(bm_obj, ("helper-r-eyelashes-1", "helper-r-eyelashes-2"))
    lash_hs = lash_l_hs | lash_r_hs
    if l_eye_h and r_eye_h:
        le = sum((verts[i].co for i in l_eye_h), Vector((0.0, 0.0, 0.0))) / float(len(l_eye_h))
        re = sum((verts[i].co for i in r_eye_h), Vector((0.0, 0.0, 0.0))) / float(len(r_eye_h))
    else:
        z_max = max(verts[i].co.z for i in body_vs)
        le = Vector((0.038, -0.113, z_max - 0.135))
        re = Vector((-0.038, -0.113, z_max - 0.135))

    eye_z = 0.5 * (le.z + re.z)
    eye_x = 0.5 * (abs(le.x) + abs(re.x))
    eye_y = 0.5 * (le.y + re.y)

    if lip_vs:
        lip_pts = [verts[i].co for i in lip_vs]
        mc = sum(lip_pts, Vector((0.0, 0.0, 0.0))) / float(len(lip_pts))
        front_lips = [p for p in lip_pts if abs(p.x) < 0.008]
        mouth_y = min((p.y for p in front_lips), default=mc.y)
        mouth_z = 0.5 * (
            max((p.z for p in front_lips), default=mc.z)
            + min((p.z for p in front_lips), default=mc.z)
        )
    else:
        mouth_y = eye_y - 0.020
        mouth_z = eye_z - 0.074

    # Measure brow overhang reference y above orbital ridge
    forehead_ref_pts = [
        verts[i].co for i in body_vs
        if abs(verts[i].co.x) < 0.055 and (eye_z + 0.042) <= verts[i].co.z <= (eye_z + 0.062)
        and verts[i].co.y < eye_y
    ]
    forehead_y_ref = (
        sum(p.y for p in forehead_ref_pts) / float(max(len(forehead_ref_pts), 1))
        if forehead_ref_pts
        else (eye_y - 0.021)
    )

    # Neck span strictly above bare collarbones (Z >= ~1.282) so shoulders stay undeformed
    z_neck_bot = eye_z - 0.174
    z_neck_top = eye_z - 0.100
    neck_cy = -0.009

    def _open_eyelid_pt(pt: Vector) -> Vector:
        """Apply continuous upper/lower anime eyelid aperture expansion around eyeball centers."""
        dx = abs(abs(pt.x) - eye_x)
        dz = pt.z - eye_z
        if dx >= 0.024 or pt.y >= eye_y + 0.005:
            return pt
        out = pt.copy()
        w_x = _gauss(dx, 0.0125)
        if -0.002 <= dz <= 0.024:
            lift = 0.0074 * w_x * _smoothstep(-0.002, 0.0035, dz) * _smoothstep(0.024, 0.008, dz)
            out.z += lift
            if out.y < eye_y - 0.003:
                out.y += 0.0022 * (lift / 0.0074) * _smoothstep(0.016, 0.004, dz)
        elif -0.020 <= dz < -0.002:
            drop = 0.0044 * w_x * _smoothstep(0.001, -0.0035, dz) * _smoothstep(-0.020, -0.008, dz)
            out.z -= drop
            if out.y < eye_y - 0.003:
                out.y += 0.0014 * (drop / 0.0044) * _smoothstep(-0.014, -0.004, dz)
        return out

    for idx in body_vs:
        if idx in ear_vs:
            continue
        p = verts[idx].co.copy()
        ax = abs(p.x)

        # Slim neck cylinder cleanly above clavicles (Z >= 1.282) without stretching bare shoulders
        if z_neck_bot <= p.z <= z_neck_top and ax < 0.080 and not (p.z > eye_z - 0.125 and p.y < -0.058):
            w_z = _smoothstep(z_neck_bot, z_neck_bot + 0.022, p.z) * _smoothstep(
                z_neck_top, z_neck_top - 0.024, p.z
            )
            w_r = _smoothstep(0.080, 0.052, ax)
            w_neck = w_z * w_r
            p.x *= 1.0 - 0.40 * w_neck
            y_shrink = 0.40 if p.y > 0.01 else 0.32
            p.y = (p.y - neck_cy) * (1.0 - y_shrink * w_neck) + neck_cy

        if p.y >= eye_y + 0.015 or p.z < z_neck_top - 0.01:
            verts[idx].co = p
            continue

        # 0. Open narrow MPFB2 eyelids and recess prominent MPFB2 brow/forehead to planar anime plane
        p = _open_eyelid_pt(p)
        if (eye_z + 0.012) <= p.z <= (eye_z + 0.105) and ax < 0.072 and p.y < eye_y - 0.004:
            w_fh = (
                _smoothstep(eye_z + 0.012, eye_z + 0.026, p.z)
                * _smoothstep(eye_z + 0.105, eye_z + 0.076, p.z)
                * _smoothstep(0.072, 0.028, ax)
            )
            p.y += 0.0085 * w_fh

        # 1. Soften prominent supraorbital brow shelf / glabella ridge to eliminate dark brow shadow
        if (eye_z + 0.018) <= p.z <= (eye_z + 0.048) and ax < 0.068 and p.y < forehead_y_ref - 0.0005:
            w_brow = _gauss(p.z - (eye_z + 0.028), 0.011) * _smoothstep(0.068, 0.024, ax)
            excess = max(0.0, (forehead_y_ref + 0.0012) - p.y)
            p.y += min(0.0046, excess * 0.85) * w_brow

        # 2. Fill under-eye tear troughs / eye-bag hollows smoothly into planar anime cheeks
        dx_eye = abs(ax - eye_x)
        if (eye_z - 0.038) <= p.z <= (eye_z - 0.013) and dx_eye < 0.032 and p.y < eye_y - 0.004:
            w_tr = _gauss(p.z - (eye_z - 0.022), 0.009) * _gauss(dx_eye, 0.018)
            p.y -= 0.0036 * w_tr

        # 3. Narrow wide MPFB2 nose bridge & alar wings + fill harsh nasolabial creases
        if (mouth_z + 0.010) <= p.z <= (eye_z + 0.006) and ax < 0.032 and p.y < eye_y + 0.005:
            w_nose_z = _gauss(p.z - (eye_z - 0.030), 0.017)
            w_nose_x = _gauss(ax, 0.018)
            p.x *= 1.0 - 0.22 * w_nose_z * w_nose_x
            if p.z < eye_z - 0.024 and ax < 0.018 and p.y < mouth_y - 0.004:
                w_tip = _gauss(ax, 0.011) * _gauss(p.z - (eye_z - 0.040), 0.010)
                p.y += 0.0028 * w_tip
                p.z += 0.0018 * w_tip
            if 0.011 < ax < 0.024 and p.z < eye_z - 0.024:
                w_ala = _gauss(ax - 0.016, 0.005) * _gauss(p.z - (eye_z - 0.040), 0.010)
                p.y -= 0.0024 * w_ala

        # 4. Slim thick realistic lips & soften mentolabial chin crease
        if abs(p.z - mouth_z) < 0.020 and ax < 0.034 and p.y < mouth_y + 0.020:
            w_lip = _gauss(ax, 0.022) * _gauss(p.z - mouth_z, 0.011)
            if p.y < mouth_y + 0.008:
                p.y += 0.0038 * w_lip * _smoothstep(mouth_y + 0.008, mouth_y - 0.004, p.y)
            dz_m = p.z - mouth_z
            if abs(dz_m) > 0.0025:
                p.z -= math.copysign(min(0.0024, (abs(dz_m) - 0.0025) * 0.35), dz_m) * w_lip

        if (mouth_z - 0.024) <= p.z <= (mouth_z - 0.009) and ax < 0.026 and p.y < mouth_y + 0.022:
            w_chin_tr = _gauss(ax, 0.016) * _gauss(p.z - (mouth_z - 0.015), 0.006)
            p.y -= 0.0024 * w_chin_tr

        verts[idx].co = p

    # Lift eyelash helpers identically with opened skin eyelids; leave helper-*-eye untouched
    # so .mhclo eye barycentric frames keep smooth round pupils without distortion
    for idx in lash_hs:
        verts[idx].co = _open_eyelid_pt(verts[idx].co)

    bm_obj.data.update()

    # Gentle localized smooth pass across brow, under-eye cheeks, and nasolabial zone
    # Strictly preserve opened eyelid opening rim, inner socket, and mouth opening seam!
    bm_sm = bmesh.new()
    bm_sm.from_mesh(bm_obj.data)
    bm_sm.verts.ensure_lookup_table()
    smooth_vs = [
        v
        for v in bm_sm.verts
        if v.index in body_vs
        and v.index not in ear_vs
        and v.co.z > z_neck_top + 0.015
        and v.co.y < eye_y + 0.008
        and not (abs(v.co.z - eye_z) < 0.022 and abs(abs(v.co.x) - eye_x) < 0.025)
        and not (abs(v.co.z - mouth_z) < 0.007 and abs(v.co.x) < 0.024)
        and not (abs(v.co.x) < 0.012 and (eye_z - 0.044) < v.co.z < (eye_z - 0.032))
    ]
    for _ in range(5):
        bmesh.ops.smooth_vert(
            bm_sm, verts=smooth_vs, factor=0.34, use_axis_x=True, use_axis_y=True, use_axis_z=True
        )
    bm_sm.to_mesh(bm_obj.data)
    bm_sm.free()
    bm_obj.data.update()


# ---------------------------------------------------------------------------
# 2. Solid Sculpted 3D Volume Lavender Hair (Zero Alpha-Clip Spaghetti!)
# ---------------------------------------------------------------------------

def _paint_hair_textures(tex_dir: Path) -> Tuple[Path, Path, Path]:
    """Paint opaque lavender hair + jagged white anime angel-ring specular halo textures."""
    hair_alb_path = tex_dir / "ghost_girl_hair_albedo.png"
    cap_alb_path = tex_dir / "ghost_girl_hair_cap_albedo.png"
    hair_orm_path = tex_dir / "ghost_girl_hair_orm.png"

    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)

    # Fine vertical strand striations along U
    s1 = np.sin(xx * math.pi * 38.0 + np.sin(yy * 7.0) * 0.35)
    s2 = np.sin(xx * math.pi * 86.0 + 1.1)
    strands = 0.50 + 0.30 * s1 + 0.20 * s2

    # Rich opaque lavender palette: #8B76BA root -> #BFAEE2 mid -> #D9CCFA tip
    root_col = np.array([0.545, 0.463, 0.729], dtype=np.float32)
    mid_col = np.array([0.749, 0.682, 0.886], dtype=np.float32)
    tip_col = np.array([0.851, 0.800, 0.980], dtype=np.float32)

    t_mid = np.clip((yy - 0.08) / 0.36, 0.0, 1.0)[:, :, None]
    t_tip = np.clip((yy - 0.56) / 0.40, 0.0, 1.0)[:, :, None]
    base_rgb = root_col * (1.0 - t_mid) + mid_col * t_mid
    base_rgb = base_rgb * (1.0 - t_tip) + tip_col * t_tip

    # Subtle cool/warm strand modulation across cross-section
    shade_mod = (0.93 + 0.09 * strands)[:, :, None]
    rgb = base_rgb * shade_mod

    # Painted jagged white anime angel-ring specular band around yy ~ 0.30 matching ref_head_back.jpg
    zig_center = 0.295 + 0.022 * np.sin(xx * math.pi * 3.0) + 0.010 * np.cos(xx * math.pi * 5.0)
    band_half = 0.024 + 0.006 * np.sin(xx * math.pi * 4.0)
    dist_halo = np.abs(yy - zig_center)
    halo_mask = np.clip(1.0 - dist_halo / np.maximum(band_half, 1e-4), 0.0, 1.0)
    # Sharpen into bold crisp anime cel highlight arcs with soft outer lavender glow
    halo_core = np.clip((halo_mask - 0.45) / 0.20, 0.0, 1.0)
    halo_glow = halo_mask * 0.28
    halo_amt = np.clip(halo_core * 0.88 + halo_glow, 0.0, 0.90)[:, :, None]

    # Secondary subtle highlight shimmer just below main ring
    zig_sub = 0.375 + 0.014 * np.sin(xx * math.pi * 4.0 + 0.8)
    sub_mask = np.clip(1.0 - np.abs(yy - zig_sub) / 0.013, 0.0, 1.0)
    sub_core = np.clip((sub_mask - 0.55) / 0.22, 0.0, 1.0)
    halo_amt = np.maximum(halo_amt, (sub_core * 0.45)[:, :, None])

    shine_col = np.array([0.965, 0.945, 1.000], dtype=np.float32)[None, None, :]
    rgb = rgb * (1.0 - halo_amt) + shine_col * halo_amt

    # Subtle tip highlight kiss & darker root under-shadow
    root_ao = np.clip(0.84 + 0.16 * (yy / 0.20), 0.84, 1.0)[:, :, None]
    rgb = np.clip(rgb * root_ao, 0.0, 1.0)
    _save_image(hair_alb_path, rgb)

    # Cap albedo: deep lavender root blending cleanly into mid lavender
    cap_rgb = np.clip(
        (root_col * (1.0 - 0.45 * np.clip(yy, 0.0, 1.0)[:, :, None]) + mid_col * 0.45 * np.clip(yy, 0.0, 1.0)[:, :, None])
        * (0.94 + 0.06 * strands[:, :, None]),
        0.0,
        1.0,
    )
    _save_image(cap_alb_path, cap_rgb)

    hair_orm = np.zeros((sz, sz, 3), dtype=np.float32)
    hair_orm[:, :, 0] = np.clip(0.76 + 0.24 * yy, 0.0, 1.0)
    hair_orm[:, :, 1] = np.clip(0.42 - 0.14 * halo_amt[:, :, 0], 0.26, 0.48)
    hair_orm[:, :, 2] = 0.0
    _save_image(hair_orm_path, hair_orm)
    return hair_alb_path, cap_alb_path, hair_orm_path


def _build_hair_cap(
    head_obj: bpy.types.Object,
    metrics: Dict[str, Vector | float],
    head_bvh: BVHTree,
    cap_mat: bpy.types.Material,
) -> bpy.types.Object:
    """Build snug cranial skull cap fitted directly onto head_obj above forehead/occiput."""
    hc = metrics["head_center"]
    z_crown = float(metrics["crown_z"])
    z_eye = float(metrics["eye_z"])
    z_ear = float(metrics["ear_y"].z)
    rx = float(metrics["skull_rx"]) + 0.0014
    ry_f = abs(float(metrics["forehead_y"]) - hc.y) + 0.0014
    ry_b = abs(float(metrics["hy_max"]) - hc.y) + 0.0014
    rz = max(z_crown - hc.z, 0.085) + 0.0014

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()

    n_rings = 7
    n_seg = 22
    apex_v = bm.verts.new(_push_outside_bvh(Vector((0.0, hc.y, z_crown + 0.002)), hc, head_bvh, 0.0014, 0.0035))

    rings: List[List[bmesh.types.BMVert]] = []
    for ri in range(1, n_rings + 1):
        rt = ri / float(n_rings)
        ring: List[bmesh.types.BMVert] = []
        for si in range(n_seg):
            az = (si / float(n_seg)) * math.tau  # 0 = front (-Y), pi = back (+Y)
            cos_a = math.cos(az)
            sin_a = math.sin(az)
            front_w = max(0.0, cos_a)
            # Stay cleanly above brows in front & above lower back bob so cap fills upper forehead gaps
            max_phi = (0.34 * math.pi) * (front_w ** 1.2) + (0.48 * math.pi) * (1.0 - front_w ** 1.2)
            phi = rt * max_phi
            ry = ry_f * (1.0 if cos_a >= 0.0 else 0.0) + ry_b * (1.0 if cos_a < 0.0 else 0.0)
            px = sin_a * rx * math.sin(phi)
            py = hc.y - cos_a * ry * math.sin(phi)
            pz = hc.z + rz * math.cos(phi)
            if front_w > 0.25 and pz < z_eye + 0.044:
                pz = z_eye + 0.044
            elif abs(cos_a) < 0.45 and pz < z_ear + 0.024:
                pz = z_ear + 0.024
            p = _push_outside_bvh(Vector((px, py, pz)), hc, head_bvh, 0.0012, 0.0028)
            ring.append(bm.verts.new(p))
        rings.append(ring)

    def _cap_uv(co: Vector) -> Tuple[float, float]:
        u = _clamp(0.5 + co.x / 0.20, 0.02, 0.98)
        v_uv = _clamp(1.0 - max(0.0, (z_crown + 0.005) - co.z) / 0.16, 0.05, 0.98)
        return (u, v_uv)

    for si in range(n_seg):
        sn = (si + 1) % n_seg
        f = bm.faces.new((apex_v, rings[0][si], rings[0][sn]))
        f.smooth = True
        for loop in f.loops:
            loop[uv_layer].uv = _cap_uv(loop.vert.co)

    for ri in range(len(rings) - 1):
        for si in range(n_seg):
            sn = (si + 1) % n_seg
            f = bm.faces.new((rings[ri][si], rings[ri + 1][si], rings[ri + 1][sn], rings[ri][sn]))
            f.smooth = True
            for loop in f.loops:
                loop[uv_layer].uv = _cap_uv(loop.vert.co)

    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median() - hc) < 0.0:
            f.normal_flip()
    cap_mesh = bpy.data.meshes.new("GhostGirl_Hair_Cap")
    bm.to_mesh(cap_mesh)
    bm.free()
    cap_mesh.materials.append(cap_mat)
    cap_obj = bpy.data.objects.new("GhostGirl_Hair_Cap", cap_mesh)
    bpy.context.collection.objects.link(cap_obj)
    return cap_obj


def _add_solid_hair_lock(
    bm: bmesh.types.BM,
    uv_layer: bmesh.types.BMLayerItem,
    pts: List[Vector],
    w_root: float,
    thick_ratio: float,
    hc: Vector,
    z_crown: float,
    tilt: float = 0.0,
    halo_z_span: float = 0.24,
) -> None:
    """Extrude a closed 5-sided convex-outer 3D hair lock tapering to a crisp pointed tip."""
    n = len(pts)
    if n < 3:
        return

    # 5 cross-section offsets: (side_mult, rad_mult, u_coord)
    # Broad curved anime ribbon arc [0,1,2,3] + tucked inner spine [4] so adjacent locks overlap cleanly
    profile: Tuple[Tuple[float, float, float], ...] = (
        (-0.54, -0.06, 0.08),
        (-0.24, 0.34, 0.30),
        (0.24, 0.34, 0.50),
        (0.54, -0.06, 0.70),
        (0.00, -0.34, 0.92),
    )

    rings: List[List[bmesh.types.BMVert]] = []
    ring_v_uvs: List[float] = []

    for i in range(n - 1):
        p = pts[i]
        t = i / float(n - 1)
        tang = (pts[1] - pts[0]) if i == 0 else (pts[i + 1] - pts[i - 1])
        if tang.length < 1e-6:
            tang = Vector((0.0, 0.0, -1.0))
        else:
            tang.normalize()

        rad = p - hc
        rad -= tang * rad.dot(tang)
        if rad.length < 1e-5:
            rad = Vector((0.0, -1.0, 0.0))
        else:
            rad.normalize()

        side = tang.cross(rad)
        if side.length < 1e-5:
            side = Vector((1.0, 0.0, 0.0))
        else:
            side.normalize()

        if abs(tilt) > 1e-4:
            side = (side * math.cos(tilt) + rad * math.sin(tilt)).normalized()
            rad = side.cross(tang).normalized()

        # Broad spoon/ribbon silhouette keeping full width down to mid-body then curving cleanly to tip
        swell = 1.0 + 0.16 * math.sin(min(t / 0.64, 1.0) * math.pi)
        tail_drop = _smoothstep(0.48, 1.0, t) ** 1.42
        taper = swell * (1.0 - 0.82 * tail_drop)
        w = max(0.0032, w_root * taper)
        th = max(0.0018, w * thick_ratio * (1.0 - 0.24 * t))

        ring: List[bmesh.types.BMVert] = []
        for s_m, r_m, _ in profile:
            co = p + side * (s_m * w) + rad * (r_m * th)
            ring.append(bm.verts.new(co))
        rings.append(ring)

        # Align V UV consistently by height drop below crown so the angel-ring halo forms a clean band
        z_drop = max(0.0, (z_crown + 0.006) - p.z)
        yy_z = _clamp(0.08 + 0.76 * (z_drop / halo_z_span), 0.06, 0.88)
        yy_blend = yy_z * (1.0 - 0.35 * (t ** 2)) + t * (0.35 * (t ** 2))
        ring_v_uvs.append(_clamp(1.0 - yy_blend, 0.04, 0.98))

    tip_v = bm.verts.new(pts[-1])

    # Closed root cap
    f_root = bm.faces.new(tuple(reversed(rings[0])))
    f_root.smooth = True
    for k, loop in enumerate(f_root.loops):
        loop[uv_layer].uv = (profile[4 - k][2], ring_v_uvs[0])

    # Tube segments
    for i in range(len(rings) - 1):
        r0 = rings[i]
        r1 = rings[i + 1]
        v0 = ring_v_uvs[i]
        v1 = ring_v_uvs[i + 1]
        for k in range(5):
            kn = (k + 1) % 5
            f = bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
            f.smooth = True
            f.loops[0][uv_layer].uv = (profile[k][2], v0)
            f.loops[1][uv_layer].uv = (profile[kn][2], v0)
            f.loops[2][uv_layer].uv = (profile[kn][2], v1)
            f.loops[3][uv_layer].uv = (profile[k][2], v1)

    # Closed pointed tip triangles
    r_last = rings[-1]
    v_last = ring_v_uvs[-1]
    for k in range(5):
        kn = (k + 1) % 5
        ft = bm.faces.new((r_last[k], r_last[kn], tip_v))
        ft.smooth = True
        ft.loops[0][uv_layer].uv = (profile[k][2], v_last)
        ft.loops[1][uv_layer].uv = (profile[kn][2], v_last)
        ft.loops[2][uv_layer].uv = (0.50, 0.01)


def build_sculpted_lavender_hair(
    head_obj: bpy.types.Object,
    head_lm: Optional[Dict[str, object]] = None,
    tex_dir: Path | str = DEFAULT_TEX_DIR,
) -> Tuple[bpy.types.Object, bpy.types.Object, Path, Path, Path]:
    """Build opaque 3D volume sculpted lavender hair (Cap + solid tapered volume locks).

    Returns `(cap_obj, cards_obj, hair_alb, hair_cap_alb, hair_orm)`.
    """
    t_dir = Path(tex_dir)
    hair_alb, cap_alb, hair_orm = _paint_hair_textures(t_dir)

    cap_mat = _make_pbr_material(
        "M_ghost_girl_hair_cap",
        albedo_path=cap_alb,
        orm_path=hair_orm,
        roughness=0.45,
        alpha_mode="OPAQUE",
        double_sided=False,
    )
    hair_mat = _make_pbr_material(
        "M_ghost_girl_hair",
        albedo_path=hair_alb,
        orm_path=hair_orm,
        roughness=0.40,
        alpha_mode="OPAQUE",
        double_sided=False,
    )

    metrics = _resolve_head_landmarks(head_obj, head_lm)
    body_vs = _body_or_all_indices(head_obj)
    head_bvh = _build_bvh(head_obj, body_vs)

    cap_obj = _build_hair_cap(head_obj, metrics, head_bvh, cap_mat)

    hc = metrics["head_center"]
    z_crown = float(metrics["crown_z"])
    z_eye = float(metrics["eye_z"])
    z_chin = float(metrics["chin"].z)
    z_ear = float(metrics["ear_y"].z)
    ear_y = float(metrics["ear_y"].y)
    ear_rx = float(metrics["ear_rx"])
    skull_rx = float(metrics["skull_rx"])
    forehead_y = float(metrics["forehead_y"])
    hy_max = float(metrics["hy_max"])

    dome_cz = z_eye + 0.022
    dome_rx = max(0.088, skull_rx + 0.002)
    dome_ry_f = max(0.095, abs(forehead_y - hc.y) + 0.002)
    dome_ry_b = max(0.105, abs(hy_max - hc.y) + 0.002)
    dome_rz = max(z_crown - dome_cz + 0.002, 0.090)

    def _fit_lock_pts(pts: List[Vector], clearance: float = 0.0036, inside_hood: bool = True) -> List[Vector]:
        out: List[Vector] = []
        for idx_p, pt in enumerate(pts):
            max_push = 0.012 if inside_hood else 0.036
            p = _push_outside_bvh(pt, hc, head_bvh, clearance, max_cap=max_push)
            # Keep upper crown, upper sides, and upper occiput snugly within hood dome envelope
            if inside_hood and (p.z > z_eye + 0.012 or (p.y > hc.y - 0.030 and p.z > z_ear - 0.020)):
                loc, _, _, _ = head_bvh.find_nearest(p)
                if loc is not None:
                    delta = p - loc
                    max_d = 0.0062 if p.z > z_eye + 0.034 else 0.0074
                    if delta.length > max_d:
                        p = loc + delta.normalized() * max_d
            # Clear protruding ears smoothly below ear top
            if (z_ear - 0.024) <= p.z <= (z_ear + 0.024) and abs(p.y - ear_y) < 0.030 and idx_p > 1:
                min_ex = ear_rx + 0.0045
                if abs(p.x) < min_ex:
                    p.x = (1.0 if p.x >= 0.0 else -1.0) * min_ex
            out.append(p)
        return out

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()

    # ------------------------------------------------------------------
    # A. Back & Side Multi-Tier Shaggy Wavy Bob (matching ref_head_back.jpg)
    #    Wide lush shingled 3D ribbons wrapping back & sides of neck cleanly down to collar
    # ------------------------------------------------------------------
    tier_specs = (
        # (n_locks, span_pi, r_off, w_root, thick, z_base_off, flare_out, wave_amp, phase, steps, inside_hood)
        # Odd lock counts put center curtain locks squarely over nape (az=pi) for zero neck gap
        (15, 0.72, 0.0035, 0.054, 0.28, -0.050, -0.002, 0.0035, 0.00, 7, True),
        (13, 0.68, 0.0065, 0.048, 0.27, -0.026, 0.008, 0.0045, 0.45, 8, True),
        (13, 0.65, 0.0090, 0.038, 0.26, 0.004, 0.016, 0.0040, 0.20, 9, True),
    )
    for n_locks, span_pi, r_off, w_root, thick, z_off, flare_out, wave_amp, phase, steps, in_hood in tier_specs:
        for k in range(n_locks):
            u_span = (k / float(max(n_locks - 1, 1))) * 2.0 - 1.0
            az = u_span * (math.pi * span_pi) + math.pi + (phase * math.pi * span_pi / float(max(n_locks - 1, 1)))
            back_center = abs(((az - math.pi + math.pi) % math.tau) - math.pi)
            is_outer_side = back_center > 1.38

            taper_len = 0.010 * math.sin(k * 2.4 + phase)
            if abs(abs(u_span) - 0.28) < 0.16 and z_off < -0.020:
                taper_len -= 0.012
            z_end = z_chin + z_off + taper_len
            if is_outer_side:
                z_end += 0.008

            pts: List[Vector] = []
            for s in range(steps):
                t = s / float(steps - 1)
                if t <= 0.58:
                    phi = 0.14 + (t / 0.58) * (math.pi * 0.52)
                    rx = (dome_rx + r_off * 0.65) * math.sin(phi)
                    ry = (dome_ry_b + r_off * 0.65) * math.sin(phi)
                    pz = dome_cz + (dome_rz + r_off * 0.25) * math.cos(phi)
                else:
                    u_lo = (t - 0.58) / 0.42
                    z_start_lo = dome_cz + (dome_rz + r_off * 0.25) * math.cos(0.66 * math.pi)
                    wave = math.sin(u_lo * math.pi * 1.10 + k * 1.15) * wave_amp
                    curl_in = -0.014 * (u_lo ** 1.8) if z_off < -0.015 else (flare_out * (u_lo ** 1.35))
                    flare = flare_out * math.sin(u_lo * math.pi * 0.85) + curl_in
                    base_r_lo = math.sin(0.66 * math.pi)
                    rx = (dome_rx + r_off * 0.65) * base_r_lo + (0.010 * u_lo) + wave + flare
                    ry = (dome_ry_b + r_off * 0.65) * base_r_lo + (0.010 * u_lo) + wave * 0.6 + flare * 0.85
                    pz = z_start_lo * (1.0 - u_lo) + z_end * u_lo
                px = math.sin(az) * rx
                py = hc.y - math.cos(az) * ry
                pts.append(Vector((px, py, pz)))

            pts = _fit_lock_pts(pts, clearance=0.0040, inside_hood=in_hood)
            _add_solid_hair_lock(
                bm,
                uv_layer,
                pts,
                w_root=w_root,
                thick_ratio=thick,
                hc=hc,
                z_crown=z_crown,
                tilt=0.08 * math.sin(k * 2.1),
            )

    # ------------------------------------------------------------------
    # B. Layered Cheek-Framing Side Locks (left +X and right -X)
    #    Full overlapping curved ribbons hugging outside wider cheeks cleanly to chin/collar
    # ------------------------------------------------------------------
    eye_plane_y = float(metrics["eye_y"]) + 0.012
    side_specs = (
        (0.95, 0.68, -0.026, 0.056, -0.018, 0.025, 0.0055),
        (1.12, 0.86, -0.018, 0.068, -0.012, 0.029, 0.0065),
        (1.28, 1.06, -0.008, 0.084, -0.016, 0.032, 0.0070),
        (1.46, 1.28, 0.006, 0.096, -0.008, 0.034, 0.0070),
    )
    for sx in (-1.0, 1.0):
        for li, (az0, az1, y_pull, x_hug, z_off, w_r, c_amp) in enumerate(side_specs):
            z_end = z_chin + z_off
            pts = []
            steps = 8
            for s in range(steps):
                t = s / float(steps - 1)
                az = sx * (az0 * (1.0 - t) + az1 * t)
                if t <= 0.42:
                    phi = 0.14 + (t / 0.42) * (math.pi * 0.44)
                    rx = (dome_rx + 0.004) * math.sin(phi)
                    ry = (dome_ry_f + 0.004) * math.sin(phi)
                    pz = dome_cz + (dome_rz + 0.003) * math.cos(phi)
                    px = math.sin(az) * rx
                    py = hc.y - math.cos(az) * ry
                else:
                    u_l = (t - 0.42) / 0.58
                    swell = c_amp * math.sin(u_l * math.pi)
                    px_surf = math.sin(az) * (dome_rx + 0.006 + swell)
                    px = px_surf * (1.0 - 0.55 * (u_l ** 1.5)) + (sx * x_hug) * (0.55 * (u_l ** 1.5))
                    py_surf = hc.y - math.cos(az) * (dome_ry_f + 0.005)
                    py = py_surf + y_pull * (u_l ** 1.2)
                    pz = dome_cz * (1.0 - u_l) + z_end * u_l
                    if pz < z_eye + 0.034:
                        py = max(py, eye_plane_y - 0.008 if li == 0 else eye_plane_y + 0.002)
                pts.append(Vector((px, py, pz)))
            pts = _fit_lock_pts(pts, clearance=0.0046, inside_hood=False)
            _add_solid_hair_lock(
                bm,
                uv_layer,
                pts,
                w_root=w_r,
                thick_ratio=0.30,
                hc=hc,
                z_crown=z_crown,
                tilt=0.10 * sx,
            )

    # ------------------------------------------------------------------
    # C. Center-Parted M-Shaped Tapered Front Bangs (matching ref_head_front_side.jpg)
    # ------------------------------------------------------------------
    z_brow = float(metrics["brow_z"])
    bang_specs = (
        (0.00, 0.00, z_brow + 0.016, 0.028, 0.0045, -0.0045),
        (-0.04, -0.08, z_eye + 0.005, 0.025, 0.0035, -0.0045),
        (0.04, 0.08, z_eye + 0.006, 0.025, 0.0035, -0.0045),
        (-0.11, -0.17, z_eye + 0.018, 0.021, 0.0055, -0.0055),
        (0.11, 0.17, z_eye + 0.018, 0.021, 0.0055, -0.0055),
        (-0.20, -0.44, z_brow + 0.012, 0.029, 0.0045, -0.0045),
        (0.20, 0.44, z_brow + 0.012, 0.029, 0.0045, -0.0045),
        (-0.32, -0.60, z_brow + 0.012, 0.028, 0.0055, -0.0055),
        (0.32, 0.60, z_brow + 0.012, 0.028, 0.0055, -0.0055),
        (-0.46, -0.74, z_brow + 0.008, 0.027, 0.0065, -0.0055),
        (0.46, 0.74, z_brow + 0.008, 0.027, 0.0065, -0.0055),
        (-0.78, -0.92, z_eye + 0.004, 0.026, 0.0050, -0.0035),
        (0.78, 0.92, z_eye + 0.004, 0.026, 0.0050, -0.0035),
        (-0.72, -0.94, z_eye + 0.014, 0.026, 0.0065, -0.0045),
        (0.72, 0.94, z_eye + 0.014, 0.026, 0.0065, -0.0045),
    )
    for bi, (u_r, u_t, z_tip, w_r, r_off, y_lift) in enumerate(bang_specs):
        pts = []
        steps = 7
        for s in range(steps):
            t = s / float(steps - 1)
            u_cur = u_r * (1.0 - t) + u_t * t
            az = u_cur * 0.88
            phi = 0.14 + t * (math.pi * 0.44)
            rx = (dome_rx + r_off) * math.sin(phi)
            ry = (dome_ry_f + r_off) * math.sin(phi)
            pz_d = dome_cz + (dome_rz + r_off * 0.35) * math.cos(phi)
            pz = pz_d * (1.0 - t ** 1.15) + z_tip * (t ** 1.15)
            px = math.sin(az) * rx
            py = hc.y - math.cos(az) * ry
            arch = math.sin(t * math.pi) * (t ** 0.7) * y_lift
            py = min(py, forehead_y + 0.020 * (u_cur * u_cur) + arch - r_off * 0.25)
            pts.append(Vector((px, py, pz)))
        pts = _fit_lock_pts(pts, clearance=0.0042, inside_hood=True)
        _add_solid_hair_lock(
            bm,
            uv_layer,
            pts,
            w_root=w_r,
            thick_ratio=0.30,
            hc=hc,
            z_crown=z_crown,
            tilt=0.07 * (1.0 if u_t >= 0.0 else -1.0),
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    cards_mesh = bpy.data.meshes.new("GhostGirl_Hair_Cards")
    bm.to_mesh(cards_mesh)
    bm.free()
    cards_mesh.materials.append(hair_mat)
    cards_obj = bpy.data.objects.new("GhostGirl_Hair_Cards", cards_mesh)
    bpy.context.collection.objects.link(cards_obj)
    return cap_obj, cards_obj, hair_alb, cap_alb, hair_orm


# ---------------------------------------------------------------------------
# 3. Snug Draped Ghost Hood + Ghost Eyes + Left Ear-Flop + Bat & Pumpkin Clips
# ---------------------------------------------------------------------------

def _paint_hood_textures(tex_dir: Path) -> Tuple[Path, Path]:
    """Paint 1024x1024 atlas for GhostGirl_Hood (white cloth, charcoal ghost eyes, bat & pumpkin clips)."""
    alb_p = tex_dir / "ghost_girl_hood_albedo.png"
    orm_p = tex_dir / "ghost_girl_hood_orm.png"
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)

    # Atlas layout (top-down row yy = 1 - v_uv):
    # - xx < 0.52: Outer white ghost hood cloth (#F5F6FC) with 2 dark charcoal ghost-eye ovals
    # - xx in [0.52, 0.72]: Pale lavender-grey inner cloth lining (#E0DFEE)
    # - xx >= 0.72, yy < 0.50: Dark charcoal bat wing clips (#1E1A26)
    # - xx >= 0.72, yy >= 0.50: Smiling jack-o'-lantern pumpkin clip (#F27A22) + green stem
    alb = np.zeros((sz, sz, 3), dtype=np.float32)
    fold = 0.022 * np.sin(xx * math.pi * 16.0) * yy
    alb[:, :, 0] = 0.962 - fold * 1.1
    alb[:, :, 1] = 0.965 - fold * 1.0
    alb[:, :, 2] = 0.986 - fold * 0.4

    inner_m = (xx >= 0.52) & (xx < 0.72)
    alb[inner_m] = np.array([0.878, 0.875, 0.935], dtype=np.float32)

    # 2 crisp dark charcoal ghost-eye ovals lowered onto visible upper-front forehead dome slope
    for cx_e, tilt_e in ((0.192, 0.09), (0.328, -0.09)):
        dx = xx - cx_e
        dy = yy - 0.675
        rx = dx * math.cos(tilt_e) - dy * math.sin(tilt_e)
        ry = dx * math.sin(tilt_e) + dy * math.cos(tilt_e)
        d_eye = np.sqrt((rx / 0.022) ** 2 + (ry / 0.046) ** 2)
        w_e = np.clip((1.0 - d_eye) / 0.05, 0.0, 1.0)[:, :, None]
        eye_col = np.array([0.110, 0.098, 0.140], dtype=np.float32)
        alb = alb * (1.0 - w_e) + eye_col[None, None, :] * w_e

    bat_m = (xx >= 0.72) & (yy < 0.50)
    alb[bat_m] = np.array([0.115, 0.100, 0.150], dtype=np.float32)

    pump_m = (xx >= 0.72) & (yy >= 0.50)
    u_p = (xx - 0.72) / 0.28
    v_p = (yy - 0.50) / 0.50
    rib = 0.060 * np.sin(u_p * math.pi * 6.0)
    p_orange = np.stack([
        np.clip(0.955 - 0.08 * rib, 0.0, 1.0),
        np.clip(0.475 - 0.07 * rib, 0.0, 1.0),
        np.clip(0.115 - 0.03 * rib, 0.0, 1.0),
    ], axis=2)
    alb = np.where(pump_m[:, :, None], p_orange, alb)

    stem_m = pump_m & (v_p < 0.16)
    alb[stem_m] = np.array([0.235, 0.365, 0.185], dtype=np.float32)

    dark_face = np.array([0.105, 0.082, 0.102], dtype=np.float32)
    tri_l = (np.abs(u_p - 0.35) < 0.090 * np.clip((v_p - 0.32) / 0.15, 0.0, 1.0)) & (v_p >= 0.32) & (v_p <= 0.47)
    tri_r = (np.abs(u_p - 0.65) < 0.090 * np.clip((v_p - 0.32) / 0.15, 0.0, 1.0)) & (v_p >= 0.32) & (v_p <= 0.47)
    nose_t = (np.abs(u_p - 0.50) < 0.045 * np.clip((v_p - 0.49) / 0.08, 0.0, 1.0)) & (v_p >= 0.49) & (v_p <= 0.57)
    smile_curve = 0.74 - 0.16 * ((u_p - 0.50) / 0.28) ** 2
    tooth = 0.030 * np.sin(u_p * 34.0)
    mouth_m = pump_m & (np.abs(u_p - 0.50) < 0.26) & (v_p >= smile_curve - 0.07 + tooth) & (v_p <= smile_curve + 0.04)
    alb[pump_m & (tri_l | tri_r | nose_t | mouth_m)] = dark_face

    _save_image(alb_p, alb)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = np.where(bat_m | pump_m, 0.46, 0.78)
    orm[:, :, 2] = 0.0
    _save_image(orm_p, orm)
    return alb_p, orm_p


def _add_bat_clip(
    bm: bmesh.types.BM,
    uv_layer: bmesh.types.BMLayerItem,
    sx: float,
    center: Vector,
    hair_bvh: Optional[BVHTree],
) -> None:
    """Add crisp scalloped bat wing hair clip seated flush on outer side bangs inside hood rim."""
    # Sleek scalloped anime bat silhouette (local X outward, local Z up)
    bat_pts = [
        Vector((0.0, 0.0, 0.0034)),
        Vector((sx * 0.0032, 0.0, 0.0076)),   # inner ear
        Vector((sx * 0.0056, 0.0, 0.0038)),
        Vector((sx * 0.0138, 0.0036, 0.0062)), # outer wing tip
        Vector((sx * 0.0116, 0.0028, -0.0018)),
        Vector((sx * 0.0080, 0.0018, -0.0005)),
        Vector((sx * 0.0052, 0.0010, -0.0034)),
        Vector((0.0, 0.0, -0.0044)),           # tail point
        Vector((-sx * 0.0052, 0.0010, -0.0034)),
        Vector((-sx * 0.0080, 0.0018, -0.0005)),
        Vector((-sx * 0.0116, 0.0028, -0.0018)),
        Vector((-sx * 0.0138, 0.0036, 0.0062)),
        Vector((-sx * 0.0056, 0.0, 0.0038)),
        Vector((-sx * 0.0032, 0.0, 0.0076)),  # outer ear
    ]
    # Angle cleanly outward & wrap gently around curved temple bangs (clear of eyebrows!)
    rot_b = (
        Matrix.Rotation(sx * 0.56, 3, "Z")
        @ Matrix.Rotation(-0.14, 3, "X")
        @ Matrix.Rotation(sx * 0.42, 3, "Y")
    )
    c_pos = center.copy()
    if hair_bvh is not None:
        # Raycast diagonally inward from front-temple air toward cranial center so clip hugs side bangs
        ray_origin = Vector((c_pos.x + sx * 0.045, c_pos.y - 0.075, c_pos.z + 0.006))
        ray_dir = (Vector((sx * 0.025, c_pos.y + 0.040, c_pos.z - 0.004)) - ray_origin).normalized()
        loc, nrm, _, _ = hair_bvh.ray_cast(ray_origin, ray_dir)
        if loc is None:
            loc, nrm, _, _ = hair_bvh.find_nearest(c_pos)
        if loc is not None:
            out_n = nrm.normalized() if nrm.length > 1e-4 else Vector((sx * 0.55, -0.82, 0.12)).normalized()
            if out_n.y > 0.15:
                out_n = -out_n
            c_pos = loc + out_n * 0.0044

    front_vs = [bm.verts.new(c_pos + rot_b @ (pt + Vector((0.0, -0.0018, 0.0)))) for pt in bat_pts]
    back_vs = [bm.verts.new(c_pos + rot_b @ (pt + Vector((0.0, 0.0018, 0.0)))) for pt in bat_pts]
    c_f = bm.verts.new(c_pos + rot_b @ Vector((0.0, -0.0024, 0.0)))
    c_b = bm.verts.new(c_pos + rot_b @ Vector((0.0, 0.0024, 0.0)))
    nb = len(bat_pts)
    for i in range(nb):
        inext = (i + 1) % nb
        ff = bm.faces.new((c_f, front_vs[i], front_vs[inext]))
        fb = bm.faces.new((c_b, back_vs[inext], back_vs[i]))
        fs = bm.faces.new((front_vs[i], back_vs[i], back_vs[inext], front_vs[inext]))
        for face in (ff, fb, fs):
            face.smooth = False
            for loop in face.loops:
                loop[uv_layer].uv = (0.86, 0.75)


def _add_pumpkin_clip(
    bm: bmesh.types.BM,
    uv_layer: bmesh.types.BMLayerItem,
    center: Vector,
    hair_bvh: Optional[BVHTree],
) -> None:
    """Add ribbed smiling jack-o'-lantern pumpkin clip flush on upper-left (+X) outer bangs."""
    p_center = center.copy()
    if hair_bvh is not None:
        ray_origin = Vector((p_center.x + 0.040, p_center.y - 0.075, p_center.z + 0.008))
        ray_dir = (Vector((0.022, p_center.y + 0.045, p_center.z - 0.006)) - ray_origin).normalized()
        loc, nrm, _, _ = hair_bvh.ray_cast(ray_origin, ray_dir)
        if loc is None:
            loc, nrm, _, _ = hair_bvh.find_nearest(p_center)
        if loc is not None:
            out_n = nrm.normalized() if nrm.length > 1e-4 else Vector((0.42, -0.85, 0.30)).normalized()
            if out_n.y > 0.15:
                out_n = -out_n
            p_center = loc + out_n * 0.0068

    rot_p = Matrix.Rotation(0.52, 3, "Z") @ Matrix.Rotation(-0.20, 3, "X")
    ret_p = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.0128)
    for v in ret_p["verts"]:
        ang_p = math.atan2(v.co.y, v.co.x)
        rib = 1.0 + 0.09 * math.cos(ang_p * 7.0)
        lp = Vector((v.co.x * rib * 1.12, v.co.y * rib * 0.60, v.co.z * 0.88))
        v.co = p_center + rot_p @ lp
    for f in {f for v in ret_p["verts"] for f in v.link_faces}:
        f.smooth = True
        for loop in f.loops:
            local_p = rot_p.inverted() @ (loop.vert.co - p_center)
            u = 0.86 + (local_p.x / 0.030) * 0.12
            v_uv = 0.21 + (local_p.z / 0.024) * 0.20
            if local_p.y > 0.002:
                u, v_uv = 0.78, 0.08
            loop[uv_layer].uv = (_clamp(u, 0.73, 0.99), _clamp(v_uv, 0.01, 0.40))

    ret_st = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.0030, radius2=0.0016, depth=0.0075
    )
    for v in ret_st["verts"]:
        lp = Vector((v.co.x, v.co.y, v.co.z + 0.0125))
        v.co = p_center + rot_p @ lp
    for f in {f for v in ret_st["verts"] for f in v.link_faces}:
        f.smooth = True
        for loop in f.loops:
            loop[uv_layer].uv = (0.86, 0.46)


def build_ghost_hood(
    head_obj: bpy.types.Object,
    head_lm: Optional[Dict[str, object]] = None,
    tex_dir: Path | str = DEFAULT_TEX_DIR,
) -> Tuple[bpy.types.Object, Path, Path]:
    """Build snug draped GhostGirl_Hood with lowered ghost eyes, +X ear-flop, bat & pumpkin clips.

    Returns `(hood_obj, hood_alb, hood_orm)`.
    """
    t_dir = Path(tex_dir)
    alb_p, orm_p = _paint_hood_textures(t_dir)
    hood_mat = _make_pbr_material(
        "M_ghost_girl_hood",
        albedo_path=alb_p,
        orm_path=orm_p,
        roughness=0.76,
        alpha_mode="OPAQUE",
        double_sided=True,
    )

    metrics = _resolve_head_landmarks(head_obj, head_lm)
    body_vs = _body_or_all_indices(head_obj)
    head_bvh = _build_bvh(head_obj, body_vs)

    hair_obj = bpy.data.objects.get("GhostGirl_Hair_Cards")
    hair_bvh = _build_bvh(hair_obj) if hair_obj is not None else None

    hc = metrics["head_center"]
    z_crown = float(metrics["crown_z"])
    z_eye = float(metrics["eye_z"])
    z_chin = float(metrics["chin"].z)
    z_ear = float(metrics["ear_y"].z)
    ear_rx = float(metrics["ear_rx"])
    skull_rx = float(metrics["skull_rx"])
    forehead_y = float(metrics["forehead_y"])
    hy_max = float(metrics["hy_max"])

    cz = z_eye + 0.022
    cy = hc.y + 0.008
    rx_cheek = max(0.116, ear_rx + 0.022)
    ry_back = max(0.130, (hy_max - cy) + 0.028)
    crown_apex = Vector((0.0, cy - 0.004, z_crown + 0.038))

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()

    n_rings = 18
    n_seg = 56

    def _pw_lerp(knots: Sequence[Tuple[float, float]], x: float) -> float:
        if x <= knots[0][0]:
            return knots[0][1]
        for idx_k in range(len(knots) - 1):
            x0, y0 = knots[idx_k]
            x1, y1 = knots[idx_k + 1]
            if x <= x1:
                t = _smoothstep(x0, x1, x)
                return y0 * (1.0 - t) + y1 * t
        return knots[-1][1]

    # Smooth monotonic rim knots over a_abs in [0..pi]; convex forehead arch, smooth monotonic cheek wrap,
    # and gently scalloped back hem revealing full shaggy lavender bob without creases or hair poke-through
    z_knots = (
        (0.00, z_crown - 0.024),
        (0.20 * math.pi, z_crown - 0.048),
        (0.42 * math.pi, z_eye + 0.006),
        (0.58 * math.pi, z_chin + 0.018),
        (0.76 * math.pi, z_ear - 0.024),
        (math.pi, z_ear - 0.028),
    )
    rx_knots = (
        (0.00, max(0.098, skull_rx + 0.008)),
        (0.20 * math.pi, max(0.105, skull_rx + 0.011)),
        (0.42 * math.pi, rx_cheek + 0.004),
        (0.58 * math.pi, rx_cheek - 0.002),
        (0.76 * math.pi, rx_cheek - 0.002),
        (math.pi, rx_cheek * 0.94),
    )
    y_knots = (
        (0.00, forehead_y - 0.004),
        (0.20 * math.pi, forehead_y + 0.010),
        (0.42 * math.pi, forehead_y + 0.038),
        (0.58 * math.pi, cy - 0.022),
        (0.76 * math.pi, cy + 0.048),
        (math.pi, cy + ry_back),
    )

    def hood_ring_pt(ring_t: float, seg_u: float) -> Vector:
        az = seg_u * math.tau  # 0 = front (-Y), pi/2 = left (+X), pi = back (+Y)
        a_abs = abs(((az + math.pi) % math.tau) - math.pi)
        cos_a = math.cos(az)
        sin_a = math.sin(az)
        front_w = max(0.0, cos_a)
        back_w = max(0.0, -cos_a)

        w_back_hem = _smoothstep(0.68 * math.pi, 0.86 * math.pi, a_abs)
        jagged_back = -0.020 * (0.5 - 0.5 * math.cos(az * 6.0)) * w_back_hem
        edge_z = _pw_lerp(z_knots, a_abs) + jagged_back
        edge_rx = _pw_lerp(rx_knots, a_abs)
        edge_y = _pw_lerp(y_knots, a_abs)
        edge_x = sin_a * edge_rx

        phi = ring_t * (math.pi * 0.50)
        h_drop = 1.0 - math.cos(phi)
        r_ease = math.sin(phi)

        # Smooth pillowy hood drape; gentle lower cheek tuck near rim only
        side_puff = 1.0 + 0.100 * math.sin(ring_t * math.pi) * (1.0 - 0.40 * front_w)
        flap_tuck = _gauss(a_abs - 0.54 * math.pi, 0.28) * _smoothstep(0.80, 1.0, ring_t)
        px = edge_x * r_ease * side_puff - sin_a * (0.012 * flap_tuck)
        py = crown_apex.y + (edge_y - crown_apex.y) * r_ease * (1.0 + 0.14 * math.sin(ring_t * math.pi) * back_w)
        iso_z = crown_apex.z - 0.030 * (1.0 - math.cos(phi))
        rim_z = crown_apex.z + (edge_z - crown_apex.z) * h_drop + 0.012 * math.sin(ring_t * math.pi) * back_w
        w_iso = _smoothstep(0.08, 0.44, ring_t)
        pz = iso_z * (1.0 - w_iso) + rim_z * w_iso

        # Cute left-side (+X) soft curved ghost ear-flop gently drooping off upper-left hood corner
        d_ear_az = ((az - 1.38 + math.pi) % math.tau) - math.pi
        ear_d2 = (d_ear_az / 0.18) ** 2 + ((ring_t - 0.30) / 0.13) ** 2
        ear_flop = math.exp(-0.5 * (ear_d2 ** 0.72))
        px += 0.068 * ear_flop
        py += 0.020 * ear_flop
        pz += 0.008 * ear_flop

        p = Vector((px, py, pz))
        p = _push_outside_bvh(p, hc, head_bvh, 0.016, max_cap=None)
        if hair_bvh is not None and (p.z > z_eye + 0.012 or p.y > hc.y - 0.055):
            p = _push_outside_bvh(p, hc, hair_bvh, 0.0110, max_cap=None)
        return p

    apex_v = bm.verts.new(crown_apex)
    ring_pts: List[List[Vector]] = [
        [hood_ring_pt(ri / float(n_rings), si / float(n_seg)) for si in range(n_seg)]
        for ri in range(1, n_rings + 1)
    ]
    # Smooth cloth dome uniformly across forehead part, front rim arch, and back occiput seam
    for _ in range(5):
        next_pts = [[pt.copy() for pt in row] for row in ring_pts]
        for ri in range(1, n_rings):
            for si in range(n_seg):
                az = (si / float(n_seg)) * math.tau
                a_abs = abs(((az + math.pi) % math.tau) - math.pi)
                # Preserve back hem scallop silhouette at rim while smoothing front arch & dome interior
                if ri == n_rings - 1 and a_abs >= 0.36 * math.pi:
                    continue
                s_p = (si - 1) % n_seg
                s_n = (si + 1) % n_seg
                if ri == n_rings - 1:
                    avg = (ring_pts[ri][s_p] + ring_pts[ri][s_n]) * 0.5
                else:
                    avg = (
                        ring_pts[ri][s_p] + ring_pts[ri][s_n]
                        + ring_pts[ri - 1][si] + ring_pts[ri + 1][si]
                    ) * 0.25
                # Preserve crisp silhouette of the +X ghost ear-flop around az=1.38
                ear_protect = _gauss(((az - 1.38 + math.pi) % math.tau) - math.pi, 0.26)
                blend = 0.56 * (1.0 - 0.88 * ear_protect)
                cand = ring_pts[ri][si].lerp(avg, blend)
                if hair_bvh is not None and a_abs > 0.14 * math.pi and (cand.z > z_eye + 0.012 or cand.y > hc.y - 0.055):
                    cand = _push_outside_bvh(cand, hc, hair_bvh, 0.0080, max_cap=None)
                elif a_abs <= 0.14 * math.pi:
                    cand = _push_outside_bvh(cand, hc, head_bvh, 0.0220, max_cap=None)
                next_pts[ri][si] = cand
        ring_pts = next_pts

    rings: List[List[bmesh.types.BMVert]] = [
        [bm.verts.new(pt) for pt in row] for row in ring_pts
    ]

    # Curled inner lining along open rim & bottom hem
    inner_ring: List[bmesh.types.BMVert] = []
    for ov in rings[-1]:
        in_dir = Vector((0.0, cy, cz)) - ov.co
        in_dir.z *= 0.20
        in_dir = in_dir.normalized() if in_dir.length > 1e-4 else Vector((0.0, 1.0, 0.0))
        inner_ring.append(bm.verts.new(ov.co + in_dir * 0.006 + Vector((0.0, 0.004, 0.002))))
    inner_deep: List[bmesh.types.BMVert] = []
    for ov in inner_ring:
        in_dir = Vector((0.0, cy, cz)) - ov.co
        in_dir.z *= 0.12
        in_dir = in_dir.normalized() if in_dir.length > 1e-4 else Vector((0.0, 1.0, 0.0))
        inner_deep.append(bm.verts.new(ov.co + in_dir * 0.011 + Vector((0.0, 0.010, 0.003))))

    def map_hood_uv(p: Vector, is_inner: bool = False) -> Tuple[float, float]:
        if is_inner:
            return (0.62, 0.50)
        # Continuous frontal-slope UV projection placing ghost eyes on visible front-upper hood dome
        dy_f = -(p.y - cy)
        dz_u = p.z - cz
        pitch = math.atan2(max(0.0, dy_f), max(1e-4, dz_u)) if dz_u > 0.0 else 1.40
        if dy_f < 0.0:
            pitch = 0.0
        u = _clamp(0.26 + p.x * 1.95, 0.02, 0.50)
        t_p = _clamp((pitch - 0.12) / 0.88, 0.0, 1.0)
        v_uv = 0.94 - 0.84 * t_p
        return (u, _clamp(v_uv, 0.04, 0.96))

    for si in range(n_seg):
        sn = (si + 1) % n_seg
        f = bm.faces.new((apex_v, rings[0][si], rings[0][sn]))
        f.smooth = True
        for loop in f.loops:
            loop[uv_layer].uv = map_hood_uv(loop.vert.co)

    for ri in range(len(rings) - 1):
        for si in range(n_seg):
            sn = (si + 1) % n_seg
            f = bm.faces.new((rings[ri][si], rings[ri + 1][si], rings[ri + 1][sn], rings[ri][sn]))
            f.smooth = True
            for loop in f.loops:
                loop[uv_layer].uv = map_hood_uv(loop.vert.co)

    for r0, r1 in ((rings[-1], inner_ring), (inner_ring, inner_deep)):
        for si in range(n_seg):
            sn = (si + 1) % n_seg
            f = bm.faces.new((r0[si], r1[si], r1[sn], r0[sn]))
            f.smooth = True
            for loop in f.loops:
                loop[uv_layer].uv = map_hood_uv(loop.vert.co, is_inner=True)

    # Bat wing clips OUTWARD on outer temple/cheek-side bangs near inner hood rim (off eyebrows!)
    clip_y_base = forehead_y + 0.024
    for sx in (-1.0, 1.0):
        bat_center = Vector((sx * 0.078, clip_y_base, z_eye + 0.028))
        _add_bat_clip(bm, uv_layer, sx, bat_center, hair_bvh)

    # Smiling jack-o'-lantern pumpkin clip flush on her left (+X) upper temple bangs above left bat clip
    pumpkin_center = Vector((0.068, clip_y_base - 0.002, z_eye + 0.056))
    _add_pumpkin_clip(bm, uv_layer, pumpkin_center, hair_bvh)

    # Ensure outer hood faces point outward from head center (avoid recalc_face_normals flipping open sheet)
    bm.normal_update()
    for f in bm.faces:
        u0 = f.loops[0][uv_layer].uv[0]
        if u0 < 0.52:
            if f.normal.dot(f.calc_center_median() - hc) < 0.0:
                f.normal_flip()
    clip_faces = [f for f in bm.faces if f.loops[0][uv_layer].uv[0] >= 0.72]
    if clip_faces:
        bmesh.ops.recalc_face_normals(bm, faces=clip_faces)
    hood_mesh = bpy.data.meshes.new("GhostGirl_Hood")
    bm.to_mesh(hood_mesh)
    bm.free()
    hood_mesh.materials.append(hood_mat)
    hood_obj = bpy.data.objects.new("GhostGirl_Hood", hood_mesh)
    bpy.context.collection.objects.link(hood_obj)
    return hood_obj, alb_p, orm_p


# ---------------------------------------------------------------------------
# 4. Outfit Polish Builders (CropTop, Skirt, Cape, Gloves, Boots)
# ---------------------------------------------------------------------------

def _paint_croptop_textures(tex_dir: Path) -> Tuple[Path, Path]:
    """Paint 1024x1024 atlas for GhostGirl_CropTop (turtleneck, silver chain, B&W sweetheart)."""
    alb_p = tex_dir / "ghost_girl_croptop_albedo.png"
    orm_p = tex_dir / "ghost_girl_croptop_orm.png"
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)

    # Atlas layout (top-down yy = 1 - v_uv):
    # - xx < 0.70: torso wrap (xx=0.35 center front), B&W sweetheart panel + white jagged hem
    # - xx in [0.72, 0.88]: turtleneck collar & halter yoke (charcoal black)
    # - xx >= 0.90: silver metallic chain clasp
    black_col = np.array([0.110, 0.100, 0.140], dtype=np.float32)
    white_col = np.array([0.958, 0.958, 0.982], dtype=np.float32)
    silver_col = np.array([0.865, 0.885, 0.930], dtype=np.float32)

    alb = np.broadcast_to(black_col[None, None, :], (sz, sz, 3)).copy()

    dx_c = np.abs(xx - 0.35)
    cup_arc = np.sqrt(np.clip(1.0 - ((np.abs(dx_c - 0.048)) / 0.056) ** 2, 0.0, 1.0))
    heart_arch = 0.28 - 0.10 * cup_arc
    panel_half_w = 0.104 * (1.0 - 0.14 * np.clip(yy - 0.24, 0.0, 1.0))
    in_sweetheart = (xx < 0.70) & (dx_c < panel_half_w) & (yy >= heart_arch) & (yy < 0.86)
    alb[in_sweetheart] = white_col

    jag = 0.81 + 0.036 * np.sin(xx * math.pi * 24.0)
    in_hem = (xx < 0.70) & (yy >= jag)
    alb[in_hem] = white_col

    in_silver = xx >= 0.90
    alb[in_silver] = silver_col
    _save_image(alb_p, alb)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = np.where(in_silver, 0.18, 0.78)
    orm[:, :, 2] = np.where(in_silver, 0.94, 0.0)
    _save_image(orm_p, orm)
    return alb_p, orm_p


def _sample_neck_ring(
    verts_list: List[Vector],
    z_c: float,
    pad: float,
    fallback_cy: float,
) -> Tuple[float, float, float]:
    band = [v for v in verts_list if (z_c - 0.012) <= v.z <= (z_c + 0.012) and abs(v.x) < 0.085]
    if not band:
        return 0.048 + pad, fallback_cy, 0.048 + pad
    rx = max(abs(v.x) for v in band) + pad
    yf = min(v.y for v in band) - pad
    yb = max(v.y for v in band) + pad
    return rx, 0.5 * (yf + yb), 0.5 * (yb - yf)


def build_croptop(
    bm_obj: bpy.types.Object,
    lm: Optional[Dict[str, object]] = None,
    tex_dir: Path | str = DEFAULT_TEX_DIR,
    head_obj: Optional[bpy.types.Object] = None,
) -> Tuple[bpy.types.Object, Path]:
    """Build seamless halter turtleneck + silver chain + B&W sweetheart crop top with jagged hem."""
    t_dir = Path(tex_dir)
    alb_p, orm_p = _paint_croptop_textures(t_dir)
    top_mat = _make_pbr_material(
        "M_ghost_girl_croptop",
        albedo_path=alb_p,
        orm_path=orm_p,
        roughness=0.76,
        alpha_mode="OPAQUE",
        double_sided=True,
    )

    body_vs = _body_or_all_indices(bm_obj)
    verts = [bm_obj.data.vertices[i].co for i in body_vs]
    z_min_raw = min(v.z for v in verts)
    z_max_raw = max(v.z for v in verts)
    z_min = 0.0 if z_min_raw > 0.05 else z_min_raw

    lm_dict = lm or {}
    z_crown_ref = (
        float(lm_dict["crown_z"])
        if isinstance(lm_dict.get("crown_z"), (int, float))
        else (z_max_raw if z_max_raw > 1.45 else 1.58)
    )
    h = z_crown_ref - z_min
    chin_v = _to_vec(lm_dict.get("chin"), Vector((0.0, -0.105, z_min + 0.845 * h)))

    # Collect neck reference vertices from head_obj (or GhostGirl_Head) if available so collar
    # embraces the anime neck snugly with zero gap/clipping, blended cleanly to bm_obj base
    neck_ref_obj = head_obj or bpy.data.objects.get("GhostGirl_Head")
    head_neck_pts: List[Vector] = []
    if neck_ref_obj is not None:
        h_vs = _body_or_all_indices(neck_ref_obj)
        head_neck_pts = [neck_ref_obj.data.vertices[i].co.copy() for i in h_vs]

    z_bot = z_min + 0.665 * h
    z_bust_top = z_min + 0.785 * h
    z_neck_cut = float(lm_dict["z_neck_cut"]) if isinstance(lm_dict.get("z_neck_cut"), (int, float)) else (z_min + 0.810 * h)
    z_neck_bot = min(z_min + 0.808 * h, z_neck_cut - 0.004)
    z_neck_top = min(z_min + 0.846 * h, chin_v.z - 0.016)
    if z_neck_top <= z_neck_bot + 0.018:
        z_neck_top = z_neck_bot + 0.030

    torso_c_y_ref = sum(v.y for v in verts if z_bot <= v.z <= z_neck_bot and abs(v.x) < 0.12) / float(
        max(sum(1 for v in verts if z_bot <= v.z <= z_neck_bot and abs(v.x) < 0.12), 1)
    )

    def _best_neck_sample(z_c: float, pad: float) -> Tuple[float, float, float]:
        if head_neck_pts:
            h_band = [v for v in head_neck_pts if (z_c - 0.012) <= v.z <= (z_c + 0.012) and abs(v.x) < 0.085]
            if len(h_band) >= 6:
                return _sample_neck_ring(head_neck_pts, z_c, pad, torso_c_y_ref)
        return _sample_neck_ring(verts, z_c, pad, torso_c_y_ref)

    r_bot = _best_neck_sample(z_neck_bot, 0.0032)
    r_mid = _best_neck_sample(0.5 * (z_neck_bot + z_neck_top), 0.0028)
    r_top = _best_neck_sample(z_neck_top, 0.0024)
    r_in = _best_neck_sample(z_neck_top - 0.005, -0.0018)  # tucked inside neck -> zero gap!

    # 1. Conformal sweetheart torso + anatomical halter yoke shell up to neck base (bare shoulders!)
    bm = bmesh.new()
    bm.from_mesh(bm_obj.data)
    del_hv = [v for v in bm.verts if v.index not in body_vs]
    if del_hv:
        bmesh.ops.delete(bm, geom=del_hv, context="VERTS")
    bm.normal_update()
    for v in bm.verts:
        n = v.normal.copy()
        n.z *= 0.22
        if n.length > 1e-4:
            n.normalize()
        is_front_bust = v.co.y < torso_c_y_ref - 0.015 and z_bot <= v.co.z <= z_bust_top + 0.025
        if is_front_bust:
            off = 0.0086
        elif v.co.z >= z_bust_top - 0.01:
            off = 0.0062
        else:
            off = 0.0054
        v.co += n * off

    def bisect_torso(z_plane: float) -> None:
        geom = (
            [v for v in bm.verts if abs(v.co.x) < 0.22 and z_bot - 0.04 <= v.co.z <= z_neck_bot + 0.04]
            + [e for e in bm.edges if all(abs(v.co.x) < 0.22 and z_bot - 0.04 <= v.co.z <= z_neck_bot + 0.04 for v in e.verts)]
            + [f for f in bm.faces if all(abs(v.co.x) < 0.22 and z_bot - 0.04 <= v.co.z <= z_neck_bot + 0.04 for v in f.verts)]
        )
        if geom:
            bmesh.ops.bisect_plane(
                bm, geom=geom, dist=1e-4, plane_co=Vector((0.0, 0.0, z_plane)), plane_no=Vector((0.0, 0.0, 1.0))
            )

    bisect_torso(z_bot + 0.020)
    bisect_torso(z_bust_top)
    for sx in (-1.0, 1.0):
        # Clean vertical side bust cut at x = +/- 0.124 (bare shoulders above z_bust_top!)
        geom_x = (
            [v for v in bm.verts if z_bot <= v.co.z <= z_bust_top + 0.02 and abs(v.co.x) < 0.22]
            + [e for e in bm.edges if all(z_bot <= v.co.z <= z_bust_top + 0.02 and abs(v.co.x) < 0.22 for v in e.verts)]
            + [f for f in bm.faces if all(z_bot <= v.co.z <= z_bust_top + 0.02 and abs(v.co.x) < 0.22 for v in f.verts)]
        )
        if geom_x:
            bmesh.ops.bisect_plane(
                bm, geom=geom_x, dist=1e-4, plane_co=Vector((sx * 0.124, 0.0, 1.15)), plane_no=Vector((sx, 0.0, 0.0))
            )

    del_f = [
        f
        for f in bm.faces
        if (c := f.calc_center_median()).z < z_bot + 0.020
        or c.z > z_bust_top
        or abs(c.x) > 0.124
    ]
    bmesh.ops.delete(bm, geom=del_f, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")

    # Enforce safe bust/chest clearance on torso wrap before lofting smooth halter panels
    body_bvh = _build_bvh(bm_obj, body_vs)
    for v in bm.verts:
        is_front_chest = v.co.y < torso_c_y_ref - 0.015
        min_clear = 0.0076 if is_front_chest else 0.0056
        v.co = _push_outside_bvh(v.co, Vector((0.0, torso_c_y_ref, v.co.z)), body_bvh, min_clear, max_cap=None)

    uv_layer = bm.loops.layers.uv.verify()
    torso_c_y = sum(v.co.y for v in bm.verts) / float(max(len(bm.verts), 1))
    for f in bm.faces:
        f.smooth = True
        for loop in f.loops:
            p = loop.vert.co
            ang = math.atan2(p.x, -(p.y - torso_c_y))
            u = 0.35 + (ang / math.pi) * 0.33
            v_uv = (p.z - z_bot) / max(z_bust_top - z_bot, 1e-4)
            loop[uv_layer].uv = (_clamp(u, 0.01, 0.68), _clamp(v_uv, 0.10, 0.96))

    # 1b. Lofted smooth regular quad front & back halter yoke (zero bisect_plane shoulder spikes!)
    n_yoke_v = 6
    n_yoke_u = 13
    for y_sign, y_ray_off in ((-1.0, -0.14), (1.0, 0.14)):
        y_grid: List[List[bmesh.types.BMVert]] = []
        for vi in range(n_yoke_v):
            tv = vi / float(n_yoke_v - 1)
            zc = (z_bust_top - 0.004) * (1.0 - tv) + (z_neck_bot + 0.002) * tv
            half_w = 0.118 * (1.0 - tv) + (r_bot[0] * 0.96) * tv
            pad_y = (0.0086 if y_sign < 0.0 else 0.0066) * (1.0 - tv) + 0.0048 * tv
            row: List[bmesh.types.BMVert] = []
            for ui in range(n_yoke_u):
                su = (ui / float(n_yoke_u - 1)) * 2.0 - 1.0
                px = su * half_w
                # Raycast cleanly onto body chest/back along +/-Y so straps hug torso smoothly
                r_orig = Vector((px, torso_c_y_ref + y_ray_off, zc))
                r_dir = Vector((0.0, -y_sign, 0.0))
                loc, nrm, _, _ = body_bvh.ray_cast(r_orig, r_dir)
                if loc is None:
                    loc, nrm, _, _ = body_bvh.find_nearest(Vector((px, torso_c_y_ref + y_sign * 0.06, zc)))
                if loc is not None:
                    out_n = nrm.normalized() if nrm.length > 1e-4 else Vector((0.0, y_sign, 0.0))
                    if out_n.y * y_sign < 0.0:
                        out_n = -out_n
                    pt = loc + out_n * pad_y
                    pt.x = px
                    pt.z = zc
                    pt = _push_outside_bvh(pt, Vector((0.0, torso_c_y_ref, zc)), body_bvh, pad_y, max_cap=None)
                else:
                    pt = Vector((px, torso_c_y_ref + y_sign * 0.055, zc))
                row.append(bm.verts.new(pt))
            y_grid.append(row)
        for vi in range(n_yoke_v - 1):
            for ui in range(n_yoke_u - 1):
                v00, v10 = y_grid[vi][ui], y_grid[vi][ui + 1]
                v11, v01 = y_grid[vi + 1][ui + 1], y_grid[vi + 1][ui]
                quad = (v00, v10, v11, v01) if y_sign < 0.0 else (v10, v00, v01, v11)
                fq = bm.faces.new(quad)
                fq.smooth = True
                for loop in fq.loops:
                    loop[uv_layer].uv = (0.80, 0.50)

    # 2. Conformal 3D jagged white bottom hem stitched cleanly from lower torso bounds
    hem_vs = [v.co.copy() for v in bm.verts if v.co.z < z_bot + 0.036]
    rx_h = max((abs(v.x) for v in hem_vs), default=0.102) + 0.0025
    y_h_f = min((v.y for v in hem_vs), default=-0.072) - 0.0020
    y_h_b = max((v.y for v in hem_vs), default=0.072) + 0.0020
    cy_h = 0.5 * (y_h_f + y_h_b)
    ry_h = 0.5 * (y_h_b - y_h_f)

    n_jag = 40
    jag_top: List[bmesh.types.BMVert] = []
    jag_bot: List[bmesh.types.BMVert] = []
    for ji in range(n_jag):
        ang = math.tau * (ji / float(n_jag))
        sa, ca = math.sin(ang), -math.cos(ang)
        px = sa * rx_h
        py = cy_h + ca * ry_h
        z_t = z_bot + 0.025
        tip_drop = 0.022 if (ji % 2 == 1) else 0.004
        z_b = z_bot + 0.015 - tip_drop
        jag_top.append(bm.verts.new(Vector((px, py, z_t))))
        jag_bot.append(bm.verts.new(Vector((px * 1.035, py * 1.035, z_b))))

    for ji in range(n_jag):
        jn = (ji + 1) % n_jag
        fj = bm.faces.new((jag_top[ji], jag_bot[ji], jag_bot[jn], jag_top[jn]))
        fj.smooth = False
        for loop in fj.loops:
            loop[uv_layer].uv = (0.35, 0.04)

    # 3. Snug Turtleneck Collar overlapping top of anatomical halter yoke & hugging anime neck
    n_cseg = 36
    collar_profiles = (
        (r_bot[0] + 0.0020, r_bot[1], r_bot[2] + 0.0020, z_neck_bot - 0.012),
        (r_bot[0] + 0.0005, r_bot[1], r_bot[2] + 0.0005, z_neck_bot),
        (r_mid[0], r_mid[1], r_mid[2], 0.5 * (z_neck_bot + z_neck_top)),
        (r_top[0], r_top[1], r_top[2], z_neck_top),
        (r_in[0], r_in[1], r_in[2], z_neck_top - 0.005),
    )

    neck_bvh = _build_bvh(neck_ref_obj, _body_or_all_indices(neck_ref_obj)) if (neck_ref_obj is not None and head_neck_pts) else None
    col_rings: List[List[bmesh.types.BMVert]] = []
    for ri, (rx_c, cy_c, ry_c, z_c) in enumerate(collar_profiles):
        ring_c: List[bmesh.types.BMVert] = []
        for si in range(n_cseg):
            ang = math.tau * (si / float(n_cseg))
            p = Vector((math.sin(ang) * rx_c, cy_c - math.cos(ang) * ry_c, z_c))
            if ri < len(collar_profiles) - 1:
                if z_c <= z_neck_bot + 0.002:
                    p = _push_outside_bvh(p, Vector((0.0, cy_c, z_c)), body_bvh, 0.0052 if z_c < z_neck_bot else 0.0046, max_cap=None)
                if neck_bvh is not None and z_c >= z_neck_bot:
                    p = _push_outside_bvh(p, Vector((0.0, cy_c, z_c)), neck_bvh, 0.0028, max_cap=None)
                elif z_c > z_neck_bot + 0.002:
                    p = _push_outside_bvh(p, Vector((0.0, cy_c, z_c)), body_bvh, 0.0028, max_cap=None)
            ring_c.append(bm.verts.new(p))
        col_rings.append(ring_c)

    # Smooth collar profile rings azimuthally to eliminate BVH step kinks at neck/shoulder seam
    for ri in range(len(col_rings) - 1):
        ring_c = col_rings[ri]
        for _ in range(3):
            smoothed = [
                ring_c[si].co.lerp(
                    (ring_c[(si - 1) % n_cseg].co + ring_c[(si + 1) % n_cseg].co) * 0.5,
                    0.50,
                )
                for si in range(n_cseg)
            ]
            for si in range(n_cseg):
                ring_c[si].co = smoothed[si]

    for ri in range(len(col_rings) - 1):
        for si in range(n_cseg):
            sn = (si + 1) % n_cseg
            fc = bm.faces.new((col_rings[ri][si], col_rings[ri][sn], col_rings[ri + 1][sn], col_rings[ri + 1][si]))
            fc.smooth = True
            for loop in fc.loops:
                loop[uv_layer].uv = (0.80, 0.50)

    # 4. Continuous curved silver chain clasp hugging front collar/yoke seam
    chain_pts: List[Vector] = []
    n_arc = 19
    for ci in range(n_arc):
        t = (ci / float(n_arc - 1)) * 2.0 - 1.0
        cx = t * min(0.056, r_bot[0] * 1.08)
        cz = (z_neck_bot + 0.002) - 0.015 * (1.0 - t * t)
        ang_c = math.asin(_clamp(cx / max(r_bot[0], 0.03), -0.95, 0.95))
        cy = (r_bot[1] - math.cos(ang_c) * r_bot[2]) - 0.0055 - 0.003 * (1.0 - t * t)
        loc_c, _, _, _ = body_bvh.ray_cast(Vector((cx, cy - 0.06, cz)), Vector((0.0, 1.0, 0.0)))
        if loc_c is not None and loc_c.y < r_bot[1]:
            cy = min(cy, loc_c.y - 0.0095)
        chain_pts.append(Vector((cx, cy, cz)))

    tube_rings: List[List[bmesh.types.BMVert]] = []
    n_sides = 8
    r_chain = 0.0023
    for ci, pt in enumerate(chain_pts):
        tang = (chain_pts[1] - chain_pts[0]) if ci == 0 else ((chain_pts[-1] - chain_pts[-2]) if ci == n_arc - 1 else (chain_pts[ci + 1] - chain_pts[ci - 1]))
        tang.normalize()
        n1 = tang.cross(Vector((0.0, 0.0, 1.0))).normalized()
        n2 = n1.cross(tang).normalized()
        r_cur = r_chain * (1.0 + 0.16 * math.cos(ci * math.pi))
        t_ring = [
            bm.verts.new(pt + (n1 * math.cos(math.tau * si / n_sides) + n2 * math.sin(math.tau * si / n_sides)) * r_cur)
            for si in range(n_sides)
        ]
        tube_rings.append(t_ring)
    for ci in range(n_arc - 1):
        for si in range(n_sides):
            sn = (si + 1) % n_sides
            ft = bm.faces.new((tube_rings[ci][si], tube_rings[ci + 1][si], tube_rings[ci + 1][sn], tube_rings[ci][sn]))
            ft.smooth = True
            for loop in ft.loops:
                loop[uv_layer].uv = (0.95, 0.50)

    ret_clasp = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.0040)
    for v in ret_clasp["verts"]:
        v.co = Vector((v.co.x, v.co.y * 0.55, v.co.z)) + chain_pts[n_arc // 2]
    for f in {f for v in ret_clasp["verts"] for f in v.link_faces}:
        f.smooth = True
        for loop in f.loops:
            loop[uv_layer].uv = (0.95, 0.50)

    chain_faces = [f for f in bm.faces if f.loops[0][uv_layer].uv[0] >= 0.90]
    if chain_faces:
        bmesh.ops.recalc_face_normals(bm, faces=chain_faces)
    crop_mesh = bpy.data.meshes.new("GhostGirl_CropTop")
    bm.to_mesh(crop_mesh)
    bm.free()
    crop_mesh.materials.append(top_mat)
    crop_obj = bpy.data.objects.new("GhostGirl_CropTop", crop_mesh)
    bpy.context.collection.objects.link(crop_obj)
    return crop_obj, alb_p


def _paint_skirt_textures(tex_dir: Path) -> Tuple[Path, Path]:
    """Paint 1024x1024 atlas for GhostGirl_Skirt (waistband, 12 B&W pleats, safety shorts)."""
    alb_p = tex_dir / "ghost_girl_skirt_albedo.png"
    orm_p = tex_dir / "ghost_girl_skirt_orm.png"
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)

    black_col = np.array([0.120, 0.110, 0.145], dtype=np.float32)
    white_col = np.array([0.950, 0.950, 0.975], dtype=np.float32)
    shorts_col = np.array([0.105, 0.095, 0.130], dtype=np.float32)

    alb = np.broadcast_to(black_col[None, None, :], (sz, sz, 3)).copy()
    pleat_idx = np.floor(((xx + 0.5 / 12.0) % 1.0) * 12.0).astype(np.int32)
    is_white = (yy >= 0.16) & (yy < 0.84) & ((pleat_idx % 2) == 1)
    alb[is_white] = white_col

    pleat_phase = (((xx + 0.5 / 12.0) % 1.0) * 12.0) % 1.0
    crease = np.exp(-0.5 * (np.minimum(pleat_phase, 1.0 - pleat_phase) / 0.045) ** 2)
    in_pleat = (yy >= 0.16) & (yy < 0.84)
    alb[in_pleat] *= (1.0 - 0.15 * crease[in_pleat, None])
    alb[yy >= 0.84] = shorts_col
    _save_image(alb_p, alb)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = 0.80
    orm[:, :, 2] = 0.0
    _save_image(orm_p, orm)
    return alb_p, orm_p


def build_skirt(
    bm_obj: bpy.types.Object,
    tex_dir: Path | str = DEFAULT_TEX_DIR,
) -> Tuple[bpy.types.Object, Path]:
    """Build 12-pleat B&W mini-skirt with jagged hem + inset dark safety shorts."""
    t_dir = Path(tex_dir)
    alb_p, orm_p = _paint_skirt_textures(t_dir)
    skirt_mat = _make_pbr_material(
        "M_ghost_girl_skirt",
        albedo_path=alb_p,
        orm_path=orm_p,
        roughness=0.80,
        alpha_mode="OPAQUE",
        double_sided=True,
    )

    body_vs = _body_or_all_indices(bm_obj)
    verts = [bm_obj.data.vertices[i].co for i in body_vs if abs(bm_obj.data.vertices[i].co.x) < 0.24]
    z_min_raw = min(v.z for v in verts)
    z_max_raw = max(v.z for v in verts)
    z_min = 0.0 if z_min_raw > 0.05 else z_min_raw
    z_max = z_max_raw if z_max_raw > 1.45 else 1.58
    h = z_max - z_min

    z_waist_top = z_min + 0.606 * h
    z_band_bot = z_min + 0.578 * h
    z_hem_base = z_min + 0.432 * h

    waist_vs = [v for v in verts if z_band_bot <= v.z <= z_waist_top]
    w_rx = max((abs(v.x) for v in waist_vs), default=0.110) + 0.006
    w_ry_f = abs(min((v.y for v in waist_vs), default=-0.080)) + 0.006
    w_ry_b = abs(max((v.y for v in waist_vs), default=0.080)) + 0.006

    hip_vs = [v for v in verts if z_hem_base <= v.z <= z_band_bot]
    max_hip_rx = max((abs(v.x) for v in hip_vs), default=0.145)
    max_hip_ry_f = abs(min((v.y for v in hip_vs), default=-0.092))
    max_hip_ry_b = abs(max((v.y for v in hip_vs), default=0.112))

    hem_rx = max(w_rx + 0.088, max_hip_rx + 0.036)
    hem_ry_f = max(w_ry_f + 0.060, max_hip_ry_f + 0.026)
    hem_ry_b = max(w_ry_b + 0.078, max_hip_ry_b + 0.032)

    n_pleats = 12
    v_per_pleat = 4
    n_segs = n_pleats * v_per_pleat
    z_levels = (
        z_waist_top,
        0.5 * (z_waist_top + z_band_bot),
        z_band_bot,
        z_band_bot - 0.045,
        z_band_bot - 0.095,
        z_band_bot - 0.145,
        z_hem_base,
    )

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()
    rings: List[List[bmesh.types.BMVert]] = []
    prev_rx, prev_ry_f, prev_ry_b = w_rx, w_ry_f, w_ry_b

    for ri, z in enumerate(z_levels):
        band_vs = [v for v in verts if (z - 0.025) <= v.z <= (z + 0.025)]
        b_rx = max((abs(v.x) for v in band_vs), default=w_rx)
        b_ry_f = abs(min((v.y for v in band_vs), default=-w_ry_f))
        b_ry_b = abs(max((v.y for v in band_vs), default=w_ry_b))

        if z >= z_band_bot:
            rx = max(w_rx, b_rx + 0.006)
            ry_f = max(w_ry_f, b_ry_f + 0.006)
            ry_b = max(w_ry_b, b_ry_b + 0.006)
            pleat_d = 0.0
        else:
            t = (z_band_bot - z) / max(z_band_bot - z_hem_base, 1e-4)
            ct = t ** 0.85
            rx = max(w_rx * (1.0 - ct) + hem_rx * ct, b_rx + 0.016, prev_rx + 0.010)
            ry_f = max(w_ry_f * (1.0 - ct) + hem_ry_f * ct, b_ry_f + 0.016, prev_ry_f + 0.008)
            ry_b = max(w_ry_b * (1.0 - ct) + hem_ry_b * ct, b_ry_b + 0.016, prev_ry_b + 0.010)
            pleat_d = 0.013 * _smoothstep(0.0, 0.45, t)

        prev_rx, prev_ry_f, prev_ry_b = rx, ry_f, ry_b
        pleat_offs = (0.0, 0.55 * pleat_d, 1.05 * pleat_d, 0.55 * pleat_d)
        ring: List[bmesh.types.BMVert] = []
        for si in range(n_segs):
            ang = math.tau * (si / float(n_segs)) - math.pi / float(n_pleats)
            sa, ca = math.sin(ang), -math.cos(ang)
            po = pleat_offs[si % v_per_pleat]
            vz = z
            if ri == len(z_levels) - 1:
                vz -= 0.020 * ((si % 2) + 0.35 * math.sin(ang * 5.0))
            ring.append(bm.verts.new(Vector((sa * (rx + po), ca * ((ry_f if ca < 0 else ry_b) + po), vz))))
        rings.append(ring)

    v_levels = (0.98, 0.91, 0.84, 0.68, 0.52, 0.36, 0.19)
    for ri in range(len(rings) - 1):
        v0, v1 = v_levels[ri], v_levels[ri + 1]
        for si in range(n_segs):
            sn = (si + 1) % n_segs
            u0 = (si / float(n_segs)) - 0.5 / float(n_pleats)
            u1 = ((si + 1) / float(n_segs)) - 0.5 / float(n_pleats)
            f = bm.faces.new((rings[ri][si], rings[ri + 1][si], rings[ri + 1][sn], rings[ri][sn]))
            f.smooth = True
            f.loops[0][uv_layer].uv = (u0, v0)
            f.loops[1][uv_layer].uv = (u0, v1)
            f.loops[2][uv_layer].uv = (u1, v1)
            f.loops[3][uv_layer].uv = (u1, v0)

    # Dark safety shorts underneath
    bm_sh = bmesh.new()
    bm_sh.from_mesh(bm_obj.data)
    del_hv = [v for v in bm_sh.verts if v.index not in body_vs]
    if del_hv:
        bmesh.ops.delete(bm_sh, geom=del_hv, context="VERTS")
    del_sf = [
        f for f in bm_sh.faces
        if f.calc_center_median().z < z_min + 0.448 * h
        or f.calc_center_median().z > z_band_bot - 0.008
        or abs(f.calc_center_median().x) > 0.19
    ]
    bmesh.ops.delete(bm_sh, geom=del_sf, context="FACES")
    loose_s = [v for v in bm_sh.verts if not v.link_faces]
    if loose_s:
        bmesh.ops.delete(bm_sh, geom=loose_s, context="VERTS")
    bm_sh.normal_update()
    for v in bm_sh.verts:
        n = v.normal.copy()
        n.z *= 0.20
        if n.length > 1e-4:
            n.normalize()
        v.co += n * 0.0020
    uv_sh = bm_sh.loops.layers.uv.verify()
    for f in bm_sh.faces:
        f.smooth = True
        for loop in f.loops:
            loop[uv_sh].uv = (0.5, 0.08)
    tmp_m = bpy.data.meshes.new("_tmp_shorts")
    bm_sh.to_mesh(tmp_m)
    bm_sh.free()
    while len(tmp_m.uv_layers) > 1:
        tmp_m.uv_layers.remove(tmp_m.uv_layers[1])
    if tmp_m.uv_layers:
        tmp_m.uv_layers[0].name = uv_layer.name
    bm.from_mesh(tmp_m)
    bpy.data.meshes.remove(tmp_m)

    skirt_mesh = bpy.data.meshes.new("GhostGirl_Skirt")
    bm.to_mesh(skirt_mesh)
    bm.free()
    skirt_mesh.materials.append(skirt_mat)
    skirt_obj = bpy.data.objects.new("GhostGirl_Skirt", skirt_mesh)
    bpy.context.collection.objects.link(skirt_obj)
    return skirt_obj, alb_p


def paint_cape_texture(tex_dir: Path | str = DEFAULT_TEX_DIR) -> Tuple[Path, Path]:
    """Paint 1024x1024 semi-translucent tattered white ghost cape texture with oval/teardrop holes."""
    t_dir = Path(tex_dir)
    alb_p = t_dir / "ghost_girl_cape_albedo.png"
    orm_p = t_dir / "ghost_girl_cape_orm.png"
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)

    fold = 0.5 + 0.5 * np.sin(xx * math.pi * 18.0)
    shade = 0.14 * yy + 0.06 * fold * (0.3 + 0.7 * yy)
    r = 0.974 - shade * 1.12
    g = 0.977 - shade * 1.02
    b = 0.996 - shade * 0.36

    # Sheer chiffon translucency across upper shoulders/torso (~0.48), softly denser toward ragged tips
    alpha = 0.48 + 0.14 * yy + 0.04 * fold

    holes = (
        (0.13, 0.68, 0.018, 0.036, 0.18),
        (0.21, 0.77, 0.015, 0.030, -0.10),
        (0.32, 0.71, 0.017, 0.034, 0.12),
        (0.45, 0.75, 0.020, 0.038, -0.05),
        (0.55, 0.72, 0.018, 0.035, 0.08),
        (0.67, 0.76, 0.017, 0.034, -0.15),
        (0.79, 0.70, 0.016, 0.032, 0.14),
        (0.87, 0.77, 0.019, 0.036, -0.12),
    )
    for hx, hy, rx, ry, ang in holes:
        dx = xx - hx
        dy = yy - hy
        ca, sa = math.cos(ang), math.sin(ang)
        ux = dx * ca - dy * sa
        vy = dx * sa + dy * ca
        taper = 1.0 - 0.28 * np.clip(-vy / ry, -0.5, 1.0)
        d = np.sqrt((ux / (rx * taper)) ** 2 + (vy / ry) ** 2)
        hole_m = np.clip((d - 0.88) / 0.04, 0.0, 1.0)
        rim = np.clip(1.0 - np.abs(d - 0.98) / 0.08, 0.0, 1.0)
        r -= 0.10 * rim
        g -= 0.09 * rim
        b -= 0.03 * rim
        alpha *= hole_m

    ragged_y = 0.89 + 0.08 * np.sin(xx * math.pi * 15.0) + 0.04 * np.cos(xx * math.pi * 27.0)
    hem_m = np.clip((ragged_y - yy) / 0.02, 0.0, 1.0)
    alpha *= hem_m

    rgba = np.stack([np.clip(r, 0.0, 1.0), np.clip(g, 0.0, 1.0), np.clip(b, 0.0, 1.0), np.clip(alpha, 0.0, 1.0)], axis=2)
    _save_image(alb_p, rgba)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.95
    orm[:, :, 1] = 0.82
    orm[:, :, 2] = 0.0
    _save_image(orm_p, orm)
    return alb_p, orm_p


def build_ghost_cape(
    body_obj: bpy.types.Object,
    alb_p: Path | str,
    orm_p: Path | str,
    is_tpose: bool = True,
    hood_obj: Optional[bpy.types.Object] = None,
    lm: Optional[Dict[str, object]] = None,
) -> bpy.types.Object:
    """Build semi-translucent tattered white ghost cape clearing hood/shoulders down to mid-calf."""
    alb_path = Path(alb_p)
    orm_path = Path(orm_p)
    cape_mat = _make_pbr_material(
        "M_ghost_girl_cape",
        albedo_path=alb_path,
        orm_path=orm_path,
        roughness=0.82,
        alpha_mode="BLEND",
        double_sided=True,
    )

    body_vs = _body_or_all_indices(body_obj)
    verts = [body_obj.data.vertices[i].co for i in body_vs]
    z_min_raw = min(v.z for v in verts)
    z_max_raw = max(v.z for v in verts)
    z_min = 0.0 if z_min_raw > 0.05 else z_min_raw
    z_max = z_max_raw if z_max_raw > 1.45 else 1.58
    h = z_max - z_min

    max_arm_x = max((abs(v.x) for v in verts if v.z > z_min + 0.45 * h), default=0.72)
    # Keep cape shawl spanning only neck + upper shoulders/deltoids (clear forearms; no hip wing triangles)
    x_wrist_span = min(0.265 if is_tpose else 0.225, max(0.20, max_arm_x - 0.14))

    def sample_arm_cross(x_pos: float) -> Tuple[float, float, float, float]:
        z_floor = (z_min + 0.695 * h) if abs(x_pos) <= 0.18 else (z_min + 0.50 * h)
        band = [v for v in verts if abs(v.x - x_pos) < 0.032 and z_floor < v.z < (z_min + 0.840 * h)]
        if not band:
            band = [v for v in verts if abs(v.x - x_pos) < 0.055 and z_floor < v.z < (z_min + 0.840 * h)]
        if not band:
            return 0.005, z_min + 0.755 * h, 0.055, 0.045
        yf = min(v.y for v in band)
        yb = max(v.y for v in band)
        zt = max(v.z for v in band)
        zb = min(v.z for v in band)
        return 0.5 * (yf + yb), 0.5 * (zt + zb), max(0.032, 0.5 * (yb - yf)), max(0.030, 0.5 * (zt - zb))

    n_u = 52
    n_v = 20

    neck_band = [v for v in verts if (z_min + 0.78 * h) <= v.z <= (z_min + 0.825 * h) and abs(v.x) < 0.08]
    y_neck_b = max((v.y for v in neck_band), default=0.068) + 0.042
    z_neck_c = z_min + 0.804 * h
    y_back_skirt = max((v.y for v in verts if (z_min + 0.42 * h) <= v.z <= (z_min + 0.62 * h) and abs(v.x) < 0.16), default=0.11)

    sh_r = sample_arm_cross(-0.118)
    sh_l = sample_arm_cross(0.118)
    sh_cy = 0.5 * (sh_r[0] + sh_l[0])
    sh_cz = 0.5 * (sh_r[1] + sh_l[1])
    sh_ry = max(sh_r[2], sh_l[2]) + 0.030
    sh_rz = max(sh_r[3], sh_l[3]) + 0.026

    col_specs: List[Tuple[float, float, float, float, float, float, float]] = []
    for ui in range(n_u):
        u = ui / float(n_u - 1)
        if u < 0.30:
            t_arm = u / 0.30
            x = -x_wrist_span * (1.0 - t_arm) - 0.118 * t_arm
            cy, cz, ry_a, rz_a = sample_arm_cross(x)
            sh_boost = _smoothstep(0.45, 0.90, t_arm)
            ry = ry_a + 0.022 + 0.008 * sh_boost
            rz = rz_a + 0.020 + 0.006 * sh_boost
            w_cov = _smoothstep(0.10, 0.45, t_arm)
            w_in = _smoothstep(0.82, 1.0, t_arm)
            phi_f = ((0.30 * (1.0 - w_cov) + 0.05 * w_cov) * (1.0 - w_in) + 0.12 * w_in) * math.pi
            col_specs.append((x, cy, cz, ry, rz, phi_f, 0.0))
        elif u <= 0.70:
            t_col = (u - 0.30) / 0.40
            px = -0.118 * math.cos(t_col * math.pi)
            s_m = math.sin(t_col * math.pi) ** 1.15
            cy_s, cz_s, ry_s, rz_s = sample_arm_cross(px if abs(px) >= 0.09 else (-0.118 if px < 0 else 0.118))
            ry_s = max(ry_s + 0.030, sh_ry) * (1.0 - 0.5 * s_m) + sh_ry * (0.5 * s_m)
            rz_s = max(rz_s + 0.026, sh_rz) * (1.0 - 0.5 * s_m) + sh_rz * (0.5 * s_m)
            col_specs.append((px, cy_s * (1.0 - s_m) + sh_cy * s_m, cz_s * (1.0 - s_m) + sh_cz * s_m, ry_s, rz_s, 0.12 * math.pi, s_m))
        else:
            t = (u - 0.70) / 0.30
            t_arm = 1.0 - t
            x = 0.118 * (1.0 - t) + x_wrist_span * t
            cy, cz, ry_a, rz_a = sample_arm_cross(x)
            sh_boost = _smoothstep(0.45, 0.90, t_arm)
            ry = ry_a + 0.022 + 0.008 * sh_boost
            rz = rz_a + 0.020 + 0.006 * sh_boost
            w_cov = _smoothstep(0.10, 0.45, t_arm)
            w_in = _smoothstep(0.82, 1.0, t_arm)
            phi_f = ((0.30 * (1.0 - w_cov) + 0.05 * w_cov) * (1.0 - w_in) + 0.12 * w_in) * math.pi
            col_specs.append((x, cy, cz, ry, rz, phi_f, 0.0))

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()
    grid: List[List[bmesh.types.BMVert]] = []

    def _eval_cowl_yz(spec: Tuple[float, float, float, float, float, float, float], s_v: float) -> Tuple[float, float]:
        _, cy_c, cz_c, ry_c, rz_c, phi_f, neck_b = spec
        phi = phi_f * (1.0 - s_v) + math.pi * s_v
        y_ell = cy_c - ry_c * math.cos(phi)
        z_ell = cz_c + rz_c * math.sin(phi)
        if neck_b <= 1e-6:
            return y_ell, z_ell
        om = 1.0 - s_v
        y_n = om * om * (y_neck_b - 0.004) + 2.0 * om * s_v * (y_neck_b + 0.014) + s_v * s_v * (y_neck_b + 0.034)
        z_n = om * om * (z_neck_c + 0.010) + 2.0 * om * s_v * (z_neck_c + 0.018) + s_v * s_v * (z_neck_c - 0.014)
        arch_z = 0.014 * math.sin(neck_b * math.pi) * (1.0 - 0.5 * s_v)
        return y_ell * (1.0 - neck_b) + y_n * neck_b, z_ell * (1.0 - neck_b) + z_n * neck_b + arch_z

    for vi in range(n_v):
        v_t = vi / float(n_v - 1)
        row: List[bmesh.types.BMVert] = []
        for ui in range(n_u):
            u = ui / float(n_u - 1)
            spec = col_specs[ui]
            pc_x = spec[0]
            center_dist = abs(u - 0.5) * 2.0
            rag = 0.044 * math.sin(u * math.pi * 15.0 + 0.4) + 0.022 * math.cos(u * math.pi * 23.0)
            # Clean vertical back drape reaching upper-mid calf (Z ~ 0.35..0.46m), tapering softly at outer shoulders
            z_hem = (z_min + 0.22 * h) + (0.42 * h) * (center_dist ** 2.4) + rag

            # Tuck lateral cape hem slightly inward downward so it drapes cleanly vertically with ZERO wing flares
            tuck_in = _smoothstep(0.32, 0.88, v_t) * _smoothstep(0.28, 0.95, center_dist)
            px = pc_x * (1.0 - 0.24 * tuck_in)

            pb_y, pb_z = _eval_cowl_yz(spec, 1.0)
            back_dome_y = max(pb_y + 0.032, y_back_skirt + 0.072) + 0.018 * math.cos(center_dist * math.pi * 0.5)
            if v_t <= 0.28:
                py, pz = _eval_cowl_yz(spec, v_t / 0.28)
            else:
                k = (v_t - 0.28) / 0.72
                ks = _smoothstep(0.0, 0.72, k)
                py = pb_y * (1.0 - ks) + back_dome_y * ks
                pz = pb_z * (1.0 - (k ** 1.08)) + z_hem * (k ** 1.08)

            row.append(bm.verts.new(Vector((px, py, pz))))
        grid.append(row)

    body_bvh = _build_bvh(body_obj, body_vs)
    hood_ref = hood_obj or bpy.data.objects.get("GhostGirl_Hood")
    hood_bvh = _build_bvh(hood_ref) if hood_ref is not None else None

    for vi in range(n_v):
        v_t = vi / float(n_v - 1)
        if v_t > 0.36:
            break
        for v in grid[vi]:
            loc, nrm, _, dist = body_bvh.find_nearest(v.co)
            if loc is not None and dist < 0.018:
                push = nrm if nrm.length > 1e-4 else Vector((0.0, 0.2, 1.0)).normalized()
                if (v.co - loc).dot(push) < 0.0:
                    push = Vector((0.0, 0.2, 1.0)).normalized()
                v.co = loc + push * 0.018
            if hood_bvh is not None and abs(v.co.x) < 0.15:
                h_loc, h_nrm, _, h_dist = hood_bvh.find_nearest(v.co)
                if h_loc is not None and h_dist < 0.009:
                    # Keep cape smoothly behind/below hood hem rather than clipping into hood back
                    v.co.y = max(v.co.y, h_loc.y + 0.010)

    for vi in range(n_v - 1):
        v0_uv = 1.0 - vi / float(n_v - 1)
        v1_uv = 1.0 - (vi + 1) / float(n_v - 1)
        for ui in range(n_u - 1):
            u0_uv = ui / float(n_u - 1)
            u1_uv = (ui + 1) / float(n_u - 1)
            f = bm.faces.new((grid[vi][ui], grid[vi + 1][ui], grid[vi + 1][ui + 1], grid[vi][ui + 1]))
            f.smooth = True
            f.loops[0][uv_layer].uv = (u0_uv, v0_uv)
            f.loops[1][uv_layer].uv = (u0_uv, v1_uv)
            f.loops[2][uv_layer].uv = (u1_uv, v1_uv)
            f.loops[3][uv_layer].uv = (u1_uv, v0_uv)

    cape_mesh = bpy.data.meshes.new("GhostGirl_Cape")
    bm.to_mesh(cape_mesh)
    bm.free()
    cape_mesh.materials.append(cape_mat)
    cape_obj = bpy.data.objects.new("GhostGirl_Cape", cape_mesh)
    bpy.context.collection.objects.link(cape_obj)
    return cape_obj


def paint_gloves_textures(tex_dir: Path | str = DEFAULT_TEX_DIR) -> Tuple[Path, Path]:
    """Paint 512x512 albedo and ORM textures for GhostGirl_Gloves."""
    t_dir = Path(tex_dir)
    alb_p = t_dir / "ghost_girl_gloves_albedo.png"
    orm_p = t_dir / "ghost_girl_gloves_orm.png"
    sz = 512
    alb = np.full((sz, sz, 3), (0.125, 0.115, 0.148), dtype=np.float32)
    alb[:96, :, :] = np.array([0.095, 0.085, 0.118], dtype=np.float32)
    _save_image(alb_p, alb)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = 0.52
    orm[:, :, 2] = 0.02
    _save_image(orm_p, orm)
    return alb_p, orm_p


def build_gloves(
    body_obj: bpy.types.Object,
    alb_p: Path | str,
    orm_p: Path | str,
) -> bpy.types.Object:
    """Build dark charcoal fingerless wrist-length gloves in A-pose or T-pose."""
    glove_mat = _make_pbr_material(
        "M_ghost_girl_gloves",
        albedo_path=Path(alb_p),
        orm_path=Path(orm_p),
        roughness=0.50,
        alpha_mode="OPAQUE",
        double_sided=False,
    )

    body_vs = _body_or_all_indices(body_obj)
    bm = bmesh.new()
    bm.from_mesh(body_obj.data)
    del_hv = [v for v in bm.verts if v.index not in body_vs]
    if del_hv:
        bmesh.ops.delete(bm, geom=del_hv, context="VERTS")
    bm.normal_update()

    hand_planes: List[Tuple[float, Vector, Vector, Vector, Vector]] = []
    for sx in (1.0, -1.0):
        side_arm = [v.co for v in bm.verts if (v.co.x * sx) > 0.25]
        if not side_arm:
            continue
        tip_p = max(side_arm, key=lambda c: c.x * sx)
        near_arm = [c for c in side_arm if (tip_p - c).length < 0.22]
        inner_p = min(near_arm, key=lambda c: c.x * sx)
        arm_dir = (tip_p - inner_p).normalized()
        p_wrist = tip_p - arm_dir * 0.155
        p_knuckle = tip_p - arm_dir * 0.068
        p_cuff = p_wrist + arm_dir * 0.018
        hand_planes.append((sx, arm_dir, p_wrist, p_cuff, p_knuckle))

    for v in bm.verts:
        v.co += v.normal * 0.0022

    for sx, arm_dir, p_wrist, p_cuff, p_knuckle in hand_planes:
        for plane_p in (p_wrist, p_cuff, p_knuckle):
            geom = (
                [v for v in bm.verts if (v.co.x * sx) > 0.22 and (v.co - p_wrist).length < 0.18]
                + [e for e in bm.edges if all((v.co.x * sx) > 0.22 and (v.co - p_wrist).length < 0.18 for v in e.verts)]
                + [f for f in bm.faces if all((v.co.x * sx) > 0.22 and (v.co - p_wrist).length < 0.18 for v in f.verts)]
            )
            if geom:
                bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-4, plane_co=plane_p, plane_no=arm_dir)

    del_faces = []
    for f in bm.faces:
        c = f.calc_center_median()
        kept = False
        for sx, arm_dir, p_wrist, _, p_knuckle in hand_planes:
            if (c.x * sx) <= 0.20:
                continue
            d_w = (c - p_wrist).dot(arm_dir)
            d_k = (c - p_knuckle).dot(arm_dir)
            if d_w >= -0.001 and d_k <= 0.001:
                if c.y < p_wrist.y - 0.055 and d_w > 0.048:
                    continue
                kept = True
                break
        if not kept:
            del_faces.append(f)

    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")

    uv_layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        f.smooth = True
        c = f.calc_center_median()
        is_cuff = False
        for sx, arm_dir, _, p_cuff, _ in hand_planes:
            if (c.x * sx) > 0.20 and (c - p_cuff).dot(arm_dir) < 0.002:
                is_cuff = True
                break
        for loop in f.loops:
            loop[uv_layer].uv = (0.5, 0.90 if is_cuff else 0.45)

    gloves_mesh = bpy.data.meshes.new("GhostGirl_Gloves")
    bm.to_mesh(gloves_mesh)
    bm.free()
    gloves_mesh.materials.append(glove_mat)
    gloves_obj = bpy.data.objects.new("GhostGirl_Gloves", gloves_mesh)
    bpy.context.collection.objects.link(gloves_obj)
    return gloves_obj


def _paint_boots_textures(tex_dir: Path) -> Tuple[Path, Path]:
    alb_p = tex_dir / "ghost_girl_boots_albedo.png"
    orm_p = tex_dir / "ghost_girl_boots_orm.png"
    sz = 512
    yy, _ = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)
    alb = np.full((sz, sz, 3), (0.180, 0.165, 0.212), dtype=np.float32)
    alb[yy < 0.25] = np.array([0.148, 0.132, 0.178], dtype=np.float32)
    alb[yy >= 0.75] = np.array([0.095, 0.084, 0.118], dtype=np.float32)
    _save_image(alb_p, alb)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = np.where(yy >= 0.75, 0.68, 0.46)
    orm[:, :, 2] = 0.04
    _save_image(orm_p, orm)
    return alb_p, orm_p


def build_boots(
    bm_obj: bpy.types.Object,
    tex_dir: Path | str = DEFAULT_TEX_DIR,
) -> Tuple[bpy.types.Object, Path]:
    """Build dark charcoal cuffed ankle boots with flat thick soles seated at Z=0."""
    t_dir = Path(tex_dir)
    alb_p, orm_p = _paint_boots_textures(t_dir)
    boot_mat = _make_pbr_material(
        "M_ghost_girl_boots",
        albedo_path=alb_p,
        orm_path=orm_p,
        roughness=0.48,
        alpha_mode="OPAQUE",
        double_sided=False,
    )

    body_vs = _body_or_all_indices(bm_obj)
    verts = [bm_obj.data.vertices[i].co for i in body_vs]

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()

    for sx in (1.0, -1.0):
        leg_vs = [v for v in verts if v.z <= 0.26 and (v.x * sx) > 0.01]
        ank_vs = [v for v in leg_vs if 0.06 <= v.z <= 0.13]
        foot_vs = [v for v in leg_vs if v.z <= 0.065]

        cx = sum(v.x for v in ank_vs) / float(len(ank_vs)) if ank_vs else (sx * 0.092)
        ank_y = sum(v.y for v in ank_vs) / float(len(ank_vs)) if ank_vs else -0.015
        y_toe = min((v.y for v in foot_vs), default=-0.160) - 0.012
        y_heel = max((v.y for v in foot_vs), default=0.052) + 0.010

        # Ensure boot shaft clears actual shin/ankle radius without widening into overlap
        shin_vs = [v for v in leg_vs if 0.13 < v.z <= 0.205 and abs(v.x - cx) < 0.060]
        shin_rx = max((abs(v.x - cx) for v in shin_vs), default=0.042)
        shaft_rx = min(0.052, max(0.045, shin_rx + 0.004))

        def loft(
            profiles: List[Tuple[float, float, float, float, float]],
            v_range: Tuple[float, float],
            cap_bot: bool = False,
            cap_top: bool = False,
        ) -> None:
            segs = 28
            sec_rings: List[List[bmesh.types.BMVert]] = []
            for yf, yb, rx_p, z_p, sq in profiles:
                yc = 0.5 * (yf + yb)
                ry = 0.5 * (yb - yf)
                ring: List[bmesh.types.BMVert] = []
                for j in range(segs):
                    ang = math.tau * (j / float(segs))
                    sa, ca = math.sin(ang), -math.cos(ang)
                    pe = 1.0 - 0.25 * sq
                    sxa = math.copysign(abs(sa) ** pe, sa)
                    sya = math.copysign(abs(ca) ** pe, ca)
                    taper = 1.0 - 0.12 * max(0.0, -ca)
                    ring.append(bm.verts.new(Vector((cx + sxa * rx_p * taper, yc + sya * ry, z_p))))
                sec_rings.append(ring)
            nr = len(sec_rings)
            for ri in range(nr - 1):
                v0 = v_range[0] + (v_range[1] - v_range[0]) * (ri / float(nr - 1))
                v1 = v_range[0] + (v_range[1] - v_range[0]) * ((ri + 1) / float(nr - 1))
                for j in range(segs):
                    jn = (j + 1) % segs
                    f = bm.faces.new((sec_rings[ri][j], sec_rings[ri][jn], sec_rings[ri + 1][jn], sec_rings[ri + 1][j]))
                    f.smooth = True
                    f.loops[0][uv_layer].uv = (j / float(segs), v0)
                    f.loops[1][uv_layer].uv = ((j + 1) / float(segs), v0)
                    f.loops[2][uv_layer].uv = ((j + 1) / float(segs), v1)
                    f.loops[3][uv_layer].uv = (j / float(segs), v1)
            if cap_bot:
                fc = bm.faces.new(sec_rings[0][::-1])
                for loop in fc.loops:
                    loop[uv_layer].uv = (0.5, v_range[0])
            if cap_top:
                fc = bm.faces.new(sec_rings[-1])
                for loop in fc.loops:
                    loop[uv_layer].uv = (0.5, v_range[1])

        loft([
            (y_toe - 0.004, y_heel + 0.004, 0.052, 0.000, 0.55),
            (y_toe - 0.005, y_heel + 0.005, 0.054, 0.022, 0.55),
            (y_toe - 0.002, y_heel + 0.003, 0.050, 0.030, 0.45),
        ], v_range=(0.05, 0.22), cap_bot=True, cap_top=True)

        loft([
            (y_toe + 0.002, y_heel - 0.001, 0.048, 0.028, 0.35),
            (y_toe + 0.006, y_heel - 0.002, 0.047, 0.055, 0.28),
            (y_toe + 0.042, y_heel - 0.004, 0.045, 0.078, 0.15),
            (ank_y - 0.052, y_heel - 0.005, 0.044, 0.105, 0.08),
            (ank_y - 0.050, ank_y + 0.050, shaft_rx, 0.152, 0.06),
            (ank_y - 0.051, ank_y + 0.051, shaft_rx + 0.002, 0.192, 0.06),
        ], v_range=(0.30, 0.72), cap_bot=False, cap_top=False)

        loft([
            (ank_y - 0.049, ank_y + 0.049, shaft_rx + 0.001, 0.155, 0.06),
            (ank_y - 0.057, ank_y + 0.057, shaft_rx + 0.008, 0.162, 0.06),
            (ank_y - 0.058, ank_y + 0.058, shaft_rx + 0.009, 0.198, 0.06),
            (ank_y - 0.050, ank_y + 0.050, shaft_rx + 0.001, 0.204, 0.06),
            (ank_y - 0.044, ank_y + 0.044, shaft_rx - 0.004, 0.190, 0.06),
        ], v_range=(0.80, 0.96), cap_bot=False, cap_top=False)

    boots_mesh = bpy.data.meshes.new("GhostGirl_Boots")
    bm.to_mesh(boots_mesh)
    bm.free()
    boots_mesh.materials.append(boot_mat)
    boots_obj = bpy.data.objects.new("GhostGirl_Boots", boots_mesh)
    bpy.context.collection.objects.link(boots_obj)
    return boots_obj, alb_p
