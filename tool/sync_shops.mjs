#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { execFileSync } from 'node:child_process';

const HEADER_ALIASES = new Map([
  ['店舗ID', ['店舗ID', 'id']],
  ['店舗名', ['店舗名', 'name']],
  ['カテゴリ', ['カテゴリ', 'category']],
  ['市町村', ['市町村', 'municipality']],
  ['住所', ['住所', 'address']],
  ['緯度', ['緯度', 'latitude']],
  ['経度', ['経度', 'longitude']],
  ['電話番号', ['電話番号', 'phone']],
  ['営業時間', ['営業時間', 'opening_hours']],
  ['定休日', ['定休日', 'closed_days']],
  ['予約・配達メモ', ['予約・配達メモ', 'delivery_notes']],
  ['情報源URL', ['情報源URL', 'url']],
  ['最終確認日', ['最終確認日', 'checked']],
  ['確認状態', ['確認状態', 'status']],
  ['座標精度', ['座標精度', 'coordinate_accuracy']],
  ['備考', ['備考', 'note']],
]);

const REQUIRED_HEADERS = [...HEADER_ALIASES.keys()];

const EXCLUDED_STATUSES = new Set(['閉店', '閉店予定']);

function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (quoted) {
      if (char === '"' && text[i + 1] === '"') {
        cell += '"';
        i += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        cell += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ',') {
      row.push(cell);
      cell = '';
    } else if (char === '\n') {
      row.push(cell.replace(/\r$/, ''));
      rows.push(row);
      row = [];
      cell = '';
    } else {
      cell += char;
    }
  }

  if (cell.length > 0 || row.length > 0) {
    row.push(cell.replace(/\r$/, ''));
    rows.push(row);
  }
  return rows;
}

function value(row, indexes, header) {
  return (row[indexes.get(header)] ?? '').trim();
}

function resolveIndexes(headers) {
  const rawIndexes = new Map(
    headers.map((header, index) => [header.replace(/^\uFEFF/, '').trim(), index]),
  );
  const indexes = new Map();
  for (const [canonical, aliases] of HEADER_ALIASES) {
    const alias = aliases.find((candidate) => rawIndexes.has(candidate));
    if (alias) indexes.set(canonical, rawIndexes.get(alias));
  }
  return indexes;
}

function combineNotes(memo, remarks) {
  return [memo, remarks].filter(Boolean).join(' ');
}

function coordinateAccuracy(sheetValue, previousValue) {
  if (!sheetValue || sheetValue === '未取得') {
    return previousValue || sheetValue || '';
  }
  return sheetValue;
}

function loadExisting(outputPath, baselineRef) {
  if (baselineRef?.startsWith('git:')) {
    return JSON.parse(
      execFileSync('git', ['show', baselineRef.slice(4)], { encoding: 'utf8' }),
    );
  }
  return fs.existsSync(outputPath)
    ? JSON.parse(fs.readFileSync(outputPath, 'utf8'))
    : [];
}

function main() {
  const args = process.argv.slice(2);
  const mergeExisting = args.includes('--merge-existing');
  const positionalArgs = args.filter((arg) => arg !== '--merge-existing');
  const csvPath = positionalArgs[0];
  const outputPath = positionalArgs[1] ?? 'assets/shops.json';
  const baselineRef = positionalArgs[2];
  if (!csvPath) {
    console.error(
      'Usage: node tool/sync_shops.mjs <store-master.csv> [output.json] [git:<ref>:<path>] [--merge-existing]',
    );
    process.exit(1);
  }

  const rows = parseCsv(fs.readFileSync(csvPath, 'utf8'));
  const headers = rows.shift() ?? [];
  const indexes = resolveIndexes(headers);
  const missingHeaders = REQUIRED_HEADERS.filter((header) => !indexes.has(header));
  if (missingHeaders.length > 0) {
    throw new Error(`Missing CSV headers: ${missingHeaders.join(', ')}`);
  }

  const existing = loadExisting(outputPath, baselineRef);
  const existingById = new Map(existing.map((shop) => [shop.id, shop]));
  const shops = [];
  const unresolved = [];

  for (const row of rows) {
    const id = value(row, indexes, '店舗ID');
    const status = value(row, indexes, '確認状態');
    if (!id || EXCLUDED_STATUSES.has(status)) continue;

    const previous = existingById.get(id);
    const latText = value(row, indexes, '緯度');
    const lonText = value(row, indexes, '経度');
    const sheetLat = latText ? Number(latText) : undefined;
    const sheetLon = lonText ? Number(lonText) : undefined;
    const preservePreviousCoordinates =
      previous &&
      Number.isFinite(sheetLat) &&
      Number.isFinite(sheetLon) &&
      Number.isFinite(previous.lat) &&
      Number.isFinite(previous.lon) &&
      Math.abs(sheetLat - previous.lat) < 0.00001 &&
      Math.abs(sheetLon - previous.lon) < 0.00001;
    const lat = preservePreviousCoordinates
      ? previous.lat
      : Number.isFinite(sheetLat)
        ? sheetLat
        : previous?.lat;
    const lon = preservePreviousCoordinates
      ? previous.lon
      : Number.isFinite(sheetLon)
        ? sheetLon
        : previous?.lon;
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      unresolved.push({ id, name: value(row, indexes, '店舗名') });
      continue;
    }

    shops.push({
      id,
      name: value(row, indexes, '店舗名'),
      category: value(row, indexes, 'カテゴリ'),
      municipality: value(row, indexes, '市町村'),
      address: value(row, indexes, '住所'),
      lat,
      lon,
      phone: value(row, indexes, '電話番号'),
      hours: value(row, indexes, '営業時間'),
      closedDays: value(row, indexes, '定休日'),
      notes: combineNotes(
        value(row, indexes, '予約・配達メモ'),
        value(row, indexes, '備考'),
      ),
      sourceUrl: value(row, indexes, '情報源URL'),
      status,
      lastVerified: value(row, indexes, '最終確認日'),
      coordinateAccuracy: coordinateAccuracy(
        value(row, indexes, '座標精度'),
        previous?.coordinateAccuracy,
      ),
    });
  }

  if (mergeExisting) {
    const importedById = new Map(shops.map((shop) => [shop.id, shop]));
    const existingIds = new Set(existing.map((shop) => shop.id));
    const merged = existing.map((shop) => importedById.get(shop.id) ?? shop);
    for (const shop of shops) {
      if (!existingIds.has(shop.id)) merged.push(shop);
    }
    shops.length = 0;
    shops.push(...merged);
  } else {
    shops.sort((a, b) => a.id.localeCompare(b.id, 'ja'));
  }
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(shops, null, 2)}\n`, 'utf8');

  console.log(
    JSON.stringify(
      {
        written: shops.length,
        output: outputPath,
        unresolved,
      },
      null,
      2,
    ),
  );
}

main();
