extends Node
## Domain notifications. UI listens; the simulation never depends on controls.
signal state_changed
signal event_raised(event: Dictionary)
signal event_resolved(outcome: Dictionary)
signal song_played(song_id: String)
signal notice(key: String, args: Dictionary)
signal offline_ready(result: Dictionary)
signal save_conflict(server: Dictionary)
signal leaderboard_ready(result: Dictionary)
signal locale_changed
signal sync_status_changed(status: String)
signal audio_requested(cue: String)
