shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
// How long the text stays still before the melt begins (0.4 = 40% of duration)
uniform float hold_ratio : hint_range(0.0, 1.0) = 0.4;
// Number of vertical strips per individual character
uniform float columns = 15.0; 
// How fast the columns fall once they start melting
uniform float melt_speed = 5.0; 

// Extremely cheap pseudo-random generation to stagger the columns
float rand(float x) {
    return fract(sin(x * 12.9898) * 43758.5453);
}

void fragment() {
    // Remap progress to only animate after the hold duration
    float melt_progress = max(0.0, (progress - hold_ratio) / (1.0 - hold_ratio));
    
    // Divide the character's UV space into discrete vertical columns
    float col_id = floor(UV.x * columns);
    
    // Give each column a randomized starting delay
    float delay = rand(col_id) * 0.3;
    
    // Calculate the drop amount, isolating the movement to the Y axis
    float drop = max(0.0, melt_progress - delay) * melt_speed;
    
    vec2 melted_uv = UV;
    melted_uv.y -= drop;
    
    // Godot groups fonts into texture atlases. 
    // To prevent melting into another letter on the atlas, we render the pixel
    // completely transparent if the UV drops outside the character's 0-1 bounds.
    if (melted_uv.y < 0.0 || melted_uv.y > 1.0) {
        COLOR = vec4(0.0);
    } else {
        COLOR = texture(TEXTURE, melted_uv) * COLOR;
    }
}