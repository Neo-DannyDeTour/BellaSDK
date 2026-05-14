extends PickableObject
class_name TetheredPlug

@export_category("Cable Physics")
## How "springy" the cable feels when you hit the max distance (0.0 = hard stop)
@export_range(0.0, 1.0) var cable_elasticity: float = 0.0

var anchor_point: Node3D
var max_cable_length: float 

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_instance_valid(anchor_point): 
		return
		
	var to_anchor := anchor_point.global_position - state.transform.origin
	var dist := to_anchor.length()
	
	# Add a tiny 0.1m buffer so it doesn't instantly drop 
	# if the physics jiggle slightly at the absolute limit.
	if dist > (max_cable_length + 0.1):
		
		# --- THE FIX: Force the player to drop the object ---
		if is_held: 
			drop() 
			
		var dir := to_anchor.normalized()
		var overshoot := dist - max_cable_length
		
		# 1. Immediately kill any velocity trying to escape further away
		var outward_vel := state.linear_velocity.dot(-dir)
		if outward_vel > 0:
			state.linear_velocity -= (-dir) * outward_vel
			
		# 2. Return the plug to the boundary
		if cable_elasticity <= 0.01:
			state.transform.origin += dir * overshoot 
		else:
			var spring_strength: float = lerpf(2.0, 15.0, cable_elasticity)
			state.linear_velocity += dir * (overshoot * spring_strength)
