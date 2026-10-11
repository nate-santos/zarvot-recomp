# Validate ownership and address boundaries without reading an ETL or starting ETW.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tokens=$null; $errors=$null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/analyze-zarvot-cpu.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
# Load only definitions: the analyzer's file/trace entry point is not executed.
$ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -in @('Assert-ZarvotCpuMetadata','Get-ZarvotCpuIdentity','Initialize-ZarvotCpuTraceEvent')}, $true) |
    ForEach-Object { . ([ScriptBlock]::Create($_.Extent.Text)) }
$runRoot = Join-Path $root 'build/cpu-analysis-fixture/run'
$directory = Join-Path $runRoot 'cpu-profiles/fixture'
$started = [DateTime]::Parse('2026-10-11T03:00:34.4457960Z').ToUniversalTime()
$session = [DateTime]::Parse('2026-10-11T03:04:38.0000000Z').ToUniversalTime()
$metadata = [pscustomobject]@{
    state='complete'; recording_started=$true; finished_utc=$session.AddMinutes(5).ToString('o')
    error=$null; cleanup_error=$null; trace_file='cpu.etl'; trace_bytes=100
    pid=7872; process_started_utc=$started.ToString('o'); run_root=$runRoot
    expected_executable=(Join-Path $runRoot 'suyu-cmd.exe')
}
$null = Assert-ZarvotCpuMetadata -Metadata $metadata -Directory $directory
foreach ($case in @('live','failed','missing','foreign_trace','foreign_exe','foreign_root')) {
    $candidate = $metadata.PSObject.Copy()
    switch ($case) {
        live { $candidate.state='recording' }
        failed { $candidate.cleanup_error='Denied stop' }
        missing { $candidate.recording_started=$false }
        foreign_trace { $candidate.trace_file='../cpu.etl' }
        foreign_exe { $candidate.expected_executable+='foreign' }
        foreign_root { $candidate.run_root+='foreign' }
    }
    $rejected=$false
    try { $null = Assert-ZarvotCpuMetadata -Metadata $candidate -Directory $directory }
    catch { $rejected=$true }
    if (-not $rejected) { throw "Accepted $case profile metadata" }
}
$process = [pscustomobject]@{
    ProcessID=7872; ImageFileName=$metadata.expected_executable
    StartTime=$session.ToLocalTime(); StartTimeRelativeMsec=0
    LoadedModules=@([pscustomobject]@{FilePath=$metadata.expected_executable})
}
$identity = Get-ZarvotCpuIdentity -Candidate $process -Metadata $metadata -SessionStart $session
if ($identity.StartMatch -ne 'pretrace_start_clamped_to_trace_start') { throw 'Pretrace identity limitation lost' }
$process.ImageFileName='suyu-cmd.exe'
if ((Get-ZarvotCpuIdentity -Candidate $process -Metadata $metadata -SessionStart $session).PathSource -ne 'loaded_executable') {
    throw 'Independent full loaded-image path was not used'
}
$process.LoadedModules=@()
if (Get-ZarvotCpuIdentity -Candidate $process -Metadata $metadata -SessionStart $session) { throw 'Accepted basename alone' }
$process.ImageFileName=$metadata.expected_executable
$process.ProcessID=999
if (Get-ZarvotCpuIdentity -Candidate $process -Metadata $metadata -SessionStart $session) { throw 'Accepted another PID' }
$process.ProcessID=7872
$process.StartTime=$session.AddSeconds(2); $process.StartTimeRelativeMsec=2000
if (Get-ZarvotCpuIdentity -Candidate $process -Metadata $metadata -SessionStart $session) { throw 'Accepted reused PID start' }
$process.StartTime=$started.ToLocalTime(); $process.StartTimeRelativeMsec=0
$identity = Get-ZarvotCpuIdentity -Candidate $process -Metadata $metadata -SessionStart $started.AddMinutes(-1)
if ($identity.StartMatch -ne 'timestamp_within_10ms') { throw 'Equivalent UTC/local starts failed to match' }
$null = Initialize-ZarvotCpuTraceEvent -ProjectRoot $root
# Bind the ETL API without scanning optional EventPipe client overloads. The
# intentionally missing file exercises API loading without opening any trace.
$missing = Join-Path $root ('build/missing-cpu-fixture-' + [Guid]::NewGuid().ToString('N') + '.etl')
$rejected=$false
try { $null = [ZarvotCpuTraceExporter]::OpenTrace($missing, [Microsoft.Diagnostics.Tracing.Etlx.TraceLogOptions]::new()) }
catch {
    if ($_.Exception.Message -notmatch 'Could not find file') { throw }
    $rejected=$true
}
if (-not $rejected) { throw 'Missing ETL fixture unexpectedly opened' }
$baseAddress = [UInt64]0x100000000
if ([ZarvotCpuTraceExporter]::RelativeAddress($baseAddress+64, $baseAddress, 100) -ne 64 -or
    $null -ne [ZarvotCpuTraceExporter]::RelativeAddress($baseAddress-1, $baseAddress, 100) -or
    $null -ne [ZarvotCpuTraceExporter]::RelativeAddress($baseAddress+100, $baseAddress, 100) -or
    $null -ne [ZarvotCpuTraceExporter]::RelativeAddress($baseAddress, $baseAddress, 0)) {
    throw 'Native 64-bit address mapping or half-open image boundary failed'
}
'CPU analysis metadata, exact identity, UTC/pretrace limits and 64-bit image boundary checks passed'
