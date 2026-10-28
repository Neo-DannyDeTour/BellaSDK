shader_type particles;
render_mode disable_velocity;

#define MAX_CASCADES      8
#define G                 (vec3(0.0, -9.81, 0.0))

#define POSITION          (TRANSFORM[3].xyz)
#define START_POS         (USERDATA1.xyz)
#define START_TIME        (USERDATA1.w)
#define PARTICLE_SCALE    (USERDATA2.xyz)
#define PARTICLE_LIFETIME (USERDATA2.w)
#define SCALE_FACTOR      (USERDATA3.z)
#define HAS_STARTED       (USERDATA3.w)

uniform uint num_particles = 1600U;
uniform vec3 particle_scale = vec3(20.0, 8.5, 20.0);
uniform float lifetime = 3.0;
uniform float lifetime_randomness : hint_range(0.0, 1.0) = 0.25;
uniform float spawn_radius = 150.0;

group_uniforms cascade_data;
uniform vec4 map_scales[MAX_CASCADES];
global uniform int num_cascades;
global uniform sampler2DArray displacements;
global uniform sampler2DArray normals : hint_normal;

vec3 hash32(uvec2 p) {
	p = 1103515245U * ((p >> 1U) ^ p.yx);
	uint h32 = 1103515245U * (p.x ^ (p.y >> 3U));
	uint n = h32 ^ (h32 >> 16U);
	uvec3 rz = uvec3(n, n * 16807U, n * 48271U);
	return vec3((rz >> 1U) & uvec3(0x7FFFFFFFU)) / float(0x7FFFFFFF);
}

void set_scale(inout mat4 transform, in vec3 scale) {
	vec3 safe_s = max(scale, vec3(0.0001));
	transform[0].xyz = normalize(transform[0].xyz + vec3(0.00001, 0.0, 0.0)) * safe_s.x;
	transform[1].xyz = normalize(transform[1].xyz + vec3(0.0, 0.00001, 0.0)) * safe_s.y;
	transform[2].xyz = normalize(transform[2].xyz + vec3(0.0, 0.0, 0.00001)) * safe_s.z;
}

void reset_candidate(
	uint particle_id,
	uint seed_offset,
	float current_time,
	vec3 emitter_origin,
	float stagger_window,
	inout mat4 transform,
	inout vec4 custom_data,
	inout vec4 userdata1,
	inout vec4 userdata2,
	inout vec4 userdata3
) {
	vec3 rand = hash32(uvec2(particle_id, seed_offset));
	vec2 coords = (rand.xy - 0.5) * (spawn_radius * 2.0);
	vec3 world_candidate = emitter_origin + vec3(coords.x, 0.0, coords.y);

	custom_data.z = rand.x;
	custom_data.w = 0.0;
	userdata2.w = max(lifetime - lifetime * lifetime_randomness * rand.y, 0.25);
	userdata1.xyz = world_candidate;
	userdata1.w = current_time + rand.z * stagger_window;
	userdata3.z = 0.0;
	userdata3.w = 0.0;

	transform[3].xyz = emitter_origin - vec3(0.0, 100.0, 0.0);
	set_scale(transform, vec3(0.0001));
}

float exp_impulse(float x, float k) {
	float h = k * x;
	return h * exp(1.0 - h);
}

void start() {
	if (RESTART_POSITION) {
		reset_candidate(
			NUMBER,
			RANDOM_SEED + uint(TIME * 60.0),
			TIME,
			EMISSION_TRANSFORM[3].xyz,
			lifetime,
			TRANSFORM,
			CUSTOM,
			USERDATA1,
			USERDATA2,
			USERDATA3
		);
	}
}

void process() {
	vec3 emitter_origin = EMISSION_TRANSFORM[3].xyz;
	bool expired = TIME > (START_TIME + PARTICLE_LIFETIME);
	bool out_of_bounds = (
		HAS_STARTED == 1.0 && length(START_POS.xz - emitter_origin.xz) > spawn_radius * 1.25
	);

	if (expired || out_of_bounds) {
		reset_candidate(
			NUMBER,
			RANDOM_SEED + uint(TIME * 131.0),
			TIME,
			emitter_origin,
			0.15,
			TRANSFORM,
			CUSTOM,
			USERDATA1,
			USERDATA2,
			USERDATA3
		);
	}

	if (TIME >= START_TIME) {
		if (HAS_STARTED == 0.0) {
			vec3 gradient = vec3(0.0);
			for (int i = 0; i < num_cascades; ++i) {
				gradient += textureLod(
					normals,
					vec3(START_POS.xz * map_scales[i].xy, float(i)),
					0.0
				).xyw;
			}

			vec3 normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
			float foam = gradient.z;
			float normal_factor = mix(0.25, 1.0, smoothstep(0.88, 0.99, normal.y));
			float foam_factor = mix(0.25, 1.0, smoothstep(0.45, 1.0, foam));

			bool should_spawn = foam > 0.25 || (CUSTOM.z > 0.55 && foam > 0.1);
			if (should_spawn) {
				SCALE_FACTOR = normal_factor * mix(0.5, 1.0, foam_factor);
				PARTICLE_SCALE = vec3(foam_factor) * vec3(1.0, normal_factor, 1.0) * particle_scale;
				HAS_STARTED = 1.0;
			} else {
				reset_candidate(
					NUMBER,
					RANDOM_SEED + uint(TIME * 257.0) + 17U,
					TIME,
					emitter_origin,
					0.1,
					TRANSFORM,
					CUSTOM,
					USERDATA1,
					USERDATA2,
					USERDATA3
				);
			}
		}

		if (HAS_STARTED == 1.0 && SCALE_FACTOR > 0.0) {
			float t = clamp((TIME - START_TIME) / max(PARTICLE_LIFETIME, 0.001), 0.0, 1.0);
			CUSTOM.w = exp_impulse(t, 10.0);

			vec3 displacement = vec3(0.0);
			for (int i = 0; i < num_cascades; ++i) {
				vec3 scales = map_scales[i].xyz;
				displacement += textureLod(
					displacements,
					vec3(START_POS.xz * scales.xy, float(i)),
					0.0
				).xyz * scales.z;
			}

			displacement *= vec3(0.75, 1.0, 0.75);
			float jump = 4.0 * t * (1.0 - t);
			displacement += vec3(0.0, jump * 3.0 * SCALE_FACTOR, 0.0);
			POSITION = START_POS + displacement;

			float size = PARTICLE_LIFETIME / max(lifetime, 0.001);
			vec3 scale_modifier = vec3(size * size);
			scale_modifier.y *= exp_impulse(t, 3.0);
			scale_modifier.xz *= vec2(log(1.0 + t) + 0.25);

			set_scale(TRANSFORM, PARTICLE_SCALE * scale_modifier);
		}
	}
}
