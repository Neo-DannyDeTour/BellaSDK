import math
import os
import bpy
import bmesh
from mathutils import Vector

# Spec constants
BAY_LENGTH: float = 4.0
PIPE_RADIUS: float = 0.032
COLLAR_RADIUS: float = 0.038
COLLAR_WIDTH: float = 0.08
PIPE_SEGMENTS: int = 8
PIPE_Y_OFFSET: float = -0.05
PIPE_Z_HEIGHTS: list[float] = [0.08, 0.20, 0.32, 0.44]

BRACKET_W: float = 0.04
BRACKET_D: float = 0.09
BRACKET_H: float = 0.52

SCRIPT_DIR: str = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT: str = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
TEX_DIR: str = os.path.join(
    REPO_ROOT, "assets", "materials", "rusty_orange_metal", "textures"
)
EXPORT_PATH: str = os.path.join(
    REPO_ROOT, "assets", "models", "props", "pipe_kit", "pipe_kit.glb"
)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_rust_material() -> bpy.types.Material:
    mat: bpy.types.Material = bpy.data.materials.new(name="M_RustyPipes")
    mat.use_nodes = True
    nt: bpy.types.NodeTree = mat.node_tree
    bsdf: bpy.types.Node | None = nt.nodes.get("Principled BSDF")
    if not bsdf:
        return mat

    albedo_path: str = os.path.join(TEX_DIR, "rusty_orange_metal_albedo.png")
    orm_path: str = os.path.join(TEX_DIR, "rusty_orange_metal_orm.png")
    normal_path: str = os.path.join(TEX_DIR, "rusty_orange_metal_normal.png")

    if os.path.isfile(albedo_path):
        tex_albedo: bpy.types.Node = nt.nodes.new("ShaderNodeTexImage")
        tex_albedo.image = bpy.data.images.load(albedo_path)
        tex_albedo.image.colorspace_settings.name = "sRGB"
        nt.links.new(tex_albedo.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (0.28, 0.18, 0.11, 1.0)

    if os.path.isfile(orm_path):
        tex_orm: bpy.types.Node = nt.nodes.new("ShaderNodeTexImage")
        tex_orm.image = bpy.data.images.load(orm_path)
        tex_orm.image.colorspace_settings.name = "Non-Color"

        sep: bpy.types.Node = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

        # glTF 2.0 exporter reads Occlusion from a 'glTF Material Output' group node
        gltf_group: bpy.types.NodeTree = bpy.data.node_groups.new(
            "glTF Material Output", "ShaderNodeTree"
        )
        gltf_group.interface.new_socket(
            name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat"
        )
        gltf_node: bpy.types.Node = nt.nodes.new("ShaderNodeGroup")
        gltf_node.node_tree = gltf_group
        nt.links.new(sep.outputs["Red"], gltf_node.inputs["Occlusion"])
    else:
        bsdf.inputs["Metallic"].default_value = 0.75
        bsdf.inputs["Roughness"].default_value = 0.82

    if os.path.isfile(normal_path):
        tex_norm: bpy.types.Node = nt.nodes.new("ShaderNodeTexImage")
        tex_norm.image = bpy.data.images.load(normal_path)
        tex_norm.image.colorspace_settings.name = "Non-Color"

        norm_map: bpy.types.Node = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tex_norm.outputs["Color"], norm_map.inputs["Color"])
        nt.links.new(norm_map.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def append_bracket(bm: bmesh.types.BMesh, x_center: float) -> None:
    hw: float = BRACKET_W * 0.5
    x0: float = x_center - hw
    x1: float = x_center + hw
    y0: float = -BRACKET_D
    y1: float = 0.0
    z0: float = 0.0
    z1: float = BRACKET_H

    verts: list[bmesh.types.BMVert] = [
        bm.verts.new((x0, y0, z0)),
        bm.verts.new((x1, y0, z0)),
        bm.verts.new((x1, y1, z0)),
        bm.verts.new((x0, y1, z0)),
        bm.verts.new((x0, y0, z1)),
        bm.verts.new((x1, y0, z1)),
        bm.verts.new((x1, y1, z1)),
        bm.verts.new((x0, y1, z1)),
    ]

    # Omit back face (2, 3, 7, 6) flush against wall Y=0.0
    faces_idx: list[tuple[int, int, int, int]] = [
        (0, 1, 5, 4),  # Front (-Y)
        (0, 4, 7, 3),  # Left (-X)
        (1, 2, 6, 5),  # Right (+X)
        (4, 5, 6, 7),  # Top (+Z)
        (0, 3, 2, 1),  # Bottom (-Z)
    ]
    for f_idx in faces_idx:
        f: bmesh.types.BMFace = bm.faces.new([verts[i] for i in f_idx])
        f.smooth = False
        for e in f.edges:
            e.smooth = False


def append_pipe_with_collar(bm: bmesh.types.BMesh, z_center: float) -> None:
    mid_x: float = BAY_LENGTH * 0.5
    c_half: float = COLLAR_WIDTH * 0.5

    stations: list[tuple[float, float]] = [
        (0.0, PIPE_RADIUS),
        (mid_x - c_half, PIPE_RADIUS),
        (mid_x - c_half, COLLAR_RADIUS),
        (mid_x + c_half, COLLAR_RADIUS),
        (mid_x + c_half, PIPE_RADIUS),
        (BAY_LENGTH, PIPE_RADIUS),
    ]

    rings: list[list[bmesh.types.BMVert]] = []
    for x_pos, radius in stations:
        ring: list[bmesh.types.BMVert] = []
        for i in range(PIPE_SEGMENTS):
            # Start angle at +Y (back-center against wall) so UV seam is hidden
            angle: float = 2.0 * math.pi * i / PIPE_SEGMENTS
            vy: float = PIPE_Y_OFFSET + math.cos(angle) * radius
            vz: float = z_center + math.sin(angle) * radius
            ring.append(bm.verts.new((x_pos, vy, vz)))
        rings.append(ring)

    # Bridge rings; mark collar radial steps flat, barrel segments smooth
    sharp_ring_indices: set[int] = {1, 2, 3, 4}
    for r_idx in range(len(rings) - 1):
        r_curr: list[bmesh.types.BMVert] = rings[r_idx]
        r_next: list[bmesh.types.BMVert] = rings[r_idx + 1]
        is_radial_step: bool = r_idx in {1, 3}

        for i in range(PIPE_SEGMENTS):
            i_next: int = (i + 1) % PIPE_SEGMENTS
            f: bmesh.types.BMFace = bm.faces.new(
                [r_curr[i], r_next[i], r_next[i_next], r_curr[i_next]]
            )
            f.smooth = not is_radial_step

        if r_idx in sharp_ring_indices:
            for i in range(PIPE_SEGMENTS):
                i_next: int = (i + 1) % PIPE_SEGMENTS
                edge: bmesh.types.BMEdge | None = bm.edges.get(
                    (r_curr[i], r_curr[i_next])
                )
                if edge:
                    edge.smooth = False

    # Mark outer boundary loops sharp
    for boundary_ring in (rings[0], rings[-1]):
        for i in range(PIPE_SEGMENTS):
            i_next: int = (i + 1) % PIPE_SEGMENTS
            edge: bmesh.types.BMEdge | None = bm.edges.get(
                (boundary_ring[i], boundary_ring[i_next])
            )
            if edge:
                edge.smooth = False


def apply_world_box_uvs(bm: bmesh.types.BMesh) -> None:
    uv_layer: bmesh.types.BMLayerItem = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n: Vector = f.normal
        nx: float = abs(n.x)
        ny: float = abs(n.y)
        nz: float = abs(n.z)
        for loop in f.loops:
            co: Vector = loop.vert.co
            if ny >= nx and ny >= nz:
                loop[uv_layer].uv = (co.x, co.z)
            elif nz >= nx and nz >= ny:
                loop[uv_layer].uv = (co.x, co.y)
            else:
                loop[uv_layer].uv = (co.y, co.z)


def finalize_mesh_object(
    name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material
) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    apply_world_box_uvs(bm)

    mesh: bpy.types.Mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    mesh.materials.append(mat)
    obj: bpy.types.Object = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_kit() -> None:
    clear_scene()
    mat: bpy.types.Material = create_rust_material()

    # 1. Pipe_Bay_4m (left bracket + 4 collared pipes)
    bm_bay: bmesh.types.BMesh = bmesh.new()
    append_bracket(bm_bay, 0.0)
    for z_h in PIPE_Z_HEIGHTS:
        append_pipe_with_collar(bm_bay, z_h)
    finalize_mesh_object("Pipe_Bay_4m", bm_bay, mat)

    # 2. Pipe_Bracket_End (standalone cap bracket at origin)
    bm_cap: bmesh.types.BMesh = bmesh.new()
    append_bracket(bm_cap, 0.0)
    obj_cap: bpy.types.Object = finalize_mesh_object(
        "Pipe_Bracket_End", bm_cap, mat
    )
    obj_cap.location = (0.0, 0.0, 0.0)

    os.makedirs(os.path.dirname(EXPORT_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=EXPORT_PATH,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    print(f"Exported Godot pipe kit -> {EXPORT_PATH}")


if __name__ == "__main__":
    build_kit()
