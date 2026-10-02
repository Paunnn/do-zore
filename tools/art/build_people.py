"""Write every character animation sheet and people.json for the isometric kafana.

    python tools/art/build_people.py
"""

from __future__ import annotations

import json
from pathlib import Path

import people as P

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/world/people"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "cell": [P.CELL_W, P.CELL_H], "scale": 2, "foot": list(P.FOOT),
        "guest_anims": P.GUEST_ANIMS, "waiter_anims": P.WAITER_ANIMS,
        "guests": {}, "waiters": [], "musicians": {}, "band_lineups": P.BAND_LINEUPS,
    }
    for kind, looks in P.GUESTS.items():
        manifest["guests"][kind] = []
        for look in looks:
            cells = [P.figure(look, pose) for pose in P.guest_poses(look)]
            (OUT / f"{look.name}.svg").write_text(P.sheet(cells), encoding="utf-8")
            manifest["guests"][kind].append(look.name)
    for name, look in P.STAFF.items():
        if name.startswith("waiter"):
            cells = [P.figure(look, pose) for pose in P.waiter_poses(look)]
            manifest["waiters"].append(name)
        else:
            cells = [P.figure(look, pose) for pose in P.staff_poses(look, name)]
            manifest[name] = {"file": name, "frames": len(cells)}
        (OUT / f"{name}.svg").write_text(P.sheet(cells), encoding="utf-8")
    for key, look in P.MUSICIANS.items():
        cells = P.render_musician(look, P.MUSICIAN_INSTRUMENT[key])
        (OUT / f"musician_{key}.svg").write_text(P.sheet(cells), encoding="utf-8")
        manifest["musicians"][key] = f"musician_{key}"
    (OUT / "people.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    print(f"{sum(len(v) for v in manifest['guests'].values())} guests, {len(manifest['waiters'])} waiters, "
          f"{len(manifest['musicians'])} musicians -> {OUT}")


if __name__ == "__main__":
    main()
