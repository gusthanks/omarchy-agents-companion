import test from 'node:test';
import assert from 'node:assert/strict';
import { usage } from './qml-js.mjs';

const M = usage('Mood');
const P = usage('Priority');
const H = 3600000, D = 24 * H, MIN = 60000;
const NOW = Date.parse('2026-11-11T12:00:00Z');
const iso = ms => new Date(ms).toISOString();

const weekly = (percent, reset = NOW + 3 * D) => ({ label: 'Weekly (7-day)', percent: percent / 100, resetsAt: iso(reset) });
const session = (percent, reset = NOW + 3 * H) => ({ label: 'Session (5-hour)', percent: percent / 100, resetsAt: iso(reset) });
const provider = (id, limits, at, extra) => Object.assign(
  { providerId: id, providerName: id, limits, limitsStale: false, limitsFetchedAt: at }, extra);

// A running panel: every step is one fresh fetch of every provider 15 minutes
// later, recorded in the history and then decided, the way PetMood.qml does.
function sim(start = NOW, state = { since: start - D, seen: {}, keys: {}, balances: {} }) {
  const s = { now: start, samples: [], state, last: null };
  s.step = (make, minutes = 15) => {
    s.now += minutes * MIN;
    const records = make(s.now);
    s.samples = P.append(s.samples, records, s.now).samples;
    s.last = M.decide(records, s.samples, s.state, s.now, { moodWindow: 'auto' });
    s.state = s.last.state;
    return s.last;
  };
  // Time passing without a new reading (the expiry timer firing).
  s.tick = (records, minutes) => {
    s.now += minutes * MIN;
    s.last = M.decide(records, s.samples, s.state, s.now, { moodWindow: 'auto' });
    s.state = s.last.state;
    return s.last;
  };
  return s;
}

test("the user's real snapshot: a full subscription nobody is spending doesn't worry him", () => {
  // codex Weekly 97% and agy Weekly 94% sit still (agy's reading is a stale
  // cache); Claude, at 54%, is the one being spent.
  const claudeSession = [2, 3, 3, 3, 3, 6];
  const s = sim();
  let r;
  for (let i = 0; i < claudeSession.length; i++) {
    r = s.step(now => [
      provider('claude', [session(claudeSession[i]), weekly(54), { label: 'Fable Weekly', percent: 0.13, resetsAt: iso(NOW + 4 * D) }], now),
      provider('codex', [{ label: '5h window', percent: 0, resetsAt: iso(now + 5 * H) }, weekly(97, NOW + D)], now),
      provider('agy', [{ label: 'Weekly (7-day)', title: 'Weekly', percent: 0.9427, resetsAt: iso(NOW + 2 * D) },
        { label: 'Argon (7-day)', title: 'Argon', percent: 1, resetsAt: iso(NOW + 2 * D) }], NOW - 18 * H, { limitsStale: true }),
    ]);
  }
  assert.equal(r.worried, false);
  assert.equal(r.cornered, false);
  assert.equal(r.tired, false);
  assert.deepEqual(r.worriedAbout, []);
  // Nothing recorded for them either: the first time codex is spent from
  // again, that is news.
  assert.equal(r.state.keys['codex::Weekly (7-day)'], undefined);
  assert.equal(M.mood({ worried: r.worried, panting: false, hungry: true }), 'hungry');
});

test('an in-use source crossing 90% worries him for ten minutes, then he calms down', () => {
  const s = sim();
  const recs = pct => now => [provider('claude', [session(40), weekly(pct)], now), provider('codex', [weekly(20)], now)];
  assert.equal(s.step(recs(86)).worried, false);
  assert.equal(s.step(recs(88)).worried, false);
  const r = s.step(recs(91));
  assert.equal(r.worried, true);
  assert.deepEqual(r.worriedAbout, ['claude::Weekly (7-day)']);
  assert.equal(r.until, s.now + M.WORRY_MS);
  assert.equal(r.cornered, false);
  assert.equal(M.mood({ worried: r.worried, panting: true, hungry: true }), 'worried');
  // Still worried a few minutes in, calm once the ten minutes are up, with
  // or without a new reading.
  assert.equal(s.tick(recs(91)(s.now), 5).worried, true);
  const calm = s.tick(recs(91)(s.now - 5 * MIN), 6);
  assert.equal(calm.worried, false);
  assert.equal(calm.until, 0);
  assert.equal(M.mood({ worried: calm.worried, panting: true }), 'panting');
  // Still climbing: no new worry, the crossing was the news.
  assert.equal(s.step(recs(95)).worried, false);
  assert.equal(s.step(recs(99)).worried, false);
});

test('the same window does not worry him again until it drops below 83% or starts over', () => {
  const s = sim();
  const recs = pct => now => [provider('codex', [weekly(pct)], now), provider('claude', [weekly(10)], now)];
  s.step(recs(80));
  assert.equal(s.step(recs(92)).worried, true);
  s.tick(recs(92)(s.now), 11);
  // Hovering around the line is not news.
  for (const pct of [89, 90, 85, 91, 84, 93]) assert.equal(s.step(recs(pct)).worried, false, String(pct));
  // Below 83 re-arms it.
  s.step(recs(82));
  assert.equal(s.state.keys['codex::Weekly (7-day)'], undefined);
  assert.equal(s.step(recs(91)).worried, true, 'a new crossing');
});

test('a window that starts over re-arms', () => {
  const s = sim();
  const recs = (pct, reset) => now => [provider('codex', [weekly(pct, reset)], now), provider('claude', [weekly(10)], now)];
  s.step(recs(85));
  assert.equal(s.step(recs(95)).worried, true);
  s.tick(recs(95)(s.now), 11);
  // Jitter and a reset nudged a little later are the same window.
  assert.equal(s.step(recs(96, NOW + 3 * D + 700)).worried, false);
  assert.equal(s.step(recs(97, NOW + 3 * D + 60 * MIN)).worried, false);
  // A new week reported straight away at 98% (rare, but a new window).
  assert.equal(s.step(recs(98, NOW + 10 * D)).worried, true, 'the reset moved a week');
  // An expired reset reads as 0%, which re-arms.
  const t = sim();
  t.step(recs(85, NOW + 2 * H));
  assert.equal(t.step(recs(95, NOW + 2 * H)).worried, true);
  t.step(recs(95, NOW + 2 * H), 120);
  assert.equal(t.state.keys['codex::Weekly (7-day)'], undefined, 'expired window');
});

test('every subscription close: worried for as long as it lasts; every one maxed: tired', () => {
  const s = sim();
  const tight = now => [provider('codex', [weekly(97)], now), provider('claude', [session(10), weekly(92)], now)];
  let r = s.step(tight);
  assert.equal(r.cornered, true);
  assert.equal(r.worried, true);
  // No history needed, and no ten-minute limit.
  r = s.tick(tight(s.now), 180);
  assert.equal(r.worried, true);
  assert.equal(M.mood({ tired: r.tired, worried: r.worried }), 'worried');
  // One with room left is somewhere to go.
  r = s.step(now => [provider('codex', [weekly(97)], now), provider('claude', [weekly(60)], now)]);
  assert.equal(r.cornered, false);
  // A model's own maxed allowance makes a source maxed, as the cap reactions do.
  r = s.step(now => [provider('codex', [weekly(100)], now), provider('agy', [weekly(80), { label: 'Argon (7-day)', title: 'Argon', percent: 1, resetsAt: iso(NOW + D) }], now)]);
  assert.equal(r.tired, true);
  assert.equal(M.mood({ tired: r.tired, worried: r.worried, panting: true, hungry: true }), 'tired');
  // A source without limits (a prepaid one) is neither room nor a cap.
  r = s.step(now => [provider('codex', [weekly(100)], now), provider('deepseek', [], 0, { balance: { remaining: 5, funded: 10 } })]);
  assert.equal(r.tired, true);
  assert.equal(M.decide([], [], null, NOW, {}).tired, false, 'nothing at all is not tired');
});

test('no history: a close subscription he cannot see being spent leaves him calm', () => {
  const r = M.decide([provider('codex', [weekly(95)], NOW - 5 * MIN), provider('claude', [weekly(30)], NOW - 5 * MIN)],
    [], { since: NOW - D, seen: {}, keys: {}, balances: {} }, NOW, {});
  assert.equal(r.worried, false);
  assert.deepEqual(r.state.keys, {}, 'still armed');
  // The mood window picks which windows count: a full session isn't news
  // with the mood on the weekly ones.
  const s = sim();
  const recs = pct => now => [provider('codex', [session(pct), weekly(40)], now), provider('claude', [weekly(30)], now)];
  s.step(recs(80));
  s.samples = P.append(s.samples, recs(95)(s.now + 15 * MIN), s.now + 15 * MIN).samples;
  const weeklyOnly = M.decide(recs(95)(s.now + 15 * MIN), s.samples, s.state, s.now + 15 * MIN, { moodWindow: 'weekly' });
  assert.equal(weeklyOnly.worried, false);
  const auto = M.decide(recs(95)(s.now + 15 * MIN), s.samples, s.state, s.now + 15 * MIN, { moodWindow: 'auto' });
  assert.equal(auto.worried, true);
});

test('in use: a rise within two hours, in any window of the source', () => {
  const at = h => NOW - h * H;
  const sample = (window, hoursAgo, percent) => ({ source: 'codex', window, at: at(hoursAgo), reset: NOW + D, percent });
  // The weekly share sits at 97 but the session moved: in use.
  assert.equal(M.inUse([sample('Weekly', 1, 97), sample('5h', 1, 2), sample('Weekly', 0.5, 97), sample('5h', 0.5, 6)], 'codex', NOW, [], 0), true);
  // The last rise was three hours ago: not any more.
  assert.equal(M.inUse([sample('Weekly', 4, 90), sample('Weekly', 3, 95), sample('Weekly', 1, 95)], 'codex', NOW, [], 0), false);
  // A drop (a reset) is not use; a wobble under half a point neither.
  assert.equal(M.inUse([sample('Weekly', 1, 95), sample('Weekly', 0.5, 3)], 'codex', NOW, [], 0), false);
  assert.equal(M.inUse([sample('Weekly', 1, 94.27), sample('Weekly', 0.5, 94.6)], 'codex', NOW, [], 0), false);
  // The current reading counts against the last one kept, once it's newer.
  assert.equal(M.inUse([sample('Weekly', 1, 95)], 'codex', NOW, [{ window: 'Weekly', percent: 96 }], NOW - MIN), true);
  assert.equal(M.inUse([sample('Weekly', 1, 95)], 'codex', NOW, [{ window: 'Weekly', percent: 96 }], 0), false);
  // Another source's readings are not this one's.
  assert.equal(M.inUse([sample('Weekly', 1, 50), sample('Weekly', 0.5, 60)], 'claude', NOW, [], 0), false);
});

test('a stale reading is not use', () => {
  const s = sim();
  s.step(now => [provider('agy', [weekly(85)], now), provider('claude', [weekly(10)], now)]);
  const r = s.step(now => [provider('agy', [weekly(95)], now - 15 * MIN, { limitsStale: true }), provider('claude', [weekly(10)], now)]);
  assert.equal(r.worried, false);
});

test('an account switch carries what he already worried about', () => {
  const s = sim();
  const one = pct => now => [provider('claude', [weekly(pct)], now), provider('codex', [weekly(10)], now)];
  s.step(one(85));
  assert.equal(s.step(one(93)).worried, true);
  s.tick(one(93)(s.now), 11);
  // A second account joins: the lone readings were the active account's.
  const two = (a, b) => now => [{
    providerId: 'claude', providerName: 'Claude', limits: [weekly(a)], limitsStale: false, limitsFetchedAt: now,
    accounts: [
      { id: 'work', label: 'Work', active: true, limits: [weekly(a)], fetchedAt: now },
      { id: 'home', label: 'Home', active: false, limits: [weekly(b)], fetchedAt: now },
    ],
  }, provider('codex', [weekly(10)], now)];
  let r = s.step(two(94, 20));
  assert.equal(r.worried, false, 'the same crossing, under its new key');
  assert.ok(r.state.keys['claude@work::Weekly (7-day)']);
  assert.equal(r.state.keys['claude::Weekly (7-day)'], undefined);
  // The other account crossing on its own is news, once it is being spent.
  s.step(two(94, 85));
  r = s.step(two(94, 91));
  assert.deepEqual(r.worriedAbout, ['claude@home::Weekly (7-day)']);
  // One account with room is somewhere to go.
  assert.equal(r.cornered, false);
});

test('a missing or corrupt state starts over quietly', () => {
  for (const text of ['', 'not json', '{"keys":[]}', '[]', '{"since":"x","seen":{},"keys":{}}', 'null'])
    assert.equal(M.parseState(text), null, JSON.stringify(text));
  const ok = M.parseState(M.serialize({ since: NOW, seen: { codex: NOW }, keys: {}, balances: {} }));
  assert.deepEqual(ok, { since: NOW, seen: { codex: NOW }, keys: {}, balances: {} });
  // Lost state while codex is being spent at 95%: no worry, and recorded as
  // worried about, so the next reading isn't news either.
  const s = sim(NOW, null);
  s.samples = [{ source: 'codex', window: 'Weekly (7-day)', at: NOW - 30 * MIN, reset: NOW + 3 * D, percent: 93 }];
  const recs = pct => now => [provider('codex', [weekly(pct)], now), provider('claude', [weekly(10)], now)];
  let r = M.decide(recs(95)(NOW - 10 * MIN), s.samples, null, NOW, {});
  assert.equal(r.worried, false);
  assert.equal(r.state.since, NOW);
  assert.deepEqual(r.state.keys['codex::Weekly (7-day)'], { noted: NOW, worriedAt: 0, reset: NOW + 3 * D });
  s.state = r.state;
  assert.equal(s.step(recs(96)).worried, false);
  // A reading from before the state existed, first seen after (the records
  // arrive one file at a time), is old news too.
  s.state = M.decide(recs(10)(NOW), [], null, NOW, {}).state;
  r = M.decide([provider('claude', [weekly(10)], NOW), provider('agy', [weekly(96)], NOW - 20 * MIN)],
    [{ source: 'agy', window: 'Weekly (7-day)', at: NOW - 40 * MIN, reset: NOW + 3 * D, percent: 90 }], s.state, NOW + MIN, {});
  assert.equal(r.worried, false);
});

test('a restart in the middle of a worry keeps the rest of it, and nothing more', () => {
  const s = sim();
  const recs = pct => now => [provider('codex', [weekly(pct)], now), provider('claude', [weekly(10)], now)];
  s.step(recs(85));
  const r = s.step(recs(92));
  const saved = M.parseState(M.serialize(r.state));
  assert.equal(M.decide(recs(92)(s.now), s.samples, saved, s.now + 4 * MIN, {}).worried, true);
  assert.equal(M.decide(recs(92)(s.now), s.samples, saved, s.now + 11 * MIN, {}).worried, false);
});

test('a prepaid balance spent down to its last 10% worries him once, for a while', () => {
  const s = sim();
  const recs = remaining => now => [provider('claude', [weekly(10)], now),
    { providerId: 'deepseek', providerName: 'DeepSeek', limits: [], balance: { remaining, funded: 10 } }];
  // First seen already low: not news (nothing seen being spent).
  assert.equal(s.step(recs(0.8)).worried, false);
  // Spent further: armed all along, and now in use, so it is news.
  assert.equal(s.step(recs(0.7)).worried, true);
  s.tick(recs(0.7)(s.now), 11);
  assert.equal(s.step(recs(0.5)).worried, false, 'once');
  // A top-up re-arms it, and spending down again is news.
  s.step(recs(5));
  s.step(recs(1.2));
  assert.equal(s.step(recs(0.9)).worried, true);
  // A balance nobody is spending stays quiet.
  const t = sim();
  t.step(recs(2));
  t.step(recs(0.5));
  t.tick(recs(0.5)(t.now), 11);
  for (let i = 0; i < 10; i++) t.step(recs(0.5));
  assert.equal(t.last.worried, false);
});

test('a key for a window no longer reported is kept a while, then dropped', () => {
  const s = sim();
  const recs = pct => now => [provider('codex', [weekly(pct)], now), provider('claude', [weekly(10)], now)];
  s.step(recs(85));
  s.step(recs(92));
  const gone = now => [provider('claude', [weekly(10)], now)];
  s.step(gone);
  assert.ok(s.state.keys['codex::Weekly (7-day)']);
  s.step(gone, 36 * 24 * 60);
  assert.equal(s.state.keys['codex::Weekly (7-day)'], undefined);
});
