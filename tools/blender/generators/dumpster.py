#!/usr/bin/env python3
"""Procedural generator for industrial dumpster prop with baked convex edge wear.

Generates Dumpster_Body and hinged Dumpster_Lid with Godot 4 compound convex colliders
(-convcolonly) and exports to assets/models/props/dumpster/dumpster.glb.
Compatible with Blender 3.6+, 4.x, and 5.x.
"""

from __future__ import annotations

import math
import os
from pathlib import Path
import bmesh
import bpy
from mathutils import Vector

SCRIPT_DIR: Path = Path(__file__).resolve().parent
PROJECT_ROOT: Path = SCRIPT_DIR.parents[2]
OUTPUT_DIR: Path = PROJECT_ROOT / "assets" / "models" / "props" / "dumpster"
OUTPUT_PATH: Path = OUTPUT_DIR / "dumpster.glb"


SCALE: float = 1.3


def get_or_create_material(
    name: str, base_color: tuple[float, float, float, float], metallic: float, roughness: float
) -> bpy.types.Material:
    """Retrieve existing material or configure a new Principled BSDF material."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_box(
    bm: bmesh.types.BMesh,
    x_min: float,
    x_max: float,
    y_min: float,
    y_max: float,
    z_min: float,
    z_max: float,
) -> list[bmesh.types.BMVert]:
    """Add an axis-aligned box to the given bmesh and return vertex references."""
    verts = [
        bm.verts.new((x_min, y_min, z_min)),
        bm.verts.new((x_max, y_min, z_min)),
        bm.verts.new((x_max, y_max, z_min)),
        bm.verts.new((x_min, y_max, z_min)),
        bm.verts.new((x_min, y_min, z_max)),
        bm.verts.new((x_max, y_min, z_max)),
        bm.verts.new((x_max, y_max, z_max)),
        bm.verts.new((x_min, y_max, z_max)),
    ]
    faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    for f in faces:
        bm.faces.new((verts[f[0]], verts[f[1]], verts[f[2]], verts[f[3]]))
    return verts


def add_sloped_hexahedron(
    bm: bmesh.types.BMesh,
    x_bot_min: float,
    x_bot_max: float,
    x_top_min: float,
    x_top_max: float,
    y_bot_min: float,
    y_bot_max: float,
    y_top_min: float,
    y_top_max: float,
    z_min: float,
    z_max: float,
) -> None:
    """Add a tapered hexahedron box with independent bottom and top bounds."""
    verts = [
        bm.verts.new((x_bot_min, y_bot_min, z_min)),
        bm.verts.new((x_bot_max, y_bot_min, z_min)),
        bm.verts.new((x_bot_max, y_bot_max, z_min)),
        bm.verts.new((x_bot_min, y_bot_max, z_min)),
        bm.verts.new((x_top_min, y_top_min, z_max)),
        bm.verts.new((x_top_max, y_top_min, z_max)),
        bm.verts.new((x_top_max, y_top_max, z_max)),
        bm.verts.new((x_top_min, y_top_max, z_max)),
    ]
    faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    for f in faces:
        bm.faces.new((verts[f[0]], verts[f[1]], verts[f[2]], verts[f[3]]))


def bake_convex_edge_colors(bm: bmesh.types.BMesh, cuts: int = 8) -> None:
    """Subdivide mesh edges and bake signed face-angle convex wear to Col layer."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    bmesh.ops.subdivide_edges(
        bm,
        edges=bm.edges,
        cuts=cuts,
        use_grid_fill=True,
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    color_layer = bm.loops.layers.color.get("Col")
    if color_layer is None:
        color_layer = bm.loops.layers.color.new("Col")

    vert_wear: dict[int, float] = {}
    for v in bm.verts:
        max_convex = 0.0
        for e in v.link_edges:
            if len(e.link_faces) == 2:
                ang = e.calc_face_angle_signed(0.0)
                if ang > 0.25:
                    wear = min(1.0, ang / (math.pi * 0.5))
                    if wear > max_convex:
                        max_convex = wear
        vert_wear[v.index] = max_convex

    for f in bm.faces:
        for loop in f.loops:
            w = vert_wear.get(loop.vert.index, 0.0)
            loop[color_layer] = (w, 0.0, 0.0, 1.0)


def create_convex_collider_obj(
    name: str, bm: bmesh.types.BMesh, parent_obj: bpy.types.Object
) -> bpy.types.Object:
    """Create child collider wire mesh matching Godot -convcolonly naming."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent_obj
    obj.location = Vector((0.0, 0.0, 0.0))
    obj.display_type = "WIRE"
    obj.hide_render = True
    return obj


def build_body_colliders(
    parent_obj: bpy.types.Object,
    xb: float,
    xt: float,
    yb: float,
    yt: float,
    ixb: float,
    ixt: float,
    iyb: float,
    iyt: float,
    z_base: float,
    iz_base: float,
    z_top: float,
    collar_out: float = 0.0,
    collar_h: float = 0.0,
) -> None:
    """Build convex collider hull boxes for floor and 4 tapered walls with front rim guide."""
    bm_floor = bmesh.new()
    add_box(bm_floor, -xb, xb, -yb, yb, 0.0, iz_base)
    create_convex_collider_obj("Dumpster_Col_Floor-convcolonly", bm_floor, parent_obj)

    bm_front = bmesh.new()
    add_sloped_hexahedron(bm_front, -xb, xb, -xt, xt, -yb, -iyb, -yt, -iyt, z_base, z_top)
    create_convex_collider_obj("Dumpster_Col_Front-convcolonly", bm_front, parent_obj)

    # Front rim collider covering the outer collar and top rim surface for vault detection
    bm_rim_front = bmesh.new()
    add_box(
        bm_rim_front,
        -xt - collar_out,
        xt + collar_out,
        -yt - collar_out,
        -iyt + 0.06 * SCALE,
        z_top - collar_h,
        z_top,
    )
    create_convex_collider_obj("Dumpster_Col_Rim_Front-convcolonly", bm_rim_front, parent_obj)

    bm_back = bmesh.new()
    add_sloped_hexahedron(bm_back, -xb, xb, -xt, xt, iyb, yb, iyt, yt, z_base, z_top)
    create_convex_collider_obj("Dumpster_Col_Back-convcolonly", bm_back, parent_obj)

    bm_left = bmesh.new()
    add_sloped_hexahedron(bm_left, -xb, -ixb, -xt, -ixt, -iyb, iyb, -iyt, iyt, z_base, z_top)
    create_convex_collider_obj("Dumpster_Col_Left-convcolonly", bm_left, parent_obj)

    bm_right = bmesh.new()
    add_sloped_hexahedron(bm_right, ixb, xb, ixt, xt, -iyb, iyb, -iyt, iyt, z_base, z_top)
    create_convex_collider_obj("Dumpster_Col_Right-convcolonly", bm_right, parent_obj)


def build_dumpster_body(name: str, mat: bpy.types.Material) -> bpy.types.Object:
    """Generate main hollow container body with rim collar and fork pilasters."""
    bm = bmesh.new()

    w_bot = 2.00 * SCALE
    w_top = 2.20 * SCALE
    d_bot = 1.05 * SCALE
    d_top = 1.25 * SCALE
    z_base = 0.04 * SCALE
    z_top = 1.15 * SCALE
    wall_t = 0.05 * SCALE
    floor_t = 0.06 * SCALE

    xb, xt = w_bot * 0.5, w_top * 0.5
    yb, yt = d_bot * 0.5, d_top * 0.5
    ixb, ixt = xb - wall_t, xt - wall_t
    iyb, iyt = yb - wall_t, yt - wall_t
    iz_base = z_base + floor_t

    o_verts = [
        bm.verts.new((-xb, -yb, z_base)),
        bm.verts.new((xb, -yb, z_base)),
        bm.verts.new((xb, yb, z_base)),
        bm.verts.new((-xb, yb, z_base)),
        bm.verts.new((-xt, -yt, z_top)),
        bm.verts.new((xt, -yt, z_top)),
        bm.verts.new((xt, yt, z_top)),
        bm.verts.new((-xt, yt, z_top)),
    ]

    i_verts = [
        bm.verts.new((-ixb, -iyb, iz_base)),
        bm.verts.new((ixb, -iyb, iz_base)),
        bm.verts.new((ixb, iyb, iz_base)),
        bm.verts.new((-ixb, iyb, iz_base)),
        bm.verts.new((-ixt, -iyt, z_top)),
        bm.verts.new((ixt, -iyt, z_top)),
        bm.verts.new((ixt, iyt, z_top)),
        bm.verts.new((-ixt, iyt, z_top)),
    ]

    outer_faces = [
        (0, 3, 2, 1),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    for f in outer_faces:
        bm.faces.new((o_verts[f[0]], o_verts[f[1]], o_verts[f[2]], o_verts[f[3]]))

    inner_faces = [
        (0, 1, 2, 3),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    ]
    for f in inner_faces:
        bm.faces.new((i_verts[f[0]], i_verts[f[1]], i_verts[f[2]], i_verts[f[3]]))

    for idx in range(4):
        nxt = (idx + 1) % 4
        bm.faces.new((o_verts[4 + idx], o_verts[4 + nxt], i_verts[4 + nxt], i_verts[4 + idx]))

    collar_h = 0.08 * SCALE
    collar_out = 0.06 * SCALE
    cz_min = z_top - collar_h
    add_box(bm, -xt - collar_out, xt + collar_out, -yt - collar_out, -yt, cz_min, z_top)
    add_box(bm, -xt - collar_out, xt + collar_out, yt, yt + collar_out, cz_min, z_top)
    add_box(bm, -xt - collar_out, -xt, -yt, yt, cz_min, z_top)
    add_box(bm, xt, xt + collar_out, -yt, yt, cz_min, z_top)

    pil_w = 0.11 * SCALE
    pil_d = 0.045 * SCALE
    for sx in (-1.0, 1.0):
        bx_min = sx * (xb - pil_w) if sx > 0 else sx * xb
        bx_max = sx * xb if sx > 0 else sx * (xb - pil_w)
        tx_min = sx * (xt - pil_w) if sx > 0 else sx * xt
        tx_max = sx * xt if sx > 0 else sx * (xt - pil_w)

        add_sloped_hexahedron(
            bm, bx_min, bx_max, tx_min, tx_max, -yb - pil_d, -yb, -yt - pil_d, -yt, z_base, cz_min
        )
        add_sloped_hexahedron(
            bm, bx_min, bx_max, tx_min, tx_max, yb, yb + pil_d, yt, yt + pil_d, z_base, cz_min
        )

    for sx in (-1.0, 1.0):
        bx_in = sx * xb
        bx_out = sx * (xb + pil_d)
        tx_in = sx * xt
        tx_out = sx * (xt + pil_d)
        add_sloped_hexahedron(
            bm,
            min(bx_in, bx_out),
            max(bx_in, bx_out),
            min(tx_in, tx_out),
            max(tx_in, tx_out),
            -0.05 * SCALE,
            0.05 * SCALE,
            -0.05 * SCALE,
            0.05 * SCALE,
            z_base,
            cz_min,
        )

    add_box(bm, -xb, -xb + 0.12 * SCALE, -yb, yb, 0.0, z_base)
    add_box(bm, xb - 0.12 * SCALE, xb, -yb, yb, 0.0, z_base)

    hinge_y = yt + 0.02 * SCALE
    hinge_z = z_top + 0.02 * SCALE
    add_box(
        bm,
        -xt + 0.05 * SCALE,
        xt - 0.05 * SCALE,
        hinge_y - 0.012 * SCALE,
        hinge_y + 0.012 * SCALE,
        hinge_z - 0.012 * SCALE,
        hinge_z + 0.012 * SCALE,
    )
    for stand_x in (-0.85 * SCALE, -0.28 * SCALE, 0.28 * SCALE, 0.85 * SCALE):
        add_box(
            bm,
            stand_x - 0.015 * SCALE,
            stand_x + 0.015 * SCALE,
            yt,
            hinge_y + 0.012 * SCALE,
            z_top - 0.04 * SCALE,
            hinge_z + 0.015 * SCALE,
        )

    bake_convex_edge_colors(bm, cuts=8)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)

    build_body_colliders(
        obj, xb, xt, yb, yt, ixb, ixt, iyb, iyt, z_base, iz_base, z_top, collar_out, collar_h
    )
    return obj


def add_lid_rib(
    bm: bmesh.types.BMesh, x_center: float, y_front: float, y_back: float, z_base: float
) -> None:
    """Generate structural reinforcing ribs on the top surface of the lid."""
    w_bot = 0.055 * SCALE
    w_top = 0.032 * SCALE
    rib_h = 0.065 * SCALE
    lug_h = 0.105 * SCALE
    y_nose = y_front + 0.12 * SCALE
    y_lug = y_back - 0.14 * SCALE

    v = [
        bm.verts.new((x_center - w_bot, y_front + 0.02 * SCALE, z_base)),
        bm.verts.new((x_center + w_bot, y_front + 0.02 * SCALE, z_base)),
        bm.verts.new((x_center + w_bot, y_lug, z_base)),
        bm.verts.new((x_center - w_bot, y_lug, z_base)),
        bm.verts.new((x_center - w_top, y_nose, z_base + rib_h)),
        bm.verts.new((x_center + w_top, y_nose, z_base + rib_h)),
        bm.verts.new((x_center + w_top, y_lug, z_base + rib_h)),
        bm.verts.new((x_center - w_top, y_lug, z_base + rib_h)),
    ]
    faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    for f in faces:
        bm.faces.new((v[f[0]], v[f[1]], v[f[2]], v[f[3]]))

    add_box(
        bm,
        x_center - w_top,
        x_center + w_top,
        y_lug,
        0.015 * SCALE,
        -0.015 * SCALE,
        z_base + lug_h,
    )


def build_dumpster_lid(
    name: str, mat: bpy.types.Material, parent_obj: bpy.types.Object
) -> bpy.types.Object:
    """Generate hinged dumpster lid placed at rear top hinge line."""
    bm = bmesh.new()

    lid_depth = 1.34 * SCALE
    y_front = -lid_depth
    y_back = -0.02 * SCALE
    deck_t = 0.035 * SCALE
    rib_h = 0.065 * SCALE
    half_w = 1.12 * SCALE
    gap = 0.012 * SCALE

    add_box(bm, -half_w, -gap, y_front, y_back, 0.0, deck_t)
    add_box(bm, gap, half_w, y_front, y_back, 0.0, deck_t)

    rib_positions = tuple(pos * SCALE for pos in (-0.92, -0.56, -0.20, 0.20, 0.56, 0.92))
    for rx in rib_positions:
        add_lid_rib(bm, rx, y_front, y_back, deck_t)

    bake_convex_edge_colors(bm, cuts=6)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)

    obj.parent = parent_obj
    obj.location = Vector((0.0, 0.645 * SCALE, 1.17 * SCALE))

    bm_lid_col = bmesh.new()
    add_box(bm_lid_col, -half_w, half_w, y_front, y_back, 0.0, deck_t + rib_h)
    create_convex_collider_obj("Dumpster_Col_Lid-convcolonly", bm_lid_col, obj)

    return obj


def export_glb(body_obj: bpy.types.Object, out_path: Path) -> None:
    """Select hierarchy and export glTF binary asset with vertex colors."""
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    for obj in bpy.context.selected_objects:
        obj.select_set(False)

    def select_hierarchy(node: bpy.types.Object) -> None:
        node.select_set(True)
        for child in node.children:
            select_hierarchy(child)

    select_hierarchy(body_obj)
    bpy.context.view_layer.objects.active = body_obj

    bpy.ops.export_scene.gltf(
        filepath=str(out_path.resolve()),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_materials="EXPORT",
        export_attributes=True,
    )
    print(f"Exported Dumpster GLB: {out_path.resolve()}")


def generate_dumpster(export_path: Path | None = None) -> bpy.types.Object:
    """Generate body, lid, colliders, bake vertex colors, and export GLB."""
    to_remove = [o for o in bpy.data.objects if o.name.startswith("Dumpster_")]
    for obj in to_remove:
        mesh_data = obj.data if obj.type == "MESH" else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh_data is not None and mesh_data.users == 0:
            bpy.data.meshes.remove(mesh_data)

    mat_green = get_or_create_material(
        "Mat_Dumpster_Green", (0.13, 0.21, 0.11, 1.0), metallic=0.55, roughness=0.78
    )
    mat_lid = get_or_create_material(
        "Mat_Dumpster_Lid", (0.07, 0.08, 0.07, 1.0), metallic=0.10, roughness=0.85
    )

    body = build_dumpster_body("Dumpster_Body", mat_green)
    lid = build_dumpster_lid("Dumpster_Lid", mat_lid, body)
    lid.rotation_euler.x = 0.0

    target_export = export_path if export_path is not None else OUTPUT_PATH
    export_glb(body, target_export)
    return body


if __name__ == "__main__":
    generate_dumpster()
