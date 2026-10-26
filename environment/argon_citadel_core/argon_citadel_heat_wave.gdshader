shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float heat_intensity : hint_range(0.0, 2.0) = 0.0;
uniform float immersion_weight : hint_range(0.0, 1.0) = 0.0;
uniform float plume_mask_weight : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_phase : hint_range(0.0, 1.0) = 0.0;
uniform vec2 core_screen_uv = vec2(0.5, 0.5);
uniform float plume_radius : hint_range(0.05, 1.0) = 0.44;
uniform float distortion_scale : hint_range(0.0, 0.05) = 0.013;
uniform float convection_speed : hint_range(0.1, 10.0) = 3.4;
uniform float chromatic_fringe : hint_range(0.0, 0.02) = 0.0045;
uniform vec4 orange_tint : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 cyan_tint : source_color = vec4(0.2, 0.88, 1.0, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.0001);
	vec2 delta = SCREEN_UV - core_screen_uv;
	delta.x *= aspect;
	// Stretch mask upward in screen space (-Y) to form a rising thermal convection plume.
	delta.y *= (delta.y < 0.0) ? 0.52 : 1.15;

	float radial_plume = smoothstep(plume_radius, plume_radius * 0.12, length(delta));
	radial_plume *= plume_mask_weight;

	float spatial_mask = clamp(max(radial_plume, immersion_weight), 0.0, 1.0);
	float active_heat = spatial_mask * heat_intensity;

	vec2 uv_scaled = vec2(SCREEN_UV.x * aspect, SCREEN_UV.y);
	float t = TIME * convection_speed;

	// Dual-octave upward convection turbulence (+t on Y moves waves toward screen top).
	vec2 p1 = uv_scaled * vec2(14.0, 9.0) + vec2(sin(t * 0.35) * 0.4, t);
	vec2 p2 = uv_scaled * vec2(29.0, 21.0) + vec2(-cos(t * 0.6) * 0.3, t * 1.65);

	float n_x = value_noise(p1) * 0.65 + value_noise(p2) * 0.35;
	float n_y = value_noise(p1 + vec2(5.2, 1.3)) * 0.6 + value_noise(p2 + vec2(2.7, 8.1)) * 0.4;

	vec2 offset = vec2(n_x * 0.65, n_y * 1.35) * distortion_scale * active_heat;
	vec2 base_uv = clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999));

	float fringe = chromatic_fringe * active_heat;
	vec2 r_uv = clamp(base_uv + vec2(fringe, -fringe * 0.5), vec2(0.001), vec2(0.999));
	vec2 b_uv = clamp(base_uv - vec2(fringe, -fringe * 0.5), vec2(0.001), vec2(0.999));

	float blur_lod = clamp(active_heat * 0.55, 0.0, 1.2);
	float col_r = textureLod(screen_texture, r_uv, blur_lod).r;
	float col_g = textureLod(screen_texture, base_uv, blur_lod).g;
	float col_b = textureLod(screen_texture, b_uv, blur_lod).b;
	vec3 refracted = vec3(col_r, col_g, col_b);

	float cyan_weight = smoothstep(0.45, 0.65, pulse_phase) * (1.0 - smoothstep(0.75, 0.95, pulse_phase));
	vec3 thermal_color = mix(orange_tint.rgb, cyan_tint.rgb, cyan_weight);
	refracted += thermal_color * (active_heat * 0.045 * max(n_y, 0.0));

	COLOR = vec4(refracted, 1.0);
}
