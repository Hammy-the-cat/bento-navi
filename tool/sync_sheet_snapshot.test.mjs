import { test } from 'node:test';
import assert from 'node:assert/strict';
import { syncSnapshot } from './sync_sheet_snapshot.mjs';

const headers = ['店舗ID','店舗名','カテゴリ','市町村','住所','緯度','経度','電話番号','営業時間','定休日','予約・配達メモ','情報源URL','最終確認日','確認状態','座標精度','備考'];
const tab = { spreadsheetId: 'test', sheetId: 0, title: '宮崎県', book: 'test' };
const registry = { tabs: [tab] };
function fixture(changes = {}) {
  const shop = { 店舗ID: 'A', 店舗名: '弁当屋', カテゴリ: '弁当', 市町村: '宮崎市', 住所: '宮崎県宮崎市1-2', 確認状態: '確認済み', ...changes };
  return { fetchedAt: '2026-09-20', tabs: [{ ...tab, grid: { rowCount: 100, columnCount: 16 }, range: "'宮崎県'!A1:P100", values: [headers, headers.map(h => shop[h] ?? '')] }] };
}
const old = { id: 'A', name: '弁当屋', address: '宮崎県宮崎市1−2', lat: 31.9, lon: 131.4, coordinateAccuracy: '店舗地点' };

test('coordinate-free shops are retained in catalog and accounted for', () => {
  const { shops, audit } = syncSnapshot(fixture(), registry, []);
  assert.equal(shops.length, 1);
  assert.equal(shops[0].lat, null);
  assert.equal(audit.directoryOnly[0].id, 'A');
  assert.equal(audit.sourceRows, shops.length + audit.closed.length);
});
test('preserves resolved coordinates only for unchanged address', () => {
  assert.equal(syncSnapshot(fixture(), registry, [old]).shops[0].lat, 31.9);
  assert.equal(syncSnapshot(fixture({ 住所: '宮崎県宮崎市9-9' }), registry, [old]).shops[0].lat, null);
});
test('closed shop is removed even when previously present', () => {
  const result = syncSnapshot(fixture({ 確認状態: '閉店' }), registry, [old]);
  assert.equal(result.shops.length, 0);
  assert.equal(result.audit.closed[0].id, 'A');
});
test('missing/duplicate tabs, partial read, duplicate IDs fail before writing', () => {
  const f = fixture();
  assert.throws(() => syncSnapshot({ ...f, tabs: [] }, registry, []), /Missing source tabs/);
  assert.throws(() => syncSnapshot({ ...f, tabs: [f.tabs[0], f.tabs[0]] }, registry, []), /duplicate tab/);
  f.tabs[0].range = "'宮崎県'!A1:P2";
  assert.throws(() => syncSnapshot(f, registry, []), /Incomplete range/);
  const g = fixture(); g.tabs[0].values.push(g.tabs[0].values[1]);
  assert.throws(() => syncSnapshot(g, registry, []), /Duplicate ID/);
});
test('bad, zero, and partial coordinates are not treated as missing', () => {
  for (const [lat, lon] of [['bad', '131'], ['0', '0'], ['31', ''], ['', '131']]) {
    assert.throws(() => syncSnapshot(fixture({ 緯度: lat, 経度: lon }), registry, []), /Invalid coordinates/);
  }
});
test('source deletion needs explicit review', () => {
  assert.throws(() => syncSnapshot(fixture(), registry, [{ ...old, id: 'B' }]), /Source deletions/);
});
