shader_type canvas_item;
render_mode unshaded;

group_uniforms Wipe_State;
uniform float wipe_progress : hint_range(0.0, 1.5, 0.001) = 0.0;
uniform float wash_intensity : hint_range(0.0, 1.0, 0.001) = 1.0;
uniform float visibility : hint_range(0.0, 1.0, 0.001) = 1.0;

group_uniforms Camera_Inertia;
uniform float angular_yaw_delta : hint_range(-10.0, 10.0, 0.01) = 0.0;
uniform float pitch_gravity_mod : hint_range(-0.5, 0.8, 0.01) = 0.0;

group_uniforms Liquid_Optics;
uniform float distortion_strength : hint_range(0.0, 0.15, 0.001) = 0.052;
uniform float meniscus_strength : hint_range(0.0, 0.15, 0.001) = 0.068;
uniform float chromatic_aberration : hint_range(0.0, 0.1, 0.001) = 0.028;
uniform float flow_speed : hint_range(0.1, 4.0, 0.05) = 1.45;
uniform float ripple_scale : hint_range(1.0, 12.0, 0.1) = 5.0;
uniform float specular_intensity : hint_range(0.0, 1.5, 0.01) = 0.42;
uniform vec4 water_tint : source_color = vec4(0.62, 0.86, 0.92, 0.18);

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.5 + 0.5;
}

// Evaluates BioShock-style domain-warped water sheet height at aspect-corrected UV
float sample_liquid_height(vec2 uv, float t, float yaw_shear) {
	vec2 sheared_uv = vec2(uv.x + uv.y * yaw_shear, uv.y);

	vec2 flow_a = vec2(yaw_shear * 0.35, -t * 1.15);
	vec2 flow_b = vec2(-yaw_shear * 0.2, -t * 0.78);

	float warp_x = gradient_noise(sheared_uv * (ripple_scale * 0.65) + flow_a * 0.6) - 0.5;
	float warp_y = gradient_noise(sheared_uv * (ripple_scale * 0.85) + flow_b * 0.8 + 7.3) - 0.5;
	vec2 warped_uv = sheared_uv + vec2(warp_x, warp_y) * 0.28;

	// Primary and secondary travelling surface ripples
	float wave_a = gradient_noise(warped_uv * ripple_scale + flow_a);
	float wave_b = gradient_noise(warped_uv * (ripple_scale * 1.85) + flow_b + vec2(3.7, 9.1));

	// Vertical Dishonored-style rivulet streams
	vec2 stream_uv = vec2(warped_uv.x * ripple_scale * 1.4, warped_uv.y * 1.6 - t * 1.35);
	float rivulets = gradient_noise(stream_uv);
	rivulets = smoothstep(0.28, 0.82, rivulets);

	// High-frequency capillary surface ripples
	float micro_ripples = sin(
		warped_uv.y * 28.0 - t * 9.5 + wave_a * 6.2831
	) * 0.5 + 0.5;

	return (wave_a * 0.45 + wave_b * 0.30 + rivulets * 0.35) + micro_ripples * 0.12;
}

void fragment() {
	float active_alpha = clamp(visibility * wash_intensity, 0.0, 1.0);
	if (active_alpha <= 0.001 || wipe_progress >= 1.495) {
		COLOR = vec4(0.0);
	} else {
		vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.0001), 1.0);
		vec2 uv = SCREEN_UV * aspect;

		float grav_mult = clamp(1.0 + pitch_gravity_mod * 0.45, 0.55, 1.65);
		float t = TIME * flow_speed * grav_mult;
		float yaw_shear = clamp(angular_yaw_delta * 0.045, -0.35, 0.35);

		// Uneven hanging liquid fingers along the falling meniscus curtain
		float finger_coarse = gradient_noise(vec2(uv.x * 2.8 + yaw_shear * 0.5, TIME * 0.35));
		float finger_fine = gradient_noise(vec2(uv.x * 7.5 - yaw_shear * 0.8, TIME * 0.6 + 4.2));
		float column_lag = (finger_coarse * 0.68 + finger_fine * 0.32) * 0.36;

		float wipe_active = step(0.001, wipe_progress);
		float curtain_y = mix(-0.25, wipe_progress * 1.28 - column_lag, wipe_active);
		float signed_dist = SCREEN_UV.y - curtain_y;

		// 1. Main water sheet mask below the falling curtain
		float sheet_mask = mix(1.0, smoothstep(-0.025, 0.055, signed_dist), wipe_active);

		// 2. Thick refractive meniscus ridge along the tearing boundary
		float meniscus_band = exp(-pow(signed_dist / 0.038, 2.0)) * wipe_active;
		float finger_slope = dFdx(column_lag) * 18.0;

		// 3. Trailing droplets and rivulet beads above the main curtain
		float trail_zone = smoothstep(-0.48, -0.01, signed_dist) * (1.0 - sheet_mask) * wipe_active;
		vec2 bead_uv = vec2(uv.x * 9.5 + yaw_shear * SCREEN_UV.y, uv.y * 5.5 - t * 0.9);
		float bead_field = smoothstep(0.62, 0.88, gradient_noise(bead_uv));
		float trail_mask = bead_field * trail_zone;

		// Analytical finite-difference normal from the domain-warped liquid heightfield
		float eps = 0.006;
		float h_c = sample_liquid_height(uv, t, yaw_shear);
		float h_x = sample_liquid_height(uv + vec2(eps, 0.0), t, yaw_shear);
		float h_y = sample_liquid_height(uv + vec2(0.0, eps), t, yaw_shear);
		vec2 sheet_norm = vec2(h_c - h_x, h_c - h_y) / eps;

		// Meniscus normal bulges strongly downward (+Y) and follows finger curvature
		vec2 meniscus_norm = vec2(
			finger_slope + sheet_norm.x * 0.6,
			(signed_dist / 0.038) * 1.85 + 0.65
		);

		vec2 combined_norm = (
			sheet_norm * (sheet_mask + trail_mask * 0.85) * distortion_strength
			+ meniscus_norm * meniscus_band * meniscus_strength
		) * active_alpha;

		float total_coverage = clamp(sheet_mask + meniscus_band + trail_mask, 0.0, 1.0) * active_alpha;
		vec2 refract_offset = combined_norm * total_coverage;

		// Chromatic aberration split along liquid normal vector
		vec2 uv_r = clamp(SCREEN_UV + refract_offset * (1.0 + chromatic_aberration), 0.001, 0.999);
		vec2 uv_g = clamp(SCREEN_UV + refract_offset, 0.001, 0.999);
		vec2 uv_b = clamp(SCREEN_UV + refract_offset * (1.0 - chromatic_aberration), 0.001, 0.999);

		float mip_lod = clamp(length(refract_offset) * 16.0, 0.0, 2.2);
		float r = textureLod(screen_texture, uv_r, mip_lod).r;
		float g = textureLod(screen_texture, uv_g, mip_lod).g;
		float b = textureLod(screen_texture, uv_b, mip_lod).b;
		vec3 refracted_rgb = vec3(r, g, b);

		// Fake-normal specular rim sheen on steep liquid ridges and meniscus lip
		float norm_mag = length(combined_norm) / max(distortion_strength, 0.001);
		float top_light = clamp(-combined_norm.y * 14.0 + combined_norm.x * 6.0 + 0.35, 0.0, 1.0);
		float rim_spec = (
			smoothstep(0.32, 1.15, norm_mag) * top_light * specular_intensity
			+ meniscus_band * 0.22
		) * total_coverage;

		// Subtle teal absorption inside thick wave crests
		float crest_thickness = clamp(h_c * sheet_mask + meniscus_band * 0.85, 0.0, 1.0);
		vec3 tinted_rgb = mix(
			refracted_rgb,
			water_tint.rgb * (dot(refracted_rgb, vec3(0.299, 0.587, 0.114)) + 0.25),
			crest_thickness * water_tint.a * total_coverage
		);

		vec3 final_rgb = tinted_rgb + vec3(0.88, 0.96, 1.0) * rim_spec;
		COLOR = vec4(final_rgb, clamp(total_coverage * 1.25, 0.0, 1.0));
	}
}
