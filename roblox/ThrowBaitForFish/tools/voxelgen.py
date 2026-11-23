#!/usr/bin/env python3
"""Воксельные модели рыб в стиле «кубиков» (как в Throw Food For Animals / Crossy Road).

Модель = сетка вокселов. Каждый воксел: роль (C1/C2/C3/Eye/Pupil/Dark/Tooth/Glow) + цвет с лёгким шумом оттенка.
Видимые грани собираются в меши, сгруппированные по цвету. Имя меша: "<роль>_<rrggbb>" —
игра красит деталь этим цветом, а мутации перекрашивают всё, кроме глаз.

Голова в -Z, хвост в +Z, длина ~1. Запуск: python3 tools/voxelgen.py [fishId ...] -> build/voxels/<id>.glb
"""
import math
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb import write_glb  # noqa: E402
import meshgen  # noqa: E402

ROOT = meshgen.ROOT
OUT = os.path.join(ROOT, "build", "voxels")

FACES = [
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]


def hash3(i, j, k, seed=0):
    h = (i * 73856093) ^ (j * 19349663) ^ (k * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF) / 0xFFFF


def shade(color, i, j, k, amount=0.07, seed=0):
    """Лёгкий шум оттенка, квантованный в 3 уровня — как текстура вокселов."""
    h = hash3(i, j, k, seed)
    f = 1 - amount if h < 0.33 else (1 + amount * 0.7 if h > 0.72 else 1.0)
    return tuple(int(max(0, min(255, c * f))) for c in color)


class Grid:
    def __init__(self, res=30):
        self.res = res          # вокселов на единицу длины
        self.s = 1.0 / res
        self.cells = {}

    def idx(self, x, y, z):
        return (int(math.floor(x * self.res + 0.5)), int(math.floor(y * self.res + 0.5)), int(math.floor(z * self.res + 0.5)))

    def center(self, i, j, k):
        return (i * self.s, j * self.s, k * self.s)

    def set(self, i, j, k, role, color):
        self.cells[(i, j, k)] = (role, color)

    def fill(self, bounds, inside, color_fn, overwrite=True, mirror=False):
        (x0, x1), (y0, y1), (z0, z1) = bounds
        r = self.res
        for i in range(int(math.floor(x0 * r)) - 1, int(math.ceil(x1 * r)) + 2):
            for j in range(int(math.floor(y0 * r)) - 1, int(math.ceil(y1 * r)) + 2):
                for k in range(int(math.floor(z0 * r)) - 1, int(math.ceil(z1 * r)) + 2):
                    x, y, z = self.center(i, j, k)
                    if inside(x, y, z):
                        if overwrite or (i, j, k) not in self.cells:
                            role, col = color_fn(x, y, z, i, j, k)
                            self.cells[(i, j, k)] = (role, col)

    def ellipsoid(self, c, rad, color_fn, overwrite=True):
        cx, cy, cz = c
        rx, ry, rz = rad
        self.fill(((cx - rx, cx + rx), (cy - ry, cy + ry), (cz - rz, cz + rz)),
                  lambda x, y, z: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1.0,
                  color_fn, overwrite)

    def box(self, a, b, color_fn, overwrite=True):
        self.fill(((min(a[0], b[0]), max(a[0], b[0])), (min(a[1], b[1]), max(a[1], b[1])), (min(a[2], b[2]), max(a[2], b[2]))),
                  lambda x, y, z: min(a[0], b[0]) - 1e-6 <= x <= max(a[0], b[0]) + 1e-6 and min(a[1], b[1]) - 1e-6 <= y <= max(a[1], b[1]) + 1e-6 and min(a[2], b[2]) - 1e-6 <= z <= max(a[2], b[2]) + 1e-6,
                  color_fn, overwrite)

    def poly_slab(self, poly_yz, x_half, color_fn, overwrite=False, x_center=0.0):
        """Плоский плавник: многоугольник в плоскости YZ (точки (z, y)), толщина 2*x_half."""
        zs = [p[0] for p in poly_yz]
        ys = [p[1] for p in poly_yz]

        def inside_poly(z, y):
            c = False
            n = len(poly_yz)
            for a in range(n):
                z1, y1 = poly_yz[a]
                z2, y2 = poly_yz[(a + 1) % n]
                if (y1 > y) != (y2 > y):
                    zc = z1 + (y - y1) * (z2 - z1) / (y2 - y1)
                    if z < zc:
                        c = not c
            return c
        self.fill(((x_center - x_half, x_center + x_half), (min(ys), max(ys)), (min(zs), max(zs))),
                  lambda x, y, z: abs(x - x_center) <= x_half + 1e-6 and inside_poly(z, y), color_fn, overwrite)

    def line(self, pts, radius, color_fn, overwrite=True):
        radius = max(radius, self.s * 0.88)  # тоньше — линия рассыпается на отдельные кубики
        for a, b in zip(pts, pts[1:]):
            a = np.array(a, float)
            b = np.array(b, float)
            n = max(2, int(np.linalg.norm(b - a) / (self.s * 0.5)))
            for q in range(n + 1):
                p = a + (b - a) * q / n
                self.ellipsoid(tuple(p), (radius, radius, radius), color_fn, overwrite)

    def mirror_x(self):
        for (i, j, k), v in list(self.cells.items()):
            if i > 0:
                self.cells[(-i, j, k)] = v

    def to_meshes(self):
        groups = {}
        cells = self.cells
        s = self.s
        for (i, j, k), (role, col) in cells.items():
            for (dx, dy, dz), quad in FACES:
                if (i + dx, j + dy, k + dz) in cells:
                    continue
                key = f"{role}_{col[0]:02x}{col[1]:02x}{col[2]:02x}"
                g = groups.setdefault(key, ([], []))
                base = len(g[0])
                for (qx, qy, qz) in quad:
                    g[0].append(((i - 0.5 + qx) * s, (j - 0.5 + qy) * s, (k - 0.5 + qz) * s))
                g[1].append([base, base + 1, base + 2])
                g[1].append([base, base + 2, base + 3])
        return groups


def solid(role, color, seed=0, amount=0.07):
    return lambda x, y, z, i, j, k: (role, shade(color, i, j, k, amount, seed))


def darker(c, f=0.7):
    return tuple(int(v * f) for v in c)


def lighter(c, f=0.35):
    return tuple(int(v + (255 - v) * f) for v in c)


# ===================== части =====================

def body_fill(g, body, d, belly_line=-0.2):
    """Тело по профилю meshgen.Body: верх C1, живот C2 (прямая линия), полосы/пятна."""
    c1, c2, c3 = d["C1"], d["C2"], d["C3"]

    def color(x, y, z, i, j, k):
        t = (z - body.z0) / body.L
        cx, cy, w, h = body.section(t)
        rel = (y - cy) / max(h, 1e-6)
        if d.get("Stripes"):
            for tc in (0.3, 0.6):
                if abs(t - tc) < 0.045:
                    return ("C2", shade(c2, i, j, k))
                if abs(t - tc) < 0.065:
                    return ("C1Dark", shade(darker(c1, 0.55), i, j, k))
        if d.get("Spots") and rel > -0.1 and hash3(i // 2, j // 2, k // 2, 7) > 0.84:
            return ("C3", shade(c3, i, j, k))
        if rel < belly_line:
            return ("C2", shade(c2, i, j, k))
        if rel > 0.75:
            return ("C1", shade(darker(c1, 0.85), i, j, k))
        return ("C1", shade(c1, i, j, k))

    def inside(x, y, z):
        t = (z - body.z0) / body.L
        if t <= 0 or t >= 1:
            return False
        cx, cy, w, h = body.section(t)
        if w <= 0 or h <= 0:
            return False
        return ((x - cx) / w) ** 2 + ((y - cy) / h) ** 2 <= 1.0
    W = body.W * 1.2
    H = body.H * 1.3
    g.fill(((-W, W), (-H, H), (body.z0, body.z0 + body.L)), inside, color)


def eyes(g, body, t, up=0.35, size=2, cute=False, pupil_color=(15, 15, 20)):
    """Квадратные глаза: белый блок size×size, зрачок спереди-снизу, выступает на 1 воксел."""
    z = body.z0 + body.L * t
    cx, cy, w, h = body.section(t)
    y = cy + h * up
    i_side = int(round((cx + w * math.sqrt(max(0.0, 1 - up * up))) * g.res))
    j0 = int(round(y * g.res))
    k0 = int(round(z * g.res))
    sz = size + (1 if cute else 0)
    for side in (1, -1):
        for dj in range(sz):
            for dk in range(sz):
                g.set(side * (i_side + 1), j0 + dj - sz // 2, k0 + dk - sz // 2, "Eye", (250, 250, 250))
                g.set(side * i_side, j0 + dj - sz // 2, k0 + dk - sz // 2, "Eye", (250, 250, 250))
        pj = j0 - sz // 2
        pk = k0 - sz // 2
        for dj in range(max(1, sz - 1)):
            for dk in range(max(1, sz - 1)):
                g.set(side * (i_side + 2) if False else side * (i_side + 1), pj + dj, pk + dk, "Pupil", pupil_color)
        g.set(side * (i_side + 1), pj + sz - 1, pk + sz - 1 if sz > 1 else pk, "Eye", (255, 255, 255))


def markers_cells(g, nose_z, top_y):
    # маркеры — отдельные крошечные меши
    pass


def tail_fork(g, z_root, y_c, h, l, color, xh=None):
    xh = xh if xh is not None else g.s * 0.6
    poly = [(z_root, y_c + h * 0.2), (z_root + l * 0.6, y_c + h * 0.7), (z_root + l, y_c + h), (z_root + l * 0.55, y_c),
            (z_root + l, y_c - h), (z_root + l * 0.6, y_c - h * 0.7), (z_root, y_c - h * 0.2)]
    g.poly_slab(poly, xh, lambda x, y, z, i, j, k: ("C3", shade(color if abs(y - y_c) < h * 0.75 else darker(color, 0.8), i, j, k)))


def dorsal_fin(g, z0, z1, y_base, height, color, sweep=0.3):
    poly = [(z0, y_base - g.s), (z0 + (z1 - z0) * 0.25 + sweep * height, y_base + height), (z1, y_base + height * 0.25), (z1, y_base - g.s)]
    g.poly_slab(poly, g.s * 0.6, lambda x, y, z, i, j, k: ("C3", shade(color if y < y_base + height * 0.7 else darker(color, 0.8), i, j, k)))


def side_fin(g, z, y, x, length, color, down=0.6):
    for side in (1, -1):
        pts = [(side * x, y, z), (side * (x + length * 0.7), y - length * down * 0.6, z + length * 0.4)]
        g.line(pts, g.s * 0.7, lambda *_a: ("C3", color))


# ===================== формы =====================

def v_fish(d):
    g = Grid(30)
    tall = 1.55 if d.get("Tall") else 1.0
    big = 1.12 if d.get("Big") else 1.0
    b = meshgen.Body(width=0.16 * big, height=0.22 * tall * big, head=0.33, tail=0.95, power=2.0)
    body_fill(g, b, d)
    _, cy, w, h = b.section(0.35)
    dorsal_fin(g, -0.12, 0.2, cy + h * 0.85, 0.16 * tall, d["C3"])
    tail_fork(g, 0.42, 0.0, 0.2 * tall ** 0.6, 0.26, d["C3"])
    _, cyb, _, hb = b.section(0.6)
    g.poly_slab([(0.05, cyb - hb * 0.8), (0.18, cyb - hb - 0.08), (0.22, cyb - hb * 0.6)], g.s * 0.6, solid("C3", d["C3"]))
    side_fin(g, -0.12, cy - h * 0.35, w * 0.8, 0.14, d["C3"])
    eyes(g, b, 0.17, 0.3, 3 if d.get("Big") else 2, cute=True)
    mouth(g, b)
    if d.get("Sword"):
        g.line([(0, 0.0, -0.5), (0, 0.01, -0.92)], g.s * 0.7, solid("C2", d["C2"]))
    if d.get("Spikes"):
        for q in range(6):
            zz = -0.15 + q * 0.06
            g.line([(0, cy + h * 0.9, zz), (0, cy + h + 0.22, zz + 0.05)], g.s * 0.5, solid("C2", d["C2"]))
    return g


def mouth(g, b, w=2):
    t = 0.02
    z = b.z0 + b.L * t
    cx, cy, _, h = b.section(0.05)
    j = int(round((cy - h * 0.25) * g.res))
    k = int(round(z * g.res))
    for i in range(-w, w + 1):
        g.set(i, j, k, "Dark", (40, 20, 25))


def v_shark(d):
    g = Grid(30)
    big = 1.1 if d.get("Big") else 1.0
    b = meshgen.Body(width=0.12 * big, height=0.14 * big, head=0.6, tail=1.15, power=2.0, droop=0.0,
                     spine_y=lambda t: 0.05 * t ** 3)
    body_fill(g, b, d, belly_line=-0.15)
    _, cy, w, h = b.section(0.38)
    g.poly_slab([(-0.12, cy + h * 0.6), (0.0, cy + h + 0.24), (0.06, cy + h + 0.22), (0.12, cy + h * 0.6)], g.s * 0.7, solid("C1", darker(d["C1"], 0.9)))
    g.poly_slab([(0.42, 0.05), (0.62, 0.42), (0.66, 0.38), (0.55, 0.05), (0.62, -0.18), (0.56, -0.2), (0.42, 0.0)], g.s * 0.7, solid("C1", d["C1"]))
    for side in (1, -1):
        g.line([(side * w * 0.8, cy - h * 0.5, -0.1), (side * (w + 0.2), cy - h - 0.1, 0.05)], g.s * 0.9, solid("C1", d["C1"]))
    # пасть
    t = 0.07
    z = b.z0 + b.L * t
    cx, cyy, ww, hh = b.section(t)
    k = int(round(z * g.res))
    jm = int(round((cyy - hh * 0.35) * g.res))
    for i in range(-2, 3):
        g.set(i, jm, k, "Dark", (120, 30, 40))
        g.set(i, jm, k + 1, "Dark", (120, 30, 40))
        if d.get("Teeth") and i % 2 == 0:
            g.set(i, jm + 1, k - 1, "Tooth", (250, 250, 245))
            g.set(i, jm - 1, k - 1, "Tooth", (250, 250, 245))
    for side in (1, -1):
        for q in range(3):
            zz = int(round((b.z0 + b.L * (0.2 + q * 0.03)) * g.res))
            ii = int(round((ww * 0.95) * g.res)) + 1
            for jj in range(-1, 2):
                g.set(side * ii, jj, zz, "C1Dark", darker(d["C1"], 0.6))
    if d.get("Cute"):
        eyes(g, b, 0.12, 0.25, 2, cute=True)
    else:
        z = b.z0 + b.L * 0.1
        _, cy2, w2, h2 = b.section(0.1)
        for side in (1, -1):
            g.set(side * (int(round(w2 * 0.85 * g.res)) + 1), int(round((cy2 + h2 * 0.2) * g.res)), int(round(z * g.res)), "Glow" if d.get("Glow") else "Pupil", d["C3"] if d.get("Glow") else (15, 15, 20))
    if d.get("Hammer"):
        g.box((-0.2, -0.01, -0.5), (0.2, 0.03, -0.44), solid("C1", d["C1"]))
        for side in (1, -1):
            g.set(side * int(round(0.2 * g.res)), 0, int(round(-0.47 * g.res)), "Pupil", (15, 15, 20))
    return g


def v_whale(d):
    g = Grid(30)
    b = meshgen.Body(width=0.17, height=0.16, head=0.3, tail=1.2, power=2.0, droop=0.01, spine_y=lambda t: 0.03 * t * t)
    body_fill(g, b, d, belly_line=-0.25)
    if d.get("Orca"):
        g.ellipsoid((0.0, 0.0, 0.0), (0.0001, 0.0001, 0.0001), solid("C1", d["C1"]))
        for side in (1, -1):
            g.ellipsoid((side * 0.13, 0.05, -0.28), (0.04, 0.035, 0.06), solid("Eye", (250, 250, 250), amount=0.02))
        _, cy, w, h = b.section(0.42)
        g.poly_slab([(-0.08, cy + h * 0.7), (0.0, cy + h + 0.3), (0.05, cy + h + 0.28), (0.06, cy + h * 0.7)], g.s * 0.7, solid("C1", d["C1"]))
    else:
        _, cy, w, h = b.section(0.68)
        g.poly_slab([(0.15, cy + h * 0.7), (0.2, cy + h + 0.05), (0.24, cy + h * 0.7)], g.s * 0.7, solid("C1", d["C1"]))
    # хвостовые лопасти (горизонтальные)
    for side in (1, -1):
        g.line([(0, 0.03, 0.45), (side * 0.12, 0.04, 0.53), (side * 0.2, 0.05, 0.6)], g.s * 0.8, solid("C1", d["C1"]))
    for side in (1, -1):
        g.line([(side * 0.14, -0.08, -0.12), (side * 0.27, -0.15, 0.0)], g.s * 0.9, solid("C1", d["C1"]))
    eyes(g, b, 0.22, -0.05, 2)
    if d.get("Glow"):
        for q in range(8):
            g.set(int(round(0.06 * math.sin(q * 2) * g.res)), int(round(0.16 * g.res)), int(round((-0.25 + q * 0.07) * g.res)), "Glow", d["C3"])
    return g


def v_puffer(d):
    g = Grid(30)
    b = meshgen.Body(length=0.8, z0=-0.4, width=0.34, height=0.32, head=0.5, tail=0.6, power=2.0, droop=0.0)
    body_fill(g, b, d, belly_line=-0.3)
    if d.get("Spikes"):
        for q in range(60):
            th = q * 2.399
            yv = 1 - 2 * (q + 0.5) / 60
            r = math.sqrt(max(0, 1 - yv * yv))
            v = np.array([math.cos(th) * r, yv, math.sin(th) * r])
            if v[2] < -0.7:
                continue
            p0 = np.array([v[0] * 0.33, v[1] * 0.31, v[2] * 0.38])
            g.line([tuple(p0), tuple(p0 + v * 0.07)], g.s * 0.5, solid("C3", d["C3"]))
    tail_fork(g, 0.36, 0.0, 0.1, 0.12, d["C3"])
    eyes(g, b, 0.2, 0.3, 3, cute=True)
    mouth(g, b, 1)
    return g


def v_eel(d):
    g = Grid(34)
    b = meshgen.Body(width=0.055, height=0.065, head=0.15, tail=0.55, power=2.0, droop=0.0,
                     spine_x=lambda t: 0.08 * math.sin(t * math.pi * 2.2) * t)
    body_fill(g, b, d, belly_line=-0.3)
    for q in range(40):
        t = 0.2 + q * 0.019
        cx, cy, w, h = b.section(t)
        z = b.z0 + b.L * t
        role = "Glow" if d.get("Glow") else "C3"
        hh = 0.03 * math.sin(math.pi * q / 40) + 0.012
        g.box((cx, cy + h, z), (cx, cy + h + hh, z + 0.02), lambda *a: (role, d["C3"]), overwrite=False)
    if d.get("Spikes"):
        for q in range(9):
            t = 0.1 + q * 0.08
            cx, cy, w, h = b.section(t)
            z = b.z0 + b.L * t
            g.line([(cx, cy + h, z), (cx, cy + h + 0.07, z + 0.03)], g.s * 0.5, solid("C3", d["C3"]))
    eyes(g, b, 0.05, 0.3, 2)
    return g


def v_angler(d):
    g = Grid(30)
    b = meshgen.Body(length=0.85, z0=-0.42, width=0.26, height=0.24, head=0.28, tail=0.85, power=2.0, droop=0.0)
    body_fill(g, b, d, belly_line=-0.3)
    g.box((-0.18, -0.1, -0.45), (0.18, 0.0, -0.36), solid("Dark", (40, 15, 25), amount=0.0))
    for q in range(-4, 5):
        x = q * 0.04
        g.set(int(round(x * g.res)), int(round(0.0 * g.res)), int(round(-0.45 * g.res)) - 1, "Tooth", (250, 250, 240))
        g.set(int(round(x * g.res)) + (1 if q % 2 else 0), int(round(-0.1 * g.res)), int(round(-0.45 * g.res)) - 1, "Tooth", (250, 250, 240))
    g.line([(0, 0.2, -0.2), (0, 0.33, -0.32), (0, 0.33, -0.48), (0, 0.27, -0.55)], g.s * 0.5, solid("C1", d["C1"]))
    g.ellipsoid((0, 0.24, -0.58), (0.045, 0.045, 0.045), solid("Glow", d["C3"], amount=0.0))
    tail_fork(g, 0.4, 0.0, 0.13, 0.14, d["C3"])
    eyes(g, b, 0.2, 0.45, 2)
    return g


def v_ray(d):
    g = Grid(30)
    c1, c2 = d["C1"], d["C2"]

    def inside(x, y, z):
        span = 0.62 * (1 + 0.3 * (abs(x) / 0.6))
        zz = z - 0.16 * (x / 0.7) ** 2
        rad = (x / 0.8) ** 2 + (zz / 0.32) ** 2
        if rad > 1:
            return False
        thick = 0.07 * (1 - 0.85 * min(1, abs(x) / 0.75)) + 0.012
        return abs(y) <= thick * math.sqrt(max(0, 1 - rad)) + 0.012

    def color(x, y, z, i, j, k):
        if y < 0:
            return ("C2", shade(c2, i, j, k))
        if d.get("Spots") and hash3(i // 2, 0, k // 2, 3) > 0.85:
            return ("C3", shade(d["C3"], i, j, k))
        return ("C1", shade(c1, i, j, k))
    g.fill(((-0.8, 0.8), (-0.1, 0.1), (-0.4, 0.5)), inside, color)
    for side in (1, -1):
        g.line([(side * 0.08, 0.0, -0.3), (side * 0.1, -0.02, -0.42), (side * 0.07, -0.05, -0.45)], g.s * 0.7, solid("C1", c1))
        g.set(side * int(round(0.13 * g.res)), 1, int(round(-0.27 * g.res)), "Eye", (250, 250, 250))
        g.set(side * int(round(0.14 * g.res)), 1, int(round(-0.28 * g.res)), "Pupil", (15, 15, 20))
    g.line([(0, 0, 0.3), (0, 0.0, 0.6), (0.03, 0.01, 0.9)], g.s * 0.45, solid("C1", c1))
    if d.get("Glow"):
        for q in range(6):
            g.set(int(round(0.1 * math.cos(q) * g.res)), 2, int(round((-0.05 + q * 0.04) * g.res)), "Glow", d["C3"])
    return g


def v_jelly(d):
    g = Grid(30)
    c1, c2, c3 = d["C1"], d["C2"], d["C3"]

    def inside(x, y, z):
        r = math.sqrt(x * x + z * z)
        if y < 0.02:
            return False
        return (r / 0.3) ** 2 + ((y - 0.02) / 0.28) ** 2 <= 1

    def color(x, y, z, i, j, k):
        if y < 0.08:
            return ("C2", shade(c2, i, j, k))
        if hash3(i // 3, j // 3, k // 3, 5) > 0.82:
            return ("C1", shade(lighter(c1, 0.3), i, j, k))
        return ("C1", shade(c1, i, j, k))
    g.fill(((-0.32, 0.32), (0, 0.32), (-0.32, 0.32)), inside, color)
    for q in range(12):
        a = q / 12 * math.tau
        pts = [(math.cos(a) * 0.24, 0.02 - s * 0.07, math.sin(a) * 0.24 + 0.02 * math.sin(s + q)) for s in range(9)]
        g.line(pts, g.s * 0.35, solid("C3", c3), overwrite=False)
    for q in range(4):
        a = q / 4 * math.tau + 0.4
        pts = [(math.cos(a) * 0.05 + 0.03 * math.sin(s), 0.03 - s * 0.06, math.sin(a) * 0.05) for s in range(8)]
        g.line(pts, g.s * 0.8, solid("C2", c2), overwrite=False)
    for side in (1, -1):
        for dj in range(2):
            for dk in range(2):
                g.set(side * 3 + (0 if side > 0 else 0), 5 + dj, -9 + dk, "Eye", (250, 250, 250))
        g.set(side * 3, 5, -10, "Pupil", (15, 15, 20))
    return g


def v_squid(d):
    g = Grid(32)
    big = 1.1 if d.get("Big") else 1.0
    b = meshgen.Body(length=0.6, z0=-0.1, width=0.1 * big, height=0.1 * big, head=0.15, tail=1.2, power=2.0, droop=0.0)
    body_fill(g, b, d, belly_line=-0.35)
    for side in (1, -1):
        g.poly_slab([(0.32, 0.0), (0.46, 0.0), (0.5, 0.0)], 0.0, solid("C3", d["C3"]))
        g.line([(side * 0.05, 0, 0.36), (side * 0.15, 0, 0.44), (side * 0.06, 0, 0.5)], g.s * 0.6, solid("C3", d["C3"]))
    g.ellipsoid((0, 0, -0.14), (0.085 * big, 0.08 * big, 0.08), solid("C2", d["C2"]))
    for side in (1, -1):
        for dj in range(3):
            for dk in range(3):
                g.set(side * int(round(0.085 * big * g.res + 1)), dj - 1, int(round(-0.16 * g.res)) + dk - 1, "Eye", (250, 250, 250))
        g.set(side * int(round(0.085 * big * g.res + 1)), -1, int(round(-0.16 * g.res)) - 1, "Pupil", (15, 15, 20))
        g.set(side * int(round(0.085 * big * g.res + 1)), 0, int(round(-0.16 * g.res)) - 1, "Pupil", (15, 15, 20))
    for q in range(8):
        a = q / 8 * math.tau
        dx, dy = math.cos(a), math.sin(a)
        pts = [(dx * (0.04 + s * 0.008 * s), dy * (0.04 + s * 0.008 * s), -0.2 - s * 0.05) for s in range(8)]
        g.line(pts, g.s * 0.55, solid("C1", d["C1"]))
    return g


def v_octopus(d):
    g = Grid(30)
    c1, c2 = d["C1"], d["C2"]

    def col(x, y, z, i, j, k):
        if hash3(i // 2, j // 2, k // 2, 9) > 0.86:
            return ("C1", shade(lighter(c1, 0.25), i, j, k))
        return ("C1", shade(c1, i, j, k))
    g.ellipsoid((0, 0.22, 0.05), (0.19, 0.23, 0.21), col)
    g.ellipsoid((0, 0.03, 0), (0.16, 0.07, 0.16), solid("C2", c2))
    for q in range(8):
        a = q / 8 * math.tau + math.pi / 8
        dx, dz = math.cos(a), math.sin(a)
        pts = []
        for s in range(12):
            t = s / 11
            r = 0.1 + t * 0.4
            curl = max(0, t - 0.6) * 2.5
            pts.append((dx * r - dz * curl * 0.06, 0.02 - t * 0.12 + curl * curl * 0.12, dz * r + dx * curl * 0.06))
        g.line(pts, g.s * 1.0, solid("C1", c1))
    for side in (1, -1):
        for dj in range(3):
            for dk in range(3):
                g.set(side * 5, 3 + dj, -6 + dk - 1, "Eye", (250, 250, 250))
                g.set(side * 4, 3 + dj, -6 + dk - 1, "Eye", (250, 250, 250))
        g.set(side * 5, 3, -7, "Pupil", (15, 15, 20))
        g.set(side * 5, 4, -7, "Pupil", (15, 15, 20))
    return g


def v_turtle(d):
    g = Grid(30)
    c1, c2, c3 = d["C1"], d["C2"], d["C3"]

    def shell(x, y, z, i, j, k):
        hexish = (i // 3 + (k // 3) % 2) % 2 == 0 and (k // 3) % 2 == 0
        return ("C1", shade(darker(c1, 0.8) if hexish else c1, i, j, k))
    g.fill(((-0.3, 0.3), (0.02, 0.26), (-0.36, 0.36)), lambda x, y, z: (x / 0.3) ** 2 + ((y - 0.02) / 0.22) ** 2 + (z / 0.36) ** 2 <= 1 and y >= 0.02, shell)
    g.box((-0.27, -0.03, -0.32), (0.27, 0.02, 0.32), solid("C2", c2))
    g.ellipsoid((0, 0.04, -0.44), (0.09, 0.08, 0.1), solid("C3", c3))
    for side in (1, -1):
        g.set(side * 3, 2, -15, "Eye", (250, 250, 250))
        g.set(side * 3, 2, -16, "Pupil", (15, 15, 20))
        g.line([(side * 0.25, 0, -0.18), (side * 0.42, -0.03, -0.1), (side * 0.5, -0.04, 0.0)], g.s * 0.9, solid("C3", c3))
        g.line([(side * 0.22, 0, 0.25), (side * 0.32, -0.03, 0.33)], g.s * 0.8, solid("C3", c3))
    return g


VBUILDERS = {
    "fish": v_fish, "shark": v_shark, "whale": v_whale, "puffer": v_puffer, "eel": v_eel, "angler": v_angler,
    "ray": v_ray, "jelly": v_jelly, "squid": v_squid, "octopus": v_octopus, "turtle": v_turtle,
}


def parse_fish_with_colors():
    src = open(os.path.join(ROOT, "src", "shared", "GameData.luau"), encoding="utf-8").read()
    out = []
    for line in src.splitlines():
        m = re.search(r'\{\s*Id = "([^"]+)", Zone = \d+, Rarity = R\.\w+, Shape = "(\w+)", C1 = rgb\((\d+), (\d+), (\d+)\), C2 = rgb\((\d+), (\d+), (\d+)\), C3 = rgb\((\d+), (\d+), (\d+)\)(.*)\}', line)
        if m:
            v = list(map(int, m.groups()[2:11]))
            flags = {k: True for k in re.findall(r"(\w+) = true", m.group(12))}
            out.append(dict(Id=m.group(1), Shape=m.group(2), C1=tuple(v[0:3]), C2=tuple(v[3:6]), C3=tuple(v[6:9]), **flags))
    return out


def build(d):
    g = VBUILDERS[d["Shape"]](d)
    if d["Shape"] in ("eel",):
        pass
    return g


def to_model_meshes(g):
    groups = g.to_meshes()
    meshes = [{"name": k, "verts": np.array(v), "faces": np.array(f)} for k, (v, f) in groups.items()]
    # маркеры ориентации: нос (-Z) и верх (+Y)
    for name, p in (("Nose", (0, 0, -0.7)), ("Top", (0, 0.7, 0))):
        vv, ff = meshgen.sphere(p, (0.004, 0.004, 0.004), 6, 4)
        meshes.append({"name": name, "verts": np.array(vv), "faces": np.array(ff)})
    return meshes


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for d in parse_fish_with_colors():
        if only and d["Id"] not in only:
            continue
        g = build(d)
        meshes = to_model_meshes(g)
        write_glb(os.path.join(OUT, d["Id"].replace(" ", "_") + ".glb"), meshes)
        tris = sum(len(m["faces"]) for m in meshes)
        print(f"{d['Id']:20s} voxels={len(g.cells):5d} parts={len(meshes):3d} tris={tris}")


if __name__ == "__main__":
    main()
