## Unit tests verifying [SaveManager], [Player], and [StatsComponent] tamper defenses.
class_name TestSaveTamperingDefense
extends GutTest

## Path to isolated test directory in user storage.
const TEST_DIR: String = "user://test_tamper/"


## Concrete mock inheriting SaveManager script for test isolation.
class ConcreteSaveManager:
	extends "res://core/save_manager.gd"


## The concrete save manager instance under test.
var save_manager: ConcreteSaveManager = null


## Sets up fresh save manager instance and prepares isolated directory before each test.
func before_each() -> void:
	print("TestSaveTamperingDefense: before_each() setup started.")
	save_manager = ConcreteSaveManager.new()
	add_child_autoqfree(save_manager)

	var dir: DirAccess = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("test_tamper"):
			var err: Error = dir.make_dir("test_tamper")
			if err != OK:
				push_error("TestSaveTamperingDefense: Failed creating test dir: " + str(err))


## Cleans up temporary test files after each test run.
func after_each() -> void:
	print("TestSaveTamperingDefense: after_each() cleanup started.")
	var dir: DirAccess = DirAccess.open(TEST_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.remove(TEST_DIR)


## Verifies [method SaveManager.load_save_game] aborts when metadata checksum is missing or empty.
func test_empty_checksum_rejection() -> void:
	print("TestSaveTamperingDefense: test_empty_checksum_rejection() executing.")
	var base_path: String = TEST_DIR + "save_empty_chk"
	var dat_path: String = base_path + ".dat"
	var meta_path: String = base_path + ".meta"

	var dat_file: FileAccess = FileAccess.open(dat_path, FileAccess.WRITE)
	assert_not_null(dat_file, "Dat file should be created.")
	dat_file.store_string("SomeDataPayload")
	dat_file.close()

	var meta_file: FileAccess = FileAccess.open(meta_path, FileAccess.WRITE)
	assert_not_null(meta_file, "Meta file should be created.")
	var forged_meta: Dictionary = {
		"name": "Forged Slot",
		"timestamp": "2026-10-31",
		"is_favorite": false,
		"level_path": "res://levels/testbed_loader.tscn",
		"checksum": ""
	}
	meta_file.store_string(JSON.stringify(forged_meta))
	meta_file.close()

	save_manager.load_save_game(base_path)
	assert_push_error("Missing or empty checksum in metadata", "Empty checksum must log error.")


## Verifies [method SaveManager.load_save_game] aborts on checksum mismatch.
func test_tampered_checksum_mismatch() -> void:
	print("TestSaveTamperingDefense: test_tampered_checksum_mismatch() executing.")
	var base_path: String = TEST_DIR + "save_mismatch"
	var dat_path: String = base_path + ".dat"
	var meta_path: String = base_path + ".meta"

	var dat_file: FileAccess = FileAccess.open(dat_path, FileAccess.WRITE)
	assert_not_null(dat_file, "Dat file should be created.")
	dat_file.store_string("LegitimatePayload")
	dat_file.close()

	var meta_file: FileAccess = FileAccess.open(meta_path, FileAccess.WRITE)
	assert_not_null(meta_file, "Meta file should be created.")
	var forged_meta: Dictionary = {
		"name": "Tampered Slot",
		"timestamp": "2026-10-31",
		"is_favorite": false,
		"level_path": "res://levels/testbed_loader.tscn",
		"checksum": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	}
	meta_file.store_string(JSON.stringify(forged_meta))
	meta_file.close()

	save_manager.load_save_game(base_path)
	assert_push_error("Checksum mismatch", "Tampered checksum mismatch must log error.")


## Verifies unencrypted plaintext dat files are rejected by encrypted reader.
func test_unencrypted_dat_rejection() -> void:
	print("TestSaveTamperingDefense: test_unencrypted_dat_rejection() executing.")
	var raw_path: String = TEST_DIR + "raw_unencrypted.dat"
	var raw_file: FileAccess = FileAccess.open(raw_path, FileAccess.WRITE)
	assert_not_null(raw_file, "Raw unencrypted file should be created.")
	raw_file.store_string("PlaintextNotEncryptedPayload")
	raw_file.close()

	save_manager._load_game_state(raw_path)
	assert_engine_error("ERR_FILE_UNRECOGNIZED", "Engine should reject unrecognized encryption.")
	assert_push_error("Failed opening encrypted save file", "Rejection must log push_error.")


## Verifies [method Player._extract_float_from_dict] rejects NaN and Inf values.
func test_player_nan_inf_sanitization() -> void:
	print("TestSaveTamperingDefense: test_player_nan_inf_sanitization() executing.")
	var player_node: Player = Player.new()
	autofree(player_node)

	var corrupted_dict: Dictionary = {
		"nan_val": NAN, "inf_val": INF, "neg_inf_val": -INF, "valid_val": 42.5
	}

	var res_nan: float = player_node.call(
		&"_extract_float_from_dict", corrupted_dict, "nan_val", 10.0
	)
	var res_inf: float = player_node.call(
		&"_extract_float_from_dict", corrupted_dict, "inf_val", 20.0
	)
	var res_neg_inf: float = player_node.call(
		&"_extract_float_from_dict", corrupted_dict, "neg_inf_val", 30.0
	)
	var res_valid: float = player_node.call(
		&"_extract_float_from_dict", corrupted_dict, "valid_val", 0.0
	)

	assert_eq(res_nan, 10.0, "NaN float must be discarded and replaced with default.")
	assert_eq(res_inf, 20.0, "INF float must be discarded and replaced with default.")
	assert_eq(res_neg_inf, 30.0, "-INF float must be discarded and replaced with default.")
	assert_eq(res_valid, 42.5, "Finite float must be retained.")


## Verifies [method PlayerStatsComponent.load_save_data] bounds and clamps loaded health.
func test_stats_component_health_clamping() -> void:
	print("TestSaveTamperingDefense: test_stats_component_health_clamping() executing.")
	var stats: PlayerStatsComponent = PlayerStatsComponent.new()
	add_child_autoqfree(stats)

	var health_comp: HealthComponent = HealthComponent.new()
	health_comp.name = "HealthComponent"
	health_comp.max_health = 100
	health_comp.current_health = 100
	stats.add_child(health_comp)
	stats.health_component = health_comp

	stats.load_save_data({"health": 999999})
	assert_eq(health_comp.current_health, 100, "Excessive health must clamp to max_health.")

	stats.load_save_data({"health": -500})
	assert_eq(health_comp.current_health, 1, "Negative health must clamp to minimum bound 1.")
