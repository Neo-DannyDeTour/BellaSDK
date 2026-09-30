extends GutTest

## A GUT test script for the [CollisionLayers] class validating layer bitmask operations.
var test_name: String = "Test CollisionLayers"


func test_constants() -> void:
	print("Testing CollisionLayers constants...")
	assert_eq(CollisionLayers.LAYER_ENVIRONMENT_IDX, 1, "Environment layer idx should be 1")
	assert_eq(CollisionLayers.MASK_ENVIRONMENT, 1, "Environment mask should be 1 << 0")
	assert_eq(CollisionLayers.LAYER_ENEMIES_IDX, 5, "Enemies layer idx should be 5")
	assert_eq(CollisionLayers.MASK_ENEMIES, 16, "Enemies mask should be 1 << 4")


func test_layer_to_mask() -> void:
	print("Testing CollisionLayers.layer_to_mask()...")
	assert_eq(CollisionLayers.layer_to_mask(1), 1, "Layer 1 should map to mask 1")
	assert_eq(CollisionLayers.layer_to_mask(2), 2, "Layer 2 should map to mask 2")
	assert_eq(CollisionLayers.layer_to_mask(5), 16, "Layer 5 should map to mask 16")
	assert_eq(CollisionLayers.layer_to_mask(0), 0, "Invalid layer 0 should return mask 0")
	assert_eq(CollisionLayers.layer_to_mask(33), 0, "Invalid layer 33 should return mask 0")


func test_has_layer() -> void:
	print("Testing CollisionLayers.has_layer()...")
	var combined_mask: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_ENEMIES
	assert_true(
		CollisionLayers.has_layer(combined_mask, CollisionLayers.LAYER_ENVIRONMENT_IDX),
		"Should have environment layer"
	)
	assert_true(
		CollisionLayers.has_layer(combined_mask, CollisionLayers.LAYER_ENEMIES_IDX),
		"Should have enemies layer"
	)
	assert_false(
		CollisionLayers.has_layer(combined_mask, CollisionLayers.LAYER_PLAYER_IDX),
		"Should not have player layer"
	)
	assert_false(CollisionLayers.has_layer(combined_mask, 0), "Invalid layer should return false")
