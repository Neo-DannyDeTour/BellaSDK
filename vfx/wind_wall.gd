@tool
## Procedural wind barrier [Node3D] driving multi-layer volumetric shaders
## and [Area3D] projectile interception via event-driven [Tween] lifecycle.
# class_name WindWall
extends Node3D

## Emitted when a Physics Layer 4 (Debris) or Layer 5 (Enemies) target hits the wall.
@warning_ignore("unused_signal")
signal intercepted(target: Node3D)

## Volumetrics render layer bitmask (Layer 10).
const RENDER_LAYER_VOLUMETRICS: int = 1 << 9

## Interactive physics layer bitmask (Layer 3).
const PHYSICS_LAYER_INTERACTIVE: int = 1 << 2

## Physics mask combination for Debris (Layer 4) and Enemies (Layer 5).
const PHYSICS_MASK_DEBRIS_ENEMIES: int = (1 << 3) | (1 << 4)

## Shader uniform name for instance color tint.
const PARAM_TINT: StringName = &"tint"

## Shader uniform name for instance UV scale vector.
const PARAM_UV_SCALE: StringName = &"uv_scale"

## Shader uniform name for instance scroll speed vector.
const PARAM_SCROLL_SPEED: StringName = &"scroll_speed"

## Shader uniform name for instance noise power exponent.
const PARAM_NOISE_POWER: StringName = &"noise_power"

## Shader uniform name for instance fade intensity multiplier.
const PARAM_FADE: StringName = &"fade"

## Total duration in seconds before the wind wall finishes transit.
@export var lifetime: float = 4.0

## Total forward displacement in meters along local -Z basis.
@export var travel_distance: float = 6.0

## Normalized fraction of [member lifetime] dedicated to fading out.
@export var fade_out_ratio: float = 0.25

## Restarts motion sequence upon completion instead of freeing node.
@export var loop: bool = false:
	set(value):
		loop = value
		if Engine.is_editor_hint() and is_inside_tree() and _nodes_verified:
			_handle_editor_loop_change(value)

var _tween: Tween = null
var _layers: Array[MeshInstance3D] = []
var _spawn_position: Vector3 = Vector3.ZERO
var _nodes_verified: bool = false

@onready var _main_layer: MeshInstance3D = $MainLayer
@onready var _back_layer: MeshInstance3D = $BackLayer
@onready var _thick_layer: MeshInstance3D = $ThickLayer
@onready var _hitbox: Area3D = $Hitbox
@onready var _screen_notifier: VisibleOnScreenNotifier3D = $ScreenNotifier


## Validates scene invariants, configures layers, and starts motion sequence.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(_main_layer != null, "MainLayer MeshInstance3D missing.")
	assert(_back_layer != null, "BackLayer MeshInstance3D missing.")
	assert(_thick_layer != null, "ThickLayer MeshInstance3D missing.")
	assert(_hitbox != null, "Hitbox Area3D missing.")
	assert(_screen_notifier != null, "ScreenNotifier missing.")

	_nodes_verified = true
	_spawn_position = position
	_layers = [_main_layer, _back_layer, _thick_layer]

	_setup_render_layers()
	if not Engine.is_editor_hint():
		_setup_physics()
		_setup_visibility_gate()
		_start_wall_sequence()
	elif loop:
		_start_wall_sequence()


## Cleans up active [Tween] on tree exit.
func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


## Assigns Render Layer 10 (Volumetrics) and per-instance uniforms without material duplication.
func _setup_render_layers() -> void:
	for mesh: MeshInstance3D in _layers:
		mesh.layers = RENDER_LAYER_VOLUMETRICS
		mesh.set_instance_shader_parameter(PARAM_FADE, 1.0)

	# Main layer: sharp high-intensity streaks.
	_main_layer.set_instance_shader_parameter(PARAM_TINT, Color(0.4, 0.85, 1.0, 1.0))
	_main_layer.set_instance_shader_parameter(PARAM_UV_SCALE, Vector2(3.2, 0.24))
	_main_layer.set_instance_shader_parameter(PARAM_SCROLL_SPEED, Vector2(0.0, -0.64))
	_main_layer.set_instance_shader_parameter(PARAM_NOISE_POWER, 3.0)

	# Back layer: softer, fuller volume fill.
	_back_layer.set_instance_shader_parameter(PARAM_TINT, Color(0.2, 0.55, 0.9, 0.45))
	_back_layer.set_instance_shader_parameter(PARAM_UV_SCALE, Vector2(1.9, 0.5))
	_back_layer.set_instance_shader_parameter(PARAM_SCROLL_SPEED, Vector2(0.0, -0.45))
	_back_layer.set_instance_shader_parameter(PARAM_NOISE_POWER, 2.0)

	# Thick layer: wider Z-scale offset for parallax thickness.
	_thick_layer.set_instance_shader_parameter(PARAM_TINT, Color(0.3, 0.75, 1.0, 0.7))
	_thick_layer.set_instance_shader_parameter(PARAM_UV_SCALE, Vector2(2.6, 0.3))
	_thick_layer.set_instance_shader_parameter(PARAM_SCROLL_SPEED, Vector2(0.0, -0.75))
	_thick_layer.set_instance_shader_parameter(PARAM_NOISE_POWER, 2.5)


## Configures Physics Layer 3 (Interactive) and masks Layers 4 (Debris) + 5 (Enemies).
func _setup_physics() -> void:
	_hitbox.collision_layer = PHYSICS_LAYER_INTERACTIVE
	_hitbox.collision_mask = PHYSICS_MASK_DEBRIS_ENEMIES
	_hitbox.body_entered.connect(_on_target_entered)
	_hitbox.area_entered.connect(_on_target_entered)


## Connects [VisibleOnScreenNotifier3D] signals to gate mesh rendering off-screen.
func _setup_visibility_gate() -> void:
	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)


## Spawns exponential deceleration movement and schedules fade-out and cleanup.
func _start_wall_sequence() -> void:
	print("WindWall: spawned at ", global_position)
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_set_wall_fade(1.0)
	if not Engine.is_editor_hint():
		_enable_hitbox()

	_tween = create_tween().set_parallel(true)
	var target_pos: Vector3 = _spawn_position - transform.basis.z * travel_distance
	var fade_start_time: float = lifetime * (1.0 - fade_out_ratio)
	var fade_duration: float = lifetime * fade_out_ratio

	# Fast burst out, slow drift to halt (matches 0.16s curve knee).
	(
		_tween
		. tween_property(self, ^"position", target_pos, lifetime)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_OUT)
	)

	# Disable hitbox monitoring when fade-out begins.
	if not Engine.is_editor_hint():
		_tween.tween_callback(_disable_hitbox).set_delay(fade_start_time)

	# Tween per-instance fade uniform from 1.0 to 0.0 over final segment.
	(
		_tween
		. tween_method(_set_wall_fade, 1.0, 0.0, fade_duration)
		. set_delay(fade_start_time)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN)
	)

	_tween.chain().tween_callback(_on_lifetime_expired)


## Updates the instance shader fade parameter across all mesh layers.
func _set_wall_fade(val: float) -> void:
	for mesh: MeshInstance3D in _layers:
		if is_instance_valid(mesh):
			mesh.set_instance_shader_parameter(PARAM_FADE, val)


## Safely enables physics monitoring via deferred call on cycle restart.
func _enable_hitbox() -> void:
	_hitbox.set_deferred(&"monitoring", true)
	_hitbox.set_deferred(&"monitorable", true)


## Safely disables physics monitoring via deferred call before fade completion.
func _disable_hitbox() -> void:
	print("WindWall: hitbox deactivated (fading out)")
	_hitbox.set_deferred(&"monitoring", false)
	_hitbox.set_deferred(&"monitorable", false)


## Frees the node or restarts loop when the lifetime tween completes.
func _on_lifetime_expired() -> void:
	if loop and is_inside_tree():
		print("WindWall: loop restart")
		position = _spawn_position
		_start_wall_sequence()
	elif not Engine.is_editor_hint():
		print("WindWall: expired and freed")
		queue_free()
	else:
		position = _spawn_position
		_set_wall_fade(1.0)


## Handles collision with projectiles or debris on Layers 4 and 5.
func _on_target_entered(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	print("WindWall: intercepted ", target.name)
	intercepted.emit(target)


## Restores mesh visibility when entering camera frustum.
func _on_screen_entered() -> void:
	for mesh: MeshInstance3D in _layers:
		mesh.visible = true


## Hides meshes when exiting camera frustum while keeping physics active.
func _on_screen_exited() -> void:
	for mesh: MeshInstance3D in _layers:
		mesh.visible = false


## Handles loop toggle changes within editor hint mode.
func _handle_editor_loop_change(enabled: bool) -> void:
	if enabled:
		_spawn_position = position
		_start_wall_sequence()
	else:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		position = _spawn_position
		_set_wall_fade(1.0)
