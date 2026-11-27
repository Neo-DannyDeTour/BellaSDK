#!/usr/bin/env python3
"""Headless Blender 4.x/5.x script: 8x8 Flipbook Atlas Generator for Godot 4.

Generates:
1. atlas_color_alpha.png (2048x2048 RGBA, premultiplied albedo/emission + opacity)
2. atlas_normal.png      (2048x2048 RGBA, camera-space normal map + opacity)
"""

import argparse
import math
import os
import shutil
import sys
import tempfile
import numpy as np
import bpy


def configure_compute_device(scene: bpy.types.Scene) -> str:
    """Configures Cycles compute device: OptiX -> CUDA -> HIP -> CPU fallback."""
    scene.render.engine = 'CYCLES'
    cprefs = bpy.context.preferences.addons['cycles'].preferences
    cprefs.refresh_devices()

    for dev_type in ('OPTIX', 'CUDA', 'HIP', 'ONEAPI', 'METAL'):
        devs = cprefs.get_devices_for_type(dev_type)
        if devs:
            cprefs.compute_device_type = dev_type
            for d in devs:
                d.use = True
            scene.cycles.device = 'GPU'
            return f"GPU ({dev_type})"

    scene.cycles.device = 'CPU'
    return "CPU"


def setup_materials() -> tuple[bpy.types.Material, bpy.types.Material]:
    """Builds Pass 1 (Color/Emission) and Pass 2 (Scatter/Normal) volume node trees."""
    mat_color = bpy.data.materials.new("Mat_ExplosionColor")
    mat_color.use_nodes = True
    c_nodes = mat_color.node_tree.nodes
    c_links = mat_color.node_tree.links
    c_nodes.clear()

    c_out = c_nodes.new("ShaderNodeOutputMaterial")
    c_vol = c_nodes.new("ShaderNodeVolumePrincipled")
    c_vol.inputs["Density"].default_value = 8.0
    c_vol.inputs["Density Attribute"].default_value = "density"
    c_vol.inputs["Color"].default_value = (0.15, 0.14, 0.13, 1.0)
    c_vol.inputs["Absorption Color"].default_value = (0.02, 0.02, 0.02, 1.0)

    attr_flame = c_nodes.new("ShaderNodeAttribute")
    attr_flame.attribute_name = "flame"

    c_ramp = c_nodes.new("ShaderNodeValToRGB")
    c_ramp.color_ramp.elements[0].position = 0.04
    c_ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    c_ramp.color_ramp.elements[1].position = 0.30
    c_ramp.color_ramp.elements[1].color = (1.0, 0.22, 0.02, 1.0)
    elem_hot = c_ramp.color_ramp.elements.new(0.70)
    elem_hot.color = (1.0, 0.85, 0.30, 1.0)

    c_mul = c_nodes.new("ShaderNodeMath")
    c_mul.operation = 'MULTIPLY'
    c_mul.inputs[1].default_value = 25.0

    c_links.new(attr_flame.outputs["Fac"], c_ramp.inputs["Fac"])
    c_links.new(c_ramp.outputs["Color"], c_vol.inputs["Emission Color"])
    c_links.new(attr_flame.outputs["Fac"], c_mul.inputs[0])
    c_links.new(c_mul.outputs["Value"], c_vol.inputs["Emission Strength"])
    c_links.new(c_vol.outputs["Volume"], c_out.inputs["Volume"])

    mat_scatter = bpy.data.materials.new("Mat_VolumeScatterNormal")
    mat_scatter.use_nodes = True
    s_nodes = mat_scatter.node_tree.nodes
    s_links = mat_scatter.node_tree.links
    s_nodes.clear()

    s_out = s_nodes.new("ShaderNodeOutputMaterial")
    s_vol = s_nodes.new("ShaderNodeVolumeScatter")
    s_vol.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    s_vol.inputs["Anisotropy"].default_value = 0.0

    s_attr = s_nodes.new("ShaderNodeAttribute")
    s_attr.attribute_name = "density"
    s_mul = s_nodes.new("ShaderNodeMath")
    s_mul.operation = 'MULTIPLY'
    s_mul.inputs[1].default_value = 5.0

    s_links.new(s_attr.outputs["Fac"], s_mul.inputs[0])
    s_links.new(s_mul.outputs["Value"], s_vol.inputs["Density"])
    s_links.new(s_vol.outputs["Volume"], s_out.inputs["Volume"])

    return mat_color, mat_scatter


def build_camera_light_rig(
    scene: bpy.types.Scene, cam_obj: bpy.types.Object
) -> dict[str, tuple[bpy.types.Object, bool]]:
    """Builds camera-space 6-way directional sun lights parented to orthographic camera."""
    light_specs = [
        ("Light_PosX", (1.0, 0.0, 0.0), (0.0, math.radians(90.0), 0.0), True),
        ("Light_PosY", (0.0, 1.0, 0.0), (math.radians(-90.0), 0.0, 0.0), True),
        ("Light_PosZ", (0.0, 0.0, 1.0), (0.0, 0.0, 0.0), True),
        ("Light_NegX", (1.0, 0.0, 0.0), (0.0, math.radians(-90.0), 0.0), False),
        ("Light_NegY", (0.0, 1.0, 0.0), (math.radians(90.0), 0.0, 0.0), False),
        ("Light_NegZ", (0.0, 0.0, 1.0), (0.0, math.radians(180.0), 0.0), False),
    ]

    lights = {}
    for name, color, rot_euler, is_pos in light_specs:
        ldata = bpy.data.lights.new(name, 'SUN')
        ldata.energy = 5.0
        ldata.color = color
        lobj = bpy.data.objects.new(name, ldata)
        lobj.parent = cam_obj
        lobj.rotation_euler = rot_euler
        lobj.hide_render = True
        scene.collection.objects.link(lobj)
        lights[name] = (lobj, is_pos)

    return lights


def read_image_to_numpy(filepath: str, width: int, height: int) -> np.ndarray:
    """Reads rendered PNG into a float32 RGBA NumPy array."""
    img = bpy.data.images.load(filepath)
    buffer = np.empty(width * height * 4, dtype=np.float32)
    img.pixels.foreach_get(buffer)
    bpy.data.images.remove(img)
    return buffer.reshape((height, width, 4))


def write_numpy_to_image(arr: np.ndarray, filepath: str) -> None:
    """Writes a float32 RGBA NumPy array directly to PNG via Blender Image API."""
    height, width, _ = arr.shape
    img_name = os.path.splitext(os.path.basename(filepath))[0]
    img = bpy.data.images.new(img_name, width=width, height=height, alpha=True, float_buffer=True)
    img.pixels.foreach_set(arr.astype(np.float32).ravel())
    img.file_format = 'PNG'
    img.filepath_raw = filepath
    img.save()
    bpy.data.images.remove(img)


def main() -> None:
    """Main execution pipeline."""
    raw_args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser(description="Headless Explosion Flipbook Atlas Generator")
    parser.add_argument("--output-dir", default=".", help="Directory to save output PNG atlases")
    parser.add_argument("--resolution", type=int, default=128, help="Mantaflow domain resolution")
    parser.add_argument("--samples", type=int, default=24, help="Cycles render samples per tile")
    parser.add_argument("--tile-size", type=int, default=256, help="Tile resolution in pixels")
    parser.add_argument("--frames", type=int, default=64, help="Total frames (8x8 = 64)")
    args = parser.parse_args(raw_args)

    out_dir = os.path.abspath(args.output_dir)
    os.makedirs(out_dir, exist_ok=True)

    tmp_dir = tempfile.mkdtemp(prefix="blender_flipbook_")
    cache_dir = os.path.join(tmp_dir, "mantaflow_cache") + "/"
    render_tmp = os.path.join(tmp_dir, "renders")
    os.makedirs(cache_dir, exist_ok=True)
    os.makedirs(render_tmp, exist_ok=True)

    print(f"=== Flipbook Atlas Generator ===")
    print(f"Output Directory: {out_dir}")
    print(f"Domain Resolution: {args.resolution} | Frames: {args.frames} | Samples: {args.samples}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    device_info = configure_compute_device(scene)
    print(f"Cycles Compute Device: {device_info}")

    scene.cycles.samples = args.samples
    scene.cycles.preview_samples = args.samples
    scene.render.resolution_x = args.tile_size
    scene.render.resolution_y = args.tile_size
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'

    scene.frame_start = 1
    scene.frame_end = args.frames

    cam_data = bpy.data.cameras.new("OrthoCamera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 5.2
    cam_obj = bpy.data.objects.new("Camera", cam_data)
    cam_obj.location = (0.0, -8.0, 0.0)
    cam_obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    lights = build_camera_light_rig(scene, cam_obj)

    domain_mesh = bpy.data.meshes.new("DomainMesh")
    domain_obj = bpy.data.objects.new("FluidDomain", domain_mesh)
    scene.collection.objects.link(domain_obj)
    domain_obj.location = (0.0, 0.0, 0.0)
    domain_obj.scale = (2.2, 2.2, 2.2)
    bpy.context.view_layer.objects.active = domain_obj
    bpy.ops.object.transform_apply(scale=True)

    dom_mod = domain_obj.modifiers.new("FluidDomain", 'FLUID')
    dom_mod.fluid_type = 'DOMAIN'
    ds = dom_mod.domain_settings
    ds.domain_type = 'GAS'
    ds.resolution_max = args.resolution
    ds.use_dissolve_smoke = True
    ds.dissolve_speed = 25
    ds.use_dissolve_smoke_log = True
    ds.cache_type = 'ALL'
    ds.cache_directory = cache_dir
    ds.cache_frame_start = 1
    ds.cache_frame_end = args.frames

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.45, location=(0.0, 0.0, -0.25))
    emitter_obj = bpy.context.active_object
    emitter_obj.name = "FluidEmitter"
    flow_mod = emitter_obj.modifiers.new("FluidFlow", 'FLUID')
    flow_mod.fluid_type = 'FLOW'
    fs = flow_mod.flow_settings
    fs.flow_type = 'BOTH'
    fs.flow_behavior = 'INFLOW'
    fs.use_initial_velocity = True
    fs.velocity_normal = 8.5
    fs.velocity_random = 5.5

    fs.use_inflow = True
    fs.keyframe_insert("use_inflow", frame=1)
    fs.keyframe_insert("use_inflow", frame=8)
    fs.use_inflow = False
    fs.keyframe_insert("use_inflow", frame=9)

    mat_color, mat_scatter = setup_materials()
    domain_obj.data.materials.append(mat_color)

    bpy.context.view_layer.objects.active = domain_obj
    print(f"Baking Mantaflow simulation ({args.frames} frames @ res {args.resolution})...")
    bpy.ops.fluid.bake_all()
    print("Mantaflow bake complete.")

    grid_size = int(math.ceil(math.sqrt(args.frames)))
    atlas_dim = grid_size * args.tile_size
    atlas_color = np.zeros((atlas_dim, atlas_dim, 4), dtype=np.float32)
    atlas_normal = np.zeros((atlas_dim, atlas_dim, 4), dtype=np.float32)

    print(f"Rendering {args.frames} frames -> {atlas_dim}x{atlas_dim} atlas...")

    for f in range(1, args.frames + 1):
        scene.frame_set(f)
        idx = f - 1
        tile_row = idx // grid_size
        tile_col = idx % grid_size

        y_start = (grid_size - 1 - tile_row) * args.tile_size
        y_end = y_start + args.tile_size
        x_start = tile_col * args.tile_size
        x_end = x_start + args.tile_size

        # Pass 1: Color
        domain_obj.data.materials[0] = mat_color
        for lobj, _ in lights.values():
            lobj.hide_render = True

        col_path = os.path.join(render_tmp, f"col_{f:03d}.png")
        scene.render.filepath = col_path
        bpy.ops.render.render(write_still=True)
        col_frame = read_image_to_numpy(col_path, args.tile_size, args.tile_size)

        alpha = col_frame[:, :, 3:4]
        col_frame[:, :, :3] = col_frame[:, :, :3] * np.clip(alpha, 0.0, 1.0)
        atlas_color[y_start:y_end, x_start:x_end] = col_frame

        # Pass 2: Normals
        domain_obj.data.materials[0] = mat_scatter

        # Sub-pass 2A: Pos
        for lobj, is_pos in lights.values():
            lobj.hide_render = not is_pos
        pos_path = os.path.join(render_tmp, f"pos_{f:03d}.png")
        scene.render.filepath = pos_path
        bpy.ops.render.render(write_still=True)
        pos_frame = read_image_to_numpy(pos_path, args.tile_size, args.tile_size)

        # Sub-pass 2B: Neg
        for lobj, is_pos in lights.values():
            lobj.hide_render = is_pos
        neg_path = os.path.join(render_tmp, f"neg_{f:03d}.png")
        scene.render.filepath = neg_path
        bpy.ops.render.render(write_still=True)
        neg_frame = read_image_to_numpy(neg_path, args.tile_size, args.tile_size)

        dx = pos_frame[:, :, 0] - neg_frame[:, :, 0]
        dy = pos_frame[:, :, 1] - neg_frame[:, :, 1]
        dz = np.maximum(
            pos_frame[:, :, 2] - neg_frame[:, :, 2],
            0.15 * np.maximum(pos_frame[:, :, 2], neg_frame[:, :, 2]),
        )

        mag = np.sqrt(dx**2 + dy**2 + dz**2)
        valid_mask = (mag > 1e-4) & (col_frame[:, :, 3] > 0.005)

        nx = np.zeros_like(dx)
        ny = np.zeros_like(dy)
        nz = np.ones_like(dz)

        nx[valid_mask] = dx[valid_mask] / mag[valid_mask]
        ny[valid_mask] = dy[valid_mask] / mag[valid_mask]
        nz[valid_mask] = dz[valid_mask] / mag[valid_mask]

        norm_r = nx * 0.5 + 0.5
        norm_g = ny * 0.5 + 0.5
        norm_b = nz * 0.5 + 0.5

        norm_r[~valid_mask] = 0.5
        norm_g[~valid_mask] = 0.5
        norm_b[~valid_mask] = 1.0

        normal_tile = np.stack([norm_r, norm_g, norm_b, col_frame[:, :, 3]], axis=-1)
        atlas_normal[y_start:y_end, x_start:x_end] = normal_tile

        if f % 8 == 0 or f == args.frames:
            print(f"Progress: frame {f:02d}/{args.frames:02d} rendered and packed.")

    out_color = os.path.join(out_dir, "atlas_color_alpha.png")
    out_normal = os.path.join(out_dir, "atlas_normal.png")

    print(f"Writing final PNG atlases...")
    write_numpy_to_image(atlas_color, out_color)
    write_numpy_to_image(atlas_normal, out_normal)

    shutil.rmtree(tmp_dir, ignore_errors=True)

    print(f"Exported: {out_color}")
    print(f"Exported: {out_normal}")
    print("Done.")


if __name__ == "__main__":
    main()
