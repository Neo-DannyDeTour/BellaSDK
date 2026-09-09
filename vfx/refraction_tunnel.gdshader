shader_type canvas_item;

// --- VIEW SETTINGS ---
group_uniforms view;
uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform float zoom : hint_range(0.1, 10.0, 0.01) = 2.0;
uniform float speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float ir : hint_range(1.0, 3.0, 0.01) = 1.3;

// --- SCENE & FRACTAL SETTINGS ---
group_uniforms scene;
uniform float field_divisor : hint_range(0.1, 20.0, 0.01) = 5.0;
uniform float step_scale : hint_range(0.01, 1.0, 0.01) = 0.1;
uniform float freq_l1 : hint_range(0.1, 10.0, 0.01) = 1.0;
uniform float freq_l2 : hint_range(0.1, 10.0, 0.01) = 2.0;
uniform float freq_l3 : hint_range(0.1, 10.0, 0.01) = 4.0;
uniform float weight_l1 : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float weight_l2 : hint_range(0.0, 2.0, 0.01) = 0.5;
uniform float weight_l3 : hint_range(0.0, 2.0, 0.01) = 0.25;

// --- COLOR & POST-PROCESSING ---
group_uniforms coloring;
uniform vec3 color_tint : source_color = vec3(0.2, 0.5, 1.0);
uniform float contrast : hint_range(0.1, 10.0, 0.01) = 2.0;
uniform float brightness : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform float fade : hint_range(0.0, 2.0, 0.01) = 0.5;

const int octaves = 16;

// Layer function combining trigonometric functions and dot product
float layer(vec3 p) {
	return abs(dot(sin(p), cos(p)));
}

// Scene field evaluation layering multiple frequencies
float scene(vec3 p) {
	float l1 = layer(p * freq_l1) * weight_l1;
	float l2 = layer(p * freq_l2) * weight_l2;
	float l3 = layer(p * freq_l3) * weight_l3;
	return (l1 + l2 + l3) / field_divisor;
}

void fragment() {
	// Center coordinates and aspect ratio correction
	vec2 uv = UV - 0.5;
	uv.x *= resolution.x / resolution.y;
	uv *= zoom;

	float time_val = TIME * speed;

	// Ray direction
	vec3 rd = normalize(vec3(uv, 1.0));

	// Cylinder intersection point
	vec3 p = rd / length(rd.xy);
	p.z += time_val;

	// Simplified cylinder normal calculation
	vec3 normal = normalize(vec3(p.xy, 0.0));

	// Refraction ray vector based on Index of Refraction (IR)
	vec3 ref = refract(rd, normal, 1.0 / ir);

	vec3 ray_pos = p;
	vec3 col = vec3(0.0);

	// Iterative layer accumulation
	for (int i = 0; i < octaves; i++) {
		float d = scene(ray_pos);

		// Advance ray position along the refracted vector
		ray_pos += ref * (d * step_scale);

		// Distance falloff from original intersection
		float dist_p = length(ray_pos - p);

		// Accumulate color density across translucent boundary layers
		col += color_tint * exp(-dist_p * fade) * (d * contrast);
	}

	col *= brightness;
	COLOR = vec4(col, 1.0);
}
