"""Build UZI RUSH's low-poly PSX models in Blender and export them as .glb.

Run headless (from the repo root):
    blender -b --factory-startup --python tools/blender_models.py            # everything
    blender -b --factory-startup --python tools/blender_models.py -- uzi grunt

All coordinates are written in Godot space (x right, y up, z toward the viewer) and converted
to Blender space (z up) when vertices are created. Enemies face +Z (Godot yaws them toward
the player). The first-person Uzi points down -Z so it can be parented straight to the camera.
The arena also writes levels/arena.json (collision boxes + spawn gates) so the game and the
model can never disagree about where the walls are.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models")
LEVELS = os.path.join(ROOT, "levels")

PREVIEW_COLORS = {
    "GunMetal": (0.25, 0.26, 0.3), "GunDark": (0.08, 0.08, 0.1), "Glove": (0.1, 0.1, 0.12),
    "Sleeve": (0.15, 0.3, 0.55), "Brass": (0.9, 0.7, 0.2),
    "BotBody": (0.7, 0.4, 0.2), "BotDark": (0.2, 0.2, 0.24), "BotPanel": (0.3, 0.8, 0.9), "EyeGlow": (1.0, 0.1, 0.1),
    "GunnerBody": (0.4, 0.3, 0.7), "VisorGlow": (1.0, 0.9, 0.2),
    "BruteArmor": (0.55, 0.55, 0.6), "BruteDark": (0.15, 0.15, 0.18), "BossArmor": (0.7, 0.1, 0.15),
    "DroneBody": (0.3, 0.7, 0.4), "Rotor": (0.8, 0.8, 0.8),
    "Medkit": (0.95, 0.95, 0.95), "MedCross": (0.9, 0.1, 0.1), "Orb": (1.0, 0.8, 0.2), "Grenade": (0.3, 0.45, 0.25),
    "Floor": (0.4, 0.4, 0.45), "Wall": (0.35, 0.3, 0.45), "Hazard": (0.9, 0.75, 0.1), "Crate": (0.6, 0.45, 0.25),
    "Pillar": (0.5, 0.5, 0.55), "NeonPink": (1, 0.2, 0.7), "NeonCyan": (0.2, 0.9, 1), "Gate": (0.05, 0.02, 0.05),
    "Sign": (1, 1, 1), "Skyline": (0.2, 0.1, 0.3), "Stage": (0.3, 0.3, 0.4), "Barrier": (0.6, 0.6, 0.6),
}


def G(x, y, z):
    """Godot-space point -> Blender-space vector."""
    return Vector((x, -z, y))


def get_material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        col = PREVIEW_COLORS.get(name, (0.8, 0.8, 0.8))
        m.diffuse_color = (*col, 1.0)
    return m


def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)


class MB:
    """Tiny mesh builder working in Godot coordinates."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []

    def mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def face(self, pts, mat, hint=None, uvs=None, uv_mode="box", uv_scale=1.0, smooth=False):
        """pts: Godot-space points. hint: outward direction (Godot space) to fix winding."""
        verts = [self.bm.verts.new(G(*p)) for p in pts]
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None
        f.material_index = self.mi(mat)
        f.smooth = smooth
        f.normal_update()
        n_g = Vector((f.normal.x, f.normal.z, -f.normal.y))  # blender normal -> godot
        if hint is not None and n_g.dot(Vector(hint)) < 0:
            f.normal_flip()
            f.normal_update()
            n_g = Vector((f.normal.x, f.normal.z, -f.normal.y))
        loops = list(f.loops)
        if uvs is not None:
            # loops follow the (possibly flipped) vertex order; match by vertex identity
            for loop in loops:
                idx = verts.index(loop.vert)
                loop[self.uv].uv = uvs[idx]
        elif uv_mode == "box":
            ax = max(range(3), key=lambda i: abs(n_g[i]))
            for loop in loops:
                gp = pts[verts.index(loop.vert)]
                x, y, z = gp
                if ax == 0:
                    u, v = (-z if n_g[0] > 0 else z), -y
                elif ax == 1:
                    u, v = x, (z if n_g[1] > 0 else -z)
                else:
                    u, v = (x if n_g[2] > 0 else -x), -y
                loop[self.uv].uv = (u * uv_scale, -v * uv_scale)
        elif uv_mode == "fit":
            ax = max(range(3), key=lambda i: abs(n_g[i]))
            proj = []
            for p in pts:
                x, y, z = p
                if ax == 0:
                    proj.append(((-z if n_g[0] > 0 else z), y))
                elif ax == 1:
                    proj.append((x, (-z if n_g[1] > 0 else z)))
                else:
                    proj.append(((x if n_g[2] > 0 else -x), y))
            us = [q[0] for q in proj]
            vs = [q[1] for q in proj]
            u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
            for loop in loops:
                q = proj[verts.index(loop.vert)]
                loop[self.uv].uv = ((q[0] - u0) / max(1e-6, u1 - u0), (q[1] - v0) / max(1e-6, v1 - v0))
        return f

    def box(self, c, s, mat, taper=(1.0, 1.0), uv_scale=1.0, face_mats=None, fit_faces=(), uv_rects=None):
        """Axis-aligned (optionally top-tapered) box. face keys: px nx py ny pz nz."""
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        tx, tz = taper
        b = [(cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz + hz),
             (cx - hx, cy - hy, cz + hz)]
        t = [(cx - hx * tx, cy + hy, cz - hz * tz), (cx + hx * tx, cy + hy, cz - hz * tz),
             (cx + hx * tx, cy + hy, cz + hz * tz), (cx - hx * tx, cy + hy, cz + hz * tz)]
        faces = {
            "ny": ([b[0], b[1], b[2], b[3]], (0, -1, 0)),
            "py": ([t[3], t[2], t[1], t[0]], (0, 1, 0)),
            "pz": ([b[3], b[2], t[2], t[3]], (0, 0, 1)),
            "nz": ([b[1], b[0], t[0], t[1]], (0, 0, -1)),
            "px": ([b[2], b[1], t[1], t[2]], (1, 0, 0)),
            "nx": ([b[0], b[3], t[3], t[0]], (-1, 0, 0)),
        }
        face_mats = face_mats or {}
        for key, (pts, n) in faces.items():
            m = face_mats.get(key, mat)
            if m is None:
                continue
            if uv_rects and key in uv_rects:
                u0, v0, u1, v1 = uv_rects[key]
                f = self.face(pts, m, hint=n, uv_mode="fit")
                for loop in f.loops:
                    uu, vv = loop[self.uv].uv
                    loop[self.uv].uv = (u0 + (u1 - u0) * uu, v0 + (v1 - v0) * vv)
            else:
                self.face(pts, m, hint=n, uv_mode="fit" if key in fit_faces else "box", uv_scale=uv_scale)

    def cyl(self, p0, p1, r0, r1, seg, mat, caps=True, v0=0.0, v1=1.0, smooth=True, cap_mat=None):
        a, bvec = Vector(p0), Vector(p1)
        axis = (bvec - a).normalized()
        ref = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))
        u = axis.cross(ref).normalized()
        w = axis.cross(u).normalized()

        def ring(center, r):
            return [tuple(center + (u * math.cos(TAU * i / seg) + w * math.sin(TAU * i / seg)) * r)
                    for i in range(seg)]

        ra = ring(a, r0)
        rb = ring(bvec, r1) if r1 > 1e-6 else None
        for i in range(seg):
            j = (i + 1) % seg
            ui, uj = i / seg, (i + 1) / seg
            mid_dir = tuple((u * math.cos(TAU * (i + 0.5) / seg) + w * math.sin(TAU * (i + 0.5) / seg)))
            if rb is None:
                self.face([ra[i], ra[j], tuple(bvec)], mat, hint=mid_dir,
                          uvs=[(ui, 1 - v0), (uj, 1 - v0), ((ui + uj) / 2, 1 - v1)], smooth=smooth)
            else:
                self.face([ra[i], ra[j], rb[j], rb[i]], mat, hint=mid_dir,
                          uvs=[(ui, 1 - v0), (uj, 1 - v0), (uj, 1 - v1), (ui, 1 - v1)], smooth=smooth)
        if caps:
            cm = cap_mat or mat
            self.face(list(reversed(ra)), cm, hint=tuple(-axis), uv_mode="box", uv_scale=4)
            if rb is not None:
                self.face(rb, cm, hint=tuple(axis), uv_mode="box", uv_scale=4)

    def sphere(self, c, radii, seg, rings, mat, smooth=True):
        cx, cy, cz = c
        rx, ry, rz = radii

        def P(i, j):
            th = math.pi * i / rings
            ph = TAU * j / seg
            return (cx + rx * math.sin(th) * math.sin(ph), cy + ry * math.cos(th), cz + rz * math.sin(th) * math.cos(ph))

        for i in range(rings):
            for j in range(seg):
                u0, u1 = j / seg, (j + 1) / seg
                va, vb = i / rings, (i + 1) / rings
                if i == 0:
                    pts = [P(0, j), P(1, j), P(1, j + 1)]
                    uvs = [((u0 + u1) / 2, 1 - va), (u0, 1 - vb), (u1, 1 - vb)]
                elif i == rings - 1:
                    pts = [P(i, j), P(rings, j), P(i, j + 1)]
                    uvs = [(u0, 1 - va), ((u0 + u1) / 2, 1 - vb), (u1, 1 - va)]
                else:
                    pts = [P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]
                    uvs = [(u0, 1 - va), (u0, 1 - vb), (u1, 1 - vb), (u1, 1 - va)]
                cen = Vector((sum(p[0] for p in pts) / len(pts) - cx, sum(p[1] for p in pts) / len(pts) - cy,
                              sum(p[2] for p in pts) / len(pts) - cz))
                self.face(pts, mat, hint=tuple(cen), uvs=uvs, smooth=smooth)

    def quad(self, pts, mat, normal, uvs=None, uv_scale=1.0, uv_mode="box"):
        self.face(pts, mat, hint=normal, uvs=uvs, uv_scale=uv_scale, uv_mode=uv_mode)

    def build(self, name, parent=None, loc=(0, 0, 0)):
        mesh = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(get_material(m))
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if parent is not None:
            obj.parent = parent
        obj.location = G(*loc)
        return obj


TAU = math.pi * 2


def empty(name, parent=None, loc=(0, 0, 0)):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    if parent is not None:
        o.parent = parent
    o.location = G(*loc)
    return o


def export(name):
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB")
    tris = 0
    for o in bpy.data.objects:
        if o.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    print(f"exported {name}.glb  ({tris} tris)")

def grid(m, x0, x1, z0, z1, step_x, step_z, y, mat, uv_scale, hole=None):
    """Subdivided ground grid. `hole` = (x0, x1, z0, z1) region left empty so layered
    ground materials never overlap (PSX vertex jitter makes overlapping planes z-fight)."""
    nx = max(1, int(round((x1 - x0) / step_x)))
    nz = max(1, int(round((z1 - z0) / step_z)))
    for i in range(nx):
        for j in range(nz):
            a = x0 + (x1 - x0) * i / nx
            b = x0 + (x1 - x0) * (i + 1) / nx
            c = z0 + (z1 - z0) * j / nz
            d = z0 + (z1 - z0) * (j + 1) / nz
            if hole and a >= hole[0] - 1e-6 and b <= hole[1] + 1e-6 and c >= hole[2] - 1e-6 and d <= hole[3] + 1e-6:
                continue
            m.quad([(a, y, d), (b, y, d), (b, y, c), (a, y, c)], mat, (0, 1, 0), uv_scale=uv_scale)


def rot(p, k):
    """Rotate a Godot-space point by k quarter turns around +Y."""
    x, y, z = p
    for _ in range(k % 4):
        x, z = z, -x
    return (x, y, z)


def rquad(m, k, pts, mat, normal, uvs):
    m.quad([rot(p, k) for p in pts], mat, rot(normal, k), uvs=uvs)


def rbox(m, k, c, s, mat, **kw):
    s2 = (s[2], s[1], s[0]) if k % 2 else s
    m.box(rot(c, k), s2, mat, **kw)


def rstrip(m, k, x0, x1, y0, y1, z, mat, seg_w, u_per_m, v0=0.0, v1=1.0):
    """Like vstrip (strip along x at depth z facing +z) but rotated to side k."""
    n = max(1, int(math.ceil((x1 - x0) / seg_w)))
    for i in range(n):
        a = x0 + (x1 - x0) * i / n
        b = x0 + (x1 - x0) * (i + 1) / n
        rquad(m, k, [(a, y0, z), (b, y0, z), (b, y1, z), (a, y1, z)], mat, (0, 0, 1),
              [(a * u_per_m, 1 - v1), (b * u_per_m, 1 - v1), (b * u_per_m, 1 - v0), (a * u_per_m, 1 - v0)])



TAU = math.pi * 2


# ----------------------------------------------------------------- the Uzi
def uzi(side="R"):
    """First-person Uzi + gloved hand + sleeve. Origin = grip, barrel points down -Z, the
    forearm trails back (+Z) and out/down toward the screen corner. side R/L mirrors in X."""
    reset()
    sx = 1 if side == "R" else -1
    root = empty("Uzi" + side)
    m = MB()
    # receiver + top cover + sights
    m.box((0, 0.045, -0.15), (0.07, 0.075, 0.34), "GunMetal")
    m.box((0, 0.088, -0.15), (0.052, 0.018, 0.30), "GunDark")
    m.box((0, 0.108, -0.30), (0.012, 0.03, 0.012), "GunDark")
    m.box((0, 0.105, -0.0), (0.034, 0.024, 0.02), "GunDark")
    # shroud + barrel + muzzle brake
    m.box((0, 0.045, -0.37), (0.052, 0.052, 0.12), "GunMetal")
    m.cyl((0, 0.045, -0.43), (0, 0.045, -0.52), 0.015, 0.015, 6, "GunDark")
    m.box((0, 0.045, -0.50), (0.034, 0.034, 0.03), "GunMetal")
    # grip / magazine + trigger guard + folded wire stock
    m.box((0, -0.09, -0.012), (0.05, 0.22, 0.064), "GunDark")
    m.box((0, -0.205, -0.012), (0.056, 0.02, 0.07), "GunMetal")
    m.box((0, -0.012, -0.1), (0.012, 0.028, 0.11), "GunMetal")
    m.cyl((0, 0.06, 0.02), (0, 0.06, 0.24), 0.009, 0.009, 4, "GunMetal")
    m.box((0, 0.06, 0.25), (0.05, 0.05, 0.012), "GunMetal")
    # ejection port + selector
    m.box((sx * 0.037, 0.058, -0.12), (0.006, 0.03, 0.07), "GunDark")
    m.box((-sx * 0.037, 0.03, -0.04), (0.008, 0.02, 0.03), "Brass")
    m.build("Gun", root)

    m = MB()
    # gloved hand wrapped round the grip
    m.box((0, -0.05, 0.005), (0.088, 0.105, 0.098), "Glove")
    m.box((0, -0.038, -0.065), (0.082, 0.03, 0.04), "Glove")
    m.box((0, -0.075, -0.065), (0.082, 0.028, 0.04), "Glove")
    m.box((sx * 0.048, 0.0, -0.03), (0.032, 0.045, 0.075), "Glove")       # thumb
    m.box((-sx * 0.046, -0.01, -0.055), (0.025, 0.03, 0.03), "Glove")     # trigger finger
    # wrist cuff + sleeve trailing back toward the camera
    m.cyl((0.0, -0.07, 0.05), (sx * 0.07, -0.16, 0.34), 0.052, 0.06, 6, "Glove", caps=False)
    m.cyl((sx * 0.07, -0.16, 0.34), (sx * 0.17, -0.27, 0.72), 0.064, 0.074, 6, "Sleeve")
    m.build("Hand", root)
    empty("Muzzle", root, (0, 0.045, -0.54))
    export("uzi_" + side.lower())


# --------------------------------------------------------------- enemy parts
def _legs(hips, body, dark, foot_len=0.27, w=0.165, thigh=0.42, shin=0.4, spread=0.1):
    for side, sx in (("R", -1), ("L", 1)):
        m = MB()
        m.box((0, -thigh / 2, 0), (w, thigh, w * 1.05), body, taper=(0.85, 0.9))
        leg = m.build("Leg" + side, hips, (spread * sx, -0.02, 0))
        m = MB()
        m.box((0, -shin / 2 + 0.01, 0), (w * 0.85, shin, w * 0.9), dark, taper=(1.05, 1.05))
        shin_o = m.build("Shin" + side, leg, (0, -thigh - 0.01, 0))
        m = MB()
        m.box((0, -0.035, 0.05), (w * 0.9, 0.09, foot_len), dark, taper=(0.95, 0.85))
        m.build("Foot" + side, shin_o, (0, -shin, 0))


def grunt():
    """SCRAPPER: rusty zombie-robot. Arms hang from the shoulders (Godot swings them forward)."""
    reset()
    root = empty("Grunt")
    m = MB()
    m.box((0, 0.02, 0), (0.36, 0.2, 0.24), "BotDark")
    hips = m.build("Hips", root, (0, 0.88, 0))
    m = MB()
    m.box((0, 0.27, 0), (0.46, 0.55, 0.3), "BotBody", taper=(1.15, 1.05))
    m.box((0, 0.3, 0.156), (0.3, 0.22, 0.02), "BotPanel")
    m.box((0.13, 0.07, 0.152), (0.07, 0.07, 0.016), "BotDark")
    m.box((0, 0.58, 0), (0.12, 0.08, 0.12), "BotDark")
    m.box((-0.05, 0.5, -0.16), (0.2, 0.3, 0.06), "BotDark")                 # back vent
    torso = m.build("Torso", hips, (0, 0.12, 0))
    m = MB()
    m.box((0, 0.14, 0), (0.3, 0.27, 0.28), "BotBody")
    m.box((0, 0.165, 0.146), (0.26, 0.075, 0.02), "EyeGlow")
    m.box((0, 0.04, 0.12), (0.2, 0.05, 0.06), "BotDark")                    # jaw
    m.cyl((0.1, 0.27, 0), (0.13, 0.48, -0.03), 0.012, 0.012, 4, "BotDark")
    m.box((0.13, 0.49, -0.03), (0.04, 0.04, 0.04), "EyeGlow")
    m.build("Head", torso, (0, 0.6, 0))
    for side, sx in (("R", -1), ("L", 1)):
        m = MB()
        m.box((0, 0, 0), (0.17, 0.15, 0.17), "BotDark")
        m.box((0, -0.15, 0), (0.12, 0.3, 0.12), "BotBody")
        arm = m.build("Arm" + side, torso, (0.31 * sx, 0.46, 0))
        m = MB()
        m.box((0, -0.14, 0), (0.105, 0.3, 0.105), "BotDark")
        fore = m.build("Forearm" + side, arm, (0, -0.3, 0))
        m = MB()
        m.box((0, -0.04, 0), (0.13, 0.1, 0.075), "BotBody")
        m.box((0.045, -0.12, 0), (0.03, 0.11, 0.03), "BotDark")
        m.box((-0.045, -0.12, 0), (0.03, 0.11, 0.03), "BotDark")
        m.box((0, -0.12, 0.035), (0.03, 0.11, 0.03), "BotDark")
        m.build("Hand" + side, fore, (0, -0.3, 0))
    _legs(hips, "BotDark", "BotBody")
    export("grunt")


def gunner():
    """SENTRY: lanky blue bot with an arm cannon aimed along +Z and a glowing visor."""
    reset()
    root = empty("Gunner")
    m = MB()
    m.box((0, 0.02, 0), (0.3, 0.2, 0.2), "BotDark")
    hips = m.build("Hips", root, (0, 0.92, 0))
    m = MB()
    m.box((0, 0.27, 0), (0.38, 0.55, 0.26), "GunnerBody", taper=(1.25, 1.0))
    m.box((0, 0.3, 0.136), (0.18, 0.18, 0.02), "VisorGlow")
    m.box((0, 0.55, 0), (0.1, 0.08, 0.1), "BotDark")
    m.box((0, 0.3, -0.19), (0.26, 0.38, 0.12), "BotDark")                   # power pack
    m.cyl((-0.08, 0.5, -0.19), (-0.08, 0.82, -0.2), 0.012, 0.012, 4, "BotDark")
    torso = m.build("Torso", hips, (0, 0.12, 0))
    m = MB()
    m.box((0, 0.13, 0), (0.26, 0.24, 0.25), "GunnerBody")
    m.box((0, 0.15, 0.13), (0.24, 0.08, 0.025), "VisorGlow")
    m.box((0, 0.27, 0), (0.28, 0.04, 0.27), "BotDark")                      # brim
    m.build("Head", torso, (0, 0.55, 0))
    # left arm hangs + swings
    m = MB()
    m.box((0, 0, 0), (0.14, 0.13, 0.14), "BotDark")
    m.box((0, -0.15, 0), (0.1, 0.3, 0.1), "GunnerBody")
    arm = m.build("ArmL", torso, (0.26, 0.44, 0))
    m = MB()
    m.box((0, -0.14, 0), (0.09, 0.28, 0.09), "BotDark")
    m.box((0, -0.3, 0), (0.1, 0.1, 0.1), "GunnerBody")
    m.build("ForearmL", arm, (0, -0.3, 0))
    # right arm = static cannon pointing forward
    m = MB()
    m.box((0, 0, 0), (0.14, 0.13, 0.14), "BotDark")
    m.cyl((0, -0.02, 0.0), (0, -0.05, 0.3), 0.055, 0.05, 6, "GunnerBody")
    m.box((0, -0.05, 0.42), (0.17, 0.17, 0.3), "BotDark")
    m.cyl((0, -0.05, 0.56), (0, -0.05, 0.86), 0.05, 0.042, 6, "GunMetal")
    m.box((0, -0.05, 0.86), (0.09, 0.09, 0.03), "VisorGlow")
    cannon = m.build("ArmR", torso, (-0.26, 0.44, 0))
    empty("Muzzle", cannon, (0, -0.05, 0.9))
    _legs(hips, "BotDark", "GunnerBody", w=0.14, thigh=0.45, shin=0.43)
    export("gunner")


def brute(boss=False):
    """BRUTE (and with boss=True the TITAN): wide armoured bruiser with huge fists."""
    reset()
    arm_m = "BossArmor" if boss else "BruteArmor"
    root = empty("Titan" if boss else "Brute")
    m = MB()
    m.box((0, 0.02, 0), (0.55, 0.26, 0.36), "BruteDark")
    hips = m.build("Hips", root, (0, 0.98, 0))
    m = MB()
    m.box((0, 0.4, 0), (0.86, 0.82, 0.5), arm_m, taper=(1.15, 1.0))
    m.box((0, 0.42, 0.26), (0.4, 0.34, 0.03), "BruteDark")
    m.box((0, 0.42, 0.28), (0.24, 0.2, 0.02), "EyeGlow")                    # glowing core
    m.box((0, 0.05, 0.255), (0.62, 0.14, 0.02), "BruteDark")
    m.box((0, 0.5, -0.27), (0.5, 0.55, 0.08), "BruteDark")                  # back plate
    torso = m.build("Torso", hips, (0, 0.14, 0))
    m = MB()
    m.box((0, 0.1, 0), (0.34, 0.28, 0.32), "BruteDark")
    m.box((0, 0.12, 0.17), (0.3, 0.07, 0.02), "EyeGlow")
    m.box((0.2, 0.2, 0), (0.07, 0.3, 0.07), arm_m, taper=(0.4, 0.4))        # horns
    m.box((-0.2, 0.2, 0), (0.07, 0.3, 0.07), arm_m, taper=(0.4, 0.4))
    if boss:
        for i in range(5):
            x = -0.14 + i * 0.07
            m.box((x, 0.34, 0), (0.05, 0.2 + (i % 2) * 0.1, 0.05), "BossArmor", taper=(0.3, 0.3))
    m.build("Head", torso, (0, 0.82, 0.02))
    for side, sx in (("R", -1), ("L", 1)):
        m = MB()
        m.box((sx * 0.04, 0.02, 0), (0.4, 0.3, 0.42), arm_m)               # pauldron
        m.box((0, -0.25, 0), (0.22, 0.4, 0.22), "BruteDark")
        arm = m.build("Arm" + side, torso, (0.58 * sx, 0.66, 0))
        m = MB()
        m.box((0, -0.2, 0), (0.24, 0.42, 0.24), arm_m)
        m.box((0, -0.5, 0), (0.34, 0.26, 0.32), "BruteDark")               # fist
        m.box((0, -0.47, 0.17), (0.3, 0.06, 0.03), arm_m)
        fore = m.build("Forearm" + side, arm, (0, -0.44, 0))
        if boss:
            m = MB()
            m.cyl((0, 0.0, 0), (0, 0.5, 0.0), 0.07, 0.05, 6, "BruteDark")
            m.box((0, 0.52, 0), (0.1, 0.06, 0.1), "EyeGlow")
            m.build("Spike" + side, torso, (0.34 * sx, 0.95, -0.1))
    _legs(hips, "BruteDark", arm_m, foot_len=0.42, w=0.27, thigh=0.5, shin=0.46, spread=0.2)
    export("titan" if boss else "brute")


def drone():
    """HOVERBOT: floating eye with a spinning rotor ("Rotor" node spins about Y)."""
    reset()
    root = empty("Drone")
    m = MB()
    m.sphere((0, 0, 0), (0.3, 0.25, 0.3), 8, 5, "DroneBody")
    m.box((0, 0.0, 0.27), (0.2, 0.2, 0.06), "BotDark")
    m.box((0, 0.0, 0.3), (0.13, 0.13, 0.03), "EyeGlow")
    m.cyl((0, -0.2, 0.08), (0, -0.2, 0.3), 0.04, 0.032, 5, "BotDark")
    m.box((0.33, 0.02, 0), (0.22, 0.04, 0.2), "BotDark")
    m.box((-0.33, 0.02, 0), (0.22, 0.04, 0.2), "BotDark")
    m.box((0, 0.28, 0), (0.05, 0.1, 0.05), "BotDark")
    m.build("Body", root)
    m = MB()
    m.box((0, 0, 0), (0.95, 0.014, 0.09), "Rotor")
    m.box((0, 0, 0), (0.09, 0.014, 0.95), "Rotor")
    m.box((0, 0.0, 0), (0.12, 0.04, 0.12), "BotDark")
    m.build("Rotor", root, (0, 0.34, 0))
    empty("Muzzle", root, (0, -0.2, 0.32))
    export("drone")


# ------------------------------------------------------------------ pickups
def pickups():
    reset()
    root = empty("Medkit")
    m = MB()
    m.box((0, 0.15, 0), (0.42, 0.3, 0.3), "Medkit")
    m.box((0, 0.32, 0), (0.14, 0.04, 0.05), "GunDark")
    for z in (0.152, -0.152):
        m.box((0, 0.15, z), (0.24, 0.075, 0.012), "MedCross")
        m.box((0, 0.15, z), (0.075, 0.24, 0.012), "MedCross")
    m.build("Box", root)
    export("medkit")

    reset()
    root = empty("Orb")
    m = MB()
    h, w = 0.34, 0.2
    top, bot = (0, h, 0), (0, -h, 0)
    ring = [(w, 0, 0), (0, 0, w), (-w, 0, 0), (0, 0, -w)]
    for i in range(4):
        a, b = ring[i], ring[(i + 1) % 4]
        cen = ((a[0] + b[0]) / 2, 0.1, (a[2] + b[2]) / 2)
        m.face([a, b, top], "Orb", hint=cen, smooth=False)
        cen2 = (cen[0], -0.1, cen[2])
        m.face([b, a, bot], "Orb", hint=cen2, smooth=False)
    m.build("Gem", root)
    export("orb")

    reset()
    root = empty("Grenade")
    m = MB()
    m.sphere((0, 0, 0), (0.1, 0.12, 0.1), 7, 4, "Grenade")
    m.cyl((0, 0.1, 0), (0, 0.16, 0), 0.04, 0.04, 6, "GunMetal")
    m.box((0.05, 0.19, 0), (0.1, 0.02, 0.02), "GunMetal")
    m.box((0, 0.0, 0), (0.205, 0.03, 0.205), "GunDark", taper=(0.98, 0.98))
    m.build("Body", root)
    export("grenade")


# -------------------------------------------------------------------- arena
HALF = 22.0
WALL_H = 9.0
CRATES = [(-14, -3), (14, 3), (-3, 14), (3, -14), (-7, -7), (7, 7), (-7, 7.5), (7.5, -7)]
BARRIERS = [((0, -10.5), 0), ((0, 10.5), 0), ((-10.5, 0), 1), ((10.5, 0), 1)]   # (xz, rotated?)
PILLARS = [(-12, -12), (12, -12), (-12, 12), (12, 12)]
STAGE = (9.0, 0.5)    # side, height


def arena():
    reset()
    root = empty("Arena")
    boxes = []

    m = MB()
    # floor, subdivided so the PSX affine warp / vertex jitter has something to chew on
    grid(m, -HALF, HALF, -HALF, HALF, 4, 4, 0.0, "Floor", 0.25, hole=(-STAGE[0] / 2, STAGE[0] / 2, -STAGE[0] / 2, STAGE[0] / 2))
    # centre stage
    s, h = STAGE
    m.box((0, h / 2, 0), (s, h, s), "Stage", face_mats={"py": "StageTop", "ny": None}, uv_scale=0.25)
    boxes.append({"c": [0, h / 2, 0], "s": [s, h, s], "kind": "stage"})

    # walls: hazard skirting, panelled body, neon band, rim
    for k in range(4):
        neon = "NeonPink" if k % 2 == 0 else "NeonCyan"
        rstrip(m, k, -HALF, HALF, 0.0, 0.9, -HALF, "Hazard", 2, 0.25, 0.0, 0.9 * 0.5)
        rstrip(m, k, -HALF, HALF, 0.9, 7.6, -HALF, "Wall", 4, 0.25, 0.0, 1.7)
        rstrip(m, k, -HALF, HALF, 7.6, 8.0, -HALF, neon, 4, 0.25, 0.0, 0.2)
        rstrip(m, k, -HALF, HALF, 8.0, WALL_H, -HALF, "Wall", 4, 0.25, 0.0, 0.3)
        # wall cap so the top edge has thickness
        rbox(m, k, (0, WALL_H + 0.25, -HALF - 0.5), (2 * HALF + 2, 0.5, 1.0), "Wall", uv_scale=0.25)
        # banner
        rquad(m, k, [(-6, 3.2, -HALF + 0.03), (6, 3.2, -HALF + 0.03), (6, 6.2, -HALF + 0.03), (-6, 6.2, -HALF + 0.03)],
              "Sign", (0, 0, 1), [(0, 1), (1, 1), (1, 0), (0, 0)])

    spawns = []
    for k in range(4):
        for gx in (-11.0, 11.0):
            # dark gate recess with a neon frame
            rstrip(m, k, gx - 2.2, gx + 2.2, 0.0, 3.4, -HALF + 0.05, "Gate", 4.4, 0.1, 0.0, 1.0)
            rbox(m, k, (gx - 2.35, 1.8, -HALF + 0.12), (0.2, 3.7, 0.22), "NeonPink")
            rbox(m, k, (gx + 2.35, 1.8, -HALF + 0.12), (0.2, 3.7, 0.22), "NeonPink")
            rbox(m, k, (gx, 3.55, -HALF + 0.12), (4.9, 0.2, 0.22), "NeonPink")
            p = rot((gx, 0, -HALF + 3.2), k)
            spawns.append([round(p[0], 3), round(p[2], 3)])

    # pillars (concrete, hazard foot, neon band)
    for (px, pz) in PILLARS:
        m.box((px, 4.5, pz), (2.0, 9.0, 2.0), "Pillar", uv_scale=0.4)
        m.box((px, 0.3, pz), (2.12, 0.6, 2.12), "Hazard", uv_scale=0.5)
        m.box((px, 4.0, pz), (2.1, 0.22, 2.1), "NeonCyan")
        boxes.append({"c": [px, 4.5, pz], "s": [2.0, 9.0, 2.0], "kind": "pillar"})

    # cover
    for (cx, cz) in CRATES:
        m.box((cx, 0.6, cz), (1.9, 1.2, 1.9), "Crate", uv_scale=0.5)
        m.box((cx, 1.22, cz), (1.5, 0.04, 1.5), "Crate")
        boxes.append({"c": [cx, 0.6, cz], "s": [1.9, 1.2, 1.9], "kind": "crate"})
    for (xz, r) in BARRIERS:
        size = (0.55, 1.0, 3.4) if r else (3.4, 1.0, 0.55)
        m.box((xz[0], 0.5, xz[1]), size, "Barrier", taper=(0.9, 0.9), uv_scale=0.5)
        m.box((xz[0], 1.01, xz[1]), (size[0] * 0.98, 0.04, size[2] * 0.98), "Hazard")
        boxes.append({"c": [xz[0], 0.5, xz[1]], "s": list(size), "kind": "barrier"})
    m.build("Level", root)

    # distant skyline ring (cutout, cull-disabled shader)
    m = MB()
    seg, rad = 28, 105.0
    for i in range(seg):
        a0, a1 = TAU * i / seg, TAU * (i + 1) / seg
        pts = [(math.sin(a0) * rad, -2.0, math.cos(a0) * rad), (math.sin(a1) * rad, -2.0, math.cos(a1) * rad),
               (math.sin(a1) * rad, 38.0, math.cos(a1) * rad), (math.sin(a0) * rad, 38.0, math.cos(a0) * rad)]
        cen = (-(pts[0][0] + pts[1][0]) / 2, 0.0, -(pts[0][2] + pts[1][2]) / 2)
        m.face(pts, "Skyline", hint=cen,
               uvs=[(i / seg * 4, 1), ((i + 1) / seg * 4, 1), ((i + 1) / seg * 4, 0), (i / seg * 4, 0)])
    m.build("Skyline", root)

    os.makedirs(LEVELS, exist_ok=True)
    with open(os.path.join(LEVELS, "arena.json"), "w") as f:
        json.dump({"half": HALF, "wall_h": WALL_H, "boxes": boxes, "spawns": spawns, "player_start": [0, 0, 7.5]}, f, indent=1)
    export("arena")


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    table = {
        "uzi": lambda: (uzi("R"), uzi("L")), "grunt": grunt, "gunner": gunner,
        "brute": lambda: (brute(False), brute(True)), "drone": drone, "pickups": pickups, "arena": arena,
    }
    for name in (only or table.keys()):
        table[name]()


main()
