import test from 'node:test';
import assert from 'node:assert/strict';
import { usage } from './qml-js.mjs';

const P = usage('Pacing');
const W = usage('Window');
const H = W.HOUR_MS, D = W.DAY_MS, M = 60000;
const NOW = Date.parse('2026-05-23T12:00:00Z');
const FIVE_H = 5 * H;
const iso = ms => new Date(ms).toISOString();

test('no reset, no length, or an expired reset: neutral', () => {
  for (const p of [P.calc(0.5, undefined, FIVE_H, NOW), P.calc(0.5, '', FIVE_H, NOW),
    P.calc(0.5, iso(NOW + H), 0, NOW), P.calc(0.5, iso(NOW - H), FIVE_H, NOW), P.calc(0.5, iso(NOW), FIVE_H, NOW)]) {
    assert.equal(p.known, false);
    assert.equal(p.delta, 0);
    assert.equal(p.ratioPace, 'on_track');
    assert.equal(p.projection, 'none');
    assert.equal(p.usedPct, 50);
  }
});

test('even pace is on track both ways', () => {
  const p = P.calc(0.5, NOW + 150 * M, FIVE_H, NOW);
  assert.equal(p.elapsedPct, 50);
  assert.equal(p.delta, 0);
  assert.equal(p.ratioPace, 'on_track');
  assert.equal(p.pointPace, 'on_track');
  assert.equal(p.projection, 'hits');
  assert.equal(p.hitsInMs, 150 * M, 'exactly at the reset');
});

test('ahead and under, past the tolerance', () => {
  const ahead = P.calc(0.7, NOW + 150 * M, FIVE_H, NOW);
  assert.deepEqual([ahead.delta, ahead.pointPace, ahead.ratioPace, ahead.ratioPct], [20, 'ahead', 'ahead', 40]);
  const under = P.calc(0.3, NOW + 150 * M, FIVE_H, NOW);
  assert.deepEqual([under.delta, under.pointPace, under.ratioPace, under.ratioPct], [-20, 'under', 'under', 40]);
});

test('inside the tolerance band the ratio is on track while the points diverge', () => {
  const p = P.calc(0.52, NOW + 150 * M, FIVE_H, NOW);
  assert.equal(p.ratioPace, 'on_track');
  assert.equal(p.pointPace, 'ahead');
  assert.equal(p.delta, 2);
  assert.equal(P.calc(0.52, NOW + 150 * M, FIVE_H, NOW, 1).ratioPace, 'ahead', 'a tighter band');
});

test('the ratio caps at 999%', () => {
  // 99% used a tenth of the way in: 990% of the pace, 890% ahead.
  const p = P.calc(0.99, NOW + 0.9 * 7 * D, 7 * D, NOW, 5, 0);
  assert.equal(p.elapsedPct, 10);
  assert.equal(p.ratioPct, 890);
  const capped = P.calc(0.6, NOW + 297 * M, FIVE_H, NOW, 5, 0);
  assert.equal(capped.elapsedPct, 1);
  assert.equal(capped.ratioPct, 999);
});

test('tiny elapsed: the ratio and the projection are noise, the points are not', () => {
  const p = P.calc(0.2, NOW + 297 * M, FIVE_H, NOW);
  assert.equal(p.known, true);
  assert.equal(p.early, true);
  assert.equal(p.ratioPace, 'on_track');
  assert.equal(p.projection, 'none');
  assert.equal(p.delta, 19);
  assert.equal(p.pointPace, 'ahead');
  const start = P.calc(0.2, NOW + FIVE_H, FIVE_H, NOW, 5, 0);
  assert.equal(start.elapsedPct, 0);
  assert.equal(start.early, true, 'nothing gone by is always early');
});

test('clock skew: a reset further away than the window is long is the very start', () => {
  const p = P.calc(0.1, NOW + 6 * H, FIVE_H, NOW);
  assert.equal(p.elapsedPct, 0);
  assert.equal(p.early, true);
  assert.equal(p.delta, 10);
});

test('projection: hits the limit before the reset, or some left at it', () => {
  // A week, 2 days gone, 40% used: 20%/day, 100% after 5 days, 2 days before the reset.
  const hits = P.calc(0.4, NOW + 5 * D, 7 * D, NOW);
  assert.equal(hits.projection, 'hits');
  assert.equal(hits.hitsInMs, 3 * D);
  assert.equal(hits.leftPct, -1);
  // Half the week gone, 20% used: 40% at the reset, 60% left.
  const left = P.calc(0.2, NOW + 3.5 * D, 7 * D, NOW);
  assert.equal(left.projection, 'left');
  assert.equal(left.leftPct, 60);
  assert.equal(left.hitsInMs, -1);
});

test('0% and 100%', () => {
  const idle = P.calc(0, NOW + 3.5 * D, 7 * D, NOW);
  assert.deepEqual([idle.projection, idle.leftPct, idle.ratioPace, idle.ratioPct], ['left', 100, 'under', 100]);
  const spent = P.calc(1, NOW + 3.5 * D, 7 * D, NOW);
  assert.deepEqual([spent.projection, spent.usedPct, spent.delta, spent.hitsInMs], ['maxed', 100, 50, -1]);
});

test('forWindow reads a limitWindow, model-scoped ones on their own clock', () => {
  const w = W.limitWindow('Opus 5 (1M context)', 0.2, iso(NOW + 3.5 * D), 'Opus 5 Weekly', NOW);
  const p = P.forWindow(w, NOW);
  assert.equal(p.elapsedPct, 50);
  assert.equal(p.leftPct, 60);
  assert.equal(P.forWindow(null, NOW).known, false);
  const unknown = W.limitWindow('Spend limit', 0.5, iso(NOW + D), undefined, NOW);
  assert.equal(P.forWindow(unknown, NOW).known, false, 'no window length');
});

test('severity bands follow claudebar', () => {
  for (const [delta, band] of [[-100, 'low'], [-11, 'low'], [-10, 'mid'], [0, 'mid'], [1, 'high'], [9, 'high'], [10, 'critical']])
    assert.equal(P.severity(delta), band, String(delta));
});
