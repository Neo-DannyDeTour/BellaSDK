shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 bolt_color : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float core_sharpness : hint_range(1.0, 32.0) = 10.0;
uniform float noise_scale : hint_range(1.0, 50.0) = 18.0;
uniform float noise_speed : hint_range(0.0, 50.0) = 24.0;
uniform float jitter_strength : hint_range(0.0, 0.45) = 0.22;

instance uniform float energy_multiplier = 12.0;
instance uniform float strike_seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	float n = fbm(vec2(UV.y * noise_scale + strike_seed * 13.7, TIME * noise_speed)) * 2.0 - 1.0;
	float center_dist = abs((UV.x - 0.5) * 2.0 + n * jitter_strength);

	float core = exp(-center_dist * core_sharpness);
	float halo = smoothstep(1.0, 0.0, center_dist);

	// COLOR.r carries branch intensity (1.0 = trunk, <1.0 = child branches).
	float branch_mask = COLOR.r;
	float tip_fade = smoothstep(1.0, 0.82, UV.y);

	vec3 final_rgb = mix(bolt_color.rgb * halo, vec3(1.0), core);
	ALBEDO = final_rgb * energy_multiplier * branch_mask * tip_fade;
	ALPHA = clamp((core + halo * 0.5) * tip_fade, 0.0, 1.0);
}
