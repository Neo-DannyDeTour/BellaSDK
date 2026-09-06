## A 3D particle emitter that simulates a refractive gas or steam leak.
##
## [GasLeakEmitter] manages a [GPUParticles3D] system to visually represent
## a hazardous or environmental gas leak, which can be toggled on and off.
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


## Syncs the initial emission state with the configured [member is_leaking] property.
func _ready() -> void:
	emitting = is_leaking
	if is_leaking:
		print("Gas leak initialized and emitting on load.")


## Can be called externally by a player interaction or trigger volume to flip the leak state.
func toggle_leak() -> void:
	print("Player interacted with gas valve.")
	is_leaking = not is_leaking
