extends Node
## The kafana's sound: the band's music and the small sounds of the room.
##
## While a song is on, its own tune plays (assets/audio/songs/<song id>.ogg); between songs the band
## plays something quieter that suits the venue (between_<venue>.ogg). Changes cross-fade. Cues from
## EventBus.audio_requested play short sounds (assets/audio/sfx). Music and sound follow the
## settings. Everything here is made by tools/audio/kafana_music.py.
const SONGS = "res://assets/audio/songs/"
const SFX = "res://assets/audio/sfx/"
const SONG_DB = -4.0
const BETWEEN_DB = -9.0
const MAP_DB = -6.0
const FADE = 1.4
## The sounds are normalised near full scale: this keeps two of them over a song clear of clipping.
const SFX_DB = -10.0
## The same sound is not started twice within this many milliseconds (a row of payouts is one coin).
const SFX_GAP_MS = 140
const CUES = {"order_served": "clink", "order_started": "pour", "purchase": "coin", "payout": "coin",
	"glass_break": "break", "event": "sting", "venue_opened": "fanfare", "request_matched": "clink"}

var players: Array = []
var active: int = 0
var track: String = ""
var sfx_players: Array = []
var next_sfx: int = 0
var sfx_started: Dictionary = {}
var cache: Dictionary = {}
## Set by the floor view: true while the whole map is in view (the music goes quieter).
var on_map: bool = false

func _ready() -> void:
	for i in range(2):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.volume_db = -80.0
		add_child(player)
		players.append(player)
	for i in range(4):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.volume_db = SFX_DB
		add_child(player)
		sfx_players.append(player)
	EventBus.audio_requested.connect(play_cue)

func _stream(path: String) -> AudioStream:
	if cache.has(path):
		return cache[path]
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = path.begins_with(SONGS)
	cache[path] = stream
	return stream

func _wanted() -> Dictionary:
	if not bool(SaveSystem.settings.get("music", true)):
		return {"path": "", "db": -80.0}
	var sim = GameState.simulation
	var song: String = str(sim.current_song)
	var extra: float = MAP_DB if on_map else 0.0
	if sim.song_remaining > 0.0 and not song.is_empty() and ResourceLoader.exists(SONGS + song + ".ogg"):
		return {"path": SONGS + song + ".ogg", "db": SONG_DB + extra}
	return {"path": SONGS + "between_" + str(GameState.save.get("venue", "birtija")) + ".ogg", "db": BETWEEN_DB + extra}

func _process(delta: float) -> void:
	var wanted: Dictionary = _wanted()
	var path: String = wanted.path
	if path != track:
		track = path
		active = 1 - active
		var player: AudioStreamPlayer = players[active]
		var stream: AudioStream = _stream(path) if not path.is_empty() else null
		player.stop()
		if stream != null:
			player.stream = stream
			player.volume_db = -40.0
			player.play()
	var step: float = delta / FADE * 40.0
	for i in range(players.size()):
		var player: AudioStreamPlayer = players[i]
		var target: float = float(wanted.db) if i == active and not track.is_empty() else -80.0
		player.volume_db = move_toward(player.volume_db, target, step if player.volume_db < target else step * 1.5)
		if i != active and player.playing and player.volume_db <= -79.0:
			player.stop()

func play_cue(cue: String) -> void:
	if not bool(SaveSystem.settings.get("sound", true)) or not CUES.has(cue):
		return
	var sound: String = str(CUES[cue])
	var now: int = Time.get_ticks_msec()
	if now - int(sfx_started.get(sound, -SFX_GAP_MS)) < SFX_GAP_MS:
		return
	var stream: AudioStream = _stream(SFX + sound + ".ogg")
	if stream == null:
		return
	sfx_started[sound] = now
	var player: AudioStreamPlayer = sfx_players[next_sfx]
	next_sfx = (next_sfx + 1) % sfx_players.size()
	player.stream = stream
	player.pitch_scale = randf_range(0.96, 1.04)
	player.play()
