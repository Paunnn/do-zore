extends Node
## Local-only envelope. Only `save` is ever sent to the API.
const Validator = preload("res://scripts/data/schema_validator.gd")
var SAVE_PATH := "user://do_zore.json"
var BACKUP_PATH := "user://do_zore.backup.json"
var TEMP_PATH := "user://do_zore.tmp.json"

var settings: Dictionary = {"sound": true, "music": true, "language": "sr"}
var network: Dictionary = {}
var last_loaded_seen: String = ""
var had_existing_save := false
var _loaded := false
var _timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var test_directory := OS.get_environment("DO_ZORE_TEST_USER_DIR")
	if not test_directory.is_empty() and test_directory.is_absolute_path():
		DirAccess.make_dir_recursive_absolute(test_directory)
		SAVE_PATH = test_directory.path_join("do_zore.json")
		BACKUP_PATH = test_directory.path_join("do_zore.backup.json")
		TEMP_PATH = test_directory.path_join("do_zore.tmp.json")
	var envelope := _read_envelope(SAVE_PATH)
	if envelope.is_empty():
		envelope = _read_envelope(BACKUP_PATH)
	if envelope.is_empty():
		envelope = _read_envelope(TEMP_PATH)
	if not envelope.is_empty():
		GameState.import_save(envelope["save"])
		had_existing_save = true
		last_loaded_seen = str(envelope["save"].get("last_seen", ""))
		if envelope.get("settings") is Dictionary:
			for key in settings:
				if envelope["settings"].has(key):
					settings[key] = envelope["settings"][key]
		if envelope.get("network") is Dictionary:
			network = envelope["network"]
	settings["sound"] = bool(settings["sound"])
	settings["music"] = bool(settings["music"])
	if str(settings["language"]) not in ["sr", "en"]:
		settings["language"] = "sr"
	DataCatalog.set_locale(str(settings["language"]))
	_loaded = true
	_timer = Timer.new()
	_timer.wait_time = maxf(1.0, float(DataCatalog.settings.get("autosave_interval_seconds", 20)))
	_timer.timeout.connect(save_now)
	add_child(_timer)
	_timer.start()

func _notification(what: int) -> void:
	if not _loaded:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()
		if is_instance_valid(_timer):
			_timer.stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED and is_instance_valid(_timer):
		_timer.start()

func set_setting(key: String, value: Variant) -> void:
	if not settings.has(key):
		return
	if key == "language":
		if str(value) not in ["sr", "en"]:
			return
		settings[key] = str(value)
		DataCatalog.set_locale(str(value))
	else:
		settings[key] = bool(value)
	save_now()

func save_now(update_last_seen: bool = true) -> bool:
	if not _loaded:
		return false
	if update_last_seen:
		GameState.save["last_seen"] = utc_now()
	var envelope := {
		"format_version": 1,
		"save": GameState.export_save(),
		"settings": settings.duplicate(true),
		"network": network.duplicate(true)
	}
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		EventBus.notice.emit("notice_save_failed", {})
		return false
	file.store_string(JSON.stringify(envelope, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		EventBus.notice.emit("notice_save_failed", {})
		return false
	var path := ProjectSettings.globalize_path(SAVE_PATH)
	var backup := ProjectSettings.globalize_path(BACKUP_PATH)
	var temporary := ProjectSettings.globalize_path(TEMP_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		if _read_envelope(SAVE_PATH).is_empty():
			# Never replace a valid backup with the corrupt primary just recovered from.
			if DirAccess.remove_absolute(path) != OK:
				EventBus.notice.emit("notice_save_failed", {})
				return false
		else:
			if FileAccess.file_exists(BACKUP_PATH):
				DirAccess.remove_absolute(backup)
			if DirAccess.rename_absolute(path, backup) != OK:
				EventBus.notice.emit("notice_save_failed", {})
				return false
	if DirAccess.rename_absolute(temporary, path) != OK:
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.rename_absolute(backup, path)
		EventBus.notice.emit("notice_save_failed", {})
		return false
	return true

func reset_progress() -> void:
	GameState.reset_progress()
	last_loaded_seen = ""
	var api := get_node_or_null("/root/ApiClient")
	if api != null:
		api.reset_for_progress()
	save_now()
	EventBus.notice.emit("notice_progress_reset", {})

func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or not parsed.get("save") is Dictionary:
		return {}
	var saved: Dictionary = parsed["save"]
	var validator = Validator.new()
	if not validator.valid(saved, validator.schemas["save.schema.json"], "save.schema.json"):
		return {}
	for key in ["schema_version", "money", "total_baksis", "venue", "band_level", "upgrades", "unlocked_songs", "last_seen"]:
		if not saved.has(key):
			return {}
	if not saved["upgrades"] is Dictionary or not saved["unlocked_songs"] is Array:
		return {}
	if DataCatalog.get_item("venues", str(saved["venue"])).is_empty() or DataCatalog.get_item("band_levels", str(saved["band_level"])).is_empty():
		return {}
	if not saved["money"] is float and not saved["money"] is int:
		return {}
	if float(saved["money"]) < 0.0 or float(saved["total_baksis"]) < 0.0:
		return {}
	return parsed

func utc_now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
