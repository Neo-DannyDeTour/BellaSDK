shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

instance uniform float jet_speed : hint_range(0.0, 30.0) = 18.0;
instance uniform float core_heat : hint_range(0.0, 1.0) = 1.0;
instance uniform float axial_tile : hint_range(0.25, 25.0) = 3.0;

uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float depth_fade_distance : hint_range(0.01, 2.0) = 0.25;
uniform float displacement_strength : hint_range(0.0, 1.0) = 0.18;
uniform float warp_strength : hint_range(0.0, 1.0) = 0.28;

void vertex() {
	float axial_envelope = smoothstep(0.0, 0.14, UV.y) * (0.35 + 0.65 * UV.y);
	float tiled_y = UV.y * axial_tile;
	vec2 disp_uv1 = vec2(UV.x * 2.0, tiled_y * 0.55 - TIME * (jet_speed * 0.45));
	vec2 disp_uv2 = vec2(UV.x * 4.0 + 0.41, tiled_y * 1.15 - TIME * (jet_speed * 0.75));
	float n1 = textureLod(noise_tex, disp_uv1, 0.0).r * 2.0 - 1.0;
	float n2 = textureLod(noise_tex, disp_uv2, 0.0).r * 2.0 - 1.0;
	float wave = n1 * 0.65 + n2 * 0.35;

	// High-frequency acoustic flutter and supersonic Mach pinch under high pressure
	float flutter = sin(TIME * 48.0 - tiled_y * 12.0) * 0.06 * core_heat;
	float pressure_pinch = mix(1.35, 0.72, core_heat);
	VERTEX += NORMAL * ((wave * displacement_strength * pressure_pinch + flutter) * axial_envelope);
}

void fragment() {
	float tiled_y = UV.y * axial_tile;

	// 3-octave domain-warped FBM for Kelvin-Helmholtz shear vortices
	vec2 uv1 = vec2(UV.x * 1.5, tiled_y * 0.55 - TIME * (jet_speed * 0.55));
	float n1 = texture(noise_tex, uv1).r;

	float shear = mix(0.25, 1.0, UV.y) * warp_strength;
	vec2 warp_offset = vec2(n1 - 0.5, (n1 - 0.5) * 1.35) * shear;

	vec2 uv2 = vec2(UV.x * 3.0 + 0.37, tiled_y * 1.15 - TIME * (jet_speed * 0.85)) + warp_offset;
	float n2 = texture(noise_tex, uv2).r;

	vec2 uv3 = (
		vec2(UV.x * 6.0 - 0.19, tiled_y * 2.3 - TIME * (jet_speed * 1.25))
		+ warp_offset * 1.6
		+ vec2(n2 - 0.5) * (shear * 0.6)
	);
	float n3 = texture(noise_tex, uv3).r;

	float fbm = n1 * 0.50 + n2 * 0.32 + n3 * 0.18;
	float fine_detail = n2 * 0.6 + n3 * 0.4;

	// Standing supersonic Mach shock diamonds near nozzle orifice
	float acoustic_flicker = 0.94 + 0.06 * sin(TIME * 53.0) * cos(TIME * 31.0);
	float mach_phase = tiled_y * 16.0 - sin(TIME * 38.0) * 0.25;
	float mach_ring = pow(clamp(0.5 + 0.5 * cos(mach_phase), 0.0, 1.0), 2.2);
	float core_mask = smoothstep(0.65, 0.0, UV.y) * core_heat;
	float shock_diamond = mix(1.0, 0.78 + 0.55 * mach_ring, core_mask);

	// Normal-perturbed volumetric optical depth
	float ndotv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float optical_depth = clamp(ndotv + (fine_detail - 0.5) * 0.38 * UV.y, 0.0, 1.0);
	float cylinder_profile = pow(optical_depth, mix(1.15, 1.75, UV.y));
	float core_beam = pow(ndotv, 3.2) * core_mask;

	// Axial envelope and turbulent flame-tongue tip erosion
	float base_gradient = pow(clamp(1.0 - UV.y, 0.0, 1.0), 0.75);
	float orifice_fade = smoothstep(0.0, 0.025, UV.y);
	float erosion_edge = mix(0.12, 0.78, UV.y * UV.y);
	float flame_mask = smoothstep(
		erosion_edge,
		erosion_edge + 0.28,
		fbm * base_gradient * 1.55 + core_beam * 0.45
	);
	float intensity = flame_mask * cylinder_profile * shock_diamond * orifice_fade * acoustic_flicker;

	// Planckian blackbody ramp: dark ember -> red -> orange -> white-yellow -> ionized cyan-white
	float temp = clamp(
		intensity * (0.95 + core_heat * 0.65)
		+ core_beam * (0.75 + 0.45 * mach_ring)
		+ base_gradient * core_heat * 0.35,
		0.0,
		1.8
	);
	vec3 col_ember = vec3(0.35, 0.02, 0.005);
	vec3 col_outer = vec3(0.92, 0.14, 0.015);
	vec3 col_mid = vec3(1.0, 0.52, 0.06);
	vec3 col_hot = vec3(1.0, 0.94, 0.68);
	vec3 col_mach = mix(vec3(1.0, 0.96, 0.82), vec3(0.42, 0.78, 1.0), core_heat);

	vec3 fire_color = mix(col_ember, col_outer, smoothstep(0.02, 0.28, temp));
	fire_color = mix(fire_color, col_mid, smoothstep(0.25, 0.65, temp));
	fire_color = mix(fire_color, col_hot, smoothstep(0.60, 1.05, temp));
	fire_color = mix(fire_color, col_mach, smoothstep(1.0, 1.55, temp));

	// Soft depth intersection against nozzle wall and colliding geometry
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	view_pos.xyz /= view_pos.w;
	float depth_diff = abs(VERTEX.z - view_pos.z);
	float depth_fade = clamp(depth_diff / depth_fade_distance, 0.0, 1.0);

	float hdr_boost = (1.8 + core_heat * 2.8) * (1.0 + core_beam * 0.6);
	ALBEDO = fire_color * hdr_boost;
	ALPHA = clamp(intensity * depth_fade, 0.0, 1.0);
}
