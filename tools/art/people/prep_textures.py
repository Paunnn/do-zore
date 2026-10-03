"""Cartoon versions of the MakeHuman hair and clothes textures: flat colour areas, clean alpha edges.

Hair becomes a mid grey with soft strand shading (the game tints it with the person's hair colour) and a
clean cut-out edge; clothes are flattened with mean-shift filtering into painted areas. One PNG per
source texture, same file name, in $DO_ZORE_ART_CACHE/toon_tex (build_people.py picks them up).

    python3 tools/art/people/prep_textures.py
"""
import glob, os, sys
import numpy as np
import cv2

CACHE = os.environ.get("DO_ZORE_ART_CACHE", os.path.expanduser("~/.cache/do-zore-art"))
MH = os.path.join(CACHE, "mh/data")


def read(path):
    img = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if img is None:
        return None
    if img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGRA)
    if img.shape[2] == 3:
        img = np.concatenate([img, np.full(img.shape[:2] + (1,), 255, np.uint8)], axis=2)
    return img


def clean_alpha(a, blur, lo, hi):
    a = cv2.GaussianBlur(a.astype(np.float32) / 255.0, (0, 0), blur)
    a = np.clip((a - lo) / (hi - lo), 0, 1)
    return (a * 255).astype(np.uint8)


def hair(path, out, size=1024):
    img = read(path)
    img = cv2.resize(img, (size, size), interpolation=cv2.INTER_AREA)
    bgr, a = img[..., :3], img[..., 3]
    # Fill the colour under transparent pixels so mipmaps don't bleed dark fringes.
    lum = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
    m = a > 40
    mean = lum[m].mean() if m.any() else 128.0
    lum = np.where(m, lum, mean)
    lum = cv2.bilateralFilter(lum.astype(np.float32), 9, 30, 9)
    lum = cv2.GaussianBlur(lum, (0, 0), 2.0)
    # Centre on mid grey with gentle strand shading: the shader tints it with the hair colour.
    g = np.clip(0.62 + (lum - mean) / max(lum[m].std() if m.any() else 1.0, 1.0) * 0.07, 0.45, 0.8)
    g = (g * 255).astype(np.uint8)
    a = clean_alpha(a, 3.0, 0.32, 0.5)
    cv2.imwrite(out, cv2.merge([g, g, g, a]))


def clothes(path, out, size=1024):
    img = read(path)
    img = cv2.resize(img, (size, size), interpolation=cv2.INTER_AREA)
    bgr, a = img[..., :3].copy(), img[..., 3]
    # Mean-shift flattens fabric weave and photo shading into flat painted areas.
    flat = cv2.pyrMeanShiftFiltering(bgr, 8, 28)
    flat = cv2.bilateralFilter(flat, 7, 40, 7)
    hsv = cv2.cvtColor(flat, cv2.COLOR_BGR2HSV).astype(np.float32)
    hsv[..., 1] = np.clip(hsv[..., 1] * 1.15, 0, 255)
    flat = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)
    a = clean_alpha(a, 1.0, 0.3, 0.6) if a.min() < 250 else a
    cv2.imwrite(out, cv2.merge([flat[..., 0], flat[..., 1], flat[..., 2], a]))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(CACHE, "toon_tex")
    os.makedirs(out, exist_ok=True)
    for kind, fn in (("hair", hair), ("clothes", clothes)):
        for path in sorted(glob.glob(f"{MH}/{kind}/*/*.png")):
            name = os.path.basename(path)
            if any(t in name.lower() for t in ("normal", "norm", "_ao", "spec", "bump", "_disp", "height")):
                continue
            target = os.path.join(out, name)
            if os.path.exists(target):
                continue
            fn(path, target)
            print(kind, name)
