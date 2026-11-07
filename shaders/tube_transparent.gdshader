shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform vec4 albedo_color : source_color = vec4(0.7, 0.85, 1.0, 1.0);
instance uniform float metallic : hint_range(0.0, 1.0) = 0.0;
instance uniform float roughness : hint_range(0.0, 1.0) = 0.12;
instance uniform float alpha : hint_range(0.0, 1.0) = 0.3;
instance uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;

instance uniform vec4 liquid_color : source_color = vec4(0.1, 0.75, 0.4, 0.9);
instance uniform float liquid_fill : hint_range(0.0, 1.0) = 0.0;
instance uniform float flow_speed : hint_range(-10.0, 10.0) = 1.5;
instance uniform float wall_rim : hint_range(0.05, 0.8) = 0.35;
instance uniform float path_length : hint_range(0.01, 100.0) = 2.0;

// Procedural 2D hash for zero-texture foam/bubble noise
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth value noise
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, fresnel_power);

	// Outer plastic shell rim mask: grazing angles show only clear tube wall
	float core_mask = smoothstep(wall_rim, wall_rim + 0.15, ndotv);

	// CSGPolygon3D maps UV.x along path distance (when path_u_distance = 1.0)
	float norm_dist = clamp(UV.x / max(path_length, 0.001), 0.0, 1.0);

	// Scrolling coordinates along tube axis (UV.x) and circumference (UV.y)
	vec2 flow_uv = vec2(UV.x * 3.5 - TIME * flow_speed, UV.y * 6.0);
	float n1 = value_noise(flow_uv);
	float n2 = value_noise(flow_uv * 2.3 + vec2(TIME * flow_speed * 0.5, 1.7));
	float pattern = n1 * 0.65 + n2 * 0.35;

	// Wavy meniscus front at the fill threshold
	float wave_edge = (n1 - 0.5) * 0.03;
	float fill_mask = smoothstep(
		liquid_fill + wave_edge,
		liquid_fill + wave_edge - 0.025,
		norm_dist
	) * step(0.001, liquid_fill);

	float meniscus_foam = smoothstep(0.03, 0.0, abs(norm_dist - (liquid_fill + wave_edge)))
		* step(0.001, liquid_fill) * step(liquid_fill, 0.999);

	float bubbles = smoothstep(0.72, 0.88, pattern);
	float liquid_presence = core_mask * fill_mask;

	vec3 fluid_rgb = mix(
		liquid_color.rgb * 0.85,
		liquid_color.rgb * 1.35,
		pattern
	);
	fluid_rgb = mix(fluid_rgb, vec3(1.0), clamp(bubbles * 0.45 + meniscus_foam * 0.8, 0.0, 1.0));

	float shell_alpha = clamp(alpha + fresnel * (1.0 - alpha), 0.0, 1.0);
	float combined_alpha = max(shell_alpha, liquid_presence * liquid_color.a);

	ALBEDO = mix(albedo_color.rgb, fluid_rgb, liquid_presence);
	METALLIC = mix(metallic, 0.0, liquid_presence);
	ROUGHNESS = mix(roughness, 0.25, liquid_presence);
	SPECULAR = 0.6;
	EMISSION = fluid_rgb * liquid_presence * 0.2;
	ALPHA = combined_alpha;
}
