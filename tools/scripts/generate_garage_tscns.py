"""Generates clean Godot 4.7 .tscn prefab scenes for the Old Garage asset pack.

Zero guessed uid:// strings; Godot assigns/resolves UIDs cleanly on --import.
"""

from __future__ import annotations

import os

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def write_file(rel_path: str, content: str) -> None:
    full = os.path.join(REPO_ROOT, rel_path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as fh:
        fh.write(content.lstrip("\n"))


def make_static_box_prop(
    rel_tscn: str,
    node_name: str,
    glb_res: str,
    box_size: tuple[float, float, float],
    box_center: tuple[float, float, float],
    col_layer: int = 1,
    mat_override: str | None = None,
) -> None:
    sx, sy, sz = box_size
    cx, cy, cz = box_center
    ext_lines = [f'[ext_resource type="PackedScene" path="{glb_res}" id="1_glb"]']
    if mat_override:
        ext_lines.append(f'[ext_resource type="Material" path="{mat_override}" id="2_mat"]')
    ext_block = "\n".join(ext_lines)
    load_steps = 3 if mat_override else 2
    content = f"""
[gd_scene load_steps={load_steps} format=3]

{ext_block}

[sub_resource type="BoxShape3D" id="BoxShape3D_1"]
size = Vector3({sx}, {sy}, {sz})

[node name="{node_name}" type="StaticBody3D"]
collision_layer = {col_layer}
collision_mask = 0

[node name="Model" parent="." instance=ExtResource("1_glb")]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {cx}, {cy}, {cz})
shape = SubResource("BoxShape3D_1")
"""
    write_file(rel_tscn, content)


def make_visual_only_prop(rel_tscn: str, node_name: str, glb_res: str) -> None:
    content = f"""
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="{glb_res}" id="1_glb"]

[node name="{node_name}" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_glb")]
"""
    write_file(rel_tscn, content)


def make_decal_scene(
    rel_tscn: str,
    node_name: str,
    tex_res: str,
    size: tuple[float, float, float],
    modulate: tuple[float, float, float, float] = (1.0, 1.0, 1.0, 0.9),
) -> None:
    sx, sy, sz = size
    r, g, b, a = modulate
    content = f"""
[gd_scene load_steps=2 format=3]

[ext_resource type="Texture2D" path="{tex_res}" id="1_tex"]

[node name="{node_name}" type="Decal"]
size = Vector3({sx}, {sy}, {sz})
texture_albedo = ExtResource("1_tex")
modulate = Color({r}, {g}, {b}, {a})
upper_fade = 0.2
lower_fade = 0.2
cull_mask = 1
"""
    write_file(rel_tscn, content)


def main() -> None:
    # --- Wave 1A: Grate Floors, Separate Gusset, Handrails, Broken Stairs ---
    make_static_box_prop(
        "props/garage_structure/grate_floor_2x1_2m.tscn",
        "GrateFloor2x1_2m",
        "res://assets/models/garage_structure/grate_floor_2x1_2m.glb",
        (2.0, 0.10, 1.2),
        (0.0, -0.05, 0.0),
    )
    make_static_box_prop(
        "props/garage_structure/grate_floor_2x2m.tscn",
        "GrateFloor2x2m",
        "res://assets/models/garage_structure/grate_floor_2x2m.glb",
        (2.0, 0.10, 2.0),
        (0.0, -0.05, 0.0),
    )
    make_static_box_prop(
        "props/garage_structure/grate_floor_1x1_2m.tscn",
        "GrateFloor1x1_2m",
        "res://assets/models/garage_structure/grate_floor_1x1_2m.glb",
        (1.0, 0.10, 1.2),
        (0.0, -0.05, 0.0),
    )
    make_static_box_prop(
        "props/garage_structure/grate_floor_damaged_2x1_2m.tscn",
        "GrateFloorDamaged2x1_2m",
        "res://assets/models/garage_structure/grate_floor_damaged_2x1_2m.glb",
        (1.1, 0.10, 1.2),
        (-0.45, -0.05, 0.0),
    )
    make_static_box_prop(
        "props/garage_structure/grate_gusset_triangle.tscn",
        "GrateGussetTriangle",
        "res://assets/models/garage_structure/grate_gusset_triangle.glb",
        (0.10, 0.55, 0.65),
        (0.0, -0.275, 0.325),
    )
    for slug, name in (
        ("handrail_pipe_2m", "HandrailPipe2m"),
        ("handrail_flatbar_2m", "HandrailFlatbar2m"),
        ("handrail_mesh_2m", "HandrailMesh2m"),
        ("handrail_bent_damaged_2m", "HandrailBentDamaged2m"),
    ):
        make_static_box_prop(
            f"props/garage_structure/{slug}.tscn",
            name,
            f"res://assets/models/garage_structure/{slug}.glb",
            (2.0, 1.05, 0.12),
            (0.0, 0.525, 0.0),
        )
    make_static_box_prop(
        "props/garage_structure/handrail_post_corner.tscn",
        "HandrailPostCorner",
        "res://assets/models/garage_structure/handrail_post_corner.glb",
        (0.13, 1.05, 0.13),
        (0.0, 0.525, 0.0),
    )
    # Broken Metal Stairs (\_ shape) with angled ramp + flat collapsed lower collider
    write_file(
        "props/garage_structure/broken_metal_stairs_lshape.tscn",
        """
[gd_scene load_steps=4 format=3]

[ext_resource type="PackedScene" path="res://assets/models/garage_structure/broken_metal_stairs_lshape.glb" id="1_glb"]

[sub_resource type="BoxShape3D" id="BoxShape3D_upper"]
size = Vector3(1.24, 0.22, 2.55)

[sub_resource type="BoxShape3D" id="BoxShape3D_lower"]
size = Vector3(1.24, 0.22, 1.25)

[node name="BrokenMetalStairsLShape" type="StaticBody3D"]
collision_layer = 1
collision_mask = 0

[node name="Model" parent="." instance=ExtResource("1_glb")]

[node name="Col_UpperRamp" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.71, -0.704, 0, 0.704, 0.71, 0, 1.12, 0.6)
shape = SubResource("BoxShape3D_upper")

[node name="Col_LowerCollapsed" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.14, -0.9)
shape = SubResource("BoxShape3D_lower")
""",
    )

    # --- Wave 1B: Chest-Clipped L-Flashlight, Gas Lamp, Ammo Box Props ---
    write_file(
        "props/flashlight_angled/flashlight_angled.tscn",
        """
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://assets/models/flashlight_angled/flashlight_angled.glb" id="1_glb"]

[sub_resource type="BoxShape3D" id="BoxShape3D_1"]
size = Vector3(0.06, 0.16, 0.065)

[node name="FlashlightAngled" type="Node3D"]

[node name="ClipPivot" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.09, -0.025)

[node name="Model" parent="ClipPivot" instance=ExtResource("1_glb")]

[node name="BeamLight" type="SpotLight3D" parent="ClipPivot"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.135, -0.035)
visible = false
light_color = Color(1, 0.96, 0.88, 1)
light_energy = 4.0
spot_range = 18.0
spot_angle = 32.0

[node name="PickupBody" type="StaticBody3D" parent="ClipPivot"]
collision_layer = 4
collision_mask = 0

[node name="CollisionShape3D" type="CollisionShape3D" parent="ClipPivot/PickupBody"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.08, 0)
shape = SubResource("BoxShape3D_1")
""",
    )

    write_file(
        "props/gas_lamp/gas_lamp.tscn",
        """
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://assets/models/gas_lamp/gas_lamp.glb" id="1_glb"]

[sub_resource type="CylinderShape3D" id="CylinderShape3D_1"]
height = 0.34
radius = 0.095

[node name="GasLamp" type="StaticBody3D"]
collision_layer = 4
collision_mask = 0

[node name="Model" parent="." instance=ExtResource("1_glb")]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.17, 0)
shape = SubResource("CylinderShape3D_1")

[node name="FlameLight" type="OmniLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.17, 0)
light_color = Color(1, 0.68, 0.32, 1)
light_energy = 2.2
shadow_enabled = false
omni_range = 5.5
omni_attenuation = 1.4
""",
    )

    make_static_box_prop(
        "props/ammo_box/ammo_box_30cal.tscn",
        "AmmoBox30Cal",
        "res://assets/models/ammo_box/ammo_box_30cal.glb",
        (0.28, 0.18, 0.10),
        (0.0, 0.09, 0.0),
        col_layer=4,
    )
    make_static_box_prop(
        "props/ammo_box/ammo_box_50cal.tscn",
        "AmmoBox50Cal",
        "res://assets/models/ammo_box/ammo_box_50cal.glb",
        (0.30, 0.21, 0.15),
        (0.0, 0.105, 0.0),
        col_layer=4,
    )

    # --- Wave 2A: Pipe Kit Extensions ---
    pipe_specs = [
        ("pipe_t_junction", "PipeTJunction", (1.6, 0.85, 0.55), (0.0, 0.35, 0.0)),
        ("pipe_cross_4way", "PipeCross4Way", (1.6, 1.6, 0.55), (0.0, 0.0, 0.0)),
        ("pipe_valve_wheel", "PipeValveWheel", (1.4, 0.95, 0.90), (0.0, 0.0, 0.35)),
        ("pipe_reducer", "PipeReducer", (0.55, 0.50, 0.55), (0.0, 0.25, 0.0)),
        ("pipe_wall_bracket", "PipeWallBracket", (0.95, 0.12, 0.65), (0.0, 0.0, 0.32)),
        ("pipe_broken_end", "PipeBrokenEnd", (0.55, 0.62, 0.55), (0.0, 0.31, 0.0)),
        ("pipe_thin_straight_2m", "PipeThinStraight2m", (0.30, 2.0, 0.30), (0.0, 1.0, 0.0)),
        ("pipe_thin_bend_90", "PipeThinBend90", (0.45, 0.45, 0.30), (0.15, 0.15, 0.0)),
    ]
    for slug, name, bsize, bctr in pipe_specs:
        make_static_box_prop(
            f"props/pipes/{slug}.tscn",
            name,
            f"res://assets/models/pipes/{slug}.glb",
            bsize,
            bctr,
            col_layer=1,
        )

    # --- Wave 2A: Cables ---
    for slug, name in (
        ("cable_fence_draped_a", "CableFenceDrapedA"),
        ("cable_fence_draped_b", "CableFenceDrapedB"),
        ("cable_wall_bundle_2m", "CableWallBundle2m"),
        ("cable_wall_bundle_4m", "CableWallBundle4m"),
        ("cable_floor_coil_large", "CableFloorCoilLarge"),
        ("cable_floor_coil_plug", "CableFloorCoilPlug"),
    ):
        make_visual_only_prop(f"props/garage_cables/{slug}.tscn", name, f"res://assets/models/garage_cables/{slug}.glb")

    # --- Wave 2A: Tables, Gears, Little Boxes, Toolboxes, Tools ---
    make_static_box_prop("props/garage_tables/workbench_steel_1_8m.tscn", "WorkbenchSteel1_8m", "res://assets/models/garage_tables/workbench_steel_1_8m.glb", (1.8, 0.88, 0.78), (0.0, 0.44, 0.0))
    make_static_box_prop("props/garage_tables/garage_table_rusty_1_2m.tscn", "GarageTableRusty1_2m", "res://assets/models/garage_tables/garage_table_rusty_1_2m.glb", (1.2, 0.78, 0.65), (0.0, 0.39, 0.0))

    for slug, name in (
        ("gear_large", "GearLarge"),
        ("gear_medium", "GearMedium"),
        ("gear_small", "GearSmall"),
        ("gear_cluster_a", "GearClusterA"),
    ):
        make_visual_only_prop(f"props/garage_gears/{slug}.tscn", name, f"res://assets/models/garage_gears/{slug}.glb")

    make_static_box_prop("props/little_boxes/parts_bin_metal.tscn", "PartsBinMetal", "res://assets/models/little_boxes/parts_bin_metal.glb", (0.34, 0.16, 0.24), (0.0, 0.08, 0.0), col_layer=4)
    make_static_box_prop("props/little_boxes/small_steel_box.tscn", "SmallSteelBox", "res://assets/models/little_boxes/small_steel_box.glb", (0.33, 0.145, 0.23), (0.0, 0.0725, 0.0), col_layer=4)
    make_static_box_prop("props/little_boxes/small_wood_box.tscn", "SmallWoodBox", "res://assets/models/little_boxes/small_wood_box.glb", (0.38, 0.18, 0.30), (0.0, 0.09, 0.0), col_layer=4)

    make_static_box_prop("props/toolbox/toolbox_portable.tscn", "ToolboxPortable", "res://assets/models/toolbox/toolbox_portable.glb", (0.49, 0.28, 0.225), (0.0, 0.14, 0.0), col_layer=4)
    make_static_box_prop("props/toolbox/tool_cabinet_rolling.tscn", "ToolCabinetRolling", "res://assets/models/toolbox/tool_cabinet_rolling.glb", (0.98, 0.985, 0.50), (0.0, 0.49, 0.0), col_layer=1)

    for slug, name in (
        ("wrench_adjustable", "WrenchAdjustable"),
        ("spanner_open", "SpannerOpen"),
        ("screwdriver", "Screwdriver"),
        ("broom_old", "BroomOld"),
    ):
        make_visual_only_prop(f"props/garage_tools/{slug}.tscn", name, f"res://assets/models/garage_tools/{slug}.glb")

    # --- Wave 2B: Hero Props (Car Engine, Mattress) ---
    make_static_box_prop("props/car_engine_v8/car_engine_v8.tscn", "CarEngineV8", "res://assets/models/car_engine_v8/car_engine_v8.glb", (0.86, 0.78, 1.02), (0.0, 0.39, 0.0), col_layer=1)
    make_static_box_prop("props/old_mattress/old_mattress.tscn", "OldMattress", "res://assets/models/old_mattress/old_mattress.glb", (0.95, 0.22, 1.92), (0.0, 0.11, 0.0), col_layer=1)

    # --- Wave 2C: Atmosphere Extras (Decals, Cobwebs, Indicators, Debris, Bollard) ---
    make_decal_scene("props/garage_decals/decal_oil_slick.tscn", "DecalOilSlick", "res://assets/decals/garage/oil_slick.png", (1.6, 0.4, 1.6), (0.15, 0.14, 0.13, 0.88))
    make_decal_scene("props/garage_decals/decal_wet_puddle.tscn", "DecalWetPuddle", "res://assets/decals/garage/wet_puddle.png", (2.2, 0.4, 1.8), (0.30, 0.34, 0.36, 0.65))
    make_decal_scene("props/garage_decals/decal_rust_streak.tscn", "DecalRustStreak", "res://assets/decals/garage/rust_streak.png", (1.4, 0.4, 2.0), (0.72, 0.44, 0.26, 0.78))
    make_decal_scene("props/garage_decals/decal_wall_grime.tscn", "DecalWallGrime", "res://assets/decals/garage/wall_grime.png", (2.4, 0.5, 2.2), (0.28, 0.30, 0.24, 0.72))

    for slug, name in (
        ("cobweb_corner", "CobwebCorner"),
        ("cobweb_drape", "CobwebDrape"),
        ("cobweb_fence", "CobwebFence"),
    ):
        make_visual_only_prop(f"props/cobwebs/{slug}.tscn", name, f"res://assets/models/cobwebs/{slug}.glb")

    write_file(
        "props/garage_door_indicator/red_door_indicator.tscn",
        """
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/models/garage_debris/red_door_indicator.glb" id="1_glb"]

[node name="RedDoorIndicator" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_glb")]

[node name="RedGlow" type="OmniLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.02, 0.12)
light_color = Color(1, 0.08, 0.05, 1)
light_energy = 1.6
shadow_enabled = false
omni_range = 3.2
""",
    )

    write_file(
        "props/industrial_wall_socket/green_industrial_socket.tscn",
        """
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/models/garage_debris/green_industrial_socket.glb" id="1_glb"]

[node name="GreenIndustrialSocket" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_glb")]

[node name="GreenGlow" type="OmniLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0.16)
light_color = Color(0.25, 0.95, 0.40, 1)
light_energy = 1.2
shadow_enabled = false
omni_range = 2.6
""",
    )

    make_static_box_prop("props/garage_debris/collapsed_rack_pile.tscn", "CollapsedRackPile", "res://assets/models/garage_debris/collapsed_rack_pile.glb", (1.45, 0.80, 0.95), (0.0, 0.40, 0.0), col_layer=1)
    make_static_box_prop("props/garage_debris/steel_bollard.tscn", "SteelBollard", "res://assets/models/garage_debris/steel_bollard.glb", (0.28, 0.96, 0.28), (0.0, 0.48, 0.0), col_layer=1)

    print("[generate_garage_tscns] Generated all Old Garage .tscn prefabs.")


if __name__ == "__main__":
    main()
