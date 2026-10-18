## Target dummy actor managed by target volumes for weapon testing.
class_name ShootingTarget
extends StaticBody3D

## Total structural hit points assigned to this target entity.
@export var target_health: int = 100

## Whether direct player weapons and projectiles can damage this target.
@export var can_player_hit: bool = true

## Hides the visual sprite icon during normal gameplay if enabled.
@export var hide_in_game: bool = false

## Time in seconds before recycling or hiding after taking fatal damage.
@export var despawn_time: float = 0.5

## The [HealthComponent] instance managing life points and death events.
@export var health_component: HealthComponent

## The [FactionComponent] providing team affiliation for hostile targeting.
@export var faction_component: FactionComponent

## Visual 2D sprite icon representing the target in 3D space.
@export var icon_sprite: Sprite3D

## Active tween handling jiggle animations upon taking damage.
var _jiggle_tween: Tween

## Cached default collision layer restored during pool resets.
var _default_collision_layer: int

## Cached default collision mask restored during pool resets.
var _default_collision_mask: int


## Initializes collision layers, assigns factions, and connects death signals.
func _ready() -> void:
	print("ShootingTarget: Initializing target dummy: ", name)
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask

	if health_component == null:
		var found_health: Node = NodeQuery.find_first_child_of_type(self, HealthComponent)
		if found_health is HealthComponent:
			health_component = found_health as HealthComponent

	if faction_component == null:
		var found_faction: Node = NodeQuery.find_first_child_of_type(self, FactionComponent)
		if found_faction is FactionComponent:
			faction_component = found_faction as FactionComponent
		else:
			faction_component = FactionComponent.new()
			faction_component.name = "FactionComponent"
			faction_component.faction = Types.Faction.TARGET
			faction_component.hostile_mask = 0
			add_child(faction_component)
	else:
		faction_component.set_faction(Types.Faction.TARGET)

	if icon_sprite == null:
		var found_sprite: Node = NodeQuery.find_first_child_of_type(self, Sprite3D)
		if found_sprite is Sprite3D:
			icon_sprite = found_sprite as Sprite3D

	if not Engine.is_editor_hint() and hide_in_game and icon_sprite != null:
		icon_sprite.visible = false

	if health_component != null:
		health_component.max_health = target_health
		health_component.current_health = target_health
		health_component.died.connect(_on_target_died)

	if not can_player_hit:
		collision_layer &= ~CollisionLayers.MASK_ENVIRONMENT


## Inflicts damage, triggers jiggle feedback, and delegates to [HealthComponent].
func take_damage(amount: int, _pos: Vector3 = Vector3.ZERO, _dir: Vector3 = Vector3.ZERO) -> void:
	print("ShootingTarget: Target hit for ", amount, " damage!")
	_play_jiggle_animation()
	if is_instance_valid(health_component):
		health_component.take_damage(amount)


## Shakes sprite anchor slightly to provide visual hit feedback.
func _play_jiggle_animation() -> void:
	print("ShootingTarget: Playing hit shake animation.")
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


## Hides visual mesh and removes collision flags when killed.
func _on_target_died() -> void:
	print("ShootingTarget: Target dead, disabling collision and visuals.")
	if icon_sprite != null:
		icon_sprite.hide()

	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_NONE


## Restores initial collision flags, health pool, and visual visibility.
func reset() -> void:
	print("ShootingTarget: Resetting target state for pool reuse.")
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask

	if icon_sprite != null and not (hide_in_game and not Engine.is_editor_hint()):
		icon_sprite.show()

	if is_instance_valid(health_component):
		health_component.reset()
