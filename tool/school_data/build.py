"""Build a compact, reproducible school index from MLIT P29 and MEXT codes.

Only verified coordinates travel to the app. Changed/missing addresses are kept
in an audit rather than silently reusing an old school's location.
"""
import argparse
import csv
import gzip
import hashlib
import io
import json
import re
import time
import unicodedata
import zipfile
from collections import Counter
from pathlib import Path
from urllib.request import urlopen

MLIT = 'https://nlftp.mlit.go.jp/ksj/gml/data/P29/P29-23/'
MEXT = 'https://www.mext.go.jp/b_menu/toukei/mext_01087.html'
PREFECTURES = '北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県 茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県 新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県 静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県 奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県 徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 長崎県 熊本県 大分県 宮崎県 鹿児島県 沖縄県'.split()


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()


def fetch(url, cache, refresh=False):
    path = cache / hashlib.sha256(url.encode()).hexdigest()
    if path.exists() and not refresh:
        return path.read_bytes()
    for attempt in range(3):
        try:
            with urlopen(url, timeout=45) as response:
                data = response.read(40_000_001)
            if len(data) > 40_000_000:
                raise ValueError('Source exceeds size limit')
            path.write_bytes(data)
            return data
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def address_key(value):
    value = unicodedata.normalize('NFKC', value).replace('ヶ', 'ケ')
    value = re.sub(r'大字|字|\s', '', value)
    # Convert Japanese chome numerals; don't alter proper nouns such as 三田.
    digits = dict(zip('一二三四五六七八九', range(1, 10)))
    def numeral(match):
        text = match[1]
        if '十' in text:
            a, b = text.split('十')
            return str((digits.get(a, 1) * 10) + digits.get(b, 0)) + '-'
        return ''.join(str(digits[c]) for c in text) + '-'
    value = re.sub(r'([一二三四五六七八九十]{1,3})丁目', numeral, value)
    value = re.sub(r'丁目|番地|番|号|[−ー－‐の]', '-', value)
    return re.sub('-+', '-', value).strip('-')


def read_mext(raw):
    try:
        text = raw.decode('utf-8-sig')
    except UnicodeError:
        text = raw.decode('cp932')
    rows = csv.reader(io.StringIO(text.replace('\r\r\n', '\n')))
    result = {}
    for row in rows:
        if not row or not re.fullmatch(r'[A-Z][0-9]{12}', row[0]):
            continue
        if len(row) < 10:
            raise ValueError('Unexpected MEXT columns')
        code = row[0]
        if code not in result or row[8] >= result[code][8]:
            result[code] = row
    if not result:
        raise ValueError('Empty MEXT source')
    return result


def reconcile(features, current):
    schools, review, seen = [], [], set()
    for f in features:
        p = f['properties']
        code = p['P29_002']
        row = current.get(code)
        reason = None
        if row is None:
            reason = 'missing-current-code'
        elif row[4].startswith('9') or row[9]:
            reason = 'closed'
        elif str(p['P29_007']) == '2':
            reason = 'suspended-in-2023'
        elif address_key(p['P29_005']) != address_key(row[6]):
            reason = 'address-changed'
        if reason:
            review.append(dict(code=code, name=p['P29_004'], reason=reason,
                               oldAddress=p['P29_005'], address=row[6] if row else None))
            continue
        lon, lat = f['geometry']['coordinates'][:2]
        if not (20 <= lat <= 46 and 122 <= lon <= 154):
            raise ValueError('Coordinates outside Japan')
        campus = str(p['P29_008'])
        identity = code + '-' + campus
        if identity in seen:
            continue
        seen.add(identity)
        pref = PREFECTURES[int(p['P29_001'][:2]) - 1]
        schools.append(dict(id=identity, name=row[5], address=row[6], prefecture=pref,
                            lat=round(lat, 6), lon=round(lon, 6),
                            campus=p.get('P29_009') or '',
                            aliases=[p['P29_004']] if row[5] != p['P29_004'] else []))
    known = {f['properties']['P29_002'] for f in features}
    for code, row in current.items():
        if code not in known and not row[4].startswith('9') and not row[9]:
            review.append(dict(code=code, name=row[5], address=row[6], reason='new-no-coordinate'))
    return sorted(schools, key=lambda s: s['id']), review


def build(cache, output, bundle=None):
    cache.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    # Discover the newest listed CSVs, not last year's hardcoded files.
    page = urlopen(MEXT, timeout=45).read().decode('utf-8')
    newest = page.split('＜過去の学校コード一覧＞')[0]
    paths = list(dict.fromkeys(re.findall(r'href="([^"]+\.csv)"', newest)))
    if not 3 <= len(paths) <= 8:
        raise ValueError('MEXT current table changed; review required')
    current, sources = {}, []
    for path in paths:
        url = 'https://www.mext.go.jp' + path
        raw = fetch(url, cache, refresh=True)
        for code, row in read_mext(raw).items():
            if code not in current or row[8] >= current[code][8]:
                current[code] = row
        sources.append(dict(url=url, sha256=hashlib.sha256(raw).hexdigest()))
    if len(current) < 40000:
        raise ValueError('Incomplete national MEXT list')
    features = []
    for n in range(1, 48):
        url = MLIT + f'P29-23_{n:02d}_GML.zip'
        raw = fetch(url, cache)
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            files = [f for f in archive.namelist() if f.endswith('.geojson')]
            if len(files) != 1:
                raise ValueError('Unexpected MLIT archive')
            items = json.loads(archive.read(files[0]))['features']
        if not items or any(f['properties']['P29_001'][:2] != f'{n:02d}' for f in items):
            raise ValueError('Prefecture mismatch')
        features.extend(items)
        sources.append(dict(url=url, count=len(items), sha256=hashlib.sha256(raw).hexdigest()))
        print(f'{n:02d}: {len(items)} school locations', flush=True)
    schools, review = reconcile(features, current)
    counts = Counter(s['prefecture'] for s in schools)
    if len(schools) < 30000 or set(counts) != set(PREFECTURES):
        raise ValueError('Incomplete reconciled dataset')
    payload = dict(schema=1, source='mlit-mext-schools', schools=schools)
    raw = encoded(payload)
    packed = bytearray(gzip.compress(raw, mtime=0))
    packed[9] = 255  # Portable gzip header across Python/runner operating systems.
    packed = bytes(packed)
    version = hashlib.sha256(raw).hexdigest()
    manifest = dict(schema=1, source='mlit-mext-schools', version=version,
                    sha256=hashlib.sha256(packed).hexdigest(), count=len(schools),
                    bytes=len(packed), jsonBytes=len(raw), path=f'/schools/{version}.json.gz')
    (output / 'schools.json.gz').write_bytes(packed)
    (output / 'manifest.json').write_bytes(encoded(manifest))
    (output / 'audit.json').write_bytes(encoded(dict(sources=sources, counts=counts,
        reviewCounts=Counter(r['reason'] for r in review), review=review)))
    if bundle:
        bundle.mkdir(parents=True, exist_ok=True)
        (bundle / 'schools.json.gz').write_bytes(packed)
        (bundle / 'manifest.json').write_bytes(encoded(manifest))
    print(json.dumps(manifest), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--cache', type=Path, default=Path('build/school-sources'))
    parser.add_argument('--output', type=Path, default=Path('build/schools'))
    parser.add_argument('--bundle', type=Path)
    args = parser.parse_args()
    build(args.cache, args.output, args.bundle)
