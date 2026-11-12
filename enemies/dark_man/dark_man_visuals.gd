class_name DarkManVisuals
extends CharacterBody3D
## Visuals, shader instance parameters, and weapon socket setup for [DarkManVisuals].

## Pre-allocated shader instance parameter name for elastomer and steel wear.
const PARAM_WEAR: StringName = &"wear_amount"
## Pre-allocated shader instance parameter name for per-instance color tinting.
const PARAM_TINT: StringName = &"tint_shift"
## Default animation clip name baked in [dark_man.glb].
const ANIM_IDLE_AXE: StringName = &"Idle_Hold_Axe"
## Shared body surface material preloaded at parse time.
const MAT_BODY: ShaderMaterial = preload("res://assets/models/dark_man/mat_dark_man.tres")
## Shared weapon surface material preloaded at parse time.
const MAT_AXE: ShaderMaterial = preload("res://assets/models/dark_man/mat_fire_axe.tres")

## Per-instance edge wear factor pushed to [member PARAM_WEAR] without duplicating materials.
@export_range(0.0, 1.0, 0.01) var wear_amount: float = 0.15:
	set(value):
		wear_amount = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_apply_instance_uniforms()

## Per-instance albedo multiplier pushed to [member PARAM_TINT].
@export var tint_shift: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		tint_shift = value
		if is_inside_tree():
			_apply_instance_uniforms()

## Automatically plays [member ANIM_IDLE_AXE] on [method _ready] when true.
@export var auto_play_idle: bool = true

## Cached humanoid body [MeshInstance3D] under [member _skeleton].
@onready var _body_mesh: MeshInstance3D = $DarkManModel/DarkManRig/Skeleton3D/DarkManBody
## Cached [Skeleton3D] matching [SkeletonProfileHumanoid] bone names.
@onready var _skeleton: Skeleton3D = $DarkManModel/DarkManRig/Skeleton3D
## Cached [AnimationPlayer] driving [member ANIM_IDLE_AXE].
@onready var _anim_player: AnimationPlayer = $DarkManModel/AnimationPlayer
## Cached [BoneAttachment3D] bound to [code]RightHand[/code].
@onready
var _right_hand_socket: BoneAttachment3D = $DarkManModel/DarkManRig/Skeleton3D/RightHandSocket
## Cached weapon [MeshInstance3D] mounted in [member _right_hand_socket].
@onready var _axe_mesh: MeshInstance3D = (
	_right_hand_socket.get_node(^"FireAxe/FireAxeMesh") as MeshInstance3D
)
## Cached weapon swing [Area3D] hitbox (inactive at rest).
@onready
var _axe_hitbox: Area3D = $DarkManModel/DarkManRig/Skeleton3D/RightHandSocket/FireAxe/AxeHitbox


## Initializes event-driven mode, enforces [CollisionLayers], and starts idle pose.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(is_instance_valid(_body_mesh), "Missing DarkManBody MeshInstance3D")
	assert(is_instance_valid(_skeleton), "Missing Skeleton3D")
	assert(is_instance_valid(_anim_player), "Missing AnimationPlayer")
	assert(is_instance_valid(_right_hand_socket), "Missing RightHandSocket BoneAttachment3D")
	assert(is_instance_valid(_axe_mesh), "Missing FireAxeMesh MeshInstance3D")
	assert(is_instance_valid(_axe_hitbox), "Missing AxeHitbox Area3D")

	collision_layer = CollisionLayers.MASK_ENEMIES
	collision_mask = CollisionLayers.MASK_SOLID_WORLD | CollisionLayers.MASK_PLAYER

	_body_mesh.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	_axe_mesh.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	_body_mesh.material_override = MAT_BODY
	_axe_mesh.material_override = MAT_AXE

	_axe_hitbox.collision_layer = 0
	_axe_hitbox.collision_mask = CollisionLayers.MASK_PLAYER
	_axe_hitbox.set_deferred(&"monitoring", false)
	_axe_hitbox.set_deferred(&"monitorable", false)

	_apply_instance_uniforms()
	if auto_play_idle:
		play_idle_hold_axe()
	print("DarkManVisuals: Ready (wear=%.2f, idle=%s)" % [wear_amount, str(auto_play_idle)])


## Updates [param wear] and [param tint] across both body and axe meshes via instance uniforms.
func apply_instance_look(wear: float, tint: Color) -> void:
	wear_amount = clampf(wear, 0.0, 1.0)
	tint_shift = tint
	if is_inside_tree():
		_apply_instance_uniforms()


## Enables looping on [member ANIM_IDLE_AXE] if available and starts playback.
func play_idle_hold_axe() -> void:
	if not is_instance_valid(_anim_player) or not _anim_player.has_animation(ANIM_IDLE_AXE):
		return
	var anim: Animation = _anim_player.get_animation(ANIM_IDLE_AXE)
	if is_instance_valid(anim):
		anim.loop_mode = Animation.LOOP_LINEAR
	_anim_player.play(ANIM_IDLE_AXE)


## Safely toggles [member _axe_hitbox] collision detection outside physics callbacks.
func set_axe_hitbox_active(active: bool) -> void:
	if not is_instance_valid(_axe_hitbox):
		return
	_axe_hitbox.set_deferred(&"monitoring", active)
	_axe_hitbox.set_deferred(&"monitorable", active)
	print("DarkManVisuals: AxeHitbox -> %s" % str(active))


## Pushes instance shader uniforms to body and axe meshes with zero material duplication.
func _apply_instance_uniforms() -> void:
	if is_instance_valid(_body_mesh):
		_body_mesh.set_instance_shader_parameter(PARAM_WEAR, wear_amount)
		_body_mesh.set_instance_shader_parameter(PARAM_TINT, tint_shift)
	if is_instance_valid(_axe_mesh):
		_axe_mesh.set_instance_shader_parameter(PARAM_WEAR, wear_amount)
		_axe_mesh.set_instance_shader_parameter(PARAM_TINT, tint_shift)
