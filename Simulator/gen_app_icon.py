# -*- coding: utf-8 -*-
from PIL import Image, ImageDraw, ImageFont
import math

size = 1024
img = Image.new('RGB', (size, size), color=(13, 13, 13))
draw = ImageDraw.Draw(img)

center = size // 2
radius_outer = 440
radius_inner = 360
radius_aperture = 260

# 1. 绘制外部暗黑镜头外筒微纹理
for r in range(radius_outer, radius_inner, -2):
    alpha = int(255 * (r - radius_inner) / (radius_outer - radius_inner))
    draw.ellipse([center - r, center - r, center + r, center + r], outline=(30, 30, 32))

# 2. 绘制标志性“尼康黄”环 (#FFD000)
nikon_yellow = (255, 208, 0)
draw.ellipse([center - radius_inner, center - radius_inner, center + radius_inner, center + radius_inner], outline=nikon_yellow, width=16)

# 3. 绘制内层精密刻度线
for angle in range(0, 360, 15):
    rad = math.radians(angle)
    r1 = radius_inner - 24
    r2 = radius_inner - 8
    x1 = center + r1 * math.cos(rad)
    y1 = center + r1 * math.sin(rad)
    x2 = center + r2 * math.cos(rad)
    y2 = center + r2 * math.sin(rad)
    draw.line([x1, y1, x2, y2], fill=(120, 120, 120), width=4)

# 4. 绘制光圈同心圆叶片底座
draw.ellipse([center - radius_aperture, center - radius_aperture, center + radius_aperture, center + radius_aperture], fill=(24, 24, 27), outline=nikon_yellow, width=6)

# 5. 录制红点
tally_red = (255, 59, 48)
draw.ellipse([center + 140, center - 140, center + 172, center - 108], fill=tally_red)

# 6. 中央绘制 Z 30 字符标 (用基础几何绘制出极具科技感的 Z30)
# 绘制 Z
z_points = [
    (center - 110, center - 70),
    (center - 10, center - 70),
    (center - 110, center + 70),
    (center - 10, center + 70)
]
draw.line([z_points[0], z_points[1]], fill=(255, 255, 255), width=22)
draw.line([z_points[1], z_points[2]], fill=nikon_yellow, width=22)
draw.line([z_points[2], z_points[3]], fill=(255, 255, 255), width=22)

# 绘制 30
# 3
draw.arc([center + 15, center - 70, center + 75, center], 270, 90, fill=(255, 255, 255), width=18)
draw.arc([center + 15, center - 5, center + 75, center + 70], 270, 90, fill=(255, 255, 255), width=18)
draw.line([center + 20, center - 70, center + 45, center - 70], fill=(255, 255, 255), width=18)
draw.line([center + 20, center + 70, center + 45, center + 70], fill=(255, 255, 255), width=18)

# 0
draw.ellipse([center + 85, center - 70, center + 150, center + 70], outline=nikon_yellow, width=18)

out_path = 'Z30Control/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png'
img.save(out_path, 'PNG')
print(f'✅ 成功生成 1024x1024 尼康黑金镜头 App 图标: {out_path}')
