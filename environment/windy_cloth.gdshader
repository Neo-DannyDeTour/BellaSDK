shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D normal_texture;
uniform sampler2D urm_texture;
uniform sampler2D wind_noise_texture;

uniform float uv_scale = 1.0;
uniform float offset_multiplier = 1.0;

global uniform vec3 wind_direction;
global uniform float wind_intensity;
global uniform float wind_speed;

varying vec2 texture_uv;

float get_position_sum(vec3 world_position) {
    return world_position.x + world_position.y + world_position.z;
}

void vertex() {
    texture_uv = UV * uv_scale;

    mat3 inv_model_matrix = mat3(inverse(MODEL_MATRIX));
    vec3 wind_local_direction = normalize(inv_model_matrix * wind_direction);
    
    // UV.y creates a gradient from 0.0 (top edge) to 1.0 (bottom edge). 
    // This pins the top of the cloth so you can freely resize the mesh!
    float use_uv_mask = UV.y; 
    
    vec3 model_front_direction = vec3(1.0, 0.0, 0.0);
    float use_dot_product = dot(model_front_direction, wind_local_direction);
    float strength = abs(use_dot_product);
    float noise_strength = clamp(strength, 0.5, 1.0);
    
    vec3 model_side_direction = vec3(0.0, 0.0, 1.0);
    float side_dot = dot(model_side_direction, wind_local_direction);
    float scroll_direction = -1.0 * sign(side_dot);
    
    float wind_uv_scale = 0.1;
    float scroll_speed = wind_speed;
    
    float position_sum = get_position_sum(NODE_POSITION_WORLD);
    float wind_object_offset = position_sum * offset_multiplier;
    
    vec2 wind_uv = vec2(
        (VERTEX.z * wind_uv_scale) + (TIME * scroll_speed * scroll_direction) + wind_object_offset,
        VERTEX.y * wind_uv_scale
    );
    
    float wind_noise = texture(wind_noise_texture, wind_uv).r;
    wind_noise = 2.0 * wind_noise - 1.0;
    
    VERTEX.x += wind_noise * use_uv_mask * (wind_intensity * 0.5) * noise_strength;
}

void fragment() {
    vec4 albedo = texture(albedo_texture, texture_uv);
    ALBEDO = albedo.rgb;
    
    vec4 urm = texture(urm_texture, texture_uv);
    AO = urm.r;
    ROUGHNESS = urm.g;
    METALLIC = urm.b;
    
    NORMAL_MAP = texture(normal_texture, texture_uv).rgb;
}