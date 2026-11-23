#!/usr/bin/env python3
"""Превью гладких рыб -> build/smooth_preview.png"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw
import preview, smoothgen, voxelgen
from vpreview import M, hexcolor
preview.role_color = hexcolor
fish = voxelgen.parse_fish_with_colors()
only = set(sys.argv[1:])
if only:
    fish = [d for d in fish if d["Id"] in only]
cell, cols = 300, 5
rows = math.ceil(len(fish) / cols)
sheet = Image.new("RGB", (cols * cell, rows * (cell + 26)), (255, 255, 255))
dr = ImageDraw.Draw(sheet)
for i, d in enumerate(fish):
    im = preview.render(M(smoothgen.build_smooth(d)), (), cell, 0.75, -0.35)
    x, y = (i % cols) * cell, (i // cols) * (cell + 26)
    sheet.paste(im, (x, y)); dr.text((x + 8, y + cell + 6), d["Id"], fill=(0, 0, 0))
out = os.path.join(voxelgen.ROOT, "build", "smooth_preview.png"); sheet.save(out); print(out)
