## Central user interface manager coordinating navigation, game context,
## audio themes, and unified setting search routing.
class_name MainMenu
extends CanvasLayer

## The base sensitivity multiplier used when no player preference is found.
const DEFAULT_SENSITIVITY: float = 0.5

## Preloaded scene for the chapter selection screen to ensure instantaneous loading.
const CHAPTER_SCREEN: PackedScene = preload("res://ui/menu_chapter_screen.tscn")

## Custom minimum width applied to the search results popup container.
const SEARCH_PANEL_MIN_WIDTH: float = 620.0

@export_group("Options Tabs & Navigation")

## Array of buttons used to navigate back to the main menu screen.
@export var back_buttons: Array[Button]

## Array of buttons that toggle between different option categories (Audio, Video, etc.).
@export var tab_buttons: Array[Button]

## Array of control panels corresponding to the tab_buttons.
@export var option_panels: Array[Control]

## The audio player responsible for playing the main theme music on the title screen.
@export var main_theme_player: AudioStreamPlayer

## The title or game name label displayed in the primary menu view.
@onready var game_name_label: Label = %GameNameLabel

## The main vertical container holding the primary menu navigation buttons.
@onready var main_buttons: VBoxContainer = $MarginContainer/MainButtons

## The centralized container that holds the overarching options menu UI.
@onready var options_menu: Control = %CenterContainer

## Container holding all tab buttons.
@onready var tab_buttons_container: HBoxContainer = %TabButtons

## Container holding all individual settings panels.
@onready var settings_area: Control = %SettingsArea

## The panel dedicated specifically to managing saved games and loading states.
@onready var save_load_panel: Panel = $SaveLoadPanel

# Main Menu Buttons

## Button to unpause and return to the active gameplay session.
@onready var continue_button: Button = %Continue

## Button to initiate a fresh playthrough or end the current run.
@onready var new_game_button: Button = %NewGame

## Button to completely restart the active gameplay session.
@onready var restart_button: Button = %RestartGame

## Button to write the current game state to disk.
@onready var save_button: Button = %SaveGame

## Button to read a previously saved game state from disk.
@onready var load_button: Button = %LoadGame

## Button to open the settings and options overlay.
@onready var options_button: Button = %Options

## Button to completely terminate the game application.
@onready var exit_button: Button = %Exit

## Button to reset active panel settings back to default.
@onready var reset_defaults_button: Button = %ResetDefaultsButton

# Search Nodes

## Input field for typing setting search terms across all option panels.
@onready var search_bar: LineEdit = %SettingsSearchEdit

## Overlay container displaying matching search results.
@onready var search_results_panel: Control = %SearchResultsPanel

## Scrollable wrapper for the search result entries.
@onready var search_scroll_container: ScrollContainer = %SearchResultsPanel/ScrollContainer

## Vertical box hosting dynamically generated search result buttons.
@onready var search_results_list: VBoxContainer = %SearchResultsList

## Tracks whether the player's mouse sensitivity has been analyzed and set.
var has_calibrated: bool = false

## Records the highest velocity of the mouse to automatically determine comfortable sensitivity.
var max_mouse_speed: float = 0.0

## Cached index of setting metadata for instantaneous search queries.
var _search_index: Array[Dictionary] = []


## Lifecycle method initializing menu state, signals, and search index caching.
func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("UI: MainMenu initialized.")

	_disable_active_grading_volumes()
	_auto_discover_panels_and_tabs()

	if continue_button:
		continue_button.pressed.connect(_on_resume_pressed)
	if new_game_button:
		new_game_button.pressed.connect(_on_new_game_pressed)
	if restart_button:
		restart_button.pressed.connect(_on_start_game_pressed)
	if options_button:
		options_button.pressed.connect(_on_options_pressed)
	if load_button:
		load_button.pressed.connect(_on_load_pressed)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)
	if reset_defaults_button:
		reset_defaults_button.visible = false
		reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)

	for btn: Button in back_buttons:
		if btn:
			btn.pressed.connect(_return_to_main_buttons)

	for i: int in range(tab_buttons.size()):
		var btn: Button = tab_buttons[i]
		if btn:
			btn.pressed.connect(_on_tab_pressed.bind(i))

	_setup_search_bar()
	_check_game_context()
	_return_to_main_buttons()


## Searches the active scene tree and resets all ColorGradingVolume3D nodes.
func _disable_active_grading_volumes() -> void:
	print("UI: Finding and disabling active ColorGradingVolume3D nodes.")
	get_tree().call_group_flags(
		SceneTree.GROUP_CALL_DEFERRED, "color_grading_volumes", "reset_to_default"
	)


## Automatically resolves tab buttons, panel references, and back buttons if unassigned.
func _auto_discover_panels_and_tabs() -> void:
	if tab_buttons.size() != 5 and tab_buttons_container:
		tab_buttons.clear()
		for child: Node in tab_buttons_container.get_children():
			if child is Button:
				tab_buttons.append(child as Button)

	if option_panels.size() != tab_buttons.size() and settings_area:
		option_panels.clear()
		for child: Node in settings_area.get_children():
			var is_valid_panel: bool = (
				child is Control
				and child != search_results_panel
				and child.name != "MasterBackButton"
			)
			if is_valid_panel:
				option_panels.append(child as Control)

	# Locate and connect MasterBackButton automatically if not wired in back_buttons
	if options_menu:
		var master_back: Button = options_menu.find_child("MasterBackButton", true, false) as Button
		if master_back and not master_back.pressed.is_connected(_return_to_main_buttons):
			master_back.pressed.connect(_return_to_main_buttons)
			print("UI: Connected MasterBackButton to main menu router.")

	print("UI: Resolved ", tab_buttons.size(), " tabs and ", option_panels.size(), " panels.")


## Configures listeners, position anchors, and styling for settings search functionality.
func _setup_search_bar() -> void:
	if not search_bar:
		return
	print("UI: Configuring Settings Search Bar.")
	search_bar.placeholder_text = "Search settings..."
	search_bar.text_changed.connect(_on_search_text_changed)
	search_bar.focus_entered.connect(_on_search_bar_focused)

	if search_results_panel:
		search_results_panel.top_level = true
		search_results_panel.visible = false
		search_results_panel.z_index = 100
		search_results_panel.custom_minimum_size.x = SEARCH_PANEL_MIN_WIDTH

	if search_scroll_container:
		search_scroll_container.size_flags_horizontal = (Control.SIZE_EXPAND_FILL)
		search_scroll_container.horizontal_scroll_mode = (ScrollContainer.SCROLL_MODE_DISABLED)


## Callback triggered when the search bar gains input focus.
func _on_search_bar_focused() -> void:
	print("UI: Search bar gained focus.")
	if search_bar and not search_bar.text.strip_edges().is_empty():
		_on_search_text_changed(search_bar.text)


## Positions the floating search panel directly
## beneath the search bar and enforces minimum dimensions.
func _update_search_panel_position() -> void:
	if not search_bar or not search_results_panel:
		return
	print("UI: Repositioning search results dropdown under search bar.")
	var bar_pos: Vector2 = search_bar.global_position
	var bar_size: Vector2 = search_bar.size
	var final_width: float = maxf(bar_size.x, SEARCH_PANEL_MIN_WIDTH)

	search_results_panel.custom_minimum_size.x = final_width
	search_results_panel.size.x = final_width

	if search_scroll_container:
		search_scroll_container.custom_minimum_size.x = final_width
		search_scroll_container.size.x = final_width

	var target_x: float = bar_pos.x
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	if target_x + final_width > viewport_width:
		target_x = maxf(0.0, viewport_width - final_width - 16.0)

	search_results_panel.global_position = Vector2(target_x, bar_pos.y + bar_size.y + 6.0)


## Builds an indexed registry of all searchable controls across every options panel.
func _build_search_index() -> void:
	_auto_discover_panels_and_tabs()
	print("UI: Indexing all settings across options panels.")
	_search_index.clear()

	for tab_idx: int in range(option_panels.size()):
		var panel: Control = option_panels[tab_idx]
		if not is_instance_valid(panel):
			continue

		var tab_name: String = ""
		if tab_idx < tab_buttons.size() and is_instance_valid(tab_buttons[tab_idx]):
			tab_name = tab_buttons[tab_idx].text.strip_edges()
		if tab_name.is_empty():
			tab_name = panel.name.replace("Panel", "").replace("Options", "")

		_scan_node_for_search(panel, tab_idx, tab_name)

	print("UI: Search index populated with ", _search_index.size(), " entries.")


## Recursively scans container structures to extract visible labels and their interactive controls.
## [param root_node] Starting container [Node].
## [param tab_idx] Index of the parent tab.
## [param tab_name] Display name of the parent tab category.
func _scan_node_for_search(root_node: Node, tab_idx: int, tab_name: String) -> void:
	if not is_instance_valid(root_node):
		return

	if root_node is Label:
		var label: Label = root_node as Label
		var label_text: String = label.text.strip_edges()
		if not label_text.is_empty() and label.name != "HeaderLabel":
			var parent: Node = label.get_parent()
			if parent:
				var interactive: Control = _find_interactive_sibling(parent, label)
				if interactive:
					_register_search_item(label.text, tab_idx, tab_name, interactive)

	elif _is_interactive_control(root_node) and root_node is Button:
		var btn: Button = root_node as Button
		var is_searchable_btn: bool = (
			not btn.text.strip_edges().is_empty()
			and not btn.has_meta("slot")
			and btn.name != "MasterBackButton"
		)
		if is_searchable_btn:
			_register_search_item(btn.text, tab_idx, tab_name, btn)

	for child: Node in root_node.get_children():
		var should_skip: bool = (
			child.name == "HeaderLabel"
			or child.name.begins_with("SectionHeader")
			or child.name.begins_with("Spacer")
		)
		if not should_skip:
			_scan_node_for_search(child, tab_idx, tab_name)


## Locates the exact interactive sibling [Control] mapped to a specific [Label].
## [param parent] The parent container [Node] holding elements.
## [param label_node] The [Label] being paired.
## [return] The matched interactive [Control], or null if none found.
func _find_interactive_sibling(parent: Node, label_node: Label) -> Control:
	var label_idx: int = label_node.get_index()
	var child_count: int = parent.get_child_count()
	var max_step: int = 4

	if parent is GridContainer:
		var grid: GridContainer = parent as GridContainer
		max_step = max(grid.columns, 2)

	for step_offset: int in range(1, max_step + 1):
		var target_idx: int = label_idx + step_offset
		if target_idx >= child_count:
			break
		var sibling: Node = parent.get_child(target_idx)
		if sibling is Label:
			break
		if _is_interactive_control(sibling):
			return sibling as Control
		for sub: Node in sibling.get_children():
			if _is_interactive_control(sub):
				return sub as Control

	return null


## Evaluates whether a node represents a focusable/interactive settings widget.
## [param node] The [Node] to evaluate.
## [return] True if the control accepts player interaction.
func _is_interactive_control(node: Node) -> bool:
	return (
		node is OptionButton
		or node is CheckButton
		or node is CheckBox
		or node is HSlider
		or node is LineEdit
		or (
			node is Button and not (node is CheckButton or node is CheckBox or node is OptionButton)
		)
	)


## Appends a formatted setting record to the global search registry.
## [param title] Setting title or label text.
## [param tab_idx] Parent tab index.
## [param tab_name] Display name of category tab.
## [param target_node] Target [Control] to focus upon selection.
func _register_search_item(
	title: String, tab_idx: int, tab_name: String, target_node: Control
) -> void:
	var clean_title: String = title.strip_edges().replace(":", "")
	if clean_title.is_empty():
		return

	for item: Dictionary in _search_index:
		if item["title"] == clean_title and item["tab_index"] == tab_idx:
			return

	_search_index.append(
		{"title": clean_title, "tab_index": tab_idx, "tab_name": tab_name, "target": target_node}
	)


## Handles real-time search input filtering and popup population with live controls.
## [param query] Search string input by the player.
func _on_search_text_changed(query: String) -> void:
	var clean_query: String = query.strip_edges().to_lower()
	print("UI: User filtering settings query -> '", clean_query, "'")

	if clean_query.is_empty():
		if search_results_panel:
			search_results_panel.visible = false
		return

	if _search_index.is_empty():
		_build_search_index()

	if not search_results_list or not search_results_panel:
		return

	for child: Node in search_results_list.get_children():
		child.queue_free()

	var matches: int = 0
	for item: Dictionary in _search_index:
		var item_title: String = item["title"] as String
		var category: String = item["tab_name"] as String
		var tab_idx: int = item["tab_index"] as int
		var target: Control = item["target"] as Control

		if clean_query in item_title.to_lower() or clean_query in category.to_lower():
			matches += 1
			var row: HBoxContainer = _create_search_result_row(
				item_title, category, tab_idx, target
			)
			search_results_list.add_child(row)

	_update_search_panel_position()
	search_results_panel.visible = matches > 0


## Navigates to a specific settings tab and focuses the selected target control.
## [param tab_idx] Index of tab to switch to.
## [param target] Target [Control] to focus.
func _navigate_to_setting(tab_idx: int, target: Control) -> void:
	print("UI: Navigating to tab index ", tab_idx, " from search selection.")
	if options_menu and not options_menu.visible:
		_on_options_pressed()

	_on_tab_pressed(tab_idx)

	if search_results_panel:
		search_results_panel.visible = false
	if search_bar:
		search_bar.text = ""

	if is_instance_valid(target):
		target.grab_focus()


## Creates an interactive horizontal row for the
## search results dropdown containing an embedded control.
## [param title] Setting label name.
## [param category] Settings category tab name.
## [param tab_idx] Tab index owning the setting.
## [param original] The original [Control] instance to clone and sync.
## [return] The constructed [HBoxContainer] row.
func _create_search_result_row(
	title: String, category: String, tab_idx: int, original: Control
) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 32.0

	var label_button: Button = Button.new()
	label_button.text = "%s  [%s]" % [title, category]
	label_button.flat = true
	label_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	label_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_button.pressed.connect(func() -> void: _navigate_to_setting(tab_idx, original))
	row.add_child(label_button)

	if not is_instance_valid(original):
		return row

	if original is OptionButton:
		var orig_ob: OptionButton = original as OptionButton
		var cloned_ob: OptionButton = OptionButton.new()
		for i: int in range(orig_ob.item_count):
			cloned_ob.add_item(orig_ob.get_item_text(i), orig_ob.get_item_id(i))
		cloned_ob.selected = orig_ob.selected
		cloned_ob.custom_minimum_size.x = 200.0

		var sync_orig: Callable = func(idx: int) -> void:
			if is_instance_valid(cloned_ob):
				cloned_ob.selected = idx

		cloned_ob.item_selected.connect(
			func(idx: int) -> void:
				print("UI: Search Quick-Change OptionButton -> ", idx)
				if orig_ob.selected != idx:
					orig_ob.selected = idx
					orig_ob.item_selected.emit(idx)
		)
		orig_ob.item_selected.connect(sync_orig)
		cloned_ob.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_ob) and orig_ob.item_selected.is_connected(sync_orig):
					orig_ob.item_selected.disconnect(sync_orig)
		)
		row.add_child(cloned_ob)

	elif original is CheckButton:
		var orig_cb: CheckButton = original as CheckButton
		var cloned_cb: CheckButton = CheckButton.new()
		cloned_cb.button_pressed = orig_cb.button_pressed

		var sync_orig: Callable = func(pressed: bool) -> void:
			if is_instance_valid(cloned_cb):
				cloned_cb.button_pressed = pressed

		cloned_cb.toggled.connect(
			func(pressed: bool) -> void:
				print("UI: Search Quick-Change CheckButton -> ", pressed)
				if orig_cb.button_pressed != pressed:
					orig_cb.button_pressed = pressed
					orig_cb.toggled.emit(pressed)
		)
		orig_cb.toggled.connect(sync_orig)
		cloned_cb.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_cb) and orig_cb.toggled.is_connected(sync_orig):
					orig_cb.toggled.disconnect(sync_orig)
		)
		row.add_child(cloned_cb)

	elif original is CheckBox:
		var orig_chk: CheckBox = original as CheckBox
		var cloned_chk: CheckBox = CheckBox.new()
		cloned_chk.button_pressed = orig_chk.button_pressed

		var sync_orig: Callable = func(pressed: bool) -> void:
			if is_instance_valid(cloned_chk):
				cloned_chk.button_pressed = pressed

		cloned_chk.toggled.connect(
			func(pressed: bool) -> void:
				print("UI: Search Quick-Change CheckBox -> ", pressed)
				if orig_chk.button_pressed != pressed:
					orig_chk.button_pressed = pressed
					orig_chk.toggled.emit(pressed)
		)
		orig_chk.toggled.connect(sync_orig)
		cloned_chk.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_chk) and orig_chk.toggled.is_connected(sync_orig):
					orig_chk.toggled.disconnect(sync_orig)
		)
		row.add_child(cloned_chk)

	elif original is HSlider:
		var orig_sl: HSlider = original as HSlider
		var cloned_sl: HSlider = HSlider.new()
		cloned_sl.min_value = orig_sl.min_value
		cloned_sl.max_value = orig_sl.max_value
		cloned_sl.step = orig_sl.step
		cloned_sl.value = orig_sl.value
		cloned_sl.custom_minimum_size.x = 180.0
		cloned_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var sync_orig: Callable = func(val: float) -> void:
			if is_instance_valid(cloned_sl):
				cloned_sl.value = val

		cloned_sl.value_changed.connect(
			func(val: float) -> void:
				print("UI: Search Quick-Change HSlider -> ", val)
				if not is_equal_approx(orig_sl.value, val):
					orig_sl.value = val
					orig_sl.value_changed.emit(val)
		)
		orig_sl.value_changed.connect(sync_orig)
		cloned_sl.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_sl) and orig_sl.value_changed.is_connected(sync_orig):
					orig_sl.value_changed.disconnect(sync_orig)
		)
		row.add_child(cloned_sl)

	elif original is Button:
		var orig_b: Button = original as Button
		var cloned_b: Button = Button.new()
		cloned_b.text = orig_b.text
		cloned_b.pressed.connect(
			func() -> void:
				print("UI: Search Quick-Click Button -> ", orig_b.text)
				orig_b.pressed.emit()
		)
		row.add_child(cloned_b)

	return row


## Evaluates game pause/save availability states.
func _check_game_context() -> void:
	print("UI: Checking game context for SaveManager and Pause state.")
	if SaveManager.has_method("has_saves"):
		var saves_exist: bool = SaveManager.has_saves() as bool
		if load_button:
			load_button.visible = saves_exist

	if get_parent().has_method("toggle_pause"):
		if continue_button:
			continue_button.show()
		if restart_button:
			restart_button.show()
		if save_button:
			save_button.show()
		if new_game_button:
			new_game_button.text = "End Run"
	else:
		if continue_button:
			continue_button.hide()
		if restart_button:
			restart_button.hide()
		if save_button:
			save_button.hide()
		_play_main_theme()


## Initiates title screen theme playback.
func _play_main_theme() -> void:
	if main_theme_player and not main_theme_player.playing:
		print("Audio: Playing main theme music.")
		main_theme_player.play()


## Stops title screen theme playback.
func _stop_main_theme() -> void:
	if main_theme_player and main_theme_player.playing:
		print("Audio: Stopping main theme music.")
		main_theme_player.stop()


## Restores the primary menu navigation screen.
func _return_to_main_buttons() -> void:
	print("UI: Player routed to Main Buttons.")
	if game_name_label:
		game_name_label.visible = true
	if main_buttons:
		main_buttons.visible = true
	if options_menu:
		options_menu.visible = false
	if save_load_panel:
		save_load_panel.visible = false
	if search_results_panel:
		search_results_panel.visible = false


## Callback triggered when the player resumes gameplay.
func _on_resume_pressed() -> void:
	print("UI: Player clicked Resume.")
	_stop_main_theme()
	var parent: Node = get_parent()
	if parent and parent.has_method("toggle_pause"):
		parent.call("toggle_pause")


## Callback triggered when the player initiates a new game.
func _on_new_game_pressed() -> void:
	print("UI: Player clicked New Game.")
	_stop_main_theme()
	if not has_calibrated:
		_apply_bucket_calibration()

	if game_name_label:
		game_name_label.hide()
	if main_buttons:
		main_buttons.hide()
	var chapter_window: Node = CHAPTER_SCREEN.instantiate()
	add_child(chapter_window)


## Callback triggered when the player initiates a game restart.
func _on_start_game_pressed() -> void:
	print("UI: Player clicked Restart Game.")
	_stop_main_theme()
	if not has_calibrated:
		_apply_bucket_calibration()

	get_tree().paused = false
	if get_parent().has_method("toggle_pause"):
		get_tree().reload_current_scene()


## Callback triggered when the player navigates to options.
func _on_options_pressed() -> void:
	print("UI: Player clicked Options.")
	if game_name_label:
		game_name_label.visible = false
	if main_buttons:
		main_buttons.visible = false
	if save_load_panel:
		save_load_panel.visible = false
	if options_menu:
		options_menu.visible = true

	if tab_buttons.size() > 0 and option_panels.size() > 0:
		_on_tab_pressed(0)

	_build_search_index()


## Callback triggered when the player opens the load menu.
func _on_load_pressed() -> void:
	print("UI: Player clicked Load Game.")
	if game_name_label:
		game_name_label.visible = false
	if main_buttons:
		main_buttons.visible = false
	if options_menu:
		options_menu.visible = false
	if save_load_panel:
		save_load_panel.visible = true


## Callback triggered when the player quits the game.
func _on_exit_pressed() -> void:
	print("UI: Player clicked Exit.")
	get_tree().quit()


## Switches active visibility across options sub-panels.
## [param tab_index] Index of panel to display.
func _on_tab_pressed(tab_index: int) -> void:
	print("UI: Switched to options tab index: ", tab_index)
	for i: int in range(option_panels.size()):
		if option_panels[i]:
			var is_active: bool = i == tab_index
			option_panels[i].visible = is_active

			# Show Reset button only when ControlsPanel is active
			if is_active and reset_defaults_button:
				reset_defaults_button.visible = (option_panels[i] is ControlsPanel)


## Analyzes peak mouse velocity to assign baseline sensitivity preset.
func _apply_bucket_calibration() -> void:
	print("System: Running mouse sensitivity bucket calibration.")
	var saved_sens: Variant = GlobalSettings.get_setting("Settings", "mouse_sensitivity", null)
	if saved_sens != null:
		has_calibrated = true
		return

	has_calibrated = true
	var auto_sens: float = DEFAULT_SENSITIVITY

	if max_mouse_speed > 6500.0:
		auto_sens = 0.70
		print("System: Calibrated TIER 7 - Extreme (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 5000.0:
		auto_sens = 0.50
		print("System: Calibrated TIER 6 - Fast (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 4000.0:
		auto_sens = 0.40
		print("System: Calibrated TIER 5 - Moderately Fast (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 3000.0:
		auto_sens = 0.30
		print("System: Calibrated TIER 4 - Average (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 2000.0:
		auto_sens = 0.20
		print("System: Calibrated TIER 3 - Moderately Low (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 1000.0:
		auto_sens = 0.10
		print("System: Calibrated TIER 2 - Low (Speed: ", max_mouse_speed, ")")
	else:
		auto_sens = 0.05
		print("System: Calibrated TIER 1 - Precise (Speed: ", max_mouse_speed, ")")

	GlobalSettings.save_setting("Settings", "mouse_sensitivity", auto_sens)


## Handles mouse calibration tracking, outside click closing, and global UI cancel input routing.
## [param event] Raw input event received by the viewport.
func _input(event: InputEvent) -> void:
	if not has_calibrated and event is InputEventMouseMotion:
		var current_speed: float = event.velocity.length()
		if current_speed > max_mouse_speed:
			max_mouse_speed = current_speed

	if event is InputEventMouseButton and event.is_pressed():
		var mouse_pos: Vector2 = event.global_position

		if search_bar and search_bar.get_global_rect().has_point(mouse_pos):
			if not search_bar.text.strip_edges().is_empty():
				_on_search_text_changed(search_bar.text)
		elif search_results_panel and search_results_panel.visible:
			var in_panel: bool = search_results_panel.get_global_rect().has_point(mouse_pos)
			if not in_panel:
				print("UI: User clicked outside search panel. Closing dropdown.")
				search_results_panel.visible = false

	if event.is_action_pressed("ui_cancel"):
		if not self.visible:
			return

		if search_results_panel and search_results_panel.visible:
			print("UI: User dismissed search popup.")
			search_results_panel.visible = false
			if search_bar:
				search_bar.text = ""
			get_viewport().set_input_as_handled()
			return

		if options_menu.visible or save_load_panel.visible:
			print("UI: User canceled out of sub-menu.")
			_return_to_main_buttons()
			get_viewport().set_input_as_handled()
		elif main_buttons.visible and get_parent().has_method("toggle_pause"):
			print("UI: User canceled out of pause menu completely.")
			_on_resume_pressed()
			get_viewport().set_input_as_handled()


## Relays reset event to the active ControlsPanel instance.
func _on_reset_defaults_pressed() -> void:
	print("UI: MainMenu -> Reset to Defaults clicked.")
	for panel: Control in option_panels:
		if panel is ControlsPanel and panel.visible:
			panel.reset_to_defaults()
			break


## Automatically connects focus and hover signals to narrate buttons via SubtitleLayer.
func _connect_menu_tts_narration() -> void:
	var buttons: Array[Button] = [
		continue_button,
		new_game_button,
		restart_button,
		save_button,
		load_button,
		options_button,
		exit_button
	]
	for btn: Button in buttons:
		if is_instance_valid(btn):
			btn.focus_entered.connect(_narrate_button.bind(btn.text))
			btn.mouse_entered.connect(_narrate_button.bind(btn.text))


## Emits a subtitle request event for menu element narration.
## [param button_text] Text of the focused button.
func _narrate_button(button_text: String) -> void:
	var is_tts: bool = GlobalSettings.get_setting("Accessibility", "tts_enabled", false) as bool
	if is_tts and has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("subtitle_requested"):
			events.subtitle_requested.emit("TTSandy", button_text, 1.5)
