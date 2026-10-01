## Manages horror border highlighting across settings rows.
class_name UniversalSettingHighlighter
extends ColorRect

## Emitted when a row gains hover focus with [param controls].
signal row_highlighted(controls: Array[Control])

## Emitted when hover focus leaves the active row.
signal highlight_cleared

## Default padding added around row boundaries in pixels.
const DEFAULT_PADDING: Vector2 = Vector2(8.0, 3.0)

## Extra pixel padding applied to the computed row rectangle.
@export var padding: Vector2 = DEFAULT_PADDING

## Duration of hover fade transitions in seconds.
@export var transition_duration: float = 0.12

## Controls belonging to the currently highlighted setting row.
var _active_row_controls: Array[Control] = []

## Combined global rectangle of the active setting row.
var _active_row_rect: Rect2 = Rect2()

## Active tween for smoothly animating hover intensity.
var _fade_tween: Tween

## Cached reference to the horror border [ShaderMaterial].
var _shader_mat: ShaderMaterial

## Active hover tracking flag.
var _is_hovered: bool = false

## Cached list of registered panel root controls.
var _registered_panels: Array[Control] = []


## Configures overlay non-blocking properties in [method _ready].
func _ready() -> void:
	print("UniversalSettingHighlighter: Overlay initialized.")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	_shader_mat = material as ShaderMaterial
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("hover_intensity", 0.0)


## Checks mouse bounds and updates tracking every frame.
func _process(_delta: float) -> void:
	if not _is_hovered or _shader_mat == null:
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	if not _active_row_rect.grow(8.0).has_point(mouse_pos):
		clear_highlight()
		return
	_update_rect_geometry()


## Traverses and registers setting rows for [param panel_root].
func register_panel(panel_root: Control) -> void:
	if _registered_panels.has(panel_root):
		return
	_registered_panels.append(panel_root)
	print("UniversalSettingHighlighter: Registering panel ", panel_root.name)
	if not panel_root.is_node_ready():
		await panel_root.ready
	_scan_node(panel_root)


## Recursively traverses hierarchy discovering grids and rows.
func _scan_node(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if node is TabContainer:
		var tabs: TabContainer = node as TabContainer
		var on_tab_changed: Callable = func(_tab: int) -> void: clear_highlight()
		if not tabs.tab_changed.is_connected(on_tab_changed):
			tabs.tab_changed.connect(on_tab_changed)

	if node is GridContainer:
		_register_grid(node as GridContainer)
		return

	for child: Node in node.get_children():
		if child is HSeparator:
			continue
		if child is HBoxContainer and _is_leaf_setting_row(child as Control):
			_register_hbox_row(child as HBoxContainer)
		elif child is BaseButton and child.get_parent() is VBoxContainer:
			_register_single_control_row(child as Control)
		else:
			_scan_node(child)


## Validates whether an [HBoxContainer] is a single setting row.
func _is_leaf_setting_row(control: Control) -> bool:
	if control.get_parent() is GridContainer:
		return false
	for child: Node in control.get_children():
		if (
			child is ScrollContainer
			or child is TabContainer
			or child is GridContainer
			or child is Panel
			or child is VBoxContainer
			or child is SubViewportContainer
			or child is TextureRect
		):
			return false
	return true


## Registers grouped setting rows inside a [GridContainer].
func _register_grid(grid: GridContainer) -> void:
	print("UniversalSettingHighlighter: Scanning GridContainer: ", grid.name)
	var cols: int = maxi(grid.columns, 1)
	var children: Array[Node] = grid.get_children()
	var total: int = children.size()
	for i: int in range(0, total, cols):
		var row_end: int = mini(i + cols, total)
		var row_items: Array[Control] = []
		for j: int in range(i, row_end):
			var item: Control = children[j] as Control
			if item != null:
				row_items.append(item)
		if row_items.is_empty():
			continue
		for item: Control in row_items:
			_attach_hover_listeners(item, row_items)


## Registers a standalone [HBoxContainer] setting row.
func _register_hbox_row(hbox: HBoxContainer) -> void:
	var row_items: Array[Control] = []
	for child: Node in hbox.get_children():
		var ctrl: Control = child as Control
		if ctrl != null:
			row_items.append(ctrl)
	if row_items.is_empty():
		return
	for item: Control in row_items:
		_attach_hover_listeners(item, row_items)


## Registers a single full-width control as a row.
func _register_single_control_row(ctrl: Control) -> void:
	var row_items: Array[Control] = [ctrl]
	_attach_hover_listeners(ctrl, row_items)


## Recursively attaches hover triggers to a control and children.
func _attach_hover_listeners(ctrl: Control, row_items: Array[Control]) -> void:
	if ctrl is Label and ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		ctrl.mouse_filter = Control.MOUSE_FILTER_PASS

	var on_enter: Callable = func() -> void: _on_row_mouse_entered(row_items)
	var on_exit: Callable = func() -> void: _on_row_mouse_exited()

	if not ctrl.mouse_entered.is_connected(on_enter):
		ctrl.mouse_entered.connect(on_enter)
	if not ctrl.mouse_exited.is_connected(on_exit):
		ctrl.mouse_exited.connect(on_exit)

	for child: Node in ctrl.get_children():
		if child is Control:
			_attach_hover_listeners(child as Control, row_items)


## Highlights target setting row with [param controls].
func highlight_row(controls: Array[Control]) -> void:
	if controls.is_empty():
		return
	_active_row_controls = controls
	_is_hovered = true
	_update_rect_geometry()
	_animate_intensity(1.0)
	row_highlighted.emit(_active_row_controls)


## Clears active highlight and smoothly fades shader out.
func clear_highlight() -> void:
	_is_hovered = false
	_animate_intensity(0.0)
	_active_row_controls.clear()
	highlight_cleared.emit()


## Triggered when the mouse enters an item in the row.
func _on_row_mouse_entered(row_items: Array[Control]) -> void:
	highlight_row(row_items)


## Triggered when the mouse exits an item in the row.
func _on_row_mouse_exited() -> void:
	var mouse_pos: Vector2 = get_global_mouse_position()
	if _active_row_rect.grow(4.0).has_point(mouse_pos):
		return
	clear_highlight()


## Updates bounding geometry and shader uniform parameters.
func _update_rect_geometry() -> void:
	if _active_row_controls.is_empty():
		return
	var combined: Rect2 = Rect2()
	var has_rect: bool = false
	for ctrl: Control in _active_row_controls:
		if not is_instance_valid(ctrl) or not ctrl.is_visible_in_tree():
			continue
		var rect: Rect2 = ctrl.get_global_rect()
		if not has_rect:
			combined = rect
			has_rect = true
		else:
			combined = combined.merge(rect)
	if not has_rect:
		return
	combined = combined.grow_individual(padding.x, padding.y, padding.x, padding.y)
	_active_row_rect = combined
	global_position = combined.position
	size = combined.size
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("rect_size", size)


## Tweens the hover intensity parameter to [param target_val].
func _animate_intensity(target_val: float) -> void:
	if _shader_mat == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var current: float = _shader_mat.get_shader_parameter("hover_intensity") as float
	_fade_tween = create_tween()
	_fade_tween.tween_method(
		func(val: float) -> void: _shader_mat.set_shader_parameter("hover_intensity", val),
		current,
		target_val,
		transition_duration
	)
