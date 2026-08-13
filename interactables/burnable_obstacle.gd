@tool
class_name BurnableObstacle
extends StaticBody3D

## Burn duration.
@export var burn_duration: float = 2.0
## Mesh size.
@export var mesh_size: Vector2 = Vector2(2.0, 2.0):
	set(value):
		mesh_size = value
		_update_obstacle_size()

## Is burning.
var _is_burning: bool = false


func _ready() -> void:
	_update_obstacle_size()

	if not Engine.is_editor_hint():
		var trigger_area: Area3D = get_node_or_null("TriggerArea") as Area3D
		if trigger_area:
			trigger_area.area_entered.connect(_on_trigger_area_entered)
			print("BurnableObstacle: Connected trigger area for collisions.")

		_initialize_material_state()


func _initialize_material_state() -> void:
	var mesh_node: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_node:
		return

	var mat: Material = mesh_node.get_active_material(0)
	if mat is ShaderMaterial:
		var unique_mat: ShaderMaterial = mat.duplicate() as ShaderMaterial
		unique_mat.set_shader_parameter("radius", 0.0)
		mesh_node.set_surface_override_material(0, unique_mat)
		print("BurnableObstacle: Initialized unique clean material state.")


func _update_obstacle_size() -> void:
	var mesh_node: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	var coll_node: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	var trigger_area: Area3D = get_node_or_null("TriggerArea") as Area3D

	if mesh_node and mesh_node.mesh is QuadMesh:
		mesh_node.mesh.size = mesh_size

	if coll_node and coll_node.shape is BoxShape3D:
		var box: BoxShape3D = coll_node.shape as BoxShape3D
		box.size = Vector3(mesh_size.x, mesh_size.y, box.size.z)

	if trigger_area:
		var trigger_coll: CollisionShape3D = (
			trigger_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		)
		if trigger_coll and trigger_coll.shape is BoxShape3D:
			var t_box: BoxShape3D = trigger_coll.shape as BoxShape3D
			t_box.size = Vector3(mesh_size.x, mesh_size.y, t_box.size.z + 0.1)

	if not Engine.is_editor_hint():
		print("BurnableObstacle: _update_obstacle_size() executed. Sizes matched to ", mesh_size)


func _on_trigger_area_entered(area: Area3D) -> void:
	if _is_burning:
		return

	if area.is_in_group("torch_flame"):
		print("BurnableObstacle: Valid torch detected entering trigger area.")
		var torch_node: Node3D = area.get_parent() as Node3D
		if torch_node:
			_start_burn(torch_node, area.global_position)


func _start_burn(torch: Node3D, hit_global_pos: Vector3) -> void:
	print("BurnableObstacle: _start_burn() called. Igniting at ", hit_global_pos)
	_is_burning = true

	# Trigger collision destruction at half duration
	var half_time_timer: SceneTreeTimer = get_tree().create_timer(burn_duration / 5.0, false)
	half_time_timer.timeout.connect(_disable_solid_collision)

	if is_instance_valid(torch):
		var timer: SceneTreeTimer = get_tree().create_timer(1.0, false)
		timer.timeout.connect(
			func() -> void:
				if is_instance_valid(torch):
					print("BurnableObstacle: 1 second passed. Destroying torch.")
					torch.queue_free()
		)

	var mesh_node: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_node:
		return

	var local_pos: Vector3 = mesh_node.to_local(hit_global_pos)
	var hit_uv: Vector2 = Vector2(
		(local_pos.x / mesh_size.x) + 0.5, (-local_pos.y / mesh_size.y) + 0.5
	)
	print("BurnableObstacle: Calculated Hit UV: ", hit_uv)

	var mat: Material = mesh_node.get_surface_override_material(0)
	if mat is ShaderMaterial:
		mat.set_shader_parameter("hit_uv", hit_uv)

		var tween: Tween = create_tween()
		tween.tween_method(_update_radius.bind(mat), 0.0, 2.5, burn_duration)
		tween.finished.connect(_on_burn_finished)


func _update_radius(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("radius", value)


func _disable_solid_collision() -> void:
	print("BurnableObstacle: _disable_solid_collision() called. Half burn duration reached.")
	var coll_node: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if coll_node:
		coll_node.set_deferred("disabled", true)


func _on_burn_finished() -> void:
	print("BurnableObstacle: _on_burn_finished() called. Destroying obstacle.")
	queue_free()
