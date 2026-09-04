shader_type canvas_item;

uniform vec2 rect_size;
uniform vec2 ui_tilt;
uniform float perspective_strength : hint_range(0.0, 0.5) = 0.15;

uniform float sweep_progress = -0.5;
uniform float hover_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float angle : hint_range(0.0, 360.0) = 25.0;
uniform float corner_cut : hint_range(0.0, 64.0) = 14.0;
uniform float bevel_width : hint_range(1.0, 16.0) = 5.0;

uniform vec4 base_color : source_color = vec4(0.08, 0.08, 0.09, 1.0);
uniform vec4 shine_color : source_color = vec4(1.0, 0.95, 0.8, 0.6);
uniform float shine_width : hint_range(0.01, 1.0) = 0.15;
uniform float slab_opacity : hint_range(0.0, 1.0) = 0.95;

uniform sampler2D scratch_texture : hint_default_white, repeat_enable;
uniform sampler2D blood_texture : repeat_enable;
uniform vec2 mouse_pos_uv;
uniform float reveal_radius : hint_range(0.0, 3.0) = 0.25;
uniform float reveal_softness : hint_range(0.0, 1.0) = 0.1;
uniform vec2 blood_offset = vec2(0.0, 0.0);
uniform float blood_scale = 1.0;
uniform sampler2D custom_light_texture;
uniform vec3 flashlight_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float flashlight_energy : hint_range(0.0, 5.0) = 0.8;

uniform bool is_card_mode = false;

void vertex() {
	vec2 safe_rect = max(rect_size, vec2(1.0));
	vec2 pivot = safe_rect / 2.0;
	vec2 offset = VERTEX - pivot;

	float depth = (offset.x / pivot.x) * ui_tilt.x + (offset.y / pivot.y) * ui_tilt.y;
	float perspective = 1.0 - (depth * perspective_strength);

	VERTEX = pivot + (offset * perspective);
}

void fragment() {
	if (!is_card_mode && hover_intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 half_size = rect_size * 0.5;
		vec2 px_coords = UV * rect_size;
		vec2 p = abs(px_coords - half_size);

		float d_x = half_size.x - p.x;
		float d_y = half_size.y - p.y;
		float min_dist = min(d_x, d_y);

		if (corner_cut > 0.001) {
			float d_diag = ((half_size.x + half_size.y - corner_cut) - (p.x + p.y)) * 0.70710678;
			min_dist = min(min_dist, d_diag);
		}

		float outer_mask = smoothstep(-0.5, 0.5, min_dist);

		float bevel_zone = 1.0 - smoothstep(0.0, bevel_width, min_dist);
		vec2 dir_from_center = normalize(px_coords - half_size);
		float light_dot = dot(-dir_from_center, vec2(0.7071, 0.7071));
		float bevel = light_dot * bevel_zone * 0.35;
		vec3 metal_slab = base_color.rgb + vec3(bevel);

		vec3 surface_color = metal_slab;

		if (is_card_mode) {
			// Read clean UV directly: vertex() already applies physical 3D tilt
			vec4 card_tex = texture(blood_texture, UV);
			float card_dim = mix(0.70, 1.0, hover_intensity);
			surface_color = card_tex.rgb * card_dim;
		} else {
			vec2 uv_offset = UV - vec2(0.5);
			float pixel_depth = (uv_offset.x / 0.5) * ui_tilt.x + (uv_offset.y / 0.5) * ui_tilt.y;
			float pixel_perspective = 1.0 - (pixel_depth * perspective_strength);
			vec2 visual_uv = vec2(0.5) + (uv_offset * pixel_perspective);

			float aspect = rect_size.x / rect_size.y;
			vec2 aspect_uv = visual_uv;
			aspect_uv.x *= aspect;

			vec2 aspect_mouse = mouse_pos_uv;
			aspect_mouse.x *= aspect;

			vec2 light_uv = (aspect_uv - aspect_mouse) / max(reveal_radius, 0.001);
			light_uv = (light_uv * 0.5) + 0.5;

			float reveal_mask = 0.0;
			float custom_light_intensity = 0.0;

			if (light_uv.x >= 0.0 && light_uv.x <= 1.0 && light_uv.y >= 0.0 && light_uv.y <= 1.0) {
				custom_light_intensity = texture(custom_light_texture, light_uv).r;
				reveal_mask = custom_light_intensity * hover_intensity;
			}

			vec4 blood_col = texture(blood_texture, (aspect_uv * blood_scale) + blood_offset);
			surface_color = mix(metal_slab, blood_col.rgb, reveal_mask);

			vec3 added_light = flashlight_color * custom_light_intensity * hover_intensity * flashlight_energy;
			surface_color += added_light;
		}

		// Specular sweep glint - strictly driven by hover_intensity
		if (hover_intensity > 0.01) {
			float rad = radians(angle);
			vec2 dir = vec2(cos(rad), sin(rad));
			float dist = abs(dot(UV, dir) - sweep_progress);
			float scratch_val = texture(scratch_texture, UV * 2.0).r;
			float scratch_mod = mix(0.4, 1.2, scratch_val);
			float entrance_shine = smoothstep(shine_width, 0.0, dist) * scratch_mod;

			vec2 centered_mouse = clamp(mouse_pos_uv - vec2(0.5), -0.5, 0.5);
			float glare_pos = 0.5 - (centered_mouse.x * cos(rad) + centered_mouse.y * sin(rad)) * 0.8;
			float persistent_glare = smoothstep(
				0.4, 0.0, abs(dot(UV, dir) - glare_pos)
			) * 0.25 * hover_intensity;

			float total_shine = clamp(
				(entrance_shine * hover_intensity) + persistent_glare, 0.0, 1.0
			);
			surface_color = mix(surface_color, shine_color.rgb, total_shine * shine_color.a);
		}

		float final_alpha = base_color.a * slab_opacity * outer_mask;
		if (!is_card_mode) {
			final_alpha *= hover_intensity;
		}

		COLOR = vec4(surface_color, final_alpha);
	}
}
