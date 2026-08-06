shader_type canvas_item;

// Switched to filter_linear to prevent nearest-neighbor fallback on the screen texture
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 mouse_uv = vec2(0.5, 0.5);
uniform float glass_radius_uv = 0.15;
uniform float zoom = 2.0;
uniform float aspect_ratio = 1.777; 

// Added controls for the border and anti-aliasing softness
uniform float border_thickness = 0.005;
uniform float edge_softness = 0.002;

void fragment() {
    // Correct for screen stretching so our magnifying glass remains a perfect circle
    vec2 aspect_uv = UV;
    aspect_uv.x *= aspect_ratio;
    
    vec2 aspect_mouse = mouse_uv;
    aspect_mouse.x *= aspect_ratio;
    
    float dist = distance(aspect_uv, aspect_mouse);
    
    // Calculate the offset from the mouse and scale it down to zoom in
    vec2 offset = (UV - mouse_uv) / zoom;
    vec4 zoomed_color = texture(screen_tex, mouse_uv + offset);
    
    vec4 border_color = vec4(0.8, 0.8, 0.8, 1.0);
    vec4 transparent = vec4(0.0, 0.0, 0.0, 0.0);
    
    // Anti-alias the outer edge of the magnifying glass
    float alpha_mask = 1.0 - smoothstep(glass_radius_uv - edge_softness, glass_radius_uv, dist);
    
    // Anti-alias the inner border of the magnifying glass
    float border_mask = smoothstep(
        glass_radius_uv - border_thickness - edge_softness, 
        glass_radius_uv - border_thickness, 
        dist
    );
    
    // Mix the zoomed texture with the border color based on the border mask
    vec4 final_color = mix(zoomed_color, border_color, border_mask);
    
    // Apply the overall alpha mask to make everything outside the circle transparent
    COLOR = mix(transparent, final_color, alpha_mask);
}