class_name PickableObject
extends RigidBody3D

## Represents a physical object that the player can pick up, throw, and interact with in the game world.
## Manages buoyancy, physics interpolation, custom TTS accessibility prompts, and player holding logic.

@export_category("Pickable Nodes")
## The [InteractComponent] responsible for handling raycast focus and interaction signals.
@export var interact_comp: InteractComponent
## The primary visual [Node3D] (usually a MeshInstance3D) representing the object.
@export var mesh: Node3D
## The floating [Label3D] used to display interaction prompts.
@export var label: Label3D

## Visual component used to apply outlines or highlights when focused.
@onready var highlight_comp: HighlightComponent = $HighlightComponent
## The physical bounds of the object.
@onready var collision: CollisionShape3D = $CollisionShape3D
## The default world gravity derived from project settings.
@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export_category("Buoyancy")
## Node containing [Marker3D] children representing volumetric probe points for water physics.
@export var probe_container: Node3D
## How strongly the water pushes up against the object. (3.0 is a great value!)
@export var float_force: float = 3.0
## Friction applied when moving through water.
@export var water_drag: float = 0.5
## Angular friction applied to rotation when submerged.
@export var water_angular_drag: float = 0.5

# --- HOLDING CONFIG ---
## How much closer to the player this object should be positioned when held.
@export var hold_distance_offset: float = 0.0

## How transparent the object gets when held (0.0 = solid, 1.0 = completely invisible).
@export_range(0.0, 1.0) var held_transparency: float = 0.25

## The mass at which an object is forced to be held lower on the screen (e.g., heavy barrels).
@export var heavy_mass_threshold: float = 10.0
## How far down on the Y-axis heavy objects are held to avoid blocking the camera.
@export var heavy_y_drop: float = 0.5

# --- COMBAT / IMPACT CONFIG ---
## The minimum velocity required for the object to register as a damaging projectile.
@export var damage_velocity_threshold: float = 8.0

## The base damage applied to a struck target upon a high-speed collision.
@export var projectile_damage: int = 20

@export_category("Accessibility")
## The dedicated [ShaderMaterial] applied as an overlay to highlight this object through walls.
@export var vision_assist_material: ShaderMaterial

## Tracks the velocity from the previous physics frame to accurately gauge impact speed.
var _last_velocity: Vector3 = Vector3.ZERO

## Indicates if the object is currently grasped by a player or entity.
var is_held: bool = false
## The [Marker3D] target the object visually tracks towards when held.
var hold_target: Marker3D = null
## The [Node3D] entity currently holding the object.
var holder: Node3D = null

# --- GLOBAL STATE TRACKING ---
## Indicates if the [PickableObject] is currently locked and cannot be interacted with.
var is_locked: bool = false:
	set(value):
		is_locked = value
		print("PickableObject: is_locked state changed to ", is_locked)
		if is_locked:
			if is_instance_valid(mesh):
				mesh.material_overlay = null
			if is_instance_valid(label):
				label.hide()

## Indicates if the object is currently inside a water volume.
var is_in_water: bool = false:
	set(value):
		if is_in_water != value:
			is_in_water = value
			print("PickableObject: is_in_water state changed to ", is_in_water)
			_update_process_state()

## Indicates if the player is currently in noclip or flying mode.
var _is_player_flying: bool = false

# --- WATER TRACKING ---
## Indicates if the object is fully submerged beneath the water plane.
var submerged: bool = false
## Reference to the current water [Node3D] applying buoyancy forces.
var current_water_node: Node3D = null
## The system time in milliseconds when the object was last grabbed.
var _grab_time: int = 0

## Cached [Camera3D] reference to avoid expensive viewport lookups every frame.
var _cached_camera: Camera3D = null

## Cached array of child probe nodes used to calculate buoyancy without recursive lookups.
var _probes: Array[Node] = []

## Tracks if the object was recently dropped to prevent immediate TTS spam on refocus.
var _is_tts_cooldown: bool = false


## Initializes the [PickableObject], setting up references, event listeners, and physics state.
func _ready() -> void:
	print("PickableObject: _ready() called. Initializing ", name)
	# Fallback assignments in case export vars were left empty in the inspector
	if not is_instance_valid(interact_comp):
		interact_comp = $InteractComponent
	if not is_instance_valid(mesh):
		mesh = $Mesh
	if not is_instance_valid(label):
		label = $Label3D
	if not is_instance_valid(probe_container):
		probe_container = $ProbeContainer

	# Cache the probe children once at startup to avoid runtime lookup spikes
	if is_instance_valid(probe_container):
		_probes = probe_container.get_children()

	if is_instance_valid(label):
		label.hide()

	if is_instance_valid(interact_comp):
		if not interact_comp.focused.is_connected(_on_interact_component_focused):
			interact_comp.focused.connect(_on_interact_component_focused)
		if not interact_comp.unfocused.is_connected(_on_interact_component_unfocused):
			interact_comp.unfocused.connect(_on_interact_component_unfocused)

	# Allow Rigidbody to sleep when sitting still for 60 FPS optimization
	sleeping_state_changed.connect(_on_sleeping_state_changed)

	# Listen to the global Event Bus for state changes
	if (
		Events.has_signal("noclip_toggled")
		and not Events.noclip_toggled.is_connected(_on_noclip_toggled)
	):
		Events.noclip_toggled.connect(_on_noclip_toggled)

	# Enable collision monitoring so the physics server reports what this object hits
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)

	# Initialize process state
	_update_process_state()

	# --- SHADER WARM-UP (Fixes the first-pickup frame drop) ---
	if is_instance_valid(mesh):
		_set_model_transparency(mesh, held_transparency)
		_revert_warmup_deferred()


## Triggers when the player toggles noclip mode. Updates internal flight state.
func _on_noclip_toggled(is_flying: bool) -> void:
	print("PickableObject: Noclip state updated via Event Bus -> ", is_flying)
	_is_player_flying = is_flying


## Triggers when the physics sleeping state changes to optimize processing loops.
func _on_sleeping_state_changed() -> void:
	_update_process_state()


## Enables or disables physics processing based on whether the object needs active updates.
func _update_process_state() -> void:
	var should_process: bool = is_held or is_in_water or not sleeping
	set_physics_process(should_process)


## Defers the reversion of the object's transparency to prevent frame drops during compilation.
func _revert_warmup_deferred() -> void:
	print("PickableObject: _revert_warmup_deferred() executing shader compilation.")
	await get_tree().process_frame
	await get_tree().process_frame

	if is_instance_valid(mesh):
		_set_model_transparency(mesh, 0.0)


## Attaches the object to the player's hold target and disables standard gravity.
func pick_up(target: Marker3D, player_node: Node3D) -> void:
	if is_locked:
		return

	print("PickableObject: pick_up() called. Grabbed: ", name)
	_grab_time = Time.get_ticks_msec()
	is_held = true
	hold_target = target
	holder = player_node

	if is_instance_valid(label):
		label.hide()

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false
	gravity_scale = 0.0

	if is_instance_valid(mesh):
		_set_model_transparency(mesh, held_transparency)

	if is_instance_valid(interact_comp):
		interact_comp.is_currently_focused = false
		interact_comp.unfocused.emit()
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	add_collision_exception_with(holder)
	_update_process_state()
	Events.item_picked_up.emit(self, holder)


## Releases the object from the player's grasp, restoring physics and applying an impulse.
func drop() -> void:
	print("PickableObject: drop() called. Action: Dropping object.")
	if Time.get_ticks_msec() - _grab_time < 100:
		return

	print("PickableObject: drop() called. Releasing: ", name)
	is_held = false

	if is_instance_valid(interact_comp):
		interact_comp.process_mode = Node.PROCESS_MODE_INHERIT

	# Start a short cooldown to prevent the TTS from instantly repeating the grab prompt
	_is_tts_cooldown = true
	get_tree().create_timer(1.5, false).timeout.connect(_reset_tts_cooldown)

	if is_locked:
		holder = null
		if is_instance_valid(interact_comp):
			interact_comp.is_currently_focused = false
		_update_process_state()
		return

	freeze = false
	sleeping = false
	gravity_scale = 1.0

	if is_instance_valid(mesh):
		_set_model_transparency(mesh, 0.0)

	if is_instance_valid(holder):
		if "velocity" in holder:
			linear_velocity = holder.velocity

		var cam_forward: Vector3 = Vector3.FORWARD
		var cam: Camera3D = _get_camera()
		if is_instance_valid(cam):
			cam_forward = -cam.global_transform.basis.z

		var flat_cam_forward: Vector3 = Vector3(cam_forward.x, 0.0, cam_forward.z)
		var push_dir: Vector3 = flat_cam_forward.normalized()

		var player_vel: Vector3 = holder.get("velocity") if "velocity" in holder else Vector3.ZERO
		var velocity_offset: Vector3 = Vector3(player_vel.x, 0.0, player_vel.z) * 0.15

		var is_nudging: bool = false
		if cam_forward.y < -0.2:
			var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
			var intended_slide: Vector3 = (push_dir * 0.35) + velocity_offset

			var check_dir: Vector3 = intended_slide.normalized()
			var check_dist: float = intended_slide.length() + 0.1
			var ray_end: Vector3 = global_position + (check_dir * check_dist)

			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				global_position, ray_end
			)
			query.exclude = [self.get_rid(), holder.get_rid()]

			var result: Dictionary = space_state.intersect_ray(query)
			var target_pos: Vector3 = global_position

			if result:
				var safe_dist: float = (
					sqrt(global_position.distance_squared_to(result.position)) - 0.1
				)
				if safe_dist > 0:
					target_pos += check_dir * safe_dist
			else:
				target_pos += intended_slide

			if target_pos != global_position:
				is_nudging = true
				angular_velocity = Vector3.ZERO

				var nudge_tween: Tween = create_tween()
				(
					nudge_tween
					. tween_property(self, "global_position:x", target_pos.x, 0.15)
					. set_trans(Tween.TRANS_SINE)
					. set_ease(Tween.EASE_OUT)
				)
				(
					nudge_tween
					. parallel()
					. tween_property(self, "global_position:z", target_pos.z, 0.15)
					. set_trans(Tween.TRANS_SINE)
					. set_ease(Tween.EASE_OUT)
				)

				nudge_tween.tween_callback(
					func() -> void:
						var toss_dir: Vector3 = push_dir
						toss_dir.y = 0.5
						apply_central_impulse(toss_dir * 5.0)
				)

		if not is_nudging:
			push_dir.y = 0.5
			apply_central_impulse(push_dir * 5.0)

		Events.item_dropped.emit(self, holder)

		var previous_holder: Node3D = holder
		_wait_to_enable_collision(previous_holder)

	holder = null
	if is_instance_valid(interact_comp):
		interact_comp.is_currently_focused = false

	_update_process_state()


## Resets the cooldown timer, allowing the text-to-speech engine to speak the grab prompt again.
func _reset_tts_cooldown() -> void:
	print("PickableObject: _reset_tts_cooldown() called. TTS focus prompts re-enabled.")
	_is_tts_cooldown = false


## Periodically checks distance to the player to safely re-enable collision.
func _attempt_enable_collision(player_node: Node3D) -> void:
	print("PickableObject: _attempt_enable_collision() executing collision check.")
	if not is_instance_valid(self) or not is_instance_valid(player_node):
		return

	var dist_sq: float = global_position.distance_squared_to(player_node.global_position)

	if dist_sq > 2.25:  # 1.5 squared
		remove_collision_exception_with(player_node)
	else:
		get_tree().create_timer(0.1).timeout.connect(_attempt_enable_collision.bind(player_node))


## Drops the object and applies a significant central impulse to throw it.
func throw(impulse_vector: Vector3) -> void:
	print(
		"PickableObject: throw() called. Throwing: ", name, " with force: ", impulse_vector.length()
	)
	drop()
	if not is_locked:
		apply_central_impulse(impulse_vector)


## Called when the player focuses on this pickable object. Highlights the mesh and triggers TTS.
func _on_interact_component_focused() -> void:
	print("PickableObject: _on_interact_component_focused() called. Highlighting object.")
	if is_locked:
		return

	if is_held:
		if is_instance_valid(mesh) and mesh is GeometryInstance3D:
			mesh.material_overlay = null
		return

	if is_instance_valid(label):
		_update_label_text()
		label.show()

		# Broadcast the custom TTS text to the Event Bus (visual label remains untouched)
		if Events.has_signal("object_focused") and not _is_tts_cooldown:
			var mesh_name: String = _get_clean_mesh_name()
			var tts_prompt: String = label.text + " " + mesh_name

			print("PickableObject: Emitting TTS prompt -> ", tts_prompt)
			# Pass 'mesh' as the caller so it generates a distinct ID from the parent body,
			# avoiding duplicate ID rejections if InteractComponent also emits blindly.
			Events.object_focused.emit(tts_prompt, mesh)


## Formats the floating [Label3D] to display the correct interaction key prompt.
func _update_label_text() -> void:
	if not is_instance_valid(label):
		return

	print("PickableObject: _update_label_text() called. Formatting interact prompt.")
	var events: Array[InputEvent] = InputMap.action_get_events("interact")
	var key_name: String = "???"

	if events.size() > 0:
		var raw_text: String = events[0].as_text()
		key_name = (
			raw_text
			. replace(" (Physical)", "")
			. replace(" - Physical", "")
			. replace(" (Physics)", "")
			. replace(" - Physics", "")
			. replace("Left Mouse Button", "LMB")
			. replace("Right Mouse Button", "RMB")
			. replace("Middle Mouse Button", "MMB")
			. strip_edges()
		)

	# Format the label to be highly descriptive for the player
	label.text = "Press [%s] to grab" % [key_name]


## Called when the player looks away. Removes the highlight and hides the label.
func _on_interact_component_unfocused() -> void:
	print("PickableObject: _on_interact_component_unfocused() called. Removing highlight.")
	if is_instance_valid(label):
		label.hide()


## Processes object movement towards the hold target or applies buoyancy forces when in water.
func _physics_process(_delta: float) -> void:
	if is_held and is_instance_valid(hold_target) and is_instance_valid(holder):
		var target_pos: Vector3 = hold_target.global_position
		var player_pos: Vector3 = holder.global_position

		var cam_forward: Vector3 = Vector3.FORWARD
		var cam: Camera3D = _get_camera()
		if is_instance_valid(cam):
			cam_forward = -cam.global_transform.basis.z

		target_pos -= cam_forward * hold_distance_offset

		var weight_ratio: float = clampf((mass - 5.0) / 5.0, 0.0, 1.0)
		var current_y_drop: float = lerpf(0.0, 0.5, weight_ratio)
		target_pos.y -= current_y_drop

		if cam_forward.y < 0.0:
			var dip_strength: float = absf(cam_forward.y) * 6.0
			target_pos.y -= (dip_strength * weight_ratio)

		var max_allowed_height: float = lerpf(player_pos.y + 3.0, player_pos.y + 1.0, weight_ratio)
		if target_pos.y > max_allowed_height:
			target_pos.y = max_allowed_height

		var flat_offset: Vector2 = Vector2(target_pos.x - player_pos.x, target_pos.z - player_pos.z)
		if flat_offset.length() < 0.8:
			flat_offset = flat_offset.normalized() * 0.8
			target_pos.x = player_pos.x + flat_offset.x
			target_pos.z = player_pos.z + flat_offset.y

		var min_height: float = player_pos.y + 0.2
		if target_pos.y < min_height:
			target_pos.y = min_height

		var distance_to_target: float = global_position.distance_to(target_pos)

		if distance_to_target > 1.5 and not _is_player_flying:
			drop()
			return

		var distance_vector: Vector3 = target_pos - global_position
		linear_velocity = distance_vector * 15.0

		var target_basis: Basis = holder.global_basis
		var current_quat: Quaternion = global_basis.get_rotation_quaternion()
		var diff_quat: Quaternion = target_basis.get_rotation_quaternion() * current_quat.inverse()

		var axis: Vector3 = Vector3(diff_quat.x, diff_quat.y, diff_quat.z)
		var angle: float = 2.0 * acos(clampf(diff_quat.w, -1.0, 1.0))

		if angle > PI:
			angle -= TAU

		if axis.length_squared() > 0.0001:
			angular_velocity = axis.normalized() * (angle * 20.0)
		else:
			angular_velocity = Vector3.ZERO
		return

	submerged = false

	# REPLACED get_children() WITH CACHED _probes ARRAY
	if is_in_water and is_instance_valid(current_water_node):
		var probe_count: int = _probes.size()
		if probe_count > 0:
			var probe_mass: float = mass / float(probe_count)

			for node: Node in _probes:
				var p: Node3D = node as Node3D
				if not is_instance_valid(p):
					continue

				var wave_height: float = current_water_node.get_wave_height_at_pos(
					p.global_position
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

	if submerged and not is_held:
		apply_central_force(-linear_velocity * water_drag * mass)
		apply_torque(-angular_velocity * water_angular_drag * mass)

	# Store the velocity at the very end of the physics frame.
	# We must do this because Godot's body_entered signal fires AFTER collision resolution.
	_last_velocity = linear_velocity


## Triggered by the physics engine whenever this rigid body collides with another physics body.
func _on_body_entered(body: Node) -> void:
	# If the object is currently physically held by a tentacle or player, don't deal impact damage
	if is_held:
		return

	var impact_speed: float = _last_velocity.length()

	# Check if the collision was forceful enough to warrant damage
	if impact_speed >= damage_velocity_threshold:
		if body.has_method("take_damage"):
			print(
				"PickableObject: _on_body_entered() - High-speed impact! Dealing ",
				projectile_damage,
				" damage to ",
				body.name
			)
			body.take_damage(projectile_damage)


## Waits until the object is safely away from the player before restoring collision to avoid clipping.
func _wait_to_enable_collision(player_node: Node3D) -> void:
	print("PickableObject: _wait_to_enable_collision() waiting for clearance.")
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

		if flat_my_pos.distance_squared_to(flat_player_pos) >= 1.0:  # 1.0 squared
			break

		current_frame += 1
		await get_tree().physics_frame

	if is_instance_valid(self) and is_instance_valid(player_node):
		var flat_my_pos: Vector2 = Vector2(global_position.x, global_position.z)
		var flat_player_pos: Vector2 = Vector2(
			player_node.global_position.x, player_node.global_position.z
		)

		if flat_my_pos.distance_squared_to(flat_player_pos) < 1.0:  # 1.0 squared
			var player_forward: Vector3 = -player_node.global_transform.basis.z
			var flat_backward: Vector3 = (
				Vector3(-player_forward.x, 0.0, -player_forward.z).normalized()
			)

			var push_distance: float = 0.2
			var push_vector: Vector3 = flat_backward * push_distance

			var safe_travel: Vector3 = push_vector
			var kin_collision: KinematicCollision3D = player_node.move_and_collide(
				push_vector, true
			)
			if kin_collision:
				safe_travel = kin_collision.get_travel()

			var target_pos: Vector3 = player_node.global_position + safe_travel

			var tween: Tween = get_tree().create_tween()
			(
				tween
				. tween_property(player_node, "global_position", target_pos, 0.15)
				. set_trans(Tween.TRANS_SINE)
				. set_ease(Tween.EASE_OUT)
			)

			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO

			tween.tween_callback(
				func() -> void:
					if is_instance_valid(self) and is_instance_valid(player_node):
						remove_collision_exception_with(player_node)
			)
			return

		remove_collision_exception_with(player_node)


## Recursively applies transparency to the mesh hierarchy when the object is held.
func _set_model_transparency(parent_node: Node, alpha: float) -> void:
	if not is_instance_valid(parent_node):
		return

	if parent_node is MeshInstance3D:
		parent_node.transparency = alpha

	for child: Node in parent_node.get_children():
		_set_model_transparency(child, alpha)


## Retrieves and caches the active [Camera3D] for calculating hold offsets and nudges.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera


## Signal callback for toggling the accessibility highlight.
func _on_vision_assist_toggled(is_active: bool) -> void:
	print(
		"PickableObject: _on_vision_assist_toggled() triggered. Applying material overlay: ",
		is_active
	)

	if is_instance_valid(mesh):
		var target_material: ShaderMaterial = vision_assist_material if is_active else null
		_set_model_overlay(mesh, target_material)


## Recursive helper to apply the overlay material to the root mesh and all child meshes.
func _set_model_overlay(parent_node: Node, mat: ShaderMaterial) -> void:
	if not is_instance_valid(parent_node):
		return

	if parent_node is GeometryInstance3D:
		parent_node.material_overlay = mat

	for child: Node in parent_node.get_children():
		_set_model_overlay(child, mat)


## Parses the name of [member mesh] to generate a clean, natural voice
## string for [PiperTTS] synthesis (e.g., converting "Barrel_red" to "barrel red").
## Returns a human-readable [String] describing the focused object.
func _get_clean_mesh_name() -> String:
	print("PickableObject: _get_clean_mesh_name() called. Parsing mesh string.")

	# Check nulls and safeguard against assigning the root rigid body to the mesh export var.
	if not is_instance_valid(mesh) or mesh == self:
		return "object"

	var raw_name: String = mesh.name

	# Only search child meshes if the assigned node has a generic engine name
	var generic_names: Array[String] = ["mesh", "meshinstance3d", "node3d", "model"]
	if raw_name.to_lower() in generic_names:
		for child: Node in mesh.get_children():
			var child_lower: String = child.name.to_lower()
			if not child_lower in generic_names and not child_lower.begins_with("pickable"):
				raw_name = child.name
				break

	# Split camelCase / PascalCase into spaced words (e.g., "BarrelRed" -> "Barrel Red")
	var regex: RegEx = RegEx.new()
	regex.compile("([a-z0-9])([A-Z])")
	var formatted_name: String = regex.sub(raw_name, "$1 $2", true)

	# Replace underscores and hyphens with spaces
	formatted_name = formatted_name.replace("_", " ").replace("-", " ")

	# Remove unwanted prefix tags
	var unwanted_prefixes: Array[String] = ["pickable ", "item ", "prop ", "meshinstance ", "mesh "]
	var lower_name: String = formatted_name.to_lower().strip_edges()
	for prefix: String in unwanted_prefixes:
		if lower_name.begins_with(prefix):
			lower_name = lower_name.trim_prefix(prefix).strip_edges()

	# Remove trailing digits and special symbols
	var clean_chars: String = ""
	for i: int in range(lower_name.length()):
		var char_str: String = lower_name.substr(i, 1)
		if not char_str.is_valid_int() and char_str != "@":
			clean_chars += char_str

	var final_name: String = clean_chars.strip_edges()

	if final_name.is_empty() or final_name in generic_names:
		return "object"

	return final_name
