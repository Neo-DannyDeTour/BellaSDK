shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Default values create a classic "Labyrinth" or "Spots" Turing pattern
uniform float feed = 0.055;
uniform float kill = 0.062;
uniform float da = 1.0;
uniform float dv = 0.5;
uniform float delta_time = 1.0;
uniform bool is_seeding = false;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 texel = 1.0 / vec2(textureSize(screen_texture, 0));

    // Read current morphogen concentrations
    vec4 state = texture(screen_texture, uv);
    float u = state.r;
    float v = state.g;

    // Initialize blank canvas with maximum 'U' chemical
    if (u == 0.0 && v == 0.0) {
        u = 1.0;
    }

    // 3x3 Laplacian Kernel (Optimized)
    float lap_u = 0.0;
    float lap_v = 0.0;

    // Adjacent pixels (weight 0.2)
    vec4 n = texture(screen_texture, uv + vec2(0.0, -texel.y));
    vec4 s = texture(screen_texture, uv + vec2(0.0, texel.y));
    vec4 e = texture(screen_texture, uv + vec2(texel.x, 0.0));
    vec4 w = texture(screen_texture, uv + vec2(-texel.x, 0.0));
    lap_u += (n.r + s.r + e.r + w.r) * 0.2;
    lap_v += (n.g + s.g + e.g + w.g) * 0.2;

    // Diagonal pixels (weight 0.05)
    vec4 nw = texture(screen_texture, uv + vec2(-texel.x, -texel.y));
    vec4 ne = texture(screen_texture, uv + vec2(texel.x, -texel.y));
    vec4 sw = texture(screen_texture, uv + vec2(-texel.x, texel.y));
    vec4 se = texture(screen_texture, uv + vec2(texel.x, texel.y));
    lap_u += (nw.r + ne.r + sw.r + se.r) * 0.05;
    lap_v += (nw.g + ne.g + sw.g + se.g) * 0.05;

    // Center pixel (weight -1.0)
    lap_u -= u;
    lap_v -= v;

    // Gray-Scott Equation
    float reaction = u * v * v;
    float next_u = u + (da * lap_u - reaction + feed * (1.0 - u)) * delta_time;
    float next_v = v + (dv * lap_v + reaction - (kill + feed) * v) * delta_time;

    // Inject 'V' chemical seed to start the reaction
    if (is_seeding) {
        float dist = distance(uv, vec2(0.5, 0.5));
        if (dist < 0.02) {
            next_v = 1.0;
        }
    }

    COLOR = vec4(clamp(next_u, 0.0, 1.0), clamp(next_v, 0.0, 1.0), 0.0, 1.0);
}