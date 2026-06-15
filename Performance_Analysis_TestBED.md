# Performance Analysis: TestBED Scene

## The Core Bottleneck
The primary cause of the severe frame drops (over 21ms CPU render time) in the `TestBED` scene is the rendering overhead from the `SubViewport` nodes, specifically the mirror implementation located at `InteractiveObjects/Mirror/SubViewport` in `shared/testbed.tscn`, as well as multiple other active viewports (`rain_viewport.tscn`, `tv_screen_scene.tscn`, `danny_cast_screen.tscn`).

The `InteractiveObjects/Mirror/SubViewport` does **not** have a `render_target_update_mode` specified in the `.tscn` file. This means it defaults to `UPDATE_ALWAYS` (value 2). Furthermore, it runs at a high resolution (`size = Vector2i(1280, 720)`). This forces Godot to re-render the entire scene into this viewport on *every single frame*, regardless of whether the mirror is actually visible or on-screen.

There is also a script (`interactables/mirror.gd`) that exists in the project which *would* implement distance-based culling and interleaved updates to optimize a mirror, but this script is **not attached** to the mirror node in the `TestBED` scene. The mirror in `TestBED` is just a raw `CSGBox3D` with a raw `SubViewport` and `Camera3D` child.

Additionally, other viewports like `rain_viewport.tscn` are rendering a 2048x2048 texture on `UPDATE_ALWAYS` (mode 4 for SubViewport in Godot 4 context).

## The "Why"
When a `SubViewport` has its update mode set to "Always", Godot executes a full render pass for that viewport on every frame.
1. **The Mirror**: Because the mirror in the `TestBED` scene is missing the optimization script and defaults to `UPDATE_ALWAYS`, a 1280x720 render pass is happening constantly. Even if the player is looking at the ground or is far away, the CPU render thread must still dispatch draw calls for the entire scene from the mirror's perspective.
2. **Compound Effect**: The scene instantiates multiple features using viewports (Mirrors, Rain, TV Screens). If several of these update continuously, the render thread must process each one independently, scaling the render time linearly with the number of active viewports. The profiler shows `Render Viewports` taking over 21ms because the CPU is overwhelmed by drawing multiple secondary camera perspectives.

## The Fix
To resolve this severe performance bottleneck, apply the following highly optimized solutions:

1. **Attach the Optimization Script**:
   * Instead of a raw `CSGBox3D`, replace the mirror in `TestBED` with the already existing optimized mirror scene (`interactables/mirror.tscn`), which uses the `mirror.gd` script.
   * This script includes critical optimizations: distance-culling (disabling the viewport when the player is too far away) and interleaved updates (rendering on alternating frames using `UPDATE_ONCE`).

2. **Change Update Mode to "When Visible" (If not using the script)**:
   * If replacing the node isn't preferred, simply set the `render_target_update_mode` on `InteractiveObjects/Mirror/SubViewport` to `UPDATE_WHEN_VISIBLE` in the inspector (or `render_target_update_mode = 1` in the `.tscn` text). This ensures the CPU only processes the viewport when the camera actually sees the mirror.

3. **Reduce Viewport Resolution**:
   * A 1280x720 render target is overkill for a mirror. Lower the `size` property of the `SubViewport` (e.g., to 512x512 or 256x256) to significantly reduce pixel fill rate and CPU/GPU cost.

4. **Optimize the Camera's Cull Mask**:
   * The `Camera3D` inside the mirror should only render what's absolutely necessary. Adjust its `cull_mask` to exclude small details, distant objects, particles, or complex shadows that aren't noticeably missing in the reflection.

5. **Review Other Viewports (Rain)**:
   * The `rain_viewport.tscn` uses a 2048x2048 resolution with `UPDATE_ALWAYS`. This is extremely expensive. Reduce the size to 512x512 or 1024x1024, or better yet, refactor the rain to use a pure shader approach or standard `GPUParticles3D` that doesn't rely on rendering to a full-sized viewport every frame.
