shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(0.95, 0.97, 1.0, 0.9);
uniform float flutter_speed : hint_range(0.0, 10.0) = 3.2;
uniform float flutter_amplitude : hint_range(0.0, 0.2) = 0.035;
uniform float proximity_fade_distance : hint_range(0.01, 2.0) = 0.25;
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
	v_seed = float(INSTANCE_ID % 1024) * 0.137 + INSTANCE_CUSTOM.x * 6.28318;
	float age = INSTANCE_CUSTOM.y;
	v_life_alpha = smoothstep(0.0, 0.1, age) * (1.0 - smoothstep(0.8, 1.0, age));

	float t = TIME * flutter_speed + v_seed;
	float angle = t * 0.6 + sin(t) * 0.4;
	float ca = cos(angle);
	float sa = sin(angle);
	mat2 rot = mat2(vec2(ca, sa), vec2(-sa, ca));

	vec2 local_xy = rot * VERTEX.xy;
	// Anisotropic tumble perspective squash so flakes look tilted in 3D
	local_xy.y *= 0.65 + 0.35 * sin(t * 1.3);

	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	vec3 flutter_offset = vec3(
		sin(t) * flutter_amplitude,
		cos(t * 1.7) * flutter_amplitude * 0.4,
		cos(t * 0.85) * flutter_amplitude
	);

	vec3 world_pos = world_origin + flutter_offset + cam_right * local_xy.x + cam_up * local_xy.y;
	VERTEX = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float theta = atan(uv.y, uv.x);

	vec2 seed_offset = vec2(v_seed * 3.1, v_seed * 7.3);
	float n1 = value_noise(uv * 3.5 + seed_offset);
	float n2 = value_noise(uv * 8.0 - seed_offset * 1.7);

	// 6-fold hexagonal crystal harmonic + 3-fold asymmetry + noise clump perturbation
	float hex_arm = cos(theta * 6.0 + n1 * 2.2) * 0.16;
	float sub_arm = cos(theta * 3.0 + v_seed) * 0.09;
	float radius_limit = 0.52 + hex_arm + sub_arm + (n1 - 0.5) * 0.25 + (n2 - 0.5) * 0.12;

	float flake_mask = 1.0 - smoothstep(radius_limit - 0.22, radius_limit, r);
	flake_mask *= 0.75 + 0.25 * n2;

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float pixel_depth = -upos.z / upos.w;
	float prox_fade = clamp((pixel_depth - (-VERTEX.z)) / proximity_fade_distance, 0.0, 1.0);

	float final_alpha = flake_mask * albedo_color.a * COLOR.a * v_life_alpha * prox_fade;
	if (final_alpha < 0.01) {
		discard;
	}

	ALBEDO = albedo_color.rgb * COLOR.rgb;
	ALPHA = final_alpha;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(0.75, 0.8, 0.9);
}
