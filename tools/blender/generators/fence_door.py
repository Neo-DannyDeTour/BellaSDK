"""Procedural Blender generator for an industrial metal-frame chain-link fence door.

Builds a two-object articulated hierarchy (FenceDoor_Frame + FenceDoor_Leaf pivoted
on the right +X hinge axis at floor level) with 2.5mm chamfered steel profiles,
diagonal tension rod with turnbuckle sleeve, 3 barrel hinges, twin C-handles with
latch plate, metric box-projected UVs, and a two-sided alpha-scissor chain-link
infill quad.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import create_pbr_material
from mathutils import Matrix, Vector

DOOR_W = 1.00
DOOR_H = 2.10
FRAME_T = 0.04
FRAME_D = 0.06
BEVEL_OFFSET = 0.0025
UV_TILE_METERS = 1.0


def _load_image_if_exists(path: Path) -> bpy.types.Image | None:
    if path.is_file():
        return bpy.data.images.load(str(path.resolve()), check_existing=True)
    return None


def _attach_metallic_image(mat: bpy.types.Material, metallic_image: bpy.types.Image | None) -> None:
    """Connect a grayscale metallic map to Principled BSDF if present."""
    if metallic_image is None or not mat.use_nodes:
        return
    tree = mat.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    if bsdf is None or "Metallic" not in bsdf.inputs:
        return
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = metallic_image
    tex.image.colorspace_settings.name = "Non-Color"
    tex.location = (-400, 150)
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Metallic"])


def _configure_alpha_scissor(mat: bpy.types.Material, threshold: float = 0.5) -> None:
    """Link base-color image Alpha to Principled BSDF Alpha and disable backface culling."""
    mat.use_backface_culling = False
    if hasattr(mat, "blend_method"):
        mat.blend_method = "CLIP"
    if hasattr(mat, "alpha_threshold"):
        mat.alpha_threshold = threshold
    if not mat.use_nodes:
        return
    tree = mat.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    if bsdf is None or "Alpha" not in bsdf.inputs:
        return
    for node in tree.nodes:
        if node.type == "TEX_IMAGE" and node.outputs["Color"].is_linked:
            for link in node.outputs["Color"].links:
                if link.to_socket == bsdf.inputs["Base Color"]:
                    tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
                    return


def _add_beveled_box(
    bm: bmesh.types.BMesh,
    center: Vector,
    size: Vector,
    mat_idx: int = 0,
    bevel: float = BEVEL_OFFSET,
) -> None:
    """Create a box with subtle edge chamfers for realistic specular highlights."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    bmesh.ops.scale(tmp, vec=size, verts=tmp.verts)
    if bevel > 0.0:
        max_bevel = min(size.x, size.y, size.z) * 0.22
        bmesh.ops.bevel(
            tmp,
            geom=list(tmp.edges),
            offset=min(bevel, max_bevel),
            segments=1,
            affect="EDGES",
            clamp_overlap=True,
        )
    bmesh.ops.translate(tmp, vec=center, verts=tmp.verts)
    for face in tmp.faces:
        face.material_index = mat_idx

    mesh_tmp = bpy.data.meshes.new("_tmp_box")
    tmp.to_mesh(mesh_tmp)
    tmp.free()
    bm.from_mesh(mesh_tmp)
    bpy.data.meshes.remove(mesh_tmp)


def _add_cylinder_between(
    bm: bmesh.types.BMesh,
    p1: Vector,
    p2: Vector,
    radius: float,
    segments: int = 8,
    mat_idx: int = 0,
) -> None:
    """Create a capped cylinder connecting p1 to p2."""
    vec = p2 - p1
    length = vec.length
    if length < 1e-6:
        return
    mid = (p1 + p2) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    trans = Matrix.Translation(mid)

    tmp = bmesh.new()
    bmesh.ops.create_cone(
        tmp,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=length,
        matrix=trans @ rot,
    )
    for face in tmp.faces:
        face.material_index = mat_idx

    mesh_tmp = bpy.data.meshes.new("_tmp_cyl")
    tmp.to_mesh(mesh_tmp)
    tmp.free()
    bm.from_mesh(mesh_tmp)
    bpy.data.meshes.remove(mesh_tmp)


def _box_project_uvs(
    bm: bmesh.types.BMesh,
    tile_meters: float,
    mat_filter: int | None = None,
) -> None:
    """Assign metric box-projected UVs across faces (optionally filtered by material_index)."""
    uv_layer = bm.loops.layers.uv.verify()
    scale = 1.0 / tile_meters
    for face in bm.faces:
        if mat_filter is not None and face.material_index != mat_filter:
            continue
        n = face.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            co = loop.vert.co
            if ax == 0:
                u, v = co.y * scale, co.z * scale
            elif ax == 1:
                u, v = co.x * scale, co.z * scale
            else:
                u, v = co.x * scale, co.y * scale
            loop[uv_layer].uv = (u, v)


def build_fence_door(project_root: Path, output_dir: Path) -> dict[str, object]:
    """Generate the articulated fence door GLB and asset manifest."""
    clean_scene()

    metal_dir = project_root / "assets/materials/fence_door_metal/textures"
    chain_dir = project_root / "assets/materials/chain_link_fence/textures"

    mat_metal = create_pbr_material(
        name="M_MetalFrame",
        base_color=(0.24, 0.25, 0.22, 1.0),
        metallic=0.15,
        roughness=0.58,
        base_color_image=_load_image_if_exists(metal_dir / "fence_door_metal_albedo.png"),
        roughness_image=_load_image_if_exists(metal_dir / "fence_door_metal_roughness.png"),
        normal_image=_load_image_if_exists(metal_dir / "fence_door_metal_normal.png"),
        normal_strength=0.75,
    )
    _attach_metallic_image(mat_metal, _load_image_if_exists(metal_dir / "fence_door_metal_metallic.png"))

    mat_chain = create_pbr_material(
        name="M_ChainLink",
        base_color=(0.45, 0.46, 0.45, 1.0),
        metallic=0.85,
        roughness=0.50,
        base_color_image=_load_image_if_exists(chain_dir / "chain_link_fence_albedo.png"),
        roughness_image=_load_image_if_exists(chain_dir / "chain_link_fence_roughness.png"),
        normal_image=_load_image_if_exists(chain_dir / "chain_link_fence_normal.png"),
        normal_strength=1.0,
    )
    _attach_metallic_image(mat_chain, _load_image_if_exists(chain_dir / "chain_link_fence_metallic.png"))
    _configure_alpha_scissor(mat_chain, threshold=0.5)

    # ==========================================
    # 1. STATIC OUTER FRAME (Origin: 0, 0, 0)
    # ==========================================
    bm_frame = bmesh.new()
    # Left Jamb (-X)
    _add_beveled_box(
        bm_frame,
        Vector((-DOOR_W * 0.5 + FRAME_T * 0.5, 0.0, DOOR_H * 0.5)),
        Vector((FRAME_T, FRAME_D, DOOR_H)),
        mat_idx=0,
    )
    # Right Jamb (+X)
    _add_beveled_box(
        bm_frame,
        Vector((DOOR_W * 0.5 - FRAME_T * 0.5, 0.0, DOOR_H * 0.5)),
        Vector((FRAME_T, FRAME_D, DOOR_H)),
        mat_idx=0,
    )
    # Top Header
    _add_beveled_box(
        bm_frame,
        Vector((0.0, 0.0, DOOR_H - FRAME_T * 0.5)),
        Vector((DOOR_W - FRAME_T * 2.0, FRAME_D, FRAME_T)),
        mat_idx=0,
    )
    # Bottom Threshold Sill
    _add_beveled_box(
        bm_frame,
        Vector((0.0, 0.0, FRAME_T * 0.25)),
        Vector((DOOR_W - FRAME_T * 2.0, FRAME_D, FRAME_T * 0.5)),
        mat_idx=0,
    )
    # Latch Strike Plate on inner face of Left Jamb (-X)
    _add_beveled_box(
        bm_frame,
        Vector((-DOOR_W * 0.5 + FRAME_T + 0.002, 0.0, DOOR_H * 0.48 + 0.05)),
        Vector((0.004, 0.032, 0.12)),
        mat_idx=0,
        bevel=0.001,
    )

    bmesh.ops.recalc_face_normals(bm_frame, faces=bm_frame.faces)
    _box_project_uvs(bm_frame, UV_TILE_METERS)
    bmesh.ops.triangulate(bm_frame, faces=bm_frame.faces)
    frame_tris = len(bm_frame.faces)

    mesh_frame = bpy.data.meshes.new("SM_FenceDoor_Frame")
    bm_frame.to_mesh(mesh_frame)
    bm_frame.free()

    obj_frame = bpy.data.objects.new("FenceDoor_Frame", mesh_frame)
    bpy.context.collection.objects.link(obj_frame)
    obj_frame.data.materials.append(mat_metal)

    # ==========================================
    # 2. ROTATABLE DOOR LEAF (Origin: Hinge +X)
    # ==========================================
    hinge_x = DOOR_W * 0.5 - FRAME_T
    gap = 0.008
    leaf_w = (DOOR_W - FRAME_T * 2.0) - gap * 2.0
    leaf_h = (DOOR_H - FRAME_T * 1.5) - gap * 2.0
    leaf_z0 = FRAME_T * 0.5 + gap
    stile_t = 0.035

    x_right = -gap
    x_left = -gap - leaf_w
    x_mid = (x_right + x_left) * 0.5
    z_bot = leaf_z0
    z_top = leaf_z0 + leaf_h
    z_mid = leaf_z0 + leaf_h * 0.48

    bm_leaf = bmesh.new()

    # Right Hinge Stile
    _add_beveled_box(
        bm_leaf,
        Vector((x_right - stile_t * 0.5, 0.0, z_bot + leaf_h * 0.5)),
        Vector((stile_t, stile_t, leaf_h)),
        mat_idx=0,
    )
    # Left Latch Stile
    _add_beveled_box(
        bm_leaf,
        Vector((x_left + stile_t * 0.5, 0.0, z_bot + leaf_h * 0.5)),
        Vector((stile_t, stile_t, leaf_h)),
        mat_idx=0,
    )
    # Top Rail
    inner_w = leaf_w - stile_t * 2.0
    _add_beveled_box(
        bm_leaf,
        Vector((x_mid, 0.0, z_top - stile_t * 0.5)),
        Vector((inner_w, stile_t, stile_t)),
        mat_idx=0,
    )
    # Bottom Rail
    _add_beveled_box(
        bm_leaf,
        Vector((x_mid, 0.0, z_bot + stile_t * 0.5)),
        Vector((inner_w, stile_t, stile_t)),
        mat_idx=0,
    )
    # Center Horizontal Cross-Bar
    _add_beveled_box(
        bm_leaf,
        Vector((x_mid, 0.0, z_mid)),
        Vector((inner_w, stile_t * 0.72, stile_t * 0.72)),
        mat_idx=0,
    )

    # Diagonal Tension Rod (Top-Left latch corner to Bottom-Right hinge corner) + turnbuckle sleeve
    p_tl = Vector((x_left + stile_t, 0.0, z_top - stile_t))
    p_br = Vector((x_right - stile_t, 0.0, z_bot + stile_t))
    _add_cylinder_between(bm_leaf, p_tl, p_br, radius=0.006, segments=8, mat_idx=0)
    rod_mid = (p_tl + p_br) * 0.5
    rod_dir = (p_br - p_tl).normalized()
    _add_cylinder_between(
        bm_leaf,
        rod_mid - rod_dir * 0.055,
        rod_mid + rod_dir * 0.055,
        radius=0.010,
        segments=8,
        mat_idx=0,
    )

    # 3 Barrel Hinges on Right Hinge Axis (X = 0)
    for hz in (z_bot + 0.25, z_mid, z_top - 0.25):
        _add_cylinder_between(
            bm_leaf,
            Vector((0.0, 0.0, hz - 0.042)),
            Vector((0.0, 0.0, hz + 0.042)),
            radius=0.011,
            segments=10,
            mat_idx=0,
        )
        # Small hinge leaf strap connecting barrel to hinge stile
        _add_beveled_box(
            bm_leaf,
            Vector((-gap * 0.5 - 0.004, 0.0, hz)),
            Vector((gap + 0.012, 0.012, 0.04)),
            mat_idx=0,
            bevel=0.001,
        )

    # Twin C-Handles + Mounting Latch Plates on Left Stile (Front -Y and Back +Y)
    handle_x = x_left + stile_t * 0.5
    handle_z1 = z_mid - 0.02
    handle_z2 = z_mid + 0.14
    handle_depth = 0.045
    handle_thick = 0.012

    for side in (-1.0, 1.0):
        y_base = side * (stile_t * 0.5)
        y_out = side * (stile_t * 0.5 + handle_depth)
        # Backplate on stile face
        _add_beveled_box(
            bm_leaf,
            Vector((handle_x, y_base + side * 0.002, (handle_z1 + handle_z2) * 0.5)),
            Vector((0.028, 0.004, (handle_z2 - handle_z1) + 0.055)),
            mat_idx=0,
            bevel=0.001,
        )
        # Top & bottom standoffs
        _add_beveled_box(
            bm_leaf,
            Vector((handle_x, (y_base + y_out) * 0.5, handle_z1)),
            Vector((handle_thick, handle_depth, handle_thick)),
            mat_idx=0,
            bevel=0.002,
        )
        _add_beveled_box(
            bm_leaf,
            Vector((handle_x, (y_base + y_out) * 0.5, handle_z2)),
            Vector((handle_thick, handle_depth, handle_thick)),
            mat_idx=0,
            bevel=0.002,
        )
        # Vertical grip bar
        _add_beveled_box(
            bm_leaf,
            Vector((handle_x, y_out, (handle_z1 + handle_z2) * 0.5)),
            Vector((handle_thick, handle_thick, handle_z2 - handle_z1 + handle_thick)),
            mat_idx=0,
            bevel=0.002,
        )

    # Chain-Link Infill Plane (Material Index 1)
    v1 = bm_leaf.verts.new(Vector((x_left + stile_t, 0.0, z_bot + stile_t)))
    v2 = bm_leaf.verts.new(Vector((x_right - stile_t, 0.0, z_bot + stile_t)))
    v3 = bm_leaf.verts.new(Vector((x_right - stile_t, 0.0, z_top - stile_t)))
    v4 = bm_leaf.verts.new(Vector((x_left + stile_t, 0.0, z_top - stile_t)))
    face_chain = bm_leaf.faces.new((v1, v2, v3, v4))
    face_chain.material_index = 1

    bmesh.ops.recalc_face_normals(bm_leaf, faces=bm_leaf.faces)

    # Metric box UVs on metal faces (slot 0)
    _box_project_uvs(bm_leaf, UV_TILE_METERS, mat_filter=0)

    # Exact tiled UVs on chain-link quad (slot 1): 10x21 tiles (2x2 diamonds/tile -> ~4.5cm mesh)
    uv_layer = bm_leaf.loops.layers.uv.verify()
    for face in bm_leaf.faces:
        if face.material_index == 1:
            face.loops[0][uv_layer].uv = (0.0, 0.0)
            face.loops[1][uv_layer].uv = (10.0, 0.0)
            face.loops[2][uv_layer].uv = (10.0, 21.0)
            face.loops[3][uv_layer].uv = (0.0, 21.0)

    bmesh.ops.triangulate(bm_leaf, faces=bm_leaf.faces)
    leaf_tris = len(bm_leaf.faces)

    mesh_leaf = bpy.data.meshes.new("SM_FenceDoor_Leaf")
    bm_leaf.to_mesh(mesh_leaf)
    bm_leaf.free()

    obj_leaf = bpy.data.objects.new("FenceDoor_Leaf", mesh_leaf)
    obj_leaf.parent = obj_frame
    obj_leaf.location = Vector((hinge_x, 0.0, 0.0))
    bpy.context.collection.objects.link(obj_leaf)
    obj_leaf.data.materials.append(mat_metal)
    obj_leaf.data.materials.append(mat_chain)

    # Compute overall bounding dimensions across both objects in world space
    bpy.context.view_layer.update()
    world_pts: list[Vector] = []
    for obj in (obj_frame, obj_leaf):
        mw = obj.matrix_world
        for v in obj.data.vertices:
            world_pts.append(mw @ v.co)

    xs = [p.x for p in world_pts]
    ys = [p.y for p in world_pts]
    zs = [p.z for p in world_pts]
    dims = {
        "x": round(max(xs) - min(xs), 4),
        "y": round(max(zs) - min(zs), 4),  # Godot Y = Blender Z
        "z": round(max(ys) - min(ys), 4),
    }

    total_tris = frame_tris + leaf_tris
    output_dir.mkdir(parents=True, exist_ok=True)
    glb_path = output_dir / "fence_door.glb"
    export_godot_glb(glb_path, export_animations=False, apply_modifiers=True)

    manifest = {
        "slug": "fence_door",
        "layer": "Layer 3 Interactive",
        "source": "procedural_bpy",
        "tri_count": total_tris,
        "submesh_tris": {
            "FenceDoor_Frame": frame_tris,
            "FenceDoor_Leaf": leaf_tris,
        },
        "uv_layers": min(len(obj_frame.data.uv_layers), len(obj_leaf.data.uv_layers)),
        "dimensions_m": dims,
        "hinge_pivot_local_m": [round(hinge_x, 4), 0.0, 0.0],
        "materials": [
            "res://assets/materials/fence_door_metal/fence_door_metal.tres",
            "res://assets/materials/chain_link_fence/chain_link_fence.tres",
        ],
        "collision_hint": "BoxShape3D (StaticBody3D jambs Layer 1 + AnimatableBody3D leaf Layer 3)",
        "glb_path": "res://assets/models/fence_door/fence_door.glb",
    }
    manifest_path = output_dir / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[fence_door] Exported {glb_path} ({total_tris} tris, dims={dims})")
    return manifest


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate Fence Door GLB")
    parser.add_argument(
        "--output-dir",
        default="assets/models/fence_door",
        help="Output directory relative to project root",
    )
    args = parser.parse_args(argv)
    project_root = Path(__file__).resolve().parent.parent.parent.parent
    out_dir = (project_root / args.output_dir).resolve()
    build_fence_door(project_root, out_dir)


if __name__ == "__main__":
    main()
