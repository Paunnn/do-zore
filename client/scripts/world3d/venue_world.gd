extends Node3D
## The venue being played, in 3D. Builds the cut-away interior and turns simulation state into
## people: parties walk in from the street, sit down, order, drink, dance and walk out paying;
## waiters carry trays from the bar; the band plays while a song is on. Presentation only: it
## reads the simulation and never changes it.
##
## Thought clouds, the "+" for the next table and fight dust are 2D nodes in `hud_layer`; the
## floor view positions them over their 3D anchors every frame.
signal payout(world_position: Vector3, amount: int, angry: bool)
signal note(world_position: Vector3, genre: String)

const Venue = preload("res://scripts/world3d/venue3d.gd")
const People = preload("res://scripts/world3d/people3d.gd")
const Builder = preload("res://scripts/world3d/builder.gd")
const Kit = preload("res://scripts/world3d/kit3d.gd")
const TableHud = preload("res://scripts/world/table_hud.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const SEATS = Venue.SEATS
const STANDING = Venue.STANDING
const WAITER_THRESHOLDS = [1, 4, 8]
const BAND_LINEUPS = People.BAND_LINEUPS
const LOOKS_PER_KIND = 8
const VESSEL_SCALE = 1.35
## Each guest's own glass, per menu item (the bottle or dish stands in the middle of the table).
const VESSEL_FOR = {"domaca_kafa": "cup", "kisela_voda": "water", "pivo": "mug", "sljivovica": "shot",
	"lozovaca": "shot", "vinjak": "shot", "crno_vino": "wine", "viski": "tumbler", "sampanjac": "flute",
	"meze": "shot", "rostilj": "mug", "riblja_corba": "wine"}

var venue_id: String = ""
var lay: Dictionary = {}
var hud_layer: Node2D
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
var light_energy: Array = []
var dust: Array = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var time: float = 0.0
var note_timer: float = 0.0
var synced_once: bool = false
var darkness: float = 0.0
## Where guests walk to the door from the city: {"point": in front of the door on the
## pavement, "dir": along the pavement}, in this node's space. Empty: straight from the door.
var approach: Dictionary = {}
var stage_anchor: Vector3 = Vector3.ZERO
## Everyone in the venue, for the shared contact shadows (one draw call for all of them).
var people: Array = []
var shadows: MultiMeshInstance3D
## Every chair in the room in one draw call; each can slide out when someone sits down or gets up.
var chairs: MultiMeshInstance3D

static var _drinks: Dictionary = {}

func build(venue: String, max_tables: int) -> void:
	venue_id = venue
	lay = Venue.layout(venue, max_tables)
	rng.seed = hash(venue)
	for child in get_children():
		child.queue_free()
	for list in [slots, waiters, jobs, band, lights, light_energy, people]:
		list.clear()
	for item in dust:
		if is_instance_valid(item): item.queue_free()
	dust.clear()
	decor.clear()
	band_id = ""
	synced_once = false
	var built: Dictionary = Venue.build_interior(self, lay)
	shadows = MultiMeshInstance3D.new()
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(0.75, 0.75)
	multimesh.mesh = quad
	multimesh.instance_count = 320
	multimesh.visible_instance_count = 0
	shadows.multimesh = multimesh
	shadows.material_override = Kit.material("blend:shadow")
	shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadows)
	lights = built.lights
	for light in lights:
		light_energy.append(light.light_energy)
	stage_anchor = Vector3(lay.stage.x / 2.0, 1.6, lay.stage.y / 2.0)
	_build_grid()
	_build_slots(built.slots)
	bartender = _person("bartender", 0)
	bartender.position = lay.bartender
	bartender.face_now(Vector3(0, 0, 1))
	bartender.play("wipe", 0.8)
	bouncer = _person("bouncer", 0)
	bouncer.position = lay.bouncer
	bouncer.face_now(Vector3(0, 0, 1))

func _build_grid() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, int(lay.w), int(lay.d))
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for cell in lay.blocked:
		astar.set_point_solid(cell)
	for cell in lay.tables:
		for seat in SEATS:
			var c: Vector2i = cell + seat.cell
			if astar.is_in_boundsv(c):
				astar.set_point_weight_scale(c, 4.0)

func _build_slots(nodes: Array) -> void:
	for index in range(nodes.size()):
		var cell: Vector2i = lay.tables[index]
		var center: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
		var slot: Dictionary = {"index": index, "cell": cell, "center": center, "guests": [], "locked": true, "party": 0,
			"kind": "", "status": "", "prep_total": 0.0, "drink": null, "vessels": [], "table": nodes[index],
			"pulls": [0.0, 0.0, 0.0, 0.0],
			"angry_until": -1.0, "anchor": Vector3(center.x, 1.95, center.y), "floor": Vector3(center.x, 0.8, center.y)}
		var marker: MeshInstance3D = MeshInstance3D.new()
		var quad: PlaneMesh = PlaneMesh.new()
		quad.size = Vector2(3.2, 3.2)
		marker.mesh = quad
		marker.position = Vector3(center.x, 0.02, center.y)
		marker.material_override = Kit.material("blend:slot")
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
		slot.marker = marker
		var hud = TableHud.new()
		if hud_layer != null: hud_layer.add_child(hud)
		slot.hud = hud
		var plus: Sprite2D = WorldData.sprite("fx/plus")
		plus.visible = false
		if hud_layer != null: hud_layer.add_child(plus)
		slot.plus = plus
		slots.append(slot)
		_set_locked(slot, true)
	chairs = MultiMeshInstance3D.new()
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = Venue.chair_mesh(venue_id)
	multimesh.instance_count = slots.size() * SEATS.size()
	chairs.multimesh = multimesh
	add_child(chairs)
	for slot in slots:
		for seat in range(SEATS.size()):
			_place_chair(slot, seat, 0.0)

## A chair at its table, `out` of the way pulled out (hidden while the table is locked).
func _place_chair(slot: Dictionary, seat: int, out: float) -> void:
	slot.pulls[seat] = out
	if chairs == null:
		return
	var offset: Vector2 = SEATS[seat].offset
	var at: Vector2 = slot.center + offset + offset.normalized() * People.CHAIR_PULL * out
	var basis: Basis = Basis(Vector3.UP, atan2(offset.x, offset.y))
	if slot.locked:
		basis = basis.scaled(Vector3.ZERO)
	chairs.multimesh.set_instance_transform(slot.index * SEATS.size() + seat, Transform3D(basis, Vector3(at.x, 0, at.y)))

## What a guest needs to use a chair (see People.sit_down).
func _seat_info(slot: Dictionary, seat: int) -> Dictionary:
	var info: Dictionary = Venue.seat_geometry(slot.center, seat)
	info.move = func(out: float): _place_chair(slot, seat, out)
	info.release = func():
		create_tween().tween_method(func(out: float): _place_chair(slot, seat, out), float(slot.pulls[seat]), 0.0, 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return info

## The walk cell beside a chair, where guests come from and go to.
func _seat_cell(slot: Dictionary, seat: int) -> Vector2i:
	if seat < SEATS.size():
		var corner: Vector2i = slot.cell + Venue.seat_geometry(slot.center, seat).corner
		if astar.is_in_boundsv(corner) and not astar.is_point_solid(corner):
			return corner
		return slot.cell + SEATS[seat].cell
	return _cell_at(Venue.seat_point(slot.center, seat))

func clear_overlay() -> void:
	for slot in slots:
		for key in ["hud", "plus"]:
			if is_instance_valid(slot[key]): slot[key].queue_free()
	for item in dust:
		if is_instance_valid(item): item.queue_free()
	dust.clear()

func _set_locked(slot: Dictionary, locked: bool) -> void:
	slot.locked = locked
	slot.table.visible = not locked
	slot.marker.visible = locked
	slot.hud.visible = not locked
	if locked:
		for guest in slot.guests:
			if is_instance_valid(guest): guest.queue_free()
		slot.guests = []
		_clear_drink(slot)
	for seat in range(SEATS.size()):
		_place_chair(slot, seat, 0.0)

func _person(kind: String, variant: int):
	var person = People.new()
	add_child(person)
	person.setup(People.make_look(kind, variant))
	people.append(person)
	return person

## Soft contact shadows under every person and every open table set, in one draw call.
func _update_shadows() -> void:
	var multimesh: MultiMesh = shadows.multimesh
	var count: int = 0
	var alive: Array = []
	for slot in slots:
		if not slot.locked and count < multimesh.instance_count:
			multimesh.set_instance_transform(count, Transform3D(Basis.from_scale(Vector3(3.4, 1, 3.4)), Vector3(slot.center.x, 0.012, slot.center.y)))
			count += 1
	for person in people:
		if not is_instance_valid(person) or person.is_queued_for_deletion():
			continue
		alive.append(person)
		if person.visible and count < multimesh.instance_count:
			var size: float = person.scale.x
			multimesh.set_instance_transform(count, Transform3D(Basis.from_scale(Vector3(size, 1, size)), Vector3(person.position.x, 0.015, person.position.z)))
			count += 1
	people = alive
	multimesh.visible_instance_count = count

# --------------------------------------------------------------------------------------------
# Paths (cells are 1 m; local positions are metres in the venue)
# --------------------------------------------------------------------------------------------

func _cell_at(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x), floori(point.z)).clamp(Vector2i.ZERO, Vector2i(int(lay.w) - 1, int(lay.d) - 1))

func _path(from: Vector3, to_cell: Vector2i) -> PackedVector3Array:
	var start: Vector2i = _cell_at(from)
	var was_solid: bool = astar.is_point_solid(start)
	if was_solid: astar.set_point_solid(start, false)
	var cells: Array[Vector2i] = astar.get_id_path(start, to_cell, true)
	if was_solid: astar.set_point_solid(start, true)
	var points: PackedVector3Array = PackedVector3Array()
	for i in range(1, cells.size()):
		points.append(Vector3(cells[i].x + 0.5, 0, cells[i].y + 0.5))
	return _straighten(from, points)

## Grid paths walk in 45-degree steps; people walk straight to the farthest point of the path they
## can reach without brushing a table, a chair or a wall (checked with a body's width).
func _straighten(from: Vector3, points: PackedVector3Array) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var anchor: Vector3 = from
	var i: int = 0
	while i < points.size():
		var far: int = i
		for j in range(points.size() - 1, i, -1):
			if _clear_line(anchor, points[j]):
				far = j
				break
		out.append(points[far])
		anchor = points[far]
		i = far + 1
	return out

func _clear_line(a: Vector3, b: Vector3) -> bool:
	var steps: int = ceili(a.distance_to(b) / 0.2)
	for k in range(1, steps):
		var p: Vector3 = a.lerp(b, float(k) / steps)
		for corner in [Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]:
			var cell: Vector2i = Vector2i(floori(p.x + corner.x), floori(p.z + corner.y))
			if not astar.is_in_boundsv(cell) or astar.is_point_solid(cell) or astar.get_point_weight_scale(cell) > 1.0:
				return false
	return true

func _street_point() -> Vector3:
	var spread: float = 0.6 if venue_id == "splav" else 6.0
	return lay.street + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-0.4, 0.4))

## The walk between the city and the door: along the pavement from one side, then to the door.
## Arriving it ends in front of the door; leaving it starts there and goes off down the street.
func _street_route(arriving: bool) -> PackedVector3Array:
	if approach.is_empty():
		return PackedVector3Array([_street_point()])
	var side: float = -1.0 if rng.randf() < 0.5 else 1.0
	var along: Vector3 = approach.dir
	var far: Vector3 = approach.point + along * side * rng.randf_range(12.0, 18.0)
	var near: Vector3 = approach.point + along * rng.randf_range(-0.8, 0.8)
	var route: PackedVector3Array = PackedVector3Array([far, near, lay.street])
	if not arriving:
		route.reverse()
	return route

func _entry() -> Vector3:
	return Vector3(lay.entry.x + 0.5, 0, lay.entry.y + 0.5)

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
		# Only the next table to buy is drawn on the floor; the rest of the room stays clean.
		slot.marker.visible = slot.locked and index == count
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

## Power cuts and closing time dim the lamps; a fight raises dust over angry tables.
func _sync_event(simulation) -> void:
	var event_id: String = str(simulation.active_event.get("id", ""))
	darkness = 1.0 if event_id == "nestanak_struje" or simulation.closed_remaining > 0.0 else 0.0
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
			if hud_layer != null: hud_layer.add_child(cloud)
			dust.append(cloud)
		dust[k].set_meta("anchor", fighting[k].floor + Vector3(0, 0.6, 0))

func _arrive(slot: Dictionary, table: Dictionary, instant: bool) -> void:
	var kind: String = str(table.guest_type)
	var party: int = int(table.party_size)
	slot.kind = kind
	slot.party = party
	slot.status = ""
	slot.angry_until = -1.0
	_clear_drink(slot)
	var shown: int = mini(party, SEATS.size() + STANDING.size())
	var first: int = rng.randi() % LOOKS_PER_KIND
	for k in range(shown):
		var guest = _person(kind, (first + k) % LOOKS_PER_KIND)
		guest.set_meta("seat", k)
		guest.set_meta("state", "walking")
		slot.guests.append(guest)
		if instant:
			_seat(slot, guest, true)
			continue
		# They come on foot down the street before they come in.
		var route: PackedVector3Array = _street_route(true)
		guest.position = route[0]
		guest.visible = false
		var points: PackedVector3Array = route.slice(1)
		points.append_array(PackedVector3Array([lay.door, _entry()]))
		points.append_array(_path(_entry(), _seat_cell(slot, k)))
		points.append(Venue.seat_geometry(slot.center, k).side if k < SEATS.size() else Venue.seat_point(slot.center, k))
		guest.arrived.connect(_seat.bind(slot, guest), CONNECT_ONE_SHOT)
		var delay: Tween = guest.create_tween()
		delay.tween_interval(0.5 * k)
		delay.tween_callback(func():
			guest.visible = true
			guest.fade_in()
			guest.walk(points))

## A guest takes their place: on their chair (pulling it out, sitting down, tucking it in), or
## standing at the corner for the ones the chairs don't fit.
func _seat(slot: Dictionary, guest, instant: bool = false) -> void:
	if not is_instance_valid(guest) or guest.get_meta("state", "") == "leaving":
		return
	var seat: int = int(guest.get_meta("seat"))
	guest.path = PackedVector3Array()
	guest.set_meta("state", "seated")
	if seat < SEATS.size():
		if instant:
			guest.sit_instant(_seat_info(slot, seat))
		else:
			guest.sit_down(_seat_info(slot, seat))
		return
	guest.position = Venue.seat_point(slot.center, seat)
	guest.face_now(Vector3(slot.center.x, 0, slot.center.y) - guest.position)
	guest.play("idle")

func _depart(slot: Dictionary, previous: Dictionary, simulation) -> void:
	var angry: bool = float(previous.get("mood", 50)) <= float(DataCatalog.data.economy.mood.leave_at_or_below) + 2.0
	var amount: int = int(previous.get("bill", 0))
	if not angry:
		amount += int(floor(simulation.tip_for(previous)))
	if simulation.closed_remaining <= 0.0 and (amount > 0 or angry):
		payout.emit(to_global(slot.floor + Vector3(0, 1.0, 0)), amount, angry)
	if angry:
		slot.angry_until = time + 2.5
	for guest in slot.guests:
		if not is_instance_valid(guest):
			continue
		guest.set_meta("state", "leaving")
		var go: Callable = func():
			if not is_instance_valid(guest):
				return
			var points: PackedVector3Array = _path(guest.position, lay.entry)
			points.append(lay.door)
			points.append_array(_street_route(false))
			guest.speed_scale = 1.3 if angry else 1.0
			if angry: guest.play("angry")
			guest.arrived.connect(func(): guest.fade_and_free(), CONNECT_ONE_SHOT)
			guest.walk(points)
		var start: Tween = guest.create_tween()
		start.tween_interval(rng.randf_range(0.0, 0.6))
		start.tween_callback(func():
			if is_instance_valid(guest):
				guest.stand_up(go))
	slot.guests = []
	slot.kind = ""
	_clear_drink(slot)

func _clear_drink(slot: Dictionary) -> void:
	if slot.drink != null and is_instance_valid(slot.drink):
		slot.drink.queue_free()
	slot.drink = null
	for vessel in slot.vessels:
		if is_instance_valid(vessel): vessel.queue_free()
	slot.vessels = []
	for guest in slot.guests:
		if is_instance_valid(guest): guest.set_vessel(null, "")

## The order arrives: its bottle or dish in the middle of the table, and a glass (or cup) in front
## of every seated guest, which they pick up and drink from.
func _place_drink(slot: Dictionary, item: String) -> void:
	_clear_drink(slot)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = drink_mesh(item)
	node.position = Vector3(0, 0.79, 0)
	slot.table.add_child(node)
	slot.drink = node
	_pop_in(node)
	var kind: String = VESSEL_FOR.get(item, "water")
	for guest in slot.guests:
		var seat: int = int(guest.get_meta("seat")) if is_instance_valid(guest) else 99
		if seat >= SEATS.size():
			continue
		var out: Vector2 = SEATS[seat].offset.normalized()
		var toward: Vector3 = -Vector3(out.x, 0, out.y)
		var right: Vector3 = toward.cross(Vector3.UP)
		var vessel: MeshInstance3D = MeshInstance3D.new()
		vessel.mesh = People.vessel_mesh(kind)
		vessel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slot.table.add_child(vessel)
		# Drawn a size up, like the people's hands.
		vessel.transform = Transform3D(Basis(Vector3.UP, atan2(toward.x, toward.z)).scaled(Vector3.ONE * VESSEL_SCALE), -toward * 0.34 + right * 0.15 + Vector3(0, 0.79, 0))
		guest.set_vessel(vessel, kind)
		slot.vessels.append(vessel)
		_pop_in(vessel)

static func _pop_in(node: Node3D) -> void:
	var size: Vector3 = node.scale
	node.scale = size * 0.1
	node.create_tween().tween_property(node, "scale", size, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A small still life for each menu item, set in the middle of the table.
static func drink_mesh(item: String) -> ArrayMesh:
	if _drinks.has(item):
		return _drinks[item]
	var b: Builder = Builder.new()
	var glass: Color = Color("dfeff0")
	match item:
		"domaca_kafa":
			# Džezva and a little plate of ratluk.
			b.cylinder(Vector3(0, 0, -0.05), 0.07, 0.13, Color("c98a4a"), "vc_metal", 12, 0.75)
			b.box(Vector3(0.1, 0.12, -0.05), Vector3(0.16, 0.018, 0.022), Color("3a2416"), "vc")
			b.cylinder(Vector3(-0.08, 0, 0.12), 0.09, 0.012, Color("f7f4ee"), "vc_gloss", 12)
			for k in range(4):
				b.box(Vector3(-0.11 + (k % 2) * 0.05, 0.012, 0.1 + (k / 2) * 0.05), Vector3(0.035, 0.03, 0.035), Color("f6efe2"), "vc")
		"kisela_voda":
			b.cylinder(Vector3(0, 0, 0), 0.06, 0.22, Color("7ab8a0"), "vc_gloss", 10)
			b.cylinder(Vector3(0, 0.22, 0), 0.025, 0.06, Color("2f6a5a"), "vc", 8)
		"pivo", "rostilj":
			if item == "rostilj":
				b.cylinder(Vector3(0, 0, 0.08), 0.24, 0.02, Color("f4f1ea"), "vc_gloss", 14)
				for k in range(5):
					b.cylinder_xf(Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(-0.1, 0.04, -0.02 + k * 0.05)), 0.02, 0.18, Color("7a3f22"), "vc", 6)
				b.sphere(Vector3(0.1, 0.04, 0.16), 0.06, Color("e8c870"), "vc", Vector3(1, 0.4, 1), 8)
			# A green beer bottle or two.
			for x in ([-0.06, 0.08] if item == "pivo" else [0.22]):
				b.cylinder(Vector3(x, 0, -0.1), 0.045, 0.17, Color("2f6a3a"), "vc_gloss", 10)
				b.cylinder(Vector3(x, 0.17, -0.1), 0.018, 0.08, Color("2f6a3a"), "vc_gloss", 8, 0.8)
				b.cylinder(Vector3(x, 0.08, -0.1), 0.047, 0.05, Color("f2e2b8"), "vc", 10)
		"sljivovica", "lozovaca", "vinjak", "meze":
			if item == "meze":
				b.cylinder(Vector3(0, 0, 0.06), 0.22, 0.025, Color("8a5a32"), "vc_gloss", 14)
				for k in range(6):
					var a: float = k * TAU / 6.0
					b.box(Vector3(cos(a) * 0.11, 0.025, 0.06 + sin(a) * 0.11), Vector3(0.07, 0.04, 0.07), [Color("f2e2a0"), Color("c0322c"), Color("e8a07a")][k % 3])
			var liquor: Color = {"lozovaca": Color("d8c27a"), "vinjak": Color("9a5a22")}.get(item, Color("e8e2c8"))
			b.cylinder(Vector3(0, 0, -0.14), 0.07, 0.24, liquor, "vc_gloss", 10)
			b.cylinder(Vector3(0, 0.24, -0.14), 0.025, 0.08, liquor, "vc_gloss", 8)
			b.cylinder(Vector3(0, 0.32, -0.14), 0.027, 0.03, Color("6a4a2a"), "vc", 8)
		"crno_vino", "riblja_corba":
			if item == "riblja_corba":
				b.cylinder(Vector3(0, 0, 0.06), 0.13, 0.08, Color("6e4528"), "vc_gloss", 12, 1.15)
				b.cylinder(Vector3(0, 0.07, 0.06), 0.13, 0.01, Color("d9622a"), "vc", 12)
			b.cylinder(Vector3(0, 0, -0.14), 0.065, 0.28, Color("3a0f1a"), "vc_gloss", 10)
			b.cylinder(Vector3(0, 0.28, -0.14), 0.022, 0.1, Color("3a0f1a"), "vc_gloss", 8)
		"viski":
			b.box(Vector3(0, 0, -0.08), Vector3(0.13, 0.22, 0.08), Color("b8722a"), "vc_gloss")
			b.cylinder(Vector3(0, 0.22, -0.08), 0.022, 0.06, Color("1d1d22"), "vc", 8)
			b.cylinder(Vector3(0.15, 0, 0.06), 0.06, 0.07, Color("c9ced6"), "vc_metal", 10)
		"sampanjac":
			b.cylinder(Vector3(0, 0, -0.08), 0.12, 0.14, Color("c9ced6"), "vc_metal", 12, 1.1)
			b.cylinder(Vector3(0, 0.05, -0.08), 0.05, 0.3, Color("2f5a35"), "vc_gloss", 10)
			b.cylinder(Vector3(0, 0.35, -0.08), 0.02, 0.06, Color("d9a531"), "vc_metal", 8)
		_:
			b.cylinder(Vector3(0, 0, 0), 0.05, 0.12, glass, "vc_gloss", 10)
	var mesh: ArrayMesh = b.mesh()
	_drinks[item] = mesh
	return mesh

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
	for guest in slot.guests:
		if not is_instance_valid(guest):
			continue
		var state: String = guest.get_meta("state", "")
		var seat: int = int(guest.get_meta("seat"))
		if dancing and state == "seated":
			# Up from the chair, a step out from the table, and dance.
			guest.set_meta("state", "dancing")
			var spot: Vector3 = Venue.seat_point(slot.center, seat)
			var out: Vector3 = (spot - Vector3(slot.center.x, 0, slot.center.y)) * 0.55
			var rate: float = rng.randf_range(0.9, 1.15)
			guest.stand_up(func():
				if not is_instance_valid(guest):
					return
				if guest.get_meta("state", "") == "returning":
					_seat(slot, guest)
					return
				guest.arrived.connect(func():
					if is_instance_valid(guest) and guest.get_meta("state", "") == "dancing":
						guest.face(out)
						guest.play("dance", rate), CONNECT_ONE_SHOT)
				guest.walk(PackedVector3Array([spot + out])))
		elif not dancing and state == "dancing":
			# Back to the chair (once up, if they are still getting up).
			guest.set_meta("state", "returning")
			if guest.seat_state == "":
				var back: Vector3 = Venue.seat_geometry(slot.center, seat).side if seat < SEATS.size() else Venue.seat_point(slot.center, seat)
				guest.arrived.connect(func():
					if is_instance_valid(guest) and guest.get_meta("state", "") == "returning":
						_seat(slot, guest), CONNECT_ONE_SHOT)
				guest.walk(PackedVector3Array([back]))
		elif state == "seated" and seat < SEATS.size() and guest.is_seated():
			var anim: String = "sit"
			if mood < float(mood_rules.unhappy_below):
				anim = "angry"
			elif mood >= float(mood_rules.happy_at_or_above) and (seat + int(time / 3.0)) % 3 == 0:
				anim = "happy"
			guest.play(anim)

func _sync_staff(save: Dictionary) -> void:
	var upgrades: Dictionary = save.get("upgrades", {})
	bouncer.visible = int(upgrades.get("izbacivac", 0)) > 0
	var wanted: int = 1
	for threshold in WAITER_THRESHOLDS:
		if int(upgrades.get("konobar", 0)) >= threshold:
			wanted += 1
	while waiters.size() < wanted:
		var waiter = _person("waiter", waiters.size())
		var home: Vector3 = lay.waiter_home - Vector3(1.0 * waiters.size(), 0, 0)
		waiter.set_meta("home", home)
		waiter.set_meta("state", "idle")
		waiter.position = home
		waiter.face_now(Vector3(0, 0, 1))
		waiters.append(waiter)
	var dekor: int = int(upgrades.get("dekor", 0))
	_decor("plants", dekor >= 1, func(b: Builder):
		for spot in lay.plants:
			Venue._plant(b, spot, "barrel" if venue_id == "birtija" else ("palm" if venue_id == "restoran" else "ficus")))
	# Kilims hang on the wall, the old kafana way (the floor stays clear for the tables).
	var wall_spot: float = Venue.free_wall_spot(lay)
	_decor("rug", dekor >= 3 and wall_spot > 0.0, func(b: Builder):
		var name: String = {"birtija": "rug_kilim", "kafana": "rug_persian", "restoran": "rug_blue"}.get(venue_id, "rug_kilim")
		b.add(Kit.unit("quad"), Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.2, 1, 1.7)), Vector3(0.06, 1.95, wall_spot)), Color.WHITE, "uv:" + name))
	var sound: int = int(upgrades.get("ozvucenje", 0))
	var make_speakers: Callable = func(b: Builder):
		var tall: float = 1.5 if sound >= 5 else 0.9
		for spot in [Vector3(lay.stage.x - 0.4, 0.35, 0.4), Vector3(0.4, 0.35, lay.stage.y - 0.4)]:
			b.box(spot, Vector3(0.55, tall, 0.5), Color("1d1d22"), "vc_gloss")
			b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), spot + Vector3(0, tall * 0.62, 0.26)), 0.17, 0.02, Color("3a3a44"), "vc", 12)
			b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), spot + Vector3(0, tall * 0.25, 0.26)), 0.1, 0.02, Color("3a3a44"), "vc", 10)
	_decor("speakers", sound >= 1, make_speakers, str(sound >= 5))
	_decor("safe", int(upgrades.get("sef", 0)) > 0, func(b: Builder):
		var at: Vector3 = Vector3(lay.bar_to - 0.2, 0, 2.3)
		b.box(at, Vector3(0.7, 0.8, 0.6), Color("4a5560"), "vc_metal")
		b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), at + Vector3(0, 0.45, 0.31)), 0.1, 0.03, Color("c9a24a"), "vc_metal", 12))

func _decor(key: String, wanted: bool, make: Callable, variant: String = "") -> void:
	var have: bool = decor.has(key)
	if have and (not wanted or str(decor[key].variant) != variant):
		decor[key].node.queue_free()
		decor.erase(key)
		have = false
	if wanted and not have:
		var node: Node3D = Node3D.new()
		add_child(node)
		var b: Builder = Builder.new()
		make.call(b)
		b.commit(node)
		decor[key] = {"node": node, "variant": variant}

func _sync_band(simulation) -> void:
	var level: String = str(simulation.save.band_level)
	if level != band_id:
		for musician in band:
			musician.queue_free()
		band.clear()
		band_id = level
		var lineup: Array = BAND_LINEUPS.get(level, ["accordion"])
		var spots: Array = lay.musicians[clampi(lineup.size(), 1, lay.musicians.size()) - 1]
		for k in range(lineup.size()):
			var musician = _person("musician:" + str(lineup[k]), k)
			musician.position = spots[k]
			musician.face_now(Vector3(0.7, 0, 1.0))
			band.append(musician)
	var playing: bool = simulation.song_remaining > 0.0 and not str(simulation.current_song).is_empty()
	for musician in band:
		musician.play("play" if playing else "idle")

# --------------------------------------------------------------------------------------------
# Waiters, lights and music
# --------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if lay.is_empty():
		return
	time += delta
	for i in range(lights.size()):
		var flicker: float = 1.0 + 0.04 * sin(time * 3.1 + i * 1.7) + 0.02 * sin(time * 7.3 + i)
		var target: float = light_energy[i] * flicker * (1.0 - 0.8 * darkness)
		lights[i].light_energy = lerpf(lights[i].light_energy, target, clampf(delta * 4.0, 0.0, 1.0))
	_run_waiters()
	_update_shadows()
	if not band.is_empty() and band[0].current == "play":
		note_timer -= delta
		if note_timer <= 0.0:
			note_timer = rng.randf_range(0.35, 0.7)
			var musician = band[rng.randi() % band.size()]
			var song: Dictionary = DataCatalog.get_item("songs", str(GameState.simulation.current_song))
			note.emit(musician.global_position + Vector3(0, 1.7, 0), str(song.get("genre", "")))

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
		waiter.hold("tray")
		var target: Vector2i = _cell_at(Vector3(slot.center.x + 1.0, 0, slot.center.y + 1.0))
		var points: PackedVector3Array = _path(waiter.position, target)
		waiter.arrived.connect(_delivered.bind(waiter, slot, str(job.item)), CONNECT_ONE_SHOT)
		waiter.play("carry")
		waiter.walk(points)

func _delivered(waiter, slot: Dictionary, item: String) -> void:
	if not slot.guests.is_empty():
		_place_drink(slot, item)
	waiter.face(Vector3(slot.center.x, 0, slot.center.y) - waiter.position)
	waiter.play("carry_idle")
	var back: Tween = waiter.create_tween()
	back.tween_interval(0.5)
	back.tween_callback(func():
		waiter.play("walk")
		var home: Vector3 = waiter.get_meta("home")
		var points: PackedVector3Array = _path(waiter.position, _cell_at(home))
		points.append(home)
		waiter.arrived.connect(func():
			waiter.set_meta("state", "idle")
			waiter.face(Vector3(0, 0, 1))
			waiter.play("idle"), CONNECT_ONE_SHOT)
		waiter.walk(points))

# --------------------------------------------------------------------------------------------
# Picking (screen space: `project` maps a global position to the screen)
# --------------------------------------------------------------------------------------------

## What a tap hits: {"kind": "table"|"slot"|"stage"|"", "index": int}. `reach` is the tap radius
## in screen pixels for one metre at the current zoom.
func pick(point: Vector2, project: Callable, metre: float) -> Dictionary:
	for slot in slots:
		if not slot.locked and slot.hud.cloud.visible and point.distance_to(slot.hud.position + Vector2(0, -44) * slot.hud.scale.x) < 64.0 * slot.hud.scale.x:
			return {"kind": "table", "index": slot.index}
	for slot in slots:
		if slot.plus.visible and point.distance_to(project.call(to_global(slot.floor))) < maxf(48.0, metre * 1.4):
			return {"kind": "slot", "index": slot.index}
	var best: Dictionary = {"kind": "", "index": -1}
	var best_distance: float = INF
	for slot in slots:
		if slot.locked:
			continue
		var d: float = point.distance_to(project.call(to_global(slot.floor)))
		if d < metre * 1.6 and d < best_distance:
			best_distance = d
			best = {"kind": "table", "index": slot.index}
	if not best.kind.is_empty():
		return best
	if point.distance_to(project.call(to_global(Vector3(lay.stage.x / 2.0, 0.6, lay.stage.y / 2.0)))) < metre * maxf(lay.stage.x, lay.stage.y) * 0.6:
		return {"kind": "stage", "index": -1}
	return best

func focus_point() -> Vector3:
	## Where the camera starts: the middle of the room, a little toward the stage.
	return to_global(Vector3(lay.w * 0.45, 0, lay.d * 0.42))

func bounds() -> AABB:
	return AABB(global_position + Vector3(-2, 0, -2), Vector3(lay.w + 4, 4, lay.d + 6))
