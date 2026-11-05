## Unit tests for [InGameConsole] functionality and UI suggestion updates.
class_name TestInGameConsole
extends GutTest

## Preloaded scene reference for the in-game console under test.
const CONSOLE_SCENE: PackedScene = preload("res://ui/in_game_console.tscn")

## Preloaded script reference for the spectator freecam camera controller.
const FREECAM_SCRIPT: GDScript = preload("res://core/console/freecam_controller.gd")

## Instance of the console UI under test.
var _console: CanvasLayer = null


## Set up test instance before each test method.
func before_each() -> void:
	print("TestInGameConsole: Instantiating InGameConsole for test.")
	var raw_node: Node = CONSOLE_SCENE.instantiate()
	_console = raw_node as CanvasLayer
	if not is_instance_valid(_console):
		if is_instance_valid(raw_node):
			raw_node.queue_free()
		return
	add_child_autofree(_console)


## Clean up test instance after each test method.
func after_each() -> void:
	print("TestInGameConsole: Cleaning up InGameConsole instance.")


## Tests that _update_suggestion_ui produces correct BBCode output when match_index is active.
func test_update_suggestion_ui_formatting() -> void:
	print("TestInGameConsole: Running test_update_suggestion_ui_formatting().")
	var matches: Array[String] = ["help", "clear", "quit"]
	_console.set("current_matches", matches)
	_console.set("match_index", 1)

	_console.call("_update_suggestion_ui")

	var expected: String = (
		"[color=gray]  help[/color]\n"
		+ "[color=yellow]> clear[/color]\n"
		+ "[color=gray]  quit[/color]"
	)

	var label_node: Node = _console.get_node_or_null(
		"BackgroundPanel/LayoutContainer/SuggestionLog"
	)
	assert_not_null(label_node, "SuggestionLog node should be present.")
	if label_node is RichTextLabel:
		var label: RichTextLabel = label_node
		assert_eq(label.text, expected)


## Tests that _update_suggestion_ui handles empty current_matches cleanly.
func test_update_suggestion_ui_empty() -> void:
	print("TestInGameConsole: Running test_update_suggestion_ui_empty().")
	var empty_matches: Array[String] = []
	_console.set("current_matches", empty_matches)
	_console.set("match_index", -1)

	_console.call("_update_suggestion_ui")

	var label_node: Node = _console.get_node_or_null(
		"BackgroundPanel/LayoutContainer/SuggestionLog"
	)
	assert_not_null(label_node, "SuggestionLog node should be present.")
	if label_node is RichTextLabel:
		var label: RichTextLabel = label_node
		assert_eq(label.text, "")


## Tests that infinite_ammo console command correctly updates settings and state.
func test_infinite_ammo_console_command() -> void:
	print("TestInGameConsole: Running test_infinite_ammo_console_command().")
	_console.call("_cmd_infinite_ammo", PackedStringArray(["on"]))
	assert_true(
		GlobalSettings.get_setting_bool("Accessibility", "infinite_ammo", false),
		"Infinite ammo should be enabled after running command with 'on'."
	)

	_console.call("_cmd_infinite_ammo", PackedStringArray(["off"]))
	assert_false(
		GlobalSettings.get_setting_bool("Accessibility", "infinite_ammo", false),
		"Infinite ammo should be disabled after running command with 'off'."
	)

	_console.call("_cmd_infinite_ammo", PackedStringArray())
	assert_true(
		GlobalSettings.get_setting_bool("Accessibility", "infinite_ammo", false),
		"Infinite ammo should be toggled to true when invoked without arguments."
	)
	_console.call("_cmd_infinite_ammo", PackedStringArray(["off"]))


## Tests that toggle commands invert state on subsequent invocations.
func test_toggle_command_double_invocation() -> void:
	print("TestInGameConsole: Running test_toggle_command_double_invocation().")
	var states: Dictionary = _console.get("toggle_states") as Dictionary
	states["wolfvision"] = false

	_console.call("_cmd_wolfvision", PackedStringArray())
	assert_true(states["wolfvision"], "First invocation without args should activate wolfvision.")

	_console.call("_cmd_wolfvision", PackedStringArray())
	assert_false(
		states["wolfvision"], "Second invocation without args should deactivate wolfvision."
	)


## Tests that toggle commands accept 1/0 and on/off arguments.
func test_toggle_command_boolean_tokens() -> void:
	print("TestInGameConsole: Running test_toggle_command_boolean_tokens().")
	var states: Dictionary = _console.get("toggle_states") as Dictionary

	_console.call("_cmd_wolfvision", PackedStringArray(["1"]))
	assert_true(states["wolfvision"], "Argument '1' should turn on wolfvision.")

	_console.call("_cmd_wolfvision", PackedStringArray(["0"]))
	assert_false(states["wolfvision"], "Argument '0' should turn off wolfvision.")

	_console.call("_cmd_wolfvision", PackedStringArray(["on"]))
	assert_true(states["wolfvision"], "Argument 'on' should turn on wolfvision.")

	_console.call("_cmd_wolfvision", PackedStringArray(["off"]))
	assert_false(states["wolfvision"], "Argument 'off' should turn off wolfvision.")


## Tests that invalid toggle arguments do not mutate state.
func test_toggle_command_invalid_argument() -> void:
	print("TestInGameConsole: Running test_toggle_command_invalid_argument().")
	var states: Dictionary = _console.get("toggle_states") as Dictionary
	states["wolfvision"] = false

	_console.call("_cmd_wolfvision", PackedStringArray(["gibberish"]))
	assert_false(states["wolfvision"], "Invalid argument should not mutate toggle state.")


## Tests that autocomplete matches include boolean toggle options.
func test_toggle_command_autocomplete_suggestions() -> void:
	print("TestInGameConsole: Running test_toggle_command_autocomplete_suggestions().")
	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")

	var matches: Array[String] = reg.get_autocomplete_matches("wolfvision ")
	assert_true(matches.has("wolfvision on"), "Suggestions should contain 'wolfvision on'.")
	assert_true(matches.has("wolfvision off"), "Suggestions should contain 'wolfvision off'.")
	assert_true(matches.has("wolfvision 1"), "Suggestions should contain 'wolfvision 1'.")
	assert_true(matches.has("wolfvision 0"), "Suggestions should contain 'wolfvision 0'.")


## Tests that autocomplete matches include give command targets.
func test_give_command_autocomplete_suggestions() -> void:
	print("TestInGameConsole: Running test_give_command_autocomplete_suggestions().")
	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")

	var matches: Array[String] = reg.get_autocomplete_matches("give ")
	assert_true(matches.has("give revolver"), "Suggestions should contain 'give revolver'.")
	assert_true(matches.has("give shotgun"), "Suggestions should contain 'give shotgun'.")
	assert_true(matches.has("give ammo"), "Suggestions should contain 'give ammo'.")
	assert_true(matches.has("give keycard_r"), "Suggestions should contain 'give keycard_r'.")


## Tests that autocomplete matches include ammo types.
func test_give_ammo_command_autocomplete_suggestions() -> void:
	print("TestInGameConsole: Running test_give_ammo_command_autocomplete_suggestions().")
	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")

	var matches: Array[String] = reg.get_autocomplete_matches("give_ammo ")
	assert_true(
		matches.has("give_ammo revolver"), "Suggestions should contain 'give_ammo revolver'."
	)
	assert_true(matches.has("give_ammo shotgun"), "Suggestions should contain 'give_ammo shotgun'.")


## Tests that give command grants keycard clearance to KeycardSystem.
func test_give_keycard_clearance() -> void:
	print("TestInGameConsole: Running test_give_keycard_clearance().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	cheats._cmd_give(PackedStringArray(["keycard_r"]))
	assert_true(KeycardSystem.has_card(&"R"), "KeycardSystem should have card 'R'.")
	KeycardSystem.consume_card(&"R")


## Tests that weapon topup gives 1 + 2 clips by default and clamps to 5x capacity.
func test_weapon_ammo_defaults_and_clamp() -> void:
	print("TestInGameConsole: Running test_weapon_ammo_defaults_and_clamp().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	var revolver: Revolver = Revolver.new()
	autofree(revolver)
	revolver.ammo_capacity = 6

	# Default topup (target_reserve = -1) -> 1 loaded + 2 clips reserve = 6 / 12
	cheats._topup_weapon_ammo(revolver, -1)
	assert_eq(revolver.current_ammo, 6, "Loaded ammo should equal capacity 6.")
	assert_eq(revolver.reserve_ammo, 12, "Default reserve should be 2 clips (12).")

	# Clamped topup (e.g. impulse 101 or high grant) -> clamped at 5x capacity = 30
	cheats._topup_weapon_ammo(revolver, 9999)
	assert_eq(revolver.current_ammo, 6, "Loaded ammo should remain at capacity 6.")
	assert_eq(revolver.reserve_ammo, 30, "Reserve ammo should be clamped to 30 (6 * 5).")


## Tests that map command provides valid level autocomplete matches.
func test_map_command_autocomplete() -> void:
	print("TestInGameConsole: Running test_map_command_autocomplete().")
	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")

	var matches: Array[String] = reg.get_autocomplete_matches("map ")
	assert_true(matches.has("map testbed"), "Suggestions should include 'map testbed'.")
	assert_true(matches.has("map testbed2"), "Suggestions should include 'map testbed2'.")


## Tests that checkpoint command validates unset vs set checkpoint positions.
func test_checkpoint_command_unset_and_set() -> void:
	print("TestInGameConsole: Running test_checkpoint_command_unset_and_set().")
	var sys: ConsoleSystemCommands = _console.get("system_commands") as ConsoleSystemCommands
	assert_not_null(sys, "ConsoleSystemCommands module should exist.")

	SaveManager.last_checkpoint_pos = Vector3.ZERO
	sys._cmd_checkpoint(PackedStringArray())
	assert_eq(SaveManager.last_checkpoint_pos, Vector3.ZERO)

	var initial_pos: Vector3 = Vector3(12.0, 3.0, -8.0)
	SaveManager.last_checkpoint_pos = initial_pos
	sys._cmd_checkpoint(PackedStringArray())
	assert_eq(SaveManager.last_checkpoint_pos, initial_pos)
	SaveManager.last_checkpoint_pos = Vector3.ZERO


## Tests that save command dispatches save creation and load lists saves.
func test_save_and_load_commands() -> void:
	print("TestInGameConsole: Running test_save_and_load_commands().")
	var sys: ConsoleSystemCommands = _console.get("system_commands") as ConsoleSystemCommands
	assert_not_null(sys, "ConsoleSystemCommands module should exist.")

	# Save with custom name
	sys._cmd_save(PackedStringArray(["test_unit_save"]))

	# Load without args lists available saves without crashing
	sys._cmd_load(PackedStringArray())

	# Load with non-existent ID reports error cleanly without throwing
	sys._cmd_load(PackedStringArray(["non_existent_save_99999"]))


## Tests that diagnostics and metrics commands emit their respective signals.
func test_telemetry_commands_emit_signals() -> void:
	print("TestInGameConsole: Running test_telemetry_commands_emit_signals().")
	var settings: ConsoleSettingsCommands = (
		_console.get("settings_commands") as ConsoleSettingsCommands
	)
	assert_not_null(settings, "ConsoleSettingsCommands module should exist.")

	watch_signals(Events)
	settings._cmd_render_diagnostics(PackedStringArray())
	assert_signal_emitted(Events, "render_diagnostics_toggle_requested")

	settings._cmd_metrics(PackedStringArray())
	assert_signal_emitted(Events, "metrics_panel_toggle_requested")


## Tests that fps_limit updates Engine max_fps and persists to GlobalSettings.
func test_fps_limit_command() -> void:
	print("TestInGameConsole: Running test_fps_limit_command().")
	var settings: ConsoleSettingsCommands = (
		_console.get("settings_commands") as ConsoleSettingsCommands
	)
	assert_not_null(settings, "ConsoleSettingsCommands module should exist.")

	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")
	var matches: Array[String] = reg.get_autocomplete_matches("fps_limit ")
	assert_true(matches.has("fps_limit 60"), "Suggestions should contain 'fps_limit 60'.")
	assert_true(matches.has("fps_limit 0"), "Suggestions should contain 'fps_limit 0'.")

	settings._cmd_fps_limit(PackedStringArray(["120"]))
	assert_eq(Engine.max_fps, 120, "Engine max_fps should equal 120.")
	assert_eq(
		GlobalSettings.get_setting_int("Settings", "fps_limit", 60),
		120,
		"GlobalSettings fps_limit should be updated to 120."
	)

	# Restore 60 fps limit
	settings._cmd_fps_limit(PackedStringArray(["60"]))


## Tests that stat_perf executes and writes metrics snapshot cleanly.
func test_stat_perf_command() -> void:
	print("TestInGameConsole: Running test_stat_perf_command().")
	var settings: ConsoleSettingsCommands = (
		_console.get("settings_commands") as ConsoleSettingsCommands
	)
	assert_not_null(settings, "ConsoleSettingsCommands module should exist.")

	settings._cmd_stat_perf(PackedStringArray())
	pass_test("stat_perf executed without throwing.")


## Tests that infinite_swim command updates GlobalSettings and emits signal.
func test_infinite_swim_command() -> void:
	print("TestInGameConsole: Running test_infinite_swim_command().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	watch_signals(Events)
	cheats._cmd_infinite_swim(PackedStringArray(["on"]))
	assert_signal_emitted(Events, "infinite_swim_toggled")
	assert_true(
		GlobalSettings.get_setting_bool("Accessibility", "infinite_swim", false),
		"Infinite swim should be true in GlobalSettings."
	)

	cheats._cmd_infinite_swim(PackedStringArray(["off"]))
	assert_false(
		GlobalSettings.get_setting_bool("Accessibility", "infinite_swim", false),
		"Infinite swim should be false in GlobalSettings."
	)


## Tests that noclip_speed validates input and emits noclip_speed_changed.
func test_noclip_speed_command() -> void:
	print("TestInGameConsole: Running test_noclip_speed_command().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")
	var matches: Array[String] = reg.get_autocomplete_matches("noclip_speed ")
	assert_true(matches.has("noclip_speed 8.0"), "Suggestions should contain 'noclip_speed 8.0'.")

	watch_signals(Events)
	cheats._cmd_noclip_speed(PackedStringArray(["16.0"]))
	assert_signal_emitted(Events, "noclip_speed_changed")


## Tests that giveall unlocks all keycards in KeycardSystem.
func test_giveall_keycard_grants() -> void:
	print("TestInGameConsole: Running test_giveall_keycard_grants().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	cheats._cmd_giveall(PackedStringArray())
	assert_true(KeycardSystem.has_card(&"G"), "KeycardSystem should contain 'G'.")
	assert_true(KeycardSystem.has_card(&"L"), "KeycardSystem should contain 'L'.")
	assert_true(KeycardSystem.has_card(&"R"), "KeycardSystem should contain 'R'.")
	assert_true(
		KeycardSystem.has_card(&"SecurityAlpha"), "KeycardSystem should have SecurityAlpha."
	)
	assert_true(KeycardSystem.has_card(&"AdminCard"), "KeycardSystem should have AdminCard.")

	# Cleanup
	KeycardSystem.consume_card(&"G")
	KeycardSystem.consume_card(&"L")
	KeycardSystem.consume_card(&"R")
	KeycardSystem.consume_card(&"SecurityAlpha")
	KeycardSystem.consume_card(&"AdminCard")


## Tests that volume command queries and updates audio bus volume.
func test_volume_command() -> void:
	print("TestInGameConsole: Running test_volume_command().")
	var settings: ConsoleSettingsCommands = (
		_console.get("settings_commands") as ConsoleSettingsCommands
	)
	assert_not_null(settings, "ConsoleSettingsCommands module should exist.")

	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")
	var matches: Array[String] = reg.get_autocomplete_matches("volume ")
	assert_true(matches.has("volume master"), "Suggestions should contain 'volume master'.")
	assert_true(matches.has("volume sfx"), "Suggestions should contain 'volume sfx'.")

	# Query without args
	settings._cmd_volume(PackedStringArray())

	# Set SFX volume
	settings._cmd_volume(PackedStringArray(["sfx", "75"]))
	assert_eq(
		GlobalSettings.get_setting("Audio", "SFX", 0.0),
		75.0,
		"GlobalSettings Audio SFX volume should be 75.0."
	)


## Tests that fullscreen command toggles display mode and updates settings.
func test_fullscreen_command() -> void:
	print("TestInGameConsole: Running test_fullscreen_command().")
	var settings: ConsoleSettingsCommands = (
		_console.get("settings_commands") as ConsoleSettingsCommands
	)
	assert_not_null(settings, "ConsoleSettingsCommands module should exist.")

	settings._cmd_fullscreen(PackedStringArray(["on"]))
	assert_eq(
		GlobalSettings.get_setting_int("Settings", "display_mode", 0),
		int(Window.MODE_EXCLUSIVE_FULLSCREEN),
		"Fullscreen should persist MODE_EXCLUSIVE_FULLSCREEN."
	)

	settings._cmd_fullscreen(PackedStringArray(["off"]))
	assert_eq(
		GlobalSettings.get_setting_int("Settings", "display_mode", 0),
		int(Window.MODE_WINDOWED),
		"Fullscreen off should persist MODE_WINDOWED."
	)


## Tests that resolution command validates bounds and persists values.
func test_resolution_command() -> void:
	print("TestInGameConsole: Running test_resolution_command().")
	var settings: ConsoleSettingsCommands = (
		_console.get("settings_commands") as ConsoleSettingsCommands
	)
	assert_not_null(settings, "ConsoleSettingsCommands module should exist.")

	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")
	var matches: Array[String] = reg.get_autocomplete_matches("resolution ")
	assert_true(
		matches.has("resolution 1920 1080"), "Suggestions should contain 'resolution 1920 1080'."
	)

	# Query without args
	settings._cmd_resolution(PackedStringArray())

	# Apply resolution
	settings._cmd_resolution(PackedStringArray(["1280", "720"]))
	assert_eq(
		GlobalSettings.get_setting_int("Settings", "resolution_x", 0),
		1280,
		"Resolution X should be persisted to 1280."
	)
	assert_eq(
		GlobalSettings.get_setting_int("Settings", "resolution_y", 0),
		720,
		"Resolution Y should be persisted to 720."
	)


## Tests that tts command toggles narration setting and emits signal.
func test_tts_command() -> void:
	print("TestInGameConsole: Running test_tts_command().")
	var settings: ConsoleSettingsCommands = (
		_console.get("settings_commands") as ConsoleSettingsCommands
	)
	assert_not_null(settings, "ConsoleSettingsCommands module should exist.")

	watch_signals(Events)
	settings._cmd_tts(PackedStringArray(["on"]))
	assert_signal_emitted(Events, "tts_state_changed")
	assert_true(
		GlobalSettings.get_setting_bool("Accessibility", "tts_enabled", false),
		"TTS should be enabled in GlobalSettings."
	)

	settings._cmd_tts(PackedStringArray(["off"]))
	assert_false(
		GlobalSettings.get_setting_bool("Accessibility", "tts_enabled", false),
		"TTS should be disabled in GlobalSettings."
	)


## Tests that freecam activates and deactivates cleanly without crashes.
func test_freecam_command_toggle() -> void:
	print("TestInGameConsole: Running test_freecam_command_toggle().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	cheats._cmd_freecam(PackedStringArray(["on"]))
	cheats._cmd_freecam(PackedStringArray(["off"]))
	assert_false(
		cheats.context.get_toggle_state("freecam", false),
		"Freecam should be false after turning off."
	)


## Tests that FreecamController initializes transform, responds to mouse look, and cleans up.
func test_freecam_controller_lifecycle_and_input() -> void:
	print("TestInGameConsole: Running test_freecam_controller_lifecycle_and_input().")
	var dummy_cam: Camera3D = Camera3D.new()
	var dummy_player: Node3D = Node3D.new()
	dummy_cam.fov = 85.0
	dummy_cam.rotation = Vector3(0.1, 0.2, 0.0)
	add_child_autofree(dummy_cam)
	add_child_autofree(dummy_player)

	var freecam_obj: Object = FREECAM_SCRIPT.new()
	var freecam: Camera3D = freecam_obj as Camera3D
	assert_not_null(freecam, "Freecam instance should instantiate properly.")
	add_child_autofree(freecam)

	freecam.call(&"setup", dummy_cam, dummy_player)
	assert_eq(freecam.fov, 85.0, "Freecam should copy original camera FOV.")
	assert_true(freecam.current, "Freecam should be active camera.")

	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 50.0)
	freecam._input(motion)
	freecam._process(0.016)

	freecam.call(&"restore_and_exit")
	assert_true(freecam.is_queued_for_deletion(), "Freecam should queue free on exit.")


## Tests that damage and heal commands broadcast event signals.
func test_damage_and_heal_commands() -> void:
	print("TestInGameConsole: Running test_damage_and_heal_commands().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	watch_signals(Events)
	cheats._cmd_damage(PackedStringArray(["25"]))
	assert_signal_emitted(Events, "player_damaged")

	cheats._cmd_heal(PackedStringArray(["30"]))
	assert_signal_emitted(Events, "player_healed")


## Tests that water_wipe and shockwave commands broadcast their signals.
func test_water_wipe_and_shockwave_commands() -> void:
	print("TestInGameConsole: Running test_water_wipe_and_shockwave_commands().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	watch_signals(Events)
	cheats._cmd_water_wipe(PackedStringArray(["1.5"]))
	assert_signal_emitted(Events, "water_sheet_wipe_requested")

	cheats._cmd_shockwave(PackedStringArray(["20.0", "30.0"]))
	assert_signal_emitted(Events, "shockwave_requested")


## Tests that outline command validates modes and emits outline_mode_changed.
func test_outline_command() -> void:
	print("TestInGameConsole: Running test_outline_command().")
	var settings: ConsoleSettingsCommands = (
		_console.get("settings_commands") as ConsoleSettingsCommands
	)
	assert_not_null(settings, "ConsoleSettingsCommands module should exist.")

	watch_signals(Events)
	settings._cmd_outline(PackedStringArray(["pulse"]))
	assert_signal_emitted(Events, "outline_mode_changed")
	assert_eq(
		GlobalSettings.get_setting_int("Accessibility", "outline_mode", 0),
		2,
		"Outline mode should be 2 for pulse."
	)

	settings._cmd_outline(PackedStringArray(["off"]))
	assert_eq(
		GlobalSettings.get_setting_int("Accessibility", "outline_mode", 2),
		0,
		"Outline mode should be 0 for off."
	)


## Tests that chapter command broadcasts chapter_triggered signal.
func test_chapter_command() -> void:
	print("TestInGameConsole: Running test_chapter_command().")
	var sys: ConsoleSystemCommands = _console.get("system_commands") as ConsoleSystemCommands
	assert_not_null(sys, "ConsoleSystemCommands module should exist.")

	watch_signals(Events)
	sys._cmd_chapter(PackedStringArray(["3"]))
	assert_signal_emitted(Events, "chapter_triggered")


## Tests that FreecamController supports mouse-wheel speed scaling and teleportation.
func test_freecam_wheel_scaling_and_teleport() -> void:
	print("TestInGameConsole: Running test_freecam_wheel_scaling_and_teleport().")
	var dummy_cam: Camera3D = Camera3D.new()
	var dummy_player: Node3D = Node3D.new()
	add_child_autofree(dummy_cam)
	add_child_autofree(dummy_player)
	dummy_player.position = Vector3(0.0, 0.0, 0.0)

	var freecam_obj: Object = FREECAM_SCRIPT.new()
	var freecam: Camera3D = freecam_obj as Camera3D
	add_child_autofree(freecam)
	freecam.call(&"setup", dummy_cam, dummy_player)
	freecam.position = Vector3(10.0, 20.0, 30.0)

	var wheel_up: InputEventMouseButton = InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	freecam._input(wheel_up)
	var speed_mult: float = freecam.get("speed_multiplier") as float
	assert_gt(speed_mult, 1.0, "Wheel up should increase speed multiplier.")

	var wheel_down: InputEventMouseButton = InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	freecam._input(wheel_down)
	freecam._input(wheel_down)
	speed_mult = freecam.get("speed_multiplier") as float
	assert_lt(speed_mult, 1.1, "Wheel down should decrease speed multiplier.")

	freecam.call(&"teleport_player_and_exit")
	assert_eq(
		dummy_player.position,
		Vector3(10.0, 20.0, 30.0),
		"Player should teleport to freecam location."
	)


## Tests that notarget and ai_disable cheats toggle state and emit expected signals.
func test_notarget_and_ai_disable_commands() -> void:
	print("TestInGameConsole: Running test_notarget_and_ai_disable_commands().")
	var cheats: ConsoleCheatCommands = _console.get("cheat_commands") as ConsoleCheatCommands
	assert_not_null(cheats, "ConsoleCheatCommands module should exist.")

	watch_signals(Events)
	cheats._cmd_notarget(PackedStringArray(["on"]))
	assert_signal_emitted(Events, "player_notarget_toggled")
	assert_true(
		cheats.context.get_toggle_state("notarget", false), "notarget state should be true."
	)

	cheats._cmd_notarget(PackedStringArray(["off"]))
	assert_false(
		cheats.context.get_toggle_state("notarget", true), "notarget state should be false."
	)

	cheats._cmd_ai_disable(PackedStringArray(["on"]))
	assert_true(
		cheats.context.get_toggle_state("ai_disable", false), "ai_disable state should be true."
	)

	cheats._cmd_ai_disable(PackedStringArray(["off"]))
	assert_false(
		cheats.context.get_toggle_state("ai_disable", true), "ai_disable state should be false."
	)


## Tests keybinding engine and shortcut commands.
func test_shortcuts_and_keybinds() -> void:
	print("TestInGameConsole: Running test_shortcuts_and_keybinds().")
	var sys: ConsoleSystemCommands = _console.get("system_commands") as ConsoleSystemCommands
	assert_not_null(sys, "ConsoleSystemCommands module should exist.")

	sys._cmd_pause(PackedStringArray())
	assert_true(get_tree().paused, "pause command should toggle paused tree state.")
	sys._cmd_pause(PackedStringArray())
	assert_false(get_tree().paused, "pause command should unpause tree state.")

	sys._cmd_bind(PackedStringArray(["v", "noclip"]))
	var keybinds: Dictionary[String, String] = _get_console_keybinds()
	assert_true(keybinds.has("v"), "Custom keybind 'v' should exist.")
	assert_eq(keybinds.get("v", ""), "noclip", "Key 'v' should map to 'noclip'.")

	sys._cmd_bindlist(PackedStringArray())

	sys._cmd_unbind(PackedStringArray(["v"]))
	keybinds = _get_console_keybinds()
	assert_false(keybinds.has("v"), "Key 'v' should be unbound.")

	sys._cmd_bind(PackedStringArray(["k", "killall"]))
	sys._cmd_unbindall(PackedStringArray())
	keybinds = _get_console_keybinds()
	assert_true(keybinds.is_empty(), "All custom keybinds should be cleared.")


## Tests showtrigger, showtriggers, hidetrigger, and hidetriggers console commands.
func test_showtriggers_and_hidetriggers_commands() -> void:
	print("TestInGameConsole: Running test_showtriggers_and_hidetriggers_commands().")
	var trigger: BaseTriggerArea3D = BaseTriggerArea3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	trigger.add_child(col)
	add_child_autoqfree(trigger)

	var visual: EditorTriggerVisualizer = trigger._get_visualizer()
	assert_not_null(visual, "BaseTriggerArea3D must retain an EditorTriggerVisualizer child.")

	_console.call("execute_command_string", "showtriggers on")
	assert_true(EditorTriggerVisualizer.debug_force_visible, "debug_force_visible should be true.")
	assert_true(visual.visible, "Visualizer should become visible when showtriggers is enabled.")

	_console.call("execute_command_string", "hidetriggers")
	assert_false(EditorTriggerVisualizer.debug_force_visible, "debug_force_visible must be false.")
	assert_false(visual.visible, "Visualizer should be hidden when hidetriggers is called.")

	_console.call("execute_command_string", "showtrigger on")
	assert_true(EditorTriggerVisualizer.debug_force_visible, "debug_force_visible should be true.")
	assert_true(visual.visible, "Visualizer should become visible via singular showtrigger.")

	_console.call("execute_command_string", "hidetrigger")
	assert_false(EditorTriggerVisualizer.debug_force_visible, "debug_force_visible must be false.")
	assert_false(visual.visible, "Visualizer should be hidden via singular hidetrigger.")


## Helper retrieving custom keybinds dictionary from console under test.
func _get_console_keybinds() -> Dictionary[String, String]:
	var keybinds: Dictionary[String, String] = {}
	if is_instance_valid(_console) and _console.has_method(&"get_keybinds"):
		var raw: Variant = _console.call(&"get_keybinds")
		if raw is Dictionary:
			var dict_val: Dictionary = raw as Dictionary
			for k: Variant in dict_val.keys():
				keybinds[str(k)] = str(dict_val[k])
	return keybinds
