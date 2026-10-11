import json
import unittest
from pathlib import Path
from publish import publish, validate


class Store:
    def __init__(self):
        self.data = {}
        self.writes = []

    def get(self, key):
        return self.data.get(key), 'etag'

    def put(self, key, body, **kwargs):
        self.writes.append(key)
        self.data[key] = body


class PublishTests(unittest.TestCase):
    folder = Path(__file__).resolve().parents[2] / 'assets' / 'schools'

    def test_atomic_separate_pointer_and_idempotence(self):
        store = Store()
        store.data['catalog/active.json'] = b'stores'
        publish(store, self.folder)
        self.assertEqual(store.writes[-1], 'schools/active.json')
        self.assertEqual(store.data['catalog/active.json'], b'stores')
        count = len(store.writes)
        publish(store, self.folder)
        self.assertEqual(len(store.writes), count)

    def test_corruption_and_count_loss(self):
        manifest = json.loads((self.folder / 'manifest.json').read_bytes())
        packed = (self.folder / 'schools.json.gz').read_bytes()
        with self.assertRaises(ValueError):
            validate(manifest, packed[:-1])
        store = Store()
        store.data['schools/active.json'] = json.dumps(dict(version='a'*64, count=90000)).encode()
        with self.assertRaises(ValueError):
            publish(store, self.folder)
        self.assertEqual(store.writes, [])


if __name__ == '__main__':
    unittest.main()
