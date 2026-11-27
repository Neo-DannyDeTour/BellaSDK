"""Bake 4x4 metaball blood burst flipbook atlas via Blender and PIL."""

import math
import os
import random
import shutil
import subprocess
import sys


def run_blender_scene_render(temp_dir: str) -> None:
	"""Executed inside Blender: animate metaball elements and render frames."""
	import bpy

	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.frame_start = 1
	scene.frame_end = 16
	scene.render.fps = 16

	# Render configuration
	scene.render.engine = "BLENDER_EEVEE"
	scene.render.resolution_x = 256
	scene.render.resolution_y = 256
	scene.render.resolution_percentage = 100
	scene.render.film_transparent = True
	scene.render.image_settings.file_format = "PNG"
	scene.render.image_settings.color_mode = "RGBA"
	scene.render.image_settings.color_depth = "8"

	# Material (Acid Green Liquid)
	mat = bpy.data.materials.new(name="GreenBloodMat")
	nodes = mat.node_tree.nodes
	nodes.clear()

	bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
	bsdf.inputs["Base Color"].default_value = (0.1, 0.8, 0.2, 1.0)
	bsdf.inputs["Roughness"].default_value = 0.1
	bsdf.inputs["IOR"].default_value = 1.333
	mat_out = nodes.new(type="ShaderNodeOutputMaterial")
	mat.node_tree.links.new(bsdf.outputs["BSDF"], mat_out.inputs["Surface"])

	# Create single Metaball object
	bpy.ops.object.metaball_add(type="BALL", location=(0, 0, 0))
	mb = bpy.context.active_object
	mb.name = "Mball"
	mb.data.resolution = 0.08
	mb.data.render_resolution = 0.08
	mb.data.materials.append(mat)

	# Core central metaball element
	core = mb.data.elements[0]
	core.radius = 0.35
	core.keyframe_insert(data_path="radius", frame=1)
	core.radius = 0.2
	core.keyframe_insert(data_path="radius", frame=8)
	core.radius = 0.04
	core.keyframe_insert(data_path="radius", frame=16)

	# 12 Satellite globules bursting radially
	rng = random.Random(42)
	for i in range(12):
		angle = (i / 12.0) * 2.0 * math.pi + rng.uniform(-0.15, 0.15)
		dist_speed = rng.uniform(0.75, 1.15)
		z_off = rng.uniform(-0.06, 0.06)
		rad = rng.uniform(0.12, 0.18)

		elem = mb.data.elements.new(type="BALL")

		# Frame 1: tight cluster
		d1 = 0.08
		elem.co = (math.cos(angle) * d1, math.sin(angle) * d1, z_off * 0.2)
		elem.radius = rad
		elem.keyframe_insert(data_path="co", frame=1)
		elem.keyframe_insert(data_path="radius", frame=1)

		# Frame 6: expanding outwards, liquid bridges
		d2 = dist_speed * 0.38
		elem.co = (math.cos(angle) * d2, math.sin(angle) * d2, z_off * 0.6)
		elem.radius = rad * 0.9
		elem.keyframe_insert(data_path="co", frame=6)
		elem.keyframe_insert(data_path="radius", frame=6)

		# Frame 11: detached droplets
		d3 = dist_speed * 0.72
		elem.co = (math.cos(angle) * d3, math.sin(angle) * d3, z_off)
		elem.radius = rad * 0.6
		elem.keyframe_insert(data_path="co", frame=11)
		elem.keyframe_insert(data_path="radius", frame=11)

		# Frame 16: dissipation
		d4 = dist_speed * 1.05
		elem.co = (math.cos(angle) * d4, math.sin(angle) * d4, z_off * 1.2)
		elem.radius = 0.01
		elem.keyframe_insert(data_path="co", frame=16)
		elem.keyframe_insert(data_path="radius", frame=16)

	# Lighting
	bpy.ops.object.light_add(type="SUN", location=(2.0, 2.0, 5.0))
	sun = bpy.context.active_object
	sun.data.energy = 4.0
	sun.rotation_euler = (math.radians(30), math.radians(20), 0)

	bpy.ops.object.light_add(type="POINT", location=(-2.0, -2.0, 3.0))
	fill = bpy.context.active_object
	fill.data.energy = 25.0

	# Camera: Top-down orthographic
	bpy.ops.object.camera_add(location=(0, 0, 5), rotation=(0, 0, 0))
	cam = bpy.context.active_object
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = 2.6
	scene.camera = cam

	# Render frames
	scene.render.filepath = os.path.join(temp_dir, "frame_")
	print(f"Blender: Rendering 16 frames to {temp_dir}...")
	bpy.ops.render.render(animation=True)
	print("Blender: Render finished.")


def main() -> None:
	# Running inside Blender
	if "bpy" in sys.modules:
		temp_dir = sys.argv[-1] if len(sys.argv) > 1 and sys.argv[-1] != "--" else "/tmp/blood_frames"
		os.makedirs(temp_dir, exist_ok=True)
		run_blender_scene_render(temp_dir)
		return

	# Running in standard Python
	from PIL import Image

	output_path = os.path.abspath("assets/vfx/green_blood_atlas.png")
	temp_dir = os.path.abspath("assets/vfx/.blood_frames_tmp")
	os.makedirs(temp_dir, exist_ok=True)

	script_file = os.path.abspath(__file__)
	cmd = [
		"/snap/bin/blender",
		"--background",
		"--python",
		script_file,
		"--",
		temp_dir,
	]
	print("Launching Blender headless render...")
	result = subprocess.run(cmd, check=True)
	if result.returncode != 0:
		raise RuntimeError(f"Blender failed with code {result.returncode}")

	print("Stitching 16 subframes into 4x4 atlas (1024x1024)...")
	atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
	for f in range(16):
		frame_path = os.path.join(temp_dir, f"frame_{f+1:04d}.png")
		if not os.path.exists(frame_path):
			raise FileNotFoundError(f"Missing frame {frame_path}")
		img = Image.open(frame_path)
		col = f % 4
		row = f // 4
		atlas.paste(img, (col * 256, row * 256))

	os.makedirs(os.path.dirname(output_path), exist_ok=True)
	atlas.save(output_path, "PNG")
	print(f"Atlas saved successfully: {output_path}")

	shutil.rmtree(temp_dir)
	print("Cleanup complete.")


if __name__ == "__main__":
	main()
