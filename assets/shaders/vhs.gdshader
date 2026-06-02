shader_type canvas_item;

// --- Screen Texture ---
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// --- Wave & Refraction Settings ---
uniform float wave_speed : hint_range(0.1, 5.0, 0.1) = 1.2;
uniform float wave_frequency : hint_range(0.1, 10.0, 0.1) = 1.5;
uniform float wave_width : hint_range(0.01, 0.5, 0.01) = 0.15;
// The amount the wave distorts the background (refraction)
uniform float refraction_strength : hint_range(0.0, 0.05, 0.001) = 0.015; 

// --- VHS & Noise Settings ---
uniform float aberration_amount : hint_range(0.0, 0.02, 0.001) = 0.004;
uniform float dither_intensity : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float desaturation : hint_range(0.0, 1.0, 0.01) = 0.4;

// Fast pseudo-random number generator for our dither and static
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = SCREEN_UV;

    // --- 1. Rolling Wave Calculation ---
    // Calculate a phase that moves downwards over time
    float wave_phase = fract(uv.y * wave_frequency - TIME * wave_speed);
    
    // Create a smooth band for the wave using smoothstep. 
    // This creates a hump that peaks in the middle of the width.
    float wave_band = smoothstep(0.0, wave_width * 0.5, wave_phase) * smoothstep(wave_width, wave_width * 0.5, wave_phase);

    // --- 2. Dither & Static Generation ---
    // Generate a noise value based on the pixel coordinate and a stepped time value (for 24fps jitter)
    float time_step = floor(TIME * 24.0);
    float noise_val = rand(FRAGCOORD.xy + vec2(time_step));
    
    // --- 3. Refraction / UV Distortion ---
    // Distort the UV horizontally where the wave is active.
    // We add a tiny bit of the noise to the distortion to give the refraction a "rippling" VHS tear effect.
    vec2 refracted_uv = uv;
    refracted_uv.x += wave_band * (refraction_strength + ((noise_val - 0.5) * 0.01));

    // --- 4. Chromatic Aberration ---
    // Sample the background using the refracted UVs, shifting Red and Blue slightly
    float r = texture(screen_texture, refracted_uv + vec2(aberration_amount, 0.0)).r;
    float g = texture(screen_texture, refracted_uv).g;
    float b = texture(screen_texture, refracted_uv - vec2(aberration_amount, 0.0)).b;
    vec3 color = vec3(r, g, b);

    // --- 5. Color Grading (Desaturation) ---
    // Standard luminance calculation
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(color, vec3(luma), desaturation);

    // --- 6. Applying Dither & Wave Highlights ---
    // Apply baseline global dither to add texture to the whole screen
    color += (noise_val - 0.5) * dither_intensity;
    
    // Add bright, intense static specifically inside the wave band to simulate tracking errors
    color += wave_band * noise_val * 0.35;

    COLOR = vec4(color, 1.0);
}