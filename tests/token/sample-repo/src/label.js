'use strict';
const { computeStabilityWindow } = require('./specimen');

// Lot numbers print as LOT-YYYY-NNNNN.
function fmtLot(year, seq) {
  return 'LOT-' + year + '-' + String(seq).padStart(5, '0');
}

function formatLabel(specimen) {
  const win = computeStabilityWindow(specimen.collectedAt, specimen.tubeType);
  const lot = fmtLot(specimen.lotYear, specimen.lotSeq);
  const expires = new Date(win.end).toISOString().slice(0, 16).replace('T', ' ');
  return [lot, specimen.tubeType, 'EXP ' + expires].join(' | ');
}

module.exports = { fmtLot, formatLabel };
