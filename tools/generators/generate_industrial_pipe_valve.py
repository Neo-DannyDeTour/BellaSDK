#!/usr/bin/env python3
"""
BellaSDK Industrial Pipe Valve Generator.
Builds low-poly 2-part articulated valve (Valve wheel + valve_base flange)
and compiles Godot 4 ORM PBR textures (Albedo, Normal, ORM).
"""

import math
import os
import subprocess
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = REPO_ROOT / "assets" / "props" / "industrial_pipe_valve"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def generate_valve_textures(output_dir: Path) -> dict[str, Path]:
    """Generates 2048x2048 Albedo, Normal, and Godot ORM textures."""
    size = 2048
    cx, cy = size // 2, size // 2
    rng = np.random.default_rng(42)

    # Base texture layout:
    # Quadrant Top-Left (0..1024, 0..1024): Red Handwheel rim + spokes
    # Quadrant Top-Right (1024..2048, 0..1024): Flange base & bolts
    # Bottom Half (0..2048, 1024..2048): Stem pipe, brass hex nut, axle details

    # 1. Albedo
    albedo = np.zeros((size, size, 3), dtype=np.uint8)

    # Cast iron background noise (for flange and unpainted parts)
    iron_base = np.array([55, 52, 48], dtype=np.float32)
    iron_noise = rng.normal(0.0, 6.0, (size, size, 3))
    albedo[:, :] = np.clip(iron_base + iron_noise, 0, 255).astype(np.uint8)

    pil_albedo = Image.fromarray(albedo, mode="RGB")
    draw = ImageDraw.Draw(pil_albedo)

    # Red industrial paint for Wheel (Left half)
    red_paint = (186, 36, 36)
    # Wheel Outer Ring (UV space: center (512, 512), radius 420)
    wc_x, wc_y = 512, 512
    draw.ellipse([wc_x - 420, wc_y - 420, wc_x + 420, wc_y + 420], outline=red_paint, width=70)
    # Wheel Hub
    draw.ellipse([wc_x - 120, wc_y - 120, wc_x + 120, wc_y + 120], fill=red_paint)
    # 4 Spokes
    for angle_deg in (0, 90, 180, 270):
        rad = math.radians(angle_deg)
        x2 = wc_x + int(400 * math.cos(rad))
        y2 = wc_y + int(400 * math.sin(rad))
        draw.line([wc_x, wc_y, x2, y2], fill=red_paint, width=44)

    # Add edge wear & paint chips to wheel (bare dark steel exposed on edges)
    arr_albedo = np.array(pil_albedo, dtype=np.float32)
    chip_noise = rng.normal(0.0, 1.0, (size, size))
    chip_mask = (chip_noise > 1.85) & (arr_albedo[..., 0] > 140)
    arr_albedo[chip_mask] = np.array([42, 40, 38], dtype=np.float32)

    # Brass Center Hex Nut (Center (512, 512))
    hex_r = 75
    hex_pts = [
        (wc_x + int(hex_r * math.cos(math.radians(a))), wc_y + int(hex_r * math.sin(math.radians(a))))
        for a in range(0, 360, 60)
    ]
    pil_albedo = Image.fromarray(arr_albedo.astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(pil_albedo)
    draw.polygon(hex_pts, fill=(200, 168, 75))  # Machined brass

    # Center axle shaft hole
    draw.ellipse([wc_x - 30, wc_y - 30, wc_x + 30, wc_y + 30], fill=(25, 25, 25))

    # Flange Base (Right half: Center (1536, 512))
    fc_x, fc_y = 1536, 512
    draw.ellipse([fc_x - 400, fc_y - 400, fc_x + 400, fc_y + 400], fill=(70, 68, 65), outline=(45, 42, 40), width=30)
    draw.ellipse([fc_x - 180, fc_y - 180, fc_x + 180, fc_y + 180], fill=(85, 82, 78))

    # 6 Hex bolts on perimeter
    for a in range(0, 360, 60):
        rad = math.radians(a)
        bx = fc_x + int(320 * math.cos(rad))
        by = fc_y + int(320 * math.sin(rad))
        bolt_pts = [
            (bx + int(32 * math.cos(math.radians(ba))), by + int(32 * math.sin(math.radians(ba))))
            for ba in range(0, 360, 60)
        ]
        draw.polygon(bolt_pts, fill=(95, 92, 88), outline=(30, 28, 26))

    albedo_path = output_dir / "industrial_pipe_valve_albedo.png"
    pil_albedo.save(albedo_path, format="PNG", optimize=True)

    # 2. Normal Map (+Y OpenGL)
    # Generate height map for relief
    height = np.zeros((size, size), dtype=np.float32)
    # Wheel ring raised
    dist_wheel = np.sqrt((np.arange(size)[:, None] - wc_y) ** 2 + (np.arange(size)[None, :] - wc_x) ** 2)
    wheel_ring = (dist_wheel >= 350) & (dist_wheel <= 420)
    height[wheel_ring] = 0.75
    height[dist_wheel < 120] = 0.85
    # Flange raised
    dist_flange = np.sqrt((np.arange(size)[:, None] - fc_y) ** 2 + (np.arange(size)[None, :] - fc_x) ** 2)
    height[dist_flange <= 400] = 0.50
    height[dist_flange <= 180] = 0.70

    # Sobel / gradient
    h_smooth = Image.fromarray((height * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius=3))
    h_arr = np.array(h_smooth, dtype=np.float32) / 255.0
    gy, gx = np.gradient(h_arr)
    dx = gx * 14.0
    dy = gy * 14.0
    dz = np.ones_like(height)

    norm = np.sqrt(dx**2 + dy**2 + dz**2)
    nx = dx / norm
    ny = -dy / norm  # Invert for OpenGL Y-up
    nz = dz / norm

    norm_rgb = np.zeros((size, size, 3), dtype=np.uint8)
    norm_rgb[..., 0] = np.clip((nx * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    norm_rgb[..., 1] = np.clip((ny * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    norm_rgb[..., 2] = np.clip((nz * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    normal_img = Image.fromarray(norm_rgb, mode="RGB")
    normal_path = output_dir / "industrial_pipe_valve_normal.png"
    normal_img.save(normal_path, format="PNG", optimize=True)

    # 3. Godot ORM Map (R: AO, G: Roughness, B: Metallic)
    # Red: AO
    ao = np.full((size, size), 255, dtype=np.uint8)
    ao[dist_wheel <= 140] = 160  # Hub cavity
    ao[(dist_flange >= 160) & (dist_flange <= 200)] = 140  # Flange step

    # Green: Roughness
    rough = np.full((size, size), 180, dtype=np.uint8)  # Cast iron: rough 0.70
    rough[arr_albedo[..., 0] > 140] = 115  # Red paint: satin 0.45
    rough[chip_mask] = 85                  # Chipped steel: 0.33
    rough[dist_wheel <= 75] = 80           # Brass nut: smooth 0.31

    # Blue: Metallic
    metal = np.zeros((size, size), dtype=np.uint8)  # Red paint: 0.0 dielectric
    metal[chip_mask] = 220                          # Bare steel: 0.86
    metal[dist_flange <= 400] = 210                 # Cast iron flange: 0.82
    metal[dist_wheel <= 75] = 230                   # Brass nut: 0.90
    metal[albedo[..., 0] < 60] = 210                # Unpainted cast iron

    orm_img = Image.merge("RGB", (
        Image.fromarray(ao, mode="L"),
        Image.fromarray(rough, mode="L"),
        Image.fromarray(metal, mode="L")
    ))
    orm_path = output_dir / "industrial_pipe_valve_orm.png"
    orm_img.save(orm_path, format="PNG", optimize=True)

    print(f"Textures generated:\n  - {albedo_path}\n  - {normal_path}\n  - {orm_path}")
    return {"albedo": albedo_path, "normal": normal_path, "orm": orm_path}


def generate_blender_valve_mesh(output_glb: Path, tex_paths: dict[str, Path]) -> None:
    """Builds 2-part articulated valve (Valve wheel + valve_base flange) in Blender."""
    base_glb = output_glb.parent / "industrial_pipe_valve_base.glb"
    wheel_glb = output_glb.parent / "industrial_pipe_valve_wheel.glb"

    blender_script = f"""
import bpy
import math

bpy.ops.wm.read_factory_settings(use_empty=True)

# 1. valve_base (flange + pipe stem + perimeter bolts)
bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.035, vertices=32, location=(0.0, 0.0, 0.0175))
flange = bpy.context.active_object

bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=0.22, vertices=16, location=(0.0, 0.0, 0.11))
flange.select_set(True)
bpy.context.view_layer.objects.active = flange
bpy.ops.object.join()

# 6 Perimeter bolts
for a in range(0, 360, 60):
    rad = math.radians(a)
    bx = 0.17 * math.cos(rad)
    by = 0.17 * math.sin(rad)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.016, depth=0.015, vertices=6, location=(bx, by, 0.04))
    flange.select_set(True)
    bpy.context.view_layer.objects.active = flange
    bpy.ops.object.join()

flange.name = "valve_base"

# 2. Valve (Handwheel: rim + hub + hex nut + 4 spokes)
bpy.ops.mesh.primitive_torus_add(major_radius=0.25, minor_radius=0.018, major_segments=32, minor_segments=8, location=(0.0, 0.0, 0.0))
wheel = bpy.context.active_object

bpy.ops.mesh.primitive_cylinder_add(radius=0.052, depth=0.04, vertices=16, location=(0.0, 0.0, 0.0))
wheel.select_set(True)
bpy.context.view_layer.objects.active = wheel
bpy.ops.object.join()

bpy.ops.mesh.primitive_cylinder_add(radius=0.034, depth=0.024, vertices=6, location=(0.0, 0.0, 0.02))
wheel.select_set(True)
bpy.context.view_layer.objects.active = wheel
bpy.ops.object.join()

# 4 Spokes (2 crossed bars)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
sp1 = bpy.context.active_object
sp1.scale = (0.48, 0.022, 0.020)
bpy.ops.object.transform_apply(scale=True)
wheel.select_set(True)
bpy.context.view_layer.objects.active = wheel
bpy.ops.object.join()

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
sp2 = bpy.context.active_object
sp2.scale = (0.022, 0.48, 0.020)
bpy.ops.object.transform_apply(scale=True)
wheel.select_set(True)
bpy.context.view_layer.objects.active = wheel
bpy.ops.object.join()

wheel.name = "Valve"
wheel.location = (0.0, 0.0, 0.24)

# UV Unwrapping
for obj in [flange, wheel]:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)

# Material assignment
mat = bpy.data.materials.new(name="M_IndustrialPipeValve")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
tex_albedo = mat.node_tree.nodes.new("ShaderNodeTexImage")
tex_albedo.image = bpy.data.images.load(r"{tex_paths['albedo']}")
mat.node_tree.links.new(tex_albedo.outputs["Color"], bsdf.inputs["Base Color"])

flange.data.materials.append(mat)
wheel.data.materials.append(mat)

# Export Combined GLB
flange.select_set(True)
wheel.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=r"{output_glb}",
    export_format='GLB',
    use_selection=True,
    export_apply=False,
    export_yup=True
)

# Export individual parts for modular Godot scene instancing
wheel.select_set(False)
flange.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=r"{base_glb}",
    export_format='GLB',
    use_selection=True,
    export_apply=False,
    export_yup=True
)

flange.select_set(False)
wheel.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=r"{wheel_glb}",
    export_format='GLB',
    use_selection=True,
    export_apply=False,
    export_yup=True
)
print("Exported industrial_pipe_valve GLBs successfully!")
"""

    script_path = output_glb.parent / "blender_valve_build.py"
    with open(script_path, "w", encoding="utf-8") as f:
        f.write(blender_script)

    cmd = ["/snap/bin/blender", "-b", "--python", str(script_path)]
    ret = subprocess.run(cmd, capture_output=True, text=True)
    if ret.returncode != 0:
        print("Blender STDERR:\n", ret.stderr, file=sys.stderr)
        raise RuntimeError(f"Blender build failed with code {ret.returncode}")
    print(ret.stdout)
    if script_path.exists():
        script_path.unlink()


def generate_godot_material(output_dir: Path) -> Path:
    """Builds Godot 4 ORMMaterial3D resource."""
    content = """[gd_resource type="ORMMaterial3D" load_steps=4 format=3]

[ext_resource type="Texture2D" path="res://assets/props/industrial_pipe_valve/industrial_pipe_valve_albedo.png" id="1_albedo"]
[ext_resource type="Texture2D" path="res://assets/props/industrial_pipe_valve/industrial_pipe_valve_orm.png" id="2_orm"]
[ext_resource type="Texture2D" path="res://assets/props/industrial_pipe_valve/industrial_pipe_valve_normal.png" id="3_normal"]

[resource]
resource_name = "M_IndustrialPipeValve"
albedo_texture = ExtResource("1_albedo")
orm_texture = ExtResource("2_orm")
normal_enabled = true
normal_texture = ExtResource("3_normal")
roughness = 1.0
metallic = 1.0
"""
    tres_path = output_dir / "industrial_pipe_valve.tres"
    with open(tres_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Generated Godot ORMMaterial3D: {tres_path}")
    return tres_path


def main() -> int:
    print(f"Generating Industrial Pipe Valve in: {OUTPUT_DIR}")
    tex_paths = generate_valve_textures(OUTPUT_DIR)
    glb_path = OUTPUT_DIR / "industrial_pipe_valve.glb"
    generate_blender_valve_mesh(glb_path, tex_paths)
    generate_godot_material(OUTPUT_DIR)
    print("\n[SUCCESS] industrial_pipe_valve asset ready!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
