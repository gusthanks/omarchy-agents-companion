// Loads a QML ".pragma library" JavaScript file in Node, the way QML would:
// its ".import" lines become the named libraries, and every top-level
// function and var is exported. It runs in this realm, so the objects it
// returns compare with assert.deepStrictEqual as they are.
import fs from 'node:fs';
import path from 'node:path';

const cache = new Map();

export function load(file) {
  const full = path.resolve(file);
  if (cache.has(full)) return cache.get(full);
  const source = fs.readFileSync(full, 'utf8');
  const imports = {};
  const body = source.split('\n').map(line => {
    if (/^\s*\.pragma\s+library\s*$/.test(line)) return '';
    const m = line.match(/^\s*\.import\s+"([^"]+\.js)"\s+as\s+(\w+)\s*$/);
    if (m) { imports[m[2]] = load(path.join(path.dirname(full), m[1])); return ''; }
    if (/^\s*\./.test(line)) throw new Error(`${file}: unsupported directive: ${line}`);
    return line;
  }).join('\n');
  const names = [...source.matchAll(/^(?:function\s+(\w+)|var\s+(\w+))/gm)].map(m => m[1] || m[2]);
  const factory = new Function(...Object.keys(imports),
    `"use strict";\n${body}\nreturn { ${names.join(', ')} };`);
  const lib = Object.freeze(factory(...Object.values(imports)));
  cache.set(full, lib);
  return lib;
}

export const repo = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
export const usage = name => load(path.join(repo, 'usage', `${name}.js`));
