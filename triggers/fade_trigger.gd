@tool
## Trigger volume initiating camera transition sequences via [ScreenEffectsCore].
class_name FadeTrigger
extends BaseTriggerArea3D

@export_group("Fade Timings")
## Duration in seconds for the screen to fade to the target color.
@export var fade_in_duration: float = 1.0

## Duration in seconds the screen remains fully faded before returning.
@export var hold_duration: float = 0.5

## Duration in seconds for the screen to return to normal.
@export var fade_out_duration: float = 1.0

@export_group("Visual Effects")
## The target color the screen will fade towards.
@export var fade_color: Color = Color.BLACK

## Enables a blur effect during the fade transition.
@export var use_blur: bool = true

## The maximum intensity of the blur effect.
@export var max_blur: float = 2.5

## Enables a blinking effect during the transition.
@export var use_blink: bool = false

## The number of times the screen blinks during the fade sequence.
@export_range(1, 10) var blink_count: int = 1


## Initializes default trigger text label for editor visualizer.
func _ready() -> void:
	if trigger_text == "TRIGGER":
		trigger_text = "FADE TRIGGER"
	super._ready()


## Dispatches screen transition parameters to centralized [ScreenEffectsCore].
func _on_player_entered(player_node: Node3D) -> void:
	print("FadeTrigger: Activated by: ", player_node.name, ". Starting screen fade sequence.")
	_dispatch_fade_sequence()


## Dispatches screen transition parameters to centralized [ScreenEffectsCore].
func _dispatch_fade_sequence() -> void:
	print("FadeTrigger: Dispatching transition payload to ScreenEffectsCore.")
	if Events.has_signal(&"screen_fade_requested"):
		Events.screen_fade_requested.emit(
			fade_color,
			fade_in_duration,
			hold_duration,
			fade_out_duration,
			use_blur,
			max_blur,
			use_blink,
			blink_count
		)
