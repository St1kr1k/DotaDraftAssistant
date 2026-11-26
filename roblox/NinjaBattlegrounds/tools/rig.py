"""Упрощённая модель R15-персонажа для превью анимаций (пропорции обычного аватара).

В игре (src/shared/Anim.luau) поза применяется так: Motor6D.C0 = C0_исходный * R, где R — поворот
в осях родительской детали (у R15 оси суставов совпадают с осями тела), а Root: C0 = T * C0_исходный.
Поэтому анимации работают на любых пропорциях аватара.

Поля позы (градусы, X вправо, Y вверх, вперёд = -Z):
  root:  x, y, z, pitch (наклон всего тела вперёд +), yaw (поворот влево +), roll
  waist: pitch (наклон корпуса вперёд +), yaw, roll
  head:  pitch (кивок вниз +), yaw, roll
  armR/armL: pitch (рука вперёд +), out (в сторону +), twist
  elbowR/elbowL: bend (сгиб +)
  legR/legL: pitch (нога вперёд +), out, twist
  kneeR/kneeL: bend (сгиб назад +)
"""
import math

import numpy as np

from r6 import angles, cf  # noqa: F401  (общие матрицы)

FIELDS = {
    "root": ("x", "y", "z", "pitch", "yaw", "roll"),
    "waist": ("pitch", "yaw", "roll"),
    "head": ("pitch", "yaw", "roll"),
    "armR": ("pitch", "out", "twist"), "armL": ("pitch", "out", "twist"),
    "elbowR": ("bend",), "elbowL": ("bend",),
    "legR": ("pitch", "out", "twist"), "legL": ("pitch", "out", "twist"),
    "kneeR": ("bend",), "kneeL": ("bend",),
}

R = math.radians


def joint_rot(key, p):
    side = -1 if key.endswith("L") else 1
    if key in ("waist", "head"):
        sgn = -1 if key == "waist" else 1  # корпус: «вперёд» = к -Z
        return angles(sgn * R(p.get("pitch", 0)) if key == "waist" else -R(p.get("pitch", 0)), R(p.get("yaw", 0)), R(p.get("roll", 0)))
    if key.startswith("arm") or key.startswith("leg"):
        return angles(R(p.get("pitch", 0)), side * R(p.get("twist", 0)), side * R(p.get("out", 0)))
    if key.startswith("elbow"):
        return angles(R(p.get("bend", 0)), 0, 0)
    if key.startswith("knee"):
        return angles(-R(p.get("bend", 0)), 0, 0)
    raise KeyError(key)


# деталь: (родитель, сустав-ключ позы, точка сустава в осях родителя (в покое), центр детали от сустава, размер, цвет)
SKIN = (245, 205, 165)
PARTS = [
    ("LowerTorso", None, None, (0, -0.8, 0), (1.9, 0.45, 1.0), (40, 40, 60)),
    ("UpperTorso", "LowerTorso", "waist", (0, 0.2, 0), (0, 0.8, 0), (230, 90, 40)),
    ("Head", "UpperTorso", "head", (0, 0.8, 0), (0, 0.6, 0), SKIN),
    ("RightUpperArm", "UpperTorso", "armR", (1.0, 0.6, 0), (0.45, -0.55, 0), (230, 90, 40)),
    ("RightLowerArm", "RightUpperArm", "elbowR", (0.45, -1.05, 0), (0, -0.45, 0), SKIN),
    ("RightHand", "RightLowerArm", None, (0, -0.9, 0), (0, -0.18, 0), SKIN),
    ("LeftUpperArm", "UpperTorso", "armL", (-1.0, 0.6, 0), (-0.45, -0.55, 0), (230, 90, 40)),
    ("LeftLowerArm", "LeftUpperArm", "elbowL", (-0.45, -1.05, 0), (0, -0.45, 0), SKIN),
    ("LeftHand", "LeftLowerArm", None, (0, -0.9, 0), (0, -0.18, 0), SKIN),
    ("RightUpperLeg", "LowerTorso", "legR", (0.5, -0.2, 0), (0, -0.6, 0), (40, 40, 60)),
    ("RightLowerLeg", "RightUpperLeg", "kneeR", (0, -1.2, 0), (0, -0.55, 0), (40, 40, 60)),
    ("RightFoot", "RightLowerLeg", None, (0, -1.1, 0), (0, -0.15, -0.15), (30, 30, 30)),
    ("LeftUpperLeg", "LowerTorso", "legL", (-0.5, -0.2, 0), (0, -0.6, 0), (40, 40, 60)),
    ("LeftLowerLeg", "LeftUpperLeg", "kneeL", (0, -1.2, 0), (0, -0.55, 0), (40, 40, 60)),
    ("LeftFoot", "LeftLowerLeg", None, (0, -1.1, 0), (0, -0.15, -0.15), (30, 30, 30)),
]
SIZES = {"UpperTorso": (1.9, 1.6, 1.0), "Head": (1.15, 1.15, 1.15), "RightUpperArm": (0.75, 1.1, 0.75), "RightLowerArm": (0.7, 0.9, 0.7),
         "RightHand": (0.7, 0.35, 0.7), "LeftUpperArm": (0.75, 1.1, 0.75), "LeftLowerArm": (0.7, 0.9, 0.7), "LeftHand": (0.7, 0.35, 0.7),
         "RightUpperLeg": (0.85, 1.2, 0.85), "RightLowerLeg": (0.8, 1.1, 0.8), "RightFoot": (0.8, 0.3, 1.1),
         "LeftUpperLeg": (0.85, 1.2, 0.85), "LeftLowerLeg": (0.8, 1.1, 0.8), "LeftFoot": (0.8, 0.3, 1.1)}


def solve(pose, hrp=None):
    """Мировые матрицы деталей. Ноги стоят на земле при y = -3.4 (HRP в нуле)."""
    hrp = np.eye(4) if hrp is None else hrp
    rp = pose.get("root", {})
    T = cf((rp.get("x", 0), rp.get("y", 0), rp.get("z", 0)),
           angles(-R(rp.get("pitch", 0)), R(rp.get("yaw", 0)), R(rp.get("roll", 0))))
    frames = {}   # «кадр сустава» детали: её начало в точке сустава
    world = {}
    for name, parent, key, pivot, center, color in PARTS:
        if parent is None:
            frame = hrp @ T @ cf(pivot)
            frames[name] = frame
            world[name] = frame
            continue
        rot = joint_rot(key, pose.get(key, {})) if key else np.eye(3)
        frame = frames[parent] @ cf(pivot) @ cf((0, 0, 0), rot)
        frames[name] = frame
        world[name] = frame @ cf(center)
    return world


def box_mesh(m, size):
    sx, sy, sz = [s / 2 for s in size]
    corners = np.array([[x, y, z] for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)])
    pts = (m[:3, :3] @ corners.T).T + m[:3, 3]
    faces = [[0, 1, 3], [0, 3, 2], [4, 6, 7], [4, 7, 5], [0, 4, 5], [0, 5, 1], [2, 3, 7], [2, 7, 6], [0, 2, 6], [0, 6, 4], [1, 5, 7], [1, 7, 3]]
    return pts, faces


def figure_meshes(pose, hrp=None, tint=None):
    w = solve(pose, hrp)
    out = []
    colors = {p[0]: p[5] for p in PARTS}
    for part, m in w.items():
        size = SIZES.get(part, (1.9, 0.45, 1.0))
        col = colors[part] if tint is None else tuple(int(c * 0.5 + t * 0.5) for c, t in zip(colors[part], tint))
        v, f = box_mesh(m, size)
        out.append((part, v, f, col))
        if part == "Head":
            v2, f2 = box_mesh(m @ cf((0, 0.1, -0.58)), (0.8, 0.22, 0.04))
            out.append(("Face", v2, f2, (25, 25, 25)))
    return out


def ease(name, t):
    if name == "in":
        return t * t * t
    if name == "out":
        return 1 - (1 - t) ** 3
    if name == "snap":
        return 1 - (1 - t) ** 6
    if name == "linear":
        return t
    return t * t * (3 - 2 * t)


def full(pose):
    return {part: {f: pose.get(part, {}).get(f, 0.0) for f in fields} for part, fields in FIELDS.items()}


def sample(clip, t):
    keys = clip["keys"]
    if t <= keys[0]["t"]:
        return full(keys[0]["pose"])
    for a, b in zip(keys, keys[1:]):
        if a["t"] <= t <= b["t"]:
            k = (t - a["t"]) / max(1e-6, b["t"] - a["t"])
            e = ease(b.get("ease", "smooth"), k)
            pa, pb = full(a["pose"]), full(b["pose"])
            return {part: {f: pa[part][f] + (pb[part][f] - pa[part][f]) * e for f in FIELDS[part]} for part in FIELDS}
    return full(keys[-1]["pose"])
