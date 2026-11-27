shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 iris_tint : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform float iris_brightness : hint_range(0.5, 2.5) = 1.0;
uniform float iris_scatter_lift : hint_range(0.0, 0.35) = 0.015;
uniform float sclera_lift : hint_range(0.0, 0.2) = 0.005;
uniform float cornea_roughness : hint_range(0.01, 0.35) = 0.03;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 1.0;
uniform float clearcoat_roughness : hint_range(0.01, 0.25) = 0.02;
uniform float parallax_depth : hint_range(0.0, 0.08) = 0.015;
uniform float limbal_darken : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	vec3 view_ts = normalize(vec3(
		dot(VIEW, TANGENT),
		dot(VIEW, BINORMAL),
		max(dot(VIEW, NORMAL), 0.15)
	));
	vec2 centered_uv = UV - vec2(0.5, 0.5);
	float radial = length(centered_uv);
	float iris_mask = 1.0 - smoothstep(0.18, 0.26, radial);
	vec2 uv_shifted = UV - (view_ts.xy / max(view_ts.z, 0.35)) * parallax_depth * iris_mask;
	float shifted_radial = length(uv_shifted - vec2(0.5, 0.5));
	float iris_ring_mask = smoothstep(0.060, 0.088, shifted_radial) * iris_mask;

	vec3 tex_col = texture(albedo_tex, uv_shifted).rgb;
	vec3 iris_col = tex_col * iris_tint.rgb * iris_brightness;
	vec3 col = mix(tex_col, iris_col, iris_ring_mask);
	float limbal_ring = smoothstep(0.16, 0.21, shifted_radial) * (1.0 - smoothstep(0.21, 0.25, shifted_radial));
	col *= 1.0 - limbal_ring * limbal_darken;

	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = col;
	AO = orm.r;
	ROUGHNESS = mix(max(orm.g, 0.12), cornea_roughness, iris_mask);
	METALLIC = 0.0;
	SPECULAR = 0.65;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	BACKLIGHT = col * (0.04 * iris_ring_mask + 0.01 * (1.0 - iris_mask));
	EMISSION = col * (iris_scatter_lift * iris_ring_mask + sclera_lift * (1.0 - iris_mask));
}
