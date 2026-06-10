shader_type spatial;
// Unshaded is very cheap for 60 FPS goals.
// Cull disabled allows viewing from both sides.
// Billboard keeps it facing the player if you use a Quad Mesh.
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform float speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float octaves : hint_range(1.0, 10.0, 1.0) = 5.0;
uniform float density : hint_range(1.0, 50.0, 0.01) = 5.0;
uniform float cut : hint_range(0.1, 10.0, 0.01) = 2.0;
// Matched to the cyan/blue hue from the video
uniform vec3 color : source_color = vec3(0.5, 1.0, 1.0); 
uniform float brightness : hint_range(0.0, 10.0, 0.01) = 1.5;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0; 
uniform float smoothness : hint_range(1.0, 1000.0, 0.1) = 100.0;

const float S = 0.36602540378;
const float U = 0.2113248654;

vec2 hash22(vec2 uv) {
	uv = vec2(dot(uv, vec2(127.1, 311.7)), dot(uv, vec2(269.5, 183.3)));
	return 2.0 * fract(sin(uv / smoothness) * 43758.5453123) - 1.0;
}

float noise(vec2 uv) {
	vec2 i = floor(uv + (uv.x + uv.y) * S);
	vec2 a = uv - i + (i.x + i.y) * U;
	vec2 m = step(a.yx, a.xy);
	vec2 b = a - m + U;
	vec2 c = a - 1.0 + 2.0 * U;
	
	vec3 h = max(0.5 - vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
	// Replaced pow(h, 4.0) with multiplication for optimization
	vec3 h2 = h * h;
	vec3 h4 = h2 * h2; 
	vec3 n = h4 * vec3(dot(a, hash22(i)), dot(b, hash22(i + m)), dot(c, hash22(i + 1.0)));
	
	return dot(n, vec3(70.0));
}

float fbm(vec2 uv) {
	float f = 0.0;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	float amp = 0.5;
	for (float i = 0.0; i < octaves; i++) {
		f += amp * noise(uv);
		uv = m * uv;
		amp *= 0.5;
	}
	return f * 0.5 + 0.6;
}

float water_layer(vec2 uv, float t, float power) {
	float flow = power * t + abs(uv.y);
	return fbm(uv * power - vec2(0.0, flow));
}

void fragment() {
	vec2 uv = UV - 0.5;
	float t = TIME * speed;
	float fluctuations = abs(sin(t));
	
	float n = water_layer(uv, t, density);
	float layer2 = water_layer(uv, t, density * 5.0);
	
	if (layer2 > 0.001) {
		n += n / layer2;
	}
	
	// Optimized exponent math
	float fluc2 = fluctuations * fluctuations;
	float fluc4 = fluc2 * fluc2;
	float fluc5 = fluc4 * fluctuations;
	
	n *= (4.0 + fluc5) * 0.1;
	
	vec2 elliptical = vec2(cut + uv.y * 1.5, 0.75);
	float silhouette = max(0.0, length(uv * elliptical) - n * max(0.0, uv.y + 0.25));
	
	float abs_y = max(abs(uv.y), 0.001);
	float mask = 1.0 - (10.0 / abs_y) * silhouette;
	
	float water = n * mask * (1.05 - uv.y);
	water += sin(water * PI) * 0.5;
	water *= 0.9 - (uv.y * uv.y);
	
	// Optimized pow(water, 4.0)
	float water2 = water * water;
	float water4 = water2 * water2;
	
	vec3 rgb = water4 * color * brightness;
	
	// Optimized pow(abs(uv.y), 10.0)
	float y2 = uv.y * uv.y;
	float y4 = y2 * y2;
	float y8 = y4 * y4;
	float y10 = y8 * y2;
	
	float a = mask * (1.0 - y10);
	
	ALBEDO = rgb;
	// Multiply the calculated alpha 'a' by your new opacity parameter
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}