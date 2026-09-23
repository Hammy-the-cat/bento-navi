import {test} from 'node:test';
import assert from 'node:assert/strict';
import {queryOverpass, validateBody} from './index.js';
const body = elements => JSON.stringify({elements});

test('HTTP 200のエラー・不完全応答を0件と扱わない', () => {
  assert.throws(() => validateBody('{"elements":[],"remark":"runtime error: timeout"}'));
  assert.throws(() => validateBody('{}'));
  assert.equal(validateBody(body([])), 0);
});
test('遅いミラーを待たず正常な応答を採用し、通信を中止する', async () => {
  const signals = [];
  const result = await queryOverpass(32,131,3000, {timeoutMs:100, endpoints:['slow','fast'], fetcher: async (url,options) => {
    signals.push(options.signal);
    return url === 'slow' ? new Promise(() => {}) : new Response(body([{id:1}]));
  }});
  assert.equal(result.count,1);
  assert.ok(signals.every(s => s.aborted));
});
test('0件+失敗は確認不能、全系統の正常0件だけを採用する', async () => {
  await assert.rejects(queryOverpass(32,131,3000, {endpoints:['empty','bad'], fetcher: async url => url==='empty' ? new Response(body([])) : new Response('bad',{status:503})}));
  const result = await queryOverpass(32,131,3000, {fetcher: async () => new Response(body([]))});
  assert.equal(result.count,0);
});
test('bodyの停止も総時間制限で中止し、重い店名検索と100件打切りを除く', async () => {
  let query;
  await assert.rejects(queryOverpass(32,131,3000, {timeoutMs:30, fetcher: async (_,options) => {
    query = new URLSearchParams(options.body).get('data');
    return {status:200, text: () => new Promise(() => {})};
  }}), /deadline/);
  assert.ok(!query.includes('["name"~'));
  assert.ok(!query.includes('tags 100'));
});
