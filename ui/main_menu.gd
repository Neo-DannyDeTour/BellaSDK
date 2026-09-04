## Central user interface coordinator orchestrating title navigation,
## pause states, music themes, and sub-menu transitions.
class_name MainMenu
extends CanvasLayer

## Default fallback sensitivity multiplier.
const DEFAULT_SENSITIVITY: float = 0.5

## Scene preloaded for instantaneous chapter view display.
const CHAPTER_SCREEN: PackedScene = preload("res://ui/menu_chapter_screen.tscn")

## Audio stream player configured for main theme playback.
@export var main_theme_player: AudioStreamPlayer

## Options menu router coordinating sub-tabs.
@onready var options_router: OptionsRouter = %OptionsMenu

## Settings search component coordinator.
@onready var settings_search: SettingsSearch = %SearchBarContainer

## Primary game title label.
@onready var game_name_label: Label = %GameNameLabel

## Vertical container grouping root buttons.
@onready var main_buttons: VBoxContainer = %MainButtons

## Center container wrapping the options menu overlay.
@onready var options_menu_container: Control = %CenterContainer

## Panel dedicated to managing game save slots.
@onready var save_load_panel: Panel = $SaveLoadPanel

# Navigation Buttons

## Button to unpause and resume active session.
@onready var continue_button: Button = %Continue

## Button to launch a new game run.
@onready var new_game_button: Button = %NewGame

## Button to restart current scene.
@onready var restart_button: Button = %RestartGame

## Button to commit save states to disk.
@onready var save_button: Button = %SaveGame

## Button to view load game menu.
@onready var load_button: Button = %LoadGame

## Button opening settings options overlay.
@onready var options_button: Button = %Options

## Button terminating application process.
@onready var exit_button: Button = %Exit

## Tracks whether automatic mouse speed bucket calibration has run.
var has_calibrated: bool = false

## Records maximum recorded mouse speed during title view.
var max_mouse_speed: float = 0.0


## Lifecycle method configuring layers, signals, and context states.
func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("UI: MainMenu coordinator initialized.")

	_disable_active_grading_volumes()
	_connect_primary_buttons()
	_connect_subcomponents()
	_check_game_context()
	_return_to_main_buttons()


## Connects all root navigation buttons to their respective callbacks.
func _connect_primary_buttons() -> void:
	print("UI: Connecting main menu buttons.")
	if is_instance_valid(continue_button):
		continue_button.pressed.connect(_on_resume_pressed)
	if is_instance_valid(new_game_button):
		new_game_button.pressed.connect(_on_new_game_pressed)
	if is_instance_valid(restart_button):
		restart_button.pressed.connect(_on_start_game_pressed)
	if is_instance_valid(options_button):
		options_button.pressed.connect(_on_options_pressed)
	if is_instance_valid(load_button):
		load_button.pressed.connect(_on_load_pressed)
	if is_instance_valid(exit_button):
		exit_button.pressed.connect(_on_exit_pressed)


## Binds subcomponent signals between router and search controllers.
func _connect_subcomponents() -> void:
	if is_instance_valid(options_router):
		options_router.back_requested.connect(_return_to_main_buttons)

	if is_instance_valid(settings_search) and is_instance_valid(options_router):
		settings_search.setting_navigated.connect(_on_setting_navigated)
		settings_search.build_index(
			options_router.get_all_panels(), options_router.get_all_tab_buttons()
		)


## Routes search result navigation events to the options controller.
## [param tab_idx] Tab category index.
## [param target] Target control widget.
func _on_setting_navigated(tab_idx: int, target: Control) -> void:
	print("UI: Routing player from search result to tab ", tab_idx)
	if not options_menu_container.visible:
		_on_options_pressed()

	if is_instance_valid(options_router):
		options_router.select_tab_by_index(tab_idx)

	if is_instance_valid(target):
		if target.focus_mode == Control.FOCUS_NONE:
			target.focus_mode = Control.FOCUS_ALL
		target.grab_focus()


## Disables active grading volume nodes across the scene tree.
func _disable_active_grading_volumes() -> void:
	print("UI: Resetting scene tree ColorGradingVolume3D nodes.")
	get_tree().call_group_flags(
		SceneTree.GROUP_CALL_DEFERRED, "color_grading_volumes", "reset_to_default"
	)


## Checks save availability and pause availability.
func _check_game_context() -> void:
	print("UI: Evaluating game execution context.")
	if SaveManager.has_method("has_saves"):
		var saves_exist: bool = SaveManager.has_saves() as bool
		if is_instance_valid(load_button):
			load_button.visible = saves_exist

	var parent: Node = get_parent()
	if is_instance_valid(parent) and parent.has_method("toggle_pause"):
		if is_instance_valid(continue_button):
			continue_button.show()
		if is_instance_valid(restart_button):
			restart_button.show()
		if is_instance_valid(save_button):
			save_button.show()
		if is_instance_valid(new_game_button):
			new_game_button.text = ""
	else:
		if is_instance_valid(continue_button):
			continue_button.hide()
		if is_instance_valid(restart_button):
			restart_button.hide()
		if is_instance_valid(save_button):
			save_button.hide()
		_play_main_theme()


## Begins main theme audio playback.
func _play_main_theme() -> void:
	if is_instance_valid(main_theme_player) and not main_theme_player.playing:
		print("Audio: Starting main theme playback.")
		main_theme_player.play()


## Halts main theme audio playback.
func _stop_main_theme() -> void:
	if is_instance_valid(main_theme_player) and main_theme_player.playing:
		print("Audio: Stopping main theme playback.")
		main_theme_player.stop()


## Restores the primary navigation view and closes overlays.
func _return_to_main_buttons() -> void:
	print("UI: Restoring root menu view.")
	if is_instance_valid(game_name_label):
		game_name_label.visible = true
	if is_instance_valid(main_buttons):
		main_buttons.visible = true
	if is_instance_valid(options_menu_container):
		options_menu_container.visible = false
	if is_instance_valid(save_load_panel):
		save_load_panel.visible = false
	if is_instance_valid(settings_search):
		settings_search.hide_search_results()


## Unpauses game session and closes title interface.
func _on_resume_pressed() -> void:
	print("UI: Player clicked Resume.")
	_stop_main_theme()
	var parent: Node = get_parent()
	if is_instance_valid(parent) and parent.has_method("toggle_pause"):
		parent.call("toggle_pause")


## Opens chapter selection screen for starting a new session.
func _on_new_game_pressed() -> void:
	print("UI: Player clicked New Game.")
	_stop_main_theme()
	if not has_calibrated:
		_apply_bucket_calibration()

	if is_instance_valid(game_name_label):
		game_name_label.hide()
	if is_instance_valid(main_buttons):
		main_buttons.hide()

	var chapter_window: Node = CHAPTER_SCREEN.instantiate()
	add_child(chapter_window)


## Restarts the current gameplay level.
func _on_start_game_pressed() -> void:
	print("UI: Player clicked Restart Game.")
	_stop_main_theme()
	if not has_calibrated:
		_apply_bucket_calibration()

	get_tree().paused = false
	var parent: Node = get_parent()
	if is_instance_valid(parent) and parent.has_method("toggle_pause"):
		get_tree().reload_current_scene()


## Opens the options menu overlay.
func _on_options_pressed() -> void:
	print("UI: Player clicked Options.")
	if is_instance_valid(game_name_label):
		game_name_label.visible = false
	if is_instance_valid(main_buttons):
		main_buttons.visible = false
	if is_instance_valid(save_load_panel):
		save_load_panel.visible = false
	if is_instance_valid(options_menu_container):
		options_menu_container.visible = true

	if is_instance_valid(options_router):
		options_router.select_tab_by_index(0)


## Opens the save/load menu overlay.
func _on_load_pressed() -> void:
	print("UI: Player clicked Load Game.")
	if is_instance_valid(game_name_label):
		game_name_label.visible = false
	if is_instance_valid(main_buttons):
		main_buttons.visible = false
	if is_instance_valid(options_menu_container):
		options_menu_container.visible = false
	if is_instance_valid(save_load_panel):
		save_load_panel.visible = true


## Quits application execution cleanly.
func _on_exit_pressed() -> void:
	print("UI: Player clicked Exit. Terminating.")
	get_tree().quit()


## Applies heuristic sensitivity calibration preset based on peak velocity.
func _apply_bucket_calibration() -> void:
	print("System: Running mouse sensitivity calibration.")
	var saved_sens: Variant = GlobalSettings.get_setting("Settings", "mouse_sensitivity", null)
	if saved_sens != null:
		has_calibrated = true
		return

	has_calibrated = true
	var auto_sens: float = DEFAULT_SENSITIVITY

	if max_mouse_speed > 6500.0:
		auto_sens = 0.70
	elif max_mouse_speed > 5000.0:
		auto_sens = 0.50
	elif max_mouse_speed > 4000.0:
		auto_sens = 0.40
	elif max_mouse_speed > 3000.0:
		auto_sens = 0.30
	elif max_mouse_speed > 2000.0:
		auto_sens = 0.20
	elif max_mouse_speed > 1000.0:
		auto_sens = 0.10
	else:
		auto_sens = 0.05

	print("System: Calibrated mouse sensitivity preset -> ", auto_sens)
	GlobalSettings.save_setting("Settings", "mouse_sensitivity", auto_sens)


## Handles peak mouse velocity sampling and UI cancel input delegation.
## [param event] Viewport input event.
func _input(event: InputEvent) -> void:
	if not has_calibrated and event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var current_speed: float = motion.velocity.length()
		if current_speed > max_mouse_speed:
			max_mouse_speed = current_speed

	if event.is_action_pressed("ui_cancel"):
		if not visible:
			return

		if is_instance_valid(settings_search):
			if (
				is_instance_valid(settings_search.search_results_panel)
				and settings_search.search_results_panel.visible
			):
				print("UI: Cancel input caught -> Hiding search popup.")
				settings_search.hide_search_results()
				get_viewport().set_input_as_handled()
				return

		if options_menu_container.visible or save_load_panel.visible:
			print("UI: Cancel input caught -> Returning to main view.")
			_return_to_main_buttons()
			get_viewport().set_input_as_handled()
		elif main_buttons.visible and get_parent().has_method("toggle_pause"):
			print("UI: Cancel input caught -> Resuming game session.")
			_on_resume_pressed()
			get_viewport().set_input_as_handled()
