# Stage the complete Zarvot DLL set with an isolated portable profile, then boot.
# Sends no controller input. Keep this local directory out of release packages.
[CmdletBinding()]
param(
    [string]$Rom,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')][string]$Target = 'zarvot',
    [ValidateNotNullOrEmpty()][string]$Package = 'out\Zarvot - Hybrid AOT + JIT',
    [string]$HostRoot,
    [switch]$Strict,
    [switch]$Capture,
    [switch]$Visible,
    [switch]$RecordCoverage,
    [switch]$StallProbe,
    [switch]$SamplePc,
    [ValidateRange(0, 86400)][int]$SampleAfterSeconds = 120,
    [string]$ProfileFromRun,
    [switch]$AllowSameGameProfileReuse,
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'
if ($RecordCoverage -and $StageOnly) { throw 'RecordCoverage requires a running game; it cannot be combined with StageOnly' }
. (Join-Path $PSScriptRoot 'zarvot-profile.ps1')
$root = Split-Path -Parent $PSScriptRoot
if ($AllowSameGameProfileReuse -and -not $ProfileFromRun) {
    throw 'Same-game profile reuse requires an explicit ProfileFromRun'
}
if (-not $Rom) { $Rom = Join-Path (Split-Path -Parent $root) 'Zarvot.nsp' }
$Rom = (Resolve-Path -LiteralPath $Rom).Path
$buildRoot = Join-Path $root "build\recomp\$Target"
$exportRoot = [IO.Path]::GetFullPath((Join-Path $root "generated\$Target\$Package\aot_cache"))
$allowedExportRoot = [IO.Path]::GetFullPath((Join-Path $root "generated\$Target")) + [IO.Path]::DirectorySeparatorChar
if (-not $exportRoot.StartsWith($allowedExportRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Package resolved outside the selected generated target'
}
if (-not $HostRoot) { $HostRoot = Join-Path $root 'build\suyu\bin' }
$HostRoot = (Resolve-Path -LiteralPath $HostRoot).Path.TrimEnd('\')
if (-not $HostRoot.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'HostRoot must stay inside this project checkout'
}
$build = Get-Content -LiteralPath (Join-Path $buildRoot 'build-status.json') -Raw | ConvertFrom-Json
$manifestPath = Join-Path $exportRoot 'aot_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = @('main', 'rtld', 'sdk', 'subsdk0')
if ($build.state -ne 'complete' -or $build.image_abi -ne 6 -or
    ($build.target -and $build.target -ne $Target) -or
    $manifest.image_abi -ne $build.image_abi -or $manifest.image_features -ne $build.image_features -or
    $manifestHash -ne $build.export_manifest_sha256 -or
    @($build.modules).Count -ne 4 -or $manifest.total_modules -ne 4 -or
    @(Compare-Object $expected @($build.modules.name | Sort-Object)).Count -ne 0 -or
    @(Compare-Object $expected @($manifest.modules.name | Sort-Object)).Count -ne 0) {
    throw 'Build all four modules from the current export before staging a CLI run'
}
$images = @()
foreach ($module in $build.modules) {
    $name = if ($module.name -eq 'main') { 'recompiled_image.dll' } else { "recompiled_$($module.name).dll" }
    $path = Join-Path $buildRoot "$($module.name)\$name"
    if ($module.state -ne 'complete' -or (Get-Item -LiteralPath $path).Length -ne $module.bytes -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $module.sha256) {
        throw "Compiled image identity does not match build evidence: $name"
    }
    $images += [pscustomobject]@{ Name = $name; Path = $path; Sha256 = $module.sha256 }
}
$hostPath = Join-Path $HostRoot 'suyu-cmd.exe'
$hostHash = (Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToLowerInvariant()
$keysRoot = Join-Path $HostRoot 'user\keys'
if (-not (Test-Path -LiteralPath (Join-Path $keysRoot 'prod.keys'))) {
    throw 'The matching local build profile must already contain the supplied keys'
}
# Preserve existing player/test sessions. This launcher never stops one.
if (-not $StageOnly -and @(Get-Process suyu,suyu-cmd -ErrorAction SilentlyContinue).Count) {
    throw 'An emulator session is already running; preserve it before starting a separate test'
}

# Clone only a closed, recorded test profile; preserve its saves and raw evidence.
function Assert-ZarvotProfileClosed($SourceRoot, $Launch) {
    if ($Launch.state -ne 'started' -or -not $Launch.pid -or -not $Launch.process_started_utc) {
        throw 'Profile source needs a recorded process identity before closure can be verified'
    }
    $started = ([DateTime]$Launch.process_started_utc).ToUniversalTime()
    $sourceExe = Join-Path $SourceRoot 'suyu-cmd.exe'
    $recorded = Get-Process -Id $Launch.pid -ErrorAction SilentlyContinue
    if ($recorded) {
        if (-not $recorded.Path -or -not $recorded.StartTime) {
            throw 'Cannot verify closure of the recorded source process'
        }
        if ($recorded.Path -eq $sourceExe) {
            throw 'Close the source test session before cloning its profile'
        }
        if ($recorded.StartTime.ToUniversalTime() -eq $started) {
            throw 'The recorded source process has a conflicting executable identity'
        }
    }
    # Also reject a manually restarted instance using the same saved profile.
    foreach ($process in @(Get-Process suyu,suyu-cmd -ErrorAction SilentlyContinue)) {
        if (-not $process.Path) { throw 'Cannot verify the source profile is closed' }
        if ($process.Path -eq $sourceExe) {
            throw 'Close the source test session before cloning its profile'
        }
    }
}
function Assert-ZarvotSameGame($Before, $After) {
    # The whole ExeFS hash binds segment contents; the per-module build IDs and
    # segment layouts must also agree. Code-generation statistics may differ.
    if ($Before.version -ne 2 -or $After.version -ne 2 -or
        $Before.source_exefs_sha256 -notmatch '^[0-9a-f]{64}$' -or
        $After.source_exefs_sha256 -notmatch '^[0-9a-f]{64}$' -or
        $Before.source_exefs_sha256 -ne $After.source_exefs_sha256 -or
        $Before.total_modules -ne 4 -or $After.total_modules -ne 4 -or
        @(Compare-Object $expected @($Before.modules.name | Sort-Object)).Count -ne 0 -or
        @(Compare-Object $expected @($After.modules.name | Sort-Object)).Count -ne 0) {
        throw 'Cross-build profile reuse requires matching source ExeFS and module identities'
    }
    foreach ($name in $expected) {
        $beforeModule = @($Before.modules | Where-Object name -eq $name)
        $afterModule = @($After.modules | Where-Object name -eq $name)
        if ($beforeModule.Count -ne 1 -or $afterModule.Count -ne 1 -or
            $beforeModule[0].build_id -notmatch '^[0-9a-f]{64}$' -or
            $beforeModule[0].build_id -ne $afterModule[0].build_id) {
            throw "Cross-build profile reuse found a different module build ID: $name"
        }
        foreach ($field in @('text_vaddr','text_size','rodata_vaddr','rodata_size','data_vaddr','data_size')) {
            $beforeValue = $beforeModule[0].$field
            $afterValue = $afterModule[0].$field
            if ($null -eq $beforeValue -or $null -eq $afterValue -or
                "$beforeValue" -notmatch '^\d+$' -or "$afterValue" -notmatch '^\d+$' -or
                [uint64]$beforeValue -ne [uint64]$afterValue) {
                throw "Cross-build profile reuse found a different or missing segment identity: $name/$field"
            }
        }
    }
}
$profileRoot = $null
$profileConfig = $null
$oldManifestHash = $null
if ($ProfileFromRun) {
    $profileRoot = (Resolve-Path -LiteralPath $ProfileFromRun).Path.TrimEnd('\')
    $runsRoot = [IO.Path]::GetFullPath((Join-Path $root 'build\zarvot-runs')).TrimEnd('\')
    if ((Split-Path -Parent $profileRoot) -ne $runsRoot) {
        throw 'Profile source must be a direct child of this project''s zarvot-runs directory'
    }
    $oldLaunch = Get-Content -LiteralPath (Join-Path $profileRoot 'launch.json') -Raw | ConvertFrom-Json
    if ($oldLaunch.run_root -ne $profileRoot) {
        throw 'Profile source does not match its recorded run root'
    }
    Assert-ZarvotProfileClosed $profileRoot $oldLaunch
    $oldManifestPath = Join-Path $profileRoot 'aot_manifest.json'
    $oldManifestHash = (Get-FileHash -LiteralPath $oldManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($oldManifestHash -ne $oldLaunch.export_manifest_sha256) {
        throw 'Profile source manifest does not match its recorded export identity'
    }
    if ($AllowSameGameProfileReuse) {
        $oldManifest = Get-Content -LiteralPath $oldManifestPath -Raw | ConvertFrom-Json
        if ($oldLaunch.image_abi -ne $oldManifest.image_abi -or
            $oldLaunch.image_features -ne $oldManifest.image_features) {
            throw 'Profile source feature identity does not match its recorded manifest'
        }
        Assert-ZarvotSameGame $oldManifest $manifest
    } elseif ($oldLaunch.host_sha256 -ne $hostHash -or $oldManifestHash -ne $manifestHash) {
        throw 'Profile source does not match the recorded runtime/export identity'
    }
    if (@($oldLaunch.modules).Count -ne 4 -or
        @(Compare-Object $expected @($oldLaunch.modules.name | Sort-Object)).Count -ne 0) {
        throw 'Profile source has an incomplete recorded compiled module set'
    }
    foreach ($module in $build.modules) {
        $oldModule = @($oldLaunch.modules | Where-Object name -eq $module.name)
        if ($oldModule.Count -ne 1 -or $oldModule[0].state -ne 'complete' -or
            $oldModule[0].sha256 -notmatch '^[0-9a-f]{64}$' -or
            (-not $AllowSameGameProfileReuse -and $oldModule[0].sha256 -ne $module.sha256)) {
            throw 'Profile source used a different compiled module set'
        }
    }
    $profileConfig = [IO.File]::ReadAllText((Join-Path $profileRoot 'user\config\sdl-config.ini'))
    $profileConfig = ConvertTo-ZarvotProfileConfig $profileConfig $profileRoot $profileRoot
}

$runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runRoot = Join-Path $root "build\zarvot-runs\$runId"
foreach ($dir in @('', 'user\keys', 'user\config', 'user\nand', 'user\sdmc', 'user\load', 'user\dump', 'user\tas', 'captures')) {
    [IO.Directory]::CreateDirectory((Join-Path $runRoot $dir)) | Out-Null
}
Copy-Item -LiteralPath $hostPath -Destination $runRoot
# Copy host dependencies only; no export README (which redirects keys/NAND).
Get-ChildItem -LiteralPath $HostRoot -File -Filter '*.dll' | Where-Object Name -notlike 'recompiled_*' |
    Copy-Item -Destination $runRoot
foreach ($image in $images) { Copy-Item -LiteralPath $image.Path -Destination (Join-Path $runRoot $image.Name) }
foreach ($name in @('prod.keys', 'title.keys')) {
    $keyPath = Join-Path $keysRoot $name
    if (Test-Path -LiteralPath $keyPath) { Copy-Item -LiteralPath $keyPath -Destination (Join-Path $runRoot "user\keys\$name") }
}
# Fresh settings retain original timing and the recorded handheld 1x/HIGH setup.
# Default runs start fresh; explicit test-profile reuse is validated and rebased below.
$config = @'
[Core]
use_speed_limit=true
use_speed_limit\default=false
speed_limit=100
speed_limit\default=false
[Renderer]
backend=1
backend\default=false
resolution_setup=3
resolution_setup\default=false
gpu_accuracy=1
gpu_accuracy\default=false
[System]
use_docked_mode=0
use_docked_mode\default=false
[Controls]
tas_enable=false
tas_enable\default=false
[Miscellaneous]
log_filter=*:Info
'@
$config += "`n[Data%20Storage]`n"
foreach ($setting in @(@('nand_directory', 'nand'), @('save_directory', 'nand'),
                       @('sdmc_directory', 'sdmc'), @('load_directory', 'load'),
                       @('dump_directory', 'dump'), @('tas_directory', 'tas'))) {
    $path = (Join-Path $runRoot "user\$($setting[1])").Replace('\', '/')
    $config += "$($setting[0])=$path`n"
}
$configPath = Join-Path $runRoot 'user\config\sdl-config.ini'
[IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))
if ($profileRoot) {
    Assert-ZarvotProfileClosed $profileRoot $oldLaunch
    foreach ($dir in @('nand', 'sdmc', 'cache', 'shader', 'load', 'system')) {
        $source = Join-Path $profileRoot "user\$dir"
        if (Test-Path -LiteralPath $source) {
            $destination = Join-Path $runRoot "user\$dir"
            [IO.Directory]::CreateDirectory($destination) | Out-Null
            Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $destination -Recurse -Force
        }
    }
    # Retain the tested input/settings while rebasing its isolated storage paths.
    $config = ConvertTo-ZarvotProfileConfig $profileConfig $profileRoot $runRoot
    [IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))
}
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $runRoot 'aot_manifest.json')
$launch = [ordered]@{
    started_utc = [DateTime]::UtcNow.ToString('o')
    run_root = $runRoot
    rom_path = $Rom
    target = $Target
    package = $Package
    host_source_root = $HostRoot
    host_sha256 = $hostHash
    export_manifest_sha256 = $manifestHash
    image_abi = $build.image_abi
    image_features = $build.image_features
    modules = $build.modules
    strict_requested = [bool]$Strict
    visible_requested = [bool]$Visible
    pc_sampling_requested = [bool]$SamplePc
    pc_sample_after_seconds = if ($SamplePc) { $SampleAfterSeconds } else { $null }
    pc_sample_shift = if ($SamplePc) { 18 } else { $null }
    coverage_recording_requested = [bool]$RecordCoverage
    stall_probe_requested = [bool]$StallProbe
    coverage_recorder_state = if ($RecordCoverage) { 'pending' } else { 'not_requested' }
    coverage_recorder_pid = $null
    coverage_recorder_started_utc = $null
    coverage_observation_path = $null
    coverage_recorder_error = $null
    profile_source_run_id = if ($profileRoot) { Split-Path -Leaf $profileRoot } else { $null }
    profile_source_manifest_sha256 = $oldManifestHash
    profile_reuse_mode = if (-not $profileRoot) { $null } elseif ($AllowSameGameProfileReuse) { 'same-game-cross-build' } else { 'same-build' }
    jit_unavailable_proven = $false
    controller_input_sent = $false
    state = 'staged'
}
$launchPath = Join-Path $runRoot 'launch.json'
function Save-Launch { [IO.File]::WriteAllText($launchPath, ($launch | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false)) }
Save-Launch
if (-not $StageOnly) {
    # Clear inherited diagnostic overrides only in this process, then restore.
    $previous = @{}
    Get-ChildItem Env: | Where-Object { $_.Name -like 'SUYU_RECOMP_*' -or $_.Name -like 'SUYU_CMD_*' -or $_.Name -eq 'SUYU_STALL_PROBE' } |
        ForEach-Object { $previous[$_.Name] = $_.Value; Remove-Item -LiteralPath "Env:\$($_.Name)" }
    try {
        $env:SUYU_RECOMP_STRICT = if ($Strict) { '1' } else { '0' }
        $env:SUYU_RECOMP_COVERAGE_PATH = Join-Path $runRoot 'coverage.txt'
        $env:SUYU_CMD_PERF_SAMPLE = '1'
        # Opt in explicitly: inherited probe state must not change a comparison.
        # These overlapping CPU scope totals do not measure hardware GPU time.
        $env:SUYU_STALL_PROBE = if ($StallProbe) { '1' } else { '0' }
        if ($SamplePc) {
            $env:SUYU_RECOMP_SAMPLE_PC = '1'
            $env:SUYU_RECOMP_SAMPLE_AFTER_SEC = [string]$SampleAfterSeconds
            $env:SUYU_RECOMP_SAMPLE_SHIFT = '18'
        }
        if ($Capture) {
            $env:SUYU_CMD_CAPTURE_DIR = Join-Path $runRoot 'captures'
            $env:SUYU_CMD_CAPTURE_FIRST_SEC = '10'
            $env:SUYU_CMD_CAPTURE_INTERVAL_SEC = '30'
        }
        $windowStyle = if ($Visible) { 'Normal' } else { 'Hidden' }
        $process = Start-Process -FilePath (Join-Path $runRoot 'suyu-cmd.exe') `
            -ArgumentList "-g `"$Rom`" -c `"$configPath`"" -WorkingDirectory $runRoot `
            -WindowStyle $windowStyle -PassThru
        $launch.pid = $process.Id
        $launch.process_started_utc = $process.StartTime.ToUniversalTime().ToString('o')
        $launch.state = 'started'
        Save-Launch
        if ($RecordCoverage) {
            # Establish the recorder from this same launch context, before the
            # user can finish a short test. A unique file cannot match an old run.
            $launch.coverage_observation_path = Join-Path $runRoot ('observations/launch-' + [Guid]::NewGuid().ToString('N') + '/observation.json')
            $stdout = Join-Path $runRoot 'coverage-recorder.stdout.log'
            $stderr = Join-Path $runRoot 'coverage-recorder.stderr.log'
            Save-Launch
            try {
                $shell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
                $helper = Join-Path $PSScriptRoot 'measure-zarvot-coverage.ps1'
                # Start-Process joins ArgumentList as native command text. All
                # paths are quoted, and none ends with a backslash before its quote.
                $arguments = '-NoLogo -NoProfile -NonInteractive -File "{0}" -RunRoot "{1}" -ObservationPath "{2}" -UntilExit' -f $helper,$runRoot,$launch.coverage_observation_path
                $recorder = Start-Process -FilePath $shell -ArgumentList $arguments -WorkingDirectory $runRoot `
                    -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
                $launch.coverage_recorder_pid = $recorder.Id
                $launch.coverage_recorder_started_utc = $recorder.StartTime.ToUniversalTime().ToString('o')
                $launch.coverage_recorder_state = 'starting'
                # The child reads launch.json once at startup. Do not rewrite it
                # concurrently; persist its PID after attachment or failure.
                $ready = [Diagnostics.Stopwatch]::StartNew()
                while ($ready.Elapsed.TotalSeconds -lt 8) {
                    $recorder.Refresh()
                    if ($recorder.HasExited) { throw "Coverage recorder exited during startup (exit $($recorder.ExitCode)); see $stderr" }
                    if (Test-Path -LiteralPath $launch.coverage_observation_path) {
                        # A concurrent initial write may be incomplete; only a
                        # parsed report establishes attachment, within the bound.
                        $observation = $null
                        try { $observation = Get-Content -LiteralPath $launch.coverage_observation_path -Raw | ConvertFrom-Json }
                        catch { }
                        if ($observation) {
                            if ($observation.pid -ne $launch.pid -or
                                ([DateTime]$observation.process_started_utc).ToUniversalTime().ToString('o') -ne $launch.process_started_utc -or
                                $observation.recorder_pid -ne $recorder.Id -or $observation.run_root -ne $runRoot -or
                                -not $observation.until_exit -or $observation.end_reason -ne 'recording' -or $observation.error) {
                                throw 'Coverage recorder reported a different process identity or failed attachment'
                            }
                            $recorder.Refresh()
                            if ($recorder.HasExited) { throw "Coverage recorder exited during startup (exit $($recorder.ExitCode)); see $stderr" }
                            $launch.coverage_recorder_state = 'attached'
                            break
                        }
                    }
                    Start-Sleep -Milliseconds 100
                }
                if ($launch.coverage_recorder_state -ne 'attached') {
                    throw "Coverage recorder did not confirm attachment within 8 seconds; see $stderr"
                }
            } catch {
                # Preserve the running game and the one recorder attempt. The
                # launch result explicitly distinguishes a failed recorder start.
                $launch.coverage_recorder_state = 'startup_failed'
                $launch.coverage_recorder_error = $_.Exception.Message
            }
            Save-Launch
        }
    } finally {
        Get-ChildItem Env: | Where-Object { $_.Name -like 'SUYU_RECOMP_*' -or $_.Name -like 'SUYU_CMD_*' -or $_.Name -eq 'SUYU_STALL_PROBE' } |
            ForEach-Object { Remove-Item -LiteralPath "Env:\$($_.Name)" }
        foreach ($name in $previous.Keys) { Set-Item -LiteralPath "Env:\$name" -Value $previous[$name] }
    }
}
[pscustomobject]@{
    RunRoot = $runRoot; Pid = $launch.pid; StrictRequested = [bool]$Strict; State = $launch.state
    StallProbeRequested = [bool]$StallProbe
    CoverageRecorderState = $launch.coverage_recorder_state; CoverageRecorderPid = $launch.coverage_recorder_pid
    CoverageObservation = $launch.coverage_observation_path; CoverageRecorderError = $launch.coverage_recorder_error
}
