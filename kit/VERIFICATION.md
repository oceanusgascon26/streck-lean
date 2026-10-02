# Kit verification record

Checked 2026-10-02 against code.claude.com docs and Claude Code CLI 2.1.287 on Windows 11 (PowerShell 5.1 and 7). "Live" means a run on this machine confirmed it.

## Settings keys (kit/settings.template.json)
| Key or value | Used in | Source | Evidence |
|---|---|---|---|
| `$schema` = `https://json.schemastore.org/claude-code-settings.json` | settings template | https://code.claude.com/docs/en/settings | Doc example uses this URL; schema may lag new keys |
| `model` (alias string) | settings template | https://code.claude.com/docs/en/settings-reference | "Type: string, a model alias or full model ID"; scope any file |
| `sonnet`, `haiku` aliases | settings, agents, env | https://code.claude.com/docs/en/model-config | Alias list: default, best, fable, sonnet, opus, haiku, sonnet[1m], opus[1m], opusplan |
| `statusLine` object: `type: "command"`, `command` | settings template | https://code.claude.com/docs/en/statusline | Doc shape; `padding` and `refreshInterval` optional (not used) |
| `powershell -NoProfile -File C:/...` form, forward slashes | settings template | https://code.claude.com/docs/en/statusline (Windows configuration) | Doc: runs through Git Bash if present, else PowerShell; backslashes get stripped. Live: `~` in `-File` fails when no shell expands it, so the path is absolute |
| `env` | settings template | https://code.claude.com/docs/en/settings-reference | "Set environment variables for every session and its subprocesses" |
| `CLAUDE_CODE_SUBAGENT_MODEL` | settings template env | https://code.claude.com/docs/en/model-config ; https://code.claude.com/docs/en/sub-agents | Default for subagents not assigned a model another way; definition `model` (including `inherit`) wins. Not in the env-vars page table at check time, but documented on both pages above |
| `permissions.deny` with `Read(path)` | settings template | https://code.claude.com/docs/en/permissions | gitignore syntax; deny evaluated before ask and allow |
| `Read(dir/**)` matches that dir at any depth (deny) | settings template | https://code.claude.com/docs/en/permissions | "Read(secrets/**) matches a directory named secrets at any depth". Live: nested `src/obj/x.txt` was denied |
| `Read(*.lock)`, `Read(package-lock.json)` bare names match at any depth | settings template | https://code.claude.com/docs/en/permissions | "Bare filenames follow gitignore semantics and match at any depth". Live: `yarn.lock` denied |
| Deny scope: file tools, Grep/Glob path, `@file`, recognized Bash file commands; not `grep -r .` or scripts | settings.README | https://code.claude.com/docs/en/permissions | Quoted limits in README |
| Live deny test | | headless | `claude -p --settings kit/settings.template.json`: node_modules file, nested obj file, yarn.lock denied; src file read |
| Settings scopes and Windows paths (user, project, local, managed `C:\Program Files\ClaudeCode\managed-settings.json`, HKLM) | settings.README | https://code.claude.com/docs/en/settings ; https://code.claude.com/docs/en/managed-settings | Legacy `C:\ProgramData` path is not read |

## Subagent frontmatter (kit/agents/*.md)
| Field | Source | Evidence |
|---|---|---|
| `name`, `description` (required) | https://code.claude.com/docs/en/sub-agents | Supported fields table |
| `tools` (comma list) | same | "Inherits all available tools if omitted" |
| `model: haiku` | same | Values sonnet, opus, haiku, fable, full ID, inherit. Live: code-search ran on a Haiku model ID per `modelUsage` in `--output-format json` |
| `omitClaudeMd: true` | same | Launch without user, project, local CLAUDE.md; managed still loads |
| `color` | same | red, blue, green, yellow, purple, orange, pink, cyan |
| File locations `.claude/agents/`, `~/.claude/agents/` | same | Priority list |

## CLAUDE.md template (kit/CLAUDE.md.template)
| Claim | Source |
|---|---|
| Target under 200 lines per CLAUDE.md; kit budget 60 is our own stricter choice | https://code.claude.com/docs/en/memory |
| `@path` imports, relative to the importing file, max four hops; imports load at launch, so they do not cut context | same |
| `.claude/rules/*.md` with `paths:` frontmatter load only for matching files | same |
| Block HTML comments are stripped before loading | same |
| Load order: managed, user, parent dirs to working dir, CLAUDE.local.md; subdirectory files on demand | same |

## Statusline input fields (kit/statusline.ps1)
| Field | Source | Notes |
|---|---|---|
| `model.display_name`, `model.id` | https://code.claude.com/docs/en/statusline | |
| `context_window.used_percentage` | same | May be null early in a session |
| `context_window.context_window_size` | same | 200000 default, 1000000 extended |
| `context_window.current_usage.{input_tokens, cache_creation_input_tokens, cache_read_input_tokens}` | same | Null before first call and after /compact; doc formula for percent is input only |
| `cost.total_cost_usd` | same | Client-side estimate at list price; resets on /clear |
| Live tests | | Doc full sample, null fields, 1M window, doc mock input, invalid JSON, empty stdin; PS 5.1 and 7 |

## Audit script sources (scripts/context-audit.ps1)
| Rule | Source |
|---|---|
| MEMORY.md loads first 200 lines or 25 KB; dir `~/.claude/projects/<project>/memory/` | https://code.claude.com/docs/en/memory |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, `autoMemoryEnabled` | https://code.claude.com/docs/en/env-vars ; https://code.claude.com/docs/en/settings-reference |
| MCP scopes: user and local in `~/.claude.json`, project `.mcp.json` (`mcpServers`), plugin `.mcp.json` or `plugin.json` | https://code.claude.com/docs/en/mcp ; https://code.claude.com/docs/en/plugins-reference |
| `disabledMcpjsonServers` | https://code.claude.com/docs/en/settings-reference |
| `managed-mcp.json` in `C:\Program Files\ClaudeCode\` | https://code.claude.com/docs/en/managed-settings |
| Skill locations, `description` + `when_to_use` truncated at 1,536 chars, listing budget 1% of context window | https://code.claude.com/docs/en/skills |
| `disable-model-invocation: true` means description not in context | same |
| `skillOverrides` values on, name-only, user-invocable-only (user-only), off | same |
| Plugin cache `~/.claude/plugins/cache/...`, `installed_plugins.json`, `enabledPlugins` id `name@marketplace`, marketplace entry `skills` list limits what loads | https://code.claude.com/docs/en/plugins/loading |
| Hooks shape and SessionStart stdout added to context | https://code.claude.com/docs/en/hooks |
| Subagent descriptions load for delegation | https://code.claude.com/docs/en/sub-agents |

## Left out (unverified or not worth it)
- `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`: documented, but it overrides agents that need a bigger model. Not shipped.
- `BASH_MAX_OUTPUT_LENGTH`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `effortLevel`: verified, but the cost effect is a tradeoff (truncated errors, earlier compaction, weaker reasoning). Not in the template.
- `DISABLE_NON_ESSENTIAL_MODEL_CALLS`, `MAX_MCP_OUTPUT_TOKENS`: not found on the env-vars page. Not shipped.
- Using `~` in the statusLine command: doc says it expands, but a live test showed `powershell -File ~/...` fails when no shell expands it. Absolute path used instead.
- Statusline relative or `${CLAUDE_PROJECT_DIR}` paths: not documented for `statusLine`. Not used.
- MCP per-server token cost: not documented; the audit uses a rough 40 tokens per server and points to `/context`.
