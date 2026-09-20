#!/usr/bin/env node
// Full, authenticated Google Sheets snapshot -> app catalog and row-level audit.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const fields = {
  id: '店舗ID', name: '店舗名', category: 'カテゴリ', municipality: '市町村',
  address: '住所', phone: '電話番号', hours: '営業時間', closedDays: '定休日',
  sourceUrl: '情報源URL', status: '確認状態', lastVerified: '最終確認日',
  coordinateAccuracy: '座標精度',
};
const required = [...Object.values(fields), '緯度', '経度', '予約・配達メモ', '備考'];
const text = v => String(v ?? '').trim();
const normalize = v => text(v).normalize('NFKC').replace(/[−‐―]/g, '-').replace(/\s/g, '');
const key = t => `${t.spreadsheetId}:${t.sheetId}`;
export const validCoordinates = (lat, lon) =>
  typeof lat === 'number' && typeof lon === 'number' &&
  Number.isFinite(lat) && Number.isFinite(lon) &&
  lat >= 20 && lat <= 46 && lon >= 122 && lon <= 154;

export function syncSnapshot(snapshot, registry, existing, { allowRemovals = false } = {}) {
  if (!/^\d{4}-\d{2}-\d{2}/.test(snapshot.fetchedAt ?? '')) throw Error('Missing fetchedAt');
  const expected = new Map(registry.tabs.map(t => [key(t), t]));
  const seenTabs = new Set();
  const seenIds = new Set();
  const previous = new Map(existing.map(s => [s.id, s]));
  if (previous.size !== existing.length) throw Error('Duplicate existing IDs');
  const shops = [];
  const audit = { fetchedAt: snapshot.fetchedAt, sourceRows: 0, mapped: 0, directoryOnly: [], closed: [], preservedCoordinates: [], removedFromSource: [], tabs: [] };
  for (const tab of snapshot.tabs) {
    const source = expected.get(key(tab));
    if (!source || seenTabs.has(key(tab)) || source.title !== tab.title) throw Error(`Unexpected/duplicate tab: ${key(tab)}`);
    seenTabs.add(key(tab));
    const [headers, ...rows] = tab.values;
    if (!headers || required.some(h => !headers.includes(h))) throw Error(`Missing columns: ${tab.book}/${tab.title}`);
    // Read through the metadata's last row and all required columns, not a sample.
    const end = tab.range?.match(/:([A-Z]+)(\d+)$/);
    const endColumn = end?.[1].split('').reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0);
    if (!end || !Number.isInteger(tab.grid?.rowCount) || Number(end[2]) < tab.grid.rowCount || endColumn < Math.max(...required.map(h => headers.indexOf(h) + 1))) {
      throw Error(`Incomplete range: ${tab.book}/${tab.title}`);
    }
    const ids = [];
    for (const [index, row] of rows.entries()) {
      if (row.every(v => !text(v))) continue;
      const get = h => text(row[headers.indexOf(h)]);
      const id = get('店舗ID');
      const location = { id, spreadsheetId: tab.spreadsheetId, sheetId: tab.sheetId, row: index + 2 };
      if (!id || !get('店舗名') || !get('市町村')) throw Error(`Missing identity: ${JSON.stringify(location)}`);
      if (seenIds.has(id)) throw Error(`Duplicate ID: ${id}`);
      seenIds.add(id); ids.push(id); audit.sourceRows++;
      if (['閉店', '閉店予定'].includes(get('確認状態'))) {
        audit.closed.push({ ...location, name: get('店舗名'), reason: get('確認状態') });
        continue;
      }
      const old = previous.get(id);
      const shop = Object.fromEntries(Object.entries(fields).map(([field, header]) => [field, get(header)]));
      // Keep harmless spelling/formatting and previously verified precision stable.
      for (const field of Object.keys(fields)) {
        if (old && normalize(shop[field]) === normalize(old[field])) shop[field] = old[field];
      }
      shop.notes = [get('予約・配達メモ'), get('備考')].filter(Boolean).join(' ');
      shop.prefecture = (/^.+[県都府道]$/.test(tab.title))
        ? tab.title : tab.book.match(/^(福岡県|佐賀県|長崎県|大分|鹿児島|みやざき)/)?.[0];
      shop.prefecture = ({ 大分: '大分県', 鹿児島: '鹿児島県', みやざき: '宮崎県' })[shop.prefecture] ?? shop.prefecture;
      if (!shop.prefecture) throw Error(`Unknown prefecture: ${tab.book}/${tab.title}`);
      const latText = get('緯度'), lonText = get('経度');
      let lat = latText ? Number(latText) : null;
      let lon = lonText ? Number(lonText) : null;
      if ((latText || lonText) && !validCoordinates(lat, lon)) throw Error(`Invalid coordinates: ${id}`);
      if (lat === null && lon === null && old && normalize(old.address) === normalize(shop.address) && validCoordinates(old.lat, old.lon)) {
        lat = old.lat; lon = old.lon;
        audit.preservedCoordinates.push(id);
        shop.coordinateAccuracy = old.coordinateAccuracy || shop.coordinateAccuracy;
      } else if (old && validCoordinates(lat, lon) && validCoordinates(old.lat, old.lon) && Math.abs(lat - old.lat) < 0.00001 && Math.abs(lon - old.lon) < 0.00001) {
        lat = old.lat; lon = old.lon;
      }
      shop.lat = lat; shop.lon = lon;
      if (validCoordinates(lat, lon)) audit.mapped++;
      else audit.directoryOnly.push({ ...location, name: shop.name, reason: get('座標精度').includes('販売店舗なし') ? '販売店舗なし・配達等の案内のみ' : '所在地・座標を確認中' });
      const order = ['id', 'name', 'category', 'municipality', 'address', 'lat', 'lon', 'phone', 'hours', 'closedDays', 'notes', 'sourceUrl', 'status', 'lastVerified', 'coordinateAccuracy', 'prefecture'];
      shops.push(Object.fromEntries(order.map(k => [k, shop[k]])));
    }
    audit.tabs.push({ ...source, rows: ids.length, ids });
  }
  if (seenTabs.size !== expected.size) throw Error('Missing source tabs');
  audit.removedFromSource = existing.filter(s => !seenIds.has(s.id)).map(s => s.id);
  if (audit.removedFromSource.length && !allowRemovals) throw Error(`Source deletions require review: ${audit.removedFromSource.join(', ')}`);
  const oldOrder = new Map(existing.map((s, i) => [s.id, i]));
  shops.sort((a, b) => (oldOrder.get(a.id) ?? Infinity) - (oldOrder.get(b.id) ?? Infinity) || a.id.localeCompare(b.id, 'en'));
  if (shops.length + audit.closed.length !== audit.sourceRows) throw Error('Unaccounted source rows');
  return { shops, audit };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  const snapshotPath = args.find(a => !a.startsWith('--'));
  if (!snapshotPath) throw Error('Usage: node tool/sync_sheet_snapshot.mjs <snapshot.json> [--write] [--allow-removals]');
  const read = p => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
  const raw = fs.readFileSync(snapshotPath);
  const result = syncSnapshot(read(snapshotPath), read('tool/sheet_sources.json'), read('assets/shops.json'), { allowRemovals: args.includes('--allow-removals') });
  const output = `${JSON.stringify(result.shops, null, 2)}\n`;
  result.audit.snapshotSha256 = createHash('sha256').update(raw).digest('hex');
  result.audit.catalogSha256 = createHash('sha256').update(output).digest('hex');
  if (args.includes('--write')) {
    // Validate everything before replacing either output.
    fs.writeFileSync('assets/shops.json', output);
    fs.mkdirSync('docs/data', { recursive: true });
    fs.writeFileSync('docs/data/sheet-sync-audit.json', `${JSON.stringify(result.audit, null, 2)}\n`);
  }
  console.log(JSON.stringify({ sourceRows: result.audit.sourceRows, catalog: result.shops.length, mapped: result.audit.mapped, directoryOnly: result.audit.directoryOnly, closed: result.audit.closed, preservedCoordinates: result.audit.preservedCoordinates.length, written: args.includes('--write') }, null, 2));
}
