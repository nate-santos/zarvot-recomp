# Run the real launcher with tiny synthetic files and mocked processes. No game is started.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixtureBase = Join-Path $root ('build\launcher tests\' + [Guid]::NewGuid().ToString('N'))
$global:ZarvotLaunchTestProcesses = @()
$global:ZarvotLaunchTestRecorder = $null
$global:ZarvotLaunchTestPollExit = $false
$script:checks = 0
function Get-Process {
    [CmdletBinding()]
    param([string[]]$Name, [int]$Id)
    if ($PSBoundParameters.ContainsKey('Id')) {
        $global:ZarvotLaunchTestProcesses | Where-Object Id -eq $Id
    } else { $global:ZarvotLaunchTestProcesses }
}
function Start-Process {
    param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle,$RedirectStandardOutput,$RedirectStandardError,[switch]$PassThru)
    if (-not $global:ZarvotLaunchTestRecorder) { throw 'The staging tests must never start a process' }
    $mock = $global:ZarvotLaunchTestRecorder
    if ([IO.Path]::GetFileName($FilePath) -eq 'suyu-cmd.exe') {
        $mock.stall_probe_value = $env:SUYU_STALL_PROBE
        if ($mock.mode -eq 'game_start_failure') { throw 'Synthetic game start failure' }
        $mock.game_starts++
        $game = [pscustomobject]@{Id=234567;Path=$FilePath;StartTime=([DateTime]'2026-10-11T14:00:00Z')}
        $global:ZarvotLaunchTestProcesses = @($game)
        return $game
    }
    $mock.recorder_starts++
    $record = Get-Content -LiteralPath (Join-Path $WorkingDirectory 'launch.json') -Raw | ConvertFrom-Json
    if ($record.state -ne 'started' -or $record.pid -ne 234567 -or -not $record.process_started_utc -or
        -not $record.coverage_recording_requested -or -not $record.coverage_observation_path -or
        $WindowStyle -ne 'Hidden' -or -not $RedirectStandardOutput -or -not $RedirectStandardError -or
        $FilePath -ne [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) {
        throw 'Recorder was not started hidden after saving the game identity in the same shell context'
    }
    foreach ($quoted in @('-RunRoot "' + $WorkingDirectory + '"',
                           '-ObservationPath "' + $record.coverage_observation_path + '"')) {
        if (-not $ArgumentList.Contains($quoted)) { throw 'Recorder paths with spaces were not quoted' }
    }
    if ($ArgumentList -notmatch '-File "[^"]+measure-zarvot-coverage\.ps1"' -or $ArgumentList -notmatch ' -UntilExit$') {
        throw 'Recorder must use a quoted helper file and lifetime recording'
    }
    if ($mock.mode -eq 'native_child') { return Microsoft.PowerShell.Management\Start-Process @PSBoundParameters }
    if ($mock.mode -eq 'start_failure') { throw 'Synthetic recorder start failure' }
    $child = [pscustomobject]@{Id=234568;StartTime=([DateTime]'2026-10-11T14:00:01Z');HasExited=($mock.mode -eq 'immediate_exit');ExitCode=9}
    $child | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }
    if ($mock.mode -ne 'immediate_exit') {
        $observation = [ordered]@{
            pid=$record.pid;process_started_utc=$record.process_started_utc;recorder_pid=$child.Id
            run_root=$WorkingDirectory;until_exit=$true;end_reason='recording';error=$null
        }
        switch ($mock.mode) {
            'wrong_pid' { $observation.pid++ }
            'wrong_start' { $observation.process_started_utc='2026-10-11T13:59:00Z' }
            'wrong_recorder' { $observation.recorder_pid++ }
            'wrong_root' { $observation.run_root += '-other' }
            'recorder_error' { $observation.end_reason='error'; $observation.error='synthetic attach error' }
        }
        Write-Json $record.coverage_observation_path $observation
    }
    $child
}
function Stop-Process { throw 'Launcher tests must never stop a process' }
function Start-Sleep {
    param([int]$Seconds,[int]$Milliseconds)
    if ($global:ZarvotLaunchTestPollExit) { $global:ZarvotLaunchTestProcesses = @(); return }
    Microsoft.PowerShell.Utility\Start-Sleep @PSBoundParameters
}
function Write-Json($Path, $Value) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
}
function Hash($Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function New-Fixture {
    $base = Join-Path $fixtureBase ([Guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.Directory]::CreateDirectory((Join-Path $base 'scripts')) | Out-Null
    foreach ($name in @('start-zarvot-recomp.ps1','zarvot-profile.ps1','measure-zarvot-coverage.ps1','zarvot-telemetry.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root "scripts\$name") -Destination (Join-Path $base 'scripts')
    }
    $rom = Join-Path $base 'zarvot.fixture'
    [IO.File]::WriteAllText($rom, 'synthetic test; no game data')
    $modules = @()
    $index = 0
    foreach ($name in @('rtld','sdk','subsdk0','main')) {
        ++$index
        $modules += [ordered]@{
            name=$name; build_id=('{0:x64}' -f $index)
            text_vaddr=0; text_size=(4096*$index); rodata_vaddr=(4096*$index)
            rodata_size=512; data_vaddr=(4096*$index+512); data_size=128
        }
    }
    $manifest = [ordered]@{
        version=2; image_abi=6; image_features=7; source_exefs_sha256=('a'*64)
        total_modules=4; total_blocks_analyzed=1; modules=$modules
    }
    $baselineManifest = Join-Path $base 'generated\zarvot\out\Zarvot - Hybrid AOT + JIT\aot_cache\aot_manifest.json'
    Write-Json $baselineManifest $manifest
    $candidateManifest = Join-Path $base 'generated\zarvot-fp32-outline\out\candidate\aot_cache\aot_manifest.json'
    $manifest.total_blocks_analyzed = 2 # changed generated build, same guest game
    Write-Json $candidateManifest $manifest
    foreach ($target in @('zarvot','zarvot-fp32-outline')) {
        $built = @()
        foreach ($name in @('rtld','sdk','subsdk0','main')) {
            $imageName = if ($name -eq 'main') { 'recompiled_image.dll' } else { "recompiled_$name.dll" }
            $image = Join-Path $base "build\recomp\$target\$name\$imageName"
            [IO.Directory]::CreateDirectory((Split-Path -Parent $image)) | Out-Null
            [IO.File]::WriteAllText($image, "synthetic $target $name")
            $built += [ordered]@{name=$name; state='complete'; bytes=(Get-Item $image).Length; sha256=(Hash $image)}
        }
        $selectedManifest = if ($target -eq 'zarvot') { $baselineManifest } else { $candidateManifest }
        Write-Json (Join-Path $base "build\recomp\$target\build-status.json") ([ordered]@{
            target=$target; state='complete'; image_abi=6; image_features=7
            export_manifest_sha256=(Hash $selectedManifest); modules=$built
        })
    }
    $previous = Join-Path $base 'build\zarvot-runs\baseline-run'
    $fixtureHost = Join-Path $base 'build\suyu\bin'
    foreach ($hostDir in @($previous,$fixtureHost)) {
        [IO.Directory]::CreateDirectory((Join-Path $hostDir 'user\keys')) | Out-Null
        [IO.File]::WriteAllText((Join-Path $hostDir 'suyu-cmd.exe'), "synthetic host $hostDir")
        [IO.File]::WriteAllText((Join-Path $hostDir 'host-dependency.dll'), 'synthetic dependency')
        [IO.File]::WriteAllText((Join-Path $hostDir 'user\keys\prod.keys'), 'synthetic key fixture')
    }
    foreach ($dir in @('config','nand','cache')) {
        [IO.Directory]::CreateDirectory((Join-Path $previous "user\$dir")) | Out-Null
    }
    $save = Join-Path $previous 'user\nand\save.fixture'
    [IO.File]::WriteAllText($save, 'synthetic saved progress')
    [IO.File]::WriteAllText((Join-Path $previous 'user\cache\cache.fixture'), 'synthetic cache')
    $config = "[Core]`nuse_speed_limit=true`nspeed_limit=100`n[Controls]`ntas_enable=false`n[Data%20Storage]`nnand_directory=" +
        ($previous.Replace('\','/') + "/user/nand`nsave_directory=" + $previous.Replace('\','/') + '/user/nand')
    [IO.File]::WriteAllText((Join-Path $previous 'user\config\sdl-config.ini'), $config)
    Copy-Item -LiteralPath $baselineManifest -Destination (Join-Path $previous 'aot_manifest.json')
    $baselineBuild = Get-Content (Join-Path $base 'build\recomp\zarvot\build-status.json') -Raw | ConvertFrom-Json
    Write-Json (Join-Path $previous 'launch.json') ([ordered]@{
        state='started'; run_root=$previous; pid=123456; process_started_utc='2026-10-01T01:00:00Z'
        host_sha256=(Hash (Join-Path $previous 'suyu-cmd.exe')); image_abi=6; image_features=7
        export_manifest_sha256=(Hash $baselineManifest); modules=$baselineBuild.modules
    })
    $global:ZarvotLaunchTestProcesses = @()
    $global:ZarvotLaunchTestRecorder = $null
    $global:ZarvotLaunchTestPollExit = $false
    [pscustomobject]@{Root=$base; Rom=$rom; Previous=$previous; Host=$fixtureHost; Save=$save
        CandidateManifest=$candidateManifest; BaselineManifest=$baselineManifest}
}
function Invoke-Fixture($Fixture, [hashtable]$Options) {
    $parameters = @{Rom=$Fixture.Rom; StageOnly=$true}
    foreach ($key in $Options.Keys) { $parameters[$key] = $Options[$key] }
    & (Join-Path $Fixture.Root 'scripts\start-zarvot-recomp.ps1') @parameters
}
function Candidate-Options($Fixture) {
    @{Target='zarvot-fp32-outline'; Package='out\candidate'; ProfileFromRun=$Fixture.Previous; AllowSameGameProfileReuse=$true}
}
function Save-CandidateManifest($Fixture, $Manifest) {
    Write-Json $Fixture.CandidateManifest $Manifest
    $path = Join-Path $Fixture.Root 'build\recomp\zarvot-fp32-outline\build-status.json'
    $build = Get-Content $path -Raw | ConvertFrom-Json
    $build.export_manifest_sha256 = Hash $Fixture.CandidateManifest
    Write-Json $path $build
}
function Reject($Name, [scriptblock]$Action, $Message) {
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Message) { throw "$Name rejected unexpectedly: $($_.Exception.Message)" }
        $rejected = $true
    }
    if (-not $rejected) { throw "Accepted invalid case: $Name" }
    ++$script:checks
}
try {
    $fixture = New-Fixture
    $before = Hash $fixture.Save
    $oldConfig = [IO.File]::ReadAllText((Join-Path $fixture.Previous 'user\config\sdl-config.ini'))
    $same = Invoke-Fixture $fixture @{HostRoot=$fixture.Previous; ProfileFromRun=$fixture.Previous}
    $record = Get-Content (Join-Path $same.RunRoot 'launch.json') -Raw | ConvertFrom-Json
    if ($same.State -ne 'staged' -or $record.profile_reuse_mode -ne 'same-build' -or
        $record.host_sha256 -ne (Hash (Join-Path $fixture.Previous 'suyu-cmd.exe'))) {
        throw 'An explicit baseline host/profile was not staged with its strict identities'
    }
    ++$script:checks

    $candidate = Invoke-Fixture $fixture (Candidate-Options $fixture)
    $record = Get-Content (Join-Path $candidate.RunRoot 'launch.json') -Raw | ConvertFrom-Json
    $clonedSave = Join-Path $candidate.RunRoot 'user\nand\save.fixture'
    $newConfig = [IO.File]::ReadAllText((Join-Path $candidate.RunRoot 'user\config\sdl-config.ini'))
    if ($record.target -ne 'zarvot-fp32-outline' -or $record.package -ne 'out\candidate' -or
        $record.profile_reuse_mode -ne 'same-game-cross-build' -or
        $record.export_manifest_sha256 -ne (Hash $fixture.CandidateManifest) -or
        $record.profile_source_manifest_sha256 -ne (Hash $fixture.BaselineManifest) -or
        $record.host_sha256 -ne (Hash (Join-Path $fixture.Host 'suyu-cmd.exe')) -or
        (Hash $clonedSave) -ne $before -or $newConfig.Contains($fixture.Previous.Replace('\','/')) -or
        -not $newConfig.Contains($candidate.RunRoot.Replace('\','/')) -or
        -not $newConfig.Contains('speed_limit=100') -or -not $newConfig.Contains('tas_enable=false')) {
        throw 'Candidate selection or isolated save/config copying failed'
    }
    [IO.File]::AppendAllText($clonedSave, ' changed only in clone')
    if ((Hash $fixture.Save) -ne $before -or
        [IO.File]::ReadAllText((Join-Path $fixture.Previous 'user\config\sdl-config.ini')) -ne $oldConfig) {
        throw 'Staging or changing the clone modified the source saved profile'
    }
    foreach ($module in $record.modules) {
        $name = if ($module.name -eq 'main') { 'recompiled_image.dll' } else { "recompiled_$($module.name).dll" }
        if ((Hash (Join-Path $candidate.RunRoot $name)) -ne $module.sha256) { throw 'Staged mixed compiled images' }
    }
    ++$script:checks

    $options = Candidate-Options $fixture
    $options.Remove('AllowSameGameProfileReuse')
    Reject 'default cross-build reuse' { Invoke-Fixture $fixture $options } 'runtime/export identity'
    Reject 'default changed host' { Invoke-Fixture $fixture @{ProfileFromRun=$fixture.Previous} } 'runtime/export identity'
    $fixture = New-Fixture
    $manifest = Get-Content $fixture.BaselineManifest -Raw | ConvertFrom-Json
    Save-CandidateManifest $fixture $manifest
    Reject 'default changed compiled DLLs' {
        Invoke-Fixture $fixture @{Target='zarvot-fp32-outline'; Package='out\candidate'; HostRoot=$fixture.Previous; ProfileFromRun=$fixture.Previous}
    } 'different compiled module set'

    foreach ($field in @('source_exefs_sha256','build_id','text_vaddr','text_size','rodata_vaddr','rodata_size','data_vaddr','data_size')) {
        $fixture = New-Fixture
        $manifest = Get-Content $fixture.CandidateManifest -Raw | ConvertFrom-Json
        if ($field -eq 'source_exefs_sha256') { $manifest.source_exefs_sha256 = 'b'*64 }
        elseif ($field -eq 'build_id') { $manifest.modules[0].build_id = 'b'*64 }
        else { $manifest.modules[0].$field++ }
        Save-CandidateManifest $fixture $manifest
        Reject "different guest $field" { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Cross-build profile reuse'
    }
    foreach ($field in @('source_exefs_sha256','text_size')) {
        $fixture = New-Fixture
        $manifest = Get-Content $fixture.CandidateManifest -Raw | ConvertFrom-Json
        if ($field -eq 'source_exefs_sha256') { $manifest.PSObject.Properties.Remove($field) }
        else { $manifest.modules[0].PSObject.Properties.Remove($field) }
        Save-CandidateManifest $fixture $manifest
        Reject "missing guest $field" { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Cross-build profile reuse'
    }
    $fixture = New-Fixture
    [IO.File]::AppendAllText((Join-Path $fixture.Previous 'aot_manifest.json'), ' ')
    Reject 'tampered source manifest' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'manifest does not match'
    $fixture = New-Fixture
    $path = Join-Path $fixture.Previous 'launch.json'
    $launch = Get-Content $path -Raw | ConvertFrom-Json
    $launch.image_features = 0
    Write-Json $path $launch
    Reject 'source feature mismatch' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'feature identity'
    $fixture = New-Fixture
    $global:ZarvotLaunchTestProcesses = @([pscustomobject]@{
        Id=123456; Path=(Join-Path $fixture.Previous 'suyu-cmd.exe'); StartTime=([DateTime]'2026-10-01T01:00:00Z')
    })
    Reject 'active source PID' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Close the source test session'
    $global:ZarvotLaunchTestProcesses[0].Id = 123457
    Reject 'manually restarted source profile' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Close the source test session'
    $global:ZarvotLaunchTestProcesses = @([pscustomobject]@{
        Id=123456; Path=(Join-Path $fixture.Host 'unrelated.exe'); StartTime=([DateTime]'2026-10-02T01:00:00Z')
    })
    Invoke-Fixture $fixture (Candidate-Options $fixture) | Out-Null
    ++$script:checks # a reused PID with a different lifetime cannot make the old run live
    $fixture = New-Fixture
    $path = Join-Path $fixture.Previous 'launch.json'
    $launch = Get-Content $path -Raw | ConvertFrom-Json
    $launch.PSObject.Properties.Remove('process_started_utc')
    Write-Json $path $launch
    Reject 'missing source process identity' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'recorded process identity'
    $fixture = New-Fixture
    Reject 'package traversal' { Invoke-Fixture $fixture @{Package='..\..\other'} } 'Package resolved outside'
    Reject 'target traversal' { Invoke-Fixture $fixture @{Target='..\other'} } 'Target'
    Reject 'foreign host root' { Invoke-Fixture $fixture @{HostRoot=$fixtureBase} } 'HostRoot must stay'
    Reject 'unscoped reuse flag' { Invoke-Fixture $fixture @{AllowSameGameProfileReuse=$true} } 'explicit ProfileFromRun'
    [IO.File]::WriteAllText((Join-Path $fixture.Previous 'user\config\sdl-config.ini'), 'nand_directory=C:/outside-profile')
    Reject 'foreign profile storage' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'outside its isolated test profile'
    $fixture = New-Fixture
    [IO.File]::AppendAllText((Join-Path $fixture.Root 'build\recomp\zarvot-fp32-outline\main\recompiled_image.dll'), ' tampered')
    Reject 'selected DLL identity' { Invoke-Fixture $fixture (Candidate-Options $fixture) } 'Compiled image identity'
    $stagingChecks = $script:checks
    $fixture = New-Fixture
    Reject 'coverage staging conflict' { Invoke-Fixture $fixture @{RecordCoverage=$true} } 'cannot be combined with StageOnly'
    if (Test-Path -LiteralPath (Join-Path $fixture.Root 'build\zarvot-runs') -PathType Container) {
        # The fixture's baseline directory predates this invocation; no new run
        # may have been staged before the conflict was rejected.
        if (@(Get-ChildItem -LiteralPath (Join-Path $fixture.Root 'build\zarvot-runs') -Directory).Count -ne 1) {
            throw 'StageOnly conflict staged an extra run'
        }
    }
    $previousProbe = $env:SUYU_STALL_PROBE
    try {
        foreach ($probeCase in @(
            @{ambient='1';requested=$false;child='0'},
            @{ambient='0';requested=$true;child='1'},
            @{ambient=$null;requested=$false;child='0'},
            @{ambient=$null;requested=$true;child='1'}
        )) {
            $fixture = New-Fixture
            $env:SUYU_STALL_PROBE = $probeCase.ambient
            $global:ZarvotLaunchTestRecorder = @{mode='attached';game_starts=0;recorder_starts=0}
            $result = Invoke-Fixture $fixture @{StageOnly=$false;StallProbe=$probeCase.requested}
            $record = Get-Content -LiteralPath (Join-Path $result.RunRoot 'launch.json') -Raw | ConvertFrom-Json
            if ($global:ZarvotLaunchTestRecorder.stall_probe_value -ne $probeCase.child -or
                $record.stall_probe_requested -ne $probeCase.requested -or
                $result.StallProbeRequested -ne $probeCase.requested -or
                $env:SUYU_STALL_PROBE -cne $probeCase.ambient) {
                throw 'Stall probe opt-in, ambient isolation, metadata or restoration failed'
            }
            ++$script:checks
        }
        $fixture = New-Fixture
        $env:SUYU_STALL_PROBE = 'restore-after-failure'
        $global:ZarvotLaunchTestRecorder = @{mode='game_start_failure';game_starts=0;recorder_starts=0}
        Reject 'probe game-start failure' { Invoke-Fixture $fixture @{StageOnly=$false;StallProbe=$true} } 'Synthetic game start failure'
        if ($env:SUYU_STALL_PROBE -cne 'restore-after-failure' -or
            $global:ZarvotLaunchTestRecorder.stall_probe_value -ne '1') {
            throw 'Stall probe environment was not restored after launch failure'
        }
        ++$script:checks
    } finally { $env:SUYU_STALL_PROBE = $previousProbe }
    foreach ($mode in @('attached','start_failure','immediate_exit','wrong_pid','wrong_start','wrong_recorder','wrong_root','recorder_error')) {
        $fixture = New-Fixture
        $global:ZarvotLaunchTestRecorder = @{mode=$mode;game_starts=0;recorder_starts=0}
        $result = Invoke-Fixture $fixture @{StageOnly=$false;RecordCoverage=$true}
        $record = Get-Content -LiteralPath (Join-Path $result.RunRoot 'launch.json') -Raw | ConvertFrom-Json
        if ($result.State -ne 'started' -or $record.state -ne 'started' -or $result.Pid -ne 234567 -or
            $global:ZarvotLaunchTestRecorder.game_starts -ne 1 -or $global:ZarvotLaunchTestRecorder.recorder_starts -ne 1 -or
            $record.coverage_recorder_state -ne $result.CoverageRecorderState -or
            $record.coverage_recorder_pid -ne $result.CoverageRecorderPid -or
            $record.coverage_recorder_error -ne $result.CoverageRecorderError -or
            $record.coverage_observation_path -ne $result.CoverageObservation -or
            @($global:ZarvotLaunchTestProcesses).Count -ne 1) {
            throw "Recorder $mode lost the running game, retried, or returned inconsistent evidence"
        }
        if ($mode -eq 'attached') {
            if ($result.CoverageRecorderState -ne 'attached' -or $result.CoverageRecorderError -or
                $result.CoverageRecorderPid -ne 234568 -or -not $record.coverage_recorder_started_utc) {
                throw 'Successful recorder attachment was not recorded'
            }
        } else {
            if ($result.CoverageRecorderState -ne 'startup_failed' -or -not $result.CoverageRecorderError -or
                ($mode -eq 'start_failure' -and $null -ne $result.CoverageRecorderPid) -or
                ($mode -ne 'start_failure' -and $result.CoverageRecorderPid -ne 234568)) {
                throw "Recorder $mode was not reported honestly"
            }
        }
        ++$script:checks
    }
    # Exercise actual native argument binding with a hidden PowerShell child.
    # Only its tiny synthetic helper runs; the game process stays mocked.
    $fixture = New-Fixture
    @'
param([string]$RunRoot,[string]$ObservationPath,[switch]$UntilExit)
$ErrorActionPreference = 'Stop'
$launch = Get-Content -LiteralPath (Join-Path $RunRoot 'launch.json') -Raw | ConvertFrom-Json
[IO.Directory]::CreateDirectory((Split-Path -Parent $ObservationPath)) | Out-Null
$report = @{pid=$launch.pid;process_started_utc=$launch.process_started_utc;recorder_pid=$PID;run_root=$RunRoot;until_exit=[bool]$UntilExit;end_reason='recording';error=$null}
[IO.File]::WriteAllText($ObservationPath,($report | ConvertTo-Json))
Start-Sleep -Milliseconds 1500
'@ | Set-Content -LiteralPath (Join-Path $fixture.Root 'scripts/measure-zarvot-coverage.ps1') -Encoding utf8
    $global:ZarvotLaunchTestRecorder = @{mode='native_child';game_starts=0;recorder_starts=0}
    $result = Invoke-Fixture $fixture @{StageOnly=$false;RecordCoverage=$true}
    if ($result.CoverageRecorderState -ne 'attached' -or $result.CoverageRecorderError -or
        $global:ZarvotLaunchTestRecorder.recorder_starts -ne 1) { throw "Native quoted recorder startup failed: $($result.CoverageRecorderError)" }
    try {
        $child = [Diagnostics.Process]::GetProcessById($result.CoverageRecorderPid)
        if (-not $child.WaitForExit(5000)) { throw 'Synthetic recorder child did not exit within its test lifetime' }
    } catch [ArgumentException] { } # It may already have completed normally.
    ++$script:checks

    # Run the real recorder with a synthetic process identity and one UI poll.
    $fixture = New-Fixture
    $game = [pscustomobject]@{Id=123456;Path=(Join-Path $fixture.Previous 'suyu-cmd.exe');StartTime=([DateTime]'2026-10-01T01:00:00Z');MainWindowTitle='Fixture | JIT transitions: 0'}
    $game | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }
    $helper = Join-Path $fixture.Root 'scripts/measure-zarvot-coverage.ps1'
    $observationPath = [IO.Path]::GetFullPath((Join-Path $fixture.Previous 'observations/explicit output/observation.json'))
    $global:ZarvotLaunchTestProcesses = @($game)
    $global:ZarvotLaunchTestPollExit = $true
    $measured = & $helper -RunRoot $fixture.Previous -ObservationPath $observationPath -UntilExit
    $observation = Get-Content -LiteralPath $observationPath -Raw | ConvertFrom-Json
    if ($measured.Evidence -ne $observationPath -or $measured.EndReason -ne 'process_exited' -or
        $observation.pid -ne 123456 -or $observation.recorder_pid -ne $PID -or
        $observation.run_root -ne $fixture.Previous -or $observation.sample_count -ne 1 -or
        ([DateTime]$observation.process_started_utc).ToUniversalTime().ToString('o') -ne $game.StartTime.ToUniversalTime().ToString('o')) {
        throw 'Real recorder did not attach to the explicit observation path and synthetic identity'
    }
    ++$script:checks
    $global:ZarvotLaunchTestProcesses = @($game)
    $legacy = & $helper -RunRoot $fixture.Previous -UntilExit
    if ($legacy.EndReason -ne 'process_exited' -or -not (Test-Path -LiteralPath $legacy.Evidence) -or
        $legacy.Evidence -eq $observationPath) { throw 'Legacy recorder invocation changed behavior' }
    ++$script:checks
    $global:ZarvotLaunchTestProcesses = @($game)
    $originalHash = Hash $observationPath
    Reject 'existing observation' { & $helper -RunRoot $fixture.Previous -ObservationPath $observationPath -UntilExit } 'already exists'
    if ((Hash $observationPath) -ne $originalHash) { throw 'Existing observation was modified' }
    Reject 'foreign observation path' { & $helper -RunRoot $fixture.Previous -ObservationPath (Join-Path $fixture.Root 'observation.json') -UntilExit } 'beneath this run'
    $game.Path = Join-Path $fixture.Previous 'other.exe'
    Reject 'recorder foreign executable' { & $helper -RunRoot $fixture.Previous -UntilExit } 'different executable'
    $game.Path = Join-Path $fixture.Previous 'suyu-cmd.exe'
    $game.StartTime = $game.StartTime.AddSeconds(1)
    Reject 'recorder reused PID' { & $helper -RunRoot $fixture.Previous -UntilExit } 'PID was reused'
    "Launcher staging/isolation checks passed: $stagingChecks; coverage startup checks passed: $($script:checks-$stagingChecks)"
} finally {
    Remove-Variable -Scope Global -Name ZarvotLaunchTestProcesses -ErrorAction SilentlyContinue
    Remove-Variable -Scope Global -Name ZarvotLaunchTestRecorder -ErrorAction SilentlyContinue
    Remove-Variable -Scope Global -Name ZarvotLaunchTestPollExit -ErrorAction SilentlyContinue
}
