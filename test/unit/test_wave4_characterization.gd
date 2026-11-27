## Characterization tests locking Wave 4 public APIs, constants, and behavior.
class_name TestWave4Characterization
extends GutTest

const WIND_WALL_SCRIPT: GDScript = preload("res://vfx/wind_wall.gd")


class _MockInteractableNode:
	extends Node3D

	var interacted_count: int = 0

	func interact() -> void:
		interacted_count += 1


class _MockPowerTarget:
	extends Node3D

	var power_on_count: int = 0
	var power_off_count: int = 0
	var last_progress: float = -1.0

	func power_on() -> void:
		power_on_count += 1

	func power_off() -> void:
		power_off_count += 1

	func set_progress(val: float) -> void:
		last_progress = val


class _SpyState:
	extends State

	var enter_count: int = 0
	var exit_count: int = 0
	var last_message: Dictionary = {}

	func enter(message: Dictionary = {}) -> void:
		enter_count += 1
		last_message = message

	func exit() -> void:
		exit_count += 1


class _SignalEmitterNode:
	extends Node

	@warning_ignore("unused_signal")
	signal pinged


## Verifies [NodeQuery] hierarchy queries, interactable root resolution, and raycast guard.
func test_node_query_contracts() -> void:
	var root: Node3D = Node3D.new()
	root.add_to_group(&"interactable")
	root.set_meta(&"wave4_meta", true)
	add_child_autofree(root)

	var mid: _MockInteractableNode = _MockInteractableNode.new()
	mid.add_to_group(&"mid_group")
	root.add_child(mid)

	var leaf: Node3D = Node3D.new()
	mid.add_child(leaf)

	assert_eq(NodeQuery.find_ancestor_of_type(leaf, _MockInteractableNode), mid)
	assert_eq(NodeQuery.find_ancestor_in_group(leaf, &"mid_group"), mid)
	assert_eq(NodeQuery.find_ancestor_with_method(leaf, &"interact"), mid)
	assert_eq(NodeQuery.find_ancestor_with_meta(leaf, &"wave4_meta"), root)
	assert_eq(NodeQuery.find_first_child_of_type(root, _MockInteractableNode), mid)
	assert_eq(NodeQuery.find_children_of_type(root, _MockInteractableNode).size(), 1)
	assert_eq(NodeQuery.find_children_in_group(root, &"mid_group").size(), 1)
	assert_eq(NodeQuery.get_single_node_in_group(get_tree(), &"mid_group"), mid)
	assert_eq(NodeQuery.resolve_interactable_root(leaf), mid)
	assert_true(NodeQuery.cast_ray(null, Vector3.ZERO, Vector3.FORWARD).is_empty())


## Verifies [Utilities] and [MathUtils] helpers, signal connect, control centering, and raycast.
func test_utilities_contracts() -> void:
	assert_true(Utilities.raycast_3d(null, Vector3.ZERO, Vector3.FORWARD).is_empty())
	assert_eq(MathUtils.snap_to_grid_3d(Vector3(1.4, 2.6, -0.4), 1.0), Vector3(1.0, 3.0, 0.0))
	assert_almost_eq(MathUtils.normalize_angle(TAU + 0.5), 0.5, 0.0001)
	assert_true(MathUtils.is_within_distance_3d(Vector3.ZERO, Vector3(3.0, 4.0, 0.0), 5.0))
	assert_false(MathUtils.is_within_distance_3d(Vector3.ZERO, Vector3(3.0, 4.1, 0.0), 5.0))

	var ctrl: Control = Control.new()
	ctrl.custom_minimum_size = Vector2(100.0, 40.0)
	add_child_autofree(ctrl)
	Utilities.center_control(ctrl)
	assert_eq(ctrl.pivot_offset, Vector2(50.0, 20.0))

	var emitter: _SignalEmitterNode = _SignalEmitterNode.new()
	add_child_autofree(emitter)
	var cb: Callable = func() -> void: pass
	assert_true(Utilities.safe_connect(emitter.pinged, cb))
	assert_false(Utilities.safe_connect(emitter.pinged, cb))

	var tw: Tween = Utilities.reset_tween(emitter, null)
	assert_not_null(tw)
	var tw2: Tween = Utilities.reset_tween_ext(emitter, tw)
	assert_not_null(tw2)
	Utilities.safe_kill_tween(tw2)


## Verifies [StateMachine] and [State] lifecycle, transitions, locking, and signal routing.
func test_state_machine_and_state_contracts() -> void:
	var sm: StateMachine = StateMachine.new()
	var state_a: _SpyState = _SpyState.new()
	state_a.name = &"Idle"
	var state_b: _SpyState = _SpyState.new()
	state_b.name = &"Move"
	sm.initial_state = state_a
	sm.add_child(state_a)
	sm.add_child(state_b)
	add_child_autofree(sm)
	watch_signals(sm)

	assert_eq(sm.get_current_state(), state_a)
	assert_true(sm.is_in_state(&"Idle"))
	assert_eq(state_a.enter_count, 1)

	var payload: Dictionary = {"speed": 5.0}
	assert_true(sm.transition_to(&"Move", payload))
	assert_eq(sm.get_current_state(), state_b)
	assert_eq(state_a.exit_count, 1)
	assert_eq(state_b.enter_count, 1)
	assert_eq(state_b.last_message.get("speed"), 5.0)
	assert_signal_emitted(sm, "state_changed")

	assert_false(sm.change_state(&"Move"), "Same-state transition should return false")
	assert_false(sm.change_state(&"Missing"), "Unknown state transition should return false")

	sm.is_locked = true
	assert_false(sm.change_state(&"Idle"), "Locked StateMachine should reject transitions")

	sm.is_locked = false
	state_b.transition_requested.emit(&"Idle", {"from": "signal"})
	assert_true(sm.is_in_state(&"Idle"))
	assert_eq(state_a.last_message.get("from"), "signal")


## Verifies [Types] enums, bitmask constants, and display string helpers.
func test_types_constants_and_helpers() -> void:
	assert_eq(Types.MASK_ENVIRONMENT, CollisionLayers.MASK_ENVIRONMENT)
	assert_eq(Types.MASK_PLAYER, CollisionLayers.MASK_PLAYER)
	assert_eq(Types.MASK_INTERACTIVE, CollisionLayers.MASK_INTERACTIVE)
	assert_eq(Types.MASK_DEBRIS, CollisionLayers.MASK_DEBRIS)
	assert_eq(Types.MASK_ENEMIES, CollisionLayers.MASK_ENEMIES)
	assert_eq(Types.MASK_SOLID_WORLD, CollisionLayers.MASK_SOLID_WORLD)
	assert_eq(Types.MASK_COMBAT_ENTITIES, CollisionLayers.MASK_COMBAT_ENTITIES)

	assert_eq(Types.item_category_to_string(Types.ItemCategory.WEAPON), "Weapon")
	assert_eq(Types.item_category_to_string(Types.ItemCategory.KEYCARD), "Keycard")
	assert_eq(Types.item_category_to_string(Types.ItemCategory.NONE), "Item")

	assert_eq(Types.faction_to_string(Types.Faction.PLAYER), "Player")
	assert_eq(Types.faction_to_string(Types.Faction.ENEMY), "Hostile")
	assert_eq(Types.faction_to_string(Types.Faction.NONE), "None")

	assert_eq(Types.damage_type_to_string(Types.DamageType.FIRE), "Thermal")
	assert_eq(Types.damage_type_to_string(Types.DamageType.FALL), "Impact")
	assert_eq(Types.damage_type_to_string(Types.DamageType.GENERIC), "Generic")


## Verifies [ReferenceData] palette defaults and icon fallback lookup.
func test_reference_data_contract() -> void:
	var ref_data: ReferenceData = ReferenceData.new()
	var fallback_tex: ImageTexture = ImageTexture.new()
	var weapon_tex: ImageTexture = ImageTexture.new()
	ref_data.fallback_texture = fallback_tex
	ref_data.item_category_icons[Types.ItemCategory.WEAPON] = weapon_tex

	assert_eq(ref_data.get_category_icon(Types.ItemCategory.WEAPON), weapon_tex)
	assert_eq(ref_data.get_category_icon(Types.ItemCategory.QUEST), fallback_tex)


## Verifies [VrsTextureGenerator] produces and caches radial density map.
func test_vrs_texture_generator_contract() -> void:
	var tex_a: ImageTexture = VrsTextureGenerator.create_radial_density_map(Vector2i(32, 32))
	assert_not_null(tex_a)
	var img: Image = tex_a.get_image()
	assert_not_null(img)
	var center_val: float = img.get_pixel(16, 16).r
	var corner_val: float = img.get_pixel(0, 0).r
	assert_gt(center_val, corner_val, "Center density should exceed corner density")

	var tex_b: ImageTexture = VrsTextureGenerator.create_radial_density_map(Vector2i(32, 32))
	assert_eq(tex_a, tex_b, "VrsTextureGenerator should return cached ImageTexture")


## Verifies [VideoConfig] presets, defaults dictionary, and UI scale helper.
func test_video_config_contract() -> void:
	assert_true(VideoConfig.PRESETS.has("Low"))
	assert_true(VideoConfig.PRESETS.has("Medium"))
	assert_true(VideoConfig.PRESETS.has("High"))
	assert_true(VideoConfig.PRESETS.has("Ultra"))
	assert_eq(VideoConfig.DEFAULT_FPS, 60)

	var defaults: Dictionary = VideoConfig.get_default_settings_dict()
	assert_eq(defaults.get("preset"), "High")
	assert_eq(defaults.get("clouds"), "Off")
	assert_eq(defaults.get("fps_limit"), 60)
	assert_almost_eq(
		VideoConfig.compute_effective_ui_scale(1.25, Vector2i(1920, 1080)), 1.25, 0.0001
	)


## Verifies [KeycardData] and [ChapterData] resource defaults.
func test_data_resources_defaults() -> void:
	var keycard: KeycardData = KeycardData.new()
	assert_eq(keycard.card_id, &"")
	assert_eq(keycard.card_color, Color.WHITE)

	var chapter: ChapterData = ChapterData.new()
	chapter.chapter_name = "Prologue"
	chapter.scene_path = "res://levels/prologue.tscn"
	assert_eq(chapter.chapter_name, "Prologue")
	assert_eq(chapter.scene_path, "res://levels/prologue.tscn")


## Verifies [Gate] progress lerping and [OutputTransmitter3D] target routing.
func test_gate_and_output_transmitter_contracts() -> void:
	var gate: Gate = Gate.new()
	gate.position = Vector3(1.0, 0.0, 0.0)
	gate.open_offset = Vector3(0.0, 4.0, 0.0)
	add_child_autofree(gate)
	gate.set_progress(0.5)
	assert_eq(gate.position, Vector3(1.0, 2.0, 0.0))

	var target: _MockPowerTarget = _MockPowerTarget.new()
	add_child_autofree(target)
	var transmitter: OutputTransmitter3D = OutputTransmitter3D.new()
	transmitter.targets = [target]
	add_child_autofree(transmitter)
	watch_signals(transmitter)

	transmitter.power_on()
	assert_true(transmitter.is_active)
	assert_eq(target.power_on_count, 1)
	assert_signal_emitted(transmitter, "activated")

	transmitter.transmit_progress(0.75)
	assert_almost_eq(target.last_progress, 0.75, 0.0001)

	transmitter.power_off()
	assert_false(transmitter.is_active)
	assert_eq(target.power_off_count, 1)
	assert_signal_emitted(transmitter, "deactivated")


## Verifies [PhysicsMagnet] layer configuration and idle physics gating.
func test_physics_magnet_contract() -> void:
	var magnet: PhysicsMagnet = PhysicsMagnet.new()
	add_child_autofree(magnet)
	assert_eq(magnet.collision_layer, 0)
	assert_eq(magnet.collision_mask, 5)
	assert_false(magnet.is_physics_processing())
	assert_eq(PhysicsMagnet.MagnetMode.ALL, 1)


## Verifies [GasLeakEmitter] and [Trail3D] state toggles.
func test_gas_leak_and_trail_3d_contracts() -> void:
	var gas: GasLeakEmitter = GasLeakEmitter.new()
	add_child_autofree(gas)
	assert_false(gas.is_leaking)
	assert_false(gas.emitting)
	gas.toggle_leak()
	assert_true(gas.is_leaking)
	assert_true(gas.emitting)

	var trail: Trail3D = Trail3D.new()
	add_child_autofree(trail)
	trail.start_trail()
	assert_true(trail.is_emitting)
	trail.stop_trail()
	assert_false(trail.is_emitting)
	trail.clear_trail()


## Verifies [UIKeypad], [UICircleTimingKeypad], and [MachineLockUI] contracts.
func test_keypad_and_machine_lock_ui_contracts() -> void:
	var keypad: UIKeypad = UIKeypad.new()
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	var line_edit: LineEdit = LineEdit.new()
	line_edit.name = "LineEdit"
	var grid: GridContainer = GridContainer.new()
	grid.name = "GridContainer"
	for btn_name: String in ["1", "2", "Enter", "Clear"]:
		var btn: Button = Button.new()
		btn.name = btn_name
		grid.add_child(btn)
	vbox.add_child(line_edit)
	vbox.add_child(grid)
	keypad.add_child(vbox)
	add_child_autofree(keypad)
	watch_signals(keypad)

	var btn_1: Button = grid.get_node("1") as Button
	var btn_enter: Button = grid.get_node("Enter") as Button
	btn_1.pressed.emit()
	assert_eq(keypad.entered_code, "1")
	assert_eq(line_edit.text, "1")
	btn_enter.pressed.emit()
	assert_signal_emitted_with_parameters(keypad, "code_entered", ["1"])

	var circle: UICircleTimingKeypad = UICircleTimingKeypad.new()
	assert_eq(circle.required_stages, 3)
	assert_eq(circle.max_tries, 5)
	assert_eq(circle.fail_damage, 20)
	assert_eq(circle.perfect_heal_amount, 25)
	circle.free()

	var lock_ui: MachineLockUI = MachineLockUI.new()
	var lbl: Label = Label.new()
	var up_btn: Button = Button.new()
	var down_btn: Button = Button.new()
	lock_ui.add_child(lbl)
	lock_ui.add_child(up_btn)
	lock_ui.add_child(down_btn)
	lock_ui.labels = [lbl]
	lock_ui.up_buttons = [up_btn]
	lock_ui.down_buttons = [down_btn]
	add_child_autofree(lock_ui)
	lock_ui.setup(true)
	assert_eq(lbl.text, "A")
	lock_ui.setup(false)
	assert_eq(lbl.text, "0")


## Verifies [StairController], [PhysicsPusher], [LightningStrikeVFX], and [WindWall] constants.
func test_player_and_vfx_constants() -> void:
	assert_almost_eq(StairController.MAX_STEP_HEIGHT, 0.55, 0.0001)
	assert_almost_eq(StairController.MIN_STEP_REACH, 0.3, 0.0001)

	var pusher: PhysicsPusher = PhysicsPusher.new()
	assert_almost_eq(pusher.push_force, 12.0, 0.0001)
	assert_almost_eq(pusher.resistance_mass_scale, 25.0, 0.0001)
	pusher.free()

	assert_eq(LightningStrikeVFX.SURFACE_BOLT, 0)
	assert_eq(LightningStrikeVFX.SURFACE_MARK, 1)
	assert_eq(LightningStrikeVFX.SURFACE_WAVE, 2)
	assert_eq(LightningStrikeVFX.DEFAULT_RENDER_LAYERS, (1 << 0) | (1 << 9))

	var wall: Node3D = WIND_WALL_SCRIPT.new() as Node3D
	assert_eq(wall.get("RENDER_LAYER_VOLUMETRICS"), 1 << 9)
	assert_eq(wall.get("PHYSICS_LAYER_INTERACTIVE"), 1 << 2)
	assert_eq(wall.get("PHYSICS_MASK_DEBRIS_ENEMIES"), (1 << 3) | (1 << 4))
	wall.free()
