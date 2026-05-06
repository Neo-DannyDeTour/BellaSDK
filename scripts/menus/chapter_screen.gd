extends Control

# Drag and drop your .tres ChapterData files into this array in the Inspector
@export var chapters: Array[ChapterData] = []

@onready var chapter_list: HBoxContainer = %ChapterList
@onready var chapter_button_template: VBoxContainer = %ChapterButtonTemplate

@onready var desc_title: Label = %DescTitle
@onready var desc_text: RichTextLabel = %DescText
@onready var play_button: Button = %PlayButton
@onready var back_button: Button = $MarginContainer/VBoxContainer/MainLayout/DetailsPanel/MarginContainer/BottomSplit/ButtonSection/BackButton
@onready var background: TextureRect = %Background

var selected_chapter: ChapterData = null

func _ready() -> void:
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
		
		# ADD THIS: Connect the hover signal
		btn.mouse_entered.connect(_on_chapter_selected.bind(chapter))
		
		chapter_list.add_child(item)
	
	if chapters.size() > 0:
		_on_chapter_selected(chapters[0])

func _on_chapter_selected(chapter: ChapterData) -> void:
	selected_chapter = chapter
	
	# Update the details window
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description
	
	# Update the background
	background.texture = chapter.image

func _on_play_pressed() -> void:
	if selected_chapter and selected_chapter.scene_path != "":
		# We must unpause the tree here, otherwise the new level will load frozen!
		get_tree().paused = false 
		get_tree().change_scene_to_file(selected_chapter.scene_path)
	else:
		push_warning("No scene path assigned to this chapter!")

func _on_back_pressed() -> void:
	var parent := get_parent()
	
	# Check if we were spawned as a child of the Menu script
	if parent and "main_buttons" in parent:
		# Show the Continue / Restart / Options buttons again
		parent.main_buttons.show()
		# Delete this Chapter Screen, revealing the menu underneath
		queue_free() 
	else:
		# Fallback just in case you ever load this scene directly
		get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")

func _on_image_gui_input(event: InputEvent, chapter: ChapterData) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			# 1. Ensure the UI registers it as the selected chapter
			_on_chapter_selected(chapter)
			
			# 2. Instantly trigger the play function
			_on_play_pressed()

func _on_chapter_hovered(chapter: ChapterData) -> void:
	# 1. Update the background image (the shader handles the rest)
	background.texture = chapter.image
	
	# 2. Update the text to preview the hovered chapter
	desc_title.text = chapter.chapter_name
	desc_text.text = chapter.description

func _on_chapter_unhovered() -> void:
	# When the mouse leaves the button, revert the UI back to the selected chapter
	if selected_chapter:
		background.texture = selected_chapter.image
		desc_title.text = selected_chapter.chapter_name
		desc_text.text = selected_chapter.description
