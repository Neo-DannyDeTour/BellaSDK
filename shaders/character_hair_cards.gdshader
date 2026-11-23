shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 root_color : source_color = vec4(0.84, 0.82, 0.80, 1.0);
uniform vec4 tip_color : source_color = vec4(0.98, 0.97, 0.95, 1.0);
uniform float alpha_hash_scale : hint_range(0.1, 2.0) = 1.0;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.75;
uniform float roughness_scale : hint_range(0.1, 1.5) = 0.48;
uniform float anisotropy_amount : hint_range(-1.0, 1.0) = 0.55;
uniform float backlit_rim : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 orm = texture(orm_tex, UV).rgb;
	float root_to_tip = clamp(UV.y, 0.0, 1.0);
	vec3 grad_tint = mix(root_color.rgb, tip_color.rgb, root_to_tip);

	ALBEDO = tex.rgb * grad_tint;
	ALPHA = tex.a;
	ALPHA_HASH_SCALE = alpha_hash_scale;
	AO = mix(0.62, 1.0, root_to_tip) * orm.r;
	ROUGHNESS = clamp(orm.g * roughness_scale, 0.24, 0.85);
	METALLIC = 0.0;
	SPECULAR = 0.52;
	ANISOTROPY = anisotropy_amount;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	RIM = backlit_rim;
	RIM_TINT = 0.85;
	BACKLIGHT = vec3(0.18, 0.17, 0.16);
}
