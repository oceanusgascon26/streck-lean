# streck-lean plugin

Claude Code plugin for the streck-lean package.

| Folder | Contents | Source |
|---|---|---|
| `.claude-plugin/plugin.json` | Manifest. The version is set here only. | hand-written |
| `skills/` | `lean-code` and `lean-chat` | generated from the repo `skills/` folder |
| `agents/` | `code-search`, `docs-lookup`, `log-summarizer`, all on Haiku and read-only | generated from the repo `kit/agents/` folder |

Do not edit `skills/` or `agents/` here. Edit the sources and run `scripts/package.ps1`. `scripts/package.ps1 -Check` fails if these copies are stale.

Plugin components are namespaced: the skills run as `/streck-lean:lean-code` and `/streck-lean:lean-chat`, and the agents appear as `streck-lean:code-search` and so on.

Not in the plugin: the settings template, the status line script, and the CLAUDE.md template. A plugin cannot set a user's `model`, `statusLine`, `env`, or `permissions`, so those install from `kit/` as described in `kit/settings.README.md`.
