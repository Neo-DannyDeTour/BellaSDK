## Manages animated weapon dogtag drop notifications in the top center HUD.
class_name TagNotification
extends Control

## Preloaded shotgun dogtag texture resource.
const SHOTGUN_TAG_TEX: Texture2D = preload("res://assets/weapons_ui_icons/tag_shotgun.png")

## Vertical distance in pixels the tag drops into view.
const DROP_OFFSET_Y: float = 80.0

## Target resting tilt angle in degrees for the dogtag.
const TARGET_ROTATION_DEG: float = 15.0

## Total seconds the tag remains visible on screen.
const DISPLAY_DURATION: float = 2.2

## TextureRect rendering the active weapon tag graphic.
@onready var tag_rect: TextureRect = $TagRect

## Active Tween instance orchestrating fall and sway animations.
var _active_tween: Tween = null


## Initializes node properties and connects event bus signals.
func _ready() -> void:
	print("TagNotification: Initializing weapon tag overlay.")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0

	if is_instance_valid(tag_rect):
		tag_rect.pivot_offset = tag_rect.size * 0.5
		tag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not Events.weapon_tag_displayed.is_connected(_on_weapon_tag_displayed):
		Events.weapon_tag_displayed.connect(_on_weapon_tag_displayed)


## Routes received weapon pickup events to the drop animation pipeline.
## [param weapon_id] String identifier of the collected weapon.
func _on_weapon_tag_displayed(weapon_id: String) -> void:
	print("TagNotification: Displaying tag for weapon -> ", weapon_id)
	if weapon_id == "shotgun":
		show_tag(SHOTGUN_TAG_TEX)


## Triggers falling sequence with rotational tilt and perspective squash.
## [param tag_texture] The [Texture2D] graphic to assign and animate.
func show_tag(tag_texture: Texture2D) -> void:
	if not is_instance_valid(tag_rect) or tag_texture == null:
		return

	print("TagNotification: Starting tag animation sequence.")
	tag_rect.texture = tag_texture
	tag_rect.pivot_offset = tag_rect.size * 0.5

	if is_instance_valid(_active_tween) and _active_tween.is_valid():
		_active_tween.kill()

	# Start above top screen boundary with neutral rotation and flat projection
	tag_rect.position.y = -tag_rect.size.y - 20.0
	tag_rect.rotation_degrees = 0.0
	tag_rect.scale = Vector2(1.0, 1.0)
	modulate.a = 1.0

	var target_y: float = DROP_OFFSET_Y
	var cos_tilt: float = cos(deg_to_rad(TARGET_ROTATION_DEG))

	_active_tween = create_tween().set_parallel(true)

	# Falling motion with elastic settling bounce
	(
		_active_tween
		. tween_property(tag_rect, "position:y", target_y, 0.65)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)

	# 15-degree roll tilt
	(
		_active_tween
		. tween_property(tag_rect, "rotation_degrees", TARGET_ROTATION_DEG, 0.55)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	# Pseudo-3D yaw compression: horizontal scale shrinks proportionally to tilt angle
	(
		_active_tween
		. tween_property(tag_rect, "scale:x", cos_tilt * 0.9, 0.55)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	# Subtle 3D swing recoil
	(
		_active_tween
		. chain()
		. tween_property(tag_rect, "rotation_degrees", TARGET_ROTATION_DEG - 3.0, 0.4)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	(
		_active_tween
		. parallel()
		. tween_property(tag_rect, "scale:x", cos_tilt, 0.4)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	# Settle hold and fade out
	_active_tween.chain().tween_interval(DISPLAY_DURATION)
	(
		_active_tween
		. chain()
		. tween_property(self, "modulate:a", 0.0, 0.35)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
