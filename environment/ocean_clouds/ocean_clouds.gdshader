shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Seamless 2D noise texture (hardware bilinear lookup replaces 480+ ALU hashes/pixel).
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;

// Wind & motion
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_speed : hint_range(0.0, 120.0) = 18.0;
uniform float evolution_speed : hint_range(0.0, 2.0) = 0.25;

// Cloud shaping
uniform float cloud_scale : hint_range(0.0003, 0.02) = 0.0022;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_density : hint_range(0.1, 5.0) = 1.6;
uniform float cloud_thickness : hint_range(10.0, 400.0) = 120.0;
uniform int march_steps : hint_range(2, 8) = 4;

// Lighting & colors
uniform vec3 sun_direction = vec3(0.45, 0.65, -0.60);
uniform vec3 cloud_color : source_color = vec3(0.96, 0.97, 1.0);
uniform vec3 shadow_color : source_color = vec3(0.32, 0.38, 0.48);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float silver_lining : hint_range(0.0, 1.5) = 0.45;

// Canopy geometry & horizon blend
uniform float canopy_radius : hint_range(200.0, 6000.0) = 1800.0;
uniform float horizon_curvature : hint_range(0.0, 0.0002) = 0.00004;

varying vec3 v_world_pos;
varying vec2 v_local_xz;

// Irrational rotation matrices break texture grid alignment and prevent checkerboarding.
const mat2 ROT_A = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
const mat2 ROT_B = mat2(vec2(-0.52, 0.854), vec2(-0.854, -0.52));

// Interleaved Gradient Noise hides low step counts without temporal flicker.
float ign(vec2 pixel_pos) {
	vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
	return fract(magic.z * fract(dot(pixel_pos, magic.xy)));
}

// Fast 2-tap rotated non-repeating cloud shape lookup (hardware filtered).
float sample_detail(vec2 uv) {
	float n1 = texture(noise_texture, uv).r;
	float n2 = texture(noise_texture, ROT_A * (uv * 2.17) + vec2(0.37, 0.61)).r;
	return n1 * 0.67 + n2 * 0.33;
}

void vertex() {
	v_local_xz = VERTEX.xz;
	float dist_sq = dot(VERTEX.xz, VERTEX.xz);
	VERTEX.y -= dist_sq * horizon_curvature;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Radial horizon fade melts canopy seamlessly into distant sky.
	float radial = length(v_local_xz) / max(canopy_radius, 1.0);
	float edge_fade = 1.0 - smoothstep(0.55, 0.98, radial);
	if (edge_fade <= 0.001) {
		discard;
	}

	vec3 ray_dir = normalize(v_world_pos - CAMERA_POSITION_WORLD);
	vec2 wind_dir = length(wind_direction) > 0.0001 ? normalize(wind_direction) : vec2(1.0, 0.0);
	vec3 sun_dir = length(sun_direction) > 0.0001
		? normalize(sun_direction)
		: normalize(vec3(0.45, 0.65, -0.6));

	// Scale world coordinates into seamless texture UV space.
	float uv_scale = cloud_scale * 0.14;
	float t = TIME;
	vec2 wind_uv = wind_dir * (wind_speed * uv_scale * t);
	vec2 base_uv = v_world_pos.xz * uv_scale;

	// Hoist macro weather front & domain warp outside the raymarch loop (1x per pixel).
	vec2 macro_uv = ROT_B * (base_uv * 0.27) - wind_uv * 0.42 + vec2(0.13, 0.71);
	float macro_field = texture(noise_texture, macro_uv).r;

	float local_cov = clamp(cloud_coverage * mix(0.42, 1.58, macro_field), 0.0, 0.98);
	float threshold = 1.0 - local_cov;

	// Early-out for completely clear sky regions before raymarching.
	if (0.86 + macro_field * 0.26 <= threshold) {
		discard;
	}

	vec2 evo = vec2(t * evolution_speed * 0.018, -t * evolution_speed * 0.013);
	vec2 warp_uv = base_uv * 0.58 - wind_uv * 0.75 + evo;
	vec2 warp = vec2(
		texture(noise_texture, warp_uv).r,
		texture(noise_texture, ROT_A * warp_uv + vec2(0.47, 0.29)).r
	) - 0.5;
	vec2 warp_offset = warp * 0.22;

	// Clamp grazing ray slope so horizon rays stay bounded and artifact-free.
	float abs_ray_y = max(abs(ray_dir.y), 0.14);
	float march_len = min(cloud_thickness / abs_ray_y, cloud_thickness * 3.8);
	int steps = clamp(march_steps, 2, 8);
	float step_len = march_len / float(steps);
	float jitter = ign(FRAGCOORD.xy);

	float looking_up = ray_dir.y >= 0.0 ? 1.0 : -1.0;

	// Henyey-Greenstein forward scattering for sun silver-lining.
	float cos_theta = dot(ray_dir, sun_dir);
	float g = 0.62;
	float g2 = g * g;
	float hg = (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 0.05), 1.5));
	float forward_scatter = clamp(hg * silver_lining, 0.0, 1.6);

	vec2 ray_step_uv = ray_dir.xz * (march_len * uv_scale);
	vec2 sun_step_uv = sun_dir.xz * (cloud_thickness * 0.28 * uv_scale);
	float density_scale = cloud_density * (step_len / max(cloud_thickness, 1.0)) * 4.2;

	float transmittance = 1.0;
	vec3 light_energy = vec3(0.0);

	for (int i = 0; i < steps; i++) {
		float frac = (float(i) + jitter) / float(steps);
		float h = looking_up > 0.0 ? frac : (1.0 - frac);

		vec2 sample_uv = base_uv + ray_step_uv * frac - wind_uv + warp_offset - wind_dir * (h * 0.035);
		float detail = sample_detail(sample_uv);

		float height_profile = smoothstep(0.0, 0.18, h) * smoothstep(1.0, 0.32, h);
		float dens = max(0.0, (detail * 0.84 + macro_field * 0.26 - threshold) * height_profile)
			* mix(1.25, 0.85, h);

		if (dens > 0.002) {
			// Single-tap shadow lookup toward sun keeps 3D puff lighting at minimal GPU cost.
			float shadow_sample = texture(noise_texture, sample_uv + sun_step_uv).r;
			float shadow_dens = max(0.0, shadow_sample * 0.84 + macro_field * 0.26 - threshold);

			float sun_trans = exp(-shadow_dens * cloud_density * 2.6);
			float powder = 1.0 - exp(-dens * cloud_density * 2.2);
			float height_lit = mix(0.28, 1.0, h);

			vec3 ambient = mix(shadow_color, cloud_color, height_lit);
			vec3 direct = sun_color * (sun_trans * (0.75 + 0.55 * powder) + forward_scatter * sun_trans);
			vec3 step_color = ambient * 0.65 + direct * 0.55;

			float step_alpha = 1.0 - exp(-dens * density_scale);
			light_energy += transmittance * step_color * step_alpha;
			transmittance *= (1.0 - step_alpha);

			if (transmittance < 0.02) {
				break;
			}
		}
	}

	float final_alpha = (1.0 - transmittance) * edge_fade;
	if (final_alpha <= 0.002) {
		discard;
	}

	ALBEDO = light_energy / max(1.0 - transmittance, 0.001);
	ALPHA = clamp(final_alpha, 0.0, 1.0);
}
