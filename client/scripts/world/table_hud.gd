extends Node2D
## Thought cloud above a table: the order (bouncing while it waits, a ring while it is being
## prepared), the requested genre, a mood emote and a +N badge for big parties.
const WorldData = preload("res://scripts/world/world_data.gd")
const SPRITES = "res://assets/sprites/"
const GENRE_COLORS = {"starogradske": Color("ffb43d"), "tamburica": Color("3ec9a7"), "izvorna": Color("ff6a5a"), "narodnjaci": Color("b77cff")}
const INK = Color("2b1d14")

var cloud: Sprite2D
var icon: Sprite2D
var note: Sprite2D
var emote: Sprite2D
var badge: Label
var mode: String = ""
var progress: float = 0.0
var time: float = 0.0
var emote_name: String = ""

func _ready() -> void:
	scale = Vector2(1.25, 1.25)
	cloud = WorldData.sprite("fx/cloud")
	add_child(cloud)
	icon = Sprite2D.new()
	icon.position = Vector2(0, -36)
	add_child(icon)
	note = WorldData.sprite("fx/note")
	note.position = Vector2(0, -10)
	add_child(note)
	emote = Sprite2D.new()
	emote.position = Vector2(44, -54)
	add_child(emote)
	badge = Label.new()
	badge.add_theme_font_size_override("font_size", 22)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", INK)
	badge.add_theme_constant_override("outline_size", 8)
	# Sits by the table's right-hand chairs, below the cloud.
	badge.position = Vector2(52, 92)
	add_child(badge)
	_apply()

## mode: "" (hidden), "order", "preparing" or "request".
func show_state(new_mode: String, drink: String, genre: String, ratio: float, mood_emote: String, extra: int) -> void:
	if new_mode != mode or (new_mode in ["order", "preparing"] and icon.texture != WorldData.texture(SPRITES + "drinks/%s.svg" % drink)):
		mode = new_mode
		if mode in ["order", "preparing"]:
			icon.texture = WorldData.texture(SPRITES + "drinks/%s.svg" % drink)
			icon.scale = Vector2(0.21, 0.21)
		_apply()
	if mode == "request":
		note.modulate = GENRE_COLORS.get(genre, Color.WHITE)
	progress = ratio
	if mood_emote != emote_name:
		emote_name = mood_emote
		emote.texture = WorldData.texture(WorldData.ROOT + "fx/%s.svg" % mood_emote) if not mood_emote.is_empty() else null
		emote.scale = Vector2(0.5, 0.5)
		if not mood_emote.is_empty():
			emote.scale = Vector2(0.1, 0.1)
			create_tween().tween_property(emote, "scale", Vector2(0.5, 0.5), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	badge.visible = extra > 0
	badge.text = "+%d" % extra
	queue_redraw()

func _apply() -> void:
	# Orders get a full cloud; a song wish gets a smaller cloud with a note in the genre colour.
	cloud.visible = mode in ["order", "preparing", "request"]
	cloud.scale = (Vector2.ONE * 0.5) if mode != "request" else (Vector2.ONE * 0.36)
	icon.visible = mode in ["order", "preparing"]
	note.visible = mode == "request"
	note.scale = Vector2.ONE * 0.32
	icon.modulate = Color(1, 1, 1, 1) if mode == "order" else Color(1, 1, 1, 0.6)

func _process(delta: float) -> void:
	time += delta
	var hop: float = 0.0
	if mode == "order":
		hop = -absf(sin(time * 4.0)) * 9.0
	elif mode == "request":
		hop = sin(time * 2.4) * 3.0
	cloud.position.y = hop
	icon.position.y = -36 + hop
	note.position.y = -16 + hop
	note.rotation = sin(time * 3.0) * 0.12
	if emote.texture != null:
		# Beside the cloud when there is one, otherwise where the cloud would be.
		var beside: bool = cloud.visible
		emote.position = Vector2(44 if beside and mode != "request" else (32 if beside else 0), (-54 if beside else -20) + sin(time * 3.2) * 3.0)

func _draw() -> void:
	if mode != "preparing":
		return
	var center: Vector2 = Vector2(0, -34) + Vector2(0, cloud.position.y)
	draw_arc(center, 25, 0, TAU, 40, Color(0, 0, 0, 0.18), 6, true)
	draw_arc(center, 25, -PI / 2, -PI / 2 + TAU * progress, 40, Color("3ec95a"), 6, true)
