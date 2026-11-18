// Shared fog-volume attenuation helpers for fog_fade shaders.

float fog_fade_height_exp(float height_falloff, float rel_height) {
	if (height_falloff <= 0.0001) {
		return 1.0;
	}
	return clamp(exp(-height_falloff * rel_height), 0.0, 1.0);
}

float fog_fade_height_exp2(float height_falloff, float rel_height) {
	return clamp(exp2(-height_falloff * rel_height), 0.0, 1.0);
}

float fog_fade_sdf_pow(float sdf, vec3 box_size, float edge_fade) {
	float min_extent = max(min(min(box_size.x, box_size.y), box_size.z), 0.001);
	float sdf_factor = clamp(-2.0 * sdf / min_extent, 0.0001, 1.0);
	return pow(sdf_factor, max(edge_fade, 0.001));
}

float fog_fade_sdf_linear(float sdf, float edge_fade) {
	return clamp(-sdf / max(edge_fade, 0.0001), 0.0, 1.0);
}

float fog_fade_box_edge(vec3 uvw, float edge_fade) {
	vec3 box_pos = abs(uvw * 2.0 - 1.0);
	float max_axis = max(box_pos.x, max(box_pos.y, box_pos.z));
	return 1.0 - smoothstep(1.0 - max(edge_fade, 0.001), 1.0, max_axis);
}

float fog_fade_plane_ramp(
	vec3 world_pos,
	vec4 fade_plane,
	float fade_sharpness,
	float near_fog_ratio
) {
	vec3 fade_plane_origin = fade_plane.xyz * fade_plane.w;
	float dist_past_plane = dot(world_pos - fade_plane_origin, fade_plane.xyz);
	float plane_ramp = clamp(dist_past_plane * fade_sharpness + 1.0, 0.0, 1.0);
	return mix(near_fog_ratio, 1.0, plane_ramp);
}

float fog_fade_plane_clip(vec3 world_pos, vec4 fade_plane) {
	float plane_dist = dot(world_pos, fade_plane.xyz) + fade_plane.w;
	return smoothstep(-0.35, 0.0, plane_dist);
}

float fog_fade_camera_clear(
	vec3 world_pos,
	vec3 camera_pos,
	vec3 camera_forward,
	float fade_plane_dist,
	float fade_sharpness,
	float near_fog_ratio
) {
	float forward_dist = dot(world_pos - camera_pos, normalize(camera_forward));
	float plane_clear = smoothstep(
		fade_plane_dist * (1.0 - fade_sharpness),
		fade_plane_dist * (1.0 + fade_sharpness),
		forward_dist
	);
	return mix(near_fog_ratio, 1.0, plane_clear);
}
