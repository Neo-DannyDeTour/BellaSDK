shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

group_uniforms Noise_And_Flow;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform sampler2D normal_flow_map : hint_normal, repeat_enable, filter_linear;
uniform vec2 flow_speed_primary = vec2(0.04, 0.08);
uniform vec2 flow_speed_secondary = vec2(-0.06, 0.03);
uniform float texture_tiling = 2.0;

group_uniforms Distortion;
uniform float distortion_strength : hint_range(0.0, 0.2, 0.001) = 0.035;
uniform float chromatic_aberration : hint_range(0.0, 0.1, 0.001) = 0.02;

group_uniforms Hiss_Haze;
uniform vec4 hiss_color : source_color = vec4(0.85, 0.08, 0.05, 0.45);
uniform float haze_intensity : hint_range(0.0, 2.0, 0.05) = 0.8;
uniform float depth_softness : hint_range(0.01, 2.0, 0.01) = 0.5;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	vec2 uv_a = UV * texture_tiling + (flow_speed_primary * TIME);
	vec2 uv_b = UV * (texture_tiling * 0.75) + (flow_speed_secondary * TIME);

	vec3 norm_a = texture(normal_flow_map, uv_a).rgb * 2.0 - 1.0;
	vec3 norm_b = texture(normal_flow_map, uv_b).rgb * 2.0 - 1.0;
	vec2 blended_flow = (norm_a.xy + norm_b.xy) * 0.5;

	float noise_val = texture(noise_texture, uv_a + blended_flow * 0.2).r;

	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords.xyz /= view_coords.w;
	float scene_depth = -view_coords.z;
	float frag_depth = -VERTEX.z;
	float depth_fade = clamp((scene_depth - frag_depth) / depth_softness, 0.0, 1.0);

	vec2 offset = blended_flow * distortion_strength * depth_fade;

	vec2 red_uv = SCREEN_UV + offset * (1.0 + chromatic_aberration);
	vec2 green_uv = SCREEN_UV + offset;
	vec2 blue_uv = SCREEN_UV + offset * (1.0 - chromatic_aberration);

	float r = texture(screen_texture, red_uv).r;
	float g = texture(screen_texture, green_uv).g;
	float b = texture(screen_texture, blue_uv).b;
	vec3 background_color = vec3(r, g, b);

	float haze_alpha = clamp(
		noise_val * hiss_color.a * depth_fade * haze_intensity,
		0.0,
		1.0
	);
	vec3 final_rgb = mix(background_color, hiss_color.rgb, haze_alpha);

	ALBEDO = final_rgb;
	ALPHA = 1.0;
}
