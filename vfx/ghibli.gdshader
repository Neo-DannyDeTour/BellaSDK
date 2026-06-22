shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float paint_smoothness : hint_range(0.0, 5.0) = 1.5;
uniform float saturation_boost : hint_range(1.0, 2.0) = 1.3;
uniform float value_boost : hint_range(1.0, 2.0) = 1.1;
uniform float edge_darkness : hint_range(0.0, 1.0) = 0.25;

// Fast RGB to HSV and HSV to RGB functions
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 p_size = 1.0 / vec2(textureSize(screen_texture, 0));

    // 1. Optimized 5-Tap Painterly Softening
    vec3 col = texture(screen_texture, uv).rgb;
    vec3 col_u = texture(screen_texture, uv + vec2(0.0, p_size.y * paint_smoothness)).rgb;
    vec3 col_d = texture(screen_texture, uv - vec2(0.0, p_size.y * paint_smoothness)).rgb;
    vec3 col_l = texture(screen_texture, uv - vec2(p_size.x * paint_smoothness, 0.0)).rgb;
    vec3 col_r = texture(screen_texture, uv + vec2(p_size.x * paint_smoothness, 0.0)).rgb;

    // Weight the center pixel higher for shape retention while softening edges
    vec3 painted_col = (col * 2.0 + col_u + col_d + col_l + col_r) / 6.0;

    // 2. Ghibli Color Grade
    vec3 hsv = rgb2hsv(painted_col);

    // Shift mid-greens towards a warmer, vibrant yellow-green
    float is_green = smoothstep(0.15, 0.4, hsv.x) * smoothstep(0.5, 0.4, hsv.x);
    hsv.x -= is_green * 0.04;

    // Shift blues towards a brighter cyan for airy skies
    float is_blue = smoothstep(0.45, 0.65, hsv.x) * smoothstep(0.75, 0.65, hsv.x);
    hsv.x -= is_blue * 0.03;

    // Apply vibrancy and brightness boosts
    hsv.y = clamp(hsv.y * saturation_boost, 0.0, 1.0);
    hsv.z = clamp(hsv.z * value_boost, 0.0, 1.0);

    painted_col = hsv2rgb(hsv);

    // 3. Subtle Pencil/Paint Edge Darkening
    float edge = length(col - col_r) + length(col - col_u);
    painted_col = mix(painted_col, painted_col * (1.0 - edge_darkness), clamp(edge * 2.5, 0.0, 1.0));

    COLOR = vec4(painted_col, 1.0);
}