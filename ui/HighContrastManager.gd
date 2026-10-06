## Global autoload that manages high-contrast UI elements for accessibility.
#class_name HighContrastManager
extends Node

## A reusable flat stylebox that creates a solid black background.
var high_contrast_style: StyleBoxFlat = StyleBoxFlat.new()

## Tracks the current state of the high contrast accessibility feature.
var is_active: bool = false


## Initializes the stylebox, loads settings, and connects to events.
func _ready() -> void:
	print("System: High Contrast Manager initialized.")
	_setup_stylebox()
	_connect_to_events()

	var setting_val: Variant = GlobalSettings.get_setting(
		"Accessibility", "high_contrast_ui", false
	)
	is_active = (setting_val == true)
	get_tree().node_added.connect(_on_scene_node_added)


## Configures the dimensions and color of the global high contrast background.
func _setup_stylebox() -> void:
	print("System: Configuring high contrast stylebox properties.")
	high_contrast_style.bg_color = Color(0.0, 0.0, 0.0, 1.0)
	high_contrast_style.content_margin_left = 6.0
	high_contrast_style.content_margin_right = 6.0
	high_contrast_style.content_margin_top = 4.0
	high_contrast_style.content_margin_bottom = 4.0


## Hooks into the global Events autoload to listen for setting toggles.
func _connect_to_events() -> void:
	var root_events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(root_events) and root_events.has_signal("high_contrast_changed"):
		root_events.connect("high_contrast_changed", _on_high_contrast_toggled)


## Triggered when the player changes the high contrast setting in the menu.
func _on_high_contrast_toggled(toggled_on: bool) -> void:
	print("System: High Contrast toggled globally to: ", toggled_on)
	is_active = toggled_on
	_process_all_nodes(get_tree().root)


## Signal callback when any new node enters the scene tree.
func _on_scene_node_added(node: Node) -> void:
	if is_active:
		_apply_contrast_to_node(node)


## Recursively iterates through the entire scene tree to apply or remove styles.
func _process_all_nodes(parent: Node) -> void:
	_apply_contrast_to_node(parent)
	for child: Node in parent.get_children():
		_process_all_nodes(child)


## Checks if a node is a text element and applies the contrast style if active.
func _apply_contrast_to_node(node: Node) -> void:
	if node is Label:
		var label_node: Label = node if node is Label else null
		if is_active:
			label_node.add_theme_stylebox_override("normal", high_contrast_style)
		else:
			label_node.remove_theme_stylebox_override("normal")

	elif node is RichTextLabel:
		var rich_node: RichTextLabel = node if node is RichTextLabel else null
		if is_active:
			rich_node.add_theme_stylebox_override("normal", high_contrast_style)
		else:
			rich_node.remove_theme_stylebox_override("normal")
