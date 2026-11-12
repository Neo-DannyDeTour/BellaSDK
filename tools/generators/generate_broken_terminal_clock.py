#!/usr/bin/env python3
"""
BellaSDK Broken Terminal Clock Generator.
Generates game-ready low-poly 3D clock with separate articulated hands (HourHand, MinuteHand)
and complete Godot 4 PBR textures (Albedo, Normal, ORM).
"""

import math
import os
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = REPO_ROOT / "assets" / "models" / "broken_terminal_clock"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

SERIF_FONT_PATH = "/usr/share/fonts/truetype/freefont/FreeSerifBold.ttf"
if not os.path.exists(SERIF_FONT_PATH):
    SERIF_FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def generate_clock_textures(output_dir: Path) -> dict[str, Path]:
    """Generates 2048x2048 Albedo, Normal, and Godot ORM textures."""
    size = 2048
    cx, cy = size // 2, size // 2
    r_outer = 980
    r_rim = 840
    r_dial = 820
    r_track = 760
    r_num = 640

    rng = np.random.default_rng(1912)

    # 1. Base Albedo
    albedo = Image.new("RGBA", (size, size), (28, 24, 20, 255))
    draw = ImageDraw.Draw(albedo)

    # Draw outer bronze/iron rim
    for r in range(r_outer, r_rim, -2):
        shade = int(32 + 18 * math.sin(r * 0.08) + rng.integers(-3, 4))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(shade + 8, shade + 4, shade, 255), width=3)

    # Dial face: aged ivory/parchment with vignette and micro-noise
    arr = np.array(albedo, dtype=np.float32)
    y_idx, x_idx = np.ogrid[:size, :size]
    dist_from_c = np.sqrt((x_idx - cx) ** 2 + (y_idx - cy) ** 2)

    dial_mask = dist_from_c <= r_dial
    parchment_base = np.array([215, 202, 172], dtype=np.float32)
    vignette = np.clip((dist_from_c / r_dial) ** 2.5 * 0.45, 0.0, 0.7)
    noise = rng.normal(0.0, 4.0, (size, size, 1))

    for c in range(3):
        color_val = (parchment_base[c] * (1.0 - vignette) + 60.0 * vignette) + noise[:, :, 0]
        arr[:, :, c] = np.where(dial_mask, np.clip(color_val, 0, 255), arr[:, :, c])

    albedo = Image.fromarray(arr.astype(np.uint8), mode="RGBA")
    draw = ImageDraw.Draw(albedo)

    # Dial track borders
    draw.ellipse([cx - r_dial, cy - r_dial, cx + r_dial, cy + r_dial], outline=(45, 38, 30, 255), width=6)
    draw.ellipse([cx - r_track, cy - r_track, cx + r_track, cy + r_track], outline=(55, 45, 35, 255), width=4)
    r_inner_track = r_track - 50
    draw.ellipse([cx - r_inner_track, cy - r_inner_track, cx + r_inner_track, cy + r_inner_track], outline=(55, 45, 35, 255), width=3)

    # 60 Minute ticks & 12 hour markers
    for m in range(60):
        angle = math.radians(m * 6 - 90)
        is_hour = (m % 5 == 0)
        t_len = 40 if is_hour else 18
        t_width = 7 if is_hour else 3

        x1 = cx + int((r_track - 5) * math.cos(angle))
        y1 = cy + int((r_track - 5) * math.sin(angle))
        x2 = cx + int((r_track - 5 - t_len) * math.cos(angle))
        y2 = cy + int((r_track - 5 - t_len) * math.sin(angle))
        draw.line([x1, y1, x2, y2], fill=(35, 28, 22, 255), width=t_width)

        # Hour diamond accent
        if is_hour:
            mid_r = r_track - 5 - t_len - 14
            dx = cx + int(mid_r * math.cos(angle))
            dy = cy + int(mid_r * math.sin(angle))
            draw.polygon([
                (dx, dy - 6), (dx + 6, dy), (dx, dy + 6), (dx - 6, dy)
            ], fill=(40, 32, 24, 255))

    # Roman numerals (I through XII)
    numerals = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
    try:
        font = ImageFont.truetype(SERIF_FONT_PATH, 110)
    except Exception:
        font = ImageFont.load_default()

    for idx, rom in enumerate(numerals):
        angle = math.radians(idx * 30 - 90)
        nx = cx + int(r_num * math.cos(angle))
        ny = cy + int(r_num * math.sin(angle))

        bbox = draw.textbbox((0, 0), rom, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]

        # Draw numeral with slight ink bleed
        draw.text((nx - tw // 2, ny - th // 2), rom, fill=(30, 24, 18, 240), font=font)

    # Center brass/bronze axle ring
    draw.ellipse([cx - 45, cy - 45, cx + 45, cy + 45], fill=(70, 55, 35, 255), outline=(35, 25, 15, 255), width=5)
    draw.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=(25, 18, 12, 255))

    # Spiderweb glass fracture (Upper-Left damage)
    impact_x, impact_y = cx - 320, cy - 380
    crack_draw = ImageDraw.Draw(albedo)
    fracture_branches = [
        [(impact_x, impact_y), (impact_x - 120, impact_y - 210), (impact_x - 190, impact_y - 340)],
        [(impact_x, impact_y), (impact_x + 90, impact_y - 180), (impact_x + 220, impact_y - 280), (impact_x + 360, impact_y - 320)],
        [(impact_x, impact_y), (impact_x + 180, impact_y - 60), (impact_x + 320, impact_y + 40)],
        [(impact_x, impact_y), (impact_x + 110, impact_y + 160), (cx + 40, cy + 30)],
        [(impact_x, impact_y), (impact_x - 140, impact_y + 80), (impact_x - 280, impact_y + 190)],
        [(impact_x, impact_y), (impact_x - 210, impact_y - 60), (impact_x - 380, impact_y - 90)],
    ]
    for branch in fracture_branches:
        for i in range(len(branch) - 1):
            p1, p2 = branch[i], branch[i + 1]
            # Subtle glass highlight line + dark refraction shadow
            crack_draw.line([p1[0] + 1, p1[1] + 1, p2[0] + 1, p2[1] + 1], fill=(40, 30, 20, 180), width=3)
            crack_draw.line([p1, p2], fill=(245, 248, 252, 220), width=2)

    # Concentric stress rings around impact
    for ring_r in (60, 130, 210, 300):
        start_a = rng.uniform(0, 360)
        end_a = start_a + rng.uniform(70, 180)
        crack_draw.arc([impact_x - ring_r, impact_y - ring_r, impact_x + ring_r, impact_y + ring_r],
                       start=start_a, end=end_a, fill=(235, 240, 245, 170), width=2)

    # Save Albedo
    albedo_path = output_dir / "broken_terminal_clock_albedo.png"
    albedo.convert("RGB").save(albedo_path, format="PNG", optimize=True)

    # 2. Normal Map (+Y OpenGL format)
    # Height derivation: rim raised, dial recessed, bezel bevel, cracks raised
    height = np.zeros((size, size), dtype=np.float32)
    # Outer rim bevel
    rim_mask = (dist_from_c >= r_rim) & (dist_from_c <= r_outer)
    height[rim_mask] = 0.85 - (np.abs(dist_from_c[rim_mask] - (r_rim + r_outer) * 0.5) / 100.0) * 0.4
    # Dial recessed
    dial_h = 0.35 + (dist_from_c / r_dial) * 0.05
    height[dial_mask] = dial_h[dial_mask]
    # Axle raised
    axle_mask = dist_from_c <= 45
    height[axle_mask] = 0.75 - (dist_from_c[axle_mask] / 45.0) * 0.25

    # Compute Normal Map using numpy gradient + PIL GaussianBlur
    h_img = Image.fromarray((height * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius=2))
    h_arr = np.array(h_img, dtype=np.float32) / 255.0
    gy, gx = np.gradient(h_arr)
    dx = gx * 18.0
    dy = gy * 18.0
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
    normal_path = output_dir / "broken_terminal_clock_normal.png"
    normal_img.save(normal_path, format="PNG", optimize=True)

    # 3. Godot ORM Map (R: AO, G: Roughness, B: Metallic)
    # Red: AO
    ao = np.full((size, size), 255, dtype=np.uint8)
    # Inner rim contact shadow
    inner_shadow = (dist_from_c >= (r_dial - 40)) & (dist_from_c <= r_dial)
    ao[inner_shadow] = np.clip(160 + (r_dial - dist_from_c[inner_shadow]) * 2.2, 100, 255).astype(np.uint8)
    ao[dist_from_c <= 55] = 140

    # Green: Roughness
    rough = np.full((size, size), 160, dtype=np.uint8)  # Default casing roughness ~0.62
    # Glass dial: shiny 0.2
    rough[dial_mask] = 55
    # Cracks: rougher 0.8
    rough_img = Image.fromarray(rough, mode="L")
    rough_draw = ImageDraw.Draw(rough_img)
    for branch in fracture_branches:
        for i in range(len(branch) - 1):
            rough_draw.line([branch[i], branch[i + 1]], fill=220, width=8)
    for ring_r in (60, 130, 210, 300):
        rough_draw.ellipse([impact_x - ring_r, impact_y - ring_r, impact_x + ring_r, impact_y + ring_r], outline=210, width=6)
    rough_final = np.array(rough_img)

    # Blue: Metallic
    metal = np.zeros((size, size), dtype=np.uint8)  # Dial is dielectric 0.0
    metal[~dial_mask] = int(0.85 * 255)  # Outer casing is bronze metal
    metal[axle_mask] = int(0.9 * 255)    # Center brass bolt

    orm_img = Image.merge("RGB", (
        Image.fromarray(ao, mode="L"),
        Image.fromarray(rough_final, mode="L"),
        Image.fromarray(metal, mode="L"),
    ))
    orm_path = output_dir / "broken_terminal_clock_orm.png"
    orm_img.save(orm_path, format="PNG", optimize=True)

    print(f"Generated textures:\n  - {albedo_path}\n  - {normal_path}\n  - {orm_path}")
    return {"albedo": albedo_path, "normal": normal_path, "orm": orm_path}


def generate_blender_clock_mesh(output_glb: Path, tex_paths: dict[str, Path]) -> None:
    """Builds low-poly articulated clock (ClockBody, HourHand, MinuteHand) in Blender."""
    blender_script = f"""
import bpy
import bmesh
import math
from mathutils import Vector, Euler

bpy.ops.wm.read_factory_settings(use_empty=True)

# 1. ClockBody
bpy.ops.mesh.primitive_cylinder_add(radius=0.50, depth=0.06, vertices=48, location=(0.0, 0.0, 0.03))
body = bpy.context.active_object
body.name = "ClockBody"
body.data.name = "ClockBodyMesh"

bev = body.modifiers.new("Bevel", "BEVEL")
bev.width = 0.008
bev.segments = 2
bev.limit_method = "ANGLE"
bpy.ops.object.modifier_apply(modifier=bev.name)

# Center axle pin
bpy.ops.mesh.primitive_cylinder_add(radius=0.025, depth=0.015, vertices=24, location=(0.0, 0.0, 0.065))
pin = bpy.context.active_object
pin.name = "CenterAxle"
bpy.context.view_layer.objects.active = body
pin.select_set(True)
body.select_set(True)
bpy.ops.object.join()

# Smart UV Project
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.02)
bpy.ops.object.mode_set(mode='OBJECT')

# Align front face UVs to 0..1 circle
mesh = body.data
uv_layer = mesh.uv_layers.active.data
for poly in mesh.polygons:
    if poly.normal.z > 0.5:
        for loop_idx in poly.loop_indices:
            v_idx = mesh.loops[loop_idx].vertex_index
            vx, vy, _ = mesh.vertices[v_idx].co
            uv_layer[loop_idx].uv = (vx + 0.5, vy + 0.5)

# 2. HourHand: Tapered spade hand (11 o'clock: angle ~ 30 deg)
# Modeled via bmesh with diamond tip
hour_mesh = bpy.data.meshes.new("HourHandMesh")
hour_obj = bpy.data.objects.new("HourHand", hour_mesh)
bpy.context.collection.objects.link(hour_obj)

bm = bmesh.new()
# Bottom tail
v0 = bm.verts.new((-0.016, -0.045, 0.0))
v1 = bm.verts.new((0.016, -0.045, 0.0))
# Shaft
v2 = bm.verts.new((0.012, 0.130, 0.0))
v3 = bm.verts.new((-0.012, 0.130, 0.0))
# Diamond head
v4 = bm.verts.new((0.035, 0.200, 0.0))
v5 = bm.verts.new((0.0, 0.290, 0.0))
v6 = bm.verts.new((-0.035, 0.200, 0.0))

bm.faces.new([v0, v1, v2, v3])
bm.faces.new([v3, v2, v4, v5, v6])
bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
for v in bm.verts:
    if v.co.z > 0.0:
        v.co.z = 0.005
bm.to_mesh(hour_mesh)
bm.free()

# Unwrap hand UVs to dark metal region (bottom edge of texture)
uv_h = hour_obj.data.uv_layers.new(name="UVMap").data
for loop in hour_obj.data.loops:
    uv_h[loop.index].uv = (0.5, 0.05)

hour_obj.location = (0.0, 0.0, 0.066)
hour_obj.rotation_euler = Euler((0.0, 0.0, math.radians(30.0)), 'XYZ')
hour_obj.parent = body

# 3. MinuteHand: Slender diamond hand (53 min: angle ~ 42 deg)
min_mesh = bpy.data.meshes.new("MinuteHandMesh")
min_obj = bpy.data.objects.new("MinuteHand", min_mesh)
bpy.context.collection.objects.link(min_obj)

bm = bmesh.new()
m0 = bm.verts.new((-0.010, -0.055, 0.0))
m1 = bm.verts.new((0.010, -0.055, 0.0))
m2 = bm.verts.new((0.007, 0.240, 0.0))
m3 = bm.verts.new((-0.007, 0.240, 0.0))
m4 = bm.verts.new((0.020, 0.330, 0.0))
m5 = bm.verts.new((0.0, 0.420, 0.0))
m6 = bm.verts.new((-0.020, 0.330, 0.0))

bm.faces.new([m0, m1, m2, m3])
bm.faces.new([m3, m2, m4, m5, m6])
bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
for v in bm.verts:
    if v.co.z > 0.0:
        v.co.z = 0.005
bm.to_mesh(min_mesh)
bm.free()

uv_m = min_obj.data.uv_layers.new(name="UVMap").data
for loop in min_obj.data.loops:
    uv_m[loop.index].uv = (0.5, 0.05)

min_obj.location = (0.0, 0.0, 0.072)
min_obj.rotation_euler = Euler((0.0, 0.0, math.radians(42.0)), 'XYZ')
min_obj.parent = body

# Material Setup
mat = bpy.data.materials.new(name="M_BrokenTerminalClock")
mat.use_nodes = True
nodes = mat.node_tree.nodes
links = mat.node_tree.links
bsdf = nodes.get("Principled BSDF")

tex_albedo = nodes.new("ShaderNodeTexImage")
tex_albedo.image = bpy.data.images.load(r"{tex_paths['albedo']}")
links.new(tex_albedo.outputs["Color"], bsdf.inputs["Base Color"])

body.data.materials.append(mat)
hour_obj.data.materials.append(mat)
min_obj.data.materials.append(mat)

# Select all objects for export
for o in [body, hour_obj, min_obj]:
    o.select_set(True)

bpy.ops.export_scene.gltf(
    filepath=r"{output_glb}",
    export_format='GLB',
    use_selection=True,
    export_apply=False,
    export_yup=True
)
print("Successfully exported GLB to:", r"{output_glb}")
"""

    script_path = output_glb.parent / "blender_build.py"
    with open(script_path, "w", encoding="utf-8") as f:
        f.write(blender_script)

    import subprocess
    cmd = ["/snap/bin/blender", "-b", "--python", str(script_path)]
    ret = subprocess.run(cmd, capture_output=True, text=True)
    if ret.returncode != 0:
        print("Blender STDERR:\n", ret.stderr, file=sys.stderr)
        raise RuntimeError(f"Blender build failed with return code {ret.returncode}")
    print(ret.stdout)
    if script_path.exists():
        script_path.unlink()


def generate_godot_material(output_dir: Path) -> Path:
    """Creates Godot 4 ORMMaterial3D (.tres) matching 60 FPS standard."""
    tres_content = """[gd_resource type="ORMMaterial3D" load_steps=4 format=3]

[ext_resource type="Texture2D" path="res://assets/models/broken_terminal_clock/broken_terminal_clock_albedo.png" id="1_albedo"]
[ext_resource type="Texture2D" path="res://assets/models/broken_terminal_clock/broken_terminal_clock_orm.png" id="2_orm"]
[ext_resource type="Texture2D" path="res://assets/models/broken_terminal_clock/broken_terminal_clock_normal.png" id="3_normal"]

[resource]
resource_name = "M_BrokenTerminalClock"
albedo_texture = ExtResource("1_albedo")
orm_texture = ExtResource("2_orm")
normal_enabled = true
normal_texture = ExtResource("3_normal")
roughness = 1.0
metallic = 1.0
"""
    tres_path = output_dir / "broken_terminal_clock.tres"
    with open(tres_path, "w", encoding="utf-8") as f:
        f.write(tres_content)
    print(f"Generated Godot ORMMaterial3D: {tres_path}")
    return tres_path


def main() -> int:
    print(f"Compiling Broken Terminal Clock in: {OUTPUT_DIR}")
    tex_paths = generate_clock_textures(OUTPUT_DIR)
    glb_path = OUTPUT_DIR / "broken_terminal_clock.glb"
    generate_blender_clock_mesh(glb_path, tex_paths)
    generate_godot_material(OUTPUT_DIR)

    # Clean up old sci_fi_terminal to prevent scene confusion
    old_dir = REPO_ROOT / "assets" / "models" / "sci_fi_terminal"
    if old_dir.exists():
        import shutil
        shutil.rmtree(old_dir)
        print(f"Removed deprecated directory: {old_dir}")

    print("\n[COMPLETE] broken_terminal_clock ready for Godot 4!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
