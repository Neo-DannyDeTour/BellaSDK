shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 telegraph_color : source_color = vec4(0.2, 0.65, 1.0, 1.0);
uniform vec4 active_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float hdr_intensity : hint_range(1.0, 25.0) = 6.5;
uniform float expand_progress : hint_range(0.0, 1.0) = 0.5;
uniform float active_phase : hint_range(0.0, 1.0) = 0.0;
uniform float fade_alpha : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float r = length(centered);
	float angle = atan(centered.y, centered.x);

	float cur_radius = mix(0.12, 0.96, expand_progress);
	float arc_noise = value_noise(vec2(angle * 12.0 + TIME * 6.0, r * 8.0 - TIME * 4.0));
	float ring_dist = abs(r - cur_radius + (arc_noise - 0.5) * 0.06 * (0.4 + active_phase));

	float outer_ring = smoothstep(0.075, 0.008, ring_dist);
	float inner_fill = smoothstep(cur_radius, cur_radius * 0.65, r) * 0.22;

	// Radial crackling spokes during active damage phase
	float spoke_noise = value_noise(vec2(angle * 18.0 - TIME * 12.0, r * 6.0));
	float spokes = smoothstep(0.68, 0.92, spoke_noise) * step(r, cur_radius) * active_phase;

	// Telegraph warning pulse
	float pulse = mix(0.55 + 0.45 * sin(TIME * 14.0), 1.0, active_phase);
	vec3 base_col = mix(telegraph_color.rgb, active_color.rgb, active_phase);
	float energy = (outer_ring * 1.4 + inner_fill + spokes * 1.2) * pulse;

	// Hard clip outside unit disc
	float disc_clip = smoothstep(1.0, 0.96, r);

	ALBEDO = base_col * hdr_intensity * energy;
	ALPHA = clamp(energy, 0.0, 1.0) * disc_clip * fade_alpha;
}
