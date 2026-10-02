'use strict';
const assert = require('assert');
const { fmtLot, formatLabel } = require('../src/label');

test('lot number is zero padded', () => {
  assert.strictEqual(fmtLot(2026, 42), 'LOT-2026-00042');
});

test('label has lot, tube, and expiry', () => {
  const s = { collectedAt: '2026-03-01T08:00:00Z', tubeType: 'EDTA', lotYear: 2026, lotSeq: 7 };
  assert.strictEqual(formatLabel(s), 'LOT-2026-00007 | EDTA | EXP 2026-03-03 08:00');
});
