## Manages setting row hover highlighting, subtle row focus, and horror UI styling.
class_name UniversalSettingHighlighter
extends ColorRect

## Emitted when a row gains hover focus with [param controls].
@warning_ignore("unused_signal")
signal row_highlighted(controls: Array[Control])

## Emitted when hover focus leaves the active row.
@warning_ignore("unused_signal")
signal highlight_cleared

## Default padding added around unscaled row boundaries in pixels.
const DEFAULT_PADDING: Vector2 = Vector2(8.0, 5.0)

## Subtle vertical expansion applied to the highlighter bar on hover.
const HIGHLIGHTER_HOVER_SCALE: Vector2 = Vector2(1.0, 1.06)

## Z-index for the highlighter surface (above panel background, below hovered row controls).
const HIGHLIGHTER_Z_INDEX: int = 0

## Z-index assigned to hovered row controls so text and buttons stay untouched on top.
const ELEVATED_ROW_Z_INDEX: int = 2

## Highlight font color applied to labels in the active hovered row.
const HOVER_LABEL_COLOR: Color = Color(1.0, 0.94, 0.88, 1.0)

## Idle font color applied to setting row labels.
const IDLE_LABEL_COLOR: Color = Color(0.86, 0.86, 0.88, 1.0)

## Shader uniform name for rectangle pixel dimensions.
const PARAM_RECT_SIZE: StringName = &"rect_size"

## Shader uniform name for local mouse coordinates inside the rectangle.
const PARAM_MOUSE_POS: StringName = &"mouse_pos"

## Shader uniform name for fade intensity.
const PARAM_HOVER_INTENSITY: StringName = &"hover_intensity"

## Human-readable sub-tab title overrides for raw section node names.
const TAB_TITLE_OVERRIDES: Dictionary[String, String] = {
	"DisplaySection": "Display",
	"QualitySection": "Quality",
	"EffectsSection": "Effects",
	"HardwareSection": "Hardware",
}

## Extra pixel padding applied to the computed row rectangle.
@export var padding: Vector2 = DEFAULT_PADDING

## Duration of hover fade and scale transitions in seconds.
@export var transition_duration: float = 0.14

## Controls belonging to the currently highlighted setting row.
var _active_row_controls: Array[Control] = []

## Combined unscaled global rectangle of the active setting row.
var _active_row_rect: Rect2 = Rect2()

## Active tween for smoothly animating shader hover intensity and highlighter scale.
var _fade_tween: Tween

## Original z_index values for controls currently or recently elevated.
var _original_z_indices: Dictionary[Control, int] = {}

## Cached reference to the setting row hover [ShaderMaterial].
var _shader_mat: ShaderMaterial

## Active hover tracking flag.
var _is_hovered: bool = false

## Current interpolated hover intensity value.
var _current_intensity: float = 0.0

## Cached list of registered panel root controls.
var _registered_panels: Array[Control] = []

## Registered setting rows mapped by their owning panel root [Control].
var _panel_rows: Dictionary[Control, Array] = {}

## Cached scroll containers per panel root used to clip row hit detection.
var _panel_scrolls: Dictionary[Control, ScrollContainer] = {}

## Currently scanned panel root during registration.
var _scanning_panel: Control = null

## Shared normal stylebox for setting buttons so they stay opaque over the red effect.
var _btn_normal_style: StyleBoxFlat

## Shared hover stylebox for setting buttons.
var _btn_hover_style: StyleBoxFlat

## Shared pressed/active stylebox for setting buttons.
var _btn_pressed_style: StyleBoxFlat

## Shared normal stylebox for [LineEdit] numerical inputs.
var _line_edit_style: StyleBoxFlat

## Shared selected tab stylebox for [TabContainer] sub-tabs.
var _tab_selected_style: StyleBoxFlat

## Shared unselected tab stylebox for [TabContainer] sub-tabs.
var _tab_unselected_style: StyleBoxFlat

## Shared hovered tab stylebox for [TabContainer] sub-tabs.
var _tab_hover_style: StyleBoxFlat


## Configures overlay non-blocking properties and initializes shared UI styles in [method _ready].
func _ready() -> void:
	print("UniversalSettingHighlighter: Overlay initialized.")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = HIGHLIGHTER_Z_INDEX
	set_process(false)
	set_physics_process(false)
	_shader_mat = material as ShaderMaterial
	assert(_shader_mat != null, "UniversalSettingHighlighter requires a ShaderMaterial.")
	_shader_mat.set_shader_parameter(PARAM_HOVER_INTENSITY, 0.0)
	_init_shared_styles()


## Evaluates row hover state on mouse motion events without relying on fragile child signals.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion or event is InputEventMouseButton):
		return

	var active_panel: Control = _get_visible_panel()
	if active_panel == null:
		if _is_hovered:
			clear_highlight()
		return

	var mouse_global: Vector2 = get_global_mouse_position()
	var matched_row: Array[Control] = _find_row_at_point(active_panel, mouse_global)
	if not matched_row.is_empty():
		highlight_row(matched_row)
		_update_shader_mouse(mouse_global)
	elif _is_hovered:
		clear_highlight()


## Traverses, styles, and registers setting rows for [param panel_root].
func register_panel(panel_root: Control) -> void:
	if _registered_panels.has(panel_root):
		return
	_registered_panels.append(panel_root)
	_panel_rows[panel_root] = []
	print("UniversalSettingHighlighter: Registering panel ", panel_root.name)
	panel_root.visibility_changed.connect(
		_on_panel_visibility_changed.bind(panel_root), Object.CONNECT_REFERENCE_COUNTED
	)
	if not panel_root.is_node_ready():
		await panel_root.ready
	_scanning_panel = panel_root
	_scan_node(panel_root)
	_scanning_panel = null


## Highlights target setting row with [param controls] while keeping text and buttons in place.
func highlight_row(controls: Array[Control]) -> void:
	if controls.is_empty():
		return
	if _is_hovered and _active_row_controls == controls:
		_update_rect_geometry()
		return
	if not _active_row_controls.is_empty():
		_restore_row_controls(_active_row_controls)
	_active_row_controls = controls.duplicate()
	_is_hovered = true
	print("UniversalSettingHighlighter: Highlighted row with ", controls.size(), " control(s).")
	_sync_parent_to_active_panel(controls[0])
	_update_rect_geometry()
	_elevate_row_controls(_active_row_controls)
	_animate_highlighter(1.0, HIGHLIGHTER_HOVER_SCALE)
	_update_shader_mouse(get_global_mouse_position())
	row_highlighted.emit(_active_row_controls)


## Clears active highlight, restores row z-index, and smoothly fades shader out.
func clear_highlight() -> void:
	if not _is_hovered and _active_row_controls.is_empty():
		return
	_is_hovered = false
	print("UniversalSettingHighlighter: Clearing active row highlight.")
	_restore_row_controls(_active_row_controls)
	_active_row_controls = []
	_animate_highlighter(0.0, Vector2.ONE)
	highlight_cleared.emit()


## Returns the currently visible registered options panel, or null if none is visible.
func _get_visible_panel() -> Control:
	for panel: Control in _registered_panels:
		if is_instance_valid(panel) and panel.is_visible_in_tree():
			return panel
	return null


## Finds the registered setting row under [param mouse_global] inside [param panel_root].
func _find_row_at_point(panel_root: Control, mouse_global: Vector2) -> Array[Control]:
	var empty_row: Array[Control] = []
	if _panel_scrolls.has(panel_root):
		var scroll: ScrollContainer = _panel_scrolls[panel_root]
		if is_instance_valid(scroll) and scroll.is_visible_in_tree():
			if not scroll.get_global_rect().has_point(mouse_global):
				return empty_row

	if not _panel_rows.has(panel_root):
		return empty_row

	var rows: Array = _panel_rows[panel_root]
	for raw_row: Variant in rows:
		if not (raw_row is Array):
			continue
		var row_controls: Array[Control] = raw_row as Array[Control]
		var row_rect: Rect2 = _compute_row_rect(row_controls)
		if (
			row_rect.size.x > 0.0
			and row_rect.grow_individual(8.0, 6.0, 8.0, 6.0).has_point(mouse_global)
		):
			return row_controls.duplicate()
	return empty_row


## Computes the combined unscaled global rectangle for [param row_controls].
func _compute_row_rect(row_controls: Array[Control]) -> Rect2:
	var combined: Rect2 = Rect2()
	var has_rect: bool = false
	for ctrl: Control in row_controls:
		if not is_instance_valid(ctrl) or not ctrl.is_visible_in_tree():
			continue
		var rect: Rect2 = Rect2(ctrl.global_position, ctrl.size)
		if not has_rect:
			combined = rect
			has_rect = true
		else:
			combined = combined.merge(rect)
	return combined


## Builds shared opaque horror [StyleBoxFlat] resources for buttons, inputs, and sub-tabs.
func _init_shared_styles() -> void:
	_btn_normal_style = StyleBoxFlat.new()
	_btn_normal_style.bg_color = Color(0.08, 0.08, 0.1, 0.96)
	_btn_normal_style.border_color = Color(0.24, 0.24, 0.28, 0.95)
	_btn_normal_style.set_border_width_all(1)
	_btn_normal_style.set_corner_radius_all(3)
	_btn_normal_style.content_margin_left = 10.0
	_btn_normal_style.content_margin_right = 10.0
	_btn_normal_style.content_margin_top = 5.0
	_btn_normal_style.content_margin_bottom = 5.0

	_btn_hover_style = _btn_normal_style.duplicate() as StyleBoxFlat
	_btn_hover_style.bg_color = Color(0.14, 0.1, 0.11, 0.98)
	_btn_hover_style.border_color = Color(0.75, 0.22, 0.22, 1.0)

	_btn_pressed_style = _btn_normal_style.duplicate() as StyleBoxFlat
	_btn_pressed_style.bg_color = Color(0.28, 0.06, 0.06, 0.98)
	_btn_pressed_style.border_color = Color(0.95, 0.22, 0.22, 1.0)
	_btn_pressed_style.border_width_bottom = 2

	_line_edit_style = _btn_normal_style.duplicate() as StyleBoxFlat
	_line_edit_style.bg_color = Color(0.06, 0.06, 0.08, 0.96)

	_tab_selected_style = StyleBoxFlat.new()
	_tab_selected_style.bg_color = Color(0.16, 0.05, 0.05, 0.96)
	_tab_selected_style.border_color = Color(0.92, 0.18, 0.18, 1.0)
	_tab_selected_style.border_width_bottom = 3
	_tab_selected_style.border_width_top = 1
	_tab_selected_style.border_width_left = 1
	_tab_selected_style.border_width_right = 1
	_tab_selected_style.content_margin_left = 18.0
	_tab_selected_style.content_margin_right = 18.0
	_tab_selected_style.content_margin_top = 8.0
	_tab_selected_style.content_margin_bottom = 8.0

	_tab_unselected_style = StyleBoxFlat.new()
	_tab_unselected_style.bg_color = Color(0.06, 0.06, 0.08, 0.88)
	_tab_unselected_style.border_color = Color(0.2, 0.2, 0.24, 0.8)
	_tab_unselected_style.set_border_width_all(1)
	_tab_unselected_style.content_margin_left = 18.0
	_tab_unselected_style.content_margin_right = 18.0
	_tab_unselected_style.content_margin_top = 8.0
	_tab_unselected_style.content_margin_bottom = 8.0

	_tab_hover_style = _tab_unselected_style.duplicate() as StyleBoxFlat
	_tab_hover_style.bg_color = Color(0.12, 0.07, 0.07, 0.94)
	_tab_hover_style.border_color = Color(0.6, 0.18, 0.18, 0.95)


## Reparents highlighter as first child of the active [Panel] so it draws behind all row widgets.
func _sync_parent_to_active_panel(first_ctrl: Control) -> void:
	if not is_instance_valid(first_ctrl):
		return
	var target_panel: Control = _get_visible_panel()
	if not is_instance_valid(target_panel):
		return
	if get_parent() != target_panel:
		Utilities.reparent_keep_transform(self, target_panel, true)
		target_panel.move_child(self, 0)
	top_level = true
	z_index = HIGHLIGHTER_Z_INDEX


## Callback invoked when a registered panel changes visibility.
func _on_panel_visibility_changed(panel_root: Control) -> void:
	if is_instance_valid(panel_root) and not panel_root.is_visible_in_tree():
		clear_highlight()


## Callback invoked when a [TabContainer] switches active sub-tabs.
func _on_tab_changed(_tab: int) -> void:
	clear_highlight()


## Recursively traverses hierarchy discovering grids, rows, and styling sub-tabs.
func _scan_node(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if node is ScrollContainer and is_instance_valid(_scanning_panel):
		if not _panel_scrolls.has(_scanning_panel):
			_panel_scrolls[_scanning_panel] = node as ScrollContainer

	if node is TabContainer:
		var tabs: TabContainer = node as TabContainer
		_style_tab_container(tabs)
		Utilities.safe_connect(tabs.tab_changed, _on_tab_changed)

	if node is GridContainer:
		_register_grid(node as GridContainer)
		return

	for child: Node in node.get_children():
		if child is HSeparator or child == self:
			continue
		if child is HBoxContainer and _is_leaf_setting_row(child as Control):
			_register_hbox_row(child as HBoxContainer)
		elif child is BaseButton and child.get_parent() is VBoxContainer:
			_register_single_control_row(child as Control)
		else:
			_scan_node(child)


## Renames raw section node names to clean tab titles and applies horror tab styling.
func _style_tab_container(tabs: TabContainer) -> void:
	tabs.add_theme_stylebox_override("tab_selected", _tab_selected_style)
	tabs.add_theme_stylebox_override("tab_unselected", _tab_unselected_style)
	tabs.add_theme_stylebox_override("tab_hovered", _tab_hover_style)
	tabs.add_theme_color_override("font_selected_color", Color(1.0, 0.92, 0.9, 1.0))
	tabs.add_theme_color_override("font_unselected_color", Color(0.68, 0.68, 0.72, 1.0))
	tabs.add_theme_color_override("font_hovered_color", Color(0.95, 0.85, 0.85, 1.0))

	var tab_count: int = tabs.get_tab_count()
	for i: int in range(tab_count):
		var tab_ctrl: Control = tabs.get_tab_control(i)
		if is_instance_valid(tab_ctrl) and TAB_TITLE_OVERRIDES.has(tab_ctrl.name):
			tabs.set_tab_title(i, TAB_TITLE_OVERRIDES[tab_ctrl.name])


## Applies opaque horror styling to row controls so buttons never look semi-transparent on hover.
func _style_row_control(ctrl: Control) -> void:
	if ctrl is HorrorButton or ctrl == self:
		return
	if ctrl is Label:
		var lbl: Label = ctrl as Label
		lbl.add_theme_color_override("font_color", IDLE_LABEL_COLOR)
	elif ctrl is LineEdit:
		var edit: LineEdit = ctrl as LineEdit
		edit.add_theme_stylebox_override("normal", _line_edit_style)
		edit.add_theme_stylebox_override("focus", _btn_hover_style)
		edit.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	elif ctrl is Button and not (ctrl is CheckBox) and not (ctrl is CheckButton):
		var btn: Button = ctrl as Button
		btn.add_theme_stylebox_override("normal", _btn_normal_style)
		btn.add_theme_stylebox_override("hover", _btn_hover_style)
		btn.add_theme_stylebox_override("pressed", _btn_pressed_style)
		btn.add_theme_stylebox_override("hover_pressed", _btn_pressed_style)
		btn.add_theme_color_override("font_color", Color(0.88, 0.88, 0.9, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.94, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.88, 1.0))
		btn.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.96, 0.92, 1.0))

	for child: Node in ctrl.get_children():
		if child is Control:
			_style_row_control(child as Control)


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


## Registers grouped setting rows inside a [GridContainer] and adds comfortable vertical spacing.
func _register_grid(grid: GridContainer) -> void:
	grid.add_theme_constant_override("v_separation", 12)
	grid.add_theme_constant_override("h_separation", 16)
	var cols: int = maxi(grid.columns, 1)
	var children: Array[Node] = grid.get_children()
	var total: int = children.size()
	for i: int in range(0, total, cols):
		var row_end: int = mini(i + cols, total)
		var row_items: Array[Control] = []
		for j: int in range(i, row_end):
			var child_node: Node = children[j]
			if child_node is Control and child_node != self:
				var ctrl: Control = child_node as Control
				_style_row_control(ctrl)
				row_items.append(ctrl)
		if row_items.is_empty():
			continue
		_store_registered_row(row_items)


## Registers a standalone [HBoxContainer] setting row.
func _register_hbox_row(hbox: HBoxContainer) -> void:
	var row_items: Array[Control] = []
	for child: Node in hbox.get_children():
		if child is Control and child != self:
			var ctrl: Control = child as Control
			_style_row_control(ctrl)
			row_items.append(ctrl)
	if row_items.is_empty():
		return
	_store_registered_row(row_items)


## Registers a single full-width control as a row.
func _register_single_control_row(ctrl: Control) -> void:
	_style_row_control(ctrl)
	var row_items: Array[Control] = [ctrl]
	_store_registered_row(row_items)


## Appends [param row_items] into the active panel's row catalog.
func _store_registered_row(row_items: Array[Control]) -> void:
	if is_instance_valid(_scanning_panel) and _panel_rows.has(_scanning_panel):
		_panel_rows[_scanning_panel].append(row_items)


## Computes unscaled bounding geometry for the active row and configures pivots.
func _update_rect_geometry() -> void:
	if _active_row_controls.is_empty():
		return
	var combined: Rect2 = _compute_row_rect(_active_row_controls)
	if combined.size.x <= 0.0:
		return
	combined = combined.grow_individual(padding.x, padding.y, padding.x, padding.y)
	_active_row_rect = combined
	global_position = combined.position
	size = combined.size
	Utilities.center_control(self)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter(PARAM_RECT_SIZE, size)


## Updates the local mouse coordinates uniform inside the shader.
func _update_shader_mouse(mouse_global: Vector2) -> void:
	if _shader_mat == null:
		return
	var local_mouse: Vector2 = get_global_transform_with_canvas().affine_inverse() * mouse_global
	_shader_mat.set_shader_parameter(PARAM_MOUSE_POS, local_mouse)


## Elevates z_index on [param controls] so text and buttons stay crisp on top without shifting.
func _elevate_row_controls(controls: Array[Control]) -> void:
	for ctrl: Control in controls:
		if not is_instance_valid(ctrl):
			continue
		if not _original_z_indices.has(ctrl):
			_original_z_indices[ctrl] = ctrl.z_index
		ctrl.z_index = ELEVATED_ROW_Z_INDEX
		if ctrl is Label:
			(ctrl as Label).add_theme_color_override("font_color", HOVER_LABEL_COLOR)


## Restores original z_index and label color for [param controls].
func _restore_row_controls(controls: Array[Control]) -> void:
	for ctrl: Control in controls:
		if not is_instance_valid(ctrl):
			continue
		if _original_z_indices.has(ctrl):
			ctrl.z_index = _original_z_indices[ctrl]
			_original_z_indices.erase(ctrl)
		if ctrl is Label:
			(ctrl as Label).add_theme_color_override("font_color", IDLE_LABEL_COLOR)


## Tweens highlighter shader intensity and subtle vertical scale simultaneously.
func _animate_highlighter(target_intensity: float, target_scale: Vector2) -> void:
	if _shader_mat == null:
		return
	_fade_tween = Utilities.reset_tween_ext(self, _fade_tween, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	if _fade_tween == null:
		return
	_fade_tween.set_parallel(true)
	_fade_tween.tween_method(
		_set_shader_intensity, _current_intensity, target_intensity, transition_duration
	)
	_fade_tween.tween_property(self, "scale", target_scale, transition_duration)


## Helper callback updating cached intensity and shader parameter.
func _set_shader_intensity(val: float) -> void:
	_current_intensity = val
	if _shader_mat != null:
		_shader_mat.set_shader_parameter(PARAM_HOVER_INTENSITY, val)
