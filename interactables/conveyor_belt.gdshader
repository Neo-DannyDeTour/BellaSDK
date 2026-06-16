shader_type spatial;

instance uniform float scroll_speed = 2.0;
instance uniform float rotation_angle = 0.0;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float texture_scale = 1.0;

varying vec2 final_uv;

void vertex() {
    vec2 pos = VERTEX.xz;

    // 1. Build rotation matrix 
    float c = cos(rotation_angle);
    float s = sin(rotation_angle);
    mat2 rot_mat = mat2(vec2(c, -s), vec2(s, c));
    
    // 2. Rotate UVs to point the arrows in the correct direction
    vec2 rotated_pos = rot_mat * pos;
    
    // 3. Scroll along the texture's native vertical axis.
    rotated_pos.y -= scroll_speed * TIME;
    
    final_uv = rotated_pos * texture_scale;
}

void fragment() {
    ALBEDO = texture(albedo_texture, final_uv).rgb;
}