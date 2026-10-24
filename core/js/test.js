#!/usr/bin/env node
/* Conformance runner: node core/js/test.js  (exit code 1 on any failure) */
'use strict';
const path = require('path');
const fs = require('fs');
const U = require('./uztranslit.js');

const fixtures = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'spec', 'fixtures.json'), 'utf8'));
let pass = 0, fail = 0;
const show = s => JSON.stringify(s);

function check(id, got, want, extra) {
  if (got === want) { pass++; return; }
  fail++;
  console.log(`FAIL ${id}${extra ? ' ' + extra : ''}\n   want ${show(want)}\n   got  ${show(got)}`);
}

for (const c of fixtures.cases) check(c.id, U.convert(c.in, c.from, c.to), c.out, `${c.from}->${c.to} ${show(c.in)}`);

for (const r of fixtures.roundtrips) {
  const there = U.convert(r.in, r.from, r.via);
  const back = U.convert(there, r.via, r.from);
  check(r.id, back, r.in, `${r.from}->${r.via}->${r.from} via ${show(there)}`);
}

for (const d of fixtures.detect) check('detect ' + show(d.in), U.detect(d.in), d.expect);

for (const o of fixtures.optional) {
  const options = o.feature === 'asciiApostrophe' ? { okina: "'", tutuq: "'" } : { skipUrls: true };
  check('optional/' + o.feature, U.convert(o.in, o.from, o.to, options), o.out);
}

console.log(`${pass} passed, ${fail} failed (uztranslit.js v${U.VERSION})`);
process.exit(fail ? 1 : 0);
