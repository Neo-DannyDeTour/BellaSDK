## Editor plugin registering [EventSequencerDock] and [EventSequencerGizmoPlugin].
@tool
extends EditorPlugin

## Title displayed on the bottom panel tab.
const PANEL_TITLE: String = "Event Sequence"

## Active dock instance managed by this plugin.
var dock_instance: EventSequencerDock = null

## Active 3D gizmo plugin rendering connection arrows.
var gizmo_plugin: EventSequencerGizmoPlugin = null


## Instantiates and registers bottom panel control and 3D gizmo when plugin enters tree.
func _enter_tree() -> void:
	print("EventSequencerPlugin: Entering tree.")
	dock_instance = EventSequencerDock.new()
	add_control_to_bottom_panel(dock_instance, PANEL_TITLE)

	gizmo_plugin = EventSequencerGizmoPlugin.new()
	add_node_3d_gizmo_plugin(gizmo_plugin)


## Removes and frees bottom panel control and 3D gizmo when plugin exits tree.
func _exit_tree() -> void:
	print("EventSequencerPlugin: Exiting tree.")
	if is_instance_valid(gizmo_plugin):
		remove_node_3d_gizmo_plugin(gizmo_plugin)
		gizmo_plugin = null

	if is_instance_valid(dock_instance):
		remove_control_from_bottom_panel(dock_instance)
		dock_instance.queue_free()


## Returns true when [param object] is an [EventSequenceTrigger].
func _handles(object: Object) -> bool:
	return object is EventSequenceTrigger


## Passes selected [EventSequenceTrigger] to [member dock_instance] and refreshes 3D gizmos.
func _edit(object: Object) -> void:
	var trigger: EventSequenceTrigger = object as EventSequenceTrigger
	if is_instance_valid(dock_instance):
		dock_instance.inspect_trigger(trigger)
	if is_instance_valid(trigger):
		trigger.update_gizmos()


## Shows bottom panel when selecting an [EventSequenceTrigger] and hides on deselect.
func _make_visible(visible: bool) -> void:
	if not is_instance_valid(dock_instance):
		return
	if visible:
		make_bottom_panel_item_visible(dock_instance)
	elif dock_instance.is_visible_in_tree():
		hide_bottom_panel()
