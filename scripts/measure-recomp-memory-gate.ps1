# Build/test generic FM1 gate alternatives. No game, exporter or profile launch.
#Requires -Version 7.0
[CmdletBinding()]
param([string]$WorkDir, [int]$Operations = 20000000, [switch]$Benchmark)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$prototypeRoot = Join-Path $project 'build/zarvot-perf-prototypes'
if (-not $WorkDir) {
    $WorkDir = Join-Path $prototypeRoot ('memory-gate-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
}
$WorkDir = [IO.Path]::GetFullPath($WorkDir)
if (-not $WorkDir.StartsWith([IO.Path]::GetFullPath($prototypeRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'WorkDir must be a new child of build/zarvot-perf-prototypes.'
}
if (Test-Path -LiteralPath $WorkDir) { throw 'Retain earlier results; use a new WorkDir.' }
if ($Operations -le 0) { throw 'Operations must be positive.' }
function Busy {
    @(Get-Process -Name cl,link,ninja,cmake,suyu,suyu-cmd,memory_gate,fmdiff_baseline,fmdiff_aligned,fmdiff_reversed,fmdiff_combined,fmdiff_masked -ErrorAction SilentlyContinue |
      Select-Object Id,ProcessName,CPU,StartTime)
}
if (@(Busy).Count) { throw 'A game, build or benchmark is running. Finish it before timing.' }
$include = Join-Path $WorkDir 'snapshot'
$fixture = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory -Path (Join-Path $include 'core/recompiler'),$fixture -Force | Out-Null
$header = Join-Path $project 'third_party/suyu/src/core/recompiler/arm64_to_c.h'
$headerHash = (Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash
Copy-Item -LiteralPath $header -Destination (Join-Path $include 'core/recompiler/arm64_to_c.h')
Copy-Item -LiteralPath (Join-Path $project 'tests/recomp_memory_gate/CMakeLists.txt'),(Join-Path $project 'tests/recomp_memory_gate/generate.cpp'),(Join-Path $project 'tests/recomp_memory_gate/runner.cpp') -Destination $fixture
Copy-Item -LiteralPath (Join-Path $project 'third_party/suyu/tests/recompiler_fastmem/fmdiff.c') -Destination $fixture
$vcvars = & (Join-Path $PSScriptRoot 'find-vcvars.ps1')
$vsLines = & $env:ComSpec /d /c "call `"$vcvars`" >nul 2>&1 && set"
if ($LASTEXITCODE -ne 0) { throw 'Visual C++ environment setup failed.' }
foreach ($line in $vsLines) {
    $at = $line.IndexOf('=')
    if ($at -gt 0) { Set-Item -LiteralPath ('Env:'+$line.Substring(0,$at)) -Value $line.Substring($at+1) }
}
$cl = (Get-Command cl -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$cmake = (Get-Command cmake -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$ninja = (Get-Command ninja -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$metadata = [ordered]@{state='building';started_utc=[DateTime]::UtcNow.ToString('o');work_dir=$WorkDir;emitter_sha256=$headerHash;compiler=$cl;cmake=$cmake;ninja=$ninja;operations_per_fmdiff_leg=$Operations;flags='/O2 /Ob2 /bigobj /fp:precise /MD; no LTO';input='synthetic only';error=$null}
function Save-Metadata { $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $WorkDir 'metadata.json') -Encoding utf8 }
function Native([string]$Name,[string]$Exe,[string[]]$Arguments,[int]$Expected = 0) {
    & $Exe @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $WorkDir ($Name + '.log')) | Out-Host
    if ($LASTEXITCODE -ne $Expected) { throw "$Name exited $LASTEXITCODE; expected $Expected" }
}
Save-Metadata
try {
    $build = Join-Path $WorkDir 'build'
    Native 'configure' $cmake @('-S',$fixture,'-B',$build,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_TRY_COMPILE_CONFIGURATION=Release',('-DCMAKE_MAKE_PROGRAM='+$ninja.Replace('\','/')),('-DCMAKE_C_COMPILER='+$cl.Replace('\','/')),('-DCMAKE_CXX_COMPILER='+$cl.Replace('\','/')),('-DEMITTER_INCLUDE='+$include.Replace('\','/')),('-DFMDIFF_SOURCE='+(Join-Path $fixture 'fmdiff.c').Replace('\','/')))
    Native 'build' $cmake @('--build',$build,'--parallel','2')
    $metadata.state='testing'; Save-Metadata
    $test = Join-Path $build 'memory_gate.exe'
    Native 'correct' $test @('--correct-only')
    Native 'control-value' $test @('--inject-value') 1
    Native 'control-callback' $test @('--inject-callback') 1
    Native 'control-arguments' $test @('--unknown-option') 2
    foreach ($tag in @('baseline','aligned','reversed','combined','masked')) {
        Native "differential-$tag" (Join-Path $build "fmdiff_$tag.exe") @([string]$Operations,'1')
        Native "differential-$tag-seed2" (Join-Path $build "fmdiff_$tag.exe") @('1048576','3735928559')
    }
    if ($Benchmark) {
        $metadata.state='timing'; Save-Metadata
        ConvertTo-Json -InputObject @(Busy) -Depth 3 | Set-Content -LiteralPath (Join-Path $WorkDir 'quiet-before.json') -Encoding utf8
        Native 'timing' $test @('--bench-only')
        ConvertTo-Json -InputObject @(Busy) -Depth 3 | Set-Content -LiteralPath (Join-Path $WorkDir 'quiet-after.json') -Encoding utf8
    }
    if ((Get-FileHash -LiteralPath $header -Algorithm SHA256).Hash -ne $headerHash) { throw 'Emitter changed during experiment.' }
    $metadata.state='complete'
}
catch { $metadata.state='error'; $metadata.error=$_.Exception.Message; throw }
finally { $metadata['finished_utc']=[DateTime]::UtcNow.ToString('o'); Save-Metadata }
[pscustomobject]@{WorkDir=$WorkDir;State=$metadata.state}
