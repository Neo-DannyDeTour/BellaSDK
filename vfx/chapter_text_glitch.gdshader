shader_type canvas_item;

// The progress uniform is driven by your Tween (0.0 to 1.0)
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.2;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;
    float time_snap = floor(TIME * 15.0);
    float block_y = floor(uv.y * 25.0);
    
    // 1. Progress Envelope: Handle fade-in, fade-out, and glitch timing
    float alpha_env = 1.0;
    float glitch_chance = 0.0;
    
    if (progress < 0.15) {
        // Fade in rapidly; heavy glitching
        alpha_env = smoothstep(0.0, 0.15, progress);
        glitch_chance = 1.0; 
    } else if (progress > 0.85) {
        // Fade out gracefully; heavy glitching
        alpha_env = smoothstep(1.0, 0.85, progress);
        glitch_chance = 1.0; 
    } else {
        // Idle phase: 5% chance of a random glitch spike to keep it feeling alive
        glitch_chance = step(0.95, rand(vec2(TIME, 0.0)));
    }

    // 2. Calculate the horizontal tearing offset
    float offset = (rand(vec2(block_y, time_snap)) - 0.5) * intensity * 0.5;
    float is_glitching = step(0.85, rand(vec2(block_y, time_snap + 1.0))) * glitch_chance;
    
    uv.x += offset * is_glitching;
    
    // 3. Chromatic Aberration for Font Textures
    // We keep the shift small (0.01) to prevent bleeding into other atlas characters.
    vec2 rgb_shift = vec2(0.01 * is_glitching, 0.0);
    
    float r_alpha = texture(TEXTURE, uv + rgb_shift).a;
    float g_alpha = texture(TEXTURE, uv).a;
    float b_alpha = texture(TEXTURE, uv - rgb_shift).a;
    
    // 4. Final Color Assembly
    // COLOR.rgb contains the text_color you passed via add_theme_color_override
    vec3 text_color = COLOR.rgb;
    vec3 split_color = vec3(r_alpha, g_alpha, b_alpha) * text_color;
    
    // Combine the maximum alpha bounds with your script's Tween fade
    float final_alpha = max(max(r_alpha, g_alpha), b_alpha) * alpha_env * COLOR.a;
    
    COLOR = vec4(split_color, final_alpha);
}