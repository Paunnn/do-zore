extends RefCounted
## Kafana UI kit: palette, type, spacing and the textured boxes drawn by tools/art/build_ui.py.
## Everything is measured in design pixels on a 1080-wide portrait screen.
const UI = "res://assets/ui/"

# Palette: walnut and brass for structure, cream paper for reading, one red, kilim navy for night.
const NIGHT = Color("0e1428")
const NAVY = Color("1f3b5a")
const WALNUT = Color("4a2c1a")
const WALNUT_DARK = Color("2e1a0f")
const BRASS = Color("d9a531")
const BRASS_LIGHT = Color("f6dc8e")
const BRASS_DARK = Color("8a5a1c")
const CREAM = Color("f3e8cf")
const PAPER = Color("fbf5e6")
const INK = Color("2b1d14")
const MUTED = Color("7a6148")
const RED = Color("b8302f")
const GREEN = Color("3d8a4f")
const LAMP = Color("ffd36a")
const GENRE_COLORS = {"starogradske": Color("e8a33a"), "tamburica": Color("2f9e86"), "izvorna": Color("d2553f"), "narodnjaci": Color("8e5cc7")}

# Spacing scale. Screens use GUTTER at the edges and GAP between stacked blocks.
const XS = 6
const S = 12
const M = 18
const L = 24
const XL = 36
const GUTTER = 24
const GAP = 16

# Type scale.
const TITLE = 56
const HEADING = 40
const NAME = 32
const BODY = 28
const SMALL = 24
const TINY = 21

# Nine-patch margins of each piece: [left, top, right, bottom] texture margins, then content margins.
const PIECES = {
	"plank": [[30, 30, 30, 38], [24, 16, 24, 26]],
	"paper": [[24, 24, 24, 30], [24, 20, 24, 26]],
	"paper_brass": [[24, 24, 24, 30], [24, 20, 24, 26]],
	"sheet": [[42, 42, 42, 50], [34, 30, 30, 42]],
	"night_sheet": [[42, 42, 42, 50], [34, 30, 30, 42]],
	"chip": [[32, 28, 32, 34], [14, 6, 24, 12]],
	"ribbon": [[50, 18, 50, 18], [58, 6, 58, 18]],
	"tab_active": [[24, 22, 24, 30], [6, 10, 6, 14]],
	"bar_back": [[13, 12, 13, 12], [0, 0, 0, 0]],
	"bar_back_light": [[13, 12, 13, 12], [0, 0, 0, 0]],
	"bar_fill": [[13, 12, 13, 12], [0, 0, 0, 0]],
	"medallion": [[54, 54, 54, 62], [20, 20, 20, 28]],
	"medallion_pressed": [[54, 54, 54, 62], [20, 28, 20, 20]],
}
const BUTTON_MARGINS = [26, 24, 26, 32]

static var _fonts: Dictionary = {}
static var _textures: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(UI + path + ".svg")
	return _textures[path]

static func glyph(name: String) -> Texture2D:
	return texture("glyphs/" + name)

## kind: display (Yeseva One), label (Alegreya SC), body, bold, number (lining tabular) or script.
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var files: Dictionary = {"display": "YesevaOne", "label": "AlegreyaSC-ExtraBold", "body": "AlegreyaSans-500",
		"bold": "AlegreyaSans-800", "number": "AlegreyaSans-800", "script": "MarckScript"}
	var base: FontFile = load("res://assets/fonts/%s.ttf" % files.get(kind, "AlegreyaSans-500"))
	var variation: FontVariation = FontVariation.new()
	variation.base_font = base
	var server: TextServer = TextServerManager.get_primary_interface()
	# Alegreya defaults to old-style figures; prices and counters read better as lining numbers.
	var features: Dictionary = {server.name_to_tag("lnum"): 1}
	if kind == "number":
		features[server.name_to_tag("tnum")] = 1
	variation.opentype_features = features
	if kind == "label":
		variation.spacing_glyph = 1
	_fonts[kind] = variation
	return variation

static func box(piece: String) -> StyleBoxTexture:
	var margins: Array = PIECES[piece]
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture(piece)
	_margins(style, margins[0], margins[1])
	return style

static func _margins(style: StyleBoxTexture, texture_margins: Array, content: Array) -> void:
	style.texture_margin_left = texture_margins[0]
	style.texture_margin_top = texture_margins[1]
	style.texture_margin_right = texture_margins[2]
	style.texture_margin_bottom = texture_margins[3]
	style.content_margin_left = content[0]
	style.content_margin_top = content[1]
	style.content_margin_right = content[2]
	style.content_margin_bottom = content[3]

## Button faces: brass (primary), red (the one big decision), paper (secondary), dark (on wood).
static func button_box(kind: String, state: String) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	var pressed: bool = state == "pressed"
	if state == "disabled":
		style.texture = texture("button_disabled")
		pressed = true
	else:
		style.texture = texture("button_%s%s" % [kind, "_pressed" if pressed else ""])
	# The face sits 7 px lower when pressed; the label moves with it.
	_margins(style, BUTTON_MARGINS, [24, 19 if pressed else 12, 24, 15 if pressed else 22])
	return style

static func style_button(button: Button, kind: String = "brass", font_size: int = 30) -> void:
	for state in ["normal", "hover", "focus", "hover_pressed"]:
		button.add_theme_stylebox_override(state, button_box(kind, "normal") if state != "focus" else StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", button_box(kind, "pressed"))
	button.add_theme_stylebox_override("disabled", button_box(kind, "disabled"))
	var text: Color = CREAM if kind in ["red", "dark"] else INK
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, text)
	button.add_theme_color_override("font_disabled_color", Color(MUTED, 0.85))
	for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, text)
	button.add_theme_color_override("icon_disabled_color", Color(MUTED, 0.7))
	button.add_theme_font_override("font", font("label"))
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_NONE

static func make_button(text: String, action: Callable, kind: String = "brass", font_size: int = 30) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 100
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_button(button, kind, font_size)
	button.pressed.connect(action)
	return button

## Round brass medallion carrying an ink glyph: settings, leaderboard, music.
static func medallion(glyph_name: String, action: Callable, side: int = 104) -> Button:
	var button: Button = Button.new()
	button.icon = glyph(glyph_name)
	button.expand_icon = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(side, side + 8)
	button.add_theme_constant_override("icon_max_width", int(side * 0.5))
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state in ["normal", "hover", "focus", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, box("medallion"))
	button.add_theme_stylebox_override("pressed", box("medallion_pressed"))
	for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, INK)
	button.pressed.connect(action)
	return button

static func label(text: String, kind: String = "body", size: int = BODY, color: Color = INK) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_override("font", font(kind))
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func picture(texture_value: Texture2D, side: float) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture_value
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

static func tinted(glyph_name: String, side: float, color: Color) -> TextureRect:
	var rect: TextureRect = picture(glyph(glyph_name), side)
	rect.self_modulate = color
	return rect

## A picture in a round brass frame; locked things sit in a dark frame with a lock.
static func framed(texture_value: Texture2D, side: float, frame: String = "ring_paper", inset: float = 0.16) -> Control:
	var holder: Control = Control.new()
	holder.custom_minimum_size = Vector2(side, side)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring: TextureRect = picture(texture(frame), side)
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(ring)
	if texture_value != null:
		var inner: TextureRect = picture(texture_value, side * (1.0 - inset * 2.0))
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var pad: float = side * inset
		inner.offset_left = pad
		inner.offset_top = pad
		inner.offset_right = -pad
		inner.offset_bottom = -pad
		holder.add_child(inner)
	return holder

## light: the track as printed on paper; otherwise a dark slot for wood and night panels.
static func bar(fill: Color, height: float = 22.0, light: bool = false) -> ProgressBar:
	var result: ProgressBar = ProgressBar.new()
	result.show_percentage = false
	result.custom_minimum_size = Vector2(0, height)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_stylebox_override("background", box("bar_back_light" if light else "bar_back"))
	var fill_box: StyleBoxTexture = box("bar_fill")
	fill_box.modulate_color = fill
	result.add_theme_stylebox_override("fill", fill_box)
	return result

static func set_bar_color(progress: ProgressBar, fill: Color) -> void:
	var fill_box: StyleBoxTexture = progress.get_theme_stylebox("fill")
	if fill_box is StyleBoxTexture and fill_box.modulate_color != fill:
		fill_box.modulate_color = fill

## Seamless kilim band used under headings and along the top of sheets.
static func kilim(height: float = 26.0) -> TextureRect:
	var strip: TextureRect = TextureRect.new()
	strip.texture = texture("kilim_strip")
	strip.stretch_mode = TextureRect.STRETCH_TILE
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.custom_minimum_size = Vector2(0, height)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return strip

static func divider() -> TextureRect:
	var rule: TextureRect = picture(texture("divider"), 0)
	rule.custom_minimum_size = Vector2(0, 24)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rule

static func panel(piece: String, content: Control = null) -> PanelContainer:
	var result: PanelContainer = PanelContainer.new()
	result.add_theme_stylebox_override("panel", box(piece))
	result.mouse_filter = Control.MOUSE_FILTER_PASS
	if content != null:
		result.add_child(content)
	return result

static func row(separation: int = M) -> HBoxContainer:
	var result: HBoxContainer = HBoxContainer.new()
	result.add_theme_constant_override("separation", separation)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func column(separation: int = S) -> VBoxContainer:
	var result: VBoxContainer = VBoxContainer.new()
	result.add_theme_constant_override("separation", separation)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

## Money with thousands grouped the local way: 12.450 in Serbian, 12,450 in English.
static func amount(value: int, locale: String) -> String:
	var digits: String = str(absi(value))
	var grouped: String = ""
	var separator: String = "." if locale == "sr" else ","
	while digits.length() > 3:
		grouped = separator + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + grouped

static func roman(value: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI"][clampi(value, 0, 6)]
