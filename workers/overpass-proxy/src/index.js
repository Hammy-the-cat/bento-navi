/**
 * べんとうナビ用 Overpass API キャッシュプロキシ。
 *
 * lib/services/bento_service.dart の searchShops() が直接 Overpass ミラーを
 * 叩いていた部分をエッジでキャッシュする。QLクエリの組み立て・ミラー順・
 * 「0件は次のミラーを試す」ロジックは同ファイルから移植したもの。
 * Worker が失敗した場合、アプリ側は従来のミラー直叩きにフォールバックする
 * (lib/services/bento_service.dart 参照)。
 */

const OVERPASS_ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

const USER_AGENT =
  'BentoNavi/1.0 (https://bento.hammythecat.com/; excitedcherry0909@gmail.com)';

const NAME_RE = '弁当|べんとう|ほか弁|ほっともっと|かまどや|オリジン|惣菜|仕出し';

// 6時間。頻繁に変わらない店舗データにはこの程度で十分。
const CACHE_TTL_SECONDS = 6 * 60 * 60;

function buildQuery(lat, lon, radiusMeters) {
  const around = `around:${radiusMeters},${lat},${lon}`;
  return `
[out:json][timeout:25];
(
  nwr["shop"~"^(convenience|supermarket|deli|bakery)$"](${around});
  nwr["amenity"="fast_food"](${around});
  nwr["name"~"${NAME_RE}"](${around});
  nwr["amenity"="restaurant"]["takeaway"~"^(yes|only)$"](${around});
);
out center tags 100;
`;
}

function hasElements(bodyText) {
  try {
    const json = JSON.parse(bodyText);
    return Array.isArray(json.elements) && json.elements.length > 0;
  } catch {
    return false;
  }
}

async function fetchWithTimeout(url, options, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function queryOverpass(lat, lon, radiusMeters) {
  const query = buildQuery(lat, lon, radiusMeters);
  let emptyBody = null;
  let lastError = null;

  for (const endpoint of OVERPASS_ENDPOINTS) {
    try {
      const res = await fetchWithTimeout(
        endpoint,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': USER_AGENT,
          },
          body: `data=${encodeURIComponent(query)}`,
        },
        20000,
      );
      if (res.status === 200) {
        const bodyText = await res.text();
        if (hasElements(bodyText)) {
          return { bodyText, cacheable: true };
        }
        // 0件はミラーがそのデータを持っていない可能性がある → 次を試す
        emptyBody ??= bodyText;
        continue;
      }
      lastError = new Error(`HTTP ${res.status}`);
    } catch (e) {
      lastError = e;
    }
  }

  if (emptyBody !== null) {
    // 全ミラーが0件 → 本当に周辺に店が無いとみなし、キャッシュもする
    return { bodyText: emptyBody, cacheable: true };
  }
  throw lastError ?? new Error('all mirrors failed');
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
  if (radius <= 0) return null;
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

    const params = normalizeParams(url);
    if (params === null) {
      return new Response(
        JSON.stringify({ error: 'lat, lon, radius は必須の数値パラメータです' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } },
      );
    }

    const cache = caches.default;
    // v2: CORSヘッダーをキャッシュ本体に含めるよう修正したため、
    // それ以前に保存された(CORSヘッダー欠落の)キャッシュを無効化するために
    // キーのバージョンを上げてある。
    const cacheKey = new Request(
      `https://cache-key.internal/overpass-v2?lat=${params.lat}&lon=${params.lon}&radius=${params.radius}`,
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
      result = await queryOverpass(params.lat, params.lon, params.radius);
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

    if (result.cacheable) {
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
