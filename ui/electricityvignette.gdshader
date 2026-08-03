shader_type canvas_item;

uniform vec4 lightning_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

float rand(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    vec2 uv = UV;
    
    // Calculate distance from center to create the vignette mask
    float dist = distance(uv, vec2(0.5));
    float vignette = smoothstep(0.4, 0.7, dist);
    
    // Generate high-speed noise for the electricity jitter
    float noise = rand(uv * floor(TIME * 20.0));
    
    // Mask the noise to the edges and scale by the tweend intensity
    float edge_electricity = vignette * noise * intensity;
    
    COLOR = lightning_color;
    COLOR.a = edge_electricity;
}