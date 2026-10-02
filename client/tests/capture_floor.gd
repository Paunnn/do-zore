extends SceneTree
## Rendered showcase of every venue at the design resolution: a full room with a song playing.
## Needs DO_ZORE_CAPTURE_OUTPUT and DO_ZORE_TEST_USER_DIR, like capture_ui.gd.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var destination: String = OS.get_environment("DO_ZORE_CAPTURE_OUTPUT")
	if destination.is_empty() or OS.get_environment("DO_ZORE_TEST_USER_DIR").is_empty():
		push_error("Capture requires DO_ZORE_CAPTURE_OUTPUT and DO_ZORE_TEST_USER_DIR")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	await process_frame
	var game = root.get_node("GameState")
	game.set_process(false)
	root.size = Vector2i(1080, 1920)
	var scene = null
	var bands: Dictionary = {"birtija": "solo_harmonikas", "kafana": "trio", "restoran": "tamburaski_orkestar", "splav": "pevacica"}
	var kinds: Array = ["penzioner", "studenti", "svatovi", "biznismen", "ozalosceni"]
	for venue in ["birtija", "kafana", "restoran", "splav"]:
		game.reset_progress()
		game.save.money = 250000
		game.save.venue = venue
		game.save.band_level = bands[venue]
		game.save.upgrades = {"dodatni_sto": 8, "konobar": 4, "dekor": 5, "ozvucenje": 5, "izbacivac": 1, "sef": 1}
		game._unlock_free_songs()
		game.simulation.refresh_tables()
		var sim = game.simulation
		sim.arrival_remaining = 1000000.0
		sim.event_roll_remaining = 1000000.0
		sim.condition_remaining = 1000000.0
		for index in range(mini(sim.tables.size(), 9)):
			sim.spawn_guest(kinds[index % kinds.size()], index)
			sim.tables[index].mood = [80.0, 55.0, 90.0, 25.0, 65.0][index % 5]
		sim.serve_table(1)
		if scene == null:
			scene = load("res://scenes/main.tscn").instantiate()
			root.add_child(scene)
		scene._open_tab("floor")
		sim.play_song(str(game.known_songs()[0].id))
		for frame in range(30):
			await process_frame
		await capture(destination, "venue-" + venue)
	print("Rendered venue showcase: " + destination)
	quit()

func capture(destination: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(destination.path_join(name + ".png"))
