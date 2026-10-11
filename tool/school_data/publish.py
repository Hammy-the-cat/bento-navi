"""Publish a verified school snapshot without touching either shop catalog."""
import argparse
import gzip
import hashlib
import json
import re
import sys
from pathlib import Path


def validate(manifest, packed):
    m = manifest
    if (m.get('schema') != 1 or m.get('source') != 'mlit-mext-schools'
            or not re.fullmatch('[a-f0-9]{64}', m.get('version', ''))
            or m.get('path') != f"/schools/{m['version']}.json.gz"
            or not 30000 <= m.get('count', 0) <= 100000
            or not 0 < len(packed) <= 10_000_000 or len(packed) != m['bytes']
            or hashlib.sha256(packed).hexdigest() != m['sha256']):
        raise ValueError('Invalid school manifest or packed data')
    raw = gzip.decompress(packed)
    if (len(raw) != m['jsonBytes'] or len(raw) > 40_000_000
            or hashlib.sha256(raw).hexdigest() != m['version']):
        raise ValueError('Invalid school content')
    payload = json.loads(raw)
    schools = payload['schools']
    if (payload['schema'] != 1 or payload['source'] != m['source']
            or len(schools) != m['count'] or len({s['id'] for s in schools}) != len(schools)
            or len({s['prefecture'] for s in schools}) != 47):
        raise ValueError('Invalid school coverage')
    for s in schools:
        if not s['name'] or not s['address'] or not (20 <= s['lat'] <= 46 and 122 <= s['lon'] <= 154):
            raise ValueError('Invalid school record')


def publish(store, folder):
    m = json.loads((folder / 'manifest.json').read_bytes())
    data = (folder / 'schools.json.gz').read_bytes()
    validate(m, data)
    previous, etag = store.get('schools/active.json')
    old = json.loads(previous) if previous else None
    if old and old['version'] == m['version']:
        print('School data unchanged')
        return
    if old and m['count'] < old['count'] * 0.95:
        raise ValueError('School count dropped over 5%; retain previous snapshot')
    key = f"schools/versions/{m['version']}.json.gz"
    existing, _ = store.get(key)
    if existing is not None and existing != data:
        raise ValueError('Immutable school version collision')
    if existing is None:
        store.put(key, data, create=True)
    if store.get(key)[0] != data:
        raise ValueError('School upload verification failed')
    if store.get('schools/active.json')[0] != previous:
        raise ValueError('School version changed concurrently')
    m['previous'] = {k: v for k, v in old.items() if k != 'previous'} if old else None
    body = json.dumps(m, separators=(',', ':')).encode()
    store.put('schools/active.json', body, etag=etag, create=old is None)
    if store.get('schools/active.json')[0] != body:
        raise ValueError('School pointer readback failed')
    print(f"Published {m['count']} schools, {m['bytes']} bytes, version {m['version']}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--folder', type=Path, required=True)
    parser.add_argument('--wrangler-config', type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'shop_data'))
    from publish import S3Store, CloudflareStore
    publish(CloudflareStore(args.wrangler_config) if args.wrangler_config else S3Store(), args.folder)
