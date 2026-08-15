## A highly volatile physics object that causes AOE damage, screen shake, and chain reactions.
##
## Inherits from [PickableObject], allowing the player to carry and throw it. When health reaches
## zero, it triggers a comprehensive explosion sequence affecting physics bodies and player sensors.
class_name ExplosiveBarrel
extends PickableObject

@export_category("Explosive Settings")
## The total amount of damage required to trigger the explosion.
@export var max_health: int = 10
## The packed visual effect scene spawned precisely at the barrel's center upon detonation.
@export var explosion_scene: PackedScene
## The maximum radius in meters within which physics objects will be pushed by the blast.
@export var max_distance: float = 3.0
## The base magnitude of the physics impulse applied to nearby rigid bodies.
@export var max_force: float = 50.0
## Distance threshold in meters where a barrel instantly detonates instead of just moving.
@export var chain_reaction_threshold: float = 1.5
## The visual distortion radius passed to the global shockwave manager.
@export var shockwave_radius: float = 5.0

## The remaining health points of the barrel before detonation.
var current_health: int
## Flag preventing recursive or multiple explosion calls.
var has_exploded: bool = false

## The area volume used to detect and calculate distances to nearby entities during the blast.
@onready var area_3d: Area3D = $Area3D


## Initializes the health pool of the barrel.
func _ready() -> void:
	current_health = max_health


## Processes incoming damage, applies a physical flinch impulse, and triggers explosion on death.
## [param amount]: The raw damage integer.
## [param hit_position]: The 3D world coordinate where the damage occurred (e.g., bullet impact).
## [param hit_direction]: The normalized vector indicating the trajectory of the incoming attack.
func take_damage(amount: int, hit_position: Vector3, hit_direction: Vector3) -> void:
	print("ExplosiveBarrel: take_damage() called. Amount: ", amount)

	if has_exploded:
		return

	current_health -= amount

	var impulse_offset: Vector3 = hit_position - global_position
	apply_impulse(hit_direction * (float(amount) * 0.2), impulse_offset)

	if current_health <= 0:
		explode()


## Orchestrates barrel destruction, coordinating VFX, physics, camera shake, and UI effects.
func explode() -> void:
	print("ExplosiveBarrel: explode() called. Triggering destruction.")
	if has_exploded:
		return

	has_exploded = true

	if get("is_held") == true:
		print("ExplosiveBarrel: Barrel was held during explosion. Forcing drop.")
		call("drop")

	_spawn_explosion_vfx()
	_trigger_shockwave()
	_apply_screen_shake_and_audio()
	_apply_aoe_physics()

	queue_free()


## Instantiates and places the particle system mapped to [member explosion_scene].
func _spawn_explosion_vfx() -> void:
	print("ExplosiveBarrel: _spawn_explosion_vfx() called.")
	if explosion_scene == null:
		return

	var explosion_instance: Node3D = explosion_scene.instantiate() as Node3D
	if is_instance_valid(explosion_instance):
		get_tree().current_scene.add_child(explosion_instance)
		explosion_instance.global_position = global_position


## Calls the global `ShockwaveManager` singleton to distort the screen space rendering.
func _trigger_shockwave() -> void:
	print("ExplosiveBarrel: _trigger_shockwave() called. Radius set to: ", shockwave_radius)
	var manager: Node = get_node_or_null("/root/ShockwaveManager")

	if is_instance_valid(manager) and manager.has_method("trigger_shockwave"):
		manager.call("trigger_shockwave", global_position, shockwave_radius)
	else:
		print("ExplosiveBarrel: ShockwaveManager not found or invalid.")


## Calculates distance to the active camera to scale screen shake and auditory tinnitus.
func _apply_screen_shake_and_audio() -> void:
	print("ExplosiveBarrel: _apply_screen_shake_and_audio() called.")
	var cam: Camera3D = get_viewport().get_camera_3d()

	if not is_instance_valid(cam):
		print("ExplosiveBarrel: No active Camera3D found for screen shake.")
		return

	var distance: float = global_position.distance_to(cam.global_position)
	var intensity: float = 0.0
	var shake_duration: float = 0.0
	var tinnitus_duration: float = 0.0

	if distance <= 2.0:
		print("ExplosiveBarrel: Player is VERY close (<= 2m). Max shake and 5s tinnitus.")
		intensity = 0.8
		shake_duration = 4.0
		tinnitus_duration = 5.0
	elif distance <= 5.0:
		print("ExplosiveBarrel: Player is in mid-range (<= 5m). Medium shake and 3s tinnitus.")
		intensity = 0.3
		shake_duration = 2.0
		tinnitus_duration = 3.0
	else:
		print("ExplosiveBarrel: Player is too far ( > 5m ). No shake or audio.")
		return

	if tinnitus_duration > 0.0:
		var tinnitus: TinnitusEffect = TinnitusEffect.new()
		tinnitus.duration = tinnitus_duration
		get_tree().current_scene.add_child(tinnitus)

	var shake_tween: Tween = get_tree().create_tween()
	var shake_step: float = 0.05
	var steps: int = int(shake_duration / shake_step)

	for i: int in range(steps):
		var falloff: float = 1.0 - (float(i) / float(steps))
		var current_intensity: float = intensity * falloff

		var rx: float = randf_range(-current_intensity, current_intensity)
		var ry: float = randf_range(-current_intensity, current_intensity)

		shake_tween.tween_property(cam, "h_offset", rx, shake_step)
		shake_tween.parallel().tween_property(cam, "v_offset", ry, shake_step)
		shake_tween.chain()

	shake_tween.tween_property(cam, "h_offset", 0.0, 0.1)
	shake_tween.parallel().tween_property(cam, "v_offset", 0.0, 0.1)


## Finds overlapping bodies, calculates physics impulses, and triggers chain reactions.
func _apply_aoe_physics() -> void:
	print("ExplosiveBarrel: _apply_aoe_physics() called.")
	if not is_instance_valid(area_3d) or not area_3d.has_overlapping_bodies():
		return

	var bodies: Array[Node3D] = area_3d.get_overlapping_bodies()

	for body: Node3D in bodies:
		if body == self:
			continue

		var distance_squared: float = global_position.distance_squared_to(body.global_position)
		var distance: float = p0.distance_to(p2) # Reverted to distance_to as sqrt negates distance_squared_to performance

		# Determine and deal damage BEFORE filtering out non-rigid bodies
		_try_apply_damage(body, distance)

		if not body is RigidBody3D:
			continue

		var rigid_body: RigidBody3D = body as RigidBody3D

		if distance <= 0.01:
			distance = 0.01

		if distance > max_distance:
			continue

		var direction: Vector3 = (rigid_body.global_position - global_position).normalized()

		var force_multiplier: float = maxf(0.0, 1.0 - (distance / max_distance))
		var impulse: Vector3 = direction * (max_force * force_multiplier)

		if rigid_body is ExplosiveBarrel:
			var other_barrel: ExplosiveBarrel = rigid_body as ExplosiveBarrel
			if not other_barrel.has_exploded:
				if distance <= chain_reaction_threshold:
					other_barrel.call_deferred("explode")
				else:
					other_barrel.apply_impulse(impulse)
		else:
			rigid_body.apply_impulse(impulse)


## Checks radial distance tiers to assign damage values to valid [HealthComponent] holders.
## [param body]: The target node within the blast radius.
## [param distance]: The calculated distance in meters from the blast center to the target.
func _try_apply_damage(body: Node3D, distance: float) -> void:
	print("ExplosiveBarrel: _try_apply_damage() calculating damage for distance ", distance)
	var damage: int = 0

	if distance <= 2.0:
		damage = 300
	elif distance <= 3.0:
		damage = 200
	elif distance <= 5.0:
		damage = 100

	if damage <= 0:
		return

	var health_comp: Node = _find_health_component(body)
	if is_instance_valid(health_comp) and health_comp.has_method("take_damage"):
		print("ExplosiveBarrel: Dealing ", damage, " damage to ", body.name)
		health_comp.call("take_damage", damage)


## Scans a target's scene hierarchy for an attached [HealthComponent] script.
## [param node]: The root node to begin searching from.
## Returns the specific node reference, or null if none is found.
func _find_health_component(node: Node) -> Node:
	print("ExplosiveBarrel: _find_health_component() scanning tree of ", node.name)

	# 1. Check direct children first (fastest)
	for child: Node in node.get_children():
		if child.get_class() == "HealthComponent" or "take_damage" in child:
			return child

	# 2. If not a direct child, perform a recursive search
	var nested_components: Array[Node] = node.find_children("*", "HealthComponent", true, false)
	if not nested_components.is_empty():
		return nested_components[0]

	return null
