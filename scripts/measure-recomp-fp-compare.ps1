# Validate an isolated scalar compare width-copy prototype. No product changes,
# game export/build, gameplay, settings or profile changes are performed.
#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$WorkDir,
    [string]$BaselineRef='60fb490b2e329f9ccb13e3548d85b3f1dc0ac37b',
    [switch]$Benchmark,
    [switch]$AnalyzeOnly,
    [string]$TimingEvidence
)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$prototypeRoot=[IO.Path]::GetFullPath((Join-Path $project 'build/zarvot-perf-prototypes'))
if(-not $WorkDir){
    if($AnalyzeOnly){throw '-AnalyzeOnly requires -WorkDir'}
    $WorkDir=Join-Path $prototypeRoot ('fp-compare-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
}
$WorkDir=[IO.Path]::GetFullPath($WorkDir,$PWD.ProviderPath)
if(-not $WorkDir.StartsWith($prototypeRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'WorkDir must be a child of build/zarvot-perf-prototypes'
}
if($Benchmark -and $TimingEvidence){throw 'Select fresh timing or reference existing timing evidence'}
if($AnalyzeOnly -and ($Benchmark -or $TimingEvidence)){throw '-AnalyzeOnly only audits the saved result'}
$python=Join-Path $project 'local/tools/python/Scripts/python.exe'
if(-not (Test-Path -LiteralPath $python)){$python=(Get-Command python -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source}
if($AnalyzeOnly){
    & $python (Join-Path $WorkDir 'analyze.py') --audit
    if($LASTEXITCODE -ne 0){throw 'Saved evidence audit failed'}
    return
}
if(Test-Path -LiteralPath $WorkDir){throw 'Retain completed/failed evidence; use a new WorkDir'}
if($TimingEvidence){
    $TimingEvidence=[IO.Path]::GetFullPath($TimingEvidence,$PWD.ProviderPath)
    if(-not $TimingEvidence.StartsWith($prototypeRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
        throw 'TimingEvidence must be under build/zarvot-perf-prototypes'
    }
}
function Busy {
    @(Get-CimInstance Win32_Process|Where-Object {$_.Name -in @('suyu.exe','suyu-cmd.exe','cl.exe','link.exe','ninja.exe','cmake.exe','wpr.exe','bench.exe','memory_gate.exe','fpx_driver.exe','fpx_outline_alias.exe','gen_baseline.exe','gen_candidate.exe')}|
      Select-Object ProcessId,Name,CreationDate,ExecutablePath)
}
if(@(Busy).Count){throw 'A game, build or benchmark is active; finish it before this experiment'}
New-Item -ItemType Directory -Path (Join-Path $WorkDir 'snapshot/core/recompiler'),(Join-Path $WorkDir 'candidate_snapshot/core/recompiler'),(Join-Path $WorkDir 'gen') -Force|Out-Null
$fixture=Join-Path $project 'tests/recomp_fp_compare'
foreach($file in @('generate.cpp','runner.cpp','prepare.py','isolation.py','analyze.py')){Copy-Item -LiteralPath (Join-Path $fixture $file) -Destination (Join-Path $WorkDir $file)}
$suyu=Join-Path $project 'third_party/suyu'
$git=(Get-Command git -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$baselineCommit=& $git -c "safe.directory=$suyu" -C $suyu rev-parse --verify ($BaselineRef+'^{commit}')
if($LASTEXITCODE -ne 0 -or $baselineCommit -notmatch '^[0-9a-f]{40}$'){throw 'Cannot resolve pinned baseline'}
$lines=& $git -c "safe.directory=$suyu" -C $suyu show ($baselineCommit+':src/core/recompiler/arm64_to_c.h')
if($LASTEXITCODE -ne 0){throw 'Cannot extract baseline emitter'}
# Explicit CRLF snapshots reproduce the initial Windows experiment byte-for-byte.
[IO.File]::WriteAllText((Join-Path $WorkDir 'snapshot/core/recompiler/arm64_to_c.h'),([string]::Join("`r`n",[string[]]$lines)+"`r`n"),[Text.UTF8Encoding]::new($false))
$productHeader=Join-Path $suyu 'src/core/recompiler/arm64_to_c.h'
$productHash=(Get-FileHash -LiteralPath $productHeader -Algorithm SHA256).Hash
$metadata=[ordered]@{state='building';started_utc=[DateTime]::UtcNow.ToString('o');baseline_commit=$baselineCommit;candidate='isolated FPX scalar S compare input width-copy prototype';snapshot_newlines='CRLF';product_header_before_sha256=$productHash;product_source_unchanged=$false;compiler=$null;flags=@('/O2','/Ob2','/bigobj','/fp:precise','/MD');benchmark_requested=[bool]$Benchmark;timing_evidence=$TimingEvidence;error=$null}
function Save {$metadata|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $WorkDir 'metadata.json') -Encoding utf8}
function Native([string]$Name,[string]$Exe,[string[]]$Arguments,[int]$Expected=0){
    & $Exe @Arguments 2>&1|Tee-Object -FilePath (Join-Path $WorkDir ($Name+'.log'))|Out-Host
    if($LASTEXITCODE -ne $Expected){throw "$Name exited $LASTEXITCODE; expected $Expected"}
}
$oldPreference=$PSNativeCommandUseErrorActionPreference
$PSNativeCommandUseErrorActionPreference=$false
Save
Push-Location $WorkDir
try {
    Native 'prepare' $python @('prepare.py')
    $vcvars=& (Join-Path $PSScriptRoot 'find-vcvars.ps1')
    $envLines=& $env:ComSpec /d /c "call `"$vcvars`" >nul 2>&1 && set"
    if($LASTEXITCODE -ne 0){throw 'Compiler environment setup failed'}
    foreach($line in $envLines){$at=$line.IndexOf('=');if($at -gt 0){Set-Item -LiteralPath ('Env:'+$line.Substring(0,$at)) -Value $line.Substring($at+1)}}
    $cl=(Get-Command cl -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $metadata.compiler=$cl;Save
    foreach($tag in @('baseline','candidate')){
        $include=if($tag -eq 'baseline'){'snapshot'}else{'candidate_snapshot'}
        $arguments=@('/nologo','/std:c++20','/EHsc','/O2','/MD',('/I'+$include),'generate.cpp',('/Fegen_'+$tag+'.exe'),('/Fogen_'+$tag+'.obj'))
        if($tag -eq 'candidate'){$arguments+='/DBENCH_CANDIDATE'}
        Native ('compile-gen-'+$tag) $cl $arguments
        Native ('generate-'+$tag) (Join-Path $WorkDir ('gen_'+$tag+'.exe')) @('gen')
    }
    Native 'emission-isolation' $python @('isolation.py')
    foreach($tag in @('baseline','candidate')){
        Native ('compile-'+$tag) $cl @('/nologo','/TC','/O2','/Ob2','/bigobj','/fp:precise','/MD','/c',('gen/'+$tag+'.c'),('/Fo'+$tag+'.obj'),'/FA',('/Fa'+$tag+'.asm'))
    }
    Native 'compile-runner' $cl @('/nologo','/std:c++20','/EHsc','/O2','/Ob2','/bigobj','/fp:precise','/MD','runner.cpp','baseline.obj','candidate.obj','/Febench.exe','/Forunner.obj','/link','/MAP:bench.map','/INCREMENTAL:NO','/OPT:REF','/OPT:ICF')
    $metadata.state='validating';Save
    Native 'validation' (Join-Path $WorkDir 'bench.exe') @('--correct')
    Native 'negative' (Join-Path $WorkDir 'bench.exe') @('--negative') 1
    if($Benchmark){
        $metadata.state='timing';Save
        foreach($entry in @(@('timing1','--bench'),@('timing2','--bench-reverse'),@('timing3','--bench'))){
            $busy=@(Busy);if($busy.Count){throw 'Another game/build/benchmark became active before timing'}
            [ordered]@{utc=[DateTime]::UtcNow.ToString('o');busy=$busy}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath ($entry[0]+'-quiet-before.json')
            Native $entry[0] (Join-Path $WorkDir 'bench.exe') @($entry[1])
            $after=@(Busy)
            [ordered]@{utc=[DateTime]::UtcNow.ToString('o');busy=$after}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath ($entry[0]+'-quiet-after.json')
            if($after.Count){throw 'Another game/build/benchmark became active during timing'}
        }
    }
    if((Get-FileHash -LiteralPath $productHeader -Algorithm SHA256).Hash -ne $productHash){throw 'Product emitter changed during experiment'}
    $metadata.product_source_unchanged=$true;$metadata.state='complete';$metadata['finished_utc']=[DateTime]::UtcNow.ToString('o');Save
    $analysisArgs=@('analyze.py')
    if($TimingEvidence){$analysisArgs+=@('--timing-evidence',$TimingEvidence)}
    Native 'analysis' $python $analysisArgs
} catch {$metadata.state='error';$metadata.error=$_.Exception.Message;$metadata['finished_utc']=[DateTime]::UtcNow.ToString('o');Save;throw}
finally {Pop-Location;$PSNativeCommandUseErrorActionPreference=$oldPreference}
[pscustomobject]@{WorkDir=$WorkDir;State=$metadata.state;Summary=(Join-Path $WorkDir 'summary.json')}
