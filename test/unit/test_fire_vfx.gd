## Unit tests for [FireFlipbookEmitter], fire_pit.tscn layers, presets, and fire shaders.
class_name TestFireVfx
extends GutTest

const FIRE_PIT_SCENE: PackedScene = preload("res://vfx/fire_pit.tscn")
const FIRE_PUNCHY_SHADER: Shader = preload("res://vfx/fire_punchy.gdshader")
const FIRE_RAYMARCH_SHADER: Shader = preload("res://vfx/fire.gdshader")

var _fire_pit: FireFlipbookEmitter = null


## Instantiates a fresh [FireFlipbookEmitter] from fire_pit.tscn before each test.
func before_each() -> void:
	_fire_pit = FIRE_PIT_SCENE.instantiate() as FireFlipbookEmitter
	add_child_autofree(_fire_pit)


## Verifies fire_pit.tscn instantiates all required layers and preserves legacy node names.
func test_scene_instantiation_and_layers() -> void:
	assert_not_null(_fire_pit, "fire_pit.tscn must instantiate FireFlipbookEmitter.")
	var flame: GPUParticles3D = _fire_pit.get_node_or_null(^"FlameParticles") as GPUParticles3D
	var outer: GPUParticles3D = _fire_pit.get_node_or_null(^"FlameOuterParticles") as GPUParticles3D
	var embers: GPUParticles3D = _fire_pit.get_node_or_null(^"EmberParticles") as GPUParticles3D
	var smoke: GPUParticles3D = _fire_pit.get_node_or_null(^"SmokeParticles") as GPUParticles3D
	var heat: GPUParticles3D = _fire_pit.get_node_or_null(^"HeatDistortion") as GPUParticles3D
	var light: OmniLight3D = _fire_pit.get_node_or_null(^"FireLight") as OmniLight3D
	var notifier: VisibleOnScreenNotifier3D = (
		_fire_pit.get_node_or_null(^"VisibilityNotifier") as VisibleOnScreenNotifier3D
	)

	assert_not_null(flame, "FlameParticles child must exist.")
	assert_not_null(outer, "FlameOuterParticles child must exist.")
	assert_not_null(embers, "EmberParticles child must exist.")
	assert_not_null(smoke, "SmokeParticles child must exist.")
	assert_not_null(heat, "HeatDistortion child must exist.")
	assert_not_null(light, "FireLight child must exist.")
	assert_not_null(notifier, "VisibilityNotifier child must exist.")

	assert_eq(flame.layers, 512, "FlameParticles must render on Layer 10 (512).")
	assert_eq(outer.layers, 512, "FlameOuterParticles must render on Layer 10 (512).")
	assert_eq(embers.layers, 512, "EmberParticles must render on Layer 10 (512).")
	assert_eq(smoke.layers, 512, "SmokeParticles must render on Layer 10 (512).")
	assert_eq(heat.layers, 512, "HeatDistortion must render on Layer 10 (512).")
	assert_almost_eq(heat.position.y, 0.95, 0.01, "HeatDistortion should sit at y=0.95.")
	assert_almost_eq(light.omni_range, 7.5, 0.01, "Default FireLight omni_range should be 7.5.")


## Verifies _process() and _physics_process() remain disabled on [FireFlipbookEmitter].
func test_process_disabled() -> void:
	assert_false(_fire_pit.is_processing(), "FireFlipbookEmitter must disable _process().")
	assert_false(
		_fire_pit.is_physics_processing(), "FireFlipbookEmitter must disable _physics_process()."
	)


## Verifies all four FirePreset modes apply distinct HDR, smoke, and scale configurations.
func test_all_fire_presets() -> void:
	var flame: GPUParticles3D = _fire_pit.get_node(^"FlameParticles") as GPUParticles3D
	var smoke: GPUParticles3D = _fire_pit.get_node(^"SmokeParticles") as GPUParticles3D
	var light: OmniLight3D = _fire_pit.get_node(^"FireLight") as OmniLight3D

	_fire_pit.fire_preset = FireFlipbookEmitter.FirePreset.CAMPFIRE
	var campfire_hdr: Variant = flame.get_instance_shader_parameter(&"hdr_intensity")
	assert_true(campfire_hdr is float)
	if campfire_hdr is float:
		var val: float = campfire_hdr
		assert_almost_eq(val, 2.4, 0.01)

	_fire_pit.fire_preset = FireFlipbookEmitter.FirePreset.BONFIRE
	var bonfire_hdr: Variant = flame.get_instance_shader_parameter(&"hdr_intensity")
	assert_true(bonfire_hdr is float)
	if bonfire_hdr is float:
		var val: float = bonfire_hdr
		assert_almost_eq(val, 3.2, 0.01)
	assert_gt(light.omni_range, 9.0, "Bonfire preset should expand light range.")

	_fire_pit.fire_preset = FireFlipbookEmitter.FirePreset.OIL_FIRE
	var oil_density: Variant = smoke.get_instance_shader_parameter(&"density_scale")
	assert_true(oil_density is float)
	if oil_density is float:
		var val: float = oil_density
		assert_almost_eq(val, 1.35, 0.01)

	_fire_pit.fire_preset = FireFlipbookEmitter.FirePreset.TORCH
	assert_lt(flame.scale.x, 0.7, "Torch preset should scale down the flame.")
	assert_almost_eq(light.light_energy, 1.8, 0.01)


## Verifies is_active toggles emission across all particles, heat distortion, and light.
func test_is_active_toggle() -> void:
	var flame: GPUParticles3D = _fire_pit.get_node(^"FlameParticles") as GPUParticles3D
	var outer: GPUParticles3D = _fire_pit.get_node(^"FlameOuterParticles") as GPUParticles3D
	var embers: GPUParticles3D = _fire_pit.get_node(^"EmberParticles") as GPUParticles3D
	var smoke: GPUParticles3D = _fire_pit.get_node(^"SmokeParticles") as GPUParticles3D
	var heat: GasLeakEmitter = _fire_pit.get_node(^"HeatDistortion") as GasLeakEmitter
	var light: OmniLight3D = _fire_pit.get_node(^"FireLight") as OmniLight3D

	_fire_pit.is_active = false
	assert_false(flame.emitting)
	assert_false(outer.emitting)
	assert_false(embers.emitting)
	assert_false(smoke.emitting)
	assert_false(heat.is_leaking)
	assert_false(light.visible)

	_fire_pit.is_active = true
	assert_true(flame.emitting)
	assert_true(outer.emitting)
	assert_true(embers.emitting)
	assert_true(smoke.emitting)
	assert_true(heat.is_leaking)
	assert_true(light.visible)


## Verifies fire_scale clamps to [0.25, 3.0] and updates emitter scale transforms.
func test_fire_scale_bounds() -> void:
	var flame: GPUParticles3D = _fire_pit.get_node(^"FlameParticles") as GPUParticles3D

	_fire_pit.fire_scale = 0.05
	assert_almost_eq(_fire_pit.fire_scale, 0.25, 0.001, "fire_scale should clamp to 0.25.")
	assert_almost_eq(flame.scale.x, 0.25, 0.001)

	_fire_pit.fire_scale = 8.0
	assert_almost_eq(_fire_pit.fire_scale, 3.0, 0.001, "fire_scale should clamp to 3.0.")
	assert_almost_eq(flame.scale.x, 3.0, 0.001)

	_fire_pit.fire_scale = 1.5
	assert_almost_eq(_fire_pit.fire_scale, 1.5, 0.001)
	assert_almost_eq(flame.scale.x, 1.5, 0.001)


## Verifies fire_punchy.gdshader and fire.gdshader compile as spatial shaders with uniforms.
func test_fire_shaders_modes_and_uniforms() -> void:
	assert_not_null(FIRE_PUNCHY_SHADER)
	assert_eq(FIRE_PUNCHY_SHADER.get_mode(), Shader.MODE_SPATIAL)
	assert_true(FIRE_PUNCHY_SHADER.code.contains("instance uniform float hdr_intensity"))
	assert_true(FIRE_PUNCHY_SHADER.code.contains("instance uniform float flicker_speed"))
	assert_true(FIRE_PUNCHY_SHADER.code.contains("instance uniform vec3 tint_shift"))

	assert_not_null(FIRE_RAYMARCH_SHADER)
	assert_eq(FIRE_RAYMARCH_SHADER.get_mode(), Shader.MODE_SPATIAL)
	assert_true(FIRE_RAYMARCH_SHADER.code.contains("interleaved_gradient_noise"))
	assert_true(FIRE_RAYMARCH_SHADER.code.contains("pow(density, 1.75) * emission_strength * 2.0"))
