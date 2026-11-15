## Personality mood component driving Imp aggression, evasion, and playful behavior weights.
class_name ImpMoodComponent
extends Node

## Percentage bias toward aggressive rushing, rapid attacks, and stack slams.
@export_range(0, 100, 1) var aggressive_pct: int = 50

## Percentage bias toward strafing, dodge-hops, and proactive hex shielding.
@export_range(0, 100, 1) var evasive_pct: int = 25

## Percentage bias toward maniacal laughing, playful hops, and infrequent attacks.
@export_range(0, 100, 1) var playful_pct: int = 25


## Disables per-frame processing since mood queries are demand-driven.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)


## Returns normalized mood weights as [Vector3](aggressive, evasive, playful) in [0..1].
func get_normalized_weights() -> Vector3:
	var agg: float = float(maxi(aggressive_pct, 0))
	var eva: float = float(maxi(evasive_pct, 0))
	var ply: float = float(maxi(playful_pct, 0))
	var total: float = agg + eva + ply
	if total <= 0.0001:
		return Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)
	return Vector3(agg / total, eva / total, ply / total)


## Returns normalized aggressive weight in [0..1].
func get_aggressive_weight() -> float:
	return get_normalized_weights().x


## Returns normalized evasive weight in [0..1].
func get_evasive_weight() -> float:
	return get_normalized_weights().y


## Returns normalized playful weight in [0..1].
func get_playful_weight() -> float:
	return get_normalized_weights().z


## Returns attack cooldown multiplier (< 1.0 faster for aggressive, > 1.0 slower for playful).
func get_attack_cooldown_multiplier() -> float:
	var w: Vector3 = get_normalized_weights()
	return w.x * 0.65 + w.y * 1.15 + w.z * 1.85


## Returns dodge-hop probability in [0..1], highest for evasive and playful imps.
func get_dodge_probability() -> float:
	var w: Vector3 = get_normalized_weights()
	return clampf(w.x * 0.15 + w.y * 0.85 + w.z * 0.65, 0.0, 1.0)


## Returns hop/taunt frequency bias in [0..1], highest for playful imps.
func get_hop_taunt_frequency() -> float:
	var w: Vector3 = get_normalized_weights()
	return clampf(w.x * 0.10 + w.y * 0.45 + w.z * 0.85, 0.0, 1.0)


## Returns laugh interval multiplier (< 1.0 laughs much more often for playful imps).
func get_laugh_interval_multiplier() -> float:
	var w: Vector3 = get_normalized_weights()
	return w.x * 1.60 + w.y * 1.10 + w.z * 0.45


## Returns hex shield deployment bias in [0..1], highest for evasive imps.
func get_shield_bias() -> float:
	var w: Vector3 = get_normalized_weights()
	return clampf(w.x * 0.25 + w.y * 0.90 + w.z * 0.40, 0.0, 1.0)


## Returns hex shield cooldown multiplier (< 1.0 refreshes faster for evasive imps).
func get_shield_cooldown_multiplier() -> float:
	var w: Vector3 = get_normalized_weights()
	return w.x * 1.25 + w.y * 0.60 + w.z * 1.00


## Returns lateral strafe bias in [0..1] during chase locomotion.
func get_strafe_bias() -> float:
	var w: Vector3 = get_normalized_weights()
	return clampf(w.x * 0.20 + w.y * 0.90 + w.z * 0.60, 0.0, 1.0)


## Returns 3-imp stack slam initiation bias in [0..1], highest for aggressive imps.
func get_stack_slam_bias() -> float:
	var w: Vector3 = get_normalized_weights()
	return clampf(w.x * 0.95 + w.y * 0.25 + w.z * 0.35, 0.0, 1.0)


## Returns movement speed multiplier (> 1.0 pushes harder for aggressive imps).
func get_speed_multiplier() -> float:
	var w: Vector3 = get_normalized_weights()
	return w.x * 1.20 + w.y * 1.08 + w.z * 0.92
