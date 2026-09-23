import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('catalog_publish', Path(__file__).with_name('publish.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Store:
    def __init__(self):
        self.data = {}
        self.corrupt = False

    def get(self, key):
        value = self.data.get(key)
        if self.corrupt and key.endswith('.gz') and value:
            return b'broken', 'etag'
        return value, 'etag' if value else None

    def put(self, key, data, etag=None, create=False):
        if create and key in self.data:
            raise ValueError('Condition failed')
        self.data[key] = data


class CatalogPublishTests(unittest.TestCase):
    def test_verified_pointer_noop_and_failed_upload_keep_last_good(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            store = Store()

            def build(label):
                raw = json.dumps([{'id': str(i), 'name': label} for i in range(10000)]).encode()
                packed = gzip.compress(raw, mtime=0)
                m = dict(schema=1, source='curated-sheets', version=hashlib.sha256(raw).hexdigest(),
                         bytes=len(packed), jsonBytes=len(raw), sha256=hashlib.sha256(packed).hexdigest(), count=10000)
                (folder / 'manifest.json').write_text(json.dumps(m))
                (folder / 'shops.json.gz').write_bytes(packed)
                (folder / 'previous-pointer.json').write_bytes(store.get('catalog/active.json')[0] or b'null')
                return m

            first = build('first')
            module.publish_catalog(store, folder)
            pointer = store.data['catalog/active.json']
            self.assertEqual(json.loads(pointer)['version'], first['version'])
            build('first')
            module.publish_catalog(store, folder)
            self.assertEqual(store.data['catalog/active.json'], pointer)
            build('second')
            store.corrupt = True
            with self.assertRaisesRegex(ValueError, 'readback'):
                module.publish_catalog(store, folder)
            self.assertEqual(store.data['catalog/active.json'], pointer)
            store.corrupt = False
            module.publish_catalog(store, folder)
            self.assertEqual(json.loads(store.data['catalog/active.json'])['previous']['version'], first['version'])

    def test_concurrent_pointer_change_blocks_publish(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            raw = json.dumps([{}] * 10000).encode()
            packed = gzip.compress(raw, mtime=0)
            m = dict(schema=1, source='curated-sheets', version=hashlib.sha256(raw).hexdigest(),
                     sha256=hashlib.sha256(packed).hexdigest(), bytes=len(packed), jsonBytes=len(raw), count=10000)
            (folder / 'manifest.json').write_text(json.dumps(m))
            (folder / 'shops.json.gz').write_bytes(packed)
            (folder / 'previous-pointer.json').write_text('null')
            store = Store()
            store.data['catalog/active.json'] = b'{"version":"newer"}'
            with self.assertRaisesRegex(ValueError, 'changed while'):
                module.publish_catalog(store, folder)


if __name__ == '__main__':
    unittest.main()
