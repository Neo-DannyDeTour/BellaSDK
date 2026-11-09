"""Procedural generator for industrial generator trailer prop.

Generates GeneratorTrailer with housing, wheels, tongue, muffler, collision boxes (-colonly)
and exports to assets/models/props/generator_trailer/generator_trailer.glb.
Compatible with Blender 3.6+, 4.x, and 5.x.
"""

from __future__ import annotations

import math
from pathlib import Path
import bmesh
import bpy
from mathutils import Matrix, Vector

SCRIPT_DIR: Path = Path(__file__).resolve().parent
PROJECT_ROOT: Path = SCRIPT_DIR.parents[2]
OUTPUT_DIR: Path = PROJECT_ROOT / "assets" / "models" / "props" / "generator_trailer"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_PATH: str = str(OUTPUT_DIR / "generator_trailer.glb")


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name: str, base_color: tuple, metallic: float, roughness: float) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_box(bm: bmesh.types.BMesh, size: tuple, center: tuple, mat_idx: int, rot_euler: tuple = (0.0, 0.0, 0.0)) -> list:
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    bmesh.ops.scale(bm, vec=size, verts=verts)
    if any(rot_euler):
        rot_mat = Matrix.Rotation(rot_euler[0], 3, 'X') @ Matrix.Rotation(rot_euler[1], 3, 'Y') @ Matrix.Rotation(rot_euler[2], 3, 'Z')
        bmesh.ops.rotate(bm, matrix=rot_mat, verts=verts)
    bmesh.ops.translate(bm, vec=center, verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    for f in faces:
        f.material_index = mat_idx
    return verts


def add_cylinder(bm: bmesh.types.BMesh, radius: float, depth: float, segments: int, center: tuple, mat_idx: int, rot_euler: tuple = (0.0, 0.0, 0.0)) -> list:
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth
    )
    verts = res["verts"]
    if any(rot_euler):
        rot_mat = Matrix.Rotation(rot_euler[0], 3, 'X') @ Matrix.Rotation(rot_euler[1], 3, 'Y') @ Matrix.Rotation(rot_euler[2], 3, 'Z')
        bmesh.ops.rotate(bm, matrix=rot_mat, verts=verts)
    bmesh.ops.translate(bm, vec=center, verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    for f in faces:
        f.material_index = mat_idx
    return verts


def add_wheel_assembly(bm: bmesh.types.BMesh, center: tuple, rot_euler: tuple, mat_rubber: int, mat_yellow: int, mat_metal: int) -> None:
    # Outer tire (dark rubber)
    add_cylinder(bm, radius=0.38, depth=0.22, segments=24, center=center, mat_idx=mat_rubber, rot_euler=rot_euler)
    # Inner yellow steel rim
    add_cylinder(bm, radius=0.23, depth=0.23, segments=24, center=center, mat_idx=mat_yellow, rot_euler=rot_euler)
    # Center dark hub cap
    add_cylinder(bm, radius=0.075, depth=0.25, segments=16, center=center, mat_idx=mat_metal, rot_euler=rot_euler)

    # 6 Lug holes / dark bolts around rim
    rot_mat = Matrix.Rotation(rot_euler[0], 3, 'X') @ Matrix.Rotation(rot_euler[1], 3, 'Y') @ Matrix.Rotation(rot_euler[2], 3, 'Z')
    for i in range(6):
        angle = i * (2.0 * math.pi / 6.0)
        local_offset = Vector((math.cos(angle) * 0.145, math.sin(angle) * 0.145, 0.0))
        world_offset = Vector(center) + (rot_mat @ local_offset)
        add_cylinder(bm, radius=0.02, depth=0.245, segments=8, center=tuple(world_offset), mat_idx=mat_metal, rot_euler=rot_euler)


def add_fender(bm: bmesh.types.BMesh, x_pos: float, y_center: float, z_center: float, mat_idx: int) -> None:
    segments = 10
    radius_inner = 0.41
    radius_outer = 0.435
    width = 0.27
    half_w = width * 0.5

    # Arc from -15 deg to 195 deg around X axis
    start_angle = math.radians(-10.0)
    end_angle = math.radians(190.0)

    ring_verts = []
    for i in range(segments + 1):
        t = i / segments
        ang = start_angle + t * (end_angle - start_angle)
        cy = y_center + math.cos(ang) * radius_inner
        cz = z_center + math.sin(ang) * radius_inner
        cy_out = y_center + math.cos(ang) * radius_outer
        cz_out = z_center + math.sin(ang) * radius_outer

        v_in_l = bm.verts.new((x_pos - half_w, cy, cz))
        v_in_r = bm.verts.new((x_pos + half_w, cy, cz))
        v_out_l = bm.verts.new((x_pos - half_w, cy_out, cz_out))
        v_out_r = bm.verts.new((x_pos + half_w, cy_out, cz_out))
        ring_verts.append((v_in_l, v_in_r, v_out_l, v_out_r))

    faces = []
    for i in range(segments):
        il0, ir0, ol0, or0 = ring_verts[i]
        il1, ir1, ol1, or1 = ring_verts[i + 1]
        faces.append(bm.faces.new((ol0, or0, or1, ol1)))  # Top outer
        faces.append(bm.faces.new((il1, ir1, ir0, il0)))  # Bottom inner
        faces.append(bm.faces.new((il0, ol0, ol1, il1)))  # Left side
        faces.append(bm.faces.new((ir1, or1, or0, ir0)))  # Right side

    # End caps
    il0, ir0, ol0, or0 = ring_verts[0]
    faces.append(bm.faces.new((il0, ir0, or0, ol0)))
    iln, irn, oln, orn = ring_verts[-1]
    faces.append(bm.faces.new((oln, orn, irn, iln)))

    for f in faces:
        f.material_index = mat_idx


def build_generator_mesh(mats: list) -> bpy.types.Object:
    bm = bmesh.new()

    MAT_YELLOW = 0
    MAT_METAL = 1
    MAT_RUBBER = 2

    # 1. Main Housing Box (X: width 0.96, Y: length 1.65, Z: height 1.08, base at Z=0.36)
    housing_verts = add_box(bm, size=(0.96, 1.65, 1.08), center=(0.0, 0.0, 0.90), mat_idx=MAT_YELLOW)
    # Chamfer top X edges of main housing
    top_edges = [
        e for e in bm.edges
        if all(v in housing_verts and v.co.z > 1.40 for v in e.verts)
        and abs(e.verts[0].co.y - e.verts[1].co.y) > 1.0
    ]
    bmesh.ops.bevel(bm, geom=top_edges, offset=0.06, segments=1, profile=0.5, affect='EDGES')

    # 2. Lower Chassis Frame Ledges & Front Bumper Step
    add_box(bm, size=(1.04, 1.70, 0.14), center=(0.0, -0.02, 0.35), mat_idx=MAT_YELLOW)
    # Front heavy step block (left & right bumper extensions shown in ref)
    add_box(bm, size=(0.22, 0.42, 0.18), center=(-0.44, -0.72, 0.37), mat_idx=MAT_YELLOW)
    add_box(bm, size=(0.22, 0.42, 0.18), center=(0.44, -0.72, 0.37), mat_idx=MAT_YELLOW)

    # 3. Side Maintenance Doors & Latches (Left & Right)
    for side in (-1.0, 1.0):
        x_door = side * 0.485
        # Rear double access panels
        add_box(bm, size=(0.025, 0.72, 0.56), center=(x_door, 0.32, 0.96), mat_idx=MAT_YELLOW)
        # Front vertical door panel
        add_box(bm, size=(0.025, 0.42, 0.74), center=(x_door, -0.36, 0.88), mat_idx=MAT_YELLOW)
        # Door latches / handles (dark metal)
        add_box(bm, size=(0.04, 0.08, 0.03), center=(side * 0.495, 0.50, 0.74), mat_idx=MAT_METAL)
        add_box(bm, size=(0.04, 0.08, 0.03), center=(side * 0.495, 0.14, 0.74), mat_idx=MAT_METAL)
        add_box(bm, size=(0.04, 0.03, 0.09), center=(side * 0.495, -0.20, 0.88), mat_idx=MAT_METAL)

    # 4. Roof Exhaust Muffler & Tailpipe
    # Muffler support brackets
    add_box(bm, size=(0.16, 0.06, 0.08), center=(0.0, 0.35, 1.46), mat_idx=MAT_METAL)
    add_box(bm, size=(0.16, 0.06, 0.08), center=(0.0, -0.35, 1.46), mat_idx=MAT_METAL)
    # Main cylindrical muffler along Y axis
    add_cylinder(
        bm, radius=0.11, depth=1.15, segments=16,
        center=(0.0, 0.0, 1.56), mat_idx=MAT_METAL,
        rot_euler=(math.radians(90.0), 0.0, 0.0)
    )
    # Forward protruding exhaust tailpipe
    add_cylinder(
        bm, radius=0.042, depth=0.32, segments=12,
        center=(0.0, -0.66, 1.56), mat_idx=MAT_METAL,
        rot_euler=(math.radians(90.0), 0.08, 0.0)
    )

    # 5. Axle, Road Wheels & Curved Fenders
    axle_y = 0.12
    axle_z = 0.38
    add_cylinder(
        bm, radius=0.045, depth=1.36, segments=12,
        center=(0.0, axle_y, axle_z), mat_idx=MAT_METAL,
        rot_euler=(0.0, math.radians(90.0), 0.0)
    )
    for side in (-1.0, 1.0):
        add_wheel_assembly(
            bm,
            center=(side * 0.61, axle_y, axle_z),
            rot_euler=(0.0, math.radians(90.0), 0.0),
            mat_rubber=MAT_RUBBER,
            mat_yellow=MAT_YELLOW,
            mat_metal=MAT_METAL
        )
        add_fender(bm, x_pos=side * 0.61, y_center=axle_y, z_center=axle_z, mat_idx=MAT_YELLOW)

    # 6. A-Frame Tow Hitch Tongue & Jack Stand (pointing forward toward -Y)
    # Left & Right converging beams
    add_box(
        bm, size=(0.07, 1.18, 0.11),
        center=(-0.21, -1.32, 0.33),
        mat_idx=MAT_YELLOW,
        rot_euler=(0.0, 0.0, math.radians(-17.5))
    )
    add_box(
        bm, size=(0.07, 1.18, 0.11),
        center=(0.21, -1.32, 0.33),
        mat_idx=MAT_YELLOW,
        rot_euler=(0.0, 0.0, math.radians(17.5))
    )
    # Hitch nose coupler + towing eye
    add_box(bm, size=(0.16, 0.22, 0.12), center=(0.0, -1.88, 0.33), mat_idx=MAT_METAL)
    add_cylinder(bm, radius=0.07, depth=0.05, segments=12, center=(0.0, -2.02, 0.33), mat_idx=MAT_METAL)

    # Vertical Jack Post + Crossbar + Footplate + Diagonal Strut
    add_box(bm, size=(0.055, 0.055, 0.44), center=(0.0, -1.38, 0.22), mat_idx=MAT_YELLOW)
    add_box(bm, size=(0.26, 0.04, 0.04), center=(0.0, -1.38, 0.12), mat_idx=MAT_YELLOW)
    add_box(bm, size=(0.14, 0.18, 0.025), center=(0.0, -1.38, 0.0125), mat_idx=MAT_METAL)
    add_box(
        bm, size=(0.045, 0.46, 0.045),
        center=(0.0, -1.18, 0.22),
        mat_idx=MAT_YELLOW,
        rot_euler=(math.radians(-38.0), 0.0, 0.0)
    )

    # 7. Front-Mounted Spare Tire + Retaining Brackets
    spare_center = (0.0, -0.97, 0.88)
    spare_rot = (math.radians(82.0), 0.0, 0.0)
    add_wheel_assembly(
        bm,
        center=spare_center,
        rot_euler=spare_rot,
        mat_rubber=MAT_RUBBER,
        mat_yellow=MAT_YELLOW,
        mat_metal=MAT_METAL
    )
    # Upper angled retaining clamp bracket over top-left of spare tire (as seen in ref)
    add_box(
        bm, size=(0.09, 0.28, 0.04),
        center=(-0.14, -0.94, 1.23),
        mat_idx=MAT_METAL,
        rot_euler=(math.radians(15.0), math.radians(22.0), math.radians(-25.0))
    )
    # Lower twin support rods holding spare tire to A-frame base
    for side in (-1.0, 1.0):
        add_box(
            bm, size=(0.035, 0.34, 0.035),
            center=(side * 0.06, -1.02, 0.46),
            mat_idx=MAT_METAL,
            rot_euler=(math.radians(58.0), 0.0, 0.0)
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("Generator_Mesh")
    for m in mats:
        mesh.materials.append(m)
    bm.to_mesh(mesh)
    bm.free()

    # Smooth normals with sharp angle threshold
    for poly in mesh.polygons:
        poly.use_smooth = True
    if hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = math.radians(42.0)

    obj = bpy.data.objects.new("Generator_Mesh", mesh)
    bpy.context.collection.objects.link(obj)

    # Auto-smooth modifier for Blender 4.1+ / 5.x
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if not hasattr(mesh, "use_auto_smooth"):
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(42.0))
        except Exception:
            pass

    # Smart UV Project
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)

    return obj


def add_collision_box(name: str, size: tuple, center: tuple, parent: bpy.types.Object) -> bpy.types.Object:
    bm = bmesh.new()
    res = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=res["verts"])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    col_obj = bpy.data.objects.new(name, mesh)
    col_obj.location = center
    col_obj.parent = parent
    bpy.context.collection.objects.link(col_obj)
    return col_obj


def main() -> None:
    clear_scene()

    # Create root node (Godot root Node3D)
    root = bpy.data.objects.new("GeneratorTrailer", None)
    bpy.context.collection.objects.link(root)

    # Create 3 Principled BSDF materials
    mat_yellow = make_material("Mat_YellowBody", (0.76, 0.47, 0.12, 1.0), metallic=0.15, roughness=0.65)
    mat_metal = make_material("Mat_DarkMetal", (0.18, 0.16, 0.14, 1.0), metallic=0.80, roughness=0.55)
    mat_rubber = make_material("Mat_TireRubber", (0.07, 0.07, 0.07, 1.0), metallic=0.0, roughness=0.88)

    # Build visual mesh
    vis_obj = build_generator_mesh([mat_yellow, mat_metal, mat_rubber])
    vis_obj.parent = root

    # Build Godot -colonly primitives
    # 1. Main housing + wheels + muffler bounding box
    add_collision_box(
        name="Col_Housing-colonly",
        size=(1.48, 1.72, 1.66),
        center=(0.0, 0.0, 0.83),
        parent=root
    )
    # 2. Front spare tire + A-frame tow hitch + jack stand bounding box
    add_collision_box(
        name="Col_Tongue-colonly",
        size=(0.82, 1.24, 1.26),
        center=(0.0, -1.44, 0.63),
        parent=root
    )

    # Export to GLB (Y-Up conversion enabled for Godot)
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_PATH,
        export_format='GLB',
        export_yup=True,
        export_apply=True
    )
    print(f"Exported Godot GLB: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
