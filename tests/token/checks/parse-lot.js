'use strict';
// T6 check. Run with cwd = the task work dir. Exits non-zero on failure.
const assert = require('assert');
const path = require('path');
const label = require(path.join(process.cwd(), 'src', 'label.js'));

assert.strictEqual(typeof label.parseLot, 'function', 'parseLot exported');
assert.deepStrictEqual(label.parseLot('LOT-2026-00042'), { year: 2026, seq: 42 });
assert.deepStrictEqual(label.parseLot('LOT-1999-12345'), { year: 1999, seq: 12345 });
for (const bad of ['', 'LOT-2026-42', 'LOT-26-00042', 'lot-2026-00042x', 'XYZ', null, undefined]) {
  assert.strictEqual(label.parseLot(bad), null, 'null for ' + JSON.stringify(bad));
}
// Existing behavior still intact.
assert.strictEqual(typeof label.formatLabel, 'function');
console.log('parse-lot ok');
