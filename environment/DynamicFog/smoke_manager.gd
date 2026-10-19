## Global coordinator routing weapon trajectories, blasts, and AI vision queries
## to volumetric fog zones.
# class_name SmokeManager
extends Node

## Default bullet tunnel radius in meters when callers pass legacy duration values.
const DEFAULT_BULLET_RADIUS: float = 0.55

## Maximum radius accepted from generic hitscan calls before clamping to default.
const MAX_HITSCAN_RADIUS: float = 1.5

## Optical depth threshold above which AI line-of-sight rays are obstructed.
const LOS_OPTICAL_DEPTH_THRESHOLD: float = 1.15

## Active environmental fog and smoke volumes currently registered in the scene tree.
var _zones: Array[FogVolume] = []


## Disables per-frame processing on startup; runs strictly on weapon/zone events.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	print("[SmokeManager] Ready and listening for fog zone registrations.")


## Registers an active [FogVolume] ([DynamicFogZone] or [SmokeHazard]) for carving and LoS.
func register_zone(zone: FogVolume) -> void:
	if not is_instance_valid(zone) or _zones.has(zone):
		return
	_zones.append(zone)
	print("[SmokeManager] Registered volumetric zone: ", zone.name)


## Unregisters a [FogVolume] when it exits the scene tree.
func unregister_zone(zone: FogVolume) -> void:
	var idx: int = _zones.find(zone)
	if idx != -1:
		_zones.remove_at(idx)
		print("[SmokeManager] Unregistered volumetric zone: ", zone.name)


## Legacy-compatible entrypoint called directly by [HitscanWeapon._execute_shot_rays].
func add_bullet_hole(
	origin: Vector3,
	direction: Vector3,
	max_range: float,
	radius_or_duration: float = DEFAULT_BULLET_RADIUS
) -> void:
	# shortcut: values above 1.5m from legacy HitscanWeapon calls are treated as default radius.
	var effective_radius: float = (
		radius_or_duration if radius_or_duration <= MAX_HITSCAN_RADIUS else DEFAULT_BULLET_RADIUS
	)
	var end_pos: Vector3 = origin + direction.normalized() * max_range
	carve_segment(origin, end_pos, effective_radius)


## Carves a 3D cylindrical tunnel between [param start_pos] and [param end_pos] in matching zones.
func carve_segment(
	start_pos: Vector3, end_pos: Vector3, radius: float = DEFAULT_BULLET_RADIUS
) -> void:
	if _zones.is_empty():
		return

	var seg_min: Vector3 = start_pos.min(end_pos) - Vector3(radius, radius, radius)
	var seg_max: Vector3 = start_pos.max(end_pos) + Vector3(radius, radius, radius)
	var seg_aabb: AABB = AABB(seg_min, seg_max - seg_min)

	for i: int in range(_zones.size() - 1, -1, -1):
		var zone: FogVolume = _zones[i]
		if not is_instance_valid(zone):
			_zones.remove_at(i)
			continue
		if (
			zone.has_method(&"intersects_world_aabb")
			and zone.call(&"intersects_world_aabb", seg_aabb)
		):
			if zone.has_method(&"carve_bullet_ray"):
				zone.call(&"carve_bullet_ray", start_pos, end_pos, radius)


## Carves a spherical explosion blast cavity in all overlapping volumetric zones.
func carve_explosion(center: Vector3, radius: float, duration: float = 3.5) -> void:
	if _zones.is_empty():
		return

	var extent: Vector3 = Vector3(radius, radius, radius)
	var blast_aabb: AABB = AABB(center - extent, extent * 2.0)

	for i: int in range(_zones.size() - 1, -1, -1):
		var zone: FogVolume = _zones[i]
		if not is_instance_valid(zone):
			_zones.remove_at(i)
			continue
		if (
			zone.has_method(&"intersects_world_aabb")
			and zone.call(&"intersects_world_aabb", blast_aabb)
		):
			if zone.has_method(&"carve_explosion_sphere"):
				zone.call(&"carve_explosion_sphere", center, radius, duration)
			elif zone.has_method(&"carve_bullet_ray"):
				zone.call(
					&"carve_bullet_ray",
					center - Vector3(0.0, 0.05, 0.0),
					center + Vector3(0.0, 0.05, 0.0),
					radius
				)


## Returns true if cumulative volumetric optical depth between [param from]
## and [param to] blocks AI sight.
func is_line_of_sight_obscured(from: Vector3, to: Vector3) -> bool:
	if _zones.is_empty():
		return false

	var seg_min: Vector3 = from.min(to)
	var seg_max: Vector3 = from.max(to)
	var ray_aabb: AABB = AABB(seg_min, seg_max - seg_min)
	var total_optical_depth: float = 0.0

	for i: int in range(_zones.size() - 1, -1, -1):
		var zone: FogVolume = _zones[i]
		if not is_instance_valid(zone):
			_zones.remove_at(i)
			continue
		if not zone.visible:
			continue
		if zone.has_method(&"get_segment_optical_depth"):
			if (
				zone.has_method(&"intersects_world_aabb")
				and not zone.call(&"intersects_world_aabb", ray_aabb)
			):
				continue
			var depth_val: Variant = zone.call(&"get_segment_optical_depth", from, to)
			if depth_val is float:
				total_optical_depth += depth_val
				if total_optical_depth >= LOS_OPTICAL_DEPTH_THRESHOLD:
					return true

	return false
