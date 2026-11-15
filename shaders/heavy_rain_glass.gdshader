shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Heavy rain / refractive glass window shader (3D spatial adaptation).
// Source: FencerDevLog (http://www.youtube.com/watch?v=dabRioRQ97U)

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float zoom : hint_range(1.0, 50.0, 0.01) = 20.0;
uniform float blur : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float fluctuations : hint_range(0.0, 10.0, 0.01) = 5.0;
uniform float size : hint_range(0.1, 100.0, 0.01) = 10.0;
uniform float refraction : hint_range(0.1, 10.0, 0.01) = 10.0;
uniform float density : hint_range(1.0, 5.0, 1.0) = 3.0;
uniform float uv_aspect : hint_range(0.1, 10.0, 0.01) = 1.0;

uniform vec4 tint_color : source_color = vec4(0.88, 0.94, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float normal_strength : hint_range(0.0, 2.0, 0.01) = 0.6;

vec2 hash22(vec2 uv) {
	uv = vec2(dot(uv, vec2(127.1, 311.7)), dot(uv, vec2(269.5, 183.3)));
	return 2.0 * fract(sin(uv) * 43758.5453123) - 1.0;
}

float voronoi_noise(float time, vec2 uv) {
	vec2 grid_uv = fract(uv) - 0.5;
	vec2 grid_coords = floor(uv);
	float min_dist = 100.0;
	for (float y = -1.0; y <= 1.0; y++) {
		for (float x = -1.0; x <= 1.0; x++) {
			vec2 offset = vec2(x, y);
			vec2 pos = cos(hash22(grid_coords + offset) * time * fluctuations) * 0.5 + 0.5;
			min_dist = min(min_dist, length(pos + offset - grid_uv));
		}
	}
	return min_dist;
}

float layers(vec2 uv, float time, float sharpness) {
	float result = 0.0;
	for (float i = 1.0; i <= density; i++) {
		uv -= vec2(0.0, time * i / density);
		float drop = clamp(voronoi_noise(time, uv * i) * 2.0, 0.0, 1.0);
		result += pow(cos(drop * PI) * 0.5 + 0.5, sharpness);
	}
	return result / density;
}

vec3 rainy_window(vec2 uv, float time, float sharpness) {
	float d = 1.0 / refraction;
	float x = layers(uv + vec2(d, 0.0), time, sharpness) - layers(uv + vec2(-d, 0.0), time, sharpness);
	float y = layers(uv + vec2(0.0, d), time, sharpness) - layers(uv + vec2(0.0, -d), time, sharpness);
	return normalize(vec3(x, y, d));
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= uv_aspect;
	float time = TIME * speed;
	vec3 rain = rainy_window(uv * zoom, time, 10.0 / size);

	vec2 refracted_uv = clamp(SCREEN_UV + blur * 0.1 * rain.xy, vec2(0.001), vec2(0.999));
	vec3 bg = textureLod(screen_texture, refracted_uv, blur * 1.5).rgb;

	ALBEDO = bg * tint_color.rgb * 0.15;
	EMISSION = bg * tint_color.rgb * 0.85;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	NORMAL_MAP = rain * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;
}
