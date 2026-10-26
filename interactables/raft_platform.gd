## Buoyant floating raft platform with four barrel pontoons supporting heavy carry and riding.
class_name RaftPlatform
extends PickableObject

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Default mass scalar in kilograms providing heavy carry resistance and buoyancy stability.
const DEFAULT_RAFT_MASS: float = 60.0

## Target vertical center of mass offset placing ballast below waterline.
const DEFAULT_COM_OFFSET_Y: float = -0.35

## Default standoff distance offset pulling large raft platform forward during carry.
const DEFAULT_HOLD_OFFSET: float = -1.6

## Maximum detach distance threshold before dropping large platform.
const DEFAULT_DETACH_DISTANCE: float = 3.6

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_group("Raft Stability")
## Vertical center of mass offset below deck origin to prevent capsizing.
@export var com_offset_y: float = DEFAULT_COM_OFFSET_Y


# --------------------------------------
# LIFECYCLE
# --------------------------------------
## Configures raft buoyancy parameters, heavy carry offsets, and center of mass ballast.
func _ready() -> void:
	# Ensure raft stays dynamic so player weight and water waves pitch/roll naturally
	lock_on_player_stand = false

	if mass <= 0.0 or mass == 1.0:
		mass = DEFAULT_RAFT_MASS

	hold_distance_offset = DEFAULT_HOLD_OFFSET
	max_detach_distance = DEFAULT_DETACH_DISTANCE

	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, com_offset_y, 0.0)

	super._ready()
	print("RaftPlatform: Initialized ", name, " with mass ", mass, "kg.")
