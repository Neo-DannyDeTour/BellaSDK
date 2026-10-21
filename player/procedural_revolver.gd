## Procedural first-person revolver and dual-hand rig built from native primitives.
## Integrates directly with [WeaponInventoryComponent] and [Events] bus.
# class_name ProceduralRevolverRig
extends Node3D

## Emitted when a shot is fired and the recoil sequence begins.
@warning_ignore("unused_signal")
signal shot_fired(ammo_remaining: int)
## Emitted when the reload sequence finishes and capacity is restored.
@warning_ignore("unused_signal")
signal reload_completed

enum WeaponState {
	IDLE,
	SHOOTING,
	RELOADING,
	INSPECTING,
}

## Identifier tag recognized by [WeaponInventoryComponent] and HUD.
@export var weapon_tag: String = "revolver"
## Preferred inventory slot (1 to 5).
@export var default_slot: int = 1
## Ammo category matching pickups from [member Events.ammo_collected].
@export var ammo_type: StringName = &"revolver_ammo"
## Reserve ammunition pool.
@export var reserve_ammo: int = 30

## Render layer 2 (Player viewmodel).
const LAYER_PLAYER: int = 1 << 1
## Maximum cartridge capacity of the cylinder.
const MAX_AMMO: int = 6

## Resting position of the weapon root relative to the camera socket.
const RIG_REST_POS: Vector3 = Vector3(0.22, -0.20, -0.42)
## Resting position of the support hand relative to the weapon root.
const LEFT_HAND_REST_POS: Vector3 = Vector3(-0.08, -0.14, 0.12)
## Resting rotation of the support hand in radians.
const LEFT_HAND_REST_ROT: Vector3 = Vector3(0.0, 0.35, 0.0)

var _state: WeaponState = WeaponState.IDLE
var _ammo: int = MAX_AMMO
var _tween: Tween = null

var _rig_root: Node3D = null
var _gun_pivot: Node3D = null
var _cylinder_crane: Node3D = null
var _cylinder_mesh: MeshInstance3D = null
var _hammer_pivot: Node3D = null
var _right_hand: Node3D = null
var _left_hand: Node3D = null


## Disables per-frame processing and builds the procedural primitive hierarchy.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_build_procedural_rig()
	assert(is_instance_valid(_rig_root), "Revolver: Rig root failed to initialize.")
	print(
		(
			"ProceduralRevolver: Initialized. Ammo: %d/%d (Reserve: %d)"
			% [_ammo, MAX_AMMO, reserve_ammo]
		)
	)


## Broadcasts current ammunition metrics to the global [Events] bus.
func sync_ammo_ui() -> void:
	if is_instance_valid(Events) and Events.has_signal(&"weapon_ammo_changed"):
		Events.weapon_ammo_changed.emit(_ammo, reserve_ammo, MAX_AMMO)


## Fires a round, triggering recoil, cylinder indexing, and HUD event sync.
## [param _player_camera] Optional reference passed by [WeaponInventoryComponent].
func shoot(_player_camera: Camera3D = null) -> void:
	if _state != WeaponState.IDLE:
		return
	if _ammo <= 0:
		print("ProceduralRevolver: Dry fire (empty cylinder).")
		_play_dry_fire()
		return

	_state = WeaponState.SHOOTING
	_ammo -= 1
	print("ProceduralRevolver: Shot fired. Ammo: %d/%d" % [_ammo, MAX_AMMO])

	shot_fired.emit(_ammo)
	sync_ammo_ui()

	_reset_tween()
	var next_cyl_angle: float = _cylinder_mesh.rotation.z + (TAU / float(MAX_AMMO))

	_tween.tween_property(_hammer_pivot, "rotation:x", -0.7, 0.03)
	_tween.tween_property(_hammer_pivot, "rotation:x", 0.0, 0.02)
	(
		_tween
		. tween_property(_rig_root, "position", RIG_REST_POS + Vector3(0.0, 0.06, 0.10), 0.05)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween
		. parallel()
		. tween_property(_rig_root, "rotation", Vector3(0.48, 0.0, 0.0), 0.05)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_OUT)
	)
	_tween.parallel().tween_property(_cylinder_mesh, "rotation:z", next_cyl_angle, 0.05)

	(
		_tween
		. tween_property(_rig_root, "position", RIG_REST_POS, 0.22)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_tween
		. parallel()
		. tween_property(_rig_root, "rotation", Vector3.ZERO, 0.22)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	_tween.tween_callback(_on_sequence_finished)


## Swings out the cylinder, ejects shells, draws rounds from reserve, and snaps shut.
func reload() -> void:
	if _state != WeaponState.IDLE or _ammo >= MAX_AMMO or reserve_ammo <= 0:
		return
	_state = WeaponState.RELOADING
	print("ProceduralRevolver: Reloading initiated.")

	_reset_tween()

	(
		_tween
		. tween_property(_rig_root, "rotation", Vector3(0.18, 0.35, -0.45), 0.25)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween
		. parallel()
		. tween_property(_cylinder_crane, "rotation:z", 1.35, 0.25)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)

	_tween.tween_property(_left_hand, "position", Vector3(-0.06, -0.01, -0.10), 0.20).set_trans(
		Tween.TRANS_SINE
	)
	(
		_tween
		. tween_property(_rig_root, "rotation", Vector3(0.65, 0.25, -0.35), 0.15)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_OUT)
	)

	_tween.tween_property(_rig_root, "rotation", Vector3(-0.15, 0.35, -0.50), 0.20)
	_tween.parallel().tween_property(_left_hand, "position", Vector3(-0.18, -0.35, 0.10), 0.20)
	(
		_tween
		. tween_property(_left_hand, "position", Vector3(-0.07, 0.01, 0.04), 0.22)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_tween.tween_property(_rig_root, "position", RIG_REST_POS + Vector3(0.0, -0.02, 0.02), 0.08)

	(
		_tween
		. tween_property(_cylinder_crane, "rotation:z", 0.0, 0.15)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_IN)
	)
	_tween.parallel().tween_property(_left_hand, "position", LEFT_HAND_REST_POS, 0.25)
	_tween.parallel().tween_property(_rig_root, "position", RIG_REST_POS, 0.25)
	_tween.parallel().tween_property(_rig_root, "rotation", Vector3.ZERO, 0.25)
	_tween.tween_callback(_on_reload_finished)


## Rotates the revolver across the viewport and spins the cylinder for inspection.
func inspect() -> void:
	if _state != WeaponState.IDLE:
		return
	_state = WeaponState.INSPECTING
	print("ProceduralRevolver: Inspecting initiated.")

	_reset_tween()
	var spin_angle: float = _cylinder_mesh.rotation.z + (TAU * 2.0)

	(
		_tween
		. tween_property(
			_left_hand, "position", LEFT_HAND_REST_POS + Vector3(-0.10, -0.18, 0.0), 0.30
		)
		. set_trans(Tween.TRANS_SINE)
	)
	(
		_tween
		. parallel()
		. tween_property(_rig_root, "position", Vector3(0.05, -0.14, -0.36), 0.40)
		. set_trans(Tween.TRANS_SINE)
	)
	(
		_tween
		. parallel()
		. tween_property(_rig_root, "rotation", Vector3(0.15, 0.85, -0.35), 0.40)
		. set_trans(Tween.TRANS_SINE)
	)
	_tween.tween_interval(0.35)

	(
		_tween
		. tween_property(_rig_root, "rotation", Vector3(-0.10, -0.75, 0.40), 0.50)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_tween
		. parallel()
		. tween_property(_cylinder_mesh, "rotation:z", spin_angle, 0.55)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	_tween.tween_interval(0.35)

	_tween.tween_property(_rig_root, "position", RIG_REST_POS, 0.35).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(_rig_root, "rotation", Vector3.ZERO, 0.35).set_trans(
		Tween.TRANS_SINE
	)
	_tween.parallel().tween_property(_left_hand, "position", LEFT_HAND_REST_POS, 0.35).set_trans(
		Tween.TRANS_SINE
	)
	_tween.tween_callback(_on_sequence_finished)


## Plays dry fire click when hammer strikes empty chamber.
func _play_dry_fire() -> void:
	_state = WeaponState.SHOOTING
	_reset_tween()
	_tween.tween_property(_hammer_pivot, "rotation:x", -0.5, 0.04)
	_tween.tween_property(_hammer_pivot, "rotation:x", 0.0, 0.02)
	_tween.tween_property(_rig_root, "position", RIG_REST_POS + Vector3(0.0, -0.005, 0.005), 0.04)
	_tween.tween_property(_rig_root, "position", RIG_REST_POS, 0.06)
	_tween.tween_callback(_on_sequence_finished)


## Kills existing active tween before constructing a new sequence.
func _reset_tween() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()


## Restores [member WeaponState.IDLE] after shooting or inspection.
func _on_sequence_finished() -> void:
	_state = WeaponState.IDLE


## Calculates ammo refilled from reserve and emits reload completion signals.
func _on_reload_finished() -> void:
	var needed: int = MAX_AMMO - _ammo
	var taken: int = mini(needed, reserve_ammo)
	_ammo += taken
	reserve_ammo -= taken
	_state = WeaponState.IDLE

	print(
		(
			"ProceduralRevolver: Reload completed. Ammo: %d/%d (Reserve: %d)"
			% [_ammo, MAX_AMMO, reserve_ammo]
		)
	)

	reload_completed.emit()
	if is_instance_valid(Events):
		if Events.has_signal(&"weapon_reloaded"):
			Events.weapon_reloaded.emit(weapon_tag)
		sync_ammo_ui()


## Constructs the hierarchical pivot tree and primitive meshes for the revolver and hands.
func _build_procedural_rig() -> void:
	# shortcut: flat albedo materials, upgrade to shared shader resource when texturing
	var mat_steel: StandardMaterial3D = _make_mat(Color(0.22, 0.24, 0.27), 0.85, 0.25)
	var mat_wood: StandardMaterial3D = _make_mat(Color(0.38, 0.20, 0.10), 0.0, 0.65)
	var mat_skin: StandardMaterial3D = _make_mat(Color(0.82, 0.64, 0.52), 0.0, 0.75)
	var mat_sleeve: StandardMaterial3D = _make_mat(Color(0.14, 0.16, 0.20), 0.0, 0.85)

	_rig_root = Node3D.new()
	_rig_root.name = &"RigRoot"
	_rig_root.position = RIG_REST_POS
	add_child(_rig_root)

	_gun_pivot = Node3D.new()
	_gun_pivot.name = &"GunPivot"
	_rig_root.add_child(_gun_pivot)

	_add_box(_gun_pivot, Vector3(0.036, 0.055, 0.14), Vector3(0.0, 0.0, 0.0), mat_steel)
	_add_box(_gun_pivot, Vector3(0.024, 0.028, 0.18), Vector3(0.0, 0.022, -0.15), mat_steel)
	_add_box(_gun_pivot, Vector3(0.018, 0.014, 0.15), Vector3(0.0, 0.002, -0.14), mat_steel)
	_add_box(_gun_pivot, Vector3(0.006, 0.014, 0.02), Vector3(0.0, 0.040, -0.22), mat_steel)
	var grip: MeshInstance3D = _add_box(
		_gun_pivot, Vector3(0.032, 0.11, 0.048), Vector3(0.0, -0.065, 0.075), mat_wood
	)
	grip.rotation.x = -0.28

	_cylinder_crane = Node3D.new()
	_cylinder_crane.name = &"CylinderCrane"
	_cylinder_crane.position = Vector3(-0.018, -0.015, 0.0)
	_gun_pivot.add_child(_cylinder_crane)

	var cyl_shape: CylinderMesh = CylinderMesh.new()
	cyl_shape.top_radius = 0.026
	cyl_shape.bottom_radius = 0.026
	cyl_shape.height = 0.068
	cyl_shape.radial_segments = 12

	_cylinder_mesh = MeshInstance3D.new()
	_cylinder_mesh.name = &"CylinderMesh"
	_cylinder_mesh.mesh = cyl_shape
	_cylinder_mesh.material_override = mat_steel
	_cylinder_mesh.layers = LAYER_PLAYER
	_cylinder_mesh.position = Vector3(0.018, 0.022, 0.0)
	_cylinder_mesh.rotation.x = PI * 0.5
	_cylinder_crane.add_child(_cylinder_mesh)

	_hammer_pivot = Node3D.new()
	_hammer_pivot.name = &"HammerPivot"
	_hammer_pivot.position = Vector3(0.0, 0.025, 0.065)
	_gun_pivot.add_child(_hammer_pivot)
	_add_box(_hammer_pivot, Vector3(0.010, 0.028, 0.024), Vector3(0.0, 0.012, 0.005), mat_steel)

	_right_hand = _create_hand(&"RightHand", true, mat_skin, mat_sleeve)
	_right_hand.position = Vector3(0.012, -0.065, 0.085)
	_right_hand.rotation = Vector3(-0.28, 0.0, 0.0)
	_gun_pivot.add_child(_right_hand)

	_left_hand = _create_hand(&"LeftHand", false, mat_skin, mat_sleeve)
	_left_hand.position = LEFT_HAND_REST_POS
	_left_hand.rotation = LEFT_HAND_REST_ROT
	_rig_root.add_child(_left_hand)


## Builds a stylized block-mesh hand and forearm sleeve.
func _create_hand(
	hand_name: StringName,
	is_right: bool,
	mat_skin: StandardMaterial3D,
	mat_sleeve: StandardMaterial3D
) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = hand_name
	var side_sign: float = -1.0 if is_right else 1.0

	_add_box(root, Vector3(0.036, 0.082, 0.065), Vector3.ZERO, mat_skin)
	_add_box(root, Vector3(0.032, 0.072, 0.045), Vector3(side_sign * 0.016, 0.0, -0.042), mat_skin)
	var thumb: MeshInstance3D = _add_box(
		root, Vector3(0.024, 0.026, 0.055), Vector3(side_sign * 0.015, 0.042, -0.015), mat_skin
	)
	thumb.rotation.y = side_sign * -0.45
	_add_box(root, Vector3(0.062, 0.078, 0.24), Vector3(0.0, -0.01, 0.15), mat_sleeve)
	return root


## Creates a [BoxMesh] child assigned to the player viewmodel render layer.
func _add_box(
	parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D
) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var inst: MeshInstance3D = MeshInstance3D.new()
	inst.mesh = box
	inst.material_override = mat
	inst.layers = LAYER_PLAYER
	inst.position = pos
	parent.add_child(inst)
	return inst


## Allocates a configured [StandardMaterial3D] for primitive parts.
func _make_mat(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
