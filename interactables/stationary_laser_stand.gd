## Stationary laser turret casting reflecting beams and damaging actors.
class_name StationaryLaserStand
extends StaticBody3D

## Max count of active scorch trail decals maintained in [ObjectPool].
const MAX_TRAIL_DECALS: int = 60

## Detach cooldown guard duration in seconds after taking manual control.
const DETACH_COOLDOWN_SEC: float = 0.35

## Cooldown duration in seconds preventing immediate re-attachment.
const REATTACH_COOLDOWN_SEC: float = 0.4

## Duration in seconds of smooth stance transition tween when taking control.
const ALIGN_TWEEN_DURATION_SEC: float = 0.3

## Continuous damage dealt per second to actors intersecting the beam.
@export var damage_per_second: float = 25.0

## Max distance laser beam travels in a single segment.
@export var max_distance: float = 50.0

## Max reflective bounces across mirror surfaces.
@export var max_bounces: int = 5

## Turret rotational speed in radians per second.
@export var rotation_speed: float = 2.0

## Mouse aiming sensitivity factor while operating the turret.
@export var mouse_sensitivity: float = 0.003

@export_group("Object Pools")

## Dedicated [ObjectPool] managing reusable scorch trail [Decal] nodes.
@export var trail_pool: ObjectPool

## Dedicated [ObjectPool] managing reusable laser impact spark emitters.
@export var impact_emitter_pool: ObjectPool

## Indicates whether player currently exercises active manual control.
var is_controlled: bool = false

## Reference to [Player] controller operating the stand.
var controlling_player: Player = null

## Active tween smoothly aligning player to stance marker position.
var _stance_tween: Tween = null

## Indicates whether player is actively tweening into operating stance.
var _is_aligning: bool = false

## Internal timer preventing accidental frame-zero release inputs.
var _control_timer: float = 0.0

## Timer preventing immediate re-attachment right after detaching.
var _reattach_cooldown_timer: float = 0.0

## Accumulated horizontal mouse input angle applied on next physics tick.
var _pending_mouse_rotation: float = 0.0

## Last node struck by laser receiving power signal via [method power_on].
var _last_target: Node3D = null

## Accumulated fractional damage awaiting whole-number application.
var _damage_accumulator: float = 0.0

## Internal pool of [MeshInstance3D] nodes representing beam segments.
var _beam_pool: Array[MeshInstance3D] = []

## Pool of [GPUParticles3D] emitting energy particles along beam paths.
var _beam_particles_pool: Array[GPUParticles3D] = []

## Pool of [GPUParticles3D] spawning sparks where laser impacts surfaces.
var _impact_particles_pool: Array[GPUParticles3D] = []

## Pool of [Decal] nodes representing active scorch marks at impacts.
var _decal_pool: Array[Decal] = []

## Generated [GradientTexture2D] used for active laser burn albedo.
var _scorch_albedo: GradientTexture2D

## Generated [GradientTexture2D] used for active laser burn emission.
var _scorch_emission: GradientTexture2D

## Generated [GradientTexture2D] used for fading trail scorch decals.
var _trail_texture: GradientTexture2D

## Template particle system used for beam core energy effects.
@onready
var base_beam_particles: GPUParticles3D = get_node_or_null("Turret/BeamParticles") as GPUParticles3D

## Template particle system used when laser impacts a surface.
@onready var base_impact_particles: GPUParticles3D = (
	get_node_or_null("Turret/ImpactParticles") as GPUParticles3D
)

## Visual teardrop mesh instance placed at the laser nozzle origin.
@onready var emitter_drop: MeshInstance3D = (
	get_node_or_null("Turret/LaserOrigin/EmitterDrop") as MeshInstance3D
)

## Rotating mechanism pivot node of the laser stand.
@onready var turret: Node3D = $Turret

## Starting 3D coordinate and rotation from which laser is cast.
@onready var laser_origin: Marker3D = $Turret/LaserOrigin

## Template 3D mesh used to construct segmented laser lines.
@onready var base_beam_mesh: MeshInstance3D = $Turret/BeamMesh

## Marker node designating where the player stands during control.
@onready var stance_marker: Marker3D = (
	(
		get_node_or_null("Turret/StanceMarker") as Marker3D
		if has_node("Turret/StanceMarker")
		else get_node_or_null("StanceMarker")
	)
	as Marker3D
)

## Interaction component allowing player to assume manual control.
@onready var interact_comp: InteractComponent = $InteractComponent


## Initializes object pools, textures, and binds interaction signals.
func _ready() -> void:
	print("StationaryLaserStand: Initializing pools and resources.")
	_scorch_albedo = _create_scorch_albedo_texture()
	_scorch_emission = _create_scorch_emission_texture()
	_trail_texture = _create_trail_texture()

	base_beam_mesh.visible = false

	if is_instance_valid(base_beam_particles):
		base_beam_particles.emitting = false
	if is_instance_valid(base_impact_particles):
		base_impact_particles.emitting = false

	if is_instance_valid(interact_comp):
		interact_comp.interacted.connect(_on_interacted)

	if not is_instance_valid(trail_pool):
		_setup_default_trail_pool()

	_preallocate_beam_pools()


## Instantiates default [ObjectPool] for scorch trail decals if unset.
func _setup_default_trail_pool() -> void:
	print("StationaryLaserStand: Initializing default trail ObjectPool.")
	var decal_template: Decal = _create_trail_decal_node()
	var packed_decal: PackedScene = PackedScene.new()
	var pack_err: Error = packed_decal.pack(decal_template)
	decal_template.queue_free()

	if pack_err != OK:
		push_error("StationaryLaserStand: Failed to pack trail decal template.")
		return

	trail_pool = ObjectPool.new()
	trail_pool.name = "TrailDecalPool"
	trail_pool.template_scene = packed_decal
	trail_pool.initial_pool_size = MAX_TRAIL_DECALS
	trail_pool.can_grow = true
	add_child(trail_pool)


## Helper creating a standalone scorch trail decal instance.
func _create_trail_decal_node() -> Decal:
	var decal: Decal = Decal.new()
	decal.texture_albedo = _trail_texture
	decal.size = Vector3(0.5, 0.5, 0.5)
	decal.top_level = true
	decal.visible = false
	# Physics Layer: Cull non-environment layers
	decal.cull_mask = CollisionLayers.RENDER_MASK_ENVIRONMENT
	return decal


## Pre-allocates laser segment meshes, decals, and particle emitters.
func _preallocate_beam_pools() -> void:
	var pool_capacity: int = max_bounces + 1
	print("StationaryLaserStand: Pre-allocating capacity: ", pool_capacity)

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
			var bp: GPUParticles3D = base_beam_particles.duplicate() as GPUParticles3D
			bp.top_level = true
			bp.emitting = false
			add_child(bp)
			_beam_particles_pool.append(bp)

		if is_instance_valid(base_impact_particles):
			var ip: GPUParticles3D = base_impact_particles.duplicate() as GPUParticles3D
			ip.top_level = true
			ip.emitting = false
			add_child(ip)
			_impact_particles_pool.append(ip)

		var decal: Decal = Decal.new()
		decal.texture_albedo = _scorch_albedo
		decal.texture_emission = _scorch_emission
		decal.emission_energy = 3.0
		decal.size = Vector3(0.5, 0.5, 0.5)
		decal.top_level = true
		decal.visible = false
		add_child(decal)
		_decal_pool.append(decal)


## Creates radial gradient texture for active laser scorch mark albedo.
func _create_scorch_albedo_texture() -> GradientTexture2D:
	print("StationaryLaserStand: Creating scorch albedo texture.")
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 0.8, 1.0])
	grad.colors = PackedColorArray(
		[
			Color(1.0, 0.5, 0.1, 1.0),
			Color(0.6, 0.1, 0.0, 0.95),
			Color(0.02, 0.02, 0.02, 0.95),
			Color(0.01, 0.01, 0.01, 0.5),
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


## Creates radial gradient texture for active laser scorch emission.
func _create_scorch_emission_texture() -> GradientTexture2D:
	print("StationaryLaserStand: Creating scorch emission texture.")
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.38, 1.0])
	grad.colors = PackedColorArray(
		[
			Color(2.5, 0.8, 0.2, 1.0),
			Color(1.0, 0.15, 0.0, 0.8),
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


## Creates radial gradient texture for fading scorch trail marks.
func _create_trail_texture() -> GradientTexture2D:
	print("StationaryLaserStand: Creating trail gradient texture.")
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray(
		[Color(0.02, 0.02, 0.02, 0.9), Color(0.02, 0.02, 0.02, 0.45), Color(0.0, 0.0, 0.0, 0.0)]
	)

	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex


## Evaluates player input, rotates turret, and updates laser bounces.
func _physics_process(delta: float) -> void:
	if _reattach_cooldown_timer > 0.0:
		_reattach_cooldown_timer -= delta

	if is_controlled:
		_control_timer += delta
		_handle_rotation_input(delta)
		_update_controlled_player_transform()
		_check_auto_release()

		if _control_timer >= DETACH_COOLDOWN_SEC:
			_handle_detachment_input()

	_process_laser(delta)


## Captures mouse motion to rotate turret during manual control.
func _input(event: InputEvent) -> void:
	if not is_controlled:
		return

	if event is InputEventMouseMotion:
		var mouse_event: InputEventMouseMotion = event as InputEventMouseMotion
		_pending_mouse_rotation -= mouse_event.relative.x * mouse_sensitivity


## Handles horizontal rotational user input during player control.
func _handle_rotation_input(delta: float) -> void:
	var turn_axis: float = GestureInputManager.get_axis(&"left", &"right")
	if is_zero_approx(turn_axis):
		if InputMap.has_action(&"ui_left") and InputMap.has_action(&"ui_right"):
			turn_axis = Input.get_axis(&"ui_left", &"ui_right")

	var keyboard_rot: float = -turn_axis * rotation_speed * delta
	var total_rot: float = keyboard_rot + _pending_mouse_rotation
	_pending_mouse_rotation = 0.0

	if not is_zero_approx(total_rot):
		turret.rotate_y(total_rot)


## Keeps player positioned and oriented facing stand during control.
func _update_controlled_player_transform() -> void:
	if not is_instance_valid(controlling_player):
		return
	if not is_instance_valid(stance_marker):
		return

	if not _is_aligning:
		controlling_player.global_position = stance_marker.global_position

	var center_point: Vector3 = Vector3(
		global_position.x, controlling_player.global_position.y, global_position.z
	)
	if not controlling_player.global_position.is_equal_approx(center_point):
		controlling_player.look_at(center_point, Vector3.UP)


## Releases player control if distance exceeds maximum allowed range.
func _check_auto_release() -> void:
	if is_instance_valid(controlling_player):
		var check_pos: Vector3 = (
			stance_marker.global_position if is_instance_valid(stance_marker) else global_position
		)
		var dist_sq: float = check_pos.distance_squared_to(controlling_player.global_position)
		if dist_sq > 9.0:
			print("StationaryLaserStand: Player out of range. Releasing.")
			_release_control()


## Raycasts bouncing laser segments through [CollisionLayers] masks.
func _process_laser(delta: float) -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var current_origin: Vector3 = laser_origin.global_position
	var current_direction: Vector3 = -laser_origin.global_transform.basis.z.normalized()

	var bounces: int = 0
	var hit_target: Node3D = null

	var beam_points: PackedVector3Array = PackedVector3Array()
	var beam_normals: PackedVector3Array = PackedVector3Array()
	var surface_hits: Array[bool] = []

	beam_points.append(current_origin)
	beam_normals.append(-current_direction)

	var exclude_rids: Array[RID] = [get_rid()]

	while bounces <= max_bounces:
		var target_pos: Vector3 = current_origin + (current_direction * max_distance)
		var query_mask: int = (
			CollisionLayers.MASK_ENVIRONMENT
			| CollisionLayers.MASK_PLAYER
			| CollisionLayers.MASK_INTERACTIVE
			| CollisionLayers.MASK_ENEMIES
		)
		var result: Dictionary = NodeQuery.cast_ray(
			space_state, current_origin, target_pos, query_mask, exclude_rids
		)

		if result.is_empty():
			beam_points.append(target_pos)
			beam_normals.append(-current_direction)
			surface_hits.append(false)
			_damage_accumulator = 0.0
			break

		var hit_point: Vector3 = result[&"position"]
		var normal: Vector3 = result[&"normal"]
		var collider: Object = result[&"collider"]

		beam_points.append(hit_point)
		beam_normals.append(normal)

		if collider is Node:
			var hit_node: Node = collider as Node
			var mirror: ReflectorMirror = (
				NodeQuery.find_ancestor_of_type(hit_node, ReflectorMirror) as ReflectorMirror
			)
			if mirror:
				var emit_normal: Vector3 = mirror.get_reflection_normal(normal)
				var marker: Marker3D = mirror.get_reflect_marker()
				if is_instance_valid(marker):
					current_origin = marker.global_position + (emit_normal * 0.05)
				else:
					current_origin = hit_point + (emit_normal * 0.05)

				current_direction = emit_normal
				bounces += 1
				exclude_rids.clear()
				if mirror.has_method(&"get_all_rids"):
					exclude_rids.append_array(mirror.get_all_rids())
				elif collider is CollisionObject3D:
					exclude_rids.append((collider as CollisionObject3D).get_rid())

				surface_hits.append(false)
				continue

			_apply_beam_damage(hit_node, delta)

			var candidate_target: Node = hit_node
			if not candidate_target.has_method(&"power_on"):
				candidate_target = NodeQuery.find_ancestor_of_type(hit_node, LaserTarget)
			if not is_instance_valid(candidate_target) and hit_node.get_parent():
				if hit_node.get_parent().has_method(&"power_on"):
					candidate_target = hit_node.get_parent()

			if is_instance_valid(candidate_target) and candidate_target.has_method(&"power_on"):
				hit_target = candidate_target as Node3D

		surface_hits.append(true)
		break

	_update_power_target(hit_target)
	_update_beam_visuals(beam_points, beam_normals, surface_hits)


## Applies continuous beam damage to struck actor or [HealthComponent].
func _apply_beam_damage(target: Node, delta: float) -> void:
	_damage_accumulator += damage_per_second * delta
	if _damage_accumulator < 1.0:
		return

	var damage_amount: int = int(_damage_accumulator)
	_damage_accumulator -= float(damage_amount)
	#print("StationaryLaserStand: Applying ", damage_amount, " damage to: ", target.name)

	var health_comp: Node = target.get_node_or_null("HealthComponent")
	if not is_instance_valid(health_comp):
		health_comp = target.find_child("HealthComponent", true, false)
	if not is_instance_valid(health_comp) and target.get_parent():
		health_comp = target.get_parent().get_node_or_null("HealthComponent")

	if is_instance_valid(health_comp):
		if health_comp.has_method(&"take_damage"):
			health_comp.call(&"take_damage", damage_amount)
			return
		if health_comp.has_method(&"apply_damage"):
			health_comp.call(&"apply_damage", damage_amount)
			return

	if target.has_method(&"take_damage"):
		target.call(&"take_damage", damage_amount)
	elif target.has_method(&"apply_damage"):
		target.call(&"apply_damage", damage_amount)


## Delegates power state to nodes struck by laser via [method power_on].
func _update_power_target(hit_target: Node3D) -> void:
	if hit_target != _last_target:
		_clear_last_target()
		if hit_target:
			print("StationaryLaserStand: Hit target: ", hit_target.name)
			hit_target.call(&"power_on")
			_last_target = hit_target


## Disconnects power from previous target node via [method power_off].
func _clear_last_target() -> void:
	if _last_target != null:
		if _last_target.has_method(&"power_off"):
			print("StationaryLaserStand: Disconnecting: ", _last_target.name)
			_last_target.call(&"power_off")
		_last_target = null


## Entry point for direct interaction calls by player character.
func interact_with(character: CharacterBody3D) -> void:
	print("StationaryLaserStand: Direct interaction from: ", character.name)
	_on_interacted(character)


## Secondary alias for interaction calls by interaction systems.
func interact(character: CharacterBody3D) -> void:
	print("StationaryLaserStand: Secondary interact invoked.")
	interact_with(character)


## Toggles control state when interacted with by a player character.
func _on_interacted(character: CharacterBody3D) -> void:
	print("StationaryLaserStand: Interaction triggered by: ", character.name)
	if _reattach_cooldown_timer > 0.0:
		print("StationaryLaserStand: Interaction rejected during cooldown.")
		return

	var p: Player = character as Player
	if not is_instance_valid(p):
		return

	if not is_controlled:
		_take_control(p)
	elif _control_timer >= DETACH_COOLDOWN_SEC:
		_release_control()


## Binds given player character to enable manual turret rotation.
func _take_control(p: Player) -> void:
	print("StationaryLaserStand: Player took control of stand: ", p.name)
	is_controlled = true
	_control_timer = 0.0
	_pending_mouse_rotation = 0.0
	controlling_player = p

	controlling_player.set_machine_lock(true)

	if is_instance_valid(_stance_tween):
		_stance_tween.kill()

	if is_instance_valid(stance_marker):
		_is_aligning = true
		_stance_tween = create_tween()
		_stance_tween.set_trans(Tween.TRANS_CUBIC)
		_stance_tween.set_ease(Tween.EASE_OUT)
		_stance_tween.tween_property(
			controlling_player,
			"global_position",
			stance_marker.global_position,
			ALIGN_TWEEN_DURATION_SEC
		)
		_stance_tween.tween_callback(
			func() -> void:
				_is_aligning = false
				print("StationaryLaserStand: Player aligned to stance marker.")
		)
	else:
		_is_aligning = false


## Releases current player from controlling the stationary stand.
func _release_control() -> void:
	print("StationaryLaserStand: Player released control of stand.")
	is_controlled = false
	_is_aligning = false
	_control_timer = 0.0
	_reattach_cooldown_timer = REATTACH_COOLDOWN_SEC
	_pending_mouse_rotation = 0.0

	if is_instance_valid(_stance_tween):
		_stance_tween.kill()

	if is_instance_valid(controlling_player):
		controlling_player.set_machine_lock(false)

	controlling_player = null


## Updates segment meshes, particles, and scorch decals from pools.
func _update_beam_visuals(
	points: PackedVector3Array, normals: PackedVector3Array, surface_hits: Array[bool]
) -> void:
	var segments_needed: int = points.size() - 1
	var max_capacity: int = _beam_pool.size()

	for i: int in range(max_capacity):
		var is_active: bool = i < segments_needed
		var is_solid_hit: bool = is_active and i < surface_hits.size() and surface_hits[i]

		if i < _beam_pool.size():
			var beam: MeshInstance3D = _beam_pool[i]
			beam.visible = is_active
			if is_active:
				var start: Vector3 = points[i]
				var end: Vector3 = points[i + 1]
				var distance: float = start.distance_to(end)
				beam.global_position = start.lerp(end, 0.5)

				if not start.is_equal_approx(end):
					var forward_dir: Vector3 = start.direction_to(end)
					var up_dir: Vector3 = (
						Vector3.RIGHT if absf(forward_dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
					)
					beam.look_at(end, up_dir)
					beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)

				beam.scale = Vector3(1.0, distance, 1.0)
				beam.set_instance_shader_parameter(&"segment_length", distance)

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

		if i < _impact_particles_pool.size():
			var ip: GPUParticles3D = _impact_particles_pool[i]
			ip.emitting = is_solid_hit
			if is_solid_hit:
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

		if i < _decal_pool.size():
			var decal: Decal = _decal_pool[i]
			decal.visible = is_solid_hit
			if is_solid_hit:
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


## Spawns a fading scorch mark decal utilizing [member trail_pool].
func _leave_trail_mark(pos: Vector3, xform: Transform3D) -> void:
	if not is_instance_valid(trail_pool):
		return

	var trail_node: Node = null
	if trail_pool.has_method(&"spawn_with_transform"):
		trail_node = trail_pool.spawn_with_transform(xform)
	elif trail_pool.has_method(&"spawn"):
		trail_node = trail_pool.spawn()

	if not is_instance_valid(trail_node):
		trail_node = _create_trail_decal_node()
		add_child(trail_node)

	if trail_node is Decal:
		var d: Decal = trail_node as Decal
		d.global_transform = xform
		d.global_position = pos
		d.visible = true
		d.albedo_mix = 1.0

		var tween: Tween = create_tween()
		tween.tween_property(d, "albedo_mix", 0.0, 1.0)
		tween.tween_callback(
			func() -> void:
				if is_instance_valid(d):
					d.visible = false
					if is_instance_valid(trail_pool) and trail_pool.has_method(&"recycle"):
						trail_pool.recycle(d)
		)


## Checks for standard player detachment inputs to release control.
func _handle_detachment_input() -> void:
	if (
		GestureInputManager.is_action_just_pressed(&"interact")
		or GestureInputManager.is_action_just_pressed(&"jump")
		or GestureInputManager.is_action_just_pressed(&"crouch")
		or Input.is_action_just_pressed(&"ui_cancel")
	):
		print("StationaryLaserStand: Detachment requested.")
		_release_control()
