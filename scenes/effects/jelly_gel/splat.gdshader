shader_type spatial;

// Uniform for the noise texture
uniform sampler2D noise_texture;
uniform vec3 color: source_color;

varying vec2 seed;

void vertex() {
    mat4 modified_model_view = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0],
        INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2],
        MODEL_MATRIX[3]
    );
    MODELVIEW_MATRIX = modified_model_view;
	seed = vec2(float(INSTANCE_ID), float(INSTANCE_ID * 2));
}

void fragment() {
   

    // Random offset based on the instance index
    vec2 random_offset = vec2(
        sin((TIME + seed.x)) ,
        cos((TIME + seed.y)) 
    );


    // Sample noise texture
    vec4 noise_color = texture(noise_texture, UV + random_offset);

  
    // Apply noise color to albedo with attenuation
    ALBEDO = color * pow(noise_color.r, 5);

    // Set alpha to 1.0 (fully opaque)
    ALPHA = clamp(noise_color.r - length(UV - vec2(0.5)) - 0.2, 0, 1) * 0.5;
}
