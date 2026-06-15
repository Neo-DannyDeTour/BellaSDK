shader_type spatial;
// Added depth_test_disabled here!
render_mode unshaded, blend_add, depth_test_disabled; 

uniform vec4 highlight_color : source_color = vec4(0.0, 1.0, 0.5, 1.0);
uniform float blink_speed : hint_range(0.0, 20.0) = 8.0; 
uniform float min_intensity : hint_range(0.0, 1.0) = 0.01;
uniform float max_intensity : hint_range(0.0, 5.0) = 0.05; 

void fragment() {
    float pulse = (sin(TIME * blink_speed) + 1.0) / 2.0;
    float current_intensity = mix(min_intensity, max_intensity, pulse);
    
    ALBEDO = highlight_color.rgb * highlight_color.a * current_intensity;
}