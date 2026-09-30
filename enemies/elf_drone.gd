## Glowing fairy drone that projects healing beams, follows swarm targets, and heals.
class_name ElfDrone
extends CharacterBody3D

## Emitted on healing pulse, passing [param target] and [param amount].
signal healing_pulsed(target: Node3D, amount: int)

## Maximum movement speed in units per second.
@export var move_speed: float = 7.0

## Rate of velocity change towards target velocity in units per second squared.
@export var acceleration: float = 18.0

## Distance in units where deceleration begins to avoid overshoot jitter.
@export var arrival_distance: float = 1.5

## Health points restored to target entity during healing pulses.
@export var heal_amount: int = 4

## Cooldown interval in seconds between consecutive healing attempts.
@export var heal_cooldown: float = 0.8

## Maximum distance in units within which healing pulses can be delivered.
@export var heal_range: float = 8.0

## Desired world coordinate towards which drone translates.
var target_position: Vector3 = Vector3.ZERO

## Internal cooldown timer tracking time between healing pulses.
var heal_timer: float = 0.0

## Cached reference to child [MeshInstance3D] handling drone glow visuals.
var mesh_instance: MeshInstance3D

## Child [MeshInstance3D] stretched as an illuminated beam to the target.
var healing_beam: MeshInstance3D

## Particle emitter producing energy motes when healing beam is active.
var beam_particles: GPUParticles3D

## Active target [Node3D] being healed and linked by the healing beam.
var current_healing_target: Node3D = null


## Initializes child node references, cached components, and sets default visuals.
func _ready() -> void:
	print("ElfDrone: _ready() - Initializing elf drone actor on ", name)
	mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	healing_beam = get_node_or_null("HealingBeam") as MeshInstance3D
	beam_particles = get_node_or_null("BeamParticles") as GPUParticles3D
	target_position = global_position

	if healing_beam != null:
		healing_beam.top_level = true
		healing_beam.visible = false

	if beam_particles != null:
		beam_particles.emitting = false


## Smoothly updates velocity towards [member target_position] and updates beam visual.
func _physics_process(delta: float) -> void:
	var displacement: Vector3 = target_position - global_position
	var distance: float = displacement.length()
	var desired_velocity: Vector3 = Vector3.ZERO

	if distance > 0.02:
		var speed_factor: float = clampf(distance / arrival_distance, 0.0, 1.0)
		desired_velocity = (displacement / distance) * (move_speed * speed_factor)

	velocity = velocity.move_toward(desired_velocity, acceleration * delta)
	move_and_slide()

	if heal_timer > 0.0:
		heal_timer = maxf(0.0, heal_timer - delta)

	if current_healing_target != null:
		_update_beam_transform()


## Updates [member target_position] destination for path and swarm steering.
func set_target_position(new_pos: Vector3) -> void:
	target_position = new_pos


## Sets or clears [member current_healing_target] and toggles beam visibility.
func set_healing_target(target: Node3D) -> void:
	if current_healing_target == target:
		return

	var target_label: String = String(target.name) if target != null else "null"
	print("ElfDrone: set_healing_target() - Target set to ", target_label)
	current_healing_target = target

	if current_healing_target == null:
		if healing_beam != null:
			healing_beam.visible = false
		if beam_particles != null:
			beam_particles.emitting = false
	else:
		if beam_particles != null:
			beam_particles.emitting = true


## Evaluates proximity to [param target] and delivers healing via [HealthComponent].
func try_heal_target(target: Node3D, _delta: float) -> void:
	if target == null or heal_timer > 0.0:
		return

	var distance: float = global_position.distance_to(target.global_position)
	if distance > heal_range:
		return

	var health_comp: HealthComponent = null
	var candidate: Node = target.get_node_or_null("Components/HealthComponent")
	if candidate is HealthComponent:
		health_comp = candidate as HealthComponent
	elif target.get_node_or_null("HealthComponent") is HealthComponent:
		health_comp = target.get_node_or_null("HealthComponent") as HealthComponent

	if health_comp != null:
		print("ElfDrone: try_heal_target() - Restoring ", heal_amount, " health to ", target.name)
		health_comp.heal(heal_amount)
		heal_timer = heal_cooldown
		healing_pulsed.emit(target, heal_amount)


## Updates emission energy and albedo color on the spherical visual mesh.
func set_glow_color(color: Color) -> void:
	print("ElfDrone: set_glow_color() - Applying glow color ", color)
	if mesh_instance == null:
		return
	var mat: StandardMaterial3D = mesh_instance.get_active_material(0) as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color
		mat.emission = color


## Scales and points [member healing_beam] between drone and target position.
func _update_beam_transform() -> void:
	if healing_beam == null:
		return

	if not is_instance_valid(current_healing_target):
		set_healing_target(null)
		return

	var start_pt: Vector3 = global_position
	var end_pt: Vector3 = current_healing_target.global_position
	var dist: float = start_pt.distance_to(end_pt)

	if dist <= 0.05 or dist > heal_range:
		healing_beam.visible = false
		return

	healing_beam.visible = true
	healing_beam.global_position = (start_pt + end_pt) * 0.5

	var dir: Vector3 = (end_pt - start_pt).normalized()
	var up_vec: Vector3 = Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP
	healing_beam.look_at(end_pt, up_vec)
	healing_beam.scale = Vector3(1.0, 1.0, dist)
