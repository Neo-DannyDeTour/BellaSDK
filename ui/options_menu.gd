extends Control
class_name OptionsRouter

signal back_requested

@onready var video_panel: Panel = %VideoOptionsPanel
@onready var audio_panel: Panel = %AudioPanel
@onready var gameplay_panel: Panel = %GameplayPanel
@onready var controls_panel: Panel = %ControlsPanel
@onready var accessibility_panel: Panel = %AccessibilityPanel

@onready var video_button: Button = %VideoButton
@onready var audio_button: Button = %AudioButton
@onready var gameplay_button: Button = %GameplayButton
@onready var controls_button: Button = %ControlsButton
@onready var accessibility_button: Button = %AccessibilityButton
@onready var back_button: Button = %BackButton

func _ready() -> void:
	print("UI: Options routing system initialized.")
	
	video_button.pressed.connect(_on_tab_pressed.bind(video_panel))
	audio_button.pressed.connect(_on_tab_pressed.bind(audio_panel))
	gameplay_button.pressed.connect(_on_tab_pressed.bind(gameplay_panel))
	controls_button.pressed.connect(_on_tab_pressed.bind(controls_panel))
	accessibility_button.pressed.connect(_on_tab_pressed.bind(accessibility_panel))
	
	back_button.pressed.connect(func() -> void: back_requested.emit())
	
	# Default to showing the Video panel first
	_on_tab_pressed(video_panel)

func _on_tab_pressed(active_panel: Panel) -> void:
	print("Player swapped options tab to: ", active_panel.name)
	
	video_panel.visible = (active_panel == video_panel)
	audio_panel.visible = (active_panel == audio_panel)
	gameplay_panel.visible = (active_panel == gameplay_panel)
	controls_panel.visible = (active_panel == controls_panel)
	accessibility_panel.visible = (active_panel == accessibility_panel)
