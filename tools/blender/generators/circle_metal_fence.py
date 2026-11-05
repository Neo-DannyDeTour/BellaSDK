#!/usr/bin/env python3
"""Procedural generator for 2-leaf octagonal sewer grate (circle_metal_fence.glb).

Builds CircleMetalFence root node containing GrateLeft and GrateRight with origins
at wall hinge axes, 8 inner crossbars, 2 wall hinge pins per leaf, and 10 compound
box colliders (-convcolonly) per leaf.
Compatible with Blender 3.6+, 4.x, and 5.x headless execution.
"""

import math
import os
from pathlib import Path
from typing import List, Tuple
import bmesh
import bpy


# --- Geometry Constants (Meters) ---
CIRCUMRADIUS: float = 1.0
APOTHEM: float = CIRCUMRADIUS * math.cos(math.pi / 8.0)  # ~0.92388 m
FRAME_FACE_WIDTH: float = 0.02
FRAME_HALF_WIDTH: float = FRAME_FACE_WIDTH * 0.5  # 0.01 m
FRAME_DEPTH: float = 0.04
FRAME_HALF_DEPTH: float = FRAME_DEPTH * 0.5  # 0.02 m
CENTER_GAP_HALF: float = 0.01  # 0.02 m total clearance between leaves

BAR_COUNT: int = 8
BAR_RADIUS: float = 0.015
BAR_SEGMENTS: int = 8

PIN_INDICES: Tuple[int, int] = (3, 6)  # 1-based from top
PIN_LENGTH: float = 0.08
PIN_RADIUS: float = 0.015

COL_HEIGHT: float = 0.03
COL_DEPTH: float = 0.04

MATERIAL_NAME: str = "M_RustyGrate"

SCRIPT_DIR: Path = Path(__file__).resolve().parent
PROJECT_ROOT: Path = SCRIPT_DIR.parents[2]
OUTPUT_DIR: Path = PROJECT_ROOT / "assets" / "models" / "props" / "circle_metal_fence"
OUTPUT_PATH: Path = OUTPUT_DIR / "circle_metal_fence.glb"


def clear_scene() -> None:
    """Remove all existing objects, meshes, and materials from the scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_material(name: str) -> bpy.types.Material:
    """Create placeholder PBR material slot for Godot material remapping."""
    mat: bpy.types.Material = bpy.data.materials.new(name=name)
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.22, 0.16, 0.13, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.85
        bsdf.inputs["Roughness"].default_value = 0.78
    return mat


def _octagon_chord_x(z_val: float, apothem_val: float) -> float:
    """Return horizontal X coordinate on the octagon perimeter at height z_val."""
    return min(apothem_val, math.sqrt(2.0) * apothem_val - abs(z_val))


def _add_d_frame(bm: bmesh.types.BMesh, sign: float) -> None:
    """Build mitered rectangular D-frame (4 outer segments + 1 vertical post)."""
    a_out: float = APOTHEM + FRAME_HALF_WIDTH
    a_in: float = APOTHEM - FRAME_HALF_WIDTH
    tan_oct: float = math.tan(math.pi / 8.0)

    x_post_out: float = CENTER_GAP_HALF
    x_post_in: float = CENTER_GAP_HALF + FRAME_FACE_WIDTH

    outer_xz: List[Tuple[float, float]] = [
        (x_post_out, a_out),
        (tan_oct * a_out, a_out),
        (a_out, tan_oct * a_out),
        (a_out, -tan_oct * a_out),
        (tan_oct * a_out, -a_out),
        (x_post_out, -a_out),
    ]
    inner_xz: List[Tuple[float, float]] = [
        (x_post_in, a_in),
        (tan_oct * a_in, a_in),
        (a_in, tan_oct * a_in),
        (a_in, -tan_oct * a_in),
        (tan_oct * a_in, -a_in),
        (x_post_in, -a_in),
    ]

    n_pts: int = len(outer_xz)
    outer_front: List[bmesh.types.BMVert] = []
    outer_back: List[bmesh.types.BMVert] = []
    inner_front: List[bmesh.types.BMVert] = []
    inner_back: List[bmesh.types.BMVert] = []

    for i in range(n_pts):
        ox_local: float = sign * (outer_xz[i][0] - APOTHEM)
        oz: float = outer_xz[i][1]
        ix_local: float = sign * (inner_xz[i][0] - APOTHEM)
        iz: float = inner_xz[i][1]

        outer_front.append(bm.verts.new((ox_local, -FRAME_HALF_DEPTH, oz)))
        outer_back.append(bm.verts.new((ox_local, FRAME_HALF_DEPTH, oz)))
        inner_front.append(bm.verts.new((ix_local, -FRAME_HALF_DEPTH, iz)))
        inner_back.append(bm.verts.new((ix_local, FRAME_HALF_DEPTH, iz)))

    for i in range(n_pts):
        nxt: int = (i + 1) % n_pts
        quads: List[Tuple[bmesh.types.BMVert, ...]] = [
            (outer_front[i], outer_front[nxt], inner_front[nxt], inner_front[i]),
            (inner_back[i], inner_back[nxt], outer_back[nxt], outer_back[i]),
            (outer_back[i], outer_back[nxt], outer_front[nxt], outer_front[i]),
            (inner_front[i], inner_front[nxt], inner_back[nxt], inner_back[i]),
        ]
        for q in quads:
            face = bm.faces.new(q)
            face.smooth = False


def _add_crossbars_and_pins(bm: bmesh.types.BMesh, sign: float) -> None:
    """Build 8 uncapped horizontal crossbars and 2 outer wall hinge pins."""
    a_in: float = APOTHEM - FRAME_HALF_WIDTH
    x_post_in: float = CENTER_GAP_HALF + FRAME_FACE_WIDTH
    z_step: float = (2.0 * APOTHEM) / (BAR_COUNT + 1)

    for bar_idx in range(1, BAR_COUNT + 1):
        z_center: float = APOTHEM - bar_idx * z_step
        ring_in: List[bmesh.types.BMVert] = []
        ring_out: List[bmesh.types.BMVert] = []

        for s in range(BAR_SEGMENTS):
            angle: float = (2.0 * math.pi * s) / BAR_SEGMENTS
            vy: float = BAR_RADIUS * math.cos(angle)
            vz: float = z_center + BAR_RADIUS * math.sin(angle)

            x_start_local: float = sign * (x_post_in - APOTHEM)
            x_end_abs: float = _octagon_chord_x(vz, a_in)
            x_end_local: float = sign * (x_end_abs - APOTHEM)

            ring_in.append(bm.verts.new((x_start_local, vy, vz)))
            ring_out.append(bm.verts.new((x_end_local, vy, vz)))

        for s in range(BAR_SEGMENTS):
            nxt: int = (s + 1) % BAR_SEGMENTS
            face = bm.faces.new((ring_in[s], ring_out[s], ring_out[nxt], ring_in[nxt]))
            face.smooth = True

        if bar_idx in PIN_INDICES:
            pin_in: List[bmesh.types.BMVert] = []
            pin_out: List[bmesh.types.BMVert] = []
            x_pin_start_local: float = 0.0  # Hinge axis (|X| = APOTHEM)
            x_pin_end_local: float = sign * PIN_LENGTH

            for s in range(BAR_SEGMENTS):
                angle = (2.0 * math.pi * s) / BAR_SEGMENTS
                vy = PIN_RADIUS * math.cos(angle)
                vz = z_center + PIN_RADIUS * math.sin(angle)
                pin_in.append(bm.verts.new((x_pin_start_local, vy, vz)))
                pin_out.append(bm.verts.new((x_pin_end_local, vy, vz)))

            for s in range(BAR_SEGMENTS):
                nxt = (s + 1) % BAR_SEGMENTS
                face = bm.faces.new((pin_in[s], pin_out[s], pin_out[nxt], pin_in[nxt]))
                face.smooth = True

            cap_face = bm.faces.new(pin_out)
            cap_face.smooth = False


def _create_box_collider(
    name: str,
    parent: bpy.types.Object,
    sign: float,
    z_center: float,
) -> bpy.types.Object:
    """Create single -convcolonly box mesh parented to grate leaf."""
    a_out: float = APOTHEM + FRAME_HALF_WIDTH
    x_min_abs: float = CENTER_GAP_HALF
    x_max_abs: float = _octagon_chord_x(z_center, a_out)

    x0: float = sign * (x_min_abs - APOTHEM)
    x1: float = sign * (x_max_abs - APOTHEM)
    x_lo: float = min(x0, x1)
    x_hi: float = max(x0, x1)

    y_lo: float = -COL_DEPTH * 0.5
    y_hi: float = COL_DEPTH * 0.5
    z_lo: float = z_center - COL_HEIGHT * 0.5
    z_hi: float = z_center + COL_HEIGHT * 0.5

    bm: bmesh.types.BMesh = bmesh.new()
    v000 = bm.verts.new((x_lo, y_lo, z_lo))
    v001 = bm.verts.new((x_lo, y_lo, z_hi))
    v010 = bm.verts.new((x_lo, y_hi, z_lo))
    v011 = bm.verts.new((x_lo, y_hi, z_hi))
    v100 = bm.verts.new((x_hi, y_lo, z_lo))
    v101 = bm.verts.new((x_hi, y_lo, z_hi))
    v110 = bm.verts.new((x_hi, y_hi, z_lo))
    v111 = bm.verts.new((x_hi, y_hi, z_hi))

    bm.faces.new((v000, v001, v101, v100))
    bm.faces.new((v110, v111, v011, v010))
    bm.faces.new((v010, v011, v001, v000))
    bm.faces.new((v100, v101, v111, v110))
    bm.faces.new((v001, v011, v111, v101))
    bm.faces.new((v010, v000, v100, v110))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh: bpy.types.Mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj: bpy.types.Object = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    return obj


def build_grate_leaf(
    leaf_name: str,
    sign: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    """Create visual mesh and 10 child -convcolonly colliders for one leaf."""
    bm: bmesh.types.BMesh = bmesh.new()
    _add_d_frame(bm, sign)
    _add_crossbars_and_pins(bm, sign)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            f0, f1 = edge.link_faces[0], edge.link_faces[1]
            if not f0.smooth or not f1.smooth:
                edge.smooth = False
            elif f0.normal.angle(f1.normal, 0.0) > math.radians(35.0):
                edge.smooth = False
        else:
            edge.smooth = False

    mesh: bpy.types.Mesh = bpy.data.meshes.new(leaf_name)
    bm.to_mesh(mesh)
    bm.free()

    if hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = math.radians(35.0)

    mesh.materials.append(material)

    leaf_obj: bpy.types.Object = bpy.data.objects.new(leaf_name, mesh)
    leaf_obj.location = (sign * APOTHEM, 0.0, 0.0)
    bpy.context.collection.objects.link(leaf_obj)

    bpy.ops.object.select_all(action="DESELECT")
    leaf_obj.select_set(True)
    bpy.context.view_layer.objects.active = leaf_obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(
        angle_limit=math.radians(66.0),
        island_margin=0.02,
        correct_aspect=True,
        scale_to_bounds=False,
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    z_step: float = (2.0 * APOTHEM) / (BAR_COUNT + 1)
    for col_idx in range(BAR_COUNT + 2):
        z_bar: float = APOTHEM - col_idx * z_step
        col_name: str = f"{leaf_name}_Col_{col_idx:02d}-convcolonly"
        _create_box_collider(col_name, leaf_obj, sign, z_bar)

    return leaf_obj


def main() -> None:
    """Build both grate leaves and export circle_metal_fence.glb."""
    clear_scene()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    mat: bpy.types.Material = create_material(MATERIAL_NAME)

    build_grate_leaf("GrateLeft", -1.0, mat)
    build_grate_leaf("GrateRight", 1.0, mat)

    out_path_str: str = str(OUTPUT_PATH.resolve())
    bpy.ops.export_scene.gltf(
        filepath=out_path_str,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
    )
    print(f"Exported: {out_path_str}")


if __name__ == "__main__":
    main()
