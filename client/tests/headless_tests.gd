extends SceneTree
## Run through run_checks.py: this test intentionally changes isolated test saves.
const EconomyChecks = preload("res://tests/economy_checks.gd")
const Simulation = preload("res://scripts/simulation/kafana_simulation.gd")
const Math = preload("res://scripts/simulation/economy_math.gd")
var failures: int = 0
var checks: int = 0
var fixtures: Dictionary = {"saves": [], "api": []}
var game: Node
var catalog: Node
var storage: Node
var api: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS " + label)
	else:
		failures += 1
		printerr("FAIL " + label)

func capture(method: String, path: String, response: Dictionary, request: Variant = null) -> Dictionary:
	var entry: Dictionary = {"method": method, "path": path, "status": int(response.http_status), "body": response.body.duplicate(true)}
	if request is Dictionary:
		entry.request = request.duplicate(true)
	fixtures.api.append(entry)
	return response

func run() -> void:
	if OS.get_environment("DO_ZORE_TEST_USER_DIR").is_empty():
		printerr("Refusing destructive tests without DO_ZORE_TEST_USER_DIR. Use tests/run_checks.py.")
		quit(2)
		return
	await process_frame
	game = root.get_node("GameState")
	catalog = root.get_node("DataCatalog")
	storage = root.get_node("SaveSystem")
	api = root.get_node("ApiClient")
	game.set_process(false)
	catalog.settings.mock_latency_ms = 0
	check(str(storage.SAVE_PATH).begins_with(OS.get_environment("DO_ZORE_TEST_USER_DIR")), "test saves are isolated")
	game.reset_progress()
	var initial: Dictionary = game.export_save()
	fixtures.saves.append(initial.duplicate(true))
	EconomyChecks.run(catalog.data, initial, check)
	check(str(catalog.locale) == "sr", "Serbian Latin is default locale")
	_test_configuration()
	_test_simulation(initial)
	_test_progression()
	await _test_api()
	await _test_ui()
	_test_persistence()
	fixtures.saves.append(game.export_save())
	var output: FileAccess = FileAccess.open(OS.get_environment("DO_ZORE_TEST_OUTPUT"), FileAccess.WRITE)
	output.store_string(JSON.stringify(fixtures, "\t"))
	output.close()
	print("Completed %d checks; %d failures." % [checks, failures])
	quit(1 if failures else 0)

func _test_configuration() -> void:
	var response: Dictionary = {"data": catalog.data.duplicate(true), "version_hash": catalog.version_hash, "min_client_version": str(catalog.settings.app_version)}
	check(catalog.apply_remote_config(response), "valid mock configuration accepted")
	var invalid: Dictionary = response.duplicate(true)
	invalid.data.venues[0].guest_mix = {}
	check(not catalog.apply_remote_config(invalid), "empty guest mix rejected")
	invalid = response.duplicate(true)
	invalid.data.genres[0].related[0].strength = 1.0
	check(not catalog.apply_remote_config(invalid), "exclusive genre strength limit enforced")
	invalid = response.duplicate(true)
	invalid.data.guest_types[0].preferred_drink = "missing_menu_item"
	check(not catalog.apply_remote_config(invalid), "broken config references rejected")
	invalid = response.duplicate(true)
	invalid.min_client_version = "999.0.0"
	check(not catalog.apply_remote_config(invalid), "incompatible config retains bundled data")
	check(catalog.apply_remote_config(response), "original config restored")

func _test_simulation(initial: Dictionary) -> void:
	var save: Dictionary = initial.duplicate(true)
	save.client = {}
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/simulation.json"))
	var sim = Simulation.new()
	sim.configure(catalog.data, rules, save, 42)
	sim.arrival_remaining = 1000000.0
	sim.event_roll_remaining = 1000000.0
	sim.condition_remaining = 1000000.0
	sim.glass_remaining = 1000000.0
	check(sim.tables.size() == int(Math.item(catalog.data, "venues", str(save.venue)).base_tables), "initial table count comes from venue")
	var guest: Dictionary = catalog.items("guest_types")[0]
	check(sim.spawn_guest(str(guest.id), 0), "guest arrives and sits")
	check(not sim.spawn_guest(str(guest.id), 0), "occupied table cannot spawn twice")
	var table: Dictionary = sim.tables[0]
	check(str(table.order_status) == "waiting" and not str(table.request_genre).is_empty(), "guest orders and requests music")
	var menu_item: Dictionary = Math.item(catalog.data, "drinks", str(table.order_item))
	var money_before: int = int(save.money)
	check(sim.serve_table(0), "serve pending order")
	check(int(save.money) == money_before - int(menu_item.cost) * int(table.party_size), "ingredients charged exactly once")
	check(not sim.serve_table(0), "double tap cannot double charge service")
	sim.tick(float(menu_item.prep_seconds) + float(rules.tick_seconds))
	check(int(table.orders_served) == 1 and int(table.bill) > 0, "prepared order adds bill")
	var matching: Dictionary = {}
	var mismatching: Dictionary = {}
	for song: Dictionary in sim.known_songs():
		if str(song.genre) == str(guest.preferred_genre):
			matching = song
		else:
			mismatching = song
	check(not matching.is_empty() and not mismatching.is_empty(), "starting repertoire supports meaningful song choices")
	table.request_song = ""
	var mood_before: float = float(table.mood)
	var expected_tip_before: float = sim.tip_for(table)
	check(sim.play_song(str(matching.id)), "known song plays")
	check(float(table.mood) > mood_before and str(table.request_genre).is_empty(), "matching song raises mood and clears wish")
	var tips: int = int(save.total_baksis)
	check(sim.tip_for(table) > expected_tip_before, "matching mood increases eventual baksis")
	check(not sim.play_song(str(matching.id)), "same active song cannot replay for rewards")
	check(not sim.play_song(str(mismatching.id)), "active song duration prevents switching spam")
	check(int(save.total_baksis) == tips, "repeated song does not duplicate tip")
	sim.current_song = ""
	sim.song_remaining = 0.0
	table.request_genre = str(guest.preferred_genre)
	table.request_song = ""
	mood_before = float(table.mood)
	check(sim.play_song(str(mismatching.id)), "different known song plays")
	check(float(table.mood) < mood_before, "mismatching music reduces mood")
	check(not sim.play_song("missing_song"), "unknown songs cannot be played")
	var bill: int = int(table.bill)
	var expected_tip: int = int(floor(sim.tip_for(table)))
	var before_departure: int = int(save.money)
	sim.depart(0)
	check(int(save.money) == before_departure + bill + expected_tip and int(save.total_baksis) == tips + expected_tip, "departure pays bill and mood-based baksis exactly once")
	sim.depart(0)
	check(int(save.money) == before_departure + bill + expected_tip, "empty table cannot pay twice")
	sim.spawn_guest(str(guest.id), 0)
	table = sim.tables[0]
	sim.spawn_guest(str(guest.id), 1)
	table.mood = float(catalog.data.economy.mood.unhappy_below) - 1.0
	sim.tables[1].mood = table.mood
	check(sim.adjacent_unhappy_count() >= 2, "nearby unhappy tables qualify for fight")
	sim.tables[0].mood = float(catalog.data.economy.mood.max)
	sim.recalculate_mood()
	check(sim.room_mood >= float(catalog.data.economy.mood.min) and sim.room_mood <= float(catalog.data.economy.mood.max), "room mood remains within contract range")
	var event: Dictionary = catalog.items("events")[0]
	check(sim.trigger_event(str(event.id)), "event can open")
	check(not sim.choose_event("missing_choice"), "invalid event choice rejected")
	var paid: Dictionary = {}
	for choice: Dictionary in event.choices:
		if sim.event_choice_cost(choice) > 0:
			paid = choice
	if not paid.is_empty():
		save.money = 0
		check(not sim.choose_event(str(paid.id)) and not sim.active_event.is_empty(), "unaffordable event choice preserves event")
	check(sim.choose_event(str(event.timeout_choice)), "free event choice resolves")
	check(sim.active_event.is_empty(), "resolved event closes")
	check(not sim.event_eligible(event), "event cooldown prevents immediate retrigger")
	var snapshot: Dictionary = sim.snapshot()
	var restored = Simulation.new()
	restored.configure(catalog.data, rules, save.duplicate(true), 7)
	restored.restore(snapshot)
	check(restored.snapshot() == snapshot, "simulation roundtrip preserves tables timers and RNG")
	fixtures.saves.append(save.duplicate(true))

func _test_progression() -> void:
	game.reset_progress()
	var start: Dictionary = game.export_save()
	var venues: Array = catalog.items("venues").duplicate(true)
	venues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order))
	game.save.money = 0
	check(not game.buy_venue(str(venues[1].id)), "venue purchase requires money")
	game.save.money = int(venues.back().unlock_cost)
	check(not game.buy_venue(str(venues.back().id)), "venue progression cannot skip tiers")
	for index: int in range(1, venues.size()):
		game.save.money = int(venues[index].unlock_cost)
		check(game.buy_venue(str(venues[index].id)), "venue progression: " + str(venues[index].id))
		check(int(game.save.money) == 0, "venue exact purchase price")
	var bands: Array = catalog.items("band_levels").duplicate(true)
	bands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order))
	for index: int in range(1, bands.size()):
		game.save.money = int(bands[index].unlock_cost)
		check(game.buy_band(str(bands[index].id)), "band progression: " + str(bands[index].id))
		check(int(game.save.money) == 0, "band exact purchase price")
	for song: Dictionary in catalog.items("songs"):
		if bool(song.is_hit):
			game.save.money = int(song.unlock_cost)
			check(game.unlock_song(str(song.id)), "lead singer unlocks hit: " + str(song.id))
			check(not game.unlock_song(str(song.id)), "owned hit cannot charge twice")
	var upgrade: Dictionary = catalog.items("upgrades")[1]
	for level: int in range(int(upgrade.max_level)):
		game.save.money = Math.upgrade_cost(catalog.data, str(upgrade.id), level)
		check(game.buy_upgrade(str(upgrade.id)), "upgrade purchase level %d" % (level + 1))
	game.save.money = Math.upgrade_cost(catalog.data, str(upgrade.id), int(upgrade.max_level))
	check(not game.buy_upgrade(str(upgrade.id)), "upgrade maximum level enforced")
	fixtures.saves.append(game.export_save())
	game.import_save(start)

func _test_api() -> void:
	var response: Dictionary = capture("GET", "/v1/health", await api.get_health())
	check(int(response.http_status) == 200, "mock health")
	response = capture("POST", "/v1/auth/device", await api.login_with_device(), {"device_id": storage.network.device_id, "device_secret": storage.network.device_secret, "platform": "editor", "app_version": catalog.settings.app_version})
	var refresh: String = str(response.body.refresh_token)
	response = capture("POST", "/v1/auth/refresh", await api.refresh_tokens(refresh), {"refresh_token": refresh})
	check(int(response.http_status) == 200, "refresh token rotates")
	response = capture("POST", "/v1/auth/refresh", await api.refresh_tokens(refresh), {"refresh_token": refresh})
	check(int(response.http_status) == 401, "used refresh token rejected")
	capture("GET", "/v1/me", await api.get_me())
	capture("PATCH", "/v1/me", await api.update_me("Test Gost"), {"display_name": "Test Gost"})
	response = capture("GET", "/v1/save", await api.get_save())
	check(int(response.http_status) == 404, "new mock account has no cloud save")
	var saved: Dictionary = game.export_save()
	saved.last_seen = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 3600) + "Z"
	response = capture("PUT", "/v1/save", await api.put_save(0, saved), {"base_version": 0, "save": saved})
	check(int(response.http_status) == 200, "first cloud write")
	var version: int = int(response.body.version)
	capture("GET", "/v1/save", await api.get_save())
	response = capture("PUT", "/v1/save", await api.put_save(0, saved), {"base_version": 0, "save": saved})
	check(int(response.http_status) == 409 and response.body.has("server"), "stale cloud write returns server copy")
	var claimed: int = int(Math.offline_earnings(catalog.data, saved, 3600).granted_amount)
	var claim: Dictionary = {"last_seen": saved.last_seen, "claimed_amount": claimed, "save_version": version}
	response = capture("POST", "/v1/offline-earnings/claim", await api.claim_offline_earnings(str(saved.last_seen), claimed, version), claim)
	check(int(response.http_status) == 200 and int(response.body.granted_amount) == claimed, "mock v1.0.1 preserves pre-upload away interval")
	response = capture("POST", "/v1/offline-earnings/claim", await api.claim_offline_earnings(str(saved.last_seen), claimed, version), claim)
	check(int(response.body.granted_amount) == 0, "mock offline claim cannot pay twice")
	capture("GET", "/v1/config", await api.get_config())
	response = capture("GET", "/v1/config", await api.get_config('"' + str(catalog.version_hash) + '"'))
	check(int(response.http_status) == 304, "config ETag unchanged response")
	capture("GET", "/v1/events/active", await api.get_active_live_events())
	response = capture("GET", "/v1/leaderboards/weekly", await api.get_weekly_leaderboard())
	var week: String = str(response.body.week_id)
	capture("POST", "/v1/leaderboards/weekly/score", await api.submit_weekly_score(week, 123), {"week_id": week, "score": 123})
	response = capture("GET", "/v1/leaderboards/weekly", await api.get_weekly_leaderboard())
	check(int(response.body.me.score) == 123, "weekly score appears in mock board")
	var batch: Dictionary = {"device_id": storage.network.device_id, "session_id": api._uuid(), "platform": "editor", "app_version": catalog.settings.app_version, "data_version_hash": catalog.version_hash, "sent_at": storage.utc_now(), "events": [{"event_id": api._uuid(), "name": "test_event", "ts": storage.utc_now(), "params": {"test": true}}]}
	capture("POST", "/v1/analytics/batch", await api.post_analytics_batch(batch), batch)
	response = capture("POST", "/v1/analytics/batch", await api.post_analytics_batch(batch), batch)
	check(int(response.body.duplicates) == 1 and int(response.body.accepted) == 0, "analytics retries are idempotent")
	capture("POST", "/v1/auth/link/google", await api.link_google("test_token"), {"id_token": "test_token"})
	capture("POST", "/v1/auth/link/apple", await api.link_apple("test_token", "test_code"), {"identity_token": "test_token", "authorization_code": "test_code"})
	capture("POST", "/v1/iap/validate", await api.validate_purchase("google", "test_product", "test_transaction", "test_receipt"), {"platform": "google", "product_id": "test_product", "transaction_id": "test_transaction", "receipt": "test_receipt"})
	await api.mock_conflict()
	var local_money: int = int(game.save.money) + 17
	game.save.money = local_money
	await api.resolve_conflict(true)
	check(int(game.save.money) == local_money, "conflict keep-device retains local money")
	await api.mock_conflict()
	game.save.money = local_money + 23
	await api.resolve_conflict(false)
	check(int(game.save.money) == local_money, "conflict keep-cloud imports cloud money")
	var previous: String = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 3600) + "Z"
	api._settle_offline(previous)
	var after_offline: int = int(game.save.money)
	api._settle_offline(previous)
	check(int(game.save.money) == after_offline and after_offline > local_money, "local offline settlement pays once")
	api.demo_offline_earnings(3600)
	check(int(game.save.money) == after_offline, "offline preview cannot mint currency")
	catalog.settings.mock_network_available = false
	api.queue_analytics("test_queued", {"amount": 1})
	var queued: int = storage.network.analytics_queue.size()
	await api.sync_now()
	check(str(api.status) == "offline" and storage.network.analytics_queue.size() == queued, "offline sync retains analytics queue")
	catalog.settings.mock_network_available = true
	await api.sync_now()
	check(storage.network.analytics_queue.size() < queued, "restored mock transport drains analytics batch")

func _test_ui() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	for locale: String in ["sr", "en"]:
		storage.set_setting("language", locale)
		for tab: String in ["floor", "band", "menu", "upgrades", "venues", "settings", "leaderboard"]:
			ui._open_tab(tab)
			await process_frame
			var shown: bool = ui.floor_view.visible and ui.floor_view.world.slots.size() >= game.simulation.tables.size() if tab == "floor" else ui.body.get_child_count() > 0
			check(str(ui.active_tab) == tab and shown, "UI route " + locale + "/" + tab)
	ui._open_tab("floor")
	ui._show_songs(-1)
	check(str(ui.modal_kind) == "song" and ui.modal_body.get_child_count() > 1, "song picker popup opens")
	ui._close_modal(false)
	ui.floor_view.stage_tapped.emit()
	check(str(ui.modal_kind) == "song", "tapping the stage opens the song picker")
	ui._close_modal(false)
	game.simulation.closed_remaining = 0.0
	var world = ui.floor_view.world
	var free_table: int = -1
	for table_index in range(game.simulation.tables.size()):
		if str(game.simulation.tables[table_index].guest_type).is_empty():
			free_table = table_index
			break
	check(free_table >= 0 and game.simulation.spawn_guest("studenti", free_table), "floor test guest arrives")
	ui.floor_view.refresh()
	var slot: Dictionary = world.slots[free_table]
	var party: int = int(game.simulation.tables[free_table].party_size)
	check(not slot.locked and slot.guests.size() == mini(party, 6) and slot.guests[0].get_meta("state") == "walking", "a new party walks in from the door")
	for guest in slot.guests:
		world._seat(slot, guest)
	ui.floor_view.refresh()
	check(slot.hud.mode == "order" and slot.guests[0].current.begins_with("sit"), "seated guests show their order in a thought cloud")
	var hit: Dictionary = world.pick(world.WorldData.iso_v(slot.center) + Vector2(0, -30))
	check(str(hit.kind) == "table" and int(hit.index) == free_table, "tapping a table picks it in the world")
	var stage_hit: Dictionary = world.pick(world.WorldData.iso(1.5, 1.5, float(world.lay.stage[4])))
	check(str(stage_hit.kind) == "stage", "tapping the stage picks it in the world")
	var locked_slots: int = world.slots.size() - game.simulation.tables.size()
	check(locked_slots <= 0 or world.slots[game.simulation.tables.size()].plus.visible, "the next free table slot offers a purchase")
	var money_before_tap: int = int(game.save.money)
	ui.floor_view.table_tapped.emit(free_table)
	check(str(game.simulation.tables[free_table].order_status) == "preparing" and int(game.save.money) < money_before_tap, "tapping a waiting table serves it")
	ui.floor_view.table_tapped.emit(free_table)
	check(str(ui.modal_kind) == "song" and int(ui.modal_table) == free_table, "tapping a served table opens its details")
	ui._close_modal(false)
	game.simulation.depart(free_table)
	ui.floor_view.refresh()
	check(slot.guests.is_empty(), "leaving guests release their table")
	ui._show_offline({"granted_amount": 0, "away_seconds": 3600, "counted_seconds": 3600, "cap_hours": 2.0, "capped": false, "source": "local"})
	check(str(ui.modal_kind) == "offline", "offline earnings popup opens")
	ui._close_modal(false)
	ui._show_conflict({"version": 1, "updated_at": storage.utc_now(), "save": game.export_save()})
	check(str(ui.modal_kind) == "conflict", "save conflict popup opens")
	ui._close_modal(false)
	var event: Dictionary = catalog.items("events")[0]
	game.simulation.trigger_event(str(event.id))
	check(str(ui.modal_kind) == "event", "event popup opens")
	game.choose_event(str(event.timeout_choice))
	ui._close_modal(false)
	ui._confirm_reset()
	check(is_instance_valid(ui.modal), "reset requires confirmation popup")
	ui._close_modal(false)
	ui.queue_free()
	await process_frame
	storage.set_setting("language", "sr")

func _test_persistence() -> void:
	storage.set_setting("language", "en")
	check(str(storage.settings.language) == "en", "English settings selection persists")
	storage.set_setting("language", "unsupported")
	check(str(storage.settings.language) == "en", "unsupported locale rejected")
	storage.set_setting("sound", false)
	check(not bool(storage.settings.sound), "sound toggle persists")
	storage.set_setting("language", "sr")
	check(storage.save_now(), "save writes atomically")
	var baseline: Dictionary = game.export_save()
	check(storage.save_now(), "second write creates backup")
	check(not storage._read_envelope(str(storage.BACKUP_PATH)).is_empty(), "backup contains a valid save")
	fixtures.backup_expected_money = int(baseline.money)
	fixtures.backup_expected_language = "sr"
	# Leave primary malformed for backup_restore.gd in a fresh process. Only the
	# DO_ZORE_TEST_USER_DIR file is touched; the previous valid backup remains.
	var corrupt: FileAccess = FileAccess.open(str(storage.SAVE_PATH), FileAccess.WRITE)
	corrupt.store_string("{interrupted write")
	corrupt.close()
	check(storage._read_envelope(str(storage.SAVE_PATH)).is_empty(), "malformed primary rejected")
