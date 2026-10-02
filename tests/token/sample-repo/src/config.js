'use strict';
const fs = require('fs');
const path = require('path');

// Runtime config. The example file is documentation only and is never loaded.
const CONFIG_PATH = path.join(__dirname, '..', 'config', 'app.json');

function loadConfig() {
  const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
  return JSON.parse(raw);
}

module.exports = { loadConfig, CONFIG_PATH };
