#class_name SceneTransition
extends CanvasLayer
## Manages threaded background scene loading with full-screen CanvasLayer visual transitions.

## Emitted when scene fade-out completes and background loading begins.
@warning_ignore("unused_signal")
signal transition_halfway

## Emitted when background scene loading and screen fade-in finish.
@warning_ignore("unused_signal")
signal transition_completed

## Emitted when scene loading progress updates. Passes [param progress_0_to_1].
@warning_ignore("unused_signal")
signal loading_progress_updated(progress_0_to_1: float)

## Full-screen color rectangle overlay for transition fades.
var _rect: ColorRect = null

## Active tween managing overlay alpha fades.
var _fade_tween: Tween = null

## Target scene path currently being loaded in the background.
var _loading_target_path: String = ""

## Array capturing threaded load progress fractions.
var _progress_array: Array = []

## Flag indicating whether active background loading is in progress.
var _is_loading: bool = false


## Lifecycle setup creating the overlay rect and setting persistent processing.
func _ready() -> void:
	print("[SceneTransition] SceneTransition Autoload initialized on Layer 100.")
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_setup_overlay_rect()


## Frame polling checking background loading status at 60 FPS.
func _process(_delta: float) -> void:
	if not _is_loading:
		return
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
		_loading_target_path, _progress_array
	)
	var current_progress: float = 0.0
	if not _progress_array.is_empty():
		current_progress = float(_progress_array[0])
	loading_progress_updated.emit(current_progress)

	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_is_loading = false
			set_process(false)
			_finalize_scene_swap()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_is_loading = false
			set_process(false)
			push_error("[SceneTransition] Failed loading scene: " + _loading_target_path)
			_fade_in_overlay(0.3)


## Constructs and anchors the full-screen blackout ColorRect.
func _setup_overlay_rect() -> void:
	_rect = ColorRect.new()
	_rect.name = "TransitionOverlay"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	print("[SceneTransition] Full-screen overlay rect initialized.")


## Starts fade-out and queues asynchronous scene loading for [param target_path].
func change_scene_to_file(target_path: String, fade_duration: float = 0.4) -> void:
	if not ResourceLoader.exists(target_path):
		push_error("[SceneTransition] Target scene path does not exist: " + target_path)
		return
	if _is_loading:
		push_warning("[SceneTransition] Scene transition already in progress.")
		return

	print("[SceneTransition] Starting scene transition to: ", target_path)
	_loading_target_path = target_path
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	if is_instance_valid(_fade_tween) and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_CUBIC)
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(_rect, "color:a", 1.0, fade_duration)
	_fade_tween.finished.connect(_on_fade_out_finished)


## Handles completion of fade-out and triggers background resource loading.
func _on_fade_out_finished() -> void:
	transition_halfway.emit()
	var err: Error = ResourceLoader.load_threaded_request(_loading_target_path, "PackedScene")
	if err != OK:
		push_error("[SceneTransition] Threaded request failed with code: " + str(err))
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	_is_loading = true
	set_process(true)


## Instantiates loaded [PackedScene] and transitions screen back to visible.
func _finalize_scene_swap() -> void:
	var packed_scene: PackedScene = (
		ResourceLoader.load_threaded_get(_loading_target_path) as PackedScene
	)
	if is_instance_valid(packed_scene):
		get_tree().change_scene_to_packed(packed_scene)
		print("[SceneTransition] Swapped active scene to: ", _loading_target_path)
	_fade_in_overlay(0.4)


## Fades overlay back to transparent and restores input control.
func _fade_in_overlay(duration: float) -> void:
	if is_instance_valid(_fade_tween) and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_CUBIC)
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(_rect, "color:a", 0.0, duration)
	_fade_tween.finished.connect(
		func() -> void:
			_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			transition_completed.emit()
			print("[SceneTransition] Transition sequence fully completed.")
	)
