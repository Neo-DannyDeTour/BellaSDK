## A stationary laser stand that fires a continuous beam, capable of bouncing off mirrors.
##
## Players can interact with this node to control the direction of the beam. It calculates
## raycasts to detect hits and spawns dynamic visuals (beams, particles, decals) using object pools.
class_name StationaryLaserStand
extends StaticBody3D

## The maximum number of scorch trail decals allowed in the object pool.
const MAX_TRAIL_DECALS: int = 60

## The maximum distance the laser beam can travel in a single straight segment.
@export var max_distance: float = 50.0
## The maximum number of times the laser beam is allowed to reflect off mirrors.
@export var max_bounces: int = 5
## How fast the stand rotates when controlled by a player.
@export var rotation_speed: float = 2.0

## Indicates whether a player is currently actively controlling this laser stand.
var is_controlled: bool = false
## A reference to the [CharacterBody3D] currently controlling this laser stand.
var controlling_player: CharacterBody3D = null
## Tracks if the player has just begun controlling the stand, to avoid immediate detachment.
var _just_attached: bool = false

## The last node that was validly struck by the laser and received a power signal.
var _last_target: Node3D = null
## A pool of [MeshInstance3D] used to visually represent straight segments of the laser beam.
var _beam_pool: Array[MeshInstance3D] = []
## A pool of [GPUParticles3D] used to emit core energy particles along the beam segments.
var _beam_particles_pool: Array[GPUParticles3D] = []
## A pool of [GPUParticles3D] used to spawn sparks where the laser impacts surfaces.
var _impact_particles_pool: Array[GPUParticles3D] = []
## A pool of [GPUParticles3D] used to emit drifting smoke along the beam path.
var _smoke_particles_pool: Array[GPUParticles3D] = []
## A pool of [Decal] nodes representing active scorch marks at current laser impact points.
var _decal_pool: Array[Decal] = []
## The number of line segments generated in the previous frame, used to optimize pool sizing.
var _last_point_count: int = 0
## A pool of [Decal] nodes used to leave fading scorch marks as the laser drags across surfaces.
var _trail_pool: Array[Decal] = []
## The current index in the scorch trail ring buffer for reusing [Decal] nodes.
var _trail_index: int = 0
## Generated [GradientTexture2D] used for active laser burn decals.
var _scorch_texture: GradientTexture2D
## Generated [GradientTexture2D] used for the fading trail scorch decals.
var _trail_texture: GradientTexture2D

@onready
## Base beam particles.
var base_beam_particles: GPUParticles3D = get_node_or_null("Turret/BeamParticles") as GPUParticles3D
## Base impact particles.
@onready var base_impact_particles: GPUParticles3D = (
	get_node_or_null("Turret/ImpactParticles") as GPUParticles3D
)
## Base smoke particles.
@onready var base_smoke_particles: GPUParticles3D = (
	get_node_or_null("Turret/SmokeParticles") as GPUParticles3D
)
## Turret.
@onready var turret: Node3D = $Turret
## Laser origin.
@onready var laser_origin: Marker3D = $Turret/LaserOrigin
## Base beam mesh.
@onready var base_beam_mesh: MeshInstance3D = $Turret/BeamMesh
## Interact comp.
@onready var interact_comp: InteractComponent = $InteractComponent


## Initializes object pools, generated scorch textures, and hides base template visuals.
func _ready() -> void:
	_scorch_texture = _create_scorch_texture()
	_trail_texture = _create_trail_texture()

	base_beam_mesh.visible = false

	if base_beam_particles:
		base_beam_particles.emitting = false
	if base_impact_particles:
		base_impact_particles.emitting = false
	if base_smoke_particles:
		base_smoke_particles.emitting = false

	if interact_comp:
		interact_comp.interacted.connect(_on_interacted)

	_initialize_trail_pool()


func _initialize_trail_pool() -> void:
	print("StationaryLaserStand: Initializing 60 FPS trail pool.")
	for i: int in range(MAX_TRAIL_DECALS):
		var d: Decal = Decal.new()
		d.texture_albedo = _trail_texture
		d.size = Vector3(0.5, 0.5, 0.5)
		d.top_level = true
		d.visible = false
		add_child(d)
		_trail_pool.append(d)


func _create_scorch_texture() -> GradientTexture2D:
	print("StationaryLaserStand: Generating active hit scorch texture.")
	var grad: Gradient = Gradient.new()

	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 1.0])
	grad.colors = PackedColorArray(
		[
			Color(1.0, 0.4, 0.0, 1.0),
			Color(0.1, 0.05, 0.0, 0.9),
			Color(0.0, 0.0, 0.0, 0.0),
			Color(0.0, 0.0, 0.0, 0.0)
		]
	)

	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128

	return tex


func _create_trail_texture() -> GradientTexture2D:
	print("StationaryLaserStand: Generating black scorch trail texture.")
	var grad: Gradient = Gradient.new()

	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray(
		[Color(0.0, 0.0, 0.0, 0.9), Color(0.0, 0.0, 0.0, 0.5), Color(0.0, 0.0, 0.0, 0.0)]
	)

	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128

	return tex


## Updates player control input rotations and calculates the laser raycast bounces.
func _physics_process(delta: float) -> void:
	if is_controlled:
		_handle_rotation_input(delta)
		_check_auto_release()

		# Skip checking detachment on the exact frame we attached
		if _just_attached:
			_just_attached = false
		else:
			_handle_detachment_input()

	_process_laser()


func _handle_rotation_input(delta: float) -> void:
	var turn_input: float = Input.get_axis("left", "right")

	if turn_input != 0.0:
		turret.rotate_y(-turn_input * rotation_speed * delta)


func _check_auto_release() -> void:
	if controlling_player:
		var distance: float = global_position.distance_to(controlling_player.global_position)
		if distance > 3.0:
			print("StationaryLaserStand: Player out of range. Auto-releasing.")
			_release_control()


func _process_laser() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var current_origin: Vector3 = laser_origin.global_position
	var current_direction: Vector3 = -laser_origin.global_transform.basis.z.normalized()

	var bounces: int = 0
	var hit_target: Node3D = null

	var beam_points: PackedVector3Array = PackedVector3Array()
	var beam_normals: PackedVector3Array = PackedVector3Array()

	beam_points.append(current_origin)
	beam_normals.append(-current_direction)

	var exclude_rids: Array[RID] = [get_rid()]

	while bounces <= max_bounces:
		var target_pos: Vector3 = current_origin + (current_direction * max_distance)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			current_origin, target_pos
		)
		query.exclude = exclude_rids

		var result: Dictionary = space_state.intersect_ray(query)

		if result.is_empty():
			beam_points.append(target_pos)
			beam_normals.append(-current_direction)
			break

		var hit_point: Vector3 = result["position"]
		var normal: Vector3 = result["normal"]
		var collider: Object = result["collider"]

		beam_points.append(hit_point)
		beam_normals.append(normal)

		if collider is Node:
			var mirror: ReflectorMirror = _get_mirror_root(collider)

			if mirror:
				var marker: Marker3D = mirror.get_reflect_marker()

				if marker:
					var perfect_normal: Vector3 = marker.global_transform.basis.z.normalized()
					current_direction = current_direction.bounce(perfect_normal)
					current_origin = marker.global_position + (current_direction * 0.01)
				else:
					current_direction = current_direction.bounce(normal)
					current_origin = hit_point + normal * 0.01

				bounces += 1
				exclude_rids.clear()
				if collider is CollisionObject3D:
					exclude_rids.append(collider.get_rid())
				continue

			if collider.has_method("power_on"):
				hit_target = collider as Node3D

		break

	_update_power_target(hit_target)
	_update_beam_visuals(beam_points, beam_normals)


## Traverses up the scene tree to find an attached [ReflectorMirror].
## [param node]: The starting node to check.
## Returns the [ReflectorMirror] instance, or null if none found.
func _get_mirror_root(node: Node) -> ReflectorMirror:
	var current: Node = node
	while current != null:
		if current is ReflectorMirror:
			return current as ReflectorMirror
		current = current.get_parent()
	return null


## Delegates power state to nodes struck by the laser.
## [param hit_target]: The current valid node being hit by the beam.
func _update_power_target(hit_target: Node3D) -> void:
	if hit_target != _last_target:
		_clear_last_target()
		if hit_target:
			print("StationaryLaserStand: Laser hit valid power target!")
			hit_target.call("power_on")
			_last_target = hit_target


## Breaks connection with the previously struck node and powers it off.
func _clear_last_target() -> void:
	if _last_target != null:
		if _last_target.has_method("power_off"):
			print("StationaryLaserStand: Connection broken. Powering off target.")
			_last_target.call("power_off")
		_last_target = null


## Called when a player interacts with the stand.
## [param character]: The [CharacterBody3D] interacting with the stand.
func _on_interacted(character: CharacterBody3D) -> void:
	print("StationaryLaserStand: Interaction triggered by player.")
	if not is_controlled:
		_take_control(character)
	else:
		_release_control()


## Binds the given player character to the stand to enable manual rotation.
## [param character]: The player to bind.
func _take_control(character: CharacterBody3D) -> void:
	print("StationaryLaserStand: Player took control of the machine.")
	is_controlled = true
	_just_attached = true
	controlling_player = character

	if controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(true)


## Releases the current player from controlling the stand.
func _release_control() -> void:
	print("StationaryLaserStand: Player released control of the machine.")
	is_controlled = false

	if controlling_player and controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(false)

	controlling_player = null


## Updates position, rotation, scale, and visibility for all pooled visual elements across segments.
## [param points]: The 3D coordinates representing the start and bounce points of the beam.
## [param normals]: The surface normals at the bounce points.
func _update_beam_visuals(points: PackedVector3Array, normals: PackedVector3Array) -> void:
	var segments_needed: int = points.size() - 1

	if segments_needed != _last_point_count:
		_last_point_count = segments_needed

	# Dynamic Allocation for Pools
	while _beam_pool.size() < segments_needed:
		var new_beam: MeshInstance3D = MeshInstance3D.new()
		new_beam.mesh = base_beam_mesh.mesh
		new_beam.material_override = base_beam_mesh.material_override
		new_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		new_beam.top_level = true
		add_child(new_beam)
		_beam_pool.append(new_beam)

	if base_beam_particles != null:
		while _beam_particles_pool.size() < segments_needed:
			var new_bp: GPUParticles3D = base_beam_particles.duplicate()
			new_bp.top_level = true
			if new_bp.process_material:
				new_bp.process_material = new_bp.process_material.duplicate()
			add_child(new_bp)
			_beam_particles_pool.append(new_bp)

	if base_smoke_particles != null:
		while _smoke_particles_pool.size() < segments_needed:
			print("StationaryLaserStand: Allocating new smoke system to pool.")
			var new_sp: GPUParticles3D = base_smoke_particles.duplicate()
			new_sp.top_level = true
			# Duplicate material so updates don't propagate across instances
			if new_sp.process_material:
				new_sp.process_material = new_sp.process_material.duplicate()
			add_child(new_sp)
			_smoke_particles_pool.append(new_sp)

	if base_impact_particles != null:
		while _impact_particles_pool.size() < segments_needed:
			var new_ip: GPUParticles3D = base_impact_particles.duplicate()
			new_ip.top_level = true
			add_child(new_ip)
			_impact_particles_pool.append(new_ip)

	while _decal_pool.size() < segments_needed:
		var new_decal: Decal = Decal.new()
		new_decal.texture_albedo = _scorch_texture
		new_decal.texture_emission = _scorch_texture
		new_decal.emission_energy = 1.5
		new_decal.size = Vector3(0.5, 0.5, 0.5)
		new_decal.top_level = true
		add_child(new_decal)
		_decal_pool.append(new_decal)

	var max_size: int = max(
		_beam_pool.size(),
		max(
			max(
				_beam_particles_pool.size(),
				max(_impact_particles_pool.size(), _smoke_particles_pool.size())
			),
			_decal_pool.size()
		)
	)

	for i: int in range(max_size):
		var is_active: bool = i < segments_needed

		# Update Beam Mesh
		if i < _beam_pool.size():
			var beam: MeshInstance3D = _beam_pool[i]
			if beam.visible != is_active:
				beam.visible = is_active

			if is_active:
				var start: Vector3 = points[i]
				var end: Vector3 = points[i + 1]
				var distance: float = start.distance_to(end)

				beam.global_position = start.lerp(end, 0.5)

				if not start.is_equal_approx(end):
					var up_dir: Vector3 = Vector3.UP
					if abs(start.direction_to(end).dot(Vector3.UP)) > 0.99:
						up_dir = Vector3.RIGHT

					beam.look_at(end, up_dir)
					beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)

				beam.scale = Vector3(1.0, distance, 1.0)
				beam.set_instance_shader_parameter("segment_length", distance)

		# Update Core Beam Particles
		if i < _beam_particles_pool.size():
			var bp: GPUParticles3D = _beam_particles_pool[i]
			if bp.emitting != is_active:
				bp.emitting = is_active

			if is_active:
				var start: Vector3 = points[i]
				var end: Vector3 = points[i + 1]
				var distance: float = start.distance_to(end)

				bp.global_position = start.lerp(end, 0.5)

				if not start.is_equal_approx(end):
					var up_dir: Vector3 = Vector3.UP
					if abs(start.direction_to(end).dot(Vector3.UP)) > 0.99:
						up_dir = Vector3.RIGHT
					bp.look_at(end, up_dir)

				var mat: ParticleProcessMaterial = bp.process_material as ParticleProcessMaterial
				if mat:
					mat.emission_box_extents = Vector3(0.05, 0.05, distance / 2.0)

		# Update Drifting Smoke Particles (Portal 2 style)
		if i < _smoke_particles_pool.size():
			var sp: GPUParticles3D = _smoke_particles_pool[i]
			if sp.emitting != is_active:
				sp.emitting = is_active
				if is_active:
					print("StationaryLaserStand: Activating smoke segment ", i)

			if is_active:
				var start: Vector3 = points[i]
				var end: Vector3 = points[i + 1]
				var distance: float = start.distance_to(end)

				sp.global_position = start.lerp(end, 0.5)

				if not start.is_equal_approx(end):
					var up_dir: Vector3 = Vector3.UP
					if abs(start.direction_to(end).dot(Vector3.UP)) > 0.99:
						up_dir = Vector3.RIGHT
					sp.look_at(end, up_dir)

				var mat: ParticleProcessMaterial = sp.process_material as ParticleProcessMaterial
				if mat:
					mat.emission_box_extents = Vector3(0.15, 0.15, distance / 2.0)

					var density_per_meter: float = 20.0
					var target_particles: float = distance * density_per_meter
					var max_capacity: float = float(sp.amount)
					sp.amount_ratio = clampf(target_particles / max_capacity, 0.01, 1.0)

		# Update Impact Particles
		if i < _impact_particles_pool.size():
			var ip: GPUParticles3D = _impact_particles_pool[i]
			if ip.emitting != is_active:
				ip.emitting = is_active

			if is_active:
				var end: Vector3 = points[i + 1]
				var normal: Vector3 = normals[i + 1]

				ip.global_position = end

				if normal != Vector3.ZERO:
					var look_pos: Vector3 = end + normal
					if not end.is_equal_approx(look_pos):
						var up_dir: Vector3 = Vector3.UP
						if abs(normal.dot(Vector3.UP)) > 0.99:
							up_dir = Vector3.RIGHT
						ip.look_at(look_pos, up_dir)

		# Update Active Scorch Decals & Leave Trails
		if i < _decal_pool.size():
			var decal: Decal = _decal_pool[i]
			if decal.visible != is_active:
				decal.visible = is_active

			if is_active:
				var end: Vector3 = points[i + 1]
				var normal: Vector3 = normals[i + 1]

				if decal.global_position.distance_squared_to(end) > 0.005:
					_leave_trail_mark(decal.global_position, decal.global_transform)

				decal.global_position = end

				if normal != Vector3.ZERO:
					var look_pos: Vector3 = end + normal
					if not end.is_equal_approx(look_pos):
						var up_dir: Vector3 = Vector3.UP
						if abs(normal.dot(Vector3.UP)) > 0.99:
							up_dir = Vector3.RIGHT

						decal.look_at(look_pos, up_dir)
						decal.rotate_object_local(Vector3.RIGHT, -PI / 2.0)


## Spawns a fading scorch mark decal at the given position to simulate dragging the laser.
## [param pos]: The global spawn position.
## [param xform]: The basis rotation transform for the decal.
func _leave_trail_mark(pos: Vector3, xform: Transform3D) -> void:
	var trail: Decal = _trail_pool[_trail_index]
	_trail_index = (_trail_index + 1) % MAX_TRAIL_DECALS

	trail.global_transform = xform
	trail.global_position = pos
	trail.visible = true
	trail.albedo_mix = 1.0

	var tween: Tween = create_tween()
	tween.tween_property(trail, "albedo_mix", 0.0, 1.0)
	tween.tween_callback(func() -> void: trail.visible = false)


## Checks for standard player inputs to release control of the stand.
func _handle_detachment_input() -> void:
	# Ensure these string names match your Project Settings -> Input Map exactly!
	if (
		Input.is_action_just_pressed("interact")
		or Input.is_action_just_pressed("jump")
		or Input.is_action_just_pressed("crouch")
	):
		print("StationaryLaserStand: Player requested detachment.")
		_release_control()
