#!/usr/bin/env python3
"""Собирает src/ в готовый файл места Roblox (.rbxlx), который открывается в Roblox Studio.

  src/shared  -> ReplicatedStorage/Shared       (*.luau -> ModuleScript)
  src/server  -> ServerScriptService/Server     (*.server.luau -> Script, остальное -> ModuleScript)
  src/client  -> StarterPlayer/StarterPlayerScripts/Client (*.client.luau -> LocalScript)

Запуск: python3 tools/build_place.py  ->  build/NinjaBattlegrounds.rbxlx
"""
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "build", "NinjaBattlegrounds.rbxlx")

_ref = 0


def ref():
    global _ref
    _ref += 1
    return "RBX%08X" % _ref


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls, name, props="", children=""):
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{escape(name)}</string>{props}</Properties>{children}</Item>'
    )


def script_item(path):
    base = os.path.basename(path)
    if base.endswith(".server.luau"):
        cls, name = "Script", base[: -len(".server.luau")]
    elif base.endswith(".client.luau"):
        cls, name = "LocalScript", base[: -len(".client.luau")]
    else:
        cls, name = "ModuleScript", base[: -len(".luau")]
    with open(path, encoding="utf-8") as f:
        source = f.read()
    return item(cls, name, f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>')


def folder(name, directory):
    files = sorted(f for f in os.listdir(directory) if f.endswith(".luau"))
    children = "".join(script_item(os.path.join(directory, f)) for f in files)
    return item("Folder", name, children=children), len(files)


def main():
    shared, n1 = folder("Shared", os.path.join(SRC, "shared"))
    server, n2 = folder("Server", os.path.join(SRC, "server"))
    client, n3 = folder("Client", os.path.join(SRC, "client"))

    parts = [
        # Стриминг выключен: клиенту нужен весь остров сразу (аквариумы, буи, причалы)
        item("Workspace", "Workspace", '<bool name="StreamingEnabled">false</bool>'),
        # Future — красивый свет от неона и фонарей
        item("Lighting", "Lighting", '<token name="Technology">4</token>'),
        item("ReplicatedStorage", "ReplicatedStorage", children=shared),
        item("ServerScriptService", "ServerScriptService", children=server),
        item(
            "StarterPlayer",
            "StarterPlayer",
            children=item("StarterPlayerScripts", "StarterPlayerScripts", children=client),
        ),
    ]
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        + "".join(parts)
        + "</roblox>"
    )
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    print(f"OK: {OUT} ({n1} shared, {n2} server, {n3} client scripts)")


if __name__ == "__main__":
    sys.exit(main())
