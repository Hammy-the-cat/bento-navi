// Immutable R2 tiles. Updating active.json is the only publication step.
const HEADERS = {'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*'};
const VERSION = /^[A-Za-z0-9_-]{1,80}$/;
const CELL = /^\d{3}_\d{4}$/;
export const MAX_TILE_BYTES = 2_000_000;

export function distance(lat, lon, a, b) {
  const rad = Math.PI / 180;
  const h = Math.sin((a - lat) * rad / 2) ** 2 +
    Math.cos(lat * rad) * Math.cos(a * rad) * Math.sin((b - lon) * rad / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function nearbyCells(lat, lon, radius) {
  const angle = radius / 6371000;
  const dy = angle * 180 / Math.PI;
  const dx = Math.asin(Math.sin(angle) / Math.cos(lat * Math.PI / 180)) * 180 / Math.PI;
  const cells = [];
  for (let y = Math.floor((lat - dy) * 10); y <= Math.floor((lat + dy) * 10); y++) {
    for (let x = Math.floor((lon - dx) * 10); x <= Math.floor((lon + dx) * 10); x++) cells.push(`${y}_${x}`);
  }
  if (cells.length > 25) throw new Error('Too many cells');
  return cells;
}

export async function sha256(bytes) {
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(hash), x => x.toString(16).padStart(2, '0')).join('');
}

async function readObject(bucket, key, expected, cache, ctx, ttl = 86400) {
  const cacheKey = new Request(`https://snapshot-cache.internal/v1/${key}`);
  const cached = cache && await cache.match(cacheKey);
  if (cached) return cached.json();
  const object = await bucket.get(key);
  if (!object || object.size > MAX_TILE_BYTES) throw new Error(`Missing/oversize object: ${key}`);
  const bytes = await object.arrayBuffer();
  if (bytes.byteLength > MAX_TILE_BYTES || (expected &&
      (bytes.byteLength !== expected.bytes || await sha256(bytes) !== expected.sha256))) {
    throw new Error(`Invalid object: ${key}`);
  }
  const text = new TextDecoder().decode(bytes);
  const data = JSON.parse(text);
  if (cache && ctx) ctx.waitUntil(cache.put(cacheKey, new Response(text, {
    headers: {...HEADERS, 'Cache-Control': `public, max-age=${ttl}`},
  })).catch(() => {}));
  return data;
}

export async function activeManifest(bucket, cache, ctx) {
  const active = await readObject(bucket, 'active.json', null, cache, ctx, 30);
  if (!VERSION.test(active.version) || !active.manifest || !/^[a-f0-9]{64}$/.test(active.manifest.sha256)) {
    throw new Error('Invalid active pointer');
  }
  const manifest = await readObject(bucket, `versions/${active.version}/manifest.json`, active.manifest, cache, ctx);
  if (manifest.schema !== 1 || manifest.version !== active.version || manifest.cellDegrees !== 0.1 ||
      manifest.coverage !== 'Japan' || !manifest.cells || manifest.count < 10000 ||
      Object.keys(manifest.sources || {}).length !== 8) throw new Error('Incomplete manifest');
  return manifest;
}

export async function querySnapshot(bucket, params, {cache, ctx} = {}) {
  const manifest = await activeManifest(bucket, cache, ctx);
  const ids = nearbyCells(params.lat, params.lon, params.radius).filter(id => Object.hasOwn(manifest.cells, id));
  const elements = [];
  // Four concurrent reads keep peak memory and outbound connections bounded.
  for (let i = 0; i < ids.length; i += 4) {
    const batches = await Promise.all(ids.slice(i, i + 4).map(async id => {
      const tile = await readObject(bucket, `versions/${manifest.version}/tiles/${id}.json`, manifest.cells[id], cache, ctx);
      if (!Array.isArray(tile.elements) || tile.elements.length !== manifest.cells[id].count) throw new Error('Incomplete tile');
      return tile.elements;
    }));
    for (const items of batches) for (const item of items) {
      if (!Number.isFinite(item.lat) || !Number.isFinite(item.lon)) throw new Error('Invalid coordinates');
      if (distance(params.lat, params.lon, item.lat, item.lon) <= params.radius) elements.push(item);
    }
  }
  return {elements, dataset: {version: manifest.version, generatedAt: manifest.generatedAt,
    attribution: manifest.attribution, license: manifest.license, sourceUrl: manifest.sourceUrl}};
}

export async function snapshotResponse(request, env, ctx, cache) {
  const url = new URL(request.url);
  try {
    if (url.pathname === '/health') {
      const m = await activeManifest(env.SHOP_DATA, cache, ctx);
      return Response.json({status: 'ready', source: 'r2', version: m.version, count: m.count,
        generatedAt: m.generatedAt, sources: m.sources}, {headers: HEADERS});
    }
    // Make the ODbL-derived database downloadable without exposing other R2 objects.
    if (url.pathname === '/data/manifest.json') {
      return Response.json(await activeManifest(env.SHOP_DATA, cache, ctx), {headers: HEADERS});
    }
    const match = url.pathname.match(/^\/data\/([A-Za-z0-9_-]+)\/tiles\/(\d{3}_\d{4})\.json$/);
    if (match && VERSION.test(match[1]) && CELL.test(match[2])) {
      const m = await activeManifest(env.SHOP_DATA, cache, ctx);
      if (m.version !== match[1] || !Object.hasOwn(m.cells, match[2])) return new Response('Not found', {status: 404, headers: HEADERS});
      const data = await readObject(env.SHOP_DATA, `versions/${m.version}/tiles/${match[2]}.json`, m.cells[match[2]], cache, ctx);
      return Response.json(data, {headers: {...HEADERS, 'Cache-Control': 'public, max-age=86400'}});
    }
    if (url.pathname !== '/') return new Response('Not found', {status: 404, headers: HEADERS});
    const raw = ['lat', 'lon', 'radius'].map(key => url.searchParams.get(key));
    const [lat, lon, radius] = raw.map(Number);
    if (raw.some(x => !x?.trim()) || ![lat, lon, radius].every(Number.isFinite) ||
        lat < 20 || lat > 46 || lon < 122 || lon > 154 || radius <= 0 || radius > 10000) {
      return Response.json({error: 'Invalid lat, lon or radius'}, {status: 400, headers: HEADERS});
    }
    const result = await querySnapshot(env.SHOP_DATA, {lat, lon, radius}, {cache, ctx});
    return Response.json(result, {headers: {...HEADERS, 'X-Data-Source': 'r2', 'X-Dataset-Version': result.dataset.version}});
  } catch (error) {
    console.error('Snapshot unavailable:', error.message);
    // A missing tile is a failure, never a successful empty result.
    return Response.json({error: '店舗データを取得できませんでした。再検索してください。'},
      {status: 503, headers: {...HEADERS, 'Retry-After': '30'}});
  }
}
