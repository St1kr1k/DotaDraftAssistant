"""Простой программный рендер треугольников (z-буфер, мягкий свет) для превью анимаций."""
import math

import numpy as np
from PIL import Image, ImageDraw


def view_matrix(yaw, pitch):
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    return Rx @ Ry


def render(meshes, size=320, yaw=0.6, pitch=-0.25, center=(0, 0, 0), scale=28.0, bg=(236, 242, 250), ground=0.0):
    W = H = size
    img = np.zeros((H, W, 3), dtype=np.float32)
    img[:] = np.array(bg) / 255
    zbuf = np.full((H, W), np.inf)
    R = view_matrix(yaw, pitch)
    light = np.array([-0.4, 0.8, -0.45])
    light /= np.linalg.norm(light)
    c = np.array(center, float)
    # пол — сетка-подсказка
    meshes = list(meshes)
    g = []
    for gx in range(-8, 9, 2):
        g.append((np.array([[gx, ground, -8], [gx + 0.08, ground, -8], [gx + 0.08, ground, 8], [gx, ground, 8]]), [[0, 1, 2], [0, 2, 3]], (200, 205, 215)))
        g.append((np.array([[-8, ground, gx], [8, ground, gx], [8, ground, gx + 0.08], [-8, ground, gx + 0.08]]), [[0, 1, 2], [0, 2, 3]], (200, 205, 215)))
    allm = [(None, v, f, col) for v, f, col in g] + meshes
    for item in allm:
        _, v, f, col = item
        col = np.array(col) / 255
        vv = (np.asarray(v, float) - c) @ R.T
        sx = vv[:, 0] * scale + W / 2
        syy = -vv[:, 1] * scale + H * 0.6
        z = vv[:, 2]
        for (a, b, cc) in f:
            tri = vv[[a, b, cc]]
            n = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            ln = np.linalg.norm(n)
            if ln < 1e-9:
                continue
            n /= ln
            shade = 0.5 + 0.5 * abs(float(np.dot(n, R @ light)))
            xs = np.array([sx[a], sx[b], sx[cc]])
            ys = np.array([syy[a], syy[b], syy[cc]])
            zs = np.array([z[a], z[b], z[cc]])
            x0, x1 = int(max(0, xs.min())), int(min(W - 1, xs.max() + 1))
            y0, y1 = int(max(0, ys.min())), int(min(H - 1, ys.max() + 1))
            if x1 < x0 or y1 < y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(d) < 1e-9:
                continue
            l1 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
            l2 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
            l3 = 1 - l1 - l2
            inside = (l1 >= -0.01) & (l2 >= -0.01) & (l3 >= -0.01)
            if not inside.any():
                continue
            zz = l1 * zs[0] + l2 * zs[1] + l3 * zs[2]
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            upd = inside & (zz < sub)
            sub[upd] = zz[upd]
            img[y0:y1 + 1, x0:x1 + 1][upd] = np.clip(col * shade, 0, 1)
    return Image.fromarray((img * 255).astype(np.uint8))


def sheet(images, labels, cols=6):
    w, h = images[0].size
    rows = math.ceil(len(images) / cols)
    out = Image.new("RGB", (cols * w, rows * (h + 18)), (255, 255, 255))
    d = ImageDraw.Draw(out)
    for i, (im, lb) in enumerate(zip(images, labels)):
        x, y = (i % cols) * w, (i // cols) * (h + 18)
        out.paste(im, (x, y))
        d.text((x + 4, y + h + 3), lb, fill=(0, 0, 0))
    return out
