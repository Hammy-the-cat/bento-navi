import {test} from 'node:test';
import assert from 'node:assert/strict';
import {querySnapshot, nearbyCells, sha256, snapshotResponse} from './snapshot.js';

const encoder = new TextEncoder();
async function fixture(elements = []) {
  const objects = new Map();
  const put = (key, value) => { const data = encoder.encode(JSON.stringify(value)); objects.set(key, data); return data; };
  const tiles = {};
  for (const e of elements) {
    const id = `${Math.floor(e.lat * 10)}_${Math.floor(e.lon * 10)}`;
    (tiles[id] ??= []).push(e);
  }
  const cells = {};
  for (const [id, items] of Object.entries(tiles)) {
    const bytes = put(`versions/test/tiles/${id}.json`, {elements: items});
    cells[id] = {count: items.length, bytes: bytes.length, sha256: await sha256(bytes)};
  }
  const manifest = put('versions/test/manifest.json', {schema: 1, version: 'test', cellDegrees: 0.1,
    count: 10000, coverage: 'Japan', sources: Object.fromEntries(['hokkaido','tohoku','kanto','chubu','kansai','chugoku','shikoku','kyushu'].map(x => [x, {}])), cells});
  put('active.json', {version: 'test', manifest: {bytes: manifest.length, sha256: await sha256(manifest)}});
  const reads = [];
  return {objects, reads, bucket: {get: async key => {
    reads.push(key);
    const bytes = objects.get(key);
    return bytes ? {size: bytes.length, arrayBuffer: async () => bytes.buffer} : null;
  }}};
}

test('境界の両側を検索し半径外は除外、全国の無関係なタイルは取得しない', async () => {
  const f = await fixture([{id: 1, lat:35.099, lon:139.099}, {id:2, lat:35.101, lon:139.101},
    {id:3, lat:35.15, lon:139.15}, {id:4, lat:43, lon:141}]);
  const result = await querySnapshot(f.bucket, {lat:35.1, lon:139.1, radius:500});
  assert.deepEqual(result.elements.map(x => x.id).sort(), [1, 2]);
  assert.ok(!f.reads.some(key => key.includes('430_1410')));
});

test('検証済み全国データの空白地域は正常0件、存在するはずのタイル欠損は失敗', async () => {
  const f = await fixture([{id:1, lat:35, lon:139}]);
  assert.equal((await querySnapshot(f.bucket, {lat:43, lon:141, radius:3000})).elements.length, 0);
  f.objects.delete('versions/test/tiles/350_1390.json');
  await assert.rejects(querySnapshot(f.bucket, {lat:35, lon:139, radius:3000}), /Missing/);
});

test('破損したタイルとmanifestを正常な検索結果にしない', async () => {
  const f = await fixture([{id:1, lat:35, lon:139}]);
  f.objects.set('versions/test/tiles/350_1390.json', encoder.encode('{"elements":[]}'));
  await assert.rejects(querySnapshot(f.bucket, {lat:35, lon:139, radius:3000}), /Invalid/);
  f.objects.delete('versions/test/manifest.json');
  await assert.rejects(querySnapshot(f.bucket, {lat:35, lon:139, radius:3000}), /Missing/);
});

test('日本の緯度と最大10kmでも読込数を制限できる', () => {
  for (let lat = 20; lat <= 46; lat += 0.07) {
    assert.ok(nearbyCells(lat, 139.05, 10000).length <= 16);
  }
});

test('丸め前の正確な座標と半径で返し、既存iOSのelements形式を維持する', async () => {
  const f = await fixture([{id:1, lat:35.00049, lon:139, tags:{name:'店舗'}}]);
  const response = await snapshotResponse(new Request('https://example.com/?lat=35.00049&lon=139&radius=1'), {SHOP_DATA:f.bucket});
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('X-Data-Source'), 'r2');
  assert.equal((await response.json()).elements.length, 1);
  const invalid = await snapshotResponse(new Request('https://example.com/?lat=35&lon=139&radius=10001'), {SHOP_DATA:f.bucket});
  assert.equal(invalid.status, 400);
});
