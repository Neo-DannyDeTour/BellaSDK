## Runtime shader and material cache avoiding compilation hitches across dynamic entities.
class_name MaterialCache
extends Object

## Cache mapping material paths or composite keys to [Material] instances.
static var _material_cache: Dictionary[String, Material] = {}


## Returns a cached clone of [param base_material] or registers a new copy.
static func get_instance(base_material: Material) -> Material:
	if base_material == null:
		return null

	var key: String = base_material.resource_path
	if key.is_empty():
		key = str(base_material.get_instance_id())

	if _material_cache.has(key):
		return _material_cache[key]

	var new_instance: Material = base_material.duplicate() as Material
	_material_cache[key] = new_instance
	print("[MaterialCache] Cached new material instance for: %s" % key)
	return new_instance


## Retrieves or creates a material clone mapped to a unique composite variant key.
static func get_variant(base_material: Material, variant_key: String) -> Material:
	if base_material == null:
		return null

	var base_id: String = base_material.resource_path
	if base_id.is_empty():
		base_id = str(base_material.get_instance_id())

	var composite_key: String = "%s:%s" % [base_id, variant_key]
	if _material_cache.has(composite_key):
		return _material_cache[composite_key]

	var new_inst: Material = base_material.duplicate() as Material
	_material_cache[composite_key] = new_inst
	print("[MaterialCache] Cached new variant [%s]" % composite_key)
	return new_inst


## Clears all cached material instances to free graphics memory.
static func clear_cache() -> void:
	var count: int = _material_cache.size()
	_material_cache.clear()
	print("[MaterialCache] Cleared %d cached material instances" % count)
