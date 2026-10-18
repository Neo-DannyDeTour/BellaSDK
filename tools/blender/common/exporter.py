"""Godot 4 glTF export presets and scene management for Blender 5.x."""

from __future__ import annotations

import os
from pathlib import Path
import bpy


def clean_scene() -> None:
    """Reset the Blender scene to a completely blank slate."""
    # Ensure in OBJECT mode if possible
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    # Select all and delete
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    # Purge orphan data blocks
    for block_collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.textures,
        bpy.data.images,
        bpy.data.armatures,
        bpy.data.actions,
        bpy.data.curves,
        bpy.data.lights,
        bpy.data.cameras,
    ):
        for item in list(block_collection):
            block_collection.remove(item)


def export_godot_glb(
    filepath: Path | str,
    export_animations: bool = True,
    apply_modifiers: bool = True,
    only_selected: bool = False,
    save_blend: bool = False,
) -> Path:
    """Export the active scene or selection to Godot 4-compatible GLB format.

    Enforces Godot 4 standards:
    - Scale 1.0 (Blender units = Godot meters)
    - +Y up orientation
    - Baked actions and animation tracks
    - PBR materials
    """
    out_path = Path(filepath).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # If requested, save a copy of the source .blend file alongside
    if save_blend:
        blend_path = out_path.with_suffix(".blend")
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
        print(f"[Blender] Saved source .blend to: {blend_path}")

    # Ensure in OBJECT mode before export
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    # Configure glTF export parameters compatible with Blender 5.x
    export_kwargs = {
        "filepath": str(out_path),
        "export_format": "GLB",
        "export_yup": True,
        "export_apply": apply_modifiers,
        "export_materials": "EXPORT",
        "export_attributes": True,
        "use_selection": only_selected,
    }

    if export_animations:
        export_kwargs.update(
            {
                "export_animations": True,
                "export_frame_range": True,
                "export_current_frame": False,
                "export_anim_single_armature": True,
                "export_def_bones": True,
                "export_nla_strips": True,
            }
        )
    else:
        export_kwargs["export_animations"] = False

    print(f"[Blender] Exporting GLB to: {out_path}...")
    bpy.ops.export_scene.gltf(**export_kwargs)
    print(f"[Blender] GLB Export successful: {out_path} ({os.path.getsize(out_path)} bytes)")
    return out_path
