// AAA Physically Based Rain, Wetness, Puddles & Snow Surface Shader for Godot 4.7+
// References:
// 1. Sebastien Lagarde - Water Drop 3B: Physically Based Wet Surfaces
// 2. Ben Cloward - Rain Ripples, Droplets & Heightmap Puddle Accumulation
// 3. DeepSpaceBanana - Rainy Surface Shader (Streaks & Slope Flow)
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms BaseMaterial;
uniform sampler2D Material_Albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D Material_Norm : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D Material_Rough : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D Material_Metal : hint_default_black, repeat_enable, filter_linear_mipmap;
uniform sampler2D Material_Height : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float scale_UV_material : hint_range(0.01, 20.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms WetnessAndPorosity;
uniform float wet_level : hint_range(0.0, 1.0) = 0.65;
uniform float porosity_strength : hint_range(0.0, 1.0) = 0.85;
uniform float wet_darkening : hint_range(0.0, 1.0) = 0.8;
uniform float water_roughness : hint_range(0.0, 0.5) = 0.06;
uniform float water_specular : hint_range(0.0, 1.0) = 0.75;
uniform float water_metallnes : hint_range(0.0, 1.0) = 0.0;

group_uniforms RainAndAngles;
uniform float rain_amount : hint_range(0.0, 1.0) = 0.8;
uniform bool rain = true;
uniform float scale_UV_rain : hint_range(0.1, 100.0) = 5.0;
uniform bool world_space_rain_uv = false;
uniform float dry_angle : hint_range(-1.0, 1.0) = -0.15;
uniform float streaks_angle : hint_range(0.0, 1.0) = 0.85;
uniform float puddle_angle : hint_range(0.5, 1.0) = 0.92;
uniform float angle_blend_softness : hint_range(0.02, 0.4) = 0.12;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

group_uniforms DropletsAndStreaks;
uniform sampler2D drops_tex : repeat_enable, filter_linear_mipmap;
uniform float drops_size : hint_range(0.1, 5.0) = 1.0;
uniform float drops_speed : hint_range(0.0, 5.0) = 1.0;
uniform float drops_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float static_drops_amount : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D streaks_tex : repeat_enable, filter_linear_mipmap;
uniform float streaks_length : hint_range(0.0, 1.0) = 0.65;
uniform float streaks_speed : hint_range(0.0, 5.0) = 1.0;
uniform float streaks_intensity : hint_range(0.0, 2.0) = 1.0;

group_uniforms PuddlesAndRipples;
uniform float puddle_coverage : hint_range(0.0, 1.0) = 0.7;
uniform float puddle_cavity_depth : hint_range(0.0, 1.0) = 0.65;
uniform bool puddles_noise = true;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D puddles_tex : hint_default_black, repeat_enable, filter_linear_mipmap;
uniform sampler2D ripples_tex : repeat_enable, filter_linear_mipmap;
uniform float ripple_density : hint_range(0.02, 1.0) = 0.15;
uniform float ripple_speed : hint_range(0.0, 4.0) = 1.0;
uniform float ripple_intensity : hint_range(0.0, 2.0) = 1.0;

group_uniforms RoofOcclusion;
uniform bool use_roof_occlusion = true;
uniform sampler2D roofing_height : hint_default_black, repeat_disable, filter_linear;
uniform vec3 cam_heightmap_world_position = vec3(0.0, 20.0, 0.0);
uniform float cam_heightmap_size : hint_range(1.0, 100.0) = 30.0;
uniform float occlusion_bias : hint_range(0.01, 2.0) = 0.25;

group_uniforms Snow;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float without_snow_angle : hint_range(0.0, 1.0) = 0.3;
uniform float snow_brightness : hint_range(0.05, 1.0) = 0.85;
uniform sampler2D snow_norm : hint_normal, repeat_enable, filter_linear_mipmap;

varying vec3 v_world_pos;
varying vec3 v_sample_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_sample_pos = world_space_rain_uv ? v_world_pos : (mat3(MODEL_MATRIX) * VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_normal(vec3 rgb, float strength) {
	vec3 n = rgb * 2.0 - 1.0;
	n.xy *= strength;
	return normalize(n);
}

vec3 pack_normal(vec3 n) {
	return normalize(n) * 0.5 + 0.5;
}

vec3 blend_rnm(vec3 base_unpacked, vec3 detail_unpacked, float weight) {
	vec2 d_xy = detail_unpacked.xy * weight;
	return normalize(vec3(base_unpacked.xy + d_xy, base_unpacked.z * detail_unpacked.z));
}

vec3 adjust_saturation(float sat, vec3 color) {
	float one_minus_sat = 1.0 - sat;
	vec3 luminance = vec3(0.3086, 0.6094, 0.0820) * one_minus_sat;
	mat3 sat_matrix = mat3(
		vec3(luminance.x) + vec3(sat, 0.0, 0.0),
		vec3(luminance.y) + vec3(0.0, sat, 0.0),
		vec3(luminance.z) + vec3(0.0, 0.0, sat)
	);
	return clamp(sat_matrix * color, 0.0, 1.0);
}

float sample_roof_exposure(vec3 world_pos) {
	if (!use_roof_occlusion) {
		return 1.0;
	}
	vec2 roof_uv = (world_pos.xz - cam_heightmap_world_position.xz) / cam_heightmap_size + 0.5;
	float in_bounds = step(0.0, roof_uv.x) * step(roof_uv.x, 1.0) * step(0.0, roof_uv.y) * step(roof_uv.y, 1.0);
	if (in_bounds < 0.5) {
		return 1.0;
	}
	// 5-tap PCF soft edge sampling on roof heightmap
	vec2 texel = vec2(1.0 / 256.0);
	float h0 = texture(roofing_height, roof_uv).g;
	float h1 = texture(roofing_height, roof_uv + vec2(texel.x, 0.0)).g;
	float h2 = texture(roofing_height, roof_uv - vec2(texel.x, 0.0)).g;
	float h3 = texture(roofing_height, roof_uv + vec2(0.0, texel.y)).g;
	float h4 = texture(roofing_height, roof_uv - vec2(0.0, texel.y)).g;

	float occ0 = step(world_pos.y, h0 - occlusion_bias);
	float occ1 = step(world_pos.y, h1 - occlusion_bias);
	float occ2 = step(world_pos.y, h2 - occlusion_bias);
	float occ3 = step(world_pos.y, h3 - occlusion_bias);
	float occ4 = step(world_pos.y, h4 - occlusion_bias);
	float occluded = (occ0 * 2.0 + occ1 + occ2 + occ3 + occ4) / 6.0;
	return 1.0 - occluded * in_bounds;
}

vec4 evaluate_droplets(vec2 uv, float time, float active_rain) {
	vec4 tex = texture(drops_tex, uv * drops_size);
	vec3 drop_norm = vec3(tex.rg, 1.0);

	float static_mask = (1.0 - step(0.1, tex.a)) * static_drops_amount;
	float phase = fract((tex.b * 2.0 - 1.0) - time * 0.25 * drops_speed);
	float dyn_mask = step(0.9, tex.a) * phase * active_rain;

	vec3 n_static = mix(vec3(0.5, 0.5, 1.0), drop_norm, static_mask);
	vec3 n_dyn = mix(vec3(0.5, 0.5, 1.0), drop_norm, phase);
	vec3 combined_rgb = mix(n_static, n_dyn, dyn_mask);
	float combined_a = clamp(static_mask * clamp(active_rain * 1.5, 0.0, 1.0) + dyn_mask, 0.0, 1.0);
	return vec4(normalize(combined_rgb), combined_a);
}

vec4 evaluate_streaks(vec2 streak_uv, float time, float streak_zone, float active_rain) {
	vec4 tex = texture(streaks_tex, streak_uv);
	vec3 streak_norm = vec3(tex.rg, 1.0);
	float scroll_v = streak_uv.y + time * 0.2 * streaks_speed;
	float flow_grad = texture(streaks_tex, vec2(streak_uv.x, scroll_v)).b;
	float threshold = 0.72 - 0.35 * streaks_length * active_rain;
	float mask = tex.a * streak_zone * clamp(flow_grad - threshold, 0.0, 1.0);
	mask = smoothstep(0.0, 0.2, mask) * active_rain;
	return vec4(normalize(streak_norm), mask);
}

vec4 evaluate_ripples(vec2 uv, float time, float active_rain) {
	vec2 r_uv = uv * ripple_density;
	vec4 c1 = texture(ripples_tex, r_uv);
	vec4 c2 = texture(ripples_tex, r_uv * vec2(1.0, -1.0) + vec2(0.37, 0.19));
	vec4 c3 = texture(ripples_tex, r_uv * vec2(-1.0, 1.0) + vec2(0.71, 0.63));
	vec4 c4 = texture(ripples_tex, r_uv * vec2(-1.0, -1.0) + vec2(0.13, 0.89));

	float t_base = time * 0.5 * ripple_speed;
	float t1 = fract(t_base + (c1.b * 2.0 - 1.0));
	float t2 = fract(t_base + 0.25 + (c2.b * 2.0 - 1.0));
	float t3 = fract(t_base + 0.5 + (c3.b * 2.0 - 1.0));
	float t4 = fract(t_base + 0.75 + (c4.b * 2.0 - 1.0));

	float waves = 3.0;
	float a1 = smoothstep(0.0, 0.8, sin(clamp((t1 - 1.0 + c1.a) * 20.0, 0.0, waves) * 6.28318) * (1.0 - t1));
	float a2 = smoothstep(0.0, 0.8, sin(clamp((t2 - 1.0 + c2.a) * 20.0, 0.0, waves) * 6.28318) * (1.0 - t2));
	float a3 = smoothstep(0.0, 0.8, sin(clamp((t3 - 1.0 + c3.a) * 20.0, 0.0, waves) * 6.28318) * (1.0 - t3));
	float a4 = smoothstep(0.0, 0.8, sin(clamp((t4 - 1.0 + c4.a) * 20.0, 0.0, waves) * 6.28318) * (1.0 - t4));

	vec4 r = vec4(c1.rg, 1.0, a1);
	r = mix(r, vec4(c2.rg, 1.0, a2), a2);
	r = mix(r, vec4(c3.rg, 1.0, a3), a3);
	r = mix(r, vec4(c4.rg, 1.0, a4), a4);
	r.rgb = normalize(r.rgb);
	r.a *= active_rain;
	return r;
}

void fragment() {
	vec3 world_norm = normalize(v_world_normal);
	float ny = world_norm.y;
	float time = TIME * 1.5;
	float active_rain = float(rain) * rain_amount;

	// 1. Roof & overhang exposure
	float roof_exposure = sample_roof_exposure(v_world_pos);
	float overhang_mask = smoothstep(dry_angle, dry_angle + angle_blend_softness, ny);
	float under_rain = roof_exposure * overhang_mask;

	// 2. Continuous surface angle zones
	// Flat tops -> puddles & ripples
	float puddle_zone = smoothstep(puddle_angle - angle_blend_softness, puddle_angle + angle_blend_softness * 0.5, ny);
	// Slopes & vertical walls -> running streaks (fades out on flat horizontal tops and under overhangs)
	float streak_zone = (1.0 - smoothstep(streaks_angle - angle_blend_softness, streaks_angle + angle_blend_softness, ny)) * overhang_mask;
	// Droplets appear on sloped and top surfaces (strongest where water doesn't pool into deep puddles)
	float droplet_zone = smoothstep(-0.05, 0.35, ny) * overhang_mask;

	// 3. Smooth Triplanar UV Weights
	vec3 tri_w = pow(abs(world_norm), vec3(triplanar_sharpness));
	tri_w /= max(tri_w.x + tri_w.y + tri_w.z, 0.0001);

	vec2 uv_x = v_sample_pos.zy * scale_UV_rain;
	vec2 uv_y = v_sample_pos.xz * scale_UV_rain;
	vec2 uv_z = v_sample_pos.xy * scale_UV_rain;

	// Gravity-aligned lateral streak UVs (compensates for tilted slopes so streaks run downhill)
	vec2 streak_uv_x = vec2(v_sample_pos.z, v_sample_pos.y - v_sample_pos.x * world_norm.x * 0.5) * scale_UV_rain * 0.2;
	vec2 streak_uv_z = vec2(v_sample_pos.x, v_sample_pos.y - v_sample_pos.z * world_norm.z * 0.5) * scale_UV_rain * 0.2;
	float lateral_sum = max(tri_w.x + tri_w.z, 0.0001);
	float wx_lat = tri_w.x / lateral_sum;
	float wz_lat = tri_w.z / lateral_sum;

	// 4. Sample Base PBR Material + Heightmap
	vec2 uv_mat = UV * scale_UV_material;
	vec3 dry_albedo = texture(Material_Albedo, uv_mat).rgb;
	vec3 base_norm_tex = texture(Material_Norm, uv_mat).rgb;
	float dry_rough = texture(Material_Rough, uv_mat).r;
	float dry_metallic = texture(Material_Metal, uv_mat).r;
	float surface_height = texture(Material_Height, uv_mat).r;

	// 5. Snow Accumulation Layer (heightmap cavity & angle aware)
	float snow_dist = roof_exposure * smoothstep(without_snow_angle, 1.0, ny);
	float luma = dot(dry_albedo, vec3(0.299, 0.587, 0.114));
	float snow_cavity = mix(1.0 - surface_height, luma, 0.35);
	float snow_mask = smoothstep(1.0 - snow_dist * snow_amount, 1.0, snow_cavity + snow_dist * snow_amount * 0.5) * step(0.001, snow_amount);
	snow_mask = clamp(snow_mask + smoothstep(0.75, 0.95, snow_dist * snow_amount), 0.0, 1.0);

	vec2 snow_uv = v_sample_pos.xz * scale_UV_rain * 0.1;
	vec3 snow_normals = texture(snow_norm, snow_uv).rgb;
	dry_albedo = mix(dry_albedo, vec3(snow_brightness), snow_mask);
	dry_rough = mix(dry_rough, 0.9, snow_mask);
	dry_metallic = mix(dry_metallic, 0.0, snow_mask);
	base_norm_tex = mix(base_norm_tex, snow_normals, snow_mask);

	// 6. Droplets & Gravity Streaks
	vec4 drops_x = evaluate_droplets(uv_x, time, active_rain);
	vec4 drops_y = evaluate_droplets(uv_y, time, active_rain);
	vec4 drops_z = evaluate_droplets(uv_z, time, active_rain);
	vec4 drops = drops_x * tri_w.x + drops_y * tri_w.y + drops_z * tri_w.z;
	drops.rgb = normalize(drops.rgb);
	drops.a *= droplet_zone * under_rain;

	vec4 streaks_x = evaluate_streaks(streak_uv_x, time, streak_zone, active_rain);
	vec4 streaks_z = evaluate_streaks(streak_uv_z, time, streak_zone, active_rain);
	vec4 streaks = streaks_x * wx_lat + streaks_z * wz_lat;
	streaks.rgb = normalize(streaks.rgb);
	streaks.a *= under_rain;

	// 7. Heightmap-Modulated Puddles & 4-Layer Ripples
	float wetness = smoothstep(0.0, 0.5, wet_level) * under_rain;
	float thin_water = smoothstep(0.5, 1.0, wet_level) * under_rain;
	float puddle_level = smoothstep(0.05, 1.0, wet_level) * puddle_coverage;

	float noise_puddle = puddles_noise ? texture(noise_tex, v_sample_pos.xz * 0.05).r : 1.0;
	float custom_puddle = texture(puddles_tex, uv_mat).r;
	float macro_puddle = clamp(noise_puddle * float(puddles_noise) + custom_puddle, 0.0, 1.0);

	// Water fills heightmap crevices first before submerging high stones
	float water_column = (macro_puddle * puddle_level) - (surface_height * puddle_cavity_depth * (1.0 - puddle_level * 0.85));
	float puddle_mask = smoothstep(-0.05, 0.2, water_column) * puddle_zone * under_rain * step(0.001, puddle_level);
	float puddle_submerge = smoothstep(0.05, 0.35, water_column) * puddle_mask;

	vec4 ripples = evaluate_ripples(uv_y, time, active_rain);

	// 8. Sebastien Lagarde Physically Based Wet Albedo & Roughness
	float porosity = clamp((dry_rough - 0.3) / 0.5, 0.0, 1.0) * porosity_strength;
	float dark_factor = mix(1.0, 1.0 - wet_darkening * 0.8, (1.0 - dry_metallic) * porosity);
	float effective_wet = clamp(max(wetness, puddle_mask), 0.0, 1.0);

	vec3 wet_albedo = adjust_saturation(1.0 + effective_wet * 0.65, dry_albedo);
	wet_albedo *= mix(1.0, dark_factor, effective_wet);
	// Deep puddles slightly attenuate underlying albedo
	wet_albedo = mix(wet_albedo, wet_albedo * 0.85, puddle_submerge);

	float wet_rough = 1.0 - mix(1.0, 1.0 - dry_rough, mix(1.0, dark_factor, effective_wet * 0.65));
	wet_rough = mix(wet_rough, wet_rough * 0.45, thin_water);
	wet_rough = mix(wet_rough, water_roughness, clamp(drops.a + streaks.a, 0.0, 1.0));
	wet_rough = mix(wet_rough, water_roughness * 0.5, puddle_submerge);

	// 9. Reoriented Normal Mapping (RNM) Composition
	vec3 n_base = unpack_normal(base_norm_tex, normal_strength);
	// Submerging in puddle water progressively flattens micro-surface normals
	n_base = normalize(mix(n_base, vec3(0.0, 0.0, 1.0), puddle_submerge * 0.92));

	vec3 n_drops = unpack_normal(drops.rgb, drops_intensity);
	vec3 n_streaks = unpack_normal(streaks.rgb, streaks_intensity);
	vec3 n_ripples = unpack_normal(ripples.rgb, ripple_intensity);

	// Blend droplets (suppressed inside deep puddles) and streaks over base normal
	float drop_weight = drops.a * (1.0 - puddle_submerge);
	vec3 n_combined = blend_rnm(n_base, n_drops, drop_weight);
	n_combined = blend_rnm(n_combined, n_streaks, streaks.a * (1.0 - puddle_submerge));
	// Blend ripples across puddle surfaces and thin wet film on top faces
	float ripple_surface_mask = max(puddle_submerge, thin_water * puddle_zone * 0.45);
	n_combined = blend_rnm(n_combined, n_ripples, ripples.a * ripple_surface_mask);

	ALBEDO = mix(dry_albedo, wet_albedo, effective_wet);
	METALLIC = mix(dry_metallic, water_metallnes, puddle_submerge);
	ROUGHNESS = clamp(mix(dry_rough, wet_rough, effective_wet), 0.02, 1.0);
	SPECULAR = mix(0.5, water_specular, max(effective_wet * 0.5, max(puddle_submerge, drops.a + streaks.a)));
	NORMAL_MAP = pack_normal(n_combined);
}
