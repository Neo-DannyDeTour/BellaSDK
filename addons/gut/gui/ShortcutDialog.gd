@tool
extends ConfirmationDialog

const GutEditorGlobals = preload('res://addons/gut/gui/editor_globals.gd')
var default_path: Variant = GutEditorGlobals.editor_shortcuts_path


@onready var scbtn_run_all: Control = $Scroll/Layout/CRunAll/ShortcutButton
@onready var scbtn_run_current_script: Control = $Scroll/Layout/CRunCurrentScript/ShortcutButton
@onready var scbtn_run_current_inner: Control = $Scroll/Layout/CRunCurrentInner/ShortcutButton
@onready var scbtn_run_current_test: Control = $Scroll/Layout/CRunCurrentTest/ShortcutButton
@onready var scbtn_run_at_cursor: Control = $Scroll/Layout/CRunAtCursor/ShortcutButton
@onready var scbtn_rerun: Control = $Scroll/Layout/CRerun/ShortcutButton
@onready var scbtn_panel: Control = $Scroll/Layout/CPanelButton/ShortcutButton
@onready var scbtn_windowed: Control = $Scroll/Layout/CToggleWindowed/ShortcutButton


@onready var all_buttons: Variant = [
	scbtn_run_all, scbtn_run_current_script, scbtn_run_current_inner,
	scbtn_run_current_test, scbtn_run_at_cursor, scbtn_rerun,
	scbtn_panel, scbtn_windowed
]


func _debug_ready() -> void:
	popup_centered()

	var btn: Button = Button.new()
	btn.text = "show"
	get_tree().root.add_child(btn)
	btn.pressed.connect(popup)
	btn.position = Vector2(100, 100)
	btn.size = Vector2(100, 100)

	size_changed.connect(func(): title = str(size))


func _ready() -> void:
	for scbtn in all_buttons:
		scbtn.connect('start_edit', _on_edit_start.bind(scbtn))
		scbtn.connect('end_edit', _on_edit_end)

	canceled.connect(_on_cancel)

	# Sizing this window on different monitors, especially compared to what it
	# looks like if you just run this project is annoying.  This is what I came
	# up with after getting annoyed.  You probably won't be looking at this
	# very often so it's fine...until it isn't.
	size = Vector2(DisplayServer.screen_get_size()) * Vector2(.5, .8)

	if(get_parent() == get_tree().root):
		_debug_ready.call_deferred()



func _cancel_all() -> void:
	for scbtn in all_buttons:
		scbtn.cancel()


# ------------
# Events
# ------------
func _on_cancel() -> void:
	_cancel_all()
	load_shortcuts()


func _on_edit_start(which: Variant) -> void:
	for scbtn in all_buttons:
		if(scbtn != which):
			scbtn.disable_set(true)
			scbtn.disable_clear(true)


func _on_edit_end() -> void:
	for scbtn in all_buttons:
		scbtn.disable_set(false)
		scbtn.disable_clear(false)


# ------------
# Public
# ------------
func save_shortcuts() -> void:
	save_shortcuts_to_file(default_path)


func save_shortcuts_to_file(path: Variant) -> void:
	var f: ConfigFile = ConfigFile.new()
	f.set_value('main', 'panel_button', scbtn_panel.get_shortcut())
	f.set_value('main', 'rerun', scbtn_rerun.get_shortcut())
	f.set_value('main', 'run_all', scbtn_run_all.get_shortcut())
	f.set_value('main', 'run_at_cursor', scbtn_run_at_cursor.get_shortcut())
	f.set_value('main', 'run_current_inner', scbtn_run_current_inner.get_shortcut())
	f.set_value('main', 'run_current_script', scbtn_run_current_script.get_shortcut())
	f.set_value('main', 'run_current_test', scbtn_run_current_test.get_shortcut())
	# f.set_value('main', 'toggle_windowed', scbtn_windowed.get_shortcut())
	f.save(path)


func load_shortcuts() -> void:
	load_shortcuts_from_file(default_path)


func load_shortcuts_from_file(path: Variant) -> void:
	var f: ConfigFile = ConfigFile.new()
	# as long as this shortcut is never modified, this is fine, otherwise
	# each thing should get its own default instead.
	var empty: Shortcut = Shortcut.new()

	f.load(path)
	scbtn_panel.set_shortcut(f.get_value('main', 'panel_button', empty))
	scbtn_rerun.set_shortcut(f.get_value('main', 'rerun', empty))
	scbtn_run_all.set_shortcut(f.get_value('main', 'run_all', empty))
	scbtn_run_at_cursor.set_shortcut(f.get_value('main', 'run_at_cursor', empty))
	scbtn_run_current_inner.set_shortcut(f.get_value('main', 'run_current_inner', empty))
	scbtn_run_current_script.set_shortcut(f.get_value('main', 'run_current_script', empty))
	scbtn_run_current_test.set_shortcut(f.get_value('main', 'run_current_test', empty))
	# scbtn_windowed.set_shortcut(f.get_value('main', 'toggle_windowed', empty))
