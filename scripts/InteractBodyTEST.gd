extends StaticBody3D
@onready var label: Label = $Label

var is_open := false


func interact() -> void:
	if is_open:
		print("Closing Door")
		# Add animation code here
	else:
		print("Opening Door")
		# Add animation code here
	is_open = not is_open
