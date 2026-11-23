shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec2 iris_center = vec2(0.5, 0.5);
uniform float iris_radius : hint_range(0.05, 0.48) = 0.23;
uniform float iris_softness : hint_range(0.005, 0.12) = 0.04;

uniform vec4 iris_tint : source_color = vec4(0.88, 0.76, 1.0, 1.0);
uniform vec4 iris_gradient_top : source_color = vec4(0.42, 0.28, 0.68, 1.0);
uniform vec4 iris_gradient_bottom : source_color = vec4(0.96, 0.86, 1.0, 1.0);
uniform float iris_gradient_strength : hint_range(0.0, 1.0) = 0.28;
uniform float iris_emission : hint_range(0.0, 1.0) = 0.24;
uniform float sclera_brightness : hint_range(0.8, 1.4) = 1.04;

uniform float parallax_depth : hint_range(0.0, 0.08) = 0.014;
uniform float limbal_darken : hint_range(0.0, 1.0) = 0.28;

uniform vec2 catchlight_primary_offset = vec2(-0.075, -0.065);
uniform float catchlight_primary_radius : hint_range(0.005, 0.12) = 0.036;
uniform vec2 catchlight_secondary_offset = vec2(0.06, 0.06);
uniform float catchlight_secondary_radius : hint_range(0.003, 0.08) = 0.018;
uniform float catchlight_strength : hint_range(0.0, 1.5) = 0.85;

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
	vec3 base_col = texture(albedo_tex, uv_shifted).rgb;

	float vert_t = clamp((centered_uv.y / max(iris_radius, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 iris_grad = mix(iris_gradient_top.rgb, iris_gradient_bottom.rgb, vert_t);
	vec3 iris_col = base_col * iris_tint.rgb;
	iris_col = mix(iris_col, iris_col * iris_grad * 1.35, iris_gradient_strength);

	vec3 col = mix(base_col * sclera_brightness, iris_col, iris_mask);

	float limbal_ring = smoothstep(iris_radius * 0.72, iris_radius * 0.94, radial)
		* (1.0 - smoothstep(iris_radius * 0.94, outer_edge, radial));
	col *= 1.0 - limbal_ring * limbal_darken;

	float dist_primary = length(centered_uv - catchlight_primary_offset);
	float dist_secondary = length(centered_uv - catchlight_secondary_offset);
	float catch_primary = 1.0 - smoothstep(
		catchlight_primary_radius * 0.68,
		catchlight_primary_radius,
		dist_primary
	);
	float catch_secondary = 1.0 - smoothstep(
		catchlight_secondary_radius * 0.68,
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
	EMISSION = iris_col * (iris_mask * iris_emission)
		+ vec3(1.0) * (catch_mask * catchlight_strength * 0.55);
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float cel_band = smoothstep(-0.1, 0.12, ndotl);
	vec3 eye_diffuse = mix(vec3(0.74, 0.70, 0.80), vec3(1.0), cel_band);
	DIFFUSE_LIGHT += eye_diffuse * LIGHT_COLOR * ATTENUATION * 0.3183;

	vec3 half_vec = normalize(LIGHT + VIEW);
	float ndoth = max(dot(NORMAL, half_vec), 0.0);
	float cornea_spec = smoothstep(0.92, 0.96, ndoth);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * cornea_spec * 0.45 * 0.3183;
}
