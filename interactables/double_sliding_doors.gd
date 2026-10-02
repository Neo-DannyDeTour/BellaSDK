## Double sliding doors that animate along tracks upon player interaction.
class_name DoubleSlidingDoors
extends Node3D

## Defines valid open and closed door states.
enum State { CLOSED, RIGHT_OPEN, LEFT_OPEN }

## Horizontal distance in meters traversed by sliding doors.
@export var slide_dist: float = 2.0

## Duration in seconds taken for door slide tween animations.
@export var speed: float = 0.4

## Maximum interval in milliseconds registered as a double click.
@export var double_click_delay: int = 300

## Initial local rest position of left door static body.
var left_origin: Vector3

## Initial local rest position of right door static body.
var right_origin: Vector3

## Timestamp in milliseconds recorded on previous interaction.
var last_click_time: int = 0

## Current mechanical configuration state of sliding doors.
var current_state: DoubleSlidingDoors.State = DoubleSlidingDoors.State.CLOSED

## Active [Tween] instances indexed by target door node.
var active_tweens: Dictionary = {}

## Static physical body representing left door panel.
@onready var left_door: StaticBody3D = $DoorLeft

## Static physical body representing right door panel.
@onready var right_door: StaticBody3D = $DoorRight

## Floating interaction prompt label attached to left door.
@onready var left_label: Label3D = $DoorLeft/Label3D

## Floating interaction prompt label attached to right door.
@onready var right_label: Label3D = $DoorRight/Label3D2

## Interaction trigger receiver attached to left door panel.
@onready var left_interact: Node = $DoorLeft/InteractComponent

## Interaction trigger receiver attached to right door panel.
@onready var right_interact: Node = $DoorRight/InteractComponent


## Caches initial door positions and connects interaction signals.
func _ready() -> void:
	print("DoubleSlidingDoors: Initializing doors.")
	left_origin = left_door.position
	right_origin = right_door.position

	right_label.hide()
	left_label.hide()

	left_interact.connect("interacted", _on_interact.bind("left"))
	right_interact.connect("interacted", _on_interact.bind("right"))

	left_interact.connect("focused", _on_focus.bind("left"))
	left_interact.connect("unfocused", _on_unfocus.bind("left"))

	right_interact.connect("focused", _on_focus.bind("right"))
	right_interact.connect("unfocused", _on_unfocus.bind("right"))


## Keeps active 3D prompt labels anchored to player interaction points.
func _process(_delta: float) -> void:
	var label_offset: Vector3 = Vector3(0.0, -0.15, 0.0)

	if left_label.visible and is_instance_valid(left_interact):
		var hit_pos: Vector3 = left_interact.get(&"last_hit_position")
		left_label.global_position = hit_pos + label_offset

	if right_label.visible and is_instance_valid(right_interact):
		var hit_pos: Vector3 = right_interact.get(&"last_hit_position")
		right_label.global_position = hit_pos + label_offset


## Displays dynamic keybind prompt when door is focused.
func _on_focus(side: String) -> void:
	print("DoubleSlidingDoors: Focus gained on side -> ", side)
	var target_label: Label3D = left_label if side == "left" else right_label

	var key_name: String = "E"
	var events: Array[InputEvent] = InputMap.action_get_events(&"interact")
	if events.size() > 0:
		key_name = (
			events[0]
			. as_text()
			. replace(" (Physical)", "")
			. replace(" - Physical", "")
			. replace("Left Mouse Button", "LMB")
			. strip_edges()
		)

	target_label.text = ("[%s] to interact\nDouble [%s] to close" % [key_name, key_name])
	target_label.show()


## Hides prompt label when player looks away from door.
func _on_unfocus(side: String) -> void:
	print("DoubleSlidingDoors: Focus lost on side -> ", side)
	var target_label: Label3D = left_label if side == "left" else right_label
	target_label.hide()


## Processes single and double interaction events from player.
func _on_interact(_character: CharacterBody3D, side: String) -> void:
	print("DoubleSlidingDoors: _on_interact() called on side: ", side)
	var now: int = Time.get_ticks_msec()

	if now - last_click_time < double_click_delay:
		print("DoubleSlidingDoors: Double interaction detected. Resetting.")
		reset_doors()
		last_click_time = 0
		return

	last_click_time = now

	match current_state:
		DoubleSlidingDoors.State.CLOSED:
			if side == "right":
				transition_to(DoubleSlidingDoors.State.RIGHT_OPEN)
			else:
				transition_to(DoubleSlidingDoors.State.LEFT_OPEN)
		DoubleSlidingDoors.State.RIGHT_OPEN:
			transition_to(DoubleSlidingDoors.State.LEFT_OPEN)
		DoubleSlidingDoors.State.LEFT_OPEN:
			transition_to(DoubleSlidingDoors.State.RIGHT_OPEN)


## Transitions doors to a new operational [enum State].
func transition_to(new_state: DoubleSlidingDoors.State) -> void:
	print("DoubleSlidingDoors: Transitioning to state -> ", new_state)
	current_state = new_state

	match current_state:
		DoubleSlidingDoors.State.RIGHT_OPEN:
			animate_door(left_door, left_origin)
			animate_door(right_door, right_origin + Vector3(-slide_dist, 0.0, 0.0))
		DoubleSlidingDoors.State.LEFT_OPEN:
			animate_door(left_door, left_origin + Vector3(slide_dist, 0.0, 0.0))
			animate_door(right_door, right_origin)


## Closes both doors back to their cached rest positions.
func reset_doors() -> void:
	print("DoubleSlidingDoors: Resetting doors to closed state.")
	animate_door(left_door, left_origin)
	animate_door(right_door, right_origin)
	current_state = DoubleSlidingDoors.State.CLOSED


## Tweens target door node position smoothly toward destination vector.
func animate_door(door: Node3D, target: Vector3) -> void:
	print("DoubleSlidingDoors: Animating door -> ", door.name)
	if active_tweens.has(door):
		var existing_tween: Tween = active_tweens[door] as Tween
		if is_instance_valid(existing_tween) and existing_tween.is_valid():
			existing_tween.kill()

	var tween: Tween = create_tween()
	active_tweens[door] = tween

	tween.tween_property(door, ^"position", target, speed).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
