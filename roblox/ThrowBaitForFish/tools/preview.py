#!/usr/bin/env python3
"""Программный рендер превью рыб (numpy + PIL): z-буфер, мягкий свет, цвета ролей как в игре.
python3 tools/preview.py -> build/fish_preview.png"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshgen  # noqa: E402

ROOT = meshgen.ROOT


def game_colors():
    src = open(os.path.join(ROOT, "src", "shared", "GameData.luau"), encoding="utf-8").read()
    out = {}
    for line in src.splitlines():
        m = re.search(r'Id = "([^"]+)".*?C1 = rgb\((\d+), (\d+), (\d+)\), C2 = rgb\((\d+), (\d+), (\d+)\), C3 = rgb\((\d+), (\d+), (\d+)\)', line)
        if m:
            v = list(map(int, m.groups()[1:]))
            out[m.group(1)] = (tuple(v[0:3]), tuple(v[3:6]), tuple(v[6:9]))
    return out


def role_color(role, c1, c2, c3):
    return {
        "C1": c1, "C2": c2, "C3": c3,
        "C1Dark": tuple(int(x * 0.6) for x in c1),
        "Eye": (250, 250, 250), "Pupil": (20, 20, 25), "Shine": (255, 255, 255),
        "Dark": (25, 15, 20), "Tooth": (250, 250, 245), "Glow": c3,
    }.get(role)


def render(model, cols, size=360, yaw=0.9, pitch=-0.3):
    W = H = size
    img = np.zeros((H, W, 3), dtype=np.float32)
    img[:] = (0.93, 0.96, 1.0)
    zbuf = np.full((H, W), np.inf)
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    R = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]) @ np.eye(3)
    R = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]]) @ R
    allv = np.concatenate([np.array(m.v) for m in model.meshes.values() if m.f and m.name not in ("Nose", "Top")])
    center = (allv.max(0) + allv.min(0)) / 2
    scale = 0.82 * size / max(1e-6, np.ptp(allv @ R.T, axis=0)[:2].max())
    light = np.array([-0.4, 0.8, -0.5])
    light /= np.linalg.norm(light)
    for mesh in model.meshes.values():
        col = role_color(mesh.name, *cols)
        if col is None or not mesh.f:
            continue
        col = np.array(col) / 255
        v = (np.array(mesh.v) - center) @ R.T
        f = np.array(mesh.f)
        sx = v[:, 0] * scale + W / 2
        syy = -v[:, 1] * scale + H / 2
        z = v[:, 2]
        tri = v[f]
        nrm = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        ln = np.linalg.norm(nrm, axis=1, keepdims=True)
        ln[ln == 0] = 1
        nrm /= ln
        for k, (a, b, c) in enumerate(f):
            n = nrm[k]
            if n[2] > 0:
                n = -n
            shade = 0.45 + 0.55 * max(0.0, float(np.dot(-n, -light)) * -1 if False else abs(float(np.dot(n, light))))
            if mesh.name in ("Shine", "Glow"):
                shade = 1.1
            xs = np.array([sx[a], sx[b], sx[c]])
            ys = np.array([syy[a], syy[b], syy[c]])
            zs = np.array([z[a], z[b], z[c]])
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


def main():
    colors = game_colors()
    fish = meshgen.parse_fish()
    only = set(sys.argv[1:])
    if only:
        fish = [d for d in fish if d["Id"] in only]
    cell = 300
    cols_n = 5
    rows = math.ceil(len(fish) / cols_n)
    sheet = Image.new("RGB", (cols_n * cell, rows * (cell + 30)), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for i, d in enumerate(fish):
        model = meshgen.BUILDERS[d["Shape"]](d)
        im = render(model, colors[d["Id"]], cell)
        x, y = (i % cols_n) * cell, (i // cols_n) * (cell + 30)
        sheet.paste(im, (x, y))
        draw.text((x + 8, y + cell + 6), d["Id"], fill=(0, 0, 0))
        print("rendered", d["Id"], flush=True)
    out = os.path.join(ROOT, "build", "fish_preview.png")
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
