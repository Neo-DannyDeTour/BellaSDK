shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 spark_color : source_color = vec4(5.5, 2.4, 0.5, 1.0);

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float radial = clamp(1.0 - dot(centered, centered), 0.0, 1.0);
	float core = pow(radial, 2.2);

	ALBEDO = spark_color.rgb * core * COLOR.rgb;
	ALPHA = core * COLOR.a;
}
