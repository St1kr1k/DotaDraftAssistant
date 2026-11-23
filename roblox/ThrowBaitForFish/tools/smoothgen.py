#!/usr/bin/env python3
"""Гладкие мультяшные рыбы: форма и цвета из воксельных моделей (voxelgen), но тело — гладкая поверхность.

1. Строим воксельную модель без шума оттенков.
2. «Мягкие» вокселы (тело, плавники, щупальца) -> поле плотности -> размытие -> Surface Nets -> сглаживание.
3. Цвет каждого треугольника берём у ближайшего воксела (ровная заливка, без ступенек и пятен).
4. Глаза, зрачки, блики и зубы остаются кубическими (как в стиле Throw Food For Animals).

Запуск: python3 tools/smoothgen.py [fishId ...] -> build/smooth/<id>.glb
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("VOXEL_MIN_THICK", "0.026")
os.environ.setdefault("VOXEL_PATTERNS", "0")
import voxelgen  # noqa: E402
from glb import write_glb  # noqa: E402
import meshgen  # noqa: E402

ROOT = voxelgen.ROOT
OUT = os.path.join(ROOT, "build", os.environ.get("SMOOTH_OUT", "smooth"))
HARD = {"Eye", "Pupil", "Tooth"}
os.environ.setdefault("VOXEL_MIN_THICK", "0.026")
os.environ.setdefault("VOXEL_PATTERNS", "0")

# без шума оттенков: ровная заливка
voxelgen.shade = lambda color, i, j, k, amount=0.07, seed=0: tuple(color)


def blur(field, sigma):
    r = max(1, int(round(sigma * 2.5)))
    xs = np.arange(-r, r + 1)
    w = np.exp(-(xs ** 2) / (2 * sigma * sigma))
    w /= w.sum()
    for axis in range(3):
        acc = np.zeros_like(field)
        for off, wk in zip(xs, w):
            acc += wk * np.roll(field, off, axis=axis)
        field = acc
    return field


def surface_nets(F, iso=0.5):
    inside = F > iso
    X, Y, Z = F.shape
    # углы ячеек
    c = [F[a:X - 1 + a, b:Y - 1 + b, d:Z - 1 + d] for a in (0, 1) for b in (0, 1) for d in (0, 1)]
    corner_off = [(a, b, d) for a in (0, 1) for b in (0, 1) for d in (0, 1)]
    ins = [ci > iso for ci in c]
    any_in = np.zeros_like(ins[0])
    all_in = np.ones_like(ins[0])
    for x in ins:
        any_in |= x
        all_in &= x
    active = any_in & ~all_in
    edges = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
    sum_p = np.zeros(active.shape + (3,))
    cnt = np.zeros(active.shape)
    for a, b in edges:
        va, vb = c[a], c[b]
        cross = (va > iso) != (vb > iso)
        t = np.where(cross, (iso - va) / np.where(np.abs(vb - va) < 1e-9, 1e-9, vb - va), 0)
        pa = np.array(corner_off[a], float)
        pb = np.array(corner_off[b], float)
        p = pa + (pb - pa) * t[..., None]
        sum_p += np.where(cross[..., None], p, 0)
        cnt += cross
    idx = -np.ones(active.shape, dtype=np.int64)
    act = np.argwhere(active)
    idx[active] = np.arange(len(act))
    base = act.astype(float)
    verts = base + sum_p[active] / np.maximum(cnt[active], 1)[:, None]
    faces = []
    # рёбра вдоль каждой оси между соседними вокселами
    for axis in range(3):
        sl_a = [slice(None)] * 3
        sl_b = [slice(None)] * 3
        sl_a[axis] = slice(0, -1)
        sl_b[axis] = slice(1, None)
        ia = inside[tuple(sl_a)]
        ib = inside[tuple(sl_b)]
        crossing = ia != ib
        pts = np.argwhere(crossing)
        u, v = [a for a in range(3) if a != axis]
        for p in pts:
            p = list(p)
            if p[u] == 0 or p[v] == 0:
                continue
            cells = []
            for du, dv in ((-1, -1), (0, -1), (0, 0), (-1, 0)):
                q = list(p)
                q[u] += du
                q[v] += dv
                if q[0] >= idx.shape[0] or q[1] >= idx.shape[1] or q[2] >= idx.shape[2]:
                    cells = None
                    break
                cells.append(idx[tuple(q)])
            if not cells or min(cells) < 0:
                continue
            a0, a1, a2, a3 = cells
            flip = bool(ia[tuple(p)])
            if axis == 1:
                flip = not flip
            if flip:
                faces += [[a0, a1, a2], [a0, a2, a3]]
            else:
                faces += [[a0, a2, a1], [a0, a3, a2]]
    return verts, np.array(faces, dtype=np.int64)


def smooth_vertices(v, f, iters=3, lam=0.5):
    n = len(v)
    for _ in range(iters):
        acc = np.zeros_like(v)
        deg = np.zeros(n)
        for a, b in ((0, 1), (1, 2), (2, 0)):
            np.add.at(acc, f[:, a], v[f[:, b]])
            np.add.at(deg, f[:, a], 1)
        avg = acc / np.maximum(deg, 1)[:, None]
        v = v + lam * (avg - v) * (deg > 0)[:, None]
    return v


def build_smooth(d, sigma=0.85):
    g = voxelgen.build(d)
    cells = g.cells
    soft = {k: v for k, v in cells.items() if v[0] not in HARD}
    keys = np.array(list(soft.keys()))
    lo = keys.min(0) - 4
    hi = keys.max(0) + 4
    shape = tuple(hi - lo + 1)
    occ = np.zeros(shape, dtype=np.float64)
    occ[tuple((keys - lo).T)] = 1.0
    F = blur(occ, sigma)
    verts, faces = surface_nets(F, 0.42)
    verts = smooth_vertices(verts, faces, 3, 0.45)
    # развернуть треугольники наружу: нормаль против градиента плотности
    gx, gy, gz = np.gradient(F)
    cent0 = verts[faces].mean(axis=1)
    ci0 = np.clip(np.round(cent0).astype(int), 0, np.array(F.shape) - 1)
    grad = np.stack([gx[tuple(ci0.T)], gy[tuple(ci0.T)], gz[tuple(ci0.T)]], axis=1)
    tri = verts[faces]
    nrm = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    bad = np.einsum("ij,ij->i", nrm, -grad) < 0
    faces[bad] = faces[bad][:, [0, 2, 1]]
    # цвет треугольника = цвет ближайшего мягкого воксела
    cent = verts[faces].mean(axis=1)
    lab = {}
    names = []
    color_grid = -np.ones(shape, dtype=np.int64)
    for (key, (role, col)) in soft.items():
        name = f"{role}_{col[0]:02x}{col[1]:02x}{col[2]:02x}"
        if name not in lab:
            lab[name] = len(names)
            names.append(name)
        color_grid[tuple(np.array(key) - lo)] = lab[name]
    # заполнить пустые клетки рядом с поверхностью цветом соседей
    for _ in range(4):
        empty = color_grid < 0
        if not empty.any():
            break
        for axis in range(3):
            for sh in (1, -1):
                rolled = np.roll(color_grid, sh, axis=axis)
                fill = empty & (rolled >= 0)
                color_grid[fill] = rolled[fill]
                empty = color_grid < 0
    # цвет вершин -> сглаживание меток по соседям (ровные границы цвета вместо «зубцов»)
    vi = np.clip(np.round(verts).astype(int), 0, np.array(shape) - 1)
    vlab = color_grid[vi[:, 0], vi[:, 1], vi[:, 2]]
    vlab[vlab < 0] = 0
    nb = [[] for _ in range(len(verts))]
    for a, b in ((0, 1), (1, 2), (2, 0)):
        for x, y in zip(faces[:, a], faces[:, b]):
            nb[x].append(y)
            nb[y].append(x)
    for _ in range(2):
        new = vlab.copy()
        for vtx in range(len(verts)):
            if nb[vtx]:
                vals, counts = np.unique(vlab[nb[vtx]], return_counts=True)
                best = vals[counts.argmax()]
                if counts.max() > len(nb[vtx]) // 2:
                    new[vtx] = best
        vlab = new
    fl = vlab[faces]
    face_lab = np.where(fl[:, 1] == fl[:, 2], fl[:, 1], fl[:, 0])
    world = (verts + lo) * g.s
    meshes = []
    for li, name in enumerate(names):
        sel = faces[face_lab == li]
        if len(sel) == 0:
            continue
        used = np.unique(sel)
        remap = -np.ones(len(world), dtype=np.int64)
        remap[used] = np.arange(len(used))
        meshes.append({"name": name, "verts": world[used], "faces": remap[sel]})
    # жёсткие кубические детали
    hard = voxelgen.Grid.__new__(voxelgen.Grid)
    hard.res, hard.s = g.res, g.s
    hard.cells = {k: v for k, v in cells.items() if v[0] in HARD}
    for name, (vv, ff) in hard.to_meshes().items():
        meshes.append({"name": name, "verts": np.array(vv), "faces": np.array(ff)})
    for name, p in (("Nose", (0, 0, -0.7)), ("Top", (0, 0.7, 0))):
        vv, ff = meshgen.sphere(p, (0.004, 0.004, 0.004), 6, 4)
        meshes.append({"name": name, "verts": np.array(vv), "faces": np.array(ff)})
    return meshes


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for d in voxelgen.parse_fish_with_colors():
        if only and d["Id"] not in only:
            continue
        meshes = build_smooth(d)
        write_glb(os.path.join(OUT, d["Id"].replace(" ", "_") + ".glb"), meshes)
        tris = sum(len(m["faces"]) for m in meshes)
        big = max(len(m["faces"]) for m in meshes)
        print(f"{d['Id']:20s} parts={len(meshes):3d} tris={tris} maxmesh={big}", flush=True)


if __name__ == "__main__":
    main()
