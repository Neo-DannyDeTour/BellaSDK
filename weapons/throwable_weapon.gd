## Base class for throwable weapons managing inventory slots, stacking, and physics launch.
class_name ThrowableWeapon
extends Node3D

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when ammunition count changes. Passes current, reserve, and max capacity.
signal ammo_updated(current: int, reserve: int, maximum: int)

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Default inventory slot index assigned to throwable ordnance.
const DEFAULT_THROWABLE_SLOT: int = 4

## Maximum held capacity for stacked throwables.
const DEFAULT_MAX_AMMO: int = 3

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Throwable Properties")
## Unique string identifier sent with weapon tag events.
@export var weapon_tag: String = "throwable"

## Preferred inventory slot number ranging from 1 to 5.
@export var default_slot: int = DEFAULT_THROWABLE_SLOT

## Packed scene instantiated and launched into the world on throw.
@export var projectile_scene: PackedScene

## Forward impulse speed in meters per second applied to thrown projectile.
@export var throw_speed: float = 16.0

## Upward arc boost in meters per second applied to thrown projectile.
@export var upward_boost: float = 2.5

## Minimum interval duration between throws in seconds.
@export_range(0.1, 3.0, 0.05) var fire_rate: float = 0.8

## Dedicated 3D audio player for throw release sound effects.
@export var throw_audio: AudioStreamPlayer3D

@export_category("Ammunition")
## Ammunition identifier matching ammo pickups.
@export var ammo_type: StringName = &"throwable"

## Current number of held throwables available.
@export var current_ammo: int = 1

## Maximum number of throwables the player can carry in this stack.
@export var max_ammo: int = DEFAULT_MAX_AMMO

@export_category("Interaction Prompt")
## Floating 3D label rendering equip and grab instructions.
@export var label: Label3D

## Sprite display rendering hardware button prompt icon.
@export var prompt_icon: Sprite3D

# --------------------------------------
# PUBLIC VARIABLES
# --------------------------------------
## Active equipping state flag.
var is_equipped: bool = false

## Millisecond timestamp when weapon was last thrown.
var last_throw_time: float = -1000.0

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------
## Toggle state governing item text prompt visibility.
var _show_text_prompts: bool = true

## Cached array of RIDs excluded from clearance raycasts.
var _excluded_rids: Array[RID] = []

# --------------------------------------
# ONREADY VARIABLES
# --------------------------------------
## Reference to muzzle marker node.
@onready var muzzle_point: Marker3D = get_node_or_null("MuzzlePoint") as Marker3D

## Interaction component trigger node.
@onready var interact_comp: InteractComponent = (
	get_node_or_null("StaticBody3D/InteractComponent") as InteractComponent
)

## Physical collider body representing the pickup in the world.
@onready var static_body: StaticBody3D = get_node_or_null("StaticBody3D") as StaticBody3D


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Binds interaction signals, caches UI nodes, and hides world prompts.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	print(weapon_tag, ": ThrowableWeapon _ready() called.")

	if not is_instance_valid(label):
		label = get_node_or_null("Label3D") as Label3D
	if not is_instance_valid(prompt_icon):
		prompt_icon = get_node_or_null("PromptIcon") as Sprite3D

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()

	var settings_node: Node = get_node_or_null("/root/GlobalSettings")
	if is_instance_valid(settings_node) and settings_node.has_method("get_setting"):
		var prompt_setting: Variant = settings_node.call(
			"get_setting", "Gameplay", "show_item_prompts", true
		)
		if typeof(prompt_setting) == TYPE_BOOL:
			_show_text_prompts = prompt_setting

	if Events.has_signal("item_prompts_toggled"):
		Utilities.safe_connect(Events.item_prompts_toggled, _on_item_prompts_toggled)

	if is_instance_valid(interact_comp):
		Utilities.safe_connect(interact_comp.focused, _on_interact_focused)
		Utilities.safe_connect(interact_comp.unfocused, _on_interact_unfocused)
		Utilities.safe_connect(interact_comp.interacted, _on_interact_component_interacted)


## Disconnects global event listeners on tree exit.
func _exit_tree() -> void:
	if (
		Events.has_signal("item_prompts_toggled")
		and Events.item_prompts_toggled.is_connected(_on_item_prompts_toggled)
	):
		Events.item_prompts_toggled.disconnect(_on_item_prompts_toggled)


# --------------------------------------
# PUBLIC METHODS
# --------------------------------------
## Attaches weapon to player socket, registers with inventory, and hides world pickup collider.
func equip_to_player(player_body: CharacterBody3D) -> void:
	print(weapon_tag, ": Equipping throwable to player.")
	is_equipped = true

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()

	if is_instance_valid(static_body):
		static_body.process_mode = PROCESS_MODE_DISABLED
		static_body.visible = false

	var inv: WeaponInventoryComponent = null
	if is_instance_valid(player_body):
		inv = (
			player_body.find_child("WeaponInventoryComponent", true, false)
			as WeaponInventoryComponent
		)
		_excluded_rids = [player_body.get_rid()]

	if not is_instance_valid(inv):
		inv = (
			get_tree().root.find_child("WeaponInventoryComponent", true, false)
			as WeaponInventoryComponent
		)

	var weapon_holder: Node3D = null
	if is_instance_valid(inv) and is_instance_valid(inv.weapon_holder):
		weapon_holder = inv.weapon_holder
	elif is_instance_valid(player_body):
		weapon_holder = (player_body.find_child("WeaponHolder", true, false) as Node3D)

	if is_instance_valid(weapon_holder):
		reparent(weapon_holder, false)
		position = Vector3.ZERO
		rotation = Vector3.ZERO

	visible = false
	set_process(false)
	set_physics_process(false)

	if is_instance_valid(inv):
		print(weapon_tag, ": Found inventory -> registering in slot ", default_slot)
		inv.register_weapon(self)
	else:
		push_error("ThrowableWeapon: Missing WeaponInventoryComponent in scene!")

	Events.weapon_tag_displayed.emit(weapon_tag)
	sync_ammo_ui()


## Increments held ammunition count up to [member max_ammo] and updates HUD.
func add_grenade(amount: int = 1) -> bool:
	if current_ammo >= max_ammo:
		print(weapon_tag, ": Ammo stack already full.")
		return false

	var space_left: int = max_ammo - current_ammo
	var to_add: int = mini(amount, space_left)
	current_ammo += to_add
	print(weapon_tag, ": Added ", to_add, " grenade(s). Count: ", current_ammo, "/", max_ammo)
	sync_ammo_ui()
	return true


## Broadcasts current stacked count to the global event bus.
func sync_ammo_ui() -> void:
	print(weapon_tag, ": Syncing ammo UI. Count: ", current_ammo, " Max: ", max_ammo)
	ammo_updated.emit(current_ammo, 0, max_ammo)
	Events.weapon_ammo_changed.emit(current_ammo, 0, max_ammo)


## Primary throw entrypoint verifying rate limit, magazine count, and camera validity.
func shoot(player_camera: Camera3D) -> bool:
	print(weapon_tag, ": shoot() called for throwable.")
	if not is_equipped or not is_instance_valid(player_camera):
		return false

	var current_time: float = Time.get_ticks_msec()
	if current_time - last_throw_time < fire_rate * 1000.0:
		return false

	if current_ammo <= 0:
		print(weapon_tag, ": No throwables remaining in stack.")
		return false

	last_throw_time = current_time
	current_ammo -= 1

	_play_throw_audio()
	_spawn_projectile(player_camera)
	sync_ammo_ui()

	if current_ammo <= 0:
		_handle_depleted()

	return true


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
## Spawns physical projectile into the active world scene with forward impulse.
func _spawn_projectile(player_camera: Camera3D) -> void:
	if not is_instance_valid(projectile_scene):
		push_error("ThrowableWeapon: projectile_scene is not assigned!")
		return

	var inst: Node = projectile_scene.instantiate()
	var projectile: RigidBody3D = inst as RigidBody3D
	if not is_instance_valid(projectile):
		if is_instance_valid(inst):
			inst.queue_free()
		return

	var forward_dir: Vector3 = -player_camera.global_transform.basis.z.normalized()
	var cam_pos: Vector3 = player_camera.global_position
	var desired_pos: Vector3 = cam_pos + forward_dir * 0.65
	if is_instance_valid(muzzle_point):
		desired_pos = muzzle_point.global_position

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var spawn_pos: Vector3 = desired_pos

	if is_instance_valid(space_state):
		var hit: Dictionary = Utilities.raycast_3d(
			space_state, cam_pos, desired_pos, Types.MASK_SOLID_WORLD, _excluded_rids
		)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit.get("position", cam_pos)
			var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
			spawn_pos = hit_pos + hit_normal * 0.12

	var scene_root: Node = get_tree().current_scene
	if not is_instance_valid(scene_root):
		scene_root = get_tree().root
	scene_root.add_child(projectile)
	projectile.global_position = spawn_pos
	projectile.linear_velocity = (forward_dir * throw_speed) + (Vector3.UP * upward_boost)
	projectile.angular_velocity = Vector3(4.0, 1.5, -2.0)
	print(weapon_tag, ": Launched projectile safely at ", spawn_pos)


## Plays throw audio effect through throttled audio manager.
func _play_throw_audio() -> void:
	if not is_instance_valid(throw_audio) or throw_audio.stream == null:
		return

	var spawn_pos: Vector3 = (
		muzzle_point.global_position if is_instance_valid(muzzle_point) else global_position
	)
	var audio_mgr: Node = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_mgr) and audio_mgr.has_method("play_sfx_3d_throttled"):
		audio_mgr.call("play_sfx_3d_throttled", throw_audio.stream, spawn_pos, throw_audio.bus)
	else:
		throw_audio.play()


## Swaps player to previous weapon when ammunition reaches zero.
func _handle_depleted() -> void:
	print(weapon_tag, ": Ammunition depleted -> auto-swapping to previous weapon.")
	var inv: WeaponInventoryComponent = _find_inventory(null)
	if is_instance_valid(inv):
		inv.swap_to_previous()


## Handles world interaction: stacks into existing weapon or equips into inventory.
func _on_interact_component_interacted(player_body: CharacterBody3D = null) -> void:
	print(weapon_tag, ": Interaction triggered on world pickup.")
	if is_equipped:
		return

	var target_player: CharacterBody3D = player_body
	if not is_instance_valid(target_player):
		target_player = (get_tree().get_first_node_in_group("player") as CharacterBody3D)

	if not is_instance_valid(target_player):
		return

	var inv: WeaponInventoryComponent = _find_inventory(target_player)
	if not is_instance_valid(inv):
		equip_to_player(target_player)
		return

	var existing_throwable: ThrowableWeapon = _find_matching_throwable(inv)
	if is_instance_valid(existing_throwable):
		if existing_throwable.current_ammo < existing_throwable.max_ammo:
			var added: bool = existing_throwable.add_grenade(current_ammo)
			if added:
				print(weapon_tag, ": Consuming world pickup into existing inventory stack.")
				if is_instance_valid(Events) and Events.has_signal("weapon_tag_displayed"):
					Events.weapon_tag_displayed.emit(weapon_tag)
				queue_free()
		else:
			print(weapon_tag, ": Player inventory already at maximum ammo capacity.")
	else:
		equip_to_player(target_player)


## Updates prompt labels and hardware icons when crosshair focuses pickup.
func _on_interact_focused() -> void:
	print(weapon_tag, ": Focus gained.")
	if is_equipped:
		return

	_update_label_text()
	if is_instance_valid(label) and _show_text_prompts:
		label.show()
	if is_instance_valid(prompt_icon) and prompt_icon.texture != null:
		prompt_icon.show()


## Hides prompt visual elements when crosshair moves away.
func _on_interact_unfocused() -> void:
	print(weapon_tag, ": Focus lost.")
	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()


## Formats prompt string dynamically matching controls and inventory capacity.
func _update_label_text() -> void:
	var key_name: String = "E"
	var icon_tex: Texture2D = null

	var input_helper_node: Node = get_node_or_null("/root/InputHelper")
	if is_instance_valid(input_helper_node):
		if input_helper_node.has_method("get_action_key_label"):
			var raw_key: Variant = input_helper_node.call("get_action_key_label", &"interact")
			if typeof(raw_key) == TYPE_STRING:
				var parsed_key: String = str(raw_key)
				if not parsed_key.is_empty():
					key_name = parsed_key

		var events: Array[InputEvent] = InputMap.action_get_events(&"interact")
		if not events.is_empty() and input_helper_node.has_method("get_event_icon"):
			var icon_val: Variant = input_helper_node.call("get_event_icon", events[0])
			if icon_val is Texture2D:
				icon_tex = icon_val

	if is_instance_valid(prompt_icon):
		prompt_icon.texture = icon_tex
		prompt_icon.visible = (icon_tex != null)

	var inv: WeaponInventoryComponent = _find_inventory(null)
	var existing: ThrowableWeapon = (
		_find_matching_throwable(inv) if is_instance_valid(inv) else null
	)
	var is_full: bool = is_instance_valid(existing) and existing.current_ammo >= existing.max_ammo

	if is_instance_valid(label):
		if is_full:
			label.text = "Full (%d/%d)" % [existing.current_ammo, existing.max_ammo]
			if is_instance_valid(prompt_icon):
				prompt_icon.hide()
		else:
			label.text = "Press [%s] to grab" % key_name
			if icon_tex != null and is_instance_valid(prompt_icon):
				label.text = "Press    to grab"
				prompt_icon.position.x = 0.0
				prompt_icon.position.y = label.position.y
		label.position.x = 0.0


## Updates prompt visibility when menu setting is modified.
func _on_item_prompts_toggled(enabled: bool) -> void:
	_show_text_prompts = enabled
	if not _show_text_prompts and is_instance_valid(label):
		label.hide()


## Locates the player's [WeaponInventoryComponent] from scene tree.
func _find_inventory(player_node: CharacterBody3D) -> WeaponInventoryComponent:
	if is_instance_valid(player_node):
		var player_inv: Node = player_node.find_child("WeaponInventoryComponent", true, false)
		if player_inv is WeaponInventoryComponent:
			return player_inv as WeaponInventoryComponent

	var root_inv: Node = get_tree().root.find_child("WeaponInventoryComponent", true, false)
	if root_inv is WeaponInventoryComponent:
		return root_inv as WeaponInventoryComponent
	return null


## Finds registered [ThrowableWeapon] in inventory matching this weapon's [member ammo_type].
func _find_matching_throwable(inv: WeaponInventoryComponent) -> ThrowableWeapon:
	if not is_instance_valid(inv):
		return null

	for w: Node3D in inv.slots:
		if is_instance_valid(w) and w is ThrowableWeapon:
			var candidate: ThrowableWeapon = w as ThrowableWeapon
			if candidate.ammo_type == ammo_type or candidate.weapon_tag == weapon_tag:
				return candidate
	return null
