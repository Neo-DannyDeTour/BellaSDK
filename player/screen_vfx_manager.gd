## Manages full-screen post-processing overlays related to environmental hazards.
##
## [ScreenVFXManager] orchestrates shaders applied to [ColorRect] UI nodes
## (e.g., raindrops, waterfall splashes, and underwater transitions) and modulates
## their intensity based on player state and camera pitch.
class_name ScreenVFXManager
extends Node

@export_category("VFX Overlays")
## The overlay used to render underwater distortion and surface wiping.
@export var screen_water_ui: ColorRect
## The overlay used for screen-space raindrops when looking up in rain volumes.
@export var rain_drops_overlay: ColorRect
## The overlay used for heavy distortion when standing inside a waterfall.
@export var waterfall_overlay: ColorRect

## True if the player is currently inside a registered rain volume.
var in_rain_volume: bool = false
## The interpolated intensity of individual screen raindrops.
var current_drop_intensity: float = 0.0
## The interpolated intensity of the heavy sheet-water wash effect.
var current_wash_intensity: float = 0.0
## True if the player's head is directly inside a waterfall area.
var in_waterfall: bool = false

## Tween reference for the underwater surface wipe animation.
var water_clear_tween: Tween
## Tween reference for the waterfall exit clearing animation.
var waterfall_clear_tween: Tween

## Cached reference to the cloned raindrop material.
var rain_mat: ShaderMaterial
## Cached reference to the cloned underwater material.
var water_mat: ShaderMaterial
## Cached reference to the cloned waterfall material.
var waterfall_mat: ShaderMaterial


## Clones the materials to ensure unique shader instances and hides overlays.
func _ready() -> void:
	# 1. Added missing print() for initialization

	# Force Godot to give each overlay its own isolated Material in memory
	# and cache them strictly to avoid casting during process loops.
	if waterfall_overlay and waterfall_overlay.material:
		waterfall_mat = waterfall_overlay.material.duplicate() as ShaderMaterial
		waterfall_overlay.material = waterfall_mat

	if rain_drops_overlay and rain_drops_overlay.material:
		rain_mat = rain_drops_overlay.material.duplicate() as ShaderMaterial
		rain_drops_overlay.material = rain_mat

	if screen_water_ui and screen_water_ui.material:
		water_mat = screen_water_ui.material.duplicate() as ShaderMaterial
		screen_water_ui.material = water_mat


## Called every frame by the player controller to process dynamic VFX values.
## [param delta] Time elapsed since the previous physics frame.
## [param camera_pitch] The current vertical rotation (pitch) of the player's camera.
func process_vfx(delta: float, camera_pitch: float) -> void:
	_handle_rain_drops(delta, camera_pitch)


## Flags the player as being inside or outside a rain volume.
## [param is_inside] True if entering, false if exiting.
func set_rain_volume(is_inside: bool) -> void:
	print("ScreenVFXManager: set_rain_volume() called. Player inside rain volume: ", is_inside)
	in_rain_volume = is_inside


## Modulates raindrop density based on how steeply the player is looking up into the rain.
## [param delta] Engine frame physics delta.
## [param camera_pitch] Vertical rotation of the camera in radians.
func _handle_rain_drops(delta: float, camera_pitch: float) -> void:
	if not rain_drops_overlay or not rain_mat:
		return

	var target_drop: float = 0.0
	var target_wash: float = 0.0

	if in_rain_volume:
		# (Negative pitch is DOWN, Positive pitch is UP)
		# 1. STANDARD DROPS (Fades in looking straight, fades out looking up/down)
		if camera_pitch > -0.3 and camera_pitch < 0.6:
			if camera_pitch <= 0.1:
				target_drop = remap(camera_pitch, -0.3, 0.1, 0.0, 1.0)
			else:
				target_drop = remap(camera_pitch, 0.1, 0.6, 1.0, 0.0)

		# 2. HEAVY WASH (Only happens when looking UP)
		if camera_pitch > 0.3:
			target_wash = remap(camera_pitch, 0.3, 1.2, 0.0, 1.0)

	target_drop = clampf(target_drop, 0.0, 1.0)
	target_wash = clampf(target_wash, 0.0, 1.0)

	current_drop_intensity = lerpf(current_drop_intensity, target_drop, delta * 4.0)
	current_wash_intensity = lerpf(current_wash_intensity, target_wash, delta * 2.5)

	if current_drop_intensity < 0.01 and current_wash_intensity < 0.01:
		if rain_drops_overlay.visible:
			# 2. Added missing print() for state change
			print("ScreenVFXManager: Rain intensity low, hiding overlay.")
			rain_drops_overlay.hide()
	else:
		if not rain_drops_overlay.visible:
			# 3. Added missing print() for state change
			print("ScreenVFXManager: Rain intensity active, showing overlay.")
			rain_drops_overlay.show()

		rain_mat.set_shader_parameter("drop_intensity", current_drop_intensity)
		rain_mat.set_shader_parameter("wash_intensity", current_wash_intensity)


## Enables or disables the underwater post-processing filter.
## [param is_underwater] True if the player's camera is submerged.
func set_underwater_state(is_underwater: bool) -> void:
	print("ScreenVFXManager: set_underwater_state() called. Player submerged: ", is_underwater)
	if not screen_water_ui or not water_mat:
		return

	if is_underwater:
		if water_clear_tween and water_clear_tween.is_valid():
			water_clear_tween.kill()
		screen_water_ui.show()
		water_mat.set_shader_parameter("clear_progress", 0.0)


## Initiates the screen-wiper animation used when emerging from water.
func trigger_surface_wipe() -> void:
	print("ScreenVFXManager: trigger_surface_wipe() executing screen clearing tween.")
	if not screen_water_ui or not water_mat:
		return

	screen_water_ui.show()
	water_mat.set_shader_parameter("clear_progress", 0.0)
	water_mat.set_shader_parameter("drop_intensity", 0.8)
	water_mat.set_shader_parameter("wash_intensity", 0.5)

	if water_clear_tween and water_clear_tween.is_valid():
		water_clear_tween.kill()

	water_clear_tween = create_tween()

	# Phase 1 & 2: Rapid wipe to 65%, then hold
	(
		water_clear_tween
		. tween_property(water_mat, "shader_parameter/clear_progress", 0.65, 0.1)
		. set_trans(Tween.TRANS_SINE)
	)
	water_clear_tween.tween_interval(0.1)

	# Phase 3: Finish sweep
	(
		water_clear_tween
		. tween_property(water_mat, "shader_parameter/clear_progress", 1.2, 0.2)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	# Phase 4: Fade droplets
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

	# Phase 5: Hide
	# 4. Added missing print() utilizing an anonymous function for the callback
	water_clear_tween.tween_callback(
		func() -> void:
			print("ScreenVFXManager: Surface wipe complete, hiding UI.")
			screen_water_ui.hide()
	)


## Instantly applies maximum distortion and wash when entering a waterfall.
func enter_waterfall() -> void:
	print("ScreenVFXManager: enter_waterfall() executed, triggering overlay tweens.")
	in_waterfall = true

	if not waterfall_overlay or not waterfall_mat:
		return

	if waterfall_clear_tween and waterfall_clear_tween.is_valid():
		waterfall_clear_tween.kill()

	waterfall_overlay.show()
	waterfall_mat.set_shader_parameter("clear_progress", 0.0)
	waterfall_mat.set_shader_parameter("wash_intensity", 1.0)
	waterfall_mat.set_shader_parameter("drop_intensity", 0.0)


## Begins the clearing and fading animation upon exiting a waterfall.
func exit_waterfall() -> void:
	print("ScreenVFXManager: exit_waterfall() executed, fading overlay out.")
	in_waterfall = false

	if not waterfall_overlay or not waterfall_mat:
		return

	if waterfall_clear_tween and waterfall_clear_tween.is_valid():
		waterfall_clear_tween.kill()

	waterfall_mat.set_shader_parameter("drop_intensity", 1.0)

	waterfall_clear_tween = create_tween()
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
	waterfall_clear_tween.tween_callback(waterfall_overlay.hide)
