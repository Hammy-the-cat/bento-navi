import {readFile} from 'node:fs/promises';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
const origin = 'https://bento-navi-overpass-proxy.excitedcherry0909.workers.dev';
const expected = JSON.parse(await readFile(process.argv[2], 'utf8'));
let m;
// The manifest is cached for 60 seconds. Allow the previous pointer to expire.
for (let attempt=0; attempt<5; attempt++) {
  const response = await fetch(`${origin}/catalog/manifest.json`, {signal:AbortSignal.timeout(15000)});
  if (!response.ok) throw Error(`Manifest HTTP ${response.status}`);
  m = await response.json();
  if (m.version === expected.version) break;
  if (attempt === 4) throw Error('Public catalog did not advance');
  await new Promise(resolve => setTimeout(resolve, 20000));
}
const response = await fetch(new URL(m.path, origin), {signal:AbortSignal.timeout(30000)});
if (!response.ok) throw Error(`Catalog HTTP ${response.status}`);
const bytes = Buffer.from(await response.arrayBuffer());
if (bytes.length !== m.bytes || createHash('sha256').update(bytes).digest('hex') !== m.sha256) throw Error('Public checksum mismatch');
const raw = gunzipSync(bytes);
const shops = JSON.parse(raw);
if (createHash('sha256').update(raw).digest('hex') !== m.version || shops.length !== m.count ||
    new Set(shops.map(s => s.id)).size !== shops.length || shops.some(s => ['閉店','閉店予定'].includes(s.status))) throw Error('Invalid public catalog');
console.log(JSON.stringify({version:m.version, count:shops.length, mapped:shops.filter(s => s.lat != null).length, bytes:bytes.length, checkedAt:new Date().toISOString()}));
