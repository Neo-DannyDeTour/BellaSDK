## A wall-mounted machine that provides healing to the player over time when held.
##
## Includes a procedural tentacle animation that tracks the player's position when they approach,
## updates a digital screen to reflect health percentage, and depletes a physical health cylinder.
class_name HealthDispenser
extends StaticBody3D

@export_category("Health Settings")
## The texture displayed on the machine's screen when player health is very low (<= 33%).
@export var tex_low_health: Texture2D
## The texture displayed on the machine's screen when player health is medium (<= 66%).
@export var tex_mid_health: Texture2D
## The texture displayed on the machine's screen when player health is high (<= 90%).
@export var tex_almost_health: Texture2D
## The texture displayed on the machine's screen when player health is full (> 90%).
@export var tex_ready_health: Texture2D
## The amount of health restored per tick while the player holds interact.
@export var heal_amount: int = 25
## The minimum time in milliseconds required between healing ticks.
@export var heal_cooldown_msec: int = 250
## The maximum amount of healing points stored in this dispenser unit.
@export var max_dispenser_health: int = 200

@export_category("Node References")
## The [Sprite3D] node used to project the health status texture on the machine face.
@export var screen_sprite: Sprite3D
## The origin point from which the procedural healing tentacle spawns.
@export var tentacle_pivot: Node3D
## The collision zone that detects player presence to animate the tentacle.
@export var detection_area: Area3D
## The cylinder mesh that visually drains and shifts color as dispenser health depletes.
@export var health_cylinder: MeshInstance3D

@export_category("Procedural Tentacle")
## The number of cylindrical segments making up the flexible tentacle.
@export var segment_count: int = 15
## The base color assigned to the generated tentacle material.
@export var tentacle_color: Color = Color(0.3, 0.1, 0.4)
## The uniform radius of the tentacle cylinder meshes.
@export var thickness: float = 0.1
## The maximum physical distance the tentacle is allowed to stretch toward a player.
@export var max_reach: float = 3.0

## The character currently standing in the detection zone.
var _nearby_player: CharacterBody3D = null
## Cached reference to the player's health node to bypass string lookups during healing.
var _player_health_component: Node = null
## Time tracker for regulating the continuous heal loop.
var _last_heal_time: int = 0
## The current remaining healing points stored in the dispenser.
var _current_dispenser_health: int = 200
## The initial local Y position of the cylinder mesh before scaling offsets.
var _cylinder_initial_pos_y: float = 0.0
## The initial full height of the cylinder mesh.
var _cylinder_initial_height: float = 1.0
## Dedicated unique material for dynamic color adjustments on the health cylinder.
var _cylinder_material: StandardMaterial3D = null

# Tentacle generation variables
## Object pool for the instantiated cylindrical mesh segments.
var _segments: Array[MeshInstance3D] = []
## Template mesh duplicated across all segments.
var _base_mesh: CylinderMesh
## The current interpolated 3D target coordinate for the tip of the tentacle.
var _current_target_pos: Vector3
## Represents the excitement or tension of the tentacle (0.0 = limp, 1.0 = reaching).
var _active_weight: float = 0.0


## Builds the procedural mesh segments, sets resting positions, and prepares the health cylinder.
func _ready() -> void:
	print("HealthDispenser: _ready() - Initializing dispenser and procedural tentacle.")

	_current_dispenser_health = max_dispenser_health
	_setup_health_cylinder()
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


## Calculates the procedural bezier curve animation when the tentacle is active.
## [param delta]: Frame delta time.
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


## Creates the base cylinder geometry assigned to all spawned segments.
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


## Pre-allocates the requested number of mesh instances into the scene tree.
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


## Traverses the bezier curve math to stretch and align each individual segment mesh.
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


## Computes a single coordinate along a quadratic Bezier curve based on time [param t].
## [param p0]: Start coordinate.
## [param p1]: Control point coordinate.
## [param p2]: End coordinate.
## [param t]: Normalized interpolation time (0.0 to 1.0).
## Returns the corresponding point on the curve.
func _get_quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	return q0.lerp(q1, t)


## Applies position, rotation, and scaling transformations to align a cylinder between two points.
## [param segment]: The [MeshInstance3D] to modify.
## [param p1]: The start coordinate for the segment.
## [param p2]: The end coordinate for the segment.
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


## Initializes parameters and materials for the fluid charge cylinder.
func _setup_health_cylinder() -> void:
	if not is_instance_valid(health_cylinder):
		return

	_cylinder_initial_pos_y = health_cylinder.position.y

	if health_cylinder.mesh is CylinderMesh:
		_cylinder_initial_height = (health_cylinder.mesh as CylinderMesh).height
	else:
		_cylinder_initial_height = 1.0

	_cylinder_material = StandardMaterial3D.new()
	_cylinder_material.roughness = 0.3
	_cylinder_material.albedo_color = Color.GREEN
	health_cylinder.material_override = _cylinder_material

	_update_cylinder_visuals()


## Scales the cylinder along the Y-axis and offsets position to keep the base locked in place.
func _update_cylinder_visuals() -> void:
	if not is_instance_valid(health_cylinder):
		return

	var ratio: float = clampf(
		float(_current_dispenser_health) / float(max_dispenser_health), 0.0, 1.0
	)

	# Scale Y while keeping the bottom anchored:
	# Mesh origin is at its center, so offset down by half of the lost height.
	health_cylinder.scale.y = ratio
	var height_lost: float = _cylinder_initial_height * (1.0 - ratio)
	health_cylinder.position.y = _cylinder_initial_pos_y - (height_lost * 0.5)

	# Color shift: 100-50% = Green, 50-25% = Yellow, 25-0% = Red
	if is_instance_valid(_cylinder_material):
		if ratio > 0.50:
			_cylinder_material.albedo_color = Color.GREEN
		elif ratio > 0.25:
			_cylinder_material.albedo_color = Color.YELLOW
		else:
			_cylinder_material.albedo_color = Color.RED


# --- INTERACTION & HEALTH LOGIC ---


## Triggered continuously while the player holds the interact button on the machine.
## Applies healing based on the internal cooldown timer and deducts from the dispenser reservoir.
## Stops dispensing if the dispenser is empty or the player's health is full.
## [param _character]: The player applying the interaction.
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
		print("HealthDispenser: interact_held() - Player already at full health.")
		return

	var current_time: int = Time.get_ticks_msec()
	if current_time - _last_heal_time >= heal_cooldown_msec:
		_last_heal_time = current_time

		# Only deduct and heal what the player actually needs or what remains in stock
		var to_heal: int = mini(heal_amount, mini(_current_dispenser_health, needed_hp))

		print("HealthDispenser: interact_held() - Dispensing ", to_heal, " HP to player.")
		_player_health_component.call("heal", to_heal)
		_current_dispenser_health -= to_heal
		_update_cylinder_visuals()


## Triggers the tentacle animation block to begin processing if a player approaches.
## [param body]: The 3D physics body entering the detection area.
func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("player"):
		print("HealthDispenser: _on_body_entered() - Player detected.")
		_nearby_player = body
		_connect_player_health(_nearby_player)
		set_physics_process(true)


## Ends the target lock for the tentacle when the player departs.
## [param body]: The 3D physics body leaving the detection area.
func _on_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		print("HealthDispenser: _on_body_exited() - Player departed.")
		_disconnect_player_health()
		_nearby_player = null


## Maps to the player's internal components to listen for health changes and update the UI screen.
## [param player]: The detected player object.
func _connect_player_health(player: CharacterBody3D) -> void:
	var health_node: Node = player.get_node_or_null("Components/HealthComponent")

	if is_instance_valid(health_node) and health_node.has_signal("health_changed"):
		_player_health_component = health_node

		if not _player_health_component.health_changed.is_connected(_on_player_health_changed):
			_player_health_component.health_changed.connect(_on_player_health_changed)

		_update_screen()


## Cleans up active signals so the dispenser does not respond to a player outside its zone.
func _disconnect_player_health() -> void:
	if (
		is_instance_valid(_player_health_component)
		and _player_health_component.has_signal("health_changed")
	):
		if _player_health_component.health_changed.is_connected(_on_player_health_changed):
			_player_health_component.health_changed.disconnect(_on_player_health_changed)

	_player_health_component = null


## Refreshes the display texture whenever a change signal is caught.
## [param _new_health]: The raw integer value of the updated health state.
func _on_player_health_changed(_new_health: int) -> void:
	_update_screen()


## Recalculates ratios to swap the active [Sprite3D] texture representing the health brackets.
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
