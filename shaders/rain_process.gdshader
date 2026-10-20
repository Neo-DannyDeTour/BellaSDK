shader_type particles;

uniform vec3 box_extents = vec3(15.0, 10.0, 15.0);
uniform float fall_speed = 22.0;
uniform vec3 wind_velocity = vec3(2.0, 0.0, 1.0);
uniform float swirl_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float swirl_frequency = 0.28;
uniform float swirl_strength = 11.0;
uniform float near_camera_bias : hint_range(0.0, 1.0) = 0.65;

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	return (x >> uint(16)) ^ x;
}

float rand_from_seed(inout uint seed) {
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	int k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

// 3D analytical helical curl field for storm gusts and mid-air vortices
vec3 get_storm_vortex(vec3 world_pos, float t, float is_swirler) {
	vec3 p = world_pos * swirl_frequency + vec3(t * 2.2, -t * 1.1, t * 1.7);
	vec3 wave = vec3(
		sin(p.z + cos(p.y * 1.3)) + cos(p.y * 1.7 - t * 3.0) * 0.5,
		sin(p.x * 1.4 - cos(p.z * 1.2)) * mix(0.25, 1.35, is_swirler),
		cos(p.x + sin(p.y * 1.3)) - sin(p.z * 1.7 + t * 2.5) * 0.5
	);
	return wave * swirl_strength * swirl_intensity * mix(0.65, 1.45, is_swirler);
}

void start() {
	uint alt_seed = hash(NUMBER + uint(1) + RANDOM_SEED);

	// Radial polar spawn in XZ to concentrate prominent drops near the camera
	float angle = rand_from_seed(alt_seed) * TAU;
	float u_rad = rand_from_seed(alt_seed);
	float biased_rad = mix(sqrt(u_rad), pow(u_rad, 1.85), near_camera_bias);
	float y_rand = rand_from_seed(alt_seed) * 2.0 - 1.0;

	vec3 local_pos = vec3(
		cos(angle) * biased_rad * box_extents.x,
		y_rand * box_extents.y,
		sin(angle) * biased_rad * box_extents.z
	);

	// Up to 42% of droplets become wind-whipped mid-air swirlers at full storm swirl
	float role_roll = rand_from_seed(alt_seed);
	float is_swirler = step(1.0 - swirl_intensity * 0.42, role_roll);

	// Swirlers spawn throughout the mid/lower volume; falling rain biases toward the top half
	if (is_swirler < 0.5) {
		local_pos.y = mix(local_pos.y, box_extents.y * 0.75, 0.35);
	}

	TRANSFORM = EMISSION_TRANSFORM;
	TRANSFORM[3].xyz += local_pos;

	float speed_var = mix(0.85, 1.2, rand_from_seed(alt_seed));
	float v_fall = fall_speed * speed_var * mix(1.0, 0.16, is_swirler);
	VELOCITY = vec3(wind_velocity.x, -v_fall, wind_velocity.z);

	// CUSTOM.x = seed phase, CUSTOM.y = is_swirler (0=falling, 1=swirling), CUSTOM.z = radial norm
	CUSTOM = vec4(rand_from_seed(alt_seed), is_swirler, biased_rad, 0.0);
}

void process() {
	vec3 world_pos = TRANSFORM[3].xyz;
	vec3 rel_pos = world_pos - EMISSION_TRANSFORM[3].xyz;

	if (any(greaterThan(abs(rel_pos), box_extents)) || COLLIDED) {
		ACTIVE = false;
	} else {
		float is_swirler = CUSTOM.y;
		vec3 gust = get_storm_vortex(world_pos + vec3(CUSTOM.x * 13.0), TIME, is_swirler);
		float base_vy = -fall_speed * mix(0.85, 1.2, CUSTOM.x) * mix(1.0, 0.16, is_swirler);

		VELOCITY = vec3(
			wind_velocity.x * mix(1.0, 1.4, is_swirler) + gust.x,
			base_vy + gust.y,
			wind_velocity.z * mix(1.0, 1.4, is_swirler) + gust.z
		);

		float speed = max(length(VELOCITY), 0.001);
		vec3 dir = VELOCITY / speed;

		// Close drops and fast streaks get thicker/longer; swirlers form compact wind-whipped beads
		float near_boost = mix(1.35, 0.85, clamp(CUSTOM.z, 0.0, 1.0));
		float width = mix(0.042, 0.052, is_swirler) * near_boost;
		float streak_len = mix(0.95, 0.38, is_swirler) * clamp(speed / 20.0, 0.45, 1.45);

		// Store width in X basis length and velocity vector * streak_len in Y basis
		TRANSFORM[0].xyz = vec3(width, 0.0, 0.0);
		TRANSFORM[1].xyz = dir * streak_len;
		TRANSFORM[2].xyz = vec3(0.0, 0.0, width);

		// Pass near-camera boost and role to fragment shader
		COLOR = vec4(near_boost, is_swirler, clamp(speed / 28.0, 0.0, 1.0), 1.0);
	}
}
