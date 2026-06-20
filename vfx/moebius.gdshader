shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Moebius Style Settings
uniform float edge_threshold : hint_range(0.0, 1.0) = 0.2;
uniform float line_thickness : hint_range(0.5, 3.0) = 1.0;
uniform float wobble_strength : hint_range(0.0, 0.05) = 0.001;
uniform float color_quantization : hint_range(1.0, 32.0) = 8.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.3;

// Crosshatch Settings
uniform float hatch_scale : hint_range(10.0, 500.0) = 150.0;
uniform float hatch_thickness : hint_range(0.0, 1.0) = 0.2;
uniform vec3 ink_color : source_color = vec3(0.15, 0.12, 0.2); // Dark blue/purple ink

// Frame pacing
uniform float frame_rate : hint_range(1.0, 60.0) = 10.0; // Slow update for grain/wobble

float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    // Stepped time for the hand-drawn illusion
    float stepped_time = floor(TIME * frame_rate) / frame_rate;
    
    // UV Wobble to mimic imperfect line work
    float noise_val = rand(SCREEN_UV + stepped_time);
    vec2 wobble_offset = vec2(cos(noise_val * 6.2831), sin(noise_val * 6.2831)) * wobble_strength;
    vec2 uv = SCREEN_UV + wobble_offset;
    
    vec2 viewport_size = vec2(textureSize(screen_texture, 0));
    vec3 luma_weights = vec3(0.299, 0.587, 0.114);
    
    // --- 1. Sobel Edge Detection ---
    vec2 texel = vec2(1.0) / viewport_size * line_thickness;
    
    float l00 = dot(texture(screen_texture, uv + vec2(-texel.x, -texel.y)).rgb, luma_weights);
    float l10 = dot(texture(screen_texture, uv + vec2(0.0, -texel.y)).rgb, luma_weights);
    float l20 = dot(texture(screen_texture, uv + vec2(texel.x, -texel.y)).rgb, luma_weights);
    float l01 = dot(texture(screen_texture, uv + vec2(-texel.x, 0.0)).rgb, luma_weights);
    float l21 = dot(texture(screen_texture, uv + vec2(texel.x, 0.0)).rgb, luma_weights);
    float l02 = dot(texture(screen_texture, uv + vec2(-texel.x, texel.y)).rgb, luma_weights);
    float l12 = dot(texture(screen_texture, uv + vec2(0.0, texel.y)).rgb, luma_weights);
    float l22 = dot(texture(screen_texture, uv + vec2(texel.x, texel.y)).rgb, luma_weights);
    
    float sobel_x = l00 + 2.0 * l01 + l02 - l20 - 2.0 * l21 - l22;
    float sobel_y = l00 + 2.0 * l10 + l20 - l02 - 2.0 * l12 - l22;
    float edge = sqrt(sobel_x * sobel_x + sobel_y * sobel_y);
    float is_edge = step(edge_threshold, edge);
    
    // --- 2. Flat Colors & Posterization ---
    vec3 base_color = texture(screen_texture, uv).rgb;
    // Quantize the colors into blocks to replicate flat comic coloring
    base_color = floor(base_color * color_quantization) / color_quantization;
    
    // Bump up the saturation slightly to match the classic BD (Bande Dessinée) look
    float luma = dot(base_color, luma_weights);
    base_color = mix(vec3(luma), base_color, saturation);
    
    // --- 3. Progressive Screen-Space Crosshatching ---
    // Keep lines square regardless of monitor aspect ratio
    vec2 screen_coord = uv * viewport_size / (viewport_size.y / hatch_scale);
    
    // Calculate the three crosshatch directions mathematically
    float h1 = step(hatch_thickness, fract(screen_coord.y)); // Horizontal
    float h2 = step(hatch_thickness, fract(screen_coord.x)); // Vertical
    float h3 = step(hatch_thickness, fract((screen_coord.x + screen_coord.y) * 0.707)); // Diagonal
    
    // Activate hatching layers progressively based on darkness
    float use_h1 = step(luma, 0.75);
    float use_h2 = step(luma, 0.50);
    float use_h3 = step(luma, 0.25);
    
    // Blend the active lines together
    float c1 = mix(1.0, h1, use_h1);
    float c2 = mix(1.0, h2, use_h2);
    float c3 = mix(1.0, h3, use_h3);
    float hatch_mask = c1 * c2 * c3; // 0.0 where lines exist, 1.0 where blank
    
    // --- 4. Branchless Composition ---
    // Draw the hatching using the ink color
    vec3 color_with_hatch = mix(ink_color, base_color, hatch_mask);
    
    // Draw the sobel outlines using the same ink color
    vec3 final_color = mix(color_with_hatch, ink_color, is_edge);
    
    // Add subtle, slowly updating film grain
    float grain = rand(uv + stepped_time) * 0.05;
    final_color -= grain;
    
    COLOR = vec4(final_color, 1.0);
}