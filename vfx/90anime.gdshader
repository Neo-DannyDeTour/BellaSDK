shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// --- Color Grading ---
uniform float saturation : hint_range(0.0, 2.0) = 1.3;
uniform float contrast : hint_range(0.0, 2.0) = 1.2;
uniform vec3 shadow_tint : source_color = vec3(0.15, 0.10, 0.25); // Deep purplish shadow
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.95, 0.90); // Warm highlight

// --- Retro Imperfections ---
uniform float grain_speed : hint_range(0.1, 10.0) = 1.0;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.05;
uniform float vignette_strength : hint_range(0.0, 3.0) = 1.2;
uniform float chromatic_strength : hint_range(0.0, 0.02) = 0.004;

// Basic pseudo-random noise generator
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 dir = uv - vec2(0.5);
    
    // 1. Chromatic Aberration (RGB shift radiating from center)
    vec2 offset = dir * chromatic_strength;
    float r = texture(screen_texture, uv - offset).r;
    float g = texture(screen_texture, uv).g;
    float b = texture(screen_texture, uv + offset).b;
    vec3 col = vec3(r, g, b);
    
    // 2. Luma Calculation for Contrast & Saturation
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, saturation);
    col = mix(vec3(0.5), col, contrast);
    
    // 3. Fake Cel-Shading Tint
    // Smoothly remaps the darks to purple and the lights to warm white
    vec3 graded_color = mix(shadow_tint * col, highlight_tint * col, smoothstep(0.1, 0.8, luma));
    
    // Blend the harsh tint back with the contrast-adjusted original color 
    col = mix(col, graded_color, 0.7);
    
    // 4. Animated Film Grain
    float grain = rand(uv + fract(TIME * grain_speed)) * grain_strength;
    col -= grain;
    
    // 5. Vignette (Darkens the corners)
    float vignette = clamp(1.0 - dot(dir, dir) * vignette_strength, 0.0, 1.0);
    col *= vignette;
    
    // Clamp to ensure colors don't blow out past standard bounds
    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}