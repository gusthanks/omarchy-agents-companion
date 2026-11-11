import test from 'node:test';
import assert from 'node:assert/strict';
import { usage } from './qml-js.mjs';

const P = usage('Priority');
const S = usage('Sources');
const H = 3600000, D = 24 * H, MIN = 60000;
const NOW = 1800000000000;
const iso = ms => new Date(ms).toISOString();

// A provider record as the panel sees it (Main.qml displayProvider).
function provider(id, limits, extra) {
  return Object.assign({ providerId: id, providerName: id, ready: true, limits, limitsStale: false, limitsFetchedAt: NOW }, extra);
}
const limit = (label, percent, resetIn, title) =>
  Object.assign({ label, percent: percent / 100, resetsAt: resetIn === null ? '' : iso(NOW + resetIn) }, title ? { title } : {});
const weekly = (id, used, extra) => provider(id, [limit('Weekly (7-day)', used, D)], extra);
const sample = (at, percent, source = 'a', reset = NOW + D) => ({ source, window: 'Weekly (7-day)', at, reset, percent });
const rank = (records, samples = [], opts) => P.rank(records, samples, NOW, opts);

test('sources: the provider itself, or each account once there are several', () => {
  const single = provider('claude', [limit('Weekly (7-day)', 10, D)], { accounts: [{ id: 'me', limits: [] }] });
  assert.deepEqual(S.sources([single]).map(s => s.key), ['claude']);
  const multi = provider('codex', [limit('Weekly (7-day)', 10, D)], { accounts: [
    { id: 'work', label: 'Work', active: true, limits: [limit('Weekly (7-day)', 30, D)], stale: false, fetchedAt: NOW,
      resetCredits: { available: 1, nextExpiresAt: iso(NOW + D) } },
    { id: 2, limits: [limit('Weekly (7-day)', 60, D)], stale: true, fetchedAt: NOW - H },
  ] });
  const list = S.sources([multi]);
  assert.deepEqual(list.map(s => [s.key, s.account, s.accountLabel, s.stale]), [['codex@work', 'work', 'Work', false], ['codex@2', '2', '2', true]]);
  assert.equal(list[0].resetCredits.available, 1);
  // Raw usage records work as well.
  assert.deepEqual(S.sources([{ id: 'grok', limits: [], limitsFetchedAt: 5 }, null, {}]).map(s => [s.key, s.fetchedAt]), [['grok', 5]]);
});

test('history: one sample per fresh fetch, and only from fresh, current, sane readings', () => {
  const a = weekly('a', 20);
  let r = P.append([], [a], NOW);
  assert.equal(r.added, 1);
  assert.deepEqual(r.samples, [{ source: 'a', window: 'Weekly (7-day)', at: NOW, reset: NOW + D, percent: 20 }]);
  r = P.append(r.samples, [a], NOW + 5 * MIN);
  assert.equal(r.added, 0, 'the same fetch again is not a new reading');
  r = P.append(r.samples, [weekly('a', 25, { limitsFetchedAt: NOW + 15 * MIN })], NOW + 15 * MIN);
  assert.equal(r.added, 1, 'the fetch time advanced');
  assert.equal(P.append([], [weekly('a', 20, { limitsStale: true })], NOW).added, 0, 'stale');
  assert.equal(P.append([], [weekly('a', 20, { limitsFetchedAt: NOW - 2 * H })], NOW).added, 0, 'too old to be current');
  assert.equal(P.append([], [weekly('a', 20, { limitsFetchedAt: NOW + H })], NOW).added, 0, 'from the future');
  assert.equal(P.append([], [weekly('a', 20, { limitsFetchedAt: NOW + MIN })], NOW).added, 1, 'a little skew is fine');
  assert.equal(P.append([], [weekly('a', 20, { limitsFetchedAt: 0 })], NOW).added, 0, 'never fetched');
  assert.equal(P.append([], [provider('a', [limit('Weekly (7-day)', 20, null)])], NOW).added, 0, 'no reset');
  assert.equal(P.append([], [provider('a', [{ label: 'Weekly', percent: 1.5, resetsAt: iso(NOW + D) }])], NOW).added, 0, 'over 100%');
  assert.equal(P.append([], [provider('a', [limit('Weekly (7-day)', 0, D), limit('Session (5-hour)', 100, H)])], NOW).added, 2, '0% and 100%');
});

test('history: accounts are their own sources', () => {
  const rec = provider('codex', [], { accounts: [
    { id: 'x', limits: [limit('Weekly (7-day)', 10, D)], fetchedAt: NOW },
    { id: 'y', limits: [limit('Weekly (7-day)', 50, D)], fetchedAt: NOW },
  ] });
  assert.deepEqual(P.append([], [rec], NOW).samples.map(s => [s.source, s.percent]), [['codex@x', 10], ['codex@y', 50]]);
});

test('history: pruned to 25 hours and capped, never mutated', () => {
  const old = [sample(NOW - 26 * H, 1), sample(NOW - 24 * H, 2), sample(NOW + H, 3), { source: 'a', percent: 'x' }];
  const frozen = JSON.stringify(old);
  const r = P.append(old, [], NOW);
  assert.deepEqual(r.samples.map(s => s.percent), [2]);
  assert.equal(JSON.stringify(old), frozen);
  const many = Array.from({ length: P.MAX_SAMPLES + 10 }, (_, i) => sample(NOW - H + i, 1));
  const capped = P.append(many, [], NOW).samples;
  assert.equal(capped.length, P.MAX_SAMPLES);
  assert.equal(capped[0].at, NOW - H + 10, 'the newest are kept');
});

test('history file: round trip, and corruption is no history', () => {
  const samples = [sample(NOW, 20)];
  assert.deepEqual(P.parse(P.serialize(samples)), samples);
  for (const text of ['', 'nope', '[]', '{"samples": 3}', 'null'])
    assert.deepEqual(P.parse(text), [], text);
  assert.deepEqual(P.parse(JSON.stringify({ samples: [sample(NOW, 20), { source: 1 }, sample(NOW, 101)] })), samples);
});

test('recent acceleration changes the order', () => {
  const a = weekly('a', 20), b = weekly('b', 30);
  assert.equal(rank([a, b])[0].key, 'a');
  const samples = Array.from({ length: 7 }, (_, i) => sample(NOW - 3 * H + i * 30 * MIN, i * 20 / 6));
  const rows = rank([a, b], samples);
  assert.equal(rows[0].key, 'b');
  assert.equal(typeof rows[1].recentPerHour, 'number');
});

test('a reset, a gap or another window makes no recent rate', () => {
  const rate = s => P.recentRate(s, 'a', 'Weekly (7-day)', NOW + D, NOW, 20, 3);
  assert.equal(rate([sample(NOW - H, 30), sample(NOW, 20)]), null, 'a drop');
  assert.equal(rate([sample(NOW - 3 * H, 0), sample(NOW, 20)]), null, 'a gap');
  assert.equal(rate([sample(NOW - H, 0, 'a', NOW + D - 7 * D), sample(NOW, 20)]), null, 'another window');
  assert.equal(rate([sample(NOW - H, 0, 'b'), sample(NOW, 20)]), null, 'another source');
  assert.equal(rate([sample(NOW - 20 * MIN, 0), sample(NOW, 20)]), null, 'under half an hour');
  assert.deepEqual(rate([sample(NOW - H, 10), sample(NOW - 30 * MIN, 15), sample(NOW, 20)]), { rate: 10, hours: 1 });
  // An hourly refresh still makes a run.
  assert.deepEqual(rate([sample(NOW - 2 * H, 10), sample(NOW - H, 15), sample(NOW, 20)]), { rate: 5, hours: 2 });
  // Reported resets jitter by a fraction of a second.
  assert.notEqual(rate([sample(NOW - H, 10, 'a', NOW + D + 700), sample(NOW, 20)]), null);
});

test('zero recent use is measured, not missing', () => {
  const samples = Array.from({ length: 7 }, (_, i) => sample(NOW - 3 * H + i * 30 * MIN, 20));
  const row = rank([weekly('a', 20)], samples)[0];
  assert.equal(row.recentPerHour, 0);
  assert.equal(row.recentHours, 3);
});

test('the configured recent span changes the rate and the priority', () => {
  // Four idle hours, then an hour of fast use.
  const samples = Array.from({ length: 11 }, (_, i) => sample(NOW - 5 * H + i * 30 * MIN, i <= 8 ? 0 : (i - 8) * 10));
  const records = [weekly('a', 20), weekly('b', 75)];
  const short = rank(records, samples, { recentHours: 1 });
  const long = rank(records, samples, { recentHours: 6 });
  assert.equal(short[0].key, 'b');
  assert.equal(long[0].key, 'a');
  assert.equal(short[1].recentPerHour, 20);
  assert.equal(long[0].recentPerHour, 4);
});

test('a stale current reading uses no recent rate', () => {
  const samples = Array.from({ length: 7 }, (_, i) => sample(NOW - 5 * H + i * 30 * MIN, i * 3));
  const row = rank([weekly('a', 18, { limitsFetchedAt: NOW - 2 * H, limitsStale: true })], samples)[0];
  assert.equal(row.status, 'priority');
  assert.equal(row.recentPerHour, null);
  assert.equal(row.stale, true);
});

test('every source with limits stays visible, in tier order', () => {
  const r = rank([
    weekly('a', 20), weekly('blocked', 100),
    weekly('stale', 20, { limitsStale: true, limitsFetchedAt: NOW - 6 * H - 1 }),
    weekly('notready', 20, { ready: false }),
    provider('unknown', [limit('Spend limit', 20, D)]),
    weekly('ontrack', 86), weekly('runout', 99),
    provider('nolimits', []),
  ]);
  assert.deepEqual(r.map(x => [x.key, x.status]), [
    ['a', 'priority'], ['ontrack', 'on_track'], ['runout', 'running_out'], ['unknown', 'unknown'], ['blocked', 'blocked'],
    ['notready', 'unavailable'], ['stale', 'unavailable'],
  ]);
  assert.ok(r.every(x => !('score' in x)));
  assert.equal(P.recommendation(r).key, 'a');
  assert.equal(P.recommendation(r.slice(1)), null);
});

test('a recently cached reading still ranks', () => {
  const row = rank([weekly('a', 20, { limitsStale: true, limitsFetchedAt: NOW - 3 * H })])[0];
  assert.equal(row.status, 'priority');
});

test('urgent only with real unused quota before a near reset', () => {
  const rows = rank([
    weekly('urgent', 20), weekly('ontrack', 86), weekly('blocked', 100),
    provider('tomorrow', [limit('Weekly (7-day)', 20, D + 1000)]),
  ]);
  assert.equal(rows[0].key, 'urgent');
  assert.equal(rows[0].urgent, true);
  assert.equal(rows[0].alertUnusedPercent, 50);
  assert.ok(rows.filter(r => r.key !== 'urgent').every(r => r.urgent === false));
  // Raise the bar and nothing is urgent; widen the horizon and tomorrow is.
  assert.equal(rank([weekly('a', 20)], [], { alertUnusedPercent: 90 })[0].urgent, false);
  assert.equal(rank([provider('t', [limit('Weekly (7-day)', 20, D + 1000)])], [], { alertHours: 48 })[0].urgent, true);
});

test('short windows are never urgent and do not mask the weekly reset', () => {
  assert.equal(rank([provider('session', [limit('Session (5-hour)', 10, H)])])[0].status, 'unknown');
  const both = rank([provider('both', [limit('Session (5-hour)', 5, H), limit('Weekly (7-day)', 30, D)])])[0];
  assert.equal(both.urgent, true);
  assert.equal(both.window, 'Weekly (7-day)');
  assert.equal(both.sessionExhausted, false);
  const spent = rank([provider('s', [limit('5h window', 100, H), limit('Weekly (7-day)', 30, D)])])[0];
  assert.equal(spent.sessionExhausted, true);
  assert.equal(spent.status, 'priority');
});

test('the binding shared weekly window is the measure; model-scoped ones are not', () => {
  const claude = provider('claude', [
    limit('Session (5-hour)', 8, H), limit('Weekly (7-day)', 31, 23 * H), limit('Fable Weekly', 100, 23 * H, 'Fable Weekly'),
  ]);
  const row = rank([claude])[0];
  assert.equal(row.status, 'priority', 'a spent model allowance does not block the subscription');
  assert.equal(row.window, 'Weekly (7-day)');
  assert.equal(row.remainingPercent, 69);
  assert.ok(row.unusedPercent > 0 && row.unusedPercent <= 69);
  // Two shared weekly windows: the fuller one binds.
  const two = rank([provider('x', [limit('Weekly (7-day)', 10, D), limit('Weekly requests (7d)', 40, D)])])[0];
  assert.equal(two.window, 'Weekly requests (7d)');
});

test('expired windows do not mask the current quota; no weekly falls back to the longest', () => {
  const row = rank([provider('a', [limit('Session (5-hour)', 100, -MIN), limit('Weekly (7-day)', 31, 23 * H)])])[0];
  assert.equal(row.sessionExhausted, false);
  assert.equal(row.status, 'priority');
  const expiredOnly = rank([provider('a', [limit('Weekly (7-day)', 100, -MIN)])])[0];
  assert.equal(expiredOnly.status, 'unknown');
  const monthly = rank([provider('m', [limit('Session (5-hour)', 1, H), limit('Monthly', 10, 2 * D)])])[0];
  assert.equal(monthly.window, 'Monthly');
});

test('no reset is unknown; 0% is the most to lose', () => {
  assert.equal(rank([provider('a', [limit('Weekly (7-day)', 20, null)])])[0].status, 'unknown');
  const rows = rank([weekly('idle', 0), weekly('busy', 60)]);
  assert.equal(rows[0].key, 'idle');
  assert.equal(rows[0].remainingPercent, 100);
});

test('options are clamped like the reference', () => {
  for (const [input, out] of [[undefined, 3], [null, 3], ['', 3], ['bad', 3], ['6', 6], [0, 1], [25, 24], [2.7, 3]])
    assert.equal(P.normalizeHours(input), out);
  for (const [input, out] of [[undefined, 50], [0, 1], [150, 100], ['30', 30]])
    assert.equal(P.normalizeAlertPercent(input), out);
  for (const [input, out] of [[undefined, 24], [0, 1], [500, 168], ['48', 48]])
    assert.equal(P.normalizeAlertHours(input), out);
});

test('accounts rank separately', () => {
  const rec = provider('codex', [], { accounts: [
    { id: 'x', limits: [limit('Weekly (7-day)', 90, D)], fetchedAt: NOW },
    { id: 'y', limits: [limit('Weekly (7-day)', 10, D)], fetchedAt: NOW },
  ] });
  assert.deepEqual(rank([rec]).map(r => [r.key, r.account]), [['codex@y', 'y'], ['codex@x', 'x']]);
});

test('listed rows, row states and the hungry pick', () => {
  const r = rank([
    weekly('spent', 100),
    provider('nolong', [limit('Session (5-hour)', 10, H)]),
    weekly('soon', 10),
    weekly('busy', 95),
  ], [], { alertUnusedPercent: 50, alertHours: 48 });
  assert.deepEqual(P.listed(r).map(x => x.key), ['soon', 'busy', 'spent']);
  assert.deepEqual(r.map(P.state), ['urgent', 'running_out', 'unknown', 'blocked']);
  assert.equal(P.actionable(r), true);
  assert.equal(P.actionable(r.slice(1)), false, 'running out, spent or unknown recommend nothing');
  // No current numbers: the agent's own section says so, not "Use first".
  assert.deepEqual(P.listed(rank([weekly('gone', 20, { ready: false }), weekly('a', 20)])).map(x => x.key), ['a']);
  assert.equal(P.hungry(r).key, 'soon');
  // Spare quota that resets later than the alert horizon isn't urgent.
  const later = rank([weekly('soon', 10)], [], { alertHours: 12 });
  assert.equal(P.state(later[0]), 'priority');
  assert.equal(P.hungry(later), null);
  assert.equal(P.hungry([]), null);
  assert.equal(P.state(null), 'unknown');
});

test('on pace lands on the cap at the reset; running out spends it well before', () => {
  // Six days in, a day left: 86% used lands on ~100% at the reset.
  const onPace = rank([weekly('a', 86)])[0];
  assert.equal(onPace.status, 'on_track');
  assert.equal(onPace.runsOutInMs, undefined);
  // The live Claude case: about half used with 4.5 days to go at twice the
  // pace that would last; and Codex at 97% with 30 hours to go.
  const claude = rank([provider('claude', [limit('Weekly (7-day)', 52, 109 * H)])])[0];
  assert.equal(claude.status, 'running_out');
  assert.ok(claude.runsOutInMs > 0 && claude.runsOutInMs < 109 * H, String(claude.runsOutInMs));
  const codex = rank([provider('codex', [limit('Weekly (7-day)', 97, 30 * H)])])[0];
  assert.equal(codex.status, 'running_out');
  assert.ok(codex.runsOutInMs < 6 * H, String(codex.runsOutInMs));
  // The later one to run out ranks first, and both rank below on pace.
  assert.deepEqual(rank([weekly('soon', 99), weekly('pace', 86), weekly('later', 95)]).map(r => r.key), ['pace', 'later', 'soon']);
});

test('a model-only title (agy "Argon") is a model allowance, not the subscription', () => {
  const agy = provider('agy', [
    limit('Weekly (7-day)', 40, 3 * D, 'Weekly'), limit('Argon (7-day)', 100, 3 * D, 'Argon'),
  ]);
  const row = rank([agy])[0];
  assert.equal(row.status, 'priority', 'a spent Argon does not block agy');
  assert.equal(row.window, 'Weekly (7-day)');
});

test('history: a provider gaining an account hands its run to the active one', () => {
  const lone = sample(NOW - H, 20, 'claude');
  const two = provider('claude', [limit('Weekly (7-day)', 22, D)], { accounts: [
    { id: 'main', active: true, limits: [limit('Weekly (7-day)', 22, D)], fetchedAt: NOW },
    { id: 'work', limits: [limit('Weekly (7-day)', 5, D)], fetchedAt: NOW },
  ] });
  const r = P.append([lone], [two], NOW);
  assert.deepEqual(r.samples.map(s => [s.source, s.percent]), [['claude@main', 20], ['claude@main', 22], ['claude@work', 5]]);
  assert.equal(lone.source, 'claude', 'never mutated');
  // And back: one account again takes the newest account's run.
  const back = P.append(r.samples, [provider('claude', [limit('Weekly (7-day)', 23, D)], { limitsFetchedAt: NOW + 30 * MIN })], NOW + 30 * MIN);
  assert.deepEqual(back.samples.filter(s => s.source === 'claude').map(s => s.percent), [20, 22, 23]);
});
