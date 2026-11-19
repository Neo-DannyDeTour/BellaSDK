"""Headless Blender procedural generator & baker for Soviet shelf prop.

Builds an open-front painted wooden shelving unit matching the reference:
- Dimensions: 0.90m W (X) x 0.38m D (Y) x 2.05m H (Z), bottom-center at Z=0.
- Open front faces +Y in Blender so glTF Y-up export faces -Z in Godot
  (matching Col_Back at +Z in props/soviet_shelf/soviet_shelf.tscn).
- 2 side panels, 7-plank vertical back panel with visible seams, top cap,
  bottom apron, 6 shelf boards aligned to Col_Board_0..5, 10 under-shelf cleats.
- Bakes 1024x1024 Albedo, OpenGL (+Y) Normal, and ORM (R=AO, G=Rough, B=Metal)
  for chipped pale sage-green paint over worn vertical wood planks.
- Exports props/soviet_shelf/soviet_shelf.glb (<= 2000 tris).
"""

import math
from pathlib import Path
import bpy
import bmesh
from mathutils import Matrix
import numpy as np

REPO_ROOT: Path = Path(__file__).resolve().parents[2]
PROP_DIR: Path = REPO_ROOT / "props" / "soviet_shelf"
EXPORT_GLB_PATH: Path = PROP_DIR / "soviet_shelf.glb"
TEX_DIR: Path = PROP_DIR / "textures"
TEX_RES: int = 1024

WIDTH: float = 0.90
DEPTH: float = 0.38
HEIGHT: float = 2.05
BOARD_THICK: float = 0.025
# Exact Y-centers from props/soviet_shelf/soviet_shelf.tscn Col_Board_0..5
BOARD_Z_CENTERS: list[float] = [0.082, 0.4715, 0.861, 1.2505, 1.64, 2.009]
NUM_BACK_PLANKS: int = 7


def clear_scene() -> None:
    """Reset Blender to an empty scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _add_beveled_box(
    bm: bmesh.types.BMesh,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    bevel_width: float = 0.002,
    mat_index: int = 0,
) -> None:
    """Append a beveled box to a BMesh with assigned material index."""
    ret = bmesh.ops.create_cube(
        bm,
        size=1.0,
        matrix=Matrix.LocRotScale(center, None, size),
    )
    verts = ret["verts"]
    vert_set = set(verts)
    faces = [f for f in bm.faces if all(v in vert_set for v in f.verts)]
    for f in faces:
        f.material_index = mat_index
    edges = [e for e in bm.edges if all(v in vert_set for v in e.verts)]
    if bevel_width > 0.0:
        bmesh.ops.bevel(
            bm,
            geom=edges,
            offset=bevel_width,
            segments=1,
            profile=0.5,
            affect="EDGES",
            clamp_overlap=True,
        )


def build_shelf_mesh() -> bpy.types.Object:
    """Build procedural Soviet shelf mesh with <= 2000 tris and Smart UV."""
    bm: bmesh.types.BMesh = bmesh.new()

    inner_w: float = WIDTH - (BOARD_THICK * 2.0)  # 0.85m
    side_x: float = (WIDTH * 0.5) - (BOARD_THICK * 0.5)  # 0.4375m
    back_y: float = -(DEPTH * 0.5) + (BOARD_THICK * 0.5)  # -0.1775m (Godot +Z)
    inner_depth: float = DEPTH - BOARD_THICK  # 0.355m
    board_y_center: float = BOARD_THICK * 0.5  # +0.0125m (from -0.165 to +0.19)

    cap_z_min: float = BOARD_Z_CENTERS[-1] + (BOARD_THICK * 0.5)
    cap_h: float = HEIGHT - cap_z_min

    # 1. Left & Right side panels (0.0 to cap_z_min, no overlap with top cap)
    for sign in (-1.0, 1.0):
        _add_beveled_box(
            bm,
            center=(sign * side_x, 0.0, cap_z_min * 0.5),
            size=(BOARD_THICK, DEPTH, cap_z_min),
            bevel_width=0.002,
            mat_index=0,
        )

    # 2. Vertical-plank back panel (7 planks, 0 gap so bevels form V-grooves with no slits)
    plank_w: float = inner_w / float(NUM_BACK_PLANKS)
    plank_offsets: list[float] = [0.0005, -0.0004, 0.0003, -0.0005, 0.0004, -0.0003, 0.0004]
    back_z_min: float = 0.02
    back_z_max: float = cap_z_min
    back_h: float = back_z_max - back_z_min
    back_z_center: float = (back_z_min + back_z_max) * 0.5
    for idx in range(NUM_BACK_PLANKS):
        px: float = -inner_w * 0.5 + plank_w * (idx + 0.5)
        py: float = back_y + plank_offsets[idx % len(plank_offsets)]
        _add_beveled_box(
            bm,
            center=(px, py, back_z_center),
            size=(plank_w, BOARD_THICK, back_h),
            bevel_width=0.0025,
            mat_index=0,
        )

    # 3. 6 Shelf boards aligned to Col_Board_0..5 (mat_index 1 = horizontal wood grain)
    for z_pos in BOARD_Z_CENTERS:
        _add_beveled_box(
            bm,
            center=(0.0, board_y_center, z_pos),
            size=(inner_w, inner_depth, BOARD_THICK),
            bevel_width=0.002,
            mat_index=1,
        )

    # 4. Top cap lip sitting cleanly on top of side panels (within 2.05m H)
    _add_beveled_box(
        bm,
        center=(0.0, 0.0, cap_z_min + cap_h * 0.5),
        size=(WIDTH, DEPTH, cap_h),
        bevel_width=0.002,
        mat_index=1,
    )

    # 5. Recessed front bottom apron rail under Board_0
    apron_h: float = BOARD_Z_CENTERS[0] - (BOARD_THICK * 0.5)
    _add_beveled_box(
        bm,
        center=(0.0, (DEPTH * 0.5) - 0.02, apron_h * 0.5),
        size=(inner_w, 0.02, apron_h),
        bevel_width=0.0015,
        mat_index=0,
    )

    # 6. 10 under-shelf support cleats/brackets (under boards 1..5, left & right)
    cleat_w: float = 0.016
    cleat_d: float = 0.29
    cleat_h: float = 0.026
    cleat_x: float = (inner_w * 0.5) - (cleat_w * 0.5)
    for z_pos in BOARD_Z_CENTERS[1:]:
        cz: float = z_pos - (BOARD_THICK * 0.5) - (cleat_h * 0.5)
        for sign in (-1.0, 1.0):
            _add_beveled_box(
                bm,
                center=(sign * cleat_x, board_y_center, cz),
                size=(cleat_w, cleat_d, cleat_h),
                bevel_width=0.002,
                mat_index=1,
            )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh_data: bpy.types.Mesh = bpy.data.meshes.new("Soviet_Shelf_Mesh")
    bm.to_mesh(mesh_data)
    bm.free()

    # Smooth shading with sharp edges by angle (via auto-smooth / weighted normals)
    for poly in mesh_data.polygons:
        poly.use_smooth = False

    obj: bpy.types.Object = bpy.data.objects.new("Soviet_Shelf", mesh_data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Smart UV unwrap
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(
        angle_limit=math.radians(66.0),
        island_margin=0.012,
        correct_aspect=True,
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    tri_count: int = sum(max(len(p.vertices) - 2, 1) for p in obj.data.polygons)
    print(f"[SovietShelf] Built mesh with {tri_count} triangles.")
    if tri_count > 2000:
        raise RuntimeError(f"Triangle count {tri_count} exceeds 2000 budget!")

    return obj


def _mix_rgba(
    nodes: bpy.types.Nodes,
    links: bpy.types.NodeLinks,
    blend_type: str = "MIX",
) -> tuple[bpy.types.Node, bpy.types.NodeSocket, bpy.types.NodeSocket, bpy.types.NodeSocket, bpy.types.NodeSocket]:
    """Create a ShaderNodeMix in RGBA mode and return (node, fac, a, b, result)."""
    node = nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    node.blend_type = blend_type
    fac_sock = node.inputs[0]
    rgba_in = [s for s in node.inputs if s.type == "RGBA"]
    rgba_out = [s for s in node.outputs if s.type == "RGBA"]
    return node, fac_sock, rgba_in[0], rgba_in[1], rgba_out[0]


def _build_procedural_wood_paint_mat(name: str, vertical_grain: bool) -> bpy.types.Material:
    """Build procedural chipped pale sage-green paint over worn wood material."""
    mat: bpy.types.Material = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_coord = nodes.new("ShaderNodeTexCoord")

    # Wood grain coordinate mapping
    map_wood = nodes.new("ShaderNodeMapping")
    if vertical_grain:
        map_wood.inputs["Scale"].default_value = (28.0, 28.0, 2.2)
    else:
        map_wood.inputs["Scale"].default_value = (2.2, 28.0, 28.0)
    links.new(tex_coord.outputs["Object"], map_wood.inputs["Vector"])

    noise_wood = nodes.new("ShaderNodeTexNoise")
    noise_wood.inputs["Scale"].default_value = 3.5
    noise_wood.inputs["Detail"].default_value = 8.0
    noise_wood.inputs["Roughness"].default_value = 0.65
    noise_wood.inputs["Distortion"].default_value = 0.8
    links.new(map_wood.outputs["Vector"], noise_wood.inputs["Vector"])

    # Wood color ramp (warm weathered brown)
    ramp_wood = nodes.new("ShaderNodeValToRGB")
    ramp_wood.color_ramp.elements[0].position = 0.25
    ramp_wood.color_ramp.elements[0].color = (0.075, 0.045, 0.022, 1.0)
    ramp_wood.color_ramp.elements[1].position = 0.78
    ramp_wood.color_ramp.elements[1].color = (0.145, 0.095, 0.048, 1.0)
    links.new(noise_wood.outputs["Fac"], ramp_wood.inputs["Fac"])

    # Paint variation (pale dusty sage green)
    noise_paint = nodes.new("ShaderNodeTexNoise")
    noise_paint.inputs["Scale"].default_value = 2.8
    noise_paint.inputs["Detail"].default_value = 5.0
    links.new(tex_coord.outputs["Object"], noise_paint.inputs["Vector"])

    ramp_paint = nodes.new("ShaderNodeValToRGB")
    ramp_paint.color_ramp.elements[0].position = 0.2
    ramp_paint.color_ramp.elements[0].color = (0.21, 0.30, 0.22, 1.0)
    ramp_paint.color_ramp.elements[1].position = 0.85
    ramp_paint.color_ramp.elements[1].color = (0.28, 0.38, 0.29, 1.0)
    links.new(noise_paint.outputs["Fac"], ramp_paint.inputs["Fac"])

    # Chipping / peeling mask: edge wear (Geometry Pointiness) + stretched noise
    ao_node = nodes.new("ShaderNodeAmbientOcclusion")
    ao_node.samples = 8
    ao_node.inputs["Distance"].default_value = 0.06

    geom_node = nodes.new("ShaderNodeNewGeometry")
    ramp_pointy = nodes.new("ShaderNodeValToRGB")
    ramp_pointy.color_ramp.elements[0].position = 0.54
    ramp_pointy.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    ramp_pointy.color_ramp.elements[1].position = 0.65
    ramp_pointy.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(geom_node.outputs["Pointiness"], ramp_pointy.inputs["Fac"])

    map_chip = nodes.new("ShaderNodeMapping")
    map_chip.inputs["Scale"].default_value = (10.0, 10.0, 1.8)
    links.new(tex_coord.outputs["Object"], map_chip.inputs["Vector"])

    noise_chip = nodes.new("ShaderNodeTexNoise")
    noise_chip.inputs["Scale"].default_value = 2.5
    noise_chip.inputs["Detail"].default_value = 6.0
    noise_chip.inputs["Roughness"].default_value = 0.55
    links.new(map_chip.outputs["Vector"], noise_chip.inputs["Vector"])

    # Combine pointiness + noise for paint-vs-wood mask (~12% chipped wood, ~88% paint)
    math_add_wear = nodes.new("ShaderNodeMath")
    math_add_wear.operation = "ADD"
    links.new(noise_chip.outputs["Fac"], math_add_wear.inputs[0])

    math_mul_edge = nodes.new("ShaderNodeMath")
    math_mul_edge.operation = "MULTIPLY"
    math_mul_edge.inputs[1].default_value = 0.18
    links.new(ramp_pointy.outputs["Color"], math_mul_edge.inputs[0])
    links.new(math_mul_edge.outputs["Value"], math_add_wear.inputs[1])

    ramp_chip_mask = nodes.new("ShaderNodeValToRGB")
    ramp_chip_mask.color_ramp.elements[0].position = 0.76
    ramp_chip_mask.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)  # Paint
    ramp_chip_mask.color_ramp.elements[1].position = 0.80
    ramp_chip_mask.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)  # Exposed wood
    links.new(math_add_wear.outputs["Value"], ramp_chip_mask.inputs["Fac"])

    # Mix paint and wood using explicit RGBA sockets
    _, mix_fac, mix_a, mix_b, mix_res = _mix_rgba(nodes, links, "MIX")
    links.new(ramp_chip_mask.outputs["Color"], mix_fac)
    links.new(ramp_paint.outputs["Color"], mix_a)
    links.new(ramp_wood.outputs["Color"], mix_b)

    # Subtle corner grime using AO
    _, grime_fac, grime_a, grime_b, grime_res = _mix_rgba(nodes, links, "MULTIPLY")
    grime_fac.default_value = 0.25
    links.new(mix_res, grime_a)
    links.new(ao_node.outputs["Color"], grime_b)

    links.new(grime_res, bsdf.inputs["Base Color"])

    # Roughness: 0.80 on paint, 0.92 on bare wood
    mix_rough = nodes.new("ShaderNodeMix")
    mix_rough.data_type = "FLOAT"
    mix_rough.inputs["A"].default_value = 0.80
    mix_rough.inputs["B"].default_value = 0.92
    links.new(ramp_chip_mask.outputs["Color"], mix_rough.inputs["Factor"])
    links.new(mix_rough.outputs["Result"], bsdf.inputs["Roughness"])

    # Bump from wood grain + chip edge
    math_bump = nodes.new("ShaderNodeMath")
    math_bump.operation = "SUBTRACT"
    links.new(noise_wood.outputs["Fac"], math_bump.inputs[0])

    math_chip_depth = nodes.new("ShaderNodeMath")
    math_chip_depth.operation = "MULTIPLY"
    math_chip_depth.inputs[1].default_value = 0.55
    links.new(ramp_chip_mask.outputs["Color"], math_chip_depth.inputs[0])
    links.new(math_chip_depth.outputs["Value"], math_bump.inputs[1])

    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    bump.inputs["Distance"].default_value = 0.004
    links.new(math_bump.outputs["Value"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def _create_image(name: str, is_data: bool) -> bpy.types.Image:
    """Create an empty bake target image with sRGB or Non-Color colorspace."""
    img: bpy.types.Image = bpy.data.images.new(name, width=TEX_RES, height=TEX_RES)
    img.colorspace_settings.name = "Non-Color" if is_data else "sRGB"
    return img


def bake_and_save_textures(obj: bpy.types.Object) -> tuple[Path, Path, Path]:
    """Bake Albedo, OpenGL (+Y) Normal, Roughness, and AO into PNG maps."""
    mat_vert: bpy.types.Material = _build_procedural_wood_paint_mat("Mat_Vert", True)
    mat_horiz: bpy.types.Material = _build_procedural_wood_paint_mat("Mat_Horiz", False)
    obj.data.materials.clear()
    obj.data.materials.append(mat_vert)
    obj.data.materials.append(mat_horiz)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16

    img_diff: bpy.types.Image = _create_image("soviet_shelf_albedo", False)
    img_norm: bpy.types.Image = _create_image("soviet_shelf_normal", True)
    img_rough: bpy.types.Image = _create_image("soviet_shelf_rough", True)
    img_ao: bpy.types.Image = _create_image("soviet_shelf_ao", True)

    # Add bake image node to both materials and make it active
    tex_nodes: list[bpy.types.ShaderNodeTexImage] = []
    for mat in (mat_vert, mat_horiz):
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        mat.node_tree.nodes.active = node
        tex_nodes.append(node)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 8

    # Bake Diffuse Color
    for n in tex_nodes:
        n.image = img_diff
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    bpy.ops.object.bake(type="DIFFUSE")

    # Bake Tangent Normal (OpenGL +Y)
    for n in tex_nodes:
        n.image = img_norm
    scene.render.bake.normal_space = "TANGENT"
    scene.render.bake.normal_r = "POS_X"
    scene.render.bake.normal_g = "POS_Y"
    scene.render.bake.normal_b = "POS_Z"
    bpy.ops.object.bake(type="NORMAL")

    # Bake Roughness
    for n in tex_nodes:
        n.image = img_rough
    bpy.ops.object.bake(type="ROUGHNESS")

    # Bake AO
    for n in tex_nodes:
        n.image = img_ao
    bpy.ops.object.bake(type="AO")

    TEX_DIR.mkdir(parents=True, exist_ok=True)
    albedo_path: Path = TEX_DIR / "soviet_shelf_albedo.png"
    normal_path: Path = TEX_DIR / "soviet_shelf_normal.png"
    orm_path: Path = TEX_DIR / "soviet_shelf_orm.png"

    img_diff.filepath_raw = str(albedo_path)
    img_diff.file_format = "PNG"
    img_diff.save()

    img_norm.filepath_raw = str(normal_path)
    img_norm.file_format = "PNG"
    img_norm.save()

    ao_px: np.ndarray = np.array(img_ao.pixels[:], dtype=np.float32).reshape(
        (TEX_RES, TEX_RES, 4)
    )
    rough_px: np.ndarray = np.array(img_rough.pixels[:], dtype=np.float32).reshape(
        (TEX_RES, TEX_RES, 4)
    )
    orm_px: np.ndarray = np.ones((TEX_RES, TEX_RES, 4), dtype=np.float32)
    orm_px[:, :, 0] = ao_px[:, :, 0]
    orm_px[:, :, 1] = np.clip(rough_px[:, :, 0], 0.65, 0.96)
    orm_px[:, :, 2] = 0.0

    img_orm: bpy.types.Image = _create_image("soviet_shelf_orm", True)
    img_orm.pixels[:] = orm_px.ravel().tolist()
    img_orm.filepath_raw = str(orm_path)
    img_orm.file_format = "PNG"
    img_orm.save()

    return albedo_path, normal_path, orm_path


def assign_baked_material(
    obj: bpy.types.Object,
    albedo_path: Path,
    normal_path: Path,
    orm_path: Path,
) -> None:
    """Assign single unified PBR material using the baked maps for GLB export."""
    for poly in obj.data.polygons:
        poly.material_index = 0
    obj.data.materials.clear()

    mat: bpy.types.Material = bpy.data.materials.new(name="SovietShelf_Mat")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nodes.new("ShaderNodeTexImage")
    tex_alb.image = bpy.data.images.load(str(albedo_path))
    tex_alb.image.colorspace_settings.name = "sRGB"
    links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nodes.new("ShaderNodeTexImage")
    tex_orm.image = bpy.data.images.load(str(orm_path))
    tex_orm.image.colorspace_settings.name = "Non-Color"
    sep = nodes.new("ShaderNodeSeparateColor")
    links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nodes.new("ShaderNodeTexImage")
    tex_nrm.image = bpy.data.images.load(str(normal_path))
    tex_nrm.image.colorspace_settings.name = "Non-Color"
    nrm_map = nodes.new("ShaderNodeNormalMap")
    links.new(tex_nrm.outputs["Color"], nrm_map.inputs["Color"])
    links.new(nrm_map.outputs["Normal"], bsdf.inputs["Normal"])

    obj.data.materials.append(mat)


def main() -> None:
    """Generate Soviet shelf GLB and baked textures."""
    clear_scene()
    shelf: bpy.types.Object = build_shelf_mesh()
    albedo_path, normal_path, orm_path = bake_and_save_textures(shelf)
    assign_baked_material(shelf, albedo_path, normal_path, orm_path)

    bpy.ops.object.select_all(action="DESELECT")
    shelf.select_set(True)
    bpy.context.view_layer.objects.active = shelf
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    EXPORT_GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(EXPORT_GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_tangents=True,
        export_yup=True,
    )
    print(f"[SovietShelf] Exported GLB -> {EXPORT_GLB_PATH}")


if __name__ == "__main__":
    main()
