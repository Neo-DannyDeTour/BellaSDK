## A specialized physics object that restricts player movement when held and enables gliding.
##
## Differs from standard [PickableObject] by using a dedicated animation tween to pull the player
## towards an anchor point before pickup, rather than pulling the object to the player.
class_name GliderItem
extends RigidBody3D

## The specific 3D coordinate the player must tween towards before the glider attaches.
@onready var player_anchor: Marker3D = $PlayerAnchor

## Caches the character currently carrying the glider to manipulate their movement states.
var current_holder: CharacterBody3D = null


## Toggles the visual rendering of the glider (currently a placeholder for custom mesh logic).
## [param p_is_visible]: Boolean state for mesh visibility.
func set_glider_mesh_visible(p_is_visible: bool) -> void:
	print("GliderItem: set_glider_mesh_visible() called. State: ", p_is_visible)
	# Toggle your specific mesh node here. For example:
	# get_node("MeshInstance3D").visible = p_is_visible


## Locks the player and tweens them to the [member player_anchor] before attaching.
## [param hold_position]: The target socket on the player's weapon mount.
## [param player]: The player executing the interaction.
func pick_up(hold_position: Marker3D, player: CharacterBody3D) -> void:
	print("GliderItem: pick_up() called. Initiating tween sequence for player.")

	current_holder = player

	# 1. Disable physics while being picked up and held
	freeze = true
	collision_layer = 0
	collision_mask = 0

	# 2. Lock the player in place using your existing function
	if player.has_method("set_machine_lock"):
		player.call("set_machine_lock", true)

	# 3. Tween the player's global X/Z to the anchor, but keep their Y to avoid clipping into the floor
	var tween: Tween = get_tree().create_tween()
	var target_pos: Vector3 = Vector3(
		player_anchor.global_position.x, player.global_position.y, player_anchor.global_position.z
	)

	(
		tween
		. tween_property(player, "global_position", target_pos, 0.4)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	tween.tween_callback(_on_player_reached_anchor.bind(player, hold_position))


## Callback after the tween finishes. Attaches the glider and restricts sprinting.
## [param player]: The character node that was moved.
## [param _hold_position]: The weapon mount socket.
func _on_player_reached_anchor(player: CharacterBody3D, _hold_position: Marker3D) -> void:
	print("GliderItem: Player reached anchor. Attaching glider to weapon holder.")

	var interaction_comp: Node = player.get("interaction_component") as Node
	if (
		is_instance_valid(interaction_comp)
		and interaction_comp.has_method("attach_item_to_weapon_holder")
	):
		interaction_comp.call("attach_item_to_weapon_holder", self, player_anchor, player)

	# 4. Apply restrictions and unlock the player
	var loco_comp: Node = player.get("locomotion_component") as Node
	if is_instance_valid(loco_comp):
		loco_comp.set("can_sprint", false)

	if player.has_method("set_machine_lock"):
		player.call("set_machine_lock", false)


## Restores player sprint ability, detaches the glider, and applies a throwing impulse.
## [param force]: The 3D directional vector representing throw strength.
## [param scene_root]: The root node to re-parent the glider into.
func throw_item(force: Vector3, scene_root: Node) -> void:
	print("GliderItem: throw_item() called. Releasing glider into the world.")

	# Restore sprint restriction
	if is_instance_valid(current_holder):
		var loco_comp: Node = current_holder.get("locomotion_component") as Node
		if is_instance_valid(loco_comp):
			loco_comp.set("can_sprint", true)
	current_holder = null

	# Detach from player and put back in world
	var current_parent: Node = get_parent()
	if is_instance_valid(current_parent):
		current_parent.remove_child(self)

	if is_instance_valid(scene_root):
		scene_root.add_child(self)

	# Re-enable physics
	freeze = false
	collision_layer = 1
	collision_mask = 1

	apply_central_impulse(force)


## Detaches the glider without force, dropping it safely at the provided coordinates.
## [param scene_root]: The root node to re-parent the glider into.
## [param drop_pos]: The safe 3D coordinate to spawn the glider at (usually the player's feet).
func drop_item(scene_root: Node, drop_pos: Vector3) -> void:
	print("GliderItem: drop_item() called. Detaching from player.")

	# Restore sprint restriction
	if is_instance_valid(current_holder):
		var loco_comp: Node = current_holder.get("locomotion_component") as Node
		if is_instance_valid(loco_comp):
			loco_comp.set("can_sprint", true)
	current_holder = null

	var current_parent: Node = get_parent()
	if is_instance_valid(current_parent):
		current_parent.remove_child(self)

	if is_instance_valid(scene_root):
		scene_root.add_child(self)

	# Place it safely at the player's feet
	global_position = drop_pos
	transform.basis = Basis.IDENTITY

	# Re-enable physics so it can be picked up again
	freeze = false
	collision_layer = 1
	collision_mask = 1
