extends Node
## Only this node resolves player-facing text. English falls back to Serbian.
const Validator = preload("res://scripts/data/schema_validator.gd")
var data: Dictionary = {}
var version_hash: String = ""
var settings: Dictionary = {}
var strings: Dictionary = {}
var locale: String = "sr"
var text_index: Dictionary = {}

func _ready() -> void:
	strings = _read_json("res://localization/strings.json")
	settings = _read_json("res://config/client.json")
	var bundle: Dictionary = _read_json("res://data/bundle.json")
	data = bundle.get("data", {})
	version_hash = bundle.get("version_hash", "")
	_index_text(data)

func _read_json(path: String) -> Dictionary:
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return result if result is Dictionary else {}

func items(collection: String) -> Array:
	return data.get(collection, [])

func get_item(collection: String, id: String) -> Dictionary:
	for item in items(collection):
		if item.id == id: return item
	return {}

func text(key: String, args: Dictionary = {}) -> String:
	var value: Dictionary = strings.get(key, {})
	var result: String = str(value.get(locale, ""))
	if result.is_empty(): result = str(value.get("sr", key))
	return result.format(args)

func localized(value: Variant) -> String:
	if value is Dictionary:
		var key: String = text_index.get(str(value.get("sr", "")), "")
		if not key.is_empty(): return text(key)
		return str(value.get(locale, value.get("sr", "")))
	return text(str(value)) if strings.has(str(value)) else str(value)

func set_locale(value: String) -> void:
	locale = value if value in ["sr", "en"] else "sr"
	EventBus.locale_changed.emit()

func _index_text(value: Variant, path: String = "data", replace: bool = false) -> void:
	if value is Dictionary:
		if value.has("sr"):
			text_index[str(value.sr)] = path
			# Remote content enters the same central in-memory string registry.
			if replace or not strings.has(path): strings[path] = value.duplicate(true)
		else:
			for key in value: _index_text(value[key], path + "." + str(key), replace)
	elif value is Array:
		for index in value.size():
			var entry: Variant = value[index]
			var id: String = str(entry.get("id", index)) if entry is Dictionary else str(index)
			_index_text(entry, path + "." + id, replace)

func apply_remote_config(response: Dictionary) -> bool:
	if not response.get("data") is Dictionary: return false
	if str(response.get("version_hash", "")).length() != 64: return false
	var minimum: PackedStringArray = str(response.get("min_client_version", "0.0.0")).split(".")
	var current: PackedStringArray = str(settings.get("app_version", "0.1.0")).split(".")
	for index in mini(minimum.size(), current.size()):
		if int(minimum[index]) > int(current[index]): return false
		if int(minimum[index]) < int(current[index]): break
	var validator = Validator.new()
	if not validator.valid(response.data, validator.schemas["game-data.schema.json"], "game-data.schema.json"): return false
	# Reject broken references before they can reach the simulation.
	var ids: Dictionary = {}
	for collection in ["venues", "songs", "band_levels", "genres", "guest_types", "drinks", "upgrades", "events"]:
		ids[collection] = []
		for item in response.data[collection]:
			if item.id in ids[collection]: return false
			ids[collection].append(item.id)
	for guest in response.data.guest_types:
		if guest.preferred_genre not in ids.genres or guest.preferred_drink not in ids.drinks: return false
	for song in response.data.songs:
		if song.genre not in ids.genres or song.min_band_level not in ids.band_levels: return false
	for venue in response.data.venues:
		if venue.base_tables > venue.max_tables or venue.base_tables < 1: return false
		for guest in venue.guest_mix:
			if guest not in ids.guest_types: return false
	for band in response.data.band_levels:
		if band.required_venue not in ids.venues: return false
		for genre in band.genres:
			if genre not in ids.genres: return false
	for collection in ["drinks", "upgrades"]:
		for item in response.data[collection]:
			if item.unlock_venue not in ids.venues: return false
	data = response.data.duplicate(true)
	version_hash = response.version_hash
	_index_text(data, "data", true)
	if is_instance_valid(get_node_or_null("/root/GameState")): GameState.refresh_data()
	return true
