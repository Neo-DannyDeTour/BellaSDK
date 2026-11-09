class_name ChunkRoot
extends Node3D
## Root controller for a 250x250m streaming chunk handling off-thread delta
## application, roaming identity metadata stamping, and mutation reporting.

## World-space width and depth of a single streaming chunk in meters.
const CHUNK_SIZE: float = 250.0

## Sentinel payload indicating an entity was destroyed or collected.
const DELTA_FREED: StringName = &"freed"

## Scene group identifying entities that reparent to the world dynamic container.
const GROUP_ROAMING: StringName = &"roaming"

## Metadata key storing a roaming entity's original spawn chunk coordinate.
const META_ORIGIN_CHUNK: StringName = &"origin_chunk"

## Metadata key preserving an entity's original scene-unique name across reparenting.
const META_ENTITY_ID: StringName = &"entity_id"

## Method name invoked on child entities to stage non-destructive delta state.
const METHOD_ENTITY_DELTA: StringName = &"apply_delta"

## Chunk grid coordinate calculated from local position.
var chunk_coord: Vector2i = Vector2i.ZERO


## Disables frame loops, resolves grid coordinates, and stamps roaming children.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	chunk_coord = _compute_coord()
	_stamp_roaming_metadata()


## Applies saved [param deltas] on a worker thread before scene tree insertion.
func apply_chunk_deltas(deltas: Dictionary) -> void:
	chunk_coord = _compute_coord()
	_stamp_roaming_metadata()
	for entity_id: StringName in deltas.keys():
		var target: Node = get_node_or_null("%" + String(entity_id))
		if target == null:
			continue
		var payload: Variant = deltas[entity_id]
		if payload is StringName and payload == DELTA_FREED:
			var parent: Node = target.get_parent()
			if parent != null:
				parent.remove_child(target)
			target.free()
		elif payload is Transform3D:
			var target_3d: Node3D = target as Node3D
			if target_3d != null:
				target_3d.transform = payload
		elif target.has_method(METHOD_ENTITY_DELTA):
			target.call(METHOD_ENTITY_DELTA, payload)


## Emits [signal Events.chunk_entity_mutated] for [param entity] with [param data].
func report_entity_mutation(entity: Node, data: Variant) -> void:
	assert(is_instance_valid(entity), "Cannot report mutation for invalid entity.")
	var origin: Vector2i = chunk_coord
	if entity.has_meta(META_ORIGIN_CHUNK):
		var raw_origin: Variant = entity.get_meta(META_ORIGIN_CHUNK)
		if raw_origin is Vector2i:
			origin = raw_origin
	var entity_id: StringName = entity.name
	if entity.has_meta(META_ENTITY_ID):
		var raw_id: Variant = entity.get_meta(META_ENTITY_ID)
		if raw_id is StringName:
			entity_id = raw_id
		elif raw_id is String:
			entity_id = StringName(raw_id)
	print("Entity mutated in chunk ", origin, ": ", entity_id)
	Events.chunk_entity_mutated.emit(origin, entity_id, data)


## Computes grid coordinate from the chunk's local position assigned by [ChunkManager].
func _compute_coord() -> Vector2i:
	return Vector2i(roundi(position.x / CHUNK_SIZE), roundi(position.z / CHUNK_SIZE))


## Stamps direct children in [constant GROUP_ROAMING] with origin coord and original ID.
func _stamp_roaming_metadata() -> void:
	# shortcut: scans direct children of chunk root only, upgrade to recursive if nested.
	var children: Array[Node] = get_children()
	for child: Node in children:
		if not child.is_in_group(GROUP_ROAMING):
			continue
		if not child.has_meta(META_ORIGIN_CHUNK):
			child.set_meta(META_ORIGIN_CHUNK, chunk_coord)
		if not child.has_meta(META_ENTITY_ID):
			child.set_meta(META_ENTITY_ID, child.name)
