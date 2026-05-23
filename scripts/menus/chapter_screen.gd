extends Control

# Track the active screen instance globally
static var active_instance: Control = null

@export var chapters: Array[ChapterData] = []

@onready var chapter_list: HBoxContainer = %ChapterList
@onready var chapter_button_template: VBoxContainer = %ChapterButtonTemplate

@onready var desc_title: Label = %DescTitle
@onready var desc_text: RichTextLabel = %DescText
@onready var play_button: Button = %PlayButton
@onready
var back_button: Button = $MarginContainer/VBoxContainer/MainLayout/DetailsPanel/MarginContainer/BottomSplit/ButtonSection/BackButton
@onready var background: TextureRect = %Background

var selected_chapter: ChapterData = null


func _ready() -> void:
	active_instance = self
	chapter_button_template.hide()
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)

	for i in chapters.size():
		var chapter := chapters[i]
		var item := chapter_button_template.duplicate()
		item.show()

		var btn: Button = item.get_node("Btn")
		var label: Label = item.get_node("ChapterTitle")

		btn.icon = chapter.image
		label.text = str(i + 1) + ". " + chapter.chapter_name

		btn.pressed.connect(_on_chapter_selected.bind(chapter))
		btn.gui_input.connect(_on_image_gui_input.bind(chapter))
		btn.mouse_entered.connect(_on_chapter_selected.bind(chapter))

		chapter_list.add_child(item)

	if chapters.size() > 0:
		_on_chapter_selected(chapters[0])


func _exit_tree() -> void:
	if active_instance == self:
		active_instance = null


# --- NEW: Catch ESC specifically for this screen ---
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		# This prevents the Main Menu from also receiving the ESC press
		get_viewport().set_input_as_handled()


func _on_chapter_selected(chapter: ChapterData) -> void:
	selected_chapter = chapter
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description
	background.texture = chapter.image


func _on_play_pressed() -> void:
	if selected_chapter and selected_chapter.scene_path != "":
		get_tree().paused = false
		get_tree().change_scene_to_file(selected_chapter.scene_path)
	else:
		push_warning("No scene path assigned to this chapter!")


func _on_back_pressed() -> void:
	var parent := get_parent()
	if parent and "main_buttons" in parent:
		parent.main_buttons.show()
		queue_free()
	else:
		get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")


func _on_image_gui_input(event: InputEvent, chapter: ChapterData) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_on_chapter_selected(chapter)
			_on_play_pressed()


func _on_chapter_hovered(chapter: ChapterData) -> void:
	background.texture = chapter.image
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description


func _on_chapter_unhovered() -> void:
	if selected_chapter:
		background.texture = selected_chapter.image
		desc_title.text = selected_chapter.chapter_name
		desc_text.text = selected_chapter.description
