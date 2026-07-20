shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back, unshaded;

uniform vec4 spark_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float core_intensity : hint_range(0.1, 5.0) = 2.0;

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float dist = length(centered_uv);
	float alpha = smoothstep(1.0, 0.0, dist);

	ALBEDO = spark_color.rgb * COLOR.rgb * core_intensity;
	ALPHA = alpha * spark_color.a * COLOR.a;
}
