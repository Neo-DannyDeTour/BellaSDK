class_name Torch
extends Node3D

@export_category("Equip Settings")
## X is Right/Left, Y is Up/Down, Z is Backward/Forward (Negative Z is forward in Godot)
@export var equip_position_offset: Vector3 = Vector3(0.3, -0.3, -0.6)
@export var equip_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0)

@export_category("Flicker Settings")
@export var noise: FastNoiseLite
@export var base_energy: float = 1.0
@export var flicker_speed: float = 150.0
@export var flicker_intensity: float = 0.5

var is_equipped: bool = false
var _time_passed: float = 0.0

@onready var _light: OmniLight3D = $FlickerLight
@onready var _particles: GPUParticles3D = $FlameParticles


func _ready() -> void:
	if noise == null:
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.05


func _process(delta: float) -> void:
	_time_passed += delta * flicker_speed

	var noise_val: float = noise.get_noise_1d(_time_passed)
	_light.light_energy = base_energy + (noise_val * flicker_intensity)


func equip_to_player(p_node: CharacterBody3D) -> void:
	print(
		"Torch: equip_to_player() called. Applying offset: Position ",
		equip_position_offset,
		", Rotation ",
		equip_rotation_degrees
	)
	is_equipped = true

	var physics_body: PhysicsBody3D = get_node_or_null("StaticBody3D")
	if physics_body:
		physics_body.process_mode = Node.PROCESS_MODE_DISABLED

	var weapon_holder: Node3D = p_node.get_node_or_null("%WeaponHolder")
	if weapon_holder:
		reparent(weapon_holder, false)
		# Apply the custom offsets instead of Vector3.ZERO
		position = equip_position_offset
		rotation_degrees = equip_rotation_degrees


func _on_interact_component_interacted(_character: CharacterBody3D = null) -> void:
	print("Torch: _on_interact_component_interacted() called. Attempting to equip.")
	if is_equipped:
		return

	var player: CharacterBody3D = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player:
		equip_to_player(player)


func ignite_torch() -> void:
	print("Torch: ignite_torch() called. Turning on the torch light and particles.")
	_particles.emitting = true
	_light.visible = true


func douse_torch() -> void:
	print("Torch: douse_torch() called. Turning off the torch light and particles.")
	_particles.emitting = false
	_light.visible = false
