@tool
## Manages 3D waterfall sheet UV scrolling, shader uniforms, and player contact VFX triggers.
class_name WaterfallStream
extends MeshInstance3D

## UV scroll speed vector across the waterfall mesh surface.
@export var scroll_speed: Vector2 = Vector2(0.0, -1.5)

## Multiplier for refraction bending against background geometry.
@export var refraction_strength: float = 0.03

## Primary albedo tint color for the falling water stream.
@export var water_tint: Color = Color(0.6, 0.8, 0.85, 0.3)

## Shader material reference cached from the surface override slot.
var _water_material: ShaderMaterial = null

## Active tween driving screen wash wipe progress on exit.
var _wipe_tween: Tween


## Lifecycle method configuring groups, material handles, and trigger bindings.
func _ready() -> void:
	print("WaterfallStream: Initializing waterfall stream.")
	add_to_group(&"waterfall_area")

	var mat: Material = get_surface_override_material(0)
	if mat is ShaderMaterial:
		_water_material = mat as ShaderMaterial
		_apply_shader_parameters()

	if not Engine.is_editor_hint():
		var area: Area3D = get_node_or_null("Area3D") as Area3D
		if is_instance_valid(area):
			area.body_entered.connect(_on_waterfall_body_entered)
			area.body_exited.connect(_on_waterfall_body_exited)


## Applies exported scroll speed and tint color to the active ShaderMaterial.
func _apply_shader_parameters() -> void:
	if not _water_material:
		return

	_water_material.set_shader_parameter(&"scroll_speed", scroll_speed)
	_water_material.set_shader_parameter(&"refraction_strength", refraction_strength)
	_water_material.set_shader_parameter(&"water_tint", water_tint)


## Sets a new UV scroll velocity for dynamic flow rate adjustments.
## [param new_speed] The [Vector2] flow velocity vector.
func set_flow_speed(new_speed: Vector2) -> void:
	print("WaterfallStream: Updating flow speed to -> ", new_speed)
	scroll_speed = new_speed
	if _water_material:
		_water_material.set_shader_parameter(&"scroll_speed", scroll_speed)


## Engages waterfall screen wash distortion when the player enters the stream.
## [param body] The [Node3D] entering the waterfall sheet.
func _on_waterfall_body_entered(body: Node3D) -> void:
	if body is Player or body.is_in_group(&"player"):
		print("WaterfallStream: Player entered stream. Activating waterfall wash VFX.")
		if _wipe_tween and _wipe_tween.is_valid():
			_wipe_tween.kill()
		Events.waterfall_vfx_toggled.emit(true, 1.0, 0.0)


## Plays a diagonal wipe transition and cleans the lens when the player exits.
## [param body] The [Node3D] exiting the waterfall sheet.
func _on_waterfall_body_exited(body: Node3D) -> void:
	if body is Player or body.is_in_group(&"player"):
		print("WaterfallStream: Player exited stream. Playing screen wipe transition.")
		if _wipe_tween and _wipe_tween.is_valid():
			_wipe_tween.kill()

		_wipe_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_wipe_tween.tween_method(
			func(prog: float) -> void:
				Events.waterfall_vfx_toggled.emit(true, 1.0 - (prog / 1.5), prog),
			0.0,
			1.5,
			1.2
		)
		_wipe_tween.finished.connect(
			func() -> void: Events.waterfall_vfx_toggled.emit(false, 0.0, 0.0)
		)
