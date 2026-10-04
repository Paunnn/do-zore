extends RefCounted
## No Nodes, UI or network access: deterministic with an injected RNG seed.

const Math = preload("res://scripts/simulation/economy_math.gd")
signal changed
signal event_raised(event: Dictionary)
signal event_resolved(outcome: Dictionary)
signal song_played(song_id: String)
signal notice(key: String, args: Dictionary)
signal audio_requested(cue: String)

var data: Dictionary = {}
var rules: Dictionary = {}
var save: Dictionary = {}
var tables: Array = []
var room_mood: float = 0.0
var current_song: String = ""
var song_remaining: float = 0.0
var active_event: Dictionary = {}
var event_remaining: float = 0.0
var closed_remaining: float = 0.0
var modifiers: Array = []
var live_modifiers: Dictionary = {}
var event_cooldowns: Dictionary = {}
var global_event_cooldown: float = 0.0
var arrival_remaining: float = 0.0
var event_roll_remaining: float = 0.0
var condition_remaining: float = 0.0
var glass_remaining: float = 0.0
var upkeep_remainder: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func configure(bundle: Dictionary, extra_rules: Dictionary, player_save: Dictionary, seed_value: int = -1) -> void:
	data = bundle
	rules = extra_rules
	save = player_save
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	room_mood = float(data.economy.mood.neutral)
	# A new night starts with a guest at the door instead of a minute of empty tables.
	arrival_remaining = minf(arrival_interval(), float(rules.get("first_arrival_seconds", INF)))
	event_roll_remaining = float(data.economy.events.roll_interval_seconds)
	condition_remaining = float(data.economy.events.condition_check_interval_seconds)
	glass_remaining = float(data.economy.get("glasses", {}).get("roll_interval_seconds", 0.0))
	refresh_tables()
	var client: Dictionary = save.get("client", {})
	if client.has("simulation") and client.simulation is Dictionary:
		restore(client.simulation)

func item(collection: String, id: String) -> Dictionary:
	return Math.item(data, collection, id)

func venue() -> Dictionary:
	return item("venues", str(save.venue))

func band() -> Dictionary:
	return item("band_levels", str(save.band_level))

func stat(name: String, base: float = 1.0) -> float:
	return Math.stat(data, save, name, base, modifiers)

func live_stat(name: String, guest_type: String = "") -> float:
	var by_type: Dictionary = live_modifiers.get(name, {})
	return float(by_type.get(guest_type, by_type.get("", 1.0)))

func guest_count() -> int:
	var count: int = 0
	for table: Dictionary in tables:
		count += int(table.get("party_size", 0))
	return count

func known_songs() -> Array:
	var result: Array = []
	for song: Dictionary in data.songs:
		if song.id in save.unlocked_songs and song_available(song):
			result.append(song)
	return result

func song_available(song: Dictionary) -> bool:
	var minimum: Dictionary = item("band_levels", str(song.min_band_level))
	return int(band().order) >= int(minimum.order) and song.genre in band().genres and (not bool(song.is_hit) or bool(band().can_play_hits))

func venue_unlocked(id: String) -> bool:
	return int(venue().order) >= int(item("venues", id).get("order", 0))

func menu() -> Array:
	var result: Array = []
	for entry: Dictionary in data.drinks:
		if venue_unlocked(str(entry.unlock_venue)):
			result.append(entry)
	return result

func empty_table(index: int) -> Dictionary:
	return {"index": index, "guest_type": "", "party_size": 0, "mood": float(data.economy.mood.neutral), "request_genre": "", "request_song": "", "order_item": "", "order_status": "", "prep_remaining": 0.0, "stay_remaining": 0.0, "dancing": false, "orders_served": 0, "bill": 0, "waiting_seconds": 0.0, "request_remaining": 0.0, "next_order_remaining": 0.0, "preferred_served": false, "glass_bonus_remaining": 0.0, "last_paid": 0}

func refresh_tables() -> void:
	var count: int = Math.table_count(data, save)
	while tables.size() < count:
		tables.append(empty_table(tables.size()))
	while tables.size() > count:
		depart(tables.size() - 1, true)
		tables.pop_back()
	recalculate_mood()

func spawn_guest(guest_type: String = "", table_index: int = -1) -> bool:
	if closed_remaining > 0.0:
		return false
	if table_index < 0:
		for index: int in range(tables.size()):
			if str(tables[index].guest_type).is_empty():
				table_index = index
				break
	if table_index < 0 or table_index >= tables.size() or not str(tables[table_index].guest_type).is_empty():
		return false
	if guest_type.is_empty():
		var weighted: Array = []
		for id: String in venue().guest_mix:
			weighted.append({"id": id, "weight": float(venue().guest_mix[id]) * live_stat("arrival_rate", id)})
		guest_type = str(weighted_pick(weighted).get("id", ""))
	var guest: Dictionary = item("guest_types", guest_type)
	if guest.is_empty():
		return false
	var table: Dictionary = empty_table(table_index)
	table.guest_type = guest_type
	table.party_size = rng.randi_range(int(guest.party_size.min), int(guest.party_size.max))
	table.mood = float(data.economy.mood.table_start)
	table.stay_remaining = float(guest.stay_seconds)
	tables[table_index] = table
	request_song(table)
	create_order(table)
	increment("guests_arrived", int(table.party_size))
	recalculate_mood()
	return true

func create_order(table: Dictionary) -> void:
	var guest: Dictionary = item("guest_types", str(table.guest_type))
	if int(table.orders_served) >= int(guest.orders_per_visit):
		return
	var available: Array = menu()
	var chosen: Dictionary = item("drinks", str(guest.preferred_drink))
	if not venue_unlocked(str(chosen.unlock_venue)):
		chosen = available[rng.randi_range(0, available.size() - 1)]
	if int(table.orders_served) > 0:
		var food: Array = available.filter(func(entry: Dictionary) -> bool: return str(entry.kind) == "food")
		if not food.is_empty():
			chosen = food[rng.randi_range(0, food.size() - 1)]
	table.order_item = str(chosen.id)
	table.order_status = "waiting"
	table.waiting_seconds = 0.0

func request_song(table: Dictionary) -> void:
	var guest: Dictionary = item("guest_types", str(table.guest_type))
	table.request_genre = str(guest.preferred_genre)
	table.request_song = ""
	table.request_remaining = float(guest.song_request_interval_seconds)
	var candidates: Array = known_songs().filter(func(song: Dictionary) -> bool: return str(song.genre) == str(guest.preferred_genre))
	if not candidates.is_empty():
		table.request_song = str(candidates[rng.randi_range(0, candidates.size() - 1)].id)
	if not current_song.is_empty() and song_remaining > 0.0:
		apply_song(table, item("songs", current_song))

func serve_table(index: int, item_id: String = "") -> bool:
	if index < 0 or index >= tables.size() or closed_remaining > 0.0:
		return false
	var table: Dictionary = tables[index]
	if str(table.guest_type).is_empty() or str(table.order_status) != "waiting":
		return false
	if item_id.is_empty():
		item_id = str(table.order_item)
	var drink: Dictionary = item("drinks", item_id)
	if drink.is_empty() or not venue_unlocked(str(drink.unlock_venue)):
		return false
	var cost: int = int(drink.cost) * int(table.party_size)
	if not spend(cost):
		return false
	table.order_item = item_id
	table.order_status = "preparing"
	table.prep_remaining = float(drink.prep_seconds) / stat("service_speed")
	audio_requested.emit("order_started")
	changed.emit()
	return true

func complete_service(table: Dictionary) -> void:
	var drink: Dictionary = item("drinks", str(table.order_item))
	var guest: Dictionary = item("guest_types", str(table.guest_type))
	var revenue: float = float(drink.price) * int(table.party_size) * float(guest.spending_power)
	revenue *= float(venue().price_multiplier) * stat("menu_price") * stat("income") * live_stat("income", str(table.guest_type))
	if float(table.glass_bonus_remaining) > 0.0 and data.economy.has("glasses"):
		revenue *= 1.0 + float(data.economy.glasses.income_bonus_fraction)
	# Each round is paid as it reaches the table; the tip comes when the party leaves.
	var paid: int = int(round(revenue))
	table.bill = int(table.bill) + paid
	table.last_paid = paid
	grant(paid)
	table.order_status = "served"
	table.orders_served = int(table.orders_served) + 1
	table.next_order_remaining = float(guest.stay_seconds) / int(guest.orders_per_visit)
	if str(drink.id) == str(guest.preferred_drink):
		table.preferred_served = true
		change_mood(table, float(data.economy.mood.preferred_drink_delta))
	increment("orders_served")
	audio_requested.emit("order_served")

func play_song(id: String) -> bool:
	var song: Dictionary = item("songs", id)
	if song.is_empty() or id not in save.unlocked_songs or not song_available(song) or closed_remaining > 0.0:
		return false
	if song_remaining > 0.0:
		return false
	current_song = id
	song_remaining = float(song.duration_seconds)
	for table: Dictionary in tables:
		if not str(table.guest_type).is_empty() and not str(table.request_genre).is_empty():
			apply_song(table, song)
	increment("songs_played")
	recalculate_mood()
	song_played.emit(id)
	audio_requested.emit("song_started")
	changed.emit()
	return true

func apply_song(table: Dictionary, song: Dictionary) -> void:
	if song.is_empty() or str(table.request_genre).is_empty():
		return
	var strength: float = 0.0
	if str(song.genre) == str(table.request_genre):
		strength = 1.0
	else:
		var preferred: Dictionary = item("genres", str(table.request_genre))
		for related: Dictionary in preferred.get("related", []):
			if str(related.genre) == str(song.genre):
				strength = float(related.strength)
	# The economy schema defines genre-strength matches, even for named wishes.
	var delta: float = float(data.economy.mood.song_mismatch_delta)
	if strength > 0.0:
		delta = float(data.economy.mood.song_match_delta) * strength * float(band().mood_multiplier)
	delta *= float(song.mood_power) * stat("song_mood_power")
	change_mood(table, delta)
	if strength > 0.0:
		table.request_genre = ""
		table.request_song = ""
		increment("requests_matched")
		audio_requested.emit("request_matched")

func tip_for(table: Dictionary) -> float:
	var guest: Dictionary = item("guest_types", str(table.guest_type))
	var tip: float = float(table.bill) * float(guest.tip_rate)
	tip *= Math.curve(data.economy.tips.mood_curve, float(table.mood)) * float(band().tip_multiplier) * stat("tip_rate")
	tip *= live_stat("tip_rate", str(table.guest_type))
	if bool(table.preferred_served):
		tip *= 1.0 + float(data.economy.tips.preferred_drink_bonus)
	return tip

## The rounds are paid on delivery, so a leaving party only adds its tip. Guests who leave
## without paying (thrown out, a closed venue) walk out on their last round as well.
func depart(index: int, pay: bool = true, with_tip: bool = true) -> void:
	var table: Dictionary = tables[index]
	if str(table.guest_type).is_empty():
		return
	if pay and with_tip:
		grant(int(floor(tip_for(table))), true)
	elif not pay:
		lose(int(table.get("last_paid", 0)))
	if int(table.orders_served) > 0:
		increment("guests_served", int(table.party_size))
	tables[index] = empty_table(index)

func tick(delta: float) -> void:
	var left: float = maxf(0.0, delta)
	while left > 0.0:
		var amount: float = minf(left, float(rules.tick_seconds))
		step_once(amount)
		left -= amount
	changed.emit()

func step_once(delta: float) -> void:
	for effect: Dictionary in modifiers:
		effect.remaining = maxf(0.0, float(effect.remaining) - delta)
	modifiers = modifiers.filter(func(effect: Dictionary) -> bool: return float(effect.remaining) > 0.0)
	for id: String in event_cooldowns:
		event_cooldowns[id] = maxf(0.0, float(event_cooldowns[id]) - delta)
	global_event_cooldown = maxf(0.0, global_event_cooldown - delta)
	if not active_event.is_empty():
		event_remaining -= delta
		if event_remaining <= 0.0:
			choose_event(str(active_event.timeout_choice))
	if closed_remaining > 0.0:
		closed_remaining = maxf(0.0, closed_remaining - delta)
		return
	upkeep_remainder += float(band().upkeep_per_hour) * delta / 3600.0
	var due: int = int(floor(upkeep_remainder))
	if due > 0:
		lose(due)
		upkeep_remainder -= due
	if song_remaining > 0.0:
		song_remaining = maxf(0.0, song_remaining - delta)
		if song_remaining == 0.0:
			current_song = ""
	for index: int in range(tables.size()):
		var table: Dictionary = tables[index]
		if str(table.guest_type).is_empty():
			continue
		var guest: Dictionary = item("guest_types", str(table.guest_type))
		table.mood = move_toward(float(table.mood), float(data.economy.mood.neutral), float(data.economy.mood.decay_per_minute) * stat("mood_decay") * float(guest.mood_sensitivity) * delta / 60.0)
		table.dancing = room_mood >= float(data.economy.mood.happy_at_or_above) and float(table.mood) >= float(data.economy.mood.happy_at_or_above) and song_remaining > 0.0
		var happy: bool = room_mood >= float(data.economy.mood.happy_at_or_above) and float(table.mood) >= float(data.economy.mood.happy_at_or_above)
		var stay_multiplier: float = float(data.economy.mood.get("happy_stay_multiplier", 1.0)) if happy else 1.0
		table.stay_remaining = float(table.stay_remaining) - delta / stay_multiplier
		table.glass_bonus_remaining = maxf(0.0, float(table.glass_bonus_remaining) - delta)
		if str(table.order_status) in ["waiting", "preparing"]:
			table.waiting_seconds = float(table.waiting_seconds) + delta
			if float(table.waiting_seconds) > float(guest.patience_seconds) * stat("patience"):
				change_mood(table, -float(data.economy.mood.waiting_penalty_per_minute) * delta / 60.0)
		# A waiter takes a waiting order by himself after a moment (sooner with better staff);
		# a tap on the table serves it at once.
		if str(table.order_status) == "waiting" and float(table.waiting_seconds) >= auto_serve_seconds():
			# Avoid repeated insufficient-money notices from automatic service.
			var ingredient_cost: int = int(item("drinks", str(table.order_item)).cost) * int(table.party_size)
			if int(save.money) >= ingredient_cost:
				serve_table(index)
		if str(table.order_status) == "preparing":
			table.prep_remaining = float(table.prep_remaining) - delta
			if float(table.prep_remaining) <= 0.0:
				complete_service(table)
		elif str(table.order_status) == "served":
			table.next_order_remaining = float(table.next_order_remaining) - delta
			if float(table.next_order_remaining) <= 0.0:
				create_order(table)
		table.request_remaining = float(table.request_remaining) - delta
		if float(table.request_remaining) <= 0.0:
			request_song(table)
		if float(table.mood) <= float(data.economy.mood.leave_at_or_below):
			depart(index, true, false)
		elif float(table.stay_remaining) <= 0.0:
			depart(index)
	recalculate_mood()
	arrival_remaining -= delta
	if arrival_remaining <= 0.0:
		spawn_guest()
		arrival_remaining = arrival_interval()
	if data.economy.has("glasses"):
		glass_remaining -= delta
	if data.economy.has("glasses") and glass_remaining <= 0.0:
		roll_glasses()
		glass_remaining = float(data.economy.glasses.roll_interval_seconds)
	condition_remaining -= delta
	if condition_remaining <= 0.0:
		check_unhappy_events()
		condition_remaining = float(data.economy.events.condition_check_interval_seconds)
	event_roll_remaining -= delta
	if event_roll_remaining <= 0.0:
		roll_event()
		event_roll_remaining = float(data.economy.events.roll_interval_seconds)

func auto_serve_seconds() -> float:
	return float(data.economy.get("service", {}).get("auto_serve_seconds", 3.0)) / stat("service_speed")

func change_mood(table: Dictionary, delta: float) -> void:
	var guest: Dictionary = item("guest_types", str(table.guest_type))
	var sensitivity: float = float(guest.get("mood_sensitivity", 1.0))
	table.mood = clampf(float(table.mood) + delta * sensitivity, float(data.economy.mood.min), float(data.economy.mood.max))

func arrival_interval() -> float:
	var rate: float = float(venue().arrivals_per_minute) * Math.curve(data.economy.arrivals.room_mood_curve, room_mood) * stat("arrival_rate")
	var mix: Dictionary = venue().guest_mix
	var weighted: float = 0.0
	var weight_sum: float = 0.0
	for id: String in mix:
		weighted += float(mix[id]) * live_stat("arrival_rate", id)
		weight_sum += float(mix[id])
	rate *= weighted / weight_sum if weight_sum > 0.0 else 1.0
	return 60.0 / rate if rate > 0.0 else INF

func recalculate_mood() -> void:
	var total: float = 0.0
	var occupied: int = 0
	for table: Dictionary in tables:
		if not str(table.guest_type).is_empty():
			total += float(table.mood)
			occupied += 1
	room_mood = total / occupied if occupied > 0 else float(data.economy.mood.neutral)

func roll_glasses() -> void:
	# Intentionally dormant until canonical /data supplies glass balance.
	if not data.economy.has("glasses") or room_mood < float(data.economy.mood.happy_at_or_above):
		return
	var glass_rules: Dictionary = data.economy.glasses
	for table: Dictionary in tables:
		if bool(table.dancing) and rng.randf() < float(glass_rules.chance_per_happy_table):
			lose(int(glass_rules.cost_per_glass))
			table.glass_bonus_remaining = float(glass_rules.bonus_duration_seconds)
			var bonus: int = int(floor(float(table.bill) * float(glass_rules.income_bonus_fraction)))
			grant(bonus)
			increment("glasses_broken")
			notice.emit("notice.glass", {"cost": int(glass_rules.cost_per_glass), "bonus": bonus})
			audio_requested.emit("glass_break")

func adjacent_unhappy_count() -> int:
	var unhappy: Array = []
	for table: Dictionary in tables:
		if not str(table.guest_type).is_empty() and float(table.mood) < float(data.economy.mood.unhappy_below):
			unhappy.append(int(table.index))
	var largest: int = 0
	var visited: Array = []
	var columns: int = int(rules.floor_columns)
	for origin: int in unhappy:
		if origin in visited:
			continue
		var cluster: Array = [origin]
		visited.append(origin)
		var cursor: int = 0
		while cursor < cluster.size():
			var index: int = int(cluster[cursor])
			cursor += 1
			for other: int in unhappy:
				var distance: int = absi(index % columns - other % columns) + absi(floori(float(index) / columns) - floori(float(other) / columns))
				if distance == 1 and other not in visited:
					cluster.append(other)
					visited.append(other)
		largest = maxi(largest, cluster.size())
	return largest

func event_eligible(event: Dictionary) -> bool:
	return active_event.is_empty() and global_event_cooldown <= 0.0 and float(event_cooldowns.get(str(event.id), 0.0)) <= 0.0 and venue_unlocked(str(event.min_venue))

func check_unhappy_events() -> void:
	for event: Dictionary in data.events:
		if str(event.trigger.kind) != "unhappy_tables" or not event_eligible(event):
			continue
		if adjacent_unhappy_count() >= int(event.trigger.min_unhappy_tables):
			var chance: float = float(event.trigger.chance) * maxf(float(data.economy.events.fight_chance_min_multiplier), stat("fight_chance"))
			if rng.randf() < chance:
				trigger_event(str(event.id))
				return

func roll_event() -> void:
	if not active_event.is_empty() or global_event_cooldown > 0.0 or rng.randf() >= float(data.economy.events.chance_per_roll):
		return
	var eligible: Array = []
	for event: Dictionary in data.events:
		if str(event.trigger.kind) == "random" and event_eligible(event):
			eligible.append({"id": event.id, "weight": event.trigger.weight})
	if not eligible.is_empty():
		trigger_event(str(weighted_pick(eligible).id))

func trigger_event(id: String) -> bool:
	var event: Dictionary = item("events", id)
	if event.is_empty() or not active_event.is_empty():
		return false
	active_event = event.duplicate(true)
	event_remaining = float(data.economy.events.decision_timeout_seconds)
	event_cooldowns[id] = float(event.cooldown_seconds)
	global_event_cooldown = float(data.economy.events.global_cooldown_seconds)
	if str(event.trigger.kind) == "unhappy_tables":
		increment("fights")
	else:
		increment("events")
	event_raised.emit(active_event)
	audio_requested.emit("event")
	changed.emit()
	return true

func event_choice_cost(choice: Dictionary) -> int:
	return Math.amount(data, save, choice.get("cost", {}))

func choose_event(choice_id: String) -> bool:
	if active_event.is_empty():
		return false
	var choice: Dictionary = {}
	for candidate: Dictionary in active_event.choices:
		if str(candidate.id) == choice_id:
			choice = candidate
	if choice.is_empty() or not spend(event_choice_cost(choice)):
		return false
	var outcome: Dictionary = weighted_pick(choice.outcomes).duplicate(true)
	outcome.event_id = str(active_event.id)
	outcome.choice_id = choice_id
	active_event = {}
	event_remaining = 0.0
	var followup: String = ""
	for effect: Dictionary in outcome.effects:
		match str(effect.type):
			"money_gain":
				grant(Math.amount(data, save, effect.amount))
			"money_loss":
				lose(Math.amount(data, save, effect.amount))
			"mood_change":
				for table: Dictionary in tables:
					if not str(table.guest_type).is_empty():
						change_mood(table, float(effect.value))
			"stat_multiplier":
				modifiers.append({"stat": effect.stat, "value": effect.value, "remaining": float(effect.duration_seconds)})
			"close_venue":
				closed_remaining = float(effect.duration_seconds)
				for index: int in range(tables.size()):
					depart(index, false, false)
				current_song = ""
				song_remaining = 0.0
			"remove_unhappy_guests":
				for index: int in range(tables.size()):
					if float(tables[index].mood) < float(data.economy.mood.unhappy_below):
						depart(index, bool(effect.pay), false)
			"spawn_guests":
				var wanted: int = int(ceil(tables.size() * float(effect.table_fraction)))
				for unused: int in range(wanted):
					spawn_guest(str(effect.guest_type))
			"trigger_event":
				followup = str(effect.event)
	recalculate_mood()
	event_resolved.emit(outcome)
	if not followup.is_empty():
		trigger_event(followup)
	changed.emit()
	return true

func weighted_pick(entries: Array) -> Dictionary:
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += float(entry.get("weight", 0.0))
	if total <= 0.0:
		return {}
	var roll: float = rng.randf() * total
	for entry: Dictionary in entries:
		roll -= float(entry.get("weight", 0.0))
		if roll < 0.0:
			return entry
	return entries.back()

func grant(amount: int, is_tip: bool = false) -> void:
	var value: int = maxi(0, amount)
	save.money = int(save.money) + value
	if is_tip:
		save.total_baksis = int(save.total_baksis) + value
	increment("money_earned", value)

func lose(amount: int) -> void:
	save.money = maxi(0, int(save.money) - maxi(0, amount))

func spend(amount: int) -> bool:
	if amount < 0 or int(save.money) < amount:
		notice.emit("notice.not_enough_money", {})
		return false
	save.money = int(save.money) - amount
	return true

func increment(key: String, amount: int = 1) -> void:
	if not save.has("stats"):
		save.stats = {}
	save.stats[key] = int(save.stats.get(key, 0)) + maxi(0, amount)

func snapshot() -> Dictionary:
	return {"tables": tables.duplicate(true), "current_song": current_song, "song_remaining": song_remaining, "active_event": active_event.duplicate(true), "event_remaining": event_remaining, "closed_remaining": closed_remaining, "modifiers": modifiers.duplicate(true), "event_cooldowns": event_cooldowns.duplicate(true), "global_event_cooldown": global_event_cooldown, "arrival_remaining": arrival_remaining, "event_roll_remaining": event_roll_remaining, "condition_remaining": condition_remaining, "glass_remaining": glass_remaining, "upkeep_remainder": upkeep_remainder, "rng_state": str(rng.state)}

func restore(state: Dictionary) -> void:
	var loaded_tables: Array = state.get("tables", [])
	for index: int in range(mini(tables.size(), loaded_tables.size())):
		if loaded_tables[index] is Dictionary:
			var table: Dictionary = empty_table(index)
			table.merge(loaded_tables[index], true)
			table.index = index
			if not str(table.guest_type).is_empty() and item("guest_types", str(table.guest_type)).is_empty():
				continue
			if not str(table.order_item).is_empty() and item("drinks", str(table.order_item)).is_empty():
				continue
			tables[index] = table
	current_song = str(state.get("current_song", ""))
	if not current_song.is_empty() and item("songs", current_song).is_empty():
		current_song = ""
	song_remaining = float(state.get("song_remaining", 0.0)) if not current_song.is_empty() else 0.0
	var saved_event: Dictionary = state.get("active_event", {})
	active_event = item("events", str(saved_event.get("id", ""))).duplicate(true)
	event_remaining = float(state.get("event_remaining", 0.0))
	closed_remaining = float(state.get("closed_remaining", 0.0))
	modifiers = state.get("modifiers", []).duplicate(true)
	event_cooldowns = state.get("event_cooldowns", {}).duplicate(true)
	global_event_cooldown = float(state.get("global_event_cooldown", 0.0))
	arrival_remaining = float(state.get("arrival_remaining", arrival_interval()))
	event_roll_remaining = float(state.get("event_roll_remaining", data.economy.events.roll_interval_seconds))
	condition_remaining = float(state.get("condition_remaining", data.economy.events.condition_check_interval_seconds))
	glass_remaining = float(state.get("glass_remaining", data.economy.get("glasses", {}).get("roll_interval_seconds", 0.0)))
	upkeep_remainder = float(state.get("upkeep_remainder", 0.0))
	if state.has("rng_state"):
		rng.state = int(str(state.rng_state))
	recalculate_mood()
