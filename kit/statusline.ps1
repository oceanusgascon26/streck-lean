# statusline.ps1: Claude Code status line for Windows PowerShell 5.1 and later.
# Claude Code pipes session JSON on stdin; this prints one short line:
#   <model> | ctx <pct>% (<used>/<size>) | $<session cost>
# Field names follow https://code.claude.com/docs/en/statusline (model.display_name,
# context_window.used_percentage, context_window.context_window_size,
# context_window.current_usage, cost.total_cost_usd). Any field may be null or absent.
# Never throws: on bad input it prints a fallback line so the status bar stays usable.

$ErrorActionPreference = 'SilentlyContinue'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function Format-Tokens([double]$n) {
    if ($n -ge 1000000) { return ($n / 1000000).ToString('0.#', $inv) + 'M' }
    if ($n -ge 1000)    { return ($n / 1000).ToString('0.#', $inv) + 'k' }
    return ([int]$n).ToString($inv)
}

$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch { $raw = '' }
if (-not $raw) { $raw = ($input | Out-String) }

$data = $null
try { $data = $raw | ConvertFrom-Json } catch { $data = $null }
if ($null -eq $data) { Write-Output 'claude | ctx ? | $?'; exit 0 }

# Model
$model = $data.model.display_name
if (-not $model) { $model = $data.model.id }
if (-not $model) { $model = 'model?' }

# Context: prefer the pre-calculated percentage; otherwise compute from current_usage
# with the documented input-only formula (input + cache creation + cache read).
$cw   = $data.context_window
$size = 0
if ($cw -and $cw.context_window_size) { $size = [double]$cw.context_window_size }
$used = $null
$cu   = $null
if ($cw) { $cu = $cw.current_usage }
if ($cu) {
    $used = [double]0
    foreach ($k in 'input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens') {
        if ($cu.$k) { $used += [double]$cu.$k }
    }
}
$pct = $null
if ($cw -and $null -ne $cw.used_percentage) { $pct = [double]$cw.used_percentage }
elseif ($null -ne $used -and $size -gt 0)   { $pct = 100 * $used / $size }

if ($null -ne $pct) {
    $ctx = 'ctx ' + ([math]::Round($pct)).ToString($inv) + '%'
    if ($null -ne $used -and $size -gt 0) { $ctx += ' (' + (Format-Tokens $used) + '/' + (Format-Tokens $size) + ')' }
} else {
    $ctx = 'ctx --'
}

# Session cost (client-side estimate at list price; resets on /clear)
$cost = '$--'
if ($data.cost -and $null -ne $data.cost.total_cost_usd) {
    $cost = '$' + ([double]$data.cost.total_cost_usd).ToString('0.00', $inv)
}

Write-Output ("{0} | {1} | {2}" -f $model, $ctx, $cost)
exit 0
