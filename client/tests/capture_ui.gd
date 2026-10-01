extends SceneTree
## Optional rendered smoke test; capture directory and save sandbox must be explicit.
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
	game.simulation.spawn_guest("penzioner", 0)
	game.simulation.spawn_guest("studenti", 1)
	game.simulation.spawn_guest("ozalosceni", 2)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for dimensions in [Vector2i(450, 800), Vector2i(450, 1000), Vector2i(768, 1024)]:
		root.size = dimensions
		scene._open_tab("floor")
		await capture(destination, "floor-%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(450, 800)
	for tab in ["band", "menu", "upgrades", "venues", "settings", "leaderboard"]:
		scene._open_tab(tab)
		await create_timer(0.5).timeout
		await capture(destination, tab)
	scene._open_tab("floor")
	scene._show_songs(0)
	await capture(destination, "song")
	scene._close_modal()
	game.simulation.trigger_event("inspekcija")
	await capture(destination, "event")
	scene._close_modal(false)
	scene._show_offline(root.get_node("Economy").offline_earnings(game.export_save(), 3600))
	await capture(destination, "offline")
	scene._show_conflict({"save": game.export_save(), "version": 2})
	await capture(destination, "conflict")
	scene._close_modal(false)
	root.get_node("SaveSystem").set_setting("language", "en")
	scene._open_tab("floor")
	await capture(destination, "floor-en")
	print("Rendered UI captures: " + destination)
	quit()

func capture(destination: String, name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(destination.path_join(name + ".png"))
