## Pooled floor hazard spilled by [EnemySquid] during leap launches and landings.
##
## Applies either a sprint-blocking mucus effect via [signal Events.sand_surface_toggled]
## or a low-friction slippery effect via [signal Events.ice_surface_toggled], using
## static overlap counters so overlapping puddles never clear active player states early.
class_name SquidPuddle
extends Area3D

## Defines the surface movement penalty applied when the player steps in the puddle.
enum PuddleType {
	NO_SPRINT,
	SLIPPERY,
}

## Radius of the cylindrical floor hazard collision and visual decal in meters.
const PUDDLE_RADIUS: float = 1.65

## Vertical thickness of the puddle detector and flattened mesh in meters.
const PUDDLE_HEIGHT: float = 0.08

## Duration of the direct sprint debuff emitted on initial no-sprint puddle contact.
const SPRINT_DEBUFF_SECONDS: float = 1.5

## Slime color used when [enum PuddleType.NO_SPRINT] is active.
const COLOR_NO_SPRINT: Color = Color(0.36, 0.14, 0.42, 0.88)

## Slime color used when [enum PuddleType.SLIPPERY] is active.
const COLOR_SLIPPERY: Color = Color(0.18, 0.52, 0.48, 0.82)

## Group identifier used to verify player body collisions.
const GROUP_PLAYER: StringName = &"player"

## Property name for deferred monitoring state toggles.
const PROP_MONITORING: StringName = &"monitoring"

## Shared count of overlapping no-sprint puddles currently occupied by the player.
static var _active_sand_puddles: int = 0

## Shared count of overlapping slippery puddles currently occupied by the player.
static var _active_ice_puddles: int = 0

## Default movement hazard applied by this puddle instance.
@export var puddle_type: PuddleType = PuddleType.NO_SPRINT

## Lifetime in seconds before the puddle shrinks and returns to the inactive pool.
@export var duration: float = 6.0

## Tracks whether this pooled instance is currently deployed in the world.
var _is_active: bool = false

## Tracks whether the player character is currently overlapping this specific puddle.
var _player_inside: bool = false

## Stores the hazard type committed when [method activate] was last called.
var _committed_type: PuddleType = PuddleType.NO_SPRINT

## Monotonic token incrementing per activation to ignore stale [SceneTreeTimer] callbacks.
var _activation_token: int = 0

## Active [Tween] controlling puddle spawn and despawn scaling.
var _scale_tween: Tween = null

## Generated visual decal mesh representing the spilled squid mucus.
var _mesh_instance: MeshInstance3D = null

## Generated collision cylinder detecting player foot contact.
var _collision_shape: CollisionShape3D = null

## Shared material instance tinted according to active [enum PuddleType].
var _material: StandardMaterial3D = null


## Configures physics masks, generates child geometry, and parks the puddle inactive.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	collision_layer = 0
	collision_mask = Types.MASK_PLAYER
	monitorable = false
	monitoring = false
	visible = false

	_build_puddle_nodes()
	assert(is_instance_valid(_mesh_instance), "SquidPuddle: Missing MeshInstance3D.")
	assert(is_instance_valid(_collision_shape), "SquidPuddle: Missing CollisionShape3D.")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Releases any active surface hazard lock if this puddle is freed while occupied.
func _exit_tree() -> void:
	if _player_inside:
		_remove_surface_effect(_committed_type)
		_player_inside = false
	if is_instance_valid(_scale_tween):
		_scale_tween.kill()
		_scale_tween = null


## Spawns the puddle at [param world_pos] with [param hazard_type] for [member duration].
func activate(world_pos: Vector3, hazard_type: PuddleType) -> void:
	if _player_inside:
		_remove_surface_effect(_committed_type)
		_player_inside = false

	_activation_token += 1
	var current_token: int = _activation_token
	_committed_type = hazard_type
	_is_active = true

	if is_instance_valid(_material):
		if _committed_type == PuddleType.NO_SPRINT:
			_material.albedo_color = COLOR_NO_SPRINT
			_material.roughness = 0.65
		else:
			_material.albedo_color = COLOR_SLIPPERY
			_material.roughness = 0.08

	global_position = world_pos
	scale = Vector3(0.05, 1.0, 0.05)
	visible = true
	set_deferred(PROP_MONITORING, true)

	if is_instance_valid(_scale_tween):
		_scale_tween.kill()
	_scale_tween = create_tween()
	(
		_scale_tween
		. tween_property(self, "scale", Vector3.ONE, 0.18)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)

	print("SquidPuddle: Activated puddle type ", _committed_type, " at ", world_pos)

	var timer: SceneTreeTimer = get_tree().create_timer(duration)
	timer.timeout.connect(_on_duration_expired.bind(current_token))


## Shrinks and parks the puddle back into the inactive pool state.
func deactivate() -> void:
	if not _is_active:
		return

	_is_active = false
	set_deferred(PROP_MONITORING, false)

	if _player_inside:
		_remove_surface_effect(_committed_type)
		_player_inside = false

	if is_instance_valid(_scale_tween):
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(self, "scale", Vector3(0.05, 1.0, 0.05), 0.2).set_trans(
		Tween.TRANS_SINE
	)
	_scale_tween.tween_callback(hide)
	print("SquidPuddle: Deactivated puddle.")


## Builds the procedural cylinder mesh and collision shape for the puddle.
func _build_puddle_nodes() -> void:
	_collision_shape = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = PUDDLE_RADIUS
	cyl_shape.height = PUDDLE_HEIGHT * 2.5
	_collision_shape.shape = cyl_shape
	add_child(_collision_shape)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.layers = 1
	var cyl_mesh: CylinderMesh = CylinderMesh.new()
	cyl_mesh.top_radius = PUDDLE_RADIUS
	cyl_mesh.bottom_radius = PUDDLE_RADIUS * 1.05
	cyl_mesh.height = PUDDLE_HEIGHT
	cyl_mesh.radial_segments = 16
	cyl_mesh.rings = 1

	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR_NO_SPRINT
	_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	cyl_mesh.material = _material

	_mesh_instance.mesh = cyl_mesh
	add_child(_mesh_instance)


## Applies the configured surface penalty when the player steps into the puddle.
func _on_body_entered(body: Node3D) -> void:
	if not _is_active or _player_inside or not is_instance_valid(body):
		return
	var is_player: bool = body.is_in_group(GROUP_PLAYER)
	if not is_player and body is CollisionObject3D:
		var col_obj: CollisionObject3D = body as CollisionObject3D
		is_player = (col_obj.collision_layer & Types.MASK_PLAYER) != 0

	if not is_player:
		return

	_player_inside = true
	_apply_surface_effect(_committed_type)


## Removes the surface penalty when the player steps out of the puddle.
func _on_body_exited(body: Node3D) -> void:
	if not _player_inside or not is_instance_valid(body):
		return
	var is_player: bool = body.is_in_group(GROUP_PLAYER)
	if not is_player and body is CollisionObject3D:
		var col_obj: CollisionObject3D = body as CollisionObject3D
		is_player = (col_obj.collision_layer & Types.MASK_PLAYER) != 0

	if not is_player:
		return

	_player_inside = false
	_remove_surface_effect(_committed_type)


## Callback triggered by [SceneTreeTimer] to expire the puddle if token matches.
func _on_duration_expired(token: int) -> void:
	if token != _activation_token or not is_inside_tree():
		return
	deactivate()


## Increments static overlap counter and notifies [Events] on first puddle entry.
func _apply_surface_effect(effect_type: PuddleType) -> void:
	if effect_type == PuddleType.NO_SPRINT:
		_active_sand_puddles += 1
		Events.sprint_debuff_applied.emit(SPRINT_DEBUFF_SECONDS)
		if _active_sand_puddles == 1:
			print("SquidPuddle: Applying no-sprint surface state.")
			Events.sand_surface_toggled.emit(true)
	else:
		_active_ice_puddles += 1
		if _active_ice_puddles == 1:
			print("SquidPuddle: Applying slippery ice surface state.")
			Events.ice_surface_toggled.emit(true)


## Decrements static overlap counter and clears [Events] state when last puddle exits.
func _remove_surface_effect(effect_type: PuddleType) -> void:
	if effect_type == PuddleType.NO_SPRINT:
		_active_sand_puddles = maxi(0, _active_sand_puddles - 1)
		if _active_sand_puddles == 0:
			print("SquidPuddle: Clearing no-sprint surface state.")
			Events.sand_surface_toggled.emit(false)
			Events.sprint_debuff_applied.emit(SPRINT_DEBUFF_SECONDS)
	else:
		_active_ice_puddles = maxi(0, _active_ice_puddles - 1)
		if _active_ice_puddles == 0:
			print("SquidPuddle: Clearing slippery ice surface state.")
			Events.ice_surface_toggled.emit(false)
