# Build one generated recompiled module into a Windows DLL.
#
# Drives generated CMake directly, so module compilation and its evidence stay
# separate from export/packaging. Historical exporter limitations must be
# checked against current source rather than assumed to apply.
#
# Target `recompiled_<module>` is the SHARED build, which exports
# recomp_image_lookup / recomp_image_set_base - the two symbols suyu resolves
# when loading an AOT image (suyu.cpp:552-553, main.cpp:6285/6305). That is the
# shape we want: it loads into a normal suyu build with no relinking.

[CmdletBinding()]
param(
    [string]$Root    = $env:MK8R_ROOT,
    [string]$Target  = $env:MK8R_TARGET,
    [string]$Package = $env:MK8R_PACKAGE,
    [Parameter(Mandatory)]
    [string]$Module,
    [string]$BuildType = 'Release',
    [ValidateRange(1, 64)][int]$ParallelJobs = 2,
    [switch]$ForceRebuild
)

# $PSScriptRoot is not populated while parameter defaults are bound under
# -File, so the fallback lives here rather than in the param block.
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root)

$ErrorActionPreference = 'Stop'

$Src    = Join-Path $Root "generated\$Target\$Package\aot_cache\exefs\$Module"
# Namespaced by target. build\recomp\<module> alone let one game's build tree be
# reused for another game's sources, and a stale DLL from a previous target is
# worse than no DLL at all: it loads, and it executes.
$Build  = Join-Path $Root "build\recomp\$Target\$Module"
$allowedBuildRoot = [IO.Path]::GetFullPath((Join-Path $Root 'build\recomp')) + [IO.Path]::DirectorySeparatorChar
$allowedSourceRoot = [IO.Path]::GetFullPath((Join-Path $Root 'generated')) + [IO.Path]::DirectorySeparatorChar
$Build = [IO.Path]::GetFullPath($Build)
$Src = [IO.Path]::GetFullPath($Src)
if (-not $Build.StartsWith($allowedBuildRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not $Src.StartsWith($allowedSourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Module source/build resolved outside the workspace generated/build roots'
}
$VcVars = & (Join-Path $PSScriptRoot 'find-vcvars.ps1')

if (-not (Test-Path -LiteralPath $Src))    { throw "No generated project at $Src" }
if (-not (Test-Path -LiteralPath $VcVars)) { throw "vcvars64.bat not found at $VcVars" }

# Reuse the build for convergence rounds when the generated source path is the
# same. If an export's package directory changed, discard only this module's
# cache; CMake caches absolute source paths and cannot retarget it safely.
$cache = Join-Path $Build 'CMakeCache.txt'
if (Test-Path -LiteralPath $cache) {
    $cachedHomeLine = Get-Content -LiteralPath $cache |
                      Where-Object { $_ -like 'CMAKE_HOME_DIRECTORY:INTERNAL=*' } |
                      Select-Object -First 1
    if ($cachedHomeLine) {
        $cachedSource = [IO.Path]::GetFullPath(($cachedHomeLine -split '=', 2)[1])
        if (-not $cachedSource.Equals([IO.Path]::GetFullPath($Src), [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $Build -Recurse -Force
        }
    }
}

New-Item -ItemType Directory -Force -Path $Build | Out-Null

function Invoke-InVsEnv([string]$Command) {
    & cmd.exe /c "call `"$VcVars`" >nul 2>&1 && $Command"
    if ($LASTEXITCODE -ne 0) { throw "Failed (exit $LASTEXITCODE): $Command" }
}

$srcSize = (Get-ChildItem -LiteralPath (Join-Path $Src 'src') -File |
            Measure-Object -Property Length -Sum).Sum
Write-Host ("module {0}: {1:n1} MB of generated C" -f $Module, ($srcSize / 1MB)) -ForegroundColor Cyan

# Invalid constant shifts in generated C are correctness bugs, even when MSVC
# would otherwise compile them as warnings. Fail the module build immediately.
Invoke-InVsEnv "cmake -S `"$Src`" -B `"$Build`" -G Ninja -DCMAKE_BUILD_TYPE=$BuildType -DCMAKE_C_FLAGS=/we4293"

# The main NSO's shared target is called recompiled_image, not recompiled_main -
# that is the name suyu's loader looks for when scanning for AOT DLLs
# (suyu.cpp:524-561 lists recompiled_rtld.dll, recompiled_image.dll,
# recompiled_subsdk0..9.dll, recompiled_sdk.dll).
$CMakeTarget = if ($Module -eq 'main') { 'recompiled_image' } else { "recompiled_$Module" }

$sw = [Diagnostics.Stopwatch]::StartNew()
$clean = if ($ForceRebuild) { ' --clean-first' } else { '' }
Invoke-InVsEnv "cmake --build `"$Build`" --target $CMakeTarget$clean --parallel $ParallelJobs"
$sw.Stop()

Write-Host ("built in {0:n1} min" -f $sw.Elapsed.TotalMinutes) -ForegroundColor Green
Get-ChildItem -LiteralPath $Build -Recurse -Include *.dll |
    Select-Object Name, Length, FullName | Format-Table -AutoSize
