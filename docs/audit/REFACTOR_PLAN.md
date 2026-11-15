# BellaSDK Ordered Refactoring Execution Plan (`REFACTOR_PLAN.md`)

## 1. Wave Execution Rules & Summary Table

Every runtime `.gd` and `.gdshader` file across all **15 runtime directories** (**595 files**, **119,089 `wc -l` lines** / **119,171 `splitlines` lines**) is partitioned into **19 topological refactor waves**, ordered from zero-dependency leaf shaders and pure helpers up to core orchestration and Autoload singletons. Every wave is strictly capped at **`<8,000` lines** (maximum wave size = **7,384 lines** in Wave 7).

| Wave | Architectural Tier / Domain | Files | `wc -l` Lines | Total Lines (`splitlines`) | `<8,000` Cap Check |
|---:|---|---:|---:|---:|---|
| **Wave 1** | Shaders (`.gdshader` Leaf & Include Pipeline — Part A) | 91 | 7,341 | 7,362 | PASS (`7,362 < 8,000`) |
| **Wave 2** | Shaders (`.gdshader` Leaf & Include Pipeline — Part B) | 119 | 7,026 | 7,087 | PASS (`7,087 < 8,000`) |
| **Wave 3** | Zero-Dependency GDScript Leaves & Foundational Core Helpers (Part A) | 51 | 7,245 | 7,245 | PASS (`7,245 < 8,000`) |
| **Wave 4** | Zero-Dependency GDScript Leaves & Foundational Core Helpers (Part B) | 45 | 5,748 | 5,748 | PASS (`5,748 < 8,000`) |
| **Wave 5** | Core Entity Components, Modular Props & Spatial Triggers | 26 | 4,634 | 4,634 | PASS (`4,634 < 8,000`) |
| **Wave 6** | VFX Controllers, Particles & Dynamic Ocean | 14 | 4,761 | 4,761 | PASS (`4,761 < 8,000`) |
| **Wave 7** | Environment Systems, Weather & World Geometry (Part A) | 19 | 7,384 | 7,384 | PASS (`7,384 < 8,000`) |
| **Wave 8** | Environment Systems (Part B) & Leaf Interactables | 16 | 4,737 | 4,737 | PASS (`4,737 < 8,000`) |
| **Wave 9** | Interactable Mechanisms & Physics Puzzles (Part A) | 29 | 6,894 | 6,894 | PASS (`6,894 < 8,000`) |
| **Wave 10** | Interactable Mechanisms & Physics Puzzles (Part B) | 23 | 6,752 | 6,752 | PASS (`6,752 < 8,000`) |
| **Wave 11** | Complex Interactables & Leaf Enemy Visuals/Entities | 9 | 4,598 | 4,598 | PASS (`4,598 < 8,000`) |
| **Wave 12** | Enemy AI, Combat Hazards & Weapon Ballistics | 21 | 6,883 | 6,883 | PASS (`6,883 < 8,000`) |
| **Wave 13** | World Streaming & User Interface Panels/HUDs (Part A) | 19 | 6,533 | 6,533 | PASS (`6,533 < 8,000`) |
| **Wave 14** | World Streaming & User Interface Panels/HUDs (Part B) | 15 | 6,946 | 6,946 | PASS (`6,946 < 8,000`) |
| **Wave 15** | Level Loaders, Options Router & Main Menu UI | 16 | 6,270 | 6,270 | PASS (`6,270 < 8,000`) |
| **Wave 16** | Player Controller, State Machine & Locomotion Components (Part A) | 20 | 6,567 | 6,567 | PASS (`6,567 < 8,000`) |
| **Wave 17** | Player Controller, State Machine & Locomotion Components (Part B) | 23 | 6,611 | 6,611 | PASS (`6,611 < 8,000`) |
| **Wave 18** | Core Orchestration, Console Subsystems & Autoload Singletons (Part A) | 21 | 7,281 | 7,281 | PASS (`7,281 < 8,000`) |
| **Wave 19** | Core Orchestration, Console Subsystems & Autoload Singletons (Part B) | 18 | 4,878 | 4,878 | PASS (`4,878 < 8,000`) |
| **TOTAL** | **All 15 Runtime Directories** | **595** | **119,089** | **119,171** | **100% `<8,000` Compliant** |

---

## 2. Detailed Wave Specifications (Waves 1–19)

### Wave 1: Shaders — Part A (91 files | `wc -l`: 7,341 | `splitlines`: 7,362)
- **Dependencies Satisfied**: Zero GDScript dependencies (leaf `.gdshader` files in `dynamic_ocean/`, `environment/`, `interactables/`, `player/`, `props/`, `shaders/`, `ui/`).
- **Files & Exact Line Counts**:
  - `dynamic_ocean/shaders/ocean_spray.gdshader` (47), `dynamic_ocean/shaders/ocean_spray_particle.gdshader` (178), `dynamic_ocean/shaders/ocean_water.gdshader` (167), `dynamic_ocean/shaders/oceanwave.gdshader` (91)
  - `environment/Citadel_TEST_2.gdshader` (57 wc / 58 lines), `environment/DynamicFog/dynamic_fog.gdshader` (205), `environment/argon_citadel_core/argon_citadel_corona.gdshader` (99), `environment/argon_citadel_core/argon_citadel_corona_waves.gdshader` (107), `environment/argon_citadel_core/argon_citadel_energy.gdshader` (82), `environment/argon_citadel_core/argon_citadel_heat_wave.gdshader` (75), `environment/argon_citadel_core/argon_citadel_inner_core.gdshader` (97), `environment/argon_citadel_core/argon_citadel_outer_shell.gdshader` (159), `environment/argon_water_body/argon_fog_fade.gdshader` (25), `environment/argon_water_body/argon_water.gdshader` (210), `environment/deprecated_camera_water_overlay.gdshader` (43 wc / 44 lines), `environment/deprecated_camera_water_overlay2.gdshader` (65 wc / 66 lines), `environment/electrified_floor.gdshader` (73 wc / 74 lines), `environment/flag_waving.gdshader` (65 wc / 66 lines), `environment/fog_fade.gdshader` (34), `environment/grain.gdshader` (22 wc / 23 lines), `environment/hydrogen_water_body/hydrogen_fog_fade.gdshader` (47), `environment/hydrogen_water_body/hydrogen_water_body.gdshader` (517), `environment/lex_partizan_rain/anti_tile.gdshader` (37), `environment/lex_partizan_rain/depth_buffer.gdshader` (16), `environment/lex_partizan_rain/rain.gdshader` (311), `environment/lex_partizan_rain/roof_depth.gdshader` (21), `environment/lex_partizan_rain/screen_space_snow.gdshader` (81), `environment/lightning_manager.gdshader` (47), `environment/lightning_orb.gdshader` (69), `environment/lightning_orb_arc.gdshader` (35), `environment/liquid_ribbon.gdshader` (52), `environment/projector_rain.gdshader` (28 wc / 29 lines), `environment/rainy_window_normal.gdshader` (58 wc / 59 lines), `environment/rainy_window_procedural.gdshader` (93 wc / 94 lines), `environment/water_body.gdshader` (528), `environment/water_ripple_overlay.gdshader` (108 wc / 109 lines), `environment/water_wipe_overlay.gdshader` (120 wc / 121 lines), `environment/waterfall.gdshader` (34 wc / 35 lines), `environment/waterfall_wipe_overlay.gdshader` (106 wc / 107 lines), `environment/weather_volume/dust_particle.gdshader` (87), `environment/weather_volume/snow_particle.gdshader` (93), `environment/windy_cloth.gdshader` (67 wc / 68 lines)
  - `interactables/conveyor_belt.gdshader` (29 wc / 30 lines), `interactables/energy_bar.gdshader` (29), `interactables/energy_cell_fill.gdshader` (24), `interactables/grimy_horror_glass.gdshader` (48), `interactables/indicator_led.gdshader` (17), `interactables/liquid_bottle/liquid_bottle.gdshader` (163), `interactables/mirror.gdshader` (125), `interactables/pickable_highlight.gdshader` (11 wc / 12 lines), `interactables/pneumatic_tube_glass.gdshader` (45), `interactables/portal.gdshader` (9), `interactables/rusted_horror_metal.gdshader` (68), `interactables/sewer_grate/sewer_grate.gdshader` (92), `interactables/wind_cable.gdshader` (59 wc / 60 lines)
  - `player/holographic_scanner.gdshader` (40 wc / 41 lines)
  - `props/breakable_shelf/breakable_shelf.gdshader` (29), `props/garage_gate/garage_panel.gdshader` (33), `props/gothic_arch/gothic_arch_stone.gdshader` (91)
  - `shaders/cinder_block.gdshader` (71), `shaders/crate_fade.gdshader` (13), `shaders/dark_man_surface.gdshader` (34), `shaders/drunk_post.gdshader` (59), `shaders/dumpster_weathered.gdshader` (116), `shaders/fluted_glass.gdshader` (46), `shaders/health_dispenser_screen.gdshader` (67), `shaders/heavy_rain_glass.gdshader` (74), `shaders/industrial_door.gdshader` (23), `shaders/lens_dirt_billboard.gdshader` (73), `shaders/props/gas_stove.gdshader` (90), `shaders/rain_drop.gdshader` (47), `shaders/rain_process.gdshader` (110), `shaders/roar_distortion.gdshader` (48), `shaders/screen_transition.gdshader` (42), `shaders/squid_tentacle.gdshader` (63), `shaders/tagged_prop.gdshader` (12), `shaders/textured_glass.gdshader` (125), `shaders/tube_opaque.gdshader` (15), `shaders/tube_transparent.gdshader` (81), `shaders/wind_wall.gdshader` (38)
  - `ui/VisionAssist.gdshader` (128), `ui/anime_speed_lines.gdshader` (85), `ui/claw_fire_outline.gdshader` (58), `ui/death_glass_screen.gdshader` (73), `ui/death_screen_ecg.gdshader` (73), `ui/death_screen_jitter.gdshader` (22), `ui/electricityvignette.gdshader` (24 wc / 25 lines), `ui/gel.gdshader` (50 wc / 51 lines), `ui/horror_black_glass.gdshader` (133), `ui/horror_glow_border.gdshader` (61), `ui/menu_chapter_screen.gdshader` (19 wc / 20 lines)
- **Specific Defects to Fix**:
  - Remove or archive unreferenced orphan shaders: `dynamic_ocean/shaders/oceanwave.gdshader:1`, `environment/deprecated_camera_water_overlay.gdshader:1`, `environment/lex_partizan_rain/anti_tile.gdshader:1`, `environment/lex_partizan_rain/depth_buffer.gdshader:1`, `environment/lex_partizan_rain/screen_space_snow.gdshader:1`, `environment/rainy_window_normal.gdshader:1`, `interactables/energy_cell_fill.gdshader:1`.
  - Deduplicate fog fade shaders (`environment/fog_fade.gdshader:1-34`, `environment/argon_water_body/argon_fog_fade.gdshader:1-25`, `environment/hydrogen_water_body/hydrogen_fog_fade.gdshader:1-47`) and normalize trailing newlines across 21 `.gdshader` files (e.g., `environment/Citadel_TEST_2.gdshader:57`, `environment/electrified_floor.gdshader:73`, `interactables/conveyor_belt.gdshader:29`, `player/holographic_scanner.gdshader:40`, `ui/menu_chapter_screen.gdshader:19`).
- **Verification**: `godot --headless --quit` (shader compilation check) + GUT suite.

### Wave 2: Shaders — Part B (119 files | `wc -l`: 7,026 | `splitlines`: 7,087)
- **Dependencies Satisfied**: Wave 1 (all remaining `ui/`, `vfx/`, `weapons/`, `world/` leaf `.gdshader` files).
- **Files & Exact Line Counts**:
  - `ui/setting_row_hover.gdshader` (105), `ui/ui_vignette.gdshader` (11 wc / 12 lines), `ui/ui_zoom_fisheye_blur.gdshader` (34 wc / 35 lines), `ui/wolf_vision.gdshader` (34)
  - `vfx/3DBurnShader.gdshader` (47 wc / 48 lines), `vfx/3Dshockwave.gdshader` (29 wc / 30 lines), `vfx/80sfantasy.gdshader` (112), `vfx/90anime.gdshader` (54 wc / 55 lines), `vfx/CitadelCode_Glowing_Circle.gdshader` (61 wc / 62 lines), `vfx/CitadelCore_HeatDistortion.gdshader` (18 wc / 19 lines), `vfx/CitadelCore_Waves.gdshader` (68 wc / 69 lines), `vfx/OuterLiquidShell.gdshader` (105 wc / 106 lines), `vfx/advisor_psychic.gdshader` (51), `vfx/arcane_burst.gdshader` (14), `vfx/argon_lightning_strike.gdshader` (53), `vfx/ascii.gdshader` (52 wc / 53 lines), `vfx/aurora_borealis.gdshader` (50), `vfx/beam.gdshader` (70), `vfx/blood_mist.gdshader` (88), `vfx/blood_spray.gdshader` (75), `vfx/botw.gdshader` (37 wc / 38 lines), `vfx/box_clouds.gdshader` (56 wc / 57 lines), `vfx/caustics_shader.gdshader` (53 wc / 54 lines), `vfx/censor_mosaic.gdshader` (36 wc / 37 lines), `vfx/chapter_text_blur.gdshader` (35 wc / 36 lines), `vfx/chapter_text_chromatic.gdshader` (38 wc / 39 lines), `vfx/chapter_text_dissolve.gdshader` (25 wc / 26 lines), `vfx/chapter_text_doom_melt.gdshader` (47 wc / 48 lines), `vfx/chapter_text_glitch.gdshader` (39 wc / 40 lines), `vfx/chapter_text_glow.gdshader` (49 wc / 50 lines), `vfx/chapter_text_hologram.gdshader` (63 wc / 64 lines), `vfx/chapter_text_light_sweep.gdshader` (25 wc / 26 lines), `vfx/chapter_text_liquid.gdshader` (26 wc / 27 lines), `vfx/chapter_text_neon.gdshader` (29 wc / 30 lines), `vfx/chapter_text_reveal.gdshader` (15 wc / 16 lines), `vfx/chapter_text_shatter.gdshader` (66 wc / 67 lines), `vfx/chapter_text_vhs.gdshader` (60 wc / 61 lines), `vfx/circle_equalizer.gdshader` (71 wc / 72 lines), `vfx/color_grading.gdshader` (86 wc / 87 lines), `vfx/colorblind.gdshader` (74), `vfx/control_hiss_distortion.gdshader` (61), `vfx/crt.gdshader` (14 wc / 15 lines), `vfx/curtain.gdshader` (30 wc / 31 lines), `vfx/death_screen_burn.gdshader` (23), `vfx/death_screen_cave_tunnel.gdshader` (86), `vfx/death_screen_lava.gdshader` (129), `vfx/death_screen_tv_static.gdshader` (35), `vfx/dev_texture.gdshader` (174 wc / 175 lines), `vfx/diorama_post_process.gdshader` (96), `vfx/energy_wall.gdshader` (60), `vfx/explosion_liquid_droplet.gdshader` (32), `vfx/explosion_shockwave.gdshader` (28), `vfx/explosion_sparks.gdshader` (13), `vfx/explosion_volumetric_smoke.gdshader` (84), `vfx/fadeeffects.gdshader` (31 wc / 32 lines), `vfx/fire.gdshader` (162), `vfx/gameboy.gdshader` (19 wc / 20 lines), `vfx/gas_leak.gdshader` (45 wc / 46 lines), `vfx/ghibli.gdshader` (62 wc / 63 lines), `vfx/glass_block.gdshader` (36), `vfx/glasses_condensation.gdshader` (116), `vfx/glitch.gdshader` (27 wc / 28 lines), `vfx/gothic_energy_gate.gdshader` (131), `vfx/green_blood.gdshader` (60), `vfx/halftone.gdshader` (24 wc / 25 lines), `vfx/handdrawn.gdshader` (60 wc / 61 lines), `vfx/harsh_contrast_transition.gdshader` (38), `vfx/heal_vignette.gdshader` (13), `vfx/hex_shield.gdshader` (178), `vfx/hex_shield_sphere.gdshader` (59), `vfx/high_contrast.gdshader` (23), `vfx/horror_text_shader.gdshader` (87), `vfx/jelly.gdshader` (127), `vfx/kuwahara.gdshader` (61 wc / 62 lines), `vfx/lightning_bolt.gdshader` (69), `vfx/lightning_mark.gdshader` (44), `vfx/lightning_wave.gdshader` (47), `vfx/magnifying_glass.gdshader` (45 wc / 46 lines), `vfx/mandelbrot.gdshader` (60 wc / 61 lines), `vfx/manga.gdshader` (76 wc / 77 lines), `vfx/moebius.gdshader` (93 wc / 94 lines), `vfx/motion_blur.gdshader` (28), `vfx/nightvision.gdshader` (24 wc / 25 lines), `vfx/obra.gdshader` (39 wc / 40 lines), `vfx/oil_spill.gdshader` (63), `vfx/old_photo.gdshader` (143), `vfx/outline_hearts_adaptable.gdshader` (32 wc / 33 lines), `vfx/outline_shader.gdshader` (30 wc / 31 lines), `vfx/outline_shader_adaptable.gdshader` (27), `vfx/phys_magnet.gdshader` (63 wc / 64 lines), `vfx/pixelate.gdshader` (11 wc / 12 lines), `vfx/plasma_spark.gdshader` (14), `vfx/pressurized_fire_jet/pressurized_fire_jet.gdshader` (105), `vfx/psychedelic.gdshader` (58 wc / 59 lines), `vfx/pulsing_border.gdshader` (20), `vfx/reaction_diffusion.gdshader` (64 wc / 65 lines), `vfx/refraction_tunnel.gdshader` (83), `vfx/shockwave_refract.gdshader` (28), `vfx/smart_outline_material.gdshader` (72 wc / 73 lines), `vfx/smoke_billow.gdshader` (161), `vfx/smoke_lod.gdshader` (32), `vfx/snow_deform.gdshader` (46), `vfx/software.gdshader` (40 wc / 41 lines), `vfx/splat.gdshader` (39), `vfx/swirl.gdshader` (44 wc / 45 lines), `vfx/toon.gdshader` (12 wc / 13 lines), `vfx/turing.gdshader` (29 wc / 30 lines), `vfx/unlit_outline_material.gdshader` (63 wc / 64 lines), `vfx/updraft_paper_strip.gdshader` (34), `vfx/updraft_smoke.gdshader` (92), `vfx/updraft_wind_lines.gdshader` (38), `vfx/vhs.gdshader` (64 wc / 65 lines), `vfx/water_effects_overlay.gdshader` (131), `vfx/water_particle.gdshader` (48), `vfx/water_sheet_wipe.gdshader` (143), `vfx/waterfall_3d.gdshader` (104 wc / 105 lines), `vfx/zoom_mask.gdshader` (55 wc / 56 lines)
  - `weapons/smoke_grenade/smoke_grenade_cloud.gdshader` (222)
  - `world/chunks/test_chunk_tint.gdshader` (6)
- **Specific Defects to Fix**:
  - Remove or wire unreferenced orphan shaders: `vfx/chapter_text_glow.gdshader:1`, `vfx/glass_block.gdshader:1`, `vfx/motion_blur.gdshader:1`, `vfx/outline_shader.gdshader:1`, `vfx/reaction_diffusion.gdshader:1`, `vfx/smart_outline_material.gdshader:1`, `vfx/turing.gdshader:1`.
  - Normalize trailing newlines on 61 `.gdshader` files (e.g., `ui/ui_vignette.gdshader:11`, `vfx/3DBurnShader.gdshader:47`, `vfx/color_grading.gdshader:86`, `vfx/zoom_mask.gdshader:55`).
- **Verification**: `godot --headless --quit` + GUT suite.

### Wave 3: Zero-Dependency GDScript Leaves & Foundational Core Helpers — Part A (51 files | `wc -l`: 7,245 | `splitlines`: 7,245)
- **Dependencies Satisfied**: Waves 1–2 (0 outbound GDScript dependencies).
- **Files & Exact Line Counts**:
  - `core/collision_layers.gd` (77), `core/components/powered_object.gd` (71), `core/components/rotator_component.gd` (27), `core/frame_graph.gd` (89), `core/material_cache.gd` (50), `core/math_utils.gd` (163), `core/object_pool.gd` (233), `core/render_context.gd` (249), `core/save_slot.gd` (137), `core/shader_cache.gd` (14), `core/singletons/system_locator.gd` (105), `core/splash_screen.gd` (31), `core/texture_baker.gd` (279)
  - `dynamic_ocean/wave_cascade_parameters.gd` (78)
  - `enemies/hex_shield.gd` (187), `enemies/spook_encounter.gd` (655)
  - `environment/animated_cube_wall.gd` (233), `environment/argon_citadel_core/argon_citadel_core.gd` (328), `environment/argon_water_body/argon_underwater_fog_volume.gd` (133), `environment/aurora_ribbon.gd` (94), `environment/box_clouds.gd` (66), `environment/citadel_test_2.gd` (61), `environment/cloth.gd` (68), `environment/decal.gd` (53), `environment/gothic_cathedral.gd` (346), `environment/graphics_cctv_camera.gd` (50), `environment/hiss_resonance_volume.gd` (67), `environment/hydrogen_water_body/hydrogen_fog_volume.gd` (108), `environment/interactive_lightning.gd` (153), `environment/lex_partizan_rain/rain_demo_controller.gd` (163), `environment/lex_partizan_rain/roof_viewport.gd` (13), `environment/lightning_manager.gd` (361), `environment/mannequin_volume.gd` (791), `environment/procedural_fence_csg.gd` (255), `environment/rain.gd` (50), `environment/ribbon_wall.gd` (362), `environment/rotating_lamp.gd` (85), `environment/snow_painter.gd` (118), `environment/soundscape_data.gd` (20), `environment/torch.gd` (133), `environment/twisted_hallway_logic.gd` (53), `environment/water_cube_test.gd` (41), `environment/water_wipe_overlay.gd` (43), `environment/weather_volume/weather_volume.gd` (153), `environment/wind_controller.gd` (57)
  - `interactables/basalt_magnet.gd` (22), `interactables/cable_point_3d.gd` (14), `interactables/conveyor_belt.gd` (135), `interactables/curtain.gd` (32), `interactables/dev_comment/auto_scroll_container.gd` (67), `interactables/door_slide.gd` (72)
- **Specific Defects to Fix**:
  - `core/collision_layers.gd:5-29` & `project.godot:218-230`: Add Physics Layer 11 (`Preview/Diorama`, `LAYER_PREVIEW_DIORAMA = 11`, `MASK_PREVIEW_DIORAMA = 1 << 10`).
  - `core/object_pool.gd:36, 143-150, 188-195`: Type `_active_ids: Dictionary[int, Node]` and defer physics state mutations (`set_deferred`).
  - `core/math_utils.gd:9, 16, 27, 34`: Type return dictionaries (`{&"position": new_position, &"velocity": new_velocity}`).
  - `core/singletons/system_locator.gd:15, 45, 50-96, 102`: Type `_services`, eliminate duplicate function calls in ternary checks (`L45, 102`), and deduplicate lookup methods (`L50-96`).
  - `core/render_context.gd:50, 102, 228`: Type collections and replace runtime `load()` (`L102`).
  - `core/splash_screen.gd:31`: Fix broken path `"res://scenes/main_menu.tscn"` -> `"res://ui/main_menu.tscn"`.
  - `core/components/rotator_component.gd:19` & `core/frame_graph.gd:29, 35`: Gate `_process` and replace `history.pop_front()`.
  - `enemies/hex_shield.gd:84, 111, 152, 154, 168`: Use `CollisionLayers.MASK_NONE`, `StringName` in `set_deferred`, and `Utilities.reset_tween()`.
  - `enemies/spook_encounter.gd:174, 188, 482, 516, 518, 606, 631, 634`: Gate `_process`, defer `queue_free()` at `L606`, narrow `wall_hit.get(&"position")` at `L518`, and eliminate per-frame `PhysicsRayQueryParameters3D.create()` at `L631`.
  - `environment/interactive_lightning.gd:1, 36, 54, 125`: Fix broken scene reference in `environment/lightning_scene.tscn:3` (`res://environment/interactive_lightning.gd`) and gate `_process`.
  - Remove or wire orphan scripts `environment/box_clouds.gd:1`, `environment/cloth.gd:1`, `environment/water_wipe_overlay.gd:1`.
- **Verification**: `gdformat --check <wave3_files> && gdlint <wave3_files>` + GUT suite.

### Wave 4: Zero-Dependency GDScript Leaves & Foundational Core Helpers — Part B (45 files | `wc -l`: 5,748 | `splitlines`: 5,748)
- **Dependencies Satisfied**: Waves 1–3 (`CollisionLayers`, `NodeQuery`, `Types`, `State` <-> `StateMachine`).
- **Files & Exact Line Counts**:
  - `core/node_query.gd` (129), `core/reference_data.gd` (38), `core/state.gd` (35), `core/state_machine.gd` (128), `core/types.gd` (133), `core/utilities.gd` (160)
  - `interactables/drawbridge.gd` (231), `interactables/gate.gd` (58), `interactables/interact_body_test.gd` (21), `interactables/interact_component.gd` (104), `interactables/keycard_data.gd` (20), `interactables/ladder.gd` (87), `interactables/meat_cube.gd` (118), `interactables/output_transmitter_3d.gd` (135), `interactables/physics_cable3_d.gd` (307), `interactables/physics_magnet.gd` (155), `interactables/poker_projectile.gd` (24), `interactables/procedural_ladder.gd` (159), `interactables/spike_trap.gd` (159), `interactables/static_cable.gd` (174), `interactables/ui_circle_keypad.gd` (305), `interactables/ui_keypad.gd` (104)
  - `player/physics_pusher.gd` (80), `player/procedural_spiral_stairs_csg.gd` (174), `player/stair_controller.gd` (224)
  - `ui/debug_pellet.gd` (13), `ui/fps_counter.gd` (29), `ui/fullscreen_control.gd` (26), `ui/lvl_instance_hide_building.gd` (30), `ui/machine_lock_ui.gd` (123), `ui/menu_chapter_data.gd` (15), `ui/perf_overlay.gd` (119), `ui/settings_search.gd` (719), `ui/video_config.gd` (486), `ui/vrs_texture_generator.gd` (30)
  - `vfx/TinnitusEffect.gd` (49), `vfx/arcane_burst.gd` (27), `vfx/blood_decal.gd` (44), `vfx/blood_splatter.gd` (44), `vfx/gas_leak_emitter.gd` (29), `vfx/lightning_strike_vfx.gd` (207), `vfx/plasma_spark.gd` (27), `vfx/trail_3d.gd` (204), `vfx/waterfall_controller.gd` (31), `vfx/wind_wall.gd` (234)
- **Specific Defects to Fix**:
  - `core/state_machine.gd:35, 41, 62, 68, 80, 87, 109, 114`: Remove `if self is PlayerStateMachine:` base-to-subclass check (`L35`), fix duplicate ternary calls (`L41, 87`), and type `message: Dictionary`.
  - `core/node_query.gd:113-129` & `core/utilities.gd:94-112`: Consolidate duplicated raycast helper and type return dictionaries.
  - `interactables/meat_cube.gd:32, 35, 52, 96`: Replace runtime `ResourceLoader.load()` (`L32, 96`), string `call_deferred` (`L35`), and un-gated `_physics_process` (`L52`).
  - `interactables/ui_circle_keypad.gd:6, 10, 14, 18, 187, 273`: Remove `@warning_ignore`, replace runtime `load(path)` (`L187`), and use `NodeQuery.find_health_component()` (`L273`).
  - `interactables/drawbridge.gd:79, 80, 218, 219, 231` & `interactables/physics_magnet.gd:49, 62, 64`: Use `CollisionLayers` constants and `StringName` in `set_deferred`.
  - `ui/vrs_texture_generator.gd:24`: Replace `distance_to()` with `distance_squared_to()`.
  - Remove or wire orphan scripts `ui/fullscreen_control.gd:1`, `vfx/TinnitusEffect.gd:1`, `vfx/blood_decal.gd:1`, `vfx/blood_splatter.gd:1`, `vfx/waterfall_controller.gd:1`.
- **Verification**: `gdformat --check <wave4_files> && gdlint <wave4_files>` + GUT suite.

### Wave 5: Core Entity Components, Modular Props & Spatial Triggers (26 files | `wc -l`: 4,634 | `splitlines`: 4,634)
- **Dependencies Satisfied**: Waves 1–4 (`CollisionLayers`, `NodeQuery`, `Utilities`, `Types`).
- **Files & Exact Line Counts**:
  - `core/components/faction_component.gd` (64), `core/components/health_component.gd` (147), `core/components/health_modifier.gd` (250)
  - `dynamic_ocean/wave_generator.gd` (357)
  - `props/breakable_shelf/breakable_shelf.gd` (157), `props/garage_gate/garage_gate.gd` (345), `props/gothic_arch/gothic_arch_post_import.gd` (143), `props/gothic_arch/gothic_arch_prop.gd` (59)
  - `triggers/base_trigger_area_3d.gd` (271), `triggers/crab_shell_trigger.gd` (33), `triggers/drunk_trigger.gd` (38), `triggers/editor_trigger_visualizer.gd` (341), `triggers/env_chapter_trigger.gd` (63), `triggers/fade_trigger.gd` (59), `triggers/killfield.gd` (43), `triggers/mannequin_attractor_trigger.gd` (276), `triggers/music_trigger.gd` (430), `triggers/spotlight_seq_trigger.gd` (27), `triggers/target_arrival_box_3d.gd` (38), `triggers/teleport.gd` (52), `triggers/trigger_hint.gd` (135), `triggers/trigger_look.gd` (109), `triggers/wake_up_trigger.gd` (242)
  - `vfx/3DShockwaveTester.gd` (34), `vfx/effects/control_explosion.gd` (600), `vfx/water_leak.gd` (321)
- **Specific Defects to Fix**:
  - `core/components/health_modifier.gd:89, 109-114, 223, 238`: Stop timer when no bodies overlap (`L109-114`), remove tick `print()` (`L223`), type `_health_cache` (`L89`), and fix duplicate ternary call (`L238`).
  - `core/components/faction_component.gd:12`: Decouple from `Player` (`player/player.gd`) via group `&"player"` to break 2-cycle.
  - `triggers/crab_shell_trigger.gd:33`: Replace synchronous `queue_free()` in `_on_body_entered` with `call_deferred(&"queue_free")`.
  - `triggers/editor_trigger_visualizer.gd:101, 103`: Remove `has_signal` check and disconnect `Events.trigger_visibility_toggled` in `_exit_tree()`.
  - `triggers/trigger_hint.gd:51`: Replace `events_node.emit_signal(&"hint_requested", ...)` with typed `Events.hint_requested.emit(...)`.
  - `props/breakable_shelf/breakable_shelf.gd:10, 111, 112, 139`: Remove `@warning_ignore`, use `CollisionLayers.MASK_NONE`, and reset tween via `Utilities.reset_tween()`.
  - `vfx/water_leak.gd:103, 234, 245, 246`: Use `CollisionLayers`, type dictionary, and replace `distance_to()` with `distance_squared_to()`.
  - Remove orphan `vfx/3DShockwaveTester.gd:1` (note: `props/gothic_arch/gothic_arch_prop.gd:1-59` is actively bound by `props/gothic_arch/gothic_arch_post_import.gd:12` and `levels/chunks/testbed/chunk_0_-2.scn`).
- **Verification**: `gdformat --check <wave5_files> && gdlint <wave5_files>` + GUT suite.

### Wave 6: VFX Controllers, Particles & Dynamic Ocean (14 files | `wc -l`: 4,761 | `splitlines`: 4,761)
- **Dependencies Satisfied**: Waves 1–5 (`WaveCascadeParameters`, `WaveGenerator`, `RenderContext`, `CollisionLayers`, `HealthComponent`, `Utilities`).
- **Files & Exact Line Counts**:
  - `dynamic_ocean/ocean.gd` (700), `dynamic_ocean/waveheight_script.gd` (81)
  - `environment/hydrogen_water_body/hydrogen_water_body.gd` (1165)
  - `scenes/vfx/explosion_crysis.gd` (220)
  - `vfx/color_grading_volume.gd` (505), `vfx/dust_puff.gd` (9), `vfx/effects/argon_lightning_controller.gd` (329), `vfx/energy_wall.gd` (201), `vfx/gel_emitter.gd` (257), `vfx/particle.gd` (175), `vfx/phys_explosion_3d.gd` (108), `vfx/pressurized_fire_jet/pressurized_fire_jet.gd` (377), `vfx/screenshake_effect.gd` (182), `vfx/smoke_explosion.gd` (452)
- **Specific Defects to Fix**:
  - `dynamic_ocean/waveheight_script.gd:46, 51-55`: Gate `_process` and narrow `water.call(&"get_height", ...)` `Variant` return before `float(...)`.
  - `environment/hydrogen_water_body/hydrogen_water_body.gd:481, 687, 1162, 1165`: Gate `_process`, use `Utilities.reset_tween()`, type array, and replace `events.callv(&"emit_signal", call_args)` with direct `Events` signals.
  - `vfx/phys_explosion_3d.gd:60, 94`: Gate `_physics_process` and replace `distance_to()` with `distance_squared_to()`.
  - `vfx/smoke_explosion.gd:10, 14`: Remove `@warning_ignore("unused_signal")`.
- **Verification**: `gdformat --check <wave6_files> && gdlint <wave6_files>` + GUT suite.

### Wave 7: Environment Systems, Weather & World Geometry — Part A (19 files | `wc -l`: 7,384 | `splitlines`: 7,384)
- **Dependencies Satisfied**: Waves 1–6 (`CollisionLayers`, `MaterialCache`, `MathUtils`, `NodeQuery`, `Utilities`, `PoweredObject`).
- **Files & Exact Line Counts**:
  - `environment/DynamicFog/dynamic_fog_zone.gd` (584), `environment/UnderwaterFogVolume.gd` (143), `environment/accessible_label_body.gd` (157), `environment/argon_water_body/argon_water_body.gd` (752), `environment/basalt_generator.gd` (326), `environment/citadel_core.gd` (119), `environment/crab_shell.gd` (202), `environment/dust_volume.gd` (355), `environment/electrified_floor.gd` (133), `environment/flag_waving.gd` (213), `environment/gothic_energy_gate.gd` (722), `environment/highlight_component.gd` (588), `environment/lightning_orb.gd` (397), `environment/rain_controller.gd` (383), `environment/snow_ground.gd` (105), `environment/supply_shell.gd` (300), `environment/water_body.gd` (1538), `environment/waypoint_3d.gd` (316), `environment/world_environment.gd` (51)
- **Specific Defects to Fix**:
  - `environment/DynamicFog/dynamic_fog_zone.gd:207, 225, 318`: Replace material `.duplicate()` with `MaterialCache`/instance params, use `CollisionLayers`, and replace `distance_to()` with `distance_squared_to()`.
  - `environment/gothic_energy_gate.gd:302, 530, 616`: Add `_exit_tree()` signal disconnect (`L302`), replace runtime `load(SHADER_PATH)` with `preload()` (`L530`), and reset tween (`L616`).
  - `environment/supply_shell.gd:238`: Replace runtime `ResourceLoader.load()` with `preload()`.
  - `environment/highlight_component.gd:136, 146, 249-281, 402-405, 567, 578-580`: Remove `_process` `print()` (`L146`), disconnect all 9 `Events.outline_*` signals in `_exit_tree()` (`L136`), pre-allocate `StringName` shader uniform keys, and type dictionary.
  - `environment/argon_water_body/argon_water_body.gd:745`: Replace `events.callv(&"emit_signal", call_args)` with typed `Events` signals.
  - `environment/rain_controller.gd:168, 203, 368`: Use `Utilities.reset_tween()`, `CollisionLayers`, and typed collections.
  - `environment/waypoint_3d.gd:206`: Replace `distance_to()` with `distance_squared_to()`.
- **Verification**: `gdformat --check <wave7_files> && gdlint <wave7_files>` + GUT suite.

### Wave 8: Environment Systems (Part B) & Leaf Interactables (16 files | `wc -l`: 4,737 | `splitlines`: 4,737)
- **Dependencies Satisfied**: Waves 1–7 (`HighlightComponent`, `PoweredObject`, `SoundscapeData`, `CollisionLayers`, `NodeQuery`, `Utilities`).
- **Files & Exact Line Counts**:
  - `environment/oil_spill_path.gd` (425), `environment/powered_light_3d.gd` (455), `environment/procedural_barbwire.gd` (207), `environment/procedural_monkey_bars.gd` (74), `environment/procedural_tube.gd` (308), `environment/smoke_hazard.gd` (517), `environment/soundscape_zone.gd` (391), `environment/tagged_prop.gd` (242), `environment/target_volume.gd` (416), `environment/updraft_vent.gd` (427), `environment/waterfall.gd` (83), `environment/wolf_climb_surface.gd` (347)
  - `interactables/PulleyCableVisual3D.gd` (95), `interactables/cable_builder.gd` (74), `interactables/checkpoint.gd` (357), `interactables/dev_comment/developer_commentary.gd` (319)
- **Specific Defects to Fix**:
  - `environment/powered_light_3d.gd:367`: Replace `(active_mat as BaseMaterial3D).duplicate()` with `MaterialCache` or per-instance shader parameters.
  - `environment/wolf_climb_surface.gd:7, 40, 165, 189, 197, 334-336`: Remove `@warning_ignore`, type dictionary, gate `_physics_process`, remove `_physics_process` `print()` statements (`L189, 197`), and decouple from `StateWolfWallRun`.
  - `environment/oil_spill_path.gd:166, 276, 316`: Gate `_process`, replace `distance_to()` with `distance_squared_to()`, and type dictionary.
  - `environment/target_volume.gd:151, 152`: Use `CollisionLayers` constants.
  - `interactables/dev_comment/developer_commentary.gd:195, 226, 279, 309`: Replace string `emit_signal` and use `Utilities.reset_tween()`.
- **Verification**: `gdformat --check <wave8_files> && gdlint <wave8_files>` + GUT suite.

### Wave 9: Interactable Mechanisms & Physics Puzzles — Part A (29 files | `wc -l`: 6,894 | `splitlines`: 6,894)
- **Dependencies Satisfied**: Waves 1–8 (`InteractComponent`, `HighlightComponent`, `OutputTransmitter3D`, `PoweredObject`, `HealthComponent`, `CollisionLayers`, `NodeQuery`, `Utilities`).
- **Files & Exact Line Counts**:
  - `interactables/breakable_crate.gd` (286), `interactables/burnable_obstacle.gd` (171), `interactables/button.gd` (182), `interactables/cinder_block/cinder_block.gd` (76), `interactables/combination_lock.gd` (152), `interactables/combustible_object.gd` (183), `interactables/door_interact.gd` (152), `interactables/door_keypad.gd` (291), `interactables/double_sliding_doors.gd` (176), `interactables/engine_ramp.gd` (564), `interactables/explosive_barrel.gd` (256), `interactables/feedback_station.gd` (122), `interactables/gas_stove.gd` (88), `interactables/ground_button.gd` (121), `interactables/health_upgrade.gd` (133), `interactables/keycard_lock.gd` (175), `interactables/keycard_pickup.gd` (59), `interactables/ladder_4m.gd` (36), `interactables/laser_target.gd` (53), `interactables/mannequin_ragdoll.gd` (401), `interactables/note_item.gd` (132), `interactables/pickable_object.gd` (920), `interactables/player_drone.gd` (171), `interactables/portal.gd` (362), `interactables/pulley_controller.gd` (113), `interactables/puzzle_socket.gd` (500), `interactables/reflector_mirror.gd` (265), `interactables/universal_cable_3d.gd` (79), `interactables/valve_base.gd` (675)
- **Specific Defects to Fix**:
  - `interactables/pickable_object.gd:215-216, 546, 641, 741, 901`: Disconnect `Events.noclip_toggled` and `Events.item_prompts_toggled` in `_exit_tree()`, type raycast dictionaries, and use `NodeQuery.find_health_component()` (`L901`).
  - `interactables/puzzle_socket.gd:137, 139, 359, 416`: Disconnect `Events.item_prompts_toggled` in `_exit_tree()`, defer `rb_plug.freeze = false` via `set_deferred(&"freeze", false)` (`L359`), and remove `has_signal` checks.
  - `interactables/valve_base.gd:168, 170, 201, 620, 673, 675`: Disconnect `Events.item_prompts_toggled` in `_exit_tree()`, use typed `Events` signals, gate `_process`, and type `events: Array[InputEvent]`.
  - `interactables/portal.gd:56, 77, 88`: Disconnect `Events.player_camera_registered` and `get_viewport().size_changed` in `_exit_tree()`.
  - `interactables/burnable_obstacle.gd:131, 148, 163`: Defer `torch.queue_free()`, use `Utilities.reset_tween()`, and pass `&"StringName"` to `set_deferred`.
  - `interactables/gas_stove.gd:8, 9`: Remove dead `signal stove_impacted(impulse_sq: float)` and `@warning_ignore`.
- **Verification**: `gdformat --check <wave9_files> && gdlint <wave9_files>` + GUT suite.

### Wave 10: Interactable Mechanisms & Physics Puzzles — Part B (23 files | `wc -l`: 6,752 | `splitlines`: 6,752)
- **Dependencies Satisfied**: Waves 1–9 (`PickableObject`, `Valve`, `InteractComponent`, `HighlightComponent`, `OutputTransmitter3D`, `PoweredObject`).
- **Files & Exact Line Counts**:
  - `interactables/cell_recharger.gd` (538), `interactables/energy_cell.gd` (138), `interactables/glider_item.gd` (393), `interactables/health_dispenser.gd` (972), `interactables/heavy_pickable_box.gd` (317), `interactables/industrial_door.gd` (431), `interactables/jump_pad.gd` (372), `interactables/lever_stick_item.gd` (144), `interactables/liquid_bottle/pickable_liquid_bottle.gd` (327), `interactables/mirror.gd` (327), `interactables/path_stick.gd` (101), `interactables/pickable_box.gd` (6), `interactables/pickable_tire.gd` (42), `interactables/pickable_valve.gd` (35), `interactables/pneumatic_tube.gd` (243), `interactables/push_wheel.gd` (567), `interactables/raft_platform.gd` (211), `interactables/scissor_gate/scissor_gate.gd` (122), `interactables/sewer_grate/sewer_grate.gd` (227), `interactables/shooting_target.gd` (126), `interactables/tethered_plug.gd` (192), `interactables/wall_generator.gd` (563), `interactables/wall_lever.gd` (358)
- **Specific Defects to Fix**:
  - `interactables/cell_recharger.gd:174`, `interactables/pneumatic_tube.gd:201`, `interactables/wall_generator.gd:185`: Defer `freeze = true` via `set_deferred(&"freeze", true)` inside collision callbacks.
  - `interactables/lever_stick_item.gd:50, 59, 69, 131, 144`: Defer `queue_free()` via `call_deferred(&"queue_free")` (`L144`) and use `StringName` in `set_deferred`.
  - `interactables/health_dispenser.gd:195, 210, 588`: Type `_conduit_arrays` / `_sucker_arrays` and replace `distance_to()` with `distance_squared_to()` (`L588`).
  - `interactables/tethered_plug.gd:183`: Replace runtime material `.duplicate()` with `MaterialCache` or instance shader parameters.
  - `interactables/scissor_gate/scissor_gate.gd:7, 11, 15` & `interactables/sewer_grate/sewer_grate.gd:8, 12, 16, 20`: Remove `@warning_ignore("unused_signal")`.
- **Verification**: `gdformat --check <wave10_files> && gdlint <wave10_files>` + GUT suite.

### Wave 11: Complex Interactables & Leaf Enemy Visuals/Entities (9 files | `wc -l`: 4,598 | `splitlines`: 4,598)
- **Dependencies Satisfied**: Waves 1–10 (`InteractComponent`, `HighlightComponent`, `OutputTransmitter3D`, `ObjectPool`, `CollisionLayers`, `NodeQuery`).
- **Files & Exact Line Counts**:
  - `enemies/dark_man/dark_man_visuals.gd` (116), `enemies/elf_drone.gd` (466), `enemies/flying_tile.gd` (139), `enemies/hex_shield_sphere.gd` (711)
  - `interactables/dumpster/dumpster.gd` (207), `interactables/rope/climb_rope.gd` (1050), `interactables/slide_track.gd` (44), `interactables/stationary_laser_stand.gd` (706), `interactables/timber_jib_crane.gd` (1159)
- **Specific Defects to Fix**:
  - `enemies/elf_drone.gd:7, 8, 40, 144, 442`: Remove dead `signal healing_pulsed(target: Node3D, amount: int)` and `@warning_ignore`, break 2-cycle with `DroneSwarmController` (`L40`), gate `_physics_process` (`L144`), and replace `distance_to()` with `distance_squared_to()` (`L442`).
  - `enemies/flying_tile.gd:63, 121, 139`: Gate `_physics_process`, use `NodeQuery.find_health_component()` (`L121`), and defer `queue_free()` in `_destroy_tile` (`L139`).
  - `enemies/hex_shield_sphere.gd:99, 166, 238, 292, 342, 371` & `enemies/dark_man/dark_man_visuals.gd:71`: Use `CollisionLayers.MASK_NONE` and `Utilities.reset_tween()`.
  - `interactables/stationary_laser_stand.gd:289, 385, 456-460, 592, 612, 686`: Gate `_physics_process`, use `NodeQuery.find_health_component()`, replace `distance_to()` with `distance_squared_to()`, and reset tween.
  - `interactables/rope/climb_rope.gd:246, 729, 740`: Use `CollisionLayers.MASK_NONE` and type dictionary.
- **Verification**: `gdformat --check <wave11_files> && gdlint <wave11_files>` + GUT suite.

### Wave 12: Enemy AI, Combat Hazards & Weapon Ballistics (21 files | `wc -l`: 6,883 | `splitlines`: 6,883)
- **Dependencies Satisfied**: Waves 1–11 (`HealthComponent`, `FactionComponent`, `ObjectPool`, `CollisionLayers`, `NodeQuery`, `Utilities`, `Types`).
- **Files & Exact Line Counts**:
  - `enemies/bear_trap.gd` (126), `enemies/drone_swarm_controller.gd` (539), `enemies/evil_goon.gd` (142), `enemies/fire.gd` (457), `enemies/guardian_pillar.gd` (196), `enemies/guardian_projectile.gd` (123), `enemies/rook_trap.gd` (236), `enemies/sensor_turret.gd` (402), `enemies/squid/enemy_squid.gd` (1030), `enemies/squid/squid_puddle.gd` (258), `enemies/tentacle.gd` (117), `enemies/tentacle_enemy.gd` (464), `enemies/tripmine.gd` (444), `enemies/turret.gd` (507), `enemies/wave_spawner.gd` (174)
  - `weapons/signal_rocket/signal_rocket_projectile.gd` (378), `weapons/signal_rocket/signal_rocket_weapon.gd` (327), `weapons/smoke_grenade/smoke_grenade_cloud.gd` (378), `weapons/smoke_grenade/smoke_grenade_projectile.gd` (72), `weapons/smoke_grenade/smoke_grenade_weapon.gd` (31), `weapons/throwable_weapon.gd` (482)
- **Specific Defects to Fix**:
  - `enemies/guardian_pillar.gd:57, 81, 84, 120, 125, 185` & `enemies/guardian_projectile.gd:51, 64, 82`: Break 2-cycle (`enemies/guardian_projectile.gd:64`), pre-allocate `SphereShape3D` / `PhysicsShapeQueryParameters3D` / `PhysicsRayQueryParameters3D` instead of allocating per physics frame (`L81, 84, 120`), and reset tween (`enemies/guardian_projectile.gd:82`).
  - `enemies/drone_swarm_controller.gd:133, 146, 151, 312-315`: Use typed `Events.player_damaged.connect(...)`, disconnect in `_exit_tree()` (`L133`), and use `NodeQuery.find_health_component()`.
  - `enemies/tentacle_enemy.gd:99, 338`: Defer `projectile.freeze = false` via `set_deferred(&"freeze", false)` (`L338`).
  - `enemies/turret.gd:290, 369, 373` & `enemies/tripmine.gd:361, 370, 402, 404`: Narrow `result.get("collider")` (`enemies/turret.gd:373`), use `NodeQuery.find_health_component()`, and replace `emit_signal` with typed `Events` signals (`enemies/tripmine.gd:402, 404`).
  - `enemies/rook_trap.gd:67, 164, 197`: Gate `_physics_process` and replace `distance_to()` with `distance_squared_to()`.
  - `weapons/signal_rocket/signal_rocket_weapon.gd:69`: Replace runtime `ResourceLoader.load(PROJECTILE_SCENE_PATH)` with `preload()`.
  - `weapons/throwable_weapon.gd:165`: Decouple from `WeaponInventoryComponent` to break 2-cycle.
- **Verification**: `gdformat --check <wave12_files> && gdlint <wave12_files>` + GUT suite.

### Wave 13: World Streaming & User Interface Panels/HUDs — Part A (19 files | `wc -l`: 6,533 | `splitlines`: 6,533)
- **Dependencies Satisfied**: Waves 1–12 (`ReferenceData`, `Types`, `FrameGraph`, `VideoConfig`, `VrsTextureGenerator`, `Utilities`).
- **Files & Exact Line Counts**:
  - `ui/ammo_hud.gd` (86), `ui/audio_panel.gd` (457), `ui/chapter_title_container.gd` (573), `ui/crosshair_hud.gd` (211), `ui/debug_overlay.gd` (291), `ui/diagnostics_panel.gd` (1829), `ui/diorama_post_process.gd` (49), `ui/display_section.gd` (291), `ui/display_ui_section.gd` (349), `ui/gameplay_panel.gd` (194), `ui/gel_stream_3d.gd` (99), `ui/hardware_section.gd` (147), `ui/magnifying_glass_ui.gd` (147), `ui/notification_hud.gd` (332), `ui/save_load_panel.gd` (138), `ui/subs_audio_section.gd` (552), `ui/vision_section.gd` (483), `ui/water_wipe_controller.gd` (214)
  - `world/chunk_root.gd` (91)
- **Specific Defects to Fix**:
  - `ui/diagnostics_panel.gd:5, 7, 229, 879, 880, 1365-1415, 1472`: Remove dead `signal metrics_updated` and `@warning_ignore`, gate `_process`, narrow `rec.get(...)` `Variant` values before `str()`, and add missing docstring at `L1472`.
  - `ui/chapter_title_container.gd:104, 108, 115, 446-565`: Disconnect `Events.chapter_triggered` and `Events.wake_up_text_requested` in `_exit_tree()` (`L115`) and pre-allocate `StringName` shader uniform keys.
  - `ui/debug_overlay.gd:136-142`, `ui/diorama_post_process.gd:23, 25`, `ui/magnifying_glass_ui.gd:42, 44`, `ui/notification_hud.gd:122-135`, `ui/subs_audio_section.gd:158-162`: Add `_exit_tree()` `Events` signal disconnections and replace string `.connect(...)`.
  - `ui/gameplay_panel.gd:160, 181`: Replace `Events.emit_signal(...)` with typed `Events.item_prompts_toggled.emit(...)` and `Events.reduce_motion_toggled.emit(...)`.
- **Verification**: `gdformat --check <wave13_files> && gdlint <wave13_files>` + GUT suite.

### Wave 14: World Streaming & User Interface Panels/HUDs — Part B (15 files | `wc -l`: 6,946 | `splitlines`: 6,946)
- **Dependencies Satisfied**: Waves 1–13 (`ChunkRoot`, `WaterWipeController`, `ReferenceData`, `Types`, `Utilities`).
- **Files & Exact Line Counts**:
  - `ui/advisor_psychic_effect.gd` (215), `ui/chunk_debug_hud.gd` (228), `ui/controls_panel.gd` (1034), `ui/controls_section.gd` (514), `ui/death_screen.gd` (695), `ui/harsh_contrast_effect.gd` (191), `ui/horror_button.gd` (670), `ui/juicy_button.gd` (94), `ui/player_status_hud.gd` (685), `ui/roar_screen_effect.gd` (81), `ui/screen_effects_manager.gd` (969), `ui/tag_notification.gd` (239), `ui/visuals_section.gd` (780)
  - `world/chunk_manager.gd` (499), `world/player_chunk_tracker.gd` (52)
- **Specific Defects to Fix**:
  - `world/chunk_manager.gd:88, 100, 164, 168, 229, 233, 298, 303, 405-406, 411, 423, 430, 497`: Replace synchronous `load(scene_path)` fallback (`L298`) and type all dictionaries/arrays.
  - `ui/controls_panel.gd:46-103, 175, 402, 417, 980-1034`: Deduplicate Kenney icon cache by delegating to `InputHelper` (removing runtime `load(p)` at `L1028`), gate `_process`, and narrow `get_meta` `Variant`.
  - `ui/screen_effects_manager.gd:152, 208, 224, 335, 492-514, 549, 580, 597, 669, 696, 736, 800, 839, 902, 924`: Disconnect all 11 remaining `Events` signals in `_exit_tree()` (`L152`) and reset tweens via `Utilities.reset_tween()`.
  - `ui/player_status_hud.gd:178, 258-270`: Disconnect all 11 remaining `Events` signals in `_exit_tree()`.
  - `ui/death_screen.gd:178, 191, 494-649`: Add `_exit_tree()` disconnect for `Events.player_died`, gate `_process`, and pre-allocate `StringName` shader uniform keys.
  - `ui/tag_notification.gd:132, 188`: Call `Utilities.reset_tween(_stack_tween)` before creating `_stack_tween`.
- **Verification**: `gdformat --check <wave14_files> && gdlint <wave14_files>` + GUT suite.

### Wave 15: Level Loaders, Options Router & Main Menu UI (16 files | `wc -l`: 6,270 | `splitlines`: 6,270)
- **Dependencies Satisfied**: Waves 1–14 (UI sections, HUDs, `VideoConfig`, `VrsTextureGenerator`).
- **Files & Exact Line Counts**:
  - `levels/procedural_blockout.gd` (789), `levels/testbed_loader.gd` (72)
  - `ui/CCTV.gd` (549), `ui/accessibility_panel.gd` (171), `ui/danny_cast_screen.gd` (170), `ui/effects_section.gd` (547), `ui/loading_screen_anim.gd` (659), `ui/main_menu.gd` (408), `ui/menu_chapter_screen.gd` (182), `ui/options_router.gd` (432), `ui/quality_section.gd` (518), `ui/ui.gd` (280), `ui/universal_setting_highlighter.gd` (526), `ui/video_applier.gd` (682), `ui/video_options_panel.gd` (153)
  - `world/test_player.gd` (132)
- **Specific Defects to Fix**:
  - `levels/testbed_loader.gd:6, 53`: Fix `DEFAULT_LOADING_SCREEN_PATH` to `"res://ui/loading_screen_anim.tscn"` and replace runtime `load()` with `preload()`.
  - `levels/procedural_blockout.gd:8, 108, 219, 282, 289, 343, 344, 401-419, 506, 507, 524, 547, 548, 577, 578`: Use `CollisionLayers` constants, replace `distance_to()` with `distance_squared_to()`, and type collections.
  - `ui/loading_screen_anim.gd:205, 228, 512, 522`: Remove `_process` `print()` statements (`L205, 228`) and decouple from `Player` / `PlayerLocomotionComponent` to break the 17-file UI/Player SCC.
  - `ui/options_router.gd:6, 278, 279`: Remove `@warning_ignore` and use `CollisionLayers.MASK_PREVIEW_DIORAMA`.
  - `ui/ui.gd:73, 85-93` & `ui/accessibility_panel.gd:111-115`: Disconnect all `Events` signals in `_exit_tree()`.
  - `ui/effects_section.gd:6, 167-514` & `ui/quality_section.gd:6, 10, 140-457`: Remove `@warning_ignore`, narrow `Variant` reads, and extract shared UI binding helper.
- **Verification**: `gdformat --check <wave15_files> && gdlint <wave15_files>` + GUT suite.

### Wave 16: Player Controller, State Machine & Locomotion Components — Part A (20 files | `wc -l`: 6,567 | `splitlines`: 6,567)
- **Dependencies Satisfied**: Waves 1–15 (`StateMachine`, `State`, `CollisionLayers`, `MathUtils`, `NodeQuery`, `Utilities`, `Types`).
- **Files & Exact Line Counts**:
  - `player/breakable_rope.gd` (315), `player/camera_3d.gd` (358), `player/camera_controller.gd` (629), `player/drunk_effect.gd` (182), `player/environment_component.gd` (355), `player/fast_rope.gd` (319), `player/flashlight_controller.gd` (171), `player/footstep_manager.gd` (323), `player/note_reader.gd` (496), `player/player_interaction_component.gd` (630), `player/player_interaction_scanner.gd` (446), `player/player_state.gd` (68), `player/player_state_machine.gd` (51), `player/procedural_revolver.gd` (388), `player/procedural_stairs_csg.gd` (266), `player/screen_vfx_manager.gd` (260), `player/state_ladders.gd` (260), `player/system_menu_controller.gd` (362), `player/vault_controller.gd` (402), `player/zipline.gd` (286)
- **Specific Defects to Fix**:
  - Break 2-cycles: `player/player_interaction_component.gd:47` <-> `player/player_interaction_scanner.gd:86` and `player/environment_component.gd:176` <-> `player/state_ladders.gd:75`.
  - Add `_exit_tree()` `Events` signal disconnects in `player/camera_3d.gd:89-101` (also replace `emit_signal` at `L87`), `player/player_interaction_component.gd:134`, `player/system_menu_controller.gd:105-108`, and `player/vault_controller.gd:90`.
  - `player/breakable_rope.gd:95, 104, 147, 171, 253, 254, 267, 268, 287, 288`: Use `CollisionLayers`, `NodeQuery.find_health_component()`, `distance_squared_to()`, and `StringName` in `set_deferred`.
  - `player/flashlight_controller.gd:98, 141`: Gate `_process` and replace `distance_to()` with `distance_squared_to()`.
- **Verification**: `gdformat --check <wave16_files> && gdlint <wave16_files>` + GUT suite.

### Wave 17: Player Controller, State Machine & Locomotion Components — Part B (23 files | `wc -l`: 6,611 | `splitlines`: 6,611)
- **Dependencies Satisfied**: Waves 1–16 (`PlayerState`, `PlayerStateMachine`, `CameraController`, `PlayerEnvironmentComponent`, `PlayerInteractionComponent`).
- **Files & Exact Line Counts**:
  - `player/StateMachineLock.gd` (50), `player/locomotion_component.gd` (424), `player/player.gd` (887), `player/push_wheel.gd` (216), `player/state_air.gd` (592), `player/state_fast_rope.gd` (56), `player/state_glide.gd` (232), `player/state_ground.gd` (374), `player/state_jib_crane.gd` (555), `player/state_monkey_bars.gd` (205), `player/state_path_slide.gd` (53), `player/state_rope.gd` (633), `player/state_slide.gd` (154), `player/state_swim.gd` (414), `player/state_terminal.gd` (55), `player/state_tube.gd` (81), `player/state_vault.gd` (52), `player/state_wolf_climb.gd` (221), `player/state_wolf_wall_run.gd` (268), `player/state_zipline.gd` (303), `player/stats_component.gd` (61), `player/weapon_inventory_component.gd` (259), `player/weapon_procedural_animator.gd` (466)
- **Specific Defects to Fix**:
  - Remove per-frame `print()` statements in all 12 `PlayerState` scripts: `player/state_fast_rope.gd:53`, `player/state_glide.gd:85`, `player/state_monkey_bars.gd:74`, `player/state_path_slide.gd:49`, `player/state_slide.gd:48`, `player/state_terminal.gd:43`, `player/state_tube.gd:74, 79`, `player/state_vault.gd:42`, `player/state_wolf_climb.gd:62`, `player/state_wolf_wall_run.gd:92`, `player/state_zipline.gd:103`.
  - Eliminate per-frame `PhysicsRayQueryParameters3D.create()` allocations in `player/state_air.gd:364`, `player/state_wolf_climb.gd:140`, and `player/state_wolf_wall_run.gd:170`.
  - `player/state_zipline.gd:68, 87, 150`: Replace `distance_to()` with `distance_squared_to()` and reset tweens via `Utilities.reset_tween()`.
  - `player/state_swim.gd:65`: Disconnect `Events.infinite_swim_toggled` in `_exit_tree()`.
  - `player/stats_component.gd:12`: Break 2-cycle with `Player` (`player/player.gd:90`).
  - `player/player.gd:6, 203-248` & `player/weapon_procedural_animator.gd:6, 10, 185, 373, 432`: Remove `@warning_ignore`, redundant `Events.has_signal()` checks, and reset tweens.
- **Verification**: `gdformat --check <wave17_files> && gdlint <wave17_files>` + GUT suite.

### Wave 18: Core Orchestration, Console Subsystems & Autoload Singletons — Part A (21 files | `wc -l`: 7,281 | `splitlines`: 7,281)
- **Dependencies Satisfied**: Waves 1–17 (all leaf helpers, domain components, UI, and player subsystems).
- **Files & Exact Line Counts**:
  - `core/KeycardSystem.gd` (44), `core/audio/sonar_manager.gd` (353), `core/audio/spatial_describer.gd` (547), `core/audio_manager.gd` (101), `core/audio_pool.gd` (131), `core/camera_shake_manager.gd` (184), `core/console/console_cheat_commands.gd` (1698), `core/console/console_context.gd` (91), `core/console/console_settings_commands.gd` (1300), `core/console/console_system_commands.gd` (449), `core/console/freecam_controller.gd` (178), `core/console_command.gd` (30), `core/console_command_registry.gd` (87), `core/console_history.gd` (56), `core/dev_metrics.gd` (451), `core/events.gd` (793), `core/interaction_manager.gd` (156), `core/shader_cache_builder.gd` (92), `core/start_screen.gd` (43), `core/tts_interact_component.gd` (63), `core/vfx/screen_effects_core.gd` (434)
- **Specific Defects to Fix**:
  - `core/events.gd:8-709, 744, 764`: Place `@warning_ignore("unused_signal")` above `##` docstrings so signal docstrings attach properly, break 2-cycle with `GlobalSettings` (`L744`), and replace runtime `load(res_path)` (`L764`).
  - `core/camera_shake_manager.gd:55-56` & `core/vfx/screen_effects_core.gd:88, 100-112, 123, 139-144`: Fix double camera trauma bug (both connect to `Events.screenshake_requested`) and add `_exit_tree()` cleanup for signals and `_shockwave_container`.
  - `core/audio/sonar_manager.gd:173-174, 177-178, 187-188, 194-197, 251` & `core/audio/spatial_describer.gd:120, 156, 188-192, 241, 289-292, 338, 396`: Narrow `dict.get()` `Variant` values, replace `distance_to()` with `distance_squared_to()`, and decouple from `PickableObject`.
  - `core/console/console_cheat_commands.gd:735, 828, 908, 961`: Replace runtime `load()` calls and narrow `ProjectSettings.get_setting()`.
  - `core/console/console_system_commands.gd:184-191` & `core/console/console_settings_commands.gd:457-466, 849-850`: Fix no-op `_cmd_uiscale` and `_cmd_mono_audio`, and fix `"Video"` vs `"Settings"` section mismatch in `_cmd_perf_uncap`.
  - `core/start_screen.gd:6`: Fix broken default scene path `"res://scenes/MainGame.tscn"`.
- **Verification**: `gdformat --check <wave18_files> && gdlint <wave18_files>` + GUT suite.

### Wave 19: Core Orchestration, Console Subsystems & Autoload Singletons — Part B (18 files | `wc -l`: 4,878 | `splitlines`: 4,878)
- **Dependencies Satisfied**: Waves 1–18 (`Events`, `AudioPool`, `AudioManager`, `KeycardSystem`, console commands, `ObjectPool`, `MaterialCache`, `Utilities`).
- **Files & Exact Line Counts**:
  - `core/gesture_input_manager.gd` (493), `core/global.gd` (91), `core/global_settings.gd` (464), `core/graphics_manager.gd` (461), `core/save_manager.gd` (385), `core/scene_transition.gd` (142), `core/spike_forensics.gd` (309)
  - `environment/DynamicFog/smoke_manager.gd` (258)
  - `ui/HighContrastManager.gd` (76), `ui/InputHelper.gd` (151), `ui/VisionAssistManager.gd` (266), `ui/debug_manager.gd` (27), `ui/in_game_console.gd` (509), `ui/subtitle_layer.gd` (410)
  - `vfx/Post_Process_Layer.gd` (134), `vfx/ShockwaveManager3D.gd` (103), `vfx/blood_manager.gd` (398), `vfx/impact_manager.gd` (201)
- **Specific Defects to Fix**:
  - `ui/HighContrastManager.gd:39`: Fix broken signal name `"high_contrast_changed"` -> typed `Events.high_contrast_toggled.connect(_on_high_contrast_toggled)`.
  - `ui/VisionAssistManager.gd:100-104, 113, 258-259` & `vfx/Post_Process_Layer.gd:65-71, 84-103, 114`: Replace string `.connect(...)` with typed `Events` connections, pre-allocate `StringName` shader uniform keys, and replace runtime `load(shader_path)` (`vfx/Post_Process_Layer.gd:114`).
  - `ui/InputHelper.gd:9, 103, 136`: Preload icon resources instead of runtime `load(full_path)` (`L103`) and type dictionaries.
  - `core/global.gd:39-40`: Disable `_process(delta)` (`set_process(false)`) and compute elapsed session time from `Time.get_ticks_msec()`.
  - `core/gesture_input_manager.gd:45-118, 335`: Gate `_process`, eliminate per-frame `Array` allocations (`L46, 101, 110`), and remove `print()` from `is_action_just_released()` (`L335`).
  - `core/global_settings.gd:229, 258, 338, 349-368` & `core/graphics_manager.gd:39, 59-69, 73-456`: Resolve boot-order inversion (`project.godot:33-34`), replace runtime `load(path)` (`core/global_settings.gd:258`), narrow `get_setting()` `Variant` returns, and decouple from `VideoApplier` / `MainMenu`.
  - `core/save_manager.gd:248-250, 292-293`: Eliminate duplicate ternary dictionary lookup and narrow `a.get("is_favorite", false)`.
  - `core/scene_transition.gd:27, 98, 133`: Type `_progress_array` and use `Utilities.reset_tween()`.
  - `environment/DynamicFog/smoke_manager.gd:19, 58, 68`: Decouple from `SmokeGrenadeCloud` to break 2-cycle.
- **Verification**: `gdformat --check <wave19_files> && gdlint <wave19_files>` + GUT suite.

---

## 3. Standard Verification Protocol Per Wave

Run the following verification commands at the end of every wave before committing:

```bash
# 1. Check formatting and lint rules on all modified .gd files in the wave
gdformat --check <wave_gd_files>
gdlint <wave_gd_files>

# 2. Run the full headless GUT unit test suite
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit -gignore_pause
```
