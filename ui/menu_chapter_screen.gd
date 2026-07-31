extends Control

## Stores the currently active instance of this screen to manage global state.
static var active_instance: Control = null

## An array of ChapterData resources used to populate the chapter list.
@export var chapters: Array[ChapterData] = []

## Holds the currently selected chapter data to pass to the game scene.
var selected_chapter: ChapterData = null

## The HBoxContainer that organizes the spawned chapter buttons horizontally.
@onready var chapter_list: HBoxContainer = %ChapterList

## The template container used to clone new chapter buttons.
@onready var chapter_button_template: VBoxContainer = %ChapterButtonTemplate

## The label used to display the currently selected chapter's title.
@onready var desc_title: Label = %DescTitle

## The rich text label used to display the selected chapter's description.
@onready var desc_text: RichTextLabel = %DescText

## The button used to start the game with the selected chapter.
@onready var play_button: Button = %PlayButton

## The button used to return to the previous screen or main menu.
@onready var back_button: Button = %BackButton

## The texture rect used to display the chapter's background image.
@onready var background: TextureRect = %Background


func _ready() -> void:
	active_instance = self
	chapter_button_template.hide()
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)

	for i: int in chapters.size():
		# Fixed static type: Changed Dictionary to ChapterData
		var chapter: ChapterData = chapters[i]
		var item: Control = chapter_button_template.duplicate() as Control
		item.show()

		var btn: Button = item.get_node("Btn") as Button
		var label: Label = item.get_node("ChapterTitle") as Label

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


# --- Catch ESC specifically for this screen ---
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		# This prevents the Main Menu from also receiving the ESC press
		get_viewport().set_input_as_handled()


func _on_chapter_selected(chapter: ChapterData) -> void:
	print("Player selected chapter: ", chapter.chapter_name)
	selected_chapter = chapter
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description
	background.texture = chapter.image


func _on_play_pressed() -> void:
	if selected_chapter:
		print("Player pressed play for chapter: ", selected_chapter.chapter_name)
	else:
		print("Player pressed play but no chapter is selected.")
		
	if selected_chapter and selected_chapter.scene_path != "":
		get_tree().paused = false
		get_tree().change_scene_to_file(selected_chapter.scene_path)
	else:
		push_warning("No scene path assigned to this chapter!")


func _on_back_pressed() -> void:
	print("Player triggered back/cancel action.")
	var parent: Node = get_parent()
	if parent and "main_buttons" in parent:
		parent.main_buttons.show()
		queue_free()
	else:
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_image_gui_input(event: InputEvent, chapter: ChapterData) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			print("Player double-clicked chapter: ", chapter.chapter_name)
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
