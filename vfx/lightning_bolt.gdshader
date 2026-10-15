shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 edge_color : source_color = vec4(0.05, 0.1, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float hdr_edge_intensity : hint_range(0.5, 20.0) = 4.0;
uniform float hdr_core_intensity : hint_range(1.0, 30.0) = 10.0;
uniform vec2 scroll_speed = vec2(0.0, -1.5);
uniform float jaggedness : hint_range(1.0, 30.0) = 12.0;
uniform float sway_amplitude : hint_range(0.0, 0.4) = 0.14;
uniform float max_dissolve : hint_range(0.1, 0.95) = 0.7;
uniform float upper_edge : hint_range(0.1, 1.0) = 0.75;

varying float v_lifetime;
varying float v_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.15;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_lifetime = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.x * 17.31;
}

void fragment() {
	vec2 scrolled_uv = UV + scroll_speed * TIME + vec2(v_seed, 0.0);

	float n1 = fbm(vec2(scrolled_uv.y * jaggedness, v_seed)) - 0.5;
	float n2 = fbm(vec2(scrolled_uv.y * jaggedness * 2.7, v_seed + 4.2)) - 0.5;
	float envelope = sin(UV.y * PI);
	float offset = (n1 + n2 * 0.45) * sway_amplitude * max(envelope, 0.25);

	float dist = abs(UV.x - 0.5 + offset);
	float bolt_tex = clamp(1.0 - (dist / 0.22), 0.0, 1.0);

	float edge0 = mix(0.0, max_dissolve, v_lifetime);
	float mask = smoothstep(edge0, upper_edge, bolt_tex);

	float vertical_tips = smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.95, UV.y);
	mask *= vertical_tips;

	vec3 col_low = edge_color.rgb * hdr_edge_intensity;
	vec3 col_high = core_color.rgb * hdr_core_intensity;
	ALBEDO = mix(col_low, col_high, mask);
	ALPHA = mask * COLOR.a;
}
