## Global coordinator routing weapon trajectories and blasts to active fog and grenade nodes.
# class_name SmokeManager
extends Node

## Default bullet tunnel radius in meters when callers pass legacy duration values.
const DEFAULT_BULLET_RADIUS: float = 0.55

## Maximum radius accepted from generic hitscan calls before clamping to default.
const MAX_HITSCAN_RADIUS: float = 1.5

## Active environmental fog zones currently registered in the scene tree.
var _zones: Array[DynamicFogZone] = []

## Active smoke grenade clouds currently registered in the scene tree.
var _grenade_clouds: Array[SmokeGrenadeCloud] = []


## Disables per-frame processing on startup; runs strictly on weapon/zone events.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	print("[SmokeManager] Ready and listening for fog zone and grenade cloud registrations.")


## Registers an active [DynamicFogZone] to receive projectile carve events.
func register_zone(zone: DynamicFogZone) -> void:
	if not is_instance_valid(zone) or _zones.has(zone):
		return
	_zones.append(zone)
	print("[SmokeManager] Registered DynamicFogZone: ", zone.name)


## Unregisters a [DynamicFogZone] when it exits the scene tree.
func unregister_zone(zone: DynamicFogZone) -> void:
	var idx: int = _zones.find(zone)
	if idx != -1:
		_zones.remove_at(idx)
		print("[SmokeManager] Unregistered DynamicFogZone: ", zone.name)


## Registers an active [SmokeGrenadeCloud] to receive bullet and blast carve events.
func register_cloud(cloud: SmokeGrenadeCloud) -> void:
	if not is_instance_valid(cloud) or _grenade_clouds.has(cloud):
		return
	_grenade_clouds.append(cloud)
	print("[SmokeManager] Registered SmokeGrenadeCloud: ", cloud.name)


## Unregisters a [SmokeGrenadeCloud] when it expires or exits the scene tree.
func unregister_cloud(cloud: SmokeGrenadeCloud) -> void:
	var idx: int = _grenade_clouds.find(cloud)
	if idx != -1:
		_grenade_clouds.remove_at(idx)
		print("[SmokeManager] Unregistered SmokeGrenadeCloud: ", cloud.name)


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
	if _zones.is_empty() and _grenade_clouds.is_empty():
		return

	var seg_min: Vector3 = start_pos.min(end_pos) - Vector3(radius, radius, radius)
	var seg_max: Vector3 = start_pos.max(end_pos) + Vector3(radius, radius, radius)
	var seg_aabb: AABB = AABB(seg_min, seg_max - seg_min)

	for i: int in range(_zones.size() - 1, -1, -1):
		var zone: DynamicFogZone = _zones[i]
		if not is_instance_valid(zone):
			_zones.remove_at(i)
			continue
		if zone.intersects_world_aabb(seg_aabb):
			zone.carve_bullet_ray(start_pos, end_pos, radius)

	for i: int in range(_grenade_clouds.size() - 1, -1, -1):
		var cloud: SmokeGrenadeCloud = _grenade_clouds[i]
		if not is_instance_valid(cloud):
			_grenade_clouds.remove_at(i)
			continue
		if cloud.intersects_world_aabb(seg_aabb):
			cloud.carve_bullet_ray(start_pos, end_pos, radius)
