## A wall-mounted machine providing healing to the player over time when held.
##
## Tracks player proximity with procedural tentacle, updates UI screen, and drains fluid cylinder.
class_name HealthDispenser
extends StaticBody3D

@export_category("Health Settings")

## Texture displayed on screen when player health is very low (<= 33%).
@export var tex_low_health: Texture2D

## Texture displayed on screen when player health is medium (<= 66%).
@export var tex_mid_health: Texture2D

## Texture displayed on screen when player health is high (<= 90%).
@export var tex_almost_health: Texture2D

## Texture displayed on screen when player health is full (> 90%).
@export var tex_ready_health: Texture2D

## Amount of health restored per tick while player holds interact.
@export var heal_amount: int = 25

## Minimum cooldown duration in milliseconds between consecutive healing ticks.
@export var heal_cooldown_msec: int = 250

## Maximum health capacity stored within this dispenser reservoir.
@export var max_dispenser_health: int = 200

@export_category("Node References")

## Screen [Sprite3D] projecting the dynamic health status texture.
@export var screen_sprite: Sprite3D

## Spatial pivot node acting as the root anchor for the procedural tentacle.
@export var tentacle_pivot: Node3D

## Trigger [Area3D] detecting player proximity to animate the tentacle.
@export var detection_area: Area3D

## Mesh representing the fluid cylinder draining as health depletes.
@export var health_cylinder: MeshInstance3D

@export_category("Procedural Tentacle")

## Number of cylindrical mesh segments forming the procedural tentacle.
@export var segment_count: int = 15

## Base albedo color applied to generated procedural tentacle segments.
@export var tentacle_color: Color = Color(0.3, 0.1, 0.4)

## Radial thickness in meters of each procedural cylinder segment.
@export var thickness: float = 0.1

## Maximum physical reach in meters the tentacle can extend toward targets.
@export var max_reach: float = 3.0

## Player character currently inside the proximity detection area.
var _nearby_player: CharacterBody3D = null

## Cached player health component bypassing repetitive string path lookups.
var _player_health_component: Node = null

## Timestamp in milliseconds tracking the last applied heal tick.
var _last_heal_time: int = 0

## Current remaining health points stored within the dispenser reservoir.
var _current_dispenser_health: int = 200

## Initial vertical local offset of the health cylinder mesh.
var _cylinder_initial_pos_y: float = 0.0

## Initial unscaled height of the health cylinder mesh geometry.
var _cylinder_initial_height: float = 1.0

## Isolated material instance for cylinder albedo and color transitions.
var _cylinder_material: StandardMaterial3D = null

## Instanced mesh segment pool forming the procedural tentacle curve.
var _segments: Array[MeshInstance3D] = []

## Reused base cylinder mesh shared across all tentacle segments.
var _base_mesh: CylinderMesh

## Target world coordinate for the tip of the procedural tentacle.
var _current_target_pos: Vector3

## Tension scalar between 0.0 (limp resting) and 1.0 (reaching toward target).
var _active_weight: float = 0.0


## Builds procedural mesh segments, sets resting positions, and prepares health cylinder.
func _ready() -> void:
	print("HealthDispenser: _ready() - Initializing dispenser and tentacle.")

	_current_dispenser_health = max_dispenser_health
	_setup_health_cylinder()
	_create_base_mesh()
	_spawn_visual_segments()

	if is_instance_valid(tentacle_pivot):
		_current_target_pos = (tentacle_pivot.global_position + (Vector3.DOWN * 1.5))
		_update_tentacle_visuals()

	set_physics_process(false)

	if is_instance_valid(detection_area):
		Utilities.safe_connect(detection_area.body_entered, _on_body_entered)
		Utilities.safe_connect(detection_area.body_exited, _on_body_exited)


## Evaluates bezier interpolation to guide procedural tentacle tip toward targets.
## [param delta] Frame delta time in seconds.
func _physics_process(delta: float) -> void:
	var is_targeting: bool = is_instance_valid(_nearby_player)
	var desired_target: Vector3

	if is_targeting:
		_active_weight = move_toward(_active_weight, 1.0, delta * 3.0)
		desired_target = (_nearby_player.global_position + Vector3(0.0, 1.0, 0.0))
	else:
		_active_weight = move_toward(_active_weight, 0.0, delta * 2.0)
		desired_target = tentacle_pivot.global_position + (Vector3.DOWN * 1.5)

	_current_target_pos = _current_target_pos.lerp(desired_target, delta * 6.0)
	_update_tentacle_visuals()

	if _active_weight <= 0.0 and _current_target_pos.is_equal_approx(desired_target):
		print("HealthDispenser: _physics_process() - Tentacle settled, sleep.")
		set_physics_process(false)


# --- PROCEDURAL TENTACLE LOGIC ---


## Creates shared cylinder geometry and material for procedural segments.
func _create_base_mesh() -> void:
	print("HealthDispenser: Creating base cylinder geometry for tentacle.")
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


## Pre-allocates cylinder segment instances under [member tentacle_pivot].
func _spawn_visual_segments() -> void:
	if not is_instance_valid(tentacle_pivot):
		return

	print("HealthDispenser: Spawning visual segments: ", segment_count)
	for i: int in range(segment_count):
		var segment: MeshInstance3D = MeshInstance3D.new()
		segment.mesh = _base_mesh
		segment.top_level = true
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		tentacle_pivot.add_child(segment)
		_segments.append(segment)


## Traverses quadratic bezier curve and orients each individual segment.
func _update_tentacle_visuals() -> void:
	if not is_instance_valid(tentacle_pivot) or _segments.is_empty():
		return

	var p0: Vector3 = tentacle_pivot.global_position
	var p2: Vector3 = _current_target_pos

	var raw_dist: float = p0.distance_to(p2)
	if raw_dist > max_reach:
		var direction: Vector3 = p0.direction_to(p2)
		p2 = p0 + (direction * max_reach)
		raw_dist = max_reach

	var p1: Vector3 = p0.lerp(p2, 0.5)
	p1.y += (raw_dist * 0.6) * _active_weight

	var prev_pos: Vector3 = p0

	for i: int in range(segment_count):
		var t: float = float(i + 1) / float(segment_count)
		var current_pos: Vector3 = _get_quadratic_bezier(p0, p1, p2, t)
		_update_visual_segment(_segments[i], prev_pos, current_pos)
		prev_pos = current_pos


## Computes point along quadratic bezier curve for normalized time [param t].
## [param p0] Start position.
## [param p1] Control point.
## [param p2] End target.
## [param t] Normalized progress between 0.0 and 1.0.
func _get_quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	return q0.lerp(q1, t)


## Aligns, rotates, and scales cylinder segment between two points in 3D space.
## [param segment] Target segment instance.
## [param p1] Origin coordinate.
## [param p2] Destination coordinate.
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


# --- HEALTH CYLINDER LOGIC ---


## Initializes cylinder mesh height, vertical offset, and dynamic material.
func _setup_health_cylinder() -> void:
	if not is_instance_valid(health_cylinder):
		return

	print("HealthDispenser: Setting up health cylinder.")
	_cylinder_initial_pos_y = health_cylinder.position.y

	if health_cylinder.mesh is CylinderMesh:
		_cylinder_initial_height = ((health_cylinder.mesh as CylinderMesh).height)
	else:
		_cylinder_initial_height = 1.0

	_cylinder_material = StandardMaterial3D.new()
	_cylinder_material.roughness = 0.3
	_cylinder_material.albedo_color = Color.GREEN
	health_cylinder.material_override = _cylinder_material

	_update_cylinder_visuals()


## Scales cylinder height and shifts albedo color matching health reservoir ratio.
func _update_cylinder_visuals() -> void:
	if not is_instance_valid(health_cylinder):
		return

	var ratio: float = clampf(
		float(_current_dispenser_health) / float(max_dispenser_health), 0.0, 1.0
	)

	health_cylinder.scale.y = ratio
	var height_lost: float = _cylinder_initial_height * (1.0 - ratio)
	health_cylinder.position.y = _cylinder_initial_pos_y - (height_lost * 0.5)

	if is_instance_valid(_cylinder_material):
		if ratio > 0.50:
			_cylinder_material.albedo_color = Color.GREEN
		elif ratio > 0.25:
			_cylinder_material.albedo_color = Color.YELLOW
		else:
			_cylinder_material.albedo_color = Color.RED


# --- INTERACTION & HEALTH LOGIC ---


## Dispenses health to player during continuous interaction hold events.
## [param _character] Character initiating interaction.
func interact_held(_character: CharacterBody3D) -> void:
	if _current_dispenser_health <= 0:
		print("HealthDispenser: interact_held() - Dispenser depleted.")
		return

	if not is_instance_valid(_player_health_component):
		return

	var current_hp: int = int(_player_health_component.get("current_health"))
	var max_hp: int = int(_player_health_component.get("max_health"))
	var needed_hp: int = max_hp - current_hp

	if needed_hp <= 0:
		print("HealthDispenser: interact_held() - Player already at full HP.")
		return

	var current_time: int = Time.get_ticks_msec()
	if current_time - _last_heal_time >= heal_cooldown_msec:
		_last_heal_time = current_time

		var to_heal: int = mini(heal_amount, mini(_current_dispenser_health, needed_hp))

		print("HealthDispenser: interact_held() - Dispensing ", to_heal, " HP.")
		_player_health_component.call("heal", to_heal)
		_current_dispenser_health -= to_heal
		_update_cylinder_visuals()


## Enables tentacle targeting loop when player character enters detection area.
## [param body] Node entering detection volume.
func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("player"):
		print("HealthDispenser: _on_body_entered() - Player detected.")
		_nearby_player = body
		_connect_player_health(_nearby_player)
		set_physics_process(true)


## Cleans up target references and puts tentacle loop to sleep when player exits.
## [param body] Node exiting detection volume.
func _on_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		print("HealthDispenser: _on_body_exited() - Player departed.")
		_disconnect_player_health()
		_nearby_player = null


## Connects player health change signal using [method Utilities.safe_connect].
## [param player] The detected player character body.
func _connect_player_health(player: CharacterBody3D) -> void:
	print("HealthDispenser: Connecting player health component signals.")
	var health_node: Node = player.get_node_or_null("Components/HealthComponent")

	if is_instance_valid(health_node) and health_node.has_signal("health_changed"):
		_player_health_component = health_node
		Utilities.safe_connect(_player_health_component.health_changed, _on_player_health_changed)
		_update_screen()


## Disconnects active player health signal listener.
func _disconnect_player_health() -> void:
	print("HealthDispenser: Disconnecting player health component signals.")
	if (
		is_instance_valid(_player_health_component)
		and _player_health_component.has_signal("health_changed")
	):
		if _player_health_component.health_changed.is_connected(_on_player_health_changed):
			_player_health_component.health_changed.disconnect(_on_player_health_changed)

	_player_health_component = null


## Refreshes screen texture display when player health changes.
## [param _new_health] Updated health point value.
func _on_player_health_changed(_new_health: int) -> void:
	print("HealthDispenser: Player health changed, refreshing UI screen.")
	_update_screen()


## Selects screen status texture matching current player health brackets.
func _update_screen() -> void:
	if not is_instance_valid(screen_sprite) or not is_instance_valid(_player_health_component):
		return

	var current: float = float(_player_health_component.get("current_health"))
	var maximum: float = float(_player_health_component.get("max_health"))
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
