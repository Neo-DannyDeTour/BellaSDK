shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// 0: Off
// 1: Protanopia (Red-blind)
// 2: Deuteranopia (Green-blind)
// 3: Tritanopia (Blue-blind)
// 4: Achromatopsia (Monochrome)
// 5: 4-Way Split Screen Debug (Protanopia | Deuteranopia // Tritanopia | Achromatopsia)
uniform int mode = 0;

// Divider configuration for 4-way split view
uniform bool show_split_lines = true;
uniform vec4 split_line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float split_line_thickness = 0.002;

vec3 apply_protanopia(vec3 c) {
	return vec3(c.r * 0.56667 + c.g * 0.43333, c.r * 0.55833 + c.g * 0.44167, c.b);
}

vec3 apply_deuteranopia(vec3 c) {
	return vec3(c.r * 0.625 + c.g * 0.375, c.r * 0.7 + c.g * 0.3, c.b);
}

vec3 apply_tritanopia(vec3 c) {
	return vec3(
		c.r * 0.95 + c.g * 0.05,
		c.g * 0.43333 + c.b * 0.56667,
		c.g * 0.475 + c.b * 0.525
	);
}

vec3 apply_achromatopsia(vec3 c) {
	float gray = dot(c, vec3(0.299, 0.587, 0.114));
	return vec3(gray);
}

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;

	if (mode == 1) {
		c = apply_protanopia(c);
	} else if (mode == 2) {
		c = apply_deuteranopia(c);
	} else if (mode == 3) {
		c = apply_tritanopia(c);
	} else if (mode == 4) {
		c = apply_achromatopsia(c);
	} else if (mode == 5) {
		// 4-Way Quadrant Split:
		// [Top-Left: Protanopia]       | [Top-Right: Deuteranopia]
		// -----------------------------+--------------------------
		// [Bottom-Left: Tritanopia]    | [Bottom-Right: Achromatopsia]
		if (SCREEN_UV.x < 0.5 && SCREEN_UV.y < 0.5) {
			c = apply_protanopia(c);
		} else if (SCREEN_UV.x >= 0.5 && SCREEN_UV.y < 0.5) {
			c = apply_deuteranopia(c);
		} else if (SCREEN_UV.x < 0.5 && SCREEN_UV.y >= 0.5) {
			c = apply_tritanopia(c);
		} else {
			c = apply_achromatopsia(c);
		}

		// Optional divider crosshair overlay
		if (show_split_lines) {
			if (abs(SCREEN_UV.x - 0.5) < split_line_thickness || abs(SCREEN_UV.y - 0.5) < split_line_thickness) {
				c = split_line_color.rgb;
			}
		}
	}

	COLOR = vec4(c, 1.0);
}
