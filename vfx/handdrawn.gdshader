shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Hand-Drawn Settings
uniform float frame_rate : hint_range(1.0, 60.0) = 12.0; // The "Spider-Verse" choppy framerate
uniform float wobble_strength : hint_range(0.0, 0.05) = 0.0015; // How much the "paper" shifts
uniform float line_thickness : hint_range(0.5, 3.0) = 1.0;
uniform float edge_threshold : hint_range(0.0, 1.0) = 0.15;
uniform vec3 paper_tint : source_color = vec3(0.96, 0.94, 0.90); // Warm parchment color

// Pseudo-random noise generator
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    // --- 1. Stepped Time (The 12 FPS Anime effect) ---
    // This locks the time variable to specific intervals, creating a stop-motion look
    float stepped_time = floor(TIME * frame_rate) / frame_rate;
    
    // --- 2. UV Boiling (The Hand-drawn wobble) ---
    // We generate a random offset based on the stepped time, so the entire screen 
    // subtly shifts every frame, mimicking redrawn animation cels.
    float noise_val = rand(SCREEN_UV + stepped_time);
    vec2 wobble_offset = vec2(cos(noise_val * 6.2831), sin(noise_val * 6.2831)) * wobble_strength;
    vec2 distorted_uv = SCREEN_UV + wobble_offset;
    
    // --- 3. Edge Detection (Ink Lines) ---
    vec2 viewport_size = vec2(textureSize(screen_texture, 0));
    vec2 texel = vec2(1.0) / viewport_size * line_thickness;
    vec3 luma_weights = vec3(0.299, 0.587, 0.114);
    
    // Fetch a 3x3 grid around the wobbly pixel to draw the outlines
    float l00 = dot(texture(screen_texture, distorted_uv + vec2(-texel.x, -texel.y)).rgb, luma_weights);
    float l10 = dot(texture(screen_texture, distorted_uv + vec2(0.0, -texel.y)).rgb, luma_weights);
    float l20 = dot(texture(screen_texture, distorted_uv + vec2(texel.x, -texel.y)).rgb, luma_weights);
    
    float l01 = dot(texture(screen_texture, distorted_uv + vec2(-texel.x, 0.0)).rgb, luma_weights);
    float l21 = dot(texture(screen_texture, distorted_uv + vec2(texel.x, 0.0)).rgb, luma_weights);
    
    float l02 = dot(texture(screen_texture, distorted_uv + vec2(-texel.x, texel.y)).rgb, luma_weights);
    float l12 = dot(texture(screen_texture, distorted_uv + vec2(0.0, texel.y)).rgb, luma_weights);
    float l22 = dot(texture(screen_texture, distorted_uv + vec2(texel.x, texel.y)).rgb, luma_weights);
    
    // Calculate Sobel gradients
    float sobel_x = l00 + 2.0 * l01 + l02 - l20 - 2.0 * l21 - l22;
    float sobel_y = l00 + 2.0 * l10 + l20 - l02 - 2.0 * l12 - l22;
    float edge = sqrt(sobel_x * sobel_x + sobel_y * sobel_y);
    
    // --- 4. Branchless Composition ---
    float is_edge = step(edge_threshold, edge);
    
    // Get the base color using the wobbly UVs and multiply it by our paper tint
    vec3 base_color = texture(screen_texture, distorted_uv).rgb * paper_tint;
    
    // Overwrite the color with pure black if it falls on an edge
    vec3 final_color = mix(base_color, vec3(0.0), is_edge);
    
    COLOR = vec4(final_color, 1.0);
}