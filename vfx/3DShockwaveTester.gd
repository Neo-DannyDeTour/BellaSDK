class_name ShockwaveTester
extends Node3D

@export var shockwave_manager: ShockwaveManager
@export var trigger_interval: float = 2.0
@export var test_radius: float = 5.0


func _ready() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = trigger_interval
	timer.autostart = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


func _on_timer_timeout() -> void:
	print(
		"ShockwaveTester: _on_timer_timeout() called. Firing shockwave with radius: ", test_radius
	)
	if shockwave_manager != null:
		shockwave_manager.trigger_shockwave(global_position, test_radius)
	else:
		print("ShockwaveTester: shockwave_manager is not assigned!")
