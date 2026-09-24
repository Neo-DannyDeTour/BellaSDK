@tool
## Procedural vacuum tube transporting rigid bodies and players along a 3D path.
class_name PneumaticTube
extends Path3D


## Internal tracking record for objects traveling inside the tube.
class PneumaticTubeRider:
	extends RefCounted
	## Reference to the transported entity [Node3D].
	var body: Node3D
	## Distance traveled along the [Curve3D] in meters.
	var progress: float = 0.0
	## Stores whether a [RigidBody3D] was frozen before capture.
	var was_frozen: bool = false
	## Physics processing status before tube entry.
	var had_physics_process: bool = true


## Emitted when an entity enters the suction intake.
signal body_entered_tube(body: Node3D)

## Emitted when an entity is ejected from the tube exit.
signal body_exited_tube(body: Node3D)

## Collision mask targeting layers 2 (Player), 3 (Interactive), 4 (Debris), 5 (Enemies).
const DEFAULT_MASK: int = 30

## Outer radius of the cylindrical tube in meters.
@export var outer_radius: float = 0.6:
	set(value):
		outer_radius = maxf(0.1, value)
		if is_inside_tree() and is_instance_valid(tube_mesh):
			rebuild_tube()

## Wall thickness of the hollow tube cylinder.
@export var wall_thickness: float = 0.06:
	set(value):
		wall_thickness = clampf(value, 0.01, outer_radius * 0.4)
		if is_inside_tree() and is_instance_valid(tube_mesh):
			rebuild_tube()

## Subdivisions for circular tube geometry resolution.
@export_range(8, 48, 1) var circle_sides: int = 24:
	set(value):
		circle_sides = clampi(value, 8, 48)
		if is_inside_tree() and is_instance_valid(tube_mesh):
			rebuild_tube()

## Speed of travel along the path in meters per second.
@export var transport_speed: float = 24.0

## Launch impulse speed when exiting the tube.
@export var exit_launch_speed: float = 26.0

## Material applied to the procedural mesh instance.
@export var tube_material: Material:
	set(value):
		tube_material = value
		if is_inside_tree() and is_instance_valid(tube_mesh):
			tube_mesh.material = tube_material

## Procedural polygon extrusion node generating the tube mesh.
@onready var tube_mesh: CSGPolygon3D = get_node_or_null("TubeMesh")

## Suction trigger area positioned at the start of the curve.
@onready var intake_area: Area3D = get_node_or_null("IntakeArea")

## Orientation marker placed at the path endpoint.
@onready var exit_marker: Marker3D = get_node_or_null("ExitMarker")

## Active list of all bodies currently traveling through the tube.
var _active_riders: Array[PneumaticTubeRider] = []


## Initializes path duplication, sets collision masks, and builds geometry.
func _ready() -> void:
	print("PneumaticTube: Initializing tube instance.")
	if curve != null and not Engine.is_editor_hint():
		curve = curve.duplicate()

	if intake_area != null:
		intake_area.collision_layer = 0
		intake_area.collision_mask = DEFAULT_MASK
		if not intake_area.body_entered.is_connected(_on_intake_body_entered):
			intake_area.body_entered.connect(_on_intake_body_entered)

	rebuild_tube()


## Updates spatial rider positions along the curve each physics tick.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or curve == null:
		return

	var total_len: float = curve.get_baked_length()
	var remaining: Array[PneumaticTubeRider] = []

	for rider: PneumaticTubeRider in _active_riders:
		if not is_instance_valid(rider.body):
			continue

		rider.progress += transport_speed * delta
		if rider.progress >= total_len:
			_eject_rider(rider)
		else:
			var local_pos: Vector3 = curve.sample_baked(rider.progress)
			rider.body.global_position = to_global(local_pos)

			# Allow player to retain free mouse look; orient physics props along curve
			if not (rider.body is Player):
				var next_progress: float = minf(rider.progress + 0.5, total_len)
				var next_pos: Vector3 = curve.sample_baked(next_progress)
				var dir: Vector3 = (to_global(next_pos) - rider.body.global_position).normalized()
				if not dir.is_zero_approx():
					var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
					rider.body.look_at(rider.body.global_position + dir, up)

			remaining.push_back(rider)

	_active_riders = remaining


## Rebuilds the hollow CSG polygon along the [Curve3D] path.
func rebuild_tube() -> void:
	print("PneumaticTube: Rebuilding procedural CSG geometry.")
	if not is_instance_valid(tube_mesh) or curve == null or curve.point_count < 2:
		return

	var inner_r: float = outer_radius - wall_thickness
	tube_mesh.mode = CSGPolygon3D.MODE_PATH
	tube_mesh.path_node = tube_mesh.get_path_to(self)
	tube_mesh.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	tube_mesh.path_interval = 0.5
	tube_mesh.path_simplify_angle = 0.0
	tube_mesh.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH
	tube_mesh.path_local = true
	tube_mesh.path_continuous_u = true
	tube_mesh.polygon = _build_ring_polygon(outer_radius, inner_r, circle_sides)

	if tube_material != null:
		tube_mesh.material = tube_material

	_update_boundary_markers()


## Creates 2D polygon vertices for a hollow ring with a closed cut seam.
func _build_ring_polygon(outer_r: float, inner_r: float, sides: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var seam_offset: float = 0.001
	var span: float = TAU - seam_offset

	for i: int in range(sides + 1):
		var angle: float = (float(i) / float(sides)) * span
		pts.push_back(Vector2(cos(angle), sin(angle)) * outer_r)

	for i: int in range(sides, -1, -1):
		var angle: float = (float(i) / float(sides)) * span
		pts.push_back(Vector2(cos(angle), sin(angle)) * inner_r)

	return pts


## Updates intake area and exit marker coordinates to curve endpoints.
func _update_boundary_markers() -> void:
	if is_instance_valid(intake_area) and curve != null and curve.point_count > 0:
		intake_area.position = curve.get_point_position(0)

	if is_instance_valid(exit_marker) and curve != null and curve.point_count > 1:
		var last_index: int = curve.point_count - 1
		exit_marker.position = curve.get_point_position(last_index)
		var exit_dir: Vector3 = _get_exit_vector()
		if not exit_dir.is_zero_approx():
			var up: Vector3 = Vector3.UP if absf(exit_dir.y) < 0.99 else Vector3.FORWARD
			exit_marker.look_at(exit_marker.global_position + exit_dir, up)


## Detects and captures valid physics bodies entering the intake volume.
func _on_intake_body_entered(body: Node3D) -> void:
	print("PneumaticTube: Body entered intake: ", body.name)
	for rider: PneumaticTubeRider in _active_riders:
		if rider.body == body:
			return
	capture_body(body)


## Registers an entity into the active transport queue.
func capture_body(body: Node3D) -> void:
	print("PneumaticTube: Capturing body into tube: ", body.name)
	var rider: PneumaticTubeRider = PneumaticTubeRider.new()
	rider.body = body
	rider.progress = 0.0
	rider.had_physics_process = body.is_physics_processing()

	if body is Player:
		var pl: Player = body as Player
		pl.enter_tube(self)
	elif body is RigidBody3D:
		var rb: RigidBody3D = body as RigidBody3D
		rider.was_frozen = rb.freeze
		rb.freeze = true
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	elif body is CharacterBody3D:
		var cb: CharacterBody3D = body as CharacterBody3D
		cb.velocity = Vector3.ZERO
		cb.set_physics_process(false)

	body.global_position = to_global(curve.sample_baked(0.0))
	_active_riders.push_back(rider)
	body_entered_tube.emit(body)


## Launches an entity from the tube exit with forward momentum.
func _eject_rider(rider: PneumaticTubeRider) -> void:
	print("PneumaticTube: Ejecting body from tube: ", rider.body.name)
	var launch_vel: Vector3 = _get_exit_vector() * exit_launch_speed

	if rider.body is Player:
		var pl: Player = rider.body as Player
		pl.exit_tube(launch_vel)
	elif rider.body is RigidBody3D:
		var rb: RigidBody3D = rider.body as RigidBody3D
		rb.freeze = rider.was_frozen
		rb.linear_velocity = launch_vel
	elif rider.body is CharacterBody3D:
		var cb: CharacterBody3D = rider.body as CharacterBody3D
		cb.set_physics_process(rider.had_physics_process)
		cb.velocity = launch_vel

	body_exited_tube.emit(rider.body)


## Calculates the normalized global forward tangent vector at the path exit.
func _get_exit_vector() -> Vector3:
	if curve == null or curve.point_count < 2:
		return -global_transform.basis.z

	var total_len: float = curve.get_baked_length()
	var p_end: Vector3 = curve.sample_baked(total_len)
	var p_prev: Vector3 = curve.sample_baked(maxf(0.0, total_len - 0.2))
	var local_dir: Vector3 = (p_end - p_prev).normalized()
	return (global_transform.basis * local_dir).normalized()
