<#
.SYNOPSIS
  Validate and package streck-lean: the plugin copies and the Claude.ai skill zips.

.DESCRIPTION
  1. Parses plugin\.claude-plugin\plugin.json and .claude-plugin\marketplace.json.
     Checks that the plugin is named streck-lean, the marketplace lists exactly
     that one plugin with source ./plugin, and version is MAJOR.MINOR.PATCH.
  2. Validates each skill in skills\ against the footprint in the build contract:
     SKILL.md present (exact case), frontmatter name equals the folder name and
     matches ^[a-z0-9-]{1,64}$, description at most 400 characters, starts with
     "Use when", contains "Not for:", body at most 120 lines. Warns when the body
     is over 1,600 tokens (estimated as characters / 4).
  3. Validates each subagent in kit\agents\: frontmatter with name (equal to the
     file name), description, and model. Warns on fields a plugin agent ignores
     (permissionMode, hooks, mcpServers, initialPrompt).
  4. Scans every shipped text file for em dashes, en dashes, and any other
     non-ASCII character: README.md, CHANGELOG.md, RESULTS.md, docs\, skills\,
     kit\, plugin\ (except the generated skills\ and agents\), .claude-plugin\,
     scripts\, and tests\token\ (except raw run output under tests\token\results\;
     the summary .md files there are scanned).
  5. Stages the skills and agents in a temp folder, copies them to plugin\skills\
     and plugin\agents\, and builds dist\claude-ai\<skill>-<version>.zip for each
     skill. Each zip has one top-level folder <skill>\ containing SKILL.md.
     lean-chat is the Claude.ai skill; lean-code is meant for Claude Code but is
     zipped too, since uploading it does no harm. Only zips for these two skills
     are replaced; other files in dist\claude-ai\ are left alone.
  6. Runs "claude plugin validate --strict" on the repo root (marketplace) and on
     plugin\ when the Claude Code CLI is on PATH. Warns if it is not.

  -Check builds the staged copy only, compares it with plugin\skills\ and
  plugin\agents\ (and with any dist\claude-ai zips for the current version),
  writes nothing to the repo, and exits 1 on any difference. Use it before a
  commit or in CI.

  Source folders (skills\, kit\) are never modified.
  Compatible with Windows PowerShell 5.1 and PowerShell 7.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\package.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\package.ps1 -Check
#>
[CmdletBinding()]
param(
    [switch]$Check
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Root         = Split-Path -Parent $PSScriptRoot
$SkillsDir    = Join-Path $Root 'skills'
$AgentsSrc    = Join-Path $Root 'kit\agents'
$PluginDir    = Join-Path $Root 'plugin'
$PluginSkills = Join-Path $PluginDir 'skills'
$PluginAgents = Join-Path $PluginDir 'agents'
$PluginJson   = Join-Path $PluginDir '.claude-plugin\plugin.json'
$MarketJson   = Join-Path $Root '.claude-plugin\marketplace.json'
$DistDir      = Join-Path $Root 'dist\claude-ai'

$PluginName     = 'streck-lean'
$ExpectedSkills = @('lean-chat', 'lean-code')
$Surface        = @{ 'lean-chat' = 'Claude.ai and Code'; 'lean-code' = 'Claude Code' }
$NamePattern    = '^[a-z0-9-]{1,64}$'
$MaxDescription = 400
$MaxBodyLines   = 120
$WarnBodyTokens = 1600
$IgnoredAgentFields = @('permissionMode', 'hooks', 'mcpServers', 'initialPrompt')
$BinaryExt = @('.png', '.jpg', '.jpeg', '.gif', '.zip', '.pdf', '.ico')

# Dash characters built from code points so this script stays pure ASCII.
$EmDash = [string][char]0x2014
$EnDash = [string][char]0x2013

$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Errors = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
    $script:Errors.Add($Message)
    Write-Host "  FAIL  $Message" -ForegroundColor Red
}

function Write-Warn([string]$Message) {
    Write-Host "  WARN  $Message" -ForegroundColor Yellow
}

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, $script:Utf8)
}

function Get-RelPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($script:Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($script:Root.Length).TrimStart('\', '/')
    }
    return $full
}

function Test-Under([string]$Path, [string]$Folder) {
    return $Path.StartsWith($Folder.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-ShippedText([string]$Path) {
    # Fails on em dash, en dash, and any other non-ASCII character (emoji, smart quotes).
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($script:BinaryExt -contains $ext) { return }
    $lines = [System.IO.File]::ReadAllLines($Path, $script:Utf8)
    $rel = Get-RelPath $Path
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line.Contains($script:EmDash)) { Add-Failure ("{0}:{1} contains an em dash (U+2014)" -f $rel, ($i + 1)); continue }
        if ($line.Contains($script:EnDash)) { Add-Failure ("{0}:{1} contains an en dash (U+2013)" -f $rel, ($i + 1)); continue }
        if ($line -match '[^\x00-\x7F]') {
            $cp = [int][char]($Matches[0][0])
            Add-Failure ("{0}:{1} contains a non-ASCII character (U+{2:X4})" -f $rel, ($i + 1), $cp)
        }
    }
}

function Split-Frontmatter([string]$Text) {
    # Returns @{ Fm = hashtable of top-level key: value; Body = string[] } or $null if no frontmatter.
    $lines = $Text -split "\r?\n"
    if ($lines.Length -lt 3 -or $lines[0].Trim() -ne '---') { return $null }
    $end = -1
    for ($i = 1; $i -lt $lines.Length; $i++) {
        if ($lines[$i].Trim() -eq '---') { $end = $i; break }
    }
    if ($end -lt 0) { return $null }
    $fm = @{}
    $currentKey = $null
    for ($i = 1; $i -lt $end; $i++) {
        $line = $lines[$i]
        if ($line -match '^([A-Za-z0-9_-]+):\s*(.*)$') {
            $currentKey = $Matches[1]
            $fm[$currentKey] = $Matches[2].Trim()
        } elseif ($currentKey -and $line -match '^\s+\S') {
            $fm[$currentKey] = ($fm[$currentKey] + ' ' + $line.Trim()).Trim()
        }
    }
    foreach ($k in @($fm.Keys)) {
        $v = $fm[$k]
        if ($v -match '^[>|][-+]?$') { $v = '' }
        if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $fm[$k] = $v
    }
    $body = @()
    if ($end + 1 -lt $lines.Length) { $body = @($lines[($end + 1)..($lines.Length - 1)]) }
    # Drop one trailing empty element left by a final newline.
    if ($body.Count -gt 0 -and $body[$body.Count - 1] -eq '') {
        if ($body.Count -eq 1) { $body = @() } else { $body = @($body[0..($body.Count - 2)]) }
    }
    return @{ Fm = $fm; Body = $body }
}

function Read-Json([string]$Path) {
    if (-not (Test-Path $Path -PathType Leaf)) { Add-Failure "$(Get-RelPath $Path) is missing"; return $null }
    try { return (Read-Text $Path | ConvertFrom-Json) }
    catch { Add-Failure "$(Get-RelPath $Path) is not valid JSON: $($_.Exception.Message)"; return $null }
}

function Get-TreeHashes([string]$Folder) {
    # Map of relative path (forward slashes) to SHA256 for every file under Folder.
    $map = @{}
    if (-not (Test-Path $Folder -PathType Container)) { return $map }
    $base = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\')
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($f in @(Get-ChildItem -Path $Folder -Recurse -File -Force)) {
            $rel = $f.FullName.Substring($base.Length).TrimStart('\').Replace('\', '/')
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            $map[$rel] = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
        }
    } finally { $sha.Dispose() }
    return $map
}

function Compare-Trees([hashtable]$Expected, [hashtable]$Actual, [string]$Label) {
    $n = 0
    foreach ($k in ($Expected.Keys | Sort-Object)) {
        if (-not $Actual.ContainsKey($k)) { Add-Failure "$Label is missing $k"; $n++ }
        elseif ($Actual[$k] -ne $Expected[$k]) { Add-Failure "$Label has a stale $k"; $n++ }
    }
    foreach ($k in ($Actual.Keys | Sort-Object)) {
        if (-not $Expected.ContainsKey($k)) { Add-Failure "$Label has an extra file $k"; $n++ }
    }
    return $n
}

function New-SkillZip([string]$SourceFolder, [string]$SkillName, [string]$ZipPath) {
    # Built entry by entry so paths use forward slashes. Compress-Archive on
    # Windows PowerShell 5.1 writes backslash separators, which non-Windows
    # unzip tools (and web uploaders) can misread as flat file names.
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $base = [System.IO.Path]::GetFullPath($SourceFolder).TrimEnd('\')
        Get-ChildItem -Path $SourceFolder -Recurse -File | Sort-Object FullName | ForEach-Object {
            $rel = $_.FullName.Substring($base.Length).TrimStart('\').Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $_.FullName, "$SkillName/$rel", [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally {
        $zip.Dispose()
    }
}

function Get-ZipHashes([string]$ZipPath) {
    $map = @{}
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $z = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($e in $z.Entries) {
            if ($e.FullName.EndsWith('/')) { continue }
            $s = $e.Open()
            try { $map[$e.FullName] = ([System.BitConverter]::ToString($sha.ComputeHash($s))).Replace('-', '') }
            finally { $s.Dispose() }
        }
    } finally { $z.Dispose(); $sha.Dispose() }
    return $map
}

function Invoke-ClaudeValidate([string]$Target) {
    # Returns $true on pass. Native stderr must not become a terminating error under 5.1.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & claude plugin validate $Target --strict 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    foreach ($l in $out) {
        # Console output may carry check marks; keep this script's own output ASCII.
        $t = ($l -replace '[^\x20-\x7E]', '').Trim()
        if ($t) { Write-Host "        $t" }
    }
    return ($code -eq 0)
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Mode = $(if ($Check) { 'check (no writes)' } else { 'build' })
Write-Host ''
Write-Host "streck-lean packaging: $Mode" -ForegroundColor Cyan
Write-Host "Root: $Root"
Write-Host "PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
Write-Host ''

# ---------------------------------------------------------------- manifests
Write-Host 'Validating manifests' -ForegroundColor Cyan
$Version = $null
$plugin = Read-Json $PluginJson
$market = Read-Json $MarketJson
$beforeManifest = $Errors.Count
if ($null -ne $plugin) {
    $props = @($plugin.PSObject.Properties.Name)
    if (-not ($props -contains 'name')) { Add-Failure 'plugin.json has no name' }
    elseif ([string]$plugin.name -cne $PluginName) { Add-Failure "plugin.json name is '$($plugin.name)', expected '$PluginName'" }
    if (-not ($props -contains 'version')) { Add-Failure 'plugin.json has no version' }
    elseif ([string]$plugin.version -notmatch '^\d+\.\d+\.\d+$') { Add-Failure "plugin.json version '$($plugin.version)' is not MAJOR.MINOR.PATCH" }
    else { $Version = [string]$plugin.version }
    foreach ($k in @('description', 'author')) { if (-not ($props -contains $k)) { Add-Failure "plugin.json has no $k" } }
}
if ($null -ne $market) {
    foreach ($k in @('name', 'owner', 'plugins')) {
        if (-not (@($market.PSObject.Properties.Name) -contains $k)) { Add-Failure "marketplace.json has no $k" }
    }
    $entries = @()
    if (@($market.PSObject.Properties.Name) -contains 'plugins') { $entries = @($market.plugins) }
    if ($entries.Count -ne 1) { Add-Failure "marketplace.json should list exactly one plugin; found $($entries.Count)" }
    else {
        $e = $entries[0]
        if ([string]$e.name -cne $PluginName) { Add-Failure "marketplace plugin name '$($e.name)' is not '$PluginName'" }
        if ([string]$e.source -ne './plugin') { Add-Failure "marketplace plugin source is '$($e.source)', expected './plugin'" }
    }
}
if ($Errors.Count -eq $beforeManifest -and $null -ne $plugin -and $null -ne $market) {
    Write-Host "  plugin $($plugin.name) $Version, marketplace $($market.name), install id $($plugin.name)@$($market.name)"
}

# ---------------------------------------------------------------- skills
Write-Host 'Validating skills against the contract footprint' -ForegroundColor Cyan
if (-not (Test-Path $SkillsDir)) { Add-Failure "skills folder not found: $SkillsDir" }

$Results = @{}
foreach ($name in $ExpectedSkills) {
    $r = @{ DescLen = 0; BodyLines = 0; BodyTokens = 0; Files = 0 }
    $Results[$name] = $r
    $folder = Join-Path $SkillsDir $name
    $skillMd = Join-Path $folder 'SKILL.md'

    if (-not (Test-Path $folder -PathType Container)) { Add-Failure "skills\$name\ is missing"; continue }
    # Exact-case check: the uploader requires SKILL.md, not skill.md.
    $mdFile = Get-ChildItem -Path $folder -File | Where-Object { $_.Name -ceq 'SKILL.md' }
    if (-not $mdFile) { Add-Failure "skills\$name\SKILL.md is missing (name is case sensitive)"; continue }

    $parsed = Split-Frontmatter (Read-Text $skillMd)
    if ($null -eq $parsed) { Add-Failure "skills\$name\SKILL.md has no YAML frontmatter block (--- ... ---) at the top"; continue }
    $fm = $parsed.Fm

    if (-not $fm.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($fm['name'])) {
        Add-Failure "skills\$name\SKILL.md frontmatter is missing 'name'"
    } else {
        $n = $fm['name']
        if ($n -cnotmatch $NamePattern) { Add-Failure "skills\$name\SKILL.md name '$n' does not match $NamePattern" }
        elseif ($n -cne $name) { Add-Failure "skills\$name\SKILL.md name '$n' does not equal folder name '$name'" }
    }
    if (-not $fm.ContainsKey('description') -or [string]::IsNullOrWhiteSpace($fm['description'])) {
        Add-Failure "skills\$name\SKILL.md frontmatter is missing 'description'"
    } else {
        $d = $fm['description']
        $r.DescLen = $d.Length
        if ($r.DescLen -gt $MaxDescription) { Add-Failure ("skills\{0}\SKILL.md description is {1} chars (max {2})" -f $name, $r.DescLen, $MaxDescription) }
        if (-not $d.StartsWith('Use when', [System.StringComparison]::Ordinal)) { Add-Failure "skills\$name\SKILL.md description must start with 'Use when'" }
        if (-not $d.Contains('Not for:')) { Add-Failure "skills\$name\SKILL.md description must contain a 'Not for:' clause" }
    }

    $body = @($parsed.Body)
    $r.BodyLines = $body.Count
    $r.BodyTokens = [int][math]::Ceiling((($body -join "`n").Length) / 4.0)
    if ($r.BodyLines -gt $MaxBodyLines) { Add-Failure ("skills\{0}\SKILL.md body is {1} lines (max {2})" -f $name, $r.BodyLines, $MaxBodyLines) }
    if ($r.BodyTokens -gt $WarnBodyTokens) { Write-Warn ("skills\{0}\SKILL.md body is about {1} tokens (chars/4), over the {2} target" -f $name, $r.BodyTokens, $WarnBodyTokens) }

    $r.Files = @(Get-ChildItem -Path $folder -Recurse -File).Count
    Write-Host ("  {0}: description {1}/{2} chars, body {3}/{4} lines, about {5} tokens" -f $name, $r.DescLen, $MaxDescription, $r.BodyLines, $MaxBodyLines, $r.BodyTokens)
}
if (Test-Path $SkillsDir) {
    Get-ChildItem -Path $SkillsDir -Directory | Where-Object { $ExpectedSkills -notcontains $_.Name } | ForEach-Object {
        Write-Warn "skills\$($_.Name)\ is not in the expected list and will not be packaged"
    }
}

# ---------------------------------------------------------------- agents
Write-Host 'Validating kit subagents' -ForegroundColor Cyan
$Agents = @()
if (Test-Path $AgentsSrc -PathType Container) { $Agents = @(Get-ChildItem -Path $AgentsSrc -Filter '*.md' -File | Sort-Object Name) }
if ($Agents.Count -eq 0) { Add-Failure 'no kit\agents\*.md found to ship in the plugin' }
foreach ($a in $Agents) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($a.Name)
    $parsed = Split-Frontmatter (Read-Text $a.FullName)
    if ($null -eq $parsed) { Add-Failure "kit\agents\$($a.Name) has no YAML frontmatter"; continue }
    $fm = $parsed.Fm
    foreach ($k in @('name', 'description', 'model')) {
        if (-not $fm.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($fm[$k])) { Add-Failure "kit\agents\$($a.Name) frontmatter is missing '$k'" }
    }
    if ($fm.ContainsKey('name') -and $fm['name'] -cne $base) { Add-Failure "kit\agents\$($a.Name) name '$($fm['name'])' does not equal file name '$base'" }
    foreach ($k in $IgnoredAgentFields) { if ($fm.ContainsKey($k)) { Write-Warn "kit\agents\$($a.Name) sets '$k', which plugin agents ignore" } }
    $model = $(if ($fm.ContainsKey('model')) { $fm['model'] } else { '' })
    $tools = $(if ($fm.ContainsKey('tools')) { $fm['tools'] } else { '(all)' })
    Write-Host ("  {0}: model {1}, tools {2}" -f $base, $model, $tools)
}

# ---------------------------------------------------------------- text scan
Write-Host 'Scanning shipped text for dashes and non-ASCII' -ForegroundColor Cyan
$ScanFiles = New-Object System.Collections.Generic.List[string]
foreach ($f in @('README.md', 'CHANGELOG.md', 'RESULTS.md')) {
    $p = Join-Path $Root $f
    if (Test-Path $p -PathType Leaf) { $ScanFiles.Add($p) }
    elseif ($f -ne 'RESULTS.md') { Add-Failure "$f is missing" }
}
foreach ($dir in @('docs', 'skills', 'kit', '.claude-plugin', 'scripts')) {
    $p = Join-Path $Root $dir
    if (Test-Path $p) { Get-ChildItem -Path $p -Recurse -File -Force | ForEach-Object { $ScanFiles.Add($_.FullName) } }
}
if (Test-Path $PluginDir) {
    Get-ChildItem -Path $PluginDir -Recurse -File -Force |
        Where-Object { -not (Test-Under $_.FullName $PluginSkills) -and -not (Test-Under $_.FullName $PluginAgents) } |
        ForEach-Object { $ScanFiles.Add($_.FullName) }
}
$TokenDir = Join-Path $Root 'tests\token'
$TokenResults = Join-Path $TokenDir 'results'
if (Test-Path $TokenDir) {
    Get-ChildItem -Path $TokenDir -Recurse -File -Force | Where-Object {
        if (-not (Test-Under $_.FullName $TokenResults)) { return $true }
        # Ship and scan only the summary markdown directly under results\.
        return ($_.DirectoryName.TrimEnd('\') -ieq $TokenResults.TrimEnd('\') -and $_.Extension -ieq '.md')
    } | ForEach-Object { $ScanFiles.Add($_.FullName) }
}
$beforeScan = $Errors.Count
foreach ($f in $ScanFiles) { Test-ShippedText $f }
if ($Errors.Count -eq $beforeScan) { Write-Host "  $($ScanFiles.Count) files clean." }

if ($Errors.Count -gt 0) {
    Write-Host ''
    Write-Host ("Validation FAILED with {0} error(s). Nothing was packaged." -f $Errors.Count) -ForegroundColor Red
    exit 1
}
Write-Host '  All checks passed.' -ForegroundColor Green
Write-Host ''

# ---------------------------------------------------------------- stage
$Stage = Join-Path ([System.IO.Path]::GetTempPath()) ("streck-lean-stage-" + [guid]::NewGuid().ToString('N'))
$StageSkills = Join-Path $Stage 'skills'
$StageAgents = Join-Path $Stage 'agents'
New-Item -ItemType Directory -Path $StageSkills, $StageAgents | Out-Null

$Summary = @()
try {
    foreach ($name in $ExpectedSkills) { Copy-Item -Path (Join-Path $SkillsDir $name) -Destination (Join-Path $StageSkills $name) -Recurse }
    foreach ($a in $Agents) { Copy-Item -Path $a.FullName -Destination (Join-Path $StageAgents $a.Name) }

    if ($Check) {
        Write-Host 'Comparing plugin\skills, plugin\agents, and dist\claude-ai with a fresh build' -ForegroundColor Cyan
        $diffs = 0
        $diffs += Compare-Trees (Get-TreeHashes $StageSkills) (Get-TreeHashes $PluginSkills) 'plugin\skills'
        $diffs += Compare-Trees (Get-TreeHashes $StageAgents) (Get-TreeHashes $PluginAgents) 'plugin\agents'
        foreach ($name in $ExpectedSkills) {
            $zipPath = Join-Path $DistDir "$name-$Version.zip"
            if (-not (Test-Path $zipPath)) { Write-Warn "dist\claude-ai\$name-$Version.zip not built yet (dist is not committed); skipped"; continue }
            $expected = @{}
            $h = Get-TreeHashes (Join-Path $StageSkills $name)
            foreach ($k in $h.Keys) { $expected["$name/$k"] = $h[$k] }
            $diffs += Compare-Trees $expected (Get-ZipHashes $zipPath) "$name-$Version.zip"
        }
        if ($diffs -gt 0) {
            Write-Host ''
            Write-Host ("Check FAILED: {0} difference(s). Run scripts\package.ps1 and commit plugin\." -f $diffs) -ForegroundColor Red
            exit 1
        }
        Write-Host '  plugin\skills and plugin\agents match skills\ and kit\agents\.' -ForegroundColor Green
    } else {
        Write-Host 'Building plugin\skills, plugin\agents, and dist\claude-ai' -ForegroundColor Cyan
        foreach ($p in @($PluginSkills, $PluginAgents)) {
            if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        }
        Copy-Item -Path $StageSkills -Destination $PluginSkills -Recurse
        Copy-Item -Path $StageAgents -Destination $PluginAgents -Recurse
        if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir -Force | Out-Null }

        foreach ($name in $ExpectedSkills) {
            # Replace every version of this skill's zip, and nothing else in dist\claude-ai.
            Get-ChildItem -Path $DistDir -Filter "$name-*.zip" -File | Where-Object { $_.Name -match ('^' + [regex]::Escape($name) + '-\d+\.\d+\.\d+\.zip$') } | Remove-Item -Force
            $staged = Join-Path $StageSkills $name
            $zipName = "$name-$Version.zip"
            $zipPath = Join-Path $DistDir $zipName
            New-SkillZip -SourceFolder $staged -SkillName $name -ZipPath $zipPath
            $before = $Errors.Count

            # Verify the zip layout: exactly one SKILL.md at <name>/SKILL.md, single top-level folder.
            $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
            try { $entries = @($z.Entries | ForEach-Object { $_.FullName }) } finally { $z.Dispose() }
            $tops = @($entries | ForEach-Object { ($_ -split '/')[0] } | Select-Object -Unique)
            $skillMds = @($entries | Where-Object { $_ -match '(^|/)SKILL\.md$' })
            if ($tops.Count -ne 1 -or $tops[0] -cne $name) { Add-Failure "$zipName top-level entries are '$($tops -join ', ')', expected only '$name'" }
            if ($skillMds.Count -ne 1 -or $skillMds[0] -cne "$name/SKILL.md") { Add-Failure "$zipName must contain exactly one SKILL.md at $name/SKILL.md" }

            $r = $Results[$name]
            $Summary += [pscustomobject]@{
                Skill      = $name
                Surface    = $Surface[$name]
                DescChars  = $r.DescLen
                BodyLines  = $r.BodyLines
                BodyTokens = $r.BodyTokens
                Zip        = $zipName
                Entries    = $entries.Count
                ZipKB      = [math]::Round((Get-Item $zipPath).Length / 1KB, 1)
                Status     = $(if ($Errors.Count -eq $before) { 'OK' } else { 'FAIL' })
            }
        }
    }
} finally {
    if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
}

if ($Summary.Count -gt 0) {
    $Summary | Select-Object Skill, Surface, DescChars, BodyLines, BodyTokens, Zip, Entries, ZipKB, Status |
        Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    Write-Host ("  plugin\agents: {0}" -f (($Agents | ForEach-Object { $_.Name }) -join ', '))
}

# ---------------------------------------------------------------- claude plugin validate
Write-Host 'Running claude plugin validate --strict' -ForegroundColor Cyan
$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($null -eq $claude) {
    Write-Warn 'Claude Code CLI not found on PATH; skipped claude plugin validate. Install it and re-run before release.'
} else {
    Write-Host '  marketplace (repo root):'
    if (-not (Invoke-ClaudeValidate $Root)) { Add-Failure 'claude plugin validate failed for the marketplace' }
    Write-Host '  plugin (plugin\):'
    if (-not (Invoke-ClaudeValidate $PluginDir)) { Add-Failure 'claude plugin validate failed for the plugin' }
}

if ($Errors.Count -gt 0) {
    Write-Host ''
    Write-Host ("FAILED with {0} error(s)." -f $Errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host ''
if ($Check) {
    Write-Host 'Check complete. Nothing was written.' -ForegroundColor Green
} else {
    Write-Host "Plugin: $(Get-RelPath $PluginDir)\ (skills\, agents\)"
    Write-Host "Skill zips: $(Get-RelPath $DistDir)\ (version $Version). Upload lean-chat-$Version.zip to Claude.ai."
    Write-Host 'Packaging complete.' -ForegroundColor Green
}
exit 0
