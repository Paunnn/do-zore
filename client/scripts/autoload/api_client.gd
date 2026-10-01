extends Node
## Offline slice: every response is local. Real HTTP transport is intentionally deferred.
## API wrapper payloads follow contracts/openapi.yaml; mock=false fails immediately.
const MockBackend = preload("res://scripts/network/mock_backend.gd")

var status: String = "starting"
var live_events: Array = []
var cached_leaderboard: Dictionary = {}
var _mock = MockBackend.new()
var _busy := false
var _auth_busy := false
var _conflict: Dictionary = {}
var _session_id: String = ""
var _pause_seen: String = ""
var _clock_offset := 0.0
var _timer: Timer
var _generation := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_id = _uuid()
	_ensure_device()
	var cached: Variant = SaveSystem.network.get("config_cache", {})
	if cached is Dictionary and not cached.is_empty():
		DataCatalog.apply_remote_config(cached)
	live_events = SaveSystem.network.get("live_events", []).duplicate(true)
	cached_leaderboard = SaveSystem.network.get("leaderboard", {}).duplicate(true)
	_clock_offset = float(SaveSystem.network.get("clock_offset", 0.0))
	_track_weekly_tips()
	EventBus.state_changed.connect(_track_weekly_tips)
	EventBus.song_played.connect(func(song_id: String) -> void: queue_analytics("song_played", {"song_id": song_id}))
	EventBus.event_resolved.connect(func(outcome: Dictionary) -> void: queue_analytics("event_choice", {"event_id": str(outcome.get("event_id", "")), "choice_id": str(outcome.get("choice_id", ""))}))
	call_deferred("_start_session")
	_timer = Timer.new()
	_timer.wait_time = maxf(1.0, float(DataCatalog.settings.get("sync_interval_seconds", 60)))
	_timer.timeout.connect(sync_now)
	add_child(_timer)
	if OS.get_environment("DO_ZORE_TEST_USER_DIR").is_empty():
		_timer.start()

func _start_session() -> void:
	_settle_offline(SaveSystem.last_loaded_seen)
	queue_analytics("session_start", {"mock": bool(DataCatalog.settings.get("mock_enabled", true))})
	if OS.get_environment("DO_ZORE_TEST_USER_DIR").is_empty():
		await sync_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_pause_seen = SaveSystem.utc_now()
		SaveSystem.save_now()
	elif what == NOTIFICATION_APPLICATION_RESUMED and not _pause_seen.is_empty():
		var previous := _pause_seen
		_pause_seen = ""
		call_deferred("_resume", previous)

func _resume(previous: String) -> void:
	_settle_offline(previous)
	await sync_now()

func _settle_offline(previous: String) -> void:
	# Money and settled ledger are written in the same atomic local envelope.
	# An interrupted pending ledger is recovered locally, without repeating a server claim.
	var pending: Dictionary = SaveSystem.network.get("offline_pending", {})
	if pending.is_empty():
		if previous.is_empty():
			return
		var away := maxi(0, int(Time.get_unix_time_from_system() - _timestamp(previous)))
		var minimum := int(DataCatalog.data.get("economy", {}).get("offline", {}).get("min_away_seconds", 0))
		if away < minimum or str(SaveSystem.network.get("offline_last_origin", "")) == previous:
			return
		pending = {"id": _uuid(), "last_seen": previous, "result": Economy.offline_earnings(GameState.export_save(), away)}
		SaveSystem.network["offline_pending"] = pending
		if not SaveSystem.save_now(false):
			return
	var result: Dictionary = pending.get("result", {}).duplicate(true)
	if result.is_empty():
		SaveSystem.network.erase("offline_pending")
		return
	Economy.grant(maxi(0, int(result.get("granted_amount", 0))))
	SaveSystem.network["offline_last_origin"] = str(pending["last_seen"])
	SaveSystem.network["offline_last_settled_id"] = str(pending["id"])
	SaveSystem.network.erase("offline_pending")
	SaveSystem.save_now()
	result["source"] = "local"
	EventBus.offline_ready.emit(result)
	queue_analytics("offline_claim", {"source": "local", "amount": int(result.get("granted_amount", 0)), "away_seconds": int(result.get("away_seconds", 0))})

func sync_now() -> void:
	if _busy or not _conflict.is_empty():
		return
	_busy = true
	var generation := _generation
	_set_status("syncing")
	await _sync_config()
	if generation != _generation:
		_busy = false
		return
	if not await _authenticate():
		_busy = false
		_set_status("offline")
		return
	var upload := await put_save(int(SaveSystem.network.get("cloud_version", 0)), GameState.export_save())
	if generation != _generation:
		_busy = false
		return
	if int(upload["http_status"]) == 409:
		_capture_conflict(upload["body"].get("server", {}))
	elif upload["ok"]:
		SaveSystem.network["cloud_version"] = int(upload["body"].get("version", 0))
		SaveSystem.save_now(false)
	var events := await get_active_live_events()
	if events["ok"] and events["body"].get("events") is Array:
		live_events = events["body"]["events"].duplicate(true)
		SaveSystem.network["live_events"] = live_events
		_update_clock(str(events["body"].get("server_time", "")))
	await _flush_analytics()
	_busy = false
	if not _conflict.is_empty():
		_set_status("conflict")
	else:
		_set_status("mock" if upload["ok"] else "offline")
	SaveSystem.save_now(false)

func _sync_config() -> void:
	var etag := str(SaveSystem.network.get("config_etag", '"' + DataCatalog.version_hash + '"'))
	var response := await get_config(etag)
	if int(response["http_status"]) != 200:
		return
	var body: Dictionary = response["body"]
	if str(body.get("version_hash", "")) != DataCatalog.version_hash:
		if not DataCatalog.apply_remote_config(body):
			return
		EventBus.notice.emit("notice_config_updated", {})
	SaveSystem.network["config_cache"] = body.duplicate(true)
	SaveSystem.network["config_etag"] = str(response["headers"].get("ETag", '"' + DataCatalog.version_hash + '"'))
	SaveSystem.save_now(false)

func resolve_conflict(keep_local: bool) -> void:
	if _conflict.is_empty():
		return
	var server := _conflict.duplicate(true)
	if not keep_local:
		if not server.get("save") is Dictionary:
			return
		GameState.import_save(server["save"])
		SaveSystem.network.erase("offline_pending")
	SaveSystem.network["cloud_version"] = int(server.get("version", 0))
	_conflict.clear()
	SaveSystem.network.erase("save_conflict")
	SaveSystem.save_now()
	EventBus.notice.emit("notice_device_kept" if keep_local else "notice_cloud_kept", {})
	await sync_now()

func _capture_conflict(server: Dictionary) -> void:
	if server.is_empty():
		return
	_conflict = server.duplicate(true)
	SaveSystem.network["save_conflict"] = _conflict
	SaveSystem.save_now(false)
	_set_status("conflict")
	EventBus.save_conflict.emit(_conflict)

func mock_conflict() -> void:
	if not bool(DataCatalog.settings.get("mock_enabled", true)) or _busy:
		return
	if not await _authenticate():
		return
	var state: Dictionary = SaveSystem.network.get("mock_server", {})
	var cloud: Dictionary = state.get("cloud", {})
	var version := maxi(int(cloud.get("version", 0)), int(SaveSystem.network.get("cloud_version", 0))) + 1
	cloud = {"version": version, "updated_at": SaveSystem.utc_now(), "save": GameState.export_save()}
	state["cloud"] = cloud
	SaveSystem.network["mock_server"] = state
	_capture_conflict(cloud)

func demo_offline_earnings(away_seconds: int) -> void:
	if not bool(DataCatalog.settings.get("demo_tools_enabled", false)):
		return
	var result: Dictionary = Economy.offline_earnings(GameState.export_save(), maxi(0, away_seconds))
	result["source"] = "demo"
	# A preview only: demo buttons never alter player money or offline-claim ledgers.
	EventBus.offline_ready.emit(result)

func request_leaderboard() -> void:
	if not await _authenticate():
		EventBus.leaderboard_ready.emit(_leaderboard_fallback())
		return
	var response := await get_weekly_leaderboard(int(DataCatalog.settings.get("leaderboard_limit", 20)))
	if response["ok"]:
		var board: Dictionary = response["body"]
		var week_id := str(board.get("week_id", ""))
		_update_clock(str(board.get("starts_at", "")), false)
		_track_weekly_tips()
		var weekly: Dictionary = SaveSystem.network.get("weekly_tips", {})
		var score := int(weekly.get("score", 0)) if str(weekly.get("week_id", "")) == week_id else 0
		var submitted := await submit_weekly_score(week_id, score)
		if submitted["ok"]:
			response = await get_weekly_leaderboard(int(DataCatalog.settings.get("leaderboard_limit", 20)))
		if response["ok"]:
			cached_leaderboard = response["body"].duplicate(true)
			SaveSystem.network["leaderboard"] = cached_leaderboard
			SaveSystem.save_now(false)
			EventBus.leaderboard_ready.emit(cached_leaderboard)
			return
	EventBus.leaderboard_ready.emit(_leaderboard_fallback())

func _leaderboard_fallback() -> Dictionary:
	var result := cached_leaderboard.duplicate(true)
	result["offline"] = true
	return result

func queue_analytics(event_name: String, params: Dictionary = {}) -> void:
	var expression := RegEx.new()
	expression.compile("^[a-z][a-z0-9_]{1,63}$")
	if expression.search(event_name) == null:
		return
	var safe_params: Dictionary = {}
	for key in params:
		if safe_params.size() >= 32:
			break
		var value: Variant = params[key]
		if value is String or value is bool or value is int or value is float:
			safe_params[str(key)] = value
	var queue: Array = SaveSystem.network.get("analytics_queue", [])
	queue.append({"event_id": _uuid(), "name": event_name, "ts": SaveSystem.utc_now(), "params": safe_params})
	var limit := maxi(1, int(DataCatalog.settings.get("analytics_queue_limit", 2000)))
	while queue.size() > limit:
		queue.pop_front()
	SaveSystem.network["analytics_queue"] = queue
	SaveSystem.save_now(false)

func _flush_analytics() -> void:
	var queue: Array = SaveSystem.network.get("analytics_queue", [])
	if queue.is_empty():
		return
	var size := clampi(int(DataCatalog.settings.get("analytics_batch_size", 50)), 1, 500)
	var batch_events: Array = queue.slice(0, mini(size, queue.size())).duplicate(true)
	var response := await post_analytics_batch({"device_id": SaveSystem.network["device_id"], "session_id": _session_id, "platform": _platform(), "app_version": str(DataCatalog.settings.get("app_version", "0.1.0")), "data_version_hash": DataCatalog.version_hash, "sent_at": SaveSystem.utc_now(), "events": batch_events})
	if int(response["http_status"]) != 202:
		return
	var sent_ids: Dictionary = {}
	for event in batch_events:
		sent_ids[event["event_id"]] = true
	# Events can be queued while the transport yields, so remove by id instead of index.
	var remaining: Array = []
	for event in SaveSystem.network.get("analytics_queue", []):
		if not sent_ids.has(event["event_id"]):
			remaining.append(event)
	SaveSystem.network["analytics_queue"] = remaining
	SaveSystem.save_now(false)

func live_multiplier(stat: String, guest_type: String = "") -> float:
	var multiplier := 1.0
	var now := Time.get_unix_time_from_system() + _clock_offset
	for event in live_events:
		if not event is Dictionary or now < _timestamp(str(event.get("starts_at", ""))) or now >= _timestamp(str(event.get("ends_at", ""))):
			continue
		for modifier in event.get("modifiers", []):
			if str(modifier.get("stat", "")) == stat and (not modifier.has("guest_type") or str(modifier["guest_type"]) == guest_type):
				multiplier *= maxf(0.0, float(modifier.get("value", 1.0)))
	return multiplier

func reset_for_progress() -> void:
	_generation += 1
	_conflict.clear()
	for key in ["offline_pending", "offline_last_origin", "offline_last_settled_id", "save_conflict", "weekly_tips", "analytics_queue"]:
		SaveSystem.network.erase(key)
	# Reset is authoritative for the local mock cloud. A later popup cannot restore it.
	var mock_server: Dictionary = SaveSystem.network.get("mock_server", {})
	mock_server.erase("cloud")
	mock_server.erase("last_activity")
	mock_server.erase("weekly_scores")
	SaveSystem.network["mock_server"] = mock_server
	SaveSystem.network["cloud_version"] = 0
	SaveSystem.network.erase("leaderboard")
	cached_leaderboard.clear()
	_track_weekly_tips()
	SaveSystem.save_now()
	EventBus.state_changed.emit()

func _track_weekly_tips() -> void:
	var week: Dictionary = _mock._week()
	var total := int(GameState.save.get("total_baksis", 0))
	var weekly: Dictionary = SaveSystem.network.get("weekly_tips", {})
	if str(weekly.get("week_id", "")) != str(week["week_id"]):
		weekly = {"week_id": week["week_id"], "last_total": total, "score": 0}
	else:
		weekly["score"] = int(weekly.get("score", 0)) + maxi(0, total - int(weekly.get("last_total", total)))
		weekly["last_total"] = total
	SaveSystem.network["weekly_tips"] = weekly

func _authenticate() -> bool:
	if _auth_busy:
		while _auth_busy:
			await get_tree().process_frame
		return not str(SaveSystem.network.get("access_token", "")).is_empty()
	if not str(SaveSystem.network.get("access_token", "")).is_empty() and Time.get_unix_time_from_system() < float(SaveSystem.network.get("access_expires_at", 0.0)):
		return true
	_auth_busy = true
	var response: Dictionary = {}
	var refresh := str(SaveSystem.network.get("refresh_token", ""))
	if not refresh.is_empty() and Time.get_unix_time_from_system() < float(SaveSystem.network.get("refresh_expires_at", 0.0)):
		response = await refresh_tokens(refresh)
		# Rotating tokens are never replayed after an ambiguous transport failure.
		if int(response.get("http_status", 0)) == 0:
			SaveSystem.network.erase("refresh_token")
	if not response.get("ok", false):
		response = await login_with_device()
	if response.get("ok", false):
		var pair: Dictionary = response["body"]
		for key in ["access_token", "refresh_token", "player_id"]:
			SaveSystem.network[key] = pair[key]
		SaveSystem.network["access_expires_at"] = Time.get_unix_time_from_system() + int(pair.get("expires_in", 0))
		SaveSystem.network["refresh_expires_at"] = Time.get_unix_time_from_system() + int(pair.get("refresh_expires_in", 0))
		SaveSystem.save_now(false)
	_auth_busy = false
	return bool(response.get("ok", false))

func _request(method: int, path: String, body: Dictionary = {}, authenticated: bool = true, extra_headers: Dictionary = {}) -> Dictionary:
	# Intentional hard boundary for Task 1: no HTTPRequest, sockets, or outbound calls.
	if not bool(DataCatalog.settings.get("mock_enabled", true)) or not bool(DataCatalog.settings.get("mock_network_available", true)):
		return _mock.result(0, {"title": "Network integration is deferred", "status": 503, "code": "network_unavailable"})
	var generation := _generation
	var headers := extra_headers.duplicate(true)
	if authenticated:
		if not await _authenticate():
			return _mock.problem(401, "unauthorized")
		headers["Authorization"] = "Bearer " + str(SaveSystem.network.get("access_token", ""))
	var delay := maxf(0.0, float(DataCatalog.settings.get("mock_latency_ms", 100)) / 1000.0)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if generation != _generation:
		return _mock.result(0, {"title": "Request cancelled after progress reset", "status": 503, "code": "request_cancelled"})
	return _mock.request(method, path, body, headers)

# Thin endpoint wrappers: only contract fields are serialized.
func get_health() -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/health", {}, false)

func login_with_device() -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/device", {"device_id": SaveSystem.network["device_id"], "device_secret": SaveSystem.network["device_secret"], "platform": _platform(), "app_version": str(DataCatalog.settings.get("app_version", "0.1.0"))}, false)

func refresh_tokens(refresh_token: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/refresh", {"refresh_token": refresh_token}, false)

func link_google(id_token: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/link/google", {"id_token": id_token})

func link_apple(identity_token: String, authorization_code: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/auth/link/apple", {"identity_token": identity_token, "authorization_code": authorization_code})

func get_me() -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/me")

func update_me(display_name: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_PATCH, "/v1/me", {"display_name": display_name})

func get_save() -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/save")

func put_save(base_version: int, save: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, "/v1/save", {"base_version": base_version, "save": save})

func claim_offline_earnings(last_seen: String, claimed_amount: int, save_version: int) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/offline-earnings/claim", {"last_seen": last_seen, "claimed_amount": claimed_amount, "save_version": save_version})

func get_config(etag: String = "") -> Dictionary:
	var headers: Dictionary = {}
	if not etag.is_empty():
		headers["If-None-Match"] = etag
	return await _request(HTTPClient.METHOD_GET, "/v1/config", {}, false, headers)

func get_active_live_events() -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/events/active", {}, false)

func get_weekly_leaderboard(limit: int = 100) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/v1/leaderboards/weekly?limit=%d" % clampi(limit, 1, 100))

func submit_weekly_score(week_id: String, score: int) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/leaderboards/weekly/score", {"week_id": week_id, "score": maxi(0, score)})

func post_analytics_batch(batch: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/analytics/batch", batch, false)

func validate_purchase(platform: String, product_id: String, transaction_id: String, receipt: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/v1/iap/validate", {"platform": platform, "product_id": product_id, "transaction_id": transaction_id, "receipt": receipt})

func _ensure_device() -> void:
	if not SaveSystem.network.has("device_id"):
		SaveSystem.network["device_id"] = _uuid()
	if not SaveSystem.network.has("device_secret"):
		SaveSystem.network["device_secret"] = Crypto.new().generate_random_bytes(32).hex_encode()
	SaveSystem.save_now(false)

func _uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var value := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [value.substr(0, 8), value.substr(8, 4), value.substr(12, 4), value.substr(16, 4), value.substr(20, 12)]

func _platform() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("ios"):
		return "ios"
	return "editor"

func _timestamp(value: String) -> float:
	if value.is_empty():
		return Time.get_unix_time_from_system()
	return Time.get_unix_time_from_datetime_string(value.trim_suffix("Z"))

func _update_clock(server_time: String, persist: bool = true) -> void:
	if server_time.is_empty() or not persist:
		return
	_clock_offset = _timestamp(server_time) - Time.get_unix_time_from_system()
	SaveSystem.network["clock_offset"] = _clock_offset

func _set_status(value: String) -> void:
	status = value
	EventBus.sync_status_changed.emit(value)
