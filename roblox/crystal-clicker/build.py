"""Собирает CrystalClicker.rbxlx из src/*.lua (без Rojo). Запуск: python build.py"""
from pathlib import Path

ROOT = Path(__file__).parent
SRC = ROOT / "src"
_ref = 0


def ref():
    global _ref
    _ref += 1
    return f"RBX{_ref:08X}"


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def script(cls, name, file):
    src = (SRC / file).read_text(encoding="utf-8")
    return (f'<Item class="{cls}" referent="{ref()}"><Properties>'
            f'<string name="Name">{name}</string>'
            f'<ProtectedString name="Source">{cdata(src)}</ProtectedString>'
            f'</Properties></Item>')


def color(r, g, b):
    return (0xFF << 24) | (r << 16) | (g << 8) | b


def part(cls, name, size, pos, rgb, material, extra=""):
    x, y, z = pos
    sx, sy, sz = size
    return (f'<Item class="{cls}" referent="{ref()}"><Properties>'
            f'<string name="Name">{name}</string>'
            f'<bool name="Anchored">true</bool>'
            f'<Vector3 name="size"><X>{sx}</X><Y>{sy}</Y><Z>{sz}</Z></Vector3>'
            f'<CoordinateFrame name="CFrame"><X>{x}</X><Y>{y}</Y><Z>{z}</Z>'
            f'<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12>'
            f'<R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>'
            f'<Color3uint8 name="Color3uint8">{color(*rgb)}</Color3uint8>'
            f'<token name="Material">{material}</token>'
            f'<token name="TopSurface">0</token><token name="BottomSurface">0</token>'
            f'{extra}</Properties></Item>')


SLATE, SMOOTH_PLASTIC = 800, 272

xml = f"""<roblox version="4">
<Item class="Workspace" referent="{ref()}"><Properties><string name="Name">Workspace</string></Properties>
{part("Part", "Baseplate", (512, 20, 512), (0, -10, 0), (40, 36, 56), SLATE, '<bool name="Locked">true</bool>')}
{part("SpawnLocation", "SpawnLocation", (12, 1, 12), (0, 0.5, 0), (70, 210, 255), SMOOTH_PLASTIC, '<int name="Duration">0</int>')}
</Item>
<Item class="ReplicatedStorage" referent="{ref()}"><Properties><string name="Name">ReplicatedStorage</string></Properties>
{script("ModuleScript", "GameConfig", "GameConfig.lua")}
</Item>
<Item class="ServerScriptService" referent="{ref()}"><Properties><string name="Name">ServerScriptService</string></Properties>
{script("Script", "GameServer", "GameServer.server.lua")}
</Item>
<Item class="StarterPlayer" referent="{ref()}"><Properties><string name="Name">StarterPlayer</string></Properties>
<Item class="StarterPlayerScripts" referent="{ref()}"><Properties><string name="Name">StarterPlayerScripts</string></Properties>
{script("LocalScript", "GameClient", "GameClient.client.lua")}
</Item>
</Item>
</roblox>
"""

out = ROOT / "CrystalClicker.rbxlx"
out.write_text(xml, encoding="utf-8")
print("Готово:", out)
