extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if OS.get_environment("DO_ZORE_TEST_USER_DIR").is_empty():
		quit(2)
		return
	await process_frame
	var game: Node = root.get_node("GameState")
	var storage: Node = root.get_node("SaveSystem")
	game.set_process(false)
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("DO_ZORE_TEST_OUTPUT")))
	if not storage.had_existing_save or int(game.save.money) != int(fixtures.backup_expected_money) or str(storage.settings.language) != str(fixtures.backup_expected_language):
		printerr("FAIL corrupt-primary restart did not recover expected backup")
		quit(1)
		return
	print("PASS fresh-process restart recovers corrupt primary from backup")
	quit(0)
