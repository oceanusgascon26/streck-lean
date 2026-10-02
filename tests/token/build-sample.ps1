<#
.SYNOPSIS
  Generates the bulky, deterministic parts of sample-repo: logs/app.log (2,000 lines),
  node_modules/ junk packages, and dist/bundle.js. Safe to re-run; -Force regenerates.
  run.ps1 calls this automatically when the generated parts are missing.
#>
[CmdletBinding()]
param(
  [string]$RepoPath = '',
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
# PS 5.1 does not populate $PSScriptRoot inside param defaults, so resolve here.
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoPath) { $RepoPath = Join-Path $here 'sample-repo' }
$utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Text([string]$Path, [string]$Text) {
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

# ---------- logs/app.log ----------
$logPath = Join-Path $RepoPath 'logs\app.log'
if ($Force -or -not (Test-Path $logPath)) {
  $rng = New-Object System.Random 142
  $base = [datetime]::SpecifyKind([datetime]'2026-09-28T00:00:00', 'Utc')
  $sb = New-Object System.Text.StringBuilder
  $infoMsgs = @(
    'SpecimenService: registered specimen lot={0} tube=cfDNA',
    'SpecimenService: registered specimen lot={0} tube=EDTA',
    'LabelService: queued label lot={0}',
    'LabelService: printed label lot={0}',
    'ReportService: appended row lot={0}',
    'HttpServer: GET /api/specimens/{0} 200 12ms',
    'HttpServer: POST /api/specimens 201 31ms',
    'Scheduler: heartbeat ok seq={0}'
  )
  $errLines = 0
  for ($i = 0; $i -lt 2000; $i++) {
    $ts = $base.AddSeconds($i * 13).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $lot = 'LOT-2026-' + (10000 + $i).ToString('00000')
    if ($i -ge 700 -and (($i - 700) % 28) -eq 0 -and $errLines -lt 47) {
      $errLines++
      [void]$sb.AppendLine("$ts ERROR LabelPrinterClient: connect ECONNREFUSED 10.20.30.40:9100 after 3 retries (lot=$lot)")
      [void]$sb.AppendLine("$ts ERROR RetryQueue: job moved to dead letter queue (lot=$lot)")
      $i++
      continue
    }
    if ($i -eq 412) { [void]$sb.AppendLine("$ts ERROR ReportWriter: EBUSY report-2026-09-28.csv locked, retried ok"); continue }
    if ($i -eq 1630) { [void]$sb.AppendLine("$ts ERROR HttpServer: GET /api/specimens/abc 400 invalid id"); continue }
    $r = $rng.Next(100)
    if ($r -lt 4) {
      [void]$sb.AppendLine("$ts WARN  Db: slow query specimens.find 812ms")
    } elseif ($r -lt 6) {
      [void]$sb.AppendLine("$ts DEBUG Cache: miss key=specimen:$lot")
    } else {
      $m = $infoMsgs[$rng.Next($infoMsgs.Count)] -f $lot
      [void]$sb.AppendLine("$ts INFO  $m")
    }
  }
  Write-Text $logPath $sb.ToString()
}

# ---------- node_modules junk ----------
$nm = Join-Path $RepoPath 'node_modules'
if ($Force -or -not (Test-Path $nm)) {
  if (Test-Path $nm) { Remove-Item -Recurse -Force $nm }
  $filler = New-Object System.Text.StringBuilder
  for ($k = 0; $k -lt 120; $k++) {
    [void]$filler.AppendLine("function helper$k(a, b) { var t = (a | 0) + (b | 0) * $k; if (t > 1e6) { t = t % 9973; } return t.toString(36); }")
  }
  $fillerText = $filler.ToString()
  $names = @('left-pad-plus','tiny-retry','fast-jsonish','color-wheelz','date-crunch','lodashette','uuid-lite','yargs-mini','chalkish','debugger-lite',
             'semver-ish','glob-lite','minimist-x','ms-plus','qs-lite','mime-ish','etag-lite','fresh-x','depd-lite','statuses-x',
             'bytes-ish','iconv-mini','raw-body-x','on-finished-x','destroy-ish','encodeurl-x','escape-html-x','parseurl-x','vary-ish','cookie-x')
  foreach ($n in $names) {
    Write-Text (Join-Path $nm "$n\package.json") ("{`"name`": `"$n`", `"version`": `"0.0.1`", `"main`": `"index.js`"}")
    Write-Text (Join-Path $nm "$n\index.js") ("'use strict';`n// generated vendor code for $n`n" + $fillerText + "module.exports = { helper0 };`n")
    Write-Text (Join-Path $nm "$n\README.md") ("# $n`n`nVendor package. Nothing to see here.`n")
    Write-Text (Join-Path $nm "$n\lib\impl.js") ("'use strict';`n" + $fillerText)
  }
  # Decoys: same names as project symbols, outside project source.
  Write-Text (Join-Path $nm 'legacy-specimen-utils\package.json') '{"name": "legacy-specimen-utils", "version": "2.1.0", "main": "index.js"}'
  Write-Text (Join-Path $nm 'legacy-specimen-utils\index.js') @"
'use strict';
// Legacy vendored helpers. Not used by this project.
function computeStabilityWindow(collected, type) { return { start: 0, end: 0, hours: 0 }; }
function fmtLot(y, s) { return 'L' + y + s; }
module.exports = { computeStabilityWindow, fmtLot };
"@
}

# ---------- dist/bundle.js ----------
$dist = Join-Path $RepoPath 'dist\bundle.js'
if ($Force -or -not (Test-Path $dist)) {
  $sb = New-Object System.Text.StringBuilder
  for ($k = 0; $k -lt 4000; $k++) { [void]$sb.Append("var _$k=function(a){return a*$k+1};") }
  [void]$sb.Append("function computeStabilityWindow(c,t){return{start:0,end:1,hours:1}};function fmtLot(y,s){return'LOT-'+y+'-'+s};")
  Write-Text $dist ($sb.ToString() + "`n")
}

Write-Host "sample-repo generated parts ready at $RepoPath"
