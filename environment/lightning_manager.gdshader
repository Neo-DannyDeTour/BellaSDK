shader_type spatial;
render_mode shadows_disabled, unshaded, cull_disabled;

// --- UNIFORMS ---
uniform vec4 lightning_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.2, 0.5, 1.0, 1.0);

// High emission strength makes it "bloom" when Using WorldEnvironment Glow
uniform float emission_strength : hint_range(0.0, 20.0) = 5.0;

// How sharply the ends fade out (0.0 = no fade)
uniform float end_fade_sharpness : hint_range(0.0, 10.0) = 2.0;

// Internal Varying to pass length info
varying float length_t; 

void vertex() {
    // When drawing PRIMITIVE_LINES, Godot standardizes vertex order.
    // We can approximate the position along the line (0.0 to 1.0)
    // by comparing vertex ID, but it's not perfect for ImmediateMesh.
    // Standard unshaded shaders usually rely purely on vertex positioning done in GDScript.
    
    // Pass the vertex Y position relative to origin as a rough 'length' approximation
    // for fragment fading. (GDScript puts the arc/jitter in world space)
    length_t = VERTEX.y;
}

void fragment() {
    // Basic color
    vec3 base_rgb = lightning_color.rgb;
    
    // Add strong emission glow
    vec3 emission_rgb = glow_color.rgb * emission_strength;
    
    // Optional: Fade out near the ends of the segment
    // (This assumes the GDScript generally keeps the segments aligned)
    float fade = 1.0;
    if (end_fade_sharpness > 0.1) {
        // Simple approximation: fade if near "center" of local vertex space
        // You might need to adjust or remove this if your arcs are extremely chaotic
        // or if you feed UVs per vertex in GDScript.
        // fade = pow(sin(UV.y * PI), end_fade_sharpness); // Doesnt work on lines
    }
    
    ALBEDO = base_rgb;
    EMISSION = emission_rgb;
    ALPHA = lightning_color.a * fade;
}