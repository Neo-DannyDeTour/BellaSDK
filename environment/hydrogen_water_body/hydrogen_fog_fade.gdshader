shader_type fog;

uniform float base_density = 0.12;
uniform vec4 albedo : source_color = vec4(0.04, 0.14, 0.24, 1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.03, 0.06, 1.0);
uniform float height_falloff = 0.0;
uniform float edge_fade = 0.15;
uniform sampler3D density_texture : hint_default_white;
uniform bool use_density_texture = false;
uniform vec3 texture_scale = vec3(0.2);

uniform vec3 camera_pos = vec3(0.0);
uniform vec3 camera_forward = vec3(0.0, 0.0, -1.0);
uniform float fade_plane_dist = 3.0;
uniform float near_fog_ratio = 0.45;
uniform float fade_sharpness = 0.35;

void fog() {
	// SDF box-edge attenuation in normalized [-1, 1]UVW space
	vec3 box_pos = abs(UVW * 2.0 - 1.0);
	float max_axis = max(box_pos.x, max(box_pos.y, box_pos.z));
	float edge_atten = 1.0 - smoothstep(1.0 - max(edge_fade, 0.001), 1.0, max_axis);

	// Exponential height falloff from top of volume
	float height_atten = 1.0;
	if (height_falloff > 0.0001) {
		height_atten = exp(-max(1.0 - UVW.y, 0.0) * height_falloff * SIZE.y);
	}

	float tex_mod = 1.0;
	if (use_density_texture) {
		tex_mod = texture(density_texture, WORLD_POSITION * texture_scale).r;
	}

	// Camera-aligned visibility fade plane preserving near-camera murk
	float forward_dist = dot(WORLD_POSITION - camera_pos, normalize(camera_forward));
	float plane_clear = smoothstep(
		fade_plane_dist * (1.0 - fade_sharpness),
		fade_plane_dist * (1.0 + fade_sharpness),
		forward_dist
	);
	float cam_mod = mix(near_fog_ratio, 1.0, plane_clear);

	DENSITY = base_density * edge_atten * height_atten * tex_mod * cam_mod;
	ALBEDO = albedo.rgb;
	EMISSION = emission.rgb;
}
