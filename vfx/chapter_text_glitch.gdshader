shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.2;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;
    float time_snap = floor(TIME * 15.0);
    float block_y = floor(uv.y * 25.0);
    
    float alpha_env = 1.0;
    float glitch_chance = 0.0;
    
    if (progress < 0.15) {
        alpha_env = smoothstep(0.0, 0.15, progress);
        glitch_chance = 1.0; 
    } else if (progress > 0.85) {
        alpha_env = smoothstep(1.0, 0.85, progress);
        glitch_chance = 1.0; 
    } else {
        glitch_chance = step(0.95, rand(vec2(TIME, 0.0)));
    }

    float offset = (rand(vec2(block_y, time_snap)) - 0.5) * intensity * 0.5;
    float is_glitching = step(0.85, rand(vec2(block_y, time_snap + 1.0))) * glitch_chance;
    
    uv.x += offset * is_glitching;
    vec2 rgb_shift = vec2(0.01 * is_glitching, 0.0);
    
    vec4 tex_r = texture(TEXTURE, uv + rgb_shift);
    vec4 tex_g = texture(TEXTURE, uv);
    vec4 tex_b = texture(TEXTURE, uv - rgb_shift);
    
    // The SubViewport perfectly isolates the text colors and transparency.
    COLOR = vec4(tex_r.r, tex_g.g, tex_b.b, max(max(tex_r.a, tex_g.a), tex_b.a) * alpha_env);
}