extends Control
## Presentation only: actions enter GameState; all balance lives in the catalog.
const BG = Color("1b2a44")
const PANEL = Color("fff6df")
const CARD = Color("fffdf6")
const INK = Color("2b1d14")
const MUTED = Color("8a6f55")
const GOLD = Color("d9771e")
const GREEN = Color("2f9a5a")
const RED = Color("d6453a")
const YELLOW = Color("ffc83d")
const LIME = Color("6fd06a")
const BODY_FONT = preload("res://assets/fonts/Baloo2-SemiBold.ttf")
const BOLD_FONT = preload("res://assets/fonts/Baloo2-ExtraBold.ttf")
const FloorView = preload("res://scripts/ui/floor_view.gd")
const SPRITES = "res://assets/sprites/"
const GENRE_COLORS = {"starogradske": Color("ffb43d"), "tamburica": Color("3ec9a7"), "izvorna": Color("ff6a5a"), "narodnjaci": Color("b77cff")}
var shell: MarginContainer
var body: VBoxContainer
var floor_view: Control
var floor_spacer: Control
var dim_backdrop: ColorRect
var sheet: PanelContainer
var mood_icon: TextureRect
var money_icon: TextureRect
var hud_panel: PanelContainer
var nav_panel: PanelContainer
var toast_panel: PanelContainer
var content_scroll: ScrollContainer
var money_label: Label
var mood_label: Label
var guest_label: Label
var venue_label: Label
var mood_bar: ProgressBar
var status_label: Label
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
	var theme_resource: Theme = Theme.new()
	theme_resource.default_font = BODY_FONT
	theme_resource.default_font_size = 30
	theme_resource.set_font("font", "Button", BOLD_FONT)
	theme_resource.set_color("font_color", "Label", INK)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme_resource.set_color(key, "Button", INK)
	theme_resource.set_color("font_disabled_color", "Button", MUTED)
	theme_resource.set_color("font_color", "CheckButton", INK)
	theme_resource.set_color("font_hover_color", "CheckButton", INK)
	theme_resource.set_color("font_pressed_color", "CheckButton", INK)
	theme_resource.set_stylebox("normal", "Button", _box(YELLOW, 24))
	theme_resource.set_stylebox("hover", "Button", _box(YELLOW.lightened(0.15), 24))
	theme_resource.set_stylebox("pressed", "Button", _box(YELLOW.darkened(0.12), 24, INK, false))
	theme_resource.set_stylebox("disabled", "Button", _box(Color("e6dcc6"), 24, MUTED.lightened(0.2), false))
	theme_resource.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		theme_resource.set_stylebox(state, "CheckButton", _box(CARD, 24))
	for icon_name in ["checked", "checked_mirrored"]:
		theme_resource.set_icon(icon_name, "CheckButton", _icon("toggle_on"))
	for icon_name in ["unchecked", "unchecked_mirrored"]:
		theme_resource.set_icon(icon_name, "CheckButton", _icon("toggle_off"))
	theme_resource.set_constant("separation", "VBoxContainer", 18)
	theme_resource.set_constant("separation", "HBoxContainer", 16)
	var bar_back: StyleBoxFlat = _box(Color("e8d9b8"), 10, INK, false)
	bar_back.set_border_width_all(3)
	bar_back.set_content_margin_all(0)
	var bar_fill: StyleBoxFlat = _box(Color("3ec9a7"), 10, Color.TRANSPARENT, false)
	bar_fill.set_border_width_all(0)
	bar_fill.set_content_margin_all(0)
	theme_resource.set_stylebox("background", "ProgressBar", bar_back)
	theme_resource.set_stylebox("fill", "ProgressBar", bar_fill)
	var scroll: StyleBoxFlat = _box(Color(INK, 0.25), 6, Color.TRANSPARENT, false)
	scroll.set_content_margin_all(4)
	theme_resource.set_stylebox("grabber", "VScrollBar", scroll)
	theme_resource.set_stylebox("grabber_highlight", "VScrollBar", scroll)
	theme_resource.set_stylebox("grabber_pressed", "VScrollBar", scroll)
	theme_resource.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	theme = theme_resource

## Cartoon box: flat colour, thick dark outline and a solid drop shadow underneath.
func _box(color: Color, radius: int = 24, border: Color = INK, shadow: bool = true) -> StyleBoxFlat:
	var result: StyleBoxFlat = StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.set_border_width_all(4)
	result.border_color = border
	if shadow:
		result.shadow_color = Color(INK, 0.35)
		result.shadow_offset = Vector2(0, 6)
		result.shadow_size = 1
	result.content_margin_left = 26
	result.content_margin_right = 26
	result.content_margin_top = 18
	result.content_margin_bottom = 20
	return result

func _label(value: String, font_size: int = 30, color: Color = INK) -> Label:
	var result: Label = Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	if font_size >= 34:
		result.add_theme_font_override("font", BOLD_FONT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _button(value: String, action: Callable, accent: bool = false) -> Button:
	var result: Button = Button.new()
	result.text = value
	result.custom_minimum_size.y = 112
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(action)
	if accent:
		result.add_theme_stylebox_override("normal", _box(LIME, 24))
		result.add_theme_stylebox_override("hover", _box(LIME.lightened(0.15), 24))
		result.add_theme_stylebox_override("pressed", _box(LIME.darkened(0.12), 24, INK, false))
	return result

func _panel(parent: Node, color: Color = CARD) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(color))
	# Cards must not swallow drags, or lists cannot be scrolled by touching a card.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(column)
	return column

func _t(key: String, args: Dictionary = {}) -> String:
	return DataCatalog.text(key, args)

func _name(collection: String, id: String, field: String = "name") -> String:
	return DataCatalog.localized(DataCatalog.get_item(collection, id).get(field, {}))

func _icon(name: String) -> Texture2D:
	return load(SPRITES + "icons/" + name + ".svg")

func _icon_rect(name: String, side: float) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = _icon(name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _icon_button(name: String, action: Callable, tint: bool = true) -> Button:
	var button: Button = Button.new()
	button.icon = _icon(name)
	button.expand_icon = true
	button.custom_minimum_size = Vector2(104, 104)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_constant_override("icon_max_width", 64)
	for state in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = _box(YELLOW if state != "pressed" else YELLOW.darkened(0.12), 52, INK, state != "pressed")
		style.set_content_margin_all(18)
		button.add_theme_stylebox_override(state, style)
	if tint:
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, INK)
	button.pressed.connect(action)
	return button

func _pill(content: Control, color: Color = PANEL) -> PanelContainer:
	var pill: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = _box(color, 40)
	style.content_margin_left = 12
	style.content_margin_right = 22
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(content)
	return pill

func _build_shell() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	floor_view = FloorView.new()
	add_child(floor_view)
	floor_view.table_tapped.connect(_on_table_tapped)
	floor_view.stage_tapped.connect(func(): _show_songs(-1))
	floor_view.slot_tapped.connect(func(_index): _open_tab("upgrades"))
	floor_view.money_target = func() -> Vector2: return money_icon.get_global_rect().get_center() if is_instance_valid(money_icon) else Vector2.ZERO
	# Other screens sit on a sheet over the still-running kafana, dimmed and not clickable.
	dim_backdrop = ColorRect.new()
	dim_backdrop.color = Color(0.06, 0.09, 0.16, 0.62)
	dim_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim_backdrop)
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 16)
	shell.add_child(column)
	hud_panel = PanelContainer.new()
	hud_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hud_panel)
	var hud: VBoxContainer = VBoxContainer.new()
	hud.add_theme_constant_override("separation", 12)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_panel.add_child(hud)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	for key in ["money", "mood", "guests"]:
		var group: HBoxContainer = HBoxContainer.new()
		group.add_theme_constant_override("separation", 8)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon: TextureRect = _icon_rect({"money": "coin", "mood": "mood_neutral", "guests": "guests_dark"}[key], 62)
		group.add_child(icon)
		var number: Label = _label("", 36, INK)
		number.autowrap_mode = TextServer.AUTOWRAP_OFF
		number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		group.add_child(number)
		var holder: Control = group
		if key == "mood":
			var stack: VBoxContainer = VBoxContainer.new()
			stack.add_theme_constant_override("separation", 0)
			stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
			group.remove_child(number)
			stack.add_child(number)
			mood_bar = ProgressBar.new()
			mood_bar.custom_minimum_size = Vector2(110, 16)
			mood_bar.show_percentage = false
			mood_bar.min_value = DataCatalog.data.economy.mood.min
			mood_bar.max_value = DataCatalog.data.economy.mood.max
			mood_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stack.add_child(mood_bar)
			group.add_child(stack)
			number.add_theme_font_size_override("font_size", 28)
		var pill: PanelContainer = _pill(holder)
		pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pill.size_flags_stretch_ratio = 1.6 if key == "money" else 1.0
		top.add_child(pill)
		match key:
			"money":
				money_label = number
				money_icon = icon
			"mood":
				mood_label = number
				mood_icon = icon
			"guests": guest_label = number
	top.add_child(_icon_button("trophy", func(): _open_tab("leaderboard"), false))
	top.add_child(_icon_button("gear", func(): _open_tab("settings")))
	var ribbon: HBoxContainer = HBoxContainer.new()
	ribbon.alignment = BoxContainer.ALIGNMENT_CENTER
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ribbon)
	venue_label = _label("", 26, Color.WHITE)
	venue_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	venue_label.add_theme_font_override("font", BOLD_FONT)
	venue_label.add_theme_color_override("font_outline_color", INK)
	venue_label.add_theme_constant_override("outline_size", 10)
	ribbon.add_child(venue_label)
	status_label = _label("", 20, Color(1, 1, 1, 0.75))
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_label.add_theme_color_override("font_outline_color", INK)
	status_label.add_theme_constant_override("outline_size", 6)
	ribbon.add_child(status_label)
	sheet = PanelContainer.new()
	var sheet_style: StyleBoxFlat = _box(PANEL, 36)
	sheet_style.content_margin_left = 22
	sheet_style.content_margin_right = 14
	sheet_style.content_margin_top = 20
	sheet_style.content_margin_bottom = 18
	sheet.add_theme_stylebox_override("panel", sheet_style)
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(sheet)
	content_scroll = ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(content_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(body)
	floor_spacer = Control.new()
	floor_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	floor_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(floor_spacer)
	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", _box(PANEL, 34))
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	column.add_child(toast_panel)
	toast = _label("", 28, INK)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_panel.add_child(toast)
	nav_panel = PanelContainer.new()
	var nav_style: StyleBoxFlat = _box(PANEL, 36)
	nav_style.set_content_margin_all(10)
	nav_panel.add_theme_stylebox_override("panel", nav_style)
	column.add_child(nav_panel)
	var nav: HBoxContainer = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	nav_panel.add_child(nav)
	for key in ["floor", "band", "menu", "upgrades", "venues"]:
		var button: Button = _button(_t("nav_" + key), _open_tab.bind(key))
		button.icon = _icon("nav_" + key)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.clip_text = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 132)
		button.add_theme_font_size_override("font_size", 22)
		button.add_theme_constant_override("icon_max_width", 58)
		nav.add_child(button)
		nav_buttons[key] = button

func _safe_area() -> void:
	var left: int = 28
	var right: int = 28
	var top: int = 26
	var bottom: int = 24
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
	# The world camera keeps the playable area between the HUD and the navigation bar.
	if is_instance_valid(floor_view) and is_instance_valid(nav_panel) and is_instance_valid(hud_panel):
		var top: float = hud_panel.get_global_rect().end.y
		var bottom: float = get_viewport_rect().size.y - nav_panel.get_global_rect().position.y
		floor_view.set_insets(top, bottom)

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _open_tab(key: String) -> void:
	active_tab = key
	_clear(body)
	purchase_buttons.clear()
	content_scroll.scroll_vertical = 0
	var on_floor: bool = key == "floor"
	floor_spacer.visible = on_floor
	sheet.visible = not on_floor
	dim_backdrop.visible = not on_floor
	for nav in nav_buttons:
		var active: bool = key == nav
		var color: Color = INK if active else MUTED
		var button: Button = nav_buttons[nav]
		button.add_theme_color_override("font_color", color)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, color)
		var style: StyleBoxFlat = _box(YELLOW, 26, INK, false) if active else _box(Color(0, 0, 0, 0), 26, Color.TRANSPARENT, false)
		style.set_content_margin_all(8)
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, style)
	match key:
		"floor": floor_view.refresh()
		"band": _band()
		"menu": _menu()
		"upgrades": _upgrades()
		"venues": _venues()
		"settings": _settings()
		"leaderboard":
			_draw_board()
			ApiClient.request_leaderboard()
	_refresh()

func _heading(title: String, subtitle: String) -> void:
	body.add_child(_label(title, 44))
	body.add_child(_label(subtitle, 27, MUTED))

func _on_table_tapped(index: int) -> void:
	if index >= GameState.simulation.tables.size(): return
	var table: Dictionary = GameState.simulation.tables[index]
	if str(table.get("guest_type", "")).is_empty(): return
	if str(table.get("order_status", "")) == "waiting":
		if GameState.serve_table(index): _notice("notice_serving", {})
		return
	_show_songs(index)

func _refresh() -> void:
	if not is_instance_valid(money_label): return
	money_label.text = _t("money_amount", {"amount": int(GameState.save.money)})
	var mood: float = GameState.room_mood()
	mood_label.text = str(roundi(mood))
	var mood_rules: Dictionary = DataCatalog.data.economy.mood
	mood_icon.texture = _icon("mood_happy" if mood >= float(mood_rules.happy_at_or_above) else "mood_unhappy" if mood < float(mood_rules.unhappy_below) else "mood_neutral")
	guest_label.text = str(GameState.guest_count())
	mood_bar.value = mood
	venue_label.text = DataCatalog.localized(GameState.venue().name).to_upper() + " · " + DataCatalog.localized(GameState.band().name)
	status_label.text = _t("sync_" + ApiClient.status)
	for entry in purchase_buttons:
		if is_instance_valid(entry.button): entry.button.disabled = not entry.allowed.call()
	for button in song_buttons:
		if is_instance_valid(button): button.disabled = GameState.simulation.song_remaining > 0
	if modal_kind == "event" and is_instance_valid(event_timer):
		if GameState.simulation.active_event.is_empty(): _close_modal()
		else: event_timer.text = _t("event_timeout", {"seconds": ceili(GameState.simulation.event_remaining)})

func _table_mood(table: Dictionary) -> String:
	var key: String = "mood_icon_neutral"
	if table.mood >= DataCatalog.data.economy.mood.happy_at_or_above: key = "mood_icon_happy"
	elif table.mood < DataCatalog.data.economy.mood.unhappy_below: key = "mood_icon_unhappy"
	return _t("dancing") if table.get("dancing", false) else _t(key) + "  " + _t("mood_value", {"value": roundi(table.mood)})

func _request_text(table: Dictionary) -> String:
	var song: String = str(table.get("request_song", ""))
	var genre: String = str(table.get("request_genre", ""))
	if song.is_empty() and genre.is_empty(): return _t("no_request")
	return _t("request", {"song": _name("songs", song, "title") if not song.is_empty() else _name("genres", genre)})

func _order_text(table: Dictionary) -> String:
	var status: String = table.get("order_status", "served")
	return _t("order_" + status, {"item": _name("drinks", table.get("order_item", "")), "seconds": ceili(table.get("prep_remaining", 0))})

func _purchase(kind: String, id: String) -> void:
	var ok: bool = false
	match kind:
		"band": ok = GameState.buy_band(id)
		"song": ok = GameState.unlock_song(id)
		"upgrade": ok = GameState.buy_upgrade(id)
		"venue": ok = GameState.buy_venue(id)
	if ok: _notice("notice_purchase", {})
	if ok: SaveSystem.save_now()
	var scroll_position: int = content_scroll.scroll_vertical
	_open_tab(active_tab)
	content_scroll.set_deferred("scroll_vertical", scroll_position)

func _band() -> void:
	_heading(_t("nav_band"), _t("band_hint"))
	for band in DataCatalog.items("band_levels"):
		var card: VBoxContainer = _panel(body)
		card.add_child(_label(DataCatalog.localized(band.name), 36, GOLD))
		card.add_child(_label(DataCatalog.localized(band.description), 27, MUTED))
		card.add_child(_label(_t("band_stats", {"members": band.members, "upkeep": int(band.upkeep_per_hour)}), 24))
		var owned: bool = band.order <= GameState.band().order
		var label: String = _t("current") if band.id == GameState.save.band_level else _t("owned") if owned else _t("unlock", {"amount": int(band.unlock_cost)})
		var button: Button = _button(label, _purchase.bind("band", band.id), not owned)
		button.disabled = owned or GameState.save.money < band.unlock_cost or GameState.venue().order < DataCatalog.get_item("venues", band.required_venue).order
		purchase_buttons.append({"button": button, "allowed": func(): return GameState.purchase_reason("band_levels", band.id).is_empty()})
		card.add_child(button)
	body.add_child(_label(_t("known_songs"), 26, GOLD))
	for song in DataCatalog.items("songs"):
		var card: VBoxContainer = _panel(body)
		card.add_child(_label(DataCatalog.localized(song.title), 33))
		card.add_child(_label(_name("genres", song.genre) + " · " + _t("requires_band", {"name": _name("band_levels", song.min_band_level)}), 24, MUTED))
		var owned: bool = song.id in GameState.save.unlocked_songs
		var button: Button = _button(_t("owned") if owned else _t("unlock", {"amount": int(song.unlock_cost)}), _purchase.bind("song", song.id))
		button.disabled = owned or GameState.save.money < song.unlock_cost or GameState.band().order < DataCatalog.get_item("band_levels", song.min_band_level).order
		purchase_buttons.append({"button": button, "allowed": func(): return GameState.purchase_reason("songs", song.id).is_empty()})
		card.add_child(button)

func _menu() -> void:
	_heading(_t("nav_menu"), _t("menu_hint"))
	for item in DataCatalog.items("drinks"):
		var row: HBoxContainer = HBoxContainer.new()
		_panel(body).add_child(row)
		var picture: TextureRect = TextureRect.new()
		picture.texture = load(SPRITES + "drinks/%s.svg" % str(item.id))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(150, 150)
		row.add_child(picture)
		var card: VBoxContainer = VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		card.add_child(_label(_t(item.kind), 20, GOLD))
		card.add_child(_label(DataCatalog.localized(item.name), 36))
		card.add_child(_label(_t("menu_price", {"price": int(item.price), "cost": int(item.cost), "seconds": int(item.prep_seconds)}), 26, MUTED))
		if DataCatalog.get_item("venues", item.unlock_venue).order > GameState.venue().order:
			card.add_child(_label(_t("requires", {"name": _name("venues", item.unlock_venue)}), 25, RED))

func _upgrades() -> void:
	_heading(_t("nav_upgrades"), _t("upgrades_hint"))
	for upgrade in DataCatalog.items("upgrades"):
		var level: int = int(GameState.save.upgrades.get(upgrade.id, 0))
		var cost: int = Economy.upgrade_cost(upgrade.id, level)
		var card: VBoxContainer = _panel(body)
		card.add_child(_label(DataCatalog.localized(upgrade.name), 36, GOLD))
		card.add_child(_label(DataCatalog.localized(upgrade.description), 27, MUTED))
		card.add_child(_label(_t("level", {"level": level, "max": int(upgrade.max_level)}), 25))
		var locked: bool = GameState.venue().order < DataCatalog.get_item("venues", upgrade.unlock_venue).order
		if locked: card.add_child(_label(_t("requires", {"name": _name("venues", upgrade.unlock_venue)}), 24, RED))
		var button: Button = _button(_t("max_level") if level >= upgrade.max_level else _t("buy", {"amount": cost}), _purchase.bind("upgrade", upgrade.id), true)
		button.disabled = locked or level >= upgrade.max_level or GameState.save.money < cost
		purchase_buttons.append({"button": button, "allowed": func(): return GameState.purchase_reason("upgrades", upgrade.id).is_empty()})
		card.add_child(button)

func _venues() -> void:
	_heading(_t("nav_venues"), _t("venues_hint"))
	for venue in DataCatalog.items("venues"):
		var card: VBoxContainer = _panel(body)
		card.add_child(_label(DataCatalog.localized(venue.name), 42, GOLD))
		card.add_child(_label(DataCatalog.localized(venue.description), 28, MUTED))
		card.add_child(_label(_t("venue_stats", {"tables": int(venue.base_tables), "max": int(venue.max_tables), "rate": int(venue.offline_income_per_minute)}), 25))
		var owned: bool = venue.order <= GameState.venue().order
		var button: Button = _button(_t("current") if venue.id == GameState.save.venue else _t("owned") if owned else _t("unlock", {"amount": int(venue.unlock_cost)}), _purchase.bind("venue", venue.id), not owned)
		button.disabled = owned or GameState.save.money < venue.unlock_cost
		purchase_buttons.append({"button": button, "allowed": func(): return GameState.purchase_reason("venues", venue.id).is_empty()})
		card.add_child(button)

func _settings() -> void:
	_heading(_t("settings"), _t("mock_label") if DataCatalog.settings.get("mock_enabled", true) else _t("offline_label"))
	for key in ["sound", "music"]:
		var toggle: CheckButton = CheckButton.new()
		toggle.text = _t(key)
		toggle.custom_minimum_size.y = 120
		toggle.button_pressed = SaveSystem.settings.get(key, true)
		toggle.toggled.connect(func(value): SaveSystem.set_setting(key, value))
		body.add_child(toggle)
	body.add_child(_label(_t("sound_stub"), 26, MUTED))
	body.add_child(_label(_t("language"), 30, GOLD))
	for locale in ["sr", "en"]:
		var button: Button = _button(_t("locale_" + locale), func(): SaveSystem.set_setting("language", locale))
		button.disabled = DataCatalog.locale == locale
		body.add_child(button)
	body.add_child(_button(_t("save"), func(): SaveSystem.save_now(); _notice("notice_saved", {})))
	if DataCatalog.settings.get("mock_enabled", true): body.add_child(_button(_t("demo_conflict"), func(): ApiClient.mock_conflict()))
	body.add_child(_button(_t("reset"), _confirm_reset))

func _draw_board() -> void:
	_clear(body)
	_heading(_t("leaderboard"), _t("mock_label") if DataCatalog.settings.get("mock_enabled", true) else _t("offline_label"))
	if board.is_empty():
		body.add_child(_label(_t("loading"), 30, MUTED))
		return
	if board.has("error") or not board.has("entries"):
		body.add_child(_label(_t("leaderboard_offline"), 30, MUTED))
		return
	body.add_child(_label(_t("leaderboard_hint", {"week": board.week_id}), 29, GOLD))
	body.add_child(_label(_t("leaderboard_me", {"score": int(board.me.score)}), 32))
	for entry in board.entries:
		_panel(body).add_child(_label(_t("leaderboard_row", {"rank": int(entry.rank), "name": entry.display_name, "score": int(entry.score)}), 30))

func _on_board(result: Dictionary) -> void:
	board = result
	if active_tab == "leaderboard": _draw_board()

func _new_modal(kind: String, title: String) -> void:
	_close_modal(false)
	modal_kind = kind
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.08, 0.14, 0.66)
	modal.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, maxi(58, shell.get_theme_constant("margin_" + side)))
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, maxi(100, shell.get_theme_constant("margin_" + side)))
	modal.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _box(PANEL, 40))
	margin.add_child(panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	modal_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = minf(get_viewport_rect().size.y - 240, 1150)
	panel.add_child(scroll)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(modal_body)
	modal_body.add_child(_label(title, 43, GOLD))
	_fit_modal.call_deferred()

func _fit_modal() -> void:
	await get_tree().process_frame
	if is_instance_valid(modal_scroll) and is_instance_valid(modal_body):
		modal_scroll.custom_minimum_size.y = minf(modal_body.get_combined_minimum_size().y, get_viewport_rect().size.y - 280)

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
		modal_body.add_child(_label(_t("table_party", {"name": _name("guest_types", table.guest_type), "count": int(table.party_size)}), 31))
		modal_body.add_child(_label(_table_mood(table), 29, RED if table.mood < DataCatalog.data.economy.mood.unhappy_below else GREEN))
		modal_body.add_child(_label(_request_text(table), 31, GREEN))
		modal_body.add_child(_label(_order_text(table), 27, MUTED))
		if table.get("order_status") == "waiting":
			var serve: Button = _button(_t("serve"), func():
				if GameState.serve_table(index): _notice("notice_serving", {})
				_show_songs(index)
			, true)
			serve.icon = load(SPRITES + "drinks/%s.svg" % str(table.get("order_item", "")))
			serve.expand_icon = true
			serve.add_theme_constant_override("icon_max_width", 84)
			modal_body.add_child(serve)
	modal_body.add_child(_label(_t("song_popup_hint"), 27, MUTED))
	modal_body.add_child(_label(_t("known_songs"), 23, GOLD))
	for song in GameState.known_songs():
		var button: Button = _button(DataCatalog.localized(song.title) + "\n" + _name("genres", song.genre), func():
			GameState.play_song(song.id)
			_close_modal()
			_refresh()
		, true)
		button.custom_minimum_size.y = 140
		button.disabled = GameState.simulation.song_remaining > 0
		var genre_color: Color = GENRE_COLORS.get(str(song.genre), GOLD)
		button.icon = _icon("note")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 48)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, genre_color)
		button.add_theme_color_override("icon_disabled_color", Color(genre_color, 0.4))
		song_buttons.append(button)
		modal_body.add_child(button)
	modal_body.add_child(_button(_t("close"), func(): _close_modal()))

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
			modal_body.add_child(_label(DataCatalog.localized(data.get("text", {})), 33))
			modal_body.add_child(_button(_t("continue"), func(): _close_modal(), true))
		"offline": _show_offline(data)
		"conflict": _show_conflict(data)

func _on_event(event: Dictionary) -> void:
	_enqueue("event", event)

func _show_event(event: Dictionary) -> void:
	if GameState.simulation.active_event.is_empty(): return
	_new_modal("event", DataCatalog.localized(event.get("name", {})))
	modal_body.add_child(_label(DataCatalog.localized(event.get("text", {})), 32))
	event_timer = _label("", 27, RED)
	modal_body.add_child(event_timer)
	for choice in event.get("choices", []):
		var cost: int = GameState.event_choice_cost(choice)
		var label: String = DataCatalog.localized(choice.label)
		if cost > 0: label = _t("choice_cost", {"label": label, "amount": cost})
		var button: Button = _button(label, func(): GameState.choose_event(choice.id), true)
		button.custom_minimum_size.y = 140
		button.disabled = GameState.save.money < cost
		modal_body.add_child(button)
	_refresh()

func _on_outcome(outcome: Dictionary) -> void:
	if modal_kind == "event": _close_modal(false)
	_enqueue("outcome", outcome)

func _show_offline(result: Dictionary) -> void:
	_new_modal("offline", _t("offline_title"))
	modal_body.add_child(_label(_t("money_amount", {"amount": int(result.get("granted_amount", 0))}), 66, GREEN))
	modal_body.add_child(_label(_t("offline_detail", {"minutes": int(result.get("counted_seconds", 0) / 60), "hours": result.get("cap_hours", 0)}), 30))
	modal_body.add_child(_label(_t("offline_server") if result.get("source", "local") == "server" else _t("offline_local"), 26, MUTED))
	if result.get("capped", false): modal_body.add_child(_label(_t("offline_cap"), 27, GOLD))
	modal_body.add_child(_button(_t("continue"), func(): _close_modal(), true))

func _show_conflict(server: Dictionary) -> void:
	_new_modal("conflict", _t("conflict_title"))
	modal_body.add_child(_label(_t("conflict_body"), 31))
	modal_body.add_child(_label(_t("conflict_money", {"local": int(GameState.save.money), "cloud": int(server.get("save", {}).get("money", 0))}), 29, GOLD))
	modal_body.add_child(_button(_t("keep_device"), func():
		ApiClient.resolve_conflict(true)
		_close_modal()
	, true))
	modal_body.add_child(_button(_t("keep_cloud"), func():
		ApiClient.resolve_conflict(false)
		_close_modal()
		_open_tab(active_tab)
	))

func _confirm_reset() -> void:
	_new_modal("reset", _t("reset_title"))
	modal_body.add_child(_label(_t("reset_body"), 31))
	modal_body.add_child(_button(_t("reset"), func():
		SaveSystem.reset_progress()
		_close_modal()
		_open_tab("floor")
	))
	modal_body.add_child(_button(_t("cancel"), func(): _close_modal(), true))

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
	_build_shell()
	_open_tab(tab)
	_safe_area()
	if pending == "event": _show_event(GameState.simulation.active_event)

func _process(delta: float) -> void:
	last_refresh += delta
	if last_refresh >= 0.25:
		last_refresh = 0
		_refresh()
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
		if is_instance_valid(modal) and modal_kind not in ["event", "conflict"]: _close_modal()
		elif not is_instance_valid(modal): _open_tab("floor")
