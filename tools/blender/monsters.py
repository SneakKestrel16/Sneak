"""Four monsters, each a different body plan, exported to assets/models/monsters/.

Every monster stands with its origin at its feet, fits the 2.4 m tall, 0.5 m radius
collision capsule in scripts/monster.gd (limbs may brush 0.1 m past it), and faces -Y.
Godot animates them by node name (`Monster` in scripts/monster.gd):

- `torso`: leans into a chase.
- `head`: looks about.
- `arm_<n>`: dangle while roaming, reach forward in a chase.
- `leg_<n>`: swing about their local X axis, even and odd numbers in turn.
- `float`: bobs up and down (for something without legs).

An empty named `eyes` marks where it looks from.
"""

import math
import random

import lib
from lib import blob, box, cyl, lathe, mat, parent, pivot, sphere, tube

OUT = lib.MODELS / "monsters"


def _claws(
    tips: list[tuple[float, float, float]], material, length: float = 0.09, down: bool = True
):
    """Small bone cones pointing down (or forward) from each fingertip."""
    parts = []
    for tip in tips:
        rot = (math.pi, 0, 0) if down else (math.pi / 2, 0, 0)
        offset = (0, 0, -length / 2) if down else (0, -length / 2, 0)
        at = (tip[0] + offset[0], tip[1] + offset[1], tip[2] + offset[2])
        parts.append(cyl(0.012, 0.0, length, at, material, rot, segments=8))
    return parts


def stalker() -> list:
    """A gaunt, hunched figure with arms to its knees, ribs showing and a long jaw."""
    skin = mat("flesh_grey", (0.16, 0.14, 0.15), 0.55)
    bone = mat("bone", (0.66, 0.62, 0.52), 0.7)
    glow = mat("glow_red", (1.0, 0.12, 0.05), emission=6.0)
    root = pivot("stalker")

    for i, side in enumerate((-1, 1)):
        hip = pivot(f"leg_{i}", (side * 0.16, 0, 1.12))
        leg = blob(
            [
                ((side * 0.16, 0, 1.12), (side * 0.18, -0.06, 0.6), 0.075),
                ((side * 0.18, -0.06, 0.6), (side * 0.17, 0.07, 0.1), 0.05),
                ((side * 0.17, 0.07, 0.06), (side * 0.17, -0.18, 0.04), 0.04),
            ],
            skin,
            name=f"leg_mesh_{i}",
        )
        toes = [(side * 0.17 + d, -0.24, 0.04) for d in (-0.03, 0, 0.03)]
        for part in [leg, *_claws(toes, bone, 0.06, down=False)]:
            parent(part, hip)
        parent(hip, root)

    torso = pivot("torso", (0, 0, 1.1))
    body = blob(
        [
            ((0, 0, 1.12), 0.14),
            ((0, -0.01, 1.15), (0, -0.06, 1.5), 0.11),
            ((0, -0.08, 1.58), (0, -0.2, 1.92), 0.19),
            ((0, 0.02, 1.86), 0.15),
            ((0, -0.2, 1.97), (0, -0.27, 2.08), 0.065),
        ],
        skin,
        name="body",
    )
    parent(body, torso)
    for k in range(4):  # Ribs pushing through the chest.
        z = 1.62 + k * 0.08
        for side in (-1, 1):
            arc = [
                (side * 0.05, -0.32 - k * 0.02, z),
                (side * 0.16, -0.27 - k * 0.02, z + 0.02),
                (side * 0.21, -0.14 - k * 0.02, z + 0.04),
                (side * 0.18, -0.02, z + 0.05),
            ]
            parent(tube(arc, 0.014, bone, 6, name="rib"), torso)
    for k in range(6):  # Spine ridges down the hump.
        z = 1.3 + k * 0.12
        y = 0.1 + 0.05 * math.sin(k / 5 * math.pi)
        parent(cyl(0.045, 0.0, 0.13, (0, y + 0.04, z), bone, (-math.pi / 2, 0, 0), 8), torso)

    for i, side in enumerate((-1, 1)):
        shoulder = pivot(f"arm_{i}", (side * 0.27, -0.16, 1.97))
        arm = blob(
            [
                ((side * 0.27, -0.16, 1.97), 0.09),
                ((side * 0.27, -0.16, 1.97), (side * 0.33, -0.18, 1.42), 0.055),
                ((side * 0.33, -0.18, 1.42), (side * 0.35, -0.24, 0.86), 0.042),
                ((side * 0.35, -0.25, 0.8), 0.05),
            ],
            skin,
            name=f"arm_mesh_{i}",
        )
        parent(arm, shoulder)
        tips = []
        for f in range(4):
            spread = (f - 1.5) * 0.03
            finger = [
                (side * 0.35 + spread, -0.25, 0.78),
                (side * 0.35 + spread * 1.4, -0.27, 0.66),
                (side * 0.35 + spread * 1.6, -0.25, 0.55),
            ]
            parent(tube(finger, [0.016, 0.013, 0.01], skin, 6, name="finger"), shoulder)
            tips.append(finger[-1])
        for claw in _claws(tips, bone, 0.1):
            parent(claw, shoulder)
        parent(shoulder, torso)

    head = pivot("head", (0, -0.28, 2.1))
    skull = blob(
        [((0, -0.3, 2.25), 0.13), ((0, -0.36, 2.22), (0, -0.42, 2.1), 0.08)], skin, name="skull"
    )
    parent(skull, head)
    for side in (-1, 1):
        parent(sphere(0.028, (side * 0.06, -0.415, 2.26), glow, segments=12), head)
    parent(box((0.1, 0.02, 0.012), (0, -0.495, 2.1), glow), head)
    for k in range(7):  # Teeth round the slit.
        x = (k - 3) * 0.016
        for z, flip in ((2.112, math.pi), (2.088, 0.0)):
            parent(cyl(0.006, 0.0, 0.025, (x, -0.49, z), bone, (flip, 0, 0), 6), head)
    parent(pivot("eyes", (0, -0.42, 2.26)), head)
    parent(head, torso)
    parent(torso, root)
    return [root]


def crawler() -> list:
    """A pale six-legged thing with a human torso and a porcelain face of many eyes."""
    flesh = mat("flesh_pale", (0.62, 0.55, 0.5), 0.5)
    chitin = mat("lacquer_chitin", (0.12, 0.08, 0.07), 0.3)
    porcelain = mat("glaze_porcelain", (0.88, 0.86, 0.82), 0.2)
    glow = mat("glow_yellow", (1.0, 0.85, 0.2), emission=6.0)
    root = pivot("crawler")

    sac = blob(
        [((0, 0.38, 0.72), 0.3), ((0, 0.55, 0.62), 0.22), ((0, 0.05, 0.75), 0.2)],
        flesh,
        name="abdomen",
    )
    parent(sac, root)
    for k in range(5):  # Dark plates along its back.
        y = 0.1 + k * 0.13
        z = 0.95 - abs(k - 2) * 0.04
        plate = sphere(0.16, (0, y, z), chitin, (1.0, 0.6, 0.25), segments=16)
        parent(plate, root)

    # Legs in tripod order: even numbers step together, then odd.
    legs = [(-1, -0.12), (1, -0.12), (1, 0.08), (-1, 0.08), (-1, 0.28), (1, 0.28)]
    for i, (side, y) in enumerate(legs):
        start = (side * 0.15, y, 0.78)
        knee = (side * 0.45, y - 0.08, 1.08)
        ankle = (side * 0.56, y - 0.12, 0.45)
        foot = (side * 0.58, y - 0.14, 0.0)
        # Local X points up, so the swing about it is a horizontal stride.
        hip = pivot(f"leg_{i}", start, (0, math.pi / 2, 0))
        leg = tube([start, knee, ankle, foot], [0.05, 0.035, 0.025, 0.008], chitin, 8, "leg")
        parent(leg, hip)
        parent(sphere(0.045, knee, chitin, segments=10), hip)
        parent(hip, root)

    torso = pivot("torso", (0, -0.15, 0.85))
    upper = blob(
        [
            ((0, -0.15, 0.82), (0, -0.25, 1.15), 0.12),
            ((0, -0.26, 1.2), (0, -0.28, 1.32), 0.15),
            ((0, -0.28, 1.36), (0, -0.3, 1.46), 0.05),
        ],
        flesh,
        name="upper",
    )
    parent(upper, torso)
    for i, side in enumerate((-1, 1)):
        shoulder = pivot(f"arm_{i}", (side * 0.16, -0.28, 1.32))
        arm = tube(
            [
                (side * 0.16, -0.28, 1.32),
                (side * 0.26, -0.35, 1.0),
                (side * 0.24, -0.5, 0.62),
                (side * 0.2, -0.55, 0.42),
            ],
            [0.045, 0.035, 0.028, 0.02],
            flesh,
            8,
            "arm",
        )
        parent(arm, shoulder)
        tips = [(side * 0.2 + d, -0.56, 0.4) for d in (-0.025, 0.0, 0.025)]
        for claw in _claws(tips, chitin, 0.12):
            parent(claw, shoulder)
        parent(shoulder, torso)

    head = pivot("head", (0, -0.3, 1.46))
    face = sphere(0.14, (0, -0.32, 1.6), porcelain, (0.85, 0.75, 1.15), segments=24)
    parent(face, head)
    parent(sphere(0.15, (0, -0.28, 1.63), flesh, (0.95, 0.85, 1.15), segments=20), head)
    eyes = [(-0.05, 1.66), (0.05, 1.66), (-0.075, 1.6), (0.075, 1.6), (-0.03, 1.72), (0.03, 1.72)]
    for x, z in eyes:
        parent(sphere(0.016, (x, -0.42, z), glow, segments=10), head)
    crack = [(0.02, -0.425, 1.75), (0.0, -0.43, 1.64), (0.03, -0.43, 1.55), (0.01, -0.42, 1.48)]
    parent(tube(crack, 0.004, chitin, 4, "crack"), head)
    parent(box((0.07, 0.02, 0.012), (0, -0.425, 1.5), glow), head)
    parent(pivot("eyes", (0, -0.42, 1.64)), head)
    parent(head, torso)
    parent(torso, root)
    return [root]


def wraith() -> list:
    """A floating, hooded shroud with a lantern, bone hands and nothing in its hood."""
    robe = mat("fabric_shroud", (0.07, 0.07, 0.08), 0.95)
    lining = mat("plain_void", (0.0, 0.0, 0.0), 1.0)
    bone = mat("bone", (0.66, 0.62, 0.52), 0.7)
    iron = mat("metal_iron", (0.2, 0.19, 0.18), 0.5, 0.8)
    glow = mat("glow_teal", (0.3, 1.0, 0.85), emission=6.0)
    flame = mat("glow_lantern", (0.5, 1.0, 0.8), emission=4.0)
    root = pivot("wraith")
    body = pivot("float", (0, 0, 0))

    profile = [
        (0.0, 0.35),
        (0.44, 0.3),
        (0.4, 0.7),
        (0.33, 1.15),
        (0.27, 1.55),
        (0.3, 1.78),
        (0.2, 1.88),
        (0.0, 1.9),
    ]
    shroud = lathe(profile, (0, 0, 0), robe, segments=40, name="shroud")
    rng = random.Random(4)
    mesh = shroud.data
    for vert in mesh.vertices:  # type: ignore[union-attr]
        if vert.co.z < 0.45:  # Ragged hem.
            angle = math.atan2(vert.co.y, vert.co.x)
            vert.co.z -= 0.18 * (0.5 + 0.5 * math.sin(angle * 7)) + rng.uniform(0, 0.12)
        else:  # Hanging folds.
            angle = math.atan2(vert.co.y, vert.co.x)
            fold = 1 + 0.06 * math.sin(angle * 9) * (1.6 - vert.co.z) / 1.6
            vert.co.x *= fold
            vert.co.y *= fold
    parent(shroud, body)
    for _ in range(5):  # Loose strips trailing under the hem.
        angle = rng.uniform(0, 2 * math.pi)
        x, y = math.cos(angle) * 0.36, math.sin(angle) * 0.36
        strip = tube(
            [(x, y, 0.35), (x * 1.05, y * 1.05, 0.15), (x * 1.1, y * 1.1, 0.02)],
            [0.04, 0.03, 0.01],
            robe,
            5,
            "strip",
        )
        parent(strip, body)

    head = pivot("head", (0, -0.02, 1.88))
    hood = sphere(0.22, (0, 0.0, 2.02), robe, (1.0, 1.1, 1.15), segments=24)
    parent(hood, head)
    parent(sphere(0.17, (0, -0.1, 1.99), lining, (1.0, 0.9, 1.1), segments=20), head)
    peak = cyl(0.2, 0.0, 0.18, (0, 0.04, 2.25), robe, (0.35, 0, 0), 16)
    parent(peak, head)
    for side in (-1, 1):
        parent(sphere(0.022, (side * 0.06, -0.25, 2.02), glow, segments=12), head)
    parent(pivot("eyes", (0, -0.25, 2.02)), head)
    parent(head, body)

    for i, side in enumerate((-1, 1)):
        shoulder = pivot(f"arm_{i}", (side * 0.27, -0.02, 1.72))
        sleeve = tube(
            [
                (side * 0.27, -0.02, 1.72),
                (side * 0.36, -0.12, 1.4),
                (side * 0.38, -0.24, 1.15),
            ],
            [0.08, 0.1, 0.13],
            robe,
            12,
            "sleeve",
        )
        parent(sleeve, shoulder)
        wrist = (side * 0.38, -0.26, 1.08)
        parent(sphere(0.035, wrist, bone, segments=10), shoulder)
        for f in range(4):
            spread = (f - 1.5) * 0.022
            finger = [
                (side * 0.38 + spread, -0.27, 1.06),
                (side * 0.38 + spread * 1.5, -0.3, 0.92),
                (side * 0.38 + spread * 1.6, -0.27, 0.8),
            ]
            parent(tube(finger, [0.011, 0.009, 0.006], bone, 6, "finger"), shoulder)
        if side == 1:  # A lantern hanging from its right hand.
            top = (side * 0.38, -0.3, 0.86)
            chain = [top, (top[0], top[1], 0.72)]
            parent(tube(chain, 0.006, iron, 5, "chain"), shoulder)
            lamp_z = 0.6
            parent(cyl(0.07, 0.07, 0.02, (top[0], top[1], lamp_z + 0.11), iron), shoulder)
            parent(cyl(0.08, 0.08, 0.02, (top[0], top[1], lamp_z - 0.11), iron), shoulder)
            parent(cyl(0.05, 0.05, 0.18, (top[0], top[1], lamp_z), flame, segments=12), shoulder)
            for k in range(4):
                a = k * math.pi / 2 + math.pi / 4
                bar = (top[0] + math.cos(a) * 0.065, top[1] + math.sin(a) * 0.065, lamp_z)
                parent(box((0.012, 0.012, 0.22), bar, iron), shoulder)
            parent(cyl(0.07, 0.0, 0.08, (top[0], top[1], lamp_z + 0.16), iron), shoulder)
            parent(pivot("light", (top[0], top[1], lamp_z)), shoulder)
        parent(shoulder, body)
    parent(body, root)
    return [root]


def brute() -> list:
    """A hulking butcher in a bloodied apron, a sack over its head and a cleaver."""
    skin = mat("flesh_ruddy", (0.42, 0.28, 0.25), 0.6)
    apron = mat("leather_apron", (0.36, 0.32, 0.27), 0.8)
    blood = mat("plain_blood", (0.28, 0.02, 0.02), 0.35)
    sack = mat("fabric_sack", (0.5, 0.42, 0.3), 1.0)
    rope = mat("fabric_rope", (0.36, 0.3, 0.2), 1.0)
    steel = mat("metal_steel", (0.55, 0.56, 0.58), 0.35, 0.9)
    wood = mat("wood_handle", (0.3, 0.2, 0.12), 0.7)
    glow = mat("glow_orange", (1.0, 0.45, 0.08), emission=6.0)
    root = pivot("brute")

    for i, side in enumerate((-1, 1)):
        hip = pivot(f"leg_{i}", (side * 0.22, 0, 1.0))
        leg = blob(
            [
                ((side * 0.22, 0, 1.0), (side * 0.25, -0.03, 0.5), 0.14),
                ((side * 0.25, -0.03, 0.5), (side * 0.25, 0.02, 0.12), 0.11),
                ((side * 0.25, -0.05, 0.07), (side * 0.25, -0.2, 0.07), 0.08),
            ],
            skin,
            name=f"leg_mesh_{i}",
        )
        parent(leg, hip)
        parent(box((0.2, 0.32, 0.1), (side * 0.25, -0.1, 0.05), apron, 0.03), hip)  # Boot.
        parent(hip, root)

    torso = pivot("torso", (0, 0, 1.0))
    body = blob(
        [
            ((0, -0.05, 1.15), 0.3),
            ((0, -0.12, 1.35), 0.33),
            ((0, -0.05, 1.7), 0.34),
            ((-0.25, -0.02, 1.85), (0.25, -0.02, 1.85), 0.2),
            ((0, 0.12, 1.85), 0.25),
            ((0, -0.12, 1.92), (0, -0.2, 2.02), 0.13),
        ],
        skin,
        name="body",
    )
    parent(body, torso)
    # The apron wraps the belly: an arc of a cylinder round the body's axis.
    front = lib.sheet(0.42, 0.95, 2.0, 0.02, apron, (0, -0.08, 0.78), name="apron")
    parent(front, torso)
    for angle, z, s in (
        (-0.25, 1.2, 0.09),
        (0.3, 1.42, 0.07),
        (0.05, 1.02, 0.11),
        (-0.5, 1.5, 0.05),
    ):
        at = (0.43 * math.sin(angle), -0.08 - 0.43 * math.cos(angle), z)
        stain = sphere(s, at, blood, (1.0, 0.12, 1.4), (0, 0, angle), segments=10)
        parent(stain, torso)
    strap = [(-0.3, -0.42, 1.7), (-0.2, -0.32, 1.95), (0.0, -0.2, 2.05)]
    parent(tube(strap, 0.02, apron, 6, "strap"), torso)
    parent(tube(lib.mirror_x(strap), 0.02, apron, 6, "strap"), torso)

    for i, side in enumerate((-1, 1)):
        shoulder = pivot(f"arm_{i}", (side * 0.42, -0.03, 1.88))
        arm = blob(
            [
                ((side * 0.42, -0.03, 1.88), 0.17),
                ((side * 0.45, -0.03, 1.85), (side * 0.52, -0.08, 1.35), 0.13),
                ((side * 0.52, -0.08, 1.35), (side * 0.55, -0.16, 0.9), 0.12),
                ((side * 0.55, -0.18, 0.78), 0.12),
            ],
            skin,
            name=f"arm_mesh_{i}",
        )
        parent(arm, shoulder)
        if side == 1:  # The cleaver, blade down and forward.
            hand = (side * 0.55, -0.2, 0.76)
            parent(cyl(0.025, 0.025, 0.24, (hand[0], hand[1] - 0.04, hand[2]), wood), shoulder)
            blade = box((0.015, 0.34, 0.2), (hand[0], hand[1] - 0.22, hand[2] - 0.06), steel)
            parent(blade, shoulder)
            edge = box((0.016, 0.34, 0.02), (hand[0], hand[1] - 0.22, hand[2] - 0.155), blood)
            parent(edge, shoulder)
        parent(shoulder, torso)

    head = pivot("head", (0, -0.2, 2.02))
    hood = blob([((0, -0.22, 2.17), 0.17), ((0, -0.24, 2.27), 0.14)], sack, name="sack")
    parent(hood, head)
    collar = [
        (0.15 * math.cos(a), -0.2 + 0.13 * math.sin(a), 2.05)
        for a in (2 * math.pi * k / 12 for k in range(13))
    ]
    parent(tube(collar, 0.02, rope, 6, "rope"), head)
    for side in (-1, 1):
        parent(sphere(0.03, (side * 0.07, -0.375, 2.21), glow, (1, 0.6, 1), segments=12), head)
        for k in range(3):  # Crude stitches round each eye.
            a = k * 2.1
            at = (side * 0.07 + math.cos(a) * 0.045, -0.38, 2.21 + math.sin(a) * 0.045)
            parent(box((0.006, 0.01, 0.03), at, rope, rot=(0, a, 0)), head)
    parent(box((0.11, 0.02, 0.012), (0, -0.375, 2.1), rope), head)
    parent(pivot("eyes", (0, -0.39, 2.21)), head)
    parent(head, torso)
    parent(torso, root)
    return [root]


MONSTERS = {"stalker": stalker, "crawler": crawler, "wraith": wraith, "brute": brute}


def main(only: set[str]) -> None:
    """Builds the monsters named in only, or all of them when it is empty."""
    for name, make in MONSTERS.items():
        if only and name not in only:
            continue
        lib.reset()
        roots = make()
        lo, hi = lib.bounds(roots)
        lib.export(OUT / f"{name}.glb", roots)
        size = hi - lo
        print(f"[monsters] {name}: {size.x:.2f} wide, {size.y:.2f} deep, {size.z:.2f} tall")
