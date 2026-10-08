shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled;

// --- COLOR UNIFORMS ---
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float core_intensity : hint_range(1.0, 25.0) = 8.0;
uniform float glow_intensity : hint_range(0.1, 10.0) = 3.0;

// --- FALLOFF CONTROLS ---
uniform float core_falloff : hint_range(1.0, 32.0) = 8.0;
uniform float glow_falloff : hint_range(0.5, 6.0) = 1.8;

// --- TURBULENCE SPEED ---
uniform float noise_speed : hint_range(1.0, 40.0) = 18.0;
uniform float pulse_speed : hint_range(1.0, 50.0) = 28.0;

float fast_hash(float p) {
    return fract(sin(p * 12.9898) * 43758.5453);
}

void fragment() {
    // Ribbon center distance (0.0 at center line, 1.0 at outer borders)
    float center_dist = abs(UV.x - 0.5) * 2.0;

    // Traveling wave ripple
    float travel = UV.y * 12.0 - TIME * noise_speed;
    float wave_noise = sin(travel) * cos(travel * 2.3);
    float flicker = mix(0.85, 1.15, fast_hash(floor(TIME * pulse_speed)));

    // Core vs Corona masks
    float core_mask = pow(clamp(1.0 - center_dist, 0.0, 1.0), core_falloff);
    float glow_mask = pow(clamp(1.0 - center_dist, 0.0, 1.0), glow_falloff);
    glow_mask *= clamp(1.0 + wave_noise * 0.35, 0.0, 2.0);

    // End contact fade
    float endpoint_fade = clamp(sin(UV.y * PI) * 2.0, 0.0, 1.0);

    // Direct emission calculations
    vec3 out_core = core_color.rgb * core_mask * core_intensity;
    vec3 out_glow = glow_color.rgb * glow_mask * glow_intensity;
    vec3 total_light = (out_core + out_glow) * (flicker * endpoint_fade);

    // With blend_add, ALBEDO directly contributes the additive color values
    ALBEDO = total_light;
    EMISSION = total_light;
}
