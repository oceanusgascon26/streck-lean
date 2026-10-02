---
name: lean-code
description: "Use when starting non-trivial coding work in Claude Code, when context is getting large, or when the user asks about cost, tokens, usage limits, model choice, effort, or slowness. Keeps Claude's own reads, replies, and subagents lean and tells the user the one command to run. Not for: Claude.ai chat use (see lean-chat) or app code that calls the Claude API."
---

# Lean code

Every turn re-sends the whole conversation. Tokens you avoid adding now are tokens you stop paying for on every later turn. Work lean by default; tell the user when a command of theirs would help.

## 1. How you work (always)

- **Find, then read ranges.** Use Grep or Glob to locate the code, then Read only the lines you need (offset and limit). Do not read a large file whole to find one function.
- **Delegate broad searches.** If answering means sweeping more than about 3 files or several naming conventions, spawn a subagent and ask for paths plus conclusions, not file dumps. Only its final summary enters your context. For pure lookup, pass `model: haiku` on the call or use a Haiku subagent from the kit; the built-in Explore agent runs on the main session's model.
- **Delegate verbose output.** Test runs, log scans, and doc fetches go to a subagent that returns the failures or the answer, or pipe through a filter (`grep`, `head`) so only the relevant lines come back.
- **Do not re-read.** A file you already read is in context. Re-read only after it changed or when you need a range you have not seen.
- **Do not echo.** Never paste back file contents, large diffs, or tool output the user can already see. Cite `path:line` instead.
- **Short replies.** Lead with the answer. No preamble, no restating the request, no recap of what you just did. Exception: a final report still states file paths and anything you did not verify.
- **Batch.** Send independent tool calls in one message instead of one per turn.
- **Prefer CLIs to MCP** when both exist (`gh`, `az`, `git`). A CLI adds no per-tool listing to context.
- **Ask for a specific target** when a request is vague ("improve this codebase"). One clarifying question is cheaper than a broad scan.
- **Watch task boundaries.** When a task is done and the next one is unrelated, or the conversation is long and mostly stale, stop and suggest `/clear` (unrelated next task) or `/compact <what to keep>` (same task continues). Do not let context grow by default.

## 2. Model tiering (you recommend, the user switches)

You cannot change your own session model. When the task does not fit the current model, say so in one line and give the command.

| Task | Model | Command |
|---|---|---|
| Renames, boilerplate, log scanning, search subagents, lookups with one obvious source | Haiku | `/model haiku` |
| Normal coding: features, fixes, tests, reviews | Sonnet (default) | `/model sonnet` |
| Plan a large change with Opus, build it with Sonnet | opusplan | `/model opusplan` |
| Architecture, hard debugging after a fix already failed, cross-cutting refactors | Opus | `/model opus` |

- Step back down once the hard part is done.
- `/model <alias>` also saves it as the default for new sessions. In the `/model` picker, press `s` on a row to switch for this session only. `claude --model <alias>` sets it at launch.
- Keep Sonnet when the answer depends on judging which source is authoritative (loaded config versus example, current versus old file). In testing, Haiku answered such a question from the decoy file in one turn.
- For subagents you spawn: give Haiku to search and summarizing, Sonnet to coding. Pass `model` per call; the user can also set `CLAUDE_CODE_SUBAGENT_MODEL` as a fallback for agents with no model of their own.

## 3. Effort and thinking

- Thinking tokens bill as output. For mechanical work (renames, formatting, boilerplate, simple lookups) suggest `/effort low` or `/effort medium`; for hard reasoning, `high` or above. Levels: `low`, `medium`, `high`, `xhigh`, `max`; `/effort auto` clears the saved level; `/effort status` prints it. `claude --effort <level>` sets it at launch.
- Thinking cannot be turned off on Opus 5.5, Sonnet 5.5, or Fable models; lower effort instead. `MAX_THINKING_TOKENS` only applies to fixed-budget models, so do not suggest it for these.

## 4. Session hygiene (commands the user runs)

| Command | Use it when |
|---|---|
| `/clear` | Switching to unrelated work. Starts a new session at no cost; the old one stays resumable with `/resume`. |
| `/compact <focus>` | Same task, long history. Example: `/compact keep the failing test, the fix plan, and touched file paths`. It reads the whole conversation to summarize, so run it at a natural break, not every few turns. |
| `/context` | Context feels heavy. Shows what is filling the window, with suggestions. |
| `/usage` (aliases `/cost`, `/stats`) | Checking session tokens, estimated cost, plan limits, and prompt cache hit rate. |
| `/rewind` | Abandoning a wrong path. Cheaper than `/compact` because it returns to an already cached point. |
| `/mcp` | Disabling MCP servers this project does not need. |

## 5. Keep the prompt cache warm

Cache reads are far cheaper than fresh input. These cause a slow, full-price turn, so do them at the start of a session or between tasks, never mid-task:

- switching models (with `opusplan`, every plan mode toggle is a model switch)
- changing effort (on Opus 5.5, Sonnet 5.5, and Fable 5.1 with an API key or subscription, effort changes keep the cache; elsewhere they break it)
- turning on fast mode
- connecting or removing an MCP server, or enabling or disabling a plugin that provides one (only when tool search is off or unavailable)
- denying an entire tool by bare name (only when tool search is off or unavailable)
- `/compact`, upgrading Claude Code, and piling up many images

Cache-safe: editing files, invoking skills, spawning subagents, changing permission mode, `/rewind`. Editing CLAUDE.md is cache-safe but does not apply until `/clear`, `/compact`, or a restart.

The cache expires after inactivity: one hour for the main conversation on a subscription within plan usage, five minutes on an API key, cloud provider, or for subagents. The first turn after a long break is a full re-read.

## 6. Heavy context at session start

If `/context` shows a large fixed load before any work (big CLAUDE.md chain, many MCP servers, a long skill list), point the user to the kit's audit script, which ranks the load and suggests fixes:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\context-audit.ps1
```

Then apply the usual fixes:

- Keep each CLAUDE.md under about 200 lines. Move workflow-specific instructions (PR review, migrations) into skills, which load only when used.
- Enable MCP servers and plugins per project, not globally.
- Put rarely needed reference material in files that CLAUDE.md points to, so it loads on demand.
