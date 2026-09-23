import {test} from 'node:test';
import assert from 'node:assert/strict';
import {catalogResponse} from './catalog.js';
const version = 'a'.repeat(64);
const m = {schema:1,version,sha256:'b'.repeat(64),count:11022,bytes:4,jsonBytes:20,
  source:'curated-sheets',path:`/catalog/${version}.json.gz`,previous:{privateAudit:true}};
const request = path => new Request(`https://example.com${path}`);
test('public manifest is separate from OSM and omits previous pointer', async () => {
  let key;
  const response = await catalogResponse(request('/catalog/manifest.json'), {SHOP_DATA:{get:async k => {
    key=k; return {size:500,text:async()=>JSON.stringify(m)};
  }}});
  assert.equal(response.status,200);
  assert.equal(key,'catalog/active.json');
  assert.equal((await response.json()).previous,undefined);
});
test('gzip payload streams without content encoding; invalid routes cannot read other objects', async () => {
  let calls=0;
  const env={SHOP_DATA:{get:async()=>{calls++;return {size:4,body:new Uint8Array([1,2,3,4])};}}};
  const response=await catalogResponse(request(m.path),env);
  assert.equal(response.headers.get('content-encoding'),null);
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())],[1,2,3,4]);
  assert.equal((await catalogResponse(request('/catalog/active.json'),env)).status,404);
  assert.equal(calls,1);
});
test('missing data is an uncached failure, never an empty catalog', async () => {
  const response=await catalogResponse(request('/catalog/manifest.json'),{SHOP_DATA:{get:async()=>null}});
  assert.equal(response.status,503);
  assert.equal(response.headers.get('Cache-Control'),'no-store');
});
