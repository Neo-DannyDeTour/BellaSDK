extends Node3D
#
@onready var anim_player := $Anim
@onready var close_timer: Timer = $CloseTimer
#
var is_moving := false
var is_open := false
var player_detected := false
var pending_open := false


func _on_detector_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not is_open and not is_moving:
		close_timer.stop()
		open()
		player_detected = true
	elif body.is_in_group("player") and is_moving:
		pending_open = true
		player_detected = true


func _on_detector_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and is_open and not is_moving:
		close_timer.start()
		close()
		player_detected = false
		pending_open = false


func open() -> void:
	is_moving = true
	anim_player.play("Open")
	await anim_player.animation_finished
	is_open = true
	is_moving = false
	print("OPEN")

	if close_timer.time_left > 0:
		pass
	elif close_timer.time_left == 0 and !player_detected:
		close()


func close() -> void:
	is_moving = true
	anim_player.play_backwards("Open")
	await anim_player.animation_finished
	is_open = false
	is_moving = false
	pending_open = false
	print("CLOSE")

	if pending_open or player_detected:
		open()
		pending_open = false
