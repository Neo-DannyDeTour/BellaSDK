shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.28, 0.19, 0.31, 1.0);
uniform vec4 tip_color : source_color = vec4(0.58, 0.16, 0.24, 1.0);
uniform vec4 wart_color : source_color = vec4(0.42, 0.36, 0.18, 1.0);
uniform float wave_amplitude : hint_range(0.0, 0.6) = 0.22;
uniform float wart_scale : hint_range(1.0, 30.0) = 14.0;
uniform float roughness_base : hint_range(0.05, 1.0) = 0.24;

instance uniform float wave_phase = 0.0;
instance uniform float move_intensity : hint_range(0.0, 1.0) = 0.0;
instance uniform float leap_phase : hint_range(-1.0, 1.0) = 0.0;
instance uniform float tentacle_seed = 0.0;

varying float v_tip_factor;
varying float v_wart_mask;

float hash_noise(vec3 p) {
	vec3 p3 = fract(p * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	float is_tentacle = step(0.001, tentacle_seed);
	float dist_from_root = clamp(0.5 - VERTEX.y, 0.0, 1.0) * is_tentacle;
	v_tip_factor = dist_from_root;

	// Sync tentacle phase offsets as velocity increases so fast motion strokes in unison.
	float desync_offset = tentacle_seed * 6.2831853;
	float synced_offset = tentacle_seed * 0.65;
	float active_offset = mix(desync_offset, synced_offset, move_intensity);
	float phase = wave_phase + active_offset - (dist_from_root * 3.4);

	float bend_weight = dist_from_root * dist_from_root;
	float dynamic_amp = wave_amplitude * mix(0.65, 1.45, move_intensity);

	float wave_x = sin(phase) * dynamic_amp * bend_weight;
	float wave_z = cos(phase * 0.85 + tentacle_seed) * dynamic_amp * 0.7 * bend_weight;

	// Negative leap_phase splays tentacles wide on crouch; positive sweeps them into a cone.
	float splay_push = -leap_phase * 0.38 * bend_weight;
	vec2 radial_dir = normalize(vec2(VERTEX.x + 0.0001, VERTEX.z + 0.0001));

	VERTEX.x += (wave_x + radial_dir.x * splay_push) * is_tentacle;
	VERTEX.z += (wave_z + radial_dir.y * splay_push) * is_tentacle;

	// Mantle organic breathing and ugly lumpy wart deformation.
	float is_mantle = 1.0 - is_tentacle;
	float mantle_pulse = sin(wave_phase * 0.6 + VERTEX.y * 4.0) * 0.045 * is_mantle;
	float wart_bump = hash_noise(VERTEX * wart_scale + vec3(tentacle_seed));
	v_wart_mask = smoothstep(0.62, 0.92, wart_bump);

	VERTEX += NORMAL * (mantle_pulse + v_wart_mask * 0.035);
}

void fragment() {
	vec3 skin_col = mix(base_color.rgb, tip_color.rgb, v_tip_factor);
	ALBEDO = mix(skin_col, wart_color.rgb, v_wart_mask * 0.55);
	ROUGHNESS = clamp(roughness_base - (v_tip_factor * 0.08) + (v_wart_mask * 0.15), 0.08, 0.95);
	SPECULAR = 0.75;
}
