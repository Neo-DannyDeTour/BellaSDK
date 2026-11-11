## Complete GUT unit test suite validating the ExplosionCrysis multi-emitter VFX hierarchy.
## Covers Tiers 1-4 per TEST_INFRA.md: scene loading, hierarchy, properties, triggers, and safety.
class_name TestExplosionCrysis
extends GutTest

## Path to the target composite explosion scene.
const SCENE_PATH: String = "res://scenes/vfx/explosion_crysis.tscn"

## Path to the generated 8x8 flipbook spritesheet texture.
const FLIPBOOK_TEXTURE_PATH: String = "res://assets/vfx/explosion/explosion_core_8x8.png"

## Path to the existing shockwave refraction spatial shader.
const SHOCKWAVE_SHADER_PATH: String = "res://vfx/explosion_shockwave.gdshader"


## Helper loading the explosion packed scene resource.
func _load_explosion_scene() -> PackedScene:
	return load(SCENE_PATH) as PackedScene


## Helper creating an explosion instance with configured lifecycle and auto-play flags.
func _instantiate_explosion(auto_play_flag: bool = false, free_flag: bool = false) -> Node3D:
	var packed_scene: PackedScene = _load_explosion_scene()
	if packed_scene == null:
		return null
	var inst: Node3D = packed_scene.instantiate() as Node3D
	if inst != null:
		inst.set(&"auto_play", auto_play_flag)
		inst.set(&"free_on_finish", free_flag)
	return inst


## Helper invoking explode or detonate on an explosion instance.
func _trigger_detonation(instance: Node3D) -> void:
	if instance == null:
		return
	if instance.has_method(&"explode"):
		instance.call(&"explode")
	elif instance.has_method(&"detonate"):
		instance.call(&"detonate")


## Helper invoking reset on an explosion instance.
func _trigger_reset(instance: Node3D) -> void:
	if instance != null and instance.has_method(&"reset"):
		instance.call(&"reset")


## Tier 1: Verifies scene loads headlessly, attaches script, and initializes default exports.
func test_tier1_scene_instantiation() -> void:
	var packed_scene: PackedScene = _load_explosion_scene()
	assert_not_null(packed_scene, "Explosion scene must load cleanly from SCENE_PATH.")
	if packed_scene == null:
		return

	var instance: Node3D = packed_scene.instantiate() as Node3D
	assert_not_null(instance, "Instance must be a valid Node3D.")
	if instance == null:
		return

	assert_not_null(instance.get_script(), "Instance must have a controller script attached.")
	var auto_play_val: Variant = instance.get(&"auto_play")
	assert_eq(auto_play_val, true, "auto_play should default to true.")
	var free_val: Variant = instance.get(&"free_on_finish")
	assert_eq(free_val, true, "free_on_finish should default to true.")
	instance.free()


## Tier 1: Verifies presence and exact node types of all 5 mandatory child nodes.
func test_tier1_node_hierarchy_presence_and_types() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	var fireball: Node = instance.get_node_or_null("CoreFireball")
	assert_not_null(fireball, "Child CoreFireball must exist.")
	assert_true(fireball is GPUParticles3D, "CoreFireball must be GPUParticles3D.")

	var smoke: Node = instance.get_node_or_null("LingeringSmoke")
	assert_not_null(smoke, "Child LingeringSmoke must exist.")
	assert_true(smoke is GPUParticles3D, "LingeringSmoke must be GPUParticles3D.")

	var sparks: Node = instance.get_node_or_null("SparksAndDebris")
	assert_not_null(sparks, "Child SparksAndDebris must exist.")
	assert_true(sparks is GPUParticles3D, "SparksAndDebris must be GPUParticles3D.")

	var flash: Node = instance.get_node_or_null("DetonationFlash")
	assert_not_null(flash, "Child DetonationFlash must exist.")
	assert_true(flash is OmniLight3D, "DetonationFlash must be OmniLight3D.")

	var distortion: Node = instance.get_node_or_null("HeatDistortion")
	assert_not_null(distortion, "Child HeatDistortion must exist.")
	assert_true(distortion is MeshInstance3D, "HeatDistortion must be MeshInstance3D.")
	instance.free()


## Tier 1: Verifies CoreFireball particle counts, timing, quad size, and flipbook parameters.
func test_tier1_core_fireball_properties() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	var emitter: GPUParticles3D = instance.get_node_or_null("CoreFireball") as GPUParticles3D
	assert_not_null(emitter, "CoreFireball emitter missing.")
	if emitter == null:
		instance.free()
		return

	assert_eq(emitter.amount, 1, "CoreFireball particle amount must be 1.")
	assert_almost_eq(emitter.lifetime, 1.1, 0.05, "CoreFireball lifetime must be 1.1s.")
	assert_true(emitter.one_shot, "CoreFireball must be one_shot.")
	assert_almost_eq(emitter.explosiveness, 1.0, 0.05, "CoreFireball explosiveness must be 1.0.")

	assert_true(emitter.draw_pass_1 is QuadMesh, "CoreFireball draw pass 1 must be QuadMesh.")
	var quad: QuadMesh = emitter.draw_pass_1 as QuadMesh
	if quad != null:
		assert_almost_eq(quad.size.x, 5.0, 0.1, "CoreFireball QuadMesh width must be 5.0m.")
		assert_almost_eq(quad.size.y, 5.0, 0.1, "CoreFireball QuadMesh height must be 5.0m.")

		var mat: StandardMaterial3D = null
		if quad.material is StandardMaterial3D:
			mat = quad.material as StandardMaterial3D
		elif emitter.material_override is StandardMaterial3D:
			mat = emitter.material_override as StandardMaterial3D

		assert_not_null(mat, "CoreFireball must have a valid StandardMaterial3D.")
		if mat != null:
			assert_eq(
				mat.shading_mode,
				BaseMaterial3D.SHADING_MODE_UNSHADED,
				"CoreFireball material must be unshaded."
			)
			assert_eq(
				mat.billboard_mode,
				BaseMaterial3D.BILLBOARD_PARTICLES,
				"CoreFireball billboard_mode must be BILLBOARD_PARTICLES (3)."
			)
			assert_eq(mat.particles_anim_h_frames, 8, "Flipbook H frames must be 8.")
			assert_eq(mat.particles_anim_v_frames, 8, "Flipbook V frames must be 8.")
			assert_false(mat.particles_anim_loop, "Flipbook animation loop must be false.")

	var pmat: ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
	assert_not_null(pmat, "CoreFireball process_material must be ParticleProcessMaterial.")
	if pmat != null:
		assert_almost_eq(pmat.anim_speed_min, 1.0, 0.05, "anim_speed_min must be 1.0.")
		assert_almost_eq(pmat.anim_speed_max, 1.0, 0.05, "anim_speed_max must be 1.0.")

	instance.free()


## Tier 1: Verifies LingeringSmoke particle count, lifetime, upward gravity, and damping.
func test_tier1_lingering_smoke_properties() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	var emitter: GPUParticles3D = instance.get_node_or_null("LingeringSmoke") as GPUParticles3D
	assert_not_null(emitter, "LingeringSmoke emitter missing.")
	if emitter == null:
		instance.free()
		return

	assert_eq(emitter.amount, 12, "LingeringSmoke particle amount must be 12.")
	assert_almost_eq(emitter.lifetime, 3.5, 0.1, "LingeringSmoke lifetime must be 3.5s.")
	assert_true(emitter.one_shot, "LingeringSmoke must be one_shot.")
	assert_almost_eq(emitter.explosiveness, 0.85, 0.05, "LingeringSmoke explosiveness ~ 0.85.")

	assert_true(emitter.draw_pass_1 is QuadMesh, "LingeringSmoke draw pass 1 must be QuadMesh.")
	var pmat: ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
	assert_not_null(pmat, "LingeringSmoke process_material must be ParticleProcessMaterial.")
	if pmat != null:
		assert_almost_eq(pmat.gravity.y, 0.8, 0.1, "LingeringSmoke buoyant gravity Y must be 0.8.")
		var damping_val: float = pmat.damping_min if pmat.damping_min > 0.0 else pmat.damping_max
		assert_almost_eq(damping_val, 4.0, 0.5, "LingeringSmoke linear damping must be ~ 4.0.")
		var radial_val: float = (
			pmat.radial_velocity_min if pmat.radial_velocity_min > 0.0 else pmat.radial_velocity_max
		)
		assert_almost_eq(radial_val, 3.0, 0.5, "LingeringSmoke radial velocity must be ~ 3.0.")

	instance.free()


## Tier 1: Verifies SparksAndDebris particle count, HDR albedo, ballistic gravity, and collision.
func test_tier1_sparks_and_debris_properties() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	var emitter: GPUParticles3D = instance.get_node_or_null("SparksAndDebris") as GPUParticles3D
	assert_not_null(emitter, "SparksAndDebris emitter missing.")
	if emitter == null:
		instance.free()
		return

	assert_eq(emitter.amount, 60, "SparksAndDebris particle amount must be 60.")
	assert_almost_eq(emitter.lifetime, 1.8, 0.1, "SparksAndDebris lifetime must be 1.8s.")
	assert_true(emitter.one_shot, "SparksAndDebris must be one_shot.")
	assert_almost_eq(emitter.explosiveness, 0.98, 0.05, "SparksAndDebris explosiveness ~ 0.98.")

	assert_true(emitter.draw_pass_1 is QuadMesh, "SparksAndDebris draw pass 1 must be QuadMesh.")
	var quad: QuadMesh = emitter.draw_pass_1 as QuadMesh
	if quad != null:
		assert_almost_eq(quad.size.x, 0.08, 0.02, "Sparks QuadMesh width must be ~ 0.08m.")
		assert_almost_eq(quad.size.y, 0.4, 0.05, "Sparks QuadMesh height must be ~ 0.4m.")

		var mat: StandardMaterial3D = null
		if quad.material is StandardMaterial3D:
			mat = quad.material as StandardMaterial3D
		elif emitter.material_override is StandardMaterial3D:
			mat = emitter.material_override as StandardMaterial3D

		assert_not_null(mat, "SparksAndDebris must have a valid StandardMaterial3D.")
		if mat != null:
			assert_almost_eq(mat.albedo_color.r, 5.0, 0.2, "Sparks HDR albedo R must be ~ 5.0.")
			assert_almost_eq(mat.albedo_color.g, 2.2, 0.2, "Sparks HDR albedo G must be ~ 2.2.")
			assert_almost_eq(mat.albedo_color.b, 0.4, 0.1, "Sparks HDR albedo B must be ~ 0.4.")

	var pmat: ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
	assert_not_null(pmat, "SparksAndDebris process_material must be ParticleProcessMaterial.")
	if pmat != null:
		assert_almost_eq(pmat.gravity.y, -18.0, 0.5, "Sparks gravity Y must be -18.0.")
		assert_eq(
			pmat.collision_mode,
			ParticleProcessMaterial.COLLISION_RIGID,
			"Sparks collision_mode must be COLLISION_RIGID (1)."
		)

	instance.free()


## Tier 1: Verifies DetonationFlash light range, warm orange color, and peak energy.
func test_tier1_detonation_flash_properties() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	var flash: OmniLight3D = instance.get_node_or_null("DetonationFlash") as OmniLight3D
	assert_not_null(flash, "DetonationFlash light missing.")
	if flash == null:
		instance.free()
		return

	assert_almost_eq(flash.omni_range, 25.0, 0.5, "DetonationFlash omni_range must be 25.0m.")
	assert_almost_eq(flash.light_color.r, 1.0, 0.05, "DetonationFlash light_color R must be 1.0.")
	assert_almost_eq(flash.light_color.g, 0.6, 0.05, "DetonationFlash light_color G must be 0.6.")
	assert_almost_eq(flash.light_color.b, 0.2, 0.05, "DetonationFlash light_color B must be 0.2.")

	var peak_constant: Variant = instance.get(&"FLASH_PEAK_ENERGY")
	var peak_val: float = (
		peak_constant if peak_constant is float or peak_constant is int else flash.light_energy
	)
	assert_almost_eq(peak_val, 16.0, 0.5, "Peak flash energy must be 16.0.")
	instance.free()


## Tier 1: Verifies HeatDistortion uses SphereMesh and attaches explosion_shockwave.gdshader.
func test_tier1_heat_distortion_properties() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	var distortion: MeshInstance3D = instance.get_node_or_null("HeatDistortion") as MeshInstance3D
	assert_not_null(distortion, "HeatDistortion node missing.")
	if distortion == null:
		instance.free()
		return

	assert_true(distortion.mesh is SphereMesh, "HeatDistortion must use SphereMesh geometry.")

	var mat: ShaderMaterial = null
	if distortion.get_active_material(0) is ShaderMaterial:
		mat = distortion.get_active_material(0) as ShaderMaterial
	elif distortion.material_override is ShaderMaterial:
		mat = distortion.material_override as ShaderMaterial
	elif distortion.mesh != null and (distortion.mesh as SphereMesh).material is ShaderMaterial:
		mat = (distortion.mesh as SphereMesh).material as ShaderMaterial

	assert_not_null(mat, "HeatDistortion must have a ShaderMaterial.")
	if mat != null:
		assert_not_null(mat.shader, "ShaderMaterial must have an assigned Shader.")
		if mat.shader != null:
			var path_matches: bool = mat.shader.resource_path.ends_with(
				"explosion_shockwave.gdshader"
			)
			assert_true(path_matches, "Shader must be explosion_shockwave.gdshader.")

	instance.free()


## Tier 2: Verifies disabling auto_play prevents immediate particle and light activation.
func test_tier2_auto_play_disabled_behavior() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	add_child_autofree(instance)

	var fireball: GPUParticles3D = instance.get_node_or_null("CoreFireball") as GPUParticles3D
	var smoke: GPUParticles3D = instance.get_node_or_null("LingeringSmoke") as GPUParticles3D
	var sparks: GPUParticles3D = instance.get_node_or_null("SparksAndDebris") as GPUParticles3D
	var flash: OmniLight3D = instance.get_node_or_null("DetonationFlash") as OmniLight3D

	if fireball != null:
		assert_false(fireball.emitting, "CoreFireball must not emit when auto_play is false.")
	if smoke != null:
		assert_false(smoke.emitting, "LingeringSmoke must not emit when auto_play is false.")
	if sparks != null:
		assert_false(sparks.emitting, "SparksAndDebris must not emit when auto_play is false.")
	if flash != null:
		assert_true(
			not flash.visible or flash.light_energy <= 0.05,
			"DetonationFlash must be inactive when auto_play is false."
		)


## Tier 2: Verifies manual detonation triggers particle emission, light, and shockwave.
func test_tier2_manual_explode_triggers_emission() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	add_child_autofree(instance)
	var has_trigger: bool = instance.has_method(&"explode") or instance.has_method(&"detonate")
	assert_true(has_trigger, "Controller must implement explode() or detonate().")

	_trigger_detonation(instance)

	var fireball: GPUParticles3D = instance.get_node_or_null("CoreFireball") as GPUParticles3D
	var smoke: GPUParticles3D = instance.get_node_or_null("LingeringSmoke") as GPUParticles3D
	var sparks: GPUParticles3D = instance.get_node_or_null("SparksAndDebris") as GPUParticles3D
	var flash: OmniLight3D = instance.get_node_or_null("DetonationFlash") as OmniLight3D
	var distortion: MeshInstance3D = instance.get_node_or_null("HeatDistortion") as MeshInstance3D

	if fireball != null:
		assert_true(fireball.emitting, "CoreFireball must emit after detonation call.")
	if smoke != null:
		assert_true(smoke.emitting, "LingeringSmoke must emit after detonation call.")
	if sparks != null:
		assert_true(sparks.emitting, "SparksAndDebris must emit after detonation call.")
	if flash != null:
		assert_true(flash.visible, "DetonationFlash must become visible after detonation call.")
		assert_gt(flash.light_energy, 0.0, "DetonationFlash light_energy must be > 0.")
	if distortion != null:
		assert_true(distortion.visible, "HeatDistortion must become visible after detonation call.")


## Tier 2: Verifies reset() returns particle emitters, flash, and shockwave to baseline.
func test_tier2_reset_returns_to_baseline() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	add_child_autofree(instance)
	_trigger_detonation(instance)

	assert_true(instance.has_method(&"reset"), "Controller must provide reset() method.")
	_trigger_reset(instance)

	var fireball: GPUParticles3D = instance.get_node_or_null("CoreFireball") as GPUParticles3D
	var smoke: GPUParticles3D = instance.get_node_or_null("LingeringSmoke") as GPUParticles3D
	var sparks: GPUParticles3D = instance.get_node_or_null("SparksAndDebris") as GPUParticles3D
	var flash: OmniLight3D = instance.get_node_or_null("DetonationFlash") as OmniLight3D
	var distortion: MeshInstance3D = instance.get_node_or_null("HeatDistortion") as MeshInstance3D

	if fireball != null:
		assert_false(fireball.emitting, "CoreFireball must cease emitting after reset().")
	if smoke != null:
		assert_false(smoke.emitting, "LingeringSmoke must cease emitting after reset().")
	if sparks != null:
		assert_false(sparks.emitting, "SparksAndDebris must cease emitting after reset().")
	if flash != null:
		assert_true(
			not flash.visible or flash.light_energy <= 0.05,
			"DetonationFlash must be hidden or 0 energy after reset()."
		)
	if distortion != null:
		assert_false(distortion.visible, "HeatDistortion must be hidden after reset().")


## Tier 2: Verifies early node freeing does not cause unhandled tween or timer crashes.
func test_tier2_early_freeing_safety() -> void:
	var instance: Node3D = _instantiate_explosion(true, true)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	add_child(instance)
	await wait_physics_frames(2)

	instance.queue_free()
	await wait_physics_frames(2)
	assert_false(is_instance_valid(instance), "Instance should free cleanly without errors.")


## Tier 3: Verifies all three particle systems, flash, and shockwave activate in the same frame.
func test_tier3_synchronized_detonation() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	add_child_autofree(instance)
	_trigger_detonation(instance)

	var fireball: GPUParticles3D = instance.get_node_or_null("CoreFireball") as GPUParticles3D
	var smoke: GPUParticles3D = instance.get_node_or_null("LingeringSmoke") as GPUParticles3D
	var sparks: GPUParticles3D = instance.get_node_or_null("SparksAndDebris") as GPUParticles3D
	var flash: OmniLight3D = instance.get_node_or_null("DetonationFlash") as OmniLight3D
	var distortion: MeshInstance3D = instance.get_node_or_null("HeatDistortion") as MeshInstance3D

	var all_synchronized: bool = (
		fireball != null
		and fireball.emitting
		and smoke != null
		and smoke.emitting
		and sparks != null
		and sparks.emitting
		and flash != null
		and flash.visible
		and distortion != null
		and distortion.visible
	)
	assert_true(all_synchronized, "All 5 explosion sub-components must synchronize on frame 0.")


## Tier 3: Verifies DetonationFlash collapses from 16.0 towards 0.0 during tween duration.
func test_tier3_flash_energy_decay_tween() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	add_child_autofree(instance)
	_trigger_detonation(instance)

	var flash: OmniLight3D = instance.get_node_or_null("DetonationFlash") as OmniLight3D
	assert_not_null(flash, "DetonationFlash light missing.")
	if flash == null:
		return

	assert_almost_eq(flash.light_energy, 16.0, 0.5, "Flash energy must initialize at 16.0.")

	await wait_seconds(0.08)
	assert_lt(flash.light_energy, 14.0, "Flash energy must collapse significantly after 0.08s.")

	await wait_seconds(0.12)
	assert_true(
		flash.light_energy <= 0.1 or not flash.visible,
		"Flash energy must decay to ~0 or hide after full duration."
	)


## Tier 3: Verifies declaration and emission of detonation lifecycle signals.
func test_tier3_signals_declaration_and_emission() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	add_child_autofree(instance)
	assert_true(
		instance.has_signal(&"detonation_started"),
		"Controller must declare detonation_started signal."
	)
	assert_true(
		instance.has_signal(&"detonation_finished"),
		"Controller must declare detonation_finished signal."
	)

	watch_signals(instance)
	_trigger_detonation(instance)
	assert_signal_emitted(
		instance, &"detonation_started", "detonation_started signal must emit on explosion trigger."
	)


## Tier 4: Simulates multiple concurrent gameplay explosions without state collision.
func test_tier4_gameplay_burst_simulation() -> void:
	var burst_count: int = 5
	var instances: Array[Node3D] = []

	for burst_index: int in range(burst_count):
		var burst_inst: Node3D = _instantiate_explosion(true, false)
		assert_not_null(burst_inst, "Burst instance must instantiate successfully.")
		if burst_inst != null:
			burst_inst.position = Vector3(float(burst_index) * 4.0, 0.0, 0.0)
			add_child_autofree(burst_inst)
			instances.append(burst_inst)

	await wait_physics_frames(3)
	for active_inst: Node3D in instances:
		assert_true(is_instance_valid(active_inst), "Burst instance must remain valid in tree.")
		var fireball: GPUParticles3D = (
			active_inst.get_node_or_null("CoreFireball") as GPUParticles3D
		)
		if fireball != null:
			assert_true(fireball.emitting, "Burst instance emitter must be actively firing.")


## Tier 4: Verifies free_on_finish export can be toggled safely for reuse or retained debugging.
func test_tier4_lifecycle_free_on_finish_toggle() -> void:
	var instance: Node3D = _instantiate_explosion(false, false)
	assert_not_null(instance, "Failed to instantiate explosion scene.")
	if instance == null:
		return

	instance.set(&"free_on_finish", false)
	var flag_false: Variant = instance.get(&"free_on_finish")
	assert_eq(flag_false, false, "free_on_finish must be toggleable to false.")

	instance.set(&"free_on_finish", true)
	var flag_true: Variant = instance.get(&"free_on_finish")
	assert_eq(flag_true, true, "free_on_finish must be toggleable to true.")
	instance.free()
