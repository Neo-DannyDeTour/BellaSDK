## A basic static testing script used to verify that interactable raycasting systems are working.
##
## Acts as a dummy door node for debugging purposes.
class_name InteractBodyTest
extends StaticBody3D

## Toggles the dummy structural state when clicked.
var is_open: bool = false
## Reference to a 2D label used for on-screen debug printing.
@onready var label: Label = $Label


## Flips the internal boolean and logs the state change.
func interact() -> void:
	if is_open:
		print("Closing Door")
		# Add animation code here
	else:
		print("Opening Door")
		# Add animation code here
	is_open = not is_open
