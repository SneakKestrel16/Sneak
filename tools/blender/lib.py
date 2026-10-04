"""Shared helpers for the Blender model scripts: primitives, materials and export.

Coordinates are Blender's: Z up, and every model faces -Y, which the glTF exporter turns
into Godot's +Z. Material names choose how Godot dresses the surface (`Models.dress` in
scripts/models.gd): the part before the first underscore is the preset ("wood", "metal",
"glow", ...); a name starting "tint_" is recoloured per item.
"""

import json
import math
from collections.abc import Iterable, Sequence
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / "assets" / "models"

Vec = Sequence[float]

# Surface radius of a lone metaball element as a share of its radius, at the default
# threshold and stiffness 2 (measured: 0.575). Blob sizes are given as surface radii.
META_SURFACE = 0.575

_materials: dict[str, bpy.types.Material] = {}


def reset() -> None:
    """Empties the scene and forgets cached materials."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for meta in list(bpy.data.metaballs):
        bpy.data.metaballs.remove(meta)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    _materials.clear()


def mat(
    name: str,
    color: Vec,
    roughness: float = 0.6,
    metallic: float = 0.0,
    emission: float = 0.0,
) -> bpy.types.Material:
    """A Principled material, shared by name; Godot reads its name and base colour.

    color is in sRGB, like the colours in the GDScript, and stored linear as Blender and
    glTF expect, so Godot reads back the same numbers.
    """
    if name in _materials:
        return _materials[name]
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    assert tree is not None
    bsdf = tree.nodes["Principled BSDF"]
    rgba = (*(_linear(c) for c in color[:3]), 1.0)
    bsdf.inputs["Base Color"].default_value = rgba  # type: ignore[attr-defined]
    bsdf.inputs["Roughness"].default_value = roughness  # type: ignore[attr-defined]
    bsdf.inputs["Metallic"].default_value = metallic  # type: ignore[attr-defined]
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = rgba  # type: ignore[attr-defined]
        bsdf.inputs["Emission Strength"].default_value = emission  # type: ignore[attr-defined]
    _materials[name] = material
    return material


def _linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _link(name: str, mesh: bpy.types.Mesh, material: bpy.types.Material | None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, mesh)
    scene = bpy.context.scene
    assert scene is not None
    scene.collection.objects.link(obj)
    if material is not None:
        mesh.materials.append(material)
    return obj


def _place(obj: bpy.types.Object, at: Vec, rot: Vec) -> bpy.types.Object:
    obj.location = Vector(at)
    obj.rotation_euler = (rot[0], rot[1], rot[2])
    _refresh()
    return obj


def _refresh() -> None:
    """Recomputes world matrices, which Blender leaves stale after a script moves things."""
    layer = bpy.context.view_layer
    assert layer is not None
    layer.update()


def _from_bmesh(
    name: str, bm: bmesh.types.BMesh, material: bpy.types.Material | None, smooth: bool
):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    return _link(name, mesh, material)


def box(
    size: Vec,
    at: Vec = (0, 0, 0),
    material: bpy.types.Material | None = None,
    bevel: float = 0.0,
    rot: Vec = (0, 0, 0),
    name: str = "box",
) -> bpy.types.Object:
    """A box of size (x, y, z) centred on at, with optionally bevelled edges."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=tuple(size), verts=list(bm.verts))
    if bevel > 0.0:
        bevel = min(bevel, min(size) * 0.45)
        bmesh.ops.bevel(
            bm, geom=list(bm.edges), offset=bevel, segments=2, profile=0.5, affect="EDGES"
        )
    return _place(_from_bmesh(name, bm, material, False), at, rot)


def cyl(
    r_bottom: float,
    r_top: float,
    height: float,
    at: Vec = (0, 0, 0),
    material: bpy.types.Material | None = None,
    rot: Vec = (0, 0, 0),
    segments: int = 24,
    name: str = "cyl",
) -> bpy.types.Object:
    """A cylinder or cone along local Z, centred on at."""
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        segments=segments,
        radius1=r_bottom,
        radius2=r_top,
        depth=height,
    )
    obj = _from_bmesh(name, bm, material, segments > 8)
    _sharpen_caps(obj)
    return _place(obj, at, rot)


def _sharpen_caps(obj: bpy.types.Object) -> None:
    mesh = obj.data
    assert isinstance(mesh, bpy.types.Mesh)
    for poly in mesh.polygons:
        if abs(poly.normal.z) > 0.99:
            poly.use_smooth = False


def sphere(
    radius: float,
    at: Vec = (0, 0, 0),
    material: bpy.types.Material | None = None,
    scale: Vec = (1, 1, 1),
    rot: Vec = (0, 0, 0),
    segments: int = 24,
    name: str = "sphere",
) -> bpy.types.Object:
    """A UV sphere, optionally squashed by scale."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2, radius=radius)
    bmesh.ops.scale(bm, vec=tuple(scale), verts=list(bm.verts))
    return _place(_from_bmesh(name, bm, material, segments > 6), at, rot)


def torus(
    major: float,
    minor: float,
    at: Vec = (0, 0, 0),
    material: bpy.types.Material | None = None,
    rot: Vec = (0, 0, 0),
    segments: int = 32,
    name: str = "torus",
) -> bpy.types.Object:
    """A ring in the local XY plane."""
    profile = [
        (major + minor * math.cos(a), minor * math.sin(a))
        for a in (2 * math.pi * i / 12 for i in range(12))
    ]
    return lathe(profile, at, material, rot, segments, closed=True, name=name)


def lathe(
    profile: Sequence[tuple[float, float]],
    at: Vec = (0, 0, 0),
    material: bpy.types.Material | None = None,
    rot: Vec = (0, 0, 0),
    segments: int = 32,
    closed: bool = False,
    smooth: bool = True,
    name: str = "lathe",
) -> bpy.types.Object:
    """Spins a (radius, height) profile round local Z: vases, bottles, lamp bases.

    A profile point with radius 0 sits on the axis and closes the shape there.
    """
    bm = bmesh.new()
    rings: list[list[bmesh.types.BMVert]] = []
    for i in range(segments):
        angle = 2 * math.pi * i / segments
        c, s = math.cos(angle), math.sin(angle)
        rings.append([bm.verts.new((r * c, r * s, z)) for r, z in profile])
    count = len(profile)
    last = count if closed else count - 1
    for i in range(segments):
        a, b = rings[i], rings[(i + 1) % segments]
        for j in range(last):
            k = (j + 1) % count
            quad = [a[j], b[j], b[k], a[k]]
            unique = list(dict.fromkeys(quad))
            if len(unique) >= 3:
                bm.faces.new(unique)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return _place(_from_bmesh(name, bm, material, smooth), at, rot)


def tube(
    points: Sequence[Vec],
    radius: float | Sequence[float],
    material: bpy.types.Material | None = None,
    sides: int = 10,
    name: str = "tube",
) -> bpy.types.Object:
    """A smooth tube through points, its radius constant or one per point; ends capped."""
    radii = [radius] * len(points) if isinstance(radius, (int, float)) else list(radius)
    pts = [Vector(p) for p in points]
    bm = bmesh.new()
    rings: list[list[bmesh.types.BMVert]] = []
    up = Vector((0, 0, 1))
    for i, p in enumerate(pts):
        after, before = pts[min(i + 1, len(pts) - 1)], pts[max(i - 1, 0)]
        ahead = Vector((after.x - before.x, after.y - before.y, after.z - before.z))
        ahead.normalize()
        side = _cross(ahead, up if abs(ahead.dot(up)) < 0.9 else Vector((1, 0, 0)))
        side.normalize()
        normal = _cross(side, ahead)
        ring = []
        for j in range(sides):
            angle = 2 * math.pi * j / sides
            offset = (side * math.cos(angle) + normal * math.sin(angle)) * radii[i]
            ring.append(bm.verts.new((p + offset).to_tuple()))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new([rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return _from_bmesh(name, bm, material, True)


def sheet(
    radius: float,
    height: float,
    arc: float,
    thickness: float,
    material: bpy.types.Material | None = None,
    base: Vec = (0, 0, 0),
    name: str = "sheet",
) -> bpy.types.Object:
    """A curved panel: arc radians of a cylinder wall round local Z, centred on -Y.

    For aprons, cloth and anything that wraps a round body. base is the axis at the bottom.
    """
    bm = bmesh.new()
    columns = 16
    rings = []
    for i in range(columns + 1):
        angle = -arc / 2 + arc * i / columns
        rings.append(
            [
                bm.verts.new((r * math.sin(angle), -r * math.cos(angle), z))
                for r, z in (
                    (radius, 0),
                    (radius, height),
                    (radius + thickness, height),
                    (radius + thickness, 0),
                )
            ]
        )
    for i in range(columns):
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new([rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]])
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return _place(_from_bmesh(name, bm, material, False), base, (0, 0, 0))


def _cross(a: Vector, b: Vector) -> Vector:
    """The 3D cross product (the stubs type Vector.cross as maybe a float, for 2D)."""
    return Vector((a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x))


def blob(
    elements: Iterable[tuple[Vec, float] | tuple[Vec, Vec, float]],
    material: bpy.types.Material,
    resolution: float = 0.03,
    name: str = "blob",
) -> bpy.types.Object:
    """Fused organic flesh from metaballs, converted to a mesh.

    Each element is (centre, radius) for a ball or (a, b, radius) for a capsule from a to b.
    Radii are of the visible surface; neighbouring elements melt together.
    """
    meta = bpy.data.metaballs.new(name)
    meta.resolution = resolution
    meta.render_resolution = resolution
    for element in elements:
        if len(element) == 2:
            centre, radius = element  # type: ignore[misc]
            ball = meta.elements.new(type="BALL")
            ball.co = Vector(centre)
            ball.radius = radius / META_SURFACE
        else:
            a, b, radius = element  # type: ignore[misc]
            va, vb = Vector(a), Vector(b)
            capsule = meta.elements.new(type="CAPSULE")
            capsule.co = (va + vb) / 2.0
            capsule.radius = radius / META_SURFACE
            span = vb - va
            capsule.size_x = max(span.length / 2.0 - radius * 0.5, 0.001)
            capsule.rotation = Vector((1, 0, 0)).rotation_difference(span.normalized())
    holder = bpy.data.objects.new(name + "_meta", meta)
    scene = bpy.context.scene
    assert scene is not None
    scene.collection.objects.link(holder)
    graph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(holder.evaluated_get(graph))
    bpy.data.objects.remove(holder)
    bpy.data.metaballs.remove(meta)
    mesh.materials.clear()
    for poly in mesh.polygons:
        poly.use_smooth = True
    return _link(name, mesh, material)


def pivot(name: str, at: Vec = (0, 0, 0), rot: Vec = (0, 0, 0)) -> bpy.types.Object:
    """An empty to hang parts on, which Godot animates by name (monsters)."""
    obj = bpy.data.objects.new(name, None)
    scene = bpy.context.scene
    assert scene is not None
    scene.collection.objects.link(obj)
    return _place(obj, at, rot)


def join(parts: Sequence[bpy.types.Object], name: str) -> bpy.types.Object:
    """Merges mesh parts into one object (one draw per material in Godot)."""
    _refresh()
    meshes = [p for p in parts if p.type == "MESH"]
    target = meshes[0]
    bm = bmesh.new()
    materials: list[bpy.types.Material] = []
    for part in meshes:
        mesh = part.data
        assert isinstance(mesh, bpy.types.Mesh)
        remap = []
        for material in mesh.materials:
            assert material is not None
            if material not in materials:
                materials.append(material)
            remap.append(materials.index(material))
        piece = bmesh.new()
        piece.from_mesh(mesh)
        piece.transform(target.matrix_world.inverted() @ part.matrix_world)
        for face in piece.faces:
            face.material_index = remap[face.material_index] if remap else 0
        temp = bpy.data.meshes.new("temp")
        piece.to_mesh(temp)
        piece.free()
        bm.from_mesh(temp)
        bpy.data.meshes.remove(temp)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for material in materials:
        mesh.materials.append(material)
    obj = _link(name, mesh, None)
    obj.matrix_world = target.matrix_world.copy()
    _refresh()
    for part in meshes:
        bpy.data.objects.remove(part)
    return obj


def parent(child: bpy.types.Object, holder: bpy.types.Object) -> None:
    """Parents child to holder, keeping where child is in the world."""
    _refresh()
    world = child.matrix_world.copy()
    child.parent = holder
    child.matrix_parent_inverse = holder.matrix_world.inverted()
    child.matrix_world = world


def mirror_x(points: Sequence[Vec]) -> list[tuple[float, float, float]]:
    """Points reflected across the YZ plane, for the other side of a body."""
    return [(-p[0], p[1], p[2]) for p in points]


def rotated(vec: Vec, angle_z: float) -> tuple[float, float, float]:
    """Vec turned angle_z radians round Z."""
    v = Matrix.Rotation(angle_z, 3, "Z") @ Vector(vec)
    return (v.x, v.y, v.z)


def bounds(objs: Sequence[bpy.types.Object]) -> tuple[Vector, Vector]:
    """World-space min and max corners of the meshes among objs and their children."""
    _refresh()
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    stack = list(objs)
    while stack:
        obj = stack.pop()
        stack.extend(obj.children)
        if obj.type != "MESH":
            continue
        mesh = obj.data
        assert isinstance(mesh, bpy.types.Mesh)
        for vert in mesh.vertices:  # Not bound_box, which overstates anything turned.
            world = obj.matrix_world @ vert.co
            lo = Vector((min(lo.x, world.x), min(lo.y, world.y), min(lo.z, world.z)))
            hi = Vector((max(hi.x, world.x), max(hi.y, world.y), max(hi.z, world.z)))
    return lo, hi


def consolidate(holder: bpy.types.Object) -> None:
    """Joins the mesh children of holder and of every empty below it, one mesh per empty.

    Godot gets one node per joint instead of one per tooth.
    """
    for child in list(holder.children):
        if child.type == "EMPTY":
            consolidate(child)
    meshes = [c for c in holder.children if c.type == "MESH"]
    if holder.type == "EMPTY" and len(meshes) > 1:
        merged = join(meshes, holder.name + "_mesh")
        parent(merged, holder)


def export(path: Path, roots: Sequence[bpy.types.Object]) -> None:
    """Writes roots and their children as a binary glTF at path."""
    for root in roots:
        consolidate(root)
    bpy.ops.object.select_all(action="DESELECT")
    stack = list(roots)
    while stack:
        obj = stack.pop()
        obj.select_set(True)
        stack.extend(obj.children)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=False,
        export_animations=False,
        export_extras=False,
    )


def write_catalogue(name: str, entries: list[dict[str, object]]) -> None:
    """Writes the list of models a script made, with their measured sizes, for Godot."""
    path = MODELS / f"{name}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(entries, indent="\t") + "\n").encode())
