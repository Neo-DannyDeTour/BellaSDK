shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 wave_color : source_color = vec4(0.5, 1.0, 1.0, 1.0);
uniform float hdr_intensity : hint_range(1.0, 20.0) = 5.0;
uniform vec2 scroll_velocity = vec2(0.0, 1.0);
uniform float streak_density : hint_range(5.0, 60.0) = 28.0;

varying float v_lifetime;
varying float v_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	v_lifetime = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.x * 9.13;
}

void fragment() {
	vec2 panned_uv = UV + scroll_velocity * v_lifetime;

	float streak_a = value_noise(vec2(panned_uv.x * streak_density, panned_uv.y * 3.0 + v_seed));
	float streak_b = value_noise(vec2(panned_uv.x * streak_density * 1.7 + 2.1, panned_uv.y * 4.0));
	float streaks = clamp(streak_a - streak_b * 0.65, 0.0, 1.0);
	streaks = smoothstep(0.15, 0.6, streaks);

	float edge_hide = sin(clamp(UV.y, 0.0, 1.0) * PI);
	edge_hide = pow(edge_hide, 1.5);

	float fade = 1.0 - v_lifetime;

	ALBEDO = wave_color.rgb * hdr_intensity;
	ALPHA = streaks * edge_hide * fade * COLOR.a;
}
