## Fat mechanical-legged electric Imp enemy with mood-driven AI, proactive HexShield,
## aim-frozen line lightning, homing orbs, 3-imp stack slams, and water dive-bombs.
class_name EnemyImp
extends CharacterBody3D

## Emitted when the imp transitions between [enum ImpState] values.
signal state_changed(new_state: ImpState)

## Emitted when the imp begins charging an electricity attack.
signal telegraph_started(attack_kind: StringName)

## Emitted when the imp locks its line lightning aim point prior to firing.
signal line_aim_locked(locked_point: Vector3)

## Emitted when the imp fires an electricity attack (line, AoE circle, or homing orbs).
signal electricity_attack_fired(attack_kind: StringName, target_pos: Vector3)

## Emitted when the imp executes a water dive-bomb explosion.
signal water_dive_exploded(water_node: Node3D, impact_pos: Vector3)

## Behavioral execution states for the Imp enemy.
enum ImpState {
	IDLE,
	CHASE,
	LEAP,
	CHARGE_LINE,
	CHARGE_AOE,
	CHARGE_ORBS,
	STACK_MOUNT,
	STACK_SLAM,
	WATER_DIVE,
	DEAD,
}

## Preloaded reactive [HexShieldSphere] scene spawned proactively or on hit cadence.
const HEX_SHIELD_SCENE: PackedScene = preload("res://enemies/hex_shield_sphere.tscn")

## Preloaded [ImpHomingOrb] scene spawned by the Demon's Souls orb attack.
const HOMING_ORB_SCENE: PackedScene = preload("res://enemies/imp/imp_homing_orb.tscn")

## Preloaded impact hurt grunt SFX.
const SFX_GRUNT: AudioStream = preload("res://assets/sounds/imp/imp_grunt_hurt.wav")

## Preloaded aggro chitter/war-cry SFX.
const SFX_AGGRO: AudioStream = preload("res://assets/sounds/imp/imp_grunt_aggro.wav")

## Preloaded death squeal SFX.
const SFX_DEATH: AudioStream = preload("res://assets/sounds/imp/imp_grunt_death.wav")

## Preloaded water splash SFX for dive-bomb impact.
const SFX_SPLASH: AudioStream = preload("res://assets/sounds/WaterSplash.mp3")

## Preloaded electric discharge SFX.
const SFX_ELECTRIC: AudioStream = preload("res://assets/sounds/imp/imp_lightning_zap.wav")

## Preloaded aim-lock cue SFX played when line lightning freezes target point.
const SFX_AIM_LOCK: AudioStream = preload("res://assets/sounds/ping_emitter_sound.mp3")

## Preloaded maniacal imp laugh SFX variant 1.
const SFX_LAUGH_01: AudioStream = preload("res://assets/sounds/imp/imp_laugh_01.wav")

## Preloaded maniacal imp laugh SFX variant 2.
const SFX_LAUGH_02: AudioStream = preload("res://assets/sounds/imp/imp_laugh_02.wav")

## Property identifier for deferred monitoring updates on [Area3D] nodes.
const PROP_MONITORING: StringName = &"monitoring"

## Group identifier for swimmable water [Area3D] volumes.
const GROUP_WATER_AREA: StringName = &"water_area"

## Group identifier for enemy actors used in autonomous 3-imp stack checks.
const GROUP_ENEMY: StringName = &"enemy"

## Default render layers (Environment + Volumetrics) for targeting beam visual.
const DEFAULT_RENDER_LAYERS: int = (1 << 0) | (1 << 9)

## Vertical totem offset per stack slot in meters.
const STACK_SLOT_HEIGHT: float = 1.15

## Maximum squared distance (12m radius) for autonomous 3-imp stack slams.
const AUTONOMOUS_STACK_RADIUS_SQ: float = 144.0

## Cooldown in seconds between autonomous 3-imp stack slams.
const AUTONOMOUS_STACK_COOLDOWN: float = 10.0

## Flicker presets triggered on nearby [PoweredLight3D] nodes.
const FLICKER_CHOICES: Array[int] = [
	PoweredLight3D.FlickerPreset.FLICKER_A,
	PoweredLight3D.FlickerPreset.FAST_STROBE,
	PoweredLight3D.FlickerPreset.FLICKER_B,
	PoweredLight3D.FlickerPreset.FLUORESCENT_FLICKER,
	PoweredLight3D.FlickerPreset.SLOW_STROBE,
]

@export_category("Movement & Combat")
## Ground waddle run speed in meters per second.
@export var waddle_speed: float = 4.2

## Upward jump velocity in meters per second for gap/ledge leaps.
@export var jump_velocity: float = 7.5

## Horizontal leap velocity in meters per second during jump traversal.
@export var leap_horizontal_speed: float = 8.5

## Squared detection radius for aggroing onto hostile targets.
@export var aggro_dist_sq: float = 324.0

## Squared deaggro radius beyond which target lock is dropped.
@export var deaggro_dist_sq: float = 900.0

## Preferred combat range squared for electricity attacks.
@export var attack_range_sq: float = 196.0

@export_category("Hex Shield")
## Cooldown in seconds between [HexShieldSphere] activations.
@export var hex_shield_cooldown: float = 8.0

## Maximum active duration in seconds before the shield expires.
@export var hex_shield_duration: float = 4.0

## Maximum hit points of the spawned [HexShieldSphere].
@export var hex_shield_health: int = 60

## Radius in meters of the spawned [HexShieldSphere].
@export var hex_shield_radius: float = 1.35

## Base proactive combat interval in seconds between unprovoked shield deployments.
@export var proactive_shield_interval: float = 9.0

## Guaranteed hit count cadence that deploys [HexShieldSphere] when off cooldown.
@export var shield_hit_cadence: int = 3

## Minimum per-hit reactive shield probability before the guaranteed hit cadence.
@export_range(0.0, 1.0, 0.05) var hex_shield_min_chance: float = 0.20

## Maximum per-hit reactive shield probability when evasive mood bias is high.
@export_range(0.0, 1.0, 0.05) var hex_shield_max_chance: float = 0.75

@export_category("Electricity Attacks")
## Telegraph charge duration in seconds before firing direct line lightning.
@export var line_charge_duration: float = 0.85

## Final frozen aim window in seconds before line lightning discharges.
@export var aim_freeze_duration: float = 0.35

## Damage dealt by direct line lightning beam.
@export var line_lightning_damage: int = 18

## Maximum range in meters for direct line lightning raycast.
@export var line_lightning_range: float = 22.0

## Telegraph charge duration in seconds before spawning 10m expanding circle AoE.
@export var aoe_charge_duration: float = 1.1

## Maximum radius in meters of the expanding lightning circle (5.0m = 10m diameter).
@export var aoe_circle_radius: float = 5.0

## Damage dealt by the 10m expanding lightning circle AoE.
@export var aoe_lightning_damage: int = 25

## Telegraph charge duration in seconds before launching homing orbs.
@export var orb_charge_duration: float = 0.75

## Number of [ImpHomingOrb] projectiles spawned per orb volley.
@export_range(1, 5, 1) var orb_count: int = 3

## Cooldown in seconds between electricity attacks.
@export var attack_cooldown: float = 2.6

@export_category("Squad Stack & Water Dive")
## AoE damage dealt by the 3-imp totem slam.
@export var stack_slam_damage: int = 35

## AoE radius in meters for the 3-imp totem slam impact.
@export var stack_slam_radius: float = 4.5

## Radius in meters within which [PoweredLight3D] nodes are forced to flicker.
@export var light_flicker_radius: float = 8.0

## Damage dealt when dive-bombing into water to electrify submerged targets.
@export var water_electrify_damage: int = 35

@export_category("VFX & Audio")
## Base interval in seconds between periodic maniacal imp laughs.
@export var laugh_base_interval: float = 7.5

## VFX scene spawned during telegraph charging.
@export var charge_vfx_scene: PackedScene = preload("res://vfx/imp/imp_charge_vfx.tscn")

## VFX scene spawned for direct line lightning.
@export var lightning_line_vfx_scene: PackedScene = preload("res://vfx/imp/imp_lightning_line.tscn")

## VFX scene spawned for 10m expanding lightning circle.
@export
var lightning_circle_vfx_scene: PackedScene = preload("res://vfx/imp/imp_lightning_circle.tscn")

## VFX scene spawned on explosion / slam / water dive-bomb.
@export var explosion_vfx_scene: PackedScene = preload("res://vfx/imp/imp_explosion_vfx.tscn")

## Homing orb projectile scene spawned by [method start_homing_orbs_attack].
@export var homing_orb_scene: PackedScene = HOMING_ORB_SCENE

@export_category("Components")
## Optional manual reference to [HealthComponent].
@export var health_component: HealthComponent = null

## Optional manual reference to [FactionComponent].
@export var faction_component: FactionComponent = null

## Optional manual reference to [TacticalAgent].
@export var tactical_agent: TacticalAgent = null

## Optional manual reference to [NavigationAgent3D].
@export var nav_agent: NavigationAgent3D = null

## Optional manual reference to [VisibleOnScreenNotifier3D].
@export var visibility_notifier: VisibleOnScreenNotifier3D = null

## Optional manual reference to [AnimationPlayer].
@export var animation_player: AnimationPlayer = null

## Optional manual reference to [ImpMoodComponent].
@export var mood_component: ImpMoodComponent = null

## Current active [enum ImpState].
var current_state: ImpState = ImpState.IDLE

## Current hostile target node.
var target: Node3D = null

var _gravity: float = 9.8
var _state_token: int = 0
var _is_on_screen: bool = true
var _can_attack: bool = true
var _can_spawn_shield: bool = true
var _active_shield: HexShieldSphere = null
var _active_charge_vfx: Node3D = null
var _flickered_lights: Dictionary[PoweredLight3D, int] = {}
var _waddle_phase: float = 0.0
var _think_accum: float = 0.0
var _stack_leader: EnemyImp = null
var _stack_slot: int = 0
var _leap_target_pos: Vector3 = Vector3.ZERO
var _dive_water_node: Node3D = null
var _visual_root: Node3D = null
var _detection_area: Area3D = null
var _los_ray: RayCast3D = null
var _obstacle_low_ray: RayCast3D = null
var _obstacle_mid_ray: RayCast3D = null
var _locked_aim_point: Vector3 = Vector3.ZERO
var _aim_locked: bool = false
var _aim_beam_mesh: MeshInstance3D = null
var _aim_beam_mat: StandardMaterial3D = null
var _orbiting_orbs: Array[ImpHomingOrb] = []
var _hits_since_shield: int = 0
var _proactive_shield_timer: float = 6.0
var _leap_cooldown_timer: float = 0.0
var _strafe_timer: float = 1.5
var _strafe_sign: float = 1.0
var _laugh_timer: float = 4.5
var _stack_slam_cooldown_timer: float = 0.0


## Initializes components, collision layers, sensors, and disables idle processing.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	add_to_group(GROUP_ENEMY)
	add_to_group(&"damageable")
	add_to_group(&"tactical_agent")

	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	collision_layer = CollisionLayers.MASK_ENEMIES
	collision_mask = (
		CollisionLayers.MASK_ENVIRONMENT
		| CollisionLayers.MASK_PLAYER
		| CollisionLayers.MASK_ENEMIES
	)

	var grav_var: Variant = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if grav_var is float:
		_gravity = grav_var

	_ensure_components()
	_ensure_collision_shape()
	_ensure_visual_root()
	_build_sensors()
	_build_aim_beam()
	_reset_proactive_shield_timer()
	_reset_laugh_timer()

	assert(is_instance_valid(health_component), "EnemyImp: Missing HealthComponent.")
	assert(is_instance_valid(faction_component), "EnemyImp: Missing FactionComponent.")
	assert(is_instance_valid(nav_agent), "EnemyImp: Missing NavigationAgent3D.")
	assert(is_instance_valid(visibility_notifier), "EnemyImp: Missing VisibleOnScreenNotifier3D.")
	assert(is_instance_valid(mood_component), "EnemyImp: Missing ImpMoodComponent.")

	Events.enemy_spawned.emit(self)
	print("EnemyImp: Initialized at ", global_position)


## Restores any flickered [PoweredLight3D] nodes and cleans up active shield/VFX/orbs.
func _exit_tree() -> void:
	_restore_all_lights()
	_clear_charge_vfx()
	_clear_orbiting_orbs()
	_hide_aim_beam()
	_despawn_hex_shield()


## Executes state-driven movement, leaps, aim-freeze tracking, stacking, and environment checks.
func _physics_process(delta: float) -> void:
	if current_state == ImpState.DEAD:
		return

	if current_state != ImpState.STACK_MOUNT and not is_on_floor():
		velocity.y -= _gravity * delta

	_leap_cooldown_timer = maxf(0.0, _leap_cooldown_timer - delta)
	_stack_slam_cooldown_timer = maxf(0.0, _stack_slam_cooldown_timer - delta)
	_tick_laugh(delta)

	if (
		current_state == ImpState.CHASE
		or current_state == ImpState.CHARGE_LINE
		or current_state == ImpState.CHARGE_AOE
		or current_state == ImpState.CHARGE_ORBS
	):
		_tick_proactive_shield(delta)

	_think_accum += delta
	if _think_accum >= 0.25:
		_think_accum = 0.0
		_update_nearby_lights()
		if current_state == ImpState.CHASE:
			_check_water_dive_opportunity()
			_check_autonomous_stack_slam()

	match current_state:
		ImpState.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, waddle_speed * 6.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, waddle_speed * 6.0 * delta)
			_play_anim(&"idle")
		ImpState.CHASE:
			_process_chase(delta)
		ImpState.LEAP:
			_process_leap(delta)
		ImpState.CHARGE_LINE:
			_process_charge_line(delta)
		ImpState.CHARGE_AOE, ImpState.CHARGE_ORBS:
			velocity.x = move_toward(velocity.x, 0.0, waddle_speed * 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, waddle_speed * 8.0 * delta)
			if is_instance_valid(target):
				_face_position(target.global_position, delta * 8.0)
		ImpState.STACK_MOUNT:
			_process_stack_mount(delta)
		ImpState.STACK_SLAM:
			_process_stack_slam(delta)
		ImpState.WATER_DIVE:
			_process_water_dive(delta)

	if current_state != ImpState.STACK_MOUNT and current_state != ImpState.DEAD:
		move_and_slide()
		_update_waddle_visual(delta)


## Applies incoming damage, updates shield hit cadence, and triggers dodge-hops or hit react.
func take_damage(
	amount: int, _hit_pos: Vector3 = Vector3.ZERO, shot_dir: Vector3 = Vector3.ZERO
) -> void:
	if current_state == ImpState.DEAD or amount <= 0:
		return

	if is_instance_valid(_active_shield):
		_active_shield.take_damage(amount, _hit_pos, shot_dir)
		return

	if is_instance_valid(health_component):
		health_component.take_damage(amount)
	if is_instance_valid(tactical_agent):
		tactical_agent.apply_damage(float(amount))

	if current_state != ImpState.DEAD:
		AudioPool.play_sfx_3d(SFX_GRUNT, global_position)
		_play_anim(&"hit_react")
		_hits_since_shield += 1
		_try_spawn_hex_shield(true)
		_try_reactive_dodge_hop()


## Initiates a ballistic jump/leap toward [param dest_pos].
func perform_leap(dest_pos: Vector3) -> void:
	if current_state == ImpState.DEAD:
		return
	_leap_target_pos = dest_pos
	var to_dest: Vector3 = dest_pos - global_position
	to_dest.y = 0.0
	var horiz_dir: Vector3 = (
		to_dest.normalized() if to_dest.length_squared() > 0.001 else Vector3.ZERO
	)
	velocity.x = horiz_dir.x * leap_horizontal_speed
	velocity.z = horiz_dir.z * leap_horizontal_speed
	velocity.y = jump_velocity
	_set_state(ImpState.LEAP)
	_play_anim(&"jump")


## Starts telegraph charging for direct line lightning with aim-freeze dodge window.
func start_line_lightning_attack() -> void:
	if current_state == ImpState.DEAD or not _can_attack:
		return
	_can_attack = false
	_state_token += 1
	var token: int = _state_token
	_aim_locked = false

	var origin: Vector3 = global_position + Vector3(0.0, 0.7, 0.0)
	if is_instance_valid(target):
		_locked_aim_point = target.global_position + Vector3(0.0, 0.9, 0.0)
	else:
		_locked_aim_point = origin + (-global_transform.basis.z) * line_lightning_range

	_set_state(ImpState.CHARGE_LINE)
	_play_anim(&"charge_lightning")
	_spawn_charge_vfx()
	_update_aim_beam_visual(origin, _locked_aim_point, false)
	telegraph_started.emit(&"line_lightning")
	print("EnemyImp: Charging direct line lightning with aim-freeze window.")

	var freeze_window: float = minf(aim_freeze_duration, line_charge_duration * 0.4)
	var track_duration: float = maxf(0.01, line_charge_duration - freeze_window)

	var lock_timer: SceneTreeTimer = get_tree().create_timer(track_duration)
	lock_timer.timeout.connect(_on_line_aim_locked.bind(token))

	var fire_timer: SceneTreeTimer = get_tree().create_timer(line_charge_duration)
	fire_timer.timeout.connect(_on_line_charge_finished.bind(token))


## Starts telegraph charging for the 10m diameter (5m radius) expanding circle AoE.
func start_aoe_circle_attack() -> void:
	if current_state == ImpState.DEAD or not _can_attack:
		return
	_can_attack = false
	_state_token += 1
	var token: int = _state_token
	_set_state(ImpState.CHARGE_AOE)
	_play_anim(&"charge_lightning")
	_spawn_charge_vfx()
	telegraph_started.emit(&"aoe_circle")
	print("EnemyImp: Charging 10m expanding lightning circle.")

	var timer: SceneTreeTimer = get_tree().create_timer(aoe_charge_duration)
	timer.timeout.connect(_on_aoe_charge_finished.bind(token))


## Starts telegraph charging and spawns orbiting [ImpHomingOrb] projectiles.
func start_homing_orbs_attack() -> void:
	if current_state == ImpState.DEAD or not _can_attack:
		return
	_can_attack = false
	_state_token += 1
	var token: int = _state_token
	_set_state(ImpState.CHARGE_ORBS)
	_play_anim(&"charge_lightning")
	_spawn_charge_vfx()
	_spawn_orbiting_orbs()
	telegraph_started.emit(&"homing_orbs")
	print("EnemyImp: Charging homing electric orbs.")

	var timer: SceneTreeTimer = get_tree().create_timer(orb_charge_duration)
	timer.timeout.connect(_on_orb_charge_finished.bind(token))


## Mounts this imp onto [param leader] at [param slot_index] for a 3-imp totem slam.
func begin_stack_slam(slot_index: int, leader: EnemyImp, slam_target_pos: Vector3) -> void:
	if current_state == ImpState.DEAD:
		return
	_stack_slot = clampi(slot_index, 0, 2)
	_stack_leader = leader
	_leap_target_pos = slam_target_pos
	_stack_slam_cooldown_timer = AUTONOMOUS_STACK_COOLDOWN
	_set_state(ImpState.STACK_MOUNT)
	_play_anim(&"stack_mount")
	set_physics_process(true)
	print("EnemyImp: Joined 3-imp stack at slot ", _stack_slot)

	if _stack_slot == 0:
		var token: int = _state_token
		var timer: SceneTreeTimer = get_tree().create_timer(0.85)
		timer.timeout.connect(_on_stack_ready_to_slam.bind(token, slam_target_pos))


## Launches this imp into the slam phase toward [param slam_target_pos].
func execute_stack_slam(slam_target_pos: Vector3) -> void:
	if current_state == ImpState.DEAD:
		return
	_stack_leader = null
	_leap_target_pos = slam_target_pos
	var to_target: Vector3 = slam_target_pos - global_position
	to_target.y = 0.0
	var horiz: Vector3 = (
		to_target.normalized() if to_target.length_squared() > 0.001 else Vector3.ZERO
	)
	velocity = Vector3(
		horiz.x * leap_horizontal_speed, jump_velocity * 0.9, horiz.z * leap_horizontal_speed
	)
	_set_state(ImpState.STACK_SLAM)
	_play_anim(&"jump")
	set_physics_process(true)


## Initiates a suicidal dive-bomb into [param water_node] to electrify the water.
func begin_water_dive(water_node: Node3D) -> void:
	if current_state == ImpState.DEAD or not is_instance_valid(water_node):
		return
	_dive_water_node = water_node
	var dive_dest: Vector3 = water_node.global_position
	if is_instance_valid(target):
		dive_dest = Vector3(
			target.global_position.x, water_node.global_position.y, target.global_position.z
		)
	_leap_target_pos = dive_dest
	var to_dest: Vector3 = dive_dest - global_position
	to_dest.y = 0.0
	var horiz: Vector3 = to_dest.normalized() if to_dest.length_squared() > 0.001 else Vector3.ZERO
	velocity = Vector3(
		horiz.x * leap_horizontal_speed * 1.15,
		jump_velocity,
		horiz.z * leap_horizontal_speed * 1.15
	)
	_set_state(ImpState.WATER_DIVE)
	_play_anim(&"dive_bomb")
	set_physics_process(true)
	print("EnemyImp: Dive-bombing into water -> ", water_node.name)


## Returns true if line lightning aim is currently frozen on [member _locked_aim_point].
func is_aim_locked() -> bool:
	return _aim_locked


## Returns the current or frozen line lightning aim point in world space.
func get_locked_aim_point() -> Vector3:
	return _locked_aim_point


## Checks for 3 living Imps within 12m and initiates an autonomous stack slam if eligible.
func try_autonomous_stack_slam(ignore_chance: bool = false) -> bool:
	if _stack_slam_cooldown_timer > 0.0 or not is_instance_valid(target) or not is_on_floor():
		return false
	if current_state != ImpState.CHASE:
		return false

	var allies: Array[EnemyImp] = []
	var nodes: Array[Node] = get_tree().get_nodes_in_group(GROUP_ENEMY)
	for node: Node in nodes:
		if not node is EnemyImp or node == self:
			continue
		var ally: EnemyImp = node as EnemyImp
		if ally.current_state != ImpState.CHASE and ally.current_state != ImpState.IDLE:
			continue
		if ally._stack_slam_cooldown_timer > 0.0:
			continue
		if ally.global_position.distance_squared_to(global_position) <= AUTONOMOUS_STACK_RADIUS_SQ:
			allies.append(ally)

	if allies.size() < 2:
		return false

	var my_id: int = get_instance_id()
	if not ignore_chance:
		for ally: EnemyImp in allies:
			if ally.current_state == ImpState.CHASE and ally.get_instance_id() < my_id:
				return false
		var slam_bias: float = (
			mood_component.get_stack_slam_bias() if is_instance_valid(mood_component) else 0.55
		)
		if randf() > slam_bias:
			return false

	var slam_target: Vector3 = target.global_position
	begin_stack_slam(0, self, slam_target)
	allies[0].begin_stack_slam(1, self, slam_target)
	allies[1].begin_stack_slam(2, self, slam_target)
	return true


## Deploys [HexShieldSphere] proactively or on hit cadence without any HP lockout.
func _try_spawn_hex_shield(from_hit: bool = true) -> bool:
	if not _can_spawn_shield or is_instance_valid(_active_shield) or current_state == ImpState.DEAD:
		return false

	if from_hit and _hits_since_shield < maxi(shield_hit_cadence, 1):
		var bias: float = (
			mood_component.get_shield_bias() if is_instance_valid(mood_component) else 0.4
		)
		var spawn_chance: float = lerpf(hex_shield_min_chance, hex_shield_max_chance, bias)
		if randf() > spawn_chance:
			return false

	return _deploy_hex_shield()


## Instantiates and activates [HexShieldSphere] around this imp and starts cooldown timers.
func _deploy_hex_shield() -> bool:
	if not _can_spawn_shield or is_instance_valid(_active_shield) or current_state == ImpState.DEAD:
		return false

	_can_spawn_shield = false
	_hits_since_shield = 0
	_reset_proactive_shield_timer()

	var shield_node: Node = HEX_SHIELD_SCENE.instantiate()
	if not shield_node is HexShieldSphere:
		if is_instance_valid(shield_node):
			shield_node.queue_free()
		return false

	var shield: HexShieldSphere = shield_node as HexShieldSphere
	shield.name = "ReactiveHexShield"
	shield.radius = hex_shield_radius
	shield.max_health = hex_shield_health
	shield.auto_generate = true
	shield.position = Vector3(0.0, 0.55, 0.0)
	add_child(shield)
	_active_shield = shield
	Utilities.safe_connect(shield.shield_destroyed, _on_hex_shield_destroyed)
	print("EnemyImp: HexShieldSphere deployed.")

	var cd_mult: float = (
		mood_component.get_shield_cooldown_multiplier()
		if is_instance_valid(mood_component)
		else 1.0
	)
	var token: int = _state_token
	var dur_timer: SceneTreeTimer = get_tree().create_timer(hex_shield_duration)
	dur_timer.timeout.connect(_on_hex_shield_expired.bind(token))

	var cd_timer: SceneTreeTimer = get_tree().create_timer(maxf(0.5, hex_shield_cooldown * cd_mult))
	cd_timer.timeout.connect(_on_hex_shield_cooldown_ready.bind(token))
	return true


## Advances proactive combat shield timer and deploys shield even when not taking hits.
func _tick_proactive_shield(delta: float) -> void:
	if not _can_spawn_shield or is_instance_valid(_active_shield) or current_state == ImpState.DEAD:
		return
	_proactive_shield_timer -= delta
	if _proactive_shield_timer <= 0.0:
		_reset_proactive_shield_timer()
		_try_spawn_hex_shield(false)


## Resets proactive shield interval scaled by [member mood_component].
func _reset_proactive_shield_timer() -> void:
	var mult: float = (
		mood_component.get_shield_cooldown_multiplier()
		if is_instance_valid(mood_component)
		else 1.0
	)
	_proactive_shield_timer = maxf(1.5, proactive_shield_interval * mult)


## Advances periodic laugh timer and plays maniacal laugh SFX on expiry.
func _tick_laugh(delta: float) -> void:
	_laugh_timer -= delta
	if _laugh_timer <= 0.0:
		_reset_laugh_timer()
		_play_laugh_sfx()


## Resets periodic laugh timer scaled by [member mood_component].
func _reset_laugh_timer() -> void:
	var mult: float = (
		mood_component.get_laugh_interval_multiplier() if is_instance_valid(mood_component) else 1.0
	)
	_laugh_timer = maxf(1.5, laugh_base_interval * mult * randf_range(0.75, 1.25))


## Plays one of the two dry maniacal imp laugh clips at [member global_position].
func _play_laugh_sfx() -> void:
	var clip: AudioStream = SFX_LAUGH_01 if randf() < 0.5 else SFX_LAUGH_02
	AudioPool.play_sfx_3d(clip, global_position)


## Updates tracking beam toward [member target] until aim locks for the dodge window.
func _process_charge_line(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, waddle_speed * 8.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, waddle_speed * 8.0 * delta)
	var origin: Vector3 = global_position + Vector3(0.0, 0.7, 0.0)
	if not _aim_locked and is_instance_valid(target):
		_locked_aim_point = target.global_position + Vector3(0.0, 0.9, 0.0)
		_face_position(target.global_position, delta * 10.0)
		_update_aim_beam_visual(origin, _locked_aim_point, false)
	elif _aim_locked:
		_update_aim_beam_visual(origin, _locked_aim_point, true)


## Fires direct line lightning along the frozen [member _locked_aim_point] vector.
func _fire_line_lightning() -> void:
	_hide_aim_beam()
	_clear_charge_vfx()
	if current_state == ImpState.DEAD:
		return

	var origin: Vector3 = global_position + Vector3(0.0, 0.7, 0.0)
	var delta_aim: Vector3 = _locked_aim_point - origin
	var aim_dir: Vector3 = (
		delta_aim.normalized() if delta_aim.length_squared() > 0.001 else -global_transform.basis.z
	)

	var end_pos: Vector3 = origin + aim_dir * line_lightning_range
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if is_instance_valid(space_state):
		var exclude_rids: Array[RID] = [get_rid()]
		var hit: Dictionary = Utilities.raycast_3d(
			space_state,
			origin,
			end_pos,
			CollisionLayers.MASK_SOLID_WORLD | CollisionLayers.MASK_PLAYER,
			exclude_rids
		)
		if not hit.is_empty():
			var pos_var: Variant = hit.get("position", end_pos)
			if pos_var is Vector3:
				end_pos = pos_var
			var col_var: Variant = hit.get("collider", null)
			if col_var is Node:
				_apply_electric_damage_to_node(col_var as Node, line_lightning_damage)

	_spawn_line_vfx(origin, end_pos)
	AudioPool.play_sfx_3d(SFX_ELECTRIC, origin)
	electricity_attack_fired.emit(&"line_lightning", end_pos)
	_schedule_attack_cooldown()
	_set_state(ImpState.CHASE)


## Spawns a 10m expanding lightning circle AoE centered on the imp.
func _fire_aoe_circle() -> void:
	_clear_charge_vfx()
	if current_state == ImpState.DEAD:
		return

	var center: Vector3 = global_position
	_spawn_circle_vfx(center, aoe_circle_radius)
	AudioPool.play_sfx_3d(SFX_ELECTRIC, center)
	_apply_radial_electric_damage(center, aoe_circle_radius, aoe_lightning_damage)
	electricity_attack_fired.emit(&"aoe_circle", center)
	_schedule_attack_cooldown()
	_set_state(ImpState.CHASE)


## Deals [param amount] electric damage if [param node] has a hostile [HealthComponent].
func _apply_electric_damage_to_node(node: Node, amount: int) -> void:
	if not is_instance_valid(node) or node == self:
		return
	var other_faction: FactionComponent = FactionComponent.get_faction_component(node)
	if is_instance_valid(other_faction) and is_instance_valid(faction_component):
		if not faction_component.is_hostile_to(other_faction):
			return
	var hc: HealthComponent = _find_health_component(node)
	if is_instance_valid(hc):
		hc.take_damage(amount)
		if is_instance_valid(tactical_agent):
			tactical_agent.report_target_damaged(float(amount))


## Applies [param amount] damage to all hostile actors within [param radius] of [param center].
func _apply_radial_electric_damage(center: Vector3, radius: float, amount: int) -> void:
	var radius_sq: float = radius * radius
	var candidates: Array[Node] = get_tree().get_nodes_in_group(&"player")
	for candidate: Node in candidates:
		if candidate is Node3D:
			var n3d: Node3D = candidate as Node3D
			if n3d.global_position.distance_squared_to(center) <= radius_sq:
				_apply_electric_damage_to_node(n3d, amount)


## Navigates toward [member target] with direct-steering fallback, obstacle leaps, and strafing.
func _process_chase(delta: float) -> void:
	if not is_instance_valid(target):
		_set_state(ImpState.IDLE)
		return

	var dist_sq: float = global_position.distance_squared_to(target.global_position)
	if dist_sq > deaggro_dist_sq:
		target = null
		_set_state(ImpState.IDLE)
		return

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_sign = -_strafe_sign
		_strafe_timer = randf_range(1.1, 2.1)

	var move_target: Vector3 = _resolve_chase_move_target()
	var move_dir: Vector3 = move_target - global_position
	move_dir.y = 0.0

	if move_dir.length_squared() > 0.01:
		var forward_dir: Vector3 = move_dir.normalized()
		var side_dir: Vector3 = Vector3(-forward_dir.z, 0.0, forward_dir.x) * _strafe_sign
		var strafe_bias: float = (
			mood_component.get_strafe_bias() if is_instance_valid(mood_component) else 0.35
		)
		var strafe_scale: float = strafe_bias * 0.65 if dist_sq <= 144.0 else 0.0
		var desired_dir: Vector3 = (forward_dir + side_dir * strafe_scale).normalized()
		var speed_mult: float = (
			mood_component.get_speed_multiplier() if is_instance_valid(mood_component) else 1.0
		)
		var effective_speed: float = waddle_speed * speed_mult
		velocity.x = desired_dir.x * effective_speed
		velocity.z = desired_dir.z * effective_speed
		_face_position(move_target, delta * 8.0)
		_play_anim(&"run")

		if is_on_floor() and _leap_cooldown_timer <= 0.0:
			if _should_leap_obstacle():
				_leap_cooldown_timer = 1.25
				perform_leap(global_position + forward_dir * 2.6 + Vector3(0.0, 1.2, 0.0))
				return
			if _should_playful_or_evasive_hop():
				_leap_cooldown_timer = 1.9
				_play_laugh_sfx()
				perform_leap(global_position + side_dir * 2.8)
				return
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_anim(&"idle")

	if _can_attack and dist_sq <= attack_range_sq and is_on_floor():
		_choose_and_start_attack(dist_sq)


## Resolves navmesh waypoint or falls back to direct steering when no valid path exists.
func _resolve_chase_move_target() -> Vector3:
	if not is_instance_valid(target):
		return global_position
	var direct_pos: Vector3 = target.global_position
	if not is_instance_valid(nav_agent):
		return direct_pos
	nav_agent.target_position = direct_pos
	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var nav_delta: Vector3 = next_pos - global_position
	nav_delta.y = 0.0
	if nav_delta.length_squared() <= 0.04:
		return direct_pos
	return next_pos


## Picks AoE circle, line lightning, or homing orbs based on distance and line-of-sight.
func _choose_and_start_attack(dist_sq: float) -> void:
	if dist_sq <= (aoe_circle_radius * aoe_circle_radius):
		start_aoe_circle_attack()
		return
	if not _has_line_of_sight_to_target():
		start_homing_orbs_attack()
		return
	if randf() < 0.45:
		start_homing_orbs_attack()
		return
	start_line_lightning_attack()


## Returns true if forward low raycast hits a jumpable crate/ledge without mid blockage.
func _should_leap_obstacle() -> bool:
	if not is_instance_valid(_obstacle_low_ray) or not is_instance_valid(_obstacle_mid_ray):
		return false
	_obstacle_low_ray.force_raycast_update()
	if not _obstacle_low_ray.is_colliding():
		return false
	_obstacle_mid_ray.force_raycast_update()
	if not _obstacle_mid_ray.is_colliding():
		return true
	if is_instance_valid(target) and target.global_position.y > global_position.y + 0.5:
		return true
	return false


## Returns true when mood-weighted playful hop or evasive strafe-hop triggers.
func _should_playful_or_evasive_hop() -> bool:
	if not is_instance_valid(mood_component):
		return false
	var hop_freq: float = mood_component.get_hop_taunt_frequency()
	return randf() < (hop_freq * 0.03)


## Triggers an evasive lateral dodge-hop upon taking damage if grounded and off cooldown.
func _try_reactive_dodge_hop() -> void:
	if not is_on_floor() or _leap_cooldown_timer > 0.0:
		return
	if (
		current_state == ImpState.STACK_MOUNT
		or current_state == ImpState.STACK_SLAM
		or current_state == ImpState.WATER_DIVE
	):
		return
	var dodge_prob: float = (
		mood_component.get_dodge_probability() if is_instance_valid(mood_component) else 0.25
	)
	if randf() < dodge_prob:
		_leap_cooldown_timer = 1.6
		var side_dir: Vector3 = global_transform.basis.x * _strafe_sign
		perform_leap(global_position + side_dir * 3.0)


## Checks direct line-of-sight to [member target] using [member _los_ray].
func _has_line_of_sight_to_target() -> bool:
	if not is_instance_valid(target) or not is_instance_valid(_los_ray):
		return true
	var target_center: Vector3 = target.global_position + Vector3(0.0, 0.9, 0.0)
	_los_ray.target_position = _los_ray.to_local(target_center)
	_los_ray.force_raycast_update()
	if not _los_ray.is_colliding():
		return true
	return _los_ray.get_collider() == target


## Handles mid-air leap traversal until landing on the floor.
func _process_leap(_delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		_set_state(ImpState.CHASE)


## Tracks stacked position above [member _stack_leader] during 3-imp totem formation.
func _process_stack_mount(_delta: float) -> void:
	if _stack_slot == 0:
		velocity = Vector3.ZERO
		return
	if not is_instance_valid(_stack_leader) or _stack_leader.current_state == ImpState.DEAD:
		_stack_leader = null
		_set_state(ImpState.CHASE)
		return
	if _stack_leader.current_state == ImpState.STACK_SLAM:
		execute_stack_slam(_leap_target_pos)
		return
	var desired_pos: Vector3 = (
		_stack_leader.global_position + Vector3(0.0, float(_stack_slot) * STACK_SLOT_HEIGHT, 0.0)
	)
	global_position = global_position.lerp(desired_pos, 0.35)
	velocity = Vector3.ZERO


## Handles 3-imp stack slam landing impact AoE.
func _process_stack_slam(_delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		_spawn_explosion_vfx(global_position)
		AudioPool.play_sfx_3d(SFX_ELECTRIC, global_position)
		_apply_radial_electric_damage(global_position, stack_slam_radius, stack_slam_damage)
		_set_state(ImpState.CHASE)


## Handles suicidal water dive-bomb impact, water electrification, and self-destruction.
func _process_water_dive(_delta: float) -> void:
	var hit_water: bool = is_on_floor() and velocity.y <= 0.0
	if is_instance_valid(_dive_water_node):
		if global_position.y <= _dive_water_node.global_position.y + 0.5:
			hit_water = true

	if hit_water:
		_detonate_water_dive()


## Detonates the imp in the water, electrifying submerged targets and killing the imp.
func _detonate_water_dive() -> void:
	var impact_pos: Vector3 = global_position
	_spawn_explosion_vfx(impact_pos)
	_spawn_circle_vfx(impact_pos, aoe_circle_radius)
	AudioPool.play_sfx_3d(SFX_SPLASH, impact_pos)
	AudioPool.play_sfx_3d(SFX_ELECTRIC, impact_pos)

	if is_instance_valid(_dive_water_node):
		if _dive_water_node.has_method(&"spawn_ripple"):
			_dive_water_node.call(&"spawn_ripple", impact_pos, 2.5)
		_electrify_water_occupants(_dive_water_node)

	water_dive_exploded.emit(_dive_water_node, impact_pos)
	if is_instance_valid(health_component) and health_component.current_health > 0:
		health_component.take_damage(health_component.current_health)


## Electrifies all hostile actors currently inside [param water_node].
func _electrify_water_occupants(water_node: Node3D) -> void:
	var swim_area: Area3D = water_node.get_node_or_null("SwimmableArea3D") as Area3D
	if not is_instance_valid(swim_area):
		_apply_radial_electric_damage(water_node.global_position, 8.0, water_electrify_damage)
		return

	var bodies: Array[Node3D] = swim_area.get_overlapping_bodies()
	for body: Node3D in bodies:
		_apply_electric_damage_to_node(body, water_electrify_damage)


## Checks if [member target] is currently standing inside a water volume to trigger dive-bomb.
func _check_water_dive_opportunity() -> void:
	if not is_instance_valid(target):
		return
	var water_areas: Array[Node] = get_tree().get_nodes_in_group(GROUP_WATER_AREA)
	for area_node: Node in water_areas:
		if area_node is Area3D:
			var area: Area3D = area_node as Area3D
			if area.overlaps_body(target):
				var parent_water: Node3D = area.get_parent() as Node3D
				if is_instance_valid(parent_water):
					begin_water_dive(parent_water)
					return


## Triggers autonomous 3-imp stack slam check when 3 imps cluster within 12m.
func _check_autonomous_stack_slam() -> void:
	try_autonomous_stack_slam(false)


## Triggers random [enum PoweredLight3D.FlickerPreset] on lights within radius and restores others.
func _update_nearby_lights() -> void:
	var radius_sq: float = light_flicker_radius * light_flicker_radius
	var lights: Array[PoweredLight3D] = _gather_powered_lights()
	var in_range: Dictionary[PoweredLight3D, bool] = {}

	for light_node: PoweredLight3D in lights:
		if not is_instance_valid(light_node):
			continue
		if light_node.global_position.distance_squared_to(global_position) <= radius_sq:
			in_range[light_node] = true
			if not _flickered_lights.has(light_node):
				_flickered_lights[light_node] = int(light_node.flicker_preset)
				var random_preset: int = FLICKER_CHOICES[randi() % FLICKER_CHOICES.size()]
				light_node.set_flicker_preset(random_preset as PoweredLight3D.FlickerPreset)

	var to_restore: Array[PoweredLight3D] = []
	for tracked: PoweredLight3D in _flickered_lights.keys():
		if not is_instance_valid(tracked) or not in_range.has(tracked):
			to_restore.append(tracked)

	for restore_light: PoweredLight3D in to_restore:
		var orig_preset: int = _flickered_lights[restore_light]
		if is_instance_valid(restore_light):
			restore_light.set_flicker_preset(orig_preset as PoweredLight3D.FlickerPreset)
		_flickered_lights.erase(restore_light)


## Restores original flicker presets on all tracked [PoweredLight3D] nodes.
func _restore_all_lights() -> void:
	for light_node: PoweredLight3D in _flickered_lights.keys():
		if is_instance_valid(light_node):
			var orig_preset: int = _flickered_lights[light_node]
			light_node.set_flicker_preset(orig_preset as PoweredLight3D.FlickerPreset)
	_flickered_lights.clear()


## Collects [PoweredLight3D] nodes from the current scene tree recursively.
func _gather_powered_lights() -> Array[PoweredLight3D]:
	var result: Array[PoweredLight3D] = []
	var root: Node = get_tree().root
	if not is_instance_valid(root):
		return result
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var curr: Node = stack.pop_back()
		if curr is PoweredLight3D:
			result.append(curr as PoweredLight3D)
		for child: Node in curr.get_children():
			stack.append(child)
	return result


## Applies a fat-imp side-to-side waddle roll to [member _visual_root] while moving.
func _update_waddle_visual(delta: float) -> void:
	if not _is_on_screen or not is_instance_valid(_visual_root):
		return
	var horiz_speed_sq: float = velocity.x * velocity.x + velocity.z * velocity.z
	if is_on_floor() and horiz_speed_sq > 0.25:
		_waddle_phase += delta * 11.0
		_visual_root.rotation.z = sin(_waddle_phase) * 0.14
	else:
		_visual_root.rotation.z = move_toward(_visual_root.rotation.z, 0.0, delta * 8.0)


## Smoothly rotates the imp around Y toward [param target_pos].
func _face_position(target_pos: Vector3, weight: float) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return
	var target_yaw: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(weight, 0.0, 1.0))


## Transitions [member current_state], cleans up interrupted telegraphs, and emits signal.
func _set_state(new_state: ImpState) -> void:
	if current_state == new_state:
		return
	if current_state == ImpState.CHARGE_LINE and new_state != ImpState.CHARGE_LINE:
		_aim_locked = false
		_hide_aim_beam()
	if current_state == ImpState.CHARGE_ORBS and new_state != ImpState.CHARGE_ORBS:
		_clear_charge_vfx()
	current_state = new_state
	state_changed.emit(new_state)
	print("EnemyImp: State -> ", new_state)


## Plays [param anim_name] on [member animation_player] if available.
func _play_anim(anim_name: StringName) -> void:
	if is_instance_valid(animation_player) and animation_player.has_animation(anim_name):
		if animation_player.current_animation != String(anim_name):
			animation_player.play(anim_name)


## Spawns telegraph charge VFX attached to the imp.
func _spawn_charge_vfx() -> void:
	_clear_charge_vfx()
	if charge_vfx_scene == null:
		return
	var inst: Node = charge_vfx_scene.instantiate()
	if inst is Node3D:
		var vfx_3d: Node3D = inst as Node3D
		vfx_3d.position = Vector3(0.0, 0.65, 0.0)
		add_child(vfx_3d)
		_active_charge_vfx = vfx_3d
		if vfx_3d is ImpChargeVFX:
			(vfx_3d as ImpChargeVFX).start_charge(0.0)


## Frees active telegraph charge VFX if present.
func _clear_charge_vfx() -> void:
	if is_instance_valid(_active_charge_vfx):
		if _active_charge_vfx is ImpChargeVFX:
			(_active_charge_vfx as ImpChargeVFX).stop_charge()
		_active_charge_vfx.queue_free()
	_active_charge_vfx = null


## Spawns [member orb_count] orbiting [ImpHomingOrb] projectiles above the imp.
func _spawn_orbiting_orbs() -> void:
	_clear_orbiting_orbs()
	if homing_orb_scene == null or not is_inside_tree():
		return
	var world_parent: Node = _get_world_container()
	var count: int = clampi(orb_count, 1, 5)
	for idx: int in range(count):
		var inst: Node = homing_orb_scene.instantiate()
		if not inst is ImpHomingOrb:
			if is_instance_valid(inst):
				inst.queue_free()
			continue
		var orb: ImpHomingOrb = inst as ImpHomingOrb
		world_parent.add_child(orb)
		var angle_offset: float = (TAU / float(count)) * float(idx)
		orb.setup_orbit(self, angle_offset, target, orb_charge_duration + 0.1)
		_orbiting_orbs.append(orb)


## Cancels any still-orbiting orbs (e.g. if imp dies mid-charge).
func _clear_orbiting_orbs() -> void:
	for orb: ImpHomingOrb in _orbiting_orbs:
		if is_instance_valid(orb) and orb.is_orbiting:
			orb.cancel_orb()
	_orbiting_orbs.clear()


## Builds the thin targeting laser mesh used during line lightning telegraph & aim lock.
func _build_aim_beam() -> void:
	_aim_beam_mesh = get_node_or_null("AimBeamMesh") as MeshInstance3D
	if not is_instance_valid(_aim_beam_mesh):
		_aim_beam_mesh = MeshInstance3D.new()
		_aim_beam_mesh.name = "AimBeamMesh"
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.015
		cyl.bottom_radius = 0.015
		cyl.height = 1.0
		cyl.radial_segments = 6
		_aim_beam_mesh.mesh = cyl
		add_child(_aim_beam_mesh)

	_aim_beam_mat = StandardMaterial3D.new()
	_aim_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_beam_mat.albedo_color = Color(0.25, 0.85, 1.0, 0.55)
	_aim_beam_mat.emission_enabled = true
	_aim_beam_mat.emission = Color(0.2, 0.8, 1.0, 1.0)
	_aim_beam_mat.emission_energy_multiplier = 4.0
	_aim_beam_mesh.material_override = _aim_beam_mat
	_aim_beam_mesh.layers = DEFAULT_RENDER_LAYERS
	_aim_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_beam_mesh.visible = false


## Positions and styles [member _aim_beam_mesh] between [param from_pos] and [param to_pos].
func _update_aim_beam_visual(from_pos: Vector3, to_pos: Vector3, locked: bool) -> void:
	if not is_instance_valid(_aim_beam_mesh) or not is_inside_tree():
		return
	var delta_vec: Vector3 = to_pos - from_pos
	var dist: float = delta_vec.length()
	if dist < 0.05:
		_aim_beam_mesh.visible = false
		return

	_aim_beam_mesh.visible = true
	var mid: Vector3 = (from_pos + to_pos) * 0.5
	_aim_beam_mesh.global_position = mid
	var dir: Vector3 = delta_vec / dist
	var up_ref: Vector3 = Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var basis_z: Vector3 = dir.cross(up_ref).normalized()
	var basis_x: Vector3 = basis_z.cross(dir).normalized()
	_aim_beam_mesh.global_transform.basis = Basis(basis_x, dir, basis_z)

	var width_scale: float = 2.6 if locked else 1.0
	_aim_beam_mesh.scale = Vector3(width_scale, dist, width_scale)

	if is_instance_valid(_aim_beam_mat):
		if locked:
			_aim_beam_mat.albedo_color = Color(0.85, 0.98, 1.0, 0.95)
			_aim_beam_mat.emission = Color(0.7, 0.95, 1.0, 1.0)
			_aim_beam_mat.emission_energy_multiplier = 10.0
		else:
			_aim_beam_mat.albedo_color = Color(0.25, 0.85, 1.0, 0.55)
			_aim_beam_mat.emission = Color(0.2, 0.8, 1.0, 1.0)
			_aim_beam_mat.emission_energy_multiplier = 4.0


## Hides the line lightning targeting beam.
func _hide_aim_beam() -> void:
	if is_instance_valid(_aim_beam_mesh):
		_aim_beam_mesh.visible = false


## Spawns and fires [ImpLightningLine] from [param from_pos] to [param to_pos].
func _spawn_line_vfx(from_pos: Vector3, to_pos: Vector3) -> void:
	var vfx_3d: Node3D = _instantiate_world_vfx(lightning_line_vfx_scene, from_pos)
	if vfx_3d is ImpLightningLine:
		var line_vfx: ImpLightningLine = vfx_3d as ImpLightningLine
		line_vfx.beam_finished.connect(line_vfx.queue_free)
		line_vfx.fire_beam(from_pos, to_pos, 0.22)


## Spawns and triggers [ImpLightningCircle] at [param center_pos] with [param radius].
func _spawn_circle_vfx(center_pos: Vector3, radius: float) -> void:
	var vfx_3d: Node3D = _instantiate_world_vfx(lightning_circle_vfx_scene, center_pos)
	if vfx_3d is ImpLightningCircle:
		var circle_vfx: ImpLightningCircle = vfx_3d as ImpLightningCircle
		circle_vfx.circle_finished.connect(circle_vfx.queue_free)
		circle_vfx.trigger_circle(center_pos, 0.12, 0.45, radius)


## Spawns and triggers [ImpExplosionVFX] at [param world_pos].
func _spawn_explosion_vfx(world_pos: Vector3) -> void:
	var vfx_3d: Node3D = _instantiate_world_vfx(explosion_vfx_scene, world_pos)
	if vfx_3d is ImpExplosionVFX:
		var exp_vfx: ImpExplosionVFX = vfx_3d as ImpExplosionVFX
		exp_vfx.explosion_finished.connect(exp_vfx.queue_free)
		exp_vfx.trigger_explosion(world_pos, 1.0)


## Instantiates a transient VFX scene in the world parent at [param spawn_pos].
func _instantiate_world_vfx(scene: PackedScene, spawn_pos: Vector3) -> Node3D:
	if scene == null or not is_inside_tree():
		return null
	var inst: Node = scene.instantiate()
	if not inst is Node3D:
		if is_instance_valid(inst):
			inst.queue_free()
		return null
	var vfx_3d: Node3D = inst as Node3D
	var parent_node: Node = _get_world_container()
	parent_node.add_child(vfx_3d)
	vfx_3d.global_position = spawn_pos
	return vfx_3d


## Returns the parent node used for world-space VFX and projectiles.
func _get_world_container() -> Node:
	var parent_node: Node = (
		get_parent() if is_instance_valid(get_parent()) else get_tree().current_scene
	)
	if not is_instance_valid(parent_node):
		parent_node = get_tree().root
	return parent_node


## Removes active reactive [HexShieldSphere] if still valid.
func _despawn_hex_shield() -> void:
	if is_instance_valid(_active_shield):
		_active_shield.queue_free()
	_active_shield = null


## Schedules electricity attack cooldown readiness scaled by [member mood_component].
func _schedule_attack_cooldown() -> void:
	var mult: float = (
		mood_component.get_attack_cooldown_multiplier()
		if is_instance_valid(mood_component)
		else 1.0
	)
	var token: int = _state_token
	var timer: SceneTreeTimer = get_tree().create_timer(maxf(0.2, attack_cooldown * mult))
	timer.timeout.connect(_on_attack_cooldown_ready.bind(token))


## Locates a [HealthComponent] on [param node] or its children.
func _find_health_component(node: Node) -> HealthComponent:
	if not is_instance_valid(node):
		return null
	if "health_component" in node:
		var prop_val: Variant = node.get("health_component")
		if prop_val is HealthComponent:
			return prop_val as HealthComponent
	var child_hc: Node = NodeQuery.find_first_child_of_type(node, HealthComponent)
	if child_hc is HealthComponent:
		return child_hc as HealthComponent
	return null


## Ensures mandatory components exist if instantiated programmatically without a scene.
func _ensure_components() -> void:
	if not is_instance_valid(faction_component):
		faction_component = (
			NodeQuery.find_first_child_of_type(self, FactionComponent) as FactionComponent
		)
	if not is_instance_valid(faction_component):
		faction_component = FactionComponent.new()
		faction_component.name = "FactionComponent"
		faction_component.faction = Types.Faction.ENEMY
		faction_component.hostile_mask = int(Types.Faction.PLAYER)
		add_child(faction_component)

	if not is_instance_valid(health_component):
		health_component = (
			NodeQuery.find_first_child_of_type(self, HealthComponent) as HealthComponent
		)
	if not is_instance_valid(health_component):
		health_component = HealthComponent.new()
		health_component.name = "HealthComponent"
		health_component.max_health = 120
		health_component.use_pooling = false
		add_child(health_component)

	Utilities.safe_connect(health_component.died, _on_died)

	if not is_instance_valid(nav_agent):
		nav_agent = NodeQuery.find_first_child_of_type(self, NavigationAgent3D) as NavigationAgent3D
	if not is_instance_valid(nav_agent):
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		add_child(nav_agent)

	if not is_instance_valid(visibility_notifier):
		visibility_notifier = (
			NodeQuery.find_first_child_of_type(self, VisibleOnScreenNotifier3D)
			as VisibleOnScreenNotifier3D
		)
	if not is_instance_valid(visibility_notifier):
		visibility_notifier = VisibleOnScreenNotifier3D.new()
		visibility_notifier.name = "VisibleOnScreenNotifier3D"
		visibility_notifier.aabb = AABB(Vector3(-0.7, 0.0, -0.7), Vector3(1.4, 1.3, 1.4))
		add_child(visibility_notifier)

	Utilities.safe_connect(visibility_notifier.screen_entered, _on_screen_entered)
	Utilities.safe_connect(visibility_notifier.screen_exited, _on_screen_exited)

	if not is_instance_valid(animation_player):
		var anim_players: Array[Node] = find_children("*", "AnimationPlayer", true, false)
		if not anim_players.is_empty():
			animation_player = anim_players[0] as AnimationPlayer

	if not is_instance_valid(mood_component):
		mood_component = (
			NodeQuery.find_first_child_of_type(self, ImpMoodComponent) as ImpMoodComponent
		)
	if not is_instance_valid(mood_component):
		mood_component = ImpMoodComponent.new()
		mood_component.name = "ImpMoodComponent"
		add_child(mood_component)

	if not is_instance_valid(tactical_agent):
		tactical_agent = NodeQuery.find_first_child_of_type(self, TacticalAgent) as TacticalAgent
	if not is_instance_valid(tactical_agent):
		tactical_agent = TacticalAgent.new()
		tactical_agent.name = "TacticalAgent"
		add_child(tactical_agent)
	tactical_agent.visibility_notifier = visibility_notifier
	tactical_agent.max_hp = float(health_component.max_health)
	tactical_agent.current_hp = float(health_component.current_health)
	Utilities.safe_connect(tactical_agent.role_changed, _on_tactical_role_changed)


## Ensures a physics [CollisionShape3D] exists on the imp body.
func _ensure_collision_shape() -> void:
	var existing: Node = NodeQuery.find_first_child_of_type(self, CollisionShape3D)
	if is_instance_valid(existing):
		return
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.15
	col.shape = capsule
	col.position = Vector3(0.0, 0.575, 0.0)
	add_child(col)


## Resolves or creates [member _visual_root] for locomotion waddle tilt.
func _ensure_visual_root() -> void:
	var existing: Node = get_node_or_null("VisualRoot")
	if existing is Node3D:
		_visual_root = existing as Node3D
		return
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)


## Builds detection area, line-of-sight raycast, and obstacle/ledge leap raycasts.
func _build_sensors() -> void:
	_detection_area = get_node_or_null("DetectionArea") as Area3D
	if not is_instance_valid(_detection_area):
		_detection_area = Area3D.new()
		_detection_area.name = "DetectionArea"
		_detection_area.collision_layer = 0
		_detection_area.collision_mask = CollisionLayers.MASK_PLAYER
		_detection_area.monitorable = false
		var col: CollisionShape3D = CollisionShape3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 18.0
		col.shape = sphere
		_detection_area.add_child(col)
		add_child(_detection_area)
	Utilities.safe_connect(_detection_area.body_entered, _on_detection_body_entered)

	_los_ray = get_node_or_null("LosRay") as RayCast3D
	if not is_instance_valid(_los_ray):
		_los_ray = RayCast3D.new()
		_los_ray.name = "LosRay"
		_los_ray.position = Vector3(0.0, 0.7, 0.0)
		_los_ray.collision_mask = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_PLAYER
		_los_ray.enabled = false
		add_child(_los_ray)

	_obstacle_low_ray = get_node_or_null("ObstacleLowRay") as RayCast3D
	if not is_instance_valid(_obstacle_low_ray):
		_obstacle_low_ray = RayCast3D.new()
		_obstacle_low_ray.name = "ObstacleLowRay"
		_obstacle_low_ray.position = Vector3(0.0, 0.25, 0.0)
		_obstacle_low_ray.target_position = Vector3(0.0, 0.0, -1.25)
		_obstacle_low_ray.collision_mask = CollisionLayers.MASK_SOLID_WORLD
		_obstacle_low_ray.enabled = false
		add_child(_obstacle_low_ray)

	_obstacle_mid_ray = get_node_or_null("ObstacleMidRay") as RayCast3D
	if not is_instance_valid(_obstacle_mid_ray):
		_obstacle_mid_ray = RayCast3D.new()
		_obstacle_mid_ray.name = "ObstacleMidRay"
		_obstacle_mid_ray.position = Vector3(0.0, 0.95, 0.0)
		_obstacle_mid_ray.target_position = Vector3(0.0, 0.0, -1.35)
		_obstacle_mid_ray.collision_mask = CollisionLayers.MASK_SOLID_WORLD
		_obstacle_mid_ray.enabled = false
		add_child(_obstacle_mid_ray)


## Wakes physics processing when a hostile actor enters [member _detection_area].
func _on_detection_body_entered(body: Node3D) -> void:
	if current_state == ImpState.DEAD or not is_instance_valid(body) or body == self:
		return
	var other_faction: FactionComponent = FactionComponent.get_faction_component(body)
	var is_hostile: bool = false
	if is_instance_valid(other_faction) and is_instance_valid(faction_component):
		is_hostile = faction_component.is_hostile_to(other_faction)
	elif body.is_in_group(&"player"):
		is_hostile = true
	if is_hostile:
		target = body
		if is_instance_valid(tactical_agent):
			tactical_agent.set_aggro(true, body.global_position)
		if current_state == ImpState.IDLE:
			_set_state(ImpState.CHASE)
			set_physics_process(true)
			AudioPool.play_sfx_3d(SFX_AGGRO, global_position)


## Responds to [TacticalAgent] role assignments from [SquadCoordinator].
func _on_tactical_role_changed(_agent: TacticalAgent, new_role: TacticalTypes.Role) -> void:
	if current_state == ImpState.DEAD:
		return
	if new_role == TacticalTypes.Role.WATER_DIVE:
		_check_water_dive_opportunity()
	elif new_role == TacticalTypes.Role.STACK_SLAM and is_instance_valid(target):
		if current_state != ImpState.STACK_MOUNT and current_state != ImpState.STACK_SLAM:
			begin_stack_slam(0, self, target.global_position)


## Locks line lightning aim point and flashes beam + audio cue for the dodge window.
func _on_line_aim_locked(token: int) -> void:
	if token != _state_token or current_state != ImpState.CHARGE_LINE:
		return
	_aim_locked = true
	if is_instance_valid(target):
		_locked_aim_point = target.global_position + Vector3(0.0, 0.9, 0.0)
	_update_aim_beam_visual(global_position + Vector3(0.0, 0.7, 0.0), _locked_aim_point, true)
	AudioPool.play_sfx_3d(SFX_AIM_LOCK, global_position)
	line_aim_locked.emit(_locked_aim_point)
	print("EnemyImp: Line lightning aim locked at ", _locked_aim_point)


## Fires direct line lightning when telegraph charge timer completes.
func _on_line_charge_finished(token: int) -> void:
	if token != _state_token or current_state != ImpState.CHARGE_LINE:
		return
	_fire_line_lightning()


## Fires 10m expanding circle AoE when telegraph charge timer completes.
func _on_aoe_charge_finished(token: int) -> void:
	if token != _state_token or current_state != ImpState.CHARGE_AOE:
		return
	_fire_aoe_circle()


## Launches orbiting [ImpHomingOrb] projectiles when orb charge timer completes.
func _on_orb_charge_finished(token: int) -> void:
	if token != _state_token or current_state != ImpState.CHARGE_ORBS:
		return
	_clear_charge_vfx()
	for orb: ImpHomingOrb in _orbiting_orbs:
		if is_instance_valid(orb) and not orb.has_launched:
			orb.launch(target)
	_orbiting_orbs.clear()
	AudioPool.play_sfx_3d(SFX_ELECTRIC, global_position)
	var tgt_pos: Vector3 = (
		target.global_position
		if is_instance_valid(target)
		else global_position + (-global_transform.basis.z) * 8.0
	)
	electricity_attack_fired.emit(&"homing_orbs", tgt_pos)
	_schedule_attack_cooldown()
	_set_state(ImpState.CHASE)


## Triggers leader slam launch after 3-imp stack formation delay.
func _on_stack_ready_to_slam(token: int, slam_pos: Vector3) -> void:
	if token != _state_token or current_state != ImpState.STACK_MOUNT:
		return
	execute_stack_slam(slam_pos)


## Re-enables electricity attack readiness after cooldown.
func _on_attack_cooldown_ready(token: int) -> void:
	if token != _state_token or current_state == ImpState.DEAD:
		return
	_can_attack = true


## Clears active shield reference when reactive [HexShieldSphere] is destroyed.
func _on_hex_shield_destroyed() -> void:
	_active_shield = null


## Despawns reactive [HexShieldSphere] when duration expires.
func _on_hex_shield_expired(token: int) -> void:
	if token != _state_token:
		return
	_despawn_hex_shield()


## Re-enables [HexShieldSphere] deployment after cooldown.
func _on_hex_shield_cooldown_ready(token: int) -> void:
	if token != _state_token:
		return
	_can_spawn_shield = true


## Halts AI, restores flickered lights, plays death anim, and emits [signal Events.enemy_killed].
func _on_died() -> void:
	_state_token += 1
	_set_state(ImpState.DEAD)
	set_physics_process(false)
	_restore_all_lights()
	_clear_charge_vfx()
	_clear_orbiting_orbs()
	_hide_aim_beam()
	_despawn_hex_shield()
	_play_anim(&"death")
	AudioPool.play_sfx_3d(SFX_DEATH, global_position)
	Events.enemy_killed.emit(self, null)
	print("EnemyImp: Died.")


## Enables visual waddle updates when entering camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true


## Disables visual waddle updates when leaving camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
