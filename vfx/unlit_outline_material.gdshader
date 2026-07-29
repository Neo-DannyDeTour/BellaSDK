shader_type spatial;
// Blend mix combined with screen sampling gives us the high contrast inversion needed for sunlight.
render_mode unshaded, blend_mix, depth_test_disabled, cull_back; 

uniform vec4 highlight_color : source_color = vec4(0.0, 1.0, 0.5, 1.0);
uniform float blink_speed : hint_range(0.0, 20.0) = 8.0; 
uniform float min_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float max_intensity : hint_range(0.0, 5.0) = 1.0; 

uniform sampler2D base_texture : source_color, filter_linear_mipmap;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

// Required to calculate color inversion for extreme sunlight visibility
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Instance parameter set strictly from GDScript. 
// Uses 1 shared material resource while allowing branched behavior!
instance uniform bool is_billboard = false;

void vertex() {
    if (is_billboard) {
        // Only run billboard distortion on 2D Quads/Planes
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
        
        MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
            vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
            vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
            vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
            vec4(0.0, 0.0, 0.0, 1.0)
        );
        
        MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
    }
}

void fragment() {
    float rim_alpha = 1.0;

    if (is_billboard) {
        float tex_alpha = texture(base_texture, UV).a;
        if (tex_alpha < alpha_scissor_threshold) {
            discard;
        }
    } else {
        // Calculate a glowing border (Fresnel effect) for 3D objects
        // This ensures the edges are distinct while the center still lightly glows.
        float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
        rim_alpha = clamp(fresnel + 0.3, 0.0, 1.0); 
    }

    float pulse = (sin(TIME * blink_speed) + 1.0) / 2.0;
    float current_intensity = mix(min_intensity, max_intensity, pulse);
    
    // Sunlight check: Read the existing screen pixels behind the overlay and invert them
    vec3 background_color = texture(screen_texture, SCREEN_UV).rgb;
    vec3 inverted_background = vec3(1.0) - background_color;
    
    // Mix the inverted screen color with the chosen highlight color
    vec3 final_color = mix(inverted_background, highlight_color.rgb, 0.6);
    
    ALBEDO = final_color;
    // Multiplied by rim_alpha to maintain the solid outline border on 3D geometry
    ALPHA = current_intensity * rim_alpha;
}