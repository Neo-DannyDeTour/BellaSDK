shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.15, 0.55, 1.0, 1.0);
uniform float hdr_core_intensity : hint_range(1.0, 30.0) = 12.0;
uniform float hdr_edge_intensity : hint_range(0.5, 20.0) = 4.5;
uniform float jaggedness : hint_range(1.0, 40.0) = 16.0;
uniform float sway_amplitude : hint_range(0.0, 0.45) = 0.18;
uniform float scroll_speed : hint_range(-20.0, 20.0) = 8.0;
uniform float beam_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float seed_offset = 0.0;

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

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.1;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float t = TIME * scroll_speed + seed_offset;
	float n1 = fbm(vec2(UV.y * jaggedness - t, seed_offset)) - 0.5;
	float n2 = fbm(vec2(UV.y * jaggedness * 2.4 + t * 1.3, seed_offset + 5.7)) - 0.5;
	float envelope = sin(UV.y * PI);
	float offset = (n1 + n2 * 0.45) * sway_amplitude * max(envelope, 0.15);

	float dist = abs(UV.x - 0.5 + offset);
	float bolt_core = smoothstep(0.11, 0.01, dist);
	float bolt_glow = smoothstep(0.32, 0.02, dist);

	float tip_fade = smoothstep(0.0, 0.04, UV.y) * smoothstep(1.0, 0.96, UV.y);
	float flicker = 0.8 + 0.2 * sin(TIME * 48.0 + seed_offset);

	vec3 rgb = edge_color.rgb * hdr_edge_intensity * bolt_glow
		+ core_color.rgb * hdr_core_intensity * bolt_core;
	float alpha = clamp(bolt_glow, 0.0, 1.0) * tip_fade * beam_alpha * flicker;

	ALBEDO = rgb;
	ALPHA = alpha;
}
