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

## Toggles the camera headbobbing animation during movement.
@onready var headbob_toggle: CheckButton = %HeadbobCheckbox

## Toggles the visibility of the center screen crosshair.
@onready var crosshair_toggle: CheckButton = %CrosshairCheckbox


func _ready() -> void:
	if not is_debug_allowed:
		godmode_toggle.hide()

	_connect_signals()


func _connect_signals() -> void:
	print("GameplayPanel: Connecting signals...")
	difficulty_option.item_selected.connect(_on_difficulty_selected)
	godmode_toggle.toggled.connect(_on_godmode_toggled)
	tutorials_toggle.toggled.connect(_on_tutorials_toggled)
	# Connect remaining signals here as you build them out


func _on_difficulty_selected(index: int) -> void:
	print("GameplayPanel: Difficulty changed to index ", index)


func _on_godmode_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: _on_godmode_toggled() - Godmode toggled. State: ", button_pressed)

	if not is_debug_allowed:
		return

	Events.is_godmode = button_pressed


func _on_tutorials_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Tutorials toggled. State: ", button_pressed)
