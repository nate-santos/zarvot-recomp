# Read periodic CLI coverage reports. No input, settings changes or FPS claims.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunRoot,
    [ValidateRange(5, 600)][int]$Seconds = 30
)
$ErrorActionPreference = 'Stop'
$RunRoot = (Resolve-Path -LiteralPath $RunRoot).Path
$launch = Get-Content -LiteralPath (Join-Path $RunRoot 'launch.json') -Raw | ConvertFrom-Json
if ($launch.state -ne 'started' -or -not $launch.pid) { throw 'Expected a started local recomp run' }
$expectedExe = Join-Path $RunRoot 'suyu-cmd.exe'
$process = Get-Process -Id $launch.pid -ErrorAction Stop
if ($process.Path -ne $expectedExe) { throw 'Run PID belongs to a different executable' }
$processStart = $process.StartTime.ToUniversalTime().ToString('o')
if ($launch.process_started_utc -and
    ([DateTime]$launch.process_started_utc).ToUniversalTime().ToString('o') -ne $processStart) {
    throw 'Run PID was reused; do not combine observations from different sessions'
}
$id = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$evidence = Join-Path $RunRoot "observations\$id"
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$samples = [Collections.Generic.List[object]]::new()
$result = [ordered]@{
    pid = $launch.pid
    process_started_utc = $processStart
    strict_requested = $launch.strict_requested
    jit_unavailable_proven = $false
    limit = 'Compiled execution only; no gameplay, full coverage or performance verdict'
    error = $null
    samples = $samples
}
$output = Join-Path $evidence 'observation.json'
function Save-Observation {
    [IO.File]::WriteAllText($output, ($result | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}
Save-Observation
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        $current = Get-Process -Id $launch.pid -ErrorAction Stop
        if ($current.Path -ne $expectedExe -or $current.StartTime.ToUniversalTime().ToString('o') -ne $processStart) {
            throw 'The original process stopped or its PID was reused'
        }
        $path = Join-Path $RunRoot 'coverage.txt'
        $sample = [ordered]@{
            timestamp_utc = [DateTime]::UtcNow.ToString('o')
            elapsed_seconds = $timer.Elapsed.TotalSeconds
            report_complete = $false
            static_blocks = $null
            jit_transitions = $null
            lookup_misses = $null
            unhandled_opcodes = $null
            unresolved_import_traps = $null
        }
        if (Test-Path -LiteralPath $path) {
            $text = [IO.File]::ReadAllText($path)
            # The runtime truncates/replaces this file; ignore partial writes.
            if ($text.Contains('=== END RECOMP EXECUTION COVERAGE ===') -and
                $text -match 'static blocks executed\s*:\s*(\d+)') {
                $sample.static_blocks = [int64]$Matches[1]
                if ($text -match 'static -> JIT\s*:\s*(\d+) \((\d+) lookup miss, (\d+) unimplemented opcode\)') {
                    $sample.jit_transitions = [int64]$Matches[1]
                    $sample.lookup_misses = [int64]$Matches[2]
                    $sample.unhandled_opcodes = [int64]$Matches[3]
                    $sample.report_complete = $true
                }
                if ($text -match 'unresolved import traps\s*:\s*(\d+)') {
                    $sample.unresolved_import_traps = [int64]$Matches[1]
                }
                if ($sample.report_complete) {
                    [IO.File]::WriteAllText((Join-Path $evidence "coverage-$($samples.Count).txt"), $text, [Text.UTF8Encoding]::new($false))
                }
            }
        }
        $samples.Add([pscustomobject]$sample)
        Save-Observation
        Start-Sleep -Seconds 2
    }
} catch {
    $result.error = $_.Exception.Message
} finally {
    $timer.Stop()
    $valid = @($samples | Where-Object report_complete)
    $result.complete_reports = $valid.Count
    $result.static_blocks_first = if ($valid.Count) { $valid[0].static_blocks } else { $null }
    $result.static_blocks_last = if ($valid.Count) { $valid[-1].static_blocks } else { $null }
    $result.compiled_count_advanced = $valid.Count -ge 2 -and
        $valid[0].static_blocks -gt 0 -and $valid[-1].static_blocks -gt $valid[0].static_blocks
    $result.max_jit_transitions = if ($valid.Count) { ($valid | Measure-Object jit_transitions -Maximum).Maximum } else { $null }
    Save-Observation
}
[pscustomobject]@{
    Evidence = $output
    CompiledCountAdvanced = $result.compiled_count_advanced
    StaticBlocksFirst = $result.static_blocks_first
    StaticBlocksLast = $result.static_blocks_last
    MaxJitTransitions = $result.max_jit_transitions
    Error = $result.error
}
