#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

layout(rgba8, binding = 0) uniform restrict image3D smoke_grid;

struct Hole {
    vec3 start;
    float radius;
    vec3 end;
    float intensity;
};

layout(set = 0, binding = 1, std430) restrict readonly buffer HoleBuffer {
    Hole holes[];
};

// Our perfectly aligned 48-byte struct
layout(push_constant, std430) uniform Params {
    vec3 player_pos;
    float num_holes;
    vec3 grid_pos;       // <--- Using grid_pos
    float grid_size;     // <--- Using grid_size
    float delta_time;
    float pad1;
    float pad2;
    float pad3;
} params;

float dist_to_segment(vec3 p, vec3 a, vec3 b) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void main() {
    ivec3 voxel_pos = ivec3(gl_GlobalInvocationID.xyz);
    
    // MATCHED NAMES HERE: grid_size and grid_pos
    float voxel_size = params.grid_size / 64.0;
    vec3 world_pos = params.grid_pos + (vec3(voxel_pos) * voxel_size);
    
    vec4 current_data = imageLoad(smoke_grid, voxel_pos);
    float density = current_data.r;
    
    // Heal smoke
    density = min(density + (params.delta_time * 0.5), 1.0);
    
    // Player Interaction
    float player_dist = distance(world_pos, params.player_pos);
    if (player_dist < 2.5) {
        float clear_amount = 1.0 - smoothstep(1.0, 2.5, player_dist); 
        density -= clear_amount;
    }
    
    // Bullet Interaction
    int hole_count = int(params.num_holes);
    for (int i = 0; i < hole_count; i++) {
        float dist = dist_to_segment(world_pos, holes[i].start, holes[i].end);
        if (dist < holes[i].radius) {
            float clear_amount = 1.0 - smoothstep(0.0, holes[i].radius, dist);
            density -= (clear_amount * holes[i].intensity);
        }
    }
    
    density = clamp(density, 0.0, 1.0);
    imageStore(smoke_grid, voxel_pos, vec4(density, 0.0, 0.0, 1.0));
}
