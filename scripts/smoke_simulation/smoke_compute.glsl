#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
layout(rgba8, binding = 0) uniform restrict image3D smoke_grid;

// Match the change from intensity to age
struct Hole {
    vec3 start;
    float radius;
    vec3 end;
    float age; // Changed from intensity to animate swirl fade
};

layout(set = 0, binding = 1, std430) restrict readonly buffer HoleBuffer {
    Hole holes[];
};

// REPACKED Push Constants matching updated Godot code
layout(push_constant, std430) uniform Params {
    vec3 player_pos;
    float num_holes;
    
    vec3 grid_pos;
    float delta_time;
    
    vec3 grid_size; 
    float time;         
    
    // Matched new packing logic from GDScript
    float hole_clear_intensity; // (0.0 to 1.0)
    float swirl_strength;
    float swirl_frequency; // (Noise complexity)
    float player_radius;
    
    float z_offset;
    float heal_rate;
    float pad1; // Preserve 16-float (64-byte) alignment
    float pad2;
} params;

// --- UTILITIES ---
// distToSegment calculates closest point on segment, vector to that point, and distance
struct SegmentHit {
    float dist;
    vec3 closestPoint;
    vec3 radialVector; // Vector from world_pos to closestPoint
};

SegmentHit dist_to_segment_detailed(vec3 p, vec3 a, vec3 b) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    vec3 closest = a + ba * h;
    SegmentHit hit;
    hit.closestPoint = closest;
    hit.radialVector = p - closest;
    hit.dist = length(hit.radialVector);
    return hit;
}

// --- FAST NOISE FUNCTIONS (Keep these identical) ---
float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
                   mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
                   mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

// --- FBM: Layers of detail (Keep this identical) ---
float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 3; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// --- NEW NOISE FOR CINEMATICS (High-Frequency Turbulence) ---
float turbulent_noise(vec3 p) {
    // Sharp noise that folds over itself (abs), looks like wisps
    float n = noise(p);
    return abs(2.0 * n - 1.0); 
}

void main() {
    ivec3 voxel_pos = ivec3(
        gl_GlobalInvocationID.x, 
        gl_GlobalInvocationID.y, 
        gl_GlobalInvocationID.z + int(params.z_offset)
    );
    
    // (Previous resolution fix math)
    vec3 voxel_size = params.grid_size / 128.0; 
    vec3 world_pos = params.grid_pos + (vec3(voxel_pos) * voxel_size);
    
    vec4 current_data = imageLoad(smoke_grid, voxel_pos);
    float density = current_data.r;
    
    // --- (The Magic) Main Smoke Billowing (Keep identical) ---
    vec3 flow = vec3(params.time * 0.15, params.time * 0.25, params.time * 0.1);
    vec3 warp_coords = world_pos * 0.3; 
    vec3 distortion = vec3(fbm(warp_coords + flow), fbm(warp_coords - flow), fbm(warp_coords + vec3(flow.y, -flow.z, flow.x)));
    float billow = fbm((world_pos * 0.5) + (distortion * 2.0));
    float target_density = smoothstep(0.3, 0.75, billow); 
    density = min(density + (params.heal_rate * params.delta_time), target_density);
    
    // Player Interaction (Keep identical)
    float player_dist = distance(world_pos, params.player_pos);
    if (player_dist < params.player_radius) {
        float clear_amount = 1.0 - smoothstep(params.player_radius * 0.3, params.player_radius, player_dist); 
        density -= clear_amount;
    }
    
    // Bullet Interaction
    // Bullet Interaction
    int hole_count = int(params.num_holes);
    for (int i = 0; i < hole_count; i++) {
        float hole_normalized_age = holes[i].age * params.heal_rate;
        if (hole_normalized_age > 1.0) continue; 
        
        float base_radius = holes[i].radius;
        float dynamic_radius = base_radius * (1.0 + hole_normalized_age * 0.5); 
        
        // --- NEW OPTIMIZATION: AABB BOUNDING BOX CULLING ---
        // We multiply by 2.5 because your swirl_mask extends to base_radius * 2.5
        float max_effect_distance = dynamic_radius * 2.5; 
        
        vec3 min_bound = min(holes[i].start, holes[i].end) - vec3(max_effect_distance);
        vec3 max_bound = max(holes[i].start, holes[i].end) + vec3(max_effect_distance);
        
        // Fast cull: If the voxel is outside this 3D box, skip to the next hole immediately
        if (any(lessThan(world_pos, min_bound)) || any(greaterThan(world_pos, max_bound))) {
            continue;
        }
        // ---------------------------------------------------

        // Only voxels close to the line will ever reach this expensive math
        SegmentHit hit = dist_to_segment_detailed(world_pos, holes[i].start, holes[i].end);
        
        if (hit.dist < dynamic_radius * 2.0) { 
        // Check radius * 2 for swirl mask coverage
            
            // 1. MASKING (The key to kinematics)
            // Mask 1: The core hole (Where density is subtracted)
            float clear_mask = 1.0 - smoothstep(0.0, dynamic_radius, hit.dist);
            
            // Mask 2: The Swirl Ring (Just outside the core hole, fading outwards)
            // It fades over time quicker than the hole does.
            float swirl_fade_over_time = smoothstep(1.0, 0.0, hole_normalized_age);
            float swirl_mask = smoothstep(base_radius * 0.5, base_radius, hit.dist) * (1.0 - smoothstep(base_radius, base_radius * 2.5, hit.dist));
            swirl_mask *= swirl_fade_over_time; // Fade swirl mask over time
            
            // 2. THE CINEMATIC SWIRL (Rotational Turbulence)
            // We need a direction to twist. We use the vector perpendicular to the pellet path
            // and the radial vector of the voxel.
            vec3 pellet_dir = normalize(holes[i].end - holes[i].start);
            // RotAxis is the direction of tangent swirl around the path
            vec3 rotAxis = normalize(cross(pellet_dir, hit.radialVector)); 
            
            // Create turbulent noise keyed on world_pos
            vec3 turbulent_coords = (world_pos * params.swirl_frequency) + (distortion * 0.5);
            // OFFSET the noise sampling using the RotAxis. This creates the "swirl."
            // We increase the rotational offset based on how fresh the shot is (swirl_fade_over_time).
            turbulent_coords += rotAxis * (params.swirl_strength * swirl_fade_over_time);
            
            float turbulence = turbulent_noise(turbulent_coords);
            
            // 3. APPLY EFFECTS
            // Subtract core density (using editor global intensity)
            // The hole also fades over time (healing towards target_density happens naturally above,
            // so we don't multiply clear_mask by age here unless we want it to vanish instantly)
            density -= (clear_mask * params.hole_clear_intensity);
            
            // Add turbulent density within the swirl mask, scaled by the editor intensity.
            // We use standard 'noise' here for wispy adding rather than the sharp 'turbulent_noise'
            density += (turbulence * swirl_mask * params.swirl_strength);
        }
    }
    
    density = clamp(density, 0.0, 1.0);
    imageStore(smoke_grid, voxel_pos, vec4(density, 0.0, 0.0, 1.0));
}

