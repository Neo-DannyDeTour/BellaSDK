@tool
## Procedural lightning orb casting dynamic electric arcs and volumetric atmospheric effects.
#class_name InteractiveLightningOrb
extends Node3D

## Emitted by [method trigger_strike] with [param pos] and [param normal] upon impact.
signal lightning_struck(pos: Vector3, normal: Vector3)

## Physics layer mask combining environment, interactive objects, debris, and enemies.
const ENVIRONMENT_COLLISION_MASK: int = 29

## Visual render layer 3 mask for interactive plasma meshes.
const RENDER_LAYER_INTERACTIVE: int = 4

## Visual render layer 10 mask for volumetric smoke particles.
const RENDER_LAYER_VOLUMETRICS: int = 512

## Combined light cull mask targeting render layers 1, 3, and 10.
const LIGHT_CULL_MASK_COMBINED: int = 517

## Vertical hovering amplitude along the Y-axis.
@export var hover_amplitude: float = 0.25

## Oscillation frequency for the floating hover effect.
@export var hover_speed: float = 2.0

## Total count of primary ground strikes emitted per cycle.
@export var strike_count: int = 3

## Count of air tendrils discharging around the orb sphere.
@export var air_tendril_count: int = 3

## Maximum raycast distance for environment lightning strikes.
@export var strike_range: float = 7.5

## Base jitter displacement strength for fractal arc generation.
@export var arc_jitter_strength: float = 0.45

## Time interval in seconds between arc shape regenerations.
@export var strike_interval: float = 0.04

## Midpoint displacement subdivision generations per arc.
@export_range(2, 6) var arc_generations: int = 4

## Half-width of arc ribbon mesh at the origin of the strike.
@export var root_half_width: float = 0.11

## Half-width of arc ribbon mesh at the tip of the strike.
@export var tip_half_width: float = 0.024

var _time_passed: float = 0.0
var _strike_timer: float = 0.0
var _base_y: float = 2.0

var _orb_container: Node3D
var _core_mesh: MeshInstance3D
var _orb_light: OmniLight3D
var _arc_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _impact_light: OmniLight3D
var _impact_sparks: GPUParticles3D
var _smoke_particles: GPUParticles3D


## Initializes node components, binds materials, and caches base height.
func _ready() -> void:
	print("InteractiveLightningOrb: Initializing orb components.")
	_resolve_or_create_components()
	if is_instance_valid(_orb_container):
		_base_y = _orb_container.position.y


## Drives hover oscillation, decays impact light, and triggers arc updates.
func _process(delta: float) -> void:
	if not is_instance_valid(_arc_instance) or not is_instance_valid(_immediate_mesh):
		_resolve_or_create_components()

	_time_passed += delta

	if is_instance_valid(_orb_container):
		var offset_y: float = sin(_time_passed * hover_speed) * hover_amplitude
		_orb_container.position.y = _base_y + offset_y

	if is_instance_valid(_impact_light) and _impact_light.light_energy > 0.0:
		_impact_light.light_energy = maxf(0.0, _impact_light.light_energy - (delta * 22.0))

	_strike_timer += delta
	if _strike_timer >= strike_interval:
		_strike_timer = 0.0
		_update_lightning_arcs()


## Triggers impact flash and particle burst at [param target_pos].
func trigger_strike(target_pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	#print("InteractiveLightningOrb: Firing lightning strike at ", target_pos)
	lightning_struck.emit(target_pos, normal)
	if is_instance_valid(_impact_light):
		_impact_light.global_position = target_pos + (normal * 0.15)
		_impact_light.light_energy = 8.5
	if is_instance_valid(_impact_sparks):
		_impact_sparks.global_position = target_pos + (normal * 0.05)
		if not normal.is_zero_approx() and absf(normal.dot(Vector3.UP)) < 0.99:
			_impact_sparks.look_at(target_pos + normal, Vector3.UP)
		_impact_sparks.restart()
		_impact_sparks.emitting = true


## Resolves existing scene nodes or dynamically instantiates missing components.
func _resolve_or_create_components() -> void:
	_orb_container = find_child("InteractiveLightningOrb", true, false) as Node3D
	if not is_instance_valid(_orb_container):
		_orb_container = Node3D.new()
		_orb_container.name = "InteractiveLightningOrb"
		_orb_container.position = Vector3(0.0, 2.0, 0.0)
		add_child(_orb_container)

	_core_mesh = _orb_container.find_child("CoreMesh", true, false) as MeshInstance3D
	if not is_instance_valid(_core_mesh):
		_core_mesh = MeshInstance3D.new()
		_core_mesh.name = "CoreMesh"
		_core_mesh.layers = RENDER_LAYER_INTERACTIVE
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.35
		sphere.height = 0.7
		_core_mesh.mesh = sphere
		_orb_container.add_child(_core_mesh)

	var orb_shader: Shader = load("res://environment/lightning_orb.gdshader") as Shader
	if is_instance_valid(orb_shader):
		if not (_core_mesh.material_override is ShaderMaterial):
			var orb_mat: ShaderMaterial = ShaderMaterial.new()
			orb_mat.shader = orb_shader
			_core_mesh.material_override = orb_mat

	_orb_light = _orb_container.find_child("OrbLight", true, false) as OmniLight3D
	if not is_instance_valid(_orb_light):
		_orb_light = OmniLight3D.new()
		_orb_light.name = "OrbLight"
		_orb_light.layers = RENDER_LAYER_INTERACTIVE
		_orb_light.light_color = Color(0.3, 0.75, 1.0)
		_orb_light.light_energy = 5.0
		_orb_light.light_cull_mask = LIGHT_CULL_MASK_COMBINED
		_orb_light.omni_range = 10.0
		_orb_light.omni_attenuation = 1.2
		_orb_container.add_child(_orb_light)

	_arc_instance = _orb_container.find_child("ArcMeshInstance", true, false) as MeshInstance3D
	if not is_instance_valid(_arc_instance):
		_arc_instance = MeshInstance3D.new()
		_arc_instance.name = "ArcMeshInstance"
		_arc_instance.layers = RENDER_LAYER_INTERACTIVE
		_orb_container.add_child(_arc_instance)

	_arc_instance.transform = Transform3D.IDENTITY
	_arc_instance.top_level = false

	if not (_arc_instance.mesh is ImmediateMesh):
		_immediate_mesh = ImmediateMesh.new()
		_arc_instance.mesh = _immediate_mesh
	else:
		_immediate_mesh = _arc_instance.mesh as ImmediateMesh

	if not (_arc_instance.material_override is ShaderMaterial):
		var arc_shader: Shader = load("res://environment/lightning_orb_arc.gdshader") as Shader
		if is_instance_valid(arc_shader):
			var arc_mat: ShaderMaterial = ShaderMaterial.new()
			arc_mat.shader = arc_shader
			_arc_instance.material_override = arc_mat

	_impact_light = _orb_container.find_child("ImpactLight", true, false) as OmniLight3D
	if not is_instance_valid(_impact_light):
		_impact_light = OmniLight3D.new()
		_impact_light.name = "ImpactLight"
		_impact_light.top_level = true
		_impact_light.light_color = Color(0.5, 0.85, 1.0)
		_impact_light.light_energy = 0.0
		_impact_light.light_cull_mask = LIGHT_CULL_MASK_COMBINED
		_impact_light.omni_range = 7.0
		_orb_container.add_child(_impact_light)

	_impact_sparks = _orb_container.find_child("ImpactSparks", true, false) as GPUParticles3D
	if not is_instance_valid(_impact_sparks):
		_impact_sparks = GPUParticles3D.new()
		_impact_sparks.name = "ImpactSparks"
		_impact_sparks.top_level = true
		_impact_sparks.layers = RENDER_LAYER_INTERACTIVE
		_impact_sparks.emitting = false
		_impact_sparks.amount = 36
		_impact_sparks.lifetime = 0.4
		_impact_sparks.one_shot = true
		_impact_sparks.explosiveness = 0.95
		_orb_container.add_child(_impact_sparks)

	_smoke_particles = find_child("VolumetricSmoke", true, false) as GPUParticles3D
	if is_instance_valid(_smoke_particles):
		_smoke_particles.layers = RENDER_LAYER_VOLUMETRICS


## Casts rays into physics environment and builds immediate mesh geometry.
func _update_lightning_arcs() -> void:
	if not is_instance_valid(_immediate_mesh) or not is_inside_tree():
		return

	_immediate_mesh.clear_surfaces()
	# Passing null allows ImmediateMesh to use ArcMeshInstance.material_override
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, null)

	var world_3d: World3D = get_world_3d()
	var space_state: PhysicsDirectSpaceState3D = (
		world_3d.direct_space_state if world_3d != null else null
	)
	var orb_global: Vector3 = (
		_core_mesh.global_position if is_instance_valid(_core_mesh) else global_position
	)

	for i: int in range(strike_count):
		_build_ground_strike(i, orb_global, space_state)

	for j: int in range(air_tendril_count):
		_build_air_tendril()

	_immediate_mesh.surface_end()


## Casts preview strike or raycasts against physics geometry.
func _build_ground_strike(
	index: int, orb_global: Vector3, space_state: PhysicsDirectSpaceState3D
) -> void:
	var random_dir: Vector3 = (
		Vector3(randf_range(-0.85, 0.85), randf_range(-1.0, -0.3), randf_range(-0.85, 0.85))
		. normalized()
	)

	var surface_origin_local: Vector3 = random_dir * 0.35
	var ray_target_global: Vector3 = orb_global + (random_dir * strike_range)
	var end_local: Vector3 = _arc_instance.to_local(ray_target_global)

	if space_state != null and not Engine.is_editor_hint():
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			orb_global, ray_target_global, ENVIRONMENT_COLLISION_MASK
		)
		var hit: Dictionary = space_state.intersect_ray(query)

		if not hit.is_empty():
			var hit_global: Vector3 = hit["position"]
			var hit_normal: Vector3 = hit["normal"]
			end_local = _arc_instance.to_local(hit_global)

			var hit_collider: Object = hit.get("collider", null)
			if hit_collider is RigidBody3D:
				var push: Vector3 = (hit_global - orb_global).normalized() * 2.0
				(hit_collider as RigidBody3D).apply_impulse(push, hit_global)

			if index == 0 and randf() < 0.35:
				trigger_strike(hit_global, hit_normal)

			var local_normal: Vector3 = _arc_instance.global_transform.basis.inverse() * hit_normal
			_build_ground_crawler(end_local, local_normal.normalized())
	else:
		var ground_dist: float = clampf(2.0 / maxf(0.1, -random_dir.y), 1.5, strike_range)
		end_local = surface_origin_local + (random_dir * ground_dist)

		# Triggers random impact preview while running in the editor
		if index == 0 and randf() < 0.35:
			var editor_hit_global: Vector3 = _arc_instance.to_global(end_local)
			trigger_strike(editor_hit_global, Vector3.UP)

	var points: Array[Vector3] = _generate_fractal_points(
		surface_origin_local, end_local, arc_jitter_strength
	)
	_build_ribbon_mesh(points, root_half_width, tip_half_width)


## Creates a curved electrical arc tendril discharging through the air.
func _build_air_tendril() -> void:
	var tendril_dir: Vector3 = (
		Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.9), randf_range(-1.0, 1.0)).normalized()
	)

	var start_local: Vector3 = tendril_dir * 0.35
	var reach: float = randf_range(1.2, 2.5)
	var curl_vector: Vector3 = tendril_dir.cross(Vector3.UP).normalized() * randf_range(-0.6, 0.6)
	var end_local: Vector3 = start_local + (tendril_dir * reach) + curl_vector

	var points: Array[Vector3] = _generate_fractal_points(start_local, end_local, 0.28)
	_build_ribbon_mesh(points, root_half_width * 0.65, tip_half_width * 0.5)


## Generates secondary crawling arcs along the impacted surface plane.
func _build_ground_crawler(origin: Vector3, normal: Vector3) -> void:
	var tangent: Vector3 = normal.cross(Vector3.UP).normalized()
	if tangent.is_zero_approx():
		tangent = normal.cross(Vector3.RIGHT).normalized()
	var bitangent: Vector3 = normal.cross(tangent).normalized()

	var count: int = randi_range(1, 2)
	for k: int in range(count):
		var crawl_dir: Vector3 = (
			(tangent * randf_range(-1.0, 1.0) + bitangent * randf_range(-1.0, 1.0)).normalized()
		)
		var crawl_end: Vector3 = origin + (crawl_dir * randf_range(0.8, 1.8)) + (normal * 0.02)
		var points: Array[Vector3] = _generate_fractal_points(
			origin + (normal * 0.02), crawl_end, 0.18
		)
		_build_ribbon_mesh(points, root_half_width * 0.5, tip_half_width * 0.4)


## Produces midpoint-displaced fractal points between start and end vectors.
func _generate_fractal_points(
	start_pos: Vector3, end_pos: Vector3, jitter: float
) -> Array[Vector3]:
	var points: Array[Vector3] = [start_pos, end_pos]
	var current_displacement: float = jitter

	for gen: int in range(arc_generations):
		var next_points: Array[Vector3] = []
		for i: int in range(points.size() - 1):
			var p1: Vector3 = points[i]
			var p2: Vector3 = points[i + 1]
			var mid: Vector3 = (p1 + p2) * 0.5
			var dir: Vector3 = (p2 - p1).normalized()
			var up_ref: Vector3 = Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
			var side: Vector3 = dir.cross(up_ref).normalized()
			var ortho_up: Vector3 = dir.cross(side).normalized()

			var offset: Vector3 = (
				side * randf_range(-current_displacement, current_displacement)
				+ ortho_up * randf_range(-current_displacement, current_displacement)
			)
			next_points.append(p1)
			next_points.append(mid + offset)
		next_points.append(points.back())
		points = next_points
		current_displacement *= 0.52

	return points


## Constructs 3-plane crossed ribbon quads with width tapering along points.
func _build_ribbon_mesh(points: Array[Vector3], start_w: float, end_w: float) -> void:
	var total_points: int = points.size()
	if total_points < 2:
		return

	for p: int in range(total_points - 1):
		var t1: float = float(p) / float(total_points - 1)
		var t2: float = float(p + 1) / float(total_points - 1)
		var w1: float = lerpf(start_w, end_w, t1)
		var w2: float = lerpf(start_w, end_w, t2)

		_add_ribbon_segment(points[p], points[p + 1], t1, t2, w1, w2)

		if randf() < 0.16 and p > 1 and p < total_points - 3:
			var branch_dir: Vector3 = Vector3(
				randf_range(-0.4, 0.4), randf_range(-0.4, 0.1), randf_range(-0.4, 0.4)
			)
			_add_ribbon_segment(
				points[p], points[p] + branch_dir, t1, t1 + 0.2, w1 * 0.6, end_w * 0.4
			)


## Appends crossed ribbon quads between two points with UVs and given widths.
func _add_ribbon_segment(
	p1: Vector3, p2: Vector3, u1: float, u2: float, w1: float, w2: float
) -> void:
	var dir: Vector3 = (p2 - p1).normalized()
	if dir.is_zero_approx():
		return

	var up_ref: Vector3 = Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	var perp1: Vector3 = dir.cross(up_ref).normalized()
	var perp2: Vector3 = dir.cross(perp1).normalized()

	var angles: Array[float] = [0.0, PI / 3.0, (2.0 * PI) / 3.0]

	for angle: float in angles:
		var n_dir: Vector3 = (perp1 * cos(angle)) + (perp2 * sin(angle))
		var v1_a: Vector3 = p1 - (n_dir * w1)
		var v1_b: Vector3 = p1 + (n_dir * w1)
		var v2_a: Vector3 = p2 - (n_dir * w2)
		var v2_b: Vector3 = p2 + (n_dir * w2)

		_immediate_mesh.surface_set_uv(Vector2(u1, 0.0))
		_immediate_mesh.surface_add_vertex(v1_a)
		_immediate_mesh.surface_set_uv(Vector2(u1, 1.0))
		_immediate_mesh.surface_add_vertex(v1_b)
		_immediate_mesh.surface_set_uv(Vector2(u2, 1.0))
		_immediate_mesh.surface_add_vertex(v2_b)

		_immediate_mesh.surface_set_uv(Vector2(u1, 0.0))
		_immediate_mesh.surface_add_vertex(v1_a)
		_immediate_mesh.surface_set_uv(Vector2(u2, 1.0))
		_immediate_mesh.surface_add_vertex(v2_b)
		_immediate_mesh.surface_set_uv(Vector2(u2, 0.0))
		_immediate_mesh.surface_add_vertex(v2_a)
