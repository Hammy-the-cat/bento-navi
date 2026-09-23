import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from build import element, eligible, cell_id, encoded
from publish import publish


class ExtractionTests(unittest.TestCase):
    def test_categories_and_closures(self):
        self.assertFalse(eligible({'name': 'Dine in', 'amenity': 'restaurant'}))
        self.assertFalse(eligible({'name': 'Closed', 'disused:shop': 'convenience'}))
        self.assertFalse(eligible({'shop': 'deli'}))
        self.assertTrue(eligible({'brand': 'Chain', 'shop': 'convenience'}))
        self.assertTrue(eligible({'name': 'Takeaway', 'amenity': 'restaurant', 'takeaway': 'only'}))

    def test_polygon_centre_original_identity_and_allowlisted_tags(self):
        result = element({'properties': {'@type': 'way', '@id': 12, 'name': 'Shop',
            'name:ja': 'お店', 'shop': 'deli', 'unneeded': 'exclude'},
            'geometry': {'type': 'Polygon', 'coordinates': [[[139, 35], [139.02, 35.02], [139, 35]]]}})
        self.assertEqual((result['lat'], result['lon']), (35.01, 139.01))
        self.assertEqual((result['type'], result['id']), ('way', 12))
        self.assertEqual(result['tags']['name'], 'お店')
        self.assertNotIn('unneeded', result['tags'])
        self.assertEqual(cell_id(35.099999, 139.100001), '350_1391')

    def test_bad_geometry_is_not_a_successful_empty_result(self):
        with self.assertRaises(ValueError):
            element({'properties': {'@type': 'node', '@id': 1, 'name': 'bad', 'shop': 'deli'},
                     'geometry': {'coordinates': [float('nan'), 35]}})


class MemoryStore:
    def __init__(self, fail=False):
        self.objects = {}
        self.writes = []
        self.fail = fail

    def get(self, key):
        return self.objects.get(key), 'etag'

    def put(self, key, body, **kwargs):
        if self.fail and '/tiles/' in key:
            raise RuntimeError('Upload interrupted')
        self.writes.append(key)
        self.objects[key] = body


class PublicationTests(unittest.TestCase):
    def fixture(self, root):
        (root / 'tiles').mkdir()
        (root / 'tiles/350_1390.json').write_bytes(b'{"elements":[]}')
        m = dict(version='test', count=10000, cells={'350_1390': {}}, sources={})
        return m, encoded(m)

    def test_failed_upload_never_changes_active_pointer(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            fixture = self.fixture(root)
            store = MemoryStore(fail=True)
            with patch('publish.validate_dataset', return_value=fixture):
                with self.assertRaises(RuntimeError):
                    publish(root, store)
            self.assertNotIn('active.json', store.objects)

    def test_pointer_is_last_and_uploaded_data_is_verified(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            fixture = self.fixture(root)
            store = MemoryStore()
            with patch('publish.validate_dataset', return_value=fixture):
                publish(root, store)
            self.assertEqual(store.writes[-1], 'active.json')
            active = json.loads(store.objects['active.json'])
            self.assertEqual(active['manifest']['sha256'], hashlib.sha256(fixture[1]).hexdigest())


if __name__ == '__main__':
    unittest.main()
