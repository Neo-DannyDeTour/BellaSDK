extends Node3D
class_name Shotgun

#@onready var anim: AnimationPlayer = $ShotgunAnim
@onready var muzzle_point: Marker3D = $MuzzlePoint

@export var pellet_count: int = 8
@export var spread_angle: float = 4.0  # Degrees of spread
@export var damage_per_pellet: int = 10
@export var max_range: float = 50.0
@export var fire_rate: float = 1.0  # Seconds between shots
@export var shotgun_fire: AudioStreamPlayer3D

var last_shot_time: float = -1000.0

# Preload the dot so it's ready in memory the moment we shoot
const DEBUG_PELLET = preload("res://scenes/debug_pellet.tscn")
const DUST_PUFF = preload("res://scenes/effects/dust_puff.tscn")

var is_equipped: bool = false


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
	if not is_equipped:
		return

	var current_time := Time.get_ticks_msec()
	if current_time - last_shot_time < fire_rate * 1000.0:
		return  # Too soon! Abort the function.

	last_shot_time = current_time

	# --- PLAY FIRE SOUND ---
	if shotgun_fire:
		shotgun_fire.play()

	# 1. Get access to the raw Physics Engine
	var space_state := get_world_3d().direct_space_state

	# 2. Get the exact center of the player's screen
	var origin := player_camera.global_position

	# The negative Z axis of the camera's basis is always exactly "forward"
	var forward_dir := -player_camera.global_transform.basis.z
	var cam_right := player_camera.global_transform.basis.x
	var cam_up := player_camera.global_transform.basis.y

	# ----------------------------------------------------
	# NEW: TELL THE SMOKE MANAGER WE FIRED A SHOTGUN BLAST
	# ----------------------------------------------------
	if SmokeManager:
		SmokeManager.add_bullet_hole(origin, forward_dir, max_range, 3.0)

	# 3. Calculate and fire each pellet
	for i in range(pellet_count):
		# Generate random spread angles
		var random_x := deg_to_rad(randf_range(-spread_angle, spread_angle))
		var random_y := deg_to_rad(randf_range(-spread_angle, spread_angle))

		# Apply the spread to our forward direction
		var pellet_dir := forward_dir.rotated(cam_right, random_y).rotated(cam_up, random_x)
		var end_point := origin + (pellet_dir * max_range)

		# 4. Create a math-based raycast
		var query := PhysicsRayQueryParameters3D.create(origin, end_point)
		# Ignore the player so we don't shoot ourselves!
		query.exclude = [player_camera.owner.get_rid()]

		# 5. Ask the physics engine what we hit
		var result := space_state.intersect_ray(query)

		if result:
			var collider: Object = result.collider

			# --- THE DAMAGE & PHYSICS CHECK ---
			if collider.has_method("take_damage"):
				# We pass the damage AND the direction the pellet was flying!
				collider.take_damage(damage_per_pellet, pellet_dir)

			elif collider is RigidBody3D:
				# If it doesn't take damage, but IS a physics object (like your box), push it!
				var hit_offset: Vector3 = result.position - collider.global_position
				collider.apply_impulse(pellet_dir * 2.0, hit_offset)

			# --- VISUAL EFFECTS ---
			if collider.has_method("leak_at"):
				collider.leak_at(result.position)

			var dot := DEBUG_PELLET.instantiate()
			get_tree().current_scene.add_child(dot)
			dot.global_position = result.position
			Console.write(
				"Pellet hit: " + str(collider.name) + " at " + str(result.position), "orange"
			)


func _on_interact_component_interacted(_player: CharacterBody3D = null) -> void:
	print("picking up shotgun")
	# 1. Don't let us pick it up twice!
	if is_equipped:
		return

	# 2. Find the player using the group we set up earlier
	var player := get_tree().get_first_node_in_group("player")

	# 3. Tell the shotgun to run its equip logic on that player
	if player:
		equip_to_player(player)
