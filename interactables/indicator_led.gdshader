shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

instance uniform vec4 led_color : source_color = vec4(0.95, 0.08, 0.08, 1.0);
instance uniform float blink_speed = 0.0;
instance uniform float intensity = 3.0;

void fragment() {
	float pulse = 1.0;
	if (blink_speed > 0.01) {
		pulse = step(0.0, sin(TIME * blink_speed));
	}
	ALBEDO = led_color.rgb * (0.2 + 0.8 * pulse);
	ROUGHNESS = 0.2;
	METALLIC = 0.1;
	EMISSION = led_color.rgb * intensity * pulse;
}
