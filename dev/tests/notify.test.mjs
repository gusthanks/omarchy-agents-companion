import test from 'node:test';
import assert from 'node:assert/strict';
import { usage } from './qml-js.mjs';

const N = usage('Notify');
const H = 3600000, D = 24 * H, MIN = 60000;
const NOW = Date.parse('2026-11-10T12:00:00Z');
const iso = ms => new Date(ms).toISOString();

let clock = NOW;
// One fresh fetch of a provider: every call advances its fetch time.
function fetch(id, limits, extra) {
  clock += 15 * MIN;
  return Object.assign({ providerId: id, providerName: id[0].toUpperCase() + id.slice(1), limits, limitsStale: false, limitsFetchedAt: clock }, extra);
}
const weekly = (percent, resetIn = 2 * D) => ({ label: 'Weekly (7-day)', percent: percent / 100, resetsAt: iso(NOW + resetIn) });
const run = (records, state, now = clock) => N.decide(records, 97, state, now);

test('crossing the threshold fires once, normal; 100% is critical', () => {
  const r = run([fetch('codex', [weekly(97)])], null);
  assert.equal(r.notifications.length, 1);
  assert.deepEqual(
    (({ kind, key, urgency, percent, window, title, source, name }) => ({ kind, key, urgency, percent, window, title, source, name }))(r.notifications[0]),
    { kind: 'limit', key: 'codex::Weekly (7-day)', urgency: 'normal', percent: 97, window: 'Weekly (7-day)', title: 'Weekly', source: 'codex', name: 'Codex' });
  assert.equal(r.notifications[0].resetAt, iso(NOW + 2 * D));
  assert.equal(run([fetch('codex', [weekly(100)])], null).notifications[0].urgency, 'critical');
  assert.equal(run([fetch('codex', [weekly(96)])], null).notifications.length, 0);
});

test('the same crossing never fires twice, even at 100%', () => {
  let s = run([fetch('codex', [weekly(97)])], null).nextState;
  for (const pct of [98, 100, 92, 97]) {
    const r = run([fetch('codex', [weekly(pct)])], s);
    assert.equal(r.notifications.length, 0, String(pct));
    s = r.nextState;
  }
});

test('hysteresis: re-arms only below threshold - 7', () => {
  let s = run([fetch('codex', [weekly(97)])], null).nextState;
  s = run([fetch('codex', [weekly(90)])], s).nextState;
  assert.equal(run([fetch('codex', [weekly(97)])], s).notifications.length, 0, '90 is inside the band');
  s = run([fetch('codex', [weekly(89)])], s).nextState;
  assert.equal(run([fetch('codex', [weekly(97)])], s).notifications.length, 1, '89 re-armed it');
});

test('a new window re-arms; jitter and an earlier reset do not', () => {
  let s = run([fetch('codex', [weekly(98)])], null).nextState;
  assert.equal(run([fetch('codex', [weekly(98, 2 * D + 700)])], s).notifications.length, 0, 'sub-second jitter');
  assert.equal(run([fetch('codex', [weekly(98, 2 * D + 60 * MIN)])], s).notifications.length, 0, 'a rolling hour');
  assert.equal(run([fetch('codex', [weekly(98, D)])], s).notifications.length, 0, 'earlier');
  assert.equal(run([fetch('codex', [weekly(98, 9 * D)])], s).notifications.length, 1, 'a new week');
  // An expired reset is a window that started over: 0%, which re-arms.
  s = run([fetch('codex', [{ label: 'Weekly (7-day)', percent: 1, resetsAt: iso(clock - MIN) }])], s).nextState;
  assert.equal(s.keys['codex::Weekly (7-day)'], undefined);
});

test('a reset appearing where none was reported re-arms; disappearing does not', () => {
  const noReset = pct => ({ label: '5h window', percent: pct / 100 });
  let s = run([fetch('codex', [noReset(99)])], null).nextState;
  assert.equal(s.keys['codex::5h window'].reset, null);
  assert.equal(run([fetch('codex', [noReset(99)])], s).notifications.length, 0);
  assert.equal(run([fetch('codex', [{ label: '5h window', percent: 0.99, resetsAt: iso(clock + 2 * H) }])], s).notifications.length, 1);
  s = run([fetch('codex', [weekly(99)])], null).nextState;
  assert.equal(run([fetch('codex', [{ label: 'Weekly (7-day)', percent: 0.99 }])], s).notifications.length, 0);
});

test('only fresh fetches decide: stale or repeated readings neither fire nor re-arm', () => {
  const rec = fetch('codex', [weekly(99)]);
  let s = run([rec], null).nextState;
  assert.equal(run([rec], s).notifications.length, 0, 'same fetch time');
  assert.equal(run([fetch('codex', [weekly(99)], { limitsStale: true })], null).notifications.length, 0, 'stale');
  const r = run([fetch('codex', [weekly(10)], { limitsStale: true })], s);
  assert.ok(r.nextState.keys['codex::Weekly (7-day)'], 'a stale drop does not re-arm');
  assert.equal(run([fetch('codex', [weekly(99)], { limitsFetchedAt: 0 })], null).notifications.length, 0, 'never fetched');
});

test('state is never mutated and survives a JSON round trip', () => {
  const first = run([fetch('codex', [weekly(99)])], null).nextState;
  const frozen = JSON.stringify(first);
  const restored = JSON.parse(frozen);
  run([fetch('codex', [weekly(10)])], first);
  assert.equal(JSON.stringify(first), frozen);
  assert.equal(run([fetch('codex', [weekly(99)])], restored).notifications.length, 0, 'a restart does not re-fire');
});

test('model-scoped windows and accounts have their own keys', () => {
  const claude = fetch('claude', [weekly(50), { label: 'Fable Weekly', title: 'Fable Weekly', percent: 0.98, resetsAt: iso(NOW + D) }]);
  const n = run([claude], null).notifications;
  assert.deepEqual(n.map(x => [x.key, x.title]), [['claude::Fable Weekly', 'Fable Weekly']]);
  clock += MIN;
  const codex = { providerId: 'codex', providerName: 'Codex', limits: [], accounts: [
    { id: 'work', label: 'Work', limits: [weekly(99)], fetchedAt: clock },
    { id: 'home', label: 'Home', limits: [weekly(99)], fetchedAt: clock, stale: true },
  ] };
  const m = run([codex], null).notifications;
  assert.deepEqual(m.map(x => [x.key, x.account, x.accountLabel]), [['codex@work::Weekly (7-day)', 'work', 'Work']]);
});

test('threshold is configurable and clamped', () => {
  assert.equal(N.decide([fetch('codex', [weekly(80)])], 80, null, clock).notifications.length, 1);
  assert.equal(N.decide([fetch('codex', [weekly(96)])], undefined, null, clock).notifications.length, 0, 'defaults to 97');
  assert.equal(N.normalizeThreshold(0), 1);
  assert.equal(N.normalizeThreshold(500), 100);
  assert.equal(N.normalizeThreshold('x'), 97);
});

test('banked reset credits: one warning inside 48h of the expiry', () => {
  const credits = (inMs, available = 2) => ({ resetCredits: { available, nextExpiresAt: iso(clock + inMs) } });
  assert.equal(run([fetch('codex', [], credits(49 * H + 15 * MIN))], null).notifications.length, 0, 'too early');
  const exp = clock + 15 * MIN + 47 * H;
  const r = run([fetch('codex', [], { resetCredits: { available: 2, nextExpiresAt: iso(exp) } })], null);
  assert.equal(r.notifications.length, 1);
  assert.deepEqual((({ kind, urgency, count, expiresAt, key }) => ({ kind, urgency, count, expiresAt, key }))(r.notifications[0]),
    { kind: 'credit', urgency: 'normal', count: 2, expiresAt: exp, key: 'codex::credit::' + exp });
  const again = run([fetch('codex', [], { resetCredits: { available: 2, nextExpiresAt: iso(exp) } })], r.nextState);
  assert.equal(again.notifications.length, 0, 'once per expiry');
  // The next credit's expiry is a new warning.
  assert.equal(run([fetch('codex', [], { resetCredits: { available: 1, nextExpiresAt: iso(exp + H) } })], again.nextState).notifications.length, 1);
  assert.equal(run([fetch('codex', [], credits(-MIN))], null).notifications.length, 0, 'already expired');
  assert.equal(run([fetch('codex', [], credits(H, 0))], null).notifications.length, 0, 'none available');
  assert.equal(run([fetch('codex', [], { resetCredits: { available: 1, nextExpiresAt: '' } })], null).notifications.length, 0, 'no expiry');
});

test('old keys are dropped: lapsed credits and crossings past the longest window', () => {
  const state = { seen: {}, keys: {
    'codex::credit::1': { notifiedAt: NOW - H, reset: NOW - MIN },
    'codex::Monthly': { notifiedAt: NOW - 40 * D, reset: null },
    'codex::Weekly (7-day)': { notifiedAt: NOW - D, reset: NOW + D },
  } };
  assert.deepEqual(Object.keys(N.decide([], 97, state, NOW).nextState.keys), ['codex::Weekly (7-day)']);
});
