shader_type canvas_item;

// --- View & Simulation Parameters ---
group_uniforms view;
uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform float zoom : hint_range(0.1, 4.0, 0.01) = 1.0;
uniform float speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float contrast : hint_range(1.0, 50.0, 0.01) = 10.0;
uniform float fade : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float bumpiness : hint_range(0.5, 10.0, 0.01) = 3.0;

// --- Color Palette ---
group_uniforms cave_palette;
uniform vec3 color_rock : source_color = vec3(0.02, 0.01, 0.015);
uniform vec3 color_ember : source_color = vec3(0.35, 0.05, 0.02);
uniform vec3 color_flame : source_color = vec3(0.9, 0.25, 0.03);
uniform vec3 color_hot : source_color = vec3(1.0, 0.75, 0.35);
uniform vec3 color_core : source_color = vec3(1.0, 0.97, 0.85);

// --- Color Transitions ---
group_uniforms color_mixing;
uniform float edge_ember : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float edge_flame : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float edge_hot : hint_range(0.0, 1.0, 0.01) = 0.8;
uniform float edge_core : hint_range(0.0, 1.0, 0.01) = 1.0;


mat2 rotate(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}


vec3 palette(float t) {
	vec3 color = mix(color_rock, color_ember, smoothstep(0.0, edge_ember, t));
	color = mix(color, color_flame, smoothstep(edge_ember - 0.05, edge_flame, t));
	color = mix(color, color_hot, smoothstep(edge_flame - 0.25, edge_hot, t));
	color = mix(color, color_core, smoothstep(edge_hot + 0.07, edge_core, t));
	return color;
}


float ray_march(vec2 uv) {
	float steps = 0.0;
	float dist = 0.1;

	for (int i = 0; i < 64; i++) {
		vec3 p = vec3(uv * dist, dist);
		p.z += TIME * speed;

		float sdf = 1.2 - length(p.xy);

		// Fixed octave loop for stable 60 FPS performance
		float a = 2.0;
		for (int j = 0; j < 5; j++) {
			vec3 q = p * a;
			q.xz = rotate(a) * q.xz;
			sdf -= abs(dot(sin(q), vec3(0.333))) / (a * bumpiness);
			a *= 2.0;
		}

		if (sdf < 0.001) {
			break;
		}

		dist += max(sdf * 0.4, 0.02);
		steps += 1.0;
	}
	return max(steps, 1.0);
}


void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= resolution.x / max(resolution.y, 0.001);
	uv *= zoom;

	float march_steps = ray_march(uv);
	float v = clamp(contrast / march_steps, 0.0, 1.0);

	float dark_center = smoothstep(0.0, 0.75, length(uv));
	v *= mix(fade, 1.0, dark_center);

	COLOR = vec4(palette(v), 1.0) * COLOR;
}
