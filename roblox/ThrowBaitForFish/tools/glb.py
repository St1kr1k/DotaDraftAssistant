"""Минимальный писатель GLB (glTF 2.0 binary) на numpy: несколько мешей, у каждого свой узел и цвет."""
import json
import struct

import numpy as np


def _pad(b: bytes, fill: bytes = b"\x00") -> bytes:
    return b + fill * ((4 - len(b) % 4) % 4)


def compute_normals(verts: np.ndarray, faces: np.ndarray) -> np.ndarray:
    n = np.zeros_like(verts)
    tri = verts[faces]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    for i in range(3):
        np.add.at(n, faces[:, i], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln == 0] = 1
    return n / ln


def write_glb(path: str, meshes: list):
    """meshes: [{"name": str, "verts": (N,3), "faces": (M,3), "color": (r,g,b) 0..1}]"""
    bin_chunks = []
    buffer_views = []
    accessors = []
    gl_meshes = []
    nodes = []
    materials = []
    offset = 0

    def add_view(data: bytes, target: int):
        nonlocal offset
        data = _pad(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        bin_chunks.append(data)
        offset += len(data)
        return len(buffer_views) - 1

    for m in meshes:
        v = np.asarray(m["verts"], dtype=np.float32)
        f = np.asarray(m["faces"], dtype=np.uint32)
        if m.get("normals") is not None:
            nrm = np.asarray(m["normals"], dtype=np.float32)
        else:
            nrm = compute_normals(v.astype(np.float64), f.astype(np.int64)).astype(np.float32)
        pv = add_view(v.tobytes(), 34962)
        accessors.append({"bufferView": pv, "componentType": 5126, "count": len(v), "type": "VEC3",
                          "min": v.min(axis=0).tolist(), "max": v.max(axis=0).tolist()})
        pa = len(accessors) - 1
        nv = add_view(nrm.tobytes(), 34962)
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
        na = len(accessors) - 1
        iv = add_view(f.flatten().tobytes(), 34963)
        accessors.append({"bufferView": iv, "componentType": 5125, "count": int(f.size), "type": "SCALAR"})
        ia = len(accessors) - 1
        r, g, b = m.get("color", (0.8, 0.8, 0.8))
        materials.append({"name": m["name"], "pbrMetallicRoughness": {"baseColorFactor": [r, g, b, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.6}})
        gl_meshes.append({"name": m["name"], "primitives": [{"attributes": {"POSITION": pa, "NORMAL": na}, "indices": ia, "material": len(materials) - 1}]})
        nodes.append({"name": m["name"], "mesh": len(gl_meshes) - 1})

    gltf = {
        "asset": {"version": "2.0", "generator": "ThrowBaitForFish meshgen"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": offset}],
    }
    js = _pad(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    bin_data = b"".join(bin_chunks)
    total = 12 + 8 + len(js) + 8 + len(bin_data)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, total))
        fh.write(struct.pack("<II", len(js), 0x4E4F534A))
        fh.write(js)
        fh.write(struct.pack("<II", len(bin_data), 0x004E4942))
        fh.write(bin_data)
