"""Модель R6-персонажа Roblox на numpy: те же суставы и C0/C1, что в Roblox.
Нужна, чтобы рендерить анимации покадрово и проверять позы до загрузки в игру.

Поза (как в игре, см. src/shared/Anim.luau): градусы, оси в пространстве торса
(X вправо, Y вверх, Z назад; вперёд = -Z):
  root: {x, y, z, pitch(наклон вперёд +), yaw(поворот влево +), roll}
  head/armR/armL/legR/legL: {pitch(вперёд +), out(в сторону от тела +), twist}
"""
import math

import numpy as np


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def angles(x, y, z):
    """CFrame.Angles(x, y, z) в Roblox = Rx * Ry * Rz."""
    return rx(x) @ ry(y) @ rz(z)


def cf(pos=(0, 0, 0), rot=None):
    m = np.eye(4)
    if rot is not None:
        m[:3, :3] = rot
    m[:3, 3] = pos
    return m


def cf_rows(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22):
    return cf((x, y, z), np.array([[r00, r01, r02], [r10, r11, r12], [r20, r21, r22]], float))


inv = np.linalg.inv

# Стандартный R6 (Roblox)
SIZES = {"HumanoidRootPart": (2, 2, 1), "Torso": (2, 2, 1), "Head": (2, 1, 1), "Right Arm": (1, 2, 1),
         "Left Arm": (1, 2, 1), "Right Leg": (1, 2, 1), "Left Leg": (1, 2, 1)}
JOINTS = {
    # имя: (Part0, Part1, C0, C1)
    "RootJoint": ("HumanoidRootPart", "Torso", cf_rows(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), cf_rows(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)),
    "Neck": ("Torso", "Head", cf_rows(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), cf_rows(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)),
    "Right Shoulder": ("Torso", "Right Arm", cf_rows(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), cf_rows(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)),
    "Left Shoulder": ("Torso", "Left Arm", cf_rows(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), cf_rows(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)),
    "Right Hip": ("Torso", "Right Leg", cf_rows(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), cf_rows(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)),
    "Left Hip": ("Torso", "Left Leg", cf_rows(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), cf_rows(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)),
}
LIMB = {"head": "Neck", "armR": "Right Shoulder", "armL": "Left Shoulder", "legR": "Right Hip", "legL": "Left Hip"}
SIDE = {"head": 1, "armR": 1, "armL": -1, "legR": 1, "legL": -1}


def limb_offset(c0, key, p):
    """Новый C0 = позиция(C0) * R * поворот(C0): вращение вокруг точки сустава в осях торса."""
    pitch = math.radians(p.get("pitch", 0))
    out = math.radians(p.get("out", 0)) * SIDE[key]
    twist = math.radians(p.get("twist", 0)) * SIDE[key]
    if key == "head":
        out = math.radians(p.get("roll", 0))
        twist = math.radians(p.get("yaw", 0))
    R = angles(pitch, twist, out)
    return cf(c0[:3, 3]) @ cf((0, 0, 0), R) @ cf((0, 0, 0), c0[:3, :3])


def root_offset(c0, p):
    # T в осях HRP: смещение + наклон вперёд (pitch +), поворот (yaw +), крен (roll)
    T = cf((p.get("x", 0), p.get("y", 0), p.get("z", 0)),
           angles(-math.radians(p.get("pitch", 0)), math.radians(p.get("yaw", 0)), math.radians(p.get("roll", 0))))
    return T @ c0


def solve(pose, hrp=None):
    """Мировые матрицы всех частей для позы."""
    hrp = np.eye(4) if hrp is None else hrp
    world = {"HumanoidRootPart": hrp}
    order = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]
    keymap = {v: k for k, v in LIMB.items()}
    for j in order:
        p0, p1, c0, c1 = JOINTS[j]
        if j == "RootJoint":
            c0n = root_offset(c0, pose.get("root", {}))
        else:
            c0n = limb_offset(c0, keymap[j], pose.get(keymap[j], {}))
        world[p1] = world[p0] @ c0n @ inv(c1)
    return world


# ===== Интерполяция клипа (так же, как в Anim.luau) =====
FIELDS = {"root": ("x", "y", "z", "pitch", "yaw", "roll"), "head": ("pitch", "yaw", "roll"),
          "armR": ("pitch", "out", "twist"), "armL": ("pitch", "out", "twist"),
          "legR": ("pitch", "out", "twist"), "legL": ("pitch", "out", "twist")}


def ease(name, t):
    if name == "in":
        return t * t * t
    if name == "out":
        return 1 - (1 - t) ** 3
    if name == "snap":  # резкий удар: почти мгновенно, потом дотягивается
        return 1 - (1 - t) ** 6
    if name == "linear":
        return t
    return t * t * (3 - 2 * t)  # smooth


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


# ===== Рендер =====
COLORS = {"Head": (245, 205, 160), "Torso": (230, 90, 40), "Right Arm": (245, 205, 160), "Left Arm": (245, 205, 160),
          "Right Leg": (40, 40, 60), "Left Leg": (40, 40, 60)}


def box_mesh(m, size):
    sx, sy, sz = [s / 2 for s in size]
    corners = np.array([[x, y, z] for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)])
    pts = (m[:3, :3] @ corners.T).T + m[:3, 3]
    faces = [[0, 1, 3], [0, 3, 2], [4, 6, 7], [4, 7, 5], [0, 4, 5], [0, 5, 1], [2, 3, 7], [2, 7, 6], [0, 2, 6], [0, 6, 4], [1, 5, 7], [1, 7, 3]]
    return pts, faces


def figure_meshes(pose, hrp=None, colors=None):
    w = solve(pose, hrp)
    out = []
    for part, m in w.items():
        if part == "HumanoidRootPart":
            continue
        v, f = box_mesh(m, SIZES[part])
        out.append((part, v, f, (colors or COLORS)[part]))
        if part == "Head":  # «лицо» — чтобы было видно, куда смотрит
            face = m @ cf((0, 0.1, -0.52))
            v2, f2 = box_mesh(face, (1.0, 0.3, 0.05))
            out.append(("Face", v2, f2, (30, 30, 30)))
    return out
