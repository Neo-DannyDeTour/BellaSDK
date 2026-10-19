## Updraft air vent that lifts player and light pickables, dynamically driving VFX.
@tool
class_name UpdraftVent
extends Area3D

# ------------------------------------------------------------------------------
# CONSTANTS
# ------------------------------------------------------------------------------
## Method name invoked on entities supporting custom updraft entry.
const METHOD_ENTER_UPDRAFT: StringName = &"enter_updraft"

## Method name invoked on entities supporting custom updraft exit.
const METHOD_EXIT_UPDRAFT: StringName = &"exit_updraft"

## Shader parameter driving wind speed in ribbons and streaks.
const PARAM_WIND_SPEED: StringName = &"wind_speed"

## Shader parameter driving vertical bend ratio in paper strips.
const PARAM_LIFT_BEND_RATIO: StringName = &"lift_bend_ratio"

## Shader parameter driving ribbon color.
const PARAM_STRIP_COLOR: StringName = &"strip_color"

## Shader parameter driving streak color in wind lines.
const PARAM_LINE_COLOR: StringName = &"line_color"

## Shader parameter driving smoke color.
const PARAM_SMOKE_COLOR: StringName = &"smoke_color"

## Shader parameter driving flow speed in wind lines.
const PARAM_FLOW_SPEED: StringName = &"flow_speed"

## Preloaded shader resource for the dynamic paper strip ribbons.
const SHADER_PAPER: Shader = preload("res://vfx/updraft_paper_strip.gdshader")

# ------------------------------------------------------------------------------
# EXPORTS
# ------------------------------------------------------------------------------
@export_group("Volume Dimensions")
## Radius of the cylindrical updraft volume in meters.
@export_range(0.2, 20.0, 0.1) var radius: float = 1.0:
	set(value):
		radius = maxf(0.2, value)
		_reconfigure_volume()

## Total height of the updraft column in meters.
@export_range(0.5, 50.0, 0.2) var height: float = 4.0:
	set(value):
		height = maxf(0.5, value)
		_reconfigure_volume()

## Upward target velocity applied to players and light pickables.
@export_range(1.0, 50.0, 0.5) var lift_strength: float = 12.0:
	set(value):
		lift_strength = value
		_update_vfx_speed()

@export_group("Paper Strips")
## Number of paper ribbons distributed around the vent perimeter.
@export_range(0, 16, 1) var paper_strip_count: int = 6:
	set(value):
		paper_strip_count = value
		_rebuild_paper_strips()

## Physical length of each paper strip quad in meters.
@export_range(0.2, 3.0, 0.05) var paper_strip_length: float = 0.8:
	set(value):
		paper_strip_length = value
		_rebuild_paper_strips()

## Physical width of each paper strip quad in meters.
@export_range(0.02, 0.5, 0.01) var paper_strip_width: float = 0.08:
	set(value):
		paper_strip_width = value
		_rebuild_paper_strips()

## Color tint applied to all paper strip meshes.
@export var paper_color: Color = Color(0.95, 0.88, 0.3, 1.0):
	set(value):
		paper_color = value
		_update_strip_materials()

@export_group("VFX Colors")
## Color tint applied to the 3D wind streak particles.
@export var wind_lines_color: Color = Color(0.82, 0.94, 1.0, 0.88):
	set(value):
		wind_lines_color = value
		_update_vfx_materials()

## Color tint applied to smoke puff particles.
@export var smoke_color: Color = Color(0.78, 0.80, 0.83, 0.55):
	set(value):
		smoke_color = value
		_update_vfx_materials()

# ------------------------------------------------------------------------------
# PRIVATE VARIABLES
# ------------------------------------------------------------------------------
## Tracked physical pickables currently floating within the updraft column.
var _active_pickables: Array[RigidBody3D] = []

## Material shared across dynamically constructed paper strip meshes.
var _strip_material: ShaderMaterial = null

# ------------------------------------------------------------------------------
# ONREADY VARIABLES
# ------------------------------------------------------------------------------
## Main physical collision shape for the updraft trigger volume.
@onready
var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D

## Editor-only visual cylinder aid representing the volume bounds.
@onready var debug_mesh: MeshInstance3D = get_node_or_null("DebugCylinderMesh") as MeshInstance3D

## Particle system emitting Nolkaloid 3D wind lines.
@onready
var wind_particles: GPUParticles3D = get_node_or_null(&"WindLineParticles") as GPUParticles3D

## Particle system emitting dust motes rising with the draft.
@onready var dust_particles: GPUParticles3D = get_node_or_null("DustParticles") as GPUParticles3D

## Particle system emitting soft billowing smoke puffs at vent base.
@onready var smoke_particles: GPUParticles3D = get_node_or_null("SmokeParticles") as GPUParticles3D

## Container node holding dynamically oriented paper strips.
@onready var paper_strips_root: Node3D = get_node_or_null("PaperStrips") as Node3D

## Spatial audio player for updraft vent sound loop.
@onready var audio_player: AudioStreamPlayer3D = (
	get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
)


# ------------------------------------------------------------------------------
# LIFECYCLE METHODS
# ------------------------------------------------------------------------------
## Validates scene nodes, hides editor helpers at runtime, and builds systems.
func _ready() -> void:
	print("UpdraftVent: Initializing node on: ", name)
	assert(is_instance_valid(collision_shape), "UpdraftVent: Missing CollisionShape3D node.")

	set_process(false)
	set_physics_process(false)

	if is_instance_valid(debug_mesh) and not Engine.is_editor_hint():
		debug_mesh.hide()

	_reconfigure_volume()
	_rebuild_paper_strips()
	_update_vfx_speed()
	_update_vfx_materials()

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


## Applies damped vertical lift and centering forces to active pickables.
func _physics_process(delta: float) -> void:
	if _active_pickables.is_empty():
		set_physics_process(false)
		return

	var scale_y: float = global_transform.basis.get_scale().y
	var scale_xz: float = maxf(
		global_transform.basis.get_scale().x, global_transform.basis.get_scale().z
	)
	var top_boundary: float = global_position.y + (height * scale_y)
	var world_radius: float = radius * scale_xz
	var radius_squared: float = world_radius * world_radius
	var write_index: int = 0

	for read_index: int in range(_active_pickables.size()):
		var pickable: RigidBody3D = _active_pickables[read_index]
		if not is_instance_valid(pickable) or not pickable.is_inside_tree():
			continue

		# Skip carrying updates while held by the player
		if "is_held" in pickable and bool(pickable.get(&"is_held")):
			_active_pickables[write_index] = pickable
			write_index += 1
			continue

		var horizontal_diff: Vector3 = global_position - pickable.global_position
		horizontal_diff.y = 0.0

		if horizontal_diff.length_squared() > (radius_squared * 1.44):
			# Object has drifted completely out of the updraft cylinder radius
			continue

		if pickable.global_position.y < top_boundary:
			# Damped upward lift matching the player locomotion float feel
			pickable.linear_velocity.y = MathUtils.damp(
				pickable.linear_velocity.y, lift_strength, 4.0, delta
			)
			# Gentle centering damping keeping the object inside the stream
			pickable.linear_velocity.x = MathUtils.damp(
				pickable.linear_velocity.x, horizontal_diff.x * 1.5, 2.0, delta
			)
			pickable.linear_velocity.z = MathUtils.damp(
				pickable.linear_velocity.z, horizontal_diff.z * 1.5, 2.0, delta
			)

		_active_pickables[write_index] = pickable
		write_index += 1

	_active_pickables.resize(write_index)

	if _active_pickables.is_empty():
		set_physics_process(false)


# ------------------------------------------------------------------------------
# SIGNAL HANDLERS
# ------------------------------------------------------------------------------
## Detects entering entities, triggering player flight or registering pickables.
func _on_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	if body.has_method(METHOD_ENTER_UPDRAFT):
		print("UpdraftVent: Entity entered updraft: ", body.name)
		var scale_y: float = global_transform.basis.get_scale().y
		var top_y: float = global_position.y + (height * scale_y)
		body.call(METHOD_ENTER_UPDRAFT, lift_strength, top_y)

	if body is HeavyPickableBox:
		print("UpdraftVent: Heavy pickable box ignored: ", body.name)
		return

	if body is RigidBody3D:
		var rigid_body: RigidBody3D = body as RigidBody3D
		if not _active_pickables.has(rigid_body):
			print("UpdraftVent: Pickable registered in stream: ", rigid_body.name)
			_active_pickables.append(rigid_body)
			set_physics_process(true)


## Detects exiting entities, cleaning up player flight or unregistering pickables.
func _on_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	if body.has_method(METHOD_EXIT_UPDRAFT):
		print("UpdraftVent: Entity exited updraft: ", body.name)
		body.call(METHOD_EXIT_UPDRAFT)

	if body is RigidBody3D:
		var rigid_body: RigidBody3D = body as RigidBody3D
		_active_pickables.erase(rigid_body)
		if _active_pickables.is_empty():
			set_physics_process(false)


# ------------------------------------------------------------------------------
# PRIVATE METHODS
# ------------------------------------------------------------------------------
## Reconfigures collision shape, debug mesh, and particle emitters.
func _reconfigure_volume() -> void:
	if not is_inside_tree():
		return

	var half_height: float = height * 0.5

	# Update collision shape cylinder
	if is_instance_valid(collision_shape):
		var cyl_shape: CylinderShape3D = collision_shape.shape as CylinderShape3D
		if not is_instance_valid(cyl_shape):
			cyl_shape = CylinderShape3D.new()
			collision_shape.shape = cyl_shape
		cyl_shape.radius = radius
		cyl_shape.height = height
		collision_shape.position = Vector3(0.0, half_height, 0.0)

	# Update editor-only debug cylinder
	if is_instance_valid(debug_mesh):
		var cyl_mesh: CylinderMesh = debug_mesh.mesh as CylinderMesh
		if not is_instance_valid(cyl_mesh):
			cyl_mesh = CylinderMesh.new()
			debug_mesh.mesh = cyl_mesh
		cyl_mesh.top_radius = radius
		cyl_mesh.bottom_radius = radius
		cyl_mesh.height = height
		debug_mesh.position = Vector3(0.0, half_height, 0.0)

	# Update particle emitter volumes and lifetimes
	_reconfigure_particle_node(wind_particles, 0.85, 0.75, 1.0)
	_reconfigure_particle_node(dust_particles, 0.8, 0.8, 1.0)
	_reconfigure_particle_node(smoke_particles, 0.65, 0.35, 0.72)

	_rebuild_paper_strips()


## Adjusts a particle system's emission cylinder, speed, height reach, and bounds.
func _reconfigure_particle_node(
	particles: GPUParticles3D,
	radius_multiplier: float,
	speed_ratio: float,
	height_reach_ratio: float
) -> void:
	if not is_instance_valid(particles):
		return

	var mat: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
	if not is_instance_valid(mat):
		return

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = radius * radius_multiplier
	mat.emission_ring_inner_radius = 0.0
	mat.emission_ring_height = clampf(height * 0.06, 0.05, 0.5)
	mat.direction = Vector3(0.0, 1.0, 0.0)

	var particle_speed: float = maxf(1.0, lift_strength * speed_ratio)
	mat.initial_velocity_min = particle_speed * 0.85
	mat.initial_velocity_max = particle_speed * 1.15

	var target_reach: float = height * height_reach_ratio
	var calculated_lifetime: float = target_reach / maxf(0.5, particle_speed)
	particles.lifetime = clampf(calculated_lifetime, 0.4, 8.0)
	if particles.trail_enabled:
		particles.trail_lifetime = clampf(particles.lifetime * 0.55, 0.2, 0.6)

	var bound_ext: float = maxf(2.0, radius * 2.5)
	particles.visibility_aabb = AABB(
		Vector3(-bound_ext, -1.0, -bound_ext),
		Vector3(bound_ext * 2.0, height + 2.5, bound_ext * 2.0)
	)
	particles.visibility_range_end = maxf(40.0, height * 4.0)


## Reconstructs paper ribbon meshes positioned radially at the base rim.
func _rebuild_paper_strips() -> void:
	if not is_inside_tree() or not is_instance_valid(paper_strips_root):
		return

	for child: Node in paper_strips_root.get_children():
		child.queue_free()

	if paper_strip_count <= 0:
		return

	_ensure_strip_material()

	var angle_step: float = TAU / float(paper_strip_count)
	var spawn_radius: float = radius * 0.85

	for index: int in range(paper_strip_count):
		var angle: float = angle_step * float(index)
		var strip_pos: Vector3 = Vector3(cos(angle) * spawn_radius, 0.02, sin(angle) * spawn_radius)

		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = "PaperStrip%d" % index

		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(paper_strip_width, paper_strip_length)
		quad.subdivide_depth = 10
		quad.center_offset = Vector3(0.0, -paper_strip_length * 0.5, 0.0)
		quad.material = _strip_material

		mesh_instance.mesh = quad
		mesh_instance.position = strip_pos

		var inward_dir: Vector3 = -Vector3(cos(angle), 0.0, sin(angle)).normalized()
		var look_basis: Basis = Basis.looking_at(inward_dir, Vector3.UP)
		mesh_instance.transform.basis = look_basis

		paper_strips_root.add_child(mesh_instance)


## Ensures the shared paper strip [ShaderMaterial] is instantiated and configured.
func _ensure_strip_material() -> void:
	if is_instance_valid(_strip_material):
		return

	if is_instance_valid(SHADER_PAPER):
		_strip_material = ShaderMaterial.new()
		_strip_material.shader = SHADER_PAPER
		_update_strip_materials()
		_update_vfx_speed()


## Updates flutter speed and upward bending uniforms across paper strips.
func _update_vfx_speed() -> void:
	if is_instance_valid(_strip_material):
		var flutter_speed: float = clampf(lift_strength * 1.5, 6.0, 45.0)
		var bend_ratio: float = clampf(lift_strength / 12.0, 0.2, 1.8)
		_strip_material.set_shader_parameter(PARAM_WIND_SPEED, flutter_speed)
		_strip_material.set_shader_parameter(PARAM_LIFT_BEND_RATIO, bend_ratio)

	if is_instance_valid(wind_particles):
		var prim_mesh: PrimitiveMesh = wind_particles.draw_pass_1 as PrimitiveMesh
		if is_instance_valid(prim_mesh):
			var mat: ShaderMaterial = prim_mesh.material as ShaderMaterial
			if is_instance_valid(mat):
				mat.set_shader_parameter(PARAM_FLOW_SPEED, clampf(lift_strength * 0.35, 1.5, 12.0))

	if is_instance_valid(audio_player):
		audio_player.pitch_scale = clampf(0.8 + (lift_strength / 25.0) * 0.4, 0.6, 1.8)


## Applies exported ribbon color to the shared paper strip material.
func _update_strip_materials() -> void:
	if is_instance_valid(_strip_material):
		_strip_material.set_shader_parameter(PARAM_STRIP_COLOR, paper_color)


## Applies exported tints to wind line and smoke particle draw passes.
func _update_vfx_materials() -> void:
	if not is_inside_tree():
		return

	if is_instance_valid(wind_particles):
		var wind_prim: PrimitiveMesh = wind_particles.draw_pass_1 as PrimitiveMesh
		if is_instance_valid(wind_prim):
			var mat: ShaderMaterial = wind_prim.material as ShaderMaterial
			if is_instance_valid(mat):
				mat.set_shader_parameter(PARAM_LINE_COLOR, wind_lines_color)

	if is_instance_valid(smoke_particles):
		var smoke_prim: PrimitiveMesh = smoke_particles.draw_pass_1 as PrimitiveMesh
		if is_instance_valid(smoke_prim):
			var smoke_mat: ShaderMaterial = smoke_prim.material as ShaderMaterial
			if is_instance_valid(smoke_mat):
				smoke_mat.set_shader_parameter(PARAM_SMOKE_COLOR, smoke_color)
