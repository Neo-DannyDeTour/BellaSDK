@tool
## Destructible obstacle destroyed by torch fire, animating radial burn shader.
class_name BurnableObstacle
extends StaticBody3D

## Total duration in seconds for the obstacle to completely burn away.
@export var burn_duration: float = 2.0

## Physical dimensions of the obstacle mesh and collision bounds.
@export var mesh_size: Vector2 = Vector2(2.0, 2.0):
	set = set_mesh_size

## Injected or resolved [MeshInstance3D] rendering the burnable surface.
@export var mesh_instance: MeshInstance3D

## Injected or resolved [CollisionShape3D] blocking movement.
@export var collision_shape: CollisionShape3D

## Injected or resolved [Area3D] detecting intersecting torch flames.
@export var trigger_area: Area3D

## Prevents multiple burn events once the obstacle catches fire.
var _is_burning: bool = false


## Initializes collision areas, material states, and dimensions.
func _ready() -> void:
	print("BurnableObstacle: Initializing burnable obstacle.")
	_resolve_node_references()
	_update_obstacle_size()

	if not Engine.is_editor_hint():
		if is_instance_valid(trigger_area):
			trigger_area.area_entered.connect(_on_trigger_area_entered)
			print("BurnableObstacle: Connected trigger area signals.")
		_initialize_material_state()


## Resolves child node references if unassigned in the inspector.
func _resolve_node_references() -> void:
	print("BurnableObstacle: Resolving node references.")
	if mesh_instance == null:
		var found_mesh: Node = NodeQuery.find_first_child_of_type(self, MeshInstance3D)
		if found_mesh is MeshInstance3D:
			mesh_instance = found_mesh as MeshInstance3D

	if collision_shape == null:
		var found_coll: Node = NodeQuery.find_first_child_of_type(self, CollisionShape3D)
		if found_coll is CollisionShape3D:
			collision_shape = found_coll as CollisionShape3D

	if trigger_area == null:
		var found_area: Node = NodeQuery.find_first_child_of_type(self, Area3D)
		if found_area is Area3D:
			trigger_area = found_area as Area3D


## Caches unique clean [ShaderMaterial] state via [MaterialCache].
func _initialize_material_state() -> void:
	print("BurnableObstacle: Initializing material state via MaterialCache.")
	if not is_instance_valid(mesh_instance):
		return

	var mat: Material = mesh_instance.get_active_material(0)
	if mat is ShaderMaterial:
		var variant_key: String = "burnable_%d" % get_instance_id()
		var unique_mat: ShaderMaterial = (
			MaterialCache.get_variant(mat, variant_key) as ShaderMaterial
		)
		if is_instance_valid(unique_mat):
			unique_mat.set_shader_parameter("radius", 0.0)
			mesh_instance.set_surface_override_material(0, unique_mat)


## Sets physical dimensions of obstacle and updates collision shapes.
func set_mesh_size(value: Vector2) -> void:
	print("BurnableObstacle: Setting mesh size to: ", value)
	mesh_size = value
	if is_inside_tree():
		_resolve_node_references()
		_update_obstacle_size()


## Synchronizes mesh and collision box sizes with [member mesh_size].
func _update_obstacle_size() -> void:
	print("BurnableObstacle: Updating obstacle bounds to: ", mesh_size)
	if is_instance_valid(mesh_instance) and mesh_instance.mesh is QuadMesh:
		mesh_instance.mesh.size = mesh_size

	if is_instance_valid(collision_shape) and collision_shape.shape is BoxShape3D:
		var box: BoxShape3D = collision_shape.shape as BoxShape3D
		box.size = Vector3(mesh_size.x, mesh_size.y, box.size.z)

	if is_instance_valid(trigger_area):
		var trig_coll: CollisionShape3D = (
			NodeQuery.find_first_child_of_type(trigger_area, CollisionShape3D) as CollisionShape3D
		)
		if is_instance_valid(trig_coll) and trig_coll.shape is BoxShape3D:
			var t_box: BoxShape3D = trig_coll.shape as BoxShape3D
			t_box.size = Vector3(mesh_size.x, mesh_size.y, t_box.size.z + 0.1)


## Detects incoming torch flames and triggers ignition sequence.
func _on_trigger_area_entered(area: Area3D) -> void:
	print("BurnableObstacle: Area entered -> ", area.name)
	if _is_burning:
		return

	if area.is_in_group(&"torch_flame"):
		print("BurnableObstacle: Valid torch detected entering trigger area.")
		var torch_node: Node3D = area.get_parent() as Node3D
		if is_instance_valid(torch_node):
			_start_burn(torch_node, area.global_position)


## Initiates radial burn sequence and schedules collision removal.
func _start_burn(torch: Node3D, hit_global_pos: Vector3) -> void:
	print("BurnableObstacle: _start_burn() called. Igniting at ", hit_global_pos)
	_is_burning = true

	var half_timer: SceneTreeTimer = get_tree().create_timer(burn_duration * 0.5, false)
	half_timer.timeout.connect(_disable_solid_collision)

	if is_instance_valid(torch):
		var destroy_timer: SceneTreeTimer = get_tree().create_timer(1.0, false)
		destroy_timer.timeout.connect(
			func() -> void:
				if is_instance_valid(torch):
					print("BurnableObstacle: Destroying torch source.")
					torch.queue_free()
		)

	if not is_instance_valid(mesh_instance):
		return

	var local_pos: Vector3 = mesh_instance.to_local(hit_global_pos)
	var hit_uv: Vector2 = Vector2(
		(local_pos.x / mesh_size.x) + 0.5, (-local_pos.y / mesh_size.y) + 0.5
	)
	print("BurnableObstacle: Calculated Hit UV: ", hit_uv)

	var mat: Material = mesh_instance.get_surface_override_material(0)
	if mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat as ShaderMaterial
		shader_mat.set_shader_parameter("hit_uv", hit_uv)

		var tween: Tween = create_tween()
		tween.tween_method(_update_radius.bind(shader_mat), 0.0, 2.5, burn_duration)
		tween.finished.connect(_on_burn_finished)


## Tween callback continuously updating shader burn expansion radius.
func _update_radius(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("radius", value)


## Disables solid collision midway through the burn sequence.
func _disable_solid_collision() -> void:
	print("BurnableObstacle: _disable_solid_collision() called.")
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_NONE


## Removes the burned obstacle from the scene tree upon completion.
func _on_burn_finished() -> void:
	print("BurnableObstacle: _on_burn_finished() called. Freeing obstacle.")
	queue_free()
