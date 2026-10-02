# Results: streck-lean 0.1.0

Measured on 2026-10-02 with the harness in tests/token/, Claude Code CLI 2.1.287. Eight developer tasks ran against a small sample repo with decoy files and a junk dependency folder. Each task ran once per configuration in a fresh headless session. Costs are the CLI's own estimates at list price.

## Configurations

- default: Sonnet, no kit.
- lean: Sonnet plus the kit (deny rules for heavy folders, Haiku subagents, lean CLAUDE.md template).
- tiered: the model the lean-code skill recommends for that kind of task. Haiku for find, log summary, rename, and config lookup; Sonnet for the rest.

## Totals

| Config | Tasks passed | Checks passed | Total tokens | Cost (USD) | Cost vs default |
|---|---|---|---|---|---|
| default | 8/8 | 26/26 | 856,889 | 0.601 | baseline |
| lean | 8/8 | 26/26 | 852,205 | 0.585 | -3% |
| tiered | 7/8 | 23/26 | 904,865 | 0.485 | -19% |

## Per task (cost in USD)

| Task | default | lean | tiered |
|---|---|---|---|
| Find a definition | 0.049 | 0.051 | 0.048 (Haiku) |
| Summarize a 2,000-line log | 0.081 | 0.085 | 0.068 (Haiku) |
| Rename across files | 0.092 | 0.065 | 0.053 (Haiku) |
| Explain a module | 0.059 | 0.058 | 0.058 |
| Fix a failing test | 0.084 | 0.084 | 0.085 |
| Add a small feature | 0.088 | 0.090 | 0.089 |
| Answer a config question | 0.083 | 0.074 | 0.019 (Haiku, wrong answer) |
| Review a diff | 0.066 | 0.078 | 0.066 |

An earlier partial run covered the first five tasks twice each and pointed the same way: tiered cost 23 percent less than default on those tasks.

## What this shows

- Model tiering is the biggest saving. Moving mechanical work (renames, log summaries, searches) to Haiku cut cost by 16 to 42 percent on those tasks at equal quality. Haiku used more tokens and turns, but each token costs much less.
- Haiku fails on judgment about sources. On the config question it answered from the example file instead of the loaded one, in a single turn. The lean-code skill now says to keep Sonnet when the answer depends on judging which source is authoritative.
- The project kit saved little on this repo. Even without the kit, Claude did not read the junk folders, so the deny rules had nothing to block. Their value is as a guardrail on large real repos, and that was not measured here.
- Most of the token floor sits below the project level. The simplest task used about 62,000 tokens, mostly cached system prompt, tools, skills, and MCP server listings from the user-level setup. A project kit cannot remove that. The levers are context-audit.ps1 for each developer and managed settings from IT (see docs/ADMIN.md).

## Limits

- The runs inherited the operator's user-level setup: skills, MCP servers, plugins, and CLAUDE.md. That inflates every absolute number, and a Streck developer with a clean setup will start lower. The harness supports `-Bare` for a clean run, which needs an API key.
- The sample is small: one run per configuration per task, on one small repo. Treat the percentages as direction, not as a forecast.
- The Claude.ai skill (lean-chat) has no automated measurement here. Claude.ai usage is best tracked with the admin analytics export, before and after rollout, as described in docs/ADMIN.md.
- Headless runs can leave MCP server processes running when the user setup includes local MCP servers. The harness cleans most of them up, but not all. Check for leftover node processes after a large run.

## Next measurement

Run the harness with `-Bare` and three repeats, on one real Streck repo. Compare the Claude.ai analytics export for a pilot group for 30 days before rollout and 30 days after.
