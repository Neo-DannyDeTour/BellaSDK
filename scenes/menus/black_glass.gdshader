shader_type canvas_item;

uniform float sweep_progress = -0.5; 
uniform float hover_intensity : hint_range(0.0, 1.0) = 0.0; 
uniform float angle : hint_range(0.0, 360.0) = 25.0;
uniform vec2 rect_size; 

uniform vec4 base_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); 
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 0.6);
uniform float shine_width : hint_range(0.01, 1.0) = 0.15; 
uniform vec4 rim_light_color : source_color = vec4(0.8, 0.9, 1.0, 0.25); 
uniform float slab_opacity : hint_range(0.0, 1.0) = 0.95; 

uniform sampler2D blood_texture : repeat_enable; 
uniform vec2 mouse_pos_uv; 
uniform float reveal_radius : hint_range(0.0, 3.0) = 0.15; 
uniform float reveal_softness : hint_range(0.0, 1.0) = 0.1; 
uniform vec2 blood_offset = vec2(0.0, 0.0); 

void fragment() {
    // --- 1. BASE MATERIAL ---
    float bevel = (1.0 - UV.y) * 0.01 + (1.0 - UV.x) * 0.01;
    vec3 solid_black_result = base_color.rgb + vec3(bevel);

    // --- 2. MATH FOR THE SHINES ---
    float rad = radians(angle);
    vec2 dir = vec2(cos(rad), sin(rad));
    
    // The Initial Quick Sweep (Runs once on hover)
    float dist = abs(dot(UV, dir) - sweep_progress);
    float entrance_shine = smoothstep(shine_width, 0.0, dist);

    // --- 3. THE PERSISTENT GLOSSY GLARE (New) ---
    // Center the mouse coordinates so (0,0) is the middle of the button
    vec2 centered_mouse = clamp(mouse_pos_uv - vec2(0.5), -0.5, 0.5);
    
    // Project the mouse position onto our shine angle to calculate where the light hits
    float glare_pos = 0.5 - (centered_mouse.x * cos(rad) + centered_mouse.y * sin(rad)) * 0.8; 
    
    // Draw a soft, wide beam of light that tracks the mouse. 
    // It's wider (0.4) and softer (0.25 opacity) than the initial sharp sweep.
    float persistent_glare = smoothstep(0.4, 0.0, abs(dot(UV, dir) - glare_pos)) * 0.25 * hover_intensity;

    // Combine both shines
    float total_shine = clamp((entrance_shine * hover_intensity) + persistent_glare, 0.0, 1.0);
    solid_black_result = mix(solid_black_result, shine_color.rgb, total_shine * shine_color.a);

    // --- 4. ANTI-ALIASING FOR ROTATION ---
    vec2 px_coords = UV * rect_size;
    float dist_x = min(px_coords.x, rect_size.x - px_coords.x);
    float dist_y = min(px_coords.y, rect_size.y - px_coords.y);
    float outer_mask = smoothstep(0.0, 1.0, min(dist_x, dist_y));

    // --- 5. THE BLOOD REVEAL MASK ---
    float aspect = rect_size.x / rect_size.y;
    vec2 aspect_uv = UV;
    aspect_uv.x *= aspect;
    vec2 aspect_mouse = mouse_pos_uv;
    aspect_mouse.x *= aspect;
    
    float d = distance(aspect_uv, aspect_mouse);
    float reveal_mask = smoothstep(reveal_radius, reveal_radius - reveal_softness, d) * hover_intensity;
    
    vec4 blood_col = texture(blood_texture, UV + blood_offset);
    vec3 facade_result = mix(solid_black_result, blood_col.rgb, reveal_mask);

    // --- 6. MOONLIGHT RIM EDGE ---
    float rim_thickness = 1.5;
    float rim_mask = clamp((1.0 - step(rim_thickness, px_coords.y)) + (1.0 - step(rim_thickness, px_coords.x)), 0.0, 1.0);
    facade_result = mix(facade_result, rim_light_color.rgb, rim_mask * rim_light_color.a);

    // --- FINAL OUT ---
    COLOR = vec4(facade_result, base_color.a * slab_opacity * outer_mask);
}