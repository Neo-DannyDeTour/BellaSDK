shader_type canvas_item;

// Bound to the Tween in your _play_shader_effect function
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// --- Wave & Refraction Settings ---
uniform float wave_speed : hint_range(0.1, 5.0, 0.1) = 1.2;
uniform float wave_frequency : hint_range(0.1, 10.0, 0.1) = 1.5;
uniform float wave_width : hint_range(0.01, 0.5, 0.01) = 0.15;
uniform float refraction_strength : hint_range(0.0, 0.05, 0.001) = 0.015; 

// --- VHS & Noise Settings ---
uniform float aberration_amount : hint_range(0.0, 0.02, 0.001) = 0.004;
uniform float dither_intensity : hint_range(0.0, 1.0, 0.01) = 0.15;

// Fast pseudo-random number generator
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;

    // --- 1. Rolling Wave Calculation ---
    float wave_phase = fract(uv.y * wave_frequency - TIME * wave_speed);
    
    // Safely calculate the hump for Vulkan (ascending edge * descending edge)
    float wave_up = smoothstep(0.0, wave_width * 0.5, wave_phase);
    float wave_down = 1.0 - smoothstep(wave_width * 0.5, wave_width, wave_phase);
    float wave_band = wave_up * wave_down;

    // --- 2. Dither & Static Generation ---
    float time_step = floor(TIME * 24.0);
    float noise_val = rand(FRAGCOORD.xy + vec2(time_step));
    
    // --- 3. Refraction / UV Distortion ---
    vec2 refracted_uv = uv;
    refracted_uv.x += wave_band * (refraction_strength + ((noise_val - 0.5) * 0.01));

    // --- 4. Chromatic Aberration ---
    // We sample TEXTURE instead of screen_texture
    float r = texture(TEXTURE, refracted_uv + vec2(aberration_amount, 0.0)).r;
    float g = texture(TEXTURE, refracted_uv).g;
    float b = texture(TEXTURE, refracted_uv - vec2(aberration_amount, 0.0)).b;
    float a = texture(TEXTURE, refracted_uv).a;
    
    vec4 tex_color = vec4(r, g, b, a);

    // --- 5. Applying Dither & Wave Highlights ---
    // We multiply the noise additions by 'a' so the static only appears 
    // ON the text, rather than filling the empty space of the UI container.
    tex_color.rgb += (noise_val - 0.5) * dither_intensity * a;
    tex_color.rgb += wave_band * noise_val * 0.35 * a;

    // --- 6. Sequence Fade ---
    // Uses the Tween progress to fade the sequence in and out gracefully
    float fade = smoothstep(0.0, 0.1, progress) * (1.0 - smoothstep(0.9, 1.0, progress));
    tex_color.a *= fade;

    COLOR = tex_color;
}