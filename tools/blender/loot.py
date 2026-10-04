"""Valuables, one model per loot kind, exported to assets/models/loot/.

Each fits inside its kind's collision box (`KINDS` in scripts/game.gd), centred on the origin,
front toward -Y. SIZES repeats those boxes in Blender's order (width, depth, height) and the
build fails if a model pokes out. Surfaces named "tint_..." take the item's colour in Godot.
"""

import math
import random

import lib
from lib import blob, box, cyl, lathe, mat, sphere, torus, tube

OUT = lib.MODELS / "loot"

GOLD = (0.85, 0.66, 0.2)
BRASS = (0.78, 0.6, 0.25)


def _gold():
    return mat("metal_gold", GOLD, 0.3, 1.0)


def _brass():
    return mat("metal_brass", BRASS, 0.35, 1.0)


def vase(w: float, d: float, h: float) -> list:
    """A glazed amphora with gold bands and two looping handles."""
    glaze = mat("tint_glaze", (0.3, 0.55, 0.9), 0.12)
    inside = mat("plain_shadow", (0.05, 0.05, 0.06), 0.9)
    gold = _gold()
    b = -h / 2
    profile = [
        (0.0, b),
        (0.07, b),
        (0.075, b + 0.02),
        (0.06, b + 0.04),
        (0.12, b + 0.12),
        (0.165, b + 0.24),
        (0.15, b + 0.33),
        (0.09, b + 0.41),
        (0.06, b + 0.46),
        (0.065, b + 0.5),
        (0.09, b + 0.545),
        (0.08, h / 2),
        (0.06, b + 0.52),
        (0.0, b + 0.5),
    ]
    parts = [lathe(profile, material=glaze, segments=40)]
    parts.append(cyl(0.06, 0.06, 0.005, (0, 0, b + 0.522), inside, segments=24))
    parts.append(torus(0.163, 0.008, (0, 0, b + 0.25), gold))
    parts.append(torus(0.068, 0.006, (0, 0, b + 0.47), gold))
    parts.append(torus(0.072, 0.005, (0, 0, b + 0.025), gold))
    for side in (-1, 1):
        arc = [
            (side * 0.06, 0, b + 0.48),
            (side * 0.13, 0, b + 0.5),
            (side * 0.15, 0, b + 0.42),
            (side * 0.12, 0, b + 0.35),
        ]
        parts.append(tube(arc, 0.012, glaze, 8, "handle"))
    return parts


def painting(w: float, d: float, h: float) -> list:
    """An oil painting in a deep carved gilt frame, hanging wire behind."""
    frame = _gold()
    dark = mat("wood_backing", (0.25, 0.18, 0.12), 0.8)
    canvas = mat("canvas", (0.5, 0.5, 0.5), 0.9)
    border = 0.1
    parts = []
    for z in (-1, 1):  # Top and bottom rails, with an inner moulding.
        parts.append(box((w, d * 0.7, border), (0, 0, z * (h - border) / 2), frame, 0.015))
        parts.append(box((w - 2 * border, d, 0.025), (0, -0.0, z * (h / 2 - border)), frame, 0.008))
    for x in (-1, 1):
        parts.append(box((border, d * 0.7, h), (x * (w - border) / 2, 0, 0), frame, 0.015))
        side = (x * (w / 2 - border), 0, 0)
        parts.append(box((0.025, d, h - 2 * border), side, frame, 0.008))
    for x in (-1, 1):
        for z in (-1, 1):
            corner = (x * (w - border) / 2, -d * 0.36, z * (h - border) / 2)
            parts.append(sphere(0.035, corner, frame, (1, 0.3, 1), segments=12))
    crest = (0, -d * 0.36, (h - border) / 2)
    parts.append(sphere(0.05, crest, frame, (1.6, 0.2, 0.8), segments=12))
    parts.append(box((w - 2 * border, 0.01, h - 2 * border), (0, -0.005, 0), canvas))
    parts.append(box((w - 0.05, 0.01, h - 0.05), (0, d * 0.3, 0), dark))
    return parts


def crate(w: float, d: float, h: float) -> list:
    """A shipping crate: gapped planks over a dark inside, edge beams, braces, iron corners."""
    planks = mat("tint_wood", (0.55, 0.38, 0.2), 0.9)
    beams = mat("wood_beam", (0.32, 0.22, 0.12), 0.9)
    inner = mat("plain_shadow", (0.05, 0.04, 0.03), 1.0)
    iron = mat("metal_iron", (0.22, 0.21, 0.2), 0.6, 1.0)
    rng = random.Random(7)
    t = 0.06
    parts = [box((w - 0.04, d - 0.04, h - 0.04), (0, 0, 0), inner)]
    rows = 4
    for face in range(6):
        axis, sign = divmod(face, 2)
        sign = sign * 2 - 1
        for r in range(rows):
            span = (h if axis != 2 else d) - 2 * t
            pitch = span / rows
            centre = -span / 2 + pitch * (r + 0.5)
            size = [w - 2 * t, d - 2 * t, h - 2 * t]
            at = [0.0, 0.0, 0.0]
            size[axis] = 0.022
            at[axis] = sign * (([w, d, h][axis]) / 2 - 0.015)
            run = 2 if axis != 2 else 1
            size[run] = pitch - 0.012
            at[run] = centre
            part = box(size, at, planks, 0.004)
            part.rotation_euler[axis] = rng.uniform(-0.01, 0.01)
            parts.append(part)
    for axis in range(3):
        for a in (-1, 1):
            for b in (-1, 1):
                size = [t, t, t]
                size[axis] = [w, d, h][axis]
                at = [0.0, 0.0, 0.0]
                at[(axis + 1) % 3] = a * ([w, d, h][(axis + 1) % 3] - t) / 2
                at[(axis + 2) % 3] = b * ([w, d, h][(axis + 2) % 3] - t) / 2
                parts.append(box(size, at, beams, 0.006))
    diagonal = math.hypot(w, h) - 2 * t
    for y in (-1, 1):
        brace = box((diagonal, 0.03, t * 0.8), (0, y * (d / 2 - 0.01), 0), beams, 0.005)
        brace.rotation_euler = (0, -y * math.atan2(h, w), 0)
        parts.append(brace)
    for x in (-1, 1):
        for y in (-1, 1):
            for z in (-1, 1):
                corner = (x * (w / 2 - 0.045), y * (d / 2 - 0.045), z * (h / 2 - 0.045))
                parts.append(box((0.1, 0.1, 0.1), corner, iron, 0.01))
    return parts


def grandfather_clock(w: float, d: float, h: float) -> list:
    """A longcase clock: plinth, trunk with a glazed pendulum door, arched hood and dial."""
    wood = mat("tint_wood", (0.4, 0.25, 0.15), 0.45)
    dark = mat("wood_inner", (0.15, 0.1, 0.06), 0.6)
    brass = _brass()
    face = mat("paper_dial", (0.93, 0.9, 0.8), 0.6)
    black = mat("plain_black", (0.03, 0.03, 0.03), 0.4)
    glass = mat("glass_clear", (0.8, 0.9, 1.0), 0.05)
    b = -h / 2
    parts = [
        box((w, d, 0.06), (0, 0, b + 0.03), wood, 0.01),
        box((w * 0.92, d * 0.92, 0.32), (0, 0, b + 0.22), wood, 0.01),
        box((w * 0.96, d * 0.96, 0.04), (0, 0, b + 0.39), wood, 0.01),
    ]
    trunk_top = b + 1.15
    parts.append(
        box(
            (w * 0.76, d * 0.78, trunk_top - (b + 0.41)),
            (0, 0, (b + 0.41 + trunk_top) / 2),
            wood,
            0.008,
        )
    )
    parts.append(box((w * 0.92, d * 0.95, 0.04), (0, 0, trunk_top + 0.02), wood, 0.01))
    hood_b = trunk_top + 0.04
    hood_top = h / 2 - 0.2
    hood_h = hood_top - hood_b
    parts.append(box((w * 0.88, d * 0.9, hood_h), (0, 0, hood_b + hood_h / 2), wood, 0.01))
    arch = cyl(w * 0.3, w * 0.3, d * 0.86, (0, 0, hood_top), wood, (math.pi / 2, 0, 0), 32)
    parts.append(arch)
    parts.append(box((w * 0.88, d * 0.9, 0.025), (0, 0, hood_top), wood, 0.005))
    for x, z in ((-1, hood_top + 0.035), (0, h / 2 - 0.05), (1, hood_top + 0.035)):  # Finials.
        parts.append(sphere(0.016, (x * w * 0.38, 0, z), brass, segments=12))
        parts.append(cyl(0.01, 0.0, 0.035, (x * w * 0.38, 0, z + 0.028), brass, segments=8))
    front = -d * 0.42
    dial_z = hood_b + hood_h * 0.5
    rot = (math.pi / 2, 0, 0)
    parts.append(cyl(w * 0.34, w * 0.34, 0.01, (0, front - 0.005, dial_z), face, rot, 40))
    parts.append(torus(w * 0.34, 0.012, (0, front - 0.01, dial_z), brass, rot))
    for k in range(12):
        a = k * math.pi / 6
        mark = (math.sin(a) * w * 0.28, front - 0.012, dial_z + math.cos(a) * w * 0.28)
        parts.append(box((0.008, 0.004, 0.03 if k % 3 == 0 else 0.018), mark, black, rot=(0, a, 0)))
    parts.append(box((0.012, 0.004, w * 0.2), (0, front - 0.016, dial_z + w * 0.09), black))
    hand = box(
        (0.009, 0.004, w * 0.26), (0.05, front - 0.018, dial_z - 0.04), black, rot=(0, 2.2, 0)
    )
    parts.append(hand)
    parts.append(sphere(0.012, (0, front - 0.02, dial_z), brass, segments=10))
    window_z = (b + 0.45 + trunk_top) / 2
    window_h = (trunk_top - b - 0.5) * 0.85
    trunk_front = -d * 0.39
    parts.append(box((w * 0.5, 0.01, window_h), (0, trunk_front + 0.006, window_z), dark))
    parts.append(box((w * 0.5, 0.004, window_h), (0, trunk_front - 0.006, window_z), glass))
    for x in (-1, 1):
        rail = (x * w * 0.27, trunk_front - 0.004, window_z)
        parts.append(box((0.025, 0.012, window_h + 0.04), rail, wood, 0.003))
    parts.append(
        box(
            (0.01, 0.006, window_h * 0.6),
            (0, trunk_front + 0.001, window_z + window_h * 0.15),
            brass,
        )
    )
    bob_at = (0, trunk_front, window_z - window_h * 0.18)
    parts.append(cyl(0.055, 0.055, 0.012, bob_at, brass, rot, 28))
    for x in (-1, 1):
        weight = (x * 0.05, trunk_front + 0.01, window_z + window_h * 0.25)
        parts.append(cyl(0.018, 0.018, 0.14, weight, brass, segments=12))
    return parts


def piano(w: float, d: float, h: float) -> list:
    """An upright piano: lacquered case, keys, fallboard, music desk, legs and pedals."""
    lacquer = mat("lacquer_black", (0.06, 0.045, 0.045), 0.08)
    ivory = mat("plain_ivory", (0.95, 0.92, 0.84), 0.35)
    ebony = mat("plain_ebony", (0.03, 0.03, 0.03), 0.3)
    brass = _brass()
    felt = mat("fabric_felt", (0.45, 0.06, 0.06), 1.0)
    b = -h / 2
    back = d / 2
    case_d = d * 0.55
    parts = [
        box(
            (w, case_d, h - 0.14), (0, back - case_d / 2, b + 0.14 + (h - 0.14) / 2), lacquer, 0.012
        ),
        box(
            (w, case_d + 0.03, 0.035), (0, back - case_d / 2 - 0.015, h / 2 - 0.018), lacquer, 0.01
        ),
        box((w, case_d, 0.14), (0, back - case_d / 2, b + 0.07), lacquer, 0.01),
    ]
    key_z = b + 0.68
    bed_d = d - case_d
    bed_y = -d / 2 + bed_d / 2
    parts.append(box((w, bed_d, 0.06), (0, bed_y, key_z - 0.05), lacquer, 0.008))
    for x in (-1, 1):  # Cheeks either side of the keys.
        cheek = box((0.06, bed_d, 0.14), (x * (w / 2 - 0.03), bed_y, key_z + 0.02), lacquer, 0.015)
        parts.append(cheek)
    keys_w = w - 0.14
    whites = 36
    pitch = keys_w / whites
    key_d = bed_d * 0.85
    for i in range(whites):
        x = -keys_w / 2 + pitch * (i + 0.5)
        parts.append(
            box((pitch - 0.002, key_d, 0.022), (x, bed_y + 0.01, key_z - 0.006), ivory, 0.002)
        )
        if i % 7 not in (2, 6) and i < whites - 1:
            black = (x + pitch / 2, bed_y + key_d * 0.2, key_z + 0.012)
            parts.append(box((pitch * 0.55, key_d * 0.6, 0.022), black, ebony, 0.002))
    parts.append(box((keys_w, 0.01, 0.012), (0, bed_y - key_d / 2 + 0.05, key_z + 0.004), felt))
    fall_y = back - case_d - 0.02
    parts.append(box((w - 0.12, 0.04, 0.12), (0, fall_y, key_z + 0.1), lacquer, 0.01))
    desk = box((w * 0.6, 0.02, 0.22), (0, fall_y - 0.02, key_z + 0.3), lacquer, 0.005)
    desk.rotation_euler = (-0.25, 0, 0)
    parts.append(desk)
    for x in (-1, 1):
        sconce = (x * w * 0.38, fall_y - 0.04, key_z + 0.33)
        parts.append(cyl(0.03, 0.015, 0.03, sconce, brass, segments=12))
        leg_at = (x * (w / 2 - 0.08), -d / 2 + 0.05, (b + key_z - 0.08) / 2)
        parts.append(
            lathe(
                [(0.0, -0.3), (0.035, -0.3), (0.045, -0.2), (0.03, 0.1), (0.04, 0.26), (0.0, 0.26)],
                leg_at,
                lacquer,
                segments=16,
            )
        )
        parts.append(box((0.08, d * 0.9, 0.05), (x * (w / 2 - 0.08), 0, b + 0.025), lacquer, 0.01))
    for x in (-0.09, 0, 0.09):
        parts.append(box((0.035, 0.12, 0.012), (x, -d / 2 + 0.2, b + 0.05), brass, 0.004))
    return parts


def gem(w: float, d: float, h: float) -> list:
    """A brilliant-cut stone: pointed pavilion, girdle, faceted crown and flat table."""
    stone = mat("tint_gem", (0.85, 0.1, 0.25), 0.05)
    r = w / 2 * 0.95
    profile = [
        (0.0, -h / 2),
        (r, -h * 0.05),
        (r, h * 0.02),
        (r * 0.6, h / 2 * 0.8),
        (0.0, h / 2 * 0.8),
    ]
    return [lathe(profile, material=stone, segments=8, smooth=False)]


def necklace(w: float, d: float, h: float) -> list:
    """A chain of links lying in a loop, a set stone hanging at the front."""
    metal = mat("tint_metal", GOLD, 0.25, 1.0)
    ruby = mat("gem_ruby", (0.75, 0.05, 0.15), 0.05)
    b = -h / 2
    parts = []
    links = 44
    for i in range(links):
        a = 2 * math.pi * i / links
        x, y = math.sin(a) * (w / 2 - 0.01), math.cos(a) * (d / 2 - 0.035) + 0.01
        tilt = (math.pi / 2 if i % 2 else 0.0, 0, -a)
        parts.append(torus(0.007, 0.0018, (x, y, b + 0.008), metal, tilt, segments=10))
    pendant = (0, -d / 2 + 0.03, b + 0.01)
    parts.append(torus(0.017, 0.003, pendant, metal, (0, 0, 0), segments=20))
    parts.append(
        lathe(
            [(0.0, -0.008), (0.014, 0.0), (0.009, 0.007), (0.0, 0.007)],
            pendant,
            ruby,
            segments=8,
            smooth=False,
        )
    )
    return parts


def book(w: float, d: float, h: float) -> list:
    """A hardback lying flat: boards, rounded spine, gilt bands, page block, brass corners."""
    cover = mat("tint_leather", (0.45, 0.12, 0.1), 0.6)
    pages = mat("paper_pages", (0.9, 0.86, 0.75), 0.9)
    gold = _gold()
    board = 0.005
    parts = []
    for z in (-1, 1):
        parts.append(box((w - 0.006, d, board), (0.003, 0, z * (h - board) / 2), cover, 0.0015))
    spine = cyl(h / 2, h / 2, d, (-w / 2 + h / 2, 0, 0), cover, (math.pi / 2, 0, 0), 20)
    spine.scale = (0.5, 1, 1)
    parts.append(spine)
    parts.append(box((w - 0.016, d - 0.008, h - 2 * board), (0.004, 0, 0), pages))
    for y in (-0.07, -0.02, 0.06):
        band = cyl(
            h / 2 + 0.001,
            h / 2 + 0.001,
            0.006,
            (-w / 2 + h / 2, y, 0),
            gold,
            (math.pi / 2, 0, 0),
            20,
        )
        band.scale = (0.52, 1, 1)
        parts.append(band)
    for y in (-1, 1):
        for z in (-1, 1):
            parts.append(
                box(
                    (0.022, 0.022, board + 0.002),
                    (w / 2 - 0.011, y * (d / 2 - 0.011), z * (h - board) / 2),
                    gold,
                )
            )
    return parts


def vial(w: float, d: float, h: float) -> list:
    """A round-bottomed flask of glowing liquid, corked, with a paper label."""
    glass = mat("glass_flask", (0.8, 0.9, 1.0), 0.05)
    liquid = mat("tint_glow", (0.3, 0.9, 0.5), emission=2.0)
    cork = mat("wood_cork", (0.6, 0.45, 0.28), 0.9)
    label = mat("paper_label", (0.85, 0.8, 0.65), 0.9)
    b = -h / 2
    r = w / 2 * 0.95
    outer = [
        (0.0, b),
        (r * 0.7, b + 0.006),
        (r, b + r),
        (r * 0.85, b + r * 1.7),
        (r * 0.4, b + r * 2.3),
        (r * 0.38, h / 2 - 0.03),
        (r * 0.45, h / 2 - 0.025),
        (r * 0.45, h / 2 - 0.02),
        (0.0, h / 2 - 0.02),
    ]
    fill = [
        (0.0, b + 0.003),
        (r * 0.62, b + 0.008),
        (r * 0.9, b + r),
        (r * 0.82, b + r * 1.4),
        (0.0, b + r * 1.4),
    ]
    parts = [lathe(outer, material=glass, segments=20), lathe(fill, material=liquid, segments=20)]
    parts.append(cyl(r * 0.42, r * 0.36, 0.03, (0, 0, h / 2 - 0.015), cork, segments=12))
    parts.append(
        lathe(
            [(r * 0.9, b + r * 0.75), (r * 1.01, b + r), (r * 0.96, b + r * 1.35)],
            material=label,
            segments=20,
        )
    )
    return parts


def bust(w: float, d: float, h: float) -> list:
    """A marble bust of a stern head on a turned pedestal."""
    marble = mat("marble_white", (0.86, 0.85, 0.82), 0.25)
    plinth = mat("marble_dark", (0.2, 0.22, 0.24), 0.2)
    b = -h / 2
    parts = [
        lathe(
            [
                (0.0, 0.0),
                (0.12, 0.0),
                (0.12, 0.03),
                (0.08, 0.05),
                (0.06, 0.1),
                (0.09, 0.13),
                (0.0, 0.13),
            ],
            (0, 0, b),
            plinth,
            segments=32,
        )
    ]
    top = b + 0.13
    flesh = blob(
        [
            ((-0.11, 0.0, top + 0.08), (0.11, 0.0, top + 0.08), 0.06),
            ((0, -0.02, top + 0.1), 0.09),
            ((0, 0.0, top + 0.14), (0, -0.01, top + 0.22), 0.045),
            ((0, 0.01, top + 0.31), 0.085),
            ((0, -0.04, top + 0.26), (0, -0.05, top + 0.31), 0.05),
            ((0, -0.085, top + 0.3), (0, -0.095, top + 0.33), 0.012),
            ((-0.08, 0.01, top + 0.31), 0.018),
            ((0.08, 0.01, top + 0.31), 0.018),
            ((0, 0.03, top + 0.36), 0.08),
        ],
        marble,
        resolution=0.012,
        name="bust",
    )
    parts.append(flesh)
    for x in (-1, 1):
        parts.append(sphere(0.012, (x * 0.032, -0.07, top + 0.33), marble, segments=10))
    return parts


def candelabra(w: float, d: float, h: float) -> list:
    """A five-branched gold candelabra with tall candles."""
    gold = _gold()
    wax = mat("plain_wax", (0.92, 0.88, 0.76), 0.6)
    flame = mat("glow_flame", (1.0, 0.7, 0.3), emission=4.0)
    b = -h / 2
    parts = [
        lathe(
            [
                (0.0, 0.0),
                (0.07, 0.0),
                (0.07, 0.012),
                (0.04, 0.03),
                (0.015, 0.06),
                (0.012, 0.2),
                (0.022, 0.21),
                (0.012, 0.22),
                (0.012, 0.28),
                (0.0, 0.28),
            ],
            (0, 0, b),
            gold,
            segments=24,
        )
    ]
    cup_z = b + 0.3
    xs = (-0.16, -0.08, 0.0, 0.08, 0.16)
    for x in xs:
        if x != 0.0:
            arc = [
                (0, 0, b + 0.2),
                (x * 0.5, 0, b + 0.2 - abs(x) * 0.2),
                (x, 0, b + 0.22),
                (x, 0, cup_z - 0.01),
            ]
            parts.append(tube(arc, 0.007, gold, 8, "arm"))
        z = cup_z + (0.04 if x == 0.0 else 0.0)
        parts.append(
            lathe(
                [(0.0, -0.01), (0.018, -0.01), (0.026, 0.01), (0.0, 0.01)],
                (x, 0, z),
                gold,
                segments=16,
            )
        )
        candle_h = h / 2 - 0.04 - (z + 0.01)
        parts.append(cyl(0.01, 0.01, candle_h, (x, 0, z + 0.01 + candle_h / 2), wax, segments=12))
        parts.append(sphere(0.008, (x, 0, h / 2 - 0.02), flame, (1, 1, 2.0), segments=8))
    return parts


def globe(w: float, d: float, h: float) -> list:
    """A terrestrial globe on a turned wooden stand with a brass meridian."""
    wood = mat("wood_stand", (0.4, 0.25, 0.14), 0.5)
    brass = _brass()
    sea = mat("glaze_sea", (0.16, 0.3, 0.42), 0.4)
    land = mat("paper_land", (0.68, 0.6, 0.4), 0.8)
    b = -h / 2
    parts = [
        lathe(
            [
                (0.0, 0.0),
                (0.15, 0.0),
                (0.15, 0.02),
                (0.06, 0.04),
                (0.025, 0.08),
                (0.02, 0.17),
                (0.0, 0.17),
            ],
            (0, 0, b),
            wood,
            segments=32,
        )
    ]
    centre = (0, 0, b + 0.37)
    r = 0.165
    tilt = (0, 0.41, 0)
    parts.append(sphere(r, centre, sea, rot=tilt, segments=32))
    rng = random.Random(3)
    for _ in range(14):
        lat = rng.uniform(-1.1, 1.2)
        lon = rng.uniform(0, 2 * math.pi)
        normal = (math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))
        at = tuple(c + n * r * 0.995 for c, n in zip(centre, normal, strict=True))
        size = rng.uniform(0.03, 0.07)
        patch = sphere(size, at, land, (1.0, 1.0, 0.12), segments=12)
        patch.rotation_mode = "XYZ"
        patch.rotation_euler = (0, math.pi / 2 - lat, lon)
        parts.append(patch)
    ring = torus(r + 0.015, 0.006, centre, brass, (math.pi / 2, 0.41, 0), segments=48)
    parts.append(ring)
    parts.append(cyl(0.008, 0.008, 0.06, (0, 0, b + 0.19), brass, segments=8))
    return parts


def gramophone(w: float, d: float, h: float) -> list:
    """A wind-up gramophone: wooden case, record, tonearm and a flared brass horn."""
    wood = mat("wood_case", (0.42, 0.24, 0.12), 0.45)
    brass = _brass()
    record = mat("plastic_record", (0.04, 0.04, 0.04), 0.25)
    label = mat("paper_record", (0.7, 0.15, 0.1), 0.8)
    felt = mat("fabric_green", (0.1, 0.3, 0.15), 1.0)
    b = -h / 2
    case_h = 0.16
    parts = [
        box((w, w, case_h), (0, 0.0, b + case_h / 2), wood, 0.01),
        box((w + 0.01, w + 0.01, 0.02), (0, 0, b + 0.01), wood, 0.005),
    ]
    top = b + case_h
    parts.append(cyl(0.18, 0.18, 0.01, (0, 0, top + 0.005), felt, segments=40))
    parts.append(cyl(0.16, 0.16, 0.006, (0, 0, top + 0.013), record, segments=40))
    parts.append(cyl(0.045, 0.045, 0.008, (0, 0, top + 0.014), label, segments=24))
    parts.append(box((0.012, 0.03, 0.06), (w / 2 - 0.004, 0.0, b + case_h / 2), brass))  # Crank.
    pillar = (w / 2 - 0.05, w / 2 - 0.05, top)
    parts.append(cyl(0.02, 0.016, 0.08, (pillar[0], pillar[1], top + 0.04), brass, segments=12))
    neck = [
        (pillar[0], pillar[1], top + 0.08),
        (0.12, 0.12, top + 0.1),
        (0.04, 0.04, top + 0.06),
        (0.03, 0.03, top + 0.04),
    ]
    parts.append(tube(neck, 0.012, brass, 8, "tonearm"))
    horn_profile = [(0.02 + 0.2 * (t / 10) ** 2.4, 0.33 * t / 10) for t in range(11)]
    inner = [(r - 0.004, z) for r, z in reversed(horn_profile)]
    # Rises from the back of the case and leans forward over the record.
    horn = lathe(horn_profile + inner, (0, 0.15, top + 0.06), brass, segments=32)
    horn.rotation_euler = (math.radians(50), 0, 0)
    parts.append(horn)
    return parts


def goblet(w: float, d: float, h: float) -> list:
    """A chalice with a jewelled cup on a knotted stem."""
    metal = mat("tint_metal", GOLD, 0.25, 1.0)
    ruby = mat("gem_ruby", (0.75, 0.05, 0.15), 0.05)
    b = -h / 2
    r = w / 2 * 0.95
    profile = [
        (0.0, b),
        (r * 0.85, b),
        (r * 0.8, b + 0.008),
        (r * 0.25, b + 0.02),
        (r * 0.15, b + 0.05),
        (r * 0.3, b + 0.06),
        (r * 0.15, b + 0.07),
        (r * 0.2, b + 0.08),
        (r * 0.85, b + 0.11),
        (r, h / 2),
        (r * 0.92, h / 2),
        (r * 0.75, b + 0.1),
        (0.0, b + 0.09),
    ]
    parts = [lathe(profile, material=metal, segments=32)]
    for k in range(4):
        a = k * math.pi / 2
        at = (math.cos(a) * r * 0.9, math.sin(a) * r * 0.9, b + 0.125)
        parts.append(sphere(0.006, at, ruby, segments=8))
    return parts


def pocket_watch(w: float, d: float, h: float) -> list:
    """A hunter pocket watch lying face up, with its crown, bow and a short chain."""
    metal = mat("tint_metal", GOLD, 0.25, 1.0)
    face = mat("paper_dial", (0.93, 0.9, 0.8), 0.6)
    black = mat("plain_black", (0.03, 0.03, 0.03), 0.4)
    glass = mat("glass_clear", (0.8, 0.9, 1.0), 0.05)
    r = w / 2 * 0.95
    y = d / 2 - r - 0.002
    parts = [
        lathe(
            [
                (0.0, -h / 2),
                (r * 0.9, -h / 2),
                (r, -h / 2 + 0.004),
                (r, h / 2 - 0.005),
                (r * 0.9, h / 2 - 0.002),
                (0.0, h / 2 - 0.002),
            ],
            (0, y, 0),
            metal,
            segments=32,
        ),
        cyl(r * 0.82, r * 0.82, 0.001, (0, y, h / 2 - 0.0015), face, segments=32),
        cyl(r * 0.84, r * 0.8, 0.002, (0, y, h / 2 - 0.0005), glass, segments=32),
        box((0.002, r * 0.5, 0.0008), (0, y - r * 0.25, h / 2 - 0.0006), black),
        box(
            (0.0018, r * 0.65, 0.0008),
            (r * 0.18, y - r * 0.18, h / 2 - 0.0004),
            black,
            rot=(0, 0, 0.8),
        ),
        cyl(0.004, 0.004, 0.006, (0, y - r - 0.003, 0), metal, (math.pi / 2, 0, 0), 12),
        torus(0.007, 0.0015, (0, y - r - 0.01, 0), metal, (math.pi / 2, 0, 0), 16),
    ]
    for k in range(12):
        a = k * math.pi / 6
        parts.append(
            box(
                (0.0015, 0.004, 0.0008),
                (math.sin(a) * r * 0.68, y + math.cos(a) * r * 0.68, h / 2 - 0.0008),
                black,
                rot=(0, 0, -a),
            )
        )
    return parts


def idol(w: float, d: float, h: float) -> list:
    """A squat golden idol, seated, with gem eyes and a crested headdress."""
    gold = _gold()
    eye = mat("gem_emerald", (0.1, 0.75, 0.35), 0.05)
    b = -h / 2
    body = blob(
        [
            ((0, 0, b + 0.034), 0.03),
            ((0, 0.0, b + 0.04), 0.03),
            ((-0.025, -0.012, b + 0.022), (0.025, -0.012, b + 0.022), 0.013),
            ((0, 0.0, b + 0.06), (0, 0.0, b + 0.075), 0.024),
            ((0, -0.003, b + 0.095), 0.026),
            ((-0.03, -0.012, b + 0.06), (-0.018, -0.02, b + 0.04), 0.008),
            ((0.03, -0.012, b + 0.06), (0.018, -0.02, b + 0.04), 0.008),
        ],
        gold,
        resolution=0.004,
        name="idol",
    )
    parts = [body, cyl(0.036, 0.036, 0.006, (0, 0, b + 0.003), gold, segments=24)]
    parts.append(box((0.05, 0.012, 0.03), (0, 0.004, h / 2 - 0.015), gold, 0.003))
    for x in (-1, 1):
        parts.append(sphere(0.005, (x * 0.01, -0.027, b + 0.1), eye, segments=8))
    return parts


# Collision boxes from KINDS in scripts/game.gd, as (width, depth, height).
KINDS = {
    "vase": (vase, (0.35, 0.35, 0.55)),
    "painting": (painting, (1.0, 0.08, 0.8)),
    "crate": (crate, (0.7, 0.7, 0.7)),
    "grandfather_clock": (grandfather_clock, (0.5, 0.4, 1.7)),
    "piano": (piano, (1.6, 0.7, 1.1)),
    "gem": (gem, (0.12, 0.12, 0.12)),
    "necklace": (necklace, (0.22, 0.2, 0.04)),
    "book": (book, (0.18, 0.25, 0.05)),
    "vial": (vial, (0.06, 0.06, 0.16)),
    "bust": (bust, (0.3, 0.26, 0.6)),
    "candelabra": (candelabra, (0.4, 0.15, 0.55)),
    "globe": (globe, (0.4, 0.4, 0.55)),
    "gramophone": (gramophone, (0.5, 0.5, 0.65)),
    "goblet": (goblet, (0.09, 0.09, 0.18)),
    "pocket_watch": (pocket_watch, (0.06, 0.09, 0.016)),
    "idol": (idol, (0.08, 0.06, 0.14)),
}


def main(only: set[str]) -> None:
    """Builds the loot models named in only, or all of them when it is empty."""
    for name, (make, size) in KINDS.items():
        if only and name not in only:
            continue
        lib.reset()
        parts = make(*size)
        lo, hi = lib.bounds(parts)
        slack = 0.01
        out = [
            axis
            for axis, a, b, s in zip("xyz", lo.to_tuple(), hi.to_tuple(), size, strict=True)
            if a < -s / 2 - slack or b > s / 2 + slack
        ]
        root = lib.join(parts, name)
        lib.export(OUT / f"{name}.glb", [root])
        span = hi - lo
        note = f"  OUTSIDE its box on {''.join(out)}" if out else ""
        print(f"[loot] {name}: {span.x:.3f} x {span.y:.3f} x {span.z:.3f} of {size}{note}")
