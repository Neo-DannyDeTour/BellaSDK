shader_type canvas_item;

uniform vec4 fire_core_color : source_color = vec4(1.0, 0.92, 0.35, 1.0);
uniform vec4 fire_outer_color : source_color = vec4(1.0, 0.22, 0.02, 1.0);
uniform float outline_width : hint_range(1.0, 12.0) = 5.0;
uniform float fire_speed : hint_range(0.5, 20.0) = 8.0;
uniform float glow_intensity : hint_range(0.5, 5.0) = 2.2;

float hash2d(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2d(i);
	float b = hash2d(i + vec2(1.0, 0.0));
	float c = hash2d(i + vec2(0.0, 1.0));
	float d = hash2d(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * outline_width;

	float n1 = noise2d(UV * 12.0 + vec2(0.0, TIME * fire_speed));
	float n2 = noise2d(UV * 24.0 - vec2(TIME * fire_speed * 0.4, -TIME * fire_speed * 1.4));
	float fire_noise = mix(n1, n2, 0.5);

	vec2 flame_warp = vec2((fire_noise - 0.5) * px.x * 1.6, -fire_noise * px.y * 2.2);
	vec2 sample_uv = UV + flame_warp;

	float max_neighbor = 0.0;
	float sum_neighbor = 0.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.78539816;
		vec2 dir = vec2(cos(angle), sin(angle));
		float a_near = texture(TEXTURE, sample_uv + dir * (px * 0.55)).a;
		float a_far = texture(TEXTURE, sample_uv + dir * px).a;
		max_neighbor = max(max_neighbor, max(a_near, a_far));
		sum_neighbor += (a_near + a_far) * 0.5;
	}
	float rim_factor = clamp(sum_neighbor / 8.0, 0.0, 1.0);
	float outline_mask = clamp(max_neighbor - base.a, 0.0, 1.0);

	float flicker = 0.75 + 0.25 * sin(TIME * fire_speed * 2.0 + UV.y * 10.0);
	float flame_alpha = outline_mask * smoothstep(0.12, 0.85, rim_factor * 0.7 + fire_noise * 0.65);

	vec3 fire_col = mix(fire_outer_color.rgb, fire_core_color.rgb, clamp(rim_factor * 1.15 * flicker, 0.0, 1.0)) * glow_intensity;
	vec3 final_rgb = mix(fire_col, base.rgb, base.a);
	float final_alpha = max(base.a, flame_alpha) * COLOR.a;

	COLOR = vec4(final_rgb, final_alpha);
}
