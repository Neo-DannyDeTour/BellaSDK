// Based on https://blog.theknightsofunity.com/make-it-snow-fast-screen-space-snow-shader/
shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D snow_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_3d_texture : repeat_enable, filter_linear_mipmap;

uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wet_amount : hint_range(0.0, 1.0) = 0.0;
uniform float camera_far : hint_range(0.0, 1000.0) = 500.0;
uniform float rain_scale : hint_range(0.0, 100.0) = 50.0;
uniform float rain_speed : hint_range(0.0, 100.0) = 20.0;

float rain_noise(vec3 x, float time) {
	x *= rain_scale;
	x.y += time;
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	vec2 uv = (p.xy + vec2(37.0, 17.0) * p.z) + f.xy;
	float dens = texture(noise_3d_texture, uv / 256.0).x;
	dens = pow(dens, 25.0 - rain_amount * 15.0);
	dens = sin(dens) * 0.2;
	return dens;
}

float rnd(vec2 uv) {
	return texture(noise_3d_texture, uv).r;
}

vec3 adjust_saturation(float sat, vec3 color) {
	float one_minus_sat = 1.0 - sat;
	vec3 luminance = vec3(0.3086, 0.6094, 0.0820) * one_minus_sat;
	mat3 sat_mat = mat3(
		vec3(luminance.x) + vec3(sat, 0.0, 0.0),
		vec3(luminance.y) + vec3(0.0, sat, 0.0),
		vec3(luminance.z) + vec3(0.0, 0.0, sat)
	);
	return clamp(sat_mat * color, 0.0, 1.0);
}

void fragment() {
	vec3 screen_col = texture(screen_texture, SCREEN_UV).rgb;
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
#if defined(RENDERER_COMPATIBILITY)
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
#endif
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float linear_depth = -view_pos.z;

	vec4 world = INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0);
	vec3 world_position = world.xyz;
	vec3 normal_from_depth = normalize(cross(dFdy(world_position), dFdx(world_position)));
	float camera_far_threshold = step(linear_depth, camera_far - 10.0);

	float distribution_snow = 0.5 * rnd(world_position.xz) + normal_from_depth.y;
	distribution_snow = smoothstep(0.75, 1.0, distribution_snow);
	float snow_amount_offset = snow_amount - 0.01 * step(snow_amount, 0.5) + 0.01 * step(0.5, snow_amount);
	distribution_snow *= smoothstep(0.0, rnd(world_position.zx), snow_amount_offset);
	distribution_snow *= camera_far_threshold;

	vec3 snow_color = texture(snow_texture, world_position.xz).rgb;
	vec3 albedo = screen_col;

	float rain_distribution = smoothstep(0.0, 1.0, normal_from_depth.y) * camera_far_threshold;
	float rain = rain_noise(world_position, TIME * rain_speed) * rain_distribution * step(0.01, rain_amount);

	albedo = mix(albedo, snow_color, distribution_snow);
	albedo = mix(
		albedo,
		adjust_saturation(1.0 + wet_amount, albedo) * (1.0 - wet_amount * 0.5) + rain,
		rain_distribution
	);
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
}
