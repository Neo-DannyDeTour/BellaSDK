"""PBR material utilities compatible with Godot 4 StandardMaterial3D."""

from __future__ import annotations

import bpy


def create_pbr_material(
    name: str,
    base_color: tuple[float, float, float, float] = (0.8, 0.8, 0.8, 1.0),
    metallic: float = 0.0,
    roughness: float = 0.5,
    emission_color: tuple[float, float, float, float] | None = None,
    emission_strength: float = 1.0,
    base_color_image: bpy.types.Image | None = None,
    roughness_image: bpy.types.Image | None = None,
    normal_image: bpy.types.Image | None = None,
    normal_strength: float = 1.0,
) -> bpy.types.Material:
    """Create a Principled BSDF PBR material for glTF export and Solid viewport."""
    mat = bpy.data.materials.get(name)
    if mat:
        bpy.data.materials.remove(mat)

    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True

    # Also set viewport Solid-mode properties so it never looks flat grey in Solid view
    mat.diffuse_color = base_color
    mat.metallic = metallic
    mat.roughness = roughness

    tree = mat.node_tree
    nodes = tree.nodes
    links = tree.links
    bsdf = nodes.get("Principled BSDF")

    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = base_color
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
        if emission_color and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emission_color
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission_strength

        if base_color_image is not None:
            tex_node = nodes.new("ShaderNodeTexImage")
            tex_node.image = base_color_image
            tex_node.location = (-400, 300)
            links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])

        if roughness_image is not None:
            rough_node = nodes.new("ShaderNodeTexImage")
            rough_node.image = roughness_image
            rough_node.image.colorspace_settings.name = "Non-Color"
            rough_node.location = (-400, 0)
            links.new(rough_node.outputs["Color"], bsdf.inputs["Roughness"])

        if normal_image is not None:
            norm_tex = nodes.new("ShaderNodeTexImage")
            norm_tex.image = normal_image
            norm_tex.image.colorspace_settings.name = "Non-Color"
            norm_tex.location = (-600, -300)

            norm_map = nodes.new("ShaderNodeNormalMap")
            norm_map.inputs["Strength"].default_value = normal_strength
            norm_map.location = (-300, -300)

            links.new(norm_tex.outputs["Color"], norm_map.inputs["Color"])
            links.new(norm_map.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    """Assign a material to an object's primary material slot."""
    if not hasattr(obj, "data") or not hasattr(obj.data, "materials"):
        return
    if len(obj.data.materials) == 0:
        obj.data.materials.append(material)
    else:
        obj.data.materials[0] = material
