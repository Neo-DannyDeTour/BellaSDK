## A UI component representing a single save file slot.
##
## [SaveSlot] handles loading the WebP thumbnail, displaying metadata,
## and emitting signals when the user interacts with its load, save, or delete buttons.
class_name SaveSlot
extends Control

## Emitted when the primary action (Load or Overwrite) is pressed.
## [param base_path] The absolute file path to the save without the extension.
signal action_pressed(base_path: String)

## Emitted when the user changes the custom name or toggles the favorite status.
## [param save_id] The unique string ID of the save file.
## [param new_name] The updated string name input by the user.
## [param is_favorite] The updated favorite boolean status.
signal meta_updated(save_id: String, new_name: String, is_favorite: bool)

## Emitted when the delete button is pressed.
## [param save_id] The unique string ID of the save file.
## [param base_path] The absolute file path to the save without the extension.
signal delete_pressed(save_id: String, base_path: String)

## Displays the captured `.webp` screenshot of the save.
@onready var thumbnail: TextureRect = %Thumbnail
## Allows the user to rename the save file inline.
@onready var name_input: LineEdit = %NameInput
## Displays the system time when the save was created.
@onready var date_label: Label = %DateLabel
## Toggles the favorite status of the save file.
@onready var fav_button: Button = %FavButton
## The main context-sensitive button (reads "Load" or "Overwrite").
@onready var action_button: Button = %ActionButton
## Triggers the deletion prompt for the save file.
@onready var delete_button: Button = %DeleteButton

## A visual border shown when the save is marked as a favorite.
@onready var highlight_border: Control = %HighlightBorder

## The raw system file path to the `.dat` file, without the extension.
var _base_path: String = ""
## The extracted unique identifier for this save.
var _save_id: String = ""


## Called when the node enters the scene tree. Connects UI signals.
func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	name_input.focus_exited.connect(_on_name_focus_exited)
	fav_button.toggled.connect(_on_fav_toggled)
	delete_button.pressed.connect(_on_delete_button_pressed)


## Initializes the slot with metadata dictionary from the [SaveManager].
## [param data] The parsed metadata JSON.
## [param is_saving] Determines if the action button says 'Load' or 'Overwrite'.
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


## Emits the primary action signal.
func _on_action_button_pressed() -> void:
	action_pressed.emit(_base_path)


## Triggers a metadata update when the user hits 'Enter' in the line edit.
## [param _new_text] The new string, though we pull from the UI directly anyway.
func _on_name_submitted(_new_text: String) -> void:
	name_input.release_focus()
	_emit_meta_update()


## Triggers a metadata update when the user clicks away from the line edit.
func _on_name_focus_exited() -> void:
	_emit_meta_update()


## Triggers a metadata update and visual refresh when the favorite button is clicked.
## [param toggled_on] The new boolean state of the toggle button.
func _on_fav_toggled(toggled_on: bool) -> void:
	_update_visuals(toggled_on)
	_emit_meta_update()


## Internal helper to extract the current text/toggle states and emit the update signal.
func _emit_meta_update() -> void:
	var current_name: String = name_input.text.strip_edges()
	var is_fav: bool = fav_button.button_pressed
	meta_updated.emit(_save_id, current_name, is_fav)


## Emits the deletion signal containing the ID and file path.
func _on_delete_button_pressed() -> void:
	delete_pressed.emit(_save_id, _base_path)


## Intercepts raw GUI input to detect double-click events on the panel.
## [param event] The generic InputEvent entering the control node.
func _gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click:
		accept_event()
		action_pressed.emit(_base_path)


## Toggles the favorite outline and updates the favorite button text.
## [param is_fav] The state determining if the visuals should be highlighted.
func _update_visuals(is_fav: bool) -> void:
	if highlight_border:
		highlight_border.visible = is_fav

	if fav_button:
		if is_fav:
			fav_button.text = "un-FAV"
		else:
			fav_button.text = "FAV"
