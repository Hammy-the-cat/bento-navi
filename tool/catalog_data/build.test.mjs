import {test} from 'node:test';
import assert from 'node:assert/strict';
import {buildCatalog} from './build.mjs';
const registry={spreadsheets:[{id:'test'}],tabs:[{spreadsheetId:'test',sheetId:0,title:'宮崎県',book:'test'}]};
const headers=['店舗ID','店舗名','カテゴリ','市町村','住所','緯度','経度','電話番号','営業時間','定休日','予約・配達メモ','情報源URL','最終確認日','確認状態','座標精度','備考'];
const old=Array.from({length:10010},(_,i)=>({id:`S${i}`,name:`店舗${i}`,category:'弁当',municipality:'宮崎市',prefecture:'宮崎県',address:`宮崎市${i}`,lat:31.9,lon:131.4}));
function fixture() {
  return {fetchedAt:new Date().toISOString(),tabs:[{...registry.tabs[0],grid:{rowCount:10011,columnCount:16},range:"'宮崎県'!A1:P10011",
    values:[headers,...old.map(s=>[s.id,s.name,s.category,s.municipality,s.address,s.lat,s.lon,'','','','','','','確認済み','',''])]}]};
}
test('daily build reflects edits and explicit closures; unchanged output has stable version',()=>{
  const f=fixture();
  f.tabs[0].values[1][1]='新しい店名';
  f.tabs[0].values[2][13]='閉店';
  const result=buildCatalog(f,registry,old);
  assert.equal(result.shops[0].name,'新しい店名');
  assert.equal(result.shops.length,10009);
  assert.equal(result.manifest.version,buildCatalog(f,registry,result.shops).manifest.version);
});
test('incomplete reads, deleted rows, address-only moves and new duplicates block publication',()=>{
  const missing=fixture();missing.tabs=[];
  assert.throws(()=>buildCatalog(missing,registry,old),/Missing source tabs/);
  const removed=fixture();removed.tabs[0].values.pop();
  assert.throws(()=>buildCatalog(removed,registry,old),/Source deletions/);
  const moved=fixture();moved.tabs[0].values[1][4]='宮崎市新住所';
  assert.throws(()=>buildCatalog(moved,registry,old),/coordinate review/);
  const dup=fixture();dup.tabs[0].values[2][1]=old[0].name;dup.tabs[0].values[2][4]=old[0].address;
  assert.throws(()=>buildCatalog(dup,registry,old),/duplicate shop|coordinate review/);
});
test('stale snapshot and mass closures keep previous version',()=>{
  const stale=fixture();stale.fetchedAt='2020-01-01';
  assert.throws(()=>buildCatalog(stale,registry,old),/Stale/);
  const closed=fixture();closed.tabs[0].values.slice(1,600).forEach(r=>r[13]='閉店');
  assert.throws(()=>buildCatalog(closed,registry,old),/count drop/);
});
