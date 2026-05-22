shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(0.1, 0.1, 0.1);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;

// Wind Uniforms
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.5);
uniform float wind_strength = 0.15;
uniform float wind_speed = 2.0;

// Interaction Uniforms
global uniform vec3 global_player_pos; // Receives the position from your player script
uniform float push_radius = 1.5; // How close the player has to be to move the cable
uniform float push_strength = 0.6; // How far the cable bends out of the way

void vertex() {
	float exact_t = COLOR.r;
	
	// Pin the cable tightly at the anchors (0.0 and 1.0)
	float pin_weight = sin(exact_t * PI);
	
	// --- 1. Calculate Ambient Wind ---
	float wind_wave = sin(TIME * wind_speed + exact_t * 5.0 + COLOR.b);
	vec3 local_offset = wind_direction * wind_wave * wind_strength * pin_weight;
	
	// --- 2. Calculate Player Interaction ---
	// Convert the local vertex position into the global world space
	vec3 global_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Find the distance and direction between the vertex and the player
	vec3 player_to_cable = global_vertex - global_player_pos;
	float dist_to_player = length(player_to_cable);
	
	if (dist_to_player < push_radius && dist_to_player > 0.001) {
		// Calculate how strong the push should be (stronger when closer)
		float push_factor = 1.0 - (dist_to_player / push_radius);
		// Smooth the curve so it doesn't snap aggressively
		push_factor = smoothstep(0.0, 1.0, push_factor);
		
		vec3 push_dir = normalize(player_to_cable);
		
		// Add a tiny sine wave "jiggle" so it looks like an elastic cable being bumped
		float jiggle = sin(TIME * 15.0) * 0.1 * push_factor;
		
		// Combine the push force and jiggle, factor in the pin_weight so anchors don't break
		vec3 global_push = push_dir * (push_strength * push_factor + jiggle) * pin_weight;
		
		// Convert the global push back into local space and add it to our offset
		local_offset += (inverse(MODEL_MATRIX) * vec4(global_push, 0.0)).xyz;
	}
	
	// Apply all movement to the actual vertex
	VERTEX += (inverse(MODEL_MATRIX) * vec4(local_offset, 0.0)).xyz;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness;
}