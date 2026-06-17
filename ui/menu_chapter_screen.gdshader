shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 5.0) = 2.0; // Uses Mipmap levels instead of pixels
uniform float pan_amount : hint_range(0.0, 0.1) = 0.05; 
uniform float pan_speed : hint_range(0.0, 5.0) = 1.0;  

void fragment() {
    // 1. Calculate a smooth back-and-forth wave
    float wave = sin(TIME * pan_speed);
    
    // 2. Zoom the UVs in slightly
    vec2 zoom_uv = (UV - 0.5) * 0.9 + 0.5; 
    
    // 3. Add the horizontal panning offset
    vec2 panned_uv = zoom_uv + vec2(wave * pan_amount, 0.0);

    // 4. Sample the texture using Level of Detail (LOD) for a free, smooth blur
    // Note: The texture MUST have "Generate Mipmaps" enabled in its import settings!
    COLOR = textureLod(TEXTURE, panned_uv, blur_amount);
}