extends Node
## Bridges pure gameplay to application signals. Network never gates a mutation.
const Simulation = preload("res://scripts/simulation/kafana_simulation.gd")
const Math = preload("res://scripts/simulation/economy_math.gd")
var save: Dictionary = {}
var simulation: RefCounted
var rules: Dictionary = {}
var _accumulator: float = 0.0
var _backgrounded: bool = false

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/simulation.json"))
	rules = parsed if parsed is Dictionary else {}
	initialize()

func fresh_save() -> Dictionary:
	var venues: Array = DataCatalog.items("venues").duplicate()
	var bands: Array = DataCatalog.items("band_levels").duplicate()
	venues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order))
	bands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order))
	return {"schema_version": 1, "money": int(DataCatalog.data.economy.start.money), "total_baksis": 0, "venue": str(venues[0].id), "band_level": str(bands[0].id), "upgrades": {}, "unlocked_songs": [], "last_seen": Time.get_datetime_string_from_system(true) + "Z", "stats": {}, "client": {}}

func initialize(player_save: Dictionary = {}) -> void:
	save = fresh_save() if player_save.is_empty() else player_save.duplicate(true)
	if not save.has("stats"):
		save.stats = {}
	if not save.has("client"):
		save.client = {}
	simulation = Simulation.new()
	simulation.configure(DataCatalog.data, rules, save)
	_unlock_free_songs()
	simulation.changed.connect(func() -> void: EventBus.state_changed.emit())
	simulation.event_raised.connect(func(event: Dictionary) -> void: EventBus.event_raised.emit(event))
	simulation.event_resolved.connect(func(outcome: Dictionary) -> void: EventBus.event_resolved.emit(outcome))
	simulation.song_played.connect(func(id: String) -> void: EventBus.song_played.emit(id))
	simulation.notice.connect(func(key: String, args: Dictionary) -> void: EventBus.notice.emit(key, args))
	simulation.audio_requested.connect(func(cue: String) -> void: EventBus.audio_requested.emit(cue))
	_accumulator = 0.0
	EventBus.state_changed.emit()

func _process(delta: float) -> void:
	if _backgrounded or simulation == null:
		return
	_accumulator += delta
	if _accumulator >= float(rules.tick_seconds):
		step(_accumulator)
		_accumulator = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_backgrounded = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_backgrounded = false
		_accumulator = 0.0

func step(delta: float) -> void:
	var api: Node = get_node_or_null("/root/ApiClient")
	if api != null and api.has_method("live_multiplier"):
		for stat_name: String in ["income", "tip_rate", "arrival_rate"]:
			var multipliers: Dictionary = {"": float(api.live_multiplier(stat_name))}
			for guest: Dictionary in DataCatalog.items("guest_types"):
				multipliers[str(guest.id)] = float(api.live_multiplier(stat_name, str(guest.id)))
			simulation.live_modifiers[stat_name] = multipliers
	simulation.tick(delta)

func export_save() -> Dictionary:
	save.client.simulation = simulation.snapshot()
	return save.duplicate(true)

func import_save(value: Dictionary) -> void:
	initialize(value)
	if not simulation.active_event.is_empty():
		EventBus.event_raised.emit(simulation.active_event)

func reset_progress() -> void:
	initialize()

func refresh_data() -> void:
	var previous: Dictionary = export_save()
	if DataCatalog.get_item("venues", str(previous.venue)).is_empty() or DataCatalog.get_item("band_levels", str(previous.band_level)).is_empty():
		return
	initialize(previous)

func room_mood() -> float:
	return simulation.room_mood

func guest_count() -> int:
	return simulation.guest_count()

func known_songs() -> Array:
	return simulation.known_songs()

func venue() -> Dictionary:
	return simulation.venue()

func band() -> Dictionary:
	return simulation.band()

func menu() -> Array:
	return simulation.menu()

func play_song(id: String) -> bool:
	return simulation.play_song(id)

func serve_table(index: int, item_id: String = "") -> bool:
	return simulation.serve_table(index, item_id)

func choose_event(choice_id: String) -> bool:
	return simulation.choose_event(choice_id)

func event_choice_cost(choice: Dictionary) -> int:
	return simulation.event_choice_cost(choice)

func purchase_reason(kind: String, id: String) -> String:
	var entry: Dictionary = DataCatalog.get_item(kind, id)
	if entry.is_empty():
		return "purchase_unavailable"
	var cost: int = 0
	match kind:
		"upgrades":
			var level: int = int(save.upgrades.get(id, 0))
			if level >= int(entry.max_level):
				return "purchase_max_level"
			if not simulation.venue_unlocked(str(entry.unlock_venue)):
				return "purchase_venue_required"
			for effect: Dictionary in entry.effects:
				if str(effect.stat) == "table_count" and simulation.tables.size() >= int(venue().max_tables):
					return "purchase_table_limit"
			cost = Math.upgrade_cost(DataCatalog.data, id, level)
		"band_levels":
			if int(entry.order) <= int(band().order):
				return "purchase_owned"
			if int(entry.order) != int(band().order) + 1:
				return "purchase_previous_required"
			if not simulation.venue_unlocked(str(entry.required_venue)):
				return "purchase_venue_required"
			cost = int(entry.unlock_cost)
		"venues":
			if int(entry.order) <= int(venue().order):
				return "purchase_owned"
			if int(entry.order) != int(venue().order) + 1:
				return "purchase_previous_required"
			cost = int(entry.unlock_cost)
		"songs":
			if id in save.unlocked_songs:
				return "purchase_owned"
			if not simulation.song_available(entry):
				return "purchase_band_required"
			cost = int(entry.unlock_cost)
		_:
			return "purchase_unavailable"
	return "notice.not_enough_money" if int(save.money) < cost else ""

func _purchase(kind: String, id: String) -> bool:
	var reason: String = purchase_reason(kind, id)
	if not reason.is_empty():
		EventBus.notice.emit(reason, {})
		return false
	var entry: Dictionary = DataCatalog.get_item(kind, id)
	var cost: int = Math.upgrade_cost(DataCatalog.data, id, int(save.upgrades.get(id, 0))) if kind == "upgrades" else int(entry.unlock_cost)
	if not simulation.spend(cost):
		return false
	match kind:
		"upgrades":
			save.upgrades[id] = int(save.upgrades.get(id, 0)) + 1
		"band_levels":
			save.band_level = id
			_unlock_free_songs()
		"venues":
			save.venue = id
		"songs":
			save.unlocked_songs.append(id)
	simulation.refresh_tables()
	var api: Node = get_node_or_null("/root/ApiClient")
	if api != null and api.has_method("queue_analytics"):
		api.queue_analytics("upgrade_bought", {"kind": kind, "id": id, "cost": cost})
	EventBus.audio_requested.emit("purchase")
	EventBus.state_changed.emit()
	return true

func buy_upgrade(id: String) -> bool:
	return _purchase("upgrades", id)

func buy_band(id: String) -> bool:
	return _purchase("band_levels", id)

func buy_venue(id: String) -> bool:
	return _purchase("venues", id)

func unlock_song(id: String) -> bool:
	return _purchase("songs", id)

func _unlock_free_songs() -> void:
	for song: Dictionary in DataCatalog.items("songs"):
		if int(song.unlock_cost) == 0 and simulation.song_available(song) and str(song.id) not in save.unlocked_songs:
			save.unlocked_songs.append(str(song.id))
