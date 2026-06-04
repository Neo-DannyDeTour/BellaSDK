class_name SaveSlot
extends Control

signal action_pressed(base_path: String)
signal meta_updated(save_id: String, new_name: String, is_favorite: bool)
signal delete_pressed(save_id: String, base_path: String)

@onready var thumbnail: TextureRect = %Thumbnail
@onready var name_input: LineEdit = %NameInput
@onready var date_label: Label = %DateLabel
@onready var fav_button: Button = %FavButton
@onready var action_button: Button = %ActionButton
@onready var delete_button: Button = %DeleteButton

# Reference to our new highlight node
@onready var highlight_border: Control = %HighlightBorder

var _base_path: String = ""
var _save_id: String = ""


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	name_input.focus_exited.connect(_on_name_focus_exited)
	fav_button.toggled.connect(_on_fav_toggled)
	delete_button.pressed.connect(_on_delete_button_pressed)


func setup(data: Dictionary, is_saving: bool) -> void:
	_base_path = data.get("base_path", "")
	_save_id = data.get("id", "")
	
	name_input.text = data.get("name", "Unknown Save")
	date_label.text = data.get("timestamp", "Unknown Date")
	
	var is_fav: bool = data.get("is_favorite", false)
	fav_button.set_pressed_no_signal(is_fav)
	
	# Apply the visual state immediately on load
	_update_visuals(is_fav)
	
	if is_saving:
		action_button.text = "Overwrite"
	else:
		action_button.text = "Load"
		
	var img_path: String = _base_path + ".webp"
	if FileAccess.file_exists(img_path):
		var image: Image = Image.load_from_file(img_path)
		if image:
			thumbnail.texture = ImageTexture.create_from_image(image)


func _on_action_button_pressed() -> void:
	action_pressed.emit(_base_path)


func _on_name_submitted(_new_text: String) -> void:
	name_input.release_focus()
	_emit_meta_update()


func _on_name_focus_exited() -> void:
	_emit_meta_update()


func _on_fav_toggled(toggled_on: bool) -> void:
	# Update visuals instantly when the user clicks
	_update_visuals(toggled_on)
	_emit_meta_update()


func _emit_meta_update() -> void:
	var current_name := name_input.text.strip_edges()
	var is_fav := fav_button.button_pressed
	meta_updated.emit(_save_id, current_name, is_fav)


func _on_delete_button_pressed() -> void:
	delete_pressed.emit(_save_id, _base_path)


# Catch double clicks directly on the slot
func _gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click:
		accept_event()
		action_pressed.emit(_base_path)


# A clean helper function to handle the styling and text
func _update_visuals(is_fav: bool) -> void:
	if highlight_border:
		highlight_border.visible = is_fav
		
	if fav_button:
		if is_fav:
			fav_button.text = "un-FAV"
		else:
			fav_button.text = "FAV"
