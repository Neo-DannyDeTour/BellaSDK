@tool
## Generates procedural electric arcs between source and target anchors.
class_name LightningManager
extends Node3D

# --------------------------------------
# EXPORTS
# --------------------------------------

@export_group("Required Assignments")
## Origin node where the lightning bolt originates.
@export var source_marker: Node3D

## Destination anchors receiving lightning discharge lines.
@export var receiver_markers: Array[Node3D]

## Shader or spatial material applied to the lightning mesh.
@export var lightning_material: ShaderMaterial

@export_group("Strike Control")
## Activates or halts the procedural lightning discharge.
@export var strike_enabled: bool = false:
	set(value):
		strike_enabled = value
		if is_node_ready():
			if value:
				strike()
			else:
				stop_strike()

## Playback speed factor affecting the flicker rate.
@export var speed: float = 1.0

## Duration in seconds between geometry redraw iterations.
@export var flicker_rate: float = 0.05

## Number of line segments calculated per lightning arc.
@export var subdivisions: int = 20

@export_group("Variation Ranges")
## Vertical height added to the apex of the arc.
@export var arc_height_base: float = 2.0

## Maximum random deviation added to the arc apex height.
@export var arc_height_variance: float = 1.0

## Base amplitude for random perpendicular segment displacement.
@export var jitter_base: float = 0.3

## Maximum random deviation added to the displacement jitter.
@export var jitter_variance: float = 0.2

# --------------------------------------
# INTERNAL VARIABLES
# --------------------------------------

## Tracks if the lightning bolt is currently discharging.
var is_striking: bool = false

## Procedural mesh resource holding generated line vertices.
var _array_mesh: ArrayMesh

## Mesh instance displaying procedural lightning lines in the scene.
var _mesh_instance: MeshInstance3D

## Elapsed time accumulator tracking the next visual flicker.
var _flicker_timer: float = 0.0

## Computed height offset for the current flicker iteration.
var _current_arc_height: float = 0.0

## Computed displacement jitter for the current flicker iteration.
var _current_jitter: float = 0.0

# --------------------------------------
# ENGINE METHODS
# --------------------------------------


## Initializes procedural mesh instance and hides editor gizmos in game builds.
func _ready() -> void:
	var sprite_icon: Sprite3D = get_node_or_null("Sprite3D") as Sprite3D
	if is_instance_valid(sprite_icon):
		sprite_icon.visible = Engine.is_editor_hint()

	_array_mesh = ArrayMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _array_mesh

	if lightning_material != null:
		_mesh_instance.material_override = lightning_material

	_mesh_instance.visible = false
	add_child(_mesh_instance)

	set_process(false)

	if strike_enabled:
		strike()


## Accumulates flicker timer and updates arc geometry at target intervals.
func _process(delta: float) -> void:
	if not is_striking:
		return

	_flicker_timer += delta * speed

	if _flicker_timer >= flicker_rate:
		_flicker_timer = 0.0
		_randomize_parameters()
		_draw_lightning()


# --------------------------------------
# STRIKE CONTROL
# --------------------------------------


## Enables process ticks and renders active lightning discharge geometry.
func strike() -> void:
	print("LightningManager: strike() called. Initiating lightning emission.")
	is_striking = true
	_flicker_timer = flicker_rate

	if _mesh_instance != null:
		_mesh_instance.visible = true

	set_process(true)


## Halts lightning emission, clears geometry, and disables process ticks.
func stop_strike() -> void:
	print("LightningManager: stop_strike() called. Halting lightning emission.")
	is_striking = false
	set_process(false)

	if is_instance_valid(_array_mesh) and _array_mesh.get_surface_count() > 0:
		_array_mesh.clear_surfaces()

	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = false


# --------------------------------------
# PROCEDURAL DRAWING
# --------------------------------------


## Generates randomized vertical arc and displacement parameters.
func _randomize_parameters() -> void:
	_current_arc_height = (arc_height_base + randf_range(-arc_height_variance, arc_height_variance))
	_current_jitter = (jitter_base + randf_range(-jitter_variance, jitter_variance))


## Reconstructs line vertices and passes arrays directly to [ArrayMesh].
func _draw_lightning() -> void:
	if not is_instance_valid(_array_mesh):
		return

	if source_marker == null or receiver_markers.is_empty():
		if _array_mesh.get_surface_count() > 0:
			_array_mesh.clear_surfaces()
		return

	var start_pos: Vector3 = to_local(source_marker.global_position)
	var active_receivers: int = 0
	for receiver: Node3D in receiver_markers:
		if is_instance_valid(receiver):
			active_receivers += 1

	if active_receivers == 0:
		if _array_mesh.get_surface_count() > 0:
			_array_mesh.clear_surfaces()
		return

	var total_verts: int = active_receivers * subdivisions * 2
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.resize(total_verts)

	var write_idx: int = 0

	for receiver: Node3D in receiver_markers:
		if not is_instance_valid(receiver):
			continue

		var end_pos: Vector3 = to_local(receiver.global_position)
		var current_pos: Vector3 = start_pos

		for i: int in range(1, subdivisions + 1):
			var t: float = float(i) / float(subdivisions)
			var target_pos: Vector3 = start_pos.lerp(end_pos, t)
			var arc_factor: float = sin(t * PI)
			target_pos.y += arc_factor * _current_arc_height

			if i < subdivisions:
				target_pos.x += randf_range(-_current_jitter, _current_jitter)
				target_pos.y += randf_range(-_current_jitter, _current_jitter)
				target_pos.z += randf_range(-_current_jitter, _current_jitter)

			vertices[write_idx] = current_pos
			vertices[write_idx + 1] = target_pos
			write_idx += 2

			current_pos = target_pos

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
