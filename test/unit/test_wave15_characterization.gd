## Characterization tests locking Wave 15 public APIs, constants, signals, and behavior.
class_name TestWave15Characterization
extends GutTest

const CCTV_SCENE: PackedScene = preload("res://ui/CCTV.tscn")
const ACCESSIBILITY_PANEL_SCENE: PackedScene = preload("res://ui/accessibility_panel.tscn")
const DANNY_CAST_SCENE: PackedScene = preload("res://ui/danny_cast_screen.tscn")
const LOADING_SCREEN_SCENE: PackedScene = preload("res://ui/loading_screen_anim.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://ui/main_menu.tscn")
const CHAPTER_SCREEN_SCENE: PackedScene = preload("res://ui/menu_chapter_screen.tscn")
const UI_SCENE: PackedScene = preload("res://ui/ui.tscn")
const VIDEO_OPTIONS_SCENE: PackedScene = preload("res://ui/video_options_panel.tscn")


## Verifies [ProceduralBlockout] enums, exports, signal, and grid coordinate helpers.
func test_procedural_blockout_contracts() -> void:
	assert_eq(ProceduralBlockout.CellType.EMPTY, 0)
	assert_eq(ProceduralBlockout.CellType.ROOM, 1)
	assert_eq(ProceduralBlockout.CellType.CORRIDOR, 2)
	assert_eq(ProceduralBlockout.CellType.STAIRS, 3)
	assert_eq(ProceduralBlockout.CellType.WALL, 4)
	assert_eq(ProceduralBlockout.CellType.LANDING_PAD, 5)
	assert_eq(ProceduralBlockout.CellType.CROUCH_DUCT, 6)
	assert_eq(ProceduralBlockout.CellType.VAULT_OBSTACLE, 7)

	assert_eq(ProceduralBlockout.RoomShape.RECTANGLE, 0)
	assert_eq(ProceduralBlockout.RoomShape.L_SHAPE, 1)
	assert_eq(ProceduralBlockout.RoomShape.T_SHAPE, 2)
	assert_eq(ProceduralBlockout.RoomShape.CROSS, 3)
	assert_eq(ProceduralBlockout.RoomShape.RADIAL, 4)

	var blockout: ProceduralBlockout = ProceduralBlockout.new()
	add_child_autofree(blockout)

	assert_true(blockout.has_signal(&"generation_completed"))
	assert_eq(blockout.room_tile_id, 0)
	assert_eq(blockout.corridor_tile_id, 1)
	assert_eq(blockout.wall_tile_id, 3)
	assert_eq(blockout.floor_count, 3)
	assert_eq(blockout.floor_height_cells, 3)
	assert_eq(blockout.wall_height, 3)
	assert_eq(blockout.floor_size, Vector2i(48, 48))
	assert_eq(blockout.rooms_per_floor, 6)
	assert_eq(blockout.min_room_size, 4)
	assert_eq(blockout.max_room_size, 10)
	assert_almost_eq(blockout.cell_size, 2.0, 0.001)
	assert_eq(blockout.stair_length_cells, 3)
	assert_true(blockout.enable_roofs_and_ceilings)
	assert_almost_eq(blockout.radial_room_ratio, 0.25, 0.001)
	assert_true(blockout.enable_nested_rooms)
	assert_true(blockout.enable_fenestration)
	assert_true(blockout.enable_parkour_elements)
	assert_almost_eq(blockout.sprint_jump_max_distance, 6.0, 0.001)
	assert_almost_eq(blockout.crouch_clearance_height, 1.1, 0.001)
	assert_almost_eq(blockout.vault_obstacle_height, 1.0, 0.001)

	assert_eq(blockout.get_cell(Vector3i(99, 99, 99)), ProceduralBlockout.CellType.EMPTY)
	assert_eq(blockout.grid_to_world(Vector3i(2, 1, 3)), Vector3(4.0, 2.0, 6.0))


## Verifies [DevTestbedLoader] constants, export defaults, and launch method contract.
func test_dev_testbed_loader_contracts() -> void:
	assert_true(DevTestbedLoader.DEFAULT_LOADING_SCREEN_PATH is String)
	assert_false(DevTestbedLoader.DEFAULT_LOADING_SCREEN_PATH.is_empty())

	var loader: DevTestbedLoader = DevTestbedLoader.new()
	loader.auto_launch_in_debug = false
	add_child_autofree(loader)

	assert_eq(loader.testbed_path, "res://levels/testbed.tscn")
	assert_true(loader.bypass_loading_screen)
	assert_eq(loader.quick_load_key, KEY_F1)
	assert_true(loader.has_method(&"launch_testbed"))


## Verifies [CCTV] export defaults and scene resource availability.
func test_cctv_contracts() -> void:
	assert_not_null(CCTV_SCENE)
	var cctv: CCTV = CCTV.new()
	assert_not_null(cctv)
	assert_almost_eq(cctv.pan_speed, 60.0, 0.001)
	assert_almost_eq(cctv.zoom_speed, 5.0, 0.001)
	assert_almost_eq(cctv.min_fov, 30.0, 0.001)
	assert_almost_eq(cctv.max_fov, 75.0, 0.001)
	assert_true(cctv.replace_player_camera)
	assert_true(cctv.disable_global_volumetrics)
	assert_almost_eq(cctv.cctv_fps, 15.0, 0.001)
	assert_almost_eq(cctv.idle_fps, 2.0, 0.001)
	assert_almost_eq(cctv.idle_update_distance, 8.0, 0.001)
	assert_eq(cctv.internal_resolution, Vector2i(640, 360))
	assert_almost_eq(cctv.camera_far_distance, 100.0, 0.001)
	cctv.free()


## Verifies [AccessibilityPanel] scene initialization, event bus sync, and tab routing.
func test_accessibility_panel_contracts() -> void:
	var panel: AccessibilityPanel = ACCESSIBILITY_PANEL_SCENE.instantiate() as AccessibilityPanel
	assert_not_null(panel)
	add_child_autofree(panel)

	assert_true(panel.visible)
	assert_true(Events.colorblind_mode_changed.is_connected(panel._on_external_colorblind_changed))
	assert_true(Events.high_contrast_toggled.is_connected(panel._on_external_high_contrast_changed))
	assert_true(
		Events.photosensitivity_mode_toggled.is_connected(
			panel._on_external_photosensitivity_changed
		)
	)
	assert_true(Events.vision_assist_toggled.is_connected(panel._on_external_vision_assist_changed))
	assert_true(Events.font_scale_changed.is_connected(panel._on_font_scale_changed))

	panel._on_tab_changed(0)
	panel._on_external_colorblind_changed(0)
	panel._on_external_high_contrast_changed(false)
	panel._on_external_photosensitivity_changed(false)
	panel._on_external_vision_assist_changed(false)


## Verifies [DannyCastScreen] scene instantiation, exports, and physics gating.
func test_danny_cast_screen_contracts() -> void:
	var screen: DannyCastScreen = DANNY_CAST_SCENE.instantiate() as DannyCastScreen
	assert_not_null(screen)
	add_child_autofree(screen)

	assert_true(screen.auto_play)
	assert_almost_eq(screen.max_view_distance, 10.0, 0.001)
	assert_not_null(screen.video_player)
	assert_not_null(screen.viewport)
	assert_not_null(screen.monitor_mesh)
	assert_not_null(screen.visibility_notifier)

	screen.stop_video()
	assert_false(screen.is_physics_processing())
	screen.play_video()
	assert_true(screen.is_physics_processing())
	screen.stop_video()
	assert_false(screen.is_physics_processing())


## Verifies [EffectsSection], [QualitySection], and [VideoOptions] contracts.
func test_video_options_and_sections_contracts() -> void:
	assert_eq(EffectsSection.VALID_EFFECT_TIERS, ["Off", "Low", "Medium", "High"])

	var video_opts: VideoOptions = VIDEO_OPTIONS_SCENE.instantiate() as VideoOptions
	assert_not_null(video_opts)
	add_child_autofree(video_opts)

	assert_false(video_opts.is_processing())
	assert_false(video_opts.is_physics_processing())
	assert_not_null(video_opts.display_section)
	assert_not_null(video_opts.quality_section)
	assert_not_null(video_opts.effects_section)
	assert_not_null(video_opts.hardware_section)
	assert_not_null(video_opts.restart_dialog)
	assert_not_null(video_opts.diorama_socket)

	assert_true(video_opts.effects_section.has_signal(&"effects_settings_changed"))
	assert_true(video_opts.quality_section.has_signal(&"preset_changed"))
	assert_true(video_opts.quality_section.has_signal(&"quality_settings_changed"))

	video_opts._on_panel_resized()
	video_opts.quality_section.load_settings()
	video_opts.effects_section.load_settings()


## Verifies [LoadingScreen] constants and scene availability.
func test_loading_screen_contracts() -> void:
	assert_not_null(LOADING_SCREEN_SCENE)
	assert_eq(LoadingScreen.WARMUP_POOL_SIZE, 4)
	assert_almost_eq(LoadingScreen.WARMUP_FRAME_BUDGET_SEC, 0.018, 0.0001)
	assert_eq(LoadingScreen.SETTLING_FRAMES, 4)
	assert_almost_eq(LoadingScreen.FILL_RATE_MAX, 75.0, 0.001)
	assert_almost_eq(LoadingScreen.SMOOTHING_SPEED, 6.0, 0.001)
	assert_almost_eq(LoadingScreen.MIN_FILL_RATE, 12.0, 0.001)
	assert_almost_eq(LoadingScreen.ANIM_FPS, 24.0, 0.001)
	assert_eq(LoadingScreen.TOTAL_ANIM_FRAMES, 120)
	assert_eq(LoadingScreen.ANIM_BELLA_WRENCH, &"bella_wrench")
	assert_eq(LoadingScreen.ANIM_PRIESTESS_TWOFACE, &"priestess_twoface")
	assert_eq(LoadingScreen.METHOD_ACTIVATE_CAMERA, &"activate_gameplay_camera")
	assert_eq(LoadingScreen.PROP_LOCOMOTION, &"locomotion_component")
	assert_eq(LoadingScreen.PROP_CAMERA_CONTROLLER, &"camera_controller")


## Verifies [MainMenu] constants and scene resource contract.
func test_main_menu_contracts() -> void:
	assert_not_null(MAIN_MENU_SCENE)
	assert_almost_eq(MainMenu.DEFAULT_SENSITIVITY, 0.5, 0.001)
	assert_not_null(MainMenu.CHAPTER_SCREEN)
	assert_not_null(MainMenu.LOADING_SCREEN_SCENE)

	var menu: MainMenu = MainMenu.new()
	assert_true(menu.has_method(&"prepare_for_level_transition"))
	menu.free()


## Verifies [ChapterScreen] scene initialization and static active instance lifecycle.
func test_chapter_screen_contracts() -> void:
	assert_not_null(ChapterScreen.LOADING_SCREEN_SCENE)
	var screen: ChapterScreen = CHAPTER_SCREEN_SCENE.instantiate() as ChapterScreen
	assert_not_null(screen)
	add_child(screen)

	assert_eq(ChapterScreen.active_instance, screen)
	assert_not_null(screen.chapter_list)
	assert_not_null(screen.play_button)
	assert_not_null(screen.back_button)

	remove_child(screen)
	screen.free()
	assert_null(ChapterScreen.active_instance)


## Verifies [OptionsRouter] signals, scene preload, and tab management API.
func test_options_router_contracts() -> void:
	assert_not_null(OptionsRouter.SETTINGS_LEVEL_SCENE)
	var router: OptionsRouter = OptionsRouter.new()
	assert_true(router.has_signal(&"back_requested"))
	assert_eq(router.get_all_panels().size(), 5)
	assert_eq(router.get_all_tab_buttons().size(), 5)
	router.select_tab_by_index(-1)
	router.teardown_diorama()
	router.free()


## Verifies [UIController] constants, scene initialization, and initial panel states.
func test_ui_controller_contracts() -> void:
	assert_eq(UIController.ACTION_DEBUG_METRICS, &"debug_toggle_metrics")
	assert_eq(UIController.ACTION_DEBUG_UI, &"debug_toggle_ui")
	assert_eq(UIController.ACTION_DEBUG_DIAGNOSTICS, &"debug_toggle_diagnostics")
	assert_eq(UIController.ACTION_CONSOLE, &"console")
	assert_eq(UIController.ACTION_DEBUG_MENU, &"debug_menu")

	var ui_ctrl: UIController = UI_SCENE.instantiate() as UIController
	assert_not_null(ui_ctrl)
	add_child_autofree(ui_ctrl)

	assert_false(ui_ctrl.is_ui_hidden)
	assert_not_null(ui_ctrl.screen_effects)
	assert_not_null(ui_ctrl.crosshair_hud)
	assert_not_null(ui_ctrl.player_status_hud)
	assert_not_null(ui_ctrl.notification_hud)
	if is_instance_valid(ui_ctrl.metrics_panel):
		assert_false(ui_ctrl.metrics_panel.visible)
	if is_instance_valid(ui_ctrl.frame_graph):
		assert_false(ui_ctrl.frame_graph.visible)


## Verifies [UniversalSettingHighlighter] constants, signals, and row highlight cycle.
func test_universal_setting_highlighter_contracts() -> void:
	assert_eq(UniversalSettingHighlighter.DEFAULT_PADDING, Vector2(8.0, 5.0))
	assert_eq(UniversalSettingHighlighter.HIGHLIGHTER_HOVER_SCALE, Vector2(1.0, 1.06))
	assert_eq(UniversalSettingHighlighter.HIGHLIGHTER_Z_INDEX, 0)
	assert_eq(UniversalSettingHighlighter.ELEVATED_ROW_Z_INDEX, 2)
	assert_eq(UniversalSettingHighlighter.PARAM_RECT_SIZE, &"rect_size")
	assert_eq(UniversalSettingHighlighter.PARAM_MOUSE_POS, &"mouse_pos")
	assert_eq(UniversalSettingHighlighter.PARAM_HOVER_INTENSITY, &"hover_intensity")
	assert_true(UniversalSettingHighlighter.TAB_TITLE_OVERRIDES.size() > 0)

	var host: Control = Control.new()
	add_child_autofree(host)
	var highlighter: UniversalSettingHighlighter = UniversalSettingHighlighter.new()
	highlighter.material = ShaderMaterial.new()
	host.add_child(highlighter)

	assert_true(highlighter.has_signal(&"row_highlighted"))
	assert_true(highlighter.has_signal(&"highlight_cleared"))
	assert_eq(highlighter.padding, Vector2(8.0, 5.0))
	assert_almost_eq(highlighter.transition_duration, 0.14, 0.001)

	var row_btn: Button = Button.new()
	row_btn.size = Vector2(120.0, 32.0)
	host.add_child(row_btn)
	highlighter.register_panel(host)

	var controls: Array[Control] = [row_btn]
	highlighter.highlight_row(controls)
	assert_eq(row_btn.z_index, UniversalSettingHighlighter.ELEVATED_ROW_Z_INDEX)
	highlighter.clear_highlight()
	assert_eq(row_btn.z_index, 0)


## Verifies [VideoApplier] constants and static environment/light/camera helpers.
func test_video_applier_contracts() -> void:
	assert_eq(VideoApplier.DIORAMA_SIZE, Vector2i(640, 480))
	assert_eq(VideoApplier.DIORAMA_SHADOW_ATLAS_SIZE, 1024)
	assert_eq(VideoApplier.DIORAMA_FOG_DEPTH, 64)

	var vrs_supported: bool = VideoApplier.is_vrs_supported()
	assert_true(vrs_supported is bool)

	var cam: Camera3D = Camera3D.new()
	cam.add_to_group(&"ignore_global_video_settings")
	add_child_autofree(cam)
	assert_false(VideoApplier.is_player_camera(cam))
	VideoApplier.apply_to_camera(cam, {"dof_enabled": true, "dof_amount": 0.5}, false)
	var cam_attr: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
	assert_not_null(cam_attr)
	assert_true(cam_attr.dof_blur_far_enabled)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	add_child_autofree(light)
	VideoApplier.apply_to_light(light, {"shadow_quality": "High"}, false)
	assert_true(light.shadow_enabled)

	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = Environment.new()
	add_child_autofree(world_env)
	VideoApplier.apply_to_world_environment(world_env, {"ssao": "Off", "exposure": 1.25})
	assert_false(world_env.environment.ssao_enabled)
	assert_almost_eq(world_env.environment.tonemap_exposure, 1.25, 0.001)


## Verifies [TestPlayer] constants, layer setup, and process gating.
func test_test_player_contracts() -> void:
	assert_almost_eq(TestPlayer.SPEED_NORMAL, 15.0, 0.001)
	assert_almost_eq(TestPlayer.SPEED_BOOST, 80.0, 0.001)
	assert_almost_eq(TestPlayer.INTERACT_RADIUS_SQ, 2500.0, 0.001)
	assert_almost_eq(TestPlayer.ROAMER_DISPLACE_X, 300.0, 0.001)
	assert_almost_eq(TestPlayer.CHUNK_SIZE, 250.0, 0.001)
	assert_eq(TestPlayer.INPUT_LEFT, &"ui_left")
	assert_eq(TestPlayer.INPUT_RIGHT, &"ui_right")
	assert_eq(TestPlayer.INPUT_UP, &"ui_up")
	assert_eq(TestPlayer.INPUT_DOWN, &"ui_down")
	assert_eq(TestPlayer.GROUP_CRATE, &"test_crate")
	assert_eq(TestPlayer.DELTA_FREED, &"freed")

	var container: Node3D = Node3D.new()
	add_child_autofree(container)
	var player: TestPlayer = TestPlayer.new()
	player.dynamic_container = container
	var tracker: PlayerChunkTracker = PlayerChunkTracker.new()
	tracker.name = "PlayerChunkTracker"
	var poll_timer: Timer = Timer.new()
	poll_timer.name = "PollTimer"
	tracker.add_child(poll_timer)
	player.add_child(tracker)
	add_child_autofree(player)

	assert_false(player.is_processing())
	assert_true(player.is_physics_processing())
	assert_eq(player.collision_layer, CollisionLayers.MASK_PLAYER)
	assert_eq(player.collision_mask, CollisionLayers.MASK_ENVIRONMENT)
