## Manages player item picking, throwing, inventory anchoring, and scanner routing.
class_name PlayerInteractionComponent
extends Node

## Minimum mass in kilograms required for an object to be considered heavy.
const HEAVY_OBJECT_MASS_THRESHOLD: float = 10.0

## Cooldown duration in milliseconds after dropping before re-grab is allowed.
const DROP_REPICK_COOLDOWN_MSEC: int = 400

## Maximum distance in meters for acquiring a wolf claw attack target.
const CLAW_ATTACK_RANGE: float = 10.0

## Squared maximum distance in meters for acquiring a wolf claw attack target.
const CLAW_ATTACK_RANGE_SQ: float = 100.0

## Minimum dot product between camera forward and target (approx 35 deg cone).
const CLAW_AIM_DOT_THRESHOLD: float = 0.819

## Lunge travel speed in meters per second during wolf claw attack.
const CLAW_LUNGE_SPEED: float = 35.0

## Damage dealt by wolf claw lunge attack.
const CLAW_ATTACK_DAMAGE: int = 100

## Candidate groups queried when scanning for wolf claw targets.
const CLAW_TARGET_GROUPS: Array[StringName] = [&"enemy", &"enemies"]

@export_category("Item Handling")
## Impulse force magnitude applied when throwing a held physical item.
@export var throw_strength: float = 15.0

@export_category("Node References")
## Shape cast used for detecting short-range physics items to grab.
@export var interact_cast: ShapeCast3D

## Marker indicating anchor point for picked-up items in front of player.
@export var hold_position: Marker3D

## Socket node holding equipped weapons and tools for the player.
@export var weapon_holder: Node3D

## Reference to the primary player camera node.
@export var camera: Camera3D

## Reference to the [InteractionScanner] sub-component.
@export var interaction_scanner: InteractionScanner

## Injected reference to the player's [WeaponInventoryComponent].
@export var weapon_inventory: WeaponInventoryComponent

## Reference to the parent [CharacterBody3D] character entity.
var player: CharacterBody3D = null

## The [RigidBody3D] currently carried by the player.
var held_item: RigidBody3D = null:
	set(value):
		var changed: bool = held_item != value
		held_item = value
		if changed:
			var is_holding: bool = is_instance_valid(held_item)
			print("InteractionComponent: Held item state changed -> ", is_holding)
			Events.held_item_changed.emit(is_holding)

## Indicates whether the player is currently operating fixed machinery.
var is_operating_machine: bool = false

## Tracks if a carried object or lifting state restricts sprint and jump.
var is_heavy_carrying: bool = false

## Indicates whether the player is carrying a heavy two-handed object.
var is_heavy_lifting: bool = false:
	set(value):
		is_heavy_lifting = value
		update_heavy_carry_state()

## Yaw heading baseline used for heavy lifting rotation clamping.
var heavy_lift_yaw_base: float = 0.0

## Indicates whether terminal focus mode is currently active.
var is_in_terminal_mode: bool = false

## Currently locked hostile target [Node3D] for wolf claw attack.
var current_claw_target: Node3D = null

## Timestamp in milliseconds of the last grab execution.
var _last_grab_time: int = 0

## Timestamp in milliseconds of the last drop execution to debounce re-grabs.
var _last_drop_time: int = 0

## Tracks whether a wolf claw lunge tween is actively executing.
var _is_claw_lunging: bool = false

## Active managed tween driving wolf claw lunge motion.
var _claw_lunge_tween: Tween = null

## Reusable RID exclusion array for wolf claw line-of-sight raycasts.
var _claw_exclude_rids: Array[RID] = []

## Reusable transition payload dictionary for claw lunge air state transition.
var _claw_transition_msg: Dictionary = {&"jump": true}


## Initializes component, caches player, and binds scanner and event listeners.
func initialize(p_player: CharacterBody3D) -> void:
	print("InteractionComponent: initialize() called. Caching player reference.")
	player = p_player

	if not is_instance_valid(weapon_inventory) and is_instance_valid(player):
		if "weapon_inventory" in player:
			var raw_inv: Variant = player.get("weapon_inventory")
			if raw_inv is WeaponInventoryComponent:
				weapon_inventory = raw_inv
		if not is_instance_valid(weapon_inventory):
			var found_inv: Node = NodeQuery.find_first_child_of_type(
				player, WeaponInventoryComponent
			)
			if found_inv is WeaponInventoryComponent:
				weapon_inventory = found_inv

	if (
		is_instance_valid(interaction_scanner)
		and interaction_scanner.has_method(&"setup_master_link")
	):
		interaction_scanner.setup_master_link(self)

	Utilities.safe_connect(Events.item_dropped, _on_global_item_dropped)


## Evaluates physics frame tick updates and polls action inputs consistently.
func process_interaction(delta: float) -> void:
	if is_instance_valid(interaction_scanner):
		interaction_scanner.process_interaction(delta)

	_process_wolf_claw_targeting()

	if is_instance_valid(held_item):
		var is_throw_triggered: bool = (
			GestureInputManager.consume_buffered_action("shoot")
			or GestureInputManager.consume_buffered_action("grenade_throw")
		)

		if is_throw_triggered:
			print("InteractionComponent: Throw input validated. Throwing item.")
			throw_held_item()
			return

	var is_interact_triggered: bool = GestureInputManager.consume_buffered_action("interact")

	if is_interact_triggered:
		if is_instance_valid(held_item):
			if held_item is GliderItem and is_instance_valid(player) and not player.is_on_floor():
				return

			if Time.get_ticks_msec() - _last_grab_time < 200:
				return

			print("InteractionComponent: Interact pressed while holding. Drop.")
			drop_held_item()
			return

		var time_since_drop: int = Time.get_ticks_msec() - _last_drop_time
		if time_since_drop < DROP_REPICK_COOLDOWN_MSEC:
			return

		if _try_pick_up():
			return

		if is_instance_valid(interaction_scanner):
			print("InteractionComponent: Forwarding interact to scanner.")
			interaction_scanner.handle_interact_input()
			return

	if not is_instance_valid(held_item):
		var is_grenade_triggered: bool = GestureInputManager.consume_buffered_action(
			"grenade_throw"
		)
		if is_grenade_triggered and is_instance_valid(weapon_inventory):
			print("InteractionComponent: Quick grenade throw triggered.")
			weapon_inventory.quick_throw_grenade()

		var is_shoot_triggered: bool = GestureInputManager.consume_buffered_action("shoot")
		if is_shoot_triggered:
			print("InteractionComponent: Processing shoot trigger.")
			if is_instance_valid(player) and player.get(&"is_wolf_mode") == true:
				if is_instance_valid(current_claw_target) and not _is_claw_lunging:
					_execute_claw_lunge(current_claw_target)
				return
			if is_instance_valid(weapon_inventory):
				weapon_inventory.shoot_active_weapon()
			elif is_instance_valid(interaction_scanner):
				interaction_scanner.handle_shoot_input()

		var is_reload_triggered: bool = GestureInputManager.consume_buffered_action("reload")
		if is_reload_triggered:
			print("InteractionComponent: Processing reload trigger.")
			if is_instance_valid(weapon_inventory):
				weapon_inventory.reload_active_weapon()
			elif is_instance_valid(interaction_scanner):
				interaction_scanner.handle_reload_input()


## Evaluates unhandled input events for gesture-resolved input routing.
func process_unhandled_input(_event: InputEvent = null) -> void:
	pass


## Attempts to detect and grab a nearby physics item using [NodeQuery].
func _try_pick_up() -> bool:
	var time_since_drop: int = Time.get_ticks_msec() - _last_drop_time
	if time_since_drop < DROP_REPICK_COOLDOWN_MSEC:
		return false

	interact_cast.force_shapecast_update()
	if interact_cast.is_colliding():
		for i: int in range(interact_cast.get_collision_count()):
			var collider: Object = interact_cast.get_collider(i)
			if not (collider is Node3D):
				continue
			var target_body: Node3D = collider if collider is Node3D else null
			if target_body is Area3D:
				var parent_node: Node = target_body.get_parent()
				target_body = parent_node if parent_node is Node3D else null

			if not is_instance_valid(target_body):
				continue

			var root_node: Node3D = NodeQuery.resolve_interactable_root(target_body)
			if root_node is RigidBody3D and root_node.has_method(&"pick_up"):
				print("InteractionComponent: Short-range grab on ", root_node.name)
				var rb_root: RigidBody3D = root_node
				force_grab_item(rb_root)
				return true

			if target_body is RigidBody3D and target_body.has_method(&"pick_up"):
				print("InteractionComponent: Short-range grab on ", target_body.name)
				var rb_target: RigidBody3D = target_body
				force_grab_item(rb_target)
				return true

	return false


## Throws currently held physics object forward along camera orientation.
func throw_held_item() -> void:
	print("InteractionComponent: throw_held_item() called.")
	if not is_instance_valid(held_item):
		return

	_last_drop_time = Time.get_ticks_msec()
	var item_to_throw: RigidBody3D = held_item
	held_item = null
	update_heavy_carry_state()

	var throw_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	throw_dir.y += 0.2
	var throw_force: Vector3 = throw_dir.normalized() * throw_strength

	if item_to_throw.has_method(&"throw"):
		item_to_throw.call(&"throw", throw_force)
	elif item_to_throw.has_method(&"throw_item"):
		item_to_throw.call(&"throw_item", throw_force, get_tree().current_scene)


## Releases and drops currently held physics object down to the floor.
func drop_held_item() -> void:
	print("InteractionComponent: drop_held_item() called. Placing item on ground.")
	if not is_instance_valid(held_item):
		return

	_last_drop_time = Time.get_ticks_msec()
	var item_to_drop: RigidBody3D = held_item
	held_item = null
	update_heavy_carry_state()
	_check_glider_restore(item_to_drop)
	_set_weapon_active(true)

	if item_to_drop.has_method(&"drop"):
		item_to_drop.call(&"drop")
	elif item_to_drop.has_method(&"drop_item"):
		item_to_drop.call(&"drop_item", get_tree().current_scene, player.global_position)


## Clears hands and restores weapons when an item is dropped globally.
func _on_global_item_dropped(item: Node3D, actor: Node3D) -> void:
	if actor == player:
		print("InteractionComponent: Global drop received. Restoring weapons.")
		_last_drop_time = Time.get_ticks_msec()
		held_item = null
		update_heavy_carry_state()
		_check_glider_restore(item)
		_set_weapon_active(true)


## Clears tracking state for carried items and restores active weapons.
func force_clear_hands() -> void:
	print("InteractionComponent: force_clear_hands() called.")
	_last_drop_time = Time.get_ticks_msec()
	if is_instance_valid(held_item) and held_item.has_method(&"drop"):
		held_item.call(&"drop")
	held_item = null
	update_heavy_carry_state()
	_set_weapon_active(true)


## Restores player sprint capabilities and resets head yaw if the dropped item is a glider.
func _check_glider_restore(item: Node) -> void:
	if item is GliderItem or (item.has_method(&"is_class") and item.is_class("GliderItem")):
		print("InteractionComponent: Released GliderItem. Restoring sprint.")
		if is_instance_valid(player):
			var raw_cam: Variant = player.get(&"camera_controller")
			if raw_cam is CameraController:
				var cam_ctrl: CameraController = raw_cam
				if cam_ctrl.has_method(&"reset_head_yaw"):
					cam_ctrl.reset_head_yaw()
				elif is_instance_valid(cam_ctrl.head):
					cam_ctrl.head.rotation.y = 0.0

			if "locomotion_component" in player:
				var raw_loco: Variant = player.get(&"locomotion_component")
				if raw_loco is PlayerLocomotionComponent:
					var locomotion: PlayerLocomotionComponent = raw_loco
					locomotion.can_sprint = true
					locomotion.set_direction(Vector3.ZERO)
		is_heavy_lifting = false


## Enables or disables active weapon holder visibility and processing.
func _set_weapon_active(active: bool) -> void:
	if is_instance_valid(weapon_holder):
		print("InteractionComponent: Setting weapon active state to: ", active)
		weapon_holder.visible = active
		weapon_holder.set_process(active)
		weapon_holder.set_physics_process(active)


## Synchronizes heavy carry state, updates movement, and emits event signal.
func update_heavy_carry_state() -> void:
	var is_heavy: bool = (
		is_heavy_lifting
		or (is_instance_valid(held_item) and held_item.mass >= HEAVY_OBJECT_MASS_THRESHOLD)
	)
	if is_heavy_carrying != is_heavy:
		is_heavy_carrying = is_heavy
		print("InteractionComponent: Heavy carry toggled -> ", is_heavy_carrying)
		if is_instance_valid(player) and "locomotion_component" in player:
			var raw_loco: Variant = player.get("locomotion_component")
			if raw_loco is PlayerLocomotionComponent:
				var locomotion: PlayerLocomotionComponent = raw_loco
				locomotion.can_sprint = not is_heavy_carrying
				locomotion.can_jump = not is_heavy_carrying
		Events.heavy_carry_toggled.emit(is_heavy_carrying)


## Directly forces the player to grab and hold a designated physics object.
func force_grab_item(item: RigidBody3D) -> void:
	print("InteractionComponent: force_grab_item() taking ownership of ", item.name)
	if is_instance_valid(held_item):
		drop_held_item()

	held_item = item
	_last_grab_time = Time.get_ticks_msec()
	update_heavy_carry_state()

	if held_item.has_method(&"pick_up"):
		held_item.call(&"pick_up", hold_position, player)

	_set_weapon_active(false)


## Attaches an item to the weapon holder socket using [Utilities].
func attach_item_to_weapon_holder(
	item: Node3D, item_anchor: Marker3D, p_player: CharacterBody3D = null
) -> void:
	print("InteractionComponent: attach_item_to_weapon_holder() reparenting item.")
	Utilities.reparent_keep_transform(item, weapon_holder, true)

	var offset: Vector3 = item.global_position - item_anchor.global_position
	item.global_position = hold_position.global_position + offset
	item.transform.basis = Basis.IDENTITY

	var target_player: CharacterBody3D = p_player if p_player != null else player
	if is_instance_valid(target_player) and "locomotion_component" in target_player:
		var raw_loco: Variant = target_player.get("locomotion_component")
		if raw_loco is PlayerLocomotionComponent:
			var locomotion: PlayerLocomotionComponent = raw_loco
			locomotion.can_sprint = false


## Sets heavy lifting state, restricts player sprint, and emits global event.
func _set_heavy_lifting(active: bool) -> void:
	if is_heavy_lifting == active:
		return

	print("InteractionComponent: Setting heavy lifting state to: ", active)
	is_heavy_lifting = active

	if is_instance_valid(player) and "locomotion_component" in player:
		var raw_loco: Variant = player.get("locomotion_component")
		if raw_loco is PlayerLocomotionComponent:
			var locomotion: PlayerLocomotionComponent = raw_loco
			locomotion.can_sprint = not active

	Events.heavy_carry_toggled.emit(active)


## Scans nearby hostile entities in wolf mode and updates claw mark UI.
func _process_wolf_claw_targeting() -> void:
	if not is_instance_valid(player) or not is_instance_valid(camera):
		_clear_claw_target()
		return

	var is_wolf: bool = player.get(&"is_wolf_mode") == true
	if not is_wolf or _is_claw_lunging:
		_clear_claw_target()
		return

	var best_target: Node3D = _find_best_claw_target()
	current_claw_target = best_target
	if is_instance_valid(current_claw_target):
		var center_pos: Vector3 = _get_target_center(current_claw_target)
		Events.claw_target_updated.emit(true, center_pos)
	else:
		Events.claw_target_updated.emit(false, Vector3.ZERO)


## Clears active wolf claw target and hides the HUD mark.
func _clear_claw_target() -> void:
	if current_claw_target != null:
		current_claw_target = null
		Events.claw_target_updated.emit(false, Vector3.ZERO)


## Evaluates candidate enemies within proximity, view cone, and line of sight.
func _find_best_claw_target() -> Node3D:
	if not is_inside_tree():
		return null

	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree):
		return null

	var player_pos: Vector3 = player.global_position
	var cam_pos: Vector3 = camera.global_position
	var cam_fwd: Vector3 = -camera.global_transform.basis.z.normalized()
	var player_fc: FactionComponent = FactionComponent.get_faction_component(player)

	var best_node: Node3D = null
	var best_score: float = -1.0

	for grp: StringName in CLAW_TARGET_GROUPS:
		var nodes: Array[Node] = tree.get_nodes_in_group(grp)
		for raw_node: Node in nodes:
			var candidate: Node3D = raw_node as Node3D
			if not is_instance_valid(candidate) or not candidate.visible:
				continue
			if candidate.get(&"_is_dead") == true:
				continue

			var target_fc: FactionComponent = FactionComponent.get_faction_component(candidate)
			if not _is_valid_hostile_target(player_fc, target_fc):
				continue

			var target_center: Vector3 = _get_target_center(candidate)
			var dist_sq: float = player_pos.distance_squared_to(target_center)
			if dist_sq > CLAW_ATTACK_RANGE_SQ or dist_sq < 0.01:
				continue

			var dir_to_target: Vector3 = cam_pos.direction_to(target_center)
			var aim_dot: float = cam_fwd.dot(dir_to_target)
			if aim_dot < CLAW_AIM_DOT_THRESHOLD:
				continue

			if not _has_claw_line_of_sight(cam_pos, target_center, candidate):
				continue

			var score: float = aim_dot - (dist_sq / CLAW_ATTACK_RANGE_SQ) * 0.25
			if score > best_score:
				best_score = score
				best_node = candidate

	return best_node


## Verifies hostility between player and candidate target via [FactionComponent].
func _is_valid_hostile_target(player_fc: FactionComponent, target_fc: FactionComponent) -> bool:
	if not is_instance_valid(target_fc) or target_fc.is_passive:
		return false
	if is_instance_valid(player_fc):
		return player_fc.is_hostile_to(target_fc) or target_fc.is_hostile_to(player_fc)
	return target_fc.faction == Types.Faction.ENEMY


## Computes the 3D torso/center coordinate of a candidate enemy.
func _get_target_center(target: Node3D) -> Vector3:
	var mesh_inst: MeshInstance3D = target.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if is_instance_valid(mesh_inst):
		var aabb: AABB = mesh_inst.get_aabb()
		return mesh_inst.to_global(aabb.get_center())
	return target.global_position


## Raycasts from camera to target center to verify unobstructed line of sight.
func _has_claw_line_of_sight(from_pos: Vector3, to_pos: Vector3, target: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	if not is_instance_valid(space):
		return false

	_claw_exclude_rids.clear()
	_claw_exclude_rids.append(player.get_rid())

	var mask: int = (
		CollisionLayers.MASK_ENVIRONMENT
		| CollisionLayers.MASK_INTERACTIVE
		| CollisionLayers.MASK_ENEMIES
	)
	var hit: Dictionary = NodeQuery.cast_ray(space, from_pos, to_pos, mask, _claw_exclude_rids)
	if hit.is_empty():
		return true

	var collider: Object = hit.get("collider")
	if collider == target:
		return true
	if collider is Node:
		var hit_node: Node = collider as Node
		return target.is_ancestor_of(hit_node) or hit_node.is_ancestor_of(target)
	return false


## Flies player rapidly toward [param target] and deals 100 claw damage on arrival.
func _execute_claw_lunge(target: Node3D) -> void:
	if not is_instance_valid(player) or not is_instance_valid(target):
		return

	print("InteractionComponent: Executing wolf claw lunge on ", target.name)
	_is_claw_lunging = true
	Events.claw_target_updated.emit(false, Vector3.ZERO)

	var start_pos: Vector3 = player.global_position
	var target_center: Vector3 = _get_target_center(target)
	var to_target: Vector3 = target_center - start_pos
	var dist: float = to_target.length()
	var attack_dir: Vector3 = to_target.normalized() if dist > 0.01 else Vector3.FORWARD
	var arrival_pos: Vector3 = target_center - (attack_dir * 1.1)
	arrival_pos.y = maxf(arrival_pos.y - 0.8, target.global_position.y - 0.8)

	var duration: float = clampf(dist / CLAW_LUNGE_SPEED, 0.06, 0.35)
	player.velocity = Vector3.ZERO

	_claw_lunge_tween = Utilities.reset_tween(self, _claw_lunge_tween)
	if not is_instance_valid(_claw_lunge_tween):
		_apply_claw_strike_damage(target, target_center, attack_dir)
		_is_claw_lunging = false
		return

	_claw_lunge_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	(
		_claw_lunge_tween
		. tween_property(player, "global_position", arrival_pos, duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_claw_lunge_tween.tween_callback(
		func() -> void:
			_apply_claw_strike_damage(target, target_center, attack_dir)
			_is_claw_lunging = false
			if is_instance_valid(player):
				player.velocity = (-attack_dir * 4.0) + Vector3(0.0, 4.5, 0.0)
				var raw_sm: Variant = player.get(&"state_machine")
				if raw_sm is StateMachine and is_instance_valid(raw_sm):
					var sm: StateMachine = raw_sm
					sm.transition_to(&"Air", _claw_transition_msg)
	)


## Applies 100 damage to [param target] via take_damage or [HealthComponent].
func _apply_claw_strike_damage(target: Node3D, hit_pos: Vector3, attack_dir: Vector3) -> void:
	if not is_instance_valid(target):
		return

	print("InteractionComponent: Claw strike landed on ", target.name, " for 100 damage.")
	if target.has_method(&"take_damage"):
		target.call(&"take_damage", CLAW_ATTACK_DAMAGE, hit_pos, attack_dir)
		return

	var raw_hc: Variant = target.get(&"health_component")
	if raw_hc is HealthComponent and is_instance_valid(raw_hc):
		var hc: HealthComponent = raw_hc
		hc.take_damage(CLAW_ATTACK_DAMAGE)
		return

	var child_hc: Node = NodeQuery.find_first_child_of_type(target, HealthComponent)
	if child_hc is HealthComponent and is_instance_valid(child_hc):
		var found_hc: HealthComponent = child_hc
		found_hc.take_damage(CLAW_ATTACK_DAMAGE)
