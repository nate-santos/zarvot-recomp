# Build the exported Zarvot module set sequentially, without a build timeout.
# Generated units are memory-bound; let their CMake compile pool limit jobs.
[CmdletBinding()]
param(
    [string]$Package = 'out\Zarvot - Hybrid AOT + JIT',
    [ValidateRange(1, 64)][int]$ParallelJobs = 2
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exportRoot = [IO.Path]::GetFullPath((Join-Path $root "generated\zarvot\$Package\aot_cache"))
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $root 'generated\zarvot')) + [IO.Path]::DirectorySeparatorChar
if (-not $exportRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Package resolved outside generated/zarvot'
}
$manifestPath = Join-Path $exportRoot 'aot_manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$modules = @('rtld', 'sdk', 'subsdk0', 'main')
$exported = @($manifest.modules | ForEach-Object name | Sort-Object)
if (@(Compare-Object ($modules | Sort-Object) $exported).Count -ne 0 -or
    $manifest.total_modules -ne 4 -or $manifest.image_abi -ne 6) {
    throw 'Expected the four-module Zarvot ABI 6 export; review the manifest before building'
}
foreach ($module in $modules) {
    if (-not (Test-Path -LiteralPath (Join-Path $exportRoot "exefs\$module\CMakeLists.txt"))) {
        throw "Missing generated project for $module"
    }
}

$buildRoot = Join-Path $root 'build\recomp\zarvot'
[IO.Directory]::CreateDirectory($buildRoot) | Out-Null
$statusPath = Join-Path $buildRoot 'build-status.json'
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$lock = $null
try {
    # Never let two instances of this runner share build trees or status output.
    $lock = [IO.File]::Open((Join-Path $buildRoot 'build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $status = [ordered]@{
        started_utc = [DateTime]::UtcNow.ToString('o')
        runner_pid = $PID
        state = 'building'
        export_manifest_sha256 = $manifestHash
        image_abi = $manifest.image_abi
        image_features = $manifest.image_features
        parallel_jobs = $ParallelJobs
        modules = @($modules | ForEach-Object {
            [ordered]@{ name = $_; state = 'pending' }
        })
    }
    function Save-BuildStatus {
        $status.updated_utc = [DateTime]::UtcNow.ToString('o')
        [IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    }
    Save-BuildStatus
    foreach ($entry in $status.modules) {
        $entry.state = 'building'
        $entry.started_utc = [DateTime]::UtcNow.ToString('o')
        Save-BuildStatus
        $timer = [Diagnostics.Stopwatch]::StartNew()
        try {
            if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifestHash) {
                throw 'Export manifest changed during the build; review and restart with a consistent export'
            }
            & "$PSScriptRoot/build-recomp.ps1" -Root $root -Target zarvot -Package $Package `
                -Module $entry.name -ParallelJobs $ParallelJobs
            $imageName = if ($entry.name -eq 'main') { 'recompiled_image.dll' } else { "recompiled_$($entry.name).dll" }
            $image = Join-Path $buildRoot "$($entry.name)\$imageName"
            $entry.bytes = (Get-Item -LiteralPath $image).Length
            $entry.sha256 = (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant()
            $entry.state = 'complete'
        } catch {
            $entry.state = 'failed'
            $entry.error = $_.Exception.Message
            $status.state = 'failed'
            throw
        } finally {
            $timer.Stop()
            $entry.elapsed_seconds = $timer.Elapsed.TotalSeconds
            $entry.finished_utc = [DateTime]::UtcNow.ToString('o')
            Save-BuildStatus
        }
    }
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifestHash) {
        $status.state = 'failed'
        Save-BuildStatus
        throw 'Export manifest changed during the build; do not treat this as a consistent module set'
    }
    $status.state = 'complete'
    Save-BuildStatus
    Write-Host "All four modules built. Local build evidence: $statusPath"
} finally {
    if ($lock) { $lock.Dispose() }
}
