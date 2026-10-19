shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

// --- Simulation & Volume Uniforms ---
uniform float water_time = 0.0;
uniform vec3 water_size = vec3(1.0, 1.0, 1.0);
uniform bool show_side_walls = false;

// --- Optical & Absorption Uniforms ---
uniform vec4 shallow_color : source_color = vec4(0.22, 0.65, 0.78, 1.0);
uniform vec4 deep_color : source_color = vec4(0.01, 0.05, 0.16, 1.0);
uniform vec3 absorption_coefficients = vec3(1.4, 0.42, 0.08);
uniform float depth_distance : hint_range(0.1, 100.0) = 4.5;
uniform float beers_law : hint_range(0.1, 20.0) = 2.2;
uniform vec4 underwater_ceiling_color : source_color = vec4(0.0, 0.1, 0.2, 1.0);

// --- Macro & Meso Wave Cascade Uniforms ---
uniform float wave_amplitude : hint_range(0.0, 5.0) = 0.1;
uniform float wave_length : hint_range(0.25, 100.0) = 4.5;
uniform float wave_speed : hint_range(0.0, 20.0) = 1.4;
uniform float wave_steepness : hint_range(0.0, 2.0) = 0.35;

// --- Interactive Multi-Scale Ripple Ring Buffer ---
uniform vec4 ripples[16];
uniform float ripple_mesh_height : hint_range(0.0, 2.0) = 0.22;

// --- Surface Micro-Detail & Normal Uniforms ---
uniform vec2 uv_scale = vec2(2.0, 2.0);
uniform float normal_bump_strength : hint_range(0.0, 8.0) = 2.0;
uniform vec2 pan_speed_1 = vec2(0.1, 0.01);
uniform vec2 pan_speed_2 = vec2(-0.015, 0.025);

// --- Reflection, Refraction & PBR Uniforms ---
uniform bool enable_ssr = true;
uniform float ssr_max_distance : hint_range(0.5, 50.0) = 4.5;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.02;
uniform vec4 sky_reflection_tint : source_color = vec4(0.65, 0.82, 1.0, 1.0);
uniform float fresnel_base : hint_range(0.0, 1.0) = 0.12;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.5;
uniform float roughness : hint_range(0.0, 1.0) = 0.03;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.12;

// --- Foam Uniforms ---
uniform sampler2D foam_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform float foam_distance : hint_range(0.0, 5.0) = 0.35;
uniform float crest_foam_threshold : hint_range(0.0, 2.0) = 0.65;

// --- Screen & Depth Textures ---
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// --- Shared Wave Direction Constants (Synced with CPU water_body.gd) ---
const vec2 WAVE_DIR_0 = vec2(0.924678, 0.380749);
const vec2 WAVE_DIR_1 = vec2(-0.451481, 0.892281);
const vec2 WAVE_DIR_2 = vec2(0.319222, -0.947680);

// --- Varyings ---
varying vec3 v_world_pos;
varying vec3 v_local_normal;
varying float v_is_top_face;
varying float v_wave_crest;
varying vec2 v_macro_slope;

// --- Procedural Simplex / Gradient Noise for Micro-Ripples & Foam ---
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float n00 = dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float n10 = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n01 = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n11 = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}

// Evaluates a single trochoidal wave octave height and analytical XZ gradient.
// Returns vec3(height, dh_dx, dh_dz) synced 1:1 with CPU get_wave_height_at_pos().
vec3 evaluate_wave_octave(
	vec2 world_xz,
	vec2 dir,
	float amp,
	float length_val,
	float speed_val,
	float steepness_val,
	float t
) {
	float safe_len = max(length_val, 0.25);
	float k = TAU / safe_len;
	float omega = speed_val * k;
	float theta = dot(dir, world_xz) * k + t * omega;
	float s1 = sin(theta);
	float c1 = cos(theta);
	float s2 = sin(2.0 * theta);
	float c2 = cos(2.0 * theta);

	float h = amp * (s1 + 0.5 * steepness_val * s2);
	float dtheta = amp * k * (c1 + steepness_val * c2);
	return vec3(h, dir.x * dtheta, dir.y * dtheta);
}

// Evaluates the 3-octave wave cascade plus 16-slot interactive ripple buffer.
// Returns vec3(total_height, dh_dx, dh_dz) synced 1:1 with CPU get_wave_height_at_pos().
vec3 evaluate_surface_displacement(vec2 world_xz, float t, bool include_micro_harmonics) {
	float total_h = 0.0;
	vec2 total_slope = vec2(0.0);

	if (wave_amplitude > 0.0001) {
		vec3 w0 = evaluate_wave_octave(
			world_xz,
			WAVE_DIR_0,
			wave_amplitude,
			wave_length,
			wave_speed,
			wave_steepness * 0.55,
			t
		);
		vec3 w1 = evaluate_wave_octave(
			world_xz,
			WAVE_DIR_1,
			wave_amplitude * 0.42,
			wave_length * 0.43,
			wave_speed * 1.28,
			wave_steepness * 0.30,
			t
		);
		vec3 w2 = evaluate_wave_octave(
			world_xz,
			WAVE_DIR_2,
			wave_amplitude * 0.18,
			wave_length * 0.19,
			wave_speed * 1.65,
			wave_steepness * 0.15,
			t
		);
		total_h += w0.x + w1.x + w2.x;
		total_slope += w0.yz + w1.yz + w2.yz;
	}

	if (ripple_mesh_height > 0.0001) {
		for (int i = 0; i < 16; i++) {
			vec4 r = ripples[i];
			float amp = r.w;
			if (amp <= 0.0001) {
				continue;
			}
			float age = t - r.z;
			float scale_f = clamp(amp, 0.05, 3.0);
			float max_age = 1.6 + scale_f * 0.9;
			if (age <= 0.0 || age >= max_age) {
				continue;
			}

			vec2 delta_xz = world_xz - r.xy;
			float dist = length(delta_xz);
			float exp_speed = 1.15 + scale_f * 0.65;
			float radius = age * exp_speed;
			float sigma = 0.14 + scale_f * 0.28;
			float delta_r = dist - radius;

			if (abs(delta_r) > sigma * 3.5) {
				continue;
			}

			float inv_two_sigma_sq = 1.0 / (2.0 * sigma * sigma);
			float env = exp(-(delta_r * delta_r) * inv_two_sigma_sq);
			float life_ratio = 1.0 - (age / max_age);
			float decay = exp(-age * (1.8 / (0.6 + scale_f * 0.4))) * life_ratio;
			float k_r = 22.0 / (0.35 + scale_f * 0.65);
			float phase = delta_r * k_r - age * 4.0;

			float eff_amp = min(amp, 2.0) * ripple_mesh_height * env * decay;
			float s_p = sin(phase);
			float c_p = cos(phase);
			total_h += s_p * eff_amp;

			if (dist > 0.0001) {
				vec2 radial_dir = delta_xz / dist;
				float d_dr = eff_amp * (k_r * c_p - s_p * delta_r * 2.0 * inv_two_sigma_sq);
				if (include_micro_harmonics) {
					// High-frequency capillary ring harmonic for sub-decimeter crispness
					float cap_phase = phase * 2.35 - age * 6.0;
					float cap_weight = clamp(1.2 - scale_f * 0.4, 0.25, 1.0);
					d_dr += eff_amp * cap_weight * k_r * 0.65 * cos(cap_phase);
				}
				total_slope += radial_dir * d_dr;
			}
		}
	}

	return vec3(total_h, total_slope.x, total_slope.y);
}

// Computes multi-band procedural micro-normal perturbation across all spatial scales.
vec2 evaluate_micro_normal_slope(vec2 world_xz, float t) {
	vec2 scaled_uv = world_xz * max(uv_scale, vec2(0.05)) * 0.35;
	vec2 uv1 = scaled_uv + pan_speed_1 * t * 4.0;
	vec2 uv2 = scaled_uv * 2.15 + pan_speed_2 * t * 4.5;
	vec2 uv3 = world_xz * 3.8 - vec2(pan_speed_1.y, -pan_speed_2.x) * t * 6.0;

	float eps = 0.04;
	float h_c1 = gradient_noise(uv1) * 0.55 + gradient_noise(uv2) * 0.30;
	float h_x1 = gradient_noise(uv1 + vec2(eps, 0.0)) * 0.55 + gradient_noise(uv2 + vec2(eps, 0.0)) * 0.30;
	float h_z1 = gradient_noise(uv1 + vec2(0.0, eps)) * 0.55 + gradient_noise(uv2 + vec2(0.0, eps)) * 0.30;

	// Fine capillary ripple octave (centimeter scale)
	float h_c2 = gradient_noise(uv3) * 0.15;
	float h_x2 = gradient_noise(uv3 + vec2(eps * 2.0, 0.0)) * 0.15;
	float h_z2 = gradient_noise(uv3 + vec2(0.0, eps * 2.0)) * 0.15;

	float tex_c = texture(foam_noise, uv1 * 0.25).r;
	float tex_x = texture(foam_noise, (uv1 + vec2(eps, 0.0)) * 0.25).r;
	float tex_z = texture(foam_noise, (uv1 + vec2(0.0, eps)) * 0.25).r;

	vec2 grad_proc = vec2((h_x1 - h_c1) + (h_x2 - h_c2), (h_z1 - h_c1) + (h_z2 - h_c2)) / eps;
	vec2 grad_tex = vec2(tex_x - tex_c, tex_z - tex_c) * 1.25;
	return (grad_proc * 0.7 + grad_tex * 0.3) * (normal_bump_strength * 0.08);
}

void vertex() {
	v_local_normal = NORMAL;
	// Scale unit BoxMesh to target water_size without CPU mesh regeneration
	vec3 scaled_vertex = VERTEX * water_size;

	// Identify top surface vertices (including top edge vertices of side walls for seamless stitching)
	v_is_top_face = step(0.5, NORMAL.y);
	float is_top_vertex = step(0.0, VERTEX.y);

	vec3 world_base = (MODEL_MATRIX * vec4(scaled_vertex, 1.0)).xyz;
	vec3 wave_data = evaluate_surface_displacement(world_base.xz, water_time, false);

	if (is_top_vertex > 0.5) {
		scaled_vertex.y += wave_data.x;
	}

	VERTEX = scaled_vertex;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_macro_slope = wave_data.yz;
	v_wave_crest = clamp(
		wave_data.x / max(wave_amplitude * 1.6 + 0.001, 0.01),
		-1.0,
		1.5
	);

	if (v_is_top_face > 0.5) {
		vec3 world_norm = normalize(vec3(-wave_data.y, 1.0, -wave_data.z));
		NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(world_norm, 0.0)).xyz);
	}
}

void fragment() {
	// Hide side walls and bottom face when show_side_walls is false
	if (v_is_top_face < 0.5 && !show_side_walls) {
		discard;
	}

	// Evaluate per-pixel analytical wave + multi-scale ripple slope + micro-capillary slope
	vec3 pixel_wave = evaluate_surface_displacement(v_world_pos.xz, water_time, true);
	vec2 micro_slope = evaluate_micro_normal_slope(v_world_pos.xz, water_time);
	vec2 combined_slope = pixel_wave.yz + micro_slope;

	vec3 world_normal = v_is_top_face > 0.5
		? normalize(vec3(-combined_slope.x, 1.0, -combined_slope.y))
		: normalize((MODEL_MATRIX * vec4(v_local_normal, 0.0)).xyz);

	if (!FRONT_FACING) {
		world_normal = -world_normal;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	// Reconstruct linear scene depth behind water surface
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view_scene = INV_PROJECTION_MATRIX * ndc;
	view_scene.xyz /= view_scene.w;
	float scene_linear_depth = -view_scene.z;
	float surface_linear_depth = -VERTEX.z;
	float water_depth_diff = max(0.0, scene_linear_depth - surface_linear_depth);

	// Depth-aware chromatic/refraction UV offset (clamped against foreground bleeding)
	vec2 refract_offset = NORMAL.xy * refraction_strength * clamp(water_depth_diff * 0.5, 0.0, 1.0);
	vec2 refracted_uv = clamp(SCREEN_UV + refract_offset, vec2(0.001), vec2(0.999));
	float refracted_raw_depth = texture(depth_texture, refracted_uv).r;
	vec4 refracted_view = INV_PROJECTION_MATRIX * vec4(refracted_uv * 2.0 - 1.0, refracted_raw_depth, 1.0);
	refracted_view.xyz /= refracted_view.w;
	float refracted_linear_depth = -refracted_view.z;

	if (refracted_linear_depth < surface_linear_depth) {
		refracted_uv = SCREEN_UV;
		refracted_linear_depth = scene_linear_depth;
	}
	float optical_depth = max(0.0, refracted_linear_depth - surface_linear_depth);
	vec3 screen_col = textureLod(screen_texture, refracted_uv, 0.0).rgb;

	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);

	if (!FRONT_FACING) {
		// --- UNDERWATER CEILING (Backface): Snell's Window & Non-Volumetric Murk ---
		// Critical angle for water-to-air is ~48.6 deg (cos(48.6 deg) ≈ 0.661)
		float snell_window = smoothstep(0.52, 0.72, ndotv);
		float ceiling_dist = length(VERTEX);

		// Guarantee murky underwater distance falloff even when Volumetric Fog is disabled
		float murk_extinction = exp(-ceiling_dist * 0.14 * max(beers_law * 0.35, 0.5));
		vec3 murk_scatter = mix(deep_color.rgb, underwater_ceiling_color.rgb, 0.55);

		vec3 tir_reflection = mix(
			murk_scatter,
			shallow_color.rgb * 0.55 + underwater_ceiling_color.rgb * 0.45,
			0.4
		);
		vec3 refracted_sky = mix(underwater_ceiling_color.rgb, screen_col, 0.78);
		vec3 ceiling_col = mix(tir_reflection, refracted_sky, snell_window);

		// Distance fogging into murky deep water so underwater view is never clean
		ALBEDO = mix(murk_scatter, ceiling_col, murk_extinction);
		ROUGHNESS = clamp(roughness * 1.5, 0.02, 1.0);
		SPECULAR = specular_strength * 0.7;
		METALLIC = metallic * 0.5;
		ALPHA = 1.0;
	} else {
		// --- TOP / EXTERIOR SURFACE (Frontface): Beer-Lambert, SSR, Fresnel & Foam ---
		float scaled_depth = optical_depth / max(depth_distance, 0.1);
		vec3 transmittance = exp(-absorption_coefficients * scaled_depth * beers_law);
		float depth_murk_factor = exp(-scaled_depth * beers_law);
		vec3 volume_scatter = mix(deep_color.rgb, shallow_color.rgb, depth_murk_factor);

		// Guarantee baseline turbidity/murk so water is never completely transparent
		vec3 absorbed_scene = screen_col * transmittance * 0.82;
		vec3 underwater_col = mix(volume_scatter, absorbed_scene + volume_scatter * (1.0 - transmittance), 0.65);

		// Raymarched Screen-Space Reflections (SSR) with screen-edge fade
		vec3 refl_col = sky_reflection_tint.rgb;
		float ssr_confidence = 0.0;
		if (enable_ssr) {
			vec3 refl_dir_view = reflect(-VIEW, NORMAL);
			if (refl_dir_view.z < 0.05) {
				int steps = 12;
				float step_len = ssr_max_distance / float(steps);
				vec3 march_pos = VERTEX;
				for (int s = 1; s <= 12; s++) {
					march_pos += refl_dir_view * step_len;
					vec4 proj = PROJECTION_MATRIX * vec4(march_pos, 1.0);
					proj.xyz /= proj.w;
					vec2 sample_uv = proj.xy * 0.5 + 0.5;
					if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
						break;
					}
					float d_sample = texture(depth_texture, sample_uv).r;
					vec4 v_sample = INV_PROJECTION_MATRIX * vec4(proj.xy, d_sample, 1.0);
					v_sample.xyz /= v_sample.w;
					float depth_delta = (-march_pos.z) - (-v_sample.z);
					if (depth_delta > 0.02 && depth_delta < step_len * 2.2) {
						vec2 edge_dist = smoothstep(vec2(0.0), vec2(0.12), sample_uv)
							* (vec2(1.0) - smoothstep(vec2(0.88), vec2(1.0), sample_uv));
						ssr_confidence = edge_dist.x * edge_dist.y * (1.0 - float(s) / float(steps));
						refl_col = mix(sky_reflection_tint.rgb, textureLod(screen_texture, sample_uv, 0.0).rgb, ssr_confidence);
						break;
					}
				}
			}
		}

		// Schlick Fresnel blending
		float fresnel = clamp(
			fresnel_base + (1.0 - fresnel_base) * pow(1.0 - ndotv, fresnel_power),
			0.0,
			1.0
		);
		vec3 surface_col = mix(underwater_col, refl_col, fresnel * 0.65);

		// Shoreline depth foam + wave crest foam modulated by noise
		if (v_is_top_face > 0.5) {
			vec2 foam_uv = v_world_pos.xz * 0.45 + pan_speed_1 * water_time * 2.0;
			float noise_val = texture(foam_noise, foam_uv).r * 0.65
				+ (gradient_noise(v_world_pos.xz * 2.4 - water_time * 0.8) * 0.5 + 0.5) * 0.35;

			float shore_mask = 1.0 - smoothstep(0.0, max(foam_distance, 0.01), water_depth_diff);
			float shore_foam = smoothstep(0.32, 0.68, shore_mask + noise_val * 0.35 * shore_mask);

			float crest_raw = smoothstep(crest_foam_threshold, crest_foam_threshold + 0.45, v_wave_crest);
			float crest_foam = crest_raw * smoothstep(0.35, 0.75, noise_val);

			// Add subtle foam ring highlight on strong interactive splash ripples
			float ripple_slope_mag = length(pixel_wave.yz - v_macro_slope);
			float splash_foam = smoothstep(0.35, 0.85, ripple_slope_mag) * noise_val * 0.6;

			float total_foam = clamp(max(shore_foam, max(crest_foam, splash_foam)), 0.0, 1.0) * foam_color.a;
			surface_col = mix(surface_col, foam_color.rgb, total_foam);
			ROUGHNESS = mix(roughness, 0.65, total_foam);
		} else {
			ROUGHNESS = roughness;
		}

		ALBEDO = surface_col;
		SPECULAR = specular_strength;
		METALLIC = metallic;
		ALPHA = 1.0;
	}
}
