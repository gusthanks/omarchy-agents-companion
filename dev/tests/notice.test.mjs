import test from 'node:test';
import assert from 'node:assert/strict';
import { usage } from './qml-js.mjs';

const N = usage('Notice');

test('a prefixed credentials error: prefix dropped, command lifted out', () => {
  assert.deepEqual(N.build('credentials error: OpenCode Go is not signed in. Run `opencode auth login` and choose OpenCode, or set OPENCODE_GO_API_KEY.', 'error'), {
    kind: 'error', category: 'credentials',
    body: 'OpenCode Go is not signed in. Run "opencode auth login" and choose OpenCode, or set OPENCODE_GO_API_KEY.',
    command: 'opencode auth login', retry: false,
  });
});

test('categories and retries', () => {
  for (const [text, category, retry] of [
    ['HTTP error: 503 Service Unavailable', 'network', true],
    ['request timed out after 10s', 'network', true],
    ['rate limited; next attempt in 4m', 'rate_limit', true],
    ['HTTP 429 Too Many Requests', 'rate_limit', true],
    ['token expired, run `claude` to re-auth', 'credentials', false],
    ['Sign-in expired', 'credentials', false],
    ['Waiting for auth', 'credentials', false],
    ['unexpected payload', 'generic', false],
    ['Limits paused', 'generic', false],
  ]) {
    const n = N.build(text, 'error');
    assert.equal(n.category, category, text);
    assert.equal(n.retry, retry, text);
  }
  assert.equal(N.build('Cached data', 'info', 'network').retry, false, 'info never retries');
  assert.equal(N.build('  ', 'error'), null);
  assert.equal(N.build(undefined, 'error'), null);
});

test('only a cued, command-shaped run is offered, never prose or shell', () => {
  assert.equal(N.commandOf('see `the docs page` for help'), '');
  assert.equal(N.commandOf('no account id at /tmp/x; run `codex login`'), 'codex login');
  assert.equal(N.commandOf('Droid is not signed in; sign in with `droid`'), 'droid');
  assert.equal(N.commandOf('Install the binary with: omarchy pkg aur add ai-usagebar-bin'), 'omarchy pkg aur add ai-usagebar-bin');
  for (const bad of ['use `$(rm -rf ~)` now', 'Run `claude; rm -rf ~` to fix', 'Run `a | sh`', 'Run `a && b`',
    'Run `cat < /etc/shadow`', 'Run `echo \\x`', 'Run `(subshell)`', 'no command here', '', undefined])
    assert.equal(N.commandOf(bad), '', String(bad));
});

test('untrusted text: one line, no control characters, bounded', () => {
  const n = N.build('network error: down\n\u001b[31mred\u0007 ' + 'x'.repeat(1000), 'error');
  assert.doesNotMatch(n.body, /[\u0000-\u001f\u007f]/);
  assert.ok(n.body.startsWith('Down [31mred x'));
  assert.ok(n.body.length <= 400);
});

test('a record status with its help line', () => {
  assert.deepEqual(N.fromStatus('Sign-in expired', 'Run `claude auth login` to restore authoritative usage.'), {
    kind: 'error', category: 'credentials',
    body: 'Sign-in expired. Run "claude auth login" to restore authoritative usage.',
    command: 'claude auth login', retry: false,
  });
  // A generic status takes its category from the help.
  const n = N.fromStatus('Claude limits unavailable', 'HTTP error: 503');
  assert.equal(n.category, 'network');
  assert.equal(n.retry, true);
  assert.equal(N.fromStatus('', 'Run `codex login` to authenticate.').command, 'codex login');
  assert.equal(N.fromStatus('', ''), null);
  assert.equal(N.fromStatus('Limits paused', '').body, 'Limits paused');
});
