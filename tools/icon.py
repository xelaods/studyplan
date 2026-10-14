"""アプリアイコン（1024x1024）を作る：青のグラデーションに、白い時間割のカード"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024


def gradient(top, bottom):
    img = Image.new("RGB", (S, S), top)
    px = img.load()
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(S):
            px[x, y] = c
    return img


img = gradient((64, 156, 255), (10, 92, 230))
d = ImageDraw.Draw(img)

# カードの影
cx0, cy0, cx1, cy1 = 192, 214, 832, 850
shadow = Image.new("L", (S, S), 0)
ImageDraw.Draw(shadow).rounded_rectangle((cx0, cy0 + 24, cx1, cy1 + 24), radius=96, fill=120)
shadow = shadow.filter(ImageFilter.GaussianBlur(30))
img.paste((0, 40, 120), (0, 0), shadow)

# カード
d.rounded_rectangle((cx0, cy0, cx1, cy1), radius=96, fill=(255, 255, 255))
# 上の帯（曜日）
d.rounded_rectangle((cx0, cy0, cx1, cy0 + 150), radius=96, fill=(255, 69, 58))
d.rectangle((cx0, cy0 + 100, cx1, cy0 + 150), fill=(255, 69, 58))
# 留め具
for x in (340, 684):
    d.rounded_rectangle((x - 22, cy0 - 50, x + 22, cy0 + 40), radius=22, fill=(235, 240, 248))

# マス（3列×3行）
cols, rows = 3, 3
gx0, gy0, gx1, gy1 = cx0 + 56, cy0 + 196, cx1 - 56, cy1 - 56
gap = 28
cw = (gx1 - gx0 - gap * (cols - 1)) / cols
ch = (gy1 - gy0 - gap * (rows - 1)) / rows
colors = {
    (0, 0): (10, 132, 255), (1, 1): (255, 159, 10), (2, 0): (48, 209, 88),
    (0, 2): (191, 90, 242), (2, 2): (255, 55, 95), (1, 0): None, (0, 1): None, (2, 1): None, (1, 2): None,
}
for r in range(rows):
    for c in range(cols):
        x = gx0 + c * (cw + gap)
        y = gy0 + r * (ch + gap)
        color = colors.get((c, r))
        if color:
            d.rounded_rectangle((x, y, x + cw, y + ch), radius=26, fill=color)
        else:
            d.rounded_rectangle((x, y, x + cw, y + ch), radius=26, fill=(236, 239, 244))

img.save(sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png")
