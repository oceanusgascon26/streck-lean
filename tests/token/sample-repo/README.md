# specimen-tracker

Small internal service that tracks collected specimens, computes how long a
tube stays stable, prints lot labels, and writes a daily report.

- `src/specimen.js` stability rules per tube type
- `src/label.js` label text for the printer
- `src/report.js` daily summary report
- `src/queue.js` retrying job queue used to send labels to the printer
- `src/config.js` loads runtime config

Run tests with `npm test` (or `node test/run.js [filter]`).
