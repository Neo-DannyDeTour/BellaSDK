## Interactive inspection rig rendering documents and handling 3D magnifying glass.
class_name NoteReader
extends Marker3D

## Preloaded shader used for the magnifying glass zoom mask quad.
const ZOOM_SHADER: Shader = preload("res://vfx/zoom_mask.gdshader")

## Multiplier for angular note sway when moving the mouse freely.
@export var sway_multiplier: float = 0.002

## Maximum deflection angle in radians the note can sway freely.
@export var max_sway_angle: float = 0.1

## Damping rate at which note sway returns to center.
@export var sway_return_speed: float = 5.0

## Rotation rate in radians per second when inspecting via keys.
@export var key_rotation_speed: float = 3.0

## Sensitivity scalar when dragging mouse to rotate inspectable note.
@export var mouse_rotation_speed: float = 0.005

## Tilt strength factor applied to proxy mesh from viewport mouse offset.
@export var hover_tilt_strength: float = 0.15

## Distance in meters the note is held in front of the camera.
@export var reading_distance: float = 0.6

## Maximum radius in UV coordinates for the 3D magnifying glass shader.
@export var max_radius: float = 0.4

## Minimum radius in UV coordinates for the 3D magnifying glass shader.
@export var min_radius: float = 0.15

## Maximum zoom factor scalar for the 3D magnifying glass shader.
@export var max_zoom: float = 5.0

## Minimum zoom factor scalar for the 3D magnifying glass shader.
@export var min_zoom: float = 1.5

## Target rotation angle calculated from relative mouse input.
var _target_sway: Vector3 = Vector3.ZERO

## Target rotation radians applied to proxy mesh via drag or keys.
var _target_rot: Vector2 = Vector2.ZERO

## Tracks whether a note is currently being read by the player.
var _is_reading: bool = false

## Tracks whether the player is holding click to inspect the note.
var _is_inspecting: bool = false

## Tracks whether the rotation axes are inverted for inspection.
var _is_inverted: bool = false

## Tracks whether the 3D magnifying glass overlay is currently active.
var _is_glass_active: bool = false

## Current zoom multiplier passed to the 3D magnification shader.
var _current_zoom: float = 2.0

## Current glass radius passed to the 3D magnification shader.
var _current_radius: float = 0.2

## Reference to the original world note entity being inspected.
var _current_note: Node3D = null

## Reusable 3D mesh instance holding the document texture in view.
var _proxy_mesh_instance: MeshInstance3D = null

## Cached [QuadMesh] driving the proxy document geometry.
var _proxy_quad: QuadMesh = null

## Cached [StandardMaterial3D] displaying the unshaded note texture.
var _proxy_material: StandardMaterial3D = null

## Reusable 3D mesh instance rendering the magnified shader quad.
var _zoomed_mesh_instance: MeshInstance3D = null

## Cached [QuadMesh] driving the magnified zoom overlay geometry.
var _zoomed_quad: QuadMesh = null

## Cached [ShaderMaterial] executing the high-res zoom shader.
var _zoomed_material: ShaderMaterial = null

## Reference to the interacting player character body.
var _current_player: CharacterBody3D = null

## Reusable background mesh instance dimming the world behind the note.
var _bg_dimmer: MeshInstance3D = null

## Cached [QuadMesh] driving the background dimmer geometry.
var _dimmer_quad: QuadMesh = null

## Cached [StandardMaterial3D] applying translucent black shading.
var _dimmer_material: StandardMaterial3D = null

## Fallback [CanvasLayer] displaying inspection keybindings.
var _instruction_ui: CanvasLayer = null

## Cached [Label] displaying control instructions on HUD.
var _instruction_label: Label = null


## Initializes pre-allocated visual quads and material caches to prevent heap leaks.
func _ready() -> void:
	print("NoteReader: Initializing zero-allocation inspection hierarchy.")
	_setup_proxy_hierarchy()
	_setup_dimmer()
	_setup_instruction_ui()


## Processes user input for toggling magnification, axis inversion, and rotation.
func _input(event: InputEvent) -> void:
	if not _is_reading or _current_note == null:
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.physical_keycode == KEY_Z and key_event.pressed and not key_event.echo:
			_is_glass_active = not _is_glass_active
			if is_instance_valid(_zoomed_mesh_instance):
				_zoomed_mesh_instance.visible = _is_glass_active
			print("NoteReader: 3D Magnifying glass toggled -> ", _is_glass_active)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if _is_glass_active and mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_3d_glass(1.0)
				get_viewport().set_input_as_handled()
				return
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_3d_glass(-1.0)
				get_viewport().set_input_as_handled()
				return

		if mouse_event.double_click:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				_target_rot = Vector2.ZERO
				if is_instance_valid(_proxy_mesh_instance):
					_proxy_mesh_instance.rotation.x = wrapf(
						_proxy_mesh_instance.rotation.x, -PI, PI
					)
					_proxy_mesh_instance.rotation.y = wrapf(
						_proxy_mesh_instance.rotation.y, -PI, PI
					)
				print("NoteReader: Double L-Click detected. Resetting rotation.")
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				_is_inverted = not _is_inverted
				_update_instruction_text()
				print("NoteReader: Double R-Click detected. Axis inverted: ", _is_inverted)

	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		close_note()
		return

	if event.is_action_pressed(&"shoot"):
		_is_inspecting = true
		print("NoteReader: Started mouse dragging inspection.")
	elif event.is_action_released(&"shoot"):
		_is_inspecting = false
		print("NoteReader: Stopped mouse dragging inspection.")

	if event is InputEventMouseMotion:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		if _is_inspecting:
			var invert_mult: float = -1.0 if _is_inverted else 1.0
			_target_rot.y -= motion_event.relative.x * mouse_rotation_speed * invert_mult
			_target_rot.x += motion_event.relative.y * mouse_rotation_speed * invert_mult
		else:
			_target_sway.y -= motion_event.relative.x * sway_multiplier
			_target_sway.x -= motion_event.relative.y * sway_multiplier
			_target_sway.y = clampf(_target_sway.y, -max_sway_angle, max_sway_angle)
			_target_sway.x = clampf(_target_sway.x, -max_sway_angle, max_sway_angle)


## Applies exponential damping to sway, rotation, and magnifying glass shader uniforms.
func _process(delta: float) -> void:
	if not _is_reading or not is_instance_valid(_proxy_mesh_instance):
		return

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)
	if input_dir.length_squared() > 0.01:
		var invert_mult: float = -1.0 if _is_inverted else 1.0
		_target_rot.y -= input_dir.x * key_rotation_speed * delta * invert_mult
		_target_rot.x += input_dir.y * key_rotation_speed * delta * invert_mult

	_target_rot.x = wrapf(_target_rot.x, -PI, PI)
	_target_rot.y = wrapf(_target_rot.y, -PI, PI)

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = screen_size * 0.5
	var mouse_offset: Vector2 = (mouse_pos - center) / center

	var hover_tilt_x: float = mouse_offset.y * hover_tilt_strength
	var hover_tilt_y: float = -mouse_offset.x * hover_tilt_strength

	position = Vector3(0.0, 0.0, -reading_distance)

	rotation.x = MathUtils.damp(rotation.x, _target_sway.x, sway_return_speed, delta)
	rotation.y = MathUtils.damp(rotation.y, _target_sway.y, sway_return_speed, delta)

	var final_x: float = _target_rot.x + hover_tilt_x
	var final_y: float = _target_rot.y + hover_tilt_y

	var damp_weight: float = 1.0 - exp(-sway_return_speed * delta)
	_proxy_mesh_instance.rotation.x = lerp_angle(
		_proxy_mesh_instance.rotation.x, final_x, damp_weight
	)
	_proxy_mesh_instance.rotation.y = lerp_angle(
		_proxy_mesh_instance.rotation.y, final_y, damp_weight
	)

	_target_sway = MathUtils.damp_v3(_target_sway, Vector3.ZERO, sway_return_speed * 0.5, delta)

	if _is_glass_active and is_instance_valid(_zoomed_mesh_instance):
		_update_magnifier_shader(mouse_pos, screen_size)


## Mounts the reader to camera, configures quad dimensions, and activates inspection.
func open_note(note_node: Node3D, note_text: String, player_character: CharacterBody3D) -> void:
	print("NoteReader: Opening note inspection view.")
	_is_reading = true
	_is_inverted = false
	_is_glass_active = false
	_current_zoom = 2.0
	_current_radius = 0.2
	_current_note = note_node
	_current_player = player_character

	_target_rot = Vector2.ZERO
	_target_sway = Vector3.ZERO

	if _current_player.has_method(&"start_operating_machine"):
		_current_player.call(&"start_operating_machine")

	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and get_parent() != cam:
		reparent(cam)

	position = Vector3(0.0, 0.0, -reading_distance)
	rotation = Vector3.ZERO

	_current_note.visible = false

	_configure_proxy_texture(cam)
	_bg_dimmer.visible = true
	_proxy_mesh_instance.visible = true
	_zoomed_mesh_instance.visible = false

	if is_instance_valid(_instruction_ui):
		_instruction_ui.visible = true
	_update_instruction_text()

	Events.note_opened.emit(note_text)


## Restores player controls, world note visibility, and hides inspection hierarchy.
func close_note() -> void:
	print("NoteReader: Closing note inspection view.")
	_is_reading = false
	_is_inspecting = false

	if is_instance_valid(_instruction_ui):
		_instruction_ui.visible = false

	var global_label: Label = get_tree().get_first_node_in_group(&"note_instruction_label") as Label
	if is_instance_valid(global_label):
		global_label.hide()

	if is_instance_valid(_current_player) and _current_player.has_method(&"stop_operating_machine"):
		_current_player.call(&"stop_operating_machine")

	_current_player = null

	if is_instance_valid(_bg_dimmer):
		_bg_dimmer.visible = false
	if is_instance_valid(_proxy_mesh_instance):
		_proxy_mesh_instance.visible = false
	if is_instance_valid(_zoomed_mesh_instance):
		_zoomed_mesh_instance.visible = false

	if is_instance_valid(_current_note):
		_current_note.visible = true
		var col: CollisionShape3D = (
			_current_note.get_node_or_null("CollisionShape3D") as CollisionShape3D
		)
		if is_instance_valid(col):
			col.disabled = false
		_current_note = null

	Events.note_closed.emit()


## Adjusts magnifying glass zoom factor and aperture radius.
func _adjust_3d_glass(direction: float) -> void:
	_current_zoom = clampf(_current_zoom + (0.5 * direction), min_zoom, max_zoom)
	_current_radius = clampf(_current_radius + (0.05 * direction), min_radius, max_radius)
	print("NoteReader: Glass scaled | Zoom: ", _current_zoom, " | Radius: ", _current_radius)


## Updates magnifying shader parameters and computes raycast UV focus point.
func _update_magnifier_shader(mouse_pos: Vector2, screen_size: Vector2) -> void:
	_zoomed_mesh_instance.rotation = _proxy_mesh_instance.rotation
	var aspect: float = screen_size.x / screen_size.y
	var mouse_uv: Vector2 = mouse_pos / screen_size

	_zoomed_material.set_shader_parameter(&"mouse_uv", mouse_uv)
	_zoomed_material.set_shader_parameter(&"aspect_ratio", aspect)
	_zoomed_material.set_shader_parameter(&"zoom", _current_zoom)
	_zoomed_material.set_shader_parameter(&"glass_radius_uv", _current_radius)

	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return

	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = cam.project_ray_normal(mouse_pos)
	var normal: Vector3 = _proxy_mesh_instance.global_transform.basis.z
	var plane: Plane = Plane(normal, _proxy_mesh_instance.global_position)
	var hit: Variant = plane.intersects_ray(ray_origin, ray_dir)

	if hit != null:
		var local_pt: Vector3 = (
			_proxy_mesh_instance.global_transform.affine_inverse() * (hit as Vector3)
		)
		var u: float = (local_pt.x / _proxy_quad.size.x) + 0.5
		var v: float = 0.5 - (local_pt.y / _proxy_quad.size.y)
		_zoomed_material.set_shader_parameter(&"focus_uv", Vector2(u, v))


## Pre-allocates proxy and zoom meshes with persistent materials.
func _setup_proxy_hierarchy() -> void:
	print("NoteReader: Pre-allocating proxy mesh nodes and materials.")
	_proxy_mesh_instance = MeshInstance3D.new()
	_proxy_quad = QuadMesh.new()
	_proxy_material = StandardMaterial3D.new()

	_proxy_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_proxy_material.no_depth_test = true
	_proxy_material.render_priority = 2
	_proxy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_proxy_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	_proxy_mesh_instance.mesh = _proxy_quad
	_proxy_mesh_instance.material_override = _proxy_material
	_proxy_mesh_instance.visible = false
	add_child(_proxy_mesh_instance)

	_zoomed_mesh_instance = MeshInstance3D.new()
	_zoomed_quad = QuadMesh.new()
	_zoomed_material = ShaderMaterial.new()
	_zoomed_material.shader = ZOOM_SHADER
	_zoomed_material.render_priority = 3

	_zoomed_mesh_instance.mesh = _zoomed_quad
	_zoomed_mesh_instance.material_override = _zoomed_material
	_zoomed_mesh_instance.scale = Vector3(5.0, 5.0, 5.0)
	_zoomed_mesh_instance.visible = false
	add_child(_zoomed_mesh_instance)


## Configures quad dimensions and texture filtering without allocations.
func _configure_proxy_texture(cam: Camera3D) -> void:
	var tex: Texture2D = null
	if _current_note != null and _current_note.get(&"note_texture") != null:
		tex = _current_note.get(&"note_texture") as Texture2D

	if tex != null:
		var fov: float = cam.fov
		var frustum_h: float = 2.0 * reading_distance * tan(deg_to_rad(fov * 0.5))
		var v_size: Vector2 = get_viewport().get_visible_rect().size
		var frustum_w: float = frustum_h * (v_size.x / v_size.y)
		var max_h: float = frustum_h * 0.63
		var max_w: float = frustum_w * 0.63

		var aspect: float = float(tex.get_width()) / float(tex.get_height())
		var quad_w: float = max_h * aspect
		var quad_h: float = max_h

		if quad_w > max_w:
			quad_w = max_w
			quad_h = quad_w / aspect

		_proxy_quad.size = Vector2(quad_w, quad_h)
		_zoomed_quad.size = _proxy_quad.size

		_proxy_material.albedo_texture = tex
		_zoomed_material.set_shader_parameter(&"albedo_tex", tex)
		_zoomed_material.set_shader_parameter(&"mesh_scale", 5.0)
	else:
		_proxy_quad.size = Vector2(0.3, 0.3)
		_zoomed_quad.size = _proxy_quad.size


## Pre-allocates background dimmer plane mesh and material.
func _setup_dimmer() -> void:
	print("NoteReader: Pre-allocating background dimmer quad.")
	_bg_dimmer = MeshInstance3D.new()
	_dimmer_quad = QuadMesh.new()
	_dimmer_quad.size = Vector2(10.0, 10.0)

	_dimmer_material = StandardMaterial3D.new()
	_dimmer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dimmer_material.albedo_color = Color(0.0, 0.0, 0.0, 0.85)
	_dimmer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dimmer_material.no_depth_test = true
	_dimmer_material.render_priority = 1

	_bg_dimmer.mesh = _dimmer_quad
	_bg_dimmer.material_override = _dimmer_material
	_bg_dimmer.position = Vector3(0.0, 0.0, -0.2)
	_bg_dimmer.visible = false
	add_child(_bg_dimmer)


## Pre-allocates fallback UI CanvasLayer and Label.
func _setup_instruction_ui() -> void:
	print("NoteReader: Pre-allocating instruction CanvasLayer.")
	_instruction_ui = CanvasLayer.new()
	_instruction_ui.layer = 100
	_instruction_ui.visible = false
	add_child(_instruction_ui)

	_instruction_label = Label.new()
	_instruction_label.name = "InstructionLabel"
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_instruction_label.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE
	)
	_instruction_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_instruction_label.offset_bottom = -40

	_instruction_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_instruction_label.add_theme_constant_override(&"outline_size", 10)
	_instruction_label.add_theme_font_size_override(&"font_size", 20)
	_instruction_ui.add_child(_instruction_label)


## Updates instruction text on UI label according to active input mappings.
func _update_instruction_text() -> void:
	var ui_label: Label = _instruction_label
	var global_label: Label = get_tree().get_first_node_in_group(&"note_instruction_label") as Label
	if is_instance_valid(global_label):
		ui_label = global_label
		ui_label.show()

	if not is_instance_valid(ui_label):
		return

	var forward_k: String = _get_key_string_for_action(&"forward", "W")
	var left_k: String = _get_key_string_for_action(&"left", "A")
	var back_k: String = _get_key_string_for_action(&"backward", "S")
	var right_k: String = _get_key_string_for_action(&"right", "D")
	var interact_k: String = _get_key_string_for_action(&"interact", "E")

	var shoot_events: Array[InputEvent] = InputMap.action_get_events(&"shoot")
	var shoot_str: String = "Left Click"
	if not shoot_events.is_empty() and shoot_events[0] is InputEventKey:
		shoot_str = OS.get_keycode_string((shoot_events[0] as InputEventKey).physical_keycode)

	var mode_str: String = "INVERTED" if _is_inverted else "DEFAULT"
	var text_fmt: String = (
		"--- [ %s MODE ] ---\n"
		+ "Use %s%s%s%s or Hold [%s] + Mouse to Rotate.\n"
		+ "Double L-Click to Reset | Double R-Click to Invert Axis.\n"
		+ "Press [Z] for Magnifying Glass (Scroll to Scale) | Press [%s] to Close."
	)
	ui_label.text = text_fmt % [mode_str, forward_k, left_k, back_k, right_k, shoot_str, interact_k]
	print("NoteReader: Instruction text updated.")


## Resolves key display string from active [InputMap] action.
func _get_key_string_for_action(action_name: StringName, fallback: String) -> String:
	if InputMap.has_action(action_name):
		var events: Array[InputEvent] = InputMap.action_get_events(action_name)
		for ev: InputEvent in events:
			if ev is InputEventKey:
				var key_ev: InputEventKey = ev as InputEventKey
				return "[" + OS.get_keycode_string(key_ev.physical_keycode) + "]"
	return "[" + fallback + "]"
