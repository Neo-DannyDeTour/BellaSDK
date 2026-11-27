#!/usr/bin/env python3
"""Headless Blender 5.3 orthographic face texture projector for BellaSDK (/3d).

Projects a high-resolution orthographic front portrait plate (`ref_detail` or
`ref_front`) onto the head/face UV map of an MPFB2 or AI-generated character
mesh using Cycles DIFFUSE (color-only) baking — zero baked shadows, crisp eyes,
freckles, and lip fidelity.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Project front portrait plate onto 3D head UV")
    parser.add_argument("--input", type=Path, required=True, help="Input character GLB/blend path")
    parser.add_argument("--image", type=Path, required=True, help="Front portrait PNG/JPG plate")
    parser.add_argument("--output-tex", type=Path, required=True, help="Baked 2K head albedo PNG")
    parser.add_argument("--output-glb", type=Path, default=None, help="Optional re-exported GLB")
    parser.add_argument("--mesh-name", type=str, default=None, help="Target mesh object name")
    parser.add_argument("--uv-size", type=int, default=2048, help="Output texture size (px)")
    parser.add_argument("--head-z-min", type=float, default=0.82, help="Normalized Z start of head")
    parser.add_argument("--head-z-max", type=float, default=1.0, help="Normalized Z end of head")
    parser.add_argument("--ortho-pad", type=float, default=1.08, help="Ortho framing scale pad")
    return parser.parse_args(argv)


def _mesh_world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
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


def _select_target_mesh(mesh_name: str | None) -> bpy.types.Object:
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("No mesh objects found in scene.")
    if mesh_name:
        for obj in meshes:
            if obj.name == mesh_name or mesh_name.lower() in obj.name.lower():
                return obj
        raise RuntimeError(f"Mesh '{mesh_name}' not found. Available: {[o.name for o in meshes]}")
    return max(meshes, key=lambda o: len(o.data.vertices))


def _ensure_uv(obj: bpy.types.Object) -> str:
    if obj.data.uv_layers:
        return obj.data.uv_layers.active.name
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj.data.uv_layers.active.name


def main() -> int:
    args = _parse_args()
    if not args.input.is_file():
        raise FileNotFoundError(f"Input asset not found: {args.input}")
    if not args.image.is_file():
        raise FileNotFoundError(f"Portrait image not found: {args.image}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    if args.input.suffix.lower() == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()))
    else:
        bpy.ops.import_scene.gltf(filepath=str(args.input.resolve()))

    obj = _select_target_mesh(args.mesh_name)
    base_uv_name = _ensure_uv(obj)
    mins, maxs = _mesh_world_bounds(obj)
    total_h = max(1e-4, maxs.z - mins.z)
    z0 = mins.z + total_h * args.head_z_min
    z1 = mins.z + total_h * args.head_z_max
    head_h = max(1e-4, z1 - z0)
    cx = 0.5 * (mins.x + maxs.x)
    cz = 0.5 * (z0 + z1)

    # Create orthographic front projection UV layer ("ProjFront") mapped to head box
    proj_uv = obj.data.uv_layers.new(name="ProjFront")
    img = bpy.data.images.load(str(args.image.resolve()))
    aspect = float(img.size[0]) / max(1.0, float(img.size[1]))
    span_z = head_h * args.ortho_pad
    span_x = span_z * aspect

    mat_world = obj.matrix_world
    for poly in obj.data.polygons:
        for loop_idx in poly.loop_indices:
            v_idx = obj.data.loops[loop_idx].vertex_index
            w_co = mat_world @ obj.data.vertices[v_idx].co
            u = 0.5 + (w_co.x - cx) / span_x
            v = 0.5 + (w_co.z - cz) / span_z
            proj_uv.data[loop_idx].uv = (u, v)

    # Set up temporary projection material baking from ProjFront -> base_uv_name
    bake_img = bpy.data.images.new(
        name="BakedHeadAlbedo",
        width=args.uv_size,
        height=args.uv_size,
        alpha=False,
    )
    proj_mat = bpy.data.materials.new(name="M_FaceProjBake")
    proj_mat.use_nodes = True
    nt = proj_mat.node_tree
    nt.nodes.clear()

    out_node = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex_src = nt.nodes.new("ShaderNodeTexImage")
    tex_src.image = img
    tex_src.extension = "EXTEND"
    uv_node = nt.nodes.new("ShaderNodeUVMap")
    uv_node.uv_map = "ProjFront"

    tex_dst = nt.nodes.new("ShaderNodeTexImage")
    tex_dst.image = bake_img
    nt.nodes.active = tex_dst

    nt.links.new(uv_node.outputs["UV"], tex_src.inputs["Vector"])
    nt.links.new(tex_src.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

    orig_mats = list(obj.data.materials)
    obj.data.materials.clear()
    obj.data.materials.append(proj_mat)
    obj.data.uv_layers.active = obj.data.uv_layers[base_uv_name]
    obj.data.uv_layers[base_uv_name].active_render = True

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    scene.render.bake.margin = 8

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="DIFFUSE")

    args.output_tex.parent.mkdir(parents=True, exist_ok=True)
    bake_img.filepath_raw = str(args.output_tex.resolve())
    bake_img.file_format = "PNG"
    bake_img.save()

    # Clean up temporary projection UV & restore/assign baked albedo if exporting GLB
    obj.data.uv_layers.remove(proj_uv)
    if args.output_glb is not None:
        obj.data.materials.clear()
        final_mat = orig_mats[0] if orig_mats else bpy.data.materials.new(name="M_HeadBaked")
        final_mat.use_nodes = True
        f_nt = final_mat.node_tree
        f_bsdf = next((n for n in f_nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if f_bsdf is not None:
            f_tex = f_nt.nodes.new("ShaderNodeTexImage")
            f_tex.image = bpy.data.images.load(str(args.output_tex.resolve()))
            f_nt.links.new(f_tex.outputs["Color"], f_bsdf.inputs["Base Color"])
        obj.data.materials.append(final_mat)
        args.output_glb.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=str(args.output_glb.resolve()),
            export_format="GLB",
            export_apply=True,
        )
        print(f"[FaceProj] Exported GLB: {args.output_glb}")

    print(f"[FaceProj] Baked head albedo ({args.uv_size}px): {args.output_tex}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
