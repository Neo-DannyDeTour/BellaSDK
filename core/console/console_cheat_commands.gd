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
			"give", "Adds an item into player inventory.", _cmd_give, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"give_ammo",
			"Adds specified ammo type into inventory.",
			_cmd_give_ammo,
			func() -> Array[String]: return ["bullet", "energy", "shell", "rocket"],
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
	_register_easter_eggs(registry)


## Returns enemy identifier keys for spawnenemy autocomplete.
func _get_enemy_options() -> Array[String]:
	var keys: Array[String] = []
	for k: String in ENEMY_SCENE_PATHS.keys():
		keys.append(k)
	return keys


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


## Grants an item directly to player inventory via event bus.
func _cmd_give(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_give called with args: ", args)
	if args.is_empty():
		context.write("Usage: give <item_name> [amount]", "yellow")
		return

	var item_name: String = args[0].to_lower()
	var amount: int = args[1].to_int() if args.size() > 1 else 1
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
	Events.ammo_collected.emit(StringName(ammo_type), amount)
	context.write("Given %d x '%s' ammo." % [amount, ammo_type], "green")


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


## Registers easter egg and cheat console commands.
func _register_easter_eggs(registry: ConsoleCommandRegistry) -> void:
	print("ConsoleCheatCommands: Registering easter egg commands.")
	registry.register_command(
		ConsoleCommand.new(
			"iddqd", "", func(_a: PackedStringArray) -> void: context.write("good memory!", "gold")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"idkfa",
			"",
			func(_a: PackedStringArray) -> void: context.write("another classic", "gold")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"kirov",
			"",
			func(_a: PackedStringArray) -> void: context.write("Kirov reporting!", "red")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"soyuz", "", func(_a: PackedStringArray) -> void: context.write("Nerushimuy!")
		)
	)
	registry.register_command(ConsoleCommand.new("motherlode", "", _cmd_motherlode))
	registry.register_command(ConsoleCommand.new("konami", "", _cmd_konami))
	registry.register_command(
		ConsoleCommand.new("upupdowndownleftrightleftrightbastart", "", _cmd_upupdowndown)
	)
	registry.register_command(ConsoleCommand.new("showmethemoney", "", _cmd_showmethemoney))
	registry.register_command(ConsoleCommand.new("thereisnocowlevel", "", _cmd_thereisnocowlevel))
	registry.register_command(ConsoleCommand.new("whosyourdaddy", "", _cmd_whosyourdaddy))
	registry.register_command(ConsoleCommand.new("dnkroz", "", _cmd_dnkroz))
	registry.register_command(ConsoleCommand.new("hesoyam", "", _cmd_hesoyam))
	registry.register_command(ConsoleCommand.new("leavemealone", "", _cmd_leavemealone))
	registry.register_command(ConsoleCommand.new("thegodfather", "", _cmd_thegodfather))
	registry.register_command(ConsoleCommand.new("sv_cheats", "", _cmd_sv_cheats))
	registry.register_command(ConsoleCommand.new("impulse", "", _cmd_impulse))


## Easter egg handler for sv_cheats command.
func _cmd_sv_cheats(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_sv_cheats called with args: ", args)
	if not args.is_empty() and args[0] == "1":
		context.write("You don't need it. God gave us enough impulse.", "white")
	else:
		context.write("Usage: sv_cheats 1", "red")


## Easter egg handler for impulse command.
func _cmd_impulse(args: PackedStringArray) -> void:
	print("ConsoleCheatCommands: _cmd_impulse called with args: ", args)
	if not args.is_empty() and args[0] == "101":
		context.write("Bella is a trained professional.", "white")
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
