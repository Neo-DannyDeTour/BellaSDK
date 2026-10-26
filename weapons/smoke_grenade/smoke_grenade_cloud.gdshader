shader_type fog;

uniform vec4 smoke_albedo : source_color = vec4(0.68, 0.72, 0.76, 1.0);
uniform vec4 emission_color : source_color = vec4(0.05, 0.07, 0.09, 1.0);
uniform float base_density : hint_range(0.5, 12.0) = 6.5;
uniform float clump_scale : hint_range(0.2, 4.0) = 0.95;
uniform float clump_contrast : hint_range(0.3, 3.0) = 1.35;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.48;
uniform float curl_advection_strength : hint_range(0.0, 4.0) = 1.45;

uniform float expansion_progress : hint_range(0.0, 1.0) = 1.0;
uniform float dissipation_alpha : hint_range(0.0, 1.0) = 1.0;

uniform vec4 lobe_spheres[10];

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
		p = p * 2.05 + shift;
		amp *= 0.45;
	}
	return v;
}

vec3 sample_curl(vec3 p, float t) {
	const float eps = 0.18;
	vec3 q = p + vec3(t * 0.24, -t * 0.18, t * 0.21);
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

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

vec3 closest_point_on_segment(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float len_sq = max(dot(ab, ab), 0.0001);
	float t = clamp(dot(p - a, ab) / len_sq, 0.0, 1.0);
	return a + ab * t;
}

void fog() {
	vec3 box_fade = smoothstep(vec3(0.0), vec3(0.08), UVW) *
			smoothstep(vec3(0.0), vec3(0.08), vec3(1.0) - UVW);
	float bounds_mask = box_fade.x * box_fade.y * box_fade.z;

	vec3 curl_vec = sample_curl(WORLD_POSITION * clump_scale * 0.85, TIME * wave_speed);
	vec3 advected_pos = WORLD_POSITION + curl_vec * (0.35 * curl_advection_strength);

	// 1. Evaluate multi-lobe wall-conforming SDF.
	float sdf_dist = 100.0;
	float expand = max(expansion_progress, 0.05);
	for (int i = 0; i < 10; i++) {
		float lobe_r = lobe_spheres[i].w * expand;
		if (lobe_r <= 0.01) {
			continue;
		}
		vec3 delta_p = WORLD_POSITION - lobe_spheres[i].xyz;
		// Flatten vertical profile slightly so smoke hugs floor and forms a dense dome.
		delta_p.y *= 1.18;
		float d = length(delta_p) - lobe_r;
		sdf_dist = smin(sdf_dist, d, 0.75 * expand);
	}

	float billow_disp = (fbm3(advected_pos * clump_scale + vec3(0.0, -TIME * wave_speed * 0.3, 0.0)) - 0.5) * 0.85;
	float plume_shell = 1.0 - smoothstep(-0.65, 0.45, sdf_dist + billow_disp * expand);

	if (plume_shell <= 0.001) {
		DENSITY = 0.0;
	} else {
		float carve_transmittance = 1.0;
		float rim_compression = 0.0;

		// 2. CS2 bullet trajectory tunnels and radial explosion shockwaves.
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

				float wall_warp = dot(curl_vec, radial_dir) * radius * 0.48 * (1.5 - life_strength);
				float warped_dist = max(0.0, dist + wall_warp);

				float expand_phase = smoothstep(0.0, 0.12, life_strength);
				float active_r = radius * expand_phase * (0.55 + 0.45 * life_strength);

				float push_mask = (1.0 - smoothstep(0.0, active_r * 2.1, warped_dist)) * life_strength;
				advected_pos -= radial_dir * (push_mask * active_r * curl_advection_strength);
				advected_pos += cross(radial_dir, curl_vec) * (push_mask * 0.75);

				float hole_core = smoothstep(active_r * 0.32, active_r * 1.15, warped_dist);
				carve_transmittance *= mix(1.0, hole_core, life_strength);

				float inner_rim = smoothstep(active_r * 0.6, active_r * 1.1, warped_dist);
				float outer_rim = 1.0 - smoothstep(active_r * 1.1, active_r * 2.0, warped_dist);
				rim_compression += inner_rim * outer_rim * life_strength * 1.45;
			}
		}

		// 3. APEX-style actor wake turbulence (capped at 45% carve to preserve LoS cover).
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

			vec3 delta_vec = WORLD_POSITION - wake_pt;
			delta_vec.y *= 0.65;
			float dist_sq = dot(delta_vec, delta_vec);
			float max_wake_r = act_radius * 2.4;

			if (dist_sq < max_wake_r * max_wake_r) {
				float dist = sqrt(max(dist_sq, 0.0001));
				vec3 push_dir = delta_vec / dist;
				float speed_factor = clamp(length(act_vel) * 0.25, 0.0, 1.0);

				float warp_dist = max(0.0, dist + dot(curl_vec, push_dir) * act_radius * 0.4);
				float displace_weight = 1.0 - smoothstep(0.0, act_radius * 2.1, warp_dist);

				vec3 vortex_dir = cross(push_dir, normalize(act_vel + vec3(0.0, 0.01, 0.0)));
				advected_pos -= push_dir * (displace_weight * act_radius * curl_advection_strength);
				advected_pos += vortex_dir * (displace_weight * speed_factor * curl_advection_strength * 1.25);

				float body_carve = smoothstep(act_radius * 0.35, act_radius * 1.2, warp_dist);
				carve_transmittance *= mix(1.0, body_carve, 0.45 * speed_factor);

				float wake_rim_in = smoothstep(act_radius * 0.7, act_radius * 1.25, warp_dist);
				float wake_rim_out = 1.0 - smoothstep(act_radius * 1.25, act_radius * 2.1, warp_dist);
				rim_compression += wake_rim_in * wake_rim_out * speed_factor * 0.85;
			}
		}

		vec3 sample_uvw = advected_pos * clump_scale + vec3(0.0, -TIME * wave_speed * 0.22, 0.0);
		float raw_clumps = fbm3(sample_uvw);
		float sculpted_clumps = clamp(pow(raw_clumps * 1.35, clump_contrast), 0.25, 1.65);

		float final_density = base_density * plume_shell * bounds_mask * dissipation_alpha;
		final_density *= (sculpted_clumps + rim_compression * 0.8) * carve_transmittance;

		DENSITY = max(0.0, final_density);
		ALBEDO = smoke_albedo.rgb * mix(0.82, 1.08, raw_clumps);
		EMISSION = emission_color.rgb * (1.0 + rim_compression * 0.45);
	}
}
