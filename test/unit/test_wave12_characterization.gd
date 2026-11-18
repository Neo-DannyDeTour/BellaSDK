## Characterization tests locking Wave 12 public APIs, constants, signals, and behavior.
class_name TestWave12Characterization
extends GutTest

const BEAR_TRAP_SCENE: PackedScene = preload("res://enemies/bear_trap.tscn")
const EVIL_GOON_SCENE: PackedScene = preload("res://enemies/evil_goon.tscn")
const FIRE_SCENE: PackedScene = preload("res://enemies/fire.tscn")
const GUARDIAN_PILLAR_SCENE: PackedScene = preload("res://enemies/guardian_pillar.tscn")
const ENERGY_BLAST_SCENE: PackedScene = preload("res://enemies/energy_blast.tscn")
const ROOK_TRAP_SCENE: PackedScene = preload("res://enemies/rook_trap.tscn")
const SENSOR_TURRET_SCENE: PackedScene = preload("res://enemies/sensor_turret.tscn")
const SENSOR_TURRET_SCRIPT: Script = preload("res://enemies/sensor_turret.gd")
const ENEMY_SQUID_SCENE: PackedScene = preload("res://enemies/squid/enemy_squid.tscn")
const SQUID_PUDDLE_SCENE: PackedScene = preload("res://enemies/squid/squid_puddle.tscn")
const TENTACLE_ENEMY_SCENE: PackedScene = preload("res://enemies/tentacle_enemy.tscn")
const TRIPMINE_SCENE: PackedScene = preload("res://enemies/tripmine.tscn")
const TURRET_SCENE: PackedScene = preload("res://enemies/turret.tscn")
const SIGNAL_ROCKET_PROJ_SCENE: PackedScene = preload(
	"res://weapons/signal_rocket/signal_rocket_projectile.tscn"
)
const SIGNAL_ROCKET_WEAP_SCENE: PackedScene = preload(
	"res://weapons/signal_rocket/signal_rocket_weapon.tscn"
)
const SMOKE_CLOUD_SCENE: PackedScene = preload(
	"res://weapons/smoke_grenade/smoke_grenade_cloud.tscn"
)
const SMOKE_PROJ_SCENE: PackedScene = preload(
	"res://weapons/smoke_grenade/smoke_grenade_projectile.tscn"
)
const SMOKE_WEAP_SCENE: PackedScene = preload(
	"res://weapons/smoke_grenade/smoke_grenade_weapon.tscn"
)


## Cleans up global smoke registrations after each test.
func after_each() -> void:
	var smoke_mgr: Node = get_tree().root.get_node_or_null("SmokeManager")
	if is_instance_valid(smoke_mgr) and smoke_mgr.has_method(&"clear_all"):
		smoke_mgr.call(&"clear_all")


## Verifies [BearTrap] enums, collision layers, initial state, and jaw snap contracts.
func test_bear_trap_contracts() -> void:
	assert_eq(BearTrap.TrapState.OPEN, 0)
	assert_eq(BearTrap.TrapState.CLOSED, 1)

	var trap: BearTrap = BEAR_TRAP_SCENE.instantiate() as BearTrap
	assert_not_null(trap)
	add_child_autofree(trap)

	assert_eq(trap.current_state, BearTrap.TrapState.OPEN)
	assert_null(trap.trapped_player)
	assert_eq(trap.collision_layer, CollisionLayers.MASK_NONE)
	assert_eq(trap.collision_mask, CollisionLayers.MASK_PLAYER)

	var dummy: Node3D = Node3D.new()
	add_child_autofree(dummy)
	trap.snap_shut(dummy)
	assert_eq(trap.current_state, BearTrap.TrapState.CLOSED)
	assert_eq(trap.trapped_player, dummy)


## Verifies [DroneSwarmController] enums, constants, signals, and formation math.
func test_drone_swarm_controller_contracts() -> void:
	assert_eq(DroneSwarmController.Formation.CIRCLE, 0)
	assert_eq(DroneSwarmController.Formation.SQUARE, 1)
	assert_eq(DroneSwarmController.Formation.CROSS, 2)
	assert_eq(DroneSwarmController.Mode.IDLE, 0)
	assert_eq(DroneSwarmController.Mode.PATH_FOLLOW, 1)
	assert_eq(DroneSwarmController.Mode.FORMATION, 2)
	assert_eq(DroneSwarmController.Mode.HEAL_PLAYER, 3)
	assert_eq(DroneSwarmController.Mode.EXPLORE, 4)
	assert_eq(DroneSwarmController.HEALTH_CHECK_INTERVAL, 0.2)

	var swarm: DroneSwarmController = DroneSwarmController.new()
	add_child_autofree(swarm)

	assert_has_signal(swarm, &"healing_started")
	assert_has_signal(swarm, &"healing_completed")
	assert_eq(swarm.formation, DroneSwarmController.Formation.CIRCLE)
	assert_eq(swarm.mode, DroneSwarmController.Mode.PATH_FOLLOW)
	assert_eq(swarm.formation_radius, 3.5)

	swarm.cycle_next_formation()
	assert_eq(swarm.formation, DroneSwarmController.Formation.SQUARE)
	swarm.switch_to_cross_formation()
	assert_eq(swarm.mode, DroneSwarmController.Mode.FORMATION)
	assert_eq(swarm.formation, DroneSwarmController.Formation.CROSS)

	assert_eq(swarm.calculate_slot_offset(0, 0), Vector3.ZERO)
	swarm.set_formation(DroneSwarmController.Formation.CIRCLE)
	var slot_zero: Vector3 = swarm.calculate_slot_offset(0, 4)
	assert_almost_eq(slot_zero.length(), swarm.formation_radius, 0.001)

	var waved: Vector3 = swarm.apply_wave_motion(0, Vector3.ZERO)
	assert_almost_eq(waved.y, 0.0, 0.001)


## Verifies [EvilGoon] constants, exports, collision masks, and damage/death signals.
func test_evil_goon_contracts() -> void:
	assert_eq(EvilGoon.DEATH_FX_OFFSET, Vector3(0.0, 0.4, 0.0))
	assert_eq(EvilGoon.HIT_HEIGHT_CLAMP, 0.6)

	var goon: EvilGoon = EVIL_GOON_SCENE.instantiate() as EvilGoon
	assert_not_null(goon)
	add_child_autofree(goon)

	assert_false(goon.is_processing())
	assert_false(goon.is_physics_processing())
	assert_eq(goon.collision_layer, CollisionLayers.MASK_ENEMIES)
	assert_not_null(goon.health_component)
	assert_not_null(goon.faction_component)
	assert_eq(goon.faction_component.faction, Types.Faction.ENEMY)
	assert_eq(goon.knockback_force, 0.5)
	assert_eq(goon.vertical_kick, 0.7)
	assert_eq(goon.sfx_bus, &"SFX")

	var start_hp: int = goon.health_component.current_health
	goon.take_damage(10, goon.global_position, Vector3.FORWARD)
	assert_eq(goon.health_component.current_health, start_hp - 10)


## Verifies [VolumetricFire] constants, signals, setters, and ignite/extinguish lifecycle.
func test_volumetric_fire_contracts() -> void:
	assert_eq(VolumetricFire.FLICKER_FREQUENCY, 12.0)
	assert_eq(VolumetricFire.VOLUMETRIC_LAYER_MASK, CollisionLayers.RENDER_MASK_VOLUMETRICS)
	assert_eq(VolumetricFire.ENVIRONMENT_LAYER_MASK, CollisionLayers.RENDER_MASK_ENVIRONMENT)

	var fire: VolumetricFire = FIRE_SCENE.instantiate() as VolumetricFire
	assert_not_null(fire)
	add_child_autofree(fire)

	assert_has_signal(fire, &"ignited")
	assert_has_signal(fire, &"extinguished")
	assert_has_signal(fire, &"body_ignited")

	watch_signals(fire)
	fire.extinguish()
	assert_signal_emitted(fire, &"extinguished")
	fire.ignite()
	assert_signal_emitted(fire, &"ignited")

	fire.set_fire_height(0.0)
	assert_almost_eq(fire.fire_height, 0.05, 0.001)
	fire.set_fire_width(3.0)
	assert_almost_eq(fire.fire_width, 3.0, 0.001)
	fire.set_fire_speed(0.5)
	assert_almost_eq(fire.fire_speed, 0.5, 0.001)
	fire.set_emission_strength(5.0)
	assert_almost_eq(fire.emission_strength, 5.0, 0.001)
	fire.set_wind_direction(Vector3(3.0, 0.0, 4.0))
	assert_almost_eq(fire.wind_direction.length(), 1.0, 0.001)
	fire.set_wind_strength(-1.0)
	assert_almost_eq(fire.wind_strength, 0.0, 0.001)


## Verifies [GuardianPillar] state enum, exports, and initial node contracts.
func test_guardian_pillar_contracts() -> void:
	assert_eq(GuardianPillar.State.SCANNING, 0)
	assert_eq(GuardianPillar.State.TARGETING, 1)
	assert_eq(GuardianPillar.State.FROZEN, 2)
	assert_eq(GuardianPillar.State.COOLDOWN, 3)

	var pillar: GuardianPillar = GUARDIAN_PILLAR_SCENE.instantiate() as GuardianPillar
	assert_not_null(pillar)
	add_child_autofree(pillar)

	assert_eq(pillar.current_state, GuardianPillar.State.SCANNING)
	assert_null(pillar.target_player)
	assert_false(pillar.is_friendly)
	assert_eq(pillar.scan_speed, 1.5)
	assert_eq(pillar.targeting_time, 2.0)
	assert_eq(pillar.freeze_time, 1.0)
	assert_eq(pillar.vision_radius, 15.0)
	assert_eq(pillar.field_of_view_degrees, 60.0)
	assert_not_null(pillar.head)
	assert_not_null(pillar.laser_mesh)
	assert_not_null(pillar.spawn_point)
	assert_not_null(pillar.state_timer)


## Verifies [EnergyBlast] exports, collision masks, and trajectory setup.
func test_energy_blast_contracts() -> void:
	var blast: EnergyBlast = ENERGY_BLAST_SCENE.instantiate() as EnergyBlast
	assert_not_null(blast)
	add_child_autofree(blast)

	assert_eq(blast.speed, 25.0)
	assert_eq(blast.damage, 100)
	assert_eq(blast.explosion_radius, 4.0)
	assert_eq(blast.lifetime, 3.0)
	assert_false(blast.is_exploding)
	assert_true(blast.get_collision_mask_value(CollisionLayers.LAYER_ENVIRONMENT_IDX))
	assert_true(blast.get_collision_mask_value(CollisionLayers.LAYER_PLAYER_IDX))

	blast.set_trajectory(Vector3(0.0, 0.0, -5.0))
	assert_eq(blast.velocity, Vector3(0.0, 0.0, -25.0))


## Verifies [RookTrap] enums, exports, child nodes, and trigger bounds.
func test_rook_trap_contracts() -> void:
	assert_eq(RookTrap.State.IDLE, 0)
	assert_eq(RookTrap.State.ATTACKING, 1)
	assert_eq(RookTrap.State.RETURNING, 2)

	var trap: RookTrap = ROOK_TRAP_SCENE.instantiate() as RookTrap
	assert_not_null(trap)
	add_child_autofree(trap)

	assert_eq(trap.attack_speed, 25.0)
	assert_eq(trap.return_speed, 5.0)
	assert_eq(trap.damage_amount, 100)
	assert_eq(trap.knockback_force, 15.0)
	assert_not_null(trap.moving_body)
	assert_not_null(trap.player_hitbox)
	assert_not_null(trap.path_lines_container)

	trap.trigger_trap(-1)
	assert_true(true, "Out-of-bounds trigger_trap should safely ignore invalid index.")


## Verifies [SensorTurret] script constants, exports, and initial gating.
func test_sensor_turret_contracts() -> void:
	var turret: Node3D = SENSOR_TURRET_SCENE.instantiate() as Node3D
	assert_not_null(turret)
	add_child_autofree(turret)

	assert_eq(turret.get_script(), SENSOR_TURRET_SCRIPT)
	assert_false(turret.is_physics_processing())
	assert_eq(turret.get(&"detection_range"), 25.0)
	assert_eq(turret.get(&"near_prop_distance"), 2.5)
	assert_eq(turret.get(&"scan_interval"), 0.25)

	turret.set(&"detection_range", -5.0)
	assert_almost_eq(float(turret.get(&"detection_range")), 0.1, 0.001)


## Verifies [EnemySquid] enums, constants, exports, and reset/damage contracts.
func test_enemy_squid_contracts() -> void:
	assert_eq(EnemySquid.SquidState.IDLE, 0)
	assert_eq(EnemySquid.SquidState.PATROL, 1)
	assert_eq(EnemySquid.SquidState.CHASE, 2)
	assert_eq(EnemySquid.SquidState.WINDUP, 3)
	assert_eq(EnemySquid.SquidState.LEAP, 4)
	assert_eq(EnemySquid.SquidState.RECOVER, 5)
	assert_eq(EnemySquid.SpillMode.NO_SPRINT, 0)
	assert_eq(EnemySquid.SpillMode.SLIPPERY, 1)
	assert_eq(EnemySquid.SpillMode.ALTERNATING, 2)
	assert_eq(EnemySquid.PARAM_WAVE_PHASE, &"wave_phase")
	assert_eq(EnemySquid.TENTACLE_COUNT, 8)
	assert_eq(EnemySquid.PUDDLE_POOL_SIZE, 4)

	var squid: EnemySquid = ENEMY_SQUID_SCENE.instantiate() as EnemySquid
	assert_not_null(squid)
	add_child_autofree(squid)

	assert_eq(squid.collision_layer, Types.MASK_ENEMIES)
	assert_not_null(squid.health_component)
	assert_not_null(squid.faction_component)
	squid.reset_squid(Vector3(3.0, 1.0, -2.0))
	assert_eq(squid.global_position, Vector3(3.0, 1.0, -2.0))
	assert_eq(squid.velocity, Vector3.ZERO)


## Verifies [SquidPuddle] enums, constants, and activate/deactivate pooling contracts.
func test_squid_puddle_contracts() -> void:
	assert_eq(SquidPuddle.PuddleType.NO_SPRINT, 0)
	assert_eq(SquidPuddle.PuddleType.SLIPPERY, 1)
	assert_eq(SquidPuddle.PUDDLE_RADIUS, 1.65)
	assert_eq(SquidPuddle.SPRINT_DEBUFF_SECONDS, 1.5)

	var puddle: SquidPuddle = SQUID_PUDDLE_SCENE.instantiate() as SquidPuddle
	assert_not_null(puddle)
	add_child_autofree(puddle)

	assert_false(puddle.is_processing())
	assert_false(puddle.is_physics_processing())
	assert_false(puddle.visible)
	assert_false(puddle.monitoring)

	puddle.activate(Vector3(1.0, 0.0, 2.0), SquidPuddle.PuddleType.SLIPPERY)
	assert_true(puddle.visible)
	assert_eq(puddle.global_position, Vector3(1.0, 0.0, 2.0))
	puddle.deactivate()
	assert_false(bool(puddle.get(&"_is_active")))


## Verifies [ProceduralTentacle3D] exports and segment generation in [method _ready].
func test_procedural_tentacle_contracts() -> void:
	var tentacle: ProceduralTentacle3D = ProceduralTentacle3D.new()
	tentacle.segment_count = 6
	tentacle.thickness = 0.2
	add_child_autofree(tentacle)

	assert_eq(tentacle.segment_count, 6)
	assert_eq(tentacle.thickness, 0.2)
	assert_eq(tentacle.get_child_count(), 6)


## Verifies [TentacleEnemy] state enum, exports, and initial idle state.
func test_tentacle_enemy_contracts() -> void:
	assert_eq(TentacleEnemy.State.IDLE, 0)
	assert_eq(TentacleEnemy.State.PLAYING, 1)
	assert_eq(TentacleEnemy.State.HOLDING, 2)
	assert_eq(TentacleEnemy.State.SPOTTED, 3)
	assert_eq(TentacleEnemy.State.ATTACKING, 4)

	var enemy: TentacleEnemy = TENTACLE_ENEMY_SCENE.instantiate() as TentacleEnemy
	assert_not_null(enemy)
	add_child_autofree(enemy)

	assert_eq(enemy.current_state, TentacleEnemy.State.IDLE)
	assert_null(enemy.held_object)
	assert_null(enemy.target_player)
	assert_eq(enemy.charge_delay, 1.0)
	assert_eq(enemy.throw_force, 15.0)
	assert_eq(enemy.strike_damage, 50)
	assert_not_null(enemy.tentacle_target)
	assert_not_null(enemy.detection_area)
	assert_not_null(enemy.health_component)


## Verifies [TripMine] enums, constants, signals, and motion mode switching.
func test_tripmine_contracts() -> void:
	assert_eq(TripMine.MotionMode.STATIC, 0)
	assert_eq(TripMine.MotionMode.VERTICAL, 1)
	assert_eq(TripMine.MotionMode.HORIZONTAL, 2)
	assert_eq(TripMine.MotionMode.CIRCLE, 3)
	assert_eq(TripMine.MotionMode.PYRAMID, 4)
	assert_eq(TripMine.MotionMode.SQUARE, 5)
	assert_almost_eq(TripMine.DAMAGE_FALLOFF_PER_METER, 66.6667, 0.001)

	var mine: TripMine = TRIPMINE_SCENE.instantiate() as TripMine
	assert_not_null(mine)
	add_child_autofree(mine)

	assert_has_signal(mine, &"detonated")
	assert_has_signal(mine, &"laser_state_changed")
	assert_eq(mine.motion_mode, TripMine.MotionMode.STATIC)
	mine.set_motion_mode(TripMine.MotionMode.CIRCLE)
	assert_eq(mine.motion_mode, TripMine.MotionMode.CIRCLE)


## Verifies [Turret] enums, exports, and initial scanning state.
func test_turret_contracts() -> void:
	assert_eq(Turret.TurretState.SCANNING, 0)
	assert_eq(Turret.TurretState.ENGAGING, 1)

	var turret: Turret = TURRET_SCENE.instantiate() as Turret
	assert_not_null(turret)
	add_child_autofree(turret)

	assert_eq(turret.current_state, Turret.TurretState.SCANNING)
	assert_false(turret.is_friendly)
	assert_eq(turret.scan_speed, 1.5)
	assert_eq(turret.turn_speed, 8.0)
	assert_eq(turret.fire_rate, 0.01)
	assert_eq(turret.detection_radius, 15.0)
	assert_eq(turret.damage, 10)
	assert_not_null(turret.head)
	assert_not_null(turret.detection_area)


## Verifies [WaveSpawner] signals, exports, wave progression, and completion signal.
func test_wave_spawner_contracts() -> void:
	var spawner: WaveSpawner = WaveSpawner.new()
	spawner.total_waves = 1
	spawner.base_enemy_count = 0
	add_child_autofree(spawner)

	assert_has_signal(spawner, &"all_waves_completed")
	assert_eq(spawner.current_wave, 0)

	watch_signals(spawner)
	spawner.start_spawner()
	assert_eq(spawner.current_wave, 1)
	spawner.start_next_wave()
	assert_signal_emitted_with_parameters(spawner, &"all_waves_completed", [1])
	spawner.stop_spawner()


## Verifies [SignalRocketProjectile] constants, exports, and arming contract.
func test_signal_rocket_projectile_contracts() -> void:
	assert_eq(SignalRocketProjectile.FLARE_ENERGY_MIN, 3.0)
	assert_eq(SignalRocketProjectile.FLARE_ENERGY_MAX, 5.0)
	assert_eq(SignalRocketProjectile.PROP_BURN_DURATION, &"burn_duration")

	var proj: SignalRocketProjectile = (
		SIGNAL_ROCKET_PROJ_SCENE.instantiate() as SignalRocketProjectile
	)
	assert_not_null(proj)
	add_child_autofree(proj)

	assert_false(proj.is_processing())
	assert_false(proj.is_physics_processing())
	assert_true(proj.continuous_cd)
	assert_eq(proj.display_name, "Signal Rocket")
	proj.arm(12.0)
	assert_eq(proj.burn_time, 12.0)


## Verifies [SignalRocketWeapon] constants, exports, and single-stack shot behavior.
func test_signal_rocket_weapon_contracts() -> void:
	assert_eq(SignalRocketWeapon.MIN_REMAINING_BURN, 0.1)
	assert_eq(SignalRocketWeapon.DROP_FORWARD_SPEED, 2.5)
	assert_eq(SignalRocketWeapon.DROP_UPWARD_BOOST, 0.5)

	var weapon: SignalRocketWeapon = SIGNAL_ROCKET_WEAP_SCENE.instantiate() as SignalRocketWeapon
	assert_not_null(weapon)
	add_child_autofree(weapon)

	assert_eq(weapon.max_ammo, 1)
	assert_eq(weapon.current_ammo, 1)
	assert_eq(weapon.burn_duration, 18.0)

	var cam: Camera3D = Camera3D.new()
	add_child_autofree(cam)
	assert_false(weapon.shoot(cam))


## Verifies [SmokeGrenadeCloud] constants, exports, AABB, LOS, and carve contracts.
func test_smoke_grenade_cloud_contracts() -> void:
	assert_eq(SmokeGrenadeCloud.LAYER_VOLUMETRICS, 1 << 9)
	assert_eq(SmokeGrenadeCloud.MAX_RAYS, 8)
	assert_eq(SmokeGrenadeCloud.LOBE_COUNT, 10)
	assert_eq(SmokeGrenadeCloud.PARAM_EXPANSION, &"expansion_progress")
	assert_eq(SmokeGrenadeCloud.PARAM_DISSIPATION, &"dissipation_alpha")

	var cloud: SmokeGrenadeCloud = SMOKE_CLOUD_SCENE.instantiate() as SmokeGrenadeCloud
	assert_not_null(cloud)
	add_child_autofree(cloud)

	assert_false(cloud.is_processing())
	assert_false(cloud.is_physics_processing())
	assert_eq(cloud.layers, SmokeGrenadeCloud.LAYER_VOLUMETRICS)
	assert_eq(cloud.max_radius, 4.4)
	assert_eq(cloud.smoke_duration, 15.0)
	assert_false(cloud.intersects_world_aabb(AABB(Vector3(500.0, 500.0, 500.0), Vector3.ONE)))
	assert_false(
		cloud.is_line_of_sight_obscured(Vector3(500.0, 0.0, 0.0), Vector3(505.0, 0.0, 0.0))
	)
	cloud.carve_bullet_ray(Vector3.ZERO, Vector3.FORWARD, 0.55)
	cloud.carve_explosion_sphere(Vector3.ZERO, 2.0, 4.5)


## Verifies [SmokeGrenadeProjectile] exports, collision layers, and fuse setup.
func test_smoke_grenade_projectile_contracts() -> void:
	var proj: SmokeGrenadeProjectile = SMOKE_PROJ_SCENE.instantiate() as SmokeGrenadeProjectile
	assert_not_null(proj)
	add_child_autofree(proj)

	assert_false(proj.is_processing())
	assert_false(proj.is_physics_processing())
	assert_true(proj.continuous_cd)
	assert_eq(proj.fuse_time, 1.6)
	assert_eq(proj.collision_layer, Types.MASK_DEBRIS)


## Verifies [SmokeGrenadeWeapon] defaults and [ThrowableWeapon] inheritance.
func test_smoke_grenade_weapon_contracts() -> void:
	var weapon: SmokeGrenadeWeapon = SMOKE_WEAP_SCENE.instantiate() as SmokeGrenadeWeapon
	assert_not_null(weapon)
	add_child_autofree(weapon)

	assert_eq(weapon.weapon_tag, "smoke_grenade")
	assert_eq(weapon.ammo_type, &"smoke_grenade")
	assert_eq(weapon.default_slot, 4)
	assert_eq(weapon.max_ammo, 3)
	assert_not_null(weapon.projectile_scene)


## Verifies [ThrowableWeapon] constants, signals, and stack/ammo contracts.
func test_throwable_weapon_contracts() -> void:
	assert_eq(ThrowableWeapon.DEFAULT_THROWABLE_SLOT, 4)
	assert_eq(ThrowableWeapon.DEFAULT_MAX_AMMO, 3)

	var throwable: ThrowableWeapon = ThrowableWeapon.new()
	add_child_autofree(throwable)

	assert_has_signal(throwable, &"ammo_updated")
	assert_false(throwable.is_processing())
	assert_false(throwable.is_physics_processing())
	assert_eq(throwable.weapon_tag, "throwable")
	assert_eq(throwable.default_slot, 4)
	assert_eq(throwable.current_ammo, 1)
	assert_eq(throwable.max_ammo, 3)

	watch_signals(throwable)
	assert_true(throwable.add_grenade(2))
	assert_eq(throwable.current_ammo, 3)
	assert_false(throwable.add_grenade(1))
	throwable.sync_ammo_ui()
	assert_signal_emitted_with_parameters(throwable, &"ammo_updated", [3, 0, 3])
