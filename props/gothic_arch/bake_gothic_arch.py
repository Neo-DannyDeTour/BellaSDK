## Headless Blender harness: High-to-Low retopo, Weighted Face Normals,
## OpenGL Normal/AO/Albedo baking, Weathered Gothic Ashlar Limestone procedural synthesis,
## ORM channel packing, and Godot 4 mesh-only GLB export.
import argparse
import math
import os
import sys
import bmesh
import bpy
import numpy as np

# Allow importing procedural architecture builder from sibling module
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_high_poly import create_gothic_arch_geometry


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Godot 4 Gothic Arch Bake Harness")
    parser.add_argument("--high", required=True, help="Path to raw high-poly GLB/OBJ")
    parser.add_argument("--outdir", required=True, help="Output directory for GLB + PNGs")
    parser.add_argument("--res", type=int, default=2048, help="Texture resolution")
    parser.add_argument("--tris", type=int, default=1900, help="Target triangle count")
    parser.add_argument("--cage", type=float, default=0.025, help="Bake ray extrusion (m)")
    return parser.parse_args(argv)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_high_poly(filepath: str) -> bpy.types.Object:
    ext = os.path.splitext(filepath)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=filepath)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=filepath)
    else:
        raise ValueError(f"Unsupported format: {ext}")

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("No mesh objects found in input file.")

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()

    high_obj = bpy.context.active_object
    high_obj.name = "Arch_HighPoly"

    # Weld split vertex duplicates created by glTF export
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.object.mode_set(mode="OBJECT")

    return high_obj


def normalize_transform_and_pivot(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Target dimensions in Blender Z-up: X=3.0m (width), Y=0.8m (depth), Z=4.0m (height)
    dims = obj.dimensions
    scale_x = 3.0 / max(dims.x, 0.001)
    scale_y = 0.8 / max(dims.y, 0.001)
    scale_z = 4.0 / max(dims.z, 0.001)
    obj.scale = (scale_x, scale_y, scale_z)
    bpy.ops.object.transform_apply(scale=True)

    # Snap origin to bottom-center floor plane [0, 0, 0]
    verts = [v.co for v in obj.data.vertices]
    min_x = min(v.x for v in verts)
    max_x = max(v.x for v in verts)
    min_y = min(v.y for v in verts)
    max_y = max(v.y for v in verts)
    min_z = min(v.z for v in verts)

    offset_x = (min_x + max_x) * 0.5
    offset_y = (min_y + max_y) * 0.5
    for v in obj.data.vertices:
        v.co.x -= offset_x
        v.co.y -= offset_y
        v.co.z -= min_z

    obj.data.update()
    obj.location = (0.0, 0.0, 0.0)


def assign_procedural_stone_shader(high_obj: bpy.types.Object) -> None:
    """Builds a rich multi-layered Weathered Gothic Ashlar Limestone node graph on high_obj.

    Replaces glTF's stripped material so Cycles bakes authentic mottled limestone
    albedo, ashlar block tonal variation, recessed mortar darkening, and chiselled
    micro-bump normal detail directly from 3D object coordinates.
    """
    high_obj.data.materials.clear()
    mat = bpy.data.materials.new(name="GothicAshlarStoneHighMat")
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

    tex_coord = nodes.new(type="ShaderNodeTexCoord")

    # 1. Brick/Ashlar block structure in 3D space (projected on XZ front/back & YZ sides)
    mapping_brick = nodes.new(type="ShaderNodeMapping")
    mapping_brick.inputs["Scale"].default_value = (1.5, 1.5, 2.2)
    links.new(tex_coord.outputs["Object"], mapping_brick.inputs["Vector"])

    brick = nodes.new(type="ShaderNodeTexBrick")
    brick.offset = 0.5
    brick.squash = 1.0
    brick.inputs["Scale"].default_value = 2.8
    brick.inputs["Mortar Size"].default_value = 0.018
    brick.inputs["Mortar Smooth"].default_value = 0.35
    brick.inputs["Bias"].default_value = 0.0
    brick.inputs["Brick Width"].default_value = 0.65
    brick.inputs["Row Height"].default_value = 0.28
    # Warm aged limestone block extremes + dark recessed mortar
    brick.inputs["Color1"].default_value = (0.36, 0.33, 0.29, 1.0)
    brick.inputs["Color2"].default_value = (0.52, 0.49, 0.44, 1.0)
    brick.inputs["Mortar"].default_value = (0.16, 0.15, 0.13, 1.0)
    links.new(mapping_brick.outputs["Vector"], brick.inputs["Vector"])

    # 2. Macro weathering cloud noise (breaks up uniformity across the arch)
    noise_macro = nodes.new(type="ShaderNodeTexNoise")
    noise_macro.inputs["Scale"].default_value = 2.6
    noise_macro.inputs["Detail"].default_value = 8.0
    noise_macro.inputs["Roughness"].default_value = 0.68
    noise_macro.inputs["Distortion"].default_value = 0.25
    links.new(tex_coord.outputs["Object"], noise_macro.inputs["Vector"])

    ramp_macro = nodes.new(type="ShaderNodeValToRGB")
    ramp_macro.color_ramp.elements[0].position = 0.22
    ramp_macro.color_ramp.elements[0].color = (0.28, 0.26, 0.23, 1.0)
    ramp_macro.color_ramp.elements[1].position = 0.78
    ramp_macro.color_ramp.elements[1].color = (0.58, 0.54, 0.49, 1.0)
    links.new(noise_macro.outputs["Fac"], ramp_macro.inputs["Fac"])

    # 3. High-frequency limestone pores, fossils & pitted mineral grain
    noise_micro = nodes.new(type="ShaderNodeTexNoise")
    noise_micro.inputs["Scale"].default_value = 34.0
    noise_micro.inputs["Detail"].default_value = 12.0
    noise_micro.inputs["Roughness"].default_value = 0.82
    links.new(tex_coord.outputs["Object"], noise_micro.inputs["Vector"])

    voronoi_pits = nodes.new(type="ShaderNodeTexVoronoi")
    voronoi_pits.inputs["Scale"].default_value = 22.0
    links.new(tex_coord.outputs["Object"], voronoi_pits.inputs["Vector"])

    # Blend Ashlar bricks + Macro weathering
    mix_color1 = nodes.new(type="ShaderNodeMix")
    mix_color1.data_type = "RGBA"
    mix_color1.blend_type = "MULTIPLY"
    mix_color1.inputs["Factor"].default_value = 0.55
    links.new(brick.outputs["Color"], mix_color1.inputs["A"])
    links.new(ramp_macro.outputs["Color"], mix_color1.inputs["B"])

    # Add micro mineral grain into Albedo
    ramp_micro = nodes.new(type="ShaderNodeValToRGB")
    ramp_micro.color_ramp.elements[0].position = 0.25
    ramp_micro.color_ramp.elements[0].color = (0.34, 0.32, 0.28, 1.0)
    ramp_micro.color_ramp.elements[1].position = 0.75
    ramp_micro.color_ramp.elements[1].color = (0.54, 0.51, 0.46, 1.0)
    links.new(noise_micro.outputs["Fac"], ramp_micro.inputs["Fac"])

    mix_final_col = nodes.new(type="ShaderNodeMix")
    mix_final_col.data_type = "RGBA"
    mix_final_col.blend_type = "MIX"
    mix_final_col.inputs["Factor"].default_value = 0.35
    links.new(mix_color1.outputs["Result"], mix_final_col.inputs["A"])
    links.new(ramp_micro.outputs["Color"], mix_final_col.inputs["B"])

    links.new(mix_final_col.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85

    # 4. Combined Height map for Bump -> Normal baking (Mortar grooves + Pores + Pits)
    mix_bump_a = nodes.new(type="ShaderNodeMix")
    mix_bump_a.data_type = "FLOAT"
    mix_bump_a.inputs["Factor"].default_value = 0.45
    links.new(noise_micro.outputs["Fac"], mix_bump_a.inputs["A"])
    links.new(voronoi_pits.outputs["Distance"], mix_bump_a.inputs["B"])

    mix_bump_b = nodes.new(type="ShaderNodeMix")
    mix_bump_b.data_type = "FLOAT"
    mix_bump_b.inputs["Factor"].default_value = 0.35
    links.new(mix_bump_a.outputs["Result"], mix_bump_b.inputs["A"])
    links.new(brick.outputs["Fac"], mix_bump_b.inputs["B"])

    bump = nodes.new(type="ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.55
    bump.inputs["Distance"].default_value = 0.012
    links.new(mix_bump_b.outputs["Result"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    high_obj.data.materials.append(mat)


def build_low_poly(high_obj: bpy.types.Object, target_tris: int) -> bpy.types.Object:
    """Builds clean, manifold low-poly architectural mesh with Weighted Normals and packed UVs."""
    low_obj = create_gothic_arch_geometry(subdivide_high=False)
    low_obj.name = "ArchMesh"
    low_obj.data.name = "ArchMesh"

    bpy.ops.object.select_all(action="DESELECT")
    low_obj.select_set(True)
    bpy.context.view_layer.objects.active = low_obj

    # 1. Dissolve coplanar micro-slivers and triangulate BEFORE scale normalization
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(4.0))
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.mesh.normals_make_consistent(inside=False)

    # 2. Mark UV seams (> 24 deg) and unwrap cleanly with 0 overlaps
    bpy.ops.mesh.mark_seam(clear=True)
    bpy.ops.mesh.select_mode(type="EDGE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.mesh.edges_select_sharp(sharpness=math.radians(24.0))
    bpy.ops.mesh.mark_seam(clear=False)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.015)
    bpy.ops.uv.pack_islands(margin=0.015)

    # 3. Mark sharp architectural edges (> 38 deg) and apply Weighted Normals
    # Eliminates ugly diagonal normal shading bands across flat stone faces!
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.mesh.edges_select_sharp(sharpness=math.radians(38.0))
    bpy.ops.mesh.mark_sharp()
    bpy.ops.object.mode_set(mode="OBJECT")

    normalize_transform_and_pivot(low_obj)

    bpy.ops.object.shade_smooth()
    wn_mod = low_obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    wn_mod.mode = "FACE_AREA_WITH_ANGLE"
    wn_mod.weight = 50
    wn_mod.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=wn_mod.name)

    return low_obj


def configure_cycles() -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.get_devices()
    configured = False
    for dev_type in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = dev_type
            for d in prefs.devices:
                if d.type == dev_type:
                    d.use = True
            scene.cycles.device = "GPU"
            configured = True
            print(f"[ConfigureCycles] Enabled GPU ({dev_type})")
            break
        except Exception as e:
            print(f"[ConfigureCycles] GPU device {dev_type} failed: {e}")
    if not configured:
        scene.cycles.device = "CPU"
        print("[ConfigureCycles] Fallback to CPU")
    scene.cycles.samples = 64
    scene.cycles.use_denoising = False


def bake_pass(
    high_obj: bpy.types.Object,
    low_obj: bpy.types.Object,
    img_name: str,
    res: int,
    bake_type: str,
    non_color: bool,
    cage_extrusion: float,
) -> bpy.types.Image:
    img = bpy.data.images.new(
        img_name, width=res, height=res, alpha=False, float_buffer=True
    )
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"

    low_obj.data.materials.clear()
    mat = bpy.data.materials.new(name=f"BakeMat_{img_name}")
    nodes = mat.node_tree.nodes
    tex_node = nodes.new(type="ShaderNodeTexImage")
    tex_node.image = img
    tex_node.select = True
    nodes.active = tex_node
    low_obj.data.materials.append(mat)

    bpy.ops.object.select_all(action="DESELECT")
    high_obj.select_set(True)
    low_obj.select_set(True)
    bpy.context.view_layer.objects.active = low_obj

    scene = bpy.context.scene
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = cage_extrusion
    scene.render.bake.max_ray_distance = cage_extrusion * 2.5
    scene.render.bake.margin = 16
    scene.render.bake.margin_type = "EXTEND"

    print(f"[BakePass] Baking {bake_type} ({img_name})...")
    if bake_type == "NORMAL":
        # OpenGL standard (+X, +Y, +Z) for Godot 4
        scene.render.bake.normal_space = "TANGENT"
        scene.render.bake.normal_r = "POS_X"
        scene.render.bake.normal_g = "POS_Y"
        scene.render.bake.normal_b = "POS_Z"
        bpy.ops.object.bake(type="NORMAL")
    elif bake_type == "AO":
        bpy.ops.object.bake(type="AO")
    elif bake_type == "DIFFUSE":
        scene.render.bake.use_pass_direct = False
        scene.render.bake.use_pass_indirect = False
        scene.render.bake.use_pass_color = True
        bpy.ops.object.bake(type="DIFFUSE")

    return img


def pack_and_save_maps(
    albedo_img: bpy.types.Image,
    ao_img: bpy.types.Image,
    normal_img: bpy.types.Image,
    res: int,
    outdir: str,
) -> None:
    os.makedirs(outdir, exist_ok=True)
    pixel_count = res * res * 4

    albedo_buf = np.empty(pixel_count, dtype=np.float32)
    ao_buf = np.empty(pixel_count, dtype=np.float32)
    normal_buf = np.empty(pixel_count, dtype=np.float32)
    albedo_img.pixels.foreach_get(albedo_buf)
    ao_img.pixels.foreach_get(ao_buf)
    normal_img.pixels.foreach_get(normal_buf)

    albedo_rgba = albedo_buf.reshape((res, res, 4))
    ao_rgba = ao_buf.reshape((res, res, 4))
    normal_rgba = normal_buf.reshape((res, res, 4))

    ao_r = np.clip(ao_rgba[:, :, 0], 0.0, 1.0)
    raw_rgb = np.clip(albedo_rgba[:, :, :3], 0.0, 1.0)

    # Identify unbaked background pixels outside UV islands & margins
    ao_unbaked = ao_r < 0.04
    albedo_unbaked = np.max(raw_rgb, axis=-1) < 0.04
    unbaked_mask = ao_unbaked | albedo_unbaked

    # Fill unbaked AO with 1.0 (unoccluded)
    ao_r[unbaked_mask] = 1.0
    # Smoothly clamp deep AO cavities so there are zero pure-black pixels
    ao_r = np.clip(ao_r, 0.22, 1.0)

    # Compute tangent-space normal steepness for chiselled edge highlight & mortar wear
    nx = normal_rgba[:, :, 0] * 2.0 - 1.0
    ny = normal_rgba[:, :, 1] * 2.0 - 1.0
    edge_slope = np.clip(np.sqrt(nx * nx + ny * ny), 0.0, 1.0)

    # Pure delighted base color (NO division by AO that caused white halos!)
    # Instead, add subtle pale chiselled edge wear on bevel slopes and warm aged tone
    delighted_rgb = raw_rgb.copy()
    chisel_highlight = (edge_slope * 0.08)[:, :, np.newaxis]
    cavity_tint = ((1.0 - ao_r) * 0.12)[:, :, np.newaxis]
    delighted_rgb = np.clip(delighted_rgb + chisel_highlight - cavity_tint, 0.18, 0.85)

    # Fill unbaked background with neutral weathered limestone base color
    delighted_rgb[unbaked_mask] = [0.46, 0.43, 0.39]
    albedo_rgba[:, :, :3] = delighted_rgb
    albedo_rgba[:, :, 3] = 1.0
    albedo_img.pixels.foreach_set(albedo_rgba.ravel())

    albedo_path = os.path.join(outdir, "arch_albedo.png")
    albedo_img.filepath_raw = albedo_path
    albedo_img.file_format = "PNG"
    albedo_img.save()
    print(f"[PackMaps] Saved: {albedo_path}")

    # Normalize tangent-space normals and fill unbaked background with neutral (0.5, 0.5, 1.0)
    norm_len = np.linalg.norm(normal_rgba[:, :, :3], axis=-1)
    invalid_norm = (norm_len < 0.2) | unbaked_mask
    normal_rgba[invalid_norm, :3] = [0.5, 0.5, 1.0]
    # Guarantee blue channel (+Z out of surface) stays positive to prevent black pixels
    normal_rgba[:, :, 2] = np.clip(normal_rgba[:, :, 2], 0.5, 1.0)
    normal_rgba[:, :, 0] = np.clip(normal_rgba[:, :, 0], 0.08, 0.92)
    normal_rgba[:, :, 1] = np.clip(normal_rgba[:, :, 1], 0.08, 0.92)
    normal_rgba[:, :, 3] = 1.0
    normal_img.pixels.foreach_set(normal_rgba.ravel())

    normal_path = os.path.join(outdir, "arch_normal.png")
    normal_img.filepath_raw = normal_path
    normal_img.file_format = "PNG"
    normal_img.save()
    print(f"[PackMaps] Saved: {normal_path}")

    # Derive Roughness from AO + limestone grain luma + edge wear
    luma = (
        0.2126 * delighted_rgb[:, :, 0]
        + 0.7152 * delighted_rgb[:, :, 1]
        + 0.0722 * delighted_rgb[:, :, 2]
    )
    roughness_g = np.clip(
        0.82 + (1.0 - ao_r) * 0.14 - (luma - 0.44) * 0.18 - edge_slope * 0.06,
        0.68,
        0.96,
    )
    roughness_g[unbaked_mask] = 0.85
    metallic_b = np.zeros_like(ao_r)

    orm_img = bpy.data.images.new("arch_orm", width=res, height=res, alpha=False)
    orm_img.colorspace_settings.name = "Non-Color"
    orm_rgba = np.stack([ao_r, roughness_g, metallic_b, np.ones_like(ao_r)], axis=-1)
    orm_img.pixels.foreach_set(orm_rgba.astype(np.float32).ravel())
    orm_path = os.path.join(outdir, "arch_orm.png")
    orm_img.filepath_raw = orm_path
    orm_img.file_format = "PNG"
    orm_img.save()
    print(f"[PackMaps] Saved: {orm_path}")


def export_clean_glb(
    low_obj: bpy.types.Object, high_obj: bpy.types.Object, outdir: str
) -> None:
    bpy.data.objects.remove(high_obj, do_unlink=True)
    low_obj.data.materials.clear()

    bpy.ops.object.select_all(action="DESELECT")
    low_obj.select_set(True)
    bpy.context.view_layer.objects.active = low_obj

    glb_path = os.path.join(outdir, "gothic_arch.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="NONE",
    )
    print(f"[GothicArchHarness] Exported clean mesh & textures to: {outdir}")


def main() -> None:
    args = parse_args()
    clear_scene()
    configure_cycles()

    high_obj = import_high_poly(args.high)
    normalize_transform_and_pivot(high_obj)
    assign_procedural_stone_shader(high_obj)

    low_obj = build_low_poly(high_obj, args.tris)

    albedo_img = bake_pass(
        high_obj, low_obj, "arch_albedo", args.res, "DIFFUSE", False, args.cage
    )
    ao_img = bake_pass(high_obj, low_obj, "arch_ao", args.res, "AO", True, args.cage)
    normal_img = bake_pass(
        high_obj, low_obj, "arch_normal", args.res, "NORMAL", True, args.cage
    )

    pack_and_save_maps(albedo_img, ao_img, normal_img, args.res, args.outdir)
    export_clean_glb(low_obj, high_obj, args.outdir)


if __name__ == "__main__":
    main()
