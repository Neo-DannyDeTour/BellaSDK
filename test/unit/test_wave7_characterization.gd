## Characterization tests locking Wave 7 public APIs, constants, signals, and behavior.
class_name TestWave7Characterization
extends GutTest

const DYNAMIC_FOG_SCENE: PackedScene = preload("res://environment/DynamicFog/dynamic_fog_zone.tscn")
const ACCESSIBLE_LABEL_SCENE: PackedScene = preload("res://environment/accessible_label_body.tscn")
const ARGON_WATER_SCENE: PackedScene = preload(
	"res://environment/argon_water_body/argon_water_body.tscn"
)
const BASALT_GENERATOR_SCENE: PackedScene = preload("res://environment/basalt_generator.tscn")
const CITADEL_CORE_SCENE: PackedScene = preload("res://environment/citadel_core.tscn")
const CRAB_SHELL_SCENE: PackedScene = preload("res://environment/crab_shell.tscn")
const DUST_VOLUME_SCENE: PackedScene = preload("res://environment/dust_volume.tscn")
const ELECTRIFIED_FLOOR_SCENE: PackedScene = preload("res://environment/electrified_floor.tscn")
const FLAG_WAVING_SCENE: PackedScene = preload("res://environment/flag_waving.tscn")
const GOTHIC_GATE_SCENE: PackedScene = preload("res://environment/gothic_energy_gate.tscn")
const HIGHLIGHT_COMPONENT_SCRIPT: GDScript = preload("res://environment/highlight_component.gd")
const LIGHTNING_ORB_SCENE: PackedScene = preload("res://environment/lightning_orb.tscn")
const RAIN_CONTROLLER_SCENE: PackedScene = preload("res://environment/rain_controller.tscn")
const SNOW_GROUND_SCRIPT: GDScript = preload("res://environment/snow_ground.gd")
const SUPPLY_SHELL_SCENE: PackedScene = preload("res://environment/supply_shell.tscn")
const UNDERWATER_FOG_SCRIPT: GDScript = preload("res://environment/UnderwaterFogVolume.gd")
const WATER_BODY_SCENE: PackedScene = preload("res://environment/water_body.tscn")
const WAYPOINT_3D_SCENE: PackedScene = preload("res://environment/waypoint_3d.tscn")
const WORLD_ENV_SCRIPT: GDScript = preload("res://environment/world_environment.gd")


## Verifies [DynamicFogZone] enums, constants, AABB queries, optical depth, and carving.
func test_dynamic_fog_zone_contracts() -> void:
	assert_eq(DynamicFogZone.FogMode.GROUND_HUGGING, 0)
	assert_eq(DynamicFogZone.FogMode.FULL_ROOM, 1)
	assert_eq(DynamicFogZone.FogMode.CUSTOM, 2)
	assert_eq(DynamicFogZone.MAX_RAYS, 8)
	assert_eq(DynamicFogZone.MAX_ACTORS, 8)
	assert_eq(DynamicFogZone.RENDER_LAYER_VOLUMETRICS, 1 << 9)
	assert_eq(DynamicFogZone.MIN_WAKE_SPEED_SQ, 0.25)
	assert_eq(DynamicFogZone.PARAM_BASE_COLOR, &"base_color")

	var fog: DynamicFogZone = DYNAMIC_FOG_SCENE.instantiate() as DynamicFogZone
	assert_not_null(fog)
	add_child_autofree(fog)
	fog.size = Vector3(10.0, 4.0, 10.0)
	fog.global_position = Vector3.ZERO

	assert_true(fog.intersects_world_aabb(AABB(Vector3(-1.0, -1.0, -1.0), Vector3.ONE)))
	assert_false(fog.intersects_world_aabb(AABB(Vector3(50.0, 50.0, 50.0), Vector3.ONE)))

	var depth_low: float = fog.get_segment_optical_depth(
		Vector3(-2.0, -1.5, 0.0), Vector3(2.0, -1.5, 0.0)
	)
	assert_gt(depth_low, 0.0)
	assert_eq(fog.get_segment_optical_depth(Vector3(50.0, 0.0, 0.0), Vector3(60.0, 0.0, 0.0)), 0.0)

	fog.visible = false
	assert_eq(fog.get_segment_optical_depth(Vector3(-2.0, -1.5, 0.0), Vector3(2.0, -1.5, 0.0)), 0.0)
	fog.visible = true

	fog.carve_bullet_ray(Vector3.ZERO, Vector3(2.0, 0.0, 0.0), 1.0)
	assert_eq(fog._live_ray_count, 1)
	fog.carve_explosion_sphere(Vector3(10.0, 0.0, 0.0), 2.0, 1.5)
	assert_eq(fog._live_ray_count, 2)


## Verifies [UnderwaterFogVolume] constants, defaults, and submersion edge fade switching.
func test_underwater_fog_volume_contracts() -> void:
	assert_eq(UnderwaterFogVolume.PARAM_DENSITY, &"density")
	assert_eq(UnderwaterFogVolume.PARAM_FADE_PLANE, &"fade_plane")
	assert_eq(UnderwaterFogVolume.GROUP_PLAYER, &"player")

	var fog_vol: UnderwaterFogVolume = UNDERWATER_FOG_SCRIPT.new() as UnderwaterFogVolume
	assert_not_null(fog_vol)
	var fmat: FogMaterial = FogMaterial.new()
	fog_vol.material = fmat
	add_child_autofree(fog_vol)

	assert_eq(fog_vol.base_density, 0.12)
	assert_eq(fog_vol.flashlight_density, 0.04)
	assert_eq(fog_vol.base_fade_dist, 3.0)
	assert_eq(fog_vol.flashlight_fade_dist, 6.0)
	assert_eq(fog_vol.transition_speed, 2.5)
	assert_eq(fog_vol.max_update_distance, 95.0)

	fog_vol.set_submerged(true)
	assert_almost_eq(fmat.edge_fade, 0.05, 0.001)
	fog_vol.set_submerged(false)
	assert_almost_eq(fmat.edge_fade, 0.2, 0.001)


## Verifies [AccessibleLabel] defaults and programmatic text updates.
func test_accessible_label_contracts() -> void:
	var label_body: AccessibleLabel = ACCESSIBLE_LABEL_SCENE.instantiate() as AccessibleLabel
	assert_not_null(label_body)
	add_child_autofree(label_body)

	assert_eq(label_body.billboard_mode, BaseMaterial3D.BILLBOARD_DISABLED)
	label_body.set_text("Elevator Access")
	assert_eq(label_body.display_text, "Elevator Access")
	var label_3d: Label3D = label_body._get_label_node()
	if is_instance_valid(label_3d):
		assert_eq(label_3d.text, "Elevator Access")


## Verifies [ArgonWaterBody] constants, flat wave height, unit normal, and ripple spawning.
func test_argon_water_body_contracts() -> void:
	assert_eq(ArgonWaterBody.MAX_RIPPLES, 16)
	assert_eq(ArgonWaterBody.RIPPLE_MAX_AGE, 4.0)
	assert_eq(ArgonWaterBody.MIN_WAKE_SPEED_SQ, 0.49)
	assert_eq(ArgonWaterBody.WAKE_COOLDOWN_SEC, 0.16)
	assert_eq(ArgonWaterBody.PARAM_WATER_TIME, &"water_time")
	assert_eq(ArgonWaterBody.PARAM_RIPPLES, &"ripples")

	var argon: ArgonWaterBody = ARGON_WATER_SCENE.instantiate() as ArgonWaterBody
	assert_not_null(argon)
	add_child_autofree(argon)
	assert_has_signal(argon, &"splashed")

	argon.water_size = Vector3(12.0, 4.0, 12.0)
	argon.wave_amplitude = 0.0
	assert_almost_eq(argon.get_wave_height_at_pos(Vector3.ZERO), 2.0, 0.001)
	var normal: Vector3 = argon.get_water_surface_normal(Vector3.ZERO)
	assert_almost_eq(normal.length(), 1.0, 0.001)
	assert_almost_eq(normal.y, 1.0, 0.001)

	argon.spawn_ripple(Vector3(1.0, 2.0, 1.0), 0.4)
	assert_gt(argon._active_ripple_count, 0)


## Verifies [BasaltGenerator] constants, defaults, and safe float conversion helper.
func test_basalt_generator_contracts() -> void:
	assert_eq(BasaltGenerator.MULTI_MESH_NAME, &"BasaltMultiMesh")
	assert_eq(BasaltGenerator.STATIC_BODY_NAME, &"BasaltStaticBody")
	assert_eq(BasaltGenerator.COLLISION_SHAPE_NAME, &"BasaltCollisionShape")
	assert_almost_eq(BasaltGenerator._to_safe_float(5), 5.0, 0.001)
	assert_almost_eq(BasaltGenerator._to_safe_float(3.25), 3.25, 0.001)
	assert_almost_eq(BasaltGenerator._to_safe_float("invalid"), 0.0, 0.001)

	var gen: BasaltGenerator = BASALT_GENERATOR_SCENE.instantiate() as BasaltGenerator
	assert_not_null(gen)
	add_child_autofree(gen)
	assert_eq(gen.field_width, 20.0)
	assert_eq(gen.field_depth, 20.0)
	assert_eq(gen.amount, 100)
	assert_eq(gen.sides, 6)
	assert_eq(gen.surface_group, "stone")


## Verifies [CitadelCore] default exports and timing updates.
func test_citadel_core_contracts() -> void:
	var core: CitadelCore = CITADEL_CORE_SCENE.instantiate() as CitadelCore
	assert_not_null(core)
	add_child_autofree(core)

	assert_eq(core.transition_time, 1.0)
	assert_eq(core.pause_time, 2.0)
	assert_eq(core.wave_duration_offset, 0.1)

	core.update_core_timing(2.5, 4.0)
	assert_eq(core.transition_time, 2.5)
	assert_eq(core.pause_time, 4.0)


## Verifies [CrabShell] initial hidden state and drop trigger activation.
func test_crab_shell_contracts() -> void:
	var shell: CrabShell = CRAB_SHELL_SCENE.instantiate() as CrabShell
	assert_not_null(shell)
	shell.drop_delay = 0.0
	add_child_autofree(shell)

	assert_eq(shell.drop_distance, 100.0)
	assert_eq(shell.travel_time, 4.0)
	assert_eq(shell.arc_height, 20.0)
	assert_true(shell.smoke_after_impact)
	assert_false(shell.visible)
	assert_false(shell.is_physics_processing())

	shell.trigger_drop()
	assert_true(shell._has_triggered)
	assert_true(shell.visible)
	assert_true(shell.is_physics_processing())


## Verifies [DustVolume] layer constant, rebuild, and freeze signal/speed scaling.
func test_dust_volume_contracts() -> void:
	assert_eq(DustVolume.LAYER_VOLUMETRICS, CollisionLayers.RENDER_MASK_VOLUMETRICS)

	var dust: DustVolume = DUST_VOLUME_SCENE.instantiate() as DustVolume
	assert_not_null(dust)
	add_child_autofree(dust)
	assert_has_signal(dust, &"frozen_changed")

	watch_signals(dust)
	dust.set_frozen(true)
	assert_true(dust.frozen)
	assert_eq(dust.speed_scale, 0.0)
	assert_signal_emitted_with_parameters(dust, &"frozen_changed", [true])

	dust.set_frozen(false)
	assert_false(dust.frozen)
	assert_eq(dust.speed_scale, 1.0)
	assert_signal_emitted_with_parameters(dust, &"frozen_changed", [false])

	dust.rebuild_volume()


## Verifies [ElectrifiedFloor] defaults, body tracking, and HealthComponent damage ticks.
func test_electrified_floor_contracts() -> void:
	var floor_node: ElectrifiedFloor = ELECTRIFIED_FLOOR_SCENE.instantiate() as ElectrifiedFloor
	assert_not_null(floor_node)
	add_child_autofree(floor_node)

	assert_eq(floor_node.floor_size, 2.0)
	assert_eq(floor_node.damage_per_tick, 100)
	assert_eq(floor_node.tick_rate, 0.5)

	floor_node._on_body_entered(floor_node)
	assert_eq(floor_node._overlapping_bodies.size(), 0)

	var victim: CharacterBody3D = CharacterBody3D.new()
	victim.name = "TestVictim"
	var hp: HealthComponent = HealthComponent.new()
	hp.max_health = 100.0
	victim.add_child(hp)
	add_child_autofree(victim)

	floor_node._on_body_entered(victim)
	assert_true(floor_node._overlapping_bodies.has(victim))
	floor_node._try_damage_body(victim)
	assert_lt(hp.current_health, 100)
	floor_node._on_body_exited(victim)
	assert_false(floor_node._overlapping_bodies.has(victim))


## Verifies [FlagController] parameter setters and mesh scaling.
func test_flag_controller_contracts() -> void:
	var flag: FlagController = FLAG_WAVING_SCENE.instantiate() as FlagController
	assert_not_null(flag)
	add_child_autofree(flag)

	flag.set_flag_size(Vector2(2.0, 1.5))
	assert_eq(flag.flag_size, Vector2(2.0, 1.5))
	if is_instance_valid(flag.front_mesh):
		assert_eq(flag.front_mesh.scale, Vector3(2.0, 1.5, 1.0))

	flag.set_wind_direction(Vector3(1.0, 0.0, 0.0))
	assert_eq(flag.wind_direction, Vector3(1.0, 0.0, 0.0))
	flag.set_wind_intensity(2.2)
	assert_eq(flag.wind_intensity, 2.2)
	flag.set_noise_strength(0.5)
	assert_eq(flag.noise_strength, 0.5)
	flag.set_wave_speed(4.0)
	assert_eq(flag.wave_speed, 4.0)
	flag.set_wave_amplitude(0.3)
	assert_eq(flag.wave_amplitude, 0.3)
	flag.set_wave_frequency(5.0)
	assert_eq(flag.wave_frequency, 5.0)
	flag.set_wave_phases(3.0)
	assert_eq(flag.wave_phases, 3.0)
	flag.set_roughness(0.4)
	assert_eq(flag.roughness, 0.4)


## Verifies [GothicEnergyGate] signals, constants, power hooks, and progress blending.
func test_gothic_energy_gate_contracts() -> void:
	assert_eq(GothicEnergyGate.SHADER_PATH, "res://vfx/gothic_energy_gate.gdshader")
	assert_eq(GothicEnergyGate.META_PART, &"generated_gate_part")
	assert_eq(GothicEnergyGate.EMITTER_RATIOS.size(), 3)
	assert_eq(GothicEnergyGate.PLAYER_LAYER_MASK, CollisionLayers.MASK_PLAYER)

	var gate: GothicEnergyGate = GOTHIC_GATE_SCENE.instantiate() as GothicEnergyGate
	assert_not_null(gate)
	add_child_autofree(gate)
	assert_has_signal(gate, &"gate_open_state_changed")
	assert_has_signal(gate, &"field_power_changed")
	assert_has_signal(gate, &"body_entered_field")

	watch_signals(gate)
	gate.set_gate_open(true)
	assert_true(gate.is_gate_open)
	assert_signal_emitted_with_parameters(gate, &"gate_open_state_changed", [true])

	gate.toggle_gate()
	assert_false(gate.is_gate_open)
	assert_signal_emitted_with_parameters(gate, &"gate_open_state_changed", [false])

	gate.set_field_powered(false)
	assert_false(gate.is_field_powered)
	assert_signal_emitted_with_parameters(gate, &"field_power_changed", [false])

	gate.set_progress(0.75)
	assert_true(gate.is_gate_open)
	gate.set_progress(0.25)
	assert_false(gate.is_gate_open)

	gate.power_on()
	assert_true(gate.is_gate_open)
	gate.power_off()
	assert_false(gate.is_gate_open)


## Verifies [HighlightComponent] constants, suppression state, and lifecycle cleanup.
func test_highlight_component_contracts() -> void:
	assert_gt(HighlightComponent.OUTLINE_COLOR_VALUES.size(), 0)
	assert_eq(HighlightComponent.DEFAULT_OUTLINE_INTERVAL, 10.0)
	assert_eq(HighlightComponent.DEFAULT_OUTLINE_DURATION, 3.0)
	assert_not_null(HighlightComponent.DEFAULT_OUTLINE_MATERIAL)

	var host: Node3D = Node3D.new()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	host.add_child(mesh)

	var hl: HighlightComponent = HIGHLIGHT_COMPONENT_SCRIPT.new() as HighlightComponent
	assert_not_null(hl)
	hl.target_meshes.append(mesh)
	host.add_child(hl)
	add_child_autofree(host)

	hl.suppress(true)
	assert_true(hl._is_suppressed)
	hl.suppress(false)
	assert_false(hl._is_suppressed)


## Verifies lightning orb constants and [signal lightning_struck] emission.
func test_lightning_orb_contracts() -> void:
	var orb: Node3D = LIGHTNING_ORB_SCENE.instantiate() as Node3D
	assert_not_null(orb)
	add_child_autofree(orb)
	assert_has_signal(orb, &"lightning_struck")
	assert_eq(orb.get("ENVIRONMENT_COLLISION_MASK"), 29)
	assert_eq(orb.get("RENDER_LAYER_INTERACTIVE"), 4)
	assert_eq(orb.get("RENDER_LAYER_VOLUMETRICS"), 512)
	assert_eq(orb.get("LIGHT_CULL_MASK_COMBINED"), 517)

	watch_signals(orb)
	var hit_pos: Vector3 = Vector3(1.0, 2.0, 3.0)
	orb.call(&"trigger_strike", hit_pos, Vector3.UP)
	assert_signal_emitted_with_parameters(orb, &"lightning_struck", [hit_pos, Vector3.UP])


## Verifies rain controller defaults, signal, and weather transition activation.
func test_rain_controller_contracts() -> void:
	var rain: Node3D = RAIN_CONTROLLER_SCENE.instantiate() as Node3D
	assert_not_null(rain)
	add_child_autofree(rain)
	assert_has_signal(rain, &"weather_transition_completed")

	assert_eq(rain.get("enabled"), true)
	assert_eq(rain.get("intensity"), 1.0)
	assert_almost_eq(float(rain.get("swirl")), 0.51, 0.001)
	assert_eq(rain.get("volume_size"), Vector3(30.0, 20.0, 30.0))
	assert_eq(rain.get("max_particles"), 25088)
	assert_eq(rain.get("follow_camera"), true)

	rain.set("enabled", false)
	rain.call(&"set_weather", 0.6, 0.8, 0.1)
	assert_eq(rain.get("enabled"), true)


## Verifies [SnowGround] constants, signal, and out-of-bounds deformation guard.
func test_snow_ground_contracts() -> void:
	assert_eq(SnowGround.PARAM_DISPLACEMENT, &"displacement_texture")
	assert_eq(SnowGround.PARAM_DIMENSIONS, &"ground_dimensions")
	assert_eq(SnowGround.PARAM_NOISE, &"base_height_noise")
	assert_eq(SnowGround.PARAM_HEIGHT_SCALE, &"terrain_height_scale")
	assert_eq(SnowGround.HEIGHTMAP_RES, 64)

	var snow: SnowGround = SNOW_GROUND_SCRIPT.new() as SnowGround
	assert_not_null(snow)
	var vp: SubViewport = SubViewport.new()
	vp.name = "DeformViewport"
	var painter: SnowPainter = SnowPainter.new()
	painter.name = "SnowPainter"
	painter.footprint_texture = PlaceholderTexture2D.new()
	vp.add_child(painter)
	snow.add_child(vp)
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = "StaticBody3D"
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	sb.add_child(col)
	snow.add_child(sb)
	add_child_autofree(snow)
	assert_has_signal(snow, &"deformed")
	assert_eq(snow.plane_size, Vector2(20.0, 20.0))

	watch_signals(snow)
	snow.deform_at(Vector3(100.0, 0.0, 100.0))
	assert_signal_not_emitted(snow, &"deformed")


## Verifies [SupplyShell] constants, initial state, and drop trigger activation.
func test_supply_shell_contracts() -> void:
	assert_not_null(SupplyShell.DEFAULT_AMMO_BOX_SCENE)

	var supply: SupplyShell = SUPPLY_SHELL_SCENE.instantiate() as SupplyShell
	assert_not_null(supply)
	supply.drop_delay = 0.0
	add_child_autofree(supply)

	assert_eq(supply.approach_distance, 70.0)
	assert_eq(supply.drop_height, 24.0)
	assert_eq(supply.travel_time, 7.5)
	assert_eq(supply.ammo_spawn_count, 2)
	assert_false(supply.visible)
	assert_false(supply.is_physics_processing())

	supply.trigger_drop()
	assert_true(supply._has_triggered)
	assert_true(supply.visible)
	assert_true(supply.is_physics_processing())


## Verifies [WaterBody] enums, wave height/normal math, ripples, and level transitions.
func test_water_body_contracts() -> void:
	assert_eq(WaterBody.WaterLevelMode.TOGGLE, 0)
	assert_eq(WaterBody.WaterLevelMode.ONE_SHOT, 1)
	assert_eq(WaterBody.MAX_RIPPLES, 16)

	var water: WaterBody = WATER_BODY_SCENE.instantiate() as WaterBody
	assert_not_null(water)
	add_child_autofree(water)
	assert_has_signal(water, &"splashed")
	assert_has_signal(water, &"water_level_transition_started")
	assert_has_signal(water, &"water_level_transition_finished")

	water.water_size = Vector3(10.0, 4.0, 10.0)
	water.wave_amplitude = 0.0
	assert_almost_eq(water.get_wave_height_at_pos(Vector3.ZERO), 2.0, 0.001)
	var normal: Vector3 = water.get_water_surface_normal(Vector3.ZERO)
	assert_almost_eq(normal.length(), 1.0, 0.001)
	assert_almost_eq(normal.y, 1.0, 0.001)

	water.spawn_ripple(Vector3(1.0, 2.0, 1.0), 1.0)
	assert_true(water._has_active_ripples)

	watch_signals(water)
	water.level_change_duration = 0.1
	water.power_on()
	assert_signal_emitted_with_parameters(water, &"water_level_transition_started", [true])
	assert_false(water.is_level_transition_complete())


## Verifies [Waypoint3D] defaults, signal, debug toggle, and arrival radius checks.
func test_waypoint_3d_contracts() -> void:
	var wp: Waypoint3D = WAYPOINT_3D_SCENE.instantiate() as Waypoint3D
	assert_not_null(wp)
	add_child_autofree(wp)
	assert_has_signal(wp, &"reached")

	assert_eq(wp.arrival_radius, 1.0)
	assert_eq(wp.wait_time, 0.0)
	assert_eq(wp.speed_modifier, 1.0)
	assert_true(wp.monitor_player)
	assert_eq(wp.trigger_text, "WAYPOINT")

	wp.global_position = Vector3.ZERO
	wp.arrival_radius = 2.0
	assert_true(wp.is_reached(Vector3(1.0, 0.0, 0.0)))
	assert_false(wp.is_reached(Vector3(5.0, 0.0, 0.0)))
	assert_false(wp.is_reached(null))

	var actor: Node3D = Node3D.new()
	add_child_autofree(actor)
	actor.global_position = Vector3(0.5, 0.0, 0.0)
	watch_signals(wp)
	assert_true(wp.is_reached(actor))
	assert_signal_emitted_with_parameters(wp, &"reached", [actor])

	wp.set_debug_visibility(true)
	wp.set_debug_visibility(false)


## Verifies [GameWorldEnvironment] fullbright toggle behavior on [Environment].
func test_world_environment_contracts() -> void:
	var world_env: GameWorldEnvironment = WORLD_ENV_SCRIPT.new() as GameWorldEnvironment
	assert_not_null(world_env)
	var env: Environment = Environment.new()
	world_env.environment = env
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	world_env.add_child(sun)
	add_child_autofree(world_env)

	world_env._on_fullbright_toggled(true)
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_eq(env.background_mode, Environment.BG_COLOR)
	assert_false(env.ssao_enabled)
	assert_false(sun.visible)

	world_env._on_fullbright_toggled(false)
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_SKY)
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_true(env.ssao_enabled)
	assert_true(sun.visible)
