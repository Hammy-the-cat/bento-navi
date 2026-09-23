"""Verify every uploaded tile before atomically advancing active.json.

CI uses bucket-scoped R2 S3 credentials. Local bootstrap can use the already
authorized Wrangler OAuth session; credentials never enter artifacts or logs.
"""
import argparse
import hashlib
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from build import REGIONS, MAX_TILE_BYTES, encoded


class S3Store:
    def __init__(self):
        import boto3
        self.bucket = os.environ['R2_BUCKET']
        account = os.environ['R2_ACCOUNT_ID']
        self.client = boto3.client('s3', endpoint_url=f'https://{account}.r2.cloudflarestorage.com', region_name='auto')

    def get(self, key):
        from botocore.exceptions import ClientError
        try:
            value = self.client.get_object(Bucket=self.bucket, Key=key)
            return value['Body'].read(), value['ETag']
        except ClientError as exc:
            if exc.response['ResponseMetadata']['HTTPStatusCode'] == 404:
                return None, None
            raise

    def put(self, key, body, etag=None, create=False):
        conditions = {'IfNoneMatch': '*'} if create else ({'IfMatch': etag} if etag else {})
        self.client.put_object(Bucket=self.bucket, Key=key, Body=body,
                               ContentType='application/json; charset=utf-8', **conditions)


class CloudflareStore:
    """Bootstrap with a locally authorized token, without exporting it to CI."""
    def __init__(self, config):
        match = re.search(r'^oauth_token\s*=\s*"([^"]+)"', config.read_text(), re.M)
        if not match:
            raise ValueError('Wrangler OAuth session unavailable')
        self.token = match.group(1)
        self.base = (f"https://api.cloudflare.com/client/v4/accounts/{os.environ['R2_ACCOUNT_ID']}"
                     f"/r2/buckets/{os.environ['R2_BUCKET']}/objects/")

    def request(self, key, body=None, headers=None):
        # Credentials are confined to the Authorization header for Cloudflare.
        request = Request(self.base + key, data=body, method='PUT' if body is not None else 'GET',
                          headers={'Authorization': 'Bearer ' + self.token,
                                   'Content-Type': 'application/json', **(headers or {})})
        for attempt in range(8):
            try:
                with urlopen(request, timeout=60) as response:
                    return response.read(), response.headers.get('ETag')
            except HTTPError as exc:
                if exc.code == 404 and body is None:
                    return None, None
                if exc.code not in (429, 500, 502, 503, 504) or attempt == 7:
                    raise RuntimeError(f'R2 {request.method} failed: HTTP {exc.code}') from None
                time.sleep(max(30 if exc.code == 429 else 1, min(60, 2 ** attempt)))

    def get(self, key):
        return self.request(key)

    def put(self, key, body, etag=None, create=False):
        headers = {'If-None-Match': '*'} if create else ({'If-Match': etag} if etag else {})
        self.request(key, body, headers)


def validate_dataset(folder):
    raw = (folder / 'manifest.json').read_bytes()
    m = json.loads(raw)
    if (m.get('schema') != 2 or m.get('coverage') != 'Japan' or m.get('cellDegrees') != 0.1
            or not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', m.get('version', ''))
            or set(m.get('sources', {})) != set(REGIONS) or m.get('count', 0) < 10000
            or len(raw) > MAX_TILE_BYTES):
        raise ValueError('Invalid national manifest')
    for source in m['sources'].values():
        stamp = datetime.fromisoformat(source['sourceTimestamp'].replace('Z', '+00:00'))
        if not -3600 <= (datetime.now(timezone.utc) - stamp).total_seconds() <= 7 * 86400:
            raise ValueError('Stale extraction; rebuild before publishing')
    pack = (folder / 'shops.pack').read_bytes()
    if len(pack) != m['pack']['bytes'] or hashlib.sha256(pack).hexdigest() != m['pack']['sha256']:
        raise ValueError('Invalid packed data')
    total = 0
    offset = 0
    for cell, meta in m['cells'].items():
        if not re.fullmatch(r'\d{3}_\d{4}', cell):
            raise ValueError('Invalid tile key')
        if meta['offset'] != offset:
            raise ValueError('Invalid byte range')
        data = pack[offset:offset + meta['bytes']]
        if (len(data) != meta['bytes'] or len(data) > MAX_TILE_BYTES
                or hashlib.sha256(data).hexdigest() != meta['sha256']
                or len(json.loads(data)['elements']) != meta['count']):
            raise ValueError(f'Invalid tile: {cell}')
        total += meta['count']
        offset += meta['bytes']
    if total != m['count'] or offset != len(pack):
        raise ValueError('Count mismatch')
    return m, raw


def publish(folder, store):
    m, raw = validate_dataset(folder)
    previous, etag = store.get('active.json')
    if previous:
        active = json.loads(previous)
        if active['version'] == m['version']:
            raise ValueError('This version is already active')
        old_raw, _ = store.get(f"versions/{active['version']}/manifest.json")
        if old_raw is None:
            raise ValueError('Previous manifest missing; publication stopped')
        old = json.loads(old_raw)
        for region in REGIONS:
            if m['sources'][region]['records'] < old['sources'][region]['records'] * 0.85:
                raise ValueError(f'Shop count dropped over 15% in {region}; keeping previous version')

    def upload(name):
        key = f"versions/{m['version']}/{name}"
        data = (folder / name).read_bytes()
        existing, _ = store.get(key)
        if existing is not None and existing != data:
            raise ValueError('Immutable version collision')
        if existing is None:
            store.put(key, data, create=True)
        remote, _ = store.get(key)
        if remote != data:
            raise ValueError(f'R2 verification failed: {name}')
        print(f'Uploaded and verified {name}: {len(data)} bytes', flush=True)

    upload('shops.pack')
    key = f"versions/{m['version']}/manifest.json"
    existing, _ = store.get(key)
    if existing is not None and existing != raw:
        raise ValueError('Immutable manifest collision')
    if existing is None:
        store.put(key, raw, create=True)
    if store.get(key)[0] != raw:
        raise ValueError('Uploaded manifest verification failed')
    # Check for concurrent changes as well as conditional PUT on stores that support it.
    if store.get('active.json')[0] != previous:
        raise ValueError('Active dataset changed concurrently')
    pointer = dict(version=m['version'], manifest=dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()),
                   previous=json.loads(previous) if previous else None)
    # Keep one previous pointer, not an ever-growing nested history.
    if pointer['previous']:
        pointer['previous'].pop('previous', None)
    body = encoded(pointer)
    store.put('active.json', body, etag=etag, create=previous is None)
    if store.get('active.json')[0] != body:
        raise ValueError('Active pointer verification failed')
    print(f"Published {m['version']}: {m['count']} records, {len(m['cells'])} tiles")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dataset', required=True, type=Path)
    parser.add_argument('--wrangler-config', type=Path)
    args = parser.parse_args()
    publish(args.dataset, CloudflareStore(args.wrangler_config) if args.wrangler_config else S3Store())
