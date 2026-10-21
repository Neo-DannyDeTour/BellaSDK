## Manages all screen-space post-processing shaders, vignettes, and screen overlays.
class_name ScreenEffectsManager
extends Control

## Pre-allocated [StringName] uniform for full-lens steam condensation flash.
const PARAM_FULL_LENS_FOG: StringName = &"full_lens_fog"

## Pre-allocated [StringName] uniform for persistent lens-edge condensation rim.
const PARAM_EDGE_CONDENSATION: StringName = &"edge_condensation"

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

## Target proximity electricity vignette intensity set by nearby energy fields.
var _target_electricity_intensity: float = 0.0

## Current interpolated proximity electricity vignette intensity.
var _current_electricity_intensity: float = 0.0

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

## Reference count of active volumetric smoke clouds currently affecting the player.
var _active_smoke_count: int = 0

## Active [Tween] animating glasses condensation entry flash and exit evaporation.
var _condensation_tween: Tween

## Current interpolated full-lens steam fog value [0.0, 1.0].
var _current_full_fog: float = 0.0

## Current interpolated lens-edge condensation value [0.0, 1.0].
var _current_edge_condensation: float = 0.0

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

## ColorRect applying full-screen water distortion and ambient raindrops.
@onready var water_vfx_overlay: ColorRect = $WaterVFXOverlay

## Dedicated controller node applying the Dishonored-style meniscus water sheet wipe.
@onready var water_wipe_overlay: WaterWipeController = (
	get_node_or_null("WaterWipeOverlay") as WaterWipeController
)

## ColorRect applying full-screen canine dichromatic color and acuity filtering.
@onready var wolf_vision_overlay: ColorRect = $WolfVisionOverlay

## ColorRect applying Bella's glasses steam/smoke condensation effect.
@onready var condensation_overlay: ColorRect = get_node_or_null("CondensationOverlay") as ColorRect

## ColorRect applying full-screen fade transitions and color flashes.
@onready var fade_overlay: ColorRect = $FadeOverlay


## Initializes layout, default shader states, and connects event listeners.
func _ready() -> void:
	print("ScreenEffectsManager: Initializing overlay materials.")
	_setup_fullscreen_layout()
	_initialize_overlays()
	_connect_signals()
	set_process(false)


## Disconnects global event bus signals and kills active tweens on tree exit.
func _exit_tree() -> void:
	if is_instance_valid(_condensation_tween):
		_condensation_tween.kill()
	if Events.smoke_hazard_changed.is_connected(_on_smoke_hazard_changed):
		Events.smoke_hazard_changed.disconnect(_on_smoke_hazard_changed)
	if Events.smoke_exposure_changed.is_connected(_on_smoke_exposure_changed):
		Events.smoke_exposure_changed.disconnect(_on_smoke_exposure_changed)


## Updates screen-space vignette transitions and rain pitch scaling when active.
func _process(delta: float) -> void:
	var has_active_vignette: bool = false
	if is_instance_valid(vignette) and vignette.material is ShaderMaterial:
		var target_vignette_opacity: float = 0.8 if is_player_crouching else 0.0
		var mat: ShaderMaterial = vignette.material as ShaderMaterial
		var current_opacity: float = type_convert(
			mat.get_shader_parameter(&"vignette_opacity"), TYPE_FLOAT
		)
		var new_opacity: float = lerpf(
			current_opacity, target_vignette_opacity, delta * ui_lerp_speed
		)
		mat.set_shader_parameter(&"vignette_opacity", new_opacity)
		vignette.visible = new_opacity > 0.001
		has_active_vignette = is_player_crouching or vignette.visible

	_process_proximity_electricity(delta)
	_process_rain_pitch_and_vfx(delta)

	var has_active_electricity: bool = (
		_target_electricity_intensity > 0.001 or _current_electricity_intensity > 0.001
	)
	var has_active_rain: bool = _target_rain_intensity > 0.001 or _current_rain_intensity > 0.001
	if not has_active_vignette and not has_active_electricity and not has_active_rain:
		set_process(false)


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
		water_wipe_overlay,
		wolf_vision_overlay,
		condensation_overlay,
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

	if is_instance_valid(condensation_overlay):
		if condensation_overlay.material is ShaderMaterial:
			var cnd_mat: ShaderMaterial = condensation_overlay.material as ShaderMaterial
			cnd_mat.set_shader_parameter(PARAM_FULL_LENS_FOG, 0.0)
			cnd_mat.set_shader_parameter(PARAM_EDGE_CONDENSATION, 0.0)
		condensation_overlay.hide()


## Verifies material presence and instantiates fallback transition shader.
func _ensure_fade_material() -> void:
	if not is_instance_valid(fade_overlay):
		return

	if is_instance_valid(fade_overlay.material) and fade_overlay.material is ShaderMaterial:
		_fade_material = fade_overlay.material as ShaderMaterial
		return

	const SHADER_PATH: String = "res://shaders/screen_transition.gdshader"
	if ResourceLoader.exists(SHADER_PATH):
		var loaded_res: Resource = load(SHADER_PATH)
		var shader: Shader = loaded_res as Shader
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
	if Events.has_signal(&"electricity_vignette_changed"):
		if not Events.electricity_vignette_changed.is_connected(_on_electricity_vignette_changed):
			Events.electricity_vignette_changed.connect(_on_electricity_vignette_changed)
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
	if Events.has_signal(&"wolf_vision_toggled"):
		if not Events.wolf_vision_toggled.is_connected(_on_wolf_vision_toggled):
			Events.wolf_vision_toggled.connect(_on_wolf_vision_toggled)
	if not Events.smoke_hazard_changed.is_connected(_on_smoke_hazard_changed):
		Events.smoke_hazard_changed.connect(_on_smoke_hazard_changed)
	if not Events.smoke_exposure_changed.is_connected(_on_smoke_exposure_changed):
		Events.smoke_exposure_changed.connect(_on_smoke_exposure_changed)


## Updates crouch state tracking to drive camera vignette lerping.
func _on_player_crouched(crouching: bool) -> void:
	print("ScreenEffectsManager: Received crouch signal. Crouching: ", crouching)
	is_player_crouching = crouching
	set_process(true)


## Smoothly tweens the fisheye lens distortion when zooming in or out.
func _on_player_zoomed(is_zooming: bool) -> void:
	print("ScreenEffectsManager: _on_player_zoomed() received -> ", is_zooming)
	if not is_instance_valid(fisheye_zoom) or not (fisheye_zoom.material is ShaderMaterial):
		return

	if fisheye_tween and fisheye_tween.is_valid():
		fisheye_tween.kill()

	var mat: ShaderMaterial = fisheye_zoom.material as ShaderMaterial
	var target_strength: float = 1.0 if is_zooming else 0.0
	var current_strength: float = type_convert(
		mat.get_shader_parameter(&"effect_strength"), TYPE_FLOAT
	)

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


## Modulates rain droplet intensity and storm wash based on camera pitch and storm strength.
func _process_rain_pitch_and_vfx(delta: float) -> void:
	if _is_underwater_active or _is_waterfall_active or _is_surfacing_active:
		return

	var pitch_factor: float = 1.0
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if is_instance_valid(viewport) else null

	# Swirling storms (>0.85 intensity) whip droplets into eyes even when looking slightly down
	var storm_floor: float = clampf(
		remap(_target_rain_intensity, 0.8, 1.35, 0.35, 0.85), 0.35, 0.85
	)
	if is_instance_valid(camera):
		var cam_forward: Vector3 = -camera.global_transform.basis.z
		var up_dot: float = cam_forward.dot(Vector3.UP)
		pitch_factor = clampf(remap(up_dot, -0.55, 0.65, storm_floor, 1.85), storm_floor, 2.0)

	var target_val: float = _target_rain_intensity * pitch_factor
	_current_rain_intensity = lerpf(_current_rain_intensity, target_val, delta * 6.0)

	if _current_rain_intensity > 0.001 or _target_rain_intensity > 0.001:
		var storm_wash: float = clampf((_current_rain_intensity - 0.85) * 0.45, 0.0, 0.35)
		set_water_vfx_state(0, _current_rain_intensity, storm_wash, 1.5)
	elif is_instance_valid(water_vfx_overlay) and water_vfx_overlay.visible:
		set_water_vfx_state(0, 0.0, 0.0, 1.5)


## Handles continuous underwater distortion emitted by WaterBody.
func _on_underwater_vfx_toggled(
	is_submerged: bool, wash_intensity: float, drop_intensity: float, _clear_prog: float
) -> void:
	_is_underwater_active = is_submerged
	_is_surfacing_active = false
	if is_submerged:
		set_water_vfx_state(0, drop_intensity, wash_intensity, 0.0)
	else:
		set_water_vfx_state(0, 0.0, 0.0, 1.5)


## Tracks waterfall active state to pause ambient rain while WaterWipeController handles wash.
func _on_waterfall_vfx_toggled(is_active: bool, _wash_intensity: float, _clear_prog: float) -> void:
	_is_waterfall_active = is_active
	if is_active:
		set_water_vfx_state(0, 0.0, 0.0, 1.5)


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
	set_process(true)


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
	var current_strength: float = type_convert(
		mat.get_shader_parameter(&"effect_strength"), TYPE_FLOAT
	)
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


## Smoothly interpolates the electricity vignette when near an energy gate.
func _process_proximity_electricity(delta: float) -> void:
	if electro_tween and electro_tween.is_valid() and electro_tween.is_running():
		return
	if not is_instance_valid(electricity_vignette):
		return
	if not (electricity_vignette.material is ShaderMaterial):
		return

	_current_electricity_intensity = lerpf(
		_current_electricity_intensity, _target_electricity_intensity, delta * 10.0
	)
	var mat: ShaderMaterial = electricity_vignette.material as ShaderMaterial
	if _current_electricity_intensity > 0.001:
		electricity_vignette.show()
		mat.set_shader_parameter(&"intensity", _current_electricity_intensity)
		electricity_vignette.queue_redraw()
	elif electricity_vignette.visible:
		mat.set_shader_parameter(&"intensity", 0.0)
		electricity_vignette.hide()


## Updates target electricity vignette intensity when approaching an energy field.
func _on_electricity_vignette_changed(intensity: float) -> void:
	print("ScreenEffectsManager: Proximity electricity intensity -> ", intensity)
	_target_electricity_intensity = clampf(intensity, 0.0, 1.0)
	set_process(true)


## Choreographs Bella's glasses condensation: 1.0s full-lens flash on entry,
## persistent rim fog while inside, and 1.5s evaporation when exiting all clouds.
func _on_smoke_hazard_changed(is_inside: bool, density: float) -> void:
	if not is_instance_valid(condensation_overlay):
		return

	if is_inside:
		var was_outside: bool = _active_smoke_count == 0
		_active_smoke_count += 1
		var target_edge: float = clampf(maxf(density, 0.5), 0.45, 1.0)

		condensation_overlay.show()
		if was_outside:
			print("ScreenEffectsManager: Triggering full-lens glasses condensation flash.")
			if is_instance_valid(_condensation_tween):
				_condensation_tween.kill()

			_set_full_lens_fog(1.0)
			_set_edge_condensation(maxf(_current_edge_condensation, 0.72))

			_condensation_tween = create_tween().set_parallel(true)
			(
				_condensation_tween
				. tween_method(_set_full_lens_fog, 1.0, 0.0, 1.0)
				. set_trans(Tween.TRANS_CUBIC)
				. set_ease(Tween.EASE_OUT)
			)
			(
				_condensation_tween
				. tween_method(_set_edge_condensation, _current_edge_condensation, target_edge, 0.6)
				. set_trans(Tween.TRANS_SINE)
				. set_ease(Tween.EASE_OUT)
			)
		else:
			_set_edge_condensation(maxf(_current_edge_condensation, target_edge))
	else:
		_active_smoke_count = maxi(0, _active_smoke_count - 1)
		if _active_smoke_count == 0:
			print("ScreenEffectsManager: Evaporating glasses condensation on smoke exit.")
			if is_instance_valid(_condensation_tween):
				_condensation_tween.kill()

			_condensation_tween = create_tween().set_parallel(true)
			(
				_condensation_tween
				. tween_method(_set_full_lens_fog, _current_full_fog, 0.0, 0.8)
				. set_trans(Tween.TRANS_SINE)
				. set_ease(Tween.EASE_OUT)
			)
			(
				_condensation_tween
				. tween_method(_set_edge_condensation, _current_edge_condensation, 0.0, 1.5)
				. set_trans(Tween.TRANS_SINE)
				. set_ease(Tween.EASE_IN_OUT)
			)
			_condensation_tween.chain().tween_callback(_on_condensation_evaporated)


## Adjusts persistent lens-edge condensation intensity as smoke exposure builds.
func _on_smoke_exposure_changed(exposure: float) -> void:
	if _active_smoke_count <= 0 or not is_instance_valid(condensation_overlay):
		return
	var target_edge: float = clampf(0.45 + exposure * 0.55, 0.45, 1.0)
	_set_edge_condensation(lerpf(_current_edge_condensation, target_edge, 0.35))


## Updates the full-lens condensation uniform on [member condensation_overlay].
func _set_full_lens_fog(val: float) -> void:
	_current_full_fog = clampf(val, 0.0, 1.0)
	if is_instance_valid(condensation_overlay) and condensation_overlay.material is ShaderMaterial:
		var mat: ShaderMaterial = condensation_overlay.material as ShaderMaterial
		mat.set_shader_parameter(PARAM_FULL_LENS_FOG, _current_full_fog)
		condensation_overlay.queue_redraw()


## Updates the lens-edge condensation uniform on [member condensation_overlay].
func _set_edge_condensation(val: float) -> void:
	_current_edge_condensation = clampf(val, 0.0, 1.0)
	if is_instance_valid(condensation_overlay) and condensation_overlay.material is ShaderMaterial:
		var mat: ShaderMaterial = condensation_overlay.material as ShaderMaterial
		mat.set_shader_parameter(PARAM_EDGE_CONDENSATION, _current_edge_condensation)
		condensation_overlay.queue_redraw()


## Hides the condensation overlay once exit evaporation completes.
func _on_condensation_evaporated() -> void:
	if _active_smoke_count == 0 and is_instance_valid(condensation_overlay):
		condensation_overlay.hide()
