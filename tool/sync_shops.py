#!/usr/bin/env python3
"""Google Sheets CSVをアプリ同梱の店舗JSONへ変換する。"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO_ROOT / "assets" / "shops.json"
DEFAULT_CACHE = REPO_ROOT / "tool" / "geocode_cache.json"
EXCLUDED_STATUSES = {"閉店", "閉店予定"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--no-geocode", action="store_true")
    return parser.parse_args()


def load_cache(path: Path) -> dict[str, dict[str, float] | None]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def geocode(address: str) -> dict[str, float] | None:
    candidates = [address]
    without_parentheses = re.sub(r"[（(].*?[）)]", "", address).strip()
    without_building = without_parentheses.split(" ", 1)[0].strip()
    for candidate in (without_parentheses, without_building):
        if candidate and candidate not in candidates:
            candidates.append(candidate)

    for candidate in candidates:
        params = urllib.parse.urlencode({"q": candidate})
        request = urllib.request.Request(
            f"https://msearch.gsi.go.jp/address-search/AddressSearch?{params}",
            headers={
                "User-Agent": "bento-navi-data-sync/1.0 (github.com/Hammy-the-cat/bento-navi)"
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                results = json.loads(response.read().decode("utf-8"))
            if results:
                lon, lat = results[0]["geometry"]["coordinates"]
                return {"lat": float(lat), "lon": float(lon)}
        except Exception:
            continue
    return None


def combine_notes(row: dict[str, str]) -> str:
    parts = [row.get("予約・配達メモ", "").strip(), row.get("備考", "").strip()]
    return " ".join(part for part in parts if part)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = parse_args()
    cache = load_cache(args.cache)
    shops: list[dict[str, object]] = []
    unresolved: list[tuple[str, str, str]] = []
    geocode_requests = 0

    with args.csv_path.open(encoding="utf-8-sig", newline="") as csv_file:
        rows = list(csv.DictReader(csv_file))

    for row in rows:
        status = row.get("確認状態", "").strip()
        if not row.get("店舗ID", "").strip() or status in EXCLUDED_STATUSES:
            continue

        address = row.get("住所", "").strip()
        lat_text = row.get("緯度", "").strip()
        lon_text = row.get("経度", "").strip()
        coords: dict[str, float] | None = None
        if lat_text and lon_text:
            coords = {"lat": float(lat_text), "lon": float(lon_text)}
        elif address and "要確認" not in address and not args.no_geocode:
            if address not in cache or cache[address] is None:
                if geocode_requests:
                    time.sleep(0.3)
                print(f"geocode: {row['店舗ID']} {address}", flush=True)
                cache[address] = geocode(address)
                geocode_requests += 1
                save_json(args.cache, cache)
            coords = cache[address]

        if coords is None:
            unresolved.append((row.get("店舗ID", ""), row.get("店舗名", ""), address))
            continue

        shops.append(
            {
                "id": row.get("店舗ID", "").strip(),
                "name": row.get("店舗名", "").strip(),
                "category": row.get("カテゴリ", "").strip(),
                "municipality": row.get("市町村", "").strip(),
                "address": address,
                "lat": coords["lat"],
                "lon": coords["lon"],
                "phone": row.get("電話番号", "").strip(),
                "hours": row.get("営業時間", "").strip(),
                "closedDays": row.get("定休日", "").strip(),
                "notes": combine_notes(row),
                "sourceUrl": row.get("情報源URL", "").strip(),
                "status": status,
                "lastVerified": row.get("最終確認日", "").strip(),
                "coordinateAccuracy": (
                    row.get("座標精度", "").strip()
                    if lat_text and lon_text
                    else "国土地理院住所検索座標（アプリ反映時）"
                ),
            }
        )

    shops.sort(key=lambda shop: str(shop["id"]))
    save_json(args.output, shops)
    save_json(args.cache, cache)

    print(f"written: {len(shops)} shops -> {args.output}")
    print(f"excluded closed: {sum(1 for row in rows if row.get('確認状態', '').strip() in EXCLUDED_STATUSES)}")
    print(f"new geocode requests: {geocode_requests}")
    print(f"unresolved: {len(unresolved)}")
    for store_id, name, address in unresolved:
        print(f"  {store_id}\t{name}\t{address}")
    return 0 if not unresolved else 2


if __name__ == "__main__":
    raise SystemExit(main())
