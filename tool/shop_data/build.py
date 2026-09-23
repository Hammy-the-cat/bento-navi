"""Stream osmium GeoJSON sequences into small, immutable search tiles.

Raw PBF and geometry processing belong on GitHub Actions, not the user's PC.
Only public OSM shop tags are retained. The curated Sheets catalog stays separate.
"""
import argparse
import hashlib
import json
import math
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

REGIONS = ('hokkaido', 'tohoku', 'kanto', 'chubu', 'kansai', 'chugoku', 'shikoku', 'kyushu')
TAGS = ('name', 'name:ja', 'brand', 'shop', 'amenity', 'takeaway', 'opening_hours')
MAX_TILE_BYTES = 2_000_000


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True).encode('utf-8')


def cell_id(lat, lon):
    return f'{math.floor(lat * 10)}_{math.floor(lon * 10)}'


def eligible(tags):
    if not (tags.get('name:ja') or tags.get('name') or tags.get('brand') or '').strip():
        return False
    return (tags.get('shop') in ('convenience', 'supermarket', 'deli', 'bakery')
            or tags.get('amenity') == 'fast_food'
            or (tags.get('amenity') == 'restaurant' and tags.get('takeaway') in ('yes', 'only')))


def points(coords):
    if len(coords) >= 2 and isinstance(coords[0], (int, float)):
        yield coords[:2]
    else:
        for child in coords:
            yield from points(child)


def element(feature):
    tags = feature.get('properties', {})
    if not eligible(tags):
        return None
    # --attributes=type,id supplies original IDs even for multipolygon areas.
    kind, ident = tags.get('@type'), tags.get('@id')
    if kind not in ('node', 'way', 'relation') or not isinstance(ident, int):
        raise ValueError('Missing original OSM type/id')
    coords = list(points(feature['geometry']['coordinates']))
    if not coords:
        raise ValueError('Empty shop geometry')
    if not all(math.isfinite(v) for pair in coords for v in pair):
        raise ValueError('Non-finite geometry')
    # Bounding-box centre agrees with the former Overpass "out center" contract.
    lon = (min(p[0] for p in coords) + max(p[0] for p in coords)) / 2
    lat = (min(p[1] for p in coords) + max(p[1] for p in coords)) / 2
    if not (20 <= lat <= 46 and 122 <= lon <= 154):
        return None
    kept = {k: tags[k] for k in TAGS if isinstance(tags.get(k), str)}
    kept['name'] = tags.get('name:ja') or tags.get('name') or tags['brand']
    return dict(type=kind, id=ident, lat=round(lat, 7), lon=round(lon, 7), tags=kept)


def extract(source, target, region, source_timestamp):
    count = 0
    with source.open(encoding='utf-8') as src, target.open('wb') as out:
        for line in src:
            if not line.strip():
                continue
            item = element(json.loads(line.lstrip('\x1e')))
            if item:
                out.write(encoded(item) + b'\n')
                count += 1
    if count < 100:
        raise ValueError(f'{region}: suspiciously few shops ({count})')
    report = dict(region=region, records=count, sourceTimestamp=source_timestamp,
                  source=f'https://download.geofabrik.de/asia/japan/{region}-latest.osm.pbf',
                  sha256=hashlib.sha256(target.read_bytes()).hexdigest())
    target.with_suffix('.report.json').write_bytes(encoded(report))
    print(json.dumps(report, ensure_ascii=False))


def assemble(inputs, output, version):
    if not version or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in version):
        raise ValueError('Invalid version')
    output.mkdir(parents=True, exist_ok=False)
    db = sqlite3.connect(str(output / 'working.sqlite'))
    db.execute('CREATE TABLE shops (id TEXT PRIMARY KEY, cell TEXT, body TEXT)')
    reports = {}
    for region in REGIONS:
        source = inputs / f'{region}.jsonl'
        report = json.loads(source.with_suffix('.report.json').read_text(encoding='utf-8'))
        if report['region'] != region or hashlib.sha256(source.read_bytes()).hexdigest() != report['sha256']:
            raise ValueError(f'Invalid extraction report: {region}')
        timestamp = datetime.fromisoformat(report['sourceTimestamp'].replace('Z', '+00:00'))
        age = (datetime.now(timezone.utc) - timestamp).total_seconds()
        if not -3600 <= age <= 7 * 86400:
            raise ValueError(f'Stale source: {region}')
        n = 0
        with source.open(encoding='utf-8') as stream:
            for line in stream:
                item = json.loads(line)
                if not eligible(item['tags']) or not (20 <= item['lat'] <= 46 and 122 <= item['lon'] <= 154):
                    raise ValueError('Invalid extracted shop')
                # Regional boundary overlap and line/polygon representations share an ID.
                db.execute('INSERT OR REPLACE INTO shops VALUES (?,?,?)',
                           (f"{item['type']}/{item['id']}", cell_id(item['lat'], item['lon']), encoded(item).decode('utf-8')))
                n += 1
        if n != report['records'] or n < 100:
            raise ValueError(f'Incomplete extraction: {region}')
        reports[region] = report
    db.commit()
    db.execute('CREATE INDEX cells ON shops(cell)')
    tiles = output / 'tiles'
    tiles.mkdir()
    cells = {}
    for (cell,) in db.execute('SELECT DISTINCT cell FROM shops ORDER BY cell'):
        items = [json.loads(row[0]) for row in db.execute('SELECT body FROM shops WHERE cell=? ORDER BY id', (cell,))]
        raw = encoded({'elements': items})
        if len(raw) > MAX_TILE_BYTES:
            raise ValueError(f'Tile exceeds Worker memory budget: {cell}')
        (tiles / f'{cell}.json').write_bytes(raw)
        cells[cell] = dict(count=len(items), bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
    db.close()
    (output / 'working.sqlite').unlink()
    manifest = dict(schema=1, version=version, cellDegrees=0.1, coverage='Japan',
                    generatedAt=datetime.now(timezone.utc).isoformat(), sources=reports,
                    attribution='© OpenStreetMap contributors',
                    license='https://opendatacommons.org/licenses/odbl/1-0/',
                    sourceUrl='https://www.openstreetmap.org/copyright',
                    count=sum(c['count'] for c in cells.values()), cells=cells)
    if manifest['count'] < 10000:
        raise ValueError('National coverage check failed')
    (output / 'manifest.json').write_bytes(encoded(manifest))
    print(json.dumps({k: v for k, v in manifest.items() if k not in ('cells', 'sources')}, ensure_ascii=False))
    print(f"{len(cells)} tiles, {sum(c['bytes'] for c in cells.values())} bytes")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    ex = sub.add_parser('extract')
    ex.add_argument('--source', type=Path, required=True)
    ex.add_argument('--output', type=Path, required=True)
    ex.add_argument('--region', choices=REGIONS, required=True)
    ex.add_argument('--source-timestamp', required=True)
    pack = sub.add_parser('assemble')
    pack.add_argument('--inputs', type=Path, required=True)
    pack.add_argument('--output', type=Path, required=True)
    pack.add_argument('--version', required=True)
    args = parser.parse_args()
    if args.command == 'extract':
        extract(args.source, args.output, args.region, args.source_timestamp)
    else:
        assemble(args.inputs, args.output, args.version)
