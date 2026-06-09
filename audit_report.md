# Optimization Audit Report

## 1. Heavy Asset Identification (High Priority)
The following image files exceed 1MB and may negatively impact loading times and memory usage.

**Approaching / Exceeding 10MB:**
- `./environment/cobblestone_curved_normal_ogl.png` - 10M
- `./environment/snow005_2_k_normal.jpg` - 7.9M
- `./environment/cobblestone_curved_albedo.png` - 6.1M
- `./environment/water_droplets.png` - 6.1M

**Other files exceeding 1MB:**
- `./environment/rain_droplet_normal.png` - 4.9M
- `./environment/ripples.png` - 3.1M
- `./environment/cobblestone_curved_roughness.png` - 2.4M
- `./shared/godiva_Godiva_Clothing_Normal_OpenGL.png` - 2.4M
- `./shared/godiva_godiva_clothing_normal_open_gl.png` - 2.4M
- `./environment/cobblestone_curved_height.png` - 2.3M
- `./shared/godiva_Godiva_Clothing_Metallic-Godiva_Clothing_Roughness.png` - 2.3M
- `./shared/godiva_godiva_clothing_metallic_godiva_clothing_roughness.png` - 2.3M
- `./shared/godiva_Godiva_Skin_Base_color-Godiva_Skin_Opacity.png` - 1.5M
- `./shared/godiva_Godiva_Skin_Normal_OpenGL.png` - 1.5M
- `./shared/godiva_godiva_skin_base_color_godiva_skin_opacity.png` - 1.5M
- `./shared/godiva_godiva_skin_normal_open_gl.png` - 1.5M
- `./shared/godiva_Godiva_Clothing_Base_color-Godiva_Clothing_Opacity.png` - 1.3M
- `./shared/godiva_godiva_clothing_base_color_godiva_clothing_opacity.png` - 1.3M
- `./shared/godiva_Godiva_Skin_Metallic-Godiva_Skin_Roughness.png` - 1.1M
- `./shared/godiva_godiva_skin_metallic_godiva_skin_roughness.png` - 1.1M


## 2. Architecture & Memory Bottlenecks
The following synchronous `load()` calls were found. These can potentially block the main thread. Consider using `preload()` (if appropriate for script initialization) or background loading (`ResourceLoader.load_threaded_request`) instead of synchronous loading at runtime.

- `./ui/gel_stream_3d.gd` Line 64: `_draw_mat.shader = load("res://ui/gel.gdshader") as Shader`
- `./ui/in_game_console.gd` Line 107: `mat.shader = load("res://vfx/colorblind.gdshader")`
- `./ui/in_game_console.gd` Line 118: `hc_mat.shader = load("res://vfx/high_contrast.gdshader")`
- `./vfx/smoke_manager.gd` Line 38: `precomputed_noise = load("res://vfx/smoke_noise_3d.tres") as Texture3D`
- `./vfx/smoke_manager.gd` Line 78: `var shader_file: RDShaderFile = load("res://vfx/smoke_compute.glsl")`

*(Note: `config.load(...)` in `player_old.gd` was ignored as it's a file I/O operation for a ConfigFile, not a resource load bottleneck).*

## 3. Code Performance & Standards Audit
The following codebase issues were found related to performance constraints.

**Expensive Operations in Process Functions:**
*(A quick search of `_process` and `_physics_process` revealed some node access overhead, but mostly cached `@onready` variables are used. However, I noticed dynamic group queries and node resolutions in frequently hit areas like loops.)*
- `./player/player.gd` Line 420: `for node: Node in get_tree().get_nodes_in_group("waterfall_area"):` (Called inside a function, ensure it is not called per-frame, as `get_nodes_in_group` causes allocation overhead in Godot 4).
- Dynamic get_node calls using `$` inside loops or process updates. Wait, looking closely at my results, most `$`, `get_node`, and `get_tree().get_nodes_in_group` calls are inside `_ready` or are `@onready` declarations, which is good practice. No severe `_process` offenders were explicitly detected in plain text, but continued vigilance is recommended for dynamic node path resolution.

**Missing Strict Static Typing:**
- All checked functions have strict static typing.

## 4. GDLint Standards Audit
The following GDLint violations were detected (excluding skipped files and addons). Below is a summary categorized by error type:

**Trailing Whitespace (Sample list):**
- `./player/player_state.gd` (multiple lines)
- `./player/zipline.gd`
- `./core/console.gd`
- `./ui/tv_screen_scene.gd`
- `./vfx/emitter.gd`

**Max Allowed Line Length (100) Exceeded:**
- `./core/console.gd` Lines 37, 72, 73, 83, 110, 117
- `./interactables/pickable_object.gd` Lines 15, 76, 336
- `./ui/chapter_screen.gd` Line 16
- `./ui/in_game_console.gd` Lines 4, 214, 411, 437, 439, 465, 535

**Definition Out of Order / Class Definitions Order:**
- `./core/global.gd`
- `./interactables/door_keypad.gd`
- `./interactables/door_interact.gd`
- `./interactables/universal_cable_3d.gd`
- `./interactables/physics_cable3_d.gd`
- `./ui/tv_screen_scene.gd`
- `./ui/ui.gd`

**Naming Violations:**
- `./interactables/door_keypad.gd` Line 7: `validCode` (class-variable-name)
- `./interactables/interact_component.gd` Line 2: `Interact_Component` (class-name)

*(A full list of 399 GDLint problems was generated during the scan. Fixing these is recommended for codebase consistency).*
