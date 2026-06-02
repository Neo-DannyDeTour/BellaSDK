shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float char_size : hint_range(4.0, 16.0, 1.0) = 8.0;

// We encode a 3x5 pixel art font into 15-bit integers.
// Ordered from darkest to brightest to match screen luminance.
const int ascii_chars[8] = int[8](
    0,      // " " (Space)
    8192,   // "." (Dot at the bottom)
    1040,   // ":" (Two vertical dots)
    1488,   // "+" (Plus symbol)
    20613,  // "x" (Cross)
    23533,  // "H" (Vertical lines + center horizontal)
    31727,  // "8" (Dense blocky 8)
    32767   // Solid Block
);

void fragment() {
    vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
    
    // Snap UVs to the character grid
    vec2 grid_uv = floor(SCREEN_UV * res / char_size) * char_size / res;
    vec2 local_uv = fract(SCREEN_UV * res / char_size);

    // Sample screen color at the center of this specific character block
    vec3 color = texture(screen_texture, grid_uv + (char_size * 0.5 * SCREEN_PIXEL_SIZE)).rgb;
    
    // Calculate true grayscale luminance
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    
    // Map luminance (0.0 to 1.0) to our character array (0 to 7)
    int char_index = int(clamp(luma * 8.0, 0.0, 7.0));
    int char_int = ascii_chars[char_index];

    // Add a 10% margin so characters don't touch each other
    float margin_mask = step(0.1, local_uv.x) * step(local_uv.x, 0.9) * step(0.1, local_uv.y) * step(local_uv.y, 0.9);

    // Map the remaining local UV space into a 3x5 font grid
    int x = int(clamp((local_uv.x - 0.1) / 0.8 * 3.0, 0.0, 2.0));
    int y = int(clamp((local_uv.y - 0.1) / 0.8 * 5.0, 0.0, 4.0));

    // Calculate the bit index (0 to 14) for the 3x5 grid
    int bit_index = x + (y * 3);

    // Bitwise extraction: Shift the integer down by the index and check if the bit is 1 or 0
    int is_lit = (char_int >> bit_index) & 1;
    
    // Output pure black or white based on the bit and the margin mask
    float final_pixel = float(is_lit) * margin_mask;
    
    COLOR = vec4(vec3(final_pixel), 1.0);
}