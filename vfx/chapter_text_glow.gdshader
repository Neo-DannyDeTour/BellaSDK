shader_type canvas_item;

// Driven by your _play_shader_effect Tween (0.0 to 1.0)
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Glow configuration
uniform float pulse_speed : hint_range(1.0, 10.0) = 3.0;
uniform float pulse_intensity : hint_range(0.0, 5.0) = 2.0;
// Keep spread low (e.g., 0.005) to prevent sampling neighboring letters in the font atlas
uniform float glow_spread : hint_range(0.0, 0.02) = 0.006; 

void fragment() {
    vec2 uv = UV;
    
    // 1. Progress Envelope: Smooth fade in (first 15%) and fade out (last 15%)
    float alpha_env = 1.0;
    if (progress < 0.15) {
        alpha_env = smoothstep(0.0, 0.15, progress);
    } else if (progress > 0.85) {
        alpha_env = smoothstep(1.0, 0.85, progress);
    }

    // 2. Base text alpha
    float base_a = texture(TEXTURE, uv).a;
    
    // 3. Optimized 4-Tap Radial Glow (Sampling diagonals)
    float glow_a = 0.0;
    glow_a += texture(TEXTURE, uv + vec2(glow_spread, glow_spread)).a;
    glow_a += texture(TEXTURE, uv + vec2(-glow_spread, glow_spread)).a;
    glow_a += texture(TEXTURE, uv + vec2(glow_spread, -glow_spread)).a;
    glow_a += texture(TEXTURE, uv + vec2(-glow_spread, -glow_spread)).a;
    
    // Average out the 4 samples
    glow_a *= 0.25;

    // 4. Calculate the pulsating multiplier using a sine wave over TIME
    // Mapped from [-1.0, 1.0] to [0.2, 1.0] so the glow never completely vanishes
    float pulse_wave = (sin(TIME * pulse_speed) * 0.4 + 0.6) * pulse_intensity;
    
    // 5. Assemble Final Color
    vec3 text_color = COLOR.rgb;
    
    // Add the glow on top of the base text, multiplied by the pulse
    vec3 final_color = text_color + (text_color * glow_a * pulse_wave);
    
    // Combine base alpha and glow alpha, masking it by the Tween's progress envelope
    float final_alpha = max(base_a, glow_a) * alpha_env * COLOR.a;
    
    COLOR = vec4(final_color, final_alpha);
}