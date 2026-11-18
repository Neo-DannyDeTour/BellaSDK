"""Procedural weathered wooden carpenter sawhorse generator for BellaSDK (Godot 4.7).

Builds a real-world 0.78 m tall carpenter trestle (flat 2x4 top rail, vertical
I-beam spine + center bottom flange, 4 splayed A-frame 2x4 legs miter-cut flat
at ground/top, and trapezoidal plywood gusset plates with forged iron nail heads),
bakes 1024x1024 Albedo, OpenGL Tangent Normal, and ORM (AO/Roughness/Metallic)
maps in Cycles, and exports a single manifold-clean game GLB + manifest.

Usage:
    python3 tools/blender/run.py sawhorse
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.exporter import clean_scene, export_godot_glb  # noqa: E402

# ---------------------------------------------------------------------------
# Spec Constants (Meters, Blender Z-up -> glTF +Y-up)
# ---------------------------------------------------------------------------
SLUG = "sawhorse"
OUT_DIR = REPO_ROOT / "assets" / "models" / SLUG
TARGET_HEIGHT = 0.78
TOP_LENGTH = 1.04
PLANK_W = 0.089  # Nominal 2x4 width (3.5 in)
PLANK_T = 0.038  # Nominal 2x4 thickness (1.5 in)
BEVEL_W = 0.0035
TEX_SIZE = 1024
TRI_BUDGET = 1000

# Splay geometry (grounded at Z = 0.0, meeting underside of top plank at Z = 0.742)
TOP_UNDERSIDE_Z = TARGET_HEIGHT - PLANK_T
LEG_TOP_X = 0.34
LEG_BOT_X = 0.415
LEG_TOP_Y = 0.019 + PLANK_T * 0.5  # Tight against vertical I-beam web (half-thickness 0.019)
LEG_BOT_Y = 0.255  # Wide stable A-frame footprint (~0.56 m outer span)

# Gusset vertical span (wide open negative space from Z=0.0 to Z=0.45)
GUSSET_Z_BOT = 0.45
GUSSET_Z_TOP = 0.655
GUSSET_THICK = 0.018

PREVIEW_PATH = Path("/tmp/sawhorse_preview.png")


# ---------------------------------------------------------------------------
# Mesh Building Helpers
# ---------------------------------------------------------------------------
def _apply_box_grain_uv(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    grain_axis: Vector,
    scale: float = 1.6,
) -> None:
    """Assign 3D box-projected UVs with U aligned along `grain_axis`."""
    g_u = grain_axis.normalized()
    up = Vector((0.0, 0.0, 1.0)) if abs(g_u.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    g_v = g_u.cross(up).normalized()
    g_w = g_u.cross(g_v).normalized()

    for face in bm.faces:
        n = face.normal.normalized()
        # Pick secondary axis most orthogonal to face normal
        v_axis = g_v if abs(n.dot(g_v)) < abs(n.dot(g_w)) else g_w
        u_axis = g_u if abs(n.dot(g_u)) < 0.85 else (g_w if v_axis == g_v else g_v)
        for loop in face.loops:
            co = loop.vert.co
            loop[uv_layer].uv = (co.dot(u_axis) * scale, co.dot(v_axis) * scale)


def _create_beveled_box_bm(
    size: tuple[float, float, float],
    center: tuple[float, float, float],
    bevel_w: float = BEVEL_W,
    mat_index: int = 0,
    grain_axis: Vector = Vector((1.0, 0.0, 0.0)),
) -> bmesh.types.BMesh:
    """Create a watertight manifold beveled box centered at `center`."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    scale_mat = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    trans_mat = Matrix.Translation(Vector(center))
    bmesh.ops.transform(bm, matrix=trans_mat @ scale_mat, verts=bm.verts)

    if bevel_w > 0.0:
        bmesh.ops.bevel(
            bm,
            geom=list(bm.edges),
            offset=bevel_w,
            segments=1,
            profile=0.5,
            affect="EDGES",
            clamp_overlap=True,
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uv_grain = bm.loops.layers.uv.new("GrainUV")
    _apply_box_grain_uv(bm, uv_grain, grain_axis)
    for f in bm.faces:
        f.material_index = mat_index
    return bm


def _create_splayed_leg_bm(
    side_x: float,
    side_y: float,
    mat_index: int = 0,
) -> bmesh.types.BMesh:
    """Create a miter-cut splayed 2x4 leg flat at Z=0 and Z=TOP_UNDERSIDE_Z."""
    p_bot = Vector((side_x * LEG_BOT_X, side_y * LEG_BOT_Y, 0.0))
    p_top = Vector((side_x * LEG_TOP_X, side_y * LEG_TOP_Y, TOP_UNDERSIDE_Z))
    axis = (p_top - p_bot).normalized()

    # Cross-section axes orthogonal to leg axis (wide face ~along X, thickness ~along Y)
    dir_x = Vector((1.0, 0.0, 0.0))
    dir_y = axis.cross(dir_x).normalized()
    dir_x = dir_y.cross(axis).normalized()

    hx = PLANK_W * 0.5
    hy = PLANK_T * 0.5

    def _plane_intersect(p0: Vector, z_target: float) -> Vector:
        t = (z_target - p0.z) / axis.z
        return p0 + axis * t

    offsets = [
        -dir_x * hx - dir_y * hy,
        dir_x * hx - dir_y * hy,
        dir_x * hx + dir_y * hy,
        -dir_x * hx + dir_y * hy,
    ]

    bm = bmesh.new()
    bot_verts = [bm.verts.new(_plane_intersect(p_bot + off, 0.0)) for off in offsets]
    top_verts = [bm.verts.new(_plane_intersect(p_bot + off, TOP_UNDERSIDE_Z)) for off in offsets]

    # Bottom, top, and 4 side faces
    bm.faces.new(list(reversed(bot_verts)))
    bm.faces.new(top_verts)
    for i in range(4):
        ni = (i + 1) % 4
        bm.faces.new([bot_verts[i], bot_verts[ni], top_verts[ni], top_verts[i]])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=BEVEL_W * 0.85,
        segments=1,
        profile=0.5,
        affect="EDGES",
        clamp_overlap=True,
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    uv_grain = bm.loops.layers.uv.new("GrainUV")
    _apply_box_grain_uv(bm, uv_grain, axis)
    for f in bm.faces:
        f.material_index = mat_index
    return bm


def _leg_center_at_z(side_x: float, side_y: float, z: float) -> Vector:
    """Interpolate a leg centerline position at height `z`."""
    t = z / TOP_UNDERSIDE_Z
    x = side_x * (LEG_BOT_X + (LEG_TOP_X - LEG_BOT_X) * t)
    y = side_y * (LEG_BOT_Y + (LEG_TOP_Y - LEG_BOT_Y) * t)
    return Vector((x, y, z))


def _create_trapezoid_gusset_bm(
    side_x: float,
    mat_index: int = 1,
) -> tuple[bmesh.types.BMesh, list[tuple[Vector, Vector]]]:
    """Create a trapezoidal plywood gusset plate nailed to the outer A-frame face.

    Returns the gusset BMesh and a list of `(position, outward_normal)` tuples
    for placing forged nail heads on the outer gusset face.
    """
    # Compute outer face X at bottom and top of gusset span so plate hugs leg splay
    c_bot_pos = _leg_center_at_z(side_x, 1.0, GUSSET_Z_BOT)
    c_top_pos = _leg_center_at_z(side_x, 1.0, GUSSET_Z_TOP)

    # Outer X sits flush on the outer face of the splayed legs (+0.0445 m from leg center)
    x_inner_bot = side_x * (abs(c_bot_pos.x) + PLANK_W * 0.46)
    x_outer_bot = x_inner_bot + side_x * GUSSET_THICK
    x_inner_top = side_x * (abs(c_top_pos.x) + PLANK_W * 0.46)
    x_outer_top = x_inner_top + side_x * GUSSET_THICK

    # Match outer Y edges of the splayed legs tightly
    y_bot = abs(c_bot_pos.y) + PLANK_T * 0.52
    y_top = abs(c_top_pos.y) + PLANK_T * 0.52

    bm = bmesh.new()
    # 4 inner corners, 4 outer corners (counter-clockwise looking from +X)
    in_bl = bm.verts.new(Vector((x_inner_bot, -y_bot, GUSSET_Z_BOT)))
    in_br = bm.verts.new(Vector((x_inner_bot, y_bot, GUSSET_Z_BOT)))
    in_tr = bm.verts.new(Vector((x_inner_top, y_top, GUSSET_Z_TOP)))
    in_tl = bm.verts.new(Vector((x_inner_top, -y_top, GUSSET_Z_TOP)))

    out_bl = bm.verts.new(Vector((x_outer_bot, -y_bot, GUSSET_Z_BOT)))
    out_br = bm.verts.new(Vector((x_outer_bot, y_bot, GUSSET_Z_BOT)))
    out_tr = bm.verts.new(Vector((x_outer_top, y_top, GUSSET_Z_TOP)))
    out_tl = bm.verts.new(Vector((x_outer_top, -y_top, GUSSET_Z_TOP)))

    bm.faces.new([in_bl, in_tl, in_tr, in_br])
    bm.faces.new([out_bl, out_br, out_tr, out_tl])
    bm.faces.new([in_bl, out_bl, out_tl, in_tl])
    bm.faces.new([in_br, in_tr, out_tr, out_br])
    bm.faces.new([in_tl, out_tl, out_tr, in_tr])
    bm.faces.new([in_bl, in_br, out_br, out_bl])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=0.002,
        segments=1,
        profile=0.5,
        affect="EDGES",
        clamp_overlap=True,
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    uv_grain = bm.loops.layers.uv.new("GrainUV")
    _apply_box_grain_uv(bm, uv_grain, Vector((0.0, 1.0, 0.0)), scale=2.2)
    for f in bm.faces:
        f.material_index = mat_index

    # Compute 6 nail positions (3 per leg) on the outer slanted gusset face
    slope_vec = Vector((x_outer_top - x_outer_bot, 0.0, GUSSET_Z_TOP - GUSSET_Z_BOT)).normalized()
    out_normal = Vector((side_x * slope_vec.z, 0.0, -side_x * slope_vec.x)).normalized()
    if out_normal.x * side_x < 0.0:
        out_normal = -out_normal

    nails: list[tuple[Vector, Vector]] = []
    for side_y in (-1.0, 1.0):
        for frac in (0.22, 0.50, 0.78):
            z = GUSSET_Z_BOT + (GUSSET_Z_TOP - GUSSET_Z_BOT) * frac
            x_face = x_outer_bot + (x_outer_top - x_outer_bot) * frac
            y_leg = abs(_leg_center_at_z(side_x, 1.0, z).y)
            pos = Vector((x_face, side_y * y_leg, z))
            nails.append((pos, out_normal))

    return bm, nails


def _create_nail_head_bm(
    pos: Vector,
    normal: Vector,
    mat_index: int = 2,
) -> bmesh.types.BMesh:
    """Create a low-poly 5-sided forged iron nail head (8 tris)."""
    bm = bmesh.new()
    radius = 0.0085
    height = 0.0042
    sides = 5

    up = normal.normalized()
    ref = Vector((0.0, 1.0, 0.0)) if abs(up.y) < 0.9 else Vector((1.0, 0.0, 0.0))
    tan = up.cross(ref).normalized()
    bitan = up.cross(tan).normalized()

    base_v = []
    for i in range(sides):
        ang = (2.0 * math.pi * i) / sides
        pt = pos + (tan * math.cos(ang) + bitan * math.sin(ang)) * radius - up * 0.0005
        base_v.append(bm.verts.new(pt))
    apex = bm.verts.new(pos + up * height)

    # Cap base and sloped pyramid sides
    bm.faces.new(list(reversed(base_v)))
    for i in range(sides):
        ni = (i + 1) % sides
        bm.faces.new([base_v[i], base_v[ni], apex])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uv_grain = bm.loops.layers.uv.new("GrainUV")
    _apply_box_grain_uv(bm, uv_grain, tan, scale=10.0)
    for f in bm.faces:
        f.material_index = mat_index
    return bm


def _merge_bmeshes(bms: list[bmesh.types.BMesh], name: str) -> bpy.types.Object:
    """Merge multiple BMeshes into a single clean triangulated-safe Blender Mesh Object."""
    merged_mesh = bpy.data.meshes.new(name)
    final_bm = bmesh.new()

    for src_bm in bms:
        # Preserve material_index across temp_mesh transfer (bmesh.to_mesh clamps to len(materials))
        part_mat_idx = src_bm.faces[0].material_index if len(src_bm.faces) > 0 else 0
        prev_face_count = len(final_bm.faces)
        temp_mesh = bpy.data.meshes.new("_tmp_part")
        src_bm.to_mesh(temp_mesh)
        src_bm.free()
        final_bm.from_mesh(temp_mesh)
        bpy.data.meshes.remove(temp_mesh)
        final_bm.faces.ensure_lookup_table()
        for fi in range(prev_face_count, len(final_bm.faces)):
            final_bm.faces[fi].material_index = part_mat_idx

    bmesh.ops.recalc_face_normals(final_bm, faces=final_bm.faces)

    # Mark crisp plank seams (>= 48 deg) sharp while keeping beveled edges smooth
    for face in final_bm.faces:
        face.smooth = True
    for edge in final_bm.edges:
        if len(edge.link_faces) == 2:
            angle = edge.calc_face_angle(0.0)
            edge.smooth = angle < math.radians(48.0)

    # Ensure 3 material slots exist before to_mesh so material_index 0/1/2 never clamp to 0
    for _ in range(3):
        merged_mesh.materials.append(None)

    final_bm.to_mesh(merged_mesh)
    final_bm.free()

    obj = bpy.data.objects.new(name, merged_mesh)
    bpy.context.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------------------
# Procedural Weathered Wood / Plywood / Iron Shaders (Bake Source)
# ---------------------------------------------------------------------------
def _make_wood_shader(
    name: str,
    base_light: tuple[float, float, float, float],
    base_dark: tuple[float, float, float, float],
    knot_col: tuple[float, float, float, float],
    grain_stretch: tuple[float, float, float],
    rough_min: float,
    rough_max: float,
    bump_strength: float,
    plywood: bool = False,
) -> bpy.types.Material:
    """Build procedural rough-sawn pine or weathered plywood PBR shader."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    # Use GrainUV so grain follows each beam/leg axis naturally
    uv_node = nt.nodes.new("ShaderNodeUVMap")
    uv_node.uv_map = "GrainUV"

    tex_coord = nt.nodes.new("ShaderNodeTexCoord")

    # Add subtle object-space offset so each plank has unique grain/knots
    vec_add = nt.nodes.new("ShaderNodeVectorMath")
    vec_add.operation = "ADD"
    nt.links.new(uv_node.outputs["UV"], vec_add.inputs[0])

    obj_scale = nt.nodes.new("ShaderNodeVectorMath")
    obj_scale.operation = "SCALE"
    obj_scale.inputs["Scale"].default_value = 0.37
    nt.links.new(tex_coord.outputs["Object"], obj_scale.inputs[0])
    nt.links.new(obj_scale.outputs["Vector"], vec_add.inputs[1])

    # Stretched mapping for wood fibers
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = grain_stretch
    nt.links.new(vec_add.outputs["Vector"], mapping.inputs["Vector"])

    # Primary fiber noise (wave + noise distortion)
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Y"
    wave.wave_profile = "SAW" if not plywood else "SIN"
    wave.inputs["Scale"].default_value = 3.2 if not plywood else 2.4
    wave.inputs["Distortion"].default_value = 7.5 if not plywood else 5.0
    wave.inputs["Detail"].default_value = 8.0
    wave.inputs["Detail Scale"].default_value = 2.2
    wave.inputs["Detail Roughness"].default_value = 0.65
    nt.links.new(mapping.outputs["Vector"], wave.inputs["Vector"])

    # Fine rough-sawn fibrous noise
    fine_noise = nt.nodes.new("ShaderNodeTexNoise")
    fine_noise.inputs["Scale"].default_value = 28.0
    fine_noise.inputs["Detail"].default_value = 10.0
    fine_noise.inputs["Roughness"].default_value = 0.72
    nt.links.new(mapping.outputs["Vector"], fine_noise.inputs["Vector"])

    # Wood knots (Voronoi distance in stretched space)
    knot_map = nt.nodes.new("ShaderNodeMapping")
    knot_map.inputs["Scale"].default_value = (1.6, 4.2, 1.6)
    nt.links.new(vec_add.outputs["Vector"], knot_map.inputs["Vector"])

    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 1.9 if not plywood else 1.2
    nt.links.new(knot_map.outputs["Vector"], vor.inputs["Vector"])

    knot_ramp = nt.nodes.new("ShaderNodeValToRGB")
    knot_ramp.color_ramp.elements[0].position = 0.0
    knot_ramp.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
    knot_ramp.color_ramp.elements[1].position = 0.16 if not plywood else 0.11
    knot_ramp.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1.0)
    nt.links.new(vor.outputs["Distance"], knot_ramp.inputs["Fac"])

    # Blend wave + fine fiber
    fiber_mix = nt.nodes.new("ShaderNodeMath")
    fiber_mix.operation = "MULTIPLY_ADD"
    fiber_mix.inputs[1].default_value = 0.65
    nt.links.new(wave.outputs["Fac"], fiber_mix.inputs[0])

    fine_scale = nt.nodes.new("ShaderNodeMath")
    fine_scale.operation = "MULTIPLY"
    fine_scale.inputs[1].default_value = 0.35
    nt.links.new(fine_noise.outputs["Fac"], fine_scale.inputs[0])
    nt.links.new(fine_scale.outputs["Value"], fiber_mix.inputs[2])

    # Weathering grime / dust variation (low-frequency object noise)
    weather_noise = nt.nodes.new("ShaderNodeTexNoise")
    weather_noise.inputs["Scale"].default_value = 3.6
    weather_noise.inputs["Detail"].default_value = 6.0
    weather_noise.inputs["Roughness"].default_value = 0.6
    nt.links.new(tex_coord.outputs["Object"], weather_noise.inputs["Vector"])

    # Base wood color ramp (light -> dark aged pine)
    col_mix = nt.nodes.new("ShaderNodeMix")
    col_mix.data_type = "RGBA"
    col_mix.inputs["A"].default_value = base_dark
    col_mix.inputs["B"].default_value = base_light
    nt.links.new(fiber_mix.outputs["Value"], col_mix.inputs["Factor"])

    # Apply subtle dark weathered mottling
    grime_mix = nt.nodes.new("ShaderNodeMix")
    grime_mix.data_type = "RGBA"
    grime_mix.blend_type = "MULTIPLY"
    grime_mix.inputs["Factor"].default_value = 0.28
    nt.links.new(col_mix.outputs["Result"], grime_mix.inputs["A"])

    grime_ramp = nt.nodes.new("ShaderNodeValToRGB")
    grime_ramp.color_ramp.elements[0].position = 0.25
    grime_ramp.color_ramp.elements[0].color = (0.58, 0.55, 0.50, 1.0)
    grime_ramp.color_ramp.elements[1].position = 0.78
    grime_ramp.color_ramp.elements[1].color = (1.0, 0.99, 0.96, 1.0)
    nt.links.new(weather_noise.outputs["Fac"], grime_ramp.inputs["Fac"])
    nt.links.new(grime_ramp.outputs["Color"], grime_mix.inputs["B"])

    # Darken wood knots
    knot_mix = nt.nodes.new("ShaderNodeMix")
    knot_mix.data_type = "RGBA"
    knot_mix.inputs["B"].default_value = knot_col
    nt.links.new(knot_ramp.outputs["Color"], knot_mix.inputs["Factor"])
    nt.links.new(grime_mix.outputs["Result"], knot_mix.inputs["A"])

    # Subtle edge wear / scuffing on top plank & beveled corners via Z + noise
    sep_xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tex_coord.outputs["Object"], sep_xyz.inputs["Vector"])

    # Feet mud/damp darkening near Z = 0..0.14m
    foot_ramp = nt.nodes.new("ShaderNodeMapRange")
    foot_ramp.clamp = True
    foot_ramp.inputs["From Min"].default_value = 0.0
    foot_ramp.inputs["From Max"].default_value = 0.14
    foot_ramp.inputs["To Min"].default_value = 0.72
    foot_ramp.inputs["To Max"].default_value = 1.0
    nt.links.new(sep_xyz.outputs["Z"], foot_ramp.inputs["Value"])

    # Top plank lighter rubbed wear near Z = 0.74..0.78m
    top_wear = nt.nodes.new("ShaderNodeMapRange")
    top_wear.clamp = True
    top_wear.inputs["From Min"].default_value = 0.74
    top_wear.inputs["From Max"].default_value = 0.78
    top_wear.inputs["To Min"].default_value = 0.0
    top_wear.inputs["To Max"].default_value = 0.22
    nt.links.new(sep_xyz.outputs["Z"], top_wear.inputs["Value"])

    foot_tint = nt.nodes.new("ShaderNodeMix")
    foot_tint.data_type = "RGBA"
    foot_tint.blend_type = "MULTIPLY"
    foot_tint.inputs["Factor"].default_value = 1.0
    nt.links.new(knot_mix.outputs["Result"], foot_tint.inputs["A"])
    nt.links.new(foot_ramp.outputs["Result"], foot_tint.inputs["B"])

    wear_tint = nt.nodes.new("ShaderNodeMix")
    wear_tint.data_type = "RGBA"
    wear_tint.inputs["B"].default_value = (
        min(base_light[0] * 1.18, 1.0),
        min(base_light[1] * 1.15, 1.0),
        min(base_light[2] * 1.12, 1.0),
        1.0,
    )
    nt.links.new(top_wear.outputs["Result"], wear_tint.inputs["Factor"])
    nt.links.new(foot_tint.outputs["Result"], wear_tint.inputs["A"])

    albedo_out = wear_tint.outputs["Result"]
    nt.links.new(albedo_out, bsdf.inputs["Base Color"])

    # Roughness: rough-sawn pine [rough_min..rough_max], slightly smoother on worn top plank
    rough_map = nt.nodes.new("ShaderNodeMapRange")
    rough_map.clamp = True
    rough_map.inputs["From Min"].default_value = 0.0
    rough_map.inputs["From Max"].default_value = 1.0
    rough_map.inputs["To Min"].default_value = rough_min
    rough_map.inputs["To Max"].default_value = rough_max
    nt.links.new(fiber_mix.outputs["Value"], rough_map.inputs["Value"])

    rough_wear = nt.nodes.new("ShaderNodeMath")
    rough_wear.operation = "SUBTRACT"
    nt.links.new(rough_map.outputs["Result"], rough_wear.inputs[0])

    wear_rough_delta = nt.nodes.new("ShaderNodeMath")
    wear_rough_delta.operation = "MULTIPLY"
    wear_rough_delta.inputs[1].default_value = 0.35
    nt.links.new(top_wear.outputs["Result"], wear_rough_delta.inputs[0])
    nt.links.new(wear_rough_delta.outputs["Value"], rough_wear.inputs[1])

    rough_clamp = nt.nodes.new("ShaderNodeClamp")
    rough_clamp.inputs["Min"].default_value = 0.72
    rough_clamp.inputs["Max"].default_value = 0.96
    nt.links.new(rough_wear.outputs["Value"], rough_clamp.inputs["Value"])
    nt.links.new(rough_clamp.outputs["Result"], bsdf.inputs["Roughness"])

    # Bump height: wood fibers + recessed knots + faint transverse saw marks
    saw_wave = nt.nodes.new("ShaderNodeTexWave")
    saw_wave.wave_type = "BANDS"
    saw_wave.bands_direction = "X"
    saw_wave.inputs["Scale"].default_value = 22.0
    saw_wave.inputs["Distortion"].default_value = 0.6
    nt.links.new(uv_node.outputs["UV"], saw_wave.inputs["Vector"])

    bump_sum = nt.nodes.new("ShaderNodeMath")
    bump_sum.operation = "MULTIPLY_ADD"
    bump_sum.inputs[1].default_value = 0.85
    nt.links.new(fiber_mix.outputs["Value"], bump_sum.inputs[0])

    saw_scale = nt.nodes.new("ShaderNodeMath")
    saw_scale.operation = "MULTIPLY"
    saw_scale.inputs[1].default_value = 0.15
    nt.links.new(saw_wave.outputs["Fac"], saw_scale.inputs[0])
    nt.links.new(saw_scale.outputs["Value"], bump_sum.inputs[2])

    bump_node = nt.nodes.new("ShaderNodeBump")
    bump_node.inputs["Strength"].default_value = bump_strength
    bump_node.inputs["Distance"].default_value = 0.004
    nt.links.new(bump_sum.outputs["Value"], bump_node.inputs["Height"])
    nt.links.new(bump_node.outputs["Normal"], bsdf.inputs["Normal"])

    # Tag helper sockets via custom node names for fast EMIT channel baking
    wear_tint.name = "BAKE_ALBEDO"
    rough_clamp.name = "BAKE_ROUGHNESS"
    return mat


def _make_nail_shader(name: str = "Src_IronNail") -> bpy.types.Material:
    """Build dark rusted galvanized iron nail head shader."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.14, 0.12, 0.11, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.88
    bsdf.inputs["Roughness"].default_value = 0.56
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    # Explicit value nodes so EMIT baking pipeline works uniformly across materials
    albedo_rgb = nt.nodes.new("ShaderNodeRGB")
    albedo_rgb.name = "BAKE_ALBEDO"
    albedo_rgb.outputs[0].default_value = (0.14, 0.12, 0.11, 1.0)
    nt.links.new(albedo_rgb.outputs[0], bsdf.inputs["Base Color"])

    rough_val = nt.nodes.new("ShaderNodeValue")
    rough_val.name = "BAKE_ROUGHNESS"
    rough_val.outputs[0].default_value = 0.56
    nt.links.new(rough_val.outputs[0], bsdf.inputs["Roughness"])

    metal_val = nt.nodes.new("ShaderNodeValue")
    metal_val.name = "BAKE_METALLIC"
    metal_val.outputs[0].default_value = 0.88
    nt.links.new(metal_val.outputs[0], bsdf.inputs["Metallic"])
    return mat


# ---------------------------------------------------------------------------
# Baking & Packing
# ---------------------------------------------------------------------------
def _bake_channel_emit(
    obj: bpy.types.Object,
    img: bpy.types.Image,
    channel: str,
    samples: int = 4,
) -> None:
    """Temporarily wire a shader channel (ALBEDO/ROUGHNESS/METALLIC/AO) to Emission and bake."""
    scene = bpy.context.scene
    scene.cycles.samples = samples

    saved_links: list[tuple[bpy.types.NodeTree, bpy.types.NodeSocket]] = []
    temp_nodes: list[tuple[bpy.types.NodeTree, list[bpy.types.Node]]] = []

    for mat in obj.data.materials:
        nt = mat.node_tree
        out_node = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        surf_in = out_node.inputs["Surface"]
        if surf_in.links:
            saved_links.append((nt, surf_in.links[0].from_socket))
        else:
            saved_links.append((nt, None))

        created: list[bpy.types.Node] = []
        emit = nt.nodes.new("ShaderNodeEmission")
        emit.inputs["Strength"].default_value = 1.0
        created.append(emit)

        tex_node = nt.nodes.new("ShaderNodeTexImage")
        tex_node.image = img
        created.append(tex_node)
        nt.nodes.active = tex_node

        if channel == "ALBEDO":
            src = nt.nodes.get("BAKE_ALBEDO")
            out_sock = src.outputs["Result"] if "Result" in src.outputs else src.outputs[0]
            nt.links.new(out_sock, emit.inputs["Color"])
        elif channel == "ROUGHNESS":
            src = nt.nodes.get("BAKE_ROUGHNESS")
            out_sock = src.outputs["Result"] if "Result" in src.outputs else src.outputs[0]
            nt.links.new(out_sock, emit.inputs["Color"])
        elif channel == "METALLIC":
            src = nt.nodes.get("BAKE_METALLIC")
            if src is not None:
                nt.links.new(src.outputs[0], emit.inputs["Color"])
            else:
                emit.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        elif channel == "AO":
            ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
            ao.samples = 16
            ao.only_local = True
            ao.inputs["Distance"].default_value = 0.32
            created.append(ao)
            nt.links.new(ao.outputs["AO"], emit.inputs["Color"])

        nt.links.new(emit.outputs["Emission"], surf_in)
        temp_nodes.append((nt, created))

    bpy.ops.object.bake(type="EMIT")

    # Restore original BSDF wiring
    for (nt, orig_sock), (_, created) in zip(saved_links, temp_nodes):
        out_node = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        for node in created:
            nt.nodes.remove(node)
        if orig_sock is not None:
            nt.links.new(orig_sock, out_node.inputs["Surface"])


def _bake_normal_map(obj: bpy.types.Object, img: bpy.types.Image) -> None:
    """Bake OpenGL (+X, +Y, +Z) tangent-space normal map from procedural bump."""
    scene = bpy.context.scene
    scene.cycles.samples = 4
    scene.render.bake.normal_space = "TANGENT"
    scene.render.bake.normal_r = "POS_X"
    scene.render.bake.normal_g = "POS_Y"
    scene.render.bake.normal_b = "POS_Z"

    temp_tex_nodes: list[tuple[bpy.types.NodeTree, bpy.types.Node]] = []
    for mat in obj.data.materials:
        nt = mat.node_tree
        tex_node = nt.nodes.new("ShaderNodeTexImage")
        tex_node.image = img
        nt.nodes.active = tex_node
        temp_tex_nodes.append((nt, tex_node))

    bpy.ops.object.bake(type="NORMAL")

    for nt, tex_node in temp_tex_nodes:
        nt.nodes.remove(tex_node)


def _save_image(img: bpy.types.Image, path: Path) -> None:
    """Save a Blender image as uncompressed/standard RGB PNG."""
    path.parent.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()


def _render_preview(obj: bpy.types.Object, out_png: Path) -> None:
    """Render a quick 512x512 3/4 studio preview to inspect silhouette and textures."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(out_png)

    # Neutral bright studio world
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.38, 0.40, 0.42, 1.0)
        bg.inputs["Strength"].default_value = 1.0
    scene.world = world

    # Key + fill sun lights
    key_data = bpy.data.lights.new("KeyLight", type="SUN")
    key_data.energy = 2.6
    key_obj = bpy.data.objects.new("KeyLight", key_data)
    key_obj.rotation_euler = Euler((math.radians(52), math.radians(15), math.radians(38)), "XYZ")
    bpy.context.collection.objects.link(key_obj)

    fill_data = bpy.data.lights.new("FillLight", type="AREA")
    fill_data.energy = 45.0
    fill_data.size = 2.5
    fill_obj = bpy.data.objects.new("FillLight", fill_data)
    fill_obj.location = (-1.6, 1.8, 1.4)
    direction = Vector((0.0, 0.0, 0.39)) - fill_obj.location
    fill_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(fill_obj)

    # 3/4 Camera framed on sawhorse center
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 52.0
    cam_obj = bpy.data.objects.new("PreviewCam", cam_data)
    cam_obj.location = (1.35, -1.45, 0.92)
    look_vec = Vector((0.0, 0.0, 0.37)) - cam_obj.location
    cam_obj.rotation_euler = look_vec.to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    bpy.ops.render.render(write_still=True)

    # Cleanup preview helpers so they never leak into GLB export
    for helper in (key_obj, fill_obj, cam_obj):
        bpy.data.objects.remove(helper, do_unlink=True)
    scene.camera = None


# ---------------------------------------------------------------------------
# Main Build Pipeline
# ---------------------------------------------------------------------------
def build_sawhorse() -> None:
    clean_scene()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    parts: list[bmesh.types.BMesh] = []

    # 1. Flat horizontal 2x4 top plank (Z: 0.742..0.780)
    parts.append(
        _create_beveled_box_bm(
            size=(TOP_LENGTH, PLANK_W, PLANK_T),
            center=(0.0, 0.0, TARGET_HEIGHT - PLANK_T * 0.5),
            mat_index=0,
            grain_axis=Vector((1.0, 0.0, 0.0)),
        )
    )

    # 2. Vertical center I-beam cleat / spine (Z: 0.653..0.743, tucked under top plank)
    spine_h = PLANK_W
    spine_z = TOP_UNDERSIDE_Z - spine_h * 0.5 + 0.001
    parts.append(
        _create_beveled_box_bm(
            size=(0.94, PLANK_T, spine_h),
            center=(0.0, 0.0, spine_z),
            mat_index=0,
            grain_axis=Vector((1.0, 0.0, 0.0)),
        )
    )

    # 3. Bottom I-beam flange between the leg pairs (completes authentic I-beam top rail)
    flange_t = 0.022
    flange_z = TOP_UNDERSIDE_Z - spine_h - flange_t * 0.5 + 0.003
    parts.append(
        _create_beveled_box_bm(
            size=(0.56, 0.072, flange_t),
            center=(0.0, 0.0, flange_z),
            mat_index=0,
            grain_axis=Vector((1.0, 0.0, 0.0)),
        )
    )

    # 4. Four splayed A-frame 2x4 timber legs (grounded at Z=0, flush at top plank)
    for side_x in (-1.0, 1.0):
        for side_y in (-1.0, 1.0):
            parts.append(_create_splayed_leg_bm(side_x, side_y, mat_index=0))

    # 5. Trapezoidal plywood gusset plates + forged iron nail heads (left & right A-frames)
    all_nails: list[tuple[Vector, Vector]] = []
    for side_x in (-1.0, 1.0):
        gusset_bm, nails = _create_trapezoid_gusset_bm(side_x, mat_index=1)
        parts.append(gusset_bm)
        all_nails.extend(nails)

    for nail_pos, nail_nrm in all_nails:
        parts.append(_create_nail_head_bm(nail_pos, nail_nrm, mat_index=2))

    obj = _merge_bmeshes(parts, "Sawhorse")

    # Verify grounding & exact height
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    min_z = min(v.z for v in bbox)
    max_z = max(v.z for v in bbox)
    if abs(min_z) > 1e-5:
        obj.location.z -= min_z
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=True)
        bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        min_z = min(v.z for v in bbox)
        max_z = max(v.z for v in bbox)

    dims = (
        max(v.x for v in bbox) - min(v.x for v in bbox),
        max(v.y for v in bbox) - min(v.y for v in bbox),
        max_z - min_z,
    )

    # Create final packed atlas UVMap (active for baking & Godot export)
    mesh = obj.data
    atlas_uv = mesh.uv_layers.new(name="UVMap")
    mesh.uv_layers.active = atlas_uv
    mesh.uv_layers.active_index = list(mesh.uv_layers).index(atlas_uv)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(
        angle_limit=math.radians(60.0),
        island_margin=0.015,
        area_weight=0.0,
        correct_aspect=True,
        scale_to_bounds=False,
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    # Attach procedural bake-source materials (slot 0: pine lumber, slot 1: plywood, slot 2: iron)
    mat_pine = _make_wood_shader(
        name="Src_WeatheredPine",
        base_light=(0.31, 0.20, 0.115, 1.0),
        base_dark=(0.11, 0.070, 0.042, 1.0),
        knot_col=(0.035, 0.020, 0.012, 1.0),
        grain_stretch=(0.9, 5.5, 1.0),
        rough_min=0.82,
        rough_max=0.94,
        bump_strength=0.45,
        plywood=False,
    )
    mat_ply = _make_wood_shader(
        name="Src_WeatheredPlywood",
        base_light=(0.40, 0.30, 0.19, 1.0),
        base_dark=(0.20, 0.145, 0.092, 1.0),
        knot_col=(0.060, 0.038, 0.022, 1.0),
        grain_stretch=(1.2, 3.8, 1.0),
        rough_min=0.80,
        rough_max=0.92,
        bump_strength=0.30,
        plywood=True,
    )
    mat_nail = _make_nail_shader()

    mesh.materials[0] = mat_pine
    mesh.materials[1] = mat_ply
    mesh.materials[2] = mat_nail

    # Configure Cycles CPU bake
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = False
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 12
    scene.render.bake.margin_type = "ADJACENT_FACES"

    # Allocate 1024x1024 bake target images
    albedo_img = bpy.data.images.new("sawhorse_albedo", width=TEX_SIZE, height=TEX_SIZE, alpha=False)
    albedo_img.colorspace_settings.name = "sRGB"

    ao_img = bpy.data.images.new("sawhorse_ao", width=TEX_SIZE, height=TEX_SIZE, alpha=False)
    ao_img.colorspace_settings.name = "Non-Color"

    rough_img = bpy.data.images.new("sawhorse_rough", width=TEX_SIZE, height=TEX_SIZE, alpha=False)
    rough_img.colorspace_settings.name = "Non-Color"

    metal_img = bpy.data.images.new("sawhorse_metal", width=TEX_SIZE, height=TEX_SIZE, alpha=False)
    metal_img.colorspace_settings.name = "Non-Color"

    normal_img = bpy.data.images.new("sawhorse_normal", width=TEX_SIZE, height=TEX_SIZE, alpha=False)
    normal_img.colorspace_settings.name = "Non-Color"

    print("[Sawhorse] Baking 1024x1024 Albedo, AO, Roughness, Metallic, Normal...")
    _bake_channel_emit(obj, albedo_img, "ALBEDO", samples=4)
    _bake_channel_emit(obj, ao_img, "AO", samples=24)
    _bake_channel_emit(obj, rough_img, "ROUGHNESS", samples=4)
    _bake_channel_emit(obj, metal_img, "METALLIC", samples=4)
    _bake_normal_map(obj, normal_img)

    # Pack ORM texture: R = AO (subtle crevice 0.72..1.0), G = Roughness, B = Metallic
    ao_px = np.array(ao_img.pixels[:], dtype=np.float32).reshape((TEX_SIZE, TEX_SIZE, 4))[:, :, 0]
    rough_px = np.array(rough_img.pixels[:], dtype=np.float32).reshape((TEX_SIZE, TEX_SIZE, 4))[:, :, 0]
    metal_px = np.array(metal_img.pixels[:], dtype=np.float32).reshape((TEX_SIZE, TEX_SIZE, 4))[:, :, 0]

    ao_calibrated = np.clip(0.72 + 0.28 * ao_px, 0.70, 1.0)
    orm_rgba = np.ones((TEX_SIZE, TEX_SIZE, 4), dtype=np.float32)
    orm_rgba[:, :, 0] = ao_calibrated
    orm_rgba[:, :, 1] = np.clip(rough_px, 0.40, 0.96)
    orm_rgba[:, :, 2] = np.clip(metal_px, 0.0, 1.0)

    orm_img = bpy.data.images.new("sawhorse_orm", width=TEX_SIZE, height=TEX_SIZE, alpha=False)
    orm_img.colorspace_settings.name = "Non-Color"
    orm_img.pixels[:] = orm_rgba.ravel()

    albedo_path = OUT_DIR / f"{SLUG}_albedo.png"
    orm_path = OUT_DIR / f"{SLUG}_orm.png"
    normal_path = OUT_DIR / f"{SLUG}_normal.png"

    _save_image(albedo_img, albedo_path)
    _save_image(orm_img, orm_path)
    _save_image(normal_img, normal_path)

    # Drop temporary GrainUV so game mesh has exactly 1 clean UV layer (`UVMap`)
    grain_uv = mesh.uv_layers.get("GrainUV")
    if grain_uv is not None:
        mesh.uv_layers.remove(grain_uv)
    mesh.uv_layers.active = mesh.uv_layers[0]

    # Replace bake-source materials with single clean PBR/ORM material for GLB export
    final_mat = bpy.data.materials.new(name="M_Sawhorse")
    final_mat.use_nodes = True
    nt = final_mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_albedo = nt.nodes.new("ShaderNodeTexImage")
    tex_albedo.image = bpy.data.images.load(str(albedo_path))
    tex_albedo.image.colorspace_settings.name = "sRGB"
    nt.links.new(tex_albedo.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.image = bpy.data.images.load(str(orm_path))
    tex_orm.image.colorspace_settings.name = "Non-Color"
    sep_orm = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_orm.outputs["Color"], sep_orm.inputs["Color"])
    nt.links.new(sep_orm.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep_orm.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.image = bpy.data.images.load(str(normal_path))
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_map = nt.nodes.new("ShaderNodeNormalMap")
    nrm_map.inputs["Strength"].default_value = 1.0
    nt.links.new(tex_nrm.outputs["Color"], nrm_map.inputs["Color"])
    nt.links.new(nrm_map.outputs["Normal"], bsdf.inputs["Normal"])

    mesh.materials.clear()
    mesh.materials.append(final_mat)
    for poly in mesh.polygons:
        poly.material_index = 0

    # Render quick preview image with baked textures before stripping for lightweight GLB
    _render_preview(obj, PREVIEW_PATH)

    # Strip embedded texture links so GLB stays ~25 KB and Godot binds external sawhorse.tres
    nt.nodes.clear()
    out_clean = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf_clean = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_clean.inputs["Base Color"].default_value = (0.28, 0.19, 0.12, 1.0)
    bsdf_clean.inputs["Roughness"].default_value = 0.88
    bsdf_clean.inputs["Metallic"].default_value = 0.0
    nt.links.new(bsdf_clean.outputs["BSDF"], out_clean.inputs["Surface"])

    # Count triangulated polygons
    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    print(f"[Sawhorse] Tri count: {tri_count} (budget: {TRI_BUDGET}) | Dims (XYZ m): {dims}")
    assert tri_count <= TRI_BUDGET, f"Tri count {tri_count} exceeds budget {TRI_BUDGET}!"

    # Export clean GLB
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    glb_path = export_godot_glb(
        OUT_DIR / f"{SLUG}.glb",
        export_animations=False,
        apply_modifiers=True,
        only_selected=True,
    )

    # Write BellaSDK asset_manifest.json
    manifest = {
        "slug": SLUG,
        "layer": "Layer 1 Environment",
        "source": "blender_procedural_bpy",
        "tri_count": tri_count,
        "tri_budget": TRI_BUDGET,
        "uv_layers": len(mesh.uv_layers),
        "dimensions_m": {
            "width_x": round(dims[0], 4),
            "height_y": round(dims[2], 4),
            "depth_z": round(dims[1], 4),
        },
        "collision_hint": "compound_box_shapes",
        "mesh": f"res://assets/models/{SLUG}/{SLUG}.glb",
        "material": f"res://assets/models/{SLUG}/{SLUG}.tres",
        "scene": "res://props/sawhorse/sawhorse.tscn",
        "textures": {
            "albedo": f"res://assets/models/{SLUG}/{SLUG}_albedo.png",
            "orm": f"res://assets/models/{SLUG}/{SLUG}_orm.png",
            "normal": f"res://assets/models/{SLUG}/{SLUG}_normal.png",
        },
    }
    manifest_path = OUT_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[Sawhorse] Manifest written -> {manifest_path}")
    print(f"[Sawhorse] Preview rendered -> {PREVIEW_PATH}")
    print(f"[Sawhorse] Done -> {glb_path}")


if __name__ == "__main__":
    build_sawhorse()
