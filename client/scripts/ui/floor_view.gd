extends Control
## The kafana floor: a camera onto the isometric world with drag-to-pan, pinch/wheel zoom and
## taps on tables, the stage and free table slots. Coins from leaving guests fly to the HUD.
signal table_tapped(index: int)
signal stage_tapped
signal slot_tapped(index: int)

const KafanaWorld = preload("res://scripts/world/kafana_world.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const TAP_SLOP = 18.0
const MIN_ZOOM = 0.38
const MAX_ZOOM = 1.35
const INK = Color("2b1d14")

var viewport_container: SubViewportContainer
var viewport: SubViewport
var camera: Camera2D
var world
var fx: Control
var song_bar: PanelContainer
var song_title: Label
var song_progress: ProgressBar
var song_note: TextureRect
var music_button: Button
var venue_id: String = ""
var backdrop: TextureRect
const PARALLAX = 0.12
const BACKDROP_BLEED = 90.0
var top_inset: float = 260.0
var bottom_inset: float = 200.0
var money_target: Callable = Callable()
var touches: Dictionary = {}
var press_position: Vector2 = Vector2.ZERO
var moved: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var pinch_distance: float = 0.0
var song_total: float = 1.0
var refresh_timer: float = 0.0
var closed_pill: PanelContainer
var closed_label: Label
var hint: Control
var hint_label: Label
var hint_arrow: Control
var hint_time: float = 0.0
var hint_target: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_container = SubViewportContainer.new()
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	viewport_container.add_child(viewport)
	var sky: CanvasLayer = CanvasLayer.new()
	sky.layer = -10
	viewport.add_child(sky)
	# Night scenery around the venue, a little larger than the screen so it can drift with the camera.
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.add_child(backdrop)
	camera = Camera2D.new()
	viewport.add_child(camera)
	camera.make_current()
	world = KafanaWorld.new()
	world.payout.connect(_on_payout)
	viewport.add_child(world)
	fx = Control.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	_build_song_bar()
	resized.connect(_on_resized)
	_ensure_world()

func _build_song_bar() -> void:
	# Now playing: a dark inset plaque with the genre note and a brass progress line.
	var line: HBoxContainer = UIKit.row(UIKit.S)
	song_note = UIKit.tinted("note", 44, UIKit.LAMP)
	song_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(song_note)
	var column: VBoxContainer = UIKit.column(4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(column)
	song_title = UIKit.label("", "label", 26, UIKit.CREAM)
	song_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	song_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(song_title)
	song_progress = UIKit.bar(UIKit.BRASS, 14)
	column.add_child(song_progress)
	song_bar = UIKit.panel("chip", line)
	song_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	song_bar.visible = false
	add_child(song_bar)
	music_button = UIKit.medallion("note", func(): stage_tapped.emit(), 136)
	add_child(music_button)
	closed_label = UIKit.label("", "label", 30, UIKit.CREAM)
	closed_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	closed_pill = UIKit.panel("ribbon", closed_label)
	closed_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed_pill.visible = false
	add_child(closed_pill)
	hint = Control.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.visible = false
	add_child(hint)
	hint_label = UIKit.label("", "bold", 28, UIKit.INK)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var hint_pill: PanelContainer = UIKit.panel("paper_brass", hint_label)
	hint_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_child(hint_pill)
	hint_arrow = Control.new()
	hint_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_arrow.draw.connect(func():
		var points: PackedVector2Array = PackedVector2Array([Vector2(-26, -40), Vector2(26, -40), Vector2(0, 0)])
		hint_arrow.draw_colored_polygon(points, UIKit.BRASS)
		hint_arrow.draw_polyline(points + PackedVector2Array([points[0]]), INK, 5.0, true))
	add_child(hint_arrow)
	_place_overlays()

func set_insets(top: float, bottom: float) -> void:
	top_inset = top
	bottom_inset = bottom
	_place_overlays()
	_clamp_camera()

func _on_resized() -> void:
	_place_overlays()
	_clamp_camera()

func _place_overlays() -> void:
	if song_bar == null:
		return
	song_bar.size = Vector2(minf(size.x - 120, 760), 0)
	song_bar.position = Vector2((size.x - song_bar.size.x) / 2, top_inset + UIKit.S)
	music_button.position = Vector2(size.x - music_button.custom_minimum_size.x - UIKit.GUTTER - 8, size.y - bottom_inset - music_button.custom_minimum_size.y - UIKit.L)

func _ensure_world() -> void:
	var venue: String = str(GameState.save.venue)
	if venue == venue_id:
		return
	venue_id = venue
	world.build(venue)
	backdrop.texture = WorldData.texture(WorldData.ROOT + "backdrops/%s.svg" % venue)
	camera.zoom = Vector2.ONE * _default_zoom()
	camera.position = world.focus_point()
	_clamp_camera()
	world.sync(GameState.simulation, GameState.save)

func _drift_backdrop() -> void:
	var shift: Vector2 = ((world.focus_point() - camera.position) * camera.zoom.x * PARALLAX).clamp(Vector2.ONE * -BACKDROP_BLEED, Vector2.ONE * BACKDROP_BLEED)
	backdrop.offset_left = -BACKDROP_BLEED + shift.x
	backdrop.offset_right = BACKDROP_BLEED + shift.x
	backdrop.offset_top = -BACKDROP_BLEED + shift.y
	backdrop.offset_bottom = BACKDROP_BLEED + shift.y

func _default_zoom() -> float:
	# Close enough to read faces; small rooms may show a little more.
	var width: float = maxf(1.0, world.room_rect.size.x)
	return clampf(size.x / width * 1.6, 0.85, 0.95) if size.x > 0 else 0.9

func refresh() -> void:
	_ensure_world()
	world.sync(GameState.simulation, GameState.save)
	var simulation = GameState.simulation
	var playing: bool = simulation.song_remaining > 0.0 and not str(simulation.current_song).is_empty()
	song_bar.visible = playing
	if playing:
		var song: Dictionary = DataCatalog.get_item("songs", str(simulation.current_song))
		song_total = maxf(1.0, float(song.get("duration_seconds", 1.0)))
		song_title.text = DataCatalog.localized(song.get("title", {})) + "  ·  " + DataCatalog.text("song_remaining", {"seconds": ceili(simulation.song_remaining)})
		song_note.self_modulate = UIKit.GENRE_COLORS.get(str(song.get("genre", "")), UIKit.LAMP).lightened(0.25)
		song_progress.max_value = song_total
		song_progress.value = song_total - simulation.song_remaining
	closed_pill.visible = simulation.closed_remaining > 0.0
	if closed_pill.visible:
		closed_label.text = DataCatalog.text("venue_closed", {"seconds": ceili(simulation.closed_remaining)})
		closed_pill.reset_size()
		closed_pill.position = (size - closed_pill.size) / 2.0
	_update_hint()
	_place_overlays()

## First-night coaching: point at the first order, then at the music button for the first wish.
func _update_hint() -> void:
	var stats: Dictionary = GameState.save.get("stats", {})
	var target: Vector2 = Vector2.INF
	var text: String = ""
	var anyone_served: bool = false
	for slot in world.slots:
		if slot.locked:
			continue
		if str(slot.status) in ["preparing", "served"]:
			anyone_served = true
	if int(stats.get("orders_served", 0)) == 0 and not anyone_served:
		for slot in world.slots:
			if not slot.locked and slot.hud.mode == "order":
				target = world_to_screen(slot.hud.position + Vector2(0, -95))
				text = DataCatalog.text("hint_serve")
				break
	elif int(stats.get("songs_played", 0)) == 0 and GameState.simulation.song_remaining <= 0.0:
		for slot in world.slots:
			if not slot.locked and slot.hud.mode == "request":
				target = music_button.position + Vector2(music_button.custom_minimum_size.x / 2, -10)
				text = DataCatalog.text("hint_song")
				break
	hint.visible = target != Vector2.INF and not closed_pill.visible
	hint_arrow.visible = hint.visible
	if hint.visible:
		hint_label.text = text
		var pill: PanelContainer = hint.get_child(0)
		pill.reset_size()
		hint_target = target
		var x: float = clampf(target.x - pill.size.x / 2, 20, size.x - pill.size.x - 20)
		hint.position = Vector2(x, target.y - 60 - pill.size.y)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_drift_backdrop()
	refresh_timer += delta
	if refresh_timer >= 0.1:
		refresh_timer = 0.0
		refresh()
	if hint.visible:
		hint_time += delta
		hint_arrow.position = hint_target + Vector2(0, absf(sin(hint_time * 5.0)) * -14.0)
	if touches.is_empty() and velocity.length() > 5.0:
		camera.position -= velocity * delta / camera.zoom.x
		velocity = velocity.lerp(Vector2.ZERO, clampf(delta * 5.0, 0.0, 1.0))
		_clamp_camera()

# --------------------------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				press_position = event.position
				moved = 0.0
				velocity = Vector2.ZERO
			pinch_distance = _pinch_span()
		else:
			var was_single: bool = touches.size() == 1
			touches.erase(event.index)
			if was_single and moved <= TAP_SLOP:
				_tap(event.position)
			pinch_distance = _pinch_span()
		accept_event()
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		touches[event.index] = event.position
		if touches.size() >= 2:
			var span: float = _pinch_span()
			if pinch_distance > 0.0 and span > 0.0:
				_zoom_at(_pinch_center(), span / pinch_distance)
			pinch_distance = span
			moved = TAP_SLOP + 1.0
		else:
			moved += event.relative.length()
			camera.position -= event.relative / camera.zoom.x
			velocity = event.velocity if event.velocity.length() < 4000.0 else event.velocity.normalized() * 4000.0
			_clamp_camera()
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.1)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		camera.position += event.delta * 12.0 / camera.zoom.x
		_clamp_camera()

func _pinch_span() -> float:
	if touches.size() < 2:
		return 0.0
	var points: Array = touches.values()
	return (points[0] as Vector2).distance_to(points[1])

func _pinch_center() -> Vector2:
	var points: Array = touches.values()
	return ((points[0] as Vector2) + (points[1] as Vector2)) / 2.0

func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before: Vector2 = screen_to_world(screen_point)
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	var after: Vector2 = screen_to_world(screen_point)
	camera.position += before - after
	_clamp_camera()

func screen_to_world(screen_point: Vector2) -> Vector2:
	return camera.position + (screen_point - size / 2.0) / camera.zoom.x

func world_to_screen(world_point: Vector2) -> Vector2:
	return (world_point - camera.position) * camera.zoom.x + size / 2.0

func _clamp_camera() -> void:
	if world == null or world.room_rect.size == Vector2.ZERO or size == Vector2.ZERO:
		return
	var rect: Rect2 = world.room_rect.grow(160)
	var half: Vector2 = size / 2.0 / camera.zoom.x
	var low: Vector2 = rect.position + half - Vector2(0, top_inset / camera.zoom.x)
	var high: Vector2 = rect.end - half + Vector2(0, bottom_inset / camera.zoom.x)
	camera.position.x = rect.get_center().x if low.x > high.x else clampf(camera.position.x, low.x, high.x)
	camera.position.y = rect.get_center().y if low.y > high.y else clampf(camera.position.y, low.y, high.y)

func _tap(screen_point: Vector2) -> void:
	var hit: Dictionary = world.pick(screen_to_world(screen_point))
	match str(hit.kind):
		"table": table_tapped.emit(int(hit.index))
		"slot": slot_tapped.emit(int(hit.index))
		"stage": stage_tapped.emit()

# --------------------------------------------------------------------------------------------
# Payouts
# --------------------------------------------------------------------------------------------

func _on_payout(world_point: Vector2, amount: int, angry: bool) -> void:
	var start: Vector2 = world_to_screen(world_point)
	var label: Label = Label.new()
	label.text = DataCatalog.text("floor_left_angry") if angry and amount <= 0 else "+" + DataCatalog.text("money_amount", {"amount": UIKit.amount(amount, DataCatalog.locale)})
	label.add_theme_font_override("font", UIKit.font("number"))
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", Color("ff6a5a") if angry and amount <= 0 else UIKit.BRASS_LIGHT)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 12)
	label.position = start - Vector2(80, 30)
	fx.add_child(label)
	var rise: Tween = label.create_tween()
	rise.set_parallel(true)
	rise.tween_property(label, "position:y", label.position.y - 110, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_property(label, "modulate:a", 0.0, 1.4).set_delay(0.5)
	rise.chain().tween_callback(label.queue_free)
	if amount <= 0 or not money_target.is_valid():
		return
	var target: Vector2 = money_target.call() - global_position
	var coins: int = clampi(3 + amount / 400, 3, 9)
	for k in range(coins):
		var coin: TextureRect = TextureRect.new()
		coin.texture = WorldData.texture(WorldData.ROOT + "fx/coin.svg")
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.size = Vector2(46, 46)
		coin.position = start + Vector2(randf_range(-50, 50), randf_range(-30, 20))
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx.add_child(coin)
		var tween: Tween = coin.create_tween()
		tween.tween_property(coin, "position:y", coin.position.y - randf_range(40, 90), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.05 * k)
		tween.tween_property(coin, "position", target - coin.size / 2, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_callback(coin.queue_free)
