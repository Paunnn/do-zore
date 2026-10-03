extends SceneTree
## Writes humanoid BoneMaps for the Unreal-style skeletons (UAL animations and MakeHuman game_engine rig).
const MAP := {
	"Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03", "Neck": "neck_01",
	"LeftShoulder": "clavicle_l", "LeftUpperArm": "upperarm_l", "LeftLowerArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightUpperArm": "upperarm_r", "RightLowerArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpperLeg": "thigh_l", "LeftLowerLeg": "calf_l", "LeftFoot": "foot_l", "LeftToes": "ball_l",
	"RightUpperLeg": "thigh_r", "RightLowerLeg": "calf_r", "RightFoot": "foot_r", "RightToes": "ball_r",
}
const FINGERS := {"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Little": "pinky"}

func make(root_name: String, head_name: String) -> BoneMap:
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	map.set_skeleton_bone_name("Root", root_name)
	map.set_skeleton_bone_name("Head", head_name)
	for key in MAP:
		map.set_skeleton_bone_name(key, MAP[key])
	for side in [["Left", "l"], ["Right", "r"]]:
		for finger in FINGERS:
			var parts: Array = ["Metacarpal", "Proximal", "Distal"] if finger == "Thumb" else ["Proximal", "Intermediate", "Distal"]
			for i in range(3):
				map.set_skeleton_bone_name("%s%s%s" % [side[0], finger, parts[i]], "%s_0%d_%s" % [FINGERS[finger], i + 1, side[1]])
	return map

func _initialize():
	ResourceSaver.save(make("root", "Head"), "res://assets/people/ual_bones.tres")
	ResourceSaver.save(make("Root", "head"), "res://assets/people/mh_bones.tres")
	print("bone maps written")
	quit()
