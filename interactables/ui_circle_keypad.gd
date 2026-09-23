## 2D timing minigame matching circles via WASD with stages and health rewards.
class_name UICircleTimingKeypad
extends Control

## Emitted when the entire puzzle sequence is successfully cleared.
@warning_ignore("unused_signal")
signal code_entered(code: String)

## Emitted when a key input is processed during the challenge.
@warning_ignore("unused_signal")
signal button_clicked(button_name: String)

## Emitted to request a SubViewport redraw.
@warning_ignore("unused_signal")
signal display_updated

## Emitted on complete failure lockout with damage dealt.
@warning_ignore("unused_signal")
signal puzzle_failed(damage: int)

## Base directory for Kenney input prompt icon assets.
const ICON_BASE_PATH: String = "res://assets/kenney_input-prompts_1.5/Keyboard & Mouse/Default/"

## Number of successful circle matches required to fully solve the puzzle.
@export var required_stages: int = 3

## Maximum misses allowed before reset. Set <= 0 for infinite tries.
@export var max_tries: int = 5

## Damage dealt to the player when all tries are exhausted.
@export var fail_damage: int = 20

## Health restored to the player for completing without a single miss.
@export var perfect_heal_amount: int = 25

## Pixel radius tolerance allowed between circles for a valid match.
@export var hit_tolerance: float = 14.0

## Duration in seconds of one full circle expansion and contraction cycle.
@export var cycle_duration: float = 2.4

## Border color of the fixed target circle.
@export var target_color: Color = Color.WHITE

## Border color of the pulsing animated circle.
@export var pulse_color: Color = Color.DEEP_SKY_BLUE

## Remaining attempts before lockout reset occurs.
var tries_remaining: int = 5

## Number of successful matches achieved in current attempt run.
var current_stage: int = 0

## Tracks if player completed all stages with zero misses.
var is_flawless: bool = true

## Controls whether the puzzle is actively processing frames and inputs.
var is_active: bool = false

## Radius in pixels of the fixed target circle.
var target_radius: float = 80.0

## Real-time animated radius of the pulsating circle.
var current_radius: float = 25.0

## Minimum pulsating circle radius in pixels.
var min_radius: float = 30.0

## Maximum pulsating circle radius in pixels.
var max_radius: float = 180.0

## Accumulated frame time within the active pulse cycle.
var cycle_timer: float = 0.0

## Active WASD key prompt string required from the player.
var active_key: String = "W"

## Prevents input evaluation during lockout or completion feedback states.
var is_locked: bool = false

## Cached reference to the interacting character for healing and damage.
var linked_player: CharacterBody3D = null

## Supported key prompt candidates.
var key_candidates: Array[String] = ["W", "A", "S", "D"]

## Overlay canvas responsible for drawing the timing circles.
@onready var circle_canvas: Control = $CircleCanvas

## TextureRect displaying Kenney WASD icon.
@onready var prompt_icon: TextureRect = $CenterContainer/PromptIcon

## Fallback label displaying plain key letters.
@onready var prompt_label: Label = $CenterContainer/PromptLabel

## Feedback status label displaying progress and tries.
@onready var status_label: Label = $StatusLabel


## Initializes canvas draw signal and disables processing until activated.
func _ready() -> void:
	print("UICircleTimingKeypad: Initializing timing minigame in dormant state.")
	set_process(false)
	if is_instance_valid(circle_canvas):
		circle_canvas.draw.connect(_on_canvas_draw)
	_hide_challenge_elements()


## Advances circle animation and registers timeouts when active.
## [param delta] Frame delta time in seconds.
func _process(delta: float) -> void:
	if not is_active or is_locked:
		return

	cycle_timer += delta
	if cycle_timer >= cycle_duration:
		print("UICircleTimingKeypad: Full cycle elapsed without matching key.")
		cycle_timer = 0.0
		_handle_failure()
		return

	var progress: float = cycle_timer / cycle_duration
	var wave: float = sin(progress * PI)
	current_radius = lerpf(min_radius, max_radius, wave)

	if is_instance_valid(circle_canvas):
		circle_canvas.queue_redraw()
	display_updated.emit()


## Draws the circles on the dedicated canvas when active.
func _on_canvas_draw() -> void:
	if not is_active:
		return
	var center: Vector2 = circle_canvas.size * 0.5
	circle_canvas.draw_arc(center, target_radius, 0.0, TAU, 64, target_color, 4.0, true)
	circle_canvas.draw_arc(center, current_radius, 0.0, TAU, 64, pulse_color, 3.0, true)


## Activates the minigame when the player interacts with the terminal.
func start_puzzle() -> void:
	print("UICircleTimingKeypad: Activating minigame loop.")
	is_active = true
	is_flawless = true
	current_stage = 0
	tries_remaining = max_tries
	is_locked = false
	cycle_timer = 0.0
	set_process(true)
	_pick_random_challenge()
	_update_status_ui()


## Halts puzzle animation and hides dynamic visuals on terminal exit.
func stop_puzzle() -> void:
	print("UICircleTimingKeypad: Deactivating minigame loop.")
	is_active = false
	set_process(false)
	_hide_challenge_elements()
	if is_instance_valid(circle_canvas):
		circle_canvas.queue_redraw()
	display_updated.emit()


## Caches interacting player reference for healing and damage routing.
## [param player] Character controller node.
func set_player_reference(player: CharacterBody3D) -> void:
	print("UICircleTimingKeypad: Player reference bound -> ", player)
	linked_player = player


## Generates a new target radius and resolves Kenney icon or label fallback.
func _pick_random_challenge() -> void:
	target_radius = randf_range(min_radius + 25.0, max_radius - 25.0)
	active_key = key_candidates.pick_random()
	print("UICircleTimingKeypad: Target: ", target_radius, " Key: ", active_key)

	var key_char: String = active_key.to_lower()
	var candidates: Array[String] = [
		ICON_BASE_PATH + "keyboard_%s.png" % key_char,
		ICON_BASE_PATH + "keyboard_%s_outline.png" % key_char,
		ICON_BASE_PATH + "Keyboard/keyboard_%s.png" % key_char,
		ICON_BASE_PATH + "Keyboard/keyboard_%s_outline.png" % key_char
	]

	var found_tex: Texture2D = null
	for path: String in candidates:
		if ResourceLoader.exists(path):
			found_tex = load(path) as Texture2D
			break

	if found_tex != null:
		prompt_icon.texture = found_tex
		prompt_icon.visible = true
		prompt_label.visible = false
	else:
		prompt_label.text = active_key
		prompt_label.visible = true
		prompt_icon.visible = false

	display_updated.emit()


## Evaluates incoming key presses against circle radius tolerance and stage logic.
## [param key_name] Uppercase key identifier.
func handle_key_input(key_name: String) -> void:
	if not is_active or is_locked:
		return

	var pressed_key: String = key_name.to_upper()
	print("UICircleTimingKeypad: Key received -> ", pressed_key)
	button_clicked.emit(pressed_key)

	var diff: float = absf(current_radius - target_radius)
	var is_radius_matched: bool = diff <= hit_tolerance
	var is_key_matched: bool = pressed_key == active_key

	if is_radius_matched and is_key_matched:
		current_stage += 1
		print("UICircleTimingKeypad: Stage cleared -> ", current_stage, "/", required_stages)
		if current_stage >= required_stages:
			_complete_puzzle()
		else:
			cycle_timer = 0.0
			_pick_random_challenge()
			_update_status_ui()
	else:
		print("UICircleTimingKeypad: Failed match. Diff: ", diff)
		is_flawless = false
		_handle_failure()


## Finalizes puzzle completion, awards flawless healing, and emits solve signal.
func _complete_puzzle() -> void:
	print("UICircleTimingKeypad: All stages completed.")
	is_locked = true
	set_process(false)

	if is_flawless and perfect_heal_amount > 0:
		print("UICircleTimingKeypad: Flawless run! Healing player: ", perfect_heal_amount)
		if is_instance_valid(linked_player) and linked_player.has_method("heal"):
			linked_player.call("heal", perfect_heal_amount)
		status_label.text = "PERFECT OVERRIDE! (+%d HP)" % perfect_heal_amount
		status_label.add_theme_color_override("font_color", Color.CYAN)
	else:
		status_label.text = "SYSTEM OVERRIDE ACCEPTED"
		status_label.add_theme_color_override("font_color", Color.SPRING_GREEN)

	_hide_challenge_elements()
	if is_instance_valid(circle_canvas):
		circle_canvas.queue_redraw()
	display_updated.emit()
	code_entered.emit(active_key)


## Deducts attempts, resets sequence on mistake, and triggers failure on zero tries.
func _handle_failure() -> void:
	current_stage = 0
	if max_tries > 0:
		tries_remaining -= 1
		print("UICircleTimingKeypad: Attempts left -> ", tries_remaining)

	if max_tries > 0 and tries_remaining <= 0:
		print("UICircleTimingKeypad: Attempts exhausted. Triggering overload.")
		is_locked = true
		set_process(false)
		display_result(false)

		if is_instance_valid(linked_player) and linked_player.has_method("take_damage"):
			print("UICircleTimingKeypad: Applying overload damage: ", fail_damage)
			linked_player.call("take_damage", fail_damage)

		puzzle_failed.emit(fail_damage)
		get_tree().create_timer(1.6).timeout.connect(start_puzzle)
	else:
		cycle_timer = 0.0
		_update_status_ui()
		_pick_random_challenge()


## Hides WASD prompt icons and letters.
func _hide_challenge_elements() -> void:
	prompt_icon.visible = false
	prompt_label.visible = false


## Updates status label with stage progression and remaining attempts.
func _update_status_ui() -> void:
	var tries_text: String = "INF" if max_tries <= 0 else str(tries_remaining)
	status_label.text = "STAGE: %d/%d  |  TRIES: %s" % [current_stage, required_stages, tries_text]
	status_label.remove_theme_color_override("font_color")
	display_updated.emit()


## Displays failure lockout styling on the status label.
## [param is_correct] Whether attempt solved puzzle.
func display_result(is_correct: bool) -> void:
	print("UICircleTimingKeypad: Displaying validation result -> ", is_correct)
	if not is_correct:
		status_label.text = "OVERLOAD DETECTED"
		status_label.add_theme_color_override("font_color", Color.ORANGE_RED)
	display_updated.emit()
