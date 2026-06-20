shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Halftone Pattern Settings
uniform float resolution_scale : hint_range(0.1, 10.0) = 4.0;
uniform float dot_size : hint_range(0.1, 2.0) = 1.0;

// Edge Detection Settings
uniform float edge_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float edge_thickness : hint_range(0.5, 3.0) = 1.0;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec3 luma_weights = vec3(0.299, 0.587, 0.114);
    
    // Get the viewport size dynamically from the screen texture
    vec2 viewport_size = vec2(textureSize(screen_texture, 0));
    
    // --- 1. Sobel Edge Detection ---
    // Calculate the size of one pixel on screen
    vec2 texel = vec2(1.0) / viewport_size * edge_thickness;
    
    // Fetch a 3x3 grid around the current pixel and convert to Luma (grayscale)
    float l00 = dot(texture(screen_texture, uv + vec2(-texel.x, -texel.y)).rgb, luma_weights);
    float l10 = dot(texture(screen_texture, uv + vec2(0.0, -texel.y)).rgb, luma_weights);
    float l20 = dot(texture(screen_texture, uv + vec2(texel.x, -texel.y)).rgb, luma_weights);
    
    float l01 = dot(texture(screen_texture, uv + vec2(-texel.x, 0.0)).rgb, luma_weights);
    float l21 = dot(texture(screen_texture, uv + vec2(texel.x, 0.0)).rgb, luma_weights);
    
    float l02 = dot(texture(screen_texture, uv + vec2(-texel.x, texel.y)).rgb, luma_weights);
    float l12 = dot(texture(screen_texture, uv + vec2(0.0, texel.y)).rgb, luma_weights);
    float l22 = dot(texture(screen_texture, uv + vec2(texel.x, texel.y)).rgb, luma_weights);
    
    // Calculate X and Y gradients
    float sobel_x = l00 + 2.0 * l01 + l02 - l20 - 2.0 * l21 - l22;
    float sobel_y = l00 + 2.0 * l10 + l20 - l02 - 2.0 * l12 - l22;
    float edge = sqrt(sobel_x * sobel_x + sobel_y * sobel_y);
    
    // --- 2. Base Luma & Screentone ---
    float luma = dot(texture(screen_texture, uv).rgb, luma_weights);
    
    // Scale screen coordinates for the dot grid using the dynamic viewport size
    vec2 screen_coord = uv * viewport_size / resolution_scale;
    
    // Rotate coordinates 45 degrees for that classic manga screentone angle
    vec2 rot_coord = vec2(
        screen_coord.x * 0.707 - screen_coord.y * 0.707,
        screen_coord.x * 0.707 + screen_coord.y * 0.707
    );
    
    // Get the distance from the center of the current dot cell
    vec2 dot_coord = fract(rot_coord) - 0.5;
    float dist = length(dot_coord);
    
    // Radius scales inversely with luma (darker base color = bigger dots)
    float radius = (1.0 - luma) * dot_size;
    
    // --- 3. Branchless Composition ---
    // Generate masks without using if/else
    float is_edge = step(edge_threshold, edge);
    float is_highlight = step(0.75, luma);
    float is_shadow = 1.0 - step(0.25, luma);
    
    // Draw the halftone dot (smoothstep adds slight anti-aliasing to the dots)
    float tone = smoothstep(radius - 0.05, radius + 0.05, dist);
    
    // Overwrite the dot pattern with pure white in highlights and pure black in shadows
    tone = mix(tone, 1.0, is_highlight);
    tone = mix(tone, 0.0, is_shadow);
    
    // Finally, force black outlines on top of everything
    float final_color = mix(tone, 0.0, is_edge);
    
    COLOR = vec4(vec3(final_color), 1.0);
}