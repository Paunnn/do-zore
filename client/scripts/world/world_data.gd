extends RefCounted
## The 2D effect sprites drawn over the 3D world (thought clouds, emotes, coins, notes, the "+"
## and fight dust) and a small texture cache. Anchors come from assets/world/world.json, written
## by tools/art/build_fx.py.
const ROOT = "res://assets/world/"

static var world: Dictionary = {}
static var _textures: Dictionary = {}

static func ensure_loaded() -> void:
	if world.is_empty():
		world = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "world.json"))

static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]

static func info(name: String) -> Dictionary:
	ensure_loaded()
	return world.sprites.get(name, {})

## A Sprite2D whose local origin is the sprite's anchor (the point it stands on).
static func sprite(name: String) -> Sprite2D:
	var data: Dictionary = info(name)
	var result: Sprite2D = Sprite2D.new()
	result.texture = texture(ROOT + name + ".svg")
	result.centered = false
	var scale_factor: float = float(data.get("scale", 2.0))
	result.scale = Vector2.ONE / scale_factor
	result.offset = -Vector2(float(data.get("ox", 0.0)), float(data.get("oy", 0.0))) * scale_factor
	return result
