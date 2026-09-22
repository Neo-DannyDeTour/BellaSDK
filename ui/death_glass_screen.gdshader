shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center = vec2(0.0);
uniform vec2 box_size = vec2(1.05, 1.05);
uniform float box_radius : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float border_weight : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform vec3 border_color : source_color = vec3(1.0);
uniform float lens_strength : hint_range(0.0, 10.0, 0.01) = 2.0;
uniform float chromatic_spread : hint_range(0.0, 2.0, 0.01) = 0.0;
uniform float lens_curve : hint_range(0.0, 2.0, 0.01) = 0.15;
uniform float distortion_mix : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float black_fade : hint_range(0.0, 1.0, 0.01) = 0.0;

// Exact 2D rounded box SDF with analytical gradient.
vec3 box_with_gradient(vec2 p, vec2 b) {
	vec2 w = abs(p) - b;
	vec2 s = vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
	float g = max(w.x, w.y);
	vec2 q = max(w, vec2(0.0));
	float l = length(q);
	return vec3(
		(g > 0.0) ? l : g,
		s * ((g > 0.0) ? (q / l) : ((w.x > w.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0)))
	);
}

void fragment() {
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = resolution.x / resolution.y;
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= aspect;
	uv -= center;

	vec2 half_extents = box_size * vec2(aspect, 1.0) * 0.5;
	vec3 box = box_with_gradient(uv, half_extents - vec2(box_radius));
	box.x -= box_radius;

	vec3 color = vec3(0.0);

	if (box.x < 0.0) {
		float factor = max(-box.x, 0.0001);
		float str_r = max(lens_strength - chromatic_spread, 0.0);
		float str_g = max(lens_strength, 0.0);
		float str_b = max(lens_strength + chromatic_spread, 0.0);

		vec2 dist_r = (SCREEN_UV - 0.5) * pow(factor * str_r, lens_curve) + 0.5;
		vec2 dist_g = (SCREEN_UV - 0.5) * pow(factor * str_g, lens_curve) + 0.5;
		vec2 dist_b = (SCREEN_UV - 0.5) * pow(factor * str_b, lens_curve) + 0.5;

		vec2 uv_r = mix(SCREEN_UV, dist_r, distortion_mix);
		vec2 uv_g = mix(SCREEN_UV, dist_g, distortion_mix);
		vec2 uv_b = mix(SCREEN_UV, dist_b, distortion_mix);

		color = vec3(
			texture(screen_texture, uv_r).r,
			texture(screen_texture, uv_g).g,
			texture(screen_texture, uv_b).b
		);
	} else {
		color = texture(screen_texture, SCREEN_UV).rgb;
	}

	if (border_weight > 0.0) {
		float w = abs(dot(dFdx(SCREEN_UV), box.yz)) + abs(dot(dFdy(SCREEN_UV), box.yz));
		float border = smoothstep(-w, w, border_weight * 0.01 - abs(box.x));
		color = mix(color, border_color, border);
	}

	color = mix(color, vec3(0.0), clamp(black_fade, 0.0, 1.0));
	COLOR = vec4(color, 1.0);
}
