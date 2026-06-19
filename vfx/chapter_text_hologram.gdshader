shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 1.0;

// Base colors
uniform vec4 base_color : source_color = vec4(0.0, 0.4, 0.8, 1.0); // Now White
uniform vec4 glitch_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // The Blue flash
uniform vec4 line_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);

// Hologram settings
uniform float speed = 2.0;
uniform float line_count = 15.0;
uniform float line_thickness : hint_range(0.01, 1.0) = 0.1;
uniform float glow_multiplier = 1.5;

// Glitch settings
uniform float spatial_glitch_intensity : hint_range(0.0, 0.1) = 0.003;
uniform float color_glitch_chance : hint_range(0.0, 1.0) = 0.05; // 5% chance to glitch
uniform float color_glitch_speed = 15.0; // How many times per second the RNG rolls

// Highly optimized pseudo-random number generator
float rand(float n) {
    return fract(sin(n) * 43758.5453123);
}

void fragment() {
    // 1. Calculate when to trigger the color glitch
    // Floor the time to create distinct "ticks" rather than a smooth gradient
    float tick = floor(TIME * color_glitch_speed);
    
    // Returns 1.0 if the random roll hits the chance threshold, otherwise 0.0
    float is_glitching = step(1.0 - color_glitch_chance, rand(tick));
    
    // Pick the active color for this exact frame
    vec4 active_base_color = mix(base_color, glitch_color, is_glitching);

    // 2. Add extra wobble if a color glitch is currently happening
    float current_wobble = spatial_glitch_intensity + (is_glitching * 0.015);
    float wobble = sin(UV.y * 50.0 + (TIME * 15.0)) * current_wobble;
    vec2 distorted_uv = vec2(UV.x + wobble, UV.y);
    
    vec4 text_texture = texture(TEXTURE, distorted_uv);

    // 3. Scanline math
    float moving_phase = (distorted_uv.y * line_count) + (TIME * speed);
    float gradient = fract(moving_phase);

    float distance_to_center = abs(gradient - 0.5) * 2.0;
    float peak = 1.0 - distance_to_center;

    float sharpness = 10.0 / line_thickness;
    float line_mask = pow(peak, sharpness);

    // 4. Apply colors using the actively chosen base color
    vec3 final_rgb = mix(active_base_color.rgb, line_color.rgb, line_mask);
    final_rgb += (line_color.rgb * line_mask * glow_multiplier);

    // 5. Calculate fade arc and final alpha
    float fade_arc = sin(progress * PI);
    float scanline_alpha = mix(active_base_color.a, line_color.a, line_mask);
    float final_alpha = scanline_alpha * text_texture.a * COLOR.a * fade_arc;

    COLOR = vec4(final_rgb, final_alpha);
}