## Characterization tests locking Wave 8 public APIs, constants, signals, and behavior.
class_name TestWave8Characterization
extends GutTest

const OIL_SPILL_SCENE: PackedScene = preload("res://environment/oil_spill.tscn")
const POWERED_LIGHT_SCENE: PackedScene = preload("res://environment/powered_light_3d.tscn")
const BARBWIRE_SCENE: PackedScene = preload("res://environment/procedural_barbwire.tscn")
const MONKEY_BAR_SCRIPT: GDScript = preload("res://environment/procedural_monkey_bars.gd")
const PROCEDURAL_TUBE_SCRIPT: GDScript = preload("res://environment/procedural_tube.gd")
const PROCEDURAL_TUBE_SCENE: PackedScene = preload("res://environment/procedural_tube.tscn")
const SMOKE_HAZARD_SCENE: PackedScene = preload("res://environment/smoke_hazard.tscn")
const SOUNDSCAPE_ZONE_SCENE: PackedScene = preload("res://environment/soundscape_zone.tscn")
const TAGGED_PROP_SCRIPT: GDScript = preload("res://environment/tagged_prop.gd")
const TAGGED_PROP_SCENE: PackedScene = preload("res://environment/tagged_prop.tscn")
const TARGET_VOLUME_SCENE: PackedScene = preload("res://environment/target_volume.tscn")
const UPDRAFT_VENT_SCENE: PackedScene = preload("res://environment/updraft_vent.tscn")
const WATERFALL_SCRIPT: GDScript = preload("res://environment/waterfall.gd")
const WOLF_CLIMB_SCENE: PackedScene = preload("res://environment/WolfClimbSurface.tscn")
const PULLEY_CABLE_SCRIPT: GDScript = preload("res://interactables/PulleyCableVisual3D.gd")
const CABLE_BUILDER_SCRIPT: GDScript = preload("res://interactables/cable_builder.gd")
const CHECKPOINT_SCENE: PackedScene = preload("res://interactables/checkpoint.tscn")
const DEV_COMMENTARY_SCENE: PackedScene = preload(
	"res://interactables/dev_comment/DeveloperCommentary.tscn"
)


## Verifies [OilSpillPath] constants, signals, ignition, damage, and extinguish contracts.
func test_oil_spill_path_contracts() -> void:
	assert_eq(OilSpillPath.INTERACTIVE_PHYSICS_LAYER, CollisionLayers.MASK_INTERACTIVE)

	var spill: OilSpillPath = OIL_SPILL_SCENE.instantiate() as OilSpillPath
	assert_not_null(spill)
	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0.0, 0.0, 4.0))
	spill.curve = curve
	add_child_autofree(spill)
	assert_has_signal(spill, &"ignited")
	assert_has_signal(spill, &"combustion_completed")

	assert_false(spill.is_burning)
	watch_signals(spill)
	spill.ignite(Vector3.ZERO)
	assert_true(spill.is_burning)
	assert_signal_emitted(spill, &"ignited")

	spill.extinguish()
	assert_false(spill.is_burning)

	spill.take_damage(10, Vector3.ZERO, Vector3.FORWARD)
	assert_true(spill.is_burning)
	spill.extinguish()


## Verifies [PoweredLight3D] enums, constants, signals, power, and flicker contracts.
func test_powered_light_3d_contracts() -> void:
	assert_eq(PoweredLight3D.ASCII_A, 97)
	assert_eq(PoweredLight3D.ASCII_M_OFFSET, 12.0)
	assert_eq(PoweredLight3D.PRESET_PATTERNS[PoweredLight3D.FlickerPreset.NORMAL], "m")
	assert_eq(
		PoweredLight3D.PRESET_PATTERNS[PoweredLight3D.FlickerPreset.FAST_STROBE], "mamamamamama"
	)

	var light_node: PoweredLight3D = POWERED_LIGHT_SCENE.instantiate() as PoweredLight3D
	assert_not_null(light_node)
	add_child_autofree(light_node)
	assert_has_signal(light_node, &"powered_on")
	assert_has_signal(light_node, &"powered_off")

	watch_signals(light_node)
	light_node.turn_on()
	assert_true(light_node.is_lit)
	assert_signal_emitted(light_node, &"powered_on")

	light_node.toggle()
	assert_false(light_node.is_lit)
	assert_signal_emitted(light_node, &"powered_off")

	light_node.set_flicker_preset(PoweredLight3D.FlickerPreset.FAST_STROBE)
	assert_eq(light_node.flicker_preset, PoweredLight3D.FlickerPreset.FAST_STROBE)
	assert_eq(light_node._pattern_scales.size(), 12)

	light_node.add_power()
	light_node.remove_power()


## Verifies [ProceduralBarbwire] enums, defaults, and curve generation contracts.
func test_procedural_barbwire_contracts() -> void:
	assert_eq(ProceduralBarbwire.WireType.STRAIGHT, 0)
	assert_eq(ProceduralBarbwire.WireType.SPRING, 1)

	var wire: ProceduralBarbwire = BARBWIRE_SCENE.instantiate() as ProceduralBarbwire
	assert_not_null(wire)
	add_child_autofree(wire)

	wire.wire_type = ProceduralBarbwire.WireType.STRAIGHT
	wire.length = 8.0
	var straight_curve: Curve3D = wire._generate_curve()
	assert_eq(straight_curve.point_count, 2)
	assert_eq(straight_curve.get_point_position(0), Vector3(-4.0, 0.0, 0.0))
	assert_eq(straight_curve.get_point_position(1), Vector3(4.0, 0.0, 0.0))

	wire.wire_type = ProceduralBarbwire.WireType.SPRING
	wire.spring_coils = 2
	wire.spring_resolution = 8
	var spring_curve: Curve3D = wire._generate_curve()
	assert_eq(spring_curve.point_count, 17)


## Verifies [MonkeyBarVolume] group, runtime visibility, and trigger box sizing contracts.
func test_monkey_bar_volume_contracts() -> void:
	var bar: MonkeyBarVolume = MONKEY_BAR_SCRIPT.new() as MonkeyBarVolume
	assert_not_null(bar)
	bar.size = Vector3(3.0, 0.5, 1.0)
	add_child_autofree(bar)

	assert_true(bar.is_in_group(&"monkey_bars"))
	assert_false(bar.visible)
	assert_false(bar.is_processing())
	assert_true(is_instance_valid(bar.interact_area))
	assert_true(is_instance_valid(bar.col_shape))
	var box: BoxShape3D = bar.col_shape.shape as BoxShape3D
	assert_not_null(box)
	assert_eq(box.size, Vector3(3.0, 2.0, 1.0))
	assert_almost_eq(bar.col_shape.position.y, -0.75, 0.001)


## Verifies [ProceduralTube] enums, constants, style defaults, and liquid fill contracts.
func test_procedural_tube_contracts() -> void:
	var style_enum: Variant = PROCEDURAL_TUBE_SCRIPT.get(&"TubeStyle")
	assert_not_null(style_enum)
	assert_eq(PROCEDURAL_TUBE_SCRIPT.get(&"PARAM_ALBEDO"), &"albedo_color")
	assert_eq(PROCEDURAL_TUBE_SCRIPT.get(&"PARAM_LIQUID_FILL"), &"liquid_fill")
	assert_eq(PROCEDURAL_TUBE_SCRIPT.get(&"PARAM_PATH_LENGTH"), &"path_length")

	var tube: Path3D = PROCEDURAL_TUBE_SCENE.instantiate() as Path3D
	assert_not_null(tube)
	add_child_autofree(tube)

	tube.set(&"style", 2)
	var metallic_val: Variant = tube.get(&"metallic")
	var roughness_val: Variant = tube.get(&"roughness")
	assert_almost_eq(metallic_val if metallic_val is float else 0.0, 0.9, 0.001)
	assert_almost_eq(roughness_val if roughness_val is float else 0.0, 0.22, 0.001)

	tube.set(&"liquid_fill", 1.5)
	var fill_val: Variant = tube.get(&"liquid_fill")
	assert_almost_eq(fill_val if fill_val is float else 0.0, 1.0, 0.001)
	assert_true(tube.has_method(&"tween_liquid_fill"))


## Verifies [SmokeHazard] signals, defaults, and direct body damage tick contracts.
func test_smoke_hazard_contracts() -> void:
	var hazard: SmokeHazard = SMOKE_HAZARD_SCENE.instantiate() as SmokeHazard
	assert_not_null(hazard)
	hazard.check_wall_occlusion = false
	hazard.damage_per_tick = 10.0
	add_child_autofree(hazard)
	assert_has_signal(hazard, &"damage_ticked")

	var target: Node3D = Node3D.new()
	var hc: HealthComponent = HealthComponent.new()
	hc.max_health = 100
	hc.current_health = 100
	target.add_child(hc)
	add_child_autofree(target)

	watch_signals(hazard)
	hazard._on_body_entered(target)
	assert_signal_emitted(hazard, &"damage_ticked")
	assert_eq(hc.current_health, 90)
	hazard._on_body_exited(target)


## Verifies [SoundscapeZone] constants, group, shape sync, and player entry/exit contracts.
func test_soundscape_zone_contracts() -> void:
	assert_eq(SoundscapeZone.DEBOUNCE_MSEC, 100)
	SoundscapeZone.current_active_zone = null
	SoundscapeZone.default_zone = null

	var zone: SoundscapeZone = SOUNDSCAPE_ZONE_SCENE.instantiate() as SoundscapeZone
	assert_not_null(zone)
	zone.zone_size = Vector3(6.0, 4.0, 8.0)
	var data: SoundscapeData = SoundscapeData.new()
	zone.soundscape = data
	add_child_autofree(zone)

	assert_true(zone.is_in_group(&"soundscape_zones"))
	var col: CollisionShape3D = zone._get_collision_shape()
	assert_not_null(col)
	assert_true(col.shape is BoxShape3D)
	var box: BoxShape3D = col.shape as BoxShape3D
	assert_eq(box.size, Vector3(6.0, 4.0, 8.0))

	var player: Node3D = Node3D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)

	zone._on_body_entered(player)
	assert_eq(SoundscapeZone.current_active_zone, zone)
	zone._on_body_exited(player)
	assert_null(SoundscapeZone.current_active_zone)

	SoundscapeZone.current_active_zone = null
	SoundscapeZone.default_zone = null


## Verifies [TaggedProp] enums, constants, metadata, shape switching, and size clamping.
func test_tagged_prop_contracts() -> void:
	assert_eq(TAGGED_PROP_SCRIPT.get(&"GROUP_TAGGED_PROP"), &"tagged_prop")
	assert_eq(TAGGED_PROP_SCRIPT.get(&"META_PROP_TAG"), &"prop_tag")
	assert_eq(TAGGED_PROP_SCRIPT.get(&"PARAM_PROP_COLOR"), &"prop_color")

	var prop: Node3D = TAGGED_PROP_SCENE.instantiate() as Node3D
	assert_not_null(prop)
	add_child_autofree(prop)

	assert_true(prop.is_in_group(&"tagged_prop"))
	prop.set(&"prop_tag", "  crate  ")
	assert_eq(prop.get_meta(&"prop_tag"), &"crate")

	prop.set(&"size", Vector3(0.0, 2.0, 3.0))
	assert_eq(prop.get(&"size"), Vector3(0.05, 2.0, 3.0))

	prop.set(&"prop_shape", 1)
	assert_true(prop.get(&"_active_shape") is CSGCylinder3D)
	prop.set(&"prop_shape", 2)
	assert_true(prop.get(&"_active_shape") is CSGSphere3D)


## Verifies [TargetVolume] enums, collision layers, and default pool settings.
func test_target_volume_contracts() -> void:
	assert_eq(TargetVolume.SpawnMode.TIME_BASED, 0)
	assert_eq(TargetVolume.SpawnMode.WAIT_FOR_KILL, 1)

	var volume: TargetVolume = TARGET_VOLUME_SCENE.instantiate() as TargetVolume
	assert_not_null(volume)
	add_child_autofree(volume)

	assert_eq(volume.collision_layer, 0)
	assert_eq(volume.collision_mask, 0)
	assert_eq(volume.max_active_targets, 3)
	assert_eq(volume.pool_size, 10)
	assert_eq(volume.active_distance, 40.0)


## Verifies [UpdraftVent] constants, paper strip count, and volume dimension contracts.
func test_updraft_vent_contracts() -> void:
	assert_eq(UpdraftVent.METHOD_ENTER_UPDRAFT, &"enter_updraft")
	assert_eq(UpdraftVent.METHOD_EXIT_UPDRAFT, &"exit_updraft")
	assert_eq(UpdraftVent.PARAM_WIND_SPEED, &"wind_speed")
	assert_eq(UpdraftVent.PARAM_STRIP_COLOR, &"strip_color")

	var vent: UpdraftVent = UPDRAFT_VENT_SCENE.instantiate() as UpdraftVent
	assert_not_null(vent)
	add_child_autofree(vent)

	assert_gt(vent.paper_strips_root.get_child_count(), 0)
	vent.radius = 2.0
	vent.height = 6.0
	var cyl: CylinderShape3D = vent.collision_shape.shape as CylinderShape3D
	assert_not_null(cyl)
	assert_almost_eq(cyl.radius, 2.0, 0.001)
	assert_almost_eq(cyl.height, 6.0, 0.001)


## Verifies [WaterfallStream] constants, group registration, flow speed, and VFX signals.
func test_waterfall_stream_contracts() -> void:
	assert_eq(WaterfallStream.GROUP_WATERFALL_AREA, &"waterfall_area")
	assert_eq(WaterfallStream.GROUP_PLAYER, &"player")
	assert_eq(WaterfallStream.PARAM_SCROLL_SPEED, &"scroll_speed")
	assert_eq(WaterfallStream.PARAM_REFRACTION_STRENGTH, &"refraction_strength")
	assert_eq(WaterfallStream.PARAM_WATER_TINT, &"water_tint")

	var stream: WaterfallStream = WATERFALL_SCRIPT.new() as WaterfallStream
	assert_not_null(stream)
	stream.mesh = PlaneMesh.new()
	add_child_autofree(stream)

	assert_true(stream.is_in_group(WaterfallStream.GROUP_WATERFALL_AREA))
	stream.set_flow_speed(Vector2(0.5, -2.5))
	assert_eq(stream.scroll_speed, Vector2(0.5, -2.5))

	var player: Node3D = Node3D.new()
	player.add_to_group(WaterfallStream.GROUP_PLAYER)
	add_child_autofree(player)

	watch_signals(Events)
	stream._on_waterfall_body_entered(player)
	assert_signal_emitted_with_parameters(Events, &"waterfall_vfx_toggled", [true, 1.0, 0.0])
	stream._on_waterfall_body_exited(player)
	assert_signal_emitted_with_parameters(Events, &"waterfall_vfx_toggled", [false, 0.0, 1.5])


## Verifies [WolfClimbSurface] constants, signals, geometry, bounds, cooldown, and latch contracts.
func test_wolf_climb_surface_contracts() -> void:
	assert_eq(WolfClimbSurface.GROUP_WOLF_CLIMBABLE, &"wolf_climbable")

	var surface: WolfClimbSurface = WOLF_CLIMB_SCENE.instantiate() as WolfClimbSurface
	assert_not_null(surface)
	add_child_autofree(surface)
	assert_has_signal(surface, &"latched_to_wall")
	assert_true(surface.is_in_group(WolfClimbSurface.GROUP_WOLF_CLIMBABLE))

	surface.set_surface_size(Vector2(6.0, 5.0))
	assert_eq(surface.surface_size, Vector2(6.0, 5.0))
	surface.set_surface_thickness(0.4)
	assert_almost_eq(surface.surface_thickness, 0.4, 0.001)
	assert_eq(surface.get_climb_normal(), Vector3(0.0, 0.0, 1.0))

	var mock_player: CharacterBody3D = CharacterBody3D.new()
	mock_player.add_to_group(&"player")
	mock_player.set_meta(&"is_wolf_mode", true)
	add_child_autofree(mock_player)
	mock_player.global_position = Vector3(0.0, 0.0, 0.0)
	assert_true(surface.is_character_on_surface(mock_player))
	mock_player.global_position = Vector3(10.0, 0.0, 0.0)
	assert_false(surface.is_character_on_surface(mock_player))

	assert_false(surface.has_dismount_cooldown(mock_player))
	surface.set_dismount_cooldown(mock_player, 500)
	assert_true(surface.has_dismount_cooldown(mock_player))


## Verifies [PulleyCableVisual3D] constants and endpoint stretching behavior.
func test_pulley_cable_visual_3d_contracts() -> void:
	assert_almost_eq(PulleyCableVisual3D.POSITION_EPSILON_SQUARED, 0.000001, 0.0000001)
	assert_almost_eq(PulleyCableVisual3D.MIN_SPAN_DISTANCE_SQUARED, 0.000001, 0.0000001)

	var cable: PulleyCableVisual3D = PULLEY_CABLE_SCRIPT.new() as PulleyCableVisual3D
	var anchor: Node3D = Node3D.new()
	var cart_node: Node3D = Node3D.new()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	cable.overhead_anchor = anchor
	cable.cart = cart_node
	cable.cable_mesh = mesh_inst
	add_child_autofree(cable)
	add_child_autofree(anchor)
	add_child_autofree(cart_node)
	add_child_autofree(mesh_inst)

	anchor.global_position = Vector3(0.0, 10.0, 0.0)
	cart_node.global_position = Vector3(0.0, 2.0, 0.0)
	cable._stretch_cable_to_fit(anchor.global_position, cart_node.global_position)
	assert_almost_eq(mesh_inst.global_position.y, 6.0, 0.01)
	assert_almost_eq(mesh_inst.scale.y, 4.0, 0.01)


## Verifies [CableBuilderComponent] curve trimming and cylinder height synchronization.
func test_cable_builder_component_contracts() -> void:
	var builder: CableBuilderComponent = CABLE_BUILDER_SCRIPT.new() as CableBuilderComponent
	var path: Path3D = Path3D.new()
	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 0.0))
	curve.add_point(Vector3(0.0, 0.0, 6.0))
	curve.add_point(Vector3(0.0, 0.0, 9.0))
	path.curve = curve

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.mesh = CylinderMesh.new()
	var col_node: CollisionShape3D = CollisionShape3D.new()
	col_node.shape = CylinderShape3D.new()

	builder.path_node = path
	builder.mesh_node = mesh_inst
	builder.collision_node = col_node
	add_child_autofree(path)
	add_child_autofree(mesh_inst)
	add_child_autofree(col_node)
	add_child_autofree(builder)

	assert_eq(path.curve.get_point_count(), 2)
	var cyl_mesh: CylinderMesh = mesh_inst.mesh as CylinderMesh
	var cyl_shape: CylinderShape3D = col_node.shape as CylinderShape3D
	assert_almost_eq(cyl_mesh.height, 6.0, 0.01)
	assert_almost_eq(cyl_shape.height, 6.0, 0.01)


## Verifies [Checkpoint] scene instantiation, activation, and deactivation contracts.
func test_checkpoint_scene_contracts() -> void:
	var prev_pos: Vector3 = SaveManager.last_checkpoint_pos
	var cp: Checkpoint = CHECKPOINT_SCENE.instantiate() as Checkpoint
	assert_not_null(cp)
	add_child_autofree(cp)
	cp.global_position = Vector3(5.0, 1.0, -3.0)

	assert_true(cp.is_in_group(&"checkpoints"))
	assert_false(cp.is_activated)
	cp.activate_checkpoint()
	assert_true(cp.is_activated)
	assert_eq(SaveManager.last_checkpoint_pos, Vector3(5.0, 1.0, -3.0))

	cp.deactivate_checkpoint()
	assert_false(cp.is_activated)
	SaveManager.last_checkpoint_pos = prev_pos


## Verifies [DeveloperCommentary] constants, initial state, open/close, and subtitle signals.
func test_developer_commentary_contracts() -> void:
	assert_eq(DeveloperCommentary.VU_COUNT, 32)

	var comm: DeveloperCommentary = DEV_COMMENTARY_SCENE.instantiate() as DeveloperCommentary
	assert_not_null(comm)
	comm.commentary_title = "Test Title"
	comm.commentary_content = "Test Content"
	add_child_autofree(comm)

	assert_false(comm.is_open)
	assert_false(comm.is_processing())
	assert_false(comm.commentary_ui.visible)
	assert_false(comm.equalizer_mesh.visible)

	watch_signals(Events)
	comm.open_commentary()
	assert_true(comm.is_open)
	assert_true(comm.is_processing())
	assert_true(comm.commentary_ui.visible)
	assert_true(comm.equalizer_mesh.visible)

	comm.close_commentary()
	assert_false(comm.is_open)
	assert_false(comm.is_processing())
	assert_false(comm.commentary_ui.visible)
	assert_false(comm.equalizer_mesh.visible)
	assert_signal_emitted(Events, &"subtitle_canceled")
