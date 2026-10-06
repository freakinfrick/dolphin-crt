#!/usr/bin/env python3
# Synthetic 640x528 frame (GameCube EFB size) for previews: colour bars, a grey ramp, fine
# vertical lines, a grid and a white disc -- the things a CRT shader visibly changes.
# Usage: python3 testpattern.py OUT.png
import sys
import numpy as np
from PIL import Image

W, H = 640, 528
img = np.zeros((H, W, 3), np.uint8)
bars = [(192, 192, 192), (192, 192, 0), (0, 192, 192), (0, 192, 0),
        (192, 0, 192), (192, 0, 0), (0, 0, 192), (16, 16, 16)]
for i, c in enumerate(bars):
    img[:200, i * W // 8:(i + 1) * W // 8] = c
img[200:260] = np.linspace(0, 255, W, dtype=np.uint8)[None, :, None]
img[260:320, ::2] = 255                      # 1-px vertical lines
img[320:] = 24
img[320::32, :] = 160                        # grid
img[320:, ::32] = 160
yy, xx = np.mgrid[:H, :W]
img[(xx - 480) ** 2 + (yy - 424) ** 2 < 70 ** 2] = 255
Image.fromarray(img).save(sys.argv[1])
