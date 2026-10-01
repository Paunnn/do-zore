extends RefCounted
## Contract-shaped local transport. Its cloud and clock survive app restarts.

func request(method: int, path: String, body: Dictionary, headers: Dictionary) -> Dictionary:
	var state: Dictionary = SaveSystem.network.get("mock_server", {})
	var now := SaveSystem.utc_now()
	var route := path.get_slice("?", 0)
	var public_route := route in ["/v1/health", "/v1/auth/device", "/v1/auth/refresh", "/v1/config", "/v1/events/active", "/v1/analytics/batch"]
	if not public_route and not str(headers.get("Authorization", "")).begins_with("Bearer "):
		return problem(401, "unauthorized")
	var response: Dictionary
	match route:
		"/v1/health":
			response = result(200, {"status": "ok", "server_time": now})
		"/v1/auth/device", "/v1/auth/refresh":
			if route.ends_with("refresh") and str(body.get("refresh_token", "")) != str(state.get("refresh_token", "missing")):
				return problem(401, "invalid_refresh_token")
			if route.ends_with("device"):
				if state.has("device_secret") and state["device_secret"] != body.get("device_secret"):
					return problem(401, "invalid_device_credentials")
				state["device_secret"] = body.get("device_secret")
			var is_new := not state.has("player_id")
			state["player_id"] = state.get("player_id", SaveSystem.network.get("device_id"))
			state["created_at"] = state.get("created_at", now)
			state["display_name"] = state.get("display_name", DataCatalog.text("mock_player_name"))
			state["refresh_token"] = Crypto.new().generate_random_bytes(32).hex_encode()
			response = result(200, {"token_type": "Bearer", "access_token": Crypto.new().generate_random_bytes(32).hex_encode(), "expires_in": 900, "refresh_token": state["refresh_token"], "refresh_expires_in": 2592000, "player_id": state["player_id"], "is_new_player": is_new})
		"/v1/auth/link/google", "/v1/auth/link/apple", "/v1/iap/validate":
			response = problem(501, "not_implemented")
		"/v1/me":
			if method == HTTPClient.METHOD_PATCH:
				if str(body.get("display_name", "")).length() < 3 or str(body.get("display_name", "")).length() > 20:
					return problem(400, "bad_request")
				state["display_name"] = str(body["display_name"])
			response = result(200, {"player_id": state.get("player_id", SaveSystem.network.get("device_id")), "display_name": state.get("display_name", DataCatalog.text("mock_player_name")), "created_at": state.get("created_at", now), "linked_providers": []})
		"/v1/save":
			var cloud: Dictionary = state.get("cloud", {})
			if method == HTTPClient.METHOD_GET:
				response = problem(404, "save_not_found") if cloud.is_empty() else result(200, cloud)
			elif not cloud.is_empty() and int(body.get("base_version", -1)) != int(cloud.get("version", 0)):
				response = result(409, {"code": "save_conflict", "server": cloud})
			else:
				var next_version := 1 if cloud.is_empty() else int(cloud["version"]) + 1
				cloud = {"version": next_version, "updated_at": now, "save": body.get("save", {}).duplicate(true)}
				state["cloud"] = cloud
				# Contract 1.0.1: uploading old last_seen preserves the unpaid away period.
				var prior := timestamp(str(state.get("last_activity", cloud["save"].get("last_seen", now))))
				var uploaded_seen := timestamp(str(cloud["save"].get("last_seen", now)))
				var activity := minf(timestamp(now), maxf(prior, uploaded_seen))
				state["last_activity"] = Time.get_datetime_string_from_unix_time(int(activity)) + "Z"
				response = result(200, {"version": cloud["version"], "updated_at": now})
		"/v1/offline-earnings/claim":
			var cloud: Dictionary = state.get("cloud", {})
			if cloud.is_empty():
				return problem(404, "save_not_found")
			if int(body.get("save_version", 0)) != int(cloud["version"]):
				return problem(409, "save_version_mismatch")
			var start := maxf(timestamp(str(body.get("last_seen", now))), timestamp(str(state.get("last_activity", now))))
			var away := maxi(0, int(Time.get_unix_time_from_system() - start))
			var computed: Dictionary = Economy.offline_earnings(cloud["save"], away)
			var claimed := maxi(0, int(body.get("claimed_amount", 0)))
			response = result(200, {"granted_amount": mini(claimed, int(computed["granted_amount"])), "claimed_amount": claimed, "computed_amount": int(computed["granted_amount"]), "away_seconds": away, "counted_seconds": int(computed["counted_seconds"]), "cap_hours": computed["cap_hours"], "capped": bool(computed["capped"]), "live_event_ids": [], "server_time": now, "data_version_hash": DataCatalog.version_hash})
			state["last_activity"] = now
		"/v1/config":
			var etag := '"' + DataCatalog.version_hash + '"'
			if str(headers.get("If-None-Match", "")) in [etag, DataCatalog.version_hash]:
				response = result(304, {}, {"ETag": etag})
			else:
				response = result(200, {"version_hash": DataCatalog.version_hash, "generated_at": now, "min_client_version": "0.1.0", "data": DataCatalog.data.duplicate(true)}, {"ETag": etag})
		"/v1/events/active":
			response = result(200, {"server_time": now, "events": []})
		"/v1/leaderboards/weekly":
			var week := _week()
			var scores: Dictionary = state.get("weekly_scores", {})
			var has_score := scores.has(week["week_id"])
			var score := int(scores.get(week["week_id"], 0))
			var entries: Array = []
			if has_score:
				entries.append({"rank": 1, "player_id": state.get("player_id", SaveSystem.network.get("device_id")), "display_name": state.get("display_name", DataCatalog.text("mock_player_name")), "score": score})
			response = result(200, {"week_id": week["week_id"], "starts_at": week["starts_at"], "ends_at": week["ends_at"], "total_players": entries.size(), "entries": entries, "me": {"rank": 1 if has_score else null, "score": score}})
		"/v1/leaderboards/weekly/score":
			var week := _week()
			if body.get("week_id") != week["week_id"]:
				return problem(409, "week_closed")
			var scores: Dictionary = state.get("weekly_scores", {})
			var accepted := maxi(int(scores.get(week["week_id"], 0)), int(body.get("score", 0)))
			scores[week["week_id"]] = accepted
			state["weekly_scores"] = scores
			response = result(200, {"week_id": week["week_id"], "accepted_score": accepted, "rank": 1})
		"/v1/analytics/batch":
			var known: Dictionary = state.get("analytics_ids", {})
			var duplicates := 0
			var accepted := 0
			for event in body.get("events", []):
				var id := str(event.get("event_id", ""))
				if known.has(id):
					duplicates += 1
				else:
					known[id] = true
					accepted += 1
			state["analytics_ids"] = known
			response = result(202, {"accepted": accepted, "duplicates": duplicates})
		_:
			response = problem(404, "not_found")
	SaveSystem.network["mock_server"] = state
	SaveSystem.save_now(false)
	return response

func result(code: int, body: Dictionary, headers: Dictionary = {}) -> Dictionary:
	return {"ok": code >= 200 and code < 300 or code == 304, "http_status": code, "body": body.duplicate(true), "headers": headers}

func problem(code: int, name: String) -> Dictionary:
	return result(code, {"type": "about:blank", "title": name, "status": code, "code": name})

func timestamp(value: String) -> float:
	return Time.get_unix_time_from_datetime_string(value.trim_suffix("Z"))

func _week() -> Dictionary:
	# Europe/Belgrade uses the EU last-Sunday daylight-saving rule.
	var now := int(Time.get_unix_time_from_system())
	var year := int(Time.get_datetime_dict_from_unix_time(now)["year"])
	var summer_start := _last_sunday(year, 3) + 3600
	var summer_end := _last_sunday(year, 10) + 3600
	var offset := 7200 if now >= summer_start and now < summer_end else 3600
	var local := now + offset
	var date := Time.get_datetime_dict_from_unix_time(local)
	var days_since_monday := (int(date["weekday"]) + 6) % 7
	var monday_local := local - int(date["hour"]) * 3600 - int(date["minute"]) * 60 - int(date["second"]) - days_since_monday * 86400
	var thursday := Time.get_datetime_dict_from_unix_time(monday_local + 3 * 86400)
	var iso_year := int(thursday["year"])
	var jan_four := int(Time.get_unix_time_from_datetime_string("%04d-01-04T00:00:00" % iso_year))
	var first_monday := jan_four - ((int(Time.get_datetime_dict_from_unix_time(jan_four)["weekday"]) + 6) % 7) * 86400
	var week_number := 1 + int((monday_local - first_monday) / (7 * 86400))
	var starts := monday_local - _belgrade_offset(monday_local)
	var ends_local := monday_local + 7 * 86400
	var ends := ends_local - _belgrade_offset(ends_local)
	return {"week_id": "%04d-W%02d" % [iso_year, week_number], "starts_at": Time.get_datetime_string_from_unix_time(starts) + "Z", "ends_at": Time.get_datetime_string_from_unix_time(ends) + "Z"}

func _last_sunday(year: int, month: int) -> int:
	var last_day := int(Time.get_unix_time_from_datetime_string("%04d-%02d-31T00:00:00" % [year, month]))
	return last_day - int(Time.get_datetime_dict_from_unix_time(last_day)["weekday"]) * 86400

func _belgrade_offset(local_midnight: int) -> int:
	var year := int(Time.get_datetime_dict_from_unix_time(local_midnight)["year"])
	return 7200 if local_midnight > _last_sunday(year, 3) and local_midnight <= _last_sunday(year, 10) else 3600
