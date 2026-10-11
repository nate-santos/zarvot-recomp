# Run the real CPU recorder against fake process and WPR commands. No ETW or game actions.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$global:ZarvotCpuFixtureBase = Join-Path $root ('build\cpu-recorder-tests\' + [Guid]::NewGuid().ToString('N'))
$global:ZarvotCpuFixtureCalls = [Collections.Generic.List[object]]::new()
function Get-Command {
    [CmdletBinding()]
    param([string]$Name, $CommandType)
    if ($Name -ne 'wpr.exe') { throw 'Unexpected tool lookup' }
    [pscustomobject]@{Source='ZarvotCpuFixtureWpr'}
}
function Get-Process {
    [CmdletBinding()]
    param([int]$Id)
    $global:ZarvotCpuFixtureProcessReads++
    if ($global:ZarvotCpuFixtureProcessReads -gt 2) { return }
    $start = $global:ZarvotCpuFixtureStart
    if ($global:ZarvotCpuFixtureMode -eq 'reused' -and $global:ZarvotCpuFixtureProcessReads -gt 1) {
        $start = $start.AddSeconds(1)
    }
    $exe = Join-Path $global:ZarvotCpuFixtureRoot 'suyu-cmd.exe'
    if ($global:ZarvotCpuFixtureMode -eq 'foreign') { $exe += '.foreign' }
    [pscustomobject]@{Path=$exe; StartTime=$start}
}
function Start-Sleep { param([int]$Seconds) }
function ZarvotCpuFixtureWpr {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:ZarvotCpuFixtureCalls.Add(@($Arguments))
    $global:LASTEXITCODE = 0
    if ($Arguments[0] -eq '-start' -and $global:ZarvotCpuFixtureMode -eq 'denied') {
        $global:LASTEXITCODE = 5
        'Access is denied. Error code: 0x80070005'
    }
    elseif ($Arguments[0] -eq '-stop') {
        if ($global:ZarvotCpuFixtureMode -eq 'save_failed') {
            $global:LASTEXITCODE = 9
            'Fixture save failure'
        }
        else { [IO.File]::WriteAllBytes($Arguments[1], [byte[]]@(1,2,3)) }
    }
}
try {
    foreach ($mode in @('normal','denied','foreign','reused','save_failed')) {
        $global:ZarvotCpuFixtureMode = $mode
        $global:ZarvotCpuFixtureRoot = Join-Path $global:ZarvotCpuFixtureBase $mode
        [IO.Directory]::CreateDirectory($global:ZarvotCpuFixtureRoot) | Out-Null
        $global:ZarvotCpuFixtureStart = [DateTime]::UtcNow
        $global:ZarvotCpuFixtureProcessReads = 0
        $global:ZarvotCpuFixtureCalls.Clear()
        @{
            state='started'; pid=123; run_root=$global:ZarvotCpuFixtureRoot
            process_started_utc=$global:ZarvotCpuFixtureStart.ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $global:ZarvotCpuFixtureRoot 'launch.json') -Encoding utf8
        $recorded = & (Join-Path $root 'scripts\measure-zarvot-cpu.ps1') -RunRoot $global:ZarvotCpuFixtureRoot
        $summary = Get-Content -LiteralPath $recorded.Evidence -Raw | ConvertFrom-Json
        foreach ($call in $global:ZarvotCpuFixtureCalls) {
            if ($call[-2] -ne '-instancename' -or $call[-1] -ne $summary.wpr_instance) {
                throw "$mode operated on an unrelated/default WPR instance"
            }
        }
        $actions = @($global:ZarvotCpuFixtureCalls | ForEach-Object { $_[0] })
        if ($actions -contains '-start') {
            $startCall = $global:ZarvotCpuFixtureCalls[0]
            if ($startCall.Count -ne 7 -or $startCall[1] -ne 'CPU.Verbose' -or
                $startCall[2] -ne '-filemode' -or $startCall[3] -ne '-recordtempto' -or
                -not (Test-Path -LiteralPath $startCall[4])) {
                throw "$mode lost the explicit CPU/file-mode/output arguments"
            }
        }
        switch ($mode) {
            normal {
                if ($summary.state -ne 'complete' -or $summary.end_reason -ne 'process_exited' -or
                    $summary.trace_bytes -ne 3 -or $actions -contains '-cancel' -or $actions -notcontains '-stop') {
                    throw 'Normal process exit failed to save owned trace'
                }
            }
            denied {
                if ($summary.state -ne 'error' -or $summary.end_reason -ne 'wpr_start_failed' -or
                    $summary.recording_started -or $summary.error -notmatch 'Access is denied' -or
                    $actions.Count -ne 1 -or $actions[0] -ne '-start') {
                    throw 'Denied start was hidden or attempted to clean up an unowned session'
                }
            }
            foreign {
                if ($summary.state -ne 'error' -or $actions.Count -ne 0) {
                    throw 'Foreign process was profiled'
                }
            }
            reused {
                if ($summary.state -ne 'error' -or $summary.error -notmatch 'identity changed' -or
                    $actions -notcontains '-stop' -or $summary.trace_bytes -ne 3) {
                    throw 'PID reuse failed to stop/save only the owned recording'
                }
            }
            save_failed {
                if ($summary.state -ne 'error' -or -not $summary.cleanup_error -or
                    $actions[-1] -ne '-cancel' -or $summary.trace_file) {
                    throw 'Failed save did not clean up the successfully started owned instance'
                }
            }
        }
    }
    'CPU recorder ownership, denied-start, process-exit, PID-reuse and save-failure checks passed'
}
finally {
    Remove-Variable -Scope Global -Name ZarvotCpuFixtureBase,ZarvotCpuFixtureCalls,ZarvotCpuFixtureMode,ZarvotCpuFixtureRoot,ZarvotCpuFixtureStart,ZarvotCpuFixtureProcessReads -ErrorAction SilentlyContinue
}
