extends Window

@onready var rtl: RichTextLabel = $TextDisplay/RichTextLabel

func _get_file_as_text(path: String) -> String:
	var to_return: String = ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f != null:
		to_return = f.get_as_text()
	else:
		to_return = str('ERROR:  Could not open file.  Error code ', FileAccess.get_open_error())
	return to_return

func _ready() -> void:
	rtl.clear()

func _on_OpenFile_pressed() -> void:
	$FileDialog.popup_centered()

func _on_FileDialog_file_selected(path: String) -> void:
	show_file(path)

func _on_Close_pressed() -> void:
	self.hide()

func show_file(path: String) -> void:
	var text: String = _get_file_as_text(path)
	if text == '':
		text = '<Empty File>'
	rtl.set_text(text)
	self.window_title = path

func show_open() -> void:
	self.popup_centered()
	$FileDialog.popup_centered()

func get_rich_text_label() -> RichTextLabel:
	return $TextDisplay/RichTextLabel

func _on_Home_pressed() -> void:
	rtl.scroll_to_line(0)

func _on_End_pressed() -> void:
	rtl.scroll_to_line(rtl.get_line_count() -1)

func _on_Copy_pressed() -> void:
	return
	# OS.clipboard = rtl.text

func _on_file_dialog_visibility_changed() -> void:
	if rtl.text.length() == 0 and not $FileDialog.visible:
		self.hide()
