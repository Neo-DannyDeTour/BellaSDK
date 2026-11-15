## Demon's Souls style electric homing orb projectile launched by [EnemyImp].
class_name ImpHomingOrb
extends Area3D

## Emitted when the orb impacts geometry, a target, or expires.
signal impacted(hit_pos: Vector3, hit_body: Node)

## Preloaded electric impact sound effect.
const SFX_ELECTRIC: AudioStream = preload("res://assets/sounds/imp/imp_lightning_zap.wav")

## Property identifier for deferred monitoring toggles.
const PROP_MONITORING: StringName = &"monitoring"

## Default render layers (Environment + Volumetrics) for glowing orb meshes.
const DEFAULT_RENDER_LAYERS: int = (1 << 0) | (1 << 9)

## Flight speed in meters per second after launch.
@export var speed: float = 11.0

## Maximum steering turn rate in degrees per second while homing.
@export var turn_rate_deg: float = 95.0

## Electric damage dealt on direct hit.
@export var damage: int = 14

## Maximum flight lifetime in seconds before self-detonation.
@export var lifetime: float = 5.5

## Horizontal orbit radius around the Imp during charge telegraph.
@export var orbit_radius: float = 0.85

## Vertical offset above Imp origin while orbiting.
@export var orbit_height: float = 1.25

## Angular orbit speed in radians per second during charge telegraph.
@export var orbit_angular_speed: float = 3.2

## Impact explosion VFX scene spawned on detonation.
@export var explosion_vfx_scene: PackedScene = preload("res://vfx/imp/imp_explosion_vfx.tscn")

## Current normalized flight direction vector.
var velocity_dir: Vector3 = Vector3.FORWARD

## True while orbiting above the Imp prior to launch.
var is_orbiting: bool = false

## True once the orb has been launched toward its target.
var has_launched: bool = false

var _owner_imp: Node3D = null
var _target: Node3D = null
var _orbit_angle: float = 0.0
var _token: int = 0
var _impacted: bool = false
var _orb_mesh: MeshInstance3D = null
var _trail_particles: GPUParticles3D = null


## Initializes collision masks, fallback geometry, and disables idle processing.
func _ready() -> void:
	set_process(false)
	if not is_orbiting and not has_launched:
		set_physics_process(false)

	collision_layer = CollisionLayers.MASK_INTERACTIVE
	collision_mask = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_PLAYER
	monitorable = false

	_ensure_visual_and_collider()
	Utilities.safe_connect(body_entered, _on_body_entered)


## Places the orb in shoulder orbit around [param owner_imp] before auto-launching.
func setup_orbit(
	owner_imp: Node3D, orbit_angle: float, target_node: Node3D, orbit_duration: float = 0.65
) -> void:
	_owner_imp = owner_imp
	_target = target_node
	_orbit_angle = orbit_angle
	is_orbiting = true
	has_launched = false
	_impacted = false
	_token += 1
	set_deferred(PROP_MONITORING, false)
	set_physics_process(true)

	if is_instance_valid(owner_imp):
		global_position = _compute_orbit_position(owner_imp.global_position)

	if orbit_duration > 0.0 and is_inside_tree():
		var local_token: int = _token
		var timer: SceneTreeTimer = get_tree().create_timer(orbit_duration)
		timer.timeout.connect(_on_orbit_finished.bind(local_token))


## Launches the orb toward [param target_node] with optional [param initial_dir].
func launch(target_node: Node3D, initial_dir: Vector3 = Vector3.ZERO) -> void:
	if _impacted or has_launched:
		return
	_target = target_node
	is_orbiting = false
	has_launched = true
	_token += 1

	if initial_dir.length_squared() > 0.001:
		velocity_dir = initial_dir.normalized()
	elif is_instance_valid(_target):
		var aim_pt: Vector3 = _target.global_position + Vector3(0.0, 0.9, 0.0)
		var delta_vec: Vector3 = aim_pt - global_position
		velocity_dir = (
			delta_vec.normalized()
			if delta_vec.length_squared() > 0.001
			else -global_transform.basis.z
		)
	else:
		velocity_dir = -global_transform.basis.z

	set_deferred(PROP_MONITORING, true)
	set_physics_process(true)
	if is_instance_valid(_trail_particles):
		_trail_particles.emitting = true

	if is_inside_tree() and lifetime > 0.0:
		var local_token: int = _token
		var timer: SceneTreeTimer = get_tree().create_timer(lifetime)
		timer.timeout.connect(_on_lifetime_expired.bind(local_token))

	print("ImpHomingOrb: Launched from ", global_position)


## Updates orbit motion or smooth homing steering each physics tick.
func _physics_process(delta: float) -> void:
	if _impacted:
		return
	if is_orbiting:
		_step_orbit(delta)
	elif has_launched:
		step_steering(delta)


## Advances flight position while smoothly steering toward [member _target].
func step_steering(delta: float) -> void:
	if is_instance_valid(_target):
		var aim_point: Vector3 = _target.global_position + Vector3(0.0, 0.9, 0.0)
		var to_target: Vector3 = aim_point - global_position
		if to_target.length_squared() > 0.001:
			var desired_dir: Vector3 = to_target.normalized()
			var max_rad: float = deg_to_rad(turn_rate_deg) * delta
			var dot_val: float = clampf(velocity_dir.dot(desired_dir), -1.0, 1.0)
			var angle: float = acos(dot_val)
			if angle > 0.0001:
				var step: float = minf(angle, max_rad)
				var axis: Vector3 = velocity_dir.cross(desired_dir)
				if axis.length_squared() < 0.00001:
					axis = Vector3.UP
				velocity_dir = velocity_dir.rotated(axis.normalized(), step).normalized()

	global_position += velocity_dir * speed * delta


## Cancels and frees the orb cleanly (e.g. if owner Imp dies during telegraph).
func cancel_orb() -> void:
	_token += 1
	_impacted = true
	is_orbiting = false
	set_physics_process(false)
	queue_free()


## Updates orbital position around [member _owner_imp], cancelling if owner died.
func _step_orbit(delta: float) -> void:
	if not is_instance_valid(_owner_imp):
		cancel_orb()
		return
	if _owner_imp is EnemyImp:
		var imp_owner: EnemyImp = _owner_imp as EnemyImp
		if imp_owner.current_state == EnemyImp.ImpState.DEAD:
			cancel_orb()
			return
	_orbit_angle += orbit_angular_speed * delta
	global_position = _compute_orbit_position(_owner_imp.global_position)


## Computes world position on the orbital ring above [param center].
func _compute_orbit_position(center: Vector3) -> Vector3:
	return (
		center
		+ Vector3(cos(_orbit_angle) * orbit_radius, orbit_height, sin(_orbit_angle) * orbit_radius)
	)


## Auto-launches the orb when its telegraph orbit duration finishes.
func _on_orbit_finished(token: int) -> void:
	if token != _token or _impacted or has_launched:
		return
	launch(_target)


## Self-detonates when flight [member lifetime] expires without impact.
func _on_lifetime_expired(token: int) -> void:
	if token != _token or _impacted:
		return
	_detonate(null)


## Deals electric damage and spawns explosion VFX upon hitting Player or Environment.
func _on_body_entered(body: Node3D) -> void:
	if _impacted or not has_launched or not is_instance_valid(body):
		return
	if body == _owner_imp or body is EnemyImp:
		return
	_apply_electric_damage(body)
	_detonate(body)


## Applies [member damage] if [param body] has a hostile [HealthComponent].
func _apply_electric_damage(body: Node3D) -> void:
	if is_instance_valid(_owner_imp):
		var owner_fc: FactionComponent = FactionComponent.get_faction_component(_owner_imp)
		var body_fc: FactionComponent = FactionComponent.get_faction_component(body)
		if is_instance_valid(owner_fc) and is_instance_valid(body_fc):
			if not owner_fc.is_hostile_to(body_fc):
				return

	var hc: HealthComponent = _resolve_health_component(body)
	if is_instance_valid(hc):
		hc.take_damage(damage)


## Resolves [HealthComponent] on [param node] via property or child query.
func _resolve_health_component(node: Node) -> HealthComponent:
	if "health_component" in node:
		var hc_var: Variant = node.get("health_component")
		if hc_var is HealthComponent:
			return hc_var as HealthComponent
	var child_hc: Node = NodeQuery.find_first_child_of_type(node, HealthComponent)
	if child_hc is HealthComponent:
		return child_hc as HealthComponent
	return null


## Spawns electric explosion VFX, plays impact audio, emits [signal impacted], and frees orb.
func _detonate(hit_body: Node) -> void:
	if _impacted:
		return
	_impacted = true
	set_physics_process(false)
	set_deferred(PROP_MONITORING, false)

	var impact_pos: Vector3 = global_position
	_spawn_explosion_vfx(impact_pos)
	AudioPool.play_sfx_3d(SFX_ELECTRIC, impact_pos)
	impacted.emit(impact_pos, hit_body)
	queue_free()


## Instantiates [member explosion_vfx_scene] in the world container at [param world_pos].
func _spawn_explosion_vfx(world_pos: Vector3) -> void:
	if explosion_vfx_scene == null or not is_inside_tree():
		return
	var inst: Node = explosion_vfx_scene.instantiate()
	if not inst is Node3D:
		if is_instance_valid(inst):
			inst.queue_free()
		return
	var vfx_3d: Node3D = inst as Node3D
	var parent_node: Node = (
		get_parent() if is_instance_valid(get_parent()) else get_tree().current_scene
	)
	if not is_instance_valid(parent_node):
		parent_node = get_tree().root
	parent_node.add_child(vfx_3d)
	vfx_3d.global_position = world_pos
	if vfx_3d is ImpExplosionVFX:
		var exp_vfx: ImpExplosionVFX = vfx_3d as ImpExplosionVFX
		exp_vfx.explosion_finished.connect(exp_vfx.queue_free)
		exp_vfx.trigger_explosion(world_pos, 0.45)


## Ensures visual mesh, trail particles, and collider exist even when created via code.
func _ensure_visual_and_collider() -> void:
	_orb_mesh = get_node_or_null("OrbMesh") as MeshInstance3D
	if not is_instance_valid(_orb_mesh):
		_orb_mesh = MeshInstance3D.new()
		_orb_mesh.name = "OrbMesh"
		var sphere_mesh: SphereMesh = SphereMesh.new()
		sphere_mesh.radius = 0.20
		sphere_mesh.height = 0.40
		sphere_mesh.radial_segments = 16
		sphere_mesh.rings = 8
		_orb_mesh.mesh = sphere_mesh
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.55, 0.92, 1.0, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.15, 0.72, 1.0, 1.0)
		mat.emission_energy_multiplier = 6.0
		_orb_mesh.material_override = mat
		add_child(_orb_mesh)
	_orb_mesh.layers = DEFAULT_RENDER_LAYERS

	_trail_particles = get_node_or_null("TrailParticles") as GPUParticles3D
	if is_instance_valid(_trail_particles):
		_trail_particles.layers = DEFAULT_RENDER_LAYERS

	var col: Node = NodeQuery.find_first_child_of_type(self, CollisionShape3D)
	if not is_instance_valid(col):
		var new_col: CollisionShape3D = CollisionShape3D.new()
		new_col.name = "CollisionShape3D"
		var shape: SphereShape3D = SphereShape3D.new()
		shape.radius = 0.28
		new_col.shape = shape
		add_child(new_col)
