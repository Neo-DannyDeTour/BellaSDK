shader_type spatial;
// Force this to draw on top of everything, unshaded, and ignore 3D clipping
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec2 mouse_uv = vec2(0.5, 0.5);
uniform vec2 focus_uv = vec2(0.5, 0.5);
uniform float glass_radius_uv = 0.2; 
uniform float aspect_ratio = 1.777;
uniform float edge_softness = 0.005;
uniform float zoom = 2.0; 

// Counteracts the 3D physical scaling to prevent edge clipping
uniform float mesh_scale = 5.0; 

uniform vec4 border_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float border_thickness = 0.008;
uniform vec4 background_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);

void fragment() {
    // 1. Re-map the UVs to account for the physically scaled-up 3D mesh
    vec2 base_uv = (UV - 0.5) * mesh_scale + 0.5;

    // 2. Calculate zoomed UVs relative to the exact raycast hit point
    vec2 zoomed_uv = (base_uv - focus_uv) / zoom + focus_uv;
    
    // Check if zoomed_uv is wandering off the physical edges of the comic
    float bounds_mask = step(0.0, zoomed_uv.x) * step(zoomed_uv.x, 1.0) *
                        step(0.0, zoomed_uv.y) * step(zoomed_uv.y, 1.0);
                        
    vec4 tex_color = texture(albedo_tex, zoomed_uv);
    vec3 final_tex = mix(background_color.rgb, tex_color.rgb, bounds_mask);
    
    // 3. Use the screen coordinates to create the circular mask
    vec2 aspect_screen_uv = SCREEN_UV;
    aspect_screen_uv.x *= aspect_ratio;
    
    vec2 aspect_mouse = mouse_uv;
    aspect_mouse.x *= aspect_ratio;
    
    float dist = distance(aspect_screen_uv, aspect_mouse);
    
    // 4. Calculate perfectly anti-aliased mask edges
    float alpha_mask = 1.0 - smoothstep(glass_radius_uv - edge_softness, glass_radius_uv, dist);
    float border_mask = smoothstep(
        glass_radius_uv - border_thickness - edge_softness, 
        glass_radius_uv - border_thickness, 
        dist
    );
    
    // 5. Mix texture with border, apply alpha to hide everything outside the circle
    vec3 final_color = mix(final_tex, border_color.rgb, border_mask);
    
    ALBEDO = final_color;
    ALPHA = alpha_mask;
}