shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;

uniform vec2 iris_center = vec2(0.5, 0.5);
uniform float iris_radius : hint_range(0.05, 0.48) = 0.30;
uniform float iris_softness : hint_range(0.005, 0.12) = 0.035;

uniform vec4 iris_tint : source_color = vec4(0.92, 0.84, 1.0, 1.0);
uniform vec4 iris_gradient_top : source_color = vec4(0.40, 0.27, 0.68, 1.0);
uniform vec4 iris_gradient_bottom : source_color = vec4(0.98, 0.90, 1.0, 1.0);
uniform float iris_gradient_strength : hint_range(0.0, 1.0) = 0.34;
uniform float iris_emission : hint_range(0.0, 1.0) = 0.16;
uniform float sclera_brightness : hint_range(0.8, 1.4) = 1.02;
uniform float eye_ambient_lift : hint_range(0.0, 0.5) = 0.06;

uniform float parallax_depth : hint_range(0.0, 0.08) = 0.015;
uniform float limbal_darken : hint_range(0.0, 1.0) = 0.25;

uniform vec2 catchlight_primary_offset = vec2(-0.105, -0.098);
uniform float catchlight_primary_radius : hint_range(0.005, 0.12) = 0.052;
uniform vec2 catchlight_secondary_offset = vec2(0.095, 0.105);
uniform float catchlight_secondary_radius : hint_range(0.003, 0.08) = 0.024;
uniform float catchlight_strength : hint_range(0.0, 1.5) = 0.95;

uniform float cornea_roughness : hint_range(0.01, 0.35) = 0.03;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.95;
uniform float clearcoat_roughness : hint_range(0.01, 0.25) = 0.02;

void fragment() {
	vec3 view_ts = normalize(vec3(
		dot(VIEW, TANGENT),
		dot(VIEW, BINORMAL),
		max(dot(VIEW, NORMAL), 0.2)
	));
	vec2 centered_uv = UV - iris_center;
	float radial = length(centered_uv);
	float outer_edge = iris_radius + iris_softness;
	float iris_mask = 1.0 - smoothstep(iris_radius - iris_softness, outer_edge, radial);

	vec2 uv_shifted = UV - (view_ts.xy / max(view_ts.z, 0.38)) * parallax_depth * iris_mask;
	vec2 shifted_centered = uv_shifted - iris_center;
	float shifted_radial = length(shifted_centered);
	vec3 base_col = texture(albedo_tex, uv_shifted).rgb;

	float vert_t = clamp((shifted_centered.y / max(iris_radius, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 iris_grad = mix(iris_gradient_top.rgb, iris_gradient_bottom.rgb, vert_t);
	vec3 iris_col = base_col * iris_tint.rgb;
	iris_col = mix(iris_col, iris_col * iris_grad * 1.35, iris_gradient_strength);

	vec3 col = mix(base_col * sclera_brightness, iris_col, iris_mask);

	float limbal_ring = smoothstep(iris_radius * 0.76, iris_radius * 0.95, shifted_radial)
		* (1.0 - smoothstep(iris_radius * 0.95, outer_edge, shifted_radial));
	col *= 1.0 - limbal_ring * limbal_darken;

	float dist_primary = length(centered_uv - catchlight_primary_offset);
	float dist_secondary = length(centered_uv - catchlight_secondary_offset);
	float catch_primary = 1.0 - smoothstep(
		catchlight_primary_radius * 0.78,
		catchlight_primary_radius,
		dist_primary
	);
	float catch_secondary = 1.0 - smoothstep(
		catchlight_secondary_radius * 0.78,
		catchlight_secondary_radius,
		dist_secondary
	);
	float catch_mask = clamp((catch_primary + catch_secondary) * iris_mask, 0.0, 1.0);
	col = mix(col, vec3(1.0), catch_mask * clamp(catchlight_strength, 0.0, 1.0));

	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = col;
	AO = orm.r;
	ROUGHNESS = mix(max(orm.g, 0.14), cornea_roughness, iris_mask);
	METALLIC = 0.0;
	SPECULAR = 0.65;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	EMISSION = col * eye_ambient_lift
		+ iris_col * (iris_mask * iris_emission)
		+ vec3(1.0) * (catch_mask * catchlight_strength * 0.45);
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float ndotl_band = smoothstep(-0.12, 0.14, ndotl);
	float shadow_mask = LIGHT_IS_DIRECTIONAL
		? smoothstep(0.10, 0.65, ATTENUATION)
		: 1.0;
	float cel_band = ndotl_band * shadow_mask;
	float floor_wrap = LIGHT_IS_DIRECTIONAL ? 1.0 : max(0.45, smoothstep(-0.85, 0.05, ndotl));
	float atten_diffuse = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	vec3 eye_diffuse = mix(vec3(0.84, 0.80, 0.92) * 0.72 * floor_wrap, vec3(1.0), cel_band);
	vec3 light_col = LIGHT_COLOR * 0.318309886;
	vec3 contrib = eye_diffuse * light_col * atten_diffuse * 0.70;
	vec3 headroom = max(vec3(0.92) - DIFFUSE_LIGHT, vec3(0.0));
	DIFFUSE_LIGHT += contrib * (headroom / (vec3(0.92) + contrib));

	vec3 half_vec = normalize(LIGHT + VIEW);
	float ndoth = max(dot(NORMAL, half_vec), 0.0);
	float cornea_spec = smoothstep(0.95, 0.985, ndoth);
	SPECULAR_LIGHT += light_col * ATTENUATION * cornea_spec * 0.18 * cel_band;
}
