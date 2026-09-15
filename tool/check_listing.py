"""App Store掲載情報の文字数がAppleの上限に収まっているか確認する。

docs/appstore_listing.md のコードブロックを読み、各欄の上限と照合する。
実行: python tool/check_listing.py
"""

import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

# 見出し → 上限文字数(Noneは上限なし)
LIMITS = [
    ("アプリ名", 30),
    ("サブタイトル", 30),
    ("プロモーションテキスト", 170),
    ("説明文", 4000),
    ("キーワード", 100),
    ("バージョン情報", 4000),
]

path = os.path.join(os.path.dirname(__file__), "..", "docs", "appstore_listing.md")
text = io.open(path, encoding="utf-8").read()

ng = 0
for name, limit in LIMITS:
    # 「## 名前（...）」の直後にある最初のコードブロックを取る
    m = re.search(r"^##\s*" + re.escape(name) + r".*?\n(.*?)(?=^## |\Z)",
                  text, re.S | re.M)
    if not m:
        print(f"[!] {name}: 見つかりません")
        ng += 1
        continue
    block = re.search(r"```\n(.*?)\n```", m.group(1), re.S)
    if not block:
        print(f"[!] {name}: コードブロックがありません")
        ng += 1
        continue
    body = block.group(1)
    n = len(body)
    ok = n <= limit
    if not ok:
        ng += 1
    print(f"{'OK ' if ok else 'NG '} {name}: {n} / {limit}文字"
          + ("" if ok else f"  ← {n - limit}文字オーバー"))

print()
print("すべて上限内です。" if ng == 0 else f"{ng}件が要修正です。")
sys.exit(1 if ng else 0)
