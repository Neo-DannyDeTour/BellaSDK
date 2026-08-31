## Manages player status indicators including health hearts,
## debuffs, surface states, and collected keycards.
class_name PlayerStatusHUD
extends MarginContainer

## Slices of the heart textures for varying health states.
@export var hearts_atlas: Texture2D

## Maps keycard IDs to their respective inventory icon textures.
@export var card_textures: Dictionary[StringName, Texture2D] = {}

## Container arranging the health heart icons horizontally.
@onready var hearts_container: HBoxContainer = $VBoxContainer/HeartsContainer

## Container arranging collected keycard icons horizontally.
@onready var keycards_container: HBoxContainer = $VBoxContainer/KeycardsContainer

## Container managing the layout of the sprint debuff UI.
@onready var sprint_debuff_container: Control = $VBoxContainer/SprintDebuff

## Texture progress bar layered over the sprint debuff icon.
@onready var sprint_icon: TextureProgressBar = $VBoxContainer/SprintDebuff/DebuffBar

## Container managing the layout of the immobilize debuff UI.
@onready var immobilize_container: Control = $VBoxContainer/ImmobilizeDebuff

## Texture progress bar layered over the immobilize debuff icon.
@onready var move_icon: TextureProgressBar = $VBoxContainer/ImmobilizeDebuff/DebuffBar

## Container managing the layout of the sand sprint-restriction indicator.
@onready var sand_indicator: Control = $VBoxContainer/SandIndicator

## Container managing the layout of the ice skating indicator.
@onready var ice_indicator: Control = $VBoxContainer/IceIndicator

## Stores the sliced textures for each state of a health heart.
var heart_textures: Array[AtlasTexture] = []

## Stores the UI nodes representing the player's health hearts.
var heart_nodes: Array[TextureRect] = []

## Stores active tweens for individual heart damage animations.
var heart_tweens: Array[Tween] = []

## Stores the currently instantiated keycard texture rectangles.
var active_card_icons: Dictionary = {}

## Tracks the player's current health to determine when to update the UI.
var current_health: int = 300

## Animates the sprint debuff progress bar.
var debuff_tween: Tween

## Animates the immobilize debuff progress bar.
var immobilize_tween: Tween

## Tracks if the player is currently under the effects of an immobilize debuff.
var is_immobilized: bool = false

## Tracks if the player is currently under the effects of a sprint block debuff.
var is_sprint_blocked: bool = false


## Lifecycle method called when the node enters the scene tree.
## Initializes containers, heart textures, and binds event bus listeners.
func _ready() -> void:
	print("PlayerStatusHUD: _ready() called. Initializing status HUD.")
	_initialize_indicators()
	_initialize_hearts()
	_connect_signals()


## Sets default visibility states for debuff containers and surface indicators.
func _initialize_indicators() -> void:
	print("PlayerStatusHUD: Setting initial indicator visibility states.")
	sprint_debuff_container.hide()
	immobilize_container.hide()
	if is_instance_valid(sand_indicator):
		sand_indicator.hide()
	if is_instance_valid(ice_indicator):
		ice_indicator.hide()


## Binds status and keycard events from the global [Events] bus and [KeycardSystem].
func _connect_signals() -> void:
	print("PlayerStatusHUD: Connecting global event bus signals.")
	if not Events.player_health_changed.is_connected(update_health):
		Events.player_health_changed.connect(update_health)
	if not Events.sprint_debuff_applied.is_connected(_on_sprint_debuff_applied):
		Events.sprint_debuff_applied.connect(_on_sprint_debuff_applied)
	if not Events.immobilize_debuff_applied.is_connected(_on_immobilize_debuff_applied):
		Events.immobilize_debuff_applied.connect(_on_immobilize_debuff_applied)
	if not Events.sand_surface_toggled.is_connected(_on_sand_surface_toggled):
		Events.sand_surface_toggled.connect(_on_sand_surface_toggled)
	if not Events.ice_surface_toggled.is_connected(_on_ice_surface_toggled):
		Events.ice_surface_toggled.connect(_on_ice_surface_toggled)

	if not KeycardSystem.card_picked_up.is_connected(_on_card_picked_up):
		KeycardSystem.card_picked_up.connect(_on_card_picked_up)
	if not KeycardSystem.card_used.is_connected(_on_card_used):
		KeycardSystem.card_used.connect(_on_card_used)


## Slices the heart atlas and builds initial health container representations.
func _initialize_hearts() -> void:
	print("PlayerStatusHUD: _initialize_hearts() called. Setting up health display.")
	if not hearts_atlas:
		push_warning("Hearts atlas not assigned in PlayerStatusHUD inspector!")
		return

	var atlas_width: float = hearts_atlas.get_width()
	var atlas_height: float = hearts_atlas.get_height()
	var frame_width: float = atlas_width / 5.0

	for i: int in range(5):
		var tex: AtlasTexture = AtlasTexture.new()
		tex.atlas = hearts_atlas
		tex.region = Rect2(i * frame_width, 0.0, frame_width, atlas_height)
		heart_textures.append(tex)

	while heart_nodes.size() * 100 < current_health:
		_add_heart_node()

	update_health(current_health)


## Dynamically adds a single heart UI node container to the screen layout.
func _add_heart_node() -> void:
	print("PlayerStatusHUD: _add_heart_node() - Expanding maximum heart UI count.")
	var atlas_height: float = hearts_atlas.get_height()
	var frame_width: float = hearts_atlas.get_width() / 5.0
	var target_size: Vector2 = Vector2(frame_width * 2.0, atlas_height * 2.0)

	var wrapper: Control = Control.new()
	wrapper.custom_minimum_size = target_size
	wrapper.use_parent_material = true
	hearts_container.add_child(wrapper)

	var rect: TextureRect = TextureRect.new()
	rect.texture = heart_textures[0]
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = target_size
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.use_parent_material = true

	wrapper.add_child(rect)
	heart_nodes.append(rect)
	heart_tweens.append(null)


## Re-renders all heart frames and plays health change damage or heal tweens.
## [param new_health] The current integer health total.
func update_health(new_health: int) -> void:
	print("PlayerStatusHUD: update_health() called with new value: ", new_health)

	while new_health > heart_nodes.size() * 100:
		_add_heart_node()

	var health_decreased: bool = new_health < current_health
	var health_increased: bool = new_health > current_health
	var previous_health: int = current_health
	current_health = new_health

	if heart_nodes.is_empty() or heart_textures.is_empty():
		return

	for i: int in range(heart_nodes.size()):
		var heart_min: int = i * 100
		var heart_val: int = clampi(current_health - heart_min, 0, 100)
		var prev_heart_val: int = clampi(previous_health - heart_min, 0, 100)

		var frame_index: int = 0
		if heart_val >= 100:
			frame_index = 0
		elif heart_val >= 75:
			frame_index = 1
		elif heart_val >= 50:
			frame_index = 2
		elif heart_val >= 25:
			frame_index = 3
		else:
			frame_index = 4

		heart_nodes[i].texture = heart_textures[frame_index]

		if health_decreased and heart_val < prev_heart_val:
			_animate_heart_damage(i)
		elif health_increased and heart_val > prev_heart_val:
			_animate_heart_heal(i, frame_index)

		heart_nodes[i].get_parent().visible = true


## Runs a vertical bounce tween on the target heart node when damaged.
## [param index] The heart slot index to animate.
func _animate_heart_damage(index: int) -> void:
	print("PlayerStatusHUD: _animate_heart_damage() called for index: ", index)
	if index < 0 or index >= heart_nodes.size():
		return

	var heart: TextureRect = heart_nodes[index]

	if heart_tweens[index] and heart_tweens[index].is_valid():
		heart_tweens[index].kill()

	heart.position.y = 0.0
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	heart_tweens[index] = tween

	var jump_height: float = -15.0
	var duration: float = 0.08

	tween.tween_property(heart, "position:y", jump_height, duration)
	tween.tween_property(heart, "position:y", jump_height * -0.3, duration)
	tween.tween_property(heart, "position:y", 0.0, duration)


## Spawns a scaling green ghost texture to visually represent health recovery.
## [param index] The heart slot index to animate.
## [param frame_index] Sliced texture frame index to duplicate on the ghost.
func _animate_heart_heal(index: int, frame_index: int) -> void:
	print("PlayerStatusHUD: _animate_heart_heal() called for index: ", index)
	if index < 0 or index >= heart_nodes.size():
		return

	var heart: TextureRect = heart_nodes[index]
	var ghost: TextureRect = TextureRect.new()

	ghost.texture = heart_textures[frame_index]
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.custom_minimum_size = heart.custom_minimum_size
	ghost.size = heart.size
	ghost.position = Vector2.ZERO
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.pivot_offset = ghost.size / 2.0
	ghost.modulate = Color(0.0, 1.0, 0.2, 0.5)

	heart.add_child(ghost)

	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	var anim_duration: float = 0.5
	tween.tween_property(ghost, "scale", Vector2(3.0, 3.0), anim_duration)
	tween.tween_property(ghost, "modulate:a", 0.0, anim_duration)
	tween.chain().tween_callback(ghost.queue_free)


## Adds a keycard texture rectangle to the HUD inventory display.
## [param card_id] Unique identifier key of the collected card.
func _on_card_picked_up(card_id: StringName) -> void:
	print("PlayerStatusHUD: Displaying new card ID ", card_id)
	var card_rect: TextureRect = TextureRect.new()
	card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_rect.custom_minimum_size = Vector2(80.0, 130.0)
	card_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if card_textures.has(card_id):
		card_rect.texture = card_textures[card_id]
	else:
		print("PlayerStatusHUD Warning: No texture mapped for card ID: ", card_id)

	keycards_container.add_child(card_rect)
	active_card_icons[card_id] = card_rect

	card_rect.scale = Vector2.ZERO
	card_rect.pivot_offset = card_rect.custom_minimum_size / 2.0
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_rect, "scale", Vector2.ONE, 0.4)


## Animates and removes a used keycard icon from the HUD inventory display.
## [param card_id] Unique identifier key of the consumed card.
func _on_card_used(card_id: StringName) -> void:
	print("PlayerStatusHUD: Removing used card ID ", card_id)
	if active_card_icons.has(card_id):
		var card_rect: TextureRect = active_card_icons[card_id]
		var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(card_rect, "scale", Vector2.ZERO, 0.2)
		tween.finished.connect(card_rect.queue_free)
		active_card_icons.erase(card_id)


## Starts and animates the sprint debuff progress bar cooldown.
## [param duration] Length of the debuff in seconds.
func _on_sprint_debuff_applied(duration: float) -> void:
	print(
		(
			"PlayerStatusHUD: _on_sprint_debuff_applied() - Starting debuff UI for "
			+ str(duration)
			+ " seconds."
		)
	)
	sprint_debuff_container.show()
	is_sprint_blocked = true

	sprint_icon.max_value = duration
	sprint_icon.value = duration

	if debuff_tween and debuff_tween.is_valid():
		debuff_tween.kill()

	debuff_tween = create_tween()
	debuff_tween.tween_property(sprint_icon, "value", 0.0, duration)
	debuff_tween.finished.connect(
		func() -> void:
			print("PlayerStatusHUD: Sprint debuff expired. Hiding UI.")
			sprint_debuff_container.hide()
			is_sprint_blocked = false
	)


## Starts and animates the immobilize debuff progress bar cooldown.
## [param duration] Length of the debuff in seconds.
func _on_immobilize_debuff_applied(duration: float) -> void:
	print(
		(
			"PlayerStatusHUD: _on_immobilize_debuff_applied() - Starting UI for "
			+ str(duration)
			+ " seconds."
		)
	)
	immobilize_container.show()
	is_immobilized = true

	move_icon.max_value = duration
	move_icon.value = duration

	if immobilize_tween and immobilize_tween.is_valid():
		immobilize_tween.kill()

	immobilize_tween = create_tween()
	immobilize_tween.tween_property(move_icon, "value", 0.0, duration)
	immobilize_tween.finished.connect(
		func() -> void:
			print("PlayerStatusHUD: Immobilize debuff expired. Hiding UI.")
			immobilize_container.hide()
			is_immobilized = false
	)


## Toggles visibility of the sand sprint-restriction icon.
## [param is_active] True if the player is currently on sand.
func _on_sand_surface_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Sand surface state toggled -> ", is_active)
	if sand_indicator:
		sand_indicator.visible = is_active


## Toggles visibility of the ice skating icon.
## [param is_active] True if the player is currently on ice.
func _on_ice_surface_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Ice surface state toggled -> ", is_active)
	if ice_indicator:
		ice_indicator.visible = is_active
