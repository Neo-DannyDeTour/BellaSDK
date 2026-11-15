## Wall-mounted gothic healing dispenser with 25mm corrugated pipe conduit,
## octopus-fang nozzle, glowing liquid glass reservoir, VHS TV screen, and iron shutters.
class_name HealthDispenser
extends StaticBody3D

## Preloaded PBR material for rusted riveted iron chassis backplate.
const RUSTED_STEEL_MAT: Material = preload("res://assets/materials/rusted_steel/rusted_steel.tres")

## Preloaded PBR material for dark gothic wrought-iron trim and hardware.
const GOTHIC_METAL_MAT: Material = preload(
	"res://assets/materials/gothic_wrought_metal/gothic_wrought_metal.tres"
)

## Preloaded PBR material for 25mm corrugated pipe conduit.
const CONDUIT_MAT: Material = preload(
	"res://assets/materials/conduit_ribbed_metal/conduit_ribbed_metal.tres"
)

## Preloaded PBR material for slimy biomechanical octopus nozzle skin.
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

## Number of cross-section rings forming the continuous 25mm corrugated conduit.
const CONDUIT_RINGS: int = 64

## Number of radial sides around the corrugated conduit circumference.
const CONDUIT_RADIAL_SEGS: int = 12

## Inner trough radius in meters of the 25mm corrugated conduit ribs.
const CONDUIT_INNER_RADIUS: float = 0.022

## Outer ridge radius in meters of the 25mm corrugated conduit ribs.
const CONDUIT_OUTER_RADIUS: float = 0.031

## Semi-transparent glowing green liquid color at high reservoir charge.
const COLOR_LIQUID_HIGH: Color = Color(0.10, 0.98, 0.30, 0.38)

## Semi-transparent glowing amber liquid color at medium reservoir charge.
const COLOR_LIQUID_MID: Color = Color(0.98, 0.72, 0.08, 0.38)

## Semi-transparent glowing red liquid color at low reservoir charge.
const COLOR_LIQUID_LOW: Color = Color(0.98, 0.14, 0.10, 0.38)

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

## Spatial pivot node acting as the root anchor for the procedural conduit.
@export var tentacle_pivot: Node3D

## Trigger [Area3D] detecting player proximity to animate the conduit.
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

## Maximum physical reach in meters the conduit can extend toward targets.
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

## Continuous procedural corrugated conduit [MeshInstance3D].
var _conduit_mesh_instance: MeshInstance3D = null

## Dynamic [ArrayMesh] updated when the conduit bends toward targets.
var _conduit_mesh: ArrayMesh = null

## Pre-allocated vertex buffer for zero-allocation conduit curve updates.
var _conduit_verts: PackedVector3Array = PackedVector3Array()

## Pre-allocated normal buffer for zero-allocation conduit curve updates.
var _conduit_normals: PackedVector3Array = PackedVector3Array()

## Pre-allocated UV buffer for zero-allocation conduit curve updates.
var _conduit_uvs: PackedVector2Array = PackedVector2Array()

## Pre-allocated triangle index buffer for the corrugated conduit mesh.
var _conduit_indices: PackedInt32Array = PackedInt32Array()

## Pre-allocated mesh surface arrays passed to [method ArrayMesh.add_surface_from_arrays].
var _conduit_arrays: Array = []

## Instanced octopus-fang nozzle attached at the conduit tip.
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

## Target world coordinate for the tip of the procedural conduit.
var _current_target_pos: Vector3 = Vector3.ZERO

## Tension scalar between 0.0 (limp resting) and 1.0 (reaching toward target).
var _active_weight: float = 0.0


## Initializes chassis PBR overrides, VHS TV screen, liquid reservoir, and conduit.
func _ready() -> void:
	print("HealthDispenser: _ready() - Initializing gothic dispenser and conduit.")

	_current_dispenser_health = max_dispenser_health
	_setup_chassis()
	_setup_screen_shader()
	_setup_health_cylinder()
	_setup_continuous_conduit()
	_spawn_octopus_nozzle()

	if is_instance_valid(depleted_label):
		depleted_label.visible = false

	if is_instance_valid(tentacle_pivot):
		_current_target_pos = tentacle_pivot.global_position + (Vector3.DOWN * 1.1)
		_update_tentacle_visuals()

	set_physics_process(false)

	if is_instance_valid(detection_area):
		Utilities.safe_connect(detection_area.body_entered, _on_body_entered)
		Utilities.safe_connect(detection_area.body_exited, _on_body_exited)


## Evaluates quadratic bezier interpolation to guide continuous conduit and nozzle.
func _physics_process(delta: float) -> void:
	if _is_depleted:
		set_physics_process(false)
		return

	var is_targeting: bool = is_instance_valid(_nearby_player)
	var desired_target: Vector3 = Vector3.ZERO

	if is_targeting:
		_active_weight = move_toward(_active_weight, 1.0, delta * 3.0)
		desired_target = _nearby_player.global_position + Vector3(0.0, 1.0, 0.0)
	else:
		_active_weight = move_toward(_active_weight, 0.0, delta * 2.0)
		desired_target = tentacle_pivot.global_position + (Vector3.DOWN * 1.1)

	_current_target_pos = _current_target_pos.lerp(desired_target, delta * 6.0)
	_update_tentacle_visuals()

	var is_resting: bool = (
		_active_weight <= 0.0 and _current_target_pos.is_equal_approx(desired_target)
	)
	if is_resting:
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


## Recursively assigns rusted iron or gothic wrought metal materials to chassis meshes.
func _apply_chassis_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if mesh_inst.name.contains("Backplate"):
			mesh_inst.material_override = RUSTED_STEEL_MAT
		elif not (mesh_inst.name.contains("GaugeFace") or mesh_inst.name.contains("ScreenBacking")):
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


## Pre-allocates mesh buffers and [MeshInstance3D] for the continuous 25mm conduit.
func _setup_continuous_conduit() -> void:
	if not is_instance_valid(tentacle_pivot):
		return

	var ring_stride: int = CONDUIT_RADIAL_SEGS + 1
	var vert_count: int = (CONDUIT_RINGS + 1) * ring_stride
	var index_count: int = CONDUIT_RINGS * CONDUIT_RADIAL_SEGS * 6

	_conduit_verts.resize(vert_count)
	_conduit_normals.resize(vert_count)
	_conduit_uvs.resize(vert_count)
	_conduit_indices.resize(index_count)

	var idx: int = 0
	for r: int in range(CONDUIT_RINGS):
		var row_a: int = r * ring_stride
		var row_b: int = (r + 1) * ring_stride
		for s: int in range(CONDUIT_RADIAL_SEGS):
			var a: int = row_a + s
			var b: int = row_a + s + 1
			var c: int = row_b + s
			var d: int = row_b + s + 1
			_conduit_indices[idx] = a
			_conduit_indices[idx + 1] = b
			_conduit_indices[idx + 2] = d
			_conduit_indices[idx + 3] = a
			_conduit_indices[idx + 4] = d
			_conduit_indices[idx + 5] = c
			idx += 6

	_conduit_arrays.resize(Mesh.ARRAY_MAX)
	_conduit_mesh = ArrayMesh.new()
	_conduit_mesh_instance = MeshInstance3D.new()
	_conduit_mesh_instance.name = "CorrugatedConduit"
	_conduit_mesh_instance.top_level = true
	_conduit_mesh_instance.mesh = _conduit_mesh
	_conduit_mesh_instance.material_override = CONDUIT_MAT
	_conduit_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	tentacle_pivot.add_child(_conduit_mesh_instance)


## Instantiates the rigged octopus-fang nozzle at the tip of the 25mm conduit.
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


## Applies slimy cephalopod flesh material to nozzle body while preserving fangs/suckers.
func _apply_nozzle_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if mesh_inst.name.contains("NozzleBody"):
			mesh_inst.material_override = OCTOPUS_MAT
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


## Rebuilds the continuous corrugated conduit mesh along the quadratic bezier curve.
func _update_tentacle_visuals() -> void:
	if not is_instance_valid(tentacle_pivot) or not is_instance_valid(_conduit_mesh):
		return

	var p0: Vector3 = tentacle_pivot.global_position
	var p2: Vector3 = _current_target_pos

	var raw_dist: float = p0.distance_to(p2)
	if raw_dist > max_reach:
		var direction: Vector3 = p0.direction_to(p2)
		p2 = p0 + (direction * max_reach)
		raw_dist = max_reach

	var p1: Vector3 = p0.lerp(p2, 0.5)
	p1.y += (raw_dist * 0.6) * _active_weight

	var ring_stride: int = CONDUIT_RADIAL_SEGS + 1
	var prev_tangent: Vector3 = Vector3.DOWN
	var ref_normal: Vector3 = Vector3.FORWARD

	for r: int in range(CONDUIT_RINGS + 1):
		var t: float = float(r) / float(CONDUIT_RINGS)
		var center: Vector3 = _get_quadratic_bezier(p0, p1, p2, t)
		var tangent: Vector3 = _get_quadratic_bezier_tangent(p0, p1, p2, t)
		if tangent.length_squared() > 0.000001:
			tangent = tangent.normalized()
		else:
			tangent = prev_tangent

		if r == 0:
			var up_ref: Vector3 = Vector3.RIGHT if absf(tangent.y) >= 0.98 else Vector3.UP
			ref_normal = tangent.cross(up_ref).normalized()
		else:
			var rot_quat: Quaternion = Quaternion(prev_tangent, tangent)
			ref_normal = (rot_quat * ref_normal).normalized()

		var binormal: Vector3 = tangent.cross(ref_normal).normalized()
		var radius: float = CONDUIT_OUTER_RADIUS if (r % 2 == 1) else CONDUIT_INNER_RADIUS
		var v_coord: float = t * 16.0

		var base_idx: int = r * ring_stride
		for s: int in range(ring_stride):
			var u_coord: float = float(s) / float(CONDUIT_RADIAL_SEGS)
			var ang: float = u_coord * TAU
			var radial_dir: Vector3 = (ref_normal * cos(ang)) + (binormal * sin(ang))
			_conduit_verts[base_idx + s] = center + (radial_dir * radius)
			_conduit_normals[base_idx + s] = radial_dir
			_conduit_uvs[base_idx + s] = Vector2(u_coord, v_coord)

		prev_tangent = tangent

	_conduit_arrays[Mesh.ARRAY_VERTEX] = _conduit_verts
	_conduit_arrays[Mesh.ARRAY_NORMAL] = _conduit_normals
	_conduit_arrays[Mesh.ARRAY_TEX_UV] = _conduit_uvs
	_conduit_arrays[Mesh.ARRAY_INDEX] = _conduit_indices
	_conduit_mesh.clear_surfaces()
	_conduit_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _conduit_arrays)

	if is_instance_valid(_nozzle_instance):
		var end_tangent: Vector3 = _get_quadratic_bezier_tangent(p0, p1, p2, 1.0)
		_orient_along_segment(_nozzle_instance, p2 - end_tangent, p2)
		_nozzle_instance.global_position = p2
		_nozzle_instance.scale = Vector3.ONE


## Computes point along quadratic bezier curve for normalized time.
func _get_quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	return q0.lerp(q1, t)


## Computes analytical tangent vector along quadratic bezier curve.
func _get_quadratic_bezier_tangent(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	return (2.0 * (1.0 - t) * (p1 - p0)) + (2.0 * t * (p2 - p1))


## Orients a +Y-aligned node so its local +Y axis points from p1 toward p2.
func _orient_along_segment(node: Node3D, p1: Vector3, p2: Vector3) -> void:
	var dir: Vector3 = p2 - p1
	if dir.length_squared() > 0.000001:
		var is_parallel: bool = absf(dir.normalized().y) >= 0.99
		var up: Vector3 = Vector3.RIGHT if is_parallel else Vector3.UP
		node.look_at(p2, up)
		node.rotate_object_local(Vector3.RIGHT, PI * 0.5)


## Initializes Lex Pertizan glowing semi-transparent liquid reservoir parameters.
func _setup_health_cylinder() -> void:
	if not is_instance_valid(health_cylinder):
		return

	print("HealthDispenser: Setting up glowing glass liquid health reservoir.")
	health_cylinder.material_override = LIQUID_BOTTLE_MAT

	var radius: float = 0.095
	var half_height: float = 0.36
	var cyl_mesh: CylinderMesh = (
		health_cylinder.mesh if health_cylinder.mesh is CylinderMesh else null
	)
	if cyl_mesh != null:
		radius = cyl_mesh.top_radius
		half_height = cyl_mesh.height * 0.5

	health_cylinder.set_instance_shader_parameter(PARAM_SIZE, Vector2(radius, half_height))
	health_cylinder.set_instance_shader_parameter(PARAM_THICKNESS, 0.008)
	health_cylinder.set_instance_shader_parameter(PARAM_SCALE, 1.05)
	health_cylinder.set_instance_shader_parameter(PARAM_VEL, 1.0)
	health_cylinder.set_instance_shader_parameter(PARAM_EMISSION, 2.4)

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


## Closes shutter doors, removes health bar & conduit, and displays medieval text.
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


## Enables conduit targeting loop when player enters detection area.
func _on_body_entered(body: Node3D) -> void:
	if _is_depleted:
		return

	var character: CharacterBody3D = body if body is CharacterBody3D else null
	if character and character.is_in_group(&"player"):
		print("HealthDispenser: _on_body_entered() - Player detected.")
		_nearby_player = character
		_connect_player_health(_nearby_player)
		set_physics_process(true)


## Cleans up references and puts conduit to sleep when player exits.
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
