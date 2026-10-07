## Universal cable extension providing interactive zipline traversal and audio feedback.
@tool
class_name Zipline
extends UniversalCable3D

## Vertical offset positioning dynamic 3D interaction label near cable hit point.
@export var label_offset_amount: float = 0.35

var player_on_zipline: bool = false
var current_player: CharacterBody3D = null
var last_player_pos: Vector3 = Vector3.ZERO
var current_travel_velocity: Vector3 = Vector3.ZERO
var _cached_camera: Camera3D = null

@onready var interact_component: InteractComponent = (
	$InteractArea/InteractComponent
	if $InteractArea/InteractComponent is InteractComponent
	else null
)
@onready var highlight_component: HighlightComponent = (
	$InteractArea/HighlightComponent
	if $InteractArea/HighlightComponent is HighlightComponent
	else null
)
@onready
var interact_label: Label3D = $InteractArea/Label3D if $InteractArea/Label3D is Label3D else null

@onready
var slide_audio: AudioStreamPlayer3D = $SlideAudio if $SlideAudio is AudioStreamPlayer3D else null
@onready
var climb_audio: AudioStreamPlayer3D = $ClimbAudio if $ClimbAudio is AudioStreamPlayer3D else null


## Initializes input action label and binds interaction component signals.
func _ready() -> void:
	print("Zipline: _ready() - Initializing zipline interactable.")
	super._ready()

	if Engine.is_editor_hint():
		return

	if not is_instance_valid(interact_component):
		push_error("Zipline: InteractComponent not found!")
		return

	if is_instance_valid(interact_label):
		interact_label.hide()

	var action_name: String = "interact"
	var events: Array[InputEvent] = InputMap.action_get_events(action_name)

	if not events.is_empty() and is_instance_valid(interact_label):
		var raw_text: String = events[0].as_text()
		var key_name: String = raw_text.get_slice(" ", 0)
		interact_label.text = "[" + key_name + "] to use ZIPLINE"

	interact_component.interacted.connect(_on_interact_component_interacted)

	if not interact_component.focused.is_connected(_on_focused):
		interact_component.focused.connect(_on_focused)
	if not interact_component.unfocused.is_connected(_on_unfocused):
		interact_component.unfocused.connect(_on_unfocused)


## Tracks player travel velocity, adjusts audio playback, and updates hint label.
func _physics_process(delta: float) -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return

	if player_on_zipline and is_instance_valid(current_player):
		if is_instance_valid(slide_audio):
			slide_audio.global_position = current_player.global_position
		if is_instance_valid(climb_audio):
			climb_audio.global_position = current_player.global_position

		current_travel_velocity = ((current_player.global_position - last_player_pos) / delta)
		var speed: float = current_travel_velocity.length()

		if speed < 0.5:
			if is_instance_valid(slide_audio) and slide_audio.playing:
				slide_audio.stop()
			if is_instance_valid(climb_audio) and climb_audio.playing:
				climb_audio.stop()
		elif current_travel_velocity.y < -0.1:
			if is_instance_valid(climb_audio) and climb_audio.playing:
				climb_audio.stop()
			if is_instance_valid(slide_audio) and not slide_audio.playing:
				slide_audio.play()
		elif current_travel_velocity.y > 0.1:
			if is_instance_valid(slide_audio) and slide_audio.playing:
				slide_audio.stop()
			if is_instance_valid(climb_audio) and not climb_audio.playing:
				climb_audio.play()
		else:
			if is_instance_valid(climb_audio) and climb_audio.playing:
				climb_audio.stop()
			if is_instance_valid(slide_audio) and not slide_audio.playing:
				slide_audio.play()

		last_player_pos = current_player.global_position

	if (
		is_instance_valid(interact_component)
		and interact_component.is_currently_focused
		and not player_on_zipline
	):
		var cam: Camera3D = _get_camera()
		if is_instance_valid(cam) and is_instance_valid(interact_label):
			var hit_point_val: Variant = interact_component.last_hit_position
			var hit_point: Vector3 = Vector3.ZERO

			if hit_point_val is Vector3:
				hit_point = hit_point_val as Vector3

			var cam_right: Vector3 = cam.global_transform.basis.x
			var cam_up: Vector3 = cam.global_transform.basis.y

			var final_pos: Vector3 = hit_point + (cam_right * label_offset_amount) + (cam_up * 0.1)
			interact_label.global_position = final_pos


## Displays interact prompt label when player focuses zipline volume.
func _on_focused() -> void:
	if not player_on_zipline and is_instance_valid(interact_label):
		interact_label.show()


## Hides interact prompt label when player looks away from zipline volume.
func _on_unfocused() -> void:
	if is_instance_valid(interact_label):
		interact_label.hide()


## Handles interact component interaction signal to mount player to zipline.
func _on_interact_component_interacted(player: CharacterBody3D) -> void:
	print("Zipline: _on_interact_component_interacted() called.")
	force_grab_zipline(player)


## Cleans up active player references, stops audio, and un-suppresses outlines.
func on_player_released() -> void:
	print("Zipline: on_player_released() called. Resetting zipline state.")
	player_on_zipline = false
	current_player = null

	if is_instance_valid(slide_audio) and slide_audio.playing:
		slide_audio.stop()
	if is_instance_valid(climb_audio) and climb_audio.playing:
		climb_audio.stop()

	if is_instance_valid(highlight_component):
		highlight_component.suppress(false)


## Returns estimated linear transit velocity calculated across frames.
func get_current_travel_velocity() -> Vector3:
	return current_travel_velocity


## Validates player cooldown and initializes zipline attachment kinematics.
func force_grab_zipline(player: CharacterBody3D) -> void:
	print("Zipline: force_grab_zipline() called for ", player.name)
	if player_on_zipline or not is_instance_valid(player):
		return

	if player.has_method(&"has_zipline_cooldown"):
		if bool(player.call(&"has_zipline_cooldown")):
			print("Zipline: Player has cooldown. Rejecting grab.")
			return

	if player.has_method(&"_on_zipline_grabbed"):
		print("Zipline: Player accepted. Attaching to cable.")
		player_on_zipline = true
		current_player = player

		last_player_pos = current_player.global_position

		if is_instance_valid(interact_label):
			interact_label.hide()

		var point_a: Vector3 = to_global(curve.get_point_position(0))
		var point_b: Vector3 = to_global(curve.get_point_position(curve.get_point_count() - 1))

		player.call(&"_on_zipline_grabbed", self, point_a, point_b)

		if is_instance_valid(highlight_component):
			highlight_component.suppress(true)


## Caches and returns active player [Camera3D] from current viewport.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			_cached_camera = vp.get_camera_3d()
	return _cached_camera
