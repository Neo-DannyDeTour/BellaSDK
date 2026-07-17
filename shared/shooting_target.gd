extends StaticBody3D
class_name ShootingTarget

@export var target_health: int = 100
@export var can_player_hit: bool = true
@export var hide_in_game: bool = false
@export var despawn_time: float = 0.5

@onready var health_component: Node = $HealthComponent
@onready var icon_sprite: Sprite3D = $Sprite3D

var _jiggle_tween: Tween
var _default_collision_layer: int
var _default_collision_mask: int


func _ready() -> void:
	# WARNING: Removed add_to_group("player"). Targets should NOT be in the player group!

	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask

	if not Engine.is_editor_hint() and hide_in_game:
		if icon_sprite != null:
			icon_sprite.visible = false

	if health_component != null:
		health_component.max_health = target_health
		health_component.current_health = target_health
		health_component.died.connect(_on_target_died)

	if not can_player_hit:
		set_collision_layer_value(1, false)


func take_damage(amount: int, _pos: Vector3 = Vector3.ZERO, _dir: Vector3 = Vector3.ZERO) -> void:
	print("ShootingTarget: take_damage() - Target hit for ", amount, " damage!")
	_play_jiggle_animation()
	if health_component != null and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


func _play_jiggle_animation() -> void:
	print("ShootingTarget: _play_jiggle_animation() - Shaking sprite.")
	if icon_sprite == null or (hide_in_game and not Engine.is_editor_hint()):
		return

	if _jiggle_tween and _jiggle_tween.is_valid():
		_jiggle_tween.kill()

	icon_sprite.position = Vector3.ZERO
	_jiggle_tween = create_tween()

	for i: int in range(4):
		var rand_x: float = randf_range(-0.15, 0.15)
		var rand_y: float = randf_range(-0.15, 0.15)
		var offset: Vector3 = Vector3(rand_x, rand_y, 0.0)
		_jiggle_tween.tween_property(icon_sprite, "position", offset, 0.04)

	_jiggle_tween.tween_property(icon_sprite, "position", Vector3.ZERO, 0.04)


func _on_target_died() -> void:
	print("ShootingTarget: _on_target_died() - Target dead, delegating pooling to HealthComponent.")
	if icon_sprite != null:
		icon_sprite.hide()

	collision_layer = 0
	collision_mask = 0
	# Removed queue_free() logic here so TargetVolume can safely re-use the node.


func reset() -> void:
	print("ShootingTarget: reset() - Restoring target state.")
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask

	if icon_sprite != null and not (hide_in_game and not Engine.is_editor_hint()):
		icon_sprite.show()

	if health_component != null and health_component.has_method("reset"):
		health_component.reset()
