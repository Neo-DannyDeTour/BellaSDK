//shader_type spatial;
//// Added depth_test_disabled here!
//render_mode unshaded, blend_add, depth_test_disabled; 
//
//uniform vec4 highlight_color : source_color = vec4(0.0, 1.0, 0.5, 1.0);
//uniform float blink_speed : hint_range(0.0, 20.0) = 8.0; 
//uniform float min_intensity : hint_range(0.0, 1.0) = 0.01;
//uniform float max_intensity : hint_range(0.0, 5.0) = 0.05; 
//
//void fragment() {
    //float pulse = (sin(TIME * blink_speed) + 1.0) / 2.0;
    //float current_intensity = mix(min_intensity, max_intensity, pulse);
    //
    //ALBEDO = highlight_color.rgb * highlight_color.a * current_intensity;
//}

shader_type spatial;
// Removed the invalid flag from render_mode
render_mode unshaded, blend_add, depth_test_disabled, cull_back; 

uniform vec4 highlight_color : source_color = vec4(0.0, 1.0, 0.5, 1.0);
uniform float blink_speed : hint_range(0.0, 20.0) = 8.0; 
uniform float min_intensity : hint_range(0.0, 1.0) = 0.01;
uniform float max_intensity : hint_range(0.0, 5.0) = 0.05; 

uniform sampler2D base_texture : source_color, filter_linear_mipmap;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

void vertex() {
    // 1. Orient the mesh to constantly face the active camera
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    
    // 2. Re-apply the node's local scale so your _beat_tween still works
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
        vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
        vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
        vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
        vec4(0.0, 0.0, 0.0, 1.0)
    );
    
    // 3. Update the normal matrix to prevent lighting/shading glitches
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    float tex_alpha = texture(base_texture, UV).a;
    
    if (tex_alpha < alpha_scissor_threshold) {
        discard;
    }

    float pulse = (sin(TIME * blink_speed) + 1.0) / 2.0;
    float current_intensity = mix(min_intensity, max_intensity, pulse); 
    
    ALBEDO = highlight_color.rgb * highlight_color.a * current_intensity;
}