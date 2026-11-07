shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

varying vec3 world_pos;

// 4-slot per-instance impact buffer (xyz = world hit pos, w = ripple progress 0..1).
// Godot instance uniforms forbid matrix types directly; 4 vec4 slots pack into a mat4 in fragment().
instance uniform vec4 hit_slot_0 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 hit_slot_1 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 hit_slot_2 = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform vec4 hit_slot_3 = vec4(0.0, 0.0, 0.0, 1.0);

uniform vec4 energy_color : source_color = vec4(0.2, 0.85, 0.3, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float max_radius : hint_range(0.1, 10.0) = 1.8;
uniform float ring_freq : hint_range(1.0, 40.0) = 16.0;
uniform float warp_strength : hint_range(0.0, 2.0) = 0.35;
uniform float uv_border_fade : hint_range(0.01, 0.5) = 0.12;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv_a = UV * 2.0 + vec2(TIME * 0.15, -TIME * 0.1);
	vec2 uv_b = UV * 3.5 - vec2(TIME * 0.12, TIME * 0.18);
	float n = (texture(noise_tex, uv_a).r + texture(noise_tex, uv_b).r) - 1.0;

	vec2 edge_lo = smoothstep(vec2(0.0), vec2(uv_border_fade), UV);
	vec2 edge_hi = smoothstep(vec2(0.0), vec2(uv_border_fade), 1.0 - UV);
	float border_mask = edge_lo.x * edge_lo.y * edge_hi.x * edge_hi.y;

	mat4 hit_buffer = mat4(hit_slot_0, hit_slot_1, hit_slot_2, hit_slot_3);
	float total_intensity = 0.0;

	for (int i = 0; i < 4; i++) {
		vec4 slot = hit_buffer[i];
		float progress = slot.w;
		if (progress >= 1.0) {
			continue;
		}

		float raw_dist = distance(world_pos, slot.xyz);
		float warped_dist = raw_dist + (n * warp_strength);

		float active_radius = max_radius * mix(0.35, 1.0, progress);
		float outer_mask = 1.0 - smoothstep(active_radius * 0.4, active_radius, warped_dist);
		float inner_mask = smoothstep(0.02, 0.18, warped_dist);

		float wave = sin(warped_dist * ring_freq - progress * 10.0) * 0.5 + 0.5;
		float rings = smoothstep(0.2, 0.95, wave);

		float time_fade = 1.0 - (progress * progress);
		total_intensity += rings * inner_mask * outer_mask * time_fade;
	}

	float intensity = total_intensity * border_mask;
	ALBEDO = energy_color.rgb;
	ALPHA = clamp(intensity * energy_color.a, 0.0, 1.0);
}
