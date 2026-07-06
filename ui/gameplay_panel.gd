extends Panel

const DEFAULT_HEADBOB: bool = true
const DEFAULT_CROSSHAIR: bool = true

@onready var headbob_checkbox: CheckBox = %HeadbobCheckbox
@onready var crosshair_checkbox: CheckBox = %CrosshairCheckbox

func _ready() -> void:
	print("UI: Gameplay Panel initialized.")
	headbob_checkbox.toggled.connect(_on_headbob_toggled)
	crosshair_checkbox.toggled.connect(_on_crosshair_toggled)
	_load_gameplay_settings()

func _load_gameplay_settings() -> void:
	print("UI: Loading gameplay data from GlobalSettings.")
	var headbob_saved: bool = GlobalSettings.get_setting("Gameplay", "headbob", DEFAULT_HEADBOB)
	var crosshair_saved: bool = GlobalSettings.get_setting("Gameplay", "crosshair", DEFAULT_CROSSHAIR)
	
	headbob_checkbox.button_pressed = headbob_saved
	crosshair_checkbox.button_pressed = crosshair_saved
	_apply_gameplay_settings()

func _on_headbob_toggled(toggled_on: bool) -> void:
	print("Player toggled Headbob to: ", toggled_on)
	GlobalSettings.save_setting("Gameplay", "headbob", toggled_on)
	_apply_gameplay_settings()

func _on_crosshair_toggled(toggled_on: bool) -> void:
	print("Player toggled Crosshair to: ", toggled_on)
	GlobalSettings.save_setting("Gameplay", "crosshair", toggled_on)
	_apply_gameplay_settings()

func _apply_gameplay_settings() -> void:
	var player: Node = _get_player()
	if player:
		print("Engine: Applying Gameplay settings to Player.")
		if "camera_controller" in player and player.camera_controller:
			player.camera_controller.enable_headbob = headbob_checkbox.button_pressed
			
		if "hud" in player and player.hud:
			if player.hud.has_method("set_crosshair_visible"):
				player.hud.set_crosshair_visible(crosshair_checkbox.button_pressed)

func _get_player() -> Node:
	var root_node: Node = get_tree().current_scene
	if root_node and "player_body" in root_node:
		return root_node.player_body
	return null
