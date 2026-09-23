import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {syncSnapshot, validCoordinates} from '../sync_sheet_snapshot.mjs';

const normalize = x => String(x ?? '').normalize('NFKC').replace(/[\s−‐―]/g, '');
const identity = s => `${normalize(s.name)}|${normalize(s.address)}`;
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export function buildCatalog(snapshot, registry, previous) {
  const age = Date.now() - Date.parse(snapshot.fetchedAt);
  if (!Number.isFinite(age) || age < -3600000 || age > 86400000) throw Error('Stale sheet snapshot');
  const result = syncSnapshot(snapshot, registry, previous);
  if (result.shops.length < 10000 || result.shops.length < previous.length * 0.95) throw Error('Unexpected catalog count drop');
  const oldIds = new Map(previous.map(s => [s.id, s]));
  const oldPairs = new Set();
  const oldSeen = new Map();
  for (const s of previous) {
    if (!s.address) continue;
    const key = identity(s);
    for (const id of oldSeen.get(key) ?? []) oldPairs.add([id, s.id].sort().join('|'));
    oldSeen.set(key, [...(oldSeen.get(key) ?? []), s.id]);
  }
  const seen = new Map();
  for (const s of result.shops) {
    const old = oldIds.get(s.id);
    // An address edit with unchanged coordinates must not move the label while
    // leaving its point at the old store. Require updated/cleared coordinates.
    if (old && normalize(s.address) !== normalize(old.address) && validCoordinates(s.lat, s.lon) &&
        s.lat === old.lat && s.lon === old.lon) throw Error(`Address changed without coordinate review: ${s.id}`);
    if (!s.address) continue; // Delivery-only entries remain available in the directory.
    const key = identity(s);
    for (const id of seen.get(key) ?? []) {
      if (!oldPairs.has([id, s.id].sort().join('|'))) throw Error(`New duplicate shop: ${id}, ${s.id}`);
    }
    seen.set(key, [...(seen.get(key) ?? []), s.id]);
  }
  const prefectures = new Set(previous.map(s => s.prefecture));
  for (const p of prefectures) {
    const old = previous.filter(s => s.prefecture === p);
    const now = result.shops.filter(s => s.prefecture === p);
    if (now.length < old.length * 0.95 || now.filter(s => validCoordinates(s.lat, s.lon)).length <
        old.filter(s => validCoordinates(s.lat, s.lon)).length * 0.95) throw Error(`Unexpected loss of shops/coordinates: ${p}`);
  }
  const json = Buffer.from(JSON.stringify(result.shops));
  const packed = gzipSync(json, {level:9});
  if (json.length > 20_000_000 || packed.length > 3_000_000) throw Error('Catalog exceeds client size limit');
  const version = sha256(json);
  const manifest = {schema:1, version, generatedAt:snapshot.fetchedAt, count:result.shops.length,
    mapped:result.audit.mapped, bytes:packed.length, jsonBytes:json.length, sha256:sha256(packed),
    path:`/catalog/${version}.json.gz`, source:'curated-sheets',
    sourceBooks:registry.spreadsheets.length, sourceTabs:registry.tabs.length};
  return {...result, json, packed, manifest};
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [snapshotFile, previousFile, outputDir] = process.argv.slice(2);
  const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  const result = buildCatalog(read(snapshotFile), read('tool/sheet_sources.json'), read(previousFile));
  fs.mkdirSync(outputDir, {recursive:true});
  fs.writeFileSync(path.join(outputDir, 'shops.json.gz'), result.packed);
  fs.writeFileSync(path.join(outputDir, 'manifest.json'), JSON.stringify(result.manifest, null, 2));
  fs.writeFileSync(path.join(outputDir, 'audit.json'), JSON.stringify(result.audit, null, 2));
  console.log(JSON.stringify(result.manifest));
}
