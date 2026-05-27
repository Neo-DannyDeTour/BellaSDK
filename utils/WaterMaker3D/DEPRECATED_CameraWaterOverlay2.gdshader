shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float clear_progress : hint_range(0.0, 1.5) = 1.5;

// AAA Parameters
uniform float ripple_magnitude : hint_range(0.0, 3) = 0.3;
uniform float ripple_speed : hint_range(0.0, 5.0) = 2.0;
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.008;
uniform vec4 water_tint : source_color = vec4(0.05, 0.3, 0.5, 0.25);
uniform float highlight_punch : hint_range(0.0, 1.0) = 0.02;

// Standard Voronoi function for organic "AAA" ripples
vec2 voronoi(vec2 uv) {
    vec2 p = floor(uv);
    vec2 f = fract(uv);
    float res = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 b = vec2(float(i), float(j));
            vec2 r = b - f + fract(sin(vec2(dot(p + b, vec2(127.1, 311.7)), dot(p + b, vec2(269.5, 183.3)))) * 43758.5453);
            res = min(res, dot(r, r));
        }
    }
    return vec2(sqrt(res), res);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    float mask = smoothstep(clear_progress - 0.4, clear_progress, uv.y);
    
    // 1. Generate Dynamic Ripples (Layered Voronoi)
    // We animate three different scales at different speeds
    float v1 = voronoi(uv * 4.0 + TIME * (ripple_speed * 0.5)).x;
    float v2 = voronoi(uv * 8.0 - TIME * ripple_speed).x;
    float v3 = voronoi(uv * 12.0 + cos(TIME)).x;
    
    // Combine for a complex, non-repeating pattern
    float combined_noise = (v1 * 0.5) + (v2 * 0.3) + (v3 * 0.2);
    
    // 2. Dynamic Distortion (Refraction)
    // We treat the noise as a heightmap and calculate a fake "Normal"
    vec2 distortion = vec2(dFdx(combined_noise), dFdy(combined_noise));
    vec2 final_uv = uv + (distortion * ripple_magnitude * mask);
    
    // 3. Chromatic Aberration
    float r = texture(screen_texture, final_uv + (vec2(chromatic_aberration) * mask)).r;
    float g = texture(screen_texture, final_uv).g;
    float b = texture(screen_texture, final_uv - (vec2(chromatic_aberration) * mask)).b;
    vec4 color = vec4(r, g, b, 1.0);
    
    // 4. Punchy Specular Highlights
    // This creates the "pretty" glints on the edges of the water ripples
    float highlights = smoothstep(0.4, 0.5, combined_noise) * highlight_punch * mask;
    color.rgb += highlights;
    
    // 5. Vibrant Tint & Vignette
    color.rgb = mix(color.rgb, water_tint.rgb, water_tint.a * mask);
    float dist = distance(uv, vec2(0.5));
    color.rgb *= smoothstep(0.8, 0.4, dist * 0.5 * mask);
    
    // 6. Contrast Boost
    color.rgb = pow(color.rgb, vec3(1.1));

    COLOR = color;
}