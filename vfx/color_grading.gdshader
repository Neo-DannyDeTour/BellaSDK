shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

group_uniforms Base;
uniform float brightness : hint_range(0.0, 5.0) = 1.0;
uniform float contrast : hint_range(0.0, 5.0) = 1.0;
uniform float saturation : hint_range(0.0, 5.0) = 1.0;

group_uniforms WhiteBalance;
uniform float temperature : hint_range(-1.0, 1.0) = 0.0;
uniform float tint : hint_range(-1.0, 1.0) = 0.0;

group_uniforms ASC_CDL;
uniform vec3 lift_color = vec3(0.0);
uniform vec3 gamma_color = vec3(1.0);
uniform vec3 gain_color = vec3(1.0);

group_uniforms LUT;
uniform sampler3D lut_texture : filter_linear;
uniform float lut_intensity : hint_range(0.0, 1.0) = 0.0;

group_uniforms Lens;
uniform float aberration_amount : hint_range(0.0, 0.05) = 0.0;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.0;

// Helper function for film grain generation
float random(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    vec3 color;
    
    // 1. Chromatic Aberration (Sample separation)
    if (aberration_amount > 0.0) {
        float r = texture(screen_texture, SCREEN_UV + vec2(aberration_amount, 0.0)).r;
        float g = texture(screen_texture, SCREEN_UV).g;
        float b = texture(screen_texture, SCREEN_UV - vec2(aberration_amount, 0.0)).b;
        color = vec3(r, g, b);
    } else {
        color = texture(screen_texture, SCREEN_UV).rgb;
    }

    // 2. White Balance
    vec3 warm = vec3(1.0, 0.9, 0.8);
    vec3 cool = vec3(0.8, 0.9, 1.0);
    vec3 temp_shift = mix(vec3(1.0), mix(cool, warm, temperature * 0.5 + 0.5), abs(temperature));
    vec3 tint_shift = mix(vec3(1.0), vec3(1.0, 1.0 - tint * 0.5, 1.0 + tint * 0.5), abs(tint));
    color *= temp_shift * tint_shift;

    // 3. Base Adjustments
    color *= brightness;
    color = (color - 0.5) * contrast + 0.5;
    
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 grayscale = vec3(luminance);
    color = mix(grayscale, color, saturation);

    // 4. ASC CDL (Lift, Gamma, Gain)
    color = max(color * gain_color + lift_color, vec3(0.0));
    color = pow(color, 1.0 / max(gamma_color, vec3(0.0001)));

    // 5. 3D LUT Application
    if (lut_intensity > 0.0) {
        // We clamp the color to 0-1 range to sample the LUT texture safely
        vec3 clamped_color = clamp(color, 0.0, 1.0);
        vec3 lut_color = texture(lut_texture, clamped_color).rgb;
        color = mix(color, lut_color, lut_intensity);
    }

    // 6. Vignette
    if (vignette_intensity > 0.0) {
        float dist = distance(UV, vec2(0.5));
        float vignette = smoothstep(0.8, vignette_intensity * 0.79, dist);
        color *= (1.0 - vignette);
    }
    
    // 7. Film Grain
    if (grain_amount > 0.0) {
        float noise = (random(UV + TIME) - 0.5) * 2.0; // Noise from -1.0 to 1.0
        color += noise * grain_amount * 0.1; 
    }

    COLOR = vec4(color, COLOR.a);
}