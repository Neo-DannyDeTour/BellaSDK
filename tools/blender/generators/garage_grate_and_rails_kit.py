"""Headless Blender generator for Old Garage Wave 1A structural kits (Full PBR + 2.5mm Bevels).

Generates:
  - Modular grate floors (no handrails, no attached gussets):
      grate_floor_2x1_2m.glb, grate_floor_2x2m.glb,
      grate_floor_1x1_2m.glb, grate_floor_damaged_2x1_2m.glb
  - Separate under-deck triangular gusset bracket:
      grate_gusset_triangle.glb
  - 4 industrial handrail types + corner post:
      handrail_pipe_2m.glb, handrail_flatbar_2m.glb,
      handrail_mesh_2m.glb, handrail_bent_damaged_2m.glb,
      handrail_post_corner.glb
  - Broken metal stairs (\\_ shape):
      broken_metal_stairs_lshape.glb
"""

from __future__ import annotations

import math
import os
import sys
import bpy
import bmesh
from mathutils import Matrix, Vector

_BLENDER_DIR: str = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if _BLENDER_DIR not in sys.path:
    sys.path.insert(0, _BLENDER_DIR)

from common.garage_pbr import apply_metric_box_uv, bevel_sharp_edges, load_project_pbr  # noqa: E402

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT_DIR: str = os.path.join(REPO_ROOT, "assets", "models", "garage_structure")
CATWALK_TEX_DIR: str = os.path.join(REPO_ROOT, "assets", "models", "props", "catwalk", "textures")

FRAME_H: float = 0.10
FRAME_FLANGE: float = 0.06
FRAME_T: float = 0.008
DECK_RECESS_Z: float = -0.015


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for blk in list(col):
            if blk.users == 0:
                col.remove(blk)


def load_image_safe(path: str, colorspace: str = "sRGB") -> bpy.types.Image | None:
    if not os.path.isfile(path):
        return None
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = colorspace
    return img


def build_grate_deck_mat() -> bpy.types.Material:
    mat = bpy.data.materials.new(name="M_Garage_Grate_Deck")
    mat.use_nodes = True
    if hasattr(mat, "blend_method"):
        mat.blend_method = "CLIP"
    if hasattr(mat, "alpha_threshold"):
        mat.alpha_threshold = 0.5
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.82
    bsdf.inputs["Roughness"].default_value = 0.70
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    for fname, cs, dst in (
        ("M_Grate_Deck_BaseColor.png", "sRGB", "Base Color"),
        ("M_Grate_Deck_Roughness.png", "Non-Color", "Roughness"),
        ("M_Grate_Deck_Alpha.png", "Non-Color", "Alpha"),
    ):
        img = load_image_safe(os.path.join(CATWALK_TEX_DIR, fname), cs)
        if img:
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = img
            links.new(tex.outputs["Color"], bsdf.inputs[dst])

    n_img = load_image_safe(os.path.join(CATWALK_TEX_DIR, "M_Grate_Deck_Normal.png"), "Non-Color")
    if n_img:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = n_img
        nmap = nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = 0.85
        links.new(tex.outputs["Color"], nmap.inputs["Color"])
        links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def get_materials() -> dict[str, bpy.types.Material]:
    return {
        "frame": load_project_pbr("pillar_rusted_truss_steel", "M_Garage_Steel_Frame", metallic_fallback=0.78),
        "grate": build_grate_deck_mat(),
        "rail": load_project_pbr("fence_door_metal", "M_Garage_Railing_Steel", metallic_fallback=0.68),
        "tread": load_project_pbr("steel_diamond_plate", "M_Garage_DiamondPlate", metallic_fallback=0.82),
    }


def add_box(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    xform: Matrix | None = None,
) -> None:
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    cx, cy, cz = (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5
    sx, sy, sz = max(abs(x1 - x0), 1e-4), max(abs(y1 - y0), 1e-4), max(abs(z1 - z0), 1e-4)
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    if xform is not None:
        m = xform @ m
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    vset = set(res["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def add_cylinder(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    radius: float,
    segments: int = 12,
    mat_idx: int = 0,
) -> None:
    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return
    mid = (p0 + p1) * 0.5
    rot = vec.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    xf = Matrix.Translation(mid) @ rot
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=length,
        matrix=xf,
    )
    vset = set(res["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def apply_deck_uv(obj: bpy.types.Object, tile_x: float = 2.0, tile_y: float = 1.2) -> None:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.x / tile_x + 0.5, co.y / tile_y + 0.5)
    bm.to_mesh(mesh)
    bm.free()


def finalize_mesh(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    uv_mode: str = "box",
    uv_scale: float = 1.0,
    bevel_offset: float = 0.0025,
) -> bpy.types.Object:
    if bevel_offset > 0.0:
        bevel_sharp_edges(bm, offset=bevel_offset, angle_deg=38.0)

    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = False
    thresh = math.radians(38.0)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) <= thresh:
            e.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        obj.data.materials.append(mat)
    if uv_mode == "deck":
        apply_deck_uv(obj)
    else:
        apply_metric_box_uv(obj, tiles_per_m=uv_scale)
    return obj


def export_glb(filename: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_normals=True,
        export_texcoords=True,
    )
    print(f"[garage_grate_and_rails_kit] Exported: {out_path}")


def build_grate_floor(width: float, depth: float, filename: str, damaged: bool = False) -> None:
    clear_scene()
    mats = get_materials()
    hw, hd = width * 0.5, depth * 0.5
    t, fl = FRAME_T, FRAME_FLANGE

    bm_frame = bmesh.new()
    for y_sign in (-1.0, 1.0):
        y_outer = y_sign * hd
        y_web_in = y_outer - y_sign * t
        y_fl_in = y_outer - y_sign * fl
        y0, y1 = min(y_outer, y_web_in), max(y_outer, y_web_in)
        fy0, fy1 = min(y_outer, y_fl_in), max(y_outer, y_fl_in)
        add_box(bm_frame, (-hw, y0, -FRAME_H), (hw, y1, 0.0), 0)
        add_box(bm_frame, (-hw, fy0, -t), (hw, fy1, 0.0), 0)
        add_box(bm_frame, (-hw, fy0, -FRAME_H), (hw, fy1, -FRAME_H + t), 0)

    for x_sign in (-1.0, 1.0):
        x_outer = x_sign * hw
        x_web_in = x_outer - x_sign * t
        x_fl_in = x_outer - x_sign * fl
        x0, x1 = min(x_outer, x_web_in), max(x_outer, x_web_in)
        fx0, fx1 = min(x_outer, x_fl_in), max(x_outer, x_fl_in)
        add_box(bm_frame, (x0, -hd, -FRAME_H), (x1, hd, 0.0), 0)
        add_box(bm_frame, (fx0, -hd, -t), (fx1, hd, 0.0), 0)
        add_box(bm_frame, (fx0, -hd, -FRAME_H), (fx1, hd, -FRAME_H + t), 0)

    rib_count = max(1, int(round(width / 0.65)) - 1)
    for i in range(1, rib_count + 1):
        rx = -hw + width * (i / (rib_count + 1))
        if damaged and i == rib_count:
            tilt = Matrix.Translation((rx, -0.1, -0.08)) @ Matrix.Rotation(math.radians(24.0), 4, "X")
            add_box(bm_frame, (-0.015, -hd * 0.45, -0.05), (0.015, hd * 0.45, 0.0), 0, tilt)
        else:
            add_box(bm_frame, (rx - 0.012, -hd + t, -FRAME_H + 0.015), (rx + 0.012, hd - t, DECK_RECESS_Z - 0.004), 0)

    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            bx, by = sx * (hw - 0.03), sy * (hd - 0.03)
            add_box(bm_frame, (bx - 0.012, by - 0.012, 0.0), (bx + 0.012, by + 0.012, 0.008), 0)

    finalize_mesh("GrateFrame", bm_frame, [mats["frame"]], uv_mode="box", uv_scale=1.1, bevel_offset=0.0015)

    bm_deck = bmesh.new()
    if not damaged:
        v0 = bm_deck.verts.new((-hw + t, -hd + t, DECK_RECESS_Z))
        v1 = bm_deck.verts.new((hw - t, -hd + t, DECK_RECESS_Z))
        v2 = bm_deck.verts.new((hw - t, hd - t, DECK_RECESS_Z))
        v3 = bm_deck.verts.new((-hw + t, hd - t, DECK_RECESS_Z))
        bm_deck.faces.new((v0, v1, v2, v3))
        v4 = bm_deck.verts.new((-hw + t, -hd + t, DECK_RECESS_Z - 0.008))
        v5 = bm_deck.verts.new((-hw + t, hd - t, DECK_RECESS_Z - 0.008))
        v6 = bm_deck.verts.new((hw - t, hd - t, DECK_RECESS_Z - 0.008))
        v7 = bm_deck.verts.new((hw - t, -hd + t, DECK_RECESS_Z - 0.008))
        bm_deck.faces.new((v4, v5, v6, v7))
    else:
        for z_off, rev in ((0.0, False), (-0.008, True)):
            v0 = bm_deck.verts.new((-hw + t, -hd + t, DECK_RECESS_Z + z_off))
            v1 = bm_deck.verts.new((0.15, -hd + t, DECK_RECESS_Z + z_off))
            v2 = bm_deck.verts.new((-0.05, hd - t, DECK_RECESS_Z + z_off))
            v3 = bm_deck.verts.new((-hw + t, hd - t, DECK_RECESS_Z + z_off))
            bm_deck.faces.new((v3, v2, v1, v0) if rev else (v0, v1, v2, v3))
            d0 = bm_deck.verts.new((0.15, -hd + t, DECK_RECESS_Z + z_off))
            d1 = bm_deck.verts.new((hw - 0.22, -hd + 0.25, -0.26 + z_off))
            d2 = bm_deck.verts.new((0.55, 0.15, -0.32 + z_off))
            d3 = bm_deck.verts.new((-0.05, 0.20, DECK_RECESS_Z + z_off))
            bm_deck.faces.new((d3, d2, d1, d0) if rev else (d0, d1, d2, d3))

    finalize_mesh("GrateDeck", bm_deck, [mats["grate"]], uv_mode="deck", bevel_offset=0.0)
    export_glb(filename)


def build_gusset_triangle() -> None:
    clear_scene()
    mats = get_materials()
    bm = bmesh.new()
    depth_y, drop_z, thick, flange_w = 0.65, 0.55, 0.016, 0.09
    add_box(bm, (-flange_w * 0.5, -depth_y, -0.014), (flange_w * 0.5, 0.0, 0.0), 0)
    add_box(bm, (-flange_w * 0.5, -0.016, -drop_z), (flange_w * 0.5, 0.0, 0.0), 0)

    hx = thick * 0.5
    tri_pts = [(0.0, -0.014), (-depth_y + 0.02, -0.014), (-0.016, -drop_z + 0.02)]
    front_v = [bm.verts.new((hx, y, z)) for (y, z) in tri_pts]
    back_v = [bm.verts.new((-hx, y, z)) for (y, z) in tri_pts]
    bm.faces.new(front_v)
    bm.faces.new(list(reversed(back_v)))
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((front_v[i], back_v[i], back_v[j], front_v[j]))

    p_top = Vector((0.0, -depth_y + 0.02, -0.014))
    p_bot = Vector((0.0, -0.016, -drop_z + 0.02))
    hyp = p_bot - p_top
    xf_hyp = Matrix.Translation((p_top + p_bot) * 0.5) @ Matrix.Rotation(math.atan2(hyp.z, hyp.y), 4, "X")
    add_box(bm, (-0.035, -hyp.length * 0.5, -0.008), (0.035, hyp.length * 0.5, 0.008), 0, xf_hyp)

    for bx in (-0.028, 0.028):
        for bz in (-0.12, -drop_z + 0.08):
            add_cylinder(bm, Vector((bx, -0.032, bz)), Vector((bx, -0.014, bz)), 0.009, 6, 0)

    finalize_mesh("GrateGussetTriangle", bm, [mats["frame"]], uv_mode="box", uv_scale=1.4, bevel_offset=0.0018)
    export_glb("grate_gusset_triangle.glb")


def build_handrail_pipe() -> None:
    clear_scene()
    mats = get_materials()
    bm = bmesh.new()
    w, h, r_post, r_rail = 2.0, 1.05, 0.022, 0.020
    for px in (-w * 0.5 + 0.04, 0.0, w * 0.5 - 0.04):
        add_cylinder(bm, Vector((px, 0.0, 0.0)), Vector((px, 0.0, h)), r_post, 12, 0)
        add_box(bm, (px - 0.055, -0.055, 0.0), (px + 0.055, 0.055, 0.012), 0)
    add_cylinder(bm, Vector((-w * 0.5, 0.0, h)), Vector((w * 0.5, 0.0, h)), r_rail, 12, 0)
    add_cylinder(bm, Vector((-w * 0.5, 0.0, h * 0.52)), Vector((w * 0.5, 0.0, h * 0.52)), r_rail * 0.85, 10, 0)
    add_box(bm, (-w * 0.5, -0.006, 0.012), (w * 0.5, 0.006, 0.11), 0)
    finalize_mesh("HandrailPipe2m", bm, [mats["rail"]], uv_mode="box", uv_scale=1.2, bevel_offset=0.0018)
    export_glb("handrail_pipe_2m.glb")


def build_handrail_flatbar() -> None:
    clear_scene()
    mats = get_materials()
    bm = bmesh.new()
    w, h = 2.0, 1.05
    for px in (-w * 0.5 + 0.03, w * 0.5 - 0.03):
        add_box(bm, (px - 0.024, -0.024, 0.0), (px + 0.024, 0.024, h), 0)
        add_box(bm, (px - 0.06, -0.06, 0.0), (px + 0.06, 0.06, 0.014), 0)
    add_box(bm, (-w * 0.5, -0.028, h - 0.022), (w * 0.5, 0.028, h), 0)
    add_box(bm, (-w * 0.5, -0.018, 0.08), (w * 0.5, 0.018, 0.115), 0)
    add_box(bm, (-w * 0.5, -0.016, h * 0.55), (w * 0.5, 0.016, h * 0.55 + 0.025), 0)
    for i in range(1, 9):
        bx = -w * 0.5 + w * (i / 9)
        add_box(bm, (bx - 0.009, -0.009, 0.115), (bx + 0.009, 0.009, h - 0.022), 0)
    finalize_mesh("HandrailFlatbar2m", bm, [mats["frame"]], uv_mode="box", uv_scale=1.2, bevel_offset=0.002)
    export_glb("handrail_flatbar_2m.glb")


def build_handrail_mesh_guard() -> None:
    clear_scene()
    mats = get_materials()
    bm_frame = bmesh.new()
    w, h = 2.0, 1.05
    for px in (-w * 0.5 + 0.025, 0.0, w * 0.5 - 0.025):
        add_box(bm_frame, (px - 0.02, -0.02, 0.0), (px + 0.02, 0.02, h), 0)
        add_box(bm_frame, (px - 0.055, -0.055, 0.0), (px + 0.055, 0.055, 0.012), 0)
    add_box(bm_frame, (-w * 0.5, -0.025, h - 0.025), (w * 0.5, 0.025, h), 0)
    add_box(bm_frame, (-w * 0.5, -0.02, 0.06), (w * 0.5, 0.02, 0.10), 0)
    finalize_mesh("HandrailMeshFrame", bm_frame, [mats["frame"]], uv_mode="box", uv_scale=1.2, bevel_offset=0.002)

    bm_mesh = bmesh.new()
    for y_off, flip in ((-0.004, False), (0.004, True)):
        v0 = bm_mesh.verts.new((-w * 0.5 + 0.04, y_off, 0.10))
        v1 = bm_mesh.verts.new((w * 0.5 - 0.04, y_off, 0.10))
        v2 = bm_mesh.verts.new((w * 0.5 - 0.04, y_off, h - 0.03))
        v3 = bm_mesh.verts.new((-w * 0.5 + 0.04, y_off, h - 0.03))
        bm_mesh.faces.new((v3, v2, v1, v0) if flip else (v0, v1, v2, v3))

    finalize_mesh("HandrailMeshInfill", bm_mesh, [mats["grate"]], uv_mode="box", uv_scale=0.85, bevel_offset=0.0)
    export_glb("handrail_mesh_2m.glb")


def build_handrail_bent_damaged() -> None:
    clear_scene()
    mats = get_materials()
    bm = bmesh.new()
    w, h, r_post, r_rail = 2.0, 1.05, 0.022, 0.020
    add_cylinder(bm, Vector((-w * 0.5 + 0.04, 0.0, 0.0)), Vector((-w * 0.5 + 0.04, 0.0, h)), r_post, 12, 0)
    add_box(bm, (-w * 0.5 - 0.015, -0.055, 0.0), (-w * 0.5 + 0.095, 0.055, 0.012), 0)
    mid_top = Vector((0.05, -0.26, h * 0.86))
    add_cylinder(bm, Vector((0.0, 0.0, 0.0)), Vector((0.0, -0.03, 0.30)), r_post, 12, 0)
    add_cylinder(bm, Vector((0.0, -0.03, 0.30)), mid_top, r_post, 12, 0)
    add_box(bm, (-0.055, -0.055, 0.0), (0.055, 0.055, 0.012), 0)
    right_x = w * 0.5 - 0.04
    add_cylinder(bm, Vector((right_x, 0.0, 0.0)), Vector((right_x, -0.08, 0.52)), r_post, 12, 0)
    add_box(bm, (right_x - 0.055, -0.055, 0.0), (right_x + 0.055, 0.055, 0.012), 0)
    add_cylinder(bm, Vector((-w * 0.5, 0.0, h)), mid_top, r_rail, 12, 0)
    add_cylinder(bm, mid_top, Vector((0.68, -0.34, 0.42)), r_rail, 12, 0)
    add_cylinder(bm, Vector((-w * 0.5, 0.0, h * 0.52)), Vector((0.02, -0.14, h * 0.44)), r_rail * 0.85, 10, 0)
    add_cylinder(bm, Vector((0.02, -0.14, h * 0.44)), Vector((right_x, -0.08, 0.46)), r_rail * 0.85, 10, 0)
    add_box(bm, (-w * 0.5, -0.006, 0.012), (0.15, 0.006, 0.11), 0)
    finalize_mesh("HandrailBentDamaged2m", bm, [mats["rail"]], uv_mode="box", uv_scale=1.2, bevel_offset=0.0018)
    export_glb("handrail_bent_damaged_2m.glb")


def build_handrail_post_corner() -> None:
    clear_scene()
    mats = get_materials()
    bm = bmesh.new()
    h = 1.05
    add_cylinder(bm, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, h)), 0.025, 12, 0)
    add_box(bm, (-0.065, -0.065, 0.0), (0.065, 0.065, 0.014), 0)
    add_cylinder(bm, Vector((0.0, 0.0, h)), Vector((0.0, 0.0, h + 0.015)), 0.028, 12, 0)
    finalize_mesh("HandrailPostCorner", bm, [mats["rail"]], uv_mode="box", uv_scale=1.2, bevel_offset=0.0018)
    export_glb("handrail_post_corner.glb")


def build_broken_metal_stairs() -> None:
    clear_scene()
    mats = get_materials()
    bm = bmesh.new()
    stair_w = 1.20
    hw = stair_w * 0.5
    p_top = Vector((0.0, -1.50, 2.00))
    p_knee = Vector((0.0, 0.30, 0.24))
    p_end = Vector((0.0, 1.50, 0.08))

    for sx in (-hw, hw):
        v_dir = (p_knee - p_top).normalized()
        s_len = (p_knee - p_top).length
        s_mid = (p_top + p_knee) * 0.5 + Vector((sx, 0.0, -0.08))
        xf_up = Matrix.Translation(s_mid) @ Matrix.Rotation(math.atan2(v_dir.z, v_dir.y), 4, "X")
        add_box(bm, (-0.025, -s_len * 0.5, -0.10), (0.025, s_len * 0.5, 0.10), 0, xf_up)

        v_low = (p_end - p_knee).normalized()
        l_len = (p_end - p_knee).length
        l_mid = (p_knee + p_end) * 0.5 + Vector((sx, 0.0, -0.04))
        twist = math.radians(10.0) if sx > 0 else math.radians(-5.0)
        xf_low = Matrix.Translation(l_mid) @ Matrix.Rotation(math.atan2(v_low.z, v_low.y), 4, "X") @ Matrix.Rotation(twist, 4, "Y")
        add_box(bm, (-0.025, -l_len * 0.5, -0.08), (0.025, l_len * 0.5, 0.08), 0, xf_low)

    add_box(bm, (-hw - 0.03, p_top.y - 0.06, p_top.z - 0.14), (hw + 0.03, p_top.y + 0.04, p_top.z), 0)

    for i in range(7):
        if i == 4:
            continue
        t = (i + 0.5) / 7
        pos = p_top.lerp(p_knee, t)
        tilt = math.radians(6.0) if i == 5 else 0.0
        xf = Matrix.Translation((0.0, pos.y, pos.z)) @ Matrix.Rotation(tilt, 4, "Y")
        add_box(bm, (-hw + 0.025, -0.13, -0.035), (hw - 0.025, 0.13, 0.0), 1, xf)
        add_box(bm, (-hw + 0.025, 0.11, -0.055), (hw - 0.025, 0.135, 0.0), 0, xf)

    xf_plate = Matrix.Translation((0.0, 0.90, 0.12)) @ Matrix.Rotation(math.radians(-6.0), 4, "X")
    add_box(bm, (-hw + 0.03, -0.52, -0.025), (hw - 0.03, 0.52, 0.015), 1, xf_plate)

    xf_loose = (
        Matrix.Translation((0.12, 0.55, 0.18))
        @ Matrix.Rotation(math.radians(18.0), 4, "Z")
        @ Matrix.Rotation(math.radians(-14.0), 4, "X")
    )
    add_box(bm, (-0.48, -0.12, -0.02), (0.48, 0.12, 0.015), 1, xf_loose)

    r_p0 = Vector((-hw, p_top.y, p_top.z))
    r_p1 = Vector((-hw, p_top.y, p_top.z + 0.92))
    r_p2 = Vector((-hw, -0.55, 1.05))
    r_p3 = Vector((-hw - 0.12, -0.10, 0.72))
    add_cylinder(bm, r_p0, r_p1, 0.02, 10, 0)
    add_cylinder(bm, Vector((-hw, -0.55, 1.05)), Vector((-hw, -0.55, 1.92)), 0.02, 10, 0)
    add_cylinder(bm, r_p1, Vector((-hw, -0.55, 1.92)), 0.018, 10, 0)
    add_cylinder(bm, Vector((-hw, -0.55, 1.92)), Vector((-hw - 0.16, 0.15, 1.25)), 0.018, 10, 0)
    add_cylinder(bm, r_p2, r_p3, 0.016, 10, 0)

    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0.0, 0.0, -min_z))

    finalize_mesh("BrokenMetalStairsLShape", bm, [mats["frame"], mats["tread"]], uv_mode="box", uv_scale=1.1, bevel_offset=0.002)
    export_glb("broken_metal_stairs_lshape.glb")


def main() -> None:
    build_grate_floor(2.0, 1.2, "grate_floor_2x1_2m.glb", damaged=False)
    build_grate_floor(2.0, 2.0, "grate_floor_2x2m.glb", damaged=False)
    build_grate_floor(1.0, 1.2, "grate_floor_1x1_2m.glb", damaged=False)
    build_grate_floor(2.0, 1.2, "grate_floor_damaged_2x1_2m.glb", damaged=True)
    build_gusset_triangle()
    build_handrail_pipe()
    build_handrail_flatbar()
    build_handrail_mesh_guard()
    build_handrail_bent_damaged()
    build_handrail_post_corner()
    build_broken_metal_stairs()


if __name__ == "__main__":
    main()
