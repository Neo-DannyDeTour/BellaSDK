## Spotlight controller with [PowerComponent] integration and Quake/Valve flicker patterns.
@tool
class_name PoweredLight3D
extends Node3D

## Emitted when required power threshold is met or light is turned on.
signal powered_on
## Emitted when power drops below threshold or light is turned off.
signal powered_off

## Quake / Half-Life light style presets plus custom string and curve modes.
enum FlickerPreset {
	NORMAL,
	FLICKER_A,
	SLOW_STRONG_PULSE,
	CANDLE_A,
	FAST_STROBE,
	GENTLE_PULSE,
	FLICKER_B,
	CANDLE_B,
	CANDLE_C,
	SLOW_STROBE,
	FLUORESCENT_FLICKER,
	SLOW_PULSE_NO_BLACK,
	CUSTOM_STRING,
	CUSTOM_CURVE,
}

## ASCII value for 'a' (0% intensity).
const ASCII_A: int = 97
## ASCII span from 'a' to 'm' (12 steps = 100% normal intensity).
const ASCII_M_OFFSET: float = 12.0

## Lookup table mapping [enum FlickerPreset] to classic Valve/Quake pattern strings.
const PRESET_PATTERNS: Dictionary[int, String] = {
	FlickerPreset.NORMAL: "m",
	FlickerPreset.FLICKER_A: "mmnmmommommnonmmonqnmmo",
	FlickerPreset.SLOW_STRONG_PULSE: "abcdefghijklmnopqrstuvwxyzyxwvutsrqponmlkjihgfedcba",
	FlickerPreset.CANDLE_A: "mmmmmaaaaammmmmaaaaaabcdefgabcdefg",
	FlickerPreset.FAST_STROBE: "mamamamamama",
	FlickerPreset.GENTLE_PULSE: "jklmnopqrstuvwxyzyxwvutsrqponmlkj",
	FlickerPreset.FLICKER_B: "nmonqnmomnmomomno",
	FlickerPreset.CANDLE_B: "mmmaaaabcdefgmmmmaaaammmaamm",
	FlickerPreset.CANDLE_C: "mmmaaammmaaammmabcdefaaaammmmabcdefmmmaaaa",
	FlickerPreset.SLOW_STROBE: "aaaaaaaazzzzzzzz",
	FlickerPreset.FLUORESCENT_FLICKER: "mmamammmmammamamaaamammma",
	FlickerPreset.SLOW_PULSE_NO_BLACK: "abcdefghijklmnopqrrqponmlkjihgfedcba",
}

@export_group("Power Settings")
## Number of distinct power inputs needed to turn this light on.
@export var required_power: int = 1:
	set(value):
		required_power = maxi(1, value)
		if is_inside_tree() and is_instance_valid(power_component):
			power_component.required_power = required_power

## If true, starts powered on at runtime without waiting for [member power_component].
@export var start_on: bool = false

@export_group("Light Appearance")
## Emitted light tint color synced to [SpotLight3D].
@export var light_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		light_color = value
		_sync_light_properties()

## Baseline energy multiplier ('m' in Quake pattern = 100% of this value).
@export_range(0.0, 64.0, 0.05) var base_energy: float = 1.0:
	set(value):
		base_energy = maxf(0.0, value)
		_sync_light_properties()

## Secondary bounce multiplier synced to [SpotLight3D].
@export_range(0.0, 16.0, 0.05) var indirect_energy: float = 1.0:
	set(value):
		indirect_energy = maxf(0.0, value)
		_sync_light_properties()

## Volumetric fog scattering multiplier synced to [SpotLight3D].
@export_range(0.0, 16.0, 0.05) var volumetric_fog_energy: float = 1.0:
	set(value):
		volumetric_fog_energy = maxf(0.0, value)
		_sync_light_properties()

## Maximum spotlight attenuation distance in meters.
@export_range(0.1, 200.0, 0.1) var spot_range: float = 10.0:
	set(value):
		spot_range = maxf(0.1, value)
		_sync_light_properties()

## Spotlight cone outer angle in degrees.
@export_range(1.0, 180.0, 0.5) var spot_angle: float = 45.0:
	set(value):
		spot_angle = clampf(value, 1.0, 180.0)
		_sync_light_properties()

## Enables real-time shadow rendering on the spotlight.
@export var shadows_enabled: bool = false:
	set(value):
		shadows_enabled = value
		_sync_light_properties()

@export_group("Flicker & Style")
## Active flicker animation style preset.
@export var flicker_preset: FlickerPreset = FlickerPreset.NORMAL:
	set(value):
		flicker_preset = value
		_rebuild_pattern_cache()
		_update_process_state()

## Custom a-z sequence when [member flicker_preset] is CUSTOM_STRING ('a'=0%, 'm'=100%, 'z'=200%).
@export var custom_pattern: String = "mmnmmommommnonmmonqnmmo":
	set(value):
		custom_pattern = value
		_rebuild_pattern_cache()
		_update_process_state()

## Custom normalized waveform [Curve] (0..1) used when [member flicker_preset] is CUSTOM_CURVE.
@export var custom_curve: Curve = null:
	set(value):
		custom_curve = value
		_update_process_state()

## Playback rate in steps per second (Quake/Half-Life standard is 10.0 Hz).
@export_range(0.5, 60.0, 0.5) var flicker_fps: float = 10.0

## Smoothly interpolates energy between adjacent pattern characters instead of stepping.
@export var smooth_interpolation: bool = false

## Runs flicker animation inside the Godot 3D editor viewport when enabled.
@export var preview_in_editor: bool = false:
	set(value):
		preview_in_editor = value
		_update_process_state()

## Tracks whether the light is currently active.
var is_lit: bool = false

## Pre-computed energy scale ratios (0.0 to 2.0) for the active pattern string.
var _pattern_scales: PackedFloat32Array = PackedFloat32Array([1.0])

## Accumulated animation phase in pattern steps.
var _phase: float = 0.0

## Tracks whether the light is inside the camera frustum.
var _is_on_screen: bool = true

## Internal visibility notifier gating per-frame flicker math when off-screen.
var _notifier: VisibleOnScreenNotifier3D = null

## Child [PowerComponent] managing power counter thresholds.
@onready var power_component: PowerComponent = get_node_or_null("PowerComponent") as PowerComponent

## Child [SpotLight3D] rendering the illumination cone.
@onready var light: SpotLight3D = get_node_or_null("SpotLight3D") as SpotLight3D


## Connects power signals, builds culling notifier, and initializes light state.
func _ready() -> void:
	set_physics_process(false)
	_rebuild_pattern_cache()
	_sync_light_properties()

	if Engine.is_editor_hint():
		if is_instance_valid(light):
			light.visible = true
		_update_process_state()
		return

	assert(is_instance_valid(light), "PoweredLight3D: Missing SpotLight3D child.")
	assert(is_instance_valid(power_component), "PoweredLight3D: Missing PowerComponent child.")

	_setup_screen_notifier()

	power_component.required_power = required_power
	if not power_component.powered_on.is_connected(turn_on):
		power_component.powered_on.connect(turn_on)
	if not power_component.powered_off.is_connected(turn_off):
		power_component.powered_off.connect(turn_off)

	if start_on:
		turn_on()
	else:
		turn_off()


## Evaluates active Quake pattern or custom curve to modulate [SpotLight3D] energy.
func _process(delta: float) -> void:
	if not is_instance_valid(light):
		set_process(false)
		return

	_phase += delta * flicker_fps

	if flicker_preset == FlickerPreset.CUSTOM_CURVE and is_instance_valid(custom_curve):
		var u: float = fposmod(_phase * 0.1, 1.0)
		light.light_energy = base_energy * maxf(0.0, custom_curve.sample_baked(u))
		return

	var count: int = _pattern_scales.size()
	if count <= 1:
		light.light_energy = base_energy * (_pattern_scales[0] if count == 1 else 1.0)
		return

	var wrapped: float = fposmod(_phase, float(count))
	var idx_a: int = int(wrapped)
	var scale_a: float = _pattern_scales[idx_a]

	if smooth_interpolation:
		var idx_b: int = (idx_a + 1) % count
		var frac: float = wrapped - float(idx_a)
		var blended: float = lerpf(scale_a, _pattern_scales[idx_b], frac)
		light.light_energy = base_energy * blended
	else:
		light.light_energy = base_energy * scale_a


## Supplies 1 unit of power to the internal [PowerComponent].
func add_power() -> void:
	if is_instance_valid(power_component):
		power_component.add_power()


## Removes 1 unit of power from the internal [PowerComponent].
func remove_power() -> void:
	if is_instance_valid(power_component):
		power_component.remove_power()


## Directly activates the light and starts flicker processing if configured.
func turn_on() -> void:
	is_lit = true
	if is_instance_valid(light):
		light.visible = true
		light.light_energy = base_energy
	_phase = 0.0
	_update_process_state()
	powered_on.emit()
	print("PoweredLight3D: [", name, "] turned ON.")


## Directly deactivates the light and halts per-frame processing.
func turn_off() -> void:
	is_lit = false
	if is_instance_valid(light):
		light.visible = false
	_update_process_state()
	powered_off.emit()
	print("PoweredLight3D: [", name, "] turned OFF.")


## Toggles the light between on and off states.
func toggle() -> void:
	if is_lit:
		turn_off()
	else:
		turn_on()


## Changes the active [enum FlickerPreset] dynamically (callable from [EventSequencerDock]).
func set_flicker_preset(preset_idx: FlickerPreset) -> void:
	print("PoweredLight3D: [", name, "] preset changed to ", preset_idx)
	flicker_preset = preset_idx


## Applies exported appearance properties to the child [SpotLight3D].
func _sync_light_properties() -> void:
	var spot: SpotLight3D = (
		light if is_instance_valid(light) else get_node_or_null("SpotLight3D") as SpotLight3D
	)
	if not is_instance_valid(spot):
		return
	spot.light_color = light_color
	spot.light_energy = base_energy
	spot.light_indirect_energy = indirect_energy
	spot.light_volumetric_fog_energy = volumetric_fog_energy
	spot.spot_range = spot_range
	spot.spot_angle = spot_angle
	spot.shadow_enabled = shadows_enabled


## Converts the active pattern string ('a'..'z') into normalized float multipliers.
func _rebuild_pattern_cache() -> void:
	var raw_str: String = (
		custom_pattern
		if flicker_preset == FlickerPreset.CUSTOM_STRING
		else PRESET_PATTERNS.get(flicker_preset, "m")
	)
	if raw_str.is_empty():
		raw_str = "m"

	_pattern_scales.clear()
	for i: int in range(raw_str.length()):
		var code: int = clampi(raw_str.unicode_at(i), ASCII_A, 122)
		var mult: float = float(code - ASCII_A) / ASCII_M_OFFSET
		_pattern_scales.append(mult)


## Enables `_process` only when lit (or editor previewing), visible on screen, and animated.
func _update_process_state() -> void:
	if not is_inside_tree():
		return

	var is_animated: bool = false
	if flicker_preset == FlickerPreset.CUSTOM_CURVE:
		is_animated = is_instance_valid(custom_curve)
	else:
		is_animated = _pattern_scales.size() > 1

	if Engine.is_editor_hint():
		set_process(preview_in_editor and is_animated)
		if not preview_in_editor and is_instance_valid(light):
			light.light_energy = base_energy
		return

	var should_run: bool = is_lit and _is_on_screen and is_animated
	set_process(should_run)
	if is_lit and not is_animated and is_instance_valid(light):
		light.light_energy = (
			base_energy * (_pattern_scales[0] if _pattern_scales.size() > 0 else 1.0)
		)


## Creates a [VisibleOnScreenNotifier3D] bounding the spotlight range to gate `_process`.
func _setup_screen_notifier() -> void:
	_notifier = VisibleOnScreenNotifier3D.new()
	var box_size: Vector3 = Vector3.ONE * (spot_range * 2.0)
	_notifier.aabb = AABB(Vector3(-spot_range, -spot_range, -spot_range), box_size)
	_notifier.screen_entered.connect(_on_screen_entered)
	_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_notifier)


## Resumes flicker evaluation when entering the camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_update_process_state()


## Pauses flicker evaluation when leaving the camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_update_process_state()
