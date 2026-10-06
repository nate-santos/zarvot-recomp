# Exercise the real recorder against a synthetic process and stale coverage.
# No emulator is launched or stopped; all fixture output stays under build/.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$global:ZarvotFixtureRoot = Join-Path $root ('build\telemetry-tests\' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($global:ZarvotFixtureRoot) | Out-Null
$started = [DateTime]::UtcNow
$global:ZarvotFixtureProcess = [pscustomobject]@{
    Path = Join-Path $global:ZarvotFixtureRoot 'suyu-cmd.exe'
    StartTime = $started
    MainWindowTitle = 'Fixture | suyu Hybrid JIT + AOT | Building 2 shaders | JIT transitions: 6 | F12 Controls'
}
$global:ZarvotFixtureProcess | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
@{state='started';pid=123;process_started_utc=$started.ToString('o');strict_requested=$false} |
    ConvertTo-Json | Set-Content (Join-Path $global:ZarvotFixtureRoot 'launch.json') -Encoding utf8
$global:ZarvotFixtureCoverage = @'
=== RECOMP EXECUTION COVERAGE ===
  static blocks executed : 42
  static -> JIT          : 0 (0 lookup miss, 0 unimplemented opcode)
  unresolved import traps: 0
=== END RECOMP EXECUTION COVERAGE ===
'@
[IO.File]::WriteAllText((Join-Path $global:ZarvotFixtureRoot 'coverage.txt'), $global:ZarvotFixtureCoverage)
$global:ZarvotFixtureCalls = 0
function Get-Process {
    [CmdletBinding()]
    param([int]$Id)
    $global:ZarvotFixtureCalls++
    if ($global:ZarvotFixtureCalls -gt 3) { return }
    if ($global:ZarvotFixtureCalls -eq 3) {
        [IO.File]::WriteAllText((Join-Path $global:ZarvotFixtureRoot 'coverage.txt'),
            $global:ZarvotFixtureCoverage.Replace(': 42', ': 84'))
    }
    $global:ZarvotFixtureProcess
}
$recorded = & (Join-Path $root 'scripts\measure-zarvot-coverage.ps1') -RunRoot $global:ZarvotFixtureRoot -UntilExit
$summary = Get-Content -LiteralPath $recorded.Evidence -Raw | ConvertFrom-Json
if ($summary.end_reason -ne 'process_exited' -or $summary.error -or
    $summary.max_ui_jit_transitions -ne 6 -or $summary.max_jit_transitions -ne 0 -or
    $summary.ui_coverage_disagreements -ne 2 -or -not $summary.compiled_count_advanced) {
    throw 'Recorder lost the UI/file discrepancy or failed to end on process exit'
}
$lines = @(Get-Content -LiteralPath $recorded.Samples)
if ($lines.Count -ne 2) { throw 'Full JSONL sample history was not retained' }
foreach ($line in $lines) {
    $sample = $line | ConvertFrom-Json
    if ($sample.ui_jit_transitions -ne 6 -or $sample.jit_transitions -ne 0 -or
        -not $sample.window_title.Contains('JIT transitions: 6') -or
        $null -eq $sample.coverage_age_seconds) { throw 'Independent raw UI/coverage sample missing' }
}
'Recorder discrepancy/lifetime checks passed'
Remove-Variable -Scope Global -Name ZarvotFixtureRoot,ZarvotFixtureProcess,ZarvotFixtureCoverage,ZarvotFixtureCalls
