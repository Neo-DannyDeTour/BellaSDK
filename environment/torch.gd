## Handheld or placeable torch providing dynamic light and flame particles.
class_name Torch
extends Node3D

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Equip Settings")
## Offset positioning torch relative to player weapon holder.
@export var equip_position_offset: Vector3 = Vector3(0.3, -0.3, -0.6)

## Rotational orientation offset applied when equipped.
@export var equip_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0)

@export_category("Flicker Settings")
## Noise generator driving light flicker variations.
@export var noise: FastNoiseLite

## Base light energy level before noise modulation.
@export var base_energy: float = 1.0

## Playback speed multiplier for flicker noise evaluation.
@export var flicker_speed: float = 150.0

## Maximum light energy variance caused by flame flicker.
@export var flicker_intensity: float = 0.5

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Indicates whether torch is actively equipped on player.
var is_equipped: bool = false

## Accumulated elapsed time in seconds for noise sampling.
var _time_passed: float = 0.0

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Dynamic light source emitting flicker illumination.
@onready var _light: OmniLight3D = $FlickerLight

## Flame particle emitter attached to torch tip.
@onready var _particles: GPUParticles3D = $FlameParticles


## Initializes noise generator for flame flicker evaluation.
func _ready() -> void:
	print("Torch: _ready() initialized.")
	if noise == null:
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.05


## Updates flicker light intensity via noise sampling each frame.
func _process(delta: float) -> void:
	_time_passed += delta * flicker_speed
	var noise_val: float = noise.get_noise_1d(_time_passed)
	if is_instance_valid(_light):
		_light.light_energy = base_energy + (noise_val * flicker_intensity)


## Attaches torch to player weapon holder with custom offset.
func equip_to_player(p_node: CharacterBody3D) -> void:
	print(
		"Torch: equip_to_player() called. Offset: ",
		equip_position_offset,
		", Rotation: ",
		equip_rotation_degrees
	)
	is_equipped = true

	var physics_body: PhysicsBody3D = (
		get_node_or_null("StaticBody3D")
		if get_node_or_null("StaticBody3D") is PhysicsBody3D
		else null
	)
	if is_instance_valid(physics_body):
		physics_body.process_mode = Node.PROCESS_MODE_DISABLED

	var weapon_holder: Node3D = (
		p_node.get_node_or_null("%WeaponHolder")
		if p_node.get_node_or_null("%WeaponHolder") is Node3D
		else null
	)
	if is_instance_valid(weapon_holder):
		reparent(weapon_holder, false)
		position = equip_position_offset
		rotation_degrees = equip_rotation_degrees


## Handles interaction signal by equipping torch to interacting player.
func _on_interact_component_interacted(_character: CharacterBody3D = null) -> void:
	print("Torch: _on_interact_component_interacted() called.")
	if is_equipped:
		return

	var player: CharacterBody3D = (
		get_tree().get_first_node_in_group(&"player")
		if get_tree().get_first_node_in_group(&"player") is CharacterBody3D
		else null
	)
	if is_instance_valid(player):
		equip_to_player(player)


## Activates flame particles and enables dynamic light source.
func ignite_torch() -> void:
	print("Torch: ignite_torch() called.")
	if is_instance_valid(_particles):
		_particles.emitting = true
	if is_instance_valid(_light):
		_light.visible = true


## Deactivates flame particles and hides dynamic light source.
func douse_torch() -> void:
	print("Torch: douse_torch() called.")
	if is_instance_valid(_particles):
		_particles.emitting = false
	if is_instance_valid(_light):
		_light.visible = false
