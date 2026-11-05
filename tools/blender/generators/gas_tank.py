"""Generator for procedural Gas Tank prop with baked PBR and Godot 4 collision."""

from __future__ import annotations

import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

# --- CONSTANTS ---
TANK_NAME = "GasTank"
COL_NAME = "GasTank-colonly"
MAT_NAME = "M_GasTank"

IMG_ALBEDO = "T_GasTank_Albedo"
IMG_ROUGH = "T_GasTank_Roughness"
IMG_NORMAL = "T_GasTank_Normal"

BAKE_RES = 1024
BAKE_MARGIN = 8
BAKE_SAMPLES = 16
EXPORT_FILENAME = "gas_tank.glb"

RADIAL_SEGS = 16
PIPE_SEGS = 12
CENTER_Z = 0.75
SHARP_ANGLE_RAD = math.radians(35.0)
UV_ANGLE_RAD = math.radians(66.0)
UV_MARGIN = 0.02


def purge_existing(
    obj_names: list[str],
    mat_names: list[str],
    img_names: list[str],
) -> None:
    """Remove prior objects, orphan meshes, materials, and baked images."""
    for name in obj_names:
        obj = bpy.data.objects.get(name)
        if obj:
            mesh_data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if mesh_data and mesh_data.users == 0:
                bpy.data.meshes.remove(mesh_data)

    for name in mat_names:
        mat = bpy.data.materials.get(name)
        if mat:
            bpy.data.materials.remove(mat, do_unlink=True)

    for name in img_names:
        img = bpy.data.images.get(name)
        if img:
            bpy.data.images.remove(img, do_unlink=True)


def add_revolved_profile(
    bm: bmesh.types.BMesh,
    profile: list[tuple[float, float]],
    segments: int,
    axis: str = "Y",
    origin: Vector = Vector((0.0, 0.0, 0.0)),
    cap_start: bool = True,
    cap_end: bool = True,
) -> None:
    """Generate coaxial revolved rings along Y or Z axis and bridge loops."""
    rings: list[list[bmesh.types.BMVert]] = []
    step_angle = (2.0 * math.pi) / segments

    for axial_pos, radius in profile:
        ring: list[bmesh.types.BMVert] = []
        for i in range(segments):
            angle = i * step_angle
            c = math.cos(angle) * radius
            s = math.sin(angle) * radius
            if axis == "Y":
                pos = origin + Vector((c, axial_pos, s))
            else:
                pos = origin + Vector((c, s, axial_pos))
            ring.append(bm.verts.new(pos))
        rings.append(ring)

    for r_idx in range(len(rings) - 1):
        r_curr = rings[r_idx]
        r_next = rings[r_idx + 1]
        for i in range(segments):
            i_next = (i + 1) % segments
            bm.faces.new((r_curr[i], r_curr[i_next], r_next[i_next], r_next[i]))

    if cap_start and rings:
        bm.faces.new(list(reversed(rings[0])))
    if cap_end and rings:
        bm.faces.new(rings[-1])


def add_front_louvers(bm: bmesh.types.BMesh, center_z: float) -> None:
    """Add 4 angled horizontal vent slats inside the front axial boss."""
    boss_y_front = 1.792
    boss_y_back = 1.762
    boss_inner_r = 0.142
    slat_thickness = 0.012
    z_offsets = (-0.075, -0.025, 0.025, 0.075)

    for dz in z_offsets:
        half_chord = math.sqrt(max(0.001, boss_inner_r**2 - dz**2)) * 0.92
        z_front = center_z + dz - 0.008
        z_back = center_z + dz + 0.008

        v0 = bm.verts.new((-half_chord, boss_y_back, z_back))
        v1 = bm.verts.new((half_chord, boss_y_back, z_back))
        v2 = bm.verts.new((half_chord, boss_y_front, z_front))
        v3 = bm.verts.new((-half_chord, boss_y_front, z_front))

        v4 = bm.verts.new((-half_chord, boss_y_back, z_back + slat_thickness))
        v5 = bm.verts.new((half_chord, boss_y_back, z_back + slat_thickness))
        v6 = bm.verts.new((half_chord, boss_y_front, z_front + slat_thickness))
        v7 = bm.verts.new((-half_chord, boss_y_front, z_front + slat_thickness))

        bm.faces.new((v0, v1, v2, v3))
        bm.faces.new((v7, v6, v5, v4))
        bm.faces.new((v0, v4, v5, v1))
        bm.faces.new((v3, v2, v6, v7))
        bm.faces.new((v0, v3, v7, v4))
        bm.faces.new((v1, v5, v6, v2))


def add_saddle_supports(bm: bmesh.types.BMesh, center_z: float) -> None:
    """Build 2 contoured cradle piers and 2 longitudinal base skid rails."""
    saddle_y_centers = (-0.85, 0.85)
    half_thick = 0.07
    cyl_r = 0.585
    x_steps = (-0.48, -0.32, -0.16, 0.0, 0.16, 0.32, 0.48)

    for y_c in saddle_y_centers:
        y_f = y_c + half_thick
        y_b = y_c - half_thick
        front_top: list[bmesh.types.BMVert] = []
        back_top: list[bmesh.types.BMVert] = []
        front_bot: list[bmesh.types.BMVert] = []
        back_bot: list[bmesh.types.BMVert] = []

        for x in x_steps:
            z_arc = center_z - math.sqrt(max(0.01, cyl_r**2 - x**2))
            x_base = x * 0.94
            front_top.append(bm.verts.new((x, y_f, z_arc)))
            back_top.append(bm.verts.new((x, y_b, z_arc)))
            front_bot.append(bm.verts.new((x_base, y_f, 0.0)))
            back_bot.append(bm.verts.new((x_base, y_b, 0.0)))

        for i in range(len(x_steps) - 1):
            bm.faces.new((front_bot[i], front_bot[i + 1], front_top[i + 1], front_top[i]))
            bm.faces.new((back_top[i], back_top[i + 1], back_bot[i + 1], back_bot[i]))
            bm.faces.new((front_top[i], front_top[i + 1], back_top[i + 1], back_top[i]))
            bm.faces.new((back_bot[i], back_bot[i + 1], front_bot[i + 1], front_bot[i]))

        bm.faces.new((back_bot[0], front_bot[0], front_top[0], back_top[0]))
        bm.faces.new((front_bot[-1], back_bot[-1], back_top[-1], front_top[-1]))

    for x_sign in (-1.0, 1.0):
        x_in = x_sign * 0.36
        x_out = x_sign * 0.46
        x_min, x_max = min(x_in, x_out), max(x_in, x_out)
        bmesh.ops.create_cube(
            bm,
            size=1.0,
            matrix=Matrix.Translation(((x_min + x_max) * 0.5, 0.0, 0.0275))
            @ Matrix.Diagonal((x_max - x_min, 2.10, 0.055, 1.0)),
        )


def build_weathered_material() -> bpy.types.Material:
    """Create procedural dark olive-grey weathered steel PBR material."""
    mat = bpy.data.materials.new(name=MAT_NAME)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    out_node.location = (400, 0)

    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.name = "Principled BSDF"
    bsdf.location = (100, 0)
    bsdf.inputs["Metallic"].default_value = 0.82

    tex_coord = nodes.new(type="ShaderNodeTexCoord")
    tex_coord.location = (-800, 0)

    noise = nodes.new(type="ShaderNodeTexNoise")
    noise.location = (-580, 100)
    noise.inputs["Scale"].default_value = 6.5
    noise.inputs["Detail"].default_value = 10.0
    noise.inputs["Roughness"].default_value = 0.65

    ramp_col = nodes.new(type="ShaderNodeValToRGB")
    ramp_col.location = (-280, 220)
    ramp_col.color_ramp.elements[0].position = 0.32
    ramp_col.color_ramp.elements[0].color = (0.14, 0.15, 0.12, 1.0)
    ramp_col.color_ramp.elements[1].position = 0.74
    ramp_col.color_ramp.elements[1].color = (0.27, 0.28, 0.23, 1.0)

    ramp_rough = nodes.new(type="ShaderNodeValToRGB")
    ramp_rough.location = (-280, -10)
    ramp_rough.color_ramp.elements[0].position = 0.25
    ramp_rough.color_ramp.elements[0].color = (0.62, 0.62, 0.62, 1.0)
    ramp_rough.color_ramp.elements[1].position = 0.80
    ramp_rough.color_ramp.elements[1].color = (0.88, 0.88, 0.88, 1.0)

    bump = nodes.new(type="ShaderNodeBump")
    bump.location = (-220, -240)
    bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.01

    links.new(tex_coord.outputs["Object"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp_col.inputs["Fac"])
    links.new(noise.outputs["Fac"], ramp_rough.inputs["Fac"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])

    links.new(ramp_col.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(ramp_rough.outputs["Color"], bsdf.inputs["Roughness"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    return mat


def create_bake_image(name: str, is_data: bool, out_dir: str) -> bpy.types.Image:
    """Allocate target image buffer, set colorspace, and save PNG to disk + pack."""
    img = bpy.data.images.new(name=name, width=BAKE_RES, height=BAKE_RES, alpha=False)
    img.colorspace_settings.name = "Non-Color" if is_data else "sRGB"
    img.filepath_raw = os.path.join(out_dir, f"{name}.png")
    img.file_format = "PNG"
    return img


def bake_pass(
    nodes: bpy.types.Nodes,
    tex_node: bpy.types.Node,
    bake_type: str,
    pass_filter: set[str] | None = None,
) -> None:
    """Set active target image node and execute a single Cycles bake pass."""
    for n in nodes:
        n.select = False
    tex_node.select = True
    nodes.active = tex_node

    if pass_filter:
        bpy.ops.object.bake(
            type=bake_type,
            pass_filter=pass_filter,
            margin=BAKE_MARGIN,
            use_clear=True,
        )
    else:
        bpy.ops.object.bake(
            type=bake_type,
            margin=BAKE_MARGIN,
            use_clear=True,
        )
    tex_node.image.save()
    tex_node.image.pack()


def bake_and_rewire_pbr(
    tank_obj: bpy.types.Object,
    mat: bpy.types.Material,
    out_dir: str,
) -> None:
    """Bake Base Color, Roughness, and Normal via Cycles, then rewire for glTF."""
    scene = bpy.context.scene
    prev_engine = scene.render.engine
    prev_samples = scene.cycles.samples
    prev_denoiser = scene.cycles.use_denoising

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = BAKE_SAMPLES
    scene.cycles.use_denoising = False

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    tank_obj.select_set(True)
    bpy.context.view_layer.objects.active = tank_obj

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    out_node = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")

    img_albedo = create_bake_image(IMG_ALBEDO, is_data=False, out_dir=out_dir)
    img_rough = create_bake_image(IMG_ROUGH, is_data=True, out_dir=out_dir)
    img_norm = create_bake_image(IMG_NORMAL, is_data=True, out_dir=out_dir)

    node_albedo = nodes.new(type="ShaderNodeTexImage")
    node_albedo.image = img_albedo
    node_rough = nodes.new(type="ShaderNodeTexImage")
    node_rough.image = img_rough
    node_norm = nodes.new(type="ShaderNodeTexImage")
    node_norm.image = img_norm

    # 1. Bake Albedo (temporarily zero Metallic so Cycles DIFFUSE outputs Base Color)
    orig_metal = bsdf.inputs["Metallic"].default_value
    bsdf.inputs["Metallic"].default_value = 0.0
    bake_pass(nodes, node_albedo, "DIFFUSE", pass_filter={"COLOR"})
    bsdf.inputs["Metallic"].default_value = orig_metal

    # 2. Bake Roughness & Tangent Normal
    bake_pass(nodes, node_rough, "ROUGHNESS")
    bake_pass(nodes, node_norm, "NORMAL")

    # 3. Strip procedural nodes and wire baked textures for glTF 2.0 export
    keep_nodes = {bsdf, out_node, node_albedo, node_rough, node_norm}
    for n in list(nodes):
        if n not in keep_nodes:
            nodes.remove(n)

    node_albedo.location = (-350, 220)
    node_rough.location = (-350, -40)
    node_norm.location = (-550, -300)

    normal_map = nodes.new(type="ShaderNodeNormalMap")
    normal_map.location = (-220, -300)

    links.new(node_albedo.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(node_rough.outputs["Color"], bsdf.inputs["Roughness"])
    links.new(node_norm.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])

    scene.render.engine = prev_engine
    scene.cycles.samples = prev_samples
    scene.cycles.use_denoising = prev_denoiser


def export_godot_glb(
    tank_obj: bpy.types.Object,
    col_obj: bpy.types.Object,
    export_path: str,
) -> None:
    """Select GasTank + GasTank-colonly and export binary glTF (.glb)."""
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    tank_obj.select_set(True)
    col_obj.select_set(True)
    bpy.context.view_layer.objects.active = tank_obj

    bpy.ops.export_scene.gltf(
        filepath=export_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )


def generate_gas_tank(out_dir: str | None = None) -> bpy.types.Object:
    """Construct mesh, UVs, procedural shader, bake PBR maps, and export .glb."""
    if out_dir is None:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        out_path = sdk_root / "assets" / "props" / "gas_tank"
        out_path.mkdir(parents=True, exist_ok=True)
        out_dir = str(out_path)
    else:
        os.makedirs(out_dir, exist_ok=True)

    purge_existing(
        obj_names=[TANK_NAME, COL_NAME],
        mat_names=[MAT_NAME],
        img_names=[IMG_ALBEDO, IMG_ROUGH, IMG_NORMAL],
    )

    bm = bmesh.new()

    hull_profile: list[tuple[float, float]] = [
        (-1.72, 0.160),
        (-1.35, 0.600),
        (-1.34, 0.635),
        (-1.26, 0.635),
        (-1.25, 0.600),
        (1.25, 0.600),
        (1.26, 0.635),
        (1.34, 0.635),
        (1.35, 0.600),
        (1.72, 0.160),
        (1.72, 0.175),
        (1.80, 0.175),
        (1.80, 0.145),
        (1.76, 0.145),
    ]
    add_revolved_profile(
        bm,
        profile=hull_profile,
        segments=RADIAL_SEGS,
        axis="Y",
        origin=Vector((0.0, 0.0, CENTER_Z)),
        cap_start=True,
        cap_end=True,
    )

    neck_profile: list[tuple[float, float]] = [
        (1.28, 0.115),
        (1.35, 0.130),
        (1.36, 0.100),
        (1.44, 0.100),
        (1.44, 0.145),
        (1.48, 0.145),
        (1.48, 0.080),
        (1.45, 0.080),
    ]
    add_revolved_profile(
        bm,
        profile=neck_profile,
        segments=PIPE_SEGS,
        axis="Z",
        origin=Vector((0.0, -0.95, 0.0)),
        cap_start=False,
        cap_end=True,
    )

    add_front_louvers(bm, CENTER_Z)
    add_saddle_supports(bm, CENTER_Z)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if edge.is_manifold and edge.calc_face_angle(0.0) > SHARP_ANGLE_RAD:
            edge.smooth = False

    mesh = bpy.data.meshes.new(TANK_NAME)
    bm.to_mesh(mesh)
    mesh.update()

    tank_obj = bpy.data.objects.new(TANK_NAME, mesh)
    bpy.context.collection.objects.link(tank_obj)
    mat = build_weathered_material()
    tank_obj.data.materials.append(mat)

    bm_col = bmesh.new()
    for v in bm.verts:
        bm_col.verts.new(v.co)
    hull_res = bmesh.ops.convex_hull(bm_col, input=bm_col.verts)
    interior_geom = list({
        elem
        for elem in hull_res.get("geom_interior", []) + hull_res.get("geom_unused", [])
        if isinstance(elem, bmesh.types.BMVert) and elem.is_valid
    })
    if interior_geom:
        bmesh.ops.delete(bm_col, geom=interior_geom, context="VERTS")

    col_mesh = bpy.data.meshes.new(COL_NAME)
    bm_col.to_mesh(col_mesh)
    bm_col.free()
    bm.free()

    col_obj = bpy.data.objects.new(COL_NAME, col_mesh)
    bpy.context.collection.objects.link(col_obj)
    col_obj.parent = tank_obj
    col_obj.display_type = "WIRE"

    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    tank_obj.select_set(True)
    bpy.context.view_layer.objects.active = tank_obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=UV_ANGLE_RAD, island_margin=UV_MARGIN)
    bpy.ops.object.mode_set(mode="OBJECT")

    bake_and_rewire_pbr(tank_obj, mat, out_dir)
    export_path = os.path.join(out_dir, EXPORT_FILENAME)
    export_godot_glb(tank_obj, col_obj, export_path)
    print(f"Exported Godot 4 asset: {export_path}")

    return tank_obj


if __name__ == "__main__":
    generate_gas_tank()
