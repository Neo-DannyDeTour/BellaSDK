## Base physical entity supporting player pickup, throws, buoyancy, and focus prompts.
class_name PickableObject
extends RigidBody3D

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Base directory path where prompt button icon textures are stored.
const ICON_BASE_PATH: String = "res://assets/kenney_input-prompts_1.5/Keyboard & Mouse/Default/"

## Minimum distance in meters maintained between player camera and held object.
const MIN_HOLD_DISTANCE: float = 1.2

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Pickable Nodes")
## The [InteractComponent] handling focus and interaction signals.
@export var interact_comp: InteractComponent

## Primary visual [Node3D] representing the object in the world.
@export var mesh: Node3D

## Floating [Label3D] displaying interaction prompts above the object.
@export var label: Label3D

## The [Sprite3D] rendering prompt icon textures beside the label.
@export var prompt_icon: Sprite3D

## Visual [HighlightComponent] applying outline shaders when focused.
@onready var highlight_comp: HighlightComponent = (
	get_node_or_null("HighlightComponent") as HighlightComponent
)

## Physical [CollisionShape3D] bounding the object collision.
@onready var collision: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D

## Default world gravity scalar retrieved from [ProjectSettings].
@onready var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

@export_category("Buoyancy")
## Container node holding [Marker3D] points for water buoyancy sampling.
@export var probe_container: Node3D

## Upward buoyant force multiplier applied when submerged in water.
@export var float_force: float = 3.0

## Linear drag coefficient applied while moving through water bodies.
@export var water_drag: float = 0.5

## Angular drag coefficient dampening rotational motion in water.
@export var water_angular_drag: float = 0.5

@export_category("Hold Settings")
## Additional distance offset pulling held object closer to the player.
@export var hold_distance_offset: float = 0.0

## Maximum separation distance before object automatically drops when stuck.
@export var max_detach_distance: float = 1.3

## Visual mesh transparency applied while the object is held.
@export_range(0.0, 1.0) var held_transparency: float = 0.25

## Mass threshold in kilograms triggering heavy carry handling.
@export var heavy_mass_threshold: float = 10.0

## Downward vertical Y-axis offset applied to held heavy objects.
@export var heavy_y_drop: float = 0.5

## Height clearance above the ground where heavy objects hover.
@export var heavy_floor_clearance: float = 0.08

## Visual mesh transparency applied specifically to heavy held objects.
@export_range(0.0, 1.0) var heavy_held_transparency: float = 0.55

## Minimum impact speed required to register damage against targets.
@export var damage_velocity_threshold: float = 8.0

## Base damage points dealt to colliding actors upon high-speed impact.
@export var projectile_damage: int = 20

@export_category("Stability & Accessibility")
## Locks motion into static platform while player stands on top.
@export var lock_on_player_stand: bool = true

## Dedicated [ShaderMaterial] highlighting the object for accessibility.
@export var vision_assist_material: ShaderMaterial

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Relative yaw angle offset in radians between camera and object.
var _held_relative_yaw: float = 0.0

## Linear velocity vector recorded on preceding physics tick.
var _last_velocity: Vector3 = Vector3.ZERO

## Tracks whether the object is currently grasped by a player.
var is_held: bool = false

## Spatial [Marker3D] target tracking the held object position.
var hold_target: Marker3D = null

## Entity [Node3D] currently holding this physical object.
var holder: Node3D = null

## Determines whether floating text prompt labels are displayed.
var _show_text_prompts: bool = true

## Tracks whether interaction is temporarily locked by systems.
var is_locked: bool = false:
	set(value):
		is_locked = value
		print("PickableObject: is_locked changed to ", is_locked)
		_handle_lock_changed()

## Indicates whether object is inside an active water volume.
var is_in_water: bool = false:
	set(value):
		if is_in_water != value:
			is_in_water = value
			print("PickableObject: is_in_water changed to ", is_in_water)
			_update_process_state()

## Indicates whether the player is currently in noclip flight mode.
var _is_player_flying: bool = false

## Indicates whether object probes are submerged in water.
var submerged: bool = false

## Active water [Node3D] instance applying buoyancy forces.
var current_water_node: Node3D = null

## System time in milliseconds recorded when the object was grabbed.
var _grab_time: int = 0

## Cached [Camera3D] reference to avoid repetitive viewport queries.
var _cached_camera: Camera3D = null

## Cached array of child [Marker3D] probe nodes for buoyancy.
var _probes: Array[Node] = []

## Tracks whether text-to-speech audio prompts are on cooldown.
var _is_tts_cooldown: bool = false

## Timestamp in milliseconds tracking the last water wake ripple.
var _last_wake_time: int = 0

## Submersion state from preceding frame for splash detection.
var _was_submerged: bool = false

## Cached array of [RID] instances excluded from raycast queries.
var _cached_exclude_rids: Array[RID] = []

## Cached formatted mesh name string for zero-allocation TTS prompts.
var _cached_mesh_name: String = ""

## Cached key name string for the interact action prompt label.
var _cached_interact_key: String = "E"

## Frame countdown timer holding static lock when stepped on.
var _standing_lock_ticks: int = 0


## Initializes collision layers, node references, signals, and cache.
func _ready() -> void:
	print("PickableObject: _ready() called. Initializing ", name)
	continuous_cd = true
	collision_layer = CollisionLayers.MASK_INTERACTIVE
	collision_mask = (
		CollisionLayers.MASK_ENVIRONMENT
		| CollisionLayers.MASK_PLAYER
		| CollisionLayers.MASK_INTERACTIVE
	)

	if not is_instance_valid(interact_comp):
		interact_comp = get_node_or_null("InteractComponent") as InteractComponent
	if not is_instance_valid(mesh):
		mesh = get_node_or_null("Mesh") as Node3D
	if not is_instance_valid(label):
		label = get_node_or_null("Label3D") as Label3D
	if not is_instance_valid(prompt_icon):
		prompt_icon = get_node_or_null("PromptIcon") as Sprite3D
	if not is_instance_valid(probe_container):
		probe_container = get_node_or_null("ProbeContainer") as Node3D

	if is_instance_valid(probe_container):
		_probes = probe_container.get_children()

	if is_instance_valid(label):
		label.hide()

	if is_instance_valid(interact_comp):
		interact_comp.focused.connect(_on_interact_component_focused)
		interact_comp.unfocused.connect(_on_interact_component_unfocused)

	sleeping_state_changed.connect(_on_sleeping_state_changed)
	Events.noclip_toggled.connect(_on_noclip_toggled)
	Events.item_prompts_toggled.connect(_on_item_prompts_toggled)

	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)

	_init_cached_strings()
	_cached_exclude_rids = [get_rid()]

	_update_process_state()
	set_model_transparency(self, held_transparency)
	_revert_warmup_deferred()


## Caches clean mesh name and interact key text for zero allocations.
func _init_cached_strings() -> void:
	print("PickableObject: Caching string lookups for UI and TTS.")
	var target_mesh: Node3D = _resolve_visual_mesh()
	if is_instance_valid(target_mesh) and target_mesh != self:
		_cached_mesh_name = target_mesh.name.to_lower().replace("_", " ").strip_edges()
	else:
		_cached_mesh_name = "object"

	var events: Array[InputEvent] = InputMap.action_get_events("interact")
	if not events.is_empty():
		_cached_interact_key = events[0].as_text()


## Clears overlay materials and hides labels when locked state updates.
func _handle_lock_changed() -> void:
	print("PickableObject: Handling lock update -> ", is_locked)
	if is_locked:
		if is_instance_valid(mesh) and mesh is GeometryInstance3D:
			(mesh as GeometryInstance3D).material_overlay = null
		if is_instance_valid(label):
			label.hide()


## Updates text prompt visibility when the global setting is toggled.
func _on_item_prompts_toggled(enabled: bool) -> void:
	print("PickableObject: Item prompt visibility updated -> ", enabled)
	_show_text_prompts = enabled
	if not _show_text_prompts and is_instance_valid(label):
		label.hide()


## Updates flight state cache when noclip mode is toggled.
func _on_noclip_toggled(is_flying: bool) -> void:
	print("PickableObject: Noclip state updated -> ", is_flying)
	_is_player_flying = is_flying


## Toggles physics process mode when physics sleeping state changes.
func _on_sleeping_state_changed() -> void:
	_update_process_state()


## Evaluates whether physics processing should be enabled or disabled.
func _update_process_state() -> void:
	var should_process: bool = is_held or is_in_water or not sleeping or _standing_lock_ticks > 0
	set_physics_process(should_process)


## Reverts startup transparency warmup after shader cache compile.
func _revert_warmup_deferred() -> void:
	print("PickableObject: _revert_warmup_deferred() executing.")
	await get_tree().process_frame
	await get_tree().process_frame
	set_model_transparency(self, 0.0)


## Attaches object to player hold target and applies transparency.
func pick_up(target: Marker3D, player_node: Node3D) -> void:
	if is_locked:
		return

	print("PickableObject: pick_up() called. Grabbed: ", name)
	_grab_time = Time.get_ticks_msec()
	is_held = true
	hold_target = target
	holder = player_node
	_cached_exclude_rids = [get_rid(), holder.get_rid()]

	var cam: Camera3D = _get_camera()
	var cam_yaw: float = (
		cam.global_transform.basis.get_euler().y
		if is_instance_valid(cam)
		else holder.global_transform.basis.get_euler().y
	)
	var obj_yaw: float = global_transform.basis.get_euler().y
	_held_relative_yaw = MathUtils.clamp_angle_rad(obj_yaw - cam_yaw, -PI, PI)

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false
	gravity_scale = 0.0

	var alpha: float = (
		heavy_held_transparency if mass >= heavy_mass_threshold else held_transparency
	)
	set_model_transparency(self, alpha)

	if is_instance_valid(interact_comp):
		interact_comp.set("is_currently_focused", false)
		if interact_comp.has_signal("unfocused"):
			interact_comp.unfocused.emit()
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	add_collision_exception_with(holder)

	if mass >= heavy_mass_threshold:
		notify_holder_heavy_carry(holder, true, mass)

	_update_process_state()
	Events.item_picked_up.emit(self, holder)


## Releases object from player grasp, restoring full visibility.
func drop() -> void:
	print("PickableObject: drop() called. Action: Dropping object.")
	is_held = false

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()

	_is_tts_cooldown = true
	get_tree().create_timer(1.5).timeout.connect(_reset_tts_cooldown)

	set_model_transparency(self, 0.0)

	if is_locked:
		holder = null
		_cached_exclude_rids = [get_rid()]
		if is_instance_valid(interact_comp):
			interact_comp.set("is_currently_focused", false)
		_update_process_state()
		return

	freeze = false
	sleeping = false
	gravity_scale = 1.0

	if is_instance_valid(holder):
		if mass >= heavy_mass_threshold:
			notify_holder_heavy_carry(holder, false, 0.0)

		if "velocity" in holder:
			linear_velocity = holder.get("velocity") as Vector3

		var cam_forward: Vector3 = Vector3.FORWARD
		var cam: Camera3D = _get_camera()
		if is_instance_valid(cam):
			cam_forward = -cam.global_transform.basis.z

		var flat_cam_forward: Vector3 = Vector3(cam_forward.x, 0.0, cam_forward.z)
		var push_dir: Vector3 = flat_cam_forward.normalized()

		var clear_impulse_mag: float = maxf(mass * 1.5, 5.0)
		var toss_dir: Vector3 = push_dir
		toss_dir.y = 0.2
		apply_central_impulse(toss_dir.normalized() * clear_impulse_mag)

		Events.item_dropped.emit(self, holder)

		var previous_holder: Node3D = holder
		wait_to_enable_collision(previous_holder)

	holder = null
	_cached_exclude_rids = [get_rid()]
	wait_for_rest_to_enable_interact()
	_update_process_state()


## Drops object and applies impulse vector [param impulse_vector].
func throw(impulse_vector: Vector3) -> void:
	print("PickableObject: throw() called with force: ", impulse_vector.length())
	drop()
	if not is_locked:
		apply_central_impulse(impulse_vector)


## Informs holder locomotion component of heavy carry status.
func notify_holder_heavy_carry(p_holder: Node3D, active: bool, mass_val: float) -> void:
	print("PickableObject: Updating holder heavy carry status: ", active)
	if not is_instance_valid(p_holder):
		return

	var loco_comp: Node = (
		p_holder.get("locomotion_component") if "locomotion_component" in p_holder else p_holder
	)
	if is_instance_valid(loco_comp):
		if loco_comp.has_method("set_heavy_carry"):
			loco_comp.call("set_heavy_carry", active, mass_val)
		else:
			if "can_sprint" in loco_comp:
				loco_comp.set("can_sprint", not active)
			if "can_jump" in loco_comp:
				loco_comp.set("can_jump", not active)
			if "sprint_active" in loco_comp and active:
				loco_comp.set("sprint_active", false)

	if "can_jump" in p_holder:
		p_holder.set("can_jump", not active)


## Informs holder interaction scanner of heavy lifting stance.
func notify_holder_heavy_lifting(p_holder: Node3D, active: bool) -> void:
	print("PickableObject: Updating holder heavy lifting stance: ", active)
	if not is_instance_valid(p_holder):
		return

	var int_comp: Node = (
		p_holder.get("interaction_component") if "interaction_component" in p_holder else null
	)
	if is_instance_valid(int_comp):
		if "is_heavy_lifting" in int_comp:
			int_comp.set("is_heavy_lifting", active)
		var scanner: Node = (
			int_comp.get("interaction_scanner") if "interaction_scanner" in int_comp else null
		)
		if is_instance_valid(scanner):
			if active and "heavy_lift_yaw_base" in scanner:
				scanner.set("heavy_lift_yaw_base", p_holder.global_rotation.y)
			if scanner.has_method("set_heavy_lifting"):
				scanner.call("set_heavy_lifting", active)


## Toggles input stun on the holder system menu controller.
func notify_holder_stun(p_holder: Node3D, stunned: bool) -> void:
	print("PickableObject: Setting holder stun state: ", stunned)
	if not is_instance_valid(p_holder):
		return
	if "is_stunned" in p_holder:
		p_holder.set("is_stunned", stunned)
	var sys_menu: Node = p_holder.get("system_menu") if "system_menu" in p_holder else null
	if is_instance_valid(sys_menu) and "is_stunned" in sys_menu:
		sys_menu.set("is_stunned", stunned)


## Instructs holder interaction component to force clear held items.
func notify_holder_clear_hands(p_holder: Node3D) -> void:
	print("PickableObject: Clearing held hands on holder.")
	if not is_instance_valid(p_holder):
		return
	var int_comp: Node = (
		p_holder.get("interaction_component") if "interaction_component" in p_holder else null
	)
	if is_instance_valid(int_comp) and int_comp.has_method("force_clear_hands"):
		int_comp.call("force_clear_hands")


## Recursively applies transparency across child [GeometryInstance3D].
func set_model_transparency(parent_node: Node, alpha: float) -> void:
	if not is_instance_valid(parent_node):
		return

	if parent_node is GeometryInstance3D:
		var geom: GeometryInstance3D = parent_node as GeometryInstance3D
		geom.transparency = alpha

	for child: Node in parent_node.get_children():
		set_model_transparency(child, alpha)


## Backwards-compatible alias for child classes calling transparency.
func _set_model_transparency(parent_node: Node, alpha: float) -> void:
	set_model_transparency(parent_node, alpha)


## Computes vertical distance from origin to bottom edge when upright.
func _get_upright_bottom_extent() -> float:
	if is_instance_valid(collision) and collision.shape != null:
		var shape: Shape3D = collision.shape
		if shape is CylinderShape3D:
			return (shape as CylinderShape3D).height * 0.5 - collision.position.y
		if shape is CapsuleShape3D:
			return (shape as CapsuleShape3D).height * 0.5 - collision.position.y
		if shape is BoxShape3D:
			return (shape as BoxShape3D).size.y * 0.5 - collision.position.y

	var target_mesh: Node3D = _resolve_visual_mesh()
	if target_mesh is VisualInstance3D:
		var aabb: AABB = (target_mesh as VisualInstance3D).get_aabb()
		return (aabb.size.y * 0.5) - target_mesh.position.y

	return 0.5


## Locks object into a static platform while player stands on it.
func register_player_standing() -> void:
	if not lock_on_player_stand or is_held:
		return

	_standing_lock_ticks = 4
	if not freeze:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_update_process_state()


## Waits until holder is out of range before restoring collisions.
func wait_to_enable_collision(p_holder: Node3D) -> void:
	print("PickableObject: Waiting to restore player collision.")
	var max_wait_frames: int = 30
	var current_frame: int = 0

	while (
		is_instance_valid(self) and is_instance_valid(p_holder) and current_frame < max_wait_frames
	):
		var flat_my_pos: Vector2 = Vector2(global_position.x, global_position.z)
		var flat_player_pos: Vector2 = Vector2(
			p_holder.global_position.x, p_holder.global_position.z
		)

		if flat_my_pos.distance_squared_to(flat_player_pos) >= 1.0:
			break

		current_frame += 1
		await get_tree().physics_frame

	if is_instance_valid(self) and is_instance_valid(p_holder):
		remove_collision_exception_with(p_holder)


## Re-enables interact component once the object has settled to rest.
func wait_for_rest_to_enable_interact() -> void:
	if is_instance_valid(interact_comp):
		interact_comp.set("is_currently_focused", false)
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	while is_instance_valid(self) and not is_held:
		await get_tree().physics_frame
		if linear_velocity.length() < 0.35 and (sleeping or is_on_floor_approx()):
			break

	if is_instance_valid(self) and not is_held and is_instance_valid(interact_comp):
		interact_comp.process_mode = Node.PROCESS_MODE_INHERIT


## Returns true if the object is resting on environment geometry.
func is_on_floor_approx() -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var res: Dictionary = NodeQuery.cast_ray(
		space_state,
		global_position,
		global_position + Vector3(0.0, -0.6, 0.0),
		CollisionLayers.MASK_ENVIRONMENT,
		[get_rid()]
	)
	return not res.is_empty()


## Resets cooldown flag for text-to-speech focus announcements.
func _reset_tts_cooldown() -> void:
	print("PickableObject: _reset_tts_cooldown() called.")
	_is_tts_cooldown = false


## Displays prompts and triggers TTS cue when focused by scanner.
func _on_interact_component_focused() -> void:
	print("PickableObject: Focused by interaction scanner.")
	if is_locked or is_held:
		return

	if linear_velocity.length() > 0.8:
		if is_instance_valid(label):
			label.hide()
		if is_instance_valid(prompt_icon):
			prompt_icon.hide()
		return

	_update_label_text()
	if is_instance_valid(label) and _show_text_prompts:
		label.show()
	if is_instance_valid(prompt_icon) and prompt_icon.texture != null:
		prompt_icon.show()

	if not _is_tts_cooldown:
		var tts_prompt: String = (
			"Press %s to grab %s" % [_cached_interact_key, _cached_mesh_name]
			if not _cached_interact_key.is_empty()
			else "Grab %s" % _cached_mesh_name
		)
		Events.object_focused.emit(tts_prompt, mesh)


## Refreshes the prompt label text with the cached interact key.
func _update_label_text() -> void:
	print("PickableObject: _update_label_text() updating prompts.")
	if is_instance_valid(label):
		label.text = "Press [%s] to grab" % _cached_interact_key
		label.position.x = 0.0


## Hides floating prompt labels and icons when focus is lost.
func _on_interact_component_unfocused() -> void:
	print("PickableObject: Unfocused by interaction scanner.")
	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()


## Evaluates hold tracking, standing locks, and water buoyancy.
func _physics_process(delta: float) -> void:
	if not is_held and lock_on_player_stand and _standing_lock_ticks > 0:
		_standing_lock_ticks -= 1
		if _standing_lock_ticks == 0 and freeze:
			freeze = false
			_update_process_state()

	if is_held and is_instance_valid(hold_target) and is_instance_valid(holder):
		_process_standard_hold(delta)

	_process_buoyancy()
	_last_velocity = linear_velocity


## Solves linear and angular spring velocities toward hold target.
func _process_standard_hold(_delta: float) -> void:
	var target_pos: Vector3 = hold_target.global_position
	var cam: Camera3D = _get_camera()
	var cam_origin: Vector3 = (
		cam.global_position if is_instance_valid(cam) else holder.global_position
	)
	var cam_forward: Vector3 = (
		-cam.global_transform.basis.z if is_instance_valid(cam) else Vector3.FORWARD
	)

	var is_heavy: bool = mass >= heavy_mass_threshold

	if is_heavy:
		var flat_forward: Vector3 = Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
		var carry_dist: float = maxf(MIN_HOLD_DISTANCE - hold_distance_offset, 1.1)
		target_pos = holder.global_position + (flat_forward * carry_dist)

		var bottom_extent: float = _get_upright_bottom_extent()
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var floor_hit: Dictionary = NodeQuery.cast_ray(
			space_state,
			target_pos + Vector3(0.0, 0.5, 0.0),
			target_pos + Vector3(0.0, -2.0, 0.0),
			CollisionLayers.MASK_ENVIRONMENT,
			_cached_exclude_rids
		)
		if not floor_hit.is_empty():
			var ground_y: float = (floor_hit.position as Vector3).y
			target_pos.y = ground_y + bottom_extent + heavy_floor_clearance
		else:
			target_pos.y = (
				holder.global_position.y + bottom_extent + heavy_floor_clearance - heavy_y_drop
			)
	else:
		var to_target: Vector3 = target_pos - cam_origin
		var forward_projection: float = to_target.dot(cam_forward)
		var required_dist: float = maxf(MIN_HOLD_DISTANCE - hold_distance_offset, 0.8)

		if forward_projection < required_dist:
			target_pos += cam_forward * (required_dist - forward_projection)

	var dist_sq: float = global_position.distance_squared_to(target_pos)
	var has_grab_settled: bool = (Time.get_ticks_msec() - _grab_time) > 250
	var detach_threshold_sq: float = max_detach_distance * max_detach_distance
	if dist_sq > detach_threshold_sq and has_grab_settled and not _is_player_flying:
		print("PickableObject: Stuck distance exceeded. Dropping: ", name)
		drop()
		return

	var holder_velocity: Vector3 = (
		holder.get("velocity") as Vector3 if "velocity" in holder else Vector3.ZERO
	)
	var distance_vector: Vector3 = target_pos - global_position
	var pos_stiffness: float = 14.0 if is_heavy else 20.0
	linear_velocity = holder_velocity + (distance_vector * pos_stiffness)

	var cam_yaw: float = (
		cam.global_transform.basis.get_euler().y
		if is_instance_valid(cam)
		else holder.global_transform.basis.get_euler().y
	)

	# Smoothly ease yaw alignment while returning pitch and roll upright
	var elapsed_ratio: float = clampf(float(Time.get_ticks_msec() - _grab_time) / 350.0, 0.0, 1.0)
	var current_held_yaw: float = lerpf(_held_relative_yaw, 0.0, elapsed_ratio)
	var target_yaw: float = cam_yaw + current_held_yaw
	var target_basis: Basis = Basis.from_euler(Vector3(0.0, target_yaw, 0.0))

	var q_target: Quaternion = target_basis.get_rotation_quaternion()
	var q_current: Quaternion = global_basis.get_rotation_quaternion()
	var q_diff: Quaternion = q_target * q_current.inverse()
	if q_diff.w < 0.0:
		q_diff = -q_diff

	var angle: float = 2.0 * acos(clampf(q_diff.w, -1.0, 1.0))
	var axis_len_sq: float = q_diff.x * q_diff.x + q_diff.y * q_diff.y + q_diff.z * q_diff.z

	# Damped angular spring allows smooth upright rotation without instant snapping
	var rot_stiffness: float = 8.0 if is_heavy else 18.0
	if axis_len_sq > 0.0001:
		var axis: Vector3 = Vector3(q_diff.x, q_diff.y, q_diff.z) / sqrt(axis_len_sq)
		angular_velocity = axis * (angle * rot_stiffness)
	else:
		angular_velocity = Vector3.ZERO


## Calculates water submersion depth and applies buoyant impulses.
func _process_buoyancy() -> void:
	submerged = false

	if is_in_water and is_instance_valid(current_water_node):
		var probe_count: int = _probes.size()
		if probe_count > 0:
			var probe_mass: float = mass / float(probe_count)

			for node: Node in _probes:
				var p: Node3D = node as Node3D
				if not is_instance_valid(p):
					continue

				var wave_height: float = float(
					current_water_node.call("get_wave_height_at_pos", p.global_position)
				)
				var depth: float = wave_height - p.global_position.y

				if depth > 0.0:
					submerged = true
					var depth_multiplier: float = clampf(depth * 4.0, 0.0, 4.0)
					var force: Vector3 = (
						Vector3.UP * probe_mass * float_force * gravity * depth_multiplier
					)
					var offset: Vector3 = p.global_position - global_position
					apply_force(force, offset)

	if not _was_submerged and submerged and not is_held:
		var impact_speed: float = linear_velocity.length()
		print("PickableObject: Water impact registered -> speed: ", impact_speed)
		if is_instance_valid(current_water_node):
			var ripple_power: float = maxf(impact_speed * 0.3, 1.2)
			if current_water_node.has_method("spawn_ripple"):
				current_water_node.call("spawn_ripple", global_position, ripple_power)
			if current_water_node.has_method("play_splash_sound"):
				current_water_node.call("play_splash_sound", global_position, impact_speed)

	_was_submerged = submerged

	if submerged and not is_held:
		apply_central_force(-linear_velocity * water_drag * mass)
		apply_torque(-angular_velocity * water_angular_drag * mass)

		var cur_time: int = Time.get_ticks_msec()
		if linear_velocity.length() > 0.8 and cur_time - _last_wake_time > 400:
			_last_wake_time = cur_time
			if current_water_node.has_method("spawn_ripple"):
				current_water_node.call("spawn_ripple", global_position, 0.4)


## Inflicts projectile damage if impact velocity exceeds threshold.
func _on_body_entered(body: Node) -> void:
	if is_held:
		return

	# Prevent self-inflicted damage when walking or tumbling near the player
	if body == holder or body.is_in_group(&"player") or body is CharacterBody3D:
		return

	var impact_speed: float = _last_velocity.length()
	if impact_speed >= damage_velocity_threshold:
		if body.has_method("take_damage"):
			print("PickableObject: Impact! Dealing ", projectile_damage, " damage.")
			body.call("take_damage", projectile_damage)


## Returns cached player [Camera3D] from the current active viewport.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera


## Resolves the primary visual mesh node from children if unassigned.
func _resolve_visual_mesh() -> Node3D:
	if is_instance_valid(mesh):
		return mesh
	var found_mesh: Node = NodeQuery.find_first_child_of_type(self, MeshInstance3D)
	if found_mesh is Node3D:
		mesh = found_mesh as Node3D
	return mesh
