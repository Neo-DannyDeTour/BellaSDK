extends Marker3D
class_name NoteReader

@export_category("Sway & Movement")
## Multiplier for how much the note sways when moving the mouse freely.
@export var sway_multiplier: float = 0.002
## Maximum angle the note can sway freely on the screen.
@export var max_sway_angle: float = 0.1
## How quickly the sway returns to center or smooths out its movement.
@export var sway_return_speed: float = 5.0

@export_category("Manual Inspection")
## How fast WASD keys rotate the note.
@export var key_rotation_speed: float = 3.0
## How fast dragging the mouse rotates the note.
@export var mouse_rotation_speed: float = 0.005
## How much the note tilts based on mouse position on screen.
@export var hover_tilt_strength: float = 0.15
## How far from the camera the note is held.
@export var reading_distance: float = 0.6

@export_category("3D Glass Limits")
## Maximum allowed radius for the 3D magnifying glass.
@export var max_radius: float = 0.4
## Minimum allowed radius for the 3D magnifying glass.
@export var min_radius: float = 0.15
## Maximum allowed zoom level for the 3D magnifying glass.
@export var max_zoom: float = 5.0
## Minimum allowed zoom level for the 3D magnifying glass.
@export var min_zoom: float = 1.5

## Target rotation angle calculated from relative mouse input.
var _target_sway: Vector3 = Vector3.ZERO
## Target rotation radians applied to the proxy mesh via dragging or keys.
var _target_rot: Vector2 = Vector2.ZERO

## Tracks whether a note is currently being read.
var _is_reading: bool = false
## Tracks whether the player is holding click to inspect/rotate the note.
var _is_inspecting: bool = false
## Tracks whether the rotation axes are inverted.
var _is_inverted: bool = false

## Is the 3D magnifying glass currently active?
var _is_glass_active: bool = false
## Current zoom multiplier for the 3D shader.
var _current_zoom: float = 2.0
## Current glass radius for the 3D shader.
var _current_radius: float = 0.2

## Reference to the original note node in the world.
var _current_note: Node3D = null
## Temporary 3D mesh instance holding the comic texture in view.
var _proxy_mesh_instance: MeshInstance3D = null
## Reference to the interacting player character.
var _current_player: CharacterBody3D = null
## Background 3D mesh used to dim the surrounding scene.
var _bg_dimmer: MeshInstance3D = null
## UI CanvasLayer created dynamically if no scene label group is found.
var _instruction_ui: CanvasLayer = null

## Temporary 3D mesh instance holding the zoomed comic texture.
var _zoomed_mesh_instance: MeshInstance3D = null

## Preloaded shader used for applying the zoom mask effect on the 3D quad.
const ZOOM_SHADER: Shader = preload("res://vfx/zoom_mask.gdshader")


func _input(event: InputEvent) -> void:
	if not _is_reading or _current_note == null:
		return

	# Toggle High-Res 3D Glass & consume input so 2D CanvasLayer doesn't fire
	if event is InputEventKey and event.physical_keycode == KEY_Z:
		if event.pressed and not event.echo:
			_is_glass_active = not _is_glass_active
			if is_instance_valid(_zoomed_mesh_instance):
				_zoomed_mesh_instance.visible = _is_glass_active
			print("NoteReader: 3D Magnifying glass toggled to ", _is_glass_active)
			get_viewport().set_input_as_handled()
			return

	# Handle mouse wheel scaling for the 3D Glass (now affects both zoom and radius)
	if _is_glass_active and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_3d_glass(1.0)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_3d_glass(-1.0)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close_note()
		return

	# Double-tap handling for Reset (Left) and Invert (Right)
	if event is InputEventMouseButton and event.double_click:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_target_rot = Vector2.ZERO

			# Wrap the physical proxy rotation to a -PI to PI range instantly
			if is_instance_valid(_proxy_mesh_instance):
				_proxy_mesh_instance.rotation.x = wrapf(_proxy_mesh_instance.rotation.x, -PI, PI)
				_proxy_mesh_instance.rotation.y = wrapf(_proxy_mesh_instance.rotation.y, -PI, PI)

			print("NoteReader: Double L-Click detected. Resetting comic rotation.")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_is_inverted = not _is_inverted
			_update_instruction_text()
			print("NoteReader: Double R-Click detected. Axis inverted: ", _is_inverted)

	if event.is_action_pressed("shoot"):
		_is_inspecting = true
		print("NoteReader: Started mouse inspection (holding left click).")
	elif event.is_action_released("shoot"):
		_is_inspecting = false
		print("NoteReader: Stopped mouse inspection.")

	# Mouse Motion Handling
	if event is InputEventMouseMotion:
		if _is_inspecting:
			# Rotate the comic via dragging, applying inversion if active
			var invert_mult: float = -1.0 if _is_inverted else 1.0
			_target_rot.y -= event.relative.x * mouse_rotation_speed * invert_mult
			_target_rot.x += event.relative.y * mouse_rotation_speed * invert_mult
		else:
			# Subtle weapon-like sway on the base rig when looking around
			_target_sway.y -= event.relative.x * sway_multiplier
			_target_sway.x -= event.relative.y * sway_multiplier

			_target_sway.y = clampf(_target_sway.y, -max_sway_angle, max_sway_angle)
			_target_sway.x = clampf(_target_sway.x, -max_sway_angle, max_sway_angle)


func _process(delta: float) -> void:
	if not _is_reading or not is_instance_valid(_proxy_mesh_instance):
		return

	# 1. Handle WASD Input for Rotation with Inversion logic
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	if input_dir.length_squared() > 0.01:
		var invert_mult: float = -1.0 if _is_inverted else 1.0
		_target_rot.y -= input_dir.x * key_rotation_speed * delta * invert_mult
		_target_rot.x += input_dir.y * key_rotation_speed * delta * invert_mult

	# Constrain target rotation between -PI and PI to prevent float overflow over time
	_target_rot.x = wrapf(_target_rot.x, -PI, PI)
	_target_rot.y = wrapf(_target_rot.y, -PI, PI)

	# 2. Calculate Balatro-style hover tilt
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = screen_size * 0.5
	var mouse_offset: Vector2 = (mouse_pos - center) / center

	var hover_tilt_x: float = mouse_offset.y * hover_tilt_strength
	var hover_tilt_y: float = -mouse_offset.x * hover_tilt_strength

	# 3. Apply combined transforms
	position = Vector3(0.0, 0.0, -reading_distance)

	# Base Rig Rotation = Mouse Sway
	rotation.x = lerp(rotation.x, _target_sway.x, sway_return_speed * delta)
	rotation.y = lerp(rotation.y, _target_sway.y, sway_return_speed * delta)

	# Proxy Note Rotation = Key/Mouse Drag + Hover Tilt
	var final_x: float = _target_rot.x + hover_tilt_x
	var final_y: float = _target_rot.y + hover_tilt_y

	# Used lerp_angle instead of lerp so it always takes the shortest path
	_proxy_mesh_instance.rotation.x = lerp_angle(
		_proxy_mesh_instance.rotation.x,
		final_x,
		sway_return_speed * delta
	)
	_proxy_mesh_instance.rotation.y = lerp_angle(
		_proxy_mesh_instance.rotation.y,
		final_y,
		sway_return_speed * delta
	)

	# Decay relative mouse sway back to center
	_target_sway = _target_sway.lerp(Vector3.ZERO, sway_return_speed * delta * 0.5)

	# Process the Zoomed Mesh Raycast if active
	if _is_glass_active and is_instance_valid(_zoomed_mesh_instance):
		_zoomed_mesh_instance.rotation = _proxy_mesh_instance.rotation

		var viewport: Viewport = get_viewport()
		var v_size: Vector2 = viewport.get_visible_rect().size
		var current_mouse_pos: Vector2 = viewport.get_mouse_position()
		var current_mouse_uv: Vector2 = current_mouse_pos / v_size
		var aspect: float = v_size.x / v_size.y

		var mat: ShaderMaterial = _zoomed_mesh_instance.material_override as ShaderMaterial
		if is_instance_valid(mat):
			mat.set_shader_parameter("mouse_uv", current_mouse_uv)
			mat.set_shader_parameter("aspect_ratio", aspect)
			mat.set_shader_parameter("zoom", _current_zoom)
			mat.set_shader_parameter("glass_radius_uv", _current_radius)

			# Fire a raycast to find exactly what UV point the mouse is hovering over
			var cam: Camera3D = viewport.get_camera_3d()
			if is_instance_valid(cam):
				var ray_origin: Vector3 = cam.project_ray_origin(current_mouse_pos)
				var ray_dir: Vector3 = cam.project_ray_normal(current_mouse_pos)

				# Create a mathematical plane using the quad's global position and normal
				var normal: Vector3 = _proxy_mesh_instance.global_transform.basis.z
				var plane: Plane = Plane(normal, _proxy_mesh_instance.global_position)
				var intersection: Variant = plane.intersects_ray(ray_origin, ray_dir)

				if intersection != null:
					# Convert intersection from global space back to the quad's local space
					var local_pt: Vector3 = _proxy_mesh_instance.global_transform.affine_inverse() * (intersection as Vector3)
					var quad: QuadMesh = _proxy_mesh_instance.mesh as QuadMesh
					if is_instance_valid(quad):
						# Map local coordinates to 0.0 - 1.0 UV space
						var u: float = (local_pt.x / quad.size.x) + 0.5
						var v: float = 0.5 - (local_pt.y / quad.size.y)
						mat.set_shader_parameter("focus_uv", Vector2(u, v))


func open_note(note_node: Node3D, note_text: String, player: CharacterBody3D) -> void:
	print("NoteReader: Opening note UI and spawning proxy reading mesh.")
	_is_reading = true
	_is_inverted = false
	_is_glass_active = false # Reset zoom state on new note
	_current_zoom = 2.0
	_current_radius = 0.2
	_current_note = note_node
	_current_player = player

	_target_rot = Vector2.ZERO
	_target_sway = Vector3.ZERO

	if _current_player.has_method("start_operating_machine"):
		_current_player.start_operating_machine()

	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam and get_parent() != cam:
		get_parent().remove_child(self)
		cam.add_child(self)

	position = Vector3(0.0, 0.0, -reading_distance)
	rotation = Vector3.ZERO

	_current_note.visible = false

	_create_proxy_mesh(cam)
	_create_3d_dimmer()
	_create_instruction_ui()

	if Events.has_signal("note_opened"):
		Events.note_opened.emit(note_text)


func close_note() -> void:
	print("NoteReader: Closing note and restoring world state.")
	_is_reading = false
	_is_inspecting = false

	var ui_label: Label = get_tree().get_first_node_in_group("note_instruction_label") as Label
	if is_instance_valid(ui_label):
		ui_label.hide()

	if is_instance_valid(_current_player) and _current_player.has_method("stop_operating_machine"):
		_current_player.stop_operating_machine()

	_current_player = null

	if is_instance_valid(_bg_dimmer):
		_bg_dimmer.queue_free()
		_bg_dimmer = null

	if is_instance_valid(_instruction_ui):
		_instruction_ui.queue_free()
		_instruction_ui = null

	if is_instance_valid(_proxy_mesh_instance):
		_proxy_mesh_instance.queue_free()
		_proxy_mesh_instance = null

	if is_instance_valid(_zoomed_mesh_instance):
		_zoomed_mesh_instance.queue_free()
		_zoomed_mesh_instance = null

	if is_instance_valid(_current_note):
		_current_note.visible = true
		var col: CollisionShape3D = _current_note.get_node_or_null("CollisionShape3D")
		if is_instance_valid(col):
			col.disabled = false
		_current_note = null

	if Events.has_signal("note_closed"):
		Events.note_closed.emit()


func _adjust_3d_glass(direction: float) -> void:
	_current_zoom = clampf(_current_zoom + (0.5 * direction), min_zoom, max_zoom)
	_current_radius = clampf(_current_radius + (0.05 * direction), min_radius, max_radius)
	print("NoteReader: Scaled 3D glass | Zoom: ", _current_zoom, " | Radius: ", _current_radius)


func _create_proxy_mesh(cam: Camera3D) -> void:
	print("NoteReader: Creating dynamic proxy mesh.")
	_proxy_mesh_instance = MeshInstance3D.new()
	add_child(_proxy_mesh_instance)
	_proxy_mesh_instance.position = Vector3.ZERO
	_proxy_mesh_instance.rotation_degrees = Vector3.ZERO

	var tex: Texture2D = null
	if _current_note.get("note_texture") != null:
		tex = _current_note.get("note_texture") as Texture2D

	var quad: QuadMesh = QuadMesh.new()

	if tex:
		var fov: float = cam.fov
		var frustum_height: float = 2.0 * reading_distance * tan(deg_to_rad(fov * 0.5))
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var frustum_width: float = frustum_height * (viewport_size.x / viewport_size.y)

		var max_h: float = frustum_height * 0.63
		var max_w: float = frustum_width * 0.63

		var aspect: float = tex.get_width() / float(tex.get_height())
		var quad_w: float = max_h * aspect
		var quad_h: float = max_h

		if quad_w > max_w:
			quad_w = max_w
			quad_h = quad_w / aspect

		quad.size = Vector2(quad_w, quad_h)

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_texture = tex

		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 2
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		# Enforce linear filtering without mipmaps to keep the UI-held comic perfectly sharp
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

		_proxy_mesh_instance.material_override = mat

		_zoomed_mesh_instance = MeshInstance3D.new()
		add_child(_zoomed_mesh_instance)

		# Duplicate the quad so it matches exactly
		_zoomed_mesh_instance.mesh = quad.duplicate()
		_zoomed_mesh_instance.position = Vector3.ZERO

		# Scale up heavily so the 3D mesh covers the screen and the shader doesn't clip
		_zoomed_mesh_instance.scale = Vector3(5.0, 5.0, 5.0)
		_zoomed_mesh_instance.visible = false

		var zoom_mat: ShaderMaterial = ShaderMaterial.new()
		zoom_mat.shader = ZOOM_SHADER
		zoom_mat.set_shader_parameter("albedo_tex", tex)

		# Tell the shader we scaled the mesh 5x so it can align the texture UVs
		zoom_mat.set_shader_parameter("mesh_scale", 5.0)

		zoom_mat.render_priority = 3
		_zoomed_mesh_instance.material_override = zoom_mat

	else:
		quad.size = Vector2(0.3, 0.3)

	_proxy_mesh_instance.mesh = quad
	print("NoteReader: Proxy mesh created with dimensions: ", quad.size)


func _create_3d_dimmer() -> void:
	print("NoteReader: Creating background dimmer plane.")
	if is_instance_valid(_bg_dimmer):
		return

	_bg_dimmer = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(10.0, 10.0)
	_bg_dimmer.mesh = quad

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 1

	_bg_dimmer.material_override = mat
	add_child(_bg_dimmer)
	_bg_dimmer.position = Vector3(0.0, 0.0, -0.2)


func _create_instruction_ui() -> void:
	print("NoteReader: Initializing instruction UI text.")
	var ui_label: Label = get_tree().get_first_node_in_group("note_instruction_label") as Label

	if not is_instance_valid(ui_label):
		print("NoteReader: 'note_instruction_label' missing. Spawning dynamic CanvasLayer fallback.")
		_instruction_ui = CanvasLayer.new()
		_instruction_ui.layer = 100
		add_child(_instruction_ui)

		ui_label = Label.new()
		ui_label.name = "InstructionLabel"
		ui_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

		# Anchor to bottom and force it to grow upwards so text doesn't fall off-screen
		ui_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
		ui_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		ui_label.offset_bottom = -40 # Pushed slightly up from the absolute bottom edge

		ui_label.add_theme_color_override("font_outline_color", Color.BLACK)
		ui_label.add_theme_constant_override("outline_size", 10)
		ui_label.add_theme_font_size_override("font_size", 20)
		_instruction_ui.add_child(ui_label)

	ui_label.show()
	_update_instruction_text()


func _update_instruction_text() -> void:
	var ui_label: Label = get_tree().get_first_node_in_group("note_instruction_label") as Label
	if not is_instance_valid(ui_label) and is_instance_valid(_instruction_ui):
		ui_label = _instruction_ui.get_node_or_null("InstructionLabel") as Label

	if not is_instance_valid(ui_label):
		return

	var forward_key: String = _get_key_string_for_action("forward", "W")
	var left_key: String = _get_key_string_for_action("left", "A")
	var backward_key: String = _get_key_string_for_action("backward", "S")
	var right_key: String = _get_key_string_for_action("right", "D")
	var interact_key: String = _get_key_string_for_action("interact", "E")

	var shoot_events: Array[InputEvent] = InputMap.action_get_events("shoot")
	var shoot_str: String = "Left Click"
	if not shoot_events.is_empty() and shoot_events[0] is InputEventKey:
		shoot_str = OS.get_keycode_string((shoot_events[0] as InputEventKey).physical_keycode)

	var mode_str: String = "INVERTED" if _is_inverted else "DEFAULT"

	# Updated to include Z for the glass and Mouse Wheel for scaling
	var text_format: String = (
		"--- [ %s MODE ] ---\n" +
		"Use %s%s%s%s or Hold [%s] + Mouse to Rotate.\n" +
		"Double L-Click to Reset | Double R-Click to Invert Axis.\n" +
        "Press [Z] for Magnifying Glass (Scroll to Scale) | Press [%s] to Close."
	)

	ui_label.text = text_format % [
		mode_str, forward_key, left_key, backward_key, right_key, shoot_str, interact_key
	]
	print("NoteReader: Instruction UI updated and displayed.")


func _get_key_string_for_action(action_name: String, fallback: String) -> String:
	if InputMap.has_action(action_name):
		var events: Array[InputEvent] = InputMap.action_get_events(action_name)
		for event: InputEvent in events:
			if event is InputEventKey:
				return "[" + OS.get_keycode_string(event.physical_keycode) + "]"
	return "[" + fallback + "]"
