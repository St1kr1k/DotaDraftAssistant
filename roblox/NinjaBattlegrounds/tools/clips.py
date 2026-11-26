#!/usr/bin/env python3
"""Все анимации бойцов — ключевые позы R6 (см. r6.py про оси).
python3 tools/clips.py            -> src/shared/Clips.luau (данные для игры)
python3 tools/clips.py preview X  -> build/clip_X.png (покадровое превью)
"""
import copy
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rig  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ===== постановка на землю =====
def foot_bottom(pose):
    import numpy as np
    w = rig.solve(rig.full(pose))
    ys = []
    for part in ("RightFoot", "LeftFoot"):
        m = w[part]
        sx, sy, sz = [v / 2 for v in rig.SIZES[part]]
        for x in (-sx, sx):
            for y in (-sy, sy):
                for z in (-sz, sz):
                    ys.append((m @ np.array([x, y, z, 1]))[1])
    return min(ys)


GROUND = foot_bottom({})


def grounded(pose):
    """Опускает/поднимает корень так, чтобы нижняя нога стояла на земле."""
    pose = copy.deepcopy(pose)
    pose.setdefault("root", {})
    pose["root"]["y"] = 0.0
    pose["root"]["y"] = GROUND - foot_bottom(pose)
    return pose


def P(**parts):
    return parts


def merge(base, **over):
    out = copy.deepcopy(base)
    for part, vals in over.items():
        out.setdefault(part, {}).update(vals)
    return out


CLIPS = {}


def clip(name, length, keys, loop=False, markers=None):
    CLIPS[name] = dict(name=name, length=length, loop=loop, keys=keys, markers=markers or [])


def K(t, pose, ease="smooth", ground=True):
    return dict(t=t, pose=grounded(pose) if ground else copy.deepcopy(pose), ease=ease)


# ===== базовые позы =====
STANCE = P(
    root=dict(yaw=30, pitch=4),
    waist=dict(pitch=10, yaw=-12),
    head=dict(yaw=-18, pitch=4),
    armL=dict(pitch=62, out=-4, twist=-10), elbowL=dict(bend=75),     # передняя рука — блок
    armR=dict(pitch=38, out=16, twist=-20), elbowR=dict(bend=118),    # задняя — кулак у подбородка
    legR=dict(pitch=-22, out=12), kneeR=dict(bend=32),
    legL=dict(pitch=30, out=8), kneeL=dict(bend=38),
)
STANCE_LOW = merge(STANCE, waist=dict(pitch=14), legR=dict(pitch=-18), kneeR=dict(bend=44), legL=dict(pitch=36), kneeL=dict(bend=52),
                   armL=dict(pitch=66), armR=dict(pitch=42))
NEUTRAL = P(elbowR=dict(bend=8), elbowL=dict(bend=8))

# ---------- Общие ----------
clip("FightIdle", 2.0, [
    K(0.0, STANCE),
    K(1.0, STANCE_LOW),
    K(2.0, STANCE),
], loop=True)

CROUCH = P(root=dict(pitch=10), waist=dict(pitch=30), head=dict(pitch=-15),
           armR=dict(pitch=-30, out=28), elbowR=dict(bend=30), armL=dict(pitch=-30, out=28), elbowL=dict(bend=30),
           legR=dict(pitch=70, out=14), kneeR=dict(bend=130), legL=dict(pitch=70, out=14), kneeL=dict(bend=130))
READY_LOW = P(root=dict(yaw=24, pitch=6), waist=dict(pitch=24, yaw=-8), head=dict(yaw=-14, pitch=-14),
              armR=dict(pitch=72, out=8, twist=-18), elbowR=dict(bend=60), armL=dict(pitch=-28, out=36), elbowL=dict(bend=40),
              legR=dict(pitch=-30, out=18), kneeR=dict(bend=95), legL=dict(pitch=72, out=10), kneeL=dict(bend=110))

clip("Dodge", 0.6, [
    K(0.0, STANCE),
    K(0.12, CROUCH, "out"),
    K(0.34, READY_LOW, "snap"),
    K(0.6, merge(READY_LOW, waist=dict(pitch=20), elbowR=dict(bend=55)), "out"),
], markers=[dict(t=0.12, name="vanish"), dict(t=0.32, name="appear")])

# ---------- Знак руками (начало суперудара) ----------
SEAL = P(root=dict(pitch=2), waist=dict(pitch=6), head=dict(pitch=6),
         armR=dict(pitch=62, out=-22, twist=0), elbowR=dict(bend=88), armL=dict(pitch=62, out=-22, twist=0), elbowL=dict(bend=88),
         legR=dict(pitch=-6, out=10), kneeR=dict(bend=18), legL=dict(pitch=10, out=10), kneeL=dict(bend=20))
POINT = P(root=dict(yaw=-20, pitch=6), waist=dict(pitch=8, yaw=6), head=dict(yaw=14, pitch=2),
          armR=dict(pitch=92, out=-6), elbowR=dict(bend=4), armL=dict(pitch=12, out=12), elbowL=dict(bend=60),
          legR=dict(pitch=-24, out=12), kneeR=dict(bend=30), legL=dict(pitch=30, out=8), kneeL=dict(bend=36))
clip("HandSeal", 0.6, [
    K(0.0, STANCE),
    K(0.12, SEAL, "snap"),
    K(0.38, merge(SEAL, waist=dict(pitch=9), kneeR=dict(bend=24), kneeL=dict(bend=26))),
    K(0.47, POINT, "snap"),
    K(0.6, merge(POINT, armR=dict(pitch=90)), "out"),
], markers=[dict(t=0.12, name="seal"), dict(t=0.47, name="point")])

# ---------- Двойник: подкат под врага и удар ногой вверх ----------
SLIDE = P(root=dict(pitch=-58), waist=dict(pitch=18), head=dict(pitch=28),
          armR=dict(pitch=-35, out=42), elbowR=dict(bend=10), armL=dict(pitch=-35, out=42), elbowL=dict(bend=10),
          legR=dict(pitch=8, out=4), kneeR=dict(bend=20), legL=dict(pitch=-4, out=10), kneeL=dict(bend=70))
KICKUP = P(root=dict(pitch=-82), waist=dict(pitch=24), head=dict(pitch=38),
           armR=dict(pitch=-50, out=52), elbowR=dict(bend=6), armL=dict(pitch=-50, out=52), elbowL=dict(bend=6),
           legR=dict(pitch=100, out=0), kneeR=dict(bend=0), legL=dict(pitch=-4, out=12), kneeL=dict(bend=80))
clip("CloneKickUp", 0.5, [
    K(0.0, SLIDE, ground=False),
    K(0.18, merge(SLIDE, root=dict(pitch=-66), legR=dict(pitch=40), kneeR=dict(bend=110)), ground=False),
    K(0.26, KICKUP, "snap", ground=False),
    K(0.5, merge(KICKUP, legR=dict(pitch=92), kneeR=dict(bend=10)), "out", ground=False),
], markers=[dict(t=0.26, name="hit")])
for k in CLIPS["CloneKickUp"]["keys"]:
    k["pose"]["root"]["y"] = -2.25  # тело почти лёжа над землёй

# ---------- Прыжок со спины двойника и удар пяткой ----------
clip("HeelDrop", 1.2, [
    K(0.0, CROUCH),
    K(0.18, P(root=dict(y=0.5, pitch=-8), waist=dict(pitch=-10), head=dict(pitch=-20),
              armR=dict(pitch=168, out=14), elbowR=dict(bend=10), armL=dict(pitch=168, out=14), elbowL=dict(bend=10),
              legR=dict(pitch=-12, out=4), kneeR=dict(bend=20), legL=dict(pitch=-8, out=4), kneeL=dict(bend=30)), "out", ground=False),
    K(0.42, P(root=dict(y=0.8, pitch=200), waist=dict(pitch=40), head=dict(pitch=30),
              armR=dict(pitch=30, out=20), elbowR=dict(bend=90), armL=dict(pitch=30, out=20), elbowL=dict(bend=90),
              legR=dict(pitch=110), kneeR=dict(bend=120), legL=dict(pitch=110), kneeL=dict(bend=120)), "smooth", ground=False),
    K(0.6, P(root=dict(y=0.8, pitch=352), waist=dict(pitch=-6), head=dict(pitch=-18),
             armR=dict(pitch=40, out=72), elbowR=dict(bend=20), armL=dict(pitch=40, out=72), elbowL=dict(bend=20),
             legR=dict(pitch=174, out=0), kneeR=dict(bend=4), legL=dict(pitch=-24, out=8), kneeL=dict(bend=40)), "out", ground=False),
    K(0.72, P(root=dict(y=0.2, pitch=368), waist=dict(pitch=16), head=dict(pitch=-24),
              armR=dict(pitch=-35, out=60), elbowR=dict(bend=20), armL=dict(pitch=-35, out=60), elbowL=dict(bend=20),
              legR=dict(pitch=-6, out=0), kneeR=dict(bend=0), legL=dict(pitch=-30, out=8), kneeL=dict(bend=50)), "snap", ground=False),
    K(0.95, merge(CROUCH, root=dict(pitch=14), armR=dict(pitch=-20, out=70), armL=dict(pitch=-20, out=70), legR=dict(pitch=60), legL=dict(pitch=20), kneeL=dict(bend=150)), "out"),
    K(1.2, STANCE, "smooth"),
], markers=[dict(t=0.18, name="jump"), dict(t=0.72, name="hit"), dict(t=0.95, name="land")])
# сальто вперёд: угол растёт непрерывно 0 -> 200 -> 352, затем бесшовный переход на -8 (та же поза)
_hd = CLIPS["HeelDrop"]["keys"]
_flip_end = copy.deepcopy(_hd[3])
_flip_end["t"] = 0.601
_flip_end["ease"] = "linear"
_flip_end["pose"]["root"]["pitch"] -= 360
_hd.insert(4, _flip_end)
for k in _hd[5:]:
    if k["pose"]["root"].get("pitch", 0) > 300:
        k["pose"]["root"]["pitch"] -= 360

# ---------- Комбо двойников (своя постановка) ----------
JAB = P(root=dict(yaw=-28, pitch=10), waist=dict(pitch=14, yaw=-14), head=dict(yaw=24),
        armR=dict(pitch=92, out=-6), elbowR=dict(bend=2), armL=dict(pitch=34, out=12), elbowL=dict(bend=120),
        legR=dict(pitch=-40, out=10), kneeR=dict(bend=20), legL=dict(pitch=46, out=8), kneeL=dict(bend=50))
clip("CloneRushPunch", 0.45, [
    K(0.0, STANCE),
    K(0.1, merge(STANCE, root=dict(yaw=44), waist=dict(yaw=10), armR=dict(pitch=20, out=12), elbowR=dict(bend=130))),
    K(0.17, JAB, "snap"),
    K(0.45, merge(JAB, armR=dict(pitch=86), elbowR=dict(bend=14)), "out"),
], markers=[dict(t=0.17, name="hit")])

SPIN = P(root=dict(pitch=-14, roll=-20, yaw=300), waist=dict(pitch=-6), head=dict(yaw=-40),
         armR=dict(pitch=10, out=70), elbowR=dict(bend=30), armL=dict(pitch=10, out=70), elbowL=dict(bend=30),
         legR=dict(pitch=18, out=95), kneeR=dict(bend=4), legL=dict(pitch=-4, out=6), kneeL=dict(bend=26))
clip("CloneSpinKick", 0.5, [
    K(0.0, STANCE),
    K(0.14, merge(STANCE, root=dict(yaw=170), legR=dict(pitch=20, out=40), kneeR=dict(bend=80))),
    K(0.24, SPIN, "snap"),
    K(0.5, merge(STANCE, root=dict(yaw=390)), "out"),
], markers=[dict(t=0.24, name="hit")])

SWEEP = P(root=dict(pitch=24, yaw=-120), waist=dict(pitch=30), head=dict(yaw=60),
          armR=dict(pitch=-18, out=70), elbowR=dict(bend=10), armL=dict(pitch=50, out=-6), elbowL=dict(bend=40),
          legR=dict(pitch=6, out=92), kneeR=dict(bend=4), legL=dict(pitch=60, out=10), kneeL=dict(bend=135))
clip("CloneSweep", 0.45, [
    K(0.0, STANCE),
    K(0.1, merge(SWEEP, root=dict(yaw=40), head=dict(yaw=0), legR=dict(pitch=-20, out=55), kneeR=dict(bend=40))),
    K(0.22, SWEEP, "snap"),
    K(0.45, merge(SWEEP, root=dict(yaw=-150), legR=dict(out=80)), "out"),
], markers=[dict(t=0.22, name="hit")])

WIND = P(root=dict(yaw=58, pitch=4), waist=dict(yaw=24, pitch=8), head=dict(yaw=-48),
         armR=dict(pitch=-62, out=28, twist=-20), elbowR=dict(bend=95), armL=dict(pitch=82, out=-18), elbowL=dict(bend=30),
         legR=dict(pitch=-34, out=16), kneeR=dict(bend=46), legL=dict(pitch=38, out=10), kneeL=dict(bend=50))
STRIKE = P(root=dict(yaw=-42, pitch=16), waist=dict(yaw=-22, pitch=18), head=dict(yaw=34, pitch=-6),
           armR=dict(pitch=94, out=-8), elbowR=dict(bend=0), armL=dict(pitch=-30, out=30), elbowL=dict(bend=80),
           legR=dict(pitch=-58, out=12), kneeR=dict(bend=10), legL=dict(pitch=60, out=8), kneeL=dict(bend=70))
clip("FinisherPunch", 0.75, [
    K(0.0, STANCE),
    K(0.26, WIND, "out"),
    K(0.33, STRIKE, "snap"),
    K(0.55, merge(STRIKE, armR=dict(pitch=92))),
    K(0.75, STANCE, "smooth"),
], markers=[dict(t=0.26, name="charge"), dict(t=0.33, name="hit")])


# ---------- Двойник подставляет спину (трамплин для прыжка) ----------
BOOST = P(root=dict(pitch=62), waist=dict(pitch=20), head=dict(pitch=-30),
          armR=dict(pitch=70, out=10), elbowR=dict(bend=20), armL=dict(pitch=70, out=10), elbowL=dict(bend=20),
          legR=dict(pitch=60, out=12), kneeR=dict(bend=120), legL=dict(pitch=60, out=12), kneeL=dict(bend=120))
clip("CloneBoost", 0.4, [K(0.0, STANCE), K(0.2, BOOST, "out"), K(0.4, BOOST)])


# ---------- Чёткие удары двойников (замах -> удар -> отыгрыш) ----------
GUARD = merge(STANCE, root=dict(yaw=20), waist=dict(yaw=-6))
JAB = P(root=dict(yaw=34, pitch=8), waist=dict(pitch=10, yaw=-22), head=dict(yaw=-16),
        armL=dict(pitch=90, out=-4, twist=0), elbowL=dict(bend=4), armR=dict(pitch=40, out=16, twist=-20), elbowR=dict(bend=120),
        legR=dict(pitch=-26, out=12), kneeR=dict(bend=30), legL=dict(pitch=34, out=8), kneeL=dict(bend=40))
CROSS = P(root=dict(yaw=-24, pitch=16), waist=dict(pitch=16, yaw=-20), head=dict(yaw=18),
          armR=dict(pitch=92, out=-10, twist=0), elbowR=dict(bend=2), armL=dict(pitch=42, out=8), elbowL=dict(bend=125),
          legR=dict(pitch=-42, out=12, twist=20), kneeR=dict(bend=18), legL=dict(pitch=40, out=8), kneeL=dict(bend=48))
clip("CloneJabCross", 0.55, [
    K(0.0, GUARD),
    K(0.07, merge(GUARD, root=dict(yaw=40, pitch=2), armL=dict(pitch=50), elbowL=dict(bend=110))),
    K(0.12, JAB, "snap"),
    K(0.19, merge(JAB, armL=dict(pitch=60), elbowL=dict(bend=95), root=dict(yaw=44))),
    K(0.25, CROSS, "snap"),
    K(0.38, merge(CROSS, armR=dict(pitch=90), elbowR=dict(bend=8))),
    K(0.55, GUARD, "smooth"),
], markers=[dict(t=0.12, name="hit"), dict(t=0.25, name="hit")])

CHAMBER = P(root=dict(yaw=-30, pitch=-4), waist=dict(pitch=-4, yaw=10), head=dict(yaw=30),
            armR=dict(pitch=20, out=40), elbowR=dict(bend=60), armL=dict(pitch=60, out=-10), elbowL=dict(bend=110),
            legR=dict(pitch=95, out=40, twist=-40), kneeR=dict(bend=130), legL=dict(pitch=-6, out=6), kneeL=dict(bend=20))
ROUNDHOUSE = P(root=dict(yaw=-80, pitch=-6, roll=-18), waist=dict(pitch=-10, yaw=12, roll=-8), head=dict(yaw=60),
               armR=dict(pitch=-30, out=60), elbowR=dict(bend=30), armL=dict(pitch=70, out=-10), elbowL=dict(bend=100),
               legR=dict(pitch=40, out=88, twist=-30), kneeR=dict(bend=4), legL=dict(pitch=-4, out=4), kneeL=dict(bend=16))
clip("CloneRoundhouse", 0.6, [
    K(0.0, GUARD),
    K(0.12, CHAMBER, "out"),
    K(0.2, ROUNDHOUSE, "snap"),
    K(0.36, merge(ROUNDHOUSE, legR=dict(out=80, pitch=30))),
    K(0.48, merge(CHAMBER, root=dict(yaw=-10))),
    K(0.6, GUARD, "smooth"),
], markers=[dict(t=0.2, name="hit")])

DIP = P(root=dict(yaw=30, pitch=20), waist=dict(pitch=26, yaw=-10), head=dict(yaw=-14, pitch=-10),
        armR=dict(pitch=-10, out=20), elbowR=dict(bend=100), armL=dict(pitch=60, out=0), elbowL=dict(bend=110),
        legR=dict(pitch=-24, out=14), kneeR=dict(bend=80), legL=dict(pitch=60, out=10), kneeL=dict(bend=100))
UPPER = P(root=dict(yaw=-10, pitch=-10, y=0.6), waist=dict(pitch=-16, yaw=-18), head=dict(yaw=10, pitch=-20),
          armR=dict(pitch=165, out=-8), elbowR=dict(bend=40), armL=dict(pitch=10, out=20), elbowL=dict(bend=80),
          legR=dict(pitch=-20, out=10), kneeR=dict(bend=6), legL=dict(pitch=10, out=8), kneeL=dict(bend=10))
clip("CloneUppercut", 0.55, [
    K(0.0, GUARD),
    K(0.12, DIP, "out"),
    K(0.19, UPPER, "snap", ground=False),
    K(0.36, merge(UPPER, root=dict(y=0.4), armR=dict(pitch=160)), ground=False),
    K(0.55, GUARD, "smooth"),
], markers=[dict(t=0.19, name="hit")])

DASH = P(root=dict(pitch=38), waist=dict(pitch=20), head=dict(pitch=-30),
         armR=dict(pitch=-60, out=20), elbowR=dict(bend=40), armL=dict(pitch=-60, out=20), elbowL=dict(bend=40),
         legR=dict(pitch=-50, out=6), kneeR=dict(bend=60), legL=dict(pitch=50, out=6), kneeL=dict(bend=70))
clip("DashIn", 0.25, [K(0.0, STANCE), K(0.08, DASH, "out"), K(0.25, DASH)])

HURT_L = P(root=dict(pitch=-12, yaw=-18, roll=8), waist=dict(pitch=-16, yaw=-20), head=dict(pitch=-28, yaw=-30),
           armR=dict(pitch=40, out=50), elbowR=dict(bend=60), armL=dict(pitch=20, out=40), elbowL=dict(bend=30),
           legR=dict(pitch=14), kneeR=dict(bend=20), legL=dict(pitch=-12), kneeL=dict(bend=26))
HURT_R = P(root=dict(pitch=-12, yaw=18, roll=-8), waist=dict(pitch=-16, yaw=20), head=dict(pitch=-28, yaw=30),
           armR=dict(pitch=20, out=40), elbowR=dict(bend=30), armL=dict(pitch=40, out=50), elbowL=dict(bend=60),
           legR=dict(pitch=-12), kneeR=dict(bend=26), legL=dict(pitch=14), kneeL=dict(bend=20))
HURT_BEND = P(root=dict(pitch=22), waist=dict(pitch=40), head=dict(pitch=20),
              armR=dict(pitch=30, out=-10), elbowR=dict(bend=80), armL=dict(pitch=30, out=-10), elbowL=dict(bend=80),
              legR=dict(pitch=10), kneeR=dict(bend=40), legL=dict(pitch=-8), kneeL=dict(bend=30))
clip("HurtL", 0.35, [K(0.0, HURT_L, "snap"), K(0.35, merge(HURT_L, root=dict(pitch=-4)))])
clip("HurtR", 0.35, [K(0.0, HURT_R, "snap"), K(0.35, merge(HURT_R, root=dict(pitch=-4)))])
clip("HurtBend", 0.4, [K(0.0, HURT_BEND, "snap"), K(0.4, merge(HURT_BEND, waist=dict(pitch=32)))])

# ---------- Реакции врага ----------
HURT = P(root=dict(pitch=-16), waist=dict(pitch=-14), head=dict(pitch=-30),
         armR=dict(pitch=30, out=40), elbowR=dict(bend=40), armL=dict(pitch=30, out=40), elbowL=dict(bend=40),
         legR=dict(pitch=12), kneeR=dict(bend=20), legL=dict(pitch=-10), kneeL=dict(bend=20))
clip("Hurt", 0.3, [K(0.0, HURT, "snap"), K(0.3, NEUTRAL)])
LAUNCH = P(root=dict(pitch=-40), waist=dict(pitch=-20), head=dict(pitch=-40),
           armR=dict(pitch=150, out=30), elbowR=dict(bend=40), armL=dict(pitch=150, out=30), elbowL=dict(bend=40),
           legR=dict(pitch=30), kneeR=dict(bend=60), legL=dict(pitch=-20), kneeL=dict(bend=40))
clip("Launched", 0.6, [K(0.0, LAUNCH, "snap", ground=False),
                       K(0.6, merge(LAUNCH, root=dict(pitch=-70), armL=dict(pitch=120, out=50), legL=dict(pitch=10)), ground=False)])
KB = P(root=dict(pitch=-45), waist=dict(pitch=-20), head=dict(pitch=-35),
       armR=dict(pitch=60, out=60), elbowR=dict(bend=30), armL=dict(pitch=60, out=60), elbowL=dict(bend=30),
       legR=dict(pitch=45), kneeR=dict(bend=40), legL=dict(pitch=20), kneeL=dict(bend=30))
clip("KnockBack", 0.6, [K(0.0, KB, "snap", ground=False), K(0.6, merge(KB, root=dict(pitch=-80, y=-1.9), armR=dict(pitch=120), armL=dict(pitch=120)), ground=False)])
LYING = P(root=dict(pitch=90, y=-2.6), head=dict(pitch=-25), armR=dict(pitch=165, out=45), elbowR=dict(bend=30), armL=dict(pitch=165, out=45),
          elbowL=dict(bend=30), legR=dict(pitch=-4, out=12), kneeR=dict(bend=10), legL=dict(pitch=-4, out=12), kneeL=dict(bend=20))
clip("Slammed", 0.5, [K(0.0, merge(LYING, root=dict(pitch=60, y=0)), "snap", ground=False), K(0.12, LYING, "snap", ground=False), K(0.5, LYING, ground=False)])
clip("GetUp", 0.6, [K(0.0, LYING, ground=False), K(0.3, merge(CROUCH, root=dict(pitch=30))), K(0.6, NEUTRAL)])


# ===== экспорт в Luau =====
def lua_pose(pose):
    parts = []
    for part in ("root", "waist", "head", "armR", "elbowR", "armL", "elbowL", "legR", "kneeR", "legL", "kneeL"):
        if part in pose:
            kv = ", ".join(f"{k} = {round(float(v), 3)}" for k, v in pose[part].items())
            parts.append(f"{part} = {{ {kv} }}")
    return "{ " + ", ".join(parts) + " }"


def export():
    lines = ["-- Анимации бойцов (генерирует tools/clips.py — правки делать там).", "return {"]
    for name, c in CLIPS.items():
        lines.append(f'\t["{name}"] = {{')
        lines.append(f"\t\tLength = {c['length']},")
        lines.append(f"\t\tLoop = {'true' if c['loop'] else 'false'},")
        lines.append("\t\tKeys = {")
        for k in c["keys"]:
            lines.append(f'\t\t\t{{ t = {k["t"]}, ease = "{k["ease"]}", pose = {lua_pose(k["pose"])} }},')
        lines.append("\t\t},")
        lines.append("\t\tMarkers = {")
        for mk in c["markers"]:
            lines.append(f'\t\t\t{{ t = {mk["t"]}, name = "{mk["name"]}" }},')
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    out = os.path.join(ROOT, "src", "shared", "Clips.luau")
    open(out, "w").write("\n".join(lines) + "\n")
    print("wrote", out, len(CLIPS), "clips")


def preview(names, frames=8):
    import math
    import render
    ims, labels = [], []
    for name in names:
        c = CLIPS[name]
        for i in range(frames):
            t = c["length"] * i / (frames - 1)
            pose = rig.sample(c, t)
            ims.append(render.render(rig.figure_meshes(pose), 170, yaw=math.pi / 2 + 0.35, pitch=-0.15, scale=14, ground=GROUND))
            labels.append(f"{name} {t:.2f}s")
    out = os.path.join(ROOT, "build", "clips_preview.png")
    render.sheet(ims, labels, frames).save(out)
    print(out)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        preview(sys.argv[2:] or list(CLIPS))
    else:
        export()
