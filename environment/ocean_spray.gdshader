shader_type spatial;
render_mode cull_back, unshaded, shadows_disabled;

global uniform vec4 water_color : source_color;
global uniform vec4 foam_color : source_color;

uniform float max_alpha : hint_range(0.0, 1.0) = 0.666;
uniform float brightness_multiplier : hint_range(1.0, 5.0) = 1.7;
uniform sampler2D albedo_texture : source_color, repeat_enable;
uniform sampler2D dissolve_texture : source_color, repeat_enable;

varying float dissolve_factor;
varying float alpha_fade;

void vertex() {
    // Particle Billboarding
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        normalize(INV_VIEW_MATRIX[0]),
        normalize(INV_VIEW_MATRIX[1]),
        normalize(INV_VIEW_MATRIX[2]),
        MODEL_MATRIX[3]
    );
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
        vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
        vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
        vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
        vec4(0.0, 0.0, 0.0, 1.0)
    );

    dissolve_factor = INSTANCE_CUSTOM.z;
    alpha_fade = INSTANCE_CUSTOM.w;
}

void fragment() {
    vec4 albedo_tex = texture(albedo_texture, UV);
    ALBEDO = albedo_tex.rgb * foam_color.rgb * brightness_multiplier;

    // FIX: Changed from an exponential fade that killed particles near the camera
    // to a smoothstep that only fades out geometry clipping into the near plane (0 to 2m).
    float distance_fade = smoothstep(0.0, 2.0, -VERTEX.z); 
    
    ALPHA = albedo_tex.a * max_alpha;
    ALPHA *= distance_fade; 
    
    float dissolve_value = texture(
        dissolve_texture,
        UV + vec2(TIME * 0.35)
    ).x;
    
    ALPHA *= clamp(
        alpha_fade + (dissolve_factor * 0.5) - (dissolve_value * 0.5),
        0.0,
        1.0
    );
}