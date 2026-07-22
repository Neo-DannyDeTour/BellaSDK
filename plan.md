1. **Remove `SceneData` Struct Definitions**: Remove `struct SceneData` entirely from `addons/SunshineClouds2/CloudsInc.comp`.
2. **Add `z_far` to `GenericData`**: Add `float z_far;` to `struct GenericData` in `addons/SunshineClouds2/CloudsInc.comp` and ensure it's padded correctly (wait, we can just append it. To maintain alignment, let's append it to `CloudsInc.comp`).
3. **Remove `SceneDataBlock` Uniforms**: Remove the `SceneDataBlock` uniform declaration from `addons/SunshineClouds2/SunshineCloudsCompute.glsl` and `addons/SunshineClouds2/SunshineCloudsPostCompute.comp`.
4. **Update Post Compute Shader**: In `addons/SunshineClouds2/SunshineCloudsPostCompute.comp`, replace `scene_data_block.data.inv_projection_matrix` with `genericData.data.cam_inv_projection` and `scene_data_block.data.z_far` with `genericData.data.z_far`. Also remove the early return block checking `scene_data_block.data.flags & SCENE_DATA_FLAGS_IN_SHADOW_PASS` since we will handle it in GDScript.
5. **Update GDScript Uniform Generation**: In `addons/SunshineClouds2/SunshineClouds.gd`:
   - Find where `camera_data` buffer is added to uniform sets (`camera_data_uniform` binding 17, and `postpass_camera_data_uniform` binding 8) and remove them.
   - We must also update the float indexing in `update_matrices()` since we are adding a float to `GenericData`. Wait, `genericData` sizes! Let's check `float_data.resize(192)` and see where we can pack `z_far`. We can add `z_far` at the end or replace a unused float or add it and increase resize.
   - Implement early return in `_render_callback` if not the main view or is a shadow/directional pass. Wait, we can check `render_data.get_camera_attributes()` or `render_scene_data` to make sure we don't render on shadow passes.
6. **Complete pre-commit steps**: Run linting/formatting tests via `pre_commit_instructions`.
7. **Submit the PR**: Commit the changes with the appropriate message.
