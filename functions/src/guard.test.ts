// `npm test` in functions/.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { bangkokDay, checkMember, checkRequest, cleanReply, isQuestion, LIMITS } from './guard';

const tool = (name: string) => ({ type: 'function', function: { name, description: 'd', parameters: { type: 'object' } } });
const ok = (messages: unknown[], tools = [tool('get_schedule')]) => checkRequest({ messages, tools });

test('only the team, managers and the Maintainer get in', () => {
  assert.equal(checkMember('a@tc.co', true, {}), null);
  assert.equal(checkMember('a@tc.co', true, { role: 'manager' }), null);
  assert.equal(checkMember('a@tc.co', true, { role: 'maintainer' }), null);
  assert.equal(checkMember('a@tc.co', true, { role: 'external' })?.code, 'permission-denied');
  assert.equal(checkMember('a@tc.co', true, { suspended: true })?.code, 'permission-denied');
  assert.equal(checkMember('a@tc.co', true, undefined)?.code, 'permission-denied');
  assert.equal(checkMember('a@tc.co', false, {})?.code, 'unauthenticated');
  assert.equal(checkMember(undefined, true, {})?.code, 'unauthenticated');
});

test('a conversation is rebuilt from known fields', () => {
  const r = ok([
    { role: 'system', content: 's', extra: 1 },
    { role: 'user', content: 'q' },
    { role: 'assistant', content: null, tool_calls: [{ id: 'c0', type: 'function', function: { name: 'get_schedule', arguments: '{}' } }] },
    { role: 'tool', content: '{}', tool_call_id: 'c0' },
  ]);
  assert.ok(!('code' in r));
  assert.deepEqual(r.messages[0], { role: 'system', content: 's' });
  assert.equal(r.messages[2].tool_calls?.[0].function.name, 'get_schedule');
  assert.equal(r.tools.length, 1);
});

test('requests outside the rules are refused', () => {
  const refused = (r: ReturnType<typeof checkRequest>) => 'code' in r && r.code === 'invalid-argument';
  assert.ok(refused(checkRequest(null)));
  assert.ok(refused(ok([])));
  assert.ok(refused(ok([{ role: 'user', content: 'q' }, { role: 'system', content: 's' }])));      // system later on
  assert.ok(refused(ok([{ role: 'developer', content: 'q' }])));
  assert.ok(refused(ok([{ role: 'user', content: 'q' }], [tool('send_email')])));                   // unknown tool
  assert.ok(refused(ok([{ role: 'user', content: 'q' }], [tool('get_schedule'), tool('get_schedule')])));
  assert.ok(refused(ok([{ role: 'user', content: 'q' }, { role: 'assistant', content: 'a' }])));     // ends with the model
  assert.ok(refused(ok([{ role: 'tool', content: '{}' }])));                                         // no call id
  assert.ok(refused(ok([{ role: 'user', content: 'q' },
    { role: 'assistant', content: null, tool_calls: [{ id: 'c', function: { name: 'rm_rf', arguments: '{}' } }] },
    { role: 'tool', content: '{}', tool_call_id: 'c' }])));
  assert.ok(refused(ok(Array.from({ length: LIMITS.messages + 1 }, () => ({ role: 'user', content: 'q' })))));
  assert.ok(refused(ok([{ role: 'user', content: 'x'.repeat(LIMITS.chars) }])));
});

test('the reply keeps only what the app reads', () => {
  assert.deepEqual(cleanReply({ role: 'assistant', content: 'hi', reasoning_content: 'r' }), { role: 'assistant', content: 'hi' });
  const calls = cleanReply({ content: null, tool_calls: [{ id: 'c', type: 'function', function: { name: 'list_stations', arguments: '{}' } }] });
  assert.equal(calls?.tool_calls?.length, 1);
  // a tool the app doesn't have becomes words, never a call
  const odd = cleanReply({ content: null, tool_calls: [{ id: 'c', function: { name: 'delete_job', arguments: '{}' } }] });
  assert.equal(odd?.tool_calls, undefined);
  assert.equal(typeof odd?.content, 'string');
  assert.equal(cleanReply(undefined), null);
});

test('days are counted in Bangkok time', () => {
  assert.equal(bangkokDay(new Date('2026-10-18T17:30:00Z')), '2026-10-19');
  assert.equal(bangkokDay(new Date('2026-10-18T16:59:00Z')), '2026-10-18');
});

test('only a person\'s message starts a question; tool rounds don\'t count', () => {
  const sys = { role: 'system', content: 's' } as const;
  assert.equal(isQuestion([sys, { role: 'user', content: 'q' }]), true);
  assert.equal(isQuestion([sys, { role: 'user', content: 'q' },
    { role: 'assistant', content: null, tool_calls: [{ id: 'c', type: 'function', function: { name: 'get_schedule', arguments: '{}' } }] },
    { role: 'tool', content: '{}', tool_call_id: 'c' }]), false);
  assert.ok(LIMITS.roundsPerQuestion >= 5, 'the app takes up to 5 rounds a question');
});
