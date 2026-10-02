extends RefCounted
## Shared access to the generated isometric art: projection, sprite anchors and textures.
const ROOT = "res://assets/world/"
const TILE = Vector2(128, 64)

static var world: Dictionary = {}
static var people: Dictionary = {}
static var _textures: Dictionary = {}

static func ensure_loaded() -> void:
	if world.is_empty():
		world = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "world.json"))
		people = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "people/people.json"))

## Floor tile coordinates (x down-right, y down-left) and height in pixels to world pixels.
static func iso(x: float, y: float, z: float = 0.0) -> Vector2:
	return Vector2((x - y) * TILE.x / 2.0, (x + y) * TILE.y / 2.0 - z)

static func iso_v(cell: Vector2, z: float = 0.0) -> Vector2:
	return iso(cell.x, cell.y, z)

## Inverse of iso() on the floor plane.
static func to_floor(point: Vector2) -> Vector2:
	var a: float = point.x / (TILE.x / 2.0)
	var b: float = point.y / (TILE.y / 2.0)
	return Vector2((a + b) / 2.0, (b - a) / 2.0)

static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]

static func info(name: String) -> Dictionary:
	ensure_loaded()
	return world.sprites.get(name, {})

## A Sprite2D whose local origin is the sprite's anchor (usually its floor contact point).
static func sprite(name: String) -> Sprite2D:
	var data: Dictionary = info(name)
	var result: Sprite2D = Sprite2D.new()
	result.texture = texture(ROOT + name + ".svg")
	result.centered = false
	var scale_factor: float = float(data.get("scale", 2.0))
	result.scale = Vector2.ONE / scale_factor
	result.offset = -Vector2(float(data.get("ox", 0.0)), float(data.get("oy", 0.0))) * scale_factor
	return result

static func venue_layout(venue_id: String) -> Dictionary:
	ensure_loaded()
	return world.venues.get(venue_id, world.venues.values()[0])
