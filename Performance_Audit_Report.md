# Executive Summary
The project currently suffers from severe GPU bandwidth bottlenecks and CPU thread synchronization spikes, particularly visible on integrated graphics. While the codebase is structured cleanly around an Event-Driven pattern and leverages strict typing, the rendering pipeline is overburdened by heavy 3D noise texture reads inside volumetric space, and the physics pipeline is overwhelmed by direct transform manipulation during high-speed movement.

The primary culprits for the frame drops are:
1.  **Over-scaled Volumetric Fog:** The project settings force an incredibly dense volumetric fog volume (256 depth/size), saturating VRAM bandwidth.
2.  **PhysicsServer Rebuilds:** High-speed noclipping directly mutates `global_position`, forcing the PhysicsServer to rebuild the BVH (Bounding Volume Hierarchy) every frame.
3.  **Flawed Performance Manager:** The `GraphicsManager` only scales settings down, creating a false "improvement" anomaly when changing resolutions.

# 1. Symptom Analysis & Root Causes

**High-Speed Traversal Drops (Noclipping):**
Performance tanks when noclipping because `system_menu_controller.gd` modifies `player_body.global_position` directly inside `process_noclip()`. In Godot 4, directly translating a `CharacterBody3D` (a physics object) outside of `move_and_slide()` or `move_and_collide()` invalidates its bounding box in the broadphase tree. The PhysicsServer is forced to recalculate the entire physics world tree on the main thread every frame at high speeds.

**Max Resolution & Addon Overhead (Clouds):**
The `SunshineClouds2` addon (`vfx/box_clouds.gdshader`) performs three separate 3D texture reads (`texture(noise_texture, ...)`) per raymarch step inside the fog volume. At max screen resolution, the number of fragments processing this volumetric shader skyrockets. Because integrated GPUs share memory bandwidth with the CPU, this fill-rate bottleneck completely starves the system.

**Volumetric Fog Bandwidth:**
Historically a major issue, the root cause lies in `project.godot`. The settings `environment/volumetric_fog/volume_size=256` and `volume_depth=256` create a massive 3D texture buffer. Integrated GPUs cannot handle rendering a 256x256x256 volumetric froxel grid alongside standard scene geometry.

**The Resolution Toggle Anomaly:**
When you lower the resolution, FPS drops temporarily, triggering `GraphicsManager._evaluate_runtime_performance()`. This function detects FPS below 55 and permanently sets `volumetric_fog_enabled = false`, `ssao_enabled = false`, and `ssr_enabled = false`. It then calls `_fps_timer.stop()`. When you increase the resolution back to max, the heavy rendering features remain permanently disabled because the timer is dead and never checks if performance allows scaling them back up. The "inexplicable improvement" is simply the game running at max resolution without Volumetric Fog, SSAO, or SSR.

# 2. Code-Level Bottlenecks

*   **`player/system_menu_controller.gd` (Line 136):** `player_body.global_position += player_body.velocity * delta`. Directly mutating the transform of a CharacterBody3D causes severe physics server overloads.
*   **`core/graphics_manager.gd` (Line 95):** The `_evaluate_runtime_performance()` only scales graphics down, completely lacking logic to scale them back up if the target FPS is exceeded. It also aggressively stops the polling timer (`_fps_timer.stop()`).
*   **`environment/ocean.gd` (Line 170):** The `_process` function attempts to freeze updating via a "Mach 3 Noclip Speed Freeze". However, using `global_position` checks and distance culling inside standard `_process` still forces the CPU to evaluate this every frame.
*   **Missing Static Typing in `environment/ocean.gd`:** Several variables in `_manage_cpu_displacement_textures_updates` (like `_cpu_displacement_textures_indeces`) lack strict array typing (e.g., `Array[int]`), causing slower Variant dynamic dispatch.

# 3. Addon Profiling

**SunshineClouds2 Addon (`vfx/box_clouds.gdshader`)**
The cloud shader is exceptionally inefficient for integrated GPUs. The `fog()` pass is executed per-froxel. Inside this pass, the shader samples a heavy 3D Noise Texture three separate times (`macro_noise`, `base_noise`, `detail_noise`). 3D texture fetches are extremely bandwidth-intensive.

**Engine Volumetric Fog Implementation**
The base engine volumetric fog is crushing the GPU because of the project settings. `RenderingServer.environment_set_volumetric_fog_volume_size()` is being called in `GraphicsManager` with sizes of 64 or 32, but `project.godot` initializes it at 256. This means the engine allocates massive buffers on boot, which fragments VRAM immediately, even if it is later downscaled via code.

# 4. Actionable Fixes & Optimization Plan

**Priority 1: Fix the Graphics Manager (Code Rewrite)**
We need to allow `GraphicsManager` to turn settings back *up* when the user switches to a dedicated GPU or lowers their resolution.
*Fix:* Replace the existing `_evaluate_runtime_performance()` logic in `core/graphics_manager.gd` with the following GDLint-compliant code. Remove `_fps_timer.stop()` from the timer timeout logic.

```gdscript
func _evaluate_runtime_performance() -> void:
	print("GraphicsManager: _evaluate_runtime_performance() executed.")
	var current_fps: float = Engine.get_frames_per_second()

	if current_fps < TARGET_FPS_MINIMUM and not _performance_downgraded:
		print("GraphicsManager: FPS below target. Downgrading graphics dynamically.")
		_active_environment.volumetric_fog_enabled = false
		if not _is_low_end:
			_active_environment.ssao_enabled = false
			_active_environment.ssr_enabled = false
		_performance_downgraded = true

	elif current_fps >= (TARGET_FPS_MINIMUM + 5.0) and _performance_downgraded:
		print("GraphicsManager: FPS stable. Upgrading graphics dynamically.")
		_active_environment.volumetric_fog_enabled = true
		if not _is_low_end:
			_active_environment.ssao_enabled = true
			_active_environment.ssr_enabled = true
		_performance_downgraded = false
```

**Priority 2: Fix PhysicsServer Overloads during Noclip**
*Optimization Steps:*
1. Open `player/system_menu_controller.gd`.
2. Locate `process_noclip()`.
3. Remove the line: `player_body.global_position += player_body.velocity * delta`.
4. Replace it with: `player_body.move_and_collide(player_body.velocity * delta)`.
5. Ensure that when Noclip is toggled ON, you disable the collision mask of `player_body` (set it to 0) so it doesn't bump into walls, and restore it when Noclip is toggled OFF.

**Priority 3: Optimize Volumetric Fog & Project Settings**
*Optimization Steps:*
1. Open `project.godot` in a text editor (or via the Godot UI).
2. Change `environment/volumetric_fog/volume_size` from 256 to 64.
3. Change `environment/volumetric_fog/volume_depth` from 256 to 64.
4. This ensures the engine does not allocate huge VRAM buffers on startup.

**Priority 4: Optimize Cloud Shader 3D Texture Reads**
*Optimization Steps:*
1. Open `vfx/box_clouds.gdshader`.
2. Combine the `base_noise` and `detail_noise` passes into a single 2D texture read (using a baked noise map) instead of 3D, keeping only the `macro_noise` as a 3D volume.
3. Alternatively, pack the macro, base, and detail noises into the R, G, and B channels of a single 3D texture, allowing you to fetch all three values with only a single `texture()` call.
