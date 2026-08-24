shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, cull_disabled;

// 0 = Black & White (White Level + Black Outlines)
// 1 = Blue (Solid Slate Blue + Light Outlines)
// 2 = Pure Black (Black Level + White Outlines)
// 3 = Neutral Grey (Medium Grey + White Outlines)
// 4 = Desaturated (Greyscale Scene Texture)
// 5 = AgX Base (Natural HDR Rolloff)
// 6 = AgX Punchy (Contrast Boosted)
// 7 = Pass-Through (Bypass / Default Environment)
uniform int mode : hint_range(0, 7) = 5;

uniform vec4 blue_base : source_color = vec4(0.05, 0.1, 0.45, 1.0);
uniform vec4 blue_outline : source_color = vec4(0.3, 0.5, 0.9, 1.0);
uniform vec4 grey_base : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform vec4 grey_outline : source_color = vec4(0.85, 0.85, 0.85, 1.0);

uniform float outline_thickness : hint_range(0.5, 5.0) = 1.0;
uniform float depth_threshold = 0.025;
uniform float normal_threshold = 0.5;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;

// AgX Matrix Constants (BT.709 / sRGB to AgX Log domain)
const mat3 AGX_INSET_MATRIX = mat3(
	vec3(0.842479062279267, 0.0423282422610123, 0.0423756549057051),
	vec3(0.0784335999999992, 0.878468636469772, 0.0784336),
	vec3(0.0792237456477922, 0.0791661274605434, 0.879142974414998)
);

const mat3 AGX_OUT_MATRIX = mat3(
	vec3(1.196879024257173, -0.052896851700547, -0.0529716355844491),
	vec3(-0.0980208811401368, 1.15190312990417, -0.0980434501171241),
	vec3(-0.0990297460767795, -0.0989611760587288, 1.15101052146908)
);

const float AGX_MIN_EV = -12.47393;
const float AGX_MAX_EV = 4.026069;

vec3 agx_default_contrast_curve(vec3 x) {
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	return + 15.5 * x4 * x2
	       - 40.14 * x4 * x
	       + 31.96 * x4
	       - 6.868 * x2 * x
	       + 0.4298 * x2
	       + 0.1191 * x
	       - 0.00232;
}

vec3 apply_agx(vec3 val, bool punchy) {
	val = AGX_INSET_MATRIX * val;
	val = max(val, vec3(1e-10));

	// Convert to Log2 domain
	val = clamp((log2(val) - AGX_MIN_EV) / (AGX_MAX_EV - AGX_MIN_EV), 0.0, 1.0);
	val = agx_default_contrast_curve(val);
	val = AGX_OUT_MATRIX * val;

	if (punchy) {
		vec3 luma_weights = vec3(0.2126, 0.7152, 0.0722);
		float luma = dot(val, luma_weights);
		val = pow(max(val, vec3(0.0)), vec3(1.35));
		val = mix(vec3(luma), val, 1.2);
	}

	return clamp(val, 0.0, 1.0);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	vec4 screen_col = texture(screen_texture, screen_uv);
	vec3 final_bg = vec3(0.0);

	if (mode == 5) {
		final_bg = apply_agx(screen_col.rgb, false);
	} else if (mode == 6) {
		final_bg = apply_agx(screen_col.rgb, true);
	} else if (mode == 7) {
		final_bg = screen_col.rgb;
	} else {
		vec2 texel = (1.0 / VIEWPORT_SIZE) * outline_thickness;

		// --- EDGE DETECTION ---
		float d_center = texture(depth_texture, screen_uv).x;
		float d_up = texture(depth_texture, screen_uv + vec2(0.0, texel.y)).x;
		float d_down = texture(depth_texture, screen_uv + vec2(0.0, -texel.y)).x;
		float d_left = texture(depth_texture, screen_uv + vec2(texel.x, 0.0)).x;
		float d_right = texture(depth_texture, screen_uv + vec2(-texel.x, 0.0)).x;

		float depth_edge = abs(d_center - d_up) + abs(d_center - d_down) +
		                   abs(d_center - d_left) + abs(d_center - d_right);

		vec3 n_center = texture(normal_texture, screen_uv).rgb;
		vec3 n_up = texture(normal_texture, screen_uv + vec2(0.0, texel.y)).rgb;
		vec3 n_down = texture(normal_texture, screen_uv + vec2(0.0, -texel.y)).rgb;
		vec3 n_left = texture(normal_texture, screen_uv + vec2(texel.x, 0.0)).rgb;
		vec3 n_right = texture(normal_texture, screen_uv + vec2(-texel.x, 0.0)).rgb;

		float normal_edge = distance(n_center, n_up) + distance(n_center, n_down) +
		                    distance(n_center, n_left) + distance(n_center, n_right);

		bool is_edge = (depth_edge > depth_threshold) || (normal_edge > normal_threshold);

		if (mode == 0) {
			final_bg = is_edge ? vec3(0.0) : vec3(1.0);
		} else if (mode == 1) {
			final_bg = is_edge ? blue_outline.rgb : blue_base.rgb;
		} else if (mode == 2) {
			final_bg = is_edge ? vec3(1.0) : vec3(0.0);
		} else if (mode == 3) {
			final_bg = is_edge ? grey_outline.rgb : grey_base.rgb;
		} else if (mode == 4) {
			float lum = dot(screen_col.rgb, vec3(0.299, 0.587, 0.114));
			final_bg = vec3(lum);
		}
	}

	ALBEDO = final_bg;
}
