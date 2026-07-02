shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex;
uniform float distortion_strength = 0.03;
uniform float distortion_speed = 0.2;

void fragment() {
    // Pan the noise texture over time
    vec2 noise_uv = UV + vec2(TIME * distortion_speed, TIME * distortion_speed * 0.8);
    vec2 distortion = texture(noise_tex, noise_uv).rg;
    
    // Center the distortion mapping
    distortion = (distortion - 0.5) * 2.0 * distortion_strength;
    
    // Read the screen behind the object and apply the warped UVs
    ALBEDO = texture(SCREEN_TEXTURE, SCREEN_UV + distortion).rgb;
}