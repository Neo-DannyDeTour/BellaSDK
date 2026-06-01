extends PanelContainer

var player: CharacterBody3D

@onready var metrics_label: RichTextLabel = $MetricsLabel


func _ready() -> void:
	visible = false  # Keep it hidden on launch

	# MAGIC BULLET: Automatically find the player without Inspector paths!
	player = get_tree().get_first_node_in_group("player")

	metrics_label.add_theme_color_override("font_outline_color", Color.BLACK)
	metrics_label.add_theme_constant_override("outline_size", 4)


func _process(_delta: float) -> void:
	# PERFORMANCE BOOST: Do nothing if the window is closed
	if not visible or not player:
		return

	var fps := Engine.get_frames_per_second()
	var vel := player.velocity
	var speed := vel.length()

	# --- YOUR ROBUST COLOR LOGIC ---
	var fps_color := "green"
	if fps >= 60:
		fps_color = "green"
	elif fps >= 30:
		fps_color = "yellow"
	else:
		fps_color = "red"

	var current_input: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	var is_pressing_keys: bool = current_input.length() > 0.1

	# 2. Update the state logic to read from our new State Machine and Components!
	var state: String = "UNKNOWN"

	if player.system_menu and player.system_menu.flying:
		state = "NOCLIP"
	elif player.state_machine and player.state_machine.state:
		# Automatically grab the name of the active state (e.g., "Air", "Ladder", "Swim")
		state = player.state_machine.state.name.to_upper()

		# Add specific modifiers if the state is "GROUND"
		if state == "GROUND":
			if player.crouching:
				state = "CROUCHING" if is_pressing_keys else "CROUCH IDLE"
			elif player.sprint_active:
				state = "SPRINTING"
			elif is_pressing_keys:
				state = "WALKING"
			else:
				state = "IDLE"

	# --- MEMORY & RENDERING METRICS ---
	var static_mem := OS.get_static_memory_usage()
	var vram_usage := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)

	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)

	# --- NEW BOOLEAN CHECKS ---
	var flashlight_str := "OFF"
	if player.has_node("%Flashlight"):  # Or whatever unique name you gave the spotlight
		flashlight_str = "ON" if player.get_node("%Flashlight").visible else "OFF"

	var weapon_str := "NONE"
	if player.get_node("%WeaponHolder").get_child_count() > 0:
		weapon_str = player.get_node("%WeaponHolder").get_child(0).name

	# --- TEXT ASSEMBLY ---
	var text := ""
	text += "--- ENGINE ---\n"
	text += "[color=%s]FPS: %d[/color]\n" % [fps_color, fps]
	text += "RAM: %s\n" % String.humanize_size(static_mem)
	text += "VRAM: %s\n" % String.humanize_size(int(vram_usage))

	text += "\n--- RENDERING ---\n"
	text += "Draw Calls: %d\n" % draw_calls
	text += "Objects: %d\n" % objects
	text += "Primitives: %d\n" % primitives

	text += "\n--- PLAYER STATE ---\n"
	text += "STATE: %s\n" % state
	text += "WEAPON: %s\n" % weapon_str
	text += "SPEED: %.2f m/s\n" % speed
	text += "POS: %s\n" % var_to_str(player.global_position).replace("Vector3", "")
	text += "GROUNDED: %s\n" % ("YES" if player.is_on_floor() else "NO")
	text += "FLASHLIGHT: %s\n" % flashlight_str

	metrics_label.text = text


# Called by UI.gd when you click the button
func toggle_window() -> void:
	visible = !visible
