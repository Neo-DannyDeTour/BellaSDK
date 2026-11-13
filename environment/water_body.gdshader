shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

const float REFLECTANCE = 0.02;

// --- Simulation & Volume Uniforms ---
uniform float water_time = 0.0;
uniform vec3 water_size = vec3(1.0, 1.0, 1.0);
uniform bool show_side_walls = false;

// --- Optical & Absorption Uniforms ---
uniform vec4 shallow_color : source_color = vec4(0.22, 0.65, 0.78, 1.0);
uniform vec4 deep_color : source_color = vec4(0.01, 0.05, 0.16, 1.0);
uniform vec3 absorption_coefficients = vec3(1.4, 0.42, 0.08);
uniform vec3 depth_color_consumption = vec3(22.0, 133.0, 168.0);
uniform float depth_distance : hint_range(0.1, 100.0) = 4.5;
uniform float beers_law : hint_range(0.1, 20.0) = 2.2;
uniform vec4 underwater_ceiling_color : source_color = vec4(0.0, 0.1, 0.2, 1.0);
uniform float underwater_fog_begin : hint_range(0.0, 50.0) = 0.5;
uniform float underwater_fog_end : hint_range(1.0, 200.0) = 28.0;

// --- Subsurface Scattering & Crest Glow Uniforms ---
uniform vec4 crest_color : source_color = vec4(0.0, 0.65, 0.85, 1.0);
uniform float crest_glow_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float aerated_foam_glow : hint_range(0.0, 2.0) = 0.5;

// --- Macro & Meso Wave Cascade Uniforms ---
uniform float wave_amplitude : hint_range(0.0, 5.0) = 0.1;
uniform float wave_length : hint_range(0.25, 100.0) = 4.5;
uniform float wave_speed : hint_range(0.0, 20.0) = 1.4;
uniform float wave_steepness : hint_range(0.0, 2.0) = 0.35;

// --- Interactive Multi-Scale Ripple Ring Buffer ---
uniform vec4 ripples[16];
uniform float ripple_mesh_height : hint_range(0.0, 2.0) = 0.22;
uniform float ripple_size : hint_range(0.1, 10.0) = 1.0;

// --- Surface Micro-Detail & Normal Flow Uniforms ---
uniform sampler2D normal_flow_map : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec2 uv_scale = vec2(2.0, 2.0);
uniform float normal_bump_strength : hint_range(0.0, 8.0) = 2.0;
uniform vec2 pan_speed_1 = vec2(0.1, 0.01);
uniform vec2 pan_speed_2 = vec2(-0.015, 0.025);

// --- Reflection, Refraction & PBR Uniforms ---
uniform bool enable_ssr = true;
uniform float ssr_max_distance : hint_range(0.5, 50.0) = 4.5;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.02;
uniform float chromatic_aberration : hint_range(0.0, 0.1) = 0.02;
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
varying float v_wave_height;
varying float v_wave_crest;
varying float v_foam_factor;
varying float v_fresnel;
varying vec2 v_macro_slope;

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
		float safe_size = max(ripple_size, 0.1);
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
			float exp_speed = (1.15 + scale_f * 0.65) * safe_size;
			float radius = age * exp_speed;
			float sigma = (0.14 + scale_f * 0.28) * safe_size;
			float delta_r = dist - radius;

			if (abs(delta_r) > sigma * 3.5) {
				continue;
			}

			float inv_two_sigma_sq = 1.0 / (2.0 * sigma * sigma);
			float env = exp(-(delta_r * delta_r) * inv_two_sigma_sq);
			float life_ratio = 1.0 - (age / max_age);
			float decay = exp(-age * (1.8 / (0.6 + scale_f * 0.4))) * life_ratio;
			float k_r = (22.0 / (0.35 + scale_f * 0.65)) / safe_size;
			float phase = delta_r * k_r - age * 4.0;

			float eff_amp = min(amp, 2.0) * ripple_mesh_height * env * decay;
			float s_p = sin(phase);
			float c_p = cos(phase);
			total_h += s_p * eff_amp;

			if (dist > 0.0001) {
				vec2 radial_dir = delta_xz / dist;
				float d_dr = eff_amp * (k_r * c_p - s_p * delta_r * 2.0 * inv_two_sigma_sq);
				if (include_micro_harmonics) {
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

// Blends dual-scrolling normal flow maps with procedural multi-band capillary slopes.
vec2 evaluate_micro_normal_slope(vec2 world_xz, float t) {
	vec2 scaled_uv = world_xz * max(uv_scale, vec2(0.05)) * 0.35;
	vec2 uv1 = scaled_uv + pan_speed_1 * t * 4.0;
	vec2 uv2 = scaled_uv * 0.75 + pan_speed_2 * t * 4.5;
	vec2 uv3 = world_xz * 3.8 - vec2(pan_speed_1.y, -pan_speed_2.x) * t * 6.0;

	vec3 norm_a = texture(normal_flow_map, uv1).rgb * 2.0 - 1.0;
	vec3 norm_b = texture(normal_flow_map, uv2).rgb * 2.0 - 1.0;
	vec2 flow_map_slope = (norm_a.xy + norm_b.xy) * 0.65;

	float eps = 0.04;
	float h_c1 = gradient_noise(uv1) * 0.55 + gradient_noise(uv2 * 2.8) * 0.30;
	float h_x1 = gradient_noise(uv1 + vec2(eps, 0.0)) * 0.55
		+ gradient_noise(uv2 * 2.8 + vec2(eps, 0.0)) * 0.30;
	float h_z1 = gradient_noise(uv1 + vec2(0.0, eps)) * 0.55
		+ gradient_noise(uv2 * 2.8 + vec2(0.0, eps)) * 0.30;

	float h_c2 = gradient_noise(uv3) * 0.15;
	float h_x2 = gradient_noise(uv3 + vec2(eps * 2.0, 0.0)) * 0.15;
	float h_z2 = gradient_noise(uv3 + vec2(0.0, eps * 2.0)) * 0.15;

	float tex_c = texture(foam_noise, uv1 * 0.25).r;
	float tex_x = texture(foam_noise, (uv1 + vec2(eps, 0.0)) * 0.25).r;
	float tex_z = texture(foam_noise, (uv1 + vec2(0.0, eps)) * 0.25).r;

	vec2 grad_proc = vec2((h_x1 - h_c1) + (h_x2 - h_c2), (h_z1 - h_c1) + (h_z2 - h_c2)) / eps;
	vec2 grad_tex = vec2(tex_x - tex_c, tex_z - tex_c) * 1.25;
	vec2 combined = grad_proc * 0.55 + grad_tex * 0.20 + flow_map_slope * 1.4;
	return combined * (normal_bump_strength * 0.08);
}

void vertex() {
	v_local_normal = NORMAL;
	vec3 scaled_vertex = VERTEX * water_size;

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
	v_wave_height = wave_data.x;
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
	if (v_is_top_face < 0.5 && !show_side_walls) {
		discard;
	}

	float dist_to_cam = length(v_world_pos - CAMERA_POSITION_WORLD);
	vec3 pixel_wave = evaluate_surface_displacement(v_world_pos.xz, water_time, true);
	vec2 micro_slope = evaluate_micro_normal_slope(v_world_pos.xz, water_time);

	// Attenuate distant normal slopes to prevent specular shimmer and Moire aliasing
	float micro_fade = mix(0.015, 1.0, exp(-dist_to_cam * 0.0175));
	float macro_fade = mix(0.15, 1.0, exp(-dist_to_cam * 0.008));
	vec2 combined_slope = (pixel_wave.yz * macro_fade) + (micro_slope * micro_fade);

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

	// HL2 chromatic aberration refraction with foreground depth-bleed guard
	vec2 refract_offset = NORMAL.xy * refraction_strength * clamp(water_depth_diff * 0.5, 0.0, 1.0);
	vec2 red_uv = clamp(
		SCREEN_UV + refract_offset * (1.0 + chromatic_aberration),
		vec2(0.001),
		vec2(0.999)
	);
	vec2 green_uv = clamp(SCREEN_UV + refract_offset, vec2(0.001), vec2(0.999));
	vec2 blue_uv = clamp(
		SCREEN_UV + refract_offset * (1.0 - chromatic_aberration),
		vec2(0.001),
		vec2(0.999)
	);

	float refracted_raw_depth = texture(depth_texture, green_uv).r;
	vec4 refracted_view = INV_PROJECTION_MATRIX
		* vec4(green_uv * 2.0 - 1.0, refracted_raw_depth, 1.0);
	refracted_view.xyz /= refracted_view.w;
	float refracted_linear_depth = -refracted_view.z;

	if (refracted_linear_depth < surface_linear_depth) {
		red_uv = SCREEN_UV;
		green_uv = SCREEN_UV;
		blue_uv = SCREEN_UV;
		refracted_linear_depth = scene_linear_depth;
	}
	float optical_depth = max(0.0, refracted_linear_depth - surface_linear_depth);
	vec3 screen_col = vec3(
		textureLod(screen_texture, red_uv, 0.0).r,
		textureLod(screen_texture, green_uv, 0.0).g,
		textureLod(screen_texture, blue_uv, 0.0).b
	);

	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float safe_rough = max(roughness, 0.001);
	float nv_inv = clamp(1.0 - ndotv, 0.0001, 1.0);
	float pbr_fresnel = mix(
		pow(nv_inv, 5.0 * exp(-2.69 * safe_rough)) / (1.0 + 22.7 * pow(safe_rough, 1.5)),
		1.0,
		REFLECTANCE
	);
	float custom_fresnel = clamp(
		fresnel_base + (1.0 - fresnel_base) * pow(1.0 - ndotv, fresnel_power),
		0.0,
		1.0
	);
	v_fresnel = clamp(max(pbr_fresnel, custom_fresnel * 0.75), 0.0, 1.0);
	v_foam_factor = 0.0;

	if (!FRONT_FACING) {
		// --- UNDERWATER CEILING & WALLS (Backface): Snell's Window + HL2 Linear Depth Fog ---
		float snell_window = smoothstep(0.52, 0.72, ndotv);
		float ceiling_dist = length(VERTEX);
		float fog_span = max(underwater_fog_end - underwater_fog_begin, 0.1);
		float hl2_fog = clamp((ceiling_dist - underwater_fog_begin) / fog_span, 0.0, 1.0);
		hl2_fog = mix(hl2_fog, hl2_fog * hl2_fog, 0.35);

		vec3 murk_scatter = mix(deep_color.rgb, underwater_ceiling_color.rgb, 0.5);
		vec3 tir_reflection = mix(
			murk_scatter,
			shallow_color.rgb * 0.5 + underwater_ceiling_color.rgb * 0.5,
			0.35
		);
		vec3 refracted_sky = mix(underwater_ceiling_color.rgb, screen_col, 0.8);
		vec3 ceiling_col = mix(tir_reflection, refracted_sky, snell_window);

		ALBEDO = mix(ceiling_col, murk_scatter, hl2_fog);
		ROUGHNESS = clamp(roughness * 1.5, 0.04, 1.0);
		SPECULAR = specular_strength * 0.7;
		METALLIC = metallic * 0.5;
		ALPHA = 1.0;
	} else {
		// --- TOP / EXTERIOR SURFACE (Frontface): Beer-Lambert, RGB Depth, SSR, SSS & Foam ---
		vec3 safe_consumption = max(depth_color_consumption, vec3(0.001));
		vec3 channel_fade = vec3(
			1.0 - smoothstep(0.0, safe_consumption.r, optical_depth),
			1.0 - smoothstep(0.0, safe_consumption.g, optical_depth),
			1.0 - smoothstep(0.0, safe_consumption.b, optical_depth)
		);
		float scaled_depth = optical_depth / max(depth_distance, 0.1);
		vec3 beers_transmittance = exp(-absorption_coefficients * scaled_depth * beers_law);
		vec3 transmittance = beers_transmittance * mix(vec3(1.0), channel_fade, 0.45);
		float depth_murk_factor = exp(-scaled_depth * beers_law);
		vec3 volume_scatter = mix(deep_color.rgb, shallow_color.rgb, depth_murk_factor);

		vec3 absorbed_scene = screen_col * transmittance * 0.85;
		vec3 underwater_col = mix(
			volume_scatter,
			absorbed_scene + volume_scatter * (1.0 - transmittance),
			0.68
		);

		// Raymarched Screen-Space Reflections (SSR) with screen-edge fade
		vec3 refl_col = sky_reflection_tint.rgb;
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
						float ssr_confidence = edge_dist.x * edge_dist.y * (1.0 - float(s) / float(steps));
						refl_col = mix(
							sky_reflection_tint.rgb,
							textureLod(screen_texture, sample_uv, 0.0).rgb,
							ssr_confidence
						);
						break;
					}
				}
			}
		}

		vec3 surface_col = mix(underwater_col, refl_col, v_fresnel * 0.65);

		if (v_is_top_face > 0.5) {
			vec2 foam_uv = v_world_pos.xz * 0.45 + pan_speed_1 * water_time * 2.0;
			float noise_val = texture(foam_noise, foam_uv).r * 0.65
				+ (gradient_noise(v_world_pos.xz * 2.4 - water_time * 0.8) * 0.5 + 0.5) * 0.35;

			float shore_mask = 1.0 - smoothstep(0.0, max(foam_distance, 0.01), water_depth_diff);
			float shore_foam = smoothstep(0.32, 0.68, shore_mask + noise_val * 0.35 * shore_mask);

			float crest_raw = smoothstep(
				crest_foam_threshold,
				crest_foam_threshold + 0.45,
				v_wave_crest
			);
			float crest_foam = crest_raw * smoothstep(0.35, 0.75, noise_val);

			float ripple_slope_mag = length(pixel_wave.yz - v_macro_slope);
			float splash_foam = smoothstep(0.35, 0.85, ripple_slope_mag) * noise_val * 0.6;

			float total_foam = clamp(max(shore_foam, max(crest_foam, splash_foam)), 0.0, 1.0)
				* foam_color.a;
			v_foam_factor = total_foam;

			// Subsurface scattering crest & aerated foam glow
			float wave_crest_mask = smoothstep(0.25, 1.25, v_wave_crest);
			float aerated_mask = smoothstep(0.1, 0.9, total_foam);
			float total_subsurface = clamp(
				(wave_crest_mask * crest_glow_intensity) + (aerated_mask * aerated_foam_glow),
				0.0,
				1.0
			);
			surface_col = mix(surface_col, crest_color.rgb, total_subsurface * 0.55);
			surface_col = mix(surface_col, foam_color.rgb, total_foam);
			ROUGHNESS = clamp(mix(roughness, 0.65, total_foam), 0.04, 1.0);
		} else {
			ROUGHNESS = clamp(roughness, 0.04, 1.0);
		}

		ALBEDO = surface_col;
		SPECULAR = specular_strength;
		METALLIC = metallic;
		ALPHA = (v_is_top_face > 0.5 && !show_side_walls)
			? smoothstep(0.0, 0.25, water_depth_diff)
			: 1.0;
	}
}

float smith_masking_shadowing(in float cos_theta, in float alpha) {
	float clamped_cos = clamp(cos_theta, 0.0001, 0.9999);
	float sin_theta = sqrt(max(1.0 - clamped_cos * clamped_cos, 0.0001));
	float denom = max(alpha * sin_theta, 0.0001);
	float a = clamped_cos / denom;
	float a_sq = a * a;
	return a < 1.6
		? (1.0 - 1.259 * a + 0.396 * a_sq) / max(3.535 * a + 2.181 * a_sq, 0.0001)
		: 0.0;
}

float ggx_distribution(in float cos_theta, in float alpha) {
	float a_sq = max(alpha * alpha, 0.0001);
	float d = 1.0 + (a_sq - 1.0) * cos_theta * cos_theta;
	return a_sq / max(PI * d * d, 0.0001);
}

void light() {
	vec3 halfway = normalize(LIGHT + VIEW + vec3(0.0, 0.0, 0.00001));
	float dot_nl = clamp(dot(NORMAL, LIGHT), 0.0001, 0.9999);
	float dot_nv = clamp(dot(NORMAL, VIEW), 0.0001, 0.9999);
	float safe_rough = max(roughness, 0.04);

	// GGX + Smith microfacet specular reflection
	float light_mask = smith_masking_shadowing(dot_nv, safe_rough);
	float view_mask = smith_masking_shadowing(dot_nl, safe_rough);
	float microfacet_dist = ggx_distribution(clamp(dot(NORMAL, halfway), 0.0, 1.0), safe_rough);
	float geom_atten = 1.0 / max(1.0 + light_mask + view_mask, 0.0001);
	SPECULAR_LIGHT += v_fresnel * microfacet_dist * geom_atten / (4.0 * dot_nv + 0.1)
		* ATTENUATION * LIGHT_COLOR * specular_strength * 2.0;

	// Diffuse + wave-crest subsurface backscatter
	vec3 sss_modifier = crest_color.rgb * 1.5 * crest_glow_intensity;
	float norm_height = clamp(v_wave_height / max(wave_amplitude, 0.05) + 0.4, 0.0, 2.0);
	float sss_height = norm_height
		* pow(max(dot(LIGHT, -VIEW), 0.0), 4.0)
		* pow(clamp(0.5 - 0.5 * dot(LIGHT, NORMAL), 0.0, 1.0), 3.0);
	float sss_near = 0.5 * (dot_nv * dot_nv) * crest_glow_intensity;
	float lambertian = 0.5 * dot_nl;
	vec3 scatter_term = (sss_height + sss_near) * sss_modifier
		/ max(1.0 + light_mask, 0.0001) + vec3(lambertian);
	DIFFUSE_LIGHT += mix(scatter_term, foam_color.rgb, v_foam_factor)
		* (1.0 - v_fresnel) * ATTENUATION * LIGHT_COLOR;
}
