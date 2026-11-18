shader_type spatial;
render_mode particle_trails, depth_prepass_alpha, cull_disabled;

uniform vec4 gel_color : source_color = vec4(0.0, 0.5, 1.0, 0.8);
uniform float wobble_strength = 1.0;

// 1. Extracted Hash Function
vec3 hash3(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    uvec3 ka = n * uvec3(n, n * 16807U, n * 48271U);
    return vec3(ka & uvec3(0x7fffffffU)) / float(0x7fffffff);
}

// 2. Extracted Displacement Function
float displacement(float seed_in, vec3 p) {
    float frequency = 45.0;
    float damping_factor = 0.03;
    float speed = (TIME * 4.2);
    vec3 dim_factor = vec3(0.21, 0.23, 0.15);
    vec3 world_wave = cos(p * dim_factor * frequency + speed);
    return length(world_wave + hash3(uint(seed_in))) * damping_factor;
}

void vertex() {
    // Keep the raindrop taper profile
    float taper = smoothstep(0.0, 0.15, UV.x) * smoothstep(1.0, 0.8, UV.x);

    // Transform vertex to world space to match the reference's wave coordinates
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // Calculate displacement using the particle's INSTANCE_ID as a unique seed
    float disp = displacement(float(INSTANCE_ID), world_pos) * wobble_strength;

    // Apply displacement scaled by our teardrop taper
    VERTEX += NORMAL * (disp * taper);
}

void fragment() {
    ALBEDO = gel_color.rgb;
    ALPHA = gel_color.a;

    // 3. Extracted PBR Material Settings
    METALLIC = 0.6;
    SPECULAR = 0.4;
    ROUGHNESS = 0.1;

    // Optional: Keep the rim light to enhance the fluid volume
    float rim = 1.0 - dot(VIEW, NORMAL);
    ALBEDO += gel_color.rgb * pow(rim, 3.0) * 0.4;
}
