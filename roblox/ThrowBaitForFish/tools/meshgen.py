#!/usr/bin/env python3
"""Генератор 3D-моделей рыб (GLB) для Throw Bait For Fish.

Система координат: X вправо, Y вверх, голова в -Z, хвост в +Z, длина тела ~1.
Каждая модель — набор именованных мешей. Имя = роль цвета в игре:
  C1 (основной), C2 (живот/второй), C3 (плавники/акцент), C1Dark, Eye, Pupil, Shine, Dark, Tooth, Glow,
  а также маркеры Nose (кончик морды) и Top (верх) — по ним игра поворачивает модель правильно.

Запуск: python3 tools/meshgen.py [fishId ...]  ->  build/meshes/<id>.glb
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb import write_glb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "meshes")

TAU = 2 * math.pi


# ===================== примитивы =====================

class Mesh:
    def __init__(self, name):
        self.name = name
        self.v = []
        self.f = []

    def add(self, verts, faces):
        base = len(self.v)
        self.v.extend([list(map(float, p)) for p in verts])
        self.f.extend([[a + base, b + base, c + base] for a, b, c in faces])
        return self


class Model:
    def __init__(self):
        self.meshes = {}

    def mesh(self, name):
        if name not in self.meshes:
            self.meshes[name] = Mesh(name)
        return self.meshes[name]

    def add(self, name, verts, faces):
        self.mesh(name).add(verts, faces)

    def write(self, path):
        out = []
        for m in self.meshes.values():
            if m.f:
                out.append({"name": m.name, "verts": np.array(m.v), "faces": np.array(m.f)})
        write_glb(path, out)


def ring_faces(n_rings, segs, closed=True):
    faces = []
    for i in range(n_rings - 1):
        for j in range(segs if closed else segs - 1):
            a = i * segs + j
            b = i * segs + (j + 1) % segs
            c = (i + 1) * segs + j
            d = (i + 1) * segs + (j + 1) % segs
            faces += [[a, b, c], [b, d, c]]
    return faces


def cap(verts, faces, ring_start, segs, point, flip):
    idx = len(verts)
    verts.append(point)
    for j in range(segs):
        a = ring_start + j
        b = ring_start + (j + 1) % segs
        faces.append([a, idx, b] if flip else [b, idx, a])


def sphere(center, radii, segs=20, rings=14, squash_bottom=1.0):
    cx, cy, cz = center
    rx, ry, rz = radii
    verts, faces = [], []
    for i in range(1, rings):
        lat = math.pi * i / rings
        y = math.cos(lat)
        r = math.sin(lat)
        if y < 0:
            y *= squash_bottom
        for j in range(segs):
            lon = TAU * j / segs
            verts.append([cx + rx * r * math.cos(lon), cy + ry * y, cz + rz * r * math.sin(lon)])
    faces = ring_faces(rings - 1, segs)
    top = [cx, cy + ry, cz]
    bot = [cx, cy - ry * squash_bottom, cz]
    cap(verts, faces, 0, segs, top, False)
    cap(verts, faces, (rings - 2) * segs, segs, bot, True)
    return verts, faces


def frame_from(direction):
    d = np.array(direction, dtype=float)
    d /= np.linalg.norm(d)
    up = np.array([0, 1.0, 0]) if abs(d[1]) < 0.9 else np.array([1.0, 0, 0])
    x = np.cross(up, d)
    x /= np.linalg.norm(x)
    y = np.cross(d, x)
    return x, y, d


def tube(path, radii, segs=12, close_start=True, close_end=True):
    """Труба вдоль ломаной path, радиусы по точкам."""
    path = [np.array(p, dtype=float) for p in path]
    verts, faces = [], []
    n = len(path)
    prev_x = None
    for i, p in enumerate(path):
        d = path[min(i + 1, n - 1)] - path[max(i - 1, 0)]
        x, y, _ = frame_from(d)
        if prev_x is not None and np.dot(x, prev_x) < 0:
            x, y = -x, -y
        prev_x = x
        r = radii[i]
        for j in range(segs):
            a = TAU * j / segs
            verts.append(p + (x * math.cos(a) + y * math.sin(a)) * r)
    faces = ring_faces(n, segs)
    if close_start:
        cap(verts, faces, 0, segs, path[0] - (path[1] - path[0]) * 0.05, True)
    if close_end:
        cap(verts, faces, (n - 1) * segs, segs, path[-1] + (path[-1] - path[-2]) * 0.05, False)
    return verts, faces


def cone(base, tip, radius, segs=10):
    base = np.array(base, dtype=float)
    tip = np.array(tip, dtype=float)
    x, y, _ = frame_from(tip - base)
    verts = [base + (x * math.cos(TAU * j / segs) + y * math.sin(TAU * j / segs)) * radius for j in range(segs)]
    faces = []
    verts.append(tip)
    t = len(verts) - 1
    for j in range(segs):
        faces.append([j, (j + 1) % segs, t])
    verts.append(base)
    b = len(verts) - 1
    for j in range(segs):
        faces.append([(j + 1) % segs, j, b])
    return verts, faces


def fin(outline, origin, u_axis, v_axis, thickness=0.012, curl=0.0, segs_per_edge=1):
    """Плоский плавник по контуру outline [(u,v),...] (звёздный относительно центроида),
    в плоскости origin + u*U + v*V, с толщиной и лёгким изгибом curl (вдоль нормали ~ u^2)."""
    o = np.array(origin, dtype=float)
    U = np.array(u_axis, dtype=float)
    V = np.array(v_axis, dtype=float)
    N = np.cross(U, V)
    N /= np.linalg.norm(N)
    pts = []
    for k in range(len(outline)):
        a = np.array(outline[k], dtype=float)
        b = np.array(outline[(k + 1) % len(outline)], dtype=float)
        for s in range(segs_per_edge):
            pts.append(a + (b - a) * s / segs_per_edge)
    c = np.mean(pts, axis=0)
    m = len(pts)

    def P(uv, side):
        u, v = uv
        bend = curl * (u * u + v * v)
        return o + U * u + V * v + N * (bend + side * thickness / 2)

    verts, faces = [], []
    for side in (1, -1):
        base = len(verts)
        verts.append(P(c, side))
        for p in pts:
            verts.append(P(p, side * 0.35))  # края тоньше
        for k in range(m):
            a = base + 1 + k
            b = base + 1 + (k + 1) % m
            faces.append([base, a, b] if side > 0 else [base, b, a])
    # торцы
    top0, bot0 = 1, m + 2
    for k in range(m):
        a, b = top0 + k, top0 + (k + 1) % m
        c2, d = bot0 + k, bot0 + (k + 1) % m
        faces += [[a, c2, b], [b, c2, d]]
    return verts, faces


# ===================== тело =====================

class Body:
    """Лофт тела: сечения-суперэллипсы вдоль Z от головы (t=0) к хвосту (t=1)."""

    def __init__(self, length=1.0, width=0.2, height=0.25, head=0.5, tail=0.9, power=2.2, droop=0.02,
                 rings=44, segs=36, spine_x=None, spine_y=None, z0=-0.5, head_flat=0.0):
        self.L, self.W, self.H = length, width, height
        self.head, self.tail, self.power = head, tail, power
        self.droop = droop
        self.rings, self.segs = rings, segs
        self.spine_x = spine_x or (lambda t: 0.0)
        self.spine_y = spine_y or (lambda t: 0.0)
        self.z0 = z0
        self.head_flat = head_flat
        ts = np.linspace(0, 1, 400)
        prof = ts ** self.head * (1 - ts) ** self.tail
        self.norm = prof.max()

    def prof(self, t):
        t = min(max(t, 1e-4), 1 - 1e-4)
        return (t ** self.head * (1 - t) ** self.tail) / self.norm

    def section(self, t):
        k = self.prof(t)
        # хвостовой стебель не сужается в ноль
        k = max(k, 0.12 * min(1, t * 4)) if t > 0.5 else k
        w = self.W * k
        h = self.H * k
        cy = -self.droop * math.sin(math.pi * t) + self.spine_y(t)
        cx = self.spine_x(t)
        return cx, cy, w, h

    def point(self, t, ang, inflate=0.0):
        cx, cy, w, h = self.section(t)
        c, s = math.cos(ang), math.sin(ang)
        e = 2.0 / self.power
        x = (w + inflate) * math.copysign(abs(c) ** e, c)
        y = (h + inflate) * math.copysign(abs(s) ** e, s)
        if y > 0 and self.head_flat:
            y *= 1 - self.head_flat * max(0, 1 - t * 3)
        z = self.z0 + self.L * t
        return np.array([cx + x, cy + y, z])

    def surface(self, t, ang, out=0.0):
        """Точка на поверхности + выход наружу на out."""
        p = self.point(t, ang)
        cx, cy, _, _ = self.section(t)
        n = p - np.array([cx, cy, p[2]])
        ln = np.linalg.norm(n)
        if ln > 0:
            n /= ln
        return p + n * out, n

    def build(self, model, top="C1", belly="C2", belly_from=200, belly_to=340, t0=0.0, t1=1.0, inflate=0.0, name_override=None):
        """Делит тело по углу: снизу живот другого цвета (чистая линия вдоль бока)."""
        segs, rings = self.segs, self.rings
        ts = [t0 + (t1 - t0) * (0.5 - 0.5 * math.cos(math.pi * i / (rings - 1))) for i in range(rings)]
        verts = []
        for t in ts:
            for j in range(segs):
                verts.append(self.point(t, TAU * j / segs, inflate))
        faces_top, faces_belly = [], []
        for i in range(rings - 1):
            for j in range(segs):
                a = i * segs + j
                b = i * segs + (j + 1) % segs
                c = (i + 1) * segs + j
                d = (i + 1) * segs + (j + 1) % segs
                ang = math.degrees(TAU * (j + 0.5) / segs)
                tgt = faces_belly if (belly and belly_from <= ang <= belly_to) else faces_top
                tgt += [[a, b, c], [b, d, c]]
        # торцы (кончик морды и хвоста)
        nose = self.point(t0, 0) * 0
        cx, cy, _, _ = self.section(t0)
        nose = np.array([cx, cy, self.z0 + self.L * t0 - 0.004])
        cx2, cy2, _, _ = self.section(t1)
        tailp = np.array([cx2, cy2, self.z0 + self.L * t1 + 0.004])
        verts_l = [list(p) for p in verts]
        cap(verts_l, faces_top, 0, segs, nose, False)
        cap(verts_l, faces_top, (rings - 1) * segs, segs, tailp, True)
        model.add(name_override or top, verts_l, faces_top)
        if faces_belly:
            model.add(belly, verts_l, faces_belly)

    def band(self, model, name, t_center, t_width, inflate=0.006):
        """Полоса, повторяющая форму тела."""
        self.build(model, top=name, belly=None, t0=max(0.01, t_center - t_width / 2), t1=min(0.99, t_center + t_width / 2), inflate=inflate)


def eye(model, pos, normal, r, cute=False):
    pos = np.array(pos, dtype=float)
    n = np.array(normal, dtype=float)
    n /= np.linalg.norm(n)
    model.add("Eye", *sphere(pos, (r, r, r), 18, 12))
    pr = r * (0.62 if cute else 0.55)
    pp = pos + n * (r * 0.62)
    model.add("Pupil", *sphere(pp, (pr, pr, pr * 0.7), 16, 10))
    sr = r * 0.2
    sp = pp + n * (pr * 0.5) + np.array([0, r * 0.25, -r * 0.2])
    model.add("Shine", *sphere(sp, (sr, sr, sr), 10, 8))


def markers(model, nose, top):
    model.add("Nose", *sphere(nose, (0.004, 0.004, 0.004), 6, 4))
    model.add("Top", *sphere(top, (0.004, 0.004, 0.004), 6, 4))


def side_pair(fn):
    for s in (-1, 1):
        fn(s)


# ===================== плавники =====================

def tail_forked(model, root, height, length, name="C3", fork=0.55, thick=0.014):
    outline = [(0, height * 0.18), (length * 0.55, height * 0.62), (length, height), (length * fork, 0.0),
               (length, -height), (length * 0.55, -height * 0.62), (0, -height * 0.18)]
    model.add(name, *fin(outline, root, (0, 0, 1), (0, 1, 0), thick, curl=0.0, segs_per_edge=3))


def tail_round(model, root, height, length, name="C3"):
    outline = [(0, height * 0.2)] + [(length * (0.4 + 0.6 * math.cos(a)), height * math.sin(a)) for a in np.linspace(math.pi / 2, -math.pi / 2, 11)] + [(0, -height * 0.2)]
    model.add(name, *fin(outline, root, (0, 0, 1), (0, 1, 0), 0.014, segs_per_edge=2))


def tail_shark(model, root, size, name="C1"):
    outline = [(0, size * 0.12), (size * 0.55, size * 0.75), (size * 0.75, size * 0.95), (size * 0.62, size * 0.35),
               (size * 0.42, 0.0), (size * 0.5, -size * 0.45), (size * 0.3, -size * 0.35), (0, -size * 0.1)]
    model.add(name, *fin(outline, root, (0, 0, 1), (0, 1, 0), 0.018, segs_per_edge=3))


def flukes(model, root, span, length, name="C1"):
    outline = [(0, 0.03), (span * 0.6, length * 0.4), (span, length * 0.95), (span * 0.55, length * 0.75),
               (0.0, length * 0.55), (-span * 0.55, length * 0.75), (-span, length * 0.95), (-span * 0.6, length * 0.4), (0, 0.03)]
    model.add(name, *fin(outline[:-1], root, (1, 0, 0), (0, 0, 1), 0.02, segs_per_edge=2))


def dorsal(model, base_front, base_len, height, name="C3", sweep=0.6, rays=0):
    pts = [(0, 0)]
    steps = 9
    for k in range(1, steps):
        u = base_len * k / steps
        hh = height * math.sin(math.pi * (k / steps) ** 0.8) * (1 - 0.15 * (k / steps))
        if rays:
            hh *= 1 + 0.12 * (1 if k % 2 else -0.4)
        pts.append((u + sweep * hh * 0.4, hh))
    pts.append((base_len, 0))
    model.add(name, *fin(pts, base_front, (0, 0, 1), (0, 1, 0), 0.012, segs_per_edge=1))


def shark_dorsal(model, base_front, base_len, height, name="C1"):
    pts = [(0, 0), (base_len * 0.45, height * 0.6), (base_len * 0.85, height), (base_len * 0.75, height * 0.55), (base_len, 0)]
    model.add(name, *fin(pts, base_front, (0, 0, 1), (0, 1, 0), 0.02, segs_per_edge=3))


def pectoral(model, root, side, length, width, name="C3", down=0.35, back=0.6):
    U = np.array([side * math.cos(back) * math.cos(down), -math.sin(down), math.sin(back) * math.cos(down)])
    V = np.array([0, 0, 1.0])
    V = V - U * np.dot(U, V)
    V /= np.linalg.norm(V)
    outline = [(0, -width * 0.3), (length * 0.6, -width * 0.45), (length, 0), (length * 0.65, width * 0.5), (0, width * 0.3)]
    model.add(name, *fin(outline, root, U, V, 0.012, curl=0.15 * side * 0, segs_per_edge=2))


# ===================== формы =====================

def build_fish(d):
    m = Model()
    tall = 1.6 if d.get("Tall") else 1.0
    big = 1.15 if d.get("Big") else 1.0
    b = Body(width=0.17 * big, height=0.23 * tall * big, head=0.36, tail=0.95, power=2.3)
    b.build(m)
    if d.get("Stripes"):
        b.band(m, "C2", 0.32, 0.07)
        b.band(m, "C2", 0.62, 0.07)
    if d.get("Spots"):
        for t, a in [(0.35, 40), (0.45, 70), (0.55, 30), (0.65, 60), (0.4, 140), (0.5, 110), (0.6, 150), (0.7, 120)]:
            p, n = b.surface(t, math.radians(a), 0.0)
            r = 0.028
            m.add("C3", *sphere(p, (r, r, r), 10, 8))
    tail_forked(m, (0, 0, 0.47), 0.2 * tall ** 0.5, 0.28)
    dorsal(m, (0, b.section(0.3)[3] * 0.92, -0.15), 0.42, 0.17 * tall, rays=1)
    dorsal(m, (0, -b.section(0.6)[3] * 0.9, 0.12), 0.18, -0.09 * tall)
    side_pair(lambda s: pectoral(m, b.surface(0.3, math.radians(200 if s < 0 else 340))[0], s, 0.16, 0.08))
    ep, en = b.surface(0.15, math.radians(28), -0.01)
    for s in (-1, 1):
        p = ep.copy(); p[0] *= s
        n = en.copy(); n[0] *= s
        eye(m, p, n, 0.045 * (0.9 if d.get("Big") else 1))
    # рот и жабры
    mp, _ = b.surface(0.015, math.radians(-10))
    m.add("Dark", *sphere(mp + np.array([0, 0, 0.004]), (0.03, 0.012, 0.01), 12, 8))
    for s in (-1, 1):
        gill = [b.surface(0.24, math.radians(a), 0.003)[0] * np.array([s, 1, 1]) for a in np.linspace(-40, 50, 8)]
        m.add("C1Dark", *tube(gill, [0.006] * len(gill), 6))
    if d.get("Sword"):
        m.add("C2", *cone((0, 0.01, -0.49), (0, 0.02, -0.95), 0.025, 12))
    if d.get("Spikes"):
        for k in range(6):
            t = 0.22 + k * 0.07
            p, _ = b.surface(t, math.pi / 2)
            m.add("C2", *cone(p, p + np.array([0, 0.2, 0.05]), 0.012, 6))
    markers(m, (0, 0, -0.52), (0, 0.4, 0))
    return m


def build_shark(d):
    m = Model()
    big = 1.15 if d.get("Big") else 1.0
    b = Body(width=0.13 * big, height=0.15 * big, head=0.62, tail=1.15, power=2.0, droop=0.0,
             spine_y=lambda t: 0.05 * t ** 3, head_flat=0.25)
    b.build(m, belly_from=195, belly_to=345)
    shark_dorsal(m, (0, b.section(0.35)[3] * 0.9, -0.12), 0.24, 0.26)
    shark_dorsal(m, (0, b.section(0.75)[3] * 0.8 + 0.02, 0.24), 0.08, 0.07)
    tail_shark(m, (0, 0.04, 0.48), 0.42)
    side_pair(lambda s: pectoral(m, b.surface(0.3, math.radians(215 if s < 0 else 325))[0], s, 0.3, 0.12, "C1", down=0.5, back=0.75))
    side_pair(lambda s: pectoral(m, b.surface(0.62, math.radians(230 if s < 0 else 310))[0], s, 0.09, 0.05, "C1", down=0.7, back=0.9))
    for s in (-1, 1):
        for k in range(5):
            t = 0.2 + k * 0.025
            gill = [b.surface(t, math.radians(a), 0.002)[0] * np.array([s, 1, 1]) for a in np.linspace(-25, 25, 6)]
            m.add("C1Dark", *tube(gill, [0.004] * len(gill), 5))
    ep, en = b.surface(0.1, math.radians(20), -0.004)
    cute = d.get("Cute")
    for s in (-1, 1):
        p = ep.copy(); p[0] *= s
        n = en.copy(); n[0] *= s
        if cute:
            eye(m, p, n, 0.04, True)
        else:
            m.add("Glow" if d.get("Glow") else "Pupil", *sphere(p, (0.02, 0.02, 0.02), 12, 8))
            sp = p + n * 0.015 + np.array([0, 0.008, -0.006])
            m.add("Shine", *sphere(sp, (0.005, 0.005, 0.005), 6, 5))
    # пасть
    mouth = [b.surface(0.07, math.radians(a), 0.001)[0] for a in np.linspace(205, 335, 12)]
    m.add("Dark", *tube(mouth, [0.008] * len(mouth), 6))
    if d.get("Teeth"):
        for k, a in enumerate(np.linspace(210, 330, 11)):
            p, n = b.surface(0.07, math.radians(a), 0.004)
            m.add("Tooth", *cone(p, p + np.array([0, -0.035, -0.008]), 0.009, 6))
    if d.get("Hammer"):
        m.add("C1", *sphere((0, 0.01, -0.47), (0.24, 0.03, 0.06), 24, 10))
        for s in (-1, 1):
            m.add("Pupil", *sphere((s * 0.24, 0.015, -0.47), (0.018, 0.018, 0.018), 10, 8))
    markers(m, (0, 0, -0.52), (0, 0.4, 0))
    return m


def build_whale(d):
    m = Model()
    b = Body(width=0.17, height=0.16, head=0.32, tail=1.25, power=2.1, droop=0.01, spine_y=lambda t: 0.03 * t ** 2)
    b.build(m, belly_from=205, belly_to=335)
    if not d.get("Orca"):
        for k in range(7):  # горловые складки
            x = -0.08 + k * 0.027
            groove = [(x, -0.14 * max(0.2, 1 - abs(x) * 4) - 0.01, z) for z in np.linspace(-0.4, -0.05, 8)]
            groove = [b.surface(0.08 + (z + 0.4) * 0.9, math.radians(270 + x * 300), 0.002)[0] for (_, _, z) in groove]
            m.add("C1Dark", *tube(groove, [0.004] * len(groove), 5))
    flukes(m, (0, 0.03, 0.47), 0.2, 0.2)
    side_pair(lambda s: pectoral(m, b.surface(0.32, math.radians(220 if s < 0 else 320))[0], s, 0.2, 0.07, "C1", down=0.6, back=0.7))
    if d.get("Orca"):
        shark_dorsal(m, (0, b.section(0.42)[3] * 0.9, -0.05), 0.14, 0.32)
        for s in (-1, 1):
            p, n = b.surface(0.17, math.radians(15), 0.003)
            p[0] *= s
            m.add("Eye", *sphere(p, (0.012, 0.035, 0.055), 14, 10))
            sp, _ = b.surface(0.66, math.radians(60), 0.003)
            sp[0] *= s
            m.add("Eye", *sphere(sp, (0.01, 0.03, 0.08), 14, 10))
    else:
        shark_dorsal(m, (0, b.section(0.68)[3] * 0.9, 0.18), 0.07, 0.05)
    ep, en = b.surface(0.22, math.radians(-8), -0.003)
    for s in (-1, 1):
        p = ep.copy(); p[0] *= s
        n = en.copy(); n[0] *= s
        m.add("Pupil", *sphere(p, (0.017, 0.017, 0.017), 12, 8))
        m.add("Shine", *sphere(p + n * 0.012 + np.array([0, 0.007, -0.005]), (0.005, 0.005, 0.005), 6, 5))
    if d.get("Glow"):
        for k in range(9):
            p, _ = b.surface(0.2 + k * 0.07, math.radians(80 + (k % 3) * 8), 0.0)
            m.add("Glow", *sphere(p, (0.018, 0.018, 0.018), 8, 6))
    markers(m, (0, 0, -0.52), (0, 0.4, 0))
    return m


def build_puffer(d):
    m = Model()
    b = Body(length=0.8, z0=-0.4, width=0.36, height=0.34, head=0.5, tail=0.6, power=2.0, droop=0.0)
    b.build(m, belly_from=210, belly_to=330)
    if d.get("Spikes"):
        n = 46
        gold = math.pi * (3 - math.sqrt(5))
        for i in range(n):
            y = 1 - (i / (n - 1)) * 2
            r = math.sqrt(1 - y * y)
            th = gold * i
            dvec = np.array([math.cos(th) * r, y, math.sin(th) * r])
            if dvec[2] < -0.75 or dvec[2] > 0.85:
                continue
            t = 0.5 + dvec[2] * 0.45
            ang = math.atan2(dvec[1], dvec[0])
            p, nrm = b.surface(t, ang, -0.01)
            m.add("C3", *cone(p, p + nrm * 0.09, 0.016, 6))
    tail_round(m, (0, 0, 0.38), 0.11, 0.15)
    dorsal(m, (0, 0.3, 0.12), 0.12, 0.08)
    side_pair(lambda s: pectoral(m, b.surface(0.35, math.radians(10 if s > 0 else 170))[0], s, 0.1, 0.07, down=0.1, back=0.9))
    ep, en = b.surface(0.2, math.radians(25), -0.02)
    for s in (-1, 1):
        p = ep.copy(); p[0] *= s
        n = en.copy(); n[0] *= s
        eye(m, p, n, 0.075, True)
    m.add("Dark", *sphere((0, -0.03, -0.405), (0.04, 0.03, 0.02), 12, 8))
    markers(m, (0, 0, -0.42), (0, 0.5, 0))
    return m


def build_eel(d):
    m = Model()
    b = Body(width=0.055, height=0.065, head=0.18, tail=0.55, power=2.0, droop=0.0, rings=90, segs=24,
             spine_x=lambda t: 0.08 * math.sin(t * math.pi * 2.2) * t, z0=-0.5)
    b.build(m, belly_from=215, belly_to=325)
    if d.get("Spots"):
        for k in range(14):
            t = 0.12 + k * 0.06
            p, _ = b.surface(t, math.radians(60 + (k % 3) * 30), 0)
            m.add("C2", *sphere(p, (0.014, 0.014, 0.014), 8, 6))
    # сплошной плавник вдоль спины
    fin_pts = []
    for k in range(40):
        t = 0.25 + k * 0.0185
        p, _ = b.surface(t, math.pi / 2)
        fin_pts.append(p)
    for k in range(len(fin_pts) - 1):
        a, c = fin_pts[k], fin_pts[k + 1]
        h1 = 0.035 * math.sin(math.pi * k / 40) + 0.01
        h2 = 0.035 * math.sin(math.pi * (k + 1) / 40) + 0.01
        verts = [a, c, c + np.array([0, h2, 0]), a + np.array([0, h1, 0])]
        m.add("Glow" if d.get("Glow") else "C3", verts, [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]])
    if d.get("Spikes"):
        for k in range(9):
            p, _ = b.surface(0.12 + k * 0.08, math.pi / 2)
            m.add("C3", *cone(p, p + np.array([0, 0.07, 0.03]), 0.012, 6))
    ep, en = b.surface(0.05, math.radians(25), -0.003)
    for s in (-1, 1):
        p = ep.copy(); p[0] *= s
        n = en.copy(); n[0] *= s
        eye(m, p, n, 0.02)
    jaw = [b.surface(0.03, math.radians(a), 0.001)[0] for a in np.linspace(200, 340, 10)]
    m.add("Dark", *tube(jaw, [0.005] * len(jaw), 5))
    markers(m, (0, 0, -0.52), (0, 0.4, 0))
    return m


def build_angler(d):
    m = Model()
    b = Body(length=0.85, z0=-0.42, width=0.27, height=0.25, head=0.3, tail=0.85, power=2.1, droop=0.0)
    b.build(m, belly_from=215, belly_to=325)
    m.add("Dark", *sphere((0, -0.04, -0.4), (0.2, 0.09, 0.05), 20, 10))
    for k, x in enumerate(np.linspace(-0.17, 0.17, 9)):
        m.add("Tooth", *cone((x, 0.04 - abs(x) * 0.2, -0.42), (x, -0.03, -0.44), 0.012, 6))
        m.add("Tooth", *cone((x + 0.02, -0.12 + abs(x) * 0.2, -0.41), (x + 0.02, -0.05, -0.43), 0.011, 6))
    stalk = [(0, 0.22, -0.18), (0, 0.33, -0.3), (0, 0.36, -0.45), (0, 0.3, -0.55)]
    m.add("C1", *tube(stalk, [0.012, 0.01, 0.008, 0.007], 8))
    m.add("Glow", *sphere((0, 0.27, -0.58), (0.045, 0.045, 0.045), 14, 10))
    tail_round(m, (0, 0, 0.42), 0.13, 0.17)
    dorsal(m, (0, 0.2, 0.05), 0.2, 0.08, rays=1)
    side_pair(lambda s: pectoral(m, b.surface(0.4, math.radians(200 if s < 0 else 340))[0], s, 0.12, 0.08))
    ep, en = b.surface(0.2, math.radians(40), -0.01)
    for s in (-1, 1):
        p = ep.copy(); p[0] *= s
        n = en.copy(); n[0] *= s
        eye(m, p, n, 0.035)
    markers(m, (0, 0, -0.45), (0, 0.5, 0))
    return m


def build_ray(d):
    m = Model()
    verts, faces_top, faces_bot = [], [], []
    segs, rings = 48, 22
    for i in range(1, rings):
        lat = math.pi * i / rings
        y0 = math.cos(lat)
        r = math.sin(lat)
        for j in range(segs):
            lon = TAU * j / segs
            x = math.cos(lon) * r
            z = math.sin(lon) * r
            span = 0.62 * (1 + 0.35 * abs(math.cos(lon)) ** 3)
            X = x * span
            Z = z * 0.36 + 0.16 * (X / 0.7) ** 2
            thick = 0.075 * (1 - 0.85 * min(1, abs(X) / 0.75)) + 0.008
            Y = y0 * thick
            verts.append([X, Y, Z])
    for i in range(rings - 2):
        for j in range(segs):
            a = i * segs + j
            b2 = i * segs + (j + 1) % segs
            c = (i + 1) * segs + j
            dd = (i + 1) * segs + (j + 1) % segs
            (faces_top if i < (rings - 2) / 2 else faces_bot).extend([[a, c, b2], [b2, c, dd]])
    cap(verts, faces_top, 0, segs, [0, 0.083, 0], True)
    cap(verts, faces_bot, (rings - 2) * segs, segs, [0, -0.083, 0], False)
    m.add("C1", verts, faces_top)
    m.add("C2", verts, faces_bot)
    if d.get("Glow") or d.get("Ghost"):
        for k in range(6):
            m.add("Glow", *sphere((0.12 * math.cos(k), 0.07, -0.05 + k * 0.04), (0.02, 0.01, 0.02), 8, 6))
    for s in (-1, 1):  # головные лопасти манты
        horn = [(s * 0.09, 0.0, -0.33), (s * 0.12, -0.01, -0.42), (s * 0.1, -0.03, -0.48), (s * 0.07, -0.05, -0.47)]
        m.add("C1", *tube(horn, [0.03, 0.025, 0.018, 0.01], 10))
        m.add("Pupil", *sphere((s * 0.14, 0.03, -0.3), (0.02, 0.02, 0.02), 10, 8))
    tail = [(0, 0, 0.3), (0, 0.0, 0.55), (0.02, 0.01, 0.8), (0.05, 0.02, 1.0)]
    m.add("C1", *tube(tail, [0.025, 0.014, 0.008, 0.003], 8))
    markers(m, (0, 0, -0.52), (0, 0.4, 0))
    return m


def build_jelly(d):
    m = Model()
    verts, faces = [], []
    segs, rings = 40, 16
    for i in range(rings):
        lat = (math.pi * 0.58) * i / (rings - 1)
        r = math.sin(lat) * 0.32
        y = math.cos(lat) * 0.26 + 0.05
        for j in range(segs):
            lon = TAU * j / segs
            scallop = 1 + (0.06 * math.cos(lon * 8) if i == rings - 1 else 0)
            verts.append([r * scallop * math.cos(lon), y, r * scallop * math.sin(lon)])
    faces = ring_faces(rings, segs)
    faces = [[a, c, b] for a, b, c in faces]
    cap(verts, faces, 0, segs, [0, 0.31, 0], True)
    # внутренняя сторона (купол видно снизу)
    inner = [[p[0] * 0.9, p[1] - 0.03, p[2] * 0.9] for p in verts[: rings * segs]]
    inner_faces = [[a, b, c] for a, b, c in ring_faces(rings, segs)]
    m.add("C1", verts, faces)
    m.add("C2", inner, inner_faces)
    m.add("Glow", *sphere((0, 0.14, 0), (0.12, 0.08, 0.12), 16, 10))
    for k in range(12):
        a = TAU * k / 12
        r0 = 0.27
        path = [(math.cos(a) * r0 * (1 - 0.02 * q), 0.05 - q * 0.07, math.sin(a) * r0 * (1 - 0.02 * q) + 0.025 * math.sin(q * 1.3 + k)) for q in range(10)]
        m.add("C3", *tube(path, [0.008 * (1 - q / 12) for q in range(10)], 6))
    for k in range(4):
        a = TAU * k / 4 + 0.4
        path = [(math.cos(a) * 0.05 + 0.03 * math.sin(q * 0.9), 0.06 - q * 0.06, math.sin(a) * 0.05 + 0.03 * math.cos(q * 0.9)) for q in range(9)]
        m.add("C2", *tube(path, [0.03 * (1 - q / 11) for q in range(9)], 8))
    for s in (-1, 1):
        eye(m, (s * 0.11, 0.17, -0.25), (s * 0.3, 0.1, -1), 0.04, True)
    markers(m, (0, 0.1, -0.35), (0, 0.6, 0))
    return m


def build_squid(d):
    m = Model()
    big = 1.15 if d.get("Big") else 1.0
    b = Body(length=0.6, z0=-0.1, width=0.11 * big, height=0.11 * big, head=0.15, tail=1.2, power=2.0, droop=0.0)
    b.build(m, belly_from=220, belly_to=320)
    for s in (-1, 1):
        outline = [(0, 0), (0.12, 0.05), (0.16, 0.16), (0.03, 0.18)]
        m.add("C3", *fin(outline, (s * 0.03, 0, 0.32), (s, 0, 0), (0, 0, 1), 0.012, segs_per_edge=2))
    m.add("C2", *sphere((0, 0, -0.14), (0.085 * big, 0.08 * big, 0.08), 18, 12))
    for s in (-1, 1):
        eye(m, (s * 0.075 * big, 0.02, -0.15), (s, 0.15, -0.3), 0.04, True)
    for k in range(8):
        a = TAU * k / 8
        dx, dy = math.cos(a), math.sin(a)
        path = [(dx * 0.04, dy * 0.04, -0.2 - q * 0.05) for q in range(8)]
        path = [(x + dx * 0.006 * q * q, y + dy * 0.006 * q * q, z) for q, (x, y, z) in enumerate(path)]
        m.add("C1", *tube(path, [0.022 * (1 - q / 9) for q in range(8)], 8))
    for s in (-1, 1):
        path = [(s * 0.02, -0.02, -0.2 - q * 0.07) for q in range(9)]
        m.add("C3", *tube(path, [0.01] * 8 + [0.025], 8))
    markers(m, (0, 0, -0.62), (0, 0.4, 0))
    return m


def build_octopus(d):
    m = Model()
    m.add("C1", *sphere((0, 0.2, 0.06), (0.2, 0.24, 0.22), 28, 18))
    m.add("C2", *sphere((0, 0.02, 0), (0.16, 0.08, 0.16), 24, 12))
    for s in (-1, 1):
        eye(m, (s * 0.12, 0.13, -0.12), (s * 0.5, 0.1, -1), 0.055, True)
    for k in range(8):
        a = TAU * k / 8 + math.pi / 8
        dx, dz = math.cos(a), math.sin(a)
        path = []
        for q in range(14):
            t = q / 13
            r = 0.1 + t * 0.42
            curl = max(0, t - 0.6) * 2.5
            y = 0.02 - t * 0.12 + curl * curl * 0.12
            path.append((dx * r - dz * curl * 0.06, y, dz * r + dx * curl * 0.06))
        m.add("C1", *tube(path, [0.05 * (1 - q / 15) + 0.006 for q in range(14)], 10))
        for q in (3, 5, 7, 9):
            x, y, z = path[q]
            m.add("C2", *sphere((x, y - 0.03 * (1 - q / 14), z), (0.012, 0.006, 0.012), 8, 5))
    markers(m, (0, 0.1, -0.3), (0, 0.6, 0))
    return m


def build_turtle(d):
    m = Model()
    m.add("C1", *sphere((0, 0.05, 0), (0.3, 0.2, 0.38), 32, 16, squash_bottom=0.2))
    m.add("C2", *sphere((0, 0.0, 0), (0.28, 0.05, 0.35), 28, 10))
    for (x, z, s) in [(0, -0.12, 0.1), (0, 0.06, 0.1), (0, 0.22, 0.08), (-0.14, -0.06, 0.08), (0.14, -0.06, 0.08), (-0.14, 0.14, 0.08), (0.14, 0.14, 0.08)]:
        y = 0.05 + 0.16 * math.sqrt(max(0, 1 - (x / 0.3) ** 2 - (z / 0.38) ** 2)) - 0.012
        m.add("C1Dark", *sphere((x, y, z), (s, 0.025, s * 1.1), 6, 6))
    m.add("C3", *sphere((0, 0.04, -0.45), (0.09, 0.08, 0.11), 18, 12))
    for s in (-1, 1):
        eye(m, (s * 0.06, 0.07, -0.5), (s, 0.3, -0.6), 0.022)
        outline = [(0, -0.04), (0.2, -0.03), (0.34, 0.06), (0.2, 0.06), (0, 0.05)]
        m.add("C3", *fin(outline, (s * 0.25, 0.0, -0.2), (s * 0.9, -0.1, 0.3), (0, 0, 1), 0.02, segs_per_edge=2))
        outline2 = [(0, -0.03), (0.12, 0.0), (0.12, 0.05), (0, 0.04)]
        m.add("C3", *fin(outline2, (s * 0.2, 0.0, 0.28), (s * 0.8, -0.1, 0.5), (0, 0, 1), 0.02, segs_per_edge=2))
    markers(m, (0, 0, -0.58), (0, 0.5, 0))
    return m


BUILDERS = {
    "fish": build_fish, "shark": build_shark, "whale": build_whale, "puffer": build_puffer, "eel": build_eel,
    "angler": build_angler, "ray": build_ray, "jelly": build_jelly, "squid": build_squid, "octopus": build_octopus,
    "turtle": build_turtle,
}


def parse_fish():
    """Читает список рыб из GameData.luau (Id, Shape и флаги)."""
    import re
    src = open(os.path.join(ROOT, "src", "shared", "GameData.luau"), encoding="utf-8").read()
    out = []
    for line in src.splitlines():
        m = re.search(r'\{\s*Id = "([^"]+)", Zone = \d+, Rarity = R\.\w+, Shape = "(\w+)"(.*)\}', line)
        if m:
            flags = {k: True for k in re.findall(r"(\w+) = true", m.group(3))}
            out.append(dict(Id=m.group(1), Shape=m.group(2), **flags))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for d in parse_fish():
        if only and d["Id"] not in only:
            continue
        model = BUILDERS[d["Shape"]](d)
        path = os.path.join(OUT, d["Id"].replace(" ", "_") + ".glb")
        model.write(path)
        tris = sum(len(mm.f) for mm in model.meshes.values())
        print(f"{d['Id']:20s} {d['Shape']:8s} parts={len(model.meshes):2d} tris={tris}")


if __name__ == "__main__":
    main()
