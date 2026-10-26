## Manages layered 3D-perspective dogtags in the top-center HUD with timed auto-dismissal.
class_name TagNotification
extends Control

## Textures registry mapping weapon tags to UI assets.
const TAG_TEXTURES: Dictionary[String, Texture2D] = {
	"shotgun": preload("res://assets/weapons_ui_icons/tag_shotgun.png"),
	"revolver": preload("res://assets/weapons_ui_icons/tag_revolver.png"),
	"smoke_grenade": preload("res://assets/weapons_ui_icons/tag_smoke_grenade.png"),
}

## Horizontal spacing between background dogtags in pixels.
const TAG_SPREAD_X: float = 48.0

## Vertical drop position for the active foreground dogtag.
const ACTIVE_Y: float = 65.0

## Resting Y position for background stacked tags.
const BACKGROUND_Y: float = 40.0

## Duration in seconds tags remain displayed before retracting off-screen.
const DISPLAY_DURATION: float = 2.5

## Dictionary holding spawned [TextureRect] instances keyed by weapon tag.
var _spawned_tags: Dictionary[String, TextureRect] = {}

## Array tracking the display order of collected weapon tags.
var _collected_order: Array[String] = []

## String tag of the currently equipped weapon.
var _active_weapon: String = ""

## Active tween coordinating entrance and dismissal animations.
var _stack_tween: Tween = null

## Timer managing the auto-retract sequence after display duration elapses.
var _dismiss_timer: Timer = null


## Initializes tag overlay and connects global weapon event signals.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	print("TagNotification: Initializing stacked dogtag HUD.")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child: Node in get_children():
		child.queue_free()

	_dismiss_timer = Timer.new()
	_dismiss_timer.name = "DismissTimer"
	_dismiss_timer.one_shot = true
	_dismiss_timer.timeout.connect(_on_dismiss_timeout)
	add_child(_dismiss_timer)

	if not Events.weapon_tag_displayed.is_connected(_on_weapon_collected):
		Events.weapon_tag_displayed.connect(_on_weapon_collected)
	if not Events.active_weapon_changed.is_connected(_on_weapon_swapped):
		Events.active_weapon_changed.connect(_on_weapon_swapped)


## Disconnects global signals and kills active tweens when removed from the tree.
func _exit_tree() -> void:
	if Events.weapon_tag_displayed.is_connected(_on_weapon_collected):
		Events.weapon_tag_displayed.disconnect(_on_weapon_collected)
	if Events.active_weapon_changed.is_connected(_on_weapon_swapped):
		Events.active_weapon_changed.disconnect(_on_weapon_swapped)
	Utilities.safe_kill_tween(_stack_tween)
	if is_instance_valid(_dismiss_timer):
		_dismiss_timer.stop()


## Handles weapon pickup, registering valid dogtag textures and rearranging the stack.
func _on_weapon_collected(weapon_id: String) -> void:
	if not TAG_TEXTURES.has(weapon_id):
		return
	print("TagNotification: Weapon tag registered -> ", weapon_id)
	if not _collected_order.has(weapon_id):
		_collected_order.append(weapon_id)
		_create_tag_node(weapon_id)

	_active_weapon = weapon_id
	_rearrange_stack(true)
	_start_dismiss_timer()


## Rearranges tags on hotkey weapon swap without bounce drop animation.
func _on_weapon_swapped(weapon_id: String) -> void:
	if not TAG_TEXTURES.has(weapon_id):
		return
	print("TagNotification: Weapon swapped to -> ", weapon_id)
	if not _collected_order.has(weapon_id):
		return
	_active_weapon = weapon_id
	_rearrange_stack(false)
	_start_dismiss_timer()


## Starts or restarts the auto-dismiss timer for the active weapon tag.
func _start_dismiss_timer() -> void:
	if not is_inside_tree() or not is_instance_valid(_dismiss_timer):
		return
	print("TagNotification: Starting dismissal timer (", DISPLAY_DURATION, "s).")
	_dismiss_timer.start(DISPLAY_DURATION)


## Triggers stack retraction when display duration elapses without weapon input.
func _on_dismiss_timeout() -> void:
	if is_inside_tree():
		_dismiss_stack()


## Retracts all active dogtag nodes upwards past the top screen boundary.
func _dismiss_stack() -> void:
	Utilities.safe_kill_tween(_stack_tween)
	if is_instance_valid(_dismiss_timer):
		_dismiss_timer.stop()
	if _spawned_tags.is_empty() or not is_inside_tree():
		return

	print("TagNotification: Dismissing dogtags off-screen.")
	var has_valid_rect: bool = false
	for weapon_id: String in _collected_order:
		var candidate: TextureRect = _spawned_tags.get(weapon_id, null)
		if is_instance_valid(candidate):
			has_valid_rect = true
			break

	if not has_valid_rect:
		return

	_stack_tween = create_tween().set_parallel(true)
	for weapon_id: String in _collected_order:
		var rect: TextureRect = _spawned_tags.get(weapon_id, null)
		if not is_instance_valid(rect):
			continue

		var offscreen_y: float = -rect.size.y - 60.0
		(
			_stack_tween
			. tween_property(rect, "position:y", offscreen_y, 0.4)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
		_stack_tween.tween_property(rect, "modulate:a", 0.0, 0.35)


## Spawns and configures a [TextureRect] node for a registered weapon tag.
func _create_tag_node(weapon_id: String) -> void:
	var tex: Texture2D = TAG_TEXTURES.get(weapon_id, null)
	if not is_instance_valid(tex):
		return

	var rect: TextureRect = TextureRect.new()
	rect.name = "Tag_" + weapon_id
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(75.0, 130.0)
	rect.size = rect.custom_minimum_size
	rect.pivot_offset = rect.size * 0.5
	rect.position = Vector2((size.x - rect.size.x) * 0.5, -rect.size.y - 60.0)
	rect.modulate.a = 0.0
	add_child(rect)

	_spawned_tags[weapon_id] = rect


## Animates the tag hierarchy so the active weapon is foregrounded and others layer behind.
func _rearrange_stack(is_pickup_drop: bool) -> void:
	Utilities.safe_kill_tween(_stack_tween)
	if _spawned_tags.is_empty() or not is_inside_tree():
		return

	var has_valid_rect: bool = false
	for weapon_id: String in _collected_order:
		var candidate: TextureRect = _spawned_tags.get(weapon_id, null)
		if is_instance_valid(candidate):
			has_valid_rect = true
			break

	if not has_valid_rect:
		return

	var screen_center_x: float = size.x * 0.5
	var bg_index: int = 0
	_stack_tween = create_tween().set_parallel(true)

	for weapon_id: String in _collected_order:
		var rect: TextureRect = _spawned_tags.get(weapon_id, null)
		if not is_instance_valid(rect):
			continue

		var is_active: bool = weapon_id == _active_weapon
		if is_active:
			move_child(rect, get_child_count() - 1)
			var target_pos: Vector2 = Vector2(screen_center_x - (rect.size.x * 0.5), ACTIVE_Y)

			if is_pickup_drop or rect.position.y < 0.0:
				rect.position.y = -rect.size.y - 20.0
				rect.rotation_degrees = 0.0
				(
					_stack_tween
					. tween_property(rect, "position", target_pos, 0.6)
					. set_trans(Tween.TRANS_BACK)
					. set_ease(Tween.EASE_OUT)
				)
			else:
				(
					_stack_tween
					. tween_property(rect, "position", target_pos, 0.25)
					. set_trans(Tween.TRANS_QUAD)
					. set_ease(Tween.EASE_OUT)
				)

			_stack_tween.tween_property(rect, "scale", Vector2.ONE, 0.3)
			_stack_tween.tween_property(rect, "rotation_degrees", 12.0, 0.4)
			_stack_tween.tween_property(rect, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)
		else:
			var offset_multiplier: float = -1.0 if bg_index % 2 == 0 else 1.0
			var side_dist: float = (floorf(float(bg_index) / 2.0) + 1.0) * TAG_SPREAD_X
			var bg_x: float = (
				screen_center_x - (rect.size.x * 0.5) + (side_dist * offset_multiplier)
			)

			var bg_pos: Vector2 = Vector2(bg_x, BACKGROUND_Y)
			move_child(rect, 0)

			(
				_stack_tween
				. tween_property(rect, "position", bg_pos, 0.35)
				. set_trans(Tween.TRANS_QUAD)
				. set_ease(Tween.EASE_OUT)
			)
			_stack_tween.tween_property(rect, "scale", Vector2(0.78, 0.78), 0.35)
			_stack_tween.tween_property(rect, "rotation_degrees", -6.0 * offset_multiplier, 0.35)
			_stack_tween.tween_property(rect, "modulate", Color(0.4, 0.4, 0.45, 0.55), 0.35)
			bg_index += 1
