# Sample native CPU stacks during user-led recomp play. Sends no game input.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunRoot,
    [ValidateRange(5, 3600)][int]$Seconds = 900
)
$ErrorActionPreference = 'Stop'
$RunRoot = (Resolve-Path -LiteralPath $RunRoot).Path
$launch = Get-Content -LiteralPath (Join-Path $RunRoot 'launch.json') -Raw | ConvertFrom-Json
$id = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$evidence = Join-Path $RunRoot "cpu-profiles/$id"
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$output = Join-Path $evidence 'cpu-profile.json'
$trace = Join-Path $evidence 'cpu.etl'
$commands = Join-Path $evidence 'wpr-commands.jsonl'
$instance = 'ZarvotCPU-' + [Guid]::NewGuid().ToString('N')
$expectedExe = Join-Path $RunRoot 'suyu-cmd.exe'
$result = [ordered]@{
    profile_version = 1
    run_root = $RunRoot
    pid = $launch.pid
    expected_executable = $expectedExe
    process_started_utc = $null
    recorder_pid = $PID
    started_utc = [DateTime]::UtcNow.ToString('o')
    heartbeat_utc = [DateTime]::UtcNow.ToString('o')
    finished_utc = $null
    seconds_limit = $Seconds
    profile = 'CPU.Verbose'
    logging_mode = 'file'
    wpr_instance = $instance
    state = 'validating'
    recording_started = $false
    elapsed_seconds = 0
    end_reason = $null
    trace_file = $null
    trace_bytes = $null
    error = $null
    cleanup_error = $null
    limit = 'System-wide statistical CPU samples; filter the exact game process and route. Not frame timings or an exact duration per call.'
}
function Save-CpuProfile {
    $result.heartbeat_utc = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText($output, ($result | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
}
function Invoke-OwnedWpr([string[]]$Arguments) {
    # WPR requires the instance argument last. Never operate on the default session.
    $argumentsWithInstance = @($Arguments) + @('-instancename', $instance)
    $global:LASTEXITCODE = 0
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $text = (& $wprExe @argumentsWithInstance 2>&1 | Out-String).Trim() }
    finally { $ErrorActionPreference = $previousPreference }
    $code = $LASTEXITCODE
    $entry = [ordered]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        arguments = $argumentsWithInstance
        exit_code = $code
        output = $text
    }
    [IO.File]::AppendAllText($commands, (($entry | ConvertTo-Json -Compress -Depth 4) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ExitCode=$code; Output=$text}
}
function Get-OwnedGame {
    $current = Get-Process -Id $launch.pid -ErrorAction SilentlyContinue
    if (-not $current) { return $null }
    if ($current.Path -ne $expectedExe -or
        $current.StartTime.ToUniversalTime().ToString('o') -ne $result.process_started_utc) {
        throw 'The recorded game process identity changed; its PID may have been reused'
    }
    return $current
}
Save-CpuProfile
$ownedRecording = $false
$timer = [Diagnostics.Stopwatch]::new()
try {
    if ($launch.state -ne 'started' -or -not $launch.pid -or -not $launch.process_started_utc -or
        -not $launch.run_root -or [IO.Path]::GetFullPath($launch.run_root) -ne $RunRoot) {
        throw 'Expected a started recomp launch record with matching run root, PID and start time'
    }
    $result.process_started_utc = ([DateTime]$launch.process_started_utc).ToUniversalTime().ToString('o')
    if (-not (Get-OwnedGame)) { throw 'The recorded game process has already exited' }
    $wprExe = (Get-Command wpr.exe -CommandType Application -ErrorAction Stop).Source
    $result.state = 'starting'
    Save-CpuProfile
    $start = Invoke-OwnedWpr -Arguments @('-start', 'CPU.Verbose', '-filemode', '-recordtempto', $evidence)
    if ($start.ExitCode -ne 0) {
        $result.end_reason = 'wpr_start_failed'
        throw "WPR could not start (exit $($start.ExitCode)): $($start.Output)"
    }
    $ownedRecording = $true
    $result.recording_started = $true
    $result.state = 'recording'
    $timer.Start()
    Save-CpuProfile
    # Retain status diagnostics, including any reported lost events, for analysis.
    $null = Invoke-OwnedWpr -Arguments @('-status', 'collectors', '-details')
    $lastSave = 0
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        if (-not (Get-OwnedGame)) { $result.end_reason = 'process_exited'; break }
        $result.elapsed_seconds = $timer.Elapsed.TotalSeconds
        if ($timer.Elapsed.TotalSeconds - $lastSave -ge 10) {
            Save-CpuProfile
            $lastSave = $timer.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 2
    }
    if (-not $result.end_reason) { $result.end_reason = 'duration_limit' }
}
catch {
    $result.error = $_.Exception.Message
    $result.state = 'error'
    if (-not $result.end_reason) { $result.end_reason = 'error' }
}
finally {
    if ($ownedRecording) {
        $result.state = 'saving'
        try {
            $null = Invoke-OwnedWpr -Arguments @('-status', 'collectors', '-details')
            $stop = Invoke-OwnedWpr -Arguments @('-stop', $trace, 'Zarvot user-led recomp CPU capture', '-skipPdbGen')
            if ($stop.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $trace)) {
                throw "WPR could not save the trace (exit $($stop.ExitCode)): $($stop.Output)"
            }
            $result.trace_file = 'cpu.etl'
            $result.trace_bytes = (Get-Item -LiteralPath $trace).Length
            $ownedRecording = $false
        }
        catch {
            $result.cleanup_error = $_.Exception.Message
            # Only our successfully started unique instance is eligible for cleanup.
            try {
                $cancel = Invoke-OwnedWpr -Arguments @('-cancel')
                if ($cancel.ExitCode -ne 0) {
                    $result.cleanup_error += " | Owned-instance cancel failed (exit $($cancel.ExitCode)): $($cancel.Output)"
                }
            }
            catch { $result.cleanup_error += " | Owned-instance cancel failed: $($_.Exception.Message)" }
        }
    }
    $timer.Stop()
    $result.elapsed_seconds = $timer.Elapsed.TotalSeconds
    $result.finished_utc = [DateTime]::UtcNow.ToString('o')
    $result.state = if ($result.error -or $result.cleanup_error) { 'error' } else { 'complete' }
    Save-CpuProfile
}
[pscustomobject]@{Evidence=$output; Trace=if ($result.trace_file) {$trace} else {$null}; State=$result.state; EndReason=$result.end_reason; Error=$result.error; CleanupError=$result.cleanup_error}
