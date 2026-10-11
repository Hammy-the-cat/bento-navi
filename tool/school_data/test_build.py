import unittest
from build import address_key, read_mext, reconcile


class BuildTests(unittest.TestCase):
    def test_address_notation(self):
        self.assertEqual(address_key('青森県深浦町大字深浦字蓙野６０'), address_key('青森県深浦町深浦蓙野60'))
        self.assertEqual(address_key('東京都中野区一丁目２番地３'), address_key('東京都中野区1-2-3'))
        self.assertNotEqual(address_key('東京都中野区1-23'), address_key('東京都中野区12-3'))

    def test_closure_and_move_never_reuse_coordinates(self):
        feature = dict(properties=dict(P29_001='02323', P29_002='C102210000881',
            P29_004='深浦町立深浦中学校', P29_005='青森県深浦町60', P29_007='1', P29_008='00'),
            geometry=dict(coordinates=[139.936082, 40.651451]))
        row = ['C102210000881', 'C1', '02', '2', '1', '深浦町立深浦中学校', '青森県深浦町６０', '', '2020-12-22', '']
        records, _ = reconcile([feature], {row[0]: row})
        self.assertEqual(len(records), 1)
        moved = row.copy(); moved[6] = '青森県深浦町999'
        records, review = reconcile([feature], {row[0]: moved})
        self.assertEqual(records, [])
        self.assertEqual(review[0]['reason'], 'address-changed')
        closed = row.copy(); closed[9] = '2026-04-01'
        records, review = reconcile([feature], {row[0]: closed})
        self.assertEqual(records, [])
        self.assertEqual(review[0]['reason'], 'closed')

    def test_new_school_is_audited(self):
        row = ['C102210000881', '', '', '', '1', '新設中学校', '青森県', '', '2026-04-01', '']
        records, review = reconcile([], {row[0]: row})
        self.assertEqual(records, [])
        self.assertEqual(review[0]['reason'], 'new-no-coordinate')

    def test_csv_latest_attribute_wins(self):
        raw = ('学校コード,学校種,県,設置,本分校,学校名,住所,郵便,設定日,廃止日\n'
               'C102210000881,C1,02,2,9,旧名,住所,,2020-12-22,2026-03-31\n'
               'C102210000881,C1,02,2,1,新名,住所,,2026-04-01,\n').encode()
        self.assertEqual(read_mext(raw)['C102210000881'][5], '新名')


if __name__ == '__main__':
    unittest.main()
