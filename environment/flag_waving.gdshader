shader_type spatial;

uniform sampler2D flag_texture : source_color, filter_linear_mipmap;
uniform sampler2D wind_noise : repeat_enable; // Assign a FastNoiseLite texture here

// Structure Ripples (Left-Right flapping)
uniform float wave_speed : hint_range(0.0, 10.0, 0.01) = 2.5;
uniform float wave_amplitude : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float wave_frequency : hint_range(0.1, 10.0, 0.01) = 3.0;
uniform float wave_phases : hint_range(1.0, 8.0, 0.01) = 2.0;

// 3D Wind Push (Front-Back chaotic fluttering)
uniform vec3 wind_direction = vec3(0.0, 0.0, 1.0);
uniform float wind_intensity : hint_range(0.0, 5.0, 0.01) = 1.0;
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.2;

uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.6;


void vertex() {
	// Mask to keep the flag attached to the pole (X=0)
	float edge_factor = UV.x;
	
	// 1. Structure Ripples (Sine waves)
	float wave1 = sin(UV.x * wave_frequency * TAU - TIME * wave_speed);
	float wave2 = sin(UV.x * wave_frequency * wave_phases * TAU - TIME * wave_speed * 1.3 + UV.y * 2.0) * 0.4;
	
	float z_ripple = (wave1 + wave2) * wave_amplitude * edge_factor;
	float y_ripple = wave1 * wave_amplitude * 0.2 * edge_factor;
	
	// 2. 3D Wind Push & Noise
	// Convert global wind direction to local space so it affects the mesh correctly regardless of rotation
	mat3 inv_model = inverse(mat3(MODEL_MATRIX));
	vec3 local_wind = normalize(inv_model * wind_direction);
	
	// Add an offset based on world position so multiple flags don't flap identically
	float position_sum = NODE_POSITION_WORLD.x + NODE_POSITION_WORLD.y + NODE_POSITION_WORLD.z;
	float wind_object_offset = position_sum * 0.1;
	
	// Scroll the UVs for the noise texture to simulate passing wind
	vec2 noise_uv = UV;
	noise_uv.x -= (TIME * wave_speed * 0.1) + wind_object_offset; 
	
	// Sample noise, remap from [0, 1] to [-1, 1] so it pushes and pulls chaotically
	float n_val = texture(wind_noise, noise_uv).r;
	n_val = (n_val * 2.0) - 1.0;
	
	// 3. Apply transformations
	// Apply the structured sine ripples
	VERTEX.z += z_ripple;
	VERTEX.y += y_ripple;
	
	// Apply chaotic flutter strictly along the wind vector
	VERTEX += local_wind * n_val * noise_strength * wind_intensity * edge_factor;
	
	// Push the entire fabric away from the wind source
	VERTEX += local_wind * wind_intensity * edge_factor * 0.3;
}


void fragment() {
	vec4 color = texture(flag_texture, UV);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ROUGHNESS = roughness;
}