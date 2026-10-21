shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// Shared visual configuration across shield instances.
uniform vec4 base_color : source_color = vec4(0.02, 0.45, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.55, 0.95, 1.0, 1.0);
uniform vec4 hit_color : source_color = vec4(1.0, 0.06, 0.04, 1.0);
uniform float hex_density : hint_range(1.0, 12.0) = 3.8;
uniform float emission_energy : hint_range(0.5, 10.0) = 3.0;
uniform float corner_radius : hint_range(0.02, 1.0) = 0.22;
uniform float border_wave_reach : hint_range(0.02, 0.5) = 0.16;
uniform float border_wave_freq : hint_range(1.0, 20.0) = 5.5;
uniform float border_wave_speed : hint_range(0.5, 10.0) = 3.2;
uniform float hit_ring_max_radius : hint_range(0.5, 6.0) = 2.2;
uniform float hit_ring_width : hint_range(0.05, 0.6) = 0.18;
uniform float scatter_distance : hint_range(0.5, 5.0) = 1.6;

// Per-instance uniforms mutated via set_instance_shader_parameter().
instance uniform vec2 shield_size = vec2(3.0, 2.0);
instance uniform vec2 canvas_size = vec2(3.0, 2.0);
instance uniform vec3 hit_local_pos = vec3(0.0);
instance uniform float hit_progress : hint_range(0.0, 1.0) = 1.0;
instance uniform float shatter_progress : hint_range(0.0, 1.0) = 0.0;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Flat-top regular hexagon SDF.
float sd_hex(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

float sd_rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Evaluates isotropic flat-top hexagon grid in meter-scaled coordinates.
vec4 eval_static_hex(vec2 p_grid) {
	const vec2 s = vec2(1.7320508, 1.0);
	vec4 hC = floor(vec4(p_grid, p_grid - vec2(1.0, 0.5)) / s.xyxy) + 0.5;
	vec4 h = vec4(p_grid - hC.xy * s, p_grid - (hC.zw + 0.5) * s);
	vec4 hex = dot(h.xy, h.xy) < dot(h.zw, h.zw)
		? vec4(h.xy, hC.xy)
		: vec4(h.zw, hC.zw + 0.5);
	float d = sd_hex(hex.xy, 0.45);
	return vec4(d, hex.zw, 1.0);
}

// Evaluates pure hexagonal tiles flying outward, spinning, and shrinking.
vec4 eval_shattered_hex(vec2 p_grid, float progress, vec2 half_extents) {
	const vec2 s = vec2(1.7320508, 1.0);
	vec2 base_cell = floor(p_grid / s);
	float min_d = 10.0;
	vec2 best_id = vec2(0.0);
	float best_life = 0.0;

	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			for (int sub = 0; sub < 2; sub++) {
				vec2 cell_id = base_cell + vec2(float(x), float(y)) + (sub == 1 ? vec2(0.5) : vec2(0.0));
				vec2 orig_center = (cell_id + 0.5) * s;
				vec2 orig_meter = orig_center / hex_density;

				if (sd_rounded_box(orig_meter, half_extents, corner_radius) <= 0.02) {
					vec2 rnd = hash22(cell_id);
					vec2 radial = normalize(orig_meter + (rnd - 0.5) * 0.35 + vec2(0.0001));
					vec2 rand_dir = normalize(rnd * 2.0 - 1.0 + vec2(0.001));
					vec2 fly_dir = normalize(mix(radial, rand_dir, 0.55));
					float speed = mix(0.8, 2.4, fract(rnd.x * 17.3));
					float life = clamp(1.0 - progress * mix(0.95, 1.45, rnd.y), 0.0, 1.0);

					if (life > 0.01) {
						float ease_p = 1.0 - pow(1.0 - progress, 2.2);
						vec2 moved = orig_center + fly_dir * ease_p * speed * scatter_distance * hex_density;
						vec2 rel = p_grid - moved;

						float angle = (rnd.x - 0.5) * ease_p * 10.0;
						float ca = cos(angle);
						float sa = sin(angle);
						rel = mat2(vec2(ca, -sa), vec2(sa, ca)) * rel;
						rel.x /= max(0.28, abs(cos(ease_p * 5.5 + rnd.y * 6.28318)));

						float d = sd_hex(rel, 0.44 * life);
						if (d < min_d) {
							min_d = d;
							best_id = cell_id;
							best_life = life;
						}
					}
				}
			}
		}
	}
	return vec4(min_d, best_id, best_life);
}

void fragment() {
	vec2 pos_m = (UV - 0.5) * canvas_size;
	vec2 half_extents = shield_size * 0.5 - vec2(0.02);

	// Strictly static outer boundary so the shield silhouette never warps.
	float box_d = sd_rounded_box(pos_m, half_extents, corner_radius);
	float clip_mask = 1.0 - smoothstep(0.0, 0.015, box_d);
	float inward_dist = max(0.0, -box_d);

	vec2 p_grid = pos_m * hex_density;
	vec4 hex_data = (shatter_progress > 0.001)
		? eval_shattered_hex(p_grid, shatter_progress, half_extents)
		: eval_static_hex(p_grid);

	float hex_d = hex_data.x;
	vec2 cell_id = hex_data.yz;
	float tile_life = hex_data.w;

	float hex_fill = 1.0 - smoothstep(-0.07, 0.015, hex_d);
	float hex_rim = smoothstep(-0.22, -0.02, hex_d) * hex_fill;

	// Dynamic organic energy pockets across interior cells.
	vec2 cell_rnd = hash22(cell_id);
	vec2 cell_m = cell_id / hex_density;
	float plasma = sin(cell_m.x * 2.5 + TIME * 2.2) * cos(cell_m.y * 2.5 - TIME * 1.8) * 0.5 + 0.5;
	float pulse = sin(TIME * 3.0 + cell_rnd.x * 6.28318) * 0.5 + 0.5;
	float center_hole = smoothstep(0.05, 0.85, length(pos_m / max(half_extents, vec2(0.01))));
	float cell_energy = clamp(
		(plasma * 0.55 + pulse * 0.45) * mix(0.2, 1.0, center_hole),
		0.04,
		1.0
	);

	// Flowing internal border waves: outer edge stays locked while inner white glow undulates.
	float wave_1 = sin(pos_m.x * border_wave_freq + TIME * border_wave_speed)
		* cos(pos_m.y * border_wave_freq - TIME * (border_wave_speed * 0.85));
	float wave_2 = sin((pos_m.x + pos_m.y) * (border_wave_freq * 1.5) - TIME * (border_wave_speed * 1.4));
	float wave_3 = sin(atan(pos_m.y, pos_m.x) * 6.0 + TIME * (border_wave_speed * 1.2));
	float flow = clamp((wave_1 * 0.45 + wave_2 * 0.35 + wave_3 * 0.2) * 0.5 + 0.5, 0.0, 1.0);

	// Crisp static rim line + undulating inner energy band that creeps across edge hexes.
	float dynamic_width = mix(0.025, border_wave_reach, flow * flow);
	float crisp_rim = exp(-inward_dist * 45.0);
	float flowing_inner = exp(-inward_dist / max(dynamic_width, 0.005)) * (0.45 + 0.75 * flow);
	// Modulate with hex pattern so the flowing white border illuminates edge hexes organically.
	float border_glow = (crisp_rim + flowing_inner * mix(0.45, 1.15, hex_fill)) * (1.0 - shatter_progress);

	// Hit effects: 1) Expanding red ring from hit_local_pos, 2) Blinking red border.
	float hit_active = 1.0 - clamp(hit_progress, 0.0, 1.0);
	float dist_to_hit = length(pos_m - hit_local_pos.xy);
	float ring_radius = hit_progress * hit_ring_max_radius;
	float ring_band = max(0.0, 1.0 - abs(dist_to_hit - ring_radius) / max(hit_ring_width, 0.001));
	float core_flash = max(0.0, 1.0 - dist_to_hit / 0.35) * max(0.0, 1.0 - hit_progress * 2.5);
	float red_wave = clamp((ring_band + core_flash) * hit_active, 0.0, 1.0) * (0.5 + 0.8 * hex_rim);

	float edge_blink_osc = abs(sin(hit_progress * 25.1327)) * hit_active;
	float red_edge = border_glow * edge_blink_osc;

	float red_factor = clamp(red_wave * 1.4 + red_edge * 1.5, 0.0, 1.0);
	red_factor = max(red_factor, shatter_progress * (1.0 - tile_life) * 0.9);

	// Hot white-cyan core at the flowing border, deep blue-cyan inside.
	vec3 cyan_col = mix(base_color.rgb, rim_color.rgb, clamp(border_glow * 0.85 + hex_rim * 0.5, 0.0, 1.0));
	cyan_col += vec3(0.45, 0.5, 0.55) * clamp(border_glow - 0.65, 0.0, 1.0);
	vec3 col = mix(cyan_col, hit_color.rgb, red_factor);

	float base_alpha = hex_fill * (0.12 + 0.55 * cell_energy + 0.38 * hex_rim) + border_glow * 0.9;
	float hit_alpha = (red_wave * hex_fill + red_edge) * 0.98;
	float alpha = max(base_alpha, hit_alpha);
	alpha *= tile_life * mix(clip_mask, 1.0, step(0.001, shatter_progress));

	ALBEDO = col * emission_energy;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
