## A 3D weapon component that fires a spread of raycast pellets.
##
## Manages its own equip logic, rate-of-fire, environmental impact effects,
## and prompt UI rendering.
class_name Shotgun
extends Node3D

## Preloaded debug pellet scene for visual hit confirmation.
const DEBUG_PELLET: PackedScene = preload("res://ui/debug_pellet.tscn")
## Preloaded dust puff scene for surface impacts.
const DUST_PUFF: PackedScene = preload("res://vfx/dust_puff.tscn")

## The number of pellets fired per shot.
@export var pellet_count: int = 8
## The spread angle in degrees for the pellets.
@export var spread_angle: float = 4.0
## The damage inflicted by each individual pellet.
@export var damage_per_pellet: int = 10
## The maximum range a pellet can travel.
@export var max_range: float = 50.0
## The time in seconds between consecutive shots.
@export var fire_rate: float = 1.0
## The AudioStreamPlayer3D used to play the firing sound.
@export var shotgun_fire: AudioStreamPlayer3D

@export_category("Interaction Prompt")
## The floating label displaying the interaction key prompt.
@export var label: Label3D
## The 3D sprite rendering the active input button icon.
@export var prompt_icon: Sprite3D

## The timestamp of the last fired shot, used for rate limiting.
var last_shot_time: float = -1000.0
## Indicates whether the shotgun is currently equipped by a player.
var is_equipped: bool = false
## Indicates whether text prompt labels are displayed over focused objects.
var _show_text_prompts: bool = true

## Reference to the muzzle marker for trajectory origins.
@onready var muzzle_point: Marker3D = $MuzzlePoint
## The child interaction component resolving hover and pickup events.
@onready var interact_comp: InteractComponent = (
	get_node_or_null("StaticBody3D/InteractComponent") as InteractComponent
)


## Initializes child references, signal hooks, and prompt settings.
func _ready() -> void:
	print("Shotgun: _ready() called. Initializing shotgun.")
	if not is_instance_valid(label):
		label = get_node_or_null("Label3D") as Label3D
	if not is_instance_valid(prompt_icon):
		prompt_icon = get_node_or_null("PromptIcon") as Sprite3D

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()

	_show_text_prompts = (GlobalSettings.get_setting("Gameplay", "show_item_prompts", true) as bool)

	if Events.has_signal("item_prompts_toggled"):
		if not Events.item_prompts_toggled.is_connected(_on_item_prompts_toggled):
			Events.item_prompts_toggled.connect(_on_item_prompts_toggled)

	if is_instance_valid(interact_comp):
		if not interact_comp.focused.is_connected(_on_interact_focused):
			interact_comp.focused.connect(_on_interact_focused)
		if not interact_comp.unfocused.is_connected(_on_interact_unfocused):
			interact_comp.unfocused.connect(_on_interact_unfocused)
		if not interact_comp.interacted.is_connected(_on_interact_component_interacted):
			interact_comp.interacted.connect(_on_interact_component_interacted)


## Updates prompt visibility setting when changed in the settings menu.
func _on_item_prompts_toggled(enabled: bool) -> void:
	print("Shotgun: Item prompt visibility updated -> ", enabled)
	_show_text_prompts = enabled
	if not _show_text_prompts and is_instance_valid(label):
		label.hide()


## Equips the weapon to [param p_node], reparenting and disabling physics.
func equip_to_player(p_node: CharacterBody3D) -> void:
	print("Shotgun: equip_to_player() called. Equipping shotgun to player.")
	is_equipped = true

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()

	var physics_body: StaticBody3D = get_node_or_null("StaticBody3D") as StaticBody3D
	if is_instance_valid(physics_body):
		physics_body.process_mode = PROCESS_MODE_DISABLED
		physics_body.visible = false

	var weapon_holder: Node = p_node.get_node_or_null("%WeaponHolder")
	if is_instance_valid(weapon_holder):
		reparent(weapon_holder, false)
		position = Vector3.ZERO
		rotation = Vector3.ZERO

	Events.weapon_tag_displayed.emit("shotgun")


## Fires pellets from [param player_camera], evaluating hits and damage.
func shoot(player_camera: Camera3D) -> void:
	print("Shotgun: shoot() called by player.")

	if not is_equipped:
		return

	var current_time: float = Time.get_ticks_msec()
	if current_time - last_shot_time < fire_rate * 1000.0:
		return

	last_shot_time = current_time

	if is_instance_valid(shotgun_fire):
		print("Shotgun: Playing fire sound.")
		shotgun_fire.play()

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = player_camera.global_position
	var forward_dir: Vector3 = -player_camera.global_transform.basis.z.normalized()
	var cam_right: Vector3 = player_camera.global_transform.basis.x.normalized()
	var cam_up: Vector3 = player_camera.global_transform.basis.y.normalized()

	var atmos_manager: Node = get_node_or_null("/root/SmokeManager")
	if atmos_manager and atmos_manager.has_method("add_bullet_hole"):
		print("Shotgun: Sending forward_dir to atmospheric SmokeManager.")
		atmos_manager.add_bullet_hole(origin, forward_dir, max_range, 4.5)

	var grenade_manager: Node = get_node_or_null("/root/SmokeGrenadeManager")
	if grenade_manager and grenade_manager.has_method("process_bullet_trajectory"):
		print("Shotgun: Sending trajectory to SmokeGrenadeManager.")
		var end_pos: Vector3 = origin + (forward_dir * max_range)
		grenade_manager.process_bullet_trajectory(origin, end_pos, 4.5)
	else:
		print("Shotgun: Could not find process_bullet_trajectory on manager.")

	for i: int in range(pellet_count):
		var rand_x: float = deg_to_rad(randf_range(-spread_angle, spread_angle))
		var rand_y: float = deg_to_rad(randf_range(-spread_angle, spread_angle))
		var pellet_dir: Vector3 = forward_dir.rotated(cam_right, rand_y).rotated(cam_up, rand_x)
		var end_point: Vector3 = origin + (pellet_dir * max_range)

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, end_point
		)
		query.exclude = [player_camera.owner.get_rid()]

		var result: Dictionary = space_state.intersect_ray(query)
		if result:
			var collider: Object = result.collider
			print("Shotgun: Pellet hit ", collider.name, " at ", result.position)

			if collider.has_method("take_damage"):
				collider.take_damage(damage_per_pellet, result.position, pellet_dir)
			elif collider is RigidBody3D:
				var hit_offset: Vector3 = (
					result.position - (collider as RigidBody3D).global_position
				)
				(collider as RigidBody3D).apply_impulse(pellet_dir * 2.0, hit_offset)

			if collider.has_method("_spawn_poker_at"):
				collider._spawn_poker_at(result.position, pellet_dir)
			elif collider.get_parent() and collider.get_parent().has_method("_spawn_poker_at"):
				collider.get_parent()._spawn_poker_at(result.position, pellet_dir)
			elif collider.get("owner") and collider.owner.has_method("_spawn_poker_at"):
				collider.owner._spawn_poker_at(result.position, pellet_dir)

			if collider.has_method("leak_at"):
				collider.leak_at(result.position)

			var pellet_instance: Node = DEBUG_PELLET.instantiate()
			var dot: Node3D = pellet_instance as Node3D
			if is_instance_valid(dot):
				get_tree().current_scene.add_child(dot)
				dot.global_position = result.position
			elif is_instance_valid(pellet_instance):
				pellet_instance.queue_free()


## Handles the interaction event to pick up and equip the weapon.
func _on_interact_component_interacted(player: CharacterBody3D = null) -> void:
	print("Shotgun: Interaction received. Equipping shotgun.")
	if is_equipped:
		return

	var target_player: CharacterBody3D = player
	if not is_instance_valid(target_player):
		target_player = (get_tree().get_first_node_in_group("player") as CharacterBody3D)

	if is_instance_valid(target_player):
		equip_to_player(target_player)


## Called when focused by the player interaction raycast.
func _on_interact_focused() -> void:
	print("Shotgun: Focus gained. Showing prompt UI.")
	if is_equipped:
		return

	_update_label_text()
	if is_instance_valid(label) and _show_text_prompts:
		label.show()
	if is_instance_valid(prompt_icon) and prompt_icon.texture != null:
		prompt_icon.show()


## Called when the player crosshair looks away from the shotgun.
func _on_interact_unfocused() -> void:
	print("Shotgun: Focus lost. Hiding prompt UI.")
	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()


## Formats the floating [Label3D] and [Sprite3D] icon using the [InputHelper] autoload.
func _update_label_text() -> void:
	print("Shotgun: _update_label_text() called. Updating visual prompts.")
	var events: Array[InputEvent] = InputMap.action_get_events("interact")
	var key_name: String = "???"
	var icon_tex: Texture2D = null

	if not events.is_empty():
		var primary_event: InputEvent = events[0]
		key_name = InputHelper.sanitize_key_name(primary_event.as_text())
		icon_tex = InputHelper.get_event_icon(primary_event)

	if is_instance_valid(prompt_icon):
		prompt_icon.texture = icon_tex
		prompt_icon.visible = (icon_tex != null)

	if is_instance_valid(label):
		if icon_tex != null:
			label.text = "Press   to equip"
			label.position.x = 0.0

			if is_instance_valid(prompt_icon):
				prompt_icon.position.x = 0.0
				prompt_icon.position.y = label.position.y
		else:
			label.text = "Press [%s] to equip" % key_name
			label.position.x = 0.0
