shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0);

float rand(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    float fade_in = smoothstep(0.0, 0.2, progress);
    
    // Shatter phase only triggers at the end of the duration (0.8 to 1.0)
    float shatter_phase = smoothstep(0.8, 1.0, progress);
    
    // Create a 25x25 fracture grid
    vec2 grid_uv = floor(UV * 25.0);
    float hash = rand(grid_uv);
    
    vec2 offset = vec2(0.0);
    if (shatter_phase > 0.0) {
        // Explode outward radially based on hash
        float angle = hash * 6.2831;
        vec2 dir = vec2(cos(angle), sin(angle));
        
        offset = dir * shatter_phase * 0.3;
        offset.y += pow(shatter_phase, 2.5) * 0.8; // Apply faux gravity downwards
    }
    
    // By subtracting the offset, we move the texture forward
    vec4 tex = texture(TEXTURE, UV - offset);
    
    // Fade out as the pieces fall
    float final_alpha = tex.a * fade_in * (1.0 - shatter_phase);
    
    COLOR = vec4(tex.rgb, final_alpha);
}