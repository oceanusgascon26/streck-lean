'use strict';
// T5 check. Run with cwd = the task work dir. Exits non-zero on failure.
const assert = require('assert');
const path = require('path');
const { isWithinStability } = require(path.join(process.cwd(), 'src', 'specimen.js'));

const s = { collectedAt: '2026-03-01T08:00:00Z', tubeType: 'EDTA' };
assert.strictEqual(isWithinStability(s, '2026-03-01T07:59:59Z'), false, 'before collection');
assert.strictEqual(isWithinStability(s, '2026-03-01T08:00:00Z'), true, 'at collection');
assert.strictEqual(isWithinStability(s, '2026-03-03T08:00:00Z'), true, 'exact end');
assert.strictEqual(isWithinStability(s, '2026-03-03T08:00:01Z'), false, 'after end');
console.log('stability-boundary ok');
