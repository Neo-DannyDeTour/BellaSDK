## Manages runtime rendering diagnostics, monitor metrics, and viewport inspection.
class_name RenderDiagnosticsPanel
extends PanelContainer

## RichTextLabel displaying formatted viewport inspection diagnostics.
@onready var diagnostics_label: RichTextLabel = %DiagnosticsLabel


## Lifecycle method called when the node enters the scene tree.
## Centers the panel horizontally and spans the full vertical viewport height.
func _ready() -> void:
	print("RenderDiagnosticsPanel: _ready() called.")
	visible = false
	_apply_layout_constraints()
	get_viewport().size_changed.connect(_apply_layout_constraints)


## Sets horizontal centering and full vertical screen spanning anchors.
func _apply_layout_constraints() -> void:
	print("RenderDiagnosticsPanel: Adjusting layout anchors to center screen.")
	var panel_width: float = 640.0
	var half_width: float = panel_width / 2.0

	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -half_width
	offset_right = half_width

	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_top = 20.0
	offset_bottom = -20.0

	custom_minimum_size = Vector2(panel_width, 0.0)


## Updates diagnostics tree inspector every frame while the window is visible.
## [param _delta] The elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if visible:
		_refresh_diagnostics_display()


## Toggles panel visibility state.
## [return] The new visibility state after toggling.
func toggle_window() -> bool:
	visible = not visible
	print("RenderDiagnosticsPanel: Visibility toggled -> ", visible)
	if visible:
		_apply_layout_constraints()
		_refresh_diagnostics_display()
	return visible


## Traverses the scene graph to update viewport update modes and layer hierarchy.
func _refresh_diagnostics_display() -> void:
	if not diagnostics_label:
		return

	var text: String = "[b][color=yellow]=== VIEWPORT & RENDER PIPELINE ===[/color][/b]\n"
	var root_vp: Window = get_tree().root
	text += (
		"• [color=white]%s[/color] (Root Window: %dx%d)\n\n"
		% [str(root_vp.name), root_vp.size.x, root_vp.size.y]
	)

	text += "[b][color=yellow]=== ACTIVE SUBVIEWPORTS ===[/color][/b]\n"
	var sub_viewports: Array[SubViewport] = []
	_collect_subviewports(root_vp, sub_viewports)

	if sub_viewports.is_empty():
		text += "[color=gray]  No active SubViewports found in tree.[/color]\n"
	else:
		for vp: SubViewport in sub_viewports:
			var mode_str: String = "UNKNOWN"
			var is_active: bool = false
			var parent_node: Node = vp.get_parent()
			var parent_visible: bool = true

			if parent_node is CanvasItem:
				parent_visible = (parent_node as CanvasItem).is_visible_in_tree()
			elif parent_node is Node3D:
				parent_visible = (parent_node as Node3D).is_visible_in_tree()

			match vp.render_target_update_mode:
				SubViewport.UPDATE_DISABLED:
					mode_str = "[color=gray]DISABLED[/color]"
					is_active = false
				SubViewport.UPDATE_ONCE:
					mode_str = "[color=yellow]ONCE[/color]"
					is_active = true
				SubViewport.UPDATE_WHEN_VISIBLE:
					mode_str = (
						"[color=green]WHEN_VISIBLE[/color]"
						if parent_visible
						else "[color=gray]WHEN_VISIBLE (Hidden)[/color]"
					)
					is_active = parent_visible
				SubViewport.UPDATE_WHEN_PARENT_VISIBLE:
					mode_str = (
						"[color=green]PARENT_VISIBLE[/color]"
						if parent_visible
						else "[color=gray]PARENT_VISIBLE (Hidden)[/color]"
					)
					is_active = parent_visible
				SubViewport.UPDATE_ALWAYS:
					mode_str = "[color=red]ALWAYS[/color]"
					is_active = true

			var status_tag: String = (
				"[color=green][ACTIVE][/color]" if is_active else "[color=red][IDLE][/color]"
			)
			var size_str: String = "%dx%d" % [vp.size.x, vp.size.y]
			var parent_name: String = str(parent_node.name) if parent_node != null else "None"

			text += ("• %s [color=white]%s[/color] (%s)\n" % [status_tag, str(vp.name), size_str])
			text += ("  └ Parent: [color=cyan]%s[/color] | Mode: %s\n" % [parent_name, mode_str])

	text += "\n[b][color=yellow]=== CANVAS LAYERS ===[/color][/b]\n"
	var canvas_layers: Array[CanvasLayer] = []
	_collect_canvas_layers(root_vp, canvas_layers)

	if canvas_layers.is_empty():
		text += "[color=gray]  No CanvasLayers found in tree.[/color]\n"
	else:
		for canvas: CanvasLayer in canvas_layers:
			var vis_str: String = (
				"[color=green]VISIBLE[/color]" if canvas.visible else "[color=gray]HIDDEN[/color]"
			)
			var is_anonymous: bool = canvas.name.begins_with("@CanvasLayer@")
			var name_color: String = "magenta" if is_anonymous else "white"

			# Resolve parent node info and node path
			var parent_node: Node = canvas.get_parent()
			var parent_name: String = (
				str(parent_node.name) if is_instance_valid(parent_node) else "None"
			)
			var node_path: String = str(canvas.get_path())

			# Resolve immediate children names to identify what is hosted inside
			var child_names: Array[String] = []
			for child: Node in canvas.get_children():
				child_names.append(child.name)
			var child_info: String = (
				", ".join(child_names) if not child_names.is_empty() else "[EMPTY]"
			)

			text += (
				"• [color=%s]%s[/color] (Layer %d) -> %s\n"
				% [name_color, str(canvas.name), canvas.layer, vis_str]
			)
			text += ("  └ Path: [color=gray]%s[/color]\n" % [node_path])
			text += (
				"  └ Parent: [color=cyan]%s[/color] | Children: [color=orange]%s[/color]\n"
				% [parent_name, child_info]
			)

	diagnostics_label.text = text


## Recursively collects all SubViewport nodes including internal children.
## [param current_node] The current node being inspected.
## [param out_viewports] The destination array to populate with found SubViewports.
func _collect_subviewports(current_node: Node, out_viewports: Array[SubViewport]) -> void:
	if current_node is SubViewport:
		out_viewports.append(current_node)

	for child: Node in current_node.get_children(true):
		_collect_subviewports(child, out_viewports)


## Recursively collects all CanvasLayer nodes including internal children.
## [param current_node] The current node being inspected.
## [param out_layers] The destination array to populate with found CanvasLayers.
func _collect_canvas_layers(current_node: Node, out_layers: Array[CanvasLayer]) -> void:
	if current_node is CanvasLayer:
		out_layers.append(current_node)

	for child: Node in current_node.get_children(true):
		_collect_canvas_layers(child, out_layers)
