#requires -Version 7.0
# Analyze a CLOSED owned CPU trace. No tracing, game input or symbol downloads.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [ValidateRange(0, [double]::MaxValue)][double]$StartSeconds = 0,
    [ValidateRange(0, [double]::MaxValue)][double]$EndSeconds = [double]::MaxValue
)
$ErrorActionPreference = 'Stop'
function Assert-ZarvotCpuMetadata($Metadata, [string]$Directory) {
    if ($Metadata.state -ne 'complete' -or $Metadata.recording_started -ne $true -or
        $Metadata.error -or $Metadata.cleanup_error -or -not $Metadata.finished_utc -or
        $Metadata.trace_file -cne 'cpu.etl' -or $Metadata.trace_bytes -le 0 -or
        $Metadata.pid -le 0 -or -not $Metadata.process_started_utc -or -not $Metadata.run_root) {
        throw 'Expected a complete, successfully saved owned CPU profile; live/failed traces are rejected'
    }
    $runRoot = [IO.Path]::GetFullPath($Metadata.run_root)
    $expected = Join-Path $runRoot 'suyu-cmd.exe'
    if ($Metadata.expected_executable -ne $expected -or
        (Split-Path -Parent (Split-Path -Parent $Directory)) -ne $runRoot) {
        throw 'CPU profile run root or executable identity is inconsistent'
    }
    return $expected
}
function Get-ZarvotCpuIdentity($Candidate, $Metadata, [DateTime]$SessionStart) {
    if ($Candidate.ProcessID -ne $Metadata.pid) { return $null }
    $pathSource = 'process_image'
    if ($Candidate.ImageFileName -ne $Metadata.expected_executable) {
        # Some kernel process records contain only a basename. Require the loaded
        # EXE's full path as independent evidence; a basename alone is insufficient.
        if ($Candidate.ImageFileName -ne 'suyu-cmd.exe' -or
            @($Candidate.LoadedModules | Where-Object FilePath -eq $Metadata.expected_executable).Count -ne 1) {
            return $null
        }
        $pathSource = 'loaded_executable'
    }
    $expectedStart = ([DateTime]$Metadata.process_started_utc).ToUniversalTime()
    $observedStart = $Candidate.StartTime.ToUniversalTime()
    $startMatch = 'timestamp_within_10ms'
    if ($expectedStart -lt $SessionStart.ToUniversalTime() -and $Candidate.StartTimeRelativeMsec -eq 0 -and
        [Math]::Abs(($observedStart - $SessionStart.ToUniversalTime()).TotalMilliseconds) -le 10) {
        # TraceEvent documents pre-existing process start times as clamped to
        # trace start. Recorder PID/path/start checks supply the earlier identity.
        $startMatch = 'pretrace_start_clamped_to_trace_start'
    }
    elseif ([Math]::Abs(($observedStart - $expectedStart).TotalMilliseconds) -gt 10) { return $null }
    [pscustomobject]@{PathSource=$pathSource; StartMatch=$startMatch}
}
function Initialize-ZarvotCpuTraceEvent([string]$ProjectRoot) {
    $portable = Join-Path $ProjectRoot 'local/tools/PerfView/PerfView.exe'
    if (-not (Test-Path -LiteralPath $portable)) { throw 'Install the official local PerfView portable tool first' }
    $portableHash = (Get-FileHash -LiteralPath $portable -Algorithm SHA256).Hash
    $support = Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'PerfView') -Directory -Filter 'VER.*' |
        Where-Object {
            $copy = Join-Path $_.FullName 'PerfView.exe'
            (Test-Path -LiteralPath $copy) -and (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -eq $portableHash
        } | Select-Object -First 1
    if (-not $support) { throw 'Run the local PerfView UserCommandHelp once to unpack its matching libraries' }
    $library = Join-Path $support.FullName 'Microsoft.Diagnostics.Tracing.TraceEvent.dll'
    $serialization = Join-Path $support.FullName 'Microsoft.Diagnostics.FastSerialization.dll'
    Add-Type -Path $serialization
    Add-Type -Path $library
    if (-not ('ZarvotCpuTraceExporter' -as [type])) {
        $references = @((Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll').FullName) + @($library, $serialization)
        Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using Microsoft.Diagnostics.Tracing.Etlx;
using Microsoft.Diagnostics.Tracing.Parsers.Kernel;
public sealed class ZarvotCpuModuleCount {
    public string Module, Category;
    public long SampleRecords, ReportedCount;
    public double FirstSeconds, LastSeconds;
}
public static class ZarvotCpuTraceExporter {
    // Bind this specific ETL API in C#, avoiding PowerShell's reflection over
    // unrelated EventPipe overloads whose optional client package is not bundled.
    public static TraceLog OpenTrace(string path, TraceLogOptions options) { return TraceLog.OpenOrConvert(path, options); }
    public static ulong? RelativeAddress(ulong address, ulong imageBase, long size) {
        if (size <= 0 || address < imageBase || address - imageBase >= (ulong)size) return null;
        return address - imageBase;
    }
    private static string Csv(string value) { return "\"" + (value ?? "").Replace("\"", "\"\"") + "\""; }
    public static ZarvotCpuModuleCount[] Export(TraceProcess process, double start, double end, string path, string exe) {
        var counts = new Dictionary<string, ZarvotCpuModuleCount>(StringComparer.OrdinalIgnoreCase);
        string runRoot = Path.GetDirectoryName(exe);
        var compiled = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
            "recompiled_image.dll", "recompiled_rtld.dll", "recompiled_sdk.dll", "recompiled_subsdk0.dll"
        };
        using (var writer = new StreamWriter(path, false, new System.Text.UTF8Encoding(false), 262144)) {
            writer.WriteLine("timestamp_utc,trace_seconds,pid,tid,instruction_pointer,module,native_rva,category,reported_count");
            foreach (var item in process.EventsInProcess) {
                var sample = item as SampledProfileTraceData;
                if (sample == null) continue;
                double seconds = sample.TimeStampRelativeMSec / 1000.0;
                if (seconds < start || seconds >= end) continue;
                var module = process.LoadedModules.GetModuleContainingAddress(sample.InstructionPointer, sample.TimeStampRelativeMSec);
                string name = module == null ? "" : module.FilePath;
                ulong? rva = module == null || module.ModuleFile == null ? null : RelativeAddress(sample.InstructionPointer, module.ImageBase, module.ModuleFile.ImageSize);
                string category = "unknown";
                if (rva.HasValue && !String.IsNullOrEmpty(name)) {
                    category = String.Equals(name, exe, StringComparison.OrdinalIgnoreCase) ? "host_executable" : "native_module";
                    if (String.Equals(Path.GetDirectoryName(name), runRoot, StringComparison.OrdinalIgnoreCase) && compiled.Contains(Path.GetFileName(name))) category = "compiled_game_module";
                } else { name = ""; rva = null; }
                ZarvotCpuModuleCount count;
                if (!counts.TryGetValue(name, out count)) {
                    count = new ZarvotCpuModuleCount {Module=name, Category=category, FirstSeconds=seconds};
                    counts.Add(name, count);
                }
                count.SampleRecords++;
                count.ReportedCount += sample.Count;
                count.LastSeconds = seconds;
                writer.WriteLine(String.Join(",", sample.TimeStamp.ToUniversalTime().ToString("o"),
                    seconds.ToString("R", CultureInfo.InvariantCulture), sample.ProcessID, sample.ThreadID,
                    "0x" + sample.InstructionPointer.ToString("x16"), Csv(name), rva.HasValue ? "0x" + rva.Value.ToString("x") : "",
                    category, sample.Count));
            }
        }
        var result = new ZarvotCpuModuleCount[counts.Count]; counts.Values.CopyTo(result, 0); return result;
    }
}
'@
    }
    return $library
}
if ($EndSeconds -le $StartSeconds) { throw 'EndSeconds must be greater than StartSeconds; range is [start,end)' }
$ProfilePath = (Resolve-Path -LiteralPath $ProfilePath).Path
$directory = Split-Path -Parent $ProfilePath
$profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$expectedExe = Assert-ZarvotCpuMetadata -Metadata $profile -Directory $directory
$trace = Join-Path $directory 'cpu.etl'
if ((Get-Item -LiteralPath $trace).Length -ne $profile.trace_bytes) { throw 'Saved trace size differs from completed profile metadata' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$library = Initialize-ZarvotCpuTraceEvent -ProjectRoot $projectRoot
$id = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$analysis = Join-Path $directory "analysis/$id"
[IO.Directory]::CreateDirectory($analysis) | Out-Null
$summaryPath = Join-Path $analysis 'summary.json'
$summary = [ordered]@{
    analysis_version=1; state='analyzing'; profile_path=$ProfilePath; trace_bytes=$profile.trace_bytes
    expected_pid=$profile.pid; expected_executable=$expectedExe; process_started_utc=$profile.process_started_utc
    started_utc=[DateTime]::UtcNow.ToString('o'); finished_utc=$null
    range_start_seconds=$StartSeconds; range_end_seconds=if ($EndSeconds -eq [double]::MaxValue) {$null} else {$EndSeconds}
    trace_event_library_sha256=(Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
    trace_event_library_version=[Microsoft.Diagnostics.Tracing.Etlx.TraceLog].Assembly.GetName().Version.ToString()
    trace_start_utc=$null; trace_end_utc=$null; trace_duration_seconds=$null
    sample_interval_ms=$null; events_lost=$null; identity_path_source=$null; identity_start_match=$null
    sample_records=0; reported_count=0; unknown_sample_records=0; compiled_module_sample_records=0
    error=$null
    limits=@('Statistical leaf CPU samples, not exact call durations or frame timings.',
        'Host executable samples include multiple subsystems; no helper symbols or causal attribution are claimed.',
        'Compiled DLL samples include generated code and inlined helpers; native RVAs are not guest PCs.',
        'Pre-existing process start timestamps are clamped to trace start; earlier identity comes from recorder validation.',
        'Events lost and unknown module addresses remain explicit. Selected time range alone does not establish combat.')
}
function Save-CpuAnalysis { [IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false)) }
Save-CpuAnalysis
$log = $null
try {
    $options = [Microsoft.Diagnostics.Tracing.Etlx.TraceLogOptions]::new()
    $options.ConversionLogName = Join-Path $analysis 'conversion.log'
    # TraceEvent caches a derived cpu.etlx beside the closed ETL and reuses it
    # for further route windows. Its timestamp/version checks govern reuse.
    $log = [ZarvotCpuTraceExporter]::OpenTrace($trace, $options)
    $summary.trace_start_utc = $log.SessionStartTime.ToUniversalTime().ToString('o')
    $summary.trace_end_utc = $log.SessionEndTime.ToUniversalTime().ToString('o')
    $summary.trace_duration_seconds = $log.SessionDuration.TotalSeconds
    $summary.sample_interval_ms = $log.SampleProfileInterval.TotalMilliseconds
    $summary.events_lost = $log.EventsLost
    $matching = @($log.Processes | Where-Object ProcessID -eq $profile.pid | ForEach-Object {
        $identity = Get-ZarvotCpuIdentity -Candidate $_ -Metadata $profile -SessionStart $log.SessionStartTime
        if ($identity) { [pscustomobject]@{Process=$_; Identity=$identity} }
    })
    if ($matching.Count -ne 1) { throw 'Trace does not contain exactly one matching PID, executable path and start-time identity' }
    $target = $matching[0].Process
    $summary.identity_path_source = $matching[0].Identity.PathSource
    $summary.identity_start_match = $matching[0].Identity.StartMatch
    @($log.Processes | Where-Object ProcessID -eq $profile.pid | Select-Object ProcessID,ProcessIndex,ImageFileName,CommandLine,StartTime,EndTime,StartTimeRelativeMsec,EndTimeRelativeMsec) |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $analysis 'process-identities.json') -Encoding utf8
    @($target.LoadedModules | ForEach-Object {
        [pscustomobject]@{module=$_.FilePath; image_base=('0x{0:x16}' -f $_.ImageBase); image_size=$_.ModuleFile.ImageSize
            loaded_seconds=$_.LoadTimeRelativeMSec/1000; unloaded_seconds=$_.UnloadTimeRelativeMSec/1000
            pdb_name=$_.ModuleFile.PdbName; pdb_signature=$_.ModuleFile.PdbSignature; pdb_age=$_.ModuleFile.PdbAge}
    }) | Export-Csv -LiteralPath (Join-Path $analysis 'image-maps.csv') -NoTypeInformation -Encoding utf8
    @($target.Threads | Select-Object ThreadID,ThreadIndex,StartTimeRelativeMsec,EndTimeRelativeMsec,ThreadInfo) |
        Export-Csv -LiteralPath (Join-Path $analysis 'thread-maps.csv') -NoTypeInformation -Encoding utf8
    Save-CpuAnalysis
    $counts = [ZarvotCpuTraceExporter]::Export($target, $StartSeconds, $EndSeconds, (Join-Path $analysis 'samples.csv'), $expectedExe)
    $summary.sample_records = [long]($counts | Measure-Object SampleRecords -Sum).Sum
    $summary.reported_count = [long]($counts | Measure-Object ReportedCount -Sum).Sum
    $summary.unknown_sample_records = [long]($counts | Where-Object Category -eq 'unknown' | Measure-Object SampleRecords -Sum).Sum
    $summary.compiled_module_sample_records = [long]($counts | Where-Object Category -eq 'compiled_game_module' | Measure-Object SampleRecords -Sum).Sum
    $counts | Sort-Object SampleRecords -Descending | Select-Object Module,Category,SampleRecords,ReportedCount,FirstSeconds,LastSeconds,
        @{Name='ShareOfSelectedSamples'; Expression={if ($summary.sample_records -gt 0) {$_.SampleRecords / $summary.sample_records} else {$null}}} |
        Export-Csv -LiteralPath (Join-Path $analysis 'module-samples.csv') -NoTypeInformation -Encoding utf8
    if ((Get-Item -LiteralPath $trace).Length -ne $profile.trace_bytes) { throw 'Raw trace size changed during analysis' }
    $summary.state = 'complete'
}
catch { $summary.state='error'; $summary.error=$_.Exception.Message }
finally {
    if ($log) { $log.Dispose() }
    $summary.finished_utc=[DateTime]::UtcNow.ToString('o')
    Save-CpuAnalysis
}
[pscustomobject]@{Summary=$summaryPath; State=$summary.state; SampleRecords=$summary.sample_records; Error=$summary.error}
