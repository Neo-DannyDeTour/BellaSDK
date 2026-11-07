shader_type spatial;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D particles;
uniform int n_particles;

uniform float k = 0.3;
uniform vec3 color : source_color = vec3(0.0);
uniform float opacity = 1.0;
uniform float metallic = 0.6;
uniform float specular = 0.4;
uniform float roughness = 0.1;

varying vec3 global_camera;
varying vec3 global_position;

const int MAX_STEPS = 20;
const float MAX_DIST = 100.0;
const float SURF_DIST = 1e-2;
const float LOCAL_BOUNDS_NEAR = 1.5;
const float LOCAL_BOUNDS_FAR = 2.5;

float op_smooth_union(float d1, float d2) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

vec3 hash3(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    uvec3 ka = n * uvec3(n, n * 16807U, n * 48271U);
    return vec3(ka & uvec3(0x7fffffffU)) / float(0x7fffffff);
}

float displacement(float seed_in, vec3 p) {
    float frequency = 45.0;
    float damping_factor = 0.03;
    float speed = (TIME * 4.2);
    vec3 dim_factor = vec3(0.21, 0.23, 0.15);
    vec3 world_wave = cos(p * dim_factor * frequency + speed);
    return length(world_wave + hash3(uint(seed_in))) * damping_factor;
}

float get_dist(vec3 p) {
    float d = 100000.0;
    int count = min(n_particles, 50);

    for (int i = 0; i < count; i++) {
        vec4 particle = texelFetch(particles, ivec2(i, 0), 0);
        // particle.a now contains the individual current_radius
        d = op_smooth_union(d, length(p - particle.rgb) - particle.a);
    }

    return d + displacement(0x1337, p);
}

float ray_march(vec3 ro, vec3 rd, float start_d, float max_d) {
    float d_o = start_d;
    float d_s;

    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + d_o * rd;
        d_s = get_dist(p);
        d_o += d_s;

        if (d_s < SURF_DIST || d_o > max_d) {
            break;
        }
    }
    return d_o;
}

vec3 get_normal(vec3 p, float center_d) {
    vec2 e = vec2(1e-3, 0.0);
    vec3 n = center_d - vec3(
        get_dist(p - e.xyy),
        get_dist(p - e.yxy),
        get_dist(p - e.yyx)
    );
    return normalize(n);
}

void vertex() {
    global_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    global_camera = INV_VIEW_MATRIX[3].xyz;
}

void fragment() {
    if (n_particles <= 0) {
        discard;
    }

    float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_depth = length(view.xyz);
    if (depth <= 0.0) {
        linear_depth = MAX_DIST;
    }

    vec3 to_frag = global_position - global_camera;
    float frag_dist = length(to_frag);
    float start_d = max(0.0, frag_dist - LOCAL_BOUNDS_NEAR);
    float max_d = min(MAX_DIST, min(linear_depth, frag_dist + LOCAL_BOUNDS_FAR));

    if (start_d >= max_d) {
        discard;
    }

    vec3 rd = to_frag / max(frag_dist, 1e-5);
    float d = ray_march(global_camera, rd, start_d, max_d);

    if (d >= max_d) {
        discard;
    } else {
        vec3 p = global_camera + rd * d;
        vec3 n = get_normal(p, get_dist(p));

        ALBEDO = color;
        ALPHA = opacity;
        NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
        METALLIC = metallic;
        SPECULAR = specular;
        ROUGHNESS = roughness;
    }
}
