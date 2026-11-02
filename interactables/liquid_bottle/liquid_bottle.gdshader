shader_type spatial;
render_mode cull_disabled, shadows_disabled, depth_draw_always;

instance uniform vec2 coeff = vec2(0.0, 0.0);
instance uniform float vel = 0.0;
instance uniform float fill_amount = 0.5;
instance uniform vec2 size = vec2(0.0393, 0.1308);
instance uniform float glass_thickness = 0.001;
instance uniform float scale = 1.0463;
instance uniform vec4 liquid_color : source_color = vec4(0.05, 0.82, 0.96, 0.45);
instance uniform float held_fade = 0.0;

uniform float wave_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float refraction_strength : hint_range(0.0, 0.25) = 0.045;
uniform float absorption_density : hint_range(0.0, 30.0) = 12.0;
uniform float meniscus_height : hint_range(0.0, 0.5) = 0.08;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.12;
uniform float specular_value : hint_range(0.0, 1.0) = 0.65;

uniform sampler2D waves_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D bubbles_tex : hint_default_black, repeat_enable, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 pos;
varying float rot_scale;
varying vec3 weights;
varying float bubble_glow;

void vertex() {
	// Move vertices inwards to simulate glass wall thickness.
	VERTEX -= glass_thickness * NORMAL;

	// Position inside container rotated to world space relative to node origin.
	mat3 model_rot = mat3(MODEL_MATRIX);
	pos = model_rot * VERTEX;

	// Interpolate between bottle radius (size.x) and half-height (size.y) based on world tilt.
	vec3 world_up_in_model = vec3(0.0, 1.0, 0.0) * model_rot;
	float up_alignment = clamp(abs(world_up_in_model.y), 0.0, 1.0);
	rot_scale = mix(size.x, size.y, up_alignment);

	vec3 world_norm = normalize(model_rot * NORMAL);
	weights = world_norm * world_norm;
}

void fragment() {
	// Sample dual-panning Worley wave noise in container horizontal world coordinates.
	vec2 wave_uv_1 = (2.0 * pos.xz + 0.5 * TIME * vec2(1.0, 1.0)) * scale;
	vec2 wave_uv_2 = (2.0 * pos.xz - 0.5 * TIME * vec2(1.0, 1.0)) * scale;
	float wave_noise_1 = texture(waves_noise, wave_uv_1).r;
	float wave_noise_2 = texture(waves_noise, wave_uv_2).g;

	float slosh_energy = length(coeff);
	float wave_offset = wave_intensity * slosh_energy * (wave_noise_1 + wave_noise_2 - 1.0);
	float tilt_offset = dot(pos.xz, coeff);
	float wave = (wave_offset + tilt_offset) * smoothstep(0.02, 0.2, fill_amount);

	float liquid_line = (fill_amount * 2.0 - 1.0 + wave) * rot_scale;
	if (pos.y > liquid_line) {
		discard;
	}

	// Reconstruct optical thickness from scene depth buffer for Beer-Lambert absorption.
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 bg_ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4 bg_view = INV_PROJECTION_MATRIX * bg_ndc;
	bg_view.xyz /= bg_view.w;
	float optical_dist = clamp(-bg_view.z + VERTEX.z, 0.0, 0.35);

	float foam_band = max(meniscus_height * scale * rot_scale, 0.002);
	float foam = smoothstep(liquid_line - foam_band, liquid_line, pos.y);

	vec3 base_col = liquid_color.rgb;
	vec3 surface_col = base_col;
	float bubbles_total = 0.0;

	if (FRONT_FACING) {
		// Rising carbonation bubbles along side walls using triplanar projection.
		vec2 distortion = vec2(wave_noise_1, wave_noise_2) * 0.015;
		vec2 flow = TIME * vec2(2.0, 0.0);
		float bub_x = smoothstep(
			0.88,
			1.0,
			texture(bubbles_tex, scale * 3.0 * pos.yx + distortion - flow).r
		);
		float bub_y = smoothstep(
			0.88,
			1.0,
			texture(bubbles_tex, scale * 3.0 * pos.yz + distortion - flow).r
		);
		vec2 bubbles = vec2(bub_x, bub_y) * weights.zx * vel;
		bubbles_total = clamp(bubbles.x + bubbles.y, 0.0, 1.0);

		// Meniscus contact ring & agitation foam.
		float rim_foam = foam * clamp(vel * 0.85 + 0.25, 0.0, 1.0);
		vec3 foam_col = mix(base_col, vec3(1.0), rim_foam);
		surface_col = mix(base_col, foam_col, clamp(vel + foam * 0.35, 0.0, 1.0)) + bubbles_total * 0.35;

		vec3 world_foam_n = normalize(vec3(-coeff.x, 1.0, -coeff.y));
		vec3 view_foam_n = normalize((VIEW_MATRIX * vec4(world_foam_n, 0.0)).xyz);
		NORMAL = normalize(mix(NORMAL, view_foam_n, foam * vel * 0.6));
	} else {
		// Top meniscus surface cap (rendered via backfaces below liquid_line).
		float surface_ripples = (wave_noise_1 - wave_noise_2) * 0.15 * clamp(slosh_energy + 0.1, 0.0, 1.0);
		vec3 world_meniscus_n = normalize(
			vec3(-coeff.x + surface_ripples, 1.0, -coeff.y + surface_ripples)
		);
		NORMAL = normalize((VIEW_MATRIX * vec4(world_meniscus_n, 0.0)).xyz);
		surface_col = mix(base_col * 1.12, vec3(1.0), vel * 0.65);
	}

	// Screen-space refraction + Beer-Lambert law absorption when liquid is translucent or held.
	float effective_alpha = clamp(liquid_color.a * (1.0 - held_fade * 0.65), 0.0, 1.0);
	if (effective_alpha < 0.99) {
		vec2 refract_offset = (
			NORMAL.xy * refraction_strength
			- coeff * 0.06
			- vec2(wave_noise_1 - 0.5, wave_noise_2 - 0.5) * 0.012
		);
		vec2 refracted_uv = clamp(SCREEN_UV + refract_offset, vec2(0.002), vec2(0.998));
		float blur_lod = effective_alpha * 2.2;
		vec3 bg_col = textureLod(screen_tex, refracted_uv, blur_lod).rgb;

		// Beer-Lambert transmittance: higher alpha or deeper path absorbs complement colors.
		vec3 absorb_coeff = (
			(vec3(1.0) - base_col) * absorption_density * (0.35 + effective_alpha * 1.65)
		);
		vec3 transmittance = exp(-absorb_coeff * (optical_dist + size.x * 1.5));
		vec3 refracted_liquid = bg_col * transmittance;

		float opacity = clamp(
			effective_alpha + bubbles_total * 0.4 + foam * vel * 0.35,
			0.0,
			1.0
		);
		ALBEDO = mix(refracted_liquid, surface_col, opacity);
	} else {
		ALBEDO = surface_col;
	}

	ROUGHNESS = mix(roughness_value, 0.6, clamp(foam * vel + bubbles_total, 0.0, 1.0));
	SPECULAR = specular_value;
	bubble_glow = bubbles_total;
}

void light() {
	// Standard Lambert diffuse + Alyx-style forward subsurface scattering when held against light.
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float back_dot = dot(-VIEW, LIGHT);
	float scatter = smoothstep(0.0, 1.0, back_dot);
	scatter *= scatter;

	vec3 direct_term = ALBEDO * ndotl * 0.55;
	vec3 scatter_term = max(scatter - bubble_glow * max(back_dot, 0.0), 0.0) * liquid_color.rgb * 1.15;
	DIFFUSE_LIGHT += (direct_term + scatter_term) * ATTENUATION * LIGHT_COLOR;

	// Blinn-Phong wet liquid highlight.
	vec3 half_vec = normalize(VIEW + LIGHT);
	float spec = pow(max(dot(NORMAL, half_vec), 0.0), 48.0) * specular_value;
	SPECULAR_LIGHT += spec * ATTENUATION * LIGHT_COLOR * 0.4;
}
