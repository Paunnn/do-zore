extends Node3D
## One person: guests, waiters, the bartender, the bouncer, the band and the people in the streets.
##
## Cartoon people built in Blender from MakeHuman bodies (tools/art/people, assets/people, CC0):
## a big round head, short legs, big hands, clothes and hair, one skinned mesh with one material.
## Their faces are drawn by the shader (shaders/person.gdshader): eyes, brows and mouth come from a
## handful of numbers, so every person can smile, laugh, sing, frown, cry or blink at any moment.
## The motion is Quaternius' Universal Animation Library (CC0), retargeted on import through Godot's
## humanoid profile; a few clips are put together here (sitting legs with drinking or cheering
## arms), and the head, arms and props are touched up in code.
##
## The node's position is the character's feet; it walks along world-space paths and turns to
## face where it goes.
signal arrived

const Builder = preload("res://scripts/world3d/builder.gd")
const Kit = preload("res://scripts/world3d/kit3d.gd")
const MODELS = "res://assets/people/"
const PERSON_SHADER = preload("res://shaders/person.gdshader")
const INK_SHADER = preload("res://shaders/ink.gdshader")
const WALK_SPEED = 2.0
## How early a walker turns into the next leg of a path (metres before the corner).
const CORNER = 0.3

## The cartoon women's head radius (head box units, round the headscarf's centre): rows every 20
## degrees down from the crown, columns every 20 degrees from the back of the head to the face.
const HEAD_ROUND: Array = [
	[0.48, 0.48, 0.48, 0.48, 0.48, 0.48, 0.48, 0.48, 0.48, 0.50],
	[0.48, 0.48, 0.48, 0.48, 0.48, 0.48, 0.49, 0.52, 0.52, 0.53],
	[0.48, 0.49, 0.48, 0.47, 0.46, 0.47, 0.49, 0.53, 0.54, 0.54],
	[0.48, 0.49, 0.48, 0.46, 0.45, 0.45, 0.46, 0.51, 0.54, 0.54],
	[0.48, 0.48, 0.48, 0.46, 0.44, 0.43, 0.45, 0.52, 0.53, 0.54],
	[0.49, 0.49, 0.50, 0.48, 0.57, 0.50, 0.54, 0.57, 0.62, 0.66],
	[0.50, 0.49, 0.50, 0.50, 0.61, 0.62, 0.62, 0.67, 0.75, 0.75],
	[0.52, 0.52, 0.53, 0.53, 0.53, 0.60, 0.65, 0.70, 0.72, 0.72],
]

## How far the bride's hair and bun reach out from the middle of her head (head box units): rows
## every 0.1 down from 0.45 above the middle, columns every 20 degrees from the back to the side.
const VEIL_ROUND: Array = [
	[0.41, 0.33, 0.12, 0.14, 0.21, 0.24],
	[0.45, 0.46, 0.46, 0.30, 0.35, 0.38],
	[0.46, 0.51, 0.50, 0.34, 0.39, 0.42],
	[0.44, 0.52, 0.53, 0.37, 0.41, 0.45],
	[0.49, 0.52, 0.53, 0.39, 0.42, 0.46],
	[0.50, 0.52, 0.50, 0.39, 0.43, 0.45],
	[0.48, 0.49, 0.38, 0.38, 0.42, 0.49],
	[0.22, 0.25, 0.30, 0.35, 0.40, 0.50],
	[0.20, 0.19, 0.20, 0.30, 0.36, 0.50],
	[0.11, 0.13, 0.17, 0.15, 0.23, 0.46],
	[0.00, 0.04, 0.00, 0.05, 0.12, 0.17],
]
## People are drawn a little larger than the furniture, so faces read on a phone.
const SIZE = 1.2
## Metres per second the walk clip covers at rate 1 for a hip height of one metre; the clip runs
## faster for shorter legs so the feet don't slide.
const STRIDE = 1.45
## Chairs: the top of the seat, how high the hips sit above it (model units), how far a chair
## slides out to let someone sit down or get up, and how far behind its centre the hips sit.
const SEAT_TOP = 0.51
const HIP_OVER_SEAT = 0.075
const CHAIR_PULL = 0.4
const SEAT_BACK = 0.0
## The table top (with its cloth) above the floor, and its near edge ahead of a tucked-in chair.
const TABLE_TOP = 0.8
const TABLE_REACH = 0.29
## A drink: reach for the glass, lift it, sip, put it down, let go (seconds from the start).
const DRINK_REACH = 0.45
const DRINK_LIFT = 0.95
const DRINK_SIP = 1.95
const DRINK_DOWN = 2.45
const DRINK_END = 2.85
## Vessels on the table, per drink: radius and height in metres (drawn a little big, like the
## hands), and how far they tip at the mouth.
const VESSELS = {
	"cup": [0.05, 0.085, 0.7], "mug": [0.065, 0.17, 1.0], "shot": [0.035, 0.085, 1.3],
	"wine": [0.05, 0.19, 0.9], "tumbler": [0.055, 0.1, 0.9], "flute": [0.032, 0.2, 1.0],
	"water": [0.05, 0.15, 0.9],
}
## How far a head tips back so the face reads from the high camera.
const HEAD_LIFT = 0.28
## Who plays in each band level, left to right on the stage.
const BAND_LINEUPS = {
	"solo_harmonikas": ["accordion"],
	"trio": ["guitar", "accordion", "bass"],
	"tamburaski_orkestar": ["tamburica", "violin", "accordion", "tamburica", "bass"],
	"pevacica": ["guitar", "tamburica", "mic", "accordion", "violin", "bass"],
}
const LOWER_BODY = ["Root", "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]
const LEFT_ARM = ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"]
const RIGHT_ARM = ["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
## Bones the code poses on top of the clips (head, spine, arms for reaching and playing).
const TOUCHED = ["Head", "Neck", "Spine", "Chest", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand"]
## Expressions: eyes (open, squint, look x, look y), brows (lift, angry, worry), mouth (smile, open,
## round, width), extra (blush, tears, happy closed eyes, wink).
const FACES = {
	"neutral": [Vector4(1, 0, 0, 0), Vector4(0, 0, 0, 0), Vector4(0.3, 0, 0, 1), Vector4(0.45, 0, 0, 0)],
	"smile": [Vector4(0.9, 0.35, 0, 0), Vector4(0.3, 0, 0, 0), Vector4(1, 0, 0, 1.1), Vector4(0.6, 0, 0, 0)],
	"grin": [Vector4(0.85, 0.4, 0, 0), Vector4(0.4, 0, 0, 0), Vector4(1, 0.35, 0, 1.15), Vector4(0.7, 0, 0, 0)],
	"laugh": [Vector4(0.0, 0.6, 0, 0), Vector4(0.6, 0, 0, 0), Vector4(1, 0.7, 0, 1.15), Vector4(0.8, 0, 1, 0)],
	"angry": [Vector4(0.8, 0.35, 0, 0), Vector4(-0.3, 1, 0, 0), Vector4(-0.6, 0.0, 0, 0.9), Vector4(0.0, 0, 0, 0)],
	"shout": [Vector4(1, 0.2, 0, 0), Vector4(-0.2, 1, 0, 0), Vector4(-0.3, 0.9, 0.2, 1.1), Vector4(0.1, 0, 0, 0)],
	"sad": [Vector4(0.75, 0.0, 0, 0.4), Vector4(0.2, 0, 1, 0), Vector4(-0.8, 0.0, 0, 0.8), Vector4(0.0, 0.8, 0, 0)],
	"glum": [Vector4(0.7, 0.0, 0, 0.3), Vector4(0.1, 0, 0.8, 0), Vector4(-0.6, 0.0, 0, 0.85), Vector4(0.0, 0, 0, 0)],
	"surprise": [Vector4(1, 0, 0, 0), Vector4(1, 0, 0.3, 0), Vector4(0, 0.55, 1, 1), Vector4(0.2, 0, 0, 0)],
	"tipsy": [Vector4(0.45, 0.2, 0.3, 0.2), Vector4(0.4, 0, 0.5, 0), Vector4(0.7, 0.15, 0, 1), Vector4(1.0, 0, 0, 0.3)],
	"sing": [Vector4(0.05, 0.0, 0, 0), Vector4(0.7, 0, 0.8, 0), Vector4(0.2, 0.8, 0.6, 1), Vector4(0.5, 0, 0, 0)],
	"blissful": [Vector4(0.0, 0.4, 0, 0), Vector4(0.5, 0, 0.3, 0), Vector4(0.9, 0.0, 0, 1.0), Vector4(0.6, 0, 1, 0)],
	"sip": [Vector4(0.3, 0.2, 0, 0), Vector4(0.3, 0, 0, 0), Vector4(0.2, 0.25, 1, 0.8), Vector4(0.6, 0, 0, 0)],
	"gulp": [Vector4(0.0, 0.3, 0, 0), Vector4(0.6, 0, 0.2, 0), Vector4(0.1, 0.12, 1, 0.65), Vector4(0.8, 0, 1, 0)],
	"whistle": [Vector4(0.9, 0.1, 0.4, -0.2), Vector4(0.4, 0, 0, 0), Vector4(0.0, 0.2, 1, 0.7), Vector4(0.3, 0, 0, 0)],
}
const SKIN = ["f6d2b4", "f2c6a0", "e8b48f", "dba27e", "f3cba8", "c98e6a"]
const HAIR = ["2b1d14", "4a3020", "7a5230", "c9a26a", "1a1a1e", "8a3a22", "a2552c"]
const GREY_HAIR = ["d8d4cc", "c9c4ba", "e8e4dc", "b4aea4"]
const EYES = ["5a3a22", "3b2a1c", "4a6a8a", "3f6b45", "6b4426"]
const BRIGHT = ["e85a4f", "3e8ed0", "f2b83a", "4fae6a", "9a5ad0", "f4f1ea", "2fb5a8", "f28a3a"]
const DENIM = ["3a5a8a", "2b2f45", "5a6a7a", "6a4a3a", "4a4a52"]

static var _library: AnimationLibrary
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _measures: Dictionary = {}
static var _prop_ink: ShaderMaterial
static var _front_sign: float = 0.0

var look: Dictionary = {}
var model: Node3D
var skeleton: Skeleton3D
var body: MeshInstance3D
var player: AnimationPlayer
var bones: Dictionary = {}
var hand: Node3D
## A waiter's tray (on the left hand, kept level: see _carry_pose).
var tray: MeshInstance3D
var instrument: Node3D
var current: String = ""
var clip: String = ""
var rate: float = 1.0
var anim_time: float = 0.0
var path: PackedVector3Array = PackedVector3Array()
var speed_scale: float = 1.0
var heading: float = 0.0
var target_heading: float = 0.0
var phase: float = 0.0
var holding: String = ""
var measure: Dictionary = {}
## The face being shown, eased towards `mood` (plus blinks, talking and short emotes).
var face_now_values: Array = []
var mood: String = "neutral"
var emote_name: String = ""
var emote_left: float = 0.0
var blink_in: float = 2.0
var talking: bool = false
## Seating: the chair ({"chair": tucked-in centre, "dir": towards the table, "move": Callable(pull)},
## venue space), where in sitting down or getting up the person is, and how far the chair is out.
var seat: Dictionary = {}
var seat_state: String = ""
var seat_time: float = 0.0
var pull: float = 0.0
var after_rising: Callable
## The person's own glass or cup on the table, where it stands, and the drink in progress.
var vessel: Node3D
var vessel_rest: Transform3D
var vessel_kind: String = ""
var sip_time: float = -1.0
var sip_in: float = 2.0
## How much the musician is playing (eases in and out with the song).
var play_amount: float = 0.0
## Walking: how far into a walk (eases in), and this person's own pace.
var gait: float = 0.0
var pace: float = 1.0

# ---------------------------------------------------------------------------------------------
# Looks
# ---------------------------------------------------------------------------------------------

## A look for a guest type (or "waiter", "bartender", "bouncer", "musician:<instrument>"): the model,
## the palette, the face's style and age, and the props (a cap, a scarf, a backpack...). The cast
## follows the guest types: penzioneri with flat caps, šajkače, headscarves and moustaches; classic
## students with backpacks; wedding guests with the bride in her veil; businessmen in suits.
static func make_look(kind: String, variant: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var pick: Callable = func(options: Array) -> String: return options[rng.randi() % options.size()]
	var female: bool = variant % 2 == 1
	var second: bool = (variant / 2) % 2 == 1
	var look: Dictionary = {"kind": kind, "variant": variant, "female": female, "model": "student", "hat": "",
		"extra": "", "instrument": "", "build": 1.0, "mood": "smile", "props": [], "age": Vector4.ZERO,
		"hunch": 0.0, "pace": 1.0,
		"pal": {"col_skin": pick.call(SKIN), "col_hair": pick.call(HAIR), "col_eye": pick.call(EYES),
			"col_top": pick.call(BRIGHT), "col_bottom": pick.call(DENIM), "col_shoes": "3a2a1e", "col_hat": "5e5d40"},
		"style": Vector4(1, 0.85, 0.5, 0) if female else Vector4(0, 1.25, 0, 0)}
	match kind:
		"penzioner":
			look.pal.col_hair = pick.call(GREY_HAIR)
			look.mood = "smile"
			look.hunch = 0.16
			look.pace = 0.8
			look.age = Vector4(1.0, 0, 0, 0.9)
			if female:
				look.model = "baba2" if second else "baba"
				look.pal.col_top = pick.call(["3a4a6a", "6a2a3a", "5a6a4a", "4a3a5a", "6e5a44", "7a3a4a"])
				look.style = Vector4(1, 0.9, 0.35, 1.0 if rng.randf() < 0.6 else 0.0)
				if second:
					look.props.append(["marama", pick.call(["b84a5a", "3e5f8a", "4f7a4a", "8a5aa0", "c98a3a"])])
			else:
				look.model = ["deda", "deda2", "deda3"][(variant / 2) % 3]
				look.pal.col_top = pick.call(["8a5a36", "6e5a44", "5a6a4a", "7a6a52", "4a5568", "8a3a32"])
				look.pal.col_bottom = pick.call(["4f5357", "5a4a3a", "3a3a40"])
				look.pal.col_hat = pick.call(["4a4a50", "5a4a3a", "3a3a40", "6a6458"])
				look.age.y = 2.0 if rng.randf() < 0.6 else 1.0
				look.style.w = 1.0 if rng.randf() < 0.35 else 0.0
				if look.model == "deda3":
					look.props.append(["sajkaca", "7d7b5c"])
		"studenti":
			look.mood = "grin"
			if female:
				look.model = "studentkinja2" if second else "studentkinja"
				look.style.w = 1.0 if second or rng.randf() < 0.2 else 0.0
			else:
				look.model = "student2" if second else "student"
				look.style.w = 1.0 if rng.randf() < 0.25 else 0.0
				look.age.z = 0.3 if rng.randf() < 0.3 else 0.0
				if second:
					look.props.append(["beanie", pick.call(["d8423a", "3e6fb0", "f2b83a", "2b2f45", "4fae6a"])])
			if rng.randf() < 0.65:
				look.props.append(["backpack", pick.call(["d8423a", "3e8ed0", "f2b83a", "2fb5a8", "9a5ad0", "2b2f45"])])
		"svatovi":
			look.mood = "laugh"
			if female:
				if variant % 8 == 1:
					look.model = "mlada"
					look.pal.col_top = "f8f6f2"
					look.props.append(["veil", "fbfaf7"])
				else:
					look.model = "svatica"
					look.pal.col_top = pick.call(["d9536a", "f2b83a", "4aa8c9", "b05ad0", "e88aa8", "3f9d6a"])
					look.props.append(["wreath", ""])
			else:
				look.model = "svat2" if second else "svat"
				look.extra = "flower"
				if second:
					look.pal.col_top = pick.call(["7a2a3a", "2f4a7a", "5a3a6a", "3a5a3a"])
					look.props.append(["sajkaca", "6a6a58"])
					look.age = Vector4(0.6, 1, 0, 0.4)
		"biznismen":
			look.mood = "neutral"
			if female:
				look.model = "biznismenka"
				look.style.w = 2.0 if rng.randf() < 0.3 else 0.0
			else:
				look.model = "biznismen2" if second else "biznismen"
				look.style.w = 2.0 if rng.randf() < 0.45 else 0.0
				if second:
					look.props.append(["chain", ""])
					look.age = Vector4(0.4, 1, 0, 0.3)
		"ozalosceni":
			look.model = "ozaloscena" if female else "ozaloscen"
			look.pal.col_top = "26262c"
			look.pal.col_hair = pick.call(["2b1d14", "1a1a1e", "4a3020", "9a948a"])
			look.style.z = 0.0
			look.mood = "sad"
			if female:
				look.props.append(["marama", "1d1d22"])
			elif not female:
				look.age = Vector4(0.3, 1.0 if rng.randf() < 0.5 else 0.0, 0.0, 0.2)
		"waiter":
			look.model = "konobarica" if female else "konobar"
			look.pal.col_top = "f4f1ea"
			look.pal.col_bottom = "1d1d22"
			if female:
				look.props.append(["apron", ""])
		"bartender":
			look.model = "sanker"
			look.female = false
			look.pal.col_top = "f4f1ea"
			look.pal.col_bottom = "1d1d22"
			look.pal.col_hair = "3a2416"
			look.extra = "bowtie"
			look.style = Vector4(0, 1.3, 0, 0)
			look.age = Vector4(0.3, 1, 0, 0.2)
			look.mood = "neutral"
		"bouncer":
			look.model = "izbacivac"
			look.female = false
			look.pal.col_top = "1d1d22"
			look.pal.col_bottom = "2b2b30"
			look.style = Vector4(0, 1.5, 0, 2)
			look.age = Vector4(0, 0, 0.5, 0)
			look.mood = "neutral"
		_:
			if kind.begins_with("musician:"):
				look.instrument = kind.split(":")[1]
				look.female = look.instrument == "mic"
				if look.female:
					look.model = "pevacica"
					look.pal.col_top = "c0242f"
					look.pal.col_hair = "1a1a1e"
					look.style = Vector4(1, 0.85, 1, 0)
					look.mood = "sing"
				else:
					look.model = "muzicar"
					look.pal.col_top = ["8a1f22", "1d2433", "2f5a35", "f4f1ea"][variant % 4]
					look.pal.col_bottom = "1d1d22"
					look.extra = "bowtie"
					look.style = Vector4(0, 1.25, 0, 0)
					look.mood = "blissful"
					if look.instrument == "accordion" or rng.randf() < 0.4:
						look.age = Vector4(0.3, 2.0 if look.instrument == "accordion" else 1.0, 0, 0.3)
	return look

# ---------------------------------------------------------------------------------------------
# Shared resources
# ---------------------------------------------------------------------------------------------

## The animation library: the retargeted clips plus a few put together from two of them.
static func library() -> AnimationLibrary:
	if _library != null:
		return _library
	var scene: Node = load(MODELS + "people_anims.glb").instantiate()
	var source: AnimationLibrary = scene.get_node("AnimationPlayer").get_animation_library("")
	_library = AnimationLibrary.new()
	for name in source.get_animation_list():
		var anim: Animation = source.get_animation(name).duplicate()
		anim.loop_mode = Animation.LOOP_NONE if name in ["Sitting_Enter", "Sitting_Exit"] else Animation.LOOP_LINEAR
		_library.add_animation(name, anim)
	scene.free()
	_compose("Sit_Drink", {"Sitting_Idle": LOWER_BODY}, "Consume")
	_compose("Sit_Cheer", {"Sitting_Talking": LOWER_BODY}, "Yes")
	_compose("Sit_No", {"Sitting_Talking": LOWER_BODY}, "Idle_No")
	_compose("Sit_Clap", {"Sitting_Talking": LOWER_BODY}, "Dance")
	_compose("Hold_Tray", {"Idle": LOWER_BODY}, "Walk_Carry")
	_compose("Play_Squeeze", {"Idle": LOWER_BODY}, "Walk_Carry")
	_compose("Play_Strum", {"Idle": LOWER_BODY, "Spell_Simple_Idle": LEFT_ARM}, "Walk_Carry")
	_compose("Play_Sing", {"Idle": LOWER_BODY}, "Spell_Simple_Idle")
	return _library

## A clip made of `base` with the bones listed in `parts` taken from other clips. Keys of the
## borrowed tracks repeat to cover the base clip's length.
static func _compose(name: String, parts: Dictionary, base: String) -> void:
	var main: Animation = _library.get_animation(base)
	var out: Animation = Animation.new()
	out.length = main.length
	out.loop_mode = Animation.LOOP_LINEAR
	var taken: Dictionary = {}
	for other in parts:
		for bone in parts[other]:
			taken[bone] = other
	for t in range(main.get_track_count()):
		if not taken.has(main.track_get_path(t).get_concatenated_subnames()):
			_copy_track(main, t, out, 0.0, main.length)
	for other in parts:
		var anim: Animation = _library.get_animation(other)
		for t in range(anim.get_track_count()):
			var bone: String = anim.track_get_path(t).get_concatenated_subnames()
			if taken.get(bone, "") != other:
				continue
			var start: float = 0.0
			while start < out.length:
				_copy_track(anim, t, out, start, out.length)
				start += maxf(anim.length, 0.1)
	_library.add_animation(name, out)

static func _copy_track(from: Animation, track: int, to: Animation, shift: float, end: float) -> void:
	var path: NodePath = from.track_get_path(track)
	var index: int = to.find_track(path, from.track_get_type(track))
	if index < 0:
		index = to.add_track(from.track_get_type(track))
		to.track_set_path(index, path)
		to.track_set_interpolation_type(index, from.track_get_interpolation_type(track))
	for k in range(from.track_get_key_count(track)):
		var time: float = from.track_get_key_time(track, k) + shift
		if time > end + 0.001:
			break
		to.track_insert_key(index, time, from.track_get_key_value(track, k))

## One toon material per model (each has its own texture atlas), with the ink outline pass.
static func _material(model_name: String, atlas: Texture2D) -> ShaderMaterial:
	if not _materials.has(model_name):
		var ink: ShaderMaterial = ShaderMaterial.new()
		ink.shader = INK_SHADER
		ink.set_shader_parameter("atlas", atlas)
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = PERSON_SHADER
		mat.set_shader_parameter("atlas", atlas)
		mat.next_pass = ink
		_materials[model_name] = mat
	return _materials[model_name]

## A bone's bind pose: mesh space to the bone's frame, as the skin deforms the mesh (falls back to
## the rest pose).
static func _bind(skeleton: Skeleton3D, skin: Skin, bone_name: String) -> Transform3D:
	if skin != null:
		var bone: int = skeleton.find_bone(bone_name)
		for i in range(skin.get_bind_count()):
			if skin.get_bind_name(i) == bone_name or (skin.get_bind_name(i) == "" and skin.get_bind_bone(i) == bone):
				return skin.get_bind_pose(i)
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone_name)).affine_inverse()

## Measures of a model, taken once: the head's box, the hip height, where the hips sit in the
## sitting clip and stand in the idle one, and where the mouth is (in the head bone's frame).
static func _measure(model_name: String, skeleton: Skeleton3D, mesh: Mesh, skin: Skin) -> Dictionary:
	if _measures.has(model_name):
		return _measures[model_name]
	var hips: int = skeleton.find_bone("Hips")
	# Mesh-space positions of the joints (the import's rest fixer moves the rests, not the mesh).
	var head_bind: Transform3D = _bind(skeleton, skin, "Head")
	var head_rest: Vector3 = head_bind.affine_inverse().origin
	var sit_hips: Vector3 = Vector3(0, 0.5, -0.2)
	var stand_hips: Vector3 = Vector3(0, 0.8, 0)
	for pair in [["Sitting_Idle", "sit"], ["Idle", "stand"]]:
		var anim: Animation = library().get_animation(pair[0])
		var track: int = anim.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
		if track >= 0:
			var at: Vector3 = (anim.track_get_key_value(track, 0) as Vector3) * skeleton.motion_scale
			if pair[1] == "sit": sit_hips = at
			else: stand_hips = at
	# The head's box (everything above the chin), the front of the chest and the mouth (the face
	# point the shader draws the mouth at), from the mesh.
	var neck: Vector3 = _bind(skeleton, skin, "Neck").affine_inverse().origin
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var face_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var head_box: AABB = AABB(head_rest, Vector3.ZERO)
	var chest_front: float = neck.z
	var chest_back: float = neck.z
	var hips_at: Vector3 = _bind(skeleton, skin, "Hips").affine_inverse().origin
	var waist_front: float = hips_at.z
	var mouth: Vector3 = head_rest + Vector3(0, 0.05, 0.15)
	var mouth_d: float = -1e9
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		if v.y > head_rest.y + 0.04:
			head_box = head_box.expand(v)
		elif v.y > neck.y - 0.16 and v.y < neck.y - 0.04 and absf(v.x) < 0.06:
			chest_front = maxf(chest_front, v.z)
			chest_back = minf(chest_back, v.z)
		if absf(v.y - hips_at.y - 0.06) < 0.03 and absf(v.x) < 0.08:
			waist_front = maxf(waist_front, v.z)
		# The face plane is a projection, so the inside of the closed mouth maps there too: take the
		# frontmost point near the mouth.
		if i < face_uv.size() and i < colors.size() and colors[i].g > 0.5 and colors[i].r < 0.1:
			if face_uv[i].distance_to(Vector2(0.5, 0.79)) < 0.06 and v.z > mouth_d:
				mouth_d = v.z
				mouth = v
	_measures[model_name] = {"head": head_box, "neck": neck, "chest_front": chest_front, "chest_back": chest_back,
		"waist": Vector3(0, hips_at.y + 0.06, waist_front),
		"hips": skeleton.get_bone_global_rest(hips).origin.y, "sit_hips": sit_hips, "stand_hips": stand_hips,
		"mouth": head_bind * mouth,
		"stride": STRIDE * skeleton.motion_scale}
	return _measures[model_name]

# ---------------------------------------------------------------------------------------------
# Props, hats and instruments (metres; the hand points along the bone's +y)
# ---------------------------------------------------------------------------------------------

static func _mesh(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var b: Builder = Builder.new()
		_accessory(b, kind)
		_meshes[kind] = b.mesh()
	return _meshes[kind]

## The ink outline drawn around props, hats and glasses, like around the people.
static func _ink() -> ShaderMaterial:
	if _prop_ink == null:
		_prop_ink = ShaderMaterial.new()
		_prop_ink.shader = INK_SHADER
		_prop_ink.set_shader_parameter("width_px", 1.1)
	return _prop_ink

## A sheet of cloth seen from both sides (an apron, a veil): the surface and, a few millimetres in
## towards `inside`, the same surface turned the other way, so its back shows cloth and not the
## outline pass.
static func _sheet(b: Builder, rows: Array, color: Color, key: String, inside: Vector3) -> void:
	_surface(b, rows, color, key, inside)
	var lining: Array = []
	var middle: Vector3 = Vector3.ZERO
	var count: int = 0
	for row in rows:
		var inner: PackedVector3Array = PackedVector3Array()
		for at in row:
			inner.append(at + (inside - at).normalized() * 0.004)
			middle += at
			count += 1
		lining.append(inner)
	middle /= float(count)
	_surface(b, lining, color.darkened(0.06), key, middle + (middle - inside) * 50.0)

## A smooth surface through rows of points (all rows the same length), its faces turned to the
## side the normals point to.
static func _surface(b: Builder, rows: Array, color: Color, key: String, inside: Vector3 = Vector3.INF) -> void:
	if _front_sign == 0.0:
		# Which way round Godot's own primitives wind their outward faces.
		var probe: Array = Kit.unit("sphere", 8)
		var pv: PackedVector3Array = probe[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = probe[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = probe[Mesh.ARRAY_INDEX]
		for t in range(0, pi.size(), 3):
			var g: Vector3 = (pv[pi[t + 1]] - pv[pi[t]]).cross(pv[pi[t + 2]] - pv[pi[t]])
			if g.length() > 1e-6:
				_front_sign = signf(g.dot(pn[pi[t]]))
				break
	var n_r: int = rows.size()
	var n_c: int = (rows[0] as PackedVector3Array).size()
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for r in range(n_r):
		for c in range(n_c):
			verts.append(rows[r][c])
	for r in range(n_r):
		for c in range(n_c):
			var du: Vector3 = rows[mini(r + 1, n_r - 1)][c] - rows[maxi(r - 1, 0)][c]
			var dv: Vector3 = rows[r][mini(c + 1, n_c - 1)] - rows[r][maxi(c - 1, 0)]
			var nn: Vector3 = du.cross(dv)
			nn = nn.normalized() if nn.length() > 1e-7 else Vector3.UP
			# A closed shape faces away from a point inside it (the loft's own sense is unreliable
			# where rows pinch to a point).
			if inside.is_finite() and nn.dot(rows[r][c] - inside) < 0.0:
				nn = -nn
			normals.append(nn)
	for r in range(n_r - 1):
		for c in range(n_c - 1):
			var a: int = r * n_c + c
			for tri in [[a, a + n_c, a + 1], [a + 1, a + n_c, a + n_c + 1]]:
				var g: Vector3 = (verts[tri[1]] - verts[tri[0]]).cross(verts[tri[2]] - verts[tri[0]])
				var nsum: Vector3 = normals[tri[0]] + normals[tri[1]] + normals[tri[2]]
				if inside.is_finite():
					nsum = (verts[tri[0]] + verts[tri[1]] + verts[tri[2]]) / 3.0 - inside
				if signf(g.dot(nsum)) != _front_sign:
					tri = [tri[0], tri[2], tri[1]]
				indices.append_array(PackedInt32Array(tri))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	b.add(arrays, Transform3D.IDENTITY, color, key)

## Adds a prop, hat or instrument to a builder (at the builder's offset).
static func _accessory(b: Builder, full_kind: String) -> void:
	var glass: Color = Color("e4f2f4")
	# "kind:rrggbb" picks the colour of cloth props.
	var kind: String = full_kind.get_slice(":", 0)
	var tint: Color = Color(full_kind.get_slice(":", 1)) if full_kind.contains(":") else Color("5e5d40")
	match kind:
		# Drinks (their base at the origin, the handle on the drinker's right, -x).
		"cup":
			# Fildžan: a small white porcelain cup with a blue band, black coffee at the top.
			b.cylinder(Vector3.ZERO, 0.04, 0.085, Color("f7f4ee"), "vc_gloss", 12, 1.25)
			b.cylinder(Vector3(0, 0.055, 0), 0.047, 0.012, Color("3e6fb0"), "vc_gloss", 12)
			b.cylinder(Vector3(0, 0.076, 0), 0.046, 0.006, Color("2a160c"), "vc", 12)
		"mug":
			# A beer mug: amber beer, a head of foam, a thick glass handle.
			b.cylinder(Vector3.ZERO, 0.065, 0.14, Color("e8a02e"), "vc_gloss", 12)
			b.cylinder(Vector3(0, 0.14, 0), 0.068, 0.035, Color("fbf6e8"), "vc", 12)
			b.sphere(Vector3(0, 0.172, 0), 0.06, Color("fbf6e8"), "vc", Vector3(1, 0.35, 1), 10)
			b.box(Vector3(-0.085, 0.03, 0), Vector3(0.02, 0.11, 0.03), glass, "vc_gloss")
			b.box(Vector3(-0.07, 0.125, 0), Vector3(0.04, 0.02, 0.03), glass, "vc_gloss")
			b.box(Vector3(-0.07, 0.03, 0), Vector3(0.04, 0.02, 0.03), glass, "vc_gloss")
		"shot":
			# Čokanjčić: a little rakija glass, flaring at the top.
			b.cylinder(Vector3.ZERO, 0.028, 0.085, glass, "vc_gloss", 10, 1.3)
			b.cylinder(Vector3(0, 0.01, 0), 0.027, 0.055, Color("f2dc8a"), "vc_gloss", 10, 1.2)
		"wine":
			b.cylinder(Vector3.ZERO, 0.04, 0.008, glass, "vc_gloss", 10)
			b.cylinder(Vector3.ZERO, 0.008, 0.09, glass, "vc_gloss", 6)
			b.sphere(Vector3(0, 0.13, 0), 0.05, Color("7a1426"), "vc_gloss", Vector3(1, 0.9, 1), 10)
			b.cylinder(Vector3(0, 0.13, 0), 0.046, 0.06, glass, "vc_gloss", 10, 0.9)
		"tumbler":
			b.cylinder(Vector3.ZERO, 0.055, 0.1, glass, "vc_gloss", 10)
			b.cylinder(Vector3(0, 0.008, 0), 0.051, 0.05, Color("c9822e"), "vc_gloss", 10)
			b.box(Vector3(0.0, 0.05, 0.0), Vector3(0.04, 0.035, 0.04), Color("f2fbff"), "vc_gloss")
		"flute":
			b.cylinder(Vector3.ZERO, 0.035, 0.008, glass, "vc_gloss", 10)
			b.cylinder(Vector3.ZERO, 0.007, 0.08, glass, "vc_gloss", 6)
			b.cylinder(Vector3(0, 0.08, 0), 0.026, 0.12, Color("f4d88a"), "vc_gloss", 10, 1.25)
		"water":
			b.cylinder(Vector3.ZERO, 0.045, 0.15, glass, "vc_gloss", 10, 1.1)
			b.cylinder(Vector3(0, 0.008, 0), 0.042, 0.1, Color("bfe4f2"), "vc_gloss", 10, 1.08)
		"tray", "tray_empty":
			# A round steel tray with a raised rim (model units), with the order on it.
			b.cylinder(Vector3.ZERO, 0.17, 0.014, Color("c9ced6"), "vc_metal", 16)
			b.cylinder(Vector3(0, 0.012, 0), 0.172, 0.014, Color("dfe3e8"), "vc_metal", 16, 1.04)
			if kind == "tray":
				b.cylinder(Vector3(0.05, 0.014, 0.04), 0.03, 0.1, Color("dfeff0"), "vc_gloss", 8)
				b.cylinder(Vector3(0.05, 0.016, 0.04), 0.027, 0.06, Color("e8b84a"), "vc_gloss", 8)
				b.cylinder(Vector3(-0.06, 0.014, 0.03), 0.03, 0.1, Color("dfeff0"), "vc_gloss", 8)
				b.cylinder(Vector3(-0.06, 0.016, 0.03), 0.027, 0.06, Color("c9402f"), "vc_gloss", 8)
				b.cylinder(Vector3(0.0, 0.014, -0.07), 0.032, 0.13, Color("3d8a4f"), "vc_gloss", 8)
				b.cylinder(Vector3(0.0, 0.144, -0.07), 0.012, 0.05, Color("2f6a3a"), "vc_gloss", 6)
		"cloth":
			b.box(Vector3(0, -0.02, 0), Vector3(0.14, 0.04, 0.11), Color("f4f1ea"))
		"sajkaca":
			# The Serbian šajkača (unit box: the head's width and depth at the band, the head's height):
			# a soft wool cap with nearly upright sides, shaped like a boat from the side (peaked at the
			# front and back) and folded down into a crease along the top.
			var rows: Array = []
			for i in range(17):
				var u: float = lerpf(-1.0, 1.0, i / 16.0)
				var half: float = 0.5 * pow(maxf(0.0, 1.0 - pow(absf(u), 2.6)), 0.42)
				var high: float = 0.42 + 0.06 * u * u + 0.015 * u
				var crease: float = 0.05 * (1.0 - u * u)
				var row: PackedVector3Array = PackedVector3Array()
				for j in range(19):
					var t: float = lerpf(-1.0, 1.0, j / 18.0)
					var x: float = half * signf(t) * pow(absf(t), 0.8)
					var y: float = high * (1.0 - pow(absf(t), 2.2)) - crease * exp(-pow(t / 0.22, 2.0))
					row.append(Vector3(x, y, u * 0.5))
				rows.append(row)
			_surface(b, rows, tint, "vc_matte", Vector3(0, 0.12, 0))
			b.sphere(Vector3(0, 0.004, 0), 0.5, tint.darkened(0.3), "vc_matte", Vector3(0.98, 0.01, 0.98), 16)
			# The little cut at the front.
			b.box(Vector3(0, 0.04, 0.5), Vector3(0.022, 0.1, 0.016), tint.darkened(0.45), "vc_matte")
		"marama":
			# A headscarf (unit head box), tied at the back of the neck the village way: over the crown,
			# down to the brow at the front and over the tops of the ears (the cartoon cheeks stay clear
			# for the face), the knot, its two ends and the scarf's corner hanging at the nape; polka
			# dots and a darker hem.
			var edge: Callable = func(phi: float) -> float:
				# How far down from the crown it reaches along each meridian (phi 0 = the back).
				var a: float = absf(rad_to_deg(phi))
				var tail: float = 22.0 * exp(-pow(a / 18.0, 2.0))
				var down: float = 128.0 + tail
				down = lerpf(down, 100.0, smoothstep(50.0, 80.0, a))
				down = lerpf(down, 60.0, smoothstep(80.0, 135.0, a))
				return deg_to_rad(lerpf(down, 54.0, smoothstep(135.0, 180.0, a)))
			var on: Callable = func(phi: float, theta: float, grow: float) -> Vector3:
				# Just outside the head, whose radius (head box units, round the scarf's centre) was
				# measured on the cartoon women every 20 degrees from the crown and from the back.
				var fa: float = clampf(absf(rad_to_deg(phi)) / 20.0, 0.0, 8.999)
				var ft: float = clampf(rad_to_deg(theta) / 20.0 - 0.5, 0.0, 6.999)
				var ia: int = int(fa)
				var it: int = int(ft)
				var r0: float = lerpf(HEAD_ROUND[it][ia], HEAD_ROUND[it][ia + 1], fa - ia)
				var r1: float = lerpf(HEAD_ROUND[it + 1][ia], HEAD_ROUND[it + 1][ia + 1], fa - ia)
				# The edge tucks in against the head, so no gap shows under it at the temples.
				var tuck: float = 0.045 * smoothstep(edge.call(phi) - 0.22, edge.call(phi), theta)
				var r: float = lerpf(r0, r1, ft - it) + 0.03 + grow - tuck
				return Vector3(sin(theta) * sin(phi) * r, cos(theta) * r, -sin(theta) * cos(phi) * r)
			var hood: Array = []
			var hem: Array = []
			for i in range(73):
				var phi: float = lerpf(-PI, PI, i / 72.0)
				var bottom: float = edge.call(phi)
				var row: PackedVector3Array = PackedVector3Array()
				var band: PackedVector3Array = PackedVector3Array()
				for j in range(15):
					row.append(on.call(phi, bottom * j / 14.0, 0.0))
				for j in range(3):
					band.append(on.call(phi, bottom - deg_to_rad(8.0) * (1.0 - j / 2.0), 0.007))
				hood.append(row)
				hem.append(band)
			_surface(b, hood, tint, "vc_matte", Vector3(0, -0.05, 0))
			_surface(b, hem, tint.darkened(0.28), "vc_matte", Vector3(0, -0.05, 0))
			var dots: RandomNumberGenerator = RandomNumberGenerator.new()
			dots.seed = 7
			for k in range(30):
				var phi: float = dots.randf_range(-PI, PI)
				var theta: float = dots.randf_range(0.3, edge.call(phi) - 0.22)
				b.sphere(on.call(phi, theta, -0.009), 0.024, tint.lightened(0.55), "vc_matte", Vector3.ONE, 6)
			# The knot at the nape and its two ends.
			var knot: Vector3 = on.call(0.0, deg_to_rad(122.0), 0.02)
			b.sphere(knot, 0.075, tint.darkened(0.12), "vc_matte", Vector3(1.25, 0.9, 0.9), 8)
			for side in [-1.0, 1.0]:
				b.sphere(knot + Vector3(side * 0.07, -0.13, -0.03), 0.5, tint.darkened(0.06), "vc_matte", Vector3(0.1, 0.22, 0.05), 8)
		"beanie":
			# A knitted cap (unit head size): a soft dome, a rolled-up rib band and a bobble.
			b.sphere(Vector3(0, 0.06, -0.02), 0.5, tint, "vc_matte", Vector3(1.0, 0.94, 1.0), 16)
			b.cylinder(Vector3(0, -0.12, -0.02), 0.515, 0.17, tint.darkened(0.14), "vc_matte", 20, 0.97)
			b.sphere(Vector3(0, 0.52, -0.04), 0.11, tint.lightened(0.45), "vc_matte", Vector3.ONE, 8)
		"veil":
			# The bride's veil (unit head box): a comb of little flowers over the bun and a short veil of
			# tulle draped over it, falling in soft folds to the shoulders (a long one would go through
			# the chair backs), its hem scalloped.
			var reach: Callable = func(y: float, phi: float) -> float:
				# How far out the hair and bun reach at this height and below the veil's top, so the
				# veil hangs from their widest point instead of going in under them.
				var fa: float = clampf(absf(rad_to_deg(phi)) / 20.0, 0.0, 4.999)
				var ia: int = int(fa)
				var most: float = 0.0
				for k in range(VEIL_ROUND.size()):
					if 0.45 - 0.1 * k + 0.05 >= y:
						most = maxf(most, lerpf(VEIL_ROUND[k][ia], VEIL_ROUND[k][ia + 1], fa - ia))
				return most
			var rows: Array = []
			for i in range(15):
				var y: float = lerpf(0.4, -0.78, i / 14.0)
				var down: float = (0.4 - y) / 1.18
				var spread: float = deg_to_rad(lerpf(58.0, 100.0, down))
				var row: PackedVector3Array = PackedVector3Array()
				for j in range(25):
					var phi: float = lerpf(-spread, spread, j / 24.0)
					var out: float = reach.call(y, phi) + 0.045 + 0.13 * pow(clampf(-y / 0.78, 0.0, 1.0), 1.5)
					out += 0.016 * sin(phi * 9.0) * smoothstep(0.2, -0.5, y)
					var hem: float = 0.025 * cos(phi * 11.0) if i == 14 else 0.0
					row.append(Vector3(sin(phi) * out, y + hem, -cos(phi) * out))
				rows.append(row)
			# Its inside, seen past the face from the front, is white tulle too.
			_sheet(b, rows, tint, "vc_matte", Vector3(0, 0.0, 0.1))
			for k in range(7):
				var phi: float = deg_to_rad(lerpf(-48.0, 48.0, k / 6.0))
				var out: float = reach.call(0.42, phi) + 0.07
				b.sphere(Vector3(sin(phi) * out, 0.43, -cos(phi) * out), 0.05, Color("fbfaf7") if k % 2 == 0 else Color("f2b8c6"), "vc", Vector3.ONE, 6)
				b.sphere(Vector3(sin(phi) * (out + 0.03), 0.45, -cos(phi) * (out + 0.03)), 0.018, Color("f2c84a"), "vc", Vector3.ONE, 4)
		"wreath":
			# Venac: a ring of flowers and leaves round the crown.
			var colours: Array = [Color("d8423a"), Color("fbfaf7"), Color("f2b83a"), Color("e88aa8")]
			for k in range(14):
				var a: float = k * TAU / 14.0
				var at: Vector3 = Vector3(sin(a) * 0.47, 0.0, cos(a) * 0.47)
				b.sphere(at, 0.07, colours[k % 4] if k % 2 == 0 else Color("4f8a3a"), "vc", Vector3(1, 0.7, 1) if k % 2 == 0 else Vector3(1.3, 0.4, 0.7), 6)
		"backpack":
			# A school backpack (metres, model scale): body, front pocket, top handle and straps.
			b.box(Vector3(0, -0.17, -0.07), Vector3(0.24, 0.3, 0.13), tint, "vc_matte")
			b.sphere(Vector3(0, 0.13, -0.07), 0.12, tint, "vc_matte", Vector3(1.0, 0.4, 0.55), 10)
			b.box(Vector3(0, -0.15, -0.155), Vector3(0.17, 0.13, 0.05), tint.darkened(0.18), "vc_matte")
			b.box(Vector3(0, -0.075, -0.18), Vector3(0.16, 0.012, 0.012), Color("d9d4c8"), "vc_matte")
			for side in [-1.0, 1.0]:
				b.box(Vector3(side * 0.075, -0.12, 0.0), Vector3(0.035, 0.3, 0.02), tint.darkened(0.3), "vc_matte")
		"chain":
			# A heavy gold chain with a medallion (metres, model scale).
			for k in range(13):
				var t: float = lerpf(-1.0, 1.0, k / 12.0)
				b.sphere(Vector3(t * 0.075, -0.075 * (1.0 - t * t), 0.012 * (1.0 - t * t)), 0.011, Color("e8b832"), "vc_metal", Vector3.ONE, 6)
			b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, -0.1, 0.018)), 0.022, 0.008, Color("f2c84a"), "vc_metal", 10)
		"apron":
			# The waitress's short apron (metres, model scale): cloth curved round the front of the hips
			# and flaring out below so the thighs stay behind it when she walks, a waistband with its
			# ties at the back, and a pocket.
			var cloth: Array = []
			var band: Array = []
			for i in range(9):
				var k: float = i / 8.0
				var row: PackedVector3Array = PackedVector3Array()
				for j in range(13):
					var x: float = lerpf(-0.15, 0.15, j / 12.0) * (1.0 + 0.12 * k)
					row.append(Vector3(x, -0.22 * k + 0.012 * cos(j * 1.6) * k, -2.0 * x * x + 0.12 * pow(k, 1.3)))
				cloth.append(row)
			for i in range(2):
				var row: PackedVector3Array = PackedVector3Array()
				for j in range(15):
					var x: float = lerpf(-0.17, 0.17, j / 14.0)
					row.append(Vector3(x, 0.012 - 0.024 * i, -2.2 * x * x + 0.006))
				band.append(row)
			_sheet(b, cloth, Color("fbfaf7"), "vc_matte", Vector3(0, -0.1, -0.3))
			_sheet(b, band, Color("e8e2d6"), "vc_matte", Vector3(0, 0.0, -0.3))
			b.box(Vector3(0.055, -0.11, 0.046), Vector3(0.08, 0.06, 0.006), Color("e4ddd0"), "vc_matte")
			for side in [-1.0, 1.0]:
				b.sphere(Vector3(side * 0.03, -0.005, -0.27), 0.5, Color("e8e2d6"), "vc_matte", Vector3(0.05, 0.03, 0.02), 6)
				b.box(Vector3(side * 0.02, -0.06, -0.275), Vector3(0.016, 0.1, 0.006), Color("e8e2d6"), "vc_matte")
		"flower":
			b.sphere(Vector3.ZERO, 0.03, Color("f4f1ea"), "vc", Vector3.ONE, 6)
			b.sphere(Vector3(0, 0, 0.016), 0.014, Color("f3d27a"), "vc", Vector3.ONE, 5)
		"bowtie":
			for x in [-0.03, 0.03]:
				b.sphere(Vector3(x, 0, 0), 0.028, Color("1d1d22"), "vc", Vector3(1.2, 0.8, 0.5), 6)
		# Instruments (model units). Each in its own frame: the hands are put on them in _play().
		"accordion_right":
			# The keyboard half: a black case with the piano keys on its outer side (-x).
			b.box(Vector3(-0.045, -0.17, -0.1), Vector3(0.09, 0.34, 0.2), Color("1d1d22"), "vc_gloss")
			b.box(Vector3(-0.098, -0.15, -0.065), Vector3(0.016, 0.3, 0.1), Color("f7f4ee"), "vc_gloss")
			for k in range(7):
				b.box(Vector3(-0.107, -0.12 + k * 0.04, -0.05), Vector3(0.012, 0.02, 0.06), Color("15151a"), "vc_gloss")
			b.box(Vector3(-0.045, 0.17, -0.1), Vector3(0.095, 0.02, 0.2), Color("d9a531"), "vc_metal")
		"accordion_bellows":
			# The bellows (from x = 0 to 0.23): red folds with dark ribs, stretched as it plays.
			for k in range(8):
				b.box(Vector3(0.0144 + k * 0.0287, -0.16, -0.09), Vector3(0.026, 0.32, 0.18), Color("c0322c") if k % 2 == 0 else Color("3a1a1e"), "vc_matte")
		"accordion_left":
			# The bass half: a black case with rows of pearl buttons and a strap on its outer side (+x).
			b.box(Vector3(0.045, -0.17, -0.1), Vector3(0.09, 0.34, 0.2), Color("1d1d22"), "vc_gloss")
			for k in range(12):
				b.sphere(Vector3(0.093, -0.1 + (k % 6) * 0.03, -0.03 - (k / 6) * 0.035), 0.009, Color("f4f1ea"), "vc_gloss", Vector3.ONE, 6)
			b.box(Vector3(0.1, -0.12, -0.08), Vector3(0.012, 0.22, 0.03), Color("6a4228"), "vc_matte")
		"guitar", "tamburica":
			# The body at the origin, the neck along +y, the strings facing +z.
			var big: bool = kind == "guitar"
			var wood: Color = Color("d8964e") if big else Color("a35a2a")
			if big:
				b.sphere(Vector3(0, -0.03, 0), 0.5, wood, "vc_gloss", Vector3(0.27, 0.25, 0.09), 14)
				b.sphere(Vector3(0, 0.15, 0), 0.5, wood, "vc_gloss", Vector3(0.21, 0.19, 0.09), 14)
			else:
				b.sphere(Vector3(0, 0.02, 0), 0.5, wood, "vc_gloss", Vector3(0.21, 0.3, 0.09), 14)
				b.sphere(Vector3(0, 0.15, 0), 0.5, wood, "vc_gloss", Vector3(0.12, 0.16, 0.085), 12)
			b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.08 if big else 0.06, 0.04)), 0.033 if big else 0.022, 0.008, Color("1a1008"), "vc", 12)
			b.box(Vector3(0, -0.085, 0.04), Vector3(0.07, 0.012, 0.012), Color("2b1810"), "vc")
			var top: float = 0.6 if big else 0.56
			b.box(Vector3(0, 0.22, 0.012), Vector3(0.045 if big else 0.032, top - 0.22, 0.026), Color("3a2416"), "vc_gloss")
			b.box(Vector3(0, top, 0.006), Vector3(0.065 if big else 0.05, 0.09, 0.022), Color("2b1810"), "vc_gloss")
			for k in range(4):
				var x: float = (k - 1.5) * (0.009 if big else 0.007)
				b.box(Vector3(x, -0.085, 0.045), Vector3(0.0025, top + 0.06, 0.0025), Color("efe8d8"), "vc")
				b.sphere(Vector3(0.04 * (1.0 if k % 2 == 0 else -1.0), top + 0.02 + (k / 2) * 0.04, 0.01), 0.009, Color("d9a531"), "vc_metal", Vector3.ONE, 5)
		"bass":
			# Berda, the bass tamburica, standing on its pin: the body low, the neck up along +y.
			var dark: Color = Color("6a3416")
			b.cylinder(Vector3.ZERO, 0.01, 0.16, Color("2b2b30"), "vc_metal", 6)
			b.sphere(Vector3(0, 0.42, 0), 0.5, dark, "vc_matte", Vector3(0.38, 0.5, 0.16), 14)
			b.sphere(Vector3(0, 0.68, 0), 0.5, dark, "vc_matte", Vector3(0.26, 0.3, 0.15), 12)
			b.cylinder_xf(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.6, 0.07)), 0.03, 0.01, Color("1a1008"), "vc", 10)
			b.box(Vector3(0, 0.27, 0.075), Vector3(0.1, 0.014, 0.014), Color("2b1810"), "vc")
			b.box(Vector3(0, 0.78, 0.03), Vector3(0.05, 0.52, 0.035), Color("2b1810"), "vc_gloss")
			b.box(Vector3(0, 1.28, 0.025), Vector3(0.075, 0.12, 0.04), Color("2b1810"), "vc_gloss")
			for k in range(4):
				b.box(Vector3((k - 1.5) * 0.011, 0.27, 0.085), Vector3(0.003, 1.05, 0.003), Color("efe8d8"), "vc")
		"violin":
			# The chin end at the origin, the scroll along +y, the strings facing +z.
			var red: Color = Color("9a3a16")
			b.sphere(Vector3(0, 0.07, 0), 0.5, red, "vc_gloss", Vector3(0.2, 0.17, 0.07), 12)
			b.sphere(Vector3(0, 0.18, 0), 0.5, red, "vc_gloss", Vector3(0.16, 0.14, 0.07), 12)
			b.sphere(Vector3(0, 0.02, 0.025), 0.03, Color("1d1d22"), "vc_gloss", Vector3(1.2, 0.8, 0.4), 8)
			b.box(Vector3(0, 0.08, 0.03), Vector3(0.025, 0.012, 0.012), Color("e8d8b0"), "vc")
			b.box(Vector3(0, 0.12, 0.028), Vector3(0.024, 0.22, 0.012), Color("15151a"), "vc_gloss")
			b.box(Vector3(0, 0.24, 0.01), Vector3(0.02, 0.12, 0.02), red.darkened(0.2), "vc_gloss")
			b.sphere(Vector3(0, 0.375, 0.012), 0.02, red.darkened(0.25), "vc_gloss", Vector3(1, 1.2, 1), 8)
			for k in range(4):
				b.box(Vector3((k - 1.5) * 0.005, 0.07, 0.036), Vector3(0.0018, 0.3, 0.0018), Color("efe8d8"), "vc")
		"bow":
			# The bow along +x from the frog: a dark stick and the pale hair under it.
			b.box(Vector3(0.24, -0.006, 0), Vector3(0.5, 0.008, 0.008), Color("2b1d14"), "vc")
			b.box(Vector3(0.24, -0.016, 0), Vector3(0.48, 0.004, 0.012), Color("f4f1ea"), "vc")
			b.box(Vector3(0.0, -0.02, 0), Vector3(0.03, 0.025, 0.014), Color("15151a"), "vc")
		"mic":
			# A handheld microphone along +y: handle and the round grille.
			b.cylinder(Vector3(0, -0.13, 0), 0.016, 0.14, Color("2b2b30"), "vc_metal", 8, 1.2)
			b.sphere(Vector3(0, 0.02, 0), 0.032, Color("9aa0a8"), "vc_metal", Vector3.ONE, 10)

# ---------------------------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------------------------

func setup(new_look: Dictionary) -> void:
	look = new_look
	scale = full_scale()
	var model_name: String = str(look.model)
	model = load(MODELS + model_name + ".glb").instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in range(skeleton.get_bone_count()):
		bones[skeleton.get_bone_name(i)] = i
	body = skeleton.find_children("*", "MeshInstance3D", true, false)[0]
	var atlas: Texture2D = load(MODELS + model_name + "_atlas.png")
	body.material_override = _material(model_name, atlas)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Coarser levels of detail kick in sooner: people are small on screen most of the time.
	body.lod_bias = 0.3
	for key in look.pal:
		body.set_instance_shader_parameter(key, Color(str(look.pal[key])))
	body.set_instance_shader_parameter("face_style", look.style)
	body.set_instance_shader_parameter("face_age", look.get("age", Vector4.ZERO))
	measure = _measure(model_name, skeleton, body.mesh, body.skin)
	player = AnimationPlayer.new()
	model.add_child(player)
	player.add_animation_library("", library())
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	hand = Node3D.new()
	hand.position = Vector3(0, 0.09, 0.03)
	_attachment("RightHand").add_child(hand)
	var head_box: AABB = measure.head
	var neck: Vector3 = measure.neck
	var front: float = float(measure.chest_front)
	if str(look.hat) != "":
		var hat: MeshInstance3D = _add_mesh(_holder("Head", Vector3(0, head_box.end.y - head_box.size.y * 0.11, head_box.get_center().z - 0.05)), _mesh(look.hat), Vector3.ZERO)
		hat.scale = Vector3(1.0, 0.9, 1.12) * head_box.size.x
	for prop in look.get("props", []):
		_add_prop(str(prop[0]), str(prop[1]))
	match str(look.extra):
		"bowtie":
			_add_mesh(_holder("UpperChest", Vector3(0, neck.y - 0.05, front + 0.01)), _mesh("bowtie"), Vector3.ZERO)
		"flower":
			_add_mesh(_holder("UpperChest", Vector3(0.09, neck.y - 0.1, front)), _mesh("flower"), Vector3.ZERO)
	if str(look.instrument) != "":
		_take_instrument(str(look.instrument))
	phase = randf() * TAU
	pace = randf_range(0.92, 1.08)
	blink_in = randf_range(0.5, 4.0)
	mood = str(look.mood)
	face_now_values = FACES[mood].duplicate()
	play("idle")

## The musician's instrument, held where it is played (model units: +x the player's left, +z ahead).
## The hands are put on it every frame in _play().
func _take_instrument(kind: String) -> void:
	var neck: Vector3 = measure.neck
	var front: float = float(measure.chest_front)
	match kind:
		"accordion":
			# Strapped to the chest: the keyboard half on the right, the bellows and the bass half
			# opening to the left.
			instrument = _holder("UpperChest", Vector3(-0.07, neck.y - 0.1, front + 0.2))
			_add_mesh(instrument, _mesh("accordion_right"), Vector3.ZERO)
			var bellows: Node3D = Node3D.new()
			instrument.add_child(bellows)
			_add_mesh(bellows, _mesh("accordion_bellows"), Vector3.ZERO)
			var left: Node3D = Node3D.new()
			instrument.add_child(left)
			_add_mesh(left, _mesh("accordion_left"), Vector3.ZERO)
			instrument.set_meta("bellows", bellows)
			instrument.set_meta("left", left)
		"guitar", "tamburica":
			# Across the body, the neck up to the left, the strings facing out.
			var at: Vector3 = Vector3(-0.05, neck.y - 0.3, front + 0.08)
			instrument = _holder("UpperChest", at, Vector3(-0.2, 0.15, -1.0))
			_add_mesh(instrument, _mesh(kind), Vector3.ZERO)
		"bass":
			# The berda stands on the floor in front of the player, leaning back against them.
			instrument = Node3D.new()
			instrument.position = Vector3(0.2, 0, front + 0.2)
			instrument.rotation = Vector3(-0.28, 0.6, 0.12)
			model.add_child(instrument)
			_add_mesh(instrument, _mesh("bass"), Vector3.ZERO)
		"violin":
			# On the left collarbone under the chin, pointing out to the left and a little up.
			var dir: Vector3 = Vector3(0.6, 0.18, 0.78).normalized()
			var up: Vector3 = (Vector3(0.25, 1, 0) - dir * Vector3(0.25, 1, 0).dot(dir)).normalized()
			var basis: Basis = Basis(dir.cross(up), dir, up)
			var holder: Node3D = _holder("UpperChest", Vector3(0.06, neck.y - 0.03, front - 0.02))
			instrument = Node3D.new()
			holder.add_child(instrument)
			instrument.transform = Transform3D(basis, Vector3.ZERO)
			_add_mesh(instrument, _mesh("violin"), Vector3.ZERO)
			var bow: MeshInstance3D = _add_mesh(model, _mesh("bow"), Vector3.ZERO)
			instrument.set_meta("bow", bow)
		"mic":
			# A handheld microphone, put in the right hand in _play().
			instrument = _add_mesh(model, _mesh("mic"), Vector3.ZERO)

## Puts on a prop from the look: hats and scarves sized to the head, the rest on the body.
func _add_prop(kind: String, colour: String) -> void:
	var head_box: AABB = measure.head
	var size: Vector3 = head_box.size
	var centre: Vector3 = head_box.get_center()
	var mesh: Mesh = _mesh(kind + (":" + colour if colour != "" else ""))
	var node: MeshInstance3D
	match kind:
		"sajkaca":
			# The band goes round the head a third of the way down (the box is widest at the cartoon
			# cheeks, so the cap is narrower than the box).
			node = _add_mesh(_holder("Head", Vector3(0, head_box.end.y - size.y * 0.3, centre.z - size.z * 0.01)), mesh, Vector3.ZERO)
			node.scale = Vector3(size.x * 0.94, size.y, size.z * 0.98)
		"marama":
			node = _add_mesh(_holder("Head", centre + Vector3(0, size.y * 0.02, -size.z * 0.05)), mesh, Vector3.ZERO)
			node.scale = Vector3(size.x * 1.0, size.y * 1.0, size.z * 0.94)
		"beanie":
			node = _add_mesh(_holder("Head", centre + Vector3(0, size.y * 0.2, -size.z * 0.04)), mesh, Vector3.ZERO)
			node.scale = Vector3(size.x * 1.08, size.y * 0.95, size.z * 1.05)
		"veil":
			node = _add_mesh(_holder("Head", centre), mesh, Vector3.ZERO)
			node.scale = size
		"wreath":
			node = _add_mesh(_holder("Head", Vector3(0, head_box.end.y - size.y * 0.24, centre.z - size.z * 0.04)), mesh, Vector3.ZERO)
			node.scale = Vector3(size.x * 0.9, size.x, size.z * 0.9)
		"backpack":
			node = _add_mesh(_holder("UpperChest", Vector3(0, float(measure.neck.y) - 0.13, float(measure.chest_back) + 0.01)), mesh, Vector3.ZERO)
			node.scale = Vector3.ONE * 1.3
		"chain":
			_add_mesh(_holder("UpperChest", Vector3(0, float(measure.neck.y) - 0.045, float(measure.chest_front) + 0.004)), mesh, Vector3.ZERO)
		"apron":
			_add_mesh(_holder("Hips", (measure.waist as Vector3) + Vector3(0, 0.17, 0.025)), mesh, Vector3.ZERO)

## The size a character is drawn at; broader for a big build.
func full_scale() -> Vector3:
	return Vector3.ONE * SIZE * (1.0 + (float(look.get("build", 1.0)) - 1.0) * 0.5)

## A node following a bone, placed by where it should be on the body in the rest pose (skeleton
## space: +y up, +z the way the person faces), so props sit right whatever the bone's own axes.
func _holder(bone_name: String, at: Vector3, turn: Vector3 = Vector3.ZERO) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.transform = _bind(skeleton, body.skin, bone_name) * Transform3D(Basis.from_euler(turn), at)
	_attachment(bone_name).add_child(holder)
	return holder

func _attachment(bone_name: String) -> Node3D:
	var attach: BoneAttachment3D = BoneAttachment3D.new()
	attach.bone_name = bone_name
	skeleton.add_child(attach)
	return attach

func _add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, turn: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation = turn
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_overlay = _ink()
	parent.add_child(node)
	return node

## A drink in front of a guest (shared mesh, base at the origin).
static func vessel_mesh(kind: String) -> Mesh:
	return _mesh(kind if VESSELS.has(kind) else "water")

## Hold something: "", "tray" (with the order on it), "tray_empty" or "cloth" (in the right hand).
func hold(kind: String) -> void:
	if kind == holding:
		return
	holding = kind
	for child in hand.get_children():
		if child.get_meta("held", false):
			child.queue_free()
	if tray != null and is_instance_valid(tray):
		tray.queue_free()
	tray = null
	if kind in ["tray", "tray_empty"]:
		tray = _add_mesh(model, _mesh(kind), Vector3.ZERO)
		tray.top_level = true
	elif kind != "":
		var held: MeshInstance3D = _add_mesh(hand, _mesh(kind), Vector3(0, 0.0, 0.04))
		held.set_meta("held", true)

# ---------------------------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------------------------

## Animations: idle, walk, sit, dance, angry, happy, carry, carry_idle, play, wipe. While someone
## is sitting down or getting up, the chair choreography owns the body and this waits.
func play(name: String, new_rate: float = 1.0, restart: bool = false) -> void:
	if name == "drink":
		name = "sit"
	if seat_state not in ["", "seated"]:
		return
	if name == current and not restart:
		rate = new_rate
		return
	current = name
	rate = new_rate
	anim_time = 0.0
	hold("tray" if name in ["carry", "carry_idle"] else ("tray_empty" if name == "carry_empty" else ("cloth" if name == "wipe" else "")))
	var kind: String = str(look.get("kind", ""))
	var chatty: bool = int(phase * 10.0) % 2 == 0
	var wanted: String = "Idle"
	talking = false
	match name:
		"walk":
			wanted = "Walk_Formal" if kind in ["ozalosceni", "biznismen"] else "Walk"
		"carry", "carry_empty":
			# An ordinary walk; the tray goes on the left hand in _carry_pose().
			wanted = "Walk"
		"carry_idle":
			wanted = "Idle"
		"sit":
			wanted = "Sitting_Talking" if chatty else "Sitting_Idle"
			talking = chatty and kind != "ozalosceni"
		"happy":
			wanted = "Sit_Cheer" if chatty else "Sit_Clap"
		"angry":
			wanted = "Sit_No" if _seated_clip(clip) else "Walk"
		"dance":
			wanted = "Dance"
		"wipe":
			wanted = "Interact"
		"play":
			# Standing to play; the arms are put on the instrument in _play().
			wanted = "Idle"
			talking = look.instrument == "mic"
		_:
			if str(look.instrument) != "":
				wanted = "Idle"
			elif kind == "bouncer":
				wanted = "Idle_FoldArms"
			elif kind == "biznismen" and not look.female:
				wanted = "Idle_TalkingPhone"
				talking = true
			elif kind == "bartender":
				wanted = "Idle_Rail"
			elif kind in ["studenti", "svatovi"] and chatty:
				wanted = "Idle_Talking"
				talking = true
	mood = _mood_for(name)
	if wanted != clip:
		_clip(wanted, 0.0 if clip == "" else 0.3, true)

## Starts a clip with a blend; looping clips start at a random point so neighbours don't move in step.
func _clip(wanted: String, blend: float, random_start: bool) -> void:
	clip = wanted
	player.play(clip, blend)
	var anim: Animation = player.get_animation(clip)
	player.seek(fmod(phase, anim.length) if random_start and anim.loop_mode != Animation.LOOP_NONE else 0.0, true)

func _seated_clip(name: String) -> bool:
	return name.begins_with("Sit_") or name in ["Sitting_Idle", "Sitting_Talking"]

# ---------------------------------------------------------------------------------------------
# Chairs: sitting down and getting up
# ---------------------------------------------------------------------------------------------

## The chair's centre (venue space), pulled `out` of the way (0 tucked in, 1 out).
func chair_at(out: float) -> Vector3:
	return seat.chair - seat.dir * CHAIR_PULL * out

## Where to stand to sit down: in front of the pulled-out chair, so that sitting back puts the
## hips on the seat.
func stand_point() -> Vector3:
	return chair_at(1.0) + seat.dir * _seat_offset().z * scale.z

## How far the body is moved (model units) while on a chair: forward so the seated hips land on the
## seat (the clips sit far back), and up to the seat's height.
func _seat_offset() -> Vector3:
	var sit: Vector3 = measure.sit_hips
	return Vector3(0, SEAT_TOP / scale.y + HIP_OVER_SEAT - sit.y, -SEAT_BACK / scale.z - sit.z)

## Sit on a chair: {"chair": tucked-in centre, "dir": towards the table, "side": a free spot beside
## it, "move": Callable(pull), "release": Callable()} (venue space). The chair slides out, the
## person steps in front of it, sits down and the chair goes back in with them on it.
func sit_down(chair: Dictionary) -> void:
	seat = chair
	seat_state = "pulling"
	seat_time = 0.0
	speed_scale = 0.6
	walk(PackedVector3Array([stand_point()]))

## Already sitting (when the venue is built with guests in it).
func sit_instant(chair: Dictionary) -> void:
	seat = chair
	pull = 0.0
	seat.move.call(0.0)
	_set_seated()

func _set_seated() -> void:
	seat_state = "seated"
	speed_scale = 1.0
	position = chair_at(pull)
	face_now(seat.dir)
	current = ""
	play("sit")

func is_seated() -> bool:
	return seat_state == "seated"

## Get up, step out beside the chair (it goes back in) and then call `then`.
func stand_up(then: Callable) -> void:
	after_rising = then
	sip_time = -1.0
	match seat_state:
		"":
			then.call()
		"pulling":
			path = PackedVector3Array()
			_step_out()
		"entering":
			_rise()
		"seated", "tucking":
			seat_state = "untucking"
			seat_time = 0.0

func _rise() -> void:
	seat_state = "rising"
	position = chair_at(pull)
	_clip("Sitting_Exit", 0.25, false)
	rate = 1.15

func _step_out() -> void:
	seat_state = "stepping"
	position = stand_point()
	model.position = Vector3.ZERO
	current = ""
	speed_scale = 0.7
	walk(PackedVector3Array([seat.side]))

func _seat_step(delta: float) -> void:
	match seat_state:
		"pulling":
			pull = minf(1.0, pull + delta / 0.45)
			seat.move.call(pull)
			if path.is_empty() and pull >= 1.0:
				seat_state = "entering"
				position = chair_at(1.0)
				face(seat.dir)
				_clip("Sitting_Enter", 0.2, false)
				rate = 1.15
		"entering":
			if player.current_animation_position >= player.get_animation("Sitting_Enter").length * 0.9:
				seat_state = "tucking"
				seat_time = 0.0
				rate = 1.0
				var chatty: bool = int(phase * 10.0) % 2 == 0
				_clip("Sitting_Talking" if chatty else "Sitting_Idle", 0.4, true)
		"tucking":
			seat_time += delta
			pull = 1.0 - smoothstep(0.0, 1.0, seat_time / 0.6)
			seat.move.call(pull)
			position = chair_at(pull)
			if seat_time >= 0.6:
				_set_seated()
		"untucking":
			seat_time += delta
			pull = smoothstep(0.0, 1.0, seat_time / 0.45)
			seat.move.call(pull)
			position = chair_at(pull)
			if seat_time >= 0.45:
				_rise()
		"rising":
			if player.current_animation_position >= player.get_animation("Sitting_Exit").length * 0.88:
				rate = 1.0
				_step_out()
		"stepping":
			if path.is_empty():
				seat_state = ""
				speed_scale = 1.0
				pull = 0.0
				seat.release.call()
				play("idle")
				if after_rising.is_valid():
					after_rising.call()

# ---------------------------------------------------------------------------------------------
# Drinking: the person's own glass, lifted to the mouth with the right arm (two-bone IK)
# ---------------------------------------------------------------------------------------------

## Give the person their drink on the table (`node` stands where it should rest), or none.
func set_vessel(node: Node3D, kind: String) -> void:
	vessel = node
	vessel_kind = kind
	sip_time = -1.0
	if node != null:
		vessel_rest = node.global_transform
		sip_in = randf_range(1.0, 4.0)

func is_drinking() -> bool:
	return sip_time >= 0.0

## Drink now (if seated and not already drinking).
func drink() -> void:
	if seat_state == "seated" and vessel != null and sip_time < 0.0:
		sip_time = 0.0

func _drink_step(delta: float) -> void:
	if vessel == null or not is_instance_valid(vessel) or seat_state != "seated":
		sip_time = -1.0
		return
	if sip_time < 0.0:
		sip_in -= delta
		if sip_in <= 0.0 and current == "sit":
			sip_time = 0.0
		return
	sip_time += delta
	if sip_time >= DRINK_END:
		sip_time = -1.0
		sip_in = randf_range(4.0, 10.0)
		emote("glum" if str(look.mood) == "sad" else "blissful", 0.9)

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)

## How far into a sip the drinker is: 0 glass down, 1 at the lips and tipped.
func _sip_amount() -> float:
	if sip_time < 0.0:
		return 0.0
	return smoothstep(DRINK_LIFT - 0.1, DRINK_LIFT + 0.25, sip_time) * (1.0 - smoothstep(DRINK_SIP - 0.25, DRINK_SIP, sip_time))

func _drink_pose() -> void:
	if vessel == null or not is_instance_valid(vessel):
		return
	if sip_time < 0.0:
		vessel.global_transform = vessel_rest
		return
	var t: float = sip_time
	var reach: float = smoothstep(0.0, DRINK_REACH, t) * (1.0 - smoothstep(DRINK_DOWN, DRINK_END, t))
	var up: float = _ease((t - DRINK_REACH) / (DRINK_LIFT - DRINK_REACH)) * (1.0 - _ease((t - DRINK_SIP) / (DRINK_DOWN - DRINK_SIP)))
	var spec: Array = VESSELS.get(vessel_kind, VESSELS.water)
	var size: float = vessel_rest.basis.get_scale().y
	var radius: float = spec[0] * size
	var height: float = spec[1] * size
	var sk: Transform3D = skeleton.global_transform
	var forward: Vector3 = sk.basis.z.normalized()
	var right: Vector3 = -sk.basis.x.normalized()
	var head: Transform3D = sk * skeleton.get_bone_global_pose(bones["Head"])
	var mouth: Vector3 = head * (measure.mouth as Vector3)
	# Tipped towards the face at the lips, more while sipping; the rim just under the lower lip.
	var tip: float = up * float(spec[2]) * (0.45 + 0.55 * _sip_amount())
	var tilt: Basis = Basis(right, tip)
	var glass_up: Vector3 = tilt * Vector3.UP
	var at_lips: Vector3 = mouth + forward * (radius * 0.9) - Vector3.UP * 0.02 - glass_up * height
	var base: Vector3 = vessel_rest.origin.lerp(at_lips, up) + (forward * 0.07 + Vector3.UP * 0.04) * sin(PI * up)
	var grip: Vector3 = base + glass_up * height * 0.45 + right * (radius + 0.03)
	if up > 0.0:
		vessel.global_transform = Transform3D(tilt * vessel_rest.basis, base)
	else:
		vessel.global_transform = vessel_rest
	_reach(grip, (right * 0.7 - Vector3.UP - forward * 0.3).normalized(), reach)

## The waiter's way with a tray: on the flat of the left hand at chest height, the elbow bent close
## to the side, the tray level whatever the walk does (so the glasses stand up on it). Standing at a
## table with a full tray, the right hand reaches down to set the order on the table.
func _carry_pose() -> void:
	var sk: Transform3D = skeleton.global_transform
	var s: float = sk.basis.get_scale().y
	var ahead: Vector3 = sk.basis.z.normalized()
	var right: Vector3 = -sk.basis.x.normalized()
	var ua: int = bones["LeftUpperArm"]
	var la: int = bones["LeftLowerArm"]
	var hd: int = bones["LeftHand"]
	var l1: float = skeleton.get_bone_global_pose(ua).origin.distance_to(skeleton.get_bone_global_pose(la).origin) * s
	var l2: float = skeleton.get_bone_global_pose(la).origin.distance_to(skeleton.get_bone_global_pose(hd).origin) * s
	var shoulder: Vector3 = sk * skeleton.get_bone_global_pose(ua).origin
	# A little give in the arm with each step.
	var give: float = 0.008 * s * sin(anim_time * 9.0 + phase) if current != "carry_idle" else 0.0
	var wrist: Vector3 = shoulder - Vector3.UP * (0.95 * l1 + 0.32 * l2 + give) + ahead * (0.25 * l1 + 0.92 * l2) - right * 0.25 * l1
	_reach(wrist, (-right * 0.7 - Vector3.UP - ahead * 0.3).normalized(), 1.0, "Left")
	# The hand flat, fingers forward, under the middle of the tray.
	var fingers: PackedInt32Array = skeleton.get_bone_children(hd)
	if fingers.size() > 0:
		var tip: int = fingers[0]
		for f in fingers:
			if "Middle" in str(skeleton.get_bone_name(f)):
				tip = f
		var h: Vector3 = skeleton.get_bone_global_pose(hd).origin
		_aim_bone(hd, skeleton.get_bone_global_pose(tip).origin - h, sk.basis.inverse() * (ahead - right * 0.25))
	var palm: Vector3 = sk * skeleton.get_bone_global_pose(hd).origin + (ahead - right * 0.25).normalized() * 0.05 * s
	tray.global_transform = Transform3D(Basis(Vector3.UP, atan2(ahead.x, ahead.z)).scaled(Vector3.ONE * s), palm + Vector3.UP * 0.03 * s)
	if current == "carry_idle":
		var serve: float = sin(PI * clampf(anim_time / 0.9, 0.0, 1.0))
		var venue_scale: float = get_parent().global_transform.basis.get_scale().y if get_parent() is Node3D else 1.0
		var spot: Vector3 = global_position + ahead * 0.6 * venue_scale + right * 0.12 * venue_scale + Vector3.UP * (TABLE_TOP + 0.1) * venue_scale
		_reach(spot, (right * 0.7 - Vector3.UP - ahead * 0.3).normalized(), serve, "Right")

## A transform on a bone as it is posed now (`local` in the bone's frame, as a holder's).
func _on_bone(bone: String, local: Transform3D) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bones[bone]) * local

## Musicians hold their instrument with both hands and play it while a song is on: frets and
## strumming, keys and bellows, the bow across the strings, the microphone at the lips.
func _play() -> void:
	var t: float = anim_time + phase
	var p: float = play_amount
	var sk: Transform3D = skeleton.global_transform
	var ahead: Vector3 = sk.basis.z.normalized()
	var right: Vector3 = -sk.basis.x.normalized()
	match str(look.instrument):
		"guitar", "tamburica":
			var g: Transform3D = _on_bone("UpperChest", instrument.transform)
			# The chord hand moves between three places on the neck, a chord a beat; the other
			# strums across the strings over the sound hole.
			var chords: Array = [0.36, 0.44, 0.5]
			var step: float = t * 1.0
			var from: float = chords[int(step) % 3]
			var to: float = chords[(int(step) + 1) % 3]
			var fret: float = lerpf(from, to, smoothstep(0.75, 1.0, fmod(step, 1.0)) * p)
			var strum: float = sin(t * TAU * 2.0) * 0.045 * p
			_reach(g * Vector3(-0.035, fret, -0.025), (-right * 0.5 - Vector3.UP - ahead * 0.3).normalized(), 1.0, "Left")
			_reach(g * Vector3(0.06 + strum, 0.05 + strum * 0.4, 0.075), (right * 0.7 - Vector3.UP * 0.5 - ahead * 0.5).normalized(), 1.0, "Right")
		"bass":
			var berda: Transform3D = model.global_transform * instrument.transform
			var pluck: float = sin(t * TAU * 1.0) * 0.04 * p
			_reach(berda * Vector3(-0.035, 0.98 + 0.05 * sin(t * 0.9) * p, -0.02), (-right * 0.4 - Vector3.UP - ahead * 0.2).normalized(), 1.0, "Left")
			_reach(berda * Vector3(-0.07 + pluck, 0.6, 0.08), (right * 0.8 - Vector3.UP * 0.4 - ahead * 0.4).normalized(), 1.0, "Right")
		"accordion":
			# The bellows breathe in and out (two seconds a breath), the bass half going with the
			# left hand; the right hand runs up and down the keys.
			var squeeze: float = 0.5 + 0.5 * sin(t * TAU * 0.5)
			var open: float = lerpf(0.3, lerpf(0.15, 0.6, squeeze), p)
			var bellows: Node3D = instrument.get_meta("bellows")
			var left: Node3D = instrument.get_meta("left")
			bellows.scale = Vector3(1.0 + open, 1, 1)
			left.position = Vector3(0.23 * (1.0 + open), 0, 0)
			var a: Transform3D = _on_bone("UpperChest", instrument.transform)
			var keys: float = (0.04 * sin(t * 3.1) + 0.03 * sin(t * 7.3)) * p
			_reach(a * Vector3(-0.15, -0.02 + keys, -0.07), (right * 0.8 - Vector3.UP * 0.6 - ahead * 0.2).normalized(), 1.0, "Right")
			_reach(a * Vector3(0.23 * (1.0 + open) + 0.13, -0.05, -0.1), (-right * 0.8 - Vector3.UP * 0.6 - ahead * 0.2).normalized(), 1.0, "Left")
		"violin":
			var holder: Node3D = instrument.get_parent()
			var v: Transform3D = _on_bone("UpperChest", holder.transform * instrument.transform)
			_reach(v * Vector3(-0.025, 0.3 + 0.006 * sin(t * 30.0) * p, -0.025), (-right * 0.3 - Vector3.UP - ahead * 0.1).normalized(), 1.0, "Left")
			# The bow: long strokes across the strings near the bridge, from the right hand.
			var contact: Vector3 = v * Vector3(0, 0.1, 0.045)
			var along: Vector3 = (v.basis * Vector3(1, -0.2, 0.35)).normalized()
			if along.dot(right) > 0.0:
				along = -along
			var stroke: float = lerpf(0.25, lerpf(0.1, 0.4, 0.5 + 0.5 * sin(t * TAU * 0.6)), p)
			var frog: Vector3 = contact - along * stroke
			var normal: Vector3 = (v.basis.z - along * v.basis.z.dot(along)).normalized()
			var bow: Node3D = instrument.get_meta("bow")
			bow.global_transform = Transform3D(Basis(along, normal, along.cross(normal)), frog)
			_reach(frog - along * 0.02, (right * 0.7 - Vector3.UP * 0.6 - ahead * 0.3).normalized(), 1.0, "Right")
		"mic":
			# The microphone at the lips; the other hand sings along.
			var head: Transform3D = sk * skeleton.get_bone_global_pose(bones["Head"])
			var mouth: Vector3 = head * (measure.mouth as Vector3)
			var grip: Vector3 = mouth + ahead * 0.11 - Vector3.UP * 0.07
			var towards: Vector3 = (mouth - grip).normalized()
			var side: Vector3 = towards.cross(Vector3.UP).normalized()
			instrument.global_transform = Transform3D(Basis(side, towards, side.cross(towards)), grip + towards * 0.05)
			_reach(grip, (right * 0.6 - Vector3.UP * 0.8).normalized(), 1.0, "Right")
			var chest: Vector3 = _on_bone("UpperChest", Transform3D.IDENTITY).origin
			var wave: Vector3 = -right * (0.22 + 0.06 * sin(t * 0.7) * p) + ahead * (0.16 + 0.04 * sin(t * 1.1)) + Vector3.UP * (0.02 + 0.08 * p * (0.5 + 0.5 * sin(t * 1.3)))
			_reach(chest + wave, (-right * 0.7 - Vector3.UP * 0.7).normalized(), 1.0, "Left")

## At the table, hands that the clip lowers into it (resting in the lap, which is under the
## tablecloth) rest on the top instead, forearms on the table; hands raised to talk, cheer or wave
## stay free.
func _hands_on_table() -> void:
	var venue: Transform3D = get_parent().global_transform
	var chair: Vector3 = venue * chair_at(pull)
	var ahead: Vector3 = (venue.basis * (seat.dir as Vector3)).normalized()
	var right: Vector3 = ahead.cross(Vector3.UP).normalized()
	var sk: Transform3D = skeleton.global_transform
	var edge: float = TABLE_REACH - CHAIR_PULL * pull
	for side in ["Left", "Right"]:
		var out: Vector3 = right if side == "Right" else -right
		var hand: Vector3 = sk * skeleton.get_bone_global_pose(bones[side + "Hand"]).origin
		var height: float = hand.y - chair.y
		var weight: float = smoothstep(TABLE_TOP + 0.1, TABLE_TOP, height)
		if weight <= 0.001:
			continue
		var drift: float = sin(anim_time * 0.6 + phase + (0.0 if side == "Right" else 2.0))
		var rest: Vector3 = chair + ahead * (edge + 0.1 + 0.02 * drift) + out * (0.14 + 0.015 * drift) + Vector3.UP * (TABLE_TOP + 0.035)
		_reach(rest, (out * 0.9 - Vector3.UP * 0.4 - ahead * 0.4).normalized(), weight, side)

## Two-bone IK on an arm ("Right" or "Left"): the wrist goes to `target` with the elbow bent towards
## `pole` (both global), blended with the animated arm by `weight`.
func _reach(target: Vector3, pole: Vector3, weight: float, side: String = "Right") -> void:
	if weight <= 0.001:
		return
	var ua: int = bones[side + "UpperArm"]
	var la: int = bones[side + "LowerArm"]
	var hd: int = bones[side + "Hand"]
	var inv: Transform3D = skeleton.global_transform.affine_inverse()
	var a: Vector3 = skeleton.get_bone_global_pose(ua).origin
	var b: Vector3 = skeleton.get_bone_global_pose(la).origin
	var c: Vector3 = skeleton.get_bone_global_pose(hd).origin
	var l1: float = a.distance_to(b)
	var l2: float = b.distance_to(c)
	var goal: Vector3 = c.lerp(inv * target, weight)
	var animated_bend: Vector3 = b - (a + c) * 0.5
	var bend: Vector3 = animated_bend.normalized().lerp((inv.basis * pole).normalized(), weight)
	var to: Vector3 = goal - a
	var dist: float = clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir: Vector3 = to.normalized()
	var cos_a: float = clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var perp: Vector3 = bend - dir * bend.dot(dir)
	if perp.length() < 0.0001:
		perp = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	perp = perp.normalized()
	var elbow: Vector3 = a + dir * (cos_a * l1) + perp * (sqrt(1.0 - cos_a * cos_a) * l1)
	_aim_bone(ua, b - a, elbow - a)
	var b2: Vector3 = skeleton.get_bone_global_pose(la).origin
	var c2: Vector3 = skeleton.get_bone_global_pose(hd).origin
	_aim_bone(la, c2 - b2, a + dir * dist - b2)

## Turns a bone so that `from` (skeleton space) points along `to`, keeping its twist.
func _aim_bone(bone: int, from: Vector3, to: Vector3) -> void:
	if from.length() < 1e-5 or to.length() < 1e-5:
		return
	var turn: Quaternion = Quaternion(from.normalized(), to.normalized())
	var parent: int = skeleton.get_bone_parent(bone)
	var parent_basis: Basis = skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var global_basis: Basis = Basis(turn) * skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * global_basis).get_rotation_quaternion())

func _mood_for(name: String) -> String:
	var base: String = str(look.get("mood", "smile"))
	match name:
		"happy":
			return "laugh"
		"angry":
			return "angry"
		"dance":
			return "laugh" if base != "sad" else "glum"
		"carry", "carry_idle", "carry_empty":
			return "smile"
		"wipe":
			return "whistle"
		"play":
			return "sing" if look.instrument == "mic" else "blissful"
	return base

## A short expression on top of the mood: "laugh", "surprise", "angry", "sad", "smile"...
func emote(name: String, seconds: float = 1.5) -> void:
	if FACES.has(name):
		emote_name = name
		emote_left = seconds

func face(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() < 0.01:
		return
	target_heading = atan2(direction.x, direction.z)

func face_now(direction: Vector3) -> void:
	face(direction)
	heading = target_heading
	rotation.y = heading

func walk(points: PackedVector3Array) -> void:
	path = points
	if path.is_empty():
		arrived.emit()

func is_walking() -> bool:
	return not path.is_empty()

func fade_in(_duration: float = 0.3) -> void:
	scale = full_scale() * 0.2
	create_tween().tween_property(self, "scale", full_scale(), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func fade_and_free(_duration: float = 0.3) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", full_scale() * 0.05, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func _process(delta: float) -> void:
	if skeleton == null:
		return
	anim_time += delta * rate
	var clip_rate: float = rate
	if path.is_empty():
		gait = 0.0
		if current == "angry" and not _seated_clip(clip):
			play("idle")
	else:
		# Turn into the next leg a little before reaching a corner, so the walk curves.
		while path.size() > 1 and Vector2(path[0].x - position.x, path[0].z - position.z).length() < CORNER:
			path.remove_at(0)
		var target: Vector3 = path[0]
		var offset: Vector3 = target - position
		offset.y = 0.0
		# Ease into a walk and slow down into the last step.
		gait = minf(1.0, gait + delta / 0.35)
		var brake: float = clampf(offset.length() / 0.5, 0.45, 1.0) if path.size() == 1 else 1.0
		var speed: float = WALK_SPEED * speed_scale * float(look.get("pace", 1.0)) * pace * lerpf(0.35, 1.0, gait) * brake
		var step: float = speed * delta
		face(offset)
		if seat_state in ["pulling", "stepping"]:
			if clip != "Walk":
				_clip("Walk", 0.2, true)
		elif current not in ["walk", "carry", "carry_empty", "angry"]:
			play("carry" if holding == "tray" else ("carry_empty" if holding == "tray_empty" else "walk"))
		clip_rate = speed / maxf(0.3, float(measure.stride) * scale.x)
		if offset.length() <= step:
			position = Vector3(target.x, position.y, target.z)
			path.remove_at(0)
			if path.is_empty():
				arrived.emit()
		else:
			position += offset.normalized() * step
	if not seat.is_empty():
		_seat_step(delta)
	_drink_step(delta)
	play_amount = move_toward(play_amount, 1.0 if current == "play" else 0.0, delta * 2.0)
	heading = lerp_angle(heading, target_heading, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = heading
	# The bones touched up in code go back to rest first, so a clip that doesn't key them doesn't let
	# the touches pile up frame after frame.
	for bone in TOUCHED:
		if bones.has(bone):
			skeleton.reset_bone_pose(bones[bone])
	player.advance(delta * clip_rate)
	_pose()
	_face(delta)

func _turn(bone: String, rotation_euler: Vector3) -> void:
	if bones.has(bone):
		var index: int = bones[bone]
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index) * Quaternion.from_euler(rotation_euler))

func _pose() -> void:
	var t: float = anim_time
	# On a chair the body moves forward and up so the hips land on the seat; while sitting down or
	# getting up the lift follows the hips (as they go down, the seat comes up to meet them).
	if seat_state in ["entering", "tucking", "seated", "untucking", "rising"]:
		var off: Vector3 = _seat_offset()
		var sit: Vector3 = measure.sit_hips
		var stand: Vector3 = measure.stand_hips
		var hip_y: float = skeleton.get_bone_pose_position(bones["Hips"]).y
		var down: float = clampf((stand.y - hip_y) / maxf(0.01, stand.y - sit.y), 0.0, 1.0)
		model.position = Vector3(0, down * off.y + maxf(0.0, sit.y - hip_y), off.z)
	else:
		model.position = Vector3.ZERO
	# Faces read from the high camera: heads tip back, more for the seated (their clips look down
	# at the table), and back again to drink.
	# (Walking, they look where they go.)
	var walking: bool = not path.is_empty() or current in ["walk", "carry", "carry_empty"]
	# (A waiter with a tray looks where they go, over it, not down at the floor.)
	var lift: float = HEAD_LIFT * (0.6 if current == "angry" else (1.35 if seat_state == "seated" else 1.0))
	if walking:
		lift = HEAD_LIFT * (0.9 if tray != null else 0.3)
	lift += _sip_amount() * 0.3
	# The old stoop a little when standing and walking (the head comes back up to look ahead).
	var hunch: float = float(look.get("hunch", 0.0))
	if hunch > 0.0 and seat_state == "" and current not in ["dance", "play"]:
		_turn("Spine", Vector3(hunch, 0, 0))
		lift += hunch * 0.8
	_turn("Head", Vector3(-lift, sin(t * 0.7 + phase) * 0.12 * (1.0 - _sip_amount()), 0))
	match current:
		"dance":
			model.position.y = absf(sin(t * 6.0 + phase)) * 0.04
		"play":
			# In time with the song: a sway, a nod and a little bounce on the beat.
			var beat: float = t * TAU * 1.0 + phase
			_turn("Spine", Vector3(0.03 * absf(sin(beat)), 0.06 * sin(beat * 0.5), 0.025 * sin(beat * 0.5)) * play_amount)
			model.position.y = absf(sin(beat)) * 0.012 * play_amount
	if instrument != null:
		_play()
	if tray != null:
		_carry_pose()
	if seat_state in ["seated", "tucking"]:
		_hands_on_table()
	if seat_state == "seated":
		_drink_pose()
	elif vessel != null and is_instance_valid(vessel):
		vessel.global_transform = vessel_rest

## The drawn face: eased towards the mood (or an emote), with blinks and a talking mouth.
func _face(delta: float) -> void:
	if emote_left > 0.0:
		emote_left -= delta
	var target: Array = FACES["gulp" if _sip_amount() > 0.3 else (emote_name if emote_left > 0.0 else mood)]
	var ease: float = clampf(delta * 8.0, 0.0, 1.0)
	for i in range(4):
		face_now_values[i] = (face_now_values[i] as Vector4).lerp(target[i], ease)
	var eyes: Vector4 = face_now_values[0]
	var mouth: Vector4 = face_now_values[2]
	blink_in -= delta
	if blink_in < 0.0:
		eyes.x *= clampf(absf(blink_in + 0.06) / 0.06, 0.0, 1.0)
		if blink_in < -0.12:
			blink_in = randf_range(1.8, 4.5)
	if talking and emote_left <= 0.0 and sip_time < 0.0:
		var chatter: float = absf(sin(anim_time * 9.0 + phase)) * (0.5 + 0.5 * sin(anim_time * 2.3 + phase * 2.0))
		mouth.y = maxf(mouth.y, chatter * 0.45)
	body.set_instance_shader_parameter("face_eyes", eyes)
	body.set_instance_shader_parameter("face_brows", face_now_values[1])
	body.set_instance_shader_parameter("face_mouth", mouth)
	body.set_instance_shader_parameter("face_extra", face_now_values[3])
