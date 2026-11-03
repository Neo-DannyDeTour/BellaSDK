## Registers and executes developer cheats, enemy spawners, and easter egg console commands.
class_name ConsoleCheatCommands
extends RefCounted

## Maps enemy identifier strings to their scene resource file paths.
const ENEMY_SCENE_PATHS: Dictionary[String, String] = {
	"bear_trap": "res://enemies/bear_trap.tscn",
	"beartrap": "res://enemies/bear_trap.tscn",
	"flying_tile": "res://enemies/flying_tile.tscn",
	"flyingtile": "res://enemies/flying_tile.tscn",
	"guardian_pillar": "res://enemies/guardian_pillar.tscn",
	"pillar": "res://enemies/guardian_pillar.tscn",
	"rook_trap": "res://enemies/rook_trap.tscn",
	"rook": "res://enemies/rook_trap.tscn",
	"tentacle": "res://enemies/tentacle_enemy.tscn",
	"tentacle_enemy": "res://enemies/tentacle_enemy.tscn",
	"turret": "res://enemies/turret.tscn"
}

## Maps weapon identifier strings to their scene resource file paths.
const WEAPON_SCENE_PATHS: Dictionary[String, String] = {
	"grenade": "res://weapons/smoke_grenade/smoke_grenade_weapon.tscn",
	"revolver": "res://assets/weapons/revolver.tscn",
	"rocket": "res://weapons/signal_rocket/signal_rocket_weapon.tscn",
	"shotgun": "res://assets/weapons/shotgun.tscn",
	"signal_rocket": "res://weapons/signal_rocket/signal_rocket_weapon.tscn",
	"smoke_grenade": "res://weapons/smoke_grenade/smoke_grenade_weapon.tscn",
}

## Maps physical item identifier strings to their scene resource file paths.
const ITEM_SCENE_PATHS: Dictionary[String, String] = {
	"glider": "res://interactables/glider_item.tscn",
	"lever": "res://interactables/lever_stick_item.tscn",
	"lever_stick": "res://interactables/lever_stick_item.tscn",
}

## Maps keycard identifier strings to system clearance identifier tokens.
const KEYCARD_CLEARANCE_MAP: Dictionary[String, StringName] = {
	"card_g": &"G",
	"card_l": &"L",
	"card_r": &"R",
	"keycard_admin": &"AdminCard",
	"keycard_alpha": &"SecurityAlpha",
	"keycard_g": &"G",
	"keycard_l": &"L",
	"keycard_r": &"R",
}

## Maps ammunition alias names to canonical ammo StringName keys.
const AMMO_TYPE_MAP: Dictionary[String, StringName] = {
	"bullet": &"revolver",
	"bullets": &"revolver",
	"grenade": &"smoke_grenade",
	"revolver": &"revolver",
	"revolver_ammo": &"revolver",
	"rocket": &"signal_rocket",
	"shell": &"shotgun",
	"shells": &"shotgun",
	"shotgun": &"shotgun",
	"shotgun_ammo": &"shotgun",
	"signal_rocket": &"signal_rocket",
	"smoke_grenade": &"smoke_grenade",
}

## Context reference providing output logging and scene tree access.
var context: ConsoleContext = null


## Constructs a new [ConsoleCheatCommands] module with the given [param p_context].
func _init(p_context: ConsoleContext) -> void:
	context = p_context


## Registers cheat and gameplay debug commands into the provided [param registry].
func register_commands(registry: ConsoleCommandRegistry) -> void:
	print("ConsoleCheatCommands: Registering cheat and debug commands.")
	registry.register_command(
		ConsoleCommand.new(
			"god", "Toggles godmode invulnerability.", _cmd_god, context.get_toggle_options, true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"noclip",
			"Toggles noclip collision mode.",
			_cmd_noclip,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"fly", "Toggles flight navigation mode.", _cmd_fly, context.get_toggle_options, true
		)
	)
	registry.register_command(
		ConsoleCommand.new("die", "Kills player instantly.", _cmd_die, Callable(), true)
	)
	registry.register_command(
		ConsoleCommand.new(
			"sethealth", "Sets player health value directly.", _cmd_sethealth, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"teleport", "Teleports player to XYZ coordinates.", _cmd_teleport, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"printpos", "Prints current player coordinates.", _cmd_printpos, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"reloadmap", "Reloads current scene tree state.", _cmd_reloadmap, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"showcolliders",
			"Toggles collision shape debug visualization.",
			_cmd_showcolliders,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"showfps",
			"Toggles performance diagnostic HUD.",
			_cmd_showfps,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"stat_fps", "Alias for showfps command.", _cmd_showfps, context.get_toggle_options, true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"showtrigger",
			"Toggles trigger visualizer mesh visibility.",
			_cmd_showtrigger,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"hidetrigger",
			"Hides all trigger visualizer meshes.",
			_cmd_hidetrigger,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"give",
			"Adds an item, weapon, or keycard into player inventory.",
			_cmd_give,
			_get_give_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"give_ammo",
			"Adds specified ammo type into player reserves.",
			_cmd_give_ammo,
			_get_ammo_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"infinite_ammo",
			"Toggles infinite reserve ammunition.",
			_cmd_infinite_ammo,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"inf_ammo",
			"Toggles infinite reserve ammunition (alias).",
			_cmd_infinite_ammo,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"spawnenemy", "Instantiates an enemy entity.", _cmd_spawnenemy, _get_enemy_options, true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"killall", "Destroys active entities in enemies group.", _cmd_killall, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"sv_gravity",
			"Overrides global physics gravity magnitude.",
			_cmd_sv_gravity,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"rain_vfx",
			"Toggles screen rain VFX intensity and uneven timing mode.",
			_cmd_rain_vfx,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"infinite_swim",
			"Toggles infinite swimming oxygen.",
			_cmd_infinite_swim,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"inf_swim",
			"Toggles infinite swimming oxygen (alias).",
			_cmd_infinite_swim,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"noclip_speed",
			"Sets noclip flight movement speed multiplier.",
			_cmd_noclip_speed,
			func() -> Array[String]: return ["1.0", "4.0", "8.0", "16.0", "32.0"],
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"playerspeed",
			"Scales player movement velocities by a multiplier factor.",
			_cmd_playerspeed,
			func() -> Array[String]: return ["1.0", "1.5", "2.0", "3.0", "reset"],
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"speed",
			"Scales player movement velocities (alias).",
			_cmd_playerspeed,
			func() -> Array[String]: return ["1.0", "1.5", "2.0", "3.0", "reset"],
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"giveall",
			"Grants full weapon arsenal, max ammunition, and all keycards.",
			_cmd_giveall,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"allweapons",
			"Grants full weapon arsenal, max ammunition, and all keycards (alias).",
			_cmd_giveall,
			Callable(),
			true
		)
	)
	_register_easter_eggs(registry)


## Returns enemy identifier keys for spawnenemy autocomplete.
func _get_enemy_options() -> Array[String]:
	var keys: Array[String] = []
	for k: String in ENEMY_SCENE_PATHS.keys():
		keys.append(k)
	return keys


## Returns autocomplete candidates for the give command.
func _get_give_options() -> Array[String]:
	return [
		"ammo",
		"glider",
		"grenade",
		"keycard_admin",
		"keycard_alpha",
		"keycard_g",
		"keycard_l",
		"keycard_r",
		"lever",
		"revolver",
		"revolver_ammo",
		"rocket",
		"shotgun",
		"shotgun_ammo",
		"signal_rocket",
		"smoke_grenade",
	]


## Returns autocomplete candidates for the give_ammo command.
func _get_ammo_options() -> Array[String]:
	return ["bullet", "grenade", "revolver", "rocket", "shell", "shotgun", "signal_rocket"]


## Toggles godmode invulnerability on the active player.
func _cmd_god(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("god", false), "god"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["god"] = active
	print("ConsoleCheatCommands: Toggled godmode -> ", active)
	Events.set(&"is_godmode", active)
	Events.godmode_toggled.emit(active)
	context.write("Godmode " + ("activated." if active else "deactivated."), "green")


## Handles noclip command toggling.
func _cmd_noclip(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: Action toggling noclip.")
	var current: bool = context.get_toggle_state("noclip", false)
	var parsed: Variant = context.parse_toggle_arg(args, current, "noclip")
	if parsed == null:
		return
	var active: bool = parsed == true
	if active != current:
		Events.noclip_ui_button_pressed.emit()
	context.write("Noclip " + ("activated." if active else "deactivated."), "green")


## Toggles gravity-free flight navigation mode via event bus.
func _cmd_fly(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("fly", false), "fly"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["fly"] = active
	print("ConsoleCheatCommands: Toggled fly mode -> ", active)
	Events.flight_mode_toggled.emit(active)
	context.write("Fly mode " + ("activated." if active else "deactivated."), "green")


## Handles die debug command by broadcasting kill request to event bus.
func _cmd_die(_args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: Action Executing 'die' command.")
	Events.player_health_set_requested.emit(0)
	Events.player_kill_requested.emit()
	context.write("Player kill signal dispatched.", "red")


## Handles sethealth debug command with input validation via event bus.
func _cmd_sethealth(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: Action Executing 'sethealth' command.")
	if args.is_empty() or not args[0].is_valid_int():
		context.write("Usage: sethealth <value 0-300>", "yellow")
		return

	var health_val: int = clampi(args[0].to_int(), 0, 300)
	Events.player_health_set_requested.emit(health_val)
	context.write("Player health set request broadcast: " + str(health_val), "green")


## Teleports the player entity to target coordinates via event bus.
func _cmd_teleport(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_teleport called with args: ", args)
	if args.size() < 3:
		context.write("Usage: teleport <x> <y> <z>", "yellow")
		return

	var target_pos: Vector3 = Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
	Events.teleport_requested.emit(target_pos)
	context.write("Teleport command dispatched to: " + str(target_pos), "green")


## Outputs the player's current global position coordinates.
func _cmd_printpos(_args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: Executing printpos.")
	var player_node: Node3D = context.get_player()
	if not is_instance_valid(player_node):
		context.write("Player entity not found.", "red")
		return

	var pos: Vector3 = player_node.global_position
	var formatted_pos: String = "%.2f, %.2f, %.2f" % [pos.x, pos.y, pos.z]
	print("Player Global Position: ", formatted_pos)
	context.write("Position: " + formatted_pos, "cyan")


## Resets the current scene state without restarting engine.
func _cmd_reloadmap(_args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: Executing reloadmap.")
	context.write("Reloading map...", "yellow")
	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		tree.paused = false
		if (
			is_instance_valid(context.host)
			and context.host.has_method(&"_on_console_toggle_requested")
		):
			context.host.call(&"_on_console_toggle_requested")
		tree.reload_current_scene()


## Toggles debug collision shape rendering in the tree.
func _cmd_showcolliders(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: Action toggling showcolliders.")
	var current: bool = context.get_toggle_state("collision", false)
	var parsed: Variant = context.parse_toggle_arg(args, current, "collision")
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["collision"] = active
	context.toggle_states["showcolliders"] = active
	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		tree.debug_collisions_hint = active
		var colliders: Array[Node] = tree.get_nodes_in_group(&"debug_colliders")
		for col: Node in colliders:
			if col is CanvasItem:
				(col as CanvasItem).visible = active
			elif col is Node3D:
				(col as Node3D).visible = active
	var stat: String = "activated." if active else "deactivated."
	context.write("Collision shapes " + stat, "green")


## Toggles the on-screen FPS and performance diagnostic HUD.
func _cmd_showfps(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("showfps", false), "showfps"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["showfps"] = active
	print("ConsoleCheatCommands: Toggled showfps -> ", active)
	Events.metrics_panel_toggle_requested.emit()
	context.write("FPS monitor " + ("enabled." if active else "disabled."), "green")


## Toggles or explicitly sets visibility of trigger visualizers.
func _cmd_showtrigger(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_showtrigger called with args: ", args)
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("showtrigger", false), "showtrigger"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	_set_trigger_visibility(active)


## Explicitly hides all trigger visualizer meshes in the world.
func _cmd_hidetrigger(_args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_hidetrigger called.")
	_set_trigger_visibility(false)


## Propagates trigger visibility state to event bus and groups.
func _set_trigger_visibility(active: bool) -> void:
	print("ConsoleCheatCommands: Setting trigger visibility to: ", active)
	context.toggle_states["showtrigger"] = active
	EditorTriggerVisualizer.set_global_debug_visibility(active)
	Events.trigger_visibility_toggled.emit(active)
	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		tree.call_group(&"trigger_visualizers", "set_debug_visibility", active)

	var stat: String = "visible." if active else "hidden."
	context.write("Triggers set to " + stat, "green")


## Grants an item, weapon, ammo, or keycard directly to the player.
func _cmd_give(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_give called with args: ", args)
	if args.is_empty():
		context.write("Usage: give <weapon | ammo | keycard | item> [amount]", "yellow")
		return

	var item_name: String = args[0].to_lower()
	var amount: int = args[1].to_int() if args.size() > 1 else 1

	if item_name == "ammo":
		if args.size() < 2:
			context.write("Usage: give ammo <type> [amount]", "yellow")
			return
		var ammo_type: String = args[1].to_lower()
		var ammo_amount: int = args[2].to_int() if args.size() > 2 else 30
		_apply_give_ammo(ammo_type, ammo_amount)
		return

	if WEAPON_SCENE_PATHS.has(item_name):
		var player_node: Node3D = context.get_player()
		if not is_instance_valid(player_node):
			context.write("Player entity not found.", "red")
			return
		var inv: WeaponInventoryComponent = (
			player_node.find_child("WeaponInventoryComponent", true, false)
			as WeaponInventoryComponent
		)
		if not is_instance_valid(inv):
			context.write("WeaponInventoryComponent not found on player.", "red")
			return
		var tree: SceneTree = context.get_tree()
		if not is_instance_valid(tree) or not is_instance_valid(tree.current_scene):
			context.write("Current scene tree invalid.", "red")
			return
		var reserve_grant: int = -1 if args.size() <= 1 else amount
		_grant_or_topup_weapon(player_node, inv, tree, item_name, reserve_grant)
		context.write("Granted weapon '%s' to player." % item_name, "green")
		return

	if AMMO_TYPE_MAP.has(item_name):
		var ammo_count: int = amount if args.size() > 1 else 30
		_apply_give_ammo(item_name, ammo_count)
		return

	if KEYCARD_CLEARANCE_MAP.has(item_name):
		var clearance_id: StringName = KEYCARD_CLEARANCE_MAP[item_name]
		var tree: SceneTree = context.get_tree()
		if is_instance_valid(tree) and is_instance_valid(tree.root):
			var keycard_sys: Node = tree.root.get_node_or_null("KeycardSystem")
			if is_instance_valid(keycard_sys) and keycard_sys.has_method(&"add_card"):
				keycard_sys.call(&"add_card", clearance_id)
		Events.keycard_collected.emit(clearance_id)
		context.write(
			"Added keycard clearance '%s' to KeycardSystem." % String(clearance_id), "green"
		)
		return

	if ITEM_SCENE_PATHS.has(item_name):
		var player_node: Node3D = context.get_player()
		if not is_instance_valid(player_node):
			context.write("Player entity not found.", "red")
			return
		var tree: SceneTree = context.get_tree()
		if not is_instance_valid(tree) or not is_instance_valid(tree.current_scene):
			context.write("Current scene tree invalid.", "red")
			return
		var item_path: String = ITEM_SCENE_PATHS[item_name]
		if not ResourceLoader.exists(item_path):
			context.write("Scene file not found: " + item_path, "red")
			return
		var packed_item: PackedScene = load(item_path) as PackedScene
		if not is_instance_valid(packed_item):
			context.write("Failed to load scene: " + item_path, "red")
			return
		var item_instance: Node = packed_item.instantiate()
		tree.current_scene.add_child(item_instance)
		var grabbed: bool = false
		if item_instance is RigidBody3D:
			var interact_comp: Node = player_node.find_child("InteractionComponent", true, false)
			if is_instance_valid(interact_comp) and interact_comp.has_method(&"force_grab_item"):
				interact_comp.call(&"force_grab_item", item_instance as RigidBody3D)
				grabbed = true
		if not grabbed and item_instance is Node3D:
			var forward_vec: Vector3 = -player_node.global_transform.basis.z.normalized()
			(item_instance as Node3D).global_position = (
				player_node.global_position + forward_vec * 1.5 + Vector3.UP * 0.5
			)
		context.write("Granted physical item '%s' to player." % item_name, "green")
		return

	Events.inventory_item_given.emit(item_name, amount)
	context.write("Given %d x '%s' to player." % [amount, item_name], "green")


## Grants ammunition directly to player reserves.
func _cmd_give_ammo(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_give_ammo called with args: ", args)
	if args.is_empty():
		context.write("Usage: give_ammo <ammo_type> [amount]", "yellow")
		return

	var ammo_type: String = args[0].to_lower()
	var amount: int = args[1].to_int() if args.size() > 1 else 30
	_apply_give_ammo(ammo_type, amount)


## Adds reserve ammunition to matching weapons in the player inventory.
func _apply_give_ammo(ammo_type_str: String, amount: int) -> void:
	var player_node: Node3D = context.get_player()
	if not is_instance_valid(player_node):
		context.write("Player entity not found.", "red")
		return

	var inv: WeaponInventoryComponent = (
		player_node.find_child("WeaponInventoryComponent", true, false) as WeaponInventoryComponent
	)
	if not is_instance_valid(inv):
		context.write("WeaponInventoryComponent not found on player.", "red")
		return

	var resolved_key: StringName = AMMO_TYPE_MAP.get(ammo_type_str, StringName(ammo_type_str))
	var applied: bool = inv.add_ammo(resolved_key, amount)
	Events.ammo_collected.emit(resolved_key, amount)

	if applied:
		context.write(
			"Given %d x '%s' ammo to player reserves." % [amount, String(resolved_key)], "green"
		)
	else:
		context.write(
			"No weapon found for ammo type '%s'. Ammo added to event bus." % String(resolved_key),
			"yellow"
		)


## Grants a weapon to the player inventory or tops up its ammo if already present.
func _grant_or_topup_weapon(
	player: Node3D,
	inv: WeaponInventoryComponent,
	tree: SceneTree,
	w_key: String,
	reserve_amount: int
) -> void:
	var existing: Node3D = null
	for slot_node: Node3D in inv.slots:
		if not is_instance_valid(slot_node):
			continue
		var tag_val: Variant = slot_node.get("weapon_tag")
		if tag_val != null and str(tag_val).to_lower() == w_key:
			existing = slot_node
			break

	if is_instance_valid(existing):
		_topup_weapon_ammo(existing, reserve_amount)
		return

	if not WEAPON_SCENE_PATHS.has(w_key):
		return

	var scene_path: String = WEAPON_SCENE_PATHS[w_key]
	if not ResourceLoader.exists(scene_path):
		return

	var packed: PackedScene = load(scene_path) as PackedScene
	if not is_instance_valid(packed):
		return

	var weapon_instance: Node = packed.instantiate()
	if not (weapon_instance is Node3D):
		return

	tree.current_scene.add_child(weapon_instance)
	if weapon_instance.has_method(&"equip_to_player") and player is CharacterBody3D:
		weapon_instance.call(&"equip_to_player", player as CharacterBody3D)
	elif is_instance_valid(inv.weapon_holder):
		inv.weapon_holder.add_child(weapon_instance)
		inv.register_weapon(weapon_instance as Node3D)

	_topup_weapon_ammo(weapon_instance as Node3D, reserve_amount)


## Tops up magazine and reserve ammunition on a weapon instance, clamping at 5x capacity.
func _topup_weapon_ammo(weapon: Node3D, target_reserve: int) -> void:
	if not is_instance_valid(weapon):
		return

	if weapon is HitscanWeapon:
		var hw: HitscanWeapon = weapon as HitscanWeapon
		var max_res: int = hw.ammo_capacity * 5
		var res_to_set: int = hw.ammo_capacity * 2 if target_reserve < 0 else target_reserve
		hw.current_ammo = hw.ammo_capacity
		hw.reserve_ammo = clampi(res_to_set, 0, max_res)
		hw.sync_ammo_ui()
	elif weapon is ThrowableWeapon:
		var tw: ThrowableWeapon = weapon as ThrowableWeapon
		tw.current_ammo = tw.max_ammo
		tw.sync_ammo_ui()
	else:
		var cap_val: Variant = weapon.get("ammo_capacity")
		var cap: int = int(cap_val) if cap_val is int else 6
		var max_res: int = cap * 5
		var res_to_set: int = cap * 2 if target_reserve < 0 else target_reserve
		weapon.set("current_ammo", cap)
		weapon.set("reserve_ammo", clampi(res_to_set, 0, max_res))
		if weapon.has_method(&"sync_ammo_ui"):
			weapon.call(&"sync_ammo_ui")


## Toggles infinite reserve ammunition via accessibility settings.
func _cmd_infinite_ammo(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_infinite_ammo called with args: ", args)
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("infinite_ammo", false), "infinite_ammo"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["infinite_ammo"] = active
	GlobalSettings.save_setting("Accessibility", "infinite_ammo", active, true)
	if Events.has_signal(&"infinite_ammo_toggled"):
		Events.infinite_ammo_toggled.emit(active)
	context.write("Infinite ammo " + ("activated." if active else "deactivated."), "green")


## Spawns an enemy instance in front of player orientation.
func _cmd_spawnenemy(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_spawnenemy called with args: ", args)
	if args.is_empty():
		var valid_list: PackedStringArray = PackedStringArray(ENEMY_SCENE_PATHS.keys())
		var msg: String = "Usage: spawnenemy <name>\nValid: " + ", ".join(valid_list)
		context.write(msg, "yellow")
		return

	var enemy_key: String = args[0].to_lower()
	if not ENEMY_SCENE_PATHS.has(enemy_key):
		context.write("Unknown enemy: '" + enemy_key + "'.", "red")
		return

	var scene_path: String = ENEMY_SCENE_PATHS[enemy_key]
	if not ResourceLoader.exists(scene_path):
		context.write("Scene file not found: " + scene_path, "red")
		return

	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if not packed_scene:
		context.write("Failed to load scene: " + scene_path, "red")
		return

	var enemy_node: Node = packed_scene.instantiate()
	var player_node: Node3D = context.get_player()
	if is_instance_valid(player_node) and enemy_node is Node3D:
		var spawn_offset: Vector3 = player_node.global_transform.basis.z * 3.0
		var spawn_pos: Vector3 = player_node.global_position - spawn_offset
		(enemy_node as Node3D).global_position = spawn_pos

	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree) and is_instance_valid(tree.current_scene):
		tree.current_scene.add_child(enemy_node)
	context.write("Spawned enemy '" + enemy_key + "' successfully.", "green")


## Destroys active enemy entities without deep recursion.
func _cmd_killall(_args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: Executing killall.")
	var tree: SceneTree = context.get_tree()
	if not is_instance_valid(tree):
		return
	var enemies: Array[Node] = tree.get_nodes_in_group(&"enemies")
	var count: int = 0

	for enemy: Node in enemies:
		if not is_instance_valid(enemy) or enemy.is_in_group(&"player"):
			continue

		var hc: HealthComponent = (
			NodeQuery.find_first_child_of_type(enemy, HealthComponent) as HealthComponent
		)
		if is_instance_valid(hc) and hc.has_method(&"take_damage"):
			hc.take_damage(99999)
			count += 1
		elif enemy.has_method(&"die"):
			enemy.call(&"die")
			count += 1
		elif enemy is Node3D:
			enemy.queue_free()
			count += 1

	context.write("Destroyed %d active entities." % count, "green")


## Overrides global physics gravity magnitude via event bus.
func _cmd_sv_gravity(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_sv_gravity called with args: ", args)
	if args.is_empty():
		var cur_g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
		var msg: String = "Current gravity: " + str(cur_g) + ". Usage: sv_gravity <val>"
		context.write(msg, "yellow")
		return

	var grav: float = args[0].to_float()
	var vp: Viewport = context.get_viewport()
	if is_instance_valid(vp) and is_instance_valid(vp.find_world_3d()):
		PhysicsServer3D.area_set_param(
			vp.find_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, grav
		)
	Events.gravity_override_requested.emit(grav)
	context.write("Global physics gravity updated to: " + str(grav), "green")


## Toggles or sets screen rain VFX intensity and uneven timing mode.
func _cmd_rain_vfx(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_rain_vfx called with args: ", args)
	var intensity: float = 0.8
	var uneven: bool = true

	if not args.is_empty():
		var first_arg: String = args[0].to_lower()
		if first_arg in ["0", "off", "false", "stop"]:
			intensity = 0.0
		elif first_arg in ["1", "on", "true"]:
			intensity = 0.8
		else:
			intensity = clampf(first_arg.to_float(), 0.0, 2.0)

	if args.size() > 1:
		var second_arg: String = args[1].to_lower()
		uneven = second_arg not in ["0", "false", "off", "even"]

	var tree: SceneTree = context.get_tree()
	if not is_instance_valid(tree):
		return
	var effects_mgr: ScreenEffectsManager = (
		tree.root.find_child("ScreenEffectsManager", true, false) as ScreenEffectsManager
	)
	if is_instance_valid(effects_mgr):
		effects_mgr.set_rain_uneven_timing(uneven)
		effects_mgr.set_rain_screen_active(intensity > 0.001, intensity)
	else:
		Events.rain_vfx_toggled.emit(intensity)

	var status: String = (
		"Rain VFX set to intensity %.2f (uneven_timing: %s)" % [intensity, str(uneven)]
	)
	context.write(status, "green" if intensity > 0.0 else "yellow")


## Toggles infinite swimming oxygen via accessibility settings.
func _cmd_infinite_swim(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_infinite_swim called with args: ", args)
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("infinite_swim", false), "infinite_swim"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["infinite_swim"] = active
	GlobalSettings.save_setting("Accessibility", "infinite_swim", active, true)
	if Events.has_signal(&"infinite_swim_toggled"):
		Events.infinite_swim_toggled.emit(active)
	context.write("Infinite swim " + ("activated." if active else "deactivated."), "green")


## Sets noclip flight speed multiplier on the player controller.
func _cmd_noclip_speed(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_noclip_speed called with args: ", args)
	if args.is_empty():
		context.write("Usage: noclip_speed <float> (e.g. 1.0, 8.0, 16.0)", "yellow")
		return

	var raw_str: String = args[0].strip_edges()
	if not raw_str.is_valid_float():
		context.write("Invalid speed value. Please provide a positive float.", "red")
		return

	var speed: float = clampf(raw_str.to_float(), 0.1, 100.0)
	var player: Node3D = context.get_player()
	if is_instance_valid(player):
		var smc: Node = player.get_node_or_null("SystemMenuController")
		if is_instance_valid(smc):
			smc.set("noclip_speed_multiplier", speed)

	if Events.has_signal(&"noclip_speed_changed"):
		Events.noclip_speed_changed.emit(speed)
	context.write("Noclip speed set to: %.1f" % speed, "green")


## Scales player movement speeds by a factor or resets them to defaults.
func _cmd_playerspeed(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_playerspeed called with args: ", args)
	var player: Node3D = context.get_player()
	if not is_instance_valid(player):
		context.write("Player node not found in scene tree.", "red")
		return

	var loco: Node = player.get_node_or_null("LocomotionComponent")
	if not is_instance_valid(loco):
		loco = player.get("locomotion_component") as Node
	if not is_instance_valid(loco):
		context.write("LocomotionComponent not found on player.", "red")
		return

	if args.is_empty():
		var cur_walk: Variant = loco.get("walking_speed")
		var cur_sprint: Variant = loco.get("sprinting_speed")
		var walk_f: float = float(cur_walk) if cur_walk != null else 5.0
		var sprint_f: float = float(cur_sprint) if cur_sprint != null else 6.5
		context.write(
			(
				"Current speeds - Walk: %.1f | Sprint: %.1f. Usage: playerspeed <mult|reset>"
				% [walk_f, sprint_f]
			),
			"yellow"
		)
		return

	var token: String = args[0].strip_edges().to_lower()
	if token == "reset" or token == "default":
		loco.set("walking_speed", 5.0)
		loco.set("sprinting_speed", 6.5)
		loco.set("crouching_speed", 3.0)
		context.write("Player movement speeds reset to defaults (Walk: 5.0, Sprint: 6.5).", "green")
		return

	if not token.is_valid_float():
		context.write(
			"Invalid speed multiplier. Provide a float (e.g. 1.5, 2.0) or 'reset'.", "red"
		)
		return

	var mult: float = clampf(token.to_float(), 0.1, 10.0)
	loco.set("walking_speed", 5.0 * mult)
	loco.set("sprinting_speed", 6.5 * mult)
	loco.set("crouching_speed", 3.0 * mult)
	context.write(
		"Player speed scaled by %.1fx (Walk: %.1f, Sprint: %.1f)." % [mult, 5.0 * mult, 6.5 * mult],
		"green"
	)


## Grants all weapons, maximum ammunition reserves, and all keycards.
func _cmd_giveall(_args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_giveall called.")
	for card_alias: String in KEYCARD_CLEARANCE_MAP:
		var clearance_key: StringName = KEYCARD_CLEARANCE_MAP[card_alias]
		KeycardSystem.add_card(clearance_key)

	var player_node: Node3D = context.get_player()
	if not is_instance_valid(player_node):
		context.write("Keycards granted. Player entity not found for weapons.", "yellow")
		return

	var inv: WeaponInventoryComponent = (
		player_node.find_child("WeaponInventoryComponent", true, false) as WeaponInventoryComponent
	)
	if not is_instance_valid(inv):
		context.write("WeaponInventoryComponent not found on player.", "red")
		return

	var tree: SceneTree = context.get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.current_scene):
		context.write("Current scene tree invalid.", "red")
		return

	var weapon_keys: Array[String] = [
		"revolver",
		"shotgun",
		"signal_rocket",
		"smoke_grenade",
	]
	for w_key: String in weapon_keys:
		_grant_or_topup_weapon(player_node, inv, tree, w_key, 9999)

	context.write("giveall: Full arsenal, ammunition, and keycards granted.", "green")


## Registers easter egg and cheat console commands.
func _register_easter_eggs(registry: ConsoleCommandRegistry) -> void:
	print("ConsoleCheatCommands: Registering easter egg commands.")
	registry.register_command(
		ConsoleCommand.new(
			"iddqd",
			"",
			func(_a: PackedStringArray) -> void: context.write("good memory!", "gold"),
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"idkfa",
			"",
			func(_a: PackedStringArray) -> void: context.write("another classic", "gold"),
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"kirov",
			"",
			func(_a: PackedStringArray) -> void: context.write("Kirov reporting!", "red"),
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"soyuz",
			"",
			func(_a: PackedStringArray) -> void: context.write("Nerushimuy!"),
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new("motherlode", "", _cmd_motherlode, Callable(), true)
	)
	registry.register_command(ConsoleCommand.new("konami", "", _cmd_konami, Callable(), true))
	registry.register_command(
		ConsoleCommand.new(
			"upupdowndownleftrightleftrightbastart", "", _cmd_upupdowndown, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new("showmethemoney", "", _cmd_showmethemoney, Callable(), true)
	)
	registry.register_command(
		ConsoleCommand.new("thereisnocowlevel", "", _cmd_thereisnocowlevel, Callable(), true)
	)
	registry.register_command(
		ConsoleCommand.new("whosyourdaddy", "", _cmd_whosyourdaddy, Callable(), true)
	)
	registry.register_command(ConsoleCommand.new("dnkroz", "", _cmd_dnkroz, Callable(), true))
	registry.register_command(ConsoleCommand.new("hesoyam", "", _cmd_hesoyam, Callable(), true))
	registry.register_command(
		ConsoleCommand.new("leavemealone", "", _cmd_leavemealone, Callable(), true)
	)
	registry.register_command(
		ConsoleCommand.new("thegodfather", "", _cmd_thegodfather, Callable(), true)
	)
	registry.register_command(ConsoleCommand.new("sv_cheats", "", _cmd_sv_cheats, Callable(), true))
	registry.register_command(ConsoleCommand.new("impulse", "", _cmd_impulse, Callable(), true))


## Easter egg handler for sv_cheats command.
func _cmd_sv_cheats(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_sv_cheats called with args: ", args)
	if not args.is_empty() and args[0] == "1":
		context.write("You don't need it. God gave us enough impulse.", "white")
	else:
		context.write("Usage: sv_cheats 1", "red")


## Executes impulse cheat granting full weapons and ammunition max-out.
func _cmd_impulse(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_impulse called with args: ", args)
	if not args.is_empty() and args[0] == "101":
		var player_node: Node3D = context.get_player()
		if not is_instance_valid(player_node):
			context.write("Player entity not found.", "red")
			return

		var inv: WeaponInventoryComponent = (
			player_node.find_child("WeaponInventoryComponent", true, false)
			as WeaponInventoryComponent
		)
		if not is_instance_valid(inv):
			context.write("WeaponInventoryComponent not found on player.", "red")
			return

		var tree: SceneTree = context.get_tree()
		if not is_instance_valid(tree) or not is_instance_valid(tree.current_scene):
			context.write("Current scene tree invalid.", "red")
			return

		var weapon_keys: Array[String] = [
			"revolver",
			"shotgun",
			"signal_rocket",
			"smoke_grenade",
		]
		for w_key: String in weapon_keys:
			_grant_or_topup_weapon(player_node, inv, tree, w_key, 9999)

		context.write("impulse 101: Arsenal granted with max ammunition.", "green")
	else:
		context.write("Usage: impulse 101", "red")


## Easter egg handler for motherlode command.
func _cmd_motherlode(_args: PackedStringArray) -> void:
	context.write("This is a classic get-rich-quick scheme! Arrested!")


## Easter egg handler for konami command.
func _cmd_konami(_args: PackedStringArray) -> void:
	context.write("Fuck Konami and thank god for Jimbo")


## Easter egg handler for upupdowndownleftrightleftrightbastart command.
func _cmd_upupdowndown(_args: PackedStringArray) -> void:
	context.write("30 lives to this miss!")


## Easter egg handler for showmethemoney command.
func _cmd_showmethemoney(_args: PackedStringArray) -> void:
	context.write("All I have is 10 bucks")


## Easter egg handler for thereisnocowlevel command.
func _cmd_thereisnocowlevel(_args: PackedStringArray) -> void:
	context.write("There is none! I swear!")


## Easter egg handler for whosyourdaddy command.
func _cmd_whosyourdaddy(_args: PackedStringArray) -> void:
	context.write("DannyDeTour, bitch")


## Easter egg handler for dnkroz command.
func _cmd_dnkroz(_args: PackedStringArray) -> void:
	context.write("You're an inspiration for birth control.")


## Easter egg handler for hesoyam command.
func _cmd_hesoyam(_args: PackedStringArray) -> void:
	context.write("What's up, homie?")


## Easter egg handler for leavemealone command.
func _cmd_leavemealone(_args: PackedStringArray) -> void:
	context.write("Tommy! Remember the good old times?!")


## Easter egg handler for thegodfather command.
func _cmd_thegodfather(_args: PackedStringArray) -> void:
	context.write("do not care")
