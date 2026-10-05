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

## ColorRect applying full-screen canine dichromatic color and acuity filtering.
@onready var wolf_vision_overlay: ColorRect = $WolfVisionOverlay

## ColorRect applying full-screen fade transitions and color flashes.
@onready var fade_overlay: ColorRect = $FadeOverlay

## Animates smooth strength transitions when toggling wolf vision.
var wolf_vision_tween: Tween

## Active [Tween] animating full-screen fade and blink transitions.
var fade_tween: Tween

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

## Controls the fisheye zoom distortion animation when zooming.
var fisheye_tween: Tween

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

## Tracks whether the camera is currently playing the surfacing waterfall wipe.
var _is_surfacing_active: bool = false

## Cached shader material applied to the fullscreen transition overlay.
var _fade_material: ShaderMaterial = null


## Initializes layout, default shader states, and connects event listeners.
func _ready() -> void:
	print("ScreenEffectsManager: Initializing overlay materials.")
	_setup_fullscreen_layout()
	_initialize_overlays()
	_connect_signals()


## Enforces full-screen anchoring and click-through filtering on all overlay nodes.
func _setup_fullscreen_layout() -> void:
	print("ScreenEffectsManager: Enforcing full-screen rect anchors and mouse passthrough.")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var overlays: Array[Control] = [
		vignette,
		pain_overlay,
		heal_vignette,
		electricity_vignette,
		glitch_overlay,
		fisheye_zoom,
		water_vfx_overlay,
		wolf_vision_overlay,
		fade_overlay
	]

	for overlay: Control in overlays:
		if is_instance_valid(overlay):
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sets default shader parameter states and hides inactive visual overlays.
func _initialize_overlays() -> void:
	print("ScreenEffectsManager: Initializing default overlay parameters.")
	if is_instance_valid(vignette):
		if vignette.material is ShaderMaterial:
			(vignette.material as ShaderMaterial).set_shader_parameter(&"vignette_opacity", 0.0)
		vignette.hide()

	_ensure_fade_material()
	if is_instance_valid(fade_overlay):
		fade_overlay.modulate = Color.WHITE
		fade_overlay.hide()

	if is_instance_valid(glitch_overlay) and glitch_overlay.material is ShaderMaterial:
		(glitch_overlay.material as ShaderMaterial).set_shader_parameter(&"intensity", 0.0)
		glitch_overlay.hide()

	if is_instance_valid(electricity_vignette) and electricity_vignette.material is ShaderMaterial:
		var mat: ShaderMaterial = electricity_vignette.material as ShaderMaterial
		mat.set_shader_parameter(&"intensity", 0.0)
		electricity_vignette.hide()

	if is_instance_valid(heal_vignette):
		if heal_vignette.material is ShaderMaterial:
			(heal_vignette.material as ShaderMaterial).set_shader_parameter(&"intensity", 0.0)
		heal_vignette.hide()

	if is_instance_valid(fisheye_zoom) and fisheye_zoom.material is ShaderMaterial:
		(fisheye_zoom.material as ShaderMaterial).set_shader_parameter(&"effect_strength", 0.0)
		fisheye_zoom.hide()

	if is_instance_valid(pain_overlay):
		pain_overlay.hide()

	if is_instance_valid(water_vfx_overlay):
		water_vfx_overlay.hide()

	if is_instance_valid(wolf_vision_overlay):
		if wolf_vision_overlay.material is ShaderMaterial:
			var mat: ShaderMaterial = wolf_vision_overlay.material as ShaderMaterial
			mat.set_shader_parameter(&"effect_strength", 0.0)
		wolf_vision_overlay.hide()


## Verifies material presence and instantiates fallback transition shader.
func _ensure_fade_material() -> void:
	if not is_instance_valid(fade_overlay):
		return

	if is_instance_valid(fade_overlay.material) and fade_overlay.material is ShaderMaterial:
		_fade_material = fade_overlay.material as ShaderMaterial
		return

	const SHADER_PATH: String = "res://shaders/screen_transition.gdshader"
	if ResourceLoader.exists(SHADER_PATH):
		var shader: Shader = load(SHADER_PATH) as Shader
		if is_instance_valid(shader):
			_fade_material = ShaderMaterial.new()
			_fade_material.shader = shader
			fade_overlay.material = _fade_material
	else:
		push_warning("ScreenEffectsManager: Shader file not found at " + SHADER_PATH)


## Safely binds overlay events from the global [Events] bus.
func _connect_signals() -> void:
	print("ScreenEffectsManager: Connecting global event bus signals.")
	if not Events.player_crouch_changed.is_connected(_on_player_crouched):
		Events.player_crouch_changed.connect(_on_player_crouched)
	if not Events.player_electrocuted.is_connected(_on_player_electrocuted):
		Events.player_electrocuted.connect(_on_player_electrocuted)
	if not Events.player_zoomed.is_connected(_on_player_zoomed):
		Events.player_zoomed.connect(_on_player_zoomed)
	if not Events.underwater_vfx_toggled.is_connected(_on_underwater_vfx_toggled):
		Events.underwater_vfx_toggled.connect(_on_underwater_vfx_toggled)
	if not Events.waterfall_vfx_toggled.is_connected(_on_waterfall_vfx_toggled):
		Events.waterfall_vfx_toggled.connect(_on_waterfall_vfx_toggled)
	if not Events.rain_vfx_toggled.is_connected(_on_rain_vfx_toggled):
		Events.rain_vfx_toggled.connect(_on_rain_vfx_toggled)
	if Events.has_signal(&"screen_blackout_instant_requested"):
		Events.screen_blackout_instant_requested.connect(set_screen_black_instant)
	if Events.has_signal(&"screen_wake_up_requested"):
		Events.screen_wake_up_requested.connect(start_wake_up)
	if Events.has_signal(&"screen_fade_requested"):
		Events.screen_fade_requested.connect(_on_screen_fade_requested)


## Updates screen-space vignette transitions and rain pitch scaling every frame.
func _process(delta: float) -> void:
	if is_instance_valid(vignette) and vignette.material is ShaderMaterial:
		var target_vignette_opacity: float = 0.8 if is_player_crouching else 0.0
		var mat: ShaderMaterial = vignette.material as ShaderMaterial
		var current_opacity: float = mat.get_shader_parameter(&"vignette_opacity") as float
		var new_opacity: float = lerpf(
			current_opacity, target_vignette_opacity, delta * ui_lerp_speed
		)
		mat.set_shader_parameter(&"vignette_opacity", new_opacity)
		vignette.visible = new_opacity > 0.001

	_process_rain_pitch_and_vfx(delta)


## Updates crouch state tracking to drive camera vignette lerping.
func _on_player_crouched(crouching: bool) -> void:
	print("ScreenEffectsManager: Received crouch signal. Crouching: ", crouching)
	is_player_crouching = crouching


## Smoothly tweens the fisheye lens distortion when zooming in or out.
func _on_player_zoomed(is_zooming: bool) -> void:
	print("ScreenEffectsManager: _on_player_zoomed() received -> ", is_zooming)
	if not is_instance_valid(fisheye_zoom) or not (fisheye_zoom.material is ShaderMaterial):
		return

	if fisheye_tween and fisheye_tween.is_valid():
		fisheye_tween.kill()

	var mat: ShaderMaterial = fisheye_zoom.material as ShaderMaterial
	var target_strength: float = 1.0 if is_zooming else 0.0
	var current_strength: float = mat.get_shader_parameter(&"effect_strength") as float

	fisheye_zoom.show()
	fisheye_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fisheye_tween.tween_method(
		func(val: float) -> void:
			mat.set_shader_parameter(&"effect_strength", val)
			fisheye_zoom.queue_redraw(),
		current_strength,
		target_strength,
		0.35
	)

	if not is_zooming:
		fisheye_tween.finished.connect(
			func() -> void:
				if not is_zooming:
					fisheye_zoom.hide()
		)


## Plays a red screen flash animation when the player sustains damage.
func trigger_pain_effect() -> void:
	print("ScreenEffectsManager: trigger_pain_effect() called. Flashing screen red.")
	if not is_instance_valid(pain_overlay):
		return

	move_child(pain_overlay, get_child_count() - 1)
	pain_overlay.show()

	if pain_tween and pain_tween.is_valid():
		pain_tween.kill()

	pain_overlay.modulate = Color(1.0, 1.0, 1.0, 1.0)
	pain_overlay.color = Color(1.0, 0.0, 0.0, 0.45)

	pain_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pain_tween.tween_property(pain_overlay, "modulate:a", 0.0, 0.35)
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
				var mat: ShaderMaterial = heal_vignette.material as ShaderMaterial
				mat.set_shader_parameter(&"intensity", val)
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
				var mat: ShaderMaterial = glitch_overlay.material as ShaderMaterial
				mat.set_shader_parameter(&"intensity", val)
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
				var mat: ShaderMaterial = electricity_vignette.material as ShaderMaterial
				mat.set_shader_parameter(&"intensity", val)
				electricity_vignette.queue_redraw(),
			1.0,
			0.0,
			0.5
		)
		electro_tween.finished.connect(electricity_vignette.hide)


## Updates unified water overlay parameters and handles automatic node visibility.
func set_water_vfx_state(mode: int, drops: float, wash: float, clear_prog: float = 0.0) -> void:
	if not is_instance_valid(water_vfx_overlay):
		return

	var is_active: bool = drops > 0.001 or wash > 0.001 or clear_prog < 1.49
	water_vfx_overlay.visible = is_active

	if is_active and water_vfx_overlay.material is ShaderMaterial:
		var mat: ShaderMaterial = water_vfx_overlay.material as ShaderMaterial
		mat.set_shader_parameter(&"effect_mode", mode)
		mat.set_shader_parameter(&"drop_intensity", drops)
		mat.set_shader_parameter(&"wash_intensity", wash)
		mat.set_shader_parameter(&"clear_progress", clear_prog)
		water_vfx_overlay.queue_redraw()


## Modulates rain droplet intensity based on camera pitch angle and manages drying transitions.
func _process_rain_pitch_and_vfx(delta: float) -> void:
	if _is_underwater_active or _is_waterfall_active or _is_surfacing_active:
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


## Handles underwater and lingering droplet transitions emitted by WaterBody.
func _on_underwater_vfx_toggled(
	is_submerged: bool, wash_intensity: float, drop_intensity: float, clear_prog: float
) -> void:
	_is_underwater_active = is_submerged
	if is_submerged:
		_is_surfacing_active = false
		set_water_vfx_state(0, drop_intensity, wash_intensity, 0.0)
	else:
		if drop_intensity > 0.001:
			_is_surfacing_active = true
			set_water_vfx_state(0, drop_intensity, 0.0, clear_prog)
		else:
			_is_surfacing_active = false
			set_water_vfx_state(0, 0.0, 0.0, 1.5)


## Handles waterfall screen wash and wipe transitions emitted by WaterfallStream.
func _on_waterfall_vfx_toggled(is_active: bool, wash_intensity: float, clear_prog: float) -> void:
	_is_waterfall_active = is_active
	if is_active:
		set_water_vfx_state(2, 0.6, wash_intensity, clear_prog)
	else:
		set_water_vfx_state(2, 0.0, 0.0, 1.5)


## Handles screen rain droplet volume transitions and starts drying timer on exit.
func _on_rain_vfx_toggled(intensity: float) -> void:
	print("ScreenEffectsManager: Rain VFX toggled -> Target intensity: ", intensity)
	if _rain_fade_tween and _rain_fade_tween.is_valid():
		_rain_fade_tween.kill()

	if intensity > 0.0:
		_target_rain_intensity = intensity
	else:
		_rain_fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_rain_fade_tween.tween_property(self, "_target_rain_intensity", 0.0, 2.8)


## Smoothly blends canine dichromacy post-processing effect in and out.
func _on_wolf_vision_toggled(is_active: bool) -> void:
	print("ScreenEffectsManager: _on_wolf_vision_toggled() -> ", is_active)
	if not is_instance_valid(wolf_vision_overlay):
		return

	if not (wolf_vision_overlay.material is ShaderMaterial):
		wolf_vision_overlay.visible = is_active
		return

	if wolf_vision_tween and wolf_vision_tween.is_valid():
		wolf_vision_tween.kill()

	var mat: ShaderMaterial = wolf_vision_overlay.material as ShaderMaterial
	var current_strength: float = mat.get_shader_parameter(&"effect_strength") as float
	var target_strength: float = 1.0 if is_active else 0.0

	wolf_vision_overlay.show()
	wolf_vision_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	wolf_vision_tween.tween_method(
		func(val: float) -> void:
			mat.set_shader_parameter(&"effect_strength", val)
			wolf_vision_overlay.queue_redraw(),
		current_strength,
		target_strength,
		0.4
	)

	if not is_active:
		wolf_vision_tween.finished.connect(
			func() -> void:
				if not is_active:
					wolf_vision_overlay.hide()
		)


## Snaps overlay to solid color immediately with initial blur level.
func set_screen_black_instant(
	is_black: bool, blur: float = 0.0, color: Color = Color.BLACK
) -> void:
	print("ScreenEffectsManager: Setting instant screen blackout -> ", is_black)
	_ensure_fade_material()
	if not is_instance_valid(fade_overlay):
		return

	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	if is_black:
		fade_overlay.visible = true
		fade_overlay.modulate = Color.WHITE
		fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		if is_instance_valid(_fade_material):
			_fade_material.set_shader_parameter(&"fade_color", color)
			_fade_material.set_shader_parameter(&"fade_amount", 1.0)
			_fade_material.set_shader_parameter(&"blur_amount", blur)
			_fade_material.set_shader_parameter(&"blink_openness", 0.0)
		else:
			fade_overlay.color = color
			fade_overlay.modulate.a = 1.0
	else:
		if is_instance_valid(_fade_material):
			_fade_material.set_shader_parameter(&"fade_amount", 0.0)
			_fade_material.set_shader_parameter(&"blur_amount", 0.0)
			_fade_material.set_shader_parameter(&"blink_openness", 1.0)
		fade_overlay.hide()


## Visual wake-up sequence clearing blackness, revealing blur, and focusing.
func start_wake_up(
	fade_color: Color = Color.BLACK,
	eye_open_time: float = 2.0,
	max_blur: float = 2.5,
	blink_count: int = 3,
	blur_clear_time: float = 1.5
) -> void:
	print("ScreenEffectsManager: Starting phased wake-up transition.")
	_ensure_fade_material()
	if not is_instance_valid(fade_overlay):
		return

	fade_overlay.visible = true
	fade_overlay.modulate = Color.WHITE
	fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if is_instance_valid(_fade_material):
		_fade_material.set_shader_parameter(&"fade_color", fade_color)
		_fade_material.set_shader_parameter(&"fade_amount", 1.0)
		_fade_material.set_shader_parameter(&"blur_amount", max_blur)
		_fade_material.set_shader_parameter(&"blink_openness", 0.0)

	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	fade_tween = create_tween()

	# Phase 1: Dissolve black overlay and open eyelids while blur stays active
	(
		fade_tween
		. tween_method(_set_fade_amount, 1.0, 0.0, eye_open_time)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	if blink_count > 0:
		var single_blink: float = eye_open_time / float(blink_count)
		for i: int in range(blink_count):
			var delay: float = i * single_blink
			var half_step: float = single_blink * 0.5
			var target_openness: float = float(i + 1) / float(blink_count)
			(
				fade_tween
				. parallel()
				. tween_method(_set_blink_openness, 0.0, target_openness, half_step)
				. set_delay(delay)
				. set_trans(Tween.TRANS_SINE)
			)
			if i < blink_count - 1:
				(
					fade_tween
					. parallel()
					. tween_method(_set_blink_openness, target_openness, 0.0, half_step)
					. set_delay(delay + half_step)
					. set_trans(Tween.TRANS_SINE)
				)

	# Phase 2: Fade blurry surroundings back into sharp focus
	(
		fade_tween
		. tween_method(_set_blur_amount, max_blur, 0.0, blur_clear_time)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)

	fade_tween.tween_callback(_on_fade_finished)


## Updates screen fade uniform on transition overlay shader.
func _set_fade_amount(val: float) -> void:
	if is_instance_valid(_fade_material):
		_fade_material.set_shader_parameter(&"fade_amount", val)


## Updates screen blur uniform on transition overlay shader.
func _set_blur_amount(val: float) -> void:
	if is_instance_valid(_fade_material):
		_fade_material.set_shader_parameter(&"blur_amount", val)


## Updates eye blink openness uniform on transition overlay shader.
func _set_blink_openness(val: float) -> void:
	if is_instance_valid(_fade_material):
		_fade_material.set_shader_parameter(&"blink_openness", val)


## Executes screen fade sequences requested by triggers or console commands.
func _on_screen_fade_requested(
	fade_color: Color,
	fade_in_duration: float,
	hold_duration: float,
	fade_out_duration: float,
	use_blur: bool,
	max_blur: float,
	_use_blink: bool,
	_blink_count: int
) -> void:
	print("ScreenEffectsManager: _on_screen_fade_requested() called.")
	_ensure_fade_material()
	if not is_instance_valid(fade_overlay):
		return

	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	fade_overlay.show()
	fade_overlay.modulate = Color.WHITE

	if is_instance_valid(_fade_material):
		_fade_material.set_shader_parameter(&"fade_color", fade_color)
		_fade_material.set_shader_parameter(&"fade_amount", 0.0)
		_fade_material.set_shader_parameter(&"blur_amount", 0.0)
		_fade_material.set_shader_parameter(&"blink_openness", 1.0)

		fade_tween = create_tween()
		(
			fade_tween
			. tween_method(_set_fade_amount, 0.0, 1.0, fade_in_duration)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

		if use_blur:
			(
				fade_tween
				. parallel()
				. tween_method(_set_blur_amount, 0.0, max_blur, fade_in_duration)
				. set_trans(Tween.TRANS_SINE)
				. set_ease(Tween.EASE_IN_OUT)
			)

		fade_tween.tween_interval(hold_duration)

		(
			fade_tween
			. tween_method(_set_fade_amount, 1.0, 0.0, fade_out_duration)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

		if use_blur:
			(
				fade_tween
				. parallel()
				. tween_method(_set_blur_amount, max_blur, 0.0, fade_out_duration)
				. set_trans(Tween.TRANS_SINE)
				. set_ease(Tween.EASE_IN_OUT)
			)

		fade_tween.tween_callback(_on_fade_finished)
	else:
		fade_overlay.color = fade_color
		fade_overlay.modulate.a = 0.0
		fade_tween = create_tween()
		fade_tween.tween_property(fade_overlay, "modulate:a", 1.0, fade_in_duration)
		fade_tween.tween_interval(hold_duration)
		fade_tween.tween_property(fade_overlay, "modulate:a", 0.0, fade_out_duration)
		fade_tween.finished.connect(_on_fade_finished)


## Hides the fade overlay and resets modulate alpha when fade completes.
func _on_fade_finished() -> void:
	print("ScreenEffectsManager: Screen fade transition completed.")
	if is_instance_valid(fade_overlay):
		fade_overlay.hide()
