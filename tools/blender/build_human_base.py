#!/usr/bin/env python3
"""Headless Blender 5.3 MPFB2 anatomical human base generator for BellaSDK (/3d).

Builds a clean, game-ready human base mesh via the installed MPFB2 extension
(`bl_ext.blender_org.mpfb`), applies macro proportions, strips MakeHuman helper
geometry, assigns clean material slots (`M_Skin_Body`, `M_Skin_Head`), scales
to exact real-world meter height (`min_z = 0`), and exports GLB (+ optional .blend).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate anatomical MPFB2 human base in Blender")
    parser.add_argument("--output", type=Path, required=True, help="Output GLB file path")
    parser.add_argument("--save-blend", type=Path, default=None, help="Optional .blend save path")
    parser.add_argument("--name", type=str, default="HumanBase", help="Mesh object name")
    parser.add_argument(
        "--gender",
        type=float,
        default=0.0,
        help="MPFB2 gender macro: 0.0 = female, 0.5 = neutral, 1.0 = male",
    )
    parser.add_argument("--age", type=float, default=0.35, help="MPFB2 age macro (0.0..1.0)")
    parser.add_argument("--muscle", type=float, default=0.35, help="MPFB2 muscle macro (0.0..1.0)")
    parser.add_argument("--weight", type=float, default=0.45, help="MPFB2 weight macro (0.0..1.0)")
    parser.add_argument("--target-height", type=float, default=1.68, help="Target height in meters")
    parser.add_argument("--head-z-ratio", type=float, default=0.84, help="Z ratio for Head slot")
    return parser.parse_args(argv)


def _enable_mpfb() -> None:
    import addon_utils

    for mod_name in ("bl_ext.blender_org.mpfb", "mpfb"):
        try:
            addon_utils.enable(mod_name, default_set=False, persistent=False)
            return
        except Exception:
            continue
    raise RuntimeError("MPFB2 Blender extension ('bl_ext.blender_org.mpfb') is not installed.")


def _import_mpfb_services():
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    from bl_ext.blender_org.mpfb.services.targetservice import TargetService

    return HumanService, TargetService


def _world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    for corner in obj.bound_box:
        pt = obj.matrix_world @ Vector(corner)
        mins.x = min(mins.x, pt.x)
        mins.y = min(mins.y, pt.y)
        mins.z = min(mins.z, pt.z)
        maxs.x = max(maxs.x, pt.x)
        maxs.y = max(maxs.y, pt.y)
        maxs.z = max(maxs.z, pt.z)
    return mins, maxs


def _make_skin_mat(name: str, base_rgb: tuple[float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*base_rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.52
        if "Subsurface Weight" in bsdf.inputs:
            bsdf.inputs["Subsurface Weight"].default_value = 0.25
    return mat


def main() -> int:
    args = _parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _enable_mpfb()
    HumanService, TargetService = _import_mpfb_services()

    macro = TargetService.get_default_macro_info_dict()
    macro["gender"] = float(max(0.0, min(1.0, args.gender)))
    macro["age"] = float(max(0.0, min(1.0, args.age)))
    macro["muscle"] = float(max(0.0, min(1.0, args.muscle)))
    macro["weight"] = float(max(0.0, min(1.0, args.weight)))

    human = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=False,
        extra_vertex_groups=False,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=macro,
    )
    human.name = args.name

    # Bake macro shape keys into base mesh, then apply MASK modifier to strip helpers
    bpy.context.view_layer.objects.active = human
    human.select_set(True)
    if human.data.shape_keys is not None:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for mod in list(human.modifiers):
        if mod.type == "MASK":
            bpy.ops.object.modifier_apply(modifier=mod.name)

    # Scale to exact target height and ground feet to z = 0
    bpy.context.view_layer.update()
    mins, maxs = _world_bounds(human)
    cur_h = max(1e-4, maxs.z - mins.z)
    scale_f = float(args.target_height) / cur_h
    human.scale = (scale_f, scale_f, scale_f)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    bpy.context.view_layer.update()
    mins, maxs = _world_bounds(human)
    cx = 0.5 * (mins.x + maxs.x)
    cy = 0.5 * (mins.y + maxs.y)
    human.location = (-cx, -cy, -mins.z)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Assign separate Body and Head material slots so Head gets dedicated 2K UV/projection
    human.data.materials.clear()
    mat_body = _make_skin_mat(f"M_{args.name}_Body", (0.86, 0.72, 0.65))
    mat_head = _make_skin_mat(f"M_{args.name}_Head", (0.88, 0.74, 0.67))
    human.data.materials.append(mat_body)
    human.data.materials.append(mat_head)

    bpy.context.view_layer.update()
    mins, maxs = _world_bounds(human)
    head_cut_z = mins.z + (maxs.z - mins.z) * args.head_z_ratio
    for poly in human.data.polygons:
        poly.use_smooth = True
        poly.material_index = 1 if poly.center.z >= head_cut_z else 0

    human.data.calc_loop_triangles()
    tri_count = len(human.data.loop_triangles)
    uv_count = len(human.data.uv_layers)

    if args.save_blend is not None:
        args.save_blend.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(args.save_blend.resolve()))
        print(f"[MPFB2] Saved blend: {args.save_blend}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(args.output.resolve()),
        export_format="GLB",
        export_apply=True,
    )
    print(
        f"[MPFB2] Exported {args.output} | tris={tri_count} | uvs={uv_count} "
        f"| slots={[m.name for m in human.data.materials]} | height={args.target_height:.3f}m"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
