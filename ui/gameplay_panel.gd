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
	if not is_debug_allowed:
		godmode_toggle.hide()

	var show_prompts: bool = (
		GlobalSettings.get_setting("Gameplay", "show_item_prompts", true) as bool
	)
	item_prompts_toggle.set_pressed_no_signal(show_prompts)

	_connect_signals()


## Wires up all user interface signals to local listener methods.
func _connect_signals() -> void:
	print("GameplayPanel: Connecting signals...")
	difficulty_option.item_selected.connect(_on_difficulty_selected)
	godmode_toggle.toggled.connect(_on_godmode_toggled)
	tutorials_toggle.toggled.connect(_on_tutorials_toggled)
	item_prompts_toggle.toggled.connect(_on_item_prompts_toggled)


## Handles difficulty option selection.
func _on_difficulty_selected(index: int) -> void:
	print("GameplayPanel: Difficulty changed to index ", index)


## Handles godmode toggle state changes.
func _on_godmode_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: _on_godmode_toggled() - Godmode toggled. State: ", button_pressed)

	if not is_debug_allowed:
		return

	Events.is_godmode = button_pressed


## Handles tutorial visibility changes.
func _on_tutorials_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Tutorials toggled. State: ", button_pressed)


## Handles item prompt label visibility changes, saves preference, and notifies the bus.
func _on_item_prompts_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Item prompts toggled. State: ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "show_item_prompts", button_pressed)
	Events.item_prompts_toggled.emit(button_pressed)
