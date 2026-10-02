## Editor plugin registering bottom panel and managing contextual visibility.
@tool
extends EditorPlugin

## Preloaded bottom dock instance.
var dock_instance: EventSequencerDock = null

## Name of the bottom panel tab in Godot editor.
const PANEL_TITLE: String = "Event Sequence"


## Registers bottom panel control and initializes dock instance.
func _enter_tree() -> void:
	print("EventSequencerPlugin: Plugin entering tree.")
	dock_instance = EventSequencerDock.new()
	add_control_to_bottom_panel(dock_instance, PANEL_TITLE)


## Cleans up bottom panel and frees dock instance when plugin disabled.
func _exit_tree() -> void:
	print("EventSequencerPlugin: Plugin exiting tree.")
	if is_instance_valid(dock_instance):
		remove_control_from_bottom_panel(dock_instance)
		dock_instance.queue_free()


## Returns true if the selected object is an [EventSequenceTrigger].
func _handles(object: Object) -> bool:
	return object is EventSequenceTrigger


## Passes selected [EventSequenceTrigger] to dock for inspection.
func _edit(object: Object) -> void:
	if is_instance_valid(dock_instance):
		dock_instance.inspect_trigger(object as EventSequenceTrigger)


## Automatically shows bottom panel on selection, and hides it when moving away.
func _make_visible(visible: bool) -> void:
	if not is_instance_valid(dock_instance):
		return
	if visible:
		make_bottom_panel_item_visible(dock_instance)
	else:
		if dock_instance.is_visible_in_tree():
			hide_bottom_panel()
