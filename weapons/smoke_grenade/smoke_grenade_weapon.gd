## Equippable smoke grenade throwable weapon compatible with [WeaponInventoryComponent].
class_name SmokeGrenadeWeapon
extends ThrowableWeapon

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Thrown physics canister packed scene spawned on throw.
const DEFAULT_PROJECTILE_SCENE: PackedScene = preload(
	"res://weapons/smoke_grenade/smoke_grenade_projectile.tscn"
)


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Sets default weapon tags and ammunition types for smoke grenade ordnance.
func _init() -> void:
	weapon_tag = "smoke_grenade"
	ammo_type = &"smoke_grenade"
	default_slot = 4
	max_ammo = 3


## Initializes grenade projectile scene, slot defaults, and delegates prompt setup to base.
func _ready() -> void:
	if not is_instance_valid(projectile_scene):
		projectile_scene = DEFAULT_PROJECTILE_SCENE

	super._ready()
	print(weapon_tag, ": SmokeGrenadeWeapon ready in slot ", default_slot)
