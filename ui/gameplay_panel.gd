## Controls gameplay and accessibility configuration toggles in the UI.
class_name GameplayPanel
extends Panel

## Dropdown menu for selecting the active game difficulty.
@onready var difficulty_option: OptionButton = %DifficultyOption

## Dropdown menu for selecting the localization language.
@onready var language_option: OptionButton = %LanguageOption

## Dropdown menu for selecting the multiplayer matchmaking region.
@onready var region_option: OptionButton = %RegionOption

## Toggles the invincible state where player health cannot drop below zero.
@onready var godmode_toggle: CheckButton = %GodmodeToggle

## Security variable: Indicates if debug commands (godmode) are allowed.
var is_debug_allowed: bool = OS.has_feature("debug")

## Toggles the display of introductory hints and tooltips.
@onready var tutorials_toggle: CheckButton = %TutorialsToggle

## Toggles the display of floating text labels above interactive items.
@onready var item_prompts_toggle: CheckButton = %ItemPromptsCheckbox

## Toggles the camera headbobbing animation during movement.
@onready var headbob_toggle: CheckButton = %HeadbobCheckbox

## Toggles the visibility of the center screen crosshair.
@onready var crosshair_toggle: CheckButton = %CrosshairCheckbox


## Initializes panel state, loads saved preferences, and connects UI events.
func _ready() -> void:
	print("GameplayPanel: _ready() called.")
	if not is_debug_allowed and is_instance_valid(godmode_toggle):
		godmode_toggle.hide()

	_load_preferences()
	_connect_signals()


## Loads persisted settings into controls without triggering change callbacks.
func _load_preferences() -> void:
	print("GameplayPanel: Loading preferences.")
	if is_instance_valid(item_prompts_toggle):
		var show_prompts: bool = (
			GlobalSettings.get_setting("Gameplay", "show_item_prompts", true) as bool
		)
		item_prompts_toggle.set_pressed_no_signal(show_prompts)

	if is_instance_valid(tutorials_toggle):
		var tutorials: bool = GlobalSettings.get_setting("Gameplay", "show_tutorials", true) as bool
		tutorials_toggle.set_pressed_no_signal(tutorials)

	if is_instance_valid(headbob_toggle):
		var headbob: bool = GlobalSettings.get_setting("Gameplay", "headbob_enabled", true) as bool
		headbob_toggle.set_pressed_no_signal(headbob)

	if is_instance_valid(crosshair_toggle):
		var crosshair: bool = (
			GlobalSettings.get_setting("Gameplay", "crosshair_enabled", true) as bool
		)
		crosshair_toggle.set_pressed_no_signal(crosshair)

	if is_instance_valid(difficulty_option):
		var diff_idx: int = GlobalSettings.get_setting("Gameplay", "difficulty", 1) as int
		difficulty_option.selected = diff_idx

	if is_instance_valid(language_option):
		var lang_idx: int = GlobalSettings.get_setting("Gameplay", "language", 0) as int
		language_option.selected = lang_idx

	if is_instance_valid(region_option):
		var reg_idx: int = GlobalSettings.get_setting("Gameplay", "region", 0) as int
		region_option.selected = reg_idx


## Wires up all user interface signals to local listener methods.
func _connect_signals() -> void:
	print("GameplayPanel: Connecting signals...")
	if is_instance_valid(difficulty_option):
		difficulty_option.item_selected.connect(_on_difficulty_selected)
	if is_instance_valid(godmode_toggle):
		godmode_toggle.toggled.connect(_on_godmode_toggled)
	if is_instance_valid(tutorials_toggle):
		tutorials_toggle.toggled.connect(_on_tutorials_toggled)
	if is_instance_valid(item_prompts_toggle):
		item_prompts_toggle.toggled.connect(_on_item_prompts_toggled)
	if is_instance_valid(headbob_toggle):
		headbob_toggle.toggled.connect(_on_headbob_toggled)
	if is_instance_valid(crosshair_toggle):
		crosshair_toggle.toggled.connect(_on_crosshair_toggled)
	if is_instance_valid(language_option):
		language_option.item_selected.connect(_on_language_selected)
	if is_instance_valid(region_option):
		region_option.item_selected.connect(_on_region_selected)


## Handles difficulty option selection.
## [param index] Chosen difficulty index.
func _on_difficulty_selected(index: int) -> void:
	print("GameplayPanel: Difficulty changed to index ", index)
	GlobalSettings.save_setting("Gameplay", "difficulty", index)


## Handles godmode toggle state changes.
## [param button_pressed] Enabled state.
func _on_godmode_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: _on_godmode_toggled() - State: ", button_pressed)
	if not is_debug_allowed:
		return
	Events.is_godmode = button_pressed


## Handles tutorial visibility changes.
## [param button_pressed] Enabled state.
func _on_tutorials_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Tutorials toggled. State: ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "show_tutorials", button_pressed)


## Handles item prompt label visibility changes, saves preference, and notifies the bus.
## [param button_pressed] Enabled state.
func _on_item_prompts_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Item prompts toggled. State: ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "show_item_prompts", button_pressed)
	Events.item_prompts_toggled.emit(button_pressed)


## Handles camera headbob toggle state changes.
## [param button_pressed] Enabled state.
func _on_headbob_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Headbob toggled. State: ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "headbob_enabled", button_pressed)


## Handles crosshair toggle state changes.
## [param button_pressed] Enabled state.
func _on_crosshair_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Crosshair toggled. State: ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "crosshair_enabled", button_pressed)


## Handles localization language selection.
## [param index] Chosen language index.
func _on_language_selected(index: int) -> void:
	print("GameplayPanel: Language changed to index ", index)
	GlobalSettings.save_setting("Gameplay", "language", index)


## Handles matchmaking region selection.
## [param index] Chosen region index.
func _on_region_selected(index: int) -> void:
	print("GameplayPanel: Matchmaking region changed to index ", index)
	GlobalSettings.save_setting("Gameplay", "region", index)
