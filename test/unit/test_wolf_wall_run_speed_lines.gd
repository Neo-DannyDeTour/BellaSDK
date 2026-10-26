## Unit tests for wolf wall run anime speed lines vignette shader and event wiring.
extends GutTest

const EventsScript: GDScript = preload("res://core/events.gd")
const UiScene: PackedScene = preload("res://ui/ui.tscn")

var _events_instance: EventsScript
var _ui_instance: Node


## Prepares test fixtures and loads references.
func before_each() -> void:
	print("Setting up wolf speed lines test fixture.")
	if is_instance_valid(Events):
		_events_instance = Events as EventsScript
	if not is_instance_valid(_events_instance):
		_events_instance = EventsScript.new() as EventsScript
		get_tree().root.add_child(_events_instance)


## Cleans up instantiated nodes after each test.
func after_each() -> void:
	print("Tearing down wolf speed lines test fixture.")
	if is_instance_valid(_ui_instance):
		_ui_instance.queue_free()
		_ui_instance = null


## Validates that wolf_wall_run_vfx_toggled signal exists on Events singleton.
func test_wolf_wall_run_vfx_signal_exists() -> void:
	print("Testing wolf_wall_run_vfx_toggled signal presence on Events.")
	assert_true(
		_events_instance.has_signal(&"wolf_wall_run_vfx_toggled"),
		"Events must define wolf_wall_run_vfx_toggled signal."
	)


## Validates emission of wolf_wall_run_vfx_toggled signal.
func test_wolf_wall_run_vfx_signal_emission() -> void:
	print("Testing wolf_wall_run_vfx_toggled emission.")
	watch_signals(_events_instance)
	_events_instance.wolf_wall_run_vfx_toggled.emit(true)
	assert_signal_emitted_with_parameters(_events_instance, "wolf_wall_run_vfx_toggled", [true])
	_events_instance.wolf_wall_run_vfx_toggled.emit(false)
	assert_signal_emitted_with_parameters(_events_instance, "wolf_wall_run_vfx_toggled", [false])


## Validates presence and material configuration of SpeedLinesOverlay in UI.
func test_speed_lines_overlay_in_ui() -> void:
	print("Testing SpeedLinesOverlay presence and ShaderMaterial configuration.")
	_ui_instance = UiScene.instantiate()
	assert_not_null(_ui_instance, "UI scene must instantiate successfully.")
	get_tree().root.add_child(_ui_instance)

	var mgr: ScreenEffectsManager = (
		_ui_instance.get_node_or_null("ScreenEffectsManager") as ScreenEffectsManager
	)
	assert_not_null(mgr, "ScreenEffectsManager must exist in UI scene.")
	assert_not_null(
		mgr.speed_lines_overlay, "ScreenEffectsManager must cache speed_lines_overlay ColorRect."
	)
	assert_true(
		mgr.speed_lines_overlay.material is ShaderMaterial,
		"SpeedLinesOverlay must have ShaderMaterial assigned."
	)

	var mat: ShaderMaterial = mgr.speed_lines_overlay.material as ShaderMaterial
	assert_not_null(mat.shader, "SpeedLinesOverlay material must hold valid shader.")


## Validates that ScreenEffectsManager shows and tweens overlay on signal reception.
func test_speed_lines_toggle_reaction() -> void:
	print("Testing ScreenEffectsManager response to wolf_wall_run_vfx_toggled.")
	_ui_instance = UiScene.instantiate()
	get_tree().root.add_child(_ui_instance)

	var mgr: ScreenEffectsManager = (
		_ui_instance.get_node_or_null("ScreenEffectsManager") as ScreenEffectsManager
	)
	assert_not_null(mgr, "ScreenEffectsManager must exist.")

	_events_instance.wolf_wall_run_vfx_toggled.emit(true)
	assert_true(
		mgr.speed_lines_overlay.visible, "SpeedLinesOverlay must be visible when toggled active."
	)

	_events_instance.wolf_wall_run_vfx_toggled.emit(false)
