extends RefCounted
## Modern-kafana UI kit: palette, type, spacing and the textured pieces drawn by tools/art/build_ui.py.
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
const GOLD = Color("ffbf2e")
const OUTLINE = Color("3a1d0e")
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
	"bar_back": [[13, 12, 13, 12], [0, 0, 0, 0]],
	"bar_back_light": [[13, 12, 13, 12], [0, 0, 0, 0]],
	"bar_fill": [[13, 12, 13, 12], [0, 0, 0, 0]],
	"pill_dark": [[36, 30, 36, 34], [16, 6, 24, 12]],
	"card": [[40, 40, 40, 50], [30, 24, 26, 40]],
	"row": [[26, 26, 26, 30], [22, 16, 22, 22]],
	"header": [[48, 30, 48, 30], [52, 6, 52, 26]],
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

## kind: display (Shrikhand, titles and venue names), label / number (Titan One: buttons, counts,
## prices), body and bold (Nunito).
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var variation: FontVariation = FontVariation.new()
	match kind:
		"display", "script":
			variation.base_font = load("res://assets/fonts/Shrikhand-Regular.ttf")
		"label", "number":
			variation.base_font = load("res://assets/fonts/TitanOne-Regular.ttf")
			variation.spacing_glyph = 1 if kind == "label" else 0
		_:
			variation.base_font = load("res://assets/fonts/Nunito-Variable.ttf")
			variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900 if kind == "bold" else 700}
	_fonts[kind] = variation
	return variation

## Game lettering: a dark outline and a drop shadow, white or gold fill.
static func outlined(target: Control, outline: int = 10, colour: Color = OUTLINE, shadow: bool = true) -> void:
	target.add_theme_color_override("font_outline_color", colour)
	target.add_theme_constant_override("outline_size", outline)
	if shadow:
		target.add_theme_color_override("font_shadow_color", Color(colour, 0.6))
		target.add_theme_constant_override("shadow_offset_x", 0)
		target.add_theme_constant_override("shadow_offset_y", 4)
		target.add_theme_constant_override("shadow_outline_size", outline)

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

## Button faces: gold (primary), red (the one big decision) and paper (secondary).
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

static func style_button(button: Button, kind: String = "gold", font_size: int = 30) -> void:
	for state in ["normal", "hover", "focus", "hover_pressed"]:
		button.add_theme_stylebox_override(state, button_box(kind, "normal") if state != "focus" else StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", button_box(kind, "pressed"))
	button.add_theme_stylebox_override("disabled", button_box(kind, "disabled"))
	var light: bool = kind in ["red", "gold"]
	var text: Color = Color.WHITE if light else INK
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, text)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.9) if light else Color(MUTED, 0.85))
	if light:
		button.add_theme_color_override("font_outline_color", OUTLINE if kind != "red" else Color("5a1210"))
		button.add_theme_constant_override("outline_size", 9)
	for key in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, text)
	button.add_theme_color_override("icon_disabled_color", Color(MUTED, 0.7))
	button.add_theme_font_override("font", font("label"))
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_NONE

static func make_button(text: String, action: Callable, kind: String = "gold", font_size: int = 30) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 100
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_button(button, kind, font_size)
	button.pressed.connect(action)
	return button

## Glossy round button with a glyph, an optional caption under it and a red badge slot.
## style: "cream" (small, ink glyph), "gold" or "red" (large, white glyph).
static func round_button(glyph_name: String, action: Callable, style: String = "cream", side: int = 104, caption: String = "") -> Control:
	var holder: VBoxContainer = column(0)
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	var button: TextureButton = TextureButton.new()
	button.texture_normal = texture("round_" + style)
	button.texture_pressed = texture("round_%s_pressed" % style)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = Vector2(side, side * 1.1)
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	holder.add_child(button)
	var icon: TextureRect = tinted(glyph_name, side * 0.48, INK if style == "cream" else Color.WHITE)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_bottom = -side * 0.16
	button.add_child(icon)
	button.button_down.connect(func(): icon.position.y = side * 0.07)
	button.button_up.connect(func(): icon.position.y = 0)
	var mark: TextureRect = picture(texture("badge"), side * 0.36)
	mark.position = Vector2(side * 0.7, -side * 0.02)
	mark.visible = false
	mark.name = "badge"
	button.add_child(mark)
	if caption != "":
		var words: Label = label(caption, "label", 22 if side < 140 else 26, Color.WHITE)
		words.autowrap_mode = TextServer.AUTOWRAP_OFF
		words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outlined(words, 8)
		holder.add_child(words)
	holder.set_meta("button", button)
	holder.set_meta("badge", mark)
	return holder

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

## Tablecloth trim (red and cream checks) under card headers; "kilim" keeps its old name.
static func kilim(height: float = 16.0) -> TextureRect:
	var strip: TextureRect = TextureRect.new()
	strip.texture = texture("checker_strip")
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
