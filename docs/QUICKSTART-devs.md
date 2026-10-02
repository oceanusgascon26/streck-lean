# Claude Code, lean: a one-page guide for developers

Goal: same results, fewer tokens, and each task on the right model. Commands below were checked against code.claude.com docs and Claude Code 2.1.287 on 2026-10-02.

## 1. Install the kit

The kit lives in `kit\`. `kit\settings.README.md` has a PowerShell snippet that does steps 1 to 3 in one go.

1. Settings template: `kit\settings.template.json`. Merge its keys into `~/.claude/settings.json` (user scope) or a repo's `.claude/settings.json` (shared project scope). Do not overwrite settings you already have. Replace `C:/Users/YOUR_USERNAME` with your own profile path, forward slashes. Org managed settings, if any, still win.
2. Status line script: `kit\statusline.ps1`. Copy it to `~/.claude/statusline.ps1`; the template's `statusLine` setting already points there: `"statusLine": { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/YOUR_USERNAME/.claude/statusline.ps1" }`. It reads session JSON on stdin and shows the model (`model.display_name`), context used (`context_window.used_percentage`), and session cost. Alternative: run `/statusline show model name and context percentage` and let Claude Code generate one.
3. Subagents: `kit\agents\code-search.md`, `kit\agents\docs-lookup.md`, `kit\agents\log-summarizer.md`. Copy them to `~/.claude/agents/` (all projects) or `.claude/agents/` (one repo, shareable). They are read-only agents pinned to Haiku with `model: haiku` and a `tools:` allowlist. Skip this step if you install the plugin below, which already ships them.
4. CLAUDE.md template: `kit\CLAUDE.md.template`. Copy it to a repo root as `CLAUDE.md` and fill it in. Its own budget is 60 lines (the docs target is under 200); move workflow detail (release steps, migration procedure) into skills, which load only when used.

Plugin option. The `streck-lean` plugin ships the `lean-code` and `lean-chat` skills and the three Haiku subagents. From a PowerShell prompt, with `<repo>` as the path to this package (or its git URL):

```powershell
claude plugin marketplace add <repo>
claude plugin install streck-lean@streck-plugins
```

Inside a session, `/plugin marketplace add <repo>` and `/plugin install streck-lean@streck-plugins` do the same. The plugin's components are namespaced: the skills run as `/streck-lean:lean-code` and `/streck-lean:lean-chat`, and the agents appear as `streck-lean:code-search`, `streck-lean:docs-lookup`, and `streck-lean:log-summarizer`. A plugin cannot set your `model`, `statusLine`, `env`, or `permissions`, so do steps 1, 2, and 4 either way. If you install the plugin, do not also copy the agent files in step 3 (drop the `Copy-Item "$kit\agents\*.md"` line from the kit snippet), or you get two copies of each agent.

## 2. Measure your context load

```powershell
powershell -ExecutionPolicy Bypass -File scripts\context-audit.ps1
```

It reports your CLAUDE.md chain size, memory files, MCP servers and tool counts, skill descriptions, and plugins, ranked by cost, with fixes. Fix the top items first. Inside a session, `/context` shows what is using the window right now.

## 3. Pick the model per task

- `/model sonnet` for most coding. This is the default to live on.
- `/model haiku` for simple, mechanical work.
- `/model opus` for hard architecture or multi-step reasoning; switch back after. `/model opusplan` uses Opus in plan mode and Sonnet for execution.
- `/effort low|medium|high|xhigh|max` changes thinking depth. Lower it for routine edits. `/effort auto` clears your saved level.
- A switch to Opus also applies to subagents that inherit your model, so pin subagents to a smaller model (step 1.3).

## 4. Keep the context small

- `/clear` between unrelated tasks. It costs nothing and resets the session. Use `/rename` first if you want to `/resume` it later.
- `/compact <what to keep>` when you need continuity, for example `/compact keep the failing test output and the file list`. Compaction reads the whole conversation, so it is itself a large request; prefer `/clear` when you do not need the history.
- `/context` to see what is loaded. `/mcp` to disable servers you are not using.
- Your first message after a long break can miss the prompt cache and reprocess everything. If the session is large, consider `/clear` with a short written handoff instead.
- Reference files by path and ask for specific functions or line ranges, not whole files. Specific prompts trigger fewer reads.

## 5. Check usage

`/usage` shows the session's tokens by model, cache use, an estimated cost, your plan limits, and on Team and Enterprise a breakdown of usage by skill, subagent, plugin, and MCP server. The cost figure is an estimate at list price unless your org set contracted rates.

## 6. Use subagents for search

When an answer needs more than a few files, ask Claude to delegate the search to a subagent and return only file paths and conclusions. The subagent reads in its own context and only its summary comes back. Use the kit's Haiku search agent for this. Subagent requests still count toward usage, which is why they run on the smaller model.

Sources: https://code.claude.com/docs/en/costs ; https://code.claude.com/docs/en/model-config ; https://code.claude.com/docs/en/sub-agents ; https://code.claude.com/docs/en/statusline
