"""べんとうナビのアプリアイコンを生成する。

App Storeの要件:
  - 1024x1024
  - アルファチャンネルなし(完全不透明)
  - 角丸はOS側で自動的に付くため、正方形のまま描く

実行: python tool/make_icon.py
出力: assets/icon/app_icon.png
"""

from PIL import Image, ImageDraw
import os

S = 1024  # 出力サイズ
SS = 4    # アンチエイリアス用の拡大率
W = S * SS

# ── 配色(アプリのテーマカラーに合わせる) ──
ORANGE_LIGHT = (255, 112, 67)   # #FF7043
ORANGE_DEEP = (191, 54, 12)     # #BF360C
BOX_CREAM = (255, 250, 244)     # 弁当箱の白
BOX_EDGE = (120, 72, 48)        # 箱のふち(木の色)
RICE = (255, 255, 255)
UMEBOSHI = (214, 45, 45)        # 梅干し
TAMAGO = (255, 193, 7)          # 卵焼き
GREEN = (56, 142, 60)           # 青菜
SHADOW = (140, 40, 10)


def rounded(draw, box, r, fill):
    draw.rounded_rectangle(box, radius=r, fill=fill)


img = Image.new("RGB", (W, W), ORANGE_LIGHT)
d = ImageDraw.Draw(img)

# ── 背景: 斜めのグラデーション ──
for i in range(W):
    t = i / W
    c = tuple(
        int(ORANGE_LIGHT[k] + (ORANGE_DEEP[k] - ORANGE_LIGHT[k]) * t)
        for k in range(3)
    )
    d.line([(0, i), (W, i)], fill=c)

# 背景の装飾円(左上を少し明るく)
d.ellipse(
    [-W * 0.18, -W * 0.22, W * 0.42, W * 0.32],
    fill=(255, 138, 92),
)

# ── 弁当箱 ──
# 箱の外形
bx0, by0 = W * 0.145, W * 0.225
bx1, by1 = W * 0.855, W * 0.775
r_box = W * 0.075

# 影
d.rounded_rectangle(
    [bx0 + W * 0.018, by0 + W * 0.028, bx1 + W * 0.018, by1 + W * 0.028],
    radius=r_box,
    fill=SHADOW,
)
# ふち(濃い色) → 内側にクリーム色を重ねて枠線に見せる
rounded(d, [bx0, by0, bx1, by1], r_box, BOX_EDGE)
pad = W * 0.028
rounded(d, [bx0 + pad, by0 + pad, bx1 - pad, by1 - pad], r_box * 0.75, BOX_CREAM)

# ── 中身の仕切り ──
ix0, iy0 = bx0 + W * 0.055, by0 + W * 0.055
ix1, iy1 = bx1 - W * 0.055, by1 - W * 0.055
gap = W * 0.022
r_in = W * 0.032

# 左: ごはん(全体の約55%)
rice_x1 = ix0 + (ix1 - ix0) * 0.54
rounded(d, [ix0, iy0, rice_x1, iy1], r_in, RICE)

# 梅干し(日の丸弁当) — アイコンの主役になる赤い点
cx = (ix0 + rice_x1) / 2
cy = (iy0 + iy1) / 2
rr = (rice_x1 - ix0) * 0.21
d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=UMEBOSHI)

# 右上: 卵焼き
right_x0 = rice_x1 + gap
mid_y = (iy0 + iy1) / 2
rounded(d, [right_x0, iy0, ix1, mid_y - gap / 2], r_in, TAMAGO)
# 卵焼きの巻き線
for k in (0.36, 0.62):
    lx = right_x0 + (ix1 - right_x0) * k
    d.line(
        [(lx, iy0 + W * 0.022), (lx, mid_y - gap / 2 - W * 0.022)],
        fill=(230, 160, 10),
        width=int(W * 0.008),
    )

# 右下: 青菜
rounded(d, [right_x0, mid_y + gap / 2, ix1, iy1], r_in, GREEN)
# 青菜の質感(丸を重ねる)
for (fx, fy, fr) in ((0.3, 0.35, 0.16), (0.62, 0.3, 0.13), (0.45, 0.68, 0.15)):
    px = right_x0 + (ix1 - right_x0) * fx
    py = (mid_y + gap / 2) + (iy1 - (mid_y + gap / 2)) * fy
    pr = (ix1 - right_x0) * fr
    d.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(76, 175, 80))

# ── 縮小してアンチエイリアス ──
img = img.resize((S, S), Image.LANCZOS)

out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, "app_icon.png")
# RGB(アルファなし)で保存 — App Storeはアルファチャンネルを許可しない
img.convert("RGB").save(out, "PNG")
print("生成:", os.path.abspath(out), img.size, img.mode)
