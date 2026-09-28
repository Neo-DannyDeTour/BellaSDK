## A trap that snaps shut when the player steps on it, dealing damage and applying debuffs.
##
## Acts as a static hazard in the environment. When the player enters the [Area3D],
## the trap closes, damages the player, and prevents them from moving or sprinting
## for a specific duration using timers.
class_name BearTrap
extends Area3D

## Defines the possible operational states of the beartrap.
enum TrapState { OPEN, CLOSED }

## Tracks the current operational state of the beartrap.
var current_state: TrapState = TrapState.OPEN

## Stores a reference to the trapped [Player] to restore their movement states later.
var trapped_player: Player = null

## Active tween controlling jaw closure; managed via [method Utilities.reset_tween].
var _snap_tween: Tween = null

## The left jaw visual node used for the snapping animation pivot.
@onready var left_jaw: Node3D = $LeftJawPivot

## The right jaw visual node used for the snapping animation pivot.
@onready var right_jaw: Node3D = $RightJawPivot

## [Timer] to control the 2-second duration where the player cannot move.
@onready var immobilize_timer: Timer = $ImmobilizeTimer

## [Timer] to control the 5-second duration where the player cannot sprint.
@onready var sprint_block_timer: Timer = $SprintBlockTimer


## Initializes the beartrap in the OPEN state, setting jaw angles and connecting signals.
func _ready() -> void:
	print("BearTrap: _ready() - Initializing beartrap in OPEN state.")
	Utilities.safe_connect(body_entered, _on_body_entered)
	Utilities.safe_connect(immobilize_timer.timeout, _on_immobilize_timeout)
	Utilities.safe_connect(sprint_block_timer.timeout, _on_sprint_block_timeout)

	left_jaw.rotation_degrees.z = 45.0
	right_jaw.rotation_degrees.z = -45.0


## Handles collision when body enters [Area3D], triggering trap if body is [Player].
## [param body] The [Node3D] that entered the trigger area.
func _on_body_entered(body: Node3D) -> void:
	if current_state == TrapState.OPEN and body is Player:
		print("BearTrap: _on_body_entered() - Player stepped in the trap!")
		snap_shut(body as Player)


## Closes the jaws, damages [param player], and applies movement and sprint debuffs.
func snap_shut(player: Player) -> void:
	print("BearTrap: snap_shut() - Closing jaws and applying debuffs to player.")
	current_state = TrapState.CLOSED
	trapped_player = player

	_snap_tween = Utilities.reset_tween(self, _snap_tween)
	if is_instance_valid(_snap_tween):
		_snap_tween.set_parallel(true)
		_snap_tween.tween_property(left_jaw, "rotation_degrees:z", 0.0, 0.1).set_trans(
			Tween.TRANS_BOUNCE
		)
		_snap_tween.tween_property(right_jaw, "rotation_degrees:z", 0.0, 0.1).set_trans(
			Tween.TRANS_BOUNCE
		)

	trapped_player.take_damage(150)

	if is_instance_valid(trapped_player.system_menu):
		trapped_player.system_menu.set("is_stunned", true)

	if is_instance_valid(trapped_player.locomotion_component):
		trapped_player.locomotion_component.set("can_sprint", false)

	Events.sprint_debuff_applied.emit(5.0)
	Events.immobilize_debuff_applied.emit(2.0)

	immobilize_timer.start(2.0)
	sprint_block_timer.start(5.0)


## Restores the player's ability to move after the immobilize timer completes.
func _on_immobilize_timeout() -> void:
	print("BearTrap: _on_immobilize_timeout() - Freeing player movement.")
	if is_instance_valid(trapped_player) and is_instance_valid(trapped_player.system_menu):
		trapped_player.system_menu.set("is_stunned", false)


## Restores the player's ability to sprint after the sprint block timer completes.
func _on_sprint_block_timeout() -> void:
	print("BearTrap: _on_sprint_block_timeout() - Restoring sprint capability.")
	if is_instance_valid(trapped_player) and is_instance_valid(trapped_player.locomotion_component):
		trapped_player.locomotion_component.set("can_sprint", true)
		trapped_player = null
