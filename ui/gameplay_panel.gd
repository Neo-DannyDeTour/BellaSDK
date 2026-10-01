## Coordinates gameplay preferences, mirrored motion toggles, and locale switches.
class_name GameplayPanel
extends Panel

## Sequential ISO language code list corresponding to dropdown option items.
const SUPPORTED_LOCALES: Array[String] = ["en", "es", "ru"]

## Dropdown menu for picking game difficulty.
@onready var difficulty_option: OptionButton = %DifficultyOption

## Dropdown menu for picking language.
@onready var language_option: OptionButton = %LanguageOption

## Dropdown menu for picking matchmaking region.
@onready var region_option: OptionButton = %RegionOption

## CheckButton for developer godmode toggle.
@onready var godmode_toggle: CheckButton = %GodmodeToggle

## GridContainer wrapping debug commands for production hiding.
@onready var section_debug: GridContainer = %SectionDebug

## CheckButton for introductory tutorials.
@onready var tutorials_toggle: CheckButton = %TutorialsToggle

## CheckButton for floating item prompts.
@onready var item_prompts_toggle: CheckButton = %ItemPromptsCheckbox

## CheckButton for camera headbobbing.
@onready var headbob_toggle: CheckButton = %HeadbobCheckbox

## CheckButton for screen center crosshair.
@onready var crosshair_toggle: CheckButton = %CrosshairCheckbox

## CheckButton for reducing motion sickness.
@onready var reduce_motion_toggle: CheckButton = %ReduceMotionCheckbox

## Flag indicating whether debug features are available.
var is_debug_allowed: bool = OS.has_feature("debug")


## Initializes UI widgets, applies saved settings, and binds listener signals.
func _ready() -> void:
	print("GameplayPanel: Initializing panel.")
	if not is_debug_allowed and is_instance_valid(section_debug):
		section_debug.hide()

	_setup_language_options()
	_load_preferences()
	_connect_signals()


## Populates language dropdown items in order.
func _setup_language_options() -> void:
	print("GameplayPanel: Populating languages.")
	if not is_instance_valid(language_option):
		return
	language_option.clear()
	language_option.add_item("English", 0)
	language_option.add_item("Español", 1)
	language_option.add_item("Русский", 2)


## Loads stored settings from disk into UI widgets.
func _load_preferences() -> void:
	print("GameplayPanel: Restoring saved preferences.")
	if is_instance_valid(item_prompts_toggle):
		var show_p: bool = GlobalSettings.get_setting("Gameplay", "show_item_prompts", true) as bool
		item_prompts_toggle.set_pressed_no_signal(show_p)

	if is_instance_valid(tutorials_toggle):
		var tuts: bool = GlobalSettings.get_setting("Gameplay", "show_tutorials", true) as bool
		tutorials_toggle.set_pressed_no_signal(tuts)

	if is_instance_valid(headbob_toggle):
		var hb: bool = GlobalSettings.get_setting("Gameplay", "headbob_enabled", true) as bool
		headbob_toggle.set_pressed_no_signal(hb)

	if is_instance_valid(crosshair_toggle):
		var ch: bool = GlobalSettings.get_setting("Gameplay", "crosshair_enabled", true) as bool
		crosshair_toggle.set_pressed_no_signal(ch)

	if is_instance_valid(reduce_motion_toggle):
		var rm: bool = GlobalSettings.get_setting("Accessibility", "reduce_motion", false) as bool
		reduce_motion_toggle.set_pressed_no_signal(rm)

	if is_instance_valid(difficulty_option):
		var diff_idx: int = GlobalSettings.get_setting("Gameplay", "difficulty", 1) as int
		difficulty_option.selected = diff_idx

	if is_instance_valid(language_option):
		var lang_idx: int = GlobalSettings.get_setting("Gameplay", "language", 0) as int
		language_option.selected = lang_idx
		_apply_language(lang_idx)

	if is_instance_valid(region_option):
		var reg_idx: int = GlobalSettings.get_setting("Gameplay", "region", 0) as int
		region_option.selected = reg_idx


## Connects all control signals to local handlers.
func _connect_signals() -> void:
	print("GameplayPanel: Connecting UI signals.")
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
	if is_instance_valid(reduce_motion_toggle):
		reduce_motion_toggle.toggled.connect(_on_reduce_motion_toggled)
	if is_instance_valid(language_option):
		language_option.item_selected.connect(_on_language_selected)
	if is_instance_valid(region_option):
		region_option.item_selected.connect(_on_region_selected)


## Applies locale code using [TranslationServer].
func _apply_language(index: int) -> void:
	print("GameplayPanel: Applying locale index -> ", index)
	if index >= 0 and index < SUPPORTED_LOCALES.size():
		var target_locale: String = SUPPORTED_LOCALES[index]
		TranslationServer.set_locale(target_locale)


## Handles difficulty option selection.
func _on_difficulty_selected(index: int) -> void:
	print("GameplayPanel: Difficulty changed -> ", index)
	GlobalSettings.save_setting("Gameplay", "difficulty", index)


## Handles godmode toggle state changes.
func _on_godmode_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Godmode changed -> ", button_pressed)
	if not is_debug_allowed:
		return
	var events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(events):
		events.set("is_godmode", button_pressed)


## Handles tutorial visibility changes.
func _on_tutorials_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Tutorials changed -> ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "show_tutorials", button_pressed)


## Handles item prompt visibility changes.
func _on_item_prompts_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Item prompts changed -> ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "show_item_prompts", button_pressed)
	var events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(events) and events.has_signal("item_prompts_toggled"):
		events.emit_signal("item_prompts_toggled", button_pressed)


## Handles camera headbob toggle state changes.
func _on_headbob_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Headbob changed -> ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "headbob_enabled", button_pressed)


## Handles crosshair toggle state changes.
func _on_crosshair_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Crosshair changed -> ", button_pressed)
	GlobalSettings.save_setting("Gameplay", "crosshair_enabled", button_pressed)


## Handles motion reduction toggle state changes.
func _on_reduce_motion_toggled(button_pressed: bool) -> void:
	print("GameplayPanel: Reduce motion changed -> ", button_pressed)
	GlobalSettings.save_setting("Accessibility", "reduce_motion", button_pressed)
	var events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(events) and events.has_signal("reduce_motion_toggled"):
		events.emit_signal("reduce_motion_toggled", button_pressed)


## Handles localization language selection.
func _on_language_selected(index: int) -> void:
	print("GameplayPanel: Language selected -> ", index)
	GlobalSettings.save_setting("Gameplay", "language", index)
	_apply_language(index)


## Handles matchmaking region selection.
func _on_region_selected(index: int) -> void:
	print("GameplayPanel: Region selected -> ", index)
	GlobalSettings.save_setting("Gameplay", "region", index)
