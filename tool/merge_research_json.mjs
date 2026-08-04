#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const EXCLUDED_STATUSES = new Set(['閉店', '閉店予定']);

function text(value) {
  return value?.toString().trim() ?? '';
}

function combineNotes(row) {
  return [text(row.delivery_notes), text(row.note)].filter(Boolean).join(' ');
}

function toAppShop(row, inputPath) {
  const id = text(row.id);
  const lat = Number(row.latitude);
  const lon = Number(row.longitude);
  if (!id) throw new Error(`Missing id in ${inputPath}`);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    throw new Error(`Invalid coordinates for ${id} in ${inputPath}`);
  }

  return {
    id,
    name: text(row.name),
    category: text(row.category),
    municipality: text(row.municipality),
    address: text(row.address),
    lat,
    lon,
    phone: text(row.phone),
    hours: text(row.opening_hours),
    closedDays: text(row.closed_days),
    notes: combineNotes(row),
    sourceUrl: text(row.url),
    status: text(row.status),
    lastVerified: text(row.checked),
    coordinateAccuracy: text(row.coordinate_accuracy),
  };
}

function main() {
  const [outputPath = 'assets/shops.json', ...inputPaths] = process.argv.slice(2);
  if (inputPaths.length === 0) {
    console.error(
      'Usage: node tool/merge_research_json.mjs <output.json> <research1.json> [research2.json ...]',
    );
    process.exit(1);
  }

  const existing = fs.existsSync(outputPath)
    ? JSON.parse(fs.readFileSync(outputPath, 'utf8'))
    : [];
  const mergedById = new Map(existing.map((shop) => [shop.id, shop]));
  const newIds = [];
  const importedIds = new Set();
  let excluded = 0;

  for (const inputPath of inputPaths) {
    const rows = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
    if (!Array.isArray(rows)) throw new Error(`Expected an array in ${inputPath}`);
    for (const row of rows) {
      if (EXCLUDED_STATUSES.has(text(row.status))) {
        excluded += 1;
        continue;
      }
      const shop = toAppShop(row, inputPath);
      if (importedIds.has(shop.id)) {
        throw new Error(`Duplicate imported id: ${shop.id}`);
      }
      importedIds.add(shop.id);
      if (!mergedById.has(shop.id)) newIds.push(shop.id);
      mergedById.set(shop.id, shop);
    }
  }

  const existingIds = new Set(existing.map((shop) => shop.id));
  const merged = existing.map((shop) => mergedById.get(shop.id));
  for (const id of newIds) {
    if (!existingIds.has(id)) merged.push(mergedById.get(id));
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(merged, null, 2)}\n`, 'utf8');
  console.log(JSON.stringify({ written: merged.length, imported: importedIds.size, excluded }, null, 2));
}

main();
