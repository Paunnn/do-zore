extends Control
## Presentation only: actions enter GameState; all balance lives in the catalog.
## The city fills the screen; a floating HUD sits over it (money, mood, the venue and the road to
## the next one), round buttons open the screens, and every screen is a cream card with a red
## header over a tablecloth trim (see ui_kit.gd).
const UIKit = preload("res://scripts/ui/ui_kit.gd")
const FloorView = preload("res://scripts/ui/floor_view.gd")
const SPRITES = "res://assets/sprites/"
const TABS = ["floor", "band", "menu", "upgrades", "venues"]

var shell: MarginContainer
var body: VBoxContainer
var floor_view: Control
var floor_spacer: Control
var dim_backdrop: ColorRect
var sheet: PanelContainer
var hud_panel: Control
var nav_panel: Control
var toast_panel: PanelContainer
var content_scroll: ScrollContainer
var money_icon: TextureRect
var money_label: Label
var mood_icon: TextureRect
var mood_bar: ProgressBar
var guest_label: Label
var venue_label: Label
var goal_button: Button
var goal_label: Label
var goal_bar: ProgressBar
var goal_ready: bool = false
var toast: Label
var toast_seconds: float = 0.0
var active_tab: String = "floor"
var nav_buttons: Dictionary = {}
var modal: Control
var modal_body: VBoxContainer
var modal_scroll: ScrollContainer
var modal_kind: String = ""
var modal_table: int = -1
var event_timer: Label
var modal_queue: Array = []
var last_refresh: float = 0.0
var board: Dictionary = {}
var purchase_buttons: Array = []
var song_buttons: Array = []
var celebration: Control
var pulse_time: float = 0.0
var card_title: Label
var side_column: VBoxContainer
var music_button: TextureButton

## Draws a dotted leader between a menu item and its price, like a printed cenovnik.
class Leader extends Control:
	func _draw() -> void:
		var y: float = size.y - 10.0
		var x: float = 6.0
		while x < size.x - 4.0:
			draw_circle(Vector2(x, y), 2.0, Color(0.48, 0.38, 0.28, 0.55))
			x += 12.0

## A dotted brass road with lamps between two stops of the journey.
class Road extends Control:
	var from_left: bool = true
	func _draw() -> void:
		var a: Vector2 = Vector2(size.x * (0.3 if from_left else 0.7), 0)
		var b: Vector2 = Vector2(size.x * (0.7 if from_left else 0.3), size.y)
		var steps: int = 9
		for k in range(steps + 1):
			var t: float = float(k) / steps
			var p: Vector2 = a.lerp(b, t) + Vector2(sin(t * PI) * 30.0 * (1 if from_left else -1), 0)
			if k % 3 == 1:
				draw_circle(p, 9.0, Color(1.0, 0.83, 0.42, 0.25))
				draw_circle(p, 4.5, Color(1.0, 0.83, 0.42))
			else:
				draw_circle(p, 2.5, Color(0.85, 0.65, 0.19, 0.9))

## Slowly turning lamp rays behind the new venue in the opening celebration.
class Rays extends Control:
	var turn: float = 0.0
	func _process(delta: float) -> void:
		turn += delta * 0.25
		queue_redraw()
	func _draw() -> void:
		var center: Vector2 = size / 2.0
		var reach: float = size.length()
		for k in range(16):
			var a: float = turn + k * TAU / 16.0
			var points: PackedVector2Array = PackedVector2Array([center, center + Vector2.from_angle(a - 0.07) * reach, center + Vector2.from_angle(a + 0.07) * reach])
			draw_colored_polygon(points, Color(1.0, 0.83, 0.42, 0.07))

func _ready() -> void:
	_install_theme()
	_build_shell()
	EventBus.locale_changed.connect(_rebuild)
	EventBus.event_raised.connect(_on_event)
	EventBus.event_resolved.connect(_on_outcome)
	EventBus.offline_ready.connect(func(result): _enqueue("offline", result))
	EventBus.save_conflict.connect(func(server): _enqueue("conflict", server))
	EventBus.leaderboard_ready.connect(_on_board)
	EventBus.notice.connect(_notice)
	EventBus.audio_requested.connect(_silent_audio_hook)
	get_viewport().size_changed.connect(_safe_area)
	get_tree().auto_accept_quit = false
	_open_tab("floor")
	_safe_area.call_deferred()
	if not GameState.simulation.active_event.is_empty(): _on_event.call_deferred(GameState.simulation.active_event)

func _install_theme() -> void:
	var kit: Theme = Theme.new()
	kit.default_font = UIKit.font("body")
	kit.default_font_size = UIKit.BODY
	kit.set_color("font_color", "Label", UIKit.INK)
	kit.set_font("font", "Button", UIKit.font("label"))
	kit.set_font("font", "CheckButton", UIKit.font("label"))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		kit.set_color(key, "CheckButton", UIKit.INK)
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		kit.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	for icon_name in ["checked", "checked_mirrored"]:
		kit.set_icon(icon_name, "CheckButton", UIKit.texture("toggle_on"))
	for icon_name in ["unchecked", "unchecked_mirrored"]:
		kit.set_icon(icon_name, "CheckButton", UIKit.texture("toggle_off"))
	kit.set_constant("separation", "VBoxContainer", UIKit.GAP)
	kit.set_constant("separation", "HBoxContainer", UIKit.GAP)
	var grabber: StyleBoxFlat = StyleBoxFlat.new()
	grabber.bg_color = Color(UIKit.WALNUT, 0.35)
	grabber.set_corner_radius_all(6)
	grabber.content_margin_left = 6
	grabber.content_margin_right = 6
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		kit.set_stylebox(state, "VScrollBar", grabber)
	kit.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	theme = kit

# --------------------------------------------------------------------------------------------
# Small builders
# --------------------------------------------------------------------------------------------

func _t(key: String, args: Dictionary = {}) -> String:
	return DataCatalog.text(key, args)

func _name(collection: String, id: String, field: String = "name") -> String:
	return DataCatalog.localized(DataCatalog.get_item(collection, id).get(field, {}))

## Serbian counts take one of three forms (1 sto, 3 stola, 5 stolova); English two.
func _plural(key: String, count: int) -> String:
	var form: String = "many"
	if DataCatalog.locale == "sr":
		if count % 10 == 1 and count % 100 != 11: form = "one"
		elif count % 10 in [2, 3, 4] and not (count % 100 in [12, 13, 14]): form = "few"
	elif count == 1:
		form = "one"
	return _t(key + "_" + form, {"count": count})

func _venue_stats(venue: Dictionary) -> String:
	return _t("venue_stats", {"tables": _plural("tables", int(venue.get("base_tables", 0))), "max": int(venue.get("max_tables", 0)),
		"rate": UIKit.amount(int(venue.get("offline_income_per_minute", 0)), DataCatalog.locale)})

func _money(value: int) -> String:
	return _t("money_amount", {"amount": UIKit.amount(value, DataCatalog.locale)})

func _icon(name: String) -> Texture2D:
	return load(SPRITES + "icons/" + name + ".svg")

func _label(value: String, font_size: int = UIKit.BODY, color: Color = UIKit.INK, kind: String = "body") -> Label:
	return UIKit.label(value, kind, font_size, color)

func _card(parent: Node, piece: String = "row") -> VBoxContainer:
	var column: VBoxContainer = UIKit.column(UIKit.S)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel: PanelContainer = UIKit.panel(piece, column)
	parent.add_child(panel)
	return column

## Price button with a coin. Colour pictures keep their own colours, so the icon is not tinted.
func _price_button(price: int, action: Callable, kind: String = "gold") -> Button:
	var button: Button = UIKit.make_button(UIKit.amount(price, DataCatalog.locale), action, kind, 30)
	button.icon = _icon("coin")
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 40)
	button.add_theme_font_override("font", UIKit.font("number"))
	button.add_theme_font_size_override("font_size", 34)
	for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.5))
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(210, 96)
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	return button

## A short state stamp where a price would be: owned, current or locked.
func _stamp(glyph: String, text: String, color: Color) -> Control:
	var stamp: HBoxContainer = UIKit.row(UIKit.XS)
	stamp.alignment = BoxContainer.ALIGNMENT_END
	stamp.custom_minimum_size = Vector2(210, 0)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stamp.add_child(UIKit.tinted(glyph, 34, color))
	var words: Label = _label(text, UIKit.SMALL, color, "label")
	words.autowrap_mode = TextServer.AUTOWRAP_OFF
	stamp.add_child(words)
	return stamp

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

# --------------------------------------------------------------------------------------------
# Shell: a floating HUD over the city, a screen card, the toast and the round action buttons
# --------------------------------------------------------------------------------------------

func _build_shell() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = UIKit.NIGHT
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	floor_view = FloorView.new()
	add_child(floor_view)
	floor_view.table_tapped.connect(_on_table_tapped)
	floor_view.stage_tapped.connect(func(): _show_songs(-1))
	floor_view.slot_tapped.connect(func(_index): _open_tab("upgrades"))
	floor_view.venue_tapped.connect(func(id): _open_tab("venues", id))
	floor_view.money_target = func() -> Vector2: return money_icon.get_global_rect().get_center() if is_instance_valid(money_icon) else Vector2.ZERO
	floor_view.music_point = func() -> Vector2: return music_button.get_global_rect().get_center() - Vector2(0, 70) if is_instance_valid(music_button) else Vector2.INF
	# Screens open on a card over the still-running city, which dims and stops taking taps.
	dim_backdrop = ColorRect.new()
	dim_backdrop.color = Color(UIKit.NIGHT, 0.55)
	dim_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	dim_backdrop.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _open_tab("floor"))
	add_child(dim_backdrop)
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)
	var column: VBoxContainer = UIKit.column(UIKit.GAP)
	shell.add_child(column)
	_build_hud(column)
	_build_card(column)
	floor_spacer = Control.new()
	floor_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	floor_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(floor_spacer)
	toast_panel = UIKit.panel("pill_dark")
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	column.add_child(toast_panel)
	toast = _label("", UIKit.BODY, Color.WHITE, "bold")
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_panel.add_child(toast)
	_build_nav(column)
	_build_side()

func _build_hud(column: VBoxContainer) -> void:
	var hud: VBoxContainer = UIKit.column(UIKit.S)
	hud_panel = hud
	column.add_child(hud)
	var top: HBoxContainer = UIKit.row(UIKit.S)
	hud.add_child(top)
	# Money: a big coin over the left end of a dark pill; earnings fly to it.
	var money: HBoxContainer = UIKit.row(UIKit.XS)
	money_icon = UIKit.picture(_icon("coin"), 64)
	money.add_child(money_icon)
	money_label = _label("", 42, Color.WHITE, "number")
	money_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	money_label.clip_text = true
	money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.outlined(money_label, 10)
	money.add_child(money_label)
	_counter(top, money, 1.9)
	var mood: HBoxContainer = UIKit.row(UIKit.XS)
	mood_icon = UIKit.picture(_icon("mood_neutral"), 50)
	mood.add_child(mood_icon)
	mood_bar = UIKit.bar(UIKit.GOLD, 18)
	mood_bar.min_value = DataCatalog.data.economy.mood.min
	mood_bar.max_value = DataCatalog.data.economy.mood.max
	mood_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mood_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mood.add_child(mood_bar)
	_counter(top, mood, 1.1)
	top.add_child(UIKit.round_button("trophy", func(): _open_tab("leaderboard"), "cream", 90))
	top.add_child(UIKit.round_button("gear", func(): _open_tab("settings"), "cream", 90))
	# The venue's name on a red ribbon, guests in the room, and the road to the next venue.
	var second: HBoxContainer = UIKit.row(UIKit.S)
	hud.add_child(second)
	venue_label = _label("", 34, Color.WHITE, "display")
	venue_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	venue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.outlined(venue_label, 9, Color("5a1210"))
	var ribbon: PanelContainer = UIKit.panel("header", venue_label)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	second.add_child(ribbon)
	var guests: HBoxContainer = UIKit.row(UIKit.XS)
	guests.add_child(UIKit.tinted("people", 40, Color.WHITE))
	guest_label = _label("", 32, Color.WHITE, "number")
	guest_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIKit.outlined(guest_label, 8)
	guests.add_child(guest_label)
	var guest_pill: PanelContainer = UIKit.panel("pill_dark", guests)
	guest_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guest_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	second.add_child(guest_pill)
	goal_button = Button.new()
	goal_button.focus_mode = Control.FOCUS_NONE
	goal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	goal_button.custom_minimum_size = Vector2(0, 76)
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		goal_button.add_theme_stylebox_override(state, UIKit.box("pill_dark"))
	goal_button.pressed.connect(func(): _open_tab("venues"))
	second.add_child(goal_button)
	var goal: HBoxContainer = UIKit.row(UIKit.S)
	goal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	goal.offset_left = 18
	goal.offset_right = -24
	goal.offset_top = 6
	goal.offset_bottom = -12
	goal_button.add_child(goal)
	goal.add_child(UIKit.tinted("map", 40, UIKit.GOLD))
	var goal_text: VBoxContainer = UIKit.column(3)
	goal_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_text.alignment = BoxContainer.ALIGNMENT_CENTER
	goal.add_child(goal_text)
	goal_label = _label("", UIKit.TINY, Color.WHITE, "label")
	goal_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	goal_label.clip_text = true
	UIKit.outlined(goal_label, 6, UIKit.OUTLINE, false)
	goal_text.add_child(goal_label)
	goal_bar = UIKit.bar(UIKit.GOLD, 14)
	goal_text.add_child(goal_bar)

func _counter(parent: HBoxContainer, content: Control, ratio: float) -> void:
	var chip: PanelContainer = UIKit.panel("pill_dark", content)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.size_flags_stretch_ratio = ratio
	parent.add_child(chip)

## The screen card: a red header with the title and a close button over a tablecloth trim.
func _build_card(column: VBoxContainer) -> void:
	sheet = PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UIKit.box("card"))
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(sheet)
	var inner: VBoxContainer = UIKit.column(UIKit.S)
	sheet.add_child(inner)
	var head: HBoxContainer = UIKit.row(UIKit.S)
	inner.add_child(head)
	card_title = _label("", 44, Color.WHITE, "display")
	card_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.outlined(card_title, 10, Color("5a1210"))
	var ribbon: PanelContainer = UIKit.panel("header", card_title)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ribbon)
	var close: TextureButton = TextureButton.new()
	close.texture_normal = UIKit.texture("close")
	close.texture_pressed = UIKit.texture("close_pressed")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.custom_minimum_size = Vector2(84, 90)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): _open_tab("floor"))
	head.add_child(close)
	inner.add_child(UIKit.kilim())
	content_scroll = ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(content_scroll)
	var inset: MarginContainer = MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_right", UIKit.S)
	inset.add_theme_constant_override("margin_top", UIKit.XS)
	inset.add_theme_constant_override("margin_bottom", UIKit.L)
	content_scroll.add_child(inset)
	body = UIKit.column(UIKit.GAP)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	inset.add_child(body)

## Bottom: map, the music (the main action) and upgrades, as big round buttons.
func _build_nav(column: VBoxContainer) -> void:
	var nav: HBoxContainer = UIKit.row(0)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_panel = nav
	column.add_child(nav)
	var specs: Array = [["venues", "map", "gold", 136, _t("nav_map")], ["music", "note", "red", 168, _t("nav_music")], ["upgrades", "nav_upgrades", "gold", 136, _t("nav_upgrades")]]
	for spec in specs:
		var key: String = spec[0]
		var action: Callable = _toggle_map if key == "venues" else (func(): _show_songs(-1)) if key == "music" else _open_tab.bind(key)
		var holder: Control = UIKit.round_button(spec[1], action, spec[2], spec[3], spec[4])
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(holder)
		nav_buttons[key] = holder
		if key == "music":
			music_button = holder.get_meta("button")

## Right edge: the band and the drinks menu.
func _build_side() -> void:
	side_column = UIKit.column(UIKit.M)
	side_column.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	side_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(side_column)
	for spec in [["band", "nav_band", _t("nav_band")], ["menu", "nav_menu", _t("nav_menu")]]:
		var holder: Control = UIKit.round_button(spec[1], _open_tab.bind(spec[0]), "cream", 100, spec[2])
		side_column.add_child(holder)
		nav_buttons[spec[0]] = holder

func _toggle_map() -> void:
	if active_tab != "floor":
		_open_tab("floor")
	if floor_view.view_width >= floor_view.MAP_ZOOM:
		floor_view.show_venue()
	else:
		floor_view.show_map()

func _style_nav() -> void:
	var on_floor: bool = active_tab == "floor"
	if is_instance_valid(side_column):
		side_column.visible = on_floor

func _safe_area() -> void:
	var left: int = UIKit.GUTTER
	var right: int = UIKit.GUTTER
	var top: int = UIKit.L
	var bottom: int = UIKit.M
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var screen: Vector2i = DisplayServer.screen_get_size()
		var logical: Vector2 = get_viewport_rect().size
		if screen.x > 0 and screen.y > 0:
			left += int(safe.position.x * logical.x / screen.x)
			right += int((screen.x - safe.end.x) * logical.x / screen.x)
			top += int(safe.position.y * logical.y / screen.y)
			bottom += int((screen.y - safe.end.y) * logical.y / screen.y)
	shell.add_theme_constant_override("margin_left", left)
	shell.add_theme_constant_override("margin_right", right)
	shell.add_theme_constant_override("margin_top", top)
	shell.add_theme_constant_override("margin_bottom", bottom)
	_fit_floor.call_deferred()

func _fit_floor() -> void:
	# The camera keeps the venue between the HUD and the round buttons; the side buttons hug the right edge.
	if is_instance_valid(floor_view) and is_instance_valid(nav_panel) and is_instance_valid(hud_panel):
		var top: float = hud_panel.get_global_rect().end.y
		var bottom: float = get_viewport_rect().size.y - nav_panel.get_global_rect().position.y
		floor_view.set_insets(top, bottom)
		if is_instance_valid(side_column):
			side_column.reset_size()
			side_column.position = Vector2(get_viewport_rect().size.x - side_column.size.x - shell.get_theme_constant("margin_right") + 4, top + 40)

func _open_tab(key: String, focus: String = "") -> void:
	active_tab = key
	_clear(body)
	purchase_buttons.clear()
	content_scroll.scroll_vertical = 0
	var on_floor: bool = key == "floor"
	floor_spacer.visible = on_floor
	sheet.visible = not on_floor
	dim_backdrop.visible = not on_floor
	_style_nav()
	match key:
		"floor": floor_view.refresh()
		"band": _band()
		"menu": _menu()
		"upgrades": _upgrades()
		"venues": _venues(focus)
		"settings": _settings()
		"leaderboard":
			_draw_board()
			ApiClient.request_leaderboard()
	_refresh()

func _heading(title: String, subtitle: String, _night: bool = false) -> void:
	card_title.text = title
	if not subtitle.is_empty():
		var line: Label = _label(subtitle, UIKit.SMALL, UIKit.MUTED, "bold")
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(line)

func _section(title: String, _night: bool = false) -> void:
	var label: Label = _label(title.to_upper(), UIKit.SMALL, UIKit.RED, "label")
	body.add_child(label)

# --------------------------------------------------------------------------------------------
# HUD refresh
# --------------------------------------------------------------------------------------------

func _refresh() -> void:
	if not is_instance_valid(money_label): return
	money_label.text = UIKit.amount(int(GameState.save.money), DataCatalog.locale)
	var mood: float = GameState.room_mood()
	var mood_rules: Dictionary = DataCatalog.data.economy.mood
	var happy: bool = mood >= float(mood_rules.happy_at_or_above)
	var unhappy: bool = mood < float(mood_rules.unhappy_below)
	mood_icon.texture = _icon("mood_happy" if happy else "mood_unhappy" if unhappy else "mood_neutral")
	mood_bar.value = mood
	UIKit.set_bar_color(mood_bar, Color("5bd16a") if happy else Color("ff5a4a") if unhappy else UIKit.GOLD)
	guest_label.text = str(GameState.guest_count())
	venue_label.text = DataCatalog.localized(GameState.venue().name)
	var next: Dictionary = _next_venue()
	goal_button.visible = not next.is_empty()
	if not next.is_empty():
		var cost: float = maxf(1.0, float(next.unlock_cost))
		goal_ready = float(GameState.save.money) >= cost
		goal_label.text = _t("goal_ready" if goal_ready else "goal_next", {"name": DataCatalog.localized(next.name)})
		goal_bar.max_value = cost
		goal_bar.value = minf(cost, float(GameState.save.money))
		UIKit.set_bar_color(goal_bar, Color("5bd16a") if goal_ready else UIKit.GOLD)
	# Red badges on the buttons whose screens hold something affordable.
	_badge("upgrades", _any_allowed("upgrades"))
	_badge("band", _any_allowed("band_levels"))
	_badge("venues", goal_ready)
	for entry in purchase_buttons:
		if is_instance_valid(entry.button): entry.button.disabled = not entry.allowed.call()
	for button in song_buttons:
		if is_instance_valid(button): button.disabled = GameState.simulation.song_remaining > 0
	if modal_kind == "event" and is_instance_valid(event_timer):
		if GameState.simulation.active_event.is_empty(): _close_modal()
		else: event_timer.text = _t("event_timeout", {"seconds": ceili(GameState.simulation.event_remaining)})

func _any_allowed(collection: String) -> bool:
	for item in DataCatalog.items(collection):
		if GameState.purchase_reason(collection, item.id).is_empty():
			return true
	return false

func _badge(key: String, show: bool) -> void:
	if nav_buttons.has(key) and is_instance_valid(nav_buttons[key]):
		nav_buttons[key].get_meta("badge").visible = show

func _next_venue() -> Dictionary:
	for venue in DataCatalog.items("venues"):
		if int(venue.order) == int(GameState.venue().order) + 1:
			return venue
	return {}

# --------------------------------------------------------------------------------------------
# Floor interaction
# --------------------------------------------------------------------------------------------

func _on_table_tapped(index: int) -> void:
	if index >= GameState.simulation.tables.size(): return
	var table: Dictionary = GameState.simulation.tables[index]
	if str(table.get("guest_type", "")).is_empty(): return
	if str(table.get("order_status", "")) == "waiting":
		if GameState.serve_table(index): _notice("notice_serving", {})
		return
	_show_songs(index)

func _table_mood(table: Dictionary) -> String:
	return _t("dancing") if table.get("dancing", false) else _t("mood_value", {"value": roundi(table.mood)})

func _request_text(table: Dictionary) -> String:
	var song: String = str(table.get("request_song", ""))
	var genre: String = str(table.get("request_genre", ""))
	if song.is_empty() and genre.is_empty(): return _t("no_request")
	return _t("request", {"song": _name("songs", song, "title") if not song.is_empty() else _name("genres", genre)})

func _order_text(table: Dictionary) -> String:
	var status: String = table.get("order_status", "served")
	return _t("order_" + status, {"item": _name("drinks", table.get("order_item", "")), "seconds": ceili(table.get("prep_remaining", 0))})

# --------------------------------------------------------------------------------------------
# Screens
# --------------------------------------------------------------------------------------------

func _purchase(kind: String, id: String) -> void:
	var ok: bool = false
	match kind:
		"band": ok = GameState.buy_band(id)
		"song": ok = GameState.unlock_song(id)
		"upgrade": ok = GameState.buy_upgrade(id)
		"venue":
			floor_view.hold_flight = true
			ok = GameState.buy_venue(id)
			if not ok: floor_view.hold_flight = false
	if ok: SaveSystem.save_now()
	if ok and kind == "venue":
		_open_tab("floor")
		_celebrate(id)
		return
	if ok: _notice("notice_purchase", {})
	var scroll_position: int = content_scroll.scroll_vertical
	_open_tab(active_tab)
	content_scroll.set_deferred("scroll_vertical", scroll_position)

func _band() -> void:
	_heading(_t("nav_band"), _t("band_hint"))
	for band in DataCatalog.items("band_levels"):
		var current: bool = band.id == GameState.save.band_level
		var owned: bool = band.order <= GameState.band().order
		var card: VBoxContainer = _card(body)
		var top: HBoxContainer = UIKit.row(UIKit.M)
		card.add_child(top)
		var stage: TextureRect = UIKit.picture(load("res://assets/ui/bands/%s.png" % str(band.id)), 0)
		stage.custom_minimum_size = Vector2(300, 225)
		if not owned and not current:
			stage.modulate = Color(0.55, 0.55, 0.62, 0.9)
		top.add_child(stage)
		var info: VBoxContainer = UIKit.column(UIKit.XS)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(info)
		info.add_child(_label(DataCatalog.localized(band.name), UIKit.NAME, UIKit.INK, "display"))
		var genres: HBoxContainer = UIKit.row(UIKit.XS)
		for genre in band.get("genres", []):
			genres.add_child(UIKit.tinted("note", 26, UIKit.GENRE_COLORS.get(str(genre), UIKit.BRASS)))
		info.add_child(genres)
		info.add_child(_label(_t("band_stats", {"members": _plural("musicians", int(band.members)), "upkeep": UIKit.amount(int(band.upkeep_per_hour), DataCatalog.locale)}), UIKit.TINY, UIKit.MUTED))
		card.add_child(_label(DataCatalog.localized(band.description), UIKit.SMALL, UIKit.MUTED))
		var reason: String = GameState.purchase_reason("band_levels", band.id)
		if current:
			card.add_child(_stamp("check", _t("current"), UIKit.GREEN))
		elif owned:
			card.add_child(_stamp("check", _t("owned"), UIKit.MUTED))
		elif reason in ["", "notice.not_enough_money"]:
			var button: Button = _price_button(int(band.unlock_cost), _purchase.bind("band", band.id))
			button.disabled = not reason.is_empty()
			purchase_buttons.append({"button": button, "allowed": func(): return GameState.purchase_reason("band_levels", band.id).is_empty()})
			card.add_child(button)
		else:
			var need: String = _name("venues", band.required_venue) if reason == "purchase_venue_required" else _t("locked")
			card.add_child(_stamp("lock", need, UIKit.MUTED))
	_section(_t("known_songs"))
	var songs: VBoxContainer = _card(body)
	var first: bool = true
	for song in DataCatalog.items("songs"):
		if not first: songs.add_child(UIKit.divider())
		first = false
		var line: HBoxContainer = UIKit.row(UIKit.M)
		songs.add_child(line)
		line.add_child(UIKit.tinted("note", 44, UIKit.GENRE_COLORS.get(str(song.genre), UIKit.BRASS)))
		var words: VBoxContainer = UIKit.column(0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_child(words)
		words.add_child(_label(DataCatalog.localized(song.title), UIKit.BODY, UIKit.INK, "bold"))
		words.add_child(_label(_name("genres", song.genre), UIKit.TINY, UIKit.MUTED))
		var reason: String = GameState.purchase_reason("songs", song.id)
		if song.id in GameState.save.unlocked_songs:
			line.add_child(_stamp("check", _t("owned"), UIKit.GREEN))
		elif reason in ["", "notice.not_enough_money"]:
			var button: Button = _price_button(int(song.unlock_cost), _purchase.bind("song", song.id))
			button.disabled = not reason.is_empty()
			purchase_buttons.append({"button": button, "allowed": func(): return GameState.purchase_reason("songs", song.id).is_empty()})
			line.add_child(button)
		else:
			line.add_child(_stamp("lock", _name("band_levels", song.min_band_level), UIKit.MUTED))

func _menu() -> void:
	_heading(_t("nav_menu"), _t("menu_hint"))
	var card: VBoxContainer = _card(body)
	card.add_theme_constant_override("separation", UIKit.M)
	for kind in ["drink", "food"]:
		var heading: Label = _label(_t(kind), UIKit.NAME, UIKit.RED, "label")
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(heading)
		card.add_child(UIKit.divider())
		for item in DataCatalog.items("drinks"):
			if str(item.kind) != kind: continue
			var locked: bool = DataCatalog.get_item("venues", item.unlock_venue).order > GameState.venue().order
			var line: HBoxContainer = UIKit.row(UIKit.M)
			if locked: line.modulate = Color(1, 1, 1, 0.45)
			card.add_child(line)
			line.add_child(UIKit.picture(load(SPRITES + "drinks/%s.svg" % str(item.id)), 84))
			var words: VBoxContainer = UIKit.column(0)
			words.alignment = BoxContainer.ALIGNMENT_CENTER
			line.add_child(words)
			words.add_child(_label(DataCatalog.localized(item.name), UIKit.BODY, UIKit.INK, "bold"))
			var detail: String = _t("requires", {"name": _name("venues", item.unlock_venue)}) if locked else _t("menu_detail", {"cost": int(item.cost), "seconds": int(item.prep_seconds)})
			words.add_child(_label(detail, UIKit.TINY, UIKit.RED if locked else UIKit.MUTED))
			for child in words.get_children(): child.autowrap_mode = TextServer.AUTOWRAP_OFF
			var leader: Leader = Leader.new()
			leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			leader.size_flags_vertical = Control.SIZE_FILL
			leader.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(leader)
			var price: Label = _label(_money(int(item.price)), UIKit.BODY, UIKit.INK, "number")
			price.autowrap_mode = TextServer.AUTOWRAP_OFF
			price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(price)

func _upgrades() -> void:
	_heading(_t("nav_upgrades"), _t("upgrades_hint"))
	for upgrade in DataCatalog.items("upgrades"):
		var level: int = int(GameState.save.upgrades.get(upgrade.id, 0))
		var cost: int = Economy.upgrade_cost(upgrade.id, level)
		var locked: bool = GameState.venue().order < DataCatalog.get_item("venues", upgrade.unlock_venue).order
		var line: HBoxContainer = UIKit.row(UIKit.M)
		_card(body).add_child(line)
		var picture: Control = UIKit.framed(UIKit.texture("upgrades/" + str(upgrade.id)), 124, "ring_dark" if locked else "ring_paper", 0.17)
		if locked: picture.modulate = Color(1, 1, 1, 0.6)
		picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(picture)
		var info: VBoxContainer = UIKit.column(UIKit.XS)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_child(info)
		info.add_child(_label(DataCatalog.localized(upgrade.name), UIKit.NAME, UIKit.INK, "display"))
		info.add_child(_label(DataCatalog.localized(upgrade.description), UIKit.SMALL, UIKit.MUTED))
		var progress: HBoxContainer = UIKit.row(UIKit.S)
		info.add_child(progress)
		var meter: ProgressBar = UIKit.bar(UIKit.BRASS, 16, true)
		meter.max_value = int(upgrade.max_level)
		meter.value = level
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress.add_child(meter)
		var count: Label = _label(_t("level_short", {"level": level, "max": int(upgrade.max_level)}), UIKit.TINY, UIKit.MUTED, "number")
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		progress.add_child(count)
		var reason: String = GameState.purchase_reason("upgrades", upgrade.id)
		if level >= int(upgrade.max_level):
			line.add_child(_stamp("check", _t("max_level"), UIKit.GREEN))
		elif locked:
			line.add_child(_stamp("lock", _name("venues", upgrade.unlock_venue), UIKit.MUTED))
		elif reason == "purchase_table_limit":
			line.add_child(_stamp("lock", _t("table_limit_short"), UIKit.MUTED))
		else:
			var button: Button = _price_button(cost, _purchase.bind("upgrade", upgrade.id))
			button.disabled = not reason.is_empty()
			purchase_buttons.append({"button": button, "allowed": func(): return GameState.purchase_reason("upgrades", upgrade.id).is_empty()})
			line.add_child(button)

## The road from the birtija to the splav: every venue as a card with its building, the next one
## with its price and progress. `focus` scrolls to a venue tapped on the map.
func _venues(focus: String = "") -> void:
	_heading(_t("nav_venues"), _t("venues_hint"))
	var venues: Array = DataCatalog.items("venues").duplicate()
	venues.sort_custom(func(a, b): return int(a.order) < int(b.order))
	var here: int = int(GameState.venue().order)
	for index in venues.size():
		var venue: Dictionary = venues[index]
		var order: int = int(venue.order)
		var state: String = "past" if order < here else "current" if order == here else "next" if order == here + 1 else "locked"
		if index > 0:
			var road: Road = Road.new()
			road.from_left = index % 2 == 1
			road.custom_minimum_size = Vector2(0, 54)
			road.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if state == "locked": road.modulate = Color(1, 1, 1, 0.35)
			body.add_child(road)
		var stop: Control = _venue_stop(venue, state, index % 2 == 0)
		if (focus.is_empty() and (state == "next" or (state == "current" and order == venues.size()))) or str(venue.id) == focus:
			_scroll_to.call_deferred(stop)

## Brings the stop that matters next into view, a little below the top edge.
func _scroll_to(target: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(target) and target.is_inside_tree():
		content_scroll.scroll_vertical = maxi(0, int(target.position.y) - 60)

func _venue_stop(venue: Dictionary, state: String, art_left: bool) -> Control:
	var column: VBoxContainer = UIKit.column(UIKit.S)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel: PanelContainer = UIKit.panel("row", column)
	if state == "current":
		var frame: StyleBoxTexture = UIKit.box("row")
		frame.modulate_color = Color("fff1c8")
		panel.add_theme_stylebox_override("panel", frame)
	body.add_child(panel)
	var line: HBoxContainer = UIKit.row(UIKit.M)
	column.add_child(line)
	var art: TextureRect = UIKit.picture(load("res://assets/ui/venues/%s.png" % str(venue.id)), 0)
	art.custom_minimum_size = Vector2(340, 255)
	if state == "locked":
		art.modulate = Color(0.35, 0.38, 0.55, 0.9)
	var info: VBoxContainer = UIKit.column(UIKit.XS)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var numeral: Label = _label(UIKit.roman(int(venue.order)), UIKit.SMALL, UIKit.RED, "label")
	info.add_child(numeral)
	info.add_child(_label(DataCatalog.localized(venue.name), 46, UIKit.INK, "display"))
	info.add_child(_label(DataCatalog.localized(venue.description), UIKit.SMALL, UIKit.MUTED))
	info.add_child(_label(_venue_stats(venue), UIKit.TINY, UIKit.MUTED))
	if art_left:
		line.add_child(art)
		line.add_child(info)
	else:
		line.add_child(info)
		line.add_child(art)
	var actions: HBoxContainer = UIKit.row(UIKit.S)
	match state:
		"current":
			actions.add_child(_stamp("check", _t("venue_here"), UIKit.GREEN))
		"past":
			actions.add_child(_stamp("check", _t("owned"), UIKit.MUTED))
		"next":
			var price: float = maxf(1.0, float(venue.unlock_cost))
			var progress: HBoxContainer = UIKit.row(UIKit.S)
			column.add_child(progress)
			var meter: ProgressBar = UIKit.bar(UIKit.GOLD, 22, true)
			meter.max_value = price
			meter.value = minf(price, float(GameState.save.money))
			meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			progress.add_child(meter)
			var share: Label = _label(_t("goal_share", {"have": UIKit.amount(mini(int(GameState.save.money), int(price)), DataCatalog.locale), "need": UIKit.amount(int(price), DataCatalog.locale)}), UIKit.TINY, UIKit.MUTED, "number")
			share.autowrap_mode = TextServer.AUTOWRAP_OFF
			progress.add_child(share)
			var button: Button = UIKit.make_button(_t("open_venue", {"name": DataCatalog.localized(venue.name)}), _purchase.bind("venue", venue.id), "red", 32)
			button.disabled = not GameState.purchase_reason("venues", venue.id).is_empty()
			purchase_buttons.append({"button": button, "allowed": func(): return GameState.purchase_reason("venues", venue.id).is_empty()})
			actions.add_child(button)
		"locked":
			actions.add_child(_stamp("lock", _t("locked"), UIKit.MUTED))
	var look: Button = UIKit.make_button(_t("show_on_map"), _show_on_map.bind(str(venue.id)), "paper", 24)
	look.custom_minimum_size = Vector2(230, 84)
	look.size_flags_horizontal = Control.SIZE_SHRINK_END
	if state in ["current", "past", "locked"]:
		var gap: Control = Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(gap)
	actions.add_child(look)
	column.add_child(actions)
	return panel

func _show_on_map(id: String) -> void:
	_open_tab("floor")
	if id == str(GameState.save.venue):
		floor_view.show_venue()
	else:
		floor_view.show_lot(id)

func _settings() -> void:
	_heading(_t("settings"), "")
	var card: VBoxContainer = _card(body)
	for key in ["sound", "music"]:
		var toggle: CheckButton = CheckButton.new()
		toggle.text = _t(key)
		toggle.custom_minimum_size.y = 92
		toggle.add_theme_font_size_override("font_size", UIKit.NAME)
		toggle.button_pressed = SaveSystem.settings.get(key, true)
		toggle.toggled.connect(func(value): SaveSystem.set_setting(key, value))
		card.add_child(toggle)
		card.add_child(UIKit.divider())
	card.add_child(_label(_t("sound_stub"), UIKit.SMALL, UIKit.MUTED))
	_section(_t("language"))
	var languages: HBoxContainer = UIKit.row(UIKit.S)
	body.add_child(languages)
	for locale in ["sr", "en"]:
		var current: bool = DataCatalog.locale == locale
		var button: Button = UIKit.make_button(_t("locale_" + locale), func(): SaveSystem.set_setting("language", locale), "gold" if current else "paper", 28)
		languages.add_child(button)
	_section(_t("save_section"))
	var storage: VBoxContainer = _card(body)
	var status: HBoxContainer = UIKit.row(UIKit.S)
	storage.add_child(status)
	status.add_child(UIKit.tinted("check" if ApiClient.status in ["online", "mock"] else "clock", 32, UIKit.GREEN if ApiClient.status in ["online", "mock"] else UIKit.MUTED))
	var status_text: Label = _label(_t("sync_" + ApiClient.status), UIKit.BODY, UIKit.INK, "bold")
	status_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(status_text)
	storage.add_child(UIKit.make_button(_t("save"), func(): SaveSystem.save_now(); _notice("notice_saved", {}), "paper"))
	if OS.is_debug_build() and DataCatalog.settings.get("demo_tools_enabled", false):
		storage.add_child(UIKit.make_button(_t("demo_conflict"), func(): ApiClient.mock_conflict(), "paper"))
	body.add_child(UIKit.make_button(_t("reset"), _confirm_reset, "red"))
	var footer: Label = _label(_t("app_footer", {"version": str(DataCatalog.settings.get("app_version", ""))}), UIKit.TINY, UIKit.MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(footer)

func _draw_board() -> void:
	_clear(body)
	_heading(_t("leaderboard"), _t("leaderboard_hint", {"week": board.get("week_id", "")}) if board.has("entries") else "")
	if board.is_empty():
		body.add_child(_label(_t("loading"), UIKit.BODY, UIKit.MUTED))
		return
	if board.has("error") or not board.has("entries"):
		var card: VBoxContainer = _card(body)
		card.add_child(UIKit.tinted("trophy", 72, UIKit.BRASS))
		card.add_child(_label(_t("leaderboard_offline"), UIKit.BODY, UIKit.MUTED))
		return
	var mine: VBoxContainer = _card(body)
	mine.add_child(_label(_t("leaderboard_me", {"score": UIKit.amount(int(board.me.score), DataCatalog.locale)}), UIKit.NAME, UIKit.INK, "display"))
	var list: VBoxContainer = _card(body)
	var first: bool = true
	for entry in board.entries:
		if not first: list.add_child(UIKit.divider())
		first = false
		var line: HBoxContainer = UIKit.row(UIKit.M)
		list.add_child(line)
		var rank: Label = _label(str(int(entry.rank)), UIKit.NAME, UIKit.BRASS_DARK if int(entry.rank) > 3 else UIKit.RED, "display")
		rank.custom_minimum_size = Vector2(64, 0)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_child(rank)
		var name_label: Label = _label(str(entry.display_name), UIKit.BODY, UIKit.INK, "bold")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var score: Label = _label(_money(int(entry.score)), UIKit.BODY, UIKit.INK, "number")
		score.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.add_child(score)

func _on_board(result: Dictionary) -> void:
	board = result
	if active_tab == "leaderboard": _draw_board()

# --------------------------------------------------------------------------------------------
# Modals
# --------------------------------------------------------------------------------------------

func _new_modal(kind: String, title: String, picture: Texture2D = null) -> void:
	_close_modal(false)
	modal_kind = kind
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(UIKit.NIGHT, 0.62)
	modal.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, maxi(40, shell.get_theme_constant("margin_" + side) + UIKit.M))
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, maxi(96, shell.get_theme_constant("margin_" + side)))
	modal.add_child(margin)
	var panel: PanelContainer = UIKit.panel("card")
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(panel)
	var frame: VBoxContainer = UIKit.column(UIKit.S)
	panel.add_child(frame)
	var heading: Label = _label(title, 40, Color.WHITE, "display")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIKit.outlined(heading, 10, Color("5a1210"))
	var ribbon: PanelContainer = UIKit.panel("header", heading)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(ribbon)
	frame.add_child(UIKit.kilim())
	var scroll: ScrollContainer = ScrollContainer.new()
	modal_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = minf(get_viewport_rect().size.y - 360, 1100)
	frame.add_child(scroll)
	modal_body = UIKit.column(UIKit.GAP)
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(modal_body)
	if picture != null:
		var art: Control = UIKit.framed(picture, 150, "ring_paper", 0.17)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		modal_body.add_child(art)
	_fit_modal.call_deferred()

func _fit_modal() -> void:
	await get_tree().process_frame
	if is_instance_valid(modal_scroll) and is_instance_valid(modal_body):
		modal_scroll.custom_minimum_size.y = minf(modal_body.get_combined_minimum_size().y, get_viewport_rect().size.y - 420)

func _close_modal(next: bool = true) -> void:
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal = null
	modal_kind = ""
	song_buttons.clear()
	event_timer = null
	if next and not modal_queue.is_empty():
		var entry: Dictionary = modal_queue.pop_front()
		_show_queued.call_deferred(entry.kind, entry.data)

func _show_songs(index: int) -> void:
	if index >= GameState.simulation.tables.size(): return
	if index >= 0 and str(GameState.simulation.tables[index].get("guest_type", "")).is_empty():
		_close_modal()
		return
	modal_table = index
	_new_modal("song", _t("song_popup_title"))
	if index >= 0:
		var table: Dictionary = GameState.simulation.tables[index]
		var party: HBoxContainer = UIKit.row(UIKit.M)
		modal_body.add_child(party)
		var portrait_path: String = "res://assets/ui/guests/%s.png" % str(table.guest_type)
		if ResourceLoader.exists(portrait_path):
			var face: TextureRect = UIKit.picture(load(portrait_path), 0)
			face.custom_minimum_size = Vector2(200, 150)
			party.add_child(face)
		var about: VBoxContainer = UIKit.column(UIKit.XS)
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		about.alignment = BoxContainer.ALIGNMENT_CENTER
		party.add_child(about)
		about.add_child(_label(_t("table_party", {"name": _name("guest_types", table.guest_type), "count": _plural("guests", int(table.party_size))}), UIKit.NAME, UIKit.INK, "display"))
		var mood_line: HBoxContainer = UIKit.row(UIKit.S)
		about.add_child(mood_line)
		var rules: Dictionary = DataCatalog.data.economy.mood
		var face_name: String = "mood_happy" if table.mood >= float(rules.happy_at_or_above) else "mood_unhappy" if table.mood < float(rules.unhappy_below) else "mood_neutral"
		mood_line.add_child(UIKit.picture(_icon(face_name), 38))
		var meter: ProgressBar = UIKit.bar(Color("4fae6a") if face_name == "mood_happy" else UIKit.RED if face_name == "mood_unhappy" else UIKit.BRASS, 16, true)
		meter.max_value = float(rules.max)
		meter.value = float(table.mood)
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mood_line.add_child(meter)
		var mood_value: Label = _label(_table_mood(table), UIKit.TINY, UIKit.MUTED, "number")
		mood_value.autowrap_mode = TextServer.AUTOWRAP_OFF
		mood_line.add_child(mood_value)
		about.add_child(_label(_request_text(table), UIKit.SMALL, UIKit.GREEN, "bold"))
		about.add_child(_label(_order_text(table), UIKit.SMALL, UIKit.MUTED))
		if table.get("order_status") == "waiting":
			var serve: Button = UIKit.make_button(_t("serve"), func():
				if GameState.serve_table(index): _notice("notice_serving", {})
				_show_songs(index)
			, "red")
			serve.icon = load(SPRITES + "drinks/%s.svg" % str(table.get("order_item", "")))
			serve.expand_icon = true
			serve.add_theme_constant_override("icon_max_width", 72)
			for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				serve.add_theme_color_override(key, Color.WHITE)
			modal_body.add_child(serve)
	modal_body.add_child(_label(_t("song_popup_hint"), UIKit.SMALL, UIKit.MUTED))
	# Songs most tables are asking for come first, with the count beside the genre.
	var wanted: Dictionary = {}
	for table in GameState.simulation.tables:
		if str(table.get("guest_type", "")).is_empty(): continue
		var key: String = str(table.get("request_song", ""))
		if key.is_empty(): key = "genre:" + str(table.get("request_genre", ""))
		wanted[key] = int(wanted.get(key, 0)) + 1
	var songs: Array = GameState.known_songs().duplicate()
	var demand: Callable = func(song) -> int: return int(wanted.get(str(song.id), 0)) + int(wanted.get("genre:" + str(song.genre), 0))
	songs.sort_custom(func(a, b): return demand.call(a) > demand.call(b))
	for song in songs:
		var count: int = demand.call(song)
		var detail: String = _name("genres", song.genre)
		if count > 0: detail = _t("song_wanted", {"genre": detail, "count": count})
		var button: Button = UIKit.make_button(DataCatalog.localized(song.title) + "\n" + detail, func():
			GameState.play_song(song.id)
			_close_modal()
			_refresh()
		, "gold" if count > 0 else "paper", 28)
		button.custom_minimum_size.y = 124
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = GameState.simulation.song_remaining > 0
		var genre_color: Color = UIKit.GENRE_COLORS.get(str(song.genre), UIKit.BRASS)
		button.icon = UIKit.glyph("note")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 48)
		button.add_theme_constant_override("h_separation", UIKit.M)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, genre_color.darkened(0.15))
		button.add_theme_color_override("icon_disabled_color", Color(genre_color, 0.4))
		song_buttons.append(button)
		modal_body.add_child(button)
	modal_body.add_child(UIKit.make_button(_t("close"), func(): _close_modal(), "paper"))

func _enqueue(kind: String, data: Dictionary) -> void:
	if is_instance_valid(modal):
		if modal_kind == "song" or modal_kind == "reset": _close_modal(false)
		else:
			modal_queue.append({"kind": kind, "data": data})
			return
	_show_queued(kind, data)

func _show_queued(kind: String, data: Dictionary) -> void:
	match kind:
		"event": _show_event(data)
		"outcome":
			_new_modal(kind, _t("event_title"))
			modal_body.add_child(_label(DataCatalog.localized(data.get("text", {})), UIKit.BODY))
			modal_body.add_child(UIKit.make_button(_t("continue"), func(): _close_modal()))
		"offline": _show_offline(data)
		"conflict": _show_conflict(data)

func _on_event(event: Dictionary) -> void:
	_enqueue("event", event)

func _show_event(event: Dictionary) -> void:
	if GameState.simulation.active_event.is_empty(): return
	var art: Texture2D = UIKit.texture("events/" + str(event.get("id", ""))) if ResourceLoader.exists(UIKit.UI + "events/%s.svg" % str(event.get("id", ""))) else null
	_new_modal("event", DataCatalog.localized(event.get("name", {})), art)
	var text: Label = _label(DataCatalog.localized(event.get("text", {})), UIKit.BODY)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_body.add_child(text)
	var timer_row: HBoxContainer = UIKit.row(UIKit.S)
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.add_child(UIKit.tinted("clock", 32, UIKit.RED))
	event_timer = _label("", UIKit.SMALL, UIKit.RED, "label")
	event_timer.autowrap_mode = TextServer.AUTOWRAP_OFF
	timer_row.add_child(event_timer)
	modal_body.add_child(timer_row)
	var first: bool = true
	for choice in event.get("choices", []):
		var cost: int = GameState.event_choice_cost(choice)
		var label: String = DataCatalog.localized(choice.label)
		if cost > 0: label = _t("choice_cost", {"label": label, "amount": UIKit.amount(cost, DataCatalog.locale)})
		var button: Button = UIKit.make_button(label, func(): GameState.choose_event(choice.id), "gold" if first else "paper", 28)
		first = false
		button.custom_minimum_size.y = 112
		button.disabled = GameState.save.money < cost
		modal_body.add_child(button)
	_refresh()

func _on_outcome(outcome: Dictionary) -> void:
	if modal_kind == "event": _close_modal(false)
	_enqueue("outcome", outcome)

func _show_offline(result: Dictionary) -> void:
	_new_modal("offline", _t("offline_title"), _icon("coin"))
	var amount: Label = _label(_money(int(result.get("granted_amount", 0))), 72, UIKit.BRASS_DARK, "display")
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_body.add_child(amount)
	modal_body.add_child(_label(_t("offline_detail", {"minutes": int(result.get("counted_seconds", 0) / 60), "hours": result.get("cap_hours", 0)}), UIKit.BODY))
	modal_body.add_child(_label(_t("offline_server") if result.get("source", "local") == "server" else _t("offline_local"), UIKit.SMALL, UIKit.MUTED))
	if result.get("capped", false): modal_body.add_child(_label(_t("offline_cap"), UIKit.SMALL, UIKit.BRASS_DARK, "bold"))
	modal_body.add_child(UIKit.make_button(_t("continue"), func(): _close_modal()))

func _show_conflict(server: Dictionary) -> void:
	_new_modal("conflict", _t("conflict_title"))
	modal_body.add_child(_label(_t("conflict_body"), UIKit.BODY))
	modal_body.add_child(_label(_t("conflict_money", {"local": UIKit.amount(int(GameState.save.money), DataCatalog.locale), "cloud": UIKit.amount(int(server.get("save", {}).get("money", 0)), DataCatalog.locale)}), UIKit.SMALL, UIKit.BRASS_DARK, "bold"))
	modal_body.add_child(UIKit.make_button(_t("keep_device"), func():
		ApiClient.resolve_conflict(true)
		_close_modal()
	))
	modal_body.add_child(UIKit.make_button(_t("keep_cloud"), func():
		ApiClient.resolve_conflict(false)
		_close_modal()
		_open_tab(active_tab)
	, "paper"))

func _confirm_reset() -> void:
	_new_modal("reset", _t("reset_title"))
	modal_body.add_child(_label(_t("reset_body"), UIKit.BODY))
	modal_body.add_child(UIKit.make_button(_t("reset"), func():
		SaveSystem.reset_progress()
		_close_modal()
		_open_tab("floor")
	, "red"))
	modal_body.add_child(UIKit.make_button(_t("cancel"), func(): _close_modal(), "paper"))

# --------------------------------------------------------------------------------------------
# A new venue opens: lamp rays, the building, its name, and the doors.
# --------------------------------------------------------------------------------------------

func _celebrate(venue_id: String) -> void:
	if is_instance_valid(celebration):
		celebration.queue_free()
	var venue: Dictionary = DataCatalog.get_item("venues", venue_id)
	celebration = Control.new()
	celebration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	celebration.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(celebration)
	var night: ColorRect = ColorRect.new()
	night.color = Color(UIKit.NIGHT, 0.94)
	night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	celebration.add_child(night)
	var stars: TextureRect = TextureRect.new()
	stars.texture = UIKit.texture("night_tile")
	stars.stretch_mode = TextureRect.STRETCH_TILE
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	celebration.add_child(stars)
	var rays: Rays = Rays.new()
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rays.offset_bottom = -get_viewport_rect().size.y * 0.25
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	celebration.add_child(rays)
	var center: VBoxContainer = UIKit.column(UIKit.M)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.offset_left = 72
	center.offset_right = -72
	celebration.add_child(center)
	var stamp: Label = _label(_t("venue_opened"), 30, Color.WHITE, "label")
	stamp.autowrap_mode = TextServer.AUTOWRAP_OFF
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.outlined(stamp, 8, Color("5a1210"))
	var ribbon: PanelContainer = UIKit.panel("header", stamp)
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(ribbon)
	var art: TextureRect = UIKit.picture(load("res://assets/ui/venues/%s.png" % venue_id), 0)
	art.custom_minimum_size = Vector2(0, 560)
	art.pivot_offset = Vector2(get_viewport_rect().size.x / 2.0 - 72, 280)
	center.add_child(art)
	var title: Label = _label(DataCatalog.localized(venue.get("name", {})), 120, UIKit.GOLD, "display")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.outlined(title, 18)
	center.add_child(title)
	var line: Label = _label(_t("venue_opened_body", {"name": DataCatalog.localized(venue.get("name", {}))}), 34, Color.WHITE, "bold")
	UIKit.outlined(line, 8)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(line)
	var stats: Label = _label(_venue_stats(venue), UIKit.SMALL, Color(UIKit.CREAM, 0.7))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(stats)
	var enter: Button = UIKit.make_button(_t("enter_venue"), _end_celebration, "gold", 38)
	enter.custom_minimum_size = Vector2(520, 116)
	enter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(enter)
	celebration.modulate.a = 0.0
	art.scale = Vector2(0.6, 0.6)
	var tween: Tween = celebration.create_tween()
	tween.tween_property(celebration, "modulate:a", 1.0, 0.35)
	tween.parallel().tween_property(art, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	EventBus.audio_requested.emit("venue_opened")

func _end_celebration() -> void:
	if not is_instance_valid(celebration): return
	var leaving: Control = celebration
	celebration = null
	floor_view.release_flight()
	var tween: Tween = leaving.create_tween()
	tween.tween_property(leaving, "modulate:a", 0.0, 0.4)
	tween.tween_callback(leaving.queue_free)

func _notice(key: String, args: Dictionary) -> void:
	toast.text = _t(key, args)
	toast_panel.visible = true
	toast_seconds = 4.0

func _silent_audio_hook(_cue: String) -> void:
	# Replace with pooled AudioStreamPlayers. No recordings ship in this slice.
	pass

func _rebuild() -> void:
	var tab: String = active_tab
	var pending: String = modal_kind
	_close_modal(false)
	_clear(self)
	celebration = null
	_build_shell()
	_open_tab(tab)
	_safe_area()
	if pending == "event": _show_event(GameState.simulation.active_event)

func _process(delta: float) -> void:
	last_refresh += delta
	if last_refresh >= 0.25:
		last_refresh = 0
		_refresh()
	# The road sign glows while the next venue is affordable.
	pulse_time += delta
	if is_instance_valid(goal_button):
		goal_button.modulate = Color(1, 1, 1) if not goal_ready else Color(1, 1, 1).lerp(Color(1.3, 1.2, 0.9), 0.5 + 0.5 * sin(pulse_time * 4.0))
	if toast_seconds > 0:
		toast_seconds -= delta
		if toast_seconds <= 0:
			toast.text = ""
			toast_panel.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveSystem.save_now()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(celebration): _end_celebration()
		elif is_instance_valid(modal) and modal_kind not in ["event", "conflict"]: _close_modal()
		elif not is_instance_valid(modal): _open_tab("floor")
