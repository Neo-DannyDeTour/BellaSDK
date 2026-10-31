## Unit tests verifying [SaveManager] SHA-256 integrity checks, schema validation, and security.
class_name TestSaveIntegrity
extends GutTest

## Path to temporary test directory in user storage.
const TEST_DIR: String = "user://test_integrity/"


## Inner mock inheriting SaveManager script directly for concrete type checking.
class ConcreteSaveManager:
	extends "res://core/save_manager.gd"


## The concrete save manager instance under test.
var save_manager: ConcreteSaveManager = null


## Sets up fresh save manager instance and prepares test directory before each test.
func before_each() -> void:
	print("TestSaveIntegrity: before_each() setup started.")
	save_manager = ConcreteSaveManager.new()
	add_child_autoqfree(save_manager)

	var dir: DirAccess = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("test_integrity"):
			var err: Error = dir.make_dir("test_integrity")
			if err != OK:
				push_error("TestSaveIntegrity: Failed creating test dir: " + str(err))


## Cleans up temporary test files after each test run.
func after_each() -> void:
	print("TestSaveIntegrity: after_each() cleanup started.")
	var dir: DirAccess = DirAccess.open(TEST_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.remove(TEST_DIR)


## Verifies SHA-256 checksum calculation produces deterministic 64-character hex strings.
func test_compute_file_sha256() -> void:
	print("TestSaveIntegrity: test_compute_file_sha256() executing.")
	var test_file_path: String = TEST_DIR + "sample.dat"
	var file: FileAccess = FileAccess.open(test_file_path, FileAccess.WRITE)
	assert_not_null(file, "Test file should open for writing.")
	file.store_string("BellaIntegrityTestDataPayload_12345")
	file.close()

	var checksum_a: String = save_manager.compute_file_sha256(test_file_path)
	var checksum_b: String = save_manager.compute_file_sha256(test_file_path)

	assert_eq(checksum_a.length(), 64, "SHA-256 hex string must be exactly 64 characters.")
	assert_eq(checksum_a, checksum_b, "Checksum of unchanged file must be deterministic.")

	var missing_checksum: String = save_manager.compute_file_sha256(TEST_DIR + "missing.dat")
	assert_eq(missing_checksum, "", "Missing file should return empty checksum.")


## Verifies level path security validation restricts external or traversal paths.
func test_level_path_validation() -> void:
	print("TestSaveIntegrity: test_level_path_validation() executing.")
	assert_true(
		save_manager.is_valid_level_path("res://levels/level_01.tscn"),
		"res:// path should be accepted."
	)
	assert_true(
		save_manager.is_valid_level_path(""), "Empty level path should be accepted as valid."
	)
	assert_false(
		save_manager.is_valid_level_path("user://malicious.gd"), "user:// path should be rejected."
	)
	assert_false(
		save_manager.is_valid_level_path("/etc/passwd"), "Absolute system path should be rejected."
	)
	assert_false(
		save_manager.is_valid_level_path("res://levels/../../secret.txt"),
		"Path traversal (..) should be rejected."
	)
	assert_false(
		save_manager.is_valid_level_path("res://core/save_manager.gd"),
		"Non-tscn files should be rejected."
	)


## Verifies state dictionary validator rejects malformed, non-dictionary, or foreign node keys.
func test_validate_state_dictionary() -> void:
	print("TestSaveIntegrity: test_validate_state_dictionary() executing.")
	var valid_state: Dictionary = {
		"/root/Main/Player": {"health": 100, "ammo": 24},
		"/root/Main/Checkpoint": {"activated": true}
	}
	assert_true(
		save_manager.validate_state_dictionary(valid_state),
		"Valid state dictionary with /root/ prefix should pass."
	)

	var non_dict: Variant = "not_a_dictionary"
	assert_false(
		save_manager.validate_state_dictionary(non_dict),
		"Non-dictionary Variant should fail validation."
	)

	var invalid_key_state: Dictionary = {"relative/path/node": {"health": 100}}
	assert_false(
		save_manager.validate_state_dictionary(invalid_key_state),
		"Non-/root/ node keys should fail validation."
	)

	var invalid_child_val: Dictionary = {"/root/Main/Player": "invalid_payload"}
	assert_false(
		save_manager.validate_state_dictionary(invalid_child_val),
		"Non-dictionary node values should fail validation."
	)


## Verifies metadata writing encodes the payload checksum properly into the JSON file.
func test_metadata_checksum_encoding() -> void:
	print("TestSaveIntegrity: test_metadata_checksum_encoding() executing.")
	var dat_path: String = TEST_DIR + "save_test.dat"
	var meta_path: String = TEST_DIR + "save_test.meta"

	var dat_file: FileAccess = FileAccess.open(dat_path, FileAccess.WRITE)
	assert_not_null(dat_file, "Dat file should be created.")
	dat_file.store_string("TestDataPayload")
	dat_file.close()

	save_manager._write_metadata(meta_path, "Slot 1", "2026-10-30", false, dat_path)

	var meta_file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
	assert_not_null(meta_file, "Metadata file should exist.")
	var raw_text: String = meta_file.get_as_text()
	meta_file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	assert_true(parsed is Dictionary, "Metadata should parse to a Dictionary.")
	var meta_dict: Dictionary = parsed if parsed is Dictionary else {}
	assert_true(meta_dict.has("checksum"), "Metadata must contain checksum field.")

	var expected_hash: String = save_manager.compute_file_sha256(dat_path)
	assert_eq(
		str(meta_dict.get("checksum", "")),
		expected_hash,
		"Checksum in metadata must match computed dat hash."
	)
