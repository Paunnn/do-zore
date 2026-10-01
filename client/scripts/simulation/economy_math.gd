extends RefCounted
## Pure balance calculations. All balancing values come from the data bundle.

static func item(data: Dictionary, collection: String, id: String) -> Dictionary:
	for entry: Dictionary in data.get(collection, []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}

static func stat(data: Dictionary, save: Dictionary, stat_name: String, base: float = 1.0, modifiers: Array = []) -> float:
	var addition: float = 0.0
	var multiplier: float = 1.0
	var owned: Dictionary = save.get("upgrades", {})
	for upgrade: Dictionary in data.get("upgrades", []):
		var level: int = int(owned.get(str(upgrade.id), 0))
		for effect: Dictionary in upgrade.get("effects", []):
			if str(effect.stat) != stat_name:
				continue
			if str(effect.op) == "add":
				addition += float(effect.per_level) * level
			else:
				multiplier *= pow(float(effect.per_level), level)
	for effect: Dictionary in modifiers:
		if str(effect.get("stat", "")) == stat_name and float(effect.get("remaining", 0.0)) > 0.0:
			multiplier *= float(effect.value)
	return (base + addition) * multiplier

static func upgrade_cost(data: Dictionary, id: String, level: int) -> int:
	var upgrade: Dictionary = item(data, "upgrades", id)
	if upgrade.is_empty():
		return 0
	return int(ceil(float(upgrade.base_cost) * pow(float(upgrade.cost_growth), level)))

static func table_count(data: Dictionary, save: Dictionary) -> int:
	var venue: Dictionary = item(data, "venues", str(save.venue))
	return mini(int(venue.max_tables), int(stat(data, save, "table_count", float(venue.base_tables))))

static func curve(points: Array, x: float) -> float:
	if points.is_empty():
		return 1.0
	if x <= float(points[0].x):
		return float(points[0].y)
	for index: int in range(1, points.size()):
		var previous: Dictionary = points[index - 1]
		var current: Dictionary = points[index]
		if x <= float(current.x):
			var width: float = float(current.x) - float(previous.x)
			return lerpf(float(previous.y), float(current.y), (x - float(previous.x)) / width)
	return float(points.back().y)

static func income_per_minute(data: Dictionary, save: Dictionary) -> float:
	var venue: Dictionary = item(data, "venues", str(save.venue))
	var band: Dictionary = item(data, "band_levels", str(save.band_level))
	var rate: float = float(venue.offline_income_per_minute)
	rate *= stat(data, save, "menu_price") * stat(data, save, "arrival_rate") * stat(data, save, "offline_income")
	rate *= float(table_count(data, save)) / float(venue.base_tables)
	rate *= float(band.tip_multiplier)
	rate -= float(band.upkeep_per_hour) / 60.0
	return maxf(0.0, rate)

static func amount(data: Dictionary, save: Dictionary, specification: Dictionary) -> int:
	var value: float = float(specification.get("fixed", 0))
	value += float(specification.get("income_minutes", 0.0)) * income_per_minute(data, save)
	return int(ceil(maxf(float(specification.get("min", 0)), value)))

static func offline_earnings(data: Dictionary, save: Dictionary, away_seconds: float, live_events: Array = [], now_unix: float = -1.0) -> Dictionary:
	var venue: Dictionary = item(data, "venues", str(save.venue))
	var offline: Dictionary = data.economy.offline
	var cap: float = minf(stat(data, save, "offline_cap_hours", float(venue.offline_cap_hours)), float(offline.max_cap_hours))
	var away: float = maxf(0.0, away_seconds)
	var counted: float = minf(away, cap * 3600.0)
	var earned: float = 0.0
	if now_unix < 0.0:
		now_unix = Time.get_unix_time_from_system()
	var period_start: float = now_unix - away
	var period_end: float = period_start + counted
	# Divide the capped absence at every live-event boundary so overlapping events
	# multiply only for the exact portion in which they overlap.
	var boundaries: Array = [period_start, period_end]
	for event: Dictionary in live_events:
		var starts: float = Time.get_unix_time_from_datetime_string(str(event.get("starts_at", "")))
		var ends: float = Time.get_unix_time_from_datetime_string(str(event.get("ends_at", "")))
		if starts > period_start and starts < period_end:
			boundaries.append(starts)
		if ends > period_start and ends < period_end:
			boundaries.append(ends)
	boundaries.sort()
	var rate: float = income_per_minute(data, save)
	for index: int in range(1, boundaries.size()):
		var interval: float = float(boundaries[index]) - float(boundaries[index - 1])
		var instant: float = (float(boundaries[index]) + float(boundaries[index - 1])) / 2.0
		earned += rate * interval / 60.0 * offline_live_multiplier(data, save, live_events, instant)
	if away < float(offline.min_away_seconds):
		earned = 0.0
		counted = 0.0
	return {"granted_amount": int(floor(earned)), "counted_seconds": int(counted), "cap_hours": cap, "capped": away > cap * 3600.0, "away_seconds": int(away)}

static func offline_live_multiplier(_data: Dictionary, _save: Dictionary, events: Array, instant: float) -> float:
	var multiplier: float = 1.0
	for event: Dictionary in events:
		var starts: float = Time.get_unix_time_from_datetime_string(str(event.get("starts_at", "")))
		var ends: float = Time.get_unix_time_from_datetime_string(str(event.get("ends_at", "")))
		if instant < starts or instant >= ends:
			continue
		for modifier: Dictionary in event.get("modifiers", []):
			if str(modifier.get("stat", "")) not in ["income", "offline_income"]:
				continue
			# The offline aggregate has no guest attribution in the contract.
			# Scoped modifiers are intentionally deferred instead of inventing weights.
			if modifier.has("guest_type"):
				continue
			multiplier *= float(modifier.value)
	return multiplier
