#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

layout(set = 0, binding = 0, rgba8) uniform restrict image3D smoke_grid;

struct Hole {
    vec3 start;
    float radius;
    vec3 end;
    float age;
};

layout(set = 0, binding = 1, std430) restrict readonly buffer HoleBuffer {
    Hole holes[];
};

layout(set = 0, binding = 2) uniform sampler3D noise_texture;

layout(push_constant, std430) uniform Params {
    vec3 player_pos;
    float num_holes;
    
    vec3 grid_pos;
    float delta_time;
    
    vec3 grid_size; 
    float time;         
    
    float hole_clear_intensity;
    float swirl_strength;
    float swirl_frequency;
    float player_radius;
    
    float z_offset;
    float heal_rate;
    float pad1; 
    float pad2;
} params;

// --- UTILITIES ---
struct SegmentHit {
    float dist;
    vec3 closestPoint;
    vec3 radialVector; 
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

void main() {
    ivec3 voxel_pos = ivec3(
        gl_GlobalInvocationID.x, 
        gl_GlobalInvocationID.y, 
        gl_GlobalInvocationID.z + int(params.z_offset)
    );
    
    vec3 voxel_size = params.grid_size / 128.0; 
    vec3 world_pos = params.grid_pos + (vec3(voxel_pos) * voxel_size);
    
    vec4 current_data = imageLoad(smoke_grid, voxel_pos);
    float density = current_data.r;
    
    vec3 flow = vec3(params.time * 0.15, params.time * 0.25, params.time * 0.1);
    vec3 warp_coords = world_pos * 0.05; 
    
    vec3 distortion = vec3(
        textureLod(noise_texture, warp_coords + flow, 0.0).r,
        textureLod(noise_texture, warp_coords - flow, 0.0).r,
        textureLod(noise_texture, warp_coords + vec3(flow.y, -flow.z, flow.x), 0.0).r
    );
    
    float billow = textureLod(
        noise_texture, (warp_coords) + (distortion * 0.5), 0.0
    ).r;
    
    float target_density = smoothstep(0.2, 0.55, billow); 
    density = min(
        density + (params.heal_rate * params.delta_time), 
        target_density
    );
    
    // --- Player Interaction ---
    float player_dist = distance(world_pos, params.player_pos);
    if (player_dist < params.player_radius) {
        float clear_amount = 1.0 - smoothstep(
            params.player_radius * 0.4, 
            params.player_radius, 
            player_dist
        ); 
        density -= clear_amount;
    }
    
    // --- Bullet Interaction ---
    int hole_count = int(params.num_holes);
    for (int i = 0; i < hole_count; i++) {
        float age = holes[i].age;
        if (age > 1.0) continue; 
        
        float base_radius = holes[i].radius;
        float dynamic_radius = base_radius * (1.0 + age * 0.1); 
        float max_effect = dynamic_radius * 2.5; 
        
        // Fast AABB early-exit to maintain 60 FPS
        vec3 min_bound = min(holes[i].start, holes[i].end) - vec3(max_effect);
        vec3 max_bound = max(holes[i].start, holes[i].end) + vec3(max_effect);
        
        if (any(lessThan(world_pos, min_bound)) || any(greaterThan(world_pos, max_bound))) {
            continue;
        }

        SegmentHit hit = dist_to_segment_detailed(
            world_pos, holes[i].start, holes[i].end
        );
        
        if (hit.dist < max_effect) { 
            float fade = 1.0 - age;
            
            // Sharp core clearing
            float core_radius = dynamic_radius * 0.4;
            float clear_mask = 1.0 - smoothstep(core_radius * 0.3, core_radius, hit.dist);
            
            // Pronounced swirl rim
            float rim_mask = smoothstep(core_radius * 0.8, dynamic_radius * 1.5, hit.dist) 
                           * (1.0 - smoothstep(dynamic_radius * 1.5, max_effect, hit.dist));
            
            vec3 pellet_dir = normalize(holes[i].end - holes[i].start);
            vec3 rotAxis = normalize(cross(pellet_dir, hit.radialVector)); 
            
            // Swirl calculation
            vec3 turb_coords = (world_pos * params.swirl_frequency) + (distortion * 0.5);
            turb_coords += rotAxis * (params.swirl_strength * fade * 2.0);
            
            float raw_noise = textureLod(noise_texture, turb_coords, 0.0).r;
            float swirl_addition = raw_noise * params.swirl_strength * rim_mask * fade;
            
            // Apply modifications
            density -= (clear_mask * params.hole_clear_intensity * fade);
            density += swirl_addition;
        }
    }
    
    density = clamp(density, 0.0, 1.0);
    imageStore(smoke_grid, voxel_pos, vec4(density, 0.0, 0.0, 1.0));
}
