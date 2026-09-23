const HEADERS = {'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Methods':'GET, OPTIONS',
  'Access-Control-Allow-Headers':'If-None-Match', 'Access-Control-Expose-Headers':'ETag',
  'Content-Type':'application/json; charset=utf-8'};
const HASH = /^[a-f0-9]{64}$/;

export async function catalogResponse(request, env, ctx, cache) {
  const url = new URL(request.url);
  if (url.pathname !== '/catalog/manifest.json' && !/^\/catalog\/[a-f0-9]{64}\.json\.gz$/.test(url.pathname)) {
    return new Response('Not found', {status:404, headers:HEADERS});
  }
  try {
    const key = new Request(`https://curated-cache.internal${url.pathname}`);
    const cached = cache && await cache.match(key);
    if (cached) return cached;
    let response;
    if (url.pathname === '/catalog/manifest.json') {
      const object = await env.SHOP_DATA.get('catalog/active.json');
      if (!object || object.size > 16384) throw Error('Catalog not published');
      const m = JSON.parse(await object.text());
      if (m.schema !== 1 || !HASH.test(m.version) || !HASH.test(m.sha256) ||
          m.count < 10000 || m.bytes < 1 || m.bytes > 3000000 ||
          m.jsonBytes > 20000000 || m.source !== 'curated-sheets' ||
          m.path !== `/catalog/${m.version}.json.gz`) throw Error('Invalid manifest');
      const {previous, ...publicManifest} = m;
      response = Response.json(publicManifest, {headers:{...HEADERS, 'Cache-Control':'public, max-age=60'}});
    } else {
      const version = url.pathname.slice('/catalog/'.length, -'.json.gz'.length);
      const object = await env.SHOP_DATA.get(`catalog/versions/${version}.json.gz`);
      if (!object || object.size > 3000000) throw Error('Missing catalog');
      response = new Response(object.body, {headers:{...HEADERS,
        'Content-Type':'application/octet-stream', 'Cache-Control':'public, max-age=31536000, immutable'}});
    }
    if (cache && ctx) ctx.waitUntil(cache.put(key, response.clone()).catch(() => {}));
    return response;
  } catch {
    return Response.json({error:'店舗一覧の更新を取得できませんでした'},
      {status:503, headers:{...HEADERS, 'Retry-After':'60', 'Cache-Control':'no-store'}});
  }
}
