<#
.SYNOPSIS
  Measures what Claude Code loads into context for a repo and ranks it, with a fix per row.

.DESCRIPTION
  Run from (or point -Path at) a repository. Read-only: it never edits any file.
  Measures:
    - CLAUDE.md chain: managed, user, project and parent directories, CLAUDE.local.md,
      unconditional .claude/rules files, and @imports (up to 4 hops)
    - Auto memory MEMORY.md against the documented load limit (200 lines or 25 KB)
    - MCP servers: user and local scope (~/.claude.json), project .mcp.json, managed-mcp.json,
      enabled plugins. Names only; env, headers, args and URLs are never read out.
    - Skills: name + description (+ when_to_use) size for user, project and enabled plugin skills,
      against the listing budget (1 percent of the context window)
    - Subagent descriptions, enabled plugins, SessionStart hooks (count only)
    - Default model, statusLine presence, Read deny rules, secret-looking strings in allow rules
  Token estimate is chars / 4. Output never prints secret values: every string passes
  through a redaction filter, the user profile path prints as %USERPROFILE%, and the
  repo root prints as <repo>.

  Doc sources for every rule used here are listed in kit/VERIFICATION.md.

.PARAMETER Path
  Repository or working directory to audit. Default: current directory.

.PARAMETER ContextWindow
  Context window size in tokens used for budget math. Default 200000.

.PARAMETER AsObject
  Emit the result rows as objects instead of a printed report.

.PARAMETER Anonymize
  Replace MCP server, skill, and plugin names with generic labels, for sharing the report.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\context-audit.ps1 -Path C:\src\myrepo
#>
[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,
    [int]$ContextWindow = 200000,
    [switch]$AsObject,
    [switch]$Anonymize
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- helpers

$UserHome  = $env:USERPROFILE
if (-not $UserHome) { $UserHome = [Environment]::GetFolderPath('UserProfile') }
$ClaudeDir = Join-Path $UserHome '.claude'
if ($env:CLAUDE_CONFIG_DIR) { $ClaudeDir = $env:CLAUDE_CONFIG_DIR }
$ManagedDir = 'C:\Program Files\ClaudeCode'

$RepoRoot = $null
$Cwd = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
if (-not $Cwd) { Write-Error "Path not found: $Path"; exit 1 }
$Cwd = $Cwd.ProviderPath.TrimEnd('\')

function Find-RepoRoot([string]$start) {
    $d = $start
    while ($d) {
        if (Test-Path -LiteralPath (Join-Path $d '.git')) { return $d }
        $p = Split-Path -Parent $d
        if (-not $p -or $p -eq $d) { break }
        $d = $p
    }
    return $null
}
$RepoRoot = Find-RepoRoot $Cwd
$ProjectRoot = $RepoRoot
if (-not $ProjectRoot) { $ProjectRoot = $Cwd }

# Redaction: applied to every string that reaches output.
$SecretPatterns = @(
    '(?i)\b(password|passwd|pwd|secret|token|apikey|api_key|api-key|accountkey|sharedaccesskey|client_secret|access_key)\s*[=:]\s*[^\s;''",]+',
    '(?i)\b(server|data source|host)\s*=\s*[^;]+;[^"''\s]*',
    '(?i)\b[a-z][a-z0-9+.-]*://[^\s:/@]+:[^\s@/]+@[^\s''"]+',
    '(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{10,}',
    '(?i)(?<=\s)--?(password|passwd|pass|pwd|token|secret|apikey|api-key|client-secret)[=\s]+[^\s-]\S*',
    '(?-i)(?<=\s)-P\s+[^\s-]\S*',
    '\bsk-[A-Za-z0-9_-]{16,}',
    '\b(AKIA|ASIA)[A-Z0-9]{16}\b',
    '\b(ghp|gho|ghs|ghu|github_pat)_[A-Za-z0-9_]{20,}',
    '\bxox[abprs]-[A-Za-z0-9-]{10,}',
    '\b[A-Fa-f0-9]{32,}\b',
    '\b(?=[A-Za-z0-9+/]*\d)(?=[A-Za-z0-9+/]*[A-Z])(?=[A-Za-z0-9+/]*[a-z])[A-Za-z0-9+/]{40,}={0,2}'
)
function Test-Secret([string]$s) {
    if (-not $s) { return $false }
    foreach ($p in $SecretPatterns) { if ($s -match $p) { return $true } }
    return $false
}
$ProfileFwd = $UserHome -replace '\\', '/'
$ProfileKey = ($UserHome -replace '[^A-Za-z0-9]', '-')
function Protect-Text([string]$s) {
    if ($null -eq $s) { return '' }
    $o = [string]$s
    foreach ($p in $SecretPatterns) { $o = [regex]::Replace($o, $p, '[REDACTED]') }
    if ($ProjectRoot) {
        $o = $o.Replace($ProjectRoot, '<repo>')
        $o = $o.Replace(($ProjectRoot -replace '\\', '/'), '<repo>')
        $o = $o.Replace(($ProjectRoot -replace '[^A-Za-z0-9]', '-'), '<repo-key>')
    }
    $o = [regex]::Replace($o, [regex]::Escape($UserHome), '%USERPROFILE%', 'IgnoreCase')
    $o = [regex]::Replace($o, [regex]::Escape($ProfileFwd), '%USERPROFILE%', 'IgnoreCase')
    $o = [regex]::Replace($o, [regex]::Escape($ProfileKey), '%USERPROFILE-KEY%', 'IgnoreCase')
    return $o
}

# JSON reader returning dictionaries. PS 5.1 ConvertFrom-Json rejects keys that differ only
# by case (common in ~/.claude.json project paths), so use JavaScriptSerializer there.
$script:Jss = $null
if ($PSVersionTable.PSVersion.Major -lt 6) {
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $script:Jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $script:Jss.MaxJsonLength = [int]::MaxValue
        $script:Jss.RecursionLimit = 1000
    } catch { $script:Jss = $null }
}
function Read-Json([string]$file) {
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    try {
        $text = [IO.File]::ReadAllText($file)
        if (-not $text.Trim()) { return $null }
        if ($script:Jss) { return $script:Jss.DeserializeObject($text) }
        return ($text | ConvertFrom-Json -AsHashtable -ErrorAction Stop)
    } catch {
        $script:Warnings += ("Could not parse JSON: " + $file)
        return $null
    }
}
function Get-Key($obj, [string]$key) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary]) {
        if ($obj.ContainsKey($key)) { return $obj[$key] }
        return $null
    }
    return $null
}
function Get-Keys($obj) {
    if ($obj -is [System.Collections.IDictionary]) { return @($obj.Keys) }
    return @()
}
function As-List($v) {
    if ($null -eq $v) { return @() }
    if ($v -is [string]) { return @($v) }
    if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [System.Collections.IDictionary])) { return @($v) }
    return @($v)
}

function Read-Text([string]$file) {
    try { return [IO.File]::ReadAllText($file) } catch { return '' }
}
function Strip-HtmlComments([string]$t) {
    # Block HTML comments are stripped before CLAUDE.md loads (memory doc). Keep code blocks intact.
    $out = New-Object System.Text.StringBuilder
    $inFence = $false; $inComment = $false
    foreach ($line in ($t -split "`r?`n")) {
        if (-not $inComment -and $line -match '^\s*(```|~~~)') { $inFence = -not $inFence; [void]$out.AppendLine($line); continue }
        if ($inFence) { [void]$out.AppendLine($line); continue }
        $l = $line
        if ($inComment) {
            $i = $l.IndexOf('-->')
            if ($i -lt 0) { continue }
            $inComment = $false; $l = $l.Substring($i + 3)
        }
        $l = [regex]::Replace($l, '<!--.*?-->', '')
        $j = $l.IndexOf('<!--')
        if ($j -ge 0) { $inComment = $true; $l = $l.Substring(0, $j) }
        if ($line -ne $l -and -not $l.Trim()) { continue }
        [void]$out.AppendLine($l)
    }
    return $out.ToString()
}
function Measure-Text([string]$t) {
    $lines = 0
    if ($t) { $lines = ($t -split "`r?`n").Count; if ($t.EndsWith("`n")) { $lines-- } }
    return [pscustomobject]@{ Chars = $t.Length; Lines = $lines; Tokens = [int][math]::Ceiling($t.Length / 4) }
}

# Frontmatter: returns hashtable of top-level scalar keys (handles quoted, folded, literal).
function Get-Frontmatter([string]$text) {
    $h = @{}
    if (-not $text) { return $h }
    $lines = $text -split "`r?`n"
    if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { return $h }
    $i = 1; $cur = $null; $buf = $null
    while ($i -lt $lines.Count) {
        $ln = $lines[$i]
        if ($ln.Trim() -eq '---') { break }
        if ($ln -match '^([A-Za-z_][\w-]*)\s*:\s*(.*)$') {
            if ($cur) { $h[$cur] = ($buf -join ' ').Trim() }
            $cur = $matches[1]; $val = $matches[2].Trim()
            if ($val -match '^[>|][+-]?$') { $buf = @() }
            else {
                if ($val.Length -ge 2 -and (($val[0] -eq '"' -and $val[-1] -eq '"') -or ($val[0] -eq "'" -and $val[-1] -eq "'"))) { $val = $val.Substring(1, $val.Length - 2) }
                $buf = @($val)
            }
        } elseif ($cur -and $ln -match '^\s+\S') {
            $buf += $ln.Trim()
        }
        $i++
    }
    if ($cur) { $h[$cur] = ($buf -join ' ').Trim() }
    return $h
}

$script:Warnings = @()
$Rows = New-Object System.Collections.ArrayList
function Add-Row([string]$item, [string]$scope, $tokens, [string]$detail, [string]$status, [string]$fix) {
    [void]$Rows.Add([pscustomobject]@{
        Item = $item; Scope = $scope; Tokens = $tokens; Detail = $detail; Status = $status; Fix = $fix
    })
}

# ---------------------------------------------------------------- settings (all scopes)

$SettingsFiles = [ordered]@{
    'managed' = (Join-Path $ManagedDir 'managed-settings.json')
    'user'    = (Join-Path $ClaudeDir 'settings.json')
    'project' = (Join-Path $Cwd '.claude\settings.json')
    'local'   = (Join-Path $ProjectRoot '.claude\settings.local.json')
}
$Settings = [ordered]@{}
foreach ($k in $SettingsFiles.Keys) { $Settings[$k] = Read-Json $SettingsFiles[$k] }
$mdDir = Join-Path $ManagedDir 'managed-settings.d'
$ManagedDrop = @()
if (Test-Path -LiteralPath $mdDir) { $ManagedDrop = @(Get-ChildItem -LiteralPath $mdDir -Filter *.json -File -ErrorAction SilentlyContinue | ForEach-Object { Read-Json $_.FullName }) }
$AllSettings = @($Settings.Values) + $ManagedDrop | Where-Object { $_ -ne $null }

# Highest-precedence value of a top-level key: managed > local > project > user
function Get-Effective([string]$key) {
    foreach ($s in @($Settings['managed']) + $ManagedDrop + @($Settings['local'], $Settings['project'], $Settings['user'])) {
        $v = Get-Key $s $key
        if ($null -ne $v) { return $v }
    }
    return $null
}

# ---------------------------------------------------------------- 1. CLAUDE.md chain

$MemFiles = New-Object System.Collections.ArrayList   # always-loaded instruction files
$OnDemand = New-Object System.Collections.ArrayList   # path-scoped rules (not counted as always-loaded)
$Seen = @{}

function Get-Imports([string]$file, [string]$text) {
    $res = @()
    $inFence = $false
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        $l = [regex]::Replace($line, '`[^`]*`', '')
        foreach ($m in [regex]::Matches($l, '(?<![\w@/])@((?:~[\\/]|\.{1,2}[\\/]|[A-Za-z]:[\\/]|/)?[\w.\-][\w.\-\\/ ]*?\.[\w]+)')) {
            $p = $m.Groups[1].Value.Trim()
            if ($p.StartsWith('~')) { $p = Join-Path $UserHome $p.Substring(2) }
            elseif (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path (Split-Path -Parent $file) $p }
            $res += $p
        }
    }
    return $res
}

function Add-MemFile([string]$file, [string]$scope, [int]$depth, [string]$via) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return }
    $full = (Resolve-Path -LiteralPath $file).ProviderPath
    $key = $full.ToLowerInvariant()
    if ($Seen.ContainsKey($key)) { return }
    $Seen[$key] = $true
    $raw = Read-Text $full
    $fm = Get-Frontmatter $raw
    if ($fm.ContainsKey('paths') -or ($raw -match '(?m)\A---\s*\r?\n(?:.*\r?\n)*?paths\s*:')) {
        $m = Measure-Text $raw
        [void]$OnDemand.Add([pscustomobject]@{ File = $full; Scope = $scope; Chars = $m.Chars; Lines = $m.Lines; Tokens = $m.Tokens })
        return
    }
    $t = Strip-HtmlComments $raw
    $m = Measure-Text $t
    [void]$MemFiles.Add([pscustomobject]@{ File = $full; Scope = $scope; Via = $via; Chars = $m.Chars; Lines = $m.Lines; Tokens = $m.Tokens })
    if ($depth -lt 4) {
        foreach ($imp in (Get-Imports $full $t)) { Add-MemFile $imp ($scope + ' import') ($depth + 1) $full }
    }
}

Add-MemFile (Join-Path $ManagedDir 'CLAUDE.md') 'managed' 0 ''
Add-MemFile (Join-Path $ClaudeDir 'CLAUDE.md') 'user' 0 ''
$ur = Join-Path $ClaudeDir 'rules'
if (Test-Path -LiteralPath $ur) { Get-ChildItem -LiteralPath $ur -Recurse -Filter *.md -File -ErrorAction SilentlyContinue | ForEach-Object { Add-MemFile $_.FullName 'user rules' 0 '' } }

# Working dir and every parent: CLAUDE.md, .claude/CLAUDE.md, CLAUDE.local.md (root first)
$chain = @(); $d = $Cwd
while ($d) { $chain += $d; $p = Split-Path -Parent $d; if (-not $p -or $p -eq $d) { break }; $d = $p }
[array]::Reverse($chain)
$foundProjectMd = $false
foreach ($dir in $chain) {
    $sc = 'parent dir'
    if ($dir -eq $ProjectRoot -or $dir -eq $Cwd) { $sc = 'project' }
    foreach ($n in 'CLAUDE.md', '.claude\CLAUDE.md', 'CLAUDE.local.md') {
        $f = Join-Path $dir $n
        if (Test-Path -LiteralPath $f -PathType Leaf) { $foundProjectMd = $true; Add-MemFile $f $sc 0 '' }
    }
}
$pr = Join-Path $Cwd '.claude\rules'
if (Test-Path -LiteralPath $pr) { Get-ChildItem -LiteralPath $pr -Recurse -Filter *.md -File -ErrorAction SilentlyContinue | ForEach-Object { Add-MemFile $_.FullName 'project rules' 0 '' } }
if (-not $foundProjectMd) {
    $ag = Join-Path $Cwd 'AGENTS.md'
    if (Test-Path -LiteralPath $ag -PathType Leaf) { Add-MemFile $ag 'project AGENTS.md' 0 '' }
}

$memTok = ($MemFiles | Measure-Object -Property Tokens -Sum).Sum; if (-not $memTok) { $memTok = 0 }
$memChars = ($MemFiles | Measure-Object -Property Chars -Sum).Sum; if (-not $memChars) { $memChars = 0 }
$big = @($MemFiles | Where-Object { $_.Lines -gt 200 })
$imports = @($MemFiles | Where-Object { $_.Scope -like '*import' })
$st = 'OK'; if ($big.Count -gt 0) { $st = 'OVER' } elseif ($memTok -gt 3000) { $st = 'WARN' }
$fix = 'Keep each CLAUDE.md under 200 lines (kit template budget: 60). Move area rules to .claude/rules with paths:, procedures to skills.'
if ($imports.Count -gt 0) { $fix += ' Imports load at launch too; turn rarely needed @imports into plain pointers.' }
Add-Row 'CLAUDE.md chain + imports' 'every session' $memTok ("{0} files, {1} chars, {2} imported, {3} over 200 lines" -f $MemFiles.Count, $memChars, $imports.Count, $big.Count) $st $fix

# ---------------------------------------------------------------- 2. Auto memory

$memKey = ($ProjectRoot -replace '[^A-Za-z0-9]', '-')
$memDir = Join-Path $ClaudeDir ("projects\" + $memKey + "\memory")
$memIdx = Join-Path $memDir 'MEMORY.md'
$amDisabled = ($env:CLAUDE_CODE_DISABLE_AUTO_MEMORY -eq '1') -or ((Get-Effective 'autoMemoryEnabled') -eq $false)
if ($amDisabled) {
    Add-Row 'Auto memory MEMORY.md' 'every session' 0 'auto memory disabled' 'OK' 'None needed.'
} elseif (Test-Path -LiteralPath $memIdx -PathType Leaf) {
    $raw = Read-Text $memIdx
    $bytes = (Get-Item -LiteralPath $memIdx).Length
    $all = $raw -split "`r?`n"
    $lineCount = $all.Count
    $loadedLines = [math]::Min($lineCount, 200)
    $loadedText = ($all[0..($loadedLines - 1)] -join "`n")
    if ($loadedText.Length -gt 25600) { $loadedText = $loadedText.Substring(0, 25600) }
    $tok = [int][math]::Ceiling($loadedText.Length / 4)
    $leaf = @(Get-ChildItem -LiteralPath $memDir -Filter *.md -File -ErrorAction SilentlyContinue).Count - 1
    $st = 'OK'; if ($lineCount -gt 200 -or $bytes -gt 25600) { $st = 'OVER' } elseif ($lineCount -gt 150 -or $bytes -gt 19200) { $st = 'WARN' }
    Add-Row 'Auto memory MEMORY.md' 'every session' $tok ("{0} lines, {1} bytes (limit 200 lines or 25 KB); {2} topic files load on demand" -f $lineCount, $bytes, $leaf) $st 'Keep MEMORY.md a one-line-per-entry index well under the limit; content past it is silently dropped. Move detail to topic files.'
} else {
    Add-Row 'Auto memory MEMORY.md' 'every session' 0 'no MEMORY.md for this repo' 'OK' 'None needed.'
}

# ---------------------------------------------------------------- 3. Plugins

$Installed = Read-Json (Join-Path $ClaudeDir 'plugins\installed_plugins.json')
$EnabledMap = @{}
foreach ($s in @($Settings['user'], $Settings['project'], $Settings['local'], $Settings['managed']) + $ManagedDrop) {
    $ep = Get-Key $s 'enabledPlugins'
    foreach ($id in (Get-Keys $ep)) { $EnabledMap[$id] = [bool]$ep[$id] }
}
$PluginDirs = @()
$instPlugins = Get-Key $Installed 'plugins'
foreach ($id in (Get-Keys $instPlugins)) {
    $on = $true
    if ($EnabledMap.ContainsKey($id)) { $on = $EnabledMap[$id] }
    if (-not $on) { continue }
    $recs = As-List $instPlugins[$id]
    $rec = $recs | Select-Object -Last 1
    $ip = Get-Key $rec 'installPath'
    if ($ip -and (Test-Path -LiteralPath $ip)) { $PluginDirs += [pscustomobject]@{ Id = $id; Dir = $ip } }
}
$syncedDir = Join-Path $ClaudeDir 'plugins\synced'
if (Test-Path -LiteralPath $syncedDir) {
    Get-ChildItem -LiteralPath $syncedDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $id = $_.Name + '@synced'
        if (-not ($EnabledMap.ContainsKey($id) -and -not $EnabledMap[$id])) { $PluginDirs += [pscustomobject]@{ Id = $id; Dir = $_.FullName } }
    }
}
$instCount = (Get-Keys $instPlugins).Count

# Marketplace entries that list specific skills: only those load (plugins loading doc).
$Known = Read-Json (Join-Path $ClaudeDir 'plugins\known_marketplaces.json')
function Get-EntrySkills([string]$id) {
    $parts = $id -split '@'
    if ($parts.Count -lt 2) { return $null }
    $mk = Get-Key $Known $parts[1]
    $loc = Get-Key $mk 'installLocation'
    if (-not $loc) { return $null }
    $mj = Read-Json (Join-Path $loc '.claude-plugin\marketplace.json')
    foreach ($e in (As-List (Get-Key $mj 'plugins'))) {
        if ((Get-Key $e 'name') -eq $parts[0]) {
            $sk = Get-Key $e 'skills'
            if ($sk) { return @(As-List $sk) }
        }
    }
    return $null
}

# ---------------------------------------------------------------- 4. MCP servers (names only)

$Mcp = New-Object System.Collections.ArrayList
$cj = Read-Json (Join-Path $UserHome '.claude.json')
foreach ($n in (Get-Keys (Get-Key $cj 'mcpServers'))) { [void]$Mcp.Add([pscustomobject]@{ Name = $n; Scope = 'user' }) }
$projs = Get-Key $cj 'projects'
$want = @(($ProjectRoot -replace '\\', '/'), ($Cwd -replace '\\', '/'))
foreach ($pk in (Get-Keys $projs)) {
    foreach ($w in $want) {
        if ($pk.TrimEnd('/') -ieq $w.TrimEnd('/')) {
            foreach ($n in (Get-Keys (Get-Key $projs[$pk] 'mcpServers'))) { [void]$Mcp.Add([pscustomobject]@{ Name = $n; Scope = 'local' }) }
        }
    }
}
$disabledProj = @()
foreach ($s in $AllSettings) { $disabledProj += As-List (Get-Key $s 'disabledMcpjsonServers') }
$pm = Read-Json (Join-Path $ProjectRoot '.mcp.json')
foreach ($n in (Get-Keys (Get-Key $pm 'mcpServers'))) {
    $sc = 'project .mcp.json'; if ($disabledProj -contains $n) { $sc = 'project .mcp.json (disabled)' }
    [void]$Mcp.Add([pscustomobject]@{ Name = $n; Scope = $sc })
}
$mm = Read-Json (Join-Path $ManagedDir 'managed-mcp.json')
foreach ($n in (Get-Keys (Get-Key $mm 'mcpServers'))) { [void]$Mcp.Add([pscustomobject]@{ Name = $n; Scope = 'managed' }) }
foreach ($pd in $PluginDirs) {
    $pj = Read-Json (Join-Path $pd.Dir '.mcp.json')
    $srv = Get-Key $pj 'mcpServers'; if (-not $srv) { $srv = $pj }
    foreach ($n in (Get-Keys $srv)) { [void]$Mcp.Add([pscustomobject]@{ Name = $n; Scope = ('plugin ' + ($pd.Id -split '@')[0]) }) }
    $man = Read-Json (Join-Path $pd.Dir '.claude-plugin\plugin.json')
    $ms = Get-Key $man 'mcpServers'
    if ($ms -is [System.Collections.IDictionary]) { foreach ($n in (Get-Keys $ms)) { [void]$Mcp.Add([pscustomobject]@{ Name = $n; Scope = ('plugin ' + ($pd.Id -split '@')[0]) }) } }
}
$Mcp = @($Mcp | Sort-Object Scope, Name -Unique)
$activeMcp = @($Mcp | Where-Object { $_.Scope -notlike '*disabled*' })
$userMcp = @($activeMcp | Where-Object { $_.Scope -eq 'user' }).Count
$mcpTok = $activeMcp.Count * 40   # rough: deferred tool names plus server instructions; real cost varies
$st = 'OK'; if ($activeMcp.Count -gt 6 -or $userMcp -gt 3) { $st = 'WARN' }
Add-Row 'MCP servers' 'every session' $mcpTok ("{0} active ({1} user scope); tool names load, schemas deferred. Estimate only: run /context for the real figure" -f $activeMcp.Count, $userMcp) $st 'Keep user scope to 1 or 2 servers; add the rest per project (.mcp.json or local scope). Remove servers that fail to connect.'

# ---------------------------------------------------------------- 5. Skills and subagent descriptions

$Overrides = @{}
foreach ($s in @($Settings['user'], $Settings['project'], $Settings['local'], $Settings['managed'])) {
    $so = Get-Key $s 'skillOverrides'
    foreach ($k in (Get-Keys $so)) { $Overrides[$k] = [string]$so[$k] }
}
$Skills = New-Object System.Collections.ArrayList
function Add-SkillDir([string]$root, [string]$scope, [string]$prefix) {
    if (-not (Test-Path -LiteralPath $root)) { return }
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -Filter SKILL.md -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName.Substring($root.Length).Split('\').Count -le 4 })
    foreach ($f in $files) {
        $fm = Get-Frontmatter (Read-Text $f.FullName)
        $name = $fm['name']; if (-not $name) { $name = $f.Directory.Name }
        $full = $name; if ($prefix) { $full = $prefix + ':' + $name }
        $desc = [string]$fm['description']; $wtu = [string]$fm['when_to_use']
        $text = ($desc + ' ' + $wtu).Trim()
        if ($text.Length -gt 1536) { $text = $text.Substring(0, 1536) }
        $mode = 'listed'
        if ($fm['disable-model-invocation'] -match '^(?i)true$') { $mode = 'hidden (disable-model-invocation)' }
        $ov = $null
        if ($Overrides.ContainsKey($full)) { $ov = $Overrides[$full] } elseif ($Overrides.ContainsKey($name)) { $ov = $Overrides[$name] }
        if ($ov -in 'off', 'user-invocable-only', 'user-only') { $mode = 'hidden (skillOverrides)' }
        $chars = 0
        if ($mode -eq 'listed') { $chars = $full.Length + $text.Length + 4 }
        if ($ov -eq 'name-only') { $mode = 'name-only'; $chars = $full.Length + 4 }
        [void]$Skills.Add([pscustomobject]@{ Name = $full; Scope = $scope; Mode = $mode; DescChars = $text.Length; Chars = $chars })
    }
}
Add-SkillDir (Join-Path $ClaudeDir 'skills') 'user' ''
$sd = $Cwd
while ($sd) {
    Add-SkillDir (Join-Path $sd '.claude\skills') 'project' ''
    if ($RepoRoot -and $sd -eq $RepoRoot) { break }
    if (-not $RepoRoot) { break }
    $p = Split-Path -Parent $sd; if (-not $p -or $p -eq $sd) { break }; $sd = $p
}
foreach ($pd in $PluginDirs) {
    $pn = ($pd.Id -split '@')[0]
    $man = Read-Json (Join-Path $pd.Dir '.claude-plugin\plugin.json')
    $mn = Get-Key $man 'name'; if ($mn) { $pn = $mn }
    $entrySkills = Get-EntrySkills $pd.Id
    if ($entrySkills) {
        foreach ($rel in $entrySkills) { Add-SkillDir (Join-Path $pd.Dir (($rel -replace '^\./', '') -replace '/', '\')) ('plugin ' + $pn) $pn }
        continue
    }
    Add-SkillDir (Join-Path $pd.Dir 'skills') ('plugin ' + $pn) $pn
    if (-not (Test-Path -LiteralPath (Join-Path $pd.Dir 'skills')) -and (Test-Path -LiteralPath (Join-Path $pd.Dir 'SKILL.md'))) {
        $fm = Get-Frontmatter (Read-Text (Join-Path $pd.Dir 'SKILL.md'))
        $t = ([string]$fm['description']).Trim()
        [void]$Skills.Add([pscustomobject]@{ Name = $pn; Scope = ('plugin ' + $pn); Mode = 'listed'; DescChars = $t.Length; Chars = $pn.Length + $t.Length + 4 })
    }
}
$skChars = ($Skills | Measure-Object -Property Chars -Sum).Sum; if (-not $skChars) { $skChars = 0 }
$listed = @($Skills | Where-Object { $_.Mode -ne 'hidden (disable-model-invocation)' -and $_.Mode -ne 'hidden (skillOverrides)' })
$budgetChars = [int]($ContextWindow * 0.01 * 4)
$longDesc = @($Skills | Where-Object { $_.Mode -eq 'listed' -and $_.DescChars -gt 400 }).Count
$st = 'OK'; if ($skChars -gt $budgetChars) { $st = 'OVER' } elseif ($skChars -gt 0.75 * $budgetChars) { $st = 'WARN' }
Add-Row 'Skill listing' 'every session' ([int][math]::Ceiling($skChars / 4)) ("{0} skills, {1} listed, {2} chars vs budget ~{3} chars (1% of {4} tokens); {5} descriptions over 400 chars" -f $Skills.Count, $listed.Count, $skChars, $budgetChars, $ContextWindow, $longDesc) $st 'Enable plugins per project, not globally; set skillOverrides "off" or "name-only" for skills you never use; trim descriptions to 1 or 2 sentences.'

$Agents = New-Object System.Collections.ArrayList
function Add-AgentDir([string]$root, [string]$scope) {
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.md -File -ErrorAction SilentlyContinue)) {
        $fm = Get-Frontmatter (Read-Text $f.FullName)
        if (-not $fm['name'] -and -not $fm['description']) { continue }
        $c = ([string]$fm['name']).Length + ([string]$fm['description']).Length + 4
        [void]$Agents.Add([pscustomobject]@{ Name = $fm['name']; Scope = $scope; Model = $fm['model']; Chars = $c })
    }
}
Add-AgentDir (Join-Path $ClaudeDir 'agents') 'user'
Add-AgentDir (Join-Path $Cwd '.claude\agents') 'project'
foreach ($pd in $PluginDirs) { Add-AgentDir (Join-Path $pd.Dir 'agents') ('plugin ' + ($pd.Id -split '@')[0]) }
$agChars = ($Agents | Measure-Object -Property Chars -Sum).Sum; if (-not $agChars) { $agChars = 0 }
$cheap = @($Agents | Where-Object { $_.Model -eq 'haiku' }).Count
$st = 'OK'; if ($Agents.Count -gt 0 -and $cheap -eq 0) { $st = 'WARN' }
if ($Agents.Count -eq 0) { $st = 'WARN' }
Add-Row 'Subagent definitions' 'every session' ([int][math]::Ceiling($agChars / 4)) ("{0} custom agents, {1} pinned to haiku" -f $Agents.Count, $cheap) $st 'Install the kit agents (code-search, log-summarizer, docs-lookup) pinned to haiku and delegate broad reads to them.'

# ---------------------------------------------------------------- 6. Hooks (SessionStart count only)

$ssCount = 0; $hookEvents = 0
function Count-SessionStart($hooksObj) {
    $n = 0
    foreach ($grp in (As-List (Get-Key $hooksObj 'SessionStart'))) { $n += @(As-List (Get-Key $grp 'hooks')).Count }
    return $n
}
foreach ($s in $AllSettings) {
    $h = Get-Key $s 'hooks'
    $ssCount += Count-SessionStart $h
    $hookEvents += (Get-Keys $h).Count
}
foreach ($pd in $PluginDirs) {
    $hj = Read-Json (Join-Path $pd.Dir 'hooks\hooks.json')
    $h = Get-Key $hj 'hooks'
    $ssCount += Count-SessionStart $h
    $hookEvents += (Get-Keys $h).Count
}
$st = 'OK'; if ($ssCount -gt 2) { $st = 'WARN' }
Add-Row 'SessionStart hooks' 'every session' '?' ("{0} SessionStart handlers; {1} hook event entries in total (settings + enabled plugins)" -f $ssCount, $hookEvents) $st 'SessionStart stdout is added to context: cap each hook output (about 2,000 chars), set a timeout, and drop hooks you do not need.'

# ---------------------------------------------------------------- 7. Plugins row

$enabledCount = $PluginDirs.Count
$st = 'OK'; if ($enabledCount -gt 5) { $st = 'WARN' }
Add-Row 'Plugins enabled' 'every session' '-' ("{0} enabled of {1} installed (skills, agents, hooks, MCP counted above)" -f $enabledCount, $instCount) $st 'Disable plugins at user scope and enable them in the project .claude/settings.json that needs them.'

# ---------------------------------------------------------------- 8. Config checks (no token cost, but they steer cost)

$model = Get-Effective 'model'
if ($env:ANTHROPIC_MODEL) { $model = $env:ANTHROPIC_MODEL + ' (ANTHROPIC_MODEL)' }
$st = 'OK'; $fx = 'None needed.'
if (-not $model) { $st = 'WARN'; $model = 'not set (account default)'; $fx = 'Set "model": "sonnet" and switch up with /model only when a task needs it.' }
elseif ($model -match '(?i)opus|fable|best|\[1m\]') { $st = 'WARN'; $fx = 'Default to sonnet; use /model opus per task. Larger models and 1M context cost more per token.' }
Add-Row 'Default model' 'config' '-' ([string]$model) $st $fx

$sl = Get-Effective 'statusLine'
$st = 'OK'; $fx = 'None needed.'; $dt = 'configured'
if (-not $sl) { $st = 'WARN'; $dt = 'none'; $fx = 'Install kit/statusline.ps1 so context percent and session cost are always visible.' }
Add-Row 'Status line' 'config' '-' $dt $st $fx

$deny = @(); $allow = @()
foreach ($s in $AllSettings) {
    $pp = Get-Key $s 'permissions'
    $deny += As-List (Get-Key $pp 'deny')
    $allow += As-List (Get-Key $pp 'allow')
}
$readDeny = @($deny | Where-Object { $_ -like 'Read(*' })
$heavy = 'node_modules', 'dist', 'build', 'bin', 'obj', '.git', 'coverage'
$missing = @($heavy | Where-Object { $h = $_; -not ($readDeny | Where-Object { $_ -like "*$h*" }) })
$st = 'OK'; if ($missing.Count -gt 0) { $st = 'WARN' }
$dt = "{0} Read deny rules; heavy dirs not covered: {1}" -f $readDeny.Count, ($(if ($missing.Count) { $missing -join ', ' } else { 'none' }))
Add-Row 'Read deny rules' 'config' '-' $dt $st 'Add the kit permissions.deny list (node_modules, bin, obj, dist, build, .git, coverage, lock files).'

$secretAllow = @($allow | Where-Object { Test-Secret ([string]$_) }).Count
$st = 'OK'; $fx = 'None needed.'
if ($secretAllow -gt 0) { $st = 'RISK'; $fx = 'Delete those allow rules and rotate the exposed values; pass secrets through env or a secrets manager, never inline on the command line.' }
elseif ($allow.Count -gt 60) { $st = 'WARN'; $fx = 'Prune the allow list; it grows from repeated "always allow" clicks.' }
Add-Row 'Allow rules hygiene' 'config' '-' ("{0} allow rules; {1} contain secret-like strings (values not shown)" -f $allow.Count, $secretAllow) $st $fx

# ---------------------------------------------------------------- output

$sevOrder = @{ 'RISK' = 0; 'OVER' = 1; 'WARN' = 2; 'OK' = 3 }
$sorted = @($Rows | Sort-Object -Property `
    @{ Expression = { if ($_.Tokens -is [string]) { 1 } else { 0 } } }, `
    @{ Expression = { if ($_.Tokens -is [string]) { 0 } else { [double]$_.Tokens } }; Descending = $true }, `
    @{ Expression = { $sevOrder[$_.Status] } })
$i = 0
foreach ($r in $sorted) { $i++; $r | Add-Member -NotePropertyName Rank -NotePropertyValue $i -Force }

$script:AnonMap = @{}
function Anon([string]$kind, [string]$name) {
    if (-not $Anonymize) { return $name }
    $k = $kind + '|' + $name
    if (-not $script:AnonMap.ContainsKey($k)) { $script:AnonMap[$k] = $kind + '-' + ($script:AnonMap.Keys | Where-Object { $_ -like ($kind + '|*') }).Count }
    return $script:AnonMap[$k]
}
function Anon-Scope([string]$scope) {
    if ($scope -like 'plugin *') { return 'plugin ' + (Anon 'plugin' $scope.Substring(7)) }
    return $scope
}

if ($AsObject) {
    $sorted | ForEach-Object {
        [pscustomobject]@{ Rank = $_.Rank; Item = $_.Item; Load = $_.Scope; ApproxTokens = $_.Tokens; Status = $_.Status; Detail = (Protect-Text $_.Detail); Fix = (Protect-Text $_.Fix) }
    }
    return
}

$alwaysTok = 0
foreach ($r in $sorted) { if ($r.Scope -eq 'every session' -and ($r.Tokens -is [int] -or $r.Tokens -is [long] -or $r.Tokens -is [double])) { $alwaysTok += [double]$r.Tokens } }

Write-Output ''
Write-Output ('Claude Code context audit   repo: ' + (Protect-Text $ProjectRoot) + '   PowerShell ' + $PSVersionTable.PSVersion.ToString())
Write-Output ('Approx tokens loaded before your first prompt (measured items, chars/4): ' + [int]$alwaysTok + '   (system prompt and built-in tools not included; /context shows the full picture)')
Write-Output ''
Write-Output ('{0,-4} {1,-27} {2,-7} {3,8}  {4}' -f '#', 'Item', 'Status', '~Tokens', 'Detail')
Write-Output ('{0,-4} {1,-27} {2,-7} {3,8}  {4}' -f '--', '----', '------', '-------', '------')
foreach ($r in $sorted) {
    Write-Output ('{0,-4} {1,-27} {2,-7} {3,8}  {4}' -f $r.Rank, $r.Item, $r.Status, $r.Tokens, (Protect-Text $r.Detail))
    Write-Output ('     fix: ' + (Protect-Text $r.Fix))
}

Write-Output ''
Write-Output 'Instruction files (always loaded), largest first:'
if ($MemFiles.Count -eq 0) { Write-Output '  none' }
foreach ($f in @($MemFiles | Sort-Object Tokens -Descending)) {
    $flag = ''; if ($f.Lines -gt 200) { $flag = '  OVER 200 LINES' } elseif ($f.Lines -gt 60) { $flag = '  over kit budget (60)' }
    Write-Output ('  {0,6} tok {1,5} lines  {2,-14} {3}{4}' -f $f.Tokens, $f.Lines, $f.Scope, (Protect-Text $f.File), $flag)
}
if ($OnDemand.Count -gt 0) {
    Write-Output ('Path-scoped rules (load only for matching files): {0} files, {1} tokens' -f $OnDemand.Count, (($OnDemand | Measure-Object Tokens -Sum).Sum))
}

Write-Output ''
Write-Output 'MCP servers (names only):'
if ($Mcp.Count -eq 0) { Write-Output '  none' }
foreach ($g in @($Mcp | Group-Object Scope)) { Write-Output ('  {0}: {1}' -f (Anon-Scope $g.Name), (Protect-Text (($g.Group | ForEach-Object { Anon 'mcp' $_.Name }) -join ', '))) }

Write-Output ''
Write-Output 'Largest skill listing entries:'
$topSk = @($Skills | Where-Object { $_.Chars -gt 0 } | Sort-Object Chars -Descending | Select-Object -First 10)
if ($topSk.Count -eq 0) { Write-Output '  none' }
foreach ($s in $topSk) { Write-Output ('  {0,5} chars  {1,-22} {2}' -f $s.Chars, (Anon-Scope $s.Scope), (Protect-Text (Anon 'skill' $s.Name))) }
$byScope = @($Skills | Group-Object Scope | Sort-Object { ($_.Group | Measure-Object Chars -Sum).Sum } -Descending)
Write-Output 'Skill listing by source:'
foreach ($g in $byScope) { Write-Output ('  {0,6} chars  {1,3} skills  {2}' -f (($g.Group | Measure-Object Chars -Sum).Sum), $g.Count, (Protect-Text (Anon-Scope $g.Name))) }

if ($script:Warnings.Count -gt 0) {
    Write-Output ''
    Write-Output 'Warnings:'
    foreach ($w in $script:Warnings) { Write-Output ('  ' + (Protect-Text $w)) }
}
Write-Output ''
Write-Output 'Notes: token figures are estimates (chars/4). MCP cost is a rough per-server figure. Verify with /context and /doctor inside Claude Code.'
