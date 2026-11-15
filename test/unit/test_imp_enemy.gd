## Tests EnemyImp components, mood weights, HexShield cadence, aim-freeze,
## homing orbs, direct-steering fallback, stack slam, lights, and water dive.
class_name TestImpEnemy
extends GutTest

## The [EnemyImp] scene under test.
const IMP_SCENE: PackedScene = preload("res://enemies/imp/imp.tscn")

## The [ImpHomingOrb] scene under test.
const HOMING_ORB_SCENE: PackedScene = preload("res://enemies/imp/imp_homing_orb.tscn")

## The [EnemyImp] instance under test.
var imp: EnemyImp = null

## Isolated container for imp and spawned world VFX nodes.
var _test_root: Node3D = null


## Creates a fresh [EnemyImp] before each test.
func before_each() -> void:
	_test_root = Node3D.new()
	add_child_autofree(_test_root)
	imp = EnemyImp.new()
	_test_root.add_child(imp)


## Verifies mandatory components, groups, and collision layers on initialization.
func test_imp_initialization_and_components() -> void:
	assert_not_null(imp.health_component, "EnemyImp must have HealthComponent.")
	assert_not_null(imp.faction_component, "EnemyImp must have FactionComponent.")
	assert_eq(imp.faction_component.faction, Types.Faction.ENEMY)
	assert_not_null(imp.tactical_agent, "EnemyImp must have TacticalAgent.")
	assert_not_null(imp.nav_agent, "EnemyImp must have NavigationAgent3D.")
	assert_not_null(imp.visibility_notifier, "EnemyImp must have VisibleOnScreenNotifier3D.")
	assert_not_null(imp.mood_component, "EnemyImp must have ImpMoodComponent.")
	assert_eq(imp.collision_layer, CollisionLayers.MASK_ENEMIES)
	assert_true(imp.is_in_group(&"enemy"))
	assert_true(imp.is_in_group(&"damageable"))
	assert_true(imp.is_in_group(&"tactical_agent"))


## Verifies ImpMoodComponent percentage normalization and personality behavior multipliers.
func test_imp_mood_component_normalization_and_multipliers() -> void:
	var mood: ImpMoodComponent = ImpMoodComponent.new()
	add_child_autofree(mood)

	var default_w: Vector3 = mood.get_normalized_weights()
	assert_almost_eq(default_w.x + default_w.y + default_w.z, 1.0, 0.001)
	assert_almost_eq(default_w.x, 0.5, 0.001)
	assert_almost_eq(default_w.y, 0.25, 0.001)
	assert_almost_eq(default_w.z, 0.25, 0.001)

	# Zeroed percentages must safely normalize to equal thirds.
	mood.aggressive_pct = 0
	mood.evasive_pct = 0
	mood.playful_pct = 0
	var zero_w: Vector3 = mood.get_normalized_weights()
	assert_almost_eq(zero_w.x + zero_w.y + zero_w.z, 1.0, 0.001)

	# Compare 100% Aggressive vs 100% Evasive vs 100% Playful.
	mood.aggressive_pct = 100
	mood.evasive_pct = 0
	mood.playful_pct = 0
	var agg_cd: float = mood.get_attack_cooldown_multiplier()
	var agg_speed: float = mood.get_speed_multiplier()
	var agg_slam: float = mood.get_stack_slam_bias()
	var agg_dodge: float = mood.get_dodge_probability()

	mood.aggressive_pct = 0
	mood.evasive_pct = 100
	mood.playful_pct = 0
	var eva_dodge: float = mood.get_dodge_probability()
	var eva_shield: float = mood.get_shield_bias()
	var eva_shield_cd: float = mood.get_shield_cooldown_multiplier()

	mood.aggressive_pct = 0
	mood.evasive_pct = 0
	mood.playful_pct = 100
	var ply_cd: float = mood.get_attack_cooldown_multiplier()
	var ply_hop: float = mood.get_hop_taunt_frequency()
	var ply_laugh_mult: float = mood.get_laugh_interval_multiplier()

	assert_lt(agg_cd, ply_cd, "Aggressive imps must attack faster than playful imps.")
	assert_gt(agg_speed, 1.0, "Aggressive imps must move faster.")
	assert_gt(agg_slam, eva_shield * 0.5)
	assert_gt(eva_dodge, agg_dodge, "Evasive imps must dodge more than aggressive imps.")
	assert_gt(eva_shield, 0.8, "Evasive imps must have high shield bias.")
	assert_lt(eva_shield_cd, 0.8, "Evasive imps must refresh shields faster.")
	assert_gt(ply_hop, 0.7, "Playful imps must hop/taunt frequently.")
	assert_lt(ply_laugh_mult, 0.6, "Playful imps must laugh more frequently.")


## Verifies leap traversal sets LEAP state and upward/horizontal velocity.
func test_imp_leap_traversal() -> void:
	imp.perform_leap(Vector3(10.0, 0.0, 0.0))
	assert_eq(imp.current_state, EnemyImp.ImpState.LEAP)
	assert_gt(imp.velocity.y, 0.0)
	assert_gt(imp.velocity.x, 0.0)


## Verifies HexShieldSphere spawns proactively on timer and by every 3rd hit without HP lockout.
func test_imp_proactive_and_hit_cadence_hex_shield() -> void:
	imp.hex_shield_min_chance = 0.0
	imp.hex_shield_max_chance = 0.0
	imp.shield_hit_cadence = 3

	var start_hp: int = imp.health_component.current_health
	imp.take_damage(5, imp.global_position, Vector3.FORWARD)
	imp.take_damage(5, imp.global_position, Vector3.FORWARD)
	assert_eq(imp.health_component.current_health, start_hp - 10)

	var before_third: HexShieldSphere = (
		NodeQuery.find_first_child_of_type(imp, HexShieldSphere) as HexShieldSphere
	)
	assert_null(before_third, "With 0 random chance, shield waits for 3rd hit.")

	# 3rd hit guarantees shield deployment even while HP is still above 50%.
	imp.take_damage(5, imp.global_position, Vector3.FORWARD)
	var shield: HexShieldSphere = (
		NodeQuery.find_first_child_of_type(imp, HexShieldSphere) as HexShieldSphere
	)
	assert_not_null(shield, "3rd hit must guarantee HexShieldSphere above 50% HP.")

	var hp_before_shield_hit: int = imp.health_component.current_health
	var shield_hp_before: int = shield.current_health
	imp.take_damage(20, imp.global_position, Vector3.FORWARD)
	assert_eq(
		imp.health_component.current_health,
		hp_before_shield_hit,
		"Active HexShieldSphere must absorb damage before imp health."
	)
	assert_lt(shield.current_health, shield_hp_before)

	# Verify proactive shield deployment on combat timer without taking any hit.
	var proactive_imp: EnemyImp = EnemyImp.new()
	_test_root.add_child(proactive_imp)
	proactive_imp.current_state = EnemyImp.ImpState.CHASE
	proactive_imp._tick_proactive_shield(20.0)
	var proactive_shield: HexShieldSphere = (
		NodeQuery.find_first_child_of_type(proactive_imp, HexShieldSphere) as HexShieldSphere
	)
	assert_not_null(proactive_shield, "Proactive timer must deploy shield even without hits.")


## Verifies imp.tscn binds AnimationPlayer from imp_rigged.glb with all 8 expected clips.
func test_imp_scene_animations_loaded() -> void:
	var scene_imp: EnemyImp = IMP_SCENE.instantiate() as EnemyImp
	_test_root.add_child(scene_imp)
	assert_not_null(scene_imp.animation_player, "imp.tscn must bind AnimationPlayer.")
	var expected: Array[StringName] = [
		&"idle",
		&"run",
		&"jump",
		&"charge_lightning",
		&"stack_mount",
		&"dive_bomb",
		&"hit_react",
		&"death",
	]
	for anim_name: StringName in expected:
		assert_true(
			scene_imp.animation_player.has_animation(anim_name),
			"Missing animation clip: %s" % String(anim_name)
		)


## Verifies direct line lightning enters telegraph charge and emits attack signals.
func test_imp_line_lightning_telegraph_and_fire() -> void:
	watch_signals(imp)
	imp.line_charge_duration = 0.05
	imp.start_line_lightning_attack()
	assert_eq(imp.current_state, EnemyImp.ImpState.CHARGE_LINE)
	assert_signal_emitted_with_parameters(imp, "telegraph_started", [&"line_lightning"])

	await wait_for_signal(imp.electricity_attack_fired, 0.5)
	assert_signal_emitted(imp, "electricity_attack_fired")


## Verifies line lightning freezes _locked_aim_point so dodging sideways avoids the beam.
func test_imp_line_lightning_aim_freeze_dodge() -> void:
	var player: CharacterBody3D = _create_mock_player(Vector3(0.0, 0.0, -8.0))
	var player_hc: HealthComponent = (
		NodeQuery.find_first_child_of_type(player, HealthComponent) as HealthComponent
	)
	var start_hp: int = player_hc.current_health

	imp.target = player
	imp.line_charge_duration = 0.20
	imp.aim_freeze_duration = 0.08
	watch_signals(imp)
	imp.start_line_lightning_attack()
	assert_false(imp.is_aim_locked(), "Aim must track before freeze window.")

	await wait_for_signal(imp.line_aim_locked, 0.5)
	assert_true(imp.is_aim_locked(), "Aim must freeze before firing.")
	var frozen_pt: Vector3 = imp.get_locked_aim_point()

	# Player sidesteps 10m sideways during the frozen dodge window.
	player.position = Vector3(10.0, 0.0, -8.0)

	await wait_for_signal(imp.electricity_attack_fired, 0.5)
	assert_almost_eq(imp.get_locked_aim_point().x, frozen_pt.x, 0.05)
	assert_eq(player_hc.current_health, start_hp, "Dodging after aim-lock must avoid damage.")


## Verifies ImpHomingOrb smooth steering curves toward target and Imp orb volley fires.
func test_imp_homing_orb_steering_and_attack() -> void:
	var orb: ImpHomingOrb = HOMING_ORB_SCENE.instantiate() as ImpHomingOrb
	_test_root.add_child(orb)
	orb.global_position = Vector3(0.0, 1.0, 0.0)
	var target_node: Node3D = Node3D.new()
	target_node.position = Vector3(0.0, 0.0, -10.0)
	_test_root.add_child(target_node)

	orb.turn_rate_deg = 95.0
	orb.speed = 11.0
	orb.launch(target_node, Vector3.RIGHT)
	var initial_z: float = orb.velocity_dir.z
	orb.step_steering(0.25)
	assert_lt(orb.velocity_dir.z, initial_z, "Orb steering must curve velocity toward -Z target.")
	assert_gt(orb.global_position.length(), 1.0)

	watch_signals(imp)
	imp.target = target_node
	imp.orb_charge_duration = 0.06
	imp.orb_count = 2
	imp.start_homing_orbs_attack()
	assert_eq(imp.current_state, EnemyImp.ImpState.CHARGE_ORBS)
	await wait_for_signal(imp.electricity_attack_fired, 0.5)
	assert_signal_emitted_with_parameters(
		imp, "electricity_attack_fired", [&"homing_orbs", target_node.global_position]
	)


## Verifies direct-steering fallback moves toward target when no NavigationMesh exists.
func test_imp_direct_steering_fallback_without_navmesh() -> void:
	var player: CharacterBody3D = _create_mock_player(Vector3(9.0, 0.0, 0.0))
	imp.target = player
	imp._can_attack = false
	imp._set_state(EnemyImp.ImpState.CHASE)
	imp.mood_component.aggressive_pct = 100
	imp.mood_component.evasive_pct = 0
	imp.mood_component.playful_pct = 0

	imp._process_chase(0.05)
	assert_gt(imp.velocity.x, 1.0, "Without a navmesh path, imp must steer directly toward target.")


## Verifies 10m expanding circle AoE damages player within 5m radius and spares outside.
func test_imp_aoe_circle_damage_radius() -> void:
	var near_player: CharacterBody3D = _create_mock_player(Vector3(4.0, 0.0, 0.0))
	var far_player: CharacterBody3D = _create_mock_player(Vector3(7.0, 0.0, 0.0))
	var near_hc: HealthComponent = (
		NodeQuery.find_first_child_of_type(near_player, HealthComponent) as HealthComponent
	)
	var far_hc: HealthComponent = (
		NodeQuery.find_first_child_of_type(far_player, HealthComponent) as HealthComponent
	)
	var near_start: int = near_hc.current_health
	var far_start: int = far_hc.current_health

	imp.aoe_charge_duration = 0.05
	imp.start_aoe_circle_attack()
	assert_eq(imp.current_state, EnemyImp.ImpState.CHARGE_AOE)

	await wait_for_signal(imp.electricity_attack_fired, 0.5)
	assert_eq(near_hc.current_health, near_start - imp.aoe_lightning_damage)
	assert_eq(far_hc.current_health, far_start)


## Verifies 3-imp stack slam mounts imps into totem slots and launches slam.
func test_imp_three_stack_slam() -> void:
	var ally1: EnemyImp = EnemyImp.new()
	var ally2: EnemyImp = EnemyImp.new()
	_test_root.add_child(ally1)
	_test_root.add_child(ally2)

	var target_pos: Vector3 = Vector3(5.0, 0.0, 0.0)
	imp.begin_stack_slam(0, imp, target_pos)
	ally1.begin_stack_slam(1, imp, target_pos)
	ally2.begin_stack_slam(2, imp, target_pos)

	assert_eq(imp.current_state, EnemyImp.ImpState.STACK_MOUNT)
	assert_eq(ally1.current_state, EnemyImp.ImpState.STACK_MOUNT)
	assert_eq(ally2.current_state, EnemyImp.ImpState.STACK_MOUNT)

	ally1.execute_stack_slam(target_pos)
	assert_eq(ally1.current_state, EnemyImp.ImpState.STACK_SLAM)


## Verifies autonomous 3-imp stack slam triggers when 3 living imps gather within 12m.
func test_imp_autonomous_stack_slam_without_coordinator() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(40.0, 1.0, 40.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_col)
	_test_root.add_child(floor_body)

	var ally1: EnemyImp = EnemyImp.new()
	var ally2: EnemyImp = EnemyImp.new()
	ally1.position = Vector3(3.0, 0.0, 0.0)
	ally2.position = Vector3(-3.0, 0.0, 0.0)
	_test_root.add_child(ally1)
	_test_root.add_child(ally2)

	var player: CharacterBody3D = _create_mock_player(Vector3(0.0, 0.0, -18.0))
	imp.target = player
	ally1.target = player
	ally2.target = player
	imp._set_state(EnemyImp.ImpState.CHASE)
	ally1._set_state(EnemyImp.ImpState.CHASE)
	ally2._set_state(EnemyImp.ImpState.CHASE)
	imp.set_physics_process(true)
	ally1.set_physics_process(true)
	ally2.set_physics_process(true)

	await wait_physics_frames(3)
	var triggered: bool = imp.try_autonomous_stack_slam(true)
	assert_true(triggered, "3 imps within 12m must autonomously initiate stack slam.")
	assert_eq(imp.current_state, EnemyImp.ImpState.STACK_MOUNT)
	assert_eq(ally1.current_state, EnemyImp.ImpState.STACK_MOUNT)
	assert_eq(ally2.current_state, EnemyImp.ImpState.STACK_MOUNT)


## Verifies PoweredLight3D flickers when imp is within radius and restores on death.
func test_imp_powered_light_flicker_and_restore() -> void:
	var light_rig: PoweredLight3D = _create_mock_powered_light(Vector3(2.0, 0.0, 0.0))
	assert_eq(light_rig.flicker_preset, PoweredLight3D.FlickerPreset.NORMAL)

	imp._update_nearby_lights()
	assert_ne(
		light_rig.flicker_preset,
		PoweredLight3D.FlickerPreset.NORMAL,
		"Nearby PoweredLight3D should switch to a random flicker preset."
	)

	imp.health_component.take_damage(imp.health_component.current_health)
	assert_eq(
		light_rig.flicker_preset,
		PoweredLight3D.FlickerPreset.NORMAL,
		"PoweredLight3D must restore its original preset when the imp dies."
	)


## Verifies water dive-bomb explodes, electrifies submerged player, and kills the imp.
func test_imp_water_dive_bomb_electrifies_and_dies() -> void:
	var water_node: Node3D = Node3D.new()
	water_node.name = "MockWaterBody"
	_test_root.add_child(water_node)

	var swim_area: Area3D = Area3D.new()
	swim_area.name = "SwimmableArea3D"
	swim_area.add_to_group(&"water_area")
	swim_area.collision_layer = 0
	swim_area.collision_mask = CollisionLayers.MASK_PLAYER
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(10.0, 4.0, 10.0)
	col.shape = box
	swim_area.add_child(col)
	water_node.add_child(swim_area)

	var player: CharacterBody3D = _create_mock_player(Vector3(0.0, 0.0, 0.0))
	var player_hc: HealthComponent = (
		NodeQuery.find_first_child_of_type(player, HealthComponent) as HealthComponent
	)
	var start_hp: int = player_hc.current_health

	# Wait physics frames for Area3D overlap registration before dive-bomb detonation.
	await wait_physics_frames(2)
	var dive_exploded: Array[bool] = [false]
	imp.water_dive_exploded.connect(
		func(_water: Node3D, _pos: Vector3) -> void: dive_exploded[0] = true
	)
	imp.begin_water_dive(water_node)
	assert_eq(imp.current_state, EnemyImp.ImpState.WATER_DIVE)
	imp._detonate_water_dive()

	assert_true(dive_exploded[0], "Water dive-bomb should emit water_dive_exploded.")
	assert_lt(player_hc.current_health, start_hp)


## Verifies imp.tscn instantiates with rigged model, MoodComponent, TacticalAgent, and components.
func test_imp_scene_instantiation() -> void:
	var inst: Node = IMP_SCENE.instantiate()
	_test_root.add_child(inst)
	assert_true(inst is EnemyImp, "imp.tscn root must be EnemyImp.")
	var scene_imp: EnemyImp = inst as EnemyImp
	assert_not_null(scene_imp.tactical_agent)
	assert_not_null(scene_imp.health_component)
	assert_not_null(scene_imp.faction_component)
	assert_not_null(scene_imp.mood_component)


## Builds a minimal player CharacterBody3D with HealthComponent and FactionComponent.
func _create_mock_player(pos: Vector3) -> CharacterBody3D:
	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group(&"player")
	player.collision_layer = CollisionLayers.MASK_PLAYER
	player.position = pos

	var col: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	col.shape = cap
	player.add_child(col)

	var fc: FactionComponent = FactionComponent.new()
	fc.name = "FactionComponent"
	fc.faction = Types.Faction.PLAYER
	player.add_child(fc)

	var hc: HealthComponent = HealthComponent.new()
	hc.name = "HealthComponent"
	hc.max_health = 100
	hc.use_pooling = false
	player.add_child(hc)

	_test_root.add_child(player)
	return player


## Builds a minimal PoweredLight3D with required Light3D and PowerComponent children.
func _create_mock_powered_light(pos: Vector3) -> PoweredLight3D:
	var light_rig: PoweredLight3D = PoweredLight3D.new()
	light_rig.position = pos
	light_rig.flicker_preset = PoweredLight3D.FlickerPreset.NORMAL

	var spot: SpotLight3D = SpotLight3D.new()
	spot.name = "SpotLight3D"
	light_rig.add_child(spot)

	var pc: PowerComponent = PowerComponent.new()
	pc.name = "PowerComponent"
	light_rig.add_child(pc)

	_test_root.add_child(light_rig)
	return light_rig
