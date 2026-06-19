shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Defines the timeline. 0.25 means it takes 25% of the total time to appear,
// holds until 75%, and uses the last 25% to melt away.
uniform float intro_ratio : hint_range(0.0, 1.0) = 0.25;
uniform float outro_ratio : hint_range(0.0, 1.0) = 0.75;

// Increased columns because this applies to the whole SubViewport width, not just a label.
uniform float columns = 80.0; 

// Controls how far the melt travels. 1.5 means it drops 1.5x the height of the Viewport.
uniform float melt_distance = 1.5; 

// Cheap pseudo-random generation to stagger the columns
float rand(float x) {
    return fract(sin(x * 12.9898) * 43758.5453);
}

void fragment() {
    float col_id = floor(UV.x * columns);
    float delay = rand(col_id) * 0.3; // Up to 30% stagger per column

    // --- PHASE 1: APPEAR (Un-melt) ---
    // progress mapped 0.0 -> intro_ratio
    float intro_prog = clamp(progress / intro_ratio, 0.0, 1.0);
    float appear_drop = clamp((intro_prog - delay) / (1.0 - delay), 0.0, 1.0);
    appear_drop = 1.0 - appear_drop; // Reverses it so it starts far away and settles to 0.0

    // --- PHASE 3: DISAPPEAR (Melt down) ---
    // progress mapped outro_ratio -> 1.0
    float outro_prog = clamp((progress - outro_ratio) / (1.0 - outro_ratio), 0.0, 1.0);
    float disappear_drop = clamp((outro_prog - delay) / (1.0 - delay), 0.0, 1.0);

    // Combine both phases. During Phase 2 (Hold), both equal 0.0.
    float drop = (appear_drop + disappear_drop) * melt_distance;

    vec2 melted_uv = UV;
    melted_uv.y -= drop;

    // Viewport bounds culling to prevent texture wrapping/atlas bleeding
    if (melted_uv.y < 0.0 || melted_uv.y > 1.0) {
        COLOR = vec4(0.0);
    } else {
        COLOR = texture(TEXTURE, melted_uv);
    }
}