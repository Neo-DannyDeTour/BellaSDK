shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Kept small so the UV shift doesn't bleed into other letters in the Godot font atlas
uniform vec2 max_offset = vec2(0.01, 0.0); 
uniform float phase_edge : hint_range(0.0, 0.5) = 0.25;

void fragment() {
    // 1. Calculate animation phases
    float t_in = smoothstep(0.0, phase_edge, progress);
    float t_out = smoothstep(1.0 - phase_edge, 1.0, progress);

    float split_amount = (1.0 - t_in) + t_out;
    float alpha_multiplier = t_in * (1.0 - t_out);

    // 2. Calculate offsets
    vec2 r_offset = max_offset * split_amount;
    vec2 b_offset = -max_offset * split_amount;

    // 3. Read the standard font alpha channel (Godot 4 default text rendering)
    float r_mask = texture(TEXTURE, UV + r_offset).a;
    float g_mask = texture(TEXTURE, UV).a;
    float b_mask = texture(TEXTURE, UV + b_offset).a;

    // 4. Combine masks for the final alpha
    float final_alpha = max(max(r_mask, g_mask), b_mask) * COLOR.a * alpha_multiplier;

    // 5. Color Mixing
    vec3 split_colors = vec3(r_mask, g_mask, b_mask);
    vec3 base_text_color = COLOR.rgb * g_mask;
    
    vec3 final_color = mix(base_text_color, split_colors, clamp(split_amount * 2.0, 0.0, 1.0));

    COLOR = vec4(final_color, final_alpha);
}