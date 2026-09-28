shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_never, depth_test_disabled;

group_uniforms quality_and_performance;
uniform int raymarch_steps : hint_range(4, 24) = 14;
uniform bool sample_jitter = true;

group_uniforms general_parameters;
uniform sampler3D sample_noise : repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture;
uniform float time_scale = 0.35;
uniform float noise_scale = 0.55;
uniform float noise_threshold = 0.38;

group_uniforms shape_composition;
uniform float fire_height = 2.45;
uniform float fire_width = 2.25;
uniform vec3 box_center = vec3(0.0, 0.0, 0.0);
uniform float sharpness_cutoff : hint_range(0.1, 10.0) = 2.2;

group_uniforms wind_and_forces;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_strength : hint_range(0.0, 5.0) = 0.5;

group_uniforms visual_composition;
uniform float emission_strength = 3.2;
uniform vec3 color_core = vec3(1.0, 0.95, 0.75);
uniform vec3 color_mid = vec3(1.0, 0.45, 0.05);
uniform vec3 color_outer = vec3(0.75, 0.08, 0.01);
uniform vec3 color_smoke = vec3(0.08, 0.06, 0.06);

varying vec3 world_position;
varying vec3 world_camera;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.3, 0.7));
	p = p * dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float flame_sdf(vec3 p, vec3 base_pos) {
	vec3 local_p = p - (base_pos + box_center);
	float h_ratio = local_p.y / fire_height;

	if (h_ratio < -0.05 || h_ratio > 1.25) {
		return 10.0;
	}

	float wind_curve = pow(clamp(h_ratio, 0.0, 1.0), 1.5);
	vec3 bent_pos = local_p - wind_direction * (wind_strength * wind_curve);

	float taper = pow(clamp(1.0 - h_ratio, 0.0, 1.0), 0.75) * smoothstep(-0.05, 0.15, h_ratio);
	float target_radius = (fire_width * 0.5) * taper;

	float radial_dist = length(bent_pos.xz);
	float dist = radial_dist - target_radius;

	dist = max(dist, -bent_pos.y);
	dist = max(dist, (bent_pos.y - fire_height) * 0.8);

	vec3 uv1 = bent_pos * noise_scale + vec3(0.0, -TIME * time_scale * 1.8, 0.0);
	vec3 uv2 = bent_pos * (noise_scale * 2.2) + vec3(0.0, -TIME * time_scale * 3.4, 0.0);
	float n1 = texture(sample_noise, fract(uv1)).r;
	float n2 = texture(sample_noise, fract(uv2)).r;
	float combined_noise = mix(n1, n2, 0.4);

	dist += (combined_noise - noise_threshold) * mix(0.25, 0.7, clamp(h_ratio, 0.0, 1.0));
	return dist;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_camera = (inverse(VIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 ray_origin = world_camera;
	vec3 ray_direction = normalize(world_position - world_camera);

	vec3 base_world = NODE_POSITION_WORLD + box_center;
	float max_reach = max(fire_width, fire_height) + wind_strength;
	vec3 wind_offset = wind_direction * wind_strength;
	vec3 box_min_world = base_world + vec3(-max_reach * 0.7, -0.2, -max_reach * 0.7)
			+ min(wind_offset, vec3(0.0));
	vec3 box_max_world = base_world + vec3(max_reach * 0.7, fire_height * 1.3, max_reach * 0.7)
			+ max(wind_offset, vec3(0.0));

	vec3 safe_dir = sign(ray_direction) * max(abs(ray_direction), vec3(0.00001));
	vec3 inv_dir = 1.0 / safe_dir;
	vec3 t0 = (box_min_world - ray_origin) * inv_dir;
	vec3 t1 = (box_max_world - ray_origin) * inv_dir;
	vec3 t_min = min(t0, t1);
	vec3 t_max = max(t0, t1);

	float t_enter = max(0.0, max(t_min.x, max(t_min.y, t_min.z)));
	float t_exit = min(t_max.x, min(t_max.y, t_max.z));

	float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	float scene_depth_dist = 100000.0;
	if (depth_raw > 0.00001) {
		vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
		view_pos.xyz /= view_pos.w;
		vec3 scene_world_pos = (inverse(VIEW_MATRIX) * vec4(view_pos.xyz, 1.0)).xyz;
		scene_depth_dist = length(scene_world_pos - ray_origin);
	}

	t_exit = min(t_exit, scene_depth_dist);

	if (t_enter >= t_exit) {
		discard;
	}

	float march_range = t_exit - t_enter;
	if (march_range <= 0.0001) {
		discard;
	}

	float step_size = march_range / float(raymarch_steps);
	float jitter_offset = 0.0;
	if (sample_jitter) {
		jitter_offset = hash(ray_origin + ray_direction * TIME) * step_size * 0.5;
	}

	float total_distance = t_enter + jitter_offset;
	vec3 final_color = vec3(0.0);
	float current_alpha = 0.0;

	for (int i = 0; i < raymarch_steps; i++) {
		if (total_distance >= t_exit) {
			break;
		}

		vec3 current_pos = ray_origin + ray_direction * total_distance;
		float dist = flame_sdf(current_pos, NODE_POSITION_WORLD);

		if (dist < 0.0) {
			float density = clamp(-dist / sharpness_cutoff, 0.0, 1.0);
			float h_norm = clamp((current_pos.y - base_world.y) / fire_height, 0.0, 1.0);

			vec3 col = mix(color_outer, color_mid, density);
			col = mix(col, color_core, smoothstep(0.4, 0.95, density) * (1.0 - h_norm * 0.85));
			col = mix(col, color_smoke, smoothstep(0.65, 1.0, h_norm));

			float alpha_step = 1.0 - exp(-density * step_size * 20.0);
			final_color += col * alpha_step * (1.0 - current_alpha);
			current_alpha += alpha_step * (1.0 - current_alpha);

			if (current_alpha > 0.98) {
				break;
			}
		}

		total_distance += step_size;
	}

	if (current_alpha <= 0.005) {
		discard;
	}

	ALPHA = clamp(current_alpha, 0.0, 1.0);
	ALBEDO = final_color * emission_strength;
}
