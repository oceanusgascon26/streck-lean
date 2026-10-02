# Token harness tasks

Eight dev tasks against `sample-repo/` (a small Node service, `specimen-tracker`). Each run starts from a fresh copy of the repo, so tasks do not affect each other.

The repo has bait for wasteful reads: `node_modules/` (about 125 vendored files, 0.8 MB), `dist/bundle.js` (one 150 KB line), and `logs/app.log` (2,000 lines). `node_modules/legacy-specimen-utils/` and `dist/bundle.js` also define decoy copies of `computeStabilityWindow` and `fmtLot`.

`run.ps1` reads the JSON block at the end of this file. The prose above it is for people. If you change a task, change the JSON.

| id | class | tiered model | what it tests |
|---|---|---|---|
| T1-find-def | lookup | haiku | find where a symbol is defined without reading the decoys |
| T2-log-summary | summarize | haiku | summarize a 2,000 line log without dumping all of it into context |
| T3-rename | rename | haiku | rename a function across src and test, leaving vendored code alone |
| T4-explain | explain | sonnet | explain one module in a bounded number of words |
| T5-fix-test | fix | sonnet | find and fix the source bug behind a failing test without editing the test |
| T6-feature | feature | sonnet | add a small function plus a test |
| T7-config | lookup | haiku | answer a config question from the file that is actually loaded, not the example |
| T8-review | review | sonnet | review a diff and catch the infinite retry loop and the logged secret |

## Ground truth

- T1: `computeStabilityWindow` is defined in `src/specimen.js` at line 13.
- T2: the main error is `LabelPrinterClient: connect ECONNREFUSED 10.20.30.40:9100`, 47 occurrences, first at `2026-09-28T02:31:40.000Z`, last at `07:10:44`. Each one is followed by a dead letter line. Two unrelated one-off errors appear (EBUSY at line 413, an HTTP 400 near the end).
- T3: `fmtLot` appears in `src/label.js`, `src/report.js`, and `test/label.test.js`.
- T5: `isWithinStability` uses `t < win.end` and should use `t <= win.end`.
- T7: `src/config.js` loads `config/app.json`: host 10.20.30.40, port 9100, retention 30 days. `config/app.example.json` (port 515, 90 days) is a decoy.
- T8: the diff drops `attempt++`, so a job that keeps failing retries forever. It also logs `labelPrinter.apiToken`, a credential (and that key is not in the config, so it logs `undefined` today).

## Check types

| type | fields | passes when |
|---|---|---|
| answer_regex | pattern | the final answer text matches (case-insensitive) |
| answer_not_regex | pattern | the final answer text does not match |
| answer_max_words | max | the final answer has at most `max` words |
| file_regex | path, pattern | the file in the work dir matches |
| no_match | paths, pattern | no file under the listed dirs matches |
| file_unchanged | path | the file is byte-identical to the pristine sample-repo copy |
| cmd | args | `node <args>` exits 0 in the work dir |
| node_check | script | `node checks/<script>` exits 0 with the work dir as cwd |

## Task definitions

```json
[
  {
    "id": "T1-find-def",
    "class": "lookup",
    "tier": "haiku",
    "maxTurns": 6,
    "edits": false,
    "prompt": "Where is the function computeStabilityWindow defined in this project's own source code? Reply with the file path and line number only.",
    "checks": [
      { "type": "answer_regex", "pattern": "src[\\\\/]specimen\\.js" },
      { "type": "answer_regex", "pattern": "\\b13\\b" }
    ]
  },
  {
    "id": "T2-log-summary",
    "class": "summarize",
    "tier": "haiku",
    "maxTurns": 8,
    "edits": false,
    "prompt": "Summarize the main error in logs/app.log: what is failing, how many times it happened, and the timestamp of the first occurrence. Keep it under 80 words.",
    "checks": [
      { "type": "answer_regex", "pattern": "ECONNREFUSED|connection refused" },
      { "type": "answer_regex", "pattern": "\\b47\\b" },
      { "type": "answer_regex", "pattern": "02:31" },
      { "type": "answer_regex", "pattern": "9100|10\\.20\\.30\\.40|label ?printer" }
    ]
  },
  {
    "id": "T3-rename",
    "class": "rename",
    "tier": "haiku",
    "maxTurns": 12,
    "edits": true,
    "prompt": "Rename the function fmtLot to formatLotNumber everywhere in this project's own code and tests (src/ and test/). Do not touch vendored or built files. Then run node test/run.js label to confirm the label tests pass.",
    "checks": [
      { "type": "no_match", "paths": ["src", "test"], "pattern": "\\bfmtLot\\b" },
      { "type": "file_regex", "path": "src/report.js", "pattern": "formatLotNumber" },
      { "type": "cmd", "args": ["test/run.js", "label"] },
      { "type": "file_unchanged", "path": "node_modules/legacy-specimen-utils/index.js" }
    ]
  },
  {
    "id": "T4-explain",
    "class": "explain",
    "tier": "sonnet",
    "maxTurns": 6,
    "edits": false,
    "prompt": "Explain what src/queue.js does and how its retry behavior works, for a developer new to the project. Under 150 words.",
    "checks": [
      { "type": "answer_regex", "pattern": "retr" },
      { "type": "answer_regex", "pattern": "exponential|backoff|doubl" },
      { "type": "answer_regex", "pattern": "dead.?letter" },
      { "type": "answer_max_words", "max": 200 }
    ]
  },
  {
    "id": "T5-fix-test",
    "class": "fix",
    "tier": "sonnet",
    "maxTurns": 12,
    "edits": true,
    "prompt": "node test/run.js is failing. Find the cause and fix the source code. Do not change any test files. Run the tests again to confirm.",
    "checks": [
      { "type": "cmd", "args": ["test/run.js"] },
      { "type": "file_unchanged", "path": "test/specimen.test.js" },
      { "type": "node_check", "script": "stability-boundary.js" }
    ]
  },
  {
    "id": "T6-feature",
    "class": "feature",
    "tier": "sonnet",
    "maxTurns": 15,
    "edits": true,
    "prompt": "Add a function parseLot(text) to src/label.js and export it. It takes a lot string like 'LOT-2026-00042' and returns { year: 2026, seq: 42 }. The format is exactly LOT-, a 4 digit year, a dash, and a 5 digit sequence; return null for anything else, including non-strings. Add at least one test for it in test/label.test.js and run node test/run.js label.",
    "checks": [
      { "type": "node_check", "script": "parse-lot.js" },
      { "type": "file_regex", "path": "test/label.test.js", "pattern": "parseLot" },
      { "type": "cmd", "args": ["test/run.js", "label"] }
    ]
  },
  {
    "id": "T7-config",
    "class": "lookup",
    "tier": "haiku",
    "maxTurns": 6,
    "edits": false,
    "prompt": "At runtime, what host and port does the app use for the label printer, and how many days are records retained? Answer in one or two lines.",
    "checks": [
      { "type": "answer_regex", "pattern": "10\\.20\\.30\\.40" },
      { "type": "answer_regex", "pattern": "\\b9100\\b" },
      { "type": "answer_regex", "pattern": "\\b30\\b" },
      { "type": "answer_not_regex", "pattern": "\\b515\\b(?![^\\n]*example)" }
    ]
  },
  {
    "id": "T8-review",
    "class": "review",
    "tier": "sonnet",
    "maxTurns": 8,
    "edits": false,
    "prompt": "Review the diff in review/pr-142.diff against the current src/queue.js. List the bugs and risks it introduces, most serious first. Be brief.",
    "checks": [
      { "type": "answer_regex", "pattern": "infinite|forever|endless|never (stop|end|terminat|exit|increment)|not increment|no longer increment|attempt\\+\\+|attempt is never" },
      { "type": "answer_regex", "pattern": "token|secret|credential" }
    ]
  }
]
```
