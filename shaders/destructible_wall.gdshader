shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform uint removed_lo = 0u;
uniform uint removed_hi = 0u;
uniform bool is_inner = false;
uniform bool has_surface_damage = false;
uniform sampler2D damage_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec2 panel_size = vec2(2.0, 3.0);
uniform float surface_max_depth : hint_range(0.0, 0.08) = 0.025;
uniform vec3 outer_color : source_color = vec3(0.56, 0.56, 0.53);
uniform vec3 inner_color : source_color = vec3(0.38, 0.37, 0.34);
uniform vec3 crater_color : source_color = vec3(0.26, 0.25, 0.23);

varying vec3 v_obj_pos;
varying vec3 v_local_normal;
varying vec3 v_view_local;

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(
			mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x),
			f.y
		),
		mix(
			mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x),
			f.y
		),
		f.z
	);
}

float fbm(vec3 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += value_noise(p) * amp;
		p *= 2.15;
		amp *= 0.5;
	}
	return v;
}

float sample_damage_mask(vec2 uv, float face_sign) {
	vec4 mask_tex = textureLod(damage_mask, uv, 0.0);
	return (face_sign > 0.0) ? mask_tex.r : mask_tex.g;
}

void vertex() {
	uint cid = uint(clamp(round(CUSTOM0.r), 0.0, 63.0));
	uint word = (cid < 32u) ? removed_lo : removed_hi;
	uint shift = (cid < 32u) ? cid : (cid - 32u);
	if ((word & (1u << shift)) != 0u) {
		VERTEX = vec3(0.0);
	}
	v_obj_pos = VERTEX;
	v_local_normal = NORMAL;
	v_view_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz - VERTEX;
}

void fragment() {
	vec2 safe_panel_size = max(panel_size, vec2(0.001));
	float n_len = length(v_local_normal);
	vec3 n_geom = (n_len > 0.0001) ? (v_local_normal / n_len) : vec3(0.0, 0.0, 1.0);
	vec3 n_local = n_geom;
	vec3 sample_pos = v_obj_pos;
	float hit_mask = 0.0;

	if (!is_inner && has_surface_damage && abs(n_geom.z) > 0.5) {
		float face_sign = sign(n_geom.z);
		vec2 base_uv = vec2(
			clamp((v_obj_pos.x / safe_panel_size.x) + 0.5, 0.0, 1.0),
			clamp(1.0 - (v_obj_pos.y / safe_panel_size.y), 0.0, 1.0)
		);
		float start_mask = sample_damage_mask(base_uv, face_sign);
		vec2 hit_uv = base_uv;

		if (start_mask > 0.001 && surface_max_depth > 0.0001) {
			float v_len = length(v_view_local);
			vec3 v_dir = (v_len > 0.0001) ? (v_view_local / v_len) : vec3(0.0, 0.0, face_sign);
			float view_dot = max(face_sign * v_dir.z, 0.2);
			vec2 max_delta_xy = -v_dir.xy * (surface_max_depth / view_dot);
			vec2 max_delta_uv = vec2(
				max_delta_xy.x / safe_panel_size.x,
				-max_delta_xy.y / safe_panel_size.y
			);

			float prev_h = 0.0;
			vec2 prev_uv = base_uv;
			float prev_mask = start_mask;

			for (int i = 1; i <= 8; i++) {
				float curr_h = float(i) * 0.125;
				vec2 curr_uv = clamp(base_uv + max_delta_uv * curr_h, vec2(0.0), vec2(1.0));
				float curr_mask = sample_damage_mask(curr_uv, face_sign);
				if (curr_h >= curr_mask) {
					float before = max(prev_mask - prev_h, 0.0);
					float after = max(curr_h - curr_mask, 0.0);
					float denom = before + after;
					float t = (denom > 0.0001) ? (before / denom) : 1.0;
					hit_uv = mix(prev_uv, curr_uv, t);
					break;
				}
				prev_h = curr_h;
				prev_uv = curr_uv;
				prev_mask = curr_mask;
				hit_uv = curr_uv;
			}
		}

		hit_mask = sample_damage_mask(hit_uv, face_sign);
		if (hit_mask > 0.001 && surface_max_depth > 0.0001) {
			vec2 uv_shift = hit_uv - base_uv;
			sample_pos += vec3(
				uv_shift.x * safe_panel_size.x,
				-uv_shift.y * safe_panel_size.y,
				-face_sign * hit_mask * surface_max_depth
			);

			vec2 tex_res = max(vec2(textureSize(damage_mask, 0)), vec2(64.0));
			vec2 eps_uv = vec2(1.0) / tex_res;
			float m_xp = sample_damage_mask(
				clamp(hit_uv + vec2(eps_uv.x, 0.0), vec2(0.0), vec2(1.0)), face_sign
			);
			float m_xn = sample_damage_mask(
				clamp(hit_uv - vec2(eps_uv.x, 0.0), vec2(0.0), vec2(1.0)), face_sign
			);
			float m_yp = sample_damage_mask(
				clamp(hit_uv - vec2(0.0, eps_uv.y), vec2(0.0), vec2(1.0)), face_sign
			);
			float m_yn = sample_damage_mask(
				clamp(hit_uv + vec2(0.0, eps_uv.y), vec2(0.0), vec2(1.0)), face_sign
			);

			float dmask_dx = (m_xp - m_xn) / (2.0 * eps_uv.x * safe_panel_size.x);
			float dmask_dy = (m_yp - m_yn) / (2.0 * eps_uv.y * safe_panel_size.y);
			float depth_scale = surface_max_depth * 2.0;
			n_local = normalize(vec3(dmask_dx * depth_scale, dmask_dy * depth_scale, face_sign));
		}
	}

	vec3 p = sample_pos * 24.0;
	float pores = fbm(p);
	float macro_grime = fbm(sample_pos * 4.2 + vec3(3.1, 7.4, 1.9));
	float agg_speck = value_noise(sample_pos * 64.0 + vec3(5.3, 2.7, 9.1));

	float bump_eps = 0.03;
	float bx = fbm(p + vec3(bump_eps, 0.0, 0.0)) - pores;
	float by = fbm(p + vec3(0.0, bump_eps, 0.0)) - pores;
	float bz = fbm(p + vec3(0.0, 0.0, bump_eps)) - pores;
	vec3 pore_grad = vec3(bx, by, bz) / bump_eps;
	vec3 surf_grad = pore_grad - n_local * dot(pore_grad, n_local);

	float crater_blend = smoothstep(0.02, 0.45, hit_mask);
	float bump_strength = is_inner ? 0.055 : mix(0.02, 0.06, crater_blend);
	n_local = normalize(n_local - surf_grad * bump_strength);

	vec3 col;
	float rough;
	float spec;

	if (is_inner) {
		float agg_blend = smoothstep(0.25, 0.80, pores * 0.65 + agg_speck * 0.45);
		col = mix(inner_color * 0.72, inner_color * 1.18, agg_blend);
		col *= mix(0.88, 1.06, macro_grime);
		rough = mix(0.98, 0.86, pores);
		spec = 0.12;
	} else {
		float outer_var = smoothstep(0.22, 0.78, pores * 0.6 + macro_grime * 0.45);
		vec3 outer_col = mix(outer_color * 0.82, outer_color * 1.06, outer_var);
		float outer_rough = mix(0.94, 0.80, pores);

		float crater_var = smoothstep(0.2, 0.85, pores * 0.55 + agg_speck * 0.55);
		vec3 crater_col = mix(crater_color * 0.72, crater_color * 1.22, crater_var);
		float crater_rough = mix(0.99, 0.89, pores);

		col = mix(outer_col, crater_col, crater_blend);
		rough = mix(outer_rough, crater_rough, crater_blend);
		spec = mix(0.18, 0.10, crater_blend);
	}

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	SPECULAR = spec;
	NORMAL = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * n_local));
}
