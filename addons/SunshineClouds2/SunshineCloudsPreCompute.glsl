#[compute]
#version 450

#include "./CloudsInc.comp"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(binding = 0) uniform sampler2D depth_image;
layout(r32f, binding = 1) uniform restrict writeonly image2D output_depth_image;

layout(binding = 2, std140) uniform uniformBuffer {
    GenericData data;
} genericData;

void main() {
    ivec2 base_uv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 lowres_size = ivec2(genericData.data.raster_size);

    if (base_uv.x >= lowres_size.x || base_uv.y >= lowres_size.y) {
        return;
    }

    int resolutionScale = max(int(genericData.data.resolutionscale), 1);
    ivec2 highres_size = lowres_size * resolutionScale;
    ivec2 start_coord = base_uv * resolutionScale;

    // In Godot Reversed-Z: 1.0 is near plane, 0.0 is infinite far sky.
    // For conservative raymarching occlusion, we track the nearest depth (maximum value in Reversed-Z)
    float max_depth = 0.0;

    for (int y = 0; y < resolutionScale; y++) {
        for (int x = 0; x < resolutionScale; x++) {
            ivec2 sample_coord = clamp(start_coord + ivec2(x, y), ivec2(0), highres_size - ivec2(1));
            vec2 sample_uv = (vec2(sample_coord) + 0.5) / vec2(highres_size);
            float d = texture(depth_image, sample_uv).r;
            max_depth = max(max_depth, d);
        }
    }

    imageStore(output_depth_image, base_uv, vec4(max_depth, 0.0, 0.0, 0.0));
}
