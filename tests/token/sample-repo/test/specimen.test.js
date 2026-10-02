'use strict';
const assert = require('assert');
const { computeStabilityWindow, isWithinStability } = require('../src/specimen');

test('cfDNA window is 14 days', () => {
  const w = computeStabilityWindow('2026-03-01T08:00:00Z', 'cfDNA');
  assert.strictEqual(w.hours, 336);
});

test('unknown tube type throws', () => {
  assert.throws(() => computeStabilityWindow('2026-03-01T08:00:00Z', 'heparin'));
});

test('specimen is usable at the exact end of its window', () => {
  const s = { collectedAt: '2026-03-01T08:00:00Z', tubeType: 'serum' };
  assert.strictEqual(isWithinStability(s, '2026-03-02T08:00:00Z'), true);
});

test('specimen is not usable after its window', () => {
  const s = { collectedAt: '2026-03-01T08:00:00Z', tubeType: 'serum' };
  assert.strictEqual(isWithinStability(s, '2026-03-02T08:00:01Z'), false);
});
