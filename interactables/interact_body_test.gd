extends StaticBody3D

## Is open.
var is_open: bool = false
## Label.
@onready var label: Label = $Label


func interact() -> void:
	if is_open:
		print("Closing Door")
		# Add animation code here
	else:
		print("Opening Door")
		# Add animation code here
	is_open = not is_open
