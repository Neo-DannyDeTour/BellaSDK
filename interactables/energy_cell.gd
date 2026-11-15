@tool
## Physical energy cell with sloshing bio-liquid core that transitions from red to green.
class_name EnergyCell
extends PickableLiquidBottle

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when [member is_charged] changes state.
signal charged_state_changed(is_charged: bool)

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Per-instance shader uniform for emissive core brightness.
const PARAM_EMISSION_ENERGY: StringName = &"emission_energy"
## Inner core cylinder dimensions (radius, half-height) matching Mat_CellCore.
const CORE_SIZE: Vector2 = Vector2(0.185, 0.39)
## Fixed liquid fill level so meniscus and slosh remain visible at all charge states.
const LIQUID_FILL_LEVEL: float = 0.78
## Triplanar wave and bubble noise tiling multiplier.
const LIQUID_UV_SCALE: float = 2.2
## Baseline bubble agitation applied when the cell is charged at rest.
const CHARGED_IDLE_BUBBLES: float = 0.35

# --------------------------------------
# EXPORTS
# --------------------------------------
## Coagulated crimson liquid color applied when depleted of energy.
@export var discharged_color: Color = Color(0.48, 0.03, 0.02, 0.88):
	set(value):
		discharged_color = value
		_update_cell_visuals()

## Toxic phosphor green liquid color applied when fully charged.
@export var charged_color: Color = Color(0.12, 0.95, 0.22, 0.78):
	set(value):
		charged_color = value
		_update_cell_visuals()

## Maximum emission multiplier applied to the liquid when fully charged.
@export var glow_energy: float = 2.8:
	set(value):
		glow_energy = value
		_update_cell_visuals()

## Indicates whether the cell is currently charged with energy.
@export var is_charged: bool = false:
	set = set_charged

# --------------------------------------
# PUBLIC VARIABLES
# --------------------------------------
## Normalized progress of the red-to-green charge transition (0.0 to 1.0).
var fill_progress: float = 0.0:
	set = set_fill_progress


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Initializes liquid metrics, visibility gating, and initial charge visuals.
func _ready() -> void:
	fill = LIQUID_FILL_LEVEL
	super._ready()
	if not Engine.is_editor_hint():
		print("EnergyCell: Initializing cell instance: ", name)
	fill_progress = 1.0 if is_charged else 0.0
	_update_cell_visuals()


# --------------------------------------
# PUBLIC METHODS
# --------------------------------------
## Sets normalized red-to-green charge progress from 0.0 (depleted) to 1.0 (charged).
func set_fill_progress(value: float) -> void:
	fill_progress = clampf(value, 0.0, 1.0)
	if not is_inside_tree():
		return
	_update_cell_visuals()
	if not Engine.is_editor_hint():
		apply_slosh_impulse(Vector2(0.08, -0.06), 0.18)


## Updates [member is_charged], snaps [member fill_progress], and emits state change.
func set_charged(value: bool) -> void:
	is_charged = value
	if not Engine.is_editor_hint():
		print("EnergyCell: set_charged() called on ", name, " -> ", is_charged)
	fill_progress = 1.0 if is_charged else 0.0
	if is_inside_tree():
		_update_cell_visuals()
		if not Engine.is_editor_hint():
			apply_slosh_impulse(Vector2(0.18, -0.14), 0.35)
	charged_state_changed.emit(is_charged)


## Fully charges the cell, shifting the internal liquid to glowing green.
func charge() -> void:
	print("EnergyCell: charge() executed on ", name)
	set_charged(true)


## Discharges the cell, shifting the internal liquid to dim crimson.
func discharge() -> void:
	print("EnergyCell: discharge() executed on ", name)
	set_charged(false)


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
## Overrides bottle metric sync to match the inner [Mat_CellCore] cylinder bounds.
func _sync_mesh_metrics() -> void:
	if not is_instance_valid(_bottle_mesh):
		return
	_mesh_size = Vector3(CORE_SIZE.x * 2.0, CORE_SIZE.y * 2.0, CORE_SIZE.x * 2.0)
	_bottle_mesh.set_instance_shader_parameter(PARAM_SIZE, CORE_SIZE)
	_bottle_mesh.set_instance_shader_parameter(PARAM_SCALE, LIQUID_UV_SCALE)


## Pushes base liquid parameters plus [EnergyCell] emission state.
func _apply_all_parameters() -> void:
	super._apply_all_parameters()
	_update_cell_visuals()


## Updates per-instance liquid color, emission, and idle bubbling from [member fill_progress].
func _update_cell_visuals() -> void:
	if not is_inside_tree() or not is_instance_valid(_bottle_mesh):
		return

	var current_col: Color = discharged_color.lerp(charged_color, fill_progress)
	var current_emission: float = lerpf(0.12, glow_energy, fill_progress * fill_progress)
	liquid_color = current_col
	_bottle_mesh.set_instance_shader_parameter(PARAM_EMISSION_ENERGY, current_emission)
	if not _is_sloshing:
		_bottle_mesh.set_instance_shader_parameter(PARAM_VEL, fill_progress * CHARGED_IDLE_BUBBLES)
