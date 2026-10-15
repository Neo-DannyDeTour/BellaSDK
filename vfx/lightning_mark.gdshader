shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 mark_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float hdr_intensity : hint_range(1.0, 20.0) = 5.0;
uniform float spoke_frequency : hint_range(2.0, 24.0) = 10.0;

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
	v_seed = INSTANCE_CUSTOM.x * 13.7;
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float r = length(centered);
	float angle = atan(centered.y, centered.x);

	float n = value_noise(vec2(angle * spoke_frequency, r * 4.0 + v_seed));
	float warped_r = r + (n - 0.5) * 0.35;

	float radial_mask = smoothstep(0.85, 0.05, warped_r);
	float fade = 1.0 - v_lifetime;

	ALBEDO = mark_color.rgb * hdr_intensity;
	ALPHA = radial_mask * fade * fade * COLOR.a;
}
