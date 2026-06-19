shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sweep_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);

    // 1. Calculate a diagonal line moving across the text
    float sweep_pos = progress * 2.5 - 0.25;
    float dist = abs((UV.x + UV.y) - sweep_pos);

    // 2. The Fix: standard smoothstep, then inverted. 
    // This creates a sharp, bright line that safely falls off to 0.0
    float sweep_intensity = 1.0 - smoothstep(0.0, 0.15, dist);

    // 3. Additive blend the bright line over the base text.
    // We multiply by 2.0 so it artificially blooms/brightens even on white text.
    tex_color.rgb += (sweep_color.rgb * sweep_intensity * 2.0) * tex_color.a;

    // 4. Alpha fade logic bound to the tween
    float fade = smoothstep(0.0, 0.1, progress) * (1.0 - smoothstep(0.9, 1.0, progress));
    tex_color.a *= fade;

    COLOR = tex_color;
}