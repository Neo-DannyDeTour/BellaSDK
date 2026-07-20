extends Node

## A reusable flat stylebox that creates a solid black background.
var high_contrast_style: StyleBoxFlat = StyleBoxFlat.new()

## Tracks the current state of the high contrast accessibility feature.
var is_active: bool = false


func _ready() -> void:
	print("System: High Contrast Manager initialized.")
	_setup_stylebox()
	_connect_to_events()
	
	# Load default state on boot
	is_active = GlobalSettings.get_setting("Accessibility", "high_contrast_ui", false) as bool
	get_tree().node_added.connect(_on_scene_node_added)


func _setup_stylebox() -> void:
	print("System: Configuring high contrast stylebox properties.")
	high_contrast_style.bg_color = Color(0.0, 0.0, 0.0, 1.0)
	high_contrast_style.content_margin_left = 6.0
	high_contrast_style.content_margin_right = 6.0
	high_contrast_style.content_margin_top = 4.0
	high_contrast_style.content_margin_bottom = 4.0


func _connect_to_events() -> void:
	var root_events: Node = get_node_or_null("/root/Events")
	if root_events and root_events.has_signal("high_contrast_changed"):
		root_events.connect("high_contrast_changed", _on_high_contrast_toggled)


func _on_high_contrast_toggled(toggled_on: bool) -> void:
	print("System: High Contrast toggled globally to: ", toggled_on)
	is_active = toggled_on
	_process_all_nodes(get_tree().root)


func _on_scene_node_added(node: Node) -> void:
	if is_active:
		_apply_contrast_to_node(node)


func _process_all_nodes(parent: Node) -> void:
	_apply_contrast_to_node(parent)
	for child: Node in parent.get_children():
		_process_all_nodes(child)


func _apply_contrast_to_node(node: Node) -> void:
	if node is Label:
		if is_active:
			node.add_theme_stylebox_override("normal", high_contrast_style)
		else:
			node.remove_theme_stylebox_override("normal")
			
	elif node is RichTextLabel:
		if is_active:
			node.add_theme_stylebox_override("normal", high_contrast_style)
		else:
			node.remove_theme_stylebox_override("normal")
