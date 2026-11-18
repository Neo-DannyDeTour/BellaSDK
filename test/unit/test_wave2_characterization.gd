## Characterization tests locking Wave 2 active shader compilation, modes, and uniform contracts.
class_name TestWave2Characterization
extends GutTest

## Active Wave 2 spatial shaders (excluding orphan candidates scheduled for removal).
const SPATIAL_SHADERS: Array[String] = [
	"res://vfx/3DBurnShader.gdshader",
	"res://vfx/3Dshockwave.gdshader",
	"res://vfx/CitadelCode_Glowing_Circle.gdshader",
	"res://vfx/CitadelCore_HeatDistortion.gdshader",
	"res://vfx/CitadelCore_Waves.gdshader",
	"res://vfx/OuterLiquidShell.gdshader",
	"res://vfx/arcane_burst.gdshader",
	"res://vfx/argon_lightning_strike.gdshader",
	"res://vfx/aurora_borealis.gdshader",
	"res://vfx/beam.gdshader",
	"res://vfx/blood_mist.gdshader",
	"res://vfx/blood_spray.gdshader",
	"res://vfx/caustics_shader.gdshader",
	"res://vfx/censor_mosaic.gdshader",
	"res://vfx/circle_equalizer.gdshader",
	"res://vfx/control_hiss_distortion.gdshader",
	"res://vfx/curtain.gdshader",
	"res://vfx/dev_texture.gdshader",
	"res://vfx/energy_wall.gdshader",
	"res://vfx/explosion_liquid_droplet.gdshader",
	"res://vfx/explosion_shockwave.gdshader",
	"res://vfx/explosion_sparks.gdshader",
	"res://vfx/explosion_volumetric_smoke.gdshader",
	"res://vfx/fire.gdshader",
	"res://vfx/gas_leak.gdshader",
	"res://vfx/gothic_energy_gate.gdshader",
	"res://vfx/green_blood.gdshader",
	"res://vfx/hex_shield.gdshader",
	"res://vfx/hex_shield_sphere.gdshader",
	"res://vfx/jelly.gdshader",
	"res://vfx/lightning_bolt.gdshader",
	"res://vfx/lightning_mark.gdshader",
	"res://vfx/lightning_wave.gdshader",
	"res://vfx/oil_spill.gdshader",
	"res://vfx/phys_magnet.gdshader",
	"res://vfx/plasma_spark.gdshader",
	"res://vfx/pressurized_fire_jet/pressurized_fire_jet.gdshader",
	"res://vfx/shockwave_refract.gdshader",
	"res://vfx/smoke_billow.gdshader",
	"res://vfx/smoke_lod.gdshader",
	"res://vfx/snow_deform.gdshader",
	"res://vfx/splat.gdshader",
	"res://vfx/unlit_outline_material.gdshader",
	"res://vfx/updraft_paper_strip.gdshader",
	"res://vfx/updraft_smoke.gdshader",
	"res://vfx/updraft_wind_lines.gdshader",
	"res://vfx/water_particle.gdshader",
	"res://vfx/waterfall_3d.gdshader",
	"res://vfx/zoom_mask.gdshader",
	"res://world/chunks/test_chunk_tint.gdshader",
]

## Active Wave 2 canvas_item shaders (excluding orphan candidates scheduled for removal).
const CANVAS_ITEM_SHADERS: Array[String] = [
	"res://ui/setting_row_hover.gdshader",
	"res://ui/ui_vignette.gdshader",
	"res://ui/ui_zoom_fisheye_blur.gdshader",
	"res://ui/wolf_vision.gdshader",
	"res://vfx/80sfantasy.gdshader",
	"res://vfx/90anime.gdshader",
	"res://vfx/advisor_psychic.gdshader",
	"res://vfx/ascii.gdshader",
	"res://vfx/botw.gdshader",
	"res://vfx/chapter_text_blur.gdshader",
	"res://vfx/chapter_text_chromatic.gdshader",
	"res://vfx/chapter_text_dissolve.gdshader",
	"res://vfx/chapter_text_doom_melt.gdshader",
	"res://vfx/chapter_text_glitch.gdshader",
	"res://vfx/chapter_text_hologram.gdshader",
	"res://vfx/chapter_text_light_sweep.gdshader",
	"res://vfx/chapter_text_liquid.gdshader",
	"res://vfx/chapter_text_neon.gdshader",
	"res://vfx/chapter_text_reveal.gdshader",
	"res://vfx/chapter_text_shatter.gdshader",
	"res://vfx/chapter_text_vhs.gdshader",
	"res://vfx/color_grading.gdshader",
	"res://vfx/colorblind.gdshader",
	"res://vfx/crt.gdshader",
	"res://vfx/death_screen_burn.gdshader",
	"res://vfx/death_screen_cave_tunnel.gdshader",
	"res://vfx/death_screen_lava.gdshader",
	"res://vfx/death_screen_tv_static.gdshader",
	"res://vfx/diorama_post_process.gdshader",
	"res://vfx/fadeeffects.gdshader",
	"res://vfx/gameboy.gdshader",
	"res://vfx/ghibli.gdshader",
	"res://vfx/glasses_condensation.gdshader",
	"res://vfx/glitch.gdshader",
	"res://vfx/halftone.gdshader",
	"res://vfx/handdrawn.gdshader",
	"res://vfx/harsh_contrast_transition.gdshader",
	"res://vfx/heal_vignette.gdshader",
	"res://vfx/high_contrast.gdshader",
	"res://vfx/horror_text_shader.gdshader",
	"res://vfx/kuwahara.gdshader",
	"res://vfx/magnifying_glass.gdshader",
	"res://vfx/mandelbrot.gdshader",
	"res://vfx/manga.gdshader",
	"res://vfx/moebius.gdshader",
	"res://vfx/nightvision.gdshader",
	"res://vfx/obra.gdshader",
	"res://vfx/old_photo.gdshader",
	"res://vfx/outline_hearts_adaptable.gdshader",
	"res://vfx/outline_shader_adaptable.gdshader",
	"res://vfx/pixelate.gdshader",
	"res://vfx/psychedelic.gdshader",
	"res://vfx/pulsing_border.gdshader",
	"res://vfx/refraction_tunnel.gdshader",
	"res://vfx/software.gdshader",
	"res://vfx/swirl.gdshader",
	"res://vfx/toon.gdshader",
	"res://vfx/vhs.gdshader",
	"res://vfx/water_effects_overlay.gdshader",
	"res://vfx/water_sheet_wipe.gdshader",
]

## Active Wave 2 fog shaders.
const FOG_SHADERS: Array[String] = [
	"res://vfx/box_clouds.gdshader",
	"res://weapons/smoke_grenade/smoke_grenade_cloud.gdshader",
]


## Verifies all 50 active Wave 2 spatial shaders load, have code, and report MODE_SPATIAL.
func test_spatial_shaders_load_and_mode() -> void:
	assert_eq(SPATIAL_SHADERS.size(), 50)
	for path: String in SPATIAL_SHADERS:
		var shader: Shader = _load_shader(path)
		assert_not_null(shader, "Failed to load spatial shader: %s" % path)
		if shader != null:
			assert_false(shader.code.is_empty(), "Empty shader code: %s" % path)
			assert_eq(shader.get_mode(), Shader.MODE_SPATIAL, "Expected MODE_SPATIAL for %s" % path)


## Verifies all 60 active Wave 2 canvas_item shaders load, have code, and report MODE_CANVAS_ITEM.
func test_canvas_item_shaders_load_and_mode() -> void:
	assert_eq(CANVAS_ITEM_SHADERS.size(), 60)
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


## Verifies both active Wave 2 fog shaders load, have code, and report MODE_FOG.
func test_fog_shaders_load_and_mode() -> void:
	assert_eq(FOG_SHADERS.size(), 2)
	for path: String in FOG_SHADERS:
		var shader: Shader = _load_shader(path)
		assert_not_null(shader, "Failed to load fog shader: %s" % path)
		if shader != null:
			assert_false(shader.code.is_empty(), "Empty shader code: %s" % path)
			assert_eq(shader.get_mode(), Shader.MODE_FOG, "Expected MODE_FOG for %s" % path)


## Verifies Wave 2 UI shader uniforms and chunk tint instance uniform contract.
func test_ui_and_chunk_uniform_contracts() -> void:
	_assert_uniforms(
		"res://ui/setting_row_hover.gdshader",
		[
			"rect_size",
			"mouse_pos",
			"hover_intensity",
			"tile_color",
			"core_glow_color",
			"corner_cut",
			"tile_size",
			"effect_radius",
			"ripple_freq",
			"ripple_speed",
		]
	)
	_assert_uniforms(
		"res://ui/ui_vignette.gdshader",
		[
			"color",
			"multiplier",
			"softness",
			"vignette_opacity",
		]
	)
	_assert_uniforms(
		"res://ui/ui_zoom_fisheye_blur.gdshader",
		[
			"distortion_amount",
			"blur_amount",
			"effect_strength",
		]
	)
	_assert_uniforms(
		"res://ui/wolf_vision.gdshader",
		[
			"effect_strength",
			"brightness_boost",
			"blur_amount",
		]
	)
	_assert_instance_uniforms(
		"res://world/chunks/test_chunk_tint.gdshader",
		[
			"instance uniform vec3 tint_color",
		]
	)


## Verifies Wave 2 fog shader uniform contracts for box_clouds and smoke_grenade_cloud.
func test_fog_shader_uniform_contracts() -> void:
	_assert_uniforms(
		"res://vfx/box_clouds.gdshader",
		[
			"noise_texture",
			"noise_scale",
			"cloud_coverage",
			"density_multiplier",
			"cloud_color",
			"shadow_color",
			"wind_direction",
			"wind_speed",
		]
	)
	_assert_uniforms(
		"res://weapons/smoke_grenade/smoke_grenade_cloud.gdshader",
		[
			"smoke_albedo",
			"emission_color",
			"base_density",
			"clump_scale",
			"clump_contrast",
			"wave_speed",
			"curl_advection_strength",
			"expansion_progress",
			"dissipation_alpha",
			"lobe_spheres",
			"active_ray_count",
			"ray_starts",
			"ray_ends",
			"active_actor_count",
			"actor_positions",
			"actor_velocities",
		]
	)


## Verifies Wave 2 post-process, accessibility, and death-screen canvas_item uniform contracts.
func test_vfx_post_process_and_death_screen_uniform_contracts() -> void:
	_assert_uniforms(
		"res://vfx/color_grading.gdshader",
		[
			"brightness",
			"contrast",
			"saturation",
			"temperature",
			"tint",
			"lift_color",
			"gamma_color",
			"gain_color",
			"lut_texture",
			"lut_intensity",
			"aberration_amount",
			"vignette_intensity",
			"grain_amount",
		]
	)
	_assert_uniforms(
		"res://vfx/colorblind.gdshader",
		[
			"mode",
			"show_split_lines",
			"split_line_color",
			"split_line_thickness",
		]
	)
	_assert_uniforms(
		"res://vfx/diorama_post_process.gdshader",
		[
			"filter_mode",
			"grain_amount",
		]
	)
	_assert_uniforms(
		"res://vfx/high_contrast.gdshader",
		[
			"dark_color",
			"light_color",
			"threshold",
		]
	)
	_assert_uniforms(
		"res://vfx/water_effects_overlay.gdshader",
		[
			"effect_mode",
			"drop_intensity",
			"wash_intensity",
			"clear_progress",
			"uneven_timing",
			"timing_randomness",
		]
	)
	_assert_uniforms(
		"res://vfx/water_sheet_wipe.gdshader",
		[
			"wipe_progress",
			"wash_intensity",
			"visibility",
			"distortion_strength",
			"meniscus_strength",
			"chromatic_aberration",
			"flow_speed",
			"ripple_scale",
			"specular_intensity",
			"water_tint",
		]
	)
	_assert_uniforms(
		"res://vfx/death_screen_burn.gdshader",
		[
			"threshold",
			"first_color",
			"second_color",
		]
	)
	_assert_uniforms(
		"res://vfx/death_screen_tv_static.gdshader",
		[
			"image_texture",
			"static_intensity",
			"scanline_count",
			"vignette_strength",
		]
	)


## Verifies Wave 2 spatial VFX regular and instance uniform contracts.
func test_vfx_spatial_and_instance_uniform_contracts() -> void:
	_assert_uniforms(
		"res://vfx/hex_shield.gdshader",
		[
			"base_color",
			"rim_color",
			"hit_color",
			"hex_density",
			"emission_energy",
			"corner_radius",
			"hit_ring_max_radius",
			"hit_ring_width",
			"scatter_distance",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/hex_shield.gdshader",
		[
			"instance uniform vec2 shield_size",
			"instance uniform vec2 canvas_size",
			"instance uniform vec3 hit_local_pos",
			"instance uniform float hit_progress",
			"instance uniform float shatter_progress",
		]
	)
	_assert_uniforms(
		"res://vfx/hex_shield_sphere.gdshader",
		[
			"base_interior_color",
			"base_edge_color",
			"hit_interior_color",
			"hit_edge_color",
			"rim_glow_color",
			"emission_energy",
			"fresnel_power",
			"refraction_strength",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/hex_shield_sphere.gdshader",
		[
			"instance uniform float hit_intensity",
			"instance uniform float damage_ratio",
			"instance uniform float opacity",
		]
	)
	_assert_uniforms(
		"res://vfx/pressurized_fire_jet/pressurized_fire_jet.gdshader",
		[
			"noise_tex",
			"depth_fade_distance",
			"displacement_strength",
			"warp_strength",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/pressurized_fire_jet/pressurized_fire_jet.gdshader",
		[
			"instance uniform float jet_speed",
			"instance uniform float core_heat",
			"instance uniform float axial_tile",
		]
	)
	_assert_uniforms(
		"res://vfx/smoke_billow.gdshader",
		[
			"core_fire_color",
			"hot_ember_color",
			"sunlit_smoke_color",
			"crevice_smoke_color",
			"displacement_strength",
			"proximity_fade_distance",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/smoke_billow.gdshader",
		[
			"instance uniform float expansion_scale",
			"instance uniform float heat_intensity",
			"instance uniform float erosion_offset",
		]
	)
	_assert_uniforms(
		"res://vfx/energy_wall.gdshader",
		[
			"energy_color",
			"noise_tex",
			"max_radius",
			"ring_freq",
			"warp_strength",
			"uv_border_fade",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/energy_wall.gdshader",
		[
			"instance uniform vec4 hit_slot_0",
			"instance uniform vec4 hit_slot_1",
			"instance uniform vec4 hit_slot_2",
			"instance uniform vec4 hit_slot_3",
		]
	)
	_assert_uniforms(
		"res://vfx/argon_lightning_strike.gdshader",
		[
			"bolt_color",
			"core_sharpness",
			"noise_scale",
			"noise_speed",
			"jitter_strength",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/argon_lightning_strike.gdshader",
		[
			"instance uniform float energy_multiplier",
			"instance uniform float strike_seed",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/aurora_borealis.gdshader",
		[
			"instance uniform vec4 tint_color",
			"instance uniform float intensity",
			"instance uniform float phase_offset",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/beam.gdshader",
		[
			"instance uniform float segment_length",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/explosion_shockwave.gdshader",
		[
			"instance uniform float explosion_progress",
			"instance uniform float distortion_strength",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/shockwave_refract.gdshader",
		[
			"instance uniform float shockwave_progress",
			"instance uniform float shockwave_scale",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/unlit_outline_material.gdshader",
		[
			"instance uniform bool is_billboard",
		]
	)
	_assert_instance_uniforms(
		"res://vfx/water_particle.gdshader",
		[
			"instance uniform vec4 leak_color",
			"instance uniform bool is_billboard",
		]
	)


## Verifies ShaderMaterial parameter round-trip on representative Wave 2 shaders.
func test_shader_material_parameter_binding() -> void:
	var vignette_shader: Shader = _load_shader("res://ui/ui_vignette.gdshader")
	assert_not_null(vignette_shader)
	if vignette_shader != null:
		var vignette_mat: ShaderMaterial = ShaderMaterial.new()
		vignette_mat.shader = vignette_shader
		vignette_mat.set_shader_parameter(&"vignette_opacity", 0.65)
		var opacity_raw: Variant = vignette_mat.get_shader_parameter(&"vignette_opacity")
		assert_true(opacity_raw is float)
		if opacity_raw is float:
			var opacity_val: float = opacity_raw
			assert_almost_eq(opacity_val, 0.65, 0.001)

	var colorblind_shader: Shader = _load_shader("res://vfx/colorblind.gdshader")
	assert_not_null(colorblind_shader)
	if colorblind_shader != null:
		var cb_mat: ShaderMaterial = ShaderMaterial.new()
		cb_mat.shader = colorblind_shader
		cb_mat.set_shader_parameter(&"mode", 2)
		cb_mat.set_shader_parameter(&"show_split_lines", true)
		var mode_raw: Variant = cb_mat.get_shader_parameter(&"mode")
		var split_raw: Variant = cb_mat.get_shader_parameter(&"show_split_lines")
		assert_true(mode_raw is int)
		assert_true(split_raw is bool)
		if mode_raw is int and split_raw is bool:
			var mode_val: int = mode_raw
			var split_val: bool = split_raw
			assert_eq(mode_val, 2)
			assert_true(split_val)

	var diorama_shader: Shader = _load_shader("res://vfx/diorama_post_process.gdshader")
	assert_not_null(diorama_shader)
	if diorama_shader != null:
		var diorama_mat: ShaderMaterial = ShaderMaterial.new()
		diorama_mat.shader = diorama_shader
		diorama_mat.set_shader_parameter(&"filter_mode", 1)
		diorama_mat.set_shader_parameter(&"grain_amount", 0.15)
		var filter_raw: Variant = diorama_mat.get_shader_parameter(&"filter_mode")
		var grain_raw: Variant = diorama_mat.get_shader_parameter(&"grain_amount")
		assert_true(filter_raw is int)
		assert_true(grain_raw is float)
		if filter_raw is int and grain_raw is float:
			var filter_val: int = filter_raw
			var grain_val: float = grain_raw
			assert_eq(filter_val, 1)
			assert_almost_eq(grain_val, 0.15, 0.001)

	var smoke_shader: Shader = _load_shader(
		"res://weapons/smoke_grenade/smoke_grenade_cloud.gdshader"
	)
	assert_not_null(smoke_shader)
	if smoke_shader != null:
		var smoke_mat: ShaderMaterial = ShaderMaterial.new()
		smoke_mat.shader = smoke_shader
		smoke_mat.set_shader_parameter(&"expansion_progress", 0.8)
		smoke_mat.set_shader_parameter(&"active_ray_count", 4)
		var exp_raw: Variant = smoke_mat.get_shader_parameter(&"expansion_progress")
		var ray_raw: Variant = smoke_mat.get_shader_parameter(&"active_ray_count")
		assert_true(exp_raw is float)
		assert_true(ray_raw is int)
		if exp_raw is float and ray_raw is int:
			var exp_val: float = exp_raw
			var ray_val: int = ray_raw
			assert_almost_eq(exp_val, 0.8, 0.001)
			assert_eq(ray_val, 4)


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


func _assert_instance_uniforms(path: String, expected_declarations: Array[String]) -> void:
	var shader: Shader = _load_shader(path)
	assert_not_null(shader, "Missing shader for instance uniform check: %s" % path)
	if shader == null:
		return
	for decl: String in expected_declarations:
		assert_true(
			shader.code.contains(decl), "Missing instance uniform '%s' in %s" % [decl, path]
		)
