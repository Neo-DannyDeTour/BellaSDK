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

uniform uint num_particles;
uniform vec3 particle_scale;
uniform float lifetime = 3.0; 
uniform float lifetime_randomness : hint_range(0.0, 1.0) = 0.25;
uniform float spawn_radius = 40.0;

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
    transform[0].xyz = normalize(transform[0].xyz) * scale.x;
    transform[1].xyz = normalize(transform[1].xyz) * scale.y;
    transform[2].xyz = normalize(transform[2].xyz) * scale.z;
}

void start() {
    if (RESTART_POSITION) {
        vec3 rand = hash32(uvec2(NUMBER, 1U) + uint(TIME) + RANDOM_SEED);

        // Optimized random distribution - faster than the modulo grid math
        vec2 coords = (rand.xy - 0.5) * (spawn_radius * 2.0);

        TRANSFORM[3].xyz = vec3(coords.x, 0.0, coords.y); 
        TRANSFORM = EMISSION_TRANSFORM * TRANSFORM;

        CUSTOM.z = rand.x;
        PARTICLE_LIFETIME = lifetime - lifetime * lifetime_randomness * rand.y;
        START_POS = POSITION;
        START_TIME = TIME + rand.z * (LIFETIME - PARTICLE_LIFETIME);

        HAS_STARTED = 0.0;
        POSITION = vec3(0.0, -1e10, 0.0); 
        set_scale(TRANSFORM, vec3(1e-3));
    }
}

float exp_impulse(float x, float k) {
    float h = k * x;
    return h * exp(1.0 - h);
}

void process() {
    if (TIME > START_TIME + PARTICLE_LIFETIME) {
        ACTIVE = false;
    } else if (HAS_STARTED == 1.0 && length(POSITION - EMISSION_TRANSFORM[3].xyz) > spawn_radius * 1.5) {
        // OPTIMIZATION: Now correctly culls only spawned particles that drift beyond visibility range.
        ACTIVE = false;
    } else if (TIME >= START_TIME) {
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
            float normal_factor = mix(0.25, 1.0, smoothstep(0.92, 0.99, normal.y));
            float foam_factor = mix(0.25, 1.0, smoothstep(0.9, 1.0, foam));

            bool random_splash = CUSTOM.z > 0.7 && foam > 0.3;
            bool should_spawn = (normal_factor >= 0.0 && normal_factor <= 1.0) && (foam > 0.75 || random_splash);
            
            if (should_spawn) {
                ACTIVE = true;
                SCALE_FACTOR = normal_factor * mix(0.5, 1.0, foam_factor);
                PARTICLE_SCALE = vec3(foam_factor) * vec3(1.0, normal_factor, 1.0) * particle_scale;
                HAS_STARTED = 1.0;
            } else {
                POSITION = vec3(0.0, -1e10, 0.0);
                HAS_STARTED = 1.0; 
                SCALE_FACTOR = 0.0;
            }
        }

        if (ACTIVE && SCALE_FACTOR > 0.0) {
            float t = (TIME - START_TIME) / PARTICLE_LIFETIME;
            CUSTOM.a = exp_impulse(t, 10.0); 

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

            float size = PARTICLE_LIFETIME / lifetime;
            vec3 scale_modifier = vec3(size * size);
            scale_modifier.y *= exp_impulse(t, 3.0);
            scale_modifier.xz *= vec2(log(1.0 + t) + 0.01);
            
            set_scale(TRANSFORM, PARTICLE_SCALE * scale_modifier);
        }
    }
}