extends SceneTree
## Renders the interface pictures from the 3D world: each venue's building (assets/ui/venues), each
## band line-up playing (assets/ui/bands) and a group of each guest type (assets/ui/guests).
## Needs a graphics-capable Godot (run under xvfb-run if headless):
##   godot --path client --rendering-driver opengl3 --script res://tests/render_venue_cards.gd
const Venue = preload("res://scripts/world3d/venue3d.gd")
const People = preload("res://scripts/world3d/people3d.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out: String = ProjectSettings.globalize_path("res://assets/ui/venues")
	DirAccess.make_dir_recursive_absolute(out)
	var catalog = root.get_node("DataCatalog")
	for id in ["birtija", "kafana", "restoran", "splav"]:
		var view: SubViewport = SubViewport.new()
		view.size = Vector2i(720, 540)
		view.transparent_bg = true
		view.own_world_3d = true
		view.msaa_3d = Viewport.MSAA_4X
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var scene: Node3D = Node3D.new()
		view.add_child(scene)
		var env: Environment = Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("6a78a8")
		env.ambient_light_energy = 0.75
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.glow_enabled = true
		env.glow_intensity = 0.6
		var holder: WorldEnvironment = WorldEnvironment.new()
		holder.environment = env
		scene.add_child(holder)
		var moon: DirectionalLight3D = DirectionalLight3D.new()
		moon.light_color = Color("c8d6ff")
		moon.light_energy = 0.8
		moon.shadow_enabled = true
		moon.rotation_degrees = Vector3(-50, -25, 0)
		scene.add_child(moon)
		var lay: Dictionary = Venue.layout(id, int(catalog.get_item("venues", id).max_tables))
		var building: Node3D = Node3D.new()
		scene.add_child(building)
		Venue.build_exterior(building, lay, "owned")
		var camera: Camera3D = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = (lay.w + lay.d) * 0.8
		camera.rotation_degrees = Vector3(-24, 45, 0)
		var height: float = 4.0 if id == "splav" else 3.4 * float(Venue.THEMES[id].storeys) * 0.5
		camera.position = Vector3(lay.w / 2.0, height, lay.d / 2.0) + camera.transform.basis.z * 80.0
		scene.add_child(camera)
		camera.make_current()
		for i in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = view.get_texture().get_image()
		image.save_png(out.path_join(id + ".png"))
		view.queue_free()
		await process_frame
	for level in People.BAND_LINEUPS:
		var lineup: Array = People.BAND_LINEUPS[level]
		await _people(ProjectSettings.globalize_path("res://assets/ui/bands"), level, lineup.map(func(m): return "musician:" + str(m)), "play")
	for kind in ["penzioner", "studenti", "ozalosceni", "svatovi", "biznismen"]:
		await _people(ProjectSettings.globalize_path("res://assets/ui/guests"), kind, [kind, kind, kind], "idle")
	print("Interface pictures rendered under res://assets/ui")
	quit()

## A small group of characters on a disc of floor, posed, lit warm from the front.
func _people(out: String, name: String, kinds: Array, pose: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var view: SubViewport = SubViewport.new()
	view.size = Vector2i(560, 420)
	view.transparent_bg = true
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var scene: Node3D = Node3D.new()
	view.add_child(scene)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a7a90")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = env
	scene.add_child(holder)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.light_color = Color("ffe2b8")
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-35, 25, 0)
	scene.add_child(key)
	var count: int = kinds.size()
	var spacing: float = 0.85
	for k in range(count):
		var person = People.new()
		scene.add_child(person)
		person.setup(People.make_look(str(kinds[k]), k + (3 if pose == "idle" else 0)))
		var x: float = (k - (count - 1) / 2.0) * spacing
		person.position = Vector3(x, 0, -absf(x) * 0.25)
		person.face_now(Vector3(-x * 0.3, 0, 1))
		person.play(pose)
		# One step of animation and face, then hold still (no blink mid-picture).
		person.blink_in = 99.0
		person._process(0.5 + k * 0.37)
		person.set_process(false)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = maxf(2.8, count * spacing + 1.0)
	camera.rotation_degrees = Vector3(-12, 0, 0)
	camera.position = Vector3(0, 1.0, 0) + camera.transform.basis.z * 20.0
	scene.add_child(camera)
	camera.make_current()
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(out.path_join(name + ".png"))
	view.queue_free()
	await process_frame
