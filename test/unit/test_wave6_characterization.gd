## Characterization tests locking Wave 6 public APIs, constants, signals, and behavior.
class_name TestWave6Characterization
extends GutTest

const ENERGY_WALL_SCRIPT: GDScript = preload("res://vfx/energy_wall.gd")
const COLOR_GRADING_SCENE: PackedScene = preload("res://vfx/color_grading_volume.tscn")
const EXPLOSION_CRYSIS_SCENE: PackedScene = preload("res://scenes/vfx/explosion_crysis.tscn")
const FIRE_JET_SCENE: PackedScene = preload(
	"res://vfx/pressurized_fire_jet/pressurized_fire_jet.tscn"
)
const GEL_EMITTER_SCENE: PackedScene = preload("res://vfx/gel_emitter.tscn")
const HYDROGEN_WATER_SCENE: PackedScene = preload(
	"res://environment/hydrogen_water_body/hydrogen_water_body.tscn"
)
const PARTICLE_SCENE: PackedScene = preload("res://vfx/particle.tscn")
const PHYS_EXPLOSION_SCENE: PackedScene = preload("res://vfx/phys_explosion_3d.tscn")
const SCREENSHAKE_SCENE: PackedScene = preload("res://vfx/screenshake_effect.tscn")
const SMOKE_EXPLOSION_SCENE: PackedScene = preload("res://vfx/smoke_explosion.tscn")


class _MockWaterSurface:
	extends Node3D

	var base_height: float = 2.0
	var slope_x: float = 0.0

	func get_height(pos: Vector3) -> float:
		return base_height + pos.x * slope_x


## Verifies [Ocean] enums, constants, cascade reset, and Gerstner height fallback.
func test_ocean_contracts() -> void:
	assert_eq(Ocean.MeshQuality.LOW, 0)
	assert_eq(Ocean.MeshQuality.HIGH, 1)
	assert_eq(Ocean.MeshQuality.HIGH8K, 2)
	assert_eq(Ocean.WaveMapResolution.RES_128, 128)
	assert_eq(Ocean.WaveMapResolution.RES_1024, 1024)
	assert_eq(Ocean.PARAM_WATER_COLOR, &"water_color")
	assert_eq(Ocean.DESC_DOWNSAMPLED, &"downsampled_map")

	var ocean: Ocean = Ocean.new()
	add_child_autofree(ocean)

	assert_eq(ocean.max_sim_distance, 150.0)
	assert_eq(ocean.distant_sim_fps, 35.0)
	assert_eq(ocean.ocean_plane_size, 300.0)
	assert_eq(ocean.spray_spawn_radius, 150.0)

	ocean.mesh_quality = Ocean.MeshQuality.LOW
	assert_eq(ocean.mesh, Ocean.WATER_MESH_LOW)
	ocean.mesh_quality = Ocean.MeshQuality.HIGH
	assert_eq(ocean.mesh, Ocean.WATER_MESH_HIGH)

	var cascade: WaveCascadeParameters = WaveCascadeParameters.new()
	cascade.displacement_scale = 2.0
	cascade.tile_length = Vector2(10.0, 10.0)
	ocean.parameters.append(cascade)

	var h: float = ocean.get_height(Vector3(1.5, 0.0, -2.5))
	assert_true(is_finite(h))

	ocean.force_reset_cascades()
	assert_eq(cascade.tile_length, Vector2(256.0, 256.0))
	assert_eq(cascade.displacement_scale, 1.0)
	assert_eq(cascade.wind_speed, 15.0)


## Verifies [WaveHeightController] water validation, buoyancy damping, and null guard.
func test_wave_height_controller_contracts() -> void:
	var mock_water: _MockWaterSurface = _MockWaterSurface.new()
	mock_water.base_height = 4.0
	mock_water.slope_x = 0.2
	add_child_autofree(mock_water)

	var floater: WaveHeightController = WaveHeightController.new()
	floater.water = mock_water
	floater.float_offset = -0.5
	floater.probe_spacing = 1.5
	floater.responsiveness = 10.0
	add_child_autofree(floater)
	floater.global_position = Vector3.ZERO

	assert_true(floater._is_water_valid)
	floater._process(0.1)
	assert_gt(floater.global_position.y, 0.0)
	assert_true(is_finite(floater.global_position.y))
	assert_true(floater.global_transform.basis.is_finite())

	var unlinked: WaveHeightController = WaveHeightController.new()
	add_child_autofree(unlinked)
	assert_false(unlinked._is_water_valid)
	unlinked._process(0.1)
	assert_eq(unlinked.global_position, Vector3.ZERO)


## Verifies [HydrogenWaterBody] wave height, normals, ripples, level tweening, and legacy props.
func test_hydrogen_water_body_contracts() -> void:
	assert_eq(HydrogenWaterBody.WaterLevelMode.TOGGLE, 0)
	assert_eq(HydrogenWaterBody.WaterLevelMode.ONE_SHOT, 1)
	assert_eq(HydrogenWaterBody.ProbeUpdateMode.ONCE, 0)
	assert_eq(HydrogenWaterBody.ProbeUpdateMode.ALWAYS, 1)
	assert_eq(HydrogenWaterBody.MAX_RIPPLES, 16)
	assert_eq(HydrogenWaterBody.RIPPLE_LIFETIME, 4.5)
	assert_eq(HydrogenWaterBody.MACRO_DIRS.size(), 8)

	var water: HydrogenWaterBody = HYDROGEN_WATER_SCENE.instantiate() as HydrogenWaterBody
	assert_not_null(water)
	add_child_autofree(water)
	water.water_size = Vector3(10.0, 4.0, 10.0)
	water.wave_amplitude = 0.0
	water.ripple_mesh_height = 0.5
	water.level_change_duration = 0.2

	assert_almost_eq(water.get_wave_height_at_pos(Vector3.ZERO), 2.0, 0.001)
	var normal: Vector3 = water.get_water_surface_normal(Vector3.ZERO)
	assert_almost_eq(normal.length(), 1.0, 0.001)
	assert_almost_eq(normal.y, 1.0, 0.001)

	water.spawn_ripple(Vector3(1.0, 2.0, 1.0), 5.0)
	assert_false(water._ripples_cleared)
	assert_eq(water._ripple_cursor, 1)
	assert_almost_eq(water._ripples[0].w, 2.5, 0.001)

	water.set(&"size", Vector3(12.0, 4.0, 12.0))
	var legacy_size: Variant = water.get(&"size")
	assert_eq(legacy_size, Vector3(12.0, 4.0, 12.0))
	assert_false(water.should_draw_camera_underwater_effect())

	watch_signals(water)
	assert_true(water.is_level_transition_complete())
	water.water_level_mode = HydrogenWaterBody.WaterLevelMode.ONE_SHOT
	water.power_on()
	assert_signal_emitted_with_parameters(water, "water_level_transition_started", [true])
	assert_false(water.is_level_transition_complete())

	water.power_off()
	assert_signal_emit_count(water, "water_level_transition_started", 1)
	water.toggle_water_level()
	assert_signal_emit_count(water, "water_level_transition_started", 1)


## Verifies [ExplosionCrysis] constants, signals, detonation, and reset contracts.
func test_explosion_crysis_contracts() -> void:
	assert_eq(ExplosionCrysis.PARAM_PROGRESS, &"explosion_progress")
	assert_eq(ExplosionCrysis.PARAM_DISTORTION, &"distortion_strength")
	assert_eq(ExplosionCrysis.FLASH_PEAK_ENERGY, 16.0)
	assert_eq(ExplosionCrysis.MAX_PARTICLE_LIFETIME, 3.5)

	var exp_node: ExplosionCrysis = EXPLOSION_CRYSIS_SCENE.instantiate() as ExplosionCrysis
	assert_not_null(exp_node)
	exp_node.auto_play = false
	exp_node.free_on_finish = false
	add_child_autofree(exp_node)
	watch_signals(exp_node)

	exp_node.explode()
	assert_signal_emitted_with_parameters(
		exp_node, "detonation_started", [exp_node.global_position]
	)
	assert_true(exp_node.detonation_flash.visible)
	assert_eq(exp_node.detonation_flash.light_energy, ExplosionCrysis.FLASH_PEAK_ENERGY)
	assert_true(exp_node.heat_distortion.visible)

	exp_node.reset()
	assert_false(exp_node.detonation_flash.visible)
	assert_eq(exp_node.detonation_flash.light_energy, 0.0)
	assert_false(exp_node.heat_distortion.visible)

	exp_node.detonate()
	assert_signal_emit_count(exp_node, "detonation_started", 2)


## Verifies [SmokeExplosionVfx] constants, blast masks, detonation, and completion signal.
func test_smoke_explosion_vfx_contracts() -> void:
	assert_eq(SmokeExplosionVfx.BLAST_RADIUS, 6.0)
	assert_eq(SmokeExplosionVfx.BLAST_RADIUS_SQ, 36.0)
	assert_eq(SmokeExplosionVfx.BLAST_PEAK_IMPULSE, 18.0)
	assert_eq(SmokeExplosionVfx.WALL_MARGIN, 0.45)
	assert_eq(
		SmokeExplosionVfx.PHYSICS_MASK_BLAST,
		(
			CollisionLayers.MASK_INTERACTIVE
			| CollisionLayers.MASK_DEBRIS
			| CollisionLayers.MASK_ENEMIES
		)
	)

	var smoke: SmokeExplosionVfx = SMOKE_EXPLOSION_SCENE.instantiate() as SmokeExplosionVfx
	assert_not_null(smoke)
	smoke.auto_play = false
	smoke.free_on_finish = false
	add_child_autofree(smoke)
	watch_signals(smoke)

	var target_pos: Vector3 = Vector3(2.0, 0.0, -3.0)
	smoke.detonate(target_pos)
	assert_eq(smoke.global_position, target_pos)
	assert_eq(smoke._flash_light.light_energy, SmokeExplosionVfx.FLASH_PEAK_ENERGY)

	smoke._on_plume_finished()
	assert_signal_emitted_with_parameters(smoke, "detonation_completed", [target_pos])


## Verifies [ColorGradingVolume3D] presets, collision masks, and reset_to_default().
func test_color_grading_volume_contracts() -> void:
	var vol: ColorGradingVolume3D = COLOR_GRADING_SCENE.instantiate() as ColorGradingVolume3D
	assert_not_null(vol)
	vol.blend_time = 0.05
	add_child_autofree(vol)

	assert_true(vol.is_in_group(&"color_grading_volumes"))
	assert_eq(vol.collision_layer, CollisionLayers.MASK_NONE)
	assert_eq(vol.collision_mask, CollisionLayers.MASK_PLAYER)

	vol.preset = ColorGradingVolume3D.Preset.BLACK_AND_WHITE
	assert_eq(vol.contrast, 1.2)
	assert_eq(vol.saturation, 0.0)

	vol.preset = ColorGradingVolume3D.Preset.WARM
	assert_eq(vol.temperature, 0.6)

	var player: Node3D = Node3D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	vol._on_body_entered(player)
	vol._on_body_exited(player)

	vol.reset_to_default()
	assert_false(vol._canvas_layer.visible)
	assert_false(vol._color_rect.visible)


## Verifies [DustPuff] auto-frees on finished signal connection.
func test_dust_puff_contracts() -> void:
	var dust: DustPuff = DustPuff.new()
	add_child_autofree(dust)
	assert_true(dust.finished.is_connected(dust.queue_free))


## Verifies [LightningController] constants, markers, and immediate mesh strike generation.
func test_argon_lightning_controller_contracts() -> void:
	assert_eq(LightningController.PARAM_ENERGY, &"energy_multiplier")
	assert_eq(LightningController.PARAM_SEED, &"strike_seed")
	assert_eq(LightningController.PARAM_COLOR, &"bolt_color")

	var ctrl: LightningController = LightningController.new()
	ctrl.auto_strike = false
	var start_marker: Marker3D = Marker3D.new()
	start_marker.name = "Start"
	start_marker.position = Vector3(0.0, 20.0, 0.0)
	var end_marker: Marker3D = Marker3D.new()
	end_marker.name = "End"
	end_marker.position = Vector3(0.0, 0.0, 0.0)
	ctrl.add_child(start_marker)
	ctrl.add_child(end_marker)
	ctrl.start_markers = [NodePath("Start")]
	ctrl.end_markers = [NodePath("End")]
	add_child_autofree(ctrl)

	assert_eq(ctrl.peak_energy, 14.0)
	assert_eq(ctrl.segment_count, 22)
	assert_eq(ctrl.speed_of_sound, 343.0)

	ctrl.strike_between_markers(-1, 0)
	ctrl.strike_between_markers(0, 99)
	assert_eq(ctrl._imm_mesh.get_surface_count(), 0)

	ctrl.strike_between_markers(0, 0)
	assert_gt(ctrl._imm_mesh.get_surface_count(), 0)
	assert_eq(ctrl._impact_light.light_energy, 30.0)


## Verifies [EnergyWall] 4-slot ring buffer, hit/damage entry points, and render layer.
func test_energy_wall_contracts() -> void:
	assert_eq(ENERGY_WALL_SCRIPT.SLOT_COUNT, 4)
	assert_eq(ENERGY_WALL_SCRIPT.INACTIVE_SLOT, Vector4(0.0, 0.0, 0.0, 1.0))
	assert_eq(ENERGY_WALL_SCRIPT.PARAM_HIT_SLOT_0, &"hit_slot_0")

	var wall: MeshInstance3D = ENERGY_WALL_SCRIPT.new() as MeshInstance3D
	assert_not_null(wall)
	wall.mesh = BoxMesh.new()
	add_child_autofree(wall)

	assert_eq(wall.layers, CollisionLayers.RENDER_MASK_ENVIRONMENT)
	assert_eq(wall.get(&"_next_slot"), 0)

	wall.call(&"trigger_hit", Vector3(1.0, 2.0, 3.0))
	assert_eq(wall.get(&"_next_slot"), 1)
	var buf: Projection = wall.get(&"_hit_buffer") as Projection
	assert_eq(Vector3(buf.x.x, buf.x.y, buf.x.z), Vector3(1.0, 2.0, 3.0))

	wall.call(&"take_damage", 25, Vector3(4.0, 5.0, 6.0), Vector3.FORWARD)
	assert_eq(wall.get(&"_next_slot"), 2)

	wall.call(&"trigger_hit", Vector3.ZERO)
	wall.call(&"trigger_hit", Vector3.ZERO)
	assert_eq(wall.get(&"_next_slot"), 0)

	wall.call(&"trigger_rapid_burst")


## Verifies [GelEmitter] pool initialization, data textures, and decal splat bounds.
func test_gel_emitter_contracts() -> void:
	assert_eq(GelEmitter.MAX_PARTICLES, 50)
	assert_eq(GelEmitter.DATA_TEXTURE_WIDTH, 64)

	var gel: GelEmitter = GEL_EMITTER_SCENE.instantiate() as GelEmitter
	assert_not_null(gel)
	add_child_autofree(gel)

	await get_tree().process_frame
	assert_eq(gel.particle_pool.size(), GelEmitter.MAX_PARTICLES)
	assert_eq(gel.data_texture.get_width(), GelEmitter.DATA_TEXTURE_WIDTH)
	assert_eq(gel.splat_pos.get_width(), 1024)

	gel.spawn_decal(Vector3(1.0, 2.0, 3.0))
	assert_eq(gel.splat_count, 1)
	assert_true(gel._splat_dirty)

	gel.splat_count = 1024
	gel.spawn_decal(Vector3.ZERO)
	assert_eq(gel.splat_count, 1024)


## Verifies [Particle] fall simulation, reset, deactivation, and shader parameter helpers.
func test_particle_contracts() -> void:
	assert_eq(Particle.GRACE_PERIOD, 0.05)

	var particle: Particle = PARTICLE_SCENE.instantiate() as Particle
	assert_not_null(particle)
	add_child_autofree(particle)

	assert_true(particle.top_level)
	assert_false(particle.is_active)

	particle.global_position = Vector3(0.0, 10.0, 0.0)
	particle.reset_particle()
	assert_true(particle.is_active)
	assert_true(particle.visible)
	assert_true(particle.is_processing())

	particle._process(0.1)
	assert_lt(particle.global_position.y, 10.0)

	particle.update_n_particles(5)
	particle.update_shader_params(Color.RED, 0.8, 0.2, 0.5, 0.3)

	particle.deactivate()
	assert_false(particle.is_active)
	assert_false(particle.visible)
	assert_false(particle.is_processing())
	assert_eq(particle.global_position, Vector3(0.0, -1000.0, 0.0))


## Verifies [PhysExplosion3D] collision setup, blast sphere sizing, and detonation.
func test_phys_explosion_3d_contracts() -> void:
	var phys: PhysExplosion3D = PHYS_EXPLOSION_SCENE.instantiate() as PhysExplosion3D
	assert_not_null(phys)
	phys.explosion_radius = 7.5
	add_child_autofree(phys)

	assert_eq(phys.explosion_force, 50.0)
	assert_eq(phys.self_kick_multiplier, 0.5)
	assert_eq(phys.blast_area.collision_layer, CollisionLayers.MASK_NONE)
	assert_eq(
		phys.blast_area.collision_mask,
		(
			CollisionLayers.MASK_DEBRIS
			| CollisionLayers.MASK_ENEMIES
			| CollisionLayers.MASK_PLAYER
			| CollisionLayers.MASK_INTERACTIVE
		)
	)
	var sphere: SphereShape3D = phys.blast_shape.shape as SphereShape3D
	assert_not_null(sphere)
	assert_eq(sphere.radius, 7.5)

	assert_true(phys._fuse_timer >= phys.min_fuse_time and phys._fuse_timer <= phys.max_fuse_time)
	phys._detonate()
	assert_true(phys.burst_sparks.emitting)
	phys._physics_process(phys.max_fuse_time + 0.1)
	assert_true(phys._fuse_timer >= phys.min_fuse_time and phys._fuse_timer <= phys.max_fuse_time)


## Verifies [PressurizedFireJet] pressure scaling, layer setup, cycle toggle, and hazard damage.
func test_pressurized_fire_jet_contracts() -> void:
	assert_eq(PressurizedFireJet.CUTOFF_PRESSURE, 0.01)
	assert_eq(PressurizedFireJet.MAX_LIGHT_ENERGY, 3.5)

	var jet: PressurizedFireJet = FIRE_JET_SCENE.instantiate() as PressurizedFireJet
	assert_not_null(jet)
	jet.cycle_enabled = false
	jet.damage_amount = 200
	jet.jet_length = 6.0
	add_child_autofree(jet)

	assert_eq(jet.jet_mesh.layers, CollisionLayers.RENDER_MASK_VOLUMETRICS)
	assert_eq(jet.hazard_area.collision_mask, CollisionLayers.MASK_PLAYER)

	jet.set_pressure(0.0, 0.0)
	assert_false(jet.jet_mesh.visible)
	assert_false(jet.jet_light.visible)
	assert_eq(jet.jet_light.light_energy, 0.0)

	jet.set_pressure(1.0, 0.0)
	assert_eq(jet.jet_light.light_energy, PressurizedFireJet.MAX_LIGHT_ENERGY)

	var actor: Node3D = Node3D.new()
	var hc: HealthComponent = HealthComponent.new()
	hc.max_health = 500
	actor.add_child(hc)
	actor.position = Vector3(0.0, 0.0, -2.0)
	add_child_autofree(actor)

	jet._on_hazard_body_entered(actor)
	assert_eq(hc.current_health, 300)
	jet._on_hazard_body_exited(actor)
	assert_false(jet._overlapping_targets.has(actor))

	jet.start_cycle()
	assert_true(jet.cycle_enabled)
	jet.stop_cycle()
	assert_false(jet.cycle_enabled)


## Verifies [ScreenshakeEffect] player-only filtering, trauma normalization, and trigger_once.
func test_screenshake_effect_contracts() -> void:
	var shake: ScreenshakeEffect = SCREENSHAKE_SCENE.instantiate() as ScreenshakeEffect
	assert_not_null(shake)
	shake.trigger_once = true
	shake.shake_intensity = 4.0
	shake.shake_duration = 2.5
	add_child_autofree(shake)

	assert_eq(shake.collision_layer, CollisionLayers.MASK_NONE)
	assert_eq(shake.collision_mask, CollisionLayers.MASK_PLAYER)

	watch_signals(Events)
	var non_player: Node3D = Node3D.new()
	add_child_autofree(non_player)
	shake._on_body_entered(non_player)
	assert_signal_not_emitted(Events, "screenshake_requested")

	var player: Node3D = Node3D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	shake._on_body_entered(player)
	assert_signal_emitted_with_parameters(Events, "screenshake_requested", [0.25, 2.5])

	shake._on_body_entered(player)
	assert_signal_emit_count(Events, "screenshake_requested", 1)

	shake.trigger_once = false
	shake._on_body_entered(player)
	assert_signal_emit_count(Events, "screenshake_requested", 2)
