## Headless Blender harness: High-to-Low retopo, OpenGL Normal/AO/Albedo baking,
## cavity delighting, ORM channel packing, and Godot 4 mesh-only GLB export.
import argparse
import math
import os
import sys
import bmesh
import bpy
import numpy as np


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Godot 4 Gothic Arch Bake Harness")
    parser.add_argument("--high", required=True, help="Path to raw high-poly GLB/OBJ")
    parser.add_argument("--outdir", required=True, help="Output directory for GLB + PNGs")
    parser.add_argument("--res", type=int, default=2048, help="Texture resolution")
    parser.add_argument("--tris", type=int, default=2000, help="Target triangle count")
    parser.add_argument("--cage", type=float, default=0.03, help="Bake ray extrusion (m)")
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

    # Weld split vertex duplicates created by glTF UV seams/normals
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


def build_low_poly(high_obj: bpy.types.Object, target_tris: int) -> bpy.types.Object:
    """Builds clean, manifold low-poly mesh within target tri budget and packs UVs."""
    low_obj = high_obj.copy()
    low_obj.data = high_obj.data.copy()
    low_obj.name = "ArchMesh"
    low_obj.data.name = "ArchMesh"
    bpy.context.collection.objects.link(low_obj)

    bpy.ops.object.select_all(action="DESELECT")
    low_obj.select_set(True)
    bpy.context.view_layer.objects.active = low_obj

    # 1. Decimate directly from manifold high-poly to target tri budget
    current_tris = sum(len(p.vertices) - 2 for p in low_obj.data.polygons)
    if current_tris > target_tris:
        dec_mod = low_obj.modifiers.new(name="Decimate", type="DECIMATE")
        dec_mod.decimate_type = "COLLAPSE"
        dec_mod.ratio = max(float(target_tris) / float(current_tris), 0.01)
        dec_mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=dec_mod.name)

    # 2. Dissolve coplanar micro-slivers and re-triangulate for clean UVs & tangents
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(2.0))
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
    bpy.ops.object.mode_set(mode="OBJECT")

    # 3. Smooth shading
    bpy.ops.object.shade_smooth()

    # 4. Smart UV Project + Island Packing for clean non-overlapping UVs in [0, 1]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.mark_seam(clear=True)
    bpy.ops.uv.smart_project(angle_limit=math.radians(25.0), island_margin=0.015)
    bpy.ops.uv.pack_islands(margin=0.015)
    bpy.ops.object.mode_set(mode="OBJECT")

    return low_obj


def ensure_high_poly_material(high_obj: bpy.types.Object) -> None:
    if high_obj.data.materials:
        return
    mat = bpy.data.materials.new(name="HighPolyFallbackMat")
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.58, 0.55, 0.50, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.85
    high_obj.data.materials.append(mat)


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

    # For AO, unbaked background outside islands/margins is filled with 1.0 (unoccluded)
    ao_unbaked = ao_r < 0.05
    ao_r[ao_unbaked] = 1.0

    # Cavity-compensation delighting on baked surfaces
    safe_ao = np.clip(ao_r[:, :, np.newaxis], 0.35, 1.0)
    delighted_rgb = np.clip(raw_rgb / safe_ao, 0.0, 1.0)

    # For Albedo, fill unbaked background with base stone color
    albedo_unbaked = np.max(raw_rgb, axis=-1) < 0.05
    delighted_rgb[albedo_unbaked] = [0.58, 0.55, 0.50]
    albedo_rgba[:, :, :3] = delighted_rgb
    albedo_rgba[:, :, 3] = 1.0
    albedo_img.pixels.foreach_set(albedo_rgba.ravel())

    albedo_path = os.path.join(outdir, "arch_albedo.png")
    albedo_img.filepath_raw = albedo_path
    albedo_img.file_format = "PNG"
    albedo_img.save()
    print(f"[PackMaps] Saved: {albedo_path}")

    # Fix any normal misses or unbaked background to tangent space neutral (0.5, 0.5, 1.0)
    norm_len = np.linalg.norm(normal_rgba[:, :, :3], axis=-1)
    normal_rgba[norm_len < 0.2, :3] = [0.5, 0.5, 1.0]
    normal_rgba[:, :, 3] = 1.0
    normal_img.pixels.foreach_set(normal_rgba.ravel())

    normal_path = os.path.join(outdir, "arch_normal.png")
    normal_img.filepath_raw = normal_path
    normal_img.file_format = "PNG"
    normal_img.save()
    print(f"[PackMaps] Saved: {normal_path}")

    # Derive Roughness from AO + delighted luma
    luma = (
        0.2126 * delighted_rgb[:, :, 0]
        + 0.7152 * delighted_rgb[:, :, 1]
        + 0.0722 * delighted_rgb[:, :, 2]
    )
    roughness_g = np.clip(0.75 + (1.0 - ao_r) * 0.20 - (luma - 0.5) * 0.10, 0.65, 0.95)
    roughness_g[ao_unbaked | albedo_unbaked] = 0.85
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
    ensure_high_poly_material(high_obj)

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
