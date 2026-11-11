import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

EXPORT_DIR: str = "/home/dkd/Documents/BellaSDK/interactables"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)


def make_pbr_mat(
    name: str,
    base_color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
    emission: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 1.0),
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emission
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def assign_mat_index(bm: bmesh.types.BMesh, faces: list[bmesh.types.BMFace], idx: int) -> None:
    for f in faces:
        f.material_index = idx


def add_box(
    bm: bmesh.types.BMesh,
    size: tuple[float, float, float],
    center: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rot_euler: tuple[float, float, float] = (0.0, 0.0, 0.0),
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    mat_rot = (
        Matrix.Rotation(rot_euler[0], 4, "X")
        @ Matrix.Rotation(rot_euler[1], 4, "Y")
        @ Matrix.Rotation(rot_euler[2], 4, "Z")
    )
    mat_scale = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    mat_trans = Matrix.Translation(center)
    bmesh.ops.transform(bm, matrix=mat_trans @ mat_rot @ mat_scale, verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    assign_mat_index(bm, faces, mat_idx)
    return faces


def add_cylinder(
    bm: bmesh.types.BMesh,
    r1: float,
    r2: float,
    depth: float,
    segments: int = 16,
    center: tuple[float, float, float] = (0.0, 0.0, 0.0),
    rot_euler: tuple[float, float, float] = (0.0, 0.0, 0.0),
    mat_idx: int = 0,
    cap_ends: bool = True,
) -> list[bmesh.types.BMFace]:
    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=r1,
        radius2=r2,
        depth=depth,
    )
    verts = ret["verts"]
    mat_rot = (
        Matrix.Rotation(rot_euler[0], 4, "X")
        @ Matrix.Rotation(rot_euler[1], 4, "Y")
        @ Matrix.Rotation(rot_euler[2], 4, "Z")
    )
    mat_trans = Matrix.Translation(center)
    bmesh.ops.transform(bm, matrix=mat_trans @ mat_rot, verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    assign_mat_index(bm, faces, mat_idx)
    return faces


def build_energy_cell(
    mat_core: bpy.types.Material,
    mat_metal: bpy.types.Material,
) -> bpy.types.Object:
    """
    Godot bounds: r=0.25, h=1.0 (Z in [-0.5, 0.5] in Blender -> Y in [-0.5, 0.5] in Godot).
    Slot 0 = Core (energy_cell_fill.gdshader), Slot 1 = Rusted Metal frame.
    """
    mesh = bpy.data.meshes.new("EnergyCellMesh")
    mesh.materials.append(mat_core)   # Surface 0: Shader material target
    mesh.materials.append(mat_metal)  # Surface 1: Rusted cage & caps

    bm = bmesh.new()

    # 1. Core Cylinder (Slot 0): spans full [-0.5, 0.5] height so shader min/max_height match
    add_cylinder(bm, r1=0.205, r2=0.205, depth=0.98, segments=16, center=(0, 0, 0), mat_idx=0)

    # 2. Bottom Cap (Slot 1): Z from -0.50 to -0.36
    add_cylinder(bm, r1=0.22, r2=0.24, depth=0.04, segments=16, center=(0, 0, -0.48), mat_idx=1)
    add_cylinder(bm, r1=0.245, r2=0.245, depth=0.08, segments=16, center=(0, 0, -0.42), mat_idx=1)
    add_cylinder(bm, r1=0.24, r2=0.22, depth=0.03, segments=16, center=(0, 0, -0.365), mat_idx=1)

    # 3. Top Cap + Terminal Nub (Slot 1): Z from 0.34 to 0.50
    add_cylinder(bm, r1=0.22, r2=0.245, depth=0.04, segments=16, center=(0, 0, 0.36), mat_idx=1)
    add_cylinder(bm, r1=0.245, r2=0.23, depth=0.06, segments=16, center=(0, 0, 0.41), mat_idx=1)
    add_cylinder(bm, r1=0.16, r2=0.14, depth=0.03, segments=16, center=(0, 0, 0.455), mat_idx=1)
    add_cylinder(bm, r1=0.075, r2=0.075, depth=0.04, segments=12, center=(0, 0, 0.48), mat_idx=1)

    # 4. Horizontal Retain Rings (Slot 1)
    add_cylinder(bm, r1=0.248, r2=0.248, depth=0.035, segments=16, center=(0, 0, -0.33), mat_idx=1)
    add_cylinder(bm, r1=0.248, r2=0.248, depth=0.035, segments=16, center=(0, 0, 0.33), mat_idx=1)

    # 5. 4 Vertical Cage Bars + Top Curved Shoulders (Slot 1)
    bar_angles = [math.radians(45 + i * 90) for i in range(4)]
    bar_radius = 0.238
    for angle in bar_angles:
        bx = math.cos(angle) * bar_radius
        by = math.sin(angle) * bar_radius
        # Vertical strut
        add_cylinder(
            bm, r1=0.014, r2=0.014, depth=0.78, segments=8,
            center=(bx, by, -0.02), mat_idx=1
        )
        # Angled top shoulder strut into terminal collar
        sx = math.cos(angle) * 0.165
        sy = math.sin(angle) * 0.165
        add_box(
            bm, size=(0.024, 0.16, 0.024),
            center=(sx, sy, 0.425),
            rot_euler=(math.radians(22), 0.0, angle - math.radians(90)),
            mat_idx=1,
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("EnergyCell", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_wall_generator(
    mat_body: bpy.types.Material,
    mat_steel: bpy.types.Material,
    mat_copper: bpy.types.Material,
    mat_hazard: bpy.types.Material,
    mat_red_ind: bpy.types.Material,
    mat_green_ind: bpy.types.Material,
) -> bpy.types.Object:
    """
    Expanded WallGenerator bounds:
    Width = 1.0m (X in [-0.5, 0.5])
    Depth = 0.5m (Y in [-0.25, 0.25] in Blender)
    Height = 1.85m (Z in [-0.75, 1.10] in Blender -> Y in [-0.75, 1.10] in Godot).
    Socket center: (0, -0.25, 0) in Blender -> (0, 0, 0.25) in Godot.
    Clear bay clearance: Z in [-0.52, 0.54] (1.06m height) with zero clipping on 1.0m EnergyCell.
    """
    mesh = bpy.data.meshes.new("WallGeneratorMesh")
    mesh.materials.append(mat_body)       # 0: Greenish rusted cast iron
    mesh.materials.append(mat_steel)      # 1: Dark rusted steel trim/brackets
    mesh.materials.append(mat_copper)     # 2: Copper leaf-spring contacts
    mesh.materials.append(mat_hazard)     # 3: Hazard stripe plate
    mesh.materials.append(mat_red_ind)    # 4: Red status button (Right)
    mesh.materials.append(mat_green_ind)  # 5: Green status button (Left)

    bm = bmesh.new()

    # 1. Backplate against wall (Z from -0.75 to +1.05 = 1.80m height, center Z = 0.15)
    add_box(bm, size=(1.0, 0.08, 1.80), center=(0.0, 0.21, 0.15), mat_idx=0)

    # 2. Left & Right Side Walls (Z from -0.70 to +1.02 = 1.72m height, center Z = 0.16)
    # Leaves central bay X in [-0.30, 0.30] open (0.60m wide, cell is 0.496m)
    add_box(bm, size=(0.20, 0.36, 1.72), center=(-0.40, -0.01, 0.16), mat_idx=0)
    add_box(bm, size=(0.20, 0.36, 1.72), center=(0.40, -0.01, 0.16), mat_idx=0)

    # Side recessed louver vents
    for side in (-1.0, 1.0):
        add_box(bm, size=(0.03, 0.22, 0.32), center=(side * 0.495, -0.02, -0.25), mat_idx=1)
        add_box(bm, size=(0.03, 0.22, 0.32), center=(side * 0.495, -0.02, 0.35), mat_idx=1)

    # 3. Bottom Tray / Cradle Pedestal (Z in [-0.75, -0.52], center Z = -0.635)
    add_box(bm, size=(0.96, 0.50, 0.23), center=(0.0, 0.0, -0.635), mat_idx=0)
    # Front lip under Z = -0.52
    add_box(bm, size=(0.76, 0.06, 0.08), center=(0.0, -0.23, -0.54), mat_idx=1)
    # Circular cell seat cradle at Z = -0.52 (cell bottom cap rests here at Z = -0.50)
    add_cylinder(bm, r1=0.24, r2=0.25, depth=0.04, segments=16, center=(0.0, -0.21, -0.52), mat_idx=1)

    # 4. Upper Slanted Control Hood (Z in [0.54, 1.06], clear above cell top Z = 0.50)
    # Main upper enclosure block
    add_box(bm, size=(0.94, 0.40, 0.50), center=(0.0, 0.03, 0.80), mat_idx=0)
    # Slanted front visor / hazard panel (Z in [0.60, 0.98])
    add_box(
        bm, size=(0.86, 0.12, 0.40),
        center=(0.0, -0.18, 0.78),
        rot_euler=(math.radians(-14), 0.0, 0.0),
        mat_idx=3,
    )
    # Top Socket Receiver Collar directly above (0, -0.25, 0.50)
    # Under-hood collar receiving cell top terminal nub at Z = 0.53
    add_box(bm, size=(0.64, 0.32, 0.06), center=(0.0, -0.12, 0.54), mat_idx=1)
    add_cylinder(bm, r1=0.11, r2=0.13, depth=0.05, segments=16, center=(0.0, -0.22, 0.535), mat_idx=1)

    # 5. Dual Reactive Indicator Buttons on Slanted Hood (Left: Green Online, Right: Red Fault/Offline)
    # Left button (Mat 5: Green)
    add_cylinder(
        bm, r1=0.055, r2=0.06, depth=0.04, segments=12,
        center=(-0.20, -0.24, 0.80),
        rot_euler=(math.radians(76), 0.0, 0.0),
        mat_idx=1,
    )
    add_cylinder(
        bm, r1=0.038, r2=0.038, depth=0.05, segments=12,
        center=(-0.20, -0.25, 0.80),
        rot_euler=(math.radians(76), 0.0, 0.0),
        mat_idx=5,
    )

    # Right button (Mat 4: Red)
    add_cylinder(
        bm, r1=0.055, r2=0.06, depth=0.04, segments=12,
        center=(0.20, -0.24, 0.80),
        rot_euler=(math.radians(76), 0.0, 0.0),
        mat_idx=1,
    )
    add_cylinder(
        bm, r1=0.038, r2=0.038, depth=0.05, segments=12,
        center=(0.20, -0.25, 0.80),
        rot_euler=(math.radians(76), 0.0, 0.0),
        mat_idx=4,
    )

    # 6. Copper Leaf-Spring Contacts inside Bay (X = -0.15, +0.15, Z in [-0.40, 0.30])
    for cx in (-0.15, 0.15):
        # Upper vertical leaf
        add_box(bm, size=(0.06, 0.02, 0.44), center=(cx, 0.13, 0.05), mat_idx=2)
        # Bowed lower contact tongue
        add_box(
            bm, size=(0.06, 0.02, 0.28),
            center=(cx, 0.06, -0.26),
            rot_euler=(math.radians(24), 0.0, 0.0),
            mat_idx=2,
        )
        # Base clamp foot
        add_box(bm, size=(0.08, 0.12, 0.03), center=(cx, 0.0, -0.48), mat_idx=2)

    # 7. Hinged Side Retaining Clamps (wrapping outer side of bay at Z = 0.0)
    for side in (-1.0, 1.0):
        add_box(bm, size=(0.06, 0.22, 0.09), center=(side * 0.28, -0.10, 0.0), mat_idx=1)

    # 8. Corner Mounting Bolts
    for bx in (-0.44, 0.44):
        for bz in (-0.68, 0.98):
            add_cylinder(
                bm, r1=0.025, r2=0.025, depth=0.04, segments=6,
                center=(bx, 0.16, bz),
                rot_euler=(math.radians(90), 0.0, 0.0),
                mat_idx=1,
            )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("WallGenerator", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def export_glb(obj: bpy.types.Object, filepath: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    orig_loc = obj.location.copy()
    obj.location = (0.0, 0.0, 0.0)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        use_selection=True,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    obj.location = orig_loc


def main() -> None:
    clear_scene()

    mat_core = make_pbr_mat(
        "Mat_CellCore",
        base_color=(0.85, 0.08, 0.08, 1.0),
        metallic=0.0,
        roughness=0.15,
        emission=(0.9, 0.1, 0.1, 1.0),
        emission_strength=2.5,
    )
    mat_rusted_steel = make_pbr_mat(
        "Mat_RustedSteel",
        base_color=(0.22, 0.15, 0.11, 1.0),
        metallic=0.75,
        roughness=0.82,
    )
    mat_gen_body = make_pbr_mat(
        "Mat_GenBody",
        base_color=(0.14, 0.19, 0.16, 1.0),
        metallic=0.65,
        roughness=0.78,
    )
    mat_copper = make_pbr_mat(
        "Mat_Copper",
        base_color=(0.72, 0.36, 0.18, 1.0),
        metallic=0.90,
        roughness=0.42,
    )
    mat_hazard = make_pbr_mat(
        "Mat_HazardPanel",
        base_color=(0.48, 0.34, 0.14, 1.0),
        metallic=0.45,
        roughness=0.75,
    )
    # Red status button (Surface 4) - initial glow on (fault/empty state)
    mat_red_ind = make_pbr_mat(
        "Mat_IndicatorRed",
        base_color=(0.95, 0.08, 0.08, 1.0),
        metallic=0.2,
        roughness=0.2,
        emission=(1.0, 0.08, 0.08, 1.0),
        emission_strength=3.0,
    )
    # Green status button (Surface 5) - initial unlit (turns on when charged cell inserted)
    mat_green_ind = make_pbr_mat(
        "Mat_IndicatorGreen",
        base_color=(0.15, 0.95, 0.25, 1.0),
        metallic=0.2,
        roughness=0.2,
        emission=(0.15, 0.95, 0.25, 1.0),
        emission_strength=0.0,
    )

    cell_obj = build_energy_cell(mat_core, mat_rusted_steel)
    gen_obj = build_wall_generator(
        mat_gen_body, mat_rusted_steel, mat_copper, mat_hazard, mat_red_ind, mat_green_ind
    )

    # Offset EnergyCell in viewport so both can be inspected side-by-side
    cell_obj.location = (1.0, 0.0, 0.0)

    if EXPORT_DIR and os.path.isdir(EXPORT_DIR):
        export_glb(cell_obj, os.path.join(EXPORT_DIR, "energy_cell.glb"))
        export_glb(gen_obj, os.path.join(EXPORT_DIR, "wall_generator.glb"))


if __name__ == "__main__":
    main()
