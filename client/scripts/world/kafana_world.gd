extends Node2D
## The isometric kafana. Builds the venue's room and furniture, and turns simulation state into
## people: guests walk in and sit down, order, dance and walk out; waiters carry trays; the band
## plays while a song is on. Presentation only: it reads the simulation and never changes it.
signal payout(world_position: Vector2, amount: int, angry: bool)

const WorldData = preload("res://scripts/world/world_data.gd")
const Person = preload("res://scripts/world/person.gd")
const TableHud = preload("res://scripts/world/table_hud.gd")
const CHAIR_GAP = 0.62
## Seats around a table: offset from the table centre in tiles, the chair sprite, whether the
## chair and sitter are mirrored, which way the sitter faces and the floor cell they walk to.
const SEATS = [
	{"offset": Vector2(-CHAIR_GAP, 0), "chair": "se", "flip": false, "view": "front", "cell": Vector2i(-1, 0)},
	{"offset": Vector2(0, -CHAIR_GAP), "chair": "se", "flip": true, "view": "front", "cell": Vector2i(0, -1)},
	{"offset": Vector2(CHAIR_GAP, 0), "chair": "nw", "flip": false, "view": "back", "cell": Vector2i(1, 0)},
	{"offset": Vector2(0, CHAIR_GAP), "chair": "nw", "flip": true, "view": "back", "cell": Vector2i(0, 1)},
]
const STANDING = [Vector2(-0.95, -0.95), Vector2(-1.0, 0.95)]
const WAITER_THRESHOLDS = [1, 4, 8]

var venue_id: String = ""
var theme: String = ""
var lay: Dictionary = {}
var background: Node2D
var actors: Node2D
var overlay: Node2D
var astar: AStarGrid2D = AStarGrid2D.new()
var slots: Array = []
var waiters: Array = []
var jobs: Array = []
var band: Array = []
var band_id: String = ""
var bartender
var bouncer
var decor: Dictionary = {}
var lights: Array = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var time: float = 0.0
var note_timer: float = 0.0
var synced_once: bool = false
var room_rect: Rect2 = Rect2()
var tint: CanvasModulate
var dust: Array = []

func build(venue: String) -> void:
	WorldData.ensure_loaded()
	venue_id = venue
	theme = venue if WorldData.world.venues.has(venue) else "kafana"
	lay = WorldData.venue_layout(theme)
	rng.seed = hash(venue)
	for child in get_children():
		child.queue_free()
	slots.clear()
	waiters.clear()
	jobs.clear()
	band.clear()
	band_id = ""
	lights.clear()
	decor.clear()
	synced_once = false
	background = Node2D.new()
	background.z_index = -10
	add_child(background)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	overlay = Node2D.new()
	overlay.z_index = 20
	add_child(overlay)
	tint = CanvasModulate.new()
	tint.color = Color.WHITE
	add_child(tint)
	dust.clear()
	var room: Sprite2D = WorldData.sprite("room_" + theme)
	background.add_child(room)
	var info: Dictionary = WorldData.info("room_" + theme)
	room_rect = Rect2(-Vector2(float(info.ox), float(info.oy)), Vector2(float(info.w), float(info.h)))
	var stage: Sprite2D = WorldData.sprite(theme + "_stage")
	stage.position = WorldData.iso(float(lay.stage[2]), float(lay.stage[3]))
	background.add_child(stage)
	_build_grid()
	_build_bar()
	_build_slots()
	_build_lights()

func _build_grid() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, int(lay.w), int(lay.d))
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for cell in lay.blocked:
		astar.set_point_solid(Vector2i(int(cell[0]), int(cell[1])))
	for table in lay.tables:
		for seat in SEATS:
			var c: Vector2i = Vector2i(int(table[0]), int(table[1])) + seat.cell
			if astar.is_in_boundsv(c):
				astar.set_point_weight_scale(c, 4.0)

func _build_bar() -> void:
	var bar: Sprite2D = WorldData.sprite(theme + "_bar")
	var bar_node: Node2D = Node2D.new()
	# Sort the long counter by its front-left end: everything in front of it has a larger y.
	bar_node.position = WorldData.iso(float(lay.bar[0]), float(lay.bar[1]) + float(lay.bar[3]))
	bar.position = WorldData.iso(float(lay.bar[0]) + float(lay.bar[2]), float(lay.bar[1]) + float(lay.bar[3])) - bar_node.position
	bar_node.add_child(bar)
	actors.add_child(bar_node)
	for spot in lay.stools:
		var stool: Sprite2D = WorldData.sprite(theme + "_stool")
		stool.position = WorldData.iso(float(spot[0]), float(spot[1]))
		actors.add_child(stool)
	bartender = _person("bartender", {"idle": [0], "wipe": [1, 2, 1, 0, 0]}, 3)
	bartender.z_index = -1
	bartender.position = WorldData.iso(float(lay.bartender[0]), float(lay.bartender[1]))
	bartender.play("wipe", 2.0)
	actors.add_child(bartender)
	bouncer = _person("bouncer", {"idle": [0, 1]}, 2)
	bouncer.position = WorldData.iso(float(lay.bouncer[0]), float(lay.bouncer[1]))
	bouncer.play("idle", 1.2)
	bouncer.sprite.flip_h = false
	actors.add_child(bouncer)
	if lay.has("poles"):
		for pole in lay.poles:
			var lantern: Sprite2D = WorldData.sprite("lantern_pole")
			lantern.position = WorldData.iso(float(pole[0]), float(pole[1]))
			actors.add_child(lantern)
			lights.append({"pos": lantern.position + Vector2(0, -160), "big": true})

func _build_slots() -> void:
	for index in range(lay.tables.size()):
		var cell: Vector2i = Vector2i(int(lay.tables[index][0]), int(lay.tables[index][1]))
		var center: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
		var slot: Dictionary = {"index": index, "cell": cell, "center": center, "guests": [], "locked": true, "party": 0,
			"kind": "", "status": "", "prep_total": 0.0, "drink": null, "nodes": [], "drink_timer": rng.randf_range(2, 6), "angry_until": -1.0}
		var table_node: Node2D = Node2D.new()
		table_node.position = WorldData.iso_v(center)
		table_node.add_child(WorldData.sprite(theme + "_table"))
		actors.add_child(table_node)
		slot.table = table_node
		slot.nodes.append(table_node)
		for seat in SEATS:
			var chair: Sprite2D = WorldData.sprite(theme + "_chair_" + seat.chair)
			chair.flip_h = seat.flip
			if seat.flip:
				chair.offset.x = -chair.offset.x - chair.texture.get_width()
			var chair_node: Node2D = Node2D.new()
			chair_node.position = WorldData.iso_v(center + seat.offset)
			chair_node.add_child(chair)
			actors.add_child(chair_node)
			slot.nodes.append(chair_node)
		var hud = TableHud.new()
		hud.position = WorldData.iso_v(center) + Vector2(0, -104)
		overlay.add_child(hud)
		slot.hud = hud
		var marker: Node2D = Node2D.new()
		marker.position = WorldData.iso_v(center)
		marker.z_index = -9
		marker.draw.connect(_draw_slot_marker.bind(marker))
		add_child(marker)
		slot.marker = marker
		var plus: Sprite2D = WorldData.sprite("fx/plus")
		plus.position = WorldData.iso_v(center) + Vector2(0, -14)
		plus.visible = false
		overlay.add_child(plus)
		slot.plus = plus
		slots.append(slot)
		_set_locked(slot, true)

func _draw_slot_marker(marker: Node2D) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for corner in [Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(1.2, 1.2), Vector2(-1.2, 1.2), Vector2(-1.2, -1.2)]:
		points.append(WorldData.iso_v(corner))
	for i in range(points.size() - 1):
		marker.draw_dashed_line(points[i], points[i + 1], Color(1, 1, 1, 0.55), 3.0, 10.0, true)
	marker.draw_colored_polygon(points, Color(1, 1, 1, 0.08))

func _set_locked(slot: Dictionary, locked: bool) -> void:
	slot.locked = locked
	for node in slot.nodes:
		node.visible = not locked
	slot.marker.visible = locked
	slot.hud.visible = not locked
	if locked:
		for guest in slot.guests:
			if is_instance_valid(guest):
				guest.queue_free()
		slot.guests = []

func _build_lights() -> void:
	var glow: Texture2D = WorldData.texture(WorldData.ROOT + "fx/glow.svg")
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for light in lay.get("lights", []):
		lights.append({"pos": Vector2(float(light[0]), float(light[1])), "big": int(light[2]) == 1})
	for light in lights:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = glow
		sprite.material = additive
		sprite.position = light.pos
		sprite.scale = Vector2.ONE * (1.6 if light.big else 0.7)
		sprite.modulate = Color(1.0, 0.82, 0.5, 0.4)
		overlay.add_child(sprite)
		light.sprite = sprite
		light.phase = rng.randf() * TAU
		light.speed = rng.randf_range(0.6, 1.5)

func _person(sheet: String, animations: Dictionary, frames: int):
	var person = Person.new()
	person.setup(sheet, animations, frames)
	return person

func _guest(look: String):
	var meta: Dictionary = WorldData.people
	return _person(look, meta.guest_anims, 20)

# --------------------------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------------------------

func _cell_at(tile: Vector2) -> Vector2i:
	var cell: Vector2i = Vector2i(floori(tile.x), floori(tile.y))
	return cell.clamp(Vector2i.ZERO, Vector2i(int(lay.w) - 1, int(lay.d) - 1))

func _path(from_tile: Vector2, to_cell: Vector2i) -> PackedVector2Array:
	var start: Vector2i = _cell_at(from_tile)
	var was_solid: bool = astar.is_point_solid(start)
	if was_solid:
		astar.set_point_solid(start, false)
	var cells: Array[Vector2i] = astar.get_id_path(start, to_cell, true)
	if was_solid:
		astar.set_point_solid(start, true)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(1, cells.size()):
		points.append(WorldData.iso(cells[i].x + 0.5, cells[i].y + 0.5))
	return points

func entry_point() -> Vector2:
	return WorldData.iso(float(lay.entry[0]), float(lay.entry[1]))

func door_point() -> Vector2:
	return WorldData.iso(0.15, float(lay.door[1]) + 0.6)

# --------------------------------------------------------------------------------------------
# Sync with the simulation
# --------------------------------------------------------------------------------------------

func sync(simulation, save: Dictionary) -> void:
	var count: int = mini(simulation.tables.size(), slots.size())
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		var open: bool = index < count
		if slot.locked == open:
			_set_locked(slot, not open)
		slot.plus.visible = index == count and count < slots.size()
		if not open:
			continue
		var table: Dictionary = simulation.tables[index]
		var previous: Dictionary = slot.get("source", {})
		if not synced_once or not is_same(previous, table):
			if synced_once and not str(previous.get("guest_type", "")).is_empty():
				_depart(slot, previous, simulation)
			if not str(table.get("guest_type", "")).is_empty():
				_arrive(slot, table, not synced_once)
			slot.source = table
		_update_slot(slot, table, simulation)
	synced_once = true
	_sync_staff(save)
	_sync_band(simulation)
	_sync_event(simulation)

## Power cuts and closing time darken the room; a fight raises a dust cloud over angry tables.
func _sync_event(simulation) -> void:
	var event_id: String = str(simulation.active_event.get("id", ""))
	var dark: bool = event_id == "nestanak_struje" or simulation.closed_remaining > 0.0
	var target: Color = Color(0.42, 0.46, 0.62) if dark else Color.WHITE
	if tint.color != target and not tint.has_meta("tweening"):
		tint.set_meta("tweening", true)
		var fade: Tween = tint.create_tween()
		fade.tween_property(tint, "color", target, 0.6)
		fade.tween_callback(func(): tint.remove_meta("tweening"))
	var fighting: Array = []
	if event_id == "tuca":
		for slot in slots:
			if not slot.locked and not slot.guests.is_empty() and float(slot.get("source", {}).get("mood", 50)) < float(DataCatalog.data.economy.mood.unhappy_below):
				fighting.append(slot)
	while dust.size() > fighting.size():
		dust.pop_back().queue_free()
	for k in range(fighting.size()):
		if k >= dust.size():
			var cloud: Sprite2D = WorldData.sprite("fx/dust")
			overlay.add_child(cloud)
			dust.append(cloud)
		dust[k].position = WorldData.iso_v(fighting[k].center) + Vector2(sin(time * 9.0 + k) * 6.0, -40 + cos(time * 7.0) * 4.0)
		dust[k].rotation = sin(time * 6.0 + k) * 0.15

func _arrive(slot: Dictionary, table: Dictionary, instant: bool) -> void:
	var kind: String = str(table.guest_type)
	var party: int = int(table.party_size)
	var looks: Array = WorldData.people.guests.get(kind, WorldData.people.guests.values()[0]).duplicate()
	looks.shuffle()
	slot.kind = kind
	slot.party = party
	slot.status = ""
	slot.angry_until = -1.0
	_clear_drink(slot)
	var shown: int = mini(party, SEATS.size() + STANDING.size())
	for k in range(shown):
		var guest = _guest(str(looks[k % looks.size()]))
		guest.set_meta("seat", k)
		guest.set_meta("state", "walking")
		actors.add_child(guest)
		slot.guests.append(guest)
		if instant:
			_seat(slot, guest)
			continue
		guest.position = door_point()
		guest.visible = false
		var target_cell: Vector2i = _seat_cell(slot, k)
		var points: PackedVector2Array = PackedVector2Array([entry_point()])
		points.append_array(_path(Vector2(lay.entry[0], lay.entry[1]), target_cell))
		points.append(_seat_point(slot, k))
		guest.arrived.connect(_seat.bind(slot, guest), CONNECT_ONE_SHOT)
		var delay: Tween = guest.create_tween()
		delay.tween_interval(0.45 * k)
		delay.tween_callback(func():
			guest.visible = true
			guest.fade_in()
			guest.walk(points))

func _seat_cell(slot: Dictionary, seat: int) -> Vector2i:
	if seat < SEATS.size():
		return slot.cell + SEATS[seat].cell
	return _cell_at(slot.center + STANDING[seat - SEATS.size()])

func _seat_point(slot: Dictionary, seat: int) -> Vector2:
	if seat < SEATS.size():
		return WorldData.iso_v(slot.center + SEATS[seat].offset)
	return WorldData.iso_v(slot.center + STANDING[seat - SEATS.size()])

func _seat(slot: Dictionary, guest) -> void:
	if not is_instance_valid(guest) or guest.get_meta("state", "") == "leaving":
		return
	var seat: int = int(guest.get_meta("seat"))
	guest.path = PackedVector2Array()
	guest.position = _seat_point(slot, seat)
	guest.set_meta("state", "seated")
	if seat < SEATS.size():
		var info: Dictionary = SEATS[seat]
		guest.sprite.flip_h = info.flip
		guest.facing_front = info.view == "front"
		# Back-chair sitters draw after their chair, front-chair sitters before it.
		var nudge: float = 1.0 if info.view == "front" else -1.0
		guest.position.y += nudge
		guest.sprite.position.y = -nudge
		guest.play("sit_front" if info.view == "front" else "sit_back")
	else:
		guest.sprite.flip_h = seat == SEATS.size() + 1
		guest.facing_front = true
		guest.play("idle_front")

func _depart(slot: Dictionary, previous: Dictionary, simulation) -> void:
	var angry: bool = float(previous.get("mood", 50)) <= float(DataCatalog.data.economy.mood.leave_at_or_below) + 2.0
	var amount: int = int(previous.get("bill", 0))
	if not angry:
		amount += int(floor(simulation.tip_for(previous)))
	if simulation.closed_remaining <= 0.0 and (amount > 0 or angry):
		payout.emit(WorldData.iso_v(slot.center) + Vector2(0, -60), amount, angry)
	if angry:
		slot.angry_until = time + 2.5
	for guest in slot.guests:
		if not is_instance_valid(guest):
			continue
		guest.set_meta("state", "leaving")
		guest.sprite.position.y = 0.0
		var from: Vector2 = WorldData.to_floor(guest.position)
		var points: PackedVector2Array = _path(from, _cell_at(Vector2(lay.entry[0], lay.entry[1])))
		points.append(entry_point())
		points.append(door_point())
		guest.speed_scale = 1.25 if angry else 1.0
		var start: Tween = guest.create_tween()
		start.tween_interval(rng.randf_range(0.0, 0.5))
		start.tween_callback(func():
			if is_instance_valid(guest):
				guest.arrived.connect(func(): guest.fade_and_free(0.3), CONNECT_ONE_SHOT)
				guest.walk(points))
	slot.guests = []
	slot.kind = ""
	_clear_drink(slot)

func _clear_drink(slot: Dictionary) -> void:
	if slot.drink != null and is_instance_valid(slot.drink):
		slot.drink.queue_free()
	slot.drink = null

func _place_drink(slot: Dictionary, item: String) -> void:
	_clear_drink(slot)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = WorldData.texture("res://assets/sprites/drinks/%s.svg" % item)
	sprite.scale = Vector2(0.15, 0.15)
	sprite.position = Vector2(0, -float(WorldData.info(theme + "_table").get("top_z", 30)) - 14)
	slot.table.add_child(sprite)
	slot.drink = sprite
	sprite.scale = Vector2(0.02, 0.02)
	sprite.create_tween().tween_property(sprite, "scale", Vector2(0.15, 0.15), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_slot(slot: Dictionary, table: Dictionary, simulation) -> void:
	var occupied: bool = not str(table.get("guest_type", "")).is_empty()
	var mood_rules: Dictionary = DataCatalog.data.economy.mood
	var status: String = str(table.get("order_status", ""))
	if not occupied:
		slot.hud.show_state("", "", "", 0.0, "angry" if time < float(slot.angry_until) else "", 0)
		slot.status = ""
		return
	var seated: bool = false
	for guest in slot.guests:
		if is_instance_valid(guest) and guest.get_meta("state", "") in ["seated", "dancing"]:
			seated = true
	var mood: float = float(table.get("mood", 50))
	if status == "preparing":
		slot.prep_total = maxf(float(slot.prep_total), float(table.get("prep_remaining", 0.0)))
	if status == "served" and slot.status == "preparing":
		jobs.append({"slot": slot, "item": str(table.get("order_item", ""))})
	elif status == "served" and slot.status == "" and slot.drink == null:
		_place_drink(slot, str(table.get("order_item", "")))
	if status != "preparing":
		slot.prep_total = 0.0
	slot.status = status
	var mode: String = ""
	var ratio: float = 0.0
	if seated and status == "waiting":
		mode = "order"
	elif seated and status == "preparing":
		mode = "preparing"
		ratio = clampf(1.0 - float(table.get("prep_remaining", 0.0)) / maxf(0.01, float(slot.prep_total)), 0.0, 1.0)
	elif seated and not str(table.get("request_genre", "")).is_empty():
		mode = "request"
	var emote: String = ""
	if seated:
		if bool(table.get("dancing", false)) or mood >= float(mood_rules.happy_at_or_above) + 12.0:
			emote = "heart"
		elif mood < float(mood_rules.unhappy_below):
			emote = "angry"
		elif status in ["waiting", "preparing"] and float(table.get("waiting_seconds", 0.0)) > 90.0:
			emote = "sleepy"
		elif mood >= float(mood_rules.happy_at_or_above):
			emote = "happy"
	var extra: int = int(table.get("party_size", 0)) - SEATS.size() - STANDING.size()
	slot.hud.show_state(mode, str(table.get("order_item", "")), str(table.get("request_genre", "")), ratio, emote, extra)
	_animate_guests(slot, table, mood, mood_rules)

func _animate_guests(slot: Dictionary, table: Dictionary, mood: float, mood_rules: Dictionary) -> void:
	var dancing: bool = bool(table.get("dancing", false))
	var drinking: bool = slot.drink != null and float(slot.drink_timer) < 1.3
	for guest in slot.guests:
		if not is_instance_valid(guest):
			continue
		var state: String = guest.get_meta("state", "")
		var seat: int = int(guest.get_meta("seat"))
		if dancing and state == "seated":
			guest.set_meta("state", "dancing")
			guest.sprite.position.y = 0.0
			var spot: Vector2 = slot.center + (SEATS[seat].offset * 1.55 if seat < SEATS.size() else STANDING[seat - SEATS.size()])
			guest.position = WorldData.iso_v(spot)
			guest.sprite.flip_h = rng.randf() < 0.5
			guest.play("dance", rng.randf_range(6.0, 8.0))
		elif not dancing and state == "dancing":
			_seat(slot, guest)
		elif state == "seated" and seat < SEATS.size():
			var front: bool = SEATS[seat].view == "front"
			var anim: String = "sit_front" if front else "sit_back"
			if drinking and (seat + int(slot.index)) % 2 == 0:
				anim = "drink_front" if front else "drink_back"
			elif front and mood < float(mood_rules.unhappy_below):
				anim = "angry_front"
			elif front and mood >= float(mood_rules.happy_at_or_above):
				anim = "happy_front"
			guest.play(anim)

func _sync_staff(save: Dictionary) -> void:
	var upgrades: Dictionary = save.get("upgrades", {})
	bouncer.visible = int(upgrades.get("izbacivac", 0)) > 0
	var wanted: int = 1
	for threshold in WAITER_THRESHOLDS:
		if int(upgrades.get("konobar", 0)) >= threshold:
			wanted += 1
	while waiters.size() < wanted:
		var names: Array = WorldData.people.waiters
		var waiter = _person(str(names[waiters.size() % names.size()]), WorldData.people.waiter_anims, 18)
		var home: Vector2 = Vector2(lay.waiter_home[0], lay.waiter_home[1]) + Vector2(0.55 * waiters.size(), 0.3 * (waiters.size() % 2))
		waiter.set_meta("home", home)
		waiter.set_meta("state", "idle")
		waiter.position = WorldData.iso_v(home)
		waiter.play("idle_front")
		waiter.walk_prefix = "walk"
		actors.add_child(waiter)
		waiters.append(waiter)
	var dekor: int = int(upgrades.get("dekor", 0))
	_decor("plants", dekor >= 1, func():
		var nodes: Array = []
		for spot in lay.plants:
			var plant: Sprite2D = WorldData.sprite("barrel" if theme == "birtija" else ("plant_ficus" if nodes.size() % 2 == 0 else "plant_fern"))
			plant.position = WorldData.iso(float(spot[0]) + 0.5, float(spot[1]) + 0.5)
			actors.add_child(plant)
			nodes.append(plant)
		return nodes)
	_decor("rug", dekor >= 3, func():
		var rug: Sprite2D = WorldData.sprite("rug_" + theme)
		rug.position = WorldData.iso(1.0, float(lay.d) - 6.0)
		rug.z_index = -9
		add_child(rug)
		return [rug])
	var sound: int = int(upgrades.get("ozvucenje", 0))
	var make_speakers: Callable = func():
		var nodes: Array = []
		for spot in [Vector2(float(lay.stage[2]) - 0.35, 0.35), Vector2(0.35, float(lay.stage[3]) - 0.35)]:
			var speaker: Sprite2D = WorldData.sprite("speaker_big" if sound >= 5 else "speaker_small")
			speaker.position = WorldData.iso_v(spot, float(lay.stage[4]))
			actors.add_child(speaker)
			nodes.append(speaker)
		return nodes
	_decor("speakers", sound >= 1, make_speakers, str(sound >= 5))
	_decor("safe", int(upgrades.get("sef", 0)) > 0, func():
		var safe: Sprite2D = WorldData.sprite("safe")
		safe.position = WorldData.iso(float(lay.bar[0]) + 0.35, 0.45)
		safe.z_index = -1
		actors.add_child(safe)
		return [safe])

func _decor(key: String, wanted: bool, make: Callable, variant: String = "") -> void:
	var have: bool = decor.has(key)
	if have and (not wanted or str(decor[key].variant) != variant):
		for node in decor[key].nodes:
			if is_instance_valid(node):
				node.queue_free()
		decor.erase(key)
		have = false
	if wanted and not have:
		decor[key] = {"nodes": make.call(), "variant": variant}

func _sync_band(simulation) -> void:
	var level: String = str(simulation.save.band_level)
	if level != band_id:
		for musician in band:
			musician.queue_free()
		band.clear()
		band_id = level
		var lineup: Array = WorldData.people.band_lineups.get(level, ["accordion"])
		var spots: Array = lay.musicians[clampi(lineup.size(), 1, lay.musicians.size()) - 1]
		for k in range(lineup.size()):
			var musician = _person(str(WorldData.people.musicians[lineup[k]]), {"idle": [0], "play": [1, 2, 3, 2]}, 4)
			musician.position = WorldData.iso(float(spots[k][0]), float(spots[k][1]), float(lay.stage[4]))
			musician.sprite.flip_h = k >= lineup.size() / 2.0 and lineup.size() > 1
			musician.play("idle")
			actors.add_child(musician)
			band.append(musician)
	var playing: bool = simulation.song_remaining > 0.0 and not str(simulation.current_song).is_empty()
	for musician in band:
		musician.play("play" if playing else "idle", 6.0)
		musician.bob = 0.0 if playing else 0.6

# --------------------------------------------------------------------------------------------
# Waiters, lights and music
# --------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if lay.is_empty():
		return
	time += delta
	for light in lights:
		var t: float = time * float(light.speed) + float(light.phase)
		var level: float = (0.32 + 0.12 * sin(t * 2.0) + 0.06 * sin(t * 5.1)) if light.big else (0.2 + 0.3 * pow(0.5 + 0.5 * sin(t * 1.4), 2.0))
		light.sprite.modulate.a = level
	for slot in slots:
		if slot.drink != null:
			slot.drink_timer = float(slot.drink_timer) - delta
			if float(slot.drink_timer) < 0.0:
				slot.drink_timer = rng.randf_range(4.0, 8.0)
	_run_waiters()
	if not band.is_empty() and band[0].current == "play":
		note_timer -= delta
		if note_timer <= 0.0:
			note_timer = rng.randf_range(0.35, 0.7)
			_spawn_note(band[rng.randi() % band.size()])

func _run_waiters() -> void:
	for waiter in waiters:
		if jobs.is_empty():
			break
		if waiter.get_meta("state") != "idle":
			continue
		var job: Dictionary = jobs.pop_front()
		var slot: Dictionary = job.slot
		if slot.locked or slot.guests.is_empty():
			continue
		waiter.set_meta("state", "delivering")
		waiter.walk_prefix = "carry"
		var target: Vector2i = _cell_at(slot.center + Vector2(1.0, 1.0))
		var points: PackedVector2Array = _path(WorldData.to_floor(waiter.position), target)
		waiter.arrived.connect(_delivered.bind(waiter, slot, str(job.item)), CONNECT_ONE_SHOT)
		waiter.walk(points)

func _delivered(waiter, slot: Dictionary, item: String) -> void:
	if not slot.guests.is_empty():
		_place_drink(slot, item)
		slot.drink_timer = 0.5
	waiter.face(WorldData.iso_v(slot.center) - waiter.position)
	waiter.play("carry_idle")
	var back: Tween = waiter.create_tween()
	back.tween_interval(0.5)
	back.tween_callback(func():
		waiter.walk_prefix = "walk"
		var home: Vector2 = waiter.get_meta("home")
		var points: PackedVector2Array = _path(WorldData.to_floor(waiter.position), _cell_at(home))
		points.append(WorldData.iso_v(home))
		waiter.arrived.connect(func():
			waiter.set_meta("state", "idle")
			waiter.sprite.flip_h = false
			waiter.play("idle_front"), CONNECT_ONE_SHOT)
		waiter.walk(points))

func _spawn_note(musician) -> void:
	var song: Dictionary = DataCatalog.get_item("songs", str(GameState.simulation.current_song))
	var note: Sprite2D = WorldData.sprite("fx/note")
	note.modulate = TableHud.GENRE_COLORS.get(str(song.get("genre", "")), Color.WHITE)
	note.position = musician.position + Vector2(rng.randf_range(-16, 16), -70)
	note.scale *= 0.7
	overlay.add_child(note)
	var tween: Tween = note.create_tween()
	tween.set_parallel(true)
	tween.tween_property(note, "position", note.position + Vector2(rng.randf_range(-50, 50), -110), 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "modulate:a", 0.0, 2.2).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(note.queue_free)

# --------------------------------------------------------------------------------------------
# Picking
# --------------------------------------------------------------------------------------------

## What a tap at a world point hits: {"kind": "table"|"slot"|"stage"|"", "index": int}.
func pick(point: Vector2) -> Dictionary:
	for slot in slots:
		if not slot.locked and slot.hud.cloud.visible and point.distance_to(slot.hud.position + Vector2(0, -44)) < 56.0:
			return {"kind": "table", "index": slot.index}
	for slot in slots:
		if slot.plus.visible and point.distance_to(slot.plus.position + Vector2(0, -24)) < 40.0:
			return {"kind": "slot", "index": slot.index}
	var best: Dictionary = {"kind": "", "index": -1}
	var best_distance: float = INF
	for slot in slots:
		if slot.locked:
			continue
		var center: Vector2 = WorldData.iso_v(slot.center) + Vector2(0, -30)
		var d: Vector2 = point - center
		var score: float = pow(d.x / 120.0, 2) + pow(d.y / 80.0, 2)
		if score <= 1.0 and score < best_distance:
			best_distance = score
			best = {"kind": "table", "index": slot.index}
	if not best.kind.is_empty():
		return best
	var tile: Vector2 = WorldData.to_floor(point + Vector2(0, float(lay.stage[4])))
	if tile.x >= 0 and tile.y >= 0 and tile.x <= float(lay.stage[2]) + 0.3 and tile.y <= float(lay.stage[3]) + 0.3:
		return {"kind": "stage", "index": -1}
	for musician in band:
		if point.distance_to(musician.position + Vector2(0, -40)) < 45:
			return {"kind": "stage", "index": -1}
	return best

func focus_point() -> Vector2:
	## Where the camera starts: between the stage and the first tables.
	return WorldData.iso(float(lay.stage[2]) + 1.5, float(lay.stage[3]) + 2.5)
