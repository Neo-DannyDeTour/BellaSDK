## Manages all screen-space post-processing shaders, vignettes, and screen overlays.
class_name ScreenEffectsManager
extends Control

## ColorRect applying a vignette effect to the screen edges.
@onready var vignette: ColorRect = $Vignette

## ColorRect providing a red flash overlay when damage is taken.
@onready var pain_overlay: ColorRect = $PainOverlay

## ColorRect providing a green vignette pulse overlay when health is restored.
@onready var heal_vignette: ColorRect = $HealVignette

## ColorRect applying an electrical shock vignette effect.
@onready var electricity_vignette: ColorRect = $ElectricityVignette

## ColorRect applying a visual glitch shader effect.
@onready var glitch_overlay: ColorRect = $GlitchOverlay

## ColorRect applying a fisheye distortion effect when zooming.
@onready var fisheye_zoom: ColorRect = $FisheyeZoom

## ColorRect applying full-screen water distortion, wipe, and raindrops.
@onready var water_vfx_overlay: ColorRect = $WaterVFXOverlay

## The speed multiplier for vignette interpolation animations.
var ui_lerp_speed: float = 15.0

## Tracks if the player is crouching to adjust vignette intensity.
var is_player_crouching: bool = false

## Animates the red flash effect when the player takes damage.
var pain_tween: Tween

## Animates the green vignette effect when the player heals.
var heal_tween: Tween

## Controls the glitch effect animation when shocked.
var glitch_tween: Tween

## Controls the electricity vignette animation when shocked.
var electro_tween: Tween

## Target rain base intensity set by rain particle volumes.
var _target_rain_intensity: float = 0.0

## Current interpolated rain intensity factoring camera pitch and drying fade.
var _current_rain_intensity: float = 0.0

## Active tween handling smooth evaporation of raindrops on exiting rain.
var _rain_fade_tween: Tween

## Tracks whether the player is currently inside a waterfall stream.
var _is_waterfall_active: bool = false

## Tracks whether the player's camera is submerged underwater.
var _is_underwater_active: bool = false


## Initializes shader parameters and connects event listeners.
func _ready() -> void:
	print("ScreenEffectsManager: _ready() called. Initializing overlay materials.")
	_initialize_overlays()
	_connect_signals()


## Sets default shader parameter states and hides inactive visual overlays.
func _initialize_overlays() -> void:
	print("ScreenEffectsManager: _initialize_overlays() initializing default shader params.")
	if is_instance_valid(glitch_overlay) and glitch_overlay.material is ShaderMaterial:
		(glitch_overlay.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)
		glitch_overlay.hide()

	if is_instance_valid(electricity_vignette) and electricity_vignette.material is ShaderMaterial:
		(electricity_vignette.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)
		electricity_vignette.hide()

	if is_instance_valid(heal_vignette):
		if heal_vignette.material is ShaderMaterial:
			(heal_vignette.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)
		heal_vignette.hide()

	if is_instance_valid(pain_overlay):
		pain_overlay.hide()

	if is_instance_valid(water_vfx_overlay):
		water_vfx_overlay.hide()


## Safely binds overlay events from the global [Events] bus.
func _connect_signals() -> void:
	print("ScreenEffectsManager: Connecting global event bus signals.")
	if not Events.player_crouch_changed.is_connected(_on_player_crouched):
		Events.player_crouch_changed.connect(_on_player_crouched)
	if not Events.player_electrocuted.is_connected(_on_player_electrocuted):
		Events.player_electrocuted.connect(_on_player_electrocuted)
	if not Events.underwater_vfx_toggled.is_connected(_on_underwater_vfx_toggled):
		Events.underwater_vfx_toggled.connect(_on_underwater_vfx_toggled)
	if not Events.waterfall_vfx_toggled.is_connected(_on_waterfall_vfx_toggled):
		Events.waterfall_vfx_toggled.connect(_on_waterfall_vfx_toggled)
	if not Events.rain_vfx_toggled.is_connected(_on_rain_vfx_toggled):
		Events.rain_vfx_toggled.connect(_on_rain_vfx_toggled)


## Updates screen-space vignette transitions and rain pitch scaling every frame.
## [param delta] The elapsed time in seconds since the previous frame.
func _process(delta: float) -> void:
	if is_instance_valid(vignette) and vignette.material is ShaderMaterial:
		var target_vignette_opacity: float = 0.8 if is_player_crouching else 0.0
		var current_opacity: float = (
			(vignette.material as ShaderMaterial).get_shader_parameter("vignette_opacity") as float
		)
		var new_opacity: float = lerp(
			current_opacity, target_vignette_opacity, delta * ui_lerp_speed
		)
		(vignette.material as ShaderMaterial).set_shader_parameter("vignette_opacity", new_opacity)

	_process_rain_pitch_and_vfx(delta)


## Updates crouch state tracking to drive camera vignette lerping.
## [param crouching] True if the player is currently crouching.
func _on_player_crouched(crouching: bool) -> void:
	print("ScreenEffectsManager: Received crouch signal. Crouching: ", crouching)
	is_player_crouching = crouching


## Plays a red screen flash animation when the player sustains damage.
func trigger_pain_effect() -> void:
	print("ScreenEffectsManager: trigger_pain_effect() called. Flashing screen red.")
	if not is_instance_valid(pain_overlay):
		return

	pain_overlay.show()

	if pain_tween and pain_tween.is_valid():
		pain_tween.kill()

	pain_overlay.color = Color(1.0, 0.0, 0.0, 0.4)
	pain_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pain_tween.tween_property(pain_overlay, "color", Color(1.0, 0.0, 0.0, 0.0), 0.3)
	pain_tween.finished.connect(pain_overlay.hide)


## Plays a green vignette pulse animation when the player restores health.
func trigger_heal_effect() -> void:
	print("ScreenEffectsManager: trigger_heal_effect() called. Pulsing green heal vignette.")
	if not is_instance_valid(heal_vignette):
		return

	heal_vignette.show()

	if heal_tween and heal_tween.is_valid():
		heal_tween.kill()

	heal_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if heal_vignette.material is ShaderMaterial:
		heal_tween.tween_method(
			func(val: float) -> void:
				(heal_vignette.material as ShaderMaterial).set_shader_parameter("intensity", val)
				heal_vignette.queue_redraw(),
			0.8,
			0.0,
			0.4
		)
	else:
		heal_vignette.modulate = Color(0.0, 1.0, 0.2, 0.4)
		heal_tween.tween_property(heal_vignette, "modulate:a", 0.0, 0.4)

	heal_tween.finished.connect(heal_vignette.hide)


## Triggers glitch and electrical vignette shader pulses upon shock damage.
func _on_player_electrocuted() -> void:
	print("ScreenEffectsManager: _on_player_electrocuted() - Triggering electric FX.")
	if pain_tween and pain_tween.is_valid():
		pain_tween.kill()
	if is_instance_valid(pain_overlay):
		pain_overlay.hide()

	if is_instance_valid(glitch_overlay) and glitch_overlay.material is ShaderMaterial:
		glitch_overlay.show()
		if glitch_tween and glitch_tween.is_valid():
			glitch_tween.kill()

		glitch_tween = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		glitch_tween.tween_method(
			func(val: float) -> void:
				(glitch_overlay.material as ShaderMaterial).set_shader_parameter("intensity", val)
				glitch_overlay.queue_redraw(),
			0.6,
			0.0,
			0.4
		)
		glitch_tween.finished.connect(glitch_overlay.hide)

	if is_instance_valid(electricity_vignette) and electricity_vignette.material is ShaderMaterial:
		electricity_vignette.show()
		if electro_tween and electro_tween.is_valid():
			electro_tween.kill()

		electro_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		electro_tween.tween_method(
			func(val: float) -> void:
				(electricity_vignette.material as ShaderMaterial).set_shader_parameter(
					"intensity", val
				)
				electricity_vignette.queue_redraw(),
			1.0,
			0.0,
			0.5
		)
		electro_tween.finished.connect(electricity_vignette.hide)


## Updates unified water overlay parameters and handles automatic node visibility.
## [param mode] 0 = Basic Ripples/Droplets, 1 = Diagonal Wipe, 2 = Waterfall Flow.
## [param drops] Intensity for pop-in droplets (0.0 to 1.0).
## [param wash] Intensity for center rings/flowing water (0.0 to 1.0).
## [param clear_prog] Wipe progress across screen (0.0 to 1.5).
func set_water_vfx_state(mode: int, drops: float, wash: float, clear_prog: float = 0.0) -> void:
	print(
		"ScreenEffectsManager: Setting Water VFX mode -> ",
		mode,
		" drops -> ",
		drops,
		" wash -> ",
		wash,
		" wipe -> ",
		clear_prog
	)
	if not is_instance_valid(water_vfx_overlay):
		return

	var is_active: bool = false
	if mode == 2:
		is_active = (drops > 0.001 or wash > 0.001 or clear_prog < 1.49)
	else:
		is_active = (drops > 0.001 or wash > 0.001)

	water_vfx_overlay.visible = is_active

	if is_active and water_vfx_overlay.material is ShaderMaterial:
		var mat: ShaderMaterial = water_vfx_overlay.material as ShaderMaterial
		mat.set_shader_parameter(&"effect_mode", mode)
		mat.set_shader_parameter(&"drop_intensity", drops)
		mat.set_shader_parameter(&"wash_intensity", wash)
		mat.set_shader_parameter(&"clear_progress", clear_prog)
		water_vfx_overlay.queue_redraw()


## Modulates rain droplet intensity based on camera pitch angle and manages drying transitions.
## [param delta] The elapsed frame delta time in seconds.
func _process_rain_pitch_and_vfx(delta: float) -> void:
	if _is_underwater_active or _is_waterfall_active:
		return

	var pitch_factor: float = 1.0
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null

	if is_instance_valid(camera):
		var cam_forward: Vector3 = -camera.global_transform.basis.z
		var up_dot: float = cam_forward.dot(Vector3.UP)
		pitch_factor = clampf(remap(up_dot, -0.35, 0.75, 0.0, 1.8), 0.0, 2.0)

	var target_val: float = _target_rain_intensity * pitch_factor
	_current_rain_intensity = lerpf(_current_rain_intensity, target_val, delta * 6.0)

	if _current_rain_intensity > 0.001 or _target_rain_intensity > 0.001:
		set_water_vfx_state(0, _current_rain_intensity, 0.0, 1.5)
	elif is_instance_valid(water_vfx_overlay) and water_vfx_overlay.visible:
		set_water_vfx_state(0, 0.0, 0.0, 1.5)


## Handles underwater VFX state transitions emitted by WaterBody.
## [param is_submerged] Whether the camera is submerged.
## [param wash_intensity] Distortion strength for underwater refraction.
## [param drop_intensity] Droplet lens effect intensity.
## [param clear_prog] Wipe mask progress across the screen (0.0 to 1.5).
func _on_underwater_vfx_toggled(
	is_submerged: bool, wash_intensity: float, drop_intensity: float, clear_prog: float
) -> void:
	_is_underwater_active = is_submerged
	print(
		"ScreenEffectsManager: Underwater VFX -> Active: ",
		is_submerged,
		" Wash: ",
		wash_intensity,
		" Drops: ",
		drop_intensity,
		" Wipe: ",
		clear_prog
	)
	if is_submerged:
		set_water_vfx_state(0, drop_intensity, wash_intensity, clear_prog)
	else:
		set_water_vfx_state(0, 0.0, 0.0, 1.5)


## Handles waterfall screen wash and wipe transitions emitted by WaterfallStream.
## [param is_active] Whether the player is contacting or exiting the waterfall.
## [param wash_intensity] Flowing stream distortion strength.
## [param clear_prog] Wipe mask progress across the screen (0.0 to 1.5).
func _on_waterfall_vfx_toggled(is_active: bool, wash_intensity: float, clear_prog: float) -> void:
	_is_waterfall_active = is_active
	print("ScreenEffectsManager: Waterfall VFX -> Active: ", is_active, " Wipe: ", clear_prog)
	if is_active:
		set_water_vfx_state(2, 0.5, wash_intensity, clear_prog)
	else:
		set_water_vfx_state(2, 0.0, 0.0, 1.5)


## Handles screen rain droplet volume transitions and starts drying timer on exit.
## [param intensity] Rain droplet effect strength (0.0 to 1.0).
func _on_rain_vfx_toggled(intensity: float) -> void:
	print("ScreenEffectsManager: Rain VFX toggled -> Target intensity: ", intensity)
	if _rain_fade_tween and _rain_fade_tween.is_valid():
		_rain_fade_tween.kill()

	if intensity > 0.0:
		_target_rain_intensity = intensity
	else:
		_rain_fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_rain_fade_tween.tween_property(self, "_target_rain_intensity", 0.0, 2.8)
