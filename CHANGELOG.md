# Changelog

Versions follow semantic versioning. The version is set in `plugin/.claude-plugin/plugin.json` only; `scripts/package.ps1` stamps it into the skill zip names.

## 0.1.0

- First release of streck-lean.
- Skills: `lean-chat` (Claude.ai, also works in Claude Code) and `lean-code` (Claude Code).
- Claude Code plugin `streck-lean` in `plugin/`, listed in the `streck-plugins` marketplace at the repo root (source `./plugin`). It ships both skills and the kit's three read-only Haiku subagents: `code-search`, `docs-lookup`, `log-summarizer`.
- Kit (`kit/`): settings template, status line script, CLAUDE.md template, and the same subagents for copy installs. Settings, status line, and CLAUDE.md are not plugin content, because a plugin cannot set user settings.
- `scripts/context-audit.ps1` ranks a developer's fixed context load and suggests fixes.
- `scripts/package.ps1` checks manifests, the skill footprint (description at most 400 characters, body at most 120 lines, warning above about 1,600 tokens), the subagent frontmatter, and every shipped text file for dashes and non-ASCII; regenerates `plugin/skills/` and `plugin/agents/`; builds `dist/claude-ai/lean-chat-<version>.zip` and `lean-code-<version>.zip`; `-Check` detects stale plugin copies; runs `claude plugin validate --strict` when the CLI is installed.
- `tests/token/` harness runs the same tasks default and lean with `claude -p --output-format json` and reports tokens, cost, and pass checks.
- The previous quality pack (`streck-disciplines` 0.2.0) is retired and not part of this package.
