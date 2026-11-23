## Characterization tests locking Wave 10 public APIs, constants, signals, and behavior.
class_name TestWave10Characterization
extends GutTest

const CELL_RECHARGER_SCENE: PackedScene = preload("res://interactables/cell_recharger.tscn")
const ENERGY_CELL_SCENE: PackedScene = preload("res://interactables/energy_cell.tscn")
const GLIDER_ITEM_SCENE: PackedScene = preload("res://interactables/glider_item.tscn")
const HEALTH_DISPENSER_SCENE: PackedScene = preload("res://interactables/health_dispenser.tscn")
const HEAVY_PICKABLE_BOX_SCENE: PackedScene = preload("res://interactables/heavy_pickable_box.tscn")
const INDUSTRIAL_DOOR_SCENE: PackedScene = preload("res://interactables/industrial_door.tscn")
const JUMP_PAD_SCENE: PackedScene = preload("res://interactables/jump_pad.tscn")
const LEVER_STICK_ITEM_SCENE: PackedScene = preload("res://interactables/lever_stick_item.tscn")
const PICKABLE_LIQUID_BOTTLE_SCENE: PackedScene = preload(
	"res://interactables/liquid_bottle/pickable_liquid_bottle.tscn"
)
const MIRROR_SCENE: PackedScene = preload("res://interactables/mirror.tscn")
const DESTRUCTIBLE_GLASS_SCENE: PackedScene = preload("res://interactables/destructible_glass.tscn")
const PICKABLE_BOX_SCENE: PackedScene = preload("res://interactables/pickable_box.tscn")
const PICKABLE_TIRE_SCENE: PackedScene = preload("res://interactables/pickable_tire.tscn")
const PICKABLE_VALVE_SCENE: PackedScene = preload("res://interactables/pickable_valve.tscn")
const PNEUMATIC_TUBE_SCENE: PackedScene = preload("res://interactables/pneumatic_tube.tscn")
const PUSH_WHEEL_SCENE: PackedScene = preload("res://interactables/push_wheel.tscn")
const RAFT_PLATFORM_SCENE: PackedScene = preload("res://interactables/raft_platform.tscn")
const SCISSOR_GATE_SCENE: PackedScene = preload(
	"res://interactables/scissor_gate/scissor_gate.tscn"
)
const SEWER_GRATE_SCENE: PackedScene = preload("res://interactables/sewer_grate/sewer_grate.tscn")
const SHOOTING_TARGET_SCENE: PackedScene = preload("res://interactables/shooting_target.tscn")
const WALL_GENERATOR_SCENE: PackedScene = preload("res://interactables/wall_generator.tscn")
const WALL_LEVER_SCENE: PackedScene = preload("res://interactables/wall_lever.tscn")


## Restores default input mouse mode after each test.
func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Verifies [CellRecharger] constants, signals, exports, and cell docking contracts.
func test_cell_recharger_contracts() -> void:
	assert_eq(CellRecharger.PARAM_ENERGY_RATIO, &"energy_ratio")
	assert_eq(CellRecharger.CLAW_RETRACT_Z, 0.05)
	assert_eq(CellRecharger.CLAW_EXTEND_Z, 0.24)
	assert_eq(CellRecharger.CLAW_OPEN_DEG, 28.0)
	assert_eq(CellRecharger.CLAW_GRIP_DEG, 6.0)

	var recharger: CellRecharger = CELL_RECHARGER_SCENE.instantiate() as CellRecharger
	assert_not_null(recharger)
	add_child_autofree(recharger)

	assert_has_signal(recharger, &"recharge_started")
	assert_has_signal(recharger, &"recharge_completed")
	assert_eq(recharger.recharge_duration, 2.0)
	assert_eq(recharger.max_energy, 2.0)
	assert_eq(recharger.available_energy, 2.0)
	assert_eq(recharger.energy_cost_per_charge, 1.0)
	assert_null(recharger.docked_cell)

	recharger.set_available_energy(1.5)
	assert_eq(recharger.available_energy, 1.5)
	recharger.set_available_energy(99.0)
	assert_eq(recharger.available_energy, recharger.max_energy)

	var cell: EnergyCell = ENERGY_CELL_SCENE.instantiate() as EnergyCell
	assert_not_null(cell)
	add_child_autofree(cell)
	cell.discharge()

	recharger.dock_cell(cell)
	assert_eq(recharger.docked_cell, cell)


## Verifies [EnergyCell] constants, signals, exports, and charge/discharge contracts.
func test_energy_cell_contracts() -> void:
	assert_eq(EnergyCell.PARAM_EMISSION_ENERGY, &"emission_energy")
	assert_eq(EnergyCell.CORE_SIZE, Vector2(0.185, 0.39))
	assert_eq(EnergyCell.LIQUID_FILL_LEVEL, 0.78)
	assert_eq(EnergyCell.LIQUID_UV_SCALE, 2.2)
	assert_eq(EnergyCell.CHARGED_IDLE_BUBBLES, 0.35)

	var cell: EnergyCell = ENERGY_CELL_SCENE.instantiate() as EnergyCell
	assert_not_null(cell)
	add_child_autofree(cell)

	assert_has_signal(cell, &"charged_state_changed")
	assert_eq(cell.glow_energy, 2.8)
	watch_signals(cell)

	cell.charge()
	assert_true(cell.is_charged)
	assert_eq(cell.fill_progress, 1.0)
	assert_signal_emitted_with_parameters(cell, &"charged_state_changed", [true])

	cell.discharge()
	assert_false(cell.is_charged)
	assert_eq(cell.fill_progress, 0.0)
	assert_signal_emitted_with_parameters(cell, &"charged_state_changed", [false])

	cell.set_fill_progress(0.45)
	assert_almost_eq(cell.fill_progress, 0.45, 0.001)


## Verifies [GliderItem] constants and public method contracts.
func test_glider_item_contracts() -> void:
	assert_eq(GliderItem.LAYER_INTERACTIVE_BIT, 4)
	assert_eq(GliderItem.PICKUP_TWEEN_DURATION, 0.4)
	assert_eq(GliderItem.DETACH_ANIM_DURATION, 1.0)
	assert_eq(GliderItem.DETACH_SPAWN_DISTANCE, 4.0)
	assert_eq(GliderItem.GLIDER_SIZE, Vector3(8.0, 0.2, 6.0))
	assert_eq(GliderItem.HALF_HEIGHT, 0.1)

	var glider: GliderItem = GLIDER_ITEM_SCENE.instantiate() as GliderItem
	assert_not_null(glider)
	add_child_autofree(glider)

	assert_null(glider.current_holder)
	assert_true(glider.has_method(&"set_glider_mesh_visible"))
	assert_true(glider.has_method(&"pick_up"))
	assert_true(glider.has_method(&"throw_item"))
	assert_true(glider.has_method(&"drop_item"))
	glider.set_glider_mesh_visible(false)
	glider.set_glider_mesh_visible(true)


## Verifies [HealthDispenser] constants, exports, and method contracts.
func test_health_dispenser_contracts() -> void:
	assert_eq(HealthDispenser.PARAM_FILL, &"fill_amount")
	assert_eq(HealthDispenser.PARAM_COLOR, &"liquid_color")
	assert_eq(HealthDispenser.PARAM_EMISSION, &"emission_energy")
	assert_eq(HealthDispenser.DEPLETED_TEXT, "Out of Lifeblood!")
	assert_eq(HealthDispenser.CONDUIT_RINGS, 64)
	assert_eq(HealthDispenser.CONDUIT_RADIAL_SEGS, 16)
	assert_eq(HealthDispenser.SUCKER_ROWS, 18)

	var dispenser: HealthDispenser = HEALTH_DISPENSER_SCENE.instantiate() as HealthDispenser
	assert_not_null(dispenser)
	add_child_autofree(dispenser)

	assert_eq(dispenser.heal_amount, 25)
	assert_eq(dispenser.heal_cooldown_msec, 250)
	assert_eq(dispenser.max_dispenser_health, 200)
	assert_eq(dispenser.segment_count, 15)
	assert_eq(dispenser.max_reach, 2.0)
	assert_true(dispenser.has_method(&"interact_held"))


## Verifies [HeavyPickableBox] exports and pickup validation contracts.
func test_heavy_pickable_box_contracts() -> void:
	var box: HeavyPickableBox = HEAVY_PICKABLE_BOX_SCENE.instantiate() as HeavyPickableBox
	assert_not_null(box)
	add_child_autofree(box)

	assert_true(box is PickableObject)
	assert_eq(box.drop_distance, 1.0)
	assert_eq(box.snap_duration, 0.3)
	assert_eq(box.box_half_width, 0.75)
	assert_eq(box.player_radius, 0.5)
	assert_eq(box.player_height, 1.8)
	assert_eq(box.hold_padding, 0.75)
	assert_false(box.is_heavy_held)
	assert_true(box.has_method(&"pick_up"))
	assert_true(box.has_method(&"drop"))
	assert_true(box.has_method(&"throw"))
	assert_true(box.has_method(&"is_valid_pickup_position"))


## Verifies [IndustrialDoor] enums, constants, signals, and lock/interact contracts.
func test_industrial_door_contracts() -> void:
	assert_eq(IndustrialDoor.DOOR_WIDTH, 0.9)
	assert_eq(IndustrialDoor.DOOR_HEIGHT, 2.0)
	assert_eq(IndustrialDoor.DOOR_DEPTH, 0.045)
	assert_eq(IndustrialDoor.SWING_DURATION, 0.6)
	assert_eq(IndustrialDoor.SwingMode.AWAY_FROM_PLAYER, 0)
	assert_eq(IndustrialDoor.SwingMode.INWARD_ONLY, 1)
	assert_eq(IndustrialDoor.SwingMode.OUTWARD_ONLY, 2)
	assert_eq(IndustrialDoor.SwingMode.BOTH_WAYS, 3)

	var door: IndustrialDoor = INDUSTRIAL_DOOR_SCENE.instantiate() as IndustrialDoor
	assert_not_null(door)
	add_child_autofree(door)

	assert_has_signal(door, &"state_changed")
	assert_has_signal(door, &"door_locked")
	assert_false(door.is_open)
	assert_false(door.is_locked)

	watch_signals(door)
	door.lock_door()
	assert_true(door.is_locked)
	door.interact()
	assert_false(door.is_open)
	assert_signal_emitted(door, &"door_locked")

	door.unlock_door()
	assert_false(door.is_locked)
	door.interact()
	assert_true(door.is_open)
	assert_signal_emitted_with_parameters(door, &"state_changed", [true])


## Verifies [JumpPad] default exports and scene instantiation.
func test_jump_pad_contracts() -> void:
	var pad: JumpPad = JUMP_PAD_SCENE.instantiate() as JumpPad
	assert_not_null(pad)
	add_child_autofree(pad)

	assert_eq(pad.apex_height, 3.0)
	assert_eq(pad.flight_speed_multiplier, 1.0)
	assert_eq(pad.player_gravity, 9.8)
	assert_eq(pad.fall_gravity_multiplier, 1.0)


## Verifies [LeverStickItem] signals, exports, and runtime mount detector setup.
func test_lever_stick_item_contracts() -> void:
	var stick: LeverStickItem = LEVER_STICK_ITEM_SCENE.instantiate() as LeverStickItem
	assert_not_null(stick)
	add_child_autofree(stick)

	assert_true(stick is PickableObject)
	assert_has_signal(stick, &"mounted_on_lever")
	assert_eq(stick.item_id, "lever_stick")
	assert_eq(stick.item_name, "Iron Lever Handle")
	assert_true(is_instance_valid(stick.mount_detector))
	assert_true(stick.has_method(&"pick_up"))
	assert_true(stick.has_method(&"drop"))
	assert_true(stick.has_method(&"throw"))


## Verifies [PickableLiquidBottle] constants, exports, and liquid property setters.
func test_pickable_liquid_bottle_contracts() -> void:
	assert_eq(PickableLiquidBottle.PARAM_COEFF, &"coeff")
	assert_eq(PickableLiquidBottle.PARAM_VEL, &"vel")
	assert_eq(PickableLiquidBottle.PARAM_FILL, &"fill_amount")
	assert_eq(PickableLiquidBottle.PARAM_COLOR, &"liquid_color")
	assert_eq(PickableLiquidBottle.SPRING_CONSTANT, 180.0)
	assert_eq(PickableLiquidBottle.REACTION_STRENGTH, 3.5)
	assert_eq(PickableLiquidBottle.DAMPENING, 4.2)

	var bottle: PickableLiquidBottle = (
		PICKABLE_LIQUID_BOTTLE_SCENE.instantiate() as PickableLiquidBottle
	)
	assert_not_null(bottle)
	add_child_autofree(bottle)

	bottle.set_fill(0.8)
	assert_almost_eq(bottle.fill, 0.8, 0.001)
	bottle.set_glass_thickness(0.03)
	assert_almost_eq(bottle.glass_thickness, 0.03, 0.001)
	bottle.set_gas(false)
	assert_false(bottle.gas)
	bottle.apply_slosh_impulse(Vector2(0.1, 0.2), 0.5)


## Verifies [Mirror] constants, exports, and clean planar reflection setup.
func test_mirror_contracts() -> void:
	assert_eq(Mirror.GROUP_IGNORE_SETTINGS, &"ignore_global_video_settings")

	var mirror: Mirror = MIRROR_SCENE.instantiate() as Mirror
	assert_not_null(mirror)
	add_child_autofree(mirror)

	assert_eq(mirror.size, Vector2(1.5, 2.0))
	assert_eq(mirror.pixels_per_unit, 64)
	assert_eq(mirror.max_viewport_size, 512)
	assert_eq(mirror.max_update_distance, 15.0)
	assert_false(mirror.has_method(&"take_damage"))


## Verifies [DestructibleGlass] constants, signals, and BREAKABLE vs ARMORED modes.
func test_destructible_glass_contracts() -> void:
	assert_eq(DestructibleGlass.PARAM_IS_ARMORED, &"is_armored")
	assert_eq(DestructibleGlass.PARAM_CRACK_INTENSITY, &"crack_intensity")
	assert_eq(DestructibleGlass.PARAM_IMPACT_UV, &"impact_uv")

	var breakable: DestructibleGlass = DESTRUCTIBLE_GLASS_SCENE.instantiate() as DestructibleGlass
	assert_not_null(breakable)
	add_child_autofree(breakable)
	assert_eq(breakable.mode, DestructibleGlass.GlassMode.BREAKABLE)
	assert_has_signal(breakable, &"glass_cracked")
	assert_has_signal(breakable, &"glass_broken")

	watch_signals(breakable)
	breakable.take_damage(20.0, breakable.global_position, Vector3.FORWARD)
	assert_signal_emitted(breakable, &"glass_cracked")
	assert_false(breakable.is_broken())

	breakable.take_damage(40.0, breakable.global_position, Vector3.FORWARD)
	assert_signal_emitted(breakable, &"glass_broken")
	assert_true(breakable.is_broken())

	breakable.repair_glass()
	assert_false(breakable.is_broken())

	var armored: DestructibleGlass = DESTRUCTIBLE_GLASS_SCENE.instantiate() as DestructibleGlass
	assert_not_null(armored)
	armored.mode = DestructibleGlass.GlassMode.ARMORED
	add_child_autofree(armored)

	watch_signals(armored)
	armored.take_damage(500.0, armored.global_position, Vector3.FORWARD)
	assert_signal_emitted(armored, &"glass_cracked")
	assert_signal_not_emitted(armored, &"glass_broken")
	assert_false(armored.is_broken())


## Verifies localized Voronoi fracture keeps perimeter shards intact and supports multi-hit holes.
func test_destructible_glass_partial_voronoi_fracture() -> void:
	var glass: DestructibleGlass = DESTRUCTIBLE_GLASS_SCENE.instantiate() as DestructibleGlass
	assert_not_null(glass)
	glass.size = Vector2(2.0, 2.0)
	glass.break_radius = 0.28
	add_child_autofree(glass)

	assert_eq(glass.get_alive_shard_count(), 1)
	glass.take_damage(60.0, glass.global_position, Vector3.FORWARD)
	assert_true(glass.is_broken())

	var remaining_after_first: int = glass.get_alive_shard_count()
	assert_gt(remaining_after_first, 4)

	glass.take_damage(60.0, glass.global_position + Vector3(0.75, 0.75, 0.0), Vector3.FORWARD)
	assert_lt(glass.get_alive_shard_count(), remaining_after_first)

	glass.repair_glass()
	assert_false(glass.is_broken())
	assert_eq(glass.get_alive_shard_count(), 1)


## Verifies [PathStick] defaults and release_player reset contract.
func test_path_stick_contracts() -> void:
	var stick: PathStick = PathStick.new()
	assert_not_null(stick)
	add_child_autofree(stick)

	assert_eq(stick.move_speed, 15.0)
	assert_eq(stick.throw_speed_threshold, 8.0)
	assert_eq(stick.throw_velocity_local, Vector3(0.0, 5.0, -20.0))
	assert_false(stick.stay_at_end)
	assert_false(stick.return_immediately)
	assert_false(stick.is_active)

	stick.is_active = true
	stick.release_player()
	assert_false(stick.is_active)
	assert_null(stick.current_player)


## Verifies [PickableBox] instantiation and base inheritance.
func test_pickable_box_contracts() -> void:
	var scene_box: Node = PICKABLE_BOX_SCENE.instantiate()
	assert_not_null(scene_box)
	add_child_autofree(scene_box)
	assert_true(scene_box is PickableObject)

	var box: PickableBox = PickableBox.new()
	assert_not_null(box)
	add_child_autofree(box)
	assert_true(box is PickableObject)


## Verifies [PickableTire] constants, mass, hold settings, and physics material.
func test_pickable_tire_contracts() -> void:
	assert_eq(PickableTire.TIRE_FRICTION, 0.9)
	assert_eq(PickableTire.TIRE_BOUNCE, 0.35)
	assert_eq(PickableTire.DEFAULT_TIRE_MASS, 9.5)

	var tire: PickableTire = PICKABLE_TIRE_SCENE.instantiate() as PickableTire
	assert_not_null(tire)
	add_child_autofree(tire)

	assert_almost_eq(tire.mass, PickableTire.DEFAULT_TIRE_MASS, 0.01)
	assert_true(tire.hold_at_chest)
	assert_not_null(tire.physics_material_override)
	assert_almost_eq(tire.physics_material_override.friction, PickableTire.TIRE_FRICTION, 0.01)
	assert_almost_eq(tire.physics_material_override.bounce, PickableTire.TIRE_BOUNCE, 0.01)


## Verifies [PickableValve] signal, exports, clamping, and rotation contract.
func test_pickable_valve_contracts() -> void:
	var valve: PickableValve = PICKABLE_VALVE_SCENE.instantiate() as PickableValve
	assert_not_null(valve)
	add_child_autofree(valve)

	assert_has_signal(valve, &"valve_rotated")
	assert_eq(valve.current_angle, 0.0)
	assert_eq(valve.max_angle, 360.0)
	assert_eq(valve.min_angle, 0.0)
	assert_false(valve.is_socketed)

	watch_signals(valve)
	valve.rotate_valve(90.0)
	assert_eq(valve.current_angle, 90.0)
	assert_signal_emitted_with_parameters(valve, &"valve_rotated", [90.0])

	valve.rotate_valve(500.0)
	assert_eq(valve.current_angle, 360.0)


## Verifies [PneumaticTube] constants, signals, exports, and public methods.
func test_pneumatic_tube_contracts() -> void:
	assert_eq(PneumaticTube.DEFAULT_MASK, 30)

	var tube: PneumaticTube = PNEUMATIC_TUBE_SCENE.instantiate() as PneumaticTube
	assert_not_null(tube)
	add_child_autofree(tube)

	assert_has_signal(tube, &"body_entered_tube")
	assert_has_signal(tube, &"body_exited_tube")
	assert_eq(tube.outer_radius, 1.5)
	assert_eq(tube.wall_thickness, 0.08)
	assert_eq(tube.circle_sides, 24)
	assert_eq(tube.transport_speed, 24.0)
	assert_eq(tube.exit_launch_speed, 28.0)
	assert_true(tube.has_method(&"rebuild_tube"))
	assert_true(tube.has_method(&"capture_body"))


## Verifies [PushWheel] constants, exports, and push/transform contracts.
func test_push_wheel_contracts() -> void:
	assert_eq(PushWheel.DOUBLE_TAP_DELAY, 0.3)

	var wheel: PushWheel = PUSH_WHEEL_SCENE.instantiate() as PushWheel
	assert_not_null(wheel)
	add_child_autofree(wheel)

	assert_eq(wheel.turn_duration, 3.0)
	assert_eq(wheel.visual_rotations, 1.0)
	assert_true(wheel.turn_clockwise)
	assert_true(wheel.allow_reverse)
	assert_eq(wheel.stick_count, 4)
	assert_eq(wheel.progress, 0.0)
	assert_false(wheel.is_locked)
	assert_true(wheel.has_method(&"push"))
	assert_true(wheel.has_method(&"get_interaction_transform"))

	wheel.push(0.25)
	assert_gt(wheel.progress, 0.0)


## Verifies [RaftPlatform] constants, mass, and stability defaults.
func test_raft_platform_contracts() -> void:
	assert_eq(RaftPlatform.DEFAULT_RAFT_MASS, 60.0)
	assert_eq(RaftPlatform.DEFAULT_COM_OFFSET_Y, -0.35)
	assert_eq(RaftPlatform.DEFAULT_HOLD_OFFSET, -1.6)
	assert_eq(RaftPlatform.DEFAULT_DETACH_DISTANCE, 3.6)
	assert_eq(RaftPlatform.GROUP_WATER_AREA_NAME, &"water_area")
	assert_eq(RaftPlatform.METHOD_ENTER_WATER_NAME, &"enter_water")

	var raft: RaftPlatform = RAFT_PLATFORM_SCENE.instantiate() as RaftPlatform
	assert_not_null(raft)
	add_child_autofree(raft)

	assert_almost_eq(raft.mass, RaftPlatform.DEFAULT_RAFT_MASS, 0.01)
	assert_almost_eq(raft.com_offset_y, RaftPlatform.DEFAULT_COM_OFFSET_Y, 0.01)


## Verifies ScissorGate signals, defaults, and open/close state transitions.
func test_scissor_gate_contracts() -> void:
	var gate: AnimatableBody3D = SCISSOR_GATE_SCENE.instantiate() as AnimatableBody3D
	assert_not_null(gate)
	add_child_autofree(gate)

	assert_has_signal(gate, &"state_changed")
	assert_has_signal(gate, &"opened")
	assert_has_signal(gate, &"closed")
	assert_false(bool(gate.get(&"is_open")))

	watch_signals(gate)
	gate.call(&"open")
	assert_true(bool(gate.get(&"is_open")))
	assert_signal_emitted_with_parameters(gate, &"state_changed", [true])

	gate.call(&"close")
	assert_false(bool(gate.get(&"is_open")))
	assert_signal_emitted_with_parameters(gate, &"state_changed", [false])


## Verifies [SewerGrate] constants, signals, exports, and open/close state transitions.
func test_sewer_grate_contracts() -> void:
	assert_eq(SewerGrate.NODE_LEFT, &"GrateLeft")
	assert_eq(SewerGrate.NODE_RIGHT, &"GrateRight")
	assert_eq(SewerGrate.PARAM_RUST_SEED, &"rust_seed")

	var grate: SewerGrate = SEWER_GRATE_SCENE.instantiate() as SewerGrate
	assert_not_null(grate)
	add_child_autofree(grate)

	assert_has_signal(grate, &"grate_state_changed")
	assert_has_signal(grate, &"opened")
	assert_has_signal(grate, &"closed")
	assert_has_signal(grate, &"leaf_detached")
	assert_eq(grate.open_angle_deg, 105.0)
	assert_eq(grate.swing_duration, 0.65)
	assert_eq(grate.leaf_mass, 45.0)
	assert_false(grate.is_open)

	grate.open()
	assert_true(grate.is_open)

	grate.close()
	assert_false(grate.is_open)


## Verifies [ShootingTarget] exports, damage handling, and pool reset contracts.
func test_shooting_target_contracts() -> void:
	var target: ShootingTarget = SHOOTING_TARGET_SCENE.instantiate() as ShootingTarget
	assert_not_null(target)
	add_child_autofree(target)

	assert_eq(target.target_health, 10)
	assert_true(target.can_player_hit)
	assert_eq(target.despawn_time, 0.5)
	assert_not_null(target.health_component)
	assert_not_null(target.faction_component)

	target.take_damage(10)
	assert_eq(target.collision_layer, CollisionLayers.MASK_NONE)
	target.reset()
	assert_ne(target.collision_layer, CollisionLayers.MASK_NONE)


## Verifies [TetheredPlug] signal, power propagation, and trailing mode state.
func test_tethered_plug_contracts() -> void:
	var plug_a: TetheredPlug = TetheredPlug.new()
	var plug_b: TetheredPlug = TetheredPlug.new()
	add_child_autofree(plug_a)
	add_child_autofree(plug_b)

	assert_has_signal(plug_a, &"power_state_changed")
	assert_false(plug_a.is_energized)
	assert_false(plug_a.is_trailing_mode)

	plug_a.partner_plug = plug_b
	plug_b.partner_plug = plug_a
	watch_signals(plug_a)
	watch_signals(plug_b)

	plug_a.set_power_state(true)
	assert_true(plug_a.is_energized)
	assert_true(plug_b.is_energized)
	assert_signal_emitted_with_parameters(plug_a, &"power_state_changed", [true])
	assert_signal_emitted_with_parameters(plug_b, &"power_state_changed", [true])

	plug_a.on_grabbed()
	assert_true(plug_b.is_trailing_mode)
	plug_a.on_released()
	assert_false(plug_b.is_trailing_mode)


## Verifies [WallGenerator] constants, signals, exports, and cell insertion contract.
func test_wall_generator_contracts() -> void:
	assert_eq(WallGenerator.PARAM_LED_COLOR, &"led_color")
	assert_eq(WallGenerator.PARAM_BLINK_SPEED, &"blink_speed")
	assert_eq(WallGenerator.PARAM_INTENSITY, &"intensity")
	assert_eq(WallGenerator.RED_BLINK_SPEED, 8.0)

	var gen: WallGenerator = WALL_GENERATOR_SCENE.instantiate() as WallGenerator
	assert_not_null(gen)
	add_child_autofree(gen)

	assert_has_signal(gen, &"cell_inserted")
	assert_has_signal(gen, &"cell_ejected")
	assert_null(gen.current_cell)

	var cell: EnergyCell = ENERGY_CELL_SCENE.instantiate() as EnergyCell
	assert_not_null(cell)
	add_child_autofree(cell)
	cell.charge()

	gen.insert_cell(cell)
	assert_eq(gen.current_cell, cell)


## Verifies [WallLever] signals, exports, stick installation, and toggle contracts.
func test_wall_lever_contracts() -> void:
	var lever: WallLever = WALL_LEVER_SCENE.instantiate() as WallLever
	assert_not_null(lever)
	add_child_autofree(lever)

	assert_has_signal(lever, &"state_changed")
	assert_has_signal(lever, &"handle_missing")
	assert_has_signal(lever, &"stick_installed")
	assert_has_signal(lever, &"stick_fallen")
	assert_eq(lever.required_item_id, "lever_stick")
	assert_eq(lever.pull_duration, 1.0)
	assert_false(lever.is_pulled)

	watch_signals(lever)
	lever.is_complete = false
	lever.install_stick()
	assert_true(lever.is_complete)
	assert_signal_emitted(lever, &"stick_installed")

	lever.toggle()
	assert_true(lever.is_pulled)
