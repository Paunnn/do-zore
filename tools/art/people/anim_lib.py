"""The people's animation library: Quaternius' Universal Animation Library 1 and 2 (CC0), cut down to the
clips the game uses, on their armature with a token mesh (so Godot imports a skeleton).

    blender -b --python tools/art/people/anim_lib.py -- client/assets/people/people_anims.glb

The game retargets it through Godot's humanoid profile (assets/people/ual_bones.tres) and builds a few
clips from it at run time (scripts/world3d/people3d.gd).
"""
import os
import sys

import bpy

CACHE = os.environ.get("DO_ZORE_ART_CACHE", os.path.expanduser("~/.cache/do-zore-art"))
UAL1 = os.path.join(CACHE, "anim/ual1/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb")
UAL2 = os.path.join(CACHE, "anim/ual2/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb")
KEEP = {
    UAL1: ["A_TPose", "Idle_Loop", "Idle_Talking_Loop", "Walk_Loop", "Walk_Formal_Loop", "Jog_Fwd_Loop",
           "Sitting_Enter", "Sitting_Idle_Loop", "Sitting_Talking_Loop", "Sitting_Exit", "Dance_Loop",
           "Interact", "PickUp_Table", "Driving_Loop", "Spell_Simple_Idle_Loop", "Hit_Head"],
    UAL2: ["Consume", "Idle_FoldArms_Loop", "Idle_No_Loop", "Yes", "Idle_TalkingPhone_Loop", "Walk_Carry_Loop",
           "Idle_Rail_Call", "Idle_Rail_Loop", "Idle_Lantern_Loop", "Zombie_Walk_Fwd_Loop"],
}


def main(out):
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    kept = []
    armature = None
    first = set()
    for path, names in KEEP.items():
        before = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=path)
        for action in [a for a in bpy.data.actions if a not in before]:
            name = action.name.split("|")[-1]
            if name in names and name not in [k.name for k in kept]:
                action.name = name
                kept.append(action)
            else:
                bpy.data.actions.remove(action)
        if armature is None:
            armature = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
            first = {o.name for o in bpy.data.objects}
        else:
            # Only the clips of the second library are wanted; its armature and mesh go.
            for name in [o.name for o in bpy.data.objects if o.name not in first]:
                if name in bpy.data.objects:
                    bpy.data.objects.remove(bpy.data.objects[name])
    for obj in [o for o in bpy.data.objects if o.type == 'MESH' and o.parent != armature]:
        bpy.data.objects.remove(obj)
    meshes = [o for o in armature.children if o.type == 'MESH']
    mesh = meshes[0]
    for extra in meshes[1:]:
        bpy.data.objects.remove(extra)
    # A token skinned mesh is enough for the importer to build a Skeleton3D.
    bpy.context.view_layer.objects.active = mesh
    decimate = mesh.modifiers.new("decimate", 'DECIMATE')
    decimate.ratio = 0.01
    bpy.ops.object.modifier_apply(modifier="decimate")
    armature.animation_data_create()
    armature.animation_data.action = None
    for track in list(armature.animation_data.nla_tracks):
        armature.animation_data.nla_tracks.remove(track)
    for action in kept:
        action.use_fake_user = True
        track = armature.animation_data.nla_tracks.new()
        track.name = action.name
        track.strips.new(action.name, int(action.frame_range[0]), action)
    armature.name = "Armature"
    bpy.ops.object.select_all(action='DESELECT')
    armature.select_set(True)
    mesh.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format='GLB', export_animations=True,
                              export_animation_mode='NLA_TRACKS', export_skins=True, export_morph=False)
    print("clips:", ", ".join(a.name for a in kept))


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1])
