# Token harness

Measures tokens and cost per task for Claude Code configurations, and checks that answer quality holds. A saving only counts if the cheaper run passes the same checks.

## Files

| path | what it is |
|---|---|
| `tasks.md` | the 8 tasks, their ground truth, and the JSON block `run.ps1` reads |
| `run.ps1` | the runner (Windows PowerShell 5.1 or later) |
| `build-sample.ps1` | generates the bulky parts of the sample repo: `logs/app.log`, `node_modules/`, `dist/bundle.js`; `run.ps1` calls it |
| `sample-repo/` | small Node service used as the task target |
| `checks/` | Node scripts for checks that need to run code |
| `results/` | one CSV and one markdown summary per run, plus raw JSON in a timestamped folder |

Requirements: `claude` and `node` on PATH. No npm install is needed; the sample repo has no dependencies.

## Configs

| config | model | kit |
|---|---|---|
| `default` | `-Model` (default `sonnet`) | none |
| `lean` | `-Model` | kit settings and agents |
| `tiered` | per task: `haiku` for lookup, summarize, rename; `sonnet` otherwise | kit settings and agents |

The kit is read from `..\..\kit\` by default: `settings.json` if present, else `settings.template.json`, plus `agents\*.md`. Override with `-LeanSettings` and `-LeanAgentsDir`. `-LeanClaudeMd <file>` also installs a CLAUDE.md into the work dir; it is off by default. If no kit files exist, `lean` is skipped with a warning and `tiered` runs without the kit, which then measures model choice only. The CSV column `kit_applied` records which happened.

The kit is installed per run into the work dir as project config: settings to `.claude\settings.json`, agents to `.claude\agents\`. That is how a developer would install it, and it makes relative deny rules such as `Read(node_modules/**)` resolve against the repo root.

## Protocol

For each task, config, and repeat:

1. Copy `sample-repo` to `%TEMP%\claude-token-harness\<timestamp>\<task>-<config>-<rep>`.
2. Install the kit for `lean` and `tiered`.
3. Run, from the work dir:
   `claude "<prompt>" -p --output-format json --model <m> --max-turns <n> --permission-mode acceptEdits --permission-prompts none --no-session-persistence --max-budget-usd <usd> --allowedTools <tools>`
   Read-only tasks get `Read Grep Glob`. Edit tasks add `Edit Write MultiEdit Bash(node *) Bash(npm test*) PowerShell(node *) PowerShell(npm test*)`. Anything else that would prompt is denied (`--permission-prompts none`); denials are counted in `permission_denials`.
4. Parse the JSON result. Token counts come from `modelUsage`, summed across every model the session used, so Haiku subagent tokens count toward the run. If `modelUsage` is missing, the main-model `usage` block is used.
5. Run the task's checks against the work dir and the final answer text.
6. Delete the work dir unless `-KeepWorkDirs`.

Recorded per run: input_tokens, output_tokens, cache_read, cache_creation, total_tokens, total_cost_usd, num_turns, duration_ms, wall_ms, subtype (`success`, `error_max_turns`, ...), models_used, subagents_spawned, permission_denials, checks passed, and a check bitmap.

The summary has totals per config with deltas against `default`, and a per-task table with mean tokens, mean cost, deltas, and a quality column (`equal`, `better`, `WORSE`) that compares mean checks passed against `default`.

## Running

```powershell
# Smoke: one task, default config, Haiku, 3 turns
.\run.ps1 -Tasks T1-find-def -Configs default -Model haiku -MaxTurns 3

# Full matrix: 8 tasks x 3 configs x 3 repeats = 72 runs
.\run.ps1 -Repeat 3

# Clean room
$env:ANTHROPIC_API_KEY = '<key>'
.\run.ps1 -Repeat 3 -Bare
```

Other switches: `-MaxTurns` overrides every task's turn limit; `-MaxBudgetUsd` caps spend per run (default 2); `-TimeoutSec` kills a hung run (default 600); `-PermissionMode`; `-ClaudePath`; `-OutDir`.

Run at least 3 repeats before quoting a number. Single runs vary a lot with the path the model takes.

## Limits

- **Inherited config.** Without `-Bare`, every run loads the operator's user-level setup: `~/.claude/settings.json`, user CLAUDE.md, plugins, skills, MCP servers, hooks, and auto memory. That overhead lands in every config, so absolute numbers describe that machine, not a clean install, and a heavy user setup shrinks the relative gain from the kit. The script prints `MODE: INHERITED` at start and end, and the summary and CSV record the mode.
- **`-Bare`.** Adds `--bare`, which skips hooks, plugins, auto memory, keychain reads, and CLAUDE.md auto-discovery. Auth is then only `ANTHROPIC_API_KEY` (or an `apiKeyHelper` passed via `--settings`); the script refuses to start without the env var. In bare mode the kit settings are also passed with `--settings`. Whether `--bare` still discovers project agents in `.claude\agents\` is UNVERIFIED; check `subagents_spawned` and `models_used` in the CSV before trusting lean numbers from a bare run.
- **Cost is an estimate.** `total_cost_usd` is the CLI's client-side figure at list price. It is not a bill, and it is not meaningful for subscription seats except as a relative measure.
- **Cache state.** The first run of a session pays cache creation; later runs within the cache TTL read it. Order and timing affect `cache_read` and `cache_creation`. Repeats and comparing totals help; per-run cache numbers are noisy.
- **Nested sessions.** If you launch the harness from inside a Claude Code session, the script unsets `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, and `CLAUDE_CODE_SSE_PORT` for the child so it behaves like a plain terminal run. Provider and auth variables are left alone. It also kills processes the child leaves behind (MCP servers, git) so they do not hold the console open. In testing this cleanup missed some MCP server processes started through npx, about 40 over a 24-run matrix. After a large run, check for leftover node processes whose parent no longer exists and stop them; left alone they accumulate and can exhaust memory.
- **Work dir location.** Runs happen under `%TEMP%`. Any CLAUDE.md in a parent of that path would load too. Check that none exists on the test machine.
- **Checks are narrow.** They catch the facts each task needs (a file and line, a count, a port, a passing test) and a few known traps. They do not grade explanation quality beyond that.
- **Turn limits matter.** A run that hits `--max-turns` ends with `subtype=error_max_turns` and no final answer, so answer checks fail even if the edits landed. Do not compare configs at a turn limit too tight for either.
