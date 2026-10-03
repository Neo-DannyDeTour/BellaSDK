## Central coordinator managing screen fades, camera shake events, and shockwave pools.
class_name ScreenEffectsCore
extends CanvasLayer

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Maximum concurrent pooled shockwave particle instances.
const SHOCKWAVE_POOL_SIZE: int = 6

## Default fallback camera trauma decay rate per second.
const DEFAULT_TRAUMA_DECAY: float = 1.0

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_group("Shockwave Settings")
## The [PackedScene] instantiated for pooled 3D shockwave visual effects.
@export var shockwave_scene: PackedScene

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Screen overlay [ColorRect] rendering post-process fade and blur shaders.
@onready var overlay_rect: ColorRect = $OverlayRect

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Shader material applied to the fullscreen transition overlay.
var _overlay_material: ShaderMaterial = null

## Active [Tween] animating screen fade, blur, and blink parameters.
var _active_fade_tween: Tween = null

## Pre-instantiated pool of [GPUParticles3D] shockwave nodes.
var _shockwave_pool: Array[GPUParticles3D] = []

## Container node in scene tree holding pooled shockwave nodes.
var _shockwave_container: Node3D = null

## Next index to allocate within the cyclic shockwave particle pool.
var _next_shockwave_index: int = 0

## Current camera trauma level clamped between 0.0 and 1.0.
var _current_trauma: float = 0.0


## Initializes the screen overlay, connects event bus, and warms shockwave pool.
func _ready() -> void:
	print("ScreenEffectsCore: Initializing centralized screen effects.")
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not is_instance_valid(overlay_rect):
		overlay_rect = get_node_or_null("OverlayRect") as ColorRect

	if not is_instance_valid(overlay_rect):
		overlay_rect = ColorRect.new()
		overlay_rect.name = "OverlayRect"
		overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay_rect)

	overlay_rect.visible = false

	if is_instance_valid(overlay_rect.material) and overlay_rect.material is ShaderMaterial:
		_overlay_material = overlay_rect.material as ShaderMaterial

	_connect_event_bus()
	_init_shockwave_pool()


## Connects the core effects controller to global [Events] bus signals.
func _connect_event_bus() -> void:
	print("ScreenEffectsCore: Connecting event bus listeners.")
	if Events.has_signal(&"screenshake_requested"):
		Events.screenshake_requested.connect(_on_screenshake_requested)
	if Events.has_signal(&"screen_fade_requested"):
		Events.screen_fade_requested.connect(start_screen_fade)
	if Events.has_signal(&"shockwave_requested"):
		Events.shockwave_requested.connect(trigger_shockwave)


## Pre-instantiates a cyclic pool of shockwave particles to avoid GC allocations.
func _init_shockwave_pool() -> void:
	if not is_instance_valid(shockwave_scene):
		print("ScreenEffectsCore: shockwave_scene unassigned. Bypassing particle pool.")
		return

	print("ScreenEffectsCore: Pre-warming shockwave particle pool (size: 6).")
	_shockwave_container = Node3D.new()
	_shockwave_container.name = "ShockwavePoolContainer"
	get_tree().root.call_deferred(&"add_child", _shockwave_container)

	_shockwave_pool.clear()
	for i: int in range(SHOCKWAVE_POOL_SIZE):
		var raw_node: Node = shockwave_scene.instantiate()
		if raw_node is GPUParticles3D:
			var particles: GPUParticles3D = raw_node as GPUParticles3D
			particles.one_shot = true
			particles.emitting = false
			_shockwave_container.add_child(particles)
			_shockwave_pool.append(particles)
		else:
			raw_node.queue_free()


## Handles screenshake trauma requests dispatched from triggers or weapons.
func _on_screenshake_requested(intensity: float, _duration: float) -> void:
	print("ScreenEffectsCore: Trauma impulse received -> ", intensity)
	_current_trauma = clampf(_current_trauma + intensity, 0.0, 1.0)
	var cam_manager: Node = SystemLocator.get_service(&"CameraShakeManager")
	if is_instance_valid(cam_manager) and cam_manager.has_method(&"add_trauma"):
		cam_manager.call(&"add_trauma", intensity)


## Executes a screen fade transition sequence with optional blur and eye blinks.
func start_screen_fade(
	fade_color: Color = Color.BLACK,
	fade_in_time: float = 1.0,
	hold_time: float = 0.5,
	fade_out_time: float = 1.0,
	use_blur: bool = true,
	max_blur: float = 2.5,
	use_blink: bool = false,
	blink_count: int = 1
) -> void:
	print("ScreenEffectsCore: Starting screen fade transition.")
	if not is_instance_valid(overlay_rect):
		return

	if not is_instance_valid(_overlay_material):
		var shader: Shader = load("res://shaders/screen_transition.gdshader") as Shader
		if is_instance_valid(shader):
			_overlay_material = ShaderMaterial.new()
			_overlay_material.shader = shader
			overlay_rect.material = _overlay_material

	if not is_instance_valid(_overlay_material):
		overlay_rect.color = fade_color
		overlay_rect.visible = true
		_run_simple_color_fade(fade_in_time, hold_time, fade_out_time)
		return

	overlay_rect.visible = true
	_overlay_material.set_shader_parameter(&"fade_color", fade_color)
	_overlay_material.set_shader_parameter(&"fade_amount", 0.0)
	_overlay_material.set_shader_parameter(&"blur_amount", 0.0)
	_overlay_material.set_shader_parameter(&"blink_openness", 1.0)

	if _active_fade_tween != null and _active_fade_tween.is_valid():
		_active_fade_tween.kill()

	_active_fade_tween = create_tween()

	# Phase 1: Fade In & Blur
	(
		_active_fade_tween
		. tween_method(_set_shader_fade, 0.0, 1.0, fade_in_time)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	if use_blur:
		(
			_active_fade_tween
			. parallel()
			. tween_method(_set_shader_blur, 0.0, max_blur, fade_in_time)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	if use_blink and blink_count > 0:
		var single_blink: float = fade_in_time / float(blink_count)
		for i: int in range(blink_count):
			var delay: float = i * single_blink
			var half_step: float = single_blink * 0.5
			(
				_active_fade_tween
				. parallel()
				. tween_method(_set_shader_blink, 1.0, 0.0, half_step)
				. set_delay(delay)
				. set_trans(Tween.TRANS_SINE)
			)
			(
				_active_fade_tween
				. parallel()
				. tween_method(_set_shader_blink, 0.0, 1.0, half_step)
				. set_delay(delay + half_step)
				. set_trans(Tween.TRANS_SINE)
			)

	# Phase 2: Hold
	_active_fade_tween.tween_interval(hold_time)

	# Phase 3: Fade Out
	(
		_active_fade_tween
		. tween_method(_set_shader_fade, 1.0, 0.0, fade_out_time)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	if use_blur:
		(
			_active_fade_tween
			. parallel()
			. tween_method(_set_shader_blur, max_blur, 0.0, fade_out_time)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	_active_fade_tween.tween_callback(_on_fade_finished)


## Fallback alpha tween when no transition shader is present.
func _run_simple_color_fade(fade_in: float, hold: float, fade_out: float) -> void:
	print("ScreenEffectsCore: Running simple ColorRect alpha fade.")
	overlay_rect.modulate.a = 0.0
	if _active_fade_tween != null and _active_fade_tween.is_valid():
		_active_fade_tween.kill()

	_active_fade_tween = create_tween()
	_active_fade_tween.tween_property(overlay_rect, "modulate:a", 1.0, fade_in)
	_active_fade_tween.tween_interval(hold)
	_active_fade_tween.tween_property(overlay_rect, "modulate:a", 0.0, fade_out)
	_active_fade_tween.tween_callback(_on_fade_finished)


## Updates screen fade uniform on transition overlay shader.
func _set_shader_fade(val: float) -> void:
	if is_instance_valid(_overlay_material):
		_overlay_material.set_shader_parameter(&"fade_amount", val)


## Updates screen blur uniform on transition overlay shader.
func _set_shader_blur(val: float) -> void:
	if is_instance_valid(_overlay_material):
		_overlay_material.set_shader_parameter(&"blur_amount", val)


## Updates eye blink openness uniform on transition overlay shader.
func _set_shader_blink(val: float) -> void:
	if is_instance_valid(_overlay_material):
		_overlay_material.set_shader_parameter(&"blink_openness", val)


## Concludes the active fade transition and hides the fullscreen rect.
func _on_fade_finished() -> void:
	print("ScreenEffectsCore: Screen fade transition completed.")
	if is_instance_valid(overlay_rect):
		overlay_rect.visible = false


## Spawns a pooled one-shot shockwave instance without heap allocation.
func trigger_shockwave(spawn_pos: Vector3, radius: float = 5.0, speed: float = 2.0) -> void:
	print("ScreenEffectsCore: Triggering shockwave at: ", spawn_pos)
	if _shockwave_pool.is_empty():
		_spawn_dynamic_shockwave(spawn_pos, radius, speed)
		return

	var particles: GPUParticles3D = _shockwave_pool[_next_shockwave_index]
	_next_shockwave_index = (_next_shockwave_index + 1) % _shockwave_pool.size()

	if is_instance_valid(particles):
		particles.global_position = spawn_pos
		particles.scale = Vector3(radius, radius, radius)
		particles.speed_scale = maxf(0.01, speed)
		particles.restart()
		particles.emitting = true


## Dynamic instantiation fallback when particle pool is uninitialized.
func _spawn_dynamic_shockwave(spawn_pos: Vector3, radius: float, speed: float) -> void:
	if not is_instance_valid(shockwave_scene):
		return

	var instance: Node = shockwave_scene.instantiate()
	if instance is GPUParticles3D:
		var effect: GPUParticles3D = instance as GPUParticles3D
		effect.one_shot = true
		effect.explosiveness = 1.0
		effect.speed_scale = maxf(0.01, speed)
		get_tree().current_scene.add_child(effect)
		effect.global_position = spawn_pos
		effect.scale = Vector3(radius, radius, radius)
		effect.restart()

		var duration: float = (effect.lifetime / effect.speed_scale) + 0.15
		get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				if is_instance_valid(effect):
					effect.queue_free()
		)
	else:
		instance.queue_free()
