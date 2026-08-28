extends "res://shared/health_modifier.gd"

var _dummy_bodies: Array[Node3D] = []

func get_overlapping_bodies() -> Array[Node3D]:
	return _dummy_bodies
