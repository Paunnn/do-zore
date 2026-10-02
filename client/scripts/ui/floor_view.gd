extends Control
## The kafana floor: painted room, the band on stage and every table with its guests.
## Presentation only; it reads GameState and reports taps through signals.
signal table_tapped(index: int)
signal stage_tapped

const TableView = preload("res://scripts/ui/table_view.gd")
const ART = "res://assets/art/"
const SPRITES = "res://assets/sprites/"
const WORLD_WIDTH = 1080.0
const TOP_PAD = 90.0
const TABLE_SCALE = 0.78
const FIRST_ROW = 905.0
const ROW_STEP = 330.0
const STAGGER = 56.0
const SKY = Color("1b2235")
const INK = Color("f4eedc")
const MUTED = Color("9fb3ad")
const GOLD = Color("eab575")
const RED = Color("ed8c7a")
const WARM = Color(1.0, 0.8, 0.47)

var layout: Dictionary = {}
var bottom_padding: float = 240.0
var scroll: ScrollContainer
var world: Control
var canvas: Control
var room: TextureRect
var floor_tiles: TextureRect
var musician: TextureRect
var musician_atlas: AtlasTexture
var lights: Array = []
var tables_root: Control
var fx: Control
var table_views: Array = []
var last_tables: Array = []
var stage_band: Label
var stage_song: Label
var stage_time: Label
var closed_shade: ColorRect
var closed_label: Label
var time: float = 0.0
var musician_position: float = 0.0
var note_timer: float = 0.0
var refresh_timer: float = 0.0
var genre_names: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout = JSON.parse_string(FileAccess.get_file_as_string(ART + "layout.json"))
	for genre in DataCatalog.items("genres"):
		genre_names[str(genre.id)] = DataCatalog.localized(genre.name)
	var sky: ColorRect = ColorRect.new()
	sky.color = SKY
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(world)
	# All art is placed in canvas pixels: the painted room is exactly WORLD_WIDTH wide.
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	world.add_child(canvas)
	room = _texture_rect(load(ART + "kafana_room.jpg"), Vector2(WORLD_WIDTH, float(layout.room_height)))
	canvas.add_child(room)
	floor_tiles = _texture_rect(load(ART + "floor_tile.jpg"), Vector2(WORLD_WIDTH, float(layout.floor_tile_height)))
	floor_tiles.stretch_mode = TextureRect.STRETCH_TILE
	floor_tiles.position.y = float(layout.room_height)
	canvas.add_child(floor_tiles)
	_build_musician()
	_build_lights()
	_build_stage_sign()
	tables_root = Control.new()
	tables_root.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(tables_root)
	fx = Control.new()
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(fx)
	closed_shade = ColorRect.new()
	closed_shade.color = Color(0.02, 0.03, 0.04, 0.72)
	closed_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	closed_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed_shade.visible = false
	add_child(closed_shade)
	closed_label = Label.new()
	closed_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	closed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	closed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	closed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	closed_label.add_theme_font_size_override("font_size", 46)
	closed_label.add_theme_color_override("font_color", RED)
	closed_shade.add_child(closed_label)
	resized.connect(_layout)
	_rebuild_tables()
	refresh()

func _texture_rect(texture: Texture2D, rect_size: Vector2) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = rect_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _build_musician() -> void:
	var info: Dictionary = layout.musician
	musician_atlas = AtlasTexture.new()
	musician_atlas.atlas = load(ART + "musician_sheet.webp")
	musician_atlas.region = Rect2(0, 0, float(info.frame_w), float(info.frame_h))
	musician = _texture_rect(musician_atlas, Vector2(float(info.w), float(info.h)))
	musician.position = Vector2(float(info.x), float(info.y))
	musician.visible = false
	canvas.add_child(musician)
	var stage: Array = layout.stage
	var stage_button: Button = Button.new()
	stage_button.flat = true
	stage_button.focus_mode = Control.FOCUS_NONE
	stage_button.position = Vector2(float(stage[0]), float(stage[1]))
	stage_button.size = Vector2(float(stage[2]) - float(stage[0]), float(stage[3]) - float(stage[1]))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		stage_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	stage_button.pressed.connect(func(): stage_tapped.emit())
	canvas.add_child(stage_button)

func _glow_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.3, Color(1, 1, 1, 0.42))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture

func _build_lights() -> void:
	var glow: GradientTexture2D = _glow_texture()
	var material_add: CanvasItemMaterial = CanvasItemMaterial.new()
	material_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for kind in ["lanterns", "bulbs"]:
		for point in layout[kind]:
			var radius: float = 150.0 if kind == "lanterns" else 30.0
			var light: TextureRect = _texture_rect(glow, Vector2(radius, radius) * 2)
			light.position = Vector2(float(point[0]), float(point[1]) + (18.0 if kind == "lanterns" else 0.0)) - Vector2(radius, radius)
			light.material = material_add
			light.modulate = WARM
			canvas.add_child(light)
			lights.append({"node": light, "lantern": kind == "lanterns", "phase": rng.randf() * TAU, "speed": rng.randf_range(0.6, 1.4)})

func _build_stage_sign() -> void:
	var sign: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.11, 0.86)
	style.set_corner_radius_all(22)
	style.set_border_width_all(3)
	style.border_color = GOLD.darkened(0.25)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 18
	sign.add_theme_stylebox_override("panel", style)
	sign.position = Vector2(588, 452)
	sign.custom_minimum_size = Vector2(420, 0)
	canvas.add_child(sign)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	sign.add_child(column)
	column.add_child(_label(DataCatalog.text("stage"), 22, GOLD))
	stage_band = _label("", 32, INK)
	column.add_child(stage_band)
	stage_song = _label("", 27, GOLD)
	stage_song.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(stage_song)
	stage_time = _label("", 22, MUTED)
	column.add_child(stage_time)
	var button: Button = Button.new()
	button.text = DataCatalog.text("choose_song")
	button.icon = load(SPRITES + "icons/note.svg")
	button.expand_icon = true
	button.custom_minimum_size = Vector2(0, 92)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_constant_override("icon_max_width", 40)
	button.add_theme_color_override("icon_normal_color", GOLD)
	button.add_theme_color_override("icon_pressed_color", GOLD)
	button.add_theme_color_override("icon_hover_color", GOLD)
	var accent: StyleBoxFlat = StyleBoxFlat.new()
	accent.bg_color = Color("684d34")
	accent.set_corner_radius_all(18)
	accent.set_border_width_all(2)
	accent.border_color = GOLD.darkened(0.3)
	button.add_theme_stylebox_override("normal", accent)
	button.pressed.connect(func(): stage_tapped.emit())
	column.add_child(button)

func _label(value: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _table_position(table_index: int) -> Vector2:
	var columns: int = maxi(1, int(GameState.simulation.rules.floor_columns))
	var column: int = table_index % columns
	var row: int = table_index / columns
	var table_size: Vector2 = Vector2(float(layout.table.w), float(layout.table.h)) * TABLE_SCALE
	var lane: float = (WORLD_WIDTH - 40.0) / columns
	var x: float = 20.0 + lane * (column + 0.5) - table_size.x / 2
	return Vector2(x, FIRST_ROW + row * ROW_STEP + (STAGGER if column % 2 == 1 else 0.0))

func _rebuild_tables() -> void:
	for view in table_views:
		view.queue_free()
	table_views.clear()
	last_tables.clear()
	var count: int = GameState.simulation.tables.size()
	var order: Array = range(count)
	order.sort_custom(func(a: int, b: int) -> bool: return _table_position(a).y < _table_position(b).y)
	var views: Array = []
	views.resize(count)
	for table_index in order:
		var view = TableView.new()
		view.setup(table_index)
		view.scale = Vector2(TABLE_SCALE, TABLE_SCALE)
		view.position = _table_position(table_index)
		view.tapped.connect(func(i: int): table_tapped.emit(i))
		tables_root.add_child(view)
		views[table_index] = view
	table_views = views
	for table in GameState.simulation.tables:
		last_tables.append(table)
	_layout()

func _layout() -> void:
	if world == null:
		return
	canvas.position = Vector2(maxf(0.0, (size.x - WORLD_WIDTH) / 2), TOP_PAD)
	var bottom: float = float(layout.room_height)
	for view in table_views:
		bottom = maxf(bottom, view.position.y + float(layout.table.h) * TABLE_SCALE)
	var world_height: float = maxf(size.y, TOP_PAD + bottom + bottom_padding)
	world.custom_minimum_size = Vector2(size.x, world_height)
	floor_tiles.size = Vector2(WORLD_WIDTH, world_height - TOP_PAD - float(layout.room_height))

func refresh() -> void:
	var simulation = GameState.simulation
	if simulation.tables.size() != table_views.size():
		_rebuild_tables()
	var mood_rules: Dictionary = DataCatalog.data.economy.mood
	for table_index in range(table_views.size()):
		var table: Dictionary = simulation.tables[table_index]
		var previous: Dictionary = last_tables[table_index] if table_index < last_tables.size() else {}
		if not is_same(previous, table) and not str(previous.get("guest_type", "")).is_empty() and str(table.guest_type).is_empty():
			_on_departure(table_index, previous)
		table_views[table_index].apply(table, mood_rules, genre_names)
		if table_index < last_tables.size():
			last_tables[table_index] = table
	stage_band.text = DataCatalog.localized(GameState.band().name)
	var playing: bool = simulation.song_remaining > 0.0 and not simulation.current_song.is_empty()
	stage_song.text = DataCatalog.localized(DataCatalog.get_item("songs", simulation.current_song).get("title", {})) if playing else DataCatalog.text("song_idle")
	stage_time.text = DataCatalog.text("song_remaining", {"seconds": ceili(simulation.song_remaining)}) if playing else ""
	stage_time.visible = playing
	closed_shade.visible = simulation.closed_remaining > 0.0
	if closed_shade.visible:
		closed_label.text = DataCatalog.text("venue_closed", {"seconds": ceili(simulation.closed_remaining)})

func _on_departure(table_index: int, previous: Dictionary) -> void:
	var simulation = GameState.simulation
	if simulation.closed_remaining > 0.0:
		return
	var angry: bool = float(previous.get("mood", 50)) <= float(DataCatalog.data.economy.mood.leave_at_or_below) + 2.0
	var amount: int = int(previous.get("bill", 0))
	if not angry:
		amount += int(floor(simulation.tip_for(previous)))
	var text: String = DataCatalog.text("floor_left_angry") if angry and amount <= 0 else "+" + DataCatalog.text("money_amount", {"amount": amount})
	if amount <= 0 and not angry:
		return
	var view: Control = table_views[table_index]
	var label: Label = _label(text, 44, RED if angry and amount <= 0 else GOLD)
	label.add_theme_color_override("font_outline_color", Color("2a1a0c"))
	label.add_theme_constant_override("outline_size", 10)
	label.position = view.position + Vector2(90, 60)
	fx.add_child(label)
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 150, 1.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 1.8).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)

func _spawn_note() -> void:
	var info: Dictionary = layout.musician
	var song: Dictionary = DataCatalog.get_item("songs", GameState.simulation.current_song)
	var note: TextureRect = _texture_rect(load(SPRITES + "icons/note.svg"), Vector2(52, 52))
	note.modulate = TableView.GENRE_COLORS.get(str(song.get("genre", "")), GOLD)
	var start: Vector2 = Vector2(float(info.x) + float(info.w) * randf_range(0.35, 0.75), float(info.y) + float(info.h) * 0.3)
	note.position = start
	note.rotation = randf_range(-0.3, 0.3)
	fx.add_child(note)
	var tween: Tween = note.create_tween()
	tween.set_parallel(true)
	tween.tween_property(note, "position", note.position + Vector2(randf_range(-80, 80), -190), 2.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(note, "modulate:a", 0.0, 2.4).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(note.queue_free)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	time += delta
	refresh_timer += delta
	if refresh_timer >= 0.15:
		refresh_timer = 0.0
		refresh()
	for light in lights:
		var t: float = time * float(light.speed) + float(light.phase)
		var level: float
		if light.lantern:
			level = 0.32 + 0.1 * sin(t * 2.1) + 0.06 * sin(t * 5.3) + 0.04 * sin(t * 11.7)
		else:
			level = 0.18 + 0.32 * pow(0.5 + 0.5 * sin(t * 1.3), 2.0)
		light.node.modulate = Color(WARM.r, WARM.g, WARM.b, level)
	var simulation = GameState.simulation
	var playing: bool = simulation.song_remaining > 0.0 and not simulation.current_song.is_empty()
	var info: Dictionary = layout.musician
	var frames: int = int(info.frames)
	var cycle: float = 2.0 * (frames - 1)
	if playing or musician_position > 0.0:
		musician_position += delta * float(info.fps)
		if musician_position >= cycle:
			musician_position = fmod(musician_position, cycle) if playing else 0.0
	musician.visible = musician_position > 0.0
	if musician.visible:
		var step: int = int(musician_position)
		var frame: int = step if step < frames else int(cycle) - step
		var columns: int = int(info.columns)
		musician_atlas.region = Rect2((frame % columns) * float(info.frame_w), (frame / columns) * float(info.frame_h), float(info.frame_w), float(info.frame_h))
	if playing:
		note_timer -= delta
		if note_timer <= 0.0:
			note_timer = randf_range(0.45, 0.8)
			_spawn_note()
