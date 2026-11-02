shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(0.82, 0.77, 0.68, 0.55);
uniform float drift_speed : hint_range(0.0, 5.0) = 0.8;
uniform float proximity_fade_distance : hint_range(0.01, 2.0) = 0.3;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying flat float v_seed;
varying float v_life_alpha;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_seed = float(INSTANCE_ID % 1024) * 0.293 + INSTANCE_CUSTOM.x * 6.28318;
	float age = INSTANCE_CUSTOM.y;
	v_life_alpha = smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(0.75, 1.0, age));

	float t = TIME * drift_speed + v_seed;
	float ca = cos(t * 0.4);
	float sa = sin(t * 0.4);
	mat2 rot = mat2(vec2(ca, sa), vec2(-sa, ca));

	// Irregular aspect ratio per mote (lint/fiber/speck variation)
	float aspect = 0.55 + 0.75 * fract(v_seed * 4.13);
	vec2 local_xy = rot * (VERTEX.xy * vec2(1.0, aspect));

	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	vec3 world_pos = world_origin + cam_right * local_xy.x + cam_up * local_xy.y;
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	vec2 seed_vec = vec2(v_seed * 5.7, v_seed * 2.3);

	// Domain-warped organic speck shape
	vec2 warp = vec2(
		value_noise(uv * 2.4 + seed_vec) - 0.5,
		value_noise(uv * 2.4 - seed_vec + vec2(4.1, 1.9)) - 0.5
	);
	vec2 warped_uv = uv + warp * 0.55;
	float dist = length(warped_uv);

	float n_fine = value_noise(warped_uv * 5.5 + seed_vec);
	float mote_mask = (1.0 - smoothstep(0.2, 0.78, dist)) * (0.6 + 0.4 * n_fine);

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float pixel_depth = -upos.z / upos.w;
	float prox_fade = clamp((pixel_depth - (-VERTEX.z)) / proximity_fade_distance, 0.0, 1.0);

	// Mie-like edge Rim/Backlight response
	float view_dot = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - view_dot, 1.5) * 0.35 + 0.65;

	float final_alpha = mote_mask * albedo_color.a * COLOR.a * v_life_alpha * prox_fade * rim;
	if (final_alpha < 0.01) {
		discard;
	}

	ALBEDO = albedo_color.rgb * COLOR.rgb;
	ALPHA = final_alpha;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = vec3(0.85, 0.8, 0.7);
}
