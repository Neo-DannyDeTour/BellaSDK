class_name StationaryLaserStand
extends StaticBody3D

@export var max_distance: float = 50.0
@export var max_bounces: int = 5
@export var rotation_speed: float = 2.0
@export var stance_marker: Marker3D

@onready var turret: Node3D = $Turret
@onready var laser_origin: Marker3D = $Turret/LaserOrigin
@onready var base_beam_mesh: MeshInstance3D = $Turret/BeamMesh
@onready var interact_comp: Interact_Component = $Interact_Component

var _last_target: Node3D = null
var is_controlled: bool = false
var controlling_player: CharacterBody3D = null

# 60 FPS Optimization: Pooling meshes
var _beam_pool: Array[MeshInstance3D] = []
var _last_point_count: int = 0


func _ready() -> void:
	print("StationaryLaserStand: _ready() initialized.")
	base_beam_mesh.visible = false
	
	if interact_comp:
		interact_comp.interacted.connect(_on_interacted)


func _physics_process(delta: float) -> void:
	if is_controlled:
		_handle_rotation_input(delta)
		_check_auto_release()
		
	_process_laser()


func _handle_rotation_input(delta: float) -> void:
	var turn_input: float = Input.get_axis("left", "right")
	
	if turn_input != 0.0:
		print("StationaryLaserStand: Player rotating turret.")
		turret.rotate_y(-turn_input * rotation_speed * delta)


func _check_auto_release() -> void:
	if controlling_player and global_position.distance_to(controlling_player.global_position) > 3.0:
		print("StationaryLaserStand: Player walked too far away. Auto-releasing.")
		_release_control()


func _process_laser() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var current_origin: Vector3 = laser_origin.global_position
	var current_direction: Vector3 = -laser_origin.global_transform.basis.z.normalized()
	
	var bounces: int = 0
	var hit_target: Node3D = null
	var beam_points: PackedVector3Array = PackedVector3Array()
	beam_points.append(current_origin)
	
	var exclude_rids: Array[RID] = [get_rid()] 
	
	while bounces <= max_bounces:
		var target_pos: Vector3 = current_origin + (current_direction * max_distance)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_origin, target_pos)
		query.exclude = exclude_rids
		
		var result: Dictionary = space_state.intersect_ray(query)
		
		if result.is_empty():
			beam_points.append(target_pos)
			break
			
		var hit_point: Vector3 = result["position"]
		var normal: Vector3 = result["normal"]
		var collider: Object = result["collider"]
		
		beam_points.append(hit_point)
		
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
			
			# If we hit a non-mirror object, check if it's a power target, then break the loop
			if collider.has_method("power_on"):
				hit_target = collider as Node3D
				
		break # Critical: Break the loop if we hit a wall to prevent infinite loop crashes
			
	_update_power_target(hit_target)
	_update_beam_visuals(beam_points)


func _get_mirror_root(node: Node) -> ReflectorMirror:
	var current: Node = node
	while current != null:
		if current is ReflectorMirror:
			return current as ReflectorMirror
		current = current.get_parent()
	return null


func _update_power_target(hit_target: Node3D) -> void:
	if hit_target != _last_target:
		_clear_last_target()
		if hit_target:
			print("StationaryLaserStand: Laser hit valid power target!")
			hit_target.power_on()
			_last_target = hit_target


func _clear_last_target() -> void:
	if _last_target != null:
		if _last_target.has_method("power_off"):
			print("StationaryLaserStand: Laser connection broken. Powering off target.")
			_last_target.power_off()
		_last_target = null


func _on_interacted(character: CharacterBody3D) -> void:
	if not is_controlled:
		_take_control(character)
	else:
		_release_control()


func _take_control(character: CharacterBody3D) -> void:
	print("StationaryLaserStand: Player took control of the machine.")
	is_controlled = true
	controlling_player = character
	
	if stance_marker:
		controlling_player.global_transform = stance_marker.global_transform
		controlling_player.velocity = Vector3.ZERO
		
	if controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(true)


func _release_control() -> void:
	print("StationaryLaserStand: Player released control of the machine.")
	is_controlled = false
	
	if controlling_player and controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(false)
		
	controlling_player = null


func _update_beam_visuals(points: PackedVector3Array) -> void:
	var segments_needed: int = points.size() - 1
	
	if segments_needed != _last_point_count:
		print("StationaryLaserStand: Updating beam visuals. Rendering %d segments." % segments_needed)
		_last_point_count = segments_needed

	while _beam_pool.size() < segments_needed:
		var new_beam: MeshInstance3D = MeshInstance3D.new()
		new_beam.mesh = base_beam_mesh.mesh
		new_beam.material_override = base_beam_mesh.material_override
		new_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		turret.add_child(new_beam)
		_beam_pool.append(new_beam)

	for i: int in range(_beam_pool.size()):
		var beam: MeshInstance3D = _beam_pool[i]
		
		if i < segments_needed:
			var start: Vector3 = points[i]
			var end: Vector3 = points[i + 1]
			var segment_length: float = start.distance_to(end)
			
			beam.visible = true
			beam.global_position = start.lerp(end, 0.5)
			
			if not start.is_equal_approx(end):
				var up_dir: Vector3 = Vector3.UP
				if abs(start.direction_to(end).dot(Vector3.UP)) > 0.99:
					up_dir = Vector3.RIGHT
				beam.look_at(end, up_dir)
				
			beam.scale = Vector3(1.0, 1.0, segment_length)
		else:
			beam.visible = false
