#!/usr/bin/env python3
"""Рендер постановочной сцены в видео: несколько персонажей по клипам, их перемещения, камера, стоп-кадры, эффекты.
python3 tools/scene.py -> build/scene_clone_combo.mp4 (+ .gif)
"""
import math
import os
import subprocess
import sys

import numpy as np
from PIL import ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clips  # noqa: E402
import render  # noqa: E402
import rig  # noqa: E402

ROOT = clips.ROOT
FPS = 30
W, H = 720, 420


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


class Actor:
    def __init__(self, name, color, visible=(0, 99)):
        self.name = name
        self.color = color
        self.events = []      # (start, clip)
        self.path = []        # (t, (x, y, z), yaw_deg, ease)
        self.visible = visible

    def play(self, t, clip):
        self.events.append((t, clip))
        self.events.sort(key=lambda e: e[0])
        return self

    def at(self, t, pos, yaw, ease="smooth"):
        self.path.append((t, np.array(pos, float), yaw, ease))
        self.path.sort(key=lambda e: e[0])
        return self

    def clip_pose(self, t):
        cur = None
        prev = None
        for i, (st, name) in enumerate(self.events):
            if st <= t:
                prev = cur
                cur = (st, name)
        if cur is None:
            return rig.full({})
        st, name = cur
        c = clips.CLIPS[name]
        lt = t - st
        if c["loop"]:
            lt %= c["length"]
        pose = rig.sample(c, min(lt, c["length"]))
        blend = 0.07
        if prev is not None and lt < blend:
            pst, pname = prev
            pc = clips.CLIPS[pname]
            plt = st - pst
            if pc["loop"]:
                plt %= pc["length"]
            ppose = rig.sample(pc, min(plt, pc["length"]))
            k = smooth(lt / blend)
            pose = {part: {f: ppose[part][f] + (pose[part][f] - ppose[part][f]) * k for f in rig.FIELDS[part]} for part in rig.FIELDS}
        return pose

    def transform(self, t):
        p = self.path
        if t <= p[0][0]:
            pos, yaw = p[0][1], p[0][2]
        elif t >= p[-1][0]:
            pos, yaw = p[-1][1], p[-1][2]
        else:
            for a, b in zip(p, p[1:]):
                if a[0] <= t <= b[0]:
                    k = (t - a[0]) / max(1e-6, b[0] - a[0])
                    e = {"smooth": smooth, "out": ease_out, "linear": lambda x: x, "in": lambda x: x ** 3}[b[3]](k)
                    pos = a[1] + (b[1] - a[1]) * e
                    yaw = a[2] + (b[2] - a[2]) * e
                    break
        m = rig.cf(tuple(pos), rig.angles(0, math.radians(yaw), 0))
        return m, pos

    def meshes(self, t, tint=None, alpha_color=None):
        if not (self.visible[0] <= t <= self.visible[1]):
            return []
        m, _ = self.transform(t)
        out = rig.figure_meshes(self.clip_pose(t), m, tint=tint if tint else self.color)
        if alpha_color:
            out = [(n, v, f, alpha_color) for (n, v, f, c) in out]
        return out


def yaw_to(src, dst):
    d = np.array(dst, float) - np.array(src, float)
    return math.degrees(math.atan2(-d[0], -d[2]))


# ===================== Сцена: комбо двойников =====================
def build_clone_combo():
    E0 = (0, 0, 0)
    M0 = (0, 0, 13)
    A0 = (-2.3, 0, 2.9)
    B0 = (2.4, 0, 2.8)
    main = Actor("Main", (240, 120, 40))
    enemy = Actor("Enemy", (150, 40, 50))
    ca = Actor("CloneA", (255, 215, 170), visible=(0.62, 2.05))
    cb = Actor("CloneB", (255, 215, 170), visible=(0.62, 2.05))

    main.play(0, "FightIdle").play(0.05, "HandSeal").play(0.7, "FightIdle").play(1.95, "DashIn").play(2.17, "FinisherPunch").play(2.92, "FightIdle")
    main.at(0, M0, 0).at(1.95, M0, 0).at(2.17, (0, 0, 3.3), 0, "out").at(4, (0, 0, 3.3), 0)

    enemy.play(0, "FightIdle")
    ea = 0.0
    yaw_e = 180.0  # смотрит на героя (+Z)
    enemy.at(0, E0, yaw_e)
    # удары двойников
    ca.play(0.62, "FightIdle").play(0.75, "CloneJabCross").play(1.3, "FightIdle").play(1.52, "CloneUppercut")
    cb.play(0.62, "FightIdle").play(1.1, "CloneRoundhouse").play(1.7, "FightIdle")
    ca.at(0, A0, yaw_to(A0, E0)).at(0.74, A0, yaw_to(A0, E0)).at(0.8, (-1.9, 0, 2.3), yaw_to(A0, E0), "out").at(1.5, (-1.9, 0, 2.3), yaw_to(A0, E0)).at(1.56, (-1.6, 0, 1.9), yaw_to(A0, E0), "out")
    cb.at(0, B0, yaw_to(B0, E0)).at(1.08, B0, yaw_to(B0, E0)).at(1.15, (2.1, 0, 2.2), yaw_to(B0, E0), "out")

    hits = []  # (время, точка, сила, цвет)
    # джеб и прямой
    enemy.play(0.87, "HurtL").play(1.0, "HurtR")
    hits += [(0.87, (0, 1.2, 0.8), 1.0), (1.0, (0, 1.0, 0.8), 1.2)]
    enemy.at(0.87, E0, yaw_e).at(1.0, (0.05, 0, -0.35), yaw_e - 6, "out").at(1.12, (0.05, 0, -0.55), yaw_e - 8, "out")
    # круговой с ноги
    enemy.play(1.3, "HurtL")
    hits += [(1.3, (0.6, 1.4, -0.3), 1.6)]
    enemy.at(1.3, (0.05, 0, -0.55), yaw_e - 8).at(1.45, (-0.7, 0, -0.9), yaw_e - 30, "out")
    # апперкот — подлёт
    enemy.play(1.71, "Launched")
    hits += [(1.71, (-0.5, 0.6, -0.6), 1.8)]
    enemy.at(1.71, (-0.7, 0, -0.9), yaw_e - 30).at(1.95, (-0.5, 2.6, -0.8), yaw_e - 10, "out").at(2.45, (-0.3, 1.2, -0.6), yaw_e, "in")
    # добивающий — враг улетает
    enemy.play(2.5, "KnockBack")
    hits += [(2.5, (0, 1.4, 0.4), 3.0)]
    enemy.at(2.5, (-0.3, 1.2, -0.6), yaw_e).at(3.15, (0, 0.6, -13), yaw_e, "out").at(4, (0, 0, -15), yaw_e)

    smokes = [(0.6, A0), (0.6, B0), (2.02, (-1.6, 0, 1.9)), (2.02, (2.1, 0, 2.2))]
    chakra = [(0.17, "hands"), (2.43, "fist")]
    stops = [(0.87, 0.04), (1.0, 0.05), (1.3, 0.07), (1.71, 0.07), (2.5, 0.16)]

    PI = math.pi
    cam = [  # (t, центр, yaw, pitch, масштаб); одинаковое время подряд = склейка
        (0.0, (0, 0.8, 13), 0.35, -0.08, 34),
        (0.6, (0, 0.6, 12.5), 0.25, -0.06, 38),
        (0.6001, (0, 0.2, 1.2), PI - 0.6, -0.34, 24),
        (1.9, (0, 0.6, 0.6), PI - 0.3, -0.28, 27),
        (1.9001, (0, 0.6, 8), PI - 1.2, -0.1, 24),
        (2.2, (0, 0.8, 3.0), PI - 0.95, -0.12, 28),
        (2.55, (0, 1.0, 1.0), PI - 0.75, -0.1, 32),
        (2.85, (0, 0.8, -3), PI - 0.9, -0.12, 22),
        (3.3, (0, 0.5, -10), PI - 1.1, -0.14, 20),
        (3.9, (0, 0.4, -12), PI - 1.2, -0.14, 20),
    ]
    slow = [(2.5, 2.85, 0.3)]  # замедление после добивающего удара
    return dict(actors=[enemy, ca, cb, main], hits=hits, smokes=smokes, chakra=chakra, stops=stops, cam=cam, length=3.9, main=main, slow=slow)


def camera_at(cam, t):
    if t <= cam[0][0]:
        k = cam[0]
        return k[1], k[2], k[3], k[4]
    for a, b in zip(cam, cam[1:]):
        if a[0] <= t <= b[0]:
            e = smooth((t - a[0]) / (b[0] - a[0]))
            c = tuple(np.array(a[1]) + (np.array(b[1]) - np.array(a[1])) * e)
            return c, a[2] + (b[2] - a[2]) * e, a[3] + (b[3] - a[3]) * e, a[4] + (b[4] - a[4]) * e
    k = cam[-1]
    return k[1], k[2], k[3], k[4]


def scene_time_map(length, stops, slow=None):
    """Время кадра -> время сцены с учётом стоп-кадров."""
    out = []
    t_scene = 0.0
    frame_dt = 1 / FPS
    stops = sorted(stops)
    while t_scene <= length:
        out.append(t_scene)
        frozen = False
        for st, dur in stops:
            if st <= t_scene < st + 1e-6:
                pass
        # продвигаемся, но если перешагнули стоп — держим
        step = frame_dt
        if slow:
            for (s0, s1, k) in slow:
                if s0 <= t_scene < s1:
                    step = frame_dt * k
        nxt = t_scene + step
        for st, dur in stops:
            if t_scene < st <= nxt:
                hold = int(round(dur * FPS))
                out += [st] * hold
                frozen = True
        t_scene = nxt
        _ = frozen
    return out


def draw_fx(img, proj, scene, t, shake):
    d = ImageDraw.Draw(img, "RGBA")
    for (ht, pos, power) in scene["hits"]:
        age = t - ht
        if 0 <= age < 0.22:
            x, y, _ = proj(pos)
            x += shake[0]
            y += shake[1]
            k = age / 0.22
            r = (8 + 26 * power) * (0.35 + k)
            a = int(255 * (1 - k))
            d.ellipse([x - r * 0.45, y - r * 0.45, x + r * 0.45, y + r * 0.45], fill=(255, 255, 240, a))
            d.ellipse([x - r, y - r * 0.55, x + r, y + r * 0.55], outline=(255, 250, 220, a), width=max(1, int(6 * (1 - k))))
            for i in range(int(8 + 4 * power)):
                ang = i / (8 + 4 * power) * math.tau + ht * 7
                r0, r1 = r * 0.5, r * (1.2 + 0.6 * ((i * 37) % 5) / 5)
                d.line([x + math.cos(ang) * r0, y + math.sin(ang) * r0, x + math.cos(ang) * r1, y + math.sin(ang) * r1], fill=(255, 245, 200, a), width=max(1, int(4 * power * (1 - k))))
    for (st, pos) in scene["smokes"]:
        age = t - st
        if 0 <= age < 0.45:
            k = age / 0.45
            x, y, _ = proj((pos[0], 0.5, pos[2]))
            for i in range(9):
                ang = i / 9 * math.tau
                rr = 18 + 40 * k
                cx, cy = x + math.cos(ang) * rr * 0.6, y + math.sin(ang) * rr * 0.35 - 30 * k
                rad = 16 + 18 * k
                d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=(240, 240, 245, int(230 * (1 - k))))
    for (st, what) in scene["chakra"]:
        age = t - st
        if 0 <= age < 0.35:
            k = age / 0.35
            m, pos = scene["main"].transform(t)
            p = pos + np.array([0, 1.0, -1.3])
            x, y, _ = proj(p)
            r = 20 + 90 * k
            d.ellipse([x - r, y - r, x + r, y + r], outline=(90, 190, 255, int(255 * (1 - k))), width=6)
            d.ellipse([x - r * 0.4, y - r * 0.4, x + r * 0.4, y + r * 0.4], fill=(150, 220, 255, int(200 * (1 - k))))


def render_scene(scene, out_name):
    frames_dir = os.path.join(ROOT, "build", "frames_" + out_name)
    os.makedirs(frames_dir, exist_ok=True)
    for f in os.listdir(frames_dir):
        os.remove(os.path.join(frames_dir, f))
    times = scene_time_map(scene["length"], scene["stops"], scene.get("slow"))
    main = scene["main"]
    for i, t in enumerate(times):
        meshes = []
        for a in scene["actors"]:
            meshes += a.meshes(t)
        # остаточные силуэты при рывке
        if 1.95 <= t <= 2.2:
            for lag, col in ((0.05, (150, 210, 255)), (0.1, (110, 180, 255))):
                meshes += main.meshes(t - lag, alpha_color=col)
        center, yaw, pitch, scale = camera_at(scene["cam"], t)
        # тряска камеры после ударов
        shake = (0.0, 0.0)
        for (ht, _, power) in scene["hits"]:
            age = t - ht
            if 0 <= age < 0.25:
                amp = power * 5 * (1 - age / 0.25)
                shake = (math.sin(i * 12.9) * amp, math.cos(i * 7.3) * amp)
        img, proj = render.render(meshes, yaw=yaw, pitch=pitch, center=center, scale=scale, ground=clips.GROUND,
                                  width=W, height=H, grid=20, return_proj=True, dist=14)
        if shake != (0.0, 0.0):
            img = img.transform(img.size, 0, (1, 0, -shake[0], 0, 1, -shake[1]), fillcolor=(236, 242, 250))
        draw_fx(img, proj, scene, t, (0, 0))
        img.save(os.path.join(frames_dir, f"{i:04d}.png"))
    mp4 = os.path.join(ROOT, "build", out_name + ".mp4")
    gif = os.path.join(ROOT, "build", out_name + ".gif")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(frames_dir, "%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", mp4], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(frames_dir, "%04d.png"),
                    "-vf", "fps=20,scale=600:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", gif], check=True)
    print(mp4, len(times), "frames")
    return mp4, gif


if __name__ == "__main__":
    render_scene(build_clone_combo(), "scene_clone_combo")
