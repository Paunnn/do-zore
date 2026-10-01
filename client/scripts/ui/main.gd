extends Control
## Presentation only: actions enter GameState; all balance lives in the catalog.
const BG = Color("10191e")
const PANEL = Color("1c2a2e")
const INK = Color("f4eedc")
const MUTED = Color("9fb3ad")
const GOLD = Color("eab575")
const GREEN = Color("72cbb6")
const RED = Color("ed8c7a")
var shell: MarginContainer
var body: VBoxContainer
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
var table_widgets: Array = []
var table_grid: GridContainer
var stage_song: Label
var stage_remaining: Label
var stage_band: Label
var night_label: Label
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
	theme_resource.default_font_size = 30
	theme_resource.set_color("font_color", "Label", INK)
	theme_resource.set_color("font_color", "Button", INK)
	theme_resource.set_color("font_hover_color", "Button", INK)
	theme_resource.set_color("font_disabled_color", "Button", MUTED.darkened(0.2))
	theme_resource.set_stylebox("normal", "Button", _box(PANEL.lightened(0.04), 20, PANEL.lightened(0.17)))
	theme_resource.set_stylebox("hover", "Button", _box(PANEL.lightened(0.14), 20, GOLD))
	theme_resource.set_stylebox("pressed", "Button", _box(Color("375248"), 20, GREEN))
	theme_resource.set_stylebox("disabled", "Button", _box(PANEL.darkened(0.12), 20, PANEL))
	theme_resource.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), 20, GOLD))
	theme_resource.set_constant("separation", "VBoxContainer", 22)
	theme_resource.set_constant("separation", "HBoxContainer", 18)
	for key in ["background", "fill"]:
		var bar_style: StyleBoxFlat = _box(BG if key == "background" else GREEN, 7)
		bar_style.set_content_margin_all(0)
		theme_resource.set_stylebox(key, "ProgressBar", bar_style)
	theme = theme_resource

func _box(color: Color, radius: int = 24, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var result: StyleBoxFlat = StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.set_border_width_all(2)
	result.border_color = border
	result.content_margin_left = 26
	result.content_margin_right = 26
	result.content_margin_top = 20
	result.content_margin_bottom = 20
	return result

func _label(value: String, font_size: int = 30, color: Color = INK) -> Label:
	var result: Label = Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
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
		result.add_theme_stylebox_override("normal", _box(Color("684d34"), 20, GOLD.darkened(0.3)))
		result.add_theme_color_override("font_color", INK)
	return result

func _panel(parent: Node, color: Color = PANEL) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(color))
	parent.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(column)
	return column

func _t(key: String, args: Dictionary = {}) -> String:
	return DataCatalog.text(key, args)

func _name(collection: String, id: String, field: String = "name") -> String:
	return DataCatalog.localized(DataCatalog.get_item(collection, id).get(field, {}))

func _build_shell() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	var column: VBoxContainer = VBoxContainer.new()
	shell.add_child(column)
	var top: HBoxContainer = HBoxContainer.new()
	column.add_child(top)
	var brand: VBoxContainer = VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	top.add_child(brand)
	brand.add_child(_label(_t("app_title"), 52, GOLD))
	brand.add_child(_label(_t("tagline"), 20, MUTED))
	var ranking: Button = _button(_t("leaderboard"), func(): _open_tab("leaderboard"))
	ranking.custom_minimum_size.x = 210
	ranking.add_theme_font_size_override("font_size", 25)
	ranking.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(ranking)
	var settings_button: Button = _button(_t("settings"), func(): _open_tab("settings"))
	settings_button.custom_minimum_size.x = 240
	settings_button.add_theme_font_size_override("font_size", 25)
	settings_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(settings_button)
	var hud: VBoxContainer = _panel(column)
	var venue_row: HBoxContainer = HBoxContainer.new()
	hud.add_child(venue_row)
	venue_label = _label("", 26, GOLD)
	venue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	venue_row.add_child(venue_label)
	status_label = _label("", 22, MUTED)
	status_label.custom_minimum_size.x = 410
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	venue_row.add_child(status_label)
	var stats: HBoxContainer = HBoxContainer.new()
	hud.add_child(stats)
	for key in ["money", "mood", "guests"]:
		var group: VBoxContainer = VBoxContainer.new()
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_theme_constant_override("separation", 6)
		stats.add_child(group)
		group.add_child(_label(_t(key), 21, MUTED))
		var number: Label = _label("", 38, GOLD if key == "money" else INK)
		group.add_child(number)
		match key:
			"money": money_label = number
			"mood": mood_label = number
			"guests": guest_label = number
	mood_bar = ProgressBar.new()
	mood_bar.custom_minimum_size.y = 14
	mood_bar.show_percentage = false
	mood_bar.min_value = DataCatalog.data.economy.mood.min
	mood_bar.max_value = DataCatalog.data.economy.mood.max
	hud.add_child(mood_bar)
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(content_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(body)
	toast = _label("", 24, GOLD)
	toast.custom_minimum_size.y = 32
	column.add_child(toast)
	var nav: HBoxContainer = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	column.add_child(nav)
	for key in ["floor", "band", "menu", "upgrades", "venues"]:
		var button: Button = _button(_t("nav_" + key), _open_tab.bind(key))
		button.custom_minimum_size.y = 132
		button.add_theme_font_size_override("font_size", 22)
		var nav_style: StyleBoxFlat = _box(PANEL, 20, PANEL.lightened(0.17))
		nav_style.content_margin_left = 10
		nav_style.content_margin_right = 10
		button.add_theme_stylebox_override("normal", nav_style)
		nav.add_child(button)
		nav_buttons[key] = button

func _safe_area() -> void:
	var left: int = 36
	var right: int = 36
	var top: int = 32
	var bottom: int = 30
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

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _open_tab(key: String) -> void:
	active_tab = key
	_clear(body)
	purchase_buttons.clear()
	table_widgets.clear()
	stage_song = null
	content_scroll.scroll_vertical = 0
	for nav in nav_buttons:
		nav_buttons[nav].add_theme_color_override("font_color", GOLD if key == nav else MUTED)
	match key:
		"floor": _floor()
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

func _floor() -> void:
	_heading(_t("floor_title"), _t("floor_hint"))
	var stage: VBoxContainer = _panel(body, Color("352b25"))
	stage.add_child(_label(_t("stage"), 21, GOLD))
	stage_band = _label("", 37)
	stage.add_child(stage_band)
	stage_song = _label("", 30, GOLD)
	stage.add_child(stage_song)
	stage_remaining = _label("", 24, MUTED)
	stage.add_child(stage_remaining)
	stage.add_child(_button(_t("choose_song"), func(): _show_songs(-1), true))
	night_label = _label(_t("night_status"), 22, GREEN)
	body.add_child(night_label)
	table_grid = GridContainer.new()
	table_grid.columns = int(GameState.simulation.rules.floor_columns)
	table_grid.add_theme_constant_override("h_separation", 18)
	table_grid.add_theme_constant_override("v_separation", 18)
	body.add_child(table_grid)
	_create_tables()

func _create_tables() -> void:
	_clear(table_grid)
	table_widgets.clear()
	for index in GameState.simulation.tables.size():
		var button: Button = _button("", _show_songs.bind(index))
		button.custom_minimum_size = Vector2(0, 330)
		table_grid.add_child(button)
		var margin: MarginContainer = MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margin)
		var content: VBoxContainer = VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 12)
		margin.add_child(content)
		var title: Label = _label(_t("table_number", {"number": index + 1}), 22, GOLD)
		content.add_child(title)
		var party: Label = _label("", 30)
		content.add_child(party)
		var mood: Label = _label("", 27, GREEN)
		content.add_child(mood)
		var request: Label = _label("", 24, MUTED)
		content.add_child(request)
		var order: Label = _label("", 24, GOLD)
		content.add_child(order)
		table_widgets.append({"button": button, "party": party, "mood": mood, "request": request, "order": order})

func _refresh() -> void:
	if not is_instance_valid(money_label): return
	money_label.text = _t("money_amount", {"amount": int(GameState.save.money)})
	mood_label.text = _t("mood_value", {"value": roundi(GameState.room_mood())})
	guest_label.text = str(GameState.guest_count())
	mood_bar.value = GameState.room_mood()
	venue_label.text = DataCatalog.localized(GameState.venue().name).to_upper()
	status_label.text = _t("sync_" + ApiClient.status)
	for entry in purchase_buttons:
		if is_instance_valid(entry.button): entry.button.disabled = not entry.allowed.call()
	for button in song_buttons:
		if is_instance_valid(button): button.disabled = GameState.simulation.song_remaining > 0
	if active_tab == "floor" and is_instance_valid(stage_song):
		stage_band.text = DataCatalog.localized(GameState.band().name)
		stage_song.text = _name("songs", GameState.simulation.current_song, "title") if not GameState.simulation.current_song.is_empty() else _t("song_idle")
		stage_remaining.text = _t("song_remaining", {"seconds": ceili(GameState.simulation.song_remaining)}) if GameState.simulation.song_remaining > 0 else _t("known_songs")
		night_label.text = _t("venue_closed", {"seconds": ceili(GameState.simulation.closed_remaining)}) if GameState.simulation.closed_remaining > 0 else _t("night_status")
		if table_widgets.size() != GameState.simulation.tables.size(): _create_tables()
		for index in table_widgets.size():
			var table: Dictionary = GameState.simulation.tables[index]
			var widgets: Dictionary = table_widgets[index]
			var empty: bool = str(table.get("guest_type", "")).is_empty()
			widgets.button.disabled = empty
			widgets.party.text = _t("table_empty") if empty else _t("table_party", {"name": _name("guest_types", table.guest_type), "count": table.party_size})
			widgets.mood.text = "" if empty else _table_mood(table)
			widgets.mood.add_theme_color_override("font_color", RED if table.get("mood", 0) < DataCatalog.data.economy.mood.unhappy_below else GREEN)
			widgets.request.text = _t("table_waiting") if empty else _request_text(table)
			widgets.order.text = "" if empty else _order_text(table)
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
		var card: VBoxContainer = _panel(body)
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
	shade.color = Color(0.015, 0.025, 0.03, 0.9)
	modal.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, maxi(58, shell.get_theme_constant("margin_" + side)))
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, maxi(100, shell.get_theme_constant("margin_" + side)))
	modal.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _box(PANEL, 32, GOLD.darkened(0.4)))
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
		modal_body.add_child(_label(_t("table_party", {"name": _name("guest_types", table.guest_type), "count": table.party_size}), 31))
		modal_body.add_child(_label(_request_text(table), 31, GREEN))
		modal_body.add_child(_label(_order_text(table), 27, MUTED))
		if table.get("order_status") == "waiting":
			modal_body.add_child(_button(_t("serve"), func():
				if GameState.serve_table(index): _notice("notice_serving", {})
				_show_songs(index)
			, true))
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
	toast_seconds = 5.0

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
		if toast_seconds <= 0: toast.text = ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveSystem.save_now()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(modal) and modal_kind not in ["event", "conflict"]: _close_modal()
		elif not is_instance_valid(modal): _open_tab("floor")
