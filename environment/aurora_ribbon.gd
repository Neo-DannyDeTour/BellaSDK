## Controls per-instance shader parameters, visibility culling, and tweened fading
## for an individual aurora borealis ribbon mesh.
@tool
# class_name AuroraRibbon
extends MeshInstance3D

const RENDER_LAYER_ENV: int = 1
const PARAM_TINT: StringName = &"tint_color"
const PARAM_INTENSITY: StringName = &"intensity"
const PARAM_PHASE: StringName = &"phase_offset"

@export var tint_color: Color = Color(0.1, 0.9, 0.4, 1.0):
	set(value):
		tint_color = value
		if is_instance_valid(self) and is_inside_tree():
			set_instance_shader_parameter(PARAM_TINT, tint_color)

@export_range(0.0, 10.0, 0.05) var intensity: float = 2.0:
	set(value):
		intensity = value
		if is_instance_valid(self) and is_inside_tree():
			set_instance_shader_parameter(PARAM_INTENSITY, intensity)

@export var phase_offset: float = 0.0:
	set(value):
		phase_offset = value
		if is_instance_valid(self) and is_inside_tree():
			set_instance_shader_parameter(PARAM_PHASE, phase_offset)

@export var screen_notifier: VisibleOnScreenNotifier3D

var _fade_tween: Tween


## Initializes render layers, disables per-frame processing, and binds screen culling.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	layers = RENDER_LAYER_ENV
	_apply_all_instance_params()

	if Engine.is_editor_hint():
		return

	assert(mesh != null, "AuroraRibbon requires a valid PlaneMesh assigned.")
	assert(
		(
			material_override != null
			or get_surface_override_material(0) != null
			or mesh.surface_get_material(0) != null
		),
		"AuroraRibbon requires a ShaderMaterial."
	)

	if is_instance_valid(screen_notifier):
		screen_notifier.screen_entered.connect(_on_screen_entered)
		screen_notifier.screen_exited.connect(_on_screen_exited)
		visible = screen_notifier.is_on_screen()


## Smoothly transitions the ribbon's emissive intensity using a Tween.
func fade_intensity(target: float, duration: float) -> void:
	print("AuroraRibbon [%s]: fading intensity to %.2f over %.2fs" % [name, target, duration])
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()

	if duration <= 0.0:
		intensity = target
		return

	_fade_tween = create_tween()
	(
		_fade_tween
		. tween_property(self, ^"intensity", target, duration)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)


## Synchronizes all exported instance shader parameters on tree entry.
func _apply_all_instance_params() -> void:
	set_instance_shader_parameter(PARAM_TINT, tint_color)
	set_instance_shader_parameter(PARAM_INTENSITY, intensity)
	set_instance_shader_parameter(PARAM_PHASE, phase_offset)


## Enables rendering when the ribbon enters the camera frustum.
func _on_screen_entered() -> void:
	visible = true


## Disables rendering when the ribbon exits the camera frustum.
func _on_screen_exited() -> void:
	visible = false
