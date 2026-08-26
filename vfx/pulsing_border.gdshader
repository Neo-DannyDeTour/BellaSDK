shader_type canvas_item;

uniform vec4 border_color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float border_width : hint_range(0.0, 0.2) = 0.08;
uniform float pulse_speed : hint_range(0.0, 15.0) = 6.0;
uniform float min_alpha : hint_range(0.0, 1.0) = 0.3;
uniform float max_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    float dist_x = min(UV.x, 1.0 - UV.x);
    float dist_y = min(UV.y, 1.0 - UV.y);
    float edge_dist = min(dist_x, dist_y);

    if (edge_dist < border_width) {
        float pulse = mix(min_alpha, max_alpha, 0.5 + 0.5 * sin(TIME * pulse_speed));
        COLOR = vec4(border_color.rgb, border_color.a * pulse);
    } else {
        COLOR = vec4(0.0);
    }
}
