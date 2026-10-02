<#
.SYNOPSIS
  Token and cost harness: runs the tasks in tasks.md headless under several Claude Code
  configurations and records usage, cost, and pass checks.

.DESCRIPTION
  For each task x config x repeat:
    1. copy sample-repo to a fresh temp work dir
    2. for kit configs, install the kit settings and agents into <work>\.claude\
    3. run: claude "<prompt>" -p --output-format json --model <m> --max-turns <n> ...
    4. parse the JSON result, run the task's pass checks against the work dir
  Writes results\<timestamp>.csv, results\<timestamp>.md, and raw JSON under results\<timestamp>\.

  Configs:
    default  -Model (Sonnet), no kit
    lean     -Model (Sonnet) plus kit settings and agents
    tiered   per-task tier model from tasks.md (haiku for lookup/summarize/rename, sonnet otherwise), plus the kit

.EXAMPLE
  # Smoke: one task, default config, Haiku, 3 turns
  .\run.ps1 -Tasks T1-find-def -Configs default -Model haiku -MaxTurns 3

.EXAMPLE
  # Full matrix, 3 repeats, clean-room mode
  $env:ANTHROPIC_API_KEY = '...'; .\run.ps1 -Repeat 3 -Bare
#>
[CmdletBinding()]
param(
  [string[]]$Tasks = @(),
  [ValidateSet('default', 'lean', 'tiered')]
  [string[]]$Configs = @('default', 'lean', 'tiered'),
  [string]$Model = 'sonnet',
  [int]$MaxTurns = 0,
  [int]$Repeat = 1,
  [string]$LeanSettings = '',
  [string]$LeanAgentsDir = '',
  [string]$LeanClaudeMd = '',
  [switch]$Bare,
  [ValidateSet('acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')]
  [string]$PermissionMode = 'acceptEdits',
  [double]$MaxBudgetUsd = 2.0,
  [int]$TimeoutSec = 600,
  [string]$ClaudePath = '',
  [string]$OutDir = '',
  [switch]$KeepWorkDirs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# PS 5.1 does not populate $PSScriptRoot inside param defaults, so resolve here.
$Here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = (Resolve-Path (Join-Path $Here '..\..')).Path
$SampleRepo = Join-Path $Here 'sample-repo'
$ChecksDir = Join-Path $Here 'checks'
if (-not $LeanSettings) {
  # Prefer an installed kit\settings.json, else the shipped template.
  $LeanSettings = Join-Path $ProjectRoot 'kit\settings.json'
  $tmpl = Join-Path $ProjectRoot 'kit\settings.template.json'
  if (-not (Test-Path $LeanSettings) -and (Test-Path $tmpl)) { $LeanSettings = $tmpl }
}
if (-not $LeanAgentsDir) { $LeanAgentsDir = Join-Path $ProjectRoot 'kit\agents' }
if (-not $OutDir) { $OutDir = Join-Path $Here 'results' }
$Utf8 = New-Object System.Text.UTF8Encoding $false

# ---------------- helpers ----------------

function Resolve-Claude {
  param([string]$Hint)
  if ($Hint) { return (Resolve-Path $Hint).Path }
  $cmds = @(Get-Command claude -All -ErrorAction SilentlyContinue)
  foreach ($c in $cmds) {
    if ($c.CommandType -eq 'Application' -and $c.Source -like '*.exe') { return $c.Source }
  }
  # npm shim: claude.cmd calls node_modules\@anthropic-ai\claude-code\bin\claude.exe
  foreach ($c in $cmds) {
    if ($c.Source -like '*.cmd') {
      $exe = Join-Path (Split-Path $c.Source -Parent) 'node_modules\@anthropic-ai\claude-code\bin\claude.exe'
      if (Test-Path $exe) { return $exe }
      return $c.Source
    }
  }
  throw 'claude not found on PATH. Pass -ClaudePath.'
}

# Quote one argument per the Windows CommandLineToArgvW rules.
function ConvertTo-Arg([string]$a) {
  if ($a -ne '' -and $a -notmatch '[\s"]') { return $a }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $bs = 0
  foreach ($ch in $a.ToCharArray()) {
    if ($ch -eq '\') { $bs++; continue }
    if ($ch -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
    if ($bs) { [void]$sb.Append('\' * $bs); $bs = 0 }
    [void]$sb.Append($ch)
  }
  if ($bs) { [void]$sb.Append('\' * ($bs * 2)) }
  [void]$sb.Append('"')
  return $sb.ToString()
}

# Job object with KILL_ON_JOB_CLOSE: every process the child spawns (MCP servers via npx,
# git, shells) joins the job and dies when the handle closes. Without it, orphaned MCP
# servers keep inherited handles open and stall the caller long after claude exits.
if (-not ('HarnessJob' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HarnessJob {
  [StructLayout(LayoutKind.Sequential)] struct BASIC { public long a; public long b; public uint LimitFlags; public UIntPtr c; public UIntPtr d; public uint e; public UIntPtr f; public uint g; public uint h; }
  [StructLayout(LayoutKind.Sequential)] struct IOC { public ulong a, b, c, d, e, f; }
  [StructLayout(LayoutKind.Sequential)] struct EXT { public BASIC Basic; public IOC Io; public UIntPtr p1, p2, p3, p4; }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string n);
  [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr j, int c, ref EXT i, uint l);
  [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  public static IntPtr Create() {
    IntPtr j = CreateJobObject(IntPtr.Zero, null);
    EXT e = new EXT(); e.Basic.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    SetInformationJobObject(j, 9, ref e, (uint)Marshal.SizeOf(typeof(EXT)));
    return j;
  }
  public static bool Assign(IntPtr j, IntPtr p) { return AssignProcessToJobObject(j, p); }
}
'@
}

function Invoke-Proc {
  param([string]$File, [string[]]$ArgList, [string]$Cwd, [int]$TimeoutSec, [string[]]$UnsetEnv = @())
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  if ($File -like '*.cmd') {
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /s /c "' + (ConvertTo-Arg $File) + ' ' + (($ArgList | ForEach-Object { ConvertTo-Arg $_ }) -join ' ') + '"'
  } else {
    $psi.FileName = $File
    $psi.Arguments = ($ArgList | ForEach-Object { ConvertTo-Arg $_ }) -join ' '
  }
  $psi.WorkingDirectory = $Cwd
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $psi.StandardErrorEncoding = $Utf8
  foreach ($v in $UnsetEnv) { if ($psi.EnvironmentVariables.ContainsKey($v)) { $psi.EnvironmentVariables.Remove($v) } }
  $job = [HarnessJob]::Create()
  $p = [System.Diagnostics.Process]::Start($psi)
  [void][HarnessJob]::Assign($job, $p.Handle)
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $timedOut = $false
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    $timedOut = $true
    & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
    [void]$p.WaitForExit(10000)
  }
  # Closing the job kills anything the child left running. The WMI sweep below is a
  # fallback for processes that escaped the job (spawned before assignment).
  [void][HarnessJob]::CloseHandle($job)
  try {
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction Stop |
      ForEach-Object { & taskkill.exe /T /F /PID $_.ProcessId 2>&1 | Out-Null }
  } catch { }
  [pscustomobject]@{
    ExitCode = $(if ($timedOut) { -1 } else { $p.ExitCode })
    TimedOut = $timedOut
    StdOut   = $outTask.Result
    StdErr   = $errTask.Result
  }
}

function Get-Tasks {
  $md = [System.IO.File]::ReadAllText((Join-Path $Here 'tasks.md'), $Utf8)
  $m = [regex]::Match($md, '```json\s*(\[[\s\S]*?\])\s*```')
  if (-not $m.Success) { throw 'No ```json task block found in tasks.md' }
  # PS 5.1 ConvertFrom-Json emits a JSON array as one object; ForEach-Object unrolls it.
  return ($m.Groups[1].Value | ConvertFrom-Json | ForEach-Object { $_ })
}

function Get-Prop($obj, [string]$name, $default = 0) {
  if ($null -eq $obj) { return $default }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p -or $null -eq $p.Value) { return $default }
  return $p.Value
}

function Test-Check {
  param($Check, [string]$Work, [string]$Answer, [string]$Pristine)
  $t = $Check.type
  try {
    switch ($t) {
      'answer_regex' { return [regex]::IsMatch($Answer, $Check.pattern, 'IgnoreCase') }
      'answer_not_regex' { return -not [regex]::IsMatch($Answer, $Check.pattern, 'IgnoreCase') }
      'answer_max_words' { return (@($Answer -split '\s+' | Where-Object { $_ }).Count -le [int]$Check.max) }
      'file_regex' {
        $f = Join-Path $Work $Check.path
        if (-not (Test-Path $f)) { return $false }
        return [regex]::IsMatch([System.IO.File]::ReadAllText($f), $Check.pattern)
      }
      'no_match' {
        foreach ($d in $Check.paths) {
          $dir = Join-Path $Work $d
          if (-not (Test-Path $dir)) { continue }
          foreach ($f in Get-ChildItem $dir -Recurse -File) {
            if ([regex]::IsMatch([System.IO.File]::ReadAllText($f.FullName), $Check.pattern)) { return $false }
          }
        }
        return $true
      }
      'file_unchanged' {
        $a = Join-Path $Work $Check.path; $b = Join-Path $Pristine $Check.path
        if (-not (Test-Path $a)) { return $false }
        return ((Get-FileHash $a).Hash -eq (Get-FileHash $b).Hash)
      }
      'cmd' {
        $r = Invoke-Proc -File $NodeExe -ArgList @($Check.args) -Cwd $Work -TimeoutSec 60
        return ($r.ExitCode -eq 0)
      }
      'node_check' {
        $r = Invoke-Proc -File $NodeExe -ArgList @((Join-Path $ChecksDir $Check.script)) -Cwd $Work -TimeoutSec 60
        return ($r.ExitCode -eq 0)
      }
      default { Write-Warning "Unknown check type '$t'"; return $false }
    }
  } catch {
    Write-Warning "Check $t threw: $($_.Exception.Message)"
    return $false
  }
}

function Format-Pct([double]$v, [double]$base) {
  if ($base -eq 0) { return 'n/a' }
  $d = ($v - $base) / $base * 100
  return ('{0:+0;-0;0}%' -f $d)
}

# ---------------- preflight ----------------

$ClaudeExe = Resolve-Claude $ClaudePath
$NodeExe = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$cliVersion = (& $ClaudeExe --version 2>&1 | Out-String).Trim()

if ($Bare -and -not $env:ANTHROPIC_API_KEY) {
  throw '-Bare requires ANTHROPIC_API_KEY in the environment (--bare never reads OAuth or the keychain).'
}
$modeLine = if ($Bare) {
  'MODE: BARE (--bare). User-level CLAUDE.md, hooks, plugins, auto memory, and keychain auth are skipped. Auth via ANTHROPIC_API_KEY. Kit settings are passed with --settings.'
} else {
  'MODE: INHERITED. Runs load the operator''s user-level config (~/.claude settings, CLAUDE.md, plugins, MCP servers, hooks, memory). Numbers include that overhead in every config. Use -Bare for a clean room.'
}
Write-Host ''
Write-Host $modeLine -ForegroundColor Yellow
Write-Host "claude: $ClaudeExe ($cliVersion)"

$kitSettingsOk = Test-Path $LeanSettings
$kitAgentsOk = (Test-Path $LeanAgentsDir) -and @(Get-ChildItem $LeanAgentsDir -Filter *.md -ErrorAction SilentlyContinue).Count -gt 0
$kitClaudeMdOk = $LeanClaudeMd -and (Test-Path $LeanClaudeMd)
$kitAvailable = $kitSettingsOk -or $kitAgentsOk
Write-Host ("kit: settings={0} ({1}); agents={2} ({3}); CLAUDE.md={4}" -f $kitSettingsOk, $LeanSettings, $kitAgentsOk, $LeanAgentsDir, [bool]$kitClaudeMdOk)

$runConfigs = New-Object System.Collections.Generic.List[string]
foreach ($c in $Configs) {
  if ($c -eq 'lean' -and -not $kitAvailable) {
    Write-Warning "Skipping 'lean': no kit settings at $LeanSettings and no agents in $LeanAgentsDir. Pass -LeanSettings / -LeanAgentsDir once the kit exists."
    continue
  }
  if ($c -eq 'tiered' -and -not $kitAvailable) {
    Write-Warning "'tiered' will run WITHOUT the kit (not present). Its delta then measures model choice only."
  }
  $runConfigs.Add($c)
}
if ($runConfigs.Count -eq 0) { throw 'No configs left to run.' }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Here 'build-sample.ps1') -RepoPath $SampleRepo | Out-Null
if (-not (Test-Path (Join-Path $SampleRepo 'logs\app.log'))) { throw 'build-sample.ps1 did not produce logs\app.log' }

$allTasks = @(Get-Tasks)
$selected = @(if ($Tasks.Count) { $allTasks | Where-Object { $Tasks -contains $_.id } } else { $allTasks })
if ($selected.Count -eq 0) { throw "No tasks matched: $($Tasks -join ', ')" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
$rawDir = Join-Path $OutDir $stamp
New-Item -ItemType Directory -Force $rawDir | Out-Null
$workRoot = Join-Path $env:TEMP "claude-token-harness\$stamp"
New-Item -ItemType Directory -Force $workRoot | Out-Null

# Variables set when this script itself runs inside a Claude Code session; unset so the
# child behaves like a run from a plain terminal. Auth and provider vars are left alone.
$unsetEnv = @('CLAUDECODE', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_SSE_PORT')

$readTools = @('Read', 'Grep', 'Glob')
$editTools = @('Edit', 'Write', 'MultiEdit', 'Bash(node *)', 'Bash(npm test*)', 'PowerShell(node *)', 'PowerShell(npm test*)')

$rows = New-Object System.Collections.Generic.List[object]
$total = $selected.Count * $runConfigs.Count * $Repeat
$n = 0

foreach ($task in $selected) {
  foreach ($cfg in $runConfigs) {
    for ($rep = 1; $rep -le $Repeat; $rep++) {
      $n++
      $useKit = ($cfg -ne 'default') -and $kitAvailable
      $m = if ($cfg -eq 'tiered') { $task.tier } else { $Model }
      $turns = if ($MaxTurns -gt 0) { $MaxTurns } else { [int]$task.maxTurns }
      Write-Host ("[{0}/{1}] {2} / {3} / {4} / rep {5}" -f $n, $total, $task.id, $cfg, $m, $rep)

      $work = Join-Path $workRoot ("{0}-{1}-{2}" -f $task.id, $cfg, $rep)
      Copy-Item $SampleRepo $work -Recurse -Force
      $settingsCopy = ''
      if ($useKit) {
        $dotClaude = Join-Path $work '.claude'
        New-Item -ItemType Directory -Force $dotClaude | Out-Null
        if ($kitSettingsOk) {
          $settingsCopy = Join-Path $dotClaude 'settings.json'
          Copy-Item $LeanSettings $settingsCopy
        }
        if ($kitAgentsOk) {
          New-Item -ItemType Directory -Force (Join-Path $dotClaude 'agents') | Out-Null
          Copy-Item (Join-Path $LeanAgentsDir '*.md') (Join-Path $dotClaude 'agents')
        }
        if ($kitClaudeMdOk) { Copy-Item $LeanClaudeMd (Join-Path $work 'CLAUDE.md') }
      }

      # Prompt goes first: --allowedTools is variadic and would swallow a trailing positional.
      $cliArgs = New-Object System.Collections.Generic.List[string]
      $cliArgs.Add([string]$task.prompt)
      $cliArgs.AddRange([string[]]@('-p', '--output-format', 'json', '--model', $m, '--max-turns', [string]$turns,
          '--permission-mode', $PermissionMode, '--permission-prompts', 'none',
          '--no-session-persistence', '--max-budget-usd', ([string]$MaxBudgetUsd)))
      if ($Bare) {
        $cliArgs.Add('--bare')
        if ($settingsCopy) { $cliArgs.AddRange([string[]]@('--settings', $settingsCopy)) }
      }
      $tools = if ($task.edits) { $readTools + $editTools } else { $readTools }
      $cliArgs.Add('--allowedTools')
      $cliArgs.AddRange([string[]]$tools)

      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $proc = Invoke-Proc -File $ClaudeExe -ArgList $cliArgs.ToArray() -Cwd $work -TimeoutSec $TimeoutSec -UnsetEnv $unsetEnv
      $sw.Stop()

      $base = "{0}-{1}-{2}" -f $task.id, $cfg, $rep
      [System.IO.File]::WriteAllText((Join-Path $rawDir "$base.json"), $proc.StdOut, $Utf8)
      if ($proc.StdErr) { [System.IO.File]::WriteAllText((Join-Path $rawDir "$base.stderr.txt"), $proc.StdErr, $Utf8) }

      $j = $null
      try { $j = $proc.StdOut | ConvertFrom-Json } catch {
        $last = @($proc.StdOut -split "`n" | Where-Object { $_.Trim().StartsWith('{') }) | Select-Object -Last 1
        if ($last) { try { $j = $last | ConvertFrom-Json } catch { $j = $null } }
      }

      $answer = [string](Get-Prop $j 'result' '')
      $usage = Get-Prop $j 'usage' $null
      # modelUsage covers every model the session used (main plus subagents); usage is the main model only.
      $mu = Get-Prop $j 'modelUsage' $null
      $muIn = 0; $muOut = 0; $muCr = 0; $muCc = 0; $models = @()
      if ($mu) {
        foreach ($p in $mu.PSObject.Properties) {
          $models += $p.Name
          $muIn += [long](Get-Prop $p.Value 'inputTokens')
          $muOut += [long](Get-Prop $p.Value 'outputTokens')
          $muCr += [long](Get-Prop $p.Value 'cacheReadInputTokens')
          $muCc += [long](Get-Prop $p.Value 'cacheCreationInputTokens')
        }
      }
      $inTok = [long](Get-Prop $usage 'input_tokens'); $outTok = [long](Get-Prop $usage 'output_tokens')
      $cr = [long](Get-Prop $usage 'cache_read_input_tokens'); $cc = [long](Get-Prop $usage 'cache_creation_input_tokens')
      if ($mu) { $inTok = $muIn; $outTok = $muOut; $cr = $muCr; $cc = $muCc }

      $pristine = $SampleRepo
      $results = @()
      foreach ($chk in $task.checks) { $results += [bool](Test-Check -Check $chk -Work $work -Answer $answer -Pristine $pristine) }
      $passed = @($results | Where-Object { $_ }).Count

      [System.IO.File]::WriteAllText((Join-Path $rawDir "$base.answer.txt"), $answer, $Utf8)

      $row = [pscustomobject][ordered]@{
        timestamp          = $stamp
        mode               = $(if ($Bare) { 'bare' } else { 'inherited' })
        task               = $task.id
        class              = $task.class
        config             = $cfg
        rep                = $rep
        model_requested    = $m
        models_used        = ($models -join ';')
        kit_applied        = $useKit
        max_turns          = $turns
        subtype            = [string](Get-Prop $j 'subtype' $(if ($proc.TimedOut) { 'timeout' } else { 'no_json' }))
        is_error           = [bool](Get-Prop $j 'is_error' $true)
        exit_code          = $proc.ExitCode
        input_tokens       = $inTok
        output_tokens      = $outTok
        cache_read         = $cr
        cache_creation     = $cc
        total_tokens       = $inTok + $outTok + $cr + $cc
        total_cost_usd     = [double](Get-Prop $j 'total_cost_usd')
        num_turns          = [int](Get-Prop $j 'num_turns')
        duration_ms        = [long](Get-Prop $j 'duration_ms' $sw.ElapsedMilliseconds)
        wall_ms            = $sw.ElapsedMilliseconds
        checks_passed      = $passed
        checks_total       = $results.Count
        pass               = ($passed -eq $results.Count -and $results.Count -gt 0)
        check_detail       = (($results | ForEach-Object { if ($_) { '1' } else { '0' } }) -join '')
        subagents_spawned  = [int](Get-Prop (Get-Prop $j 'subagent_stats' $null) 'spawned')
        permission_denials = @(Get-Prop $j 'permission_denials' @()).Count
        session_id         = [string](Get-Prop $j 'session_id' '')
      }
      $rows.Add($row)
      Write-Host ("    tokens={0} cost=`${1:N4} turns={2} checks={3}/{4} subtype={5}" -f $row.total_tokens, $row.total_cost_usd, $row.num_turns, $passed, $results.Count, $row.subtype)

      if (-not $KeepWorkDirs) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }
    }
  }
}

# ---------------- outputs ----------------

$csv = Join-Path $OutDir "$stamp.csv"
$rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Token harness results $stamp")
[void]$md.AppendLine('')
[void]$md.AppendLine($modeLine)
[void]$md.AppendLine('')
[void]$md.AppendLine("CLI: $cliVersion. Base model: $Model. Repeats: $Repeat. Permission mode: $PermissionMode. Kit available: $kitAvailable.")
[void]$md.AppendLine('')
[void]$md.AppendLine('## Totals by config')
[void]$md.AppendLine('')
[void]$md.AppendLine('| config | runs | tasks passed | checks passed | input | output | cache read | cache write | total tokens | cost USD | turns | delta tokens vs default | delta cost vs default |')
[void]$md.AppendLine('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
$agg = @{}
foreach ($c in $runConfigs) {
  $r = @($rows | Where-Object { $_.config -eq $c })
  $agg[$c] = [pscustomobject]@{
    runs = $r.Count
    pass = @($r | Where-Object { $_.pass }).Count
    cp = ($r | Measure-Object checks_passed -Sum).Sum
    ct = ($r | Measure-Object checks_total -Sum).Sum
    inp = ($r | Measure-Object input_tokens -Sum).Sum
    out = ($r | Measure-Object output_tokens -Sum).Sum
    cr = ($r | Measure-Object cache_read -Sum).Sum
    cc = ($r | Measure-Object cache_creation -Sum).Sum
    tot = ($r | Measure-Object total_tokens -Sum).Sum
    cost = ($r | Measure-Object total_cost_usd -Sum).Sum
    turns = ($r | Measure-Object num_turns -Sum).Sum
  }
}
foreach ($c in $runConfigs) {
  $a = $agg[$c]
  $dt = 'baseline'; $dc = 'baseline'
  if ($c -ne 'default') {
    if ($agg.ContainsKey('default')) { $dt = Format-Pct $a.tot $agg['default'].tot; $dc = Format-Pct $a.cost $agg['default'].cost } else { $dt = 'n/a'; $dc = 'n/a' }
  }
  [void]$md.AppendLine(("| {0} | {1} | {2}/{1} | {3}/{4} | {5:N0} | {6:N0} | {7:N0} | {8:N0} | {9:N0} | {10:N4} | {11} | {12} | {13} |" -f $c, $a.runs, $a.pass, $a.cp, $a.ct, $a.inp, $a.out, $a.cr, $a.cc, $a.tot, $a.cost, $a.turns, $dt, $dc))
}
[void]$md.AppendLine('')
[void]$md.AppendLine('## Per task (mean over repeats)')
[void]$md.AppendLine('')
[void]$md.AppendLine('| task | config | model | pass rate | mean checks | mean tokens | mean cost USD | delta tokens | delta cost | quality vs default |')
[void]$md.AppendLine('|---|---|---|---|---|---|---|---|---|---|')
foreach ($task in $selected) {
  $baseRows = @($rows | Where-Object { $_.task -eq $task.id -and $_.config -eq 'default' })
  $bTok = 0; $bCost = 0; $bChk = 0
  if ($baseRows.Count) {
    $bTok = ($baseRows | Measure-Object total_tokens -Average).Average
    $bCost = ($baseRows | Measure-Object total_cost_usd -Average).Average
    $bChk = ($baseRows | Measure-Object checks_passed -Average).Average
  }
  foreach ($c in $runConfigs) {
    $r = @($rows | Where-Object { $_.task -eq $task.id -and $_.config -eq $c })
    if (-not $r.Count) { continue }
    $tok = ($r | Measure-Object total_tokens -Average).Average
    $cost = ($r | Measure-Object total_cost_usd -Average).Average
    $chk = ($r | Measure-Object checks_passed -Average).Average
    $pr = @($r | Where-Object { $_.pass }).Count
    $q = 'baseline'; $dt = 'baseline'; $dc = 'baseline'
    if ($c -ne 'default') {
      if ($baseRows.Count) {
        $dt = Format-Pct $tok $bTok; $dc = Format-Pct $cost $bCost
        $q = if ($chk -lt $bChk) { 'WORSE' } elseif ($chk -gt $bChk) { 'better' } else { 'equal' }
      } else { $dt = 'n/a'; $dc = 'n/a'; $q = 'n/a' }
    }
    [void]$md.AppendLine(("| {0} | {1} | {2} | {3}/{4} | {5:N2}/{6} | {7:N0} | {8:N4} | {9} | {10} | {11} |" -f $task.id, $c, $r[0].model_requested, $pr, $r.Count, $chk, $r[0].checks_total, $tok, $cost, $dt, $dc, $q))
  }
}
[void]$md.AppendLine('')
[void]$md.AppendLine('A token or cost saving counts only where quality is equal or better. Rows marked WORSE are not savings.')
[void]$md.AppendLine('total_cost_usd is the CLI''s client-side estimate, not a billing record.')
$mdPath = Join-Path $OutDir "$stamp.md"
[System.IO.File]::WriteAllText($mdPath, $md.ToString(), $Utf8)

if (-not $KeepWorkDirs) { Remove-Item -Recurse -Force $workRoot -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host $modeLine -ForegroundColor Yellow
Write-Host "CSV:     $csv"
Write-Host "Summary: $mdPath"
Write-Host "Raw:     $rawDir"
