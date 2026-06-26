class_name ScreenVFXManager
extends Node

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("VFX Overlays")
@export var screen_water_ui: ColorRect
@export var rain_drops_overlay: ColorRect
@export var waterfall_overlay: ColorRect

# --------------------------------------
# VARIABLES
# --------------------------------------
var in_rain_volume: bool = false
var current_drop_intensity: float = 0.0
var current_wash_intensity: float = 0.0

var in_waterfall: bool = false

var water_clear_tween: Tween
var waterfall_clear_tween: Tween

# Cached Materials for performance
var rain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var waterfall_mat: ShaderMaterial


func _ready() -> void:
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


# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------
func process_vfx(delta: float, camera_pitch: float) -> void:
	_handle_rain_drops(delta, camera_pitch)


# --------------------------------------
# RAIN LOGIC
# --------------------------------------
func set_rain_volume(is_inside: bool) -> void:
	print("ScreenVFXManager: set_rain_volume() called. Player inside rain volume: ", is_inside)
	in_rain_volume = is_inside


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
			rain_drops_overlay.hide()
	else:
		if not rain_drops_overlay.visible:
			rain_drops_overlay.show()

		rain_mat.set_shader_parameter("drop_intensity", current_drop_intensity)
		rain_mat.set_shader_parameter("wash_intensity", current_wash_intensity)


# --------------------------------------
# UNDERWATER WIPE LOGIC
# --------------------------------------
func set_underwater_state(is_underwater: bool) -> void:
	print("ScreenVFXManager: set_underwater_state() called. Player submerged: ", is_underwater)
	if not screen_water_ui or not water_mat:
		return

	if is_underwater:
		if water_clear_tween and water_clear_tween.is_valid():
			water_clear_tween.kill()
		screen_water_ui.show()
		water_mat.set_shader_parameter("clear_progress", 0.0)


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
	water_clear_tween.tween_callback(screen_water_ui.hide)


# --------------------------------------
# WATERFALL LOGIC
# --------------------------------------
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

#class_name ScreenVFXManager
#extends Node
#
## --------------------------------------
## EXPORTS
## --------------------------------------
#@export_category("VFX Overlays")
#@export var screen_water_ui: ColorRect
#@export var rain_drops_overlay: ColorRect
#@export var waterfall_overlay: ColorRect
#
## --------------------------------------
## VARIABLES
## --------------------------------------
#var in_rain_volume: bool = false
#var current_drop_intensity: float = 0.0
#var current_wash_intensity: float = 0.0
#
#var in_waterfall: bool = false
#
#var water_clear_tween: Tween
#var waterfall_clear_tween: Tween
#
#
#func _ready() -> void:
## Force Godot to give each overlay its own isolated Material in memory
## This prevents changing one shader from accidentally changing another
#if waterfall_overlay and waterfall_overlay.material:
#waterfall_overlay.material = waterfall_overlay.material.duplicate()
#
#if rain_drops_overlay and rain_drops_overlay.material:
#rain_drops_overlay.material = rain_drops_overlay.material.duplicate()
#
#if screen_water_ui and screen_water_ui.material:
#screen_water_ui.material = screen_water_ui.material.duplicate()
#
#
## --------------------------------------
## CORE PROCESS LOGIC
## --------------------------------------
#func process_vfx(delta: float, camera_pitch: float) -> void:
#_handle_rain_drops(delta, camera_pitch)
#
#
## --------------------------------------
## RAIN LOGIC
## --------------------------------------
#func set_rain_volume(is_inside: bool) -> void:
#in_rain_volume = is_inside
#
#
#func _handle_rain_drops(delta: float, camera_pitch: float) -> void:
#if not screen_water_ui or not rain_drops_overlay or not rain_drops_overlay.material:
#return
#
#var target_drop: float = 0.0
#var target_wash: float = 0.0
#
#if in_rain_volume:
## (Negative pitch is DOWN, Positive pitch is UP)
## 1. STANDARD DROPS (Fades in looking straight, fades out looking up/down)
#if camera_pitch > -0.3 and camera_pitch < 0.6:
#if camera_pitch <= 0.1:
#target_drop = remap(camera_pitch, -0.3, 0.1, 0.0, 1.0)
#else:
#target_drop = remap(camera_pitch, 0.1, 0.6, 1.0, 0.0)
#
## 2. HEAVY WASH (Only happens when looking UP)
#if camera_pitch > 0.3:
#target_wash = remap(camera_pitch, 0.3, 1.2, 0.0, 1.0)
#
#target_drop = clampf(target_drop, 0.0, 1.0)
#target_wash = clampf(target_wash, 0.0, 1.0)
#
#current_drop_intensity = lerpf(current_drop_intensity, target_drop, delta * 4.0)
#current_wash_intensity = lerpf(current_wash_intensity, target_wash, delta * 2.5)
#
#if current_drop_intensity < 0.01 and current_wash_intensity < 0.01:
#rain_drops_overlay.hide()
#else:
#rain_drops_overlay.show()
#var mat: ShaderMaterial = rain_drops_overlay.material as ShaderMaterial
#mat.set_shader_parameter("drop_intensity", current_drop_intensity)
#mat.set_shader_parameter("wash_intensity", current_wash_intensity)
#
#
## --------------------------------------
## UNDERWATER WIPE LOGIC
## --------------------------------------
#func set_underwater_state(is_underwater: bool) -> void:
#if not screen_water_ui:
#return
#
#var mat: ShaderMaterial = screen_water_ui.material as ShaderMaterial
#if not mat:
#return
#
#if is_underwater:
#if water_clear_tween and water_clear_tween.is_valid():
#water_clear_tween.kill()
#screen_water_ui.show()
#mat.set_shader_parameter("clear_progress", 0.0)
#
#
#func trigger_surface_wipe() -> void:
#if not screen_water_ui:
#return
#
#var mat: ShaderMaterial = screen_water_ui.material as ShaderMaterial
#if not mat:
#return
#
#screen_water_ui.show()
#mat.set_shader_parameter("clear_progress", 0.0)
#mat.set_shader_parameter("drop_intensity", 0.8)
#mat.set_shader_parameter("wash_intensity", 0.5)
#
#if water_clear_tween and water_clear_tween.is_valid():
#water_clear_tween.kill()
#
#water_clear_tween = create_tween()
#
## Phase 1 & 2: Rapid wipe to 65%, then hold
#water_clear_tween.tween_property(mat, "shader_parameter/clear_progress", 0.65, 0.1).set_trans(
#Tween.TRANS_SINE
#)
#water_clear_tween.tween_interval(0.1)
#
## Phase 3: Finish sweep
#(
#water_clear_tween
#. tween_property(mat, "shader_parameter/clear_progress", 1.2, 0.2)
#. set_trans(Tween.TRANS_CUBIC)
#. set_ease(Tween.EASE_OUT)
#)
#
## Phase 4: Fade droplets
#water_clear_tween.tween_property(mat, "shader_parameter/drop_intensity", 0.0, 1.0).set_trans(
#Tween.TRANS_SINE
#)
#(
#water_clear_tween
#. parallel()
#. tween_property(mat, "shader_parameter/wash_intensity", 0.0, 1.0)
#. set_trans(Tween.TRANS_SINE)
#)
#
## Phase 5: Hide
#water_clear_tween.tween_callback(screen_water_ui.hide)
#
#
## --------------------------------------
## WATERFALL LOGIC
## --------------------------------------
#func enter_waterfall() -> void:
#print("ScreenVFXManager executing enter_waterfall(), triggering overlay tweens.")
#in_waterfall = true
#if not waterfall_overlay:
#return
#
#var mat: ShaderMaterial = waterfall_overlay.material as ShaderMaterial
#if not mat:
#return
#
#if waterfall_clear_tween and waterfall_clear_tween.is_valid():
#waterfall_clear_tween.kill()
#
#waterfall_overlay.show()
#mat.set_shader_parameter("clear_progress", 0.0)
#mat.set_shader_parameter("wash_intensity", 1.0)
#mat.set_shader_parameter("drop_intensity", 0.0)
#
#
#func exit_waterfall() -> void:
#print("ScreenVFXManager executing exit_waterfall(), fading overlay out.")
#in_waterfall = false
#if not waterfall_overlay:
#return
#
#var mat: ShaderMaterial = waterfall_overlay.material as ShaderMaterial
#if not mat:
#return
#
#if waterfall_clear_tween and waterfall_clear_tween.is_valid():
#waterfall_clear_tween.kill()
#
#mat.set_shader_parameter("drop_intensity", 1.0)
#
#waterfall_clear_tween = create_tween()
#
#(
#waterfall_clear_tween
#. tween_property(mat, "shader_parameter/clear_progress", 1.2, 0.4)
#. set_trans(Tween.TRANS_CUBIC)
#. set_ease(Tween.EASE_OUT)
#)
#
#(
#waterfall_clear_tween
#. parallel()
#. tween_property(mat, "shader_parameter/wash_intensity", 0.0, 0.4)
#. set_trans(Tween.TRANS_SINE)
#)
#
#(
#waterfall_clear_tween
#. parallel()
#. tween_property(mat, "shader_parameter/drop_intensity", 0.0, 1.2)
#. set_trans(Tween.TRANS_QUAD)
#. set_ease(Tween.EASE_IN)
#)
#
#waterfall_clear_tween.tween_callback(waterfall_overlay.hide)
