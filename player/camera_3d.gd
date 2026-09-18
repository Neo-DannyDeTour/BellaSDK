## Manages [Camera3D] audio listening, screen shake trauma decay, DoF, and motion blur overlays.
class_name ExtendedCamera3D
extends Camera3D

@export_category("Camera Role")
## If true, activates [AudioListener3D] and runs process loop on boot.
@export var is_player_camera: bool = true

@export_category("Screenshake Settings")
## Speed scalar driving procedural noise sampling for camera screen shake offsets.
@export var noise_speed: float = 50.0
## Maximum horizontal translational pixel offset applied during peak camera shake.
@export var max_offset_x: float = 0.5
## Maximum vertical translational pixel offset applied during peak camera shake.
@export var max_offset_y: float = 0.5
## Maximum rotational roll in degrees applied to camera during peak screen shake.
@export var max_roll_z: float = 2.0

## Current trauma scalar in range [0, 1] determining instantaneous shake energy.
var _trauma: float = 0.0
## Peak amplitude assigned to current shake event from bus signal payload.
var _amplitude: float = 0.0
## Speed at which [member _trauma] decays back to zero over elapsed delta time.
var _decay_rate: float = 1.0
## Accumulated elapsed time in seconds passed into [FastNoiseLite] sample queries.
var _time_passed: float = 0.0
## Procedural simplex noise generator driving smooth pseudo-random camera offsets.
var _noise: FastNoiseLite = FastNoiseLite.new()

## Full-screen accessibility quad [MeshInstance3D] hosting high-contrast shaders.
var vision_assist_mesh: MeshInstance3D = null
## Legacy mesh reference retained for cleanup if spawned in older scene setups.
var motion_blur_mesh: MeshInstance3D = null
## Dedicated [AudioListener3D] instance attached as a child node for 3D panning.
var _spatial_listener: AudioListener3D = null

## Cached duplicated [ShaderMaterial] instance driving vision assist color modes.
var _vision_shader_material: ShaderMaterial = null
## Cached [ShaderMaterial] instance applying screen-space motion blur convolution.
var _motion_blur_material: ShaderMaterial = null

## Full-screen [CanvasLayer] hosting the screen-space motion blur canvas item.
var motion_blur_layer: CanvasLayer = null
## Full-screen [ColorRect] carrying the motion blur shader and sampling viewport.
var motion_blur_rect: ColorRect = null
## Global rotation [Quaternion] from previous frame used to compute angular delta.
var _prev_camera_quat: Quaternion = Quaternion.IDENTITY
## Indicates whether [member _prev_camera_quat] has been seeded with valid rotation.
var _has_prev_rot: bool = false


## Initializes audio listeners, motion blur passes, and screen shake listeners.
func _ready() -> void:
	print("ExtendedCamera3D: Initializing camera components for: ", name)
	_resolve_vision_mesh()
	_cache_vision_material()
	_setup_motion_blur_quad()
	_setup_camera_attributes()

	var is_preview_cam: bool = get_viewport() is SubViewport
	if not is_player_camera and not is_preview_cam:
		print("ExtendedCamera3D: Non-player camera; disabling process loop.")
		set_process(false)
		if is_instance_valid(vision_assist_mesh):
			vision_assist_mesh.visible = current
		if is_instance_valid(motion_blur_mesh):
			motion_blur_mesh.visible = current
		return

	if is_player_camera:
		make_current()
		print("ExtendedCamera3D: Player camera set as active listener.")
		_setup_audio_listener()

	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("player_camera_registered"):
			events.emit_signal("player_camera_registered", self)
		if events.has_signal("screenshake_requested"):
			events.screenshake_requested.connect(_on_screenshake_requested)
		if events.has_signal("vision_assist_toggled"):
			events.vision_assist_toggled.connect(_on_vision_assist_toggled)
		if events.has_signal("vision_assist_mode_changed"):
			events.vision_assist_mode_changed.connect(set_vision_assist_mode)


## Configures [CameraAttributesPractical] and ensures DoF is disabled on boot.
func _setup_camera_attributes() -> void:
	print("ExtendedCamera3D: Configuring CameraAttributesPractical.")
	if not is_instance_valid(attributes) or not (attributes is CameraAttributesPractical):
		attributes = CameraAttributesPractical.new()

	var attr: CameraAttributesPractical = attributes as CameraAttributesPractical
	attr.dof_blur_far_distance = 6.0
	attr.dof_blur_far_transition = 4.0
	attr.dof_blur_near_distance = 0.5
	attr.dof_blur_near_transition = 0.5
	attr.dof_blur_far_enabled = false
	attr.dof_blur_near_enabled = false
	attr.dof_blur_amount = 0.0


## Spawns dormant [CanvasLayer] post-process overlay with 4-sample blur shader.
func _setup_motion_blur_quad() -> void:
	print("ExtendedCamera3D: Setting up CanvasLayer motion blur overlay.")
	if is_instance_valid(motion_blur_mesh):
		motion_blur_mesh.queue_free()
		motion_blur_mesh = null

	var existing_layer: Node = get_node_or_null("MotionBlurLayer")
	if is_instance_valid(existing_layer):
		motion_blur_layer = existing_layer as CanvasLayer
		motion_blur_rect = motion_blur_layer.get_node_or_null("BlurRect") as ColorRect
	else:
		motion_blur_layer = CanvasLayer.new()
		motion_blur_layer.name = "MotionBlurLayer"
		motion_blur_layer.layer = 10
		add_child(motion_blur_layer)

		motion_blur_rect = ColorRect.new()
		motion_blur_rect.name = "BlurRect"
		motion_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		motion_blur_layer.add_child(motion_blur_rect)
		motion_blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	motion_blur_layer.visible = false

	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 camera_angular_velocity = vec2(0.0);
uniform float motion_blur_strength = 0.0;
uniform int blur_samples = 4;

void fragment() {
	vec2 vel = camera_angular_velocity * motion_blur_strength * 0.08;
	vel = clamp(vel, vec2(-0.05), vec2(0.05));

	if (motion_blur_strength <= 0.005 || length(vel) < 0.00005) {
		COLOR = texture(screen_texture, SCREEN_UV);
	} else {
		vec4 color = vec4(0.0);
		for (int i = 0; i < blur_samples; i++) {
			float offset_scale = (float(i) / float(blur_samples - 1)) - 0.5;
			vec2 sample_uv = clamp(
				SCREEN_UV + (vel * offset_scale),
				vec2(0.001),
				vec2(0.999)
			);
			color += texture(screen_texture, sample_uv);
		}
		COLOR = color / float(blur_samples);
	}
}
"""
	_motion_blur_material = ShaderMaterial.new()
	_motion_blur_material.shader = shader
	motion_blur_rect.material = _motion_blur_material


## Sets motion blur shader strength and toggles [CanvasLayer] visibility directly.
func set_motion_blur_strength(strength: float) -> void:
	print("ExtendedCamera3D: Setting motion blur strength to: ", strength)
	var is_active: bool = strength > 0.005
	if is_instance_valid(motion_blur_layer):
		motion_blur_layer.visible = is_active
	if is_instance_valid(_motion_blur_material):
		_motion_blur_material.set_shader_parameter(
			"motion_blur_strength", strength if is_active else 0.0
		)


## Discovers and caches [member vision_assist_mesh] child node in the scene tree.
func _resolve_vision_mesh() -> void:
	print("ExtendedCamera3D: Resolving vision assist mesh.")
	if is_instance_valid(vision_assist_mesh):
		return
	vision_assist_mesh = get_node_or_null("VisionAssistMesh")
	if not is_instance_valid(vision_assist_mesh):
		for child: Node in get_children():
			if child is MeshInstance3D and child.name.begins_with("VisionAssistMesh"):
				vision_assist_mesh = child as MeshInstance3D
				break


## Duplicates vision assist material into an isolated unique [ShaderMaterial].
func _cache_vision_material() -> void:
	print("ExtendedCamera3D: Caching unique vision assist material.")
	_resolve_vision_mesh()
	if is_instance_valid(vision_assist_mesh):
		var active_mat: Material = vision_assist_mesh.get_surface_override_material(0)
		if not is_instance_valid(active_mat):
			active_mat = vision_assist_mesh.get_active_material(0)
		if active_mat is ShaderMaterial:
			_vision_shader_material = active_mat.duplicate() as ShaderMaterial
			_vision_shader_material.render_priority = 10
			vision_assist_mesh.set_surface_override_material(0, _vision_shader_material)


## Creates and activates child [AudioListener3D] node for spatial 3D sound panning.
func _setup_audio_listener() -> void:
	print("ExtendedCamera3D: Setting up spatial audio listener.")
	if not is_instance_valid(_spatial_listener):
		_spatial_listener = AudioListener3D.new()
		add_child(_spatial_listener)
	_spatial_listener.make_current()


## Processes shake trauma decay and updates motion blur angular velocity vectors.
func _process(delta: float) -> void:
	if _trauma > 0.0:
		_trauma = maxf(_trauma - (_decay_rate * delta), 0.0)
		_apply_shake(delta)
	elif h_offset != 0.0 or v_offset != 0.0 or rotation_degrees.z != 0.0:
		h_offset = 0.0
		v_offset = 0.0
		rotation_degrees.z = 0.0
		_amplitude = 0.0

	_update_motion_blur_matrices(delta)


## Submits camera angular delta to shader when blur overlay is actively visible.
func _update_motion_blur_matrices(delta: float) -> void:
	if not is_instance_valid(_motion_blur_material):
		return

	var cur_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
	if not _has_prev_rot:
		_prev_camera_quat = cur_quat
		_has_prev_rot = true
		return

	if is_instance_valid(motion_blur_layer) and not motion_blur_layer.visible:
		_prev_camera_quat = cur_quat
		return

	var rot_diff: Quaternion = _prev_camera_quat.inverse() * cur_quat
	var euler_diff: Vector3 = rot_diff.get_euler()

	var fps_factor: float = (1.0 / 60.0) / maxf(delta, 0.0001)
	var screen_vel: Vector2 = Vector2(-euler_diff.y, euler_diff.x) * fps_factor
	_motion_blur_material.set_shader_parameter("camera_angular_velocity", screen_vel)

	_prev_camera_quat = cur_quat


## Computes procedural noise offsets and applies h_offset, v_offset, and roll.
func _apply_shake(delta: float) -> void:
	_time_passed += delta * noise_speed
	var shake_power: float = (_trauma * _trauma) * _amplitude

	h_offset = max_offset_x * shake_power * _noise.get_noise_2d(_time_passed, 0.0)
	v_offset = max_offset_y * shake_power * _noise.get_noise_2d(_time_passed, 100.0)
	rotation_degrees.z = (max_roll_z * shake_power * _noise.get_noise_2d(_time_passed, 200.0))


## Receives shake impulse event from bus and sets [member _trauma] and decay rate.
func _on_screenshake_requested(intensity: float, duration: float) -> void:
	print("ExtendedCamera3D: Shake requested on: ", name, " -> ", intensity)
	_amplitude = maxf(_amplitude, clampf(intensity, 0.0, 16.0))
	_trauma = 1.0
	_decay_rate = 1.0 / duration if duration > 0.0 else 1.0


## Toggles visibility on [member vision_assist_mesh] when accessibility is flipped.
func _on_vision_assist_toggled(is_active: bool) -> void:
	print("ExtendedCamera3D: Toggling vision assist to: ", is_active)
	_resolve_vision_mesh()
	if is_instance_valid(vision_assist_mesh):
		vision_assist_mesh.visible = is_active and current


## Updates shader mode integer uniform for accessibility high-contrast rendering.
func set_vision_assist_mode(mode_name: String) -> void:
	print("ExtendedCamera3D: Setting vision assist mode: ", mode_name)
	if not is_instance_valid(_vision_shader_material):
		_cache_vision_material()

	if not is_instance_valid(_vision_shader_material):
		return

	match mode_name:
		"black_and_white":
			_vision_shader_material.set_shader_parameter("mode", 0)
		"blue":
			_vision_shader_material.set_shader_parameter("mode", 1)
			_vision_shader_material.set_shader_parameter("blue_base", Color(0.05, 0.1, 0.45, 1.0))
			_vision_shader_material.set_shader_parameter("blue_outline", Color(0.3, 0.5, 0.9, 1.0))
		"pure_black":
			_vision_shader_material.set_shader_parameter("mode", 2)
		"grey":
			_vision_shader_material.set_shader_parameter("mode", 3)
			_vision_shader_material.set_shader_parameter("grey_base", Color(0.25, 0.25, 0.25, 1.0))
			_vision_shader_material.set_shader_parameter(
				"grey_outline", Color(0.85, 0.85, 0.85, 1.0)
			)
		"desaturated":
			_vision_shader_material.set_shader_parameter("mode", 4)
