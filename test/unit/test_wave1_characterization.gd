## Characterization tests locking Wave 1 active shader compilation, modes, and uniform contracts.
class_name TestWave1Characterization
extends GutTest

## Active Wave 1 spatial shaders (excluding 7 orphan candidates scheduled for removal).
const SPATIAL_SHADERS: Array[String] = [
	"res://environment/dynamic_ocean/shaders/ocean_spray.gdshader",
	"res://environment/dynamic_ocean/shaders/ocean_water.gdshader",
	"res://environment/Citadel_TEST_2.gdshader",
	"res://environment/argon_citadel_core/argon_citadel_corona.gdshader",
	"res://environment/argon_citadel_core/argon_citadel_corona_waves.gdshader",
	"res://environment/argon_citadel_core/argon_citadel_energy.gdshader",
	"res://environment/argon_citadel_core/argon_citadel_inner_core.gdshader",
	"res://environment/argon_citadel_core/argon_citadel_outer_shell.gdshader",
	"res://environment/argon_water_body/argon_water.gdshader",
	"res://environment/electrified_floor.gdshader",
	"res://environment/flag_waving.gdshader",
	"res://environment/hydrogen_water_body/hydrogen_water_body.gdshader",
	"res://environment/lex_partizan_rain/rain.gdshader",
	"res://environment/lex_partizan_rain/roof_depth.gdshader",
	"res://environment/lightning_manager.gdshader",
	"res://environment/lightning_orb.gdshader",
	"res://environment/lightning_orb_arc.gdshader",
	"res://environment/liquid_ribbon.gdshader",
	"res://environment/projector_rain.gdshader",
	"res://environment/rainy_window_procedural.gdshader",
	"res://environment/water_body.gdshader",
	"res://environment/waterfall.gdshader",
	"res://environment/weather_volume/dust_particle.gdshader",
	"res://environment/weather_volume/snow_particle.gdshader",
	"res://environment/windy_cloth.gdshader",
	"res://interactables/conveyor_belt.gdshader",
	"res://interactables/destructible_glass.gdshader",
	"res://interactables/energy_bar.gdshader",
	"res://interactables/grimy_horror_glass.gdshader",
	"res://interactables/indicator_led.gdshader",
	"res://interactables/liquid_bottle/liquid_bottle.gdshader",
	"res://interactables/mirror.gdshader",
	"res://interactables/pickable_highlight.gdshader",
	"res://interactables/pneumatic_tube_glass.gdshader",
	"res://interactables/portal.gdshader",
	"res://interactables/rusted_horror_metal.gdshader",
	"res://interactables/sewer_grate/sewer_grate.gdshader",
	"res://interactables/wind_cable.gdshader",
	"res://player/holographic_scanner.gdshader",
	"res://props/breakable_shelf/breakable_shelf.gdshader",
	"res://props/garage_gate/garage_panel.gdshader",
	"res://props/gothic_arch/gothic_arch_stone.gdshader",
	"res://shaders/cinder_block.gdshader",
	"res://shaders/crate_fade.gdshader",
	"res://shaders/dark_man_surface.gdshader",
	"res://shaders/dumpster_weathered.gdshader",
	"res://shaders/fluted_glass.gdshader",
	"res://shaders/health_dispenser_screen.gdshader",
	"res://shaders/heavy_rain_glass.gdshader",
	"res://shaders/industrial_door.gdshader",
	"res://shaders/lens_dirt_billboard.gdshader",
	"res://shaders/props/gas_stove.gdshader",
	"res://shaders/props/tin_can.gdshader",
	"res://shaders/rain_drop.gdshader",
	"res://shaders/revolver_orm.gdshader",
	"res://shaders/shroud_mannequinn.gdshader",
	"res://shaders/squid_tentacle.gdshader",
	"res://shaders/tagged_prop.gdshader",
	"res://shaders/textured_glass.gdshader",
	"res://shaders/tube_opaque.gdshader",
	"res://shaders/tube_transparent.gdshader",
	"res://shaders/wind_wall.gdshader",
	"res://ui/VisionAssist.gdshader",
	"res://ui/gel.gdshader",
]

## Active Wave 1 canvas_item shaders.
const CANVAS_ITEM_SHADERS: Array[String] = [
	"res://environment/argon_citadel_core/argon_citadel_heat_wave.gdshader",
	"res://environment/deprecated_camera_water_overlay2.gdshader",
	"res://environment/grain.gdshader",
	"res://environment/water_ripple_overlay.gdshader",
	"res://environment/water_wipe_overlay.gdshader",
	"res://environment/waterfall_wipe_overlay.gdshader",
	"res://shaders/drunk_post.gdshader",
	"res://shaders/roar_distortion.gdshader",
	"res://shaders/screen_transition.gdshader",
	"res://ui/anime_speed_lines.gdshader",
	"res://ui/claw_fire_outline.gdshader",
	"res://ui/death_glass_screen.gdshader",
	"res://ui/death_screen_ecg.gdshader",
	"res://ui/death_screen_jitter.gdshader",
	"res://ui/electricityvignette.gdshader",
	"res://ui/horror_black_glass.gdshader",
	"res://ui/horror_glow_border.gdshader",
	"res://ui/menu_chapter_screen.gdshader",
]

## Active Wave 1 fog shaders.
const FOG_SHADERS: Array[String] = [
	"res://environment/DynamicFog/dynamic_fog.gdshader",
	"res://environment/argon_water_body/argon_fog_fade.gdshader",
	"res://environment/fog_fade.gdshader",
	"res://environment/hydrogen_water_body/hydrogen_fog_fade.gdshader",
]

## Active Wave 1 particles shaders.
const PARTICLES_SHADERS: Array[String] = [
	"res://environment/dynamic_ocean/shaders/ocean_spray_particle.gdshader",
	"res://shaders/rain_process.gdshader",
]


## Verifies all 63 active Wave 1 spatial shaders load, have code, and report MODE_SPATIAL.
func test_spatial_shaders_load_and_mode() -> void:
	assert_eq(SPATIAL_SHADERS.size(), 63)
	for path: String in SPATIAL_SHADERS:
		var shader: Shader = _load_shader(path)
		assert_not_null(shader, "Failed to load spatial shader: %s" % path)
		if shader != null:
			assert_false(shader.code.is_empty(), "Empty shader code: %s" % path)
			assert_eq(shader.get_mode(), Shader.MODE_SPATIAL, "Expected MODE_SPATIAL for %s" % path)


## Verifies all 18 active Wave 1 canvas_item shaders load, have code, and report MODE_CANVAS_ITEM.
func test_canvas_item_shaders_load_and_mode() -> void:
	assert_eq(CANVAS_ITEM_SHADERS.size(), 18)
	for path: String in CANVAS_ITEM_SHADERS:
		var shader: Shader = _load_shader(path)
		assert_not_null(shader, "Failed to load canvas_item shader: %s" % path)
		if shader != null:
			assert_false(shader.code.is_empty(), "Empty shader code: %s" % path)
			assert_eq(
				shader.get_mode(),
				Shader.MODE_CANVAS_ITEM,
				"Expected MODE_CANVAS_ITEM for %s" % path
			)


## Verifies all 4 active Wave 1 fog shaders load, have code, and report MODE_FOG.
func test_fog_shaders_load_and_mode() -> void:
	assert_eq(FOG_SHADERS.size(), 4)
	for path: String in FOG_SHADERS:
		var shader: Shader = _load_shader(path)
		assert_not_null(shader, "Failed to load fog shader: %s" % path)
		if shader != null:
			assert_false(shader.code.is_empty(), "Empty shader code: %s" % path)
			assert_eq(shader.get_mode(), Shader.MODE_FOG, "Expected MODE_FOG for %s" % path)


## Verifies both active Wave 1 particles shaders load, have code, and report MODE_PARTICLES.
func test_particles_shaders_load_and_mode() -> void:
	assert_eq(PARTICLES_SHADERS.size(), 2)
	for path: String in PARTICLES_SHADERS:
		var shader: Shader = _load_shader(path)
		assert_not_null(shader, "Failed to load particles shader: %s" % path)
		if shader != null:
			assert_false(shader.code.is_empty(), "Empty shader code: %s" % path)
			assert_eq(
				shader.get_mode(), Shader.MODE_PARTICLES, "Expected MODE_PARTICLES for %s" % path
			)


## Verifies dynamic ocean shader uniform contracts for water, spray, and spray particles.
func test_dynamic_ocean_uniform_contracts() -> void:
	_assert_uniforms(
		"res://environment/dynamic_ocean/shaders/ocean_water.gdshader",
		[
			"depth_color_consumption",
			"crest_color",
			"crest_glow_intensity",
			"aerated_foam_glow",
			"roughness",
			"normal_strength",
			"foam_noise_tex",
			"map_scales",
		]
	)
	_assert_uniforms(
		"res://environment/dynamic_ocean/shaders/ocean_spray.gdshader",
		[
			"max_alpha",
			"brightness_multiplier",
			"albedo_texture",
			"dissolve_texture",
		]
	)
	_assert_uniforms(
		"res://environment/dynamic_ocean/shaders/ocean_spray_particle.gdshader",
		[
			"num_particles",
			"particle_scale",
			"lifetime",
			"lifetime_randomness",
			"spawn_radius",
			"map_scales",
		]
	)


## Verifies fog shader uniform contracts across dynamic_fog and all three fog_fade variants.
func test_fog_shader_uniform_contracts() -> void:
	_assert_uniforms(
		"res://environment/fog_fade.gdshader",
		[
			"density",
			"albedo",
			"emission",
			"height_falloff",
			"edge_fade",
			"near_fog_ratio",
			"fade_sharpness",
			"density_texture",
			"fade_plane",
		]
	)
	_assert_uniforms(
		"res://environment/argon_water_body/argon_fog_fade.gdshader",
		[
			"density",
			"albedo",
			"emission",
			"height_falloff",
			"edge_fade",
			"density_texture",
			"fade_plane",
		]
	)
	_assert_uniforms(
		"res://environment/hydrogen_water_body/hydrogen_fog_fade.gdshader",
		[
			"base_density",
			"albedo",
			"emission",
			"height_falloff",
			"edge_fade",
		]
	)
	_assert_uniforms(
		"res://environment/DynamicFog/dynamic_fog.gdshader",
		[
			"base_color",
			"emission_color",
			"base_density",
			"height_falloff",
			"ground_hugging_height",
		]
	)


## Verifies environment water body and rain shader uniform contracts.
func test_environment_water_and_rain_uniform_contracts() -> void:
	_assert_uniforms(
		"res://environment/water_body.gdshader",
		[
			"foam_color",
			"foam_distance",
			"crest_foam_threshold",
		]
	)
	_assert_uniforms(
		"res://environment/argon_water_body/argon_water.gdshader",
		[
			"water_time",
			"wave_amplitude",
			"wave_frequency",
			"wave_speed",
			"wave_steepness",
		]
	)
	_assert_uniforms(
		"res://environment/hydrogen_water_body/hydrogen_water_body.gdshader",
		[
			"water_size",
			"show_side_walls",
			"water_time",
		]
	)
	_assert_uniforms(
		"res://environment/lex_partizan_rain/rain.gdshader",
		[
			"Material_Albedo",
			"Material_Norm",
			"Material_Rough",
			"Material_Metal",
			"Material_Height",
		]
	)


## Verifies interactable and player shader uniform contracts including mirror and scanner.
func test_interactable_and_player_uniform_contracts() -> void:
	_assert_uniforms(
		"res://interactables/mirror.gdshader",
		[
			"reflection_texture",
			"glass_tint",
			"base_roughness",
		]
	)
	_assert_uniforms(
		"res://interactables/destructible_glass.gdshader",
		[
			"glass_tint",
			"fresnel_power",
			"fresnel_strength",
			"cage_color",
			"cage_density",
			"cage_thickness",
			"cage_depth",
			"base_roughness",
			"is_armored",
			"crack_intensity",
			"impact_uv",
		]
	)
	_assert_uniforms(
		"res://interactables/conveyor_belt.gdshader",
		"res://interactables/destructible_glass.gdshader",
		[
			"albedo_texture",
			"texture_scale",
		]
	)
	var conveyor_shader: Shader = _load_shader("res://interactables/conveyor_belt.gdshader")
	assert_not_null(conveyor_shader)
	if conveyor_shader != null:
		assert_true(conveyor_shader.code.contains("instance uniform float scroll_speed"))
		assert_true(conveyor_shader.code.contains("instance uniform float rotation_angle"))
	var scanner_shader: Shader = _load_shader("res://player/holographic_scanner.gdshader")
	assert_not_null(scanner_shader)
	if scanner_shader != null:
		assert_true(scanner_shader.code.contains("instance uniform vec4 base_color"))
		assert_true(scanner_shader.code.contains("instance uniform vec4 line_color"))
		assert_true(scanner_shader.code.contains("instance uniform float speed"))
		assert_true(scanner_shader.code.contains("instance uniform float line_count"))
		assert_true(scanner_shader.code.contains("instance uniform float line_thickness"))
		assert_true(scanner_shader.code.contains("instance uniform float glow_multiplier"))


## Verifies post-process, transition, and VisionAssist uniform contracts.
func test_post_process_and_ui_uniform_contracts() -> void:
	_assert_uniforms(
		"res://shaders/drunk_post.gdshader",
		[
			"intensity",
			"enable_desaturation",
			"desaturation_amount",
			"trail_decay",
			"zoom_amount",
			"drunk_speed",
			"drunk_amplitude",
			"blur_radius",
			"chromatic_aberration",
		]
	)
	_assert_uniforms(
		"res://shaders/screen_transition.gdshader",
		[
			"fade_color",
			"fade_amount",
			"blur_amount",
			"blink_openness",
		]
	)
	_assert_uniforms(
		"res://ui/VisionAssist.gdshader",
		[
			"mode",
			"blue_base",
			"blue_outline",
			"grey_base",
			"grey_outline",
			"outline_thickness",
			"depth_threshold",
			"normal_threshold",
		]
	)


## Verifies ShaderMaterial parameter round-trip on representative Wave 1 shaders.
func test_shader_material_parameter_binding() -> void:
	var drunk_shader: Shader = _load_shader("res://shaders/drunk_post.gdshader")
	assert_not_null(drunk_shader)
	if drunk_shader != null:
		var drunk_mat: ShaderMaterial = ShaderMaterial.new()
		drunk_mat.shader = drunk_shader
		drunk_mat.set_shader_parameter(&"intensity", 0.75)
		var intensity_raw: Variant = drunk_mat.get_shader_parameter(&"intensity")
		assert_true(intensity_raw is float)
		if intensity_raw is float:
			var intensity_val: float = intensity_raw
			assert_almost_eq(intensity_val, 0.75, 0.001)

	var transition_shader: Shader = _load_shader("res://shaders/screen_transition.gdshader")
	assert_not_null(transition_shader)
	if transition_shader != null:
		var trans_mat: ShaderMaterial = ShaderMaterial.new()
		trans_mat.shader = transition_shader
		trans_mat.set_shader_parameter(&"fade_amount", 0.5)
		trans_mat.set_shader_parameter(&"blink_openness", 0.25)
		var fade_raw: Variant = trans_mat.get_shader_parameter(&"fade_amount")
		var blink_raw: Variant = trans_mat.get_shader_parameter(&"blink_openness")
		assert_true(fade_raw is float)
		assert_true(blink_raw is float)
		if fade_raw is float and blink_raw is float:
			var fade_val: float = fade_raw
			var blink_val: float = blink_raw
			assert_almost_eq(fade_val, 0.5, 0.001)
			assert_almost_eq(blink_val, 0.25, 0.001)

	var vision_shader: Shader = _load_shader("res://ui/VisionAssist.gdshader")
	assert_not_null(vision_shader)
	if vision_shader != null:
		var vision_mat: ShaderMaterial = ShaderMaterial.new()
		vision_mat.shader = vision_shader
		vision_mat.set_shader_parameter(&"mode", 3)
		var mode_raw: Variant = vision_mat.get_shader_parameter(&"mode")
		assert_true(mode_raw is int)
		if mode_raw is int:
			var mode_val: int = mode_raw
			assert_eq(mode_val, 3)


func _load_shader(path: String) -> Shader:
	var res: Resource = ResourceLoader.load(path)
	if res is Shader:
		return res as Shader
	return null


func _assert_uniforms(path: String, expected_names: Array[String]) -> void:
	var shader: Shader = _load_shader(path)
	assert_not_null(shader, "Missing shader for uniform check: %s" % path)
	if shader == null:
		return
	var uniform_list: Array = shader.get_shader_uniform_list()
	var found_names: Dictionary[String, bool] = {}
	for entry_raw: Variant in uniform_list:
		if entry_raw is Dictionary:
			var entry: Dictionary = entry_raw
			var name_raw: Variant = entry.get("name", "")
			if name_raw is String:
				var uniform_name: String = name_raw
				found_names[uniform_name] = true
	for expected: String in expected_names:
		assert_true(found_names.has(expected), "Missing uniform '%s' in %s" % [expected, path])
