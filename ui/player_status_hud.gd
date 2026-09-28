## Manages player status indicators including health hearts, debuff slots, and keycards.
class_name PlayerStatusHUD
extends MarginContainer

## Sliced texture frames of health hearts for varying status levels.
@export var hearts_atlas: Texture2D

## Maps keycard IDs to their respective inventory icon textures.
@export var card_textures: Dictionary[StringName, Texture2D] = {}

## Container arranging health heart icons horizontally.
@onready var hearts_container: HBoxContainer = $VBoxContainer/HeartsContainer

## Container arranging collected keycard icons horizontally.
@onready var keycards_container: HBoxContainer = $VBoxContainer/KeycardsContainer

## Container managing layout of sprint debuff UI slot.
@onready var sprint_debuff_container: Control = $VBoxContainer/SprintDebuff

## Texture progress bar layered over sprint debuff icon.
@onready var sprint_bar: TextureProgressBar = $VBoxContainer/SprintDebuff/DebuffBar

## Frame border overlay node for sprint status slot.
@onready var sprint_border: NinePatchRect = $VBoxContainer/SprintDebuff/BorderOverlay

## Numeric timer label displaying remaining sprint debuff duration.
@onready var sprint_timer_label: Label = $VBoxContainer/SprintDebuff/TimerLabel

## Container managing layout of immobilize debuff UI slot.
@onready var immobilize_container: Control = $VBoxContainer/ImmobilizeDebuff

## Texture progress bar layered over immobilize debuff icon.
@onready var move_bar: TextureProgressBar = $VBoxContainer/ImmobilizeDebuff/DebuffBar

## Frame border overlay node for immobilize status slot.
@onready var immobilize_border: NinePatchRect = $VBoxContainer/ImmobilizeDebuff/BorderOverlay

## Numeric timer label displaying remaining immobilize duration.
@onready var immobilize_timer_label: Label = $VBoxContainer/ImmobilizeDebuff/TimerLabel

## Container managing layout of ice debuff UI slot.
@onready var ice_debuff_container: Control = $VBoxContainer/IceDebuff

## Texture progress bar layered over ice debuff icon.
@onready var ice_bar: TextureProgressBar = $VBoxContainer/IceDebuff/DebuffBar

## Frame border overlay node for ice status slot.
@onready var ice_border: NinePatchRect = $VBoxContainer/IceDebuff/BorderOverlay

## Numeric timer label displaying remaining ice debuff duration.
@onready var ice_timer_label: Label = $VBoxContainer/IceDebuff/TimerLabel

## Container managing layout of swim debuff UI slot.
@onready var swim_debuff_container: Control = $VBoxContainer/SwimDebuff

## Texture progress bar layered over swim debuff icon.
@onready var swim_bar: TextureProgressBar = $VBoxContainer/SwimDebuff/DebuffBar

## Frame border overlay node for swim status slot.
@onready var swim_border: NinePatchRect = $VBoxContainer/SwimDebuff/BorderOverlay

## Numeric timer label displaying remaining swim duration.
@onready var swim_timer_label: Label = $VBoxContainer/SwimDebuff/TimerLabel

## Container managing layout of steam debuff UI slot.
@onready var steam_debuff_container: Control = $VBoxContainer/SteamDebuff

## Texture progress bar layered over steam debuff icon.
@onready var steam_bar: TextureProgressBar = $VBoxContainer/SteamDebuff/DebuffBar

## Frame border overlay node for steam status slot.
@onready var steam_border: NinePatchRect = $VBoxContainer/SteamDebuff/BorderOverlay

## Numeric timer label displaying remaining steam debuff duration.
@onready var steam_timer_label: Label = $VBoxContainer/SteamDebuff/TimerLabel

## Container managing layout of fire debuff UI slot.
@onready var fire_debuff_container: Control = $VBoxContainer/FireDebuff

## Texture progress bar layered over fire debuff icon.
@onready var fire_bar: TextureProgressBar = $VBoxContainer/FireDebuff/DebuffBar

## Frame border overlay node for fire status slot.
@onready var fire_border: NinePatchRect = $VBoxContainer/FireDebuff/BorderOverlay

## Numeric timer label displaying remaining fire debuff duration.
@onready var fire_timer_label: Label = $VBoxContainer/FireDebuff/TimerLabel

## Stores sliced textures for each state of health heart.
var heart_textures: Array[AtlasTexture] = []

## Stores UI nodes representing player's health hearts.
var heart_nodes: Array[TextureRect] = []

## Stores active tweens for individual heart damage animations.
var heart_tweens: Array[Tween] = []

## Stores instantiated keycard texture rectangles mapped by ID.
var active_card_icons: Dictionary = {}

## Tracks current player health to determine when to update UI.
var current_health: int = 300

## Animates sprint debuff progress bar and timer label.
var debuff_tween: Tween

## Animates immobilize debuff progress bar and timer label.
var immobilize_tween: Tween

## Animates swim oxygen progress bar and timer label.
var swim_tween: Tween

## Animates or fades fire damage indicator when burning ceases.
var fire_tween: Tween

## Tracks if timed sprint cooldown is currently active.
var is_sprint_timer_active: bool = false

## Tracks if player is currently standing on sand.
var is_on_sand: bool = false

## Tracks if player is currently carrying heavy object.
var is_heavy_carrying: bool = false

## Tracks if player is currently standing on ice.
var is_on_ice: bool = false

## Tracks if player is under immobilize debuff effect.
var is_immobilized: bool = false

## Tracks if player is under sprint blocked debuff effect.
var is_sprint_blocked: bool = false

## Tracks if infinite swim accessibility mode is enabled.
var is_infinite_swim: bool = false

## Tracks whether player head is submerged underwater.
var is_submerged: bool = false

## Tracks if player is standing in active steam hazard.
var is_in_steam: bool = false

## Tracks if player is actively suffering fire damage.
var is_in_fire: bool = false


## Lifecycle method called when node enters the tree.
func _ready() -> void:
	print("PlayerStatusHUD: _ready() called. Initializing status HUD.")
	is_infinite_swim = bool(GlobalSettings.get_setting("Accessibility", "infinite_swim", false))
	_initialize_indicators()
	_initialize_hearts()
	_connect_signals()


## Sets default visibility states for debuff containers and surface indicators.
func _initialize_indicators() -> void:
	print("PlayerStatusHUD: Setting initial indicator visibility states.")
	sprint_debuff_container.hide()
	sprint_bar.hide()
	sprint_timer_label.hide()
	immobilize_container.hide()
	move_bar.hide()
	immobilize_timer_label.hide()
	ice_debuff_container.hide()
	ice_bar.hide()
	ice_timer_label.hide()
	swim_debuff_container.hide()
	swim_bar.hide()
	swim_timer_label.hide()
	steam_debuff_container.hide()
	steam_bar.hide()
	steam_timer_label.hide()
	fire_debuff_container.hide()
	fire_border.hide()
	fire_bar.hide()
	fire_timer_label.hide()


## Binds status and keycard events from global bus using [Utilities.safe_connect].
func _connect_signals() -> void:
	print("PlayerStatusHUD: Connecting global event bus signals.")
	Utilities.safe_connect(Events.player_health_changed, update_health)
	Utilities.safe_connect(Events.sprint_debuff_applied, _on_sprint_debuff_applied)
	Utilities.safe_connect(Events.immobilize_debuff_applied, _on_immobilize_debuff_applied)
	Utilities.safe_connect(Events.sand_surface_toggled, _on_sand_surface_toggled)
	Utilities.safe_connect(Events.ice_surface_toggled, _on_ice_surface_toggled)
	Utilities.safe_connect(Events.heavy_carry_toggled, _on_heavy_carry_toggled)
	Utilities.safe_connect(Events.oxygen_timer_started, _on_oxygen_timer_started)
	Utilities.safe_connect(Events.oxygen_timer_stopped, _on_oxygen_timer_stopped)
	Utilities.safe_connect(Events.steam_hazard_toggled, _on_steam_hazard_toggled)
	Utilities.safe_connect(Events.fire_hazard_toggled, _on_fire_hazard_toggled)

	Utilities.safe_connect(KeycardSystem.card_picked_up, _on_card_picked_up)
	Utilities.safe_connect(KeycardSystem.card_used, _on_card_used)
	Utilities.safe_connect(Events.infinite_swim_toggled, _on_infinite_swim_toggled)


## Slices the heart atlas and builds initial health representations.
func _initialize_hearts() -> void:
	print("PlayerStatusHUD: _initialize_hearts() called.")
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
	print("PlayerStatusHUD: _add_heart_node() - Expanding heart UI count.")
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


## Re-renders all heart frames and plays health change animations.
## [param new_health] Current integer health total.
func update_health(new_health: int) -> void:
	print("PlayerStatusHUD: update_health() called with: ", new_health)

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
## [param index] Heart slot index to animate.
func _animate_heart_damage(index: int) -> void:
	print("PlayerStatusHUD: _animate_heart_damage() called for index: ", index)
	if index < 0 or index >= heart_nodes.size():
		return

	var heart: TextureRect = heart_nodes[index]
	heart_tweens[index] = Utilities.reset_tween(self, heart_tweens[index])
	if not is_instance_valid(heart_tweens[index]):
		return

	heart.position.y = 0.0
	var tween: Tween = heart_tweens[index]
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var jump_height: float = -15.0
	var duration: float = 0.08

	tween.tween_property(heart, "position:y", jump_height, duration)
	tween.tween_property(heart, "position:y", jump_height * -0.3, duration)
	tween.tween_property(heart, "position:y", 0.0, duration)


## Spawns a scaling green ghost texture to visually represent health recovery.
## [param index] Heart slot index to animate.
## [param frame_index] Sliced texture frame index to duplicate on ghost.
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
	Utilities.center_control(ghost)
	ghost.modulate = Color(0.0, 1.0, 0.2, 0.5)

	heart.add_child(ghost)

	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var anim_duration: float = 0.5
	tween.tween_property(ghost, "scale", Vector2(3.0, 3.0), anim_duration)
	tween.tween_property(ghost, "modulate:a", 0.0, anim_duration)
	tween.chain().tween_callback(ghost.queue_free)


## Adds a keycard texture rectangle using [method Utilities.center_control].
## [param card_id] Unique identifier key of collected card.
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
	Utilities.center_control(card_rect)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card_rect, "scale", Vector2.ONE, 0.4)


## Animates and removes used keycard icon safely avoiding leaks.
## [param card_id] Unique identifier key of consumed card.
func _on_card_used(card_id: StringName) -> void:
	print("PlayerStatusHUD: Removing used card ID ", card_id)
	if active_card_icons.has(card_id):
		var card_rect: TextureRect = active_card_icons[card_id]
		var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(card_rect, "scale", Vector2.ZERO, 0.2)
		tween.finished.connect(card_rect.queue_free)
		active_card_icons.erase(card_id)


## Starts and animates the sprint debuff progress bar cooldown.
## [param duration] Length of the debuff in seconds.
func _on_sprint_debuff_applied(duration: float) -> void:
	print("PlayerStatusHUD: _on_sprint_debuff_applied() - Starting for ", duration)
	is_sprint_timer_active = true
	sprint_bar.show()
	sprint_timer_label.show()
	sprint_bar.max_value = duration
	sprint_bar.value = duration
	sprint_timer_label.text = "%.1fs" % duration

	_sync_sprint_display()

	debuff_tween = Utilities.reset_tween(self, debuff_tween)
	if not is_instance_valid(debuff_tween):
		return

	debuff_tween.tween_method(
		func(val: float) -> void:
			sprint_bar.value = val
			sprint_timer_label.text = "%.1fs" % val,
		duration,
		0.0,
		duration
	)
	debuff_tween.finished.connect(
		func() -> void:
			print("PlayerStatusHUD: Timed sprint debuff completed.")
			is_sprint_timer_active = false
			sprint_bar.hide()
			sprint_timer_label.hide()
			_sync_sprint_display()
	)


## Starts and animates the immobilize debuff progress bar cooldown.
## [param duration] Length of the debuff in seconds.
func _on_immobilize_debuff_applied(duration: float) -> void:
	print("PlayerStatusHUD: _on_immobilize_debuff_applied() - Starting UI for ", duration)
	is_immobilized = true
	immobilize_container.show()
	move_bar.show()
	immobilize_timer_label.show()
	immobilize_border.show()

	move_bar.max_value = duration
	move_bar.value = duration
	immobilize_timer_label.text = "%.1fs" % duration

	immobilize_tween = Utilities.reset_tween(self, immobilize_tween)
	if not is_instance_valid(immobilize_tween):
		return

	immobilize_tween.tween_method(
		func(val: float) -> void:
			move_bar.value = val
			immobilize_timer_label.text = "%.1fs" % val,
		duration,
		0.0,
		duration
	)
	immobilize_tween.finished.connect(
		func() -> void:
			print("PlayerStatusHUD: Immobilize debuff expired. Hiding UI.")
			is_immobilized = false
			move_bar.hide()
			immobilize_timer_label.hide()
			immobilize_container.hide()
	)


## Handles updates to the infinite swim mode setting.
## [param enabled] True if infinite swim mode is turned on.
func _on_infinite_swim_toggled(enabled: bool) -> void:
	print("PlayerStatusHUD: Infinite swim toggled -> ", enabled)
	is_infinite_swim = enabled

	if not is_submerged:
		return

	if is_infinite_swim:
		if is_instance_valid(swim_tween) and swim_tween.is_valid():
			swim_tween.kill()
		swim_debuff_container.show()
		swim_border.show()
		swim_bar.hide()
		swim_timer_label.hide()
	else:
		swim_debuff_container.show()
		swim_border.show()


## Starts and animates the submerged swim progress bar and timer label.
## [param duration] Length of the swim breath timer in seconds.
func _on_oxygen_timer_started(duration: float) -> void:
	print("PlayerStatusHUD: _on_oxygen_timer_started() called. Duration: ", duration)
	is_submerged = true
	swim_debuff_container.show()
	swim_border.show()

	if is_infinite_swim:
		if is_instance_valid(swim_tween) and swim_tween.is_valid():
			swim_tween.kill()
		swim_bar.hide()
		swim_timer_label.hide()
		return

	swim_tween = Utilities.reset_tween(self, swim_tween)
	if not is_instance_valid(swim_tween):
		return

	swim_bar.show()
	swim_timer_label.show()
	swim_bar.max_value = duration
	swim_bar.value = duration
	swim_timer_label.text = "%.1fs" % duration

	swim_tween.tween_method(
		func(val: float) -> void:
			swim_bar.value = val
			swim_timer_label.text = "%.1fs" % val,
		duration,
		0.0,
		duration
	)
	swim_tween.finished.connect(
		func() -> void:
			print("PlayerStatusHUD: Swim oxygen timer expired. Drowning begins.")
			swim_bar.value = 0.0
			swim_timer_label.text = "0.0s"
	)


## Stops the swim countdown and completely hides the swimming HUD slot.
func _on_oxygen_timer_stopped() -> void:
	print("PlayerStatusHUD: _on_oxygen_timer_stopped() - Player surfaced.")
	is_submerged = false
	if is_instance_valid(swim_tween) and swim_tween.is_valid():
		swim_tween.kill()

	swim_bar.hide()
	swim_timer_label.hide()
	swim_border.hide()
	swim_debuff_container.hide()


## Updates steam hazard indicator icon and border overlay.
## [param is_active] True if the player is actively exposed to steam.
func _on_steam_hazard_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Steam hazard toggled -> ", is_active)
	is_in_steam = is_active
	steam_debuff_container.visible = is_in_steam
	steam_border.visible = is_in_steam
	steam_bar.hide()
	steam_timer_label.hide()


## Updates fire hazard indicator icon and border overlay.
## [param is_active] True if the player is actively exposed to fire.
func _on_fire_hazard_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Fire hazard toggled -> ", is_active)
	is_in_fire = is_active
	fire_debuff_container.visible = is_in_fire
	fire_border.visible = is_in_fire
	fire_bar.hide()
	fire_timer_label.hide()


## Updates persistent sand sprint-restriction status.
## [param is_active] True if the player is currently on sand.
func _on_sand_surface_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Sand surface toggled -> ", is_active)
	is_on_sand = is_active
	_sync_sprint_display()


## Updates ice surface status indicator and border overlay.
## [param is_active] True if the player is currently on ice.
func _on_ice_surface_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Ice surface toggled -> ", is_active)
	is_on_ice = is_active
	ice_debuff_container.visible = is_on_ice
	ice_border.visible = is_on_ice
	ice_bar.hide()
	ice_timer_label.hide()


## Toggles sprint debuff icon visibility based on heavy carry status.
## [param is_active] True if the player is holding a heavy object.
func _on_heavy_carry_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Heavy carry toggled -> ", is_active)
	is_heavy_carrying = is_active
	_sync_sprint_display()


## Resolves visibility of the sprint slot and border across active sources.
func _sync_sprint_display() -> void:
	print("PlayerStatusHUD: Synchronizing sprint debuff slot visibility.")
	is_sprint_blocked = (is_sprint_timer_active or is_on_sand or is_heavy_carrying)
	sprint_debuff_container.visible = is_sprint_blocked
	sprint_border.visible = is_sprint_blocked

	if not is_sprint_timer_active:
		sprint_bar.hide()
		sprint_timer_label.hide()
