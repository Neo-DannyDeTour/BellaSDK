## A pair of sliding doors that track separate interaction states and manage floating UI prompts.
##
## Supports double-clicking to close both doors and cross-referencing input actions to automatically
## update prompt labels.
class_name DoubleSlidingDoors
extends Node3D

## Defines the three possible states for the dual door system.
enum State { CLOSED, RIGHT_OPEN, LEFT_OPEN }

## The physical distance in meters that a single door will translate along its local X-axis.
@export var slide_dist: float = 2.0
## The duration in seconds for the sliding animation to complete.
@export var speed: float = 0.4
## The maximum time window in milliseconds between clicks to register a 'close all' command.
@export var double_click_delay: int = 300

## Cached local starting position for the left door mesh.
var left_origin: Vector3
## Cached local starting position for the right door mesh.
var right_origin: Vector3
## Timestamp of the previous interaction, used to calculate double-clicks.
var last_click_time: int = 0
## The currently active positional state of the door system.
var current_state: State = State.CLOSED
## Tracks active [Tween] instances per door to allow graceful interruptions.
var active_tweens: Dictionary = {}

## Reference to the left door physics body.
@onready var left_door: StaticBody3D = $DoorLeft
## Reference to the right door physics body.
@onready var right_door: StaticBody3D = $DoorRight

## Floating interaction prompt label for the left door.
@onready var left_label: Label3D = $DoorLeft/Label3D
## Floating interaction prompt label for the right door.
@onready var right_label: Label3D = $DoorRight/Label3D2

## Interaction component bound to the left door's surface.
@onready var left_interact: Node = $DoorLeft/InteractComponent
## Interaction component bound to the right door's surface.
@onready var right_interact: Node = $DoorRight/InteractComponent


## Caches initial door positions, hides default labels, and maps interaction signals.
func _ready() -> void:
	left_origin = left_door.position
	right_origin = right_door.position

	right_label.hide()
	left_label.hide()

	left_interact.interacted.connect(_on_interact.bind("left"))
	right_interact.interacted.connect(_on_interact.bind("right"))

	left_interact.focused.connect(_on_focus.bind("left"))
	left_interact.unfocused.connect(_on_unfocus.bind("left"))

	right_interact.focused.connect(_on_focus.bind("right"))
	right_interact.unfocused.connect(_on_unfocus.bind("right"))


## Snaps visible labels to the exact 3D raycast hit coordinate on the door surface.
## [param _delta]: Frame delta time.
func _process(_delta: float) -> void:
	var label_offset: Vector3 = Vector3(0, -0.15, 0)
	if left_label.visible:
		left_label.global_position = left_interact.get("last_hit_position") + label_offset

	if right_label.visible:
		right_label.global_position = right_interact.get("last_hit_position") + label_offset


# ==========================================
# LABEL LOGIC
# ==========================================


## Formats and displays the interact label with the bound input key.
## [param side]: The string identifier ("left" or "right") indicating which door was focused.
func _on_focus(side: String) -> void:
	var target_label: Label3D = left_label if side == "left" else right_label

	var key_name: String = "E"
	var events: Array[InputEvent] = InputMap.action_get_events("interact")
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


## Hides the interaction label when the player looks away.
## [param side]: The string identifier ("left" or "right") indicating which door was unfocused.
func _on_unfocus(side: String) -> void:
	var target_label: Label3D = left_label if side == "left" else right_label
	target_label.hide()


# ==========================================
# MOVEMENT LOGIC
# ==========================================


## Evaluates timestamps to distinguish single clicks from double clicks.
## [param _character]: The player character executing the interaction.
## [param side]: The side being operated ("left" or "right").
func _on_interact(_character: CharacterBody3D, side: String) -> void:
	print("DoubleSlidingDoors: _on_interact() called. Operating doors.")
	var now: int = Time.get_ticks_msec()

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


## Updates the logic state and computes the target vectors for the tweening function.
## [param new_state]: The requested positional configuration from the [enum State] definitions.
func transition_to(new_state: State) -> void:
	current_state = new_state

	match current_state:
		State.RIGHT_OPEN:
			animate_door(left_door, left_origin)
			animate_door(right_door, right_origin + Vector3(-slide_dist, 0, 0))
		State.LEFT_OPEN:
			animate_door(left_door, left_origin + Vector3(slide_dist, 0, 0))
			animate_door(right_door, right_origin)


## Resets both door meshes back to their cached origins.
func reset_doors() -> void:
	animate_door(left_door, left_origin)
	animate_door(right_door, right_origin)
	current_state = State.CLOSED


## Creates or overrides a [Tween] to slide the specified door node to a given local coordinate.
## [param door]: The specific [StaticBody3D] to move.
## [param target]: The final local 3D position vector.
func animate_door(door: Node3D, target: Vector3) -> void:
	if active_tweens.has(door) and active_tweens[door] and active_tweens[door].is_valid():
		active_tweens[door].kill()

	var tween: Tween = create_tween()
	active_tweens[door] = tween

	tween.tween_property(door, "position", target, speed).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
