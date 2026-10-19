shader_type fog;

global uniform vec3 wind_direction;
global uniform float wind_intensity;
global uniform float wind_speed;

uniform vec4 color_dark_grey : source_color = vec4(0.16, 0.17, 0.19, 1.0);
uniform vec4 color_mid_grey : source_color = vec4(0.44, 0.46, 0.49, 1.0);
uniform vec4 color_light_ash : source_color = vec4(0.76, 0.78, 0.81, 1.0);
uniform vec4 emission_tint : source_color = vec4(0.04, 0.05, 0.06, 1.0);

uniform float base_density : hint_range(0.0, 8.0) = 2.6;
uniform float phase_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float core_radius_ratio : hint_range(0.05, 0.9) = 0.38;
uniform float edge_softness : hint_range(0.05, 0.8) = 0.42;
uniform float billow_scale : hint_range(0.1, 4.0) = 0.85;
uniform float detail_scale : hint_range(0.2, 8.0) = 2.15;
uniform float plume_contrast : hint_range(0.3, 3.5) = 1.55;
uniform float turbulence_speed : hint_range(0.0, 3.0) = 0.48;
uniform float curl_strength : hint_range(0.0, 4.0) = 1.55;
uniform float wind_influence : hint_range(0.0, 3.0) = 0.85;

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

float fbm4(vec3 p) {
	float v = 0.0;
	float amp = 0.52;
	vec3 shift = vec3(17.3, 31.7, 11.9);
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p = p * 2.09 + shift;
		amp *= 0.48;
	}
	return v;
}

vec3 sample_curl(vec3 p, float t) {
	const float eps = 0.16;
	vec3 q = p + vec3(t * 0.24, -t * 0.31, t * 0.18);
	float n1 = value_noise(q + vec3(eps, 0.0, 0.0)) - value_noise(q - vec3(eps, 0.0, 0.0));
	float n2 = value_noise(q + vec3(0.0, eps, 0.0)) - value_noise(q - vec3(0.0, eps, 0.0));
	float n3 = value_noise(q + vec3(0.0, 0.0, eps)) - value_noise(q - vec3(0.0, 0.0, eps));
	vec3 grad_a = vec3(n1, n2, n3) / (2.0 * eps);

	vec3 q2 = q + vec3(29.1, 53.4, 17.6);
	float m1 = value_noise(q2 + vec3(eps, 0.0, 0.0)) - value_noise(q2 - vec3(eps, 0.0, 0.0));
	float m2 = value_noise(q2 + vec3(0.0, eps, 0.0)) - value_noise(q2 - vec3(0.0, eps, 0.0));
	float m3 = value_noise(q2 + vec3(0.0, 0.0, eps)) - value_noise(q2 - vec3(0.0, 0.0, eps));
	vec3 grad_b = vec3(m1, m2, m3) / (2.0 * eps);

	return cross(grad_a, grad_b);
}

vec3 closest_point_on_segment(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float len_sq = max(dot(ab, ab), 0.00001);
	float t = clamp(dot(p - a, ab) / len_sq, 0.0, 1.0);
	return a + ab * t;
}

void fog() {
	if (phase_alpha <= 0.001 || base_density <= 0.001) {
		DENSITY = 0.0;
		ALBEDO = color_mid_grey.rgb;
		EMISSION = vec3(0.0);
	} else {
		vec3 wind_dir = length(wind_direction) > 0.001 ? normalize(wind_direction) : vec3(1.0, 0.0, 0.0);
		vec3 wind_offset = (wind_dir * max(wind_intensity, 0.25) * max(wind_speed, 0.35) * wind_influence + vec3(0.0, 0.65, 0.0)) * TIME * turbulence_speed;

		vec3 curl_vec = sample_curl(WORLD_POSITION * billow_scale * 0.75 - wind_offset * 0.4, TIME * turbulence_speed);
		vec3 advected_pos = WORLD_POSITION - wind_offset + curl_vec * (0.42 * curl_strength);

		float carve_transmittance = 1.0;
		float rim_compression = 0.0;

		// 1. Bullet trajectories & spherical explosion cavities (8-slot ring buffer).
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
			float max_reach = radius * 2.45;

			if (dist_sq < max_reach * max_reach) {
				float dist = sqrt(max(dist_sq, 0.0001));
				vec3 radial_dir = radial_vec / dist;

				float wall_warp = dot(curl_vec, radial_dir) * radius * 0.48 * (1.45 - life_strength);
				float warped_dist = max(0.0, dist + wall_warp);

				float expand_phase = smoothstep(0.0, 0.1, life_strength);
				float active_r = radius * expand_phase * (0.55 + 0.45 * life_strength);

				float push_mask = (1.0 - smoothstep(0.0, active_r * 2.15, warped_dist)) * life_strength;
				advected_pos -= radial_dir * (push_mask * active_r * curl_strength);
				advected_pos += cross(radial_dir, curl_vec) * (push_mask * 0.7);

				float hole_core = smoothstep(active_r * 0.3, active_r * 1.18, warped_dist);
				carve_transmittance *= mix(1.0, hole_core, life_strength);

				float inner_rim = smoothstep(active_r * 0.6, active_r * 1.1, warped_dist);
				float outer_rim = 1.0 - smoothstep(active_r * 1.1, active_r * 2.05, warped_dist);
				rim_compression += inner_rim * outer_rim * life_strength * 1.4;
			}
		}

		// 2. Actor body displacement and trailing velocity wakes.
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
			delta_vec.y *= 0.62;
			float dist_sq = dot(delta_vec, delta_vec);
			float max_wake_r = act_radius * 2.5;

			if (dist_sq < max_wake_r * max_wake_r) {
				float dist = sqrt(max(dist_sq, 0.0001));
				vec3 push_dir = delta_vec / dist;
				float speed_factor = clamp(length(act_vel) * 0.25, 0.15, 1.0);

				float warp_dist = max(0.0, dist + dot(curl_vec, push_dir) * act_radius * 0.42);
				float displace_weight = 1.0 - smoothstep(0.0, act_radius * 2.2, warp_dist);

				vec3 vortex_dir = cross(push_dir, normalize(act_vel + vec3(0.0, 0.01, 0.0)));
				advected_pos -= push_dir * (displace_weight * act_radius * curl_strength);
				advected_pos += vortex_dir * (displace_weight * speed_factor * curl_strength);

				float body_carve = smoothstep(act_radius * 0.35, act_radius * 1.2, warp_dist);
				carve_transmittance *= mix(1.0, body_carve, 0.9);

				float wake_rim_in = smoothstep(act_radius * 0.7, act_radius * 1.25, warp_dist);
				float wake_rim_out = 1.0 - smoothstep(act_radius * 1.25, act_radius * 2.2, warp_dist);
				rim_compression += wake_rim_in * wake_rim_out * (0.65 + speed_factor * 0.9);
			}
		}

		// 3. Domain-warped organic cloud morphology (irregular billowing plume, never uniform spheres).
		vec3 centered_uvw = (UVW - vec3(0.5)) * 2.0;
		vec3 shape_warp = curl_vec * edge_softness * 0.65;
		float macro_noise = fbm4(advected_pos * billow_scale);
		float micro_noise = value_noise(advected_pos * detail_scale + curl_vec * 1.3);

		vec3 warped_radial = centered_uvw + shape_warp + (macro_noise - 0.5) * edge_softness * 0.85;
		float radial_dist = length(warped_radial);

		float radial_envelope = 1.0 - smoothstep(core_radius_ratio, 1.0, radial_dist);
		vec3 box_guard = smoothstep(vec3(0.0), vec3(0.08), UVW) * smoothstep(vec3(0.0), vec3(0.08), vec3(1.0) - UVW);
		float bounds_mask = radial_envelope * box_guard.x * box_guard.y * box_guard.z;

		float combined_noise = mix(macro_noise, micro_noise, 0.38);
		float sculpted_plume = clamp(pow(combined_noise * 1.32, plume_contrast), 0.0, 1.85);

		// Erode outer edges with noise so silhouettes look ragged and turbulent.
		float edge_erosion = smoothstep(1.0 - radial_envelope * 0.85, 1.0, combined_noise + radial_envelope * 0.55);
		float final_density = base_density * phase_alpha * bounds_mask * edge_erosion;
		final_density *= (sculpted_plume + rim_compression * 0.8) * carve_transmittance;

		// 4. Multi-shade grey palette: dark charcoal core, slate mid-tones, light ash highlights on billowing tops/rims.
		float shade_driver = clamp(combined_noise * 0.65 + UVW.y * 0.35 + rim_compression * 0.25 - radial_envelope * 0.2, 0.0, 1.0);
		vec3 low_to_mid = mix(color_dark_grey.rgb, color_mid_grey.rgb, smoothstep(0.15, 0.55, shade_driver));
		vec3 final_albedo = mix(low_to_mid, color_light_ash.rgb, smoothstep(0.55, 0.92, shade_driver));

		DENSITY = max(0.0, final_density);
		ALBEDO = final_albedo;
		EMISSION = emission_tint.rgb * (0.7 + 0.6 * shade_driver + rim_compression * 0.35);
	}
}
