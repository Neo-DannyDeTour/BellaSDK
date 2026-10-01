## Ground trap snapping shut on contact to deal damage and immobilize player.
class_name BearTrap
extends Area3D

## Defines possible operational states of beartrap.
enum TrapState { OPEN, CLOSED }

## Tracks current operational state of beartrap.
var current_state: TrapState = TrapState.OPEN

## Stores reference to trapped player to restore mobility.
var trapped_player: Player = null

## Active tween controlling jaw snapping closure animation.
var _snap_tween: Tween = null

## Left jaw visual node used for snapping animation pivot.
@onready var left_jaw: Node3D = $LeftJawPivot

## Right jaw visual node used for snapping animation pivot.
@onready var right_jaw: Node3D = $RightJawPivot

## Timer controlling player immobilization duration.
@onready var immobilize_timer: Timer = $ImmobilizeTimer

## Timer controlling sprint prevention duration.
@onready var sprint_block_timer: Timer = $SprintBlockTimer


## Initializes jaw rotations and connects trigger signals.
func _ready() -> void:
	print("BearTrap: _ready() initializing bear trap.")
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER

	Utilities.safe_connect(body_entered, _on_body_entered)
	Utilities.safe_connect(immobilize_timer.timeout, _on_immobilize_timeout)
	Utilities.safe_connect(sprint_block_timer.timeout, _on_sprint_block_timeout)

	left_jaw.rotation_degrees.z = 45.0
	right_jaw.rotation_degrees.z = -45.0


## Evaluates body entry and triggers trap closure on player.
func _on_body_entered(body: Node3D) -> void:
	print("BearTrap: _on_body_entered() body: ", body.name)
	if current_state == TrapState.OPEN and body is Player:
		print("BearTrap: Player triggered trap!")
		snap_shut(body as Player)


## Snaps jaws shut, inflicts damage, and applies mobility debuffs.
func snap_shut(target_player: Player) -> void:
	print("BearTrap: snap_shut() closing jaws on player: ", target_player.name)
	current_state = TrapState.CLOSED
	trapped_player = target_player

	_snap_tween = Utilities.reset_tween(self, _snap_tween)
	if is_instance_valid(_snap_tween):
		_snap_tween.set_parallel(true)
		_snap_tween.tween_property(left_jaw, "rotation_degrees:z", 0.0, 0.1).set_trans(
			Tween.TRANS_BOUNCE
		)
		_snap_tween.tween_property(right_jaw, "rotation_degrees:z", 0.0, 0.1).set_trans(
			Tween.TRANS_BOUNCE
		)

	var health_comp: HealthComponent = (
		NodeQuery.find_first_child_of_type(trapped_player, HealthComponent) as HealthComponent
	)
	if is_instance_valid(health_comp):
		health_comp.take_damage(150)
	elif trapped_player.has_method(&"take_damage"):
		trapped_player.call(&"take_damage", 150)

	if is_instance_valid(trapped_player.system_menu):
		trapped_player.system_menu.set(&"is_stunned", true)

	if is_instance_valid(trapped_player.locomotion_component):
		trapped_player.locomotion_component.set(&"can_sprint", false)

	Events.sprint_debuff_applied.emit(5.0)
	Events.immobilize_debuff_applied.emit(2.0)

	immobilize_timer.start(2.0)
	sprint_block_timer.start(5.0)


## Restores player movement after immobilization timer expires.
func _on_immobilize_timeout() -> void:
	print("BearTrap: _on_immobilize_timeout() restoring player movement.")
	if is_instance_valid(trapped_player) and is_instance_valid(trapped_player.system_menu):
		trapped_player.system_menu.set(&"is_stunned", false)


## Restores player sprint ability after sprint timer expires.
func _on_sprint_block_timeout() -> void:
	print("BearTrap: _on_sprint_block_timeout() restoring player sprint.")
	if is_instance_valid(trapped_player) and is_instance_valid(trapped_player.locomotion_component):
		trapped_player.locomotion_component.set(&"can_sprint", true)
		trapped_player = null
