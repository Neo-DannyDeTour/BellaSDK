extends StaticBody3D

var is_open := false
@onready var label: Label = $Label


func interact() -> void:
	if is_open:
		print("Closing Door")
		# Add animation code here
	else:
		print("Opening Door")
		# Add animation code here
	is_open = not is_open
