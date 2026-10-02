'use strict';
// Minimal test runner. Usage: node test/run.js [filter]
const path = require('path');
const fs = require('fs');

const filter = process.argv[2] || '';
const tests = [];
global.test = (name, fn) => tests.push({ name, fn });

for (const f of fs.readdirSync(__dirname)) {
  if (f.endsWith('.test.js') && f.includes(filter)) require(path.join(__dirname, f));
}

(async () => {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log('ok   ' + t.name);
    } catch (e) {
      failed++;
      console.log('FAIL ' + t.name + ': ' + e.message);
    }
  }
  console.log(tests.length - failed + '/' + tests.length + ' passed');
  process.exit(failed ? 1 : 0);
})();
