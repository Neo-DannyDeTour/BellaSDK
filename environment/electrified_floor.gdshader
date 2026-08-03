shader_type spatial;
render_mode blend_add, shadows_disabled, cull_disabled;

uniform vec4 lightning_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float emission_energy = 3.0;

uniform float lightning_scale = 1.0; 
uniform float lightning_thickness = 0.02;
uniform float speed = 3.0;
uniform float jaggedness = 0.2;
uniform float strike_frequency : hint_range(0.0, 1.0) = 0.8;

// Basic hash for pseudo-randomness
float hash21(vec2 p) {
	p = fract(p * vec2(13.31, 4.31));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 2D Noise function
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Fractal Brownian Motion for jagged branching
float fbm(vec2 p) {
	float f = 0.0;
	float w = 0.5;
	for (int i = 0; i < 4; i++) {
		f += w * noise(p);
		p *= 2.0;
		w *= 0.5;
	}
	return f;
}

void fragment() {
	// Apply scaling to dictate how many arcs populate the surface
	vec2 uv = UV * lightning_scale;
	
	// Distort the UV coordinates to create a jagged path
	float distortion = fbm(uv + TIME * speed) * jaggedness;
	uv.y += distortion - (jaggedness * 0.5); 
	
	// Create a line passing through the center of the modified UVs
	float dist = abs(fract(uv.y) - 0.5);
	
	// Inverse distance creates a nice fading neon glow falloff
	float intensity = lightning_thickness / (dist + 0.001); 
	intensity = clamp(intensity, 0.0, 1.0);
	
	// Tile-based random blinking
	float tile_id = floor(uv.y); 
	float time_step = floor(TIME * speed * 2.0);
	
	// Determine if this specific arc is actively striking
	float strike = hash21(vec2(tile_id, time_step));
	float is_striking = step(1.0 - strike_frequency, strike);
	
	intensity *= is_striking;
	
	// Softly fade out the hard edges on the left and right bounds
	float edge_fade = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x);
	intensity *= edge_fade;
	
	ALBEDO = lightning_color.rgb * intensity;
	EMISSION = emission_color.rgb * intensity * emission_energy;
	ALPHA = intensity * lightning_color.a;
}