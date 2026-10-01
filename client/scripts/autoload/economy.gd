extends Node
const Math = preload("res://scripts/simulation/economy_math.gd")

func stat(player_save: Dictionary, stat_name: String, base: float = 1.0) -> float:
	return Math.stat(DataCatalog.data, player_save, stat_name, base)

func upgrade_cost(id: String, owned_level: int) -> int:
	return Math.upgrade_cost(DataCatalog.data, id, owned_level)

func offline_earnings(player_save: Dictionary, away_seconds: float) -> Dictionary:
	var api: Node = get_node_or_null("/root/ApiClient")
	var live_events: Array = []
	if api != null:
		live_events = api.live_events
	return Math.offline_earnings(DataCatalog.data, player_save, away_seconds, live_events)

func grant(amount: int, is_tip: bool = false) -> void:
	GameState.simulation.grant(amount, is_tip)
	EventBus.state_changed.emit()

func spend(amount: int) -> bool:
	var success: bool = GameState.simulation.spend(amount)
	if success:
		EventBus.state_changed.emit()
	return success
