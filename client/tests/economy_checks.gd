extends RefCounted
## Deterministic checks against formulas in contracts/schemas/economy.schema.json.
const Math = preload("res://scripts/simulation/economy_math.gd")

static func run(data: Dictionary, initial: Dictionary, check: Callable) -> void:
	var save: Dictionary = initial.duplicate(true)
	var venue: Dictionary = Math.item(data, "venues", str(save.venue))
	var band: Dictionary = Math.item(data, "band_levels", str(save.band_level))
	var rate: float = maxf(0.0, float(venue.offline_income_per_minute) * float(band.tip_multiplier) - float(band.upkeep_per_hour) / 60.0)
	check.call(is_equal_approx(Math.income_per_minute(data, save), rate), "offline base income matches contract formula")
	var minimum: float = float(data.economy.offline.min_away_seconds)
	check.call(int(Math.offline_earnings(data, save, minimum - 1).granted_amount) == 0, "offline minimum away gate")
	check.call(int(Math.offline_earnings(data, save, -minimum).granted_amount) == 0, "clock rollback cannot grant money")
	var cap: float = minf(float(venue.offline_cap_hours), float(data.economy.offline.max_cap_hours))
	var capped: Dictionary = Math.offline_earnings(data, save, cap * 7200.0)
	check.call(int(capped.granted_amount) == int(floor(rate * cap * 60.0)), "offline earnings cap")
	check.call(bool(capped.capped) and int(capped.counted_seconds) == int(cap * 3600.0), "offline cap metadata")
	check.call(int(Math.offline_earnings(data, save, cap * 3600.0).granted_amount) == int(capped.granted_amount), "extra absent time cannot exceed cap")
	for upgrade: Dictionary in data.upgrades:
		var level: int = int(upgrade.max_level)
		check.call(Math.upgrade_cost(data, str(upgrade.id), level - 1) == int(ceil(float(upgrade.base_cost) * pow(float(upgrade.cost_growth), level - 1))), "upgrade price curve: " + str(upgrade.id))
		for effect: Dictionary in upgrade.effects:
			save.upgrades = {str(upgrade.id): level}
			var expected: float = 1.0 + float(effect.per_level) * level if str(effect.op) == "add" else pow(float(effect.per_level), level)
			check.call(is_equal_approx(Math.stat(data, save, str(effect.stat)), expected), "upgrade effect: " + str(upgrade.id) + "/" + str(effect.stat))
	save = initial.duplicate(true)
	for upgrade: Dictionary in data.upgrades:
		save.upgrades[str(upgrade.id)] = int(upgrade.max_level)
	check.call(Math.table_count(data, save) <= int(venue.max_tables), "table capacity respects venue max")
	check.call(float(Math.offline_earnings(data, save, 1000000).cap_hours) <= float(data.economy.offline.max_cap_hours), "global offline cap respects data")
	var curve: Array = data.economy.tips.mood_curve
	check.call(is_equal_approx(Math.curve(curve, float(curve[0].x) - 1.0), float(curve[0].y)), "mood curve lower clamp")
	check.call(is_equal_approx(Math.curve(curve, float(curve.back().x) + 1.0), float(curve.back().y)), "mood curve upper clamp")
	var midpoint: float = (float(curve[0].x) + float(curve[1].x)) / 2.0
	check.call(is_equal_approx(Math.curve(curve, midpoint), (float(curve[0].y) + float(curve[1].y)) / 2.0), "piecewise mood interpolation")
	# A temporary double-income event covers exactly half of a valid absence.
	save = initial.duplicate(true)
	var period: float = maxf(minimum, 600.0)
	var start: float = Time.get_unix_time_from_datetime_string("2026-01-01T00:00:00Z")
	var events: Array = [{"id": "test_income", "starts_at": Time.get_datetime_string_from_unix_time(int(start)) + "Z", "ends_at": Time.get_datetime_string_from_unix_time(int(start + period / 2.0)) + "Z", "modifiers": [{"stat": "income", "value": 2.0}]}]
	check.call(int(Math.offline_earnings(data, save, period, events, start + period).granted_amount) == int(floor(rate * period / 60.0 * 1.5)), "live event applies only to overlapping offline time")
	events[0].modifiers[0].guest_type = str(data.guest_types[0].id)
	check.call(int(Math.offline_earnings(data, save, period, events, start + period).granted_amount) == int(floor(rate * period / 60.0)), "guest-scoped offline bonus waits for agreed aggregate formula")
	events[0].modifiers[0].erase("guest_type")
	# Ended and upcoming modifiers must not affect this absence.
	events[0].starts_at = Time.get_datetime_string_from_unix_time(int(start + period)) + "Z"
	events[0].ends_at = Time.get_datetime_string_from_unix_time(int(start + period * 2.0)) + "Z"
	check.call(int(Math.offline_earnings(data, save, period, events, start + period).granted_amount) == int(floor(rate * period / 60.0)), "upcoming live event does not pay early")
