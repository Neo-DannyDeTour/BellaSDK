shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D displacement_texture : hint_default_black, filter_linear;
uniform sampler2D base_height_noise : hint_default_black, filter_linear_mipmap;

uniform float terrain_height_scale : hint_range(0.0, 5.0) = 0.8;
uniform float max_depression_depth : hint_range(0.0, 1.0) = 0.35;
uniform vec2 ground_dimensions = vec2(20.0, 20.0);

uniform vec4 snow_color : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.24, 0.17, 0.12, 1.0);
uniform float snow_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float dirt_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float dirt_threshold : hint_range(0.0, 1.0) = 0.25;

float get_height(vec2 uv) {
	float base = textureLod(base_height_noise, uv, 0.0).r * terrain_height_scale;
	float deform = textureLod(displacement_texture, uv, 0.0).r * max_depression_depth;
	return base - deform;
}

void vertex() {
	VERTEX.y += get_height(UV);

	// Finite-difference normal calculation matching terrain mounds + craters
	float texel = 2.0 / 1024.0;
	float h_center = get_height(UV);
	float h_right = get_height(UV + vec2(texel, 0.0));
	float h_up = get_height(UV + vec2(0.0, texel));

	float dx = texel * ground_dimensions.x;
	float dz = texel * ground_dimensions.y;

	vec3 tangent = vec3(dx, h_right - h_center, 0.0);
	vec3 bitangent = vec3(0.0, h_up - h_center, dz);
	NORMAL = normalize(cross(bitangent, tangent));
}

void fragment() {
	float depth = texture(displacement_texture, UV).r;
	float blend_factor = smoothstep(dirt_threshold, dirt_threshold + 0.35, depth);

	ALBEDO = mix(snow_color.rgb, dirt_color.rgb, blend_factor);
	ROUGHNESS = mix(snow_roughness, dirt_roughness, blend_factor);
	SPECULAR = mix(0.25, 0.08, blend_factor);
}
