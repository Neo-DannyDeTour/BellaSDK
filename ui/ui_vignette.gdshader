shader_type canvas_item;

uniform vec4 color: source_color;
uniform float multiplier = 0.2;
uniform float softness = 3.0;
uniform float vignette_opacity = 0.0;

void fragment() {
    float value = distance(UV, vec2(0.5));
    float base_alpha = smoothstep(multiplier, softness, value);
    COLOR = vec4(color.rgb, base_alpha * vignette_opacity);
}
