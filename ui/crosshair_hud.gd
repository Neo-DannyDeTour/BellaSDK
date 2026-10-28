## Manages central crosshair reticle states, aim zoom visuals, and terminal focus scaling.
class_name CrosshairHUD
extends CenterContainer

## Shader parameter name for target acquisition tint blending.
const PARAM_TARGET_TINT: StringName = &"shader_parameter/target_tint_weight"

## The central dot texture of the crosshair.
@onready var center_dot: TextureRect = $CenterDot

## The outer circular texture shown when zooming.
@onready var ui_circle_zoom: TextureRect = $UICircleZoom

## The inner circular texture shown when zooming.
@onready var ui_circle_zoom_inner: TextureRect = $UICircleZoomInner

## Animates the crosshair scaling and transformations.
var crosshair_tween: Tween

## Animates the UI elements when the player enters or exits zoom mode.
var zoom_tween: Tween

## Stores the default dimensions of the center crosshair dot.
var default_crosshair_size: Vector2

## Target screen offset vector for magnetic aim assist visual pull.
var _assist_target_offset: Vector2 = Vector2.ZERO

## Current smoothed offset vector applied to the center crosshair dot.
var _assist_current_offset: Vector2 = Vector2.ZERO

## Tween controlling target tint weight on the adaptable outline shader.
var _tint_tween: Tween

## Tracks active target lock state to prevent per-frame tween recreation.
var _is_tint_active: bool = false


## Initializes crosshair element default transforms and connects event listeners.
func _ready() -> void:
	print("CrosshairHUD: _ready() called. Initializing reticle elements.")
	set_process(false)
	_initialize_reticle_elements()
	_connect_signals()


## Updates smoothed spring offset towards target position while assist is active.
func _process(delta: float) -> void:
	if not is_instance_valid(center_dot):
		set_process(false)
		return

	if not _assist_current_offset.is_finite() or not _assist_target_offset.is_finite():
		_assist_current_offset = Vector2.ZERO
		_assist_target_offset = Vector2.ZERO

	_assist_current_offset = _assist_current_offset.lerp(_assist_target_offset, delta * 16.0)
	var base_center: Vector2 = (size - center_dot.size) * 0.5
	center_dot.position = base_center + _assist_current_offset

	if _assist_target_offset == Vector2.ZERO and _assist_current_offset.length_squared() < 0.05:
		_assist_current_offset = Vector2.ZERO
		center_dot.position = base_center
		queue_sort()
		set_process(false)


## Sets default sizes, pivot offsets, and initial visibility for zoom reticles.
func _initialize_reticle_elements() -> void:
	print("CrosshairHUD: Setting initial reticle transformations and pivots.")
	ui_circle_zoom.pivot_offset = ui_circle_zoom.custom_minimum_size / 2.0
	ui_circle_zoom.scale = Vector2.ZERO
	ui_circle_zoom.modulate.a = 0.0
	ui_circle_zoom.hide()

	ui_circle_zoom_inner.pivot_offset = ui_circle_zoom_inner.custom_minimum_size / 2.0
	ui_circle_zoom_inner.scale = Vector2.ZERO
	ui_circle_zoom_inner.modulate.a = 0.0
	ui_circle_zoom_inner.hide()

	default_crosshair_size = center_dot.custom_minimum_size
	if default_crosshair_size == Vector2.ZERO:
		default_crosshair_size = center_dot.size


## Connects global zoom, terminal interaction, and aim assist signals.
func _connect_signals() -> void:
	print("CrosshairHUD: Connecting global event bus signals.")
	if not Events.player_zoomed.is_connected(_on_player_zoomed):
		Events.player_zoomed.connect(_on_player_zoomed)
	if not Events.terminal_mode_toggled.is_connected(_on_terminal_mode_toggled):
		Events.terminal_mode_toggled.connect(_on_terminal_mode_toggled)
	if Events.has_signal(&"aim_assist_target_acquired"):
		if not Events.aim_assist_target_acquired.is_connected(_on_aim_assist_target_acquired):
			Events.aim_assist_target_acquired.connect(_on_aim_assist_target_acquired)


## Cleans up event connections on tree exit.
func _exit_tree() -> void:
	if Events.player_zoomed.is_connected(_on_player_zoomed):
		Events.player_zoomed.disconnect(_on_player_zoomed)
	if Events.terminal_mode_toggled.is_connected(_on_terminal_mode_toggled):
		Events.terminal_mode_toggled.disconnect(_on_terminal_mode_toggled)
	if Events.has_signal(&"aim_assist_target_acquired"):
		if Events.aim_assist_target_acquired.is_connected(_on_aim_assist_target_acquired):
			Events.aim_assist_target_acquired.disconnect(_on_aim_assist_target_acquired)


## Pulls center dot toward target screen position and blends target tint on state change.
func _on_aim_assist_target_acquired(has_target: bool, screen_pos: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(center_dot):
		return

	var valid_target: bool = has_target and screen_pos.is_finite() and screen_pos != Vector2.ZERO

	if valid_target:
		var viewport_center: Vector2 = get_viewport_rect().size * 0.5
		var delta_to_target: Vector2 = screen_pos - viewport_center
		var dist: float = delta_to_target.length()
		if dist > 0.001:
			var pull_distance: float = minf(dist * 0.35, 50.0)
			_assist_target_offset = (delta_to_target / dist) * pull_distance
		else:
			_assist_target_offset = Vector2.ZERO
	else:
		_assist_target_offset = Vector2.ZERO

	set_process(true)

	if valid_target != _is_tint_active:
		_is_tint_active = valid_target
		var mat: ShaderMaterial = center_dot.material as ShaderMaterial
		if is_instance_valid(mat):
			if _tint_tween and _tint_tween.is_valid():
				_tint_tween.kill()
			_tint_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			var target_weight: float = 1.0 if _is_tint_active else 0.0
			var duration: float = 0.15 if _is_tint_active else 0.25
			_tint_tween.tween_property(mat, NodePath(PARAM_TARGET_TINT), target_weight, duration)


## Tweens reticle rings when entering or exiting aim zoom.
## [param is_zooming] True if the player is actively zoomed in.
func _on_player_zoomed(is_zooming: bool) -> void:
	print("CrosshairHUD: _on_player_zoomed() called. State: ", is_zooming)
	if zoom_tween and zoom_tween.is_valid():
		zoom_tween.kill()

	zoom_tween = (create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	))

	if is_zooming:
		center_dot.hide()
		ui_circle_zoom.show()
		ui_circle_zoom_inner.show()

		ui_circle_zoom.scale = Vector2.ZERO
		ui_circle_zoom.modulate.a = 0.0
		ui_circle_zoom_inner.scale = Vector2.ZERO
		ui_circle_zoom_inner.modulate.a = 0.0

		zoom_tween.tween_property(ui_circle_zoom, "scale", Vector2.ONE, 0.5).from(Vector2.ZERO)
		zoom_tween.tween_property(ui_circle_zoom, "modulate:a", 1.0, 0.3).from(0.0)
		zoom_tween.tween_property(ui_circle_zoom, "rotation", deg_to_rad(15), 1.0).from(0.0)

		zoom_tween.tween_property(ui_circle_zoom_inner, "scale", Vector2.ONE, 0.5).from(
			Vector2.ZERO
		)
		zoom_tween.tween_property(ui_circle_zoom_inner, "modulate:a", 0.1, 0.3).from(0.0)
		zoom_tween.tween_property(ui_circle_zoom_inner, "rotation", deg_to_rad(-45), 1.0).from(0.0)
	else:
		center_dot.show()
		zoom_tween.tween_property(ui_circle_zoom, "scale", Vector2.ZERO, 0.5)
		zoom_tween.tween_property(ui_circle_zoom, "modulate:a", 0.0, 0.3)
		zoom_tween.tween_property(ui_circle_zoom, "rotation", deg_to_rad(0), 0.25)

		zoom_tween.tween_property(ui_circle_zoom_inner, "scale", Vector2.ZERO, 0.5)
		zoom_tween.tween_property(ui_circle_zoom_inner, "modulate:a", 0.0, 0.3)
		zoom_tween.tween_property(ui_circle_zoom_inner, "rotation", deg_to_rad(0), 0.25)

		zoom_tween.finished.connect(_on_zoom_out_finished)


## Callback triggered when zoom out tween completes to hide inner nodes.
func _on_zoom_out_finished() -> void:
	ui_circle_zoom.hide()
	ui_circle_zoom_inner.hide()


## Expands the crosshair dot into terminal interaction bounds.
## [param is_active] True if the player is currently focused on an active terminal.
func _on_terminal_mode_toggled(is_active: bool) -> void:
	print("CrosshairHUD: Terminal mode toggled: ", is_active)

	if crosshair_tween and crosshair_tween.is_valid():
		crosshair_tween.kill()

	crosshair_tween = (create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	))

	if is_active:
		var target_size: Vector2 = Vector2(16.0, 16.0)
		crosshair_tween.tween_property(center_dot, "custom_minimum_size", target_size, 0.3)
		crosshair_tween.tween_property(center_dot, "size", target_size, 0.3)
	else:
		crosshair_tween.tween_property(
			center_dot, "custom_minimum_size", default_crosshair_size, 0.3
		)
		crosshair_tween.tween_property(center_dot, "size", default_crosshair_size, 0.3)
