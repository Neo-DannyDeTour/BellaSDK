## A test harness for triggering 3D shockwave effects automatically.
##
## [ShockwaveTester] sets up a timer to continuously trigger a shockwave
## through the assigned [ShockwaveManager] at regular intervals.
class_name ShockwaveTester
extends Node3D

## The shockwave manager responsible for dispatching the effect.
@export var shockwave_manager: ShockwaveManager
## The time in seconds between consecutive shockwave triggers.
@export var trigger_interval: float = 2.0
## The maximum radius the shockwave effect will reach.
@export var test_radius: float = 5.0


## Creates and configures the internal timer used for triggering shockwaves.
func _ready() -> void:
	var timer: Timer = Timer.new()
	timer.wait_time = trigger_interval
	timer.autostart = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


## Fires a shockwave event when the timer expires.
func _on_timer_timeout() -> void:
	print(
		"ShockwaveTester: _on_timer_timeout() called. Firing shockwave with radius: ", test_radius
	)
	if shockwave_manager != null:
		shockwave_manager.trigger_shockwave(global_position, test_radius)
	else:
		print("ShockwaveTester: shockwave_manager is not assigned!")
