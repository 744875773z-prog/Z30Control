"""v1.0.22 取景页效果示意图（布局按代码画的，不是真机截图）。"""
from PIL import Image, ImageDraw, ImageFont, ImageOps

W, H = 1500, 980
BG = (245, 245, 247)
INK = (28, 28, 30)
GRAY = (110, 110, 115)
GREEN = (52, 199, 89)
BLUE = (10, 132, 255)
DARK_PILL = (44, 44, 46)
TAB_BG = (58, 58, 60)

FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
FONTB = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"


def font(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


def rounded(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def pill(draw, x, y, text, size, fg, bg, pad_x=10, bold=False):
    f = font(size, bold)
    tw = draw.textlength(text, font=f)
    w = int(tw) + pad_x * 2
    h = size + 12
    rounded(draw, [x, y, x + w, y + h], radius=h // 2, fill=bg)
    draw.text((x + pad_x, y + 5), text, font=f, fill=fg)
    return w


def make_scene(w, h):
    """一张横幅风景当取景画面：天、太阳、山、地面。"""
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for yy in range(h):
        t = yy / h
        r = int(126 + (232 - 126) * t)
        g = int(200 + (244 - 200) * t)
        b = int(227 + (248 - 227) * t)
        d.line([(0, yy), (w, yy)], fill=(r, g, b))
    d.ellipse([w - 110, 30, w - 40, 100], fill=(255, 236, 170))
    d.polygon([(0, h), (w * 0.28, h * 0.42), (w * 0.55, h)], fill=(91, 122, 107))
    d.polygon([(w * 0.35, h), (w * 0.68, h * 0.30), (w, h)], fill=(62, 92, 80))
    d.rectangle([0, int(h * 0.82), w, h], fill=(52, 84, 66))
    return img


canvas = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(canvas)

# ---------- 左：竖着拿 ----------
px, py, pw, ph = 110, 60, 330, 700
rounded(d, [px, py, px + pw, py + ph], radius=46, fill=(20, 20, 22))
sx, sy, sw, sh = px + 12, py + 12, pw - 24, ph - 24
rounded(d, [sx, sy, sx + sw, sy + sh], radius=36, fill=(0, 0, 0))
d.text((sx + 18, sy + 12), "20:05", font=font(20, True), fill=(255, 255, 255))
d.text((sx + sw - 74, sy + 12), "5G ▂▄▆", font=font(18), fill=(255, 255, 255))

# HUD pills
x = sx + 14
y = sy + 52
x += pill(d, x, y, "● 取景中 640×424", 19, (0, 0, 0), GREEN, bold=True) + 8
x += pill(d, x, y, "满屏", 19, (255, 255, 255), DARK_PILL) + 8
pill(d, x, y, "增强", 19, (255, 255, 255), DARK_PILL)
y += 42
x = sx + 14
for t in ("快门 1/10", "光圈 f/6.3", "ISO 1250"):
    x += pill(d, x, y, t, 18, (255, 255, 255), DARK_PILL) + 8

# 中间画面：横幅风景转 90°，铺满
scene = make_scene(500, 330)
rot = scene.rotate(90, expand=True)  # 330×500，侧着的
area_x, area_y, area_w, area_h = sx, sy + 150, sw, 420
fit = ImageOps.fit(rot, (area_w, area_h))
canvas.paste(fit, (area_x, area_y))
pill(d, area_x + 14, area_y + 12, "画面已转 90°", 18, (255, 255, 255), (0, 0, 0))
d.text((area_x + 14, area_y + area_h - 36), "取景画面（横）", font=font(18), fill=(255, 255, 255))

# 快门键
cx = sx + sw // 2
cy = sy + 612
d.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], outline=(255, 255, 255), width=4)
d.ellipse([cx - 21, cy - 21, cx + 21, cy + 21], fill=(255, 255, 255))

# 底栏（原位置：底部）
bx, by, bw, bh = sx + 12, sy + sh - 58, sw - 24, 46
rounded(d, [bx, by, bx + bw, by + bh], radius=23, fill=TAB_BG)
labels = [("控制", False), ("实时取景", True), ("图库", False)]
seg = bw // 3
for i, (t, sel) in enumerate(labels):
    cx2 = bx + seg * i + seg // 2
    if sel:
        f = font(19, True)
        tw = d.textlength(t, font=f)
        rounded(d, [cx2 - tw / 2 - 10, by + 7, cx2 + tw / 2 + 10, by + bh - 7],
                radius=16, fill=BLUE)
    d.text((cx2 - d.textlength(t, font=font(19, True)) / 2, by + 12),
           t, font=font(19, True), fill=(255, 255, 255) if sel else (160, 160, 165))

d.text((px, py + ph + 18), "竖着拿：底栏还在底部原位置", font=font(26),
       fill=INK, anchor="la")
d.text((px, py + ph + 56), "画面是横过来的（侧着看）", font=font(22),
       fill=GRAY, anchor="la")

# ---------- 中间箭头 ----------
ax = 500
d.line([(ax, 410), (ax + 80, 410)], fill=INK, width=4)
d.polygon([(ax + 80, 410), (ax + 62, 398), (ax + 62, 422)], fill=INK)
d.text((ax + 6, 360), "转 90°", font=font(26, True), fill=INK)

# ---------- 右：横过来拿 ----------
qx, qy, qw, qh = 620, 210, 760, 330
rounded(d, [qx, qy, qx + qw, qy + qh], radius=40, fill=(20, 20, 22))
sx2, sy2, sw2, sh2 = qx + 12, qy + 12, qw - 24, qh - 24
rounded(d, [sx2, sy2, sx2 + sw2, sy2 + sh2], radius=30, fill=(0, 0, 0))
scene2 = ImageOps.fit(make_scene(760, 330), (sw2, sh2))
canvas.paste(scene2, (sx2, sy2))

# 左边竖排 HUD（竖屏顶栏转过来后在左边）
hud = Image.new("RGBA", (340, 40), (0, 0, 0, 0))
hd = ImageDraw.Draw(hud)
pill(hd, 0, 0, "● 取景中 640×424", 19, (0, 0, 0), GREEN, bold=True)
hud = hud.rotate(90, expand=True)
canvas.paste(hud, (sx2 + 16, sy2 + sh2 // 2 - hud.height // 2), hud)

# 右边竖排底栏（竖屏底栏转过来后在右边）
tab = Image.new("RGBA", (280, 46), (0, 0, 0, 0))
td = ImageDraw.Draw(tab)
rounded(td, [0, 0, 280, 46], radius=23, fill=TAB_BG + (255,))
seg = 280 // 3
for i, (t, sel) in enumerate(labels):
    cx2 = seg * i + seg // 2
    if sel:
        f = font(19, True)
        tw = td.textlength(t, font=f)
        rounded(td, [cx2 - tw / 2 - 10, 7, cx2 + tw / 2 + 10, 39], radius=16, fill=BLUE + (255,))
    td.text((cx2 - td.textlength(t, font=font(19, True)) / 2, 12),
            t, font=font(19, True), fill=(255, 255, 255, 255) if sel else (160, 160, 165, 255))
tab = tab.rotate(-90, expand=True)  # 46×280，竖着
canvas.paste(tab, (sx2 + sw2 - 16 - tab.width, sy2 + sh2 // 2 - tab.height // 2), tab)

# 快门键（在底栏左边一点）
cx3 = sx2 + sw2 - 130
cy3 = sy2 + sh2 // 2
d.ellipse([cx3 - 28, cy3 - 28, cx3 + 28, cy3 + 28], outline=(255, 255, 255), width=4)
d.ellipse([cx3 - 19, cy3 - 19, cx3 + 19, cy3 + 19], fill=(255, 255, 255))

d.text((qx, qy + qh + 18), "横过来拿（顶朝左）：画面正过来铺满", font=font(26),
       fill=INK, anchor="la")
d.text((qx, qy + qh + 56), "不用开方向锁定，底栏在侧边还在", font=font(22),
       fill=GRAY, anchor="la")

d.text((W // 2, H - 48), "示意图：按 v1.0.22 代码画的布局，不是真机截图，真机以装上 IPA 后为准",
       font=font(21), fill=GRAY, anchor="ma")

canvas.save("/tmp/z30fix/v1022_preview.png")
print("saved", canvas.size)
