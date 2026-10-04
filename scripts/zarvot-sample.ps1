[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Scene,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$EmulatorPath,
    [ValidateRange(5, 3600)][int]$Seconds = 60,
    [int]$Port = 9742,
    [switch]$IncludeGpuCounters
)

# FPS/frame_ms are interval telemetry, NOT individual frame measurements.
# This intentionally reports no 1% lows, frame percentiles or CPU/GPU time split.
$ErrorActionPreference = 'Stop'
$expectedPath = (Resolve-Path -LiteralPath $EmulatorPath).Path
$processes = @(Get-Process suyu -ErrorAction SilentlyContinue | Where-Object Path -eq $expectedPath)
if ($processes.Count -ne 1) { throw "Expected one emulator at $expectedPath; found $($processes.Count)" }
$emulatorProcess = $processes[0]
$logicalCores = [Environment]::ProcessorCount
$gpuError = $null
$gpuPaths = @()
if ($IncludeGpuCounters) {
    try {
        # Discover once; repeated wildcard discovery substantially increases overhead.
        $initial = Get-Counter -Counter '\GPU Engine(*)\Utilization Percentage' -MaxSamples 1 -ErrorAction Stop
        $gpuPaths = @($initial.CounterSamples | Where-Object InstanceName -like "pid_$($emulatorProcess.Id)_*" | ForEach-Object Path)
        if (-not $gpuPaths.Count) { throw 'No GPU engine counters for this process' }
    } catch { $gpuError = $_.Exception.Message }
}
$samples = [Collections.Generic.List[object]]::new()
$clock = [Diagnostics.Stopwatch]::StartNew()
$previousTime = 0.0
$previousCpu = $emulatorProcess.TotalProcessorTime.TotalSeconds
while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
    $requestStart = $clock.Elapsed.TotalSeconds
    $response = & "$PSScriptRoot/zarvot-rpc.ps1" -Tool get_emulator_state -Port $Port -TimeoutSeconds 5
    if ($response.result.isError) { throw ($response.result | ConvertTo-Json -Depth 10) }
    $block = $response.result.content | Where-Object type -eq text | Select-Object -First 1
    $state = $block.text | ConvertFrom-Json
    if (-not $state.game_running) { throw 'Game stopped; this measurement is incomplete' }
    $gpuEngines = @()
    if ($IncludeGpuCounters -and -not $gpuError) {
        try {
            $counters = Get-Counter -Counter $gpuPaths -MaxSamples 1 -ErrorAction Stop
            $gpuEngines = @($counters.CounterSamples | Where-Object InstanceName -like "pid_$($emulatorProcess.Id)_*" |
                ForEach-Object { [pscustomobject]@{ Engine=$_.InstanceName; UtilizationPercent=$_.CookedValue } })
        } catch { $gpuError = $_.Exception.Message }
    }
    $emulatorProcess.Refresh()
    $elapsed = $clock.Elapsed.TotalSeconds
    $cpu = $emulatorProcess.TotalProcessorTime.TotalSeconds
    $interval = $elapsed - $previousTime
    $samples.Add([pscustomobject]@{
        ElapsedSeconds=$elapsed
        FpsObservationElapsedSeconds=$requestStart
        CollectionSeconds=$elapsed-$requestStart
        Fps=$state.fps
        VblanksPerSecond=$state.vps
        ReportedFrameMs=$state.frame_ms
        EmulationSpeed=$state.emulation_speed
        GameRunning=$state.game_running
        EmulationThreadRunning=$state.emulation_thread_running
        ShadersBuilding=$state.shaders_building
        StaticBackendActive=$state.static_backend_active
        TasFrame=$state.tas_frame
        TasRunning=$state.tas_running
        TasCompletionGeneration=$state.tas_completion_generation
        CpuCoreEquivalents=($cpu-$previousCpu)/$interval
        CpuMachinePercent=100*($cpu-$previousCpu)/$interval/$logicalCores
        WorkingSetBytes=$emulatorProcess.WorkingSet64
        PrivateBytes=$emulatorProcess.PrivateMemorySize64
        GpuEngines=$gpuEngines
    })
    $previousTime=$elapsed
    $previousCpu=$cpu
    # Aim for about one health sample per second; actual interval is recorded.
    $remaining = 1-($clock.Elapsed.TotalSeconds-$requestStart)
    if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int]($remaining*1000)) }
}
$fps = @($samples | ForEach-Object Fps)
$sorted = @($fps | Sort-Object)
$median = if ($sorted.Count % 2) { $sorted[[int][Math]::Floor($sorted.Count/2)] } else { ($sorted[$sorted.Count/2-1]+$sorted[$sorted.Count/2])/2 }
$stats = $fps | Measure-Object -Average -Minimum -Maximum
$summary = [pscustomobject]@{
    Samples=$samples.Count
    DurationSeconds=$clock.Elapsed.TotalSeconds
    SampledFpsMean=$stats.Average
    SampledFpsMedian=$median
    SampledFpsMin=$stats.Minimum
    SampledFpsMax=$stats.Maximum
    SamplesBelow55=@($fps | Where-Object { $_ -lt 55 }).Count
    SamplesWithEmulationStopped=@($samples | Where-Object { -not $_.EmulationThreadRunning }).Count
    SamplesWithTasActive=@($samples | Where-Object { $_.TasRunning }).Count
    CpuCoreEquivalentsMean=($samples | Measure-Object CpuCoreEquivalents -Average).Average
    WorkingSetPeakBytes=($samples | Measure-Object WorkingSetBytes -Maximum).Maximum
}
$result = [pscustomobject]@{
    TimestampUtc=[DateTime]::UtcNow.ToString('o')
    Scene=$Scene
    EmulatorPid=$emulatorProcess.Id
    EmulatorSha256=(Get-FileHash -LiteralPath $expectedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    LogicalProcessors=$logicalCores
    Focus='Caller must keep game visible and foreground; not verified by this sampler'
    MetricLimit='Interval polling only; cannot derive per-frame p95/p99, 1% lows or CPU/GPU critical path'
    GpuCounterError=$gpuError
    Summary=$summary
    Samples=$samples
}
$output = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output, ($result | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json
