// The same query code runs against local Actions artifacts or the deployed Worker.
import {readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {querySnapshot, distance, sha256} from '../../workers/overpass-proxy/src/snapshot.js';

const [target, reportPath] = process.argv.slice(2);
if (!target) throw new Error('Usage: node tool/shop_data/check.mjs <dataset-directory|https://worker> [report.json]');
const audit = JSON.parse(await readFile(new URL('../../docs/data/regional-search-audit-2026-09-20.json', import.meta.url)));
const venues = JSON.parse(await readFile(new URL('../../assets/venues.json', import.meta.url)));
const places = [...audit.afterFix.filter(p => p.lat), ...audit.tokyoRetest, ...venues,
  {name:'那覇市役所（沖縄の収録確認）', lat:26.2123, lon:127.6791}];
let bucket;
if (!target.startsWith('https://')) {
  const raw = await readFile(resolve(target, 'manifest.json'));
  const manifest = JSON.parse(raw);
  const active = new TextEncoder().encode(JSON.stringify({version:manifest.version, manifest:{bytes:raw.length, sha256:await sha256(raw)}}));
  bucket = {get: async (key, options) => {
    if (key === 'active.json') return {size:active.length, arrayBuffer:async () => active};
    const relative = key.replace(`versions/${manifest.version}/`, '');
    const data = await readFile(resolve(target, relative));
    const range = options?.range;
    return {size:data.length, arrayBuffer:async () => range ? data.subarray(range.offset, range.offset + range.length) : data};
  }};
}
const results = [];
for (const place of places) {
  const params = {lat:place.lat, lon:place.lon, radius:3000};
  const start = performance.now();
  let result;
  if (bucket) result = await querySnapshot(bucket, params);
  else {
    const url = new URL(target);
    Object.entries(params).forEach(([k,v]) => url.searchParams.set(k, v));
    const response = await fetch(url, {signal:AbortSignal.timeout(8000)});
    if (!response.ok || response.headers.get('X-Data-Source') !== 'r2') throw new Error(`Not a successful R2 response: ${response.status}`);
    result = await response.json();
  }
  if (!result.elements?.length) throw new Error(`No OSM shops at ${place.name || place.query}`);
  if (result.elements.some(e => distance(place.lat, place.lon, e.lat, e.lon) > 3000.001)) throw new Error('Out-of-radius result');
  const ids = result.elements.map(e => `${e.type}/${e.id}`);
  if (new Set(ids).size !== ids.length) throw new Error('Duplicate OSM identity');
  results.push({name:place.name || place.query, lat:place.lat, lon:place.lon,
    radius:3000, count:ids.length, ms:Math.round(performance.now() - start), version:result.dataset.version});
  console.log(JSON.stringify(results.at(-1)));
}
if (reportPath) await writeFile(reportPath, JSON.stringify({target, checkedAt:new Date().toISOString(), results}, null, 2));
