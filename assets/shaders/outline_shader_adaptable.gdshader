shader_type canvas_item;

// This grabs the rendered game world behind the UI
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
    // 1. Get the color of the screen exactly behind this pixel
    vec4 screen_color = texture(screen_texture, SCREEN_UV);
    
    // 2. Calculate how bright the background is (Standard Luminance formula)
    float brightness = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));
    
    // 3. Get the shape and transparency of your actual UI circle texture
    vec4 circle_texture = texture(TEXTURE, UV);
    
    // 4. If the background brightness is > 0.5 (light), make the circle black. 
    //    If it's < 0.5 (dark), make the circle white.
    vec3 final_color = mix(vec3(1.0), vec3(0.0), step(0.5, brightness));
    
    // 5. Output the color, but keep your circle's original transparency
    COLOR = vec4(final_color, circle_texture.a);
}
