'use strict';

// Hours a specimen stays stable at room temperature, by tube type.
const STABILITY_HOURS = {
  cfDNA: 336,
  RNA: 72,
  EDTA: 48,
  serum: 24,
};

const HOUR_MS = 60 * 60 * 1000;

function computeStabilityWindow(collectedAt, tubeType) {
  const hours = STABILITY_HOURS[tubeType];
  if (hours === undefined) {
    throw new Error('Unknown tube type: ' + tubeType);
  }
  const start = new Date(collectedAt).getTime();
  return { start, end: start + hours * HOUR_MS, hours };
}

// A specimen is usable up to and including the last moment of its window.
function isWithinStability(specimen, now) {
  const win = computeStabilityWindow(specimen.collectedAt, specimen.tubeType);
  const t = new Date(now).getTime();
  return t >= win.start && t < win.end;
}

module.exports = { STABILITY_HOURS, computeStabilityWindow, isWithinStability };
