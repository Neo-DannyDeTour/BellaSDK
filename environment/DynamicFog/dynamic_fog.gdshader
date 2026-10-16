shader_type fog;

uniform vec4 base_color : source_color = vec4(0.72, 0.78, 0.84, 1.0);
uniform vec4 emission_color : source_color = vec4(0.06, 0.09, 0.12, 1.0);
uniform float base_density : hint_range(0.0, 5.0) = 1.15;
uniform float height_falloff : hint_range(0.0, 10.0) = 3.2;
uniform float ground_hugging_height : hint_range(0.0, 1.0) = 0.28;
uniform float edge_fade : hint_range(0.01, 0.5) = 0.12;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.38;
uniform float wave_scale : hint_range(0.05, 3.0) = 0.35;
uniform float clump_scale : hint_range(0.1, 4.0) = 0.75;
uniform float clump_contrast : hint_range(0.2, 3.0) = 1.45;
uniform float curl_advection_strength : hint_range(0.0, 4.0) = 1.35;

uniform int active_ray_count = 0;
uniform vec4 ray_starts[8];
uniform vec4 ray_ends[8];

uniform int active_actor_count = 0;
uniform vec4 actor_positions[8];
uniform vec4 actor_velocities[8];

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float amp = 0.55;
	vec3 shift = vec3(13.7, 29.3, 7.1);
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p = p * 2.07 + shift;
		amp *= 0.45;
	}
	return v;
}

// Tetrahedral finite-difference approximation for divergence-free 3D curl swirl.
vec3 sample_curl(vec3 p, float t) {
	const float eps = 0.18;
	vec3 q = p + vec3(t * 0.22, -t * 0.15, t * 0.19);
	float n1 = value_noise(q + vec3(eps, 0.0, 0.0)) - value_noise(q - vec3(eps, 0.0, 0.0));
	float n2 = value_noise(q + vec3(0.0, eps, 0.0)) - value_noise(q - vec3(0.0, eps, 0.0));
	float n3 = value_noise(q + vec3(0.0, 0.0, eps)) - value_noise(q - vec3(0.0, 0.0, eps));
	vec3 grad_a = vec3(n1, n2, n3) / (2.0 * eps);

	vec3 q2 = q + vec3(31.4, 47.2, 19.8);
	float m1 = value_noise(q2 + vec3(eps, 0.0, 0.0)) - value_noise(q2 - vec3(eps, 0.0, 0.0));
	float m2 = value_noise(q2 + vec3(0.0, eps, 0.0)) - value_noise(q2 - vec3(0.0, eps, 0.0));
	float m3 = value_noise(q2 + vec3(0.0, 0.0, eps)) - value_noise(q2 - vec3(0.0, 0.0, eps));
	vec3 grad_b = vec3(m1, m2, m3) / (2.0 * eps);

	return cross(grad_a, grad_b);
}

vec3 closest_point_on_segment(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float len_sq = max(dot(ab, ab), 0.0001);
	float t = clamp(dot(p - a, ab) / len_sq, 0.0, 1.0);
	return a + ab * t;
}

void fog() {
	vec3 box_fade = smoothstep(vec3(0.0), vec3(edge_fade), UVW) *
			smoothstep(vec3(0.0), vec3(edge_fade), vec3(1.0) - UVW);
	float bounds_mask = box_fade.x * box_fade.y * box_fade.z;

	float height_norm = clamp(UVW.y, 0.0, 1.0);
	float excess_h = max(0.0, height_norm - ground_hugging_height) /
			max(1.0 - ground_hugging_height, 0.001);
	float vertical_profile = exp(-excess_h * height_falloff);

	vec3 curl_vec = sample_curl(WORLD_POSITION * clump_scale * 0.85, TIME * wave_speed);
	vec3 advected_pos = WORLD_POSITION + curl_vec * (0.35 * curl_advection_strength);

	float carve_transmittance = 1.0;
	float rim_compression = 0.0;

	// 1. CS2-style bullet trajectory tunnels with radial curl advection and rim bunching.
	for (int i = 0; i < 8; i++) {
		if (i >= active_ray_count) {
			break;
		}
		float life_strength = ray_starts[i].w;
		if (life_strength <= 0.001) {
			continue;
		}
		float radius = max(ray_ends[i].w, 0.05);
		vec3 seg_pt = closest_point_on_segment(
				WORLD_POSITION,
				ray_starts[i].xyz,
				ray_ends[i].xyz
		);
		vec3 radial_vec = WORLD_POSITION - seg_pt;
		float dist_sq = dot(radial_vec, radial_vec);
		float max_reach = radius * 2.4;

		if (dist_sq < max_reach * max_reach) {
			float dist = sqrt(max(dist_sq, 0.0001));
			vec3 radial_dir = radial_vec / dist;

			// Perturb tunnel wall with curl vector so holes swirl shut organically.
			float wall_warp = dot(curl_vec, radial_dir) * radius * 0.45 * (1.5 - life_strength);
			float warped_dist = max(0.0, dist + wall_warp);

			float expand_phase = smoothstep(0.0, 0.12, life_strength);
			float active_r = radius * expand_phase * (0.55 + 0.45 * life_strength);

			float push_mask = (1.0 - smoothstep(0.0, active_r * 2.1, warped_dist)) * life_strength;
			advected_pos -= radial_dir * (push_mask * active_r * curl_advection_strength);
			advected_pos += cross(radial_dir, curl_vec) * (push_mask * 0.65);

			float hole_core = smoothstep(active_r * 0.35, active_r * 1.15, warped_dist);
			carve_transmittance *= mix(1.0, hole_core, life_strength);

			float inner_rim = smoothstep(active_r * 0.6, active_r * 1.1, warped_dist);
			float outer_rim = 1.0 - smoothstep(active_r * 1.1, active_r * 2.0, warped_dist);
			rim_compression += inner_rim * outer_rim * life_strength * 1.35;
		}
	}

	// 2. Arkham Knight-style body displacement and trailing velocity wakes.
	for (int i = 0; i < 8; i++) {
		if (i >= active_actor_count) {
			break;
		}
		vec3 act_pos = actor_positions[i].xyz;
		float act_radius = max(actor_positions[i].w, 0.1);
		vec3 act_vel = actor_velocities[i].xyz;
		float wake_mult = actor_velocities[i].w;

		vec3 tail_end = act_pos - act_vel * wake_mult;
		vec3 wake_pt = closest_point_on_segment(WORLD_POSITION, act_pos, tail_end);

		// Stretch vertical interaction for standing character capsules.
		vec3 delta_vec = WORLD_POSITION - wake_pt;
		delta_vec.y *= 0.62;
		float dist_sq = dot(delta_vec, delta_vec);
		float max_wake_r = act_radius * 2.5;

		if (dist_sq < max_wake_r * max_wake_r) {
			float dist = sqrt(max(dist_sq, 0.0001));
			vec3 push_dir = delta_vec / dist;
			float speed_factor = clamp(length(act_vel) * 0.25, 0.15, 1.0);

			float warp_dist = max(0.0, dist + dot(curl_vec, push_dir) * act_radius * 0.4);
			float displace_weight = 1.0 - smoothstep(0.0, act_radius * 2.2, warp_dist);

			// Swirl displaced fog outward and into a trailing vortex behind the actor.
			vec3 vortex_dir = cross(push_dir, normalize(act_vel + vec3(0.0, 0.01, 0.0)));
			advected_pos -= push_dir * (displace_weight * act_radius * curl_advection_strength);
			advected_pos += vortex_dir * (displace_weight * speed_factor * curl_advection_strength);

			float body_carve = smoothstep(act_radius * 0.35, act_radius * 1.2, warp_dist);
			carve_transmittance *= mix(1.0, body_carve, 0.88);

			float wake_rim_in = smoothstep(act_radius * 0.7, act_radius * 1.25, warp_dist);
			float wake_rim_out = 1.0 - smoothstep(act_radius * 1.25, act_radius * 2.2, warp_dist);
			rim_compression += wake_rim_in * wake_rim_out * (0.65 + speed_factor * 0.9);
		}
	}

	// 3. Evaluate dynamic rolling waves and 3D clumps at the curl-advected coordinates.
	vec2 wave_phase = advected_pos.xz * wave_scale + vec2(TIME * wave_speed, -TIME * wave_speed * 0.7);
	float billow_wave = sin(wave_phase.x + curl_vec.x * 1.8) *
			cos(wave_phase.y + curl_vec.z * 1.8) * 0.5 + 0.5;

	vec3 sample_uvw = advected_pos * clump_scale + vec3(0.0, -TIME * wave_speed * 0.18, 0.0);
	float raw_clumps = fbm3(sample_uvw);
	float sculpted_clumps = clamp(pow(raw_clumps * 1.25, clump_contrast), 0.0, 1.6);

	float combined_structure = mix(sculpted_clumps, sculpted_clumps * (0.65 + 0.7 * billow_wave), 0.65);
	float final_density = base_density * vertical_profile * bounds_mask;
	final_density *= (combined_structure + rim_compression * 0.75) * carve_transmittance;

	DENSITY = max(0.0, final_density);
	ALBEDO = base_color.rgb;
	EMISSION = emission_color.rgb * (1.0 + rim_compression * 0.4);
}
