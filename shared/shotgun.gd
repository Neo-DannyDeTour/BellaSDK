class_name Shotgun
extends Node3D

# Preload the dot so it's ready in memory the moment we shoot
const DEBUG_PELLET = preload("res://ui/debug_pellet.tscn")
const DUST_PUFF = preload("res://vfx/dust_puff.tscn")

@export var pellet_count: int = 8
@export var spread_angle: float = 4.0  # Degrees of spread
@export var damage_per_pellet: int = 10
@export var max_range: float = 50.0
@export var fire_rate: float = 1.0  # Seconds between shots
@export var shotgun_fire: AudioStreamPlayer3D

var last_shot_time: float = -1000.0

var is_equipped: bool = false

#@onready var anim: AnimationPlayer = $ShotgunAnim
@onready var muzzle_point: Marker3D = $MuzzlePoint


func _ready() -> void:
	pass


# --- EQUIP LOGIC ---
func equip_to_player(p_node: CharacterBody3D) -> void:
	is_equipped = true

	# 1. FIND THE PHYSICS BODY (StaticBody3D or RigidBody3D)
	# If your Interact_Component is a child of the StaticBody,
	# we grab the parent of the component.
	var physics_body := get_node("StaticBody3D")  # Update path if named differently

	# 2. DISABLE IT COMPLETELY
	if physics_body:
		# This stops the "launching" glitch
		physics_body.process_mode = PROCESS_MODE_DISABLED
		physics_body.visible = false  # Optional: hide the interaction helper

	# 3. REPARENT AS NORMAL
	var weapon_holder := p_node.get_node("%WeaponHolder")
	if weapon_holder:
		reparent(weapon_holder, false)
		position = Vector3.ZERO
		rotation = Vector3.ZERO


# --- SHOOT LOGIC (The Pro Way) ---
func shoot(player_camera: Camera3D) -> void:
	print("Shotgun: shoot() called by player.")

	if not is_equipped:
		return

	var current_time: float = Time.get_ticks_msec()
	if current_time - last_shot_time < fire_rate * 1000.0:
		return

	last_shot_time = current_time

	if shotgun_fire:
		print("Shotgun: Playing fire sound.")
		shotgun_fire.play()

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = player_camera.global_position

	var forward_dir: Vector3 = -player_camera.global_transform.basis.z.normalized()
	var cam_right: Vector3 = player_camera.global_transform.basis.x.normalized()
	var cam_up: Vector3 = player_camera.global_transform.basis.y.normalized()

	# ----------------------------------------------------
	# TELL ALL SMOKE MANAGERS WE FIRED A SHOTGUN BLAST
	# ----------------------------------------------------
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

	# ----------------------------------------------------
	# PELLET RAYCASTING
	# ----------------------------------------------------
	for i: int in range(pellet_count):
		var random_x: float = deg_to_rad(randf_range(-spread_angle, spread_angle))
		var random_y: float = deg_to_rad(randf_range(-spread_angle, spread_angle))

		var pellet_dir: Vector3 = forward_dir.rotated(cam_right, random_y).rotated(cam_up, random_x)
		var end_point: Vector3 = origin + (pellet_dir * max_range)

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, end_point
		)
		query.exclude = [player_camera.owner.get_rid()]

		var result: Dictionary = space_state.intersect_ray(query)

		if result:
			var collider: Object = result.collider
			print("Shotgun: Pellet hit " + str(collider.name) + " at " + str(result.position))

			if collider.has_method("take_damage"):
				collider.take_damage(damage_per_pellet, result.position, pellet_dir)
			elif collider is RigidBody3D:
				var hit_offset: Vector3 = (
					result.position - (collider as RigidBody3D).global_position
				)
				(collider as RigidBody3D).apply_impulse(pellet_dir * 2.0, hit_offset)

			if collider.has_method("leak_at"):
				collider.leak_at(result.position)

			var dot: Node3D = DEBUG_PELLET.instantiate() as Node3D
			get_tree().current_scene.add_child(dot)
			dot.global_position = result.position


func _on_interact_component_interacted(_player: CharacterBody3D = null) -> void:
	print("Shotgun: _on_interact_component_interacted() called. Picking up shotgun.")

	# 1. Don't let us pick it up twice!
	if is_equipped:
		return

	# 2. Find the player using the group and strictly cast it
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player") as CharacterBody3D

	# 3. Tell the shotgun to run its equip logic on that player
	if player:
		equip_to_player(player)
