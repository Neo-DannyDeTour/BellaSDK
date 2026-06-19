shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Tweak this to make the red/blue spread wider or tighter
uniform vec2 max_offset = vec2(0.015, 0.0); 
uniform float phase_edge : hint_range(0.0, 0.5) = 0.25;

void fragment() {
    // 1. Separate the alpha fade from the movement
    // The text needs to fade in almost instantly so you can actually see it travel
    float alpha_in = smoothstep(0.0, 0.1, progress);
    float alpha_out = smoothstep(0.9, 1.0, progress);
    float alpha_multiplier = alpha_in * (1.0 - alpha_out);

    // 2. Movement phase (1.0 at start, 0.0 in middle, 1.0 at end)
    float move_in = smoothstep(0.0, phase_edge, progress);
    float move_out = smoothstep(1.0 - phase_edge, 1.0, progress);
    float split_amount = (1.0 - move_in) + move_out;

    // 3. Calculate dynamic UV offsets
    vec2 offset = max_offset * split_amount;

    // 4. Directly sample the physical RGB channels of the Viewport texture
    // We physically read the red channel from slightly left, and blue from slightly right
    float r = texture(TEXTURE, UV + offset).r;
    float g = texture(TEXTURE, UV).g;
    float b = texture(TEXTURE, UV - offset).b;

    // 5. Sample alphas to ensure the offset red/blue colors don't get cut off
    float a_r = texture(TEXTURE, UV + offset).a;
    float a_g = texture(TEXTURE, UV).a;
    float a_b = texture(TEXTURE, UV - offset).a;

    // 6. Combine
    vec3 final_color = vec3(r, g, b);
    float final_alpha = max(max(a_r, a_g), a_b) * alpha_multiplier;

    COLOR = vec4(final_color, final_alpha);
}