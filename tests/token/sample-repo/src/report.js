'use strict';
const { fmtLot } = require('./label');
const { isWithinStability } = require('./specimen');

function dailyReport(specimens, now) {
  const lines = [];
  let expired = 0;
  for (const s of specimens) {
    const ok = isWithinStability(s, now);
    if (!ok) expired += 1;
    lines.push(fmtLot(s.lotYear, s.lotSeq) + (ok ? ' OK' : ' EXPIRED'));
  }
  lines.push('total=' + specimens.length + ' expired=' + expired);
  return lines.join('\n');
}

module.exports = { dailyReport };
