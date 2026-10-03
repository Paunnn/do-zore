extends RefCounted
## The four venues in 3D. The venue being played is a roofless cut-away full of furniture,
## decor and warm lamps; the others stand on the map as closed buildings with their signs.
##
## Venue space: the floor spans x in [0, w] and z in [0, d] metres. The back walls stand on
## x = 0 and z = 0 (the camera looks from +x, +z), the street door is in the front wall at z = d.
## Tables sit on a 4 m grid of 1 m walk cells: the table in the middle cell, a chair on each
## side and an aisle between neighbours.
const Kit = preload("res://scripts/world3d/kit3d.gd")
const Builder = preload("res://scripts/world3d/builder.gd")
const PITCH = 4
const WALL_H = 3.2
const FRONT_H = 0.75
const CHAIR_GAP = 0.85
## Seat offsets around a table and the walk cell beside each chair.
const SEATS = [
	{"offset": Vector2(-CHAIR_GAP, 0), "cell": Vector2i(-1, 0)},
	{"offset": Vector2(0, -CHAIR_GAP), "cell": Vector2i(0, -1)},
	{"offset": Vector2(CHAIR_GAP, 0), "cell": Vector2i(1, 0)},
	{"offset": Vector2(0, CHAIR_GAP), "cell": Vector2i(0, 1)},
]
const STANDING = [Vector2(-1.1, -1.1), Vector2(1.1, -1.1)]

const THEMES = {
	"birtija": {
		"cols": 3, "top": 5, "stage": Vector2i(4, 3),
		"floor": "tex:planks_rough:0.4", "wall": "tex:logs:0.45", "wall_tint": "ffffff", "upper": "", "trim": "5a3a22",
		"facade": "tex:plaster_warm:0.25", "facade_tint": "f2e2c4", "roof": "roof_tiles", "storeys": 1,
		"table": "8a5e3a", "chair": "6e4528", "cloth": "", "stool": "6e4528", "bar": "7a4a2c", "bar_top": "5a3420",
		"lamp": "ffbf6a", "glass": "1d2c4a",
	},
	"kafana": {
		"cols": 4, "top": 6, "stage": Vector2i(5, 4),
		"floor": "tex:planks_walnut:0.45", "wall": "tex:damask_red:0.45", "wall_tint": "ffffff", "upper": "", "trim": "6e3c22",
		"facade": "tex:plaster_rose:0.25", "facade_tint": "f0d8c8", "roof": "roof_tiles", "storeys": 2,
		"table": "7a4628", "chair": "6a3a20", "cloth": "tex:cloth_red:0.9", "stool": "6a3a20", "bar": "7a4628", "bar_top": "5a3018",
		"lamp": "ffc070", "glass": "1d2c4a",
	},
	"restoran": {
		"cols": 5, "top": 6, "stage": Vector2i(6, 4),
		"floor": "tex:parquet:0.35", "wall": "tex:stripes_cream:0.45", "wall_tint": "ffffff", "upper": "", "trim": "f4efe4",
		"facade": "tex:plaster_white:0.25", "facade_tint": "f4efe4", "roof": "", "storeys": 3,
		"table": "e8e2d6", "chair": "a8323c", "cloth": "tex:linen:0.6", "stool": "a8323c", "bar": "4a4a58", "bar_top": "e8e2d6",
		"lamp": "ffe4b0", "glass": "1d2c4a",
	},
	"splav": {
		"cols": 6, "top": 6, "stage": Vector2i(6, 4),
		"floor": "tex:planks_deck:0.4", "wall": "", "wall_tint": "ffffff", "upper": "", "trim": "e8e2d6",
		"facade": "", "facade_tint": "ffffff", "roof": "", "storeys": 0,
		"table": "e8e2d6", "chair": "f4f1ea", "cloth": "tex:cloth_blue:0.9", "stool": "f4f1ea", "bar": "6e5a44", "bar_top": "e8e2d6",
		"lamp": "ffd890", "glass": "1d2c4a",
	},
}

# ---------------------------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------------------------

static func layout(venue_id: String, max_tables: int) -> Dictionary:
	var t: Dictionary = THEMES.get(venue_id, THEMES.kafana)
	var cols: int = int(t.cols)
	var rows: int = ceili(maxi(1, max_tables) / float(cols))
	var top: int = int(t.top)
	var w: int = cols * PITCH + 1
	var d: int = top + rows * PITCH + 1
	var stage: Vector2i = t.stage
	var tables: Array = []
	for r in range(rows):
		for c in range(cols):
			if tables.size() < max_tables:
				tables.append(Vector2i(2 + c * PITCH, top + 2 + r * PITCH))
	var bar_from: int = stage.x + 1
	var bar_to: int = w - 1
	var door_x: int = w - 3
	var blocked: Array = []
	for x in range(stage.x):
		for z in range(stage.y):
			blocked.append(Vector2i(x, z))
	for x in range(bar_from, bar_to):
		blocked.append(Vector2i(x, 0))
		blocked.append(Vector2i(x, 1))
	for cell in tables:
		blocked.append(cell)
	# The band: up to three in a row; from four on, every other one (the bass, the accordion) stands
	# in a second row behind, moved over to be seen past the front row from the camera, so the
	# players and their instruments keep clear of each other.
	var musicians: Array = []
	for count in range(1, 7):
		var spots: Array = []
		var front: int = count if count <= 3 else ceili(count / 2.0)
		var gap: float = (stage.x - 1.2) / front
		for k in range(count):
			var back: bool = count > 3 and k % 2 == 1
			var i: int = k if count <= 3 else k / 2
			var x: float = 0.6 + (i + 0.5) * gap + (gap * 0.5 if back else 0.0)
			spots.append(Vector3(x, 0.35, stage.y - (1.9 if back else (0.8 if count > 3 else 1.2))))
		musicians.append(spots)
	return {
		"id": venue_id, "w": w, "d": d, "top": top, "cols": cols, "rows": rows, "stage": stage,
		"tables": tables, "blocked": blocked, "bar_from": bar_from, "bar_to": bar_to,
		"door_x": door_x, "entry": Vector2i(door_x, d - 1),
		"door": Vector3(door_x + 0.5, 0, d + 0.4),
		"street": Vector3(door_x + 0.5, 0, d + (8.4 if venue_id == "splav" else 1.3)),
		"bartender": Vector3((bar_from + bar_to) / 2.0, 0, 0.55),
		"bouncer": Vector3(door_x + 1.6, 0, d + 0.9),
		"waiter_home": Vector3(bar_to - 1.5, 0, 2.8),
		"musicians": musicians,
		"plants": [Vector3(w - 0.7, 0, top + 0.7), Vector3(0.7, 0, d - 0.7), Vector3(w - 0.7, 0, d - 2.2), Vector3(0.7, 0, top + 0.7)],
	}

## Where things already hang on the side wall (x = 0), as distances from the first table row.
const WALL_ITEMS = {"birtija": [0.2, 2.0, 4.0, 6.0, 7.0, 10.0], "kafana": [3.0, 6.0, 9.0], "restoran": [2.5, 7.5, 12.5]}

## The middle of the widest free stretch of the side wall (z), or -1 when there is no room for a
## hanging 1.2 m wide.
static func free_wall_spot(lay: Dictionary) -> float:
	if not WALL_ITEMS.has(lay.id):
		return -1.0
	var top: float = float(lay.top)
	var marks: Array = [top - 0.2, float(lay.d) - 0.6]
	for at in WALL_ITEMS[lay.id]:
		if top + at < float(lay.d) - 0.6:
			marks.append(top + at)
	marks.sort()
	var best: float = -1.0
	var gap: float = 0.0
	for i in range(marks.size() - 1):
		if marks[i + 1] - marks[i] > gap:
			gap = marks[i + 1] - marks[i]
			best = (marks[i] + marks[i + 1]) / 2.0
	return best if gap >= 2.2 else -1.0

static func seat_point(center: Vector2, seat: int) -> Vector3:
	var offset: Vector2 = SEATS[seat].offset if seat < SEATS.size() else STANDING[seat - SEATS.size()]
	return Vector3(center.x + offset.x, 0, center.y + offset.y)

## A chair at a table: its tucked-in centre, the way to the table, a free spot beside where one
## stands to sit down (people come and go from there), and the walk cell next to that spot.
static func seat_geometry(center: Vector2, seat: int) -> Dictionary:
	var offset: Vector2 = SEATS[seat].offset
	var chair: Vector3 = Vector3(center.x + offset.x, 0, center.y + offset.y)
	var dir: Vector3 = -Vector3(offset.x, 0, offset.y).normalized()
	var side: Vector3 = Vector3(-dir.z, 0, dir.x)
	return {"chair": chair, "dir": dir, "side": chair - dir * 0.12 + side * 0.6,
		"corner": SEATS[seat].cell + Vector2i(roundi(side.x), roundi(side.z))}

# ---------------------------------------------------------------------------------------------
# Interior: the venue being played
# ---------------------------------------------------------------------------------------------

## Builds the cut-away into `root` and returns {"slots": [Node3D per table], "lights": [...]}.
static func build_interior(root: Node3D, lay: Dictionary) -> Dictionary:
	var id: String = lay.id
	var t: Dictionary = THEMES[id]
	var b: Builder = Builder.new(8.0)
	var w: float = lay.w
	var d: float = lay.d
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(id)
	if id == "splav":
		_raft(b, lay, rng)
	else:
		_room(b, lay, t, rng)
	_bar(b, lay, t, rng)
	_stage(b, lay, t, rng)
	match id:
		"birtija": _birtija_decor(b, lay, rng)
		"kafana": _kafana_decor(b, lay, rng)
		"restoran": _restoran_decor(b, lay, rng)
		"splav": _splav_decor(b, lay, rng)
	b.commit(root)
	var lights: Array = _lamps(root, lay, t)
	var slots: Array = []
	for index in range(lay.tables.size()):
		var cell: Vector2i = lay.tables[index]
		var node: Node3D = Node3D.new()
		node.position = Vector3(cell.x + 0.5, 0, cell.y + 0.5)
		root.add_child(node)
		var dining: Builder = Builder.new()
		_dining_set(dining, id, t, rng, false)
		dining.commit(node)
		slots.append(node)
	return {"slots": slots, "lights": lights}

static func _room(b: Builder, lay: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var w: float = lay.w
	var d: float = lay.d
	var trim: Color = Color(t.trim)
	var white: Color = Color.WHITE
	# Floor slab with a darker plinth showing at the cut edges.
	b.box(Vector3(w / 2.0, -0.28, d / 2.0), Vector3(w + 0.6, 0.25, d + 0.6), Color("e6e2dc"), "tex:sidewalk:0.4")
	b.box(Vector3(w / 2.0, -0.02, d / 2.0), Vector3(w, 0.02, d), white, t.floor)
	# Back walls with a wainscot, a skirting board and a cornice.
	b.box(Vector3(w / 2.0, 0, -0.15), Vector3(w + 0.3, WALL_H, 0.3), Color(t.wall_tint), t.wall)
	b.box(Vector3(-0.15, 0, d / 2.0), Vector3(0.3, WALL_H, d), Color(t.wall_tint), t.wall)
	if lay.id != "birtija":
		b.box(Vector3(w / 2.0, 0, -0.02), Vector3(w, 1.15, 0.06), trim, "vc_gloss")
		b.box(Vector3(-0.02, 0, d / 2.0), Vector3(0.06, 1.15, d), trim, "vc_gloss")
		b.box(Vector3(w / 2.0, 1.15, 0.0), Vector3(w, 0.08, 0.1), trim.lightened(0.2), "vc_gloss")
		b.box(Vector3(0.0, 1.15, d / 2.0), Vector3(0.1, 0.08, d), trim.lightened(0.2), "vc_gloss")
	b.box(Vector3(w / 2.0, WALL_H, -0.15), Vector3(w + 0.5, 0.18, 0.5), trim.darkened(0.1))
	b.box(Vector3(-0.15, WALL_H, d / 2.0), Vector3(0.5, 0.18, d + 0.2), trim.darkened(0.1))
	# Low front walls (cut away) with the door gap; light caps show the section.
	var door_x: float = lay.door_x
	var cap: Color = Color("efe6d2")
	b.box(Vector3(door_x / 2.0, 0, d + 0.15), Vector3(door_x, FRONT_H, 0.3), Color(t.wall_tint), t.wall if lay.id == "birtija" else t.facade)
	b.box(Vector3((door_x + 1.2 + w) / 2.0, 0, d + 0.15), Vector3(w - door_x - 1.2, FRONT_H, 0.3), Color(t.wall_tint), t.wall if lay.id == "birtija" else t.facade)
	b.box(Vector3(w + 0.15, 0, d / 2.0), Vector3(0.3, FRONT_H, d + 0.6), Color(t.wall_tint), t.wall if lay.id == "birtija" else t.facade)
	b.box(Vector3(door_x / 2.0, FRONT_H, d + 0.15), Vector3(door_x, 0.06, 0.34), cap)
	b.box(Vector3((door_x + 1.2 + w) / 2.0, FRONT_H, d + 0.15), Vector3(w - door_x - 1.2, 0.06, 0.34), cap)
	b.box(Vector3(w + 0.15, FRONT_H, d / 2.0), Vector3(0.34, 0.06, d + 0.6), cap)
	# Door frame and the venue's sign facing the street.
	for x in [door_x - 0.1, door_x + 1.3]:
		b.box(Vector3(x, 0, d + 0.15), Vector3(0.18, 2.5, 0.36), trim)
	b.box(Vector3(door_x + 0.6, 2.5, d + 0.15), Vector3(1.6, 0.2, 0.4), trim)
	b.box(Vector3(door_x + 0.6, 2.7, d + 0.2), Vector3(2.6, 0.9, 0.12), Color("2b1d14"))
	b.panel(Vector3(door_x + 0.6, 3.15, d + 0.27), Vector2(2.5, 0.75), Color.WHITE, "uv:sign_" + str(lay.id))
	# Windows in the back walls: night outside, deep blue glass in wooden frames.
	var glass: Color = Color(t.glass)
	for k in range(int(w / 4.0)):
		var x: float = 2.6 + k * 4.0
		if x > lay.bar_from - 0.5 and x < lay.bar_to and lay.id != "restoran":
			continue
		_window(b, Vector3(x, 1.35, 0.02), 0.0, glass, trim)
	for k in range(int((d - lay.top) / 4.0)):
		var z: float = lay.top + 2.0 + k * 4.0
		_window(b, Vector3(0.02, 1.35, z), PI / 2.0, glass, trim)

static func _window(b: Builder, at: Vector3, turn: float, glass: Color, frame: Color) -> void:
	var xf: Transform3D = Transform3D(Basis(Vector3.UP, turn), at)
	b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0.0)), Vector3(1.5, 1.45, 0.06), frame, "vc_gloss")
	b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0.03)), Vector3(1.3, 1.25, 0.04), glass, "glow:2d4a7a:0.7")
	b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0.06)), Vector3(0.06, 1.25, 0.04), frame, "vc")
	b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0.06)), Vector3(1.3, 0.06, 0.04), frame, "vc")
	b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0.12)), Vector3(1.6, 0.08, 0.22), frame, "vc_gloss")

static func _bar(b: Builder, lay: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0: float = lay.bar_from
	var x1: float = lay.bar_to
	var mid: float = (x0 + x1) / 2.0
	var length: float = x1 - x0
	var wood: Color = Color(t.bar)
	b.box(Vector3(mid, 0, 1.45), Vector3(length, 1.05, 0.7), wood, "vc_gloss")
	b.box(Vector3(mid, 1.05, 1.42), Vector3(length + 0.2, 0.08, 0.95), Color(t.bar_top), "vc_gloss")
	for k in range(int(length / 1.2)):
		b.box(Vector3(x0 + 0.6 + k * 1.2, 0.15, 1.81), Vector3(0.9, 0.7, 0.03), wood.lightened(0.12), "vc_gloss")
	if lay.id == "kafana" or lay.id == "restoran":
		b.cylinder_xf(Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(x0, 0.2, 1.95)), 0.035, length, Color("d9a531"), "vc_metal", 8)
	# Back shelves with bottles and, in the city venues, a mirror.
	var shelf: Color = Color(t.trim).darkened(0.15)
	if lay.id != "restoran":
		b.box(Vector3(mid, 1.2, 0.05), Vector3(length - 0.4, 1.3, 0.04), Color("1f2a3a"), "vc_gloss")
	for level in [1.35, 1.95, 2.55]:
		b.box(Vector3(mid, level, 0.2), Vector3(length - 0.2, 0.06, 0.35), shelf, "vc_gloss")
		var x: float = x0 + 0.4
		while x < x1 - 0.4:
			var c: Color = [Color("3d8a4f"), Color("c9a24a"), Color("b8302f"), Color("e8e2c8"), Color("6a2f5a"), Color("7aa7c9")][rng.randi() % 6]
			var tall: float = rng.randf_range(0.28, 0.42)
			b.cylinder(Vector3(x, level + 0.06, 0.2), 0.065, tall, c, "vc_gloss", 8)
			b.cylinder(Vector3(x, level + 0.06 + tall, 0.2), 0.025, 0.12, c.darkened(0.2), "vc_gloss", 6)
			x += rng.randf_range(0.18, 0.3)
	# Taps, a till and glasses on the counter.
	b.box(Vector3(x1 - 1.0, 1.13, 1.35), Vector3(0.45, 0.32, 0.4), Color("3a3a42"), "vc_gloss")
	b.box(Vector3(x1 - 1.0, 1.45, 1.3), Vector3(0.4, 0.05, 0.3), Color("2a2a30"), "vc_gloss")
	for k in range(3):
		b.cylinder(Vector3(x0 + 1.0 + k * 0.25, 1.13, 1.25), 0.03, 0.45, Color("c9ced6"), "vc_metal", 6)
	for k in range(5):
		b.cylinder(Vector3(mid - 0.8 + k * 0.4, 1.13, 1.55), 0.06, 0.16, Color("dfeff0"), "vc_gloss", 8)
	# Bar stools.
	var x: float = x0 + 0.8
	while x < x1 - 0.6:
		b.cylinder(Vector3(x, 0, 2.25), 0.05, 0.72, Color("2b2b30"), "vc_metal", 6)
		b.cylinder(Vector3(x, 0.72, 2.25), 0.22, 0.08, Color(t.stool), "vc_gloss", 12)
		x += 1.1

static func _stage(b: Builder, lay: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var s: Vector2i = lay.stage
	var top: Color = {"birtija": Color("7a5a3a"), "kafana": Color("6e1f22"), "restoran": Color("2a2a33"), "splav": Color("1f2a44")}[lay.id]
	b.box(Vector3(s.x / 2.0, 0, s.y / 2.0), Vector3(s.x, 0.35, s.y), top.darkened(0.25), "vc_gloss")
	b.box(Vector3(s.x / 2.0, 0.35, s.y / 2.0), Vector3(s.x - 0.1, 0.02, s.y - 0.1), top, "vc_gloss" if lay.id != "birtija" else "tex:planks_rough:0.4")
	var edge: Color = Color("d9a531") if lay.id in ["kafana", "restoran"] else top.lightened(0.2)
	b.box(Vector3(s.x / 2.0, 0.3, s.y), Vector3(s.x, 0.06, 0.06), edge, "vc_metal")
	b.box(Vector3(s.x, 0.3, s.y / 2.0), Vector3(0.06, 0.06, s.y), edge, "vc_metal")
	if lay.id in ["kafana", "restoran"]:
		# Velvet curtains in folds behind the band.
		var curtain: Color = Color("8a1f22") if lay.id == "kafana" else Color("1f2a5a")
		for k in range(int(s.x / 0.35)):
			var x: float = 0.2 + k * 0.35
			b.cylinder(Vector3(x, 0.35, 0.12), 0.17, WALL_H - 0.35, curtain.darkened(0.18 * (k % 2)), "vc", 8)
		for k in range(int(s.y / 0.35)):
			var z: float = 0.2 + k * 0.35
			b.cylinder(Vector3(0.12, 0.35, z), 0.17, WALL_H - 0.35, curtain.darkened(0.18 * (k % 2)), "vc", 8)
		b.box(Vector3(s.x / 2.0, WALL_H - 0.3, 0.2), Vector3(s.x, 0.4, 0.25), Color("d9a531"), "vc_metal")

## Warm lights over the floor (lights only: nothing hangs between the camera and the tables),
## sconces on the back walls and shaded pendants over the bar. Returns the lights for flicker
## and dimming.
static func _lamps(root: Node3D, lay: Dictionary, t: Dictionary) -> Array:
	var b: Builder = Builder.new()
	var lights: Array = []
	var colour: Color = Color(t.lamp)
	var spots: Array = []
	var cols: int = maxi(2, int(lay.cols) - 1)
	var rows: int = maxi(1, int(lay.rows) - 1) + 1
	for r in range(rows):
		for c in range(cols):
			spots.append(Vector3(lay.w * (c + 1.0) / (cols + 1.0), 2.6, lay.top + (lay.d - lay.top) * (r + 0.5) / rows))
	spots.append(Vector3((lay.bar_from + lay.bar_to) / 2.0, 2.4, 1.9))
	spots.append(Vector3(lay.stage.x / 2.0, 2.8, lay.stage.y / 2.0 + 0.6))
	for spot in spots:
		var pos: Vector3 = spot
		if lay.id == "splav":
			pos.y = 3.0
		lights.append(Kit.omni(root, pos - Vector3(0, 0.15, 0), colour, 1.6, 6.5))
	if lay.id != "splav":
		var lamp: String = t.lamp.to_lower()
		for k in range(int(lay.w / 4.0)):
			var x: float = 4.6 + k * 4.0
			if x < lay.w - 1.0 and (x < lay.bar_from - 0.4 or x > lay.bar_to + 0.4) and x > lay.stage.x + 0.4:
				_sconce(b, Vector3(x, 2.2, 0.0), 0.0, lamp, lay.id)
		for k in range(int((lay.d - lay.top) / 4.0)):
			var z: float = lay.top + 4.0 + k * 4.0
			if z < lay.d - 1.0:
				_sconce(b, Vector3(0.0, 2.2, z), PI / 2.0, lamp, lay.id)
		var length: float = lay.bar_to - lay.bar_from
		var count: int = maxi(2, int(length / 2.4))
		for k in range(count):
			_pendant(b, Vector3(lay.bar_from + (k + 0.5) * length / count, 2.45, 1.45), lamp, lay.id)
	b.commit(root, false)
	return lights

## A wall lamp: a small plate and a glowing shade standing off the wall.
static func _sconce(b: Builder, at: Vector3, turn: float, lamp: String, id: String) -> void:
	var xf: Transform3D = Transform3D(Basis(Vector3.UP, turn), at)
	var metal: Color = Color("d9a531") if id in ["kafana", "restoran"] else Color("3a3a32")
	b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.12, 0.03)), Vector3(0.12, 0.26, 0.04), metal, "vc_metal")
	b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.05, 0.1)), Vector3(0.04, 0.04, 0.14), metal, "vc_metal")
	b.cylinder_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0.18)), 0.1, 0.2, Color.WHITE, "glow:%s:1.6" % lamp, 10, 0.7)

## A lamp over the bar under an opaque shade, so from above it reads as a lamp and not a glare.
static func _pendant(b: Builder, at: Vector3, lamp: String, id: String) -> void:
	var shade: Color = {"birtija": Color("2f4a3a"), "kafana": Color("b8862a"), "restoran": Color("f4efe4")}.get(id, Color("2f4a3a"))
	var key: String = "vc_metal" if id == "kafana" else "vc_gloss"
	b.cylinder(at + Vector3(0, 0.22, 0), 0.012, WALL_H + 0.2 - at.y, Color("1d1d22"), "vc", 4)
	b.cylinder(at, 0.26, 0.24, shade, key, 14, 0.3)
	b.cylinder(at - Vector3(0, 0.01, 0), 0.25, 0.02, Color.WHITE, "glow:%s:1.2" % lamp, 14)
	b.sphere(at - Vector3(0, 0.03, 0), 0.07, Color.WHITE, "glow:%s:2.2" % lamp, Vector3.ONE, 8)

## A table, set for the venue; the chairs too unless they are drawn apart (see chair_mesh).
static func _dining_set(b: Builder, id: String, t: Dictionary, rng: RandomNumberGenerator, chairs: bool = true) -> void:
	var wood: Color = Color(t.table)
	var chair: Color = Color(t.chair)
	if id == "restoran":
		b.cylinder(Vector3.ZERO, 0.08, 0.72, Color("2a2a30"), "vc_metal", 8)
		b.cylinder(Vector3.ZERO, 0.3, 0.04, Color("2a2a30"), "vc_metal", 12)
		b.cylinder(Vector3(0, 0.48, 0), 0.66, 0.3, Color.WHITE, t.cloth, 20, 0.95)
		b.cylinder(Vector3(0, 0.76, 0), 0.62, 0.03, Color.WHITE, t.cloth, 20)
		b.cylinder(Vector3(0.15, 0.79, -0.1), 0.03, 0.18, Color("f4ead2"), "vc", 6)
		b.sphere(Vector3(0.15, 1.0, -0.1), 0.035, Color.WHITE, "glow:ffcf70:4.0")
	else:
		for corner in [Vector2(-0.42, -0.42), Vector2(0.42, -0.42), Vector2(-0.42, 0.42), Vector2(0.42, 0.42)]:
			b.box(Vector3(corner.x, 0, corner.y), Vector3(0.08, 0.72, 0.08), wood.darkened(0.2), "vc_gloss")
		b.box(Vector3(0, 0.72, 0), Vector3(1.05, 0.06, 1.05), wood, "vc_gloss" if t.cloth == "" else "vc")
		if t.cloth != "":
			b.box(Vector3(0, 0.5, 0), Vector3(1.14, 0.29, 1.14), Color.WHITE, t.cloth)
			b.box(Vector3(0, 0.78, 0), Vector3(1.12, 0.01, 1.12), Color.WHITE, t.cloth)
		if id == "splav":
			b.cylinder(Vector3(0.2, 0.79, 0.2), 0.06, 0.14, Color("e8e2d6"), "vc", 8)
			b.sphere(Vector3(0.2, 0.95, 0.2), 0.05, Color.WHITE, "glow:ffd890:3.0")
		elif id == "birtija":
			b.cylinder(Vector3(-0.2, 0.75, 0.15), 0.05, 0.2, Color("dfeff0"), "vc_gloss", 8)
			b.cylinder(Vector3(0.25, 0.75, -0.2), 0.11, 0.05, Color("c9ced6"), "vc_gloss", 10)
	if not chairs:
		return
	for seat in SEATS:
		var offset: Vector2 = seat.offset
		var turn: float = atan2(offset.x, offset.y)
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, turn), Vector3(offset.x, 0, offset.y))
		_chair(b, xf, id, chair)

## One of the venue's chairs on its own (its back towards +z), so chairs can slide out and back.
static func chair_mesh(id: String) -> ArrayMesh:
	var b: Builder = Builder.new()
	_chair(b, Transform3D.IDENTITY, id, Color(THEMES[id].chair))
	return b.mesh()

## A chair whose back faces away from the table (local +Z points away from it).
static func _chair(b: Builder, xf: Transform3D, id: String, colour: Color) -> void:
	var key: String = "vc_gloss"
	for corner in [Vector2(-0.19, -0.19), Vector2(0.19, -0.19), Vector2(-0.19, 0.19), Vector2(0.19, 0.19)]:
		b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(corner.x, 0.0, corner.y)), Vector3(0.05, 0.45, 0.05), colour.darkened(0.15), key)
	var seat_colour: Color = Color("9a2a32") if id == "restoran" else colour
	b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), Vector3(0.46, 0.06, 0.46), seat_colour, "vc" if id == "restoran" else key)
	if id == "kafana":
		# Bentwood back: two posts and a curved rail.
		for x in [-0.17, 0.17]:
			b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(x, 0.5, 0.2)), Vector3(0.05, 0.55, 0.05), colour, key)
		b.cylinder_xf(xf * Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(-0.2, 0.98, 0.2)), 0.035, 0.4, colour, key, 6)
		b.cylinder_xf(xf * Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(-0.2, 0.75, 0.2)), 0.025, 0.4, colour, key, 6)
	else:
		var back_h: float = 0.6 if id != "restoran" else 0.7
		b.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0.21)), Vector3(0.46, back_h, 0.05), seat_colour if id == "restoran" else colour, key)

static func _plant(b: Builder, at: Vector3, kind: String) -> void:
	match kind:
		"palm":
			b.cylinder(at, 0.28, 0.5, Color("e8e2d6"), "vc_gloss", 12, 0.85)
			b.cylinder(at + Vector3(0, 0.5, 0), 0.05, 1.1, Color("6e5a3a"), "vc", 6)
			for k in range(7):
				var a: float = k * TAU / 7.0
				b.sphere(at + Vector3(cos(a) * 0.38, 1.65, sin(a) * 0.38), 0.32, Color("2f6a3a").lightened(0.1 * (k % 2)), "vc", Vector3(1.4, 0.35, 0.6), 8)
		"barrel":
			b.cylinder(at, 0.36, 0.95, Color("7a4a2c"), "vc_gloss", 14)
			for y in [0.15, 0.8]:
				b.cylinder(at + Vector3(0, y, 0), 0.375, 0.06, Color("3a3a3a"), "vc_metal", 14)
		_:
			b.cylinder(at, 0.26, 0.45, Color("a8532f"), "vc_gloss", 12, 0.8)
			for k in range(8):
				var a: float = k * TAU / 8.0
				b.sphere(at + Vector3(cos(a) * 0.18, 0.75 + 0.15 * (k % 3), sin(a) * 0.18), 0.3, Color("3d7a3a").darkened(0.1 * (k % 2)), "vc", Vector3.ONE, 8)

static func _painting(b: Builder, at: Vector3, turn: float, name: String, size: Vector2, frame: Color) -> void:
	var xf: Transform3D = Transform3D(Basis(Vector3.UP, turn), at)
	b.box_xf(xf, Vector3(size.x + 0.16, size.y + 0.16, 0.06), frame, "vc_metal")
	b.add(Kit.unit("quad"), xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(size.x, 1, size.y)), Vector3(0, (size.y + 0.16) / 2.0, 0.04)), Color.WHITE, "uv:" + name)

# ---------------------------------------------------------------------------------------------
# Theme decor
# ---------------------------------------------------------------------------------------------

static func _birtija_decor(b: Builder, lay: Dictionary, rng: RandomNumberGenerator) -> void:
	var d: float = lay.d
	var w: float = lay.w
	# Smederevac: the white enamel wood stove, with its pipe up the wall.
	var stove: Vector3 = Vector3(0.6, 0, lay.top + 0.2)
	b.box(stove, Vector3(0.8, 0.85, 0.6), Color("eeeae0"), "vc_gloss")
	b.box(stove + Vector3(0, 0.85, 0), Vector3(0.84, 0.05, 0.64), Color("2b2b30"), "vc_metal")
	b.box(stove + Vector3(0.41, 0.3, 0), Vector3(0.02, 0.3, 0.3), Color("2b2b30"), "vc_metal")
	b.cylinder(stove + Vector3(-0.2, 0.9, 0), 0.08, WALL_H, Color("3a3a3a"), "vc_metal", 8)
	b.sphere(stove + Vector3(0.42, 0.4, 0), 0.07, Color.WHITE, "glow:ff8a3a:3.0")
	# Ristra of red peppers and garlic on the walls, hats on pegs.
	for k in range(3):
		var z: float = lay.top + 4.0 + k * 3.0
		if z > d - 1.0:
			break
		for j in range(9):
			b.sphere(Vector3(0.1, 2.5 - j * 0.12, z + sin(j) * 0.04), 0.06, Color("c0322c").darkened(0.15 * (j % 2)), "vc_gloss", Vector3(0.8, 1.3, 0.8), 6)
	for k in range(4):
		var x: float = lay.stage.x + 0.7 + k * 0.5
		b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(x, 2.4, 0.0)), 0.025, 0.2, Color("4a3020"), "vc", 6)
	for k in range(2):
		var at: Vector3 = Vector3(lay.stage.x + 0.7 + k * 1.0, 2.3, 0.14)
		b.cylinder(at, 0.17, 0.1, Color("4a5a3a"), "vc", 10, 0.85)
		b.box(at + Vector3(0, 0.1, 0), Vector3(0.26, 0.06, 0.1), Color("3a4a2c"), "vc")
	_painting(b, Vector3(0.05, 1.6, lay.top + 2.0), PI / 2.0, "painting_portrait", Vector2(0.7, 0.55), Color("6e4528"))
	# A big barrel and crates by the bar, a bench along the wall.
	_plant(b, Vector3(w - 0.6, 0, 0.6), "barrel")
	b.box(Vector3(w - 0.6, 0, 1.6), Vector3(0.6, 0.45, 0.6), Color("e8dcc8"), "tex:planks_rough:0.8")
	b.box(Vector3(0.35, 0, d - 3.0), Vector3(0.5, 0.42, 3.4), Color("7a4a2c"), "vc_gloss")
	# Calendar and clock.
	b.box(Vector3(lay.bar_to - 0.8, 2.0, 0.02), Vector3(0.5, 0.6, 0.02), Color("f4ead2"))
	b.box(Vector3(lay.bar_to - 0.8, 2.48, 0.03), Vector3(0.5, 0.14, 0.02), Color("c0322c"))
	b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, 2.3, lay.top + 6.0)), 0.22, 0.06, Color("f4ead2"), "vc", 16)

static func _kafana_decor(b: Builder, lay: Dictionary, rng: RandomNumberGenerator) -> void:
	var d: float = lay.d
	var w: float = lay.w
	_painting(b, Vector3(0.05, 1.5, lay.top + 3.0), PI / 2.0, "painting_landscape", Vector2(1.2, 0.9), Color("d9a531"))
	_painting(b, Vector3(0.05, 1.5, lay.top + 9.0), PI / 2.0, "painting_still", Vector2(0.9, 0.7), Color("d9a531"))
	# A kilim hung on the wall.
	b.add(Kit.unit("quad"), Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.3, 1, 1.9)), Vector3(0.05, 1.95, lay.top + 6.0)), Color.WHITE, "uv:rug_kilim")
	# Coat rack by the door, an old radio on a sideboard, plants.
	var rack: Vector3 = Vector3(w - 0.6, 0, d - 1.2)
	b.cylinder(rack, 0.04, 1.9, Color("3a2016"), "vc_gloss", 6)
	b.cylinder(rack, 0.25, 0.04, Color("3a2016"), "vc_gloss", 10)
	b.sphere(rack + Vector3(0.1, 1.7, 0), 0.16, Color("2b2b33"), "vc", Vector3(1.0, 1.4, 0.7), 8)
	b.box(Vector3(0.35, 0, lay.top + 11.0), Vector3(0.6, 0.85, 1.6), Color("4a2a18"), "vc_gloss")
	b.box(Vector3(0.35, 0.85, lay.top + 11.0), Vector3(0.4, 0.32, 0.55), Color("6e4528"), "vc_gloss")
	b.box(Vector3(0.56, 0.95, lay.top + 11.0), Vector3(0.02, 0.18, 0.4), Color("e0c48a"), "vc")
	_plant(b, Vector3(w - 0.6, 0, lay.top + 0.6), "ficus")
	_plant(b, Vector3(0.6, 0, d - 0.6), "ficus")

static func _restoran_decor(b: Builder, lay: Dictionary, rng: RandomNumberGenerator) -> void:
	var d: float = lay.d
	var w: float = lay.w
	# Grand piano on the stage.
	var p: Vector3 = Vector3(1.6, 0.35, 1.5)
	b.box(p + Vector3(0, 0.0, 0), Vector3(0.1, 0.65, 0.1), Color("15151a"), "vc_gloss")
	b.box(p + Vector3(1.2, 0.0, 0.3), Vector3(0.1, 0.65, 0.1), Color("15151a"), "vc_gloss")
	b.box(p + Vector3(0.2, 0.0, 0.9), Vector3(0.1, 0.65, 0.1), Color("15151a"), "vc_gloss")
	b.box(p + Vector3(0.6, 0.65, 0.45), Vector3(1.5, 0.32, 1.1), Color("101014"), "vc_gloss", 0.35)
	b.box(p + Vector3(-0.05, 0.86, 0.55), Vector3(0.95, 0.06, 0.25), Color("f4f1ea"), "vc_gloss", 0.35)
	# Gilded mirrors and paintings, palms in the corners.
	for k in range(3):
		var z: float = lay.top + 2.5 + k * 5.0
		if z > d - 2.0:
			break
		_painting(b, Vector3(0.05, 1.5, z), PI / 2.0, ["painting_river", "painting_landscape", "painting_portrait"][k], Vector2(1.3, 1.0), Color("d9a531"))
	_plant(b, Vector3(w - 0.6, 0, lay.top + 0.6), "palm")
	_plant(b, Vector3(0.7, 0, d - 0.7), "palm")
	_plant(b, Vector3(w - 0.6, 0, d - 2.4), "palm")
	# Wine rack along the back wall.
	b.box(Vector3(lay.bar_to - 0.5, 0, 0.3), Vector3(0.9, 2.4, 0.5), Color("3a2016"), "vc_gloss")
	for r in range(6):
		for c in range(3):
			b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(lay.bar_to - 0.8 + c * 0.3, 0.3 + r * 0.36, 0.3)), 0.06, 0.4, Color("4a1a24"), "vc_gloss", 6)

static func _splav_decor(b: Builder, lay: Dictionary, rng: RandomNumberGenerator) -> void:
	var w: float = lay.w
	var d: float = lay.d
	# Speakers by the stage, life rings on the rail, flags.
	for x in [0.5, lay.stage.x - 0.5]:
		b.box(Vector3(x, 0.35, lay.stage.y - 0.4), Vector3(0.6, 1.4, 0.5), Color("1d1d22"), "vc_gloss")
		b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(x, 0.8, lay.stage.y - 0.14)), 0.2, 0.03, Color("3a3a44"), "vc", 12)
	for z in [lay.top + 3.0, lay.top + 11.0]:
		b.cylinder_xf(Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(w + 0.55, 0.8, z)), 0.3, 0.08, Color("f26a2a"), "vc_gloss", 14)
		for a in [0.0, PI / 2.0, PI, PI * 1.5]:
			b.box(Vector3(w + 0.6, 0.8 + sin(a) * 0.26, z + cos(a) * 0.26), Vector3(0.1, 0.1, 0.1), Color("f4f1ea"), "vc")

## A thin cord between two points (string lights).
static func _cord(b: Builder, from: Vector3, to: Vector3) -> void:
	var along: Vector3 = to - from
	var up: Vector3 = along.normalized()
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var basis: Basis = Basis(side, up, side.cross(up))
	b.cylinder_xf(Transform3D(basis, from), 0.012, along.length(), Color("1d1d22"), "vc", 4)

## The splav: a deck on pontoons, railings all round and a canopy frame of string lights.
static func _raft(b: Builder, lay: Dictionary, rng: RandomNumberGenerator) -> void:
	var w: float = lay.w
	var d: float = lay.d
	for k in range(int(w / 3.0) + 1):
		b.box(Vector3(1.0 + k * 3.0 - 0.5, -0.9, d / 2.0), Vector3(1.6, 0.8, d + 0.6), Color("c9ced6"), "vc_gloss")
	b.box(Vector3(w / 2.0, -0.26, d / 2.0), Vector3(w + 0.8, 0.22, d + 0.8), Color("6e5a44"), "vc")
	b.box(Vector3(w / 2.0, -0.02, d / 2.0), Vector3(w + 0.6, 0.02, d + 0.6), Color.WHITE, "tex:planks_deck:0.4")
	var rail: Color = Color("f4f1ea")
	var x: float = -0.2
	while x <= w + 0.3:
		b.box(Vector3(x, 0, d + 0.3), Vector3(0.07, 1.0, 0.07), rail, "vc_gloss")
		b.box(Vector3(x, 0, -0.3), Vector3(0.07, 1.0, 0.07), rail, "vc_gloss")
		x += 1.0
	var z: float = -0.3
	while z <= d + 0.3:
		b.box(Vector3(w + 0.3, 0, z), Vector3(0.07, 1.0, 0.07), rail, "vc_gloss")
		b.box(Vector3(-0.3, 0, z), Vector3(0.07, 1.0, 0.07), rail, "vc_gloss")
		z += 1.0
	for spec in [[Vector3(w / 2.0, 1.0, d + 0.3), Vector3(w + 0.7, 0.07, 0.09)], [Vector3(w / 2.0, 1.0, -0.3), Vector3(w + 0.7, 0.07, 0.09)],
			[Vector3(w + 0.3, 1.0, d / 2.0), Vector3(0.09, 0.07, d + 0.7)], [Vector3(-0.3, 1.0, d / 2.0), Vector3(0.09, 0.07, d + 0.7)]]:
		b.box(spec[0], spec[1], rail, "vc_gloss")
	# Gap in the rail for the gangway.
	b.box(Vector3(lay.door_x + 0.6, -0.05, d + 4.3), Vector3(1.4, 0.08, 8.0), Color("f0e8dc"), "tex:planks_deck:0.6")
	for k in range(9):
		for side in [-0.7, 0.7]:
			b.box(Vector3(lay.door_x + 0.6 + side, 0, d + 0.6 + k), Vector3(0.05, 0.9, 0.05), Color("f4f1ea"), "vc_gloss")
	# Canopy posts and string lights.
	var posts: Array = []
	for px in [0.0, w / 2.0, w]:
		for pz in [lay.top - 0.5, d]:
			posts.append(Vector3(px, 0, pz))
	for post in posts:
		b.cylinder(post, 0.07, 3.2, Color("e8e2d6"), "vc_gloss", 8)
	# String lights: bulbs on a sagging cord between the posts.
	for zz in [lay.top - 0.5, d]:
		var previous: Vector3 = Vector3(0, 3.1, zz)
		var steps: int = int(w / 0.8)
		for k in range(1, steps + 1):
			var bx: float = w * k / steps
			var point: Vector3 = Vector3(bx, 3.1 - sin(bx / w * PI) * 0.45, zz)
			_cord(b, previous, point)
			b.sphere(point - Vector3(0, 0.06, 0), 0.06, Color.WHITE, "glow:ffd890:2.4", Vector3.ONE, 6)
			previous = point
	# The back wall of the splav is the bar hut under a striped canvas awning, like its roof on the map.
	var mid: float = (lay.bar_from + lay.bar_to) / 2.0
	var span: float = lay.bar_to - lay.bar_from + 1.0
	b.box(Vector3(mid, 0, -0.1), Vector3(span - 0.4, 2.6, 0.2), Color("d8c8b4"), "tex:planks_deck:0.5")
	var stripes: int = int(span / 0.5)
	var slope: float = atan2(0.6, 2.6)
	for k in range(stripes):
		var sx: float = lay.bar_from - 0.5 + (k + 0.5) * span / stripes
		var stripe: Color = Color("c0322c") if k % 2 == 0 else Color("f4f1ea")
		b.box_xf(Transform3D(Basis(Vector3.RIGHT, slope), Vector3(sx, 2.65, 1.25)), Vector3(span / stripes + 0.01, 0.06, 2.7), stripe, "vc")
		b.box(Vector3(sx, 2.15, 2.55), Vector3(span / stripes + 0.01, 0.25, 0.04), stripe, "vc")
	for px in [lay.bar_from - 0.4, lay.bar_to + 0.4]:
		b.cylinder(Vector3(px, 0, 2.5), 0.05, 2.3, Color("e8e2d6"), "vc_gloss", 8)
	# Planters along the rail.
	for px in [w * 0.25, w * 0.75]:
		b.box(Vector3(px, 0, d - 0.1), Vector3(1.4, 0.45, 0.45), Color("d8c8b4"), "tex:planks_deck:0.6")
		for k in range(4):
			b.sphere(Vector3(px - 0.5 + k * 0.33, 0.6, d - 0.1), 0.22, Color("4f8a46").darkened(0.12 * (k % 2)), "vc", Vector3.ONE, 8)

# ---------------------------------------------------------------------------------------------
# Exterior: the venue as a building on the map
# ---------------------------------------------------------------------------------------------

## state: "owned" (lit), "next" (for sale, dark), "locked" (dark and quiet).
static func build_exterior(root: Node3D, lay: Dictionary, state: String) -> void:
	var id: String = lay.id
	var t: Dictionary = THEMES[id]
	var b: Builder = Builder.new(8.0)
	var w: float = lay.w
	var d: float = lay.d
	var lit: bool = state == "owned"
	var warm: String = "glow:ffb060:1.4" if lit else "glow:2d3a5a:0.5"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(id) + 7
	if id == "splav":
		_raft(b, lay, rng)
		var canopy: Color = Color("b8392f") if lit else Color("6a3a3a")
		var mid_z: float = d / 2.0 + lay.top / 2.0 - 0.25
		var depth: float = d - lay.top + 1.5
		# One striped gable over the deck: slices of the same roof, ridge along x.
		for k in range(int((w + 1.0) / 1.5)):
			var x: float = -0.5 + k * 1.5 + 0.75
			b.prism(Vector3(x, 3.0, mid_z), Vector3(depth, 2.2, 1.5), canopy if k % 2 == 0 else (Color("f4ead2") if lit else Color("8a8070")), "vc", PI / 2.0)
		for k in range(int(w / 3.0) + 1):
			b.box(Vector3(k * 3.0, 4.4, mid_z), Vector3(0.05, 1.2, 0.05), Color("e8e2d6"))
			b.box(Vector3(k * 3.0 + 0.3, 5.3, mid_z), Vector3(0.6, 0.35, 0.02), [Color("c0322c"), Color("2f5fa8"), Color("f4f1ea")][k % 3])
		b.commit(root)
		return
	var storeys: int = int(t.storeys)
	var height: float = 3.4 * storeys
	var wall: Color = Color(t.facade_tint)
	b.box(Vector3(w / 2.0, -0.28, d / 2.0), Vector3(w + 0.6, 0.25, d + 0.6), Color("e6e2dc"), "tex:sidewalk:0.4")
	b.box(Vector3(w / 2.0, 0, d / 2.0), Vector3(w, height, d), wall, t.facade if id != "birtija" else "tex:plaster_warm:0.25")
	b.box(Vector3(w / 2.0, 0, d / 2.0), Vector3(w + 0.12, 0.7, d + 0.12), wall.lerp(Color.WHITE, 0.3), "tex:stone_wall:0.5")
	for s in range(1, storeys + 1):
		b.box(Vector3(w / 2.0, 3.4 * s - 0.2, d / 2.0), Vector3(w + 0.3, 0.22, d + 0.3), wall.darkened(0.12))
	var shutter: Color = {"birtija": Color("5a3a22"), "kafana": Color("3d6a4a"), "restoran": Color("f4efe4")}[id]
	for s in range(storeys):
		var y: float = 1.0 + s * 3.4
		var tall: float = 2.2 if id == "restoran" else (1.9 if s == 0 and id == "kafana" else 1.5)
		var wide: float = 1.5 if s == 0 and id == "kafana" else 1.0
		for side in ["south", "east"]:
			var length: float = w if side == "south" else d
			var count: int = maxi(1, int(length / (3.0 if wide > 1.2 else 2.4)))
			for k in range(count):
				var u: float = (k + 0.5) * length / count
				var p: Vector3 = Vector3(u, y, d + 0.03) if side == "south" else Vector3(w + 0.03, y, u)
				if side == "south" and s == 0 and absf(u - (lay.door_x + 0.6)) < 1.6:
					continue
				var face: Vector3 = Vector3(wide, tall, 0.06) if side == "south" else Vector3(0.06, tall, wide)
				var frame: Color = wall.lightened(0.35) if id == "restoran" else Color("2b1d14")
				b.box(p - Vector3(0, 0.08, 0), face + Vector3(0.24, 0.24, 0.0) if side == "south" else face + Vector3(0.0, 0.24, 0.24), frame)
				var glass: String = warm if lit else ("glow:ffb060:1.0" if rng.randf() < 0.5 else "glow:2d3a5a:0.5")
				b.box(p, face, Color.WHITE, glass if (not lit or rng.randf() < 0.85) else "glow:2d3a5a:0.5")
				if id == "restoran":
					# Classical pediments and a mullion cross.
					var mull: Vector3 = Vector3(0.06, tall, 0.03) if side == "south" else Vector3(0.03, tall, 0.06)
					b.box(p + (Vector3(0, 0, 0.04) if side == "south" else Vector3(0.04, 0, 0)), mull, frame)
					var top_at: Vector3 = p + Vector3(0, tall + 0.12, 0) + (Vector3(0, 0, 0.05) if side == "south" else Vector3(0.05, 0, 0))
					b.prism(top_at, Vector3(wide + 0.5, 0.35, 0.14), frame, "vc", 0.0 if side == "south" else PI / 2.0)
				var sill: Vector3 = Vector3(wide + 0.3, 0.1, 0.25) if side == "south" else Vector3(0.25, 0.1, wide + 0.3)
				b.box(p - Vector3(0, 0.12, 0) + (Vector3(0, 0, 0.1) if side == "south" else Vector3(0.1, 0, 0)), sill, wall.darkened(0.2))
				if id != "restoran":
					var off: Vector3 = Vector3(wide / 2.0 + 0.22, 0, 0.03) if side == "south" else Vector3(0.03, 0, wide / 2.0 + 0.22)
					var leaf: Vector3 = Vector3(0.36, tall, 0.05) if side == "south" else Vector3(0.05, tall, 0.36)
					b.box(p - off, leaf, shutter)
					b.box(p + off, leaf, shutter)
				if s > 0 and id == "kafana":
					var box_at: Vector3 = p - Vector3(0, 0.3, 0) + (Vector3(0, 0, 0.32) if side == "south" else Vector3(0.32, 0, 0))
					b.box(box_at, Vector3(wide + 0.1, 0.25, 0.3) if side == "south" else Vector3(0.3, 0.25, wide + 0.1), Color("6e4528"))
					for f in range(4):
						var fp: Vector3 = box_at + (Vector3(-0.36 + f * 0.24, 0.32, 0) if side == "south" else Vector3(0, 0.32, -0.36 + f * 0.24))
						b.sphere(fp, 0.13, [Color("d9536a"), Color("f2b83a"), Color("c0322c"), Color("f4f1ea")][f], "vc", Vector3.ONE, 6)
	# Door, lamps and sign on the street side.
	var door: Vector3 = Vector3(lay.door_x + 0.6, 0, d + 0.06)
	b.box(door, Vector3(1.4, 2.5, 0.12), Color("4a2a18"), "vc_gloss")
	b.box(door + Vector3(0, 0.3, 0.05), Vector3(1.0, 1.6, 0.04), Color.WHITE, "glow:ffc070:1.6" if lit else "glow:2d3a5a:0.5")
	for x in [-1.0, 1.0]:
		b.sphere(door + Vector3(x, 2.3, 0.25), 0.12, Color.WHITE, "glow:ffd38a:4.0" if lit else "glow:4a4a5a:0.4")
	b.box(Vector3(lay.door_x + 0.6, 2.85, d + 0.14), Vector3(2.9, 0.95, 0.12), Color("2b1d14"))
	b.panel(Vector3(lay.door_x + 0.6, 3.32, d + 0.22), Vector2(2.8, 0.82), Color.WHITE if state != "locked" else Color(0.55, 0.55, 0.6), "uv:sign_" + id)
	match id:
		"birtija":
			# A wooden porch along the front with a bench and a lantern.
			b.box(Vector3(w / 2.0, 0, d + 1.2), Vector3(w - 1.0, 0.2, 2.2), Color("e8dcc8"), "tex:planks_rough:0.6")
			for k in range(5):
				b.box(Vector3(1.0 + k * (w - 2.0) / 4.0, 0.2, d + 2.15), Vector3(0.16, 2.6, 0.16), Color("6e4528"))
			b.box(Vector3(w / 2.0, 2.8, d + 1.3), Vector3(w - 0.6, 0.14, 2.6), Color("6e4528"))
			b.box(Vector3(2.4, 0.2, d + 0.6), Vector3(1.8, 0.42, 0.45), Color("7a4a2c"), "vc_gloss")
			_plant(b, Vector3(w - 1.2, 0.2, d + 1.2), "barrel")
		"kafana":
			# Striped awning over the ground-floor windows.
			for k in range(int(w / 0.6)):
				b.box(Vector3(0.3 + k * 0.6, 3.0, d + 0.75), Vector3(0.6, 0.1, 1.5), Color("c0322c") if k % 2 == 0 else Color("f4ead2"))
			for k in range(int(w / 0.6)):
				b.box(Vector3(0.3 + k * 0.6, 2.75, d + 1.5), Vector3(0.6, 0.35, 0.05), Color("c0322c") if k % 2 == 0 else Color("f4ead2"))
			_plant(b, Vector3(0.8, 0, d + 0.6), "ficus")
		"restoran":
			# Pilasters, a balcony with a balustrade over the door and a corner dome.
			for k in range(int(w / 3.0) + 1):
				b.box(Vector3(k * 3.0, 0.7, d + 0.12), Vector3(0.4, height - 1.0, 0.18), Color("f8f4ea"))
			b.box(Vector3(lay.door_x + 0.6, 3.4, d + 0.7), Vector3(4.0, 0.2, 1.4), Color("e8e2d6"))
			for k in range(9):
				b.cylinder(Vector3(lay.door_x - 1.2 + k * 0.45, 3.6, d + 1.3), 0.07, 0.75, Color("f8f4ea"), "vc", 8)
			b.box(Vector3(lay.door_x + 0.6, 4.35, d + 1.3), Vector3(4.0, 0.12, 0.2), Color("e8e2d6"))
			b.cylinder(Vector3(w - 2.0, height, d - 2.0), 1.8, 1.4, Color("e8e2d6"), "vc", 16)
			b.sphere(Vector3(w - 2.0, height + 1.4, d - 2.0), 1.8, Color("4a7a8a"), "vc_metal", Vector3(1, 0.9, 1), 16)
			b.sphere(Vector3(w - 2.0, height + 3.2, d - 2.0), 0.2, Color("d9a531"), "vc_metal")
	# Roof.
	if str(t.roof) != "":
		var pitch: float = minf(w, d) * 0.42
		b.prism(Vector3(w / 2.0, height, d / 2.0), Vector3(d + 0.8, pitch, w + 0.8), Color.WHITE, "tex:roof_tiles:0.35", PI / 2.0)
		b.box(Vector3(w * 0.7, height + pitch * 0.4, d * 0.4), Vector3(0.7, pitch * 0.75, 0.7), Color("f4e4dc"), "tex:bricks:0.6")
	else:
		b.box(Vector3(w / 2.0, height, d / 2.0), Vector3(w + 0.4, 0.5, d + 0.4), wall.darkened(0.08))
		b.box(Vector3(w / 2.0, height + 0.5, d / 2.0), Vector3(w - 0.6, 0.06, d - 0.6), Color("a49e98"))
		for k in range(int(w / 0.8)):
			b.box(Vector3(0.4 + k * 0.8, height + 0.5, d + 0.1), Vector3(0.14, 0.55, 0.14), wall)
		b.box(Vector3(w / 2.0, height + 1.05, d + 0.1), Vector3(w + 0.2, 0.12, 0.26), wall)
	b.commit(root)
