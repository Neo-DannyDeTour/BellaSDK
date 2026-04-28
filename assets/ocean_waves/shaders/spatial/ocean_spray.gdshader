shader_type spatial;
render_mode cull_back, unshaded, shadows_disabled;

/**
 * Handles the opacity and billboarding for the sea spray mesh.
 */

global uniform vec4 water_color : source_color;
global uniform vec4 foam_color : source_color;

uniform float max_alpha : hint_range(0.0, 1.0) = 0.666;
uniform float brightness_multiplier : hint_range(1.0, 5.0) = 1.7; // Replaces hardcoded vec3
uniform sampler2D albedo_texture : source_color, repeat_enable;
uniform sampler2D dissolve_texture : source_color, repeat_enable;

varying float dissolve_factor;
varying float alpha_fade;

void vertex() {
    // Particle Billboarding (Keep Scale)
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));

    // Read custom data passed from the GPUParticles3D node
    dissolve_factor = INSTANCE_CUSTOM.z;
    alpha_fade = INSTANCE_CUSTOM.w;
}

void fragment() {
    vec4 albedo_tex = texture(albedo_texture, UV);
    
    // Apply albedo, global foam color, and brightness multiplier
    ALBEDO = albedo_tex.rgb * foam_color.rgb * brightness_multiplier;

    // Fade based on actual distance from the camera (depth) to prevent clipping
    float distance_fade = 1.0 - exp(VERTEX.z * 0.04); 
    
    ALPHA = albedo_tex.a * max_alpha;
    ALPHA *= clamp(distance_fade, 0.0, 1.0); // Clamped to prevent negative alpha errors
    
    // Organic dissolve using noise texture and particle lifetime
    float dissolve_value = texture(dissolve_texture, UV + vec2(TIME * 0.35)).x;
    ALPHA *= max((alpha_fade + dissolve_factor) * 0.5 - dissolve_value, 0.0);
}