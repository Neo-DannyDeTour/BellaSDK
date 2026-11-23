shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D reflection_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 glass_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 refl_uv = vec2(1.0 - UV.x, UV.y);
	vec3 reflection = texture(reflection_texture, clamp(refl_uv, 0.001, 0.999)).rgb;

	ALBEDO = reflection * glass_tint.rgb;
}
