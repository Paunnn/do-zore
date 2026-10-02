extends Control
## One table on the floor: the painted table in three layers, guests seated between them,
## and the order, song-request and mood badges. Presentation only; reads a table dictionary.
signal tapped(index: int)

const SPRITES = "res://assets/sprites/"
const ART = "res://assets/art/"
const GENRE_COLORS = {"starogradske": Color("eab575"), "tamburica": Color("72cbb6"), "izvorna": Color("ed8c7a"), "narodnjaci": Color("c49be8")}
const INK = Color("f4eedc")
const BUST = Vector2(162, 216)
# Bust rectangles in table pixels: two guests face us from the back chairs, two sit with their
# backs to us on the front chairs.
const BACK_SEATS = [Vector2(24, 0), Vector2(342, 0)]
const FRONT_SEATS = [Vector2(76, 181), Vector2(288, 181)]
const TAP_SLOP = 24.0

static var _textures: Dictionary = {}

var index: int = 0
var back_guests: Array = []
var front_guests: Array = []
var order_bubble: Control
var order_icon: TextureRect
var order_ring: Control
var request_badge: PanelContainer
var request_note: TextureRect
var request_label: Label
var mood_icon: TextureRect
var count_badge: PanelContainer
var count_label: Label
var time: float = 0.0
var prep_total: float = 0.0
var prep_progress: float = 0.0
var waiting: bool = false
var dancing: bool = false
var occupied: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _pressing: bool = false

static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]

func setup(table_index: int) -> void:
	index = table_index
	var base: Texture2D = texture(ART + "table_back.png")
	size = base.get_size()
	mouse_filter = Control.MOUSE_FILTER_PASS
	_layer("table_back.png")
	for seat in BACK_SEATS: back_guests.append(_guest_slot(seat))
	_layer("table_front.png")
	for seat in FRONT_SEATS: front_guests.append(_guest_slot(seat))
	_layer("table_rests.png")
	_build_badges()

func _layer(file: String) -> void:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture(ART + file)
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

func _guest_slot(origin: Vector2) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = origin
	rect.size = BUST
	rect.pivot_offset = Vector2(BUST.x / 2, BUST.y)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	rect.set_meta("origin", origin)
	add_child(rect)
	return rect

func _pill(color: Color) -> PanelContainer:
	var pill: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(26)
	style.set_border_width_all(3)
	style.border_color = Color("3b2a1c")
	style.content_margin_left = 14
	style.content_margin_right = 18
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pill)
	return pill

func _build_badges() -> void:
	order_bubble = Control.new()
	order_bubble.position = Vector2(190, -150)
	order_bubble.size = Vector2(156, 172)
	order_bubble.pivot_offset = Vector2(78, 172)
	order_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(order_bubble)
	var bubble: TextureRect = TextureRect.new()
	bubble.texture = texture(SPRITES + "icons/bubble.svg")
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.size = order_bubble.size
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_bubble.add_child(bubble)
	order_icon = TextureRect.new()
	order_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	order_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	order_icon.position = Vector2(22, 14)
	order_icon.size = Vector2(112, 112)
	order_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_bubble.add_child(order_icon)
	order_ring = Control.new()
	order_ring.position = Vector2(14, 6)
	order_ring.size = Vector2(128, 128)
	order_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_ring.draw.connect(_draw_ring)
	order_bubble.add_child(order_ring)
	request_badge = _pill(Color("1c2a2e"))
	request_badge.position = Vector2(-20, -66)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	request_badge.add_child(row)
	request_note = TextureRect.new()
	request_note.texture = texture(SPRITES + "icons/note.svg")
	request_note.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	request_note.custom_minimum_size = Vector2(40, 40)
	request_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(request_note)
	request_label = Label.new()
	request_label.add_theme_font_size_override("font_size", 30)
	request_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(request_label)
	mood_icon = TextureRect.new()
	mood_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mood_icon.position = Vector2(478, 236)
	mood_icon.size = Vector2(72, 72)
	mood_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mood_icon)
	count_badge = _pill(Color("eab575"))
	count_badge.position = Vector2(420, 420)
	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 32)
	count_label.add_theme_color_override("font_color", Color("2a1a0c"))
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_badge.add_child(count_label)

func _draw_ring() -> void:
	if waiting or prep_total <= 0.0:
		return
	var center: Vector2 = order_ring.size / 2
	order_ring.draw_arc(center, 60, 0, TAU, 48, Color(0, 0, 0, 0.25), 10, true)
	order_ring.draw_arc(center, 60, -PI / 2, -PI / 2 + TAU * prep_progress, 48, Color("72cbb6"), 10, true)

func apply(table: Dictionary, mood_rules: Dictionary, genre_names: Dictionary) -> void:
	var guest_type: String = str(table.get("guest_type", ""))
	var was_occupied: bool = occupied
	occupied = not guest_type.is_empty()
	var party: int = int(table.get("party_size", 0))
	var mood: float = float(table.get("mood", 50))
	var face: String = "neutral"
	if mood >= float(mood_rules.happy_at_or_above): face = "happy"
	elif mood < float(mood_rules.unhappy_below): face = "angry"
	for seat in range(back_guests.size()):
		var slot: TextureRect = back_guests[seat]
		slot.visible = occupied and seat < party
		if slot.visible: slot.texture = texture(SPRITES + "guests/%s_%s_%s.svg" % [guest_type, _variant(seat, party), face])
	for seat in range(front_guests.size()):
		var slot: TextureRect = front_guests[seat]
		slot.visible = occupied and seat + back_guests.size() < party
		if slot.visible: slot.texture = texture(SPRITES + "guests/%s_%s_back.svg" % [guest_type, _variant(seat + 1, party)])
	if occupied and not was_occupied:
		for slot in back_guests + front_guests:
			slot.modulate.a = 0.0
			create_tween().tween_property(slot, "modulate:a", 1.0, 0.45)
	var extra: int = party - back_guests.size() - front_guests.size()
	count_badge.visible = occupied and extra > 0
	count_label.text = "+%d" % extra
	var status: String = str(table.get("order_status", ""))
	waiting = occupied and status == "waiting"
	order_bubble.visible = occupied and status in ["waiting", "preparing"]
	if order_bubble.visible:
		order_icon.texture = texture(SPRITES + "drinks/%s.svg" % str(table.get("order_item", "")))
	if status == "preparing":
		var remaining: float = float(table.get("prep_remaining", 0.0))
		prep_total = maxf(prep_total, remaining)
		prep_progress = clampf(1.0 - remaining / prep_total, 0.0, 1.0) if prep_total > 0.0 else 1.0
	else:
		prep_total = 0.0
		prep_progress = 0.0
	order_icon.modulate = Color(1, 1, 1, 1) if waiting else Color(1, 1, 1, 0.55)
	order_ring.queue_redraw()
	var genre: String = str(table.get("request_genre", ""))
	request_badge.visible = occupied and not genre.is_empty()
	if request_badge.visible:
		var color: Color = GENRE_COLORS.get(genre, INK)
		request_note.modulate = color
		request_label.text = str(genre_names.get(genre, genre))
		request_label.add_theme_color_override("font_color", color)
	mood_icon.visible = occupied
	if occupied:
		var mood_key: String = "mood_happy" if face == "happy" else "mood_unhappy" if face == "angry" else "mood_neutral"
		mood_icon.texture = texture(SPRITES + "icons/%s.svg" % mood_key)
	dancing = bool(table.get("dancing", false))

func _variant(seat: int, party: int) -> String:
	return "a" if (index + seat + party) % 2 == 0 else "b"

func _process(delta: float) -> void:
	time += delta
	if order_bubble.visible:
		var pulse: float = 1.0 + (0.07 * sin(time * 5.5) if waiting else 0.0)
		order_bubble.scale = Vector2(pulse, pulse)
		order_bubble.position.y = -150 + (sin(time * 2.2 + index) * 6.0 if waiting else 0.0)
	var slots: Array = back_guests + front_guests
	for seat in range(slots.size()):
		var slot: TextureRect = slots[seat]
		var origin: Vector2 = slot.get_meta("origin")
		var bob: float = absf(sin(time * 7.0 + seat * 1.3)) * -14.0 if dancing else sin(time * 1.4 + seat * 2.1 + index) * 1.5
		slot.position = origin + Vector2(0, bob)
		slot.rotation = sin(time * 7.0 + seat) * 0.06 if dancing else 0.0

func _gui_input(event: InputEvent) -> void:
	var press: bool = false
	var release: bool = false
	if event is InputEventScreenTouch:
		press = event.pressed
		release = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		press = event.pressed
		release = not event.pressed
	else:
		return
	if press:
		_pressing = true
		_press_position = get_global_mouse_position()
	elif release and _pressing:
		_pressing = false
		if get_global_mouse_position().distance_to(_press_position) <= TAP_SLOP:
			tapped.emit(index)

func _has_point(point: Vector2) -> bool:
	# Only the table and its chairs react, not the transparent corners of the layer images.
	return Rect2(Vector2(20, 20), size - Vector2(40, 60)).has_point(point)
