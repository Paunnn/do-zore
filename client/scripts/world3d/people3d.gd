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
const MODELS = "res://assets/people/"
const PERSON_SHADER = preload("res://shaders/person.gdshader")
const INK_SHADER = preload("res://shaders/ink.gdshader")
const WALK_SPEED = 2.0
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

var look: Dictionary = {}
var model: Node3D
var skeleton: Skeleton3D
var body: MeshInstance3D
var player: AnimationPlayer
var bones: Dictionary = {}
var hand: Node3D
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

# ---------------------------------------------------------------------------------------------
# Looks
# ---------------------------------------------------------------------------------------------

## A look for a guest type (or "waiter", "bartender", "bouncer", "musician:<instrument>").
static func make_look(kind: String, variant: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var pick: Callable = func(options: Array) -> String: return options[rng.randi() % options.size()]
	var female: bool = variant % 2 == 1
	var look: Dictionary = {"kind": kind, "variant": variant, "female": female, "model": "student", "hat": "",
		"extra": "", "instrument": "", "build": 1.0, "mood": "smile",
		"pal": {"col_skin": pick.call(SKIN), "col_hair": pick.call(HAIR), "col_eye": pick.call(EYES),
			"col_top": pick.call(BRIGHT), "col_bottom": pick.call(DENIM), "col_shoes": "3a2a1e", "col_hat": "5e5d40"},
		"style": Vector4(1, 0.85, 0.5, 0) if female else Vector4(0, 1.25, 0, 0)}
	match kind:
		"penzioner":
			look.pal.col_hair = pick.call(GREY_HAIR)
			look.mood = "smile"
			if female:
				look.model = "baba"
				look.pal.col_top = pick.call(["3a4a6a", "6a2a3a", "5a6a4a", "4a3a5a", "6e5a44"])
				look.style = Vector4(1, 0.9, 0.35, 0)
			else:
				look.model = "deda" if variant % 4 != 0 else "deda2"
				look.pal.col_top = pick.call(["8a5a36", "6e5a44", "5a6a4a", "7a6a52", "4a5568"])
				look.pal.col_bottom = pick.call(["4f5357", "5a4a3a", "3a3a40"])
				look.hat = "sajkaca" if rng.randf() < 0.6 else ""
				look.style.w = 1.0 if rng.randf() < 0.3 else 0.0
		"studenti":
			look.model = "studentkinja" if female else "student"
			look.mood = "grin"
		"svatovi":
			look.model = "svatica" if female else "svat"
			look.pal.col_top = pick.call(["d9536a", "f2b83a", "4aa8c9", "b05ad0", "f4f1ea", "e88aa8"])
			look.extra = "" if female else "flower"
			look.mood = "laugh"
		"biznismen":
			look.model = "biznismenka" if female else "biznismen"
			look.style.w = 1.0 if rng.randf() < 0.4 else 0.0
			look.mood = "neutral"
		"ozalosceni":
			look.model = "ozaloscena" if female else "ozaloscen"
			look.pal.col_top = "26262c"
			look.pal.col_hair = pick.call(["2b1d14", "1a1a1e", "4a3020", "9a948a"])
			look.style.z = 0.0
			look.mood = "sad"
		"waiter":
			look.model = "konobarica" if female else "konobar"
			look.pal.col_top = "f4f1ea"
			look.pal.col_bottom = "1d1d22"
		"bartender":
			look.model = "sanker"
			look.female = false
			look.pal.col_top = "f4f1ea"
			look.pal.col_bottom = "1d1d22"
			look.pal.col_hair = "3a2416"
			look.extra = "bowtie"
			look.style = Vector4(0, 1.3, 0, 0)
			look.mood = "neutral"
		"bouncer":
			look.model = "izbacivac"
			look.female = false
			look.pal.col_top = "1d1d22"
			look.pal.col_bottom = "2b2b30"
			look.style = Vector4(0, 1.5, 0, 2)
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
	var mouth: Vector3 = head_rest + Vector3(0, 0.05, 0.15)
	var mouth_d: float = -1e9
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		if v.y > head_rest.y + 0.04:
			head_box = head_box.expand(v)
		elif v.y > neck.y - 0.16 and v.y < neck.y - 0.04 and absf(v.x) < 0.06:
			chest_front = maxf(chest_front, v.z)
		# The face plane is a projection, so the inside of the closed mouth maps there too: take the
		# frontmost point near the mouth.
		if i < face_uv.size() and i < colors.size() and colors[i].g > 0.5 and colors[i].r < 0.1:
			if face_uv[i].distance_to(Vector2(0.5, 0.79)) < 0.06 and v.z > mouth_d:
				mouth_d = v.z
				mouth = v
	_measures[model_name] = {"head": head_box, "neck": neck, "chest_front": chest_front,
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

## Adds a prop, hat or instrument to a builder (at the builder's offset).
static func _accessory(b: Builder, kind: String) -> void:
	var glass: Color = Color("e4f2f4")
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
		"tray":
			b.cylinder(Vector3.ZERO, 0.2, 0.018, Color("c9ced6"), "vc_metal", 14)
			b.cylinder(Vector3(0.05, 0.018, 0.03), 0.035, 0.12, Color("dfeff0"), "vc_gloss", 8)
			b.cylinder(Vector3(-0.07, 0.018, -0.03), 0.032, 0.17, Color("3d8a4f"), "vc_gloss", 8)
		"cloth":
			b.box(Vector3(0, -0.02, 0), Vector3(0.14, 0.04, 0.11), Color("f4f1ea"))
		"sajkaca":
			# The Serbian šajkača (unit width): a grey-green cap, boat-shaped, pinched along the top and
			# notched at the front.
			var cloth: Color = Color("5e5d40")
			b.sphere(Vector3(0, 0.0, 0), 0.5, cloth, "vc", Vector3(0.92, 0.38, 1.08), 14)
			for side in [-1.0, 1.0]:
				b.sphere(Vector3(side * 0.16, 0.1, 0), 0.5, cloth.darkened(0.06), "vc", Vector3(0.36, 0.26, 1.02), 10)
			b.box(Vector3(0, 0.04, 0.52), Vector3(0.1, 0.14, 0.05), cloth.darkened(0.35))
		"flower":
			b.sphere(Vector3.ZERO, 0.03, Color("f4f1ea"), "vc", Vector3.ONE, 6)
			b.sphere(Vector3(0, 0, 0.016), 0.014, Color("f3d27a"), "vc", Vector3.ONE, 5)
		"bowtie":
			for x in [-0.03, 0.03]:
				b.sphere(Vector3(x, 0, 0), 0.028, Color("1d1d22"), "vc", Vector3(1.2, 0.8, 0.5), 6)
		"accordion":
			# A black accordion with a pearl keyboard and a brass grille, red bellows open between.
			b.box(Vector3(-0.16, 0, 0), Vector3(0.09, 0.32, 0.19), Color("1d1d22"), "vc_gloss")
			b.box(Vector3(0.16, 0, 0), Vector3(0.09, 0.32, 0.19), Color("1d1d22"), "vc_gloss")
			for k in range(6):
				b.box(Vector3(-0.1 + k * 0.04, 0.005, 0), Vector3(0.032, 0.3, 0.18), Color("c0322c") if k % 2 == 0 else Color("2b2b30"))
			b.box(Vector3(-0.21, 0, 0.015), Vector3(0.018, 0.28, 0.14), Color("f4f1ea"), "vc_gloss")
			b.box(Vector3(0.21, 0.01, 0.0), Vector3(0.012, 0.19, 0.12), Color("d9a531"), "vc_metal")
		"guitar", "tamburica", "bass":
			var scale: float = {"guitar": 1.0, "tamburica": 0.75, "bass": 1.25}[kind]
			var wood: Color = {"guitar": Color("c98a4a"), "tamburica": Color("8a4a22"), "bass": Color("3a2416")}[kind]
			b.sphere(Vector3.ZERO, 0.16 * scale, wood, "vc_gloss", Vector3(1.0, 1.25, 0.35), 12)
			b.sphere(Vector3(0, 0, 0.05 * scale), 0.05 * scale, Color("1a1410"), "vc", Vector3(1, 1, 0.2), 8)
			b.box(Vector3(0, 0.15 * scale, 0), Vector3(0.05, 0.48 * scale, 0.038), Color("2b1d14"), "vc_gloss")
		"violin":
			b.sphere(Vector3.ZERO, 0.085, Color("8a3a1a"), "vc_gloss", Vector3(1.0, 1.4, 0.4), 10)
			b.box(Vector3(0, 0.14, 0), Vector3(0.028, 0.19, 0.028), Color("1a1410"))
		"bow":
			b.box(Vector3.ZERO, Vector3(0.01, 0.48, 0.01), Color("2b1d14"))
		"mic":
			b.cylinder(Vector3(0, 0, 0), 0.015, 1.25, Color("2b2b30"), "vc_metal", 6)
			b.cylinder(Vector3(0, 0, 0), 0.12, 0.02, Color("2b2b30"), "vc_metal", 10)
			b.sphere(Vector3(0, 1.29, 0), 0.04, Color("8a8f98"), "vc_metal", Vector3.ONE, 8)

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
	match str(look.extra):
		"bowtie":
			_add_mesh(_holder("UpperChest", Vector3(0, neck.y - 0.05, front + 0.01)), _mesh("bowtie"), Vector3.ZERO)
		"flower":
			_add_mesh(_holder("UpperChest", Vector3(0.09, neck.y - 0.1, front)), _mesh("flower"), Vector3.ZERO)
	if str(look.instrument) != "":
		var kind: String = look.instrument
		match kind:
			"accordion":
				instrument = _holder("UpperChest", Vector3(0, neck.y - 0.24, front + 0.14))
			"violin":
				instrument = _holder("LeftShoulder", Vector3(0.12, neck.y - 0.02, front), Vector3(0.4, 0.3, 1.1))
			"mic":
				instrument = Node3D.new()
				instrument.position = Vector3(0, 0, 0.36)
				model.add_child(instrument)
			_:
				instrument = _holder("UpperChest", Vector3(0.02, neck.y - 0.3, front + 0.07), Vector3(0, 0, -0.9))
		_add_mesh(instrument, _mesh(kind), Vector3.ZERO)
		if kind == "violin":
			_add_mesh(hand, _mesh("bow"), Vector3.ZERO, Vector3(0, 0, 1.2))
	phase = randf() * TAU
	blink_in = randf_range(0.5, 4.0)
	mood = str(look.mood)
	face_now_values = FACES[mood].duplicate()
	play("idle")

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
	parent.add_child(node)
	return node

## A drink in front of a guest (shared mesh, base at the origin).
static func vessel_mesh(kind: String) -> Mesh:
	return _mesh(kind if VESSELS.has(kind) else "water")

## Hold something in the right hand: "", "tray" or "cloth".
func hold(kind: String) -> void:
	if kind == holding:
		return
	holding = kind
	for child in hand.get_children():
		if child.get_meta("held", false):
			child.queue_free()
	if kind != "":
		var held: MeshInstance3D = _add_mesh(hand, _mesh(kind), Vector3(0, 0.03 if kind == "tray" else 0.0, 0.04))
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
	hold("tray" if name in ["carry", "carry_idle"] else ("cloth" if name == "wipe" else ""))
	var kind: String = str(look.get("kind", ""))
	var chatty: bool = int(phase * 10.0) % 2 == 0
	var wanted: String = "Idle"
	talking = false
	match name:
		"walk":
			wanted = "Walk_Formal" if kind in ["ozalosceni", "biznismen"] else "Walk"
		"carry":
			wanted = "Walk_Carry"
		"carry_idle":
			wanted = "Hold_Tray"
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
			wanted = {"accordion": "Play_Squeeze", "mic": "Play_Sing"}.get(str(look.instrument), "Play_Strum")
			talking = look.instrument == "mic"
		_:
			if kind == "bouncer":
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

## Two-bone IK on the right arm: the wrist goes to `target` with the elbow bent towards `pole`
## (both global), blended with the animated arm by `weight`.
func _reach(target: Vector3, pole: Vector3, weight: float) -> void:
	if weight <= 0.001:
		return
	var ua: int = bones["RightUpperArm"]
	var la: int = bones["RightLowerArm"]
	var hd: int = bones["RightHand"]
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
		"carry", "carry_idle":
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
	if not path.is_empty():
		var target: Vector3 = path[0]
		var offset: Vector3 = target - position
		offset.y = 0.0
		var step: float = WALK_SPEED * speed_scale * delta
		face(offset)
		if seat_state in ["pulling", "stepping"]:
			if clip != "Walk":
				_clip("Walk", 0.2, true)
		elif current not in ["walk", "carry", "angry"]:
			play("carry" if holding == "tray" else "walk")
		clip_rate = WALK_SPEED * speed_scale / maxf(0.3, float(measure.stride) * scale.x)
		if offset.length() <= step:
			position = Vector3(target.x, position.y, target.z)
			path.remove_at(0)
			if path.is_empty():
				arrived.emit()
		else:
			position += offset.normalized() * step
	elif current == "angry" and not _seated_clip(clip):
		play("idle")
	if not seat.is_empty():
		_seat_step(delta)
	_drink_step(delta)
	heading = lerp_angle(heading, target_heading, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = heading
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
	var lift: float = HEAD_LIFT * (0.6 if current == "angry" else (1.6 if seat_state == "seated" else 1.0))
	lift += _sip_amount() * 0.3
	_turn("Head", Vector3(-lift, sin(t * 0.7 + phase) * 0.12 * (1.0 - _sip_amount()), 0))
	match current:
		"dance":
			model.position.y = absf(sin(t * 6.0 + phase)) * 0.04
		"play":
			var beat: float = sin(t * 8.0 + phase)
			match str(look.instrument):
				"accordion":
					instrument.scale = Vector3(1.0 + beat * 0.15, 1, 1)
					_turn("Spine", Vector3(0, beat * 0.08, 0))
				"mic":
					_turn("Spine", Vector3(0, sin(t * 2.0 + phase) * 0.1, 0))
				_:
					_turn("RightLowerArm", Vector3(beat * 0.25, 0, 0))
			model.position.y = absf(sin(t * 4.0 + phase)) * 0.015
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
