## Reusable 3D muzzle flash controller driving flash quads, light, sparks, and gunsmoke.
class_name MuzzleFlash
extends Node3D

## Shader uniform key controlling per-instance flash alpha decay.
const PARAM_FLASH_ALPHA: StringName = &"flash_alpha"
## Shader uniform key controlling per-instance HDR emission intensity.
const PARAM_HDR_ENERGY: StringName = &"hdr_energy"

## Duration in seconds for the flash quads to decay from peak to invisible.
@export var flash_duration: float = 0.05
## Peak light energy for [OmniLight3D] muzzle illumination.
@export var light_energy_peak: float = 5.0
## Maximum range in meters for [OmniLight3D] muzzle illumination.
@export var light_range: float = 6.0
## Tint color applied to the [OmniLight3D] muzzle illumination.
@export var light_color: Color = Color(1.0, 0.72, 0.32, 1.0)
## HDR emission multiplier written to flash mesh instance shader parameters.
@export var hdr_energy: float = 7.5
## Minimum uniform scale multiplier applied to [member _flash_rig] per shot.
@export var scale_jitter_min: float = 0.85
## Maximum uniform scale multiplier applied to [member _flash_rig] per shot.
@export var scale_jitter_max: float = 1.18

var _flash_tween: Tween = null
var _flash_meshes: Array[MeshInstance3D] = []

@onready var _flash_rig: Node3D = get_node_or_null("FlashRig") as Node3D
@onready var _flash_light: OmniLight3D = get_node_or_null("FlashLight") as OmniLight3D
@onready var _powder_sparks: GPUParticles3D = get_node_or_null("PowderSparks") as GPUParticles3D
@onready var _barrel_smoke: GPUParticles3D = get_node_or_null("BarrelSmoke") as GPUParticles3D


## Initializes render layers, resets flash visuals, and disables process ticks.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_enforce_render_layer(self)
	_collect_flash_meshes()
	_apply_hdr_energy()
	_set_flash_alpha(0.0)

	if is_instance_valid(_flash_rig):
		_flash_rig.visible = false

	if is_instance_valid(_flash_light):
		_flash_light.shadow_enabled = false
		_flash_light.light_color = light_color
		_flash_light.omni_range = light_range
		_flash_light.light_energy = 0.0

	if is_instance_valid(_powder_sparks):
		_powder_sparks.one_shot = true
		_powder_sparks.emitting = false

	if is_instance_valid(_barrel_smoke):
		_barrel_smoke.local_coords = false
		_barrel_smoke.one_shot = true
		_barrel_smoke.emitting = false


## Kills any active decay tween when leaving the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_flash_tween)
	_flash_tween = null


## Triggers a one-shot muzzle flash, omni light pulse, spark burst, and barrel smoke puff.
func trigger() -> void:
	print("MuzzleFlash: Triggered.")
	if is_instance_valid(_flash_rig):
		_flash_rig.rotation.z = randf_range(0.0, TAU)
		var jitter_scale: float = randf_range(scale_jitter_min, scale_jitter_max)
		_flash_rig.scale = Vector3.ONE * jitter_scale
		_flash_rig.visible = true

	_apply_hdr_energy()
	_set_flash_alpha(1.0)

	if is_instance_valid(_flash_light):
		_flash_light.light_color = light_color
		_flash_light.omni_range = light_range
		_flash_light.light_energy = light_energy_peak

	if is_instance_valid(_powder_sparks):
		_powder_sparks.restart()
		_powder_sparks.emitting = true

	if is_instance_valid(_barrel_smoke):
		_barrel_smoke.restart()
		_barrel_smoke.emitting = true

	_flash_tween = Utilities.reset_tween(self, _flash_tween)
	if is_instance_valid(_flash_tween):
		_flash_tween.set_parallel(true)
		(
			_flash_tween
			. tween_method(_set_flash_alpha, 1.0, 0.0, flash_duration)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		if is_instance_valid(_flash_light):
			(
				_flash_tween
				. tween_property(_flash_light, "light_energy", 0.0, flash_duration * 1.15)
				. set_trans(Tween.TRANS_QUAD)
				. set_ease(Tween.EASE_OUT)
			)
		_flash_tween.chain().tween_callback(_on_flash_finished)


## Enforces Volumetric Render Layer 10 and disables shadow casting on visual descendants.
func _enforce_render_layer(node: Node) -> void:
	if node is GeometryInstance3D:
		var geom: GeometryInstance3D = node as GeometryInstance3D
		geom.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
		geom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_enforce_render_layer(child)


## Caches all [MeshInstance3D] flash quads inside [member _flash_rig].
func _collect_flash_meshes() -> void:
	_flash_meshes.clear()
	if not is_instance_valid(_flash_rig):
		return
	for child: Node in _flash_rig.get_children():
		if child is MeshInstance3D:
			_flash_meshes.append(child as MeshInstance3D)


## Writes [member hdr_energy] to every flash quad's instance shader parameter.
func _apply_hdr_energy() -> void:
	for mesh: MeshInstance3D in _flash_meshes:
		if is_instance_valid(mesh):
			mesh.set_instance_shader_parameter(PARAM_HDR_ENERGY, hdr_energy)


## Updates per-instance [code]flash_alpha[/code] across all flash quads.
func _set_flash_alpha(alpha: float) -> void:
	for mesh: MeshInstance3D in _flash_meshes:
		if is_instance_valid(mesh):
			mesh.set_instance_shader_parameter(PARAM_FLASH_ALPHA, alpha)


## Hides the flash rig and zeroes light energy after decay finishes.
func _on_flash_finished() -> void:
	_set_flash_alpha(0.0)
	if is_instance_valid(_flash_rig):
		_flash_rig.visible = false
	if is_instance_valid(_flash_light):
		_flash_light.light_energy = 0.0
