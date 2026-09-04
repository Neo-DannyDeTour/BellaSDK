## Screen controller for selecting and launching game chapters.
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


## Initializes UI signals, populates the chapter selection list, and hides template.
func _ready() -> void:
	active_instance = self
	chapter_button_template.hide()
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)

	for i: int in chapters.size():
		var chapter: ChapterData = chapters[i]
		var item: Control = chapter_button_template.duplicate() as Control
		item.show()

		var btn: HorrorButton = item.get_node("HorrorButton") as HorrorButton
		var label: Label = item.get_node("ChapterTitle") as Label

		label.text = str(i + 1) + ". " + chapter.chapter_name
		btn.setup_chapter_card(chapter)

		btn.mouse_entered.connect(_on_chapter_hovered.bind(chapter))
		btn.mouse_exited.connect(_on_chapter_unhovered)
		btn.pressed.connect(_on_chapter_clicked.bind(chapter))
		btn.gui_input.connect(_on_image_gui_input.bind(chapter))

		chapter_list.add_child(item)

	if chapters.size() > 0:
		_on_chapter_selected(chapters[0])


## Cleans up static active instance reference upon scene exit.
func _exit_tree() -> void:
	if active_instance == self:
		active_instance = null


## Intercepts UI cancel (ESC) actions to handle back navigation safely.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


## Handles selection updates when a chapter is permanently chosen or clicked.
func _on_chapter_selected(chapter: ChapterData) -> void:
	print("Player selected chapter: ", chapter.chapter_name)
	selected_chapter = chapter
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description
	background.texture = chapter.image


## Immediately selects and launches the chapter when its button is clicked.
func _on_chapter_clicked(chapter: ChapterData) -> void:
	print("Player clicked chapter button: ", chapter.chapter_name)
	_on_chapter_selected(chapter)
	_on_play_pressed()


## Executes game scene launch logic for the currently selected chapter.
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


## Handles returning to previous menu or restoring parent navigation buttons.
func _on_back_pressed() -> void:
	print("Player triggered back/cancel action.")
	var parent: Node = get_parent()
	if parent and "main_buttons" in parent:
		parent.main_buttons.show()
		queue_free()
	else:
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")


## Handles double-click navigation triggers directly on the chapter image.
func _on_image_gui_input(event: InputEvent, chapter: ChapterData) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			print("Player double-clicked chapter: ", chapter.chapter_name)
			_on_chapter_selected(chapter)
			_on_play_pressed()


## Updates background and labels preview on mouse hover.
func _on_chapter_hovered(chapter: ChapterData) -> void:
	print("Player hovered over chapter: ", chapter.chapter_name)
	background.texture = chapter.image
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description


## Restores background and preview details back to selected chapter on mouse exit.
func _on_chapter_unhovered() -> void:
	if selected_chapter:
		background.texture = selected_chapter.image
		desc_title.text = selected_chapter.chapter_name
		desc_text.text = selected_chapter.description
