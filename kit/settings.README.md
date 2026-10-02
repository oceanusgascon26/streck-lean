# settings.template.json

## Where the file goes
- User (you, every project): `%USERPROFILE%\.claude\settings.json`. Start here.
- Project (everyone who clones the repo): `.claude\settings.json`, committed to git.
- Project local (you, one repo, not committed): `.claude\settings.local.json`.
- Managed (IT, every machine, cannot be overridden): `C:\Program Files\ClaudeCode\managed-settings.json`, the HKLM policy key, or server-managed settings from the admin console. See docs/ADMIN.md.

Settings files are strict JSON: no comments, no trailing commas. If you already have a settings file, merge these keys into it instead of overwriting it.

## Keys
- `$schema`: editor autocomplete and validation; Claude Code ignores it at runtime.
- `model`: `sonnet` as the default for new sessions; switch with `/model opus` when a task needs it.
- `statusLine`: runs `statusline.ps1` to show model, context percent, and session cost under the prompt.
- `env.CLAUDE_CODE_SUBAGENT_MODEL`: `haiku` for subagents that have no model of their own. Agents with a `model` field (including `inherit`) are not affected. Remove it if delegated work comes back weak.
- `permissions.deny`: `Read(...)` rules that stop Claude reading generated, vendored, and lock files. Relative patterns with one folder name match that folder at any depth.

## Install (user scope, PowerShell)
```powershell
$kit = '<path to this kit folder>'
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\agents" | Out-Null
Copy-Item "$kit\statusline.ps1" "$env:USERPROFILE\.claude\statusline.ps1"
Copy-Item "$kit\agents\*.md" "$env:USERPROFILE\.claude\agents\"
$dest = "$env:USERPROFILE\.claude\settings.json"
$json = (Get-Content "$kit\settings.template.json" -Raw) -replace 'C:/Users/YOUR_USERNAME', ($env:USERPROFILE -replace '\\','/')
if (Test-Path $dest) { $json | Set-Content "$dest.kit-example" -Encoding ASCII; "Merge $dest.kit-example into $dest by hand" }
else { $json | Set-Content $dest -Encoding ASCII }
```
The statusline path must use forward slashes; Git Bash strips backslashes. `~` does not work when Claude Code routes the command through PowerShell, so the path is absolute.

## Notes on the deny list
- Deny rules cover Claude's file tools, `@file` mentions, and file commands it recognizes in Bash (`cat`, `head`, `tail`). They do not stop `grep -r .` or a script that opens files itself. They do not shrink the system prompt.
- `bin/**` also blocks a source folder named `bin`. If your repo keeps scripts there, remove that rule in the project file.
- Need a lock file for a dependency question? Paste the relevant lines. A deny rule wins over allow rules, so to lift it you remove it from the file that sets it.
- Large data folders: add your own, for example `"Read(data/raw/**)"` or `"Read(*.parquet)"`.
- Deny and ask rules apply at once in a project file; allow rules wait for the folder trust prompt.
