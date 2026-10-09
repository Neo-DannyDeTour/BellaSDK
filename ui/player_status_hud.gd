## Player status HUD managing health hearts, hazard slots, and inventory keycards.
class_name PlayerStatusHUD
extends MarginContainer

## Sliced texture frames of health hearts for varying status levels.
@export var hearts_atlas: Texture2D

## Maps keycard IDs to their respective inventory icon textures.
@export var card_textures: Dictionary[StringName, Texture2D] = {}

## Palette and asset registry providing theme colors and fallback textures.
@export var reference_data: ReferenceData

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
var active_card_icons: Dictionary[StringName, TextureRect] = {}

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

## Tracks last rendered tenth of second for sprint timer label.
var _last_sprint_tenth: int = -1

## Tracks last rendered tenth of second for immobilize timer label.
var _last_move_tenth: int = -1

## Tracks last rendered tenth of second for swim timer label.
var _last_swim_tenth: int = -1


## Lifecycle method called when node enters the tree.
func _ready() -> void:
	print("PlayerStatusHUD: _ready() called. Initializing status HUD.")
	var swim_val: Variant = GlobalSettings.get_setting("Accessibility", "infinite_swim", false)
	if swim_val is bool:
		is_infinite_swim = swim_val

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


## Binds status and keycard events from global bus using [method Utilities.safe_connect].
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
	Utilities.safe_connect(Events.infinite_swim_toggled, _on_infinite_swim_toggled)

	var keycard_sys: Node = get_node_or_null("/root/KeycardSystem")
	if is_instance_valid(keycard_sys):
		if keycard_sys.has_signal(&"card_picked_up"):
			var card_picked_sig: Signal = Signal(keycard_sys, &"card_picked_up")
			Utilities.safe_connect(card_picked_sig, _on_card_picked_up)
		if keycard_sys.has_signal(&"card_used"):
			var card_used_sig: Signal = Signal(keycard_sys, &"card_used")
			Utilities.safe_connect(card_used_sig, _on_card_used)


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
## [param new_health] The updated health total to display.
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

		var heart_parent: CanvasItem = (
			heart_nodes[i].get_parent() if heart_nodes[i].get_parent() is CanvasItem else null
		)
		if is_instance_valid(heart_parent):
			heart_parent.visible = true


## Runs a vertical bounce tween on the target heart node when damaged.
## [param index] Index of the damaged heart in [member heart_nodes].
func _animate_heart_damage(index: int) -> void:
	# print("PlayerStatusHUD: _animate_heart_damage() called for index: ", index)
	if index < 0 or index >= heart_nodes.size():
		return

	var heart: TextureRect = heart_nodes[index]
	heart_tweens[index] = Utilities.reset_tween_ext(
		self, heart_tweens[index], Tween.TRANS_SINE, Tween.EASE_IN_OUT
	)
	if not is_instance_valid(heart_tweens[index]):
		return

	heart.position.y = 0.0
	var tween: Tween = heart_tweens[index]
	var jump_height: float = -15.0
	var duration: float = 0.08

	tween.tween_property(heart, "position:y", jump_height, duration)
	tween.tween_property(heart, "position:y", jump_height * -0.3, duration)
	tween.tween_property(heart, "position:y", 0.0, duration)


## Spawns a scaling heal ghost texture to visually represent health recovery.
## [param index] Index of the healed heart in [member heart_nodes].
## [param frame_index] Sliced atlas frame index representing health status.
func _animate_heart_heal(index: int, frame_index: int) -> void:
	# print("PlayerStatusHUD: _animate_heart_heal() called for index: ", index)
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

	var heal_tint: Color = Color(0.2, 0.85, 0.35, 0.5)
	if is_instance_valid(reference_data):
		heal_tint = reference_data.success_color
		heal_tint.a = 0.5
	ghost.modulate = heal_tint

	heart.add_child(ghost)

	var tween: Tween = Utilities.reset_tween_ext(self, null, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	if not is_instance_valid(tween):
		ghost.queue_free()
		return

	tween.set_parallel(true)
	var anim_duration: float = 0.5
	tween.tween_property(ghost, "scale", Vector2(3.0, 3.0), anim_duration)
	tween.tween_property(ghost, "modulate:a", 0.0, anim_duration)
	tween.chain().tween_callback(ghost.queue_free)


## Adds a keycard texture rectangle using [method Utilities.center_control].
## [param card_id] Unique identifier for the picked up keycard item.
func _on_card_picked_up(card_id: StringName) -> void:
	print("PlayerStatusHUD: Displaying new card ID ", card_id)
	var card_rect: TextureRect = TextureRect.new()
	card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_rect.custom_minimum_size = Vector2(80.0, 130.0)
	card_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var resolved_icon: Texture2D = card_textures.get(card_id, null)
	if resolved_icon == null and is_instance_valid(reference_data):
		resolved_icon = reference_data.get_category_icon(Types.ItemCategory.KEYCARD)
	card_rect.texture = resolved_icon

	keycards_container.add_child(card_rect)
	active_card_icons[card_id] = card_rect

	card_rect.scale = Vector2.ZERO
	Utilities.center_control(card_rect)
	var tween: Tween = Utilities.reset_tween_ext(self, null, Tween.TRANS_BACK, Tween.EASE_OUT)
	if is_instance_valid(tween):
		tween.tween_property(card_rect, "scale", Vector2.ONE, 0.4)


## Animates and removes used keycard icon safely avoiding memory leaks.
## [param card_id] Unique identifier for the used keycard item to discard.
func _on_card_used(card_id: StringName) -> void:
	print("PlayerStatusHUD: Removing used card ID ", card_id)
	if active_card_icons.has(card_id):
		var card_rect: TextureRect = active_card_icons[card_id]
		var tween: Tween = Utilities.reset_tween_ext(self, null, Tween.TRANS_BACK, Tween.EASE_IN)
		if is_instance_valid(tween):
			tween.tween_property(card_rect, "scale", Vector2.ZERO, 0.2)
			tween.finished.connect(card_rect.queue_free)
		else:
			card_rect.queue_free()
		active_card_icons.erase(card_id)


## Starts and animates the sprint debuff progress bar cooldown.
## [param duration] Cooldown timer duration in seconds.
func _on_sprint_debuff_applied(duration: float) -> void:
	print("PlayerStatusHUD: _on_sprint_debuff_applied() - Starting for ", duration)
	is_sprint_timer_active = true
	sprint_bar.show()
	sprint_timer_label.show()
	sprint_bar.max_value = duration
	sprint_bar.value = duration
	sprint_timer_label.text = "%.1fs" % duration
	_last_sprint_tenth = -1

	_sync_sprint_display()

	debuff_tween = Utilities.reset_tween_ext(
		self, debuff_tween, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT
	)
	if not is_instance_valid(debuff_tween):
		return

	var update_sprint: Callable = func(val: float) -> void:
		sprint_bar.value = val
		var current_tenth: int = int(roundf(val * 10.0))
		if current_tenth != _last_sprint_tenth:
			_last_sprint_tenth = current_tenth
			sprint_timer_label.text = "%.1fs" % (float(current_tenth) * 0.1)

	debuff_tween.tween_method(update_sprint, duration, 0.0, duration)
	debuff_tween.finished.connect(
		func() -> void:
			print("PlayerStatusHUD: Timed sprint debuff completed.")
			is_sprint_timer_active = false
			sprint_bar.hide()
			sprint_timer_label.hide()
			_sync_sprint_display()
	)


## Starts and animates the immobilize debuff progress bar cooldown.
## [param duration] Cooldown timer duration in seconds.
func _on_immobilize_debuff_applied(duration: float) -> void:
	print("PlayerStatusHUD: _on_immobilize_debuff_applied() - Starting for ", duration)
	is_immobilized = true
	immobilize_container.show()
	move_bar.show()
	immobilize_timer_label.show()
	immobilize_border.show()

	move_bar.max_value = duration
	move_bar.value = duration
	immobilize_timer_label.text = "%.1fs" % duration
	_last_move_tenth = -1

	immobilize_tween = Utilities.reset_tween_ext(
		self, immobilize_tween, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT
	)
	if not is_instance_valid(immobilize_tween):
		return

	var update_immobilize: Callable = func(val: float) -> void:
		move_bar.value = val
		var current_tenth: int = int(roundf(val * 10.0))
		if current_tenth != _last_move_tenth:
			_last_move_tenth = current_tenth
			immobilize_timer_label.text = "%.1fs" % (float(current_tenth) * 0.1)

	immobilize_tween.tween_method(update_immobilize, duration, 0.0, duration)
	immobilize_tween.finished.connect(
		func() -> void:
			print("PlayerStatusHUD: Immobilize debuff expired. Hiding UI.")
			is_immobilized = false
			move_bar.hide()
			immobilize_timer_label.hide()
			immobilize_container.hide()
	)


## Handles updates to the infinite swim mode setting.
## [param enabled] True if infinite swim accessibility mode is active.
func _on_infinite_swim_toggled(enabled: bool) -> void:
	print("PlayerStatusHUD: Infinite swim toggled -> ", enabled)
	is_infinite_swim = enabled

	if not is_submerged:
		return

	if is_infinite_swim:
		Utilities.safe_kill_tween(swim_tween)
		swim_debuff_container.show()
		swim_border.show()
		swim_bar.hide()
		swim_timer_label.hide()
	else:
		swim_debuff_container.show()
		swim_border.show()


## Starts and animates the submerged swim progress bar and timer label.
## [param duration] Remaining oxygen countdown duration in seconds.
func _on_oxygen_timer_started(duration: float) -> void:
	# print("PlayerStatusHUD: _on_oxygen_timer_started() called. Duration: ", duration)
	is_submerged = true
	swim_debuff_container.show()
	swim_border.show()

	if is_infinite_swim:
		Utilities.safe_kill_tween(swim_tween)
		swim_bar.hide()
		swim_timer_label.hide()
		return

	swim_tween = Utilities.reset_tween_ext(self, swim_tween, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	if not is_instance_valid(swim_tween):
		return

	swim_bar.show()
	swim_timer_label.show()
	swim_bar.max_value = duration
	swim_bar.value = duration
	swim_timer_label.text = "%.1fs" % duration
	_last_swim_tenth = -1

	var update_swim: Callable = func(val: float) -> void:
		swim_bar.value = val
		var current_tenth: int = int(roundf(val * 10.0))
		if current_tenth != _last_swim_tenth:
			_last_swim_tenth = current_tenth
			swim_timer_label.text = "%.1fs" % (float(current_tenth) * 0.1)

	swim_tween.tween_method(update_swim, duration, 0.0, duration)
	swim_tween.finished.connect(
		func() -> void:
			# print("PlayerStatusHUD: Swim oxygen timer expired. Drowning begins.")
			swim_bar.value = 0.0
			swim_timer_label.text = "0.0s"
	)


## Stops the swim countdown and completely hides the swimming HUD slot.
func _on_oxygen_timer_stopped() -> void:
	# print("PlayerStatusHUD: _on_oxygen_timer_stopped() - Player surfaced.")
	is_submerged = false
	Utilities.safe_kill_tween(swim_tween)
	swim_bar.hide()
	swim_timer_label.hide()
	swim_border.hide()
	swim_debuff_container.hide()


## Updates steam hazard indicator icon and border overlay.
## [param is_active] True if player is standing in steam hazard.
func _on_steam_hazard_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Steam hazard toggled -> ", is_active)
	is_in_steam = is_active
	steam_debuff_container.visible = is_in_steam
	steam_border.visible = is_in_steam
	steam_bar.hide()
	steam_timer_label.hide()


## Updates fire hazard indicator icon and border overlay.
## [param is_active] True if player is actively suffering fire damage.
func _on_fire_hazard_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Fire hazard toggled -> ", is_active)
	is_in_fire = is_active
	fire_debuff_container.visible = is_in_fire
	fire_border.visible = is_in_fire
	fire_bar.hide()
	fire_timer_label.hide()


## Updates persistent sand sprint-restriction status.
## [param is_active] True if player is standing on sand surface.
func _on_sand_surface_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Sand surface toggled -> ", is_active)
	is_on_sand = is_active
	_sync_sprint_display()


## Updates ice surface status indicator and border overlay.
## [param is_active] True if player is standing on ice surface.
func _on_ice_surface_toggled(is_active: bool) -> void:
	print("PlayerStatusHUD: Ice surface toggled -> ", is_active)
	is_on_ice = is_active
	ice_debuff_container.visible = is_on_ice
	ice_border.visible = is_on_ice
	ice_bar.hide()
	ice_timer_label.hide()


## Toggles sprint debuff icon visibility based on heavy carry status.
## [param is_active] True if player is carrying a heavy object.
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
