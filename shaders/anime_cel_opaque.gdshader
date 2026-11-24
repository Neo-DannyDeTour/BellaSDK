shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.95, 0.74, 0.73, 1.0);
uniform float shadow_threshold : hint_range(-0.5, 0.8) = 0.08;
uniform float shadow_softness : hint_range(0.001, 0.35) = 0.08;
uniform float shadow_floor : hint_range(0.0, 0.95) = 0.56;
uniform float shadow_ambient_lift : hint_range(0.0, 0.5) = 0.05;

uniform float specular_threshold : hint_range(0.05, 0.99) = 0.62;
uniform float specular_softness : hint_range(0.001, 0.25) = 0.05;
uniform float specular_strength : hint_range(0.0, 1.5) = 0.15;

uniform vec4 rim_color : source_color = vec4(0.95, 0.88, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.4;
uniform float rim_threshold : hint_range(0.05, 0.95) = 0.52;
uniform float rim_softness : hint_range(0.005, 0.4) = 0.12;
uniform float rim_strength : hint_range(0.0, 1.5) = 0.12;

uniform float roughness_scale : hint_range(0.1, 2.0) = 0.85;
uniform float metallic_scale : hint_range(0.0, 1.0) = 1.0;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.35;
uniform float diffuse_light_scale : hint_range(0.2, 2.0) = 0.72;
uniform float diffuse_ceiling : hint_range(0.3, 2.0) = 0.95;

uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * albedo_tint;
	vec3 orm = texture(orm_tex, UV).rgb;
	float metal = smoothstep(0.10, 0.90, orm.b) * metallic_scale;

	ALBEDO = tex.rgb;
	AO = mix(1.0, orm.r, ao_strength);
	ROUGHNESS = clamp(orm.g * roughness_scale, 0.08, 0.96);
	METALLIC = metal;
	SPECULAR = mix(0.35, 0.85, metal);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	EMISSION = emission_color.rgb * emission_strength
		+ tex.rgb * shadow_tint.rgb * (shadow_ambient_lift * AO * (1.0 - metal));
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float ndotl_band = smoothstep(
		shadow_threshold - shadow_softness,
		shadow_threshold + shadow_softness,
		ndotl
	);
	float shadow_mask = LIGHT_IS_DIRECTIONAL
		? smoothstep(0.10, 0.65, ATTENUATION)
		: 1.0;
	float cel_band = ndotl_band * shadow_mask;

	// Clamp floor_wrap >= 0.45 so recessed cavities/mouth keep warm shadow tint instead of black.
	float floor_wrap = LIGHT_IS_DIRECTIONAL ? 1.0 : max(0.45, smoothstep(-0.85, 0.05, ndotl));
	float atten_diffuse = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	vec3 shadow_col = shadow_tint.rgb * shadow_floor * floor_wrap;
	vec3 cel_diffuse = mix(shadow_col, vec3(1.0), cel_band);
	vec3 light_col = LIGHT_COLOR * 0.318309886;
	vec3 contrib = cel_diffuse * light_col * atten_diffuse * diffuse_light_scale * (1.0 - METALLIC * 0.85);
	float ceil_v = max(diffuse_ceiling, 0.25);
	vec3 headroom = max(vec3(ceil_v) - DIFFUSE_LIGHT, vec3(0.0));
	DIFFUSE_LIGHT += contrib * (headroom / (vec3(ceil_v) + contrib));

	vec3 half_vec = normalize(LIGHT + VIEW);
	float ndoth = max(dot(NORMAL, half_vec), 0.0);
	float spec_pow = pow(ndoth, mix(64.0, 8.0, ROUGHNESS));
	float spec_band = smoothstep(
		specular_threshold - specular_softness,
		specular_threshold + specular_softness,
		spec_pow
	);

	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, rim_power);
	float rim_mask = smoothstep(
		rim_threshold - rim_softness,
		rim_threshold + rim_softness,
		fresnel
	);
	float rim_wrap = 0.25 + 0.75 * clamp(ndotl, 0.0, 1.0);

	float effective_spec = mix(specular_strength, 0.45, METALLIC);
	vec3 spec_tint = mix(vec3(1.0), ALBEDO, METALLIC);
	vec3 rim_tint_col = mix(
		rim_color.rgb,
		rim_color.rgb * clamp(ALBEDO * 3.0, vec3(0.12), vec3(1.0)),
		0.72
	);
	vec3 metal_band = mix(vec3(0.16, 0.18, 0.24), vec3(0.55, 0.58, 0.65), cel_band);
	vec3 metal_sheen = ALBEDO * METALLIC * metal_band * atten_diffuse;
	vec3 spec_add = light_col * (
		ATTENUATION * spec_tint * spec_band * effective_spec * cel_band
		+ ATTENUATION * rim_tint_col * rim_mask * rim_strength * rim_wrap
		+ metal_sheen
	);
	vec3 spec_headroom = max(vec3(0.85) - SPECULAR_LIGHT, vec3(0.0));
	SPECULAR_LIGHT += spec_add * (spec_headroom / (vec3(0.85) + spec_add));
}
