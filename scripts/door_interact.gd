extends Node3D

@onready var animation_player: AnimationPlayer = $AnimatableBody3D/AnimationPlayer
@onready var timer: Timer = $Timer

# --- POWER SYSTEM ---
@export var required_power: int = 1
var power_component: PowerComponent
var is_powered_door: bool = false # Tracks if this is a puzzle door or normal door

var is_on_cooldown: bool = false

@export var open := false :
	set(v):
		if v != open:
			open = v
			update_door()

func _ready() -> void:
	# 1. Look for a PowerComponent child dynamically
	power_component = get_node_or_null("PowerComponent")
	
	if power_component:
		is_powered_door = true
		power_component.required_power = self.required_power
		# --- THE FIX: Point these to our renamed functions below ---
		power_component.powered_on.connect(power_on)
		power_component.powered_off.connect(power_off)

# --- PUZZLE LOGIC ---
# --- THE FIX: We removed the "_on_" so the Socket can call these directly! ---
func power_on() -> void:
	# We bypass the toggle_open() cooldown so puzzle buttons feel instantly responsive!
	open = true

func power_off() -> void:
	open = false

# --- ANIMATION LOGIC ---
func update_door() -> void:
	if not is_node_ready():
		await ready
		
	if open:
		print("opening")
		if animation_player.current_animation != "open":
			animation_player.play("open")
	else:
		print("closing")
		if animation_player.current_animation != "open" or animation_player.current_animation_position > 0:
			animation_player.play_backwards("open")

# --- MANUAL INTERACT LOGIC ---
func interact() -> void:
	if is_powered_door:
		print("This door is locked by a mechanism!")
		return # Block manual interaction if it requires a button!
		
	toggle_open()

func toggle_open(_player: CharacterBody3D = null) -> void:
	if is_on_cooldown:
		return
		
	is_on_cooldown = true
	open = !open
	
	await get_tree().create_timer(1.0).timeout
	is_on_cooldown = false

# --- DETECTOR LOGIC ---
func _on_detector_body_exited(body: Node3D) -> void:
	if is_powered_door: return # Don't auto-close puzzle doors!
	
	print("exited")
	if open and body.is_in_group("player"):
		timer.start()

func _on_detector_body_entered(body: Node3D) -> void:
	if is_powered_door: return 
	
	print("entered")
	if body.is_in_group("player") and not timer.is_stopped():
		timer.stop()
		
func _on_timer_timeout() -> void:
	if is_powered_door: return
	
	if open:
		if not is_on_cooldown:
			is_on_cooldown = true
			open = false
			await get_tree().create_timer(1.0).timeout
			is_on_cooldown = false
		else:
			timer.start(0.5)
