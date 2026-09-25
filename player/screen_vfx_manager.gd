## Manages full-screen post-processing overlays for rain, underwater submersion, and waterfalls.
##
## Controls shader parameters and transitions across screen-space [ColorRect] overlays.
class_name ScreenVFXManager
extends Node

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("VFX Overlays")

## Fullscreen [ColorRect] overlay displaying underwater tint and surface droplet wipes.
@export var screen_water_ui: ColorRect = null

## Fullscreen [ColorRect] overlay displaying dynamic rain droplets and camera wash.
@export var rain_drops_overlay: ColorRect = null

## Fullscreen [ColorRect] overlay displaying intense falling water sheets and blur.
@export var waterfall_overlay: ColorRect = null

# --------------------------------------
# VARIABLES
# --------------------------------------

## Indicates whether the player is currently inside a weather precipitation zone.
var in_rain_volume: bool = false

## Current interpolated opacity of camera lens rain droplets (0.0 to 1.0).
var current_drop_intensity: float = 0.0

## Current interpolated opacity of heavy upward rain wash streams (0.0 to 1.0).
var current_wash_intensity: float = 0.0

## Indicates whether the player is currently traversing a waterfall curtain.
var in_waterfall: bool = false

## Active tween driving screen water wipe clearing animations via [Utilities].
var water_clear_tween: Tween = null

## Active tween driving waterfall overlay fade-out animations via [Utilities].
var waterfall_clear_tween: Tween = null

## Cached isolated [ShaderMaterial] instance for rain droplet post-processing.
var rain_mat: ShaderMaterial = null

## Cached isolated [ShaderMaterial] instance for underwater distortion effects.
var water_mat: ShaderMaterial = null

## Cached isolated [ShaderMaterial] instance for waterfall impact overlay effects.
var waterfall_mat: ShaderMaterial = null


## Duplicates and isolates overlay materials to prevent shared resource mutation.
func _ready() -> void:
	print("ScreenVFXManager: _ready() - Initializing isolated overlay materials.")
	if is_instance_valid(waterfall_overlay) and waterfall_overlay.material:
		waterfall_mat = (waterfall_overlay.material.duplicate() as ShaderMaterial)
		waterfall_overlay.material = waterfall_mat

	if is_instance_valid(rain_drops_overlay) and rain_drops_overlay.material:
		rain_mat = (rain_drops_overlay.material.duplicate() as ShaderMaterial)
		rain_drops_overlay.material = rain_mat

	if is_instance_valid(screen_water_ui) and screen_water_ui.material:
		water_mat = screen_water_ui.material.duplicate() as ShaderMaterial
		screen_water_ui.material = water_mat


# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------


## Updates screen visual effects based on elapsed frame time and camera pitch.
## [param delta] Elapsed frame delta in seconds.
## [param camera_pitch] Camera vertical pitch angle in radians.
func process_vfx(delta: float, camera_pitch: float) -> void:
	_handle_rain_drops(delta, camera_pitch)


# --------------------------------------
# RAIN LOGIC
# --------------------------------------


## Sets whether player is inside rain volume and updates weather simulation flag.
## [param is_inside] True if entering rain, false otherwise.
func set_rain_volume(is_inside: bool) -> void:
	print("ScreenVFXManager: set_rain_volume() called. Player inside rain: ", is_inside)
	in_rain_volume = is_inside


## Computes droplet and wash intensities from camera pitch and updates shader.
## [param delta] Elapsed frame delta in seconds.
## [param camera_pitch] Camera vertical pitch angle in radians.
func _handle_rain_drops(delta: float, camera_pitch: float) -> void:
	if not is_instance_valid(rain_drops_overlay) or not is_instance_valid(rain_mat):
		return

	var target_drop: float = 0.0
	var target_wash: float = 0.0

	if in_rain_volume:
		if camera_pitch > -0.3 and camera_pitch < 0.6:
			if camera_pitch <= 0.1:
				target_drop = remap(camera_pitch, -0.3, 0.1, 0.0, 1.0)
			else:
				target_drop = remap(camera_pitch, 0.1, 0.6, 1.0, 0.0)

		if camera_pitch > 0.3:
			target_wash = remap(camera_pitch, 0.3, 1.2, 0.0, 1.0)

	target_drop = clampf(target_drop, 0.0, 1.0)
	target_wash = clampf(target_wash, 0.0, 1.0)

	current_drop_intensity = lerpf(current_drop_intensity, target_drop, delta * 4.0)
	current_wash_intensity = lerpf(current_wash_intensity, target_wash, delta * 2.5)

	if current_drop_intensity < 0.01 and current_wash_intensity < 0.01:
		if rain_drops_overlay.visible:
			print("ScreenVFXManager: Rain intensity low, hiding overlay.")
			rain_drops_overlay.hide()
	else:
		if not rain_drops_overlay.visible:
			print("ScreenVFXManager: Rain intensity active, showing overlay.")
			rain_drops_overlay.show()

		rain_mat.set_shader_parameter("drop_intensity", current_drop_intensity)
		rain_mat.set_shader_parameter("wash_intensity", current_wash_intensity)


# --------------------------------------
# UNDERWATER WIPE LOGIC
# --------------------------------------


## Updates screen overlay state when player submerges or leaves water volume.
## [param is_underwater] True if camera is submerged underwater.
func set_underwater_state(is_underwater: bool) -> void:
	print("ScreenVFXManager: set_underwater_state() called. Submerged: ", is_underwater)
	if not is_instance_valid(screen_water_ui) or not is_instance_valid(water_mat):
		return

	if is_underwater:
		if is_instance_valid(water_clear_tween) and water_clear_tween.is_valid():
			water_clear_tween.kill()
		water_clear_tween = null
		screen_water_ui.show()
		water_mat.set_shader_parameter("clear_progress", 0.0)


## Initiates multi-phase surface wipe tween when surfacing from water volume.
func trigger_surface_wipe() -> void:
	print("ScreenVFXManager: trigger_surface_wipe() executing screen wipe.")
	if not is_instance_valid(screen_water_ui) or not is_instance_valid(water_mat):
		return

	screen_water_ui.show()
	water_mat.set_shader_parameter("clear_progress", 0.0)
	water_mat.set_shader_parameter("drop_intensity", 0.8)
	water_mat.set_shader_parameter("wash_intensity", 0.5)

	water_clear_tween = Utilities.reset_tween(self, water_clear_tween)
	if not is_instance_valid(water_clear_tween):
		return

	(
		water_clear_tween
		. tween_property(water_mat, "shader_parameter/clear_progress", 0.65, 0.1)
		. set_trans(Tween.TRANS_SINE)
	)
	water_clear_tween.tween_interval(0.1)

	(
		water_clear_tween
		. tween_property(water_mat, "shader_parameter/clear_progress", 1.2, 0.2)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	(
		water_clear_tween
		. tween_property(water_mat, "shader_parameter/drop_intensity", 0.0, 1.0)
		. set_trans(Tween.TRANS_SINE)
	)
	(
		water_clear_tween
		. parallel()
		. tween_property(water_mat, "shader_parameter/wash_intensity", 0.0, 1.0)
		. set_trans(Tween.TRANS_SINE)
	)

	water_clear_tween.tween_callback(
		func() -> void:
			print("ScreenVFXManager: Surface wipe complete, hiding UI.")
			if is_instance_valid(screen_water_ui):
				screen_water_ui.hide()
	)


# --------------------------------------
# WATERFALL LOGIC
# --------------------------------------


## Displays waterfall screen overlay and prepares shader parameters.
func enter_waterfall() -> void:
	print("ScreenVFXManager: enter_waterfall() executed, showing overlay.")
	in_waterfall = true

	if not is_instance_valid(waterfall_overlay) or not is_instance_valid(waterfall_mat):
		return

	if is_instance_valid(waterfall_clear_tween) and waterfall_clear_tween.is_valid():
		waterfall_clear_tween.kill()
	waterfall_clear_tween = null

	waterfall_overlay.show()
	waterfall_mat.set_shader_parameter("clear_progress", 0.0)
	waterfall_mat.set_shader_parameter("wash_intensity", 1.0)
	waterfall_mat.set_shader_parameter("drop_intensity", 0.0)


## Initiates managed exit tween fading out waterfall wash and droplet overlays.
func exit_waterfall() -> void:
	print("ScreenVFXManager: exit_waterfall() executed, fading overlay out.")
	in_waterfall = false

	if not is_instance_valid(waterfall_overlay) or not is_instance_valid(waterfall_mat):
		return

	waterfall_mat.set_shader_parameter("drop_intensity", 1.0)

	waterfall_clear_tween = Utilities.reset_tween(self, waterfall_clear_tween)
	if not is_instance_valid(waterfall_clear_tween):
		return

	(
		waterfall_clear_tween
		. tween_property(waterfall_mat, "shader_parameter/clear_progress", 1.2, 0.4)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	(
		waterfall_clear_tween
		. parallel()
		. tween_property(waterfall_mat, "shader_parameter/wash_intensity", 0.0, 0.4)
		. set_trans(Tween.TRANS_SINE)
	)
	(
		waterfall_clear_tween
		. parallel()
		. tween_property(waterfall_mat, "shader_parameter/drop_intensity", 0.0, 1.2)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	waterfall_clear_tween.tween_callback(
		func() -> void:
			print("ScreenVFXManager: Waterfall fade complete, hiding overlay.")
			if is_instance_valid(waterfall_overlay):
				waterfall_overlay.hide()
	)
