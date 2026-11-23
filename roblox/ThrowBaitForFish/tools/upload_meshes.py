#!/usr/bin/env python3
"""Загружает build/meshes/*.glb в Roblox (Open Cloud Assets API) и пишет src/shared/FishMeshes.luau.
Ключ подставляет прокси окружения (заголовок x-api-key). Повторный запуск грузит только отсутствующие."""
import json, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshgen
ROOT = meshgen.ROOT
USER_ID = "922063027"
MAP = os.path.join(ROOT, "src", "shared", "FishMeshes.luau")

def curl(args):
    r = subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected"] + args, capture_output=True, text=True)
    return json.loads(r.stdout)

def load_map():
    if not os.path.exists(MAP):
        return {}
    return dict(re.findall(r'\["([^"]+)"\] = (\d+)', open(MAP).read()))

def save_map(m):
    lines = ["-- Id загруженных 3D-моделей рыб (генерирует tools/upload_meshes.py). Не править руками.", "return {"]
    for k in sorted(m):
        lines.append(f'\t["{k}"] = {m[k]},')
    lines.append("}")
    open(MAP, "w").write("\n".join(lines) + "\n")

def main():
    force = "--force" in sys.argv
    m = {} if force else load_map()
    for d in meshgen.parse_fish():
        fid = d["Id"]
        if fid in m:
            continue
        path = os.path.join(meshgen.OUT, fid.replace(" ", "_") + ".glb")
        req = json.dumps({"assetType": "Model", "displayName": "TBFF " + fid, "description": "Throw Bait For Fish model",
                          "creationContext": {"creator": {"userId": USER_ID}}})
        op = curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets", "--form-string", "request=" + req,
                   "-F", f"fileContent=@{path};type=model/gltf-binary"])
        if "operationId" not in op:
            print("FAIL", fid, op); time.sleep(5); continue
        for _ in range(40):
            time.sleep(4)
            r = curl([f"https://apis.roblox.com/assets/v1/operations/{op['operationId']}"])
            if r.get("done"):
                break
        aid = r.get("response", {}).get("assetId")
        state = r.get("response", {}).get("moderationResult", {}).get("moderationState")
        print(fid, aid, state, flush=True)
        if aid:
            m[fid] = aid
            save_map(m)
    save_map(m)
    print("total", len(m))

if __name__ == "__main__":
    main()
