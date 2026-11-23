#!/usr/bin/env python3
"""MPFB2-Based Full Character & Humanizer Builder for Ghost Girl (1.58m T-Pose, 16 Meshes, 52 ARKit).

Builds Ghost Girl from an un-morphed MPFB2 base mesh (19,158 verts) sculpted into stylized
anime proportions (1.58m tall, ~1:6.2 head-to-body ratio, enlarged anime eye orbits, tapered
V-chin, slender limbs) and produces BOTH:
1. Humanizer export (`assets/models/ghost_girl/humanizer_export/`):
   - `ghost_girl_anime.target` (MakeHuman Y-up/+Z-forward deltas in meters, unit_scale=1.0 vs basis.data)
   - `export_meta.json` (basis/sculpted bounds, unit scale, asset slot/material manifest)
   - `ghost_girl_anime_skin.png` (2048x2048 seamless peach-fair anime skin for Body-Default)
   - 10 modular `.mhclo` + `.obj` + `_albedo.png` assets aligned to the canonical MPFB2 pose:
     `GhostGirl_Hair_Cards`, `GhostGirl_Hood`, `GhostGirl_Cape`, `GhostGirl_CropTop`,
     `GhostGirl_Skirt`, `GhostGirl_Gloves`, `GhostGirl_Boots`, `GhostGirl_Eye_L`,
     `GhostGirl_Eye_R`, `GhostGirl_Eyelashes`.
2. Standalone T-pose GLB (`assets/models/ghost_girl/ghost_girl.glb`):
   - Exactly 16 clean modular meshes (0 stray objects):
     `GhostGirl_Body`, `GhostGirl_Head`, `GhostGirl_Eye_L`, `GhostGirl_Eye_R`,
     `GhostGirl_Eyelashes`, `GhostGirl_Teeth_Upper`, `GhostGirl_Teeth_Lower`,
     `GhostGirl_Tongue`, `GhostGirl_Hair_Cap`, `GhostGirl_Hair_Cards`, `GhostGirl_Hood`,
     `GhostGirl_Cape`, `GhostGirl_CropTop`, `GhostGirl_Skirt`, `GhostGirl_Gloves`,
     `GhostGirl_Boots`.
   - 52 ARKit blendshapes on `GhostGirl_Head` + 6 eyelid keys on `GhostGirl_Eyelashes`.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set, Tuple

_TOOL_DIR = Path(__file__).resolve().parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

from bl_ext.blender_org.mpfb.entities.objectproperties import HumanObjectProperties
from bl_ext.blender_org.mpfb.services.assetservice import AssetService
from bl_ext.blender_org.mpfb.services.clothesservice import CLOTHES_REFERENCE_SCALE
from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.locationservice import LocationService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService
from common.exporter import clean_scene, export_godot_glb

SDK_ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = SDK_ROOT / "assets" / "models" / "ghost_girl"
TEX_DIR = MODEL_DIR / "textures"
HUMANIZER_DIR = MODEL_DIR / "humanizer_export"
TARGET_GLB = MODEL_DIR / "ghost_girl.glb"

TARGET_HEIGHT_M: float = 1.58

EXPECTED_16_MESHES: Tuple[str, ...] = (
    "GhostGirl_Body",
    "GhostGirl_Head",
    "GhostGirl_Eye_L",
    "GhostGirl_Eye_R",
    "GhostGirl_Eyelashes",
    "GhostGirl_Teeth_Upper",
    "GhostGirl_Teeth_Lower",
    "GhostGirl_Tongue",
    "GhostGirl_Hair_Cap",
    "GhostGirl_Hair_Cards",
    "GhostGirl_Hood",
    "GhostGirl_Cape",
    "GhostGirl_CropTop",
    "GhostGirl_Skirt",
    "GhostGirl_Gloves",
    "GhostGirl_Boots",
)

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
# Generic Math & Image Helpers
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


def _load_image_rgba(path: Path) -> np.ndarray:
    img = bpy.data.images.load(str(path), check_existing=False)
    w, h = img.size[0], img.size[1]
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    rgba = buf.reshape((h, w, 4))
    return np.ascontiguousarray(rgba[::-1, :, :])


def _load_image_rgb(path: Path) -> np.ndarray:
    return _load_image_rgba(path)[:, :, :3]


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
    normal_path: Optional[Path] = None,
    orm_path: Optional[Path] = None,
    base_color: Tuple[float, float, float, float] = (0.85, 0.85, 0.85, 1.0),
    roughness: float = 0.60,
    metallic: float = 0.0,
    alpha_mode: str = "OPAQUE",
    alpha_threshold: float = 0.42,
    double_sided: bool = False,
    coat: float = 0.0,
    sss: float = 0.0,
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
    bsdf.inputs["Metallic"].default_value = metallic
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.05
    if "Subsurface Weight" in bsdf.inputs and sss > 0.0:
        bsdf.inputs["Subsurface Weight"].default_value = sss
        if "Subsurface Scale" in bsdf.inputs:
            bsdf.inputs["Subsurface Scale"].default_value = 0.005
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if albedo_path and albedo_path.exists():
        img = bpy.data.images.load(str(albedo_path), check_existing=True)
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_mode != "OPAQUE":
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])

    if normal_path and normal_path.exists():
        img_n = bpy.data.images.load(str(normal_path), check_existing=True)
        img_n.colorspace_settings.name = "Non-Color"
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = img_n
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = 0.55
        nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

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
    elif alpha_mode == "CLIP":
        if hasattr(mat, "blend_method"):
            mat.blend_method = "CLIP"
        if hasattr(mat, "alpha_threshold"):
            mat.alpha_threshold = alpha_threshold
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "DITHERED"
    elif alpha_mode == "HASHED":
        if hasattr(mat, "blend_method"):
            mat.blend_method = "HASHED"
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


def _bake_shape_keys_to_mesh(obj: bpy.types.Object) -> None:
    """Evaluate current mixed shape keys into mesh vertices and clear shape keys (preserves vert indices)."""
    if obj.data.shape_keys is None:
        return
    deps = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(deps)
    eval_mesh = eval_obj.to_mesh()
    for i, v in enumerate(obj.data.vertices):
        v.co = eval_mesh.vertices[i].co.copy()
    eval_obj.to_mesh_clear()
    obj.shape_key_clear()
    obj.data.update()


# ---------------------------------------------------------------------------
# Step 1: Spawn MPFB2 Un-Morphed Basis & Sculpt Anime Ghost Girl
# ---------------------------------------------------------------------------

def _spawn_and_sculpt_anime_base() -> Tuple[bpy.types.Object, List[Vector]]:
    """Spawn MPFB2 19,158-vert base mesh, capture un-morphed basis, apply anime sculpt & 1.58m height."""
    # 1. Capture un-morphed neutral basis (mask_helpers=False -> 19,158 verts) matching Godot basis.data
    basis_obj = HumanService.create_human(
        mask_helpers=False,
        detailed_helpers=True,
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=None,
    )
    assert len(basis_obj.data.vertices) == 19158, (
        f"Expected 19158 MPFB2 vertices, got {len(basis_obj.data.vertices)}"
    )
    # Record neutral un-morphed vertex coordinates before macro/anime morphs
    basis_coords: List[Vector] = [v.co.copy() for v in basis_obj.data.vertices]

    # 2. Apply youthful female macro targets onto the exact same 19,158-vert mesh
    macro = TargetService.get_default_macro_info_dict()
    macro.update(
        {
            "gender": 0.0,
            "age": 0.22,
            "muscle": 0.24,
            "weight": 0.25,
            "proportions": 0.55,
            "height": 0.30,
            "cupsize": 0.44,
            "firmness": 0.74,
            "race": {"asian": 0.70, "caucasian": 0.30, "african": 0.0},
        }
    )
    for k, val in macro.items():
        if k != "race":
            HumanObjectProperties.set_value(k, val, entity_reference=basis_obj)
    for rk, rval in macro["race"].items():
        HumanObjectProperties.set_value(rk, rval, entity_reference=basis_obj)
    TargetService.reapply_macro_details(basis_obj)
    _bake_shape_keys_to_mesh(basis_obj)

    bm_obj = basis_obj
    bm_obj.name = "GhostGirl_Base"

    # Re-seat body feet at Z=0 before sculpting
    body_vs = _vg_indices(bm_obj, ("body",))
    min_body_z = min(bm_obj.data.vertices[i].co.z for i in body_vs)
    for v in bm_obj.data.vertices:
        v.co.z -= min_body_z

    # Flatten sharp nipple tips smoothly
    nip_vs = _vg_indices(bm_obj, ("nippleTip", "nipple"))
    for idx in nip_vs:
        bm_obj.data.vertices[idx].co.y += 0.008

    # Measure key anatomical landmarks in canonical MPFB2 pose before anime sculpt
    verts = bm_obj.data.vertices
    z_crown_raw = max(verts[i].co.z for i in body_vs)
    l_eye_helper = _vg_indices(bm_obj, ("helper-l-eye",))
    r_eye_helper = _vg_indices(bm_obj, ("helper-r-eye",))
    l_eye_c = sum((verts[i].co for i in l_eye_helper), Vector((0.0, 0.0, 0.0))) / float(len(l_eye_helper))
    r_eye_c = sum((verts[i].co for i in r_eye_helper), Vector((0.0, 0.0, 0.0))) / float(len(r_eye_helper))

    lip_vs = _vg_indices(bm_obj, ("lips",))
    mouth_c = sum((verts[i].co for i in lip_vs), Vector((0.0, 0.0, 0.0))) / float(len(lip_vs))
    z_neck_base = z_crown_raw - 0.275
    z_neck_top = z_crown_raw - 0.210
    neck_pivot = Vector((0.0, 0.5 * (l_eye_c.y + mouth_c.y) + 0.045, z_neck_base))

    # 3. Sculpt anime body + head proportions (~1:6.2 head-to-body ratio, slender torso/legs,
    #    tapered V-chin, enlarged anime eye orbits, petite nose/mouth) across ALL 19,158 verts
    #    so skin AND helper-* geometry deform in exact lockstep!
    eye_helpers_l = _vg_indices(bm_obj, ("helper-l-eye", "helper-l-eyelashes-1", "helper-l-eyelashes-2", "joint-l-eye", "joint-l-upperlid", "joint-l-lowerlid"))
    eye_helpers_r = _vg_indices(bm_obj, ("helper-r-eye", "helper-r-eyelashes-1", "helper-r-eyelashes-2", "joint-r-eye", "joint-r-upperlid", "joint-r-lowerlid"))

    for v in verts:
        p = v.co.copy()
        z = p.z
        ax = abs(p.x)

        # Slender anime torso/hips/waist calibration
        if z < z_neck_base and ax < 0.20:
            w_waist = _gauss(z - (z_crown_raw * 0.625), 0.075)
            if w_waist > 1e-3:
                p.x *= 1.0 - 0.075 * w_waist
                p.y *= 1.0 - 0.045 * w_waist
            # Smooth bust apex cones slightly
            if p.y < -0.05 and (z_crown_raw * 0.70) <= z <= (z_crown_raw * 0.80) and ax < 0.13:
                w_apex = _gauss(ax - 0.072, 0.024) * _gauss(z - (z_crown_raw * 0.745), 0.025)
                p.y += 0.008 * w_apex
            # Subtle slender legs
            if z < z_crown_raw * 0.52:
                w_leg = _smoothstep(z_crown_raw * 0.52, z_crown_raw * 0.12, z)
                p.x *= 1.0 - 0.03 * w_leg
                p.y *= 1.0 - 0.03 * w_leg

        # Anime head scale (~1.10x larger head for ~1:6.2 head-to-body ratio)
        w_head = _smoothstep(z_neck_base - 0.02, z_neck_top + 0.02, z)
        if w_head > 1e-4:
            rel_h = p - neck_pivot
            head_scaled = neck_pivot + Vector((rel_h.x * 1.11, rel_h.y * 1.09, rel_h.z * 1.11))
            p = p.lerp(head_scaled, w_head)

            # Tapered anime V-chin & soft narrow lower jaw
            if z < l_eye_c.z - 0.015 and p.y < 0.015:
                w_jaw = _smoothstep(l_eye_c.z - 0.015, z_neck_top + 0.01, z) * _smoothstep(0.015, -0.08, p.y)
                p.x *= 1.0 - 0.135 * w_jaw
                # Soften chin point forward/up slightly
                w_chin = _gauss(ax, 0.030) * _gauss(z - (mouth_c.z - 0.032), 0.020) * _smoothstep(0.0, -0.08, p.y)
                p.z += 0.0065 * w_chin
                p.y += 0.0035 * w_chin

            # Petite anime nose (narrow sleek bridge, dainty button tip, soft philtrum)
            if p.y < -0.095 and ax < 0.030 and (mouth_c.z + 0.008) < z < (l_eye_c.z + 0.008):
                w_nose = _gauss(ax, 0.018) * _gauss(z - (l_eye_c.z - 0.019), 0.015)
                p.x *= 1.0 - 0.28 * w_nose
                p.y += 0.0068 * w_nose

            # Petite anime mouth (narrow delicate lips, slim profile protrusion)
            if p.y < -0.090 and ax < 0.036 and abs(z - mouth_c.z) < 0.024:
                w_m = _gauss(ax, 0.024) * _gauss(z - mouth_c.z, 0.014)
                p.x *= 1.0 - 0.24 * w_m
                p.y += 0.0055 * w_m

        v.co = p

    bm_obj.data.update()

    # Re-measure eye centers after head scale and enlarge anime eye orbits cleanly (~1.5x tall anime eyes)
    l_eye_c2 = sum((verts[i].co for i in l_eye_helper), Vector((0.0, 0.0, 0.0))) / float(len(l_eye_helper))
    r_eye_c2 = sum((verts[i].co for i in r_eye_helper), Vector((0.0, 0.0, 0.0))) / float(len(r_eye_helper))

    for idx, v in enumerate(verts):
        p = v.co.copy()
        for eye_c, helper_set, sx_sign in (
            (l_eye_c2, eye_helpers_l, 1.0),
            (r_eye_c2, eye_helpers_r, -1.0),
        ):
            rel = p - eye_c
            # Only affect anterior orbital region around this eye
            if p.x * sx_sign < -0.004:
                continue
            d_orbit = math.sqrt((rel.x / 0.030) ** 2 + (rel.z / 0.026) ** 2 + (rel.y / 0.032) ** 2)
            is_eye_helper = idx in helper_set
            if is_eye_helper:
                # Tall expressive anime eyeballs, tucked cleanly in socket so +20deg yaw never pokes outer cheek
                new_rel = Vector((
                    rel.x * 1.32 + sx_sign * 0.0012,
                    rel.y * 0.76 - 0.0004,
                    rel.z * 1.72,
                ))
                p = eye_c + new_rel
                break
            elif d_orbit < 1.65 and p.y < eye_c.y + 0.030:
                # Wide open tall round-oval anime eye aperture (trigger 100% right at ±4.5mm eyelid rim!)
                w_orb = math.exp(-0.55 * (d_orbit ** 2))
                dz_open = (0.0145 if rel.z >= 0.0 else -0.0105) * _smoothstep(0.0005, 0.0045, abs(rel.z))
                dx_open = sx_sign * 0.0048 * _smoothstep(0.001, 0.012, abs(rel.x))
                dy_flat = -0.0028 if abs(rel.z) < 0.018 else 0.0014
                p += Vector((dx_open * w_orb, dy_flat * w_orb, dz_open * w_orb))
                # Gently lift recessed under-eye tear-trough hollow so cheeks read smooth anime
                if -0.028 < rel.z < -0.012 and abs(rel.x) < 0.028:
                    w_trough = _gauss(rel.z + 0.018, 0.007) * _gauss(rel.x, 0.018)
                    p.y -= 0.0024 * w_trough
                break
        v.co = p

    # Smooth ONLY lower cheek/jaw/forehead transitions (STRICTLY preserve wide open eye sockets & eyelids!)
    bm_sm = bmesh.new()
    bm_sm.from_mesh(bm_obj.data)
    bm_sm.verts.ensure_lookup_table()
    face_smooth_vs = [
        v
        for v in bm_sm.verts
        if v.index in body_vs
        and v.co.z > z_neck_top + 0.02
        and v.co.y < l_eye_c2.y + 0.015
        and not (abs(v.co.z - l_eye_c2.z) < 0.024 and abs(abs(v.co.x) - abs(l_eye_c2.x)) < 0.032)
        and abs(v.co.z - mouth_c.z) > 0.009
    ]
    for _ in range(4):
        bmesh.ops.smooth_vert(bm_sm, verts=face_smooth_vs, factor=0.40, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm_sm.to_mesh(bm_obj.data)
    bm_sm.free()

    # 4. Uniformly scale canonical mesh to TARGET_HEIGHT_M = 1.58m with body feet at Z=0
    min_bz = min(verts[i].co.z for i in body_vs)
    max_bz = max(verts[i].co.z for i in body_vs)
    cur_h = max(max_bz - min_bz, 1e-4)
    scale_f = TARGET_HEIGHT_M / cur_h
    mid_x = 0.5 * (min(verts[i].co.x for i in body_vs) + max(verts[i].co.x for i in body_vs))
    pelvis_ys = [
        verts[i].co.y
        for i in body_vs
        if abs(verts[i].co.x) < 0.10 and (min_bz + 0.45 * cur_h) <= verts[i].co.z <= (min_bz + 0.55 * cur_h)
    ]
    mid_y = sum(pelvis_ys) / len(pelvis_ys) if pelvis_ys else 0.0

    for v in verts:
        v.co.x = (v.co.x - mid_x) * scale_f
        v.co.y = (v.co.y - mid_y) * scale_f
        v.co.z = (v.co.z - min_bz) * scale_f
    bm_obj.data.update()

    final_min_z = min(verts[i].co.z for i in body_vs)
    final_max_z = max(verts[i].co.z for i in body_vs)
    print(
        f"[build_ghost_girl] Canonical anime MPFB2 mesh ready: verts={len(verts)}, "
        f"body Z=[{final_min_z:.4f}, {final_max_z:.4f}]m"
    )
    return bm_obj, basis_coords


# ---------------------------------------------------------------------------
# Step 2: Humanizer .target + BVHTree .mhclo + .obj Export (Canonical Pose)
# ---------------------------------------------------------------------------

def _bl_to_mh_vec(v: Vector) -> Tuple[float, float, float]:
    """Convert Blender (X, Y, Z) -> MakeHuman / Godot (X, Z, -Y)."""
    return (v.x, v.z, -v.y)


def _export_humanizer_target(
    bm_obj: bpy.types.Object,
    basis_coords: List[Vector],
) -> Tuple[List[float], List[float], List[float], List[float]]:
    """Write ghost_girl_anime.target (meters, Y-up/+Z-forward) and return basis/sculpted MH bounds."""
    HUMANIZER_DIR.mkdir(parents=True, exist_ok=True)
    target_path = HUMANIZER_DIR / "ghost_girl_anime.target"

    basis_mh = [_bl_to_mh_vec(c) for c in basis_coords]
    sculpt_mh = [_bl_to_mh_vec(v.co) for v in bm_obj.data.vertices]

    b_min = [min(p[i] for p in basis_mh) for i in range(3)]
    b_max = [max(p[i] for p in basis_mh) for i in range(3)]
    s_min = [min(p[i] for p in sculpt_mh) for i in range(3)]
    s_max = [max(p[i] for p in sculpt_mh) for i in range(3)]

    lines: List[str] = [
        "# MakeHuman target morph for Ghost Girl stylized anime proportions\n",
        "# Coordinate system: MakeHuman / Godot Y-up, +Z-forward (dx = x, dy = z_bl, dz = -y_bl)\n",
        "# unit_scale_to_basis_data: 1.0 (deltas are already in meters matching basis.data)\n",
        f"# vert_count: {len(sculpt_mh)}\n",
    ]
    written = 0
    for idx, (b_p, s_p) in enumerate(zip(basis_mh, sculpt_mh)):
        dx = s_p[0] - b_p[0]
        dy = s_p[1] - b_p[1]
        dz = s_p[2] - b_p[2]
        if (dx * dx + dy * dy + dz * dz) > 1e-12:
            lines.append(f"{idx} {dx:.6f} {dy:.6f} {dz:.6f}\n")
            written += 1

    target_path.write_text("".join(lines), encoding="utf-8")
    print(f"[build_ghost_girl] Wrote {target_path} ({written}/{len(sculpt_mh)} deltas)")
    return b_min, b_max, s_min, s_max


def _barycentric_weights(p: Vector, a: Vector, b: Vector, c: Vector) -> Tuple[float, float, float]:
    """Compute exact clamped barycentric weights of point p projected onto triangle (a, b, c)."""
    v0 = b - a
    v1 = c - a
    v2 = p - a
    d00 = v0.dot(v0)
    d01 = v0.dot(v1)
    d11 = v1.dot(v1)
    d20 = v2.dot(v0)
    d21 = v2.dot(v1)
    denom = d00 * d11 - d01 * d01
    if abs(denom) < 1e-14:
        return (1.0, 0.0, 0.0)
    v = (d11 * d20 - d01 * d21) / denom
    w = (d00 * d21 - d01 * d20) / denom
    u = 1.0 - v - w
    return (u, v, w)


def _export_wavefront_obj_exact(obj: bpy.types.Object, obj_path: Path) -> None:
    """Write Wavefront .obj in Y-up/+Z-forward meters preserving exact mesh vertex indices 0..N-1."""
    mesh = obj.data
    mesh.update()
    uv_layer = mesh.uv_layers.active.data if mesh.uv_layers.active else None

    lines: List[str] = [
        "# Wavefront OBJ exported by build_ghost_girl.py (Y-up, +Z-forward, meters)\n",
        f"o {obj.name}\n",
    ]
    for v in mesh.vertices:
        mx, my, mz = _bl_to_mh_vec(v.co)
        lines.append(f"v {mx:.6f} {my:.6f} {mz:.6f}\n")

    vt_map: Dict[Tuple[float, float], int] = {}
    vt_list: List[Tuple[float, float]] = []
    vn_map: Dict[Tuple[float, float, float], int] = {}
    vn_list: List[Tuple[float, float, float]] = []
    face_lines: List[str] = []

    for poly in mesh.polygons:
        n_v = _bl_to_mh_vec(poly.normal)
        f_tokens: List[str] = []
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index + 1
            if uv_layer is not None:
                u, v_uv = uv_layer[li].uv
                uv_key = (round(float(u), 6), round(float(v_uv), 6))
            else:
                uv_key = (0.0, 0.0)
            if uv_key not in vt_map:
                vt_list.append(uv_key)
                vt_map[uv_key] = len(vt_list)
            vti = vt_map[uv_key]

            v_n = mesh.vertices[vi - 1].normal if poly.use_smooth else poly.normal
            nx, ny, nz = _bl_to_mh_vec(v_n)
            n_len = math.sqrt(nx * nx + ny * ny + nz * nz)
            if n_len > 1e-6:
                nx, ny, nz = nx / n_len, ny / n_len, nz / n_len
            else:
                nx, ny, nz = n_v
            vn_key = (round(nx, 4), round(ny, 4), round(nz, 4))
            if vn_key not in vn_map:
                vn_list.append(vn_key)
                vn_map[vn_key] = len(vn_list)
            vni = vn_map[vn_key]
            f_tokens.append(f"{vi}/{vti}/{vni}")
        face_lines.append("f " + " ".join(f_tokens) + "\n")

    for u, v_uv in vt_list:
        lines.append(f"vt {u:.6f} {v_uv:.6f}\n")
    for nx, ny, nz in vn_list:
        lines.append(f"vn {nx:.4f} {ny:.4f} {nz:.4f}\n")
    lines.extend(face_lines)
    obj_path.write_text("".join(lines), encoding="utf-8")


def _export_mhclo_asset(
    bm_obj: bpy.types.Object,
    garment_obj: bpy.types.Object,
    asset_name: str,
    albedo_src: Path,
    allowed_base_groups: Sequence[str],
    scale_part: str = "Torso",
    z_depth: int = 50,
    delete_groups: Optional[Sequence[str]] = None,
) -> Dict[str, object]:
    """Compute BVHTree barycentric triangle bindings against bm_obj and write .mhclo + .obj + albedo."""
    out_dir = HUMANIZER_DIR / asset_name
    out_dir.mkdir(parents=True, exist_ok=True)
    mhclo_path = out_dir / f"{asset_name}.mhclo"
    obj_path = out_dir / f"{asset_name}.obj"
    alb_dst = out_dir / f"{asset_name}_albedo.png"

    if albedo_src.exists():
        arr = _load_image_rgba(albedo_src)
        _save_image(alb_dst, arr)

    _export_wavefront_obj_exact(garment_obj, obj_path)

    # Build BVHTree over ONLY triangles belonging to allowed_base_groups on the 19,158-vert bm_obj
    allowed_verts = _vg_indices(bm_obj, allowed_base_groups, min_w=0.01)
    bm = bmesh.new()
    bm.from_mesh(bm_obj.data)
    bm.verts.ensure_lookup_table()

    # Keep triangles whose 3 vertices all belong to allowed_verts and have non-zero area
    tris: List[Tuple[int, int, int]] = []
    bvh_verts: List[Vector] = [v.co.copy() for v in bm.verts]
    for f in bm.faces:
        f_verts = [v.index for v in f.verts]
        if len(f_verts) < 3 or not all(vi in allowed_verts for vi in f_verts):
            continue
        for i in range(1, len(f_verts) - 1):
            a_i, b_i, c_i = f_verts[0], f_verts[i], f_verts[i + 1]
            ab = bvh_verts[b_i] - bvh_verts[a_i]
            ac = bvh_verts[c_i] - bvh_verts[a_i]
            if ab.cross(ac).length > 1e-9:
                tris.append((a_i, b_i, c_i))
    bm.free()

    bvh = BVHTree.FromPolygons(bvh_verts, tris, all_triangles=True)

    # Reference scale on sculpted bm_obj (scale_factor = 0.1 -> decimeters)
    dims = CLOTHES_REFERENCE_SCALE[scale_part]
    v_bm = bm_obj.data.vertices
    x_len = max(abs(v_bm[dims["xmax"]].co.x - v_bm[dims["xmin"]].co.x) / 0.1, 0.1)
    z_len_bl = max(abs(v_bm[dims["zmax"]].co.z - v_bm[dims["zmin"]].co.z) / 0.1, 0.1)
    y_len_bl = max(abs(v_bm[dims["ymax"]].co.y - v_bm[dims["ymin"]].co.y) / 0.1, 0.1)

    lines: List[str] = [
        "# MHCLO asset exported by build_ghost_girl.py for Humanizer\n",
        f"name {asset_name}\n",
        f"obj_file {asset_name}.obj\n",
        f"x_scale {dims['xmin']} {dims['xmax']} {x_len:.4f}\n",
        f"y_scale {dims['zmin']} {dims['zmax']} {z_len_bl:.4f}\n",
        f"z_scale {dims['ymin']} {dims['ymax']} {y_len_bl:.4f}\n",
        f"z_depth {z_depth}\n",
        "verts 0\n",
    ]

    for gv in garment_obj.data.vertices:
        q = gv.co
        loc, _, tri_idx, _ = bvh.find_nearest(q)
        if tri_idx is None:
            # Fallback to vertex 0
            lines.append("0\n")
            continue
        ia, ib, ic = tris[tri_idx]
        va, vb, vc = bvh_verts[ia], bvh_verts[ib], bvh_verts[ic]
        wa, wb, wc = _barycentric_weights(loc, va, vb, vc)
        # Clamp mild extrapolation for numerical stability while keeping sum = 1
        wa = max(-0.5, min(1.5, wa))
        wb = max(-0.5, min(1.5, wb))
        wc = 1.0 - wa - wb
        base_pt = va * wa + vb * wb + vc * wc
        d = q - base_pt
        # Convert Blender meters -> MakeHuman decimeters Y-up/+Z-forward
        ox, oy, oz = d.x / 0.1, d.z / 0.1, -d.y / 0.1
        lines.append(f"{ia} {ib} {ic} {wa:.4f} {wb:.4f} {wc:.4f} {ox:.4f} {oy:.4f} {oz:.4f}\n")

    if delete_groups:
        del_idxs = sorted(_vg_indices(bm_obj, delete_groups, min_w=0.05))
        if del_idxs:
            lines.append("\ndelete_verts\n")
            ranges: List[str] = []
            start = prev = del_idxs[0]
            for di in del_idxs[1:]:
                if di == prev + 1:
                    prev = di
                else:
                    ranges.append(f"{start} - {prev}" if start != prev else f"{start}")
                    start = prev = di
            ranges.append(f"{start} - {prev}" if start != prev else f"{start}")
            lines.append(" ".join(ranges) + "\n")

    mhclo_path.write_text("".join(lines), encoding="utf-8")
    print(
        f"[build_ghost_girl] Exported Humanizer {asset_name}: "
        f"{len(garment_obj.data.vertices)} verts -> {mhclo_path.name}"
    )
    return {
        "name": asset_name,
        "mhclo": f"{asset_name}/{asset_name}.mhclo",
        "obj": f"{asset_name}/{asset_name}.obj",
        "albedo": f"{asset_name}/{asset_name}_albedo.png",
        "vert_count": len(garment_obj.data.vertices),
    }


# ---------------------------------------------------------------------------
# Step 3: Clean Anime Skin, Eyes, Eyelashes, Mouth & Hair Builders
# ---------------------------------------------------------------------------

def _measure_canonical_landmarks(
    bm_obj: bpy.types.Object,
    eyes_obj: bpy.types.Object,
) -> Dict[str, Vector]:
    """Measure key facial and body landmarks on sculpted 1.58m canonical or head mesh."""
    verts = bm_obj.data.vertices
    body_vs = _vg_indices(bm_obj, ("body",))
    if not body_vs:
        body_vs = set(range(len(verts)))

    pts = [verts[i].co.copy() for i in body_vs]
    z_min = min(v.z for v in pts)
    z_max = max(v.z for v in pts)
    x_min = min(v.x for v in pts)
    x_max = max(v.x for v in pts)
    y_min = min(v.y for v in pts)
    y_max = max(v.y for v in pts)

    l_eye_pts = [v.co for v in eyes_obj.data.vertices if v.co.x >= 0.0]
    r_eye_pts = [v.co for v in eyes_obj.data.vertices if v.co.x < 0.0]
    l_eye_c = sum(l_eye_pts, Vector((0.0, 0.0, 0.0))) / float(max(len(l_eye_pts), 1))
    r_eye_c = sum(r_eye_pts, Vector((0.0, 0.0, 0.0))) / float(max(len(r_eye_pts), 1))
    ex = 0.5 * (abs(l_eye_c.x) + abs(r_eye_c.x))
    ey = 0.5 * (l_eye_c.y + r_eye_c.y)
    ez = 0.5 * (l_eye_c.z + r_eye_c.z)
    l_eye_c = Vector((ex, ey, ez))
    r_eye_c = Vector((-ex, ey, ez))

    lip_vs = _vg_indices(bm_obj, ("lips",))
    lip_pts = [verts[i].co for i in lip_vs] if lip_vs else []
    front_lips = [p for p in lip_pts if abs(p.x) < 0.008]
    y_lip_front = min((p.y for p in front_lips), default=y_min + 0.01)
    z_up_lip = max((p.z for p in front_lips), default=ez - 0.048)
    z_lo_lip = min((p.z for p in front_lips), default=ez - 0.068)
    z_mouth = 0.5 * (z_up_lip + z_lo_lip) + 0.0005
    mouth_c = Vector((0.0, y_lip_front + 0.003, z_mouth))

    nose_cands = [p for p in pts if abs(p.x) < 0.012 and (z_up_lip + 0.006) < p.z < (ez - 0.006)]
    nose_tip = min(nose_cands, key=lambda v: v.y) if nose_cands else Vector((0.0, y_lip_front - 0.008, ez - 0.025))

    chin_cands = [
        p for p in pts
        if abs(p.x) < 0.015 and p.y < y_lip_front + 0.030 and (z_lo_lip - 0.055) < p.z < (z_lo_lip - 0.010)
    ]
    chin_pt = min(chin_cands, key=lambda v: v.z) if chin_cands else Vector((0.0, y_lip_front + 0.010, z_lo_lip - 0.030))

    ear_vs = _vg_indices(bm_obj, ("ears",))
    ear_pts = [verts[i].co for i in ear_vs]
    ear_z = sum(p.z for p in ear_pts) / float(len(ear_pts)) if ear_pts else (ez - 0.012)
    ear_y = sum(p.y for p in ear_pts) / float(len(ear_pts)) if ear_pts else (0.5 * (y_min + y_max))
    ear_max_x = max((abs(p.x) for p in ear_pts), default=0.088)

    head_pts = [p for p in pts if p.z > chin_pt.z - 0.02 and abs(p.x) < 0.14]
    hy_min = min((p.y for p in head_pts), default=y_min)
    hy_max = max((p.y for p in head_pts), default=y_max)

    return {
        "bbox_min": Vector((x_min, y_min, z_min)),
        "bbox_max": Vector((x_max, y_max, z_max)),
        "left_eye": l_eye_c,
        "right_eye": r_eye_c,
        "mouth": mouth_c,
        "z_upper_lip_top": Vector((0.0, y_lip_front, z_up_lip)),
        "z_lower_lip_bot": Vector((0.0, y_lip_front, z_lo_lip)),
        "nose_tip": nose_tip,
        "chin": chin_pt,
        "ear_y": Vector((ear_max_x, ear_y, ear_z)),
        "head_center": Vector((0.0, 0.5 * (hy_min + hy_max), 0.5 * (chin_pt.z + z_max))),
        "head_y_min": Vector((0.0, hy_min, ez)),
        "head_y_max": Vector((0.0, hy_max, ez)),
    }


def _build_anime_skin_texture(
    bm_obj: bpy.types.Object,
    lm: Dict[str, Vector],
    tex_size: int = 2048,
) -> Tuple[Path, Path, Path]:
    """Generate clean seamless 2048x2048 anime skin albedo + normal + ORM on MakeHuman UV layout."""
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    HUMANIZER_DIR.mkdir(parents=True, exist_ok=True)
    alb_path = TEX_DIR / "ghost_girl_skin_albedo.png"
    hum_skin_path = HUMANIZER_DIR / "ghost_girl_anime_skin.png"
    nrm_path = TEX_DIR / "ghost_girl_skin_normal.png"
    orm_path = TEX_DIR / "ghost_girl_skin_orm.png"

    # Rasterize ONLY anatomical 'body' faces (0..13379) onto 2K UV atlas
    body_verts = _vg_indices(bm_obj, ("body",))
    mesh = bm_obj.data
    mesh.calc_loop_triangles()
    uv_layer = mesh.uv_layers.active.data

    pos_map = np.zeros((tex_size, tex_size, 3), dtype=np.float32)
    nrm_map = np.zeros((tex_size, tex_size, 3), dtype=np.float32)
    ear_map = np.zeros((tex_size, tex_size), dtype=np.float32)
    cov_map = np.zeros((tex_size, tex_size), dtype=np.uint8)

    verts_co = np.array([v.co[:] for v in mesh.vertices], dtype=np.float32)
    verts_no = np.array([v.normal[:] for v in mesh.vertices], dtype=np.float32)
    ear_vs = _vg_indices(bm_obj, ("ears",))
    ear_w = np.zeros(len(mesh.vertices), dtype=np.float32)
    for ei in ear_vs:
        ear_w[ei] = 1.0

    for tri in mesh.loop_triangles:
        v_idx = tri.vertices
        if not all(int(vi) in body_verts for vi in v_idx):
            continue
        l_idx = tri.loops
        u0, v0 = uv_layer[l_idx[0]].uv
        u1, v1 = uv_layer[l_idx[1]].uv
        u2, v2 = uv_layer[l_idx[2]].uv
        px0, py0 = u0 * (tex_size - 1), (1.0 - v0) * (tex_size - 1)
        px1, py1 = u1 * (tex_size - 1), (1.0 - v1) * (tex_size - 1)
        px2, py2 = u2 * (tex_size - 1), (1.0 - v2) * (tex_size - 1)
        min_x = max(0, int(math.floor(min(px0, px1, px2))))
        max_x = min(tex_size - 1, int(math.ceil(max(px0, px1, px2))))
        min_y = max(0, int(math.floor(min(py0, py1, py2))))
        max_y = min(tex_size - 1, int(math.ceil(max(py0, py1, py2))))
        if max_x < min_x or max_y < min_y:
            continue
        denom = (py1 - py2) * (px0 - px2) + (px2 - px1) * (py0 - py2)
        if abs(denom) < 1e-7:
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
        pos_map[min_y + iy, min_x + ix] = b0 * verts_co[v_idx[0]] + b1 * verts_co[v_idx[1]] + b2 * verts_co[v_idx[2]]
        nrm_map[min_y + iy, min_x + ix] = b0 * verts_no[v_idx[0]] + b1 * verts_no[v_idx[1]] + b2 * verts_no[v_idx[2]]
        ear_map[min_y + iy, min_x + ix] = b0[:, 0] * ear_w[v_idx[0]] + b1[:, 0] * ear_w[v_idx[1]] + b2[:, 0] * ear_w[v_idx[2]]
        cov_map[min_y + iy, min_x + ix] = 1

    # Soft peach-fair anime base skin (#FDE6DA) with zero dark under-eye rings
    base_col = np.array([0.990, 0.902, 0.855], dtype=np.float32)
    blush_col = np.array([0.970, 0.755, 0.730], dtype=np.float32)
    shadow_col = np.array([0.920, 0.775, 0.740], dtype=np.float32)
    lash_col = np.array([0.115, 0.088, 0.165], dtype=np.float32)
    brow_col = np.array([0.365, 0.295, 0.490], dtype=np.float32)
    lip_col = np.array([0.948, 0.700, 0.695], dtype=np.float32)

    albedo = np.broadcast_to(base_col[None, None, :], (tex_size, tex_size, 3)).copy()
    ys_c, xs_c = np.where(cov_map > 0)
    P = pos_map[ys_c, xs_c]
    N = nrm_map[ys_c, xs_c]
    E = ear_map[ys_c, xs_c]

    px = P[:, 0]
    py = P[:, 1]
    pz = P[:, 2]

    le = lm["left_eye"]
    re = lm["right_eye"]
    mc = lm["mouth"]
    nt = lm["nose_tip"]

    col = np.broadcast_to(base_col[None, :], (len(px), 3)).copy()

    # 1. Soft ear concha shading
    w_ear = np.clip(E * 0.45, 0.0, 0.45)[:, None]
    col = col * (1.0 - w_ear) + shadow_col[None, :] * w_ear

    # 2. Anterior face painting (-Y facing)
    is_front = py < lm["ear_y"].y - 0.015

    # Soft anime cheek blush ovals positioned on mid-cheeks (well below under-eye!)
    cheek_l = np.exp(-0.5 * (((np.abs(px) - (abs(le.x) + 0.010)) / 0.016) ** 2 + ((pz - (le.z - 0.032)) / 0.009) ** 2))
    w_cheek = np.where(is_front, cheek_l * 0.28, 0.0)[:, None]
    col = col * (1.0 - w_cheek) + blush_col[None, :] * w_cheek

    # Delicate petite anime nose tip blush
    nose_d = np.exp(-0.5 * ((px / 0.0038) ** 2 + ((pz - (nt.z - 0.002)) / 0.0042) ** 2))
    w_nose = np.where(is_front & (py < nt.y + 0.015), nose_d * 0.24, 0.0)[:, None]
    col = col * (1.0 - w_nose) + shadow_col[None, :] * w_nose

    # Petite anime mouth line & soft lip tint
    mouth_line = np.exp(-0.5 * ((px / 0.012) ** 2 + ((pz - mc.z) / 0.0014) ** 2))
    mouth_tint = np.exp(-0.5 * ((px / 0.013) ** 2 + ((pz - mc.z) / 0.0045) ** 2))
    w_lip = np.where(is_front & (py < mc.y + 0.015), mouth_tint * 0.30, 0.0)[:, None]
    col = col * (1.0 - w_lip) + lip_col[None, :] * w_lip
    w_mline = np.where(is_front & (py < mc.y + 0.010), mouth_line * 0.35, 0.0)[:, None]
    col = col * (1.0 - w_mline) + (shadow_col * 0.70)[None, :] * w_mline

    # Crisp thin dark-lavender arched anime eyebrows clearly visible above enlarged eyes (below lifted bangs!)
    brow_dark = np.array([0.245, 0.185, 0.385], dtype=np.float32)
    for ex_c in (le.x, re.x):
        dx_b = (px - ex_c) / 0.024
        arch_z = le.z + 0.0245 - 0.0042 * (dx_b * dx_b)
        brow_m = np.exp(-0.5 * ((pz - arch_z) / 0.0016) ** 2) * np.clip(1.0 - (np.abs(dx_b) ** 2), 0.0, 1.0) * 1.5
        brow_m = np.where(is_front & (np.abs(dx_b) < 1.05) & (py < le.y + 0.012), np.clip(brow_m, 0.0, 1.0), 0.0)[:, None]
        col = col * (1.0 - brow_m * 0.94) + brow_dark[None, :] * (brow_m * 0.94)

    # Keep upper eyelid dome CLEAN peach-fair skin so Blink has ZERO bruise smudge!
    # Apply only a razor-thin dark lash-root seam right along the enlarged upper lid rim.
    for ex_c, sx in ((le.x, 1.0), (re.x, -1.0)):
        dx_e = (px - ex_c) / 0.024
        lid_arch = le.z + 0.0195 - 0.0055 * (dx_e * dx_e)
        liner = np.exp(-0.5 * ((pz - lid_arch) / 0.00085) ** 2) * np.clip(1.0 - (np.abs(dx_e) ** 3), 0.0, 1.0)
        w_liner = np.where(is_front & (np.abs(dx_e) < 1.06) & (py < le.y + 0.008), np.clip(liner, 0.0, 1.0), 0.0)[:, None]
        col = col * (1.0 - w_liner * 0.78) + lash_col[None, :] * (w_liner * 0.78)

    # 3. Body anime details: crisp subtle navel indent + soft knee blush
    z_h = lm["bbox_max"].z - lm["bbox_min"].z
    z_navel = lm["bbox_min"].z + z_h * 0.616
    navel_indent = np.exp(-0.5 * ((px / 0.0038) ** 2 + ((pz - z_navel) / 0.0068) ** 2))
    navel_rim = np.exp(-0.5 * ((px / 0.0055) ** 2 + ((pz - (z_navel + 0.0022)) / 0.0040) ** 2))
    w_navel = np.where(py < -0.04, np.clip(navel_indent * 0.85 + navel_rim * 0.35, 0.0, 0.95), 0.0)[:, None]
    navel_col = np.array([0.780, 0.595, 0.560], dtype=np.float32)
    col = col * (1.0 - w_navel) + navel_col[None, :] * w_navel

    z_knee = lm["bbox_min"].z + z_h * 0.285
    knee_m = np.exp(-0.5 * (((np.abs(px) - 0.085) / 0.028) ** 2 + ((pz - z_knee) / 0.025) ** 2))
    w_knee = np.where(py < -0.01, knee_m * 0.32, 0.0)[:, None]
    col = col * (1.0 - w_knee) + blush_col[None, :] * w_knee

    albedo[ys_c, xs_c] = np.clip(col, 0.0, 1.0)

    # Dilate 4px to prevent UV mip seam lines
    dil = albedo.copy()
    mask = cov_map > 0
    for _ in range(4):
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted = np.roll(np.roll(dil, dy, axis=0), dx, axis=1)
            smask = np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
            fill = (~mask) & smask
            dil[fill] = shifted[fill]
            mask = mask | fill
    albedo = np.clip(dil, 0.0, 1.0)

    _save_image(alb_path, albedo)
    _save_image(hum_skin_path, albedo)

    # Smooth flat-clean anime normal map & ORM (roughness=0.64 matte cel skin)
    flat_nrm = np.zeros((tex_size, tex_size, 3), dtype=np.float32)
    flat_nrm[:, :, 0] = 0.5
    flat_nrm[:, :, 1] = 0.5
    flat_nrm[:, :, 2] = 1.0
    _save_image(nrm_path, flat_nrm)

    orm = np.zeros((tex_size, tex_size, 3), dtype=np.float32)
    orm[:, :, 0] = 0.96
    orm[:, :, 1] = 0.64
    orm[:, :, 2] = 0.0
    _save_image(orm_path, orm)

    return alb_path, nrm_path, orm_path


def _build_anime_eyes(
    eyes_obj: bpy.types.Object,
) -> Tuple[bpy.types.Object, bpy.types.Object, Path]:
    """Split fitted MPFB2 high-poly eyes into GhostGirl_Eye_L & R with large lavender-violet anime iris."""
    eye_alb_path = TEX_DIR / "ghost_girl_eye_albedo.png"
    eye_orm_path = TEX_DIR / "ghost_girl_eye_orm.png"

    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)
    dx = xx - 0.5
    dy = yy - 0.5
    # Large oval anime iris ratio filling cornea generously
    r_circ = np.sqrt(dx * dx + dy * dy)
    r_oval = np.sqrt((dx / 0.320) ** 2 + (dy / 0.360) ** 2)
    ang = np.arctan2(dy, dx)

    img = np.zeros((sz, sz, 3), dtype=np.float32)
    # Clean bright anime sclera (#FCF9FF)
    img[:, :, 0] = 0.988
    img[:, :, 1] = 0.980
    img[:, :, 2] = 0.998

    # Rich anime lavender-violet gradient iris
    iris_mask = r_oval <= 1.0
    grad_y = np.clip((dy / 0.345 + 1.0) * 0.5, 0.0, 1.0)
    spokes = 0.5 + 0.5 * np.cos(ang * 26.0)
    col_top = np.array([0.365, 0.285, 0.695], dtype=np.float32)
    col_mid = np.array([0.655, 0.555, 0.935], dtype=np.float32)
    col_bot = np.array([0.905, 0.845, 1.000], dtype=np.float32)

    iris_col = np.where(
        (grad_y < 0.50)[:, :, None],
        col_top[None, None, :] * (1.0 - (grad_y / 0.50)[:, :, None]) + col_mid[None, None, :] * (grad_y / 0.50)[:, :, None],
        col_mid[None, None, :] * (1.0 - ((grad_y - 0.50) / 0.50)[:, :, None]) + col_bot[None, None, :] * ((grad_y - 0.50) / 0.50)[:, :, None],
    )
    iris_col = np.clip(iris_col + (spokes[:, :, None] - 0.5) * 0.045, 0.0, 1.0)

    # Dark violet limbal outline ring
    rim_w = np.clip((r_oval - 0.86) / 0.14, 0.0, 1.0)[:, :, None]
    limbal = np.array([0.130, 0.095, 0.265], dtype=np.float32)
    iris_col = iris_col * (1.0 - 0.84 * rim_w) + limbal[None, None, :] * (0.84 * rim_w)

    aa_iris = np.clip((1.0 - r_oval) / 0.03, 0.0, 1.0)[:, :, None]
    img = img * (1.0 - aa_iris) + iris_col * aa_iris

    # Crisp dark violet-black oval pupil
    r_pup = np.sqrt((dx / 0.115) ** 2 + (dy / 0.145) ** 2)
    aa_pup = np.clip((1.0 - r_pup) / 0.05, 0.0, 1.0)[:, :, None]
    pup_col = np.array([0.085, 0.060, 0.175], dtype=np.float32)
    img = img * (1.0 - aa_pup) + pup_col[None, None, :] * aa_pup

    # Upper eyelid soft cast shadow across top of sclera & iris (dy < -0.06)
    upper_sh = np.clip((-dy - 0.06) / 0.20, 0.0, 1.0)[:, :, None]
    sh_tint = np.array([0.74, 0.72, 0.88], dtype=np.float32)
    img = img * (1.0 - 0.34 * upper_sh) + (img * sh_tint[None, None, :]) * (0.34 * upper_sh)

    # Dual crisp white anime specular catchlights!
    # 1. Large sharp oval highlight upper-left (-0.125, -0.115)
    h1 = np.sqrt(((dx + 0.125) / 0.072) ** 2 + ((dy + 0.115) / 0.062) ** 2)
    w_h1 = np.clip((1.0 - h1) / 0.06, 0.0, 1.0)[:, :, None]
    # 2. Secondary crisp dot lower-right (+0.110, +0.125)
    h2 = np.sqrt(((dx - 0.110) / 0.038) ** 2 + ((dy - 0.125) / 0.038) ** 2)
    w_h2 = np.clip((1.0 - h2) / 0.06, 0.0, 1.0)[:, :, None]
    w_hl = np.maximum(w_h1, w_h2)
    img = img * (1.0 - w_hl) + w_hl

    # Soft peach-rose edge at far sclera corners (r_circ > 0.42)
    periph = np.clip((r_circ - 0.42) / 0.12, 0.0, 1.0)[:, :, None]
    canthus = np.array([0.88, 0.74, 0.74], dtype=np.float32)
    img = img * (1.0 - 0.65 * periph) + canthus[None, None, :] * (0.65 * periph)

    _save_image(eye_alb_path, img)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.96
    orm[:, :, 1] = np.where(iris_mask, 0.06, 0.14)
    orm[:, :, 2] = 0.0
    _save_image(eye_orm_path, orm)

    eye_mat = _make_pbr_material(
        "M_ghost_girl_eye",
        albedo_path=eye_alb_path,
        orm_path=eye_orm_path,
        roughness=0.06,
        coat=0.90,
    )

    out_eyes: List[bpy.types.Object] = []
    for name, keep_left in (("GhostGirl_Eye_L", True), ("GhostGirl_Eye_R", False)):
        e_copy = eyes_obj.copy()
        e_copy.data = eyes_obj.data.copy()
        e_copy.name = name
        e_copy.data.name = name
        bpy.context.collection.objects.link(e_copy)

        bm = bmesh.new()
        bm.from_mesh(e_copy.data)
        del_faces = [
            f
            for f in bm.faces
            if (f.calc_center_median().x < 0.0 if keep_left else f.calc_center_median().x >= 0.0)
        ]
        bmesh.ops.delete(bm, geom=del_faces, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")

        pts = [v.co.copy() for v in bm.verts]
        center = sum(pts, Vector((0.0, 0.0, 0.0))) / float(len(pts))
        rx = max(abs(p.x - center.x) for p in pts)
        rz = max(abs(p.z - center.z) for p in pts)
        r_max = max(rx, rz, 0.015)

        uv_layer = bm.loops.layers.uv.verify()
        for f in bm.faces:
            f.smooth = True
            for loop in f.loops:
                rel = loop.vert.co - center
                u = 0.5 + (rel.x / (r_max * 1.72))
                v_uv = 0.5 + (rel.z / (r_max * 1.72))
                if rel.y > 0.002:
                    u, v_uv = 0.05, 0.05
                loop[uv_layer].uv = (max(0.01, min(0.99, u)), max(0.01, min(0.99, v_uv)))

        bm.to_mesh(e_copy.data)
        bm.free()
        e_copy.data.materials.clear()
        e_copy.data.materials.append(eye_mat)
        e_copy.data.update()
        out_eyes.append(e_copy)

    bpy.data.objects.remove(eyes_obj, do_unlink=True)
    return out_eyes[0], out_eyes[1], eye_alb_path


def _build_anime_eyelashes(lash_obj: bpy.types.Object) -> Tuple[bpy.types.Object, Path]:
    """Style MPFB2 eyelashes01 as crisp dark plum-black anime upper/outer eyelashes."""
    lash_alb_path = TEX_DIR / "ghost_girl_lash_albedo.png"
    sz = 512
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)
    # Dense bold anime upper lash band + delicate tapered wing tips
    strand = np.power(0.5 + 0.5 * np.sin(xx * math.pi * 42.0), 1.6)
    base_solid = np.clip((0.52 - yy) / 0.12, 0.0, 1.0)
    taper = np.clip(1.0 - yy * 0.88, 0.0, 1.0)
    alpha = np.clip(np.maximum(base_solid, (strand * 0.85 + 0.15) * taper) * np.sin(xx * math.pi) ** 0.30, 0.0, 1.0)
    rgba = np.zeros((sz, sz, 4), dtype=np.float32)
    rgba[:, :, 0] = 0.095
    rgba[:, :, 1] = 0.072
    rgba[:, :, 2] = 0.145
    rgba[:, :, 3] = alpha
    _save_image(lash_alb_path, rgba)

    lash_mat = _make_pbr_material(
        "M_ghost_girl_eyelashes",
        albedo_path=lash_alb_path,
        roughness=0.55,
        alpha_mode="CLIP",
        alpha_threshold=0.35,
        double_sided=True,
    )
    lash_obj.name = "GhostGirl_Eyelashes"
    lash_obj.data.name = "GhostGirl_Eyelashes"
    # Remove MPFB2 lower eyelashes AND any detached small outer triangles (<12 verts) -> zero floating >/< islands!
    bm_l = bmesh.new()
    bm_l.from_mesh(lash_obj.data)
    all_l_z = [v.co.z for v in bm_l.verts]
    mid_l_z = (0.5 * (min(all_l_z) + max(all_l_z))) if all_l_z else 1.44
    del_lower = [f for f in bm_l.faces if f.calc_center_median().z < mid_l_z - 0.002]
    if del_lower and len(del_lower) < len(bm_l.faces):
        bmesh.ops.delete(bm_l, geom=del_lower, context="FACES")
        loose_l = [v for v in bm_l.verts if not v.link_faces]
        if loose_l:
            bmesh.ops.delete(bm_l, geom=loose_l, context="VERTS")

    # Prune isolated small connected islands (the floating outer corner wings)
    bm_l.verts.ensure_lookup_table()
    seen_l: set[int] = set()
    small_verts: List[bmesh.types.BMVert] = []
    for v in bm_l.verts:
        if v.index in seen_l:
            continue
        stack = [v]
        comp: List[bmesh.types.BMVert] = []
        while stack:
            cur = stack.pop()
            if cur.index in seen_l:
                continue
            seen_l.add(cur.index)
            comp.append(cur)
            for e in cur.link_edges:
                stack.append(e.other_vert(cur))
        if len(comp) < 12:
            small_verts.extend(comp)
    if small_verts:
        bmesh.ops.delete(bm_l, geom=small_verts, context="VERTS")

    for v in bm_l.verts:
        if v.co.y < -0.10:
            v.co.y -= 0.0014
    for f in bm_l.faces:
        f.smooth = True
    bm_l.to_mesh(lash_obj.data)
    bm_l.free()
    lash_obj.data.materials.clear()
    lash_obj.data.materials.append(lash_mat)
    lash_obj.data.update()
    return lash_obj, lash_alb_path


def _build_mouth_from_mpfb(
    teeth_obj: bpy.types.Object,
    tongue_obj: bpy.types.Object,
    lm: Dict[str, Vector],
) -> Tuple[bpy.types.Object, bpy.types.Object, bpy.types.Object]:
    """Split teeth into GhostGirl_Teeth_Upper/Lower and configure GhostGirl_Tongue."""
    mouth_alb = TEX_DIR / "ghost_girl_mouth_albedo.png"
    tongue_alb = TEX_DIR / "ghost_girl_tongue_albedo.png"

    mh_teeth_tex = Path(LocationService.get_user_data("teeth/teeth_base/teeth.png"))
    mh_tongue_tex = Path(LocationService.get_user_data("tongue/tongue01/tongue01_diffuse.png"))

    if mh_teeth_tex.exists():
        t_img = _load_image_rgb(mh_teeth_tex)
        is_enamel = (t_img[:, :, 0] - t_img[:, :, 1]) < 0.08
        t_img = np.where(is_enamel[:, :, None], np.clip(t_img * 1.48 + 0.14, 0.0, 0.99), np.clip(t_img * 1.25 + 0.08, 0.0, 0.95))
    else:
        t_img = np.full((512, 512, 3), (0.98, 0.97, 0.96), dtype=np.float32)
    _save_image(mouth_alb, t_img)

    if mh_tongue_tex.exists():
        tg_img = np.clip(_load_image_rgb(mh_tongue_tex) * np.array([1.35, 0.92, 1.05], dtype=np.float32) + np.array([0.22, 0.14, 0.18], dtype=np.float32), 0.0, 0.98)
    else:
        tg_img = np.full((512, 512, 3), (0.96, 0.56, 0.64), dtype=np.float32)
    _save_image(tongue_alb, tg_img)

    teeth_mat = _make_pbr_material("M_ghost_girl_mouth", albedo_path=mouth_alb, roughness=0.22)
    tongue_mat = _make_pbr_material("M_ghost_girl_tongue", albedo_path=tongue_alb, roughness=0.32)
    # Soft mouth-interior bounce fill so Cycles 16-sample renders keep teeth & pink tongue crisp inside Jaw Open
    for mat_i, em_s in ((teeth_mat, 0.30), (tongue_mat, 0.25)):
        bsdf_i = mat_i.node_tree.nodes.get("Principled BSDF")
        tex_nodes = [n for n in mat_i.node_tree.nodes if n.type == "TEX_IMAGE"]
        if bsdf_i and tex_nodes and "Emission Color" in bsdf_i.inputs:
            mat_i.node_tree.links.new(tex_nodes[0].outputs["Color"], bsdf_i.inputs["Emission Color"])
            bsdf_i.inputs["Emission Strength"].default_value = em_s

    # Position teeth & tongue cleanly inside oral cavity so Neutral lips cover them AND Jaw Open reveals bright upper/lower teeth & tongue
    mc = lm["mouth"]
    t_pts_all = [v.co for v in teeth_obj.data.vertices]
    t_min_y = min(p.y for p in t_pts_all)
    t_mid_z = 0.5 * (min(p.z for p in t_pts_all) + max(p.z for p in t_pts_all))
    anchor_y = mc.y + 0.0052
    dy_teeth = anchor_y - t_min_y
    dz_teeth = (mc.z - 0.0055) - t_mid_z
    for obj in (teeth_obj, tongue_obj):
        z_extra = 0.0065 if obj == tongue_obj else 0.0
        for v in obj.data.vertices:
            v.co.x *= 0.82
            v.co.y = anchor_y + ((v.co.y + dy_teeth) - anchor_y) * 0.80
            v.co.z += dz_teeth + z_extra
        obj.data.update()

    z_split = mc.z - 0.0065
    out_teeth: List[bpy.types.Object] = []
    for name, is_upper in (("GhostGirl_Teeth_Upper", True), ("GhostGirl_Teeth_Lower", False)):
        t_copy = teeth_obj.copy()
        t_copy.data = teeth_obj.data.copy()
        t_copy.name = name
        t_copy.data.name = name
        bpy.context.collection.objects.link(t_copy)

        bm = bmesh.new()
        bm.from_mesh(t_copy.data)
        del_faces = [
            f
            for f in bm.faces
            if (
                (f.calc_center_median().z < z_split or f.calc_center_median().z > z_split + 0.013)
                if is_upper
                else (f.calc_center_median().z >= z_split or f.calc_center_median().z < z_split - 0.011)
            )
        ]
        bmesh.ops.delete(bm, geom=del_faces, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        for f in bm.faces:
            f.smooth = True
        bm.to_mesh(t_copy.data)
        bm.free()
        t_copy.data.materials.clear()
        t_copy.data.materials.append(teeth_mat)
        t_copy.data.update()
        out_teeth.append(t_copy)

    bpy.data.objects.remove(teeth_obj, do_unlink=True)

    tongue_obj.name = "GhostGirl_Tongue"
    tongue_obj.data.name = "GhostGirl_Tongue"
    for p in tongue_obj.data.polygons:
        p.use_smooth = True
    tongue_obj.data.materials.clear()
    tongue_obj.data.materials.append(tongue_mat)
    tongue_obj.data.update()
    return out_teeth[0], out_teeth[1], tongue_obj


def _build_lavender_hair(
    bm_obj: bpy.types.Object,
    lm: Dict[str, Vector],
) -> Tuple[bpy.types.Object, bpy.types.Object, Path]:
    """Create GhostGirl_Hair_Cap + GhostGirl_Hair_Cards (lavender messy wavy chin-length bob + bangs)."""
    hair_alb_path = TEX_DIR / "ghost_girl_hair_albedo.png"
    hair_orm_path = TEX_DIR / "ghost_girl_hair_orm.png"
    cap_alb_path = TEX_DIR / "ghost_girl_hair_cap_albedo.png"

    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)
    s1 = np.sin(xx * math.pi * 54.0 + np.sin(yy * 5.0) * 0.6)
    s2 = np.sin(xx * math.pi * 128.0 + 1.2)
    strands = 0.54 + 0.24 * s1 + 0.14 * s2

    # Lavender-purple palette matching ref_front_back.jpg (#B4A0D8 mid, #7F69AD root, #D8CBFF shine)
    root_grad = 0.76 + 0.24 * np.power(yy, 0.55)
    # Soft horizontal anime specular band around yy ~ 0.34
    shine = np.exp(-0.5 * ((yy - 0.34) / 0.085) ** 2) * (0.4 + 0.6 * strands)
    r_ch = np.clip((0.705 + 0.07 * strands) * root_grad + 0.14 * shine, 0.0, 1.0)
    g_ch = np.clip((0.620 + 0.06 * strands) * root_grad + 0.14 * shine, 0.0, 1.0)
    b_ch = np.clip((0.865 + 0.06 * strands) * root_grad + 0.10 * shine, 0.0, 1.0)

    # Soft wispy multi-strand anime hair lock tips (eliminates sharp angular sawtooth triangle points in 90 deg side view!)
    spike_tip = 0.87 + 0.11 * np.sin(xx * math.pi) + 0.03 * strands
    tip_alpha = np.clip((spike_tip - yy) / 0.12, 0.0, 1.0)
    side_alpha = np.clip((np.sin(xx * math.pi) - 0.03) / 0.15, 0.0, 1.0)
    alpha = np.clip(tip_alpha * side_alpha, 0.0, 1.0)

    rgba = np.stack([r_ch, g_ch, b_ch, alpha], axis=2)
    _save_image(hair_alb_path, rgba)

    cap_rgb = np.stack([r_ch * 0.90, g_ch * 0.90, b_ch * 0.92], axis=2)
    _save_image(cap_alb_path, cap_rgb)

    hair_orm = np.zeros((sz, sz, 3), dtype=np.float32)
    hair_orm[:, :, 0] = np.clip(0.75 + 0.25 * yy, 0.0, 1.0)
    hair_orm[:, :, 1] = 0.44
    hair_orm[:, :, 2] = 0.0
    _save_image(hair_orm_path, hair_orm)

    cap_mat = _make_pbr_material(
        "M_ghost_girl_hair_cap",
        albedo_path=cap_alb_path,
        orm_path=hair_orm_path,
        roughness=0.48,
    )
    cards_mat = _make_pbr_material(
        "M_ghost_girl_hair",
        albedo_path=hair_alb_path,
        orm_path=hair_orm_path,
        roughness=0.42,
        alpha_mode="CLIP",
        alpha_threshold=0.40,
        double_sided=True,
    )

    body_verts = _vg_indices(bm_obj, ("body",))
    ear_vs = _vg_indices(bm_obj, ("ears",))
    verts = bm_obj.data.vertices

    # 1. GhostGirl_Hair_Cap: snug lavender skull cap inside the ghost hood
    cap_mesh = bpy.data.meshes.new("GhostGirl_Hair_Cap")
    bm_cap = bmesh.new()
    bm_cap.from_mesh(bm_obj.data)
    hc = lm["head_center"]
    z_brow = lm["left_eye"].z + 0.022
    z_ear = lm["ear_y"].z
    keep_v = {
        i
        for i in body_verts
        if (i not in ear_vs)
        and ((verts[i].co.z > z_brow + 0.036) or (verts[i].co.y > lm["ear_y"].y + 0.015 and verts[i].co.z > z_ear - 0.016))
    }
    del_f = [f for f in bm_cap.faces if not all(v.index in keep_v for v in f.verts)]
    bmesh.ops.delete(bm_cap, geom=del_f, context="FACES")
    loose = [v for v in bm_cap.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm_cap, geom=loose, context="VERTS")
    uv_cap = bm_cap.loops.layers.uv.verify()
    for v in bm_cap.verts:
        d = (v.co - hc).normalized()
        v.co += d * 0.0035
    for f in bm_cap.faces:
        f.smooth = True
        for loop in f.loops:
            co = loop.vert.co
            u = 0.5 + (co.x / 0.20)
            v_uv = 0.5 + ((co.y - hc.y) / 0.22)
            loop[uv_cap].uv = (max(0.01, min(0.99, u)), max(0.01, min(0.99, v_uv)))
    bm_cap.to_mesh(cap_mesh)
    bm_cap.free()
    cap_mesh.materials.append(cap_mat)
    cap_obj = bpy.data.objects.new("GhostGirl_Hair_Cap", cap_mesh)
    bpy.context.collection.objects.link(cap_obj)

    # 2. GhostGirl_Hair_Cards: messy chin-length wavy bob + center-parted choppy bangs + side locks
    #    Strictly stays inside the hood dome so hair never clips out the top/back of the hood,
    #    while emerging below the hood's jagged back hem and framing the face cleanly!
    cards_mesh = bpy.data.meshes.new("GhostGirl_Hair_Cards")
    bm_cards = bmesh.new()
    uv_layer = bm_cards.loops.layers.uv.verify()

    z_crown = max(verts[i].co.z for i in body_verts) + 0.004
    z_chin = lm["chin"].z
    z_eye = lm["left_eye"].z
    dome_cz = z_eye + 0.022
    ear_max_x = lm["ear_y"].x
    dome_rx = max(0.092, ear_max_x + 0.006)
    dome_ry = max(0.112, 0.5 * (lm["head_y_max"].y - lm["head_y_min"].y) + 0.003)
    dome_rz = max(z_crown - dome_cz, 0.094)

    forehead_min_y = min(
        (verts[i].co.y for i in body_verts if verts[i].co.z > z_eye + 0.014 and abs(verts[i].co.x) < 0.065),
        default=lm["head_y_min"].y + 0.012,
    )

    def add_hair_ribbon(pts: List[Vector], w_root: float, w_tip: float, tilt: float = 0.0) -> None:
        n = len(pts)
        prev_l = prev_m = prev_r = None
        for i, p in enumerate(pts):
            t = i / float(n - 1)
            tang = (pts[1] - pts[0]) if i == 0 else ((pts[-1] - pts[-2]) if i == n - 1 else (pts[i + 1] - pts[i - 1]))
            tang.normalize()
            rad = p - Vector((0.0, hc.y, dome_cz))
            if rad.length < 1e-4:
                rad = Vector((0.0, -1.0, 0.0))
            rad.normalize()
            side = tang.cross(rad).normalized()
            if abs(tilt) > 1e-4:
                side = (side * math.cos(tilt) + rad * math.sin(tilt)).normalized()
            taper_w = 1.0 - 0.42 * (t ** 1.50)
            w = w_root * taper_w + w_tip * (1.0 - taper_w)
            # Soft rounded 3-vertex anime hair ribbon (crown arch eliminates flat polygonal facet look)
            crown_lift = rad * (0.0030 * (1.0 - 0.65 * t))
            vl = bm_cards.verts.new(p - side * (0.5 * w))
            vm = bm_cards.verts.new(p + crown_lift)
            vr = bm_cards.verts.new(p + side * (0.5 * w))
            if prev_l is not None:
                v0 = 1.0 - (i - 1) / float(n - 1)
                v1 = 1.0 - t
                fl = bm_cards.faces.new((prev_l, prev_m, vm, vl))
                fr = bm_cards.faces.new((prev_m, prev_r, vr, vm))
                for f, u_a, u_b in ((fl, 0.0, 0.5), (fr, 0.5, 1.0)):
                    f.smooth = True
                    f.loops[0][uv_layer].uv = (u_a, v0)
                    f.loops[1][uv_layer].uv = (u_b, v0)
                    f.loops[2][uv_layer].uv = (u_b, v1)
                    f.loops[3][uv_layer].uv = (u_a, v1)
            prev_l, prev_m, prev_r = vl, vm, vr

    # Back & side messy wavy bob (emerging richly below jagged back hood hem down to nape/chin)
    eye_plane_y = lm["left_eye"].y + 0.026
    for n_cards, r_off, w_root, w_tip, phase, len_var in (
        (52, 0.005, 0.030, 0.008, 0.00, 0.000),
        (58, 0.011, 0.026, 0.006, 0.04, 0.010),
    ):
        for k in range(n_cards):
            az = (k / float(n_cards)) * math.tau + phase
            front_ang = min(az, math.tau - az)
            if front_ang < 1.05:
                continue
            is_side = front_ang < 1.55
            z_end = (z_chin - 0.018) if is_side else (z_chin - 0.036)
            z_end += 0.014 * math.sin(k * 3.1) + len_var
            pts: List[Vector] = []
            steps = 18
            for s in range(steps):
                t = s / float(steps - 1)
                if t <= 0.42:
                    phi = 0.08 + (t / 0.42) * (math.pi * 0.46)
                    rx = (dome_rx + r_off) * math.sin(phi)
                    ry = (dome_ry + r_off) * math.sin(phi)
                    pz = dome_cz + (dome_rz + r_off * 0.55) * math.cos(phi)
                else:
                    u_low = (t - 0.42) / 0.58
                    # Messy wavy S-curve + outward kick at bob tips (visible below hood!)
                    wave = math.sin(u_low * math.pi * 2.4 + k * 1.1) * 0.008
                    tip_flare = 0.018 * (u_low ** 2.0) if not is_side else (-0.010 * (u_low ** 1.6))
                    rx = dome_rx + r_off + wave + tip_flare
                    ry = dome_ry + r_off + wave * 0.6 + (0.020 * (u_low ** 1.9) if not is_side else -0.006 * u_low)
                    pz = dome_cz * (1.0 - u_low) + z_end * u_low
                px = math.sin(az) * rx
                py = hc.y - math.cos(az) * ry
                if is_side and t > 0.18 and pz < z_eye + 0.048:
                    py = max(py, eye_plane_y)
                if (z_ear - 0.025) <= pz <= (z_ear + 0.030) and abs(py - lm["ear_y"].y) < 0.030:
                    min_ear_rx = ear_max_x + 0.007 + r_off * 0.4
                    if abs(px) < min_ear_rx:
                        px = (1.0 if px >= 0.0 else -1.0) * min_ear_rx
                pts.append(Vector((px, py, pz)))
            add_hair_ribbon(pts, w_root, w_tip, tilt=0.14 * math.sin(k * 2.3))

    # Face-framing messy wavy side locks (swept smoothly behind lateral eye/lash corner so 90 deg side profile reads sharply!)
    for sx in (-1.0, 1.0):
        for li, (ang_off, z_drop, wave_ph) in enumerate((
            (1.16, -0.024, 0.0),
            (1.26, -0.018, 1.3),
            (1.36, -0.012, 2.5),
            (1.48, -0.022, 0.7),
        )):
            az = sx * ang_off
            z_end = z_chin + z_drop
            pts = []
            for s in range(16):
                t = s / 15.0
                phi = 0.14 + t * (math.pi * 0.46)
                if t <= 0.48:
                    rx = (dome_rx + 0.004) * math.sin(phi)
                    ry = (dome_ry + 0.004) * math.sin(phi)
                    pz = dome_cz + (dome_rz + 0.003) * math.cos(phi)
                else:
                    u_l = (t - 0.48) / 0.52
                    wave = 0.007 * math.sin(u_l * math.pi * 2.2 + wave_ph)
                    rx = (dome_rx + 0.004) * (1.0 - 0.16 * u_l) + wave
                    ry = (dome_ry + 0.004) * (1.0 - 0.10 * u_l) + wave * 0.4
                    pz = dome_cz * (1.0 - u_l) + z_end * u_l
                px = math.sin(az) * rx
                py = hc.y - math.cos(az) * ry
                if t > 0.20 and pz < z_eye + 0.048:
                    py = max(py, eye_plane_y)
                pts.append(Vector((px, py, pz)))
            add_hair_ribbon(pts, 0.024, 0.009, tilt=0.08 * sx)

    # Center-parted choppy bangs (lifted cleanly above eyebrows at z_eye + 0.0325 so brows read crisply!)
    for n_b, r_off, z_off in ((16, 0.003, -0.001), (10, 0.007, 0.003)):
        for k in range(n_b):
            u = (k / float(n_b - 1)) * 2.0 - 1.0
            part_push = (0.12 if u >= 0.0 else -0.12) * math.exp(-abs(u) * 5.0)
            az = (u * 0.46) + part_push
            choppy = 0.004 * math.sin(k * 3.7)
            # Clear eyebrow arch across central forehead; swoop lower gently at outer temple corners
            z_tip = z_eye + 0.0325 - 0.004 * (u * u) + z_off + choppy
            pts = []
            for s in range(14):
                t = s / 13.0
                phi = 0.12 + t * (math.pi * 0.44)
                rx = (dome_rx + r_off) * math.sin(phi)
                ry = (dome_ry + r_off) * math.sin(phi)
                pz_d = dome_cz + (dome_rz + r_off * 0.40) * math.cos(phi)
                pz = pz_d * (1.0 - t * 0.45) + (z_crown * (1.0 - t) + z_tip * t) * (t * 0.45)
                if t > 0.55:
                    u_b = (t - 0.55) / 0.45
                    pz = pz * (1.0 - u_b) + z_tip * u_b
                px = math.sin(az) * rx
                py = hc.y - math.cos(az) * ry
                if t > 0.25:
                    max_y = forehead_min_y + 0.016 * (u * u) - 0.002 - r_off * 0.25
                    py = min(py, max_y)
                pts.append(Vector((px, py, pz)))
            add_hair_ribbon(pts, 0.022, 0.003, tilt=0.05 * u)

    bm_cards.to_mesh(cards_mesh)
    bm_cards.free()
    cards_mesh.materials.append(cards_mat)
    cards_obj = bpy.data.objects.new("GhostGirl_Hair_Cards", cards_mesh)
    bpy.context.collection.objects.link(cards_obj)
    return cap_obj, cards_obj, hair_alb_path


# ---------------------------------------------------------------------------
# Step 4: Ghost Girl Outfit Meshes (Hood + Clips, Cape, CropTop, Skirt, Gloves, Boots)
# ---------------------------------------------------------------------------

def _paint_hood_textures() -> Tuple[Path, Path]:
    """Paint 1024x1024 atlas for GhostGirl_Hood (white hood + ghost eyes, bat clips, pumpkin clip)."""
    alb_p = TEX_DIR / "ghost_girl_hood_albedo.png"
    orm_p = TEX_DIR / "ghost_girl_hood_orm.png"
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)

    # Quadrant layout in Blender bottom-up UV space (top-down row yy = 1 - v_uv):
    # - Left half (xx < 0.72): White ghost hood cloth (lit outer, cool lavender inner lining at xx in [0.52, 0.72])
    # - Top-right (xx >= 0.72, yy < 0.50): Black bat wing clips (#1E1A26)
    # - Bottom-right (xx >= 0.72, yy >= 0.50): Smiling orange jack-o'-lantern pumpkin clip (#F27A22)
    alb = np.zeros((sz, sz, 3), dtype=np.float32)
    # Outer white ghost cloth (#F5F6FC) with soft vertical fold shading
    fold = 0.025 * np.sin(xx * math.pi * 16.0) * yy
    alb[:, :, 0] = 0.960 - fold * 1.1
    alb[:, :, 1] = 0.964 - fold * 1.0
    alb[:, :, 2] = 0.985 - fold * 0.4

    # Inner hood lining strip (xx in [0.52, 0.72]): clean pale white-lavender sheet underside
    inner_m = (xx >= 0.52) & (xx < 0.72)
    alb[inner_m] = np.array([0.925, 0.930, 0.968], dtype=np.float32)

    # 2 Black ghost-eye ovals painted on front-top hood region (xx centered at 0.21 & 0.31, yy ~ 0.25)
    for cx_e, tilt_e in ((0.205, 0.08), (0.315, -0.08)):
        dx = xx - cx_e
        dy = yy - 0.265
        rx = dx * math.cos(tilt_e) - dy * math.sin(tilt_e)
        ry = dx * math.sin(tilt_e) + dy * math.cos(tilt_e)
        d_eye = np.sqrt((rx / 0.026) ** 2 + (ry / 0.036) ** 2)
        w_e = np.clip((1.0 - d_eye) / 0.06, 0.0, 1.0)[:, :, None]
        eye_col = np.array([0.115, 0.105, 0.145], dtype=np.float32)
        alb = alb * (1.0 - w_e) + eye_col[None, None, :] * w_e

    # Bat clip region (xx >= 0.72, yy < 0.50)
    bat_m = (xx >= 0.72) & (yy < 0.50)
    alb[bat_m] = np.array([0.115, 0.100, 0.150], dtype=np.float32)

    # Pumpkin clip region (xx >= 0.72, yy >= 0.50)
    pump_m = (xx >= 0.72) & (yy >= 0.50)
    # Local coords inside pumpkin front face UV patch: u_p in [0, 1], v_p in [0, 1]
    u_p = (xx - 0.72) / 0.28
    v_p = (yy - 0.50) / 0.50
    rib = 0.055 * np.sin(u_p * math.pi * 6.0)
    p_orange = np.stack([
        np.clip(0.955 - 0.08 * rib, 0.0, 1.0),
        np.clip(0.470 - 0.07 * rib, 0.0, 1.0),
        np.clip(0.115 - 0.03 * rib, 0.0, 1.0),
    ], axis=2)
    alb = np.where(pump_m[:, :, None], p_orange, alb)

    # Green stem at top band of pumpkin UV (v_p < 0.18)
    stem_m = pump_m & (v_p < 0.18)
    alb[stem_m] = np.array([0.235, 0.365, 0.185], dtype=np.float32)

    # Dark smiling jack-o'-lantern eyes & jagged mouth on front pumpkin face (u_p in [0.15, 0.85], v_p in [0.25, 0.88])
    dark_face = np.array([0.110, 0.085, 0.105], dtype=np.float32)
    tri_l = (np.abs(u_p - 0.36) < 0.085 * np.clip((v_p - 0.34) / 0.14, 0.0, 1.0)) & (v_p >= 0.34) & (v_p <= 0.48)
    tri_r = (np.abs(u_p - 0.64) < 0.085 * np.clip((v_p - 0.34) / 0.14, 0.0, 1.0)) & (v_p >= 0.34) & (v_p <= 0.48)
    smile_curve = 0.72 - 0.16 * ((u_p - 0.50) / 0.28) ** 2
    tooth = 0.032 * np.sin(u_p * 34.0)
    mouth_m = pump_m & (np.abs(u_p - 0.50) < 0.25) & (v_p >= smile_curve - 0.07 + tooth) & (v_p <= smile_curve + 0.04)
    face_m = pump_m & (tri_l | tri_r | mouth_m)
    alb[face_m] = dark_face

    _save_image(alb_p, alb)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = np.where(bat_m | pump_m, 0.48, 0.78)
    orm[:, :, 2] = 0.0
    _save_image(orm_p, orm)
    return alb_p, orm_p


def _build_ghost_hood(bm_obj: bpy.types.Object, lm: Dict[str, Vector]) -> Tuple[bpy.types.Object, Path]:
    """Build white ghost hood (GhostGirl_Hood) with 2 black ghost eyes, left fold, bat clips, and pumpkin clip."""
    alb_p, orm_p = _paint_hood_textures()
    hood_mat = _make_pbr_material(
        "M_ghost_girl_hood",
        albedo_path=alb_p,
        orm_path=orm_p,
        roughness=0.76,
        double_sided=True,
    )

    body_vs = _vg_indices(bm_obj, ("body",))
    verts = bm_obj.data.vertices
    z_crown = max(verts[i].co.z for i in body_vs)
    hc = lm["head_center"]
    z_eye = lm["left_eye"].z
    z_chin = lm["chin"].z

    # Hood dome center & clean open-face clearance around hair & face
    cz = z_eye + 0.022
    rx_base = max(0.118, lm["ear_y"].x + 0.032)
    ry_base = max(0.122, 0.5 * (lm["head_y_max"].y - lm["head_y_min"].y) + 0.020)
    rz_base = max(z_crown - cz + 0.028, 0.130)
    cy = hc.y + 0.010

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()

    n_rings = 16
    n_seg = 48
    crown_apex = Vector((0.0, cy - 0.012, z_crown + 0.034))

    def hood_ring_pt(ring_t: float, seg_u: float) -> Vector:
        az = seg_u * math.tau  # 0 = front (-Y), pi/2 = left (+X), pi = back (+Y), 3pi/2 = right (-X)
        cos_a = math.cos(az)
        sin_a = math.sin(az)
        front_w = max(0.0, cos_a)
        back_w = max(0.0, -cos_a)

        # Wide open front arch above bangs; jagged scalloped back hem at occiput/nape exposing wavy lavender back hair!
        jagged = -0.024 * (abs(math.sin(az * 6.5)) ** 1.2) * (1.0 - 0.90 * (front_w ** 1.5))
        z_back_hem = lm["ear_y"].z - 0.015
        edge_z = (
            (z_crown - 0.010) * (front_w ** 1.4)
            + z_back_hem * (1.0 - front_w ** 1.4)
            + jagged
        )
        edge_rx = 0.098 * front_w + (rx_base + 0.014) * (1.0 - front_w)
        edge_y_front = lm["head_y_min"].y + 0.012
        edge_y_side = cy - 0.006
        edge_y_back = cy + ry_base + 0.024

        if cos_a >= 0.0:
            edge_y = edge_y_front * (front_w ** 1.6) + edge_y_side * (1.0 - front_w ** 1.6)
        else:
            edge_y = edge_y_back * (back_w ** 1.2) + edge_y_side * (1.0 - back_w ** 1.2)
        edge_x = sin_a * edge_rx

        # Smooth dome arc from crown_apex (ring_t=0) to open rim/hem (ring_t=1)
        phi = ring_t * (math.pi * 0.50)
        h_drop = 1.0 - math.cos(phi)
        r_ease = math.sin(phi)

        # Gentle rounded hood contour (clears back hair cleanly with zero hair poke-through!)
        side_puff = 1.0 + 0.08 * math.sin(ring_t * math.pi) * (1.0 - 0.65 * front_w)
        px = edge_x * r_ease * side_puff
        py = crown_apex.y + (edge_y - crown_apex.y) * r_ease * (1.0 + 0.14 * math.sin(ring_t * math.pi) * back_w)
        pz = crown_apex.z + (edge_z - crown_apex.z) * h_drop + 0.012 * math.sin(ring_t * math.pi) * back_w

        # Soft folded cloth sheet-ear drape on LEFT (+X) temple/side (no spiky crown dorsal fin in 90° profile!)
        ear_fold = math.exp(-0.5 * (((az - 1.60) / 0.36) ** 2 + ((ring_t - 0.48) / 0.24) ** 2))
        px += 0.032 * ear_fold
        py += 0.004 * ear_fold
        pz += 0.005 * ear_fold

        return Vector((px, py, pz))

    apex_v = bm.verts.new(crown_apex)
    rings: List[List[bmesh.types.BMVert]] = []
    for ri in range(1, n_rings + 1):
        rt = ri / float(n_rings)
        ring: List[bmesh.types.BMVert] = []
        for si in range(n_seg):
            su = si / float(n_seg)
            ring.append(bm.verts.new(hood_ring_pt(rt, su)))
        rings.append(ring)

    # Inner shadow lining ring curled cleanly inward around the open rim & bottom hem
    inner_ring: List[bmesh.types.BMVert] = []
    for ov in rings[-1]:
        in_dir = Vector((0.0, cy, cz)) - ov.co
        in_dir.z *= 0.25
        in_dir.normalize()
        inner_ring.append(bm.verts.new(ov.co + in_dir * 0.007 + Vector((0.0, 0.005, 0.002))))
    inner_deep: List[bmesh.types.BMVert] = []
    for ov in inner_ring:
        in_dir = Vector((0.0, cy, cz)) - ov.co
        in_dir.z *= 0.15
        in_dir.normalize()
        inner_deep.append(bm.verts.new(ov.co + in_dir * 0.012 + Vector((0.0, 0.012, 0.004))))

    def map_hood_uv(p: Vector, is_inner: bool = False) -> Tuple[float, float]:
        if is_inner:
            return (0.62, 0.50)
        # Map front-top crown slope onto ghost-eye region [0.05..0.48, 0.52..0.96]
        # Ghost eye centers are at u=0.205 & 0.315 (dx = ±0.055), v_uv = 0.735 (yy = 0.265)
        if p.y > crown_apex.y + 0.005 or p.z < z_crown - 0.015:
            return (0.10, 0.15)
        u = 0.26 + (p.x * 2.35)
        # Map z from [z_crown - 0.010 .. crown_apex.z] onto [0.55 .. 0.92]
        v_top = (p.z - (z_crown - 0.010)) / max(crown_apex.z - (z_crown - 0.010), 1e-4)
        v_uv = 0.54 + 0.38 * max(0.0, min(1.0, v_top))
        return (max(0.02, min(0.50, u)), max(0.02, min(0.98, v_uv)))

    # Apex fan
    for si in range(n_seg):
        sn = (si + 1) % n_seg
        f = bm.faces.new((apex_v, rings[0][si], rings[0][sn]))
        f.smooth = True
        for loop in f.loops:
            loop[uv_layer].uv = map_hood_uv(loop.vert.co)

    # Outer rings
    for ri in range(len(rings) - 1):
        for si in range(n_seg):
            sn = (si + 1) % n_seg
            f = bm.faces.new((rings[ri][si], rings[ri + 1][si], rings[ri + 1][sn], rings[ri][sn]))
            f.smooth = True
            for loop in f.loops:
                loop[uv_layer].uv = map_hood_uv(loop.vert.co)

    # Rolled inner lining rings
    for r0, r1 in ((rings[-1], inner_ring), (inner_ring, inner_deep)):
        for si in range(n_seg):
            sn = (si + 1) % n_seg
            f = bm.faces.new((r0[si], r1[si], r1[sn], r0[sn]))
            f.smooth = True
            for loop in f.loops:
                loop[uv_layer].uv = map_hood_uv(loop.vert.co, is_inner=True)

    # Bat wing clips seated snugly ON TOP OF front bangs (visible, flush, never buried inside bangs!)
    forehead_y0 = min(
        (verts[i].co.y for i in body_vs if verts[i].co.z > z_eye + 0.018 and abs(verts[i].co.x) < 0.05),
        default=lm["head_y_min"].y + 0.010,
    )
    for sx in (-1.0, 1.0):
        bx = sx * 0.038
        # Seat cleanly right on curved outer bang layer (y = forehead_y0 - 0.0055)
        by = forehead_y0 - 0.0055
        bz = z_eye + 0.041
        bat_pts = [
            Vector((0.0, 0.0, 0.0045)),
            Vector((sx * 0.0045, 0.0, 0.0095)),
            Vector((sx * 0.010, 0.0, 0.005)),
            Vector((sx * 0.020, 0.004, 0.007)),
            Vector((sx * 0.016, 0.003, -0.0035)),
            Vector((sx * 0.008, 0.0015, -0.0025)),
            Vector((0.0, 0.0, -0.006)),
            Vector((-sx * 0.008, 0.0015, -0.0025)),
            Vector((-sx * 0.016, 0.003, -0.0035)),
            Vector((-sx * 0.020, 0.004, 0.007)),
            Vector((-sx * 0.010, 0.0, 0.005)),
            Vector((-sx * 0.0045, 0.0, 0.0095)),
        ]
        rot_b = Matrix.Rotation(sx * 0.28, 3, "Z") @ Matrix.Rotation(-0.16, 3, "X")
        bat_center = Vector((bx, by, bz))
        front_vs = [bm.verts.new(bat_center + rot_b @ (pt + Vector((0.0, -0.0022, 0.0)))) for pt in bat_pts]
        back_vs = [bm.verts.new(bat_center + rot_b @ (pt + Vector((0.0, 0.0022, 0.0)))) for pt in bat_pts]
        c_f = bm.verts.new(bat_center + rot_b @ Vector((0.0, -0.0026, 0.0)))
        c_b = bm.verts.new(bat_center + rot_b @ Vector((0.0, 0.0026, 0.0)))
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

    # Smiling orange jack-o'-lantern pumpkin clip clearly separated at her LEFT temple (+X, viewer's right!)
    px_c = 0.068
    py_c = forehead_y0 + 0.008
    pz_c = z_eye + 0.060
    p_center = Vector((px_c, py_c, pz_c))
    rot_p = Matrix.Rotation(0.52, 3, "Z") @ Matrix.Rotation(-0.14, 3, "X")

    ret_p = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.0155)
    for v in ret_p["verts"]:
        # Ribbed slightly squashed pumpkin silhouette
        ang_p = math.atan2(v.co.y, v.co.x)
        rib = 1.0 + 0.09 * math.cos(ang_p * 7.0)
        lp = Vector((v.co.x * rib * 1.12, v.co.y * rib * 0.62, v.co.z * 0.90))
        v.co = p_center + rot_p @ lp
    for f in {f for v in ret_p["verts"] for f in v.link_faces}:
        f.smooth = True
        for loop in f.loops:
            # Map pumpkin front face (-Y in local space) onto lower-right UV quadrant [0.72..1.0, 0.0..0.50]
            local_p = rot_p.inverted() @ (loop.vert.co - p_center)
            u = 0.86 + (local_p.x / 0.032) * 0.12
            # In Blender bottom-up UV, top of pumpkin (z > 0) -> v=0.40 (yy=0.60), bottom -> v=0.06 (yy=0.94)
            v_uv = 0.22 + (local_p.z / 0.026) * 0.22
            if local_p.y > 0.002:
                # Back of pumpkin gets pure orange (below stem band)
                u, v_uv = 0.78, 0.10
            loop[uv_layer].uv = (max(0.73, min(0.99, u)), max(0.01, min(0.41, v_uv)))

    # Pumpkin green stem at top
    ret_st = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.0032, radius2=0.0018, depth=0.008
    )
    for v in ret_st["verts"]:
        lp = Vector((v.co.x, v.co.y, v.co.z + 0.013))
        v.co = p_center + rot_p @ lp
    for f in {f for v in ret_st["verts"] for f in v.link_faces}:
        f.smooth = True
        for loop in f.loops:
            loop[uv_layer].uv = (0.86, 0.46)  # yy=0.54 -> green stem band in pump_m!

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    hood_mesh = bpy.data.meshes.new("GhostGirl_Hood")
    bm.to_mesh(hood_mesh)
    bm.free()
    hood_mesh.materials.append(hood_mat)
    hood_obj = bpy.data.objects.new("GhostGirl_Hood", hood_mesh)
    bpy.context.collection.objects.link(hood_obj)
    return hood_obj, alb_p


def _paint_cape_texture() -> Tuple[Path, Path]:
    """Paint 1024x1024 semi-translucent white tattered ghost cape with crisp oval/teardrop holes."""
    alb_p = TEX_DIR / "ghost_girl_cape_albedo.png"
    orm_p = TEX_DIR / "ghost_girl_cape_orm.png"
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)
    # In Blender UV: v_uv = 1 - yy, so v_uv=1.0 is top shoulder ridge (yy=0), v_uv=0.0 is bottom ragged hem (yy=1)
    # Ghost white cloth (#F7F8FD) shading softly to pale lavender-grey (#D7DAF0) toward folds & ragged hem
    fold = 0.5 + 0.5 * np.sin(xx * math.pi * 18.0)
    shade = 0.14 * yy + 0.06 * fold * (0.3 + 0.7 * yy)
    r = 0.972 - shade * 1.15
    g = 0.975 - shade * 1.05
    b = 0.996 - shade * 0.40

    # Smooth clean semi-translucent alpha (~0.86 so crop top & skirt show softly without noisy Cycles dither)
    alpha = 0.88 - 0.06 * yy

    # Crisp oval / teardrop ghost holes near lower wings & back skirt/calf drape (yy in [0.56, 0.88])
    holes = (
        (0.14, 0.70, 0.018, 0.036, 0.18),
        (0.21, 0.78, 0.015, 0.030, -0.10),
        (0.32, 0.72, 0.017, 0.034, 0.12),
        (0.45, 0.76, 0.020, 0.038, -0.05),
        (0.55, 0.73, 0.018, 0.035, 0.08),
        (0.67, 0.77, 0.017, 0.034, -0.15),
        (0.79, 0.71, 0.016, 0.032, 0.14),
        (0.86, 0.78, 0.019, 0.036, -0.12),
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

    # Ragged bottom hem cutout for crisp extra tattered points
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


def _build_ghost_cape(
    body_obj: bpy.types.Object,
    alb_p: Path,
    orm_p: Path,
    is_tpose: bool,
) -> bpy.types.Object:
    """Build semi-translucent tattered white ghost cape (GhostGirl_Cape) for A-pose or T-pose."""
    cape_mat = _make_pbr_material(
        "M_ghost_girl_cape",
        albedo_path=alb_p,
        orm_path=orm_p,
        roughness=0.82,
        alpha_mode="BLEND",
        double_sided=True,
    )

    body_vs = _vg_indices(body_obj, ("body",))
    if not body_vs:
        body_vs = set(range(len(body_obj.data.vertices)))
    verts = [body_obj.data.vertices[i].co for i in body_vs]
    z_min = min(v.z for v in verts)
    z_max = max(v.z for v in verts)
    h = z_max - z_min

    # Measure arm ridge curve from collar/shoulder -> elbow -> wrist on Left (+X) and Right (-X)
    # In canonical A-pose arms slope downward; in T-pose arms extend horizontally!
    arm_pts_r: List[Vector] = []
    arm_pts_l: List[Vector] = []
    max_arm_x = max(abs(v.x) for v in verts if v.z > z_min + 0.45 * h)
    x_wrist_span = max_arm_x - 0.14  # stops cleanly near wrist/glove cuff

    def sample_arm_cross(x_pos: float) -> Tuple[float, float, float, float]:
        # Measure arm/shoulder cross-section (cy, cz, ry_arm, rz_arm), excluding bust/ribcage below underarm
        z_floor = (z_min + 0.695 * h) if abs(x_pos) <= 0.18 else (z_min + 0.50 * h)
        band = [v for v in verts if abs(v.x - x_pos) < 0.032 and z_floor < v.z < (z_min + 0.840 * h)]
        if not band:
            band = [v for v in verts if abs(v.x - x_pos) < 0.055 and z_floor < v.z < (z_min + 0.840 * h)]
        if not band:
            return 0.005, z_min + 0.755 * h, 0.055, 0.045
        y_f = min(v.y for v in band)
        y_b = max(v.y for v in band)
        z_t = max(v.z for v in band)
        z_b = min(v.z for v in band)
        return (
            0.5 * (y_f + y_b),
            0.5 * (z_t + z_b),
            max(0.032, 0.5 * (y_b - y_f)),
            max(0.030, 0.5 * (z_t - z_b)),
        )

    # Build continuous ghost cape mantle draping OVER shoulders/upper arms/elbows and long to mid-calf behind!
    n_u = 52
    n_v = 20

    neck_band = [v for v in verts if (z_min + 0.78 * h) <= v.z <= (z_min + 0.835 * h) and abs(v.x) < 0.08]
    y_neck_b = max((v.y for v in neck_band), default=0.07) + 0.036
    z_neck_c = z_min + 0.818 * h
    y_back_skirt = max((v.y for v in verts if (z_min + 0.42 * h) <= v.z <= (z_min + 0.62 * h) and abs(v.x) < 0.16), default=0.11)

    sh_r = sample_arm_cross(-0.118)
    sh_l = sample_arm_cross(0.118)
    sh_cy = 0.5 * (sh_r[0] + sh_l[0])
    sh_cz = 0.5 * (sh_r[1] + sh_l[1])
    sh_ry = max(sh_r[2], sh_l[2]) + 0.030
    sh_rz = max(sh_r[3], sh_l[3]) + 0.026

    # Column specs: (px, cy, cz, ry, rz, phi_front, neck_blend)
    col_specs: List[Tuple[float, float, float, float, float, float, float]] = []
    for ui in range(n_u):
        u = ui / float(n_u - 1)
        if u < 0.34:
            # Right wrist (-x_wrist_span) -> Right inner shoulder (-0.118)
            t_arm = u / 0.34
            x = -x_wrist_span * (1.0 - t_arm) - 0.118 * t_arm
            cy, cz, ry_a, rz_a = sample_arm_cross(x)
            sh_boost = _smoothstep(0.55, 0.90, t_arm)
            ry = ry_a + 0.022 + 0.008 * sh_boost
            rz = rz_a + 0.020 + 0.006 * sh_boost
            w_cov = _smoothstep(0.12, 0.48, t_arm)
            w_in = _smoothstep(0.84, 1.0, t_arm)
            # Cover front-upper curve of deltoid & upper arm smoothly (+0.04*pi..+0.12*pi), opening toward wrist
            phi_f = ((0.32 * (1.0 - w_cov) + 0.04 * w_cov) * (1.0 - w_in) + 0.12 * w_in) * math.pi
            col_specs.append((x, cy, cz, ry, rz, phi_f, 0.0))
        elif u <= 0.66:
            # Smooth collar arc behind neck blending seamlessly into both shoulder outer-ellipses
            t_col = (u - 0.34) / 0.32
            px = -0.118 * math.cos(t_col * math.pi)
            s_m = math.sin(t_col * math.pi) ** 1.15
            cy_s, cz_s, ry_s, rz_s = sample_arm_cross(px if abs(px) >= 0.09 else (-0.118 if px < 0 else 0.118))
            ry_s = max(ry_s + 0.030, sh_ry) * (1.0 - 0.5 * s_m) + sh_ry * (0.5 * s_m)
            rz_s = max(rz_s + 0.026, sh_rz) * (1.0 - 0.5 * s_m) + sh_rz * (0.5 * s_m)
            col_specs.append((px, cy_s * (1.0 - s_m) + sh_cy * s_m, cz_s * (1.0 - s_m) + sh_cz * s_m, ry_s, rz_s, 0.12 * math.pi, s_m))
        else:
            # Left inner shoulder (+0.118) -> Left wrist (+x_wrist_span)
            t = (u - 0.66) / 0.34
            t_arm = 1.0 - t
            x = 0.118 * (1.0 - t) + x_wrist_span * t
            cy, cz, ry_a, rz_a = sample_arm_cross(x)
            sh_boost = _smoothstep(0.55, 0.90, t_arm)
            ry = ry_a + 0.022 + 0.008 * sh_boost
            rz = rz_a + 0.020 + 0.006 * sh_boost
            w_cov = _smoothstep(0.12, 0.48, t_arm)
            w_in = _smoothstep(0.84, 1.0, t_arm)
            phi_f = ((0.32 * (1.0 - w_cov) + 0.04 * w_cov) * (1.0 - w_in) + 0.12 * w_in) * math.pi
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
        # Keep collar arc high over trapezius/nape (never cutting linearly through shoulder interior)
        y_n = om * om * (y_neck_b - 0.006) + 2.0 * om * s_v * (y_neck_b + 0.012) + s_v * s_v * (y_neck_b + 0.030)
        z_n = om * om * (z_neck_c + 0.014) + 2.0 * om * s_v * (z_neck_c + 0.022) + s_v * s_v * (z_neck_c - 0.010)
        # Arch upward smoothly across the shoulder-to-neck blend so the sheet clears the trapezius cleanly
        arch_z = 0.018 * math.sin(neck_b * math.pi) * (1.0 - 0.5 * s_v)
        return y_ell * (1.0 - neck_b) + y_n * neck_b, z_ell * (1.0 - neck_b) + z_n * neck_b + arch_z

    for vi in range(n_v):
        v_t = vi / float(n_v - 1)
        row: List[bmesh.types.BMVert] = []
        for ui in range(n_u):
            u = ui / float(n_u - 1)
            spec = col_specs[ui]
            pc_x = spec[0]
            center_dist = abs(u - 0.5) * 2.0
            # Keep ENTIRE back/side cloak long to mid-calf (below knees ~0.29..0.40m) via **2.6 power
            rag = 0.048 * math.sin(u * math.pi * 15.0 + 0.4) + 0.024 * math.cos(u * math.pi * 23.0)
            z_hem = (z_min + 0.18 * h) + (0.39 * h) * (center_dist ** 2.6) + rag
            if not is_tpose and center_dist > 0.55:
                z_hem = max(z_hem, spec[2] + spec[4] - 0.28 * h)

            flare_taper = max(0.0, 1.0 - 0.85 * (center_dist ** 1.8))
            x_norm = max(-1.0, min(1.0, pc_x / 0.12))
            flare_x = x_norm * 0.042 * (v_t ** 1.15) * flare_taper
            px = pc_x * (1.0 + 0.03 * v_t * flare_taper) + flare_x

            pb_y, pb_z = _eval_cowl_yz(spec, 1.0)
            # Broad convex back dome curve + generous shoulder/arm clearance (+0.036m proud of back cowl!)
            back_dome_y = max(pb_y + 0.036, y_back_skirt + 0.080) + 0.022 * math.cos(center_dist * math.pi * 0.5)
            if v_t <= 0.28:
                py, pz = _eval_cowl_yz(spec, v_t / 0.28)
            else:
                k = (v_t - 0.28) / 0.72
                ks = _smoothstep(0.0, 0.72, k)
                py = pb_y * (1.0 - ks) + back_dome_y * ks
                pz = pb_z * (1.0 - (k ** 1.08)) + z_hem * (k ** 1.08)

            row.append(bm.verts.new(Vector((px, py, pz))))
        grid.append(row)

    # Guarantee >= 0.018m cowl clearance above body/shoulder/arm surface via BVH projection
    from mathutils.bvhtree import BVHTree
    bm_body = bmesh.new()
    bm_body.from_mesh(body_obj.data)
    bvh_body = BVHTree.FromBMesh(bm_body)
    bm_body.free()
    for vi in range(n_v):
        v_t = vi / float(n_v - 1)
        if v_t > 0.34:
            break
        for v in grid[vi]:
            loc, nrm, _, dist = bvh_body.find_nearest(v.co)
            if loc is not None and dist < 0.018:
                push = nrm if nrm.length > 1e-4 else Vector((0.0, 0.2, 1.0)).normalized()
                if (v.co - loc).dot(push) < 0.0:
                    push = Vector((0.0, 0.2, 1.0)).normalized()
                v.co = loc + push * 0.018

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


def _paint_croptop_textures() -> Tuple[Path, Path]:
    """Paint 1024x1024 atlas for GhostGirl_CropTop (turtleneck, silver chain, B&W sweetheart crop top)."""
    alb_p = TEX_DIR / "ghost_girl_croptop_albedo.png"
    orm_p = TEX_DIR / "ghost_girl_croptop_orm.png"
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)

    # UV layout (bottom-up Blender v -> yy = 1 - v):
    # - u in [0, 0.70]: crop top front/back torso wrap (u=0.35 is center front!)
    # - u in [0.72, 0.88]: turtleneck collar (dark charcoal-black #1E1B24)
    # - u in [0.90, 1.00]: silver metallic chain clasp (#DCDFE8)
    black_col = np.array([0.115, 0.105, 0.145], dtype=np.float32)
    white_col = np.array([0.955, 0.955, 0.980], dtype=np.float32)
    silver_col = np.array([0.855, 0.875, 0.920], dtype=np.float32)

    alb = np.broadcast_to(black_col[None, None, :], (sz, sz, 3)).copy()

    # Smooth rounded double-arch sweetheart white bust panel centered at xx = 0.35
    dx_c = np.abs(xx - 0.35)
    # Two symmetrical rounded sweetheart bust arches peaking cleanly at ±0.052 around center dip 0.31
    cup_arc = np.sqrt(np.clip(1.0 - ((np.abs(dx_c - 0.048)) / 0.058) ** 2, 0.0, 1.0))
    heart_arch = 0.32 - 0.11 * cup_arc
    panel_half_w = 0.106 * (1.0 - 0.18 * np.clip(yy - 0.28, 0.0, 1.0))
    in_sweetheart = (xx < 0.70) & (dx_c < panel_half_w) & (yy >= heart_arch) & (yy < 0.84)
    alb[in_sweetheart] = white_col

    # Jagged white tattered bottom hem strip around ENTIRE crop top (front & back!) for yy >= 0.78
    jag = 0.78 + 0.042 * np.sin(xx * math.pi * 22.0)
    in_hem = (xx < 0.70) & (yy >= jag)
    alb[in_hem] = white_col

    # Silver chain region (xx >= 0.90)
    in_silver = xx >= 0.90
    alb[in_silver] = silver_col

    _save_image(alb_p, alb)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = np.where(in_silver, 0.20, 0.78)
    orm[:, :, 2] = np.where(in_silver, 0.94, 0.0)
    _save_image(orm_p, orm)
    return alb_p, orm_p


def _build_croptop(bm_obj: bpy.types.Object, lm: Dict[str, Vector]) -> Tuple[bpy.types.Object, Path]:
    """Build black turtleneck + silver chain clasp + B&W sweetheart crop top with jagged hem."""
    alb_p, orm_p = _paint_croptop_textures()
    top_mat = _make_pbr_material(
        "M_ghost_girl_croptop",
        albedo_path=alb_p,
        orm_path=orm_p,
        roughness=0.76,
        double_sided=True,
    )

    body_vs = _vg_indices(bm_obj, ("body",))
    verts = [bm_obj.data.vertices[i].co for i in body_vs]
    z_min = min(v.z for v in verts)
    z_max = max(v.z for v in verts)
    h = z_max - z_min

    # Crop top Z bounds: bottom above navel, turtleneck strictly BELOW chin!
    z_bot = z_min + 0.665 * h
    z_sh_top = z_min + 0.810 * h
    z_neck_top = min(z_min + 0.842 * h, lm["chin"].z - 0.018)
    z_neck_bot = z_neck_top - 0.040

    # 1. Build sleeveless sweetheart crop top shell conformal to anatomical torso
    bm = bmesh.new()
    bm.from_mesh(bm_obj.data)
    # Remove non-body helper verts before extracting torso shell
    del_helper_v = [v for v in bm.verts if v.index not in body_vs]
    if del_helper_v:
        bmesh.ops.delete(bm, geom=del_helper_v, context="VERTS")

    bm.normal_update()
    for v in bm.verts:
        n = v.normal.copy()
        n.z *= 0.25
        if n.length > 1e-4:
            n.normalize()
        v.co += n * 0.0040

    # Bisect crisp horizontal planes for jagged hem base and upper bust edge
    def bisect_torso(z_plane: float) -> None:
        geom = (
            [v for v in bm.verts if abs(v.co.x) < 0.20 and z_bot - 0.05 <= v.co.z <= z_neck_top + 0.04]
            + [e for e in bm.edges if all(abs(v.co.x) < 0.20 and z_bot - 0.05 <= v.co.z <= z_neck_top + 0.04 for v in e.verts)]
            + [f for f in bm.faces if all(abs(v.co.x) < 0.20 and z_bot - 0.05 <= v.co.z <= z_neck_top + 0.04 for v in f.verts)]
        )
        if geom:
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-4, plane_co=Vector((0.0, 0.0, z_plane)), plane_no=Vector((0.0, 0.0, 1.0)))

    bisect_torso(z_bot + 0.020)
    bisect_torso(z_sh_top)
    for sx in (-1.0, 1.0):
        geom_x = (
            [v for v in bm.verts if z_bot <= v.co.z <= z_sh_top + 0.02 and abs(v.co.x) < 0.22]
            + [e for e in bm.edges if all(z_bot <= v.co.z <= z_sh_top + 0.02 and abs(v.co.x) < 0.22 for v in e.verts)]
            + [f for f in bm.faces if all(z_bot <= v.co.z <= z_sh_top + 0.02 and abs(v.co.x) < 0.22 for v in f.verts)]
        )
        if geom_x:
            bmesh.ops.bisect_plane(bm, geom=geom_x, dist=1e-4, plane_co=Vector((sx * 0.128, 0.0, 1.15)), plane_no=Vector((sx, 0.0, 0.0)))

    # Restrict crop top to clean sleeveless torso (|x| <= 0.128, Z in [z_bot + 0.020, z_sh_top])
    del_f = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z < z_bot + 0.020 or c.z > z_sh_top or abs(c.x) > 0.128:
            del_f.append(f)
    bmesh.ops.delete(bm, geom=del_f, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")

    uv_layer = bm.loops.layers.uv.verify()
    torso_c_y = sum(v.co.y for v in bm.verts) / float(max(len(bm.verts), 1))
    for f in bm.faces:
        f.smooth = True
        for loop in f.loops:
            p = loop.vert.co
            ang = math.atan2(p.x, -(p.y - torso_c_y))  # 0 at front (-Y), +/-pi at back (+Y)
            u = 0.35 + (ang / math.pi) * 0.33
            v_uv = (p.z - z_bot) / max(z_sh_top - z_bot, 1e-4)
            loop[uv_layer].uv = (max(0.01, min(0.68, u)), max(0.08, min(0.98, v_uv)))

    # Add 3D jagged white tattered bottom hem teeth wrapping cleanly around bottom edge (z_bot .. z_bot + 0.024)
    hem_vs = [v.co.copy() for v in bm.verts if v.co.z < z_bot + 0.036]
    rx_h = max((abs(v.x) for v in hem_vs), default=0.105) + 0.002
    y_h_f = min((v.y for v in hem_vs), default=-0.075) - 0.001
    y_h_b = max((v.y for v in hem_vs), default=0.075) + 0.001
    cy_h = 0.5 * (y_h_f + y_h_b)
    ry_h = 0.5 * (y_h_b - y_h_f)

    n_jag = 36
    jag_top: List[bmesh.types.BMVert] = []
    jag_bot: List[bmesh.types.BMVert] = []
    for ji in range(n_jag):
        ang = math.tau * (ji / float(n_jag))
        sa, ca = math.sin(ang), -math.cos(ang)
        px = sa * rx_h
        py = cy_h + ca * ry_h
        z_t = z_bot + 0.026
        tip_drop = 0.024 if (ji % 2 == 1) else 0.004
        z_b = z_bot + 0.014 - tip_drop
        jag_top.append(bm.verts.new(Vector((px, py, z_t))))
        jag_bot.append(bm.verts.new(Vector((px * 1.03, py * 1.03, z_b))))

    for ji in range(n_jag):
        jn = (ji + 1) % n_jag
        fj = bm.faces.new((jag_top[ji], jag_bot[ji], jag_bot[jn], jag_top[jn]))
        fj.smooth = False
        for loop in fj.loops:
            loop[uv_layer].uv = (0.35, 0.05)  # yy=0.95 -> pure white jagged hem

    # 2. Snug black turtleneck collar hugging neck silhouette + halter base (ZERO floating collar gap)
    col_rings: List[List[bmesh.types.BMVert]] = []
    for z_c, pad in ((z_sh_top - 0.004, 0.0045), (z_neck_bot + 0.002, 0.0035), (0.5 * (z_neck_bot + z_neck_top), 0.0032), (z_neck_top, 0.0028), (z_neck_top - 0.005, 0.0015)):
        n_band = [v for v in verts if (z_c - 0.014) <= v.z <= (z_c + 0.014) and abs(v.x) < 0.085]
        if n_band:
            rx_c = max(abs(v.x) for v in n_band) + pad
            y_f = min(v.y for v in n_band) - pad
            y_b = max(v.y for v in n_band) + pad
            cy_c = 0.5 * (y_f + y_b)
            ry_c = 0.5 * (y_b - y_f)
        else:
            rx_c, cy_c, ry_c = 0.052 + pad, torso_c_y, 0.052 + pad
        ring_c: List[bmesh.types.BMVert] = []
        for si in range(32):
            ang = math.tau * (si / 32.0)
            ring_c.append(bm.verts.new(Vector((math.sin(ang) * rx_c, cy_c - math.cos(ang) * ry_c, z_c))))
        col_rings.append(ring_c)
    for ri in range(len(col_rings) - 1):
        for si in range(32):
            sn = (si + 1) % 32
            fc = bm.faces.new((col_rings[ri][si], col_rings[ri + 1][si], col_rings[ri + 1][sn], col_rings[ri][sn]))
            fc.smooth = True
            for loop in fc.loops:
                loop[uv_layer].uv = (0.80, 0.50)

    # 3. Continuous curved silver chain clasp across front collarbone (ZERO detached beads)
    c_band = [v for v in verts if (z_sh_top - 0.025) <= v.z <= (z_neck_bot + 0.010) and abs(v.x) < 0.085 and v.y < torso_c_y]
    chain_y_front = min((v.y for v in c_band), default=torso_c_y - 0.052) - 0.0045
    chain_pts: List[Vector] = []
    n_arc = 17
    for ci in range(n_arc):
        t = (ci / float(n_arc - 1)) * 2.0 - 1.0
        cx = t * 0.062
        cz = (z_neck_bot - 0.004) - 0.014 * (1.0 - t * t)
        cy = chain_y_front + 0.016 * (t * t)
        chain_pts.append(Vector((cx, cy, cz)))

    tube_rings: List[List[bmesh.types.BMVert]] = []
    n_sides = 8
    r_chain = 0.0024
    for ci, pt in enumerate(chain_pts):
        tang = (chain_pts[1] - chain_pts[0]) if ci == 0 else ((chain_pts[-1] - chain_pts[-2]) if ci == n_arc - 1 else (chain_pts[ci + 1] - chain_pts[ci - 1]))
        tang.normalize()
        up_v = Vector((0.0, 0.0, 1.0))
        n1 = tang.cross(up_v).normalized()
        n2 = n1.cross(tang).normalized()
        # Subtle braided link ripple along chain
        r_cur = r_chain * (1.0 + 0.16 * math.cos(ci * math.pi))
        t_ring: List[bmesh.types.BMVert] = []
        for si in range(n_sides):
            ang = math.tau * (si / float(n_sides))
            offset = (n1 * math.cos(ang) + n2 * math.sin(ang)) * r_cur
            t_ring.append(bm.verts.new(pt + offset))
        tube_rings.append(t_ring)
    for ci in range(n_arc - 1):
        for si in range(n_sides):
            sn = (si + 1) % n_sides
            ft = bm.faces.new((tube_rings[ci][si], tube_rings[ci + 1][si], tube_rings[ci + 1][sn], tube_rings[ci][sn]))
            ft.smooth = True
            for loop in ft.loops:
                loop[uv_layer].uv = (0.95, 0.50)
    # Small silver clasp ring medallion at center collarbone
    ret_clasp = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.0042)
    for v in ret_clasp["verts"]:
        v.co = Vector((v.co.x, v.co.y * 0.55, v.co.z)) + chain_pts[n_arc // 2]
    for f in {f for v in ret_clasp["verts"] for f in v.link_faces}:
        f.smooth = True
        for loop in f.loops:
            loop[uv_layer].uv = (0.95, 0.50)

    crop_mesh = bpy.data.meshes.new("GhostGirl_CropTop")
    bm.to_mesh(crop_mesh)
    bm.free()
    crop_mesh.materials.append(top_mat)
    crop_obj = bpy.data.objects.new("GhostGirl_CropTop", crop_mesh)
    bpy.context.collection.objects.link(crop_obj)
    return crop_obj, alb_p


def _paint_skirt_textures() -> Tuple[Path, Path]:
    """Paint 1024x1024 atlas for GhostGirl_Skirt (waistband, 12 alternating B&W pleats, safety shorts)."""
    alb_p = TEX_DIR / "ghost_girl_skirt_albedo.png"
    orm_p = TEX_DIR / "ghost_girl_skirt_orm.png"
    sz = 1024
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)

    # UV layout (top-down yy = 1 - v_uv):
    # - yy < 0.16: dark charcoal waistband (#201D26)
    # - yy in [0.16, 0.84]: 12 alternating black & white pleats!
    #   Center front is at xx = 0.0/1.0 (pleat 0 -> BLACK), flanked by WHITE (pleat 1, 11), etc.
    # - yy >= 0.84: dark safety shorts (#1B1822)
    black_col = np.array([0.125, 0.115, 0.150], dtype=np.float32)
    white_col = np.array([0.945, 0.945, 0.970], dtype=np.float32)
    shorts_col = np.array([0.105, 0.095, 0.130], dtype=np.float32)

    alb = np.broadcast_to(black_col[None, None, :], (sz, sz, 3)).copy()
    # 12 pleats across xx in [0, 1], shifted by +0.5/12 so pleat 0 is centered at xx=0.0/1.0
    pleat_idx = np.floor(((xx + 0.5 / 12.0) % 1.0) * 12.0).astype(np.int32)
    is_white_pleat = (yy >= 0.16) & (yy < 0.84) & ((pleat_idx % 2) == 1)
    alb[is_white_pleat] = white_col

    # Subtle fold shadow near pleat borders
    pleat_phase = (((xx + 0.5 / 12.0) % 1.0) * 12.0) % 1.0
    crease = np.exp(-0.5 * (np.minimum(pleat_phase, 1.0 - pleat_phase) / 0.05) ** 2)
    in_pleat_zone = (yy >= 0.16) & (yy < 0.84)
    alb[in_pleat_zone] *= (1.0 - 0.16 * crease[in_pleat_zone, None])

    alb[yy >= 0.84] = shorts_col
    _save_image(alb_p, alb)

    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = 0.80
    orm[:, :, 2] = 0.0
    _save_image(orm_p, orm)
    return alb_p, orm_p


def _build_skirt(bm_obj: bpy.types.Object) -> Tuple[bpy.types.Object, Path]:
    """Build B&W alternating pleated mini-skirt with jagged hem + dark safety shorts underneath."""
    alb_p, orm_p = _paint_skirt_textures()
    skirt_mat = _make_pbr_material(
        "M_ghost_girl_skirt",
        albedo_path=alb_p,
        orm_path=orm_p,
        roughness=0.80,
        double_sided=True,
    )

    body_vs = _vg_indices(bm_obj, ("body",))
    verts = [bm_obj.data.vertices[i].co for i in body_vs if abs(bm_obj.data.vertices[i].co.x) < 0.24]
    z_min = min(v.z for v in verts)
    z_max = max(v.z for v in verts)
    h = z_max - z_min

    z_waist_top = z_min + 0.605 * h
    z_band_bot = z_min + 0.578 * h
    z_hem_base = z_min + 0.430 * h

    waist_vs = [v for v in verts if z_band_bot <= v.z <= z_waist_top]
    w_rx = max((abs(v.x) for v in waist_vs), default=0.112) + 0.006
    w_ry_f = abs(min((v.y for v in waist_vs), default=-0.082)) + 0.006
    w_ry_b = abs(max((v.y for v in waist_vs), default=0.082)) + 0.006

    hip_vs = [v for v in verts if z_hem_base <= v.z <= z_band_bot]
    max_hip_rx = max((abs(v.x) for v in hip_vs), default=0.145)
    max_hip_ry_f = abs(min((v.y for v in hip_vs), default=-0.092))
    max_hip_ry_b = abs(max((v.y for v in hip_vs), default=0.112))

    hem_rx = max(w_rx + 0.085, max_hip_rx + 0.035)
    hem_ry_f = max(w_ry_f + 0.058, max_hip_ry_f + 0.026)
    hem_ry_b = max(w_ry_b + 0.075, max_hip_ry_b + 0.030)

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
            pleat_d = 0.012 * _smoothstep(0.0, 0.45, t)

        prev_rx, prev_ry_f, prev_ry_b = rx, ry_f, ry_b
        # Clean symmetric A-line accordion pleats (zero self-folding or hem balloon tuck)
        pleat_offs = (0.0, 0.55 * pleat_d, 1.05 * pleat_d, 0.55 * pleat_d)
        ring: List[bmesh.types.BMVert] = []
        for si in range(n_segs):
            # Shift by -pi/n_pleats so pleat 0 (centered at ang=0 front -Y) aligns cleanly with texture!
            ang = math.tau * (si / float(n_segs)) - math.pi / float(n_pleats)
            sa, ca = math.sin(ang), -math.cos(ang)
            po = pleat_offs[si % v_per_pleat]
            vz = z
            if ri == len(z_levels) - 1:
                # Crisp jagged tattered hem points flaring cleanly outward!
                vz -= 0.018 * ((si % 2) + 0.4 * math.sin(ang * 5.0))
            ring.append(bm.verts.new(Vector((sa * (rx + po), ca * ((ry_f if ca < 0 else ry_b) + po), vz))))
        rings.append(ring)

    # Map z_levels monotonically onto yy in [0.02..0.82] (v_uv in [0.18..0.98]) — NEVER break wrap with % 1.0!
    v_levels = (0.98, 0.91, 0.84, 0.68, 0.52, 0.36, 0.19)
    for ri in range(len(rings) - 1):
        v0 = v_levels[ri]
        v1 = v_levels[ri + 1]
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

    # Dark safety shorts underneath (cleanly inset inside skirt pleats)
    bm_sh = bmesh.new()
    bm_sh.from_mesh(bm_obj.data)
    del_hv = [v for v in bm_sh.verts if v.index not in body_vs]
    if del_hv:
        bmesh.ops.delete(bm_sh, geom=del_hv, context="VERTS")
    del_sf = [
        f
        for f in bm_sh.faces
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
        n.z *= 0.2
        if n.length > 1e-4:
            n.normalize()
        v.co += n * 0.0014
    uv_sh = bm_sh.loops.layers.uv.verify()
    for f in bm_sh.faces:
        f.smooth = True
        for loop in f.loops:
            loop[uv_sh].uv = (0.5, 0.08)  # yy=0.92 -> dark safety shorts!
    tmp_m = bpy.data.meshes.new("_tmp_shorts")
    bm_sh.to_mesh(tmp_m)
    bm_sh.free()
    # Ensure exact single UV layer named matching bm's uv_layer so pleats don't lose active UV!
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


def _paint_gloves_textures() -> Tuple[Path, Path]:
    alb_p = TEX_DIR / "ghost_girl_gloves_albedo.png"
    orm_p = TEX_DIR / "ghost_girl_gloves_orm.png"
    sz = 512
    alb = np.full((sz, sz, 3), (0.125, 0.115, 0.148), dtype=np.float32)
    alb[:96, :, :] = np.array([0.095, 0.085, 0.118], dtype=np.float32)  # darker cuff trim
    _save_image(alb_p, alb)
    orm = np.zeros((sz, sz, 3), dtype=np.float32)
    orm[:, :, 0] = 0.94
    orm[:, :, 1] = 0.52
    orm[:, :, 2] = 0.02
    _save_image(orm_p, orm)
    return alb_p, orm_p


def _build_gloves(
    body_obj: bpy.types.Object,
    alb_p: Path,
    orm_p: Path,
) -> bpy.types.Object:
    """Build black fingerless wrist-length gloves (GhostGirl_Gloves) along arm axis in A-pose or T-pose."""
    glove_mat = _make_pbr_material("M_ghost_girl_gloves", albedo_path=alb_p, orm_path=orm_p, roughness=0.50)

    body_vs = _vg_indices(body_obj, ("body",))
    if not body_vs:
        body_vs = set(range(len(body_obj.data.vertices)))

    bm = bmesh.new()
    bm.from_mesh(body_obj.data)
    del_hv = [v for v in bm.verts if v.index not in body_vs]
    if del_hv:
        bmesh.ops.delete(bm, geom=del_hv, context="VERTS")
    bm.normal_update()

    # Measure hand vector along each side (Left +X, Right -X) using outermost vertices so it works in BOTH A-pose & T-pose!
    hand_planes: List[Tuple[float, Vector, Vector, Vector, Vector]] = []
    for sx in (1.0, -1.0):
        side_arm = [v.co for v in bm.verts if (v.co.x * sx) > 0.25]
        if not side_arm:
            continue
        tip_p = max(side_arm, key=lambda c: c.x * sx)
        # Find wrist centroid ~13cm inward along arm from fingertip
        near_arm = [c for c in side_arm if (tip_p - c).length < 0.22]
        inner_p = min(near_arm, key=lambda c: c.x * sx)
        arm_dir = (tip_p - inner_p).normalized()
        # Wrist cuff at ~15.5cm back from fingertip, knuckle finger cut at ~6.8cm back from fingertip
        p_wrist = tip_p - arm_dir * 0.155
        p_knuckle = tip_p - arm_dir * 0.068
        p_cuff = p_wrist + arm_dir * 0.018
        hand_planes.append((sx, arm_dir, p_wrist, p_cuff, p_knuckle))

    for v in bm.verts:
        v.co += v.normal * 0.0018

    # Bisect wrist & finger-cut planes perpendicular to arm_dir
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
        for sx, arm_dir, p_wrist, p_cuff, p_knuckle in hand_planes:
            if (c.x * sx) <= 0.20:
                continue
            d_w = (c - p_wrist).dot(arm_dir)
            d_k = (c - p_knuckle).dot(arm_dir)
            if d_w >= -0.001 and d_k <= 0.001:
                # Cut thumb forward protrusion past proximal joint
                # Check distance perpendicular to arm axis toward -Y (thumb side)
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
        for sx, arm_dir, p_wrist, p_cuff, _ in hand_planes:
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


def _paint_boots_textures() -> Tuple[Path, Path]:
    alb_p = TEX_DIR / "ghost_girl_boots_albedo.png"
    orm_p = TEX_DIR / "ghost_girl_boots_orm.png"
    sz = 512
    yy, _ = np.mgrid[0:sz, 0:sz].astype(np.float32) / float(sz)
    # Top-down yy < 0.25: cuff collar (#26222D), mid [0.25..0.75]: boot leather (#2E2A36), bottom > 0.75: thick flat sole (#18151E)
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


def _build_boots(bm_obj: bpy.types.Object) -> Tuple[bpy.types.Object, Path]:
    """Build dark charcoal cuffed ankle boots (GhostGirl_Boots) with flat thick soles seated at Z=0."""
    alb_p, orm_p = _paint_boots_textures()
    boot_mat = _make_pbr_material("M_ghost_girl_boots", albedo_path=alb_p, orm_path=orm_p, roughness=0.48)

    body_vs = _vg_indices(bm_obj, ("body",))
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

        def loft(profiles: List[Tuple[float, float, float, float, float]], v_range: Tuple[float, float], cap_bot: bool = False, cap_top: bool = False) -> None:
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

        # 1. Flat thick dark sole (Z: 0.000 -> 0.030)
        loft([
            (y_toe - 0.004, y_heel + 0.004, 0.052, 0.000, 0.55),
            (y_toe - 0.005, y_heel + 0.005, 0.054, 0.022, 0.55),
            (y_toe - 0.002, y_heel + 0.003, 0.050, 0.030, 0.45),
        ], v_range=(0.05, 0.22), cap_bot=True, cap_top=True)

        # 2. Smooth boot vamp & ankle shaft (Z: 0.028 -> 0.195)
        loft([
            (y_toe + 0.002, y_heel - 0.001, 0.047, 0.028, 0.35),
            (y_toe + 0.006, y_heel - 0.002, 0.046, 0.055, 0.28),
            (y_toe + 0.042, y_heel - 0.004, 0.044, 0.078, 0.15),
            (ank_y - 0.052, y_heel - 0.005, 0.042, 0.105, 0.08),
            (ank_y - 0.049, ank_y + 0.049, 0.044, 0.152, 0.06),
            (ank_y - 0.050, ank_y + 0.050, 0.046, 0.192, 0.06),
        ], v_range=(0.30, 0.72), cap_bot=False, cap_top=False)

        # 3. Turned-down / banded ankle cuff collar (Z: 0.155 -> 0.205, slightly flared)
        loft([
            (ank_y - 0.048, ank_y + 0.048, 0.045, 0.155, 0.06),
            (ank_y - 0.056, ank_y + 0.056, 0.052, 0.162, 0.06),
            (ank_y - 0.057, ank_y + 0.057, 0.053, 0.198, 0.06),
            (ank_y - 0.049, ank_y + 0.049, 0.045, 0.204, 0.06),
            (ank_y - 0.043, ank_y + 0.043, 0.040, 0.190, 0.06),
        ], v_range=(0.80, 0.96), cap_bot=False, cap_top=False)

    boots_mesh = bpy.data.meshes.new("GhostGirl_Boots")
    bm.to_mesh(boots_mesh)
    bm.free()
    boots_mesh.materials.append(boot_mat)
    boots_obj = bpy.data.objects.new("GhostGirl_Boots", boots_mesh)
    bpy.context.collection.objects.link(boots_obj)
    return boots_obj, alb_p


# ---------------------------------------------------------------------------
# Step 5: Standalone T-Pose Cleanup, Head/Body Split & 52+6 ARKit Blendshapes
# ---------------------------------------------------------------------------

def _straighten_arms_to_tpose(
    obj: bpy.types.Object,
    joints: Optional[Dict[str, Vector]] = None,
) -> None:
    """Two-stage anatomical arm straighten (elbow -> true shoulder joint) with smooth armpit blend."""
    verts = obj.data.vertices
    adj: Dict[int, List[int]] = {i: [] for i in range(len(verts))}
    for e in obj.data.edges:
        v0, v1 = e.vertices[0], e.vertices[1]
        adj[v0].append(v1)
        adj[v1].append(v0)

    def _dist_point_to_seg(p: Vector, a: Vector, b: Vector) -> float:
        ab = b - a
        ab2 = ab.length_squared
        if ab2 < 1e-8:
            return (p - a).length
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab2))
        return (p - (a + ab * t)).length

    j = joints or {}
    sh_l = j.get("sh_l", Vector((0.151, 0.001, 1.183)))
    el_l = j.get("el_l", Vector((0.303, 0.011, 1.014)))
    ha_l = j.get("ha_l", Vector((0.411, -0.135, 0.910)))
    sh_r = j.get("sh_r", Vector((-sh_l.x, sh_l.y, sh_l.z)))
    el_r = j.get("el_r", Vector((-el_l.x, el_l.y, el_l.z)))
    ha_r = j.get("ha_r", Vector((-ha_l.x, ha_l.y, ha_l.z)))

    orig = [v.co.copy() for v in verts]
    smooth_band: Set[int] = set()

    for sx, p_sh, p_el, p_ha in ((1.0, sh_l, el_l, ha_l), (-1.0, sh_r, el_r, ha_r)):
        seeds = [v.index for v in verts if (orig[v.index].x * sx) > 0.25]
        side_set = set(seeds)
        queue = list(seeds)
        while queue:
            curr = queue.pop()
            for nb in adj[curr]:
                if nb in side_set:
                    continue
                p0 = orig[nb]
                if (p0.x * sx) < 0.075:
                    continue
                if (p0.x * sx) < 0.22 and p0.z < p_sh.z - 0.145:
                    continue
                side_set.add(nb)
                queue.append(nb)

        dir_up = (p_el - p_sh).normalized()
        dir_fa = (p_ha - p_el).normalized()
        q_el = dir_fa.rotation_difference(dir_up)
        ax_el, ang_el = q_el.axis, q_el.angle

        target_dir = Vector((sx, 0.0, 0.0))
        q_sh = dir_up.rotation_difference(target_dir)
        ax_sh, ang_sh = q_sh.axis, q_sh.angle

        seam_origin = p_sh - Vector((0.022 * sx, 0.0, 0.0))
        seam_normal = Vector((0.94 * sx, 0.0, -0.34)).normalized()

        for idx in side_set:
            p0 = orig[idx]
            # Only guard lateral ribcage/bust near torso; hands & fingers (|x| >= 0.22) must stay 1.0!
            if (p0.x * sx) < 0.22 and p0.z < p_sh.z + 0.015:
                d_arm = min(_dist_point_to_seg(p0, p_sh, p_el), _dist_point_to_seg(p0, p_el, p_ha))
                w_guard = 1.0 - _smoothstep(0.062, 0.092, d_arm)
                if w_guard <= 1e-4:
                    continue
            else:
                w_guard = 1.0

            # Stage 1: Straighten elbow bend into aligned A-pose axis around p_el
            proj_el = (p0 - p_el).dot(dir_up)
            w_el = _smoothstep(-0.045, 0.045, proj_el) * w_guard
            p1 = p_el + (Matrix.Rotation(ang_el * w_el, 3, ax_el) @ (p0 - p_el)) if (w_el > 1e-4 and ang_el > 1e-4) else p0.copy()

            # Stage 2: Raise straight arm around true humeral head pivot p_sh into horizontal T-pose
            s_ring = (p0 - seam_origin).dot(seam_normal)
            w_sh = _smoothstep(-0.032, 0.076, s_ring) * w_guard
            if w_sh > 1e-4 and ang_sh > 1e-4:
                verts[idx].co = p_sh + (Matrix.Rotation(ang_sh * w_sh, 3, ax_sh) @ (p1 - p_sh))
            else:
                verts[idx].co = p1

            if 0.02 < w_sh < 0.98:
                smooth_band.add(idx)

    # Gentle volume-preserving relaxation across the raised armpit/shoulder bend zone ONLY
    if smooth_band:
        for _ in range(4):
            nxt: Dict[int, Vector] = {}
            for idx in smooth_band:
                nbs = adj[idx]
                if not nbs:
                    continue
                avg = sum((verts[nb].co for nb in nbs), Vector((0.0, 0.0, 0.0))) / float(len(nbs))
                nxt[idx] = verts[idx].co.lerp(avg, 0.30)
            for idx, co in nxt.items():
                verts[idx].co = co
    obj.data.update()


def _strip_helpers_and_split_head_body(
    bm_obj: bpy.types.Object,
    skin_alb: Path,
    skin_nrm: Path,
    skin_orm: Path,
    lm: Dict[str, Vector],
) -> Tuple[bpy.types.Object, bpy.types.Object]:
    """Strip MakeHuman helper faces, hide feet inside boots, and split at neck collar into Head & Body."""
    # Sample exact MakeHuman joint centers from JointCubes BEFORE deleting helper vertices
    joints: Dict[str, Vector] = {}
    for key, vgn in (
        ("sh_l", "joint-l-shoulder"),
        ("el_l", "joint-l-elbow"),
        ("ha_l", "joint-l-hand"),
        ("sh_r", "joint-r-shoulder"),
        ("el_r", "joint-r-elbow"),
        ("ha_r", "joint-r-hand"),
    ):
        vg = bm_obj.vertex_groups.get(vgn)
        if vg is not None:
            pts = [v.co.copy() for v in bm_obj.data.vertices if any(g.group == vg.index for g in v.groups)]
            if pts:
                joints[key] = sum(pts, Vector((0.0, 0.0, 0.0))) / float(len(pts))

    body_vs = _vg_indices(bm_obj, ("body",))
    bm_clean = bmesh.new()
    bm_clean.from_mesh(bm_obj.data)
    del_h = [v for v in bm_clean.verts if v.index not in body_vs]
    if del_h:
        bmesh.ops.delete(bm_clean, geom=del_h, context="VERTS")
    bm_clean.to_mesh(bm_obj.data)
    bm_clean.free()
    bm_obj.data.update()

    # Straighten arms to T-pose cleanly around exact MakeHuman humeral pivots
    _straighten_arms_to_tpose(bm_obj, joints)

    # Split inside black turtleneck collar cleanly below chin
    z_cut = min(TARGET_HEIGHT_M - 0.255, lm["chin"].z - 0.036)

    head_obj = bm_obj.copy()
    head_obj.data = bm_obj.data.copy()
    head_obj.name = "GhostGirl_Head"
    head_obj.data.name = "GhostGirl_Head"
    bpy.context.collection.objects.link(head_obj)

    body_obj = bm_obj
    body_obj.name = "GhostGirl_Body"
    body_obj.data.name = "GhostGirl_Body"

    bm_h = bmesh.new()
    bm_h.from_mesh(head_obj.data)
    # Apply |x| width guard only in the lower collar band so ears/temples above z_cut+0.04 stay on Head
    del_fh = [
        f
        for f in bm_h.faces
        if (c := f.calc_center_median()).z < z_cut - 0.012
        or (c.z < z_cut + 0.04 and abs(c.x) > 0.088)
    ]
    bmesh.ops.delete(bm_h, geom=del_fh, context="FACES")
    loose_h = [v for v in bm_h.verts if not v.link_faces]
    if loose_h:
        bmesh.ops.delete(bm_h, geom=loose_h, context="VERTS")
    # Push strictly central interior mouth-sock back wall backward (NEVER touching exterior cheek/chin corners)
    mc_h = lm["mouth"]
    for v in bm_h.verts:
        if (
            abs(v.co.x) < 0.014
            and (mc_h.z - 0.006) <= v.co.z <= (mc_h.z + 0.008)
            and (mc_h.y + 0.012) < v.co.y < (mc_h.y + 0.055)
        ):
            w_bag = _smoothstep(mc_h.y + 0.012, mc_h.y + 0.018, v.co.y)
            v.co.y += 0.028 * w_bag
    for f in bm_h.faces:
        f.smooth = True
    bm_h.to_mesh(head_obj.data)
    bm_h.free()
    head_obj.data.update()

    bm_b = bmesh.new()
    bm_b.from_mesh(body_obj.data)
    # Remove all head/ear faces (z >= z_cut+0.04), neck collar core, and hidden foot faces inside boots (z < 0.145)
    del_fb = [
        f
        for f in bm_b.faces
        if (c := f.calc_center_median()).z >= z_cut + 0.04
        or (c.z >= z_cut - 0.008 and abs(c.x) <= 0.085)
        or c.z < 0.145
    ]
    bmesh.ops.delete(bm_b, geom=del_fb, context="FACES")
    loose_b = [v for v in bm_b.verts if not v.link_faces]
    if loose_b:
        bmesh.ops.delete(bm_b, geom=loose_b, context="VERTS")
    for f in bm_b.faces:
        f.smooth = True
    bm_b.to_mesh(body_obj.data)
    bm_b.free()
    body_obj.data.update()

    face_mat = _make_pbr_material(
        "M_ghost_girl_face",
        albedo_path=skin_alb,
        normal_path=skin_nrm,
        orm_path=skin_orm,
        roughness=0.64,
        sss=0.0,
    )
    body_mat = _make_pbr_material(
        "M_ghost_girl_body_skin",
        albedo_path=skin_alb,
        normal_path=skin_nrm,
        orm_path=skin_orm,
        roughness=0.64,
        sss=0.0,
    )
    head_obj.data.materials.clear()
    head_obj.data.materials.append(face_mat)
    body_obj.data.materials.clear()
    body_obj.data.materials.append(body_mat)
    return head_obj, body_obj


def _bake_arkit_52_shape_keys(
    head_obj: bpy.types.Object,
    lash_obj: bpy.types.Object,
    eye_l_obj: bpy.types.Object,
    lm: Dict[str, Vector],
) -> None:
    """Bake 52 ARKit blendshapes on GhostGirl_Head + 6 eyelid keys on GhostGirl_Eyelashes.

    Calibrated specifically for GhostGirl's enlarged anime eye sockets so eyeBlinkLeft/Right = 1.0
    wraps the upper eyelid cleanly down and forward along the spherical cornea with ZERO eyeball
    poke-through.
    """
    head_obj.shape_key_clear()
    head_obj.shape_key_add(name="Basis", from_mix=False)
    head_obj.data.shape_keys.use_relative = True
    lash_obj.shape_key_clear()
    lash_obj.shape_key_add(name="Basis", from_mix=False)
    lash_obj.data.shape_keys.use_relative = True

    le = lm["left_eye"]
    re = lm["right_eye"]
    mc = lm["mouth"]
    nt = lm["nose_tip"]
    chin = lm["chin"]
    jaw_pivot = Vector((0.0, lm["ear_y"].y + 0.012, lm["ear_y"].z - 0.024))
    brow_z = le.z + 0.025
    mouth_half_w = 0.021

    # Measure exact anime eyeball cornea radius & vertical aperture for leak-free blink closure
    l_pts = [v.co for v in eye_l_obj.data.vertices]
    y_cornea_front = min((p.y for p in l_pts), default=le.y - 0.014)
    r_eye_x = max((max(p.x for p in l_pts) - min(p.x for p in l_pts)) * 0.5, 0.015)
    r_eye_y = max(le.y - y_cornea_front, 0.013)
    r_eye_z = max((max(p.z for p in l_pts) - min(p.z for p in l_pts)) * 0.5, 0.015)

    def compute_delta(shape: str, p: Vector) -> Vector:
        if p.y > lm["ear_y"].y + 0.015 or p.z < chin.z - 0.035:
            return Vector((0.0, 0.0, 0.0))

        d = Vector((0.0, 0.0, 0.0))
        is_left = shape.endswith("Left")
        eye_c = le if is_left else re
        sx = 1.0 if is_left else -1.0

        if shape in ("eyeBlinkLeft", "eyeBlinkRight"):
            dx_signed = (p.x - eye_c.x) * sx
            dx = abs(dx_signed)
            dz = p.z - eye_c.z
            # Tighter horizontal cutoff on inner nose bridge (-sx) vs outer temple (+sx) to prevent bridge crease
            dx_in = r_eye_x * (0.90 if dx_signed < 0.0 else 1.15)
            dx_out = r_eye_x * (1.34 if dx_signed < 0.0 else 1.78)
            if p.y < eye_c.y + 0.014 and dx < dx_out and -r_eye_z * 1.65 < dz < r_eye_z * 1.62:
                kx = 1.0 - _smoothstep(dx_in, dx_out, dx)
                dx_u = min(1.0, dx / max(r_eye_x * 1.25, 0.015))
                z_closed = eye_c.z - 0.0092 + 0.0022 * (dx_u * dx_u)
                z_rim = eye_c.z + r_eye_z * 1.04
                z_brow = eye_c.z + r_eye_z * 1.60
                if dz >= -0.005:
                    # Map rim & lashes to curved closed line, and smoothly stretch upper eyelid skin monotonically
                    if p.z <= z_rim:
                        desired_z = z_closed
                    elif p.z < z_brow:
                        t_ab = (p.z - z_rim) / max(z_brow - z_rim, 1e-4)
                        desired_z = z_closed + (t_ab ** 0.72) * (z_brow - z_closed)
                    else:
                        desired_z = p.z
                    d.z += (desired_z - p.z) * kx
                    kz_env = 1.0 - _smoothstep(r_eye_z * 1.12, r_eye_z * 1.58, dz)
                else:
                    kz_env = 1.0 - _smoothstep(r_eye_z * 0.78, r_eye_z * 1.48, -dz)
                    lift = min(0.0065, max(0.0, (z_closed + 0.0032) - p.z))
                    d.z += lift * kx * kz_env
                # Wrap cleanly forward around enlarged cornea (-Y) fading toward corners so socket never bulges
                new_z = p.z + d.z
                cornea_proj = math.sqrt(max(0.0, 1.0 - min(0.95, ((p.x - eye_c.x) / (r_eye_x * 1.32)) ** 2 + ((new_z - eye_c.z) / (r_eye_z * 1.12)) ** 2)))
                safe_y = eye_c.y - r_eye_y * cornea_proj - 0.0018
                ky_dome = (1.0 - _smoothstep(r_eye_x * 0.72, r_eye_x * 1.32, dx)) * (1.0 - _smoothstep(r_eye_z * 0.85, r_eye_z * 1.38, abs(dz)))
                if p.y + d.y > safe_y:
                    d.y += (safe_y - (p.y + d.y)) * ky_dome
        elif shape in ("eyeWideLeft", "eyeWideRight"):
            w = _gauss((p - eye_c).length, 0.022)
            if p.z >= eye_c.z:
                d.z += 0.0065 * w
            else:
                d.z -= 0.0025 * w
        elif shape in ("eyeSquintLeft", "eyeSquintRight"):
            w = _gauss((p - (eye_c + Vector((0.0, 0.0, -0.009)))).length, 0.022)
            d.z += 0.0055 * w
            d.y -= 0.0018 * w
        elif shape.startswith("eyeLook"):
            w = _gauss((p - eye_c).length, 0.020)
            if "Down" in shape:
                d.z -= 0.0038 * w
            elif "Up" in shape:
                d.z += 0.0038 * w
            elif "In" in shape:
                d.x -= sx * 0.0030 * w
            elif "Out" in shape:
                d.x += sx * 0.0030 * w
        elif shape == "jawOpen":
            if p.z < mc.z - 0.001:
                w = _smoothstep(mc.z - 0.001, mc.z - 0.009, p.z) * _smoothstep(lm["ear_y"].y, mc.y + 0.030, p.y)
                rel = p - jaw_pivot
                rot = Matrix.Rotation(math.radians(17.0), 3, "X")
                d = ((jaw_pivot + rot @ rel) - p) * w
            elif p.z <= mc.z + 0.018:
                # Lift ENTIRE upper lip arch & inner curtain cleanly so upper incisors read clearly!
                w_up = _gauss((p - Vector((0.0, mc.y, mc.z + 0.002))).length, 0.018)
                d.z += 0.0100 * w_up
                d.y -= 0.0028 * w_up
        elif shape == "jawForward":
            w = _smoothstep(mc.z + 0.005, chin.z, p.z)
            d.y -= 0.007 * w
        elif shape in ("jawLeft", "jawRight"):
            w = _smoothstep(mc.z + 0.005, chin.z, p.z)
            d.x += (0.007 if shape == "jawLeft" else -0.007) * w
        elif shape == "mouthClose":
            w = _gauss((p - mc).length, 0.022)
            d.z += (0.0055 if p.z < mc.z else -0.0025) * w
        elif shape == "mouthFunnel":
            w = _gauss((p - mc).length, 0.024)
            d.x -= p.x * 0.28 * w
            d.y -= 0.0085 * w
        elif shape == "mouthPucker":
            w = _gauss((p - mc).length, 0.023)
            d.x -= p.x * 0.38 * w
            d.y -= 0.010 * w
        elif shape in ("mouthLeft", "mouthRight"):
            w = _gauss((p - mc).length, 0.026)
            d.x += (0.008 if shape == "mouthLeft" else -0.008) * w
        elif shape in ("mouthSmileLeft", "mouthSmileRight"):
            corner = Vector((sx * (mouth_half_w + 0.003), mc.y, mc.z))
            w = _gauss((p - corner).length, 0.014)
            d.x += sx * 0.0080 * w
            d.z += 0.0105 * w
            d.y += 0.0042 * w
            # Subtle closed/relaxed smile corner curve without teeth-baring grimace
            if p.z > mc.z + 0.001:
                w_cen = _gauss((p - Vector((sx * 0.006, mc.y, mc.z + 0.003))).length, 0.012)
                d.z -= 0.0012 * w_cen
        elif shape in ("mouthFrownLeft", "mouthFrownRight"):
            corner = Vector((sx * mouth_half_w, mc.y, mc.z))
            w = _gauss((p - corner).length, 0.022)
            d.z -= 0.0075 * w
        elif shape in ("mouthDimpleLeft", "mouthDimpleRight"):
            corner = Vector((sx * (mouth_half_w + 0.006), mc.y, mc.z))
            w = _gauss((p - corner).length, 0.018)
            d.x += sx * 0.0035 * w
            d.y += 0.0045 * w
        elif shape in ("mouthStretchLeft", "mouthStretchRight"):
            corner = Vector((sx * mouth_half_w, mc.y, mc.z))
            w = _gauss((p - corner).length, 0.022)
            d.x += sx * 0.0085 * w
            d.z -= 0.0018 * w
        elif shape in ("mouthRollLower", "mouthRollUpper"):
            lip_z = mc.z - 0.004 if "Lower" in shape else mc.z + 0.004
            w = _gauss((p - Vector((0.0, mc.y, lip_z))).length, 0.018)
            d.y += 0.005 * w
            d.z += (0.003 if "Lower" in shape else -0.003) * w
        elif shape in ("mouthShrugLower", "mouthShrugUpper"):
            lip_z = mc.z - 0.004 if "Lower" in shape else mc.z + 0.004
            w = _gauss((p - Vector((0.0, mc.y, lip_z))).length, 0.020)
            d.z += 0.005 * w
            d.y -= 0.0028 * w
        elif shape in ("mouthPressLeft", "mouthPressRight"):
            corner = Vector((sx * mouth_half_w * 0.7, mc.y, mc.z))
            w = _gauss((p - corner).length, 0.016)
            d.y += 0.003 * w
            d.z += (0.0025 if p.z < mc.z else -0.0025) * w
        elif shape in ("mouthUpperUpLeft", "mouthUpperUpRight"):
            pt = Vector((sx * 0.011, mc.y, mc.z + 0.005))
            w = _gauss((p - pt).length, 0.016)
            d.z += 0.0065 * w
        elif shape in ("mouthLowerDownLeft", "mouthLowerDownRight"):
            pt = Vector((sx * 0.011, mc.y, mc.z - 0.005))
            w = _gauss((p - pt).length, 0.016)
            d.z -= 0.0065 * w
        elif shape == "browInnerUp":
            w = _gauss((p - Vector((0.0, le.y - 0.008, brow_z))).length, 0.024)
            d.z += 0.0085 * w
        elif shape in ("browDownLeft", "browDownRight"):
            pt = Vector((sx * 0.026, le.y - 0.008, brow_z))
            w = _gauss((p - pt).length, 0.024)
            d.z -= 0.0080 * w
            d.x -= sx * 0.003 * w
        elif shape in ("browOuterUpLeft", "browOuterUpRight"):
            pt = Vector((sx * 0.044, le.y - 0.004, brow_z))
            w = _gauss((p - pt).length, 0.022)
            d.z += 0.0080 * w
        elif shape == "cheekPuff":
            w = max(
                _gauss((p - Vector((0.044, mc.y + 0.014, mc.z + 0.012))).length, 0.026),
                _gauss((p - Vector((-0.044, mc.y + 0.014, mc.z + 0.012))).length, 0.026),
            )
            d.x += (1.0 if p.x >= 0.0 else -1.0) * 0.009 * w
            d.y -= 0.008 * w
        elif shape in ("cheekSquintLeft", "cheekSquintRight"):
            pt = Vector((sx * 0.042, eye_c.y - 0.004, eye_c.z - 0.024))
            w = _gauss((p - pt).length, 0.025)
            d.z += 0.0065 * w
            d.y -= 0.0035 * w
        elif shape in ("noseSneerLeft", "noseSneerRight"):
            pt = Vector((sx * 0.014, nt.y + 0.005, nt.z + 0.004))
            w = _gauss((p - pt).length, 0.016)
            d.z += 0.0050 * w
        elif shape == "tongueOut":
            w = _gauss((p - mc).length, 0.015)
            d.z -= 0.002 * w
        return d

    for shape_name in ARKIT_52:
        sk = head_obj.shape_key_add(name=shape_name, from_mix=False)
        sk.value = 0.0
        for idx, v in enumerate(head_obj.data.vertices):
            sk.data[idx].co = v.co + compute_delta(shape_name, v.co)
    head_obj.active_shape_key_index = 0

    for shape_name in EYELASH_6:
        sk = lash_obj.shape_key_add(name=shape_name, from_mix=False)
        sk.value = 0.0
        for idx, v in enumerate(lash_obj.data.vertices):
            sk.data[idx].co = v.co + compute_delta(shape_name, v.co)
    lash_obj.active_shape_key_index = 0


def _purge_stray_objects() -> None:
    """Remove stray temporary objects and assert exact 16 expected modular meshes."""
    valid = set(EXPECTED_16_MESHES)
    for obj in list(bpy.data.objects):
        if obj.name not in valid:
            bpy.data.objects.remove(obj, do_unlink=True)
        elif obj.type == "MESH":
            obj.data.name = obj.name
            obj.data.validate(clean_customdata=False)
            obj.data.update()
    present = sorted(o.name for o in bpy.context.scene.objects if o.type == "MESH")
    missing = [n for n in EXPECTED_16_MESHES if n not in present]
    if missing or len(present) != 16:
        raise RuntimeError(f"Expected 16 modular meshes, got {len(present)}: {present} (missing={missing})")


# ---------------------------------------------------------------------------
# Main Build Pipeline
# ---------------------------------------------------------------------------

def main() -> None:
    clean_scene()
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    HUMANIZER_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Spawn un-morphed MPFB2 base mesh, capture basis, sculpt anime Ghost Girl at 1.58m
    bm_obj, basis_coords = _spawn_and_sculpt_anime_base()

    # 2. Fit official MPFB2 eyes, eyelashes, teeth, tongue on sculpted canonical pose
    mhclo_specs = (
        ("eyes", "high-poly/high-poly.mhclo"),
        ("eyelashes", "eyelashes01/eyelashes01.mhclo"),
        ("teeth", "teeth_base/teeth_base.mhclo"),
        ("tongue", "tongue01/tongue01.mhclo"),
    )
    fitted: Dict[str, bpy.types.Object] = {}
    for subdir, frag in mhclo_specs:
        apath = AssetService.find_asset_absolute_path(frag, subdir)
        if not apath:
            raise RuntimeError(f"Missing MPFB2 system asset: {subdir}/{frag}")
        asset_obj = HumanService.add_mhclo_asset(apath, bm_obj, asset_type=subdir.capitalize(), subdiv_levels=0)
        fitted[subdir] = asset_obj

    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in list(fitted.values()):
        eval_obj = obj.evaluated_get(depsgraph)
        clean_mesh = bpy.data.meshes.new_from_object(eval_obj)
        old_mesh = obj.data
        obj.modifiers.clear()
        obj.shape_key_clear()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data = clean_mesh
        bpy.data.meshes.remove(old_mesh)
        obj.data.update()

    # 3. Export Humanizer .target + metadata BEFORE splitting head/body or straightening arms
    b_min, b_max, s_min, s_max = _export_humanizer_target(bm_obj, basis_coords)
    lm = _measure_canonical_landmarks(bm_obj, fitted["eyes"])
    skin_alb, skin_nrm, skin_orm = _build_anime_skin_texture(bm_obj, lm, tex_size=2048)

    # 4. Build all modular meshes aligned to canonical MPFB2 pose
    eye_l_obj, eye_r_obj, eye_alb = _build_anime_eyes(fitted["eyes"])
    lash_obj, lash_alb = _build_anime_eyelashes(fitted["eyelashes"])
    _build_mouth_from_mpfb(fitted["teeth"], fitted["tongue"], lm)
    cap_obj, cards_obj, hair_alb = _build_lavender_hair(bm_obj, lm)
    hood_obj, hood_alb = _build_ghost_hood(bm_obj, lm)
    cape_alb, cape_orm = _paint_cape_texture()
    cape_canon = _build_ghost_cape(bm_obj, cape_alb, cape_orm, is_tpose=False)
    croptop_obj, croptop_alb = _build_croptop(bm_obj, lm)
    skirt_obj, skirt_alb = _build_skirt(bm_obj)
    gloves_alb, gloves_orm = _paint_gloves_textures()
    gloves_canon = _build_gloves(bm_obj, gloves_alb, gloves_orm)
    boots_obj, boots_alb = _build_boots(bm_obj)

    # 5. Export all 10 modular Humanizer assets (.mhclo + .obj + _albedo.png)
    eye_l_helpers = ("helper-l-eye",)
    eye_r_helpers = ("helper-r-eye",)
    lash_helpers = ("helper-l-eyelashes-1", "helper-l-eyelashes-2", "helper-r-eyelashes-1", "helper-r-eyelashes-2")
    body_group = ("body",)

    hum_assets_meta: List[Dict[str, object]] = []
    export_specs = (
        ("GhostGirl_Hair_Cards", cards_obj, hair_alb, body_group, "Head", 60, "hair", "CLIP", True, None),
        ("GhostGirl_Hood", hood_obj, hood_alb, body_group, "Head", 70, "headclothes", "OPAQUE", True, None),
        ("GhostGirl_Cape", cape_canon, cape_alb, body_group, "Torso", 80, "armsclothes", "BLEND", True, None),
        ("GhostGirl_CropTop", croptop_obj, croptop_alb, body_group, "Torso", 50, "torsoclothes", "OPAQUE", True, None),
        ("GhostGirl_Skirt", skirt_obj, skirt_alb, body_group, "Torso", 55, "legsclothes", "OPAQUE", True, None),
        ("GhostGirl_Gloves", gloves_canon, gloves_alb, body_group, "Hand", 50, "handsclothes", "OPAQUE", False, None),
        ("GhostGirl_Boots", boots_obj, boots_alb, body_group, "Foot", 50, "feetclothes", "OPAQUE", False, None),
        ("GhostGirl_Eye_L", eye_l_obj, eye_alb, eye_l_helpers, "Eye", 10, "lefteye", "OPAQUE", False, None),
        ("GhostGirl_Eye_R", eye_r_obj, eye_alb, eye_r_helpers, "Eye", 10, "righteye", "OPAQUE", False, None),
        ("GhostGirl_Eyelashes", lash_obj, lash_alb, lash_helpers, "Head", 20, "lefteyelash", "CLIP", True, None),
    )
    for (a_name, g_obj, a_alb, b_groups, sc_part, z_d, slot, alpha_m, dbl, del_g) in export_specs:
        meta = _export_mhclo_asset(
            bm_obj=bm_obj,
            garment_obj=g_obj,
            asset_name=a_name,
            albedo_src=a_alb,
            allowed_base_groups=b_groups,
            scale_part=sc_part,
            z_depth=z_d,
            delete_groups=del_g,
        )
        meta.update({"slot": slot, "alpha_mode": alpha_m, "double_sided": dbl, "scale_reference": sc_part})
        hum_assets_meta.append(meta)

    export_meta = {
        "character": "GhostGirl",
        "target_file": "ghost_girl_anime.target",
        "target_key": "custom_ghost_girl_anime",
        "target_unit_scale": 1.0,
        "vert_count": 19158,
        "coordinate_system": "MakeHuman_Y_up_Z_forward",
        "obj_vt_convention": "blender_bottom_up (Godot uv.y = 1.0 - vt.y)",
        "skin_texture": "ghost_girl_anime_skin.png",
        "basis_bounds": {"min": b_min, "max": b_max},
        "sculpted_bounds": {"min": s_min, "max": s_max},
        "assets": hum_assets_meta,
    }
    (HUMANIZER_DIR / "export_meta.json").write_text(json.dumps(export_meta, indent=2), encoding="utf-8")

    # Remove canonical A-pose cape & gloves objects + mesh datablocks before building T-pose counterparts
    for canon_obj in (cape_canon, gloves_canon):
        canon_mesh = canon_obj.data
        bpy.data.objects.remove(canon_obj, do_unlink=True)
        bpy.data.meshes.remove(canon_mesh)

    # 6. Strip helpers, straighten arms to T-pose, split Head & Body, build T-pose Cape & Gloves
    head_obj, body_obj = _strip_helpers_and_split_head_body(bm_obj, skin_alb, skin_nrm, skin_orm, lm)
    _build_ghost_cape(body_obj, cape_alb, cape_orm, is_tpose=True)
    _build_gloves(body_obj, gloves_alb, gloves_orm)

    # 7. Bake 52 ARKit blendshapes on GhostGirl_Head + 6 eyelid keys on GhostGirl_Eyelashes
    _bake_arkit_52_shape_keys(head_obj, lash_obj, eye_l_obj, lm)

    # 8. Validate exact 16 modular meshes and export standalone GLB
    _purge_stray_objects()
    export_godot_glb(str(TARGET_GLB), export_animations=False)
    print(f"[build_ghost_girl] Exported 16-mesh Ghost Girl -> {TARGET_GLB}")


if __name__ == "__main__":
    main()
