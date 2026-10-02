extends Node2D
## One animated character: plays sheet animations, walks along world-space paths and turns to
## face the direction it moves. The node's position is the character's feet.
signal arrived

const WorldData = preload("res://scripts/world/world_data.gd")
const WALK_SPEED = 135.0
const SIZE = 1.12

var sprite: Sprite2D
var atlas: AtlasTexture
var anims: Dictionary = {}
var frames_per_row: int = 1
var cell: Vector2 = Vector2(144, 208)
var current: String = ""
var anim_time: float = 0.0
var fps: float = 8.0
var path: PackedVector2Array = PackedVector2Array()
var facing_front: bool = true
var walk_prefix: String = "walk"
var bob: float = 0.0
var speed_scale: float = 1.0
var fade_out_at_end: bool = false

func setup(sheet: String, animations: Dictionary, frame_count: int) -> void:
	WorldData.ensure_loaded()
	var meta: Dictionary = WorldData.people
	var scale_factor: float = float(meta.scale)
	cell = Vector2(float(meta.cell[0]), float(meta.cell[1])) * scale_factor
	frames_per_row = frame_count
	atlas = AtlasTexture.new()
	atlas.atlas = WorldData.texture(WorldData.ROOT + "people/" + sheet + ".svg")
	atlas.region = Rect2(Vector2.ZERO, cell)
	sprite = Sprite2D.new()
	sprite.texture = atlas
	sprite.centered = false
	sprite.scale = Vector2.ONE * SIZE / scale_factor
	sprite.offset = -Vector2(float(meta.foot[0]), float(meta.foot[1])) * scale_factor
	add_child(sprite)
	anims = animations
	play(anims.keys()[0])

func play(name: String, rate: float = 8.0, restart: bool = false) -> void:
	if not anims.has(name):
		return
	if name == current and not restart:
		fps = rate
		return
	current = name
	fps = rate
	anim_time = 0.0
	_show_frame()

func _show_frame() -> void:
	var frames: Array = anims.get(current, [0])
	var frame: int = int(frames[int(anim_time * fps) % frames.size()])
	atlas.region = Rect2(Vector2(frame % frames_per_row, frame / frames_per_row) * cell, cell)

func face(direction: Vector2) -> void:
	if direction.length() < 0.01:
		return
	facing_front = direction.y >= -0.01
	sprite.flip_h = direction.x < 0.0 if facing_front else direction.x > 0.0

func walk(points: PackedVector2Array) -> void:
	path = points
	if path.is_empty():
		arrived.emit()

func is_walking() -> bool:
	return not path.is_empty()

func _process(delta: float) -> void:
	anim_time += delta
	if not path.is_empty():
		var target: Vector2 = path[0]
		var offset: Vector2 = target - position
		var step: float = WALK_SPEED * speed_scale * delta
		face(offset)
		play(walk_prefix + ("_front" if facing_front else "_back"), 9.0)
		if offset.length() <= step:
			position = target
			path.remove_at(0)
			if path.is_empty():
				arrived.emit()
		else:
			position += offset.normalized() * step
	_show_frame()
	if bob != 0.0:
		sprite.position.y = sin(anim_time * 2.2 + get_instance_id() % 7) * bob

func fade_in(duration: float = 0.35) -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, duration)

func fade_and_free(duration: float = 0.4) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_callback(queue_free)
