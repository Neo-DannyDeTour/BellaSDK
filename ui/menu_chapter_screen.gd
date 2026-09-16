## Screen controller for selecting and launching game chapters.
class_name ChapterScreen
extends Control

## Preloaded loading screen scene to manage background streaming.
const LOADING_SCREEN_SCENE: PackedScene = preload("res://ui/loading_screen_anim.tscn")

## Stores the currently active instance of this screen.
static var active_instance: Control = null

## An array of [ChapterData] resources used to populate the list.
@export var chapters: Array[ChapterData] = []

## Holds the currently selected [ChapterData] to pass to the game.
var selected_chapter: ChapterData = null

## Atomic flag preventing concurrent scene load executions.
var _is_transitioning: bool = false

## The [HBoxContainer] that organizes chapter buttons horizontally.
@onready var chapter_list: HBoxContainer = %ChapterList

## The template container used to clone new chapter buttons.
@onready var chapter_button_template: VBoxContainer = %ChapterButtonTemplate

## The label used to display the currently selected chapter title.
@onready var desc_title: Label = %DescTitle

## The rich text label used to display the chapter description.
@onready var desc_text: RichTextLabel = %DescText

## The button used to start the game with the selected chapter.
@onready var play_button: Button = %PlayButton

## The button used to return to previous menu.
@onready var back_button: Button = %BackButton

## The texture rect used to display the chapter background image.
@onready var background: TextureRect = %Background


## Initializes signals and populates the chapter selection list.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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

	if not chapters.is_empty():
		_on_chapter_selected(chapters[0])


## Cleans up static active instance reference upon scene exit.
func _exit_tree() -> void:
	if active_instance == self:
		active_instance = null


## Intercepts UI cancel actions to handle back navigation safely.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


## Handles selection updates when a chapter is clicked or hovered.
func _on_chapter_selected(chapter: ChapterData) -> void:
	print("ChapterScreen: Selected chapter: ", chapter.chapter_name)
	selected_chapter = chapter
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description
	background.texture = chapter.image


## Selects the chapter card on click.
func _on_chapter_clicked(chapter: ChapterData) -> void:
	print("ChapterScreen: Clicked chapter card: ", chapter.chapter_name)
	_on_chapter_selected(chapter)


## Executes game scene launch logic with strict mutual exclusion.
func _on_play_pressed() -> void:
	if _is_transitioning:
		print("ChapterScreen: Transition underway. Ignoring play press.")
		return

	if not selected_chapter or selected_chapter.scene_path.is_empty():
		push_warning("ChapterScreen: No valid scene path assigned!")
		return

	print("ChapterScreen: Launching chapter: ", selected_chapter.chapter_name)
	_is_transitioning = true
	play_button.disabled = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var parent: Node = get_parent()
	if is_instance_valid(parent) and parent.has_method("prepare_for_level_transition"):
		await parent.call("prepare_for_level_transition")

	var loader: LoadingScreen = LOADING_SCREEN_SCENE.instantiate() as LoadingScreen
	loader.level_scene_path = selected_chapter.scene_path
	get_tree().root.add_child(loader)


## Handles returning to previous menu or restoring parent navigation buttons.
func _on_back_pressed() -> void:
	if _is_transitioning:
		return
	print("ChapterScreen: Navigating back.")
	var parent: Node = get_parent()
	if parent and "main_buttons" in parent:
		parent.main_buttons.show()
		queue_free()
	else:
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")


## Double-click on chapter image immediately executes game launch.
func _on_image_gui_input(event: InputEvent, chapter: ChapterData) -> void:
	if _is_transitioning:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			print("ChapterScreen: Double-clicked chapter: ", chapter.chapter_name)
			_on_chapter_selected(chapter)
			_on_play_pressed()


## Updates background and labels preview on mouse hover.
func _on_chapter_hovered(chapter: ChapterData) -> void:
	print("ChapterScreen: Hovered over chapter: ", chapter.chapter_name)
	background.texture = chapter.image
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description


## Restores preview details back to selected chapter on mouse exit.
func _on_chapter_unhovered() -> void:
	if is_instance_valid(selected_chapter):
		background.texture = selected_chapter.image
		desc_title.text = selected_chapter.chapter_name
		desc_text.text = selected_chapter.description
