class_name HealthDispenser
extends StaticBody3D

@export_category("Health Settings")
@export var tex_low_health: Texture2D
@export var tex_mid_health: Texture2D
@export var tex_almost_health: Texture2D
@export var tex_ready_health: Texture2D
@export var heal_amount: int = 25
@export var heal_cooldown_msec: int = 250

@export_category("Node References")
@export var screen_sprite: Sprite3D
@export var tentacle_pivot: Node3D
@export var detection_area: Area3D

@export_category("Procedural Tentacle")
@export var segment_count: int = 15
@export var tentacle_color: Color = Color(0.3, 0.1, 0.4)
@export var thickness: float = 0.1
@export var max_reach: float = 3.0

var _nearby_player: CharacterBody3D = null
var _player_health_component: HealthComponent = null
var _last_heal_time: int = 0

# Tentacle generation variables
var _segments: Array[MeshInstance3D] = []
var _base_mesh: CylinderMesh
var _current_target_pos: Vector3
var _active_weight: float = 0.0  # 0.0 = Limp, 1.0 = Fully active


func _ready() -> void:
	print("HealthDispenser: _ready() - Initializing dispenser and procedural tentacle.")
	
	_create_base_mesh()
	_spawn_visual_segments()
	
	if is_instance_valid(tentacle_pivot):
		# Set initial resting position straight down
		_current_target_pos = tentacle_pivot.global_position + (Vector3.DOWN * 1.5)
		_update_tentacle_visuals()
	
	set_physics_process(false)
	
	if is_instance_valid(detection_area):
		detection_area.body_entered.connect(_on_body_entered)
		detection_area.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	var is_targeting: bool = is_instance_valid(_nearby_player)
	var desired_target: Vector3
	
	if is_targeting:
		_active_weight = move_toward(_active_weight, 1.0, delta * 3.0)
		desired_target = _nearby_player.global_position + Vector3(0.0, 1.0, 0.0)
	else:
		_active_weight = move_toward(_active_weight, 0.0, delta * 2.0)
		desired_target = tentacle_pivot.global_position + (Vector3.DOWN * 1.5)
	
	# Smoothly move the tip of the tentacle toward the desired position
	_current_target_pos = _current_target_pos.lerp(desired_target, delta * 6.0)
	
	_update_tentacle_visuals()
	
	# Optimization: Turn off processing once fully limp and settled
	if _active_weight <= 0.0 and _current_target_pos.is_equal_approx(desired_target):
		print("HealthDispenser: _physics_process() - Tentacle settled, disabling loop.")
		set_physics_process(false)


# --- PROCEDURAL TENTACLE LOGIC ---

func _create_base_mesh() -> void:
	_base_mesh = CylinderMesh.new()
	_base_mesh.top_radius = thickness
	_base_mesh.bottom_radius = thickness
	_base_mesh.height = 1.0
	_base_mesh.radial_segments = 8
	_base_mesh.rings = 1

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tentacle_color
	mat.roughness = 0.6
	_base_mesh.material = mat


func _spawn_visual_segments() -> void:
	if not is_instance_valid(tentacle_pivot):
		return
		
	for i: int in range(segment_count):
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.mesh = _base_mesh
		segment.top_level = true
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		tentacle_pivot.add_child(segment)
		_segments.append(segment)


func _update_tentacle_visuals() -> void:
	if not is_instance_valid(tentacle_pivot) or _segments.is_empty():
		return
		
	var p0: Vector3 = tentacle_pivot.global_position
	var p2: Vector3 = _current_target_pos
	
	# Clamp maximum distance so it doesn't stretch infinitely
	var raw_dist: float = p0.distance_to(p2)
	if raw_dist > max_reach:
		var direction: Vector3 = p0.direction_to(p2)
		p2 = p0 + (direction * max_reach)
		raw_dist = max_reach

	# The middle control point arcs upwards, but only when active
	var p1: Vector3 = p0.lerp(p2, 0.5)
	p1.y += (raw_dist * 0.6) * _active_weight

	var prev_pos: Vector3 = p0

	for i: int in range(segment_count):
		var t: float = float(i + 1) / float(segment_count)
		var current_pos: Vector3 = _get_quadratic_bezier(p0, p1, p2, t)
		_update_visual_segment(_segments[i], prev_pos, current_pos)
		prev_pos = current_pos


func _get_quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	return q0.lerp(q1, t)


func _update_visual_segment(segment: MeshInstance3D, p1: Vector3, p2: Vector3) -> void:
	var dist_sq: float = p1.distance_squared_to(p2)
	var dist: float = sqrt(dist_sq)
	segment.global_position = p1.lerp(p2, 0.5)

	var dir: Vector3 = p2 - p1
	if dir.length_squared() > 0.000001:
		var up: Vector3 = Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT
		segment.look_at(p2, up)
		segment.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	segment.scale = Vector3(1.0, dist, 1.0)


# --- INTERACTION & HEALTH LOGIC ---

func interact_held(_character: CharacterBody3D) -> void:
	var current_time: int = Time.get_ticks_msec()
	
	if current_time - _last_heal_time >= heal_cooldown_msec:
		_last_heal_time = current_time
		
		if is_instance_valid(_player_health_component):
			_player_health_component.heal(heal_amount)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("player"):
		_nearby_player = body
		_connect_player_health(_nearby_player)
		set_physics_process(true)


func _on_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		_disconnect_player_health()
		_nearby_player = null
		# Process stays true until the tentacle fully settles


func _connect_player_health(player: CharacterBody3D) -> void:
	var health_node: Node = player.get_node_or_null("Components/HealthComponent")
	
	if is_instance_valid(health_node) and health_node is HealthComponent:
		_player_health_component = health_node as HealthComponent
		
		if not _player_health_component.health_changed.is_connected(_on_player_health_changed):
			_player_health_component.health_changed.connect(_on_player_health_changed)
			
		_update_screen()


func _disconnect_player_health() -> void:
	if is_instance_valid(_player_health_component):
		if _player_health_component.health_changed.is_connected(_on_player_health_changed):
			_player_health_component.health_changed.disconnect(_on_player_health_changed)
	
	_player_health_component = null


func _on_player_health_changed(_new_health: int) -> void:
	_update_screen()


func _update_screen() -> void:
	if not is_instance_valid(screen_sprite) or not is_instance_valid(_player_health_component):
		return
		
	var current: float = float(_player_health_component.current_health)
	var maximum: float = float(_player_health_component.max_health)
	var ratio: float = 0.0
	
	if maximum > 0.0:
		ratio = current / maximum
	
	if ratio <= 0.33:
		screen_sprite.texture = tex_low_health
	elif ratio <= 0.66:
		screen_sprite.texture = tex_mid_health
	elif ratio <= 0.90:
		screen_sprite.texture = tex_almost_health
	else:
		screen_sprite.texture = tex_ready_health
