## Interactive electric lightning orb with pseudo-volumetric smoke illumination.
class_name InteractiveLightningOrb
extends Node3D

## Emitted by [method trigger_strike] when lightning strikes [param strike_position].
signal lightning_struck(strike_position: Vector3)

## Physics collision layer mask used for raycasting environment hits (Layer 1).
const ENVIRONMENT_COLLISION_MASK: int = 1

## Maximum number of jitter segments generated per arc in [method _build_jagged_arc].
const MAX_ARC_SEGMENTS: int = 10

## Floating amplitude of the orb along the Y-axis.
@export var hover_amplitude: float = 0.25

## Speed of the hover bobbing animation.
@export var hover_speed: float = 2.0

## Number of simultaneous electrical arcs jumping from the orb.
@export var arc_count: int = 3

## Maximum distance lightning rays probe into the environment.
@export var strike_range: float = 6.0

## Strength of jagged displacement on electric arcs.
@export var arc_jitter_strength: float = 0.35

## Time interval in seconds between lightning arc regenerations.
@export var strike_interval: float = 0.06

var _time_passed: float = 0.0
var _strike_timer: float = 0.0
var _base_y: float = 0.0
var _immediate_mesh: ImmediateMesh = ImmediateMesh.new()
var _arc_material: StandardMaterial3D = StandardMaterial3D.new()

@onready var core_mesh: MeshInstance3D = $CoreMesh
@onready var orb_light: OmniLight3D = $OrbLight
@onready var arc_mesh_instance: MeshInstance3D = $ArcMeshInstance
@onready var impact_light: OmniLight3D = $ImpactLight
@onready var impact_sparks: GPUParticles3D = $ImpactSparks
@onready var smoke_particles: GPUParticles3D = get_node_or_null("../VolumetricSmoke")


## Initializes procedural meshes, materials, and prints the setup status.
func _ready() -> void:
	print("InteractiveLightningOrb: Initializing lightning effect system.")
	_base_y = position.y
	_setup_arc_rendering()


## Updates hover motion, arc generation timer, and fades the impact light.
func _process(delta: float) -> void:
	_time_passed += delta
	position.y = _base_y + (sin(_time_passed * hover_speed) * hover_amplitude)

	if impact_light.light_energy > 0.0:
		impact_light.light_energy = maxf(0.0, impact_light.light_energy - (delta * 18.0))

	_strike_timer += delta
	if _strike_timer >= strike_interval:
		_strike_timer = 0.0
		_update_lightning_arcs()


## Handles keyboard and mouse inputs for moving and manual strike testing.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		print("InteractiveLightningOrb: Player triggered manual lightning strike.")
		var random_offset: Vector3 = Vector3(randf_range(-2.5, 2.5), -2.0, randf_range(-2.5, 2.5))
		trigger_strike(global_position + random_offset)


## Manually triggers a lightning discharge toward [param target_position].
func trigger_strike(target_position: Vector3) -> void:
	print("InteractiveLightningOrb: Firing lightning strike at ", target_position)
	lightning_struck.emit(target_position)
	impact_light.global_position = target_position + Vector3(0.0, 0.2, 0.0)
	impact_light.light_energy = 5.0
	impact_sparks.global_position = target_position
	impact_sparks.restart()
	impact_sparks.emitting = true


## Adjusts the pseudo-volumetric smoke emission energy multiplier.
func set_smoke_intensity(energy: float) -> void:
	print("InteractiveLightningOrb: Setting smoke illumination energy to ", energy)
	if is_instance_valid(smoke_particles):
		var mat: StandardMaterial3D = smoke_particles.draw_pass_1.material as StandardMaterial3D
		if is_instance_valid(mat):
			mat.albedo_color.a = clampf(energy, 0.05, 0.8)


## Configures the [ImmediateMesh] and unshaded emissive material for electric arcs.
func _setup_arc_rendering() -> void:
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.albedo_color = Color(0.5, 0.9, 1.0, 1.0)
	_arc_material.render_priority = 1
	arc_mesh_instance.mesh = _immediate_mesh
	arc_mesh_instance.material_override = _arc_material


## Raycasts toward environment colliders and regenerates all electrical arcs.
func _update_lightning_arcs() -> void:
	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _arc_material)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for i: int in range(arc_count):
		var random_dir: Vector3 = (
			Vector3(randf_range(-0.8, 0.8), randf_range(-1.0, -0.2), randf_range(-0.8, 0.8))
			. normalized()
		)
		var ray_target: Vector3 = global_position + (random_dir * strike_range)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			global_position, ray_target, ENVIRONMENT_COLLISION_MASK
		)
		var hit: Dictionary = space_state.intersect_ray(query)
		var end_point: Vector3 = ray_target
		if not hit.is_empty():
			end_point = hit["position"]
			if i == 0 and randf() < 0.35:
				trigger_strike(end_point)

		_build_jagged_arc(global_position, end_point)

	_immediate_mesh.surface_end()


## Builds jagged line segments between [param start_pos] and [param end_pos].
func _build_jagged_arc(start_pos: Vector3, end_pos: Vector3) -> void:
	var points: Array[Vector3] = [start_pos]
	var step_vec: Vector3 = (end_pos - start_pos) / float(MAX_ARC_SEGMENTS)
	for s: int in range(1, MAX_ARC_SEGMENTS):
		var base_point: Vector3 = start_pos + (step_vec * float(s))
		var jitter: Vector3 = Vector3(
			randf_range(-arc_jitter_strength, arc_jitter_strength),
			randf_range(-arc_jitter_strength, arc_jitter_strength),
			randf_range(-arc_jitter_strength, arc_jitter_strength)
		)
		points.append(base_point + jitter)
	points.append(end_pos)

	for p: int in range(points.size() - 1):
		_immediate_mesh.surface_add_vertex(points[p] - global_position)
		_immediate_mesh.surface_add_vertex(points[p + 1] - global_position)
