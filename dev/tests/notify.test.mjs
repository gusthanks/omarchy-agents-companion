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

test('the same crossing fires once near the cap and once more when spent', () => {
  let s = run([fetch('codex', [weekly(97)])], null).nextState;
  assert.equal(s.keys['codex::Weekly (7-day)'].level, 'normal');
  let r = run([fetch('codex', [weekly(98)])], s);
  assert.equal(r.notifications.length, 0, '98');
  r = run([fetch('codex', [weekly(100)])], r.nextState);
  assert.deepEqual(r.notifications.map(n => [n.urgency, n.percent]), [['critical', 100]], 'spent');
  s = r.nextState;
  for (const pct of [100, 99, 92, 100, 97]) {
    r = run([fetch('codex', [weekly(pct)])], s);
    assert.equal(r.notifications.length, 0, String(pct));
    s = r.nextState;
  }
  // A crossing first seen at 100% is critical once, and that's all.
  s = run([fetch('claude', [weekly(100)])], null).nextState;
  assert.equal(run([fetch('claude', [weekly(100)])], s).notifications.length, 0);
  // A key kept without a level (an older state) is taken to have had both.
  const legacy = { seen: {}, keys: { 'codex::Weekly (7-day)': { notifiedAt: clock, reset: NOW + 2 * D } } };
  assert.equal(run([fetch('codex', [weekly(100)])], legacy).notifications.length, 0);
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

test('readings from before the plugin started are recorded quietly, for sources never seen', () => {
  const old = fetch('codex', [weekly(99)]);
  const start = clock + MIN;
  let r = N.decide([old], 97, null, start, start);
  assert.equal(r.notifications.length, 0, 'old news on a first run');
  assert.ok(r.nextState.keys['codex::Weekly (7-day)'], 'but it is marked');
  assert.equal(N.decide([fetch('codex', [weekly(99)])], 97, r.nextState, clock, start).notifications.length, 0, 'the same crossing');
  assert.deepEqual(N.decide([fetch('codex', [weekly(100)])], 97, r.nextState, clock, start).notifications.map(n => n.urgency), ['critical'], 'but spending it is news');
  // A source the state knows fires for a reading taken while the shell was down.
  const known = { seen: { codex: old.limitsFetchedAt - H }, keys: {} };
  assert.equal(N.decide([old], 97, known, start, start).notifications.length, 1);
  // A source first seen after the start is news.
  assert.equal(N.decide([fetch('claude', [weekly(99)])], 97, r.nextState, clock, start).notifications.length, 1);
  // A quiet credit is marked too, and doesn't fire later.
  const exp = clock + 15 * MIN + 20 * H;
  const credit = fetch('codex', [], { resetCredits: { available: 1, nextExpiresAt: iso(exp) } });
  r = N.decide([credit], 97, null, clock, clock + MIN);
  assert.equal(r.notifications.length, 0);
  assert.equal(run([fetch('codex', [], { resetCredits: { available: 1, nextExpiresAt: iso(exp) } })], r.nextState).notifications.length, 0);
});

test('notify-send argv: no shell, switches first, provider text tamed', () => {
  assert.deepEqual(N.sendArgs('normal', 'Claude: Weekly at 97%', 'Resets in 1d 4h.', '/c/kian-icon.png'),
    ['notify-send', '-a', 'Agents Pet', '-u', 'normal', '-i', '/c/kian-icon.png', 'Claude: Weekly at 97%', 'Resets in 1d 4h.']);
  assert.deepEqual(N.sendArgs('critical', 't', 'b', ''), ['notify-send', '-a', 'Agents Pet', '-u', 'critical', '-t', '30000', 't', 'b']);
  const args = N.sendArgs('normal', '--help\n$(rm -rf ~)', 'a <b>&</b>\u0007 c', null);
  assert.deepEqual(args.slice(-2), ['help $(rm -rf ~)', 'a &lt;b&gt;&amp;&lt;/b&gt; c']);
  assert.equal(N.sendArgs('weird', 'x', 'y')[4], 'normal');
});

test('persisted state is read back only in its own shape', () => {
  const s = { seen: { codex: 1 }, keys: { 'codex::Weekly': { notifiedAt: 1, reset: null } } };
  assert.deepEqual(N.parseState(JSON.stringify(s)), s);
  for (const bad of ['', '{', 'null', '[]', '{"seen":{}}', '{"seen":1,"keys":{}}'])
    assert.equal(N.parseState(bad), null, bad);
});

test('a provider gaining or losing an account keeps its past', () => {
  const single = (pct, extra) => fetch('claude', [weekly(pct)], extra);
  const two = (pct, active = 'main') => {
    clock += 15 * MIN;
    return { providerId: 'claude', providerName: 'Claude', limits: [weekly(pct)], limitsFetchedAt: clock, accounts: [
      { id: 'main', label: 'Main', active: active === 'main', limits: [weekly(pct)], fetchedAt: clock },
      { id: 'work', label: 'Work', active: active === 'work', limits: [weekly(10)], fetchedAt: clock },
    ] };
  };
  const start = NOW - D;
  let r = N.decide([single(97)], 97, null, clock, start);
  assert.equal(r.notifications.length, 1);
  // An hour later a second account is added while the shell runs: the active
  // one inherits the crossing, the new one has nothing to say.
  clock += H;
  r = N.decide([two(97)], 97, r.nextState, clock, start);
  assert.deepEqual(r.notifications, [], 'no repeat for claude@main');
  assert.ok(r.nextState.keys['claude@main::Weekly (7-day)']);
  assert.equal(r.nextState.keys['claude::Weekly (7-day)'], undefined);
  assert.equal(r.nextState.seen.claude, undefined);
  // Spent on the same account still gets its critical notice.
  r = N.decide([two(100)], 97, r.nextState, clock, start);
  assert.deepEqual(r.notifications.map(n => [n.key, n.urgency]), [['claude@main::Weekly (7-day)', 'critical']]);
  // Back to one account: the bare key takes the newest account's past.
  r = N.decide([single(100)], 97, r.nextState, clock, start);
  assert.deepEqual(r.notifications, [], 'no repeat for claude');
  assert.equal(r.nextState.keys['claude::Weekly (7-day)'].level, 'critical');
  // Two accounts with no active one: nothing to hand over, so nothing moves.
  assert.equal(N.decide([two(50, 'none')], 97, r.nextState, clock, start).nextState.keys['claude::Weekly (7-day)'].level, 'critical');
});

test('a fetch stamped in the future neither fires nor holds back the real ones', () => {
  const ahead = fetch('codex', [weekly(99)], { limitsFetchedAt: clock + 30 * D });
  let r = run([ahead], null, clock);
  assert.equal(r.notifications.length, 0, 'a clock running ahead');
  assert.equal(r.nextState.seen.codex, undefined);
  // A bad stamp already in the state doesn't block the next real fetch.
  r = run([fetch('codex', [weekly(100)])], { seen: { codex: clock + 30 * D }, keys: {} });
  assert.equal(r.notifications.length, 1);
  assert.equal(r.nextState.seen.codex, clock);
});
