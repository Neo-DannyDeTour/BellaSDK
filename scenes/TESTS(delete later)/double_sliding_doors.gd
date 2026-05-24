extends Node3D

enum State { CLOSED, RIGHT_OPEN, LEFT_OPEN }

@export var slide_dist: float = 2.0
@export var speed: float = 0.4
@export var double_click_delay: int = 300

var left_origin: Vector3
var right_origin: Vector3
var last_click_time: int = 0
var current_state: State = State.CLOSED
var active_tweens: Dictionary = {}
@onready var left_door: StaticBody3D = $DoorLeft
@onready var right_door: StaticBody3D = $DoorRight

@onready var left_label: Label3D = $DoorLeft/Label3D
@onready var right_label: Label3D = $DoorRight/Label3D2

@onready var left_interact: Node = $DoorLeft/Interact_Component
@onready var right_interact: Node = $DoorRight/Interact_Component


func _ready() -> void:
	# Use .position instead of .transform.origin
	left_origin = left_door.position
	right_origin = right_door.position

	right_label.hide()
	left_label.hide()

	# --- THE FIX: SWAP THE BINDS ---
	# If clicking the left door moves the right door, we just tell the left
	# component that it is actually controlling the right door!
	left_interact.interacted.connect(_on_interact.bind("left"))
	right_interact.interacted.connect(_on_interact.bind("right"))

	# Do the same for the focus labels so the text pops up on the correct side
	left_interact.focused.connect(_on_focus.bind("left"))
	left_interact.unfocused.connect(_on_unfocus.bind("left"))

	right_interact.focused.connect(_on_focus.bind("right"))
	right_interact.unfocused.connect(_on_unfocus.bind("right"))


func _process(_delta: float) -> void:
	var label_offset := Vector3(0, -0.15, 0)
	# Keep the label stuck to the exact hit point on the screen
	if left_label.visible:
		# Add the offset to the hit position
		left_label.global_position = left_interact.last_hit_position + label_offset

	if right_label.visible:
		# Add the offset to the hit position
		right_label.global_position = right_interact.last_hit_position + label_offset


# ==========================================
# LABEL LOGIC
# ==========================================
func _on_focus(side: String) -> void:
	var target_label := left_label if side == "left" else right_label

	var key_name := "E"
	var events := InputMap.action_get_events("interact")
	if events.size() > 0:
		key_name = (
			events[0]
			. as_text()
			. replace(" (Physical)", "")
			. replace(" - Physical", "")
			. replace("Left Mouse Button", "LMB")
			. strip_edges()
		)

	target_label.text = "[%s] to interact\nDouble [%s] to close" % [key_name, key_name]
	target_label.show()


func _on_unfocus(side: String) -> void:
	var target_label := left_label if side == "left" else right_label
	target_label.hide()


# ==========================================
# MOVEMENT LOGIC
# ==========================================
func _on_interact(_character: CharacterBody3D, side: String) -> void:
	var now := Time.get_ticks_msec()

	if now - last_click_time < double_click_delay:
		reset_doors()
		last_click_time = 0
		return

	last_click_time = now

	match current_state:
		State.CLOSED:
			if side == "right":
				transition_to(State.RIGHT_OPEN)
			else:
				transition_to(State.LEFT_OPEN)
		State.RIGHT_OPEN:
			transition_to(State.LEFT_OPEN)
		State.LEFT_OPEN:
			transition_to(State.RIGHT_OPEN)


func transition_to(new_state: State) -> void:
	current_state = new_state

	match current_state:
		State.RIGHT_OPEN:
			animate_door(left_door, left_origin)
			animate_door(right_door, right_origin + Vector3(-slide_dist, 0, 0))
		State.LEFT_OPEN:
			animate_door(left_door, left_origin + Vector3(slide_dist, 0, 0))
			animate_door(right_door, right_origin)


func reset_doors() -> void:
	animate_door(left_door, left_origin)
	animate_door(right_door, right_origin)
	current_state = State.CLOSED


func animate_door(door: Node3D, target: Vector3) -> void:
	if active_tweens.has(door) and active_tweens[door] and active_tweens[door].is_valid():
		active_tweens[door].kill()

	var tween := create_tween()
	active_tweens[door] = tween

	# CHANGED: "transform:origin" is now "position"
	tween.tween_property(door, "position", target, speed).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
