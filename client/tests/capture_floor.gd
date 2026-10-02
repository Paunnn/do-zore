extends SceneTree
## Rendered showcase of the floor scene at the design resolution: a busy night with a song
## playing, orders in every state and one table about to start a fight.
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
	game.reset_progress()
	game.save.money = 250000
	game.save.upgrades["dodatni_sto"] = 3
	game.simulation.refresh_tables()
	var sim = game.simulation
	sim.arrival_remaining = 1000000.0
	sim.event_roll_remaining = 1000000.0
	sim.condition_remaining = 1000000.0
	for entry in [["penzioner", 0], ["studenti", 1], ["svatovi", 2], ["biznismen", 3], ["ozalosceni", 4]]:
		sim.spawn_guest(entry[0], entry[1])
	sim.serve_table(1)
	sim.tables[2].mood = 92.0
	sim.tables[3].mood = 20.0
	sim.tables[4].mood = 75.0
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1080, 1920)
	scene._open_tab("floor")
	sim.play_song(str(game.known_songs()[0].id))
	sim.room_mood = 80.0
	sim.tables[2].dancing = true
	for frame in range(40):
		await process_frame
	await capture(destination, "showcase-top")
	scene.floor_view.scroll.scroll_vertical = 700
	for frame in range(10):
		await process_frame
	await capture(destination, "showcase-scrolled")
	sim.trigger_event("inspekcija")
	scene._close_modal(false)
	sim.choose_event("zatvori")
	scene._close_modal(false)
	scene.modal_queue.clear()
	for frame in range(10):
		await process_frame
	await capture(destination, "showcase-closed")
	print("Rendered floor showcase: " + destination)
	quit()

func capture(destination: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(destination.path_join(name + ".png"))
