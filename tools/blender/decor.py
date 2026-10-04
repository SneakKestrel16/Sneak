"""Furniture and decorations that dress the rooms, exported to assets/models/decor/.

Every model is moved so its origin is on the floor in the middle of its footprint, front
toward -Y (its back goes against a wall). The catalogue, assets/models/decor.json, lists each
with its measured size and how scripts/decor.gd places it:

- place: "wall" (back to a wall), "corner" (back to a wall, slid into a corner), "free"
  (anywhere clear in the room), "rug" (flat in the middle of the room, walked over) or "hang"
  (on a wall, its bottom `mount` metres up, no collision).
- themes: the room themes it belongs in (see THEMES in scripts/decor.gd).
- tints: optional colours for surfaces named "tint_...", one chosen per piece.
- anywhere: clutter that may also stand away from the walls, like a "free" piece.
"""

import math
import random
from collections.abc import Callable
from dataclasses import dataclass, field

import lib
from lib import blob, box, cyl, lathe, mat, sheet, sphere, torus, tube

OUT = lib.MODELS / "decor"

# Shared materials, made on demand after each scene reset.


def oak():
    return mat("wood_oak", (0.5, 0.34, 0.2), 0.55)


def walnut():
    return mat("wood_walnut", (0.27, 0.17, 0.1), 0.45)


def pine():
    return mat("wood_pine", (0.68, 0.54, 0.36), 0.7)


def steel():
    return mat("metal_steel", (0.6, 0.62, 0.64), 0.35, 1.0)


def iron():
    return mat("metal_iron", (0.2, 0.2, 0.2), 0.55, 1.0)


def brass():
    return mat("metal_brass", (0.78, 0.6, 0.25), 0.3, 1.0)


def porcelain():
    return mat("glaze_white", (0.92, 0.92, 0.9), 0.1)


def glass():
    return mat("glass_clear", (0.8, 0.9, 1.0), 0.05)


def warm_glow():
    return mat("glow_warm", (1.0, 0.82, 0.55), emission=3.0)


def tint_fabric(color=(0.45, 0.12, 0.12)):
    return mat("tint_fabric", color, 1.0)


BOOK_COLOURS = [
    (0.45, 0.12, 0.1),
    (0.12, 0.2, 0.4),
    (0.15, 0.3, 0.15),
    (0.5, 0.4, 0.25),
    (0.2, 0.15, 0.12),
    (0.55, 0.5, 0.42),
]


def turn(parts: list, yaw: float, at: tuple[float, float, float]) -> list:
    """Turns parts built round the origin by yaw about Z, then moves them to at."""
    for part in parts:
        x, y, z = lib.rotated(part.location, yaw)
        part.location = (x + at[0], y + at[1], z + at[2])
        part.rotation_euler.z += yaw
    return parts


def legs(w: float, d: float, h: float, r: float, material, inset: float = 0.04, square=False):
    """Four legs under a w x d top whose underside is h up."""
    parts = []
    for x in (-1, 1):
        for y in (-1, 1):
            at = (x * (w / 2 - inset - r), y * (d / 2 - inset - r), h / 2)
            if square:
                parts.append(box((r * 2, r * 2, h), at, material, 0.004))
            else:
                parts.append(cyl(r, r * 0.75, h, at, material, segments=12))
    return parts


def books(x0: float, x1: float, y: float, z: float, depth: float, rng: random.Random, tall=0.3):
    """A shelf's row of books from x0 to x1, standing on z, spines toward -Y."""
    parts = []
    x = x0
    while x < x1 - 0.03:
        thick = rng.uniform(0.025, 0.06)
        if x + thick > x1:
            break
        if rng.random() < 0.08:  # A gap, now and then.
            x += thick
            continue
        high = rng.uniform(tall * 0.65, tall)
        colour = rng.randrange(len(BOOK_COLOURS))
        cover = mat(f"leather_book{colour}", BOOK_COLOURS[colour], 0.7)
        lean = rng.uniform(-0.06, 0.06) if rng.random() < 0.2 else 0.0
        book = box(
            (thick, depth * rng.uniform(0.75, 0.95), high),
            (x + thick / 2, y, z + high / 2),
            cover,
        )  # Unbevelled: a shelf holds hundreds, and bevels tripled the file.
        book.rotation_euler.y = lean
        parts.append(book)
        x += thick + 0.002
    return parts


def jar(at, r: float, h: float, colour, rng: random.Random | None = None):
    """A glass jar with a lid, partly full of glowing or murky liquid."""
    glow = mat(f"glow_jar{colour}", colour, emission=1.5)
    x, y, z = at
    fill = h * (rng.uniform(0.4, 0.85) if rng else 0.7)
    return [
        cyl(r, r, h, (x, y, z + h / 2), glass(), segments=16),
        cyl(r * 0.9, r * 0.9, fill, (x, y, z + fill / 2 + 0.003), glow, segments=16),
        cyl(r * 1.05, r * 1.05, 0.015, (x, y, z + h + 0.007), iron(), segments=16),
    ]


def chair(wood, seat, at=(0, 0, 0), yaw=0.0):
    """A dining chair facing -Y, seat 0.46 up, ready to be turned to a table."""
    parts = legs(0.44, 0.42, 0.44, 0.02, wood, 0.01, square=True)
    parts.append(box((0.46, 0.44, 0.04), (0, 0, 0.46), wood, 0.008))
    parts.append(box((0.42, 0.4, 0.05), (0, -0.01, 0.5), seat, 0.02))
    for x in (-1, 1):
        parts.append(box((0.035, 0.035, 0.5), (x * 0.2, 0.2, 0.73), wood, 0.006))
    parts.append(box((0.44, 0.03, 0.14), (0, 0.205, 0.9), wood, 0.008))
    parts.append(box((0.38, 0.02, 0.18), (0, 0.205, 0.7), wood, 0.005))
    return turn(parts, yaw, at)


def cushion(size, at, material, rot=(0, 0, 0)):
    return box(size, at, material, min(size) * 0.4, rot)


# Living room -----------------------------------------------------------------


def sofa(rng):
    cloth = tint_fabric()
    w, d = 2.0, 0.9
    parts = [box((w, d, 0.28), (0, 0, 0.24), cloth, 0.04)]
    parts += legs(w, d, 0.1, 0.03, walnut(), 0.06)
    for x in (-1, 1):
        parts.append(cushion((0.2, d, 0.62), (x * (w / 2 - 0.1), 0, 0.41), cloth))
    for i in range(3):
        x = (i - 1) * 0.54
        parts.append(cushion((0.54, 0.62, 0.16), (x, -0.08, 0.45), cloth))
        parts.append(cushion((0.52, 0.2, 0.46), (x, 0.3, 0.68), cloth, (-0.15, 0, 0)))
    parts.append(box((w - 0.4, 0.14, 0.5), (0, d / 2 - 0.07, 0.62), cloth, 0.04))
    parts.append(
        cushion(
            (0.38, 0.12, 0.34),
            (-0.72, 0.15, 0.62),
            mat("fabric_cream", (0.75, 0.7, 0.58), 1.0),
            (-0.3, 0, 0.3),
        )
    )
    return parts


def armchair(rng):
    cloth = tint_fabric()
    w, d = 0.85, 0.85
    parts = [box((w, d, 0.3), (0, 0, 0.25), cloth, 0.04)]
    parts += legs(w, d, 0.1, 0.025, walnut(), 0.05)
    for x in (-1, 1):
        parts.append(cushion((0.15, d - 0.1, 0.6), (x * (w / 2 - 0.075), -0.03, 0.42), cloth))
        wing = cushion((0.12, 0.3, 0.55), (x * (w / 2 - 0.08), 0.3, 0.92), cloth, (0, 0, -x * 0.25))
        parts.append(wing)
    parts.append(cushion((w - 0.3, d - 0.2, 0.15), (0, -0.08, 0.47), cloth))
    parts.append(box((w - 0.1, 0.16, 0.95), (0, d / 2 - 0.08, 0.75), cloth, 0.05))
    return parts


def coffee_table(rng):
    wood = walnut()
    parts = [
        box((1.1, 0.6, 0.05), (0, 0, 0.43), wood, 0.01),
        box((1.0, 0.5, 0.02), (0, 0, 0.12), wood, 0.005),
    ]
    parts += legs(1.1, 0.6, 0.41, 0.025, wood, 0.03, square=True)
    parts += book_pile((0.25, 0.05, 0.455), rng, 3)
    parts.append(cyl(0.11, 0.07, 0.06, (-0.25, 0.0, 0.485), porcelain(), segments=24))
    return parts


def book_pile(at, rng, count):
    parts = []
    z = at[2]
    for _ in range(count):
        colour = rng.randrange(len(BOOK_COLOURS))
        cover = mat(f"leather_book{colour}", BOOK_COLOURS[colour], 0.7)
        t = rng.uniform(0.03, 0.05)
        b = box((0.2, 0.27, t), (at[0], at[1], z + t / 2), cover, 0.004)
        b.rotation_euler.z = rng.uniform(-0.3, 0.3)
        parts.append(b)
        z += t
    return parts


def bookcase(rng):
    wood = walnut()
    w, d, h = 1.0, 0.36, 2.0
    parts = [box((w, 0.02, h), (0, d / 2 - 0.01, h / 2), wood)]
    for x in (-1, 1):
        parts.append(box((0.03, d, h), (x * (w / 2 - 0.015), 0, h / 2), wood, 0.004))
    shelves = [0.08, 0.45, 0.82, 1.19, 1.56, 1.96]
    for z in shelves:
        parts.append(box((w, d, 0.03), (0, 0, z), wood, 0.004))
    parts.append(box((w + 0.06, d + 0.04, 0.06), (0, -0.01, h - 0.01), wood, 0.01))
    parts.append(box((w, 0.03, 0.08), (0, -d / 2 + 0.015, 0.04), wood, 0.004))
    for z0, z1 in zip(shelves, shelves[1:], strict=False):
        parts += books(
            -w / 2 + 0.04, w / 2 - 0.04, 0.02, z0 + 0.015, d - 0.06, rng, min(z1 - z0 - 0.05, 0.32)
        )
    return parts


def fireplace(rng):
    stone = mat("stone_surround", (0.55, 0.52, 0.48), 0.85)
    soot = mat("plain_soot", (0.03, 0.03, 0.03), 1.0)
    log = mat("wood_log", (0.3, 0.2, 0.12), 0.9)
    embers = mat("glow_embers", (1.0, 0.35, 0.08), emission=4.0)
    w, d, h = 1.6, 0.5, 1.2
    parts = [
        box((w, d, 0.12), (0, 0, 0.06), stone, 0.01),
        box((0.32, d - 0.06, h - 0.2), (-w / 2 + 0.16, 0.03, 0.12 + (h - 0.2) / 2), stone, 0.01),
        box((0.32, d - 0.06, h - 0.2), (w / 2 - 0.16, 0.03, 0.12 + (h - 0.2) / 2), stone, 0.01),
        box((w - 0.64, d - 0.06, 0.3), (0, 0.03, h - 0.23), stone, 0.01),
        box((w + 0.1, d + 0.06, 0.08), (0, -0.0, h - 0.04), walnut(), 0.01),
        box((w - 0.64, 0.05, h - 0.4), (0, d / 2 - 0.05, 0.12 + (h - 0.4) / 2), soot),
        box((w - 0.64, d - 0.1, 0.02), (0, 0.04, 0.13), soot),
    ]
    for k in range(3):
        y = 0.02 + k * 0.03
        lg = cyl(0.05, 0.05, 0.55, (0, y, 0.2 + k * 0.05), log, (0, math.pi / 2, (k - 1) * 0.3), 12)
        parts.append(lg)
    parts.append(box((0.5, 0.25, 0.03), (0, 0.04, 0.155), embers, 0.01))
    for x in (-0.25, 0.25):
        parts.append(box((0.03, 0.3, 0.12), (x, 0.0, 0.2), iron(), 0.005))
    for x in (-0.6, 0.6):
        parts.append(cyl(0.035, 0.025, 0.2, (x, 0, h + 0.1), brass(), segments=12))
        parts.append(
            cyl(
                0.012,
                0.012,
                0.12,
                (x, 0, h + 0.26),
                mat("plain_wax", (0.92, 0.88, 0.76), 0.6),
                segments=8,
            )
        )
    parts.append(
        lathe(
            [(0.0, 0.0), (0.06, 0.0), (0.09, 0.08), (0.05, 0.2), (0.07, 0.24), (0.0, 0.24)],
            (0.2, 0, h),
            mat("tint_glaze", (0.3, 0.45, 0.6), 0.12),
            segments=24,
        )
    )
    return parts


def floor_lamp(rng):
    shade = mat("fabric_shade", (0.85, 0.75, 0.55), 1.0)
    parts = [
        lathe(
            [(0.0, 0.0), (0.18, 0.0), (0.17, 0.03), (0.04, 0.06), (0.0, 0.06)],
            material=brass(),
            segments=32,
        ),
        cyl(0.015, 0.015, 1.4, (0, 0, 0.75), brass(), segments=10),
        lathe(
            [(0.12, 1.32), (0.21, 1.62), (0.2, 1.62), (0.11, 1.33)],
            material=shade,
            segments=32,
            closed=True,
        ),
        sphere(0.05, (0, 0, 1.45), warm_glow(), segments=12),
    ]
    return parts


def potted_plant(rng):
    pot = mat("stone_terracotta", (0.62, 0.32, 0.2), 0.85)
    soil = mat("plain_soil", (0.12, 0.09, 0.06), 1.0)
    leaf = mat("fabric_leaf", (0.18, 0.36, 0.14), 0.7)
    stem = mat("wood_stem", (0.3, 0.25, 0.12), 0.8)
    parts = [
        lathe(
            [(0.0, 0.0), (0.14, 0.0), (0.2, 0.36), (0.22, 0.38), (0.22, 0.42), (0.0, 0.42)],
            material=pot,
            segments=28,
        ),
        cyl(0.19, 0.19, 0.01, (0, 0, 0.415), soil, segments=28),
    ]
    for _ in range(9):
        a = rng.uniform(0, 2 * math.pi)
        reach = rng.uniform(0.12, 0.28)
        top = rng.uniform(0.75, 1.25)
        tip = (math.cos(a) * reach, math.sin(a) * reach, top)
        mid = (tip[0] * 0.3, tip[1] * 0.3, (0.42 + top) / 2)
        parts.append(tube([(0, 0, 0.4), mid, tip], [0.012, 0.009, 0.005], stem, 6))
        for k in range(3):
            t = 0.5 + k * 0.22
            at = (
                mid[0] + (tip[0] - mid[0]) * t,
                mid[1] + (tip[1] - mid[1]) * t,
                mid[2] + (tip[2] - mid[2]) * t,
            )
            blade = sphere(0.1, at, leaf, (1.0, 0.4, 0.06), segments=10)
            blade.rotation_euler = (
                rng.uniform(-0.6, 0.6),
                rng.uniform(-0.5, 0.5),
                a + rng.uniform(-0.5, 0.5),
            )
            parts.append(blade)
    return parts


def side_table(rng):
    wood = walnut()
    parts = [
        lathe([(0.0, 0.58), (0.25, 0.58), (0.25, 0.61), (0.0, 0.61)], material=wood, segments=32)
    ]
    parts.append(
        lathe(
            [
                (0.0, 0.0),
                (0.18, 0.0),
                (0.16, 0.03),
                (0.03, 0.08),
                (0.04, 0.3),
                (0.025, 0.56),
                (0.05, 0.58),
                (0.0, 0.58),
            ],
            material=wood,
            segments=24,
        )
    )
    parts += table_lamp((0.05, 0.05, 0.61))
    return parts


def table_lamp(at, shade_colour=(0.85, 0.75, 0.55)):
    shade = mat("fabric_shade", shade_colour, 1.0)
    x, y, z = at
    return [
        lathe(
            [
                (0.0, 0.0),
                (0.07, 0.0),
                (0.08, 0.04),
                (0.04, 0.14),
                (0.012, 0.18),
                (0.012, 0.3),
                (0.0, 0.3),
            ],
            (x, y, z),
            porcelain(),
            segments=24,
        ),
        lathe(
            [(0.07, 0.24), (0.13, 0.4), (0.125, 0.4), (0.065, 0.245)],
            (x, y, z),
            shade,
            segments=24,
            closed=True,
        ),
        sphere(0.035, (x, y, z + 0.3), warm_glow(), segments=10),
    ]


# Dining room -----------------------------------------------------------------


def dining_set(rng):
    wood = oak()
    seat = mat("fabric_seat", (0.45, 0.15, 0.15), 1.0)
    w, d = 2.0, 1.0
    parts = [box((w, d, 0.05), (0, 0, 0.75), wood, 0.012)]
    parts += legs(w, d, 0.725, 0.04, wood, 0.06, square=True)
    parts.append(box((w - 0.2, 0.03, 0.08), (0, d / 2 - 0.12, 0.68), wood))
    parts.append(box((w - 0.2, 0.03, 0.08), (0, -d / 2 + 0.12, 0.68), wood))
    for x in (-0.55, 0.55):
        parts += chair(wood, seat, (x, -0.68, 0), 0.0)
        parts += chair(wood, seat, (x, 0.68, 0), math.pi)
    for x in (-0.55, 0.55):
        for y in (-0.3, 0.3):
            parts.append(cyl(0.12, 0.1, 0.015, (x, y, 0.783), porcelain(), segments=24))
    parts.append(
        lathe(
            [(0.0, 0.0), (0.06, 0.0), (0.02, 0.05), (0.015, 0.25), (0.03, 0.27), (0.0, 0.27)],
            (0, 0, 0.775),
            brass(),
            segments=20,
        )
    )
    parts.append(
        cyl(0.012, 0.012, 0.15, (0, 0, 1.12), mat("plain_wax", (0.92, 0.88, 0.76), 0.6), segments=8)
    )
    return parts


def sideboard(rng):
    wood = walnut()
    w, d, h = 1.6, 0.5, 0.9
    parts = [box((w, d, h - 0.12), (0, 0, 0.12 + (h - 0.12) / 2), wood, 0.01)]
    parts += legs(w, d, 0.12, 0.03, wood, 0.03)
    parts.append(box((w + 0.04, d + 0.03, 0.035), (0, -0.01, h), wood, 0.01))
    for i in range(3):
        x = (i - 1) * w / 3
        parts.append(box((w / 3 - 0.03, 0.02, 0.5), (x, -d / 2 - 0.005, 0.42), wood, 0.006))
        parts.append(box((w / 3 - 0.03, 0.02, 0.14), (x, -d / 2 - 0.005, 0.78), wood, 0.006))
        parts.append(sphere(0.018, (x, -d / 2 - 0.025, 0.78), brass(), segments=10))
        parts.append(sphere(0.018, (x + 0.18, -d / 2 - 0.025, 0.5), brass(), segments=10))
    parts.append(
        lathe(
            [(0.0, 0.0), (0.06, 0.0), (0.16, 0.08), (0.17, 0.1), (0.0, 0.05)],
            (-0.4, 0, h + 0.018),
            porcelain(),
            segments=28,
        )
    )
    for k in range(3):
        parts.append(
            sphere(
                0.04,
                (-0.4 + (k - 1) * 0.05, (k % 2) * 0.04, h + 0.1),
                mat("plain_apple", (0.6, 0.1, 0.08), 0.4),
                segments=12,
            )
        )
    parts.append(
        lathe(
            [(0.0, 0.0), (0.07, 0.0), (0.09, 0.15), (0.05, 0.3), (0.06, 0.34), (0.0, 0.34)],
            (0.45, 0.05, h + 0.018),
            mat("tint_glaze", (0.3, 0.45, 0.6), 0.12),
            segments=24,
        )
    )
    return parts


def china_cabinet(rng):
    wood = walnut()
    w, d, h = 1.1, 0.45, 1.95
    parts = [
        box((w, d, 0.85), (0, 0, 0.5), wood, 0.01),
        box((w, d * 0.75, 1.0), (0, d * 0.125, 1.43), wood, 0.01),
    ]
    parts.append(box((w + 0.06, d + 0.04, 0.08), (0, 0, 0.08 / 2 + 0.04), wood, 0.01))
    parts.append(box((w + 0.06, d * 0.75 + 0.05, 0.06), (0, d * 0.125, h - 0.03), wood, 0.01))
    front = -d / 2 + d * 0.25
    for x in (-1, 1):
        parts.append(box((w / 2 - 0.04, 0.02, 0.7), (x * w / 4, -d / 2 - 0.005, 0.5), wood, 0.006))
        parts.append(sphere(0.016, (x * 0.06, -d / 2 - 0.025, 0.55), brass(), segments=10))
        parts.append(box((w / 2 - 0.06, 0.01, 0.9), (x * w / 4, front - 0.005, 1.43), glass()))
        parts.append(box((0.03, 0.02, 0.94), (x * (w / 2 - 0.02), front - 0.01, 1.43), wood))
    parts.append(box((0.03, 0.02, 0.94), (0, front - 0.01, 1.43), wood))
    for z in (1.15, 1.45, 1.72):
        parts.append(box((w - 0.06, d * 0.7, 0.02), (0, d * 0.125, z), wood))
        for k in range(4):
            x = -0.36 + k * 0.24
            plate = cyl(0.09, 0.09, 0.012, (x, d * 0.32, z + 0.1), porcelain(), (1.3, 0, 0), 24)
            parts.append(plate)
    return parts


# Library and study -----------------------------------------------------------


def writing_desk(rng):
    wood = walnut()
    leather = mat("leather_green", (0.12, 0.25, 0.15), 0.6)
    w, d = 1.4, 0.7
    parts = [
        box((w, d, 0.04), (0, 0, 0.76), wood, 0.008),
        box((w - 0.2, d - 0.2, 0.005), (0, 0, 0.782), leather),
    ]
    for x in (-1, 1):
        parts.append(box((0.42, d - 0.04, 0.72), (x * (w / 2 - 0.23), 0, 0.38), wood, 0.008))
        for k in range(3):
            z = 0.15 + k * 0.22
            parts.append(
                box((0.38, 0.02, 0.19), (x * (w / 2 - 0.23), -d / 2 + 0.01, z), wood, 0.005)
            )
            parts.append(
                box((0.08, 0.02, 0.015), (x * (w / 2 - 0.23), -d / 2 - 0.005, z + 0.03), brass())
            )
    paper = mat("paper_sheet", (0.92, 0.9, 0.84), 0.9)
    for k in range(4):
        sheet_ = box(
            (0.21, 0.297, 0.002),
            (rng.uniform(-0.2, 0.1), rng.uniform(-0.15, 0.05), 0.785 + k * 0.002),
            paper,
        )
        sheet_.rotation_euler.z = rng.uniform(-0.4, 0.4)
        parts.append(sheet_)
    green = mat("glass_banker", (0.1, 0.5, 0.2), 0.1)
    parts += [
        box((0.18, 0.12, 0.02), (0.45, 0.15, 0.79), brass(), 0.005),
        cyl(0.01, 0.01, 0.3, (0.45, 0.17, 0.94), brass(), segments=8),
        sheet(0.12, 0.08, math.pi, 0.004, green, (0.45, 0.12, 1.06), "shade"),
        box((0.2, 0.04, 0.02), (0.45, 0.1, 1.06), warm_glow()),
        cyl(
            0.03,
            0.025,
            0.05,
            (-0.45, 0.2, 0.805),
            mat("glass_ink", (0.1, 0.1, 0.25), 0.05),
            segments=12,
        ),
    ]
    parts += chair(wood, leather, (0, -0.55, 0), math.pi)
    return parts


# Bedroom ---------------------------------------------------------------------


def bed_double(rng):
    return _bed(rng, 1.6, 2.1, walnut(), turned=True)


def bed_single(rng):
    return _bed(rng, 1.0, 2.0, iron(), turned=False)


def _bed(rng, w, d, frame, turned):
    sheet_ = mat("fabric_sheet", (0.88, 0.86, 0.8), 1.0)
    cover = tint_fabric((0.3, 0.35, 0.55))
    parts = []
    if turned:
        parts.append(box((w + 0.08, 0.08, 1.1), (0, d / 2 - 0.04, 0.55), frame, 0.02))
        parts.append(box((w + 0.08, 0.08, 0.6), (0, -d / 2 + 0.04, 0.3), frame, 0.02))
        for x in (-1, 1):
            parts.append(box((0.05, d - 0.1, 0.18), (x * (w / 2 + 0.015), 0, 0.3), frame, 0.01))
    else:
        for y, top in ((d / 2, 1.0), (-d / 2, 0.75)):
            for x in (-1, 1):
                parts.append(cyl(0.022, 0.022, top, (x * w / 2, y, top / 2), frame, segments=10))
            parts.append(cyl(0.015, 0.015, w, (0, y, top - 0.03), frame, (0, math.pi / 2, 0), 8))
            for k in range(5):
                x = -w / 2 + w * (k + 1) / 6
                parts.append(
                    cyl(
                        0.008, 0.008, top - 0.35, (x, y, 0.35 + (top - 0.35) / 2), frame, segments=6
                    )
                )
        for x in (-1, 1):
            parts.append(box((0.04, d, 0.05), (x * w / 2, 0, 0.32), frame))
    parts.append(box((w - 0.04, d - 0.12, 0.2), (0, 0, 0.45), sheet_, 0.06))
    parts.append(box((w + 0.02, d * 0.7, 0.06), (0, -d * 0.12, 0.56), cover, 0.03))
    for x in (-1, 1):
        parts.append(
            box((0.03, d * 0.7, 0.28), (x * (w / 2 + 0.01), -d * 0.12, 0.42), cover, 0.012)
        )
    parts.append(box((w + 0.02, 0.03, 0.28), (0, -d / 2 + 0.06, 0.42), cover, 0.012))
    pillows = [-w / 4, w / 4] if w > 1.2 else [0.0]
    for x in pillows:
        parts.append(
            cushion(
                (min(w / 2 - 0.1, 0.65), 0.38, 0.14), (x, d / 2 - 0.3, 0.62), sheet_, (0.25, 0, 0)
            )
        )
    return parts


def nightstand(rng):
    wood = walnut()
    parts = [box((0.5, 0.4, 0.5), (0, 0, 0.3), wood, 0.01)]
    parts += legs(0.5, 0.4, 0.06, 0.02, wood, 0.02)
    parts.append(box((0.44, 0.02, 0.16), (0, -0.205, 0.44), wood, 0.005))
    parts.append(sphere(0.015, (0, -0.225, 0.44), brass(), segments=10))
    parts += table_lamp((0.1, 0.05, 0.55))
    parts += book_pile((-0.12, -0.02, 0.55), rng, 2)
    return parts


def wardrobe(rng):
    wood = oak()
    w, d, h = 1.2, 0.6, 2.1
    parts = [box((w, d, h - 0.2), (0, 0, 0.1 + (h - 0.2) / 2), wood, 0.01)]
    parts.append(box((w + 0.08, d + 0.05, 0.1), (0, -0.01, h - 0.05), wood, 0.02))
    parts.append(box((w + 0.04, d + 0.02, 0.1), (0, 0, 0.05), wood, 0.02))
    for x in (-1, 1):
        parts.append(
            box((w / 2 - 0.04, 0.025, h - 0.38), (x * w / 4, -d / 2 - 0.01, h / 2), wood, 0.01)
        )
        parts.append(
            box((w / 2 - 0.16, 0.01, h - 0.7), (x * w / 4, -d / 2 - 0.025, h / 2), wood, 0.01)
        )
        parts.append(box((0.015, 0.03, 0.14), (x * 0.04, -d / 2 - 0.035, h / 2), brass(), 0.004))
    parts.append(box((w - 0.1, 0.02, 0.18), (0, -d / 2 - 0.01, 0.22), wood, 0.005))
    return parts


def vanity(rng):
    wood = oak()
    parts = [box((1.0, 0.45, 0.04), (0, 0, 0.74), wood, 0.008)]
    parts += legs(1.0, 0.45, 0.72, 0.022, wood, 0.03)
    parts.append(box((0.9, 0.02, 0.12), (0, -0.215, 0.66), wood, 0.004))
    parts.append(box((0.8, 0.04, 0.72), (0, 0.19, 1.15), wood, 0.01))
    parts.append(
        box((0.7, 0.01, 0.62), (0, 0.165, 1.15), mat("metal_mirror", (0.75, 0.78, 0.8), 0.05, 1.0))
    )
    parts.append(
        lathe(
            [(0.0, 0.0), (0.04, 0.0), (0.03, 0.08), (0.012, 0.11), (0.0, 0.11)],
            (-0.3, 0.0, 0.76),
            mat("glass_perfume", (0.85, 0.6, 0.75), 0.05),
            segments=16,
        )
    )
    parts.append(
        box((0.14, 0.1, 0.06), (0.3, 0.02, 0.79), mat("lacquer_box", (0.5, 0.1, 0.15), 0.2), 0.01)
    )
    stool = cyl(0.2, 0.2, 0.08, (0, -0.48, 0.44), tint_fabric((0.6, 0.5, 0.6)), segments=24)
    parts.append(stool)
    for k in range(3):
        a = k * 2 * math.pi / 3
        parts.append(
            cyl(
                0.015,
                0.012,
                0.42,
                (math.cos(a) * 0.14, -0.48 + math.sin(a) * 0.14, 0.2),
                wood,
                segments=8,
            )
        )
    return parts


# Office ------------------------------------------------------------------------


def office_desk(rng):
    grey = mat("metal_desk", (0.42, 0.45, 0.42), 0.5, 0.6)
    top = mat("plastic_desktop", (0.55, 0.5, 0.42), 0.5)
    beige = mat("plastic_beige", (0.78, 0.74, 0.64), 0.45)
    screen = mat("glow_screen", (0.25, 0.9, 0.45), emission=1.5)
    black = mat("plastic_black", (0.06, 0.06, 0.06), 0.4)
    w, d = 1.5, 0.75
    parts = [box((w, d, 0.04), (0, 0, 0.74), top, 0.004)]
    parts.append(box((0.45, d - 0.04, 0.72), (w / 2 - 0.25, 0, 0.36), grey, 0.006))
    for k in range(3):
        parts.append(
            box((0.41, 0.02, 0.2), (w / 2 - 0.25, -d / 2 - 0.005, 0.13 + k * 0.22), grey, 0.004)
        )
        parts.append(
            box((0.12, 0.02, 0.02), (w / 2 - 0.25, -d / 2 - 0.02, 0.18 + k * 0.22), steel())
        )
    parts.append(box((0.03, d - 0.04, 0.72), (-w / 2 + 0.04, 0, 0.36), grey, 0.004))
    parts.append(box((w - 0.5, 0.02, 0.4), (-0.2, d / 2 - 0.04, 0.5), grey))
    # A boxy CRT monitor and keyboard.
    parts += [
        box((0.4, 0.4, 0.36), (-0.15, 0.12, 0.98), beige, 0.03),
        box((0.3, 0.2, 0.26), (-0.15, 0.3, 0.95), beige, 0.04),
        box((0.31, 0.01, 0.24), (-0.15, -0.085, 0.99), screen),
        box((0.22, 0.2, 0.04), (-0.15, 0.12, 0.78), beige, 0.01),
        box((0.45, 0.16, 0.025), (-0.15, -0.22, 0.775), beige, 0.006),
        box((0.42, 0.12, 0.01), (-0.15, -0.22, 0.79), black),
    ]
    mug = cyl(
        0.04, 0.04, 0.1, (0.35, -0.1, 0.81), mat("tint_glaze", (0.3, 0.45, 0.6), 0.12), segments=16
    )
    parts.append(mug)
    parts += office_chair((-0.15, -0.6, 0))
    return parts


def office_chair(at):
    black = mat("fabric_chair", (0.12, 0.12, 0.13), 1.0)
    x, y, _ = at
    parts = [
        cushion((0.48, 0.46, 0.08), (x, y, 0.48), black),
        box((0.44, 0.07, 0.5), (x, y + 0.24, 0.82), black, 0.03),
        cyl(0.025, 0.025, 0.36, (x, y, 0.28), steel(), segments=10),
    ]
    for k in range(5):
        a = k * 2 * math.pi / 5
        tip = (x + math.cos(a) * 0.28, y + math.sin(a) * 0.28, 0.06)
        parts.append(tube([(x, y, 0.1), tip], 0.018, black, 6))
        parts.append(sphere(0.03, (tip[0], tip[1], 0.03), black, segments=8))
    return parts


def filing_cabinet(rng):
    grey = mat("metal_filing", (0.45, 0.5, 0.47), 0.45, 0.6)
    w, d, h = 0.5, 0.65, 1.32
    parts = [box((w, d, h), (0, 0, h / 2), grey, 0.008)]
    for k in range(4):
        z = 0.17 + k * 0.32
        parts.append(box((w - 0.04, 0.02, 0.3), (0, -d / 2 - 0.005, z), grey, 0.006))
        parts.append(box((0.14, 0.03, 0.025), (0, -d / 2 - 0.025, z + 0.06), steel(), 0.004))
        parts.append(
            box(
                (0.07, 0.01, 0.04),
                (0, -d / 2 - 0.015, z + 0.1),
                mat("paper_tag", (0.9, 0.88, 0.8), 0.9),
            )
        )
    parts.append(
        box((0.3, 0.38, 0.12), (0.0, 0.05, h + 0.06), mat("paper_box", (0.6, 0.5, 0.35), 0.9), 0.01)
    )
    return parts


def water_cooler(rng):
    white = mat("plastic_white", (0.86, 0.86, 0.84), 0.4)
    water = mat("glass_water", (0.5, 0.75, 0.95), 0.05)
    parts = [box((0.32, 0.32, 0.95), (0, 0, 0.475), white, 0.03)]
    parts.append(
        lathe(
            [
                (0.0, 0.0),
                (0.13, 0.0),
                (0.14, 0.05),
                (0.14, 0.32),
                (0.05, 0.4),
                (0.04, 0.45),
                (0.0, 0.45),
            ],
            (0, 0, 0.95),
            water,
            segments=24,
        )
    )
    parts.append(
        box((0.06, 0.04, 0.04), (-0.06, -0.17, 0.7), mat("plastic_blue", (0.2, 0.35, 0.8), 0.4))
    )
    parts.append(
        box((0.06, 0.04, 0.04), (0.06, -0.17, 0.7), mat("plastic_red", (0.8, 0.15, 0.1), 0.4))
    )
    return parts


def metal_shelf(rng):
    rack = mat("metal_rack", (0.35, 0.38, 0.4), 0.5, 0.7)
    card = mat("paper_box", (0.6, 0.5, 0.35), 0.9)
    w, d, h = 1.2, 0.45, 1.9
    parts = []
    for x in (-1, 1):
        for y in (-1, 1):
            parts.append(
                box((0.035, 0.035, h), (x * (w / 2 - 0.02), y * (d / 2 - 0.02), h / 2), rack)
            )
    for z in (0.1, 0.55, 1.0, 1.45, 1.88):
        parts.append(box((w, d, 0.02), (0, 0, z), rack, 0.004))
    for z in (0.11, 0.56, 1.01, 1.46):
        x = -w / 2 + 0.05
        while x < w / 2 - 0.2:
            kind = rng.random()
            if kind < 0.45:
                bw, bh = rng.uniform(0.25, 0.4), rng.uniform(0.18, 0.35)
                parts.append(box((bw, d - 0.08, bh), (x + bw / 2, 0, z + bh / 2), card, 0.01))
                x += bw + 0.03
            elif kind < 0.75:
                for _ in range(rng.randint(3, 6)):
                    colour = rng.randrange(len(BOOK_COLOURS))
                    binder = mat(f"plastic_binder{colour}", BOOK_COLOURS[colour], 0.5)
                    parts.append(
                        box((0.06, 0.28, 0.32), (x + 0.03, -0.02, z + 0.16), binder, 0.004)
                    )
                    x += 0.065
                x += 0.05
            else:
                x += rng.uniform(0.1, 0.3)
    return parts


# Kitchen -------------------------------------------------------------------------


def kitchen_counter(rng):
    wood = pine()
    top = mat("stone_counter", (0.3, 0.3, 0.32), 0.3)
    w, d = 1.8, 0.62
    parts = [box((w, d - 0.03, 0.82), (0, 0.015, 0.41), wood, 0.006)]
    parts.append(box((w + 0.02, d + 0.02, 0.05), (0, 0, 0.865), top, 0.008))
    parts.append(
        box((w, 0.05, 0.08), (0, -d / 2 + 0.06, 0.04), mat("plain_kick", (0.1, 0.08, 0.06), 0.9))
    )
    for i in range(3):
        x = (i - 1) * w / 3
        parts.append(box((w / 3 - 0.03, 0.02, 0.5), (x, -d / 2 + 0.015, 0.36), wood, 0.008))
        parts.append(box((w / 3 - 0.03, 0.02, 0.16), (x, -d / 2 + 0.015, 0.73), wood, 0.008))
        parts.append(box((0.12, 0.02, 0.015), (x, -d / 2, 0.73), steel()))
        parts.append(box((0.015, 0.02, 0.1), (x + 0.2, -d / 2, 0.52), steel()))
    basin = (-0.4, 0.0, 0.89)
    parts.append(box((0.55, 0.42, 0.012), (basin[0], basin[1], basin[2] - 0.005), steel(), 0.004))
    parts.append(
        box(
            (0.48, 0.36, 0.01),
            (basin[0], basin[1], basin[2] - 0.0),
            mat("plain_drain", (0.12, 0.12, 0.13), 0.4),
        )
    )
    parts.append(
        tube(
            [
                (basin[0], 0.25, 0.89),
                (basin[0], 0.25, 1.15),
                (basin[0], 0.12, 1.2),
                (basin[0], 0.08, 1.12),
            ],
            0.015,
            steel(),
            8,
        )
    )
    for k in range(3):
        parts.append(
            cyl(
                0.11,
                0.1,
                0.012,
                (0.4 + rng.uniform(-0.02, 0.02), 0.0, 0.9 + k * 0.013),
                porcelain(),
                segments=24,
            )
        )
    parts.append(
        box((0.3, 0.22, 0.02), (0.65, 0.12, 0.9), mat("wood_board", (0.6, 0.45, 0.28), 0.7), 0.005)
    )
    return parts


def stove(rng):
    enamel = mat("glaze_enamel", (0.85, 0.83, 0.76), 0.2)
    black = mat("plain_black", (0.04, 0.04, 0.04), 0.5)
    w, d = 0.8, 0.66
    parts = [box((w, d, 0.9), (0, 0, 0.45), enamel, 0.02)]
    parts.append(box((w, 0.08, 0.25), (0, d / 2 - 0.04, 1.02), enamel, 0.01))
    parts.append(box((w - 0.12, 0.03, 0.5), (0, -d / 2 - 0.01, 0.38), enamel, 0.015))
    parts.append(
        box(
            (w - 0.3, 0.01, 0.2),
            (0, -d / 2 - 0.03, 0.45),
            mat("glass_oven", (0.15, 0.12, 0.1), 0.05),
        )
    )
    parts.append(
        cyl(0.012, 0.012, w - 0.2, (0, -d / 2 - 0.07, 0.68), steel(), (0, math.pi / 2, 0), 8)
    )
    for x in (-1, 1):
        parts.append(box((0.02, 0.05, 0.02), (x * 0.28, -d / 2 - 0.045, 0.68), steel()))
    for k in range(5):
        parts.append(
            cyl(
                0.022,
                0.022,
                0.03,
                (-0.3 + k * 0.15, -d / 2 - 0.01, 0.82),
                black,
                (math.pi / 2, 0, 0),
                12,
            )
        )
    for x in (-0.18, 0.18):
        for y in (-0.15, 0.13):
            parts.append(torus(0.08, 0.012, (x, y, 0.905), black, segments=20))
            parts.append(cyl(0.04, 0.04, 0.012, (x, y, 0.905), black, segments=12))
    pot = lathe(
        [
            (0.0, 0.0),
            (0.12, 0.0),
            (0.13, 0.02),
            (0.13, 0.16),
            (0.12, 0.16),
            (0.12, 0.02),
            (0.0, 0.02),
        ],
        (-0.18, -0.15, 0.915),
        iron(),
        segments=28,
    )
    parts.append(pot)
    parts.append(box((0.12, 0.03, 0.02), (-0.18 - 0.19, -0.15, 1.06), iron()))
    return parts


def fridge(rng):
    white = mat("glaze_fridge", (0.88, 0.87, 0.82), 0.2)
    w, d, h = 0.78, 0.72, 1.82
    parts = [box((w, d, h - 0.06), (0, 0, 0.06 + (h - 0.06) / 2), white, 0.08)]
    parts.append(
        box((w - 0.04, 0.03, 0.01), (0, -d / 2, 1.2), mat("plain_seam", (0.3, 0.3, 0.3), 0.6))
    )
    for z0, z1 in ((1.3, 1.6), (0.6, 1.05)):
        parts.append(
            tube(
                [
                    (w / 2 - 0.08, -d / 2, z0),
                    (w / 2 - 0.08, -d / 2 - 0.05, z0 + 0.03),
                    (w / 2 - 0.08, -d / 2 - 0.05, z1 - 0.03),
                    (w / 2 - 0.08, -d / 2, z1),
                ],
                0.014,
                steel(),
                8,
            )
        )
    parts.append(
        box((w - 0.1, d - 0.1, 0.06), (0, 0, 0.03), mat("plain_black", (0.04, 0.04, 0.04), 0.5))
    )
    parts.append(
        box(
            (0.08, 0.005, 0.08),
            (-0.1, -d / 2 - 0.002, 1.5),
            mat("paper_note", (0.95, 0.85, 0.4), 0.9),
        )
    )
    return parts


def kitchen_table(rng):
    wood = pine()
    cloth = mat("fabric_check", (0.7, 0.2, 0.18), 1.0)
    parts = [box((1.2, 0.8, 0.04), (0, 0, 0.74), wood, 0.008)]
    parts += legs(1.2, 0.8, 0.72, 0.03, wood, 0.05, square=True)
    parts.append(box((0.5, 0.5, 0.004), (0.1, 0.0, 0.762), cloth))
    for x in (-0.3, 0.3):
        parts += chair(wood, wood, (x, -0.58, 0), 0.0)
    parts += chair(wood, wood, (0.32, 0.62, 0), math.pi + 0.3)  # Pushed back askew.
    parts += chair(wood, wood, (-0.3, 0.58, 0), math.pi)
    parts.append(
        lathe(
            [(0.0, 0.0), (0.05, 0.0), (0.06, 0.12), (0.035, 0.18), (0.0, 0.18)],
            (0.1, 0.0, 0.762),
            glass(),
            segments=16,
        )
    )
    return parts


# Laboratory ----------------------------------------------------------------------


def workbench(rng):
    wood = pine()
    peg = mat("wood_pegboard", (0.62, 0.5, 0.36), 0.8)
    w, d = 1.8, 0.75
    parts = [
        box((w, d, 0.07), (0, 0, 0.9), wood, 0.01),
        box((w - 0.1, d - 0.1, 0.03), (0, 0, 0.2), wood),
    ]
    parts += legs(w, d, 0.865, 0.04, wood, 0.03, square=True)
    parts.append(box((w, 0.03, 0.75), (0, d / 2 - 0.015, 1.3), peg))
    for k in range(10):  # Tools hung on the board.
        x = -w / 2 + 0.15 + k * 0.16
        z = 1.25 + rng.uniform(-0.1, 0.25)
        if k % 3 == 0:
            parts.append(box((0.03, 0.02, 0.25), (x, d / 2 - 0.05, z), wood, 0.005))
            parts.append(box((0.1, 0.03, 0.04), (x, d / 2 - 0.05, z + 0.13), iron(), 0.005))
        elif k % 3 == 1:
            parts.append(torus(0.05, 0.008, (x, d / 2 - 0.05, z), steel(), (math.pi / 2, 0, 0), 16))
        else:
            parts.append(box((0.03, 0.015, 0.22), (x, d / 2 - 0.05, z), steel(), 0.004))
    vise = (w / 2 - 0.2, -d / 2 + 0.1, 0.94)
    parts.append(box((0.18, 0.2, 0.1), vise, iron(), 0.01))
    parts.append(
        cyl(
            0.012,
            0.012,
            0.3,
            (vise[0], vise[1] - 0.15, vise[2] + 0.02),
            steel(),
            (math.pi / 2, 0, 0),
            8,
        )
    )
    parts += jar((-0.5, 0.15, 0.935), 0.05, 0.14, (0.3, 0.9, 0.4), rng)
    parts += jar((-0.36, 0.2, 0.935), 0.04, 0.1, (0.9, 0.5, 0.1), rng)
    parts.append(
        box((0.4, 0.25, 0.015), (0.0, -0.05, 0.94), mat("paper_plans", (0.3, 0.4, 0.7), 0.9))
    )
    return parts


def specimen_tank(rng):
    fluid = mat("glow_fluid", (0.35, 0.95, 0.5), emission=1.2)
    thing = mat("flesh_specimen", (0.45, 0.4, 0.35), 0.5)
    r, h = 0.33, 1.95
    parts = [
        cyl(0.4, 0.4, 0.28, (0, 0, 0.14), steel(), segments=32),
        cyl(0.4, 0.38, 0.2, (0, 0, h - 0.1), steel(), segments=32),
        cyl(r, r, h - 0.48, (0, 0, 0.28 + (h - 0.48) / 2), glass(), segments=32),
        cyl(r - 0.01, r - 0.01, h - 0.62, (0, 0, 0.28 + (h - 0.62) / 2), fluid, segments=32),
    ]
    creature = blob(
        [
            ((0, 0, 1.15), 0.12),
            ((0, 0.02, 1.1), (0, 0.06, 0.75), 0.1),
            ((-0.05, -0.04, 0.75), (-0.08, -0.1, 0.55), 0.05),
            ((0.05, -0.04, 0.75), (0.1, -0.06, 0.5), 0.05),
            ((-0.08, -0.05, 1.0), (-0.15, -0.1, 0.85), 0.035),
            ((0.08, -0.05, 1.0), (0.13, -0.12, 1.1), 0.035),
        ],
        thing,
        name="specimen",
    )
    parts.append(creature)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        parts.append(
            cyl(
                0.02,
                0.02,
                h - 0.48,
                (math.cos(a) * 0.36, math.sin(a) * 0.36, 0.28 + (h - 0.48) / 2),
                steel(),
                segments=8,
            )
        )
    parts.append(
        tube([(0.2, 0.25, h), (0.2, 0.3, h + 0.15), (0.0, 0.38, h + 0.2)], 0.035, iron(), 10)
    )
    for k in range(3):
        parts.append(
            sphere(
                0.02,
                (0.1 * k - 0.1, -0.15, 0.4 + k * 0.5),
                mat("glass_bubble", (0.9, 1.0, 0.9), 0.05),
                segments=8,
            )
        )
    return parts


def lab_shelf(rng):
    rack = mat("metal_rack", (0.35, 0.38, 0.4), 0.5, 0.7)
    w, d, h = 1.2, 0.4, 1.8
    parts = []
    for x in (-1, 1):
        for y in (-1, 1):
            parts.append(
                box((0.03, 0.03, h), (x * (w / 2 - 0.02), y * (d / 2 - 0.02), h / 2), rack)
            )
    colours = [
        (0.3, 0.9, 0.4),
        (0.9, 0.3, 0.2),
        (0.3, 0.5, 0.95),
        (0.95, 0.8, 0.2),
        (0.7, 0.3, 0.9),
    ]
    for z in (0.1, 0.55, 1.0, 1.45):
        parts.append(box((w, d, 0.02), (0, 0, z), rack, 0.004))
        x = -w / 2 + 0.08
        while x < w / 2 - 0.08:
            r = rng.uniform(0.03, 0.06)
            hj = rng.uniform(0.1, 0.25)
            parts += jar(
                (x + r, rng.uniform(-0.08, 0.08), z + 0.01), r, hj, rng.choice(colours), rng
            )
            x += 2 * r + rng.uniform(0.02, 0.08)
    parts.append(box((w, d, 0.02), (0, 0, h - 0.01), rack, 0.004))
    return parts


def gurney(rng):
    sheet_ = mat("fabric_sheet", (0.85, 0.85, 0.8), 1.0)
    length, w = 2.0, 0.7
    parts = [
        box((length, w, 0.06), (0, 0, 0.78), steel(), 0.01),
        box(
            (length - 0.1, w - 0.1, 0.08),
            (0, 0, 0.84),
            mat("fabric_pad", (0.3, 0.4, 0.45), 0.8),
            0.03,
        ),
    ]
    for x in (-1, 1):
        for y in (-1, 1):
            parts.append(
                cyl(
                    0.02,
                    0.02,
                    0.68,
                    (x * (length / 2 - 0.08), y * (w / 2 - 0.06), 0.42),
                    steel(),
                    segments=8,
                )
            )
            parts.append(
                sphere(
                    0.045,
                    (x * (length / 2 - 0.08), y * (w / 2 - 0.06), 0.045),
                    mat("plastic_black", (0.06, 0.06, 0.06), 0.4),
                    segments=10,
                )
            )
    shape = blob(
        [
            ((-0.65, 0, 0.98), 0.13),
            ((-0.45, 0, 0.94), (0.25, 0, 0.95), 0.17),
            ((0.25, 0.09, 0.92), (0.85, 0.08, 0.9), 0.07),
            ((0.25, -0.09, 0.92), (0.85, -0.08, 0.9), 0.07),
            ((0.9, 0.08, 0.95), 0.05),
            ((0.9, -0.08, 0.95), 0.05),
        ],
        sheet_,
        resolution=0.03,
        name="covered",
    )
    parts.append(shape)
    parts.append(box((length - 0.05, w - 0.02, 0.02), (0, 0, 0.885), sheet_, 0.005))
    parts.append(box((length - 0.2, 0.01, 0.2), (0, -w / 2 - 0.01, 0.78), sheet_))  # Hanging edge.
    return parts


def server_rack(rng):
    black = mat("metal_rackcase", (0.1, 0.1, 0.11), 0.4, 0.5)
    face = mat("plastic_panel", (0.2, 0.2, 0.22), 0.5)
    lights = [
        mat("glow_led_g", (0.2, 1.0, 0.3), emission=3.0),
        mat("glow_led_r", (1.0, 0.2, 0.15), emission=3.0),
        mat("glow_led_a", (1.0, 0.7, 0.1), emission=3.0),
    ]
    w, d, h = 0.62, 0.9, 2.0
    parts = [box((w, d, h), (0, 0, h / 2), black, 0.01)]
    z = 0.15
    while z < h - 0.2:
        unit = rng.choice((0.09, 0.09, 0.18, 0.27))
        parts.append(
            box((w - 0.08, 0.02, unit - 0.01), (0, -d / 2 - 0.005, z + unit / 2), face, 0.003)
        )
        for k in range(rng.randint(2, 7)):
            parts.append(
                box(
                    (0.012, 0.01, 0.012),
                    (-w / 2 + 0.08 + k * 0.03, -d / 2 - 0.016, z + unit / 2),
                    rng.choice(lights),
                )
            )
        z += unit + 0.005
    return parts


# Bathroom --------------------------------------------------------------------------


def toilet(rng):
    white = porcelain()
    parts = [
        lathe(
            [(0.0, 0.0), (0.12, 0.0), (0.1, 0.15), (0.16, 0.38), (0.0, 0.38)],
            (0, -0.1, 0),
            white,
            segments=28,
        ),
        torus(0.15, 0.025, (0, -0.12, 0.41), white, segments=28),
        box((0.38, 0.2, 0.36), (0, 0.22, 0.58), white, 0.03),
        box((0.4, 0.22, 0.04), (0, 0.22, 0.78), white, 0.01),
        box((0.06, 0.02, 0.02), (-0.12, 0.11, 0.72), steel()),
    ]
    parts[0].scale = (1.0, 1.25, 1.0)
    parts[1].scale = (1.0, 1.25, 1.0)
    return parts


def bath_sink(rng):
    white = porcelain()
    return [
        lathe(
            [(0.0, 0.0), (0.12, 0.0), (0.08, 0.05), (0.07, 0.6), (0.12, 0.72), (0.0, 0.72)],
            (0, 0.05, 0),
            white,
            segments=28,
        ),
        box((0.6, 0.45, 0.15), (0, 0.0, 0.8), white, 0.05),
        box((0.48, 0.3, 0.02), (0, -0.02, 0.875), mat("plain_drain", (0.12, 0.12, 0.13), 0.4)),
        tube(
            [(0, 0.18, 0.87), (0, 0.18, 0.98), (0, 0.08, 1.0), (0, 0.06, 0.95)], 0.012, steel(), 8
        ),
        sphere(0.025, (-0.1, 0.18, 0.9), steel(), segments=10),
        sphere(0.025, (0.1, 0.18, 0.9), steel(), segments=10),
    ]


def bathtub(rng):
    white = porcelain()
    tub = lathe(
        [
            (0.0, 0.12),
            (0.3, 0.12),
            (0.38, 0.4),
            (0.4, 0.62),
            (0.36, 0.62),
            (0.34, 0.42),
            (0.27, 0.2),
            (0.0, 0.2),
        ],
        (0, 0, 0),
        white,
        segments=40,
    )
    tub.scale = (2.1, 1.0, 1.0)
    parts = [tub]
    for x in (-1, 1):
        for y in (-1, 1):
            parts.append(
                blob(
                    [((x * 0.6, y * 0.26, 0.14), (x * 0.65, y * 0.3, 0.03), 0.035)],
                    brass(),
                    resolution=0.01,
                    name="foot",
                )
            )
    parts.append(
        tube(
            [(-0.78, 0.0, 0.6), (-0.78, 0.0, 0.75), (-0.7, 0.0, 0.78), (-0.66, 0.0, 0.72)],
            0.014,
            brass(),
            8,
        )
    )
    return parts


# Storage --------------------------------------------------------------------------


def box_stack(rng):
    card = mat("paper_box", (0.6, 0.5, 0.35), 0.9)
    tape = mat("plastic_tape", (0.7, 0.6, 0.4), 0.4)
    parts = []
    z = 0.0
    for level in range(3):
        bw, bd, bh = rng.uniform(0.5, 0.8), rng.uniform(0.45, 0.7), rng.uniform(0.3, 0.45)
        at = (rng.uniform(-0.1, 0.1), rng.uniform(-0.05, 0.05), z + bh / 2)
        b = box((bw, bd, bh), at, card, 0.01)
        b.rotation_euler.z = rng.uniform(-0.2, 0.2)
        t = box((bw * 1.001, 0.06, bh * 1.001), at, tape)
        t.rotation_euler.z = b.rotation_euler.z
        parts += [b, t]
        if level == 0:
            side = box((0.45, 0.4, 0.35), (0.62, 0.0, 0.175), card, 0.01)
            side.rotation_euler.z = rng.uniform(-0.3, 0.3)
            parts.append(side)
        z += bh
    return parts


def barrel(rng):
    wood = mat("wood_barrel", (0.45, 0.3, 0.17), 0.8)
    profile = [
        (0.0, 0.0),
        (0.26, 0.0),
        (0.3, 0.2),
        (0.31, 0.45),
        (0.3, 0.7),
        (0.26, 0.9),
        (0.0, 0.9),
    ]
    parts = [lathe(profile, material=wood, segments=24, smooth=False)]
    for z, r in ((0.08, 0.275), (0.3, 0.307), (0.6, 0.307), (0.82, 0.275)):
        parts.append(torus(r, 0.012, (0, 0, z), iron(), segments=32))
    keg = [(0.0, 0.0), (0.17, 0.0), (0.2, 0.15), (0.2, 0.3), (0.17, 0.45), (0.0, 0.45)]
    parts.append(lathe(keg, (0.42, 0.12, 0.0), wood, segments=20, smooth=False))  # A smaller keg.
    return parts


def mop_bucket(rng):
    yellow = mat("plastic_yellow", (0.85, 0.7, 0.1), 0.4)
    water = mat("glass_murky", (0.35, 0.33, 0.25), 0.05)
    mop = mat("fabric_mop", (0.75, 0.72, 0.62), 1.0)
    parts = [
        lathe(
            [(0.0, 0.0), (0.16, 0.0), (0.19, 0.32), (0.18, 0.32), (0.15, 0.03), (0.0, 0.03)],
            material=yellow,
            segments=24,
        ),
        cyl(0.165, 0.165, 0.01, (0, 0, 0.22), water, segments=24),
        tube([(-0.18, 0, 0.3), (0, 0, 0.45), (0.18, 0, 0.3)], 0.008, steel(), 6),
        cyl(
            0.015,
            0.015,
            1.25,
            (0.05, 0.05, 0.75),
            mat("wood_handle", (0.6, 0.45, 0.28), 0.7),
            (0.12, -0.08, 0),
            8,
        ),
    ]
    for k in range(10):
        a = k * 2 * math.pi / 10
        parts.append(
            tube(
                [
                    (0.0, 0.0, 0.18),
                    (math.cos(a) * 0.08, math.sin(a) * 0.08, 0.1),
                    (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.05),
                ],
                0.012,
                mop,
                5,
            )
        )
    return parts


def sacks(rng):
    burlap = mat("fabric_burlap", (0.55, 0.45, 0.3), 1.0)
    parts = []
    spots = [(-0.22, 0.0, 0.0), (0.22, 0.05, 0.0), (0.0, 0.02, 0.36)]
    for x, y, z in spots:
        s = blob(
            [((x, y, z + 0.18), 0.2), ((x, y, z + 0.32), 0.12), ((x + 0.05, y, z + 0.1), 0.17)],
            burlap,
            resolution=0.035,
            name="sack",
        )
        parts.append(s)
        parts.append(
            torus(
                0.05,
                0.012,
                (x, y, z + 0.42),
                mat("fabric_twine", (0.4, 0.33, 0.2), 1.0),
                segments=12,
            )
        )
    return parts


# Hallway ----------------------------------------------------------------------------


def bench(rng):
    wood = oak()
    parts = [box((1.4, 0.42, 0.05), (0, 0, 0.45), wood, 0.01)]
    parts += legs(1.4, 0.42, 0.425, 0.03, wood, 0.04, square=True)
    parts.append(box((1.3, 0.03, 0.06), (0, 0, 0.15), wood))
    parts.append(cushion((1.3, 0.38, 0.06), (0, 0, 0.5), tint_fabric((0.3, 0.35, 0.25))))
    return parts


def coat_rack(rng):
    wood = walnut()
    coat = [
        mat("fabric_coat0", (0.25, 0.2, 0.16), 1.0),
        mat("fabric_coat1", (0.18, 0.2, 0.25), 1.0),
    ]
    parts = [
        lathe(
            [
                (0.0, 0.0),
                (0.22, 0.0),
                (0.2, 0.03),
                (0.03, 0.06),
                (0.025, 1.75),
                (0.045, 1.8),
                (0.0, 1.82),
            ],
            material=wood,
            segments=24,
        )
    ]
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        parts.append(
            tube(
                [
                    (0, 0, 1.62),
                    (math.cos(a) * 0.16, math.sin(a) * 0.16, 1.66),
                    (math.cos(a) * 0.2, math.sin(a) * 0.2, 1.74),
                ],
                0.012,
                wood,
                6,
            )
        )
    for k, a in enumerate((0.4, 0.4 + math.pi)):
        x, y = math.cos(a) * 0.17, math.sin(a) * 0.17
        hang = blob(
            [((x, y, 1.6), (x * 1.3, y * 1.3, 0.8), 0.1), ((x * 1.2, y * 1.2, 1.1), 0.13)],
            coat[k],
            resolution=0.035,
            name="coat",
        )
        parts.append(hang)
    parts.append(
        lathe(
            [(0.0, 0.0), (0.17, 0.0), (0.17, 0.01), (0.1, 0.02), (0.09, 0.12), (0.0, 0.13)],
            (math.cos(2.0) * 0.2, math.sin(2.0) * 0.2, 1.74),
            mat("fabric_hat", (0.1, 0.1, 0.1), 1.0),
            segments=24,
        )
    )
    return parts


def umbrella_stand(rng):
    parts = [
        lathe(
            [
                (0.0, 0.0),
                (0.13, 0.0),
                (0.12, 0.6),
                (0.13, 0.62),
                (0.11, 0.62),
                (0.1, 0.03),
                (0.0, 0.03),
            ],
            material=mat("tint_glaze", (0.25, 0.3, 0.45), 0.15),
            segments=24,
        )
    ]
    for k, colour in enumerate(((0.1, 0.1, 0.1), (0.5, 0.1, 0.1))):
        cloth = mat(f"fabric_brolly{k}", colour, 0.8)
        x = (k - 0.5) * 0.08
        parts.append(cyl(0.035, 0.01, 0.6, (x, 0, 0.55), cloth, (0, (k - 0.5) * 0.2, 0), 8))
        parts.append(
            tube(
                [(x, 0, 0.85), (x, 0, 0.92), (x + 0.04, 0, 0.95), (x + 0.06, 0, 0.92)],
                0.008,
                walnut(),
                6,
            )
        )
    return parts


def console_table(rng):
    wood = walnut()
    parts = [
        box((1.2, 0.38, 0.04), (0, 0, 0.82), wood, 0.008),
        box((1.1, 0.3, 0.1), (0, 0, 0.75), wood, 0.005),
    ]
    parts += legs(1.2, 0.38, 0.8, 0.02, wood, 0.03)
    parts.append(box((1.1, 0.3, 0.02), (0, 0, 0.15), wood))
    parts.append(
        lathe(
            [(0.0, 0.0), (0.07, 0.0), (0.11, 0.1), (0.06, 0.25), (0.08, 0.3), (0.0, 0.3)],
            (-0.35, 0.02, 0.84),
            mat("tint_glaze", (0.6, 0.2, 0.2), 0.12),
            segments=24,
        )
    )
    parts.append(
        lathe(
            [(0.0, 0.0), (0.05, 0.0), (0.14, 0.05), (0.15, 0.06), (0.0, 0.03)],
            (0.3, 0.0, 0.84),
            brass(),
            segments=24,
        )
    )
    for k in range(3):
        parts.append(sphere(0.012, (0.3 + (k - 1) * 0.03, 0.0, 0.88), brass(), segments=8))
    return parts


def radiator(rng):
    paint = mat("metal_radiator", (0.75, 0.74, 0.7), 0.4, 0.4)
    parts = []
    for k in range(14):
        x = -0.45 + k * 0.07
        parts.append(box((0.05, 0.14, 0.55), (x, 0, 0.38), paint, 0.02))
    for z in (0.12, 0.64):
        parts.append(cyl(0.02, 0.02, 0.98, (0, 0, z), paint, (0, math.pi / 2, 0), 10))
    parts.append(cyl(0.015, 0.015, 0.12, (0.5, 0.0, 0.06), steel(), segments=8))
    return parts


# Rugs ---------------------------------------------------------------------------------


def rug_persian(rng):
    field = tint_fabric((0.5, 0.12, 0.1))
    border = mat("fabric_border", (0.15, 0.12, 0.25), 1.0)
    gold = mat("fabric_gold", (0.75, 0.6, 0.3), 1.0)
    w, d = 2.6, 1.8
    parts = [
        box((w, d, 0.008), (0, 0, 0.004), border),
        box((w - 0.24, d - 0.24, 0.01), (0, 0, 0.005), field),
    ]
    parts.append(box((w - 0.14, d - 0.14, 0.009), (0, 0, 0.0045), gold))
    medallion = cyl(0.42, 0.42, 0.012, (0, 0, 0.006), border, segments=8)
    medallion.scale = (1.4, 1.0, 1.0)
    parts.append(medallion)
    parts.append(cyl(0.25, 0.25, 0.014, (0, 0, 0.007), gold, segments=8))
    for x in (-1, 1):
        for y in (-1, 1):
            parts.append(
                cyl(
                    0.12,
                    0.12,
                    0.012,
                    (x * (w / 2 - 0.35), y * (d / 2 - 0.3), 0.006),
                    border,
                    segments=4,
                )
            )
        for k in range(18):
            parts.append(
                box(
                    (0.008, 0.06, 0.004),
                    (x * (w / 2 + 0.03), -d / 2 + 0.05 + k * (d - 0.1) / 17, 0.002),
                    gold,
                    rot=(0, 0, math.pi / 2),
                )
            )
    return parts


def rug_round(rng):
    parts = []
    colours = [(0.3, 0.38, 0.5), (0.7, 0.62, 0.45), (0.3, 0.38, 0.5), (0.5, 0.2, 0.18)]
    for k, colour in enumerate(colours):
        r = 1.0 - k * 0.2
        parts.append(
            cyl(
                r,
                r,
                0.008 + k * 0.001,
                (0, 0, 0.004 + k * 0.0005),
                mat(f"fabric_ring{k}", colour, 1.0),
                segments=48,
            )
        )
    return parts


def runner(rng):
    field = tint_fabric((0.4, 0.15, 0.15))
    edge = mat("fabric_border", (0.15, 0.12, 0.25), 1.0)
    parts = [
        box((0.9, 3.0, 0.008), (0, 0, 0.004), edge),
        box((0.7, 2.8, 0.01), (0, 0, 0.005), field),
    ]
    for k in range(5):
        diamond = cyl(0.18, 0.18, 0.012, (0, -1.1 + k * 0.55, 0.006), edge, segments=4)
        diamond.scale = (0.8, 1.2, 1)
        parts.append(diamond)
    return parts


# On the walls -------------------------------------------------------------------------


def framed_picture(rng):
    frame = mat("wood_frame", (0.3, 0.2, 0.12), 0.5)
    w, h = 0.9, 0.65
    parts = [
        box((w, 0.05, h), (0, 0, h / 2), frame, 0.012),
        box((w - 0.12, 0.01, h - 0.12), (0, -0.026, h / 2), mat("canvas", (0.5, 0.5, 0.5), 0.9)),
    ]
    return parts


def portrait(rng):
    gold = mat("metal_gold", (0.85, 0.66, 0.2), 0.3, 1.0)
    dark = mat("plain_portrait", (0.08, 0.07, 0.06), 0.9)
    face = mat("plain_face", (0.7, 0.55, 0.42), 0.8)
    coat = mat("plain_coat", (0.1, 0.1, 0.12), 0.9)
    ring = torus(0.3, 0.035, (0, 0, 0.4), gold, (math.pi / 2, 0, 0), 40)
    ring.scale = (0.8, 1.0, 1.0)
    back = cyl(0.3, 0.3, 0.03, (0, 0.005, 0.4), dark, (math.pi / 2, 0, 0), 40)
    back.scale = (0.8, 1.0, 1.0)
    parts = [ring, back]
    parts.append(sphere(0.08, (0, -0.012, 0.47), face, (0.8, 0.15, 1.0), segments=16))
    parts.append(sphere(0.18, (0, -0.012, 0.22), coat, (1.0, 0.12, 0.6), segments=16))
    for x in (-0.025, 0.025):
        parts.append(
            sphere(
                0.008,
                (x, -0.025, 0.49),
                mat("glow_eyes", (0.9, 0.85, 0.6), emission=0.6),
                segments=6,
            )
        )
    return parts


def mirror(rng):
    frame = mat("metal_gold", (0.85, 0.66, 0.2), 0.3, 1.0)
    glass_ = mat("metal_mirror", (0.75, 0.78, 0.8), 0.05, 1.0)
    parts = [
        box((0.6, 0.04, 0.9), (0, 0, 0.45), frame, 0.015),
        box((0.5, 0.01, 0.8), (0, -0.02, 0.45), glass_),
    ]
    parts.append(sphere(0.05, (0, -0.01, 0.92), frame, (1.6, 0.4, 1.0), segments=12))
    return parts


def wall_clock(rng):
    wood = walnut()
    face = mat("paper_dial", (0.93, 0.9, 0.8), 0.6)
    black = mat("plain_black", (0.03, 0.03, 0.03), 0.4)
    rot = (math.pi / 2, 0, 0)
    parts = [
        cyl(0.2, 0.2, 0.06, (0, 0, 0.2), wood, rot, 40),
        cyl(0.17, 0.17, 0.01, (0, -0.03, 0.2), face, rot, 40),
    ]
    for k in range(12):
        a = k * math.pi / 6
        parts.append(
            box(
                (0.008, 0.005, 0.025),
                (math.sin(a) * 0.145, -0.036, 0.2 + math.cos(a) * 0.145),
                black,
                rot=(0, a, 0),
            )
        )
    parts.append(box((0.01, 0.005, 0.1), (0.02, -0.04, 0.24), black, rot=(0, 0.4, 0)))
    parts.append(box((0.008, 0.005, 0.13), (-0.04, -0.042, 0.18), black, rot=(0, 2.1, 0)))
    return parts


def wall_shelf(rng):
    wood = oak()
    parts = [box((1.0, 0.24, 0.03), (0, 0, 0.0 + 0.1), wood, 0.005)]
    for x in (-0.35, 0.35):
        parts.append(box((0.03, 0.2, 0.1), (x, 0.0, 0.05), iron(), 0.004))
    parts += books(-0.45, 0.05, 0.0, 0.115, 0.2, rng, 0.25)
    parts += jar((0.2, 0.0, 0.115), 0.045, 0.14, (0.8, 0.5, 0.2), rng)
    parts += jar((0.35, 0.02, 0.115), 0.035, 0.1, (0.4, 0.7, 0.3), rng)
    return parts


def antlers(rng):
    wood = walnut()
    bone = mat("bone", (0.78, 0.72, 0.6), 0.7)
    parts = [box((0.3, 0.04, 0.4), (0, 0.03, 0.2), wood, 0.03)]
    parts.append(
        blob(
            [((0, -0.02, 0.22), 0.06), ((0, -0.08, 0.24), (0, -0.16, 0.16), 0.04)],
            mat("fabric_hide", (0.4, 0.28, 0.18), 1.0),
            resolution=0.02,
            name="head",
        )
    )
    for x in (-1, 1):
        beam = [
            (x * 0.05, -0.04, 0.3),
            (x * 0.15, -0.06, 0.42),
            (x * 0.3, -0.04, 0.52),
            (x * 0.34, -0.02, 0.62),
        ]
        parts.append(tube(beam, [0.016, 0.013, 0.01, 0.006], bone, 6))
        for t0, t1 in ((1, (0.14, -0.1, 0.55)), (2, (0.26, -0.08, 0.66))):
            parts.append(tube([beam[t0], (x * t1[0], t1[1], t1[2])], [0.01, 0.004], bone, 6))
    return parts


def sconce(rng):
    return [
        box((0.1, 0.03, 0.18), (0, 0.0, 0.09), brass(), 0.01),
        tube([(0, 0.0, 0.08), (0, -0.1, 0.1), (0, -0.14, 0.16)], 0.01, brass(), 8),
        lathe(
            [(0.05, 0.15), (0.09, 0.28), (0.085, 0.28), (0.045, 0.155)],
            (0, -0.14, 0),
            mat("glass_frost", (0.95, 0.85, 0.7), 0.3),
            segments=20,
            closed=True,
        ),
        sphere(0.03, (0, -0.14, 0.2), warm_glow(), segments=10),
    ]


def notice_board(rng):
    cork = mat("stone_cork", (0.62, 0.45, 0.3), 0.9)
    paper = [
        mat("paper_notice", (0.92, 0.9, 0.84), 0.9),
        mat("paper_yellow", (0.95, 0.85, 0.4), 0.9),
        mat("paper_blue", (0.55, 0.7, 0.9), 0.9),
    ]
    parts = [
        box((1.1, 0.03, 0.75), (0, 0, 0.375), mat("wood_frame", (0.3, 0.2, 0.12), 0.5), 0.01),
        box((1.02, 0.01, 0.67), (0, -0.016, 0.375), cork),
    ]
    for _ in range(9):
        w, h = rng.uniform(0.12, 0.22), rng.uniform(0.1, 0.28)
        note = box(
            (w, 0.003, h),
            (rng.uniform(-0.4, 0.4), -0.023, rng.uniform(0.18, 0.58)),
            rng.choice(paper),
        )
        note.rotation_euler.y = rng.uniform(-0.15, 0.15)
        parts.append(note)
    return parts


def wall_cabinet(rng):
    wood = pine()
    parts = [box((1.2, 0.34, 0.7), (0, 0, 0.35), wood, 0.008)]
    for x in (-1, 1):
        parts.append(box((0.58, 0.02, 0.66), (x * 0.3, -0.175, 0.35), wood, 0.008))
        parts.append(box((0.015, 0.02, 0.1), (x * 0.05, -0.19, 0.12), steel()))
    return parts


@dataclass
class Piece:
    """One decor model and how the game places it."""

    make: Callable[[random.Random], list]
    place: str
    themes: list[str]
    tints: list[tuple[float, float, float]] = field(default_factory=list)
    mount: float = 0.0
    solid: bool = True
    anywhere: bool = False


FABRICS = [
    (0.45, 0.12, 0.12),
    (0.2, 0.32, 0.22),
    (0.2, 0.27, 0.42),
    (0.6, 0.52, 0.4),
    (0.35, 0.22, 0.3),
]
GLAZES = [(0.3, 0.45, 0.6), (0.6, 0.2, 0.2), (0.25, 0.45, 0.3), (0.8, 0.75, 0.6)]

PIECES = {
    "sofa": Piece(sofa, "wall", ["living"], FABRICS),
    "armchair": Piece(armchair, "corner", ["living", "library", "bedroom"], FABRICS, anywhere=True),
    "coffee_table": Piece(coffee_table, "free", ["living"]),
    "bookcase": Piece(bookcase, "wall", ["living", "library", "office"], anywhere=True),
    "fireplace": Piece(fireplace, "wall", ["living", "library", "dining"], GLAZES),
    "floor_lamp": Piece(floor_lamp, "corner", ["living", "library", "bedroom"], anywhere=True),
    "potted_plant": Piece(
        potted_plant, "corner", ["living", "dining", "office", "hall", "library"], anywhere=True
    ),
    "side_table": Piece(side_table, "wall", ["living", "library", "hall"]),
    "dining_set": Piece(dining_set, "free", ["dining"]),
    "sideboard": Piece(sideboard, "wall", ["dining", "living"], GLAZES),
    "china_cabinet": Piece(china_cabinet, "wall", ["dining", "kitchen"]),
    "writing_desk": Piece(writing_desk, "wall", ["library", "office", "bedroom"]),
    "bed_double": Piece(bed_double, "wall", ["bedroom"], FABRICS),
    "bed_single": Piece(bed_single, "wall", ["bedroom", "lab"], FABRICS),
    "nightstand": Piece(nightstand, "wall", ["bedroom"]),
    "wardrobe": Piece(wardrobe, "wall", ["bedroom"]),
    "vanity": Piece(vanity, "wall", ["bedroom"], FABRICS),
    "office_desk": Piece(office_desk, "wall", ["office", "lab"], GLAZES),
    "filing_cabinet": Piece(filing_cabinet, "wall", ["office", "lab", "storage"], anywhere=True),
    "water_cooler": Piece(water_cooler, "corner", ["office", "hall"]),
    "metal_shelf": Piece(metal_shelf, "wall", ["storage", "office", "lab"], anywhere=True),
    "kitchen_counter": Piece(kitchen_counter, "wall", ["kitchen"]),
    "stove": Piece(stove, "wall", ["kitchen"]),
    "fridge": Piece(fridge, "corner", ["kitchen"]),
    "kitchen_table": Piece(kitchen_table, "free", ["kitchen"]),
    "workbench": Piece(workbench, "wall", ["lab", "storage"]),
    "specimen_tank": Piece(specimen_tank, "corner", ["lab"]),
    "lab_shelf": Piece(lab_shelf, "wall", ["lab"], anywhere=True),
    "gurney": Piece(gurney, "wall", ["lab"]),
    "server_rack": Piece(server_rack, "wall", ["lab", "office"]),
    "toilet": Piece(toilet, "wall", ["bathroom"]),
    "bath_sink": Piece(bath_sink, "wall", ["bathroom"]),
    "bathtub": Piece(bathtub, "wall", ["bathroom"]),
    "box_stack": Piece(box_stack, "corner", ["storage", "hall", "lab"], anywhere=True),
    "barrel": Piece(barrel, "corner", ["storage", "kitchen"], anywhere=True),
    "mop_bucket": Piece(mop_bucket, "corner", ["storage", "bathroom", "hall"]),
    "sacks": Piece(sacks, "corner", ["storage", "kitchen"], anywhere=True),
    "bench": Piece(bench, "wall", ["hall"], FABRICS),
    "coat_rack": Piece(coat_rack, "corner", ["hall", "bedroom"], anywhere=True),
    "umbrella_stand": Piece(umbrella_stand, "corner", ["hall"], GLAZES),
    "console_table": Piece(console_table, "wall", ["hall", "living"], GLAZES),
    "radiator": Piece(
        radiator, "wall", ["living", "bedroom", "office", "hall", "bathroom", "dining"]
    ),
    "rug_persian": Piece(
        rug_persian, "rug", ["living", "dining", "library", "bedroom"], FABRICS, solid=False
    ),
    "rug_round": Piece(rug_round, "rug", ["living", "bedroom"], solid=False),
    "runner": Piece(runner, "rug", ["hall"], FABRICS, solid=False),
    "framed_picture": Piece(
        framed_picture,
        "hang",
        ["living", "dining", "bedroom", "hall", "library", "office"],
        mount=1.3,
        solid=False,
    ),
    "portrait": Piece(
        portrait, "hang", ["living", "dining", "hall", "library"], mount=1.2, solid=False
    ),
    "mirror": Piece(mirror, "hang", ["bathroom", "bedroom", "hall"], mount=1.0, solid=False),
    "wall_clock": Piece(
        wall_clock, "hang", ["kitchen", "office", "hall", "living"], mount=1.7, solid=False
    ),
    "wall_shelf": Piece(
        wall_shelf, "hang", ["kitchen", "library", "lab", "bedroom"], mount=1.45, solid=False
    ),
    "antlers": Piece(antlers, "hang", ["living", "hall", "library"], mount=1.75, solid=False),
    "sconce": Piece(
        sconce, "hang", ["hall", "living", "dining", "bathroom"], mount=1.55, solid=False
    ),
    "notice_board": Piece(
        notice_board, "hang", ["office", "lab", "storage"], mount=1.0, solid=False
    ),
    "wall_cabinet": Piece(wall_cabinet, "hang", ["kitchen"], mount=1.5, solid=False),
}


def main(only: set[str]) -> None:
    """Builds the decor named in only (or all of it), and the catalogue when building all."""
    entries: list[dict[str, object]] = []
    for name, piece in PIECES.items():
        if only and name not in only:
            continue
        lib.reset()
        rng = random.Random(name)
        parts = piece.make(rng)
        lo, hi = lib.bounds(parts)
        root = lib.join(parts, name)
        # Origin on the floor in the middle of the footprint.
        root.location = (
            root.location[0] - (lo.x + hi.x) / 2,
            root.location[1] - (lo.y + hi.y) / 2,
            root.location[2] - lo.z,
        )
        lib.export(OUT / f"{name}.glb", [root])
        size = hi - lo
        print(f"[decor] {name}: {size.x:.2f} x {size.y:.2f} x {size.z:.2f} m")
        entry: dict[str, object] = {
            "name": name,
            "size": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],
            "place": piece.place,
            "themes": piece.themes,
            "solid": piece.solid,
        }
        if piece.tints:
            entry["tints"] = [list(c) for c in piece.tints]
        if piece.mount:
            entry["mount"] = piece.mount
        if piece.anywhere:
            entry["anywhere"] = True
        entries.append(entry)
    if not only:
        lib.write_catalogue("decor", entries)
