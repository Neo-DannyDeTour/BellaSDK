"""Procedural Blender generator for intact HL2-style chain-link fence kit (6 GLBs).

Generates modular industrial security fence panels matching `fence_door.py` conventions:
  1. fence_straight_2m.glb         (2.0m W x 2.1m H)
  2. fence_straight_4m.glb         (4.0m W x 2.1m H)
  3. fence_barb_45_2m.glb          (2.0m W x 2.5m H — 45-deg outrigger arms + 3 strands)
  4. fence_barb_curved_2m.glb      (2.0m W x 2.5m H — swan-neck arms + 4 strands)
  5. fence_barb_y_concertina_2m.glb(2.0m W x 2.6m H — Y-arm V-brackets + concertina coil)
  6. fence_post_corner.glb         (0.12m W x 2.5m H — standalone heavy corner/end post)

Conventions:
- Bottom-center origin (0, 0, 0), facing -Y in Blender (-Z in Godot), grounded min_z = 0.
- 2.5mm chamfers on steel posts/rails, beveled concrete footings (0.16 x 0.16 x 0.14m).
- Metric box UVs on metal/concrete, ~10 tiles/m UVs on alpha-scissor chain-link quads.
- Static Godot `-colonly` box collision meshes matching each panel's solid bounds.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import create_pbr_material
from mathutils import Matrix, Vector

# Shared dimensional constants (meters)
BASE_H = 2.10
POST_W = 0.052
POST_D = 0.052
RAIL_TOP_H = 0.040
RAIL_MID_H = 0.032
RAIL_BOT_H = 0.036
FOOTING_W = 0.16
FOOTING_D = 0.16
FOOTING_H = 0.14
BEVEL_OFFSET = 0.0025
UV_TILE_METERS = 1.0
CHAIN_TILES_PER_M = 10.0

# Material slot indices on visual mesh
MAT_METAL = 0
MAT_CHAIN = 1
MAT_CONCRETE = 2
MAT_BARB = 3


def _load_image_if_exists(path: Path) -> bpy.types.Image | None:
    if path.is_file():
        return bpy.data.images.load(str(path.resolve()), check_existing=True)
    return None


def _attach_metallic_image(
    mat: bpy.types.Material, metallic_image: bpy.types.Image | None
) -> None:
    """Connect a grayscale metallic map to Principled BSDF if present."""
    if metallic_image is None or not mat.use_nodes:
        return
    tree = mat.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    if bsdf is None or "Metallic" not in bsdf.inputs:
        return
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = metallic_image
    tex.image.colorspace_settings.name = "Non-Color"
    tex.location = (-400, 150)
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Metallic"])


def _configure_alpha_scissor(mat: bpy.types.Material, threshold: float = 0.5) -> None:
    """Link base-color image Alpha to Principled BSDF Alpha and disable backface culling."""
    mat.use_backface_culling = False
    if hasattr(mat, "blend_method"):
        mat.blend_method = "CLIP"
    if hasattr(mat, "alpha_threshold"):
        mat.alpha_threshold = threshold
    if not mat.use_nodes:
        return
    tree = mat.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    if bsdf is None or "Alpha" not in bsdf.inputs:
        return
    for node in tree.nodes:
        if node.type == "TEX_IMAGE" and node.outputs["Color"].is_linked:
            for link in node.outputs["Color"].links:
                if link.to_socket == bsdf.inputs["Base Color"]:
                    tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
                    return


def _create_kit_materials(project_root: Path) -> dict[str, bpy.types.Material]:
    """Create and bind PBR materials for metal, chain-link, concrete, barbed wire, and collider."""
    metal_dir = project_root / "assets/materials/fence_door_metal/textures"
    chain_dir = project_root / "assets/materials/chain_link_fence/textures"
    concrete_dir = project_root / "assets/materials/weathered_concrete/textures"
    barb_dir = project_root / "assets/materials/barbed_wire/textures"

    mat_metal = create_pbr_material(
        name="M_MetalFrame",
        base_color=(0.24, 0.25, 0.22, 1.0),
        metallic=0.25,
        roughness=0.58,
        base_color_image=_load_image_if_exists(metal_dir / "fence_door_metal_albedo.png"),
        roughness_image=_load_image_if_exists(metal_dir / "fence_door_metal_roughness.png"),
        normal_image=_load_image_if_exists(metal_dir / "fence_door_metal_normal.png"),
        normal_strength=0.75,
    )
    _attach_metallic_image(
        mat_metal, _load_image_if_exists(metal_dir / "fence_door_metal_metallic.png")
    )

    mat_chain = create_pbr_material(
        name="M_ChainLink",
        base_color=(0.45, 0.46, 0.45, 1.0),
        metallic=0.85,
        roughness=0.50,
        base_color_image=_load_image_if_exists(chain_dir / "chain_link_fence_albedo.png"),
        roughness_image=_load_image_if_exists(chain_dir / "chain_link_fence_roughness.png"),
        normal_image=_load_image_if_exists(chain_dir / "chain_link_fence_normal.png"),
        normal_strength=1.0,
    )
    _attach_metallic_image(
        mat_chain, _load_image_if_exists(chain_dir / "chain_link_fence_metallic.png")
    )
    _configure_alpha_scissor(mat_chain, threshold=0.5)

    mat_concrete = create_pbr_material(
        name="M_Concrete",
        base_color=(0.42, 0.41, 0.38, 1.0),
        metallic=0.0,
        roughness=0.85,
        base_color_image=_load_image_if_exists(concrete_dir / "weathered_concrete_albedo.png"),
        roughness_image=_load_image_if_exists(concrete_dir / "weathered_concrete_roughness.png"),
        normal_image=_load_image_if_exists(concrete_dir / "weathered_concrete_normal.png"),
        normal_strength=0.8,
    )

    mat_barb = create_pbr_material(
        name="M_BarbedWire",
        base_color=(0.36, 0.30, 0.26, 1.0),
        metallic=0.72,
        roughness=0.62,
        base_color_image=_load_image_if_exists(barb_dir / "barbed_wire_albedo.png"),
        roughness_image=_load_image_if_exists(barb_dir / "barbed_wire_roughness.png"),
        normal_image=_load_image_if_exists(barb_dir / "barbed_wire_normal.png"),
        normal_strength=1.0,
    )
    _attach_metallic_image(
        mat_barb, _load_image_if_exists(barb_dir / "barbed_wire_metallic.png")
    )
    _configure_alpha_scissor(mat_barb, threshold=0.5)

    # Invisible material for -colonly proxy so headless Cycles QA renders never show solid box
    mat_col = create_pbr_material(
        name="M_ColliderHidden",
        base_color=(0.0, 0.0, 0.0, 0.0),
        metallic=0.0,
        roughness=1.0,
    )
    mat_col.use_backface_culling = False
    if hasattr(mat_col, "blend_method"):
        mat_col.blend_method = "CLIP"
    if hasattr(mat_col, "alpha_threshold"):
        mat_col.alpha_threshold = 0.5
    bsdf = mat_col.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None and "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = 0.0

    return {
        "metal": mat_metal,
        "chain": mat_chain,
        "concrete": mat_concrete,
        "barb": mat_barb,
        "collider": mat_col,
    }


def _add_beveled_box(
    bm: bmesh.types.BMesh,
    center: Vector,
    size: Vector,
    mat_idx: int = MAT_METAL,
    bevel: float = BEVEL_OFFSET,
    rot_matrix: Matrix | None = None,
) -> None:
    """Create a box with subtle edge chamfers for realistic specular highlights."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    bmesh.ops.scale(tmp, vec=size, verts=tmp.verts)
    if bevel > 0.0:
        max_bevel = min(size.x, size.y, size.z) * 0.22
        bmesh.ops.bevel(
            tmp,
            geom=list(tmp.edges),
            offset=min(bevel, max_bevel),
            segments=1,
            affect="EDGES",
            clamp_overlap=True,
        )
    if rot_matrix is not None:
        bmesh.ops.transform(tmp, matrix=rot_matrix, verts=tmp.verts)
    bmesh.ops.translate(tmp, vec=center, verts=tmp.verts)
    for face in tmp.faces:
        face.material_index = mat_idx

    mesh_tmp = bpy.data.meshes.new("_tmp_box")
    tmp.to_mesh(mesh_tmp)
    tmp.free()
    bm.from_mesh(mesh_tmp)
    bpy.data.meshes.remove(mesh_tmp)


def _add_box_between(
    bm: bmesh.types.BMesh,
    p1: Vector,
    p2: Vector,
    width: float,
    depth: float,
    mat_idx: int = MAT_METAL,
    bevel: float = BEVEL_OFFSET,
) -> None:
    """Create a beveled rectangular bar connecting p1 to p2 along local Z."""
    vec = p2 - p1
    length = vec.length
    if length < 1e-6:
        return
    mid = (p1 + p2) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    _add_beveled_box(bm, mid, Vector((width, depth, length)), mat_idx=mat_idx, bevel=bevel, rot_matrix=rot)


def _add_swept_tube(
    bm: bmesh.types.BMesh,
    points: list[Vector],
    radius: float,
    sides: int = 4,
    mat_idx: int = MAT_METAL,
    cap_ends: bool = True,
    uv_scale_u: float = 1.0,
) -> None:
    """Sweep a regular N-sided prism tube along a 3D polyline."""
    if len(points) < 2:
        return
    uv_layer = bm.loops.layers.uv.verify()
    rings: list[list[bmesh.types.BMVert]] = []
    cum_len: list[float] = [0.0]

    for idx, pt in enumerate(points):
        if idx > 0:
            cum_len.append(cum_len[-1] + (pt - points[idx - 1]).length)
        if idx == 0:
            tangent = (points[1] - points[0]).normalized()
        elif idx == len(points) - 1:
            tangent = (points[-1] - points[-2]).normalized()
        else:
            tangent = (points[idx + 1] - points[idx - 1]).normalized()
        if tangent.length < 1e-6:
            tangent = Vector((1.0, 0.0, 0.0))

        ref = Vector((0.0, 0.0, 1.0)) if abs(tangent.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        binorm = tangent.cross(ref).normalized()
        norm = binorm.cross(tangent).normalized()

        ring: list[bmesh.types.BMVert] = []
        for s in range(sides):
            ang = (2.0 * math.pi * s) / sides + math.pi * 0.25
            offset = (norm * math.cos(ang) + binorm * math.sin(ang)) * radius
            ring.append(bm.verts.new(pt + offset))
        rings.append(ring)

    for i in range(len(rings) - 1):
        r0 = rings[i]
        r1 = rings[i + 1]
        u0 = cum_len[i] * uv_scale_u
        u1 = cum_len[i + 1] * uv_scale_u
        for s in range(sides):
            sn = (s + 1) % sides
            v0 = s / sides
            v1 = (s + 1) / sides
            face = bm.faces.new((r0[s], r1[s], r1[sn], r0[sn]))
            face.material_index = mat_idx
            face.loops[0][uv_layer].uv = (u0, v0)
            face.loops[1][uv_layer].uv = (u1, v0)
            face.loops[2][uv_layer].uv = (u1, v1)
            face.loops[3][uv_layer].uv = (u0, v1)

    if cap_ends:
        f_start = bm.faces.new(list(reversed(rings[0])))
        f_start.material_index = mat_idx
        f_end = bm.faces.new(rings[-1])
        f_end.material_index = mat_idx


def _add_barb_strand(
    bm: bmesh.types.BMesh,
    p_start: Vector,
    p_end: Vector,
    sag: float = 0.022,
    segments: int = 3,
    wire_radius: float = 0.0028,
    card_half_h: float = 0.028,
    tiles_per_m: float = 3.2,
) -> None:
    """Add a 4-sided 3D wire core + crossed alpha-scissor barb ribbon cards."""
    pts: list[Vector] = []
    for i in range(segments + 1):
        t = i / segments
        p = p_start.lerp(p_end, t)
        p.z -= sag * 4.0 * t * (1.0 - t)
        pts.append(p)

    # 1. Thin 4-sided 3D wire core (metal material)
    _add_swept_tube(bm, pts, radius=wire_radius, sides=4, mat_idx=MAT_METAL, cap_ends=False)

    # 2. Crossed alpha-scissor barbed-wire cards (+45 deg and -45 deg around wire axis)
    uv_layer = bm.loops.layers.uv.verify()
    span_len = (p_end - p_start).length
    u_total = span_len * tiles_per_m
    tangent = (p_end - p_start).normalized()
    up = Vector((0.0, 0.0, 1.0))
    side = tangent.cross(up).normalized()
    if side.length < 1e-6:
        side = Vector((0.0, 1.0, 0.0))

    for tilt_deg in (40.0, -40.0):
        rad = math.radians(tilt_deg)
        axis = (up * math.cos(rad) + side * math.sin(rad)) * card_half_h
        for i in range(segments):
            u0 = (i / segments) * u_total
            u1 = ((i + 1) / segments) * u_total
            v0 = bm.verts.new(pts[i] - axis)
            v1 = bm.verts.new(pts[i + 1] - axis)
            v2 = bm.verts.new(pts[i + 1] + axis)
            v3 = bm.verts.new(pts[i] + axis)
            face = bm.faces.new((v0, v1, v2, v3))
            face.material_index = MAT_BARB
            face.loops[0][uv_layer].uv = (u0, 0.0)
            face.loops[1][uv_layer].uv = (u1, 0.0)
            face.loops[2][uv_layer].uv = (u1, 1.0)
            face.loops[3][uv_layer].uv = (u0, 1.0)


def _add_concertina_coil(
    bm: bmesh.types.BMesh,
    x_start: float,
    x_end: float,
    y_center: float,
    z_center: float,
    coil_radius: float = 0.20,
    turns: float = 6.0,
    segs_per_turn: int = 8,
    ribbon_half_w: float = 0.032,
) -> None:
    """Build a coiled concertina razor-wire crown: 4-sided 3D helix + radial razor ribbon."""
    total_segs = int(round(turns * segs_per_turn))
    pts: list[Vector] = []
    radials: list[Vector] = []

    for i in range(total_segs + 1):
        t = i / total_segs
        ang = t * turns * 2.0 * math.pi
        x = x_start + (x_end - x_start) * t
        y = y_center + math.cos(ang) * coil_radius
        z = z_center + math.sin(ang) * coil_radius
        pts.append(Vector((x, y, z)))
        radials.append(Vector((0.0, math.cos(ang), math.sin(ang))).normalized())

    # 3D 4-sided helical steel wire core
    _add_swept_tube(bm, pts, radius=0.0032, sides=4, mat_idx=MAT_METAL, cap_ends=False)

    # Continuous alpha-scissor razor-blade ribbon along the helix
    uv_layer = bm.loops.layers.uv.verify()
    cum_len = 0.0
    tiles_per_m = 3.5
    prev_inner = bm.verts.new(pts[0] - radials[0] * ribbon_half_w)
    prev_outer = bm.verts.new(pts[0] + radials[0] * ribbon_half_w)

    for i in range(1, len(pts)):
        seg_len = (pts[i] - pts[i - 1]).length
        u0 = cum_len * tiles_per_m
        cum_len += seg_len
        u1 = cum_len * tiles_per_m

        cur_inner = bm.verts.new(pts[i] - radials[i] * ribbon_half_w)
        cur_outer = bm.verts.new(pts[i] + radials[i] * ribbon_half_w)
        face = bm.faces.new((prev_inner, cur_inner, cur_outer, prev_outer))
        face.material_index = MAT_BARB
        face.loops[0][uv_layer].uv = (u0, 0.0)
        face.loops[1][uv_layer].uv = (u1, 0.0)
        face.loops[2][uv_layer].uv = (u1, 1.0)
        face.loops[3][uv_layer].uv = (u0, 1.0)
        prev_inner = cur_inner
        prev_outer = cur_outer


def _add_chain_link_quad(
    bm: bmesh.types.BMesh,
    x_min: float,
    x_max: float,
    z_min: float,
    z_max: float,
    y_plane: float = 0.0,
) -> None:
    """Add a 2-sided alpha-scissor chain-link infill quad with ~10 tiles/m UVs."""
    uv_layer = bm.loops.layers.uv.verify()
    v1 = bm.verts.new(Vector((x_min, y_plane, z_min)))
    v2 = bm.verts.new(Vector((x_max, y_plane, z_min)))
    v3 = bm.verts.new(Vector((x_max, y_plane, z_max)))
    v4 = bm.verts.new(Vector((x_min, y_plane, z_max)))
    face = bm.faces.new((v1, v2, v3, v4))
    face.material_index = MAT_CHAIN

    u_tiles = max(1.0, round((x_max - x_min) * CHAIN_TILES_PER_M, 2))
    v_tiles = max(1.0, round((z_max - z_min) * CHAIN_TILES_PER_M, 2))
    face.loops[0][uv_layer].uv = (0.0, 0.0)
    face.loops[1][uv_layer].uv = (u_tiles, 0.0)
    face.loops[2][uv_layer].uv = (u_tiles, v_tiles)
    face.loops[3][uv_layer].uv = (0.0, v_tiles)


def _box_project_uvs(
    bm: bmesh.types.BMesh,
    tile_meters: float,
    mat_indices: set[int],
) -> None:
    """Assign metric box-projected UVs to faces matching mat_indices."""
    uv_layer = bm.loops.layers.uv.verify()
    scale = 1.0 / tile_meters
    for face in bm.faces:
        if face.material_index not in mat_indices:
            continue
        n = face.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            co = loop.vert.co
            if ax == 0:
                u, v = co.y * scale, co.z * scale
            elif ax == 1:
                u, v = co.x * scale, co.z * scale
            else:
                u, v = co.x * scale, co.y * scale
            loop[uv_layer].uv = (u, v)


def _add_base_fence_panel(
    bm: bmesh.types.BMesh,
    width: float,
    height: float = BASE_H,
    center_post: bool = False,
    add_post_caps: bool = True,
    add_rail_collars: bool = True,
) -> list[float]:
    """Build standard tubular frame, footings, rails, brackets, and chain-link infill.

    Returns the list of post X centers.
    """
    half_w = width * 0.5
    post_xs = [-half_w + POST_W * 0.5, half_w - POST_W * 0.5]
    if center_post:
        post_xs.insert(1, 0.0)

    z_bot_rail = FOOTING_H + RAIL_BOT_H * 0.5
    z_mid_rail = height * 0.52
    z_top_rail = height - RAIL_TOP_H * 0.5

    # Vertical posts + concrete footing blocks
    for px in post_xs:
        # Keep footing within [-half_w, +half_w] so modular panels tile at exact width
        fx = max(-half_w + FOOTING_W * 0.5, min(half_w - FOOTING_W * 0.5, px))
        _add_beveled_box(
            bm,
            Vector((fx, 0.0, FOOTING_H * 0.5)),
            Vector((FOOTING_W, FOOTING_D, FOOTING_H)),
            mat_idx=MAT_CONCRETE,
            bevel=0.008,
        )
        # Main vertical steel post seated into top of concrete footing (avoids outer X coplanarity)
        post_z0 = FOOTING_H - 0.015
        post_z1 = height - 0.015 if add_post_caps else height
        post_h = post_z1 - post_z0
        _add_beveled_box(
            bm,
            Vector((px, 0.0, post_z0 + post_h * 0.5)),
            Vector((POST_W, POST_D, post_h)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        if add_post_caps:
            _add_beveled_box(
                bm,
                Vector((px, 0.0, height - 0.0075)),
                Vector((POST_W + 0.012, POST_D + 0.012, 0.015)),
                mat_idx=MAT_METAL,
                bevel=0.002,
            )

    # Horizontal rails + chain-link per bay
    for bay_idx in range(len(post_xs) - 1):
        x_l = post_xs[bay_idx] + POST_W * 0.5
        x_r = post_xs[bay_idx + 1] - POST_W * 0.5
        bay_w = x_r - x_l
        bay_cx = (x_l + x_r) * 0.5

        # Top rail
        _add_beveled_box(
            bm,
            Vector((bay_cx, 0.0, z_top_rail)),
            Vector((bay_w, RAIL_TOP_H, RAIL_TOP_H)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        # Mid rail
        _add_beveled_box(
            bm,
            Vector((bay_cx, 0.0, z_mid_rail)),
            Vector((bay_w, RAIL_MID_H, RAIL_MID_H)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        # Bottom tension rail
        _add_beveled_box(
            bm,
            Vector((bay_cx, 0.0, z_bot_rail)),
            Vector((bay_w, RAIL_BOT_H, RAIL_BOT_H)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )

        # Chain-link infill quad spanning between rails and posts
        _add_chain_link_quad(
            bm,
            x_min=x_l,
            x_max=x_r,
            z_min=z_bot_rail + RAIL_BOT_H * 0.45,
            z_max=z_top_rail - RAIL_TOP_H * 0.45,
            y_plane=0.0,
        )

    # Rail-to-post mounting bracket collars
    if add_rail_collars:
        for px in post_xs:
            for rz in (z_bot_rail, z_mid_rail, z_top_rail):
                _add_beveled_box(
                    bm,
                    Vector((px, 0.0, rz)),
                    Vector((POST_W + 0.014, POST_D + 0.014, 0.044)),
                    mat_idx=MAT_METAL,
                    bevel=0.0,  # Crisp low-poly clamp collar (12 tris vs 44)
                )

    return post_xs


def _create_colonly_box(
    name: str,
    center: Vector,
    size: Vector,
    mat_collider: bpy.types.Material,
) -> bpy.types.Object:
    """Create a static Godot `-colonly` box collider with valid UVs and hidden QA render."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    _box_project_uvs(bm, 1.0, {0})
    bmesh.ops.triangulate(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new(f"SM_{name}")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat_collider)
    obj.display_type = "WIRE"
    obj.hide_render = True
    return obj


def _finalize_and_export(
    slug: str,
    mesh_name: str,
    bm: bmesh.types.BMesh,
    mats: dict[str, bpy.types.Material],
    col_center: Vector,
    col_size: Vector,
    collision_hint: str,
    output_dir: Path,
    used_barb: bool = False,
    used_chain: bool = True,
    col_boxes: list[tuple[str, Vector, Vector]] | None = None,
) -> dict[str, Any]:
    """Finalize UVs, triangulate, attach materials + `-colonly` box(es), and export GLB."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _box_project_uvs(bm, UV_TILE_METERS, {MAT_METAL, MAT_CONCRETE})
    bmesh.ops.triangulate(bm, faces=bm.faces)
    visual_tris = len(bm.faces)

    mesh = bpy.data.meshes.new(f"SM_{mesh_name}")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(mesh_name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mats["metal"])
    obj.data.materials.append(mats["chain"])
    obj.data.materials.append(mats["concrete"])
    obj.data.materials.append(mats["barb"])

    boxes = col_boxes if col_boxes is not None else [(f"{mesh_name}-colonly", col_center, col_size)]
    col_objs: list[bpy.types.Object] = []
    for cname, ccenter, csize in boxes:
        col_objs.append(_create_colonly_box(cname, ccenter, csize, mats["collider"]))
    col_tris = sum(len(co.data.polygons) for co in col_objs)

    bpy.context.view_layer.update()
    world_pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    xs = [p.x for p in world_pts]
    ys = [p.y for p in world_pts]
    zs = [p.z for p in world_pts]
    dims = {
        "x": round(max(xs) - min(xs), 4),
        "y": round(max(zs) - min(zs), 4),  # Godot Y = Blender Z
        "z": round(max(ys) - min(ys), 4),
    }
    min_y_m = round(min(zs), 4)

    glb_path = output_dir / f"{slug}.glb"
    export_godot_glb(glb_path, export_animations=False, apply_modifiers=True)

    mat_paths = [
        "res://assets/materials/fence_door_metal/fence_door_metal.tres",
        "res://assets/materials/weathered_concrete/weathered_concrete.tres",
    ]
    if used_chain:
        mat_paths.append("res://assets/materials/chain_link_fence/chain_link_fence.tres")
    if used_barb:
        mat_paths.append("res://assets/materials/barbed_wire/barbed_wire.tres")

    total_tris = visual_tris + col_tris
    uv_counts = [len(obj.data.uv_layers)] + [len(co.data.uv_layers) for co in col_objs]
    print(
        f"[fence_kit_intact] {slug}: visual={visual_tris} tris, total={total_tris} tris, "
        f"dims={dims}, min_y={min_y_m}"
    )
    return {
        "slug": slug,
        "tri_count": total_tris,
        "visual_tri_count": visual_tris,
        "uv_layers": min(uv_counts),
        "dimensions_m": dims,
        "min_y_m": min_y_m,
        "collision_hint": collision_hint,
        "materials": mat_paths,
        "glb_path": f"res://assets/models/chain_link_fence_kit/{slug}.glb",
    }


def build_fence_straight_2m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """1. Standard 2.0m W x 2.1m H chain-link fence panel."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    _add_base_fence_panel(bm, width=2.0, height=BASE_H, center_post=False)
    return _finalize_and_export(
        slug="fence_straight_2m",
        mesh_name="FenceStraight2m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, BASE_H * 0.5)),
        col_size=Vector((2.0, 0.08, BASE_H)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 2.00 x 2.10 x 0.08m)",
        output_dir=output_dir,
        used_barb=False,
    )


def build_fence_straight_4m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """2. Double-bay 4.0m W x 2.1m H chain-link fence panel with center support post."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    _add_base_fence_panel(bm, width=4.0, height=BASE_H, center_post=True)
    return _finalize_and_export(
        slug="fence_straight_4m",
        mesh_name="FenceStraight4m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, BASE_H * 0.5)),
        col_size=Vector((4.0, 0.08, BASE_H)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 4.00 x 2.10 x 0.08m)",
        output_dir=output_dir,
        used_barb=False,
    )


def build_fence_barb_45_2m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """3. 2.0m W x 2.5m H fence panel with straight 45-deg outrigger arms + 3 barbed strands."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=2.0, height=BASE_H, add_post_caps=False)

    arm_base_z = BASE_H - 0.02
    arm_tip_z = 2.50
    arm_tip_y = -0.38  # Leaning outward toward -Y front (Godot -Z)

    for px in post_xs:
        p0 = Vector((px, 0.0, arm_base_z))
        p1 = Vector((px, arm_tip_y, arm_tip_z))
        # Post top mounting sleeve
        _add_beveled_box(
            bm,
            Vector((px, 0.0, BASE_H - 0.03)),
            Vector((POST_W + 0.016, POST_D + 0.016, 0.07)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        # Angled 45-deg outrigger steel arm
        _add_box_between(bm, p0, p1, width=0.036, depth=0.036, mat_idx=MAT_METAL)
        # Triangular bracing gusset strut under arm
        _add_box_between(
            bm,
            Vector((px, -0.02, BASE_H - 0.14)),
            p0.lerp(p1, 0.42),
            width=0.018,
            depth=0.018,
            mat_idx=MAT_METAL,
            bevel=0.0,
        )

    # 3 horizontal barbed-wire strands stretched along the 45-deg arms
    x_l, x_r = post_xs[0], post_xs[-1]
    for frac in (0.34, 0.67, 0.96):
        wy = arm_tip_y * frac
        wz = arm_base_z + (arm_tip_z - arm_base_z) * frac
        _add_barb_strand(
            bm,
            Vector((x_l, wy, wz)),
            Vector((x_r, wy, wz)),
            sag=0.020,
            segments=3,
        )

    return _finalize_and_export(
        slug="fence_barb_45_2m",
        mesh_name="FenceBarb45_2m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.04, 1.25)),
        col_size=Vector((2.0, 0.16, 2.50)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 2.00 x 2.50 x 0.16m)",
        output_dir=output_dir,
        used_barb=True,
    )


def build_fence_barb_curved_2m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """4. 2.0m W x 2.5m H fence panel with curved swan-neck outrigger arms + 4 barbed strands."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=2.0, height=BASE_H, add_post_caps=False)

    # Smooth quadratic Bezier swan-neck profile curving up then forward (-Y)
    p0_yz = Vector((0.0, BASE_H - 0.02))
    p1_yz = Vector((-0.06, 2.48))
    p2_yz = Vector((-0.40, 2.50))

    def _eval_curve(t: float) -> tuple[float, float]:
        mt = 1.0 - t
        pt = (mt * mt) * p0_yz + (2.0 * mt * t) * p1_yz + (t * t) * p2_yz
        return pt.x, pt.y

    curve_steps = 6
    for px in post_xs:
        _add_beveled_box(
            bm,
            Vector((px, 0.0, BASE_H - 0.03)),
            Vector((POST_W + 0.016, POST_D + 0.016, 0.07)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        arm_pts: list[Vector] = []
        for s in range(curve_steps + 1):
            cy, cz = _eval_curve(s / curve_steps)
            arm_pts.append(Vector((px, cy, cz)))
        _add_swept_tube(bm, arm_pts, radius=0.020, sides=6, mat_idx=MAT_METAL, cap_ends=True)

    # 4 horizontal barbed-wire strands along swan-neck curve
    x_l, x_r = post_xs[0], post_xs[-1]
    for frac in (0.28, 0.52, 0.76, 0.98):
        wy, wz = _eval_curve(frac)
        _add_barb_strand(
            bm,
            Vector((x_l, wy, wz)),
            Vector((x_r, wy, wz)),
            sag=0.018,
            segments=3,
        )

    return _finalize_and_export(
        slug="fence_barb_curved_2m",
        mesh_name="FenceBarbCurved2m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.05, 1.25)),
        col_size=Vector((2.0, 0.18, 2.50)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 2.00 x 2.50 x 0.18m)",
        output_dir=output_dir,
        used_barb=True,
    )


def build_fence_barb_y_concertina_2m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """5. 2.0m W x 2.6m H fence panel with Y-arm V-brackets + coiled concertina razor-wire crown."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=2.0, height=BASE_H, add_post_caps=False)

    arm_base_z = BASE_H - 0.02
    arm_tip_z = 2.52
    arm_spread_y = 0.28

    for px in post_xs:
        # Heavy Y-bracket collar
        _add_beveled_box(
            bm,
            Vector((px, 0.0, BASE_H - 0.025)),
            Vector((POST_W + 0.018, POST_D + 0.018, 0.075)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        # Front (-Y) and Back (+Y) V-arms
        for side in (-1.0, 1.0):
            _add_box_between(
                bm,
                Vector((px, 0.0, arm_base_z)),
                Vector((px, side * arm_spread_y, arm_tip_z)),
                width=0.032,
                depth=0.032,
                mat_idx=MAT_METAL,
                bevel=0.002,
            )

    # 2 outer tension guide wires along V-bracket tips
    x_l, x_r = post_xs[0], post_xs[-1]
    for side in (-1.0, 1.0):
        _add_barb_strand(
            bm,
            Vector((x_l, side * arm_spread_y * 0.94, arm_tip_z - 0.02)),
            Vector((x_r, side * arm_spread_y * 0.94, arm_tip_z - 0.02)),
            sag=0.018,
            segments=3,
        )

    # Coiled concertina razor-wire crown seated in the V-cradle (top reaches ~2.60m)
    _add_concertina_coil(
        bm,
        x_start=x_l + 0.02,
        x_end=x_r - 0.02,
        y_center=0.0,
        z_center=2.37,
        coil_radius=0.20,
        turns=6.0,
        segs_per_turn=8,
        ribbon_half_w=0.030,
    )

    return _finalize_and_export(
        slug="fence_barb_y_concertina_2m",
        mesh_name="FenceBarbYConcertina2m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, 1.30)),
        col_size=Vector((2.0, 0.24, 2.60)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 2.00 x 2.60 x 0.24m)",
        output_dir=output_dir,
        used_barb=True,
    )


def build_fence_post_corner(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """6. Standalone heavy corner/end post (0.12m W steel profile, 0.16m footing, 2.5m H)."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()

    post_h = 2.50
    col_w = 0.092

    # Beveled concrete footing block (0.16m x 0.16m x 0.14m)
    _add_beveled_box(
        bm,
        Vector((0.0, 0.0, FOOTING_H * 0.5)),
        Vector((FOOTING_W, FOOTING_D, FOOTING_H)),
        mat_idx=MAT_CONCRETE,
        bevel=0.008,
    )

    # Steel anchor baseplate seated on top of concrete footing (0.12m x 0.12m)
    _add_beveled_box(
        bm,
        Vector((0.0, 0.0, FOOTING_H + 0.010)),
        Vector((0.12, 0.12, 0.020)),
        mat_idx=MAT_METAL,
        bevel=0.002,
    )

    # 4 corner anchor bolt heads on baseplate
    for sx in (-0.044, 0.044):
        for sy in (-0.044, 0.044):
            _add_beveled_box(
                bm,
                Vector((sx, sy, FOOTING_H + 0.026)),
                Vector((0.016, 0.016, 0.012)),
                mat_idx=MAT_METAL,
                bevel=0.0,
            )

    # Heavy vertical square steel column
    _add_beveled_box(
        bm,
        Vector((0.0, 0.0, (post_h - 0.03) * 0.5 + 0.01)),
        Vector((col_w, col_w, post_h - 0.03)),
        mat_idx=MAT_METAL,
        bevel=BEVEL_OFFSET,
    )

    # 3 heavy rail-mounting tension collar bands matching fence rail heights
    for rz in (FOOTING_H + RAIL_BOT_H * 0.5, BASE_H * 0.52, BASE_H - RAIL_TOP_H * 0.5):
        _add_beveled_box(
            bm,
            Vector((0.0, 0.0, rz)),
            Vector((0.116, 0.116, 0.052)),
            mat_idx=MAT_METAL,
            bevel=0.002,
        )

    # Stepped heavy post cap reaching z = 2.50m
    _add_beveled_box(
        bm,
        Vector((0.0, 0.0, post_h - 0.018)),
        Vector((0.118, 0.118, 0.022)),
        mat_idx=MAT_METAL,
        bevel=0.003,
    )
    _add_beveled_box(
        bm,
        Vector((0.0, 0.0, post_h - 0.004)),
        Vector((0.088, 0.088, 0.008)),
        mat_idx=MAT_METAL,
        bevel=0.002,
    )

    return _finalize_and_export(
        slug="fence_post_corner",
        mesh_name="FencePostCorner",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, post_h * 0.5)),
        col_size=Vector((0.12, 0.12, post_h)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 0.12 x 2.50 x 0.12m)",
        output_dir=output_dir,
        used_barb=False,
        used_chain=False,
    )


def _add_barb_45_topper(
    bm: bmesh.types.BMesh,
    post_xs: list[float],
    base_h: float,
    strand_segments: int = 3,
) -> float:
    """Add 45-deg outrigger arms + gussets + 3 barbed strands across post_xs. Returns tip Z."""
    arm_base_z = base_h - 0.02
    arm_tip_z = base_h + 0.40
    arm_tip_y = -0.38

    for px in post_xs:
        p0 = Vector((px, 0.0, arm_base_z))
        p1 = Vector((px, arm_tip_y, arm_tip_z))
        _add_beveled_box(
            bm,
            Vector((px, 0.0, base_h - 0.03)),
            Vector((POST_W + 0.016, POST_D + 0.016, 0.07)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        _add_box_between(bm, p0, p1, width=0.036, depth=0.036, mat_idx=MAT_METAL)
        _add_box_between(
            bm,
            Vector((px, -0.02, base_h - 0.14)),
            p0.lerp(p1, 0.42),
            width=0.018,
            depth=0.018,
            mat_idx=MAT_METAL,
            bevel=0.0,
        )

    for idx in range(len(post_xs) - 1):
        x_l, x_r = post_xs[idx], post_xs[idx + 1]
        span_sag = 0.020 * min(1.2, (x_r - x_l) / 2.0)
        for frac in (0.34, 0.67, 0.96):
            wy = arm_tip_y * frac
            wz = arm_base_z + (arm_tip_z - arm_base_z) * frac
            _add_barb_strand(
                bm,
                Vector((x_l, wy, wz)),
                Vector((x_r, wy, wz)),
                sag=span_sag,
                segments=strand_segments,
            )
    return arm_tip_z


def _add_barb_curved_topper(
    bm: bmesh.types.BMesh,
    post_xs: list[float],
    base_h: float,
    strand_segments: int = 3,
    curve_steps: int = 5,
) -> float:
    """Add curved swan-neck outrigger arms + 4 barbed strands across post_xs. Returns tip Z."""
    tip_z = base_h + 0.40
    p0_yz = Vector((0.0, base_h - 0.02))
    p1_yz = Vector((-0.06, base_h + 0.38))
    p2_yz = Vector((-0.40, tip_z))

    def _eval_curve(t: float) -> tuple[float, float]:
        mt = 1.0 - t
        pt = (mt * mt) * p0_yz + (2.0 * mt * t) * p1_yz + (t * t) * p2_yz
        return pt.x, pt.y

    for px in post_xs:
        _add_beveled_box(
            bm,
            Vector((px, 0.0, base_h - 0.03)),
            Vector((POST_W + 0.016, POST_D + 0.016, 0.07)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        arm_pts = [
            Vector((px, *_eval_curve(s / curve_steps)))
            for s in range(curve_steps + 1)
        ]
        _add_swept_tube(bm, arm_pts, radius=0.020, sides=6, mat_idx=MAT_METAL, cap_ends=True)

    for idx in range(len(post_xs) - 1):
        x_l, x_r = post_xs[idx], post_xs[idx + 1]
        span_sag = 0.018 * min(1.2, (x_r - x_l) / 2.0)
        for frac in (0.28, 0.52, 0.76, 0.98):
            wy, wz = _eval_curve(frac)
            _add_barb_strand(
                bm,
                Vector((x_l, wy, wz)),
                Vector((x_r, wy, wz)),
                sag=span_sag,
                segments=strand_segments,
            )
    return tip_z


def _add_barb_y_concertina_topper(
    bm: bmesh.types.BMesh,
    post_xs: list[float],
    base_h: float,
    turns: float = 6.0,
    segs_per_turn: int = 8,
    strand_segments: int = 2,
) -> float:
    """Add Y-arm V-brackets + 2 guide wires + concertina coil across post_xs. Returns crown Z."""
    arm_base_z = base_h - 0.02
    arm_tip_z = base_h + 0.42
    arm_spread_y = 0.28

    for px in post_xs:
        _add_beveled_box(
            bm,
            Vector((px, 0.0, base_h - 0.025)),
            Vector((POST_W + 0.018, POST_D + 0.018, 0.075)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        for side in (-1.0, 1.0):
            _add_box_between(
                bm,
                Vector((px, 0.0, arm_base_z)),
                Vector((px, side * arm_spread_y, arm_tip_z)),
                width=0.032,
                depth=0.032,
                mat_idx=MAT_METAL,
                bevel=0.0,
            )

    x_min, x_max = post_xs[0], post_xs[-1]
    for side in (-1.0, 1.0):
        _add_barb_strand(
            bm,
            Vector((x_min, side * arm_spread_y * 0.94, arm_tip_z - 0.02)),
            Vector((x_max, side * arm_spread_y * 0.94, arm_tip_z - 0.02)),
            sag=0.018,
            segments=strand_segments,
        )

    coil_z = base_h + 0.27
    _add_concertina_coil(
        bm,
        x_start=x_min + 0.02,
        x_end=x_max - 0.02,
        y_center=0.0,
        z_center=coil_z,
        coil_radius=0.20,
        turns=turns,
        segs_per_turn=segs_per_turn,
        ribbon_half_w=0.030,
    )
    return base_h + 0.50


def _add_door_surround_panel(
    bm: bmesh.types.BMesh,
    total_w: float = 4.0,
    door_w: float = 1.0,
    height: float = BASE_H,
    add_post_caps: bool = True,
) -> list[float]:
    """Build 4.0m fence bay with a centered 1.0m x 2.1m doorway cutout for `fence_door.glb`."""
    half_w = total_w * 0.5
    door_half = door_w * 0.5
    x_outer_l = -half_w + POST_W * 0.5
    x_inner_l = -(door_half + POST_W * 0.5)
    x_inner_r = door_half + POST_W * 0.5
    x_outer_r = half_w - POST_W * 0.5
    post_xs = [x_outer_l, x_inner_l, x_inner_r, x_outer_r]

    z_bot_rail = FOOTING_H + RAIL_BOT_H * 0.5
    z_mid_rail = height * 0.52
    z_top_rail = height - RAIL_TOP_H * 0.5

    # Footings: keep inner footings strictly outside [-door_half, +door_half] so door sits flush
    footing_xs = [
        -half_w + FOOTING_W * 0.5,
        -(door_half + FOOTING_W * 0.5),
        door_half + FOOTING_W * 0.5,
        half_w - FOOTING_W * 0.5,
    ]
    for px, fx in zip(post_xs, footing_xs):
        _add_beveled_box(
            bm,
            Vector((fx, 0.0, FOOTING_H * 0.5)),
            Vector((FOOTING_W, FOOTING_D, FOOTING_H)),
            mat_idx=MAT_CONCRETE,
            bevel=0.008,
        )
        post_z0 = FOOTING_H - 0.015
        post_z1 = height - 0.015 if add_post_caps else height
        post_h = post_z1 - post_z0
        _add_beveled_box(
            bm,
            Vector((px, 0.0, post_z0 + post_h * 0.5)),
            Vector((POST_W, POST_D, post_h)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        if add_post_caps:
            _add_beveled_box(
                bm,
                Vector((px, 0.0, height - 0.0075)),
                Vector((POST_W + 0.012, POST_D + 0.012, 0.015)),
                mat_idx=MAT_METAL,
                bevel=0.002,
            )

    # Left wing and Right wing chain-link bays (skip center doorway bay)
    for x_p0, x_p1 in ((x_outer_l, x_inner_l), (x_inner_r, x_outer_r)):
        x_l = x_p0 + POST_W * 0.5
        x_r = x_p1 - POST_W * 0.5
        bay_w = x_r - x_l
        bay_cx = (x_l + x_r) * 0.5
        _add_beveled_box(
            bm,
            Vector((bay_cx, 0.0, z_top_rail)),
            Vector((bay_w, RAIL_TOP_H, RAIL_TOP_H)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        _add_beveled_box(
            bm,
            Vector((bay_cx, 0.0, z_mid_rail)),
            Vector((bay_w, RAIL_MID_H, RAIL_MID_H)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        _add_beveled_box(
            bm,
            Vector((bay_cx, 0.0, z_bot_rail)),
            Vector((bay_w, RAIL_BOT_H, RAIL_BOT_H)),
            mat_idx=MAT_METAL,
            bevel=BEVEL_OFFSET,
        )
        _add_chain_link_quad(
            bm,
            x_min=x_l,
            x_max=x_r,
            z_min=z_bot_rail + RAIL_BOT_H * 0.45,
            z_max=z_top_rail - RAIL_TOP_H * 0.45,
            y_plane=0.0,
        )

    # Overhead doorway header tie-bar sitting just above z = 2.10m so fence_door slides cleanly under
    header_span = (x_inner_r - x_inner_l) + POST_W
    _add_beveled_box(
        bm,
        Vector((0.0, 0.0, height + RAIL_TOP_H * 0.5)),
        Vector((header_span, RAIL_TOP_H, RAIL_TOP_H)),
        mat_idx=MAT_METAL,
        bevel=BEVEL_OFFSET,
    )

    for px in post_xs:
        for rz in (z_bot_rail, z_mid_rail, z_top_rail):
            _add_beveled_box(
                bm,
                Vector((px, 0.0, rz)),
                Vector((POST_W + 0.014, POST_D + 0.014, 0.044)),
                mat_idx=MAT_METAL,
                bevel=0.0,
            )

    return post_xs


def _door_bay_col_boxes(
    mesh_name: str,
    top_h: float,
    col_depth: float,
    y_offset: float = 0.0,
    total_w: float = 4.0,
    door_w: float = 1.0,
) -> list[tuple[str, Vector, Vector]]:
    """Split L/R wing colliders + overhead header collider preserving 1.0m x 2.1m door opening."""
    wing_w = (total_w - door_w) * 0.5
    wing_cx = (door_w + wing_w) * 0.5
    boxes = [
        (f"{mesh_name}_Left-colonly", Vector((-wing_cx, y_offset, top_h * 0.5)), Vector((wing_w, col_depth, top_h))),
        (f"{mesh_name}_Right-colonly", Vector((wing_cx, y_offset, top_h * 0.5)), Vector((wing_w, col_depth, top_h))),
    ]
    header_h = max(0.06, top_h - BASE_H)
    boxes.append(
        (
            f"{mesh_name}_Header-colonly",
            Vector((0.0, y_offset, BASE_H + header_h * 0.5)),
            Vector((door_w, col_depth, header_h)),
        )
    )
    return boxes


# --- 4.0m Barbed-Wire Bays (2.1m base) ---


def build_fence_barb_45_4m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """7. 4.0m W x 2.5m H double-bay fence with 45-deg barbed-wire topper."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=4.0, height=BASE_H, center_post=True, add_post_caps=False)
    top_h = _add_barb_45_topper(bm, post_xs, BASE_H, strand_segments=2)
    return _finalize_and_export(
        slug="fence_barb_45_4m",
        mesh_name="FenceBarb45_4m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.04, top_h * 0.5)),
        col_size=Vector((4.0, 0.16, top_h)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 4.00 x 2.50 x 0.16m)",
        output_dir=output_dir,
        used_barb=True,
    )


def build_fence_barb_curved_4m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """8. 4.0m W x 2.5m H double-bay fence with curved swan-neck barbed-wire topper."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=4.0, height=BASE_H, center_post=True, add_post_caps=False)
    top_h = _add_barb_curved_topper(bm, post_xs, BASE_H, strand_segments=2, curve_steps=5)
    return _finalize_and_export(
        slug="fence_barb_curved_4m",
        mesh_name="FenceBarbCurved4m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.05, top_h * 0.5)),
        col_size=Vector((4.0, 0.18, top_h)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 4.00 x 2.50 x 0.18m)",
        output_dir=output_dir,
        used_barb=True,
    )


def build_fence_barb_y_concertina_4m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """9. 4.0m W x 2.6m H double-bay fence with Y-arm V-brackets + concertina razor-wire crown."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=4.0, height=BASE_H, center_post=True, add_post_caps=False)
    top_h = _add_barb_y_concertina_topper(bm, post_xs, BASE_H, turns=10.0, segs_per_turn=6, strand_segments=2)
    return _finalize_and_export(
        slug="fence_barb_y_concertina_4m",
        mesh_name="FenceBarbYConcertina4m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, top_h * 0.5)),
        col_size=Vector((4.0, 0.24, top_h)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 4.00 x 2.60 x 0.24m)",
        output_dir=output_dir,
        used_barb=True,
    )


# --- 4.0m Door-Surround Bays (centered 1.0m x 2.1m cutout for fence_door.glb) ---


def build_fence_door_bay_4m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """10. 4.0m W x 2.14m H fence surrounding a centered 1.0m x 2.1m doorway cutout."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    _add_door_surround_panel(bm, total_w=4.0, door_w=1.0, height=BASE_H, add_post_caps=True)
    top_h = BASE_H + RAIL_TOP_H
    return _finalize_and_export(
        slug="fence_door_bay_4m",
        mesh_name="FenceDoorBay4m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, top_h * 0.5)),
        col_size=Vector((4.0, 0.08, top_h)),
        collision_hint="StaticBody3D split L/R/Header BoxShape3D (-colonly, 1.0m x 2.1m door cutout)",
        output_dir=output_dir,
        used_barb=False,
        col_boxes=_door_bay_col_boxes("FenceDoorBay4m", top_h, 0.08),
    )


def build_fence_door_bay_4m_barb_45(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """11. 4.0m door-surround bay with 45-deg barbed-wire topper."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_door_surround_panel(bm, total_w=4.0, door_w=1.0, height=BASE_H, add_post_caps=False)
    top_h = _add_barb_45_topper(bm, post_xs, BASE_H, strand_segments=2)
    return _finalize_and_export(
        slug="fence_door_bay_4m_barb_45",
        mesh_name="FenceDoorBay4mBarb45",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.04, top_h * 0.5)),
        col_size=Vector((4.0, 0.16, top_h)),
        collision_hint="StaticBody3D split L/R/Header BoxShape3D (-colonly, 1.0m x 2.1m door cutout)",
        output_dir=output_dir,
        used_barb=True,
        col_boxes=_door_bay_col_boxes("FenceDoorBay4mBarb45", top_h, 0.16, y_offset=-0.04),
    )


def build_fence_door_bay_4m_barb_curved(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """12. 4.0m door-surround bay with curved swan-neck barbed-wire topper."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_door_surround_panel(bm, total_w=4.0, door_w=1.0, height=BASE_H, add_post_caps=False)
    top_h = _add_barb_curved_topper(bm, post_xs, BASE_H, strand_segments=2, curve_steps=4)
    return _finalize_and_export(
        slug="fence_door_bay_4m_barb_curved",
        mesh_name="FenceDoorBay4mBarbCurved",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.05, top_h * 0.5)),
        col_size=Vector((4.0, 0.18, top_h)),
        collision_hint="StaticBody3D split L/R/Header BoxShape3D (-colonly, 1.0m x 2.1m door cutout)",
        output_dir=output_dir,
        used_barb=True,
        col_boxes=_door_bay_col_boxes("FenceDoorBay4mBarbCurved", top_h, 0.18, y_offset=-0.05),
    )


def build_fence_door_bay_4m_barb_y_concertina(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """13. 4.0m door-surround bay with Y-arm V-brackets + concertina razor-wire crown."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_door_surround_panel(bm, total_w=4.0, door_w=1.0, height=BASE_H, add_post_caps=False)
    top_h = _add_barb_y_concertina_topper(bm, post_xs, BASE_H, turns=9.0, segs_per_turn=6, strand_segments=2)
    return _finalize_and_export(
        slug="fence_door_bay_4m_barb_y_concertina",
        mesh_name="FenceDoorBay4mBarbYConcertina",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, top_h * 0.5)),
        col_size=Vector((4.0, 0.24, top_h)),
        collision_hint="StaticBody3D split L/R/Header BoxShape3D (-colonly, 1.0m x 2.1m door cutout)",
        output_dir=output_dir,
        used_barb=True,
        col_boxes=_door_bay_col_boxes("FenceDoorBay4mBarbYConcertina", top_h, 0.24),
    )


# --- 1.0m Wide x 2.0m Tall Narrow/Short Variations ---

SHORT_H = 2.00


def build_fence_straight_1m_2m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """14. Narrow 1.0m W x 2.0m H chain-link fence panel."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    _add_base_fence_panel(bm, width=1.0, height=SHORT_H, center_post=False)
    return _finalize_and_export(
        slug="fence_straight_1m_2m",
        mesh_name="FenceStraight1m2m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, SHORT_H * 0.5)),
        col_size=Vector((1.0, 0.08, SHORT_H)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 1.00 x 2.00 x 0.08m)",
        output_dir=output_dir,
        used_barb=False,
    )


def build_fence_barb_45_1m_2m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """15. Narrow 1.0m W x 2.4m H (2.0m base) fence with 45-deg barbed-wire topper."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=1.0, height=SHORT_H, add_post_caps=False)
    top_h = _add_barb_45_topper(bm, post_xs, SHORT_H, strand_segments=2)
    return _finalize_and_export(
        slug="fence_barb_45_1m_2m",
        mesh_name="FenceBarb45_1m2m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.04, top_h * 0.5)),
        col_size=Vector((1.0, 0.16, top_h)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 1.00 x 2.40 x 0.16m)",
        output_dir=output_dir,
        used_barb=True,
    )


def build_fence_barb_curved_1m_2m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """16. Narrow 1.0m W x 2.4m H (2.0m base) fence with curved swan-neck barbed-wire topper."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=1.0, height=SHORT_H, add_post_caps=False)
    top_h = _add_barb_curved_topper(bm, post_xs, SHORT_H, strand_segments=2, curve_steps=5)
    return _finalize_and_export(
        slug="fence_barb_curved_1m_2m",
        mesh_name="FenceBarbCurved1m2m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.05, top_h * 0.5)),
        col_size=Vector((1.0, 0.18, top_h)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 1.00 x 2.40 x 0.18m)",
        output_dir=output_dir,
        used_barb=True,
    )


def build_fence_barb_y_concertina_1m_2m(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """17. Narrow 1.0m W x 2.5m H (2.0m base) fence with Y-arm V-brackets + concertina crown."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_base_fence_panel(bm, width=1.0, height=SHORT_H, add_post_caps=False)
    top_h = _add_barb_y_concertina_topper(bm, post_xs, SHORT_H, turns=3.5, segs_per_turn=8, strand_segments=2)
    return _finalize_and_export(
        slug="fence_barb_y_concertina_1m_2m",
        mesh_name="FenceBarbYConcertina1m2m",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, top_h * 0.5)),
        col_size=Vector((1.0, 0.24, top_h)),
        collision_hint="StaticBody3D BoxShape3D (-colonly, 1.00 x 2.50 x 0.24m)",
        output_dir=output_dir,
        used_barb=True,
    )


# --- Compact 1.80m Door-Surround Bays (0.40m wings + 1.0m x 2.1m door cutout) ---

COMPACT_DOOR_W = 1.80


def build_fence_door_bay_compact(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """18. Compact 1.80m W x 2.14m H door-surround bay (0.40m chain-link wings)."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    _add_door_surround_panel(bm, total_w=COMPACT_DOOR_W, door_w=1.0, height=BASE_H, add_post_caps=True)
    top_h = BASE_H + RAIL_TOP_H
    return _finalize_and_export(
        slug="fence_door_bay_compact",
        mesh_name="FenceDoorBayCompact",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, top_h * 0.5)),
        col_size=Vector((COMPACT_DOOR_W, 0.08, top_h)),
        collision_hint="StaticBody3D split L/R (0.40m) + Header BoxShape3D (-colonly, 1.0m x 2.1m cutout)",
        output_dir=output_dir,
        used_barb=False,
        col_boxes=_door_bay_col_boxes("FenceDoorBayCompact", top_h, 0.08, total_w=COMPACT_DOOR_W),
    )


def build_fence_door_bay_compact_barb_45(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """19. Compact 1.80m door-surround bay with 45-deg barbed-wire topper."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_door_surround_panel(
        bm, total_w=COMPACT_DOOR_W, door_w=1.0, height=BASE_H, add_post_caps=False
    )
    top_h = _add_barb_45_topper(bm, post_xs, BASE_H, strand_segments=2)
    return _finalize_and_export(
        slug="fence_door_bay_compact_barb_45",
        mesh_name="FenceDoorBayCompactBarb45",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.04, top_h * 0.5)),
        col_size=Vector((COMPACT_DOOR_W, 0.16, top_h)),
        collision_hint="StaticBody3D split L/R (0.40m) + Header BoxShape3D (-colonly, 1.0m x 2.1m cutout)",
        output_dir=output_dir,
        used_barb=True,
        col_boxes=_door_bay_col_boxes(
            "FenceDoorBayCompactBarb45", top_h, 0.16, y_offset=-0.04, total_w=COMPACT_DOOR_W
        ),
    )


def build_fence_door_bay_compact_barb_curved(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """20. Compact 1.80m door-surround bay with curved swan-neck barbed-wire topper."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_door_surround_panel(
        bm, total_w=COMPACT_DOOR_W, door_w=1.0, height=BASE_H, add_post_caps=False
    )
    top_h = _add_barb_curved_topper(bm, post_xs, BASE_H, strand_segments=2, curve_steps=4)
    return _finalize_and_export(
        slug="fence_door_bay_compact_barb_curved",
        mesh_name="FenceDoorBayCompactBarbCurved",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, -0.05, top_h * 0.5)),
        col_size=Vector((COMPACT_DOOR_W, 0.18, top_h)),
        collision_hint="StaticBody3D split L/R (0.40m) + Header BoxShape3D (-colonly, 1.0m x 2.1m cutout)",
        output_dir=output_dir,
        used_barb=True,
        col_boxes=_door_bay_col_boxes(
            "FenceDoorBayCompactBarbCurved", top_h, 0.18, y_offset=-0.05, total_w=COMPACT_DOOR_W
        ),
    )


def build_fence_door_bay_compact_barb_y_concertina(
    project_root: Path, output_dir: Path
) -> dict[str, Any]:
    """21. Compact 1.80m door-surround bay with Y-arm V-brackets + concertina crown."""
    clean_scene()
    mats = _create_kit_materials(project_root)
    bm = bmesh.new()
    post_xs = _add_door_surround_panel(
        bm, total_w=COMPACT_DOOR_W, door_w=1.0, height=BASE_H, add_post_caps=False
    )
    top_h = _add_barb_y_concertina_topper(
        bm, post_xs, BASE_H, turns=5.5, segs_per_turn=7, strand_segments=2
    )
    return _finalize_and_export(
        slug="fence_door_bay_compact_barb_y_concertina",
        mesh_name="FenceDoorBayCompactBarbYConcertina",
        bm=bm,
        mats=mats,
        col_center=Vector((0.0, 0.0, top_h * 0.5)),
        col_size=Vector((COMPACT_DOOR_W, 0.24, top_h)),
        collision_hint="StaticBody3D split L/R (0.40m) + Header BoxShape3D (-colonly, 1.0m x 2.1m cutout)",
        output_dir=output_dir,
        used_barb=True,
        col_boxes=_door_bay_col_boxes(
            "FenceDoorBayCompactBarbYConcertina", top_h, 0.24, total_w=COMPACT_DOOR_W
        ),
    )


def build_all(project_root: Path, output_dir: Path) -> dict[str, Any]:
    """Generate all 21 intact fence kit GLBs and write manifest_intact.json."""
    output_dir.mkdir(parents=True, exist_ok=True)
    builders = [
        build_fence_straight_2m,
        build_fence_straight_4m,
        build_fence_barb_45_2m,
        build_fence_barb_curved_2m,
        build_fence_barb_y_concertina_2m,
        build_fence_post_corner,
        build_fence_barb_45_4m,
        build_fence_barb_curved_4m,
        build_fence_barb_y_concertina_4m,
        build_fence_door_bay_4m,
        build_fence_door_bay_4m_barb_45,
        build_fence_door_bay_4m_barb_curved,
        build_fence_door_bay_4m_barb_y_concertina,
        build_fence_straight_1m_2m,
        build_fence_barb_45_1m_2m,
        build_fence_barb_curved_1m_2m,
        build_fence_barb_y_concertina_1m_2m,
        build_fence_door_bay_compact,
        build_fence_door_bay_compact_barb_45,
        build_fence_door_bay_compact_barb_curved,
        build_fence_door_bay_compact_barb_y_concertina,
    ]
    assets: list[dict[str, Any]] = []
    for builder in builders:
        assets.append(builder(project_root, output_dir))

    manifest = {
        "kit": "chain_link_fence_kit_intact",
        "layer": "Layer 1 Environment",
        "source": "procedural_bpy",
        "assets": assets,
    }
    manifest_path = output_dir / "manifest_intact.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[fence_kit_intact] Wrote {manifest_path} ({len(assets)} GLBs)")
    return manifest


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate intact HL2 chain-link fence kit GLBs")
    parser.add_argument(
        "--output-dir",
        default="assets/models/chain_link_fence_kit",
        help="Output directory relative to project root",
    )
    args = parser.parse_args(argv)
    project_root = Path(__file__).resolve().parent.parent.parent.parent
    out_dir = (project_root / args.output_dir).resolve()
    build_all(project_root, out_dir)


if __name__ == "__main__":
    main()
