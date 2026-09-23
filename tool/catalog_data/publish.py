"""Independent curated-catalog pointer; never changes the weekly OSM snapshot."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'shop_data'))
from publish import S3Store, CloudflareStore


def checked_payload(manifest, packed):
    if (manifest.get('schema') != 1 or manifest.get('source') != 'curated-sheets'
            or not packed or len(packed) > 3_000_000 or len(packed) != manifest['bytes']
            or hashlib.sha256(packed).hexdigest() != manifest['sha256']):
        raise ValueError('Invalid catalog payload')
    raw = gzip.decompress(packed)
    if (len(raw) != manifest['jsonBytes'] or len(raw) > 20_000_000
            or hashlib.sha256(raw).hexdigest() != manifest['version']):
        raise ValueError('Invalid catalog content')
    shops = json.loads(raw)
    if len(shops) != manifest['count'] or len(shops) < 10000:
        raise ValueError('Invalid catalog count')
    return raw


def load_previous(store, folder):
    raw, _ = store.get('catalog/active.json')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'previous-pointer.json').write_bytes(raw or b'null')
    if raw:
        m = json.loads(raw)
        packed, _ = store.get(f"catalog/versions/{m['version']}.json.gz")
        previous = checked_payload(m, packed)
    else:
        previous = Path('assets/shops.json').read_bytes()
    (folder / 'previous.json').write_bytes(previous)


def publish_catalog(store, folder):
    manifest = json.loads((folder / 'manifest.json').read_bytes())
    packed = (folder / 'shops.json.gz').read_bytes()
    checked_payload(manifest, packed)
    previous_raw, etag = store.get('catalog/active.json')
    expected = json.loads((folder / 'previous-pointer.json').read_bytes())
    previous = json.loads(previous_raw) if previous_raw else None
    if previous != expected:
        raise ValueError('Catalog changed while processing; run again')
    if previous and previous['version'] == manifest['version']:
        print(f"No changes: {manifest['count']} shops; previous catalog retained")
        return
    if previous and manifest['count'] < previous['count'] * 0.95:
        raise ValueError('Unexpected count drop; previous catalog retained')
    key = f"catalog/versions/{manifest['version']}.json.gz"
    existing, _ = store.get(key)
    if existing is not None and existing != packed:
        raise ValueError('Immutable catalog collision')
    if existing is None:
        store.put(key, packed, create=True)
    if store.get(key)[0] != packed:
        raise ValueError('Catalog readback failed')
    manifest['previous'] = ({k:v for k,v in previous.items() if k != 'previous'} if previous else None)
    body = json.dumps(manifest, ensure_ascii=False, separators=(',', ':')).encode()
    store.put('catalog/active.json', body, etag=etag, create=previous is None)
    if store.get('catalog/active.json')[0] != body:
        raise ValueError('Catalog pointer readback failed')
    print(f"Published curated catalog: {manifest['count']} shops, {len(packed)} bytes, version {manifest['version']}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['previous', 'publish'])
    parser.add_argument('--folder', required=True, type=Path)
    parser.add_argument('--wrangler-config', type=Path)
    args = parser.parse_args()
    store = CloudflareStore(args.wrangler_config) if args.wrangler_config else S3Store()
    (load_previous if args.command == 'previous' else publish_catalog)(store, args.folder)
