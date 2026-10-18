"""Generator for a static prop with PBR materials and Godot 4 collision."""

from __future__ import annotations

import sys
from pathlib import Path

# Add tools/blender to sys.path so common utilities are importable
_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bpy
from common.collisions import create_box_collision
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material


def generate_dev_chest(output_dir: Path) -> Path:
    clean_scene()

    # 1. Base Crate Body (1m x 1m x 0.8m)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.4))
    body = bpy.context.active_object
    body.name = "Chest_Body"
    body.scale = (1.0, 1.0, 0.8)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Bevel modifier for rounded edges
    bevel = body.modifiers.new(name="Bevel", type="BEVEL")
    bevel.width = 0.04
    bevel.segments = 3

    # Materials
    metal_mat = create_pbr_material(
        name="Mat_Chest_Metal",
        base_color=(0.12, 0.14, 0.18, 1.0),
        metallic=0.85,
        roughness=0.35,
    )
    assign_material(body, metal_mat)

    # 2. Emissive Trim Band
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.4))
    trim = bpy.context.active_object
    trim.name = "Chest_Emissive_Trim"
    trim.scale = (1.02, 1.02, 0.08)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    trim_mat = create_pbr_material(
        name="Mat_Chest_Glow",
        base_color=(1.0, 0.45, 0.05, 1.0),
        metallic=0.1,
        roughness=0.2,
        emission_color=(1.0, 0.4, 0.0, 1.0),
        emission_strength=4.0,
    )
    assign_material(trim, trim_mat)

    # Join visual meshes
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    trim.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "dev_chest"

    # 3. Godot 4 Collision Mesh (-colonly)
    create_box_collision(body, suffix="-colonly")

    # 4. Export to GLB
    output_path = output_dir / "dev_chest.glb"
    export_godot_glb(
        filepath=output_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=True,
    )
    return output_path


def main() -> None:
    try:
        # Resolve BellaSDK root relative to this script
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        assets_dir = sdk_root / "assets" / "models" / "dev_chest"
        generate_dev_chest(assets_dir)
    except Exception as exc:
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
