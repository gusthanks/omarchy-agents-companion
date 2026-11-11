import test from 'node:test';
import assert from 'node:assert/strict';
import { usage } from './qml-js.mjs';

const D = usage('Display');
const P = usage('Pacing');
const W = usage('Window');
const H = W.HOUR_MS, DAY = W.DAY_MS;
const NOW = Date.parse('2026-05-23T12:00:00Z');
const iso = ms => new Date(ms).toISOString();
// A window with `elapsed` (0..1) of its span gone by.
const win = (title, percent, elapsed, span = W.WEEK_MS) =>
  ({ title, percent, resetAt: iso(NOW + (1 - elapsed) * span), spanMs: span });

test('settings: flags, readings and mood windows, unknown values fall back', () => {
  assert.equal(D.flag(true, false), true);
  assert.equal(D.flag('off', true), false);
  assert.equal(D.flag(' On ', false), true);
  assert.equal(D.flag(undefined, true), true);
  assert.equal(D.flag('maybe', false), false);
  assert.equal(D.normalizeShowAs('left'), 'left');
  assert.equal(D.normalizeShowAs('Remaining'), 'left');
  assert.equal(D.normalizeShowAs(undefined), 'used');
  assert.equal(D.normalizeShowAs('sideways'), 'used');
  assert.equal(D.normalizeMoodWindow('7d'), 'weekly');
  assert.equal(D.normalizeMoodWindow('Session'), 'session');
  assert.equal(D.normalizeMoodWindow(''), 'auto');
  assert.equal(D.normalizeMoodWindow('monthly'), 'auto');
});

test('the shown share is used or left, clamped', () => {
  assert.equal(D.shownFraction(0.74, 'used'), 0.74);
  assert.ok(Math.abs(D.shownFraction(0.74, 'left') - 0.26) < 1e-9);
  assert.equal(D.shownFraction(1.3, 'left'), 0);
  assert.equal(D.shownFraction(-1, 'used'), 0);
});

test('color rungs match severity_for, critical exactly at the alarm', () => {
  assert.deepEqual([0, 0.49, 0.5, 0.74, 0.75, 0.899, 0.9, 1].map(D.level),
    ['low', 'low', 'mid', 'mid', 'high', 'high', 'critical', 'critical']);
});

test('pace glyphs follow the ratio pace, and say nothing early or unknown', () => {
  const span = 5 * H;
  assert.equal(D.paceGlyph(P.calc(0.7, NOW + span / 2, span, NOW)), '↑');
  assert.equal(D.paceGlyph(P.calc(0.3, NOW + span / 2, span, NOW)), '↓');
  assert.equal(D.paceGlyph(P.calc(0.52, NOW + span / 2, span, NOW)), '→', 'inside the band');
  assert.equal(D.paceGlyph(P.calc(0.52, NOW + span / 2, span, NOW), true), '←', 'mirrored');
  assert.equal(D.paceGlyph(P.calc(0.3, NOW + span * 0.98, span, NOW)), '', 'early');
  assert.equal(D.paceGlyph(P.calc(0.3, '', span, NOW)), '', 'no reset');
  assert.equal(D.paceGlyph(null), '');
});

test('window kinds, scoped windows on their own clock', () => {
  assert.equal(D.kindOf('Session'), 'session');
  assert.equal(D.kindOf('Weekly'), 'weekly');
  assert.equal(D.kindOf('Fable Weekly'), 'weekly');
  assert.equal(D.kindOf('Monthly'), 'monthly');
  assert.equal(D.kindOf('Spend limit'), '');
});

test('mood windows pick the kind, or keep everything when a provider lacks it', () => {
  const session = win('Session', 0.2, 0.5, 5 * H);
  const weekly = win('Weekly', 0.97, 0.5);
  const fable = win('Fable Weekly', 0.4, 0.5);
  const all = [session, weekly, fable];
  assert.deepEqual(D.moodWindows(all, 'auto'), all);
  assert.deepEqual(D.moodWindows(all, 'session'), [session]);
  assert.deepEqual(D.moodWindows(all, 'weekly'), [weekly, fable]);
  const monthly = [win('Monthly', 0.5, 0.5, W.MONTH_MS)];
  assert.deepEqual(D.moodWindows(monthly, 'weekly'), monthly);
  assert.equal(D.fullest(all), weekly);
  assert.equal(D.fullest(D.moodWindows(all, 'session')), session);
  assert.equal(D.fullest([]), null);
});

test('panting needs a clear lead, enough used, and room before the cap', () => {
  const pace = (percent, elapsed) => P.forWindow(win('Weekly', percent, elapsed), NOW);
  assert.equal(D.panting(pace(0.5, 0.3), 0.5), true, '20 points ahead at 50%');
  assert.equal(D.panting(pace(0.44, 0.3), 0.44), false, '14 points is not enough');
  assert.equal(D.panting(pace(0.45, 0.3), 0.45), true, '15 points is');
  assert.equal(D.panting(pace(0.19, 0.02), 0.19), false, 'early, and under 20% used');
  assert.equal(D.panting(pace(0.25, 0.09), 0.25), true, 'just past the early guard');
  assert.equal(D.panting(pace(0.9, 0.5), 0.9), false, 'near the cap is worried, not panting');
  assert.equal(D.panting(pace(0.3, 0.5), 0.3), false, 'under pace');
  assert.equal(D.panting(P.neutral(80), 0.8), false, 'unknown pace');
});

test('the most pressing window is the one that runs out first', () => {
  const slowWeek = { provider: 'Claude', window: win('Weekly', 0.5, 0.3) };
  const fastSession = { provider: 'Codex', window: win('Session', 0.6, 0.3, 5 * H) };
  const calm = { provider: 'Kimi', window: win('Weekly', 0.2, 0.5) };
  const near = { provider: 'Grok', window: win('Weekly', 0.95, 0.5) };
  const best = D.hurried([slowWeek, calm, fastSession, near], NOW);
  assert.equal(best.provider, 'Codex');
  assert.equal(best.window, fastSession.window);
  assert.ok(best.pace.hitsInMs > 0 && best.pace.hitsInMs < 5 * H);
  const week = D.hurried([slowWeek, calm], NOW);
  assert.equal(week.provider, 'Claude');
  // 50% in 30% of a week: the rest goes in 0.5 / (0.5 / 2.1 days) = 2.1 days.
  assert.ok(Math.abs(week.pace.hitsInMs - 2.1 * DAY) < 60000);
  assert.equal(D.hurried([calm, near], NOW), null);
  assert.equal(D.hurried([], NOW), null);
});
