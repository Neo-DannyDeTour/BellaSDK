## Physical object for player pickup, throws, buoyancy, and TTS prompts.
class_name PickableObject
extends RigidBody3D

@export_category("Pickable Nodes")
## The [InteractComponent] handling focus and interaction signals.
@export var interact_comp: InteractComponent

## The primary visual [Node3D] representing the object.
@export var mesh: Node3D

## The floating [Label3D] displaying interaction prompts.
@export var label: Label3D

## The [Sprite3D] rendering prompt icon textures beside the label.
@export var prompt_icon: Sprite3D

## Visual [HighlightComponent] applying outlines when focused.
@onready var highlight_comp: HighlightComponent = (
	get_node_or_null("HighlightComponent") as HighlightComponent
)

## The physical [CollisionShape3D] bounding the object.
@onready var collision: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D

## The default world gravity scalar from project settings.
@onready var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

@export_category("Buoyancy")
## Node containing [Marker3D] children for buoyancy probes.
@export var probe_container: Node3D

## Upward buoyant force multiplier applied by water volumes.
@export var float_force: float = 3.0

## Linear drag coefficient applied when moving through water.
@export var water_drag: float = 0.5

## Angular drag coefficient applied to rotation in water.
@export var water_angular_drag: float = 0.5

## Minimum distance maintained between camera and object.
const MIN_HOLD_DISTANCE: float = 1.2

## Distance offset pulling held object closer to player.
@export var hold_distance_offset: float = 0.0

## Transparency applied to the object while held.
@export_range(0.0, 1.0) var held_transparency: float = 0.25

## Mass threshold triggering heavy carry offsets.
@export var heavy_mass_threshold: float = 10.0

## Downward Y-axis offset applied to held heavy objects.
@export var heavy_y_drop: float = 0.5

## Height above floor where heavy objects hover.
@export var heavy_floor_clearance: float = 0.35

## Transparency applied specifically to heavy held objects.
@export_range(0.0, 1.0) var heavy_held_transparency: float = 0.55

## Minimum impact speed required to register damage.
@export var damage_velocity_threshold: float = 8.0

## Base damage points dealt upon high-speed impact.
@export var projectile_damage: int = 20

@export_category("Accessibility")
## Dedicated [ShaderMaterial] highlighting the object.
@export var vision_assist_material: ShaderMaterial

## Relative yaw offset between camera and object.
var _held_relative_yaw: float = 0.0

## Linear velocity vector recorded on preceding frame.
var _last_velocity: Vector3 = Vector3.ZERO

## Tracks whether object is currently grasped.
var is_held: bool = false

## Spatial [Marker3D] target tracking held object.
var hold_target: Marker3D = null

## Entity [Node3D] currently holding this object.
var holder: Node3D = null

## Base directory path where prompt icons are stored.
const ICON_BASE_PATH: String = "res://assets/kenney_input-prompts_1.5/Keyboard & Mouse/Default/"

## Cached resolved icon file paths dictionary.
var _icon_path_cache: Dictionary = {}

## Determines whether text prompt labels are displayed.
var _show_text_prompts: bool = true

## Tracks whether interaction is temporarily locked.
var is_locked: bool = false:
	set(value):
		is_locked = value
		print("PickableObject: is_locked state changed to ", is_locked)
		if is_locked:
			if is_instance_valid(mesh) and mesh is GeometryInstance3D:
				(mesh as GeometryInstance3D).material_overlay = null
			if is_instance_valid(label):
				label.hide()

## Indicates whether object is inside an active water volume.
var is_in_water: bool = false:
	set(value):
		if is_in_water != value:
			is_in_water = value
			print("PickableObject: is_in_water state changed to ", is_in_water)
			_update_process_state()

## Indicates whether player is in noclip flight mode.
var _is_player_flying: bool = false

## Indicates whether object is submerged in water.
var submerged: bool = false

## Current water [Node3D] instance applying buoyancy.
var current_water_node: Node3D = null

## System time in milliseconds when object was grabbed.
var _grab_time: int = 0

## Cached [Camera3D] reference to avoid viewport lookups.
var _cached_camera: Camera3D = null

## Cached array of child probe nodes for buoyancy.
var _probes: Array[Node] = []

## Tracks whether TTS grab prompts are on cooldown.
var _is_tts_cooldown: bool = false

## Timestamp in milliseconds tracking last wake ripple.
var _last_wake_time: int = 0

## Preceding frame submersion state for impact detection.
var _was_submerged: bool = false


## Initializes references, collision detection, and contacts.
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

	_update_process_state()

	if is_instance_valid(mesh):
		_set_model_transparency(mesh, held_transparency)
		_revert_warmup_deferred()


## Updates prompt visibility setting when changed.
func _on_item_prompts_toggled(enabled: bool) -> void:
	print("PickableObject: Item prompt visibility updated -> ", enabled)
	_show_text_prompts = enabled
	if not _show_text_prompts and is_instance_valid(label):
		label.hide()


## Triggers when player toggles noclip mode.
func _on_noclip_toggled(is_flying: bool) -> void:
	print("PickableObject: Noclip state updated via Event Bus -> ", is_flying)
	_is_player_flying = is_flying


## Triggers when physics sleeping state changes.
func _on_sleeping_state_changed() -> void:
	_update_process_state()


## Enables or disables physics processing based on state.
func _update_process_state() -> void:
	var should_process: bool = is_held or is_in_water or not sleeping
	set_physics_process(should_process)


## Defers transparency restoration for shader compilation.
func _revert_warmup_deferred() -> void:
	print("PickableObject: _revert_warmup_deferred() executing.")
	await get_tree().process_frame
	await get_tree().process_frame

	if is_instance_valid(mesh):
		_set_model_transparency(mesh, 0.0)


## Attaches object to player hold target with transparency.
func pick_up(target: Marker3D, player_node: Node3D) -> void:
	if is_locked:
		return

	print("PickableObject: pick_up() called. Grabbed: ", name)
	_grab_time = Time.get_ticks_msec()
	is_held = true
	hold_target = target
	holder = player_node

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

	var active_mesh: Node3D = _resolve_visual_mesh()
	if is_instance_valid(active_mesh):
		var alpha: float = (
			heavy_held_transparency if mass >= heavy_mass_threshold else held_transparency
		)
		_set_model_transparency(active_mesh, alpha)

	if is_instance_valid(interact_comp):
		interact_comp.set("is_currently_focused", false)
		if interact_comp.has_signal("unfocused"):
			interact_comp.unfocused.emit()
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	add_collision_exception_with(holder)
	_update_process_state()
	Events.item_picked_up.emit(self, holder)


## Releases object from player grasp and restores opacity.
func drop() -> void:
	print("PickableObject: drop() called. Action: Dropping object.")
	if Time.get_ticks_msec() - _grab_time < 100:
		return

	print("PickableObject: drop() releasing: ", name)
	is_held = false

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()

	_is_tts_cooldown = true
	get_tree().create_timer(1.5).timeout.connect(_reset_tts_cooldown)

	var active_mesh: Node3D = _resolve_visual_mesh()
	if is_instance_valid(active_mesh):
		_set_model_transparency(active_mesh, 0.0)

	if is_locked:
		holder = null
		if is_instance_valid(interact_comp):
			interact_comp.set("is_currently_focused", false)
		_update_process_state()
		return

	freeze = false
	sleeping = false
	gravity_scale = 1.0

	if is_instance_valid(holder):
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
		_wait_to_enable_collision(previous_holder)

	holder = null
	_wait_for_rest_to_enable_interact()
	_update_process_state()


## Drops object and applies central impulse to throw it.
func throw(impulse_vector: Vector3) -> void:
	print("PickableObject: throw() called with force: ", impulse_vector.length())
	drop()
	if not is_locked:
		apply_central_impulse(impulse_vector)


## Defers enabling interact component until object settles.
func _wait_for_rest_to_enable_interact() -> void:
	if is_instance_valid(interact_comp):
		interact_comp.set("is_currently_focused", false)
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	while is_instance_valid(self) and not is_held:
		await get_tree().physics_frame
		if linear_velocity.length() < 0.35 and (sleeping or is_on_floor_approx()):
			break

	if is_instance_valid(self) and not is_held and is_instance_valid(interact_comp):
		interact_comp.process_mode = Node.PROCESS_MODE_INHERIT


## Checks if object has settled on physical surface.
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


## Resets cooldown timer for TTS prompts.
func _reset_tts_cooldown() -> void:
	print("PickableObject: _reset_tts_cooldown() called.")
	_is_tts_cooldown = false


## Handles focus events, highlighting mesh and TTS cues.
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
		var events: Array[InputEvent] = InputMap.action_get_events("interact")
		var key_name: String = ""
		if not events.is_empty():
			key_name = events[0].as_text()

		var mesh_name: String = _get_clean_mesh_name()
		var tts_prompt: String = (
			"Press %s to grab %s" % [key_name, mesh_name]
			if not key_name.is_empty()
			else "Grab %s" % mesh_name
		)
		Events.object_focused.emit(tts_prompt, mesh)


## Formats floating prompt label and icon textures.
func _update_label_text() -> void:
	print("PickableObject: _update_label_text() updating prompts.")
	var events: Array[InputEvent] = InputMap.action_get_events("interact")
	var key_name: String = "E"
	if not events.is_empty():
		key_name = events[0].as_text()

	if is_instance_valid(label):
		label.text = "Press [%s] to grab" % key_name
		label.position.x = 0.0


## Hides labels and icons when player stops focusing.
func _on_interact_component_unfocused() -> void:
	print("PickableObject: Unfocused by interaction scanner.")
	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()


## Processes hold motion, buoyancy, and physics raycasts.
func _physics_process(_delta: float) -> void:
	if is_held and is_instance_valid(hold_target) and is_instance_valid(holder):
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
			target_pos = (
				holder.global_position
				+ (flat_forward * carry_dist)
				+ Vector3(0.0, heavy_floor_clearance, 0.0)
			)

			var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
			var floor_hit: Dictionary = NodeQuery.cast_ray(
				space_state,
				target_pos + Vector3(0.0, 0.5, 0.0),
				target_pos + Vector3(0.0, -1.0, 0.0),
				CollisionLayers.MASK_ENVIRONMENT,
				[get_rid(), holder.get_rid()]
			)
			if not floor_hit.is_empty():
				var ground_y: float = (floor_hit.position as Vector3).y
				target_pos.y = ground_y + heavy_floor_clearance
		else:
			var to_target: Vector3 = target_pos - cam_origin
			var forward_projection: float = to_target.dot(cam_forward)
			var required_dist: float = maxf(MIN_HOLD_DISTANCE - hold_distance_offset, 0.8)

			if forward_projection < required_dist:
				target_pos += cam_forward * (required_dist - forward_projection)

		var dist_sq: float = global_position.distance_squared_to(target_pos)
		var has_grab_settled: bool = (Time.get_ticks_msec() - _grab_time) > 300
		if dist_sq > 9.0 and has_grab_settled and not _is_player_flying:
			drop()
			return

		var holder_velocity: Vector3 = (
			holder.get("velocity") as Vector3 if "velocity" in holder else Vector3.ZERO
		)
		var distance_vector: Vector3 = target_pos - global_position

		var pos_stiffness: float = 8.0 if is_heavy else 20.0
		linear_velocity = holder_velocity + (distance_vector * pos_stiffness)

		var cam_yaw: float = (
			cam.global_transform.basis.get_euler().y
			if is_instance_valid(cam)
			else holder.global_transform.basis.get_euler().y
		)
		var target_yaw: float = cam_yaw + _held_relative_yaw
		var target_basis: Basis = Basis.from_euler(Vector3(0.0, target_yaw, 0.0))

		var current_quat: Quaternion = global_basis.get_rotation_quaternion()
		var diff_quat: Quaternion = target_basis.get_rotation_quaternion() * current_quat.inverse()

		var axis: Vector3 = Vector3(diff_quat.x, diff_quat.y, diff_quat.z)
		var angle: float = 2.0 * acos(clampf(diff_quat.w, -1.0, 1.0))

		if angle > PI:
			angle -= TAU

		var rot_stiffness: float = 8.0 if is_heavy else 25.0
		if axis.length_squared() > 0.0001:
			angular_velocity = axis.normalized() * (angle * rot_stiffness)
		else:
			angular_velocity = Vector3.ZERO

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

	_last_velocity = linear_velocity


## Deals impact damage if collision velocity is high.
func _on_body_entered(body: Node) -> void:
	if is_held:
		return

	var impact_speed: float = _last_velocity.length()

	if impact_speed >= damage_velocity_threshold:
		if body.has_method("take_damage"):
			print("PickableObject: Impact! Dealing ", projectile_damage, " damage.")
			body.call("take_damage", projectile_damage)


## Safely clears collision exception after clearing radius.
func _wait_to_enable_collision(player_node: Node3D) -> void:
	print("PickableObject: Waiting to restore player collision.")
	var max_wait_frames: int = 30
	var current_frame: int = 0

	while (
		is_instance_valid(self)
		and is_instance_valid(player_node)
		and current_frame < max_wait_frames
	):
		var flat_my_pos: Vector2 = Vector2(global_position.x, global_position.z)
		var flat_player_pos: Vector2 = Vector2(
			player_node.global_position.x, player_node.global_position.z
		)

		if flat_my_pos.distance_squared_to(flat_player_pos) >= 1.0:
			break

		current_frame += 1
		await get_tree().physics_frame

	if is_instance_valid(self) and is_instance_valid(player_node):
		remove_collision_exception_with(player_node)


## Recursively applies transparency across child meshes.
func _set_model_transparency(parent_node: Node, alpha: float) -> void:
	if not is_instance_valid(parent_node):
		return

	if parent_node is GeometryInstance3D:
		var geom: GeometryInstance3D = parent_node as GeometryInstance3D
		geom.transparency = alpha

	for child: Node in parent_node.get_children():
		_set_model_transparency(child, alpha)


## Retrieves and caches active [Camera3D] for hold math.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera


## Parses mesh node name to generate natural TTS string.
func _get_clean_mesh_name() -> String:
	if not is_instance_valid(mesh) or mesh == self:
		return "object"
	return mesh.name.to_lower().replace("_", " ").strip_edges()


## Resolves visual mesh references from children if needed.
func _resolve_visual_mesh() -> Node3D:
	if is_instance_valid(mesh):
		return mesh
	var found_mesh: Node = NodeQuery.find_first_child_of_type(self, MeshInstance3D)
	if found_mesh is Node3D:
		mesh = found_mesh as Node3D
	return mesh
