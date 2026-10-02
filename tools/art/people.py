"""Parametric chibi characters for the isometric kafana, drawn as SVG animation sheets.

Every frame is a 72x104 design-pixel cell with the feet (or the chair seat) at FOOT. Frames
face down-right ("front") or up-left ("back"); the game mirrors them for the other two
directions. Limbs are outlined capsules, so the figures match the outlined props.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

CELL_W, CELL_H = 72, 104
FOOT = (36.0, 98.0)
INK = "#2b1d14"
LINE = 1.7

SKIN = ["#f6d3b3", "#efc29c", "#e0a77e", "#c58a62", "#8d5b3d"]


def shade(color: str, amount: float) -> str:
    r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
    if amount >= 0:
        r, g, b = (round(c + (255 - c) * amount) for c in (r, g, b))
    else:
        r, g, b = (round(c * (1 + amount)) for c in (r, g, b))
    return f"#{r:02x}{g:02x}{b:02x}"


@dataclass
class Look:
    name: str
    skin: str = SKIN[1]
    hair: str = "#3a2a22"
    hair_style: str = "short"       # short messy long ponytail bun bald fringe slick curly bob none
    top: str = "#3b8fd0"
    top_style: str = "tshirt"       # tshirt shirt sweater hoodie suit vest cardigan dress jacket blazer
    accent: str = "#f4f1ea"         # shirt under suit/vest, collar, dress trim
    bottom: str = "#34405c"
    shoes: str = "#3a2a22"
    skirt: bool = False
    hat: str = ""                   # cap sajkaca scarf veil beanie fedora wreath
    hat_color: str = "#5a5a5f"
    extras: list = field(default_factory=list)  # glasses shades mustache beard chain tie bowtie flower backpack earrings
    tie: str = "#b8302f"
    build: float = 1.0              # torso width factor
    height: float = 1.0


# --------------------------------------------------------------------------------------------
# Pose: joint positions in cell pixels.
# --------------------------------------------------------------------------------------------

@dataclass
class Pose:
    view: str                 # front | back
    hip: tuple
    shoulder: tuple
    head: tuple
    near_foot: tuple
    far_foot: tuple
    near_hand: tuple
    far_hand: tuple
    near_knee: tuple | None = None
    far_knee: tuple | None = None
    sitting: bool = False
    mouth: str = "smile"      # smile open grin flat sad o
    eyes: str = "open"        # open happy closed
    prop: str = ""            # glass tray mic


def _walk_pose(view: str, phase: int, look: Look, carry: str = "") -> Pose:
    x0, y0 = FOOT
    step = [1, 0, -1, 0][phase]
    bob = [0.0, -1.6, 0.0, -1.6][phase]
    d = 1 if view == "front" else -1          # walking direction along the screen x axis
    hip = (x0, y0 - 30 * look.height + bob)
    shoulder = (x0 + 0.5 * d, hip[1] - 22 * look.height)
    head = (x0 + 1.0 * d, shoulder[1] - 15)
    reach = 7.0
    near_foot = (x0 - 3 + d * reach * step, y0 + 0.8 * step)
    far_foot = (x0 + 3 - d * reach * step, y0 - 1.2 - 0.8 * step)
    swing = 6.5
    near_hand = (shoulder[0] - 8 - d * swing * step, shoulder[1] + 19)
    far_hand = (shoulder[0] + 8 + d * swing * step, shoulder[1] + 18)
    if view == "back":
        near_hand, far_hand = (shoulder[0] + 8 - d * swing * step, shoulder[1] + 19), (shoulder[0] - 8 + d * swing * step, shoulder[1] + 18)
        near_foot, far_foot = (x0 + 3 + d * reach * step, y0 + 0.8 * step), (x0 - 3 - d * reach * step, y0 - 1.2 - 0.8 * step)
    pose = Pose(view, hip, shoulder, head, near_foot, far_foot, near_hand, far_hand)
    if carry == "tray":
        side = -1 if view == "front" else 1
        pose.near_hand = (shoulder[0] + side * 14, shoulder[1] - 4)
        pose.prop = "tray"
    return pose


def _idle_pose(view: str, look: Look, breathe: float = 0.0) -> Pose:
    x0, y0 = FOOT
    hip = (x0, y0 - 30 * look.height)
    shoulder = (x0, hip[1] - 22 * look.height + breathe)
    head = (x0 + (1 if view == "front" else -1), shoulder[1] - 15)
    if view == "front":
        return Pose(view, hip, shoulder, head, (x0 - 4, y0), (x0 + 4, y0 - 1.5), (shoulder[0] - 9, shoulder[1] + 19), (shoulder[0] + 9, shoulder[1] + 18))
    return Pose(view, hip, shoulder, head, (x0 + 4, y0), (x0 - 4, y0 - 1.5), (shoulder[0] + 9, shoulder[1] + 19), (shoulder[0] - 9, shoulder[1] + 18))


def _sit_pose(view: str, look: Look, drinking: bool = False) -> Pose:
    x0, y0 = FOOT
    hip = (x0 - (2 if view == "front" else -2), y0 - 19)
    shoulder = (hip[0] + (1.5 if view == "front" else -1.5), hip[1] - 21 * look.height)
    head = (shoulder[0] + (1.5 if view == "front" else -1.5), shoulder[1] - 15)
    if view == "front":
        knee_n, knee_f = (hip[0] + 9, hip[1] + 3), (hip[0] + 13, hip[1] + 1)
        pose = Pose(view, hip, shoulder, head, (knee_n[0] + 1, y0), (knee_f[0] + 1, y0 - 2),
                    (shoulder[0] + 9, shoulder[1] + 14), (shoulder[0] + 15, shoulder[1] + 12), knee_n, knee_f, sitting=True)
        if drinking:
            pose.near_hand = (head[0] + 5, head[1] + 9)
            pose.prop = "glass"
            pose.eyes = "happy"
        return pose
    knee_n, knee_f = (hip[0] - 9, hip[1] + 2), (hip[0] - 13, hip[1])
    pose = Pose(view, hip, shoulder, head, (knee_n[0], y0 - 4), (knee_f[0], y0 - 6),
                (shoulder[0] - 9, shoulder[1] + 13), (shoulder[0] - 13, shoulder[1] + 12), knee_n, knee_f, sitting=True)
    if drinking:
        pose.near_hand = (head[0] - 4, head[1] + 8)
        pose.prop = "glass"
    return pose


def _dance_pose(phase: int, look: Look) -> Pose:
    x0, y0 = FOOT
    sway = [-2.5, 0, 2.5, 0][phase]
    lift = [0, -3, 0, -3][phase]
    hip = (x0 + sway, y0 - 30 * look.height + lift)
    shoulder = (x0 + sway * 1.6, hip[1] - 22 * look.height)
    head = (shoulder[0] + sway * 0.6, shoulder[1] - 15)
    up_near = phase in (0, 1)
    near_hand = (shoulder[0] - 18, shoulder[1] - 15) if up_near else (shoulder[0] - 13, shoulder[1] + 6)
    far_hand = (shoulder[0] + 17, shoulder[1] - 15) if not up_near else (shoulder[0] + 13, shoulder[1] + 5)
    near_foot = (x0 - 5, y0 - (4 if phase == 1 else 0))
    far_foot = (x0 + 5, y0 - 1.5 - (4 if phase == 3 else 0))
    pose = Pose("front", hip, shoulder, head, near_foot, far_foot, near_hand, far_hand)
    pose.mouth = "open" if phase % 2 else "grin"
    pose.eyes = "happy"
    return pose


# --------------------------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------------------------

def capsule(a: tuple, b: tuple, width: float, color: str) -> str:
    return (f'<path d="M{a[0]:.1f} {a[1]:.1f} L{b[0]:.1f} {b[1]:.1f}" stroke="{INK}" stroke-width="{width + 2 * LINE:.1f}" stroke-linecap="round"/>'
            f'<path d="M{a[0]:.1f} {a[1]:.1f} L{b[0]:.1f} {b[1]:.1f}" stroke="{color}" stroke-width="{width:.1f}" stroke-linecap="round"/>')


def limb(points: list, width: float, color: str) -> str:
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in points)
    return (f'<path d="{d}" stroke="{INK}" stroke-width="{width + 2 * LINE:.1f}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>'
            f'<path d="{d}" stroke="{color}" stroke-width="{width:.1f}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>')


def leg(look: Look, pose: Pose, near: bool) -> str:
    hip_x = pose.hip[0] + ((-3 if near else 3) * (1 if pose.view == "front" else -1))
    foot = pose.near_foot if near else pose.far_foot
    knee = pose.near_knee if near else pose.far_knee
    bare = look.skirt or look.top_style == "dress"
    base = look.skin if bare else look.bottom
    color = base if near else shade(base, -0.08)
    pts = [(hip_x, pose.hip[1])] + ([knee] if knee else []) + [(foot[0], foot[1] - 3)]
    out = limb(pts, 5.2 if bare else 7.2, color)
    shoe_dx = 2.4 if pose.view == "front" else -2.4
    out += f'<ellipse cx="{foot[0] + shoe_dx:.1f}" cy="{foot[1] - 1.6:.1f}" rx="5" ry="3" fill="{look.shoes}" stroke="{INK}" stroke-width="{LINE}"/>'
    return out


def arm(look: Look, pose: Pose, near: bool) -> str:
    side = -1 if near else 1
    if pose.view == "back":
        side = -side
    sx = pose.shoulder[0] + side * 8.5 * look.build
    sy = pose.shoulder[1] + 2
    hand = pose.near_hand if near else pose.far_hand
    sleeve = look.top if look.top_style not in ("dress",) else look.skin
    if look.top_style == "vest":
        sleeve = look.accent
    elbow = ((sx + hand[0]) / 2 + side * 1.5, (sy + hand[1]) / 2 + 1)
    color = sleeve if near else shade(sleeve, -0.12)
    out = limb([(sx, sy), elbow, (hand[0], hand[1] - 1.5)], 5.6, color)
    out += f'<circle cx="{hand[0]:.1f}" cy="{hand[1]:.1f}" r="3.2" fill="{look.skin if near else shade(look.skin, -0.08)}" stroke="{INK}" stroke-width="{LINE}"/>'
    return out


def torso(look: Look, pose: Pose) -> str:
    (hx, hy), (sx, sy) = pose.hip, pose.shoulder
    w = 9.5 * look.build
    wh = 8.0 * look.build
    if look.top_style == "dress" and not pose.sitting:
        wh = 13 * look.build
        hy = hy + 10
    elif look.skirt and not pose.sitting:
        wh = 11
        hy = hy + 6
    body = (f'M{sx - w:.1f} {sy + 3:.1f} Q{sx - w:.1f} {sy - 1:.1f} {sx - w + 4:.1f} {sy - 1.5:.1f} '
            f'L{sx + w - 4:.1f} {sy - 1.5:.1f} Q{sx + w:.1f} {sy - 1:.1f} {sx + w:.1f} {sy + 3:.1f} '
            f'L{hx + wh:.1f} {hy + 1:.1f} Q{hx:.1f} {hy + 3.5:.1f} {hx - wh:.1f} {hy + 1:.1f} Z')
    top = look.top
    parts = [f'<path d="{body}" fill="{top}" stroke="{INK}" stroke-width="{LINE}" stroke-linejoin="round"/>']
    # Side shading towards the back of the figure.
    shade_x = (sx + w - 3) if pose.view == "front" else (sx - w + 3)
    parts.append(f'<path d="M{shade_x:.1f} {sy:.1f} L{hx + (wh - 2) * (1 if pose.view == "front" else -1):.1f} {hy:.1f}" '
                 f'stroke="{shade(top, -0.18)}" stroke-width="3.2" stroke-linecap="round" opacity="0.8"/>')
    style = look.top_style
    front = pose.view == "front"
    cx = sx + (1.2 if front else -1.2)
    if front:
        if style in ("suit", "blazer"):
            parts.append(f'<path d="M{cx - 4:.1f} {sy - 1.5:.1f} L{cx + 1:.1f} {sy + 9:.1f} L{cx + 5:.1f} {sy - 1.5:.1f} Z" fill="{look.accent}" stroke="{INK}" stroke-width="1.1"/>')
            parts.append(f'<path d="M{cx - 5:.1f} {sy - 1:.1f} L{cx:.1f} {sy + 12:.1f} M{cx + 6:.1f} {sy - 1:.1f} L{cx + 2:.1f} {sy + 12:.1f}" stroke="{shade(top, -0.35)}" stroke-width="1.3"/>')
        elif style == "vest":
            parts.append(f'<path d="M{cx - 3.5:.1f} {sy - 1.5:.1f} L{cx + 0.5:.1f} {sy + 14:.1f} L{cx + 4.5:.1f} {sy - 1.5:.1f} Z" fill="{look.accent}" stroke="{INK}" stroke-width="1.1"/>')
            parts.append(f'<path d="M{sx - w + 1:.1f} {sy + 2:.1f} L{sx - w + 1:.1f} {sy + 8:.1f}" stroke="{look.accent}" stroke-width="2"/>')
            parts.append(f'<g fill="#e7b44c"><circle cx="{cx - 2:.1f}" cy="{sy + 7:.1f}" r="0.9"/><circle cx="{cx - 1.5:.1f}" cy="{sy + 11:.1f}" r="0.9"/></g>')
        elif style == "shirt":
            parts.append(f'<path d="M{cx - 4:.1f} {sy - 1.5:.1f} L{cx + 0.5:.1f} {sy + 3.5:.1f} L{cx + 5:.1f} {sy - 1.5:.1f}" fill="none" stroke="{shade(top, -0.3)}" stroke-width="1.2"/>')
            parts.append(f'<path d="M{cx + 0.5:.1f} {sy + 4:.1f} L{cx + 0.5:.1f} {hy - 1:.1f}" stroke="{shade(top, -0.25)}" stroke-width="0.9"/>')
        elif style == "cardigan":
            parts.append(f'<path d="M{cx - 3:.1f} {sy - 1.5:.1f} L{cx + 0.5:.1f} {sy + 6:.1f} L{cx + 4:.1f} {sy - 1.5:.1f} Z" fill="{look.accent}" stroke="{INK}" stroke-width="1"/>')
            parts.append(f'<path d="M{cx + 0.5:.1f} {sy + 6:.1f} L{cx + 0.5:.1f} {hy:.1f}" stroke="{shade(top, -0.35)}" stroke-width="1.2"/>')
            parts.append(f'<g fill="{shade(top, 0.45)}"><circle cx="{cx + 1.8:.1f}" cy="{sy + 9:.1f}" r="0.9"/><circle cx="{cx + 1.8:.1f}" cy="{sy + 13:.1f}" r="0.9"/></g>')
        elif style == "hoodie":
            parts.append(f'<path d="M{cx - 6:.1f} {sy - 1:.1f} Q{cx + 0.5:.1f} {sy + 6:.1f} {cx + 7:.1f} {sy - 1:.1f}" fill="none" stroke="{shade(top, -0.35)}" stroke-width="1.5"/>')
            parts.append(f'<path d="M{cx - 1.5:.1f} {sy + 3:.1f} L{cx - 2:.1f} {sy + 9:.1f} M{cx + 3:.1f} {sy + 3:.1f} L{cx + 3.5:.1f} {sy + 9:.1f}" stroke="#f4f1ea" stroke-width="1"/>')
            parts.append(f'<path d="M{cx - 5:.1f} {hy - 6:.1f} L{cx + 6:.1f} {hy - 6:.1f}" stroke="{shade(top, -0.25)}" stroke-width="1.2"/>')
        elif style == "jacket":
            parts.append(f'<path d="M{cx + 0.5:.1f} {sy:.1f} L{cx + 0.5:.1f} {hy:.1f}" stroke="{shade(top, -0.4)}" stroke-width="1.3"/>')
            parts.append(f'<path d="M{cx - 4:.1f} {sy - 1:.1f} L{cx - 1:.1f} {sy + 4:.1f} M{cx + 5:.1f} {sy - 1:.1f} L{cx + 2:.1f} {sy + 4:.1f}" stroke="{shade(top, -0.4)}" stroke-width="1.3"/>')
        elif style == "dress":
            parts.append(f'<path d="M{cx - 5:.1f} {sy - 1:.1f} Q{cx + 0.5:.1f} {sy + 5:.1f} {cx + 6:.1f} {sy - 1:.1f}" fill="{look.skin}" stroke="{INK}" stroke-width="1"/>')
            parts.append(f'<path d="M{sx - w + 2:.1f} {pose.hip[1] - 4:.1f} L{sx + w - 2:.1f} {pose.hip[1] - 4:.1f}" stroke="{look.accent}" stroke-width="1.6"/>')
        elif style == "tshirt":
            parts.append(f'<path d="M{cx - 4:.1f} {sy - 1.5:.1f} Q{cx + 0.5:.1f} {sy + 3:.1f} {cx + 5:.1f} {sy - 1.5:.1f}" fill="none" stroke="{shade(top, -0.3)}" stroke-width="1.2"/>')
        elif style == "sweater":
            parts.append(f'<path d="M{cx - 5:.1f} {sy - 1:.1f} Q{cx + 0.5:.1f} {sy + 3:.1f} {cx + 6:.1f} {sy - 1:.1f}" fill="none" stroke="{shade(top, -0.3)}" stroke-width="2"/>')
            parts.append(f'<path d="M{sx - w + 1:.1f} {hy - 2:.1f} L{sx + w - 1:.1f} {hy - 2:.1f}" stroke="{shade(top, -0.2)}" stroke-width="2"/>')
        if "tie" in look.extras:
            parts.append(f'<path d="M{cx - 0.5:.1f} {sy - 0.5:.1f} L{cx + 1.7:.1f} {sy - 0.5:.1f} L{cx + 2.2:.1f} {sy + 2:.1f} L{cx + 1.3:.1f} {sy + 10:.1f} L{cx + 0.6:.1f} {sy + 11:.1f} L{cx - 0.2:.1f} {sy + 10:.1f} L{cx - 1:.1f} {sy + 2:.1f} Z" fill="{look.tie}" stroke="{INK}" stroke-width="0.8"/>')
        if "bowtie" in look.extras:
            parts.append(f'<path d="M{cx - 3:.1f} {sy - 0.5:.1f} L{cx + 0.6:.1f} {sy + 1:.1f} L{cx - 3:.1f} {sy + 2.5:.1f} Z M{cx + 4:.1f} {sy - 0.5:.1f} L{cx + 0.6:.1f} {sy + 1:.1f} L{cx + 4:.1f} {sy + 2.5:.1f} Z" fill="{look.tie}" stroke="{INK}" stroke-width="0.8"/>')
        if "chain" in look.extras:
            parts.append(f'<path d="M{cx - 4:.1f} {sy:.1f} Q{cx + 0.5:.1f} {sy + 8:.1f} {cx + 5:.1f} {sy:.1f}" stroke="#f0c040" stroke-width="1.4" fill="none" stroke-dasharray="1.6 0.8"/>')
        if "flower" in look.extras:
            parts.append(f'<circle cx="{cx - 5:.1f}" cy="{sy + 4:.1f}" r="2.3" fill="#e8f4ea" stroke="{INK}" stroke-width="0.8"/><circle cx="{cx - 5:.1f}" cy="{sy + 4:.1f}" r="1" fill="#e9c94a"/>')
    else:
        if style == "hoodie":
            parts.append(f'<path d="M{sx - 7:.1f} {sy:.1f} Q{sx:.1f} {sy + 11:.1f} {sx + 7:.1f} {sy:.1f}" fill="{shade(top, -0.1)}" stroke="{INK}" stroke-width="1.2"/>')
        if style in ("suit", "blazer", "jacket"):
            parts.append(f'<path d="M{sx:.1f} {sy + 2:.1f} L{hx:.1f} {hy:.1f}" stroke="{shade(top, -0.3)}" stroke-width="1"/>')
        if style == "vest":
            parts.append(f'<path d="M{sx - w:.1f} {sy + 2:.1f} L{sx - w + 3:.1f} {sy - 1:.1f} M{sx + w:.1f} {sy + 2:.1f} L{sx + w - 3:.1f} {sy - 1:.1f}" stroke="{look.accent}" stroke-width="2.4"/>')
        if "backpack" in look.extras:
            parts.append(f'<rect x="{sx - 6:.1f}" y="{sy + 2:.1f}" width="12" height="13" rx="3" fill="#e0a43a" stroke="{INK}" stroke-width="{LINE}"/>'
                         f'<path d="M{sx - 4:.1f} {sy + 9:.1f} L{sx + 4:.1f} {sy + 9:.1f}" stroke="{INK}" stroke-width="1"/>')
    if front and "backpack" in look.extras:
        parts.append(f'<path d="M{sx - w + 2:.1f} {sy:.1f} L{sx - w + 3:.1f} {sy + 14:.1f}" stroke="#e0a43a" stroke-width="2"/>')
    return "".join(parts)


def head(look: Look, pose: Pose) -> str:
    cx, cy = pose.head
    front = pose.view == "front"
    r = 12.5
    parts = []
    # Hair behind the head.
    hs, hair = look.hair_style, look.hair
    if hs == "long":
        parts.append(f'<path d="M{cx - 13:.1f} {cy - 2:.1f} Q{cx - 15:.1f} {cy + 14:.1f} {cx - 11:.1f} {cy + 19:.1f} L{cx + 11:.1f} {cy + 19:.1f} Q{cx + 15:.1f} {cy + 14:.1f} {cx + 13:.1f} {cy - 2:.1f} Z" fill="{shade(hair, -0.1)}" stroke="{INK}" stroke-width="{LINE}"/>')
    if hs == "ponytail":
        tail_x = cx - 13 if front else cx + 13
        parts.append(f'<path d="M{tail_x:.1f} {cy - 4:.1f} q{-6 if front else 6} 6 {-2 if front else 2} 16 q{5 if front else -5} -6 {3 if front else -3} -15 Z" fill="{hair}" stroke="{INK}" stroke-width="{LINE}"/>')
    if hs == "bun":
        parts.append(f'<circle cx="{cx - (3 if front else -3):.1f}" cy="{cy - 13:.1f}" r="5" fill="{hair}" stroke="{INK}" stroke-width="{LINE}"/>')
    if look.hat == "veil":
        parts.append(f'<path d="M{cx - 9:.1f} {cy - 10:.1f} Q{cx - 20:.1f} {cy + 10:.1f} {cx - 16:.1f} {cy + 30:.1f} L{cx + 16:.1f} {cy + 30:.1f} Q{cx + 20:.1f} {cy + 10:.1f} {cx + 9:.1f} {cy - 10:.1f} Z" fill="#ffffff" fill-opacity="0.85" stroke="{INK}" stroke-width="1.2"/>')
    if look.hat == "scarf":
        parts.append(f'<path d="M{cx - 14:.1f} {cy + 2:.1f} Q{cx - 16:.1f} {cy - 16:.1f} {cx:.1f} {cy - 16:.1f} Q{cx + 16:.1f} {cy - 16:.1f} {cx + 14:.1f} {cy + 2:.1f} L{cx + 12:.1f} {cy + 14:.1f} Q{cx:.1f} {cy + 19:.1f} {cx - 12:.1f} {cy + 14:.1f} Z" fill="{look.hat_color}" stroke="{INK}" stroke-width="{LINE}"/>')
    # Neck.
    parts.append(f'<rect x="{cx - 3.2 - (1 if not front else -1):.1f}" y="{cy + 8:.1f}" width="6.4" height="7" fill="{shade(look.skin, -0.12)}" stroke="{INK}" stroke-width="1.1"/>')
    # Ear on the side away from the face.
    ear_x = cx - 11.5 if front else cx + 11.5
    if not front:
        ear_x = cx + 11.5
    parts.append(f'<ellipse cx="{ear_x:.1f}" cy="{cy + 1:.1f}" rx="2.8" ry="3.6" fill="{look.skin}" stroke="{INK}" stroke-width="{LINE}"/>')
    if not front:
        parts.append(f'<ellipse cx="{cx - 11.5:.1f}" cy="{cy + 1:.1f}" rx="2.6" ry="3.4" fill="{shade(look.skin, -0.05)}" stroke="{INK}" stroke-width="{LINE}"/>')
    # Skull.
    skull = look.skin if front or hs in ("bald", "fringe", "none") else hair
    if look.hat == "scarf" and not front:
        skull = look.hat_color
    parts.append(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{r:.1f}" ry="{r + 0.8:.1f}" fill="{skull}" stroke="{INK}" stroke-width="{LINE}"/>')
    if front:
        parts.append(face(look, pose))
    parts.append(hair_front(look, pose))
    parts.append(hat(look, pose))
    if front and "earrings" in look.extras:
        parts.append(f'<circle cx="{cx - 11:.1f}" cy="{cy + 6:.1f}" r="1.3" fill="#f0c040" stroke="{INK}" stroke-width="0.6"/>')
    return "".join(parts)


def face(look: Look, pose: Pose) -> str:
    cx, cy = pose.head
    ex1, ex2, ey = cx - 1.5, cx + 6.5, cy + 0.5
    parts = [f'<ellipse cx="{cx - 4:.1f}" cy="{cy + 6:.1f}" rx="2.6" ry="1.5" fill="#f08a7a" opacity="0.45"/>',
             f'<ellipse cx="{cx + 9:.1f}" cy="{cy + 6:.1f}" rx="2" ry="1.4" fill="#f08a7a" opacity="0.45"/>']
    if pose.eyes == "happy":
        parts.append(f'<path d="M{ex1 - 2:.1f} {ey + 0.8:.1f} Q{ex1:.1f} {ey - 2.2:.1f} {ex1 + 2:.1f} {ey + 0.8:.1f} M{ex2 - 1.8:.1f} {ey + 0.8:.1f} Q{ex2:.1f} {ey - 2.2:.1f} {ex2 + 1.8:.1f} {ey + 0.8:.1f}" stroke="{INK}" stroke-width="1.4" fill="none" stroke-linecap="round"/>')
    elif pose.eyes == "closed":
        parts.append(f'<path d="M{ex1 - 2:.1f} {ey:.1f} L{ex1 + 2:.1f} {ey:.1f} M{ex2 - 1.8:.1f} {ey:.1f} L{ex2 + 1.8:.1f} {ey:.1f}" stroke="{INK}" stroke-width="1.4" stroke-linecap="round"/>')
    else:
        parts.append(f'<g fill="{INK}"><ellipse cx="{ex1:.1f}" cy="{ey:.1f}" rx="1.6" ry="2.2"/><ellipse cx="{ex2:.1f}" cy="{ey:.1f}" rx="1.45" ry="2.1"/></g>'
                     f'<g fill="#fff"><circle cx="{ex1 + 0.5:.1f}" cy="{ey - 0.8:.1f}" r="0.55"/><circle cx="{ex2 + 0.5:.1f}" cy="{ey - 0.8:.1f}" r="0.5"/></g>')
    brow = shade(look.hair, -0.2) if look.hair_style not in ("bald",) else "#6a5a50"
    parts.append(f'<path d="M{ex1 - 2.2:.1f} {ey - 4:.1f} L{ex1 + 1.8:.1f} {ey - 4.6:.1f} M{ex2 - 1.6:.1f} {ey - 4.6:.1f} L{ex2 + 2:.1f} {ey - 4.2:.1f}" stroke="{brow}" stroke-width="1.2" stroke-linecap="round"/>')
    parts.append(f'<path d="M{cx + 9:.1f} {cy + 2:.1f} q1.6 2.2 -0.6 3" stroke="{shade(look.skin, -0.35)}" stroke-width="1" fill="none" stroke-linecap="round"/>')
    mx, my = cx + 3.5, cy + 7.8
    mouth = pose.mouth
    if mouth == "open":
        parts.append(f'<path d="M{mx - 2.6:.1f} {my - 0.6:.1f} Q{mx:.1f} {my + 4:.1f} {mx + 2.6:.1f} {my - 0.6:.1f} Z" fill="#8b2e2a" stroke="{INK}" stroke-width="1"/>')
    elif mouth == "grin":
        parts.append(f'<path d="M{mx - 3:.1f} {my - 0.8:.1f} Q{mx:.1f} {my + 3.2:.1f} {mx + 3:.1f} {my - 0.8:.1f} Z" fill="#fff" stroke="{INK}" stroke-width="1"/>')
    elif mouth == "sad":
        parts.append(f'<path d="M{mx - 2.2:.1f} {my + 1.2:.1f} Q{mx:.1f} {my - 1.2:.1f} {mx + 2.2:.1f} {my + 1.2:.1f}" stroke="{INK}" stroke-width="1.2" fill="none" stroke-linecap="round"/>')
    else:
        parts.append(f'<path d="M{mx - 2.4:.1f} {my - 0.6:.1f} Q{mx:.1f} {my + 2:.1f} {mx + 2.4:.1f} {my - 0.6:.1f}" stroke="{INK}" stroke-width="1.2" fill="none" stroke-linecap="round"/>')
    if "mustache" in look.extras:
        color = look.hair if look.hair_style not in ("bald",) else "#3a2a22"
        parts.append(f'<path d="M{mx - 4.2:.1f} {my - 1.4:.1f} Q{mx - 2:.1f} {my - 4:.1f} {mx:.1f} {my - 2.4:.1f} Q{mx + 2:.1f} {my - 4:.1f} {mx + 4.2:.1f} {my - 1.4:.1f} Q{mx:.1f} {my - 0.6:.1f} {mx - 4.2:.1f} {my - 1.4:.1f} Z" fill="{color}" stroke="{INK}" stroke-width="0.8"/>')
    if "beard" in look.extras:
        parts.append(f'<path d="M{cx - 9:.1f} {cy + 3:.1f} Q{cx - 8:.1f} {cy + 15:.1f} {cx + 3:.1f} {cy + 14:.1f} Q{cx + 11:.1f} {cy + 13:.1f} {cx + 11.5:.1f} {cy + 4:.1f} Q{cx + 8:.1f} {cy + 10:.1f} {mx:.1f} {my + 2.5:.1f} Q{cx - 3:.1f} {cy + 10:.1f} {cx - 9:.1f} {cy + 3:.1f} Z" fill="{look.hair}" stroke="{INK}" stroke-width="1"/>')
    if "glasses" in look.extras:
        parts.append(f'<g fill="#ffffff" fill-opacity="0.25" stroke="{INK}" stroke-width="1.1"><circle cx="{ex1:.1f}" cy="{ey:.1f}" r="3.2"/><circle cx="{ex2:.1f}" cy="{ey:.1f}" r="3"/></g>'
                     f'<path d="M{ex1 + 3.2:.1f} {ey:.1f} L{ex2 - 3:.1f} {ey:.1f} M{ex1 - 3.2:.1f} {ey:.1f} L{cx - 11:.1f} {ey - 1:.1f}" stroke="{INK}" stroke-width="1"/>')
    if "shades" in look.extras:
        parts.append(f'<path d="M{ex1 - 3.6:.1f} {ey - 2.6:.1f} L{ex1 + 3:.1f} {ey - 2.6:.1f} L{ex1 + 2.4:.1f} {ey + 2:.1f} Q{ex1:.1f} {ey + 3:.1f} {ex1 - 3:.1f} {ey + 1.6:.1f} Z M{ex2 - 2.8:.1f} {ey - 2.6:.1f} L{ex2 + 3:.1f} {ey - 2.6:.1f} L{ex2 + 2.4:.1f} {ey + 1.8:.1f} Q{ex2:.1f} {ey + 3:.1f} {ex2 - 2.4:.1f} {ey + 1.6:.1f} Z" fill="#17171c" stroke="{INK}" stroke-width="0.8"/>'
                     f'<path d="M{ex1 + 3:.1f} {ey - 2:.1f} L{ex2 - 2.8:.1f} {ey - 2:.1f} M{ex1 - 3.6:.1f} {ey - 2.2:.1f} L{cx - 11:.1f} {ey - 2:.1f}" stroke="#17171c" stroke-width="1.2"/>'
                     f'<path d="M{ex1 - 2:.1f} {ey - 1.6:.1f} L{ex1:.1f} {ey - 1.6:.1f}" stroke="#fff" stroke-width="0.8" opacity="0.7"/>')
    return "".join(parts)


def hair_front(look: Look, pose: Pose) -> str:
    cx, cy = pose.head
    hs, hair = look.hair_style, look.hair
    front = pose.view == "front"
    edge = f'stroke="{INK}" stroke-width="{LINE}" stroke-linejoin="round"'
    if look.hat in ("scarf",):
        if front:
            return (f'<path d="M{cx - 13:.1f} {cy + 1:.1f} Q{cx - 14:.1f} {cy - 15:.1f} {cx:.1f} {cy - 15:.1f} Q{cx + 14:.1f} {cy - 15:.1f} {cx + 13:.1f} {cy + 1:.1f} Q{cx + 9:.1f} {cy - 9:.1f} {cx:.1f} {cy - 9:.1f} Q{cx - 9:.1f} {cy - 9:.1f} {cx - 13:.1f} {cy + 1:.1f} Z" fill="{look.hat_color}" {edge}/>')
        return ""
    if hs in ("none", "bald"):
        return f'<ellipse cx="{cx - 3:.1f}" cy="{cy - 8:.1f}" rx="4" ry="2" fill="#fff" opacity="0.35"/>' if hs == "bald" else ""
    if not front:
        # Back view: hair covers the skull; add strands and the hairline at the neck.
        out = ""
        if hs == "fringe":
            out = f'<path d="M{cx - 12.3:.1f} {cy - 2:.1f} Q{cx:.1f} {cy + 3:.1f} {cx + 12.3:.1f} {cy - 2:.1f} L{cx + 12:.1f} {cy + 3:.1f} Q{cx:.1f} {cy + 8:.1f} {cx - 12:.1f} {cy + 3:.1f} Z" fill="{hair}" {edge}/>'
        elif hs == "messy":
            out = f'<path d="M{cx - 9:.1f} {cy - 10:.1f} l3 -5 l2 4 l3 -6 l2 5 l3 -5 l2 5" stroke="{INK}" stroke-width="1.2" fill="{hair}"/>'
        elif hs == "curly":
            out = "".join(f'<circle cx="{cx + dx:.1f}" cy="{cy + dy:.1f}" r="4.2" fill="{hair}" {edge}/>' for dx, dy in [(-8, -8), (0, -11), (8, -8), (-10, 0), (10, 0)])
        elif hs == "slick":
            out = f'<path d="M{cx - 7:.1f} {cy - 9:.1f} Q{cx:.1f} {cy - 12:.1f} {cx + 7:.1f} {cy - 9:.1f}" stroke="{shade(hair, 0.4)}" stroke-width="1.2" fill="none"/>'
        elif hs == "bob":
            out = f'<path d="M{cx - 13:.1f} {cy:.1f} L{cx - 13:.1f} {cy + 10:.1f} Q{cx:.1f} {cy + 13:.1f} {cx + 13:.1f} {cy + 10:.1f} L{cx + 13:.1f} {cy:.1f}" fill="{hair}" {edge}/>'
        return out
    if hs == "short":
        return f'<path d="M{cx - 12.5:.1f} {cy + 1:.1f} Q{cx - 14:.1f} {cy - 14.5:.1f} {cx + 1:.1f} {cy - 14:.1f} Q{cx + 13.5:.1f} {cy - 13:.1f} {cx + 12.5:.1f} {cy - 2:.1f} Q{cx + 9:.1f} {cy - 8:.1f} {cx + 2:.1f} {cy - 8.5:.1f} Q{cx - 5:.1f} {cy - 7:.1f} {cx - 8:.1f} {cy - 4:.1f} L{cx - 9:.1f} {cy + 3:.1f} Z" fill="{hair}" {edge}/>'
    if hs == "messy":
        return (f'<path d="M{cx - 13:.1f} {cy + 2:.1f} Q{cx - 16:.1f} {cy - 12:.1f} {cx - 6:.1f} {cy - 15:.1f} L{cx - 4:.1f} {cy - 19:.1f} L{cx:.1f} {cy - 15:.1f} L{cx + 4:.1f} {cy - 19:.1f} L{cx + 6:.1f} {cy - 14:.1f} '
                f'L{cx + 12:.1f} {cy - 16:.1f} L{cx + 11:.1f} {cy - 10:.1f} Q{cx + 15:.1f} {cy - 6:.1f} {cx + 12.5:.1f} {cy - 1:.1f} L{cx + 8:.1f} {cy - 7:.1f} L{cx + 4:.1f} {cy - 4:.1f} L{cx:.1f} {cy - 8:.1f} L{cx - 5:.1f} {cy - 5:.1f} L{cx - 8:.1f} {cy - 3:.1f} L{cx - 9:.1f} {cy + 3:.1f} Z" fill="{hair}" {edge}/>')
    if hs == "slick":
        return (f'<path d="M{cx - 12.5:.1f} {cy + 1:.1f} Q{cx - 13:.1f} {cy - 15:.1f} {cx + 1:.1f} {cy - 14.5:.1f} Q{cx + 13:.1f} {cy - 13.5:.1f} {cx + 12.5:.1f} {cy - 3:.1f} Q{cx + 4:.1f} {cy - 12:.1f} {cx - 8:.1f} {cy - 5:.1f} L{cx - 9:.1f} {cy + 3:.1f} Z" fill="{hair}" {edge}/>'
                f'<path d="M{cx - 6:.1f} {cy - 11:.1f} Q{cx + 2:.1f} {cy - 14:.1f} {cx + 9:.1f} {cy - 10:.1f}" stroke="{shade(hair, 0.45)}" stroke-width="1.2" fill="none"/>')
    if hs == "fringe":
        return (f'<path d="M{cx - 12.8:.1f} {cy + 4:.1f} Q{cx - 13:.1f} {cy - 6:.1f} {cx - 8:.1f} {cy - 9:.1f} L{cx - 8:.1f} {cy + 4:.1f} Z" fill="{hair}" {edge}/>'
                f'<ellipse cx="{cx - 1:.1f}" cy="{cy - 8:.1f}" rx="4" ry="2" fill="#fff" opacity="0.3"/>')
    if hs == "curly":
        return "".join(f'<circle cx="{cx + dx:.1f}" cy="{cy + dy:.1f}" r="{rr}" fill="{hair}" {edge}/>'
                       for dx, dy, rr in [(-11, -2, 4.4), (-9, -9, 4.6), (-2, -13, 4.8), (6, -12, 4.6), (11, -6, 4.2), (-12, 5, 3.6)])
    if hs in ("long", "ponytail", "bun", "bob"):
        out = f'<path d="M{cx - 13:.1f} {cy + 4:.1f} Q{cx - 14:.1f} {cy - 15:.1f} {cx + 1:.1f} {cy - 14.5:.1f} Q{cx + 14:.1f} {cy - 13:.1f} {cx + 13:.1f} {cy + 1:.1f} Q{cx + 10:.1f} {cy - 9:.1f} {cx + 3:.1f} {cy - 7:.1f} Q{cx - 3:.1f} {cy - 4:.1f} {cx - 9:.1f} {cy - 5:.1f} L{cx - 9.5:.1f} {cy + 6:.1f} Z" fill="{hair}" {edge}/>'
        if hs == "bob":
            out += f'<path d="M{cx - 13:.1f} {cy:.1f} L{cx - 13.5:.1f} {cy + 10:.1f} L{cx - 7:.1f} {cy + 10:.1f} L{cx - 8:.1f} {cy:.1f} Z" fill="{hair}" {edge}/>'
        return out
    return ""


def hat(look: Look, pose: Pose) -> str:
    cx, cy = pose.head
    front = pose.view == "front"
    c = look.hat_color
    edge = f'stroke="{INK}" stroke-width="{LINE}" stroke-linejoin="round"'
    if look.hat == "cap":
        brim = f'<path d="M{cx - 2:.1f} {cy - 9:.1f} Q{cx + 12:.1f} {cy - 10:.1f} {cx + 17:.1f} {cy - 6:.1f} Q{cx + 10:.1f} {cy - 4:.1f} {cx - 2:.1f} {cy - 6:.1f} Z" fill="{shade(c, -0.15)}" {edge}/>' if front else ""
        return f'<path d="M{cx - 13:.1f} {cy - 4:.1f} Q{cx - 13:.1f} {cy - 17:.1f} {cx:.1f} {cy - 17:.1f} Q{cx + 13:.1f} {cy - 17:.1f} {cx + 13:.1f} {cy - 5:.1f} Q{cx:.1f} {cy - 9:.1f} {cx - 13:.1f} {cy - 4:.1f} Z" fill="{c}" {edge}/>' + brim
    if look.hat == "sajkaca":
        return (f'<path d="M{cx - 13:.1f} {cy - 6:.1f} L{cx - 11:.1f} {cy - 16:.1f} Q{cx:.1f} {cy - 22:.1f} {cx + 11:.1f} {cy - 16:.1f} L{cx + 13:.1f} {cy - 6:.1f} Q{cx:.1f} {cy - 10:.1f} {cx - 13:.1f} {cy - 6:.1f} Z" fill="{c}" {edge}/>'
                f'<path d="M{cx - 9:.1f} {cy - 17:.1f} Q{cx:.1f} {cy - 13:.1f} {cx + 9:.1f} {cy - 17:.1f}" stroke="{shade(c, -0.35)}" stroke-width="1.2" fill="none"/>')
    if look.hat == "beanie":
        return (f'<path d="M{cx - 13:.1f} {cy - 3:.1f} Q{cx - 14:.1f} {cy - 19:.1f} {cx:.1f} {cy - 19:.1f} Q{cx + 14:.1f} {cy - 19:.1f} {cx + 13:.1f} {cy - 3:.1f} Z" fill="{c}" {edge}/>'
                f'<rect x="{cx - 13.5:.1f}" y="{cy - 7:.1f}" width="27" height="5" rx="2" fill="{shade(c, -0.15)}" {edge}/>')
    if look.hat == "fedora":
        return (f'<ellipse cx="{cx + 1:.1f}" cy="{cy - 8:.1f}" rx="18" ry="4" fill="{shade(c, -0.1)}" {edge}/>'
                f'<path d="M{cx - 10:.1f} {cy - 8:.1f} L{cx - 9:.1f} {cy - 19:.1f} Q{cx:.1f} {cy - 15:.1f} {cx + 10:.1f} {cy - 19:.1f} L{cx + 11:.1f} {cy - 8:.1f} Z" fill="{c}" {edge}/>'
                f'<path d="M{cx - 10:.1f} {cy - 11:.1f} L{cx + 11:.1f} {cy - 11:.1f}" stroke="#b8302f" stroke-width="2"/>')
    if look.hat == "wreath":
        return "".join(f'<circle cx="{cx + dx:.1f}" cy="{cy + dy:.1f}" r="2.6" fill="{col}" stroke="{INK}" stroke-width="0.8"/>'
                       for dx, dy, col in [(-11, -6, "#f4f1ea"), (-7, -12, "#d63a3a"), (0, -14, "#f4f1ea"), (7, -12, "#d63a3a"), (11, -6, "#f4f1ea")])
    if look.hat == "veil":
        return f'<path d="M{cx - 9:.1f} {cy - 12:.1f} Q{cx:.1f} {cy - 17:.1f} {cx + 9:.1f} {cy - 12:.1f}" stroke="#f0c040" stroke-width="2.2" fill="none"/>'
    return ""


def held(look: Look, pose: Pose) -> str:
    hx, hy = pose.near_hand
    if pose.prop == "glass":
        return (f'<path d="M{hx - 2.6:.1f} {hy - 7:.1f} L{hx + 2.6:.1f} {hy - 7:.1f} L{hx + 2:.1f} {hy + 1:.1f} L{hx - 2:.1f} {hy + 1:.1f} Z" fill="#f2c45a" stroke="{INK}" stroke-width="1"/>'
                f'<path d="M{hx - 2.6:.1f} {hy - 7:.1f} L{hx + 2.6:.1f} {hy - 7:.1f} L{hx + 2.4:.1f} {hy - 4.5:.1f} L{hx - 2.4:.1f} {hy - 4.5:.1f} Z" fill="#fbf3dc"/>')
    if pose.prop == "tray":
        return (f'<ellipse cx="{hx:.1f}" cy="{hy - 2:.1f}" rx="9" ry="3" fill="#c9ced3" stroke="{INK}" stroke-width="{LINE}"/>'
                f'<path d="M{hx - 4:.1f} {hy - 10:.1f} L{hx - 0.5:.1f} {hy - 10:.1f} L{hx - 1:.1f} {hy - 3:.1f} L{hx - 3.5:.1f} {hy - 3:.1f} Z" fill="#f2c45a" stroke="{INK}" stroke-width="0.9"/>'
                f'<path d="M{hx + 1.5:.1f} {hy - 8:.1f} L{hx + 5.5:.1f} {hy - 8:.1f} L{hx + 5:.1f} {hy - 3:.1f} L{hx + 2:.1f} {hy - 3:.1f} Z" fill="#b8302f" stroke="{INK}" stroke-width="0.9"/>')
    return ""


def figure(look: Look, pose: Pose) -> str:
    """One character in one pose, back to front."""
    parts = []
    if pose.view == "front":
        if not pose.sitting:
            parts.append(leg(look, pose, near=False))
        parts.append(arm(look, pose, near=False))
        if pose.sitting:
            parts.append(leg(look, pose, near=False))
            parts.append(leg(look, pose, near=True))
        else:
            parts.append(leg(look, pose, near=True))
        parts.append(torso(look, pose))
        parts.append(head(look, pose))
        parts.append(arm(look, pose, near=True))
        parts.append(held(look, pose))
    else:
        parts.append(arm(look, pose, near=False))
        if not pose.sitting:
            parts.append(leg(look, pose, near=False))
            parts.append(leg(look, pose, near=True))
        parts.append(arm(look, pose, near=True))
        if pose.prop:
            parts.append(held(look, pose))
        parts.append(torso(look, pose))
        parts.append(head(look, pose))
    return "".join(parts)


# --------------------------------------------------------------------------------------------
# Animation sets
# --------------------------------------------------------------------------------------------

GUEST_FRAMES = ["walk_f0", "walk_f1", "walk_f2", "walk_f3", "walk_b0", "walk_b1", "walk_b2", "walk_b3",
                "idle_f", "idle_b", "sit_f", "sit_f_drink", "sit_b", "sit_b_drink", "dance0", "dance1", "dance2", "dance3",
                "sit_f_angry", "sit_f_happy"]
GUEST_ANIMS = {"walk_front": [0, 1, 2, 3], "walk_back": [4, 5, 6, 7], "idle_front": [8], "idle_back": [9],
               "sit_front": [10], "drink_front": [11], "sit_back": [12], "drink_back": [13], "dance": [14, 15, 16, 17],
               "angry_front": [18], "happy_front": [19]}


def guest_poses(look: Look) -> list:
    poses = [_walk_pose("front", i, look) for i in range(4)] + [_walk_pose("back", i, look) for i in range(4)]
    poses += [_idle_pose("front", look), _idle_pose("back", look)]
    poses += [_sit_pose("front", look), _sit_pose("front", look, True), _sit_pose("back", look), _sit_pose("back", look, True)]
    poses += [_dance_pose(i, look) for i in range(4)]
    angry = _sit_pose("front", look)
    angry.mouth, angry.eyes = "sad", "open"
    happy = _sit_pose("front", look)
    happy.mouth, happy.eyes = "grin", "happy"
    poses += [angry, happy]
    return poses


WAITER_FRAMES = ["tray_f0", "tray_f1", "tray_f2", "tray_f3", "tray_b0", "tray_b1", "tray_b2", "tray_b3",
                 "walk_f0", "walk_f1", "walk_f2", "walk_f3", "walk_b0", "walk_b1", "walk_b2", "walk_b3", "idle_f", "idle_f_tray"]
WAITER_ANIMS = {"carry_front": [0, 1, 2, 3], "carry_back": [4, 5, 6, 7], "walk_front": [8, 9, 10, 11], "walk_back": [12, 13, 14, 15],
                "idle_front": [16], "carry_idle": [17]}


def waiter_poses(look: Look) -> list:
    poses = [_walk_pose("front", i, look, "tray") for i in range(4)] + [_walk_pose("back", i, look, "tray") for i in range(4)]
    poses += [_walk_pose("front", i, look) for i in range(4)] + [_walk_pose("back", i, look) for i in range(4)]
    idle_tray = _idle_pose("front", look)
    idle_tray.near_hand = (idle_tray.shoulder[0] - 2, idle_tray.shoulder[1] - 3)
    idle_tray.prop = "tray"
    poses += [_idle_pose("front", look), idle_tray]
    return poses


def staff_poses(look: Look, kind: str) -> list:
    if kind == "bartender":
        a = _idle_pose("front", look)
        b = _idle_pose("front", look)
        b.near_hand = (b.shoulder[0] + 4, b.shoulder[1] + 9)
        b.far_hand = (b.shoulder[0] + 9, b.shoulder[1] + 11)
        b.prop = "glass"
        c = _idle_pose("front", look, -0.8)
        c.near_hand = (c.shoulder[0] + 1, c.shoulder[1] + 10)
        c.far_hand = (c.shoulder[0] + 10, c.shoulder[1] + 10)
        c.prop = "glass"
        c.eyes = "happy"
        return [a, b, c]
    # Bouncer: arms folded.
    a = _idle_pose("front", look)
    a.near_hand = (a.shoulder[0] + 6, a.shoulder[1] + 10)
    a.far_hand = (a.shoulder[0] - 2, a.shoulder[1] + 9)
    a.mouth = "flat"
    b = _idle_pose("front", look, -0.7)
    b.near_hand, b.far_hand, b.mouth = a.near_hand, a.far_hand, "flat"
    return [a, b]


# --------------------------------------------------------------------------------------------
# Musicians
# --------------------------------------------------------------------------------------------

def instrument(kind: str, pose: Pose, frame: int) -> tuple:
    """(behind, in_front) SVG fragments for an instrument held in front of the body."""
    sx, sy = pose.shoulder
    if kind == "accordion":
        spread = [3.0, 6.5, 10.0][frame % 3]
        x0 = sx - 9 - spread / 2
        x1 = sx + 4 + spread / 2
        bellows = "".join(f'<path d="M{x0 + 6 + i * (x1 - x0 - 6) / 5:.1f} {sy + 3:.1f} L{x0 + 6 + i * (x1 - x0 - 6) / 5:.1f} {sy + 19:.1f}" stroke="{INK}" stroke-width="0.9"/>' for i in range(1, 5))
        front = (f'<rect x="{x0 + 5:.1f}" y="{sy + 3:.1f}" width="{x1 - x0 - 5:.1f}" height="16" fill="#2b2b33" stroke="{INK}" stroke-width="{LINE}"/>{bellows}'
                 f'<rect x="{x0 - 1:.1f}" y="{sy + 1:.1f}" width="8" height="20" rx="1.5" fill="#c0392b" stroke="{INK}" stroke-width="{LINE}"/>'
                 f'<g fill="#f4f1ea">' + "".join(f'<rect x="{x0 + 0.6:.1f}" y="{sy + 3 + i * 3.4:.1f}" width="4.8" height="2.3"/>' for i in range(5)) + '</g>'
                 f'<rect x="{x1:.1f}" y="{sy + 2:.1f}" width="7" height="18" rx="1.5" fill="#c0392b" stroke="{INK}" stroke-width="{LINE}"/>'
                 f'<g fill="#f0c040">' + "".join(f'<circle cx="{x1 + 3.5:.1f}" cy="{sy + 5 + i * 3.4:.1f}" r="0.9"/>' for i in range(4)) + '</g>')
        return "", front
    if kind in ("guitar", "tamburica"):
        scale = 1.0 if kind == "guitar" else 0.8
        color = "#c27a3a" if kind == "guitar" else "#9a5a2a"
        bx, by = sx + 1, sy + 15
        neck_end = (sx + 20 * scale, sy - 3)
        strum = [0, 2.5, -1.5][frame % 3]
        body = (f'<path d="M{bx + 2:.1f} {by - 2:.1f} L{neck_end[0]:.1f} {neck_end[1]:.1f}" stroke="{INK}" stroke-width="{3.4 + 2 * LINE:.1f}" stroke-linecap="round"/>'
                f'<path d="M{bx + 2:.1f} {by - 2:.1f} L{neck_end[0]:.1f} {neck_end[1]:.1f}" stroke="#5a3a22" stroke-width="3.4" stroke-linecap="round"/>'
                f'<ellipse cx="{bx - 3 * scale:.1f}" cy="{by + 2:.1f}" rx="{8 * scale:.1f}" ry="{6.5 * scale:.1f}" fill="{color}" stroke="{INK}" stroke-width="{LINE}" transform="rotate(-25 {bx:.1f} {by:.1f})"/>'
                f'<ellipse cx="{bx + 4 * scale:.1f}" cy="{by - 2:.1f}" rx="{5.5 * scale:.1f}" ry="{4.6 * scale:.1f}" fill="{color}" stroke="{INK}" stroke-width="{LINE}" transform="rotate(-25 {bx:.1f} {by:.1f})"/>'
                f'<circle cx="{bx:.1f}" cy="{by:.1f}" r="{2 * scale:.1f}" fill="#2b1d14"/>')
        pose.near_hand = (bx - 2 + strum, by + 1)
        pose.far_hand = (neck_end[0] - 4, neck_end[1] + 2)
        return "", body
    if kind == "bass":
        x, y = sx - 13, sy + 12
        bow = [0, 3, -2][frame % 3]
        behind = (f'<path d="M{x + 2:.1f} {y - 34:.1f} L{x + 4:.1f} {y + 10:.1f}" stroke="{INK}" stroke-width="{3 + 2 * LINE}" stroke-linecap="round"/>'
                  f'<path d="M{x + 2:.1f} {y - 34:.1f} L{x + 4:.1f} {y + 10:.1f}" stroke="#4a2c18" stroke-width="3" stroke-linecap="round"/>'
                  f'<path d="M{x - 6:.1f} {y + 4:.1f} Q{x - 9:.1f} {y + 16:.1f} {x - 4:.1f} {y + 26:.1f} Q{x + 4:.1f} {y + 34:.1f} {x + 12:.1f} {y + 26:.1f} Q{x + 17:.1f} {y + 16:.1f} {x + 13:.1f} {y + 4:.1f} Q{x + 15:.1f} {y - 6:.1f} {x + 4:.1f} {y - 7:.1f} Q{x - 7:.1f} {y - 6:.1f} {x - 6:.1f} {y + 4:.1f} Z" fill="#a0522d" stroke="{INK}" stroke-width="{LINE}"/>'
                  f'<path d="M{x + 1:.1f} {y + 8:.1f} q-1 4 1 8 M{x + 7:.1f} {y + 8:.1f} q1 4 -1 8" stroke="{INK}" stroke-width="1" fill="none"/>')
        pose.far_hand = (x + 3, y - 18)
        pose.near_hand = (x + 9 + bow, y + 12)
        return behind, ""
    if kind == "violin":
        x, y = sx + 7, sy + 2
        bow = [0, 5, -4][frame % 3]
        front = (f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="5" ry="3.5" fill="#a0522d" stroke="{INK}" stroke-width="{LINE}" transform="rotate(30 {x:.1f} {y:.1f})"/>'
                 f'<path d="M{x + 3:.1f} {y + 2:.1f} L{x + 14:.1f} {y + 8:.1f}" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>'
                 f'<path d="M{x - 9 + bow:.1f} {y + 10:.1f} L{x + 9 + bow:.1f} {y - 6:.1f}" stroke="#d9c8a0" stroke-width="1.2"/>')
        pose.far_hand = (x + 13, y + 7)
        pose.near_hand = (x - 7 + bow, y + 9)
        return "", front
    if kind == "mic":
        sway = [0, 1.5, -1.5][frame % 3]
        x, y = sx + 10, sy - 3
        front = (f'<path d="M{x:.1f} {y + 2:.1f} L{x - 3:.1f} {y + 10:.1f}" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>'
                 f'<circle cx="{x + 0.5:.1f}" cy="{y:.1f}" r="2.4" fill="#9aa0a8" stroke="{INK}" stroke-width="1"/>')
        pose.near_hand = (x - 3, y + 9)
        pose.far_hand = (sx - 12 + sway, sy + 2 - abs(sway) * 2)
        return "", front
    return "", ""


def musician_frames(look: Look, kind: str) -> list:
    out = []
    for frame in range(4):
        breathe = [0, -0.8, 0, -0.8][frame]
        pose = _idle_pose("front", look, breathe)
        pose.eyes = "happy" if frame else "open"
        pose.mouth = ("open" if frame % 2 else "smile") if kind == "mic" else ("grin" if frame else "smile")
        if frame == 0:
            pose.eyes, pose.mouth = "open", "smile"
        behind, front = instrument(kind, pose, max(0, frame - 1))
        out.append((pose, behind, front))
    return out


def render_musician(look: Look, kind: str) -> list:
    cells = []
    for pose, behind, front in musician_frames(look, kind):
        parts = [behind, leg(look, pose, False), arm(look, pose, False), leg(look, pose, True), torso(look, pose), head(look, pose), front, arm(look, pose, True)]
        cells.append("".join(parts))
    return cells


# --------------------------------------------------------------------------------------------
# Cast
# --------------------------------------------------------------------------------------------

def L(name, **kw) -> Look:
    return Look(name=name, **kw)


GUESTS = {
    "penzioner": [
        L("penzioner_1", skin=SKIN[1], hair="#d9d6cf", hair_style="fringe", top="#7a5a3c", top_style="cardigan", accent="#efe8d8", bottom="#5a5a62", hat="cap", hat_color="#5f6066", extras=["mustache"]),
        L("penzioner_2", skin=SKIN[0], hair="#cfcdc8", hair_style="bun", top="#8a5a9a", top_style="cardigan", accent="#f2ece0", bottom="#4a4a58", skirt=True, extras=["glasses", "earrings"]),
        L("penzioner_3", skin=SKIN[2], hair="#bdbbb5", hair_style="bald", top="#f1ede4", top_style="vest", accent="#f1ede4", bottom="#3a3a44", extras=["glasses", "mustache"], build=1.08),
        L("penzioner_4", skin=SKIN[1], hair="#c8c4bc", hair_style="short", top="#f3efe6", top_style="vest", accent="#f3efe6", bottom="#2f2f36", hat="sajkaca", hat_color="#4a3b30", extras=["mustache"]),
        L("penzioner_5", skin=SKIN[0], hair="#c9c6c0", hair_style="short", top="#3f6e5a", top_style="dress", accent="#e9d27a", bottom="#3f6e5a", hat="scarf", hat_color="#b84a5a", shoes="#2b2b33"),
        L("penzioner_6", skin=SKIN[3], hair="#dcd8d0", hair_style="slick", top="#6b4f3a", top_style="suit", accent="#efe8d8", bottom="#6b4f3a", extras=["tie"], tie="#2f5d8a"),
    ],
    "studenti": [
        L("studenti_1", skin=SKIN[1], hair="#3a2a22", hair_style="messy", top="#2f9d8f", top_style="hoodie", bottom="#3b4f7a", shoes="#f1f1f1"),
        L("studenti_2", skin=SKIN[0], hair="#7a4a2a", hair_style="ponytail", top="#5b7fb8", top_style="jacket", accent="#f4f1ea", bottom="#2b2b33", shoes="#f1f1f1", extras=["earrings"]),
        L("studenti_3", skin=SKIN[3], hair="#1f1814", hair_style="curly", top="#e0a43a", top_style="tshirt", bottom="#3b4f7a", extras=["backpack"]),
        L("studenti_4", skin=SKIN[1], hair="#5a3a22", hair_style="long", top="#c25b7a", top_style="sweater", bottom="#34405c", extras=["glasses"]),
        L("studenti_5", skin=SKIN[2], hair="#2a2018", hair_style="short", top="#b8473a", top_style="shirt", bottom="#4a5a3a", hat="beanie", hat_color="#3b6e8a", extras=["beard"]),
        L("studenti_6", skin=SKIN[0], hair="#d9a648", hair_style="bob", top="#7fb069", top_style="tshirt", bottom="#2b2b33", skirt=True, shoes="#c25b7a"),
    ],
    "ozalosceni": [
        L("ozalosceni_1", skin=SKIN[1], hair="#2b2622", hair_style="short", top="#24242a", top_style="suit", accent="#f1eee8", bottom="#24242a", extras=["tie"], tie="#111114"),
        L("ozalosceni_2", skin=SKIN[0], hair="#1f1f24", hair_style="long", top="#2a2a30", top_style="dress", accent="#2a2a30", bottom="#2a2a30", hat="scarf", hat_color="#18181c"),
        L("ozalosceni_3", skin=SKIN[2], hair="#3a2a22", hair_style="short", top="#1e1e24", top_style="shirt", bottom="#2a2a30", extras=["beard"]),
        L("ozalosceni_4", skin=SKIN[1], hair="#2b2018", hair_style="bun", top="#26262c", top_style="blazer", accent="#3a3a40", bottom="#26262c", skirt=True, extras=["earrings"]),
        L("ozalosceni_5", skin=SKIN[1], hair="#d0ccc4", hair_style="fringe", top="#2c2c32", top_style="suit", accent="#f1eee8", bottom="#2c2c32", hat="fedora", hat_color="#1c1c20", extras=["tie", "mustache"], tie="#111114"),
        L("ozalosceni_6", skin=SKIN[3], hair="#1a1410", hair_style="messy", top="#2a2a30", top_style="sweater", bottom="#1e1e24"),
    ],
    "svatovi": [
        L("svatovi_1", skin=SKIN[0], hair="#5a3a22", hair_style="bun", top="#fbf8f1", top_style="dress", accent="#e7d39a", bottom="#fbf8f1", hat="veil", shoes="#f1f1f1", extras=["earrings"]),
        L("svatovi_2", skin=SKIN[1], hair="#2a2018", hair_style="slick", top="#1f2230", top_style="suit", accent="#f4f1ea", bottom="#1f2230", extras=["bowtie", "flower"], tie="#111114"),
        L("svatovi_3", skin=SKIN[2], hair="#3b2a1f", hair_style="short", top="#f5f2ea", top_style="vest", accent="#f5f2ea", bottom="#2b2b33", hat="sajkaca", hat_color="#2b2b33", extras=["mustache", "flower"]),
        L("svatovi_4", skin=SKIN[1], hair="#2e1f18", hair_style="long", top="#c23a3a", top_style="dress", accent="#f0c040", bottom="#c23a3a", hat="wreath", extras=["earrings"]),
        L("svatovi_5", skin=SKIN[3], hair="#1f1814", hair_style="short", top="#b8302f", top_style="vest", accent="#f5f2ea", bottom="#2b2b33", extras=["flower", "beard"]),
        L("svatovi_6", skin=SKIN[0], hair="#a0522d", hair_style="ponytail", top="#3f9d6a", top_style="dress", accent="#f0c040", bottom="#3f9d6a", extras=["earrings"]),
    ],
    "biznismen": [
        L("biznismen_1", skin=SKIN[1], hair="#1f1a17", hair_style="slick", top="#1f2a44", top_style="suit", accent="#f4f1ea", bottom="#1f2a44", extras=["tie", "shades"], tie="#d9a531"),
        L("biznismen_2", skin=SKIN[2], hair="#1c1816", hair_style="bald", top="#3a3a42", top_style="suit", accent="#f4f1ea", bottom="#3a3a42", extras=["chain", "mustache"], build=1.18),
        L("biznismen_3", skin=SKIN[1], hair="#2a2018", hair_style="short", top="#18181c", top_style="suit", accent="#f4f1ea", bottom="#18181c", extras=["tie", "mustache"], tie="#b8302f"),
        L("biznismen_4", skin=SKIN[0], hair="#3a2a22", hair_style="bun", top="#2f3e5c", top_style="blazer", accent="#f4f1ea", bottom="#2f3e5c", skirt=True, extras=["earrings", "glasses"]),
        L("biznismen_5", skin=SKIN[2], hair="#1f1814", hair_style="slick", top="#f2efe8", top_style="suit", accent="#1f1f24", bottom="#f2efe8", extras=["chain", "shades"]),
        L("biznismen_6", skin=SKIN[3], hair="#1a1410", hair_style="short", top="#4a2c20", top_style="jacket", bottom="#24242a", extras=["shades", "chain"]),
    ],
}

STAFF = {
    "waiter_1": L("waiter_1", skin=SKIN[1], hair="#2a2018", hair_style="slick", top="#1f1f24", top_style="vest", accent="#f7f4ee", bottom="#1f1f24", extras=["bowtie"], tie="#b8302f"),
    "waiter_2": L("waiter_2", skin=SKIN[0], hair="#5a3a22", hair_style="ponytail", top="#1f1f24", top_style="vest", accent="#f7f4ee", bottom="#1f1f24", extras=["bowtie"], tie="#b8302f"),
    "waiter_3": L("waiter_3", skin=SKIN[3], hair="#1a1410", hair_style="short", top="#1f1f24", top_style="vest", accent="#f7f4ee", bottom="#1f1f24", extras=["bowtie", "mustache"], tie="#b8302f"),
    "bartender": L("bartender", skin=SKIN[2], hair="#2a2018", hair_style="short", top="#f7f4ee", top_style="shirt", bottom="#2b2b33", extras=["mustache", "bowtie"], tie="#1f1f24"),
    "bouncer": L("bouncer", skin=SKIN[3], hair="#1a1410", hair_style="bald", top="#18181c", top_style="tshirt", bottom="#18181c", extras=["shades"], build=1.35),
}

MUSICIANS = {
    "accordion": L("m_accordion", skin=SKIN[1], hair="#3a2a22", hair_style="short", top="#f4f1ea", top_style="vest", accent="#f4f1ea", bottom="#1f1f24", extras=["mustache"]),
    "guitar": L("m_guitar", skin=SKIN[2], hair="#1f1814", hair_style="slick", top="#7a2a2a", top_style="shirt", bottom="#1f1f24"),
    "bass": L("m_bass", skin=SKIN[1], hair="#bdbbb5", hair_style="fringe", top="#2f3e5c", top_style="vest", accent="#f4f1ea", bottom="#1f1f24", extras=["glasses"]),
    "tamburica": L("m_tamburica", skin=SKIN[1], hair="#2a2018", hair_style="short", top="#f5f2ea", top_style="vest", accent="#f5f2ea", bottom="#2b2b33", hat="sajkaca", hat_color="#2b2b33"),
    "tamburica_2": L("m_tamburica_2", skin=SKIN[3], hair="#1a1410", hair_style="curly", top="#b8302f", top_style="vest", accent="#f5f2ea", bottom="#2b2b33", extras=["mustache"]),
    "violin": L("m_violin", skin=SKIN[0], hair="#7a4a2a", hair_style="long", top="#2a2a30", top_style="dress", accent="#f0c040", bottom="#2a2a30"),
    "mic": L("m_singer", skin=SKIN[0], hair="#1f1410", hair_style="long", top="#c0306a", top_style="dress", accent="#f0c040", bottom="#c0306a", extras=["earrings"]),
}

MUSICIAN_INSTRUMENT = {"accordion": "accordion", "guitar": "guitar", "bass": "bass", "tamburica": "tamburica",
                       "tamburica_2": "tamburica", "violin": "violin", "mic": "mic"}

BAND_LINEUPS = {
    "solo_harmonikas": ["accordion"],
    "trio": ["guitar", "accordion", "bass"],
    "tamburaski_orkestar": ["tamburica", "violin", "accordion", "tamburica_2", "bass"],
    "pevacica": ["guitar", "tamburica", "mic", "accordion", "violin", "bass"],
}


def sheet(cells: list, columns: int | None = None, scale: float = 2.0) -> str:
    columns = columns or len(cells)
    rows = (len(cells) + columns - 1) // columns
    w, h = CELL_W * columns, CELL_H * rows
    body = "".join(f'<g transform="translate({(i % columns) * CELL_W} {(i // columns) * CELL_H})">{c}</g>' for i, c in enumerate(cells))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * scale:.0f}" height="{h * scale:.0f}" viewBox="0 0 {w} {h}">'
            f'<g stroke-linejoin="round">{body}</g></svg>\n')
