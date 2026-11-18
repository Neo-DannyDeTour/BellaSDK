shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.65;
uniform float metallic : hint_range(0.0, 1.0) = 0.45;
uniform float interior_darken : hint_range(0.0, 1.0) = 0.45;
instance uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	float side_mult = FRONT_FACING ? 1.0 : interior_darken;
	ALBEDO = tex.rgb * tint_color.rgb * side_mult;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}
