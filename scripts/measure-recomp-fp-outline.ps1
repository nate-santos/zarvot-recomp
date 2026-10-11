# Build and compare generic FP32 blocks from two emitter revisions. No game is run.
# The immutable baseline defaults to the pre-outline pinned source. All artifacts
# stay under build/zarvot-perf-prototypes; timings are observations, not test gates.
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Root,
    [string]$WorkDir,
    [string]$BaselineRef = '5949cab3ba93233ddd1c319bfc6f010f6cfa910a',
    [switch]$AnalyzeOnly
)
# Parameter binding can precede $PSScriptRoot initialization under -File.
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)
$prototypeRoot = [IO.Path]::GetFullPath((Join-Path $Root 'build/zarvot-perf-prototypes'))
if (-not $WorkDir) {
    if ($AnalyzeOnly) { throw '-AnalyzeOnly requires an existing -WorkDir.' }
    $WorkDir = Join-Path $prototypeRoot ('fp-outline-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
}
$WorkDir = [IO.Path]::GetFullPath($WorkDir)
if (-not $WorkDir.StartsWith($prototypeRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'WorkDir must be a child of build/zarvot-perf-prototypes.'
}
function Get-BusyProcesses {
    @(Get-Process -Name cl,link,ninja,cmake,fpx_driver,fpx_outline_alias,fpx_gen,smoke_export,smoke_run,bench,suyu,suyu-cmd -ErrorAction SilentlyContinue |
        Select-Object Id,ProcessName,CPU,StartTime)
}
function Invoke-LoggedNative {
    param([string]$Name,[string]$Exe,[string[]]$Arguments,[int]$ExpectedExit = 0)
    & $Exe @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $WorkDir ($Name + '.log')) | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne $ExpectedExit) { throw "$Name exited $code; expected $ExpectedExit. See its log." }
}
function Read-InvariantDouble([string]$Value) {
    [double]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture)
}
function Get-EvidenceHashes {
    $hashes = [ordered]@{}
    foreach ($file in @('bench.exe','generate.cpp','runner.cpp','gen/baseline.c','gen/candidate.c','gen/helpers.c','gen/rt_baseline.h','gen/rt_candidate.h','snapshot/core/recompiler/arm64_to_c.h','candidate_snapshot/core/recompiler/arm64_to_c.h','baseline.asm','candidate.asm','helpers.asm','validation.log','control.log','timing.log','quiet-before.json','quiet-after.json')) {
        $hashes[$file] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $WorkDir $file)).Hash
    }
    $hashes
}
function Get-Allocation([string]$AsmPath,[string]$Function) {
    $text = Get-Content -LiteralPath $AsmPath -Raw
    $body = [regex]::Match($text, '(?ms)^' + [regex]::Escape($Function) + ' PROC\b.*?^' + [regex]::Escape($Function) + ' ENDP\b').Value
    if (-not $body) { throw "Missing assembly body: $Function" }
    $probe = $body -match 'call\s+__chkstk'
    $allocation = if ($probe) { [regex]::Match($body,'mov\s+eax,\s*(\d+)[^\r\n]*\r?\n\s*call\s+__chkstk').Groups[1].Value }
                  else { [regex]::Match($body,'sub\s+rsp,\s*(\d+)').Groups[1].Value }
    [ordered]@{ function=$Function; explicit_stack_allocation_bytes=if($allocation){[long]$allocation}else{$null}; chkstk=$probe }
}

$metadataPath = Join-Path $WorkDir 'build-metadata.json'
$oldNativePreference = $PSNativeCommandUseErrorActionPreference
$PSNativeCommandUseErrorActionPreference = $false
try {
    if (-not $AnalyzeOnly) {
        if (Test-Path -LiteralPath $WorkDir) { throw 'Use a new empty WorkDir; completed baselines are never overwritten.' }
        if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell for the x64 compiler/runtime.' }
        $busy = @(Get-BusyProcesses)
        if ($busy.Count) { throw 'Another compiler or synthetic test is running. Finish that work before benchmarking.' }
        $baselineDir = Join-Path $WorkDir 'snapshot/core/recompiler'
        $candidateDir = Join-Path $WorkDir 'candidate_snapshot/core/recompiler'
        New-Item -ItemType Directory -Force -Path $baselineDir,$candidateDir | Out-Null
        $suyu = Join-Path $Root 'third_party/suyu'
        $git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $baselineCommit = & $git -c "safe.directory=$suyu" -C $suyu rev-parse --verify ($BaselineRef + '^{commit}')
        if ($LASTEXITCODE -ne 0 -or $baselineCommit -notmatch '^[0-9a-f]{40}$') { throw 'Could not resolve the baseline commit.' }
        $baselineLines = & $git -c "safe.directory=$suyu" -C $suyu show ($baselineCommit + ':src/core/recompiler/arm64_to_c.h')
        if ($LASTEXITCODE -ne 0) { throw 'Could not read the baseline emitter.' }
        $baselineHeader = Join-Path $baselineDir 'arm64_to_c.h'
        # Normalize Git's textual stdout to LF; record the exact compiled hash.
        [IO.File]::WriteAllText($baselineHeader,([string]::Join("`n",[string[]]$baselineLines)+"`n"),[Text.UTF8Encoding]::new($false))
        $candidateSource = Join-Path $suyu 'src/core/recompiler/arm64_to_c.h'
        $before = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateSource).Hash
        $candidateHeader = Join-Path $candidateDir 'arm64_to_c.h'
        Copy-Item -LiteralPath $candidateSource -Destination $candidateHeader
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $candidateSource).Hash -ne $before -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateHeader).Hash -ne $before) { throw 'Candidate changed while being copied.' }
        Copy-Item -LiteralPath (Join-Path $Root 'tests/recomp_fp_outline_benchmark.cpp') -Destination (Join-Path $WorkDir 'generate.cpp')
        Copy-Item -LiteralPath (Join-Path $Root 'tests/recomp_fp_outline_benchmark_runner.cpp') -Destination (Join-Path $WorkDir 'runner.cpp')
        $vcvars = & (Join-Path $PSScriptRoot 'find-vcvars.ps1')
        $vsLines = & $env:ComSpec /d /c "call `"$vcvars`" >nul 2>&1 && set"
        if ($LASTEXITCODE -ne 0) { throw 'Visual C++ environment setup failed.' }
        foreach ($line in $vsLines) {
            $at = $line.IndexOf('=')
            if ($at -gt 0) { Set-Item -LiteralPath ('Env:'+$line.Substring(0,$at)) -Value $line.Substring($at+1) }
        }
        $cl = (Get-Command cl -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $metadata = [ordered]@{
            started_utc=[DateTime]::UtcNow.ToString('o'); baseline_commit=$baselineCommit
            baseline_header_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $baselineHeader).Hash
            candidate_header_sha256=$before; compiler=$cl
            c_flags=@('/TC','/O2','/Ob2','/bigobj','/fp:precise','/MD'); input='generic synthetic instructions only'
            source_files=@('generate.cpp','runner.cpp'); state='building'
        }
        $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding utf8
        Push-Location $WorkDir
        try {
            foreach ($tag in @('baseline','candidate')) {
                $includes = if ($tag -eq 'baseline') { Join-Path $WorkDir 'snapshot' } else { Join-Path $WorkDir 'candidate_snapshot' }
                $arguments = @('/nologo','/EHsc','/std:c++20','/O2','/MD',('/I'+$includes),'generate.cpp',('/Fe'+$WorkDir+"/gen_$tag.exe"),('/Fo'+$WorkDir+"/gen_$tag.obj"))
                if ($tag -eq 'candidate') { $arguments += '/DBENCH_CANDIDATE' }
                Invoke-LoggedNative -Name "compile-generator-$tag" -Exe $cl -Arguments $arguments
                Invoke-LoggedNative -Name "generate-$tag" -Exe (Join-Path $WorkDir "gen_$tag.exe") -Arguments @('gen')
            }
            foreach ($unit in @('baseline','candidate','helpers')) {
                Invoke-LoggedNative -Name "compile-$unit" -Exe $cl -Arguments (@('/nologo')+$metadata.c_flags+@('/c',"gen/$unit.c",('/Fo'+$WorkDir+"/$unit.obj"),'/FA',('/Fa'+$WorkDir+"/$unit.asm")))
            }
            Invoke-LoggedNative -Name 'compile-runner' -Exe $cl -Arguments @('/nologo','/EHsc','/std:c++20','/O2','/Ob2','/bigobj','/fp:precise','/MD','runner.cpp','baseline.obj','candidate.obj','helpers.obj',('/Fe'+$WorkDir+'/bench.exe'),('/Fo'+$WorkDir+'/runner.obj'),'/link',('/MAP:'+$WorkDir+'/bench.map'),'/INCREMENTAL:NO','/OPT:REF','/OPT:ICF')
            $benchmark = Join-Path $WorkDir 'bench.exe'
            Invoke-LoggedNative -Name 'validation' -Exe $benchmark -Arguments @('--correct-only')
            Invoke-LoggedNative -Name 'control' -Exe $benchmark -Arguments @('--inject-mismatch') -ExpectedExit 1
            $busy = @(Get-BusyProcesses)
            if ($busy.Count) { throw 'Another compiler/test became active; validation is saved, but timing was not started.' }
            [ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');busy_processes=$busy} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath 'quiet-before.json' -Encoding utf8
            Invoke-LoggedNative -Name 'timing' -Exe $benchmark -Arguments @('--bench-only')
            [ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');busy_processes=@(Get-BusyProcesses)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath 'quiet-after.json' -Encoding utf8
            $metadata.state='complete'; $metadata.finished_utc=[DateTime]::UtcNow.ToString('o')
            $metadata.benchmark_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $benchmark).Hash
            $metadata.evidence_sha256=Get-EvidenceHashes
            $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding utf8
        } finally { Pop-Location }
    }
    if (-not (Test-Path -LiteralPath $metadataPath)) { throw 'Missing build metadata.' }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.state -ne 'complete' -or -not $metadata.evidence_sha256) { throw 'Only a complete, hashed benchmark may be analyzed.' }
    foreach ($property in $metadata.evidence_sha256.PSObject.Properties) {
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $WorkDir $property.Name)).Hash -ne $property.Value) { throw "Changed evidence: $($property.Name)" }
    }
    $validation = Get-Content -LiteralPath (Join-Path $WorkDir 'validation.log')
    $timing = Get-Content -LiteralPath (Join-Path $WorkDir 'timing.log')
    $control = Get-Content -LiteralPath (Join-Path $WorkDir 'control.log')
    $checks = @($validation | Where-Object {$_ -match '^CORRECT ops=(16|122) full_state_checks=32768 fpcr_modes=32 fpsr_states=4 samples_per_mode=256$'} | ForEach-Object {[int]([regex]::Match($_,'ops=(\d+)').Groups[1].Value)})
    if ($checks.Count -ne 2 -or 16 -notin $checks -or 122 -notin $checks -or -not ($control -match '^MISMATCH ')) { throw 'Missing complete semantic checks or detector evidence.' }
    $medians = @(); $ranges = @(); $points = @{}
    foreach ($line in $timing) {
        if ($line -match '^MEDIAN ops=(\d+) dataset=(\d+) baseline_ns=([0-9.]+) candidate_ns=([0-9.]+) ratio=([0-9.]+)$') {
            $medians += [ordered]@{ops=[int]$Matches[1];dataset=[int]$Matches[2];baseline_ns=Read-InvariantDouble $Matches[3];candidate_ns=Read-InvariantDouble $Matches[4];candidate_over_baseline=Read-InvariantDouble $Matches[5]}
        } elseif ($line -match '^NATIVE_EXTENT function=(\w+) unwind_bytes=(\d+) ') {
            $ranges += [ordered]@{function=$Matches[1];entry_unwind_range_bytes=[long]$Matches[2]}
        } elseif ($line -match '^TIMING ops=(\d+) dataset=(\d+) sequence=(\d+) arm=([AB]) calls=(\d+) seconds=([0-9.]+) checksum=([0-9a-f]+)$') {
            $key = $Matches[1] + ':' + $Matches[2]
            if (-not $points.ContainsKey($key)) { $points[$key] = @() }
            $points[$key] += [pscustomobject]@{sequence=[int]$Matches[3];arm=$Matches[4];calls=[long]$Matches[5];checksum=$Matches[7]}
        }
    }
    if ($medians.Count -ne 6 -or $points.Count -ne 6) { throw 'Incomplete ABBA timing output.' }
    foreach ($count in @(16,122)) { foreach ($dataset in @(0,1,2)) {
        $key = "$count`:$dataset"; $rows = @($points[$key])
        if ($rows.Count -ne 8 -or @($medians | Where-Object {$_.ops -eq $count -and $_.dataset -eq $dataset}).Count -ne 1) { throw "Incomplete group: $key" }
        for ($i=0;$i -lt 8;$i++) {
            if ($rows[$i].sequence -ne $i -or $rows[$i].arm -ne [string]'ABBAABBA'[$i] -or $rows[$i].calls -le 0 -or $rows[$i].calls -ne $rows[0].calls -or $rows[$i].checksum -ne $rows[0].checksum) { throw "Inconsistent equivalent work/checksum: $key" }
        }
    } }
    $quietBefore = Get-Content -LiteralPath (Join-Path $WorkDir 'quiet-before.json') -Raw | ConvertFrom-Json
    $quietAfter = Get-Content -LiteralPath (Join-Path $WorkDir 'quiet-after.json') -Raw | ConvertFrom-Json
    $allocations = @()
    foreach ($tag in @('baseline','candidate')) { foreach ($count in @(16,122)) { $allocations += Get-Allocation (Join-Path $WorkDir "$tag.asm") ($tag+'_'+$count) } }
    $summary = [ordered]@{
        state='complete'; work_dir=$WorkDir; build=$metadata; full_state_comparisons=65536; detector_expected_exit=1
        sequence='ABBAABBA'; datasets=@('finite moderate FPX open','IXC initially clear','FPX inhibited')
        named_busy_processes_before=@($quietBefore.busy_processes).Count; named_busy_processes_after=@($quietAfter.busy_processes).Count
        medians=$medians; entry_unwind_ranges=$ranges; stack_allocations=$allocations
        limitations=@('Synthetic equivalent arithmetic, not a game FPS measurement.','Timings include identical output/FPSR reset work; RNG, validation and checksums are outside the timed region.','No probes or shadow instrumentation are timed.','Entry unwind ranges exclude other fragments/callees; stack allocations exclude pushed registers and callees.','Busy-process snapshots cover named project/compiler processes, not all system activity.')
    }
    $summaryPath = Join-Path $WorkDir 'summary.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    [pscustomobject]@{SummaryPath=$summaryPath;FullStateComparisons=65536;Medians=$medians}
} finally { $PSNativeCommandUseErrorActionPreference = $oldNativePreference }
