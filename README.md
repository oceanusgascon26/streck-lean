# streck-lean

A small package that cuts token spend and context bloat for Streck's Claude users and puts each task on the right model tier. It covers two groups: staff using Claude.ai Enterprise, and developers using Claude Code.

The previous quality pack is not part of this deliverable. It is archived and does not ship.

## What is in it

| Piece | What it does | For |
|---|---|---|
| `skills/lean-chat/` | Skill for Claude.ai (also works in Claude Code): right model and effort, one task per chat, summarize and restart long chats, Projects for reused documents, answers sized to need | All Claude.ai staff |
| `skills/lean-code/` | Skill for Claude Code: model routing, subagents on cheaper models for search, `/clear` `/compact` `/context` `/usage` habits, targeted reads, lean CLAUDE.md | Developers |
| `kit/` | Claude Code config pack: settings template, status line with context percent, Haiku search subagents, CLAUDE.md template with a line budget | Developers |
| `scripts/context-audit.ps1` | Measures a developer's context load (CLAUDE.md chain, memory, MCP servers and tools, skill descriptions, plugins) and prints a ranked report with fixes | Developers |
| `docs/ADMIN.md` | Org levers: default and allowed models, effort caps, gating Claude Code and Cowork, spend limits, analytics, Claude Code managed settings, a recommended starting policy, and a monthly review routine | IT admins |
| `docs/QUICKSTART-users.md` | One page of habits for non-technical staff | All Claude.ai staff |
| `docs/QUICKSTART-devs.md` | One page: install the kit, run the audit, model tiering, context commands | Developers |
| `tests/token/` | Harness that runs the same tasks lean and default with `claude -p --output-format json` and reports tokens, cost, and a quality check | Maintainers |

## Layout

```
README.md            this file
CONTRACT.md          build rules for the package
skills/              lean-chat, lean-code (SKILL.md each)
kit/                 Claude Code config pack
plugin/              Claude Code plugin wrapper
scripts/             context-audit.ps1 and packaging scripts
docs/                ADMIN.md, QUICKSTART-users.md, QUICKSTART-devs.md
tests/token/         token harness
research/            source notes with Anthropic doc links behind every claim
dist/                built skill zips for Claude.ai upload
```

The 0.2.0 zips currently in `dist/claude-ai/` belong to the previous quality pack and are not part of this deliverable.

## How to install

Build first: `powershell -ExecutionPolicy Bypass -File scripts\package.ps1` validates everything, refreshes `plugin\skills\` and `plugin\agents\`, and writes `dist\claude-ai\lean-chat-<version>.zip` and `dist\claude-ai\lean-code-<version>.zip`. Add `-Check` to verify without writing.

Claude.ai (admin): an Owner uploads `dist\claude-ai\lean-chat-<version>.zip` at Organization settings > Plugins & skills > Add > Upload a skill. It goes to everyone and is on by default. Code execution and Skills must be on under the Policy tab. See `docs/ADMIN.md` step A7. Then share `docs/QUICKSTART-users.md`. The `lean-code` zip is for Claude Code habits; uploading it to Claude.ai does no harm but adds little.

Claude Code (developer):
- Plugin (skills and Haiku subagents): `claude plugin marketplace add <path to this repo or its git URL>`, then `claude plugin install streck-lean@streck-plugins`. The marketplace file is `.claude-plugin/marketplace.json`; the plugin is in `plugin/`.
- Kit (settings, status line, CLAUDE.md template): a plugin cannot set user settings, so these install from `kit/` with the snippet in `kit/settings.README.md`. If you installed the plugin, skip the snippet's agent copy line.
- Without the plugin, the same snippet also copies the subagents; the skills can be copied from `skills/` to `~/.claude/skills/`.

Details and file names: `docs/QUICKSTART-devs.md`.

Org-wide Claude Code policy (models, env, MCP allow and deny) is set by IT through managed settings; see `docs/ADMIN.md` Part B.

## Results

Measured token and cost results from the harness will be published in `RESULTS.md` at the root.

## Rules this package follows

Every product claim is checked against current Anthropic documentation and cited in `research/` or inline. Anything that could not be confirmed is marked UNVERIFIED.
