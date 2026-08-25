extends Area3D
class_name BearTrap

enum TrapState { OPEN, CLOSED }

## Tracks the current operational state of the beartrap.
var current_state: TrapState = TrapState.OPEN

## Stores a reference to the trapped player to restore their movement states later.
var trapped_player: Player = null

## The left jaw visual node used for the snapping animation pivot.
@onready var left_jaw: Node3D = $LeftJawPivot

## The right jaw visual node used for the snapping animation pivot.
@onready var right_jaw: Node3D = $RightJawPivot

## [Timer] to control the 2-second duration where the player cannot move.
@onready var immobilize_timer: Timer = $ImmobilizeTimer

## [Timer] to control the 5-second duration where the player cannot sprint.
@onready var sprint_block_timer: Timer = $SprintBlockTimer


func _ready() -> void:
	print("BearTrap: _ready() - Initializing beartrap in OPEN state.")
	body_entered.connect(_on_body_entered)
	immobilize_timer.timeout.connect(_on_immobilize_timeout)
	sprint_block_timer.timeout.connect(_on_sprint_block_timeout)

	left_jaw.rotation_degrees.z = 45.0
	right_jaw.rotation_degrees.z = -45.0


func _on_body_entered(body: Node3D) -> void:
	if current_state == TrapState.OPEN and body is Player:
		print("BearTrap: _on_body_entered() - Player stepped in the trap!")
		snap_shut(body as Player)


func snap_shut(player: Player) -> void:
	print("BearTrap: snap_shut() - Closing jaws and applying debuffs to player.")
	current_state = TrapState.CLOSED
	trapped_player = player

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(left_jaw, "rotation_degrees:z", 0.0, 0.1).set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(right_jaw, "rotation_degrees:z", 0.0, 0.1).set_trans(Tween.TRANS_BOUNCE)

	trapped_player.take_damage(150)

	if is_instance_valid(trapped_player.system_menu):
		trapped_player.system_menu.is_stunned = true

	if is_instance_valid(trapped_player.locomotion_component):
		trapped_player.locomotion_component.can_sprint = false

	Events.sprint_debuff_applied.emit(5.0)
	Events.immobilize_debuff_applied.emit(2.0)

	immobilize_timer.start(2.0)
	sprint_block_timer.start(5.0)


func _on_immobilize_timeout() -> void:
	print("BearTrap: _on_immobilize_timeout() - Freeing player movement.")
	if is_instance_valid(trapped_player) and is_instance_valid(trapped_player.system_menu):
		trapped_player.system_menu.is_stunned = false


func _on_sprint_block_timeout() -> void:
	print("BearTrap: _on_sprint_block_timeout() - Restoring sprint capability.")
	if is_instance_valid(trapped_player) and is_instance_valid(trapped_player.locomotion_component):
		trapped_player.locomotion_component.can_sprint = true
		trapped_player = null
