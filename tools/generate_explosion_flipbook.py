#!/usr/bin/env python3
"""Headless Blender Mantaflow explosion simulation bake and 8x8 flipbook generator.

Executes within Blender headless environment (`blender --background --python tools/generate_explosion_flipbook.py`):
1. Clears default scene.
2. Creates an inflow UV-sphere emitter with keyframed emission (frames 1-3 only).
3. Creates a cubic Mantaflow gas domain with resolution 128, reaction speed, and smoke dissolution.
4. Sets up Principled Volume shader with flame emission and density attributes.
5. Configures orthographic camera, lights, and transparent EEVEE renderer at 256x256.
6. Bakes simulation data for 64 frames via Mantaflow solver.
7. Renders 64 frames to intermediate temporary directory.
8. Assembles frames into 2048x2048 8x8 spritesheet (explosion_core_8x8.png).
9. Cleans up intermediate simulation cache and frame files.
10. Triggers headless Godot editor import to produce .import and .uid metadata.
"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def log(msg: str) -> None:
    """Print standard timestamped log message."""
    print(f"[FlipbookPipeline] {msg}", flush=True)


def parse_args() -> argparse.Namespace:
    """Parse CLI options passed to script or after '--' in Blender."""
    raw_args: list[str] = sys.argv
    if "--" in raw_args:
        raw_args = raw_args[raw_args.index("--") + 1 :]
    else:
        raw_args = []

    parser = argparse.ArgumentParser(
        description="Headless Blender Mantaflow explosion flipbook generator"
    )
    parser.add_argument(
        "--resolution",
        type=int,
        default=128,
        help="Mantaflow domain max resolution divisions (default: 128)",
    )
    parser.add_argument(
        "--frames",
        type=int,
        default=64,
        help="Number of animation frames to bake and render (default: 64)",
    )
    parser.add_argument(
        "--frame-size",
        type=int,
        default=256,
        help="Per-frame pixel width and height (default: 256)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="",
        help="Destination path for assembled spritesheet (default: assets/vfx/explosion/explosion_core_8x8.png)",
    )
    parser.add_argument(
        "--skip-import",
        action="store_true",
        help="Skip triggering godot --headless --editor --quit",
    )
    return parser.parse_args(raw_args)


def assemble_spritesheet(
    frames_dir: Path, output_path: Path, frame_count: int = 64, frame_size: int = 256
) -> None:
    """Assemble rendered individual PNG frames into an 8x8 spritesheet."""
    log(f"Assembling {frame_count} frames into spritesheet at {output_path}...")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    grid_cols = 8
    grid_rows = 8
    sheet_width = grid_cols * frame_size
    sheet_height = grid_rows * frame_size

    # Collect sorted frame paths
    frame_files: list[Path] = sorted(frames_dir.glob("frame_*.png"))
    if len(frame_files) < frame_count:
        raise RuntimeError(
            f"Expected {frame_count} frames in {frames_dir}, but found {len(frame_files)}"
        )
    target_frames = frame_files[:frame_count]

    assembled = False

    # Method 1: Try PIL in current Python process
    try:
        from PIL import Image  # type: ignore

        sheet = Image.new("RGBA", (sheet_width, sheet_height), (0, 0, 0, 0))
        for idx, frame_path in enumerate(target_frames):
            col = idx % grid_cols
            row = idx // grid_cols
            with Image.open(frame_path) as frame_img:
                sheet.paste(frame_img.convert("RGBA"), (col * frame_size, row * frame_size))
        sheet.save(str(output_path), format="PNG")
        assembled = True
        log("Spritesheet assembled successfully via embedded PIL.")
    except ImportError:
        log("Embedded PIL not available in Blender Python. Attempting system python3 with Pillow...")

    # Method 2: Call system python3 with Pillow
    if not assembled and shutil.which("python3"):
        py_code = """
import sys
from pathlib import Path
from PIL import Image

frames_dir = Path(sys.argv[1])
out_path = Path(sys.argv[2])
frame_count = int(sys.argv[3])
frame_size = int(sys.argv[4])
grid_cols = 8
grid_rows = 8

frame_files = sorted(frames_dir.glob("frame_*.png"))[:frame_count]
sheet = Image.new("RGBA", (grid_cols * frame_size, grid_rows * frame_size), (0, 0, 0, 0))

for idx, fpath in enumerate(frame_files):
    col = idx % grid_cols
    row = idx // grid_cols
    with Image.open(fpath) as img:
        sheet.paste(img.convert("RGBA"), (col * frame_size, row * frame_size))

out_path.parent.mkdir(parents=True, exist_ok=True)
sheet.save(str(out_path), format="PNG")
print("System Pillow assembly finished successfully.")
"""
        proc = subprocess.run(
            [
                "python3",
                "-c",
                py_code,
                str(frames_dir),
                str(output_path),
                str(frame_count),
                str(frame_size),
            ],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0:
            assembled = True
            log("Spritesheet assembled successfully via system python3 Pillow.")
        else:
            log(f"System python3 Pillow attempt failed: {proc.stderr}")

    # Method 3: Call ImageMagick montage
    if not assembled and shutil.which("montage"):
        log("Attempting assembly via ImageMagick montage...")
        cmd = [
            "montage",
            *[str(p) for p in target_frames],
            "-tile",
            f"{grid_cols}x{grid_rows}",
            "-geometry",
            f"{frame_size}x{frame_size}+0+0",
            "-background",
            "none",
            f"PNG32:{output_path}",
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode == 0:
            assembled = True
            log("Spritesheet assembled successfully via ImageMagick montage.")
        else:
            log(f"Montage execution failed: {proc.stderr}")

    if not assembled:
        raise RuntimeError("Failed to assemble spritesheet: neither Pillow nor montage succeeded.")

    if not output_path.exists() or output_path.stat().st_size == 0:
        raise RuntimeError(f"Assembled file at {output_path} is missing or empty.")


def trigger_godot_import(project_root: Path) -> None:
    """Run godot headless editor to generate .import and .uid files."""
    godot_bin = shutil.which("godot")
    if not godot_bin:
        log("WARNING: godot executable not found in PATH; skipping asset import step.")
        return

    log(f"Running '{godot_bin} --headless --editor --quit' in {project_root}...")
    try:
        proc = subprocess.run(
            [godot_bin, "--headless", "--editor", "--quit"],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            timeout=90,
        )
        if proc.returncode == 0:
            log("Godot headless import completed successfully.")
        else:
            log(f"Godot import returned code {proc.returncode}. Stderr: {proc.stderr[:300]}")
    except subprocess.TimeoutExpired:
        log("Godot editor headless import timed out after 90 seconds.")
    except Exception as exc:  # pylint: disable=broad-exception-caught
        log(f"Exception during Godot import: {exc}")


def run_pipeline() -> None:
    """Run full Blender Mantaflow bake, render, and flipbook assembly."""
    try:
        import bpy  # type: ignore # pylint: disable=import-error
    except ImportError as err:
        log("Error: bpy module not found. This script must be executed via 'blender --background --python'.")
        sys.exit(1)

    args = parse_args()
    project_root = Path(__file__).resolve().parent.parent

    if args.output:
        output_spritesheet = Path(args.output).resolve()
    else:
        output_spritesheet = project_root / "assets" / "vfx" / "explosion" / "explosion_core_8x8.png"

    log("=================================================================")
    log("Starting Blender Mantaflow Explosion Flipbook Generation Pipeline")
    log(f"Project root: {project_root}")
    log(f"Target spritesheet: {output_spritesheet}")
    log(f"Resolution divisions: {args.resolution}")
    log(f"Frames: {args.frames} (8x8 grid of {args.frame_size}x{args.frame_size})")
    log("=================================================================")

    temp_cache_dir = tempfile.mkdtemp(prefix="mantaflow_cache_")
    temp_frames_dir = tempfile.mkdtemp(prefix="mantaflow_frames_")
    log(f"Temporary cache dir:  {temp_cache_dir}")
    log(f"Temporary frames dir: {temp_frames_dir}")

    try:
        # 1. Reset scene to clean slate
        log("Step 1: Resetting factory settings to clean scene...")
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene

        # 2. Configure scene render settings
        log("Step 2: Configuring render settings (EEVEE, 256x256, transparent)...")
        available_engines = [
            item.identifier for item in scene.render.bl_rna.properties["engine"].enum_items
        ]
        if "BLENDER_EEVEE" in available_engines:
            scene.render.engine = "BLENDER_EEVEE"
        elif "CYCLES" in available_engines:
            scene.render.engine = "CYCLES"
        else:
            scene.render.engine = available_engines[0]
        log(f"Selected render engine: {scene.render.engine}")

        scene.render.film_transparent = True
        scene.render.resolution_x = args.frame_size
        scene.render.resolution_y = args.frame_size
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGBA"
        scene.render.image_settings.color_depth = "8"

        scene.frame_start = 1
        scene.frame_end = args.frames
        scene.frame_step = 1

        if hasattr(scene, "eevee"):
            try:
                scene.eevee.volumetric_tile_size = "4"
                scene.eevee.volumetric_samples = 64
            except (AttributeError, TypeError):
                pass

        # 3. Create Emitter (Sphere mesh, radius 0.4m at origin)
        log("Step 3: Creating Mantaflow flow emitter (radius 0.4m, inflow frames 1-3)...")
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.4, location=(0.0, 0.0, 0.0))
        emitter = bpy.context.active_object
        emitter.name = "ExplosionEmitter"
        emitter.hide_render = True

        em_mod = emitter.modifiers.new("Fluid", "FLUID")
        em_mod.fluid_type = "FLOW"
        em_flow = em_mod.flow_settings
        em_flow.flow_type = "BOTH"
        em_flow.flow_behavior = "INFLOW"
        em_flow.use_initial_velocity = True
        em_flow.velocity_normal = 8.0
        em_flow.velocity_random = 2.5
        em_flow.fuel_amount = 1.8
        em_flow.surface_distance = 1.0

        # Keyframe inflow: active on frames 1-3, off on frame 4+
        em_flow.use_inflow = True
        em_flow.keyframe_insert(data_path="use_inflow", frame=1)
        em_flow.keyframe_insert(data_path="use_inflow", frame=3)
        em_flow.use_inflow = False
        em_flow.keyframe_insert(data_path="use_inflow", frame=4)

        # 4. Create Mantaflow Domain (6m x 6m x 6m centered at (0, 0, 2.0))
        log(f"Step 4: Creating Mantaflow gas domain (6x6x6m, res {args.resolution})...")
        bpy.ops.mesh.primitive_cube_add(size=6.0, location=(0.0, 0.0, 2.0))
        domain = bpy.context.active_object
        domain.name = "ExplosionDomain"

        dom_mod = domain.modifiers.new("Fluid", "FLUID")
        dom_mod.fluid_type = "DOMAIN"
        dom_settings = dom_mod.domain_settings
        dom_settings.domain_type = "GAS"
        dom_settings.resolution_max = args.resolution
        dom_settings.time_scale = 1.3
        dom_settings.burning_rate = 0.65
        dom_settings.flame_smoke = 3.0
        dom_settings.flame_vorticity = 0.45
        dom_settings.vorticity = 0.45
        dom_settings.use_dissolve_smoke = True
        dom_settings.dissolve_speed = 45
        dom_settings.use_dissolve_smoke_log = True
        dom_settings.cache_type = "ALL"
        dom_settings.cache_frame_start = 1
        dom_settings.cache_frame_end = args.frames
        dom_settings.cache_directory = temp_cache_dir

        # 5. Create Orthographic Camera
        log("Step 5: Setting up orthographic camera at (0, -7.5, 2.0)...")
        cam_data = bpy.data.cameras.new("FlipbookCamera")
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = 7.0
        cam_obj = bpy.data.objects.new("FlipbookCamera", cam_data)
        scene.collection.objects.link(cam_obj)
        cam_obj.location = (0.0, -7.5, 2.0)
        cam_obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        scene.camera = cam_obj

        # 6. Add Directional Lighting to illuminate smoke volume
        log("Step 6: Setting up scene directional lighting for smoke volume...")
        sun_data = bpy.data.lights.new("SunKey", type="SUN")
        sun_data.energy = 5.0
        sun_obj = bpy.data.objects.new("SunKey", sun_data)
        scene.collection.objects.link(sun_obj)
        sun_obj.rotation_euler = (math.radians(50.0), math.radians(25.0), math.radians(-35.0))

        fill_data = bpy.data.lights.new("SunFill", type="SUN")
        fill_data.energy = 2.0
        fill_obj = bpy.data.objects.new("SunFill", fill_data)
        scene.collection.objects.link(fill_obj)
        fill_obj.rotation_euler = (math.radians(-30.0), math.radians(-40.0), math.radians(120.0))

        # 7. Create Principled Volume Shader
        log("Step 7: Creating Principled Volume shader network...")
        mat = bpy.data.materials.new("M_ExplosionVolume")
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        nodes.clear()

        # Attribute node for flame
        attr_flame = nodes.new("ShaderNodeAttribute")
        attr_flame.attribute_name = "flame"

        # Color ramp for fire emission
        ramp = nodes.new("ShaderNodeValToRGB")
        cr = ramp.color_ramp
        cr.elements[0].position = 0.0
        cr.elements[0].color = (0.0, 0.0, 0.0, 1.0)
        cr.elements[1].position = 0.90
        cr.elements[1].color = (1.0, 0.40, 0.05, 1.0)
        e_mid = cr.elements.new(0.35)
        e_mid.color = (0.90, 0.15, 0.01, 1.0)
        e_hot = cr.elements.new(0.98)
        e_hot.color = (1.0, 0.92, 0.55, 1.0)

        # Math multiplier for emission strength
        mult_emit = nodes.new("ShaderNodeMath")
        mult_emit.operation = "MULTIPLY"
        mult_emit.inputs[1].default_value = 25.0

        # Principled Volume node
        vol_node = nodes.new("ShaderNodeVolumePrincipled")
        vol_node.inputs["Color"].default_value = (0.28, 0.27, 0.26, 1.0)
        vol_node.inputs["Density Attribute"].default_value = "density"
        vol_node.inputs["Density"].default_value = 8.0
        vol_node.inputs["Temperature Attribute"].default_value = "flame"
        vol_node.inputs["Blackbody Intensity"].default_value = 1.0

        links.new(attr_flame.outputs["Fac"], ramp.inputs["Fac"])
        links.new(attr_flame.outputs["Fac"], mult_emit.inputs[0])
        links.new(ramp.outputs["Color"], vol_node.inputs["Emission Color"])
        links.new(mult_emit.outputs["Value"], vol_node.inputs["Emission Strength"])

        out_node = nodes.new("ShaderNodeOutputMaterial")
        links.new(vol_node.outputs["Volume"], out_node.inputs["Volume"])
        domain.data.materials.append(mat)

        # 8. Bake Mantaflow Simulation
        log("Step 8: Baking Mantaflow simulation data (bpy.ops.fluid.bake_all())...")
        bpy.context.view_layer.objects.active = domain
        domain.select_set(True)
        bake_result = bpy.ops.fluid.bake_all()
        log(f"Bake operator returned: {bake_result}")

        # 9. Render All Animation Frames
        log(f"Step 9: Rendering {args.frames} frames to {temp_frames_dir}...")
        for frame_idx in range(1, args.frames + 1):
            scene.frame_set(frame_idx)
            frame_path = os.path.join(temp_frames_dir, f"frame_{frame_idx:04d}.png")
            scene.render.filepath = frame_path
            bpy.ops.render.render(write_still=True)
            if frame_idx % 8 == 0 or frame_idx == args.frames:
                log(f"Rendered frame {frame_idx}/{args.frames}")

        # 10. Assemble Spritesheet
        log("Step 10: Assembling spritesheet...")
        assemble_spritesheet(
            Path(temp_frames_dir),
            output_spritesheet,
            frame_count=args.frames,
            frame_size=args.frame_size,
        )

        # 11. Verify output spritesheet
        log("Step 11: Verifying assembled spritesheet...")
        file_size = output_spritesheet.stat().st_size
        log(f"Spritesheet successfully generated: {output_spritesheet} ({file_size} bytes)")

        # 12. Trigger Godot Import
        if not args.skip_import:
            log("Step 12: Triggering Godot asset import...")
            trigger_godot_import(project_root)
            import_file = output_spritesheet.with_suffix(".png.import")
            if import_file.exists():
                log(f"Verified Godot import file exists: {import_file}")
            else:
                log(f"Note: Godot import file {import_file} will be created when editor runs.")

        log("Pipeline complete! Milestone 1 deliverables generated.")

    finally:
        # Cleanup intermediate simulation and render directories
        log("Step 13: Cleaning up intermediate temporary directories...")
        shutil.rmtree(temp_cache_dir, ignore_errors=True)
        shutil.rmtree(temp_frames_dir, ignore_errors=True)
        log("Temporary directories purged cleanly.")


if __name__ == "__main__":
    run_pipeline()
