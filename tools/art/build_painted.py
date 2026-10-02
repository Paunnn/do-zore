"""Cut the painted kafana source images into game-ready layers.

Inputs live in client/art_source/painted (excluded from Godot import):
  kafana_empty.png      empty room (walls, lights, stage, musician, bare floor)
  kafana_tables.png     the same room with tables; one table is cut out of it
  musician_motion.mp4   image-to-video clip of the accordion player

Outputs go to client/assets/art and client/assets/art/layout.json. Everything is
expressed in world pixels: the room is scaled to the 1080 px design width.

    python tools/art/build_painted.py
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "client/art_source/painted"
OUT = ROOT / "client/assets/art"
WIDTH = 1080
SHEET_SCALE = 0.5   # musician frames are stored at half size; the clip is ~480p anyway
FLOOR_CUT = 1660    # world y where the painted room hands over to the repeating floor tile
FLOOR_TILE = 590    # height of the repeating floor tile
FLOOR_OVERLAP = 40  # extra source rows used to make the tile seamless
TABLE_BOX = (205, 1000, 585, 1360)  # table cut-out in source pixels (x0, y0, x1, y1)


def sift_transform(moving: np.ndarray, fixed: np.ndarray, mask: np.ndarray | None = None,
                   homography: bool = False) -> np.ndarray:
    """3x3 transform that maps `moving` pixels onto `fixed`."""
    sift = cv2.SIFT_create(6000)
    km, dm = sift.detectAndCompute(cv2.cvtColor(moving, cv2.COLOR_BGR2GRAY), None)
    kf, df = sift.detectAndCompute(cv2.cvtColor(fixed, cv2.COLOR_BGR2GRAY), mask)
    pairs = cv2.BFMatcher().knnMatch(dm, df, k=2)
    good = [a for a, b in pairs if a.distance < 0.75 * b.distance]
    src = np.float32([km[a.queryIdx].pt for a in good])
    dst = np.float32([kf[a.trainIdx].pt for a in good])
    if homography:
        matrix, _ = cv2.findHomography(src, dst, cv2.RANSAC, 2.0)
        return matrix
    affine, _ = cv2.estimateAffinePartial2D(src, dst, method=cv2.RANSAC, ransacReprojThreshold=2.0)
    return np.vstack([affine, [0, 0, 1]])


def color_match(image: np.ndarray, reference: np.ndarray, region: np.ndarray) -> np.ndarray:
    result = image.astype(np.float32).copy()
    for channel in range(3):
        a = result[..., channel][region]
        b = reference[..., channel][region].astype(np.float32)
        result[..., channel] = (result[..., channel] - a.mean()) * (b.std() / (a.std() + 1e-6)) + b.mean()
    return np.clip(result, 0, 255)


def fill_holes(mask: np.ndarray) -> np.ndarray:
    flood = mask.copy()
    border = np.zeros((mask.shape[0] + 2, mask.shape[1] + 2), np.uint8)
    cv2.floodFill(flood, border, (0, 0), 1)
    return mask | (flood == 0).astype(np.uint8)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    empty = cv2.imread(str(SOURCE / "kafana_empty.png"))
    tables = cv2.imread(str(SOURCE / "kafana_tables.png"))
    scale = WIDTH / empty.shape[1]
    height = int(round(empty.shape[0] * scale))
    to_world = np.diag([scale, scale, 1.0])
    room = cv2.resize(empty, (WIDTH, height), interpolation=cv2.INTER_LANCZOS4).astype(np.float32)

    # The table image differs from the empty room by a small camera shift: register on the
    # walls and stage only, where both images share content.
    upper = np.zeros(empty.shape[:2], np.uint8)
    upper[:640] = 255
    tables_to_empty = sift_transform(tables, empty, upper, homography=True)

    # --- musician: every video frame registered straight into world space -----------------
    capture = cv2.VideoCapture(str(SOURCE / "musician_motion.mp4"))
    frames = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        frames.append(frame)
    warped = []
    for frame in frames:
        to_tables = sift_transform(frame, tables)
        matrix = to_world @ tables_to_empty @ to_tables
        warped.append(cv2.warpPerspective(frame, matrix, (WIDTH, height), flags=cv2.INTER_CUBIC,
                                          borderMode=cv2.BORDER_REPLICATE).astype(np.float32))
    box = (30, 330, 470, 830)  # world area around the stage that may contain the musician
    x0, y0, x1, y1 = box
    stack = np.stack([w[y0:y1, x0:x1] for w in warped])
    motion = (stack.std(axis=0).mean(axis=2) > 6).astype(np.uint8)
    motion = cv2.morphologyEx(motion, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(motion)
    keep = np.zeros_like(motion)
    if count > 1:
        keep[labels == 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))] = 1
    keep = cv2.dilate(keep, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (45, 45)))
    keep = fill_holes(cv2.morphologyEx(keep, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (61, 61))))
    mask = np.zeros((height, WIDTH), np.float32)
    mask[y0:y1, x0:x1] = keep
    mask = np.clip(cv2.GaussianBlur(mask, (0, 0), 10) * 1.2, 0, 1)
    ring = (cv2.GaussianBlur(mask, (0, 0), 30) > 0.02) & (mask < 0.01)
    warped = [color_match(w, room, ring) for w in warped]
    bx, by, bw, bh = cv2.boundingRect((mask > 0.01).astype(np.uint8))
    bx, by = bx - bx % 2, by - by % 2
    bw, bh = bw + bw % 2, bh + bh % 2

    # Idle pose = first frame, baked into the backdrop so the animation starts without a pop.
    m3 = mask[..., None]
    room = room * (1 - m3) + warped[0] * m3

    # Ping-pong is done at runtime; store frames once at half size in one sheet.
    fw, fh = int(bw * SHEET_SCALE), int(bh * SHEET_SCALE)
    columns = 7
    rows = (len(warped) + columns - 1) // columns
    sheet = np.zeros((rows * fh, columns * fw, 4), np.uint8)
    alpha = (mask[by:by + bh, bx:bx + bw] * 255).astype(np.uint8)
    for index, frame in enumerate(warped):
        rgba = np.dstack([frame[by:by + bh, bx:bx + bw].astype(np.uint8), alpha])
        small = cv2.resize(rgba, (fw, fh), interpolation=cv2.INTER_AREA)
        r, c = divmod(index, columns)
        sheet[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = small
    sheet[sheet[..., 3] == 0, :3] = 0
    cv2.imwrite(str(OUT / "musician_sheet.webp"), sheet, [cv2.IMWRITE_WEBP_QUALITY, 88])

    # --- backdrop and repeating floor --------------------------------------------------------
    room_u8 = np.clip(room, 0, 255).astype(np.uint8)
    cv2.imwrite(str(OUT / "kafana_room.jpg"), room_u8[:FLOOR_CUT], [cv2.IMWRITE_JPEG_QUALITY, 90])
    source = room[FLOOR_CUT - FLOOR_TILE:FLOOR_CUT + FLOOR_OVERLAP]
    tile = source[:FLOOR_TILE].copy()
    for k in range(FLOOR_OVERLAP):
        weight = k / FLOOR_OVERLAP
        tile[k] = source[k] * weight + source[k + FLOOR_TILE] * (1 - weight)
    cv2.imwrite(str(OUT / "floor_tile.jpg"), np.clip(tile, 0, 255).astype(np.uint8), [cv2.IMWRITE_JPEG_QUALITY, 90])

    # --- one table, cut out of the furnished room ----------------------------------------------
    furnished = cv2.warpPerspective(tables, tables_to_empty, (empty.shape[1], empty.shape[0]),
                                    flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    tx0, ty0, tx1, ty1 = TABLE_BOX
    crop = furnished[ty0:ty1, tx0:tx1]
    diff = cv2.GaussianBlur(cv2.absdiff(crop, empty[ty0:ty1, tx0:tx1]), (0, 0), 1.5).max(axis=2)
    cut = (diff > 16).astype(np.uint8)
    cut = fill_holes(cv2.morphologyEx(cut, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))))
    cut = cv2.morphologyEx(cut, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
    count, labels, stats, centers = cv2.connectedComponentsWithStats(cut)
    keep = np.zeros_like(cut)
    for j in range(1, count):
        x, y, w, h, area = stats[j]
        if area > 300 and x + w < cut.shape[1] - 2 and abs(centers[j][0] - cut.shape[1] / 2) < 150:
            keep[labels == j] = 1
    table_alpha = cv2.GaussianBlur(keep.astype(np.float32), (0, 0), 1.2)
    # The source table touches the bottom of the painting: fade the cut chair legs into the floor.
    fade = np.clip((cut.shape[0] - 1 - np.arange(cut.shape[0])) / 40.0, 0, 1)
    table_alpha *= fade[:, None]
    table = np.dstack([crop, (table_alpha * 255).astype(np.uint8)])
    tw, th = int(round(table.shape[1] * scale)), int(round(table.shape[0] * scale))
    table = cv2.resize(table, (tw, th), interpolation=cv2.INTER_LANCZOS4)
    s = scale
    # Layers, in cut-out pixels: everything below the cloth's back edge sits in front of guests
    # on the back chairs; the two front backrests sit in front of guests seen from behind.
    back_edge = [(0, 175), (40, 175), (62, 128), (190, 68), (305, 122), (345, 175), (380, 175), (380, 360), (0, 360)]
    backrests = [[(8, 160), (100, 160), (100, 360), (8, 360)], [(282, 160), (372, 160), (372, 360), (282, 360)]]
    front = np.zeros((th, tw), np.uint8)
    cv2.fillPoly(front, [np.int32([(x * s, y * s) for x, y in back_edge])], 255)
    rests = np.zeros((th, tw), np.uint8)
    for poly in backrests:
        cv2.fillPoly(rests, [np.int32([(x * s, y * s) for x, y in poly])], 255)
    # Backrests only where the chair is: keep wood-coloured pixels, drop the cloth and floor gaps.
    hsv = cv2.cvtColor(table[..., :3], cv2.COLOR_BGR2HSV)
    wood = ((hsv[..., 0] >= 5) & (hsv[..., 0] <= 25) & (hsv[..., 1] > 90)).astype(np.uint8) * 255
    rests = cv2.bitwise_and(rests, cv2.dilate(wood, np.ones((3, 3), np.uint8)))
    for name, layer in [("table_back.png", None), ("table_front.png", front), ("table_rests.png", rests)]:
        image = table.copy()
        if layer is not None:
            image[..., 3] = (image[..., 3].astype(np.float32) * cv2.GaussianBlur(layer, (0, 0), 0.8) / 255).astype(np.uint8)
        image[image[..., 3] == 0, :3] = 0
        cv2.imwrite(str(OUT / name), image)

    # --- lights -------------------------------------------------------------------------------
    value = cv2.cvtColor(empty, cv2.COLOR_BGR2HSV)[..., 2]
    bright = ((value > 235) & (np.arange(empty.shape[0])[:, None] < 420)).astype(np.uint8)
    count, labels, stats, centers = cv2.connectedComponentsWithStats(bright)
    lanterns, bulbs = [], []
    for j in range(1, count):
        area = stats[j, cv2.CC_STAT_AREA]
        point = [round(float(centers[j][0] * scale), 1), round(float(centers[j][1] * scale), 1)]
        if area > 600:
            lanterns.append(point)
        elif 60 < area <= 600 and stats[j, cv2.CC_STAT_WIDTH] < 25:
            bulbs.append(point)

    layout = {
        "width": WIDTH,
        "room_height": FLOOR_CUT,
        "floor_tile_height": FLOOR_TILE,
        "musician": {"x": bx, "y": by, "w": bw, "h": bh, "frames": len(warped), "columns": columns,
                     "frame_w": fw, "frame_h": fh, "fps": 16},
        "stage": [40 * scale, 300 * scale, 410 * scale, 640 * scale],
        "table": {"w": tw, "h": th, "back_seats": [[78 * s, 112 * s], [300 * s, 112 * s]],
                  "front_seats": [[112 * s, 228 * s], [262 * s, 228 * s]], "top": [182 * s, 120 * s]},
        "lanterns": lanterns,
        "bulbs": bulbs,
    }
    (OUT / "layout.json").write_text(json.dumps(layout, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: layout[k] for k in ("musician", "table")}, indent=1))
    print(f"{len(lanterns)} lanterns, {len(bulbs)} bulbs, room {WIDTH}x{FLOOR_CUT}")


if __name__ == "__main__":
    main()
