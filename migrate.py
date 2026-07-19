#!/usr/bin/env python3
import os
import subprocess
import sys

# [Insert your mapping dictionary here]
mapping = {
    	"assets/Godiva.glb": "shared/godiva.glb",

	"assets/Godiva_Godiva_Clothing_Base_color-Godiva_Clothing_Opacity.png": "shared/godiva_godiva_clothing_base_color_godiva_clothing_opacity.png",

	"assets/Godiva_Godiva_Clothing_Emissive.png": "shared/godiva_godiva_clothing_emissive.png",

	"assets/Godiva_Godiva_Clothing_Metallic-Godiva_Clothing_Roughness.png": "shared/godiva_godiva_clothing_metallic_godiva_clothing_roughness.png",

	"assets/Godiva_Godiva_Clothing_Normal_OpenGL.png": "shared/godiva_godiva_clothing_normal_open_gl.png",

	"assets/Godiva_Godiva_Skin_Base_color-Godiva_Skin_Opacity.png": "shared/godiva_godiva_skin_base_color_godiva_skin_opacity.png",

	"assets/Godiva_Godiva_Skin_Emissive.png": "shared/godiva_godiva_skin_emissive.png",

	"assets/Godiva_Godiva_Skin_Metallic-Godiva_Skin_Roughness.png": "shared/godiva_godiva_skin_metallic_godiva_skin_roughness.png",

	"assets/Godiva_Godiva_Skin_Normal_OpenGL.png": "shared/godiva_godiva_skin_normal_open_gl.png",

	"assets/box_clouds/box_clouds.gd": "shared/box_clouds.gd",

	"assets/box_clouds/box_clouds.gdshader": "vfx/box_clouds.gdshader",

	"assets/ocean_waves/ocean/mat_ocean.tres": "environment/mat_ocean.tres",

	"assets/ocean_waves/ocean/mat_spray.tres": "environment/mat_spray.tres",

	"assets/ocean_waves/ocean/ocean.gd": "environment/ocean.gd",

	"assets/ocean_waves/ocean/ocean_spray.png": "environment/ocean_spray.png",

	"assets/ocean_waves/ocean/wave_cascade_parameters.gd": "environment/wave_cascade_parameters.gd",

	"assets/ocean_waves/ocean/wave_generator.gd": "environment/wave_generator.gd",

	"assets/ocean_waves/ocean/waveheight_script.gd": "environment/waveheight_script.gd",

	"assets/ocean_waves/shaders/compute/downsample_compute.glsl": "environment/downsample_compute.glsl",

	"assets/ocean_waves/shaders/compute/fft_butterfly.glsl": "environment/fft_butterfly.glsl",

	"assets/ocean_waves/shaders/compute/fft_compute.glsl": "environment/fft_compute.glsl",

	"assets/ocean_waves/shaders/compute/fft_unpack.glsl": "environment/fft_unpack.glsl",

	"assets/ocean_waves/shaders/compute/spectrum_compute.glsl": "environment/spectrum_compute.glsl",

	"assets/ocean_waves/shaders/compute/spectrum_modulate.glsl": "environment/spectrum_modulate.glsl",

	"assets/ocean_waves/shaders/compute/transpose.glsl": "environment/transpose.glsl",

	"assets/ocean_waves/shaders/spatial/ocean_spray.gdshader": "environment/ocean_spray.gdshader",

	"assets/ocean_waves/shaders/spatial/ocean_spray_particle.gdshader": "environment/ocean_spray_particle.gdshader",

	"assets/ocean_waves/shaders/spatial/ocean_water.gdshader": "environment/ocean_water.gdshader",

	"assets/rain_effect/Snow005_2K_Normal.jpg": "environment/snow005_2_k_normal.jpg",

	"assets/rain_effect/cobblestone-curved_albedo.png": "environment/cobblestone_curved_albedo.png",

	"assets/rain_effect/cobblestone-curved_height.png": "environment/cobblestone_curved_height.png",

	"assets/rain_effect/cobblestone-curved_normal-ogl.png": "environment/cobblestone_curved_normal_ogl.png",

	"assets/rain_effect/cobblestone-curved_roughness.png": "environment/cobblestone_curved_roughness.png",

	"assets/rain_effect/drops512.png": "environment/drops512.png",

	"assets/rain_effect/rain_effects.tres": "environment/rain_effects.tres",

	"assets/rain_effect/raineffects.gdshader": "environment/raineffects.gdshader",

	"assets/rain_effect/ripples.png": "environment/ripples.png",

	"assets/rain_effect/ripples512.png": "environment/ripples512.png",

	"assets/rain_effect/snow_tex.jpg": "environment/snow_tex.jpg",

	"assets/rain_effect/water_droplets.png": "environment/water_droplets.png",

	"assets/rainfall/rain_alpha_mask.png": "environment/rain_alpha_mask.png",

	"assets/rainfall/rain_alpha_mask_2.jpeg": "environment/rain_alpha_mask_2.jpeg",

	"assets/rainfall/rain_droplet_normal.png": "environment/rain_droplet_normal.png",

	"assets/rainfall/rain_droplet_normal_2.png": "environment/rain_droplet_normal_2.png",

	"assets/rainfall/scenes/instance/rain_effect.tscn": "environment/rain_effect.tscn",

	"assets/rainfall/scripts/rain_particles.gd": "environment/rain_particles.gd",

	"assets/shaders/HorrorTextShader.gdshader": "vfx/horror_text_shader.gdshader",

	"assets/shaders/SmartOutlineMaterial.gdshader": "vfx/smart_outline_material.gdshader",

	"assets/shaders/SmartOutlineMaterial.tres": "vfx/smart_outline_material.tres",

	"assets/shaders/UnlitOutlineMaterial.gdshader": "vfx/unlit_outline_material.gdshader",

	"assets/shaders/ascii.gdshader": "vfx/ascii.gdshader",

	"assets/shaders/caustics_shader.gdshader": "vfx/caustics_shader.gdshader",

	"assets/shaders/censor_mosaic.gdshader": "vfx/censor_mosaic.gdshader",

	"assets/shaders/circle_shader.tres": "vfx/circle_shader.tres",

	"assets/shaders/colorblind.gdshader": "vfx/colorblind.gdshader",

	"assets/shaders/crt.gdshader": "vfx/crt.gdshader",

	"assets/shaders/gameboy.gdshader": "vfx/gameboy.gdshader",

	"assets/shaders/glitch.gdshader": "vfx/glitch.gdshader",

	"assets/shaders/grain.gdshader": "environment/grain.gdshader",

	"assets/shaders/halftone.gdshader": "vfx/halftone.gdshader",

	"assets/shaders/high_contrast.gdshader": "vfx/high_contrast.gdshader",

	"assets/shaders/holographic_scanner.gdshader": "player/holographic_scanner.gdshader",

	"assets/shaders/kuwahara.gdshader": "vfx/kuwahara.gdshader",

	"assets/shaders/mirror.gdshader": "interactables/mirror.gdshader",

	"assets/shaders/nightvision.gdshader": "vfx/nightvision.gdshader",

	"assets/shaders/oceanwave.gdshader": "environment/oceanwave.gdshader",

	"assets/shaders/outline_hearts_adaptable.gdshader": "vfx/outline_hearts_adaptable.gdshader",

	"assets/shaders/outline_shader.gdshader": "vfx/outline_shader.gdshader",

	"assets/shaders/outline_shader_adaptable.gdshader": "vfx/outline_shader_adaptable.gdshader",

	"assets/shaders/pixelate.gdshader": "vfx/pixelate.gdshader",

	"assets/shaders/projector_rain.gdshader": "environment/projector_rain.gdshader",

	"assets/shaders/rainy_window.material": "environment/rainy_window.material",

	"assets/shaders/rainy_window.material.depren": "environment/rainy_window.material.depren",

	"assets/shaders/rainy_window_normal.gdshader": "environment/rainy_window_normal.gdshader",

	"assets/shaders/rainy_window_procedural.gdshader": "environment/rainy_window_procedural.gdshader",

	"assets/shaders/toon.gdshader": "vfx/toon.gdshader",

	"assets/shaders/ui_vignette.gdshader": "ui/ui_vignette.gdshader",

	"assets/shaders/ui_zoom_fisheye_blur.gdshader": "ui/ui_zoom_fisheye_blur.gdshader",

	"assets/shaders/vhs.gdshader": "vfx/vhs.gdshader",

	"assets/shaders/water_wipe_overlay.gdshader": "environment/water_wipe_overlay.gdshader",

	"assets/shaders/waterfall.gdshader": "environment/waterfall.gdshader",

	"assets/shaders/waterfall_wipe_overlay.gdshader": "environment/waterfall_wipe_overlay.gdshader",

	"assets/shaders/wind_cable.gdshader": "interactables/wind_cable.gdshader",

	"scenes/ChapterScreen.gdshader": "ui/chapter_screen.gdshader",

	"scenes/ChapterScreen.tscn": "ui/chapter_screen.tscn",

	"scenes/DynamicOcean.tscn": "environment/dynamic_ocean.tscn",

	"scenes/HealthModifier.tscn": "shared/health_modifier.tscn",

	"scenes/Pickable_Barrel_green.tscn": "interactables/pickable_barrel_green.tscn",

	"scenes/Pickable_Barrel_red.tscn": "interactables/pickable_barrel_red.tscn",

	"scenes/Player.tscn": "player/player.tscn",

	"scenes/PuzzleSocket.tscn": "shared/puzzle_socket.tscn",

	"scenes/TESTS(delete later)/DoubleSlidingDoors.tscn": "interactables/double_sliding_doors.tscn",

	"scenes/TESTS(delete later)/double_sliding_doors.gd": "interactables/double_sliding_doors.gd",

	"scenes/TESTS(delete later)/hide_building_test.tscn": "ui/hide_building_test.tscn",

	"scenes/VFX_blood_burst.tscn": "shared/vfx_blood_burst.tscn",

	"scenes/WaterRippleOverlay.gdshader": "environment/water_ripple_overlay.gdshader",

	"scenes/barrel_red.tscn": "interactables/barrel_red.tscn",

	"scenes/basalt_generator.tscn": "shared/basalt_generator.tscn",

	"scenes/basalt_magnet.tscn": "interactables/basalt_magnet.tscn",

	"scenes/breakable_rope.tscn": "player/breakable_rope.tscn",

	"scenes/button.tscn": "shared/button.tscn",

	"scenes/cable_link.tscn": "interactables/cable_link.tscn",

	"scenes/checkpoint.tscn": "interactables/checkpoint.tscn",

	"scenes/climable_rope.tscn": "player/climable_rope.tscn",

	"scenes/danny_cast_screen.tscn": "ui/danny_cast_screen.tscn",

	"scenes/debug_pellet.tscn": "ui/debug_pellet.tscn",

	"scenes/dev_arrow.tscn": "ui/dev_arrow.tscn",

	"scenes/dev_cylinder.tscn": "shared/dev_cylinder.tscn",

	"scenes/door_interact.tscn": "interactables/door_interact.tscn",

	"scenes/door_keypad.tscn": "interactables/door_keypad.tscn",

	"scenes/door_slide.tscn": "interactables/door_slide.tscn",

	"scenes/double_cable.tscn": "interactables/double_cable.tscn",

	"scenes/draw_bridge_system.tscn": "shared/draw_bridge_system.tscn",

	"scenes/effects/dust_puff.tscn": "vfx/dust_puff.tscn",

	"scenes/effects/fluid_gel/gel.gdshader": "ui/gel.gdshader",

	"scenes/effects/fluid_gel/gel_stream_3d.gd": "ui/gel_stream_3d.gd",

	"scenes/effects/jelly_gel/emitter.gd": "vfx/emitter.gd",

	"scenes/effects/jelly_gel/emitter.tscn": "vfx/emitter.tscn",

	"scenes/effects/jelly_gel/jelly.gdshader": "vfx/jelly.gdshader",

	"scenes/effects/jelly_gel/particle.gd": "vfx/particle.gd",

	"scenes/effects/jelly_gel/particle.tscn": "vfx/particle.tscn",

	"scenes/effects/jelly_gel/splat.gdshader": "vfx/splat.gdshader",

	"scenes/effects/rain_viewport.tscn": "environment/rain_viewport.tscn",

	"scenes/effects/smoke_wake_collider.gd": "vfx/smoke_wake_collider.gd",

	"scenes/effects/water_wipe_overlay.gd": "environment/water_wipe_overlay.gd",

	"scenes/enemy_TEST.tscn": "shared/enemy_test.tscn",

	"scenes/fade_trigger.tscn": "shared/fade_trigger.tscn",

	"scenes/fast_rope.tscn": "player/fast_rope.tscn",

	"scenes/fps_counter.tscn": "shared/fps_counter.tscn",

	"scenes/gate.gd": "interactables/gate.gd",

	"scenes/gate.tscn": "interactables/gate.tscn",

	"scenes/ground_button.tscn": "shared/ground_button.tscn",

	"scenes/heavy_pickable_box.tscn": "interactables/heavy_pickable_box.tscn",

	"scenes/keypad.tscn": "shared/keypad.tscn",

	"scenes/killfield.tscn": "shared/killfield.tscn",

	"scenes/ladder.tscn": "interactables/ladder.tscn",

	"scenes/levels/VisTEST.tscn": "shared/vis_test.tscn",

	"scenes/levels/VisTEST_proper.tscn": "player/vis_test_proper.tscn",

	"scenes/levels/testbed.scn": "shared/testbed.scn",

	"scenes/levels/testbed.scn.depren": "shared/testbed.scn.depren",

	"scenes/levels/testbed.tscn": "shared/testbed.tscn",

	"scenes/light_logic.tscn": "environment/light_logic.tscn",

	"scenes/loading_screen_DELETE?.tscn": "ui/loading_screen_delete.tscn",

	"scenes/loading_screen_anim.tscn": "ui/loading_screen_anim.tscn",

	"scenes/menus/BorderGlow.gdshader": "ui/border_glow.gdshader",

	"scenes/menus/black_glass.gdshader": "ui/black_glass.gdshader",

	"scenes/menus/main_menu.tscn": "ui/main_menu.tscn",

	"scenes/mirror.tscn": "interactables/mirror.tscn",

	"scenes/monke_bar.tscn": "shared/monke_bar.tscn",

	"scenes/object_interact.tscn": "interactables/object_interact.tscn",

	"scenes/phys_explosion_3d.tscn": "vfx/phys_explosion_3d.tscn",

	"scenes/physics_cable_3d.tscn": "interactables/physics_cable_3d.tscn",

	"scenes/pickable_box.gd": "interactables/pickable_box.gd",

	"scenes/pickable_box.tscn": "interactables/pickable_box.tscn",

	"scenes/pickable_object.tscn": "interactables/pickable_object.tscn",

	"scenes/pickable_valve.tscn": "interactables/pickable_valve.tscn",

	"scenes/save_slot.tscn": "core/save_slot.tscn",

	"scenes/soundscape_zone.tscn": "shared/soundscape_zone.tscn",

	"scenes/soundscapes/sounscape_cave.tres": "shared/sounscape_cave.tres",

	"scenes/soundscapes/sounscape_street_day_busy.tres": "shared/sounscape_street_day_busy.tres",

	"scenes/teleport.tscn": "shared/teleport.tscn",

	"scenes/teleport_destination.tscn": "shared/teleport_destination.tscn",

	"scenes/trigger_look.tscn": "shared/trigger_look.tscn",

	"scenes/tv_screen_scene.tscn": "ui/tv_screen_scene.tscn",

	"scenes/ui.tscn": "ui/ui.tscn",

	"scenes/updraft_volume.tscn": "shared/updraft_volume.tscn",

	"scenes/valve.tscn": "interactables/valve.tscn",

	"scenes/ventilator.tscn": "shared/ventilator.tscn",

	"scenes/vfx_smoke_flipbook.tscn": "vfx/vfx_smoke_flipbook.tscn",

	"scenes/water_cube_TEST.tscn": "environment/water_cube_test.tscn",

	"scenes/zipline.tscn": "player/zipline.tscn",

	"scripts/DevMetrics.gd": "core/dev_metrics.gd",

	"scripts/HealthComponent.gd": "shared/health_component.gd",

	"scripts/HealthModifier.gd": "shared/health_modifier.gd",

	"scripts/InGameConsole.gd": "ui/in_game_console.gd",

	"scripts/InteractBodyTEST.gd": "interactables/interact_body_test.gd",

	"scripts/InteractComponent.gd": "interactables/interact_component.gd",

	"scripts/PhysicsCable3D.gd": "interactables/physics_cable3_d.gd",

	"scripts/Player.gd": "player/player.gd",

	"scripts/ProceduralSpiralStairsCSG.gd": "player/procedural_spiral_stairs_csg.gd",

	"scripts/ProceduralStairsCSG.gd": "player/procedural_stairs_csg.gd",

	"scripts/PuzzleSocket.gd": "shared/puzzle_socket.gd",

	"scripts/SaveManager.gd": "core/save_manager.gd",

	"scripts/TetheredPlug.gd": "shared/tethered_plug.gd",

	"scripts/basalt_generator.gd": "shared/basalt_generator.gd",

	"scripts/basalt_magnet.gd": "interactables/basalt_magnet.gd",

	"scripts/breakable_rope.gd": "player/breakable_rope.gd",

	"scripts/button.gd": "shared/button.gd",

	"scripts/cable_builder.gd": "interactables/cable_builder.gd",

	"scripts/cable_point_3d.gd": "interactables/cable_point_3d.gd",

	"scripts/checkpoint.gd": "interactables/checkpoint.gd",

	"scripts/climable_rope.gd": "player/climable_rope.gd",

	"scripts/cloth.gd": "shared/cloth.gd",

	"scripts/danny_cast_screen.gd": "ui/danny_cast_screen.gd",

	"scripts/debug_manager.gd": "ui/debug_manager.gd",

	"scripts/dev_cylinder.gd": "shared/dev_cylinder.gd",

	"scripts/dev_hologram_tool.gd": "shared/dev_hologram_tool.gd",

	"scripts/door_interact.gd": "interactables/door_interact.gd",

	"scripts/door_keypad.gd": "interactables/door_keypad.gd",

	"scripts/door_slide.gd": "interactables/door_slide.gd",

	"scripts/drawbridge.gd": "shared/drawbridge.gd",

	"scripts/enemy_TEST.gd": "shared/enemy_test.gd",

	"scripts/events.gd": "shared/events.gd",

	"scripts/fade_trigger.gd": "shared/fade_trigger.gd",

	"scripts/fast_rope.gd": "player/fast_rope.gd",

	"scripts/fps_counter.gd": "shared/fps_counter.gd",

	"scripts/frame_graph.gd": "core/frame_graph.gd",

	"scripts/fuzzer.gd": "core/fuzzer.gd",

	"scripts/ground_button.gd": "shared/ground_button.gd",

	"scripts/heavy_pickable_box.gd": "interactables/heavy_pickable_box.gd",

	"scripts/highlight_component.gd": "environment/highlight_component.gd",

	"scripts/keypad.gd": "shared/keypad.gd",

	"scripts/killfield.gd": "shared/killfield.gd",

	"scripts/ladder.gd": "interactables/ladder.gd",

	"scripts/light_logic.gd": "environment/light_logic.gd",

	"scripts/loading_screen.gd": "ui/loading_screen.gd",

	"scripts/loading_screen_anim.gd": "ui/loading_screen_anim.gd",

	"scripts/menus/HorrorButton.gd": "ui/horror_button.gd",

	"scripts/menus/JuicyButton.gd": "ui/juicy_button.gd",

	"scripts/menus/chapter_data.gd": "ui/chapter_data.gd",

	"scripts/menus/chapter_screen.gd": "ui/chapter_screen.gd",

	"scripts/menus/fullscreen_control.gd": "ui/fullscreen_control.gd",

	"scripts/menus/main_menu.gd": "ui/main_menu.gd",

	"scripts/mirror.gd": "interactables/mirror.gd",

	"scripts/phys_explosion_3d.gd": "vfx/phys_explosion_3d.gd",

	"scripts/pickable_object.gd": "interactables/pickable_object.gd",

	"scripts/pickable_valve.gd": "interactables/pickable_valve.gd",

	"scripts/player_components/PlayerState.gd": "player/player_state.gd",

	"scripts/player_components/PlayerStateMachine.gd": "player/player_state_machine.gd",

	"scripts/player_components/Player_OLD.gd": "player/player_old.gd",

	"scripts/player_components/Player_OLD.tscn": "player/player_old.tscn",

	"scripts/player_components/StateAir.gd": "player/state_air.gd",

	"scripts/player_components/StateFastRope.gd": "player/state_fast_rope.gd",

	"scripts/player_components/StateGround.gd": "player/state_ground.gd",

	"scripts/player_components/StateLadders.gd": "player/state_ladders.gd",

	"scripts/player_components/StateMonkeyBars.gd": "player/state_monkey_bars.gd",

	"scripts/player_components/StateRope.gd": "player/state_rope.gd",

	"scripts/player_components/StateSwim.gd": "player/state_swim.gd",

	"scripts/player_components/StateVault.gd": "player/state_vault.gd",

	"scripts/player_components/StateZipline.gd": "player/state_zipline.gd",

	"scripts/player_components/SystemMenuController.gd": "player/system_menu_controller.gd",

	"scripts/player_components/camera_controller.gd": "player/camera_controller.gd",

	"scripts/player_components/flashlight_controller.gd": "player/flashlight_controller.gd",

	"scripts/player_components/footstep_manager.gd": "player/footstep_manager.gd",

	"scripts/player_components/interaction_scanner.gd": "player/interaction_scanner.gd",

	"scripts/player_components/physics_pusher.gd": "player/physics_pusher.gd",

	"scripts/player_components/screen_vfx_manager.gd": "player/screen_vfx_manager.gd",

	"scripts/player_components/stair_controller.gd": "player/stair_controller.gd",

	"scripts/player_components/vault_controller.gd": "player/vault_controller.gd",

	"scripts/powered_object.gd": "shared/powered_object.gd",

	"scripts/procedural_fence_CSG.gd": "shared/procedural_fence_csg.gd",

	"scripts/procedural_ladder.gd": "interactables/procedural_ladder.gd",

	"scripts/procedural_monkey_bars.gd": "shared/procedural_monkey_bars.gd",

	"scripts/pulley_controller.gd": "shared/pulley_controller.gd",

	"scripts/render_context.gd": "shared/render_context.gd",

	"scripts/rotator_component.gd": "shared/rotator_component.gd",

	"scripts/save_slot.gd": "core/save_slot.gd",

	"scripts/save_system.gd": "core/save_system.gd",

	"scripts/shader_scripts/rain.gd": "environment/rain.gd",

	"scripts/smoke_simulation/SmokeManager.gd": "vfx/smoke_manager.gd",

	"scripts/smoke_simulation/SmokeSimulation.gd": "vfx/smoke_simulation.gd",

	"scripts/smoke_simulation/smoke_compute.glsl": "vfx/smoke_compute.glsl",

	"scripts/smoke_simulation/smoke_noise_3d.tres": "vfx/smoke_noise_3d.tres",

	"scripts/soundscape_data.gd": "shared/soundscape_data.gd",

	"scripts/soundscape_zone.gd": "shared/soundscape_zone.gd",

	"scripts/static_cable.gd": "interactables/static_cable.gd",

	"scripts/teleport.gd": "shared/teleport.gd",

	"scripts/trigger_look.gd": "shared/trigger_look.gd",

	"scripts/trigger_scripts/lvl_instance_hide_building.gd": "ui/lvl_instance_hide_building.gd",

	"scripts/trigger_scripts/spotlight_seq_trigger.gd": "environment/spotlight_seq_trigger.gd",

	"scripts/tv_screen_scene.gd": "ui/tv_screen_scene.gd",

	"scripts/ui.gd": "ui/ui.gd",

	"scripts/universal_cable_3d.gd": "interactables/universal_cable_3d.gd",

	"scripts/updraft_volume.gd": "shared/updraft_volume.gd",

	"scripts/valve.gd": "interactables/valve.gd",

	"scripts/water_cube_TEST.gd": "environment/water_cube_test.gd",

	"scripts/waterfall.gd": "environment/waterfall.gd",

	"scripts/weapons/debug_pellet.gd": "ui/debug_pellet.gd",

	"scripts/weapons/dust_puff.gd": "shared/dust_puff.gd",

	"scripts/weapons/shotgun.gd": "shared/shotgun.gd",

	"scripts/world_environment.gd": "shared/world_environment.gd",

	"scripts/zipline.gd": "player/zipline.gd",

	"utils/WaterMaker3D/DEPRECATED_CameraWaterOverlay.gdshader": "environment/deprecated_camera_water_overlay.gdshader",

	"utils/WaterMaker3D/DEPRECATED_CameraWaterOverlay2.gdshader": "environment/deprecated_camera_water_overlay2.gdshader",

	"utils/WaterMaker3D/FogFade.gdshader": "environment/fog_fade.gdshader",

	"utils/WaterMaker3D/FogVolumeFadeScript.gd": "environment/fog_volume_fade_script.gd",

	"utils/WaterMaker3D/WaterMaker3D.gd": "environment/water_maker3_d.gd",

	"utils/WaterMaker3D/WaterMaker3D.gdshader": "environment/water_maker3_d.gdshader",

	"utils/WaterMaker3D/WaterMaker3D.tscn": "environment/water_maker3_d.tscn", 
}

def verify_environment():
    print("Verifying environment and checking for project.godot...")
    if not os.path.exists("project.godot"):
        print("Error: Please run this script from the root of your Godot project (where project.godot is located).")
        sys.exit(1)

def create_target_directories(file_mapping):
    print("Creating target directories for the new structure...")
    features = set([os.path.dirname(v) for v in file_mapping.values()])
    for feature in features:
        os.makedirs(feature, exist_ok=True)

def perform_git_moves(file_mapping):
    print("Moving files via git mv...")
    moved_files = []
    for old_path, new_path in file_mapping.items():
        if not os.path.exists(old_path):
            continue
        try:
            # Move the core file
            subprocess.run(['git', 'mv', old_path, new_path], check=True, capture_output=True)
            moved_files.append((old_path, new_path))
            
            # Handle Godot metadata files gracefully
            for ext in ['.uid', '.import']:
                meta_old = old_path + ext
                if os.path.exists(meta_old):
                    subprocess.run(['git', 'mv', meta_old, new_path + ext], check=True, capture_output=True)
                    
        except subprocess.CalledProcessError as e:
            print(f"Error moving {old_path} to {new_path}: {e.stderr.decode()}")
            
    print(f"Successfully moved {len(moved_files)} files.")
    return moved_files

def update_resource_references(file_mapping):
    print("Updating internal paths in .tscn, .tres, and .gd files...")
    search_exts = {'.tscn', '.tres', '.gd'}
    sorted_mapping = sorted(file_mapping.items(), key=lambda x: len(x[0]), reverse=True)
    updates_made = 0
    
    for root, _, fs in os.walk('.'):
        if '.git' in root or 'addons' in root:
            continue
        for f in fs:
            if any(f.endswith(ext) for ext in search_exts):
                file_path = os.path.join(root, f)
                
                try:
                    with open(file_path, 'r', encoding='utf-8') as file:
                        content = file.read()
                except UnicodeDecodeError:
                    continue
                    
                original_content = content
                
                for old_p, new_p in sorted_mapping:
                    # Clean paths and check if they exist before replacing
                    old_res = f"res://{old_p.lstrip('./').replace('\\', '/')}"
                    if old_res in content:
                        new_res = f"res://{new_p.lstrip('./').replace('\\', '/')}"
                        content = content.replace(old_res, new_res)
                        
                if content != original_content:
                    with open(file_path, 'w', encoding='utf-8') as file:
                        file.write(content)
                    updates_made += 1
                    
    print(f"Updated references in {updates_made} files.")

def apply_hardcoded_patches():
    print("Applying hardcoded miss patches...")
    patches = [
        ('shared/testbed.tscn', 'res://scenes/world_environment.tscn', 'res://shared/world_environment.tscn'),
        ('shared/testbed.tscn', 'res://scenes/plug_and_cable.tscn', 'res://interactables/plug_and_cable.tscn'),
        ('shared/monke_bar.tscn', 'res://scripts/monke_bar.gd', 'res://shared/monke_bar.gd'),
        ('vfx/smoke_compute.glsl.import', 'res://scripts/smoke_simulation/smoke_compute.glsl', 'res://vfx/smoke_compute.glsl')
    ]
    
    for file_path, old_str, new_str in patches:
        if not os.path.exists(file_path):
            continue
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            if old_str in content:
                content = content.replace(old_str, new_str)
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
        except Exception as e:
            print(f"Failed to patch {file_path}: {e}")

def clean_empty_directories(base_path='.'):
    print("Cleaning up old empty directories...")
    for dirpath, dirnames, _ in os.walk(base_path, topdown=False):
        if '.git' in dirpath or 'addons' in dirpath:
            continue
        for dirname in dirnames:
            full_path = os.path.join(dirpath, dirname)
            if not os.listdir(full_path):
                try:
                    os.rmdir(full_path)
                except OSError:
                    pass

def main():
    print("Starting BellaSDK folder migration...")
    verify_environment()
    create_target_directories(mapping)
    perform_git_moves(mapping)
    update_resource_references(mapping)
    apply_hardcoded_patches()
    clean_empty_directories()
    print("Migration complete! You can now verify the WIP node in GitKraken, then stage and commit.")

if __name__ == "__main__":
    main()
