shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float threshold : hint_range(-0.2, 1.2, 0.01) = 1.2;
uniform vec4 first_color : source_color = vec4(0.8, 0.4, 0.2, 1.0);
uniform vec4 second_color : source_color = vec4(0.5, 0.0, 0.0, 1.0);

void fragment() {
	vec4 color = texture(screen_texture, SCREEN_UV);
	float gray = (color.r + color.g + color.b) / 3.0;

	if (gray > threshold - 0.2) {
		color = first_color;
		if (gray > threshold - 0.1) {
			color = second_color;
			if (gray > threshold) {
				color = vec4(0.0, 0.0, 0.0, 1.0);
			}
		}
	}

	COLOR = color;
}
