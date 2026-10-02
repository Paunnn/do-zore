extends Node3D
## The night city that is the game's map. The road from the birtija to the splav climbs up the
## screen through four districts: the village edge, the cobbled old town, the city centre and the
## river quay where the splav is moored under a lit bridge.
##
## Streets form a grid along the world axes (blocks every 52 m). A district is decided by how far
## a block lies along the road ("up" the screen). Every venue owns a lot on its block; the played
## venue is built separately as a cut-away, the others stand here as closed buildings.
const Kit = preload("res://scripts/world3d/kit3d.gd")
const Builder = preload("res://scripts/world3d/builder.gd")
const Venue = preload("res://scripts/world3d/venue3d.gd")
const BLOCK = 52.0
const STREET = 9.0
const ROAD = 6.0
const RIVER_NEAR = -224.0
const RIVER_FAR = -296.0
## Lot corners (the venue's local origin) for each venue, chosen on blocks along the road.
const LOTS = {
	"birtija": Vector3(14, 0, 33),
	"kafana": Vector3(-34, 0, -28),
	"restoran": Vector3(-86, 0, -84),
	"splav": Vector3(-139, 0, -141),
}

var lots: Dictionary = {}
## Areas in front of the played venue (toward the camera) where buildings stay one storey low.
var low_zones: Array = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var traffic: Array = []
var time: float = 0.0

## Up the screen: how far a point lies along the road (metres, birtija ~ -45, splav ~ 190).
static func along(point: Vector3) -> float:
	return -(point.x + point.z) / sqrt(2.0)

static func across(point: Vector3) -> float:
	return (point.x - point.z) / sqrt(2.0)

static func district(point: Vector3) -> String:
	var t: float = along(point)
	if t < -12.0: return "village"
	if t < 62.0: return "oldtown"
	if t < 140.0: return "center"
	return "quay"

## active: the venue being played (left empty here); states: venue id -> "owned"|"next"|"locked".
func build(active: String, states: Dictionary, max_tables: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	traffic.clear()
	rng.seed = 1912
	lots.clear()
	for id in LOTS:
		var lay: Dictionary = Venue.layout(id, int(max_tables.get(id, 6)))
		lots[id] = {"origin": LOTS[id], "lay": lay}
	low_zones.clear()
	if lots.has(active):
		var o: Vector3 = lots[active].origin
		var lay: Dictionary = lots[active].lay
		low_zones.append(Rect2(o.x - 14.0, o.z + lay.d, lay.w + 40.0, 30.0))
		low_zones.append(Rect2(o.x + lay.w, o.z - 14.0, 30.0, lay.d + 40.0))
	var b: Builder = Builder.new(64.0)
	_ground(b)
	_river(b)
	for bx in range(-6, 3):
		for bz in range(-6, 3):
			_block(b, bx, bz)
	_streets(b)
	_quay(b)
	_bridge(b)
	_far_bank(b)
	b.commit(self)
	for id in lots:
		if id == active:
			continue
		var node: Node3D = Node3D.new()
		node.position = lots[id].origin
		add_child(node)
		Venue.build_exterior(node, lots[id].lay, str(states.get(id, "locked")))
	_traffic()

# --------------------------------------------------------------------------------------------
# Ground, streets and blocks
# --------------------------------------------------------------------------------------------

func _ground(b: Builder) -> void:
	# A wide dark base so the city never shows its edge.
	b.box(Vector3(-80, -1.2, -80), Vector3(560, 0.3, 560), Color("1c2a22"), "vc")
	# A lawn strip between the last blocks and the quay.
	_diag_box(b, -RIVER_NEAR / sqrt(2.0) - 30.0, 0.0, Vector3(320, 0.42, 34.0), Color("8aa88a"), "tex:grass:0.25", -0.5)

func _block_rect(bx: int, bz: int) -> Rect2:
	return Rect2(bx * BLOCK + STREET / 2.0, bz * BLOCK + STREET / 2.0, BLOCK - STREET, BLOCK - STREET)

func _in_water(x: float, z: float) -> bool:
	return x + z < RIVER_NEAR - 18.0

func _block(b: Builder, bx: int, bz: int) -> void:
	var r: Rect2 = _block_rect(bx, bz)
	var c: Vector3 = Vector3(r.get_center().x, 0, r.get_center().y)
	if r.position.x + r.position.y < RIVER_NEAR + 22.0 or absf(across(c)) > 95.0 or along(c) < -110.0:
		return
	var kind: String = district(c)
	if kind == "quay" and c.x + c.z < RIVER_NEAR + 30.0:
		return
	var ground: String = {"village": "tex:grass:0.25", "oldtown": "tex:paving:0.35", "center": "tex:paving:0.3", "quay": "tex:paving:0.3"}[kind]
	var tint: Color = {"village": Color("9ab89a"), "oldtown": Color("c8bfb2"), "center": Color("b8b2aa"), "quay": Color("b8b2aa")}[kind]
	b.box(Vector3(c.x, -0.46, c.z), Vector3(r.size.x, 0.42, r.size.y), tint, ground)
	var keep_out: Array = []
	for id in lots:
		var origin: Vector3 = lots[id].origin
		var lay: Dictionary = lots[id].lay
		var lot: Rect2 = Rect2(origin.x - 3.0, origin.z - 3.0, lay.w + 6.0, lay.d + 9.0)
		if lot.intersects(r):
			keep_out.append(lot)
	match kind:
		"village": _village_block(b, r, keep_out)
		"oldtown": _town_block(b, r, keep_out, 2, 3, true)
		"center":
			if bx == -2 and bz == -1:
				_square(b, r)
			else:
				_town_block(b, r, keep_out, 4, 6, false)
		"quay": _park_block(b, r, keep_out)

func _free(rect: Rect2, keep_out: Array) -> bool:
	for k in keep_out:
		if k.intersects(rect):
			return false
	return true

## Village: a few houses in gardens behind wooden fences, fruit trees and haystacks.
func _village_block(b: Builder, r: Rect2, keep_out: Array) -> void:
	for k in range(6):
		var w: float = rng.randf_range(7, 10)
		var d: float = rng.randf_range(6, 8)
		var x: float = r.position.x + rng.randf_range(1, r.size.x - w - 1)
		var z: float = r.position.y + rng.randf_range(1, r.size.y - d - 1)
		var rect: Rect2 = Rect2(x - 1.5, z - 1.5, w + 3, d + 3)
		if not _free(rect, keep_out):
			continue
		keep_out.append(rect)
		_house(b, Vector3(x, 0, z), Vector3(w, 3.0, d), Color(["f2e2c4", "e8d8b8", "f4ead2", "e6cfa6", "dcc9b0"][k % 5]), true)
		_fence(b, rect.grow(0.5))
	for k in range(9):
		var p: Vector3 = Vector3(r.position.x + rng.randf_range(2, r.size.x - 2), 0, r.position.y + rng.randf_range(2, r.size.y - 2))
		if not _free(Rect2(p.x - 1.5, p.z - 1.5, 3, 3), keep_out):
			continue
		if k % 4 == 3:
			b.cylinder(p, 1.4, 2.0, Color("c9a24a"), "vc", 12, 0.25)
		else:
			_tree(b, p, rng.randf_range(0.8, 1.2), "fruit")

func _fence(b: Builder, rect: Rect2) -> void:
	var wood: Color = Color("6e5a3a")
	for side in range(4):
		var a: Vector2 = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)][side]
		var c: Vector2 = [Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position][side]
		var length: float = a.distance_to(c)
		var steps: int = int(length / 1.2)
		for s in range(steps + 1):
			var p: Vector2 = a.lerp(c, float(s) / maxi(1, steps))
			b.box(Vector3(p.x, 0, p.y), Vector3(0.1, 0.9, 0.1), wood)
		var mid: Vector2 = (a + c) / 2.0
		var horizontal: bool = absf(a.y - c.y) < 0.01
		b.box(Vector3(mid.x, 0.55, mid.y), Vector3(length if horizontal else 0.06, 0.08, 0.06 if horizontal else length), wood)

## Old town and centre: buildings shoulder to shoulder around the block's street edges.
func _town_block(b: Builder, r: Rect2, keep_out: Array, low: int, high: int, roofs: bool) -> void:
	var depth: float = 11.0
	var colors: Array = ["e6cfa6", "d9a596", "9fb3c6", "efe9de", "c9d6b8", "e8c49a", "b8c4d0", "f0d8c8"]
	# Front row along the south street (z = r.end.y) and the east street (x = r.end.x).
	var x: float = r.position.x
	while x < r.end.x - 4.0:
		var w: float = minf(rng.randf_range(7, 12), r.end.x - x)
		var rect: Rect2 = Rect2(x, r.end.y - depth, w - 0.2, depth)
		if _free(rect, keep_out):
			_town_house(b, rect, rng.randi_range(low, high), Color(colors[rng.randi() % colors.size()]), roofs, "south")
		x += w
	var z: float = r.position.y
	while z < r.end.y - depth - 4.0:
		var d: float = minf(rng.randf_range(7, 12), r.end.y - depth - z)
		var rect: Rect2 = Rect2(r.end.x - depth, z, depth, d - 0.2)
		if _free(rect, keep_out):
			_town_house(b, rect, rng.randi_range(low, high), Color(colors[rng.randi() % colors.size()]), roofs, "east")
		z += d
	# Back rows are mostly hidden by the front ones; a few roofs and courtyard trees.
	for k in range(3):
		var p: Vector3 = Vector3(r.position.x + rng.randf_range(4, r.size.x - depth - 4), 0, r.position.y + rng.randf_range(4, r.size.y - depth - 4))
		if _free(Rect2(p.x - 2, p.z - 2, 4, 4), keep_out):
			_tree(b, p, 1.2, "round")

## The central square: paving, a fountain, trees and benches.
func _square(b: Builder, r: Rect2) -> void:
	var c: Vector3 = Vector3(r.get_center().x, 0, r.get_center().y)
	b.cylinder(c, 5.5, 0.6, Color("b8b2aa"), "tex:stone_wall:0.6", 24)
	b.cylinder(c + Vector3(0, 0.1, 0), 5.0, 0.55, Color("3a6a9a"), "glow:2f5a8a:0.6", 24)
	b.cylinder(c, 1.0, 1.8, Color("d8d2c6"), "vc_gloss", 14, 0.6)
	b.cylinder(c + Vector3(0, 1.8, 0), 2.0, 0.3, Color("d8d2c6"), "vc_gloss", 16)
	b.sphere(c + Vector3(0, 2.6, 0), 0.6, Color("bfe0ff"), "glow:bfe0ff:1.2", Vector3(1, 1.4, 1), 10)
	for k in range(8):
		var a: float = k * TAU / 8.0
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * 13.0
		_tree(b, p, 1.3, "round")
		_lamp(b, c + Vector3(cos(a + 0.4), 0, sin(a + 0.4)) * 9.0)
		var bench: Vector3 = c + Vector3(cos(a + 0.2), 0, sin(a + 0.2)) * 9.5
		b.box(bench, Vector3(1.6, 0.45, 0.5), Color("6e4528"), "vc_gloss", -a)

func _park_block(b: Builder, r: Rect2, keep_out: Array) -> void:
	for k in range(10):
		var p: Vector3 = Vector3(r.position.x + rng.randf_range(2, r.size.x - 2), 0, r.position.y + rng.randf_range(2, r.size.y - 2))
		if p.x + p.z < RIVER_NEAR + 8.0 or not _free(Rect2(p.x - 2, p.z - 2, 4, 4), keep_out):
			continue
		_tree(b, p, rng.randf_range(1.0, 1.4), "round")

# --------------------------------------------------------------------------------------------
# Buildings
# --------------------------------------------------------------------------------------------

func _window_key() -> String:
	var roll: float = rng.randf()
	if roll < 0.42: return "glow:ffb060:1.4"
	if roll < 0.5: return "glow:a8c8ff:1.2"
	return "glow:24324e:0.4"

## A town house: storeys of windows with shutters on the street faces, a cornice and a roof.
func _town_house(b: Builder, rect: Rect2, storeys: int, colour: Color, roof: bool, face: String) -> void:
	for zone in low_zones:
		if zone.intersects(rect):
			_pocket_park(b, rect)
			return
	var h: float = 3.2 * storeys + 0.6
	var at: Vector3 = Vector3(rect.get_center().x, 0, rect.get_center().y)
	b.box(at, Vector3(rect.size.x, h, rect.size.y), colour, "tex:plaster_white:0.25")
	b.box(at, Vector3(rect.size.x + 0.08, 0.9, rect.size.y + 0.08), colour.darkened(0.3), "tex:stone_wall:0.5")
	b.box(at + Vector3(0, h - 0.35, 0), Vector3(rect.size.x + 0.3, 0.35, rect.size.y + 0.3), colour.darkened(0.15))
	var shutter: Color = [Color("3d6a4a"), Color("6e3a2a"), Color("3a4a6a"), Color("5a4a3a")][rng.randi() % 4]
	for s in range(storeys):
		var y: float = 1.2 + s * 3.2
		var shop: bool = s == 0 and not roof and rng.randf() < 0.6
		# South face (+Z) and east face (+X) are the ones the camera sees.
		for side in ["south", "east"]:
			var length: float = rect.size.x if side == "south" else rect.size.y
			var count: int = maxi(1, int(length / 2.6))
			for k in range(count):
				var u: float = (k + 0.5) * length / count - length / 2.0
				var p: Vector3
				var size: Vector3
				if side == "south":
					p = Vector3(at.x + u, y, rect.end.y + 0.03)
					size = Vector3(1.05, 1.5, 0.06)
				else:
					p = Vector3(rect.end.x + 0.03, y, at.z + u)
					size = Vector3(0.06, 1.5, 1.05)
				if shop:
					b.box(p - Vector3(0, 0.8, 0), size * Vector3(1.9 if side == "south" else 1, 1.45, 1.9 if side == "east" else 1), Color.WHITE, "glow:ffd9a0:1.6" if rng.randf() < 0.6 else "glow:24324e:0.4")
					continue
				b.box(p, size, Color.WHITE, _window_key())
				var sh: Vector3 = Vector3(0.35, 1.5, 0.05) if side == "south" else Vector3(0.05, 1.5, 0.35)
				var off: Vector3 = Vector3(0.72, 0, 0.02) if side == "south" else Vector3(0.02, 0, 0.72)
				b.box(p - off, sh, shutter, "vc")
				b.box(p + off, sh, shutter, "vc")
				b.box(p - Vector3(0, 0.12, 0) + (Vector3(0, 0, 0.12) if side == "south" else Vector3(0.12, 0, 0)), Vector3(1.3, 0.1, 0.28) if side == "south" else Vector3(0.28, 0.1, 1.3), colour.darkened(0.2))
				if s > 0 and rng.randf() < 0.18:
					var box_at: Vector3 = p + (Vector3(0, -0.85, 0.3) if side == "south" else Vector3(0.3, -0.85, 0))
					b.box(box_at, Vector3(1.0, 0.25, 0.3) if side == "south" else Vector3(0.3, 0.25, 1.0), Color("6e4528"))
					for f in range(4):
						var fp: Vector3 = box_at + (Vector3(-0.36 + f * 0.24, 0.3, 0) if side == "south" else Vector3(0, 0.3, -0.36 + f * 0.24))
						b.sphere(fp, 0.12, [Color("d9536a"), Color("f2b83a"), Color("c0322c")][f % 3], "vc", Vector3.ONE, 6)
		if shop:
			var awning: Color = [Color("c0322c"), Color("2f6a5a"), Color("3a5a8a"), Color("d9a531")][rng.randi() % 4]
			b.box(Vector3(at.x, 3.0, rect.end.y + 0.6), Vector3(rect.size.x - 0.6, 0.12, 1.2), awning, "vc")
	if roof:
		var pitch: float = minf(rect.size.x, rect.size.y) * 0.45
		var along_x: bool = rect.size.x >= rect.size.y
		var span: Vector3 = Vector3(rect.size.y + 0.6, pitch, rect.size.x + 0.6) if along_x else Vector3(rect.size.x + 0.6, pitch, rect.size.y + 0.6)
		b.prism(at + Vector3(0, h, 0), span, Color.WHITE, "tex:roof_tiles:0.35", PI / 2.0 if along_x else 0.0)
		b.box(at + Vector3(rect.size.x * 0.25, h + 0.8, 0), Vector3(0.6, 2.2, 0.6), Color("8a4a32"), "tex:bricks:0.6")
	else:
		b.box(at + Vector3(0, h, 0), Vector3(rect.size.x - 0.4, 0.5, rect.size.y - 0.4), Color("4a4f5a"))
		if rng.randf() < 0.4:
			b.box(at + Vector3(rect.size.x * 0.2, h + 0.5, -rect.size.y * 0.1), Vector3(2.0, 1.4, 2.0), Color("6a6f7a"))

## Where a house would block the view of the played venue: a pocket park instead.
func _pocket_park(b: Builder, rect: Rect2) -> void:
	var c: Vector3 = Vector3(rect.get_center().x, 0, rect.get_center().y)
	b.box(c - Vector3(0, 0.02, 0), Vector3(rect.size.x - 0.6, 0.06, rect.size.y - 0.6), Color("7a9a6e"), "tex:grass:0.3")
	var count: int = maxi(1, int(rect.size.x * rect.size.y / 40.0))
	for k in range(count):
		var p: Vector3 = Vector3(rect.position.x + rng.randf_range(1.5, rect.size.x - 1.5), 0, rect.position.y + rng.randf_range(1.5, rect.size.y - 1.5))
		_tree(b, p, rng.randf_range(0.8, 1.1), "round")
	b.box(c + Vector3(0, 0, rect.size.y * 0.3), Vector3(1.8, 0.45, 0.5), Color("6e4528"), "vc_gloss")
	_lamp(b, c + Vector3(rect.size.x * 0.3, 0, rect.size.y * 0.35))

## A village house: one storey, a gable roof, a porch light.
func _house(b: Builder, at: Vector3, size: Vector3, colour: Color, porch: bool) -> void:
	var c: Vector3 = at + Vector3(size.x / 2.0, 0, size.z / 2.0)
	b.box(c, size, colour, "tex:plaster_warm:0.3")
	b.box(c, Vector3(size.x + 0.06, 0.6, size.z + 0.06), colour.darkened(0.35), "tex:stone_wall:0.5")
	b.prism(c + Vector3(0, size.y, 0), Vector3(size.z + 0.8, minf(size.x, size.z) * 0.5, size.x + 0.8), Color.WHITE, "tex:roof_tiles:0.35", PI / 2.0)
	b.box(c + Vector3(size.x * 0.28, size.y + 0.6, 0), Vector3(0.5, 1.8, 0.5), Color("8a4a32"), "tex:bricks:0.6")
	for k in range(2):
		var x: float = at.x + size.x * (0.3 + 0.4 * k)
		b.box(Vector3(x, 1.0, at.z + size.z + 0.03), Vector3(0.9, 1.1, 0.06), Color.WHITE, _window_key())
	b.box(Vector3(at.x + size.x + 0.03, 1.0, c.z), Vector3(0.06, 1.1, 0.9), Color.WHITE, _window_key())
	b.box(Vector3(at.x + size.x * 0.5, 0, at.z + size.z + 0.04), Vector3(0.9, 2.0, 0.06), Color("5a3a22"))
	if porch:
		b.sphere(Vector3(at.x + size.x * 0.5 + 0.7, 2.2, at.z + size.z + 0.15), 0.09, Color.WHITE, "glow:ffbf6a:3.0")
		b.quad(Vector3(at.x + size.x * 0.5 + 0.7, 0.03, at.z + size.z + 1.2), Vector2(4.5, 4.5), Color(1, 1, 1, 0.55), "add:pool")

func _tree(b: Builder, at: Vector3, size: float, kind: String) -> void:
	b.cylinder(at, 0.16 * size, 1.6 * size, Color("4a3020"), "vc", 6)
	match kind:
		"fruit":
			b.sphere(at + Vector3(0, 2.3 * size, 0), 1.2 * size, Color("2f5a35"), "vc", Vector3(1, 0.85, 1), 8)
			for k in range(5):
				b.sphere(at + Vector3(cos(k) * 0.8, 2.0 + sin(k * 2.0) * 0.5, sin(k) * 0.8) * size, 0.12 * size, Color("c0322c"), "vc", Vector3.ONE, 5)
		"poplar":
			b.sphere(at + Vector3(0, 3.6 * size, 0), 0.9 * size, Color("27502f"), "vc", Vector3(1, 3.0, 1), 8)
		_:
			b.sphere(at + Vector3(0, 2.6 * size, 0), 1.35 * size, Color("2d5a36"), "vc", Vector3(1, 0.9, 1), 9)
			b.sphere(at + Vector3(0.6, 3.2, 0.3) * size, 0.9 * size, Color("356a3e"), "vc", Vector3.ONE, 8)

func _lamp(b: Builder, at: Vector3) -> void:
	b.cylinder(at, 0.07, 4.0, Color("1d1d22"), "vc_metal", 6)
	b.cylinder(at + Vector3(0, 4.0, 0), 0.22, 0.25, Color("1d1d22"), "vc_metal", 8, 0.5)
	b.sphere(at + Vector3(0, 3.9, 0), 0.16, Color.WHITE, "glow:ffd38a:4.0")
	b.quad(at + Vector3(0, 0.04, 0), Vector2(7.0, 7.0), Color(1, 1, 1, 0.65), "add:pool")

# --------------------------------------------------------------------------------------------
# Streets
# --------------------------------------------------------------------------------------------

func _streets(b: Builder) -> void:
	for k in range(-6, 4):
		var line: float = k * BLOCK
		for j in range(-6, 3):
			# Street along X at z = line, segment over block column j.
			var seg_x: Vector3 = Vector3(j * BLOCK + BLOCK / 2.0, 0, line)
			_street_segment(b, seg_x, true)
			var seg_z: Vector3 = Vector3(line, 0, j * BLOCK + BLOCK / 2.0)
			_street_segment(b, seg_z, false)

func _street_segment(b: Builder, c: Vector3, along_x: bool) -> void:
	if _in_water(c.x, c.z) or absf(across(c)) > 100.0 or along(c) < -115.0:
		return
	if c.x + c.z - BLOCK / 2.0 < RIVER_NEAR + 22.0:
		return
	var kind: String = district(c)
	var size: Vector3 = Vector3(BLOCK, 0.3, ROAD) if along_x else Vector3(ROAD, 0.3, BLOCK)
	var road: String = {"village": "tex:dirt:0.3", "oldtown": "tex:cobble:0.35", "center": "tex:asphalt:0.3", "quay": "tex:asphalt:0.3"}[kind]
	b.box(c - Vector3(0, 0.4, 0), size, Color.WHITE, road)
	if kind == "village":
		return
	# Sidewalks and kerbs.
	for s in [-1.0, 1.0]:
		var off: Vector3 = Vector3(0, 0, s * (ROAD / 2.0 + 0.75)) if along_x else Vector3(s * (ROAD / 2.0 + 0.75), 0, 0)
		var walk: Vector3 = Vector3(BLOCK - STREET, 0.36, 1.5) if along_x else Vector3(1.5, 0.36, BLOCK - STREET)
		b.box(c + off - Vector3(0, 0.3, 0), walk, Color("bdb6aa"), "tex:sidewalk:0.4")
	if kind == "center":
		var dash: Vector3 = Vector3(2.0, 0.02, 0.15) if along_x else Vector3(0.15, 0.02, 2.0)
		for k in range(-5, 6):
			b.box(c + (Vector3(k * 4.4, -0.03, 0) if along_x else Vector3(0, -0.03, k * 4.4)), dash, Color("e8e2d0"))
	# Lamps along one side, every ~17 m.
	for k in range(3):
		var u: float = -BLOCK / 2.0 + 9.0 + k * 17.0
		var p: Vector3 = c + (Vector3(u, 0, ROAD / 2.0 + 1.0) if along_x else Vector3(ROAD / 2.0 + 1.0, 0, u))
		_lamp(b, p)
		if kind == "center" and k != 1:
			_tree(b, p + (Vector3(8.5, 0, 0) if along_x else Vector3(0, 0, 8.5)), 0.9, "round")

func _traffic() -> void:
	# Parked and passing cars near the venues.
	var colours: Array = ["c0322c", "f2f0ea", "3a5a8a", "2b2b30", "d9a531", "4f8a5a", "9aa4b4"]
	for id in ["kafana", "restoran"]:
		var lay: Dictionary = lots[id].lay
		var front: float = lots[id].origin.z + lay.d + 7.0
		for k in range(4):
			var car: Node3D = _car(Color(colours[(k + hash(id)) % colours.size()]))
			car.position = Vector3(lots[id].origin.x - 8.0 + k * 9.0 + rng.randf_range(-1, 1), 0, front)
			car.rotation.y = PI / 2.0
			add_child(car)
	for k in range(5):
		var car: Node3D = _car(Color(colours[k % colours.size()]))
		add_child(car)
		var street_z: float = [0.0, -52.0, 52.0, -104.0, 0.0][k] - 1.5
		car.set_meta("street", street_z)
		car.set_meta("speed", rng.randf_range(7.0, 11.0) * (1.0 if k % 2 == 0 else -1.0))
		car.set_meta("min_x", maxf(-170.0, RIVER_NEAR + 30.0 - street_z))
		car.position = Vector3(rng.randf_range(maxf(-150.0, RIVER_NEAR + 30.0 - street_z), 60.0), 0, street_z + (0.0 if k % 2 == 0 else 3.0))
		car.rotation.y = PI / 2.0 if k % 2 == 0 else -PI / 2.0
		traffic.append(car)

func _car(colour: Color) -> Node3D:
	var node: Node3D = Node3D.new()
	var b: Builder = Builder.new()
	b.box(Vector3(0, 0.3, 0), Vector3(1.7, 0.6, 3.8), colour, "vc_gloss")
	b.box(Vector3(0, 0.9, -0.2), Vector3(1.5, 0.55, 2.0), colour.lightened(0.1), "vc_gloss")
	b.box(Vector3(0, 0.95, -0.2), Vector3(1.52, 0.42, 1.8), Color("2a3a52"), "vc_gloss")
	for x in [-0.8, 0.8]:
		for z in [-1.2, 1.2]:
			b.cylinder_xf(Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(x + (0.12 if x > 0 else -0.12), 0.33, z)), 0.33, 0.24, Color("15151a"), "vc", 10)
	b.box(Vector3(0.55, 0.55, 1.91), Vector3(0.35, 0.15, 0.03), Color.WHITE, "glow:fff4d0:3.0")
	b.box(Vector3(-0.55, 0.55, 1.91), Vector3(0.35, 0.15, 0.03), Color.WHITE, "glow:fff4d0:3.0")
	b.box(Vector3(0.6, 0.55, -1.91), Vector3(0.3, 0.12, 0.03), Color.WHITE, "glow:ff3a2a:2.0")
	b.box(Vector3(-0.6, 0.55, -1.91), Vector3(0.3, 0.12, 0.03), Color.WHITE, "glow:ff3a2a:2.0")
	b.commit(node)
	var blob: MeshInstance3D = MeshInstance3D.new()
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2(2.6, 4.8)
	blob.mesh = quad
	blob.position = Vector3(0, 0.02, 0)
	blob.material_override = Kit.material("blend:shadow")
	node.add_child(blob)
	return node

func _process(delta: float) -> void:
	time += delta
	for car in traffic:
		var low: float = float(car.get_meta("min_x"))
		car.position.x += float(car.get_meta("speed")) * delta
		if car.position.x > 80.0: car.position.x = low
		if car.position.x < low: car.position.x = 80.0

# --------------------------------------------------------------------------------------------
# River, quay, bridge and the far bank
# --------------------------------------------------------------------------------------------

## The river runs across the screen between the lines x + z = RIVER_NEAR and RIVER_FAR.
func _diag_box(b: Builder, center_along: float, center_across: float, size: Vector3, colour: Color, key: String, lift: float = 0.0) -> void:
	# A box aligned with the river: `size.x` across the screen, `size.z` along the road.
	var dir_up: Vector3 = Vector3(-1, 0, -1).normalized()
	var dir_right: Vector3 = Vector3(1, 0, -1).normalized()
	var at: Vector3 = dir_up * center_along + dir_right * center_across + Vector3(0, lift, 0)
	var basis: Basis = Basis(dir_right, Vector3.UP, -dir_up)
	b.box_xf(Transform3D(basis, at), size, colour, key)

func _river(b: Builder) -> void:
	var near_t: float = -RIVER_NEAR / sqrt(2.0)
	var far_t: float = -RIVER_FAR / sqrt(2.0)
	var mid: float = (near_t + far_t) / 2.0
	var width: float = far_t - near_t + 12.0
	var dir_up: Vector3 = Vector3(-1, 0, -1).normalized()
	var dir_right: Vector3 = Vector3(1, 0, -1).normalized()
	var at: Vector3 = dir_up * mid + Vector3(0, -0.55, 0)
	var basis: Basis = Basis(dir_right, Vector3.UP, -dir_up) * Basis.from_scale(Vector3(360, 1, width))
	b.add(Kit.unit("grid", 48), Transform3D(basis, at), Color.WHITE, "water")
	# Reflections of the far bank and the bridge lamps: long soft streaks on the water.
	for k in range(40):
		var t: float = rng.randf_range(near_t + 4.0, far_t - 4.0)
		var u: float = rng.randf_range(-90, 90)
		_diag_box(b, t, u, Vector3(rng.randf_range(0.8, 2.4), 0.02, 0.12), Color.WHITE, "glow:ffd38a:1.2", -0.48)

func _quay(b: Builder) -> void:
	var near_t: float = -RIVER_NEAR / sqrt(2.0)
	# Stone embankment wall and a paved promenade with lamps and benches.
	_diag_box(b, near_t - 1.0, 0.0, Vector3(300, 1.4, 2.0), Color("9a9184"), "tex:stone_wall:0.5", -1.0)
	_diag_box(b, near_t - 8.0, 0.0, Vector3(300, 0.42, 14.0), Color("b8b2aa"), "tex:paving:0.3", -0.46)
	for k in range(-9, 10):
		var u: float = k * 14.0
		var dir_up: Vector3 = Vector3(-1, 0, -1).normalized()
		var dir_right: Vector3 = Vector3(1, 0, -1).normalized()
		var p: Vector3 = dir_up * (near_t - 2.6) + dir_right * u
		_lamp(b, p)
		if k % 2 == 0:
			_diag_box(b, near_t - 5.0, u + 4.0, Vector3(1.8, 0.45, 0.5), Color("6e4528"), "vc_gloss")
		if k % 3 == 0:
			_tree(b, dir_up * (near_t - 11.0) + dir_right * (u + 7.0), 1.1, "round")
	# Railing along the water.
	_diag_box(b, near_t - 0.2, 0.0, Vector3(300, 0.08, 0.08), Color("2b2b30"), "vc_metal", 1.0)

func _bridge(b: Builder) -> void:
	var near_t: float = -RIVER_NEAR / sqrt(2.0)
	var far_t: float = -RIVER_FAR / sqrt(2.0)
	var u: float = 46.0
	var length: float = far_t - near_t + 16.0
	var mid: float = (near_t + far_t) / 2.0
	_diag_box(b, mid, u, Vector3(12.0, 0.8, length), Color("e0d8ca"), "tex:stone_wall:0.5", 4.0)
	_diag_box(b, mid, u, Vector3(8.0, 0.05, length), Color("8a8c94"), "tex:asphalt:0.3", 4.8)
	for side in [-5.0, 5.0]:
		_diag_box(b, mid, u + side, Vector3(1.6, 0.08, length), Color("d8d2c6"), "tex:sidewalk:0.4", 4.8)
	for side in [-5.9, 5.9]:
		_diag_box(b, mid, u + side, Vector3(0.25, 1.0, length), Color("e8e2d6"), "vc", 4.8)
	# Piers and arches.
	for k in range(5):
		var t: float = near_t + 4.0 + k * (far_t - near_t - 8.0) / 4.0
		_diag_box(b, t, u, Vector3(10.0, 5.0, 3.0), Color("a8a196"), "tex:stone_wall:0.5", -1.0)
	# Lamps along the bridge.
	var dir_up: Vector3 = Vector3(-1, 0, -1).normalized()
	var dir_right: Vector3 = Vector3(1, 0, -1).normalized()
	for k in range(9):
		var t: float = near_t - 6.0 + k * length / 8.0
		for side in [-5.6, 5.6]:
			var p: Vector3 = dir_up * t + dir_right * (u + side) + Vector3(0, 4.8, 0)
			b.cylinder(p, 0.08, 3.4, Color("1d1d22"), "vc_metal", 6)
			b.sphere(p + Vector3(0, 3.4, 0), 0.22, Color.WHITE, "glow:ffd38a:4.0")
			b.quad(p + Vector3(0, 0.12, 0), Vector2(7.0, 7.0), Color(1, 1, 1, 0.6), "add:pool")

func _far_bank(b: Builder) -> void:
	var far_t: float = -RIVER_FAR / sqrt(2.0)
	_diag_box(b, far_t + 18.0, 0.0, Vector3(320, 0.5, 40.0), Color("2a2f3a"), "vc", -0.3)
	var dir_up: Vector3 = Vector3(-1, 0, -1).normalized()
	var dir_right: Vector3 = Vector3(1, 0, -1).normalized()
	var u: float = -140.0
	while u < 140.0:
		var w: float = rng.randf_range(8, 16)
		var h: float = rng.randf_range(8, 30)
		var t: float = far_t + rng.randf_range(10, 22)
		var at: Vector3 = dir_up * t + dir_right * u
		var basis: Basis = Basis(dir_right, Vector3.UP, -dir_up)
		b.box_xf(Transform3D(basis, at), Vector3(w, h, 10), Color("1d2438"), "vc")
		for row in range(int(h / 3.0)):
			for col in range(int(w / 2.2)):
				if rng.randf() < 0.4:
					var wp: Vector3 = at + dir_right * (-w / 2.0 + 1.2 + col * 2.2) + Vector3(0, 1.5 + row * 3.0, 0) - dir_up * 5.05
					b.box_xf(Transform3D(basis, wp), Vector3(0.9, 1.2, 0.05), Color.WHITE, "glow:ffc070:1.6")
		u += w + rng.randf_range(0.5, 3.0)
