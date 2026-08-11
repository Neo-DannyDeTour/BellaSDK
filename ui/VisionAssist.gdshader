shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, cull_disabled;

// We removed screen_texture entirely for better performance
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

uniform float outline_thickness = 1.0;
uniform float depth_threshold = 0.025;
uniform float normal_threshold = 0.5;

void vertex() {
    // Snap the quad to the screen space
    POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
    vec2 screen_uv = SCREEN_UV;
    vec2 texel = (1.0 / VIEWPORT_SIZE) * outline_thickness;
    
    // --- EDGE DETECTION ---
    float d_center = texture(depth_texture, screen_uv).x;
    float d_up = texture(depth_texture, screen_uv + vec2(0.0, texel.y)).x;
    float d_down = texture(depth_texture, screen_uv + vec2(0.0, -texel.y)).x;
    float d_left = texture(depth_texture, screen_uv + vec2(texel.x, 0.0)).x;
    float d_right = texture(depth_texture, screen_uv + vec2(-texel.x, 0.0)).x;
    
    float depth_edge = abs(d_center - d_up) + abs(d_center - d_down) + 
                       abs(d_center - d_left) + abs(d_center - d_right);
    
    vec3 n_center = texture(normal_texture, screen_uv).rgb;
    vec3 n_up = texture(normal_texture, screen_uv + vec2(0.0, texel.y)).rgb;
    vec3 n_down = texture(normal_texture, screen_uv + vec2(0.0, -texel.y)).rgb;
    vec3 n_left = texture(normal_texture, screen_uv + vec2(texel.x, 0.0)).rgb;
    vec3 n_right = texture(normal_texture, screen_uv + vec2(-texel.x, 0.0)).rgb;
    
    float normal_edge = distance(n_center, n_up) + distance(n_center, n_down) + 
                         distance(n_center, n_left) + distance(n_center, n_right);
    
    // --- FINAL COMPOSITING ---
    if ((depth_edge > depth_threshold) || (normal_edge > normal_threshold)) {
        ALBEDO = outline_color.rgb;
    } else {
        ALBEDO = base_color.rgb;
    }
}