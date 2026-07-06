class_name GasLeakEmitter
extends GPUParticles3D

## Toggles the gas leak refraction effect on or off.
@export var is_leaking: bool = false:
	set(value):
		is_leaking = value
		emitting = is_leaking
		if is_leaking:
			print("Gas leak started: Emitting refractive fumes.")
		else:
			print("Gas leak stopped: Fumes dissipating.")


func _ready() -> void:
	emitting = is_leaking
	if is_leaking:
		print("Gas leak initialized and emitting on load.")


## Can be called externally by a player interaction or trigger volume.
func toggle_leak() -> void:
	print("Player interacted with gas valve.")
	is_leaking = !is_leaking
