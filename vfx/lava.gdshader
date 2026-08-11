shader_type canvas_item;

// ## The screen or ColorRect resolution used to maintain the correct aspect ratio.
uniform vec2 resolution = vec2(1920.0, 1080.0);

// ## The overall scale of the lava texture viewing distance.
uniform float zoom: hint_range(0.01, 40.0, 0.01) = 4.0;

// ## The playback speed of the lava flow animation.
uniform float speed: hint_range(0.0, 4.0, 0.01) = 0.6;

// ## The primary distortion factor that shapes the fractal structure.
uniform float warp_primary: hint_range(0.0, 4.0, 0.01) = 0.2;

// ## The secondary distortion factor that creates swirling ripples.
uniform float warp_secondary: hint_range(0.0, 4.0, 0.01) = 0.3;

// ## The overall brightness multiplier applied across noise iterations.
uniform float brightness: hint_range(0.0, 1.0, 0.01) = 0.5;

// ## Controls the sharpness and frequency scaling of the plasma noise.
uniform float sharpness: hint_range(1.0, 4.0, 0.01) = 2.0;

// ## The exponent applied to the heat value, affecting deep dark spots.
uniform float contrast: hint_range(0.1, 4.0, 0.01) = 1.3;

// ## The intensity multiplier that makes the hot lava areas glow (useful for HDR).
uniform float emission: hint_range(0.0, 10.0, 0.01) = 1.5;

// ## The primary color of the hottest lava areas.
uniform vec3 color_core: source_color = vec3(1.2, 0.0, 0.0);

// ## The secondary boundary color for the cooler, darker edges.
uniform vec3 color_edge: source_color = vec3(0.9, 0.7, 0.3);

// ## The number of fractal iterations (loops) used for lava generation.
const int OCTAVES = 5;

// ## The unit cube vertices utilized for trilinear noise interpolation.
const vec3 CUBE[8] = vec3[8](
	vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0),
	vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 1.0), vec3(1.0, 1.0, 1.0)
);

// PCG (Permuted Congruential Generator) 4D algorithm
uvec4 pcg4d(uvec4 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.w;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v.w += v.y * v.z;
	v ^= v >> 16u;
	v.x += v.y * v.w;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v.w += v.y * v.z;
	return v;
}

vec4 hash43(vec3 p) {
	uvec4 v = uvec4(
		floatBitsToUint(p.x),
		floatBitsToUint(p.y),
		floatBitsToUint(p.z),
		floatBitsToUint(p.x + p.y + p.z)
	);
	v = pcg4d(v);
	return vec4(v) / 4294967295.0 * 2.0 - 1.0;
}

vec4 noise(vec3 x) {
	vec3 p = floor(x);
	vec3 fr = smoothstep(0.0, 1.0, fract(x));
	
	// Level 1: Blend pairs of corners along the x-axis
	vec4 l1c1 = mix(hash43(p + CUBE[0]), hash43(p + CUBE[2]), fr.x);
	vec4 l1c2 = mix(hash43(p + CUBE[1]), hash43(p + CUBE[3]), fr.x);
	vec4 l1c3 = mix(hash43(p + CUBE[4]), hash43(p + CUBE[6]), fr.x);
	vec4 l1c4 = mix(hash43(p + CUBE[5]), hash43(p + CUBE[7]), fr.x);
	
	// Level 2: Blend along the y-axis
	vec4 l2c1 = mix(l1c1, l1c2, fr.y);
	vec4 l2c2 = mix(l1c3, l1c4, fr.y);
	
	// Level 3: Blend along the z-axis
	return mix(l2c1, l2c2, fr.z);
}

vec4 decorrelated_noise(vec3 p) {
	return (noise(p) + noise(p + 120.5)) * 0.5;
}

vec4 fbm(vec3 p) {
	vec4 fractal = vec4(0.0);
	vec4 swizzle = vec4(0.0);
	float amplitude = 1.0;
	float warp = 0.0;
	
	for (int i = 0; i < OCTAVES; i++) {
		vec4 n = decorrelated_noise(p);
		fractal += abs(n) * amplitude;
		swizzle += n.zwxy * amplitude;
		amplitude *= brightness;
		warp += 1.0;
		p *= sharpness;
		p += n.xyz * warp_primary * warp;
		p += swizzle.xyz * warp_secondary;
		p.z += (fractal.w * 0.5 + 0.5) * 0.015;
	}
	
	return fractal;
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= resolution.x / resolution.y;
	uv *= zoom;
	float time = TIME * speed;
	
	vec4 result = fbm(vec3(uv, time));
	
	// Generate heat mask based on swizzled dot product
	float heat = dot(result.xyzw, result.yxwx) * 0.5;
	heat = pow(max(heat, 0.0), contrast);
	heat = smoothstep(0.0, 1.0, heat);
	
	vec3 color = heat * mix(color_core, color_edge, heat) * emission;
	COLOR = vec4(color, 1.0);
}