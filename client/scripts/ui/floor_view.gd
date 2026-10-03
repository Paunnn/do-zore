extends Control
## The game world on screen: a night city seen through an orthographic isometric camera, with
## the venue being played as a cut-away full of guests. Drag to pan, pinch or wheel to zoom from
## a table close-up out to the whole map; tap tables, the stage, a free table slot or another
## venue on the map. Thought clouds, coins and notes are 2D nodes kept over their 3D anchors.
signal table_tapped(index: int)
signal stage_tapped
signal slot_tapped(index: int)
signal venue_tapped(id: String)

const City = preload("res://scripts/world3d/city3d.gd")
const Kit = preload("res://scripts/world3d/kit3d.gd")
const VenueWorld = preload("res://scripts/world3d/venue_world.gd")
const UIKit = preload("res://scripts/ui/ui_kit.gd")
const WorldData = preload("res://scripts/world/world_data.gd")
const TAP_SLOP = 18.0
const PITCH = -46.0
const YAW = 45.0
const CLOSE = 13.0
const FAR = 150.0
const MAP_ZOOM = 46.0
## One night takes this long: warm evening, deep night, then dawn ("do zore"), and round again.
const NIGHT_SECONDS = 1200.0
## Sky keyframes over the night (0..1): background, ambient light, the sun/moon and the river.
const SKIES = [
	{"at": 0.0, "bg": Color("2b2546"), "ambient": Color("948ac0"), "ambient_energy": 0.66, "sun": Color("ffb47e"), "sun_energy": 1.0, "pitch": -42.0, "yaw": 58.0, "deep": Color("1f2b55"), "shallow": Color("3c4a80")},
	{"at": 0.35, "bg": Color("0e1830"), "ambient": Color("50639a"), "ambient_energy": 0.62, "sun": Color("a9c2ff"), "sun_energy": 0.5, "pitch": -58.0, "yaw": 40.0, "deep": Color("0d1a33"), "shallow": Color("1f375e")},
	{"at": 0.7, "bg": Color("0e1830"), "ambient": Color("50639a"), "ambient_energy": 0.62, "sun": Color("a9c2ff"), "sun_energy": 0.5, "pitch": -58.0, "yaw": 40.0, "deep": Color("0d1a33"), "shallow": Color("1f375e")},
	{"at": 0.88, "bg": Color("3b3658"), "ambient": Color("a99fca"), "ambient_energy": 0.7, "sun": Color("ffc9ad"), "sun_energy": 0.92, "pitch": -40.0, "yaw": 30.0, "deep": Color("25335f"), "shallow": Color("4a5588")},
	{"at": 1.0, "bg": Color("2b2546"), "ambient": Color("948ac0"), "ambient_energy": 0.66, "sun": Color("ffb47e"), "sun_energy": 1.0, "pitch": -42.0, "yaw": 58.0, "deep": Color("1f2b55"), "shallow": Color("3c4a80")},
]
const INK = Color("2b1d14")

var viewport_container: SubViewportContainer
var viewport: SubViewport
var scene: Node3D
var camera: Camera3D
var environment: Environment
var moon: DirectionalLight3D
var city
var world
var hud_layer: Node2D
var map_layer: Control
var map_pins: Dictionary = {}
var fx: Control
var song_bar: PanelContainer
var song_title: Label
var song_progress: ProgressBar
var song_note: TextureRect
## Where the music button is on screen (the HUD owns it); the first song hint points there.
var music_point: Callable = Callable()
var venue_id: String = ""
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
## Camera state: the ground point it looks at and the width of view in metres.
var target: Vector3 = Vector3.ZERO
var view_width: float = 24.0
var flight: Tween
## Set before a venue is bought with a celebration: the camera waits on the old venue until
## release_flight() so the player sees the glide across the city.
var hold_flight: bool = false
var held_focus: Array = []
## Where we are in the night (see SKIES); every new venue opens at dusk.
var night_clock: float = 0.03

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_container = SubViewportContainer.new()
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport_container.add_child(viewport)
	scene = Node3D.new()
	viewport.add_child(scene)
	_build_environment()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.rotation_degrees = Vector3(PITCH, YAW, 0)
	camera.near = 1.0
	camera.far = 900.0
	scene.add_child(camera)
	camera.make_current()
	city = City.new()
	scene.add_child(city)
	world = VenueWorld.new()
	world.payout.connect(_on_payout)
	world.note.connect(_on_note)
	scene.add_child(world)
	map_layer = Control.new()
	map_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_layer)
	hud_layer = Node2D.new()
	add_child(hud_layer)
	world.hud_layer = hud_layer
	fx = Control.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	_build_song_bar()
	resized.connect(_on_resized)
	_ensure_world()

func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0e1830")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("4d5f94")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = true
	environment.glow_intensity = 0.75
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = environment
	scene.add_child(holder)
	moon = DirectionalLight3D.new()
	moon.light_color = Color("a9c2ff")
	moon.light_energy = 0.5
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 140.0
	moon.shadow_blur = 1.5
	moon.rotation_degrees = Vector3(-56, -28, 0)
	scene.add_child(moon)

func _build_song_bar() -> void:
	# Now playing: a dark inset plaque with the genre note and a brass progress line.
	var line: HBoxContainer = UIKit.row(UIKit.S)
	song_note = UIKit.tinted("note", 36, UIKit.LAMP)
	song_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(song_note)
	var column: VBoxContainer = UIKit.column(4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(column)
	song_title = UIKit.label("", "label", 23, Color.WHITE)
	UIKit.outlined(song_title, 6, UIKit.OUTLINE, false)
	song_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	song_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(song_title)
	song_progress = UIKit.bar(UIKit.GOLD, 10)
	column.add_child(song_progress)
	song_bar = UIKit.panel("pill_dark", line)
	song_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	song_bar.visible = false
	add_child(song_bar)
	closed_label = UIKit.label("", "label", 30, Color.WHITE)
	closed_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIKit.outlined(closed_label, 8, Color("5a1210"))
	closed_pill = UIKit.panel("header", closed_label)
	closed_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed_pill.visible = false
	add_child(closed_pill)
	hint = Control.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.visible = false
	add_child(hint)
	hint_label = UIKit.label("", "bold", 28, UIKit.INK)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var hint_pill: PanelContainer = UIKit.panel("row", hint_label)
	hint_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_child(hint_pill)
	hint_arrow = Control.new()
	hint_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_arrow.draw.connect(func():
		var points: PackedVector2Array = PackedVector2Array([Vector2(-26, -40), Vector2(26, -40), Vector2(0, 0)])
		hint_arrow.draw_colored_polygon(points, UIKit.GOLD)
		hint_arrow.draw_polyline(points + PackedVector2Array([points[0]]), INK, 5.0, true))
	add_child(hint_arrow)
	_place_overlays()

func set_insets(top: float, bottom: float) -> void:
	top_inset = top
	bottom_inset = bottom
	_place_overlays()
	_apply_camera()

func _on_resized() -> void:
	_place_overlays()
	_apply_camera()

func _place_overlays() -> void:
	if song_bar == null:
		return
	# Now playing sits just above the music button, out of the way of the room.
	song_bar.size = Vector2(minf(size.x - 280, 620), 0)
	song_bar.reset_size()
	song_bar.size.x = minf(size.x - 280, 620)
	song_bar.position = Vector2((size.x - song_bar.size.x) / 2, size.y - bottom_inset - song_bar.size.y - UIKit.XS)

# --------------------------------------------------------------------------------------------
# World and map
# --------------------------------------------------------------------------------------------

func _venue_states() -> Dictionary:
	var states: Dictionary = {}
	var here: int = int(GameState.venue().order)
	for venue in DataCatalog.items("venues"):
		var order: int = int(venue.order)
		states[venue.id] = "owned" if order < here else ("next" if order == here + 1 else ("locked" if order > here else "current"))
	return states

func _ensure_world() -> void:
	var venue: String = str(GameState.save.venue)
	if venue == venue_id:
		return
	var previous: String = venue_id
	venue_id = venue
	var max_tables: Dictionary = {}
	for item in DataCatalog.items("venues"):
		max_tables[item.id] = int(item.max_tables)
	world.clear_overlay()
	city.build(venue, _venue_states(), max_tables)
	world.position = city.lots[venue].origin
	world.build(venue, int(max_tables.get(venue, 6)))
	var path: Dictionary = city.approach(venue)
	world.approach = {"point": path.point - world.position, "dir": path.dir}
	_build_pins()
	var focus: Vector3 = world.focus_point()
	var width: float = venue_width()
	if previous.is_empty() or not city.lots.has(previous):
		target = focus
		view_width = width
		_apply_camera()
	else:
		# A new venue: a new night, and the camera glides over from the old one.
		night_clock = 0.03
		if hold_flight:
			var old: Dictionary = city.lots[previous]
			target = old.origin + Vector3(old.lay.w * 0.5, 0, old.lay.d * 0.5)
			_apply_camera()
			held_focus = [focus, width]
		else:
			fly_to(focus, width, city.lots[previous].origin)
	world.sync(GameState.simulation, GameState.save)

## The default zoom on the venue being played: the room fills the screen edge to edge.
func venue_width() -> float:
	return clampf((world.lay.w + world.lay.d) * 0.5, 12.5, 23.0)

## The sky at a point of the night, blended between its keyframes.
static func sky_at(clock: float) -> Dictionary:
	for i in range(SKIES.size() - 1):
		var a: Dictionary = SKIES[i]
		var b: Dictionary = SKIES[i + 1]
		if clock <= b.at:
			var t: float = smoothstep(a.at, b.at, clock)
			var result: Dictionary = {}
			for key in a:
				result[key] = a[key].lerp(b[key], t) if a[key] is Color else lerpf(a[key], b[key], t)
			return result
	return SKIES[0]

func _apply_sky(sky: Dictionary) -> void:
	environment.background_color = sky.bg
	environment.ambient_light_color = sky.ambient
	moon.light_color = sky.sun
	moon.light_energy = sky.sun_energy
	moon.rotation_degrees = Vector3(sky.pitch, sky.yaw, 0)
	var water: ShaderMaterial = Kit.material("water")
	water.set_shader_parameter("deep", sky.deep)
	water.set_shader_parameter("shallow", sky.shallow)
	# People catch a rim of the sky's light: warm at dusk and dawn, cool by night.
	var people: ShaderMaterial = Kit.material("people")
	people.set_shader_parameter("rim", sky.sun.lerp(Color(1, 1, 1), 0.25))

## Glide across the map: out over the city, then down into the new venue.
func fly_to(point: Vector3, width: float, from: Vector3 = Vector3.INF) -> void:
	if flight != null and flight.is_valid():
		flight.kill()
	if from != Vector3.INF:
		target = from
	var start: Vector3 = target
	var start_width: float = view_width
	var travel: float = start.distance_to(point)
	var high: float = clampf(travel * 0.9, maxf(start_width, width) + 10.0, FAR * 0.8)
	flight = create_tween()
	flight.tween_method(func(t: float):
		var eased: float = t * t * (3.0 - 2.0 * t)
		target = start.lerp(point, eased)
		var arc: float = sin(t * PI)
		view_width = lerpf(start_width, width, eased) * (1.0 - arc) + high * arc
		_apply_camera(), 0.0, 1.0, 2.2)

func _build_pins() -> void:
	for pin in map_pins.values():
		pin.queue_free()
	map_pins.clear()
	var states: Dictionary = _venue_states()
	for id in city.lots:
		var venue: Dictionary = DataCatalog.get_item("venues", id)
		var column: VBoxContainer = UIKit.column(2)
		var name: Label = UIKit.label(DataCatalog.localized(venue.get("name", {})), "display", 32, Color.WHITE)
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UIKit.outlined(name, 8, Color("5a1210"))
		column.add_child(name)
		var state: String = states.get(id, "locked")
		if state == "next":
			var price: Label = UIKit.label(DataCatalog.text("money_amount", {"amount": UIKit.amount(int(venue.get("unlock_cost", 0)), DataCatalog.locale)}), "number", 26, UIKit.GOLD)
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UIKit.outlined(price, 7)
			column.add_child(price)
		var pin: PanelContainer = UIKit.panel("header" if state in ["current", "next"] else "pill_dark", column)
		pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pin.modulate = Color(1, 1, 1, 0.75) if state == "locked" else Color.WHITE
		map_layer.add_child(pin)
		map_pins[id] = pin

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
	var point: Vector2 = Vector2.INF
	var text: String = ""
	var anyone_served: bool = false
	for slot in world.slots:
		if not slot.locked and str(slot.status) in ["preparing", "served"]:
			anyone_served = true
	if int(stats.get("orders_served", 0)) == 0 and not anyone_served:
		for slot in world.slots:
			if not slot.locked and slot.hud.mode == "order":
				point = slot.hud.position + Vector2(0, -95) * slot.hud.scale.x
				text = DataCatalog.text("hint_serve")
				break
	elif int(stats.get("songs_played", 0)) == 0 and GameState.simulation.song_remaining <= 0.0:
		for slot in world.slots:
			if not slot.locked and slot.hud.mode == "request":
				point = music_point.call() - global_position if music_point.is_valid() else Vector2.INF
				text = DataCatalog.text("hint_song")
				break
	hint.visible = point != Vector2.INF and not closed_pill.visible and view_width < MAP_ZOOM
	hint_arrow.visible = hint.visible
	if hint.visible:
		hint_label.text = text
		var pill: PanelContainer = hint.get_child(0)
		pill.reset_size()
		hint_target = point
		var x: float = clampf(point.x - pill.size.x / 2, 20, size.x - pill.size.x - 20)
		hint.position = Vector2(x, point.y - 60 - pill.size.y)

# --------------------------------------------------------------------------------------------
# Camera
# --------------------------------------------------------------------------------------------

## Pixels per metre on screen at the current zoom.
func metre() -> float:
	return size.x / maxf(1.0, view_width) if size.x > 0 else 40.0

func _apply_camera() -> void:
	if camera == null:
		return
	var bounds_low: float = -95.0
	var bounds_high: float = 235.0
	var t: float = clampf(City.along(target), bounds_low, bounds_high)
	var u: float = clampf(City.across(target), -80.0, 80.0)
	target = Vector3(-1, 0, -1).normalized() * t + Vector3(1, 0, -1).normalized() * u
	view_width = clampf(view_width, CLOSE, FAR)
	camera.size = view_width
	# Keep the looked-at point in the middle of the space between the HUD and the bottom bar.
	var shift: float = (bottom_inset - top_inset) / 2.0 / metre()
	camera.position = target + camera.transform.basis.z * 200.0
	camera.v_offset = -shift
	moon.directional_shadow_max_distance = clampf(view_width * 3.5, 60.0, 260.0)
	_update_overlay()

func project(point: Vector3) -> Vector2:
	return camera.unproject_position(point)

func screen_to_ground(point: Vector2) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(point)
	var normal: Vector3 = camera.project_ray_normal(point)
	if absf(normal.y) < 0.001:
		return target
	return origin + normal * (-origin.y / normal.y)

func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before: Vector3 = screen_to_ground(screen_point)
	view_width = clampf(view_width / factor, CLOSE, FAR)
	_apply_camera()
	var after: Vector3 = screen_to_ground(screen_point)
	target += before - after
	_apply_camera()

func _pan(screen_delta: Vector2) -> void:
	var right: Vector3 = Vector3(1, 0, -1).normalized()
	var down: Vector3 = Vector3(1, 0, 1).normalized()
	# Screen y covers less ground than x at this pitch.
	var scale_y: float = 1.0 / sin(deg_to_rad(-PITCH))
	target -= (right * screen_delta.x + down * screen_delta.y * scale_y) / metre()
	_apply_camera()

func _update_overlay() -> void:
	if world == null or world.slots.is_empty():
		return
	var zoom: float = clampf(22.0 / view_width, 0.42, 1.25)
	var near: bool = view_width < MAP_ZOOM
	for slot in world.slots:
		var anchor: Vector3 = world.to_global(slot.anchor)
		slot.hud.position = project(anchor)
		slot.hud.scale = Vector2.ONE * zoom
		slot.hud.visible = near and not slot.locked
		slot.plus.position = project(world.to_global(slot.floor + Vector3(0, 0.5, 0)))
		slot.plus.scale = Vector2.ONE * zoom * 0.5
		if not near: slot.plus.visible = false
	for cloud in world.dust:
		if cloud.has_meta("anchor"):
			cloud.position = project(world.to_global(cloud.get_meta("anchor")))
			cloud.scale = Vector2.ONE * zoom * 0.5
			cloud.visible = near
	var show_pins: bool = view_width > MAP_ZOOM * 0.8
	for id in map_pins:
		var pin: PanelContainer = map_pins[id]
		var lot: Dictionary = city.lots[id]
		var top: Vector3 = lot.origin + Vector3(lot.lay.w / 2.0, 12.0, lot.lay.d / 2.0)
		pin.reset_size()
		pin.position = project(top) - pin.size / 2.0
		pin.visible = show_pins
		pin.modulate.a = clampf((view_width - MAP_ZOOM * 0.8) / 10.0, 0.0, 1.0) * (0.75 if pin.modulate.a < 0.9 and id != venue_id else 1.0)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	refresh_timer += delta
	if refresh_timer >= 0.1:
		refresh_timer = 0.0
		refresh()
	if hint.visible:
		hint_time += delta
		hint_arrow.position = hint_target + Vector2(0, absf(sin(hint_time * 5.0)) * -14.0)
	if touches.is_empty() and velocity.length() > 5.0:
		_pan(velocity * delta)
		velocity = velocity.lerp(Vector2.ZERO, clampf(delta * 5.0, 0.0, 1.0))
	night_clock = fmod(night_clock + delta / NIGHT_SECONDS, 1.0)
	var sky: Dictionary = sky_at(night_clock)
	_apply_sky(sky)
	environment.ambient_light_energy = lerpf(environment.ambient_light_energy, sky.ambient_energy * (1.0 - 0.4 * world.darkness), clampf(delta * 3.0, 0.0, 1.0))
	_update_overlay()

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
				if flight != null and flight.is_valid(): flight.kill()
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
			_pan(event.relative)
			velocity = event.velocity if event.velocity.length() < 4000.0 else event.velocity.normalized() * 4000.0
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.12)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		_pan(-event.delta * 12.0)

func _pinch_span() -> float:
	if touches.size() < 2:
		return 0.0
	var points: Array = touches.values()
	return (points[0] as Vector2).distance_to(points[1])

func _pinch_center() -> Vector2:
	var points: Array = touches.values()
	return ((points[0] as Vector2) + (points[1] as Vector2)) / 2.0

func _tap(screen_point: Vector2) -> void:
	if view_width < MAP_ZOOM:
		var hit: Dictionary = world.pick(screen_point, project, metre())
		match str(hit.kind):
			"table":
				table_tapped.emit(int(hit.index))
				return
			"slot":
				slot_tapped.emit(int(hit.index))
				return
			"stage":
				stage_tapped.emit()
				return
	# On the map: tapping a venue's building or pin.
	var ground: Vector3 = screen_to_ground(screen_point)
	for id in city.lots:
		var lot: Dictionary = city.lots[id]
		var rect: Rect2 = Rect2(lot.origin.x - 2, lot.origin.z - 2, lot.lay.w + 4, lot.lay.d + 4)
		var pin_hit: bool = map_pins.has(id) and map_pins[id].visible and map_pins[id].get_rect().has_point(screen_point)
		if rect.has_point(Vector2(ground.x, ground.z)) or pin_hit:
			if id == venue_id and view_width >= MAP_ZOOM:
				fly_to(world.focus_point(), venue_width())
			elif id != venue_id:
				venue_tapped.emit(id)
			return

func release_flight() -> void:
	hold_flight = false
	if not held_focus.is_empty():
		fly_to(held_focus[0], held_focus[1])
		held_focus = []

## Show the whole road from the birtija to the splav.
func show_map() -> void:
	var middle: Vector3 = (city.lots.birtija.origin + city.lots.splav.origin) / 2.0
	fly_to(middle, FAR * 0.95)

## Look at another venue's lot on the map.
func show_lot(id: String) -> void:
	if not city.lots.has(id):
		return
	var lot: Dictionary = city.lots[id]
	fly_to(lot.origin + Vector3(lot.lay.w * 0.5, 0, lot.lay.d * 0.5), clampf((lot.lay.w + lot.lay.d) * 0.9, 24.0, 44.0))

func show_venue() -> void:
	fly_to(world.focus_point(), venue_width())

# --------------------------------------------------------------------------------------------
# Payouts and music notes
# --------------------------------------------------------------------------------------------

func _on_payout(world_point: Vector3, amount: int, angry: bool) -> void:
	var start: Vector2 = project(world_point)
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
	var goal: Vector2 = money_target.call() - global_position
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
		tween.tween_property(coin, "position", goal - coin.size / 2, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_callback(coin.queue_free)

func _on_note(world_point: Vector3, genre: String) -> void:
	if view_width >= MAP_ZOOM:
		return
	var note: Sprite2D = WorldData.sprite("fx/note")
	note.modulate = UIKit.GENRE_COLORS.get(genre, Color.WHITE).lightened(0.2)
	note.position = project(world_point) + Vector2(randf_range(-16, 16), 0)
	note.scale *= 0.7 * clampf(22.0 / view_width, 0.5, 1.2)
	fx.add_child(note)
	var tween: Tween = note.create_tween()
	tween.set_parallel(true)
	tween.tween_property(note, "position", note.position + Vector2(randf_range(-50, 50), -110), 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "modulate:a", 0.0, 2.2).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(note.queue_free)
