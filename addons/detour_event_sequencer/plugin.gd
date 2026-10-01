## Editor plugin registering the Event Sequencer bottom panel dock.
@tool
extends EditorPlugin

## Preloaded bottom dock instance.
var dock_instance: EventSequencerDock = null

## Name of the bottom panel tab in Godot editor.
const PANEL_TITLE: String = "Event Sequence"

## [method _enter_tree] registers bottom panel and selection signal.
func _enter_tree() -> void:
	print("Source Sequencer plugin entering editor tree.")
	dock_instance = EventSequencerDock.new()
	add_control_to_bottom_panel(dock_instance, PANEL_TITLE)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)

## [method _exit_tree] cleans up bottom panel and disconnected signals.
func _exit_tree() -> void:
	print("Source Sequencer plugin exiting editor tree.")
	if is_instance_valid(dock_instance):
		remove_control_from_bottom_panel(dock_instance)
		dock_instance.queue_free()

## Updates dock when user selects a different node in the editor.
func _on_selection_changed() -> void:
	print("Editor selection changed.")
	var selected_nodes: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty():
		if is_instance_valid(dock_instance):
			dock_instance.inspect_trigger(null)
		return
	var selected: Node = selected_nodes[0]
	if selected is EventSequenceTrigger:
		if is_instance_valid(dock_instance):
			dock_instance.inspect_trigger(selected)
	else:
		if is_instance_valid(dock_instance):
			dock_instance.inspect_trigger(null)
