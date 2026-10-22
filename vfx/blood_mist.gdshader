shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec4 mist_core_color : source_color = vec4(0.28, 0.01, 0.015, 0.72);
uniform vec4 mist_edge_color : source_color = vec4(0.52, 0.025, 0.03, 0.38);
uniform float proximity_fade_distance : hint_range(0.05, 2.0) = 0.35;

varying float v_seed;
varying float v_life;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	v += 0.5000 * value_noise(p);
	p *= 2.02;
	v += 0.2500 * value_noise(p);
	p *= 2.03;
	v += 0.1250 * value_noise(p);
	return v;
}

void vertex() {
	v_seed = INSTANCE_CUSTOM.x;
	v_life = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);

	float angle = v_seed * 6.2831853 + v_life * 0.65;
	float s = sin(angle);
	float c = cos(angle);

	// Expand cloud radius smoothly as aerosol disperses over lifetime.
	float expansion = mix(0.65, 1.55, sqrt(v_life));
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	) * expansion;

	vec3 rot_x = vec3(c, s, 0.0) * scale.x;
	vec3 rot_y = vec3(-s, c, 0.0) * scale.y;
	vec3 rot_z = vec3(0.0, 0.0, scale.z);

	MODELVIEW_MATRIX = mat4(
		vec4(rot_x, 0.0),
		vec4(rot_y, 0.0),
		vec4(rot_z, 0.0),
		VIEW_MATRIX * MODEL_MATRIX[3]
	);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float dist = length(centered_uv);
	float radial_mask = smoothstep(1.0, 0.18, dist);

	vec2 noise_coord = UV * 3.2 + vec2(v_seed * 11.7, TIME * 0.18);
	float cloud = fbm(noise_coord);
	float density = smoothstep(0.22 + v_life * 0.28, 0.78, cloud * radial_mask);

	// Soft depth proximity fade against environment geometry.
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_z = upos.z / upos.w;
	float depth_diff = clamp((VERTEX.z - scene_z) / proximity_fade_distance, 0.0, 1.0);

	float life_fade = sin(clamp(1.0 - v_life, 0.0, 1.0) * 1.5707963);
	ALBEDO = mix(mist_core_color.rgb, mist_edge_color.rgb, cloud) * COLOR.rgb;
	ROUGHNESS = 0.88;
	SPECULAR = 0.15;
	ALPHA = density * mist_core_color.a * life_fade * depth_diff * COLOR.a;
}
