"""Procedural Blender generator for the 5 HL2-style damaged chain-link fence kit variants.

Generates modular damaged fence panels matching the BellaSDK fence door & intact kit:
1. fence_bent_impact_2m.glb  (2.0m W x 2.5m H — bent right post, kinked rail, sagging mesh + slack barbed wire)
2. fence_crawl_under_2m.glb  (2.0m W x 2.1m H — bottom torn/curled up >= 0.85m crawl clearance; upper+post -colonly)
3. fence_breach_hole_2m.glb  (2.0m W x 2.1m H — jagged center walk-through >= 0.95m x 1.75m; split L/R -colonly)
4. fence_collapsed_2m.glb    (2.0m W x ~0.55m H — snapped post stumps + crushed panel at ~72 deg; low walk-over -colonly)
5. fence_broken_end_1m.glb   (1.0m W x 2.1m H — sheared half-panel with dangling top rail & torn edge; -colonly)

Conventions:
- Bottom-center origin (0, 0, 0), facing -Y in Blender (-Z in Godot), grounded min_z = 0.
- Material slots: 0=M_MetalFrame, 1=M_ChainLink, 2=M_Concrete, 3=M_BarbedWire.
- Invisible alpha-clipped material on `-colonly` boxes so Blender QA renders stay unobstructed
  while Godot 4 glTF import converts them to StaticBody3D collision shapes.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import create_pbr_material
from mathutils import Euler, Matrix, Vector

# Shared kit dimensions (aligned with fence_door.py & intact kit)
PANEL_W = 2.00
PANEL_H = 2.10
POST_X = 0.972
POST_R = 0.028
TOP_RAIL_Z = 2.06
TOP_RAIL_R = 0.020
MID_RAIL_Z = 1.05
MID_RAIL_R = 0.017
BOT_WIRE_Z = 0.10
BOT_WIRE_R = 0.008

FOOTING_SIZE = Vector((0.16, 0.16, 0.14))
FOOTING_BEVEL = 0.008
METAL_BEVEL = 0.0025

CHAIN_UV_TILES_PER_M = 10.0
METAL_UV_TILE_M = 1.0
CONCRETE_UV_TILE_M = 0.6

MAT_METAL = 0
MAT_CHAIN = 1
MAT_CONCRETE = 2
MAT_BARB = 3


def _load_image_if_exists(path: Path) -> bpy.types.Image | None:
    if path.is_file():
        return bpy.data.images.load(str(path.resolve()), check_existing=True)
    return None


def _attach_metallic_image(mat: bpy.types.Material, metallic_image: bpy.types.Image | None) -> None:
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


def _create_invisible_col_material() -> bpy.types.Material:
    """Create a fully transparent alpha-clipped material for -colonly proxies."""
    mat = bpy.data.materials.new(name="M_ColOnly_Invisible")
    mat.use_nodes = True
    mat.use_backface_culling = False
    if hasattr(mat, "blend_method"):
        mat.blend_method = "CLIP"
    if hasattr(mat, "alpha_threshold"):
        mat.alpha_threshold = 0.5
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 0.0)
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = 0.0
    return mat


def _build_materials(project_root: Path) -> list[bpy.types.Material]:
    """Create the 4 kit materials binding project PBR textures."""
    metal_dir = project_root / "assets/materials/fence_door_metal/textures"
    chain_dir = project_root / "assets/materials/chain_link_fence/textures"
    conc_dir = project_root / "assets/materials/weathered_concrete/textures"
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
        metallic=0.82,
        roughness=0.52,
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
        roughness=0.88,
        base_color_image=_load_image_if_exists(conc_dir / "weathered_concrete_albedo.png"),
        roughness_image=_load_image_if_exists(conc_dir / "weathered_concrete_roughness.png"),
        normal_image=_load_image_if_exists(conc_dir / "weathered_concrete_normal.png"),
        normal_strength=0.85,
    )

    mat_barb = create_pbr_material(
        name="M_BarbedWire",
        base_color=(0.38, 0.34, 0.30, 1.0),
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

    return [mat_metal, mat_chain, mat_concrete, mat_barb]


def _append_tmp_bmesh(dst: bmesh.types.BMesh, src: bmesh.types.BMesh, mat_idx: int) -> None:
    """Merge a temporary BMesh into dst with a given material_index."""
    for face in src.faces:
        face.material_index = mat_idx
    mesh_tmp = bpy.data.meshes.new("_tmp_geo")
    src.to_mesh(mesh_tmp)
    src.free()
    dst.from_mesh(mesh_tmp)
    bpy.data.meshes.remove(mesh_tmp)


def _add_beveled_box(
    bm: bmesh.types.BMesh,
    center: Vector,
    size: Vector,
    mat_idx: int = MAT_METAL,
    bevel: float = METAL_BEVEL,
    rot_euler: tuple[float, float, float] = (0.0, 0.0, 0.0),
    ground_min_z: float | None = None,
) -> None:
    """Add a beveled box with optional Euler rotation and min-Z grounding clamp."""
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
    if any(abs(a) > 1e-6 for a in rot_euler):
        rot_mat = Euler(rot_euler, "XYZ").to_matrix().to_4x4()
        bmesh.ops.transform(tmp, matrix=rot_mat, verts=tmp.verts)
    bmesh.ops.translate(tmp, vec=center, verts=tmp.verts)

    if ground_min_z is not None:
        min_z = min(v.co.z for v in tmp.verts)
        if min_z < ground_min_z:
            bmesh.ops.translate(tmp, vec=Vector((0.0, 0.0, ground_min_z - min_z)), verts=tmp.verts)

    _append_tmp_bmesh(bm, tmp, mat_idx)


def _add_footing(
    bm: bmesh.types.BMesh,
    x: float,
    y: float = 0.0,
    tilt_x_deg: float = 0.0,
    tilt_y_deg: float = 0.0,
    cracked: bool = False,
) -> None:
    """Add a concrete post footing (optionally tilted and accompanied by rubble chunks)."""
    _add_beveled_box(
        bm,
        center=Vector((x, y, FOOTING_SIZE.z * 0.5)),
        size=FOOTING_SIZE,
        mat_idx=MAT_CONCRETE,
        bevel=FOOTING_BEVEL,
        rot_euler=(math.radians(tilt_x_deg), math.radians(tilt_y_deg), 0.0),
        ground_min_z=0.0,
    )
    if cracked:
        _add_beveled_box(
            bm,
            center=Vector((x + 0.09, y - 0.08, 0.025)),
            size=Vector((0.065, 0.055, 0.045)),
            mat_idx=MAT_CONCRETE,
            bevel=0.006,
            rot_euler=(math.radians(12.0), math.radians(-18.0), math.radians(28.0)),
            ground_min_z=0.0,
        )
        _add_beveled_box(
            bm,
            center=Vector((x - 0.08, y - 0.09, 0.018)),
            size=Vector((0.048, 0.042, 0.032)),
            mat_idx=MAT_CONCRETE,
            bevel=0.005,
            rot_euler=(math.radians(-8.0), math.radians(15.0), math.radians(-35.0)),
            ground_min_z=0.0,
        )


def _add_cylinder_between(
    bm: bmesh.types.BMesh,
    p1: Vector,
    p2: Vector,
    radius: float,
    segments: int = 8,
    mat_idx: int = MAT_METAL,
    r2: float | None = None,
) -> None:
    """Create a capped cylinder connecting p1 to p2."""
    vec = p2 - p1
    length = vec.length
    if length < 1e-6:
        return
    mid = (p1 + p2) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    trans = Matrix.Translation(mid)

    tmp = bmesh.new()
    bmesh.ops.create_cone(
        tmp,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius if r2 is None else r2,
        depth=length,
        matrix=trans @ rot,
    )
    _append_tmp_bmesh(bm, tmp, mat_idx)


def _add_polyline_tube(
    bm: bmesh.types.BMesh,
    points: list[Vector],
    radius: float,
    segments: int = 8,
    mat_idx: int = MAT_METAL,
) -> None:
    """Build a segmented steel pipe along a list of 3D points."""
    for idx in range(len(points) - 1):
        _add_cylinder_between(bm, points[idx], points[idx + 1], radius, segments, mat_idx)


def _add_post_cap(bm: bmesh.types.BMesh, top: Vector, axis: Vector, radius: float = POST_R) -> None:
    """Add a slightly wider welded steel cap collar at the top of a fence post."""
    d = axis.normalized()
    _add_cylinder_between(
        bm,
        top - d * 0.015,
        top + d * 0.022,
        radius=radius * 1.18,
        segments=8,
        mat_idx=MAT_METAL,
    )


def _add_barbed_wire_strand(
    bm: bmesh.types.BMesh,
    points: list[Vector],
    ribbon_height: float = 0.075,
    uv_tiles_per_m: float = 3.2,
) -> None:
    """Add a 4-sided 3D core wire plus a two-sided alpha-scissor barb ribbon along points."""
    _add_polyline_tube(bm, points, radius=0.004, segments=4, mat_idx=MAT_METAL)

    uv_layer = bm.loops.layers.uv.verify()
    half_h = ribbon_height * 0.5
    up = Vector((0.0, 0.0, 1.0))

    # Build two crossed ribbons (vertical + tilted 60 deg) or a single clean vertical ribbon.
    # A single vertical ribbon along the wire keeps tri count tiny and reads cleanly from front/back.
    cum_len = 0.0
    prev_bot = None
    prev_top = None
    prev_u = 0.0
    for idx, pt in enumerate(points):
        if idx > 0:
            cum_len += (pt - points[idx - 1]).length
        u = cum_len * uv_tiles_per_m
        v_bot = bm.verts.new(pt - up * half_h)
        v_top = bm.verts.new(pt + up * half_h)
        if prev_bot is not None and prev_top is not None:
            face = bm.faces.new((prev_bot, v_bot, v_top, prev_top))
            face.material_index = MAT_BARB
            face.loops[0][uv_layer].uv = (prev_u, 0.0)
            face.loops[1][uv_layer].uv = (u, 0.0)
            face.loops[2][uv_layer].uv = (u, 1.0)
            face.loops[3][uv_layer].uv = (prev_u, 1.0)
        prev_bot = v_bot
        prev_top = v_top
        prev_u = u


def _add_parametric_chain_strip(
    bm: bmesh.types.BMesh,
    nx: int,
    nz: int,
    orig_xz_fn,
    deform_fn,
    uv_origin: tuple[float, float] = (-POST_X, BOT_WIRE_Z),
) -> None:
    """Create a conformal subdivided chain-link strip with exact jagged edges and unstretched UVs."""
    uv_layer = bm.loops.layers.uv.verify()
    grid_verts: list[list[bmesh.types.BMVert]] = []
    grid_uvs: list[list[tuple[float, float]]] = []

    for iz in range(nz + 1):
        vz = iz / float(nz)
        row_v: list[bmesh.types.BMVert] = []
        row_uv: list[tuple[float, float]] = []
        for ix in range(nx + 1):
            ux = ix / float(nx)
            x0, z0 = orig_xz_fn(ux, vz)
            pos = deform_fn(x0, z0, ux, vz)
            row_v.append(bm.verts.new(pos))
            row_uv.append(
                (
                    (x0 - uv_origin[0]) * CHAIN_UV_TILES_PER_M,
                    (z0 - uv_origin[1]) * CHAIN_UV_TILES_PER_M,
                )
            )
        grid_verts.append(row_v)
        grid_uvs.append(row_uv)

    for iz in range(nz):
        for ix in range(nx):
            v00 = grid_verts[iz][ix]
            v10 = grid_verts[iz][ix + 1]
            v11 = grid_verts[iz + 1][ix + 1]
            v01 = grid_verts[iz + 1][ix]
            try:
                face = bm.faces.new((v00, v10, v11, v01))
            except ValueError:
                continue
            face.material_index = MAT_CHAIN
            face.loops[0][uv_layer].uv = grid_uvs[iz][ix]
            face.loops[1][uv_layer].uv = grid_uvs[iz][ix + 1]
            face.loops[2][uv_layer].uv = grid_uvs[iz + 1][ix + 1]
            face.loops[3][uv_layer].uv = grid_uvs[iz + 1][ix]


def _add_deformed_chain_grid(
    bm: bmesh.types.BMesh,
    nx: int,
    nz: int,
    x_min: float,
    x_max: float,
    z_min: float,
    z_max: float,
    deform_fn,
    keep_quad_fn=None,
) -> None:
    """Create a subdivided deformable chain-link mesh with unstretched tiled UVs."""
    uv_layer = bm.loops.layers.uv.verify()
    grid_verts: list[list[bmesh.types.BMVert | None]] = [
        [None for _ in range(nx + 1)] for _ in range(nz + 1)
    ]
    grid_uvs: list[list[tuple[float, float]]] = [
        [(0.0, 0.0) for _ in range(nx + 1)] for _ in range(nz + 1)
    ]

    for iz in range(nz + 1):
        vz = iz / float(nz)
        z0 = z_min + (z_max - z_min) * vz
        for ix in range(nx + 1):
            ux = ix / float(nx)
            x0 = x_min + (x_max - x_min) * ux
            grid_uvs[iz][ix] = (
                (x0 - x_min) * CHAIN_UV_TILES_PER_M,
                (z0 - z_min) * CHAIN_UV_TILES_PER_M,
            )

    def get_vert(iz: int, ix: int) -> bmesh.types.BMVert:
        v = grid_verts[iz][ix]
        if v is None:
            ux = ix / float(nx)
            vz = iz / float(nz)
            x0 = x_min + (x_max - x_min) * ux
            z0 = z_min + (z_max - z_min) * vz
            pos = deform_fn(x0, z0, ux, vz)
            v = bm.verts.new(pos)
            grid_verts[iz][ix] = v
        return v

    for iz in range(nz):
        z_mid = z_min + (z_max - z_min) * ((iz + 0.5) / float(nz))
        for ix in range(nx):
            x_mid = x_min + (x_max - x_min) * ((ix + 0.5) / float(nx))
            if keep_quad_fn is not None and not keep_quad_fn(x_mid, z_mid):
                continue
            v00 = get_vert(iz, ix)
            v10 = get_vert(iz, ix + 1)
            v11 = get_vert(iz + 1, ix + 1)
            v01 = get_vert(iz + 1, ix)
            try:
                face = bm.faces.new((v00, v10, v11, v01))
            except ValueError:
                continue
            face.material_index = MAT_CHAIN
            face.loops[0][uv_layer].uv = grid_uvs[iz][ix]
            face.loops[1][uv_layer].uv = grid_uvs[iz][ix + 1]
            face.loops[2][uv_layer].uv = grid_uvs[iz + 1][ix + 1]
            face.loops[3][uv_layer].uv = grid_uvs[iz + 1][ix]


def _box_project_uvs(bm: bmesh.types.BMesh, tile_meters: float, mat_filter: int) -> None:
    """Assign metric box-projected UVs to faces matching mat_filter."""
    uv_layer = bm.loops.layers.uv.verify()
    scale = 1.0 / tile_meters
    for face in bm.faces:
        if face.material_index != mat_filter:
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


def _create_colonly_box(
    name: str,
    bmin: Vector,
    bmax: Vector,
    parent: bpy.types.Object,
    col_mat: bpy.types.Material,
) -> bpy.types.Object:
    """Create a Godot `-colonly` box collider mesh parented to the visual mesh."""
    center = (bmin + bmax) * 0.5
    size = bmax - bmin
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    _box_project_uvs(bm, 1.0, 0)
    bmesh.ops.triangulate(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    obj.parent = parent
    obj.display_type = "WIRE"
    obj.data.materials.append(col_mat)
    bpy.context.collection.objects.link(obj)
    return obj


def _finalize_and_export(
    slug: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    col_boxes: list[tuple[str, Vector, Vector]],
    collision_hint: str,
    output_dir: Path,
) -> dict[str, object]:
    """Finalize UVs, ground min_z = 0, attach -colonly proxies, export GLB, return manifest row."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Ensure strictly grounded min_z = 0.0 on the visual mesh
    min_z = min(v.co.z for v in bm.verts)
    if abs(min_z) > 1e-5:
        bmesh.ops.translate(bm, vec=Vector((0.0, 0.0, -min_z)), verts=bm.verts)

    _box_project_uvs(bm, METAL_UV_TILE_M, MAT_METAL)
    _box_project_uvs(bm, CONCRETE_UV_TILE_M, MAT_CONCRETE)
    bmesh.ops.triangulate(bm, faces=bm.faces)

    tri_count = len(bm.faces)
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    dims = {
        "x": round(max(xs) - min(xs), 4),
        "y": round(max(zs) - min(zs), 4),  # Godot Y = Blender Z
        "z": round(max(ys) - min(ys), 4),
    }

    mesh = bpy.data.meshes.new(f"SM_{slug}")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(slug, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        obj.data.materials.append(mat)

    col_mat = _create_invisible_col_material()
    for col_name, bmin, bmax in col_boxes:
        _create_colonly_box(col_name, bmin, bmax, obj, col_mat)

    bpy.context.view_layer.update()
    glb_path = output_dir / f"{slug}.glb"
    export_godot_glb(glb_path, export_animations=False, apply_modifiers=True)

    entry = {
        "slug": slug,
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": dims,
        "min_z_m": round(min(zs), 5),
        "collision_hint": collision_hint,
        "glb_path": f"res://assets/models/chain_link_fence_kit/{slug}.glb",
    }
    print(f"[fence_kit_damaged] Exported {slug}.glb ({tri_count} tris, dims={dims})")
    return entry


# ==============================================================================
# 1. fence_bent_impact_2m.glb
# ==============================================================================
def build_bent_impact(project_root: Path, output_dir: Path) -> dict[str, object]:
    """2.0m W x 2.5m H — right post bent ~25 deg, kinked rail, sagging mesh + slack barbed wires."""
    clean_scene()
    materials = _build_materials(project_root)
    bm = bmesh.new()

    # Footings: left intact, right cracked & tilted toward -Y
    _add_footing(bm, -POST_X, 0.0)
    _add_footing(bm, POST_X, 0.0, tilt_x_deg=-14.0, tilt_y_deg=4.0, cracked=True)

    # Left post (vertical) + 45 deg outrigger arm pointing -Y / +Z
    p_l_bot = Vector((-POST_X, 0.0, 0.0))
    p_l_top = Vector((-POST_X, 0.0, PANEL_H))
    _add_cylinder_between(bm, p_l_bot, p_l_top, POST_R, segments=8)
    _add_post_cap(bm, p_l_top, Vector((0.0, 0.0, 1.0)))

    arm_len = 0.56
    arm_l_dir = Vector((0.0, -math.sin(math.radians(45.0)), math.cos(math.radians(45.0))))
    arm_l_tip = p_l_top + arm_l_dir * arm_len
    _add_cylinder_between(bm, p_l_top - Vector((0.0, 0.0, 0.03)), arm_l_tip, 0.018, segments=6)

    # Right post: vertical stump 0..0.28m, then bent ~25 deg off vertical toward -Y (and +4 deg X)
    bend_rad = math.radians(25.0)
    lean_x_rad = math.radians(4.0)
    r_dir = Vector((
        math.sin(lean_x_rad),
        -math.sin(bend_rad) * math.cos(lean_x_rad),
        math.cos(bend_rad) * math.cos(lean_x_rad),
    )).normalized()

    p_r_bot = Vector((POST_X, 0.0, 0.0))
    p_r_knee = Vector((POST_X, -0.02, 0.28))
    p_r_top = p_r_knee + r_dir * (PANEL_H - 0.28)
    _add_polyline_tube(bm, [p_r_bot, p_r_knee, p_r_top], POST_R, segments=8)
    _add_post_cap(bm, p_r_top, r_dir)

    # Right 45-deg outrigger arm rotated further down with the bent post (~68 deg from vertical)
    arm_r_dir = Vector((0.08, -math.sin(math.radians(66.0)), math.cos(math.radians(66.0)))).normalized()
    arm_r_tip = p_r_top + arm_r_dir * arm_len
    _add_cylinder_between(bm, p_r_top - r_dir * 0.03, arm_r_tip, 0.018, segments=6)

    # Helper to sample left and right post centerlines at parameter v in [0, 1]
    def left_post_pt(v: float) -> Vector:
        return p_l_bot.lerp(p_l_top, v)

    def right_post_pt(v: float) -> Vector:
        z_target = v * PANEL_H
        if z_target <= 0.28:
            t = z_target / 0.28
            return p_r_bot.lerp(p_r_knee, t)
        t = (z_target - 0.28) / (PANEL_H - 0.28)
        return p_r_knee.lerp(p_r_top, t)

    # Kinked top rail
    tr_l = left_post_pt(TOP_RAIL_Z / PANEL_H)
    tr_r = right_post_pt(TOP_RAIL_Z / PANEL_H)
    tr_kink = tr_l.lerp(tr_r, 0.65) + Vector((0.0, -0.18, -0.13))
    _add_polyline_tube(bm, [tr_l, tr_kink, tr_r], TOP_RAIL_R, segments=6)

    # Kinked mid rail
    mr_l = left_post_pt(MID_RAIL_Z / PANEL_H)
    mr_r = right_post_pt(MID_RAIL_Z / PANEL_H)
    mr_kink = mr_l.lerp(mr_r, 0.68) + Vector((0.0, -0.22, -0.07))
    _add_polyline_tube(bm, [mr_l, mr_kink, mr_r], MID_RAIL_R, segments=6)

    # Bottom tension wire
    bw_l = left_post_pt(BOT_WIRE_Z / PANEL_H)
    bw_r = right_post_pt(BOT_WIRE_Z / PANEL_H)
    bw_mid = bw_l.lerp(bw_r, 0.62) + Vector((0.0, -0.05, 0.0))
    _add_polyline_tube(bm, [bw_l, bw_mid, bw_r], BOT_WIRE_R, segments=6)

    # Warped, sagging chain-link mesh (16 x 12 = 384 tris)
    def deform_bent(_x0: float, _z0: float, u: float, v: float) -> Vector:
        v_rail = (BOT_WIRE_Z + v * (TOP_RAIL_Z - BOT_WIRE_Z)) / PANEL_H
        p_l = left_post_pt(v_rail)
        p_r = right_post_pt(v_rail)
        base = p_l.lerp(p_r, u)

        # Follow kinked rail bend profile across u (peaking at u=0.66)
        kink_w = math.exp(-((u - 0.66) / 0.26) ** 2)
        bulge_y = -0.22 * kink_w * math.sin(v * math.pi * 0.85 + 0.15)
        sag_z = -0.13 * kink_w * (v ** 1.3)
        # Subtle slack ripple in chain-link
        ripple_y = 0.025 * math.sin(u * math.pi * 3.0) * math.sin(v * math.pi)
        return Vector((base.x, base.y + bulge_y + ripple_y, max(0.03, base.z + sag_z)))

    _add_deformed_chain_grid(
        bm,
        nx=16,
        nz=12,
        x_min=-POST_X + POST_R,
        x_max=POST_X - POST_R,
        z_min=BOT_WIRE_Z,
        z_max=TOP_RAIL_Z,
        deform_fn=deform_bent,
    )

    # 3 slackened barbed-wire strands between left & right 45-deg outrigger arms
    for frac, sag_amp in ((0.35, 0.16), (0.68, 0.22), (0.96, 0.27)):
        p_start = p_l_top.lerp(arm_l_tip, frac)
        p_end = p_r_top.lerp(arm_r_tip, frac)
        strand_pts: list[Vector] = []
        steps = 6
        for i in range(steps + 1):
            t = i / float(steps)
            pt = p_start.lerp(p_end, t)
            # Catenary sag + slight forward drift
            sag = 4.0 * t * (1.0 - t)
            pt.z -= sag_amp * sag
            pt.y -= 0.06 * sag
            strand_pts.append(pt)
        _add_barbed_wire_strand(bm, strand_pts, ribbon_height=0.07)

    col_boxes = [
        (
            "FenceBentImpact_Col-colonly",
            Vector((-1.02, -1.20, 0.0)),
            Vector((1.15, 0.14, 2.50)),
        )
    ]
    return _finalize_and_export(
        "fence_bent_impact_2m",
        bm,
        materials,
        col_boxes,
        "Solid BoxShape3D (-colonly) covering bent panel footprint",
        output_dir,
    )


# ==============================================================================
# 2. fence_crawl_under_2m.glb
# ==============================================================================
def build_crawl_under(project_root: Path, output_dir: Path) -> dict[str, object]:
    """2.0m W x 2.1m H — bottom chain-link torn & curled up >= 0.85m clearance; upper+post -colonly."""
    clean_scene()
    materials = _build_materials(project_root)
    bm = bmesh.new()

    # Intact footings and vertical posts
    _add_footing(bm, -POST_X, 0.0)
    _add_footing(bm, POST_X, 0.0)

    for px in (-POST_X, POST_X):
        p_bot = Vector((px, 0.0, 0.0))
        p_top = Vector((px, 0.0, PANEL_H))
        _add_cylinder_between(bm, p_bot, p_top, POST_R, segments=8)
        _add_post_cap(bm, p_top, Vector((0.0, 0.0, 1.0)))

    # Intact top rail
    _add_cylinder_between(
        bm,
        Vector((-POST_X, 0.0, TOP_RAIL_Z)),
        Vector((POST_X, 0.0, TOP_RAIL_Z)),
        TOP_RAIL_R,
        segments=6,
    )

    # Mid rail pry-bent slightly upward in center (clears z >= 1.12m)
    _add_polyline_tube(
        bm,
        [
            Vector((-POST_X, 0.0, MID_RAIL_Z)),
            Vector((-0.35, -0.05, MID_RAIL_Z + 0.08)),
            Vector((0.35, -0.06, MID_RAIL_Z + 0.10)),
            Vector((POST_X, 0.0, MID_RAIL_Z)),
        ],
        MID_RAIL_R,
        segments=6,
    )

    # Snapped bottom wire stubs tucked tightly against posts (do not block crawlway)
    _add_polyline_tube(
        bm,
        [
            Vector((-POST_X, 0.0, BOT_WIRE_Z)),
            Vector((-0.88, -0.05, BOT_WIRE_Z + 0.03)),
            Vector((-0.84, -0.09, BOT_WIRE_Z + 0.08)),
        ],
        BOT_WIRE_R,
        segments=6,
    )
    _add_polyline_tube(
        bm,
        [
            Vector((POST_X, 0.0, BOT_WIRE_Z)),
            Vector((0.89, 0.04, BOT_WIRE_Z + 0.02)),
            Vector((0.85, 0.08, BOT_WIRE_Z + 0.06)),
        ],
        BOT_WIRE_R,
        segments=6,
    )

    # Torn & upward-curled chain-link mesh
    # Original z spans 0.56..2.05; center lower portion curls UP & OUT (-Y) so clearance >= 0.92m!
    def deform_crawl(x0: float, z0: float, u: float, _v: float) -> Vector:
        # Center mask: 1.0 across crawlway (|x| < 0.72), tapering smoothly near posts
        edge_dist = min(u, 1.0 - u)
        center_mask = min(1.0, max(0.0, (edge_dist - 0.03) / 0.14))
        center_mask = center_mask * center_mask * (3.0 - 2.0 * center_mask)

        # Jagged bottom lift variation so torn edge looks organic
        jagged = 0.045 * math.sin(u * math.pi * 7.0 + 0.4) + 0.025 * math.cos(u * math.pi * 13.0)

        # Curl zone below z0 = 1.25m
        if z0 < 1.25:
            t = (1.25 - z0) / (1.25 - 0.56)  # 0 at z=1.25, 1 at bottom torn edge z=0.56
            # Roll upward & forward (-Y) like peeled-back chain-link curtain
            curl_angle = t * math.radians(135.0) * center_mask
            radius = 0.24
            y_out = -math.sin(curl_angle) * radius * (0.6 + 0.4 * t) - 0.08 * t * center_mask
            # Lift bottom edge cleanly above z = 0.94m in the center
            z_lifted = z0 + (0.42 + jagged) * (t ** 1.2) * center_mask
            # Slight side-skirt peel near posts (z >= 0.65m at edges, >= 0.93m in center)
            z_final = max(0.93 if center_mask > 0.65 else 0.58, z_lifted)
            return Vector((x0, y_out, z_final))

        # Slight forward pull above z=1.25 from the curled weight
        pull_t = max(0.0, 1.0 - (z0 - 1.25) / 0.80)
        y_pull = -0.05 * (pull_t ** 2) * center_mask
        return Vector((x0, y_pull, z0))

    _add_deformed_chain_grid(
        bm,
        nx=16,
        nz=12,
        x_min=-POST_X + POST_R,
        x_max=POST_X - POST_R,
        z_min=0.56,
        z_max=TOP_RAIL_Z,
        deform_fn=deform_crawl,
    )

    # CRITICAL: -colonly covers UPPER half z >= 0.90m + side posts ONLY so player crawls under!
    col_boxes = [
        (
            "FenceCrawl_Col_Upper-colonly",
            Vector((-1.02, -0.22, 0.92)),
            Vector((1.02, 0.10, PANEL_H)),
        ),
        (
            "FenceCrawl_Col_PostL-colonly",
            Vector((-1.05, -0.09, 0.0)),
            Vector((-0.88, 0.09, 0.92)),
        ),
        (
            "FenceCrawl_Col_PostR-colonly",
            Vector((0.88, -0.09, 0.0)),
            Vector((1.05, 0.09, 0.92)),
        ),
    ]
    return _finalize_and_export(
        "fence_crawl_under_2m",
        bm,
        materials,
        col_boxes,
        "Split BoxShape3D (-colonly): upper panel z>=0.92m + left/right posts ONLY (1.76m x 0.92m crawl clearance)",
        output_dir,
    )


# ==============================================================================
# 3. fence_breach_hole_2m.glb
# ==============================================================================
def build_breach_hole(project_root: Path, output_dir: Path) -> dict[str, object]:
    """2.0m W x 2.1m H — jagged ripped center walk-through >= 0.95m x 1.75m; split L/R -colonly."""
    clean_scene()
    materials = _build_materials(project_root)
    bm = bmesh.new()

    # Intact footings and vertical posts
    _add_footing(bm, -POST_X, 0.0)
    _add_footing(bm, POST_X, 0.0)

    for px in (-POST_X, POST_X):
        p_bot = Vector((px, 0.0, 0.0))
        p_top = Vector((px, 0.0, PANEL_H))
        _add_cylinder_between(bm, p_bot, p_top, POST_R, segments=8)
        _add_post_cap(bm, p_top, Vector((0.0, 0.0, 1.0)))

    # Top rail slightly arched upward above the breach
    _add_polyline_tube(
        bm,
        [
            Vector((-POST_X, 0.0, TOP_RAIL_Z)),
            Vector((0.0, -0.02, TOP_RAIL_Z + 0.03)),
            Vector((POST_X, 0.0, TOP_RAIL_Z)),
        ],
        TOP_RAIL_R,
        segments=6,
    )

    # Severed mid-rail stubs bent outward away from walk-through corridor (|x| >= 0.54)
    _add_polyline_tube(
        bm,
        [
            Vector((-POST_X, 0.0, MID_RAIL_Z)),
            Vector((-0.68, -0.02, MID_RAIL_Z)),
            Vector((-0.55, -0.14, MID_RAIL_Z - 0.05)),
        ],
        MID_RAIL_R,
        segments=6,
    )
    _add_polyline_tube(
        bm,
        [
            Vector((POST_X, 0.0, MID_RAIL_Z)),
            Vector((0.68, 0.02, MID_RAIL_Z)),
            Vector((0.55, 0.13, MID_RAIL_Z + 0.04)),
        ],
        MID_RAIL_R,
        segments=6,
    )

    # Severed bottom wire stubs
    _add_polyline_tube(
        bm,
        [
            Vector((-POST_X, 0.0, BOT_WIRE_Z)),
            Vector((-0.62, -0.03, BOT_WIRE_Z)),
            Vector((-0.55, -0.10, BOT_WIRE_Z + 0.04)),
        ],
        BOT_WIRE_R,
        segments=6,
    )
    _add_polyline_tube(
        bm,
        [
            Vector((POST_X, 0.0, BOT_WIRE_Z)),
            Vector((0.62, 0.03, BOT_WIRE_Z)),
            Vector((0.55, 0.10, BOT_WIRE_Z + 0.03)),
        ],
        BOT_WIRE_R,
        segments=6,
    )

    # Jagged breach opening curves: strictly >= 1.04m wide (|x| <= 0.52) up to z = 1.82m!
    def hole_half_width(z: float) -> float:
        base_w = 0.55 + 0.055 * math.sin((z / 1.85) * math.pi)
        jag = 0.04 * math.sin(z * 11.5) + 0.025 * math.cos(z * 19.0)
        return max(0.53, base_w + jag)

    def hole_top_z(x: float) -> float:
        norm = min(1.0, abs(x) / 0.60)
        arch = 1.88 - 0.08 * (norm ** 2)
        jag = 0.032 * math.sin(x * 16.0) + 0.018 * math.cos(x * 27.0)
        return max(1.80, min(TOP_RAIL_Z - 0.06, arch + jag))

    # Curl wire flaps OUTWARD (away from walk-through opening) near the ripped boundary
    def deform_breach(x0: float, z0: float, _u: float, _v: float) -> Vector:
        hw = hole_half_width(z0)
        tz = hole_top_z(x0)
        dist_side = max(0.0, abs(x0) - hw)
        dist_top = max(0.0, z0 - tz)

        y_off = 0.0
        x_off = 0.0
        z_off = 0.0

        # Side flaps peel outward away from walk-through corridor
        if z0 < tz + 0.08 and dist_side < 0.24:
            flap_t = 1.0 - (dist_side / 0.24)
            flap_t = flap_t * flap_t
            side_sign = -1.0 if x0 < 0.0 else 1.0
            y_off += side_sign * 0.22 * flap_t
            x_off += side_sign * 0.05 * flap_t

        # Top torn flap curls forward (-Y) and slightly upward
        if abs(x0) < hw + 0.06 and dist_top < 0.18:
            top_t = 1.0 - (dist_top / 0.18)
            top_t = top_t * top_t
            y_off -= 0.14 * top_t
            z_off += 0.035 * top_t

        return Vector((x0 + x_off, y_off, z0 + z_off))

    x_left_edge = -POST_X + POST_R
    x_right_edge = POST_X - POST_R

    # Left conformal strip: from left post to jagged left breach edge
    _add_parametric_chain_strip(
        bm,
        nx=5,
        nz=16,
        orig_xz_fn=lambda u, v: (
            x_left_edge + ((-hole_half_width(BOT_WIRE_Z + v * (TOP_RAIL_Z - BOT_WIRE_Z))) - x_left_edge) * u,
            BOT_WIRE_Z + v * (TOP_RAIL_Z - BOT_WIRE_Z),
        ),
        deform_fn=deform_breach,
    )
    # Right conformal strip: from jagged right breach edge to right post
    _add_parametric_chain_strip(
        bm,
        nx=5,
        nz=16,
        orig_xz_fn=lambda u, v: (
            hole_half_width(BOT_WIRE_Z + v * (TOP_RAIL_Z - BOT_WIRE_Z))
            + (x_right_edge - hole_half_width(BOT_WIRE_Z + v * (TOP_RAIL_Z - BOT_WIRE_Z))) * u,
            BOT_WIRE_Z + v * (TOP_RAIL_Z - BOT_WIRE_Z),
        ),
        deform_fn=deform_breach,
    )
    # Top arch header strip bridging between left and right strips above the breach
    def top_strip_xz(u: float, v: float) -> tuple[float, float]:
        # Span x between -hw(z) and +hw(z) at top rail height
        hw_top = hole_half_width(TOP_RAIL_Z - 0.12)
        x0 = -hw_top + (2.0 * hw_top) * u
        z_bot = hole_top_z(x0)
        z0 = z_bot + (TOP_RAIL_Z - z_bot) * v
        return x0, z0

    _add_parametric_chain_strip(
        bm,
        nx=10,
        nz=3,
        orig_xz_fn=top_strip_xz,
        deform_fn=deform_breach,
    )

    # CRITICAL: Split LEFT and RIGHT -colonly boxes ONLY so player walks right through!
    col_boxes = [
        (
            "FenceBreach_Col_Left-colonly",
            Vector((-1.02, -0.20, 0.0)),
            Vector((-0.52, 0.14, PANEL_H)),
        ),
        (
            "FenceBreach_Col_Right-colonly",
            Vector((0.52, -0.14, 0.0)),
            Vector((1.02, 0.20, PANEL_H)),
        ),
    ]
    return _finalize_and_export(
        "fence_breach_hole_2m",
        bm,
        materials,
        col_boxes,
        "Split LEFT and RIGHT BoxShape3D (-colonly) ONLY (1.04m wide full walk-through opening)",
        output_dir,
    )


# ==============================================================================
# 4. fence_collapsed_2m.glb
# ==============================================================================
def build_collapsed(project_root: Path, output_dir: Path) -> dict[str, object]:
    """2.0m W x ~0.55m H — snapped post stumps at z=0..0.22m + crushed panel lying at ~72 deg."""
    clean_scene()
    materials = _build_materials(project_root)
    bm = bmesh.new()

    # Cracked/tilted footings at the original fence line (y = 0)
    _add_footing(bm, -POST_X, 0.0, tilt_x_deg=-10.0, tilt_y_deg=-5.0, cracked=True)
    _add_footing(bm, POST_X, 0.0, tilt_x_deg=-16.0, tilt_y_deg=6.0, cracked=True)

    # Snapped rusted post stumps (z = 0..0.22m)
    _add_cylinder_between(
        bm,
        Vector((-POST_X, 0.0, 0.0)),
        Vector((-POST_X + 0.01, -0.03, 0.21)),
        POST_R,
        segments=8,
        r2=POST_R * 0.85,
    )
    _add_cylinder_between(
        bm,
        Vector((POST_X, 0.0, 0.0)),
        Vector((POST_X - 0.02, -0.04, 0.18)),
        POST_R,
        segments=8,
        r2=POST_R * 0.82,
    )

    # Transform for the collapsed panel: tilted ~76 deg forward toward -Y (so peak height ~0.55m)
    # Pivot near the snapped stumps so the fallen posts visually connect to the break.
    tilt_rad = math.radians(76.0)
    cos_t = math.cos(tilt_rad)
    sin_t = math.sin(tilt_rad)

    def map_fallen(x_local: float, z_local: float, crush_z: float = 0.0) -> Vector:
        # Local z_local in [0.0, 1.92] maps along -Y and gently upward in +Z
        y = -0.06 - z_local * sin_t
        # Gentle arch/buckle in the middle of the crushed panel, landing near ground at top
        z = 0.16 + z_local * cos_t * 0.65 + crush_z
        # Subtle twist so right side lies slightly flatter than left
        z -= 0.04 * ((x_local + 1.0) * 0.5) * (z_local / 1.92)
        return Vector((x_local, y, max(0.025, z)))

    # Fallen broken left & right post shafts (segmented with crush bends)
    for px, bend_x in ((-POST_X, -0.04), (POST_X, 0.05)):
        pts = [
            map_fallen(px, 0.0, 0.0),
            map_fallen(px + bend_x * 0.5, 0.95, 0.06),
            map_fallen(px + bend_x, 1.90, -0.08),
        ]
        _add_polyline_tube(bm, pts, POST_R, segments=8)
        _add_post_cap(bm, pts[-1], pts[-1] - pts[-2])

    # Fallen top rail (buckled)
    _add_polyline_tube(
        bm,
        [
            map_fallen(-POST_X - 0.04, 1.88, -0.08),
            map_fallen(-0.20, 1.84, 0.05),
            map_fallen(0.35, 1.82, -0.04),
            map_fallen(POST_X + 0.05, 1.88, -0.08),
        ],
        TOP_RAIL_R,
        segments=6,
    )

    # Fallen mid rail (crushed dome up to ~0.48m)
    _add_polyline_tube(
        bm,
        [
            map_fallen(-POST_X - 0.02, 0.95, 0.06),
            map_fallen(0.0, 0.92, 0.14),
            map_fallen(POST_X + 0.025, 0.95, 0.06),
        ],
        MID_RAIL_R,
        segments=6,
    )

    # Fallen bottom wire
    _add_polyline_tube(
        bm,
        [
            map_fallen(-POST_X, 0.06, 0.0),
            map_fallen(0.0, 0.10, 0.03),
            map_fallen(POST_X, 0.06, 0.0),
        ],
        BOT_WIRE_R,
        segments=6,
    )

    # Crushed wavy chain-link mesh (14 x 10 = 280 tris)
    def deform_collapsed(x0: float, z0: float, u: float, v: float) -> Vector:
        # Interpolate slight x drift matching bent posts
        x_drift = (-0.04 * (1.0 - u) + 0.05 * u) * v
        # Crumpled waves peaking around z ~ 0.52m in the buckled mid-section
        buckle = 0.14 * math.sin(v * math.pi) * math.sin(u * math.pi)
        wave = 0.045 * math.sin(u * math.pi * 3.0 + 0.5) * math.sin(v * math.pi * 2.0)
        return map_fallen(x0 + x_drift, z0, buckle + wave)

    _add_deformed_chain_grid(
        bm,
        nx=14,
        nz=10,
        x_min=-POST_X + POST_R,
        x_max=POST_X - POST_R,
        z_min=0.06,
        z_max=1.88,
        deform_fn=deform_collapsed,
    )

    # Low walk-over -colonly box
    col_boxes = [
        (
            "FenceCollapsed_Col-colonly",
            Vector((-1.05, -1.96, 0.0)),
            Vector((1.05, 0.10, 0.42)),
        )
    ]
    return _finalize_and_export(
        "fence_collapsed_2m",
        bm,
        materials,
        col_boxes,
        "Low walk-over BoxShape3D (-colonly, height 0.42m)",
        output_dir,
    )


# ==============================================================================
# 5. fence_broken_end_1m.glb
# ==============================================================================
def build_broken_end(project_root: Path, output_dir: Path) -> dict[str, object]:
    """1.0m W x 2.1m H — sheared-off ragged half-panel with dangling bent top rail & torn edge."""
    clean_scene()
    materials = _build_materials(project_root)
    bm = bmesh.new()

    left_x = -0.472
    _add_footing(bm, left_x, 0.0)

    # Intact left vertical post
    p_bot = Vector((left_x, 0.0, 0.0))
    p_top = Vector((left_x, 0.0, PANEL_H))
    _add_cylinder_between(bm, p_bot, p_top, POST_R, segments=8)
    _add_post_cap(bm, p_top, Vector((0.0, 0.0, 1.0)))

    # Dangling bent top rail (sheared & bent sharply downward toward +X / -Y)
    _add_polyline_tube(
        bm,
        [
            Vector((left_x, 0.0, TOP_RAIL_Z)),
            Vector((0.08, -0.01, TOP_RAIL_Z - 0.02)),
            Vector((0.26, -0.06, TOP_RAIL_Z - 0.18)),
            Vector((0.46, -0.14, TOP_RAIL_Z - 0.46)),
        ],
        TOP_RAIL_R,
        segments=6,
    )

    # Sheared mid-rail stub bent outward
    _add_polyline_tube(
        bm,
        [
            Vector((left_x, 0.0, MID_RAIL_Z)),
            Vector((0.10, 0.0, MID_RAIL_Z)),
            Vector((0.30, 0.09, MID_RAIL_Z - 0.07)),
        ],
        MID_RAIL_R,
        segments=6,
    )

    # Snapped bottom tension wire curling slightly up
    _add_polyline_tube(
        bm,
        [
            Vector((left_x, 0.0, BOT_WIRE_Z)),
            Vector((0.18, -0.02, BOT_WIRE_Z)),
            Vector((0.34, -0.07, BOT_WIRE_Z + 0.06)),
        ],
        BOT_WIRE_R,
        segments=6,
    )

    # Jagged torn right-edge boundary x_max(z)
    def torn_right_x(z: float) -> float:
        base = 0.36 - 0.05 * ((z / PANEL_H) ** 2)
        jag = 0.085 * math.sin(z * 8.5 + 0.6) + 0.045 * math.cos(z * 17.0)
        return min(0.48, max(0.18, base + jag))

    def deform_end(x0: float, z0: float, u: float, v: float) -> Vector:
        rx = torn_right_x(z0)
        dist_edge = max(0.0, rx - x0)
        y_off = 0.0
        z_off = 0.0

        # Follow dangling top rail droop in upper-right corner
        if u > 0.50 and v > 0.72:
            droop_u = (u - 0.50) / 0.50
            droop_v = (v - 0.72) / 0.28
            z_off -= 0.34 * (droop_u ** 1.4) * (droop_v ** 1.5)
            y_off -= 0.11 * droop_u * droop_v

        # Curl & flare along torn right edge
        if dist_edge < 0.20:
            edge_t = 1.0 - (dist_edge / 0.20)
            edge_t = edge_t * edge_t
            y_off += 0.15 * edge_t * math.sin(z0 * 4.5 + 0.5)

        return Vector((x0, y_off, max(0.04, z0 + z_off)))

    x_start = left_x + POST_R
    _add_parametric_chain_strip(
        bm,
        nx=8,
        nz=16,
        orig_xz_fn=lambda u, v: (
            x_start + (torn_right_x(BOT_WIRE_Z + v * (TOP_RAIL_Z - BOT_WIRE_Z)) - x_start) * u,
            BOT_WIRE_Z + v * (TOP_RAIL_Z - BOT_WIRE_Z),
        ),
        deform_fn=deform_end,
        uv_origin=(left_x, BOT_WIRE_Z),
    )

    col_boxes = [
        (
            "FenceBrokenEnd_Col-colonly",
            Vector((-0.52, -0.16, 0.0)),
            Vector((0.46, 0.14, PANEL_H)),
        )
    ]
    return _finalize_and_export(
        "fence_broken_end_1m",
        bm,
        materials,
        col_boxes,
        "Solid BoxShape3D (-colonly) covering 1.0m sheared half-panel",
        output_dir,
    )


def build_all(project_root: Path, output_dir: Path) -> dict[str, object]:
    """Generate all 5 damaged fence kit GLBs and write manifest_damaged.json."""
    output_dir.mkdir(parents=True, exist_ok=True)
    builders = [
        build_bent_impact,
        build_crawl_under,
        build_breach_hole,
        build_collapsed,
        build_broken_end,
    ]
    entries = [fn(project_root, output_dir) for fn in builders]
    manifest = {
        "kit": "chain_link_fence_kit_damaged",
        "source": "procedural_bpy",
        "materials": [
            "res://assets/materials/fence_door_metal/fence_door_metal.tres",
            "res://assets/materials/chain_link_fence/chain_link_fence.tres",
            "res://assets/materials/weathered_concrete/weathered_concrete.tres",
            "res://assets/materials/barbed_wire/barbed_wire.tres",
        ],
        "assets": entries,
    }
    manifest_path = output_dir / "manifest_damaged.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[fence_kit_damaged] Wrote manifest: {manifest_path}")
    return manifest


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate HL2 damaged chain-link fence kit GLBs")
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
