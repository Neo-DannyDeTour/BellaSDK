## Fast vector math, wave equations, and physics damping helpers in [MathUtils].
class_name MathUtils
extends Object


## Calculates semi-implicit Euler damped spring position and velocity.
static func damped_spring(
	current: float, target: float, velocity: float, stiffness: float, damping: float, delta: float
) -> Dictionary:
	var displacement: float = current - target
	var spring_force: float = -(stiffness * displacement)
	var damping_force: float = -(damping * velocity)
	var acceleration: float = spring_force + damping_force
	var new_velocity: float = velocity + acceleration * delta
	var new_position: float = current + new_velocity * delta
	return {&"position": new_position, &"velocity": new_velocity}


## Calculates semi-implicit Euler damped spring for a [Vector3] position and velocity.
static func damped_spring_v3(
	current: Vector3,
	target: Vector3,
	velocity: Vector3,
	stiffness: float,
	damping: float,
	delta: float
) -> Dictionary:
	var displacement: Vector3 = current - target
	var spring_force: Vector3 = -(stiffness * displacement)
	var damping_force: Vector3 = -(damping * velocity)
	var acceleration: Vector3 = spring_force + damping_force
	var new_velocity: Vector3 = velocity + acceleration * delta
	var new_position: Vector3 = current + new_velocity * delta
	return {&"position": new_position, &"velocity": new_velocity}


## Calculates quadratic Bezier curve point at interpolation factor [param t].
static func quadratic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var inv_t: float = 1.0 - t
	return (inv_t * inv_t * p0) + (2.0 * inv_t * t * p1) + (t * t * p2)


## Calculates cubic Bezier curve point at interpolation factor [param t].
static func cubic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var inv_t: float = 1.0 - t
	var inv_t2: float = inv_t * inv_t
	var t2: float = t * t
	return (inv_t2 * inv_t * p0) + (3.0 * inv_t2 * t * p1) + (3.0 * inv_t * t2 * p2) + (t2 * t * p3)


## Computes single harmonic sine wave displacement.
static func sine_wave(
	time: float, frequency: float, position_x: float, wave_number: float, amplitude: float
) -> float:
	return sin(time * frequency + position_x * wave_number) * amplitude


## Computes Gerstner wave 3D displacement vector for fluid surfaces.
static func gerstner_wave(
	pos: Vector3, wave_dir: Vector2, steepness: float, wavelength: float, time: float
) -> Vector3:
	var k: float = TAU / maxf(0.001, wavelength)
	var c: float = sqrt(9.8 / k)
	var d: Vector2 = wave_dir.normalized()
	var f: float = k * (d.x * pos.x + d.y * pos.z) - c * time
	var a: float = steepness / k
	return Vector3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)))


## Computes compound ocean wave displacement from position and packed parameters.
static func calculate_wave_height(pos: Vector3, wave_params: Vector4, time: float) -> float:
	var freq: float = wave_params.x
	var amp: float = wave_params.y
	var speed: float = wave_params.z
	var phase: float = wave_params.w
	return sin(pos.x * freq + time * speed + phase) * amp


## Computes dual-frequency compound wave height.
static func compound_wave_height(x: float, z: float, t: float) -> float:
	return sin(x * 0.5 + t) * cos(z * 0.5 + t)


## Clamps an angle in degrees between minimum and maximum bounds.
static func clamp_angle_deg(angle_deg: float, min_deg: float, max_deg: float) -> float:
	var wrapped: float = fposmod(angle_deg + 180.0, 360.0) - 180.0
	return clampf(wrapped, min_deg, max_deg)


## Clamps an angle in radians between minimum and maximum bounds.
static func clamp_angle_rad(angle_rad: float, min_rad: float, max_rad: float) -> float:
	var wrapped: float = fposmod(angle_rad + PI, TAU) - PI
	return clampf(wrapped, min_rad, max_rad)


## Smoothly damps an angular rotation towards a target angle avoiding wrapping issues.
static func smooth_damp_angle(
	current: float, target: float, velocity: float, smooth_time: float, delta: float
) -> Vector2:
	var diff: float = fposmod(target - current + PI, TAU) - PI
	var target_unwrapped: float = current + diff
	var omega: float = 2.0 / maxf(0.0001, smooth_time)
	var x: float = omega * delta
	var exp_decay: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change: float = current - target_unwrapped
	var temp: float = (velocity + omega * change) * delta
	var new_vel: float = (velocity - omega * temp) * exp_decay
	var new_pos: float = target_unwrapped + (change + temp) * exp_decay
	return Vector2(new_pos, new_vel)


## Exponentially damps a scalar float towards a target value.
static func damp(current: float, target: float, smoothing: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-smoothing * delta))


## Exponentially damps a [Vector2] towards a target vector.
static func damp_v2(current: Vector2, target: Vector2, smoothing: float, delta: float) -> Vector2:
	return current.lerp(target, 1.0 - exp(-smoothing * delta))


## Exponentially damps a [Vector3] towards a target vector.
static func damp_v3(current: Vector3, target: Vector3, smoothing: float, delta: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-smoothing * delta))


## Calculates the exact midpoint vector between two points.
static func get_midpoint(a: Vector3, b: Vector3) -> Vector3:
	return (a + b) * 0.5
