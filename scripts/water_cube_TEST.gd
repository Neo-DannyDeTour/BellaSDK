extends StaticBody3D

var target_scale_y: float = 1.0
var drain_speed: float = 0.5  # How fast the water lowers

@onready var water_wrapper := $WaterWrapper


func leak_at(hit_pos: Vector3) -> void:
	# 1. Convert global hit to local space
	var local_hit := to_local(hit_pos)

	# 2. Grab the height of the bullet hole
	var new_scale := local_hit.y

	# --- NEW: THE FATAL SHOT CHECK ---
	# If they shoot the very bottom (below 0.05 on the local Y), force it to 0
	if new_scale <= 0.05:
		new_scale = 0.0
		print("Fatal hit! Draining completely.")

	# 3. Only lower the water! (Prevents water from rising if they shoot the top again)
	if new_scale < target_scale_y and new_scale >= 0.0:
		target_scale_y = new_scale
		print("Water draining down to height: ", target_scale_y)


func _process(delta: float) -> void:
	# Smoothly shrink the water wrapper
	if water_wrapper.scale.y > target_scale_y:
		water_wrapper.scale.y -= drain_speed * delta

		# Snap it when it reaches the hole
		if water_wrapper.scale.y <= target_scale_y:
			water_wrapper.scale.y = target_scale_y

			# --- NEW: DESTROY ON EMPTY ---
			if target_scale_y <= 0.0:
				print("Tank empty! Destroying.")
				# Optional: Spawn a broken glass sound or particle here!
				queue_free()
