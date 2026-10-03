"""Cartoon people for Do Zore, built in Blender from MakeHuman bodies (CC0).

Each look becomes one GLB: a game_engine rig (Unreal-style bone names, so the Quaternius animation library
retargets onto it) and one skinned mesh with one material. The bodies are reshaped into cartoon proportions
(big round head, shorter legs, bigger hands and feet) before the clothes and hair are fitted, so everything
follows the new shape. The face is cleaned into one smooth surface: the game's character shader draws the
eyes, brows and mouth on it (client/shaders/person.gdshader), which is what lets every emotion show.

The mesh carries what the shader needs:
- UV:  an atlas with the cartoonised textures of the hair and clothes (see prep_textures.py), written next
  to the GLB as LOOK_atlas.png;
- UV2: the face plane, eyes at (0.31, 0.41) and (0.69, 0.41), mouth at (0.5, 0.79);
- COLOR: r = palette slot (skin, hair, top, bottom, shoes, hat), g = face mask, b = 1 to keep the texture's
  own colours instead of tinting it with the palette.

Run with Blender 4.5 and the MPFB 2 add-on (see setup.sh):

    blender -b --python tools/art/people/build_people.py -- OUT_DIR [look ...]
"""
import importlib
import json
import os
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

CACHE = os.environ.get("DO_ZORE_ART_CACHE", os.path.expanduser("~/.cache/do-zore-art"))
MPFB_DATA = os.path.join(CACHE, "mpfb2/src/mpfb/data")
MH = os.path.join(CACHE, "mh/data")
TOON_TEX = os.path.join(CACHE, "toon_tex")
WEIGHTS = json.load(open(os.path.join(MPFB_DATA, "rigs/standard/weights.game_engine.json")))["weights"]
ATLAS = 1024


def _mpfb(path, key):
    for name in list(sys.modules):
        if name.endswith(path):
            return getattr(importlib.import_module(name), key)
    raise ImportError(f"MPFB is not enabled in this Blender ({path})")


HumanService = _mpfb("mpfb.services.humanservice", "HumanService")
AssetService = _mpfb("mpfb.services.assetservice", "AssetService")
TargetService = _mpfb("mpfb.services.targetservice", "TargetService")

# Palette slot per part (vertex colour red channel) and its cell in the texture atlas (x, y, size, from top-left).
REGION = {"skin": 0.0, "hair": 0.2, "top": 0.4, "bottom": 0.6, "shoes": 0.8, "hat": 1.0}
CELLS = {"hair": (0, 0, 512), "top": (512, 0, 512), "bottom": (0, 512, 512), "shoes": (512, 512, 256),
         "hat": (768, 512, 256), "extra": (512, 768, 256), "skin": (768, 768, 256)}

STYLE = {"head": 2.2, "legs": 0.72, "torso": 0.85, "hands": 1.3, "feet": 1.25, "nose": 0.75, "jaw": 0.8,
         "cheeks": 1.1, "smooth": 0.6, "smooth_iter": 40}

CAUCASIAN = {"asian": 0.0, "caucasian": 1.0, "african": 0.0}

# The cast. Parts: (asset folder, asset, palette slot, keep the texture's colours). Tinted parts take their
# colour from the person's palette in the game, so one look serves many people.
MAN = {"gender": 1.0, "age": 0.5, "weight": 0.5, "muscle": 0.5, "height": 0.55}
WOMAN = {"gender": 0.0, "age": 0.5, "weight": 0.5, "muscle": 0.45, "height": 0.5}
SHOES_M, SHOES_W = ("clothes", "shoes03", "shoes", True), ("clothes", "shoes04", "shoes", True)
LOOKS = {
    # Guests
    "deda": {"macro": dict(MAN, age=0.85, weight=0.72, muscle=0.45, height=0.4), "hair": "short02",
             "parts": [("clothes", "toigo_fisherman_sweater", "top", False),
                       ("clothes", "toigo_wool_pants", "bottom", False), ("clothes", "shoes01", "shoes", True)]},
    "deda2": {"macro": dict(MAN, age=0.9, weight=0.6, height=0.45), "hair": "short01",
              "parts": [("clothes", "male_casualsuit05", "top", True), ("clothes", "shoes01", "shoes", True)]},
    "baba": {"style": {"leg_slim": 0.8}, "macro": dict(WOMAN, age=0.85, weight=0.75, muscle=0.4, height=0.35), "hair": "toigo_curled_under_bob",
             "parts": [("clothes", "toigo_shift_dress", "top", False), SHOES_W]},
    "student": {"macro": dict(MAN, age=0.45, weight=0.45), "hair": "short04",
                "parts": [("clothes", "elvs_crude_t-shirt_male", "top", False),
                          ("clothes", "cortu_cargo_pants", "bottom", False), ("clothes", "shoes06", "shoes", True)]},
    "studentkinja": {"macro": dict(WOMAN, age=0.45, weight=0.45), "hair": "ponytail01",
                     "parts": [("clothes", "toigo_basic_tucked_t-shirt", "top", False),
                               ("clothes", "toigo_wool_pants", "bottom", False), ("clothes", "shoes05", "shoes", True)]},
    "svat": {"macro": dict(MAN, age=0.5), "hair": "short01",
             "parts": [("clothes", "toigo_male_suit_tie_and_jacket", "top", True), SHOES_M]},
    "svatica": {"style": {"leg_slim": 0.8}, "macro": dict(WOMAN, age=0.5), "hair": "toigo_curled_under_bob_with_bangs",
                "parts": [("clothes", "toigo_halter_dress_knee_length", "top", False), SHOES_W]},
    "biznismen": {"macro": dict(MAN, age=0.62, weight=0.65), "hair": "short03",
                  "parts": [("clothes", "toigo_male_suit_3", "top", True), SHOES_M]},
    "biznismenka": {"macro": dict(WOMAN, age=0.55), "hair": "toigo_inverted_bob",
                    "parts": [("clothes", "female_elegantsuit01", "top", True), SHOES_W]},
    "ozaloscen": {"macro": dict(MAN, age=0.6, weight=0.55), "hair": "short01",
                  "parts": [("clothes", "toigo_male_double-breasted_suit", "top", False), SHOES_M]},
    "ozaloscena": {"style": {"leg_slim": 0.8}, "macro": dict(WOMAN, age=0.65, weight=0.6), "hair": "toigo_curled_under_bob",
                   "parts": [("clothes", "toigo_shift_dress", "top", False), SHOES_W]},
    # Staff
    "konobar": {"macro": dict(MAN, age=0.55), "hair": "short01",
                "parts": [("clothes", "toigo_suit_with_dinner_jacket", "top", True), SHOES_M]},
    "konobarica": {"macro": dict(WOMAN, age=0.5), "hair": "ponytail01",
                   "parts": [("clothes", "toigo_basic_tucked_t-shirt", "top", False),
                             ("clothes", "toigo_wool_pants", "bottom", False), SHOES_W]},
    "sanker": {"macro": dict(MAN, age=0.65, weight=0.75), "hair": "short02",
               "parts": [("clothes", "namuhekam_male_polo_shirt", "top", False),
                         ("clothes", "toigo_wool_pants", "bottom", False), SHOES_M]},
    "izbacivac": {"macro": dict(MAN, age=0.55, weight=0.7, muscle=0.95, height=0.7), "hair": "",
                  "parts": [("clothes", "elvs_crude_t-shirt_male", "top", False),
                            ("clothes", "cortu_cargo_pants", "bottom", False), SHOES_M]},
    # Band
    "muzicar": {"macro": dict(MAN, age=0.55, weight=0.6), "hair": "short04",
                "parts": [("clothes", "namuhekam_male_polo_shirt", "top", False),
                          ("clothes", "toigo_wool_pants", "bottom", False), SHOES_M]},
    "pevacica": {"style": {"leg_slim": 0.8}, "macro": dict(WOMAN, age=0.55), "hair": "long01",
                 "parts": [("clothes", "toigo_halter_dress_midi", "top", False), SHOES_W]},
}

# Triangle budgets per part. The face is drawn on a plane projection (UV2), so it stays exact on a
# coarser mesh.
BUDGET = {"skin": 3500, "hair": 1500, "top": 2200, "bottom": 1200, "shoes": 500, "hat": 600, "extra": 1200}


def find(name, subdir):
    path = AssetService.find_asset_absolute_path(name, asset_subdir=subdir)
    if path is None:
        raise FileNotFoundError(f"{subdir}/{name} (is the MakeHuman asset pack installed?)")
    return path


def bone_weight(names, count):
    w = np.zeros(count, np.float32)
    for name in names:
        for index, value in WEIGHTS.get(name, []):
            if index < count:
                w[index] += value
    return np.clip(w, 0.0, 1.0)


def group_mask(obj, name):
    group = obj.vertex_groups.get(name)
    mask = np.zeros(len(obj.data.vertices), np.float32)
    if group is None:
        return mask
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group == group.index:
                mask[v.index] = g.weight
    return mask


def mix_coords(obj):
    """Vertex positions with every shape key applied at its current value."""
    key = obj.shape_key_add(name="tmp_mix", from_mix=True)
    co = np.empty(len(obj.data.vertices) * 3, np.float32)
    key.data.foreach_get("co", co)
    obj.shape_key_remove(key)
    return co.reshape(-1, 3)


def centroid(obj, coords, group):
    return coords[group_mask(obj, group) > 0.5].mean(axis=0)


def laplacian(V, edges, strength, iterations):
    n = len(V)
    a, b = edges[:, 0], edges[:, 1]
    deg = np.maximum(np.bincount(a, minlength=n) + np.bincount(b, minlength=n), 1)[:, None]
    for _ in range(iterations):
        acc = np.zeros_like(V)
        np.add.at(acc, a, V[b])
        np.add.at(acc, b, V[a])
        V = V + (acc / deg - V) * strength[:, None]
    return V


def cartoonify(bm, style):
    """Adds the 'cartoon' shape key. Runs before the rig, clothes and hair so they all follow it."""
    n = len(bm.data.vertices)
    V0 = mix_coords(bm)
    # Close the eyes first (the game draws them), so the lids meet and smooth into one surface.
    for side in ("Left", "Right"):
        TargetService.load_target(bm, os.path.join(MH, f"targets/faceunits/eyeBlink{side}.target"), weight=1.0,
                                  name=f"tmp_blink{side}")
    V = mix_coords(bm)
    for block in list(bm.data.shape_keys.key_blocks):
        if block.name.startswith("tmp_blink"):
            bm.shape_key_remove(block)
    edges = np.empty(len(bm.data.edges) * 2, np.int32)
    bm.data.edges.foreach_get("vertices", edges)
    edges = edges.reshape(-1, 2)
    head_w = bone_weight(["head"], n)
    body = group_mask(bm, "body") > 0.5
    eye_l, eye_r = centroid(bm, V, "helper-l-eye"), centroid(bm, V, "helper-r-eye")
    lips = centroid(bm, V, "lips")
    face_c = (eye_l + eye_r) * 0.5 * 0.55 + lips * 0.45
    eye_dist = np.linalg.norm(eye_l - eye_r)
    # Stitch the closed lids: tie each rim vertex to its nearest partner across the slit while smoothing.
    edge_faces = {}
    for poly in bm.data.polygons:
        vs = poly.vertices
        for i in range(len(vs)):
            k = tuple(sorted((vs[i], vs[(i + 1) % len(vs)])))
            edge_faces[k] = edge_faces.get(k, 0) + 1
    boundary = {v for k, c in edge_faces.items() if c == 1 for v in k}
    near_face = np.linalg.norm(V - face_c, axis=1) < eye_dist * 1.6
    rim = np.array([i for i in boundary if body[i] and near_face[i]], np.int32)
    extra = []
    for k, i in enumerate(rim):
        d = np.linalg.norm(V[rim] - V[i], axis=1)
        d[k] = 1e9
        extra += [(i, rim[j]) for j in np.argsort(d)[:4] if d[j] < eye_dist * 0.06]
    if extra:
        edges = np.concatenate([edges, np.array(extra, np.int32)])
    # Smooth away the realistic detail of the face (not the mouth: its inside is removed at export).
    r = np.linalg.norm((V - face_c) * np.array([1.0, 0.6, 1.0]), axis=1) / eye_dist
    front = V[:, 1] < face_c[1] + eye_dist * 0.5
    smooth_w = np.clip(1.4 - r * 0.9, 0.0, 1.0) * head_w * front * body * (1.0 - group_mask(bm, "ears"))
    smooth_w *= np.clip(np.linalg.norm(V - lips, axis=1) / (eye_dist * 0.55) - 0.4, 0.0, 1.0)
    V = laplacian(V, edges, smooth_w * style["smooth"], style["smooth_iter"])
    # A small round nose.
    tip = V[np.argmin(np.where(smooth_w > 0.5, V[:, 1], 1e9))].copy()
    nose_w = np.clip(1.0 - np.linalg.norm(V - tip, axis=1) / eye_dist / 0.55, 0, 1) ** 1.5 * head_w
    root = tip + np.array([0, eye_dist * 0.35, eye_dist * 0.05])
    V = V + ((root + (V - root) * style["nose"]) - V) * nose_w[:, None]
    # A rounder face: shorter jaw, fuller cheeks.
    eye_z = (eye_l[2] + eye_r[2]) * 0.5
    V[:, 2] = V[:, 2] + (eye_z - V[:, 2]) * (1.0 - style["jaw"]) * head_w * (V[:, 2] < eye_z)
    cheek = np.exp(-(((V[:, 2] - (eye_z - eye_dist * 0.75)) / (eye_dist * 0.7)) ** 2)) * head_w
    V[:, 0] = face_c[0] + (V[:, 0] - face_c[0]) * (1.0 + (style["cheeks"] - 1.0) * cheek)
    # Bigger hands and feet.
    for side in ("l", "r"):
        fingers = [f"{f}_0{i}_{side}" for f in ("index", "middle", "ring", "pinky", "thumb") for i in (1, 2, 3)]
        hw = bone_weight([f"hand_{side}"] + fingers, n)
        wrist = centroid(bm, V0, f"joint-{side}-hand")
        V = V + ((wrist + (V - wrist) * style["hands"]) - V) * hw[:, None]
        fw = bone_weight([f"foot_{side}", f"ball_{side}"], n)
        ankle = centroid(bm, V0, f"joint-{side}-ankle")
        V = V + ((ankle + (V - ankle) * style["feet"]) - V) * fw[:, None]
    # Slimmer legs under dresses, so they don't poke through the skirt when walking.
    if style.get("leg_slim", 1.0) != 1.0:
        for side in ("l", "r"):
            lw = bone_weight([f"thigh_{side}", f"calf_{side}"], n)
            axis = centroid(bm, V0, f"joint-{side}-upper-leg")
            V[:, 0] = V[:, 0] + (axis[0] + (V[:, 0] - axis[0]) * style["leg_slim"] - V[:, 0]) * lw
            V[:, 1] = V[:, 1] + (axis[1] + (V[:, 1] - axis[1]) * style["leg_slim"] - V[:, 1]) * lw
    # Shorter legs and torso.
    leg_w = bone_weight(["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"], n)
    hip_z = centroid(bm, V0, "joint-pelvis")[2]
    neck_z = centroid(bm, V0, "joint-head")[2]
    z = V[:, 2].copy()
    body_z = np.where(z < neck_z, hip_z * style["legs"] + (z - hip_z) * style["torso"],
                      hip_z * style["legs"] + (neck_z - hip_z) * style["torso"] + (z - neck_z))
    V[:, 2] = leg_w * z * style["legs"] + (1.0 - leg_w) * body_z
    # The big head, grown about the chin so it stays on the collar. The neck and head joint cubes (which
    # place the bones) stay where a neck would be.
    pivot = centroid(bm, V0, "joint-head").copy()
    pivot[2] = V[(head_w > 0.99) & body, 2].min()
    cubes = np.zeros(n, bool)
    for g in ("joint-head", "joint-head-2", "joint-neck", "joint-l-eye", "joint-r-eye"):
        cubes |= group_mask(bm, g) > 0.5
    scale_w = np.where(cubes, 0.0, head_w)
    V = V + ((pivot + (V - pivot) * style["head"]) - V) * scale_w[:, None]
    basis = np.empty(n * 3, np.float32)
    bm.data.shape_keys.key_blocks[0].data.foreach_get("co", basis)
    key = bm.shape_key_add(name="cartoon", from_mix=False)
    key.data.foreach_set("co", (basis.reshape(-1, 3) + (V - V0)).reshape(-1))
    key.value = 1.0


def build(look):
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    macro = {"gender": 0.5, "age": 0.5, "muscle": 0.5, "weight": 0.5, "proportions": 0.5, "height": 0.5,
             "cupsize": 0.5, "firmness": 0.5, "race": dict(CAUCASIAN)}
    macro.update(look["macro"])
    bm = HumanService.create_human(macro_detail_dict=macro, feet_on_ground=True)
    cartoonify(bm, dict(STYLE, **look.get("style", {})))
    HumanService.add_builtin_rig(bm, "game_engine")
    parts = {bm.name: ("skin", True)}
    wanted = list(look.get("parts", []))
    if look.get("hair"):
        wanted.insert(0, ("hair", look["hair"], "hair", False))
    for subdir, name, region, keep in wanted:
        kind = "Hair" if subdir == "hair" else "Clothes"
        obj = HumanService.add_mhclo_asset(find(name + ".mhclo", subdir), bm, asset_type=kind,
                                           material_type="GAMEENGINE", subdiv_levels=0)
        parts[obj.name] = (region, keep)
    V = mix_coords(bm)
    face = {"eye_l": centroid(bm, V, "helper-l-eye"), "eye_r": centroid(bm, V, "helper-r-eye"),
            "lips": centroid(bm, V, "lips")}
    return bm, parts, face


def clean_face(obj, face):
    """Remove the inside of the mouth and eye sockets, close the slits and smooth the face into one surface."""
    eye_l, eye_r, lips = Vector(face["eye_l"]), Vector(face["eye_r"]), Vector(face["lips"])
    ed = (eye_l - eye_r).length
    eye_z = (eye_l.z + eye_r.z) * 0.5
    cx = (eye_l.x + eye_r.x) * 0.5
    front_y = min(eye_l.y, eye_r.y, lips.y)
    bmsh = bmesh.new()
    bmsh.from_mesh(obj.data)

    def in_region(co):
        return abs(co.x - cx) < ed * 1.05 and lips.z - ed * 0.55 < co.z < eye_z + ed * 0.45 and co.y < front_y + ed * 0.9

    def in_cavity(co):
        if abs(co.x - cx) < ed * 0.75 and abs(co.z - lips.z) < ed * 0.4:
            return True
        return any(abs(co.x - e.x) < ed * 0.45 and abs(co.z - e.z) < ed * 0.3 for e in (eye_l, eye_r))

    tree = BVHTree.FromBMesh(bmsh)
    hidden = []
    for f in bmsh.faces:
        c = f.calc_center_median()
        if not (in_region(c) and in_cavity(c)):
            continue
        seen = False
        for d in (Vector((0, -1, 0)), f.normal, (Vector((0, -1, 0)) + f.normal)):
            if d.length > 0.5 and tree.ray_cast(c + d.normalized() * 0.0005, d.normalized(), 0.3)[0] is None:
                seen = True
                break
        if not seen:
            hidden.append(f)
    bmesh.ops.delete(bmsh, geom=hidden, context='FACES')
    bmesh.ops.delete(bmsh, geom=[v for v in bmsh.verts if not v.link_faces], context='VERTS')
    rim = [v for v in bmsh.verts if v.is_boundary and in_region(v.co)]
    bmesh.ops.remove_doubles(bmsh, verts=rim, dist=ed * 0.07)
    holes = [e for e in bmsh.edges if e.is_boundary and in_region(e.verts[0].co)]
    filled = bmesh.ops.holes_fill(bmsh, edges=holes, sides=0)
    if filled["faces"]:
        bmesh.ops.triangulate(bmsh, faces=filled["faces"])
    centre = Vector((cx, front_y, (eye_z + lips.z) * 0.5))
    weight = {}
    for v in bmsh.verts:
        if in_region(v.co) and not v.is_boundary:
            r = ((v.co - centre) * Vector((1.0 / ed, 0.6 / ed, 1.0 / ed))).length
            weight[v] = max(0.0, min(1.0, 1.5 - r * 1.1))
    for _ in range(25):
        moved = {}
        for v, w in weight.items():
            if w > 0.0 and v.link_edges:
                avg = sum((e.other_vert(v).co for e in v.link_edges), Vector()) / len(v.link_edges)
                moved[v] = v.co + (avg - v.co) * 0.5 * w
        for v, co in moved.items():
            v.co = co
    bmsh.normal_update()
    bmsh.to_mesh(obj.data)
    bmsh.free()
    obj.data.update()


def image_of(obj):
    """The colour texture of a part: the image feeding the base colour, else the likeliest-named one."""
    images = []
    for slot in obj.material_slots:
        if not (slot.material and slot.material.use_nodes):
            continue
        tree = slot.material.node_tree
        for node in tree.nodes:
            if node.type == 'BSDF_PRINCIPLED':
                pending = [link.from_node for link in node.inputs["Base Color"].links]
                while pending:
                    upstream = pending.pop()
                    if upstream.type == 'TEX_IMAGE' and upstream.image:
                        return upstream.image
                    for socket in upstream.inputs:
                        pending += [link.from_node for link in socket.links]
        images += [n.image for n in tree.nodes if n.type == 'TEX_IMAGE' and n.image]
    skip = ("norm", "spec", "bump", "height", "_ao", "rough", "disp")
    for image in images:
        if not any(word in image.name.lower() for word in skip):
            return image
    return None


def decimate(obj, target, protect=None):
    """Collapse-decimate a part down to about `target` triangles; `protect` is a vertex group to keep."""
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris <= target:
        return
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("decimate", 'DECIMATE')
    modifier.ratio = target / tris
    if protect:
        modifier.vertex_group = protect
        modifier.invert_vertex_group = True
        modifier.vertex_group_factor = 1.0
    bpy.ops.object.modifier_apply(modifier="decimate")


def load_pixels(image, size):
    """The cartoonised copy of an image (if prep_textures.py made one), as top-left-origin RGBA floats."""
    path = bpy.path.abspath(image.filepath)
    toon = os.path.join(TOON_TEX, os.path.basename(path))
    if os.path.exists(toon):
        image = bpy.data.images.load(toon, check_existing=True)
    w, h = image.size
    px = np.empty(w * h * 4, np.float32)
    image.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[::-1]
    ys = (np.arange(size) + 0.5) * h / size
    xs = (np.arange(size) + 0.5) * w / size
    # Box-average down to the cell size.
    step = max(1, w // size)
    if w % size == 0 and h % size == 0:
        return px.reshape(size, h // size, size, w // size, 4).mean(axis=(1, 3))
    return px[ys.astype(int)][:, xs.astype(int)]


def finish(bm, parts, face, path):
    armature = bm.parent
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    for obj in meshes:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        if obj.data.shape_keys:
            co = mix_coords(obj)
            obj.shape_key_clear()
            obj.data.vertices.foreach_set("co", co.reshape(-1))
            obj.data.update()
        for modifier in list(obj.modifiers):
            if modifier.type in ('MASK', 'SUBSURF'):
                bpy.ops.object.modifier_apply(modifier=modifier.name)
    clean_face(bm, face)
    # Keep the body inside its clothes: clothes stand a few millimetres proud, the covered body shrinks a
    # little (head, hands and feet stay as they are).
    for obj in meshes:
        n = len(obj.data.vertices)
        co = np.empty(n * 3, np.float32)
        obj.data.vertices.foreach_get("co", co)
        nor = np.empty(n * 3, np.float32)
        obj.data.vertices.foreach_get("normal", nor)
        co, nor = co.reshape(-1, 3), nor.reshape(-1, 3)
        if obj == bm:
            keep = np.zeros(n, np.float32)
            for bone in ["head", "neck_01", "hand_l", "hand_r", "foot_l", "foot_r", "ball_l", "ball_r"] + \
                    [f"{f}_0{i}_{s}" for f in ("index", "middle", "ring", "pinky", "thumb") for i in (1, 2, 3) for s in "lr"]:
                keep = np.maximum(keep, group_mask(obj, bone))
            co -= nor * (0.005 * (1.0 - keep))[:, None]
        elif parts.get(obj.name, ("", True))[0] in ("top", "bottom"):
            co += nor * 0.004
        obj.data.vertices.foreach_set("co", co.reshape(-1))
        obj.data.update()
    eye_l, eye_r, lips = face["eye_l"], face["eye_r"], face["lips"]
    mid = (eye_l + eye_r) * 0.5
    sx = 0.36 / abs(eye_l[0] - eye_r[0])
    sz = 0.38 / max(mid[2] - lips[2], 1e-3)
    atlas = np.zeros((ATLAS, ATLAS, 4), np.float32)
    x, y, s = CELLS["skin"]
    atlas[y:y + s, x:x + s] = 1.0
    used = {"skin"}
    for obj in meshes:
        mesh = obj.data
        region, keep = parts.get(obj.name, ("top", True))
        n = len(mesh.vertices)
        co = np.empty(n * 3, np.float32)
        mesh.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        nor = np.empty(n * 3, np.float32)
        mesh.vertices.foreach_get("normal", nor)
        nor = nor.reshape(-1, 3)
        color = np.zeros((n, 4), np.float32)
        color[:, 0] = REGION[region]
        color[:, 2] = 1.0 if keep and obj != bm else 0.0
        color[:, 3] = 1.0
        cu = 0.5 + (co[:, 0] - mid[0]) * sx
        cv = 0.42 + (mid[2] - co[:, 2]) * sz
        if obj == bm:
            oval = np.sqrt(((cu - 0.5) / 0.56) ** 2 + ((cv - 0.6) / 0.52) ** 2)
            mask = np.clip((1.0 - oval) / 0.12, 0, 1) * np.clip((-nor[:, 1] + 0.05) / 0.3, 0, 1)
            color[:, 1] = mask * (group_mask(obj, "head") > 0.5)
        attr = mesh.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
        attr.data.foreach_set("color", color.reshape(-1))
        mesh.color_attributes.active_color = attr
        # Atlas cell for this part.
        cell = region if region not in used or region == "skin" else "extra"
        used.add(cell)
        x, y, s = CELLS[cell]
        image = image_of(obj) if obj != bm else None
        if image is not None:
            atlas[y:y + s, x:x + s] = load_pixels(image, s)
            if region != "hair":
                # Clothes are solid; only hair keeps its cut-out edge.
                atlas[y:y + s, x:x + s, 3] = 1.0
        elif cell != "skin":
            atlas[y:y + s, x:x + s] = 1.0
        loops = np.empty(len(mesh.loops), np.int32)
        mesh.loops.foreach_get("vertex_index", loops)
        while len(mesh.uv_layers) > 1:
            mesh.uv_layers.remove(mesh.uv_layers[-1])
        if not mesh.uv_layers:
            mesh.uv_layers.new(name="UVMap")
        uv = mesh.uv_layers[0]
        uv.name = "UVMap"
        data = np.empty(len(mesh.loops) * 2, np.float32)
        uv.data.foreach_get("uv", data)
        data = np.clip(data.reshape(-1, 2), 0.0, 1.0)
        margin = 3.0
        u = (x + margin + data[:, 0] * (s - 2 * margin)) / ATLAS
        v = 1.0 - (y + margin + (1.0 - data[:, 1]) * (s - 2 * margin)) / ATLAS
        if obj == bm:
            u = np.full_like(u, (x + s * 0.5) / ATLAS)
            v = np.full_like(v, 1.0 - (y + s * 0.5) / ATLAS)
        uv.data.foreach_set("uv", np.stack([u, v], axis=1).reshape(-1))
        face_uv = mesh.uv_layers.new(name="Face")
        face_uv.data.foreach_set("uv", np.stack([cu[loops], 1.0 - cv[loops]], axis=1).reshape(-1).astype(np.float32))
        decimate(obj, BUDGET.get(cell, 2000))
    # One mesh, one material.
    bones = {b.name for b in armature.data.bones}
    for obj in meshes:
        bpy.context.view_layer.objects.active = obj
        for group in list(obj.vertex_groups):
            if group.name not in bones:
                obj.vertex_groups.remove(group)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bm
    bpy.ops.object.join()
    image = bpy.data.images.new("atlas", ATLAS, ATLAS, alpha=True)
    image.pixels.foreach_set(atlas[::-1].reshape(-1))
    image.filepath_raw = os.path.splitext(path)[0] + "_atlas.png"
    image.file_format = 'PNG'
    image.save()
    material = bpy.data.materials.new("person")
    material.use_nodes = True
    tex = material.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = image
    bsdf = material.node_tree.nodes["Principled BSDF"]
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    material.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    material.blend_method = 'CLIP'
    bm.data.materials.clear()
    bm.data.materials.append(material)
    for poly in bm.data.polygons:
        poly.material_index = 0
    bm.name = "Body"
    armature.name = "Armature"
    bpy.ops.object.select_all(action='DESELECT')
    armature.select_set(True)
    bm.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_animations=False,
                              export_skins=True, export_vertex_color='ACTIVE', export_all_vertex_colors=True,
                              export_yup=True, export_apply=False, export_image_format='NONE')
    return len(bm.data.vertices), sum(len(p.vertices) - 2 for p in bm.data.polygons)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    out_dir = args[0]
    os.makedirs(out_dir, exist_ok=True)
    for name in args[1:] or list(LOOKS):
        start = time.time()
        human, parts, face = build(LOOKS[name])
        verts, tris = finish(human, parts, face, os.path.join(out_dir, name + ".glb"))
        print(f"{name}: {verts} verts, {tris} tris, {time.time() - start:.1f} s")
