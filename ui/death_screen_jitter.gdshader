shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float power : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float intensity : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float black_fade : hint_range(0.0, 1.0, 0.01) = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float jitter = hash12(vec2(TIME * 25.0, uv.y)) * 2.0 - 1.0;
	jitter *= step(1.0 - intensity, abs(jitter)) * power * 0.1;
	uv.x += jitter;

	vec4 scene_color = texture(screen_texture, uv);
	COLOR = mix(scene_color, vec4(0.0, 0.0, 0.0, 1.0), black_fade);
}
