## Stationary laser turret casting continuous reflecting beams and handling player control.
## Emits energy beams, sparks, and smoke using pre-allocated pools to ensure 60 FPS pacing.
class_name StationaryLaserStand
extends StaticBody3D

## The maximum number of scorch trail decals allowed in the object pool.
const MAX_TRAIL_DECALS: int = 60

## Maximum distance the laser beam can travel in a single straight segment.
@export var max_distance: float = 50.0
## Maximum number of reflections allowed off mirrors.
@export var max_bounces: int = 5
## Rotational speed in radians per second when controlled by player.
@export var rotation_speed: float = 2.0

## Indicates whether player is currently actively controlling this stand.
var is_controlled: bool = false
## Reference to the [CharacterBody3D] currently controlling this stand.
var controlling_player: CharacterBody3D = null
## Tracks if player just attached to avoid immediate detachment.
var _just_attached: bool = false
## Last valid node struck by laser receiving a power signal.
var _last_target: Node3D = null
## Pool of [MeshInstance3D] nodes visually representing beam segments.
var _beam_pool: Array[MeshInstance3D] = []
## Pool of [GPUParticles3D] emitting energy particles along beam paths.
var _beam_particles_pool: Array[GPUParticles3D] = []
## Pool of [GPUParticles3D] spawning sparks where laser impacts surfaces.
var _impact_particles_pool: Array[GPUParticles3D] = []
## Pool of [GPUParticles3D] emitting drifting smoke along beam paths.
var _smoke_particles_pool: Array[GPUParticles3D] = []
## Pool of [Decal] nodes representing active scorch marks at impacts.
var _decal_pool: Array[Decal] = []
## Pool of [Decal] nodes leaving fading scorch marks across surfaces.
var _trail_pool: Array[Decal] = []
## Ring buffer index pointer for reusing scorch trail [Decal] nodes.
var _trail_index: int = 0
## Generated [GradientTexture2D] used for active laser burn decals.
var _scorch_texture: GradientTexture2D
## Generated [GradientTexture2D] used for fading trail scorch decals.
var _trail_texture: GradientTexture2D

## Template particle system used for beam core energy effects.
@onready
var base_beam_particles: GPUParticles3D = get_node_or_null("Turret/BeamParticles") as GPUParticles3D
## Template particle system used when laser impacts a surface.
@onready var base_impact_particles: GPUParticles3D = (
	get_node_or_null("Turret/ImpactParticles") as GPUParticles3D
)
## Template particle system used to spawn drifting smoke along laser.
@onready var base_smoke_particles: GPUParticles3D = (
	get_node_or_null("Turret/SmokeParticles") as GPUParticles3D
)
## Rotating mechanism pivot node of the laser stand.
@onready var turret: Node3D = $Turret
## Starting 3D coordinate and rotation from which laser is cast.
@onready var laser_origin: Marker3D = $Turret/LaserOrigin
## Template 3D mesh used to construct segmented laser lines.
@onready var base_beam_mesh: MeshInstance3D = $Turret/BeamMesh
## Interaction component allowing player to assume manual control.
@onready var interact_comp: InteractComponent = $InteractComponent


## Initializes object pools, generated textures, and binds interaction signals.
func _ready() -> void:
	print("StationaryLaserStand: Initializing pools and resources.")
	_scorch_texture = _create_scorch_texture()
	_trail_texture = _create_trail_texture()

	base_beam_mesh.visible = false

	if is_instance_valid(base_beam_particles):
		base_beam_particles.emitting = false
	if is_instance_valid(base_impact_particles):
		base_impact_particles.emitting = false
	if is_instance_valid(base_smoke_particles):
		base_smoke_particles.emitting = false

	if is_instance_valid(interact_comp):
		Utilities.safe_connect(interact_comp.interacted, _on_interacted)

	_initialize_trail_pool()
	_preallocate_beam_pools()


## Pre-allocates all segment pools on boot to achieve 0 runtime allocations.
func _preallocate_beam_pools() -> void:
	var pool_capacity: int = max_bounces + 1
	print("StationaryLaserStand: Pre-allocating pools capacity: ", pool_capacity)

	for i: int in range(pool_capacity):
		var beam: MeshInstance3D = MeshInstance3D.new()
		beam.mesh = base_beam_mesh.mesh
		beam.material_override = base_beam_mesh.material_override
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.top_level = true
		beam.visible = false
		add_child(beam)
		_beam_pool.append(beam)

		if is_instance_valid(base_beam_particles):
			var bp: GPUParticles3D = base_beam_particles.duplicate()
			bp.top_level = true
			bp.emitting = false
			if bp.process_material:
				bp.process_material = (
					MaterialCache.get_instance(bp.process_material) as ParticleProcessMaterial
				)
			add_child(bp)
			_beam_particles_pool.append(bp)

		if is_instance_valid(base_smoke_particles):
			var sp: GPUParticles3D = base_smoke_particles.duplicate()
			sp.top_level = true
			sp.emitting = false
			if sp.process_material:
				sp.process_material = (
					MaterialCache.get_instance(sp.process_material) as ParticleProcessMaterial
				)
			add_child(sp)
			_smoke_particles_pool.append(sp)

		if is_instance_valid(base_impact_particles):
			var ip: GPUParticles3D = base_impact_particles.duplicate()
			ip.top_level = true
			ip.emitting = false
			add_child(ip)
			_impact_particles_pool.append(ip)

		var decal: Decal = Decal.new()
		decal.texture_albedo = _scorch_texture
		decal.texture_emission = _scorch_texture
		decal.emission_energy = 1.5
		decal.size = Vector3(0.5, 0.5, 0.5)
		decal.top_level = true
		decal.visible = false
		add_child(decal)
		_decal_pool.append(decal)


## Initializes trail pool of fading scorch decals.
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


## Creates radial gradient texture for active laser hit scorch mark.
func _create_scorch_texture() -> GradientTexture2D:
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


## Creates radial gradient texture for black fading scorch trail marks.
func _create_trail_texture() -> GradientTexture2D:
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


## Evaluates input, handles player rotation, and processes laser raycasts.
## [param delta] Frame delta time in seconds.
func _physics_process(delta: float) -> void:
	if is_controlled:
		_handle_rotation_input(delta)
		_check_auto_release()

		if _just_attached:
			_just_attached = false
		else:
			_handle_detachment_input()

	_process_laser()


## Handles horizontal rotational user input.
## [param delta] Frame delta time in seconds.
func _handle_rotation_input(delta: float) -> void:
	var turn_input: float = GestureInputManager.get_axis("left", "right")
	if turn_input != 0.0:
		turret.rotate_y(-turn_input * rotation_speed * delta)


## Releases player control if distance exceeds maximum range.
func _check_auto_release() -> void:
	if controlling_player:
		var dist_sq: float = global_position.distance_squared_to(controlling_player.global_position)
		if dist_sq > 9.0:
			print("StationaryLaserStand: Player out of range. Releasing.")
			_release_control()


## Evaluates bouncing laser segments via centralized [CollisionLayers].
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
		query.collision_mask = (CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_INTERACTIVE)
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
			var mirror: ReflectorMirror = (
				NodeQuery.find_ancestor_of_type(collider as Node, ReflectorMirror)
				as ReflectorMirror
			)
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
					exclude_rids.append((collider as CollisionObject3D).get_rid())
				continue

			if collider.has_method("power_on"):
				hit_target = collider as Node3D

		break

	_update_power_target(hit_target)
	_update_beam_visuals(beam_points, beam_normals)


## Delegates power state to nodes struck by laser.
## [param hit_target] Target node receiving power.
func _update_power_target(hit_target: Node3D) -> void:
	if hit_target != _last_target:
		_clear_last_target()
		if hit_target:
			print("StationaryLaserStand: Laser hit valid power target!")
			hit_target.call("power_on")
			_last_target = hit_target


## Powers off the previously struck node upon beam disconnection.
func _clear_last_target() -> void:
	if _last_target != null:
		if _last_target.has_method("power_off"):
			print("StationaryLaserStand: Connection broken. Powering off.")
			_last_target.call("power_off")
		_last_target = null


## Toggles control state when interacted with by a player.
## [param character] Interacting character controller.
func _on_interacted(character: CharacterBody3D) -> void:
	print("StationaryLaserStand: Interaction triggered by player.")
	if not is_controlled:
		_take_control(character)
	else:
		_release_control()


## Binds the given player character to enable manual rotation.
## [param character] Player character instance to bind.
func _take_control(character: CharacterBody3D) -> void:
	print("StationaryLaserStand: Player took control of the stand.")
	is_controlled = true
	_just_attached = true
	controlling_player = character

	if controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(true)


## Releases current player from controlling the stand.
func _release_control() -> void:
	print("StationaryLaserStand: Player released control.")
	is_controlled = false

	if is_instance_valid(controlling_player):
		if controlling_player.has_method("set_machine_lock"):
			controlling_player.set_machine_lock(false)

	controlling_player = null


## Updates visual segments, particles, and decals using pre-allocated pools.
## [param points] Segment start and bounce points.
## [param normals] Surface normals at bounce points.
func _update_beam_visuals(points: PackedVector3Array, normals: PackedVector3Array) -> void:
	var segments_needed: int = points.size() - 1
	var max_capacity: int = _beam_pool.size()

	for i: int in range(max_capacity):
		var is_active: bool = i < segments_needed

		# 1. Beam Mesh
		if i < _beam_pool.size():
			var beam: MeshInstance3D = _beam_pool[i]
			beam.visible = is_active
			if is_active:
				var start: Vector3 = points[i]
				var end: Vector3 = points[i + 1]
				var distance: float = start.distance_to(end)
				beam.global_position = start.lerp(end, 0.5)

				if not start.is_equal_approx(end):
					var up_dir: Vector3 = (
						Vector3.RIGHT
						if absf(start.direction_to(end).dot(Vector3.UP)) > 0.99
						else Vector3.UP
					)
					beam.look_at(end, up_dir)
					beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)

				beam.scale = Vector3(1.0, distance, 1.0)
				beam.set_instance_shader_parameter("segment_length", distance)

		# 2. Beam Particles
		if i < _beam_particles_pool.size():
			var bp: GPUParticles3D = _beam_particles_pool[i]
			bp.emitting = is_active
			if is_active:
				var start: Vector3 = points[i]
				var end: Vector3 = points[i + 1]
				var distance: float = start.distance_to(end)
				bp.global_position = start.lerp(end, 0.5)

				if not start.is_equal_approx(end):
					var up_dir: Vector3 = (
						Vector3.RIGHT
						if absf(start.direction_to(end).dot(Vector3.UP)) > 0.99
						else Vector3.UP
					)
					bp.look_at(end, up_dir)

				var mat: ParticleProcessMaterial = bp.process_material as ParticleProcessMaterial
				if mat:
					mat.emission_box_extents = Vector3(0.05, 0.05, distance * 0.5)

		# 3. Drifting Smoke Particles
		if i < _smoke_particles_pool.size():
			var sp: GPUParticles3D = _smoke_particles_pool[i]
			sp.emitting = is_active
			if is_active:
				var start: Vector3 = points[i]
				var end: Vector3 = points[i + 1]
				var distance: float = start.distance_to(end)
				sp.global_position = start.lerp(end, 0.5)

				if not start.is_equal_approx(end):
					var up_dir: Vector3 = (
						Vector3.RIGHT
						if absf(start.direction_to(end).dot(Vector3.UP)) > 0.99
						else Vector3.UP
					)
					sp.look_at(end, up_dir)

				var smat: ParticleProcessMaterial = sp.process_material as ParticleProcessMaterial
				if smat:
					smat.emission_box_extents = Vector3(0.15, 0.15, distance * 0.5)
					var density: float = 20.0
					var target_count: float = distance * density
					sp.amount_ratio = clampf(target_count / float(sp.amount), 0.01, 1.0)

		# 4. Impact Particles
		if i < _impact_particles_pool.size():
			var ip: GPUParticles3D = _impact_particles_pool[i]
			ip.emitting = is_active
			if is_active:
				var end: Vector3 = points[i + 1]
				var normal: Vector3 = normals[i + 1]
				ip.global_position = end

				if normal != Vector3.ZERO:
					var look_pos: Vector3 = end + normal
					if not end.is_equal_approx(look_pos):
						var up_dir: Vector3 = (
							Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.99 else Vector3.UP
						)
						ip.look_at(look_pos, up_dir)

		# 5. Scorch Decals
		if i < _decal_pool.size():
			var decal: Decal = _decal_pool[i]
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
						var up_dir: Vector3 = (
							Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.99 else Vector3.UP
						)
						decal.look_at(look_pos, up_dir)
						decal.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


## Spawns a fading scorch mark decal at the given position.
## [param pos] Global spawn position.
## [param xform] Basis rotation transform for the decal.
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


## Checks for standard player inputs to release control of stand.
func _handle_detachment_input() -> void:
	if (
		GestureInputManager.is_action_just_pressed("interact")
		or GestureInputManager.is_action_just_pressed("jump")
		or GestureInputManager.is_action_just_pressed("crouch")
	):
		print("StationaryLaserStand: Player requested detachment.")
		_release_control()
