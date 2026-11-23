shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.92, 0.78, 0.84, 1.0);
uniform float shadow_threshold : hint_range(-0.5, 0.8) = 0.08;
uniform float shadow_softness : hint_range(0.001, 0.35) = 0.05;
uniform float shadow_floor : hint_range(0.0, 0.9) = 0.42;

uniform float specular_threshold : hint_range(0.05, 0.99) = 0.58;
uniform float specular_softness : hint_range(0.001, 0.25) = 0.03;
uniform float specular_strength : hint_range(0.0, 1.5) = 0.2;

uniform vec4 rim_color : source_color = vec4(0.92, 0.86, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.2;
uniform float rim_threshold : hint_range(0.05, 0.95) = 0.45;
uniform float rim_softness : hint_range(0.005, 0.4) = 0.08;
uniform float rim_strength : hint_range(0.0, 1.5) = 0.28;

uniform float roughness_scale : hint_range(0.1, 2.0) = 0.85;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.5;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.45;

uniform float alpha_scale : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.0;
uniform bool double_sided = true;

uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	if (!double_sided && !FRONT_FACING) {
		discard;
	}

	vec4 tex = texture(albedo_tex, UV) * albedo_tint;
	vec3 orm = texture(orm_tex, UV).rgb;
	float alpha_out = clamp(tex.a * alpha_scale, 0.0, 1.0);

	if (alpha_scissor_threshold > 0.001) {
		if (alpha_out < alpha_scissor_threshold) {
			discard;
		}
		alpha_out = 1.0;
	}

	ALBEDO = tex.rgb;
	ALPHA = alpha_out;
	AO = mix(1.0, orm.r, ao_strength);
	ROUGHNESS = clamp(orm.g * roughness_scale, 0.08, 0.96);
	METALLIC = orm.b * 0.25;
	SPECULAR = 0.35;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	EMISSION = emission_color.rgb * emission_strength;
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float cel_band = smoothstep(
		shadow_threshold - shadow_softness,
		shadow_threshold + shadow_softness,
		ndotl
	);
	vec3 cel_diffuse = mix(shadow_tint.rgb * shadow_floor, vec3(1.0), cel_band);
	DIFFUSE_LIGHT += cel_diffuse * LIGHT_COLOR * ATTENUATION * 0.3183;

	vec3 half_vec = normalize(LIGHT + VIEW);
	float ndoth = max(dot(NORMAL, half_vec), 0.0);
	float spec_pow = pow(ndoth, mix(48.0, 10.0, ROUGHNESS));
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
	float rim_wrap = 0.35 + 0.65 * clamp(ndotl, 0.0, 1.0);

	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (
		spec_band * specular_strength * cel_band
		+ rim_color.rgb * rim_mask * rim_strength * rim_wrap
	) * 0.3183;
}
