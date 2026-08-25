shader_type canvas_item;

uniform vec4 vignette_color : source_color = vec4(0.0, 1.0, 0.2, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.3;
uniform float outer_radius : hint_range(0.0, 1.0) = 0.75;

void fragment() {
    vec2 centered_uv = UV - vec2(0.5);
    float dist = length(centered_uv);
    float vignette = smoothstep(inner_radius, outer_radius, dist);
    COLOR = vec4(vignette_color.rgb, vignette * intensity * vignette_color.a);
}
