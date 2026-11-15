#!/usr/bin/env python3
"""Headless Blender post-processor for TRELLIS / AI-generated GLB assets.

Performs UV-preserving quadric decimation, normal recalculation, real-world
meter scaling, bottom-center pivot grounding, embedded PBR texture extraction,
and Godot 4 GLB re-export.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import bmesh
import bpy
from mathutils import Vector

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.exporter import clean_scene, export_godot_glb  # noqa: E402


def _parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Post-process TRELLIS GLB in Blender")
    parser.add_argument("--input", type=Path, required=True, help="Input raw GLB path")
    parser.add_argument("--output", type=Path, required=True, help="Output clean GLB path")
    parser.add_argument("--slug", type=str, required=True, help="Asset slug")
    parser.add_argument("--tri-budget", type=int, default=2000, help="Target max triangles")
    parser.add_argument("--target-height", type=float, default=None, help="Target height (meters)")
    parser.add_argument("--scale", type=float, default=None, help="Uniform scale multiplier")
    parser.add_argument("--tex-dir", type=Path, required=True, help="Directory for extracted textures")
    parser.add_argument("--meta-out", type=Path, required=True, help="Output JSON metadata path")
    parser.add_argument("--keep-separate", action="store_true", help="Do not join sub-meshes")
    return parser.parse_args(argv)


def _get_mesh_objects() -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def _world_bounds(mesh_objs: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for obj in mesh_objs:
        mat = obj.matrix_world
        for corner in obj.bound_box:
            pt = mat @ Vector(corner)
            mins.x = min(mins.x, pt.x)
            mins.y = min(mins.y, pt.y)
            mins.z = min(mins.z, pt.z)
            maxs.x = max(maxs.x, pt.x)
            maxs.y = max(maxs.y, pt.y)
            maxs.z = max(maxs.z, pt.z)
    return mins, maxs


def _total_triangles(mesh_objs: list[bpy.types.Object]) -> int:
    total = 0
    for obj in mesh_objs:
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def _clean_geometry(obj: bpy.types.Object, merge_dist: float = 0.0005) -> None:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge_dist)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def _decimate_uv_safe(obj: bpy.types.Object, target_tris: int) -> None:
    obj.data.calc_loop_triangles()
    current_tris = len(obj.data.loop_triangles)
    if current_tris <= target_tris or current_tris <= 0:
        return

    ratio = max(0.01, min(0.99, float(target_tris) / float(current_tris)))
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new(name="TrellisDecimate", type="DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)


def _trace_image_node(socket: bpy.types.NodeSocket) -> bpy.types.Image | None:
    if not socket.is_linked:
        return None
    node = socket.links[0].from_node
    if node.type == "TEX_IMAGE" and node.image is not None:
        return node.image
    if node.type == "NORMAL_MAP" and "Color" in node.inputs:
        return _trace_image_node(node.inputs["Color"])
    if node.type == "SEPARATE_COLOR" and "Color" in node.inputs:
        return _trace_image_node(node.inputs["Color"])
    for inp in node.inputs:
        img = _trace_image_node(inp)
        if img is not None:
            return img
    return None


def _save_image_png(img: bpy.types.Image, out_path: Path) -> Path | None:
    if img.size[0] == 0 or img.size[1] == 0:
        return None
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img_copy = img.copy()
    try:
        if img_copy.packed_file is None:
            img_copy.pack()
        img_copy.filepath_raw = str(out_path)
        img_copy.file_format = "PNG"
        img_copy.save()
        return out_path if out_path.is_file() else None
    finally:
        bpy.data.images.remove(img_copy)


def _extract_material_textures(
    mesh_objs: list[bpy.types.Object],
    tex_dir: Path,
    slug: str,
) -> dict[str, str]:
    extracted: dict[str, str] = {}
    seen_mats: set[str] = set()
    for obj in mesh_objs:
        for mat in obj.data.materials:
            if mat is None or mat.name in seen_mats or mat.node_tree is None:
                continue
            seen_mats.add(mat.name)
            bsdf = next(
                (n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"),
                None,
            )
            if bsdf is None:
                continue

            slot_map = {
                "albedo": "Base Color",
                "normal": "Normal",
                "metallic": "Metallic",
                "roughness": "Roughness",
            }
            for key, input_name in slot_map.items():
                if key in extracted or input_name not in bsdf.inputs:
                    continue
                img = _trace_image_node(bsdf.inputs[input_name])
                if img is None:
                    continue
                target = tex_dir / f"{slug}_{key}_raw.png"
                saved = _save_image_png(img, target)
                if saved is not None:
                    extracted[key] = str(saved)
    return extracted


def main() -> int:
    args = _parse_args()
    clean_scene()

    bpy.ops.import_scene.gltf(filepath=str(args.input.resolve()))
    mesh_objs = _get_mesh_objects()
    if not mesh_objs:
        raise RuntimeError(f"No mesh objects found in {args.input}")

    # Unparent while keeping world transforms and remove empty hierarchy nodes
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")

    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)

    if not args.keep_separate and len(mesh_objs) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in mesh_objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = mesh_objs[0]
        bpy.ops.object.join()
        mesh_objs = _get_mesh_objects()

    # Apply rotation & scale first so dimensions match world units
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Extract embedded textures before decimation/export
    extracted = _extract_material_textures(mesh_objs, args.tex_dir, args.slug)

    # Weld vertices, recalc normals, and UV-safe decimate proportionally per object
    total_before = _total_triangles(mesh_objs)
    for obj in mesh_objs:
        _clean_geometry(obj)
        obj.data.calc_loop_triangles()
        obj_tris = len(obj.data.loop_triangles)
        share = max(12, int(args.tri_budget * (float(obj_tris) / max(1.0, float(total_before)))))
        _decimate_uv_safe(obj, share)
        for poly in obj.data.polygons:
            poly.use_smooth = True

    # Real-world meter scale and bottom-center pivot grounding (min_z = 0, XY centered)
    mins, maxs = _world_bounds(mesh_objs)
    height_z = max(1e-5, maxs.z - mins.z)
    factor = 1.0
    if args.scale is not None:
        factor = float(args.scale)
    elif args.target_height is not None:
        factor = float(args.target_height) / height_z

    if abs(factor - 1.0) > 1e-6:
        for obj in mesh_objs:
            obj.scale = (factor, factor, factor)
            obj.location = obj.location * factor
        bpy.context.view_layer.update()
        mins, maxs = _world_bounds(mesh_objs)

    center_x = 0.5 * (mins.x + maxs.x)
    center_y = 0.5 * (mins.y + maxs.y)
    offset = Vector((-center_x, -center_y, -mins.z))
    for obj in mesh_objs:
        obj.location += offset

    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    bpy.context.view_layer.update()
    final_mins, final_maxs = _world_bounds(mesh_objs)
    ext_blender = final_maxs - final_mins
    # Godot uses +Y up, -Z forward -> Blender (X, Y, Z) maps to Godot (X, Z, Y)
    godot_dims = [round(float(ext_blender.x), 4), round(float(ext_blender.z), 4), round(float(ext_blender.y), 4)]
    final_tris = _total_triangles(mesh_objs)

    export_godot_glb(args.output, export_animations=False, apply_modifiers=True)

    meta: dict[str, Any] = {
        "tri_count_raw": total_before,
        "tri_count": final_tris,
        "dimensions_m": godot_dims,
        "uv_layers": max((len(o.data.uv_layers) for o in mesh_objs), default=0),
        "extracted_textures": extracted,
    }
    args.meta_out.parent.mkdir(parents=True, exist_ok=True)
    args.meta_out.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"[BlenderPost] {args.slug}: {total_before} -> {final_tris} tris | dims_m={godot_dims}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
