shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float color_bands : hint_range(2.0, 32.0) = 12.0;
uniform float edge_threshold : hint_range(0.0, 1.0) = 0.15;
uniform vec4 edge_color : source_color = vec4(0.25, 0.18, 0.1, 1.0);
uniform vec3 warm_tint = vec3(1.05, 1.02, 0.95);

void fragment() {
    vec2 uv = SCREEN_UV;
    vec4 original = texture(screen_texture, uv);

    // 1. Quantize colors to simulate cel-shading
    vec3 color = floor(original.rgb * color_bands) / color_bands;

    // 2. Apply the characteristic warm, bright tint
    color *= warm_tint;

    // 3. Fast 4-tap Edge Detection
    vec2 p_size = 1.0 / vec2(textureSize(screen_texture, 0));

    vec3 right = texture(screen_texture, uv + vec2(p_size.x, 0.0)).rgb;
    vec3 left = texture(screen_texture, uv - vec2(p_size.x, 0.0)).rgb;
    vec3 up = texture(screen_texture, uv + vec2(0.0, p_size.y)).rgb;
    vec3 down = texture(screen_texture, uv - vec2(0.0, p_size.y)).rgb;

    float diff_x = length(right - left);
    float diff_y = length(up - down);
    float edge = clamp((diff_x + diff_y) * 1.5, 0.0, 1.0);

    // 4. Mix in the warm dark brown edge outline
    if (edge > edge_threshold) {
        color = mix(color, edge_color.rgb, edge);
    }

    COLOR = vec4(color, original.a);
}