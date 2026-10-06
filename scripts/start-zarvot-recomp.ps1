# Stage the complete Zarvot DLL set with an isolated portable profile, then boot.
# Sends no controller input. Keep this local directory out of release packages.
[CmdletBinding()]
param(
    [string]$Rom,
    [switch]$Strict,
    [switch]$Capture,
    [switch]$Visible,
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Rom) { $Rom = Join-Path (Split-Path -Parent $root) 'Zarvot.nsp' }
$Rom = (Resolve-Path -LiteralPath $Rom).Path
$buildRoot = Join-Path $root 'build\recomp\zarvot'
$hostRoot = Join-Path $root 'build\suyu\bin'
$build = Get-Content -LiteralPath (Join-Path $buildRoot 'build-status.json') -Raw | ConvertFrom-Json
$manifestPath = Join-Path $root 'generated\zarvot\out\Zarvot - Hybrid AOT + JIT\aot_cache\aot_manifest.json'
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = @('main', 'rtld', 'sdk', 'subsdk0')
if ($build.state -ne 'complete' -or $build.image_abi -ne 6 -or
    $manifestHash -ne $build.export_manifest_sha256 -or
    @($build.modules).Count -ne 4 -or
    @(Compare-Object $expected @($build.modules.name | Sort-Object)).Count -ne 0) {
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
$hostPath = Join-Path $hostRoot 'suyu-cmd.exe'
$hostHash = (Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToLowerInvariant()
$keysRoot = Join-Path $hostRoot 'user\keys'
if (-not (Test-Path -LiteralPath (Join-Path $keysRoot 'prod.keys'))) {
    throw 'The matching local build profile must already contain the supplied keys'
}
# Preserve existing player/test sessions. This launcher never stops one.
if (-not $StageOnly -and @(Get-Process suyu,suyu-cmd -ErrorAction SilentlyContinue).Count) {
    throw 'An emulator session is already running; preserve it before starting a separate test'
}

$runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runRoot = Join-Path $root "build\zarvot-runs\$runId"
foreach ($dir in @('', 'user\keys', 'user\config', 'user\nand', 'user\sdmc', 'user\load', 'user\dump', 'user\tas', 'captures')) {
    [IO.Directory]::CreateDirectory((Join-Path $runRoot $dir)) | Out-Null
}
Copy-Item -LiteralPath $hostPath -Destination $runRoot
# Copy host dependencies only; no export README (which redirects keys/NAND).
Get-ChildItem -LiteralPath $hostRoot -File -Filter '*.dll' | Where-Object Name -notlike 'recompiled_*' |
    Copy-Item -Destination $runRoot
foreach ($image in $images) { Copy-Item -LiteralPath $image.Path -Destination (Join-Path $runRoot $image.Name) }
foreach ($name in @('prod.keys', 'title.keys')) {
    $keyPath = Join-Path $keysRoot $name
    if (Test-Path -LiteralPath $keyPath) { Copy-Item -LiteralPath $keyPath -Destination (Join-Path $runRoot "user\keys\$name") }
}
# Fresh settings retain original timing and the recorded handheld 1x/HIGH setup.
# No old config or saves are copied, so absolute NAND paths cannot escape isolation.
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
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $runRoot 'aot_manifest.json')
$launch = [ordered]@{
    started_utc = [DateTime]::UtcNow.ToString('o')
    run_root = $runRoot
    rom_path = $Rom
    host_sha256 = $hostHash
    export_manifest_sha256 = $manifestHash
    image_abi = $build.image_abi
    image_features = $build.image_features
    modules = $build.modules
    strict_requested = [bool]$Strict
    visible_requested = [bool]$Visible
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
    Get-ChildItem Env: | Where-Object { $_.Name -like 'SUYU_RECOMP_*' -or $_.Name -like 'SUYU_CMD_*' } |
        ForEach-Object { $previous[$_.Name] = $_.Value; Remove-Item -LiteralPath "Env:\$($_.Name)" }
    try {
        $env:SUYU_RECOMP_STRICT = if ($Strict) { '1' } else { '0' }
        $env:SUYU_RECOMP_COVERAGE_PATH = Join-Path $runRoot 'coverage.txt'
        $env:SUYU_CMD_PERF_SAMPLE = '1'
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
    } finally {
        Get-ChildItem Env: | Where-Object { $_.Name -like 'SUYU_RECOMP_*' -or $_.Name -like 'SUYU_CMD_*' } |
            ForEach-Object { Remove-Item -LiteralPath "Env:\$($_.Name)" }
        foreach ($name in $previous.Keys) { Set-Item -LiteralPath "Env:\$name" -Value $previous[$name] }
    }
}
[pscustomobject]@{ RunRoot = $runRoot; Pid = $launch.pid; StrictRequested = [bool]$Strict; State = $launch.state }
