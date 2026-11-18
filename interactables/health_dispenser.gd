## Wall-mounted gothic healing dispenser with organic S-curved cephalopod tentacle,
## suction-cup fang nozzle, multi-layer glass reservoir vessel, VHS screen, and shutters.
class_name HealthDispenser
extends StaticBody3D

## Preloaded PBR material for rusted riveted iron chassis backplate.
const RUSTED_STEEL_MAT: Material = preload("res://assets/materials/rusted_steel/rusted_steel.tres")

## Preloaded PBR material for dark gothic wrought-iron trim and hardware.
const GOTHIC_METAL_MAT: Material = preload(
	"res://assets/materials/gothic_wrought_metal/gothic_wrought_metal.tres"
)

## Preloaded PBR material for antique tarnished brass edges, gothic arch, and cages.
const TARNISHED_BRASS_MAT: Material = preload(
	"res://assets/materials/tarnished_brass/tarnished_brass.tres"
)

## Preloaded PBR material for slimy biomechanical octopus tentacle skin.
const OCTOPUS_MAT: Material = preload("res://assets/materials/octopus_flesh/octopus_flesh.tres")

## Preloaded Lex Pertizan glass + liquid shader material for the health reservoir.
const LIQUID_BOTTLE_MAT: Material = preload(
	"res://interactables/liquid_bottle/liquid_bottle_material.tres"
)

## Preloaded VHS/static TV screen spatial shader.
const SCREEN_SHADER: Shader = preload("res://shaders/health_dispenser_screen.gdshader")

## Preloaded rigged octopus-fang nozzle scene.
const OCTOPUS_NOZZLE_SCENE: PackedScene = preload(
	"res://assets/models/health_dispenser/octopus_nozzle.glb"
)

## Preloaded dry 3D healing SFX variation 1.
const HEAL_SFX_1: AudioStream = preload("res://assets/audio/sfx/health_dispenser_heal_01.wav")

## Preloaded dry 3D healing SFX variation 2.
const HEAL_SFX_2: AudioStream = preload("res://assets/audio/sfx/health_dispenser_heal_02.wav")

## Preloaded dry 3D shutter close SFX.
const CLOSE_SFX: AudioStream = preload("res://assets/audio/sfx/health_dispenser_close.wav")

## Pre-allocated shader parameter name for normalized liquid fill height.
const PARAM_FILL: StringName = &"fill_amount"

## Pre-allocated shader parameter name for RGBA liquid albedo and opacity.
const PARAM_COLOR: StringName = &"liquid_color"

## Pre-allocated shader parameter name for liquid emission glow intensity.
const PARAM_EMISSION: StringName = &"emission_energy"

## Pre-allocated shader parameter name for tank half-extents.
const PARAM_SIZE: StringName = &"size"

## Pre-allocated shader parameter name for simulated glass wall thickness.
const PARAM_THICKNESS: StringName = &"glass_thickness"

## Pre-allocated shader parameter name for rising bubble agitation velocity.
const PARAM_VEL: StringName = &"vel"

## Pre-allocated shader parameter name for liquid noise UV scale.
const PARAM_SCALE: StringName = &"scale"

## Pre-allocated shader parameter name for the TV screen face texture.
const PARAM_SCREEN_TEX: StringName = &"screen_tex"

## Pre-allocated animation name for closing the gothic shutter doors.
const ANIM_CLOSE: StringName = &"close"

## Pre-allocated animation name for snapping the octopus nozzle fangs.
const ANIM_BITE: StringName = &"bite"

## Depleted medieval status text shown after shutters close.
const DEPLETED_TEXT: String = "Out of Lifeblood!"

## Number of cross-section rings forming the continuous organic tentacle body.
const CONDUIT_RINGS: int = 64

## Number of radial sides around the organic tentacle circumference.
const CONDUIT_RADIAL_SEGS: int = 16

## Muscular base radius in meters where tentacle emerges from lower pipe socket.
const TENTACLE_BASE_RADIUS: float = 0.068

## Tapered distal radius in meters where tentacle body meets the tip nozzle.
const TENTACLE_TIP_RADIUS: float = 0.028

## Number of paired suction cup rows along the ventral tentacle curve.
const SUCKER_ROWS: int = 18

## Number of radial segments per procedural suction cup ring.
const SUCKER_RADIAL_SEGS: int = 8

## Rich emerald-green bioluminescent liquid color at high reservoir charge.
const COLOR_LIQUID_HIGH: Color = Color(0.02, 0.34, 0.06, 0.42)

## Glowing amber-chartreuse liquid color at medium reservoir charge.
const COLOR_LIQUID_MID: Color = Color(0.55, 0.38, 0.04, 0.42)

## Glowing crimson liquid color at low reservoir charge.
const COLOR_LIQUID_LOW: Color = Color(0.58, 0.06, 0.04, 0.42)

@export_category("Health Settings")
## Texture displayed on screen when player health is very low (<= 33%).
@export var tex_low_health: Texture2D

## Texture displayed on screen when player health is medium (<= 66%).
@export var tex_mid_health: Texture2D

## Texture displayed on screen when player health is high (<= 90%).
@export var tex_almost_health: Texture2D

## Texture displayed on screen when player health is full (> 90%).
@export var tex_ready_health: Texture2D

## Amount of health restored per tick while player holds interact.
@export var heal_amount: int = 25

## Minimum cooldown duration in milliseconds between consecutive healing ticks.
@export var heal_cooldown_msec: int = 250

## Maximum health capacity stored within this dispenser reservoir.
@export var max_dispenser_health: int = 200

@export_category("Node References")
## Screen [Sprite3D] projecting the dynamic health status texture.
@export var screen_sprite: Sprite3D

## Spatial pivot node acting as the root anchor for the procedural tentacle.
@export var tentacle_pivot: Node3D

## Trigger [Area3D] detecting player proximity to animate the tentacle.
@export var detection_area: Area3D

## Mesh representing the glass liquid reservoir draining as health depletes.
@export var health_cylinder: MeshInstance3D

## Optional imported gothic chassis model containing shutter [AnimationPlayer].
@export var chassis_model: Node3D

## Optional [Label3D] displaying medieval depleted message when empty.
@export var depleted_label: Label3D

@export_category("Procedural Conduit")
## Legacy segment count kept for inspector compatibility.
@export var segment_count: int = 15

## Legacy fallback color kept for inspector compatibility.
@export var tentacle_color: Color = Color(0.3, 0.1, 0.4)

## Legacy radial thickness kept for inspector compatibility.
@export var thickness: float = 0.034

## Maximum physical reach in meters the tentacle can extend toward targets.
@export var max_reach: float = 2.0

## Player character currently inside the proximity detection area.
var _nearby_player: CharacterBody3D = null

## Cached player health component bypassing repetitive string path lookups.
var _player_health_component: Node = null

## Timestamp in milliseconds tracking the last applied heal tick.
var _last_heal_time: int = 0

## Current remaining health points stored within the dispenser reservoir.
var _current_dispenser_health: int = 200

## Tracks whether the dispenser has already transitioned into depleted state.
var _is_depleted: bool = false

## Alternates between healing SFX variations on consecutive ticks.
var _heal_sfx_toggle: bool = false

## Continuous procedural organic tentacle [MeshInstance3D].
var _conduit_mesh_instance: MeshInstance3D = null

## Dynamic [ArrayMesh] updated when the tentacle bends toward targets.
var _conduit_mesh: ArrayMesh = null

## Pre-allocated vertex buffer for zero-allocation tentacle curve updates.
var _conduit_verts: PackedVector3Array = PackedVector3Array()

## Pre-allocated normal buffer for zero-allocation tentacle curve updates.
var _conduit_normals: PackedVector3Array = PackedVector3Array()

## Pre-allocated UV buffer for zero-allocation tentacle curve updates.
var _conduit_uvs: PackedVector2Array = PackedVector2Array()

## Pre-allocated triangle index buffer for the tentacle skin mesh.
var _conduit_indices: PackedInt32Array = PackedInt32Array()

## Pre-allocated mesh surface arrays for the tentacle skin surface.
var _conduit_arrays: Array[Variant] = []

## Pre-allocated vertex buffer for paired underside suction cups.
var _sucker_verts: PackedVector3Array = PackedVector3Array()

## Pre-allocated normal buffer for paired underside suction cups.
var _sucker_normals: PackedVector3Array = PackedVector3Array()

## Pre-allocated UV buffer for paired underside suction cups.
var _sucker_uvs: PackedVector2Array = PackedVector2Array()

## Pre-allocated triangle index buffer for paired underside suction cups.
var _sucker_indices: PackedInt32Array = PackedInt32Array()

## Pre-allocated mesh surface arrays for the suction cups surface.
var _sucker_arrays: Array[Variant] = []

## Wet fleshy pink material shared by tentacle and nozzle suction cups.
var _sucker_material: StandardMaterial3D = null

## Refractive Fresnel glass material applied to the outer reservoir vessel shell.
var _vessel_glass_material: StandardMaterial3D = null

## Instanced octopus-fang nozzle attached at the tentacle tip.
var _nozzle_instance: Node3D = null

## Cached [AnimationPlayer] inside the octopus nozzle instance.
var _nozzle_anim: AnimationPlayer = null

## Cached [AnimationPlayer] inside the gothic chassis model.
var _chassis_anim: AnimationPlayer = null

## Dedicated [ShaderMaterial] driving VHS waves and periodic static on the TV screen.
var _screen_material: ShaderMaterial = null

## Tween smoothing liquid fill level and color transitions.
var _liquid_tween: Tween = null

## Currently displayed normalized liquid fill ratio [0.0..1.0].
var _displayed_fill: float = 1.0

## Currently displayed glowing liquid color.
var _displayed_color: Color = COLOR_LIQUID_HIGH

## Target world coordinate for the tip of the procedural tentacle.
var _current_target_pos: Vector3 = Vector3.ZERO

## Tension scalar between 0.0 (S-curve rest) and 1.0 (reaching toward target).
var _active_weight: float = 0.0

## Accumulated phase timer driving subtle organic tentacle breathing motion.
var _organic_phase: float = 0.0


## Initializes chassis PBR overrides, VHS TV screen, liquid vessel, and tentacle.
func _ready() -> void:
	print("HealthDispenser: _ready() - Initializing gothic dispenser and organic tentacle.")

	_current_dispenser_health = max_dispenser_health
	_create_custom_materials()
	_setup_chassis()
	_setup_screen_shader()
	_setup_health_cylinder()
	_setup_continuous_conduit()
	_spawn_octopus_nozzle()

	if is_instance_valid(depleted_label):
		depleted_label.visible = false

	if is_instance_valid(tentacle_pivot):
		_current_target_pos = _get_rest_tip_world_pos()
		_update_tentacle_visuals()

	set_physics_process(false)

	if is_instance_valid(detection_area):
		Utilities.safe_connect(detection_area.body_entered, _on_body_entered)
		Utilities.safe_connect(detection_area.body_exited, _on_body_exited)


## Evaluates cubic bezier S-curve interpolation to guide organic tentacle and tip.
func _physics_process(delta: float) -> void:
	if _is_depleted:
		set_physics_process(false)
		return

	var is_targeting: bool = is_instance_valid(_nearby_player)
	var rest_tip: Vector3 = _get_rest_tip_world_pos()
	var desired_target: Vector3 = rest_tip

	if is_targeting:
		_active_weight = move_toward(_active_weight, 1.0, delta * 2.8)
		_organic_phase += delta * 2.4
		desired_target = _nearby_player.global_position + Vector3(0.0, 1.05, 0.0)
	else:
		_active_weight = move_toward(_active_weight, 0.0, delta * 2.0)
		_organic_phase = move_toward(_organic_phase, 0.0, delta * 2.0)

	_current_target_pos = _current_target_pos.lerp(desired_target, delta * 5.5)
	_update_tentacle_visuals()

	var is_resting: bool = (
		not is_targeting
		and _active_weight <= 0.001
		and _current_target_pos.distance_squared_to(rest_tip) <= 0.0001
	)
	if is_resting:
		_current_target_pos = rest_tip
		_update_tentacle_visuals()
		set_physics_process(false)


## Dispenses health to player during continuous interaction hold events.
func interact_held(_character: CharacterBody3D) -> void:
	if _is_depleted or _current_dispenser_health <= 0:
		print("HealthDispenser: interact_held() - Dispenser depleted.")
		return

	if not is_instance_valid(_player_health_component):
		return

	var raw_cur: Variant = _player_health_component.get("current_health")
	var raw_max: Variant = _player_health_component.get("max_health")
	var current_hp: int = raw_cur if raw_cur is int else 0
	var max_hp: int = raw_max if raw_max is int else 0
	var needed_hp: int = max_hp - current_hp

	if needed_hp <= 0:
		print("HealthDispenser: interact_held() - Player already at full HP.")
		return

	var current_time: int = Time.get_ticks_msec()
	if current_time - _last_heal_time >= heal_cooldown_msec:
		_last_heal_time = current_time

		var to_heal: int = mini(heal_amount, mini(_current_dispenser_health, needed_hp))
		print("HealthDispenser: interact_held() - Dispensing ", to_heal, " HP.")
		_player_health_component.call(&"heal", to_heal)
		_current_dispenser_health -= to_heal
		_trigger_nozzle_bite()
		_play_heal_sfx()
		_update_cylinder_visuals()

		if _current_dispenser_health <= 0:
			_on_dispenser_depleted()


## Creates shared wet suction-cup and outer refractive glass vessel materials.
func _create_custom_materials() -> void:
	_sucker_material = StandardMaterial3D.new()
	_sucker_material.albedo_color = Color(0.58, 0.25, 0.38, 1.0)
	_sucker_material.roughness = 0.14
	_sucker_material.metallic_specular = 0.85
	_sucker_material.rim_enabled = true
	_sucker_material.rim = 0.45
	_sucker_material.rim_tint = 0.55
	_sucker_material.clearcoat_enabled = true
	_sucker_material.clearcoat = 0.90
	_sucker_material.clearcoat_roughness = 0.06

	_vessel_glass_material = StandardMaterial3D.new()
	_vessel_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_vessel_glass_material.cull_mode = BaseMaterial3D.CULL_BACK
	_vessel_glass_material.albedo_color = Color(0.45, 0.78, 0.54, 0.24)
	_vessel_glass_material.metallic = 0.08
	_vessel_glass_material.metallic_specular = 0.96
	_vessel_glass_material.roughness = 0.05
	_vessel_glass_material.rim_enabled = true
	_vessel_glass_material.rim = 0.72
	_vessel_glass_material.rim_tint = 0.35
	_vessel_glass_material.clearcoat_enabled = true
	_vessel_glass_material.clearcoat = 1.0
	_vessel_glass_material.clearcoat_roughness = 0.03


## Applies PBR material overrides and caches shutter [AnimationPlayer] on chassis.
func _setup_chassis() -> void:
	if not is_instance_valid(chassis_model):
		return

	_apply_chassis_materials(chassis_model)
	_chassis_anim = _find_animation_player(chassis_model)
	if is_instance_valid(_chassis_anim) and _chassis_anim.has_animation(ANIM_CLOSE):
		_chassis_anim.play(ANIM_CLOSE)
		_chassis_anim.seek(0.0, true)
		_chassis_anim.pause()


## Recursively assigns tarnished brass, rusted steel, glass, or wrought iron to chassis.
func _apply_chassis_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		var m_name: String = mesh_inst.name
		if m_name.contains("Backplate") or m_name.contains("LowerPipeUpMouth"):
			mesh_inst.material_override = RUSTED_STEEL_MAT
		elif m_name.contains("Brass"):
			mesh_inst.material_override = TARNISHED_BRASS_MAT
		elif m_name.contains("GlassVesselOuter"):
			mesh_inst.material_override = _vessel_glass_material
		elif not (
			m_name.contains("GaugeFace")
			or m_name.contains("ScreenBacking")
			or m_name.contains("UpperSocketHole")
		):
			mesh_inst.material_override = GOTHIC_METAL_MAT

	for child: Node in node.get_children():
		_apply_chassis_materials(child)


## Configures the VHS/static TV screen shader material on [member screen_sprite].
func _setup_screen_shader() -> void:
	if not is_instance_valid(screen_sprite):
		return

	_screen_material = ShaderMaterial.new()
	_screen_material.shader = SCREEN_SHADER
	var initial_tex: Texture2D = (
		screen_sprite.texture if is_instance_valid(screen_sprite.texture) else tex_ready_health
	)
	if is_instance_valid(initial_tex):
		_screen_material.set_shader_parameter(PARAM_SCREEN_TEX, initial_tex)
	screen_sprite.material_override = _screen_material


## Pre-allocates mesh buffers for the organic tentacle skin and underside suction cups.
func _setup_continuous_conduit() -> void:
	if not is_instance_valid(tentacle_pivot):
		return

	var ring_stride: int = CONDUIT_RADIAL_SEGS + 1
	var body_vert_count: int = (CONDUIT_RINGS + 1) * ring_stride + 1
	var root_center_idx: int = (CONDUIT_RINGS + 1) * ring_stride
	var body_index_count: int = (
		(CONDUIT_RINGS * CONDUIT_RADIAL_SEGS * 6) + (CONDUIT_RADIAL_SEGS * 3)
	)

	_conduit_verts.resize(body_vert_count)
	_conduit_normals.resize(body_vert_count)
	_conduit_uvs.resize(body_vert_count)
	_conduit_indices.resize(body_index_count)

	var idx: int = 0
	for r: int in range(CONDUIT_RINGS):
		var row_a: int = r * ring_stride
		var row_b: int = (r + 1) * ring_stride
		for s: int in range(CONDUIT_RADIAL_SEGS):
			var a: int = row_a + s
			var b: int = row_a + s + 1
			var c: int = row_b + s
			var d: int = row_b + s + 1
			# Clockwise front-face winding for Godot 4 Vulkan renderer (normals point outward)
			_conduit_indices[idx] = a
			_conduit_indices[idx + 1] = d
			_conduit_indices[idx + 2] = b
			_conduit_indices[idx + 3] = a
			_conduit_indices[idx + 4] = c
			_conduit_indices[idx + 5] = d
			idx += 6

	# Cap the base of the tentacle inside the pipe mouth so interiors are never visible
	for s: int in range(CONDUIT_RADIAL_SEGS):
		_conduit_indices[idx] = root_center_idx
		_conduit_indices[idx + 1] = s
		_conduit_indices[idx + 2] = s + 1
		idx += 3

	_conduit_arrays.resize(Mesh.ARRAY_MAX)

	# Pre-allocate Surface 1: paired rows of 3D cup-shaped suckers along the underside
	var total_suckers: int = SUCKER_ROWS * 2
	var verts_per_sucker: int = (SUCKER_RADIAL_SEGS * 2) + 1
	var indices_per_sucker: int = SUCKER_RADIAL_SEGS * 9
	_sucker_verts.resize(total_suckers * verts_per_sucker)
	_sucker_normals.resize(total_suckers * verts_per_sucker)
	_sucker_uvs.resize(total_suckers * verts_per_sucker)
	_sucker_indices.resize(total_suckers * indices_per_sucker)

	var s_idx: int = 0
	for sc: int in range(total_suckers):
		var v_base: int = sc * verts_per_sucker
		var rim_base: int = v_base + SUCKER_RADIAL_SEGS
		var cup_center: int = v_base + (SUCKER_RADIAL_SEGS * 2)
		for s: int in range(SUCKER_RADIAL_SEGS):
			var sn: int = (s + 1) % SUCKER_RADIAL_SEGS
			var b0: int = v_base + s
			var b1: int = v_base + sn
			var r0: int = rim_base + s
			var r1: int = rim_base + sn
			# Outer stalk wall (CW outward)
			_sucker_indices[s_idx] = b0
			_sucker_indices[s_idx + 1] = r1
			_sucker_indices[s_idx + 2] = b1
			_sucker_indices[s_idx + 3] = b0
			_sucker_indices[s_idx + 4] = r0
			_sucker_indices[s_idx + 5] = r1
			# Concave inner suction disk (CW outward)
			_sucker_indices[s_idx + 6] = r0
			_sucker_indices[s_idx + 7] = cup_center
			_sucker_indices[s_idx + 8] = r1
			s_idx += 9

	_sucker_arrays.resize(Mesh.ARRAY_MAX)

	_conduit_mesh = ArrayMesh.new()
	_conduit_mesh_instance = MeshInstance3D.new()
	_conduit_mesh_instance.name = "OrganicTentacle"
	_conduit_mesh_instance.top_level = true
	_conduit_mesh_instance.mesh = _conduit_mesh
	_conduit_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	tentacle_pivot.add_child(_conduit_mesh_instance)


## Instantiates the rigged tentacle tip nozzle at the distal end of the tentacle.
func _spawn_octopus_nozzle() -> void:
	if not is_instance_valid(tentacle_pivot):
		return

	var inst: Node = OCTOPUS_NOZZLE_SCENE.instantiate()
	_nozzle_instance = inst as Node3D
	if not is_instance_valid(_nozzle_instance):
		return

	_nozzle_instance.top_level = true
	_apply_nozzle_materials(_nozzle_instance)
	tentacle_pivot.add_child(_nozzle_instance)
	_nozzle_anim = _find_animation_player(_nozzle_instance)


## Applies slimy cephalopod flesh and sucker materials to nozzle sub-meshes.
func _apply_nozzle_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if mesh_inst.name.contains("NozzleBody"):
			mesh_inst.material_override = OCTOPUS_MAT
		elif mesh_inst.name.contains("Suckers"):
			mesh_inst.material_override = _sucker_material
	for child: Node in node.get_children():
		_apply_nozzle_materials(child)


## Finds the first [AnimationPlayer] descendant under a root node.
func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child: Node in root.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if is_instance_valid(found):
			return found
	return null


## Plays the octopus fang bite animation when dispensing health.
func _trigger_nozzle_bite() -> void:
	if is_instance_valid(_nozzle_anim) and _nozzle_anim.has_animation(ANIM_BITE):
		_nozzle_anim.stop()
		_nozzle_anim.play(ANIM_BITE)


## Plays alternating dry 3D healing SFX at the nozzle tip via [AudioPool].
func _play_heal_sfx() -> void:
	if not is_inside_tree():
		return

	var pos: Vector3 = (
		_nozzle_instance.global_position if is_instance_valid(_nozzle_instance) else global_position
	)
	var stream: AudioStream = HEAL_SFX_1 if _heal_sfx_toggle else HEAL_SFX_2
	_heal_sfx_toggle = not _heal_sfx_toggle
	AudioPool.play_sfx_3d(stream, pos)


## Returns the world-space upper socket position where the S-curved tentacle rests.
func _get_rest_tip_world_pos() -> Vector3:
	if not is_instance_valid(tentacle_pivot):
		return global_position
	var b: Basis = global_transform.basis
	return tentacle_pivot.global_position + (b * Vector3(-0.08, 0.64, -0.06))


## Rebuilds the tapered organic tentacle and underside suckers along a cubic S-curve.
func _update_tentacle_visuals() -> void:
	if not is_instance_valid(tentacle_pivot) or not is_instance_valid(_conduit_mesh):
		return

	var b: Basis = global_transform.basis
	var right_dir: Vector3 = b.x.normalized()
	var up_dir: Vector3 = b.y.normalized()
	var fwd_dir: Vector3 = b.z.normalized()

	var p0: Vector3 = tentacle_pivot.global_position
	var p3: Vector3 = _current_target_pos

	var raw_dist_sq: float = p0.distance_squared_to(p3)
	var raw_dist: float = max_reach
	if raw_dist_sq > max_reach * max_reach:
		var direction: Vector3 = p0.direction_to(p3)
		p3 = p0 + (direction * max_reach)
	else:
		raw_dist = sqrt(raw_dist_sq)

	# Resting S-curve control points matching reference art (sweeps right then left then up)
	var p1_rest: Vector3 = p0 + (right_dir * 0.24) + (up_dir * 0.22) + (fwd_dir * 0.18)
	var p2_rest: Vector3 = p0 + (right_dir * -0.28) + (up_dir * 0.52) + (fwd_dir * 0.16)

	# Active reaching control points with subtle organic muscular undulation
	var sway_a: float = sin(_organic_phase) * 0.04 * _active_weight
	var sway_b: float = cos(_organic_phase * 0.85) * 0.04 * _active_weight
	var p1_act: Vector3 = (
		p0.lerp(p3, 0.33)
		+ (right_dir * (0.14 + sway_a))
		+ (up_dir * (0.22 * raw_dist))
		+ (fwd_dir * 0.15)
	)
	var p2_act: Vector3 = (
		p0.lerp(p3, 0.68)
		+ (right_dir * (-0.12 + sway_b))
		+ (up_dir * (0.12 * raw_dist))
		+ (fwd_dir * 0.08)
	)

	var p1: Vector3 = p1_rest.lerp(p1_act, _active_weight)
	var p2: Vector3 = p2_rest.lerp(p2_act, _active_weight)

	var ring_stride: int = CONDUIT_RADIAL_SEGS + 1
	var prev_tangent: Vector3 = up_dir
	var ref_normal: Vector3 = right_dir
	var binormal: Vector3 = fwd_dir

	for r: int in range(CONDUIT_RINGS + 1):
		var t: float = float(r) / float(CONDUIT_RINGS)
		var center: Vector3 = _get_cubic_bezier(p0, p1, p2, p3, t)
		var tangent: Vector3 = _get_cubic_bezier_tangent(p0, p1, p2, p3, t)
		if tangent.length_squared() > 0.000001:
			tangent = tangent.normalized()
		else:
			tangent = prev_tangent

		if r == 0:
			# Stable initial frame anchored to wall forward axis (never crosses gimbal lock)
			var wall_ref: Vector3 = up_dir if absf(tangent.dot(fwd_dir)) >= 0.95 else (-fwd_dir)
			ref_normal = tangent.cross(wall_ref).normalized()
		else:
			var rot_quat: Quaternion = Quaternion(prev_tangent, tangent)
			ref_normal = (rot_quat * ref_normal).normalized()

		# Right-handed frame: ref_normal (-X left), tangent (+Y along curve), binormal (+Z forward)
		binormal = tangent.cross(ref_normal).normalized()
		ref_normal = binormal.cross(tangent).normalized()

		# Smooth organic cephalopod taper + subtle muscular peristalsis ripple
		var base_r: float = lerpf(TENTACLE_BASE_RADIUS, TENTACLE_TIP_RADIUS, pow(t, 0.82))
		var muscle_ripple: float = 1.0 + (0.035 * sin(t * TAU * 7.0 - _organic_phase * 2.0))
		var radius: float = base_r * muscle_ripple
		var v_coord: float = t * 6.0

		var base_idx: int = r * ring_stride
		for s: int in range(ring_stride):
			var u_coord: float = float(s) / float(CONDUIT_RADIAL_SEGS)
			var ang: float = u_coord * TAU
			var ca: float = cos(ang)
			var sa: float = sin(ang)
			# Slightly flatten ventral front side (sa > 0) where suction cups sit
			var ventral_flatten: float = 0.90 if sa > 0.0 else 1.0
			var radial_dir: Vector3 = (
				((ref_normal * ca) + (binormal * (sa * ventral_flatten))).normalized()
			)
			_conduit_verts[base_idx + s] = center + (radial_dir * (radius * ventral_flatten))
			_conduit_normals[base_idx + s] = radial_dir
			_conduit_uvs[base_idx + s] = Vector2(u_coord, v_coord)

		prev_tangent = tangent

	# Root cap center vertex at r = 0
	var root_center_idx: int = (CONDUIT_RINGS + 1) * ring_stride
	_conduit_verts[root_center_idx] = p0
	_conduit_normals[root_center_idx] = -up_dir
	_conduit_uvs[root_center_idx] = Vector2(0.5, 0.0)

	# Populate Surface 1: paired rows of fleshy suction cups along ventral curve
	_update_sucker_geometry(p0, p1, p2, p3, up_dir, fwd_dir)

	_conduit_arrays[Mesh.ARRAY_VERTEX] = _conduit_verts
	_conduit_arrays[Mesh.ARRAY_NORMAL] = _conduit_normals
	_conduit_arrays[Mesh.ARRAY_TEX_UV] = _conduit_uvs
	_conduit_arrays[Mesh.ARRAY_INDEX] = _conduit_indices

	_sucker_arrays[Mesh.ARRAY_VERTEX] = _sucker_verts
	_sucker_arrays[Mesh.ARRAY_NORMAL] = _sucker_normals
	_sucker_arrays[Mesh.ARRAY_TEX_UV] = _sucker_uvs
	_sucker_arrays[Mesh.ARRAY_INDEX] = _sucker_indices

	_conduit_mesh.clear_surfaces()
	_conduit_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _conduit_arrays)
	_conduit_mesh.surface_set_material(0, OCTOPUS_MAT)
	_conduit_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _sucker_arrays)
	_conduit_mesh.surface_set_material(1, _sucker_material)

	# Orient tip nozzle directly from the final ring's twist-free orthonormal basis (zero spin!)
	if is_instance_valid(_nozzle_instance):
		var tip_basis: Basis = Basis(ref_normal, prev_tangent, binormal).orthonormalized()
		_nozzle_instance.global_transform = Transform3D(tip_basis, p3)


## Updates pre-allocated 3D suction cup vertices along the tentacle's ventral side.
func _update_sucker_geometry(
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	up_dir: Vector3,
	fwd_dir: Vector3,
) -> void:
	var verts_per_sucker: int = (SUCKER_RADIAL_SEGS * 2) + 1
	var prev_tangent: Vector3 = up_dir
	var ref_normal: Vector3 = up_dir.cross(-fwd_dir).normalized()

	for row: int in range(SUCKER_ROWS):
		var t: float = lerpf(0.06, 0.94, float(row) / float(SUCKER_ROWS - 1))
		var center: Vector3 = _get_cubic_bezier(p0, p1, p2, p3, t)
		var tangent: Vector3 = _get_cubic_bezier_tangent(p0, p1, p2, p3, t)
		if tangent.length_squared() > 0.000001:
			tangent = tangent.normalized()
		else:
			tangent = prev_tangent

		if row == 0:
			var wall_ref: Vector3 = up_dir if absf(tangent.dot(fwd_dir)) >= 0.95 else (-fwd_dir)
			ref_normal = tangent.cross(wall_ref).normalized()
		else:
			var rot_quat: Quaternion = Quaternion(prev_tangent, tangent)
			ref_normal = (rot_quat * ref_normal).normalized()

		var binormal: Vector3 = tangent.cross(ref_normal).normalized()
		ref_normal = binormal.cross(tangent).normalized()
		prev_tangent = tangent

		var body_r: float = lerpf(TENTACLE_BASE_RADIUS, TENTACLE_TIP_RADIUS, pow(t, 0.82)) * 0.90
		var cup_r: float = body_r * 0.38
		var cup_h: float = cup_r * 0.72

		for side_idx: int in range(2):
			var side_sign: float = -1.0 if side_idx == 0 else 1.0
			var sc_idx: int = (row * 2) + side_idx
			var v_base: int = sc_idx * verts_per_sucker
			var rim_base: int = v_base + SUCKER_RADIAL_SEGS
			var cup_center_idx: int = v_base + (SUCKER_RADIAL_SEGS * 2)

			# Position paired suckers on the front-outer (+binormal / +ref_normal) side facing player
			var cup_axis: Vector3 = (
				((binormal * 0.82) + (ref_normal * (side_sign * 0.48 + 0.22))).normalized()
			)
			var u_axis: Vector3 = cup_axis.cross(tangent).normalized()
			var v_axis: Vector3 = cup_axis.cross(u_axis).normalized()
			var root_pos: Vector3 = center + (cup_axis * (body_r * 0.92))
			var rim_center: Vector3 = root_pos + (cup_axis * cup_h)

			for s: int in range(SUCKER_RADIAL_SEGS):
				var ang: float = (float(s) / float(SUCKER_RADIAL_SEGS)) * TAU
				var ring_dir: Vector3 = (u_axis * cos(ang)) + (v_axis * sin(ang))
				_sucker_verts[v_base + s] = root_pos + (ring_dir * (cup_r * 0.78))
				_sucker_normals[v_base + s] = (ring_dir + (cup_axis * 0.35)).normalized()
				_sucker_uvs[v_base + s] = Vector2(float(s) / float(SUCKER_RADIAL_SEGS), 0.0)

				_sucker_verts[rim_base + s] = rim_center + (ring_dir * cup_r)
				_sucker_normals[rim_base + s] = (cup_axis + (ring_dir * 0.55)).normalized()
				_sucker_uvs[rim_base + s] = Vector2(float(s) / float(SUCKER_RADIAL_SEGS), 1.0)

			# Deeply recessed suction cavity center with inverted normal for dark hollow shading
			_sucker_verts[cup_center_idx] = root_pos - (cup_axis * (cup_h * 0.25))
			_sucker_normals[cup_center_idx] = -cup_axis
			_sucker_uvs[cup_center_idx] = Vector2(0.5, 0.5)


## Computes point along cubic bezier curve for normalized time t in [0..1].
func _get_cubic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	var tt: float = t * t
	var uu: float = u * u
	return (p0 * (uu * u)) + (p1 * (3.0 * uu * t)) + (p2 * (3.0 * u * tt)) + (p3 * (tt * t))


## Computes analytical tangent vector along cubic bezier curve for normalized time t.
func _get_cubic_bezier_tangent(
	p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float
) -> Vector3:
	var u: float = 1.0 - t
	return ((p1 - p0) * (3.0 * u * u)) + ((p2 - p1) * (6.0 * u * t)) + ((p3 - p2) * (3.0 * t * t))


## Initializes Lex Pertizan glowing emerald-green liquid reservoir parameters.
func _setup_health_cylinder() -> void:
	if not is_instance_valid(health_cylinder):
		return

	print("HealthDispenser: Setting up glowing glass liquid health reservoir.")
	health_cylinder.material_override = LIQUID_BOTTLE_MAT

	var radius: float = 0.095
	var half_height: float = 0.34
	var cyl_mesh: CylinderMesh = (
		health_cylinder.mesh if health_cylinder.mesh is CylinderMesh else null
	)
	if cyl_mesh != null:
		radius = cyl_mesh.top_radius
		half_height = cyl_mesh.height * 0.5

	health_cylinder.set_instance_shader_parameter(PARAM_SIZE, Vector2(radius, half_height))
	health_cylinder.set_instance_shader_parameter(PARAM_THICKNESS, 0.005)
	health_cylinder.set_instance_shader_parameter(PARAM_SCALE, 1.35)
	health_cylinder.set_instance_shader_parameter(PARAM_VEL, 1.15)
	health_cylinder.set_instance_shader_parameter(PARAM_EMISSION, 0.35)

	_displayed_fill = 1.0
	_displayed_color = COLOR_LIQUID_HIGH
	_apply_liquid_shader_state()


## Smoothly tweens liquid fill level and glowing color toward current reservoir ratio.
func _update_cylinder_visuals() -> void:
	if not is_instance_valid(health_cylinder):
		return

	var target_ratio: float = clampf(
		float(_current_dispenser_health) / float(max_dispenser_health), 0.0, 1.0
	)
	var target_color: Color = COLOR_LIQUID_HIGH
	if target_ratio <= 0.25:
		target_color = COLOR_LIQUID_LOW
	elif target_ratio <= 0.50:
		target_color = COLOR_LIQUID_MID

	if not is_inside_tree():
		_displayed_fill = target_ratio
		_displayed_color = target_color
		_apply_liquid_shader_state()
		return

	_liquid_tween = Utilities.reset_tween_ext(self, _liquid_tween, Tween.TRANS_SINE, Tween.EASE_OUT)
	if is_instance_valid(_liquid_tween):
		_liquid_tween.set_parallel(true)
		_liquid_tween.tween_method(_set_displayed_fill, _displayed_fill, target_ratio, 0.30)
		_liquid_tween.tween_method(_set_displayed_color, _displayed_color, target_color, 0.45)


## Tween callback updating displayed liquid fill level.
func _set_displayed_fill(value: float) -> void:
	_displayed_fill = value
	if is_instance_valid(health_cylinder):
		health_cylinder.set_instance_shader_parameter(PARAM_FILL, _displayed_fill)


## Tween callback updating displayed glowing liquid color.
func _set_displayed_color(value: Color) -> void:
	_displayed_color = value
	if is_instance_valid(health_cylinder):
		health_cylinder.set_instance_shader_parameter(PARAM_COLOR, _displayed_color)


## Synchronizes both liquid fill and color instance parameters immediately.
func _apply_liquid_shader_state() -> void:
	if not is_instance_valid(health_cylinder):
		return
	health_cylinder.set_instance_shader_parameter(PARAM_FILL, _displayed_fill)
	health_cylinder.set_instance_shader_parameter(PARAM_COLOR, _displayed_color)


## Closes shutter doors, hides liquid & tentacle, and displays medieval text.
func _on_dispenser_depleted() -> void:
	if _is_depleted:
		return

	_is_depleted = true
	_nearby_player = null
	_active_weight = 0.0
	set_physics_process(false)
	print("HealthDispenser: Reservoir empty! Closing shutters -> ", DEPLETED_TEXT)

	if is_instance_valid(health_cylinder):
		health_cylinder.visible = false

	if is_instance_valid(screen_sprite):
		screen_sprite.visible = false

	if is_instance_valid(_conduit_mesh_instance):
		_conduit_mesh_instance.visible = false

	if is_instance_valid(_nozzle_instance):
		_nozzle_instance.visible = false

	if is_instance_valid(_chassis_anim) and _chassis_anim.has_animation(ANIM_CLOSE):
		_chassis_anim.play(ANIM_CLOSE)

	if is_inside_tree():
		AudioPool.play_sfx_3d(CLOSE_SFX, global_position)

	if is_instance_valid(depleted_label):
		depleted_label.text = DEPLETED_TEXT
		depleted_label.visible = true


## Enables tentacle targeting loop when player enters detection area.
func _on_body_entered(body: Node3D) -> void:
	if _is_depleted:
		return

	var character: CharacterBody3D = body if body is CharacterBody3D else null
	if character and character.is_in_group(&"player"):
		print("HealthDispenser: _on_body_entered() - Player detected.")
		_nearby_player = character
		_connect_player_health(_nearby_player)
		set_physics_process(true)


## Cleans up references and returns tentacle to S-curve rest when player exits.
func _on_body_exited(body: Node3D) -> void:
	if body == _nearby_player:
		print("HealthDispenser: _on_body_exited() - Player departed.")
		_disconnect_player_health()
		_nearby_player = null


## Connects player health change signal using [method Utilities.safe_connect].
func _connect_player_health(player: CharacterBody3D) -> void:
	print("HealthDispenser: Connecting player health component signals.")
	var health_node: Node = player.get_node_or_null("Components/HealthComponent")

	if is_instance_valid(health_node) and health_node.has_signal(&"health_changed"):
		_player_health_component = health_node
		var sig: Signal = Signal(_player_health_component, &"health_changed")
		Utilities.safe_connect(sig, _on_player_health_changed)
		_update_screen()


## Disconnects active player health signal listener.
func _disconnect_player_health() -> void:
	print("HealthDispenser: Disconnecting player health component signals.")
	if is_instance_valid(_player_health_component):
		if _player_health_component.has_signal(&"health_changed"):
			var sig: Signal = Signal(_player_health_component, &"health_changed")
			if sig.is_connected(_on_player_health_changed):
				sig.disconnect(_on_player_health_changed)

	_player_health_component = null


## Refreshes screen texture display when player health changes.
func _on_player_health_changed(_new_health: int) -> void:
	print("HealthDispenser: Player health changed, refreshing UI screen.")
	_update_screen()


## Selects screen status texture matching current player health brackets.
func _update_screen() -> void:
	var is_valid: bool = (
		is_instance_valid(screen_sprite) and is_instance_valid(_player_health_component)
	)
	if not is_valid:
		return

	var raw_cur: Variant = _player_health_component.get("current_health")
	var raw_max: Variant = _player_health_component.get("max_health")
	var current: float = float(raw_cur) if raw_cur is int or raw_cur is float else 0.0
	var maximum: float = float(raw_max) if raw_max is int or raw_max is float else 0.0
	var ratio: float = 0.0

	if maximum > 0.0:
		ratio = current / maximum

	var selected_tex: Texture2D = tex_ready_health
	if ratio <= 0.33:
		selected_tex = tex_low_health
	elif ratio <= 0.66:
		selected_tex = tex_mid_health
	elif ratio <= 0.90:
		selected_tex = tex_almost_health

	screen_sprite.texture = selected_tex
	if is_instance_valid(_screen_material) and is_instance_valid(selected_tex):
		_screen_material.set_shader_parameter(PARAM_SCREEN_TEX, selected_tex)
