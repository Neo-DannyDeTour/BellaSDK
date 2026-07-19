shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx, unshaded;

uniform vec4 burst_color : source_color = vec4(0.5, 0.0, 1.0, 1.0);
uniform float edge_softness : hint_range(0.01, 1.0) = 0.5;

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float dist = length(centered_uv);
	float alpha = smoothstep(1.0, 1.0 - edge_softness, dist);

	ALBEDO = burst_color.rgb * COLOR.rgb;
	ALPHA = alpha * burst_color.a * COLOR.a;
}
