# Blender Python (bpy) — Modular Industrial Grate Catwalk Generator (Godot 4 .glb)
# Run headless: blender -b -P generate_catwalk.py

import math
import os
import bpy
import bmesh
from mathutils import Vector, Matrix

# ==============================================================================
# CONFIGURATION
# ==============================================================================
BAY_LENGTH: float = 2.0          # X: -1.0m to +1.0m
BAY_DEPTH: float = 1.2           # Y:  0.0m (wall) to -1.2m (front edge)
FRAME_HEIGHT: float = 0.10       # Z:  0.0m (top) to -0.10m (bottom)
FRAME_FLANGE: float = 0.06       # C-channel flange width
FRAME_THICK: float = 0.008       # Steel wall thickness
DECK_RECESS_Z: float = -0.015    # Grate surface Z offset

USE_3D_GRID: bool = False        # False = 2-tri UV quad; True = 3D lattice bars
GRID_PITCH: float = 0.05         # 40 x 24 cells per 2.0m x 1.2m bay
GRID_BAR_W: float = 0.005
GRID_BAR_H: float = 0.015

BAKE_TEXTURES: bool = True       # Bake 1024x1024 PBR PNGs via Cycles before glTF export
TEX_RES: int = 1024
EXPORT_DIR: str = os.path.abspath("./assets/models/props/catwalk")
GLB_FILENAME: str = "catwalk_modular.glb"


# ==============================================================================
# SCENE & BMesh HELPERS
# ==============================================================================
def clear_scene() -> None:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block_col in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for block in list(block_col):
            if block.users == 0:
                block_col.remove(block)


def create_mesh_obj(
    name: str,
    bm: bmesh.types.BMesh,
    parent: bpy.types.Object,
    materials: list[bpy.types.Material],
    auto_smooth_deg: float = 35.0,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Version-agnostic hard-edge split at threshold angle (Blender 3.6 / 4.x+)
    thresh_rad = math.radians(auto_smooth_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) <= thresh_rad
        else:
            e.smooth = False

    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    for mat in materials:
        obj.data.materials.append(mat)
    return obj


def add_box(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    coords = [
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
    ]
    verts = [bm.verts.new(c) for c in coords]
    quads = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (2, 3, 7, 6),
        (0, 4, 7, 3), (1, 2, 6, 5),
    ]
    faces = []
    for q in quads:
        f = bm.faces.new([verts[i] for i in q])
        f.material_index = mat_idx
        faces.append(f)
    return faces


def add_c_channel_x(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    y_outer: float,
    z_top: float,
    height: float,
    flange: float,
    thick: float,
    dir_y: float,
    mat_idx: int = 0,
) -> None:
    y_web_in = y_outer + dir_y * thick
    y_flg_in = y_outer + dir_y * flange
    # Vertical web
    add_box(
        bm,
        (x0, min(y_outer, y_web_in), z_top - height),
        (x1, max(y_outer, y_web_in), z_top),
        mat_idx,
    )
    # Top flange
    add_box(
        bm,
        (x0, min(y_web_in, y_flg_in), z_top - thick),
        (x1, max(y_web_in, y_flg_in), z_top),
        mat_idx,
    )
    # Bottom flange
    add_box(
        bm,
        (x0, min(y_web_in, y_flg_in), z_top - height),
        (x1, max(y_web_in, y_flg_in), z_top - height + thick),
        mat_idx,
    )


def add_c_channel_y(
    bm: bmesh.types.BMesh,
    y0: float,
    y1: float,
    x_outer: float,
    z_top: float,
    height: float,
    flange: float,
    thick: float,
    dir_x: float,
    mat_idx: int = 0,
) -> None:
    x_web_in = x_outer + dir_x * thick
    x_flg_in = x_outer + dir_x * flange
    add_box(
        bm,
        (min(x_outer, x_web_in), y0, z_top - height),
        (max(x_outer, x_web_in), y1, z_top),
        mat_idx,
    )
    add_box(
        bm,
        (min(x_web_in, x_flg_in), y0, z_top - thick),
        (max(x_web_in, x_flg_in), y1, z_top),
        mat_idx,
    )
    add_box(
        bm,
        (min(x_web_in, x_flg_in), y0, z_top - height),
        (max(x_web_in, x_flg_in), y1, z_top - height + thick),
        mat_idx,
    )


def add_flat_strap_xy(
    bm: bmesh.types.BMesh,
    p0: tuple[float, float],
    p1: tuple[float, float],
    width: float,
    thick: float,
    z_center: float,
    mat_idx: int = 0,
) -> None:
    v0 = Vector((p0[0], p0[1], 0.0))
    v1 = Vector((p1[0], p1[1], 0.0))
    tangent = (v1 - v0).normalized()
    normal = Vector((-tangent.y, tangent.x, 0.0)) * (width * 0.5)
    z0 = z_center - thick * 0.5
    z1 = z_center + thick * 0.5

    c_bot = [v0 - normal, v1 - normal, v1 + normal, v0 + normal]
    verts = (
        [bm.verts.new((c.x, c.y, z0)) for c in c_bot]
        + [bm.verts.new((c.x, c.y, z1)) for c in c_bot]
    )
    quads = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (2, 3, 7, 6),
        (0, 4, 7, 3), (1, 2, 6, 5),
    ]
    for q in quads:
        f = bm.faces.new([verts[i] for i in q])
        f.material_index = mat_idx


def add_diagonal_strut_yz(
    bm: bmesh.types.BMesh,
    x_center: float,
    width_x: float,
    yz0: tuple[float, float],
    yz1: tuple[float, float],
    thickness_yz: float,
    mat_idx: int = 0,
) -> None:
    p0 = Vector((0.0, yz0[0], yz0[1]))
    p1 = Vector((0.0, yz1[0], yz1[1]))
    tangent = (p1 - p0).normalized()
    perp = Vector((0.0, -tangent.z, tangent.y)) * (thickness_yz * 0.5)
    x0 = x_center - width_x * 0.5
    x1 = x_center + width_x * 0.5

    ring = [p0 - perp, p1 - perp, p1 + perp, p0 + perp]
    verts = (
        [bm.verts.new((x0, p.y, p.z)) for p in ring]
        + [bm.verts.new((x1, p.y, p.z)) for p in ring]
    )
    quads = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (2, 3, 7, 6),
        (0, 4, 7, 3), (1, 2, 6, 5),
    ]
    for q in quads:
        f = bm.faces.new([verts[i] for i in q])
        f.material_index = mat_idx


def add_pipe_segment(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    radius: float,
    segments: int,
    cap_ends: bool = True,
    mat_idx: int = 0,
) -> None:
    vec = p1 - p0
    length = vec.length
    mid = (p0 + p1) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    xf = Matrix.Translation(mid) @ rot

    res = bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=length,
        matrix=xf,
    )
    new_verts = set(res["verts"])
    for f in bm.faces:
        if all(v in new_verts for v in f.verts):
            f.material_index = mat_idx


# ==============================================================================
# UV PROJECTION (WORLD-SCALE BOX & NORMALIZED 0..1)
# ==============================================================================
def apply_world_box_uv(obj: bpy.types.Object, scale: float = 1.0) -> None:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.verify()

    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co * scale
            if az >= ax and az >= ay:
                loop[uv_layer].uv = (co.x, co.y)
            elif ay >= ax and ay >= az:
                loop[uv_layer].uv = (co.x, co.z)
            else:
                loop[uv_layer].uv = (co.y, co.z)

    bm.to_mesh(mesh)
    bm.free()


def apply_normalized_deck_uv(
    obj: bpy.types.Object,
    x_min: float,
    x_max: float,
    y_min: float,
    y_max: float,
) -> None:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.verify()
    dx = max(x_max - x_min, 1e-5)
    dy = max(y_max - y_min, 1e-5)

    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            u = (co.x - x_min) / dx
            v = (co.y - y_min) / dy
            loop[uv_layer].uv = (u, v)

    bm.to_mesh(mesh)
    bm.free()


# ==============================================================================
# PROCEDURAL PBR MATERIALS
# ==============================================================================
def build_steel_material(
    name: str,
    base_col_a: tuple[float, float, float, float],
    base_col_b: tuple[float, float, float, float],
    rust_col: tuple[float, float, float, float],
    metallic: float,
    rough_min: float,
    rough_max: float,
    bump_dist: float,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = metallic
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_coord = nodes.new("ShaderNodeTexCoord")

    # Fine surface grain noise
    noise_fine = nodes.new("ShaderNodeTexNoise")
    noise_fine.inputs["Scale"].default_value = 18.0
    noise_fine.inputs["Detail"].default_value = 10.0
    noise_fine.inputs["Roughness"].default_value = 0.65
    links.new(tex_coord.outputs["UV"], noise_fine.inputs["Vector"])

    # Macro rust blotch mask
    noise_rust = nodes.new("ShaderNodeTexNoise")
    noise_rust.inputs["Scale"].default_value = 4.2
    noise_rust.inputs["Detail"].default_value = 8.0
    noise_rust.inputs["Roughness"].default_value = 0.72
    links.new(tex_coord.outputs["UV"], noise_rust.inputs["Vector"])

    ramp_rust = nodes.new("ShaderNodeValToRGB")
    ramp_rust.color_ramp.elements[0].position = 0.54
    ramp_rust.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    ramp_rust.color_ramp.elements[1].position = 0.68
    ramp_rust.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(noise_rust.outputs["Fac"], ramp_rust.inputs["Fac"])

    ramp_base = nodes.new("ShaderNodeValToRGB")
    ramp_base.color_ramp.elements[0].position = 0.25
    ramp_base.color_ramp.elements[0].color = base_col_a
    ramp_base.color_ramp.elements[1].position = 0.75
    ramp_base.color_ramp.elements[1].color = base_col_b
    links.new(noise_fine.outputs["Fac"], ramp_base.inputs["Fac"])

    # Blend base metal with rust patches
    mix_col = nodes.new("ShaderNodeMixRGB")
    mix_col.inputs["Color2"].default_value = rust_col
    links.new(ramp_rust.outputs["Color"], mix_col.inputs["Fac"])
    links.new(ramp_base.outputs["Color"], mix_col.inputs["Color1"])
    links.new(mix_col.outputs["Color"], bsdf.inputs["Base Color"])

    # Roughness ramp
    ramp_rough = nodes.new("ShaderNodeValToRGB")
    ramp_rough.color_ramp.elements[0].position = 0.2
    ramp_rough.color_ramp.elements[0].color = (rough_min, rough_min, rough_min, 1.0)
    ramp_rough.color_ramp.elements[1].position = 0.85
    ramp_rough.color_ramp.elements[1].color = (rough_max, rough_max, rough_max, 1.0)
    links.new(noise_fine.outputs["Fac"], ramp_rough.inputs["Fac"])
    links.new(ramp_rough.outputs["Color"], bsdf.inputs["Roughness"])

    # Bump normal
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = bump_dist
    links.new(noise_fine.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def build_grate_deck_material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    if hasattr(mat, "blend_method"):
        mat.blend_method = 'CLIP'
    if hasattr(mat, "alpha_threshold"):
        mat.alpha_threshold = 0.5

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.82
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_coord = nodes.new("ShaderNodeTexCoord")

    # 40 x 24 square lattice UV scaling over normalized 0..1 deck quad
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (38.0, 22.0, 1.0)
    links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])

    brick = nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.11
    brick.inputs["Mortar Smooth"].default_value = 0.02
    brick.inputs["Row Height"].default_value = 1.0
    brick.inputs["Brick Width"].default_value = 1.0
    # Mortar = 1.0 (solid steel bar), Brick = 0.0 (open hole cutout)
    brick.inputs["Mortar"].default_value = (1.0, 1.0, 1.0, 1.0)
    brick.inputs["Color1"].default_value = (0.0, 0.0, 0.0, 1.0)
    brick.inputs["Color2"].default_value = (0.0, 0.0, 0.0, 1.0)
    links.new(mapping.outputs["Vector"], brick.inputs["Vector"])
    links.new(brick.outputs["Fac"], bsdf.inputs["Alpha"])

    # Rusted steel surface coloring on grate bars
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 12.0
    noise.inputs["Detail"].default_value = 8.0
    links.new(tex_coord.outputs["UV"], noise.inputs["Vector"])

    ramp_col = nodes.new("ShaderNodeValToRGB")
    ramp_col.color_ramp.elements[0].position = 0.35
    ramp_col.color_ramp.elements[0].color = (0.16, 0.18, 0.17, 1.0)
    ramp_col.color_ramp.elements[1].position = 0.72
    ramp_col.color_ramp.elements[1].color = (0.32, 0.21, 0.13, 1.0)
    links.new(noise.outputs["Fac"], ramp_col.inputs["Fac"])
    links.new(ramp_col.outputs["Color"], bsdf.inputs["Base Color"])

    ramp_rough = nodes.new("ShaderNodeValToRGB")
    ramp_rough.color_ramp.elements[0].position = 0.2
    ramp_rough.color_ramp.elements[0].color = (0.55, 0.55, 0.55, 1.0)
    ramp_rough.color_ramp.elements[1].position = 0.8
    ramp_rough.color_ramp.elements[1].color = (0.88, 0.88, 0.88, 1.0)
    links.new(noise.outputs["Fac"], ramp_rough.inputs["Fac"])
    links.new(ramp_rough.outputs["Color"], bsdf.inputs["Roughness"])

    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    bump.inputs["Distance"].default_value = 0.008
    links.new(brick.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


# ==============================================================================
# MODULAR GEOMETRY BUILDERS
# ==============================================================================
def build_frame_bay(
    parent: bpy.types.Object,
    mat_steel: bpy.types.Material,
) -> bpy.types.Object:
    bm = bmesh.new()
    half_x = BAY_LENGTH * 0.5
    end_flange = FRAME_FLANGE

    # 1. Outer longitudinal C-channels (Back at Y=0.0, Front at Y=-1.20)
    add_c_channel_x(
        bm, -half_x, half_x, 0.0, 0.0,
        FRAME_HEIGHT, FRAME_FLANGE, FRAME_THICK, dir_y=-1.0,
    )
    add_c_channel_x(
        bm, -half_x, half_x, -BAY_DEPTH, 0.0,
        FRAME_HEIGHT, FRAME_FLANGE, FRAME_THICK, dir_y=1.0,
    )

    # 2. Asymmetric half-width (0.06m) transverse end C-channels at X = ±1.0m
    y_inner_front = -BAY_DEPTH + FRAME_FLANGE
    y_inner_back = -FRAME_FLANGE
    add_c_channel_y(
        bm, y_inner_front, y_inner_back, -half_x, 0.0,
        FRAME_HEIGHT, end_flange, FRAME_THICK, dir_x=1.0,
    )
    add_c_channel_y(
        bm, y_inner_front, y_inner_back, half_x, 0.0,
        FRAME_HEIGHT, end_flange, FRAME_THICK, dir_x=-1.0,
    )

    # 3. Diagonal flat-bar X-bracing (0.05m x 0.008m at Z = -0.04m)
    x_brace = half_x - end_flange
    add_flat_strap_xy(
        bm, (-x_brace, y_inner_back), (x_brace, y_inner_front),
        width=0.05, thick=0.008, z_center=-0.038,
    )
    add_flat_strap_xy(
        bm, (-x_brace, y_inner_front), (x_brace, y_inner_back),
        width=0.05, thick=0.008, z_center=-0.046,
    )

    # 4. 1-segment 0.003m bevel on sharp structural edges
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    sharp_edges = [
        e for e in bm.edges
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(35.0)
    ]
    if sharp_edges:
        bmesh.ops.bevel(
            bm,
            geom=sharp_edges,
            offset=0.003,
            offset_type='OFFSET',
            segments=1,
            profile=0.5,
            affect='EDGES',
        )

    obj = create_mesh_obj("Frame_Bay", bm, parent, [mat_steel], auto_smooth_deg=35.0)
    apply_world_box_uv(obj, scale=1.0)
    return obj


def build_grate_deck(
    parent: bpy.types.Object,
    mat_grate: bpy.types.Material,
    mat_steel: bpy.types.Material,
) -> bpy.types.Object:
    bm = bmesh.new()
    x0 = -BAY_LENGTH * 0.5 + FRAME_FLANGE
    x1 = BAY_LENGTH * 0.5 - FRAME_FLANGE
    y0 = -BAY_DEPTH + FRAME_FLANGE
    y1 = -FRAME_FLANGE

    if not USE_3D_GRID:
        verts = [
            bm.verts.new((x0, y0, DECK_RECESS_Z)),
            bm.verts.new((x1, y0, DECK_RECESS_Z)),
            bm.verts.new((x1, y1, DECK_RECESS_Z)),
            bm.verts.new((x0, y1, DECK_RECESS_Z)),
        ]
        f = bm.faces.new(verts)
        f.material_index = 0
        obj = create_mesh_obj("Grate_Deck", bm, parent, [mat_grate], auto_smooth_deg=35.0)
        apply_normalized_deck_uv(obj, x0, x1, y0, y1)
        return obj

    # Optional 3D physical grid lattice (0.05m pitch, 0.005m width, 0.015m depth)
    z_bot = DECK_RECESS_Z - GRID_BAR_H
    z_top = DECK_RECESS_Z
    hw = GRID_BAR_W * 0.5

    nx = int(round((x1 - x0) / GRID_PITCH))
    for i in range(nx + 1):
        xc = x0 + i * ((x1 - x0) / nx)
        add_box(bm, (xc - hw, y0, z_bot), (xc + hw, y1, z_top), mat_idx=0)

    ny = int(round((y1 - y0) / GRID_PITCH))
    for j in range(ny + 1):
        yc = y0 + j * ((y1 - y0) / ny)
        add_box(bm, (x0, yc - hw, z_bot), (x1, yc + hw, z_top), mat_idx=0)

    obj = create_mesh_obj("Grate_Deck", bm, parent, [mat_steel], auto_smooth_deg=35.0)
    apply_world_box_uv(obj, scale=1.0)
    return obj


def add_wall_bracket_geometry(
    bm: bmesh.types.BMesh,
    x_center: float,
    mat_idx: int = 0,
) -> None:
    w = 0.06
    hw = w * 0.5
    t = 0.012
    # Vertical wall mounting plate (0.75m drop: Z = -0.10m to -0.85m)
    add_box(
        bm,
        (x_center - hw, -t, -0.85),
        (x_center + hw, 0.0, -0.10),
        mat_idx,
    )
    # Horizontal top cantilever support arm (1.15m reach: Y = 0.0m to -1.15m)
    add_box(
        bm,
        (x_center - hw, -1.15, -0.14),
        (x_center + hw, -t, -0.10),
        mat_idx,
    )
    # 45-degree diagonal strut (0.06m wide x 0.05m deep)
    add_diagonal_strut_yz(
        bm,
        x_center=x_center,
        width_x=w,
        yz0=(-0.03, -0.81),
        yz1=(-1.08, -0.13),
        thickness_yz=0.05,
        mat_idx=mat_idx,
    )


def add_handrail_post_geometry(
    bm: bmesh.types.BMesh,
    x_pos: float,
    y_rail: float,
    mat_idx: int = 0,
) -> None:
    add_pipe_segment(
        bm,
        Vector((x_pos, y_rail, -0.09)),
        Vector((x_pos, y_rail, 1.05)),
        radius=0.014,
        segments=8,
        cap_ends=True,
        mat_idx=mat_idx,
    )
    # Base mounting cleat tying post to front C-channel face (Y = -1.20m)
    add_box(
        bm,
        (x_pos - 0.02, y_rail, -0.085),
        (x_pos + 0.02, -BAY_DEPTH, -0.015),
        mat_idx=mat_idx,
    )


def build_railing_front(
    parent: bpy.types.Object,
    mat_railing: bpy.types.Material,
) -> bpy.types.Object:
    bm = bmesh.new()
    half_x = BAY_LENGTH * 0.5
    y_rail = -BAY_DEPTH - 0.016

    # Top rail (Z = +1.05m, R = 0.022m, 12 segs)
    add_pipe_segment(
        bm,
        Vector((-half_x, y_rail, 1.05)),
        Vector((half_x, y_rail, 1.05)),
        radius=0.022,
        segments=12,
        cap_ends=False,
        mat_idx=0,
    )
    # Mid rail (Z = +0.55m, R = 0.012m, 8 segs)
    add_pipe_segment(
        bm,
        Vector((-half_x, y_rail, 0.55)),
        Vector((half_x, y_rail, 0.55)),
        radius=0.012,
        segments=8,
        cap_ends=False,
        mat_idx=0,
    )
    # Asymmetric vertical posts at X = -1.0m and X = 0.0m only
    for x_post in (-half_x, 0.0):
        add_handrail_post_geometry(bm, x_post, y_rail, mat_idx=0)

    obj = create_mesh_obj("Railing_Front", bm, parent, [mat_railing], auto_smooth_deg=45.0)
    apply_world_box_uv(obj, scale=1.0)
    return obj


def build_bracket_wall(
    parent: bpy.types.Object,
    mat_steel: bpy.types.Material,
) -> bpy.types.Object:
    bm = bmesh.new()
    add_wall_bracket_geometry(bm, x_center=-BAY_LENGTH * 0.5, mat_idx=0)
    obj = create_mesh_obj("Bracket_Wall", bm, parent, [mat_steel], auto_smooth_deg=35.0)
    apply_world_box_uv(obj, scale=1.0)
    return obj


def build_cap_right_end(
    parent: bpy.types.Object,
    mat_steel: bpy.types.Material,
    mat_railing: bpy.types.Material,
) -> bpy.types.Object:
    bm = bmesh.new()
    x_end = BAY_LENGTH * 0.5
    y_rail = -BAY_DEPTH - 0.016

    add_wall_bracket_geometry(bm, x_center=x_end, mat_idx=0)
    add_handrail_post_geometry(bm, x_pos=x_end, y_rail=y_rail, mat_idx=1)

    obj = create_mesh_obj(
        "Cap_Right_End", bm, parent, [mat_steel, mat_railing], auto_smooth_deg=40.0
    )
    apply_world_box_uv(obj, scale=1.0)
    return obj


def build_collision_boxes(parent: bpy.types.Object) -> None:
    half_x = BAY_LENGTH * 0.5

    # Deck-colonly: 2.0m x 1.2m x 0.10m, top at Z = 0.0m
    bm_deck = bmesh.new()
    add_box(bm_deck, (-half_x, -BAY_DEPTH, -FRAME_HEIGHT), (half_x, 0.0, 0.0))
    col_deck = create_mesh_obj("Deck-colonly", bm_deck, parent, [])
    col_deck.display_type = 'WIRE'
    col_deck.hide_render = True

    # Railing-colonly: 2.0m x 0.05m x 1.07m at Y = -1.20m
    bm_rail = bmesh.new()
    add_box(
        bm_rail,
        (-half_x, -BAY_DEPTH - 0.025, 0.0),
        (half_x, -BAY_DEPTH + 0.025, 1.07),
    )
    col_rail = create_mesh_obj("Railing-colonly", bm_rail, parent, [])
    col_rail.display_type = 'WIRE'
    col_rail.hide_render = True


# ==============================================================================
# CYCLES PBR TEXTURE BAKING PIPELINE (1024x1024 PNG)
# ==============================================================================
def bake_material_to_pbr(
    mat: bpy.types.Material,
    tex_dir: str,
    has_alpha_cutout: bool = False,
) -> None:
    os.makedirs(tex_dir, exist_ok=True)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    out_node = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')

    # Spawn temporary 1x1 normalized UV dummy quad for overlap-free baking
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, 0.0, 10.0))
    dummy = bpy.context.active_object
    dummy.data.materials.append(mat)

    def _bake_socket_to_image(
        img_name: str,
        socket_out: bpy.types.NodeSocket | None,
        bake_type: str,
        is_data: bool,
    ) -> bpy.types.Image:
        img = bpy.data.images.new(img_name, width=TEX_RES, height=TEX_RES, alpha=True)
        img.colorspace_settings.name = 'Non-Color' if is_data else 'sRGB'

        tex_node = nodes.new("ShaderNodeTexImage")
        tex_node.image = img
        for n in nodes:
            n.select = False
        tex_node.select = True
        nodes.active = tex_node

        emit_node = None
        orig_surface = out_node.inputs["Surface"].links[0].from_socket

        if bake_type == 'EMIT' and socket_out is not None:
            emit_node = nodes.new("ShaderNodeEmission")
            links.new(socket_out, emit_node.inputs["Color"])
            links.new(emit_node.outputs["Emission"], out_node.inputs["Surface"])

        bpy.ops.object.select_all(action='DESELECT')
        dummy.select_set(True)
        bpy.context.view_layer.objects.active = dummy
        bpy.ops.object.bake(type=bake_type)

        if emit_node is not None:
            links.new(orig_surface, out_node.inputs["Surface"])
            nodes.remove(emit_node)
        nodes.remove(tex_node)

        filepath = os.path.join(tex_dir, f"{img_name}.png")
        img.filepath_raw = filepath
        img.file_format = 'PNG'
        img.save()
        return img

    col_sock = bsdf.inputs["Base Color"].links[0].from_socket
    rough_sock = bsdf.inputs["Roughness"].links[0].from_socket
    alpha_sock = (
        bsdf.inputs["Alpha"].links[0].from_socket
        if has_alpha_cutout and bsdf.inputs["Alpha"].is_linked
        else None
    )

    img_albedo = _bake_socket_to_image(f"{mat.name}_BaseColor", col_sock, 'EMIT', False)
    img_rough = _bake_socket_to_image(f"{mat.name}_Roughness", rough_sock, 'EMIT', True)
    img_norm = _bake_socket_to_image(f"{mat.name}_Normal", None, 'NORMAL', True)

    if alpha_sock is not None:
        img_alpha = _bake_socket_to_image(f"{mat.name}_Alpha", alpha_sock, 'EMIT', True)
        px_col = list(img_albedo.pixels)
        px_alp = list(img_alpha.pixels)
        # Fast channel copy: Alpha is emitted to RGB grayscale, transfer R to A channel
        px_col[3::4] = px_alp[0::4]
        img_albedo.pixels[:] = px_col
        img_albedo.save()
        bpy.data.images.remove(img_alpha)

    bpy.data.objects.remove(dummy, do_unlink=True)

    # Rewire material to glTF-compliant Image Texture -> Principled BSDF graph
    nodes.clear()
    out_new = nodes.new("ShaderNodeOutputMaterial")
    bsdf_new = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_new.inputs["Metallic"].default_value = 0.85
    links.new(bsdf_new.outputs["BSDF"], out_new.inputs["Surface"])

    n_col = nodes.new("ShaderNodeTexImage")
    n_col.image = img_albedo
    links.new(n_col.outputs["Color"], bsdf_new.inputs["Base Color"])
    if has_alpha_cutout:
        # Standard glTF 2.0 Alpha Mask export (Math:ROUND detects alphaMode='MASK' cutoff=0.5)
        math_round = nodes.new("ShaderNodeMath")
        math_round.operation = 'ROUND'
        links.new(n_col.outputs["Alpha"], math_round.inputs[0])
        links.new(math_round.outputs["Value"], bsdf_new.inputs["Alpha"])

    n_rough = nodes.new("ShaderNodeTexImage")
    n_rough.image = img_rough
    links.new(n_rough.outputs["Color"], bsdf_new.inputs["Roughness"])

    n_norm = nodes.new("ShaderNodeTexImage")
    n_norm.image = img_norm
    norm_map = nodes.new("ShaderNodeNormalMap")
    links.new(n_norm.outputs["Color"], norm_map.inputs["Color"])
    links.new(norm_map.outputs["Normal"], bsdf_new.inputs["Normal"])


# ==============================================================================
# MAIN PIPELINE
# ==============================================================================
def main() -> None:
    clear_scene()
    os.makedirs(EXPORT_DIR, exist_ok=True)

    # Root anchor at [0, 0, 0] (top-back-center wall mount line)
    root = bpy.data.objects.new("Catwalk_Modular_Root", None)
    root.empty_display_type = 'PLAIN_AXES'
    root.empty_display_size = 0.25
    bpy.context.collection.objects.link(root)

    # Materials
    mat_steel = build_steel_material(
        name="M_Steel_Frame",
        base_col_a=(0.14, 0.17, 0.15, 1.0),
        base_col_b=(0.22, 0.26, 0.23, 1.0),
        rust_col=(0.30, 0.18, 0.10, 1.0),
        metallic=0.85,
        rough_min=0.58,
        rough_max=0.90,
        bump_dist=0.005,
    )
    mat_railing = build_steel_material(
        name="M_Railing_Steel",
        base_col_a=(0.38, 0.42, 0.40, 1.0),
        base_col_b=(0.55, 0.59, 0.56, 1.0),
        rust_col=(0.34, 0.22, 0.13, 1.0),
        metallic=0.80,
        rough_min=0.45,
        rough_max=0.82,
        bump_dist=0.003,
    )
    mat_grate = build_grate_deck_material("M_Grate_Deck")

    # Assemble hierarchy
    build_frame_bay(root, mat_steel)
    build_grate_deck(root, mat_grate, mat_steel)
    build_railing_front(root, mat_railing)
    build_bracket_wall(root, mat_steel)
    build_cap_right_end(root, mat_steel, mat_railing)
    build_collision_boxes(root)

    # Cycles PBR baking
    if BAKE_TEXTURES:
        scene = bpy.context.scene
        scene.render.engine = 'CYCLES'
        scene.cycles.samples = 16
        scene.cycles.use_denoising = False
        tex_dir = os.path.join(EXPORT_DIR, "textures")
        bake_material_to_pbr(mat_steel, tex_dir, has_alpha_cutout=False)
        bake_material_to_pbr(mat_railing, tex_dir, has_alpha_cutout=False)
        if not USE_3D_GRID:
            bake_material_to_pbr(mat_grate, tex_dir, has_alpha_cutout=True)

    # Export glTF 2.0 (.glb) for Godot 4
    glb_path = os.path.join(EXPORT_DIR, GLB_FILENAME)
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials='EXPORT',
    )
    print(f"[OK] Exported modular catwalk kit -> {glb_path}")


if __name__ == "__main__":
    main()
