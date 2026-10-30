@tool
## Physics trigger volume initiating a cinematic chapter title card upon player entry.
## Hooks into [Events] singleton and configures an [EditorTriggerVisualizer] debug gizmo.
class_name EnvChapterTrigger
extends BaseTriggerArea3D

@export_category("Chapter Settings")
## The exact string to display on the screen when the title card animates in.
@export var chapter_name: String = "Chapter 1"

## The base color of the chapter text.
@export var text_color: Color = Color.WHITE

## The preset animation style passed to the UI handler.
@export var animation_style: Events.ChapterAnimStyle = Events.ChapterAnimStyle.SIMPLE

## How long in seconds the chapter title remains visible on screen.
@export var display_duration: float = 5.0

@export_category("Randomization")
## If true, overrides the inspector settings with random effects on entry.
@export var play_random_effects: bool = false


## Initializes default trigger text label for editor visualizer.
func _ready() -> void:
	if trigger_text == "TRIGGER":
		trigger_text = "CHAPTER TRIGGER"
	super._ready()


## Validates player presence and fires the global chapter event signal.
func _on_player_entered(_player_node: Node3D) -> void:
	_apply_random_effects_if_enabled()
	print(
		"EnvChapterTrigger: Player entered. Emitting chapter '",
		chapter_name,
		"' with style ID ",
		animation_style
	)
	Events.chapter_triggered.emit(chapter_name, int(animation_style), display_duration, text_color)


## Applies randomized styling parameters for demonstration scenarios.
func _apply_random_effects_if_enabled() -> void:
	if not play_random_effects:
		return

	print("EnvChapterTrigger: _apply_random_effects_if_enabled() called.")
	var count: int = Events.ChapterAnimStyle.size()
	var random_index: int = randi() % count
	animation_style = random_index as Events.ChapterAnimStyle
	text_color = Color(randf(), randf(), randf(), 1.0)
	display_duration = randf_range(3.0, 7.0)

	print(
		"EnvChapterTrigger: Random effects generated -> Style: ",
		animation_style,
		", Color: ",
		text_color,
		", Duration: ",
		display_duration
	)
