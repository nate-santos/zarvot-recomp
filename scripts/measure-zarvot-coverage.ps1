# Record the owned CLI's actual title and coverage independently. Sends no input.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunRoot,
    [ValidateRange(5, 600)][int]$Seconds = 30,
    [switch]$UntilExit
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'zarvot-telemetry.ps1')
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
$evidence = Join-Path $RunRoot "observations/$id"
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$samples = [Collections.Generic.List[object]]::new()
$result = [ordered]@{
    observation_version = 2
    pid = $launch.pid
    process_started_utc = $processStart
    strict_requested = $launch.strict_requested
    jit_unavailable_proven = $false
    until_exit = [bool]$UntilExit
    limit = 'UI polls and compiled execution only; no per-frame, gameplay or full coverage verdict'
    samples_file = 'samples.jsonl'
    samples_retained_limit = 300
    sample_count = 0
    complete_reports = 0
    static_blocks_first = $null
    static_blocks_last = $null
    max_jit_transitions = $null
    max_lookup_misses = $null
    max_unhandled_opcodes = $null
    max_unresolved_import_traps = $null
    max_ui_jit_transitions = $null
    ui_nonzero_first_utc = $null
    ui_coverage_disagreements = 0
    file_counter_regressions = 0
    ui_counter_regressions = 0
    pc_samples_present = $false
    compiled_count_advanced = $false
    end_reason = 'recording'
    error = $null
    samples = $samples
}
$output = Join-Path $evidence 'observation.json'
$stream = Join-Path $evidence 'samples.jsonl'
function Save-Observation {
    $result.compiled_count_advanced = $result.complete_reports -ge 2 -and
        $result.static_blocks_first -gt 0 -and $result.static_blocks_last -gt $result.static_blocks_first -and
        $result.file_counter_regressions -eq 0
    [IO.File]::WriteAllText($output, ($result | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}
function Set-Maximum([string]$Name, $Value) {
    if ($null -ne $Value -and ($null -eq $result[$Name] -or $Value -gt $result[$Name])) {
        $result[$Name] = $Value
    }
}
Save-Observation
$timer = [Diagnostics.Stopwatch]::StartNew()
$lastSaveSeconds = 0
$previousUiCount = $null
$previousFileCount = $null
$previousBlocks = $null
$lastRawText = $null
$lastRawPath = $null
try {
    while ($UntilExit -or $timer.Elapsed.TotalSeconds -lt $Seconds) {
        $current = Get-Process -Id $launch.pid -ErrorAction SilentlyContinue
        if (-not $current) { $result.end_reason = 'process_exited'; break }
        if ($current.Path -ne $expectedExe -or $current.StartTime.ToUniversalTime().ToString('o') -ne $processStart) {
            throw 'The original process identity changed; its PID may have been reused'
        }
        $current.Refresh()
        $title = $current.MainWindowTitle
        $ui = ConvertFrom-ZarvotWindowTitle $title
        $sample = [ordered]@{
            sequence = $result.sample_count
            timestamp_utc = [DateTime]::UtcNow.ToString('o')
            elapsed_seconds = $timer.Elapsed.TotalSeconds
            window_title = $title
            ui_jit_transitions = $ui.jit_transitions
            ui_shaders_building = $ui.shaders_building
            ui_fps = $ui.fps
            report_complete = $false
            static_blocks = $null
            jit_transitions = $null
            lookup_misses = $null
            unhandled_opcodes = $null
            unresolved_import_traps = $null
            coverage_written_utc = $null
            coverage_age_seconds = $null
            coverage_snapshot = $null
            coverage_read_error = $null
            ui_coverage_disagrees = $null
        }
        if ($null -ne $ui.jit_transitions) {
            Set-Maximum 'max_ui_jit_transitions' $ui.jit_transitions
            if ($ui.jit_transitions -gt 0 -and -not $result.ui_nonzero_first_utc) {
                $result.ui_nonzero_first_utc = $sample.timestamp_utc
            }
            if ($null -ne $previousUiCount -and $ui.jit_transitions -lt $previousUiCount) {
                $result.ui_counter_regressions++
            }
            $previousUiCount = $ui.jit_transitions
        }
        $path = Join-Path $RunRoot 'coverage.txt'
        if (Test-Path -LiteralPath $path) {
            try {
                $written = (Get-Item -LiteralPath $path).LastWriteTimeUtc
                $sample.coverage_written_utc = $written.ToString('o')
                $sample.coverage_age_seconds = ([DateTime]::UtcNow - $written).TotalSeconds
                $rawText = [IO.File]::ReadAllText($path)
                # Keep changed partial reports too; another writer may be truncating it.
                if ($rawText -cne $lastRawText) {
                    $lastRawPath = "coverage-$($result.sample_count).txt"
                    [IO.File]::WriteAllText((Join-Path $evidence $lastRawPath), $rawText, [Text.UTF8Encoding]::new($false))
                    $lastRawText = $rawText
                }
                $sample.coverage_snapshot = $lastRawPath
                $coverage = ConvertFrom-ZarvotCoverage $rawText
                foreach ($name in @('report_complete', 'static_blocks', 'jit_transitions', 'lookup_misses',
                                    'unhandled_opcodes', 'unresolved_import_traps')) {
                    $sample[$name] = $coverage.$name
                }
                if ($coverage.report_complete) {
                    $result.complete_reports++
                    if ($null -eq $result.static_blocks_first) { $result.static_blocks_first = $coverage.static_blocks }
                    $result.static_blocks_last = $coverage.static_blocks
                    Set-Maximum 'max_jit_transitions' $coverage.jit_transitions
                    Set-Maximum 'max_lookup_misses' $coverage.lookup_misses
                    Set-Maximum 'max_unhandled_opcodes' $coverage.unhandled_opcodes
                    Set-Maximum 'max_unresolved_import_traps' $coverage.unresolved_import_traps
                    if (($null -ne $previousFileCount -and $coverage.jit_transitions -lt $previousFileCount) -or
                        ($null -ne $previousBlocks -and $coverage.static_blocks -lt $previousBlocks)) {
                        $result.file_counter_regressions++
                    }
                    $previousFileCount = $coverage.jit_transitions
                    $previousBlocks = $coverage.static_blocks
                    if ($rawText -match 'distinct sampled PCs') { $result.pc_samples_present = $true }
                    if ($null -ne $ui.jit_transitions) {
                        $sample.ui_coverage_disagrees = $ui.jit_transitions -ne $coverage.jit_transitions
                        if ($sample.ui_coverage_disagrees) { $result.ui_coverage_disagreements++ }
                    }
                }
            } catch {
                # A failed read is unknown telemetry; keep recording the independent UI.
                $sample.coverage_read_error = $_.Exception.Message
            }
        }
        $result.sample_count++
        $samples.Add([pscustomobject]$sample)
        if ($samples.Count -gt $result.samples_retained_limit) { $samples.RemoveAt(0) }
        [IO.File]::AppendAllText($stream, (($sample | ConvertTo-Json -Compress -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        # Bounded summary writes avoid rewriting an ever-growing recording while playing.
        if ($timer.Elapsed.TotalSeconds - $lastSaveSeconds -ge 10) {
            Save-Observation
            $lastSaveSeconds = $timer.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 2
    }
    if ($result.end_reason -eq 'recording') { $result.end_reason = 'duration_limit' }
} catch {
    $result.error = $_.Exception.Message
    $result.end_reason = 'error'
} finally {
    $timer.Stop()
    Save-Observation
}
[pscustomobject]@{
    Evidence = $output
    Samples = $stream
    CompiledCountAdvanced = $result.compiled_count_advanced
    StaticBlocksFirst = $result.static_blocks_first
    StaticBlocksLast = $result.static_blocks_last
    MaxJitTransitions = $result.max_jit_transitions
    MaxUiJitTransitions = $result.max_ui_jit_transitions
    UiCoverageDisagreements = $result.ui_coverage_disagreements
    EndReason = $result.end_reason
    Error = $result.error
}
