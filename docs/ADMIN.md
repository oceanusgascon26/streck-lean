# streck-lean admin guide

For Streck IT admins who own the Claude Enterprise organization and the Claude Code rollout. Work through the checklist in order. Each step gives the menu path or setting key and the Anthropic source it was checked against on 2026-10-02.

Items marked UNVERIFIED were not confirmed in a current Anthropic source. Check them in the console before relying on them.

Roles: most org settings need the Primary Owner or Owner role. Model defaults and custom roles can also be managed by a custom role with the Identity & Access permission. Claude Code server-managed settings need Owner or Primary Owner.

---

## Part A. Claude.ai Enterprise organization

### A1. Set the organization default model

- Path: Organization settings > Models. Choose "Use Anthropic's recommended default" (follows Anthropic's updates) or "Choose a specific model" (stays fixed until you change it). A default effort level can be set in the same place. Custom roles can carry their own default.
- Sticky default (beta): turn on "Always start with the default model and effort level" so every new conversation starts on the org default. Users can still switch inside a chat.
- Scope: applies to chat, Cowork, Claude Code (CLI 2.1.199 or later), Office, and Design. For Claude Code, a managed settings `model` key overrides it (see B3).
- Anthropic's guidance is Sonnet as the org default for daily work.
- Source: https://support.claude.com/en/articles/15330088-set-a-default-model-for-your-organization ; https://support.claude.com/en/articles/14782391-claude-enterprise-consumption-guide

### A2. Disable models and cap effort, org-wide and by role

- Disable a model for everyone: Organization settings > Models > Model access > find the model, deselect its roles in the role dropdown, switch the toggle off, Save. Disabling removes the model for everyone, Owners included.
- Cap effort per model: Organization settings > Models > Model access > the model's effort level dropdown > pick the maximum > Save.
- Per role: Organization settings > Roles > select or create a role > Models tab > switch each model on or off; the gear icon next to a model sets that role's effort cap > Save.
- Haiku models are always available and cannot be disabled.
- Fable is the most expensive tier and can be left disabled or restricted to one custom role.
- Source: https://support.claude.com/en/articles/15694740-manage-model-access-for-your-organization ; https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan

### A3. Gate Claude Code and Cowork by group

- Path: Organization settings > Roles. Custom roles grant or withhold capabilities such as chat, Claude Cowork, Claude Code, and web search, plus the org's connectors. A capability must be on at the organization level before a role can grant it. Assign roles to groups; with SCIM directory sync, groups come from your identity provider.
- Anthropic ranks surface intensity as chat lower, Claude Code higher, Cowork highest, and gives "only an Engineering group gets Claude Code" as the example.
- "Run Cowork in the cloud" is off by default on Enterprise; an Owner turns it on and then grants it to a group through a custom role. Claude Code dynamic workflows are on by default; decide which roles keep them, since one run can last hours.
- UNVERIFIED: the exact toggle labels on the role capability list. Confirm in the console.
- Source: https://support.claude.com/en/articles/13930452-manage-custom-roles-on-enterprise-plans ; https://support.claude.com/en/articles/13930458-set-up-role-based-permissions-on-enterprise-plans ; https://support.claude.com/en/articles/13455879-use-claude-cowork-on-team-and-enterprise-plans ; https://support.claude.com/en/articles/14782391-claude-enterprise-consumption-guide

### A4. Spend limits and alerts

- Path: Organization settings > Usage (https://claude.ai/admin-settings/usage) > By group/tier > Edit limits. Choose "No member limit" or "Member limit" and enter an amount.
- Levels: organization, group, and individual, plus pooled group budgets (beta). An individual limit wins over a group limit; a group limit wins over the org limit. When a member is in several groups, an org setting decides whether the higher or lower limit applies.
- Alerts: org alerts at 75% and 90%; pooled budget alerts at 50, 75, 95, and 100%. UNVERIFIED: where alert recipients are configured, and whether per-user alerts exist.
- A request already running can go past a limit; the next request is blocked.
- Anthropic recommends group and per-user limits over a hard org cap, and suggests defining usage tiers by job function before rollout.
- On usage-based Enterprise, all usage is billed at API rates from a shared org pool and spend limits are the control. Claude Code draws from the same pool and the same limits.
- Source: https://support.claude.com/en/articles/13799932-manage-groups-and-group-spend-limits-on-enterprise-plans ; https://support.claude.com/en/articles/11526368-how-am-i-billed-for-my-enterprise-plan ; https://support.claude.com/en/articles/14552983-models-usage-and-limits-in-claude-code

### A5. Connector tool access mode

- Each connector takes up space in a conversation. Modes: Auto (default; Claude picks what to load), Always available (all loaded upfront; best under 10 connectors), On demand (loaded only after Claude searches; best for 10 or more connectors or when hitting length limits).
- Path for users: in a chat, "+" or "/" > Connectors > Tool access > pick a mode. This is set per conversation.
- UNVERIFIED: an org-wide default for tool access mode. None was found. The admin levers are which connectors you enable for the org and for each role (A3), plus user guidance (QUICKSTART-users.md).
- Source: https://support.claude.com/en/articles/13730515-manage-claude-s-tool-access

### A6. Keep code execution on

- Code execution is required for automatic context management in long chats and for skills, including the streck-lean skills. Turning it off to save tokens removes both.
- Path: Organization settings > Plugins & skills > Policy tab > "Cloud code execution and file creation" and "Skills" both on.
- Source: https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work ; https://support.claude.com/en/articles/13119606-provision-and-manage-skills-for-your-organization

### A7. Provision the lean-chat skill

- Path: Organization settings > Plugins & skills > Add > Upload a skill > select the zip (must contain SKILL.md). It is provisioned to everyone and enabled by default; users can turn it off. To limit it to some users, bundle it in a plugin and assign the plugin to a group.
- Source: https://support.claude.com/en/articles/13119606-provision-and-manage-skills-for-your-organization

### A8. Monitoring: analytics dashboard, CSV export, Analytics API

- Dashboard: active members, seat use, adoption, skills with cost per use, connector activity, spend MTD/QTD/YTD, spend by model, top users, time at limit, and a "Blocked by a spend limit" list. Separate views for chat, Claude Code, Cowork, and Design. Visible to Owners, Primary Owners, and Admins; spend is hidden from Admins.
- CSV export: spend per user and per model with request counts, prompt and completion tokens, and net and gross spend. Daily refresh, one-day lag, ranges up to 90 days.
- Member self-view: usage-based Enterprise members can see their own usage in Settings > Usage if Owners enable it.
- Analytics API (Enterprise): a Primary Owner enables it under Organization settings > API and creates a key with the `read:analytics` scope at https://claude.ai/analytics/api-keys. It returns per-user usage and cost across surfaces, including Claude Code.
- Claude Code adoption view: https://claude.ai/analytics/claude-code (daily active users, sessions, contribution metrics).
- Source: https://support.claude.com/en/articles/12883420-view-usage-analytics-for-team-and-enterprise-plans ; https://code.claude.com/docs/en/costs ; https://support.claude.com/en/articles/9797531-what-is-the-enterprise-plan

---

## Part B. Claude Code managed settings

### B1. Pick a delivery mechanism

| Mechanism | Where | Notes |
|---|---|---|
| Server-managed | Admin Settings > Claude Code > Managed settings (https://claude.ai/admin-settings/claude-code). Paste JSON. | Owner or Primary Owner. Fetched at startup and hourly. Applies to every user in the org; per-group configuration is not supported yet. Needs network access to api.anthropic.com. Skipped when a user sets a third-party provider variable or a custom `ANTHROPIC_BASE_URL`. Not fetched in Cowork sessions. |
| Windows file | `C:\Program Files\ClaudeCode\managed-settings.json`, plus optional `managed-settings.d\*.json` drop-ins | The legacy path `C:\ProgramData\ClaudeCode\managed-settings.json` is not read. |
| Windows registry | `HKLM\SOFTWARE\Policies\ClaudeCode`, value `Settings` (REG_SZ or REG_EXPAND_SZ) holding the JSON | Deploy with Intune or Group Policy. `HKCU` at the same path is a user-writable fallback, not an admin source. |
| macOS | File: `/Library/Application Support/ClaudeCode/managed-settings.json`. Profile: domain `com.anthropic.claudecode` | |
| Linux and WSL | `/etc/claude-code/managed-settings.json` | |

Precedence: managed settings sit above command line, project local, shared project, and user settings. Within the managed tier, Claude Code by default uses the first source that delivers a policy key, in this order: server-managed, then MDM/registry (HKLM or plist), then managed settings files, then HKCU. Sources do not merge unless the top source sets `managedSourcesBehavior` to `"merge"`. Exceptions: the `env` block merges per variable across admin sources (v2.1.223 or later), and `deniedMcpServers` entries apply from any admin source.

For Streck: if developer machines are in Intune, endpoint-managed (HKLM or the Program Files file) is the stronger control because the OS protects it from user edits. Server-managed is the option for unmanaged machines. If you use both, remember server-managed wins whole unless you set merge.

Verify on a test machine: `/status` shows the `Setting sources` line; `claude doctor` shows the `Managed settings (remote)` outcome (v2.1.248 or later).

Sources: https://code.claude.com/docs/en/server-managed-settings ; https://code.claude.com/docs/en/managed-settings ; https://code.claude.com/docs/en/settings

### B2. Restrict models: `availableModels`

- `availableModels` limits what users can pick with `/model`, `--model`, or their own `model` key. Entries can be a family alias (`sonnet`), a version prefix, or a full model ID.
- Add `"enforceAvailableModels": true` so the Default option also resolves inside the list. Without it, Default stays on the account's runtime default.
- When managed settings define `availableModels`, entries users add in their own files are ignored.
- The claude.ai org default model (A1) is checked against the list; one outside the list falls back to the enforced default.
- Source: https://code.claude.com/docs/en/model-config ; https://code.claude.com/docs/en/settings

### B3. Default model and effort: `model`, `effortLevel`

- A managed `model` sets the model each session starts with. It is a starting point, not a lock: users can still switch with `/model` within `availableModels`. Changes to `model` apply at the next launch.
- Precedence over the claude.ai org default: `--model` and `ANTHROPIC_MODEL` first, then a managed `model`, then user or project `model`. If nothing is set, the claude.ai org default applies (Anthropic API with claude.ai login only; not Bedrock, Vertex, or Foundry).
- Effort: `effortLevel` key (or per model under `modelSettings`), `CLAUDE_CODE_EFFORT_LEVEL` env var (v2.1.236 or later). Users override with `/effort` or `--effort`. Default effort is `medium` on Opus 5.5 and Sonnet 5.5 and `high` on most others. Effort caps set in claude.ai (A2) also apply to Claude Code.
- UNVERIFIED: whether a managed `effortLevel` beats a user's own `/effort` choice. The docs give an explicit user choice first priority, so treat it as a default, and use the claude.ai effort cap (A2) as the ceiling.
- Source: https://code.claude.com/docs/en/model-config ; https://support.claude.com/en/articles/15694740-manage-model-access-for-your-organization

### B4. Environment variables: `env`

- Useful for cost: `CLAUDE_CODE_SUBAGENT_MODEL` sets the model for subagents that do not name one (resolution: per-call parameter, then the agent file's `model`, then this variable, then the main model). `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` makes it override everything; avoid that unless you want every subagent pinned.
- Model, effort, and compaction variables (for example `ANTHROPIC_MODEL`, `CLAUDE_CODE_EFFORT_LEVEL`, `DISABLE_AUTO_COMPACT`) apply from server-managed settings without a user approval dialog. Proxy and base URL variables require approval.
- Source: https://code.claude.com/docs/en/sub-agents ; https://code.claude.com/docs/en/server-managed-settings

### B5. MCP allow and deny

- `deniedMcpServers`: list of entries, each one of `{ "serverUrl": "https://host/*" }`, `{ "serverCommand": ["cmd", "arg"] }`, or `{ "serverName": "label" }`. A deny match always wins.
- `allowedMcpServers` plus `"allowManagedMcpServersOnly": true`: an approved catalog that users cannot widen. Without the lock, users can add to the allowlist in their own settings. An empty array allows no user-added servers.
- `serverName` is a user-chosen label and is not a security control. Use `serverUrl` and `serverCommand` for enforcement.
- `managedMcpServers` (v2.1.259 or later) provides remote http/sse servers to everyone. A `managed-mcp.json` file at the system path (Windows: `C:\Program Files\ClaudeCode\managed-mcp.json`) takes exclusive control; it cannot be delivered through server-managed settings.
- Context cost: MCP tool definitions are deferred by default, so only tool names and server instructions load until a tool is used. Fewer servers still means less context; CLI tools such as `gh` add no per-tool listing.
- Source: https://code.claude.com/docs/en/managed-mcp ; https://code.claude.com/docs/en/costs

### B6. Cost display at contracted rates: `modelPricing`

- Managed-only key (v2.1.242 or later). Makes `/usage` and the status line show cost at Streck's contracted rates instead of list price. It changes what is displayed, not what is billed.
- Source: https://code.claude.com/docs/en/costs

---

## Part C. Recommended starting policy

RECOMMENDATION ONLY. Streck decides. Dollar amounts are left blank on purpose; set them from a pilot baseline. Anthropic suggests a small pilot group first and weekly review during rollout.

Claude.ai:
1. Org default: "Choose a specific model", latest Sonnet, with sticky default on.
2. Fable: disabled, or granted to one small custom role on request.
3. Opus: on for all staff with an effort cap of High for general roles; Extra High and Max only on a developer or analyst role.
4. Roles: a "Developers" custom role, mapped to an Entra ID group through SCIM, is the only role with Claude Code. Cowork goes to a named pilot group only. Everyone else gets chat.
5. Spend: per-user member limits on every group, set lower for chat-only groups than for Developers. Org-level limit as a backstop with the 75% and 90% alerts. Prefer group and user caps over a hard org cap.
6. Connectors: enable only the connectors each role needs. Teach On demand mode for anyone with many connectors.
7. Code execution and Skills on; provision lean-chat.

Claude Code managed settings (deliver via HKLM or `C:\Program Files\ClaudeCode\managed-settings.json` on Intune devices, or server-managed for others):

```json
{
  "model": "sonnet",
  "availableModels": ["sonnet", "haiku", "opus"],
  "enforceAvailableModels": true,
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "haiku"
  },
  "deniedMcpServers": [
    { "serverUrl": "https://*.example-unapproved.com/*" }
  ]
}
```

Replace the denylist entry with Streck's real list, or remove it. Add `modelPricing` if Streck has contracted rates. Add `fable` to `availableModels` only if A2 grants Fable to developers.

---

## Part D. Monthly review routine

Run once a month after the first month (weekly during the pilot). About 30 minutes.

1. Export the spend CSV for the last 30 days (Analytics > spend report, or the Analytics API).
2. Top spenders by model: sort by net spend; for the top 10 users, see which model carries the spend. Opus or Fable heavy users who do routine work are the first coaching conversation.
3. Model mix: share of spend on Sonnet and Haiku versus Opus and Fable. The target is most spend on Sonnet. If the mix is drifting up, check that the sticky default is still on.
4. Effort mix: UNVERIFIED that effort level appears in the CSV or dashboard. If it does not, use model mix and per-request token counts (completion tokens per request) as a proxy; a rising completion-tokens-per-request figure on one model suggests higher effort.
5. Skill cost per use: open the skills view in the dashboard. Flag any skill whose cost per use is out of line with what it does, and any provisioned skill nobody uses.
6. Limits: review "Blocked by a spend limit" and time-at-limit per seat. Investigate before raising a limit; raise only where the work justifies it.
7. Claude Code: compare Code spend per active developer month over month on the Claude Code view. A jump usually means long uncleared sessions or Opus as default; send the QUICKSTART-devs.md link.
8. Record the month's numbers and any setting changes in a short log so the trend is visible.

---

## UNVERIFIED items in this guide

1. Exact capability toggle labels on the custom role page (A3).
2. Where spend alert recipients are set, and whether per-user alerts exist (A4).
3. An org-wide default for connector tool access mode (A5). None found.
4. Whether a managed `effortLevel` overrides a user's `/effort` choice (B3).
5. Whether effort level is reported in the analytics CSV or dashboard (D4).
