## Ground trap snapping shut on contact to deal damage and immobilize player.
class_name BearTrap
extends Area3D

## Defines possible operational states of beartrap.
enum TrapState { OPEN, CLOSED }

## Tracks current operational state of beartrap.
var current_state: TrapState = TrapState.OPEN

## Stores reference to trapped player to restore mobility.
var trapped_player: Node = null

## Active tween controlling jaw snapping closure animation.
var _snap_tween: Tween = null

## Left jaw visual node used for snapping animation pivot.
@onready var left_jaw: Node3D = get_node_or_null("LeftJawPivot") as Node3D

## Right jaw visual node used for snapping animation pivot.
@onready var right_jaw: Node3D = get_node_or_null("RightJawPivot") as Node3D

## Timer controlling player immobilization duration.
@onready var immobilize_timer: Timer = get_node_or_null("ImmobilizeTimer") as Timer

## Timer controlling sprint prevention duration.
@onready var sprint_block_timer: Timer = get_node_or_null("SprintBlockTimer") as Timer


## Initializes jaw rotations and connects trigger signals.
func _ready() -> void:
	print("BearTrap: _ready() initializing bear trap.")
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER

	Utilities.safe_connect(body_entered, _on_body_entered)
	if is_instance_valid(immobilize_timer):
		Utilities.safe_connect(immobilize_timer.timeout, _on_immobilize_timeout)
	if is_instance_valid(sprint_block_timer):
		Utilities.safe_connect(sprint_block_timer.timeout, _on_sprint_block_timeout)

	if is_instance_valid(left_jaw):
		left_jaw.rotation_degrees.z = 45.0
	if is_instance_valid(right_jaw):
		right_jaw.rotation_degrees.z = -45.0


## Evaluates body entry and triggers trap closure on player.
func _on_body_entered(body: Node3D) -> void:
	print("BearTrap: _on_body_entered() body: ", body.name)
	if current_state == TrapState.OPEN and (body is Player or body.is_in_group(&"player")):
		print("BearTrap: Player triggered trap!")
		snap_shut(body)


## Snaps jaws shut, inflicts damage, and applies mobility debuffs.
func snap_shut(target_player: Node) -> void:
	current_state = TrapState.CLOSED
	trapped_player = target_player
	if not is_instance_valid(target_player):
		return

	print("BearTrap: snap_shut() closing jaws on player: ", target_player.name)

	_snap_tween = Utilities.reset_tween(self, _snap_tween)
	if is_instance_valid(_snap_tween):
		_snap_tween.set_parallel(true)
		if is_instance_valid(left_jaw):
			_snap_tween.tween_property(left_jaw, "rotation_degrees:z", 0.0, 0.1).set_trans(
				Tween.TRANS_BOUNCE
			)
		if is_instance_valid(right_jaw):
			_snap_tween.tween_property(right_jaw, "rotation_degrees:z", 0.0, 0.1).set_trans(
				Tween.TRANS_BOUNCE
			)

	if trapped_player.has_method(&"take_damage"):
		trapped_player.call(&"take_damage", 150)
	else:
		var raw_comp: Node = NodeQuery.find_first_child_of_type(trapped_player, HealthComponent)
		var health_comp: HealthComponent = raw_comp if raw_comp is HealthComponent else null
		if is_instance_valid(health_comp):
			health_comp.take_damage(150)

	var sys_menu: Variant = trapped_player.get(&"system_menu")
	var sys_menu_obj: Object = sys_menu if sys_menu is Object else null
	if is_instance_valid(sys_menu_obj):
		sys_menu_obj.set(&"is_stunned", true)

	var loco_comp: Variant = trapped_player.get(&"locomotion_component")
	var loco_comp_obj: Object = loco_comp if loco_comp is Object else null
	if is_instance_valid(loco_comp_obj):
		loco_comp_obj.set(&"can_sprint", false)

	if Events.has_signal(&"sprint_debuff_applied"):
		Events.sprint_debuff_applied.emit(5.0)
	if Events.has_signal(&"immobilize_debuff_applied"):
		Events.immobilize_debuff_applied.emit(2.0)

	if is_instance_valid(immobilize_timer):
		immobilize_timer.start(2.0)
	if is_instance_valid(sprint_block_timer):
		sprint_block_timer.start(5.0)


## Restores player movement after immobilization timer expires.
func _on_immobilize_timeout() -> void:
	print("BearTrap: _on_immobilize_timeout() restoring player movement.")
	if not is_instance_valid(trapped_player):
		return
	var sys_menu: Variant = trapped_player.get(&"system_menu")
	var sys_menu_obj: Object = sys_menu if sys_menu is Object else null
	if is_instance_valid(sys_menu_obj):
		sys_menu_obj.set(&"is_stunned", false)


## Restores player sprint ability after sprint timer expires.
func _on_sprint_block_timeout() -> void:
	print("BearTrap: _on_sprint_block_timeout() restoring player sprint.")
	if not is_instance_valid(trapped_player):
		return
	var loco_comp: Variant = trapped_player.get(&"locomotion_component")
	var loco_comp_obj: Object = loco_comp if loco_comp is Object else null
	if is_instance_valid(loco_comp_obj):
		loco_comp_obj.set(&"can_sprint", true)
	trapped_player = null
