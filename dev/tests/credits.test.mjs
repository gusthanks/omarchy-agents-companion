import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { repo } from './qml-js.mjs';

// The MIT notice travels with the ported logic: in each file, and in both READMEs.
test('ported files and the READMEs credit ai-usagebar', () => {
  const dir = path.join(repo, 'usage');
  const ported = fs.readdirSync(dir).filter(f => f.endsWith('.js'))
    .filter(f => /ai-usagebar/.test(fs.readFileSync(path.join(dir, f), 'utf8')));
  assert.deepEqual(ported.sort(), ['Display.js', 'Notice.js', 'Notify.js', 'Pacing.js', 'Priority.js']);
  for (const f of ported)
    assert.match(fs.readFileSync(path.join(dir, f), 'utf8').split('\n')[1],
      /^\/\/ Ported from ai-usagebar \(MIT, \(c\) 2026 AkitaOnRails\): \S+$/, f);
  for (const readme of ['README.md', 'README.pt-BR.md'])
    assert.match(fs.readFileSync(path.join(repo, readme), 'utf8'), /ai-usagebar\]\(https:\/\/github\.com\/akitaonrails\/ai-usagebar\)[^\n]*MIT/, readme);
});
