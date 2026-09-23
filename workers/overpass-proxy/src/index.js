import {snapshotResponse} from './snapshot.js';
import {catalogResponse} from './catalog.js';

/**
 * べんとうナビの店舗検索プロキシ。2系統を総時間7秒で照会し、
 * 完全な正常応答だけを採用する。店舗がある応答のみ6時間キャッシュ。
 */

const OVERPASS_ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];

const USER_AGENT =
  'BentoNavi/1.0 (https://bento.hammythecat.com/; excitedcherry0909@gmail.com)';


// 6時間。頻繁に変わらない店舗データにはこの程度で十分。
const CACHE_TTL_SECONDS = 6 * 60 * 60;

function buildQuery(lat, lon, radiusMeters) {
  const around = `around:${radiusMeters},${lat},${lon}`;
  return `
[out:json][timeout:6];
(
  nwr["shop"~"^(convenience|supermarket|deli|bakery)$"](${around});
  nwr["amenity"="fast_food"](${around});
  nwr["amenity"="restaurant"]["takeaway"~"^(yes|only)$"](${around});
);
out center tags;
`;
}

export function validateBody(bodyText) {
  const data = JSON.parse(bodyText);
  if (!Array.isArray(data.elements) || data.remark != null) {
    throw new Error('Incomplete Overpass response');
  }
  return data.elements.length;
}

// 同時に2系統まで。正常な非空応答を先着採用し、不要な通信も中止する。
// 0件は全系統が正常に0件と確認できた場合だけ採用する。
export async function queryOverpass(lat, lon, radiusMeters, {
  fetcher = fetch, timeoutMs = 7000, endpoints = OVERPASS_ENDPOINTS,
} = {}) {
  const controllers = endpoints.map(() => new AbortController());
  let timer;
  const tasks = endpoints.map(async (endpoint, i) => {
    const response = await fetcher(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': USER_AGENT },
      body: `data=${encodeURIComponent(buildQuery(lat, lon, radiusMeters))}`,
      signal: controllers[i].signal,
    });
    if (response.status !== 200) throw new Error(`HTTP ${response.status}`);
    const bodyText = await response.text(); // body読み取りも総時間制限の対象
    return { bodyText, count: validateBody(bodyText) };
  });
  const success = Promise.any(tasks.map(async task => {
    const result = await task;
    if (!result.count) throw new Error('empty');
    return result;
  }));
  const allEmpty = Promise.all(tasks).then(results => {
    if (results.every(r => r.count === 0)) return results[0];
    return new Promise(() => {});
  });
  // 一方の失敗で、もう一方の有効な応答を捨てない。
  const result = Promise.any([success, allEmpty]);
  try {
    return await Promise.race([result, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('Upstream deadline exceeded')), timeoutMs);
    })]);
  } finally {
    clearTimeout(timer);
    controllers.forEach(c => c.abort());
  }
}

function normalizeParams(url) {
  const latRaw = url.searchParams.get('lat');
  const lonRaw = url.searchParams.get('lon');
  const radiusRaw = url.searchParams.get('radius');
  if (!latRaw || !lonRaw || !radiusRaw) return null;

  const lat = Number(latRaw);
  const lon = Number(lonRaw);
  const radius = Number(radiusRaw);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || !Number.isFinite(radius)) {
    return null;
  }
  if (lat < 20 || lat > 46 || lon < 122 || lon > 154 || radius <= 0 || radius > 10000) return null;
  // キャッシュヒット率を上げるため、座標を約100m単位に丸める。
  // 検索半径(500m〜3km)に対して十分小さい誤差であり、キャッシュキーと
  // 実際にOverpassへ投げる座標の両方をこの丸めた値に揃える。
  return {
    lat: Math.round(lat * 1000) / 1000,
    lon: Math.round(lon * 1000) / 1000,
    radius: Math.round(radius),
  };
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }
    if (request.method !== 'GET') {
      return new Response('Method Not Allowed', { status: 405, headers: CORS_HEADERS });
    }

    // Activate only after a complete, validated dataset has been published.
    // Existing iOS versions understand the same {elements: [...]} response.
    if (env.SHOP_DATA) {
      if (url.pathname.startsWith('/catalog/')) return catalogResponse(request, env, ctx, caches.default);
      return snapshotResponse(request, env, ctx, caches.default);
    }

    const params = normalizeParams(url);
    if (params === null) {
      return new Response(
        JSON.stringify({ error: 'lat, lon, radius は必須の数値パラメータです' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } },
      );
    }

    const cache = caches.default;
    // v3: 不完全な応答・誤った0件キャッシュを無効化。
    const cacheKey = new Request(
      `https://cache-key.internal/overpass-v3?lat=${params.lat}&lon=${params.lon}&radius=${params.radius}`,
      { method: 'GET' },
    );

    const cached = await cache.match(cacheKey);
    if (cached) {
      const headers = new Headers(cached.headers);
      headers.set('X-Cache', 'HIT');
      return new Response(cached.body, { status: cached.status, headers });
    }

    let result;
    try {
      result = await queryOverpass(params.lat, params.lon, params.radius + 80);
    } catch (e) {
      return new Response(
        JSON.stringify({ error: `Overpass取得に失敗しました: ${e}` }),
        { status: 502, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } },
      );
    }

    const responseHeaders = {
      'Content-Type': 'application/json',
      'X-Cache': 'MISS',
      ...CORS_HEADERS,
    };

    if (result.count > 0) {
      const cacheableResponse = new Response(result.bodyText, {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': `public, max-age=${CACHE_TTL_SECONDS}`,
          ...CORS_HEADERS,
        },
      });
      ctx.waitUntil(cache.put(cacheKey, cacheableResponse));
    }

    return new Response(result.bodyText, { status: 200, headers: responseHeaders });
  },
};
