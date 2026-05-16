#!/usr/bin/env python3
"""生成整合包预览图示例 (800x450)"""

from PIL import Image, ImageDraw, ImageFont
import os

# 尺寸: 800x450 (16:9)
WIDTH, HEIGHT = 800, 450

img = Image.new('RGB', (WIDTH, HEIGHT))
draw = ImageDraw.Draw(img)

# 背景渐变 - 深色主题
for y in range(HEIGHT):
    ratio = y / HEIGHT
    r = int(20 + 30 * ratio)
    g = int(20 + 30 * ratio)
    b = int(40 + 40 * ratio)
    draw.line([(0, y), (WIDTH, y)], fill=(r, g, b))

# 装饰图案 - 几何线条
draw.line([(0, HEIGHT//2), (WIDTH, HEIGHT//2)], fill=(60, 60, 80), width=2)

# 中心图标 - 剑与卡牌
cx, cy = WIDTH // 2, HEIGHT // 2 - 30

# 卡牌形状
card_w, card_h = 80, 110
card_x = cx - 50
card_y = cy - card_h // 2
draw.rounded_rectangle(
    [card_x, card_y, card_x + card_w, card_y + card_h],
    radius=8,
    fill=(180, 140, 80),
    outline=(255, 220, 150),
    width=2
)

# 卡牌内部 - 钻石图案
draw.polygon([
    (cx - 35, cy - 10),
    (cx - 15, cy - 30),
    (cx + 5, cy - 10),
    (cx - 15, cy + 10)
], fill=(255, 200, 100))

# 剑形状
sword_pts = [
    (cx + 30, cy - 60),   # 剑尖
    (cx + 40, cy),
    (cx + 55, cy + 20),   # 剑柄右
    (cx + 45, cy + 20),
    (cx + 45, cy + 70),   # 剑柄底
    (cx + 25, cy + 70),
    (cx + 25, cy + 20),
    (cx + 15, cy + 20),
]
draw.polygon(sword_pts, fill=(200, 200, 220), outline=(255, 255, 255), width=1)

# 标题文字
try:
    font_large = ImageFont.truetype("msyh.ttc", 48)
    font_small = ImageFont.truetype("msyh.ttc", 24)
except:
    font_large = ImageFont.load_default()
    font_small = ImageFont.load_default()

title = "整合包预览"
subtitle = "Slay the Spire 2"

# 标题
text_bbox = draw.textbbox((0, 0), title, font=font_large)
text_w = text_bbox[2] - text_bbox[0]
draw.text((WIDTH // 2 - text_w // 2, HEIGHT - 100), title, fill=(255, 220, 150), font=font_large)

# 副标题
text_bbox2 = draw.textbbox((0, 0), subtitle, font=font_small)
text_w2 = text_bbox2[2] - text_bbox2[0]
draw.text((WIDTH // 2 - text_w2 // 2, HEIGHT - 55), subtitle, fill=(180, 180, 180), font=font_small)

# 保存
output_path = os.path.join(os.path.dirname(__file__), "bundle_preview.png")
img.save(output_path)
print(f"已生成预览图: {output_path}")