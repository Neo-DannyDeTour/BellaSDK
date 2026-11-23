shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D skin_albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D band_mask_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 nylon_color : source_color = vec4(0.04, 0.04, 0.045, 1.0);
uniform float base_sheer_opacity : hint_range(0.1, 0.95) = 0.52;
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.2;
uniform float fresnel_opacity_boost : hint_range(0.0, 0.6) = 0.42;
uniform float nylon_roughness : hint_range(0.15, 0.95) = 0.62;

void fragment() {
	vec3 skin_col = texture(skin_albedo_tex, UV).rgb;
	float band_mask = texture(band_mask_tex, UV).r;
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, fresnel_power);
	float opacity = clamp(base_sheer_opacity + fresnel * fresnel_opacity_boost + band_mask * 0.45, 0.0, 0.97);

	ALBEDO = mix(skin_col, nylon_color.rgb, opacity);
	ROUGHNESS = mix(nylon_roughness, 0.78, band_mask);
	METALLIC = 0.0;
	SPECULAR = 0.32;
}
