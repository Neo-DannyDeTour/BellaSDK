#[compute]
#version 460

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Read from the heavy 1024x1024 map
layout(rgba16f, set = 0, binding = 0) restrict readonly uniform image2DArray high_res_map;
// Write to the lightweight 128x128 map
layout(rgba16f, set = 0, binding = 1) restrict writeonly uniform image2DArray low_res_map;

layout(push_constant) restrict readonly uniform PushConstants {
    uint cascade_index;
    float ratio; // The scale difference (e.g., 1024 / 128 = 8.0)
};

void main() {
    ivec2 low_res_id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dims = imageSize(low_res_map).xy;

    if (low_res_id.x >= dims.x || low_res_id.y >= dims.y) return;

    // Figure out which high-res pixel this low-res pixel corresponds to
    ivec2 high_res_id = ivec2(vec2(low_res_id) * ratio);

    // Grab the wave height and store it in the tiny map
    vec4 height_data = imageLoad(high_res_map, ivec3(high_res_id, cascade_index));
    imageStore(low_res_map, ivec3(low_res_id, cascade_index), height_data);
}
