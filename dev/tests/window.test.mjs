import test from 'node:test';
import assert from 'node:assert/strict';
import { usage } from './qml-js.mjs';

const W = usage('Window');
const H = W.HOUR_MS, D = W.DAY_MS;
const NOW = Date.parse('2026-11-10T12:00:00Z');
const iso = ms => new Date(ms).toISOString();

test('titles: Claude spells windows out, Codex abbreviates them', () => {
  for (const [label, title] of [
    ['Session (5-hour)', 'Session'], ['5h window', 'Session'], ['30m window', 'Session'],
    ['Weekly (7-day)', 'Weekly'], ['Monthly', 'Monthly'],
    ['Spend limit', 'Spend limit'], ['', 'Limit'], ['Requests (beta)', 'Requests'],
  ]) assert.equal(W.title(label), title, label);
});

test('durations from labels', () => {
  for (const [label, ms] of [
    ['Session (5-hour)', 5 * H], ['5h window', 5 * H], ['30m window', 30 * 60000],
    ['Weekly (7-day)', 7 * D], ['Weekly (7d)', 7 * D], ['7d window', 7 * D],
    ['Monthly', 30 * D], ['30-day window', 30 * D], ['Daily', D], ['24-hour', 24 * H],
    ['Session', 5 * H], ['Spend limit', 0], ['', 0],
  ]) assert.equal(W.durationMs(label), ms, label);
});

test('a collector title beats the label, model names never parse as spans', () => {
  assert.equal(W.durationMs('Fable Weekly', 'Fable Weekly'), 7 * D);
  assert.equal(W.durationMs('Opus 5 (1M context)', 'Opus 5 Weekly'), 7 * D);
  assert.equal(W.durationMs('Opus 5 (1M context)', 'Opus 5 Session'), 5 * H);
  assert.equal(W.durationMs('Opus (3-hour)', 'Opus Session'), 3 * H);
  assert.equal(W.durationMs('Opus 5 Monthly', 'Opus 5 Monthly'), 30 * D);
  assert.equal(W.durationMs('Opus 5 (1M context)', 'Opus 5 (1M context)'), 0);
  assert.equal(W.limitWindow('Opus 5 (1M context)', 0.2, '', 'Opus 5 Weekly', NOW).title, 'Opus 5 Weekly');
});

test('scoped titles', () => {
  assert.deepEqual(W.scopedPart('Fable Weekly'), { model: 'Fable', window: 'Weekly' });
  assert.deepEqual(W.scopedPart('Opus 5 Session'), { model: 'Opus 5', window: 'Session' });
  assert.equal(W.scopedPart('Weekly'), null);
  assert.equal(W.scopedPart(''), null);
});

test('limitWindow: an expired reset starts the window over, no reset is kept as unknown', () => {
  const live = W.limitWindow('Weekly (7-day)', 0.5, iso(NOW + D), undefined, NOW);
  assert.deepEqual(live, { label: 'Weekly (7-day)', title: 'Weekly', percent: 0.5, resetAt: iso(NOW + D), spanMs: 7 * D });
  const expired = W.limitWindow('Weekly (7-day)', 1, iso(NOW - 1), undefined, NOW);
  assert.equal(expired.percent, 0);
  assert.equal(expired.resetAt, '');
  const none = W.limitWindow('5h window', 0.3, undefined, undefined, NOW);
  assert.equal(none.percent, 0.3);
  assert.equal(none.resetAt, '');
  assert.equal(W.resetInMs(none, NOW), -1);
  assert.equal(W.resetInMs(live, NOW), D);
});

test('limitWindows keeps only real percentages, 0% and 100% included', () => {
  const out = W.limitWindows([
    { label: 'Session (5-hour)', percent: 0, resetsAt: iso(NOW + H) },
    { label: 'Weekly (7-day)', percent: 1, resetsAt: iso(NOW + D) },
    { label: 'Broken', percent: 'n/a' }, null,
    { label: 'Fable Weekly', percent: 0.13, resetsAt: iso(NOW + D), title: 'Fable Weekly' },
  ], NOW);
  assert.deepEqual(out.map(w => [w.title, w.percent]), [['Session', 0], ['Weekly', 1], ['Fable Weekly', 0.13]]);
  assert.deepEqual(W.limitWindows(undefined, NOW), []);
});

test('timeMs reads ISO strings and epoch ms', () => {
  assert.equal(W.timeMs('2026-11-15T16:00:01.003835+00:00'), Date.parse('2026-11-15T16:00:01.003Z'));
  assert.equal(W.timeMs(NOW), NOW);
  assert.ok(Number.isNaN(W.timeMs('')));
  assert.ok(Number.isNaN(W.timeMs(undefined)));
  assert.ok(Number.isNaN(W.timeMs('soon')));
  assert.ok(Number.isNaN(W.timeMs(Infinity)));
});

test('elapsed fraction, with clock skew and unknowns', () => {
  assert.equal(W.elapsedFraction(NOW + 2.5 * H, 5 * H, NOW), 0.5);
  assert.equal(W.elapsedFraction(NOW + 6 * H, 5 * H, NOW), 0, 'reset further away than the window is long');
  assert.equal(W.elapsedFraction(NOW - H, 5 * H, NOW), 1, 'past reset');
  assert.equal(W.elapsedFraction(NaN, 5 * H, NOW), -1);
  assert.equal(W.elapsedFraction(NOW + H, 0, NOW), -1);
});

test('a title naming only a model takes its length from the label (agy)', () => {
  assert.equal(W.durationMs('Argon (7-day)', 'Argon'), 7 * D);
  assert.equal(W.durationMs('Argon (5-hour)', 'Argon'), 5 * H);
  assert.equal(W.durationMs('Argon (2 days)', 'Argon'), 2 * D);
  assert.equal(W.durationMs('Argon', 'Argon'), 0);
  assert.equal(W.durationMs('Opus 5 (1M context)', 'Opus 5'), 0, 'never minutes');
  assert.equal(W.limitWindow('Argon (7-day)', 1, iso(NOW + D), 'Argon', NOW).spanMs, 7 * D);
  assert.equal(W.durationMs('Claude/GPT Weekly', 'Claude/GPT Weekly'), 7 * D);
  assert.equal(W.durationMs('Weekly (7-day)', 'Weekly'), 7 * D);
});

test('model-scoped limits: "<model> <kind>" or a title that names no kind', () => {
  for (const [label, title, scoped] of [
    ['Argon (7-day)', 'Argon', true], ['Claude/GPT Weekly', 'Claude/GPT Weekly', true],
    ['Weekly (7-day)', 'Weekly', false],
    ['Session (5-hour)', 'Session', false], ['Weekly (7-day)', undefined, false],
    ['Spend limit', undefined, false],
  ]) assert.equal(W.isModelScoped(label, title), scoped, `${label} / ${title}`);
});
