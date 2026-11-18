## Manages global [WorldEnvironment] lighting and fullbright debug toggles.
class_name GameWorldEnvironment
extends WorldEnvironment

## Reference to the WorldEnvironment node.
@onready var world_env: WorldEnvironment = $"."
## Reference to the main DirectionalLight3D sun.
@onready var sun: DirectionalLight3D = $DirectionalLight3D


## Connects global fullbright toggle signals.
func _ready() -> void:
	if (
		is_instance_valid(Events)
		and not Events.fullbright_toggled.is_connected(_on_fullbright_toggled)
	):
		Events.fullbright_toggled.connect(_on_fullbright_toggled)


## Disconnects global fullbright toggle signals.
func _exit_tree() -> void:
	if is_instance_valid(Events) and Events.fullbright_toggled.is_connected(_on_fullbright_toggled):
		Events.fullbright_toggled.disconnect(_on_fullbright_toggled)


## Applies or reverts fullbright debug lighting on the environment and sun.
func _on_fullbright_toggled(is_fullbright: bool) -> void:
	if not world_env or not world_env.environment:
		return

	if is_fullbright:
		# 1. THE LIGHTING: Use "Color" mode at maximum energy
		world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_env.environment.ambient_light_color = Color.WHITE
		world_env.environment.ambient_light_energy = 2.0  # Extra high to wash out textures

		# 2. THE BACKGROUND: Grey void
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0.5, 0.5, 0.5)

		# 3. THE SHADOW KILLERS: Disable these specifically
		world_env.environment.ssao_enabled = false
		world_env.environment.ssil_enabled = false
		world_env.environment.sdfgi_enabled = false
		world_env.environment.glow_enabled = false

		if sun:
			sun.visible = false
			sun.shadow_enabled = false
	else:
		world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		world_env.environment.background_mode = Environment.BG_SKY
		world_env.environment.ambient_light_energy = 1.0

		# Re-enable your game's specific fancy effects here
		world_env.environment.ssao_enabled = true
		world_env.environment.ssil_enabled = true
		world_env.environment.sdfgi_enabled = true
		world_env.environment.glow_enabled = true
		world_env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

		if sun:
			sun.visible = true
			sun.shadow_enabled = true
