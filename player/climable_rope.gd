@tool
extends Node3D

@export_category("Rope Properties")
@export var is_swingable: bool = false
@export var swing_force: float = 150.0
@export var label_offset_amount: float = 0.35
@export var rope_sound: AudioStreamPlayer3D
@export var slide_sound: AudioStreamPlayer3D

# --- SLOMO VARS ---
@export var activate_slomo: bool = false

@export_range(2.0, 30.0, 0.1) var rope_length: float = 5.0:
	set(value):
		rope_length = value
		_update_rope_size()

var slomo_tween: Tween
var player_on_rope: bool = false
var _cached_camera: Camera3D

@onready var rope_body: RigidBody3D = $RopeBody
@onready var interact_component: Interact_Component = $RopeBody/Interact_Component
@onready var highlight_component: HighlightComponent = $RopeBody/HighlightComponent
@onready var rope_mesh: MeshInstance3D = $RopeBody/MeshInstance3D
@onready var rope_col: CollisionShape3D = $RopeBody/CollisionShape3D
@onready var anchor: StaticBody3D = $Anchor
@onready var pivot: ConeTwistJoint3D = $Pivot
@onready var interact_label: Label3D = $RopeBody/Label3D


func _ready() -> void:
	interact_label.hide()
	_update_rope_size()

	if Engine.is_editor_hint():
		return

	# --- PHYSICS SETUP ---
	if rope_body:
		rope_body.freeze = not is_swingable
		rope_body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		rope_body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		_reset_rope_dampening()

	if interact_component == null:
		return

	# --- UI SETUP ---
	var action_name := "interact"
	var events := InputMap.action_get_events(action_name)

	if events.size() > 0:
		var raw_text := events[0].as_text()
		var key_name := raw_text.split(" ")[0]
		interact_label.text = "[" + key_name + "] CLIMB"

	# --- SIGNAL CONNECTIONS ---
	if not interact_component.interacted.is_connected(_on_interacted):
		interact_component.interacted.connect(_on_interacted)
	if not interact_component.focused.is_connected(_on_focused):
		interact_component.focused.connect(_on_focused)
	if not interact_component.unfocused.is_connected(_on_unfocused):
		interact_component.unfocused.connect(_on_unfocused)


func _process(_delta: float) -> void:
	if not is_inside_tree() or interact_component == null:
		return

	# Process UI updates for visual smoothness
	if interact_component.get("is_currently_focused") == true and not player_on_rope:
		if _cached_camera == null:
			_cached_camera = get_viewport().get_camera_3d()

		if _cached_camera:
			var hit_point_val: Variant = interact_component.get("last_hit_position")
			var hit_point: Vector3 = Vector3.ZERO

			if hit_point_val is Vector3:
				hit_point = hit_point_val

			var cam_right: Vector3 = _cached_camera.global_transform.basis.x
			var cam_up: Vector3 = _cached_camera.global_transform.basis.y

			var final_pos: Vector3 = hit_point + (cam_right * label_offset_amount) + (cam_up * 0.1)
			interact_label.global_position = final_pos


# --- THE SLOMO ENGINE ---
func _set_slomo(target_scale: float) -> void:
	if slomo_tween and slomo_tween.is_valid():
		slomo_tween.kill()

	print("Rope: Engine time_scale transitioning to ", target_scale)

	slomo_tween = create_tween()
	slomo_tween.set_ignore_time_scale(true)
	slomo_tween.tween_property(Engine, "time_scale", target_scale, 0.25)


func _reset_rope_dampening() -> void:
	if rope_body:
		rope_body.angular_damp = 2.5
		rope_body.linear_damp = 1.5


# Helper functions for the signals
func _on_focused() -> void:
	if not player_on_rope:
		interact_label.show()
		if activate_slomo:
			_set_slomo(0.3)


func _on_unfocused() -> void:
	interact_label.hide()
	if activate_slomo:
		_set_slomo(1.0)


func _update_rope_size() -> void:
	if not is_inside_tree() or rope_mesh == null or rope_col == null:
		return

	if rope_mesh.mesh:
		rope_mesh.mesh.height = rope_length
	if rope_col.shape:
		rope_col.shape.height = rope_length

	if rope_mesh:
		rope_mesh.position.y = -rope_length * 0.5
	if rope_col:
		rope_col.position.y = -rope_length * 0.5

	if anchor:
		anchor.position.y = 0.0
	if pivot:
		pivot.position.y = 0.0

	if rope_body:
		rope_body.position = Vector3.ZERO


func _on_interacted(player: CharacterBody3D) -> void:
	print("Player interacted with the rope.")

	if player.has_method("_on_rope_grabbed"):
		player.call("_on_rope_grabbed", rope_body)
		player_on_rope = true
		interact_label.hide()

		if activate_slomo:
			_set_slomo(1.0)

		rope_body.angular_damp = 0.0
		rope_body.linear_damp = 0.0
		if highlight_component:
			highlight_component.suppress(true)


func on_player_released() -> void:
	print("Player released the rope.")
	player_on_rope = false

	handle_rope_sounds(false, false)
	_reset_rope_dampening()

	if highlight_component:
		highlight_component.suppress(false)

	if activate_slomo:
		_set_slomo(1.0)


func handle_rope_sounds(is_climbing: bool, is_sliding: bool) -> void:
	print("Rope handling sounds - Climbing: ", is_climbing, " | Sliding: ", is_sliding)

	# 1. Handle the normal climbing/slow descending sound
	if rope_sound:
		if is_climbing and not is_sliding:
			if not rope_sound.playing:
				rope_sound.play()
		else:
			if rope_sound.playing:
				rope_sound.stop()

	# 2. Handle the fast sliding sound
	if slide_sound:
		if is_sliding:
			if not slide_sound.playing:
				slide_sound.play()
		else:
			if slide_sound.playing:
				slide_sound.stop()
