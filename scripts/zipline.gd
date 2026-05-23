@tool
extends UniversalCable3D

@onready var interact_component: Interact_Component = $InteractArea/Interact_Component
@onready var highlight_component: HighlightComponent = $InteractArea/HighlightComponent
@onready var interact_label: Label3D = $InteractArea/Label3D

@onready var slide_audio: AudioStreamPlayer3D = $SlideAudio
@onready var climb_audio: AudioStreamPlayer3D = $ClimbAudio

@export var label_offset_amount: float = 0.35

# --- THE LOCK ---
var player_on_zipline: bool = false
var current_player: CharacterBody3D = null

# NEW: We need to track real position changes in case the player's built-in velocity is zero
var last_player_pos: Vector3 = Vector3.ZERO
var current_travel_velocity: Vector3 = Vector3.ZERO  # NEW: Store this globally for the player to grab


func _ready() -> void:
	super._ready()

	if Engine.is_editor_hint():
		return

	if interact_component == null:
		push_error("Zipline: InteractComponent not found!")
		return

	if interact_label:
		interact_label.hide()

	var action_name := "interact"
	var events := InputMap.action_get_events(action_name)
	if events.size() > 0 and interact_label:
		var raw_text := events[0].as_text()
		var key_name := raw_text.split(" ")[0]
		interact_label.text = "[" + key_name + "] to use ZIPLINE"

	interact_component.interacted.connect(_on_interact_component_interacted)

	if not interact_component.focused.is_connected(_on_focused):
		interact_component.focused.connect(_on_focused)
	if not interact_component.unfocused.is_connected(_on_unfocused):
		interact_component.unfocused.connect(_on_unfocused)


func _physics_process(delta: float) -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return

	if player_on_zipline and is_instance_valid(current_player):
		if slide_audio:
			slide_audio.global_position = current_player.global_position
		if climb_audio:
			climb_audio.global_position = current_player.global_position

		# UPDATED: Use the class-level variable
		current_travel_velocity = (current_player.global_position - last_player_pos) / delta
		var speed: float = current_travel_velocity.length()

		if speed < 0.5:
			if slide_audio and slide_audio.playing:
				slide_audio.stop()
			if climb_audio and climb_audio.playing:
				climb_audio.stop()

		elif current_travel_velocity.y < -0.1:
			if climb_audio and climb_audio.playing:
				climb_audio.stop()
			if slide_audio and not slide_audio.playing:
				slide_audio.play()

		elif current_travel_velocity.y > 0.1:
			if slide_audio and slide_audio.playing:
				slide_audio.stop()
			if climb_audio and not climb_audio.playing:
				climb_audio.play()

		else:
			if climb_audio and climb_audio.playing:
				climb_audio.stop()
			if slide_audio and not slide_audio.playing:
				slide_audio.play()

		last_player_pos = current_player.global_position

	# Label logic remains the same
	if interact_component and interact_component.is_currently_focused and not player_on_zipline:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam and interact_label:
			var hit_point_val: Variant = interact_component.last_hit_position
			var hit_point: Vector3 = Vector3.ZERO

			if hit_point_val is Vector3:
				hit_point = hit_point_val

			var cam_right: Vector3 = cam.global_transform.basis.x
			var cam_up: Vector3 = cam.global_transform.basis.y

			var final_pos: Vector3 = hit_point + (cam_right * label_offset_amount) + (cam_up * 0.1)
			interact_label.global_position = final_pos


func _on_focused() -> void:
	if not player_on_zipline and interact_label:
		interact_label.show()


func _on_unfocused() -> void:
	if interact_label:
		interact_label.hide()


func _on_interact_component_interacted(player: CharacterBody3D) -> void:
	force_grab_zipline(player)


func on_player_released() -> void:
	player_on_zipline = false
	current_player = null

	if slide_audio and slide_audio.playing:
		slide_audio.stop()
	if climb_audio and climb_audio.playing:
		climb_audio.stop()

	if highlight_component:
		highlight_component.suppress(false)


# Inside UniversalCable3D (Zipline) script


func force_grab_zipline(player: CharacterBody3D) -> void:
	if player_on_zipline:
		return

	# NEW: Check if the player is currently locked out of grabbing
	if "zipline_cooldown" in player and player.zipline_cooldown > 0.0:
		return  # Reject the grab attempt!

	if player and player.has_method("_on_zipline_grabbed"):
		player_on_zipline = true
		current_player = player

		last_player_pos = current_player.global_position

		if interact_label:
			interact_label.hide()

		var point_a := to_global(curve.get_point_position(0))
		var point_b := to_global(curve.get_point_position(curve.get_point_count() - 1))

		player._on_zipline_grabbed(self, point_a, point_b)

		if highlight_component:
			highlight_component.suppress(true)
