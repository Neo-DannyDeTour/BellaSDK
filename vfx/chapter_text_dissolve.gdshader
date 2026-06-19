shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0);
uniform vec4 burn_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);

float hash(vec2 p) {
    return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x))));
}

void fragment() {
    vec2 uv = UV;
    vec4 tex_color = texture(TEXTURE, uv);
    float noise_val = hash(floor(uv * 20.0));
    
    // Threshold smoothly scales: 0.0 (start) -> 1.0 (hold) -> 0.0 (end)
    float threshold = smoothstep(0.0, 0.2, progress) - smoothstep(0.8, 1.0, progress);
    
    // Pixel is visible if noise is below the threshold
    float alpha_mask = step(noise_val, threshold);
    float burn_mask = step(noise_val, threshold + 0.1) - alpha_mask;
    
    vec4 final_color = mix(tex_color, burn_color, burn_mask);
    final_color.a *= alpha_mask * tex_color.a;
    
    COLOR = final_color;
}