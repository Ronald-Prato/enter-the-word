"""Genera escenas .tscn heredadas de room_base con open_exits y decor_variant."""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOMS = ROOT / "scenes" / "rooms"
BASE = "res://scenes/rooms/room_base.tscn"

SCENE_TEMPLATE = """[gd_scene format=4 uid="{uid}"]

[ext_resource type="PackedScene" uid="uid://bym2kjnpytjvx" path="res://scenes/rooms/room_base.tscn" id="1_base"]

[node name="{name}" type="Node2D" instance=ExtResource("1_base")]
open_exits = {mask}
decor_variant = {variant}
exterior_deco_salt = {salt}
"""


def mask_from_letters(letters: str) -> int:
    m = 0
    if "N" in letters:
        m |= 1
    if "S" in letters:
        m |= 2
    if "E" in letters:
        m |= 4
    if "W" in letters:
        m |= 8
    return m


def write_room(folder: Path, stem: str, mask: int, variant: int, salt: int) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    h = hashlib.sha256(f"{folder.name}/{stem}_{variant}".encode()).hexdigest()
    uid = "uid://" + h[:12]
    path = folder / f"{stem}.tscn"
    name = stem.replace("-", "_")
    path.write_text(
        SCENE_TEMPLATE.format(uid=uid, name=name, mask=mask, variant=variant, salt=salt),
        encoding="utf-8",
    )


def main() -> None:
    salt = 1
    # 1exit
    for d in ("N", "S", "E", "W"):
        for v in (1, 2):
            write_room(ROOMS / "1exit", f"{d}_{v}", mask_from_letters(d), v, salt)
            salt += 1
    # 2exit (orden alfabético de par de letras)
    pairs2 = ("NS", "NE", "NW", "SE", "SW", "EW")
    for p in pairs2:
        for v in (1, 2):
            write_room(ROOMS / "2exit", f"{p}_{v}", mask_from_letters(p), v, salt)
            salt += 1
    # 3exit
    triples = ("NSE", "NSW", "NEW", "SEW")
    for t in triples:
        for v in (1, 2):
            write_room(ROOMS / "3exit", f"{t}_{v}", mask_from_letters(t), v, salt)
            salt += 1
    # 4exit
    for v in (1, 2):
        write_room(ROOMS / "4exit", f"NSEW_{v}", 15, v, salt)
        salt += 1
    print("Wrote rooms under", ROOMS)


if __name__ == "__main__":
    main()
