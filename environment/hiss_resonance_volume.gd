## Area-based Hiss distortion volume mimicking Control screen-space distortion.
class_name HissResonanceVolume
extends Area3D

## Emitted when an entity enters or exits the resonance anomaly boundary.
signal resonance_state_changed(is_active: bool)

## Target visual mesh render layer: Layer 10 (Volumetrics = 1 << 9).
const VOLUMETRIC_RENDER_LAYER: int = 512

@export var max_distortion: float = 0.05
@export var fade_duration: float = 1.2
@export var mesh_instance: MeshInstance3D

var _shader_material: ShaderMaterial
var _tween: Tween


## Validates nodes, assigns layer 10 (Volumetrics), and caches material.
func _ready() -> void:
	print("HissResonanceVolume: Initializing resonance volume.")
	if not is_instance_valid(mesh_instance):
		mesh_instance = get_node_or_null("EffectMesh") as MeshInstance3D

	if is_instance_valid(mesh_instance):
		mesh_instance.layers = VOLUMETRIC_RENDER_LAYER
		_shader_material = mesh_instance.get_active_material(0) as ShaderMaterial

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Adjusts shader distortion intensity smoothly using a [Tween].
func set_distortion_intensity(target_intensity: float) -> void:
	print("HissResonanceVolume: Setting distortion intensity to ", target_intensity)
	if not is_instance_valid(_shader_material):
		return

	if is_instance_valid(_tween) and _tween.is_running():
		_tween.kill()

	_tween = create_tween()
	(
		_tween
		. tween_property(
			_shader_material,
			"shader_parameter/distortion_strength",
			target_intensity,
			fade_duration
		)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)


## Handles body entry to trigger resonance increase for players.
func _on_body_entered(body: Node3D) -> void:
	print("HissResonanceVolume: Entity entered volume: ", body.name)
	set_distortion_intensity(max_distortion)
	resonance_state_changed.emit(true)


## Handles body exit to restore idle distortion level.
func _on_body_exited(body: Node3D) -> void:
	print("HissResonanceVolume: Entity exited volume: ", body.name)
	set_distortion_intensity(0.01)
	resonance_state_changed.emit(false)
