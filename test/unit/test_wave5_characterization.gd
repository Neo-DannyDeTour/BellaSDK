## Characterization tests locking Wave 5 public APIs, constants, signals, and behavior.
class_name TestWave5Characterization
extends GutTest

const BREAKABLE_SHELF_SCRIPT: GDScript = preload("res://props/breakable_shelf/breakable_shelf.gd")
const GARAGE_GATE_SCRIPT: GDScript = preload("res://props/garage_gate/garage_gate.gd")
const GOTHIC_ARCH_POST_IMPORT_SCRIPT: GDScript = preload(
	"res://props/gothic_arch/gothic_arch_post_import.gd"
)
const GOTHIC_ARCH_PROP_SCRIPT: GDScript = preload("res://props/gothic_arch/gothic_arch_prop.gd")


class _MockShell:
	extends Node3D

	var drop_count: int = 0

	func trigger_drop() -> void:
		drop_count += 1


class _MockKillfieldPlayer:
	extends Node3D

	var noclip: bool = false
	var teleport_calls: int = 0
	var last_teleport_pos: Vector3 = Vector3.ZERO
	var last_teleport_dur: float = -1.0

	func teleport_to(pos: Vector3, dur: float = 0.0) -> void:
		teleport_calls += 1
		last_teleport_pos = pos
		last_teleport_dur = dur


class _MockPowerTarget:
	extends Node

	var power_count: int = 0

	func add_power() -> void:
		power_count += 1


class _MockHealthModifier:
	extends HealthModifier

	var mock_bodies: Array[Node3D] = []

	func _get_target_bodies() -> Array[Node3D]:
		return mock_bodies


## Verifies [FactionComponent] allegiance, hostility mask, signals, and static lookup.
func test_faction_component_contracts() -> void:
	var primary: Node3D = Node3D.new()
	var fc_a: FactionComponent = FactionComponent.new()
	fc_a.name = "FactionComponent"
	primary.add_child(fc_a)
	add_child_autofree(primary)

	var secondary: Node3D = Node3D.new()
	var comps: Node = Node.new()
	comps.name = "Components"
	var fc_b: FactionComponent = FactionComponent.new()
	fc_b.name = "FactionComponent"
	comps.add_child(fc_b)
	secondary.add_child(comps)
	add_child_autofree(secondary)

	assert_eq(fc_a.faction, Types.Faction.ENEMY)
	assert_eq(fc_a.hostile_mask, 1)
	assert_false(fc_a.is_passive)

	fc_b.faction = Types.Faction.PLAYER
	assert_true(fc_a.is_hostile_to(fc_b))
	fc_b.is_passive = true
	assert_false(fc_a.is_hostile_to(fc_b))
	fc_b.is_passive = false

	fc_a.add_hostile_faction(Types.Faction.CIVILIAN)
	fc_b.faction = Types.Faction.CIVILIAN
	assert_true(fc_a.is_hostile_to(fc_b))

	watch_signals(fc_a)
	fc_a.set_faction(Types.Faction.ENEMY)
	assert_signal_not_emitted(fc_a, "faction_changed")
	fc_a.set_faction(Types.Faction.NEUTRAL)
	assert_signal_emitted_with_parameters(
		fc_a, "faction_changed", [Types.Faction.ENEMY, Types.Faction.NEUTRAL]
	)

	assert_eq(FactionComponent.get_faction_component(primary), fc_a)
	assert_eq(FactionComponent.get_faction_component(secondary), fc_b)
	assert_null(FactionComponent.get_faction_component(null))


## Verifies [HealthComponent] damage, healing, godmode, pooling, and random range.
func test_health_component_contracts() -> void:
	var actor: Node3D = Node3D.new()
	var hc: HealthComponent = HealthComponent.new()
	hc.max_health = 100
	actor.add_child(hc)
	add_child_autofree(actor)
	watch_signals(hc)

	assert_true(hc.is_in_group(&"damageable"))
	hc.take_damage(0)
	hc.take_damage(-5)
	assert_eq(hc.current_health, 100)

	hc.take_damage(30)
	assert_eq(hc.current_health, 70)
	assert_signal_emitted_with_parameters(hc, "health_changed", [70])

	hc.heal(50)
	assert_eq(hc.current_health, 100)

	hc.increase_max_health(25)
	assert_eq(hc.max_health, 125)
	assert_eq(hc.current_health, 125)
	assert_signal_emitted_with_parameters(hc, "max_health_changed", [125])

	var prev_godmode: bool = Events.is_godmode
	hc.is_player_health = true
	Events.is_godmode = true
	hc.take_damage(50)
	assert_eq(hc.current_health, 125)
	Events.is_godmode = prev_godmode
	hc.is_player_health = false

	hc.take_damage(999)
	assert_eq(hc.current_health, 0)
	assert_signal_emitted(hc, "died")
	assert_false(actor.visible)
	assert_eq(actor.process_mode, Node.PROCESS_MODE_DISABLED)

	hc.heal(20)
	assert_eq(hc.current_health, 0)

	hc.reset()
	assert_eq(hc.current_health, 125)
	assert_true(actor.visible)
	assert_eq(actor.process_mode, Node.PROCESS_MODE_INHERIT)


## Verifies [HealthModifier] timer creation, collision bounds sync, and tick damage/heal.
func test_health_modifier_contracts() -> void:
	var mod: _MockHealthModifier = _MockHealthModifier.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	mod.add_child(col)
	mod.tick_interval = 0.25
	add_child_autofree(mod)

	assert_eq(mod.modify_amount, -25)
	assert_true(col.shape is BoxShape3D)
	assert_not_null(mod.get_node_or_null("TickTimer"))

	mod.shape_type = EditorTriggerVisualizer.ShapeType.SPHERE
	mod.trigger_size = Vector3(4.0, 4.0, 4.0)
	assert_true(col.shape is SphereShape3D)
	var sphere: SphereShape3D = col.shape as SphereShape3D
	assert_almost_eq(sphere.radius, 2.0, 0.0001)

	var body: Node3D = Node3D.new()
	var hc: HealthComponent = HealthComponent.new()
	hc.max_health = 100
	body.add_child(hc)
	add_child_autofree(body)

	mod.mock_bodies = [body]
	mod._on_tick_timer_timeout()
	assert_eq(hc.current_health, 75)

	mod.modify_amount = 15
	mod._on_tick_timer_timeout()
	assert_eq(hc.current_health, 90)


## Verifies [WaveGenerator] constants, idle gating, empty update guard, and JONSWAP math.
func test_wave_generator_contracts() -> void:
	assert_almost_eq(WaveGenerator.G, 9.81, 0.0001)
	assert_almost_eq(WaveGenerator.DEPTH, 20.0, 0.0001)
	assert_eq(WaveGenerator.KEY_SPECTRUM, &"spectrum")
	assert_eq(WaveGenerator.KEY_DISPLACEMENT, &"displacement_map")
	assert_eq(WaveGenerator.KEY_NORMAL, &"normal_map")
	assert_eq(WaveGenerator.PIPE_SPECTRUM_COMPUTE, &"spectrum_compute")
	assert_eq(WaveGenerator.PIPE_FFT_UNPACK, &"fft_unpack")

	var wg: WaveGenerator = WaveGenerator.new()
	add_child_autofree(wg)
	assert_eq(wg.cpu_map_size, 128)
	assert_false(wg.is_initialized)
	assert_false(wg.is_processing())
	assert_false(wg.is_physics_processing())

	var empty_params: Array[WaveCascadeParameters] = []
	wg.update(0.016, empty_params)
	assert_false(wg.is_initialized)

	var alpha: float = wg.jonswap_alpha(20.0, 550e3)
	var omega: float = wg.jonswap_peak_angular_frequency(20.0, 550e3)
	assert_gt(alpha, 0.0)
	assert_gt(omega, 0.0)


## Verifies [BreakableShelf] constants, damage absorption, and deferred break behavior.
func test_breakable_shelf_contracts() -> void:
	var shelf: RigidBody3D = BREAKABLE_SHELF_SCRIPT.new() as RigidBody3D
	assert_eq(shelf.get("SHADER_ALPHA_PARAM"), &"albedo_alpha")
	assert_eq(shelf.get("LAYER_DEBRIS"), CollisionLayers.MASK_DEBRIS)
	assert_eq(
		shelf.get("MASK_DEBRIS"), CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_DEBRIS
	)
	assert_almost_eq(float(shelf.get("FADE_DELAY_SEC")), 4.0, 0.0001)
	assert_almost_eq(float(shelf.get("FADE_DURATION_SEC")), 1.0, 0.0001)

	var intact: Node3D = Node3D.new()
	intact.name = "IntactVisuals"
	shelf.add_child(intact)
	var gibs: Node3D = Node3D.new()
	gibs.name = "Gibs"
	gibs.visible = false
	for i: int in range(5):
		var gib: RigidBody3D = RigidBody3D.new()
		gib.name = "Gib_" + str(i)
		autofree(gib)
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = "Mesh"
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.name = "Shape"
		shape.disabled = true
		gib.add_child(mesh)
		gib.add_child(shape)
		gibs.add_child(gib)
	shelf.add_child(gibs)
	add_child_autofree(shelf)
	watch_signals(shelf)

	assert_false(shelf.is_processing())
	assert_false(shelf.is_physics_processing())

	shelf.call(&"take_damage", 5.0, Vector3.ZERO)
	assert_false(bool(shelf.get("_is_broken")))
	shelf.call(&"take_damage", 25.0, Vector3.ZERO, Vector3.UP)
	assert_true(bool(shelf.get("_is_broken")))
	await get_tree().process_frame
	assert_signal_emitted(shelf, "broken")
	assert_false(intact.visible)
	assert_true(gibs.visible)


## Verifies [GarageGate] constants, panel generation, and open/close state transitions.
func test_garage_gate_contracts() -> void:
	var gate: Node3D = GARAGE_GATE_SCRIPT.new() as Node3D
	assert_eq(gate.get("PANEL_COUNT"), 4)
	assert_almost_eq(float(gate.get("PANEL_WIDTH")), 3.0, 0.0001)
	assert_almost_eq(float(gate.get("PANEL_HEIGHT")), 0.60, 0.0001)
	assert_almost_eq(float(gate.get("SLACK_GAP")), 0.038, 0.0001)
	assert_almost_eq(float(gate.get("PHASE_1_RATIO")), 0.15, 0.0001)
	assert_almost_eq(float(gate.get("MAX_TRAVEL_DIST")), 2.35, 0.0001)
	assert_eq(gate.get("SFX_BUS"), &"SFX")
	assert_eq(gate.get("PARAM_WEAR_OFFSET"), &"wear_offset")

	gate.set("panel_mesh", BoxMesh.new())
	gate.set("frame_mesh", BoxMesh.new())
	add_child_autofree(gate)

	assert_false(bool(gate.get("is_open")))
	assert_false(gate.is_processing())
	assert_false(gate.is_physics_processing())
	assert_not_null(gate.get_node_or_null("FrameMesh"))
	assert_not_null(gate.get_node_or_null("Panel_0"))
	assert_not_null(gate.get_node_or_null("Panel_3"))

	gate.call(&"toggle_gate")
	assert_true(bool(gate.get("is_open")))
	gate.call(&"set_gate_open", false)
	assert_false(bool(gate.get("is_open")))


## Verifies [GothicArchProp] and [GothicArchPostImport] constants and layer invariants.
func test_gothic_arch_contracts() -> void:
	var prop: StaticBody3D = GOTHIC_ARCH_PROP_SCRIPT.new() as StaticBody3D
	var arch_mesh: MeshInstance3D = MeshInstance3D.new()
	arch_mesh.name = "ArchMesh"
	prop.add_child(arch_mesh)
	add_child_autofree(prop)

	assert_eq(prop.get("PARAM_TINT"), &"instance_tint")
	assert_eq(prop.get("PARAM_WEAR"), &"wear_intensity")
	assert_eq(prop.get("PARAM_MOSS"), &"moss_coverage")
	assert_eq(prop.collision_layer, CollisionLayers.MASK_ENVIRONMENT)
	assert_eq(prop.collision_mask, CollisionLayers.MASK_NONE)
	assert_eq(arch_mesh.layers, CollisionLayers.RENDER_MASK_ENVIRONMENT)
	assert_false(prop.is_processing())
	assert_false(prop.is_physics_processing())

	var consts: Dictionary = GOTHIC_ARCH_POST_IMPORT_SCRIPT.get_script_constant_map()
	assert_eq(consts.get("SHADER_FILE"), "gothic_arch_stone.gdshader")
	assert_eq(consts.get("PROP_SCRIPT_FILE"), "gothic_arch_prop.gd")
	assert_eq(consts.get("MAT_FILE"), "gothic_arch_mat.tres")
	assert_eq(consts.get("PILLAR_SIZE"), Vector3(0.6, 3.55, 0.8))
	assert_eq(consts.get("LINTEL_SIZE"), Vector3(3.0, 0.45, 0.8))


## Verifies [BaseTriggerArea3D] layers, shape sync, player filtering, and once/repeat rules.
func test_base_trigger_area_3d_contracts() -> void:
	var trigger: BaseTriggerArea3D = BaseTriggerArea3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	trigger.add_child(col)
	add_child_autofree(trigger)
	watch_signals(trigger)

	assert_eq(trigger.collision_layer, CollisionLayers.MASK_NONE)
	assert_eq(trigger.collision_mask, CollisionLayers.MASK_PLAYER)
	assert_true(col.shape is BoxShape3D)
	assert_not_null(trigger.get_node_or_null("EditorTriggerVisualizer"))

	trigger.shape_type = EditorTriggerVisualizer.ShapeType.CYLINDER
	trigger.trigger_size = Vector3(4.0, 3.0, 4.0)
	assert_true(col.shape is CylinderShape3D)
	var cyl: CylinderShape3D = col.shape as CylinderShape3D
	assert_almost_eq(cyl.radius, 2.0, 0.0001)
	assert_almost_eq(cyl.height, 3.0, 0.0001)

	var non_player: Node3D = Node3D.new()
	non_player.name = "Crate"
	add_child_autofree(non_player)
	trigger._on_body_entered(non_player)
	assert_signal_not_emitted(trigger, "player_entered")

	var player_node: Node3D = Node3D.new()
	player_node.name = "Player"
	player_node.add_to_group(&"player")
	add_child_autofree(player_node)

	trigger._on_body_entered(player_node)
	assert_signal_emit_count(trigger, "player_entered", 1)
	trigger._on_body_entered(player_node)
	assert_signal_emit_count(trigger, "player_entered", 1)

	trigger.trigger_once = false
	trigger._on_body_entered(player_node)
	assert_signal_emit_count(trigger, "player_entered", 2)
	trigger._on_body_exited(player_node)
	assert_signal_emitted_with_parameters(trigger, "player_exited", [player_node])


## Verifies [CrabShellTrigger] defaults, shell activation, and self-freeing behavior.
func test_crab_shell_trigger_contracts() -> void:
	var shell: _MockShell = _MockShell.new()
	add_child_autofree(shell)

	var trigger: CrabShellTrigger = CrabShellTrigger.new()
	trigger.linked_shell = shell
	add_child_autofree(trigger)
	assert_eq(trigger.trigger_text, "CRAB TRAP")

	var actor: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(actor)
	trigger._on_body_entered(actor)
	assert_eq(shell.drop_count, 1)
	await get_tree().process_frame
	assert_true(not is_instance_valid(trigger) or trigger.is_queued_for_deletion())


## Verifies [DrunkTrigger], [EnvChapterTrigger], [FadeTrigger], and [HintTrigger] Events.
func test_event_dispatching_triggers_contracts() -> void:
	var player_node: Node3D = Node3D.new()
	player_node.name = "Player"
	add_child_autofree(player_node)
	watch_signals(Events)

	var drunk: DrunkTrigger = DrunkTrigger.new()
	drunk.target_intensity = 0.75
	drunk.transition_duration = 0.5
	drunk.exit_duration = 1.2
	add_child_autofree(drunk)
	assert_eq(drunk.trigger_text, "DRUNK TRIGGER")
	drunk._on_player_entered(player_node)
	assert_signal_emitted_with_parameters(Events, "drunk_intensity_changed", [0.75, 0.5])
	drunk._on_player_exited(player_node)
	assert_signal_emitted_with_parameters(Events, "drunk_intensity_changed", [0.0, 1.2])

	var chapter: EnvChapterTrigger = EnvChapterTrigger.new()
	chapter.chapter_name = "Act II"
	chapter.animation_style = Events.ChapterAnimStyle.SIMPLE
	chapter.display_duration = 4.0
	chapter.text_color = Color.RED
	add_child_autofree(chapter)
	assert_eq(chapter.trigger_text, "CHAPTER TRIGGER")
	chapter._on_player_entered(player_node)
	assert_signal_emitted_with_parameters(
		Events, "chapter_triggered", ["Act II", int(Events.ChapterAnimStyle.SIMPLE), 4.0, Color.RED]
	)

	var fade: FadeTrigger = FadeTrigger.new()
	fade.fade_color = Color.BLUE
	fade.fade_in_duration = 0.2
	fade.hold_duration = 0.3
	fade.fade_out_duration = 0.4
	fade.use_blur = false
	fade.max_blur = 1.0
	fade.use_blink = true
	fade.blink_count = 2
	add_child_autofree(fade)
	assert_eq(fade.trigger_text, "FADE TRIGGER")
	fade._on_player_entered(player_node)
	assert_signal_emitted_with_parameters(
		Events, "screen_fade_requested", [Color.BLUE, 0.2, 0.3, 0.4, false, 1.0, true, 2]
	)

	var hint: HintTrigger = HintTrigger.new()
	hint.hint_type = HintTrigger.HintType.CUSTOM
	hint.custom_message = "Custom Wave 5 Hint"
	hint.duration = 2.5
	add_child_autofree(hint)
	assert_eq(hint.trigger_text, "HINT")
	hint._on_player_entered(player_node)
	assert_signal_emitted_with_parameters(Events, "hint_requested", ["Custom Wave 5 Hint", 2.5])


## Verifies [EditorTriggerVisualizer] gizmo child creation, group, and visibility toggle.
func test_editor_trigger_visualizer_contracts() -> void:
	var vis: EditorTriggerVisualizer = EditorTriggerVisualizer.new()
	add_child_autofree(vis)

	assert_true(vis.is_in_group(&"trigger_visualizers"))
	assert_not_null(vis.get_node_or_null("Wireframe"))
	assert_not_null(vis.get_node_or_null("DirectionArrow"))
	assert_not_null(vis.get_node_or_null("VisualizerLabel"))
	assert_false(vis.visible)

	vis.set_debug_visibility(true)
	assert_true(vis.visible)
	vis.set_debug_visibility(false)
	assert_false(vis.visible)


## Verifies [Killfield], [SpotlightSeqTrigger], [Teleport], and [WakeUpTrigger] contracts.
func test_spatial_utility_triggers_contracts() -> void:
	var saved_checkpoint: Vector3 = SaveManager.last_checkpoint_pos
	SaveManager.last_checkpoint_pos = Vector3(10.0, 2.0, -5.0)

	var kf: Killfield = Killfield.new()
	kf.spawn_height_offset = 1.5
	add_child_autofree(kf)
	assert_false(kf.trigger_once)
	assert_eq(kf.trigger_text, "KILLFIELD")

	var kf_player: _MockKillfieldPlayer = _MockKillfieldPlayer.new()
	add_child_autofree(kf_player)
	kf_player.noclip = true
	kf._on_player_entered(kf_player)
	assert_eq(kf_player.teleport_calls, 0)

	kf_player.noclip = false
	kf._on_player_entered(kf_player)
	assert_eq(kf_player.teleport_calls, 1)
	assert_eq(kf_player.last_teleport_pos, Vector3(10.0, 3.5, -5.0))
	assert_almost_eq(kf_player.last_teleport_dur, 0.2, 0.0001)
	SaveManager.last_checkpoint_pos = saved_checkpoint

	var spot: SpotlightSeqTrigger = SpotlightSeqTrigger.new()
	var anim: AnimationPlayer = AnimationPlayer.new()
	spot.sequence_player = anim
	add_child_autofree(anim)
	add_child_autofree(spot)
	assert_eq(spot.trigger_text, "SPOTLIGHT_SEQ")

	var portal_dest: Area3D = Area3D.new()
	add_child_autofree(portal_dest)
	portal_dest.global_position = Vector3(5.0, 1.0, 8.0)
	var tp: Teleport = Teleport.new()
	tp.connect_portal = portal_dest
	add_child_autofree(tp)
	assert_false(tp.trigger_once)
	tp._on_player_entered(kf_player)
	assert_eq(kf_player.global_position, Vector3(5.0, 1.0, 8.0))

	var wake: WakeUpTrigger = WakeUpTrigger.new()
	add_child_autofree(wake)
	assert_eq(wake.trigger_text, "WAKE UP TRIGGER")
	assert_almost_eq(wake.eye_open_duration, 2.0, 0.0001)
	assert_eq(wake.blink_count, 3)
	assert_almost_eq(wake.lying_camera_height, 0.25, 0.0001)
	assert_almost_eq(wake.lying_camera_roll, -28.0, 0.0001)
	assert_almost_eq(wake.look_up_pitch, 38.0, 0.0001)


## Verifies [MannequinAttractorTrigger3D] bone presets and [TargetArrivalBox3D] containment.
func test_mannequin_attractor_and_arrival_box_contracts() -> void:
	var attractor: MannequinAttractorTrigger3D = MannequinAttractorTrigger3D.new()
	add_child_autofree(attractor)
	assert_eq(attractor.bone_preset, MannequinAttractorTrigger3D.BonePreset.TORSO)
	assert_eq(attractor.target_bones, MannequinAttractorTrigger3D.PRESET_TORSO_BONES)

	attractor.bone_preset = MannequinAttractorTrigger3D.BonePreset.HEAD
	assert_eq(attractor.target_bones, MannequinAttractorTrigger3D.PRESET_HEAD_BONES)
	attractor.bone_preset = MannequinAttractorTrigger3D.BonePreset.ALL
	assert_eq(attractor.target_bones.size(), 17)

	var box: TargetArrivalBox3D = TargetArrivalBox3D.new()
	box.trigger_size = Vector3(2.0, 2.0, 2.0)
	box.trigger_offset = Vector3(1.0, 0.0, 0.0)
	add_child_autofree(box)
	assert_eq(box.trigger_text, "DESTINATION")
	assert_eq(box.get_target_center(), Vector3(1.0, 0.0, 0.0))
	assert_true(box.contains_point(Vector3(1.5, 0.5, 0.5)))
	assert_false(box.contains_point(Vector3(-0.5, 0.0, 0.0)))

	box.shape_type = EditorTriggerVisualizer.ShapeType.SPHERE
	assert_true(box.contains_point(Vector3(1.9, 0.0, 0.0)))
	assert_false(box.contains_point(Vector3(2.2, 0.0, 0.0)))


## Verifies [MusicTrigger3D] constants, clamping setters, and self-connection guard.
func test_music_trigger_contracts() -> void:
	assert_eq(MusicTrigger3D.TRIGGER_GROUP, "music_triggers")
	assert_almost_eq(MusicTrigger3D.BOUNDARY_TOLERANCE_SEC, 0.05, 0.0001)
	assert_eq(MusicTrigger3D.SwitchMode.IMMEDIATE, 0)
	assert_eq(MusicTrigger3D.SwitchMode.END_OF_SECTION, 1)

	var mt: MusicTrigger3D = MusicTrigger3D.new()
	add_child_autofree(mt)
	mt.section_index = 0
	assert_eq(mt.section_index, 1)
	mt.custom_start_time = -5.0
	assert_almost_eq(mt.custom_start_time, 0.0, 0.0001)
	mt.custom_end_time = -2.0
	assert_almost_eq(mt.custom_end_time, 0.0, 0.0001)
	mt.connected_music_trigger = mt
	assert_null(mt.connected_music_trigger)


## Verifies [TriggerLook] gaze process gating, fire_once alias, and target power dispatch.
func test_trigger_look_contracts() -> void:
	var target: _MockPowerTarget = _MockPowerTarget.new()
	add_child_autofree(target)

	var look: TriggerLook = TriggerLook.new()
	look.targets = [target]
	add_child_autofree(look)

	assert_false(look.auto_consume_on_entry)
	assert_false(look.is_processing())
	look.fire_once = false
	assert_false(look.trigger_once)
	look.fire_once = true

	var player_node: Node3D = Node3D.new()
	player_node.name = "Player"
	add_child_autofree(player_node)

	look._on_player_entered(player_node)
	assert_true(look.is_processing())
	look._on_player_exited(player_node)
	assert_false(look.is_processing())

	look._trigger_event()
	assert_eq(target.power_count, 1)


## Verifies [ControlExplosion] and [WaterLeak] VFX contracts.
func test_vfx_wave5_contracts() -> void:
	assert_eq(ControlExplosion.RENDER_LAYER_ENVIRONMENT, 1)
	assert_eq(ControlExplosion.RENDER_LAYER_VOLUMETRICS, 1 << 9)
	assert_eq(ControlExplosion.PHYSICS_LAYER_ENVIRONMENT, 1)
	assert_eq(
		ControlExplosion.PHYSICS_MASK_BLAST_TARGETS, (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
	)
	assert_eq(ControlExplosion.PARAM_PROGRESS, &"explosion_progress")
	assert_eq(ControlExplosion.PARAM_DISTORTION, &"distortion_strength")

	var explosion: ControlExplosion = ControlExplosion.new()
	explosion.blast_radius = 0.1
	assert_almost_eq(explosion.blast_radius, 0.5, 0.0001)
	add_child_autofree(explosion)
	assert_false(explosion.is_processing())
	assert_false(explosion.is_physics_processing())
	explosion.detonate()
	assert_true(explosion.is_physics_processing())

	assert_eq(WaterLeak.PARAM_LEAK_COLOR, &"leak_color")
	assert_eq(WaterLeak.PARAM_IS_BILLBOARD, &"is_billboard")
	assert_eq(WaterLeak.ARC_STEPS, 8)
	assert_almost_eq(WaterLeak.MAX_ARC_TIME, 1.5, 0.0001)
	assert_eq(WaterLeak.ENV_COLLISION_MASK, 1)
	assert_eq(WaterLeak.PLAYER_COLLISION_MASK, 2)

	var leak: WaterLeak = WaterLeak.new()
	leak.leak_speed = 0.1
	assert_almost_eq(leak.leak_speed, 0.5, 0.0001)
	leak.leak_amount = 2
	assert_eq(leak.leak_amount, 12)
	var jet: GPUParticles3D = GPUParticles3D.new()
	jet.name = "JetStream"
	var mist: GPUParticles3D = GPUParticles3D.new()
	mist.name = "MistSpray"
	var splash: GPUParticles3D = GPUParticles3D.new()
	splash.name = "ImpactSplash"
	var audio: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	audio.name = "LeakAudio"
	var notifier: VisibleOnScreenNotifier3D = VisibleOnScreenNotifier3D.new()
	notifier.name = "ScreenNotifier"
	var zone: Area3D = Area3D.new()
	zone.name = "SplashZone"
	var zone_col: CollisionShape3D = CollisionShape3D.new()
	zone_col.name = "CollisionShape3D"
	zone.add_child(zone_col)
	leak.add_child(jet)
	leak.add_child(mist)
	leak.add_child(splash)
	leak.add_child(audio)
	leak.add_child(notifier)
	leak.add_child(zone)
	add_child_autofree(leak)

	assert_false(leak.is_processing())
	assert_false(leak.is_physics_processing())
	assert_eq(zone.collision_layer, 0)
	assert_eq(zone.collision_mask, WaterLeak.PLAYER_COLLISION_MASK)
