shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

instance uniform float glass_held_fade = 0.0;

uniform sampler2D worley_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 glass_tint : source_color = vec4(0.12, 0.15, 0.13, 0.16);
uniform vec3 sludge_color : source_color = vec3(0.06, 0.04, 0.03);

varying vec3 local_pos;
varying vec3 local_norm;

void vertex() {
	local_pos = VERTEX;
	local_norm = abs(NORMAL);
}

void fragment() {
	vec3 w = local_norm / max(local_norm.x + local_norm.y + local_norm.z, 0.0001);
	vec3 p = local_pos * 3.2;

	float smudge = (
		texture(worley_tex, p.yz).r * w.x
		+ texture(worley_tex, p.xz).r * w.y
		+ texture(worley_tex, p.xy).r * w.z
	);
	float scratches = (
		texture(grain_tex, p.yz * 3.5).r * w.x
		+ texture(grain_tex, p.xz * 3.5).r * w.y
		+ texture(grain_tex, p.xy * 3.5).r * w.z
	);

	// Darker bio-residue ring near top/bottom metal seals.
	float seal_grime = smoothstep(0.28, 0.39, abs(local_pos.y));
	float dirt_mask = clamp(
		smoothstep(0.45, 0.85, smudge * 0.7 + scratches * 0.3) * 0.45 + seal_grime * 0.65,
		0.0,
		1.0
	);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	ALBEDO = mix(glass_tint.rgb, sludge_color, dirt_mask);
	ROUGHNESS = mix(0.08, 0.78, dirt_mask);
	METALLIC = 0.05;
	SPECULAR = mix(0.85, 0.25, dirt_mask);
	ALPHA = clamp((glass_tint.a + dirt_mask * 0.32 + fresnel * 0.22) * (1.0 - glass_held_fade * 0.65), 0.04, 0.75);
}
